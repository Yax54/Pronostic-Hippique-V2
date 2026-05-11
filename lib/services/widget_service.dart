// ═══════════════════════════════════════════════════════════════════
//  WIDGET SERVICE — Pronostic Hippique v2.0 (Lot 4)
//
//  NOUVEAUTÉS v2.0 :
//   ★ Enrichi avec les données IA complètes :
//      score IA, tendance, ELO, type de pari conseillé
//   ★ Mise à jour auto depuis DataRefreshService (appelé après chaque refresh)
//   ★ Méthode updateFromReunions() directement depuis les ZtReunion
//      → pas besoin de BetOpportunity (découplé de best_bet_engine)
//   ★ Top 3 courses du jour (pas seulement la première)
//   ★ Widget "vide" si aucune course à venir aujourd'hui
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/zt_models.dart';
import 'ia_memory_service.dart';
import 'ia_personality_service.dart'; // ★ v9.86
import 'ia_badges_service.dart';      // ★ v9.86
import 'elo_service.dart';
import 'alert_service.dart';          // ★ v10.24 : coursesConseilIA + tendanceForme

class WidgetService {
  // ── Singleton ─────────────────────────────────────────────────────
  static final WidgetService _instance = WidgetService._();
  static WidgetService get instance => _instance;
  WidgetService._();

  static const _channel = MethodChannel('com.racepredictor.predict/widget');

  // Clés SharedPreferences — préfixe 'rp_' pour le widget natif Android
  // ★ Fix widget : clés alignées avec RacePredictorWidget.kt (Kotlin)
  // IMPORTANT : ces clés DOIVENT correspondre exactement aux KEY_* dans RacePredictorWidget.kt
  static const _kCourse     = 'widget_course_name';
  static const _kHorse      = 'widget_horse_name';
  static const _kHorseNum   = 'widget_horse_num';
  static const _kConfiance  = 'widget_confiance';
  static const _kGain       = 'widget_gain';
  static const _kHippodrome = 'widget_hippodrome';
  static const _kHeure      = 'widget_heure';
  static const _kNbCourses  = 'widget_nb_courses';
  static const _kUpdatedAt  = 'widget_updated_at';
  // ★ v2.0 : nouveaux champs (lus par Kotlin si ajoutés aux KEY_*)
  static const _kScoreIA    = 'widget_score_ia';
  static const _kTypePari   = 'widget_type_pari';
  static const _kTendance   = 'widget_tendance';
  static const _kEloRating  = 'widget_elo';
  static const _kCourse2    = 'widget_course2_name';
  static const _kHorse2     = 'widget_horse2_name';
  static const _kHeure2     = 'widget_heure2';
  static const _kConfiance2 = 'widget_confiance2';
  // ★ v9.86 : badge IA et niveau
  static const _kIaBadges   = 'widget_ia_badges';
  static const _kIaNiveau   = 'widget_ia_niveau';
  static const _kIaName     = 'widget_ia_name';
  static const _kCourse3     = 'widget_course3_name';
  static const _kHorse3      = 'widget_horse3_name';
  static const _kHeure3      = 'widget_heure3';
  static const _kConfiance3  = 'widget_confiance3';
  // ★ v10.24 : compteur Conseils IA + score de forme top cheval
  static const _kNbCriteres  = 'widget_nb_criteres';
  static const _kForme       = 'widget_forme';

