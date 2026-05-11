import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'ia_memory_service.dart';
import 'zone_turf_service.dart';
import 'data_refresh_service.dart';
import '../models/zt_models.dart';
import '../providers/pmu_provider.dart';
import '../utils/format_euros.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// AlertService — Gestion complète des alertes Pronostic Hippique v3.0 (Lot 2)
///
/// NOUVEAUTÉS v3.0 :
///   ★ ajouterAlertNonPartant() : alerte push quand un cheval est retiré
///   ★ Notifications enrichies : arrivée officielle + gain/perte calculé
///   ★ signalerResultat() enrichi avec arriveeOfficielle + gainNet
///
/// Fonctionnement :
///   • Alertes in-app  : SnackBar / overlay (fonctionne toujours)
///   • Permissions     : demande automatique sur Android 13+
///   • Surveillance    : timer périodique qui vérifie les paris suivis
///
/// Types d'alertes :
///   - courseImminente   : course dans < X min
///   - courseCommence    : course démarre maintenant
///   - courseEnCours     : course en cours (rappel)
///   - resultatsGagnant  : pari gagné 🎉
///   - resultatsNon      : pari perdu
///   - rappelMise        : rappel de miser avant le départ
/// ═══════════════════════════════════════════════════════════════════════════

// ─── Types d'alertes ─────────────────────────────────────────────────────────
enum AlertType {
  courseImminente,
  courseCommence,
  courseEnCours,
  resultatsGagnant,
  resultatsPerdant,
  rappelMise,
  conseilIA,     // ★ v10.23 : cours entrant dans les critères Conseils IA
  coteBaisse,    // ★ v10.24 : cote qui chute ≥ 20% en 1h
  derniereChance,// ★ v10.24 : 30min avant départ, pas encore misé
}

extension AlertTypeExt on AlertType {
  String get label {
    switch (this) {
      case AlertType.courseImminente:  return '⏰ Course imminente';
      case AlertType.courseCommence:   return '🏇 Départ !';
      case AlertType.courseEnCours:    return '🔴 En cours';
      case AlertType.resultatsGagnant: return '🎉 Paris gagnant !';
      case AlertType.resultatsPerdant: return '😔 Paris perdu';
      case AlertType.rappelMise:       return '💰 Rappel de mise';
      case AlertType.conseilIA:        return '🎯 Conseil IA';
      case AlertType.coteBaisse:       return '📉 Cote qui chute';
      case AlertType.derniereChance:   return '⏰ Dernière chance';
    }
  }

  Color get color {
    switch (this) {
      case AlertType.courseImminente:  return const Color(0xFFFFB74D);
      case AlertType.courseCommence:   return const Color(0xFF4CAF7D);
      case AlertType.courseEnCours:    return const Color(0xFF64B5F6);
      case AlertType.resultatsGagnant: return const Color(0xFFFFD700);
      case AlertType.resultatsPerdant: return const Color(0xFFEF5350);
      case AlertType.rappelMise:       return const Color(0xFFFF9800);
      case AlertType.conseilIA:        return const Color(0xFF4CAF7D);
      case AlertType.coteBaisse:       return const Color(0xFFEF5350);
      case AlertType.derniereChance:   return const Color(0xFFFF6F00);
    }
  }

  IconData get icon {
    switch (this) {
      case AlertType.courseImminente:  return Icons.timer;
      case AlertType.courseCommence:   return Icons.flag;
      case AlertType.courseEnCours:    return Icons.radio_button_checked;
      case AlertType.resultatsGagnant: return Icons.emoji_events;
      case AlertType.resultatsPerdant: return Icons.sentiment_dissatisfied;
      case AlertType.rappelMise:       return Icons.payments;
      case AlertType.conseilIA:        return Icons.stars;
      case AlertType.coteBaisse:       return Icons.trending_down;
      case AlertType.derniereChance:   return Icons.alarm;
    }
  }
}

// ─── Modèle d'une alerte ─────────────────────────────────────────────────────
class AppAlert {
  final String id;
  final AlertType type;
  final String titre;
  final String message;
  final DateTime timestamp;
  bool isRead;
  // ★ Lien vers la course pour navigation depuis l'historique
  final int? numReunion;
  final int? numCourse;
  final String? dateStrCourse; // format 'YYYYMMDD' pour l'API PMU
  final DateTime? heureDepart;  // heure réelle de la course (pour affichage)

  AppAlert({
    required this.id,
    required this.type,
    required this.titre,
    required this.message,
    required this.timestamp,
    this.isRead = false,
    this.numReunion,
    this.numCourse,
    this.dateStrCourse,
    this.heureDepart,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.index,
    'titre': titre,
    'message': message,
    'timestamp': timestamp.toIso8601String(),
    'isRead': isRead,
    'numReunion': numReunion,
    'numCourse': numCourse,
    'dateStrCourse': dateStrCourse,
    'heureDepart': heureDepart?.toIso8601String(),
  };

  factory AppAlert.fromJson(Map<String, dynamic> j) => AppAlert(
    id: j['id'] as String,
    type: AlertType.values[j['type'] as int],
    titre: j['titre'] as String,
    message: j['message'] as String,
    timestamp: DateTime.parse(j['timestamp'] as String),
    isRead: j['isRead'] as bool? ?? false,
    numReunion: j['numReunion'] as int?,
    numCourse: j['numCourse'] as int?,
    dateStrCourse: j['dateStrCourse'] as String?,
    heureDepart: j['heureDepart'] != null
        ? DateTime.tryParse(j['heureDepart'] as String)
        : null,
  );
}

// ─── Périmètre de surveillance des alertes ────────────────────────────────────
// ★ v10.16 : AlertScope remplacé par 3 booleans indépendants dans AlertConfig
// Conservé pour rétrocompatibilité fromJson des anciens backups
enum AlertScope {
  toutesLesCourses,
  coursesFavoris,
  coursesSuivies,
}

// ★ v10.16 : Extension conservée pour l'affichage UI (label, icon, color, description)
extension AlertScopeExt on AlertScope {
  String get label {
    switch (this) {
      case AlertScope.toutesLesCourses: return 'Toutes les courses';
      case AlertScope.coursesFavoris:   return 'Courses en favoris';
      case AlertScope.coursesSuivies:   return 'Courses suivies';
    }
  }

  String get description {
    switch (this) {
      case AlertScope.toutesLesCourses: return 'Alertes pour toutes les courses du suivi';
      case AlertScope.coursesFavoris:   return 'Alertes uniquement pour vos ★ favoris';
      case AlertScope.coursesSuivies:   return 'Alertes uniquement pour vos paris validés';
    }
  }

  IconData get icon {
    switch (this) {
      case AlertScope.toutesLesCourses: return Icons.notifications_active;
      case AlertScope.coursesFavoris:   return Icons.star;
      case AlertScope.coursesSuivies:   return Icons.bookmark;
    }
  }

  Color get color {
    switch (this) {
      case AlertScope.toutesLesCourses: return const Color(0xFF64B5F6);
      case AlertScope.coursesFavoris:   return const Color(0xFFFFD700);
      case AlertScope.coursesSuivies:   return const Color(0xFF4CAF7D);
    }
  }
}

// ─── Configuration des alertes ────────────────────────────────────────────────
class AlertConfig {
  final bool activerCourseImminente;   // X min avant
  final bool activerCourseCommence;    // au départ
  final bool activerCourseEnCours;     // pendant la course
  final bool activerResultats;         // résultat final
  final bool activerRappelMise;        // rappel de miser
  final int minutesAvantDepart;        // 5, 10, 15, 30 min
  final bool vibrationsActivees;       // vibration pour les alertes
  final bool sonsActives;              // son pour les alertes importantes
  // ★ v10.16 : 3 flags indépendants (multi-sélection) — remplace scopeAlerte
  final bool scopeToutes;    // toutes les courses du suivi
  final bool scopeFavoris;   // courses marquées ★ favori
  final bool scopeSuivies;   // courses avec un pari engagé (mise > 0)
  // ★ v10.23 : Alerte Conseil IA — notif quand une course entre dans les critères
  final bool activerConseilIA;
  // ★ v10.24 : Alerte Cote qui chute — notif si cote baisse ≥ 20% en 1h
  final bool activerCoteChute;
  // ★ v10.24 : Alerte Dernière chance — notif 30min avant départ si pas encore misé
  final bool activerDerniereChance;
  // ★ v10.24 : Rappel quotidien à heure fixe
  final bool activerRappelQuotidien;
  final int rappelHeure;    // 0-23
  final int rappelMinute;   // 0-59

  const AlertConfig({
    this.activerCourseImminente  = true,
    this.activerCourseCommence   = true,
    this.activerCourseEnCours    = false,
    this.activerResultats        = true,
    this.activerRappelMise       = true,
    this.minutesAvantDepart      = 15,
    this.vibrationsActivees      = true,
    this.sonsActives             = true,
    this.scopeToutes             = true,
    this.scopeFavoris            = false,
    this.scopeSuivies            = false,
    this.activerConseilIA        = true,
    this.activerCoteChute        = true,   // ★ v10.24 : activé par défaut
    this.activerDerniereChance   = true,   // ★ v10.24 : activé par défaut
    this.activerRappelQuotidien  = false,  // ★ v10.24 : désactivé par défaut
    this.rappelHeure             = 9,      // 9h00 par défaut
    this.rappelMinute            = 0,
  });

  static const AlertConfig defaut = AlertConfig();

  Map<String, dynamic> toJson() => {
    'courseImminente':  activerCourseImminente,
    'courseCommence':   activerCourseCommence,
    'courseEnCours':    activerCourseEnCours,
    'resultats':        activerResultats,
    'rappelMise':       activerRappelMise,
    'minutesAvant':     minutesAvantDepart,
    'vibrations':       vibrationsActivees,
    'sons':             sonsActives,
    // ★ v10.16 : 3 flags indépendants
    'scopeToutes':      scopeToutes,
    'scopeFavoris':     scopeFavoris,
    'scopeSuivies':     scopeSuivies,
    'activerConseilIA':       activerConseilIA,
    'activerCoteChute':       activerCoteChute,
    'activerDerniereChance':  activerDerniereChance,
    'activerRappelQuotidien': activerRappelQuotidien,
    'rappelHeure':            rappelHeure,
    'rappelMinute':           rappelMinute,
  };

  factory AlertConfig.fromJson(Map<String, dynamic> j) {
    // ★ v10.16 : migration rétrocompatible depuis l'ancien scopeAlerte (index)
    bool defToutes = true, defFavoris = false, defSuivies = false;
    if (j.containsKey('scopeToutes')) {
      // Nouveau format v10.16
      defToutes   = j['scopeToutes']  as bool? ?? true;
      defFavoris  = j['scopeFavoris'] as bool? ?? false;
      defSuivies  = j['scopeSuivies'] as bool? ?? false;
    } else if (j.containsKey('scopeAlerte')) {
      // Ancien format : migrer l'index vers les flags
      final idx = (j['scopeAlerte'] as int? ?? 0).clamp(0, 2);
      defToutes  = idx == 0;
      defFavoris = idx == 1;
      defSuivies = idx == 2;
    }
    return AlertConfig(
      activerCourseImminente: j['courseImminente'] as bool? ?? true,
      activerCourseCommence:  j['courseCommence']  as bool? ?? true,
      activerCourseEnCours:   j['courseEnCours']   as bool? ?? false,
      activerResultats:       j['resultats']       as bool? ?? true,
      activerRappelMise:      j['rappelMise']      as bool? ?? true,
      minutesAvantDepart:     j['minutesAvant']    as int?  ?? 15,
      vibrationsActivees:     j['vibrations']      as bool? ?? true,
      sonsActives:            j['sons']            as bool? ?? true,
      scopeToutes:            defToutes,
      scopeFavoris:           defFavoris,
      scopeSuivies:           defSuivies,
      activerConseilIA:       j['activerConseilIA']       as bool? ?? true,
      activerCoteChute:       j['activerCoteChute']       as bool? ?? true,
      activerDerniereChance:  j['activerDerniereChance']  as bool? ?? true,
      activerRappelQuotidien: j['activerRappelQuotidien'] as bool? ?? false,
      rappelHeure:            j['rappelHeure']            as int?  ?? 9,
      rappelMinute:           j['rappelMinute']           as int?  ?? 0,
    );
  }

  AlertConfig copyWith({
    bool? activerCourseImminente,
    bool? activerCourseCommence,
    bool? activerCourseEnCours,
    bool? activerResultats,
    bool? activerRappelMise,
    int?  minutesAvantDepart,
    bool? vibrationsActivees,
    bool? sonsActives,
    bool? scopeToutes,
    bool? scopeFavoris,
    bool? scopeSuivies,
    bool? activerConseilIA,
    bool? activerCoteChute,
    bool? activerDerniereChance,
    bool? activerRappelQuotidien,
    int?  rappelHeure,
    int?  rappelMinute,
  }) => AlertConfig(
    activerCourseImminente:  activerCourseImminente  ?? this.activerCourseImminente,
    activerCourseCommence:   activerCourseCommence   ?? this.activerCourseCommence,
    activerCourseEnCours:    activerCourseEnCours    ?? this.activerCourseEnCours,
    activerResultats:        activerResultats        ?? this.activerResultats,
    activerRappelMise:       activerRappelMise       ?? this.activerRappelMise,
    minutesAvantDepart:      minutesAvantDepart      ?? this.minutesAvantDepart,
    vibrationsActivees:      vibrationsActivees      ?? this.vibrationsActivees,
    sonsActives:             sonsActives             ?? this.sonsActives,
    scopeToutes:             scopeToutes             ?? this.scopeToutes,
    scopeFavoris:            scopeFavoris            ?? this.scopeFavoris,
    scopeSuivies:            scopeSuivies            ?? this.scopeSuivies,
    activerConseilIA:        activerConseilIA        ?? this.activerConseilIA,
    activerCoteChute:        activerCoteChute        ?? this.activerCoteChute,
    activerDerniereChance:   activerDerniereChance   ?? this.activerDerniereChance,
    activerRappelQuotidien:  activerRappelQuotidien  ?? this.activerRappelQuotidien,
    rappelHeure:             rappelHeure             ?? this.rappelHeure,
    rappelMinute:            rappelMinute            ?? this.rappelMinute,
  );
}

// ─── État des permissions ────────────────────────────────────────────────────
enum NotificationPermissionStatus {
  notChecked,
  granted,
  denied,
  permanentlyDenied,
}

// ─── Service principal ────────────────────────────────────────────────────────
class AlertService extends ChangeNotifier {
  static final AlertService _instance = AlertService._();
  static AlertService get instance => _instance;
  AlertService._();

  // Référence au PmuProvider pour mettre à jour isCorrect automatiquement
  // Initialisée depuis main.dart après le build du contexte
  PmuProvider? _pmuProvider;
  void setPmuProvider(PmuProvider p) { _pmuProvider = p; }

  // ★ v10.24 : callback injecté par CoteTrackerService pour éviter import circulaire
  // Retourne List<({courseKey, nomCourse, hippodrome, numero, nom, coteDebut, coteFin, variationPct})>
  List<Map<String, dynamic>> Function()? _getCotesChute;
  void setCotesChuteCallback(List<Map<String, dynamic>> Function() fn) {
    _getCotesChute = fn;
  }

