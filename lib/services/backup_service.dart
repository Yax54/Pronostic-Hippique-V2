// ═══════════════════════════════════════════════════════════════════════════
//  BackupService — Sauvegarde & Restauration COMPLETE des donnees
//  Pronostic Hippique v5.0 — Couverture 100% de toutes les SharedPreferences
//
//  ── INVENTAIRE COMPLET DES CLES SAUVEGARDEES ─────────────────────────────
//
//  🧠 MEMOIRE IA (ia_memory_service.dart) — 9 cles
//     ia_poids_v3          : Poids adaptatifs (19 criteres + PoidsIndices
//                            [criteres/confiance/reussite] + momentum
//                            + poidsParDiscipline) — COEUR de l'IA
//     ia_pronostics_v2     : 600 pronostics avec scores par critere,
//                            arrivee reelle, rangFavori, nbTop3, nbTop5,
//                            scorePerformance, typePariConseille,
//                            tauxReussiteAuMoment, precisionIA
//     ia_journal_v2        : 150 entrees journal gradient (avant/apres poids,
//                            diagnostic, methode, scorePerf)
//     ia_rapports_v1       : 60 rapports journaliers glissants (stats, note, discipline,
//                            19 criteres poidsApres, detail cours par cours,
//                            stats par type de pari, heure analyse)
//     ia_derniere_analyse_v1 : Date dernière analyse journée (format ddMMyyyy)
//     ia_stats_types_v1    : Stats cumulatives par type de pari (nbJoues,
//                            nbGagnes, nbPerdus, gainNet)
//     ia_precision_v2      : Precision IA par type de pari (StatsPrecisionParType)
//     ia_seuils_v1         : Seuils de confiance adaptatifs (SeuilsConfianceAdaptatifs)
//     ia_premium_historique_v1 : ★ v10.38 — Historique premium calendrier étoile (multi-jours)
//     ia_premium_du_jour_v1    : ★ v10.38 — Ancien format compat lecture (migration)
//     premium_widgets_selection_jour_v1 : ★ v10.62 — Figeage 5 widgets premium du jour
//
//  🎯 CONFIG FUSION BestBet (fusion_config_service.dart) — 4 cles
//     fusion_poids_confiance : Poids confiance (double)
//     fusion_poids_gain      : Poids qualite gain (double)
//     fusion_poids_risque    : Poids rapport risque (double)
//     fusion_seuil_min       : Seuil confiance minimum (int)
//
//  📋 PARIS UTILISATEUR (pmu_provider.dart) — 1 cle
//     user_predictions_v2  : Liste complete des paris (id, date, cheval,
//                            cote, typePari, mise, gain, isCorrect, scoreIA)
//
//  🔔 ALERTES (alert_service.dart) — 5 cles
//     alert_config_v2               : Configuration alertes (activees, seuil, types)
//     alert_history_v1              : Historique des alertes recues
//     tracked_courses_v1            : Courses actuellement suivies
//     alert_sent_ids_v1             : Anti-doublons notifications
//     alert_resultats_verifies_v1   : Resultats deja verifies
//
//  👤 PROFIL UTILISATEUR (profile_screen.dart) — 2 cles
//     profil_nom        : Nom affiche dans l'app
//     profil_gmail      : Adresse email de l'utilisateur
//     NOTE: profil_photo_path exclu (chemin local non portable entre appareils)
//
//  📱 WIDGET ANDROID (widget_service.dart) — clés écrites via MethodChannel
//     widget_course_name  : Nom de la course affichee dans le widget
//     widget_horse_name   : Nom du cheval favori IA
//     widget_horse_num    : Numero du cheval favori
//     widget_confiance    : Niveau de confiance IA (%)
//     widget_gain         : Gain potentiel estime
//     widget_hippodrome   : Hippodrome
//     widget_heure        : Heure de la course
//     widget_nb_courses   : Nombre de courses disponibles
//     widget_updated_at   : Derniere mise a jour du widget
//     widget_score_ia     : Score IA du cheval favori
//     widget_type_pari    : Type de pari conseillé
//     widget_tendance     : Tendance du cheval
//     widget_elo          : Rating ELO du cheval
//     widget_course2_name / widget_horse2_name / widget_heure2 / widget_confiance2
//     widget_course3_name / widget_horse3_name / widget_heure3 / widget_confiance3
//
//  🧪 LABO IA — Simulations sauvegardées (simulation_candidate_service.dart) — 1 clé
//     simulation_candidates_v1 : Pistes de simulation enregistrées (candidats)
//                                Obligatoire — non recalculable.
//
//  📊 CACHE AUDIT — Cache de calcul IA (ia_audit_cache_service.dart) — 1 clé
//     ia_audit_cache_v1 : Cache des 4 onglets Audit (Utilité, Morts,
//                         Corrélations, Discipline). Optionnel — recalculable.
//
//  ── TOTAL : 41 CLES — COUVERTURE 100% ────────────────────────────────────
//
//  ── CE QUE CONTIENT CHAQUE CLE ───────────────────────────────────────────
//
//  ia_poids_v3 (String JSON) contient :
//    • forme, gains, record, cote, constance, victoires, discipline (7 poids de base)
//    • distSpec, jockey, repos, hippo (4 poids enrichis v4.1/v7.0)
//    • momentum (Map<String,double> : vitesse apprentissage par critere)
//    • poidsParDiscipline (Map<discipline, Map<critere, double>>)
//    • nbMisesAJour (compteur d'apprentissages)
//    • poidsIndices.pc / pco / pr (PoidsIndices : criteres/confiance/reussite)
//    • calibration (score de calibration global)
//
//  ia_pronostics_v2 (StringList<JSON>) contient par pronostic :
//    • courseKey, nomCourse, hippodrome, discipline, datePronostic
//    • scoresIA : Map<numCheval, scoreIA>
//    • rangFavori : rang predit du favori IA
//    • scoresCriteres : Map<numCheval, ScoresCriteres{19 criteres}>
//    • arriveeReelle : liste d'arrivee (si connue)
//    • nbTop3, nbTop5, scorePerformance
//    • typePariConseille, tauxReussiteAuMoment, precisionIA
//    • confianceIA : score de confiance (0-100)
//
//  ── RETROCOMPATIBILITE ───────────────────────────────────────────────────
//     v1.0 : Sans configIA/alertes/widget → import partiel, sans crash
//     v2.x : Sans ameliorations IA v6.0   → restaure, formules appliquees
//     v3.0 : Sans widget + double/int fusion → restaure correctement
//     v4.0 : Couverture 100% (groupes separes)
//     v5.0 : Correction caracteres + reinitialisation complete + compteurs corrects
//     v7.2 : +cooldown bulle, +message jour, +heure analyse, +conseils notifiés
//     v7.3 : +résumé hebdo lundi, +anti-doublon cote chute, retrait clé orpheline
//     v7.4 : +bt_discipline, +bt_hippodrome, +flags transitoires ELO/conseils
//     v7.6 : +ia_premium_historique_v1 (étoiles calendrier), +ia_premium_du_jour_v1 (compat)
//     v7.7 : +premium_widgets_selection_jour_v1 (figeage 5 widgets premium du jour)
//     v7.8 : +ia_narrative_memory_v1 (mémoire narrative anti-répétition)
//     v7.9 : +ia_narrative_daily_cache_v1 (cache journalier narratif anti-rebuild)
//     v8.0 : +ia_stats_filtre_actif_v1, +ia_stats_date_debut_v1, +ia_stats_date_fin_v1 (filtres Précision IA — préférences affichage uniquement)
//     v9.0 : +ia_quasi_gros_paris_v1 (Gros paris à surveiller + Quasi gagnants — non recalculable)
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'alert_service.dart'; // ★ v10.26d
import 'elo_service.dart'; // ★ v8.0
import 'ia_memory_service.dart'; // ★ v10.26c
import 'quasi_gros_paris_service.dart'; // ★ v10.72

