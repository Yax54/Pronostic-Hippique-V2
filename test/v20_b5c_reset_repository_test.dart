// ═══════════════════════════════════════════════════════════════════════════
//  V20 — B5c : la réinitialisation complète vide-t-elle la RAM de
//              PronosticResultatsRepository ?
//
//  ⚠️  FICHIER DE TEST uniquement. AUCUNE modification de lib/ autre que le
//      correctif B5c lui-même.
//
//  Défaut d'origine (B5c) :
//    `reinitialiserComplet()` (backup_service.dart) efface bien
//    'pronostic_resultats_repository_v2' du disque, MAIS
//    PronosticResultatsRepository garde `_items` peuplé en RAM et `_charge`
//    à `true`. Or `charger()` sort immédiatement quand `_charge` est vrai
//    (`if (_charge) return`, l.52). Le prochain `ajouterOuRemplacer()`
//    réécrivait donc TOUTES les anciennes entrées et annulait le reset.
//
//  Correctif testé :
//    1. `PronosticResultatsRepository.viderMemoirePourResetComplet()`
//       → `_items.clear()` + `_charge = false`, SANS écrire sur le disque.
//    2. Appel de cette méthode depuis `BackupService.reinitialiserComplet()`,
//       après les vidages B5 (ELO) et B5b (cote).
//
//  ⚠️ Risques documentés, VOLONTAIREMENT NON corrigés à cette étape :
//    R-3  le `_items.clear()` de `charger()` (l.58) est conditionnel : il
//         n'est exécuté que si la clé existe et n'est pas vide.
//    R-4  une écriture déjà en vol dans `_sauvegarder()` (suspendue sur
//         `getInstance()` ou `setString()`) pourrait recréer la clé après
//         le vidage. Aucun chemin de production ne l'atteint aujourd'hui.
//
//  Périmètre STRICT : aucun gradient, aucun poids, aucun seuil, aucun TOP3,
//  aucune analyseJourneeComplete(), aucune archive E3/E4, aucun bouton UI.
//
//  ⚠️ Ces tests prouvent des observations ciblées, pas le bon
//     fonctionnement global de l'application.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/pronostic_resultat_utilisateur.dart';
import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/pronostic_resultats_repository.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Fabrique d'items — clés de course identifiables (aucune donnée inventée
//  côté production : ce sont des données de test, pas des résultats réels).
// ───────────────────────────────────────────────────────────────────────────

