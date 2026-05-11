// ═══════════════════════════════════════════════════════════════════════════
//  IA BADGES SERVICE — v9.85
//  Système de badges et récompenses partagés avec l'IA
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Définition d'un badge ───────────────────────────────────────────────────
class IaBadge {
  final String id;
  final String emoji;
  final String titre;
  final String description;
  final String categorie; // 'analyse' | 'paris' | 'ia' | 'serie'
  final DateTime? debloqueLe;

  const IaBadge({
    required this.id,
    required this.emoji,
    required this.titre,
    required this.description,
    required this.categorie,
    this.debloqueLe,
  });

  bool get estDebloque => debloqueLe != null;

  IaBadge avecDate(DateTime date) => IaBadge(
    id: id, emoji: emoji, titre: titre,
    description: description, categorie: categorie,
    debloqueLe: date,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'debloqueLe': debloqueLe?.toIso8601String(),
  };
}

// ─── Catalogue complet des badges ────────────────────────────────────────────
class IaBadgesCatalogue {
  static const List<IaBadge> tous = [
    // ── Analyse IA ──────────────────────────────────────────────────────────
    IaBadge(id: 'premiere_analyse',   emoji: '🔬', titre: 'Premier regard',      description: 'Lancer la première analyse journée',            categorie: 'analyse'),
    IaBadge(id: 'analyse_10',         emoji: '📊', titre: 'Analyste',             description: '10 analyses journées effectuées',               categorie: 'analyse'),
    IaBadge(id: 'analyse_50',         emoji: '🧠', titre: 'Cerveau actif',        description: '50 analyses journées effectuées',               categorie: 'analyse'),
    IaBadge(id: 'analyse_100',        emoji: '🎓', titre: 'Expert en données',    description: '100 analyses journées effectuées',              categorie: 'analyse'),
    IaBadge(id: 'courses_100',        emoji: '🏇', titre: '100 courses',          description: '100 courses analysées avec résultat',           categorie: 'analyse'),
    IaBadge(id: 'courses_300',        emoji: '💎', titre: 'Maître des courses',   description: '300 courses analysées avec résultat',           categorie: 'analyse'),
    IaBadge(id: 'taux_60',           emoji: '🎯', titre: 'Précision confirmée',   description: 'Taux de réussite IA ≥ 60% sur 30 jours',       categorie: 'analyse'),
    IaBadge(id: 'taux_75',           emoji: '🔥', titre: 'Excellence',            description: 'Taux de réussite IA ≥ 75% sur 30 jours',       categorie: 'analyse'),

    // ── Paris ────────────────────────────────────────────────────────────────
    IaBadge(id: 'premier_pari',       emoji: '🎫', titre: 'Premier ticket',       description: 'Placer le premier pari suivi',                  categorie: 'paris'),
    IaBadge(id: 'premiere_victoire',  emoji: '🏆', titre: 'Première victoire',    description: 'Gagner le premier pari',                        categorie: 'paris'),
    IaBadge(id: 'premier_quinte',     emoji: '⭐', titre: 'Premier Quinté',       description: 'Réussir un Quinté+',                           categorie: 'paris'),
    IaBadge(id: 'paris_10',          emoji: '🎰', titre: 'Parieur confirmé',      description: '10 paris enregistrés',                         categorie: 'paris'),
    IaBadge(id: 'paris_50',          emoji: '🃏', titre: 'Parieur expérimenté',   description: '50 paris enregistrés',                         categorie: 'paris'),
    IaBadge(id: 'gain_100',          emoji: '💰', titre: 'Centenaire',            description: 'Cumuler 100 € de gains nets',                  categorie: 'paris'),
    IaBadge(id: 'gain_500',          emoji: '🤑', titre: 'Grand gagnant',         description: 'Cumuler 500 € de gains nets',                  categorie: 'paris'),
    IaBadge(id: 'outlier',           emoji: '🦄', titre: 'L\'outsider payant',    description: 'Gagner avec un cheval à cote > 10',            categorie: 'paris'),

    // ── Séries ───────────────────────────────────────────────────────────────
    IaBadge(id: 'serie_3',           emoji: '🔗', titre: 'En série !',            description: '3 paris gagnants consécutifs',                  categorie: 'serie'),
    IaBadge(id: 'serie_5',           emoji: '⚡', titre: 'Inarrêtable',           description: '5 paris gagnants consécutifs',                  categorie: 'serie'),
    IaBadge(id: 'serie_10',          emoji: '👑', titre: 'Légendaire',            description: '10 paris gagnants consécutifs',                 categorie: 'serie'),
    IaBadge(id: 'rebond',            emoji: '💪', titre: 'Le rebond',             description: 'Gagner après 3 défaites consécutives',          categorie: 'serie'),

    // ── IA ───────────────────────────────────────────────────────────────────
    IaBadge(id: 'ia_1mois',          emoji: '🎂', titre: '1 mois ensemble',       description: 'L\'IA a 1 mois d\'existence',                  categorie: 'ia'),
    IaBadge(id: 'ia_6mois',          emoji: '🌟', titre: '6 mois ensemble',       description: 'L\'IA a 6 mois d\'existence',                  categorie: 'ia'),
    IaBadge(id: 'ia_1an',            emoji: '🎊', titre: '1 an ensemble',         description: 'L\'IA a 1 an d\'existence',                    categorie: 'ia'),
    IaBadge(id: 'ia_prenom',         emoji: '✏️', titre: 'Personnalisée',         description: 'Donner un prénom à l\'IA',                     categorie: 'ia'),
    IaBadge(id: 'backtesting_1',     emoji: '🔭', titre: 'Explorateur',           description: 'Lancer le premier backtesting',                 categorie: 'ia'),
  ];

