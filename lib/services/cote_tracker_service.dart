// ═══════════════════════════════════════════════════════════════════════════
//  COTE TRACKER SERVICE — v9.92
//
//  Surveille les mouvements de cotes PMU en temps réel dans la fenêtre
//  des 30 minutes avant chaque départ.
//
//  Fonctionnement :
//   • Poll toutes les 3 minutes les cotes des courses imminentes (< 35 min)
//   • Stocke un historique de cotes par partant sur la fenêtre pré-course
//   • Calcule la variation en % depuis le début de la fenêtre
//   • Déclenche une alerte push si variation > 40% en 15 min sur un cheval
//     déjà recommandé par l'IA (convergence IA + argent informé)
//
//  Critère R (18ème critère IA) :
//   • Dans la fenêtre 30 min → score actif basé sur le mouvement réel
//   • Hors fenêtre → score neutre (50) avec mention "données insuffisantes"
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/zt_models.dart';
import 'alert_service.dart';

// ── Snapshot d'une cote à un instant T ──────────────────────────────────────
class SnapshotCote {
  final DateTime horodatage;
  final double   cote;        // Valeur décimale (ex: 4.5)
  const SnapshotCote({required this.horodatage, required this.cote});
}

// ── Résultat du mouvement pour un partant ───────────────────────────────────
class MouvementCote {
  final String numero;
  final String nom;
  final double coteDebut;     // Première cote observée dans la fenêtre
  final double coteCourante;  // Cote la plus récente
  final double variationPct;  // (coteCourante - coteDebut) / coteDebut * 100
  // Négatif = cote baisse (argent qui rentre) — Positif = cote monte (argent qui fuit)
  final DateTime premierSnap;
  final DateTime dernierSnap;
  final int      nbSnapshots;

  const MouvementCote({
    required this.numero,
    required this.nom,
    required this.coteDebut,
    required this.coteCourante,
    required this.variationPct,
    required this.premierSnap,
    required this.dernierSnap,
    required this.nbSnapshots,
  });

  // Catégorie du mouvement pour l'affichage
  String get categorie {
    if (variationPct <= -40) return 'effondrement';  // Cote chute > 40%
    if (variationPct <= -20) return 'forte_baisse';
    if (variationPct <= -10) return 'baisse';
    if (variationPct >=  40) return 'forte_hausse';  // Cote monte > 40%
    if (variationPct >=  20) return 'hausse';
    if (variationPct >=  10) return 'legere_hausse';
    return 'stable';
  }

  // Score IA (0-100) : baisse de cote = bon signal (argent informé)
  double get scoreIA {
    // Effondrement (-40%+) → score très élevé (90)
    // Forte baisse (-20%) → score élevé (75)
    // Baisse (-10%) → score modéré (62)
    // Stable → neutre (50)
    // Hausse (+10%) → signal négatif (38)
    // Forte hausse (+20%) → signal très négatif (25)
    if (variationPct <= -40) return 90.0;
    if (variationPct <= -20) return 75.0;
    if (variationPct <= -10) return 62.0;
    if (variationPct >=  40) return 15.0;
    if (variationPct >=  20) return 28.0;
    if (variationPct >=  10) return 38.0;
    return 50.0;  // Stable
  }

  String get emoji {
    switch (categorie) {
      case 'effondrement':  return '🔥';
      case 'forte_baisse':  return '📉';
      case 'baisse':        return '↘️';
      case 'forte_hausse':  return '📈';
      case 'hausse':        return '↗️';
      case 'legere_hausse': return '↑';
      default:              return '→';
    }
  }

  String get deltaStr {
    final sign = variationPct < 0 ? '' : '+';
    return '$sign${variationPct.toStringAsFixed(0)}%';
  }
}

// ── CoteTrackerService ───────────────────────────────────────────────────────
class CoteTrackerService {
  static final CoteTrackerService _instance = CoteTrackerService._();
  static CoteTrackerService get instance => _instance;
  CoteTrackerService._();

