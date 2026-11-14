// ═══════════════════════════════════════════════════════════════════════════
//  V19 — B5b : le reset complet vide aussi les caches du suivi de cote
//
//  ⚠️  FICHIER DE TEST uniquement. AUCUNE modification de lib/.
//
//  Défaut d'origine (B5b) : `reinitialiserComplet()` effaçait la clé
//  `cote_tracker_mouvements_v1` du DISQUE, mais `CoteTrackerService`
//  conservait ses `_mouvements` en RAM. Preuve mesurée avant correctif :
//      disque APRES reset : null
//      cache RAM APRES reset : 1 mouvement (ANCIEN_CHEVAL, -52%, effondrement)
//  Ces données alimentaient encore les alertes « cotes qui chutent ».
//
//  Correctif testé (option A complète) :
//    A.1 `viderCachePourResetComplet()` — vide les 3 caches RAM
//    A.2 `reinitialiserComplet()` l'appelle après le vidage ELO
//    A.3 `chargerMouvementsPersistes()` vide le cache si la clé est absente
//  + garde de génération et attente des écritures différées en vol.
//
//  ⚠️ Ces tests prouvent des observations ciblées, pas le bon
//     fonctionnement global de l'application.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/cote_tracker_service.dart';

import 'v17_faux_store.dart'; // FauxStore + installerStore + store

// ───────────────────────────────────────────────────────────────────────────
//  Fabriques
// ───────────────────────────────────────────────────────────────────────────

/// Date au format JJMMYYYY, décalée de +1 jour.
///
/// ⚠️ INDISPENSABLE : le filtre de `chargerMouvementsPersistes()` compare
/// `DateTime(y, m, d)` — donc MINUIT — à `DateTime.now()`. Passé 6 h du
/// matin, la journée en cours est déjà jugée périmée et l'entrée est
/// écartée. Sans ce décalage, les tests « passeraient » pour la mauvaise
/// raison (entrée filtrée, et non cache vidé). Ce défaut de filtre est
/// HORS PÉRIMÈTRE B5b et n'est pas corrigé ici.
String dateDecalee() {
  final d = DateTime.now().add(const Duration(days: 1));
  return '${d.day.toString().padLeft(2, '0')}'
      '${d.month.toString().padLeft(2, '0')}${d.year}';
}

const String kChevalAncien = 'ANCIEN_CHEVAL';

/// Clé de course lisible par le filtre `_(\d{8})$`.
String cleCourse() => 'R1C1_${dateDecalee()}';

/// Bloc persisté contenant UN mouvement ancien bien identifiable.
String mouvementsPersistes() {
  final now = DateTime.now();
  return json.encode({
    cleCourse(): [
      {
        'numero': '1',
        'nom': kChevalAncien,
        'coteDebut': 5.0,
        'coteCourante': 2.4,
        'variationPct': -52.0,
        'premierSnap':
            now.subtract(const Duration(minutes: 12)).toIso8601String(),
        'dernierSnap': now.toIso8601String(),
        'nbSnapshots': 5,
      }
    ],
  });
}

/// Prefs de départ : la clé cote est peuplée AVANT le service.
Map<String, Object> prefsAvecCotes() => <String, Object>{
      'cote_tracker_mouvements_v1': mouvementsPersistes(),
      'cote_mouvements_live_v1': json.encode([
        {'courseKey': cleCourse(), 'nomCheval': kChevalAncien}
      ]),
    };

Future<bool> cleCotePresente() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('cote_tracker_mouvements_v1') != null;
}

Future<bool> cleLivePresente() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('cote_mouvements_live_v1') != null;
}

