// ═══════════════════════════════════════════════════════════════════
//  DATA REFRESH SERVICE — Pronostic Hippique v9.0 (Lot 2)
//
//  NOUVEAUTÉS v9.0 :
//   ★ Détection automatique des non-partants
//      Compare la liste des partants entre 2 refreshs.
//      Si un cheval disparaît → notification immédiate + recalcul IA auto.
//      Stocke l'état précédent en mémoire (_partantsParCourse).
//
//   ★ compute() isolate pour les calculs IA lourds
//      _enregistrerPronosticsBatch tourne dans un isolate Flutter séparé
//      via compute() → le thread UI ne freeze plus pendant le calcul.
//      Les données sont sérialisées en JSON pour passer l'isolate boundary.
//
//   ★ Toutes les signatures publiques V2 conservées (compatibilité totale)
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'zone_turf_service.dart';
import 'ia_memory_service.dart';
import 'ia_personality_service.dart'; // ★ v9.85
import 'ia_memory_models.dart';
import 'ia_pronostic_engine.dart';
import 'elo_service.dart';
import 'alert_service.dart';
import 'cote_tracker_service.dart';   // ★ v9.92 : critère R mouvement de cote
import '../widgets/ia/ia_bubble_widget.dart'; // ★ v9.93 : bulle non-partant
import 'widget_service.dart'; // ★ Lot 4
import '../models/zt_models.dart';

// ─── Payload pour compute() isolate ─────────────────────────────────────────
// Tout ce qui entre dans un isolate doit être sérialisable (pas de méthodes).
class _BatchPayload {
  final List<Map<String, dynamic>> reunionsJson;
  final Map<String, dynamic> poidsJson;
  final Map<String, dynamic> eloJson;
  final Map<String, dynamic> seuilsJson;
  _BatchPayload({
    required this.reunionsJson,
    required this.poidsJson,
    required this.eloJson,
    required this.seuilsJson,
  });
}

// ─── Résultat de l'isolate ────────────────────────────────────────────────────
class _BatchResult {
  final List<Map<String, dynamic>> nouveaux;
  _BatchResult(this.nouveaux);
}

// ─── Fonction top-level exécutée dans l'isolate ──────────────────────────────
// ★ DOIT être une fonction top-level (pas une méthode de classe) pour compute()
_BatchResult _calculerPronosticsBatch(_BatchPayload payload) {
  // Reconstruire les poids depuis JSON
  final poids = IaPoidsAdaptatifs.fromJson(payload.poidsJson);

  // Reconstruire les seuils depuis JSON (toujours non-null grâce au fallback)
  late final SeuilsConfianceAdaptatifs seuils;
  try {
    seuils = SeuilsConfianceAdaptatifs.fromJson(payload.seuilsJson);
  } catch (_) {
    seuils = SeuilsConfianceAdaptatifs();
  }

  final List<Map<String, dynamic>> nouveaux = [];

  for (final reunionJson in payload.reunionsJson) {
    final reunion = ZtReunion.fromJson(reunionJson);

    final numRMatch = RegExp(r'R(\d+)').firstMatch(reunion.code);
    final numR = numRMatch != null
        ? int.tryParse(numRMatch.group(1) ?? '1') ?? 1
        : 1;

    for (final course in reunion.courses) {
      if (course.partants.isEmpty) continue;

      final dep = course.heureDateTime;
      final dj = dep.day.toString().padLeft(2, '0');
      final dm = dep.month.toString().padLeft(2, '0');
      final courseKey = 'R${numR}C${course.numCourse}_$dj$dm${dep.year}';

      // Calcul IA avec les poids passés (pas d'accès au singleton depuis l'isolate)
      final (partantsClasses, scoresCriteres) =
          IaPronosticEngine.analyserCourseAvecCriteres(
            course,
            poidsOverride: poids,
          );
      if (partantsClasses.isEmpty) continue;

      final confiance = course.confianceIA;

      // Déterminer le type de pari conseillé
      final scoreConf = partantsClasses.first.scoreIA;
      final score2nd  = partantsClasses.length >= 2 ? partantsClasses[1].scoreIA : 0.0;
      final ecart12   = (scoreConf - score2nd).abs();
      final estEquil  = ecart12 <= 15 && scoreConf >= 60 && score2nd >= 50;
      final coteTop   = partantsClasses.first.coteDecimale;

      final String typePariAuto;
      if (course.isQuinte) {
        typePariAuto = 'Quinté+';
      } else if (course.isQuarte) {
        typePariAuto = 'Quarté+';
      } else if (estEquil && scoreConf >= seuils.seuilCoupleGagnant) {
        typePariAuto = 'Couplé Gagnant';
      } else if (estEquil && scoreConf >= seuils.seuilCouplePlace) {
        typePariAuto = 'Couplé Placé';
      } else if (scoreConf >= seuils.seuilSimpleGagnant && coteTop <= 8.0) {
        typePariAuto = 'Simple Gagnant';
      } else if (scoreConf >= seuils.seuilSimpleGagnant) {
        typePariAuto = 'Gagnant+Placé';
      } else if (scoreConf >= seuils.seuilSimplePlace) {
        typePariAuto = 'Simple Placé';
      } else if (scoreConf >= seuils.seuilGagnantPlace) {
        typePariAuto = 'Gagnant+Placé';
      } else if (scoreConf >= seuils.seuilTierce) {
        typePariAuto = 'Tiercé';
      } else {
        typePariAuto = 'À surveiller';
      }

      // Sérialiser les scores critères
      final scoresJson = <String, dynamic>{};
      scoresCriteres.forEach((num, sc) => scoresJson[num] = sc.toJson());

      // Sérialiser les partants classés (score + rang seulement)
      final partantsJson = partantsClasses
          .map((p) => {'numero': p.numero, 'scoreIA': p.scoreIA, 'rang': p.rang})
          .toList();

      nouveaux.add({
        'courseKey':        courseKey,
        'courseJson':       course.toJson(),
        'partantsJson':     partantsJson,
        'scoresJson':       scoresJson,
        'confiance':        confiance,
        'typePariConseille': typePariAuto,
      });
    }
  }

  return _BatchResult(nouveaux);
}

