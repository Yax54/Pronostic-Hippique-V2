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

/// ★ A7 (3.2) — RÉSULTAT D'UNE TENTATIVE DE PERSISTANCE ELO.
///
/// Ce type existe parce qu'un `Future<void>` ne permet pas de distinguer une
/// écriture CONFIRMÉE d'une écriture REFUSÉE, d'une écriture en ERREUR, ou
/// d'un appel qui n'a rien eu à écrire. Aujourd'hui, l'appelant reçoit la fin
/// de la future et ne peut rien en déduire — c'est le défaut que 3.2 corrige.
///
/// ⚠️ CE QUE CES ÉTATS NE DISENT **PAS** — À LIRE AVANT TOUT USAGE
/// ────────────────────────────────────────────────────────────────
/// `refusee` et `echouee` signifient **« persistance NON CONFIRMÉE »**,
/// JAMAIS « ratings persistés inchangés ». Le stockage peut avoir écrit puis
/// répondu `false`, ou avoir levé après une écriture partielle. Aucun code ne
/// doit déduire de ces états que le disque est resté intact.
///
/// Corollaire : ces états ne constituent PAS une autorisation de rejouer
/// l'opération. 3.2 n'implémente aucun rejeu. La RAM a été modifiée dans tous
/// les cas où l'état n'est pas [nonTentee] / [abandonneeParReset] : la
/// sauvegarde SUIVANTE resérialisera `_ratings` en entier et persistera donc
/// la course dont l'écriture avait échoué. C'est un rattrapage de fait, non
/// une garantie — le journal d'intention de 3.3 est ce qui le rendra explicite.
enum EtatPersistanceElo {
  /// `setString` a répondu `true` sur `elo_ratings_v2`.
  /// C'est la SEULE valeur qui constitue une confirmation d'écriture.
  persistee,

  /// `setString` a répondu `false`. Persistance NON CONFIRMÉE.
  refusee,

  /// Une exception est survenue pendant l'écriture. Persistance NON CONFIRMÉE.
  echouee,

  /// Rien n'a été tenté : arrivée vide, ou moins de deux partants.
  /// Ce n'est PAS un échec — aucun écriture n'était justifiée.
  nonTentee,