  // ★ v10.24 : Timer dédié pour le rappel quotidien à heure fixe
  Timer? _rappelTimer;

  static const String _configKey       = 'alert_config_v2';
  static const String _alertsKey       = 'alert_history_v1';
  static const String _trackedKey      = 'tracked_courses_v1';
  // ★ Clé pour les favoris non pariés — lue par HippiqueWorker (Kotlin)
  // Format : liste JSON de {numR, numC, nomCourse, hippodrome, scoreIA, dejaParI}
  static const String _favoritesKey    = 'hippique_favorites_v1';
  // ★ Clé publique — utilisée par favori_button.dart et mes_paris_screen.dart
  static const String favoritesKey     = _favoritesKey;
  static const String _sentIdsKey      = 'alert_sent_ids_v1';      // ← persistance anti-doublons
  static const String _resultatsKey    = 'alert_resultats_verifies_v1'; // ← persistance résultats
  static const String _coteChuteKey    = 'alert_cote_chute_notifies_v1'; // ★ v10.24 audit : anti-doublon cote

  AlertConfig _config = AlertConfig.defaut;
  final List<AppAlert> _alerts = [];
  // Courses suivies : key = "R${numR}C${numC}", value = DateHeure départ
  final Map<String, TrackedCourse> _trackedCourses = {};
  // Alertes déjà envoyées pour éviter les doublons
  final Set<String> _sentAlertIds = {};
  // Courses dont le résultat a déjà été récupéré automatiquement
  final Set<String> _resultatsVerifies = {};
  // ★ Tracking DQ : statuts PMU connus par courseKey pour ne notifier qu'une fois
  // Clé : courseKey, Valeur : set des numéros déjà identifiés comme DQ/RETRAIT
  final Map<String, Set<int>> _disqDetectes = {};
  // ★ Clé de re-analyse en cours pour éviter les appels simultanés
  final Set<String> _reanalyseEnCours = {};
  Timer? _watchdogTimer;

  // État des permissions de notification
  NotificationPermissionStatus _permissionStatus = NotificationPermissionStatus.notChecked;

  AlertConfig get config => _config;
  List<AppAlert> get alerts => List.unmodifiable(_alerts.reversed);
  int get unreadCount => _alerts.where((a) => !a.isRead).length;
  Map<String, TrackedCourse> get trackedCourses => Map.unmodifiable(_trackedCourses);

  /// Retourne les numéros des chevaux DQ/retirés détectés pour une course.
  /// [courseKey] : clé de la course (ex: "R1C3")
  /// Retourne une liste vide si aucun DQ détecté.
  List<int> disqPourCourse(String courseKey) {
    return (_disqDetectes[courseKey] ?? {}).toList()..sort();
  }
  NotificationPermissionStatus get permissionStatus => _permissionStatus;
  bool get hasNotificationPermission => _permissionStatus == NotificationPermissionStatus.granted;

  // ── Initialisation ────────────────────────────────────────────────────────

  static Future<void> init() async {
    await _instance._load();
    _instance._startWatchdog();
  }

