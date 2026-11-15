// ═══════════════════════════════════════════════════════════════════════════
//  V23 — B5c étape 4 : la réinitialisation complète vide-t-elle la RAM de
//                      IaUserPrefsService ?
//
//  ⚠️  FICHIER DE TEST uniquement. AUCUNE modification de lib/ autre que le
//      correctif B5c étape 4 lui-même.
//
//  Défaut d'origine (B5c étape 4) :
//    `reinitialiserComplet()` efface bien 'ia_user_prefs_v1' du disque (clé
//    dans `_keysConfigIA`, backup_service.dart:213), MAIS `_prefs` gardait les
//    habitudes détectées en RAM. Trois widgets les lisaient encore :
//      • profile_profil_tab.dart:685        → section « Préférences détectées »
//      • profile_progression_tab.dart:230   → section « Mise adaptative »
//      • profile_progression_tab.dart:263   → miseSuggeree()
//
//  ⚠️ DIFFÉRENCE ESSENTIELLE avec les étapes 1, 2 et 3 :
//    Ce service ne peut PAS ressusciter de données sur le disque.
//    `_sauvegarder()` (l.149) a UN SEUL appelant, `analyserDepuisParis()`
//    (l.145), qui REMPLACE `_prefs` (l.137) par un recalcul complet SANS
//    jamais fusionner avec l'ancien état. Il n'y a donc rien à « ne pas
//    réécrire » : le prochain enregistrement part d'une base neuve.
//    Le correctif est donc d'une nature différente : il s'agit d'éviter
//    l'AFFICHAGE de préférences périmées, pas d'empêcher une réécriture.
//    Les tests le reflètent : V23-3 vérifie l'absence de fusion, pas
//    l'absence de résurrection.
//
//  ⚠️ Risque résiduel documenté (R-8), NON corrigé ici :
//    un `analyserDepuisParis()` exécuté avant que `AlertService` (source de
//    `preds`) n'ait été vidé pourrait recalculer depuis des données périmées.
//    Voir rapport étape 4 / étape 5.
//
//  Périmètre STRICT : aucune logique de calcul de préférences, aucun seuil de
//  `miseSuggeree()`, aucun message personnalisé, aucun bouton.
//
//  ⚠️ Ces tests prouvent des observations ciblées, pas le bon
//     fonctionnement global de l'application.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/ia_user_prefs_service.dart';

/// Préférences anciennes, valeurs distinctives pour détecter toute survie.
const Map<String, dynamic> kPrefsAnciennes = <String, dynamic>{
  'parType': {'Quinté+': 12, 'Simple Gagnant': 5},
  'hippodrome': {'VINCENNES-TEST': 8},
  'mises': [42.0, 42.0, 42.0],
  'discipline': {'Trot': 10},
  'heure': {'14': 6},
};

/// Faux TrackedCourse pour `analyserDepuisParis` (accès duck-typing).
class _FauxTracked {
  _FauxTracked(this.typePari, this.hippodrome, this.miseEngagee, this.heureDepart);
  final String typePari;
  final String hippodrome;
  final double miseEngagee;
  final DateTime heureDepart;
}