  /// Refusée par la barrière de reset (contrôle 1 ou 2 de `_sauvegarder`).
  /// Ce n'est PAS un échec — l'écriture a été invalidée volontairement.
  abandonneeParReset,
}

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

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ A7 (3.2) — COMPTEURS D'OBSERVABILITÉ DE LA PERSISTANCE.
  //
  //  ⚠️ CES COMPTEURS S'AJOUTENT, ILS NE REMPLACENT RIEN. Les quatre
  //  compteurs historiques ci-dessus gardent leur valeur, leur point
  //  d'incrément et leur sémantique : `v29`/`v29b` les mesurent par DELTA
  //  avant/après, donc leur ajouter des voisins n'a aucun effet sur eux.
  //
  //  Un compteur ne s'incrémente QUE sur l'issue qu'il nomme :
  //    • nbPersistees       ← `setString(true)` ;
  //    • nbRefuseesStockage ← `setString(false)` ;
  //    • nbEchouees         ← exception pendant l'écriture des ratings ;
  //    • nbEchecsTs         ← `setInt(false)` ou exception sur `_ts` SEUL.
  //  Un échec de `_ts` N'INCRÉMENTE PAS `nbEchecs` : le rating est persisté.
  // ──────────────────────────────────────────────────────────────────────────
  int _nbPersistees = 0;
  int _nbRefuseesStockage = 0;
  int _nbEchouees = 0;
  int _nbEchecsTs = 0;

  /// Écritures de `elo_ratings_v2` CONFIRMÉES par `setString → true`.
  int get nbPersistees => _nbPersistees;

  /// Écritures de `elo_ratings_v2` REFUSÉES par `setString → false`.
  /// Persistance NON CONFIRMÉE (voir [EtatPersistanceElo]).
  int get nbRefuseesStockage => _nbRefuseesStockage;

  /// Écritures de `elo_ratings_v2` ayant LEVÉ une exception.
  /// Persistance NON CONFIRMÉE (voir [EtatPersistanceElo]).
  int get nbEchouees => _nbEchouees;

  /// Défauts SECONDAIRES sur `elo_ratings_v2_ts`, indépendants du rating.
  /// `elo_ratings_v2_ts` n'est PAS une preuve d'application ELO.
  int get nbEchecsTs => _nbEchecsTs;

  /// Dernière exception observée pendant une écriture, ou `null`.
  /// Conservée pour le diagnostic : 3.2 n'ouvre AUCUN rejeu à partir d'elle.
  Object? _derniereErreurEcriture;
  Object? get derniereErreurEcriture => _derniereErreurEcriture;

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
          // ★ A7 (3.2) : le résultat est CONNU et journalisé, jamais ignoré.
          // Aucune exception ne peut s'en échapper (option A validée) : le
          // chemin de chargement reste donc inchangé sur le plan du contrôle.
          final etatPurge = await _sauvegarder(); // persister immédiatement
          if (etatPurge != EtatPersistanceElo.persistee) {
            debugPrint('[EloService] ⚠️ Purge orphelins non confirmée sur le '
                'disque : ${etatPurge.name}');
          }
        }
      }
    } catch (e) {
      debugPrint('[EloService] ⚠️ Erreur chargement : $e');
      _charge = true;
    }
  }

  /// ★ B5c-RDR-05 — Enveloppe l'écriture disque dans la barrière de reset.
  ///
  /// Deux contrôles historiques INCHANGÉS (`_resetEnCours`, puis génération),
  /// mêmes compteurs, mêmes points d'incrément. Ce qui change en 3.2 : les
  /// sorties ne sont plus muettes, elles rendent une valeur explicite.
  ///
  /// ★ SÉMANTIQUE DU RETOUR (3.2) : [EtatPersistanceElo.refusee] et
  /// [EtatPersistanceElo.echouee] signifient PERSISTANCE NON CONFIRMÉE,
  /// JAMAIS « disque inchangé ». Aucun rejeu ne doit en être déduit.
  Future<EtatPersistanceElo> _sauvegarder() async {
    if (_resetEnCours) {
      _nbRefusParReset++;
      return EtatPersistanceElo.abandonneeParReset; // Contrôle 1
    }
    final generation = _generationCache;
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      // ★ 3.2 : n'était qu'un `debugPrint` + `return` muet. L'échec est
      // désormais COMPTÉ et CONSERVÉ — plus jamais silencieux.
      _nbEchouees++;
      _derniereErreurEcriture = e;
      debugPrint('[EloService] ⚠️ Sauvegarde impossible '
          '(SharedPreferences indisponible) : $e');
      return EtatPersistanceElo.echouee;
    }
    if (_resetEnCours || generation != _generationCache) {
      // Contrôle 2 — distinct du contrôle 1 : une génération peut avoir
      // changé alors qu'aucun reset n'est plus EN COURS (il est terminé).
      _nbRefusParGeneration++;
      return EtatPersistanceElo.abandonneeParReset;
    }
    // ↓↓↓ AUCUN `await` de ce point jusqu'au `add` (invariant P1) ↓↓↓
    final Future<EtatPersistanceElo> f = _executerSauvegarde(prefs);
    _ecrituresEnCours.add(f);
    f.whenComplete(() => _ecrituresEnCours.remove(f)).ignore();
    return f;
  }

  /// Corps de l'écriture, isolé pour que [_sauvegarder] obtienne la future
  /// AVANT le premier `await` — c'est la condition du registre sans trou.
  ///
  /// ★ A7 (3.2) — DEUX changements, et deux seulement :
  ///   • les retours `bool` de `setString`/`setInt` ne sont plus jetés ;
  ///   • l'exception n'est plus avalée : journalisée, comptée, convertie.
  ///
  /// ⚠️ NOMBRE D'ÉCRITURES — ÉNONCÉ EXACT (corrigé en 3.2 / lot 1, cf. C2).
  /// Au cas NOMINAL, le comportement est identique à avant 3.2 : deux
  /// écritures, `_prefsKey` puis `_prefsKeyTs`, dans cet ordre exact.
  ///
  /// En CAS D'ÉCHEC de `setString`, il DIFFÈRE, et il faut le savoir :
  /// avant 3.2 les deux `await` vivaient dans UN SEUL `try`, donc une
  /// exception sur `setString` sautait `setInt` (0 écriture `_ts`) ; depuis
  /// 3.2 `_prefsKeyTs` est écrite dans un `try` SÉPARÉ, donc elle est
  /// TENTÉE (1 écriture `_ts`) même quand les ratings ont échoué. C'est
  /// voulu : c'est ce qui rend l'échec secondaire observable et comptable
  /// séparément, sans jamais altérer le résultat principal.
  ///
  /// ⚠️ `_prefsKeyTs` N'EST PAS une preuve d'application ELO. Son échec
  /// n'altère donc JAMAIS le résultat principal : si `setString` a confirmé
  /// le rating, le résultat reste [EtatPersistanceElo.persistee] et le défaut
  /// secondaire est seulement compté dans [nbEchecsTs].
  Future<EtatPersistanceElo> _executerSauvegarde(
      SharedPreferences prefs) async {
    EtatPersistanceElo etat;
    try {
      final data  = <String, dynamic>{};
      _ratings.forEach((k, v) => data[k] = v.toJson());
      // ★ 3.2 : le booléen était JETÉ, il ne l'est plus.
      final bool okRatings =
          await prefs.setString(_prefsKey, jsonEncode(data));
      if (okRatings) {
        _nbPersistees++;
        etat = EtatPersistanceElo.persistee;
      } else {
        _nbRefuseesStockage++;
        etat = EtatPersistanceElo.refusee;
        debugPrint('[EloService] ⚠️ Sauvegarde REFUSÉE par le stockage sur '
            '`$_prefsKey` — persistance NON CONFIRMÉE (le disque n\'est PAS '
            'prouvé inchangé)');
      }
    } catch (e, st) {
      // ★ 3.2 : exception JOURNALISÉE, COMPTÉE, CONSERVÉE — jamais avalée.
      _nbEchouees++;
      _derniereErreurEcriture = e;
      etat = EtatPersistanceElo.echouee;
      debugPrint('[EloService] ⚠️ Exception pendant la sauvegarde de '
          '`$_prefsKey` — persistance NON CONFIRMÉE : $e\n$st');
    }

    // ── Horodatage SECONDAIRE, hors du mécanisme de preuve ────────────────
    // Écrit dans TOUS les cas, exactement comme avant. Son issue ne modifie
    // jamais `etat` : elle est seulement rendue observable.
    try {
      final bool okTs = await prefs.setInt(
          _prefsKeyTs, DateTime.now().millisecondsSinceEpoch);
      if (!okTs) {
        _nbEchecsTs++;
        debugPrint('[EloService] ⚠️ Horodatage REFUSÉ sur `$_prefsKeyTs` '
            '(défaut SECONDAIRE — le rating n\'est PAS concerné)');
      }
    } catch (e) {
      _nbEchecsTs++;
      debugPrint('[EloService] ⚠️ Exception sur `$_prefsKeyTs` '
          '(défaut SECONDAIRE — le rating n\'est PAS concerné) : $e');
    }

    return etat;
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
  //
  // ★ A7 (3.2) : retourne l'ISSUE de la persistance. Les calculs, formules,
  //   K-factors et les deux sorties anticipées sont STRICTEMENT inchangés ;
  //   seules leurs valeurs de retour deviennent explicites.
  Future<EtatPersistanceElo> mettreAJourApresArrivee({
    required List<int>       arrivee,
    required List<ZtPartant> partants,
    String discipline = '',  // ★ v9.92 : type de course passé par l'appelant
  }) async {
    if (!_charge) await _charger();
    if (arrivee.isEmpty || partants.isEmpty) {
      return EtatPersistanceElo.nonTentee; // rien à écrire : pas un échec
    }

    final Map<int, ZtPartant> mapPartants = {
      for (final p in partants)
        if (int.tryParse(p.numero) != null) int.parse(p.numero): p
    };
    final n = arrivee.length;
    if (n < 2) return EtatPersistanceElo.nonTentee;

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

    final EtatPersistanceElo etat = await _sauvegarder();
    debugPrint('[EloService] ${etat == EtatPersistanceElo.persistee ? "✅" : "⚠️"} '
        '${deltas.length} ELO mis à jour (discipline: $discipline) — '
        'persistance: ${etat.name}');
    return etat;
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

  Future<EtatPersistanceElo> importerDepuisBackup(
      Map<String, dynamic> data) async {
    _ratings.clear();
    data.forEach((key, val) {
      try { _ratings[key] = EloScore.fromJson(val as Map<String, dynamic>); } catch (_) {}
    });
    final etat = await _sauvegarder();
    debugPrint('[EloService] ${etat == EtatPersistanceElo.persistee ? "✅" : "⚠️"} '
        'Import backup : ${_ratings.length} ratings restaurés — '
        'persistance: ${etat.name}');
    return etat;
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

  Future<EtatPersistanceElo> reinitialiser() async {
    _ratings.clear();
    final etat = await _sauvegarder();
    debugPrint('[EloService] 🔄 ELO réinitialisés — persistance: ${etat.name}');
    return etat;
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
  //  de la boucle des 108 suppressions, à l'intérieur des barrières
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