class BackupService {
  BackupService._();
  static final instance = BackupService._();

  // ── Numero de version du format backup ───────────────────────────────────
  static const _backupVersion = '9.0'; // ★ v10.72 : +ia_quasi_gros_paris_v1 (Gros paris à surveiller + Quasi gagnants)

  // ════════════════════════════════════════════════════════════════════════
  //  INVENTAIRE COMPLET DES CLES — toutes les SharedPreferences de l'app
  // ════════════════════════════════════════════════════════════════════════

  // 🧠 Memoire IA — coeur de l'apprentissage
  // ia_poids_v3 inclut : 19 poids adaptatifs + PoidsIndices + momentum
  //                      + poidsParDiscipline + nbMisesAJour + calibration
  //                      + mouvCote (R) + placeDepart (S) + atypiques_YYYY-MM
  static const _keysIA = [
    'ia_pronostics_v2',     // 600 pronostics (non compressé — rétrocompatibilité)
    'ia_pronostics_v2_gz',  // ★ Lot 4 : pronostics compressés gzip+base64
    'ia_poids_v3',          // Poids adaptatifs (19 critères v10.x : +mouvCote, +placeDepart)
    'ia_journal_v2',        // Journal gradient (150 entrées) + journées atypiques
    'ia_rapports_v1',       // 365 rapports journaliers glissants (★ v9.91 : monté de 60→365)
    'ia_bilans_semaine_v1', // ★ v9.91 : Bilans de semaine archivés
    'ia_bilans_mois_v1',    // ★ v9.91 : Bilans de mois archivés
    'ia_derniere_analyse_v1', // ★ v9.6 : Date dernière analyse (pour rappel Worker Kotlin)
    'ia_stats_types_v1',    // Stats cumulatives par type de pari
    'ia_precision_v2',      // Précision IA par type de pari
    'ia_stats_labels_v1',   // ★ v9.0 : Stats par label IA
    'ia_seuils_v1',         // Seuils de confiance adaptatifs
    // ★ v10.38 : Historique premium calendrier (étoiles multi-jours)
    'ia_premium_historique_v1', // Historique premium calendrier étoile (non recalculable)
    'ia_premium_du_jour_v1',    // Ancien format compat (lecture seule — migration vers _historique)
    // ★ v10.62 : Figeage des 5 widgets premium du jour (conseilJour/meilleurPari/topEquilibre/plusSur/plusRentable)
    // Non recalculable — doit être restauré pour préserver le figeage inter-sessions.
    'premium_widgets_selection_jour_v1',
    // Note : ia_rapport_hebdo_v1 retiré (jamais écrit — clé orpheline v9.87)
  ];

  // 📡 ELO & Cote — données dynamiques par discipline
  static const _keysELO = [
    'elo_ratings_v2',       // ★ v9.92 : Ratings ELO par cheval×discipline (K-factor adaptatif)
    'elo_ratings_v2_ts',    // ★ v9.92 : Timestamp dernière mise à jour ELO
    'cote_tracker_mouvements_v1', // ★ v9.97 : Mouvements de cote en temps réel
    'cote_mouvements_live_v1',    // ★ v9.97 : Sync Flutter→Kotlin Worker (alertes cote)
  ];

  // 🎯 Config fusion BestBet — reglages de l'algorithme de selection
  // IMPORTANT : fusion_poids_* sont stockes en DOUBLE, fusion_seuil_min en INT
  // On les serialise tous en String JSON pour une restauration universelle
  static const _keysConfigIA = [
    'fusion_poids_confiance',
    'fusion_poids_gain',
    'fusion_poids_risque',
    'fusion_seuil_min',
    // ★ v9.80 : Préférences Backtesting
    'bt_mise',
    'bt_jours',
    'bt_type',
    'bt_confiance_min',
    'bt_discipline',     // ★ v10.371-audit : filtre discipline backtesting
    'bt_hippodrome',     // ★ v10.371-audit : filtre hippodrome backtesting
    // ★ v10.22 : Filtres Conseils IA (persistés dans conseils_screen.dart)
    'conseils_filtres_types_paris',
    'conseils_filtres_confiance_min',
    'conseils_filtres_hippodromes',
    'conseils_filtres_disciplines',
    'conseils_filtres_tri_mode',    // ★ v10.24 audit
    'conseils_filtres_actifs',      // ★ v9.93 : état ON/OFF bouton filtres
    // ★ v9.85 : Identité de l'IA
    'ia_prenom',
    'ia_avatar_id',
    'ia_date_installation',
    'ia_bulle_active',
    // ★ v9.94 : Cooldown bulle et message du jour (manquants dans v7.1)
    'ia_derniere_bulle',          // Timestamp dernière bulle affichée (cooldown 30min)
    'ia_dernier_message_jour',    // Message IA du jour (évite répétition)
    // ★ v9.85 : Préférences utilisateur et badges
    'ia_user_prefs_v1',
    'ia_badges_v1',
    // ★ v10.27 : Seuils paliers calendrier (editables par l'utilisateur)
    'ia_calendrier_seuils_v1',
    // ★ v10.34/v10.35 : Flags migration précision (recalcul après fix Couplé)
    'ia_precision_migrated_v2',
    'ia_precision_migrated_v3',
    // ★ v10.65 : Mémoire narrative anti-répétition (secondaire — recréable si absente)
    // Si absente dans un ancien backup : créée vide automatiquement, jamais crash
    'ia_narrative_memory_v1',
    // ★ v10.66 : Cache narratif journalier (secondaire — recréable proprement si absent)
    // En cas d'absence dans un ancien backup → reset cache uniquement, jamais bloquer la restauration
    'ia_narrative_daily_cache_v1',
    // ★ v10.371-audit : flags transitoires (one-shot — restaurer évite un recalcul inutile)
    'elo_orphelins_purges_v1',   // Flag purge ELO orphelins (elo_service)
    'conseils_inject_pending',   // Flag injection conseils en attente
    // ★ v10.70 : Filtres Précision IA (préférences d'affichage uniquement)
    // Ces clés NE touchent PAS : apprentissage IA, poids, premium, backtesting, calendrier.
    // Si absentes dans un ancien backup → filtre par défaut '60j' utilisé. Jamais bloquant.
    'ia_stats_filtre_actif_v1',  // Filtre actif : '60j', 'all', '7j', 'today', 'custom'
    'ia_stats_date_debut_v1',    // Date début période personnalisée (ISO 8601)
    'ia_stats_date_fin_v1',      // Date fin période personnalisée (ISO 8601)
  ];

  // 📋 Paris utilisateur — historique complet
  static const _keysParis = [
    'user_predictions_v2',
  ];