void main() {
  setUp(() {
    installerStore(data: prefsAvecCotes());
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  1 — Vidage des mouvements et des alertes après reset
  // ═══════════════════════════════════════════════════════════════════════
  test('B5b-1 — le reset vide les caches RAM (mouvements et alertes)', () async {
    // Cache peuplé, comme au démarrage de l'app.
    await CoteTrackerService.instance.chargerMouvementsPersistes();

    final avant = CoteTrackerService.instance.mouvementsPourCourse(cleCourse());
    expect(avant.length, 1,
        reason: 'état de départ : le cache doit contenir ANCIEN_CHEVAL');
    expect(avant.first.nom, kChevalAncien);
    expect(avant.first.categorie, 'effondrement');

    await BackupService.instance.reinitialiserComplet();

    final apres = CoteTrackerService.instance.mouvementsPourCourse(cleCourse());
    expect(apres, isEmpty,
        reason: 'B5b : le cache RAM doit être vidé par le reset complet');
    expect(
      CoteTrackerService.instance.mouvementPourPartant(cleCourse(), '1'),
      isNull,
      reason: 'aucun partant ne doit rester consultable',
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  2 — Cohérence RAM / disque
  // ═══════════════════════════════════════════════════════════════════════
  test('B5b-2 — cohérence RAM/disque : les deux sont vides après reset',
      () async {
    await CoteTrackerService.instance.chargerMouvementsPersistes();
    expect(await cleCotePresente(), isTrue, reason: 'disque peuplé au départ');
    expect(await cleLivePresente(), isTrue);

    await BackupService.instance.reinitialiserComplet();

    // Disque
    expect(await cleCotePresente(), isFalse,
        reason: 'B5 : la clé cote doit avoir disparu du disque');
    expect(await cleLivePresente(), isFalse,
        reason: 'B5 : la clé live doit avoir disparu du disque');

    // RAM
    expect(CoteTrackerService.instance.mouvementsPourCourse(cleCourse()),
        isEmpty,
        reason: 'B5b : le cache RAM doit être vide en même temps que le disque');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  3 — Rechargement avec clé absente
  // ═══════════════════════════════════════════════════════════════════════
  test('B5b-3 — chargerMouvementsPersistes() avec clé absente vide le cache',
      () async {
    await CoteTrackerService.instance.chargerMouvementsPersistes();
    expect(CoteTrackerService.instance.mouvementsPourCourse(cleCourse()).length,
        1);

    // La clé disparaît du disque, SANS passer par le service.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cote_tracker_mouvements_v1');
    await prefs.remove('cote_mouvements_live_v1');

    // Avant correctif : retour immédiat, le cache restait plein.
    await CoteTrackerService.instance.chargerMouvementsPersistes();

    expect(CoteTrackerService.instance.mouvementsPourCourse(cleCourse()),
        isEmpty,
        reason: 'A.3 : une clé absente doit vider le cache, pas le laisser '
            'dans son état précédent');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  4 — Fonctionnement normal SANS reset (non-régression du suivi)
  // ═══════════════════════════════════════════════════════════════════════
  test('B5b-4 — sans reset, le suivi fonctionne normalement', () async {
    // `CoteTrackerService` est un SINGLETON : sa génération persiste d'un
    // test à l'autre. On mesure donc une VARIATION, pas une valeur absolue.
    final generationAvant = CoteTrackerService.instance.generationCache;

    // Chargement
    await CoteTrackerService.instance.chargerMouvementsPersistes();
    expect(CoteTrackerService.instance.mouvementsPourCourse(cleCourse()).length,
        1,
        reason: 'le rechargement doit conserver les mouvements existants');

    // Rechargement répété : idempotent, pas de doublon.
    await CoteTrackerService.instance.chargerMouvementsPersistes();
    expect(CoteTrackerService.instance.mouvementsPourCourse(cleCourse()).length,
        1,
        reason: 'un second chargement ne doit pas dupliquer les entrées');

    // Les accesseurs restent fonctionnels.
    final m = CoteTrackerService.instance.mouvementPourPartant(cleCourse(), '1');
    expect(m, isNotNull);
    expect(m!.variationPct, -52.0);
    expect(m.categorie, 'effondrement');
    expect(CoteTrackerService.instance.scoreCritereR(cleCourse(), '1'),
        isNotNull);

    // Aucun vidage n'a eu lieu : la génération n'a pas bougé.
    expect(CoteTrackerService.instance.generationCache, generationAvant,
        reason: 'sans reset, la génération ne doit pas être incrémentée');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  5 — Non-régression B5 (les clés ELO du disque)
  // ═══════════════════════════════════════════════════════════════════════
  test('B5b-5 — non-régression B5 : les clés ELO restent effacées', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('elo_ratings_v2', '{"A|TROT":{"rating":1922.5}}');
    await prefs.setInt('elo_ratings_v2_ts', 1234567890);
    await prefs.setString('elo_ratings_v1', '{"A":{"rating":1500.0}}');

    await BackupService.instance.reinitialiserComplet();

    final apres = await SharedPreferences.getInstance();
    expect(apres.getString('elo_ratings_v2'), isNull);
    expect(apres.getInt('elo_ratings_v2_ts'), isNull);
    expect(apres.getString('elo_ratings_v1'), isNull);
    // Et le vidage cote n'a rien cassé au passage.
    expect(CoteTrackerService.instance.mouvementsPourCourse(cleCourse()),
        isEmpty);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  6 — Opération asynchrone commencée AVANT le reset, terminée APRÈS
  //
  //  Scénario réel : un `chargerMouvementsPersistes()` ou une écriture
  //  différée est en vol quand l'utilisateur déclenche le reset.
  // ═══════════════════════════════════════════════════════════════════════
  test('B5b-6a — un chargement en vol ne repeuple pas le cache après reset',
      () async {
    // Le chargement est lancé ; on ne l'attend PAS.
    final chargement = CoteTrackerService.instance.chargerMouvementsPersistes();

    // Le reset le précède (il incrémente la génération).
    await BackupService.instance.reinitialiserComplet();

    // Le chargement se termine maintenant, APRÈS le reset.
    await chargement;

    expect(CoteTrackerService.instance.mouvementsPourCourse(cleCourse()),
        isEmpty,
        reason: 'un chargement démarré avant le reset ne doit pas repeupler '
            'le cache : la garde de génération doit l\'abandonner');
    expect(CoteTrackerService.instance.generationCache, greaterThan(0),
        reason: 'le reset a bien incrémenté la génération');
  });

  test('B5b-6b — le reset attend les écritures différées en vol', () async {
    await CoteTrackerService.instance.chargerMouvementsPersistes();

    // Aucune écriture en vol au départ.
    expect(CoteTrackerService.instance.nbEcrituresEnCours, 0);

    await BackupService.instance.reinitialiserComplet();

    // Après le reset, aucune écriture ne doit rester en attente : sinon
    // elle pourrait recréer la clé. Le vidage les a attendues.
    expect(CoteTrackerService.instance.nbEcrituresEnCours, 0,
        reason: 'le reset doit attendre les écritures différées');

    // Et le disque est bien propre.
    expect(await cleCotePresente(), isFalse);
    expect(await cleLivePresente(), isFalse);
  });

  test('B5b-6c — deux resets successifs restent idempotents', () async {
    await CoteTrackerService.instance.chargerMouvementsPersistes();

    await BackupService.instance.reinitialiserComplet();
    final gen1 = CoteTrackerService.instance.generationCache;

    await BackupService.instance.reinitialiserComplet();
    final gen2 = CoteTrackerService.instance.generationCache;

    expect(gen2, greaterThan(gen1),
        reason: 'chaque reset incrémente la génération');
    expect(CoteTrackerService.instance.mouvementsPourCourse(cleCourse()),
        isEmpty);
    expect(await cleCotePresente(), isFalse,
        reason: 'aucune clé ne doit être recréée entre les deux resets');
  });
}
