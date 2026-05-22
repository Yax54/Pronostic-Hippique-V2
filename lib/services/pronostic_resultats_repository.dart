// ═══════════════════════════════════════════════════════════════════════════
//  PronosticResultatsRepository — Singleton persistant v10.76
//
//  Clé SharedPreferences : 'pronostic_resultats_repository_v2'
//
//  Responsabilités :
//    • Stocker les PronosticResultatUtilisateur (gros paris gagnants)
//    • ajouterOuRemplacer() : idempotent, anti-doublon strict
//    • dedoublonnerParCourseEtPriorite() : garde le meilleur pari par course
//    • Lecture seule depuis l'extérieur (stats utilisateur, Calendrier, IA Stats)
//
//  RÈGLE ABSOLUE : utilisableApprentissage = false pour grosParisSurveiller
//  — ces données ne doivent JAMAIS alimenter le gradient descent.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pronostic_resultat_utilisateur.dart';
import '../models/quasi_gros_paris_models.dart' show prioritePari;

class PronosticResultatsRepository {
  PronosticResultatsRepository._();
  static final instance = PronosticResultatsRepository._();

  static const String storageKey = 'pronostic_resultats_repository_v2';

  final List<PronosticResultatUtilisateur> _items = [];
  bool _charge = false;

  // ── Accès lecture seule ────────────────────────────────────────────────
  List<PronosticResultatUtilisateur> get tous =>
      List.unmodifiable(_items);

  List<PronosticResultatUtilisateur> get gagnants =>
      List.unmodifiable(_items.where((e) => e.gagnant).toList());

  List<PronosticResultatUtilisateur> get utilisablesStats =>
      List.unmodifiable(
          _items.where((e) => e.utilisableStatsUtilisateur).toList());

  // ══════════════════════════════════════════════════════════════════════
  //  PERSISTENCE
  // ══════════════════════════════════════════════════════════════════════