  // 🔔 Alertes — config + historique + courses suivies
  static const _keysAlertes = [
    'alert_config_v2',
    'alert_history_v1',
    'tracked_courses_v1',
    'alert_sent_ids_v1',
    'alert_resultats_verifies_v1',
    'hippique_favorites_v1',        // ★ v9.5 : Cours favorites (FavoriButton)
    // ★ v9.94 : Conseils IA notifiés (anti-spam + résumé matinal)
    'conseil_ia_notifies_v1',         // CourseKeys déjà notifiées ce jour
    'conseil_ia_resume_date',         // Date du dernier résumé matinal
    // ★ v9.94-audit : clés manquantes
    'alert_cote_chute_notifies_v1',   // Anti-doublons alertes cote chute (alert_service)
    'data_refresh_resume_hebdo_date', // Date dernier résumé hebdo lundi (data_refresh_service)
    'alerte_sommeil_v1',              // ★ v10.41 : Mode Sommeil — plage horaire sans alertes
  ];

  // 👤 Profil — identite de l'utilisateur
  // profil_photo_path exclu : chemin local non portable entre telephones
  static const _keysProfil = [
    'profil_nom',
    'profil_gmail',
    'chevaux_suivis_v1',
    // ★ v9.85 : Bankroll
    'bankroll_capital_v1',
    // ★ v9.94 : Heure dernière analyse (manquante dans v7.1)
    'ia_derniere_analyse_heure_v1', // Heure précise de la dernière analyse journée
  ];

  // 📱 Widget Android — etat du widget affiche sur l'ecran d'accueil
  // Clés alignées avec widget_service.dart (écrites via MethodChannel → RacePredictorWidgetData)
  // NOTE : ces clés sont dans FlutterSharedPreferences (préfixe flutter. ajouté automatiquement)
  // mais le widget natif lit dans RacePredictorWidgetData via son propre getSharedPreferences.
  // Le backup de ces clés sert à restaurer l'affichage inter-sessions (régénéré au prochain refresh).
  static const _keysWidget = [
    'widget_course_name',
    'widget_horse_name',
    'widget_horse_num',
    'widget_confiance',
    'widget_gain',
    'widget_hippodrome',
    'widget_heure',
    'widget_nb_courses',
    'widget_updated_at',
    // ★ Lot 4 : nouveaux champs widget v2.0
    'widget_score_ia',
    'widget_type_pari',
    'widget_tendance',
    'widget_elo',
    'widget_course2_name',
    'widget_horse2_name',
    'widget_heure2',
    'widget_confiance2',
    'widget_course3_name',
    'widget_horse3_name',
    'widget_heure3',
    'widget_confiance3',
    // ★ v10.24 audit : Feature #7 — compteur Conseils IA + forme top cheval
    'widget_nb_criteres',
    'widget_forme',
  ];

  // 🧪 Labo IA — pistes de simulation sauvegardées par l'utilisateur
  // OBLIGATOIRE : non recalculable (données saisies manuellement par l'utilisateur)
  static const _keysLaboIA = [
    'simulation_candidates_v1', // Pistes Labo IA (SimulationCandidateService)
  ];

  // 📊 Cache Audit — résultats pré-calculés des 4 onglets Audit
  // OPTIONNEL : recalculable, mais évite 30s de recalcul au premier lancement
  static const _keysAuditCache = [
    'ia_audit_cache_v1', // Cache des onglets Audit (IaAuditCacheService)
  ];

  // ⚠️ Gros Paris — signaux Gros paris à surveiller + Quasi gagnants archivés
  // OBLIGATOIRE : non recalculable (signaux d'avant-course disparus après la course)
  // Rétrocompat : absent dans un ancien backup → reset à liste vide (jamais crash)
  static const _keysGrosParis = [
    'ia_quasi_gros_paris_v1',          // ★ v10.72 : Signaux Gros paris + Quasi gagnants
    'ia_gros_paris_resultats_v1',      // ★ v10.75b : Vrais gagnants ordre/désordre
    // ★ v10.76 : Nouvelles clés
    'pronostic_resultats_repository_v2',   // Repository résultats utilisateur
    'home_best_bet_snapshot_v2',           // Snapshot "Meilleur Pari" Home
    'home_best_bet_snapshot_date_v2',      // Date snapshot Home
    'ia_migration_gros_paris_desordre_v1_done', // Flag migration one-shot v10.76
    // ★ v10.77 : Migration stats — branchement PronosticResultatsRepository dans écrans stats
    'ia_migration_gros_paris_stats_v2_done',    // Flag migration stats v10.77
    // ★ v10.79 : Migration types dérivés — évalue Tiercé/Quarté+/Quinté+ séparément
    'ia_migration_gros_paris_types_derives_v1_done', // Flag migration types dérivés v10.79
    // ★ v10.80 : Migration suite IA classique — réussites dérivées depuis topNIA figé
    'ia_migration_suite_ia_classique_v1_done',        // Flag migration suite IA classique v10.80
  ];

  // Toutes les cles reunies (pour reinitialisation complete)
  static List<String> get _toutesLesCles => [
    ..._keysIA,
    ..._keysConfigIA,
    ..._keysParis,
    ..._keysAlertes,
    ..._keysProfil,
    ..._keysWidget,
    ..._keysLaboIA,
    ..._keysAuditCache,
    ..._keysGrosParis,
  ];

  // ════════════════════════════════════════════════════════════════════════
  //  LECTURE UNIVERSELLE — supporte StringList, String, int, double, bool
  // ════════════════════════════════════════════════════════════════════════

  /// Lit une cle SharedPreferences en detectant automatiquement son type.
  /// Retourne null si la cle n'existe pas.
  Map<String, dynamic>? _lireEntree(SharedPreferences prefs, String key) {
    // Priority 1 : StringList (ia_pronostics_v2, ia_journal_v2, etc.)
    try {
      final list = prefs.getStringList(key);
      if (list != null) return {'type': 'StringList', 'value': list};
    } catch (_) {}

    // Priority 2 : Scalaire via prefs.get()
    final v = prefs.get(key);
    if (v == null) return null;
    if (v is String)  return {'type': 'String',  'value': v};
    if (v is int)     return {'type': 'int',     'value': v};
    if (v is double)  return {'type': 'double',  'value': v};
    if (v is bool)    return {'type': 'bool',    'value': v};
    if (v is List)    return {'type': 'StringList', 'value': List<String>.from(v.map((e) => e.toString()))};
    return null;
  }

  // ════════════════════════════════════════════════════════════════════════
  //  COLLECTE — lit TOUTES les donnees de l'app
  // ════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> _collecterDonnees() async {
    final prefs = await SharedPreferences.getInstance();

    final data = <String, dynamic>{
      'version'    : _backupVersion,
      'appName'    : 'Pronostic Hippique',
      'dateBackup' : DateTime.now().toIso8601String(),
      'ia'         : <String, dynamic>{},
      'configIA'   : <String, dynamic>{},
      'paris'      : <String, dynamic>{},
      'alertes'    : <String, dynamic>{},
      'profil'     : <String, dynamic>{},
      'widget'     : <String, dynamic>{},
      'laboIA'     : <String, dynamic>{},   // ★ v10.35 : Pistes Labo IA
      'auditCache' : <String, dynamic>{},   // ★ v10.35 : Cache Audit
      'grosParis'  : <String, dynamic>{},   // ★ v10.72 : Gros Paris à surveiller
    };

