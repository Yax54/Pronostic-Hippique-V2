import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'ia_memory_service.dart';
import 'recommandation_pari_service.dart' // ★ BLOC 1 : source unique du type de pari
    show cascadeRecommandation;
// ★ A6 : décision d'arrivée partagée (L0 prioritaire + contrôle d'appartenance).
// `arrivee_pmu_ordonnee.dart` n'est plus importé ici : la décision P5 ne
// consulte plus directement `analyserRapportsPmu` (mesuré : 0 occurrence).
import 'arrivee_officielle_prioritaire.dart'; // ★ A6 : L0 prioritaire + appartenance
import 'arrivee_officielle_service.dart'; // ★ A6 : lecture L0 en RAM (copie profonde)
import 'zone_turf_service.dart';
import 'data_refresh_service.dart';
import '../models/zt_models.dart';
import '../providers/pmu_provider.dart';
import 'resultat_ecriture_gain.dart'; // ★ B1-T12 lot 2-C — issue des écritures
import '../utils/format_euros.dart';
import '../utils/type_pari_utils.dart'; // ★ A-0 — reconnaissance Gagnant+Placé
// ★ ÉTAPE 2 — référentiel central : reconnaissance EN LECTURE des types de
//   paris historiques. Module pur, sans état et sans import : aucune boucle
//   possible. Utilisé UNIQUEMENT par des getters dérivés de `TrackedCourse`.
import 'referentiel_paris_pmu.dart';
// ★ R10 : source UNIQUE du nombre de chevaux attendu. Fichier pur (0 import).
import 'gain_ticket_calculator.dart'
    show TypePariJoue, typePariDepuisLibelle, tailleCombinaisonAttendue, exigeOrdreExact;
// ★ LOT B-1 — types purs des gains PMU structurés (modèle jumeau de
//   `UserPrediction`). `gain_pmu_types.dart` n'importe que
//   `gain_ticket_calculator.dart` (0 import) : chaîne fermée, aucun cycle.
import 'gain_pmu_types.dart'
    show
        EtatGain,
        EtatTirelire,
        MotifNonDetermination,
        RapportAttribue;