  /// Recharge toutes les données AlertService depuis SharedPreferences.
  /// Appelé après une restauration backup pour activer immédiatement
  /// les données restaurées sans redémarrer l'application.
  Future<void> recharger() async {
    await _load();
    notifyListeners();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Config
      final cfgStr = prefs.getString(_configKey);
      if (cfgStr != null) {
        _config = AlertConfig.fromJson(json.decode(cfgStr) as Map<String, dynamic>);
      }
      // Historique alertes (50 dernières)
      final alertsRaw = prefs.getStringList(_alertsKey) ?? [];
      _alerts.clear();
      for (final s in alertsRaw) {
        try {
          _alerts.add(AppAlert.fromJson(json.decode(s) as Map<String, dynamic>));
        } catch (_) {}
      }
      // Courses suivies
      final trackedRaw = prefs.getStringList(_trackedKey) ?? [];
      _trackedCourses.clear();
      for (final s in trackedRaw) {
        try {
          final tc = TrackedCourse.fromJson(json.decode(s) as Map<String, dynamic>);
          // Utiliser la storageKey persistée (avec timestamp) si disponible
          // sinon fallback sur tc.key (anciens paris sans storageKey)
          final loadKey = tc.storageKey ?? tc.key;
          _trackedCourses[loadKey] = tc;
        } catch (_) {}
      }
      // ★ Option B — Nettoyage automatique renforcé (v9.44)
      // 1) Purge les courses de plus de 24h (évite collisions entre journées)
      // 2) Purge les clés au format ancien sans date (ex: "R3C3" au lieu de "R3C3_23042026")
      //    Ces vieilles clés causaient l'écran gris en faisant croire qu'une course
      //    était déjà suivie alors qu'elle venait d'un autre jour.
      final now = DateTime.now();
      _trackedCourses.removeWhere((key, tc) {
        // Clé ancienne format (sans date, ex: "R3C3") → purger immédiatement
        final hasDate = RegExp(r'R\d+C\d+_\d{8}').hasMatch(key);
        if (!hasDate) return true;
        // Clé valide mais trop ancienne → purger après 24h
        return now.difference(tc.heureDepart).inHours > 24;
      });
      // ★ Bug fix : charger les IDs déjà envoyés pour éviter doublons au redémarrage
      final sentIds = prefs.getStringList(_sentIdsKey) ?? [];
      _sentAlertIds.addAll(sentIds);
      // ★ Bug fix : charger les résultats déjà vérifiés pour éviter re-fetch au redémarrage
      final resultatsIds = prefs.getStringList(_resultatsKey) ?? [];
      _resultatsVerifies.addAll(resultatsIds);
      // ★ v10.24 audit : charger les alertes cote-chute déjà envoyées (anti-doublon inter-session)
      // Max 100 IDs — purgé à chaque _save(). Les IDs contiennent la courseKey du jour
      // donc ils deviennent naturellement caducs au lendemain (nouvelles courseKeys).
      final coteChuteIds = prefs.getStringList(_coteChuteKey) ?? [];
      _coteChuteNotifies.addAll(coteChuteIds);
    } catch (e) {
      if (kDebugMode) debugPrint('AlertService._load error: $e');
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_configKey, json.encode(_config.toJson()));
      final alertsToSave = _alerts.take(50).map((a) => json.encode(a.toJson())).toList();
      await prefs.setStringList(_alertsKey, alertsToSave);
      final trackedToSave = _trackedCourses.values.map((tc) => json.encode(tc.toJson())).toList();
      await prefs.setStringList(_trackedKey, trackedToSave);
      // ★ Bug fix : persister les IDs envoyés (max 200 pour limiter la taille)
      final sentToSave = _sentAlertIds.take(200).toList();
      await prefs.setStringList(_sentIdsKey, sentToSave);
      // ★ Bug fix : persister les résultats vérifiés (max 100)
      final resultatsToSave = _resultatsVerifies.take(100).toList();
      await prefs.setStringList(_resultatsKey, resultatsToSave);
      // ★ v10.24 audit : persister les alertes cote-chute envoyées (max 100, jour glissant)
      final coteChuteToSave = _coteChuteNotifies.take(100).toList();
      await prefs.setStringList(_coteChuteKey, coteChuteToSave);
    } catch (e) {
      if (kDebugMode) debugPrint('AlertService._save error: $e');
    }
  }

  // ── Gestion des permissions Android 13+ ──────────────────────────────────

  /// Vérifie et demande les permissions de notification
  /// Returns true si accordées
  Future<bool> requestNotificationPermission(BuildContext context) async {
    // Sur Android < 13, les notifications sont accordées par défaut
    // Sur Android 13+, on doit demander explicitement
    try {
      // Utiliser le MethodChannel pour vérifier / demander les permissions
      const channel = MethodChannel('com.racepredictor.predict/permissions');
      final bool granted = await channel.invokeMethod('requestNotificationPermission');
      _permissionStatus = granted
          ? NotificationPermissionStatus.granted
          : NotificationPermissionStatus.denied;
      notifyListeners();
      return granted;
    } catch (e) {
      // Si le canal n'est pas implémenté (mode debug web ou ancien Android),
      // on considère que les permissions sont accordées
      if (kDebugMode) debugPrint('Permission channel not available: $e');
      _permissionStatus = NotificationPermissionStatus.granted;
      notifyListeners();
      return true;
    }
  }

  /// Ouvre les paramètres de notification de l'application
  Future<void> ouvrirParametresNotification() async {
    try {
      const channel = MethodChannel('com.racepredictor.predict/permissions');
      await channel.invokeMethod('openNotificationSettings');
    } catch (e) {
      if (kDebugMode) debugPrint('openNotificationSettings error: $e');
    }
  }

  /// Vérifie l'état actuel des permissions sans les demander
  Future<void> checkPermissionStatus() async {
    try {
      const channel = MethodChannel('com.racepredictor.predict/permissions');
      final bool granted = await channel.invokeMethod('checkNotificationPermission');
      _permissionStatus = granted
          ? NotificationPermissionStatus.granted
          : NotificationPermissionStatus.denied;
      notifyListeners();
    } catch (e) {
      // Si le canal n'est pas disponible, supposer accordé (compatibilité)
      _permissionStatus = NotificationPermissionStatus.granted;
      notifyListeners();
    }
  }

  // ── Configuration ─────────────────────────────────────────────────────────

  Future<void> updateConfig(AlertConfig newConfig) async {
    final ancienRappel = _config.activerRappelQuotidien;
    final ancienHeure  = _config.rappelHeure;
    final ancienMinute = _config.rappelMinute;
    _config = newConfig;
    notifyListeners();
    await _save();
    // ★ v10.24 : redémarrer le timer rappel si la config change
    if (newConfig.activerRappelQuotidien != ancienRappel ||
        newConfig.rappelHeure  != ancienHeure  ||
        newConfig.rappelMinute != ancienMinute) {
      _demarrerRappelQuotidien();
    }
  }

  // ── Suivi des courses ─────────────────────────────────────────────────────

  bool isSuivi(String key) => _trackedCourses.containsKey(key);

  /// ★ Fix doublon : vérifie si une course avec cette baseKey (sans timestamp)
  /// est déjà en suivi — utile car les storageKeys incluent un timestamp.
  /// Ex: cherche 'R4C7_23042026' parmi 'R4C7_23042026_1745000000000'
  bool estDejaEnSuivi(String baseKey) =>
      _trackedCourses.keys.any((k) => k == baseKey || k.startsWith('${baseKey}_'));

  Future<void> ajouterSuivi(TrackedCourse course, {String? overrideKey}) async {
    // ★ Fix option A : plusieurs paris possibles sur la même course
    // On ajoute un timestamp à la clé pour que chaque pari soit unique
    // Ex: R4C7_23042026 → R4C7_23042026_1745000000000
    final baseKey = overrideKey ?? course.key;
    final storageKey = '${baseKey}_${DateTime.now().millisecondsSinceEpoch}';
    // Créer une copie du course avec la storageKey intégrée pour la persistance
    final courseAvecKey = TrackedCourse(
      numReunion: course.numReunion,
      numCourse: course.numCourse,
      nomCourse: course.nomCourse,
      hippodrome: course.hippodrome,
      heureDepart: course.heureDepart,
      nomCheval: course.nomCheval,
      numeroCheval: course.numeroCheval,
      miseEngagee: course.miseEngagee,
      addedAt: course.addedAt,
      typePari: course.typePari,
      numerosJoues: course.numerosJoues,
      iaMemKey: course.iaMemKey,
      scoreIA: course.scoreIA,
      cote: course.cote,
      isGagne: course.isGagne,
      arriveeFinale: course.arriveeFinale,
      messageResultat: course.messageResultat,
      dividendePmuReel: course.dividendePmuReel,
      combinaisonPmu: course.combinaisonPmu,
      storageKey: storageKey,
    );
    _trackedCourses[storageKey] = courseAvecKey;
    notifyListeners();
    await _save();
    // Alerte immédiate de confirmation
    // ★ Fix Source 3 : ID stable basé sur baseKey + date (sans milliseconde)
    // Evite de renvoyer la notif si l'utilisateur rouvre le sheet par erreur
    final now2 = DateTime.now();
    final confirmedId = '${baseKey}_added_${now2.year}${now2.month}${now2.day}';
    _addAlert(AppAlert(
      id: confirmedId,
      type: AlertType.rappelMise,
      titre: '✅ Course suivie',
      message: '${course.nomCourse} — ${course.hippodrome}\n'
               'Mise enregistrée : ${course.miseEngagee != null ? fmtEuros(course.miseEngagee!) : '?'} €\n'
               'Départ prévu : ${_formatHeure(course.heureDepart)}',
      timestamp: now2,
      numReunion: course.numReunion,
      numCourse: course.numCourse,
    ));
  }

  Future<void> retirerSuivi(String key) async {
    _trackedCourses.remove(key);
    notifyListeners();
    await _save();
  }

  /// ★ Nouveau — Persiste le résultat d'un pari dans TrackedCourse
  /// Appelé automatiquement depuis _TrackedCourseCardState quand le résultat est connu.
  /// Le résultat est ainsi conservé même après navigation / fermeture de l'app.
  Future<void> enregistrerResultatPari(
    String courseKey, {
    required bool isGagne,
    required List<int> arrivee,
    required String message,
  }) async {
    final tc = _trackedCourses[courseKey];
    if (tc == null) return;
    if (tc.isGagne != null) return; // déjà enregistré, ne pas écraser
    _trackedCourses[courseKey] = tc.withResultat(
      isGagne: isGagne,
      arrivee: arrivee,
      message: message,
    );
    notifyListeners();
    await _save();
  }

  /// Persiste le dividende PMU réel dans TrackedCourse après la course
  /// Appelé depuis paris_detail_screen ou mes_paris_screen une fois le dividende récupéré.
  /// ★ Fix : vérifie que le pari est réellement gagnant avant d'enregistrer
  Future<void> enregistrerDividendePmuTracked(
    String courseKey, {
    required double dividende,
    required String combinaison,
  }) async {
    final tc = _trackedCourses[courseKey];
    if (tc == null) return;
    if (tc.dividendePmuReel != null) return; // déjà enregistré
    // ★ Fix bug profil : ne jamais enregistrer un dividende sur un pari perdu
    // isGagne == false → pari perdu, on n'enregistre rien
    // isGagne == null  → résultat inconnu, on n'enregistre pas encore
    // isGagne == true  → pari gagné, on enregistre
    if (tc.isGagne != true) return;
    _trackedCourses[courseKey] = tc.withDividende(
      dividende: dividende,
      combinaison: combinaison,
    );
    notifyListeners();
    await _save();
  }

  // ── Ajout d'alerte ────────────────────────────────────────────────────────

  void _addAlert(AppAlert alert) {
    if (_sentAlertIds.contains(alert.id)) return;
    _sentAlertIds.add(alert.id);
    _alerts.insert(0, alert);
    if (_alerts.length > 100) _alerts.removeLast();
    notifyListeners();
    _save();
    // ★ Bug fix #5 : envoyer la vraie notification Android native
    _sendNativeNotification(alert);
  }

  /// Envoie une notification système Android
  /// ★ v9.6 Fix arrière-plan : double stratégie
  ///   1. MethodChannel (app ouverte) → immédiat
  ///   2. SharedPreferences (app fermée) → Worker Kotlin lit et envoie
  Future<void> _sendNativeNotification(AppAlert alert) async {
    final notifId = alert.id.hashCode.abs() % 100000;

    // Stratégie 1 : MethodChannel si app en premier plan
    try {
      const channel = MethodChannel('com.racepredictor.predict/permissions');
      await channel.invokeMethod('showNotification', {
        'title':     alert.titre,
        'body':      alert.message,
        'id':        notifId,
        'courseKey': alert.id, // ★ v9.84 : deep link vers le pari concerné
      });
    } catch (_) {
      // App en arrière-plan → fallback SharedPreferences
    }

    // Stratégie 2 : écrire dans SharedPreferences pour que le Worker
    // Kotlin envoie la notification même si l'app est fermée
    try {
      final prefs = await SharedPreferences.getInstance();
      // Format JSON compatible Android natif : getString/setString + jsonEncode
      // (setStringList Flutter n'est pas lisible par getStringSet Kotlin)
      final existing = prefs.getString('flutter.hippique_pending_notifs');
      final pending = existing != null
          ? List<String>.from(jsonDecode(existing) as List)
          : <String>[];
      // Format : id|titre|message|timestamp
      final entry = '$notifId|${alert.titre}|${alert.message}|${DateTime.now().millisecondsSinceEpoch}';
      // Garder max 10 notifications en attente
      pending.add(entry);
      if (pending.length > 10) pending.removeAt(0);
      await prefs.setString('flutter.hippique_pending_notifs', jsonEncode(pending));
    } catch (_) {}
  }

  /// Appel externe pour signaler un résultat de course
  /// L'ID est stable (basé sur courseKey + date du jour) pour éviter les doublons
  // ══════════════════════════════════════════════════════════════════════════
  // ★ GESTION DES FAVORIS POUR LE WORKER ARRIÈRE-PLAN (HippiqueWorker.kt)
  // ══════════════════════════════════════════════════════════════════════════

  /// Ajoute une course aux "favoris" pour que le Worker en arrière-plan
  /// surveille ses cotes et alerte si une bonne opportunité se présente.
  /// À appeler depuis l'UI quand l'utilisateur marque une course comme favorite.
  Future<void> ajouterFavoriPourWorker({
    required int numR,
    required int numC,
    required String nomCourse,
    required String hippodrome,
    required double scoreIA,
    String heure = '',      // ★ v9.5 : heure de départ pour alerte 10 min avant
    String distance = '',
    String prix = '',
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_favoritesKey) ?? '[]';
      final List<dynamic> list = json.decode(raw) as List<dynamic>;

      // Éviter les doublons
      list.removeWhere((e) =>
        (e as Map)['numR'] == numR && e['numC'] == numC);

      list.add({
        'numR': numR,
        'numC': numC,
        'nomCourse': nomCourse,
        'hippodrome': hippodrome,
        'scoreIA': scoreIA,
        'heure': heure,         // ★ v9.5
        'distance': distance,   // ★ v9.5
        'prix': prix,           // ★ v9.5
        'dejaParI': false,
        'ajouteLe': DateTime.now().toIso8601String(),
      });

      // Garder les 20 derniers favoris max
      final trimmed = list.length > 20
          ? list.sublist(list.length - 20)
          : list;

      await prefs.setString(_favoritesKey, json.encode(trimmed));
    } catch (e) {
      if (kDebugMode) debugPrint('[AlertService] Erreur ajouterFavori: $e');
    }
  }

  /// Marque un favori comme "déjà parié" pour éviter les alertes redondantes.
  /// À appeler quand l'utilisateur place un pari sur cette course.
  Future<void> marquerFavoriCommeParI(int numR, int numC) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_favoritesKey) ?? '[]';
      final List<dynamic> list = json.decode(raw) as List<dynamic>;
      for (final e in list) {
        if ((e as Map)['numR'] == numR && e['numC'] == numC) {
          e['dejaParI'] = true;
        }
      }
      await prefs.setString(_favoritesKey, json.encode(list));
    } catch (e) {
      if (kDebugMode) debugPrint('[AlertService] Erreur marquerFavoriCommeParI: $e');
    }
  }

  /// Supprime les favoris des jours passés (nettoyage automatique).
  Future<void> nettoyerFavorisObsoletes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_favoritesKey) ?? '[]';
      final List<dynamic> list = json.decode(raw) as List<dynamic>;
      final hier = DateTime.now().subtract(const Duration(days: 1));
      list.removeWhere((e) {
        final ajouteLe = DateTime.tryParse((e as Map)['ajouteLe'] as String? ?? '');
        return ajouteLe != null && ajouteLe.isBefore(hier);
      });
      await prefs.setString(_favoritesKey, json.encode(list));
    } catch (_) {}
  }

  void signalerResultat({
    required String courseKey,
    required String nomCourse,
    required String hippodrome,
    required bool gagnant,
    required int? position,
    double? gainEstime,
    // ★ v3.0 : paramètres enrichis
    List<int> arriveeOfficielle = const [],
    double? miseEngagee,
    double? gainNet,
    String? nomCheval,
    int? numeroCheval,
  }) {
    if (!_config.activerResultats) return;

    final type = gagnant ? AlertType.resultatsGagnant : AlertType.resultatsPerdant;
    final now  = DateTime.now();
    final stableId = '${courseKey}_result_${now.year}${now.month}${now.day}';

    // ★ v3.0 : Construire une notification enrichie
    final String titre;
    final String message;

    if (gagnant) {
      final gainStr = gainNet != null && gainNet > 0
          ? '+${fmtEuros(gainNet)} €'
          : gainEstime != null && gainEstime > 0
              ? '+${fmtEuros(gainEstime)} €'
              : 'Vérifiez PMU';
      titre   = '🏆 GAGNÉ — $gainStr !';
      final chevalStr = (nomCheval != null && nomCheval.isNotEmpty)
          ? '${nomCheval} (N°${numeroCheval ?? "?"}) '
          : '';
      final arriveeStr = arriveeOfficielle.isNotEmpty
          ? '\nArrivée : ${arriveeOfficielle.take(5).map((n) => "N°$n").join(" - ")}'
          : '';
      final miseStr = miseEngagee != null && miseEngagee > 0
          ? '\nMise : ${fmtEuros(miseEngagee)} € → Gain : $gainStr'
          : '';
      message = '$chevalStr$nomCourse\n$hippodrome$arriveeStr$miseStr';
    } else {
      final posStr = position != null ? ' (${position}e)' : '';
      final arriveeStr = arriveeOfficielle.isNotEmpty
          ? '\nArrivée : ${arriveeOfficielle.take(5).map((n) => "N°$n").join(" - ")}'
          : '';
      final miseStr = miseEngagee != null && miseEngagee > 0
          ? '\nMise perdue : ${fmtEuros(miseEngagee)} €'
          : '';
      titre   = '😔 Paris Perdu$posStr';
      message = '$nomCourse\n$hippodrome$arriveeStr$miseStr';
    }

    // Extraire numR et numC depuis courseKey (format R3C5_23042026)
    int? numR, numC;
    final mKey = RegExp(r'R(\d+)C(\d+)').firstMatch(courseKey);
    if (mKey != null) {
      numR = int.tryParse(mKey.group(1)!);
      numC = int.tryParse(mKey.group(2)!);
    }
    _addAlert(AppAlert(
      id:        stableId,
      type:      type,
      titre:     titre,
      message:   message,
      timestamp: now,
      numReunion: numR,
      numCourse:  numC,
    ));
  }

  // ★ v3.0 ── Alerte non-partant (appelée par DataRefreshService) ─────────
  /// Envoie une notification push quand un cheval est retiré/non-partant.
  /// ★ v10.20 FIX : respecte le filtre scope (favoris / suivies / toutes)
  void ajouterAlertNonPartant({
    required String alertId,
    required String courseKey,
    required String nomCourse,
    required String hippodrome,
    required String numsStr,
  }) {
    // ★ v10.20 : vérifier le filtre scope AVANT d'envoyer la notification
    if (!_coursePasseFiltreByCourseKey(courseKey)) return;

    int? numR, numC;
    final mKey = RegExp(r'R(\d+)C(\d+)').firstMatch(courseKey);
    if (mKey != null) {
      numR = int.tryParse(mKey.group(1)!);
      numC = int.tryParse(mKey.group(2)!);
    }
    _addAlert(AppAlert(
      id:    alertId,
      type:  AlertType.courseImminente,
      titre: '⚠️ Non-partant(s) — $nomCourse',
      message: '$numsStr retiré(s) de $nomCourse\n'
               '$hippodrome\n'
               'Pronostic IA recalculé automatiquement.',
      timestamp: DateTime.now(),
      numReunion: numR,
      numCourse:  numC,
    ));
  }

  /// ★ v9.79 : Notification "Résultats disponibles" — envoyée automatiquement
  /// quand DataRefreshService récupère des arrivées officielles PMU.
  /// Anti-doublon via _sentAlertIds : une seule notif push par journée calendaire.
  /// _addAlert() appelle déjà _sendNativeNotification() → push Android garanti.
  // ★ v9.92 : Alerte convergence IA + mouvement de cote
  // ★ v10.20 FIX : respecte le filtre scope
  void ajouterAlertConvergenceIACote({
    required String courseKey,
    required String nomCourse,
    required String hippodrome,
    required String nomCheval,
    required String numero,
    required double coteDebut,
    required double coteFin,
    required String delta,
    required double scoreIA,
  }) {
    // ★ v10.20 : vérifier le filtre scope AVANT d'envoyer la notification
    if (!_coursePasseFiltreByCourseKey(courseKey)) return;

    final alertId = '${courseKey}_convergence_$numero';
    final now     = DateTime.now();
    int? numR, numC;
    final mKey = RegExp(r'R(\d+)C(\d+)').firstMatch(courseKey);
    if (mKey != null) {
      numR = int.tryParse(mKey.group(1)!);
      numC = int.tryParse(mKey.group(2)!);
    }
    _addAlert(AppAlert(
      id:        alertId,
      type:      AlertType.courseImminente,
      titre:     '🔥 Signal fort — N°$numero $nomCheval',
      message:   'Cote ${coteDebut.toStringAsFixed(1)} → ${coteFin.toStringAsFixed(1)} ($delta en < 15 min)\n'
                 'IA : ${scoreIA.toStringAsFixed(0)}/100 — Argent informé + IA alignés\n'
                 '$nomCourse',
      timestamp: now,
      numReunion: numR,
      numCourse:  numC,
    ));
  }

  /// ★ v10.20 FIX : Résultats — toujours envoyé (pas de filtre par course,
  /// c'est une info globale de la journée, pas une alerte de course spécifique).
  /// En revanche, on ne l'envoie que si au moins un flag d'alerte est activé.
  Future<void> envoyerNotifResultatsDisponibles(int nbResultats) async {
    // ★ v10.20 : ne pas notifier si toutes les alertes sont désactivées
    final aucunFlag = !_config.scopeToutes && !_config.scopeFavoris && !_config.scopeSuivies;
    if (aucunFlag) return;
    // Les résultats sont une info globale → pas de filtre par course individuelle
    if (!_config.activerResultats) return;

    final now = DateTime.now();
    final dayKey = 'resultats_'
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

    final label = nbResultats == 1
        ? '1 résultat officiel disponible'
        : '$nbResultats résultats officiels disponibles';

    _addAlert(AppAlert(
      id:        dayKey,
      type:      AlertType.courseImminente,
      titre:     '🏁 Résultats PMU du jour disponibles',
      message:   '$label — Ouvrez l\'onglet IA Stats pour lancer '
                 'l\'analyse et améliorer les pronostics.',
      timestamp: now,
    ));
  }

  /// Marquer toutes les alertes comme lues
  // ── ★ v10.23 : Alerte Conseil IA ─────────────────────────────────────────
  // Clé prefs pour mémoriser les courseKeys déjà notifiées (anti-spam)
  static const String _conseilIANotifiesKey = 'conseil_ia_notifies_v1';
  // Clé prefs pour le résumé matinal (1 seul par jour)
  static const String _conseilIAResumeDateKey = 'conseil_ia_resume_date';
  // Cache interne des courseKeys déjà notifiées ce jour
  final Set<String> _conseilIANotifies = {};

  /// Charge les courseKeys déjà notifiées depuis SharedPreferences.
  Future<void> _chargerConseilIANotifies() async {
    final prefs = await SharedPreferences.getInstance();
    final list  = prefs.getStringList(_conseilIANotifiesKey) ?? [];
    _conseilIANotifies.addAll(list);
  }

  /// Sauvegarde les courseKeys notifiées.
  Future<void> _sauvegarderConseilIANotifies() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_conseilIANotifiesKey, _conseilIANotifies.toList());
  }

  /// Réinitialise les courseKeys notifiées (appelé au changement de jour).
  Future<void> _resetConseilIANotifiesIfNewDay() async {
    final prefs   = await SharedPreferences.getInstance();
    final today   = DateTime.now();
    final todayKey = '${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';
    final stored  = prefs.getString(_conseilIANotifiesKey + '_date') ?? '';
    if (stored != todayKey) {
      _conseilIANotifies.clear();
      await prefs.setString(_conseilIANotifiesKey + '_date', todayKey);
      await _sauvegarderConseilIANotifies();
    }
  }

  /// ★ v10.23 — Résumé matinal : combien de courses correspondent aux critères.
  /// Appelé à la 1ère connexion du jour depuis HomeScreen.
  /// Retourne le message IA à afficher dans la bulle (ou null si rien à dire).
  Future<String?> verifierCoursesConseilIA(List<ZtReunion> reunions) async {
    if (!_config.activerConseilIA) return null;
    await _resetConseilIANotifiesIfNewDay();
    await _chargerConseilIANotifies();

    final courses = _filtrerCoursesSelonCriteresConseils(reunions);

    // ── Résumé matinal (1 fois par jour) ────────────────────────────
    final prefs   = await SharedPreferences.getInstance();
    final today   = DateTime.now();
    final todayKey = '${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';
    final resumeDate = prefs.getString(_conseilIAResumeDateKey) ?? '';
    String? messageBulle;

    if (resumeDate != todayKey) {
      await prefs.setString(_conseilIAResumeDateKey, todayKey);
      if (courses.isEmpty) {
        messageBulle = '🎯 Aucune course ne correspond à tes critères pour aujourd\'hui.';
      } else {
        final n = courses.length;
        final noms = courses.take(2).map((c) => c.course.nom.split(' ').take(3).join(' ')).join(', ');
        messageBulle = '🎯 $n course${n > 1 ? 's correspondent' : ' correspond'} à tes critères aujourd\'hui : $noms${n > 2 ? '...' : ''}.';
      }
    }

    return messageBulle;
  }

  /// ★ v10.23 — Vérification continue : notifie seulement les NOUVELLES courses.
  /// Appelé à chaque refresh des données (DataRefreshService).
  Future<void> verifierNouvellesCoursesConseilIA(List<ZtReunion> reunions) async {
    if (!_config.activerConseilIA) return;
    await _resetConseilIANotifiesIfNewDay();
    await _chargerConseilIANotifies();

    final courses = _filtrerCoursesSelonCriteresConseils(reunions);

    for (final item in courses) {
      final key = '${item.course.nom}_${item.reunion.lieu}';
      if (_conseilIANotifies.contains(key)) continue; // déjà notifié

      _conseilIANotifies.add(key);

      // Score top 1
      final score = item.course.partantsParRangIA.isNotEmpty
          ? item.course.partantsParRangIA.first.scoreIA.round()
          : 0;
      final typePari = _getTypePariPourCourse(item.course);
      final alertId  = 'conseil_ia_${key.replaceAll(' ', '_')}';

      _addAlert(AppAlert(
        id:        alertId,
        type:      AlertType.conseilIA,
        titre:     '🎯 Nouvelle course dans tes critères',
        message:   '${item.course.nom} — $score% confiance, $typePari\n${item.reunion.lieu} • ${item.course.heure}',
        timestamp: DateTime.now(),
      ));
    }

    if (courses.isNotEmpty) {
      await _sauvegarderConseilIANotifies();
    }
  }

  /// Filtre les courses selon les critères Conseils IA sauvegardés en prefs.
  List<({ZtCourse course, ZtReunion reunion})> _filtrerCoursesSelonCriteresConseils(
      List<ZtReunion> reunions) {
    // Lire les critères sauvegardés (même clés que conseils_screen.dart)
    return _coursesMatchingConseils;
  }

  // Cache synchrone des courses matchant les critères — mis à jour par
  // checkCoursesConseilIA() depuis DataRefreshService.
  List<({ZtCourse course, ZtReunion reunion})> _coursesMatchingConseils = [];

  /// Recalcule les courses correspondant aux critères Conseils IA.
  /// Appelé après chaque refresh. Retourne le nombre de courses trouvées.
  Future<int> recalculerCoursesConseilIA(List<ZtReunion> reunions) async {
    final prefs    = await SharedPreferences.getInstance();

    // ★ v9.93 : si le bouton ON/OFF Conseils IA est sur OFF,
    // on vide la liste → pas d'alerte Dernière chance.
    // Important : les 2 systèmes restent INDÉPENDANTS —
    // l'option "Alerte Conseil IA" dans Mes Paris fonctionne toujours.
    final filtresActifs = prefs.getBool('conseils_filtres_actifs') ?? true;
    if (!filtresActifs) {
      _coursesMatchingConseils = [];
      notifyListeners();
      return 0;
    }

    final types    = prefs.getStringList('conseils_filtres_types_paris')  ?? [];
    final hippos   = prefs.getStringList('conseils_filtres_hippodromes')  ?? [];
    final discs    = prefs.getStringList('conseils_filtres_disciplines')  ?? [];
    final confMin  = prefs.getInt('conseils_filtres_confiance_min')       ?? 0;

    final result   = <({ZtCourse course, ZtReunion reunion})>[];

    for (final r in reunions) {
      for (final c in r.courses) {
        if (c.partants.isEmpty) continue;
        final score   = c.partantsParRangIA.isNotEmpty ? c.partantsParRangIA.first.scoreIA : 0.0;
        final typePari = _getTypePariPourCourse(c);
        final hippo   = r.lieu.toUpperCase();
        final disc    = r.discipline.isEmpty ? '' :
            r.discipline[0].toUpperCase() + r.discipline.substring(1).toLowerCase();

        if (types.isNotEmpty  && !types.contains(typePari)) continue;
        if (confMin > 0       && score < confMin)           continue;
        if (hippos.isNotEmpty && !hippos.contains(hippo))   continue;
        if (discs.isNotEmpty  && !discs.contains(disc))     continue;

        result.add((course: c, reunion: r));
      }
    }

    _coursesMatchingConseils = result;
    notifyListeners(); // met à jour le bandeau HomeScreen
    return result.length;
  }

  /// Getter public pour le bandeau HomeScreen.
  List<({ZtCourse course, ZtReunion reunion})> get coursesConseilIA => _coursesMatchingConseils;

  /// Résumé des critères actifs pour l'affichage (bandeau + UI alertes).
  Future<Map<String, dynamic>> getCriteresConseilIA() async {
    final prefs   = await SharedPreferences.getInstance();
    final types   = prefs.getStringList('conseils_filtres_types_paris')  ?? [];
    final hippos  = prefs.getStringList('conseils_filtres_hippodromes')  ?? [];
    final discs   = prefs.getStringList('conseils_filtres_disciplines')  ?? [];
    final confMin = prefs.getInt('conseils_filtres_confiance_min')       ?? 0;
    return {
      'types':    types,
      'hippos':   hippos,
      'discs':    discs,
      'confMin':  confMin,
      'actifs':   types.isNotEmpty || hippos.isNotEmpty || discs.isNotEmpty || confMin > 0,
    };
  }

  /// Calcule le type de pari recommandé pour une course (copie de conseils_screen).
  String _getTypePariPourCourse(ZtCourse course) {
    final sorted = course.partantsParRangIA;
    if (sorted.isEmpty) return 'À surveiller';
    final score  = sorted.first.scoreIA;
    final score2 = sorted.length >= 2 ? sorted[1].scoreIA : 0.0;
    final score3 = sorted.length >= 3 ? sorted[2].scoreIA : 0.0;
    final score4 = sorted.length >= 4 ? sorted[3].scoreIA : 0.0;
    final ecart12 = (score - score2).abs();
    final estEquilibre = !course.isQuinte && ecart12 <= 15 && score >= 60 && score2 >= 50;
    final cote = sorted.first.coteDecimale;

    // ★ v9.93 : Course classique sans Quarté/Quinté → limiter au Tiercé max
    if (course.isClassiqueSansMultiple) {
      if (score >= 75 && score2 >= 55 && score3 >= 45) return 'Tiercé';
      if (estEquilibre && score >= 75) return 'Couplé Gagnant';
      if (estEquilibre && score >= 60) return 'Couplé Placé';
      if (score >= 80 && cote <= 8.0) return 'Simple Gagnant';
      if (score >= 80) return 'Gagnant+Placé';
      if (score >= 65) return 'Simple Placé';
      if (score >= 50) return 'Gagnant+Placé';
      return 'À surveiller';
    }

    if (course.isQuinte) {
      if (score >= 75 && score2 >= 60 && score3 >= 55) return 'Quinté+';
      if (score >= 65 && score2 >= 55) return 'Quarté+';
      if (score >= 55 && score2 >= 50) return 'Tiercé';
      if (score >= 45) return 'Couplé Gagnant';
      return 'À surveiller';
    } else if (course.isQuarte) {
      if (score >= 60 && score2 >= 50 && score3 >= 40 && score4 >= 35) return 'Quarté+';
      if (score >= 55 && score2 >= 45 && score3 >= 35) return 'Tiercé';
      if (score >= 45) return 'Couplé Gagnant';
      return 'À surveiller';
    } else if (score >= 65 && score2 >= 60 && score3 >= 55 && score4 >= 50 && course.partants.length >= 10) {
      return 'Quarté+';
    } else if (estEquilibre && score >= 75) {
      return 'Couplé Gagnant';
    } else if (estEquilibre && score >= 60) {
      return 'Couplé Placé';
    } else if (score >= 80 && cote <= 8.0) {
      return 'Simple Gagnant';
    } else if (score >= 80) {
      return 'Gagnant+Placé';
    } else if (score >= 65) {
      return 'Simple Placé';
    } else if (score >= 50) {
      return 'Gagnant+Placé';
    } else if (score >= 35) {
      return 'Tiercé';
    }
    return 'À surveiller';
  }

  // ── ★ v10.24 : Feature #2 — Alerte "Cote qui chute" ─────────────────────────
  // Clé anti-doublon : 1 alerte par cheval par session
  final Set<String> _coteChuteNotifies = {};

  /// Vérifie les mouvements de cotes et notifie si chute ≥ 20% sur 1h.
  /// Appelé par CoteTrackerService via callback (pas d'import circulaire).
  void verifierCotesChute() {
    if (!_config.activerCoteChute) return;
    final fn = _getCotesChute;
    if (fn == null) return;

    final mouvements = fn();
    for (final m in mouvements) {
      final courseKey  = m['courseKey']  as String? ?? '';
      final nomCourse  = m['nomCourse']  as String? ?? '';
      final hippodrome = m['hippodrome'] as String? ?? '';
      final numero     = m['numero']     as String? ?? '';
      final nom        = m['nom']        as String? ?? '';
      final coteDebut  = (m['coteDebut']  as num?)?.toDouble() ?? 0.0;
      final coteFin    = (m['coteFin']    as num?)?.toDouble() ?? 0.0;
      final variation  = (m['variationPct'] as num?)?.toDouble() ?? 0.0;

      // Seuil : baisse ≥ 20% (forte_baisse ou effondrement)
      if (variation > -20) continue;

      final alertId = '${courseKey}_cote_chute_$numero';
      if (_coteChuteNotifies.contains(alertId)) continue;
      _coteChuteNotifies.add(alertId);

      final emoji = variation <= -40 ? '🔥' : '📉';
      final label = variation <= -40 ? 'Effondrement' : 'Forte baisse';
      final deltaStr = '${variation.toStringAsFixed(0)}%';

      int? numR, numC;
      final mKey = RegExp(r'R(\d+)C(\d+)').firstMatch(courseKey);
      if (mKey != null) {
        numR = int.tryParse(mKey.group(1)!);
        numC = int.tryParse(mKey.group(2)!);
      }

      _addAlert(AppAlert(
        id:      alertId,
        type:    AlertType.coteBaisse,
        titre:   '$emoji $label cote — N°$numero $nom',
        message: 'Cote : ${coteDebut.toStringAsFixed(1)} → ${coteFin.toStringAsFixed(1)} ($deltaStr)\n'
                 '$nomCourse — $hippodrome\n'
                 'Signal d\'argent informé — vérifiez le pronostic IA',
        timestamp: DateTime.now(),
        numReunion: numR,
        numCourse:  numC,
      ));

      if (kDebugMode) debugPrint('[AlertService] 📉 Cote chute: N°$numero $nom $deltaStr dans $courseKey');
    }
  }

  // ── ★ v10.24 : Feature #9 — Rappel quotidien à heure fixe ───────────────────
  /// Démarre ou redémarre le timer de rappel quotidien.
  /// Appelé à chaque modification de la config.
  void _demarrerRappelQuotidien() {
    _rappelTimer?.cancel();
    _rappelTimer = null;
    if (!_config.activerRappelQuotidien) return;

    // Vérifier toutes les minutes si l'heure de rappel est atteinte
    _rappelTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _verifierRappelQuotidien();
    });
    _verifierRappelQuotidien();
  }

  void _verifierRappelQuotidien() {
    if (!_config.activerRappelQuotidien) return;
    final now = DateTime.now();
    if (now.hour != _config.rappelHeure || now.minute != _config.rappelMinute) return;

    // Anti-doublon : 1 rappel par jour
    final todayKey = 'rappel_quotidien_${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}';
    if (_sentAlertIds.contains(todayKey)) return;

    // Compter les courses disponibles aujourd'hui
    final nb = _coursesMatchingConseils.length;
    final nbStr = nb > 0 ? '$nb course${nb > 1 ? "s" : ""} dans tes critères' : 'Consulte les pronostics du jour';

    _addAlert(AppAlert(
      id:      todayKey,
      type:    AlertType.rappelMise,
      titre:   '🌅 Bonjour — Pronostics du jour disponibles',
      message: '$nbStr\nOuvre l\'app pour voir les conseils IA.',
      timestamp: now,
    ));
  }

  void markAllRead() {
    for (final a in _alerts) {
      a.isRead = true;
    }
    notifyListeners();
    _save();
  }

  void markRead(String id) {
    final idx = _alerts.indexWhere((a) => a.id == id);
    if (idx >= 0) {
      _alerts[idx].isRead = true;
      notifyListeners();
      _save();
    }
  }

  /// Supprimer une alerte individuelle par son ID
  void deleteAlert(String id) {
    _alerts.removeWhere((a) => a.id == id);
    notifyListeners();
    _save();
  }

  void clearHistory() {
    _alerts.clear();
    _sentAlertIds.clear();
    notifyListeners();
    _save();
  }

  // ── Watchdog : vérifie les alertes toutes les 60 secondes ────────────────

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _checkAlerts();
    });
    // ★ v10.24 : démarrer le timer de rappel quotidien
    _demarrerRappelQuotidien();
    // Vérifier immédiatement
    _checkAlerts();
  }

  /// ★ v10.16 : Filtre multi-flags — OR entre les options cochées.
  /// Si aucun flag activé → fallback toutes les courses (sécurité).
  /// scopeToutes  = true → toujours accepté
  /// scopeSuivies = true → accepté si mise engagée > 0
  /// scopeFavoris = true → accepté si dans hippique_favorites_v1
  bool _coursePasseFiltre(TrackedCourse tc) {
    // Fallback : si aucune case cochée, on laisse tout passer
    final aucunFlag = !_config.scopeToutes && !_config.scopeFavoris && !_config.scopeSuivies;
    if (aucunFlag || _config.scopeToutes) return true;

    // Vérification favoris
    if (_config.scopeFavoris) {
      final estFavori = _favorisSet.any(
        (f) => f['numR'] == tc.numReunion && f['numC'] == tc.numCourse,
      );
      if (estFavori) return true;
    }

    // Vérification suivies (avec mise engagée)
    if (_config.scopeSuivies) {
      if (tc.miseEngagee != null && tc.miseEngagee! > 0) return true;
    }

    return false;
  }

  /// ★ v9.94 : Accès public pour data_refresh_service (bulles nonPartant scope)
  bool coursePasseFiltrePublic(String courseKey) => _coursePasseFiltreByCourseKey(courseKey);

  /// ★ v10.20 — Variante du filtre scope utilisant directement la courseKey
  /// (format "R{n}C{n}...") pour les alertes externes (non-partants, convergence).
  /// Utilisée par ajouterAlertNonPartant() et ajouterAlertConvergenceIACote()
  /// qui reçoivent une courseKey mais pas un objet TrackedCourse.
  bool _coursePasseFiltreByCourseKey(String courseKey) {
    // Fallback sécurité : aucun flag → laisser passer
    final aucunFlag = !_config.scopeToutes && !_config.scopeFavoris && !_config.scopeSuivies;
    if (aucunFlag || _config.scopeToutes) return true;

    // Extraire numR / numC depuis la courseKey (ex: "R3C5_...")  
    final m = RegExp(r'R(\d+)C(\d+)').firstMatch(courseKey);
    final numR = m != null ? int.tryParse(m.group(1)!) : null;
    final numC = m != null ? int.tryParse(m.group(2)!) : null;

    // Vérification favoris : numR + numC dans _favorisSet
    if (_config.scopeFavoris && numR != null && numC != null) {
      final estFavori = _favorisSet.any(
        (f) => f['numR'] == numR && f['numC'] == numC,
      );
      if (estFavori) return true;
    }

    // Vérification suivies : course présente dans _trackedCourses avec mise > 0
    if (_config.scopeSuivies) {
      final tc = _trackedCourses.values.where((t) =>
        t.numReunion == numR && t.numCourse == numC
      ).firstOrNull;
      if (tc != null && tc.miseEngagee != null && tc.miseEngagee! > 0) return true;
    }

    return false;
  }

  // Cache des favoris chargé au démarrage et mis à jour en tâche de fond
  List<Map<String, dynamic>> _favorisSet = [];

  /// Recharge le cache des favoris depuis SharedPreferences
  Future<void> _rechargerFavoris() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_favoritesKey) ?? '[]';
      final List<dynamic> list = json.decode(raw) as List<dynamic>;
      _favorisSet = list.cast<Map<String, dynamic>>();
    } catch (_) {}
  }

  void _checkAlerts() {
    // Rafraîchir le cache favoris de manière asynchrone à chaque cycle
    _rechargerFavoris();
    // ★ v10.24 : vérification rappel quotidien
    _verifierRappelQuotidien();
    final now = DateTime.now();

    // ★ v10.24 : Feature #10 — Alerte "Dernière chance"
    // Vérifier les courses des critères Conseils IA qui partent dans 25-35 min
    // et pour lesquelles aucun pari n'a encore été enregistré
    if (_config.activerDerniereChance) {
      for (final item in _coursesMatchingConseils) {
        final diffMin = item.course.heureDateTime.difference(now).inMinutes;
        // Fenêtre 25-35 min avant départ
        if (diffMin < 25 || diffMin > 35) continue;

        // Vérifier qu'aucun pari n'est déjà enregistré pour cette course
        final estMise = _trackedCourses.values.any((tc) =>
          tc.numCourse == item.course.numCourse &&
          tc.hippodrome.toUpperCase() == item.reunion.lieu.toUpperCase() &&
          tc.miseEngagee != null &&
          tc.miseEngagee! > 0
        );
        if (estMise) continue;

        final alertId = 'derniere_chance_${item.course.nom}_${item.reunion.lieu}_${now.year}${now.month}${now.day}';
        final top = item.course.partantsParRangIA.isNotEmpty
            ? item.course.partantsParRangIA.first
            : null;
        final topStr = top != null
            ? ' — N°${top.numero} ${top.nom} (${top.scoreIA.round()}%)'
            : '';

        _addAlert(AppAlert(
          id:      alertId,
          type:    AlertType.derniereChance,
          titre:   '⏰ Dernière chance ! Départ dans $diffMin min',
          message: '${item.course.nom}$topStr\n'
                   '${item.reunion.lieu} • ${item.course.heure}\n'
                   'Cette course est dans tes critères — tu n\'as pas encore misé.',
          timestamp: now,
        ));
      }
    }

    for (final tc in _trackedCourses.values) {
      // ── Filtre périmètre : sauter les courses hors scope ──
      if (!_coursePasseFiltre(tc)) continue;
      final diff = tc.heureDepart.difference(now);
      final diffMin = diff.inMinutes;

      // Alerte imminente (X min avant)
      // ★ v9.93 : UNE SEULE alerte par course — ID fixe basé sur la course uniquement.
      // L'ancien système de "tranches" générait 2-3 alertes (10 min + 5 min + 1 min)
      // car chaque tranche produisait un ID différent (_imminent_t2, _imminent_t1…).
      // Désormais l'ID est stable toute la durée d'approche → 1 seule entrée dans la liste.
      if (_config.activerCourseImminente) {
        final threshold = _config.minutesAvantDepart;
        if (diffMin <= threshold && diffMin > 0) {
          // ID stable : ne change jamais pour cette course → _addAlert est idempotent
          final alertId = '${(tc.storageKey ?? tc.key)}_imminent';
          // ★ v9.94 Amél. 5 : Ligne cheval parié OU favori IA
          final String favorIaLine;
          if (tc.nomCheval != null) {
            // Pari existant : nom du cheval + score IA si disponible
            final scoreStr = (tc.scoreIA > 0)
                ? ' (${tc.scoreIA.round()} pts IA)'
                : '';
            favorIaLine = 'Votre cheval : ${tc.nomCheval}$scoreStr';
          } else {
            // Pas de pari : chercher le favori IA depuis la mémoire
            final courseKey = 'R${tc.numReunion}C${tc.numCourse}';
            final prono = IaMemoryService.instance.getPronostic(courseKey);
            if (prono != null &&
                prono.favoriIaNom != null &&
                prono.favoriIaNom!.isNotEmpty) {
              // Récupérer le score du favori (numéro le mieux classé dans scoresIA)
              double scoreFavori = 0;
              if (prono.scoresIA.isNotEmpty) {
                scoreFavori = prono.scoresIA.values
                    .reduce((a, b) => a > b ? a : b);
              }
              final scoreStr = scoreFavori > 0
                  ? ' (${scoreFavori.round()} pts)'
                  : '';
              favorIaLine = '⭐ Favori IA : ${prono.favoriIaNom}$scoreStr';
            } else {
              favorIaLine = '';
            }
          }
          _addAlert(AppAlert(
            id: alertId,
            type: AlertType.courseImminente,
            titre: '⏰ Départ dans $diffMin min',
            message: '${tc.nomCourse}\n${tc.hippodrome} — ${_formatHeure(tc.heureDepart)}'
                     '${favorIaLine.isNotEmpty ? "\n$favorIaLine" : ""}',
            timestamp: now,
            numReunion: tc.numReunion,
            numCourse:  tc.numCourse,
            dateStrCourse: _dateStrYYYYMMDD(tc.heureDepart),
            heureDepart: tc.heureDepart,
          ));
        }
      }

      // Alerte départ (dans la minute qui suit l'heure prévue)
      if (_config.activerCourseCommence) {
        if (diffMin <= 0 && diffMin >= -2) {
          // ★ v9.94 Amél. 5 (cohérence) : cheval parié OU favori IA au départ
          final String selectionDepart;
          if (tc.nomCheval != null) {
            selectionDepart = 'Votre sélection : ${tc.nomCheval}';
          } else {
            final courseKeyD = 'R${tc.numReunion}C${tc.numCourse}';
            final pronoD = IaMemoryService.instance.getPronostic(courseKeyD);
            if (pronoD != null &&
                pronoD.favoriIaNom != null &&
                pronoD.favoriIaNom!.isNotEmpty) {
              selectionDepart = '⭐ Favori IA : ${pronoD.favoriIaNom}';
            } else {
              selectionDepart = '';
            }
          }
          _addAlert(AppAlert(
            id: '${(tc.storageKey ?? tc.key)}_depart_${tc.heureDepart.day}${tc.heureDepart.hour}${tc.heureDepart.minute}',
            type: AlertType.courseCommence,
            titre: '🏇 C\'est parti !',
            message: '${tc.nomCourse} démarre maintenant !'
                     '${selectionDepart.isNotEmpty ? "\n$selectionDepart" : ""}\n'
                     '${tc.hippodrome}',
            timestamp: now,
            numReunion: tc.numReunion,
            numCourse:  tc.numCourse,
            dateStrCourse: _dateStrYYYYMMDD(tc.heureDepart),
            heureDepart: tc.heureDepart,
          ));
        }
      }

      // Alerte en cours — UNE SEULE notification par course (ID fixe, sans diffMin)
      if (_config.activerCourseEnCours) {
        if (diffMin < -2 && diffMin > -30) {
          // ★ Fix doublon : alertId fixe basé sur la clé de course uniquement
          // L'ancienne formule `_encours_${diffMin ~/ 3}` générait un nouvel ID
          // à chaque cycle (ex: _encours_-1, _encours_-2…) → spam de notifications.
          // Désormais l'ID est stable : une seule alerte par course.
          // ★ Fix alertes doublons : storageKey unique par pari
          final alertId = '${(tc.storageKey ?? tc.key)}_encours';
          _addAlert(AppAlert(
            id: alertId,
            type: AlertType.courseEnCours,
            titre: '🔴 Course en cours',
            message: '${tc.nomCourse} — ${tc.hippodrome}\n'
                     '${tc.nomCheval != null ? "Votre cheval : ${tc.nomCheval}" : ""}',
            timestamp: now,
            numReunion: tc.numReunion,
            numCourse:  tc.numCourse,
            dateStrCourse: _dateStrYYYYMMDD(tc.heureDepart),
            heureDepart: tc.heureDepart,
          ));
        }
      }

      // ── Récupération automatique du résultat ──────────────────────────
      // ★ Fix délai : on tente l'API dès -10 min (résultats PMU souvent dispo à H+5/10)
      // L'ancienne valeur -25 retardait inutilement la clôture du pari.
      // En cas d'échec (API pas encore prête) le resultKey est retiré → retry au prochain cycle.
      if (_config.activerResultats && diffMin <= -10) {
        // ★ Fix : storageKey unique pour le résultat de chaque pari
        final resultKey = '${(tc.storageKey ?? tc.key)}_${tc.heureDepart.day}${tc.heureDepart.month}${tc.heureDepart.year}';
        if (!_resultatsVerifies.contains(resultKey)) {
          _resultatsVerifies.add(resultKey);
          _fetchResultatAuto(tc, resultKey);
        }
      }

      // ── Détection DQ / Retrait / Blessure PENDANT la course ──────────
      // Polling léger : on interroge l'API statuts uniquement pendant
      // la fenêtre [-2 min … -30 min] pour détecter les chevaux hors course.
      // Quand un nouveau DQ est détecté : notification + re-analyse IA.
      if (diffMin < -1 && diffMin > -35) {
        _detecterDisqPendantCourse(tc);
      }
    }
    notifyListeners();
  }

  // ── Détection des DQ / Retraits / Blessures en cours de course ─────────────
  /// Interroge l'API statuts des partants pendant la course.
  /// Si un nouveau cheval est DQ/ARRETE/TOMBE par rapport au dernier état connu :
  ///  1. Envoie une notification "Alerte DQ"
  ///  2. Déclenche la re-analyse IA sans ce cheval
  ///
  /// Fréquence : appelé à chaque tick du watchdog (60 s) pendant [-2 … -35 min]
  /// mais le polling réseau n'est fait qu'une fois par minute (protection anti-spam).
  Future<void> _detecterDisqPendantCourse(TrackedCourse tc) async {
    final courseKey = tc.key;

    // Anti-spam : une seule requête à la fois par course
    if (_reanalyseEnCours.contains(courseKey)) return;
    _reanalyseEnCours.add(courseKey);

    try {
      final statuts = await ZoneTurfService.chargerStatutsPartants(
        heureDepart: tc.heureDepart,
        numReunion: tc.numReunion,
        numCourse: tc.numCourse,
      );

      if (statuts == null) return;

      // Statuts "hors course" qu'on veut détecter
      const statutsHorsCourse = {
        'DISQUALIFIE', 'DISQUALIFIED', 'ARRETE', 'TOMBE', 'NON_PARTANT', 'RETRAIT'
      };

      // Numéros actuellement hors course selon l'API
      final nouveauxHorsCourse = <int>[];
      for (final entry in statuts.entries) {
        if (statutsHorsCourse.contains(entry.value.toUpperCase())) {
          nouveauxHorsCourse.add(entry.key);
        }
      }

      if (nouveauxHorsCourse.isEmpty) return;

      // Comparer avec ce qu'on connaît déjà pour cette course
      final dejaConnus = _disqDetectes[courseKey] ?? {};
      final vraimentNouveaux = nouveauxHorsCourse
          .where((n) => !dejaConnus.contains(n))
          .toList();

      if (vraimentNouveaux.isEmpty) return;

      // Mettre à jour notre état connu
      _disqDetectes[courseKey] = {...dejaConnus, ...vraimentNouveaux};

      // Séparer DQ (pendant la course) des retraits (avant départ)
      final disqPendant = <int>[];
      final retraitsAvant = <int>[];
      for (final n in vraimentNouveaux) {
        final s = statuts[n]?.toUpperCase() ?? '';
        if (s == 'NON_PARTANT' || s == 'RETRAIT') {
          retraitsAvant.add(n);
        } else {
          disqPendant.add(n);
        }
      }

      // ── Notification utilisateur ──────────────────────────────────────
      if (disqPendant.isNotEmpty) {
        final numsStr = disqPendant.map((n) => 'N°$n').join(', ');
        final alertId = '${courseKey}_disq_${disqPendant.join("_")}';
        _addAlert(AppAlert(
          id: alertId,
          type: AlertType.courseEnCours,
          titre: '⚠️ Disqualification — ${tc.nomCourse}',
          message: '$numsStr disqualifié(s) dans ${tc.nomCourse}\n'
                   '${tc.hippodrome}\n'
                   'Nouveau pronostic IA en cours de calcul…',
          timestamp: DateTime.now(),
          numReunion: tc.numReunion,
          numCourse:  tc.numCourse,
          dateStrCourse: _dateStrYYYYMMDD(tc.heureDepart),
        ));
        if (kDebugMode) {
          if (kDebugMode) debugPrint('[AlertService] DQ détecté: $numsStr dans $courseKey');
        }
      }

      if (retraitsAvant.isNotEmpty) {
        final numsStr = retraitsAvant.map((n) => 'N°$n').join(', ');
        final alertId = '${courseKey}_retrait_${retraitsAvant.join("_")}';
        _addAlert(AppAlert(
          id: alertId,
          type: AlertType.courseImminente,
          titre: '⚠️ Retrait — ${tc.nomCourse}',
          message: '$numsStr retiré(s) de ${tc.nomCourse}\n'
                   '${tc.hippodrome}\n'
                   'Nouveau pronostic IA en cours de calcul…',
          timestamp: DateTime.now(),
          numReunion: tc.numReunion,
          numCourse:  tc.numCourse,
          dateStrCourse: _dateStrYYYYMMDD(tc.heureDepart),
        ));
      }

      // ── Re-analyse IA ───────────────────────────────────────────────────
      // On demande à DataRefreshService de recalculer le pronostic.
      // DataRefreshService récupère les partants actifs et recalcule les scores.
      // On passe par la clé de la course pour trouver la ZtCourse correspondante.
      await _triggerReanalyseCourse(
        tc: tc,
        disqualifies: disqPendant,
        retraits: retraitsAvant,
      );

    } catch (e) {
      if (kDebugMode) debugPrint('[AlertService] _detecterDisqPendantCourse: $e');
    } finally {
      _reanalyseEnCours.remove(courseKey);
    }
  }

  /// Déclenche la re-analyse IA après un DQ/retrait.
  /// Cherche la ZtCourse dans DataRefreshService, sinon construit une version
  /// minimale pour forcer un rechargement des partants depuis l'API.
  Future<void> _triggerReanalyseCourse({
    required TrackedCourse tc,
    List<int> disqualifies = const [],
    List<int> retraits = const [],
  }) async {
    try {
      // Construire la courseKey au format IaMemoryService
      final d = tc.heureDepart;
      final dj = d.day.toString().padLeft(2, '0');
      final dm = d.month.toString().padLeft(2, '0');
      final memKey = 'R${tc.numReunion}C${tc.numCourse}_$dj$dm${d.year}';

      // Chercher la ZtCourse dans DataRefreshService.
      // On identifie la course par son numéro ET son heure de départ
      // (ZtCourse n'a pas de numReunion, on utilise l'heure comme discriminant).
      ZtCourse? ztCourse;
      final reunions = DataRefreshService.instance.reunions;
      for (final reunion in reunions) {
        // Vérifier le numéro de réunion via le code "R1", "R2", etc.
        final numRMatch = RegExp(r'R(\d+)').firstMatch(reunion.code);
        final numR = numRMatch != null
            ? int.tryParse(numRMatch.group(1) ?? '') ?? 0
            : 0;
        if (numR != tc.numReunion) continue;

        for (final course in reunion.courses) {
          if (course.numCourse == tc.numCourse) {
            ztCourse = course;
            break;
          }
        }
        if (ztCourse != null) break;
      }

      if (ztCourse == null) {
        // Course introuvable en mémoire → déclencher un refresh du programme
        // qui rechargera automatiquement les partants (sans les DQ)
        if (kDebugMode) {
          if (kDebugMode) debugPrint('[AlertService] Course $memKey introuvable en mémoire → refresh programme');
        }
        await DataRefreshService.instance.refresh();
        return;
      }

      // Déclencher la re-analyse avec les partants actifs
      await DataRefreshService.instance.reAnalyserCourse(
        courseKey: memKey,
        course: ztCourse,
        disqualifies: disqualifies,
        retraits: retraits,
      );

      // Mettre à jour la notification précédente pour confirmer le recalcul
      if (disqualifies.isNotEmpty || retraits.isNotEmpty) {
        final tous = [...disqualifies, ...retraits];
        final alertId = '${tc.key}_reanalyse';
        _addAlert(AppAlert(
          id: alertId,
          type: AlertType.courseEnCours,
          titre: '🔄 Pronostic IA mis à jour — ${tc.nomCourse}',
          message: 'Suite au retrait de ${tous.map((n) => "N°$n").join(", ")}\n'
                   'Le pronostic IA a été recalculé sans ces chevaux.\n'
                   'Consultez la fiche course pour les nouvelles recommandations.',
          timestamp: DateTime.now(),
          numReunion: tc.numReunion,
          numCourse:  tc.numCourse,
          dateStrCourse: _dateStrYYYYMMDD(tc.heureDepart),
        ));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AlertService] _triggerReanalyseCourse: $e');
    }
  }

  /// Interroge l'API PMU pour récupérer le résultat officiel de la course
  Future<void> _fetchResultatAuto(TrackedCourse tc, String resultKey) async {
    try {
      // Formater la date au format PMU : JJMMAAAA
      final d = tc.heureDepart;
      final dateStr =
          '${d.day.toString().padLeft(2, '0')}'
          '${d.month.toString().padLeft(2, '0')}'
          '${d.year}';

      final url =
          'https://turfinfo.api.pmu.fr/rest/client/7'
          '/programme/$dateStr'
          '/R${tc.numReunion}/C${tc.numCourse}'
          '/rapports-definitifs?specialisation=INTERNET';

      final resp = await http
          .get(Uri.parse(url),
              headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        // API pas encore disponible — on réessaiera au prochain cycle
        _resultatsVerifies.remove(resultKey);
        return;
      }

      final List<dynamic> rapports =
          jsonDecode(resp.body) as List<dynamic>;

      // ── Extraire TOUS les résultats utiles depuis l'API PMU ──────────────
      String? numGagnant;
      double? coteGagnant;
      double? cotePlace;           // cote Placé réelle PMU
      final List<int> arriveeOfficielle = []; // ordre d'arrivée complet
      final List<int> placesOfficielles = [];  // top 3 placés
      double? dividendeTierce;         // Tiercé ORDRE
      double? dividendeTierceDesordre; // Tiercé DÉSORDRE
      double? dividendeQuarte;         // Quarté+ ORDRE
      double? dividendeQuarteDesordre; // Quarté+ DÉSORDRE
      double? dividendeQuinte;         // Quinté+ ORDRE
      double? dividendeQuinteDesordre; // Quinté+ DÉSORDRE
      double? dividendeQuinte4sur5;    // Quinté+ BONUS 4/5
      double? dividendeCouple;         // Couplé Gagnant
      double? dividendeCouplePlace;    // Couplé Placé

      for (final r in rapports) {
        final typePari = r['typePari'] as String? ?? '';
        final rList = (r['rapports'] as List<dynamic>? ?? []);

        // ── Helper local : extraire dividende et combinaison ──────────────
        double? _div(Map<String, dynamic> rap) {
          final d = rap['dividendePourUnEuro'];
          return d != null ? (d as num).toDouble() / 100.0 : null;
        }
        void _extractCombo(String combo) {
          for (final part in combo.split('-')) {
            final n = int.tryParse(part.trim());
            if (n != null && !arriveeOfficielle.contains(n)) arriveeOfficielle.add(n);
          }
        }

        // ── Simple Gagnant → cheval N°1 + cote réelle ─────────────────────
        if (typePari == 'E_SIMPLE_GAGNANT' && rList.isNotEmpty) {
          final rap = rList.first as Map<String, dynamic>;
          numGagnant = rap['combinaison']?.toString();
          coteGagnant = _div(rap);
          final n = int.tryParse(numGagnant ?? '');
          if (n != null && !arriveeOfficielle.contains(n)) arriveeOfficielle.add(n);
        }

        // ── Simple Placé → top 3 + cote Placé réelle ──────────────────────
        if (typePari == 'E_SIMPLE_PLACE' && rList.isNotEmpty) {
          // On garde la cote du 1er cheval placé comme référence
          if (cotePlace == null && rList.isNotEmpty) {
            cotePlace = _div(rList.first as Map<String, dynamic>);
          }
          for (final p in rList) {
            final n = int.tryParse((p as Map)['combinaison']?.toString() ?? '');
            if (n != null) {
              placesOfficielles.add(n);
              if (!arriveeOfficielle.contains(n)) arriveeOfficielle.add(n);
            }
          }
        }

        // ── Tiercé ORDRE ──────────────────────────────────────────────────
        if (rList.isNotEmpty &&
            (typePari == 'E_TIERCE' || typePari == 'E_TIERCE_ORDRE' ||
             typePari == 'TIERCE'   || typePari == 'TIERCE_ORDRE') &&
            !typePari.contains('DESORDRE') && !typePari.contains('DÉSORDRE')) {
          final rap = rList.first as Map<String, dynamic>;
          dividendeTierce ??= _div(rap);
          _extractCombo(rap['combinaison']?.toString() ?? '');
        }

        // ── Tiercé DÉSORDRE ───────────────────────────────────────────────
        if (rList.isNotEmpty &&
            (typePari == 'TIERCE_DESORDRE' || typePari == 'E_TIERCE_DESORDRE' ||
             typePari == 'TIERCE_DÉSORDRE' || typePari.contains('TIERCE') &&
             (typePari.contains('DESORDRE') || typePari.contains('DÉSORDRE')))) {
          final rap = rList.first as Map<String, dynamic>;
          dividendeTierceDesordre ??= _div(rap);
        }

        // ── Quarté+ ORDRE ─────────────────────────────────────────────────
        if (rList.isNotEmpty &&
            (typePari == 'E_QUARTE' || typePari == 'E_QUARTE_PLUS' ||
             typePari == 'QUARTE'   || typePari == 'QUARTE_PLUS') &&
            !typePari.contains('DESORDRE') && !typePari.contains('DÉSORDRE')) {
          final rap = rList.first as Map<String, dynamic>;
          dividendeQuarte ??= _div(rap);
          _extractCombo(rap['combinaison']?.toString() ?? '');
        }

        // ── Quarté+ DÉSORDRE ──────────────────────────────────────────────
        if (rList.isNotEmpty &&
            (typePari == 'QUARTE_DESORDRE' || typePari == 'E_QUARTE_DESORDRE' ||
             typePari == 'QUARTE_DÉSORDRE' || typePari.contains('QUARTE') &&
             (typePari.contains('DESORDRE') || typePari.contains('DÉSORDRE')))) {
          final rap = rList.first as Map<String, dynamic>;
          dividendeQuarteDesordre ??= _div(rap);
        }

        // ── Quinté+ ORDRE ─────────────────────────────────────────────────
        if (rList.isNotEmpty &&
            (typePari == 'E_QUINTE' || typePari == 'E_QUINTE_PLUS' ||
             typePari == 'QUINTE'   || typePari == 'QUINTE_PLUS') &&
            !typePari.contains('DESORDRE') && !typePari.contains('DÉSORDRE') &&
            !typePari.contains('4SUR5') && !typePari.contains('4/5')) {
          final rap = rList.first as Map<String, dynamic>;
          dividendeQuinte ??= _div(rap);
          _extractCombo(rap['combinaison']?.toString() ?? '');
        }

        // ── Quinté+ DÉSORDRE ──────────────────────────────────────────────
        if (rList.isNotEmpty &&
            (typePari == 'QUINTE_DESORDRE' || typePari == 'E_QUINTE_DESORDRE' ||
             typePari == 'QUINTE_DÉSORDRE' || typePari.contains('QUINTE') &&
             (typePari.contains('DESORDRE') || typePari.contains('DÉSORDRE')))) {
          final rap = rList.first as Map<String, dynamic>;
          dividendeQuinteDesordre ??= _div(rap);
        }

        // ── Quinté+ BONUS 4/5 ─────────────────────────────────────────────
        if (rList.isNotEmpty &&
            (typePari.contains('4SUR5') || typePari.contains('4_SUR_5') ||
             typePari.contains('QUINTE') && typePari.contains('4'))) {
          final rap = rList.first as Map<String, dynamic>;
          dividendeQuinte4sur5 ??= _div(rap);
        }

        // ── Couplé Gagnant ────────────────────────────────────────────────
        if (rList.isNotEmpty &&
            (typePari == 'COUPLE_GAGNANT' || typePari == 'E_COUPLE_GAGNANT' ||
             typePari == 'COUPLÉ_GAGNANT' || typePari == 'COUPLE' ||
             typePari.contains('COUPLE') && typePari.contains('GAGNANT'))) {
          final rap = rList.first as Map<String, dynamic>;
          dividendeCouple ??= _div(rap);
        }

        // ── Couplé Placé ──────────────────────────────────────────────────
        if (rList.isNotEmpty &&
            (typePari == 'COUPLE_PLACE' || typePari == 'E_COUPLE_PLACE' ||
             typePari == 'COUPLÉ_PLACÉ' ||
             typePari.contains('COUPLE') && typePari.contains('PLACE'))) {
          final rap = rList.first as Map<String, dynamic>;
          dividendeCouplePlace ??= _div(rap);
        }
      }

      // Si pas de gagnant mais qu'on a l'arrivée complète (ex: résultat Tiercé/Quinté)
      // on peut quand même traiter le résultat
      if (numGagnant == null && arriveeOfficielle.isEmpty) {
        // Résultats pas encore disponibles → réessayer au prochain cycle
        _resultatsVerifies.remove(resultKey);
        return;
      }
      // Fallback : prendre le 1er de l'arrivée officielle si pas de Simple Gagnant
      if (numGagnant == null && arriveeOfficielle.isNotEmpty) {
        numGagnant = arriveeOfficielle.first.toString();
      }

      // ── Analyser le résultat selon le type de pari enregistré ───────────
      final mise = tc.miseEngagee ?? 0.0;
      final typePari = tc.typePari;
      final mesNumeros = tc.numerosJoues;
      final monNumero = tc.numeroCheval?.toString();

      // Top 3 officiels (pour Tiercé, Placé)
      final top3 = arriveeOfficielle.take(3).toList();
      final top4 = arriveeOfficielle.take(4).toList();
      final top5 = arriveeOfficielle.take(5).toList();

      // Résumé de l'arrivée à afficher
      final arriveeStr = arriveeOfficielle.take(5).map((n) => 'N°$n').join(' - ');

      String titre;
      String messageResultat;
      AlertType alertType;
      double gainNet = 0.0;

      // ── CAS 1 : Simple Gagnant / Placé ─────────────────────────────────
      // Aussi déclenché si le pari est Tiercé/Quarté/Quinté mais avec 1 seul numéro
      // (fallback rétrocompatible pour les anciens paris sans numerosJoues)
      final estPariMulti = (typePari == 'Tiercé' || typePari == 'Quarté+' || typePari == 'Quinté+')
                           && mesNumeros.length >= 3;
      final estCouple = (typePari == 'Couplé Gagnant' || typePari == 'Couplé Placé')
                        && mesNumeros.length >= 2;
      if (estCouple) {
        // ── CAS Couplé Gagnant : les 2 chevaux dans le top 2 ──────────────
        // ── CAS Couplé Placé   : les 2 chevaux dans le top 3 ──────────────
        final mesNums = mesNumeros.take(2).toSet();
        final top2Set = arriveeOfficielle.take(2).toSet();
        final top3Set = arriveeOfficielle.take(3).toSet();
        final estCoupleGagne = typePari == 'Couplé Gagnant'
            ? mesNums.length == 2 && mesNums.containsAll(top2Set) && top2Set.containsAll(mesNums)
            : mesNums.length == 2 && mesNums.every((n) => top3Set.contains(n));
        if (estCoupleGagne) {
          // Dividende réel PMU si disponible, sinon estimation
          final divC = typePari == 'Couplé Gagnant' ? dividendeCouple : dividendeCouplePlace;
          if (divC != null) {
            gainNet = mise * divC - mise;
            titre = '🏆 COUPLÉ ${typePari == "Couplé Gagnant" ? "GAGNANT" : "PLACÉ"} — +${fmtEuros(gainNet)} €';
          } else {
            gainNet = mise * (typePari == 'Couplé Gagnant' ? 8.0 : 4.0);
            titre = '🏆 COUPLÉ GAGNÉ — vérifiez PMU';
          }
          alertType = AlertType.resultatsGagnant;
          messageResultat =
              '🎉 COUPLÉ ${typePari == "Couplé Gagnant" ? "GAGNANT" : "PLACÉ"} VALIDÉ !\n'
              '${tc.nomCourse} — ${tc.hippodrome}\n'
              'Vos 2 chevaux : ${mesNums.map((n) => "N°$n").join(" + ")}\n'
              'Arrivée : $arriveeStr\n'
              'Mise : ${fmtEuros(mise)} €'
              '${divC != null ? " → Gain : +${fmtEuros(gainNet)} €" : "\nVérifiez le dividende exact sur PMU.fr"}';
        } else {
          final nbBons = typePari == 'Couplé Gagnant'
              ? mesNums.intersection(top2Set).length
              : mesNums.intersection(top3Set).length;
          titre = '😔 Couplé perdu ($nbBons/2 bons)';
          alertType = AlertType.resultatsPerdant;
          messageResultat =
              '😔 Couplé non validé — $nbBons cheval(aux) sur 2 dans le top.\n'
              '${tc.nomCourse} — ${tc.hippodrome}\n'
              'Vos 2 chevaux : ${mesNums.map((n) => "N°$n").join(" + ")}\n'
              'Arrivée : $arriveeStr\n'
              'Mise perdue : ${fmtEuros(mise)} €';
        }
      } else if (!estPariMulti && (typePari == 'Simple Gagnant' || typePari == 'Gagnant+Placé' ||
          typePari == 'Simple Placé' || typePari == 'Placé' || mesNumeros.length <= 1)) {
        final estGagnant = monNumero == numGagnant;
        // Placé = dans les placesOfficielles PMU OU dans les 3 premiers de l'arrivée officielle
        final monNumeroInt = int.tryParse(monNumero ?? '');
        final estPlaceViaArrivee = monNumeroInt != null && arriveeOfficielle.take(3).contains(monNumeroInt);
        final estPlace = placesOfficielles.map((n) => n.toString()).contains(monNumero) || estPlaceViaArrivee;

        if (estGagnant) {
          final cote = coteGagnant ?? tc.cote;
          gainNet = mise * cote - mise;
          titre = '🏆 GAGNÉ — +${fmtEuros(gainNet)} €';
          alertType = AlertType.resultatsGagnant;
          messageResultat =
              '🎉 ${tc.nomCheval ?? "Votre cheval"} (N°$monNumero) a GAGNÉ !\n'
              '${tc.nomCourse} — ${tc.hippodrome}\n'
              'Cote officielle : ×${cote.toStringAsFixed(2)}\n'
              'Mise : ${fmtEuros(mise)} € → Retour : ${fmtEuros(mise * cote)} € (gain net : +${fmtEuros(gainNet)} €)\n'
              'Arrivée : $arriveeStr';
        } else if (estPlace && typePari == 'Gagnant+Placé') {
          // Cote Placé réelle PMU disponible ?
          final cpReel = cotePlace;
          if (cpReel != null) {
            gainNet = mise * cpReel - mise * 2; // mise réelle = ×2
            titre = '🥈 Placé (G+P) — ${gainNet >= 0 ? "+" : ""}${fmtEuros(gainNet)} €';
            alertType = AlertType.resultatsGagnant;
            messageResultat =
                '🥈 ${tc.nomCheval ?? "Votre cheval"} (N°$monNumero) est Placé !\n'
                '${tc.nomCourse} — ${tc.hippodrome}\n'
                'Cote Placé officielle : ×${cpReel.toStringAsFixed(2)}\n'
                'Mise réelle : ${fmtEuros(mise * 2)} € → Retour Placé : ${fmtEuros(mise * cpReel)} €\n'
                'Résultat net : ${gainNet >= 0 ? "+" : ""}${fmtEuros(gainNet)} €\n'
                'Arrivée : $arriveeStr';
          } else {
            titre = '🥈 Placé (G+P) — vérifiez PMU';
            alertType = AlertType.resultatsPerdant;
            messageResultat =
                '🥈 ${tc.nomCheval ?? "Votre cheval"} (N°$monNumero) est Placé !\n'
                '${tc.nomCourse} — ${tc.hippodrome}\n'
                'Gagnant : N°$numGagnant — Arrivée : $arriveeStr\n'
                'Vérifiez votre gain Placé sur PMU.fr';
          }
        } else if (estPlace) {
          final cpReel = cotePlace;
          if (cpReel != null) {
            gainNet = mise * cpReel - mise;
            titre = '🥈 Placé — +${fmtEuros(gainNet)} €';
            alertType = AlertType.resultatsGagnant;
            messageResultat =
                '🥈 ${tc.nomCheval ?? "Votre cheval"} (N°$monNumero) est Placé (top 3)\n'
                '${tc.nomCourse} — ${tc.hippodrome}\n'
                'Cote Placé officielle : ×${cpReel.toStringAsFixed(2)}\n'
                'Mise : ${fmtEuros(mise)} € → Retour : ${fmtEuros(mise * cpReel)} € (gain net : +${fmtEuros(gainNet)} €)\n'
                'Arrivée : $arriveeStr';
          } else {
            titre = '🥈 Placé — vérifiez PMU';
            alertType = AlertType.resultatsPerdant;
            messageResultat =
                '🥈 ${tc.nomCheval ?? "Votre cheval"} (N°$monNumero) est Placé (top 3)\n'
                '${tc.nomCourse} — ${tc.hippodrome}\n'
                'Gagnant : N°$numGagnant — Arrivée : $arriveeStr\n'
                'Vérifiez votre gain Placé sur PMU.fr';
          }
        } else {
          titre = '😔 Perdu — N°$numGagnant gagnant';
          alertType = AlertType.resultatsPerdant;
          messageResultat =
              '😔 ${tc.nomCheval ?? "Votre cheval"} (N°$monNumero) n\'a pas gagné.\n'
              '${tc.nomCourse} — ${tc.hippodrome}\n'
              'Arrivée officielle : $arriveeStr\n'
              'Mise perdue : ${fmtEuros(mise)} €';
        }

      // ── CAS 2 : Tiercé (3 chevaux dans le top 3, ordre libre) ──────────
      } else if (typePari == 'Tiercé' && mesNumeros.length >= 3) {
        final mesTop3 = mesNumeros.take(3).toSet();
        final officielTop3 = top3.toSet();
        final estTierceDesordre = mesTop3.containsAll(officielTop3) && officielTop3.containsAll(mesTop3);
        final estTierceOrdre = mesNumeros.take(3).toList().toString() == top3.toString();
        final nbBons = mesTop3.intersection(officielTop3).length;

        if (estTierceOrdre) {
          // Dividende officiel disponible → gain exact, sinon estimation
          final divT = dividendeTierce;
          if (divT != null) {
            gainNet = mise * divT;
            titre = '🏆 TIERCÉ ORDRE — +${fmtEuros(gainNet)} €';
          } else {
            gainNet = 0;
            titre = '🏆 TIERCÉ ORDRE GAGNÉ — vérifiez PMU';
          }
          alertType = AlertType.resultatsGagnant;
          messageResultat =
              '🎉 TIERCÉ DANS L\'ORDRE GAGNÉ !\n'
              '${tc.nomCourse} — ${tc.hippodrome}\n'
              'Vos numéros : ${mesNumeros.take(3).map((n) => "N°$n").join(" - ")}\n'
              'Arrivée : $arriveeStr\n'
              'Mise : ${fmtEuros(mise)} € → Gain : +${fmtEuros(gainNet)} €';
        } else if (estTierceDesordre) {
          // Priorité : dividende désordre réel PMU
          // Fallback : ~40% du dividende ordre (règle PMU approximative)
          final divTD = dividendeTierceDesordre;
          final divTO = dividendeTierce;
          if (divTD != null) {
            gainNet = mise * divTD - mise;
            titre = '🥇 TIERCÉ DÉSORDRE — +${fmtEuros(gainNet)} €';
          } else if (divTO != null) {
            gainNet = mise * divTO * 0.4 - mise;
            titre = '🥇 TIERCÉ DÉSORDRE — ~+${fmtEuros(gainNet)} €';
          } else {
            gainNet = 0;
            titre = '🥇 TIERCÉ DÉSORDRE GAGNÉ — vérifiez PMU';
          }
          alertType = AlertType.resultatsGagnant;
          final gainStr = divTD != null
              ? 'Gain : +${fmtEuros(gainNet)} €'
              : divTO != null
                  ? 'Gain estimé : ~+${fmtEuros(gainNet)} € (vérifiez sur PMU.fr)'
                  : 'Vérifiez le dividende exact sur PMU.fr';
          messageResultat =
              '🎉 TIERCÉ DANS LE DÉSORDRE GAGNÉ !\n'
              '${tc.nomCourse} — ${tc.hippodrome}\n'
              'Vos numéros : ${mesNumeros.take(3).map((n) => "N°$n").join(" - ")}\n'
              'Arrivée : $arriveeStr\n'
              'Mise : ${fmtEuros(mise)} € → $gainStr';
        } else if (nbBons == 2) {
          titre = '👍 2/3 du Tiercé — pas tout à fait';
          alertType = AlertType.resultatsPerdant;
          messageResultat =
              '😔 2 chevaux sur 3 bons pour le Tiercé.\n'
              '${tc.nomCourse} — ${tc.hippodrome}\n'
              'Vos numéros : ${mesNumeros.take(3).map((n) => "N°$n").join(" - ")}\n'
              'Arrivée : $arriveeStr\n'
              'Il manquait : ${officielTop3.difference(mesTop3).map((n) => "N°$n").join(", ")}';
        } else {
          titre = '😔 Tiercé perdu — ${nbBons}/3 bons';
          alertType = AlertType.resultatsPerdant;
          messageResultat =
              '😔 Tiercé non validé ($nbBons/3 chevaux corrects).\n'
              '${tc.nomCourse} — ${tc.hippodrome}\n'
              'Vos numéros : ${mesNumeros.take(3).map((n) => "N°$n").join(" - ")}\n'
              'Arrivée : $arriveeStr';
        }

      // ── CAS 3 : Quarté (4 chevaux dans le top 4) ────────────────────────
      } else if (typePari == 'Quarté+' && mesNumeros.length >= 4) {
        final mesTop4 = mesNumeros.take(4).toSet();
        final officielTop4 = top4.toSet();
        final nbBons = mesTop4.intersection(officielTop4).length;
        final estQuarteDesordre = nbBons == 4;
        final estQuarteOrdre = mesNumeros.take(4).toList().toString() == top4.toString();

        if (estQuarteOrdre) {
          final divQ = dividendeQuarte;
          if (divQ != null) {
            gainNet = mise * divQ;
            titre = '🏆 QUARTÉ ORDRE — +${fmtEuros(gainNet)} €';
          } else {
            gainNet = 0;
            titre = '🏆 QUARTÉ ORDRE GAGNÉ — vérifiez PMU';
          }
          alertType = AlertType.resultatsGagnant;
          messageResultat =
              '🎉 QUARTÉ DANS L\'ORDRE GAGNÉ !\n'
              '${tc.nomCourse} — ${tc.hippodrome}\n'
              'Vos numéros : ${mesNumeros.take(4).map((n) => "N°$n").join(" - ")}\n'
              'Arrivée : $arriveeStr\n'
              'Mise : ${fmtEuros(mise)} € → Gain : +${fmtEuros(gainNet)} €';
        } else if (estQuarteDesordre) {
          final divQD = dividendeQuarteDesordre;
          final divQO = dividendeQuarte;
          if (divQD != null) {
            gainNet = mise * divQD - mise;
            titre = '🥇 QUARTÉ DÉSORDRE — +${fmtEuros(gainNet)} €';
          } else if (divQO != null) {
            gainNet = mise * divQO * 0.12 - mise; // ~12% du dividende ordre PMU
            titre = '🥇 QUARTÉ DÉSORDRE — ~+${fmtEuros(gainNet)} €';
          } else {
            gainNet = 0;
            titre = '🥇 QUARTÉ DÉSORDRE GAGNÉ — vérifiez PMU';
          }
          alertType = AlertType.resultatsGagnant;
          final gainStr = divQD != null
              ? 'Gain : +${fmtEuros(gainNet)} €'
              : divQO != null
                  ? 'Gain estimé : ~+${fmtEuros(gainNet)} € (vérifiez sur PMU.fr)'
                  : 'Vérifiez le dividende exact sur PMU.fr';
          messageResultat =
              '🎉 QUARTÉ DANS LE DÉSORDRE GAGNÉ !\n'
              '${tc.nomCourse} — ${tc.hippodrome}\n'
              'Vos numéros : ${mesNumeros.take(4).map((n) => "N°$n").join(" - ")}\n'
              'Arrivée : $arriveeStr\n'
              'Mise : ${fmtEuros(mise)} € → $gainStr';
        } else {
          titre = '😔 Quarté perdu — $nbBons/4 bons';
          alertType = AlertType.resultatsPerdant;
          messageResultat =
              '😔 Quarté non validé ($nbBons/4 chevaux corrects).\n'
              '${tc.nomCourse} — ${tc.hippodrome}\n'
              'Vos numéros : ${mesNumeros.take(4).map((n) => "N°$n").join(" - ")}\n'
              'Arrivée : $arriveeStr';
        }

      // ── CAS 4 : Quinté+ (5 chevaux dans le top 5) ───────────────────────
      } else if (typePari == 'Quinté+' && mesNumeros.length >= 5) {
        final mesTop5 = mesNumeros.take(5).toSet();
        final officielTop5 = top5.toSet();
        final nbBons = mesTop5.intersection(officielTop5).length;
        final estQuinteOrdre = mesNumeros.take(5).toList().toString() == top5.toString();
        final estQuinteDesordre = nbBons == 5;

        if (estQuinteOrdre) {
          final divQn = dividendeQuinte;
          if (divQn != null) {
            gainNet = mise * divQn;
            titre = '🏆 QUINTÉ ORDRE — +${fmtEuros(gainNet)} €';
          } else {
            gainNet = 0;
            titre = '🏆 QUINTÉ ORDRE GAGNÉ — vérifiez PMU';
          }
          alertType = AlertType.resultatsGagnant;
          messageResultat =
              '🎉🎉 QUINTÉ+ DANS L\'ORDRE GAGNÉ ! 🎉🎉\n'
              '${tc.nomCourse} — ${tc.hippodrome}\n'
              'Vos numéros : ${mesNumeros.take(5).map((n) => "N°$n").join(" - ")}\n'
              'Arrivée : $arriveeStr\n'
              'Mise : ${fmtEuros(mise)} € → Gain : +${fmtEuros(gainNet)} €';
        } else if (estQuinteDesordre) {
          final divQnD = dividendeQuinteDesordre;
          final divQnO = dividendeQuinte;
          if (divQnD != null) {
            gainNet = mise * divQnD - mise;
            titre = '🥇 QUINTÉ DÉSORDRE — +${fmtEuros(gainNet)} €';
          } else if (divQnO != null) {
            gainNet = mise * divQnO * 0.06 - mise; // ~6% du dividende ordre PMU
            titre = '🥇 QUINTÉ DÉSORDRE — ~+${fmtEuros(gainNet)} €';
          } else {
            gainNet = 0;
            titre = '🥇 QUINTÉ+ DÉSORDRE GAGNÉ — vérifiez PMU';
          }
          alertType = AlertType.resultatsGagnant;
          final gainStr = divQnD != null
              ? 'Gain : +${fmtEuros(gainNet)} €'
              : divQnO != null
                  ? 'Gain estimé : ~+${fmtEuros(gainNet)} € (vérifiez sur PMU.fr)'
                  : 'Vérifiez le dividende exact sur PMU.fr';
          messageResultat =
              '🎉 QUINTÉ+ DANS LE DÉSORDRE GAGNÉ !\n'
              '${tc.nomCourse} — ${tc.hippodrome}\n'
              'Vos numéros : ${mesNumeros.take(5).map((n) => "N°$n").join(" - ")}\n'
              'Arrivée : $arriveeStr\n'
              'Mise : ${fmtEuros(mise)} € → $gainStr';
        } else if (nbBons == 4) {
          final div4 = dividendeQuinte4sur5;
          if (div4 != null) {
            gainNet = mise * div4 - mise;
            titre = '⭐ 4/5 Quinté — +${fmtEuros(gainNet)} €';
          } else {
            gainNet = 0;
            titre = '⭐ 4/5 du Quinté — Bonus possible !';
          }
          alertType = AlertType.resultatsGagnant;
          messageResultat =
              '⭐ 4 chevaux sur 5 bons pour le Quinté+ !\n'
              '${tc.nomCourse} — ${tc.hippodrome}\n'
              'Vos numéros : ${mesNumeros.take(5).map((n) => "N°$n").join(" - ")}\n'
              'Arrivée : $arriveeStr\n'
              'Mise : ${fmtEuros(mise)} €'
              '${div4 != null ? " → Bonus : +${fmtEuros(gainNet)} €" : "\nVérifiez si un bonus de consolation s\'applique sur PMU.fr"}';
        } else if (nbBons == 3) {
          titre = '👍 3/5 du Quinté — pas cette fois';
          alertType = AlertType.resultatsPerdant;
          messageResultat =
              '😔 3 chevaux sur 5 bons pour le Quinté+.\n'
              '${tc.nomCourse} — ${tc.hippodrome}\n'
              'Vos numéros : ${mesNumeros.take(5).map((n) => "N°$n").join(" - ")}\n'
              'Arrivée : $arriveeStr';
        } else {
          titre = '😔 Quinté+ perdu — $nbBons/5 bons';
          alertType = AlertType.resultatsPerdant;
          messageResultat =
              '😔 Quinté+ non validé ($nbBons/5 chevaux corrects).\n'
              '${tc.nomCourse} — ${tc.hippodrome}\n'
              'Vos numéros : ${mesNumeros.take(5).map((n) => "N°$n").join(" - ")}\n'
              'Arrivée : $arriveeStr';
        }

      // ── CAS 5 : Pas de numéros enregistrés → résultat brut ──────────────
      } else {
        titre = '📋 Résultat : ${tc.nomCourse}';
        alertType = AlertType.courseEnCours;
        messageResultat =
            'Arrivée officielle : $arriveeStr\n'
            '${tc.hippodrome}';
      }

      // ★ v3.0 : Notification enrichie avec arrivée + gain calculé
      // ★ Anti-doublon push : UN SEUL _addAlert ici — _addAlert appelle déjà
      //   _sendNativeNotification() → supprimer l'ancien appel signalerResultat()
      //   qui créait un 2ème push avec un ID différent (${courseKey}_result_YYYYMMDD)
      //   et contournait ainsi le filtre _sentAlertIds.
      _addAlert(AppAlert(
        id: '${resultKey}_resultat',
        type: alertType,
        titre: titre,
        message: messageResultat,
        timestamp: DateTime.now(),
        numReunion: tc.numReunion,
        numCourse:  tc.numCourse,
        dateStrCourse: _dateStrYYYYMMDD(tc.heureDepart),
        heureDepart: tc.heureDepart,
      ));

      // ★ Notification supplémentaire si l'arrivée finale contient des DQ
      // (chevaux disqualifiés APRÈS la course qui modifient le classement)
      final disqFinaux = _disqDetectes[tc.key] ?? {};
      // On considère qu'il y a un DQ significatif si on en a détecté pendant
      // la course ET qu'il n'est pas dans l'arrivée officielle
      final disqNonDansArrivee = disqFinaux.where(
          (n) => !arriveeOfficielle.contains(n)).toList();
      if (disqNonDansArrivee.isNotEmpty) {
        final disqStr = disqNonDansArrivee.map((n) => 'N°$n').join(', ');
        _addAlert(AppAlert(
          id: '${resultKey}_disq_final',
          type: AlertType.courseEnCours,
          titre: '⚠️ DQ confirmé — arrivée officielle recalculée',
          message: '$disqStr disqualifié(s) — arrivée officielle :\n'
                   '$arriveeStr\n'
                   '${tc.nomCourse} — ${tc.hippodrome}',
          timestamp: DateTime.now(),
        ));
      }

      // ★ Bug fix #3 : Mettre à jour isCorrect dans PmuProvider → Profil cohérent
      // On cherche la UserPrediction correspondante par numéros de réunion/course
      if (_pmuProvider != null) {
        final estGagne = alertType == AlertType.resultatsGagnant;
        final matched = _pmuProvider!.predictions.where((p) =>
          p.numReunion == tc.numReunion &&
          p.numCourse == tc.numCourse &&
          p.isCorrect == null  // seulement si pas encore validé
        ).toList();
        for (final pred in matched) {
          final misePred = pred.montantMise > 0
              ? pred.montantMise
              : (tc.miseEngagee ?? pred.montantMise);
          // Passer le gainNet réel calculé depuis les dividendes PMU
          // → profil et stats en temps réel avec les vrais montants
          final gainReel = gainNet != 0.0
              ? gainNet
              : (estGagne && misePred > 0 && pred.cote > 1
                  ? pred.cote * misePred - misePred
                  : (!estGagne && misePred > 0 ? -misePred : null));
          _pmuProvider!.validatePrediction(
            pred.id,
            isCorrect: estGagne,
            montantMise: misePred,
            gainRealise: gainReel,
          );
        }
      }

      // ── Notifier la mémoire IA du résultat réel ──────────────────────────
      // La mémoire IA compare les pronostics et ajuste les poids adaptatifs.
      // On utilise iaMemKey si disponible (clé précise depuis le pari),
      // sinon on construit la clé standard pour rétrocompatibilité.
      if (arriveeOfficielle.isNotEmpty) {
        final _aj = tc.heureDepart.day.toString().padLeft(2, '0');
        final _am = tc.heureDepart.month.toString().padLeft(2, '0');
        final memKey = tc.iaMemKey ??
            '${tc.key}_$_aj$_am${tc.heureDepart.year}';
        await IaMemoryService.instance.enregistrerResultat(
          courseKey: memKey,
          arriveeReelle: arriveeOfficielle,
        );
        if (kDebugMode) {
          if (kDebugMode) debugPrint('IA Mémoire : résultat enregistré pour $memKey - '
              'Arrivée: ${arriveeOfficielle.take(5).join("-")}');
        }
      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('_fetchResultatAuto error: $e');
      // En cas d'erreur réseau, on retire la clé pour réessayer
      _resultatsVerifies.remove(resultKey);
    }
  }

  // ── Affichage in-app overlay ──────────────────────────────────────────────

  static void showInAppAlert(BuildContext context, AppAlert alert) {
    final color = alert.type.color;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF0A1F12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: color.withValues(alpha: 0.6)),
        ),
        margin: const EdgeInsets.all(12),
        content: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(alert.type.icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(alert.titre,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
              Text(alert.message,
                  style: const TextStyle(color: Colors.white60, fontSize: 10),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _formatHeure(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}h${dt.minute.toString().padLeft(2, '0')}';

  /// Formate une date en 'YYYYMMDD' pour l'API PMU et RaceDetailScreen.
  static String _dateStrYYYYMMDD(DateTime dt) =>
      '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _watchdogTimer?.cancel();
    super.dispose();
  }
}

// ─── Modèle de course suivie ──────────────────────────────────────────────────
class TrackedCourse {
  final int numReunion;
  final int numCourse;
  final String nomCourse;
  final String hippodrome;
  final DateTime heureDepart;
  final String? nomCheval;          // cheval principal sélectionné
  final int? numeroCheval;          // numéro du cheval principal
  final double? miseEngagee;        // mise en €
  final DateTime addedAt;
  // ★ Clé de stockage unique (avec timestamp) — persiste entre redémarrages
  final String? storageKey;
  // ── Nouveaux champs (rétrocompatibles) ──────────────────────────
  final String typePari;            // 'Simple Gagnant','Simple Placé','Gagnant+Placé','Couplé Gagnant','Couplé Placé','Tiercé','Quarté+','Quinté+'
  final List<int> numerosJoues;     // tous les numéros joués (ex: [7,4,2,10,3] pour Quinté)
  // ── Clé mémoire IA (lien entre pari et pronostic enregistré) ────
  final String? iaMemKey;           // clé utilisée dans IaMemoryService
  // ── Score de confiance IA du cheval sélectionné ───────────────────
  final double scoreIA;             // score IA 0–100
  // ── Cote du cheval au moment du pari ─────────────────────────────
  final double cote;               // cote PMU ex: 6.5 → gain = mise × cote
  // ── Résultat persisté (★ nouveau – évite de reperdre le résultat à la navigation) ──
  final bool? isGagne;             // null = inconnu, true = gagné, false = perdu
  final List<int> arriveeFinale;   // ordre d'arrivée officiel persisté
  final String? messageResultat;   // message affiché lors du résultat
  // ── Dividende PMU réel (récupéré post-course via API rapports-definitifs) ──
  final double? dividendePmuReel;  // ex: 45.2 → retour pour 1€ misé (null = pas encore récupéré)
  final String? combinaisonPmu;    // ex: "5-12-3" → numéros gagnants PMU officiels

  TrackedCourse({
    required this.numReunion,
    required this.numCourse,
    required this.nomCourse,
    required this.hippodrome,
    required this.heureDepart,
    this.storageKey,
    this.nomCheval,
    this.numeroCheval,
    this.miseEngagee,
    DateTime? addedAt,
    this.typePari = 'Simple Gagnant',
    this.numerosJoues = const [],
    this.iaMemKey,
    this.scoreIA = 0.0,
    this.cote = 0.0,
    this.isGagne,
    this.arriveeFinale = const [],
    this.messageResultat,
    this.dividendePmuReel,
    this.combinaisonPmu,
  }) : addedAt = addedAt ?? DateTime.now();

  /// Crée une copie avec résultat mis à jour (pour persister sans muter)
  TrackedCourse withResultat({
    required bool isGagne,
    required List<int> arrivee,
    required String message,
  }) => TrackedCourse(
    numReunion: numReunion,
    numCourse: numCourse,
    nomCourse: nomCourse,
    hippodrome: hippodrome,
    heureDepart: heureDepart,
    nomCheval: nomCheval,
    numeroCheval: numeroCheval,
    miseEngagee: miseEngagee,
    addedAt: addedAt,
    typePari: typePari,
    numerosJoues: numerosJoues,
    iaMemKey: iaMemKey,
    scoreIA: scoreIA,
    cote: cote,
    isGagne: isGagne,
    arriveeFinale: arrivee,
    messageResultat: message,
    dividendePmuReel: dividendePmuReel,
    combinaisonPmu: combinaisonPmu,
  );

  /// Crée une copie avec le dividende PMU réel mis à jour
  TrackedCourse withDividende({
    required double dividende,
    required String combinaison,
  }) => TrackedCourse(
    numReunion: numReunion,
    numCourse: numCourse,
    nomCourse: nomCourse,
    hippodrome: hippodrome,
    heureDepart: heureDepart,
    nomCheval: nomCheval,
    numeroCheval: numeroCheval,
    miseEngagee: miseEngagee,
    addedAt: addedAt,
    typePari: typePari,
    numerosJoues: numerosJoues,
    iaMemKey: iaMemKey,
    scoreIA: scoreIA,
    cote: cote,
    isGagne: isGagne ?? true,
    arriveeFinale: arriveeFinale,
    messageResultat: messageResultat,
    dividendePmuReel: dividende,
    combinaisonPmu: combinaison,
    storageKey: storageKey,
  );

  /// Clé unique incluant la date du jour → évite les collisions entre journées
  /// Format identique à buildCourseKey() : R3C5_23042026  (ddmmyyyy)
  String get key {
    final d = heureDepart;
    final dateStr = '${d.day.toString().padLeft(2,'0')}${d.month.toString().padLeft(2,'0')}${d.year}';
    return 'R${numReunion}C${numCourse}_$dateStr';
  }

  String get statutLabel {
    final diff = heureDepart.difference(DateTime.now());
    if (diff.inMinutes > 60) return 'À venir dans ${diff.inHours}h${diff.inMinutes % 60}min';
    if (diff.inMinutes > 0)  return 'Dans ${diff.inMinutes} min';
    // ★ Fix seuil : "En cours" jusqu'à -45 min (courses jusqu'à 40 min de durée)
    // Ancienne valeur -20 trop courte → pari restait affiché "Terminé" avant résultat
    if (diff.inMinutes > -20) return '🔴 En cours';
    return '✅ Terminée';
  }

  Color get statutColor {
    final diff = heureDepart.difference(DateTime.now());
    if (diff.inMinutes > 60) return const Color(0xFF64B5F6);
    if (diff.inMinutes > 15) return const Color(0xFFFFB74D);
    if (diff.inMinutes > 0)  return const Color(0xFFFF9800);
    if (diff.inMinutes > -20) return const Color(0xFFEF5350);
    return const Color(0xFF4CAF7D);
  }

  Map<String, dynamic> toJson() => {
    'numReunion': numReunion,
    'numCourse': numCourse,
    'nomCourse': nomCourse,
    'hippodrome': hippodrome,
    'heureDepart': heureDepart.toIso8601String(),
    'nomCheval': nomCheval,
    'numeroCheval': numeroCheval,
    'miseEngagee': miseEngagee,
    'addedAt': addedAt.toIso8601String(),
    'typePari': typePari,
    'numerosJoues': numerosJoues,
    'iaMemKey': iaMemKey,
    'scoreIA': scoreIA,
    'cote': cote,
    // ★ Résultat persisté
    'isGagne': isGagne,
    'arriveeFinale': arriveeFinale,
    'messageResultat': messageResultat,
    // ★ Dividende PMU réel post-course
    'dividendePmuReel': dividendePmuReel,
    'combinaisonPmu': combinaisonPmu,
    // ★ Clé de stockage unique — persiste le timestamp entre redémarrages
    'storageKey': storageKey,
  };

  factory TrackedCourse.fromJson(Map<String, dynamic> j) => TrackedCourse(
    numReunion:   j['numReunion']   as int,
    numCourse:    j['numCourse']    as int,
    nomCourse:    j['nomCourse']    as String,
    hippodrome:   j['hippodrome']   as String,
    heureDepart:  DateTime.parse(j['heureDepart'] as String),
    storageKey:   j['storageKey']   as String?,
    nomCheval:    j['nomCheval']    as String?,
    numeroCheval: j['numeroCheval'] as int?,
    miseEngagee:  (j['miseEngagee'] as num?)?.toDouble(),
    addedAt:      j['addedAt'] != null ? DateTime.parse(j['addedAt'] as String) : null,
    // Rétrocompatibles : valeurs par défaut si absent (anciens paris sauvegardés)
    typePari:     j['typePari']     as String? ?? 'Simple Gagnant',
    numerosJoues: (j['numerosJoues'] as List<dynamic>? ?? [])
                      .map((e) => (e as num).toInt()).toList(),
    iaMemKey:     j['iaMemKey']     as String?,
    scoreIA:      (j['scoreIA'] as num?)?.toDouble() ?? 0.0,
    cote:         (j['cote'] as num?)?.toDouble() ?? 0.0,
    // ★ Résultat persisté (rétrocompatible)
    isGagne:         j['isGagne'] as bool?,
    arriveeFinale:   (j['arriveeFinale'] as List<dynamic>? ?? [])
                         .map((e) => (e as num).toInt()).toList(),
    messageResultat: j['messageResultat'] as String?,
    // ★ Dividende PMU réel (rétrocompatible)
    dividendePmuReel: (j['dividendePmuReel'] as num?)?.toDouble(),
    combinaisonPmu:   j['combinaisonPmu'] as String?,
  );
}