// ─── Service principal ────────────────────────────────────────────────────────
class DataRefreshService extends ChangeNotifier {
  // ── Singleton ────────────────────────────────────────────────────
  static final DataRefreshService _instance = DataRefreshService._();
  static DataRefreshService get instance => _instance;
  DataRefreshService._();

  // ── État ─────────────────────────────────────────────────────────
  List<ZtReunion> _reunions = [];
  bool _loading = false;
  String? _lastError;
  DateTime? _lastRefresh;
  Timer? _autoTimer;

  // ★ v9.0 : État précédent des partants par courseKey pour détection non-partants
  // Clé : courseKey (ex: "R1C3"), Valeur : set des numéros connus
  final Map<String, Set<int>> _partantsParCourse = {};

  // ★ v9.0 : Notifications de non-partants déjà envoyées (anti-doublon)
  final Set<String> _nonPartantsNotifies = {};

  // ── Persistance ──────────────────────────────────────────────────
  static const String _prefsCachePrefix  = 'cache_reunions_';
  static const Duration _refreshInterval = Duration(minutes: 15);
  static const Duration _cacheLocalDuree = Duration(hours: 8);

  List<ZtReunion> get reunions    => _reunions;
  bool            get loading     => _loading;
  String?         get lastError   => _lastError;
  DateTime?       get lastRefresh => _lastRefresh;

  String get lastRefreshLabel {
    if (_lastRefresh == null) return 'Jamais';
    final diff = DateTime.now().difference(_lastRefresh!);
    if (diff.inSeconds < 60)  return 'À l\'instant';
    if (diff.inMinutes < 60)  return 'Il y a ${diff.inMinutes} min';
    return 'Il y a ${diff.inHours}h';
  }

  // ── Initialisation ────────────────────────────────────────────────
  static Future<void> init() async {
    await _instance._chargerCacheLocal();
    _instance._startAutoTimer();
    _instance._doRefresh().ignore();
    // ★ v9.85 : Synchroniser les stats IA au démarrage pour que la forme du
    // matin soit à jour avant même que l'utilisateur ouvre le Profil.
    _instance._syncIaStatsAuDemarrage().ignore();
    // ★ v9.94 Amél. 3 : Résumé hebdomadaire automatique le lundi matin
    _instance._verifierResumeHebdoLundi().ignore();
  }

