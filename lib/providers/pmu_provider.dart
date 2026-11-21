import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pmu_models.dart';
import '../services/pmu_api_service.dart';
import '../services/ia_memory_service.dart';
import '../utils/type_pari_utils.dart'
    show estEtatSansPariRecommande, estTypeGagnantPlace;

enum LoadingState { idle, loading, success, error }

class PmuProvider extends ChangeNotifier {
  List<PmuReunion> _reunions = [];
  final List<UserPrediction> _predictions = [];
  // Cache des pronostics Equidia : clé = "R1C1"
  final Map<String, EquidiaPronostics> _equidiaCache = {};
  LoadingState _loadingState = LoadingState.idle;
  String _errorMessage = '';
  String _filter = 'Toutes';
  String _dateStr = '';

  static const String _prefsKey = 'user_predictions_v2';

  PmuProvider() {
    _dateStr = _todayDateStr();
    _loadSavedPredictions().then((_) => loadProgramme());
  }

  static String _todayDateStr() {
    final now = DateTime.now();
    final d = now.day.toString().padLeft(2, '0');
    final m = now.month.toString().padLeft(2, '0');
    final y = now.year.toString();
    return '$d$m$y';
  }

  List<PmuReunion> get reunions => _reunions;
  List<UserPrediction> get predictions =>
      List.unmodifiable(_predictions.reversed.toList());
  Map<String, EquidiaPronostics> get equidiaCache => _equidiaCache;
  LoadingState get loadingState => _loadingState;
  String get errorMessage => _errorMessage;
  String get filter => _filter;
  String get dateStr => _dateStr;

  // ─── Réunions françaises uniquement ──────────────────────────────────────
  /// Uniquement les réunions PMU France (exclut Pays-Bas, GB, Chili, etc.)
  List<PmuReunion> get frenchReunions =>
      _reunions.where((r) => r.isFrench).toList();

  /// Toutes courses confondues (toutes réunions y compris étrangères)
  List<PmuCourse> get allCourses =>
      _reunions.expand((r) => r.courses).toList();

  /// Courses françaises uniquement
  List<PmuCourse> get frenchCourses =>
      frenchReunions.expand((r) => r.courses).toList();

  List<PmuCourse> get filteredCourses {
    // On filtre sur les courses françaises uniquement
    final all = frenchCourses;
    switch (_filter) {
      case 'À venir':
        return all.where((c) => c.status == CourseStatus.aVenir).toList();
      case 'En cours':
        return all.where((c) => c.status == CourseStatus.enCours).toList();
      case 'Terminées':
        return all.where((c) => c.status == CourseStatus.terminee).toList();
      default:
        return all;
    }
  }

  List<PmuCourse> get upcomingCourses {
    final courses = frenchCourses
        .where((c) => c.status == CourseStatus.aVenir)
        .toList()
      ..sort((a, b) => a.heureDepart.compareTo(b.heureDepart));
    return courses;
  }

  List<PmuCourse> get topCourses {
    final sorted = List<PmuCourse>.from(frenchCourses)
      ..sort((a, b) => b.montantPrix.compareTo(a.montantPrix));
    return sorted.take(5).toList();
  }

  int get totalPredictions => _predictions.length;
  int get correctPredictions =>
      _predictions.where((p) => p.isCorrect == true).length;
  int get lostPredictions =>
      _predictions.where((p) => p.isCorrect == false).length;
  int get pendingPredictions =>
      _predictions.where((p) => p.isCorrect == null).length;
  double get successRate =>
      totalPredictions > 0 ? (correctPredictions / totalPredictions) * 100 : 0;

  /// Total des gains nets (gains - pertes) depuis le début
  ///
  /// ★ LOT G+P / AFFICHAGE : un gain G+P NON ÉTABLI n'est pas additionné.
  ///
  ///   La formule de `gainNet` est inchangée ; c'est la CONTRIBUTION d'un
  ///   ticket à un total affiché qui est filtrée. Le montant exclu est
  ///   exactement celui qui n'est pas prouvé (produit d'une seule cote sur
  ///   une mise à deux composantes). Les pertes G+P (`-montantMise`), les
  ///   gains G+P officiels et TOUS les autres types de paris restent comptés
  ///   à l'identique : le prédicat rend `true` hors G+P et sur un `-mise`.
  double get totalGainsNet {
    return _predictions.fold(
        0.0, (sum, p) => sum + (p.gainGagnantPlaceEtabli ? p.gainNet : 0.0));
  }