  // ── Mise à jour depuis les réunions ZoneTurf ★ v2.0 ─────────────
  /// Appelé automatiquement par DataRefreshService après chaque refresh.
  /// Sélectionne la meilleure course à venir et l'envoie au widget natif.
  Future<void> updateFromReunions(List<ZtReunion> reunions) async {
    if (reunions.isEmpty) {
      await _writeEmpty();
      return;
    }

    final now = DateTime.now();

    // Construire la liste de toutes les courses avec leurs scores IA
    final List<_CourseWidget> toutes = [];

    for (final reunion in reunions) {
      for (final course in reunion.courses) {
        if (course.partants.isEmpty) continue;
        final sorted = course.partantsParRangIA;
        if (sorted.isEmpty) continue;

        final top        = sorted.first;
        final diffMin    = course.heureDateTime.difference(now).inMinutes;
        final estAVenir  = diffMin > -5; // inclure courses dans la prochaine heure

        if (!estAVenir) continue; // ignorer les courses passées

        // Score composite : confiance IA (65%) + potentiel gain (35%)
        final cote = top.coteDecimale;
        final scoreGain = cote > 0 && cote < 99
            ? (cote.clamp(1.1, 15.0) / 15.0 * 100).clamp(0.0, 100.0)
            : (100.0 - top.scoreIA).clamp(20.0, 80.0);
        final composite = top.scoreIA * 0.65 + scoreGain * 0.35;

        // Type de pari conseillé
        final seuils    = IaMemoryService.instance.seuilsConfiance;
        final score2nd  = sorted.length >= 2 ? sorted[1].scoreIA : 0.0;
        final ecart12   = (top.scoreIA - score2nd).abs();
        final estEquil  = ecart12 <= 15 && top.scoreIA >= 60 && score2nd >= 50;
        final String typePari;
        if (course.isQuinte) {
          typePari = 'Quinté+';
        } else if (course.isQuarte) {
          typePari = 'Quarté+';
        } else if (estEquil && top.scoreIA >= seuils.seuilCoupleGagnant) {
          typePari = 'Couplé Gagnant';
        } else if (top.scoreIA >= seuils.seuilSimpleGagnant && cote <= 8.0) {
          typePari = 'Simple Gagnant';
        } else if (top.scoreIA >= seuils.seuilSimpleGagnant) {
          typePari = 'Gagnant+Placé';
        } else if (top.scoreIA >= seuils.seuilSimplePlace) {
          typePari = 'Simple Placé';
        } else {
          typePari = 'À surveiller';
        }

        // ★ v9.92 : ELO par discipline
        final elo = EloService.instance.getScore(top.nom,
            discipline: course.type);

        // Gain estimé pour 10€
        final gainEstime = cote > 0 && cote < 99 ? cote * 10.0 - 10.0 : 0.0;

        toutes.add(_CourseWidget(
          courseName:  course.nom.isNotEmpty ? course.nom : 'Course ${course.numCourse}',
          horseName:   top.nom,
          horseNum:    top.numero,
          hippodrome:  reunion.lieu,
          heure:       course.heure,
          confiance:   course.confianceIA,
          scoreIA:     top.scoreIA,
          typePari:    typePari,
          tendance:    top.tendanceLabel,
          eloRating:   elo.nbCourses > 0 ? elo.rating : 0,
          gainEstime:  gainEstime,
          composite:   composite,
          diffMin:     diffMin,
        ));
      }
    }

    if (toutes.isEmpty) {
      await _writeEmpty();
      return;
    }

    // Trier par score composite décroissant
    toutes.sort((a, b) => b.composite.compareTo(a.composite));

    final top1 = toutes.first;
    final top2 = toutes.length >= 2 ? toutes[1] : null;
    final top3 = toutes.length >= 3 ? toutes[2] : null;

    final gainStr = top1.gainEstime > 0
        ? '~${top1.gainEstime.toStringAsFixed(0)} €'
        : '--';
    final confianceStr = '${top1.confiance.round()}%';

    final data = <String, String>{
      _kCourse:     top1.courseName,
      _kHorse:      top1.horseName,
      _kHorseNum:   top1.horseNum,
      _kConfiance:  confianceStr,
      _kGain:       gainStr,
      _kHippodrome: top1.hippodrome,
      _kHeure:      top1.heure,
      _kNbCourses:  toutes.length.toString(),
      _kUpdatedAt:  DateTime.now().millisecondsSinceEpoch.toString(),
      // ★ v2.0
      _kScoreIA:    top1.scoreIA.round().toString(),
      _kTypePari:   top1.typePari,
      _kTendance:   top1.tendance,
      _kEloRating:  top1.eloRating > 0 ? top1.eloRating.round().toString() : '--',
      // ★ v9.86 : badge IA et niveau
      _kIaBadges: () {
        final nb = IaBadgesService.instance.badgesDebloques.length;
        return nb > 0 ? '$nb badge${nb > 1 ? "s" : ""}' : '';
      }(),
      _kIaNiveau: IaPersonalityService.instance.niveau.label,
      _kIaName:   IaPersonalityService.instance.prenom,
      // Top 2
      if (top2 != null) ...{
        _kCourse2:    top2.courseName,
        _kHorse2:     top2.horseName,
        _kHeure2:     top2.heure,
        _kConfiance2: '${top2.confiance.round()}%',
      },
      // Top 3
      if (top3 != null) ...{
        _kCourse3:    top3.courseName,
        _kHorse3:     top3.horseName,
        _kHeure3:     top3.heure,
        _kConfiance3: '${top3.confiance.round()}%',
      },
      // ★ v10.24 : compteur Conseils IA + forme du top cheval
      ..._buildConseilIAData(toutes.first),
    };

    await _writeToPrefs(data);
    await _notifyNativeWidget(data);

    debugPrint('[WidgetService] ✅ Widget mis à jour : ${top1.horseName} '
        '— ${top1.heure} à ${top1.hippodrome} '
        '— confiance ${confianceStr} — ${toutes.length} courses');
  }