    // ── 🧠 Memoire IA ────────────────────────────────────────────────────
    for (final key in _keysIA) {
      final entry = _lireEntree(prefs, key);
      if (entry != null) {
        data['ia'][key] = entry;
        if (kDebugMode) {
          final val = entry['value'];
          final info = val is List ? '${val.length} entrees' : 'ok (${entry['type']})';
          debugPrint('[Backup] IA  $key -> $info');
        }
      } else {
        if (kDebugMode) debugPrint('[Backup] IA  $key -> ABSENT (ok)');
      }
    }

    // ── 🎯 Config Fusion BestBet ─────────────────────────────────────────
    // fusion_poids_* : double | fusion_seuil_min : int
    for (final key in _keysConfigIA) {
      final entry = _lireEntree(prefs, key);
      if (entry != null) {
        data['configIA'][key] = entry;
        if (kDebugMode) debugPrint('[Backup] CFG $key -> ${entry['value']}');
      }
    }

    // ── 📋 Paris utilisateur ─────────────────────────────────────────────
    for (final key in _keysParis) {
      final list = prefs.getStringList(key) ?? [];
      data['paris'][key] = {'type': 'StringList', 'value': list};
      if (kDebugMode) debugPrint('[Backup] PAR $key -> ${list.length} paris');
    }

    // ── 🔔 Alertes ────────────────────────────────────────────────────────
    for (final key in _keysAlertes) {
      final entry = _lireEntree(prefs, key);
      if (entry != null) {
        data['alertes'][key] = entry;
        if (kDebugMode) {
          final val = entry['value'];
          final info = val is List ? '${val.length} entrees' : 'ok';
          debugPrint('[Backup] ALT $key -> $info');
        }
      }
    }

    // ── 👤 Profil ─────────────────────────────────────────────────────────
    for (final key in _keysProfil) {
      final entry = _lireEntree(prefs, key);
      if (entry != null) {
        data['profil'][key] = entry;
        if (kDebugMode) debugPrint('[Backup] PRF $key -> ok');
      }
    }

    // ── 📱 Widget Android ─────────────────────────────────────────────────
    for (final key in _keysWidget) {
      final entry = _lireEntree(prefs, key);
      if (entry != null) {
        data['widget'][key] = entry;
        if (kDebugMode) debugPrint('[Backup] WGT $key -> ok');
      }
    }

    // ── 🧪 Labo IA — pistes de simulation ★ v10.35 ───────────────────────
    for (final key in _keysLaboIA) {
      final entry = _lireEntree(prefs, key);
      if (entry != null) {
        data['laboIA'][key] = entry;
        if (kDebugMode) {
          final val = entry['value'];
          final info = val is List ? '${val.length} pistes' : 'ok (${entry['type']})';
          debugPrint('[Backup] LAB $key -> $info');
        }
      } else {
        if (kDebugMode) debugPrint('[Backup] LAB $key -> ABSENT (ok)');
      }
    }

    // ── 📊 Cache Audit — ★ v10.35 ────────────────────────────────────────
    for (final key in _keysAuditCache) {
      final entry = _lireEntree(prefs, key);
      if (entry != null) {
        data['auditCache'][key] = entry;
        if (kDebugMode) debugPrint('[Backup] AUD $key -> ok');
      } else {
        if (kDebugMode) debugPrint('[Backup] AUD $key -> ABSENT (ok)');
      }
    }

    // ── ⚠️ Gros Paris ★ v10.72 / v10.75b ──────────────────────────────────────
    // Les données sont gérées par QuasiGrosParisService (pas des SharedPreferences
    // classiques) — on les exporte via la méthode dédiée du service.
    // ★ v10.75b : inclut maintenant grosParisGagnants (ia_gros_paris_resultats_v1)
    try {
      final grosParisData = QuasiGrosParisService.instance.exporterPourBackup();
      if (grosParisData.isNotEmpty) {
        data['grosParis'] = grosParisData;
        if (kDebugMode) {
          final nbSignaux  = (grosParisData['signaux']           as List? ?? []).length;
          final nbQG       = (grosParisData['quasiGagnants']     as List? ?? []).length;
          final nbGagnants = (grosParisData['grosParisGagnants'] as List? ?? []).length;
          debugPrint('[Backup] GRO -> $nbSignaux signaux, $nbQG quasi-gagnants, '
              '$nbGagnants gagnants (ia_gros_paris_resultats_v1)');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Backup] GRO export partiel : $e');
    }

    // ── 🏇 ELO SERVICE ★ v8.0 ──────────────────────────────────────────────
    // Les ratings ELO sont gérés par EloService (pas des SharedPreferences
    // classiques) — on les exporte/importe via la méthode dédiée du service.
    final eloData = EloService.instance.exporterPourBackup();
    if (eloData.isNotEmpty) {
      data['elo_service'] = eloData;
      if (kDebugMode) debugPrint('[Backup] ELO -> ${eloData.length} chevaux');
    }

    // ── 📡 CoteTracker ★ v9.97 ─────────────────────────────────────────────
    // Mouvements de cote en temps réel + sync Flutter→Kotlin Worker
    data['cote'] = <String, dynamic>{};
    for (final key in _keysELO.where((k) => k.startsWith('cote_'))) {
      final entry = _lireEntree(prefs, key);
      if (entry != null) {
        data['cote'][key] = entry;
        if (kDebugMode) debugPrint('[Backup] COT $key -> ok');
      }
    }

    return data;
  }

  // ════════════════════════════════════════════════════════════════════════
  //  RESTAURATION UNIVERSELLE d'un groupe de cles
  // ════════════════════════════════════════════════════════════════════════

