// ═══════════════════════════════════════════════════════════════════
//  ELO SERVICE — v9.92
//
//  ★ v9.92 : ELO par discipline — clé = "NOM_CHEVAL|DISCIPLINE"
//    Un cheval qui passe du Trot Attelé au Plat repart à 1500
//    sur la nouvelle discipline. Les ELO ne se polluent plus.
//    K-factor par discipline conservé (48 débutant, 32 confirmé).
//    Rétrocompatibilité : anciens ELO sans discipline → clé globale
//    conservée en lecture, mais les nouvelles mises à jour utilisent
//    la clé disciplinée.
// ═══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/zt_models.dart';

class EloService {
  static final EloService _instance = EloService._();
  static EloService get instance => _instance;
  EloService._();

  static const String _prefsKey   = 'elo_ratings_v2';   // ★ v9.92 : nouvelle clé (par discipline)
  static const String _prefsKeyTs = 'elo_ratings_v2_ts';
  // Ancienne clé — lue en migration uniquement
  static const String _prefsKeyOld = 'elo_ratings_v1';

  static const double _eloDefaut    = 1500.0;
  static const double _kFactor      = 32.0;
  static const double _kDebutant    = 48.0;

  // ★ v9.93 POINT 3 : K-factor adapté par discipline
  // Trot Attelé : très discriminant → K plus élevé (convergence rapide)
  // Obstacle : part d'aléatoire importante (chutes) → K réduit
  // Galop Plat : valeur standard
  static double _kFacteurPourDiscipline(String discipline, bool estDebutant) {
    return switch (discipline) {
      'TROT_ATTELE'      => estDebutant ? 52.0 : 36.0,
      'TROT_MONTE'       => estDebutant ? 50.0 : 34.0,
      'OBSTACLE_HAIE'    => estDebutant ? 44.0 : 28.0,
      'OBSTACLE_STEEPLE' => estDebutant ? 42.0 : 26.0,
      'OBSTACLE_CROSS'   => estDebutant ? 40.0 : 24.0,
      'PLAT'             => estDebutant ? 48.0 : 32.0,
      _                  => estDebutant ? _kDebutant : _kFactor,
    };
  }
  static const int    _seuilDebutant = 20;
  static const double _eloMin       = 800.0;
  static const double _eloMax       = 2500.0;

