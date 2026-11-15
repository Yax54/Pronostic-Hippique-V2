// ═══════════════════════════════════════════════════════════════════════════
//  V21 — B5c étape 2 : la réinitialisation complète vide-t-elle la RAM de
//                      QuasiGrosParisService ?
//
//  ⚠️  FICHIER DE TEST uniquement. AUCUNE modification de lib/ autre que le
//      correctif B5c étape 2 lui-même.
//
//  Défaut d'origine (B5c étape 2) :
//    `reinitialiserComplet()` efface bien les DEUX clés du disque
//    ('ia_quasi_gros_paris_v1' et 'ia_gros_paris_resultats_v1'), MAIS le
//    service garde `_signaux`, `_quasiGagnants` et `_grosParisGagnants`
//    peuplés en RAM, avec `_charge == true`. Or `charger()` sort
//    immédiatement quand `_charge` est vrai (`if (_charge) return`, l.190).
//    Le prochain `ajouterSignauxBatch()` — appelé à chaque ouverture de
//    BestBetScreen (best_bet_screen.dart:197) — réécrivait donc toutes les
//    anciennes entrées et annulait le reset.
//
//  Correctif testé :
//    1. `QuasiGrosParisService.viderMemoirePourResetComplet()`
//       → clear des 3 listes + `_charge = false`, SANS écrire sur le disque.
//    2. Appel de cette méthode depuis `BackupService.reinitialiserComplet()`,
//       après les vidages B5 (ELO), B5b (cote) et B5c-1 (repository).
//
//  ⚠️ Risques documentés, VOLONTAIREMENT NON corrigés à cette étape :
//    R-4  une écriture déjà en vol dans `_sauvegarder()` (suspendue sur
//         `getInstance()` l.247, `setString()` l.253 ou l.258) pourrait
//         recréer les clés. Aucun chemin de production ne l'atteint.
//    R-5  `_sauvegarder()` écrit les deux clés INCONDITIONNELLEMENT et
//         BestBetScreen recalcule à chaque ouverture : les clés peuvent
//         réapparaître VIDES. C'est une recréation de clés vides, pas une
//         résurrection de données. V21-6 documente ce comportement réel.
//
//  Périmètre STRICT : aucun gradient, aucun poids, aucun seuil, aucun TOP3,
//  aucune analyseJourneeComplete(), aucune archive E3/E4, aucune migration,
//  aucun bouton UI, aucun autre service B5c.
//
//  ⚠️ Ces tests prouvent des observations ciblées, pas le bon
//     fonctionnement global de l'application.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// quasi_gros_paris_models est ré-exporté par quasi_gros_paris_service :
// on importe uniquement le service pour éviter un import redondant.
import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/quasi_gros_paris_service.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Fabriques — données de TEST, aucun résultat réel n'est inventé.
//  Les dates sont « maintenant » pour survivre à la purge > 90 jours de
//  `ajouterSignauxBatch()` (l.1071-1072).
// ───────────────────────────────────────────────────────────────────────────

GrosPariSurveiller _signal(int n) {
  return GrosPariSurveiller(
    id: 'SIG-$n',
    courseKey: 'R${n}C${n}_TEST',
    dateCourse: DateTime.now(),
    nomCourse: 'Course test $n',
    hippodrome: 'TEST-HIPPODROME',
    heure: '13h0$n',
    discipline: 'TROT_ATTELE',
    type: TypeGrosPari.quinte,
    numeros: const <String>['1', '2', '3', '4', '5'],
    scoresParNumero: const <String, double>{'1': 91.0, '2': 88.0},
    scoreMoyenSelection: 87.5,
    ecartAvecSuivant: 4.25,
    fiabilite: 82.0,
    niveau: NiveauFiabiliteGrosPari.fort,
    createdAt: DateTime.now(),
  );
}

