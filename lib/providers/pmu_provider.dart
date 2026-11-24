import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pmu_models.dart';
import '../models/decision_gain_pmu.dart';
import '../services/pmu_api_service.dart';
import '../services/branchement_verdict_course.dart'
    show construireTicketPrediction, appliquerVerdictPrediction;
import '../services/resolution_gain_ticket_pmu.dart'
    show ResultatOfficielCourse, resoudreGainTicketDepuisDonnees;
// ★ B1-T12 / RACCORDEMENT TARDIF — conversion PURE verdict → montant officiel.
//
// ⚠️ `show` CIBLÉ SUR UNE SEULE FONCTION, et non sur le socle des gains PMU :
//    c'est ce qui permet à `PmuProvider` de produire un montant officiel SANS
//    devenir le dixième importateur de ce socle (garde B-0, liste fermée de
//    neuf comparée par égalité). Le type du paramètre reste INFÉRÉ — aucun
//    nom de type du socle n'apparaît ici.
//    ⚠️ AUCUNE CITATION DU NOM DE FICHIER DU SOCLE, même en commentaire : la
//       garde B-0 cherche cette sous-chaîne dans le texte BRUT, commentaires
//       inclus. La nommer ici ferait de ce fichier un « coupable » alors qu'il
//       ne l'importe pas. C'est la prose qui s'adapte, jamais la garde.
// ⚠️ AUCUN CYCLE : `enregistreur_verdict_gain_pmu.dart` n'importe que
//    `pmu_models`, le socle et le moteur ; il ne remonte jamais vers ce
//    provider. Vérifié par `grep` sur ses trois `import`.
import '../services/enregistreur_verdict_gain_pmu.dart'
    show montantOfficielDepuisVerdict;
// Le TYPE du verdict est nommé ici pour que la conversion ne soit jamais
// appelée sur un `dynamic` : un paramètre non typé déplacerait le contrôle de
// type à l'exécution, là où il n'y a plus de test possible. `VerdictGain` vit
// dans le moteur, qui n'est PAS le socle fermé surveillé par B-0 — importer le
// moteur ne change donc pas la liste des neuf.
import '../services/moteur_gain_pmu.dart' show VerdictGain;
import '../services/ia_memory_service.dart';
import '../utils/type_pari_utils.dart'
    show estEtatSansPariRecommande, estTypeGagnantPlace;

enum LoadingState { idle, loading, success, error }

/// ★ B1-T12 / LOT 2-C — ISSUE RÉELLE D'UNE MODIFICATION DE GAIN MANUEL.
///
/// Trois états pour la confirmation, jamais confondus : deux opérations
/// concurrentes demandant 10 € puis 20 € ne peuvent pas toutes deux être
/// déclarées « enregistrées » alors que le disque ne porte que 20 €.
enum IssueEcritureGain {
  /// Le montant DEMANDÉ est réellement présent sur le support persistant.
  confirme,

  /// La valeur demandée a été REMPLACÉE par une opération ultérieure.
  /// Elle n'est plus enregistrée : on ne l'annonce donc jamais comme telle.
  remplacee,

  /// La sauvegarde a échoué, mais mémoire et disque sont PROUVÉS alignés.
  echec,