  static IaBadge? findById(String id) {
    try {
      return tous.firstWhere((b) => b.id == id);
    } catch (_) {
      return null;
    }
  }
}

// ─── Service principal ───────────────────────────────────────────────────────
class IaBadgesService extends ChangeNotifier {
  static IaBadgesService? _instance;
  static IaBadgesService get instance {
    _instance ??= IaBadgesService._();
    return _instance!;
  }
  IaBadgesService._();

  static const _key = 'ia_badges_v1';

  // Map id → date de déblocage
  final Map<String, DateTime> _debloques = {};

  // Callback pour afficher la bulle de félicitations
  Function(IaBadge)? onNouveauBadge;

  List<IaBadge> get tousLesBadges {
    return IaBadgesCatalogue.tous.map((b) {
      final date = _debloques[b.id];
      return date != null ? b.avecDate(date) : b;
    }).toList();
  }

  List<IaBadge> get badgesDebloques =>
      tousLesBadges.where((b) => b.estDebloque).toList()
        ..sort((a, b) => b.debloqueLe!.compareTo(a.debloqueLe!));

  List<IaBadge> get badgesVerrouilles =>
      tousLesBadges.where((b) => !b.estDebloque).toList();

  int get nbDebloques => _debloques.length;

  // ── Init ──────────────────────────────────────────────────────────────────
  static Future<void> init() async {
    final svc = instance;
    final sp  = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        map.forEach((id, dateStr) {
          final date = DateTime.tryParse(dateStr as String? ?? '');
          if (date != null) svc._debloques[id] = date;
        });
      } catch (_) {}
    }
  }

  // ── Débloquer un badge ────────────────────────────────────────────────────
  Future<bool> debloquer(String id) async {
    if (_debloques.containsKey(id)) return false; // déjà débloqué
    final badge = IaBadgesCatalogue.findById(id);
    if (badge == null) return false;

    _debloques[id] = DateTime.now();
    await _sauvegarder();
    notifyListeners();

    // Déclencher le callback pour la bulle
    onNouveauBadge?.call(badge.avecDate(_debloques[id]!));
    return true;
  }

  // ── Vérifier les badges automatiquement ──────────────────────────────────
  Future<void> verifierTout({
    required int nbCoursesAnalysees,
    required int nbAnalysesJournees,
    required double tauxReussite,
    required int nbParisTotal,
    required int nbParisGagnes,
    required double gainsNets,
    required int serieGagnante,
    required int seriePerdante,
    required bool aGagneQuinte,
    required bool aGagneOutsider,
    required int ageIaEnJours,
    required bool prenomPersonnalise,
    required bool backtestingLance,
  }) async {
    // ── Analyse ──────────────────────────────────────────────────────────────
    if (nbAnalysesJournees >= 1)   await debloquer('premiere_analyse');
    if (nbAnalysesJournees >= 10)  await debloquer('analyse_10');
    if (nbAnalysesJournees >= 50)  await debloquer('analyse_50');
    if (nbAnalysesJournees >= 100) await debloquer('analyse_100');
    if (nbCoursesAnalysees >= 100) await debloquer('courses_100');
    if (nbCoursesAnalysees >= 300) await debloquer('courses_300');
    if (tauxReussite >= 60)        await debloquer('taux_60');
    if (tauxReussite >= 75)        await debloquer('taux_75');

    // ── Paris ─────────────────────────────────────────────────────────────────
    if (nbParisTotal >= 1)         await debloquer('premier_pari');
    if (nbParisGagnes >= 1)        await debloquer('premiere_victoire');
    if (aGagneQuinte)              await debloquer('premier_quinte');
    if (nbParisTotal >= 10)        await debloquer('paris_10');
    if (nbParisTotal >= 50)        await debloquer('paris_50');
    if (gainsNets >= 100)          await debloquer('gain_100');
    if (gainsNets >= 500)          await debloquer('gain_500');
    if (aGagneOutsider)            await debloquer('outlier');

    // ── Séries ────────────────────────────────────────────────────────────────
    if (serieGagnante >= 3)        await debloquer('serie_3');
    if (serieGagnante >= 5)        await debloquer('serie_5');
    if (serieGagnante >= 10)       await debloquer('serie_10');
    if (seriePerdante >= 3 && nbParisGagnes > 0) await debloquer('rebond');

    // ── IA ────────────────────────────────────────────────────────────────────
    if (ageIaEnJours >= 30)        await debloquer('ia_1mois');
    if (ageIaEnJours >= 180)       await debloquer('ia_6mois');
    if (ageIaEnJours >= 365)       await debloquer('ia_1an');
    if (prenomPersonnalise)        await debloquer('ia_prenom');
    if (backtestingLance)          await debloquer('backtesting_1');
  }

  Future<void> _sauvegarder() async {
    final sp = await SharedPreferences.getInstance();
    final map = _debloques.map((k, v) => MapEntry(k, v.toIso8601String()));
    await sp.setString(_key, jsonEncode(map));
  }

  static const List<String> keysBackup = [_key];
}