  // ★ v9.92 : clé = "NOM_NORMALISE|DISCIPLINE_NORM"
  final Map<String, EloScore> _ratings = {};
  bool _charge = false;

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ B5c-RDR-05 — barrière de reset (patron CoteTrackerService B5b /
  //  IaMemoryService B5c-P1).
  //
  //  AUCUNE formule ELO, aucun K-factor, aucun rating n'est concerné : on ne
  //  fait qu'encadrer les ÉCRITURES disque de `_sauvegarder()`.
  //
  //  Les trois protections couvrent trois scénarios DISTINCTS et mesurés
  //  (V29-A, V29-B, V29-I) — aucun n'est redondant :
  //    • contrôle 1 (`_resetEnCours`) → écriture née PENDANT l'effacement ;
  //    • contrôle 2 (génération)      → écriture née APRÈS le reset ;
  //    • drain                        → écriture ENGAGÉE avant le reset,
  //      jamais refusable (elle a franchi les deux contrôles).
  // ══════════════════════════════════════════════════════════════════════════
  bool _resetEnCours = false;
  int _generationCache = 0;
  final Set<Future<void>> _ecrituresEnCours = <Future<void>>{};

  /// Nombre de vidages effectués (observable par les tests).
  int get generationCache => _generationCache;

  /// Écritures encore en vol (observable par les tests).
  int get nbEcrituresEnCours => _ecrituresEnCours.length;

  /// Refus par le CONTRÔLE 1 — écriture née pendant l'effacement.
  int _nbRefusParReset = 0;
  int get nbRefusParReset => _nbRefusParReset;

  /// Refus par le CONTRÔLE 2 — génération périmée (écriture née avant le reset).
  int _nbRefusParGeneration = 0;
  int get nbRefusParGeneration => _nbRefusParGeneration;

  static Future<void> init() async => _instance._charger();

  Future<void> _charger() async {
    if (_charge) return;
    try {
      final prefs = await SharedPreferences.getInstance();

      // ── Migration v1 → v2 ─────────────────────────────────────────
      // Si la nouvelle clé est absente mais l'ancienne présente →
      // on importe les anciens ELO avec discipline vide (clé globale)
      final jsonV2 = prefs.getString(_prefsKey);
      if (jsonV2 == null || jsonV2.isEmpty) {
        final jsonV1 = prefs.getString(_prefsKeyOld);
        if (jsonV1 != null && jsonV1.isNotEmpty) {
          final Map<String, dynamic> old = jsonDecode(jsonV1) as Map<String, dynamic>;
          // Les anciens ELO sont stockés sans discipline — on les garde
          // sous la clé "NOM|" (discipline vide) pour ne pas les perdre
          // mais ils ne seront plus mis à jour (les nouvelles mises à jour
          // utilisent la clé avec discipline).
          old.forEach((key, val) {
            try {
              _ratings['$key|'] = EloScore.fromJson(val as Map<String, dynamic>);
            } catch (_) {}
          });
          debugPrint('[EloService] ✅ Migration v1→v2 : ${_ratings.length} ELO importés');
          // ★ v9.99 : supprimer l'ancienne clé après migration pour libérer l'espace
          await prefs.remove(_prefsKeyOld);
        }
      } else {
        final Map<String, dynamic> data = jsonDecode(jsonV2) as Map<String, dynamic>;
        data.forEach((key, val) {
          try {
            _ratings[key] = EloScore.fromJson(val as Map<String, dynamic>);
          } catch (_) {}
        });
      }
      _charge = true;
      debugPrint('[EloService] ✅ ${_ratings.length} ratings chargés (v2)');

      // ★ v9.98 : Purge one-shot des entrées orphelines "NOM|" (discipline vide)
      // Issues de la migration v1→v2 : nb=1 chacune, rating ≈ 1500 ± K, jamais lues
      // car le moteur cherche "NOM|DISCIPLINE" — elles n'apportent rien à l'IA.
      final flagPurge = prefs.getBool('elo_orphelins_purges_v1') ?? false;
      if (!flagPurge) {
        final keysOrphelins = _ratings.keys
            .where((k) => k.endsWith('|'))
            .toList();
        for (final k in keysOrphelins) _ratings.remove(k);
        await prefs.setBool('elo_orphelins_purges_v1', true);
        if (keysOrphelins.isNotEmpty) {
          debugPrint('[EloService] 🧹 Purge orphelins : ${keysOrphelins.length} entrées "NOM|" supprimées');
          await _sauvegarder(); // persister immédiatement
        }
      }
    } catch (e) {
      debugPrint('[EloService] ⚠️ Erreur chargement : $e');
      _charge = true;
    }
  }

  /// ★ B5c-RDR-05 — Enveloppe l'écriture disque dans la barrière de reset.
  ///
  /// Comportement EXTERNE inchangé : retourne `Future<void>`, n'échoue jamais
  /// bruyamment (les erreurs sont journalisées, comme avant), et écrit
  /// exactement les deux mêmes clés dans le même ordre.
  ///
  /// Ce qui change : l'écriture peut être REFUSÉE (et devient alors un no-op
  /// silencieux) si un reset complet est en cours ou est intervenu.
  ///
  /// Cette protection s'applique AUSSI quand `_sauvegarder()` est appelée
  /// depuis `_charger()` (l.107) — demandé explicitement par D-M2.
  Future<void> _sauvegarder() async {
    if (_resetEnCours) {
      _nbRefusParReset++;
      return; // Contrôle 1
    }
    final generation = _generationCache;
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('[EloService] ⚠️ Erreur sauvegarde : $e');
      return;
    }
    if (_resetEnCours || generation != _generationCache) {
      // Contrôle 2 — distinct du contrôle 1 : une génération peut avoir
      // changé alors qu'aucun reset n'est plus EN COURS (il est terminé).
      _nbRefusParGeneration++;
      return;
    }
    // ↓↓↓ AUCUN `await` de ce point jusqu'au `add` (invariant P1) ↓↓↓
    final Future<void> f = _executerSauvegarde(prefs);
    _ecrituresEnCours.add(f);
    f.whenComplete(() => _ecrituresEnCours.remove(f)).ignore();
    return f;
  }