  Future<int> _restaurerGroupe(
    SharedPreferences prefs,
    Map<String, dynamic>? groupe,
  ) async {
    if (groupe == null) return 0;
    int nbRestaurees = 0;

    for (final entry in groupe.entries) {
      final key = entry.key;
      final raw = entry.value;

      try {
        // Format v4.0/v5.0 : {'type': '...', 'value': ...}
        if (raw is Map<String, dynamic> && raw.containsKey('type') && raw.containsKey('value')) {
          final type = raw['type'] as String;
          final val  = raw['value'];

          switch (type) {
            case 'StringList':
              final list = List<String>.from((val as List).map((e) => e.toString()));
              await prefs.setStringList(key, list);
            case 'String':
              await prefs.setString(key, val as String);
            case 'int':
              // Robustesse : val peut etre int ou double selon JSON parse
              await prefs.setInt(key, (val as num).toInt());
            case 'double':
              await prefs.setDouble(key, (val as num).toDouble());
            case 'bool':
              await prefs.setBool(key, val as bool);
            default:
              // Fallback : si type inconnu, tenter String
              await prefs.setString(key, val.toString());
          }
          nbRestaurees++;
        }
        // Retrocompatibilite v1–v3 : valeur brute sans enveloppe 'type'
        else if (raw is List) {
          final list = List<String>.from(raw.map((e) => e.toString()));
          await prefs.setStringList(key, list);
          nbRestaurees++;
        } else if (raw is String) {
          await prefs.setString(key, raw);
          nbRestaurees++;
        } else if (raw is int) {
          await prefs.setInt(key, raw);
          nbRestaurees++;
        } else if (raw is double) {
          await prefs.setDouble(key, raw);
          nbRestaurees++;
        } else if (raw is bool) {
          await prefs.setBool(key, raw);
          nbRestaurees++;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[Backup] Restauration $key : $e');
      }
    }
    return nbRestaurees;
  }

  // ════════════════════════════════════════════════════════════════════════
  //  EXPORT — Genere le fichier JSON de sauvegarde
  // ════════════════════════════════════════════════════════════════════════

  Future<ExportResult> exporterDonnees() async {
    try {
      final data    = await _collecterDonnees();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      final bytes   = utf8.encode(jsonStr);

      final now     = DateTime.now();
      final dateStr = '${now.day.toString().padLeft(2,'0')}${now.month.toString().padLeft(2,'0')}${now.year}';
      final fileName = 'backup_pronostic_hippique_$dateStr.json';

      final tmpDir = await getTemporaryDirectory();
      final file   = File('${tmpDir.path}/$fileName');
      await file.writeAsBytes(bytes);

      if (kDebugMode) {
        debugPrint('[Backup] Export OK -> ${file.path} (${(bytes.length / 1024).toStringAsFixed(1)} Ko)');
      }
      return ExportResult(succes: true, filePath: file.path, fileName: fileName, tailleOctets: bytes.length);
    } catch (e) {
      if (kDebugMode) debugPrint('[Backup] Export ERREUR : $e');
      return ExportResult(succes: false, erreur: e.toString());
    }
  }

  /// Partage le fichier backup via le menu natif Android
  Future<bool> partagerBackup() async {
    try {
      final result = await exporterDonnees();
      if (!result.succes) return false;

      final now     = DateTime.now();
      final dateStr = '${now.day.toString().padLeft(2,'0')}/${now.month.toString().padLeft(2,'0')}/${now.year}';

      await SharePlus.instance.share(
        ShareParams(
          files  : [XFile(result.filePath!, mimeType: 'application/json')],
          text   : 'Sauvegarde Pronostic Hippique du $dateStr\n'
                   'Contient : IA (19 critères + ELO + terrain + progression + mémoire + PoidsIndices) + Paris + Alertes + Profil + Widget v2.0',
          subject: 'Sauvegarde Pronostic Hippique $dateStr',
        ),
      );
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[Backup] Partage ERREUR : $e');
      return false;
    }
  }

  /// Ouvre Google Drive avec le fichier backup (via le menu de partage)
  Future<bool> sauvegarderSurDrive() async => partagerBackup();

  /// Copie le fichier backup dans le dossier Telechargements du telephone
  Future<ExportResult> telechargerSurTelephone() async {
    try {
      final result = await exporterDonnees();
      if (!result.succes) return result;

      final downloadsDir = await getExternalStorageDirectory();
      String downloadPath;

      if (downloadsDir != null) {
        final parts      = downloadsDir.path.split('/');
        final androidIdx = parts.indexOf('Android');
        downloadPath = androidIdx > 0
            ? '${parts.take(androidIdx).join('/')}/Download'
            : '${downloadsDir.path}/backup';
      } else {
        return ExportResult(succes: false, erreur: 'Stockage externe inaccessible');
      }

      final destDir = Directory(downloadPath);
      if (!await destDir.exists()) await destDir.create(recursive: true);

      final destFile = File('$downloadPath/${result.fileName}');
      await File(result.filePath!).copy(destFile.path);

      if (kDebugMode) debugPrint('[Backup] Telecharge -> ${destFile.path}');
      return ExportResult(
        succes: true,
        filePath: destFile.path,
        fileName: result.fileName,
        tailleOctets: result.tailleOctets,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Backup] Telechargement ERREUR : $e');
      return ExportResult(succes: false, erreur: e.toString());
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  IMPORT — Restaure depuis un fichier JSON selectionne par l'utilisateur
  // ════════════════════════════════════════════════════════════════════════

  Future<ImportResult> importerDepuisFichier() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type             : FileType.custom,
        allowedExtensions: ['json'],
        withData         : true,
      );

      if (picked == null || picked.files.isEmpty) {
        return ImportResult(succes: false, erreur: 'Aucun fichier selectionne');
      }

      final file = picked.files.first;
      String jsonStr;

      if (file.bytes != null) {
        jsonStr = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        jsonStr = await File(file.path!).readAsString();
      } else {
        return ImportResult(succes: false, erreur: 'Impossible de lire le fichier');
      }

      return await _restaurerDepuisJson(jsonStr);
    } catch (e) {
      if (kDebugMode) debugPrint('[Backup] Import ERREUR : $e');
      return ImportResult(succes: false, erreur: e.toString());
    }
  }