// ★ B1-T12 / étape 1 (complément) — la copie déliée de `TrackedCourse` est
//   une EXTENSION déclarée dans ce fichier (classe `TrackedCourseCopy`), pas
//   une méthode de la classe. Sans cet import, `delierSuivi` ne compile pas :
//   mesuré — « The method 'copieDeliee' isn't defined for the type
//   'TrackedCourse' ». Cet import est le SEUL motif de la dépendance, et il
//   ne touche aucune logique de verdict de ce fichier.
import 'enregistreur_verdict_gain_suivi.dart' show TrackedCourseCopy;

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
  gainTardif,    // ★ CHANTIER 2/3 : gain officiel PMU arrivé après coup
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
      case AlertType.gainTardif:       return '🏆 Gain officiel disponible';
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
      case AlertType.gainTardif:       return const Color(0xFFFFD700);
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
      case AlertType.gainTardif:       return Icons.emoji_events;
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
  // ─────────────────────────────────────────────────────────────────────────
  //  ★ B1-T12 / étape 1 (complément) — GÉNÉRATEUR D'IDENTIFIANTS UNIQUES
  // ─────────────────────────────────────────────────────────────────────────
  //
  //  DÉFAUT MESURÉ AVANT D'ÉCRIRE : `UserPrediction.id` et la `storageKey`
  //  étaient fabriqués à partir de `DateTime.now().millisecondsSinceEpoch`.
  //  Deux tickets créés dans la MÊME milliseconde recevaient donc le même
  //  identifiant. Conséquence sur `UserPrediction` (identité de première
  //  classe — 5 usages de production : `validatePrediction`, `updateMise`,
  //  `enregistrerDividendePmu`, `appliquerVerdictGainPrediction` via
  //  `indexWhere((p) => p.id == id)`, et `removePrediction` via `removeWhere`) :
  //  un gain saisi pour l'un s'appliquait au PREMIER trouvé, et une
  //  suppression en emportait DEUX. C'est la confusion de gains interdite.
  //
  //  POURQUOI LE COMPTEUR PROPOSÉ N'EST PAS RETENU : un compteur incrémental
  //  doit, au redémarrage, retrouver sa dernière valeur. Or les tickets
  //  purgés au chargement (`_load`, purge > 24 h et clés sans date) ne sont
  //  plus lisibles : le compteur redémarrerait plus bas et RÉÉMETTRAIT des
  //  identifiants déjà utilisés — exactement la collision qu'on veut éviter.
  //  Il ne garantirait donc pas l'unicité « y compris après redémarrage ».
  //
  //  SOLUTION RETENUE — unicité SANS ÉTAT, donc valable à travers les
  //  redémarrages : horodatage en RÉSOLUTION DE LA MICROSECONDE (`microsecondsSinceEpoch`,
  //  1 000 fois plus fine) + désambiguïsation par compteur MONOTONE EN MÉMOIRE
  //  qui n'est JAMAIS persisté et ne conditionne pas l'unicité de la première
  //  occurrence. Deux tickets consécutifs ne peuvent donc pas partager un
  //  identifiant, et aucun état survivant n'est nécessaire.
  //
  //  GARANTIE ANTI-ÉCRASEMENT, structurelle et non probabiliste : avant de
  //  publier un identifiant, on vérifie qu'il n'existe NI dans le store de
  //  suivi (`_trackedCourses`) NI dans la réserve des identifiants de profil.
  //  Si l'un des deux le détient, on passe au candidat suivant. Aucun suivi
  //  existant ne peut être écrasé, aucun profil ne peut être confondu.
  // ─────────────────────────────────────────────────────────────────────────

  /// Dernier horodatage distribué. `0` = jamais utilisé dans ce processus.
  /// ⚠️ VOLONTAIREMENT NON PERSISTÉ : il ne sert qu'à garantir que deux
  /// appels consécutifs du même processus ne rendent pas la même valeur.
  int _dernierHorodatageIdentifiant = 0;

  /// Désambiguïsation monotone du dernier horodatage distribué.
  int _compteurIdentifiant = 0;

  /// Identifiants de profil déjà distribués mais peut-être pas encore
  /// enregistrés (la création fait deux écritures distinctes, non
  /// transactionnelles). Réserve **en mémoire uniquement**, jamais écrite
  /// sur disque, donc elle ne peut pas grossir indéfiniment.
  final Set<String> _idsPredictionReserves = {};
  /// IDs de profil connus par l'appelant (`PmuProvider.predictions`), mis à
  /// jour à chaque publication. Rend la transaction de `bet_bottom_sheet`
  /// **rejouable** et donc vérifiable en test : la seconde écriture peut
  /// échouer puis être retentée avec exactement le même identifiant.
  final Set<String> _idsProfilConnus = {};

  /// Source de l'horodatage des identifiants.
  ///
  /// ⚠️ POINT D'INJECTION POUR LES TESTS — ajouté parce qu'une GARDE
  /// INATTEIGNABLE N'EST PAS UNE GARDE PROUVÉE. Mesuré : avec l'horloge
  /// réelle, la monotonie rend le repli « candidat déjà pris » pratiquement
  /// inaccessible, donc son test ne pouvait pas échouer — et une mutation
  /// qui supprimait ce repli n'était détectée par AUCUN test. Exposer
  /// l'horloge permet de FORCER un candidat déjà occupé et de vérifier que
  /// le repli fonctionne réellement. En production, la valeur reste
  /// `DateTime.now().microsecondsSinceEpoch` : comportement inchangé.
  int Function() sourceHorodatageIdentifiant =
      () => DateTime.now().microsecondsSinceEpoch;

  /// Déclare les IDs de profil actuellement connus de l'appelant.
  ///
  /// Sans effet sur l'unicité (qui est garantie sans état) : c'est une
  /// information de vérification, pour le repli anti-écrasement et pour
  /// permettre une reprise après échec de la seconde écriture.
  void declarerIdsProfil(Iterable<String> ids) {
    _idsProfilConnus
      ..clear()
      ..addAll(ids);
  }

  /// Fabrique le candidat proposé à partir de l'horodatage courant.
  ///
  /// ⚠️ POINT D'INJECTION POUR LES TESTS, ET RAISON MESURÉE DE SON EMPLACEMENT :
  /// ma première tentative exposait l'HORLOGE. Elle ne prouvait rien — deux
  /// mutations successives supprimant le repli anti-écrasement n'étaient
  /// détectées par AUCUN test, parce que la monotonie changeait la valeur
  /// avant que la garde ne soit consultée. Exposer la FABRIQUE DU CANDIDAT
  /// cible la garde elle-même, sans court-circuiter la procédure.
  ///
  /// En production, c'est la construction exacte d'origine. Le repli
  /// anti-écrasement, lui, reste TOUJOURS dans la boucle et ne peut pas être
  /// neutralisé par un test.
  String Function(String baseKey, int horodatage, int compteur) fabriqueCandidat =
      (baseKey, horodatage, compteur) =>
          '${baseKey}_$horodatage${compteur == 0 ? '' : '-$compteur'}';

  /// Publie un identifiant de ticket UNIQUE, pour le suivi ET le profil.
  ///
  /// [baseKey] doit être la clé de base `R<n>C<n>_<ddmmyyyy>` : elle est
  /// conservée EN PRÉFIXE à l'identique, car deux mécanismes existants en
  /// dépendent — `estDejaEnSuivi` (`k == baseKey || k.startsWith('${baseKey}_')`)
  /// et la purge au chargement (`RegExp(r'R\d+C\d+_\d{8}')` sur la clé).
  ///
  /// Synchrone À DESSEIN : le seul appelant (`bet_bottom_sheet._valider`)
  /// l'est, et le générateur ne doit rien attendre pour rester atomique du
  /// point de vue de l'appelant.
  String genererIdentifiantTicket(String baseKey, {Set<String>? idsProfil}) {
    final reserve = idsProfil ?? const <String>{};
    String candidat;
    // Borne de sécurité : chaque tour consomme un horodatage PLUS GRAND, donc
    // le repli progresse toujours. Sans cette borne, une source d'horodatage
    // figée (test, horloge gelée) ferait tourner la boucle sans fin.
    var tours = 0;
    do {
      if (tours++ > 100000) {
        throw StateError(
            'genererIdentifiantTicket : impossible de publier un identifiant '
            'unique après $tours tentatives (base « $baseKey »)');
      }
      final maintenant = sourceHorodatageIdentifiant();
      if (maintenant > _dernierHorodatageIdentifiant) {
        _dernierHorodatageIdentifiant = maintenant;
        _compteurIdentifiant = 0;
      } else {
        // Horloge revenue en arrière, ou même microseconde : on force la
        // monotonie. L'identifiant reste unique même si l'horloge régresse.
        _dernierHorodatageIdentifiant += 1;
        _compteurIdentifiant += 1;
      }
      candidat = fabriqueCandidat(
          baseKey, _dernierHorodatageIdentifiant, _compteurIdentifiant);
    } while (_trackedCourses.containsKey(candidat) ||
        _idsPredictionReserves.contains(candidat) ||
        _idsProfilConnus.contains(candidat) ||
        reserve.contains(candidat));

    _idsPredictionReserves.add(candidat);
    _idsProfilConnus.add(candidat);
    return candidat;
  }

  /// Libère un identifiant de profil réservé mais finalement NON enregistré.
  ///
  /// Appelé quand la seconde écriture (profil) échoue : sans libération, la
  /// réserve grossirait à chaque échec. Un identifiant libéré n'est PAS
  /// réutilisé, il redevient simplement candidat-vérifiable comme les autres.
  void libererIdentifiantTicket(String id) {
    _idsPredictionReserves.remove(id);
  }

  /// Alertes déjà envoyées pour éviter les doublons
  final Set<String> _sentAlertIds = {};
  // Courses dont le résultat a déjà été récupéré automatiquement
  final Set<String> _resultatsVerifies = {};
  // ★ Tracking DQ : statuts PMU connus par courseKey pour ne notifier qu'une fois
  // Clé : courseKey, Valeur : set des numéros déjà identifiés comme DQ/RETRAIT
  final Map<String, Set<int>> _disqDetectes = {};
  // ★ Clé de re-analyse en cours pour éviter les appels simultanés
  final Set<String> _reanalyseEnCours = {};
  Timer? _watchdogTimer;

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ B5c — Barrière d'écriture unifiée
  //
  //  Le reset complet efface les clés du disque. Sans barrière, une écriture
  //  déjà engagée peut se terminer APRÈS l'effacement et recréer les clés
  //  avec les anciennes données : c'est le défaut B5c, variante 5.
  //
  //  Le service possède HUIT chemins d'écriture SharedPreferences :
  //    1. _save()                                  (6 clés)
  //    2. _sendNativeNotification()                (file de notifications)
  //    3. ajouterFavoriPourWorker()                (hippique_favorites_v1)
  //    4. marquerFavoriCommeParI()                 (hippique_favorites_v1)
  //    5. nettoyerFavorisObsoletes()               (hippique_favorites_v1)
  //    6. _sauvegarderConseilIANotifies()          (conseil_ia_notifies_v1)
  //    7. _resetConseilIANotifiesIfNewDay()        (_date + liste, en un bloc)
  //    8. verifierCoursesConseilIA()               (conseil_ia_resume_date)
  //
  //  Les huit passent OBLIGATOIREMENT par [_ecrireProtege], seul point
  //  d'enregistrement dans [_ecrituresEnCours].
  // ══════════════════════════════════════════════════════════════════════════

  /// Barrière temporelle : vraie du début du reset à la fin de l'effacement.
  bool _resetEnCours = false;

  /// Verrou définitif : ne redescend jamais. Couvre les écritures dont le
  /// `SharedPreferences.getInstance()` se résout APRÈS la libération de
  /// [_resetEnCours] dans le `finally` du reset.
  int _generationCache = 0;

  /// Registre des écritures ENGAGÉES (contrôles franchis, action démarrée).
  /// Alimenté et vidé par [_ecrireProtege] UNIQUEMENT — jamais par un appelant.
  final Set<Future<bool>> _ecrituresEnCours = <Future<bool>>{};

  /// Diagnostic : nombre d'écritures encore en vol.
  /// Miroir de `CoteTrackerService.nbEcrituresEnCours`.
  int get nbEcrituresEnCours => _ecrituresEnCours.length;

  /// ★ B5c — Instantané des courses déjà connues au moment du dernier reset.
  ///
  /// Capturé AVANT le drain, donc sur le cache `_coursesMatchingConseils`
  /// d'entrée. Consommé une seule fois par clé (via `remove`).
  /// Il empêche de rejouer une rafale d'alertes « conseil IA » sur des courses
  /// que l'utilisateur voyait déjà, tout en laissant passer les courses
  /// réellement nouvelles.
  ///
  /// ⚠️ R-21 (limite assumée) : cet instantané vit en RAM et disparaît au
  ///    redémarrage. Après un reset suivi d'une relance AVANT tout refresh,
  ///    le premier refresh notifie une fois chaque course du jour encore dans
  ///    les critères. Ce ne sont pas d'anciennes alertes (les jours précédents
  ///    ne sont plus dans le cache), et aucune donnée ne survit au reset.
  ///    Rendre cet instantané persistant contredirait la décision de vidage.
  Set<String> _conseilIASilencieux = <String>{};

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

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ B5c — Enveloppe d'écriture protégée (SEUL point d'enregistrement)
  // ══════════════════════════════════════════════════════════════════════════

  /// Dernière erreur d'écriture, conservée pour diagnostic.
  /// Les écritures ne propagent pas d'exception (une écriture « fire and
  /// forget » ne doit pas produire d'erreur asynchrone non gérée), mais
  /// l'erreur est journalisée et mémorisée ici : elle reste diagnostiquable.
  Object? _derniereErreurEcriture;
  Object? get derniereErreurEcriture => _derniereErreurEcriture;

  /// Exécute [action] sous barrière de reset. Renvoie `true` si l'écriture a
  /// été exécutée, `false` si elle a été refusée (barrière active) ou si elle
  /// a échoué.
  ///
  /// ⚠️ POINT CRUCIAL — entre le franchissement du contrôle 2 et l'ajout au
  ///    registre, il n'existe AUCUN `await`. Si une suspension s'y glissait,
  ///    une écriture pourrait franchir les contrôles sans être vue du drain :
  ///    c'est exactement le défaut que cette méthode corrige.
  ///
  /// ⚠️ Il n'y a QU'UN `add` et QU'UN `whenComplete` par écriture : un
  ///    appelant ne doit jamais enregistrer lui-même sa future.
  Future<bool> _ecrireProtege(
      Future<void> Function(SharedPreferences prefs) action) async {
    // Contrôle 1 — à la naissance : aucune écriture ne doit pouvoir DÉMARRER.
    if (_resetEnCours) return false;

    final generation = _generationCache;
    final prefs = await SharedPreferences.getInstance();

    // Contrôle 2 — avant démarrage effectif de l'action : rattrape celles
    // qui étaient suspendues sur `getInstance()` quand le reset a commencé.
    if (_resetEnCours || generation != _generationCache) return false;

    // ↓↓↓ AUCUN `await` de ce point jusqu'au `add` ↓↓↓
    final Future<bool> f = _executerEcriture(prefs, action);
    _ecrituresEnCours.add(f);
    f.whenComplete(() => _ecrituresEnCours.remove(f)).ignore();
    // ↑↑↑ aucune écriture ne franchit le contrôle 2 sans être vue du drain ↑↑↑

    return f;
  }

  /// Corps de l'écriture, isolé pour que [_ecrireProtege] obtienne la future
  /// AVANT le premier `await`. `_executerEcriture` étant `async`, son corps
  /// s'exécute synchroniquement jusqu'à `await action(prefs)`.
  ///
  /// L'exception est capturée ici, journalisée et mémorisée : le drain peut
  /// attendre la future sans risque d'erreur asynchrone non gérée, et
  /// l'erreur reste visible pour le diagnostic.
  Future<bool> _executerEcriture(
      SharedPreferences prefs,
      Future<void> Function(SharedPreferences prefs) action) async {
    try {
      await action(prefs);
      return true;
    } catch (e, st) {
      _derniereErreurEcriture = e;
      debugPrint('AlertService._ecrireProtege error: $e\n$st');
      return false;
    }
  }

  /// Refus SILENCIEUX d'une écriture de `SharedPreferences` : le support a
  /// rendu `false` sans lever d'exception.
  ///
  /// ⚠️ POURQUOI UNE EXCEPTION, ET POURQUOI PRIVÉE.
  ///    `_ecrireProtege` a UN SEUL chemin d'échec fiable : `_executerEcriture`
  ///    capture les exceptions et rend `false`. Réutiliser ce chemin évite de
  ///    toucher à la barrière de reset, donc de rouvrir un mécanisme déjà
  ///    validé par la suite B5c. Le type est privé : il ne fait pas partie de
  ///    l'API publique et ne peut pas fuiter chez un appelant.
  ///
  ///    Le refus n'est PAS avalé : il devient `false` ET il est mémorisé
  ///    dans [derniereErreurEcriture], donc diagnostiquable.
  ///
  /// Sauvegarde l'état complet de l'AlertService.
  ///
  /// Rend `true` si les SIX écritures ont réellement abouti.
  ///
  /// ★ LOT 2-C — `_ecrireProtege` rendait déjà un `bool` fiable (mesuré :
  /// `false` sur exception via `_executerEcriture`, `false` si un reset est en
  /// cours). `_save` le JETAIT. On le PROPAGE : c'est la seule façon de
  /// n'annoncer une décision enregistrée QUE si sa persistance est confirmée.
  ///
  /// ⚠️ DÉFAUT MESURÉ, CORRIGÉ ICI — `SharedPreferences.setStringList` rend un
  ///    `bool`. Les six appels ci-dessous IGNORAIENT cette valeur (mesuré :
  ///    `grep -c "if (!await prefs.setString"` → **0**, aucune capture du tout).
  ///    Un support qui REFUSE sans lever d'exception (`return false`) était donc
  ///    indiscernable d'un succès : `_ecrireProtege` ne bascule sur `false` que
  ///    s'il y a une EXCEPTION, et il n'y en avait pas. Le service annonçait
  ///    alors « suivi écrit » sur une écriture refusée — un faux succès, ce que
  ///    ce lot doit rendre impossible.
  ///
  ///    Correctif MINIMAL : chaque écriture est capturée ; si l'une d'elles a
  ///    été refusée, l'action lève [_EcritureAlertesRefusee], que
  ///    `_executerEcriture` transforme déjà en `false` (chemin existant, aucune
  ///    signature modifiée) et mémorise dans [derniereErreurEcriture].
  ///
  ///    Politique TOUT-OU-RIEN assumée : si une seule des six écritures est
  ///    refusée, on ne prétend pas que la sauvegarde a réussi. Le sens est
  ///    conservateur — on peut annoncer `durableSeul` alors que le suivi a
  ///    partiellement abouti, jamais l'inverse.
  ///
  /// ⚠️ LES SIX ÉCRITURES SONT INCHANGÉES, à l'octet près (mêmes clés, mêmes
  ///    valeurs, même ordre). Seuls le type de retour, la CAPTURE des six
  ///    résultats et la valeur rendue changent.
  Future<bool> _save() async {
    // ★ B5c : _save ne gère pas le registre, il délègue entièrement.
    return _ecrireProtege((prefs) async {
      final configEcrit =
          await prefs.setString(_configKey, json.encode(_config.toJson()));
      final alertsToSave = _alerts.take(50).map((a) => json.encode(a.toJson())).toList();
      final alertsEcrit = await prefs.setStringList(_alertsKey, alertsToSave);
      final trackedToSave = _trackedCourses.values.map((tc) => json.encode(tc.toJson())).toList();
      final trackedEcrit = await prefs.setStringList(_trackedKey, trackedToSave);
      // ★ Bug fix : persister les IDs envoyés (max 200 pour limiter la taille)
      final sentToSave = _sentAlertIds.take(200).toList();
      final sentEcrit = await prefs.setStringList(_sentIdsKey, sentToSave);
      // ★ Bug fix : persister les résultats vérifiés (max 100)
      final resultatsToSave = _resultatsVerifies.take(100).toList();
      final resultatsEcrit =
          await prefs.setStringList(_resultatsKey, resultatsToSave);
      // ★ v10.24 audit : persister les alertes cote-chute envoyées (max 100, jour glissant)
      final coteChuteToSave = _coteChuteNotifies.take(100).toList();
      final coteChuteEcrit =
          await prefs.setStringList(_coteChuteKey, coteChuteToSave);
      // Les six sont tentées dans TOUS les cas (aucun court-circuit : une
      // écriture non tentée serait un autre mensonge). On ne tranche qu'après.
      if (!configEcrit ||
          !alertsEcrit ||
          !trackedEcrit ||
          !sentEcrit ||
          !resultatsEcrit ||
          !coteChuteEcrit) {
        throw const _EcritureAlertesRefusee();
      }
    });
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
    // ★ B5c : pendant le reset, la config RAM doit rester `AlertConfig.defaut`.
    //   Sans ce garde, `_config` serait écrasée par l'ancienne config (RAM)
    //   alors que sa clé est effacée : `_save()` bloqué, mais l'état RAM
    //   redeviendrait incohérent avec le disque et pourrait être persisté
    //   plus tard, restaurant l'ancienne configuration.
    if (_resetEnCours) return;
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
    // ★ B5c : pendant le reset, un pari ajouté resterait en RAM (map déjà
    //   vidée) sans jamais atteindre le disque (clé effacée, `_save()` bloqué).
    //   Ce serait un « pari fantôme » visible jusqu'au redémarrage.
    if (_resetEnCours) return;
    // ★ Fix option A : plusieurs paris possibles sur la même course
    // On ajoute un timestamp à la clé pour que chaque pari soit unique
    // Ex: R4C7_23042026 → R4C7_23042026_1745000000000
    final baseKey = overrideKey ?? course.key;
    // ★ B1-T12 / étape 1 (complément) — UNE SEULE GÉNÉRATION D'IDENTIFIANT.
    //
    //  DÉFAUT MESURÉ AVANT CETTE CORRECTION : cette ligne ajoutait TOUJOURS un
    //  second horodatage, même quand l'appelant fournissait déjà une clé
    //  complète via `overrideKey`. Depuis que `bet_bottom_sheet` fabrique la
    //  clé de liaison, la valeur réellement persistée devenait donc
    //  `<baseKey>_<ts1>_<ts2>`, alors que `UserPrediction.idTicketLie`
    //  pointait sur `<baseKey>_<ts1>` : la LIAISON RETOUR ÉTAIT PENDANTE.
    //  `tracked.idTicketLie` visait juste, mais `prediction.idTicketLie` non.
    //
    //  RÈGLE CORRIGÉE : un identifiant fourni par l'appelant est utilisé TEL
    //  QUEL (il est déjà complet et unique) ; sinon on en génère un. Plus
    //  aucune concaténation aveugle, donc plus de désalignement possible.
    final storageKey = overrideKey ?? genererIdentifiantTicket(baseKey);
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
      // ★ LOT B2-C : sans ces deux lignes, la ventilation serait perdue
      //   ici même — exactement le défaut corrigé par R1 sur `storageKey`.
      miseGagnant: course.miseGagnant,
      misePlace: course.misePlace,
      // ★ SOUS-LOT B : même piège R1 — les deux cotes par composante aussi.
      coteGagnant: course.coteGagnant,
      cotePlace: course.cotePlace,
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
      // ★ LOT B-2 : l'arrivée structurée suit `arriveeFinale`, qui est
      //   recopiée telle quelle deux lignes plus haut. Les groupes restent
      //   donc cohérents par construction. Sans ces deux lignes, un ticket
      //   ré-ajouté perdrait ses ex æquo et son caractère définitif.
      arriveeGroupes: course.arriveeGroupes,
      arriveeDefinitive: course.arriveeDefinitive,
      // ★ ÉTAPE 4-F : les quatre champs de capture DOIVENT survivre à cette
      //   reconstruction. Sans ces lignes, tout ticket tiercé/couplé ordre
      //   perdrait sa variante et son ordre dès l'appel à `ajouterSuivi`,
      //   c'est-à-dire AVANT même la première sauvegarde — même piège que
      //   `storageKey` (R1) et que la ventilation G+P (B2-C).
      codePmuOfficiel: course.codePmuOfficiel,
      varianteChoisie: course.varianteChoisie,
      numerosDansOrdre: course.numerosDansOrdre,
      formulePari: course.formulePari,
      // ★ LOT B-1 : MÊME PIÈGE, CINQUIÈME OCCURRENCE. Cette reconstruction
      //   champ-par-champ oublierait les sept champs de gain PMU exactement
      //   comme elle oubliait `storageKey` (R1), la ventilation G+P (B2-C) et
      //   la capture 4-F. Les sept lignes ci-dessous ferment ce point de
      //   perte AVANT qu'un gain existe : aujourd'hui les deux seuls
      //   appelants de `ajouterSuivi` (mes_paris_screen.dart:3083 et
      //   bet_bottom_sheet.dart:3116) créent des tickets neufs, donc sans
      //   gain. Le jour où un ticket déjà résolu sera ré-ajouté (reprise,
      //   duplication, resynchronisation), il perdrait son gain sans ces
      //   lignes — et un ticket sans état de gain est un ticket dont le
      //   « Gain gagné » retomberait silencieusement à néant.
      etatGain: course.etatGain,
      rapportsAttribues: course.rapportsAttribues,
      etatTirelire: course.etatTirelire,
      dividendeGagnant: course.dividendeGagnant,
      dividendePlace: course.dividendePlace,
      miseBaseCentimesUtilisee: course.miseBaseCentimesUtilisee,
      motifNonDetermination: course.motifNonDetermination,
      // ★ B1-T12 / étape 1 — SIXIÈME OCCURRENCE DU PIÈGE R1.
      //   Cette reconstruction champ-par-champ oublierait le gain manuel et
      //   la liaison exactement comme elle oubliait `storageKey` (R1), la
      //   ventilation G+P (B2-C), la capture 4-F et les sept champs B-1.
      //   Un ticket porteur d'un gain déclaré par l'utilisateur perdrait ce
      //   gain dès le ré-ajout au suivi s'il n'était pas recopié ici.
      montantGainManuel: course.montantGainManuel,
      idTicketLie: course.idTicketLie,
      // ★ CHANTIER 1/3 — le remboursement officiel survit au ré-ajout au suivi.
      remboursementPmu: course.remboursementPmu,
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

  /// ★ B1-T12 / étape 2 (lot 2-A) — ENREGISTRE UN GAIN DÉCLARÉ PAR L'UTILISATEUR.
  ///
  /// Écrit `montantGainManuel` sur LE ticket désigné par sa CLÉ PERSISTANTE.
  ///
  /// [storageKey] est la clé RÉELLE du ticket (`trackedCourses.keys`), jamais
  /// une clé reconstituée : aucun rapprochement par réunion, course ou heure.
  ///
  /// [montant] à `null` ANNULE la déclaration (retour au calcul PMU).
  ///
  /// ★ LOT 2-C — CE QUI A CHANGÉ : le lot 2-A n'écrivait que le suivi
  /// TEMPORAIRE (`tracked_courses_v1`), purgé après 24 h. Le gain déclaré
  /// disparaissait donc avec lui. Il est désormais écrit AUSSI dans
  /// `UserPrediction`, qui n'est jamais purgé — quand la liaison est CERTAINE.
  ///
  /// ⚠️ CONTRAT HISTORIQUE PRÉSERVÉ (aucun test modifié) : `true` = le gain
  ///    est retenu, `false` = rien n'a été enregistré. La version détaillée
  ///    ci-dessous nomme l'issue ; celle-ci la réduit à ce contrat.
  Future<bool> enregistrerGainManuel(String storageKey, double? montant) async {
    final r = await enregistrerGainManuelDetaille(storageKey, montant);
    return r == ResultatEcritureGain.complet ||
        r == ResultatEcritureGain.durableSeul ||
        r == ResultatEcritureGain.nonLie;
  }

  /// ★ LOT 2-C — MÊME ÉCRITURE, ISSUE NOMMÉE, ORDRE FINANCIER RESPECTÉ.
  ///
  /// ORDRE IMPÉRATIF : ① écriture FINANCIÈRE durable → ② confirmation réelle
  /// → ③ écriture du suivi temporaire → ④ confirmation.
  ///
  /// Un échec ① interrompt TOUT : on n'a encore rien touché d'autre, donc
  /// rien à défaire. Un échec ③ sur un ticket lié conserve le durable
  /// (`durableSeul`). Un échec ③ sur un ticket NON lié réaligne la mémoire
  /// sur le disque : on n'affiche jamais un montant que le disque n'a pas.
  Future<ResultatEcritureGain> enregistrerGainManuelDetaille(
      String storageKey, double? montant) async {
    final tc = _trackedCourses[storageKey];
    if (tc == null) return ResultatEcritureGain.ticketIntrouvable;

    final pmu = _pmuProvider;
    // ⚠️ NOM DE VARIABLE CONTRAINT PAR LA BARRIÈRE B4.4/10.13 (mesurée) :
    //    ce fichier ne doit contenir AUCUNE des trois appellations de clé de
    //    profil que le test recherche, pas même dans un commentaire.
    //    `TrackedCourse` ne porte que sa propre clé, `idTicketLie`.
    final cleTicketProfil = tc.idTicketLie;
    // LIAISON STRICTE : uniquement l'identifiant persistant. Jamais une
    // déduction par réunion, course, date ou type de pari.
    final liee = pmu != null && cleTicketProfil != null;

    if (liee) {
      // ① + ② — l'unique écriture qui survit à la purge.
      final issue =
          await pmu.enregistrerGainManuelPrediction(cleTicketProfil, montant);
      if (issue == IssueEcritureGain.echec) {
        return ResultatEcritureGain.echecFinancier;
      }
      if (issue == IssueEcritureGain.echecNonReconcilie) {
        return ResultatEcritureGain.echecNonReconcilie;
      }
      if (issue == IssueEcritureGain.remplacee) {
        // Une modification plus récente fait foi : on n'écrit PAS le suivi
        // (il décrirait un montant qui n'est plus en vigueur) et on le DIT.
        return ResultatEcritureGain.remplaceeParPlusRecente;
      }
      // `confirme` : on poursuit vers le suivi temporaire.
    }

    // ③ — suivi temporaire, écriture inchangée.
    if (tc.montantGainManuel != montant) {
      _trackedCourses[storageKey] = tc.copieAvecGainManuel(montant);
      notifyListeners();
    }
    // ④ — le résultat de cette écriture est CAPTURÉ, plus jamais ignoré.
    final suiviEcrit = await _save();

    if (suiviEcrit) {
      return liee ? ResultatEcritureGain.complet : ResultatEcritureGain.nonLie;
    }
    if (liee) return ResultatEcritureGain.durableSeul;
    // Rien de durable, suivi non écrit ⇒ réalignement de la mémoire sur le
    // disque : aucun montant trompeur n'est laissé à l'écran.
    _trackedCourses[storageKey] = tc;
    notifyListeners();
    return ResultatEcritureGain.echecFinancier;
  }

  Future<void> retirerSuivi(String key) async {
    _trackedCourses.remove(key);
    notifyListeners();
    await _save();
  }

  /// ★ B1-T12 / étape 1 (complément) — DÉLIE un suivi de son ticket de profil.
  ///
  /// RAISON D'ÊTRE : la création d'un pari fait DEUX écritures distinctes et
  /// non transactionnelles (`ajouterSuivi` puis `addPrediction`). Si la
  /// seconde échoue, le suivi survivrait en prétendant être lié à un ticket
  /// de profil qui n'existe pas. Cette méthode remet `idTicketLie` à `null`
  /// pour que l'état publié soit « non lié » — une information honnête,
  /// jamais une association erronée.
  ///
  /// Ne touche À RIEN d'autre : ni le verdict, ni les rapports, ni les sept
  /// champs B-1, ni `dividendePmuReel`. Un ticket non lié conserve donc
  /// l'intégralité de son contenu et son propre gain manuel.
  Future<void> delierSuivi(String storageKey) async {
    final tc = _trackedCourses[storageKey];
    if (tc == null) return;
    if (tc.idTicketLie == null) return; // déjà non lié : rien à faire
    // ⚠️ AUCUNE COPIE LOCALE ICI : le test B4.4/12.3 verrouille le fait que
    //   ce fichier n'en contient aucune (une seule occurrence, AlertConfig).
    //   La copie déliée est fournie par l'extension TrackedCourseCopy, dans
    //   `enregistreur_verdict_gain_suivi.dart`, où elle a sa place.
    _trackedCourses[storageKey] = tc.copieDeliee();
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
    // ★ LOT B-2 bis — arrivée structurée, facultative. `null` = groupes
    //   inconnus ou arrivée provisoire. Jamais déduite de `arrivee`.
    List<List<int>>? arriveeGroupes,
    bool? arriveeDefinitive,
  }) async {
    final tc = _trackedCourses[courseKey];
    if (tc == null) return;
    if (tc.isGagne != null) return; // déjà enregistré, ne pas écraser
    _trackedCourses[courseKey] = tc.withResultat(
      isGagne: isGagne,
      arrivee: arrivee,
      message: message,
      arriveeGroupes: arriveeGroupes,
      arriveeDefinitive: arriveeDefinitive,
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

  /// ★ LOT B-4.5 — Persiste un ticket DÉJÀ RÉSOLU par l'enregistreur B-4.4.
  ///
  /// POURQUOI CETTE MÉTHODE EXISTE : `ajouterSuivi` fabrique TOUJOURS une
  /// nouvelle `storageKey` (`${baseKey}_${millisecondes}`), donc elle ne peut
  /// pas mettre à jour un ticket existant sans en créer un doublon. Or un
  /// verdict doit s'écrire sur le ticket EXISTANT.
  ///
  /// ⚠️ ELLE N'ÉCRIT AUCUNE DÉCISION : le ticket reçu est celui que
  ///    l'enregistreur B-4.4 a produit. Cette méthode le range sous sa clé et
  ///    sauvegarde, rien de plus. Aucun `isGagne`, aucun `dividendePmuReel`,
  ///    aucun `messageResultat` n'y est calculé ni modifié.
  ///
  /// ⚠️ ELLE NE DÉCLENCHE AUCUNE SYNCHRONISATION IA : elle n'appelle ni
  ///    `PmuProvider.enregistrerDividendePmu`, ni `_syncStatsTypesIA`, ni
  ///    `IaMemoryService`.
  ///
  /// Rend `true` si le ticket existait et a été remplacé, `false` sinon.
  Future<bool> appliquerVerdictGainSuivi(
    String courseKey,
    TrackedCourse ticketResolu,
  ) async {
    final existant = _trackedCourses[courseKey];
    if (existant == null) return false;
    // La clé de rangement est conservée : aucun doublon n'est créé.
    _trackedCourses[courseKey] = ticketResolu;
    notifyListeners();
    await _save();
    return true;
  }

  // ── Ajout d'alerte ────────────────────────────────────────────────────────

  void _addAlert(AppAlert alert) {
    // ★ B5c : pendant le reset, aucune alerte ne doit être émise. Sans ce
    //   garde, `_sendNativeNotification` écrirait la file de notifications
    //   natives (chemin d'écriture n°2) hors de tout enregistrement, et
    //   `_alerts` se repeuplerait juste avant d'être vidé.
    if (_resetEnCours) return;
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
    // ★ B5c — chemin d'écriture n°2 : passe par la barrière.
    await _ecrireProtege((prefs) async {
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
    });
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
    // ★ B5c — chemin d'écriture n°3 : passe par la barrière.
    await _ecrireProtege((prefs) async {
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
    });
  }

  /// Marque un favori comme "déjà parié" pour éviter les alertes redondantes.
  /// À appeler quand l'utilisateur place un pari sur cette course.
  Future<void> marquerFavoriCommeParI(int numR, int numC) async {
    // ★ B5c — chemin d'écriture n°4 : passe par la barrière.
    await _ecrireProtege((prefs) async {
      final raw = prefs.getString(_favoritesKey) ?? '[]';
      final List<dynamic> list = json.decode(raw) as List<dynamic>;
      for (final e in list) {
        if ((e as Map)['numR'] == numR && e['numC'] == numC) {
          e['dejaParI'] = true;
        }
      }
      await prefs.setString(_favoritesKey, json.encode(list));
    });
  }

  /// Supprime les favoris des jours passés (nettoyage automatique).
  Future<void> nettoyerFavorisObsoletes() async {
    // ★ B5c — chemin d'écriture n°5 : passe par la barrière.
    await _ecrireProtege((prefs) async {
      final raw = prefs.getString(_favoritesKey) ?? '[]';
      final List<dynamic> list = json.decode(raw) as List<dynamic>;
      final hier = DateTime.now().subtract(const Duration(days: 1));
      list.removeWhere((e) {
        final ajouteLe = DateTime.tryParse((e as Map)['ajouteLe'] as String? ?? '');
        return ajouteLe != null && ajouteLe.isBefore(hier);
      });
      await prefs.setString(_favoritesKey, json.encode(list));
    });
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
          ? '$nomCheval (N°${numeroCheval ?? "?"}) '
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

  // ★ CHANTIER 2/3 ── Alerte de GAIN OFFICIEL TARDIF ───────────────────────
  //
  /// Émet LA notification de remontée tardive pour le ticket [idTicket].
  ///
  /// Rend `true` SEULEMENT si l'alerte a réellement été enregistrée ET que sa
  /// persistance a été confirmée par [_save]. Un `false` ne dit donc jamais
  /// « notification produite » : l'appelant (`ServiceGainsTardifs`) s'en sert
  /// pour décider de NE PAS poser son marqueur d'idempotence, afin que le
  /// ticket reste renotifiable au cycle suivant.
  ///
  /// ⚠️ IDENTIFIANT STABLE, JAMAIS HORODATÉ.
  ///    `signalerResultat` compose `'${courseKey}_result_${aaaa}${m}${j}'`,
  ///    ce qui autorise UNE alerte par course et par jour. Ici l'exigence est
  ///    « une seule par TICKET, à vie » : l'identifiant est donc dérivé du
  ///    seul `idTicket`. Deux cycles de détection, deux rafraîchissements, un
  ///    redémarrage ou une nouvelle récupération du même rapport produisent
  ///    le MÊME identifiant, donc une seule entrée (`_sentAlertIds` la
  ///    refuse, et `_addAlert` la refuse une seconde fois).
  ///
  /// ⚠️ CE QUE CETTE MÉTHODE NE FAIT PAS — ET NE DOIT JAMAIS FAIRE :
  ///    • elle n'écrit AUCUN montant, ne décide RIEN (une notification lue ou
  ///      fermée ne vaut ni acceptation ni refus) ;
  ///    • elle n'est PAS la preuve durable de l'idempotence : `_sentAlertIds`
  ///      et `_alerts` sont purgés (reset, plafond de 100, restauration). La
  ///      preuve durable est `MemoireGainsTardifsNotifies`, hors de ce fichier.
  Future<bool> emettreAlerteGainTardif({
    required String idTicket,
    required String titre,
    required String message,
    required int numReunion,
    required int numCourse,
    String? dateStrCourse,
  }) async {
    // Le filtre de configuration le plus proche du sens métier : un
    // utilisateur qui coupe les alertes de résultats ne veut pas non plus
    // être relancé sur un gain officiel. On n'invente pas de nouveau flag.
    if (!_config.activerResultats) return false;

    final id = 'gainTardif_$idTicket';
    // Déjà enregistrée (mémoire ou disque rechargé) : rien à refaire. On rend
    // `true` car la notification EXISTE — c'est un succès idempotent, pas un
    // échec, et le marqueur durable peut donc être posé sans mentir.
    if (_sentAlertIds.contains(id)) return true;

    _addAlert(AppAlert(
      id: id,
      type: AlertType.gainTardif,
      titre: titre,
      message: message,
      timestamp: DateTime.now(),
      numReunion: numReunion,
      numCourse: numCourse,
      dateStrCourse: dateStrCourse,
    ));

    // ⚠️ `_addAlert` ne rend rien et `_save()` est lancé sans être attendu à
    //    l'intérieur : on attend ICI la persistance réelle, puis on confirme
    //    par une relecture du disque. Un `setStringList` refusé sans exception
    //    est déjà transformé en `false` par `_save` (capture des six retours).
    final persiste = await _save();
    if (!persiste) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final brut = prefs.getStringList(_alertsKey) ?? const <String>[];
    for (final ligne in brut) {
      try {
        final j = json.decode(ligne) as Map<String, dynamic>;
        if (j['id'] == id) return true;
      } catch (_) {
        // Ligne illisible : elle ne prouve rien, on continue.
      }
    }
    return false;
  }

  // ★ v3.0 ── Alerte non-partant (appelée par DataRefreshService) ─────────
  //
  // ★ CHANTIER 2/3 — VIDE L'HISTORIQUE DES ALERTES, POUR LES TESTS SEULEMENT.
  //
  //  Il reproduit exactement ce que fait la purge réelle sur `_alerts` et
  //  `_sentAlertIds`, SANS toucher aux autres clés. Il permet donc de
  //  DÉMONTRER que l'idempotence des gains tardifs ne repose pas sur
  //  l'historique temporaire — ce qui est l'exigence du chantier.
  //
  //  ⚠️ Aucun écran, aucun service de production ne l'appelle.
  @visibleForTesting
  Future<void> reinitialiserHistoriquePourTest() async {
    _alerts.clear();
    _sentAlertIds.clear();
    notifyListeners();
    await _save();
  }

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
  /// ★ B5c — chemin d'écriture n°6 : passe par la barrière.
  Future<void> _sauvegarderConseilIANotifies() async {
    await _ecrireProtege((prefs) async {
      await prefs.setStringList(_conseilIANotifiesKey, _conseilIANotifies.toList());
    });
  }

  /// Réinitialise les courseKeys notifiées (appelé au changement de jour).
  ///
  /// ★ B5c — chemin d'écriture n°7 : les DEUX écritures (`_date` et la liste)
  ///   sont regroupées dans UN SEUL bloc protégé. Séparées, un reset pourrait
  ///   s'intercaler entre les deux et laisser `_date` réapparaître sur le
  ///   disque sans sa liste. Groupées, le drain attend le bloc entier :
  ///   soit les deux écritures passent puis sont effacées, soit aucune.
  Future<void> _resetConseilIANotifiesIfNewDay() async {
    final prefs   = await SharedPreferences.getInstance();
    final today   = DateTime.now();
    final todayKey = '${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';
    final stored  = prefs.getString('${_conseilIANotifiesKey}_date') ?? '';
    if (stored != todayKey) {
      _conseilIANotifies.clear();
      await _ecrireProtege((prefs) async {
        await prefs.setString('${_conseilIANotifiesKey}_date', todayKey);
        await prefs.setStringList(_conseilIANotifiesKey, _conseilIANotifies.toList());
      });
    }
  }

  /// ★ v10.23 — Résumé matinal : combien de courses correspondent aux critères.
  /// Appelé à la 1ère connexion du jour depuis HomeScreen.
  /// Retourne le message IA à afficher dans la bulle (ou null si rien à dire).
  Future<String?> verifierCoursesConseilIA(List<ZtReunion> reunions) async {
    // ★ B5c : pendant le reset, aucune écriture `conseil_ia_resume_date` et
    //   aucune mutation de `_conseilIANotifies` ne doivent avoir lieu.
    if (_resetEnCours) return null;
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
      // ★ B5c — chemin d'écriture n°8 : passe par la barrière.
      await _ecrireProtege((prefs) async {
        await prefs.setString(_conseilIAResumeDateKey, todayKey);
      });
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
    // ★ B5c : pendant le reset, la boucle ne doit pas repartir — elle
    //   déclencherait `_addAlert` → `_save` (bloqué) mais aussi
    //   `_sauvegarderConseilIANotifies` après le drain.
    if (_resetEnCours) return;
    if (!_config.activerConseilIA) return;
    await _resetConseilIANotifiesIfNewDay();
    await _chargerConseilIANotifies();

    final courses = _filtrerCoursesSelonCriteresConseils(reunions);

    for (final item in courses) {
      // ★ v10.25 — Filtre périmètre : respecter scope favoris/suivies/toutes
      final courseKey = '${item.reunion.code}C${item.course.numCourse}';
      if (!_coursePasseFiltreByCourseKey(courseKey)) continue;

      final key = '${item.course.nom}_${item.reunion.lieu}';
      if (_conseilIANotifies.contains(key)) continue; // déjà notifié

      // ★ B5c — S1 : course déjà connue AVANT le dernier reset. On l'enregistre
      //   comme annoncée sans émettre d'alerte, pour ne pas rejouer une rafale
      //   sur des courses que l'utilisateur voyait déjà. `remove` (et non
      //   `contains`) garantit qu'une clé n'est tue qu'UNE fois : si elle
      //   réapparaît plus tard, elle suivra le chemin normal.
      //   Une course ABSENTE de cet instantané est réellement nouvelle → elle
      //   est notifiée normalement.
      //   ⚠️ R-21 : cet instantané vit en RAM ; il disparaît au redémarrage.
      //   Après un reset suivi d'une relance avant tout refresh, le premier
      //   refresh notifie une fois les courses du jour (limite documentée).
      if (_conseilIASilencieux.remove(key)) {
        _conseilIANotifies.add(key);
        continue;
      }

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

  // ★ v10.63 : caches synchrones pour bandeau Home (sans FutureBuilder)
  // mis à jour par recalculerCoursesConseilIA() après chaque refresh/changement.
  List<({ZtCourse course, ZtReunion reunion})> _coursesMatchingConseils    = [];
  List<({ZtCourse course, ZtReunion reunion})> _toutesCoursesConseilIALst  = [];
  bool     _conseilsFiltresActifs      = true;
  List<String> _conseilsFiltresTypes   = [];
  List<String> _conseilsFiltresHippos  = [];
  List<String> _conseilsFiltresDiscs   = [];
  int      _conseilsFiltresConfMin     = 0;

  // Getters synchrones utilisés par _buildBandeauConseilIA() via context.watch
  bool         get conseilsFiltresActifs      => _conseilsFiltresActifs;
  List<String> get conseilsFiltresTypesParis  => _conseilsFiltresTypes;
  List<String> get conseilsFiltresHippodromes => _conseilsFiltresHippos;
  List<String> get conseilsFiltresDisciplines => _conseilsFiltresDiscs;
  int          get conseilsFiltresConfianceMin => _conseilsFiltresConfMin;

  /// Toutes les courses IA disponibles AVANT filtres (bouton ON + aucun critère).
  List<({ZtCourse course, ZtReunion reunion})> get toutesCoursesConseilIA => _toutesCoursesConseilIALst;

  /// Recalcule les courses correspondant aux critères Conseils IA.
  /// ★ v10.63 : logique 3 états (OFF / ON+aucunCritère / ON+critères)
  /// Appelé après chaque refresh ET au retour de la page Conseils IA.
  Future<int> recalculerCoursesConseilIA(List<ZtReunion> reunions) async {
    final prefs = await SharedPreferences.getInstance();

    // ── Lire l'état bouton ON/OFF ──────────────────────────────────────
    final filtresActifs = prefs.getBool('conseils_filtres_actifs') ?? true;
    final types   = prefs.getStringList('conseils_filtres_types_paris')  ?? [];
    final hippos  = prefs.getStringList('conseils_filtres_hippodromes')  ?? [];
    final discs   = prefs.getStringList('conseils_filtres_disciplines')  ?? [];
    final confMin = prefs.getInt('conseils_filtres_confiance_min')       ?? 0;

    // Mettre à jour les caches synchrones (lus par le bandeau Home)
    _conseilsFiltresActifs   = filtresActifs;
    _conseilsFiltresTypes    = types;
    _conseilsFiltresHippos   = hippos;
    _conseilsFiltresDiscs    = discs;
    _conseilsFiltresConfMin  = confMin;

    // ── Construire la liste de TOUTES les courses IA (avant filtres) ──
    // Utilisée par le cas ON+aucun critère pour afficher le vrai total.
    final toutesIA = <({ZtCourse course, ZtReunion reunion})>[];
    for (final r in reunions) {
      for (final c in r.courses) {
        if (c.partants.isNotEmpty) toutesIA.add((course: c, reunion: r));
      }
    }
    _toutesCoursesConseilIALst = toutesIA;

    // ── État 1 : bouton OFF → liste vide (pas d'alerte Dernière chance) ──
    if (!filtresActifs) {
      _coursesMatchingConseils = [];
      notifyListeners();
      return 0;
    }

    // ── État 2 : bouton ON + aucun critère → toutes les courses IA ──
    // RÈGLE MÉTIER : ON sans critère = "Tous les conseils IA"
    final aucunCritere = types.isEmpty && hippos.isEmpty &&
        discs.isEmpty && confMin <= 0;
    if (aucunCritere) {
      _coursesMatchingConseils = toutesIA;
      notifyListeners();
      return toutesIA.length;
    }

    // ── État 3 : bouton ON + critères → filtrage ──────────────────────
    final result = <({ZtCourse course, ZtReunion reunion})>[];
    for (final r in reunions) {
      for (final c in r.courses) {
        if (c.partants.isEmpty) continue;
        final score    = c.partantsParRangIA.isNotEmpty
            ? c.partantsParRangIA.first.scoreIA : 0.0;
        final typePari = _getTypePariPourCourse(c);
        final hippo    = r.lieu.toUpperCase();
        final disc     = r.discipline.isEmpty ? ''
            : r.discipline[0].toUpperCase() + r.discipline.substring(1).toLowerCase();

        if (types.isNotEmpty   && !types.contains(typePari))  continue;
        if (confMin > 0        && score < confMin)            continue;
        if (hippos.isNotEmpty  && !hippos.contains(hippo))    continue;
        if (discs.isNotEmpty   && !discs.contains(disc))      continue;

        result.add((course: c, reunion: r));
      }
    }

    _coursesMatchingConseils = result;
    notifyListeners(); // met à jour le bandeau HomeScreen
    return result.length;
  }

  /// Getter public pour le bandeau HomeScreen (liste filtrée selon état actuel).
  List<({ZtCourse course, ZtReunion reunion})> get coursesConseilIA => _coursesMatchingConseils;

  /// Résumé des critères actifs pour l'affichage (rétrocompatibilité).
  /// ★ v10.63 : lit correctement le bouton ON/OFF ('conseils_filtres_actifs').
  Future<Map<String, dynamic>> getCriteresConseilIA() async {
    final prefs   = await SharedPreferences.getInstance();
    final actifs  = prefs.getBool('conseils_filtres_actifs') ?? true;
    final types   = prefs.getStringList('conseils_filtres_types_paris')  ?? [];
    final hippos  = prefs.getStringList('conseils_filtres_hippodromes')  ?? [];
    final discs   = prefs.getStringList('conseils_filtres_disciplines')  ?? [];
    final confMin = prefs.getInt('conseils_filtres_confiance_min')       ?? 0;
    return {
      'actifs':   actifs,   // bouton ON/OFF réel
      'types':    types,
      'hippos':   hippos,
      'discs':    discs,
      'confMin':  confMin,
    };
  }

  /// Calcule le type de pari recommandé pour une course.
  ///
  /// ★ CORRECTION BLOC 1 (BL1-A02 / BL1-A08 / BL1-A14 / BL3-A26) — SOURCE UNIQUE
  ///
  ///   AVANT : cette méthode était une COPIE de celle de `conseils_screen`
  ///   (son propre commentaire l'admettait : « copie de conseils_screen »),
  ///   donc une cascade FIGÉE n'ayant jamais accès aux seuils adaptatifs.
  ///   L'alerte « Dernière chance » pouvait donc annoncer un type de pari
  ///   différent de celui affiché par Best Bet pour la même course.
  ///
  ///   APRÈS : délégation à `cascadeRecommandation()`. Aucune valeur
  ///   numérique n'est modifiée ; les seuils appris sont enfin respectés par
  ///   les notifications comme par les écrans.
  String _getTypePariPourCourse(ZtCourse course) {
    final sorted = course.partantsParRangIA;
    if (sorted.isEmpty) return 'À surveiller';
    return cascadeRecommandation(
      course: course,
      seuils: IaMemoryService.instance.seuilsConfiance,
      scoreConf: sorted.first.scoreIA,
      score2nd: sorted.length >= 2 ? sorted[1].scoreIA : null,
      score3: sorted.length >= 3 ? sorted[2].scoreIA : null,
      score4: sorted.length >= 4 ? sorted[3].scoreIA : null,
      coteTop: sorted.first.coteDecimale,
    ).typePari;
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
        // ★ v10.25 — Filtre périmètre : respecter scope favoris/suivies/toutes
        final courseKeyDC = '${item.reunion.code}C${item.course.numCourse}';
        if (!_coursePasseFiltreByCourseKey(courseKeyDC)) continue;

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

      // ★ FINALISATION A6 (P5) : L0 PRIORITAIRE, décision PARTAGÉE avec
      //   P1, P2 et P3.
      //
      //   AVANT : ce chemin ne consultait QUE les rapports PMU ordonnés. Une
      //   égalité officielle CONNUE (L0) pouvait donc être écrasée par un
      //   ordre PMU aplati — exactement ce que le mandat interdit.
      //
      //   APRÈS : `deciderArriveeOfficielle` lit L0 d'abord (lecture PURE,
      //   copie profonde `arrivee_officielle_service.dart:593-599`) et ne
      //   retombe sur le repli PMU ordonné que si L0 est ABSENT.
      //
      //   `tc.key` est déjà au format L0 exact
      //   (`R{numReunion}C{numCourse}_JJMMAAAA`, alert_service.dart:2965-2969).
      //
      //   CONTRÔLE D'APPARTENANCE : les partants fiables sont ceux du
      //   programme déjà en mémoire (`DataRefreshService.instance.reunions`),
      //   comme `_triggerReanalyseCourse` le fait l.1977-1993. Liste absente
      //   → contrôle IMPOSSIBLE, donc aucune arrivée refusée pour ce motif ;
      //   aucune liste n'est inventée depuis la longueur de l'arrivée.
      final DecisionArriveeOfficielle decision = deciderArriveeOfficielle(
        groupesL0: ArriveeOfficielleService.instance.arrivee(tc.key),
        rapportsPmu: rapports,
        partants: _partantsDeLaCourse(tc),
      );

      // ── Extraire TOUS les résultats utiles depuis l'API PMU ──────────────
      String? numGagnant;
      double? coteGagnant;
      double? cotePlace;           // cote Placé réelle PMU
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
        double? div(Map<String, dynamic> rap) {
          final d = rap['dividendePourUnEuro'];
          return d != null ? (d as num).toDouble() / 100.0 : null;
        }

        // ── Simple Gagnant → gagnant officiel + cote réelle ───────────────
        // ⚠️ A6 (P5) : ce bloc ne sert PLUS à constituer une arrivée. Il ne
        //    fournit que le numéro gagnant officiel (identique à
        //    `decision.gagnant`) et sa cote. La liste d'arrivée vient
        //    uniquement de `decision.ordre`.
        if (typePari == 'E_SIMPLE_GAGNANT' && rList.isNotEmpty) {
          final rap = rList.first as Map<String, dynamic>;
          numGagnant ??= rap['combinaison']?.toString();
          coteGagnant ??= div(rap);
        }

        // ── Simple Placé → places + cote Placé (JAMAIS un classement) ─────
        if (typePari == 'E_SIMPLE_PLACE' && rList.isNotEmpty) {
          // On garde la cote du 1er cheval placé comme référence
          cotePlace ??= div(rList.first as Map<String, dynamic>);
          for (final p in rList) {
            final n = int.tryParse((p as Map)['combinaison']?.toString() ?? '');
            if (n != null && !placesOfficielles.contains(n)) {
              placesOfficielles.add(n);
            }
          }
        }

        // ── Tiercé ORDRE ──────────────────────────────────────────────────
        if (rList.isNotEmpty &&
            (typePari == 'E_TIERCE' || typePari == 'E_TIERCE_ORDRE' ||
             typePari == 'TIERCE'   || typePari == 'TIERCE_ORDRE') &&
            !typePari.contains('DESORDRE') && !typePari.contains('DÉSORDRE')) {
          // ⚠️ A6 (P5) : le dividende est conservé ; la combinaison n'alimente
          //    PLUS l'arrivée — celle-ci vient uniquement de `decision.ordre`.
          dividendeTierce ??= div(rList.first as Map<String, dynamic>);
        }

        // ── Tiercé DÉSORDRE ───────────────────────────────────────────────
        if (rList.isNotEmpty &&
            (typePari == 'TIERCE_DESORDRE' || typePari == 'E_TIERCE_DESORDRE' ||
             typePari == 'TIERCE_DÉSORDRE' || typePari.contains('TIERCE') &&
             (typePari.contains('DESORDRE') || typePari.contains('DÉSORDRE')))) {
          final rap = rList.first as Map<String, dynamic>;
          dividendeTierceDesordre ??= div(rap);
        }

        // ── Quarté+ ORDRE ─────────────────────────────────────────────────
        if (rList.isNotEmpty &&
            (typePari == 'E_QUARTE' || typePari == 'E_QUARTE_PLUS' ||
             typePari == 'QUARTE'   || typePari == 'QUARTE_PLUS') &&
            !typePari.contains('DESORDRE') && !typePari.contains('DÉSORDRE')) {
          // ⚠️ A6 (P5) : dividende conservé, combinaison non utilisée.
          dividendeQuarte ??= div(rList.first as Map<String, dynamic>);
        }

        // ── Quarté+ DÉSORDRE ──────────────────────────────────────────────
        if (rList.isNotEmpty &&
            (typePari == 'QUARTE_DESORDRE' || typePari == 'E_QUARTE_DESORDRE' ||
             typePari == 'QUARTE_DÉSORDRE' || typePari.contains('QUARTE') &&
             (typePari.contains('DESORDRE') || typePari.contains('DÉSORDRE')))) {
          final rap = rList.first as Map<String, dynamic>;
          dividendeQuarteDesordre ??= div(rap);
        }

        // ── Quinté+ ORDRE ─────────────────────────────────────────────────
        if (rList.isNotEmpty &&
            (typePari == 'E_QUINTE' || typePari == 'E_QUINTE_PLUS' ||
             typePari == 'QUINTE'   || typePari == 'QUINTE_PLUS') &&
            !typePari.contains('DESORDRE') && !typePari.contains('DÉSORDRE') &&
            !typePari.contains('4SUR5') && !typePari.contains('4/5')) {
          // ⚠️ A6 (P5) : dividende conservé, combinaison non utilisée.
          dividendeQuinte ??= div(rList.first as Map<String, dynamic>);
        }

        // ── Quinté+ DÉSORDRE ──────────────────────────────────────────────
        if (rList.isNotEmpty &&
            (typePari == 'QUINTE_DESORDRE' || typePari == 'E_QUINTE_DESORDRE' ||
             typePari == 'QUINTE_DÉSORDRE' || typePari.contains('QUINTE') &&
             (typePari.contains('DESORDRE') || typePari.contains('DÉSORDRE')))) {
          final rap = rList.first as Map<String, dynamic>;
          dividendeQuinteDesordre ??= div(rap);
        }

        // ── Quinté+ BONUS 4/5 ─────────────────────────────────────────────
        if (rList.isNotEmpty &&
            (typePari.contains('4SUR5') || typePari.contains('4_SUR_5') ||
             typePari.contains('QUINTE') && typePari.contains('4'))) {
          final rap = rList.first as Map<String, dynamic>;
          dividendeQuinte4sur5 ??= div(rap);
        }

        // ── Couplé Gagnant ────────────────────────────────────────────────
        if (rList.isNotEmpty &&
            (typePari == 'COUPLE_GAGNANT' || typePari == 'E_COUPLE_GAGNANT' ||
             typePari == 'COUPLÉ_GAGNANT' || typePari == 'COUPLE' ||
             typePari.contains('COUPLE') && typePari.contains('GAGNANT'))) {
          final rap = rList.first as Map<String, dynamic>;
          dividendeCouple ??= div(rap);
        }

        // ── Couplé Placé ──────────────────────────────────────────────────
        if (rList.isNotEmpty &&
            (typePari == 'COUPLE_PLACE' || typePari == 'E_COUPLE_PLACE' ||
             typePari == 'COUPLÉ_PLACÉ' ||
             typePari.contains('COUPLE') && typePari.contains('PLACE'))) {
          final rap = rList.first as Map<String, dynamic>;
          dividendeCouplePlace ??= div(rap);
        }
      }

      // ═══════════════════════════════════════════════════════════════════
      //  ★ FINALISATION A6 (P5) — ARRIVÉE ET GAGNANT ISSUS D'UNE DÉCISION
      //  PARTAGÉE, PLUS DE FABRICATION DE GAIN DEPUIS UN RAPPORT PLACÉ.
      //
      //  AVANT (l.2213-2215) :
      //      if (numGagnant == null && arriveeOfficielle.isNotEmpty) {
      //        numGagnant = arriveeOfficielle.first.toString();
      //      }
      //  Ce repli promouvait le PREMIER cheval d'une liste construite par
      //  empilement des rapports `E_SIMPLE_PLACE` — un cheval simplement PLACÉ —
      //  au rang de GAGNANT, puis `estGagnant` devenait vrai et un gain était
      //  ANNONCÉ. C'est exactement « fabriquer un gain à partir d'un rapport
      //  PLACÉ », que le mandat interdit.
      //
      //  APRÈS : `numGagnant` ne provient PLUS QUE du rapport
      //  `E_SIMPLE_GAGNANT` officiel (`decision.gagnant`), et `arriveeOfficielle`
      //  ne provient PLUS QUE d'un rapport ORDONNÉ, d'au moins
      //  `kLongueurMinimaleArrivee` chevaux, cohérent avec le Simple Gagnant
      //  lorsqu'il existe. `placesOfficielles` reste ce qu'elle est : la liste
      //  des placés, jamais un classement.
      //
      //  Ce qui est PRÉSERVÉ à l'identique : la logique de paiement
      //  `Gagnant+Placé` (CAS 1), les dividendes Tiercé / Quarté / Quinté et
      //  leurs variantes DÉSORDRE, et les alertes non liées au résultat.
      // ═══════════════════════════════════════════════════════════════════

      // Si ni gagnant officiel ni arrivée exploitable → réessayer plus tard.
      if (numGagnant == null && !decision.disponible) {
        // Résultats pas encore disponibles → réessayer au prochain cycle
        _resultatsVerifies.remove(resultKey);
        return;
      }

      // ⚠️ A6 (P5) : EX ÆQUO OFFICIEL → AUCUNE notification de résultat et
      //    AUCUN enregistrement. `IaPronostic.arriveeReelle` est `List<int>?`
      //    (ia_memory_models.dart:285) : aplatir `[[7,12],[8]]` en `[7,12,8]`
      //    inventerait un rang pour 12 et fausserait `rangFavoriIaDansArrivee`,
      //    `nbTop3`, `nbTop5`, `scorePerformance` puis l'ELO. L0 reste intact :
      //    l'affichage des ex æquo passe par les écrans, jamais par ce chemin.
      if (decision.aDesExAequo) {
        if (kDebugMode) {
          debugPrint('[AlertService] ⚠️ ${tc.key} : ${decision.motif}');
        }
        _resultatsVerifies.remove(resultKey);
        return;
      }

      // ⚠️ A6 (P5) : la liste transmise à la mémoire IA est la liste RETENUE,
      //    jamais la liste empilée. Si la décision est refusée, `arriveeRetenue`
      //    est vide et l'enregistrement l.2649 est sauté : rien n'est appris, et
      //    la course reste récupérable au cycle suivant.
      final List<int> arriveeRetenue = decision.arriveePlate;

      // ⚠️ A6 (P5) : plus AUCUNE promotion du premier placé en gagnant.
      //    Si `numGagnant` est null, `estGagnant` reste faux et le message
      //    « Perdu » ne peut plus nommer un gagnant inexistant.

      // ── Analyser le résultat selon le type de pari enregistré ───────────
      final mise = tc.miseEngagee ?? 0.0;
      final typePari = tc.typePari;
      final mesNumeros = tc.numerosJoues;
      final monNumero = tc.numeroCheval?.toString();

      // Top 3 officiels (pour Tiercé, Placé)
      final top3 = arriveeRetenue.take(3).toList();
      final top4 = arriveeRetenue.take(4).toList();
      final top5 = arriveeRetenue.take(5).toList();

      // Résumé de l'arrivée à afficher
      final arriveeStr = arriveeRetenue.take(5).map((n) => 'N°$n').join(' - ');

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
        final top2Set = arriveeRetenue.take(2).toSet();
        final top3Set = arriveeRetenue.take(3).toSet();
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
        final estPlaceViaArrivee = monNumeroInt != null && arriveeRetenue.take(3).contains(monNumeroInt);
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
          titre = '😔 Tiercé perdu — $nbBons/3 bons';
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
              '${div4 != null ? " → Bonus : +${fmtEuros(gainNet)} €" : "\nVérifiez si un bonus de consolation s'applique sur PMU.fr"}';
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
          (n) => !arriveeRetenue.contains(n)).toList();
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
          // ★ LOT A-0 (protection P3) : Gagnant+Placé = 2 composantes.
          //   `gainNet` provient du bloc l.2348-2419, qui calcule le G+P avec
          //   une cote Placé lue sur le MAUVAIS cheval (`cotePlace` vient de
          //   `rList.first` l.2133, alors que l'ordre de `E_SIMPLE_PLACE`
          //   n'est pas le classement officiel — `arrivee_pmu_ordonnee.dart`).
          //   On n'écrit donc RIEN : `isCorrect`/`gainRealise` restent null.
          //   Le RÉSULTAT SPORTIF est conservé : l'arrivée est déjà enregistrée
          //   dans la mémoire IA plus bas (l.2719, hors de cette boucle), et
          //   les notifications d'arrivée (l.2649+) ne dépendent pas d'ici.
          if (estTypeGagnantPlace(pred.typePari)) continue; // A-0
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
      if (arriveeRetenue.isNotEmpty) {
        final aj = tc.heureDepart.day.toString().padLeft(2, '0');
        final am = tc.heureDepart.month.toString().padLeft(2, '0');
        final memKey = tc.iaMemKey ??
            '${tc.key}_$aj$am${tc.heureDepart.year}';
        await IaMemoryService.instance.enregistrerResultat(
          courseKey: memKey,
          arriveeReelle: arriveeRetenue,
        );
        if (kDebugMode) {
          if (kDebugMode) {
            debugPrint('IA Mémoire : résultat enregistré pour $memKey - '
              'Arrivée: ${arriveeRetenue.take(5).join("-")}');
          }
        }
      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('_fetchResultatAuto error: $e');
      // En cas d'erreur réseau, on retire la clé pour réessayer
      _resultatsVerifies.remove(resultKey);
    }
  }

  /// ★ A6 (P5) — Liste FIABLE des partants d'une course suivie, ou `null`.
  ///
  /// Lit le programme déjà en mémoire (`DataRefreshService.programme`), exactement
  /// comme le fait déjà ce fichier pour retrouver une course (l.2085-2103).
  /// `ZtEquivHorse.numero` est une **String** (`z_models.dart:94`) : elle est
  /// convertie, jamais concaténée.
  ///
  /// Renvoie `null` si la course est absente du programme chargé ou si sa liste
  /// de partants est vide. Ce `null` signifie « vérification impossible », et
  /// **jamais** « arrivée suspecte » : l'appelant ne refuse rien dans ce cas.
  /// Aucune liste n'est jamais déduite de la longueur de l'arrivée.
  Set<int>? _partantsDeLaCourse(TrackedCourse tc) {
    for (final reunion in DataRefreshService.instance.reunions) {
      final rMatch = RegExp(r'R(\d+)').firstMatch(reunion.code);
      final rNum =
          rMatch != null ? int.tryParse(rMatch.group(1) ?? '') ?? 0 : 0;
      if (rNum != tc.numReunion) continue;
      ZtCourse? course;
      for (final c in reunion.courses) {
        if (c.numCourse == tc.numCourse) {
          course = c;
          break;
        }
      }
      if (course == null || course.partants.isEmpty) return null;
      final numeros = <int>{};
      for (final p in course.partants) {
        final n = int.tryParse(p.numero);
        if (n != null) numeros.add(n);
      }
      return numeros.isEmpty ? null : numeros;
    }
    return null;
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

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ B5c — Reset complet sous barrière d'écriture
  // ══════════════════════════════════════════════════════════════════════════

  /// Vide la RAM d'AlertService PUIS exécute [supprimerLesCles], le tout sous
  /// une barrière qui empêche les huit chemins d'écriture du service de
  /// réécrire le disque après son effacement.
  ///
  /// Appelé exclusivement par `BackupService.reinitialiserComplet()`, en TÊTE,
  /// avant les cinq autres services.
  ///
  /// Pourquoi `AlertService` encadre-t-il l'effacement, contrairement aux
  /// autres services ? Parce qu'il est le seul à posséder cette barrière.
  /// Les autres (`EloService`, `CoteTrackerService`, `PronosticResultats`…)
  /// sont appelés APRÈS l'effacement, comme validé en B5, B5b et B5c-1..4.
  ///
  /// Pourquoi ne pas passer par `recharger()` ? Parce que `_load()` relit le
  /// disque — vide — mais ne jette pas les collections dont les clés sont
  /// absentes (`addAll` sans `clear` sur `_sentAlertIds`, `_resultatsVerifies`
  /// et `_coteChuteNotifies`), et surtout parce que le prochain `_save()`
  /// réécrirait intégralement l'ancien contenu.
  ///
  /// Ordre imposé :
  ///   1. barrière ON               → aucune écriture ne peut NAÎTRE ;
  ///   2. génération++              → verrou définitif sur les suspendues ;
  ///   3. capture S1                → périmètre déjà connu, avant le drain ;
  ///   4. drain                     → les écritures engagées se terminent ;
  ///   5. vidage RAM + config défaut ;
  ///   6. [supprimerLesCles]        → l'effacement, ENCORE sous barrière ;
  ///   7. `finally`                 → barrière OFF + rappel resynchronisé.
  ///
  /// ⚠️ [supprimerLesCles] ne doit contenir que des `prefs.remove()` : toute
  ///    écriture y serait bloquée par la barrière (comportement voulu).
  ///
  /// ⚠️ R-11 ne peut pas être totalement fermé : `MethodChannel
  ///    .invokeMethod('showNotification')` dans [_sendNativeNotification]
  ///    n'est pas une écriture SharedPreferences et échappe à la barrière.
  ///    Le garde placé en tête de [_addAlert] ferme ce chemin à la source.
  Future<void> executerResetComplet(
      Future<void> Function() supprimerLesCles) async {
    _resetEnCours = true;   // 1. plus aucune écriture ne NAÎT
    _generationCache++;     // 2. verrou définitif sur les suspendues
    try {
      // 3. Capture S1 — AVANT le drain, donc sur le cache d'entrée.
      //    `recalculerCoursesConseilIA` peut modifier ce cache pendant la
      //    fenêtre ; on veut le périmètre tel que l'utilisateur le voyait.
      _conseilIASilencieux = {
        for (final item in _coursesMatchingConseils)
          '${item.course.nom}_${item.reunion.lieu}',
      };

      // 4. Drain : on attend la fin de TOUTES les écritures engagées, y
      //    compris les sept chemins indépendants (registre unifié).
      //    Boucle plutôt qu'un `Future.wait` unique : `whenComplete` s'exécute
      //    en microtâche APRÈS la complétion, donc `Future.wait` peut se
      //    résoudre alors que le `remove` du registre n'a pas encore tourné.
      //    La condition garantit qu'on ne sort que registre réellement vide.
      while (_ecrituresEnCours.isNotEmpty) {
        final enVol = List<Future<bool>>.from(_ecrituresEnCours);
        try {
          await Future.wait(enVol);
        } catch (_) {
          // Une écriture qui échoue ne doit jamais faire échouer le reset.
          // L'erreur est déjà journalisée et mémorisée par _executerEcriture.
        }
      }

      // 5. État RAM neuf.
      _alerts.clear();
      _trackedCourses.clear();
      _sentAlertIds.clear();
      _resultatsVerifies.clear();
      _coteChuteNotifies.clear();
      _disqDetectes.clear();
      _conseilIANotifies.clear();
      _config = AlertConfig.defaut;

      // 6. Effacement disque — TOUJOURS sous barrière.
      await supprimerLesCles();
    } finally {
      // 7. Libération inconditionnelle, même sur exception : sans ce finally,
      //    une erreur laisserait le service muet jusqu'au redémarrage.
      _resetEnCours = false;
      // Rappel quotidien resynchronisé sur la config par défaut.
      // `_demarrerRappelQuotidien()` commence par `cancel()` puis sort
      // immédiatement (activerRappelQuotidien == false) : le timer s'arrête.
      // Il redémarrera si l'utilisateur réactive l'option (updateConfig).
      // Le watchdog de 60 s n'est PAS touché.
      _demarrerRappelQuotidien();
    }
    if (kDebugMode) {
      debugPrint('[AlertService] 🧹 Reset complet effectué '
          '(génération $_generationCache, '
          '${_conseilIASilencieux.length} courses déjà connues, '
          'disque non réécrit)');
    }
    notifyListeners();
  }

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
  // ★ LOT B2-C : ventilation Gagnant / Placé (C-2a : mises seules, aucune cote).
  //   null = composante non renseignée (autre type de pari, ou donnée antérieure).
  final double? miseGagnant;        // mise engagée sur le Gagnant, en €
  final double? misePlace;          // mise engagée sur le Placé, en €
  // ★ SOUS-LOT B : cotes RÉELLEMENT connues au moment du pari, par composante.
  //   Elles servent uniquement au « Gain potentiel » AVANT l'arrivée : après
  //   la course, seuls les rapports officiels font foi. null = inconnue.
  //   Aucune valeur par défaut n'est jamais inventée (ni ×2, ni ×2.5, ni ×3).
  final double? coteGagnant;
  final double? cotePlace;
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

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ LOT B-2 — ARRIVÉE OFFICIELLE STRUCTURÉE (2 champs FACULTATIFS)
  //
  //  POURQUOI CES CHAMPS EXISTENT — mesuré, pas supposé :
  //  `arriveeFinale` (ci-dessus) est une `List<int>` APLATIE. Elle ne peut pas
  //  représenter deux chevaux ex æquo : `[5, 7]` et `[7, 5]` y sont
  //  indiscernables, et le rang de chaque cheval devient indéterminable.
  //  Trois courses réelles portent un ex æquo dans les captures :
  //    prog_17112026 R5C5  [[2],[4],[5,7],[8],[3],[6]]
  //    prog_17112026 R6C5  [[12],[1,7],[9],[2],[10],[8],[6],[13],[5]]
  //    prog_20112026 R5C7  [[4],[6],[1,5],[2]]
  //
  //  RÈGLES ABSOLUES DE CE LOT :
  //   • `arriveeFinale` GARDE son format et son fonctionnement, à l'identique.
  //     Ces deux champs sont ADDITIFS et ne la remplacent pas.
  //   • Aucun groupe n'est JAMAIS reconstruit à partir d'une liste aplatie :
  //     `arriveeGroupes` ne peut contenir qu'une structure reçue telle quelle.
  //   • `null` = « groupes non connus ». Ce n'est PAS « pas d'ex æquo ».
  //     Un ticket historique n'aura jamais de groupes inventés.
  // ══════════════════════════════════════════════════════════════════════════

  /// Groupes d'arrivée EXACTS tels que publiés par l'API (`List<List<int>>`),
  /// chaque sous-liste étant un rang (plusieurs numéros = ex æquo).
  /// `null` = informations non disponibles. Jamais déduit d'[arriveeFinale].
  final List<List<int>>? arriveeGroupes;

  /// Caractère DÉFINITIF de l'arrivée.
  /// `null` = inconnu (ticket historique, ou API muette). `false` = provisoire.
  /// Une arrivée provisoire ne doit JAMAIS être présentée ni exploitée comme
  /// définitive ; l'absence d'information n'autorise pas à conclure « définitive ».
  final bool? arriveeDefinitive;

  /// `true` s'il y a au moins un ex æquo dans les groupes CONNUS.
  /// `false` si les groupes sont inconnus : on n'affirme pas l'absence.
  bool get aDesExAequo => arriveeGroupes?.any((g) => g.length > 1) ?? false;

  /// ★ LOT B-2 — les groupes connus décrivent-ils EXACTEMENT cette liste plate ?
  ///
  /// Comparaison stricte, dans l'ordre : un aplatissement de groupes est
  /// ordonné par rangs, donc la comparaison positionnelle est la bonne.
  /// Sert uniquement à décider si une donnée DÉJÀ STOCKÉE reste valable après
  /// le remplacement de `arriveeFinale`. Ne fabrique jamais de groupes.
  static bool _groupesCoherentsAvec(
    List<List<int>>? groupes,
    List<int> plate,
  ) {
    if (groupes == null) return false;
    final aplati = <int>[for (final g in groupes) ...g];
    if (aplati.length != plate.length) return false;
    for (var i = 0; i < aplati.length; i++) {
      if (aplati[i] != plate[i]) return false;
    }
    return true;
  }

  /// Aplatit les groupes SANS PERTE, en conservant l'ordre des rangs.
  /// Retourne `null` si les groupes sont inconnus : un appelant ne peut pas
  /// fabriquer une arrivée plate à partir de rien.
  List<int>? get arriveeGroupesAplatis =>
      arriveeGroupes == null ? null : <int>[for (final g in arriveeGroupes!) ...g];

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ ÉTAPE 4-F — CAPTURE DU PARI RÉELLEMENT JOUÉ (4 champs FACULTATIFS)
  //
  //  Contrat STRICTEMENT identique à celui de `UserPrediction` :
  //   • les QUATRE champs sont `null` pour tout ticket antérieur à 4-F ;
  //   • aucune valeur n'est jamais déduite, devinée ni reconstituée ;
  //   • `numerosJoues` GARDE sa signification historique (ensemble trié) ;
  //   • `typePari` reste inchangé : la variante vit dans [varianteChoisie].
  //
  //  ⚠️ CES CHAMPS DOIVENT ÊTRE PROPAGÉS PAR TOUTES LES RECONSTRUCTIONS.
  //     Ce fichier reconstruit `TrackedCourse` champ par champ à trois endroits
  //     (`ajouterSuivi`, `withResultat`, `withDividende`). Oublier une ligne
  //     ici perd la donnée en silence — exactement le défaut déjà rencontré
  //     sur `storageKey` (lot R1) puis sur la ventilation G+P (lot B2-C).
  // ══════════════════════════════════════════════════════════════════════════

  /// Code API PMU réellement visé (`'E_TIERCE'`, `'E_QUARTE_PLUS'`…).
  /// `null` = non capturé. Aucune valeur par défaut.
  final String? codePmuOfficiel;

  /// Variante **choisie par le parieur** : `'ordre'` ou `'desordre'`.
  /// Renseignée uniquement pour Tiercé Ordre/Désordre et Couplé Ordre.
  /// Reste `null` pour Quarté+/Quinté+ (le rapport officiel tranche).
  final String? varianteChoisie;

  /// Ordre des chevaux tel que saisi, lorsque le pari exige l'ordre.
  /// Invariant : le tri de ce champ doit être égal à [numerosJoues].
  final List<int>? numerosDansOrdre;

  /// Formule Multi / Mini Multi (`'en4'`…`'en7'`). Toujours `null` dans ce lot.
  final String? formulePari;

  // ═════════════════════════════════════════════════════════════════════════
  //  ★ LOT B-1 — GAINS PMU STRUCTURÉS (tous facultatifs)
  //
  //  Modèle JUMEAU de `UserPrediction` : contrat strictement identique, pour
  //  qu'aucune des deux représentations du même ticket ne puisse diverger.
  //
  //  RÈGLE DE COMPATIBILITÉ — ABSOLUE
  //   • `null` = ticket HISTORIQUE : le chemin de calcul actuel s'applique,
  //     strictement inchangé. Aucun recalcul rétroactif.
  //   • Les clés JSON ne sont écrites QUE si `etatGain != null` : un ticket
  //     historique relu puis réécrit garde EXACTEMENT 28 clés (verrou mesuré).
  //   • `dividendePmuReel` est CONSERVÉ et reste lu partout. Il n'est plus
  //     alimenté par le nouveau moteur, mais il n'est ni supprimé ni
  //     réinterprété.
  // ═════════════════════════════════════════════════════════════════════════

  /// État du gain, ou `null` pour un ticket historique (chemin legacy).
  final EtatGain? etatGain;

  /// Rapports officiels RÉELLEMENT attribués. `null` = jamais résolu.
  final List<RapportAttribue>? rapportsAttribues;

  /// État de la Tirelire, INDÉPENDANT du rapport Ordre.
  final EtatTirelire? etatTirelire;

  /// Dividende de la composante Gagnant d'un Gagnant+Placé, pour 1 €.
  final double? dividendeGagnant;

  /// Dividende de la composante Placé d'un Gagnant+Placé, pour 1 €.
  final double? dividendePlace;

  /// `miseBase` du bloc PMU employé, en centimes — AUDIT UNIQUEMENT (R17).
  final int? miseBaseCentimesUtilisee;

  /// Motif fermé expliquant un `etatGain == nonDetermine`.
  final MotifNonDetermination? motifNonDetermination;

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ B1-T12 / ÉTAPE 1 — GAIN MANUEL ET LIAISON CERTAINE (côté suivi)
  //
  //  Mêmes règles que sur `UserPrediction`, et mêmes raisons :
  //    • `montantGainManuel` est le montant BRUT reçu, déclaré par
  //      l'utilisateur. Il est DISTINCT de `dividendePmuReel` et des sept
  //      champs B-1, qui restent les données OFFICIELLES du PMU. Aucune
  //      saisie manuelle n'écrit dans les champs PMU.
  //    • `null` = aucune saisie. `0.0` = l'utilisateur a déclaré 0 €.
  //    • `idTicketLie` porte l'`id` du `UserPrediction` jumeau, et `null`
  //      signifie « non lié » — jamais « à deviner ». Aucun rapprochement
  //      par réunion/course/heure n'est autorisé.
  // ══════════════════════════════════════════════════════════════════════════

  /// Montant BRUT réellement reçu, déclaré par l'utilisateur, en euros.
  /// `null` = aucune saisie → le PMU fait foi.
  final double? montantGainManuel;

  /// `id` du `UserPrediction` jumeau, si et seulement si la correspondance
  /// a été établie au moment de la création du pari. `null` = non lié.
  final String? idTicketLie;

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ CHANTIER 1/3 — LE REMBOURSEMENT, DISTINCT DU GAIN (côté suivi)
  //
  //  Contrat STRICTEMENT IDENTIQUE à `UserPrediction.remboursementPmu` : même
  //  signification, même distinction absence / 0 €, même alimentation
  //  exclusivement officielle. Les deux représentations du même ticket ne
  //  peuvent donc pas diverger sur ce montant.
  //
  //  ⚠️ Clé JSON ÉCRITE UNIQUEMENT si la valeur est non nulle : un ticket
  //     historique relu puis réécrit garde EXACTEMENT ses 28 clés.
  // ══════════════════════════════════════════════════════════════════════════

  /// Somme des mises EFFECTIVEMENT reversées au joueur, en euros.
  ///
  /// `null` = aucun remboursement établi (PAS un 0 € officiel).
  /// Ne participe JAMAIS à un gain, ni à `isGagne`, ni à `dividendePmuReel`.
  final double? remboursementPmu;

  /// ★ R10 — Le ticket a-t-il de quoi identifier sa variante **sans deviner** ?
  ///
  /// CONTRAT STRICTEMENT IDENTIQUE à `UserPrediction.capturePariComplete`
  /// (approche FACTUELLE). L'ancienne version rendait `true` dès que le code
  /// PMU était présent, ce qui était faux dans cinq cas mesurés (Quinté+ sans
  /// numéro, Tiercé à deux numéros, ticket vide avec code forcé, ordre
  /// incohérent, Multi sans formule).
  ///
  /// `true` exige donc TOUT ceci : code PMU connu, type identifié, nombre de
  /// numéros EXACTEMENT celui attendu par le règlement, ordre réellement
  /// capturé si le pari l'impose (et cohérent avec `numerosJoues`), variante
  /// explicitement choisie s'il en faut une.
  ///
  /// ⚠️ Ne dit RIEN de la calculabilité financière : une mise absente ou un
  ///    rapport officiel manquant ne changent pas ce verdict.
  ///
  /// Getter DÉRIVÉ : jamais persisté.
  bool get capturePariComplete {
    if (codePmuOfficiel == null) return false;

    final type = typePariDepuisLibelle(typePari);
    if (type == TypePariJoue.inconnu) return false;

    final attendu = tailleCombinaisonAttendue(type);
    if (attendu == null || numerosJoues.length != attendu) return false;

    if (exigeOrdreExact(type)) {
      final ordre = numerosDansOrdre;
      if (ordre == null) return false;
      if (ordre.length != numerosJoues.length) return false;
      final triOrdre = List<int>.from(ordre)..sort();
      final triJoues = List<int>.from(numerosJoues)..sort();
      for (var i = 0; i < triOrdre.length; i++) {
        if (triOrdre[i] != triJoues[i]) return false;
      }
    }

    final exigeVariante = typePari == 'Tiercé Ordre' ||
        typePari == 'Tiercé Désordre' ||
        typePari == 'Couplé Ordre';
    return exigeVariante ? varianteChoisie != null : true;
  }

  /// ★ LOT B2-C — Mise totale réellement engagée (contrat B1) :
  /// - les deux composantes nulles → `miseEngagee` (pari historique mono-composante)
  /// - une seule nulle → `null` (état incomplet : aucun total inventé)
  /// - les deux présentes → somme des deux composantes
  /// Règle métier : 10 € saisis = 10 € Gagnant + 10 € Placé = 20 € engagés.
  double? get miseTotaleEngagee {
    if (miseGagnant == null && misePlace == null) return miseEngagee;
    if (miseGagnant == null || misePlace == null) return null;
    return miseGagnant! + misePlace!;
  }

  /// ★ LOT B2-C — Vrai si une seule des deux composantes est renseignée.
  bool get misesGagnantPlaceIncompletes =>
      (miseGagnant == null) != (misePlace == null);

  // ────────────────────────────────────────────────────────────────────────
  //  ★ B1-T12 / ÉTAPE 1 — LE GAIN RETENU (côté suivi), MÊME RÈGLE QUE LE
  //  MODÈLE `UserPrediction`, POUR QUE LES DEUX ÉCRANS NE DIVERGENT JAMAIS.
  //
  //  PRIORITÉ : ① gain manuel ② gain officiel PMU ③ indéterminé (`null`).
  //
  //  ⚠️ `dividendePmuReel` ET LES SEPT CHAMPS B-1 NE SONT PAS TOUCHÉS.
  //  Ils gardent leur sens officiel, et `affichageGainSuivi` continue de les
  //  lire comme avant. `gainRetenuBrut` est une VUE, pas une réécriture.
  // ────────────────────────────────────────────────────────────────────────

  /// Le montant BRUT retenu : manuel s'il existe, sinon celui établi par le
  /// verdict PMU, sinon `null` (= indéterminé, on n'affirme rien).
  double? get gainRetenuBrut {
    // ① La déclaration de l'utilisateur est prioritaire. `0.0` est un montant.
    final manuel = montantGainManuel;
    if (manuel != null) return manuel;

    // ② Le PMU fait foi quand l'utilisateur n'a rien déclaré.
    //
    //    ⚠️ MESURÉ AVANT D'ÉCRIRE : `EtatGain` est un ENUM d'ÉTATS
    //    (nonDetermine / attribue / perdu / rembourse) — il NE PORTE AUCUN
    //    MONTANT. Le montant brut officiel vit dans `rapportsAttribues[]`,
    //    chaque `RapportAttribue` exposant `montantRetour` (déjà calculé à
    //    sa construction comme `miseAppliquee × rapport.pourUnEuro`).
    //
    //    On se contente donc de SOMMER des montants DÉJÀ CALCULÉS. Aucune
    //    formule PMU n'est réappliquée ici, aucun rapport n'est reconstruit.
    //    On ne somme QUE si le verdict est `attribue` : un état
    //    `nonDetermine` ne porte aucun montant fiable, `perdu` vaut 0 brut
    //    et `rembourse` est un remboursement, pas un gain.
    if (etatGain == EtatGain.attribue) {
      final rapports = rapportsAttribues;
      if (rapports != null && rapports.isNotEmpty) {
        var total = 0.0;
        for (final r in rapports) {
          total += r.montantRetour;
        }
        return total;
      }
    }

    // ③ Rien de fiable : indéterminé. On ne retombe PAS sur la cote : ce
    //    serait exactement le défaut mesuré en B1-T12.
    return null;
  }

  /// Le gain NET retenu, ou `null` si la mise engagée est inconnue.
  ///
  /// Net = brut − mise réellement engagée.
  ///
  /// ⚠️ `mise > 0` et non `mise != null` : PARITÉ STRICTE avec
  /// `UserPrediction.gainRetenuNet`. Côté `UserPrediction`, `montantMise` est
  /// un `double` de défaut `0.0`, donc une mise absente s'y présente comme
  /// `0.0` ; le modèle y traite donc déjà `<= 0` comme « non renseignée ».
  /// Si ce getter-ci acceptait `0.0` comme une mise connue, le MÊME pari
  /// afficherait un net chiffré ici et `null` côté PROFIL. Une garde qui ne
  /// peut que transformer un nombre inventé en « indéterminé » explicite,
  /// jamais l'inverse — et qui n'a, à ce jour, AUCUN consommateur de
  /// production (mesuré : grep vide sur `gainRetenuNet` hors définitions).
  double? get gainRetenuNet {
    final brut = gainRetenuBrut;
    if (brut == null) return null;
    final mise = miseTotaleEngagee;
    if (mise == null || mise <= 0) return null;
    return brut - mise;
  }

  /// Un gain manuel a-t-il été déclaré ? (`0.0` compte comme déclaré.)
  bool get aGainManuel => montantGainManuel != null;

  /// Le ticket est-il lié de façon certaine à son `UserPrediction` jumeau ?
  bool get estLieAuProfil => idTicketLie != null;

  // ★ ÉTAPE 2 — INTERPRÉTATION EN LECTURE DU TYPE DE PARI.
  //
  //  Contrat strict :
  //   • `typePari` n'est JAMAIS modifié, normalisé ni réécrit ;
  //   • aucun getter ci-dessous n'écrit quoi que ce soit ;
  //   • `toJson` reste inchangé, et `fromJson` conserve son défaut existant
  //     (`?? 'Simple Gagnant'`) : ces valeurs sont DÉRIVÉES, jamais stockées ;
  //   • les anciens tickets gardent leur `storageKey` et leurs champs intacts.
  //
  //  ⚠️ POINT DÉLICAT, MESURÉ ET NON CORRIGÉ ICI : `fromJson` applique
  //     `j['typePari'] as String? ?? 'Simple Gagnant'`. Un ticket enregistré
  //     SANS clé `typePari` est donc relu comme « Simple Gagnant » — une
  //     supposition faite EN AMONT, dans le désérialiseur. La présente étape
  //     ne la modifie pas (elle changerait le comportement de chargement des
  //     anciens tickets, ce qui est interdit) ; elle ne peut donc pas la
  //     distinguer d'un vrai Simple Gagnant. C'est une limite assumée,
  //     documentée ici pour l'étape 3.

  /// Type de pari PMU canonique, ou `null` si le libellé enregistré n'est pas
  /// répertorié. Lecture seule.
  ///
  /// Un ticket « Gagnant+Placé » rend `null` : ce n'est pas un pari PMU mais
  /// un ticket applicatif à deux composantes.
  TypePariPmu? get typePmu => typePmuDepuisLibelleHistorique(typePari);

  /// `true` si le libellé enregistré est reconnu par le référentiel.
  bool get typePariReconnu => typePmu != null;

  /// `true` si le libellé est le ticket applicatif à deux composantes
  /// (« Gagnant+Placé »), volontairement hors référentiel PMU.
  bool get typePariHorsReferentielPmu =>
      estTicketApplicatifHorsReferentielPmu(typePari);

  /// `true` si le type est absent, vide ou inconnu : aucune interprétation
  /// possible. État signalé, jamais comblé par un type par défaut.
  bool get typePariNonResolu => typePmu == null && !typePariHorsReferentielPmu;

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
    this.miseGagnant,
    this.misePlace,
    this.coteGagnant,
    this.cotePlace,
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
    // ★ LOT B-2 — arrivée structurée (tous facultatifs, null par défaut)
    this.arriveeGroupes,
    this.arriveeDefinitive,
    // ★ ÉTAPE 4-F — capture du pari réellement joué (tous facultatifs)
    this.codePmuOfficiel,
    this.varianteChoisie,
    this.numerosDansOrdre,
    this.formulePari,
    // ★ LOT B-1 — gains PMU structurés (tous facultatifs, null par défaut)
    this.etatGain,
    this.rapportsAttribues,
    this.etatTirelire,
    this.dividendeGagnant,
    this.dividendePlace,
    this.miseBaseCentimesUtilisee,
    this.motifNonDetermination,
    // ★ B1-T12 / étape 1 — gain manuel et liaison certaine
    this.montantGainManuel,
    this.idTicketLie,
    // ★ CHANTIER 1/3 — remboursement officiel, distinct du gain
    this.remboursementPmu,
  }) : addedAt = addedAt ?? DateTime.now();

  /// Crée une copie avec résultat mis à jour (pour persister sans muter)
  TrackedCourse withResultat({
    required bool isGagne,
    required List<int> arrivee,
    required String message,
    List<List<int>>? arriveeGroupes,
    bool? arriveeDefinitive,
  }) => TrackedCourse(
    numReunion: numReunion,
    numCourse: numCourse,
    nomCourse: nomCourse,
    hippodrome: hippodrome,
    heureDepart: heureDepart,
    nomCheval: nomCheval,
    numeroCheval: numeroCheval,
    miseEngagee: miseEngagee,
    // ★ LOT B2-C : les deux composantes doivent survivre à la copie.
    miseGagnant: miseGagnant,
    misePlace: misePlace,
    // ★ SOUS-LOT B : les deux cotes par composante aussi (piège R1).
    coteGagnant: coteGagnant,
    cotePlace: cotePlace,
    addedAt: addedAt,
    typePari: typePari,
    numerosJoues: numerosJoues,
    iaMemKey: iaMemKey,
    scoreIA: scoreIA,
    cote: cote,
    isGagne: isGagne,
    arriveeFinale: arrivee,
    messageResultat: message,
    // ★ LOT B-2 — arrivée structurée. DEUX SOURCES, UNE SEULE VÉRITÉ.
    //
    //   `arrivee` (paramètre) REMPLACE `arriveeFinale` : la nouvelle arrivée
    //   fait foi. Propager aveuglément `this.arriveeGroupes` associerait donc
    //   des groupes à une liste plate qui ne leur correspond plus — exactement
    //   le genre d'incohérence silencieuse que ce chantier traque.
    //
    //   Choix retenu, explicite :
    //     • si l'appelant FOURNIT des groupes, ils sont retenus (chemin neuf) ;
    //     • sinon, on CONSERVE les groupes déjà connus UNIQUEMENT s'ils sont
    //       cohérents avec la nouvelle liste plate — c'est-à-dire s'ils
    //       s'aplatissent exactement dessus. Sinon `null` : « inconnus ».
    //   `arriveeDefinitive` ne dépend pas de la forme de l'arrivée : elle est
    //   conservée si l'appelant n'en fournit pas.
    arriveeGroupes: arriveeGroupes ??
        (_groupesCoherentsAvec(this.arriveeGroupes, arrivee)
            ? this.arriveeGroupes
            : null),
    arriveeDefinitive: arriveeDefinitive ?? this.arriveeDefinitive,
    dividendePmuReel: dividendePmuReel,
    combinaisonPmu: combinaisonPmu,
    // ★ ÉTAPE 4-F : capture du pari propagée. Un ticket Tiercé Ordre dont le
    //   résultat est enregistré doit conserver son ordre saisi et sa variante,
    //   sinon l'information disparaît à la première mise à jour de résultat.
    codePmuOfficiel: codePmuOfficiel,
    varianteChoisie: varianteChoisie,
    numerosDansOrdre: numerosDansOrdre,
    formulePari: formulePari,
    // ★ LOT B-1 : les gains structurés DOIVENT survivre à la copie.
    //   Sans ces sept lignes, une mise à jour de résultat effacerait les
    //   rapports attribués — exactement le défaut corrigé en 4-F pour les
    //   quatre champs de capture.
    etatGain: etatGain,
    rapportsAttribues: rapportsAttribues,
    etatTirelire: etatTirelire,
    dividendeGagnant: dividendeGagnant,
    dividendePlace: dividendePlace,
    miseBaseCentimesUtilisee: miseBaseCentimesUtilisee,
    motifNonDetermination: motifNonDetermination,
    // ★ B1-T12 / étape 1 — le gain manuel et la liaison survivent à la copie.
    //   Sans ces deux lignes, enregistrer un résultat effacerait le montant
    //   déclaré par l'utilisateur — même piège que 4-F, B-1 et R1.
    montantGainManuel: montantGainManuel,
    idTicketLie: idTicketLie,
    // ★ CHANTIER 1/3 — LE REMBOURSEMENT SURVIT À LA COPIE.
    //   Sans cette ligne, enregistrer un résultat effacerait le remboursement
    //   officiel : `totalReverse` et `resultatNet` deviendraient faux alors que
    //   les rapports, eux, seraient conservés. Même piège que 4-F / B-1 / R1.
    remboursementPmu: remboursementPmu,
    // ★ LOT R1 : `storageKey` DOIT être propagée.
    //   Sans cette ligne, la copie renvoyée par `withResultat()` perdait sa
    //   clé (mesuré : 0 occurrence de `storageKey` dans ce corps, contre 1
    //   dans `withDividende()` — asymétrie non intentionnelle).
    //   NB : la référence était un numéro de ligne (« l.3041 »), devenu faux
    //   après les insertions de B2-C → remplacé par le nom du champ.
    //   `_save()` sérialise ensuite `'storageKey': null` (l.611 → toJson) et
    //   `_load()` retombe sur `tc.storageKey ?? tc.key` (l.509) : au
    //   rechargement, l'entrée réapparaissait sous une clé SANS horodatage,
    //   distincte de la clé d'origine — la persistance demandée par R1
    //   échouait alors même que la session paraissait correcte.
    storageKey: storageKey,
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
    // ★ LOT B2-C : les deux composantes doivent survivre à la copie.
    miseGagnant: miseGagnant,
    misePlace: misePlace,
    // ★ SOUS-LOT B : les deux cotes par composante aussi (piège R1).
    coteGagnant: coteGagnant,
    cotePlace: cotePlace,
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
    // ★ LOT B-2 : l'arrivée structurée survit à `withDividende`.
    //   `arriveeFinale` n'est PAS modifiée par ce chemin : les groupes restent
    //   donc cohérents par construction, et sont propagés tels quels.
    arriveeGroupes: arriveeGroupes,
    arriveeDefinitive: arriveeDefinitive,
    // ★ LOT B-1 : les gains structurés survivent aussi à `withDividende`.
    //   Ce chemin est utilisé par l'ancien moteur (`enregistrerDividendePmu`) ;
    //   il ne doit ni perdre ni écraser les rapports attribués par le nouveau.
    etatGain: etatGain,
    rapportsAttribues: rapportsAttribues,
    etatTirelire: etatTirelire,
    dividendeGagnant: dividendeGagnant,
    dividendePlace: dividendePlace,
    miseBaseCentimesUtilisee: miseBaseCentimesUtilisee,
    motifNonDetermination: motifNonDetermination,
    codePmuOfficiel: codePmuOfficiel,
    varianteChoisie: varianteChoisie,
    numerosDansOrdre: numerosDansOrdre,
    formulePari: formulePari,
    // ★ CHANTIER 1/3 — ASYMÉTRIE FERMÉE (même classe de défaut que R1).
    //
    //   `withResultat` propageait déjà `montantGainManuel`, `idTicketLie` et
    //   `remboursementPmu` ; `withDividende` — l'autre reconstructeur du même
    //   objet — ne les propageait PAS. Une simple mise à jour de dividende
    //   effaçait donc le remboursement officiel d'un ticket déjà résolu : le
    //   résultat financier devenait faux après une opération sans rapport.
    //   Mesuré : 0 occurrence des trois champs dans ce corps avant correction,
    //   contre 3 dans `withResultat()`.
    montantGainManuel: montantGainManuel,
    idTicketLie: idTicketLie,
    remboursementPmu: remboursementPmu,
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
    // ★ LOT B2-C : ventilation Gagnant / Placé (null pour les autres paris)
    'miseGagnant': miseGagnant,
    'misePlace': misePlace,
    // ★ SOUS-LOT B : cotes par composante (null pour les paris historiques)
    'coteGagnant': coteGagnant,
    'cotePlace': cotePlace,
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
    // ★ ÉTAPE 4-F — capture du pari réellement joué.
    //   Toujours écrites, y compris à `null`, comme les clés B2-C ci-dessus.
    'codePmuOfficiel': codePmuOfficiel,
    'varianteChoisie': varianteChoisie,
    'numerosDansOrdre': numerosDansOrdre,
    'formulePari': formulePari,
    // ★ LOT B-2 — arrivée structurée, ÉCRITURE CONDITIONNELLE.
    //
    //   Même raisonnement que pour B-1 : un ticket historique relu puis
    //   réécrit doit conserver EXACTEMENT 28 clés. Ces deux clés ne sont donc
    //   écrites que si l'une des deux au moins est connue. Un ticket sans
    //   arrivée structurée ne grossit pas.
    //
    //   `arriveeDefinitive` peut être connue seule (arrivée définitive mais
    //   groupes non récupérés) : les deux clés sont alors écrites ensemble,
    //   la seconde valant `null`, pour que la forme soit stable et lisible.
    ...?(arriveeGroupes == null && arriveeDefinitive == null)
        ? null
        : <String, dynamic>{
            'arriveeGroupes': arriveeGroupes
                ?.map((g) => List<int>.from(g))
                .toList(growable: false),
            'arriveeDefinitive': arriveeDefinitive,
          },
    // ★ LOT B-1 — gains PMU structurés.
    //
    //   ⚠️ ÉCRITURE CONDITIONNELLE, ET C'EST VOLONTAIRE.
    //   Les quatre clés 4-F ci-dessus sont inconditionnelles : un ticket
    //   historique relu puis réécrit conserve donc 28 clés exactement.
    //   Écrire ici sept clés inconditionnelles ferait passer ce même ticket à
    //   35 clés, romprait le verrou mesuré `expect(json.length, 28)` et
    //   modifierait la FORME des sauvegardes historiques.
    ...?etatGain == null
        ? null
        : <String, dynamic>{
            'etatGain': etatGain!.toJson(),
            'rapportsAttribues':
                rapportsAttribues?.map((a) => a.toJson()).toList(),
            'etatTirelire': etatTirelire?.toJson(),
            'dividendeGagnant': dividendeGagnant,
            'dividendePlace': dividendePlace,
            'miseBaseCentimesUtilisee': miseBaseCentimesUtilisee,
            'motifNonDetermination': motifNonDetermination?.toJson(),
          },
    // ★ B1-T12 / étape 1 — gain manuel et liaison certaine.
    //
    //   ⚠️ ÉCRITURE CONDITIONNELLE, MÊME RAISONNEMENT QUE B-1 ET B-2.
    //   Le verrou mesuré `expect(json.length, 28)` protège la FORME des
    //   sauvegardes historiques. Un ticket sans gain manuel et sans liaison
    //   ne doit pas grossir : les deux clés ne sont écrites que si l'une des
    //   deux au moins est renseignée.
    //
    //   `montantGainManuel` à `0.0` DOIT être écrit (déclaration explicite,
    //   distincte de l'absence) : le test est `!= null`, pas un test de
    //   véracité, qui aurait perdu le 0 €.
    ...?(montantGainManuel == null && idTicketLie == null)
        ? null
        : <String, dynamic>{
            'montantGainManuel': montantGainManuel,
            'idTicketLie': idTicketLie,
          },
    // ★ CHANTIER 1/3 — LE REMBOURSEMENT, CLÉ FACULTATIVE.
    //
    //   Écrite DÈS QUE la valeur est non nulle, `0.0` COMPRIS (convention
    //   validée, opération 4). Un ticket historique relu puis réécrit garde
    //   donc 28 clés exactement (verrou mesuré), et l'ABSENCE de la clé se
    //   relit en `null` — jamais en `0 €` officiel. Un remboursement
    //   officiellement établi à `0 €` est une information : il s'écrit.
    ...?(remboursementPmu == null)
        ? null
        : <String, dynamic>{'remboursementPmu': remboursementPmu},
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
    // ★ LOT B2-C : clés absentes des données antérieures → null (rétrocompatible)
    miseGagnant:  (j['miseGagnant'] as num?)?.toDouble(),
    misePlace:    (j['misePlace'] as num?)?.toDouble(),
    // ★ SOUS-LOT B : rétrocompatible — absentes des données antérieures ⇒ null
    coteGagnant:  (j['coteGagnant'] as num?)?.toDouble(),
    cotePlace:    (j['cotePlace'] as num?)?.toDouble(),
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
    // ★ ÉTAPE 4-F — lecture TOLÉRANTE : clé absente ⇒ `null`.
    //   Aucune variante, aucun ordre et aucune formule ne sont inventés.
    //   `numerosDansOrdre` reste `null` (et non `[]`) si la clé manque :
    //   « non capturé » ≠ « aucun cheval dans l'ordre ».
    codePmuOfficiel:  j['codePmuOfficiel'] as String?,
    varianteChoisie:  j['varianteChoisie'] as String?,
    numerosDansOrdre: (j['numerosDansOrdre'] as List<dynamic>?)
                          ?.map((e) => (e as num).toInt()).toList(),
    formulePari:      j['formulePari'] as String?,
    // ★ LOT B-2 — lecture STRICTE de l'arrivée structurée.
    //
    //   `null` si les groupes sont absents, mal formés, ou vides : on ne
    //   reconstruit JAMAIS des groupes à partir de `arriveeFinale`. Mieux vaut
    //   « groupes inconnus » qu'une structure inventée qui ferait croire à des
    //   ex æquo là où il n'y en a pas — ou l'inverse.
    arriveeGroupes: _lireArriveeGroupes(j['arriveeGroupes']),
    //   Lecture TOLÉRANTE : `as bool?` LÈVE une exception si la valeur est
    //   d'un autre type (mesuré : `type 'String' is not a subtype of type
    //   'bool?' in type cast`). Une sauvegarde corrompue ferait alors échouer
    //   la restauration du ticket ENTIER. On rend `null` — « inconnu » — et
    //   `null` n'est jamais interprété comme « définitif ».
    arriveeDefinitive:
        j['arriveeDefinitive'] is bool ? j['arriveeDefinitive'] as bool : null,
    // ★ LOT B-1 — lecture TOLÉRANTE des gains structurés.
    //   Clé absente ⇒ `null` ⇒ chemin legacy inchangé. Aucun état déduit,
    //   aucun rapport reconstruit, aucun montant complété.
    etatGain: EtatGain.fromJson(j['etatGain']),
    rapportsAttribues: _lireRapportsAttribuesJ(j['rapportsAttribues']),
    etatTirelire: EtatTirelire.fromJson(j['etatTirelire']),
    dividendeGagnant: (j['dividendeGagnant'] as num?)?.toDouble(),
    dividendePlace: (j['dividendePlace'] as num?)?.toDouble(),
    miseBaseCentimesUtilisee: (j['miseBaseCentimesUtilisee'] as num?)?.toInt(),
    motifNonDetermination:
        MotifNonDetermination.fromJson(j['motifNonDetermination']),
    // ★ B1-T12 / étape 1 — lecture TOLÉRANTE : clé absente ⇒ `null`.
    //   Un ticket historique reste « aucun gain manuel » et « non lié »,
    //   ce qui est la vérité. Aucun gain n'est recalculé au chargement et
    //   aucun rapprochement n'est tenté (interdictions du mandat).
    montantGainManuel: (j['montantGainManuel'] as num?)?.toDouble(),
    idTicketLie: j['idTicketLie'] as String?,
    // ★ CHANTIER 1/3 — lecture TOLÉRANTE : clé absente ⇒ `null` ⇒ « aucun
    //   remboursement établi ». Ce `null` n'est JAMAIS converti en `0.0` :
    //   l'absence d'information n'est pas un remboursement officiel nul.
    remboursementPmu: (j['remboursementPmu'] as num?)?.toDouble(),
  );

  /// Relecture tolérante d'une liste de rapports attribués.
  ///
  /// Rend `null` — et non une liste vide — quand la clé est absente ou n'est
  /// pas une liste : « non résolu » et « résolu sans rapport » ne sont pas le
  /// même état. Un élément illisible est IGNORÉ, jamais fabriqué ; s'il n'en
  /// reste aucun, on rend `null` pour ne pas affirmer une résolution.
  static List<RapportAttribue>? _lireRapportsAttribuesJ(dynamic valeur) {
    if (valeur is! List) return null;
    final out = <RapportAttribue>[];
    for (final item in valeur) {
      if (item is! Map) continue;
      try {
        out.add(RapportAttribue.fromJson(Map<String, dynamic>.from(item)));
      } on FormatException {
        continue; // élément illisible : ignoré, jamais deviné
      }
    }
    return out.isEmpty ? null : out;
  }

  /// ★ LOT B-2 — lit `arriveeGroupes` de façon STRICTE.
  ///
  /// Rend `null` — et n'invente RIEN — si :
  ///   • la valeur n'est pas une liste, ou est vide ;
  ///   • un « rang » n'est pas une liste non vide ;
  ///   • un numéro n'est pas un entier > 0.
  ///
  /// Un seul élément invalide fait refuser l'ENSEMBLE : mieux vaut « groupes
  /// inconnus » qu'une arrivée partielle présentée comme complète. En
  /// particulier, cette fonction ne consulte JAMAIS `arriveeFinale` : aucun
  /// regroupement n'est reconstruit par déduction.
  static List<List<int>>? _lireArriveeGroupes(dynamic valeur) {
    if (valeur is! List || valeur.isEmpty) return null;
    final out = <List<int>>[];
    for (final g in valeur) {
      if (g is! List || g.isEmpty) return null;
      final groupe = <int>[];
      for (final n in g) {
        if (n is int && n > 0) {
          groupe.add(n);
        } else if (n is num && n > 0 && n == n.toInt()) {
          groupe.add(n.toInt());
        } else {
          return null;
        }
      }
      out.add(List<int>.unmodifiable(groupe));
    }
    return List<List<int>>.unmodifiable(out);
  }
}

/// Refus silencieux d'une écriture de `SharedPreferences` (`false` sans
/// exception). Voir [AlertService._save] : c'est ce type qui transforme un
/// refus muet en échec de sauvegarde réellement observable.
class _EcritureAlertesRefusee implements Exception {
  const _EcritureAlertesRefusee();
  @override
  String toString() =>
      'EcritureAlertesRefusee: le stockage a refusé une écriture (false)';
}