  static const String _baseUrl = 'https://turfinfo.api.pmu.fr/rest/client/7';
  static const String _specialisation = 'specialisation=INTERNET';

  // ── État interne ────────────────────────────────────────────────────────
  // Clé : 'RNCN_DDMMYYYY|numero' → historique de snapshots
  final Map<String, List<SnapshotCote>> _historique = {};
  // Clé : 'RNCN_DDMMYYYY' → derniers mouvements calculés
  final Map<String, List<MouvementCote>> _mouvements = {};

  Timer? _pollTimer;
  bool   _polling = false;

  // Alertes déjà envoyées pour éviter les doublons
  final Set<String> _alertesEnvoyees = {};

  // ★ v9.99 : clé SharedPreferences pour persister les derniers mouvements
  static const String _prefsKeyMouvements = 'cote_tracker_mouvements_v1';

  // ── Démarrage / arrêt ────────────────────────────────────────────────────
  void demarrer(List<ZtReunion> reunions) {
    // ★ v10.24 : injecter le callback "cotes qui chutent" dans AlertService
    // (évite l'import circulaire : CoteTracker → AlertService déjà présent,
    //  AlertService → CoteTracker serait circulaire)
    AlertService.instance.setCotesChuteCallback(_getCotesChuteActuelles);

    _pollTimer?.cancel();
    // Poll toutes les 3 minutes
    _pollTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      _pollCotesImminentes(reunions);
    });
    // Premier poll immédiat
    _pollCotesImminentes(reunions);
  }

  // ★ v10.24 : retourne les mouvements de cote ≥ 20% de baisse
  // Format : [{courseKey, numero, nom, variationPct, coteCourante, categorie}]
  List<Map<String, dynamic>> _getCotesChuteActuelles() {
    final result = <Map<String, dynamic>>[];
    _mouvements.forEach((courseKey, mouvs) {
      for (final m in mouvs) {
        // forte_baisse = ≤-20%, effondrement = ≤-40%
        if (m.categorie == 'forte_baisse' || m.categorie == 'effondrement') {
          result.add({
            'courseKey':   courseKey,
            'numero':      m.numero,
            'nom':         m.nom,
            'variationPct':m.variationPct,
            'coteCourante':m.coteCourante,
            'categorie':   m.categorie,
          });
        }
      }
    });
    return result;
  }

  void arreter() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void mettreAJourReunions(List<ZtReunion> reunions) {
    // Relancer le timer avec les nouvelles réunions
    demarrer(reunions);
  }

  // ★ v9.99 : Charger les mouvements persistés (appelé au démarrage)
  Future<void> chargerMouvementsPersistes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKeyMouvements);
      if (raw == null || raw.isEmpty) return;
      final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
      final now = DateTime.now();
      data.forEach((courseKey, listRaw) {
        // Ne restaurer que les mouvements du jour (< 6h)
        final dateMatch = RegExp(r'_(\d{8})$').firstMatch(courseKey);
        if (dateMatch != null) {
          try {
            final ds = dateMatch.group(1)!;
            final d = int.parse(ds.substring(0, 2));
            final m = int.parse(ds.substring(2, 4));
            final y = int.parse(ds.substring(4, 8));
            final courseDate = DateTime(y, m, d);
            if (now.difference(courseDate).inHours > 6) return;
          } catch (_) { return; }
        }
        try {
          final list = (listRaw as List<dynamic>).map((e) {
            final j = e as Map<String, dynamic>;
            return MouvementCote(
              numero:       j['numero'] as String,
              nom:          j['nom'] as String,
              coteDebut:    (j['coteDebut'] as num).toDouble(),
              coteCourante: (j['coteCourante'] as num).toDouble(),
              variationPct: (j['variationPct'] as num).toDouble(),
              premierSnap:  DateTime.parse(j['premierSnap'] as String),
              dernierSnap:  DateTime.parse(j['dernierSnap'] as String),
              nbSnapshots:  (j['nbSnapshots'] as int? ?? 1),
            );
          }).toList();
          _mouvements[courseKey] = list;
        } catch (_) {}
      });
      if (kDebugMode) debugPrint('[CoteTracker] ✅ Mouvements restaurés : ${_mouvements.length} course(s)');
    } catch (e) {
      if (kDebugMode) debugPrint('[CoteTracker] ⚠️ Erreur restauration : $e');
    }
  }

  // ★ v9.99 : Sauvegarder les mouvements actuels dans SharedPreferences
  Future<void> _sauvegarderMouvements() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> data = {};
      _mouvements.forEach((courseKey, mouvs) {
        data[courseKey] = mouvs.map((m) => {
          'numero':       m.numero,
          'nom':          m.nom,
          'coteDebut':    m.coteDebut,
          'coteCourante': m.coteCourante,
          'variationPct': m.variationPct,
          'premierSnap':  m.premierSnap.toIso8601String(),
          'dernierSnap':  m.dernierSnap.toIso8601String(),
          'nbSnapshots':  m.nbSnapshots,
        }).toList();
      });
      await prefs.setString(_prefsKeyMouvements, jsonEncode(data));
    } catch (e) {
      if (kDebugMode) debugPrint('[CoteTracker] ⚠️ Erreur sauvegarde : $e');
    }
  }

  // ── Accès aux mouvements pour une course ─────────────────────────────────
  List<MouvementCote> mouvementsPourCourse(String courseKey) =>
      _mouvements[courseKey] ?? [];

  MouvementCote? mouvementPourPartant(String courseKey, String numero) {
    return _mouvements[courseKey]
        ?.where((m) => m.numero == numero)
        .firstOrNull;
  }

  // ── Vérifier si on est dans la fenêtre active (< 30 min avant départ) ─────
  bool estDansFenetre(ZtCourse course) {
    final now    = DateTime.now();
    final depart = course.heureDateTime;
    final diff   = depart.difference(now).inMinutes;
    return diff >= 0 && diff <= 30;
  }

  // ── Score du critère R pour un partant ────────────────────────────────────
  // Retourne null si hors fenêtre (affichage "données insuffisantes")
  double? scoreCritereR(String courseKey, String numero) {
    final m = mouvementPourPartant(courseKey, numero);
    if (m == null) return null;
    return m.scoreIA;
  }

  // ── Poll des cotes pour les courses imminentes ────────────────────────────
  Future<void> _pollCotesImminentes(List<ZtReunion> reunions) async {
    if (_polling) return;
    _polling = true;
    try {
      final now = DateTime.now();
      for (final reunion in reunions) {
        final numRMatch = RegExp(r'R(\d+)').firstMatch(reunion.code);
        if (numRMatch == null) continue;
        final numR = int.tryParse(numRMatch.group(1) ?? '') ?? 0;

        for (final course in reunion.courses) {
          final depart = course.heureDateTime;
          final diffMin = depart.difference(now).inMinutes;

          // Fenêtre active : entre 0 et 35 minutes avant le départ
          // (5 min de marge pour s'assurer d'avoir au moins 2 snapshots)
          if (diffMin < 0 || diffMin > 35) continue;

          final dateStr = reunion.dateStr.isNotEmpty ? reunion.dateStr
              : '${now.day.toString().padLeft(2,'0')}${now.month.toString().padLeft(2,'0')}${now.year}';

          final courseKey = 'R${numR}C${course.numCourse}_$dateStr';

          await _fetchEtStockerCotes(
            dateStr:   dateStr,
            numR:      numR,
            numC:      course.numCourse,
            courseKey: courseKey,
            partants:  course.partants,
            course:    course,
          );
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[CoteTracker] Erreur poll: $e');
    } finally {
      _polling = false;
    }
  }

  // ── Fetch les cotes depuis l'API PMU et stocke les snapshots ─────────────
  Future<void> _fetchEtStockerCotes({
    required String       dateStr,
    required int          numR,
    required int          numC,
    required String       courseKey,
    required List<ZtPartant> partants,
    required ZtCourse     course,
  }) async {
    try {
      final url = '$_baseUrl/programme/$dateStr/R$numR/C$numC'
          '/participants?$_specialisation';
      final resp = await http.get(Uri.parse(url), headers: {
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 8));

      if (resp.statusCode != 200) return;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = (data['participants'] as List<dynamic>? ?? []);

      final now = DateTime.now();

      for (final item in list) {
        final numStr = (item['numPmu'] ?? item['numero'])?.toString() ?? '';
        if (numStr.isEmpty) continue;

        // Chercher la cote dans la réponse API
        double cote = 0.0;
        final rapports = item['rapports'] as List<dynamic>? ?? [];
        for (final r in rapports) {
          if ((r['typePari'] as String? ?? '').contains('SIMPLE_GAGNANT') ||
              (r['typePari'] as String? ?? '').contains('E_SIMPLE_GAGNANT')) {
            cote = (r['rapport'] as num?)?.toDouble() ?? 0.0;
            break;
          }
        }
        // Fallback : chercher directement dans les champs du partant
        if (cote <= 0) {
          cote = (item['rapportParis'] as num?)?.toDouble() ?? 0.0;
        }
        if (cote <= 0) continue;

        final snapKey = '$courseKey|$numStr';
        _historique.putIfAbsent(snapKey, () => []);
        _historique[snapKey]!.add(SnapshotCote(horodatage: now, cote: cote));

        // Garder max 20 snapshots (= 1h de données à 3 min/snap)
        if (_historique[snapKey]!.length > 20) {
          _historique[snapKey]!.removeAt(0);
        }
      }

      // Recalculer les mouvements pour cette course
      _calculerMouvements(courseKey, partants, course);

    } catch (e) {
      if (kDebugMode) debugPrint('[CoteTracker] Erreur fetch R${numR}C$numC: $e');
    }
  }

  // ── Calcul des mouvements et détection des alertes ────────────────────────
  void _calculerMouvements(
      String courseKey, List<ZtPartant> partants, ZtCourse course) {
    final mouvements = <MouvementCote>[];
    for (final partant in partants) {
      final snapKey  = '$courseKey|${partant.numero}';
      final snaps    = _historique[snapKey] ?? [];
      if (snaps.length < 2) continue;

      final coteDebut    = snaps.first.cote;
      final coteCourante = snaps.last.cote;
      final variationPct = (coteCourante - coteDebut) / coteDebut * 100;

      final m = MouvementCote(
        numero:        partant.numero,
        nom:           partant.nom,
        coteDebut:     coteDebut,
        coteCourante:  coteCourante,
        variationPct:  variationPct,
        premierSnap:   snaps.first.horodatage,
        dernierSnap:   snaps.last.horodatage,
        nbSnapshots:   snaps.length,
      );
      mouvements.add(m);

      // ── Détection alerte convergence IA + cote ──────────────────────────
      // Conditions :
      //   1. Cote chute de plus de 40% depuis le début de la fenêtre
      //   2. Le cheval est en top 3 IA (scoreIA >= 65 ou rang <= 3)
      //   3. Le mouvement s'est produit en moins de 15 min
      //   4. L'alerte n'a pas déjà été envoyée pour ce cheval/course
      final alerteKey = '$courseKey|${partant.numero}|convergence';
      if (!_alertesEnvoyees.contains(alerteKey) &&
          variationPct <= -40 &&
          partant.scoreIA >= 65 &&
          snaps.last.horodatage.difference(snaps.first.horodatage).inMinutes <= 15) {
        _alertesEnvoyees.add(alerteKey);
        _envoyerAlerteConvergence(
          courseKey:     courseKey,
          course:        course,
          partant:       partant,
          mouvement:     m,
        );
      }
    }

    _mouvements[courseKey] = mouvements;
    // ★ v9.93 : Synchroniser vers SharedPreferences pour le Worker Kotlin
    _syncMouvementsVersPrefs().ignore();
    if (kDebugMode && mouvements.isNotEmpty) {
      debugPrint('[CoteTracker] $courseKey — ${mouvements.length} mouvements calculés');
    }
    // ★ v9.99 : persister après chaque calcul
    _sauvegarderMouvements();
  }

  // ── Alerte push convergence IA + argent informé ───────────────────────────
  void _envoyerAlerteConvergence({
    required String       courseKey,
    required ZtCourse     course,
    required ZtPartant    partant,
    required MouvementCote mouvement,
  }) {
    final deltaStr = mouvement.deltaStr;
    AlertService.instance.ajouterAlertConvergenceIACote(
      courseKey:  courseKey,
      nomCourse:  course.nom,
      hippodrome: '', // sera rempli par AlertService depuis la réunion
      nomCheval:  partant.nom,
      numero:     partant.numero,
      coteDebut:  mouvement.coteDebut,
      coteFin:    mouvement.coteCourante,
      delta:      deltaStr,
      scoreIA:    partant.scoreIA,
    );
    if (kDebugMode) {
      debugPrint('[CoteTracker] 🔥 ALERTE CONVERGENCE: ${partant.nom} '
          'cote ${mouvement.coteDebut}→${mouvement.coteCourante} ($deltaStr) '
          'IA ${partant.scoreIA.toStringAsFixed(0)}/100');
    }
  }

  // ★ v9.93 POINT 4 : Synchroniser les mouvements de cotes vers SharedPreferences
  // pour que le Worker Kotlin puisse les lire (évite le doublon de logique).
  // Format JSON : [{'courseKey': '...', 'numero': '...', 'nomCheval': '...',
  //                'coteDebut': 0.0, 'coteCourante': 0.0, 'variationPct': 0.0,
  //                'scoreIA': 0.0, 'categorie': '...'}]
  Future<void> _syncMouvementsVersPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tous  = <Map<String, dynamic>>[];
      _mouvements.forEach((courseKey, mouvements) {
        for (final m in mouvements) {
          if (m.variationPct.abs() < 5) continue; // ignorer les mouvements insignifiants
          tous.add({
            'courseKey':    courseKey,
            'numero':       m.numero,
            'nomCheval':    m.nom,
            'coteDebut':    m.coteDebut,
            'coteCourante': m.coteCourante,
            'variationPct': m.variationPct,
            'scoreIA':      0.0, // sera rempli par le caller qui a accès à scoreIA
            'categorie':    m.categorie,
          });
        }
      });
      await prefs.setString('cote_mouvements_live_v1', json.encode(tous));
    } catch (e) {
      if (kDebugMode) debugPrint('[CoteTracker] Erreur sync prefs: $e');
    }
  }
  void nettoyerDonneesPerimees() {
    final now = DateTime.now();
    _historique.removeWhere((key, snaps) {
      if (snaps.isEmpty) return true;
      // Supprimer les données de plus de 3h
      return now.difference(snaps.last.horodatage).inHours > 3;
    });
    _mouvements.removeWhere((key, _) {
      // Extraire la date depuis la clé
      final dateMatch = RegExp(r'_(\d{8})$').firstMatch(key);
      if (dateMatch == null) return false;
      final ds = dateMatch.group(1)!;
      try {
        final d = int.parse(ds.substring(0, 2));
        final m = int.parse(ds.substring(2, 4));
        final y = int.parse(ds.substring(4, 8));
        final courseDate = DateTime(y, m, d);
        return now.difference(courseDate).inHours > 6;
      } catch (_) {
        return false;
      }
    });
  }
}