  /// Total misé (toutes les prédictions avec une mise définie)
  ///
  /// ★ LOT G+P : la mise réellement engagée d'un G+P est la SOMME de ses deux
  ///   composantes (`miseTotaleEngagee`), jamais `montantMise` qui n'en
  ///   porte qu'une. Hors G+P, la valeur est strictement identique.
  double get totalMise {
    return _predictions.fold(0.0, (sum, p) => sum + _miseEngageeDe(p));
  }

  /// Mise réellement engagée d'un ticket, telle qu'elle doit être totalisée.
  ///
  /// Le seul cas où ce n'est pas `montantMise` est le Gagnant + Placé dont les
  /// DEUX composantes sont renseignées. Si elles sont incomplètes,
  /// `miseTotaleEngagee` vaut `null` : on retombe alors sur `montantMise`
  /// (comportement historique), sans jamais inventer de montant.
  double _miseEngageeDe(UserPrediction p) =>
      p.miseTotaleEngagee ?? p.montantMise;

  /// Total gagné — Option A : retour total encaissé (mise × cote)
  /// Ex: 2 € misés à cote ×1.9 → retour = 3.80 € (pas le profit net 1.80 €)
  ///
  /// ★ LOT G+P / AFFICHAGE : un gain G+P non établi ne produit pas de retour
  ///   affichable. `retourTotal` n'est pas modifié ; sa contribution à un
  ///   total est filtrée par le même prédicat que `totalGainsNet`.
  double get totalGagnes {
    return _predictions
        .where((p) => p.isCorrect == true)
        .fold(
            0.0,
            (sum, p) =>
                sum + (p.gainGagnantPlaceEtabli ? p.retourTotal : 0.0));
  }

  /// Total perdu
  ///
  /// ★ LOT G+P : la perte d'un G+P est la mise engagée des DEUX composantes.
  double get totalPerdu {
    return _predictions
        .where((p) => p.isCorrect == false)
        .fold(0.0, (sum, p) => sum + _miseEngageeDe(p));
  }