QuasiGagnant _quasi(int n) {
  return QuasiGagnant(
    id: 'Q-$n',
    courseKey: 'R${n}C${n}_TEST',
    dateCourse: DateTime.now(),
    nomCourse: 'Course test $n',
    hippodrome: 'TEST-HIPPODROME',
    heure: '13h0$n',
    discipline: 'TROT_ATTELE',
    type: TypeGrosPari.quinte,
    source: SourceQuasiGagnant.grosParisSurveiller,
    numerosIA: const <String>['1', '2', '3', '4', '5'],
    arriveeReelle: const <String>['1', '2', '9', '4', '5'],
    numerosTrouves: const <String>['1', '2', '4', '5'],
    numerosManquants: const <String>['3'],
    nbTrouves: 4,
    nbRequis: 5,
    fiabilite: 82.0,
    createdAt: DateTime.now(),
  );
}

GrosPariGagnant _gagnant(int n) {
  return GrosPariGagnant(
    id: 'G-$n',
    courseKey: 'R${n}C${n}_TEST',
    dateCourse: DateTime.now(),
    nomCourse: 'Course test $n',
    hippodrome: 'TEST-HIPPODROME',
    heure: '13h0$n',
    discipline: 'TROT_ATTELE',
    typePari: 'Quinté+',
    selectionIA: const <String>['1', '2', '3', '4', '5'],
    arriveePMUComplete: const <String>['1', '2', '3', '4', '5'],
    statut: ResultatPariType.gagnantDesordre,
    ordreExact: false,
    createdAt: DateTime.now(),
  );
}