void main() {
  final svc = IaUserPrefsService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    svc.viderMemoirePourResetComplet();
  });

  tearDown(() async {
    svc.viderMemoirePourResetComplet();
  });

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<String?> brutPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('ia_user_prefs_v1');
  }

  Future<bool> clePresente() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('ia_user_prefs_v1');
  }

  /// Installe les préférences anciennes en RAM ET sur le disque, via le
  /// chemin de production `init()`.
  Future<void> installerPrefsAnciennes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ia_user_prefs_v1', json.encode(kPrefsAnciennes));
    await IaUserPrefsService.init();
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  V23-1 — Le reset complet efface ia_user_prefs_v1 du disque
  //          (déjà correct — garde-fou de non-régression)
  // ═══════════════════════════════════════════════════════════════════════
  test('V23-1 — reinitialiserComplet() efface ia_user_prefs_v1 du disque',
      () async {
    await installerPrefsAnciennes();
    expect(await clePresente(), isTrue);
    expect(svc.prefs.hippodromeFavori, 'VINCENNES-TEST');

    await BackupService.instance.reinitialiserComplet();

    expect(await clePresente(), isFalse,
        reason: 'ia_user_prefs_v1 doit être effacée');
    expect(await brutPrefs(), isNull);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V23-2 — Après reset, les préférences RAM sont revenues au défaut
  //
  //  Cœur du correctif. Sans lui : hippodrome favori, type favori et mise
  //  habituelle restent affichés par les 3 widgets consommateurs.
  // ═══════════════════════════════════════════════════════════════════════
  test('V23-2 — reinitialiserComplet() remet les préférences RAM par défaut',
      () async {
    await installerPrefsAnciennes();

    // Contrôle de départ : les anciennes valeurs sont bien là.
    expect(svc.prefs.typeFavori, 'Quinté+');
    expect(svc.prefs.hippodromeFavori, 'VINCENNES-TEST');
    expect(svc.prefs.disciplineFavorite, 'Trot');
    expect(svc.prefs.miseHabituelle, 42.0);
    expect(svc.resumePreferences, contains('VINCENNES-TEST'));

    await BackupService.instance.reinitialiserComplet();

    // ── Toutes les préférences sont revenues au défaut ───────────────────
    expect(svc.prefs.typeFavori, '',
        reason: 'sans correctif : Quinté+ (affiché dans le profil)');
    expect(svc.prefs.hippodromeFavori, '',
        reason: 'sans correctif : VINCENNES-TEST (affiché dans le profil)');
    expect(svc.prefs.disciplineFavorite, '');
    expect(svc.prefs.frequenceParType, isEmpty);
    expect(svc.prefs.frequenceHippodrome, isEmpty);
    expect(svc.prefs.frequenceDiscipline, isEmpty);
    expect(svc.prefs.frequenceHeure, isEmpty);
    expect(svc.prefs.misesUtilisees, isEmpty);

    // La mise par défaut est 5.0 (défaut du modèle, l.44 et l.49).
    expect(svc.prefs.miseHabituelle, 5.0,
        reason: 'sans correctif : 42.0 (mise ancienne encore proposée)');
    expect(svc.prefs.miseMoyenne, 5.0);

    // Le résumé ne doit plus mentionner l'ancien hippodrome.
    // NOTE : `resumePreferences` (l.190-196) affiche « 5 €/course » même sans
    // aucune préférence, car `miseHabituelle` retourne 5.0 quand la liste des
    // mises est vide (l.48-50). C'est un comportement PRÉEXISTANT du service,
    // indépendant du reset : `'Aucune préférence détectée'` est en pratique
    // inatteignable. Constat documenté, NON corrigé (hors périmètre B5c).
    expect(svc.resumePreferences, '5 €/course',
        reason: 'préexistant : mise par défaut affichée seule');
    expect(svc.resumePreferences, isNot(contains('VINCENNES-TEST')),
        reason: 'sans correctif : l\'ancien hippodrome resterait affiché');
    expect(svc.resumePreferences, isNot(contains('42')),
        reason: 'sans correctif : l\'ancienne mise de 42 € resterait affichée');
    expect(svc.resumePreferences, isNot(contains('Quinté+')));

    // L'ancien hippodrome ne doit plus être reconnu comme « favori ».
    // NOTE : `messagePersonnalise` (l.166-187) retourne « Mise habituelle :
    // 5 €. » même sans préférence, car `miseBase > 0` est vrai avec le défaut
    // 5.0 (l.181-184). Comportement PRÉEXISTANT, indépendant du reset.
    final msg = svc.messagePersonnalise('Prix test', 'VINCENNES-TEST', 'Quinté+');
    expect(msg, isNot(contains('hippodrome préféré')),
        reason: 'sans correctif : l\'ancien hippodrome serait reconnu comme '
            'favori et le message « C\'est ton hippodrome préféré » apparaîtrait');
    expect(msg, isNot(contains('VINCENNES-TEST')),
        reason: 'sans correctif : l\'ancien hippodrome serait cité');
    expect(msg, isNot(contains('ta stratégie habituelle')),
        reason: 'sans correctif : l\'ancien type favori Quinté+ serait suggéré');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V23-3 — Après reset, analyserDepuisParis() ne réécrit QUE le recalcul
  //
  //  ⚠️ Ce test ne prouve PAS une non-résurrection (elle est impossible par
  //  conception : le service remplace au lieu de fusionner). Il prouve que
  //  le premier recalcul après reset ne contient AUCUNE trace des anciennes
  //  préférences.
  // ═══════════════════════════════════════════════════════════════════════
  test('V23-3 — reset puis analyserDepuisParis : aucune trace des anciennes '
      'préférences', () async {
    await installerPrefsAnciennes();
    await BackupService.instance.reinitialiserComplet();
    expect(await clePresente(), isFalse);

    // Un seul pari : Tiercé sur un autre hippodrome, mise 7 €.
    await svc.analyserDepuisParis(<dynamic>[
      _FauxTracked('Tiercé', 'AUTRE-HIPPODROME', 7.0, DateTime(2026, 6, 1, 16)),
    ]);

    final map = json.decode((await brutPrefs())!) as Map<String, dynamic>;

    // Le recalcul est présent…
    expect((map['parType'] as Map).keys.toList(), ['Tiercé']);
    expect((map['hippodrome'] as Map).keys.toList(), ['AUTRE-HIPPODROME']);
    expect((map['mises'] as List).length, 1);

    // …et aucune ancienne valeur n'y figure.
    final brut = await brutPrefs();
    expect(brut, isNot(contains('VINCENNES-TEST')),
        reason: 'l\'ancien hippodrome ne doit pas apparaître');
    expect(brut, isNot(contains('Quinté+')));
    expect(brut, isNot(contains('Simple Gagnant')));
    expect(brut, isNot(contains('42')));
    expect(brut, isNot(contains('Trot')),
        reason: 'l\'ancienne discipline ne doit pas apparaître');

    expect(svc.prefs.hippodromeFavori, 'AUTRE-HIPPODROME');
    expect(svc.prefs.typeFavori, 'Tiercé');
    expect(svc.prefs.miseHabituelle, 7.0);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V23-4 — analyserDepuisParis() REMPLACE, il ne fusionne jamais
  //
  //  Preuve de la différence de nature avec les étapes 1-3 : même sans reset,
  //  un recalcul avec une liste vide ne conserve rien de l'ancien état.
  //  C'est ce qui rend une résurrection disque structurellement impossible.
  // ═══════════════════════════════════════════════════════════════════════
  test('V23-4 — analyserDepuisParis() remplace l\'état, il ne fusionne pas',
      () async {
    await installerPrefsAnciennes();
    expect(svc.prefs.hippodromeFavori, 'VINCENNES-TEST');

    // Recalcul avec une liste VIDE — sans aucun reset préalable.
    await svc.analyserDepuisParis(<dynamic>[]);

    expect(svc.prefs.hippodromeFavori, '',
        reason: 'le service REMPLACE _prefs (l.137) : il ne fusionne pas');
    expect(svc.prefs.typeFavori, '');
    expect(svc.prefs.misesUtilisees, isEmpty);

    final brut = await brutPrefs();
    expect(brut, isNot(contains('VINCENNES-TEST')));
    expect(brut, isNot(contains('42')));
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V23-5 — Redémarrage simulé : init() ne ressuscite rien et n'écrit rien
  // ═══════════════════════════════════════════════════════════════════════
  test('V23-5 — après reset, init() ne ressuscite rien et n\'écrit rien',
      () async {
    await installerPrefsAnciennes();
    await BackupService.instance.reinitialiserComplet();

    await IaUserPrefsService.init();

    expect(svc.prefs.frequenceParType, isEmpty,
        reason: 'sans correctif : init() retrouve la clé et recharge tout');
    expect(svc.prefs.hippodromeFavori, '');
    expect(svc.prefs.miseHabituelle, 5.0);
    expect(await clePresente(), isFalse,
        reason: 'init() ne doit jamais écrire : la clé doit rester absente');
    expect(await brutPrefs(), isNull);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V23-6 — Les réinitialisations PARTIELLES préservent les préférences
  //
  //  ia_user_prefs_v1 est dans `_keysConfigIA`, ni dans `_keysIA` ni
  //  `_keysParis`. Seul le reset COMPLET doit y toucher.
  // ═══════════════════════════════════════════════════════════════════════
  test('V23-6 — reinitialiserIA() et reinitialiserParis() préservent les '
      'préférences', () async {
    await installerPrefsAnciennes();
    final disqueAvant = await brutPrefs();
    expect(disqueAvant, isNotNull);

    await BackupService.instance.reinitialiserIA();
    expect(await brutPrefs(), disqueAvant,
        reason: 'reinitialiserIA() ne doit PAS toucher à ia_user_prefs_v1');
    expect(svc.prefs.hippodromeFavori, 'VINCENNES-TEST',
        reason: 'la RAM des préférences survit à reinitialiserIA()');

    await BackupService.instance.reinitialiserParis();
    expect(await brutPrefs(), disqueAvant,
        reason: 'reinitialiserParis() ne doit PAS toucher à ia_user_prefs_v1');
    expect(svc.prefs.hippodromeFavori, 'VINCENNES-TEST',
        reason: 'la RAM des préférences survit à reinitialiserParis()');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V23-7 — Les valeurs par défaut restent cohérentes et utilisables
  //
  //  Vérifie qu'après reset le service ne tombe ni sur 0 € ni sur un état
  //  incohérent : `miseSuggeree()` doit rester bornée [2, 200] et se baser
  //  sur la mise par défaut de 5 €.
  // ═══════════════════════════════════════════════════════════════════════
  test('V23-7 — après reset, miseSuggeree() repart de la mise par défaut',
      () async {
    await installerPrefsAnciennes();
    // Avant reset : base 42 € → score 90 ⇒ 84 €.
    expect(svc.miseSuggeree(90), 84.0);

    await BackupService.instance.reinitialiserComplet();

    // Après reset : base 5 € → score 90 ⇒ 10 €.
    expect(svc.prefs.miseHabituelle, 5.0);
    expect(svc.miseSuggeree(90), 10.0,
        reason: 'sans correctif : 84 €, calculée sur l\'ancienne mise de 42 €');
    expect(svc.miseSuggeree(80), 7.5);
    expect(svc.miseSuggeree(65), 5.0);
    expect(svc.miseSuggeree(50), 2.5);

    // Bornes inchangées.
    expect(svc.miseSuggeree(100), lessThanOrEqualTo(200.0));
    expect(svc.miseSuggeree(0), greaterThanOrEqualTo(2.0));
  });
}