  /// Prédictions filtrées par plage de dates
  List<UserPrediction> getPredictionsByDateRange(DateTime? debut, DateTime? fin) {
    return _predictions.where((p) {
      if (debut != null && p.createdAt.isBefore(debut)) return false;
      if (fin != null && p.createdAt.isAfter(fin.add(const Duration(days: 1)))) return false;
      return true;
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Gains nets sur une plage de dates
  ///
  /// ★ LOT G+P / AFFICHAGE : même prédicat que `totalGainsNet` — un gain G+P
  ///   non établi n'entre pas dans un total affiché.
  double getGainsNetByDateRange(DateTime? debut, DateTime? fin) {
    return getPredictionsByDateRange(debut, fin).fold(
        0.0, (sum, p) => sum + (p.gainGagnantPlaceEtabli ? p.gainNet : 0.0));
  }

  PmuReunion? getReunionByNum(int num) {
    try {
      return _reunions.firstWhere((r) => r.numOfficiel == num);
    } catch (_) {
      return null;
    }
  }

  void setFilter(String f) {
    _filter = f;
    notifyListeners();
  }

  // ─── Programme PMU ────────────────────────────────────────────────────────

  Future<void> loadProgramme({bool refresh = false}) async {
    if (_loadingState == LoadingState.loading && !refresh) return;
    _loadingState = LoadingState.loading;
    _errorMessage = '';
    notifyListeners();

    try {
      final reunions = await PmuApiService.fetchProgramme(dateStr: _dateStr);
      _reunions = reunions;
      _loadingState = LoadingState.success;
      notifyListeners();

      // Charger automatiquement tous les participants en arrière-plan
      // après que le programme est disponible
      loadAllFrenchParticipants();
    } catch (e) {
      _loadingState = LoadingState.error;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      if (kDebugMode) debugPrint('PmuProvider.loadProgramme error: $e');
      notifyListeners();
    }
  }

  /// Charge les participants d'une course depuis l'API PMU réelle.
  /// 
  /// Règles de rechargement :
  /// - Si jamais chargé → charge
  /// - Si déjà chargé MAIS liste vide → retente (API peut ne pas avoir encore les données)
  /// - Si déjà chargé ET liste non-vide → ne recharge pas (données déjà OK)
  /// - forceReload = true → recharge toujours (bouton Réessayer)
  Future<void> loadParticipants(PmuCourse course, {bool forceReload = false}) async {
    // Ne pas recharger si on a déjà des participants valides
    if (!forceReload && course.participantsLoaded && course.participants.isNotEmpty) {
      return;
    }

    // NE PAS appeler notifyListeners() ici — évite les rebuilds intermédiaires
    // qui afficheraient une liste vide pendant le fetch
    course.participantsLoaded = false;

    try {
      final participants = await PmuApiService.fetchParticipants(
          _dateStr, course.numReunion, course.numOrdre);
      course.participants = participants;
      course.participantsLoaded = true;
      if (kDebugMode) {
        debugPrint('✅ R${course.numReunion}C${course.numOrdre}: ${participants.length} partants réels');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('loadParticipants error: $e');
      course.participants = [];
      course.participantsLoaded = true;
    }
    // Un seul notifyListeners() à la fin, quand les données sont prêtes
    notifyListeners();
  }

  /// Charge les participants de TOUTES les courses françaises en parallèle
  /// puis notifie une seule fois — utilisé par conseils et best_bet
  Future<void> loadAllFrenchParticipants({bool forceReload = false}) async {
    final courses = frenchCourses;
    if (courses.isEmpty) return;

    // Charger toutes les courses en parallèle (pas séquentiellement)
    await Future.wait(
      courses.map((c) async {
        if (forceReload || !c.participantsLoaded || c.participants.isEmpty) {
          c.participantsLoaded = false;
          try {
            final participants = await PmuApiService.fetchParticipants(
                _dateStr, c.numReunion, c.numOrdre);
            c.participants = participants;
            c.participantsLoaded = true;
            if (kDebugMode) {
              debugPrint('✅ R${c.numReunion}C${c.numOrdre}: ${participants.length} partants');
            }
          } catch (e) {
            c.participants = [];
            c.participantsLoaded = true;
            if (kDebugMode) debugPrint('loadParticipants error R${c.numReunion}C${c.numOrdre}: $e');
          }
        }
      }),
    );
    // Un seul notifyListeners() pour tout le batch
    notifyListeners();
  }

  Future<EquidiaPronostics?> loadEquidiaPronostics(PmuCourse course) async {
    final key = 'R${course.numReunion}C${course.numOrdre}';
    if (_equidiaCache.containsKey(key)) return _equidiaCache[key];
    try {
      final prono = await PmuApiService.fetchPronostics(
          _dateStr, course.numReunion, course.numOrdre);
      if (prono != null && !prono.isEmpty) {
        _equidiaCache[key] = prono;
        notifyListeners();
        return prono;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('loadEquidiaPronostics error: $e');
    }
    return null;
  }

  EquidiaPronostics? getEquidiaPronostics(int numR, int numC) {
    return _equidiaCache['R${numR}C$numC'];
  }

  // ─── Gestion des prédictions avec persistance ─────────────────────────────

  /// Méthode publique pour recharger les prédictions depuis le stockage local
  Future<void> reloadPredictions() => _loadSavedPredictions();

  /// Charge les sélections sauvegardées localement
  Future<void> _loadSavedPredictions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_prefsKey) ?? [];
      _predictions.clear();
      final seenIds = <String>{};
      for (final str in raw) {
        try {
          final map = jsonDecode(str) as Map<String, dynamic>;
          final pred = UserPrediction.fromJson(map);
          // Éviter les doublons par ID au chargement
          if (seenIds.add(pred.id)) {
            _predictions.add(pred);
          }
        } catch (e) {
          if (kDebugMode) debugPrint('Erreur parsing prédiction: $e');
        }
      }
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('_loadSavedPredictions error: $e');
    }
  }

  /// Sauvegarde toutes les prédictions localement
  Future<void> _savePredictions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = _predictions.map((p) => jsonEncode(p.toJson())).toList();
      await prefs.setStringList(_prefsKey, raw);
    } catch (e) {
      if (kDebugMode) debugPrint('_savePredictions error: $e');
    }
  }

  /// Ajoute une prédiction (plusieurs paris sur la même course autorisés)
  void addPrediction(UserPrediction pred) {
    // Ne pas supprimer les paris existants : l'ID unique (timestamp) suffit
    _predictions.add(pred);
    _savePredictions();
    notifyListeners();
  }