  Future<ImportResult> _restaurerDepuisJson(String jsonStr) async {
    try {
      final Map<String, dynamic> data = json.decode(jsonStr) as Map<String, dynamic>;

      if (data['appName'] != 'Pronostic Hippique') {
        return ImportResult(succes: false, erreur: 'Fichier invalide ou incompatible');
      }

      final prefs = await SharedPreferences.getInstance();
      int total = 0;

      // 🧠 Memoire IA
      final nbIA = await _restaurerGroupe(prefs, data['ia'] as Map<String, dynamic>?);
      total += nbIA;
      if (kDebugMode) debugPrint('[Backup] IA restauree : $nbIA cles');

      // 🎯 Config Fusion
      final nbCfg = await _restaurerGroupe(prefs, data['configIA'] as Map<String, dynamic>?);
      total += nbCfg;
      if (kDebugMode) debugPrint('[Backup] Config IA restauree : $nbCfg cles');

      // 📋 Paris
      final nbParisCles = await _restaurerGroupe(prefs, data['paris'] as Map<String, dynamic>?);
      total += nbParisCles;
      // Compter le nombre reel de paris restaures
      int nbParisCount = 0;
      try {
        final list = prefs.getStringList('user_predictions_v2') ?? [];
        nbParisCount = list.length;
      } catch (_) {}
      if (kDebugMode) debugPrint('[Backup] Paris restaures : $nbParisCount paris');

      // 🔔 Alertes
      final nbAlertesCles = await _restaurerGroupe(prefs, data['alertes'] as Map<String, dynamic>?);
      total += nbAlertesCles;
      // Compter le nombre reel d'alertes
      int nbAlertesCount = 0;
      try {
        final list = prefs.getStringList('alert_history_v1') ?? [];
        nbAlertesCount = list.length;
      } catch (_) {}
      if (kDebugMode) debugPrint('[Backup] Alertes restaurees : $nbAlertesCount alertes ($nbAlertesCles cles)');

      // 👤 Profil
      final nbProfil = await _restaurerGroupe(prefs, data['profil'] as Map<String, dynamic>?);
      total += nbProfil;
      if (kDebugMode) debugPrint('[Backup] Profil restaure : $nbProfil cles');

      // 📱 Widget
      final nbWidget = await _restaurerGroupe(prefs, data['widget'] as Map<String, dynamic>?);
      total += nbWidget;
      if (kDebugMode) debugPrint('[Backup] Widget restaure : $nbWidget cles');

      // ── 🏇 ELO SERVICE ★ v8.0 ────────────────────────────────────────────
      // Restaurer les ratings ELO depuis le backup si présents
      if (data.containsKey('elo_service')) {
        try {
          await EloService.instance.importerDepuisBackup(
              data['elo_service'] as Map<String, dynamic>);
          if (kDebugMode) debugPrint('[Backup] ELO restaure');
        } catch (e) {
          if (kDebugMode) debugPrint('[Backup] ELO restauration partielle : $e');
        }
      }

      // ── 📡 COTE TRACKER ★ v9.97 ──────────────────────────────────────────
      // Restaurer les mouvements de cote en temps réel
      if (data.containsKey('cote')) {
        final nbCote = await _restaurerGroupe(prefs, data['cote'] as Map<String, dynamic>?);
        total += nbCote;
        if (kDebugMode) debugPrint('[Backup] CoteTracker restaure : $nbCote cles');
      }

      // ── 🧪 LABO IA ★ v10.35 ──────────────────────────────────────────────
      // Restaurer les pistes de simulation (obligatoire — non recalculable)
      if (data.containsKey('laboIA')) {
        final nbLabo = await _restaurerGroupe(prefs, data['laboIA'] as Map<String, dynamic>?);
        total += nbLabo;
        if (kDebugMode) debugPrint('[Backup] LaboIA restaure : $nbLabo cles');
      }

      // ── 📊 CACHE AUDIT ★ v10.35 ──────────────────────────────────────────
      // Restaurer le cache Audit (optionnel — recalculable si absent)
      if (data.containsKey('auditCache')) {
        final nbAudit = await _restaurerGroupe(prefs, data['auditCache'] as Map<String, dynamic>?);
        total += nbAudit;
        if (kDebugMode) debugPrint('[Backup] AuditCache restaure : $nbAudit cles');
      }

      // ── ⚠️ GROS PARIS ★ v10.72 ───────────────────────────────────────────
      // Restaurer les signaux Gros Paris + Quasi Gagnants (obligatoire — non recalculable)
      // Rétrocompat : clé absente dans un ancien backup → reset à vide, jamais crash
      try {
        if (data.containsKey('grosParis')) {
          final grosParisRaw = data['grosParis'];
          if (grosParisRaw is Map<String, dynamic>) {
            await QuasiGrosParisService.instance.importerDepuisBackup(grosParisRaw);
            if (kDebugMode) {
              final nbS = (grosParisRaw['signaux']           as List? ?? []).length;
              final nbQ = (grosParisRaw['quasiGagnants']     as List? ?? []).length;
              final nbG = (grosParisRaw['grosParisGagnants'] as List? ?? []).length;
              debugPrint('[Backup] GrosParis restaure : $nbS signaux, $nbQ quasi-gagnants, '
                  '$nbG gagnants (ia_gros_paris_resultats_v1)');
            }
          }
        } else {
          // Rétrocompat : absent dans un ancien backup → reset propre à vide
          await QuasiGrosParisService.instance.importerDepuisBackup({'signaux': [], 'quasiGagnants': []});
          if (kDebugMode) {
            debugPrint('[Backup] grosParis absent → reset à vide (compat v<9.0)');
          }
        }
      } catch (e) {
        // Clé corrompue : reset uniquement cette clé, ne jamais bloquer la restauration
        if (kDebugMode) debugPrint('[Backup] GrosParis restauration partielle (reset) : $e');
        try {
          await QuasiGrosParisService.instance.importerDepuisBackup({'signaux': [], 'quasiGagnants': []});
        } catch (_) {}
      }

      // Retrocompatibilite : anciens formats v1/v2/v3 sans certains groupes
      final backupVer  = data['version'] as String? ?? '1.0';
      final dateBackup = data['dateBackup'] as String? ?? '';

      // Compter les pronostics IA restaurés (version compressée ou non)
      int nbPronosticsIA = 0;
      try {
        // D'abord chercher la version compressée (Lot 4)
        final gz = prefs.getString('ia_pronostics_v2_gz') ?? '';
        if (gz.isNotEmpty) {
          // Estimation : ~1 pronostic = ~200 octets JSON = ~100 octets gzip base64
          nbPronosticsIA = (gz.length / 130).round();
        } else {
          final list = prefs.getStringList('ia_pronostics_v2') ?? [];
          nbPronosticsIA = list.length;
        }
      } catch (_) {}

      if (kDebugMode) {
        debugPrint('[Backup] Import complet — $total cles restaurees '
            '($nbParisCount paris, $nbPronosticsIA pronostics) — format v$backupVer');
      }

      // ★ v10.65 — Compatibilité mémoire narrative (secondaire)
      // Si ia_narrative_memory_v1 est absente dans un ancien backup :
      //   → supprimer la clé existante pour repartir proprement sur mémoire vide
      //   → ne jamais crasher — la narration est secondaire
      try {
        final configGroupe = data['configIA'] as Map<String, dynamic>?;
        final hasNarrativeMemory = configGroupe != null &&
            configGroupe.containsKey('ia_narrative_memory_v1');
        if (!hasNarrativeMemory) {
          await prefs.remove('ia_narrative_memory_v1');
          if (kDebugMode) {
            debugPrint('[Backup] ia_narrative_memory_v1 absente → mémoire narrative vide (compat)');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[Backup] ia_narrative_memory_v1 compat (ignoré) : $e');
        }
      }

      // ★ v10.66 — Compatibilité cache narratif journalier (secondaire — recréable)
      // Si ia_narrative_daily_cache_v1 est absente dans un ancien backup :
      //   → reset du cache uniquement → régénération normale au prochain affichage du Journal IA
      //   → ne jamais bloquer la restauration principale
      try {
        final configGroupe = data['configIA'] as Map<String, dynamic>?;
        final hasDailyCache = configGroupe != null &&
            configGroupe.containsKey('ia_narrative_daily_cache_v1');
        if (!hasDailyCache) {
          await prefs.remove('ia_narrative_daily_cache_v1');
          if (kDebugMode) {
            debugPrint('[Backup] ia_narrative_daily_cache_v1 absente → cache narratif reset (compat)');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[Backup] ia_narrative_daily_cache_v1 compat (ignoré) : $e');
        }
      }

      // ★ v10.26c — Recharger la RAM IaMemoryService depuis les SharedPreferences restaurées
      // Indispensable si la restauration est appelée hors UI (appel direct au service)
      await IaMemoryService.instance.recharger();
      if (kDebugMode) debugPrint('[Backup] IaMemoryService rechargé depuis SharedPreferences');

      // ★ v10.26d — Recharger AlertService (alertes, courses suivies, anti-doublons)
      await AlertService.instance.recharger();
      if (kDebugMode) debugPrint('[Backup] AlertService rechargé depuis SharedPreferences');

      return ImportResult(
        succes             : true,
        nbClesRestaurees   : total,
        nbParis            : nbParisCount,
        nbPronosticsIA     : nbPronosticsIA,
        nbIA               : nbIA,
        nbAlertes          : nbAlertesCount,
        nbAlertesCles      : nbAlertesCles,
        nbWidget           : nbWidget,
        nbConfigIA         : nbCfg,
        nbProfil           : nbProfil,
        dateBackup         : dateBackup.isNotEmpty ? DateTime.tryParse(dateBackup) : null,
        version            : backupVer,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Backup] Parsing JSON : $e');
      return ImportResult(succes: false, erreur: 'Fichier corrompu : $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  GMAIL — Acces direct a l'email de l'utilisateur
  // ════════════════════════════════════════════════════════════════════════

  Future<String?> lireGmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('profil_gmail');
  }

  Future<void> sauvegarderGmail(String gmail) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profil_gmail', gmail.trim().toLowerCase());
  }

  Future<void> supprimerGmail() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('profil_gmail');
  }

  // ════════════════════════════════════════════════════════════════════════
  //  INFOS — Resume du contenu actuel pour affichage dans l'UI
  // ════════════════════════════════════════════════════════════════════════

  Future<BackupInfo> obtenirInfos() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // ── Paris utilisateur ────────────────────────────────────────────────
      final nbParis = (prefs.getStringList('user_predictions_v2') ?? []).length;

      // ── Memoire IA ───────────────────────────────────────────────────────
      final nbPronostics = (prefs.getStringList('ia_pronostics_v2') ?? []).length;
      final nbJournal    = (prefs.getStringList('ia_journal_v2')    ?? []).length;
      final nbRapports   = (prefs.getStringList('ia_rapports_v1')   ?? []).length;

      // Poids IA — nb de mises a jour (indique si l'IA a appris)
      bool iaApprise = false;
      int  nbAjustements = 0;
      Map<String, double> poidsActuels = {};
      PoidsIndicesResume? poidsIndices;
      final poidsStr = prefs.getString('ia_poids_v3');
      if (poidsStr != null) {
        try {
          final p = json.decode(poidsStr) as Map<String, dynamic>;
          nbAjustements = (p['nbMisesAJour'] as num?)?.toInt() ?? 0;
          iaApprise     = nbAjustements > 0;
          // Extraire les 19 poids adaptatifs pour affichage (v9.93)
          for (final key in ['forme','gains','record','cote','constance','victoires',
                             'discipline','distSpec','jockey','repos','hippo',
                             'entraineur','elo',                                    // v8.0
                             'terrain','divergence','poidsRel','progression',       // v9.0
                             'mouvCote','placeDepart']) {                           // v9.92/v9.93
            final val = (p[key] as num?)?.toDouble();
            if (val != null) poidsActuels[key] = val;
          }
          // Extraire PoidsIndices (pc/pco/pr)
          final piMap = p['poidsIndices'] as Map<String, dynamic>?;
          if (piMap != null) {
            poidsIndices = PoidsIndicesResume(
              criteres : (piMap['pc']  as num?)?.toDouble() ?? 0.40,
              confiance: (piMap['pco'] as num?)?.toDouble() ?? 0.35,
              reussite : (piMap['pr']  as num?)?.toDouble() ?? 0.25,
            );
          }
        } catch (_) {}
      }

      // Seuils adaptatifs
      final aSeuilsAdaptatifs = prefs.getString('ia_seuils_v1') != null;

      // Precision IA par type de pari
      int nbTypesPrecision = 0;
      final precStr = prefs.getString('ia_precision_v2');
      if (precStr != null) {
        try {
          final pMap = json.decode(precStr) as Map<String, dynamic>;
          nbTypesPrecision = pMap.length;
        } catch (_) {}
      }

      // ★ v9.0 : Stats par label IA
      int nbStatsLabels = 0;
      final labelsStr = prefs.getString('ia_stats_labels_v1');
      if (labelsStr != null) {
        try {
          final lMap = json.decode(labelsStr) as Map<String, dynamic>;
          nbStatsLabels = lMap.length;
        } catch (_) {}
      }

      // Stats par type de pari
      final nbStatsTypes = (prefs.getStringList('ia_stats_types_v1') ?? []).length;

      // ── Alertes ──────────────────────────────────────────────────────────
      final nbAlertes      = (prefs.getStringList('alert_history_v1') ?? []).length;
      final nbCoursesTrack = (prefs.getStringList('tracked_courses_v1') ?? []).length;

      // ── Profil ────────────────────────────────────────────────────────────
      final nomProfil = prefs.getString('profil_nom');
      final gmail     = prefs.getString('profil_gmail');

      // ── Config Fusion ─────────────────────────────────────────────────────
      final fusionConfiance = prefs.getDouble('fusion_poids_confiance');
      final fusionSeuil     = prefs.getInt('fusion_seuil_min');

      // ── Widget ────────────────────────────────────────────────────────────
      final widgetUpdatedAt = prefs.getString('widget_updated_at');
      final aWidget         = widgetUpdatedAt != null;

      // ── Taille estimee ────────────────────────────────────────────────────
      // ★ fix #6 : estimation rapide sans sérialiser tout le JSON
      // On additionne les tailles brutes des clés SharedPreferences (≈ même ordre de grandeur)
      int taille = 0;
      for (final key in ['user_predictions_v2', 'ia_pronostics_v2', 'ia_journal_v2',
                         'ia_rapports_v1', 'alert_history_v1', 'tracked_courses_v1',
                         'ia_poids_v3', 'ia_seuils_v1', 'ia_precision_v2',
                         'ia_stats_labels_v1', 'ia_stats_types_v1']) {
        final s = prefs.getString(key) ?? (prefs.getStringList(key) ?? []).join(',');
        taille += utf8.encode(s).length;
      }

      return BackupInfo(
        tailleOctets       : taille,
        nbParis            : nbParis,
        nbPronostics       : nbPronostics,
        nbJournal          : nbJournal,
        nbRapports         : nbRapports,
        nbAlertes          : nbAlertes,
        nbCoursesTrack     : nbCoursesTrack,
        iaApprise          : iaApprise,
        nbAjustements      : nbAjustements,
        poidsActuels       : poidsActuels,
        poidsIndices       : poidsIndices,
        aSeuilsAdaptatifs  : aSeuilsAdaptatifs,
        nbTypesPrecision   : nbTypesPrecision,
        nbStatsTypes       : nbStatsTypes,
        nbStatsLabels      : nbStatsLabels,  // ★ v9.0
        gmail              : gmail,
        nomProfil          : nomProfil,
        aConfigFusion      : fusionConfiance != null,
        fusionConfiance    : fusionConfiance,
        fusionSeuil        : fusionSeuil,
        aWidget            : aWidget,
        widgetUpdatedAt    : widgetUpdatedAt,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Backup] obtenirInfos : $e');
      return BackupInfo(
        tailleOctets: 0, nbParis: 0, nbPronostics: 0,
        nbJournal: 0, nbRapports: 0, nbAlertes: 0,
      );
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  REINITIALISATION — efface des donnees selectivement
  // ════════════════════════════════════════════════════════════════════════

  /// Efface uniquement la memoire IA (conserve les paris et le profil)
  Future<void> reinitialiserIA() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _keysIA) {
      await prefs.remove(key);
    }
    if (kDebugMode) {
      debugPrint('[Backup] IA reinitialisee (${_keysIA.length} cles effacees)');
    }
  }