  // ★ v10.24 — Construit les données Conseil IA pour le widget
  // Récupère le nombre de courses dans les critères + forme du top cheval
  Map<String, String> _buildConseilIAData(_CourseWidget topCourse) {
    try {
      final courses = AlertService.instance.coursesConseilIA;
      final nbCriteres = courses.length;

      // Forme du cheval top-1 : récupérer via les réunions du DataRefreshService
      // La forme est encodée dans tendance (label) du top cheval
      // On utilise le score composite du top pour déterminer la tendance IA globale
      String formeStr = '';
      if (courses.isNotEmpty) {
        // Prioriser la forme du cheval en tête des courses Conseil IA
        final topCourseIA = courses.first;
        final partants = topCourseIA.course.partantsParRangIA;
        if (partants.isNotEmpty) {
          final topPartant = partants.first;
          switch (topPartant.tendanceForme) {
            case TendanceForme.hausse:      formeStr = '📈';
            case TendanceForme.baisse:      formeStr = '📉';
            case TendanceForme.stable:      formeStr = '➡️';
            case TendanceForme.insuffisant: formeStr = '';
          }
        }
      } else {
        // Fallback : forme du top-1 global basée sur sa tendance IA
        // On utilise topCourse.tendance (label) comme proxy
        if (topCourse.tendance.contains('hausse') || topCourse.tendance.contains('montée')) {
          formeStr = '📈';
        } else if (topCourse.tendance.contains('baisse') || topCourse.tendance.contains('chute')) {
          formeStr = '📉';
        } else if (topCourse.tendance.contains('stable')) {
          formeStr = '➡️';
        }
      }

      return {
        _kNbCriteres: nbCriteres.toString(),
        if (formeStr.isNotEmpty) _kForme: formeStr,
      };
    } catch (e) {
      return {_kNbCriteres: '0'};
    }
  }

  /// Met à jour le widget depuis une liste de BetOpportunity
  /// (rétrocompatibilité avec l'ancienne API)
  static Future<void> updateFromOpportunities(
    List<dynamic> opportunities,
  ) async {
    // Déléguer à l'instance singleton
    // Note : cette méthode est conservée pour rétrocompatibilité
    // mais ne fait rien si les opportunités ne sont pas des _BetOpp
    if (opportunities.isEmpty) {
      await _instance._writeEmpty();
      return;
    }
    debugPrint('[WidgetService] updateFromOpportunities appelé (legacy)');
  }

  // ── Écriture SharedPreferences ────────────────────────────────────
  Future<void> _writeToPrefs(Map<String, String> data) async {
    // ★ Fix widget : on passe par le MethodChannel updateWidget
    // qui écrit dans "RacePredictorWidgetData" (le bon fichier SharedPreferences
    // lu par RacePredictorWidget.kt). Ne pas utiliser SharedPreferences.getInstance()
    // qui écrit dans un fichier différent inaccessible au widget Android.
    // L'écriture réelle se fait dans _notifyNativeWidget via le canal.
    debugPrint('[WidgetService] 📝 Données prêtes pour le widget natif');
  }