  Future<void> _syncIaStatsAuDemarrage() async {
    try {
      final iaMem = IaMemoryService.instance;
      // S'assurer que la mémoire IA est chargée (init() est idempotent)
      await IaMemoryService.init();
      final stats = iaMem.calculerStats();
      IaPersonalityService.instance.mettreAJourStats(
        coursesAvecResultat:    stats.coursesAvecResultat,
        tauxReussite:           stats.coursesAvecResultat > 0
            ? stats.favoriTop3 / stats.coursesAvecResultat * 100
            : 0.0,
        meilleureSerieGagnante: 0, // calculé dans IaMemoryService si besoin
        pireSeriesPerdantes:    0,
      );
      if (kDebugMode) {
        debugPrint('[DataRefresh] ★ Stats IA synchronisées au démarrage : '
            '${stats.coursesAvecResultat} courses, '
            '${stats.favoriTop3} top3');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[DataRefresh] ⚠️ Sync stats IA : $e');
    }
  }

  // ── ★ v9.94 Amél. 3 : Résumé hebdomadaire automatique le lundi matin ────────
  static const String _keyResumeHebdoDate = 'data_refresh_resume_hebdo_date';

  Future<void> _verifierResumeHebdoLundi() async {
    try {
      final now = DateTime.now();
      // Uniquement le lundi (weekday == 1)
      if (now.weekday != DateTime.monday) return;

      final prefs = await SharedPreferences.getInstance();
      final todayKey = '${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}';
      final dernierLundi = prefs.getString(_keyResumeHebdoDate) ?? '';

      // Déjà envoyé aujourd'hui
      if (dernierLundi == todayKey) return;

      // S'assurer que la mémoire IA est chargée
      await IaMemoryService.init();
      final hebdo = IaMemoryService.instance.calculerRapportHebdo();
      if (hebdo == null) return; // Pas assez de données

      final nbCourses   = hebdo['totalCourses']   as int;
      final tauxGagnant = hebdo['tauxGagnant']     as double;
      final tauxTop3    = hebdo['tauxTop3']        as double;
      final meilleureDisc = hebdo['meilleureDisc'] as String;
      final nbJours     = hebdo['nbJours']         as int;

      // Construire le message résumé
      final tauxStr  = tauxGagnant.toStringAsFixed(0);
      final top3Str  = tauxTop3.toStringAsFixed(0);
      final discStr  = meilleureDisc.isNotEmpty ? '\nMeilleure discipline : $meilleureDisc' : '';
      final message  =
        '📊 Bilan semaine — $nbJours jour${nbJours > 1 ? "s" : ""} analysé${nbJours > 1 ? "s" : ""}\n'
        '$nbCourses courses • $tauxStr% gagnant • $top3Str% top3$discStr';

      // Afficher la bulle résumé (type 'analyse' — bypassse le cooldown)
      IaBubbleOverlayState.afficher(message, type: 'analyse');

      // Marquer comme envoyé ce lundi
      await prefs.setString(_keyResumeHebdoDate, todayKey);

      if (kDebugMode) debugPrint('[DataRefresh] ★ Résumé hebdo lundi envoyé : $message');
    } catch (e) {
      if (kDebugMode) debugPrint('[DataRefresh] ⚠️ Résumé hebdo : $e');
    }
  }

  void _startAutoTimer() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(_refreshInterval, (_) {
      _doRefresh(force: true);
    });
  }

  // ── Cache local ───────────────────────────────────────────────────
  String _cleCachePourDate(String dateStr) => '$_prefsCachePrefix$dateStr';