  /// Valide ou invalide un pronostic + enregistre la mise et le gain
  void validatePrediction(String id, {
    required bool isCorrect,
    double? montantMise,
    double? gainRealise,
  }) {
    final idx = _predictions.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final old = _predictions[idx];

    // ★ LOT C3 — GARDE DÉFENSIVE « AUCUN PARI RECOMMANDÉ ».
    //
    //   Un ticket `'À surveiller'` (ou de type vide) n'est pas un pari :
    //   il ne doit jamais recevoir de mise, de gain ni de perte, quelle que
    //   soit la voie d'écriture qui l'atteint.
    //
    //   Cette garde ne REMPLACE aucune garde existante : elle s'ajoute.
    //   Elle couvre notamment les voies qui ne passent par aucun dialogue
    //   corrigé en C2 — restauration de sauvegarde, synchronisation
    //   automatique après arrivée (`alert_service.dart:2723`), résolution
    //   post-restauration (`profile_profil_tab.dart:1653`),
    //   `mes_paris_screen.dart:1455`.
    //
    //   Elle n'altère AUCUNE formule : `gainNet`, `retourTotal`, les deux
    //   formules T8b de `enregistrerDividendePmu` et la garde A-0 restent
    //   strictement inchangés. Elle empêche seulement l'écriture : le ticket
    //   garde `isCorrect == null` → « En attente » → exclu des statistiques
    //   par la règle préexistante `ia_memory_service.dart:5493`.
    //
    //   Aucune migration, aucune suppression, aucune réécriture : le ticket
    //   historique est laissé TEL QUEL.
    if (estEtatSansPariRecommande(old.typePari)) {
      if (kDebugMode) {
        debugPrint('⛔ validatePrediction ignorée : ticket sans pari '
            'recommandé (typePari="${old.typePari}", id=${old.id})');
      }
      return;
    }

    final mise = montantMise ?? old.montantMise;

    // ★ LOT G+P — AUCUN GAIN DÉDUIT D'UNE COTE POUR UN GAGNANT + PLACÉ.
    //
    //   Le repli ci-dessous (`(cote × mise) − mise`) n'a de sens que pour un
    //   pari MONO-COMPOSANTE : il applique la cote à la mise totale. Sur un
    //   Gagnant+Placé, `cote` est la cote du GAGNANT SEUL et la mise est la
    //   somme des DEUX composantes : ce produit ne vaut rien de réel. Il est
    //   exactement le montant fictif que la garde A-0 empêche déjà sur les
    //   trois voies automatiques (`alert_service.dart:2712`,
    //   `profile_profil_tab.dart:1652`, `mes_paris_screen.dart:1453`).
    //
    //   On n'invente donc RIEN : on n'écrit pas de gain (`gainRealise` reste
    //   `null`), et le gain officiel reste à établir par
    //   `enregistrerDividendePmu` à partir des rapports PMU.
    //   Point 6 du mandat : un dividende ambigu ne décide jamais d'un
    //   gagnant/perdant — a fortiori une cote Gagnant seule.
    //
    //   ⚠️ La formule elle-même est INCHANGÉE : c'est un aiguillage placé
    //   devant, exactement comme la garde C3 ci-dessus. `isCorrect` est
    //   toujours enregistré (résultat sportif), et le chemin « Perdu »
    //   (`gainRealise: -mise`, explicite) n'est pas concerné.
    final bool estGagnantPlace = estTypeGagnantPlace(old.typePari);
    final gain = gainRealise ??
        (estGagnantPlace
            ? null
            : (isCorrect && mise > 0 && old.cote > 0
                ? (old.cote * mise) - mise
                : (!isCorrect && mise > 0 ? -mise : null)));
    _predictions[idx]
      ..isCorrect = isCorrect
      ..montantMise = mise
      ..gainRealise = gain;
    _savePredictions();
    notifyListeners();
    _syncStatsTypesIA();
  }

  /// Met à jour le dividende PMU réel après la course
  /// Appelé automatiquement par le watchdog ou manuellement depuis paris_detail_screen
  /// ✅ Fix: isCorrect calculé depuis dividendePmuReel > 0 (jamais hardcodé à true)
  void enregistrerDividendePmu(String id, {
    required double dividendePmuReel,
    required String combinaisonPmu,
  }) {
    final idx = _predictions.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final old = _predictions[idx];

    // ★ LOT C1/C3 — GARDE DÉFENSIVE « AUCUN PARI RECOMMANDÉ ».
    //
    //   Cette méthode déclare un gagnant/perdant à partir de la SEULE valeur
    //   du dividende (`estGagnant = dividende > 0`), sans regarder le type de
    //   pari. Sur un ticket `'À surveiller'` (mise 0 €), elle écrirait un
    //   résultat financier sur un ticket qui n'a jamais été un pari.
    //
    //   On n'écrit donc RIEN : ni `dividendePmuReel`, ni `combinaisonPmu`,
    //   ni `isCorrect`, ni `gainRealise`. Le ticket reste « En attente ».
    //
    //   Les deux formules ci-dessous sont INCHANGÉES : la garde est un
    //   aiguillage placé AVANT elles, pas une réécriture.
    if (estEtatSansPariRecommande(old.typePari)) {
      if (kDebugMode) {
        debugPrint('⛔ enregistrerDividendePmu ignorée : ticket sans pari '
            'recommandé (typePari="${old.typePari}", id=${old.id})');
      }
      return;
    }

    // ✅ Fix: un dividende > 0 = pari gagnant, dividende = 0 = pari perdu
    final bool estGagnant = dividendePmuReel > 0;
    final gainNet = estGagnant
        ? (dividendePmuReel * old.montantMise) - old.montantMise
        : -old.montantMise; // pari perdu → on perd la mise
    _predictions[idx]
      ..dividendePmuReel = dividendePmuReel
      ..combinaisonPmu = combinaisonPmu
      ..isCorrect = estGagnant
      ..gainRealise = gainNet;
    _savePredictions();
    notifyListeners();
    _syncStatsTypesIA();
    if (kDebugMode) {
      debugPrint('✅ Dividende PMU enregistré: ×${dividendePmuReel.toStringAsFixed(2)} → gain ${gainNet.toStringAsFixed(2)}€');
    }
  }