  /// Efface TOUTES les donnees de l'application (remise a zero complete)
  Future<void> reinitialiserComplet() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _toutesLesCles) {
      await prefs.remove(key);
    }
    if (kDebugMode) {
      debugPrint('[Backup] Reinitialisation complete (${_toutesLesCles.length} cles effacees)');
    }
  }

  /// Efface uniquement les paris utilisateur (conserve la memoire IA)
  Future<void> reinitialiserParis() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _keysParis) {
      await prefs.remove(key);
    }
    if (kDebugMode) {
      debugPrint('[Backup] Paris reinitialises (${_keysParis.length} cles effacees)');
    }
  }

  /// Efface uniquement les alertes
  Future<void> reinitialiserAlertes() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _keysAlertes) {
      await prefs.remove(key);
    }
    if (kDebugMode) {
      debugPrint('[Backup] Alertes reinitialisees (${_keysAlertes.length} cles effacees)');
    }
  }
}

// ── Resume PoidsIndices pour l'affichage ─────────────────────────────────────

class PoidsIndicesResume {
  final double criteres;   // Poids du score multicriteres (0-1)
  final double confiance;  // Poids de la confiance IA (0-1)
  final double reussite;   // Poids du taux de reussite historique (0-1)

  const PoidsIndicesResume({
    required this.criteres,
    required this.confiance,
    required this.reussite,
  });

