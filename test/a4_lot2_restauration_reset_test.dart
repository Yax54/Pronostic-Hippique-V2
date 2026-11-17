// ═══════════════════════════════════════════════════════════════════════════
//  A4 — LOT 2/2 : RESTAURATION DE SAUVEGARDE (T6) ET RÉINITIALISATION (T7)
//
//  ⚠️  FICHIER DE TEST uniquement. AUCUNE modification de lib/.
//  ⚠️  Aucun test existant n'est modifié : ce fichier est autonome.
//
//  ── T6 — RESTAURATION DE SAUVEGARDE ──────────────────────────────────────
//  Une sauvegarde est produite avec des paramètres IA VOLONTAIREMENT
//  DIFFÉRENTS de l'état de l'appareil, puis restaurée par la vraie API
//  publique (`exporterDonnees` → `importerDepuisFichier` →
//  `_restaurerDepuisJson`). On vérifie que la restauration produit
//  EXACTEMENT l'état décrit par le format de sauvegarde, et rien de plus.
//
//  ── T7 — RÉINITIALISATION ───────────────────────────────────────────────
//  Le périmètre est identifié AVANT d'être testé, en lisant le code :
//    • `BackupService.reinitialiserComplet()`  (backup_service.dart:1496)
//        efface les 107 clés fixes + les `cache_reunions_*` dynamiques,
//        vide la RAM des services et remet poids/seuils/calibration
//        aux valeurs d'usine. Les 15 clés `_keysIA` disparaissent.
//        L'ARCHIVE HISTORIQUE et les ARRIVÉES OFFICIELLES ne figurent dans
//        aucune des listes effacées : elles survivent (décision E4 / L0).
//    • `BackupService.reinitialiserIA()`       (backup_service.dart:1482)
//        efface UNIQUEMENT les 15 clés `_keysIA` sur le disque.
//        Il ne vide PAS la RAM et ne touche à AUCUNE autre famille de clés.
//        Ce périmètre restreint est MESURÉ ici, pas supposé.
//
//  Les deux dépendances de plateforme sont injectées, comme dans V5 :
//    • PathProviderPlatform.instance → _FakePathProvider
//    • FilePicker.platform           → _FakeFilePicker
//  Le stockage est un espion en mémoire qui compte les écritures.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/arrivee_officielle_service.dart';
import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_archive_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Faux de plateforme
// ───────────────────────────────────────────────────────────────────────────

/// Injecte un répertoire temporaire réel : `exporterDonnees()` doit pouvoir
/// écrire le fichier JSON sur le disque du sandbox.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.tmpPath);
  final String tmpPath;

  @override
  Future<String?> getTemporaryPath() async => tmpPath;
}

/// Injecte un fichier choisi sans passer par le sélecteur natif.
/// `FilePicker()` appelle `super(token: _token)` → la vérification
/// `PlatformInterface.verifyToken` du setter `FilePicker.platform` passe.
class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this._result);

  final FilePickerResult? _result;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      _result;
}

// ───────────────────────────────────────────────────────────────────────────
//  Espion de stockage : mêmes contrat et niveau de nommage que le vrai store
//  (`flutter.` préfixé), plus un journal des écritures réellement effectuées.
// ───────────────────────────────────────────────────────────────────────────
class _Espion extends SharedPreferencesStorePlatform {
  _Espion();

  final Map<String, Object> _valeurs = <String, Object>{};

  /// Écritures (`SET`/`REM`) réellement exécutées, dans l'ordre.
  final List<String> journal = <String>[];

