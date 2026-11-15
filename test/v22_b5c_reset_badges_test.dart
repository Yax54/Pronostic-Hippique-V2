// ═══════════════════════════════════════════════════════════════════════════
//  V22 — B5c étape 3 : la réinitialisation complète vide-t-elle la RAM de
//                      IaBadgesService ?
//
//  ⚠️  FICHIER DE TEST uniquement. AUCUNE modification de lib/ autre que le
//      correctif B5c étape 3 lui-même.
//
//  Défaut d'origine (B5c étape 3) :
//    `reinitialiserComplet()` efface bien 'ia_badges_v1' du disque (la clé est
//    dans `_keysConfigIA`, backup_service.dart:213 → `_toutesLesCles`), MAIS
//    `_debloques` restait peuplé en RAM. Or `_sauvegarder()` (l.201) écrit la
//    map ENTIÈRE. Le prochain `debloquer()` — déclenché par « Analyser la
//    journée » (ia_performance_screen.dart:1686 → :779) — réécrivait donc
//    TOUS les anciens badges, avec leurs dates d'origine.
//
//  Spécificité vs étapes 1 et 2 :
//    Ce service n'a AUCUN flag `_charge`. Le correctif se réduit à une purge
//    de `_debloques`, suivie de `notifyListeners()` (option B, validée après
//    vérification qu'aucun effet secondaire n'existe : aucun
//    watch/read/Consumer/Provider.of<IaBadgesService> dans lib/, et l'unique
//    écouteur direct ne fait qu'un `setState` gardé par `mounted`).
//
//  ⚠️ Risques documentés, VOLONTAIREMENT NON corrigés à cette étape :
//    R-4  une écriture en vol dans `_sauvegarder()` (suspendue l.202) résume
//         `_debloques` APRÈS l'await : clé recréée VIDE, jamais les anciennes
//         dates. La fenêtre est de toute façon inatteignable.
//    R-6  `_sauvegarder()` n'a aucun try/catch.
//    R-7  `init()` ne fait pas de `clear()` avant de charger — latent.
//
//  Périmètre STRICT : aucun badge du catalogue, aucun seuil de verifierTout(),
//  aucune migration, aucun bouton, aucun autre service B5c.
//
//  ⚠️ Ces tests prouvent des observations ciblées, pas le bon
//     fonctionnement global de l'application.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/ia_badges_service.dart';

/// Les 3 badges préinstallés par les tests. Dates volontairement
/// distinctives : une résurrection écrirait 2024-01-01, un re-déblocage
/// légitime écrirait DateTime.now().
const Map<String, String> kBadgesAnciens = <String, String>{
  'analyse_10': '2024-01-01T10:00:00.000',
  'premier_pari': '2024-01-01T11:00:00.000',
  'serie_3': '2024-01-01T12:00:00.000',
};