  /// Corps de l'écriture, isolé pour que [_sauvegarder] obtienne la future
  /// AVANT le premier `await` — c'est la condition du registre sans trou.
  ///
  /// Strictement identique à l'ancien corps : mêmes deux écritures, même
  /// `try/catch` silencieux, même journalisation.
  Future<void> _executerSauvegarde(SharedPreferences prefs) async {
    try {
      final data  = <String, dynamic>{};
      _ratings.forEach((k, v) => data[k] = v.toJson());
      await prefs.setString(_prefsKey, jsonEncode(data));
      await prefs.setInt(_prefsKeyTs, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('[EloService] ⚠️ Erreur sauvegarde : $e');
    }
  }

  // ── Normalisation ─────────────────────────────────────────────────
  String _cleNom(String nom) =>
      nom.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');

  // ★ v9.92 : normalise le type de course en discipline canonique
  static String normaliserDiscipline(String type) {
    final t = type.toLowerCase();
    if (t.contains('attele') || t.contains('attelé') || t.contains('trot a')) return 'TROT_ATTELE';
    if (t.contains('monte')  || t.contains('monté')  || t.contains('trot m')) return 'TROT_MONTE';
    if (t.contains('haie')   || t.contains('haies'))                           return 'OBSTACLE_HAIE';
    if (t.contains('steeple'))                                                  return 'OBSTACLE_STEEPLE';
    if (t.contains('cross'))                                                    return 'OBSTACLE_CROSS';
    if (t.contains('plat'))                                                     return 'PLAT';
    if (t.contains('trot'))                                                     return 'TROT_ATTELE';
    if (t.contains('galop'))                                                    return 'PLAT';
    return 'INCONNU';
  }

  // ★ v9.92 : clé composite NOM|DISCIPLINE
  String _cle(String nom, String discipline) =>
      '${_cleNom(nom)}|${normaliserDiscipline(discipline)}';

  // ── Obtenir le score ELO d'un cheval pour une discipline ──────────
  EloScore getScore(String nomCheval, {String discipline = ''}) {
    if (discipline.isNotEmpty) {
      final cleDisc = _cle(nomCheval, discipline);
      if (_ratings.containsKey(cleDisc)) return _ratings[cleDisc]!;
    }
    // Fallback : ancienne clé globale (migration)
    final cleOld = '${_cleNom(nomCheval)}|';
    return _ratings[cleOld] ??
        EloScore(nomCheval: nomCheval, rating: _eloDefaut);
  }

  double getRating(String nomCheval, {String discipline = ''}) =>
      getScore(nomCheval, discipline: discipline).rating;

  // ── Mettre à jour les ELO après une arrivée ── ★ v9.92 : + discipline
  Future<void> mettreAJourApresArrivee({
    required List<int>       arrivee,
    required List<ZtPartant> partants,
    String discipline = '',  // ★ v9.92 : type de course passé par l'appelant
  }) async {
    if (!_charge) await _charger();
    if (arrivee.isEmpty || partants.isEmpty) return;

    final Map<int, ZtPartant> mapPartants = {
      for (final p in partants)
        if (int.tryParse(p.numero) != null) int.parse(p.numero): p
    };
    final n = arrivee.length;
    if (n < 2) return;

    final Map<String, double> deltas = {};

    for (int i = 0; i < n; i++) {
      for (int j = i + 1; j < math.min(i + 4, n); j++) {
        final partantA = mapPartants[arrivee[i]];
        final partantB = mapPartants[arrivee[j]];
        if (partantA == null || partantB == null) continue;

        final cleA = _cle(partantA.nom, discipline);
        final cleB = _cle(partantB.nom, discipline);
        final rA   = getRating(partantA.nom, discipline: discipline);
        final rB   = getRating(partantB.nom, discipline: discipline);

        final probA = 1.0 / (1.0 + math.pow(10, (rB - rA) / 400));
        final probB = 1.0 - probA;

        final nbA = getScore(partantA.nom, discipline: discipline).nbCourses;
        final nbB = getScore(partantB.nom, discipline: discipline).nbCourses;
        final kA  = _kFacteurPourDiscipline(
            EloService.normaliserDiscipline(discipline), nbA < _seuilDebutant);
        final kB  = _kFacteurPourDiscipline(
            EloService.normaliserDiscipline(discipline), nbB < _seuilDebutant);

        final facteurDistance = math.pow(0.7, j - i - 1).toDouble();
        deltas[cleA] = (deltas[cleA] ?? 0.0) + kA * (1.0 - probA) * facteurDistance;
        deltas[cleB] = (deltas[cleB] ?? 0.0) + kB * (0.0 - probB) * facteurDistance;
      }
    }

    deltas.forEach((cle, delta) {
      // Extraire le nom depuis la clé "NOM|DISC"
      final nomDisc  = cle.split('|');
      final nomNorm  = nomDisc[0];
      final partant  = partants.firstWhere(
        (p) => _cleNom(p.nom) == nomNorm,
        orElse: () => partants.first,
      );
      final ancien   = _ratings[cle];
      final ancienR  = ancien?.rating ?? _eloDefaut;
      final nouveau  = (ancienR + delta).clamp(_eloMin, _eloMax);
      final varMois  = ((ancien?.variationMois ?? 0.0) + delta).clamp(-300.0, 300.0);

      _ratings[cle] = EloScore(
        nomCheval:     partant.nom,
        rating:        nouveau,
        nbCourses:     (ancien?.nbCourses ?? 0) + 1,
        variationMois: varMois,
      );
    });

    await _sauvegarder();
    debugPrint('[EloService] ✅ ${deltas.length} ELO mis à jour (discipline: $discipline)');
  }

  // ── Enrichir les partants avec leur ELO ── ★ v9.92 : + discipline
  List<ZtPartant> enrichirAvecElo(List<ZtPartant> partants,
      {String discipline = ''}) {
    return partants.map((p) {
      final score = getScore(p.nom, discipline: discipline);
      return p.copyWith(
        eloRating:        score.rating,
        eloNbCourses:     score.nbCourses,
        eloVariationMois: score.variationMois,
      );
    }).toList();
  }

  int    get nbChevauxSuivis => _ratings.length;
  double get ratingMoyen {
    if (_ratings.isEmpty) return _eloDefaut;
    return _ratings.values.map((e) => e.rating).reduce((a, b) => a + b) / _ratings.length;
  }

  Map<String, dynamic> exporterPourBackup() {
    final data = <String, dynamic>{};
    _ratings.forEach((k, v) => data[k] = v.toJson());
    return data;
  }

  Future<void> importerDepuisBackup(Map<String, dynamic> data) async {
    _ratings.clear();
    data.forEach((key, val) {
      try { _ratings[key] = EloScore.fromJson(val as Map<String, dynamic>); } catch (_) {}
    });
    await _sauvegarder();
    debugPrint('[EloService] ✅ Import backup : ${_ratings.length} ratings restaurés');
  }

  /// ★ v10.82 — D3 : chargement SYNCHRONE depuis une Map JSON, sans
  /// SharedPreferences (indisponible dans un isolate `compute()`).
  ///
  /// Lecture seule : ne sauvegarde rien, ne modifie aucun rating,
  /// ne touche à aucune formule ELO. Utilisé exclusivement par
  /// l'isolate de data_refresh_service.
  ///
  /// Sans ceci, dans un isolate, `EloService.instance` est une instance
  /// neuve (`_ratings` vide) et `enrichirAvecElo()` écrase `eloRating`
  /// avec le défaut 1500 → critère M figé à 37.5 pour tous les chevaux.
  void chargerDepuisMapIsolate(Map<String, dynamic> data) {
    _ratings.clear();
    data.forEach((key, val) {
      try {
        _ratings[key] = EloScore.fromJson(val as Map<String, dynamic>);
      } catch (_) {}
    });
    _charge = true;
    debugPrint('[EloService/isolate] ✅ ${_ratings.length} ratings restaurés');
  }

  Future<void> reinitialiser() async {
    _ratings.clear();
    await _sauvegarder();
    debugPrint('[EloService] 🔄 ELO réinitialisés');
  }

  /// ★ B5-RDR-05 — Vide l'état RAM SANS écrire sur le disque.
  ///
  /// ⚠️ DEPUIS R-DR-05, CETTE MÉTHODE N'EST PLUS APPELÉE PAR LE RESET.
  /// `BackupService.reinitialiserComplet()` utilise désormais
  /// [executerResetComplet], qui vide `_ratings` dans son `finally`.
  ///
  /// Elle est CONSERVÉE parce que :
  ///   • elle est utilisée comme utilitaire de vidage RAM par
  ///     `test/v18_b5_reset_elo_test.dart` (setUp, tearDown et simulation de
  ///     redémarrage) — la supprimer casserait un test validé ;
  ///   • elle reste le moyen sûr de jeter la mémoire sans recréer les clés
  ///     (contrairement à [reinitialiser], qui termine par `_sauvegarder()`).
  ///
  /// ⚠️ COMPORTEMENT RÉSIDUEL DOCUMENTÉ (décision D-M2, non corrigé) :
  /// cette méthode est SYNCHRONE et n'attend RIEN. Appelée alors qu'une
  /// écriture de `_sauvegarder()` est encore en vol, elle vide `_ratings`
  /// mais n'empêche pas cette écriture d'aboutir avec la map qu'elle a déjà
  /// sérialisée. Elle ne ferme pas la barrière, n'incrémente pas la
  /// génération et ne draine pas le registre.
  /// ⇒ Pour un reset, utiliser [executerResetComplet]. Cette méthode ne doit
  ///   JAMAIS être utilisée comme substitut d'un encadrement de reset.
  void viderMemoirePourResetComplet() {
    _ratings.clear();
    debugPrint('[EloService] 🧹 Mémoire vidée (reset complet, disque non réécrit)');
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ B5c-RDR-05 — ENCADREMENT DU RESET COMPLET
  //
  //  Appelé EXCLUSIVEMENT par `BackupService.reinitialiserComplet()`, autour
  //  de la boucle des 107 suppressions, à l'intérieur des barrières
  //  d'`AlertService` et d'`IaMemoryService`.
  //
  //  Sémantique : identique à celle des autres services. On ne calcule RIEN,
  //  on jette un état mémoire devenu obsolète. Aucune formule, aucun
  //  K-factor, aucun rating n'est recalculé ni modifié.
  //
  //  Pourquoi le vidage RAM est dans le `finally` (décision D-M1) :
  //  `supprimerLesCles()` peut lever une `StateError` (C1-a) quand une
  //  suppression est refusée. Avant R-DR-05, l'appel au vidage était situé
  //  APRÈS le bloc, donc jamais atteint sur ce chemin : `_ratings` gardait
  //  les anciennes valeurs alors que les clés ELO avaient été supprimées du
  //  disque. Le `finally` rend le vidage INCONDITIONNEL, y compris en cas
  //  d'échec partiel.
  //
  //  ⚠️ `supprimerLesCles()` n'est entouré d'AUCUN `catch` : l'exception
  //  originale remonte telle quelle, avec sa pile, sans être transformée en
  //  succès. Seul un `finally` est présent.
  //
  //  ⚠️ `_charge` n'est PAS touché : il reste `true`. C'est mesuré et voulu
  //  (V29-C) — repasser `_charge` à `false` ferait relire le disque par
  //  `_charger()` et IMPORTERAIT les données résiduelles.
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> executerResetComplet(
      Future<void> Function() supprimerLesCles) async {
    // 1. Barrière SYNCHRONE — aucun `await` avant ces deux lignes, sinon une
    //    écriture pourrait naître dans la fenêtre.
    _resetEnCours = true;
    _generationCache++;
    try {
      // 2. Drain des écritures ENGAGÉES. Boucle et non `Future.wait` unique :
      //    `whenComplete` s'exécute en microtâche APRÈS la complétion, donc
      //    un `wait` simple peut rendre la main registre non vide.
      //
      //    Sans ce drain, une écriture déjà au-delà des deux contrôles
      //    achèverait son `setString` APRÈS l'effacement et recréerait la clé
      //    (scénario V29-A, mesuré).
      while (_ecrituresEnCours.isNotEmpty) {
        final enVol = List<Future<void>>.from(_ecrituresEnCours);
        try {
          await Future.wait(enVol);
        } catch (_) {
          // Une écriture en échec ne doit jamais faire échouer le reset :
          // l'erreur est déjà journalisée par `_executerSauvegarde`.
        }
      }

      // 3. Effacement disque — TOUJOURS sous barrière.
      //    Aucune exception capturée : elle remonte TELLE QUELLE.
      await supprimerLesCles();
    } finally {
      // 4. Libérations INCONDITIONNELLES, même sur exception.
      //
      //    `_ratings.clear()` est ici, et pas après le bloc : c'est la
      //    décision D-M1. Un reset partiellement échoué ne doit pas laisser
      //    une RAM peuplée face à un disque dont les clés ELO sont parties.
      //
      //    Aucun `await` ne sépare ces deux instructions : aucune autre tâche
      //    ne peut s'intercaler entre le vidage et la réouverture.
      _ratings.clear();
      _resetEnCours = false;
      debugPrint('[EloService] 🧹 Mémoire vidée (reset complet, disque non réécrit)');
    }
  }
}
