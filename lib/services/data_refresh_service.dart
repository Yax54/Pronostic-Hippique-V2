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
import 'package:shared_preferences/shared_preferences.dart';
import '../data/connaissances/_acquisition/acquisition_pmu.dart';
import 'zone_turf_service.dart';
import 'arrivee_officielle_prioritaire.dart'; // ★ A6 : L0 prioritaire + appartenance
import 'arrivee_officielle_service.dart';      // ★ A6 : lecture L0 (RAM, copie profonde)
import 'ia_memory_service.dart';
import 'ia_personality_service.dart'; // ★ v9.85
import 'ia_memory_models.dart';
import 'ia_pronostic_engine.dart';
import 'elo_service.dart';
import 'alert_service.dart';
import 'cote_tracker_service.dart';   // ★ v9.92 : critère R mouvement de cote
import 'recommandation_pari_service.dart' // ★ BLOC 1 : source unique du type de pari
    show cascadeRecommandation;
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

  /// ★ CORRECTION BLOC 1 — MOUVEMENTS DE COTES TRANSPORTÉS VERS L'ISOLATE.
  ///
  /// DÉFAUT MESURÉ : un isolate a sa PROPRE mémoire. `CoteTrackerService
  /// .instance` y est une instance neuve dont `_mouvements` est vide, donc
  /// `scoreCritereR()` rendait toujours `null` et `p.scoreMouvementCote`
  /// restait à 50.0 dans TOUS les pronostics calculés par `compute()` — le
  /// critère R (`mouvCote: 0.06`) était neutralisé sur ce chemin, exactement
  /// comme le critère ELO l'était avant `chargerDepuisMapIsolate`
  /// (`elo_service.dart:4260`, correctif v10.82 documenté au même endroit).
  ///
  /// Ce champ transporte les MOUVEMENTS (entrées : coteDebut, coteCourante,
  /// variationPct, horodatages), jamais le score calculé — le barème est
  /// réappliqué dans l'isolate, aucune valeur n'est figée.
  final Map<String, dynamic> mouvementsCotesJson;

  _BatchPayload({
    required this.reunionsJson,
    required this.poidsJson,
    required this.eloJson,
    required this.seuilsJson,
    this.mouvementsCotesJson = const <String, dynamic>{},
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
  } catch (e) {
    // ★ CORRECTION BLOC 1 (BL1-A08) — CE REPLI NE DOIT PAS ÊTRE SILENCIEUX.
    //   `seuilsJson` est produit par `seuilsConfiance.toJson()` dans le
    //   processus principal : il est valide par construction. Si la
    //   désérialisation échoue néanmoins, les seuils APPRIS sont perdus et
    //   l'isolate déciderait avec les DÉFAUTS — exactement le défaut
    //   BL1-A08, mais provoqué par une corruption et non par une copie.
    //
    //   Les deux options sont : interrompre tout le lot, ou continuer avec
    //   les défauts. On continue (un lot perdu coûte davantage qu'un lot
    //   calculé avec des seuils neutres), mais on TRACE : sans cette trace,
    //   la dégradation serait invisible et l'audit incapable de la mesurer.
    //   Aucune valeur de seuil n'est modifiée ici.
    if (kDebugMode) {
      debugPrint('[DataRefresh/isolate] ⚠️ seuilsJson illisible ($e) — '
          'calcul avec les seuils PAR DÉFAUT pour ce lot');
    }
    seuils = SeuilsConfianceAdaptatifs();
  }

  // ★ v10.82 — D3 : restaurer les ELO dans l'isolate.
  // Sans ceci, EloService.instance est une instance neuve (_ratings vide)
  // et enrichirAvecElo() écrase eloRating avec le défaut 1500
  // → critère M figé à 37.5 pour tous les chevaux.
  // Lecture seule : aucune formule ELO n'est modifiée.
  EloService.instance.chargerDepuisMapIsolate(payload.eloJson);

  // ★ CORRECTION BLOC 1 — RESTAURER LES MOUVEMENTS DE COTES.
  //   Sans ceci, `_mouvements` est vide dans l'isolate et le critère R
  //   (`mouvCote: 0.06`) vaut 50.0 pour TOUS les partants, même dans la
  //   fenêtre des 30 minutes. Même motif que la restauration ELO ci-dessus.
  //   Lecture seule du barème : seule la DONNÉE d'entrée est transmise.
  CoteTrackerService.instance
      .chargerMouvementsDepuisMapIsolate(payload.mouvementsCotesJson);

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
      final coteTop   = partantsClasses.first.coteDecimale;

      // ★ CORRECTION BLOC 1 (BL1-A02 / BL1-A03 / BL3-A26) — SOURCE UNIQUE
      //   Cette cascade locale à l'isolate dupliquait la logique de décision
      //   avec des variantes (elle omettait notamment la branche `isQuarte`
      //   dans le fallback synchrone, cf. BL1-A03). Elle délègue désormais à
      //   `cascadeRecommandation()`, qui est PURE et sans état : elle peut
      //   donc s'exécuter dans un isolate. Les seuils lui sont passés
      //   explicitement (`seuils`, reconstruits depuis `payload.seuilsJson`),
      //   ce qui garantit que l'isolate applique exactement les seuils appris
      //   par `IaMemoryService` et non une copie par défaut.
      final typePariAuto = cascadeRecommandation(
        course: course,
        seuils: seuils,
        scoreConf: scoreConf,
        score2nd: partantsClasses.length >= 2
            ? partantsClasses[1].scoreIA
            : null,
        score3: partantsClasses.length >= 3 ? partantsClasses[2].scoreIA : null,
        score4: partantsClasses.length >= 4 ? partantsClasses[3].scoreIA : null,
        coteTop: coteTop,
      ).typePari;

      // Sérialiser les scores critères
      final scoresJson = <String, dynamic>{};
      scoresCriteres.forEach((cle, sc) => scoresJson[cle] = sc.toJson());

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

  /// Date/heure de la dernière TENTATIVE (réussie ou non). Voir [derniereTentative].
  DateTime? _dateDerniereTentative;

  /// Issue de la dernière tentative. Voir [derniereIssue].
  IssueChargement? _derniereIssue;

  // ★ v9.0 : État précédent des partants par courseKey pour détection non-partants
  // Clé : courseKey (ex: "R1C3"), Valeur : set des numéros connus
  final Map<String, Set<int>> _partantsParCourse = {};

  // ★ v9.0 : Notifications de non-partants déjà envoyées (anti-doublon)
  final Set<String> _nonPartantsNotifies = {};

  // ── Persistance ──────────────────────────────────────────────────
  static const String _prefsCachePrefix  = 'cache_reunions_';
  static const Duration _refreshInterval = Duration(minutes: 15);
  static const Duration _cacheLocalDuree = Duration(hours: 8);

  // ═══════════════════════════════════════════════════════════════════════
  //  ★ B5c-RDR-01-c — BARRIÈRE DE RÉINITIALISATION.
  //
  //  MODÈLE : identique à `AlertService`, `IaMemoryService`, `EloService` et
  //  `CoteTrackerService`, pour que le raisonnement soit transposable.
  //    • `_resetEnCours`   : barrière TEMPORELLE, vraie du début du reset à la
  //                          fin de l'effacement disque.
  //    • `_generationCache`: verrou DÉFINITIF, jamais décrémenté. Il couvre
  //                          les opérations dont un `await` se résout APRÈS
  //                          la fermeture de `_resetEnCours` — c'est-à-dire
  //                          précisément le cas « reset pendant le chargement
  //                          réseau » que cette correction traite.
  //    • `_ecrituresEnCours`: registre des écritures ENGAGÉES, alimenté et
  //                          vidé par `_ecrireProtege` UNIQUEMENT.
  //
  //  CE QUI ÉTAIT FAUX AVANT (mesuré) : `_doRefresh()` traversait un `await
  //  ZoneTurfService.chargerProgramme()` pouvant durer 20 s. Un reset exécuté
  //  dans cette fenêtre effaçait le disque, puis le rafraîchissement REPRENAIT
  //  son cours : `_reunions = reunions` (l.520) repeuplait la RAM vidée par
  //  R-DR-01-b, `_initialiserEtatPartants` repeuplait `_partantsParCourse`,
  //  `_lastRefresh` était réécrit, `_sauvegarderCacheLocal` recréait les deux
  //  clés supprimées par R-DR-01-a, et les cinq effets secondaires
  //  (pronostics, widget, cotes, résultats, conseils) étaient relancés.
  // ═══════════════════════════════════════════════════════════════════════

  /// Barrière temporelle : vraie du début du reset à la fin de l'effacement.
  bool _resetEnCours = false;

  /// Verrou définitif : ne redescend jamais.
  int _generationCache = 0;

  /// Registre des écritures de cache ENGAGÉES (contrôles franchis).
  final Set<Future<bool>> _ecrituresEnCours = <Future<bool>>{};

  bool get resetEnCours => _resetEnCours;
  int get generationCache => _generationCache;
  int get nbEcrituresEnCours => _ecrituresEnCours.length;

  List<ZtReunion> get reunions    => _reunions;
  bool            get loading     => _loading;
  String?         get lastError   => _lastError;

  /// Dernière actualisation **RÉUSSIE** — et non dernière tentative.
  ///
  /// ═══════════════════════════════════════════════════════════════════════════
  ///  ⚠️ DÉFAUT MESURÉ AVANT CETTE CORRECTION (M4-a)
  ///
  ///  Une coupure réseau TOTALE (aucune réponse obtenue) produisait :
  ///      lastError  = null
  ///      lastRefresh = 2026-11-26 18:11:12.959362   ← renseigné !
  ///  L'interface affichait donc « À l'instant » alors qu'aucune donnée
  ///  n'avait été obtenue. C'est exactement « un échec présenté comme une
  ///  réussite ».
  ///
  ///  CAUSE : `_lastRefresh` était réécrit inconditionnellement dans `try`,
  ///  juste après les traitements, sans regarder ce que le producteur avait
  ///  réellement rapporté. Le producteur rend `[]` aussi bien pour une panne
  ///  que pour une journée sans course, et `_doRefresh` ne consultait que la
  ///  LONGUEUR de la liste — jamais sa NATURE.
  ///
  ///  CORRECTION : `_lastRefresh` n'est plus écrit que si le producteur a
  ///  publié une issue de RÉUSSITE (`complet`, `incomplet`, `aucuneCourse`).
  ///  Les issues de PANNE (`reseauIndisponible`, `reponseInvalide`,
  ///  `erreurServeur`) alimentent `_lastError` et laissent `_lastRefresh`
  ///  intact : la dernière connaissance valide n'est ni effacée ni présentée
  ///  comme fraîche.
  ///
  ///  L'état de la DERNIÈRE TENTATIVE, réussie ou non, est publié séparément
  ///  par [derniereTentative], pour que l'appelant puisse distinguer « je n'ai
  ///  pas pu actualiser » de « la dernière actualisation date de X ».
  /// ═══════════════════════════════════════════════════════════════════════════
  DateTime? get lastRefresh => _lastRefresh;

  /// Horodatage de la dernière **tentative**, qu'elle ait réussi ou échoué.
  ///
  /// Distinct de [lastRefresh] par construction : une tentative ratée met ce
  /// champ à jour et laisse [lastRefresh] inchangé. C'est la seule façon de
  /// répondre à « quand a-t-on essayé pour la dernière fois ? » sans mentir
  /// sur « quand a-t-on réussi pour la dernière fois ? ».
  DateTime? get derniereTentative => _dateDerniereTentative;

  /// Issue de la dernière tentative. `null` avant toute tentative.
  IssueChargement? get derniereIssue => _derniereIssue;

  /// Vrai si la dernière tentative a effectivement abouti à des données
  /// exploitables (ou à une absence légitime de course).
  bool get derniereTentativeReussie => _derniereIssue?.estReussite ?? false;

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
    // ★ B5c-RDR-01-c : l'écriture passe par le REGISTRE, donc par la
    //   barrière. Sans cela, le drain du reset ne la verrait pas : une
    //   écriture suspendue se terminerait après l'effacement et recréerait
    //   la paire de clés (scénario mesuré V31b R01-J).
    //
    //   ⚠️ `_ecrireProtegeCache` est asynchrone et son corps s'exécute
    //   jusqu'au premier `await` de façon synchrone : la future est donc
    //   enregistrée avant tout point de reprise, comme l'exige le drain.
    await _ecrireProtegeCache((prefs) async {
      final cle = _cleCachePourDate(dateStr);

      // ───────────────────────────────────────────────────────────────────
      //  ORDRE D'ÉCRITURE : `_ts` puis JSON, et NON l'inverse.
      //
      //  `_chargerCacheLocal` lit le JSON d'abord et sort si `jsonStr == null
      //  || jsonStr.isEmpty` (l.296-297). Une clé `_ts` orpheline est donc
      //  inoffensive. À l'inverse, un JSON SANS `_ts` est relu avec
      //  `timestampMs == null` → `_lastRefresh = null` (l.350-352), donc SANS
      //  contrôle de péremption. Écrire l'horodatage en premier garantit
      //  qu'une interruption ne laisse jamais de JSON sans `_ts` : le seul
      //  résidu possible est une clé `_ts` seule, que R-DR-01-a supprime et
      //  que la lecture ignore.
      // ───────────────────────────────────────────────────────────────────
      final okTs = await prefs.setInt(
          '${cle}_ts', DateTime.now().millisecondsSinceEpoch);

      // Contrôle de génération entre les DEUX écritures : `setInt` est
      // asynchrone. Un reset survenu pendant sa résolution rend la paire
      // incohérente ; on retire alors le `_ts` déjà posé.
      if (_resetEnCours) {
        await prefs.remove('${cle}_ts');
        if (kDebugMode) {
          debugPrint('[DataRefresh] ⏭️ cache non écrit : reset survenu entre '
              'les deux écritures — clé _ts orpheline retirée');
        }
        return;
      }

      if (!okTs) {
        // Écriture d'horodatage REFUSÉE : on n'écrit pas le JSON, sinon on
        // créerait exactement la paire désynchronisée interdite.
        _derniereErreurCache =
            'setInt refusé pour ${cle}_ts — JSON non écrit';
        debugPrint('[DataRefresh] ⚠️ $_derniereErreurCache');
        return;
      }

      final okJson = await prefs.setString(
          cle, jsonEncode(reunions.map((r) => r.toJson()).toList()));

      if (!okJson) {
        // Écriture du JSON REFUSÉE : le `_ts` déjà écrit devient orphelin.
        // On le supprime pour ne laisser aucune clé partielle.
        await prefs.remove('${cle}_ts');
        _derniereErreurCache =
            'setString refusé pour $cle — clé _ts orpheline retirée';
        debugPrint('[DataRefresh] ⚠️ $_derniereErreurCache');
        return;
      }

      _derniereErreurCache = null;
      await _nettoyerAnciensCache(prefs, dateStr);
    });
  }

  /// Dernière erreur d'écriture de cache, pour le diagnostic (et les tests).
  /// `null` quand la dernière écriture a réussi. Une écriture REFUSÉE par la
  /// barrière de reset n'est PAS une erreur : elle n'est pas enregistrée ici.
  String? _derniereErreurCache;
  String? get derniereErreurCache => _derniereErreurCache;

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

  /// Discriminant de changement, exposé pour que la MESURE porte sur le code
  /// de production et non sur une reproduction.
  ///
  /// ⚠️ POURQUOI CETTE EXPOSITION EXISTE
  ///    Ma première mesure du mouvement de cote (M2-a) reproduisait la règle
  ///    de `_signaturedReunions` DANS le fichier de test. Elle ne mesurait donc
  ///    que sa propre copie : une correction de la production y serait restée
  ///    invisible, et un défaut de la copie aurait pu être attribué au service.
  ///    C'est exactement le raisonnement qu'il faut s'interdire.
  ///
  ///    Cette exposition ne change aucun comportement : `_signaturedReunions`
  ///    est la méthode effectivement utilisée par `_doRefresh`.
  @visibleForTesting
  String signaturePourMesure(List<ZtReunion> reunions) =>
      _signaturedReunions(reunions);

  String _signaturedReunions(List<ZtReunion> reunions) {
    final buf = StringBuffer();
    final maintenant = DateTime.now();
    for (final r in reunions) {
      buf.write('${r.code}:${r.courses.length}');
      for (final c in r.courses) {
        final isTerminee = maintenant.difference(c.heureDateTime).inMinutes > 90;
        // ★ Fix : inclure le nombre de partants dans la signature
        // Sans ça, quand les cotes apparaissent (partants 0→13), la signature
        // ne change pas → _enregistrerPronosticsAuto non appelé → pronostics jamais créés
        buf.write('|${c.numCourse}${c.heure}${isTerminee ? "T" : "A"}${c.partants.length}');

        // ══════════════════════════════════════════════════════════════════
        //  ★ §2 — LE MOUVEMENT DE COTE DOIT ÊTRE UN CHANGEMENT UTILE
        //
        //  ⚠️ DÉFAUT MESURÉ AVANT CETTE CORRECTION (test/audit/
        //     mecanismes_actualisation_mesure_test.dart, M2-a) :
        //     deux programmes ne différant QUE par la cote d'un cheval
        //     (4,0 → 9,0) produisaient la MÊME signature :
        //         signature(cotes 4.0)     = R1:1|113:00T8
        //         signature(cote 1 → 9.0)  = R1:1|113:00T8
        //     La cote était donc invisible du discriminant : un mouvement de
        //     marché ne pouvait jamais être signalé comme un changement.
        //
        //  CE QUI EST AJOUTÉ, ET SON PÉRIMÈTRE EXACT :
        //     • uniquement les cotes des courses NON TERMINÉES. Une course
        //       terminée ne bouge plus : l'inclure ferait varier la signature
        //       sans aucune information nouvelle, donc pour rien ;
        //     • la cote est arrondie au dixième. Ce n'est PAS un seuil métier
        //       et cela ne modifie aucun calcul : c'est une décision de
        //       GRANULARITÉ du discriminant, prise pour que le bruit de
        //       troisième décimale du flux PMU ne déclenche pas un cycle
        //       complet de rafraîchissement toutes les 15 minutes
        //       (§2 exige aussi la prévention des traitements redondants).
        //     • l'ORDRE des partants est celui de la liste : deux programmes
        //       dont les partants sont dans un ordre différent produisent donc
        //       des signatures différentes. C'est conservateur — un faux
        //       « changement » coûte un cycle, un faux « identique » perd une
        //       information — et c'est le sens de l'exigence.
        //
        //  ⚠️ AUCUN CRITÈRE, AUCUN POIDS, AUCUN SEUIL N'EST TOUCHÉ ICI.
        //     Le critère R (`mouvCote`) continue d'être alimenté par
        //     `CoteTrackerService`, qui suit les snapshots horodatés : ce bloc
        //     ne fait que rendre le mouvement VISIBLE du rafraîchissement.
        // ══════════════════════════════════════════════════════════════════
        if (!isTerminee) {
          for (final p in c.partants) {
            final cote = double.tryParse(p.cote.replaceAll(',', '.')) ?? 0.0;
            // `toStringAsFixed(1)` : granularité assumée, voir ci-dessus.
            buf.write('~${p.numero}:${cote.toStringAsFixed(1)}');
          }
        }
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
  //
  //  ★ B5c-RDR-01-c — CYCLE COMPLET PROTÉGÉ.
  //
  //  La génération est capturée AVANT le premier `await` (le chargement
  //  réseau) et revérifiée à CHAQUE point de reprise asynchrone. Tout ce qui
  //  touche la RAM ou le disque est donc conditionné.
  //
  //  Ce qui est CONSERVÉ à l'identique : l'ordre des opérations, les
  //  conditions de changement de signature, la détection des non-partants,
  //  `_initialiserEtatPartants`, la sauvegarde du cache, et les cinq effets
  //  secondaires. Aucun calcul, aucune règle métier, aucun seuil n'est touché.
  //
  //  Ce qui est AJOUTÉ : trois sorties anticipées, toutes sur le même critère
  //  `_estObsolete(generation)`, et un `finally` qui ne notifie plus un état
  //  périmé. Une opération obsolète ne réécrit rien et ne relance rien.
  Future<void> _doRefresh({bool force = false}) async {
    if (_loading) return;

    // ── Capture AVANT tout `await` : c'est le point d'engagement. ────────
    //  Lue en PREMIER, avant même la pose de `_loading`, pour qu'aucun code
    //  asynchrone puisse s'intercaler entre la capture et le début du travail.
    final generationAuDemarrage = _generationCache;

    if (_resetEnCours) {
      // Un reset est déjà en cours : ne rien démarrer du tout.
      if (kDebugMode) {
        debugPrint('[DataRefresh] ⏭️ refresh refusé : reset en cours');
      }
      return;
    }

    _loading   = true;
    _lastError = null;
    notifyListeners();

    try {
      debugPrint('[DataRefresh] Chargement programme réseau...');
      final todayStr = _todayDateStr();
      final reunions = await ZoneTurfService.chargerProgramme(
          forceRefresh: force);

      // ═══════════════════ ISSUE DE LA TENTATIVE ════════════════════════
      //  ★ §2 — LA NATURE DE L'ISSUE EST LUE ICI, PAS SEULEMENT LA LONGUEUR.
      //
      //  Avant, `_doRefresh` ne regardait que `reunions.isEmpty`. Or le
      //  producteur rend `[]` aussi bien pour une journée sans course que pour
      //  une coupure réseau : les deux étaient donc traitées identiquement, et
      //  `_lastRefresh` était réécrit dans les deux cas (défaut M4-a mesuré).
      //
      //  ⚠️ CETTE LECTURE EST FAITE AVANT TOUT AUTRE `await` APRÈS LE
      //     CHARGEMENT : `issueCourante` est un état global du producteur, un
      //     autre chargement pourrait le modifier. Le lire immédiatement après
      //     le retour garantit qu'il décrit CE chargement.
      final issue = ZoneTurfService.issueCourante;
      _derniereIssue = issue;
      _dateDerniereTentative = DateTime.now();
      if (kDebugMode) {
        debugPrint('[DataRefresh] issue du chargement : ${issue.name} '
            '(${reunions.length} réunion(s))');
      }

      // ═══════════════ POINT DE REPRISE ASYNCHRONE N°1 ══════════════════
      //  Le chargement réseau a pu durer 20 s, pendant lesquelles un reset
      //  complet s'est éventuellement déroulé. On ne touche plus à rien.
      if (_estObsolete(generationAuDemarrage)) {
        if (kDebugMode) {
          debugPrint('[DataRefresh] ⏭️ refresh abandonné : reset survenu '
              'pendant le chargement réseau (génération '
              '$generationAuDemarrage → $_generationCache)');
        }
        return;
      }

      // ── ÉCHEC DÉCLARÉ : aucune connaissance valide n'est effacée ───────
      //  §2 : « un échec d'actualisation ne doit pas effacer les dernières
      //  connaissances valides ni être présenté comme une réussite ».
      //  On sort donc AVANT toute réécriture de `_reunions`, AVANT la
      //  sauvegarde du cache et AVANT les cinq effets secondaires.
      if (!issue.estReussite) {
        _lastError = _messagePourIssue(issue);
        // `_lastRefresh` N'EST PAS TOUCHÉ : il garde la dernière réussite.
        if (kDebugMode) {
          debugPrint('[DataRefresh] ⚠️ tentative en échec (${issue.name}) — '
              'dernière réussite conservée : $_lastRefresh');
        }
        return;
      }

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

            // ═══════════ POINT DE REPRISE ASYNCHRONE N°2 ═══════════════
            //  `_detecterNonPartants` contient des `await` (recalcul IA par
            //  course). Le reset a pu s'exécuter pendant l'un d'eux : on ne
            //  réécrit pas `_reunions` et on ne réinitialise pas l'état des
            //  partants sur des données d'avant le reset.
            if (_estObsolete(generationAuDemarrage)) {
              if (kDebugMode) {
                debugPrint('[DataRefresh] ⏭️ refresh abandonné : reset survenu '
                    'pendant la détection des non-partants');
              }
              return;
            }
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
      // Une erreur d'un rafraîchissement OBSOLÈTE ne doit pas s'afficher :
      // elle décrit un état aboli par le reset.
      //
      // ★ §2 — comme pour les issues, `_lastRefresh` N'EST PAS TOUCHÉ ici :
      //   une exception est une tentative, pas une réussite. Seul l'état de la
      //   tentative est publié, afin que l'interface puisse dire « la dernière
      //   tentative a échoué » sans prétendre que les données sont fraîches.
      if (!_estObsolete(generationAuDemarrage)) {
        _lastError = e.toString();
        _dateDerniereTentative = DateTime.now();
        // L'exception n'a pas de nature d'issue propre : on conserve celle que
        // le producteur avait publiée si elle est déjà un échec, sinon on
        // classe en `reponseInvalide` — l'information disponible ne permet pas
        // d'affirmer mieux, et l'affirmer mieux serait l'inventer.
        if (_derniereIssue == null || _derniereIssue!.estReussite) {
          _derniereIssue = IssueChargement.reponseInvalide;
        }
      }
      debugPrint('[DataRefresh] ❌ Erreur: $e');
    } finally {
      _loading = false;
      // Même règle pour la notification : on ne réveille pas l'UI sur un état
      // périmé. En cas d'obsolescence, R-DR-01-b a déjà vidé la RAM et le
      // `notifyListeners()` de fin de `reinitialiserComplet()` a prévenu l'UI.
      if (!_estObsolete(generationAuDemarrage)) {
        notifyListeners();
      }
    }
  }

  /// Vrai si le rafraîchissement engagé sous [generation] ne doit plus rien
  /// écrire : soit un reset est en cours, soit la génération a changé.
  ///
  /// Les deux termes sont nécessaires : `_resetEnCours` couvre la fenêtre
  /// d'effacement, la génération couvre les reprises postérieures à sa
  /// fermeture. C'est la même combinaison que `AlertService._ecrireProtege`.
  bool _estObsolete(int generation) =>
      _resetEnCours || generation != _generationCache;

  /// Message destiné à l'utilisateur pour une issue d'échec.
  ///
  /// ⚠️ Chaque cause a son message, parce que l'action attendue diffère :
  ///    • réseau indisponible → réessayer plus tard, la cause est extérieure ;
  ///    • réponse invalide    → incident de la source, réessayer ne nuit pas ;
  ///    • erreur serveur      → le PMU est en défaut, réessayer plus tard.
  ///    Un message unique « erreur de chargement » empêcherait l'utilisateur
  ///    de savoir s'il doit insister ou attendre — c'est précisément ce que
  ///    §2 demande de distinguer.
  ///
  /// ⚠️ Aucune de ces issues n'efface les connaissances déjà chargées : le
  ///    message décrit la TENTATIVE, pas l'état des données.
  String? _messagePourIssue(IssueChargement issue) {
    switch (issue) {
      case IssueChargement.reseauIndisponible:
        return 'Réseau indisponible : les dernières données connues sont '
            'conservées. Nouvelle tentative au prochain rafraîchissement.';
      case IssueChargement.reponseInvalide:
        return 'Réponse du PMU illisible : les dernières données connues sont '
            'conservées.';
      case IssueChargement.erreurServeur:
        return 'Le PMU a répondu par une erreur : les dernières données connues '
            'sont conservées.';
      case IssueChargement.inconnue:
        return 'Aucune tentative de chargement n\'a encore abouti.';
      case IssueChargement.complet:
      case IssueChargement.incomplet:
      case IssueChargement.aucuneCourse:
      case IssueChargement.mutualise:
        // Issues de RÉUSSITE : aucun message d'erreur. `incomplet` n'est pas
        // une erreur (le programme existe, il n'est pas encore alimenté) et
        // `aucuneCourse` non plus (journée légitimement sans course).
        return null;
    }
  }

  /// Lance [action] en microtâche SI la génération [generation] est encore
  /// valide au moment où la microtâche s'exécute.
  ///
  /// Un seul point de passage, pour que l'invariant « aucun effet secondaire
  /// obsolète » soit vérifiable à la lecture : chaque tâche différée de ce
  /// service (pronostics, résultats) est envoyée par ici. Le travail évité
  /// n'est pas seulement une écriture : ce sont aussi un isolate de calcul
  /// et des requêtes réseau que le reset vient d'invalider.
  void _enMicrotacheSiNonObsolete(
      int generation, Future<void> Function() action, String nom) {
    Future.microtask(() async {
      if (_estObsolete(generation)) {
        if (kDebugMode) {
          debugPrint('[DataRefresh] ⏭️ $nom non lancé(s) : reset survenu '
              'avant la microtâche');
        }
        return;
      }
      await action();
    });
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
    // ★ B5c-RDR-01-c : capture AVANT tout `await` (il y en a un dans
    //   `invaliderEtRecalculer`). Voir la garde placée avant la mutation de
    //   `_reunions`, plus bas.
    final generationAuDemarrage = _generationCache;
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

      // ═══════════════════════════════════════════════════════════════════
      //  ★ B5c-RDR-01-c — GARDE SUR LA MUTATION RAM DE `reAnalyserCourse`.
      //
      //  `invaliderEtRecalculer` ci-dessus contient des `await` et possède
      //  DÉJÀ sa propre garde (R-DR-04) : elle refuse d'écrire `_pronostics`
      //  si un reset est intervenu. Mais la boucle ci-dessous, qui mute
      //  `_reunions` — donc l'état que sert l'UI — n'avait AUCUNE protection.
      //
      //  Deux défauts distincts en découlaient :
      //    1. après un reset, `_reunions` venait d'être vidé : le parcours ne
      //       trouvait rien et ne faisait rien. Bénin, mais par accident ;
      //    2. pendant un reset, un rafraîchissement EN VOL avait pu repeupler
      //       `_reunions` avant le vidage : la boucle retrouvait alors la
      //       course et réinjectait `courseFiltre` — un `ZtCourse` construit
      //       à partir d'une réunion d'AVANT le reset — juste avant que le
      //       `finally` ne vide. La donnée ne survivait pas, mais la mutation
      //       avait bien eu lieu, ce qui rendait l'invariant indémontrable.
      //
      //  Aucune règle métier n'est touchée : on ne fait que conditionner
      //  l'écriture à la validité de la génération engagée à l'entrée.
      // ═══════════════════════════════════════════════════════════════════
      if (_estObsolete(generationAuDemarrage)) {
        if (kDebugMode) {
          debugPrint('[DataRefresh] ⏭️ reAnalyserCourse: $courseKey — reset '
              'intervenu, mise à jour de `_reunions` annulée');
        }
        return;
      }

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
    // ★ B5c-RDR-01-c : la génération est capturée AU MOMENT DE L'ENVOI, pas
    //   dans la microtâche. Un reset survenu entre les deux doit empêcher le
    //   calcul de partir : c'est un effet secondaire d'un rafraîchissement
    //   aboli. Le rejet à l'engagement (R-DR-02) reste en place — ces deux
    //   protections sont complémentaires, la première évite le travail
    //   inutile, la seconde garantit qu'aucune donnée n'est écrite.
    _enMicrotacheSiNonObsolete(
      _generationCache,
      () => _enregistrerPronosticsBatchIsolate(reunions),
      'pronostics',
    );
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

    // ══════════════════════════════════════════════════════════════════════
    //  ★ B5c-RDR-02 — CAPTURE ATOMIQUE DE L'ÉTAT IA
    //
    //  Ces quatre lectures sont dans la MÊME section synchrone : aucun `await`
    //  ne les sépare, ni entre elles, ni de l'entrée de la méthode (le premier
    //  `await` est celui de `compute()`, plus bas). L'état capturé est donc
    //  cohérent, et c'est EXACTEMENT celui que l'isolate va recevoir.
    //
    //  La génération est lue EN PREMIER, et l'ordre n'est pas décoratif :
    //    • si un reset s'intercale AVANT ces lignes → génération neuve ET
    //      poids neufs → le lot sera ACCEPTÉ et calculé avec les bons poids ;
    //    • si un reset s'intercale APRÈS ces lignes → génération ancienne ET
    //      poids anciens → le lot sera REJETÉ à l'engagement.
    //  Les deux valeurs ne peuvent pas être désappariées, faute de `await`
    //  entre elles. Capturer la génération APRÈS les poids (donc juste avant
    //  `compute`) fonctionnerait aujourd'hui par accident, mais exprimerait
    //  une garantie non vérifiée : le jour où un `await` s'introduirait dans
    //  la préparation du payload, l'erreur serait silencieuse.
    //
    //  Hors du `try` pour rester visible du `catch` : le fallback n'en a pas
    //  besoin (il lit l'état courant de façon atomique), mais ces valeurs
    //  doivent être définies quel que soit le chemin.
    // ══════════════════════════════════════════════════════════════════════
    final generationAvantCalcul = IaMemoryService.instance.generationCache;
    final poidsJsonAvantCalcul  = IaMemoryService.instance.poids.toJson();
    final eloJsonAvantCalcul    = EloService.instance.exporterPourBackup();
    final seuilsJsonAvantCalcul =
        IaMemoryService.instance.seuilsConfiance.toJson();

    // ★ CORRECTION BLOC 1 — Les MOUVEMENTS DE COTES sont capturés ICI, dans le
    //   processus principal, où `CoteTrackerService.instance` est le VRAI
    //   service alimenté par le polling. L'isolate ne peut pas les calculer :
    //   il n'a ni le réseau, ni les snapshots horodatés, ni l'état du service.
    //   Capture SYNCHRONE (pas d'`await`) : elle lit l'état courant sans
    //   risque d'entrelacement, comme les trois exportations ci-dessus.
    final mouvementsJsonAvantCalcul =
        CoteTrackerService.instance.exporterMouvementsPourIsolate();

    try {
      // ★ Préparer le payload pour l'isolate
      final payload = _BatchPayload(
        reunionsJson: reunionsFiltrees
            .map((r) => r.toJson())
            .toList(),
        poidsJson:   poidsJsonAvantCalcul,
        eloJson:     eloJsonAvantCalcul,
        seuilsJson:  seuilsJsonAvantCalcul,
        mouvementsCotesJson: mouvementsJsonAvantCalcul,
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
        // ★ B5c-RDR-02 — la génération capturée AVANT `compute()` est
        //   transmise. Si un reset complet a eu lieu pendant le calcul,
        //   `enregistrerPronosticsBatch` écarte le lot EN ENTIER : aucune
        //   insertion RAM, aucune écriture disque. Sans cela, le lot
        //   réécrirait des pronostics que le reset vient d'effacer,
        //   avec des scores calculés sur les poids d'avant.
        await IaMemoryService.instance.enregistrerPronosticsBatch(batch,
            generationAuDemarrage: generationAvantCalcul);
        debugPrint('[DataRefresh] 🧠 ${batch.length} pronostic(s) IA '
            'enregistrés (isolate)');
      }
    } catch (e) {
      // Fallback : calcul sur le thread principal si l'isolate échoue
      //
      // ★ B5c-RDR-02 — le fallback ne reçoit AUCUNE génération, et c'est
      //   délibéré : il lit l'état IA et construit son lot sans aucun `await`
      //   intermédiaire (`_enregistrerPronosticsBatchFallback`, l.750→814).
      //   Son lot est donc TOUJOURS cohérent avec l'état courant. Lui passer
      //   `generationAvantCalcul` ferait rejeter des pronostics pourtant
      //   calculés avec les bons poids.
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
        final coteTop   = partantsClasses.first.coteDecimale;

        // ★ CORRECTION BLOC 1 (BL1-A03) — la branche `isQuarte` MANQUAIT ici.
        //   Un `★ fix` équivalent existait dans `ia_memory_service.dart:6229`
        //   mais pas dans ce fallback : quand l'isolate échouait, toutes les
        //   courses Quarté+ du lot recevaient un `typePariConseille` erroné,
        //   persisté puis exploité par le Calendrier, les Statistiques, le
        //   Backtesting et le ROI/Value. La délégation à la cascade unique
        //   supprime la cause : la branche Quarté+ ne peut plus être oubliée
        //   dans une copie.
        final typePari = cascadeRecommandation(
          course: course,
          seuils: seuils,
          scoreConf: scoreConf,
          score2nd: partantsClasses.length >= 2
              ? partantsClasses[1].scoreIA
              : null,
          score3: partantsClasses.length >= 3
              ? partantsClasses[2].scoreIA
              : null,
          score4: partantsClasses.length >= 4
              ? partantsClasses[3].scoreIA
              : null,
          coteTop: coteTop,
        ).typePari;

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
    // ★ B5c-RDR-01-c : même raison que pour les pronostics. Cette tâche
    //   interroge le réseau et déclenche `EloService.mettreAJourApresArrivee`
    //   (écriture ELO). Une opération obsolète ne doit pas être relancée.
    _enMicrotacheSiNonObsolete(
      _generationCache,
      _recupererResultatsBatch,
      'résultats',
    );
  }

  Future<void> _recupererResultatsBatch() async {
    // ★ B5c-RDR-03 — capture de génération pour le cycle de récupération des
    //   résultats officiels. La méthode est entièrement asynchrone et attend
    //   le RÉSEAU, suspension invisible de tous les registres de drainage :
    //   un reset complet peut donc s'exécuter pendant elle. La capture est
    //   faite avant tout `await`.
    final generationAuDemarrage = _generationCache;
    // ★ B5c-RDR-03 — DEUX compteurs DISTINCTS, capturés séparément.
    //   `_estObsolete()` ci-dessous compare à `_generationCache` de CE service
    //   (barrière DataRefresh). La garde d'`enregistrerResultat()` compare à
    //   `IaMemoryService._generationCache`. Transmettre l'un à la place de
    //   l'autre ferait comparer deux échelles indépendantes : sur un état neuf
    //   (DataRefresh = 5, IaMemory = 0) tout enregistrement serait refusé à
    //   tort. On capture donc la génération de `IaMemoryService` ICI, avant
    //   tout `await`, et c'est elle qu'on transmet.
    final generationIaAuDemarrage = IaMemoryService.instance.generationCache;
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

        // ═══════════════ POINT DE REPRISE ASYNCHRONE ═══════════════════════
        //  L'appel réseau ci-dessus a pu durer plusieurs secondes, pendant
        //  lesquelles un reset complet s'est éventuellement déroulé. On ne
        //  réintroduit plus rien : ni résultat, ni ELO, ni apprentissage.
        if (_estObsolete(generationAuDemarrage)) {
          if (kDebugMode) {
            debugPrint('[DataRefresh] ⏭️ résultat R${numR}C$numC abandonné : '
                'reset survenu pendant la récupération réseau '
                '(génération $generationAuDemarrage → $_generationCache)');
          }
          return;
        }

        // ★ A7 — OPTION A : on CAPTURE le booléen. Il signifie exactement
        //   « résultat nouveau accepté par IaMemoryService » : `true` ssi la
        //   course est passée de non résolue à résolue PAR CET APPEL.
        //   `false` couvre : génération/reset, résultat déjà connu, et
        //   consignation en archive seule.
        final bool resultatEnregistre =
            await IaMemoryService.instance.enregistrerResultat(
          courseKey:    p.courseKey,
          arriveeReelle: arrivee,
          // Génération d'`IaMemoryService`, capturée à l'ENGAGEMENT du cycle :
          // la garde d'`enregistrerResultat()` la compare au compteur de CE
          // service. Toute la branche ci-dessus a déjà été validée sur la
          // génération de `DataRefreshService`.
          generationAppelante: generationIaAuDemarrage,
        );

        // ★ v9.0 : Mettre à jour l'ELO après chaque arrivée officielle
        // ★ A7 — OPTION A : UNIQUEMENT si le résultat est NOUVEAU.
        //   Avant cette correction, l'appel était INCONDITIONNEL : une arrivée
        //   déjà connue (rejouée d'un cycle à l'autre, ou résolue entre-temps
        //   par un autre chemin) ré-appliquait le delta ELO à chaque passage.
        //   `EloService.mettreAJourApresArrivee()` n'a aucune garde
        //   d'idempotence et ne reçoit pas `courseKey` : il ne peut pas se
        //   protéger lui-même. Le conditionnement est donc fait ICI.
        if (resultatEnregistre) {
          // ★ A7 (3.2) : l'appel est ATTENDU. Sans conséquence sur le métier
          // (voir la note de `_mettreAJourEloApresArrivee`), et c'est ce qui
          // rend l'issue de la persistance ELO observable.
          await _mettreAJourEloApresArrivee(p.courseKey, arrivee);
        } else if (kDebugMode) {
          debugPrint('[DataRefresh] ⏭️ ELO non mis à jour pour '
              'R${numR}C$numC : arrivée déjà traitée (ou consignée en archive '
              'seule) — voir IaMemoryService.enregistrerResultat()');
        }

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

  // ── Mise à jour ELO après une arrivée officielle ────────────────────
  //
  // ★ A7 (3.2) : le `.ignore()` est SUPPRIMÉ. Il rendait invisible l'issue
  //   de la SEULE écriture ELO de production. L'appel est désormais attendu
  //   et son issue est journalisée.
  //
  //   POURQUOI ATTENDRE ICI NE CHANGE RIEN AU MÉTIER (mesuré) :
  //   cette méthode n'est appelée QUE depuis `_recupererResultatsBatch`
  //   (l.1192), elle-même lancée exclusivement par `_recupererResultatsAuto`
  //   (l.1106) via `_enMicrotacheSiNonObsolete`, donc dans une microtâche que
  //   PERSONNE n'attend (`_doRefresh` l.702 ne l'attend pas). Aucun écran,
  //   aucune notification, aucun `refresh()` ne peut être ralenti.
  //
  //   Aucun rejeu n'est déclenché, quelle que soit l'issue. Les décisions
  //   métier (enregistrement, notification, comptage) sont INCHANGÉES.
  Future<void> _mettreAJourEloApresArrivee(
      String courseKey, List<int> arrivee) async {
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
        typeCourse = course.type; // ★ v9.92 : type pour ELO par discipline
        break;
      }
    }
    if (partants == null || partants.isEmpty) {
      if (kDebugMode) {
        debugPrint('[DataRefresh] ⏭️ ELO non recalculé pour '
            'R${numR}C$numC : partants indisponibles');
      }
      return;
    }

    // ★ A7 (3.3-B2-e) — TRANSMISSION DE L'IDENTITÉ DE COURSE.
    //   `courseKey` est le paramètre REÇU de `_recupererResultatsBatch`
    //   (l.1195 : `p.courseKey`). Ce n'est ni une reconstruction, ni une
    //   dérivation depuis `numR`/`numC` : une identité fabriquée ne serait pas
    //   comparable à celle du registre. Sans elle, `EloService` ne peut ni
    //   vérifier qu'une course a déjà été appliquée, ni journaliser : il
    //   refuse alors l'application (aucune mutation ELO non journalisée).
    final EtatPersistanceElo etat =
        await EloService.instance.mettreAJourApresArrivee(
      arrivee:    arrivee,
      partants:   partants,
      discipline: typeCourse, // ★ v9.92
      courseKey:  courseKey,  // ★ B2-e — identité réelle, jamais reconstruite
    );

    // ★ A7 (3.2) : l'issue est SIGNALÉE, jamais ignorée. Aucun rejeu n'est
    // tenté sur `refusee`/`echouee` : la persistance n'est pas confirmée,
    // elle n'est pas prouvée absente non plus, et rejouer écraserait une
    // valeur peut-être déjà écrite.
    if (etat != EtatPersistanceElo.persistee) {
      debugPrint('[DataRefresh] ⚠️ ELO R${numR}C$numC : ratings NON '
          'CONFIRMÉS (${etat.name}) — aucun rejeu tenté');
    }
  }

  /// Récupère l'arrivée officielle d'une course depuis les rapports PMU.
  ///
  /// ★ FINALISATION A6 (P4) — DÉCISION PARTAGÉE, PLUS DE RECONSTRUCTION.
  ///
  /// AVANT : `E_SIMPLE_GAGNANT` était inséré en tête puis les rapports
  /// `E_SIMPLE_PLACE` étaient AJOUTÉS dans l'ordre fourni par l'API. Cet ordre
  /// n'est pas celui de l'arrivée officielle : les rangs 2 et 3 étaient donc
  /// INVENTÉS. Aucune garde de longueur n'existait : un seul cheval devenait
  /// une « arrivée », puis `enregistrerResultat()` l'inscrivait définitivement
  /// — la garde d'idempotence interdisant toute réécriture ultérieure.
  ///
  /// APRÈS : décision unique et PARTAGÉE avec P1, P2 et P5
  /// (`analyserRapportsPmu`). Une liste vide signifie « aucune arrivée
  /// exploitable pour l'instant » et n'écrit rien : la course reste non
  /// résolue, donc récupérable au cycle suivant.
  Future<List<int>> _fetchArriveeOfficielle(
      int numR, int numC, String dateStr) async {
    // ═══════════════════════════════════════════════════════════════════
    //  ★ ACQUISITION CANONIQUE — plus d'URL ni de délai construits ici.
    //
    //  L'acquisition passe par `AcquisitionPmu`, point de passage unique :
    //  une seule autorité d'URL, un seul délai, et surtout une NATURE de
    //  réponse que ce service n'a plus à deviner. Avant, ce site rendait
    //  `[]` aussi bien pour une liste vide que pour HTTP 500 ou une coupure
    //  réseau — sans que l'appelant puisse faire la différence.
    //
    //  ⚠️ LE DÉLAI EST CONSERVÉ À 15 s, valeur historique de CE site.
    //     L'uniformiser sur 20 s changerait un comportement non demandé.
    // ═══════════════════════════════════════════════════════════════════
    final reponse = await AcquisitionPmu.get(
      'programme/$dateStr/R$numR/C$numC/rapports-definitifs',
      delai: const Duration(seconds: 15),
    );

    if (!reponse.estSucces) {
      // La cause est NOMMÉE, jamais confondue avec « aucune arrivée ».
      if (kDebugMode) {
        debugPrint('[DataRefresh] ⏸️ R${numR}C$numC : acquisition — '
            '${reponse.nature.name}${reponse.details != null ? " (${reponse.details})" : ""}');
      }
      return const <int>[];
    }

    final charge = reponse.charge;
    if (charge is! List) {
      if (kDebugMode) {
        debugPrint('[DataRefresh] ⏸️ R${numR}C$numC : charge non-listable');
      }
      return const <int>[];
    }

    // ═══════════════════════════════════════════════════════════════════
    //  ★ A6 — L0 PRIORITAIRE + CONTRÔLE D'APPARTENANCE (P4).
    //
    //  AVANT : ce chemin ignorait totalement L0 et n'exerçait aucun contrôle
    //  sur les numéros reçus. Une arrivée contenant un numéro absent des
    //  partants pouvait donc être enregistrée.
    //
    //  ICI, la liste des partants EST DISPONIBLE : `_partantsDeLaCourse`
    //  la lit dans `_reunions` (données déjà chargées par cet écran). Le
    //  contrôle est donc effectif : tout numéro inconnu fait REJETER
    //  l'arrivée. Si les partants ne sont pas disponibles, la fonction
    //  retourne `null` et AUCUN rejet n'est prononcé — une absence de
    //  données n'est pas une preuve d'incohérence.
    //
    //  L0 est consulté EN PREMIER. S'il contient un ex æquo, l'arrivée ne
    //  doit pas être transmise à l'apprentissage : la fonction retourne une
    //  liste vide, ce qui suffit car l'appelant n'appelle `enregistrerResultat`
    //  ET `_mettreAJourEloApresArrivee` qu'après `if (arrivee.isEmpty) continue;`.
    //  Aucune signature, aucun mécanisme protégé n'est modifié.
    // ═══════════════════════════════════════════════════════════════════
    final DecisionArriveeOfficielle decision;
    try {
      decision = deciderArriveeOfficielle(
        groupesL0: ArriveeOfficielleService.instance
            .arrivee('R${numR}C$numC' '_$dateStr'),
        rapportsPmu: charge,
        partants: _partantsDeLaCourse(numR, numC),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DataRefresh] ⏸️ R${numR}C$numC : rapports illisibles ($e)');
      }
      return const <int>[];
    }

    if (decision.aDesExAequo) {
      // Ex æquo officiel : affichable via L0, mais JAMAIS enregistrable.
      // Liste vide → ni apprentissage, ni mise à jour ELO en aval.
      if (kDebugMode) {
        debugPrint('[DataRefresh] ⚠️ R${numR}C$numC : ${decision.motif}');
      }
      return const <int>[];
    }

    if (!decision.disponible || !decision.peutEnregistrer) {
      if (kDebugMode) {
        debugPrint('[DataRefresh] ⏸️ R${numR}C$numC : arrivée REFUSÉE — '
            '${decision.motif} (réessai possible au prochain cycle)');
      }
      return const <int>[];
    }

    return decision.arriveePlate;
  }

  /// Ensemble FIABLE des numéros partants d'une course, ou `null`.
  ///
  /// PURE : lecture seule de `_reunions`, déjà en mémoire. `null` si la
  /// course ou ses partants ne sont pas disponibles — auquel cas le contrôle
  /// d'appartenance est IMPOSSIBLE et ne doit produire aucun rejet.
  Set<int>? _partantsDeLaCourse(int numR, int numC) {
    for (final reunion in _reunions) {
      final rMatch = RegExp(r'R(\d+)').firstMatch(reunion.code);
      final rNum = rMatch != null ? int.tryParse(rMatch.group(1) ?? '') ?? 0 : 0;
      if (rNum != numR) continue;
      final course = reunion.courses.where((c) => c.numCourse == numC).firstOrNull;
      if (course == null) return null;
      if (course.partants.isEmpty) return null;
      final numeros = <int>{};
      for (final p in course.partants) {
        final n = int.tryParse(p.numero);
        if (n != null) numeros.add(n);
      }
      return numeros.isEmpty ? null : numeros;
    }
    return null;
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

  // ═══════════════════════════════════════════════════════════════════════
  //  ★ B5c-RDR-01-b — VIDAGE RAM POUR LE RESET COMPLET.
  //
  //  POURQUOI : `BackupService.reinitialiserComplet()` efface le disque, mais
  //  ce service gardait tout son état EN MÉMOIRE. Mesuré V31 R01-H : après un
  //  reset terminé, `_reunions` contenait encore la réunion d'AVANT le reset
  //  (`lieu=RAM-SURVIT`), et l'UI la servait telle quelle
  //  (home_screen.dart l.46 lit `DataRefreshService.instance.reunions`).
  //
  //  C'est la MÊME cause que celles traitées en B5/B5c pour EloService,
  //  PronosticResultatsRepository, QuasiGrosParisService, IaBadgesService et
  //  IaUserPrefsService : le disque est vidé, la RAM non. D'où le nommage
  //  identique, pour que l'asymétrie ne puisse plus passer inaperçue.
  //
  //  CE QUE CETTE MÉTHODE NE FAIT **PAS**, ET NE DOIT PAS FAIRE :
  //    • aucun `_doRefresh()` / `refresh()` → pas de récupération réseau ;
  //    • aucun `_sauvegarderCacheLocal()` → on ne RECRÉE pas les clés que
  //      R01-a vient de supprimer (même piège que `restaurerDepuisBackup({})`
  //      ou `reinitialiser()` d'EloService, qui réécrivaient une clé vide) ;
  //    • aucun calcul IA, aucun appel à `IaMemoryService` ;
  //    • AUCUN `notifyListeners()` — l'autorisation de cette correction
  //      exclut toute notification métier supplémentaire. Conséquence
  //      assumée : l'UI ne se rafraîchit qu'au prochain événement qui notifie
  //      déjà (fin de `_doRefresh`, ou le `notifyListeners()` de fin de
  //      `reinitialiserComplet()` côté BackupService).
  //
  //  `_lastError` EST remis à `null` : l'UI l'affiche directement
  //  (home_screen.dart l.2306 : `lastError ?? ''`, programme_screen.dart
  //  l.73/91/117/126). Sans cette remise à zéro, une erreur réseau ANTÉRIEURE
  //  au reset resterait affichée alors que plus rien ne la justifie : ce
  //  serait un signalement faux, de la même famille que celui documenté en
  //  R-DR-04-G. `_doRefresh` la remet déjà à `null` à son démarrage (l.499)
  //  et à sa réussite (l.528), donc cette remise à zéro est cohérente avec
  //  le cycle de vie existant et n'invente aucune règle.
  // ═══════════════════════════════════════════════════════════════════════
  void viderMemoirePourResetComplet() {
    // `_reunions` est une `List` : on la vide SUR PLACE plutôt que de la
    // réassigner, comme le fait `executerResetComplet` d'IaMemoryService pour
    // ses collections. Aucun getter ne l'expose mutable, donc les deux formes
    // sont équivalentes ici ; on garde la forme « sur place » par cohérence.
    _reunions.clear();

    // État de détection des non-partants : sans ce vidage, le premier refresh
    // post-reset comparerait les nouveaux partants à l'état d'AVANT le reset
    // et pourrait notifier des « non-partants » fantômes.
    _partantsParCourse.clear();

    // Anti-doublon des notifications de non-partants : le vider autorise à
    // re-notifier les mêmes numéros après un reset, ce qui est le
    // comportement attendu d'une remise à zéro complète.
    _nonPartantsNotifies.clear();

    _lastRefresh = null;
    _lastError = null;

    if (kDebugMode) {
      debugPrint('[DataRefresh] 🧹 Mémoire vidée (reset complet, '
          'disque non réécrit)');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  ★ B5c-RDR-01-c — BARRIÈRE DE RESET DU SERVICE.
  //
  //  Appelée EXCLUSIVEMENT par `BackupService.reinitialiserComplet()`, en
  //  TÊTE, comme `AlertService`, `IaMemoryService` et `EloService`. Elle
  //  encadre l'effacement disque : c'est la seule position qui permette de
  //  refuser une écriture NAISSANT pendant l'effacement.
  //
  //  TROIS ÉTAPES, dans cet ordre et sans interchangeabilité :
  //    1. fermer la barrière (`_resetEnCours`) et incrémenter la génération —
  //       plus aucune écriture ne NAÎT, et toute opération engagée avant est
  //       définitivement invalide, y compris après réouverture ;
  //    2. DRAINER les écritures de cache déjà engagées (registre) : sans
  //       cela, un `setString` suspendu se terminerait APRÈS l'effacement et
  //       recréerait la clé (scénario mesuré V31b R01-J) ;
  //    3. exécuter le callback d'effacement, puis vider la RAM dans le
  //       `finally` — INCONDITIONNEL, y compris si l'effacement lève.
  //
  //  POURQUOI LA RAM EST VIDÉE ICI ET PLUS DANS `BackupService` : R-DR-01-b
  //  l'appelait après la fermeture des barrières. C'était correct pour un
  //  rafraîchissement ARRÊTÉ, mais pas pour un rafraîchissement EN VOL : ses
  //  branches d'écriture sont désormais refusées, donc plus rien ne peut
  //  repeupler la RAM après ce vidage. Le déplacement rend l'invariant
  //  démontrable au lieu d'être espéré.
  // ═══════════════════════════════════════════════════════════════════════
  Future<void> executerResetComplet(
      Future<void> Function() supprimerLesCles) async {
    _resetEnCours = true;   // 1. plus aucune écriture ne NAÎT
    _generationCache++;     //    verrou définitif sur les engagées
    try {
      // 2. Drain : on attend la fin de toutes les écritures de cache
      //    déjà engagées. Boucle (et non `Future.wait` unique) pour la même
      //    raison que dans AlertService : `whenComplete` s'exécute en
      //    microtâche APRÈS la complétion.
      while (_ecrituresEnCours.isNotEmpty) {
        final enVol = List<Future<bool>>.from(_ecrituresEnCours);
        try {
          await Future.wait(enVol);
        } catch (_) {
          // Une écriture qui échoue ne doit jamais faire échouer le reset.
          // Elle a déjà été journalisée par `_executerEcritureCache`.
        }
      }

      // 3. Effacement disque — TOUJOURS sous barrière.
      await supprimerLesCles();
    } finally {
      // 4. Vidage RAM INCONDITIONNEL puis libération de la barrière.
      //    Le vidage est fait AVANT la réouverture : un rafraîchissement qui
      //    repartirait à la microtâche suivante trouverait une RAM déjà vide.
      viderMemoirePourResetComplet();
      _resetEnCours = false;
    }
    if (kDebugMode) {
      debugPrint('[DataRefresh] 🧹 Reset complet effectué '
          '(génération $_generationCache, disque non réécrit)');
    }
  }

  /// Exécute [action] sous barrière, écritures de cache uniquement.
  ///
  /// ⚠️ POINT CRUCIAL : entre le franchissement du contrôle 2 et l'ajout au
  ///    registre, il n'existe AUCUN `await`. Une suspension glissée ici
  ///    permettrait à une écriture de franchir les contrôles sans être vue du
  ///    drain — c'est exactement le défaut que cette méthode corrige.
  Future<bool> _ecrireProtegeCache(
      Future<void> Function(SharedPreferences prefs) action) async {
    // Contrôle 1 — à la naissance : aucune écriture ne doit pouvoir DÉMARRER.
    if (_resetEnCours) return false;

    final generation = _generationCache;
    final prefs = await SharedPreferences.getInstance();

    // Contrôle 2 — rattrape celles qui étaient suspendues sur `getInstance()`
    // quand le reset a commencé.
    if (_resetEnCours || generation != _generationCache) return false;

    // ↓↓↓ AUCUN `await` de ce point jusqu'au `add` ↓↓↓
    final Future<bool> f = _executerEcritureCache(prefs, action);
    _ecrituresEnCours.add(f);
    f.whenComplete(() => _ecrituresEnCours.remove(f)).ignore();
    // ↑↑↑ aucune écriture ne franchit le contrôle 2 sans être vue du drain ↑↑↑

    return f;
  }

  /// Corps de l'écriture, isolé pour que `_ecrireProtegeCache` obtienne la
  /// future AVANT le premier `await`. L'exception est capturée ici : le drain
  /// peut attendre la future sans erreur asynchrone non gérée.
  Future<bool> _executerEcritureCache(
      SharedPreferences prefs,
      Future<void> Function(SharedPreferences prefs) action) async {
    try {
      await action(prefs);
      return true;
    } catch (e) {
      _derniereErreurCache = 'exception : $e';
      debugPrint('[DataRefresh] ⚠️ Erreur écriture cache: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }
}