  Future<void> charger() async {
    if (_charge) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw != null && raw.isNotEmpty) {
        final list = json.decode(raw) as List? ?? [];
        _items.clear();
        for (final item in list) {
          try {
            _items.add(PronosticResultatUtilisateur.fromJson(
                item as Map<String, dynamic>));
          } catch (e) {
            if (kDebugMode) {
              debugPrint('[PronosticRepo] item corrompu ignoré: $e');
            }
          }
        }
      }
      if (kDebugMode) {
        debugPrint('[PronosticRepo] Chargé : ${_items.length} résultats');
      }
      _charge = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[PronosticRepo] Erreur chargement: $e');
      _charge = true; // ne jamais bloquer
    }
  }

  Future<void> _sauvegarder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = json.encode(
          _items.map((e) => e.toJson()).toList());
      await prefs.setString(storageKey, encoded);
    } catch (e) {
      if (kDebugMode) debugPrint('[PronosticRepo] Erreur sauvegarde: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  //  ajouterOuRemplacer — idempotent, anti-doublon strict
  //  Supprime tous les doublons courseKey+typePari+source avant insertion.
  //  Applique ensuite la déduplication forte par course.
  // ══════════════════════════════════════════════════════════════════════

  Future<void> ajouterOuRemplacer(PronosticResultatUtilisateur item) async {
    await charger();

    // Supprimer tous les doublons exacts (courseKey + typePari + source)
    _items.removeWhere((e) =>
        e.courseKey == item.courseKey &&
        e.typePari  == item.typePari  &&
        e.source    == item.source);

    _items.add(item);

    // Déduplication forte : une seule entrée par course (meilleur pari)
    final dedoublonnes = dedoublonnerParCourseEtPriorite(_items);
    _items
      ..clear()
      ..addAll(dedoublonnes);

    await _sauvegarder();

    if (kDebugMode) {
      debugPrint('[PronosticRepo] ajouterOuRemplacer: '
          '${item.courseKey} ${item.typePari} '
          '(${item.gagnant ? "✅ gagnant" : "❌ perdant"}) '
          '— total: ${_items.length}');
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  //  dedoublonnerParCourseEtPriorite — garde le meilleur pari par course
  //  Priorité source : grosParisSurveiller > programme
  //  Priorité type : Quinté+ > Quarté+ > Tiercé > Couplé > Placé > Simple
  // ══════════════════════════════════════════════════════════════════════

  static List<PronosticResultatUtilisateur> dedoublonnerParCourseEtPriorite(
    List<PronosticResultatUtilisateur> items,
  ) {
    final map = <String, PronosticResultatUtilisateur>{};

    for (final item in items) {
      final old = map[item.courseKey];

      if (old == null) {
        map[item.courseKey] = item;
        continue;
      }

      final itemPriorite = prioritePari(item.typePari);
      final oldPriorite  = prioritePari(old.typePari);

      if (itemPriorite > oldPriorite) {
        map[item.courseKey] = item;
      } else if (itemPriorite == oldPriorite) {
        // À priorité de type égale, grosParisSurveiller prend le dessus
        if (item.source == 'grosParisSurveiller' &&
            old.source  != 'grosParisSurveiller') {
          map[item.courseKey] = item;
        }
      }
    }

    return map.values.toList();
  }

  // ══════════════════════════════════════════════════════════════════════
  //  Filtres utilitaires (lecture seule — jamais dans gradient)
  // ══════════════════════════════════════════════════════════════════════

  /// Résultats pour une période donnée.
  List<PronosticResultatUtilisateur> pourPeriode({
    required DateTime debut,
    required DateTime fin,
  }) {
    return _items
        .where((e) =>
            !e.dateCourse.isBefore(debut) && !e.dateCourse.isAfter(fin))
        .toList()
      ..sort((a, b) => b.dateCourse.compareTo(a.dateCourse));
  }

  /// Résultats d'une date précise.
  List<PronosticResultatUtilisateur> pourDate(DateTime date) {
    return _items
        .where((e) =>
            e.dateCourse.year  == date.year &&
            e.dateCourse.month == date.month &&
            e.dateCourse.day   == date.day)
        .toList()
      ..sort((a, b) => b.dateCourse.compareTo(a.dateCourse));
  }

  /// Stats par type de pari (lecture seule, jamais apprentissage).
  /// Retourne : {'Tiercé': {'nb': 5, 'gagnants': 2, 'ordre': 1, 'desordre': 1}}
  Map<String, Map<String, int>> statsParType({
    DateTime? debut,
    DateTime? fin,
  }) {
    final filtered = (debut != null && fin != null)
        ? pourPeriode(debut: debut, fin: fin)
        : _items.where((e) => e.utilisableStatsUtilisateur).toList();

    final stats = <String, Map<String, int>>{};

    for (final item in filtered) {
      if (!item.utilisableStatsUtilisateur) continue;
      final t = item.typePari;
      stats.putIfAbsent(t, () => {'nb': 0, 'gagnants': 0, 'ordre': 0, 'desordre': 0});
      stats[t]!['nb'] = (stats[t]!['nb'] ?? 0) + 1;
      if (item.gagnant) {
        stats[t]!['gagnants'] = (stats[t]!['gagnants'] ?? 0) + 1;
        if (item.ordreExact) {
          stats[t]!['ordre'] = (stats[t]!['ordre'] ?? 0) + 1;
        } else {
          stats[t]!['desordre'] = (stats[t]!['desordre'] ?? 0) + 1;
        }
      }
    }

    return stats;
  }

  // ══════════════════════════════════════════════════════════════════════
  //  Export backup
  // ══════════════════════════════════════════════════════════════════════

  Map<String, dynamic> exporterPourBackup() => {
    'pronosticResultats': _items.map((e) => e.toJson()).toList(),
    'nbResultats': _items.length,
    'nbGagnants':  _items.where((e) => e.gagnant).length,
  };

  Future<void> restaurerDepuisBackup(Map<String, dynamic> data) async {
    try {
      final list = data['pronosticResultats'] as List? ?? [];
      _items.clear();
      for (final item in list) {
        try {
          _items.add(PronosticResultatUtilisateur.fromJson(
              item as Map<String, dynamic>));
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[PronosticRepo] restauration item corrompu ignoré: $e');
          }
        }
      }
      await _sauvegarder();
      if (kDebugMode) {
        debugPrint('[PronosticRepo] Restauré : ${_items.length} résultats');
      }
    } catch (e) {
      // Ne jamais bloquer la restauration
      if (kDebugMode) debugPrint('[PronosticRepo] Erreur restauration: $e');
    }
  }
}