  @override
  Future<bool> clear() async {
    journal.add('CLEAR');
    _valeurs.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<Map<String, Object>> getAllWithParameters(
      GetAllParameters parameters) async {
    final prefix = parameters.filter.prefix;
    return <String, Object>{
      for (final e in _valeurs.entries)
        if (e.key.startsWith(prefix)) e.key: e.value,
    };
  }

  @override
  Future<bool> remove(String key) async {
    journal.add('REM $key');
    _valeurs.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    journal.add('SET $key');
    _valeurs[key] = value;
    return true;
  }

  // ── Helpers : clé NON préfixée, comme `prefs.setString(key, …)` ───────────
  void semer(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;

  void retirer(String cle) => _valeurs.remove('flutter.$cle');

  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');

  Object? brut(String cle) => _valeurs['flutter.$cle'];

  /// Clés présentes, sans le préfixe `flutter.`, triées.
  List<String> get cles => _valeurs.keys
      .map((k) => k.startsWith('flutter.') ? k.substring(8) : k)
      .toList()
    ..sort();

  int get nbCles => _valeurs.length;

  void viderJournal() => journal.clear();
}

// ignore: library_private_types_in_public_api
late _Espion store;

/// Installe un espion NEUF et vide le cache statique de SharedPreferences.
/// Aucune donnée héritée d'un test précédent ne peut subsister.
void _installerStore() {
  store = _Espion();
  SharedPreferencesStorePlatform.instance = store;
  SharedPreferences.resetStatic();
}

// ───────────────────────────────────────────────────────────────────────────
//  Dates et clés CALCULÉES, jamais figées (même règle que A-3 / v26).
//  Une date figée finirait par dépasser `_maxPronosticsAge` (90 jours) et
//  `_purgerVieuxPronostics()` fausserait les témoins.
// ───────────────────────────────────────────────────────────────────────────
DateTime get _jourRef {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

String _ddmmyyyy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

String _courseKey(int r, int c, DateTime d) =>
    'R${r}C${c}_${_ddmmyyyy(d)}';

String _cleElo(String nom, String discipline) {
  final nomNorm = nom.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
  return '$nomNorm|${EloService.normaliserDiscipline(discipline)}';
}

// ───────────────────────────────────────────────────────────────────────────
//  Les 15 clés `_keysIA` — recopiées à l'identique de backup_service.dart:154.
//  Elles servent de périmètre MESURÉ, jamais supposé.
// ───────────────────────────────────────────────────────────────────────────
const List<String> _clesIA = <String>[
  'ia_pronostics_v2',
  'ia_pronostics_v2_gz',
  'ia_poids_v3',
  'ia_journal_v2',
  'ia_rapports_v1',
  'ia_bilans_semaine_v1',
  'ia_bilans_mois_v1',
  'ia_derniere_analyse_v1',
  'ia_stats_types_v1',
  'ia_precision_v2',
  'ia_stats_labels_v1',
  'ia_seuils_v1',
  'ia_premium_historique_v1',
  'ia_premium_du_jour_v1',
  'premium_widgets_selection_jour_v1',
];

/// Les 5 clés ELO/Cote — `_keysELO`, backup_service.dart:177.
const List<String> _clesELO = <String>[
  'elo_ratings_v2',
  'elo_ratings_v2_ts',
  'elo_ratings_v1',
  'cote_tracker_mouvements_v1',
  'cote_mouvements_live_v1',
];

/// Les 107 clés de `_toutesLesCles` (backup_service.dart:389), recopiées
/// groupe par groupe à l'identique : IA 15 + ELO 5 + configIA 34 + paris 1
/// + alertes 12 + profil 5 + widget 23 + laboIA 1 + auditCache 1
/// + grosParis 9 + notifications 1 = 107.
const List<String> _clesToutes = <String>[
  // _keysIA (15)
  'ia_pronostics_v2',
  'ia_pronostics_v2_gz',
  'ia_poids_v3',
  'ia_journal_v2',
  'ia_rapports_v1',
  'ia_bilans_semaine_v1',
  'ia_bilans_mois_v1',
  'ia_derniere_analyse_v1',
  'ia_stats_types_v1',
  'ia_precision_v2',
  'ia_stats_labels_v1',
  'ia_seuils_v1',
  'ia_premium_historique_v1',
  'ia_premium_du_jour_v1',
  'premium_widgets_selection_jour_v1',
  // _keysELO (5)
  'elo_ratings_v2',
  'elo_ratings_v2_ts',
  'elo_ratings_v1',
  'cote_tracker_mouvements_v1',
  'cote_mouvements_live_v1',
  // _keysConfigIA (34)
  'fusion_poids_confiance',
  'fusion_poids_gain',
  'fusion_poids_risque',
  'fusion_seuil_min',
  'bt_mise',
  'bt_jours',
  'bt_type',
  'bt_confiance_min',
  'bt_discipline',
  'bt_hippodrome',
  'conseils_filtres_types_paris',
  'conseils_filtres_confiance_min',
  'conseils_filtres_hippodromes',
  'conseils_filtres_disciplines',
  'conseils_filtres_tri_mode',
  'conseils_filtres_actifs',
  'ia_prenom',
  'ia_avatar_id',
  'ia_date_installation',
  'ia_bulle_active',
  'ia_derniere_bulle',
  'ia_dernier_message_jour',
  'ia_user_prefs_v1',
  'ia_badges_v1',
  'ia_calendrier_seuils_v1',
  'ia_precision_migrated_v2',
  'ia_precision_migrated_v3',
  'ia_narrative_memory_v1',
  'ia_narrative_daily_cache_v1',
  'elo_orphelins_purges_v1',
  'conseils_inject_pending',
  'ia_stats_filtre_actif_v1',
  'ia_stats_date_debut_v1',
  'ia_stats_date_fin_v1',
  // _keysParis (1)
  'user_predictions_v2',
  // _keysAlertes (12)
  'alert_config_v2',
  'alert_history_v1',
  'tracked_courses_v1',
  'alert_sent_ids_v1',
  'alert_resultats_verifies_v1',
  'hippique_favorites_v1',
  'conseil_ia_notifies_v1',
  'conseil_ia_notifies_v1_date',
  'conseil_ia_resume_date',
  'alert_cote_chute_notifies_v1',
  'data_refresh_resume_hebdo_date',
  'alerte_sommeil_v1',
  // _keysProfil (5)
  'profil_nom',
  'profil_gmail',
  'chevaux_suivis_v1',
  'bankroll_capital_v1',
  'ia_derniere_analyse_heure_v1',
  // _keysWidget (23)
  'widget_course_name',
  'widget_horse_name',
  'widget_horse_num',
  'widget_confiance',
  'widget_gain',
  'widget_hippodrome',
  'widget_heure',
  'widget_nb_courses',
  'widget_updated_at',
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
  'widget_nb_criteres',
  'widget_forme',
  // _keysLaboIA (1)
  'simulation_candidates_v1',
  // _keysAuditCache (1)
  'ia_audit_cache_v1',
  // _keysGrosParis (9)
  'ia_quasi_gros_paris_v1',
  'ia_gros_paris_resultats_v1',
  'pronostic_resultats_repository_v2',
  'home_best_bet_snapshot_v2',
  'home_best_bet_snapshot_date_v2',
  'ia_migration_gros_paris_desordre_v1_done',
  'ia_migration_gros_paris_stats_v2_done',
  'ia_migration_gros_paris_types_derives_v1_done',
  'ia_migration_suite_ia_classique_v1_done',
  // _keysNotificationsEnAttente (1) — double préfixe VOULU et documenté
  // (backup_service.dart:359-363) : la clé native devient
  // `flutter.flutter.hippique_pending_notifs`.
  'flutter.hippique_pending_notifs',
];

// ───────────────────────────────────────────────────────────────────────────
//  Valeurs d'usine, lues à la source et non recopiées à la main :
//    • poids      → `IaPoidsAdaptatifs.defaut()`  (ia_memory_models.dart:854)
//    • seuils     → `SeuilsConfianceAdaptatifs()` (ia_memory_service.dart:7500)
//    • calibration→ 50.0 puis `clamp(10, 90)`
//  On les matérialise une fois pour que les assertions comparent des SNAPSHOTS.
// ───────────────────────────────────────────────────────────────────────────
Map<String, dynamic> get _poidsUsine => IaPoidsAdaptatifs.defaut().toJson();

Map<String, dynamic> get _seuilsUsine => SeuilsConfianceAdaptatifs().toJson();

// ───────────────────────────────────────────────────────────────────────────
//  Jeux de données NON TRIVIAUX et TOUS DISTINCTS
//  Aucune valeur n'est un défaut : toute perte ou substitution est visible.
// ───────────────────────────────────────────────────────────────────────────

/// Poids portés par la SAUVEGARDE (état « distant »).
Map<String, dynamic> _poidsBackup() {
  final p = IaPoidsAdaptatifs.defaut();
  p.nbMisesAJour = 251;
  p.calibrationScore = 17.5;
  p.forme = 0.2813;
  p.gains = 0.1177;
  p.record = 0.0931;
  p.cote = 0.0743;
  p.mouvCote = 0.0827;
  p.placeDepart = 0.0257;
  p.dernierGradient = {'forme': 0.0083, 'elo': -0.0041, 'terrain': 0.0019};
  p.poidsIndices = PoidsIndices(
      poidsCriteres: 0.3157, poidsConfiance: 0.4021, poidsReussite: 0.2822);
  p.correlations = {'forme|cote': 0.3719, 'elo|distSpec': -0.2283};
  p.poidsParDiscipline['PLAT'] = {
    'forme': 0.26,
    'gains': 0.12,
    'record': 0.09,
    'cote': 0.07,
    'constance': 0.10,
    'victoires': 0.04,
    'discipline': 0.02,
    'distSpec': 0.09,
    'jockey': 0.07,
    'repos': 0.03,
    'hippo': 0.04,
    'entraineur': 0.04,
    'elo': 0.05,
    'terrain': 0.05,
    'divergence': 0.03,
    'poidsRel': 0.03,
    'progression': 0.03,
    'mouvCote': 0.08,
    'placeDepart': 0.02,
  };
  return p.toJson();
}

/// Poids portés par l'APPAREIL AVANT la restauration — franchement différents.
Map<String, dynamic> _poidsAppareil() {
  final p = IaPoidsAdaptatifs.defaut();
  p.nbMisesAJour = 3;
  p.calibrationScore = 88.75;
  p.forme = 0.5123;
  p.gains = 0.2109;
  p.elo = 0.0111;
  p.dernierGradient = {'constance': -0.0217};
  p.poidsIndices = PoidsIndices(
      poidsCriteres: 0.5231, poidsConfiance: 0.2103, poidsReussite: 0.2666);
  p.correlations = {'record|hippo': 0.6125};
  p.poidsParDiscipline['OBSTACLE'] = {'forme': 0.40, 'gains': 0.11};
  return p.toJson();
}

/// Seuils portés par la SAUVEGARDE.
SeuilsConfianceAdaptatifs _seuilsBackup() => SeuilsConfianceAdaptatifs(
      seuilSimpleGagnant: 71.25,
      seuilGagnantPlace: 46.875,
      seuilSimplePlace: 58.5,
      seuilCoupleGagnant: 82.125,
      seuilCouplePlace: 63.75,
      seuilTierce: 29.375,
      seuilQuarte: 88.5,
      seuilQuinte: 0.0,
    );

/// Seuils portés par l'APPAREIL AVANT la restauration.
SeuilsConfianceAdaptatifs _seuilsAppareil() => SeuilsConfianceAdaptatifs(
      seuilSimpleGagnant: 90.5,
      seuilGagnantPlace: 40.25,
      seuilSimplePlace: 77.125,
      seuilCoupleGagnant: 61.875,
      seuilCouplePlace: 48.5,
      seuilTierce: 52.25,
      seuilQuarte: 69.375,
      seuilQuinte: 0.0,
    );

/// 19 critères tous distincts et non neutres.
ScoresCriteres _criteres({double decalage = 0.0}) => ScoresCriteres(
      forme: 71.5 + decalage,
      gains: 38.25 + decalage,
      record: 83.75 + decalage,
      cote: 24.5 + decalage,
      constance: 61.125 + decalage,
      victoires: 42.875 + decalage,
      discipline: 55.0 + decalage,
      distSpec: 49.5 + decalage,
      jockey: 68.25 + decalage,
      repos: 33.75 + decalage,
      hippo: 57.5 + decalage,
      entraineur: 46.625 + decalage,
      elo: 74.25 + decalage,
      terrain: 41.5 + decalage,
      divergence: 63.875 + decalage,
      poidsRel: 52.25 + decalage,
      progression: 59.125 + decalage,
      mouvCote: 36.5 + decalage,
      placeDepart: 67.25 + decalage,
    );

/// Pronostic complet, daté relativement à aujourd'hui.
IaPronostic _pronostic({
  required String courseKey,
  required DateTime date,
  bool avecResultat = false,
  int nbChevaux = 4,
  double decalage = 0.0,
}) {
  final scores = <String, double>{};
  final criteres = <String, ScoresCriteres>{};
  for (var i = 1; i <= nbChevaux; i++) {
    scores['$i'] = 94.0 - i * 8.25 - decalage;
    criteres['$i'] = _criteres(decalage: i.toDouble() + decalage);
  }
  return IaPronostic(
    courseKey: courseKey,
    nomCourse: 'Prix A4 $courseKey',
    hippodrome: 'VINCENNES',
    discipline: 'Trot Attelé',
    datePronostic: date.add(const Duration(hours: 15)),
    scoresIA: scores,
    scoresCriteres: criteres,
    varianceScores: 137.5 + decalage,
    arriveeReelle: avecResultat ? [2, 1, 3, 4] : null,
    dateResultat: avecResultat ? date.add(const Duration(hours: 17)) : null,
    resultatsReels: avecResultat,
    rangFavoriIaDansArrivee: avecResultat ? 2 : null,
    nbTop3DansArriveeReelle: avecResultat ? 3 : null,
    nbTop5DansArriveeReelle: avecResultat ? 4 : null,
    scorePerformance: avecResultat ? 72.375 : null,
    confiancePredite: 86.25,
    typePariConseille: avecResultat ? 'Quinté+' : 'Tiercé',
    tauxReussiteAuMoment: 41.125,
    precisionIA: 64.875,
    favoriIaNom: 'CHEVAL UN',
    coteFavoriPmu: 4.65,
    cotesPmuParNumero: const {'1': 4.65, '2': 7.9, '3': 13.2, '4': 22.5},
  );
}

JournalEntree _entreeJournal(int i, String methode) => JournalEntree(
      date: _jourRef.subtract(Duration(days: 30 - i)),
      nomCourse: 'Prix Journal A4 $i',
      discipline: 'Trot Attelé',
      nbCoursesAnalysees: 14 + i,
      diagnostic: 'Diagnostic A4-$i (methode=$methode)',
      avant: {'forme': 0.25, 'elo': 0.05},
      apres: {'forme': 0.2500 + i * 0.0025, 'elo': 0.05 - i * 0.0025},
      scorePerf: 62.5 + i,
      methode: methode,
    );

StatsPrecisionParType _precision(String type, int nb, int bons) {
  final s = StatsPrecisionParType(typePari: type);
  s.ajouterJournee(_jourRef.subtract(const Duration(days: 3)), nb, bons,
      ordre: 1, desordre: 1);
  return s;
}

StatsParLabel _label(String lb, int nb, int t1, int t3, int t5) =>
    StatsParLabel(label: lb, nbTotal: nb, nbTop1: t1, nbTop3: t3, nbTop5: t5)
      ..historique.add({'d': _jourRef.toIso8601String().substring(0, 10),
        'nb': nb, 't1': t1, 't3': t3, 't5': t5});

/// 'YYYY-MM-DD' — même format que `IaMemoryService._dateKey()` (l.6452) et que
/// les clés d'historique premium.
String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Rapport journalier aux valeurs TOUTES non triviales (aucun champ à 0).
RapportJournalier _rapportJournalier() => RapportJournalier(
      date: _jourRef,
      nbCoursesAnalysees: 7,
      nbAvecResultat: 5,
      nbPronosticsAjoutes: 7,
      favoriGagnant: 2,
      favoriTop3: 4,
      favoriTop5: 5,
      top3Correct2sur3: 3,
      top5Correct4sur5: 4,
      scoreMoyenJour: 61.375,
      parDiscipline: const <StatsDisciplineJour>[
        StatsDisciplineJour(
          discipline: 'Trot Attelé',
          nbCourses: 4,
          favoriGagnant: 1,
          favoriTop3: 3,
          favoriTop5: 4,
          scoreMoyen: 58.25,
        ),
        StatsDisciplineJour(
          discipline: 'Plat',
          nbCourses: 3,
          favoriGagnant: 1,
          favoriTop3: 1,
          favoriTop5: 1,
          scoreMoyen: 64.5,
        ),
      ],
      nbMisesAJourPoids: 11,
      poidsApres: const <String, double>{'forme': 0.2813, 'elo': 0.0512},
      nbCoursesEchouees: 2,
      noteJournee: 'Bonne',
      heureAnalyse: _jourRef.add(const Duration(hours: 17, minutes: 42)),
    );

/// Bilan hebdomadaire non vide, avec un rapport sérialisé réel.
BilanSemaine _bilanSemaine() => BilanSemaine(
      lundi: _jourRef.subtract(const Duration(days: 6)),
      dimanche: _jourRef,
      rapportsJson: <String>[jsonEncode(_rapportJournalier().toJson())],
      totalCourses: 5,
      totalResultats: 4,
      totalGagnant: 2,
      totalTop3: 3,
      scoreMoyen: 59.875,
      meilleureDisc: 'Plat',
      meilleurTaux: 66.75,
    );

/// Bilan mensuel contenant le bilan hebdomadaire ci-dessus.
BilanMois _bilanMois() => BilanMois(
      annee: _jourRef.year,
      mois: _jourRef.month,
      semaines: <BilanSemaine>[_bilanSemaine()],
      totalCourses: 5,
      totalResultats: 4,
      totalGagnant: 2,
      totalTop3: 3,
      scoreMoyen: 59.875,
      meilleureDisc: 'Plat',
      meilleurTaux: 66.75,
    );

// ───────────────────────────────────────────────────────────────────────────
//  SNAPSHOTS — toujours via `toJson()` + `jsonEncode`.
//  Les getters `poids` et `seuilsConfiance` rendent des RÉFÉRENCES VIVANTES :
//  les comparer directement comparerait le même objet à lui-même.
// ───────────────────────────────────────────────────────────────────────────
String _enc(Object? v) {
  if (v == null) return 'null';
  try {
    return jsonEncode(v);
  } catch (_) {
    return v.toString();
  }
}

/// Photographie complète de l'état IA observé : mémoire ET stockage.
class _Etat {
  _Etat({
    required this.poids,
    required this.seuils,
    required this.elo,
    required this.journal,
    required this.pronostics,
    required this.rapports,
    required this.precisionParType,
    required this.statsLabels,
    required this.statsTypes,
    required this.clesIADisque,
    required this.clesELODisque,
    required this.disqueService,
    required this.horodatageElo,
  });

  final String poids;
  final String seuils;
  final String elo;
  final String journal;
  final String pronostics;
  final String rapports;
  final String precisionParType;
  final String statsLabels;
  final String statsTypes;
  final String clesIADisque;
  final String clesELODisque;
  final String disqueService;

  /// Valeur brute de `elo_ratings_v2_ts`. Mesurée à part car elle est
  /// réécrite à CHAQUE `_sauvegarder()` ELO (horodatage).
  final String horodatageElo;

  static _Etat prendre() {
    final svc = IaMemoryService.instance;

    // Journal : `journal` est rendu INVERSÉ (plus récent d'abord). On trie sur
    // le contenu sérialisé pour que l'ordre de restitution ne soit pas un
    // facteur de faux positif.
    final journalTrie = svc.journal.map((j) => _enc(j.toJson())).toList()
      ..sort();
    final pronosticsTries =
        svc.pronostics.map((p) => _enc(p.toJson())).toList()..sort();
    final rapportsTries = svc.rapports.map((r) => _enc(r.toJson())).toList()
      ..sort();
    final precisionTriee = svc.precisionParType
        .map((p) => _enc(p.toJson()))
        .toList()
      ..sort();
    // Getters publics réels : `statsParLabel` (l.969) et `statsParType` (l.276).
    final labelsTries = svc.statsParLabel
        .map((l) => _enc(l.toJson()))
        .toList()
      ..sort();
    final typesTries = svc.statsParType
        .map((t) => _enc(t.toJson()))
        .toList()
      ..sort();

    return _Etat(
      poids: _enc(svc.poids.toJson()),
      seuils: _enc(svc.seuilsConfiance.toJson()),
      elo: _enc(EloService.instance.exporterPourBackup()),
      journal: _enc(journalTrie),
      pronostics: _enc(pronosticsTries),
      rapports: _enc(rapportsTries),
      precisionParType: _enc(precisionTriee),
      statsLabels: _enc(labelsTries),
      statsTypes: _enc(typesTries),
      clesIADisque: _enc(
          _clesIA.where(store.contient).toList()..sort()),
      clesELODisque: _enc(
          _clesELO.where(store.contient).toList()..sort()),
      disqueService: _enc(<String, String>{
        // `elo_ratings_v2_ts` est EXCLU de cette photographie : c'est un
        // HORODATAGE (`_executerSauvegarde`, elo_service.dart:192 :
        // `setInt(_prefsKeyTs, DateTime.now().millisecondsSinceEpoch)`),
        // donc structurellement différent à chaque écriture. Il est mesuré
        // à part dans `horodatageElo`, jamais ignoré.
        for (final k in <String>[..._clesIA, ..._clesELO])
          if (k != 'elo_ratings_v2_ts' && store.contient(k))
            k: _enc(store.brut(k)),
      }),
      horodatageElo: _enc(store.contient('elo_ratings_v2_ts')
          ? store.brut('elo_ratings_v2_ts')
          : null),
    );
  }

  /// Liste des champs qui DIFFÈRENT entre deux états, avec leur valeur.
  List<String> differences(_Etat apres) {
    final ecarts = <String>[];
    void comparer(String nom, String a, String b) {
      if (a != b) ecarts.add('$nom :\n  avant = $a\n  apres = $b');
    }

    comparer('poids', poids, apres.poids);
    comparer('seuils', seuils, apres.seuils);
    comparer('elo', elo, apres.elo);
    comparer('journal', journal, apres.journal);
    comparer('pronostics', pronostics, apres.pronostics);
    comparer('rapports', rapports, apres.rapports);
    comparer('precisionParType', precisionParType, apres.precisionParType);
    comparer('statsLabels', statsLabels, apres.statsLabels);
    comparer('statsTypes', statsTypes, apres.statsTypes);
    comparer('clesIADisque', clesIADisque, apres.clesIADisque);
    comparer('clesELODisque', clesELODisque, apres.clesELODisque);
    comparer('disqueService', disqueService, apres.disqueService);
    // `horodatageElo` n'est PAS comparé : c'est un `DateTime.now()` réécrit à
    // chaque `_sauvegarder()`. Il est affiché par `rapport()` pour rester
    // visible sans produire de faux positif.
    return ecarts;
  }

  String rapport(String titre, _Etat apres) {
    final d = differences(apres);
    final horodatage = horodatageElo == apres.horodatageElo
        ? 'elo_ratings_v2_ts : inchangé ($horodatageElo)'
        : 'elo_ratings_v2_ts : RÉÉCRIT (horodatage ÉLO) '
            '$horodatageElo → ${apres.horodatageElo}';
    if (d.isEmpty) {
      return '[$titre] AUCUNE différence sémantique (12 champs comparés) | '
          '$horodatage';
    }
    return '[$titre] ${d.length} champ(s) modifié(s) :\n${d.join('\n')}\n'
        '  $horodatage';
  }
}

// ───────────────────────────────────────────────────────────────────────────
//  Amorçage : écritures RÉELLES via l'API SharedPreferences (le cache et
//  l'espion restent donc synchronisés — aucune manipulation du Map interne).
// ───────────────────────────────────────────────────────────────────────────
/// Sème un état IA **COMPLET et NON TRIVIAL** sur le disque.
///
/// ⚠️ CONTRAT DE TYPE, mesuré et non supposé : `_load()`
///    (ia_memory_service.dart:2225-2382) lit CHAQUE clé avec un type précis.
///    `ia_poids_v3` avec une valeur non décodable fait lever `json.decode`
///    HORS du `try` local (l.2227) → le `catch` global (l.2385) avale
///    l'exception et `_load()` AVORTE **après** que `recharger()` a vidé la
///    RAM (l.2193). Toute clé IA doit donc être semée ici avec son type réel ;
///    un `setString` de convenance sur ces clés rend la RAM vide à la mesure.
///
/// Ce helper couvre les 15 clés `_keysIA` sauf les deux formats de pronostics
/// (mutuellement exclusifs, gérés par l'appelant) — soit 13 clés.
Future<SharedPreferences> _amorcer({
  required Map<String, dynamic> poids,
  required SeuilsConfianceAdaptatifs seuils,
  required List<IaPronostic> pronostics,
  required List<JournalEntree> journal,
  required Map<String, StatsPrecisionParType> precision,
  required Map<String, StatsParLabel> labels,
  /// Sème AUSSI rapports / bilans / premium en `StringList` JSON réels.
  /// Désactivé par défaut pour ne PAS modifier l'état monté par T6/T7-A,
  /// dont les assertions ont été écrites et validées sur l'ensemble initial.
  /// T7-B l'active : c'est lui qui a besoin de témoins non vacuitaires sur les
  /// 13 champs RAM vidés par `executerResetComplet`.
  bool contenuEtendu = false,
}) async {
  final prefs = await SharedPreferences.getInstance();
  // ✅ Sans ce flag, `_load()` exécuterait la migration
  //    `_recalculerPrecisionParTypeDepuisPronostics()` ET une écriture.
  await prefs.setBool('ia_precision_migrated_v3', true);
  await prefs.setString('ia_poids_v3', jsonEncode(poids));
  await prefs.setString('ia_seuils_v1', jsonEncode(seuils.toJson()));
  await prefs.setStringList(
      'ia_pronostics_v2', pronostics.map((p) => jsonEncode(p.toJson())).toList());
  await prefs.setStringList(
      'ia_journal_v2', journal.map((j) => jsonEncode(j.toJson())).toList());
  await prefs.setString('ia_precision_v2',
      jsonEncode(precision.map((k, v) => MapEntry(k, v.toJson()))));
  await prefs.setString('ia_stats_labels_v1',
      jsonEncode(labels.map((k, v) => MapEntry(k, v.toJson()))));
  await prefs.setStringList('ia_stats_types_v1', <String>[
    jsonEncode({'tp': 'Quinté+', 'nj': 24, 'ng': 9, 'np': 15, 'gn': -4.5}),
  ]);
  // ── Rapports / bilans : `getStringList` côté `_load()` (l.2278/2288/2296).
  //    Le `fromJson` est TOLÉRANT (défauts à 0 / listes vides), donc une chaîne
  //    JSON valide suffit à produire une entrée NON VIDE mesurable.
  if (contenuEtendu) {
    await prefs.setStringList('ia_rapports_v1', <String>[
      jsonEncode(_rapportJournalier().toJson()),
    ]);
    await prefs.setStringList('ia_bilans_semaine_v1', <String>[
      jsonEncode(_bilanSemaine().toJson()),
    ]);
    await prefs.setStringList('ia_bilans_mois_v1', <String>[
      jsonEncode(_bilanMois().toJson()),
    ]);
    // ── Champs « String » simples.
    await prefs.setString(
        'ia_derniere_analyse_v1', _jourRef.toIso8601String());
    // `_chargerPremiumHistorique()` (l.6717) attend `{'entries': {dateKey: [...]}}`.
    // L'historique est VIDE si les entrées sont absentes → on sème une entrée
    // réelle pour que `premiumsPourDate()` soit un témoin non vacuitaire.
    await prefs.setString(
        'ia_premium_historique_v1',
        jsonEncode(<String, dynamic>{
          'entries': <String, dynamic>{
            _dateKey(_jourRef): <Map<String, dynamic>>[
              const PremiumPronosticDuJour(
                courseKey: 'R1C1_A4',
                typePari: 'Simple Gagnant',
                numeros: <String>['3', '7'],
                sourceWidget: 'conseilJour',
              ).toJson(),
            ],
          },
        }));
    // `_chargerPremiumDuJour()` (l.6703) attend '<yyyy-MM-dd>|<k1,k2>'.
    await prefs.setString('ia_premium_du_jour_v1',
        '${_dateKey(_jourRef)}|${_courseKey(1, 1, _jourRef)}');
    // Bornes réelles des 5 widgets premium (JSON quelconque accepté : aucun
    // `fromJson` n'est appelé au chargement).
    await prefs.setString('premium_widgets_selection_jour_v1',
        jsonEncode(<String, dynamic>{
          _dateKey(_jourRef): <String, dynamic>{
            'conseilJour': <String, dynamic>{
              'courseKey': _courseKey(1, 1, _jourRef),
              'typePari': 'Simple Gagnant',
              'numeros': <String>['3', '7'],
              'sourceWidget': 'conseilJour',
            },
          },
        }));
  }
  return prefs;
}

/// Installe un jeu d'ELO dans le service PUIS le persiste sur le disque.
Future<void> _amorcerElo(Map<String, double> ratings) async {
  final payload = <String, dynamic>{};
  ratings.forEach((cle, rating) {
    final nom = cle.split('|').first;
    payload[cle] = EloScore(
      nomCheval: nom,
      rating: rating,
      nbCourses: 19,
      variationMois: 14.5,
    ).toJson();
  });
  await EloService.instance.importerDepuisBackup(payload);
}

// ═══════════════════════════════════════════════════════════════════════════
//  T6 — RESTAURATION DE SAUVEGARDE
//
//  Contrat vérifié, lu dans le code AVANT d'être testé :
//
//  ① `exporterDonnees()` (backup_service.dart:868) → `_collecterDonnees()`
//     (l.433). Chaque clé est enveloppée `{'type':…, 'value':…}` par
//     `_lireEntree()` (l.411). Les poids/seuils partent donc en `String`.
//
//  ② `importerDepuisFichier()` (l.961) → `_restaurerDepuisJson()` (l.991).
//     • `_restaurerGroupe()` (l.658) écrit CLÉ PAR CLÉ, valeur par valeur.
//       Il NE SUPPRIME PAS une clé locale ABSENTE de la sauvegarde.
//     • Les pronostics passent à part (`_restaurerPronostics`, l.847) : UN
//       SEUL format est retenu (JSON ou gzip), l'autre est purgé.
//     • `resultatsGrosParis` présent → remplace la liste entière.
//     • `archiveIA` / `arriveesOfficielles` → FUSION (jamais destructrice).
//     • `grosParis` ABSENT → remis à vide (contrat de rétrocompatibilité).
//     • Fin : `IaMemoryService.instance.recharger()` (l.1290) PUIS
//       `AlertService.instance.recharger()` (l.1294).
//
//  ③ Aucun de ces chemins n'appelle `_apprendreParGradient`,
//     `_apprendreReglesBase`, `_apprendreParDiscipline` ni
//     `_mettreAJourCalibration`. C'est MESURÉ ici, pas affirmé.
// ═══════════════════════════════════════════════════════════════════════════
void main() {
  late Directory tmpDir;

  setUpAll(() {
    tmpDir = Directory.systemTemp.createTempSync('a4_lot2_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir.path);
  });

  tearDownAll(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T6 — RESTAURATION AVEC DES PARAMÈTRES IA VOLONTAIREMENT DIFFÉRENTS
  // ═════════════════════════════════════════════════════════════════════════
  test('A4-T6 — restauration exacte d\'une sauvegarde aux paramètres différents',
      () async {
    final jour = _jourRef;
    final jour2 = jour.subtract(const Duration(days: 1));

    // ── Phase 1 : l'APPAREIL, avec ses propres paramètres (état A) ─────────
    _installerStore();
    final poidsAppareil = _poidsAppareil();
    final seuilsAppareil = _seuilsAppareil();
    final pronosticsAppareil = <IaPronostic>[
      _pronostic(courseKey: _courseKey(9, 9, jour), date: jour),
    ];
    await _amorcer(
      poids: poidsAppareil,
      seuils: seuilsAppareil,
      pronostics: pronosticsAppareil,
      journal: <JournalEntree>[_entreeJournal(1, 'regles')],
      precision: <String, StatsPrecisionParType>{
        'Simple Gagnant': _precision('Simple Gagnant', 5, 1),
      },
      labels: <String, StatsParLabel>{'LABEL APPAREIL': _label('LABEL APPAREIL', 5, 1, 2, 3)},
    );
    await _amorcerElo(<String, double>{
      _cleElo('OURAGAN DE TEST', 'Trot Attelé'): 1712.5,
    });
    // Clé LOCALE qui n'existe PAS dans la sauvegarde → doit survivre
    // (`_restaurerGroupe` ne supprime pas les clés absentes du fichier).
    (await SharedPreferences.getInstance())
        .setString('profil_nom', 'PROFIL LOCAL APPAREIL');

    await IaMemoryService.instance.recharger();

    // Témoin de non-vacuité : l'appareil porte bien des valeurs NON d'usine.
    expect(IaMemoryService.instance.poids.nbMisesAJour, 3,
        reason: 'T6 témoin : l\'appareil doit partir d\'un état non trivial');
    expect(IaMemoryService.instance.poids.forme, 0.5123,
        reason: 'T6 témoin : poids `forme` de l\'appareil');
    expect(IaMemoryService.instance.seuilsConfiance.seuilSimpleGagnant, 90.5,
        reason: 'T6 témoin : seuilSimpleGagnant de l\'appareil');
    expect(_Etat.prendre().poids, isNot(_enc(_poidsUsine)),
        reason: 'T6 témoin : l\'appareil n\'est PAS aux valeurs d\'usine');

    // ── Phase 2 : la SAUVEGARDE, aux paramètres FRANCHEMENT différents ────
    final poidsBackup = _poidsBackup();
    final seuilsBackup = _seuilsBackup();
    final pronosticsBackup = <IaPronostic>[
      _pronostic(courseKey: _courseKey(1, 2, jour), date: jour,
          avecResultat: true),
      _pronostic(courseKey: _courseKey(2, 4, jour2), date: jour2),
    ];
    final journalBackup = <JournalEntree>[
      _entreeJournal(3, 'gradient'),
      _entreeJournal(4, 'gradient'),
      _entreeJournal(5, 'discipline'),
    ];
    final precisionBackup = <String, StatsPrecisionParType>{
      'Quinté+': _precision('Quinté+', 11, 5),
      'Tiercé': _precision('Tiercé', 7, 2),
    };
    final labelsBackup = <String, StatsParLabel>{
      'FAVORI IA BACKUP': _label('FAVORI IA BACKUP', 11, 5, 8, 9),
    };

    // L'appareil reçoit le contenu de la sauvegarde : c'est ainsi que le
    // fichier est produit sur un AUTRE appareil, avec d'AUTRES paramètres.
    await _amorcer(
      poids: poidsBackup,
      seuils: seuilsBackup,
      pronostics: pronosticsBackup,
      journal: journalBackup,
      precision: precisionBackup,
      labels: labelsBackup,
    );
    await _amorcerElo(<String, double>{
      _cleElo('OURAGAN DE TEST', 'Trot Attelé'): 1712.5, // identique (inchangé)
      _cleElo('TORNADE DU TEST', 'Plat'): 1438.75,        // nouveau
    });
    await IaMemoryService.instance.recharger();

    // Export réel sur le disque.
    final export = await BackupService.instance.exporterDonnees();
    expect(export.succes, isTrue,
        reason: 'T6 : l\'export de sauvegarde doit réussir '
            '(${export.erreur ?? "sans erreur"})');
    final fichier = File(export.filePath!);
    expect(await fichier.exists(), isTrue,
        reason: 'T6 : le fichier de sauvegarde doit exister sur le disque');
    final contenuJson =
        json.decode(await fichier.readAsString()) as Map<String, dynamic>;
    expect(contenuJson['appName'], 'Pronostic Hippique',
        reason: 'T6 : sceau applicatif exigé par _restaurerDepuisJson l.995');
    expect(contenuJson['version'], '9.1',
        reason: 'T6 : _backupVersion vaut 9.1 (backup_service.dart:144)');

    // ── Phase 3 : l'appareil est remis dans son état A d'origine ──────────
    _installerStore();
    final poidsRetourA = _poidsAppareil();
    await _amorcer(
      poids: poidsRetourA,
      seuils: _seuilsAppareil(),
      pronostics: pronosticsAppareil,
      journal: <JournalEntree>[_entreeJournal(1, 'regles')],
      precision: <String, StatsPrecisionParType>{
        'Simple Gagnant': _precision('Simple Gagnant', 5, 1),
      },
      labels: <String, StatsParLabel>{'LABEL APPAREIL': _label('LABEL APPAREIL', 5, 1, 2, 3)},
    );
    await _amorcerElo(<String, double>{
      _cleElo('OURAGAN DE TEST', 'Trot Attelé'): 1712.5,
    });
    (await SharedPreferences.getInstance())
        .setString('profil_nom', 'PROFIL LOCAL APPAREIL');
    await IaMemoryService.instance.recharger();

    final avant = _Etat.prendre();
    expect(avant.poids, isNot(_enc(poidsBackup)),
        reason: 'T6 témoin : AVANT restauration, l\'appareil n\'a pas les '
            'poids de la sauvegarde');
    expect(avant.seuils, isNot(_enc(seuilsBackup.toJson())),
        reason: 'T6 témoin : AVANT restauration, l\'appareil n\'a pas les '
            'seuils de la sauvegarde');
    expect(IaMemoryService.instance.pronostics.length, 1,
        reason: 'T6 témoin : un seul pronostic local avant restauration');

    // ── Phase 4 : RESTAURATION par la vraie API publique ──────────────────
    store.viderJournal();
    FilePicker.platform = _FakeFilePicker(FilePickerResult([
      PlatformFile(
        name: export.fileName!,
        size: export.tailleOctets,
        bytes: Uint8List.fromList(await fichier.readAsBytes()),
      ),
    ]));

    final import = await BackupService.instance.importerDepuisFichier();
    expect(import.succes, isTrue,
        reason: 'T6 : la restauration doit réussir '
            '(${import.erreur ?? "sans erreur"})');
    expect(import.nbPronosticsIA, 2,
        reason: 'T6 : la sauvegarde contient 2 pronostics');

    final apres = _Etat.prendre();

    // ── ① Restauration EXACTE des poids et seuils prévus ─────────────────
    expect(apres.poids, _enc(poidsBackup),
        reason: 'T6 : les poids doivent être EXACTEMENT ceux de la sauvegarde');
    expect(apres.seuils, _enc(seuilsBackup.toJson()),
        reason: 'T6 : les seuils doivent être EXACTEMENT ceux de la sauvegarde');
    expect(IaMemoryService.instance.poids.nbMisesAJour, 251,
        reason: 'T6 : compteur de mises à jour restauré tel quel');
    expect(IaMemoryService.instance.poids.calibrationScore, 17.5,
        reason: 'T6 : calibrationScore restauré tel quel');

    // Le registre statique suit `_load()` (ia_memory_service.dart:2353),
    // avec le `clamp(10, 90)` de IaCalibrationRegistry.update (zt_models.dart:22).
    expect(IaCalibrationRegistry.value, 17.5,
        reason: 'T6 : IaCalibrationRegistry resynchronisé sur la valeur '
            'restaurée (17.5 est dans [10, 90], aucun clamp)');

    // ── ② Autres données : conservation ou remplacement selon le contrat ──
    expect(IaMemoryService.instance.pronostics.length, 2,
        reason: 'T6 : les pronostics de la sauvegarde remplacent les locaux');
    expect(
      IaMemoryService.instance.pronostics.map((p) => p.courseKey).toSet(),
      pronosticsBackup.map((p) => p.courseKey).toSet(),
      reason: 'T6 : identité exacte des courses restaurées');
    // Le résidu de l'AUTRE format est purgé (l.860) : jamais deux jeux.
    expect(store.contient('ia_pronostics_v2_gz'), isFalse,
        reason: 'T6 : format gzip purgé après restauration du format JSON');

    expect(IaMemoryService.instance.journal.length, 3,
        reason: 'T6 : le journal de la sauvegarde remplace le journal local');
    expect(
      IaMemoryService.instance.journal.map((j) => j.methode).toList()..sort(),
      <String>['discipline', 'gradient', 'gradient'],
      reason: 'T6 : méthodes du journal restauré',
    );

    expect(IaMemoryService.instance.rapports, isEmpty,
        reason: 'T6 : la sauvegarde ne contient aucun rapport → la clé locale '
            'ABSENTE du fichier est CONSERVÉE telle quelle (elle était vide)');

    // `profil_nom` est ABSENT de la sauvegarde (profil non collecté ici car
    // le groupe `profil` est bien exporté → il est présent). On vérifie donc
    // le contrat réel : la clé est ÉCRITE par la restauration.
    final profilApres =
        (await SharedPreferences.getInstance()).getString('profil_nom');
    expect(profilApres, 'PROFIL LOCAL APPAREIL',
        reason: 'T6 : le profil local est restauré depuis le fichier '
            '(même valeur ici : elle a été exportée depuis cet état)');

    // ── ③ Cohérence MÉMOIRE ↔ STOCKAGE après le `recharger()` final ───────
    final poidsSurDisque = store.brut('ia_poids_v3') as String;
    expect(_enc(json.decode(poidsSurDisque)), apres.poids,
        reason: 'T6 : la MÉMOIRE et le DISQUE portent les mêmes poids');
    final seuilsSurDisque = store.brut('ia_seuils_v1') as String;
    expect(_enc(json.decode(seuilsSurDisque)), apres.seuils,
        reason: 'T6 : la MÉMOIRE et le DISQUE portent les mêmes seuils');

    // ── ④ Aucun apprentissage déclenché par la SEULE restauration ─────────
    // Le compteur de mises à jour est celui de la sauvegarde : s'il avait
    // appris, `_apprendreReglesBase` / `_apprendreParGradient` l'auraient
    // incrémenté (l.4310 / l.4280-4309).
    expect(IaMemoryService.instance.poids.nbMisesAJour, 251,
        reason: 'T6 : `nbMisesAJour` reste 251 — AUCUNE mise à jour de poids '
            'n\'a été ajoutée par la restauration');
    // Le journal compte EXACTEMENT les entrées du fichier : aucune entrée
    // `gradient` / `regles` / `discipline` supplémentaire.
    expect(IaMemoryService.instance.journal.length, journalBackup.length,
        reason: 'T6 : le journal compte exactement les entrées de la '
            'sauvegarde — aucune entrée d\'apprentissage ajoutée');

    // ── ⑤ Cohérence du journal et des compteurs ──────────────────────────
    expect(IaMemoryService.instance.precisionParType.length, 2,
        reason: 'T6 : deux types de pari dans la précision restaurée');
    expect(
      IaMemoryService.instance.precisionParType.map((p) => p.typePari).toSet(),
      <String>{'Quinté+', 'Tiercé'},
      reason: 'T6 : identité des types restaurés');
    expect(IaMemoryService.instance.statsParLabel.length, 1,
        reason: 'T6 : un seul label dans la sauvegarde');
    expect(IaMemoryService.instance.statsParLabel.first.label, 'FAVORI IA BACKUP',
        reason: 'T6 : le label de la sauvegarde remplace celui de l\'appareil');

    // ── ⑥ Aucune mutation ELO injustifiée ────────────────────────────────
    // `importerDepuisBackup` (elo_service.dart:333) fait `clear` puis réinjecte
    // les ratings du fichier, puis `_sauvegarder()`. Le rating commun garde
    // donc sa valeur EXACTE : aucune formule ELO n'est appliquée.
    expect(EloService.instance.getRating('OURAGAN DE TEST',
            discipline: 'Trot Attelé'),
        1712.5,
        reason: 'T6 : rating commun inchangé — aucune formule ELO appliquée');
    expect(EloService.instance.getRating('TORNADE DU TEST', discipline: 'Plat'),
        1438.75,
        reason: 'T6 : rating absent de l\'appareil, présent dans la sauvegarde');
    expect(EloService.instance.nbChevauxSuivis, 2,
        reason: 'T6 : exactement les 2 ratings de la sauvegarde');
    // Le rating de l'appareil ABSENT de la sauvegarde a bien disparu —
    // `importerDepuisBackup` REMPLACE la map, il ne fusionne pas.
    expect(EloService.instance.getRating('INCONNU TOTAL'),
        1500.0,
        reason: 'T6 : un cheval hors sauvegarde retombe sur `_eloDefaut` '
            '(elo_service.dart:29) — la map a bien été REMPLACÉE, pas fusionnée');

    // ── ⑦ Idempotence d'une SECONDE restauration identique ───────────────
    // Le contrat le permet : `_restaurerGroupe` réécrit les mêmes valeurs,
    // `importerDepuisBackup` réinjecte les mêmes ratings, `recharger()`
    // reconstruit la même RAM. On mesure l'état, pas le nombre d'écritures.
    final avantSeconde = _Etat.prendre();
    FilePicker.platform = _FakeFilePicker(FilePickerResult([
      PlatformFile(
        name: export.fileName!,
        size: export.tailleOctets,
        bytes: Uint8List.fromList(await fichier.readAsBytes()),
      ),
    ]));
    final import2 = await BackupService.instance.importerDepuisFichier();
    expect(import2.succes, isTrue,
        reason: 'T6 : la seconde restauration doit réussir');
    final apresSeconde = _Etat.prendre();

    final ecarts = avantSeconde.differences(apresSeconde);
    expect(ecarts, isEmpty,
        reason: 'T6 : une SECONDE restauration identique ne doit RIEN changer '
            '— écarts mesurés : ${avantSeconde.rapport("T6/seconde", apresSeconde)}');
    // ignore: avoid_print
    print(avantSeconde.rapport('T6/idempotence', apresSeconde));
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T7-A — `reinitialiserIA()` : PÉRIMÈTRE MESURÉ, PAS SUPPOSÉ
  //
  //  Lu dans le code (backup_service.dart:1482) : cette méthode se contente de
  //
  //      for (final key in _keysIA) { await prefs.remove(key); }
  //
  //  Elle ne vide AUCUNE RAM, ne touche à AUCUNE autre famille de clés, et
  //  n'appelle aucun service. Son commentaire (l.1477-1481) documente que
  //  l'archive historique est volontairement préservée (décision E4).
  //  On mesure donc les trois conséquences : disque, RAM, et rechargement.
  // ═════════════════════════════════════════════════════════════════════════
  test('A4-T7-A — reinitialiserIA() : 15 clés IA effacées, le reste intact',
      () async {
    final jour = _jourRef;
    _installerStore();

    // ── Préparation : mémoire IA NON triviale + clés extérieures ──────────
    final poids = _poidsBackup();
    final seuils = _seuilsBackup();
    final pronostics = <IaPronostic>[
      _pronostic(courseKey: _courseKey(1, 1, jour), date: jour,
          avecResultat: true),
      _pronostic(courseKey: _courseKey(1, 2, jour), date: jour),
    ];
    await _amorcer(
      poids: poids,
      seuils: seuils,
      pronostics: pronostics,
      journal: <JournalEntree>[
        _entreeJournal(1, 'gradient'),
        _entreeJournal(2, 'gradient'),
      ],
      precision: <String, StatsPrecisionParType>{
        'Quinté+': _precision('Quinté+', 9, 4),
      },
      labels: <String, StatsParLabel>{
        'FAVORI IA': _label('FAVORI IA', 9, 4, 7, 8),
      },
    );
    // Clés IA supplémentaires à valeur non triviale, pour que l'effacement
    // soit démontrable sur CHACUNE des 15 clés (aucune n'est laissée vide).
    // ⚠️ Les TYPES sont ceux que les getters de `_load()` attendent
    // (`getStringList` pour les collections, `getString` pour les scalaires).
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('ia_rapports_v1', <String>['RAPPORT-A4']);
    await prefs.setStringList(
        'ia_bilans_semaine_v1', <String>['BILAN-SEM-A4']);
    await prefs.setStringList('ia_bilans_mois_v1', <String>['BILAN-MOIS-A4']);
    await prefs.setString('ia_derniere_analyse_v1', '2026-01-01T00:00:00.000');
    await prefs.setString('ia_premium_historique_v1', 'PREMIUM-HIST-A4');
    await prefs.setString('ia_premium_du_jour_v1', 'PREMIUM-JOUR-A4');
    await prefs.setString('premium_widgets_selection_jour_v1', 'WIDGETS-A4');

    // Clés EXTÉRIEURES : elles doivent survivre à `reinitialiserIA()`.
    await prefs.setString('profil_nom', 'PROFIL T7-A');
    await prefs.setString('bankroll_capital_v1', '2500.0');
    await prefs.setStringList('user_predictions_v2', <String>['PARI-A4']);
    await prefs.setString('fusion_poids_confiance', '0.4321');
    await prefs.setString('alert_config_v2', 'CONFIG-ALERTE-A4');
    await prefs.setString('widget_course_name', 'WIDGET-COURSE-A4');
    await prefs.setString('simulation_candidates_v1', 'LABO-A4');
    await prefs.setString('ia_audit_cache_v1', 'AUDIT-A4');
    await prefs.setString('ia_quasi_gros_paris_v1', 'GROS-PARIS-A4');

    await _amorcerElo(<String, double>{
      _cleElo('OURAGAN T7A', 'Trot Attelé'): 1621.25,
    });

    // Archive historique ET arrivées officielles : doivent survivre.
    IaArchiveService.instance.enregistrerEviction(
        _pronostic(courseKey: _courseKey(7, 7, jour),
            date: jour, avecResultat: true));
    expect(await IaArchiveService.instance.persisterEnAttente(), isTrue,
        reason: 'T7-A : préparation de l\'archive non confirmée');
    final arrivees = await ArriveeOfficielleService.instance.enregistrer(
        EntreeArrivee(
            courseKey: _courseKey(8, 8, jour),
            rangs: <List<int>>[
              <int>[3],
              <int>[1],
              <int>[2],
            ]));
    expect(arrivees.succes, isTrue,
        reason: 'T7-A : préparation des arrivées officielles non confirmée');

    await IaMemoryService.instance.recharger();

    // ── TÉMOINS DE NON-VACUITÉ : tout est réellement présent AVANT ─────────
    // `ia_pronostics_v2` et `ia_pronostics_v2_gz` sont MUTUELLEMENT EXCLUSIFS
    // par construction : `_save()` n'en écrit qu'UN seul (le gzip seulement
    // au-delà de 20 pronostics). Les exiger tous deux serait un faux témoin.
    // Le contrat réel est donc mesuré sur les 13 autres clés, PLUS l'exigence
    // « exactement un des deux formats est présent ».
    const clesFormat = <String>['ia_pronostics_v2', 'ia_pronostics_v2_gz'];
    final formatsPresents =
        clesFormat.where(store.contient).toList();
    expect(formatsPresents.length, 1,
        reason: 'T7-A témoin : `_save()` ne laisse qu\'UN seul format de '
            'pronostics — présents : $formatsPresents');
    expect(formatsPresents.single, 'ia_pronostics_v2',
        reason: 'T7-A témoin : avec 2 pronostics (< 21), le format retenu est '
            'le JSON non compressé');

    final clesASurveiller =
        _clesIA.where((k) => !clesFormat.contains(k)).toList();
    for (final cle in clesASurveiller) {
      expect(store.contient(cle), isTrue,
          reason: 'T7-A témoin : la clé `$cle` doit être PRÉSENTE avant le '
              'reset, sinon sa disparition ne prouverait rien');
    }
    expect(clesASurveiller.length, 13,
        reason: 'T7-A : 15 clés `_keysIA` − 2 clés de format mutuellement '
            'exclusives = 13 clés surveillées une à une');
    expect(store.nbCles, greaterThan(_clesIA.length),
        reason: 'T7-A témoin : le stockage contient les clés extérieures');
    expect(IaMemoryService.instance.pronostics.length, 2,
        reason: 'T7-A témoin : 2 pronostics en mémoire avant le reset');
    expect(IaMemoryService.instance.poids.nbMisesAJour, 251,
        reason: 'T7-A témoin : compteur de mises à jour non trivial');
    expect(IaArchiveService.instance.nbVersionsArchivees, greaterThan(0),
        reason: 'T7-A témoin : l\'archive contient au moins une version');
    expect(
        await ArriveeOfficielleService.instance.enumererClesSurStockage(),
        isNotEmpty,
        reason: 'T7-A témoin : un shard d\'arrivées existe sur le disque');

    final eloAvant = EloService.instance.getRating('OURAGAN T7A',
        discipline: 'Trot Attelé');
    expect(eloAvant, 1621.25, reason: 'T7-A témoin : ELO non trivial');

    final avant = _Etat.prendre();

    // ── ACTION : la vraie API publique ───────────────────────────────────
    await BackupService.instance.reinitialiserIA();

    // ── ① Les 15 clés IA ont disparu du DISQUE ───────────────────────────
    final survivantesIA =
        _clesIA.where(store.contient).toList();
    expect(survivantesIA, isEmpty,
        reason: 'T7-A : les 15 clés `_keysIA` doivent TOUTES être effacées — '
            'survivantes : $survivantesIA');

    // ── ② Les clés EXTÉRIEURES sont intactes ─────────────────────────────
    final exterieures = <String>[
      'profil_nom',
      'bankroll_capital_v1',
      'user_predictions_v2',
      'fusion_poids_confiance',
      'alert_config_v2',
      'widget_course_name',
      'simulation_candidates_v1',
      'ia_audit_cache_v1',
      'ia_quasi_gros_paris_v1',
    ];
    final disparues = exterieures.where((k) => !store.contient(k)).toList();
    expect(disparues, isEmpty,
        reason: 'T7-A : `reinitialiserIA()` ne doit toucher AUCUNE clé hors '
            '`_keysIA` — clés perdues : $disparues');
    expect((await SharedPreferences.getInstance()).getString('profil_nom'),
        'PROFIL T7-A', reason: 'T7-A : profil conservé, valeur exacte');
    expect(
        (await SharedPreferences.getInstance())
            .getStringList('user_predictions_v2'),
        <String>['PARI-A4'], reason: 'T7-A : paris conservés, valeur exacte');

    // ── ③ Comportement RÉEL de la RAM : elle n'est PAS vidée ─────────────
    // C'est le point le plus important : `reinitialiserIA()` n'appelle aucun
    // service. La mémoire reste donc peuplée alors que ses clés ont disparu.
    final apres = _Etat.prendre();
    expect(apres.poids, avant.poids,
        reason: 'T7-A : la RAM des poids est INCHANGÉE — cette méthode ne la '
            'vide pas (backup_service.dart:1482 ne mute aucun champ)');
    expect(IaMemoryService.instance.pronostics.length, 2,
        reason: 'T7-A : les 2 pronostics restent EN MÉMOIRE');
    expect(IaMemoryService.instance.poids.nbMisesAJour, 251,
        reason: 'T7-A : le compteur reste 251 en RAM');
    expect(IaMemoryService.instance.journal.length, 2,
        reason: 'T7-A : le journal reste en mémoire');
    expect(EloService.instance.getRating('OURAGAN T7A',
            discipline: 'Trot Attelé'),
        1621.25,
        reason: 'T7-A : les ratings ELO restent en RAM');

    // ── ④ Cohérence APRÈS RECHARGEMENT : la RAM se vide, le disque gagne ──
    await IaMemoryService.instance.recharger();
    final apresRechargement = _Etat.prendre();
    expect(IaMemoryService.instance.pronostics, isEmpty,
        reason: 'T7-A : après rechargement, plus aucun pronostic — la source '
            'de vérité est le disque, désormais vide pour les clés IA');
    expect(IaMemoryService.instance.journal, isEmpty,
        reason: 'T7-A : journal vide après rechargement');
    expect(IaMemoryService.instance.rapports, isEmpty,
        reason: 'T7-A : rapports vides après rechargement');
    expect(IaMemoryService.instance.poids.nbMisesAJour, 0,
        reason: 'T7-A : `ia_poids_v3` absente → `IaPoidsAdaptatifs` par défaut '
            'via le constructeur (ia_memory_service.dart:2225-2229 ne fait '
            'rien si la clé est absente, le champ garde `defaut()`)');
    expect(_enc(IaMemoryService.instance.poids.toJson()), _enc(_poidsUsine),
        reason: 'T7-A : les poids reviennent aux valeurs d\'usine APRÈS '
            'rechargement (conséquence du disque effacé, pas d\'un calcul)');
    expect(_enc(IaMemoryService.instance.seuilsConfiance.toJson()),
        _enc(_seuilsUsine),
        reason: 'T7-A : seuils d\'usine après rechargement');
    expect(IaCalibrationRegistry.value, 50.0,
        reason: 'T7-A : registre de calibration resynchronisé sur 50.0 '
            '(`_load` l.2353 avec `calibrationScore` par défaut)');

    // ── ⑤ Archive ET arrivées officielles conservées ─────────────────────
    expect(IaArchiveService.instance.nbVersionsArchivees, greaterThan(0),
        reason: 'T7-A : l\'archive historique N\'EST PAS effacée par '
            '`reinitialiserIA()` (décision E4, commentaire l.1477-1481)');
    expect(store.cles.any((k) => k.startsWith('ia_archive_v1_')), isTrue,
        reason: 'T7-A : des shards d\'archive subsistent sur le disque');
    expect(
        await ArriveeOfficielleService.instance.enumererClesSurStockage(),
        isNotEmpty,
        reason: 'T7-A : les arrivées officielles ne figurent dans AUCUNE liste '
            'de clés effacées — elles survivent');

    // ── ⑥ Aucun apprentissage involontaire ───────────────────────────────
    // Sur le disque, `ia_poids_v3` et `ia_journal_v2` ont disparu : aucune
    // entrée n'a pu être ajoutée. Après rechargement, le compteur est à 0.
    expect(store.contient('ia_poids_v3'), isFalse,
        reason: 'T7-A : aucune réécriture de `ia_poids_v3`');
    expect(store.contient('ia_journal_v2'), isFalse,
        reason: 'T7-A : aucune entrée de journal réécrite');
    expect(apresRechargement.journal, _enc(<String>[]),
        reason: 'T7-A : journal disque ET mémoire vides — aucune méthode '
            '`gradient`/`regles` ajoutée');

    // ignore: avoid_print
    print('[A4-T7-A] 15 clés IA effacées | 9 clés extérieures intactes | '
        'RAM intacte avant rechargement | poids réinitialisés après '
        'rechargement | archive=${IaArchiveService.instance.nbVersionsArchivees} '
        'version(s)');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T7-B — `reinitialiserComplet()` : LE PÉRIMÈTRE RÉEL DES 107 CLÉS
  //
  //  Lu dans le code (backup_service.dart:1496) : quatre barrières imbriquées
  //  (AlertService 1549 → IaMemoryService 1550 → EloService 1575 →
  //  DataRefreshService 1576) encadrent UNE boucle sur `_toutesLesCles` (1578)
  //  dont CHAQUE `remove()` est contrôlé (1581-1582), plus un balayage
  //  dynamique `cache_reunions_*` (1617-1624) et une `StateError` listant les
  //  survivantes (1627-1633).
  //
  //  Les 107 clés sont recopiées à l'identique dans `_clesToutes` ci-dessous.
  //  Chacune reçoit une valeur NON TRIVIALE de son type réel, et sa présence
  //  est VÉRIFIÉE AVANT le reset : « absente avant » ne peut jamais passer
  //  pour « correctement supprimée après ».
  // ═════════════════════════════════════════════════════════════════════════
  test('A4-T7-B — reinitialiserComplet() : 107 clés, RAM d\'usine, archive '
      'et arrivées préservées', () async {
    final jour = _jourRef;
    _installerStore();

    // ── 1) Les services NON-IA d'abord (ils écrivent sur le disque) ──────
    // ⚠️ ORDRE CRITIQUE, mesuré : `_amorcer()` doit venir APRÈS tout appel
    //    susceptible de déclencher un `_save()` IA. Un `recharger()` prématuré
    //    suivi d'un `_save()` resérialise une RAM déjà vidée.
    final prefs = await SharedPreferences.getInstance();

    // Les clés hors périmètre IA, chacune avec une valeur non triviale.
    const clesFormat = <String>['ia_pronostics_v2', 'ia_pronostics_v2_gz'];
    final clesNonIA = _clesToutes
        .where((k) => !_clesIA.contains(k))
        .where((k) => !_clesELO.contains(k))
        .toList();
    for (final cle in clesNonIA) {
      await prefs.setString(cle, 'VALEUR-A4-$cle');
    }

    // ── Clés ELO/Cote restantes, avec leur contenu RÉEL de type String ───
    // `elo_ratings_v1` est la relique de migration lue par `EloService`
    // (`_charger` l.66) : on lui donne un rating ancien non trivial.
    await prefs.setString('elo_ratings_v1',
        jsonEncode(<String, dynamic>{
          'OURAGAN HERITE|TROT_ATTELE': EloScore(
            nomCheval: 'OURAGAN HERITE',
            rating: 1555.0,
            nbCourses: 8,
            variationMois: -7.5,
          ).toJson(),
        }));
    // Les deux clés CoteTracker sont de simples chaînes JSON côté service.
    await prefs.setString('cote_tracker_mouvements_v1',
        jsonEncode(<String, dynamic>{'R1C1': 4.65}));
    await prefs.setString('cote_mouvements_live_v1',
        jsonEncode(<String, dynamic>{'R1C1': 4.10}));

    // ── Clés DYNAMIQUES `cache_reunions_*` (balayage R01-a) ──────────────
    final cleCacheJour = 'cache_reunions_${_ddmmyyyy(jour)}';
    final cleCacheTs = '${cleCacheJour}_ts';
    await prefs.setString(cleCacheJour, '{"reunions":[1,2,3]}');
    await prefs.setInt(cleCacheTs, 1794900000000);

    // ── ELO non trivial ─────────────────────────────────────────────────
    await _amorcerElo(<String, double>{
      _cleElo('OURAGAN T7B', 'Trot Attelé'): 1683.5,
      _cleElo('TORNADE T7B', 'Plat'): 1471.25,
    });

    // ── Archive + arrivées officielles : doivent survivre ────────────────
    IaArchiveService.instance.enregistrerEviction(
        _pronostic(courseKey: _courseKey(7, 7, jour),
            date: jour, avecResultat: true));
    expect(await IaArchiveService.instance.persisterEnAttente(), isTrue,
        reason: 'T7-B : préparation de l\'archive non confirmée');
    final arrivees = await ArriveeOfficielleService.instance.enregistrer(
        EntreeArrivee(
            courseKey: _courseKey(8, 8, jour),
            rangs: <List<int>>[
              <int>[3],
              <int>[1],
              <int>[2],
            ]));
    expect(arrivees.succes, isTrue,
        reason: 'T7-B : préparation des arrivées officielles non confirmée');

    // ── 2) L'état IA en DERNIER : plus aucun service ne peut le réécrire ──
    // `_amorcer()` sème les 13 clés IA de contenu avec leur TYPE RÉEL
    // (StringList pour rapports/bilans/pronostics/journal, String pour le
    // reste). C'est ce contrat de type qui rend `_load()` complet.
    await _amorcer(
      poids: _poidsBackup(),
      seuils: _seuilsBackup(),
      pronostics: <IaPronostic>[
        _pronostic(courseKey: _courseKey(1, 1, jour), date: jour,
            avecResultat: true),
        _pronostic(courseKey: _courseKey(1, 2, jour), date: jour),
      ],
      journal: <JournalEntree>[
        _entreeJournal(1, 'gradient'),
        _entreeJournal(2, 'gradient'),
      ],
      precision: <String, StatsPrecisionParType>{
        'Quinté+': _precision('Quinté+', 9, 4),
        'Tiercé': _precision('Tiercé', 6, 2),
      },
      labels: <String, StatsParLabel>{
        'FAVORI IA': _label('FAVORI IA', 9, 4, 7, 8),
      },
      contenuEtendu: true,
    );

    await IaMemoryService.instance.recharger();

    // ── TÉMOINS DE NON-VACUITÉ : les clés sont présentes AVANT ───────────
    // `ia_pronostics_v2` et `ia_pronostics_v2_gz` sont MUTUELLEMENT EXCLUSIFS :
    // `_save()` n'en écrit qu'UN seul (le gzip au-delà de 20 pronostics).
    // Les exiger tous deux serait un faux témoin. On mesure donc
    // « exactement un des deux formats », puis les 105 autres clés une à une.
    final formatsPresents = clesFormat.where(store.contient).toList();
    expect(formatsPresents.length, 1,
        reason: 'T7-B témoin : `_save()` ne laisse qu\'UN seul format de '
            'pronostics — présents : $formatsPresents');
    expect(formatsPresents.single, 'ia_pronostics_v2',
        reason: 'T7-B témoin : avec 2 pronostics (< 21), le format retenu est '
            'le JSON non compressé');

    final absentesAvant = _clesToutes
        .where((k) => !clesFormat.contains(k))
        .where((k) => !store.contient(k))
        .toList();
    expect(absentesAvant, isEmpty,
        reason: 'T7-B témoin : les ${_clesToutes.length - 1} autres clés de '
            '`_toutesLesCles` doivent TOUTES être présentes AVANT le reset — '
            'absentes : $absentesAvant');
    expect(store.contient(cleCacheJour), isTrue,
        reason: 'T7-B témoin : clé de cache dynamique présente');
    expect(store.contient(cleCacheTs), isTrue,
        reason: 'T7-B témoin : clé `_ts` du cache présente');

    // Témoins RAM non triviaux.
    final svc = IaMemoryService.instance;
    expect(svc.pronostics.length, 2, reason: 'T7-B témoin : 2 pronostics');
    expect(svc.journal.length, 2, reason: 'T7-B témoin : 2 entrées de journal');
    // Rapports / bilans : semés en StringList JSON avec leur type réel.
    expect(svc.rapports.length, 1,
        reason: 'T7-B témoin : 1 rapport journalier chargé depuis le disque');
    expect(svc.rapports.single.nbCoursesAnalysees, 7,
        reason: 'T7-B témoin : rapport non trivial (7 courses analysées)');
    expect(svc.bilansSemaine.length, 1,
        reason: 'T7-B témoin : 1 bilan hebdomadaire chargé');
    expect(svc.bilansSemaine.single.totalCourses, 5,
        reason: 'T7-B témoin : bilan hebdomadaire non trivial (5 courses)');
    expect(svc.bilansMois.length, 1,
        reason: 'T7-B témoin : 1 bilan mensuel chargé');
    expect(svc.statsParType.length, 1,
        reason: 'T7-B témoin : 1 ligne de stats par type');
    expect(svc.precisionParType.length, 2,
        reason: 'T7-B témoin : 2 types de pari en précision');
    expect(svc.statsParLabel.length, 1,
        reason: 'T7-B témoin : 1 label de stats');
    expect(svc.premiumsPourDate(jour.year, jour.month, jour.day), isNotEmpty,
        reason: 'T7-B témoin : historique premium NON vide pour la date');
    expect(svc.arriveeConnue(_courseKey(1, 1, jour)), <int>[2, 1, 3, 4],
        reason: 'T7-B témoin : arrivée connue via le pronostic RÉSOLU (cache RAM '
            'vide), ce qui prouve que le cache est bien le chemin mesuré');
    expect(svc.poids.nbMisesAJour, 251,
        reason: 'T7-B témoin : compteur de mises à jour non trivial');
    expect(svc.poids.calibrationScore, 17.5,
        reason: 'T7-B témoin : calibration non usine');
    expect(IaCalibrationRegistry.value, 17.5,
        reason: 'T7-B témoin : registre aligné sur 17.5 avant le reset');
    expect(_enc(svc.poids.toJson()), isNot(_enc(_poidsUsine)),
        reason: 'T7-B témoin : les poids NE sont PAS ceux d\'usine avant');
    expect(_enc(svc.seuilsConfiance.toJson()), isNot(_enc(_seuilsUsine)),
        reason: 'T7-B témoin : les seuils NE sont PAS ceux d\'usine avant');
    expect(EloService.instance.nbChevauxSuivis, 2,
        reason: 'T7-B témoin : 2 ratings ELO en mémoire');
    expect(IaArchiveService.instance.nbVersionsArchivees, greaterThan(0),
        reason: 'T7-B témoin : archive non vide');
    expect(
        await ArriveeOfficielleService.instance.enumererClesSurStockage(),
        isNotEmpty,
        reason: 'T7-B témoin : shard d\'arrivées présent sur le disque');
    // Config d'alertes non usine (AlertConfig.defaut a activerCourseEnCours=false).
    await AlertService.instance.updateConfig(
        const AlertConfig(activerCourseEnCours: true, minutesAvantDepart: 27));
    expect(AlertService.instance.config.activerCourseEnCours, isTrue,
        reason: 'T7-B témoin : config d\'alertes NON usine avant le reset');
    expect(AlertService.instance.config.minutesAvantDepart, 27,
        reason: 'T7-B témoin : minutesAvantDepart = 27 avant le reset');
    expect(store.contient('alert_config_v2'), isTrue,
        reason: 'T7-B témoin : la config d\'alertes est bien persistée');

    final poidsAvant = _enc(svc.poids.toJson());

    // ── ACTION : la vraie API publique ───────────────────────────────────
    await BackupService.instance.reinitialiserComplet();

    // ── ① Les 107 clés fixes ont TOUTES disparu du disque ────────────────
    final survivantes = _clesToutes.where(store.contient).toList();
    expect(survivantes, isEmpty,
        reason: 'T7-B : les ${_clesToutes.length} clés de `_toutesLesCles` '
            'doivent toutes être effacées — survivantes : $survivantes');

    // ── ② Les clés DYNAMIQUES `cache_reunions_*` sont balayées ───────────
    expect(store.contient(cleCacheJour), isFalse,
        reason: 'T7-B : la clé `cache_reunions_<ddmmyyyy>` est balayée par '
            'R01-a (backup_service.dart:1617-1624)');
    expect(store.contient(cleCacheTs), isFalse,
        reason: 'T7-B : la clé `cache_reunions_<ddmmyyyy>_ts` est balayée '
            'aussi — elle commence par le même préfixe');
    final cachesRestants =
        store.cles.where((k) => k.startsWith('cache_reunions_')).toList();
    expect(cachesRestants, isEmpty,
        reason: 'T7-B : aucun `cache_reunions_*` ne doit subsister — '
            'restants : $cachesRestants');

    // ── ③ Poids, seuils et calibration reviennent aux VALEURS D'USINE ────
    expect(_enc(svc.poids.toJson()), _enc(_poidsUsine),
        reason: 'T7-B : `_poids = IaPoidsAdaptatifs.defaut()` (l.2107) — '
            'valeurs d\'usine exactes en RAM');
    expect(svc.poids.nbMisesAJour, 0,
        reason: 'T7-B : compteur de mises à jour remis à 0');
    expect(svc.poids.calibrationScore, 50.0,
        reason: 'T7-B : calibrationScore d\'usine = 50.0');
    expect(_enc(svc.seuilsConfiance.toJson()), _enc(_seuilsUsine),
        reason: 'T7-B : `_seuils = SeuilsConfianceAdaptatifs()` (l.2108)');
    expect(IaCalibrationRegistry.value, 50.0,
        reason: 'T7-B : registre resynchronisé par '
            '`IaCalibrationRegistry.update(_poids.calibrationScore)` (l.2114)');
    expect(_enc(svc.poids.toJson()), isNot(poidsAvant),
        reason: 'T7-B : les poids ont RÉELLEMENT changé (témoin inverse)');

    // ── ④ Compteurs et journal : les 13 champs RAM vidés ─────────────────
    expect(svc.pronostics, isEmpty, reason: 'T7-B : `_pronostics.clear()`');
    expect(svc.journal, isEmpty, reason: 'T7-B : `_journal.clear()`');
    expect(svc.rapports, isEmpty, reason: 'T7-B : `_rapports.clear()`');
    expect(svc.bilansSemaine, isEmpty,
        reason: 'T7-B : `_bilansSemaine.clear()`');
    expect(svc.bilansMois, isEmpty, reason: 'T7-B : `_bilansMois.clear()`');
    expect(svc.statsParType, isEmpty, reason: 'T7-B : `_statsTypes.clear()`');
    expect(svc.precisionParType, isEmpty,
        reason: 'T7-B : `_precisionParType.clear()`');
    expect(svc.statsParLabel, isEmpty,
        reason: 'T7-B : `_statsLabels.clear()`');
    expect(svc.premiumsPourDate(jour.year, jour.month, jour.day), isEmpty,
        reason: 'T7-B : `_premiumHistorique = {}` (l.2098)');
    // `_arriveeCache` / `_arriveeEnCours` sont vidés (l.2100-2101) : une
    // arrivée qui n'était connue QUE par le cache RAM ne l'est plus.
    expect(svc.arriveeConnue(_courseKey(1, 1, jour)), isNull,
        reason: 'T7-B : `_arriveeCache.clear()` — l\'arrivée n\'est plus '
            'connue, alors qu\'elle l\'était par le pronostic résolu avant');
    // `_premiumCourseKeys` vidé (l.2097) : prouvé par la clé premium effacée
    // et l'historique vide ci-dessus ; le champ n'a pas de getter public.

    // ── ⑤ Remise à zéro ELO (RAM vidée dans le `finally`, l.458) ─────────
    expect(EloService.instance.nbChevauxSuivis, 0,
        reason: 'T7-B : `_ratings.clear()` dans le finally de '
            '`EloService.executerResetComplet`');
    expect(EloService.instance.getRating('OURAGAN T7B',
            discipline: 'Trot Attelé'),
        1500.0,
        reason: 'T7-B : plus aucun rating → `_eloDefaut` (1500.0)');

    // ── ⑥ Alertes et autres services : config d'usine ────────────────────
    expect(AlertService.instance.config.activerCourseEnCours, isFalse,
        reason: 'T7-B : `_config = AlertConfig.defaut` (alert_service.dart:2896)');
    expect(AlertService.instance.config.minutesAvantDepart, 15,
        reason: 'T7-B : minutesAvantDepart d\'usine = 15');
    expect(store.contient('alert_config_v2'), isFalse,
        reason: 'T7-B : la clé de config d\'alertes est effacée');

    // ── ⑦ Archive ET arrivées officielles préservées ─────────────────────
    expect(IaArchiveService.instance.nbVersionsArchivees, greaterThan(0),
        reason: 'T7-B : l\'archive survit à un reset complet (décision E4, '
            'prouvée par v14_e3 Z-1)');
    expect(store.cles.any((k) => k.startsWith('ia_archive_v1_')), isTrue,
        reason: 'T7-B : les shards d\'archive sont bien sur le disque');
    expect(
        await ArriveeOfficielleService.instance.enumererClesSurStockage(),
        isNotEmpty,
        reason: 'T7-B : les arrivées officielles ne sont dans aucune liste '
            'effacée (L0-8) — elles survivent');

    // ── ⑧ Stabilité après RECHARGEMENT + absence d'apprentissage ─────────
    final apresReset = _Etat.prendre();
    await IaMemoryService.instance.recharger();
    final apresRechargement = _Etat.prendre();

    final ecarts = apresReset.differences(apresRechargement);
    expect(ecarts, isEmpty,
        reason: 'T7-B : après un reset RÉUSSI, un rechargement ne doit rien '
            'changer (RAM et disque sont déjà cohérents) — écarts : '
            '${apresReset.rapport("T7-B/rechargement", apresRechargement)}');
    expect(_enc(IaMemoryService.instance.poids.toJson()), _enc(_poidsUsine),
        reason: 'T7-B : les poids restent d\'usine après rechargement');
    expect(IaCalibrationRegistry.value, 50.0,
        reason: 'T7-B : registre stable à 50.0 après rechargement');
    // Aucune clé IA n'a été RECRÉÉE par le rechargement : le garde
    // `_resetEnCours` (l.2218) interdit tout `_load()` pendant le reset, et
    // aucun `_save()` n'est déclenché ensuite.
    final reecrites = _clesIA.where(store.contient).toList();
    expect(reecrites, isEmpty,
        reason: 'T7-B : aucune clé `_keysIA` ne doit réapparaître après le '
            'rechargement — réécrites : $reecrites');
    expect(IaMemoryService.instance.journal, isEmpty,
        reason: 'T7-B : journal toujours vide — AUCUNE entrée '
            '`gradient`/`regles`/`discipline` ajoutée (aucun apprentissage '
            'involontaire)');
    expect(IaMemoryService.instance.poids.nbMisesAJour, 0,
        reason: 'T7-B : compteur toujours à 0 — aucune mise à jour de poids');

    // ignore: avoid_print
    print('[A4-T7-B] ${_clesToutes.length} clés fixes effacées | 2 clés '
        'dynamiques cache_reunions_* balayées | poids/seuils/calibration '
        'd\'usine | ELO=${EloService.instance.nbChevauxSuivis} rating(s) | '
        'alertes=defaut | archive='
        '${IaArchiveService.instance.nbVersionsArchivees} version(s) | '
        'arrivées préservées | rechargement stable');
  });
}