void main() {
  final svc = IaBadgesService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Isolation entre tests : le singleton survit d'un test à l'autre.
    svc.viderMemoirePourResetComplet();
  });

  tearDown(() async {
    svc.viderMemoirePourResetComplet();
  });

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<String?> brutBadges() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('ia_badges_v1');
  }

  Future<bool> clePresente() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('ia_badges_v1');
  }

  Future<Map<String, dynamic>> mapDisque() async {
    final raw = await brutBadges();
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    return json.decode(raw) as Map<String, dynamic>;
  }

  /// Installe 3 badges anciens en RAM ET sur le disque, en passant par le
  /// chemin de production `init()` (qui lit SharedPreferences).
  Future<void> installerBadgesAnciens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ia_badges_v1', json.encode(kBadgesAnciens));
    await IaBadgesService.init();
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  V22-1 — Le reset complet efface ia_badges_v1 du disque
  //          (comportement déjà correct — garde-fou de non-régression)
  // ═══════════════════════════════════════════════════════════════════════
  test('V22-1 — reinitialiserComplet() efface ia_badges_v1 du disque',
      () async {
    await installerBadgesAnciens();

    // Contrôle de départ.
    expect(await clePresente(), isTrue);
    expect(svc.nbDebloques, 3);
    expect((await mapDisque()).length, 3);

    await BackupService.instance.reinitialiserComplet();

    expect(await clePresente(), isFalse,
        reason: 'ia_badges_v1 doit être effacée par un reset « complet »');
    expect(await brutBadges(), isNull);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V22-2 — Après reset, la RAM ne contient plus aucun badge débloqué
  //
  //  Cœur du correctif. Sans lui : 3 badges subsistent.
  // ═══════════════════════════════════════════════════════════════════════
  test('V22-2 — reinitialiserComplet() vide la RAM des badges', () async {
    await installerBadgesAnciens();
    expect(svc.nbDebloques, 3);

    await BackupService.instance.reinitialiserComplet();

    expect(svc.nbDebloques, 0,
        reason: '_debloques doit être vidé (sans correctif : 3)');
    expect(svc.badgesDebloques, isEmpty,
        reason: 'aucun badge ne doit rester débloqué (sans correctif : 3)');
    expect(svc.badgesVerrouilles.length, IaBadgesCatalogue.tous.length,
        reason: 'tous les badges doivent être de nouveau verrouillés');

    // Aucun des anciens ids ne doit apparaître comme débloqué.
    for (final id in kBadgesAnciens.keys) {
      final badge = svc.tousLesBadges.firstWhere((b) => b.id == id);
      expect(badge.estDebloque, isFalse,
          reason: '$id ne doit plus être débloqué en RAM');
    }
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V22-3 — Après reset, le premier debloquer() n'écrit QUE le nouveau
  //
  //  Scénario exact du défaut, sur le seul déclencheur de production.
  // ═══════════════════════════════════════════════════════════════════════
  test('V22-3 — reset puis debloquer : le disque ne contient que le '
      'nouveau badge', () async {
    await installerBadgesAnciens();
    await BackupService.instance.reinitialiserComplet();
    expect(await clePresente(), isFalse);

    final ok = await svc.debloquer('premiere_analyse');
    expect(ok, isTrue, reason: 'le badge est légitimement déblocable après reset');

    final map = await mapDisque();
    expect(map.length, 1,
        reason: 'le disque ne doit contenir QUE le nouveau badge '
            '(sans correctif : 4 entrées — les 3 anciennes reviennent)');
    expect(map.containsKey('premiere_analyse'), isTrue);

    for (final id in kBadgesAnciens.keys) {
      expect(map.containsKey(id), isFalse,
          reason: 'l\'ancien badge $id ne doit pas être réécrit sur le disque');
    }
    expect(await brutBadges(), isNot(contains('2024-01-01')),
        reason: 'aucune date de 2024 ne doit réapparaître');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V22-4 — LE TEST LE PLUS TRANCHANT : résurrection vs re-déblocage
  //
  //  Les 3 badges anciens portent la date 2024-01-01. Après reset, on
  //  re-débloque les MÊMES ids. Si les anciennes données ressuscitaient,
  //  la date resterait 2024-01-01. Si le re-déblocage est légitime, la date
  //  doit être NEUVE (>= date de référence prise avant le test).
  // ═══════════════════════════════════════════════════════════════════════
  test('V22-4 — reset puis re-déblocage des mêmes ids : dates NEUVES, '
      'jamais 2024-01-01', () async {
    final reference = DateTime.now().subtract(const Duration(seconds: 1));

    await installerBadgesAnciens();
    // Contrôle : les dates en RAM sont bien celles de 2024.
    final avantReset = svc.tousLesBadges
        .where((b) => b.estDebloque)
        .toList();
    expect(avantReset.length, 3);
    for (final b in avantReset) {
      expect(b.debloqueLe!.year, 2024,
          reason: 'état de départ : dates de 2024 en RAM');
    }

    await BackupService.instance.reinitialiserComplet();

    // Re-déblocage des MÊMES ids que les anciens.
    for (final id in kBadgesAnciens.keys) {
      final ok = await svc.debloquer(id);
      expect(ok, isTrue, reason: '$id doit être re-déblocable après reset');
    }

    // ── Vérification en RAM ──────────────────────────────────────────────
    final apres = svc.tousLesBadges.where((b) => b.estDebloque).toList();
    expect(apres.length, 3);
    for (final b in apres) {
      expect(b.debloqueLe!.year, isNot(2024),
          reason: 'RÉSURRECTION DÉTECTÉE : ${b.id} a retrouvé sa date 2024');
      expect(b.debloqueLe!.isBefore(reference), isFalse,
          reason: '${b.id} doit porter une date NEUVE, pas une date recyclée');
    }

    // ── Vérification sur le disque ───────────────────────────────────────
    final map = await mapDisque();
    expect(map.length, 3,
        reason: 'exactement 3 badges : les re-débloqués, rien de plus');
    expect(await brutBadges(), isNot(contains('2024-01-01')),
        reason: 'aucune date 2024 ne doit subsister sur le disque');
    for (final id in kBadgesAnciens.keys) {
      final date = DateTime.parse(map[id] as String);
      expect(date.isBefore(reference), isFalse,
          reason: 'la date de $id sur le disque doit être neuve');
    }
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V22-5 — Redémarrage simulé : init() ne ressuscite rien et n'écrit rien
  //
  //  `init()` ne fait qu'AJOUTER (l.128-131) et n'a aucune branche else.
  //  Ce test prouve qu'il ne peut pas servir de résurrection.
  // ═══════════════════════════════════════════════════════════════════════
  test('V22-5 — après reset, init() ne ressuscite rien et n\'écrit rien',
      () async {
    await installerBadgesAnciens();
    await BackupService.instance.reinitialiserComplet();

    // Redémarrage simulé : le service est réinitialisé puis init() est rejoué.
    await IaBadgesService.init();

    expect(svc.nbDebloques, 0,
        reason: 'sans correctif : init() retrouve la clé et recharge les 3');
    expect(svc.badgesDebloques, isEmpty);
    expect(await clePresente(), isFalse,
        reason: 'init() ne doit jamais écrire : la clé doit rester absente');
    expect(await brutBadges(), isNull);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V22-6 — Les réinitialisations PARTIELLES préservent les badges
  //
  //  ia_badges_v1 est dans `_keysConfigIA`, pas dans `_keysIA` ni
  //  `_keysParis`. Seul le reset COMPLET doit y toucher.
  // ═══════════════════════════════════════════════════════════════════════
  test('V22-6 — reinitialiserIA() et reinitialiserParis() préservent les '
      'badges', () async {
    await installerBadgesAnciens();
    final disqueAvant = await brutBadges();
    expect(disqueAvant, isNotNull);

    await BackupService.instance.reinitialiserIA();
    expect(await brutBadges(), disqueAvant,
        reason: 'reinitialiserIA() ne doit PAS toucher à ia_badges_v1');
    expect(svc.nbDebloques, 3,
        reason: 'la RAM des badges survit à reinitialiserIA()');

    await BackupService.instance.reinitialiserParis();
    expect(await brutBadges(), disqueAvant,
        reason: 'reinitialiserParis() ne doit PAS toucher à ia_badges_v1');
    expect(svc.nbDebloques, 3,
        reason: 'la RAM des badges survit à reinitialiserParis()');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V22-7 — La garde de debloquer() ne sur-bloque pas après un reset
  //
  //  `debloquer()` retourne false si le badge est déjà dans `_debloques`
  //  (l.138). Après un vidage, il doit retourner true.
  // ═══════════════════════════════════════════════════════════════════════
  test('V22-7 — après reset, debloquer() retourne true pour un badge '
      'précédemment débloqué', () async {
    await installerBadgesAnciens();
    // Avant le reset : déjà débloqué → false.
    expect(await svc.debloquer('premier_pari'), isFalse,
        reason: 'état de départ : déjà débloqué, la garde l.138 répond false');

    await BackupService.instance.reinitialiserComplet();

    // Après le reset : plus rien en RAM → doit retourner true.
    expect(await svc.debloquer('premier_pari'), isTrue,
        reason: 'sans correctif : _debloques garde premier_pari → false, '
            'le badge ne serait jamais ré-accordé');
    expect(svc.nbDebloques, 1);
    expect((await mapDisque()).keys.toList(), ['premier_pari']);
  });
}