  /// La sauvegarde ET la réconciliation ont échoué : la cohérence n'est PAS
  /// prouvée. Le ticket est bloqué jusqu'à récupération contrôlée.
  echecNonReconcilie,
}

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
  List<PmuCourse> get allCourses => _reunions.expand((r) => r.courses).toList();

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
    return _predictions.where((p) => p.isCorrect == true).fold(0.0,
        (sum, p) => sum + (p.gainGagnantPlaceEtabli ? p.retourTotal : 0.0));
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
  List<UserPrediction> getPredictionsByDateRange(
      DateTime? debut, DateTime? fin) {
    return _predictions.where((p) {
      if (debut != null && p.createdAt.isBefore(debut)) return false;
      if (fin != null && p.createdAt.isAfter(fin.add(const Duration(days: 1))))
        return false;
      return true;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
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
  Future<void> loadParticipants(PmuCourse course,
      {bool forceReload = false}) async {
    // Ne pas recharger si on a déjà des participants valides
    if (!forceReload &&
        course.participantsLoaded &&
        course.participants.isNotEmpty) {
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
        debugPrint(
            '✅ R${course.numReunion}C${course.numOrdre}: ${participants.length} partants réels');
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
              debugPrint(
                  '✅ R${c.numReunion}C${c.numOrdre}: ${participants.length} partants');
            }
          } catch (e) {
            c.participants = [];
            c.participantsLoaded = true;
            if (kDebugMode)
              debugPrint(
                  'loadParticipants error R${c.numReunion}C${c.numOrdre}: $e');
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

  /// ★ B-4.6 — sérialisation des écritures, sans décaler la PREMIÈRE.
  ///
  /// MESURÉ, pas supposé : sans sérialisation, deux `setStringList` rapprochés
  /// peuvent s'achever dans le désordre. Reproduction obtenue :
  /// ordre d'achèvement `[RECENT, ANCIEN]`, contenu final `[ANCIEN]` — le
  /// disque garde donc l'état ANCIEN et la modification récente est perdue.
  /// Les sept appels de [_savePredictions] étaient dans ce cas (aucun `await`).
  ///
  /// Choix de conception : on n'empile PAS les écritures. Si une écriture est
  /// en cours, on lève seulement un drapeau ; la boucle réécrit alors l'état
  /// COURANT avant de rendre la main. Conséquences :
  ///   • la toute première écriture démarre au même instant qu'avant
  ///     (aucun microtask ajouté — un test qui lisait le disque juste après
  ///     une validation continue de voir la donnée) ;
  ///   • la DERNIÈRE demande gagne toujours, quel que soit l'ordre
  ///     d'achèvement des `setStringList` ;
  ///   • aucune écriture intermédiaire n'est perdue durablement : la dernière
  ///     photographie est complète (`_predictions` entier).
  bool _ecritureEnCours = false;
  bool _ecritureRedemandee = false;
  Completer<bool>? _ecritureAttente;

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ B1-T12 / LOT 2-C — CONFIRMATION RÉELLE DES ÉCRITURES FINANCIÈRES
  //
  //  DÉFAUT MESURÉ AVANT D'ÉCRIRE : `_ecrirePredictions` AVALAIT l'exception
  //  (`catch (e) { debugPrint }`) et `_savePredictions` rendait un
  //  `Future<void>`. Un échec d'écriture était donc STRICTEMENT indétectable :
  //  aucune décision financière ne pouvait être annoncée de façon honnête.
  //
  //  Ce qui change, et RIEN de plus :
  //    • `_ecrirePredictions` rend le `bool` réel de `setStringList` ;
  //    • `_savePredictions` / `_boucleEcriture` le propagent ;
  //    • un numéro de version mémoire est comparé à un numéro de version
  //      RÉELLEMENT écrit, pour qu'un succès corresponde à une version donnée.
  //
  //  ⚠️ LE MÉCANISME B-4.6 EST INCHANGÉ : pas d'empilement d'écritures, pas de
  //     microtask ajouté, « la dernière demande gagne ».
  // ══════════════════════════════════════════════════════════════════════════

  /// Numéro de version de l'état mémoire. Incrémenté par toute écriture
  /// financière du lot 2-C.
  int _versionMemoire = 0;

  /// Version RÉELLEMENT écrite, ou `null` si AUCUNE écriture réussie n'a
  /// encore eu lieu.
  ///
  /// ⚠️ POURQUOI `int?` ET NON `int = 0` : avec `0`, la comparaison `0 >= 0`
  ///    rendait `true` alors qu'aucun octet n'avait été écrit — un faux succès
  ///    mesuré. `null` rend « jamais écrit » impossible à confondre avec
  ///    « écrit à la version 0 » : une PREUVE d'écriture est exigée.
  int? _versionEecrite;

  /// Une version demandée est-elle réellement sur le disque ?
  ///
  /// DÉFINITION UNIQUE, partagée par les trois points de décision (appel
  /// regroupé, appel séquentiel, confirmation) : ils ne peuvent pas diverger.
  bool _versionEcriteCouvre(int versionDemandee) {
    final ecrite = _versionEecrite;
    return ecrite != null && ecrite >= versionDemandee;
  }

  /// ★ GÉNÉRATION D'OPÉRATION, PAR TICKET.
  ///
  /// Chaque modification de `montantGainManuel` reçoit un numéro strictement
  /// croissant. Un rétablissement n'est permis QUE si l'opération échouée est
  /// encore la DERNIÈRE applicable à ce ticket.
  ///
  /// ⚠️ LA COMPARAISON DE MONTANT SEULE NE SUFFIT PAS (défaut identifié) :
  ///    la succession 10 € → 20 € → 10 € ramène `montantGainManuel` à la
  ///    valeur de la PREMIÈRE opération. Un contrôle par égalité de montant
  ///    laisserait la 1ʳᵉ opération (échouée, périmée) se croire légitime et
  ///    rétablir un état qui n'est plus le sien. Seul un identifiant
  ///    d'opération distingue ces deux « 10 € ».
  final Map<String, int> _generationGainManuel = <String, int>{};

  int _incrementerGenerationGainManuel(String id) {
    final g = (_generationGainManuel[id] ?? 0) + 1;
    _generationGainManuel[id] = g;
    return g;
  }

  /// ★ TICKETS DONT LA COHÉRENCE MÉMOIRE/DISQUE N'EST PAS PROUVÉE.
  ///
  /// Alimenté UNIQUEMENT par un échec de réconciliation. Tant qu'un
  /// identifiant y figure, AUCUNE nouvelle écriture financière ne s'appuie sur
  /// l'état mémoire de ce ticket : il pourrait diverger du disque. La garde
  /// est BLOQUANTE et le dit — elle ne « tente pas quand même ».
  final Set<String> _etatFinancierDivergent = <String>{};

  /// Le ticket est-il dans un état financier non prouvé ?
  bool estEtatFinancierDivergent(String id) =>
      _etatFinancierDivergent.contains(id);

  /// Nombre de tickets en état non réconcilié — pour l'UI et les tests.
  int get nombreEtatsFinanciersDivergents => _etatFinancierDivergent.length;

  /// Sauvegarde toutes les prédictions localement.
  ///
  /// Rend un `Future` qui se termine quand l'écriture couvrant cet appel est
  /// achevée. Les sept appelants historiques l'ignorent : leur comportement
  /// observable est inchangé.
  Future<bool> _savePredictions() {
    // Version demandée = état mémoire AU MOMENT DE L'APPEL. C'est elle qui
    // doit se retrouver sur le disque pour qu'un `true` soit honnête.
    final versionDemandee = _versionMemoire;
    if (_ecritureEnCours) {
      _ecritureRedemandee = true;
      // ⚠️ JAMAIS `true` par défaut : un completer absent ne prouve RIEN.
      final attente = _ecritureAttente;
      if (attente == null) return Future<bool>.value(false);
      // On ne se contente pas du résultat de la passe en cours : la VERSION
      // DEMANDÉE doit avoir été écrite.
      return attente.future
          .then((ok) => ok && _versionEcriteCouvre(versionDemandee));
    }
    _ecritureAttente = Completer<bool>();
    return _boucleEcriture(versionDemandee);
  }

  Future<bool> _boucleEcriture(int versionDemandee) async {
    _ecritureEnCours = true;
    var ok = true;
    try {
      do {
        _ecritureRedemandee = false;
        // La version est lue JUSTE AVANT la construction de la photographie.
        // Une mutation survenue après est au pire non couverte par cette
        // passe, mais elle lèvera `_ecritureRedemandee`.
        final versionPhoto = _versionMemoire;
        ok = await _ecrirePredictions();
        if (ok) _versionEecrite = versionPhoto;
      } while (_ecritureRedemandee);
    } finally {
      _ecritureEnCours = false;
      final attente = _ecritureAttente;
      _ecritureAttente = null;
      // Tous les appelants regroupés partagent ce completer : ils reçoivent
      // le résultat de la photographie FINALE, jamais d'une passe
      // intermédiaire.
      if (attente != null && !attente.isCompleted) attente.complete(ok);
    }
    // Succès ⇔ la passe a réussi ET ma version est bien sur le disque.
    return ok && _versionEcriteCouvre(versionDemandee);
  }

  /// Attend la fin de l'écriture de sauvegarde en cours, s'il y en a une.
  ///
  /// ★ B-4.6 — exposé pour que la sérialisation soit VÉRIFIABLE : sans point
  /// d'attente public, un test ne peut pas distinguer « écriture pas encore
  /// commencée » de « écriture perdue ». Ne modifie aucun état.
  Future<void> sauvegardeTerminee() => _ecritureEnCours
      ? (_ecritureAttente?.future ?? Future<void>.value())
      : Future<void>.value();

  /// Écriture effective.
  ///
  /// Rend `true` si le disque a réellement accepté la liste.
  /// `SharedPreferences.setStringList` rend lui-même un `bool` : c'est la
  /// seule confirmation réelle disponible, et elle est utilisée telle quelle.
  /// Une exception rend `false` — jamais un succès silencieux.
  Future<bool> _ecrirePredictions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = _predictions.map((p) => jsonEncode(p.toJson())).toList();
      return await prefs.setStringList(_prefsKey, raw);
    } catch (e) {
      if (kDebugMode) debugPrint('_savePredictions error: $e');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ B1-T12 / LOT 2-C — ÉCRITURE FINANCIÈRE DURABLE, CONFIRMÉE ET REPRENABLE
  // ══════════════════════════════════════════════════════════════════════════

  /// ★ GARDE-FOU D'INTÉGRATION — NON ACTIF DANS CE RACCORDEMENT.
  ///
  /// ⚠️ STATUT MESURÉ, SANS AUCUNE AMBIGUÏTÉ :
  ///    • la méthode EXISTE et son mécanisme est testé isolément ;
  ///    • elle N'EST APPELÉE PAR AUCUNE TRANSITION Accepter/Refuser ;
  ///    • aucune transition Accepter/Refuser n'existe encore dans ce
  ///      raccordement (`grep "DecisionGainPmu" lib/` ne trouve que le modèle
  ///      et les getters, jamais un appel d'écriture de décision).
  ///    Elle ne protège donc RIEN aujourd'hui. La présenter comme active
  ///    serait un mensonge : elle est un POINT D'ACCROÎT.
  ///
  /// ⚠️ EXIGENCE POUR L'IMPLÉMENTATION FUTURE — l'invalidation devra être
  ///    intégrée à une TRANSITION FINANCIÈRE COMPLÈTE, c'est-à-dire testée
  ///    dans le même scénario que la persistance de la décision :
  ///      ① `invaliderPourDecisionFinanciere(id)` — EN PREMIÈRE INSTRUCTION ;
  ///      ② écriture de `decisionGainPmu` + `montantOfficielPmu` ;
  ///      ③ confirmation réelle de cette écriture ;
  ///      ④ vérification qu'aucun rétablissement de gain manuel ne l'annule ;
  ///      ⑤ relecture après redémarrage.
  ///    Un appel isolé dans un test ne prouvera JAMAIS l'intégration : le test
  ///    devra exercer la décision réelle de bout en bout.
  void invaliderPourDecisionFinanciere(String id) =>
      _invaliderOperationsGainManuel(id);

  /// Invalide TOUTES les opérations de gain manuel en vol sur ce ticket :
  /// après cet appel, aucune d'elles n'est plus la dernière génération, donc
  /// aucune ne peut plus effectuer de rétablissement ni se déclarer confirmée.
  ///
  /// On ne fait qu'avancer un compteur interne : aucune règle métier, aucun
  /// moteur PMU, aucune décision utilisateur n'est modifiée.
  void _invaliderOperationsGainManuel(String id) {
    _generationGainManuel[id] = (_generationGainManuel[id] ?? 0) + 1;
  }

  /// ★ ÉCRITURE FINANCIÈRE DURABLE DU GAIN DÉCLARÉ.
  ///
  /// Rend une ISSUE À QUATRE ÉTATS, jamais un booléen ambigu :
  ///   • `confirme`  : le montant DEMANDÉ est réellement sur le disque ;
  ///   • `remplacee` : une opération plus récente fait foi, ma valeur n'est
  ///                   plus enregistrée ;
  ///   • `echec`     : échec, mais mémoire et disque sont PROUVÉS alignés ;
  ///   • `echecNonReconcilie` : échec dont la réconciliation a échoué — la
  ///                   cohérence n'est PAS prouvée, le ticket est bloqué.
  ///
  /// `montant == null` EFFACE la déclaration ; `0.0` est une déclaration
  /// explicite. Les deux restent distincts de bout en bout.
  ///
  /// ⚠️ N'APPELLE **PAS** `_syncStatsTypesIA()` : les statistiques et le
  ///    PROFIL sont hors périmètre de ce lot.
  Future<IssueEcritureGain> enregistrerGainManuelPrediction(
      String id, double? montant) async {
    // ★ GARDE BLOQUANTE — on n'écrit JAMAIS sur un ticket dont la cohérence
    //   n'est pas prouvée. On ne réutilise donc pas silencieusement un état
    //   mémoire potentiellement divergent.
    if (_etatFinancierDivergent.contains(id)) {
      return IssueEcritureGain.echecNonReconcilie;
    }

    final idx = _predictions.indexWhere((p) => p.id == id);
    if (idx == -1) return IssueEcritureGain.echec;

    // ① L'opération reçoit son identifiant AVANT toute écriture.
    final maGeneration = _incrementerGenerationGainManuel(id);
    final ancienMontant = _predictions[idx].montantGainManuel;

    // ② Égalité en mémoire ≠ preuve disque : on VÉRIFIE, on ne conclut pas.
    if (ancienMontant == montant) {
      return _issueDepuisDisque(id, montant, maGeneration);
    }

    // ③ Modification en mémoire — SEUL `montantGainManuel` est touché.
    _predictions[idx] = _predictions[idx].copyWith(montantGainManuel: montant);
    _versionMemoire++;
    notifyListeners();

    final ecrit = await _savePredictions();
    if (!ecrit) {
      return _rollbackCible(id, montant, ancienMontant, maGeneration);
    }

    // ④ Preuve finale : le ticket porte-t-il, PAR SON ID, CE montant ?
    return _issueDepuisDisque(id, montant, maGeneration);
  }

  /// Issue d'une opération, établie à partir du disque ET de sa génération.
  ///
  /// ⚠️ L'ORDRE COMPTE AUTANT QUE LA COMPARAISON : la génération est vérifiée
  ///    AVANT la lecture, puis REVÉRIFIÉE APRÈS — un `await` laisse toujours
  ///    passer une opération concurrente. Sans la revérification, la
  ///    succession 10 € → 20 € → 10 € ferait croire à l'opération N°1 que le
  ///    « 10 » du disque est le sien, alors qu'il vient de l'opération N°3.
  Future<IssueEcritureGain> _issueDepuisDisque(
      String id, double? montant, int maGeneration) async {
    // ① Suis-je encore la dernière opération applicable ?
    if (_generationGainManuel[id] != maGeneration) {
      return IssueEcritureGain.remplacee;
    }

    // ② Lecture asynchrone — point de reprise pour une autre opération.
    final presentSurDisque = await verifierGainPersiste(id, montant);

    // ③ La génération a-t-elle bougé pendant l'attente ?
    if (_generationGainManuel[id] != maGeneration) {
      return IssueEcritureGain.remplacee;
    }

    // ④ Je suis la dernière ET le disque porte ma valeur.
    return presentSurDisque
        ? IssueEcritureGain.confirme
        : IssueEcritureGain.echec;
  }

  /// Rétablissement du SEUL champ `montantGainManuel` après échec.
  ///
  /// TROIS GARDE-FOUS, chacun mesurable :
  ///   ① GÉNÉRATION : l'opération échouée doit être la DERNIÈRE applicable.
  ///      Une acceptation, un refus ou une réédition survenue entre-temps
  ///      interdit donc le rétablissement, et n'est jamais annulée.
  ///   ② VALEUR : le champ doit encore porter la valeur que l'on a échoué à
  ///      écrire. S'il a changé, on ne touche à rien.
  ///   ③ PORTÉE : `copyWith` ne reçoit QUE `montantGainManuel`. Tous les
  ///      autres champs (`decisionGainPmu`, `montantOfficielPmu`,
  ///      `montantGainManuelAvantDecision`, mises, cotes, verdicts…) gardent
  ///      leur valeur COURANTE. On ne réinstalle JAMAIS l'objet entier.
  Future<IssueEcritureGain> _rollbackCible(String id, double? montantEchoue,
      double? ancienMontant, int maGeneration) async {
    if (_generationGainManuel[id] != maGeneration) {
      return IssueEcritureGain.remplacee;
    }
    final idx = _predictions.indexWhere((p) => p.id == id);
    if (idx == -1) return IssueEcritureGain.echec;
    if (_predictions[idx].montantGainManuel != montantEchoue) {
      return IssueEcritureGain.remplacee;
    }

    // Rétablissement LIMITÉ à ce seul champ.
    _predictions[idx] =
        _predictions[idx].copyWith(montantGainManuel: ancienMontant);
    _versionMemoire++;
    notifyListeners();

    return _reconcilierApresEchec(id, ancienMontant, maGeneration);
  }

  /// Aligne mémoire et disque, et DIT honnêtement si l'alignement est établi.
  ///
  /// ⚠️ LE RÉSULTAT DE `_savePredictions()` N'EST PLUS IGNORÉ : c'est lui qui
  ///    distingue `echec` (alignement prouvé) de `echecNonReconcilie`
  ///    (cohérence non prouvée, ticket bloqué).
  ///
  /// ⚠️ AUCUNE ÉCRITURE PARALLÈLE : si une passe est en vol, `_savePredictions`
  ///    lève `_ecritureRedemandee` et la boucle B-4.6 existante réécrit la
  ///    photographie COURANTE. On n'introduit donc jamais une écriture
  ///    susceptible de restaurer un ancien montant par-dessus une décision.
  Future<IssueEcritureGain> _reconcilierApresEchec(
      String id, double? ancienMontant, int maGeneration) async {
    // Le disque porte-t-il DÉJÀ l'ancien montant ? La première écriture n'a
    // alors rien changé : la mémoire est alignée, rien à écrire.
    if (await verifierGainPersiste(id, ancienMontant)) {
      if (_generationGainManuel[id] != maGeneration) {
        return IssueEcritureGain.remplacee;
      }
      _etatFinancierDivergent.remove(id); // cohérence prouvée
      return IssueEcritureGain.echec;
    }
    if (_generationGainManuel[id] != maGeneration) {
      return IssueEcritureGain.remplacee;
    }

    final reconcilie = await _savePredictions();
    if (!reconcilie) {
      _etatFinancierDivergent.add(id); // cohérence NON prouvée
      return IssueEcritureGain.echecNonReconcilie;
    }
    if (!await verifierGainPersiste(id, ancienMontant)) {
      _etatFinancierDivergent.add(id);
      return IssueEcritureGain.echecNonReconcilie;
    }
    if (_generationGainManuel[id] != maGeneration) {
      return IssueEcritureGain.remplacee;
    }
    _etatFinancierDivergent.remove(id);
    return IssueEcritureGain.echec; // échec d'écriture, alignement PROUVÉ
  }

  /// Vérifie que le ticket [id] porte réellement [montant] sur le DISQUE.
  ///
  /// Lecture seule : ne peut rien corrompre. Utilisée comme PREUVE finale,
  /// car ni le `bool` de `setStringList` ni la version ne prouvent qu'un
  /// ticket DONNÉ porte un montant DONNÉ — la photographie peut contenir une
  /// valeur plus récente.
  ///
  /// ⚠️ `null` ET `0.0` SONT DISTINGUÉS PAR CONSTRUCTION :
  ///    • `montant == null` → la clé doit valoir `null` (effacement écrit) ;
  ///    • `montant == 0.0`  → la clé doit valoir `0.0` (déclaration explicite).
  /// Un montant EFFACÉ n'est donc jamais confondu avec un montant nul.
  ///
  /// Rend `false` si le ticket est absent du disque : rien n'est confirmé.
  Future<bool> verifierGainPersiste(String id, double? montant) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // ⚠️ DÉFAUT MESURÉ, CORRIGÉ ICI — `SharedPreferences` tient un CACHE
      //    mémoire qui est mis à jour MÊME QUAND LE SUPPORT REFUSE
      //    L'ÉCRITURE (`setStringList` rend `false` mais le cache porte la
      //    nouvelle valeur). Sans `reload()`, cette preuve lisait donc le
      //    CACHE et pouvait confirmer un montant que le DISQUE ne porte pas :
      //    un faux succès, exactement ce que ce lot doit rendre impossible.
      //    `reload()` réaligne le cache sur le support réel avant la lecture.
      //    Coût négligeable ; aucune donnée en mémoire applicative n'est
      //    touchée (`_predictions` n'est pas modifiée).
      await prefs.reload();
      final raw = prefs.getStringList(_prefsKey) ?? [];
      for (final s in raw) {
        final map = jsonDecode(s) as Map<String, dynamic>;
        if (map['id'] != id) continue;
        final stocke = (map['montantGainManuel'] as num?)?.toDouble();
        if (montant == null) return stocke == null;
        return stocke == montant;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Confirmation fiable pour une écriture financière.
  ///
  /// Distincte de [sauvegardeTerminee] (dont la signature et le contrat sont
  /// INCHANGÉS) : celle-ci rend le RÉSULTAT RÉEL de l'écriture.
  ///
  /// ⚠️ AUCUN indicateur « écriture en retard » n'intervient ici : ce serait
  ///    exactement l'indicateur dont il est interdit de faire une preuve. La
  ///    preuve est le retour de `setStringList` + la version écrite.
  Future<bool> confirmationEcriturePredictions() {
    final attente = _ecritureAttente;
    final versionDemandee = _versionMemoire;
    // Aucune écriture réussie n'a jamais eu lieu ⇒ `false`. Sans cette
    // ligne, `0 >= 0` rendrait `true` : faux succès mesuré.
    if (_versionEecrite == null && !_ecritureEnCours) {
      return Future<bool>.value(false);
    }
    if (_ecritureEnCours && attente != null) {
      return attente.future
          .then((ok) => ok && _versionEcriteCouvre(versionDemandee));
    }
    return Future<bool>.value(_versionEcriteCouvre(versionDemandee));
  }

  /// ★ RÉCUPÉRATION CONTRÔLÉE D'UN ÉTAT FINANCIER NON PROUVÉ.
  ///
  /// ⚠️ CE QUE CETTE MÉTHODE NE FAIT PAS, ET C'EST LE CŒUR DE LA CORRECTION :
  ///    elle N'APPELLE PAS `reloadPredictions()`. Un rechargement ÉCRASE
  ///    l'état mémoire AVANT toute comparaison : on ne pourrait plus rien
  ///    comparer, et une modification concurrente plus récente serait perdue.
  ///    On lit donc le disque SÉPARÉMENT, sans y substituer la mémoire.
  ///
  /// DÉROULEMENT, aucune étape raccourcie :
  ///   ① ATTENDRE les écritures en vol : on n'observe jamais un état
  ///      intermédiaire, donc jamais un faux désaccord.
  ///   ② LIRE le disque sans écraser la mémoire.
  ///   ③ COMPARER les TROIS champs financiers : `montantGainManuel`,
  ///      `montantOfficielPmu`, `decisionGainPmu`.
  ///   ④ PRÉSERVER la modification concurrente plus récente : si l'état
  ///      mémoire a bougé pendant la lecture, on ne conclut RIEN.
  ///   ⑤ DÉBLOQUER seulement si les trois champs concordent.
  ///   ⑥ INCERTITUDE ⇒ le ticket RESTE bloqué et on rend `false`.
  ///
  /// Rend `true` UNIQUEMENT si la cohérence des trois champs est prouvée.
  Future<bool> reconcilierEtatFinancier(String id) async {
    // ① Attendre les écritures en cours (mécanisme B-4.6, contrat inchangé).
    await sauvegardeTerminee();

    final idx = _predictions.indexWhere((p) => p.id == id);
    if (idx == -1)
      return false; // ticket absent : l'absence n'est pas une preuve

    // ② Lecture du disque, SANS toucher à la mémoire.
    Map<String, dynamic>? surDisque;
    try {
      final prefs = await SharedPreferences.getInstance();
      // ⚠️ MÊME DÉFAUT QUE DANS `verifierGainPersiste`, MÊME CORRECTIF : le
      //    cache de `SharedPreferences` porte la valeur REFUSÉE par le
      //    support. Comparer la mémoire à ce cache ne prouverait rien — on
      //    compare à ce que le DISQUE contient réellement.
      await prefs.reload();
      final raw = prefs.getStringList(_prefsKey) ?? [];
      for (final s in raw) {
        final map = jsonDecode(s) as Map<String, dynamic>;
        if (map['id'] == id) {
          surDisque = map;
          break;
        }
      }
    } catch (_) {
      return false; // lecture impossible : incertitude ⇒ reste bloqué
    }
    if (surDisque == null) return false; // absent du disque : aucune preuve

    // ④ Capturer la génération AVANT de figer les valeurs mémoire : si elle
    //    changeait pendant la suite, une modification concurrente serait en
    //    cours et aucun verdict ne serait honnête.
    final generationAvant = _generationGainManuel[id] ?? 0;
    final memoire = _predictions[idx];

    // ③ Comparaison des TROIS champs financiers.
    final manuelDisque = (surDisque['montantGainManuel'] as num?)?.toDouble();
    final officielDisque =
        (surDisque['montantOfficielPmu'] as num?)?.toDouble();
    final decisionDisque =
        _lireDecisionGainDepuisJson(surDisque['decisionGainPmu']);

    final concordance = memoire.montantGainManuel == manuelDisque &&
        memoire.montantOfficielPmu == officielDisque &&
        memoire.decisionGainPmu == decisionDisque;

    // ④ Modification concurrente survenue pendant la lecture ?
    if ((_generationGainManuel[id] ?? 0) != generationAvant) {
      return false; // on ne débloque pas sur un état qui a bougé
    }

    // ⑤ / ⑥ Déblocage seulement sur concordance prouvée.
    if (!concordance) return false;
    _etatFinancierDivergent.remove(id);
    notifyListeners();
    return true;
  }

  /// Relecture tolérante d'une décision depuis une map JSON brute.
  /// Toute valeur absente ou inconnue rend `null` (jamais un refus inventé).
  static DecisionGainPmu? _lireDecisionGainDepuisJson(dynamic valeur) {
    if (valeur is! String) return null;
    for (final d in DecisionGainPmu.values) {
      if (d.name == valeur) return d;
    }
    return null;
  }

  /// Ajoute une prédiction (plusieurs paris sur la même course autorisés)
  void addPrediction(UserPrediction pred) {
    // Ne pas supprimer les paris existants : l'ID unique (timestamp) suffit
    _predictions.add(pred);
    _savePredictions();
    notifyListeners();
  }

  /// ★ LOT B-4.5 — Remplace un pronostic par sa version PORTANT LE VERDICT.
  ///
  /// POURQUOI CETTE MÉTHODE EXISTE : `validatePrediction` et
  /// `enregistrerDividendePmu` modifient `isCorrect`, `gainRealise` et
  /// `dividendePmuReel`, puis appellent `_syncStatsTypesIA()`. Écrire un
  /// verdict par leur intermédiaire déclencherait donc une resynchronisation
  /// des statistiques d'apprentissage IA — ce que le lot B-4.5 interdit.
  ///
  /// ⚠️ CETTE MÉTHODE N'ÉCRIT AUCUNE DÉCISION : le pronostic reçu est celui
  ///    que l'enregistreur B-4.3 a produit (champs B-1 seulement). Elle le
  ///    range à la place de l'ancien et sauvegarde.
  ///
  /// ⚠️ ELLE N'APPELLE **PAS** `_syncStatsTypesIA()` : aucune statistique IA
  ///    n'est recalculée, aucun historique IA n'est modifié. Les écritures
  ///    IA existantes (via `enregistrerDividendePmu`) restent le SEUL chemin
  ///    de synchronisation, et elles ne sont pas empruntées ici.
  ///
  /// Preuve que le DISQUE porte bien l'état du ticket [id] après un `await`.
  ///
  /// ⚠️ MÊME RIGUEUR QUE [_issueDepuisDisque] : la génération est contrôlée
  ///    AVANT la lecture, puis REVÉRIFIÉE APRÈS — un `await` laisse toujours
  ///    passer une opération concurrente. Sans la revérification, une opération
  ///    périmée pourrait se croire confirmée sur une valeur écrite par une
  ///    autre.
  ///
  /// ⚠️ `verifierGainPersiste` N'EST PAS RÉUTILISÉE : elle est câblée sur
  ///    `montantGainManuel`. L'appeler ici prouverait le MAUVAIS champ, donc
  ///    un faux succès de plus. La lecture porte sur les SEPT champs que
  ///    l'enregistreur B-4.3 écrit.
  Future<IssueEcritureGain> _issueDepuisDisqueVerdict(
      String id, int maGeneration, UserPrediction verdictEcrit) async {
    // ① Suis-je encore la dernière opération applicable ?
    if (_generationGainManuel[id] != maGeneration) {
      return IssueEcritureGain.remplacee;
    }

    final present = await _disquePorteLeVerdict(id, verdictEcrit);

    // ② La génération a-t-elle bougé pendant la lecture ?
    if (_generationGainManuel[id] != maGeneration) {
      return IssueEcritureGain.remplacee;
    }

    if (present) {
      _etatFinancierDivergent.remove(id); // cohérence prouvée
      return IssueEcritureGain.confirme;
    }

    // ③ Le disque NE PORTE PAS le verdict alors que `_savePredictions()` a
    //    rendu `true`. Rendre `echec` ici serait MENSONGER : `echec` signifie
    //    « échec dont l'alignement mémoire/disque est PROUVÉ ». On tente donc
    //    UNE réconciliation, puis on PROUVE — ou on bloque.
    final reconcilie = await _savePredictions();
    if (!reconcilie) {
      _etatFinancierDivergent.add(id);
      return IssueEcritureGain.echecNonReconcilie;
    }
    if (!await _disquePorteLeVerdict(id, verdictEcrit)) {
      _etatFinancierDivergent.add(id);
      return IssueEcritureGain.echecNonReconcilie;
    }
    if (_generationGainManuel[id] != maGeneration) {
      return IssueEcritureGain.remplacee;
    }
    _etatFinancierDivergent.remove(id);
    return IssueEcritureGain.confirme;
  }

  /// Lit le DISQUE (après `prefs.reload()`) et compare les SEPT champs B-1.
  ///
  /// Rend `false` si le ticket est absent : rien n'est confirmé.
  Future<bool> _disquePorteLeVerdict(String id, UserPrediction attendu) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // ⚠️ DÉFAUT MESURÉ, CORRIGÉ : `SharedPreferences` tient un CACHE mis à
      //    jour MÊME QUAND LE SUPPORT REFUSE (`setStringList` rend `false` mais
      //    le cache porte la nouvelle valeur). Sans `reload()`, cette preuve
      //    lirait le CACHE et confirmerait une valeur que le DISQUE ne porte
      //    pas — un faux succès.
      await prefs.reload();
      final raw = prefs.getStringList(_prefsKey) ?? <String>[];
      for (final s in raw) {
        final map = jsonDecode(s) as Map<String, dynamic>;
        if (map['id'] != id) continue;
        final lu = UserPrediction.fromJson(map);
        return lu.etatGain == attendu.etatGain &&
            lu.motifNonDetermination == attendu.motifNonDetermination &&
            lu.etatTirelire == attendu.etatTirelire &&
            lu.dividendeGagnant == attendu.dividendeGagnant &&
            lu.dividendePlace == attendu.dividendePlace &&
            lu.miseBaseCentimesUtilisee == attendu.miseBaseCentimesUtilisee &&
            // ★ CHANTIER 1/3 — le remboursement est un champ ÉCRIT par cette
            //   opération : la preuve d'alignement doit donc le couvrir. Sans
            //   cette comparaison, un disque à `null` et une mémoire à `10.0`
            //   seraient déclarés « alignés ».
            lu.remboursementPmu == attendu.remboursementPmu &&
            lu.rapportsAttribues?.length == attendu.rapportsAttribues?.length;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Rétablissement CONDITIONNEL des SEPT champs du verdict après échec.
  ///
  /// ⚠️ TROIS GARDE-FOUS, identiques à [_rollbackCible] :
  ///   ① GÉNÉRATION : une opération plus récente interdit tout rétablissement.
  ///   ② VALEUR : on ne rétablit que si la mémoire porte ENCORE le verdict
  ///      que l'on a échoué à écrire.
  ///   ③ PORTÉE : seuls les sept champs du verdict sont touchés. Les QUATRE
  ///      champs financiers du lot 2-C (dont `montantGainManuel`) sont repris
  ///      de l'état COURANT — jamais d'un ancien objet entier.
  ///
  /// Rend `echec` si l'alignement est PROUVÉ, `echecNonReconcilie` sinon (le
  /// ticket est alors bloqué par `_etatFinancierDivergent`).
  Future<IssueEcritureGain> _retablirVerdictApresEchec(
    String id,
    int maGeneration,
    UserPrediction verdictEchoue,
    UserPrediction avantVerdict,
  ) async {
    // ① Une opération plus récente fait foi : je ne rétablis rien.
    if (_generationGainManuel[id] != maGeneration) {
      return IssueEcritureGain.remplacee;
    }

    final idx = _predictions.indexWhere((p) => p.id == id);
    if (idx == -1) return IssueEcritureGain.echecNonReconcilie;

    // ② VALEUR : on ne rétablit que si la mémoire porte ENCORE le verdict que
    //    l'on a échoué à écrire. S'il a changé, l'état courant n'est plus le
    //    mien et je n'ai rien à annuler.
    if (!_memesChampsVerdict(_predictions[idx], verdictEchoue)) {
      return IssueEcritureGain.remplacee;
    }

    // ③ Rétablissement LIMITÉ aux sept champs du verdict, SUR l'état courant :
    //    les quatre champs financiers ne sont même pas transmis à `copyWith`,
    //    donc ils ne peuvent pas être écrasés.
    //
    //    ★ B1-T12 / P1 — SAUF `montantOfficielPmu`. MESURÉ : sans cette ligne,
    //    un échec de sauvegarde sur le chemin `enregistrerMontantOfficiel:
    //    true` laissait la MÉMOIRE porter le montant officiel (75,0) alors que
    //    le DISQUE portait `null`, tout en rendant `echec` — c'est-à-dire en
    //    AFFIRMANT un alignement faux. Le montant officiel fait donc partie du
    //    rétablissement : c'est un champ écrit par CETTE opération, il doit
    //    revenir à sa valeur d'avant. Les trois autres champs financiers
    //    (`montantGainManuel`, `decisionGainPmu`,
    //    `montantGainManuelAvantDecision`) ne sont TOUJOURS PAS transmis : ils
    //    n'appartiennent pas à cette opération et ne doivent jamais bouger.
    _predictions[idx] = _predictions[idx].copyWith(
      etatGain: avantVerdict.etatGain,
      rapportsAttribues: avantVerdict.rapportsAttribues,
      etatTirelire: avantVerdict.etatTirelire,
      dividendeGagnant: avantVerdict.dividendeGagnant,
      dividendePlace: avantVerdict.dividendePlace,
      miseBaseCentimesUtilisee: avantVerdict.miseBaseCentimesUtilisee,
      motifNonDetermination: avantVerdict.motifNonDetermination,
      montantOfficielPmu: avantVerdict.montantOfficielPmu,
      // ★ CHANTIER 1/3 — le remboursement fait partie de CE que cette
      //   opération écrit, donc de ce qu'elle doit savoir annuler. Sans cette
      //   ligne, un échec de sauvegarde laisserait la MÉMOIRE porter un
      //   remboursement que le DISQUE n'a jamais reçu, tout en rendant
      //   `echec` — c'est-à-dire en affirmant un alignement faux.
      remboursementPmu: avantVerdict.remboursementPmu,
    );
    _versionMemoire++;
    notifyListeners();

    // ③bis Le disque porte-t-il DÉJÀ cet état ? Alors rien n'a été changé :
    //    l'alignement est PROUVÉ, l'issue est `echec` (et non un blocage).
    if (await _disquePorteLeVerdict(id, _predictions[idx])) {
      if (_generationGainManuel[id] != maGeneration) {
        return IssueEcritureGain.remplacee;
      }
      _etatFinancierDivergent.remove(id);
      return IssueEcritureGain.echec;
    }
    if (_generationGainManuel[id] != maGeneration) {
      return IssueEcritureGain.remplacee;
    }

    // ④ Réconciliation : une seule tentative, puis preuve. `echec` n'est rendu
    //    QUE si le disque porte réellement l'état rétabli — sinon le ticket
    //    est bloqué et on le DIT (`echecNonReconcilie`).
    final reconcilie = await _savePredictions();
    if (!reconcilie) {
      _etatFinancierDivergent.add(id);
      return IssueEcritureGain.echecNonReconcilie;
    }
    if (!await _disquePorteLeVerdict(id, _predictions[idx])) {
      _etatFinancierDivergent.add(id);
      return IssueEcritureGain.echecNonReconcilie;
    }
    if (_generationGainManuel[id] != maGeneration) {
      return IssueEcritureGain.remplacee;
    }
    _etatFinancierDivergent.remove(id);
    return IssueEcritureGain.echec; // échec d'écriture, alignement PROUVÉ
  }

  /// Comparaison PURE de deux états en mémoire sur les SEPT champs du verdict.
  ///
  /// Sert la garde de VALEUR du rétablissement : elle ne lit RIEN sur le
  /// disque et ne prouve donc que ce qu'elle prétend — l'état mémoire est-il
  /// encore celui que l'on a échoué à écrire.
  bool _memesChampsVerdict(UserPrediction courant, UserPrediction attendu) =>
      courant.etatGain == attendu.etatGain &&
      courant.motifNonDetermination == attendu.motifNonDetermination &&
      courant.etatTirelire == attendu.etatTirelire &&
      courant.dividendeGagnant == attendu.dividendeGagnant &&
      courant.dividendePlace == attendu.dividendePlace &&
      courant.miseBaseCentimesUtilisee == attendu.miseBaseCentimesUtilisee &&
      // ★ B1-T12 / P1 — le montant officiel fait partie de CE que cette
      //   opération écrit, donc de ce qu'elle doit pouvoir reconnaître comme
      //   sien. Sans cette comparaison, un échec pouvait être jugé « déjà en
      //   place » sur la seule base des sept autres champs alors que le
      //   montant officiel, lui, différait entre mémoire et disque.
      courant.montantOfficielPmu == attendu.montantOfficielPmu &&
      courant.rapportsAttribues?.length == attendu.rapportsAttribues?.length;

  /// Rend `true` si le pronostic existait et a été remplacé, `false` sinon.
  bool appliquerVerdictGainPrediction(UserPrediction resolue) {
    final idx = _predictions.indexWhere((p) => p.id == resolue.id);
    if (idx == -1) return false;
    _predictions[idx] = resolue;
    _savePredictions();
    notifyListeners();
    return true;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ B1-T12 / LOT 2-C — ÉCRITURE DE VERDICT SANS ÉCRASEMENT FINANCIER
  // ══════════════════════════════════════════════════════════════════════════
  //
  //  DÉFAUT MESURÉ, REPRODUIT PAR TEST (D1) :
  //
  //    `appliquerVerdictGainPrediction` ci-dessus affecte un OBJET ENTIER
  //    (`_predictions[idx] = resolue`). L'objet reçu a été calculé par
  //    l'appelant à partir d'un INSTANTANÉ capturé AVANT une attente réseau
  //    (~15 s). Pendant cette attente, l'utilisateur peut saisir un gain
  //    manuel : `enregistrerGainManuelPrediction` écrit alors `12.0` dans
  //    `_predictions[idx]`, puis le verdict reprend et REMPLACE l'objet par
  //    celui de l'instantané, qui porte `montantGainManuel: null`.
  //
  //    Mesure D1 : `expect(12.0)` → `Actual: <null>`, MÉMOIRE **ET** DISQUE.
  //
  //    L'asymétrie est décisive (mesure D2) : dans l'ordre inverse, la saisie
  //    manuelle survit, parce que `enregistrerGainManuelPrediction` fait un
  //    `copyWith` limité à UN champ. Une seule des deux écritures est donc
  //    destructrice — ce n'est pas « l'ordre » qui est fragile, c'est
  //    l'affectation d'objet entier.
  //
  //  CORRECTION — SANS AUCUN `await` ENTRE LECTURE ET ÉCRITURE :
  //
  //    L'état est relu sur `_predictions[idx]` (l'état FRAIS, jamais
  //    l'instantané de l'appelant), résolu, décidé et fusionné DANS UN SEUL
  //    BLOC SYNCHRONE. L'isolate Dart est mono-thread : sans point de
  //    suspension, aucune opération concurrente ne peut s'intercaler, donc
  //    aucun état ne peut devenir périmé entre la lecture et l'affectation.
  //    C'est exactement ce qu'une « relecture avant écriture » séparée par un
  //    `await` ne garantirait PAS.
  //
  //    ⚠️ AUCUNE RÈGLE MÉTIER N'EST REPRODUITE ICI. La politique d'écriture
  //       (idempotence, refus du verdict définitif, transition
  //       `nonDetermine → définitif`, cohérence interne, refus d'ambiguïté)
  //       reste ENTIÈREMENT dans `appliquerVerdictPrediction` / B-4.3, qui est
  //       APPELÉE telle quelle. Aucun montant n'est calculé : `VerdictGain`
  //       vient de `resoudreGainTicketDepuisDonnees` (moteur B-3).

  /// Applique le verdict officiel de [resultat] au ticket [id], en RELISANT
  /// l'état courant et en préservant INTÉGRALEMENT les champs financiers.
  ///
  /// Rend `true` si un verdict a été écrit en mémoire (la persistance reste à
  /// confirmer par l'appelant via [confirmationEcriturePredictions]).
  ///
  /// Rend `false` — sans rien écrire — dans tous les autres cas : ticket
  /// absent, état financier divergent, verdict déjà posé, capture
  /// inexploitable, ou refus de la politique B-4.3.
  Future<IssueEcritureGain> appliquerVerdictGainPredictionSecurise(
      String id, ResultatOfficielCourse resultat,
      {bool enregistrerMontantOfficiel = false}) async {
    // ⚠️ GARDE BLOQUANTE — jamais d'écriture sur un ticket dont la cohérence
    //    mémoire/disque n'est pas prouvée (même règle que le gain manuel).
    if (_etatFinancierDivergent.contains(id)) {
      return IssueEcritureGain.echecNonReconcilie;
    }

    // ══ PARTIE 1 — SYNCHRONE. AUCUN `await` DE LA LECTURE À L'AFFECTATION ══
    //    L'isolate Dart est mono-thread : sans point de suspension, aucune
    //    opération concurrente ne peut s'intercaler, donc l'état lu ne peut
    //    pas devenir périmé avant l'affectation. C'est la protection CAUSALE
    //    contre le défaut D1 (voir E10).
    final idx = _predictions.indexWhere((p) => p.id == id);
    if (idx == -1) return IssueEcritureGain.echec;

    // ① L'état FRAIS, relu maintenant — PAS l'instantané de l'appelant.
    final etatFrais = _predictions[idx];

    // ② Verdict déjà posé : la politique B-4.3 le refuserait de toute façon
    //    (`refuseVerdictDefinitifExistant`) ; on évite un calcul inutile.
    if (etatFrais.etatGain != null) return IssueEcritureGain.echec;

    // ③ Construction du ticket : refuse explicitement toute capture
    //    incomplète. On ne complète NI numéro, NI ordre, NI mise.
    final construit = construireTicketPrediction(etatFrais);
    if (!construit.estExploitable) return IssueEcritureGain.echec;

    // ④ Résolution officielle — moteur B-3, synchrone, pur. INCHANGÉ.
    final verdict = resoudreGainTicketDepuisDonnees(
      ticket: construit.ticket!,
      resultat: resultat,
    );

    // ⑤ Politique d'écriture — B-4.3, appelée telle quelle. INCHANGÉE.
    final enregistrement = appliquerVerdictPrediction(
      ticket: etatFrais,
      verdict: verdict,
      resultat: resultat,
    );
    if (!enregistrement.estEnregistre) return IssueEcritureGain.echec;

    // ⑥ FUSION EXPLICITE — les SEPT champs B-1 proviennent de l'enregistreur ;
    //    les QUATRE champs financiers du lot 2-C sont repris de l'état FRAIS.
    //    `copyWith` porte des sentinelles : un `null` explicite est écrit tel
    //    quel. Cette fusion est DÉFENSIVE (l'enregistreur part déjà de
    //    `etatFrais`) : elle est conservée comme garde en profondeur, et non
    //    présentée comme la protection — les mutations l'ont mesuré.
    final fusionnee = enregistrement.ticket.copyWith(
      montantGainManuel: etatFrais.montantGainManuel,
      montantOfficielPmu: etatFrais.montantOfficielPmu,
      decisionGainPmu: etatFrais.decisionGainPmu,
      montantGainManuelAvantDecision: etatFrais.montantGainManuelAvantDecision,
    );

    // ⑥-bis ★ B1-T12 / RACCORDEMENT DES GAINS OFFICIELS TARDIFS.
    //
    //   DÉSACTIVÉ PAR DÉFAUT. Sans ce drapeau, la méthode est EXACTEMENT celle
    //   validée au lot 2-C : les 38 appels existants (2 écrans + tests) n'ont
    //   pas changé d'un caractère et leur comportement est identique — la
    //   mutation « retrait de l'attente de `_savePredictions()` » produit
    //   toujours ses 8 échecs, ce qui le prouve.
    //
    //   QUAND IL EST ACTIVÉ (voie tardive uniquement), il écrit le montant
    //   OFFICIEL BRUT issu du verdict, par la fonction PURE de B-4.3 :
    //     • `attribue` → retour brut, seulement si démontrablement complet ;
    //     • `perdu`    → `0.0` (perte établie) ;
    //     • `rembourse`→ `null` — JAMAIS converti en gain (arbitrage A) ;
    //     • `nonDetermine` → `null`.
    //
    //   ⚠️ CE QUI N'EST JAMAIS ÉCRIT ICI :
    //     • `montantGainManuel` — la saisie de l'utilisateur est INTOUCHÉE ;
    //     • `decisionGainPmu` — aucune décision Accepter/Refuser automatique ;
    //     • `montantGainManuelAvantDecision` — trace, préservée.
    //
    //   ⚠️ DIVERGENCE, PAS ÉCRASEMENT. Si un gain manuel existe et que le
    //      montant officiel diffère, on enregistre l'officiel en RÉFÉRENCE et
    //      on laisse `decisionGainPmu` à `null` : la demande reste ouverte.
    //      Le montant manuel continue donc de faire foi à l'affichage
    //      (`gainRetenuBrut`, branche ①) jusqu'à décision explicite.
    //      Montants IDENTIQUES : même chose, l'information d'égalité est
    //      portée par l'égalité elle-même, disponible pour la notification
    //      informative unique ultérieure — sans nouveau champ.
    //
    //   ⚠️ GARDE-FOU DE REMBOURSEMENT — POURQUOI IL EST ICI ET PAS AILLEURS.
    //      Le moteur ne teste pas `publie.rembourse` dans
    //      `_composanteGagnantPlace` : un rapport REMBOURSÉ portant
    //      `pourUnEuro > 0` y produit un `montantRetour` compté comme gain, et
    //      `VerdictGain.attribue` l'accepte. Le montant officiel serait alors
    //      FAUX. Le moteur est protégé et sa correction métier relève d'un
    //      autre lot : on n'y touche pas. On arrête donc l'erreur au dernier
    //      point autorisé, en NOMMANT les combinaisons réellement remboursées
    //      publiées pour cette course. `montantOfficielDepuisVerdict` rend
    //      alors `null` : aucun montant n'est écrit, aucune perte de `0.0`
    //      n'est inventée, aucun remboursement ne devient un gain.
    final combinaisonsRemboursees = _combinaisonsRemboursees(verdict, resultat);
    final avecOfficiel = enregistrerMontantOfficiel
        ? _fusionnerMontantOfficiel(
            fusionnee,
            verdict,
            combinaisonsRemboursees: combinaisonsRemboursees,
          )
        : fusionnee;

    // ⑦ Témoin d'AVANT, indispensable au rétablissement conditionnel : ce que
    //    le disque devra porter si l'écriture échoue.
    // ⚠️ Le témoin d'AVANT est l'OBJET `UserPrediction` lui-même, et non sept
    //    variables typées : `PmuProvider` n'importe PAS le socle `gain_pmu_types`
    //    (garde B-0 : la liste des importateurs est FERMÉE et nominative). Les
    //    types des sept champs sont donc obtenus par INFÉRENCE depuis les
    //    accesseurs de `UserPrediction` — aucun nom de type du socle n'est
    //    écrit ici, et la portée du rétablissement reste identique.
    final avantVerdict = etatFrais;

    // ⑧ GÉNÉRATION PARTAGÉE — une saisie manuelle en vol ne doit plus se croire
    //    légitime. `maGeneration` identifie CETTE opération : une opération
    //    plus récente la remplacera et interdisra tout rétablissement.
    final maGeneration = _incrementerGenerationGainManuel(id);

    _predictions[idx] = avecOfficiel;
    _versionMemoire++;
    notifyListeners();
    // ══ FIN DE LA PARTIE SYNCHRONE ═════════════════════════════════════════
    //    Le témoin transmis est l'état EXACT que l'on vient d'écrire en
    //    mémoire : c'est lui que le disque doit porter. Le relire après coup
    //    (`_predictions[idx]`) serait faux — `notifyListeners()` a pu laisser
    //    un auditeur modifier l'entrée, et on confirmerait alors l'écriture
    //    d'autrui.
    final verdictEcrit = avecOfficiel;

    // ══ PARTIE 2 — ASYNCHRONE. LE SUCCÈS N'EST JAMAIS RENDU SANS PREUVE. ════
    //    Avant cette correction, la méthode rendait `true` juste après avoir
    //    APPELÉ `_savePredictions()` sans attendre son résultat : `true` ne
    //    prouvait donc RIEN sur la persistance. Le contrat est désormais le
    //    même que celui du gain manuel : on attend, puis on RELIT le disque.
    final ecrit = await _savePredictions();
    if (!ecrit) {
      return _retablirVerdictApresEchec(
          id, maGeneration, verdictEcrit, avantVerdict);
    }
    return _issueDepuisDisqueVerdict(id, maGeneration, verdictEcrit);
  }

  /// ★ B1-T12 / RACCORDEMENT TARDIF — fusion du SEUL champ officiel.
  ///
  /// Écrit `montantOfficielPmu` à partir du verdict, et RIEN d'autre :
  ///   • `montantGainManuel` n'est pas passé à `copyWith` ⇒ il reste celui de
  ///     [base], c'est-à-dire la saisie de l'utilisateur, intacte ;
  ///   • `decisionGainPmu` n'est pas passé ⇒ aucune décision automatique ;
  ///   • `montantGainManuelAvantDecision` n'est pas passé ⇒ trace préservée ;
  ///   • les sept champs B-1 viennent de l'enregistreur et ne sont pas touchés.
  ///
  /// ⚠️ DIVERGENCE ASSUMÉE : quand un gain manuel existe et que l'officiel en
  ///    diffère, on n'écrase RIEN. On enregistre l'officiel en RÉFÉRENCE et on
  ///    laisse `decisionGainPmu == null` : la demande reste ouverte, et le
  ///    montant manuel continue de faire foi à l'affichage. C'est exactement
  ///    « conserver le gain manuel actif et enregistrer l'état de divergence ».
  ///
  /// ⚠️ `null` N'ÉCRASE PAS UN OFFICIEL DÉJÀ CONNU. Si le verdict ne permet
  ///    pas d'établir de montant (`rembourse`, `nonDetermine`, ou total non
  ///    démontrable), on conserve la valeur déjà présente : une absence de
  ///    preuve n'est pas une preuve d'absence, et effacer un montant officiel
  ///    antérieurement établi serait une régression.
  /// ★ B1-T12 / P1 — combinaisons réellement remboursées ET PERTINENTES.
  ///
  /// Le moteur ne teste pas `publie.rembourse` : un rapport remboursé portant
  /// `pourUnEuro > 0` fonde un `montantRetour` compté comme gain. On arrête
  /// cette erreur ici, sans toucher au moteur protégé.
  ///
  /// ⚠️ PRÉCISION, PAS BLOCAGE EN MASSE. Rendre toutes les combinaisons
  ///    remboursées de la course bloquerait un ticket VALIDE dès qu'un autre
  ///    pari de la même course est remboursé. On n'ajoute donc la combinaison
  ///    d'une composante que si LE rapport qui l'a fondée est remboursé :
  ///      • correspondance sur la COMBINAISON (normalisée), ET
  ///      • correspondance sur le LIBELLÉ officiel quand les deux côtés en
  ///        portent un — c'est lui qui distingue « e-Simple Gagnant » de
  ///        « e-Simple Placé » sur une même combinaison.
  ///
  /// ⚠️ DIRECTION SÛRE EN CAS DE DOUTE. Si la composante ne porte pas de
  ///    libellé, on ne peut pas établir la correspondance : on retient alors
  ///    la combinaison dès qu'un rapport remboursé la porte. Le doute bloque
  ///    l'écriture plutôt que de laisser passer un gain faux — on ne fabrique
  ///    jamais un montant sur une incertitude.
  Set<String> _combinaisonsRemboursees(
    VerdictGain verdict,
    ResultatOfficielCourse resultat,
  ) {
    final rembourses = <String>{
      for (final r in resultat.rapports)
        if (r.rembourse) r.combinaison.trim(),
    }..removeWhere((c) => c.isEmpty);
    if (rembourses.isEmpty) return const <String>{};

    final retenues = <String>{};
    for (final composante in verdict.composantes) {
      final combinaison = composante.combinaisonRapport.trim();
      if (combinaison.isEmpty) continue;
      if (!rembourses.contains(combinaison)) continue;

      final libelle = composante.libelleRapport.trim();
      // Rapports remboursés portant CETTE combinaison.
      final candidats = resultat.rapports
          .where((r) => r.rembourse && r.combinaison.trim() == combinaison)
          .toList();

      if (libelle.isEmpty) {
        // Correspondance indémontrable : on retient (direction sûre).
        retenues.add(combinaison);
        continue;
      }

      final memeLibelle = candidats.any((r) {
        final l = r.libelleOfficiel.trim();
        return l.isEmpty || l == libelle;
      });
      if (memeLibelle) retenues.add(combinaison);
    }
    return retenues;
  }

  UserPrediction _fusionnerMontantOfficiel(
    UserPrediction base,
    VerdictGain verdictOfficiel, {
    Set<String> combinaisonsRemboursees = const <String>{},
  }) {
    final montant = montantOfficielDepuisVerdict(
      verdictOfficiel,
      combinaisonsRemboursees: combinaisonsRemboursees,
    );

    // ★ CHANTIER 1/3 — LE REMBOURSEMENT EST RACCORDÉ ICI, ET NULLE PART AILLEURS.
    //
    //   DÉFAUT MESURÉ AVANT D'ÉCRIRE : `_fusionnerMontantOfficiel` n'écrivait
    //   que `montantOfficielPmu`. Un Gagnant+Placé mixte (75 € gagnés + 10 €
    //   remboursés) persistait donc 75 € SANS les 10 € rendus : « Remboursement »
    //   restait vide alors que le montant est démontré, et le total reversé
    //   affiché (75 €) était FAUX — il vaut 85 €.
    //
    //   ⚠️ DEUX CHAMPS, DEUX SIGLES, JAMAIS FUSIONNÉS. Le remboursement ne
    //      rentre pas dans `montantOfficielPmu` : il a son propre champ, sa
    //      propre clé JSON, son propre libellé d'affichage. C'est la règle.
    //
    //   ⚠️ `null` N'ÉCRASE PAS UN REMBOURSEMENT DÉJÀ CONNU — même raisonnement
    //      que pour le montant : si le verdict ne démontre aucun remboursement,
    //      effacer un remboursement antérieurement établi serait une régression.
    //      Un remboursement établi est un FAIT officiel, pas une absence.
    final remboursement = verdictOfficiel.remboursement > 0
        ? verdictOfficiel.remboursement
        : null;

    if (montant == null && remboursement == null) return base;
    return base.copyWith(
      montantOfficielPmu: montant ?? base.montantOfficielPmu,
      remboursementPmu: remboursement ?? base.remboursementPmu,
    );
  }

  /// Valide ou invalide un pronostic + enregistre la mise et le gain
  void validatePrediction(
    String id, {
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
  void enregistrerDividendePmu(
    String id, {
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
      debugPrint(
          '✅ Dividende PMU enregistré: ×${dividendePmuReel.toStringAsFixed(2)} → gain ${gainNet.toStringAsFixed(2)}€');
    }
  }

  /// Tente de récupérer les dividendes PMU réels pour tous les paris
  /// combinés (Tiercé/Quarté/Quinté) dont le résultat est encore en attente.
  /// À appeler après la fin d'une course.
  Future<int> recupererDividendesPmuManquants() async {
    int nbMisAJour = 0;
    final enAttenteCombines = _predictions
        .where((p) => p.isCorrect == null && p.estPariCombine)
        .toList();

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
        if (kDebugMode)
          debugPrint('❌ Erreur récupération dividende ${pred.id}: $e');
      }
    }
    if (nbMisAJour > 0) {
      if (kDebugMode)
        debugPrint('✅ $nbMisAJour dividendes PMU récupérés et enregistrés');
    }
    return nbMisAJour;
  }

  void _syncStatsTypesIA() {
    // ★ B1-T12 / étape 1 — LA CONTRIBUTION FINANCIÈRE TRANSMISE EST GARDÉE.
    //
    //   DÉFAUT MESURÉ (test/b1_t12_sync_stats_gp_test.dart, T1) : un ticket
    //   `Gagnant+Placé` déclaré gagnant par `validatePrediction` reçoit
    //   `isCorrect = true` MAIS `gainRealise = null` (la garde G+P de
    //   `validatePrediction` ne produit aucun montant). L'état transmis ici
    //   était alors `p.gainNet`, soit (18,00 × 10) − 10 = **170,00 €** :
    //   un produit cote × mise d'UNE SEULE composante, appliqué à un ticket
    //   qui en engage DEUX. Ces 170,00 € entraient dans `_statsTypes`, y
    //   étaient PERSISTÉS (`ia_stats_types_v1`) et affichés comme un gain.
    //
    //   CE QUI EST CORRIGÉ, ET RIEN DE PLUS : la VALEUR TRANSMISE. Le prédicat
    //   `gainGagnantPlaceEtabli` — déjà utilisé par les 12 autres sites
    //   d'affichage et par `totalGainsNet` / `getGainsNetByDateRange` ci-dessus
    //   — vaut :
    //     • `false` sur un G+P gagné sans gain officiel  → contribution 0,00 €
    //     • `true`  sur un G+P dont le gain est officiel → montant CONSERVÉ
    //     • `true`  sur un G+P perdant                   → −mise CONSERVÉE
    //     • `true`  hors Gagnant+Placé                   → STRICTEMENT inchangé
    //
    //   NE SONT PAS MODIFIÉS : `UserPrediction.gainNet`, `retourTotal`,
    //   `miseTotaleEngagee`, les formules, les modèles, la persistance, les
    //   poids, seuils, gradient descent, TOP3 learning, le ROI et l'ELO.
    //   Aucune migration, aucun recalcul forcé : les tickets historiques ne
    //   sont pas réécrits, et `mettreAJourStatsTypes` recalcule depuis la
    //   liste reçue à chaque appel — la correction prend donc effet au
    //   prochain recalcul NORMAL, sans intervention.
    final allPreds = _predictions
        .map((p) => {
              'typePari': p.typePari,
              'isCorrect': p.isCorrect,
              'gainNet': p.gainGagnantPlaceEtabli ? p.gainNet : 0.0,
            })
        .toList();
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
      return _predictions
          .firstWhere((p) => p.numReunion == numR && p.numCourse == numC);
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
      return _predictions.firstWhere((p) =>
          p.numReunion == numR && p.numCourse == numC && p.isCorrect == null);
    } catch (_) {
      return getPredictionForCourse(numR, numC); // fallback sur le premier
    }
  }
}