PronosticResultatUtilisateur _res(int n) {
  return PronosticResultatUtilisateur.depuisPronosticClassique(
    courseKey: 'R${n}C${n}_15032026',
    dateCourse: DateTime.utc(2026, 3, 15),
    typePari: 'Quinté+',
    predictionIA: const <String>['1', '2', '3'],
    arriveePMUComplete: const <String>['1', '2', '3'],
    gagnant: true,
    ordreExact: false,
    nbTrouves: 3,
    nbRequis: 5,
    source: 'programme',
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Isolation entre tests : on réutilise la méthode de production pour
    // repartir d'une RAM vide (le singleton survit d'un test à l'autre).
    PronosticResultatsRepository.instance.viderMemoirePourResetComplet();
  });

  tearDown(() async {
    PronosticResultatsRepository.instance.viderMemoirePourResetComplet();
  });

  /// Nombre d'entrées réellement présentes SUR LE DISQUE (0 si clé absente).
  Future<int> nbSurDisque() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(PronosticResultatsRepository.storageKey);
    if (raw == null || raw.isEmpty) return 0;
    return (json.decode(raw) as List).length;
  }

  Future<bool> clePresente() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(PronosticResultatsRepository.storageKey);
  }

  Future<String?> brutDisque() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(PronosticResultatsRepository.storageKey);
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  V20-1 — Après un reset complet, le premier ajout ne doit PAS réécrire
  //          les anciennes entrées.
  //
  //  Scénario exact du défaut :
  //    3 items en RAM et sur le disque, `_charge = true`
  //    → reinitialiserComplet()  (disque effacé, RAM intacte AVANT correctif)
  //    → ajouterOuRemplacer(1 neuf)
  //  Sans correctif : charger() sort tout de suite, _items = 3 + 1 = 4 → 4
  //  écrits sur le disque. Avec correctif : 1 seul.
  // ═══════════════════════════════════════════════════════════════════════
  test(
      'V20-1 — reset complet puis ajout : le disque ne contient que le '
      'nouvel item', () async {
    // ── État de départ ───────────────────────────────────────────────────
    for (var i = 1; i <= 3; i++) {
      await PronosticResultatsRepository.instance.ajouterOuRemplacer(_res(i));
    }
    expect(PronosticResultatsRepository.instance.tous.length, 3,
        reason: 'état de départ : 3 résultats en RAM');
    expect(await nbSurDisque(), 3,
        reason: 'état de départ : 3 résultats sur le disque');
    expect(await clePresente(), isTrue);

    // ── Reset complet ────────────────────────────────────────────────────
    await BackupService.instance.reinitialiserComplet();

    // Le disque est bien effacé (comportement déjà correct avant B5c).
    expect(await clePresente(), isFalse,
        reason: 'B5c : la clé doit être effacée du disque par le reset');

    // ── Premier ajout APRÈS le reset ─────────────────────────────────────
    await PronosticResultatsRepository.instance.ajouterOuRemplacer(_res(99));

    // ── Vérifications ────────────────────────────────────────────────────
    expect(PronosticResultatsRepository.instance.tous.length, 1,
        reason: 'la RAM ne doit contenir que le nouvel item '
            '(sans correctif : 4)');
    expect(await nbSurDisque(), 1,
        reason: 'le disque ne doit contenir que le nouvel item '
            '(sans correctif : 4 anciennes entrées réécrites)');

    final brut = await brutDisque();
    expect(brut, isNotNull);
    for (var i = 1; i <= 3; i++) {
      expect(brut, isNot(contains('R${i}C${i}_15032026')),
          reason: 'l\'ancien item $i ne doit pas être réécrit sur le disque');
    }
    expect(brut, contains('R99C99_15032026'),
        reason: 'le nouvel item, lui, doit bien être persisté');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V20-2 — Après un reset complet, un `charger()` ne ressuscite rien
  //          et n'écrit rien.
  //
  //  C'est le second effet du correctif : `_charge = false` force le
  //  rechargement, et comme la clé est absente, `charger()` laisse `_items`
  //  vide (le `clear()` conditionnel de l.58 n'est pas nécessaire ici
  //  puisque `viderMemoirePourResetComplet()` a déjà vidé la RAM).
  //  Sans correctif : `charger()` sort immédiatement (`_charge == true`)
  //  et `tous` renvoie encore les 3 anciennes entrées.
  // ═══════════════════════════════════════════════════════════════════════
  test(
      'V20-2 — après reset, charger() ne ressuscite rien et n\'écrit rien',
      () async {
    for (var i = 1; i <= 3; i++) {
      await PronosticResultatsRepository.instance.ajouterOuRemplacer(_res(i));
    }
    expect(PronosticResultatsRepository.instance.tous.length, 3);

    // `_charge` vaut true à ce stade (charger() a été appelé par les ajouts).
    await BackupService.instance.reinitialiserComplet();
    expect(await clePresente(), isFalse,
        reason: 'le reset ne doit laisser aucune clé sur le disque');

    // Prochain appel de charger() — c'est exactement ce que fait
    // ajouterOuRemplacer(), et ce que font les écrans de stats.
    await PronosticResultatsRepository.instance.charger();

    expect(PronosticResultatsRepository.instance.tous, isEmpty,
        reason: 'sans correctif : charger() sort tout de suite '
            '(_charge == true) et _items conserve ses 3 entrées');
    expect(PronosticResultatsRepository.instance.gagnants, isEmpty);
    expect(PronosticResultatsRepository.instance.utilisablesStats, isEmpty);

    expect(await clePresente(), isFalse,
        reason: 'charger() ne doit rien écrire : la clé doit rester absente');
    expect(await nbSurDisque(), 0);

    // Second charger() : idempotent, toujours rien.
    await PronosticResultatsRepository.instance.charger();
    expect(PronosticResultatsRepository.instance.tous, isEmpty);
    expect(await clePresente(), isFalse);
  });
}