  String get resume =>
    'Criteres:${(criteres*100).toStringAsFixed(0)}% '
    'Confiance:${(confiance*100).toStringAsFixed(0)}% '
    'Reussite:${(reussite*100).toStringAsFixed(0)}%';
}

// ── Resultats Export ─────────────────────────────────────────────────────────

class ExportResult {
  final bool    succes;
  final String? filePath;
  final String? fileName;
  final int     tailleOctets;
  final String? erreur;

  ExportResult({
    required this.succes,
    this.filePath,
    this.fileName,
    this.tailleOctets = 0,
    this.erreur,
  });

  String get tailleLisible {
    if (tailleOctets < 1024)            return '$tailleOctets o';
    if (tailleOctets < 1024 * 1024)     return '${(tailleOctets / 1024).toStringAsFixed(1)} Ko';
    return '${(tailleOctets / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }
}

// ── Resultats Import ─────────────────────────────────────────────────────────

class ImportResult {
  final bool      succes;
  final int       nbClesRestaurees;
  final int       nbParis;           // Nombre reel de paris restaures
  final int       nbPronosticsIA;    // Nombre reel de pronostics IA restaures
  final int       nbIA;              // Nombre de cles IA restaurees
  final int       nbAlertes;         // Nombre reel d'alertes restaurees
  final int       nbAlertesCles;     // Nombre de cles alertes restaurees
  final int       nbWidget;          // Nombre de cles widget restaurees
  final int       nbConfigIA;        // Nombre de cles config IA restaurees
  final int       nbProfil;          // Nombre de cles profil restaurees
  final DateTime? dateBackup;
  final String    version;
  final String?   erreur;

  ImportResult({
    required this.succes,
    this.nbClesRestaurees = 0,
    this.nbParis          = 0,
    this.nbPronosticsIA   = 0,
    this.nbIA             = 0,
    this.nbAlertes        = 0,
    this.nbAlertesCles    = 0,
    this.nbWidget         = 0,
    this.nbConfigIA       = 0,
    this.nbProfil         = 0,
    this.dateBackup,
    this.version = '?',
    this.erreur,
  });

  String get dateBackupLisible {
    if (dateBackup == null) return 'inconnue';
    final d = dateBackup!;
    return '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year} a ${d.hour.toString().padLeft(2,'0')}h${d.minute.toString().padLeft(2,'0')}';
  }

  /// Resume lisible du resultat de l'import
  String get resumeRestauration {
    if (!succes) return 'Echec : ${erreur ?? 'Erreur inconnue'}';
    final parts = <String>[];
    if (nbParis > 0)          parts.add('$nbParis paris');
    if (nbPronosticsIA > 0)   parts.add('$nbPronosticsIA pronostics IA');
    if (nbIA > 0)             parts.add('$nbIA cles IA');
    if (nbAlertes > 0)        parts.add('$nbAlertes alertes');
    if (nbWidget > 0)         parts.add('widget');
    if (nbProfil > 0)         parts.add('profil');
    return 'Restaure : ${parts.isEmpty ? '$nbClesRestaurees cles' : parts.join(', ')}';
  }
}

// ── Informations sur le backup actuel ────────────────────────────────────────

class BackupInfo {
  // Volume de donnees
  final int     tailleOctets;
  final int     nbParis;
  final int     nbPronostics;
  final int     nbJournal;
  final int     nbRapports;

  // Alertes
  final int     nbAlertes;
  final int     nbCoursesTrack;

  // IA
  final bool    iaApprise;
  final int     nbAjustements;
  final Map<String, double> poidsActuels;   // 19 critères adaptatifs (v10.x : +mouvCote, +placeDepart)
  final PoidsIndicesResume? poidsIndices;   // Indices criteres/confiance/reussite
  final bool    aSeuilsAdaptatifs;
  final int     nbTypesPrecision;
  final int     nbStatsTypes;
  final int     nbStatsLabels;    // ★ v9.0 : Stats par label IA

  // Profil
  final String? gmail;
  final String? nomProfil;

  // Config Fusion
  final bool    aConfigFusion;
  final double? fusionConfiance;
  final int?    fusionSeuil;

  // Widget
  final bool    aWidget;
  final String? widgetUpdatedAt;

  BackupInfo({
    required this.tailleOctets,
    required this.nbParis,
    required this.nbPronostics,
    required this.nbJournal,
    required this.nbRapports,
    required this.nbAlertes,
    this.nbCoursesTrack     = 0,
    this.iaApprise          = false,
    this.nbAjustements      = 0,
    this.poidsActuels       = const {},
    this.poidsIndices,
    this.aSeuilsAdaptatifs  = false,
    this.nbTypesPrecision   = 0,
    this.nbStatsTypes       = 0,
    this.nbStatsLabels      = 0,  // ★ v9.0
    this.gmail,
    this.nomProfil,
    this.aConfigFusion      = false,
    this.fusionConfiance,
    this.fusionSeuil,
    this.aWidget            = false,
    this.widgetUpdatedAt,
  });

  String get tailleLisible {
    if (tailleOctets < 1024)         return '$tailleOctets o';
    if (tailleOctets < 1024 * 1024)  return '${(tailleOctets / 1024).toStringAsFixed(1)} Ko';
    return '${(tailleOctets / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }

  /// Pourcentage de couverture (indicateur sante du backup)
  /// Compte les 10 categories principales presentant des donnees
  int get couverturePct {
    int couvert = 0;
    if (nbPronostics > 0)    couvert++;  // Pronostics IA
    if (nbJournal > 0)       couvert++;  // Journal gradient
    if (nbRapports > 0)      couvert++;  // Rapports journaliers
    if (nbParis > 0)         couvert++;  // Paris utilisateur
    if (nbAlertes > 0)       couvert++;  // Alertes
    if (iaApprise)           couvert++;  // IA a appris (poids ajustes)
    if (aSeuilsAdaptatifs)   couvert++;  // Seuils adaptatifs
    if (aConfigFusion)       couvert++;  // Config Fusion BestBet
    if (gmail != null)       couvert++;  // Profil Gmail
    if (aWidget)             couvert++;  // Widget Android
    return couvert * 10; // /10 categories = %
  }

  /// Description des poids IA pour l'UI
  String get resumePoidsIA {
    if (poidsActuels.isEmpty) return 'IA non initialisee';
    final parts = <String>[];
    void ajouter(String key, String label) {
      final v = poidsActuels[key];
      if (v != null) parts.add('$label:${(v*100).toStringAsFixed(0)}%');
    }
    ajouter('forme',     'Forme');
    ajouter('cote',      'Cote');
    ajouter('gains',     'Gains');
    ajouter('jockey',    'Jockey');
    ajouter('hippo',     'Hippo');
    return parts.join(' | ');
  }
}