  // ── Notification widget natif Android ────────────────────────────
  Future<void> _notifyNativeWidget(Map<String, String> data) async {
    try {
      await _channel.invokeMethod('updateWidget', data);
    } catch (e) {
      // Normal si le canal n'est pas enregistré (mode debug, iOS)
    }
  }

  // ── Widget vide ───────────────────────────────────────────────────
  Future<void> _writeEmpty() async {
    final data = <String, String>{
      _kCourse:    'Aucune course disponible',
      _kHorse:     '—',
      _kHorseNum:  '?',
      _kConfiance: '--',
      _kGain:      '--',
      _kHippodrome:'—',
      _kHeure:     '--:--',
      _kNbCourses: '0',
      _kUpdatedAt: DateTime.now().millisecondsSinceEpoch.toString(),
      _kScoreIA:   '--',
      _kTypePari:  '—',
      _kTendance:  '—',
      _kEloRating: '--',
    };
    await _writeToPrefs(data);
    await _notifyNativeWidget(data);
  }

  // ── Lire les données actuelles du widget ──────────────────────────
  /// Retourne les données stockées dans SharedPreferences pour affichage
  /// dans l'écran WidgetSetupScreen.
  Future<Map<String, String>> lireDonneesActuelles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'course':    prefs.getString(_kCourse)    ?? '—',
        'cheval':    prefs.getString(_kHorse)     ?? '—',
        'numero':    prefs.getString(_kHorseNum)  ?? '?',
        'confiance': prefs.getString(_kConfiance) ?? '--',
        'gain':      prefs.getString(_kGain)      ?? '--',
        'hippodrome':prefs.getString(_kHippodrome)?? '—',
        'heure':     prefs.getString(_kHeure)     ?? '--:--',
        'nbCourses': prefs.getString(_kNbCourses) ?? '0',
        'scoreIA':   prefs.getString(_kScoreIA)   ?? '--',
        'typePari':  prefs.getString(_kTypePari)  ?? '—',
        'tendance':  prefs.getString(_kTendance)  ?? '—',
        'elo':       prefs.getString(_kEloRating) ?? '--',
        'updatedAt': prefs.getString(_kUpdatedAt) ?? '',
        // Top 2
        'course2':    prefs.getString(_kCourse2)    ?? '',
        'cheval2':    prefs.getString(_kHorse2)     ?? '',
        'heure2':     prefs.getString(_kHeure2)     ?? '',
        'confiance2': prefs.getString(_kConfiance2) ?? '',
        // Top 3
        'course3':    prefs.getString(_kCourse3)    ?? '',
        'cheval3':    prefs.getString(_kHorse3)     ?? '',
        'heure3':     prefs.getString(_kHeure3)     ?? '',
        'confiance3': prefs.getString(_kConfiance3) ?? '',
        // ★ v10.24 : Conseil IA
        'nbCriteres': prefs.getString(_kNbCriteres) ?? '0',
        'forme':      prefs.getString(_kForme)      ?? '',
      };
    } catch (e) {
      return {};
    }
  }

  /// Timestamp de la dernière mise à jour (null si jamais mis à jour)
  Future<DateTime?> derniereMiseAJour() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getString(_kUpdatedAt);
      if (ts == null || ts.isEmpty) return null;
      final ms = int.tryParse(ts);
      if (ms == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) { return null; }
  }
}

// ─── Données d'une course pour le widget ─────────────────────────────────────
class _CourseWidget {
  final String courseName;
  final String horseName;
  final String horseNum;
  final String hippodrome;
  final String heure;
  final double confiance;
  final double scoreIA;
  final String typePari;
  final String tendance;
  final double eloRating;
  final double gainEstime;
  final double composite;
  final int    diffMin;

  const _CourseWidget({
    required this.courseName,
    required this.horseName,
    required this.horseNum,
    required this.hippodrome,
    required this.heure,
    required this.confiance,
    required this.scoreIA,
    required this.typePari,
    required this.tendance,
    required this.eloRating,
    required this.gainEstime,
    required this.composite,
    required this.diffMin,
  });
}
