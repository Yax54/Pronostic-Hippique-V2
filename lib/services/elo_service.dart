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

  Future<void> _sauvegarder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
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

  Future<void> reinitialiser() async {
    _ratings.clear();
    await _sauvegarder();
    debugPrint('[EloService] 🔄 ELO réinitialisés');
  }
}