void main() {
  final svc = QuasiGrosParisService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Isolation entre tests : le singleton survit d'un test à l'autre.
    svc.viderMemoirePourResetComplet();
  });

  tearDown(() async {
    svc.viderMemoirePourResetComplet();
  });

  // ── Helpers de lecture disque ────────────────────────────────────────────

  Future<String?> brutQuasi() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(QuasiGrosParisService.storageKey);
  }

  Future<String?> brutGagnants() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(QuasiGrosParisService.storageKeyGagnants);
  }

  Future<bool> cleQuasiPresente() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(QuasiGrosParisService.storageKey);
  }

  Future<bool> cleGagnantsPresente() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(QuasiGrosParisService.storageKeyGagnants);
  }

  /// Nombre d'éléments réellement SUR LE DISQUE (0 si clé absente).
  Future<int> nbSignauxDisque() async {
    final raw = await brutQuasi();
    if (raw == null || raw.isEmpty) return 0;
    return ((json.decode(raw) as Map<String, dynamic>)['signaux'] as List? ?? [])
        .length;
  }

  Future<int> nbQuasiDisque() async {
    final raw = await brutQuasi();
    if (raw == null || raw.isEmpty) return 0;
    return ((json.decode(raw) as Map<String, dynamic>)['quasiGagnants']
            as List? ??
        []).length;
  }

  Future<int> nbGagnantsDisque() async {
    final raw = await brutGagnants();
    if (raw == null || raw.isEmpty) return 0;
    return ((json.decode(raw) as Map<String, dynamic>)['grosParisGagnants']
            as List? ??
        []).length;
  }

  /// Installe 3 signaux + 3 quasi + 3 gagnants en RAM ET sur le disque.
  /// Passe par le chemin de restauration réel (importerDepuisBackup), qui
  /// pose `_charge = true` et appelle `_sauvegarder()`.
  Future<void> installerEtatComplet() async {
    await svc.importerDepuisBackup(<String, dynamic>{
      'signaux': [for (var i = 1; i <= 3; i++) _signal(i).toJson()],
      'quasiGagnants': [for (var i = 1; i <= 3; i++) _quasi(i).toJson()],
      'grosParisGagnants': [for (var i = 1; i <= 3; i++) _gagnant(i).toJson()],
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  V21-1 — Le reset complet efface les DEUX clés du disque
  //          (comportement déjà correct — garde-fou de non-régression)
  // ═══════════════════════════════════════════════════════════════════════
  test('V21-1 — reinitialiserComplet() efface les 2 clés Gros Paris du disque',
      () async {
    await installerEtatComplet();

    // Contrôle de départ : les 2 clés sont bien présentes avec 3 éléments.
    expect(await cleQuasiPresente(), isTrue);
    expect(await cleGagnantsPresente(), isTrue);
    expect(await nbSignauxDisque(), 3);
    expect(await nbQuasiDisque(), 3);
    expect(await nbGagnantsDisque(), 3);

    await BackupService.instance.reinitialiserComplet();

    expect(await cleQuasiPresente(), isFalse,
        reason: 'ia_quasi_gros_paris_v1 doit être effacée');
    expect(await cleGagnantsPresente(), isFalse,
        reason: 'ia_gros_paris_resultats_v1 doit être effacée');
    expect(await nbSignauxDisque(), 0);
    expect(await nbGagnantsDisque(), 0);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V21-2 — Après reset, les TROIS listes RAM sont vides
  //
  //  Cœur du correctif. Sans lui : 3/3/3 subsistent en mémoire.
  // ═══════════════════════════════════════════════════════════════════════
  test('V21-2 — reinitialiserComplet() vide les 3 caches RAM', () async {
    await installerEtatComplet();
    expect(svc.signaux.length, 3);
    expect(svc.quasiGagnants.length, 3);
    expect(svc.grosParisGagnants.length, 3);

    await BackupService.instance.reinitialiserComplet();

    expect(svc.signaux, isEmpty,
        reason: '_signaux doit être vidé en RAM (sans correctif : 3)');
    expect(svc.quasiGagnants, isEmpty,
        reason: '_quasiGagnants doit être vidé en RAM (sans correctif : 3)');
    expect(svc.grosParisGagnants, isEmpty,
        reason: '_grosParisGagnants doit être vidé en RAM (sans correctif : 3)');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V21-3 — Après reset, un charger() ne ressuscite rien et n'écrit rien
  //
  //  Prouve `_charge = false`. Sans le correctif : charger() sort en l.190
  //  et les trois listes conservent leurs 3 éléments.
  // ═══════════════════════════════════════════════════════════════════════
  test('V21-3 — après reset, charger() ne ressuscite rien et n\'écrit rien',
      () async {
    await installerEtatComplet();
    await BackupService.instance.reinitialiserComplet();

    await svc.charger();

    expect(svc.signaux, isEmpty,
        reason: 'sans correctif : charger() sort sur `_charge == true`');
    expect(svc.quasiGagnants, isEmpty);
    expect(svc.grosParisGagnants, isEmpty);

    expect(await cleQuasiPresente(), isFalse,
        reason: 'charger() ne doit rien écrire : la clé doit rester absente');
    expect(await cleGagnantsPresente(), isFalse);
    expect(await nbSignauxDisque(), 0);
    expect(await nbGagnantsDisque(), 0);

    // Second charger() : idempotent.
    await svc.charger();
    expect(svc.signaux, isEmpty);
    expect(svc.grosParisGagnants, isEmpty);
    expect(await cleQuasiPresente(), isFalse);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V21-4 — Après reset, le premier ajoutBatch ne réécrit PAS les anciens
  //
  //  Scénario exact du défaut, sur le SEUL écrivain vivant en production
  //  (best_bet_screen.dart:197).
  // ═══════════════════════════════════════════════════════════════════════
  test(
      'V21-4 — reset puis ajouterSignauxBatch : le disque ne contient que le '
      'nouveau signal', () async {
    await installerEtatComplet();
    await BackupService.instance.reinitialiserComplet();

    await svc.ajouterSignauxBatch(<GrosPariSurveiller>[_signal(99)]);

    expect(svc.signaux.length, 1,
        reason: 'la RAM ne doit contenir que le nouveau signal '
            '(sans correctif : 4)');
    expect(await nbSignauxDisque(), 1,
        reason: 'le disque ne doit contenir que le nouveau signal '
            '(sans correctif : 4 anciens réécrits)');
    expect(await nbGagnantsDisque(), 0,
        reason: 'les 3 anciens gagnants ne doivent pas réapparaître '
            '(sans correctif : 3)');

    final rawQuasi = await brutQuasi();
    final rawGagnants = await brutGagnants();
    for (var i = 1; i <= 3; i++) {
      expect(rawQuasi, isNot(contains('R${i}C${i}_TEST')),
          reason: 'l\'ancien signal $i ne doit pas être réécrit');
      expect(rawGagnants, isNot(contains('R${i}C${i}_TEST')),
          reason: 'l\'ancien gagnant $i ne doit pas être réécrit');
    }
    expect(rawQuasi, contains('R99C99_TEST'));

    expect(svc.grosParisGagnants, isEmpty);
    expect(svc.quasiGagnants, isEmpty);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V21-5 — LES DEUX CLÉS SONT INDÉPENDANTES
  //
  //  Exigence explicite : « après un reset complet, aucune ancienne donnée
  //  ne doit survivre en RAM, même si une seule clé est ensuite présente ».
  //
  //  Scénario :
  //    1. 3/3/3 en RAM et sur le disque
  //    2. reinitialiserComplet()  → tout doit être vidé
  //    3. on réinjecte UNIQUEMENT 'ia_quasi_gros_paris_v1' sur le disque
  //       (1 signal légitime, réécriture normale d'une seule clé —
  //        exactement ce que fait BestBetScreen)
  //    4. charger()
  //  Attendu : `_signaux` reprend le signal LÉGITIME (1), mais
  //            `_grosParisGagnants` et `_quasiGagnants` restent VIDES car
  //            leur garde (l.220 pour les gagnants) est indépendante.
  //
  //  Ce test est le seul à couvrir la seconde garde conditionnelle de
  //  `charger()` (l.220). Il échoue si `_grosParisGagnants.clear()` est
  //  retiré du correctif, même si les deux autres clear() sont présents.
  // ═══════════════════════════════════════════════════════════════════════
  test('V21-5 — reset puis UNE SEULE clé réinjectée : aucune ancienne donnée '
      'ne survit en RAM', () async {
    await installerEtatComplet();
    await BackupService.instance.reinitialiserComplet();

    // Contrôle : le reset a bien tout vidé.
    expect(svc.signaux, isEmpty);
    expect(svc.quasiGagnants, isEmpty);
    expect(svc.grosParisGagnants, isEmpty);

    // ── Étape 3 : UNE SEULE clé est réécrite (le CHEMIN LÉGITIME) ────────
    // On imite exactement ce que fait le service quand il sauvegarde :
    // la clé quasi contient 1 signal + 0 quasi ; la clé gagnants reste
    // ABSENTE (aucune écriture).
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      QuasiGrosParisService.storageKey,
      json.encode(<String, dynamic>{
        'signaux': [_signal(42).toJson()],
        'quasiGagnants': <dynamic>[],
      }),
    );
    // On s'assure que la clé gagnants n'existe pas.
    await prefs.remove(QuasiGrosParisService.storageKeyGagnants);

    expect(await cleQuasiPresente(), isTrue);
    expect(await cleGagnantsPresente(), isFalse,
        reason: 'scénario : une seule clé présente');

    // ── Étape 4 : rechargement ───────────────────────────────────────────
    await svc.charger();

    // Le signal légitime est bien repris…
    expect(svc.signaux.length, 1,
        reason: 'le signal réinjecté après le reset est légitime');
    expect(svc.signaux.first.courseKey, 'R42C42_TEST');

    // …MAIS aucune ancienne donnée ne réapparaît, malgré la garde l.196
    // satisfaite pour _signaux et _quasiGagnants.
    expect(svc.quasiGagnants, isEmpty,
        reason: 'garde l.196 satisfaite mais la liste est vide côté disque');
    expect(svc.grosParisGagnants, isEmpty,
        reason: 'PROPRIÉTÉ CLÉ : la garde l.220 est indépendante de l.196. '
            'Les 3 anciens gagnants ne doivent pas survivre en RAM. '
            'Échoue si _grosParisGagnants.clear() est retiré du correctif.');
    for (var i = 1; i <= 3; i++) {
      expect(svc.grosParisGagnants.any((g) => g.courseKey == 'R${i}C${i}_TEST'),
          isFalse,
          reason: 'l\'ancien gagnant $i ne doit pas survivre en RAM');
      expect(svc.signaux.any((s) => s.courseKey == 'R${i}C${i}_TEST'), isFalse,
          reason: 'l\'ancien signal $i ne doit pas survivre en RAM');
    }

    // charger() n'a rien écrit : la clé gagnants reste absente.
    expect(await cleGagnantsPresente(), isFalse,
        reason: 'charger() ne doit jamais écrire');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V21-6 — Chemin rétrocompat de restauration (backup_service.dart:1036)
  //
  //  ⚠️ Ce test DOCUMENTE un comportement réel, il ne prouve pas le
  //  correctif : `importerDepuisBackup` vide les trois listes par lui-même.
  //  Il établit que ce chemin réécrit volontairement les DEUX clés avec des
  //  listes vides (risque R-5 documenté) et qu'aucune ancienne donnée ne
  //  revient.
  // ═══════════════════════════════════════════════════════════════════════
  test('V21-6 — import rétrocompat après reset : clés réécrites VIDES, '
      'aucune ancienne donnée', () async {
    await installerEtatComplet();
    await BackupService.instance.reinitialiserComplet();

    // Map sans 'grosParisGagnants' — exactement l'appel de backup_service:1036
    await svc.importerDepuisBackup(<String, dynamic>{
      'signaux': <dynamic>[],
      'quasiGagnants': <dynamic>[],
    });

    expect(svc.signaux, isEmpty);
    expect(svc.quasiGagnants, isEmpty);
    expect(svc.grosParisGagnants, isEmpty);

    // R-5 : ce chemin réécrit les deux clés, avec du vide.
    expect(await cleQuasiPresente(), isTrue,
        reason: 'R-5 : _sauvegarder() écrit la clé inconditionnellement');
    expect(await cleGagnantsPresente(), isTrue,
        reason: 'R-5 : _sauvegarder() écrit la clé inconditionnellement');
    expect(await nbSignauxDisque(), 0);
    expect(await nbQuasiDisque(), 0);
    expect(await nbGagnantsDisque(), 0);

    final rawQuasi = await brutQuasi();
    final rawGagnants = await brutGagnants();
    for (var i = 1; i <= 3; i++) {
      expect(rawQuasi, isNot(contains('R${i}C${i}_TEST')));
      expect(rawGagnants, isNot(contains('R${i}C${i}_TEST')));
    }
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V21-7 — Les réinitialisations PARTIELLES préservent les Gros Paris
  //
  //  Non-régression : seul le reset COMPLET doit vider les trois caches.
  // ═══════════════════════════════════════════════════════════════════════
  test('V21-7 — reinitialiserIA() et reinitialiserParis() préservent les '
      'Gros Paris', () async {
    await installerEtatComplet();
    final quasiAvant = await brutQuasi();
    final gagnantsAvant = await brutGagnants();

    await BackupService.instance.reinitialiserIA();
    expect(await brutQuasi(), quasiAvant,
        reason: 'reinitialiserIA() ne doit PAS toucher à ia_quasi_gros_paris_v1');
    expect(await brutGagnants(), gagnantsAvant,
        reason:
            'reinitialiserIA() ne doit PAS toucher à ia_gros_paris_resultats_v1');
    expect(svc.signaux.length, 3, reason: 'la RAM survit à reinitialiserIA()');
    expect(svc.grosParisGagnants.length, 3);

    await BackupService.instance.reinitialiserParis();
    expect(await brutQuasi(), quasiAvant,
        reason:
            'reinitialiserParis() ne doit PAS toucher à ia_quasi_gros_paris_v1');
    expect(await brutGagnants(), gagnantsAvant);
    expect(svc.grosParisGagnants.length, 3,
        reason: 'la RAM survit à reinitialiserParis()');
  });
}