  Future<void> _chargerCacheLocal() async {
    try {
      final prefs    = await SharedPreferences.getInstance();
      final todayStr = _todayDateStr();
      final cle      = _cleCachePourDate(todayStr);
      final jsonStr  = prefs.getString(cle);
      if (jsonStr == null || jsonStr.isEmpty) return;

      final timestampMs = prefs.getInt('${cle}_ts');
      if (timestampMs != null) {
        final age = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(timestampMs));
        if (age > _cacheLocalDuree) return;
      }

      final List<dynamic> reunionsJson = jsonDecode(jsonStr) as List<dynamic>;
      final reunions = reunionsJson
          .map((r) => ZtReunion.fromJson(r as Map<String, dynamic>))
          .toList();

      if (reunions.isNotEmpty) {
        _reunions     = reunions;
        _lastRefresh  = timestampMs != null
            ? DateTime.fromMillisecondsSinceEpoch(timestampMs)
            : null;
        // Initialiser l'état des partants depuis le cache
        _initialiserEtatPartants(reunions);
        notifyListeners();
        debugPrint('[DataRefresh] ✅ Cache local restauré : '
            '${reunions.length} réunions');
      }
    } catch (e) {
      debugPrint('[DataRefresh] ⚠️ Erreur cache local : $e');
    }
  }

  Future<void> _sauvegarderCacheLocal(
      List<ZtReunion> reunions, String dateStr) async {
    try {
      final prefs  = await SharedPreferences.getInstance();
      final cle    = _cleCachePourDate(dateStr);
      await prefs.setString(cle, jsonEncode(reunions.map((r) => r.toJson()).toList()));
      await prefs.setInt('${cle}_ts', DateTime.now().millisecondsSinceEpoch);
      await _nettoyerAnciensCache(prefs, dateStr);
    } catch (e) {
      debugPrint('[DataRefresh] ⚠️ Erreur sauvegarde cache : $e');
    }
  }

  Future<void> _nettoyerAnciensCache(
      SharedPreferences prefs, String dateActuelle) async {
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefsCachePrefix));
    for (final key in keys) {
      final dateKey = key
          .replaceFirst(_prefsCachePrefix, '')
          .replaceAll('_ts', '');
      if (dateKey.length == 8 && dateKey != dateActuelle) {
        await prefs.remove(key);
        await prefs.remove('${key}_ts');
      }
    }
  }

  String _signaturedReunions(List<ZtReunion> reunions) {
    final buf = StringBuffer();
    for (final r in reunions) {
      buf.write('${r.code}:${r.courses.length}');
      for (final c in r.courses) {
        final isTerminee = DateTime.now().difference(c.heureDateTime).inMinutes > 90;
        // ★ Fix : inclure le nombre de partants dans la signature
        // Sans ça, quand les cotes apparaissent (partants 0→13), la signature
        // ne change pas → _enregistrerPronosticsAuto non appelé → pronostics jamais créés
        buf.write('|${c.numCourse}${c.heure}${isTerminee ? "T" : "A"}${c.partants.length}');
      }
    }
    return buf.toString();
  }

  // ── Initialiser / mettre à jour l'état des partants ───────────────
  // ★ v9.0 : Appelé à chaque chargement de données pour préparer la
  // comparaison lors du prochain refresh.
  void _initialiserEtatPartants(List<ZtReunion> reunions) {
    for (final reunion in reunions) {
      final numRMatch = RegExp(r'R(\d+)').firstMatch(reunion.code);
      final numR = numRMatch != null
          ? int.tryParse(numRMatch.group(1) ?? '1') ?? 1 : 1;
      for (final course in reunion.courses) {
        final dep = course.heureDateTime;
        final dj  = dep.day.toString().padLeft(2, '0');
        final dm  = dep.month.toString().padLeft(2, '0');
        final key = 'R${numR}C${course.numCourse}_$dj$dm${dep.year}';
        final nums = course.partants
            .where((p) => !p.estHorsCourse)
            .map((p) => int.tryParse(p.numero) ?? 0)
            .where((n) => n > 0)
            .toSet();
        _partantsParCourse[key] = nums;
      }
    }
  }

  // ── Détection automatique des non-partants ★ v9.0 ────────────────
  // Compare l'état précédent des partants avec le nouvel état.
  // Pour chaque cheval qui disparaît (ou passe en statut hors course) :
  //   1. Log de détection
  //   2. Notification push via AlertService
  //   3. Recalcul IA via reAnalyserCourse()
  Future<void> _detecterNonPartants(List<ZtReunion> nouvellesReunions) async {
    for (final reunion in nouvellesReunions) {
      final numRMatch = RegExp(r'R(\d+)').firstMatch(reunion.code);
      final numR = numRMatch != null
          ? int.tryParse(numRMatch.group(1) ?? '1') ?? 1 : 1;

      for (final course in reunion.courses) {
        // Ne détecter que pour les courses pas encore terminées
        final now = DateTime.now();
        final diffMin = course.heureDateTime.difference(now).inMinutes;
        if (diffMin < -30 || diffMin > 240) continue; // hors fenêtre utile

        final dep = course.heureDateTime;
        final dj  = dep.day.toString().padLeft(2, '0');
        final dm  = dep.month.toString().padLeft(2, '0');
        final courseKey = 'R${numR}C${course.numCourse}_$dj$dm${dep.year}';

        // Partants actifs dans le NOUVEL état
        final numsActuels = course.partants
            .where((p) => !p.estHorsCourse)
            .map((p) => int.tryParse(p.numero) ?? 0)
            .where((n) => n > 0)
            .toSet();

        // Partants connus dans l'ANCIEN état
        final numsAnciens = _partantsParCourse[courseKey];

        // Première fois qu'on voit cette course → juste mémoriser
        if (numsAnciens == null) {
          _partantsParCourse[courseKey] = numsActuels;
          continue;
        }

        // Chercher les chevaux qui ont disparu
        final disparus = numsAnciens.difference(numsActuels).toList()..sort();

        if (disparus.isEmpty) {
          _partantsParCourse[courseKey] = numsActuels;
          continue;
        }

        // Filtrer ceux dont on a déjà notifié
        final vraimentsNouveaux = disparus
            .where((n) => !_nonPartantsNotifies
                .contains('${courseKey}_$n'))
            .toList();

        if (vraimentsNouveaux.isEmpty) {
          _partantsParCourse[courseKey] = numsActuels;
          continue;
        }

        // Marquer comme notifiés
        for (final n in vraimentsNouveaux) {
          _nonPartantsNotifies.add('${courseKey}_$n');
        }

        // Mettre à jour l'état
        _partantsParCourse[courseKey] = numsActuels;

        debugPrint('[DataRefresh] ⚠️ Non-partants détectés dans $courseKey : '
            '${vraimentsNouveaux.map((n) => "N°$n").join(", ")}');

        // ── Notification via AlertService ─────────────────────────────
        // Construire le message de notification
        final numsStr    = vraimentsNouveaux.map((n) => 'N°$n').join(', ');
        final alertId    = '${courseKey}_np_${vraimentsNouveaux.join("_")}';
        final nomCourse  = course.nom.isNotEmpty ? course.nom : 'Course ${course.numCourse}';

        // On utilise le type rappelMise pour signaler l'alerte non-partant
        AlertService.instance.ajouterAlertNonPartant(
          alertId:    alertId,
          courseKey:  courseKey,
          nomCourse:  nomCourse,
          hippodrome: reunion.lieu,
          numsStr:    numsStr,
        );

        // ★ v9.94 Amél. 1+2 : Bulle nonPartant avec scope AlertConfig + ligne pronostic
        // Amél. 2 : respecter le scope (favoris/suivies/toutes) comme les notifications push
        if (AlertService.instance.coursePasseFiltrePublic(courseKey)) {
          IaBubbleOverlayState.afficher(
            '⚠️ $numsStr retiré(s) de $nomCourse (${reunion.lieu})\n'
            '→ Nouveau pronostic IA disponible.',  // Amél. 1 : ligne pronostic
            type: 'nonPartant',
          );
        }

        // ── Recalcul IA sans les chevaux retirés ──────────────────────
        await reAnalyserCourse(
          courseKey:  courseKey,
          course:     course,
          retraits:   vraimentsNouveaux,
        );
      }
    }
  }

  // ── Rafraîchissement principal ────────────────────────────────────
  Future<void> _doRefresh({bool force = false}) async {
    if (_loading) return;
    _loading   = true;
    _lastError = null;
    notifyListeners();

    try {
      debugPrint('[DataRefresh] Chargement programme réseau...');
      final todayStr = _todayDateStr();
      final reunions = await ZoneTurfService.chargerProgramme(
          forceRefresh: force);

      if (reunions.isEmpty && _reunions.isNotEmpty) {
        debugPrint('[DataRefresh] ⚠️ API retourne 0 réunion — cache conservé');
      } else {
        final ancienneSignature = _signaturedReunions(_reunions);
        final nouvelleSignature = _signaturedReunions(reunions);
        final aChange = ancienneSignature != nouvelleSignature;

        if (aChange || _reunions.isEmpty) {
          // ★ v9.0 : Détecter les non-partants AVANT de mettre à jour _reunions
          if (_reunions.isNotEmpty && aChange) {
            await _detecterNonPartants(reunions);
          }
          _reunions = reunions;
          // ★ v9.0 : Mettre à jour l'état des partants après chaque refresh
          _initialiserEtatPartants(reunions);
          debugPrint('[DataRefresh] ✅ ${reunions.length} réunions chargées');
        }
      }

      _lastRefresh = DateTime.now();
      _lastError   = null;

      if (reunions.isNotEmpty) {
        _sauvegarderCacheLocal(reunions, todayStr).ignore();
      }

      // ★ Fix : toujours appeler _enregistrerPronosticsAuto même si la signature
      // n'a pas changé — la méthode ignore les courses déjà en mémoire (getPronostic != null)
      // et crée les pronostics manquants (courses dont les partants viennent d'apparaître)
      _enregistrerPronosticsAuto(reunions.isNotEmpty ? reunions : _reunions);

      // ★ Lot 4 : Mettre à jour le widget Android avec les meilleures courses
      WidgetService.instance.updateFromReunions(reunions).ignore();

      // ★ v9.92 : Démarrer/mettre à jour le tracker de mouvements de cotes
      // ★ v9.99 : charger les mouvements persistés avant de démarrer
      CoteTrackerService.instance.chargerMouvementsPersistes();
      CoteTrackerService.instance.mettreAJourReunions(
          reunions.isNotEmpty ? reunions : _reunions);

      _recupererResultatsAuto();

      // ★ v10.23 : Recalculer les courses Conseil IA + notifier les nouvelles
      final reunionsPourConseils = reunions.isNotEmpty ? reunions : _reunions;
      AlertService.instance.recalculerCoursesConseilIA(reunionsPourConseils).ignore();
      AlertService.instance.verifierNouvellesCoursesConseilIA(reunionsPourConseils).ignore();

    } catch (e) {
      _lastError = e.toString();
      debugPrint('[DataRefresh] ❌ Erreur: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Rafraîchissement manuel
  Future<void> refresh() => _doRefresh(force: true);

  // ── Re-analyse après DQ/retrait ───────────────────────────────────
  Future<void> reAnalyserCourse({
    required String courseKey,
    required ZtCourse course,
    List<int> disqualifies = const [],
    List<int> retraits     = const [],
  }) async {
    try {
      final partantsActifs = course.partants
          .where((p) => !p.estHorsCourse)
          .toList();
      if (partantsActifs.isEmpty) return;

      final courseFiltre = ZtCourse(
        numCourse:   course.numCourse,
        anchor:      course.anchor,
        nom:         course.nom,
        heure:       course.heure,
        distance:    course.distance,
        prix:        course.prix,
        type:        course.type,
        piste:       course.piste,
        categorie:   course.categorie,
        isQuinte:    course.isQuinte,
        pronosticZt: course.pronosticZt,
        partants:    partantsActifs,
      )..dateStr = course.dateStr;

      final (partantsClasses, scoresCriteres) =
          IaPronosticEngine.analyserCourseAvecCriteres(courseFiltre);
      if (partantsClasses.isEmpty) return;

      final confiance = courseFiltre.confianceIA;

      final mouvements = <String>[];
      if (disqualifies.isNotEmpty) {
        mouvements.add('DQ: ${disqualifies.map((n) => "N°$n").join(", ")}');
      }
      if (retraits.isNotEmpty) {
        mouvements.add('Retrait: ${retraits.map((n) => "N°$n").join(", ")}');
      }
      final infoMvt = mouvements.join(' | ');

      await IaMemoryService.instance.invaliderEtRecalculer(
        courseKey:           courseKey,
        course:              courseFiltre,
        partantsClasses:     partantsClasses,
        scoresCriteres:      scoresCriteres,
        confiance:           confiance,
        raisonInvalidation:  infoMvt,
      );

      // Mettre à jour _reunions en mémoire
      for (int i = 0; i < _reunions.length; i++) {
        final r   = _reunions[i];
        final idx = r.courses.indexWhere(
            (c) => c.numCourse == course.numCourse);
        if (idx >= 0) {
          final newCourses = List<ZtCourse>.from(r.courses);
          newCourses[idx] = courseFiltre;
          _reunions[i] = ZtReunion(
            code: r.code, lieu: r.lieu,
            discipline: r.discipline, dateStr: r.dateStr,
            courses: newCourses,
          );
          break;
        }
      }

      debugPrint('[DataRefresh] ✅ Pronostic recalculé pour $courseKey'
          '${infoMvt.isNotEmpty ? " ($infoMvt)" : ""}');
      notifyListeners();
    } catch (e) {
      debugPrint('[DataRefresh] ❌ reAnalyserCourse erreur: $e');
    }
  }

  // ── Enregistrement batch IA ★ v9.0 : dans un isolate via compute() ─
  void _enregistrerPronosticsAuto(List<ZtReunion> reunions) {
    Future.microtask(() => _enregistrerPronosticsBatchIsolate(reunions));
  }

  Future<void> _enregistrerPronosticsBatchIsolate(
      List<ZtReunion> reunions) async {
    // Filtrer les courses sans pronostic existant
    final reunionsFiltrees = <ZtReunion>[];
    for (final reunion in reunions) {
      final numRMatch = RegExp(r'R(\d+)').firstMatch(reunion.code);
      final numR = numRMatch != null
          ? int.tryParse(numRMatch.group(1) ?? '1') ?? 1 : 1;

      final coursesFiltrees = <ZtCourse>[];
      for (final course in reunion.courses) {
        if (course.partants.isEmpty) continue;
        final dep = course.heureDateTime;
        final dj  = dep.day.toString().padLeft(2, '0');
        final dm  = dep.month.toString().padLeft(2, '0');
        final courseKey = 'R${numR}C${course.numCourse}_$dj$dm${dep.year}';
        // Ignorer si pronostic déjà en mémoire
        if (IaMemoryService.instance.getPronostic(courseKey) != null) continue;
        coursesFiltrees.add(course);
      }
      if (coursesFiltrees.isEmpty) continue;

      // Reconstruire une réunion avec seulement les courses à calculer
      reunionsFiltrees.add(ZtReunion(
        code: reunion.code, lieu: reunion.lieu,
        discipline: reunion.discipline, dateStr: reunion.dateStr,
        courses: coursesFiltrees,
      ));
    }

    if (reunionsFiltrees.isEmpty) return;

    try {
      // ★ Préparer le payload pour l'isolate
      final payload = _BatchPayload(
        reunionsJson: reunionsFiltrees
            .map((r) => r.toJson())
            .toList(),
        poidsJson:   IaMemoryService.instance.poids.toJson(),
        eloJson:     EloService.instance.exporterPourBackup(),
        seuilsJson:  IaMemoryService.instance.seuilsConfiance.toJson(),
      );

      // ★ Lancer dans un isolate Flutter (ne bloque pas l'UI)
      final result = await compute(_calculerPronosticsBatch, payload);

      if (result.nouveaux.isEmpty) return;

      // Reconstituer les objets depuis les JSON retournés
      final batch = <Map<String, dynamic>>[];
      for (final item in result.nouveaux) {
        try {
          final course = ZtCourse.fromJson(
              item['courseJson'] as Map<String, dynamic>);
          // Reconstituer ScoresCriteres depuis JSON
          final scoresRaw = item['scoresJson'] as Map<String, dynamic>;
          final scoresCriteres = scoresRaw.map(
            (k, v) => MapEntry(k,
                ScoresCriteres.fromJson(v as Map<String, dynamic>)));
          // Reconstituer les partants classés minimaux
          final partantsRaw =
              item['partantsJson'] as List<dynamic>;
          // On utilise les partants de la course originale enrichis des rangs
          final partantsClasses = course.partants.map((p) {
            final rankData = partantsRaw.firstWhere(
              (r) => r['numero'] == p.numero,
              orElse: () => {'scoreIA': 0.0, 'rang': 99},
            ) as Map<String, dynamic>;
            return p.copyWith(
              scoreIA: (rankData['scoreIA'] as num?)?.toDouble() ?? 0.0,
              rang:    (rankData['rang']    as int?)             ?? 99,
            );
          }).toList()
            ..sort((a, b) => a.rang.compareTo(b.rang));

          batch.add({
            'courseKey':          item['courseKey'],
            'course':             course,
            'partantsClasses':    partantsClasses,
            'scoresCriteres':     scoresCriteres,
            'confiance':          item['confiance'],
            'typePariConseille':  item['typePariConseille'],
          });
        } catch (e) {
          debugPrint('[DataRefresh] ⚠️ Reconstitution batch: $e');
        }
      }

      if (batch.isNotEmpty) {
        await IaMemoryService.instance.enregistrerPronosticsBatch(batch);
        debugPrint('[DataRefresh] 🧠 ${batch.length} pronostic(s) IA '
            'enregistrés (isolate)');
      }
    } catch (e) {
      // Fallback : calcul sur le thread principal si l'isolate échoue
      debugPrint('[DataRefresh] ⚠️ Isolate batch échoué, fallback: $e');
      await _enregistrerPronosticsBatchFallback(reunionsFiltrees);
    }
  }

  /// Fallback synchrone si compute() échoue
  Future<void> _enregistrerPronosticsBatchFallback(
      List<ZtReunion> reunions) async {
    final List<Map<String, dynamic>> nouveaux = [];

    for (final reunion in reunions) {
      final numRMatch = RegExp(r'R(\d+)').firstMatch(reunion.code);
      final numR = numRMatch != null
          ? int.tryParse(numRMatch.group(1) ?? '1') ?? 1 : 1;

      for (final course in reunion.courses) {
        if (course.partants.isEmpty) continue;
        final dep = course.heureDateTime;
        final dj  = dep.day.toString().padLeft(2, '0');
        final dm  = dep.month.toString().padLeft(2, '0');
        final courseKey = 'R${numR}C${course.numCourse}_$dj$dm${dep.year}';

        if (IaMemoryService.instance.getPronostic(courseKey) != null) continue;

        final (partantsClasses, scoresCriteres) =
            IaPronosticEngine.analyserCourseAvecCriteres(course);
        if (partantsClasses.isEmpty) continue;

        final confiance = course.confianceIA;
        final seuils    = IaMemoryService.instance.seuilsConfiance;
        final scoreConf = partantsClasses.first.scoreIA;
        final score2nd  = partantsClasses.length >= 2
            ? partantsClasses[1].scoreIA : 0.0;
        final ecart12   = (scoreConf - score2nd).abs();
        final estEquil  = ecart12 <= 15 && scoreConf >= 60 && score2nd >= 50;
        final coteTop   = partantsClasses.first.coteDecimale;

        final String typePari;
        if (course.isQuinte) {
          typePari = 'Quinté+';
        } else if (estEquil && scoreConf >= seuils.seuilCoupleGagnant) {
          typePari = 'Couplé Gagnant';
        } else if (estEquil && scoreConf >= seuils.seuilCouplePlace) {
          typePari = 'Couplé Placé';
        } else if (scoreConf >= seuils.seuilSimpleGagnant && coteTop <= 8.0) {
          typePari = 'Simple Gagnant';
        } else if (scoreConf >= seuils.seuilSimpleGagnant) {
          typePari = 'Gagnant+Placé';
        } else if (scoreConf >= seuils.seuilSimplePlace) {
          typePari = 'Simple Placé';
        } else if (scoreConf >= seuils.seuilGagnantPlace) {
          typePari = 'Gagnant+Placé';
        } else if (scoreConf >= seuils.seuilTierce) {
          typePari = 'Tiercé';
        } else {
          typePari = 'À surveiller';
        }

        nouveaux.add({
          'courseKey':         courseKey,
          'course':            course,
          'partantsClasses':   partantsClasses,
          'scoresCriteres':    scoresCriteres,
          'confiance':         confiance,
          'typePariConseille': typePari,
        });
      }
    }

    if (nouveaux.isNotEmpty) {
      await IaMemoryService.instance.enregistrerPronosticsBatch(nouveaux);
      debugPrint('[DataRefresh] 🧠 ${nouveaux.length} pronostic(s) (fallback)');
    }
  }

  // ── Récupération automatique résultats PMU ────────────────────────
  void _recupererResultatsAuto() {
    Future.microtask(_recupererResultatsBatch);
  }

  Future<void> _recupererResultatsBatch() async {
    final now = DateTime.now();
    final pronosticsEnAttente = IaMemoryService.instance.pronostics
        .where((p) => !p.resultatsReels)
        .toList();
    if (pronosticsEnAttente.isEmpty) return;

    int nbRecuperes = 0;
    for (final p in pronosticsEnAttente) {
      final match = RegExp(r'^R(\d+)C(\d+)_(\d{2})(\d{2})(\d{4})$')
          .firstMatch(p.courseKey);
      if (match == null) continue;

      final numR    = int.tryParse(match.group(1) ?? '') ?? 0;
      final numC    = int.tryParse(match.group(2) ?? '') ?? 0;
      final dd      = match.group(3)!;
      final mm      = match.group(4)!;
      final yyyy    = match.group(5)!;
      final dateStr = '$dd$mm$yyyy';

      final courseDiff = now.difference(p.datePronostic);
      if (courseDiff.inMinutes < 10) continue;
      if (courseDiff.inHours   > 24) continue;

      try {
        final arrivee = await _fetchArriveeOfficielle(numR, numC, dateStr);
        if (arrivee.isEmpty) continue;

        await IaMemoryService.instance.enregistrerResultat(
          courseKey:    p.courseKey,
          arriveeReelle: arrivee,
        );

        // ★ v9.0 : Mettre à jour l'ELO après chaque arrivée officielle
        _mettreAJourEloApresArrivee(p.courseKey, arrivee);

        nbRecuperes++;
        debugPrint('[DataRefresh] ✅ Résultat R${numR}C$numC : '
            '${arrivee.take(5).map((n) => "N°$n").join("-")}');
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[DataRefresh] ⚠️ Résultat R${numR}C$numC : $e');
        }
      }
    }

    if (nbRecuperes > 0) {
      debugPrint('[DataRefresh] 🏆 $nbRecuperes résultat(s) récupérés');
      // ★ v9.79 : notif push Android "Résultats disponibles"
      AlertService.instance.envoyerNotifResultatsDisponibles(nbRecuperes);
      notifyListeners();
    }
  }

  /// ★ v9.0 : Met à jour les scores ELO après une arrivée officielle
  void _mettreAJourEloApresArrivee(String courseKey, List<int> arrivee) {
    final match = RegExp(r'^R(\d+)C(\d+)_').firstMatch(courseKey);
    if (match == null) return;
    final numR = int.tryParse(match.group(1) ?? '') ?? 0;
    final numC = int.tryParse(match.group(2) ?? '') ?? 0;

    List<ZtPartant>? partants;
    String typeCourse = '';
    for (final reunion in _reunions) {
      final rMatch = RegExp(r'R(\d+)').firstMatch(reunion.code);
      final rNum   = rMatch != null
          ? int.tryParse(rMatch.group(1) ?? '') ?? 0 : 0;
      if (rNum != numR) continue;
      final course = reunion.courses
          .where((c) => c.numCourse == numC)
          .firstOrNull;
      if (course != null) {
        partants   = course.partants;
        typeCourse = course.type; // ★ v9.92 : récupérer le type pour ELO par discipline
        break;
      }
    }
    if (partants == null || partants.isEmpty) return;

    EloService.instance.mettreAJourApresArrivee(
      arrivee:    arrivee,
      partants:   partants,
      discipline: typeCourse, // ★ v9.92
    ).ignore();
  }

  Future<List<int>> _fetchArriveeOfficielle(
      int numR, int numC, String dateStr) async {
    final url = 'https://turfinfo.api.pmu.fr/rest/client/7'
        '/programme/$dateStr'
        '/R$numR/C$numC'
        '/rapports-definitifs?specialisation=INTERNET';

    final resp = await http
        .get(Uri.parse(url), headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 15));

    if (resp.statusCode != 200) return [];

    final List<dynamic> rapports = jsonDecode(resp.body) as List<dynamic>;
    final List<int> arrivee = [];

    for (final r in rapports) {
      final typePari = r['typePari'] as String? ?? '';
      final rList    = (r['rapports'] as List<dynamic>? ?? []);
      if (rList.isEmpty) continue;

      if (typePari == 'E_SIMPLE_GAGNANT' ||
          typePari == 'SIMPLE_GAGNANT' ||
          typePari == 'GAGNANT') {
        final rap = rList.first as Map<String, dynamic>;
        final n   = int.tryParse(rap['combinaison']?.toString() ?? '');
        if (n != null && !arrivee.contains(n)) arrivee.insert(0, n);
      }

      if (typePari == 'E_SIMPLE_PLACE' ||
          typePari == 'SIMPLE_PLACE' ||
          typePari == 'PLACE') {
        for (final pl in rList) {
          final n = int.tryParse((pl as Map)['combinaison']?.toString() ?? '');
          if (n != null && !arrivee.contains(n)) arrivee.add(n);
        }
      }

      if (typePari.contains('TIERCE') ||
          typePari.contains('QUARTE') ||
          typePari.contains('QUINTE')) {
        final rap   = rList.first as Map<String, dynamic>;
        final combo = rap['combinaison']?.toString() ?? '';
        for (final part in combo.split('-')) {
          final n = int.tryParse(part.trim());
          if (n != null && !arrivee.contains(n)) arrivee.add(n);
        }
      }
    }
    return arrivee;
  }

  /// Rafraîchissement pour une date spécifique (écran Courses)
  Future<List<ZtReunion>> chargerPourDate(
      DateTime date, {bool force = false}) async {
    return ZoneTurfService.chargerProgramme(date: date, forceRefresh: force);
  }

  String _todayDateStr() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.year}';
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }
}