  /// Tente de récupérer les dividendes PMU réels pour tous les paris
  /// combinés (Tiercé/Quarté/Quinté) dont le résultat est encore en attente.
  /// À appeler après la fin d'une course.
  Future<int> recupererDividendesPmuManquants() async {
    int nbMisAJour = 0;
    final enAttenteCombines = _predictions.where((p) =>
      p.isCorrect == null && p.estPariCombine).toList();

    for (final pred in enAttenteCombines) {
      try {
        final rapport = await PmuApiService.fetchDividendePourPari(
          date: pred.dateStr,
          numR: pred.numReunion,
          numC: pred.numCourse,
          typePari: pred.typePari,
          numerosJoues: pred.numerosJoues,
        );
        if (rapport != null && rapport.dividende > 0) {
          enregistrerDividendePmu(
            pred.id,
            dividendePmuReel: rapport.dividende,
            combinaisonPmu: rapport.combinaison,
            // ✅ Fix: isCorrect calculé automatiquement depuis dividende > 0
          );
          nbMisAJour++;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('❌ Erreur récupération dividende ${pred.id}: $e');
      }
    }
    if (nbMisAJour > 0) {
      if (kDebugMode) debugPrint('✅ $nbMisAJour dividendes PMU récupérés et enregistrés');
    }
    return nbMisAJour;
  }

  void _syncStatsTypesIA() {
    final allPreds = _predictions.map((p) => {
      'typePari':  p.typePari,
      'isCorrect': p.isCorrect,
      'gainNet':   p.gainNet,
    }).toList();
    // Appel async non bloquant — on ignore le Future
    IaMemoryService.instance.mettreAJourStatsTypes(allPreds);
  }

  /// Met à jour seulement la mise d'un pronostic (avant la course)
  void updateMise(String id, double montantMise) {
    final idx = _predictions.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    _predictions[idx].montantMise = montantMise;
    _savePredictions();
    notifyListeners();
  }

  /// Supprime une seule prédiction par son id
  void removePrediction(String id) {
    _predictions.removeWhere((p) => p.id == id);
    _savePredictions();
    notifyListeners();
  }

  /// Supprime toutes les prédictions
  void clearAllPredictions() {
    _predictions.clear();
    _savePredictions();
    notifyListeners();
  }

  bool hasPredictionForCourse(int numR, int numC) =>
      _predictions.any((p) => p.numReunion == numR && p.numCourse == numC);

  /// Retourne le PREMIER paris pour une course donnée.
  /// ⚠️ Utiliser [getAllPredictionsForCourse] si plusieurs paris sur la même course.
  UserPrediction? getPredictionForCourse(int numR, int numC) {
    try {
      return _predictions.firstWhere(
          (p) => p.numReunion == numR && p.numCourse == numC);
    } catch (_) {
      return null;
    }
  }

  /// ✅ Fix audit : retourne TOUS les paris pour une course donnée.
  /// Un utilisateur peut parier plusieurs types (ex: Simple Gagnant + Tiercé)
  /// sur la même course — [getPredictionForCourse] ignorait les paris suivants.
  List<UserPrediction> getAllPredictionsForCourse(int numR, int numC) {
    return _predictions
        .where((p) => p.numReunion == numR && p.numCourse == numC)
        .toList();
  }

  /// Retourne le premier paris non encore résolu pour une course.
  /// Utile pour les mises à jour de dividende : on cherche le pari en attente.
  UserPrediction? getPendingPredictionForCourse(int numR, int numC) {
    try {
      return _predictions.firstWhere(
          (p) => p.numReunion == numR && p.numCourse == numC && p.isCorrect == null);
    } catch (_) {
      return getPredictionForCourse(numR, numC); // fallback sur le premier
    }
  }
}
