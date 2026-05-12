// ═══════════════════════════════════════════════════════════════════════════
//  IaMemoryService — Mémoire & Auto-apprentissage v4.0 (Lot 1 : ELO + Entraîneur)
//
//  Architecture de l'apprentissage :
//
//  ┌─────────────────────────────────────────────────────────────────────┐
//  │  Pour chaque course avec résultat réel :                            │
//  │                                                                     │
//  │  1. On sait quels chevaux ont BIEN été classés par l'IA             │
//  │  2. Pour chaque critère (Forme, Gains, Cote…) on calcule :          │
//  │     → Score moyen du critère pour les chevaux BIEN classés          │
//  │     → Score moyen du critère pour les chevaux MAL classés           │
//  │  3. Si un critère discrimine bien (bon > mauvais) → augmenter poids │
//  │  4. Si un critère ne discrimine pas (scores similaires) → réduire   │
//  │                                                                     │
//  │  Formule :  Δpoids = lr × (score_bon - score_mauvais) / 100         │
//  │                                                                     │
//  │  NOUVEAU v3 : Poids DISTINCTS par discipline                        │
//  │  → L'IA apprend que la Cote compte plus en Trot,                    │
//  │    que la Forme compte plus en Plat, etc.                           │
//  │                                                                     │
//  │  NOUVEAU v3 : Indice de Confiance Adaptative                        │
//  │  → L'IA signale quand elle est "certaine" vs "incertaine"           │
//  │    selon la variance de ses scores (champ resserré = incertitude)   │
//  │                                                                     │
//  │  C'est l'idée centrale du gradient descent adapté aux courses PMU.  │
//  └─────────────────────────────────────────────────────────────────────┘
//
//  En plus : journal complet des ajustements pour transparence totale.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async'; // ★ v9.90 : Completer pour _load race condition
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
// flutter/material.dart not needed here (foundation.dart suffices)
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/zt_models.dart';

// import 'elo_service.dart'; // ★ v8.0 — utilisé par DataRefreshService, pas ici directement

// ─── Scores bruts par critère pour un cheval donné ───────────────────────────
// Sauvegardés au moment du pronostic pour l'apprentissage ultérieur


// ─── Modèles de données extraits dans ia_memory_models.dart ──────────────────
import 'ia_memory_models.dart';
import 'ia_pronostic_engine.dart';

class IaMemoryService extends ChangeNotifier {
  static final IaMemoryService _instance = IaMemoryService._();
  static IaMemoryService get instance => _instance;
  IaMemoryService._();

  static const _pronosticsKey   = 'ia_pronostics_v2';
  static const _poidsKey        = 'ia_poids_v3';
  static const _journalKey      = 'ia_journal_v2';
  static const _rapportsKey     = 'ia_rapports_v1';    // ★ Rapports journaliers
  static const _statsTypesKey   = 'ia_stats_types_v1'; // ★ Stats cumulatives par type de pari
  static const _precisionIAKey  = 'ia_precision_v2';   // ★ Précision IA par type de pari (v2)
  static const _seuilsKey       = 'ia_seuils_v1';      // ★ Seuils de confiance adaptatifs
  static const _statsLabelsKey  = 'ia_stats_labels_v1'; // ★ v9.0 Stats par label IA
  static const _maxPronostics   = 600;
  // ★ Lot 4 : Compression + purge automatique
  static const _maxPronosticsAge = 90;    // purger les pronostics > 90 jours sans résultat
  static const _useCompression   = true;  // activer gzip sur les listes longues
  static const _compressionKey   = 'ia_pronostics_v2_gz'; // clé des données compressées
  static const _maxJournal      = 500;  // ★ v9.91 : monté de 300 → 500
  static const _maxRapports     = 365;  // ★ v9.91 : monté de 60 → 365 (1 an)
  // ★ v9.91 : clés pour la structure hiérarchique du journal
  static const _bilansSemaineKey = 'ia_bilans_semaine_v1';
  static const _bilansMoisKey    = 'ia_bilans_mois_v1';

  final List<IaPronostic>          _pronostics    = [];
  final List<JournalEntree>        _journal       = [];
  final List<RapportJournalier>    _rapports      = [];
  // ★ v9.91 : structure hiérarchique du journal
  final List<BilanSemaine>         _bilansSemaine = [];
  BilanSemaine? _pendingBilanHebdo; // ★ v9.93 : bilan semaine en attente pour bulle
  final List<BilanMois>            _bilansMois    = [];
  final Map<String, StatsTypePari>    _statsTypes    = {}; // ★ clé = typePari
  // ★ Précision IA par type de pari (clé = typePari, ex: 'Quinté+', 'Simple Gagnant'...)
  final Map<String, StatsPrecisionParType> _precisionParType = {};
  // ★ v9.0 : Stats par label IA (⚡ Coup préparé, 🥇 FAVORI IA, etc.)
  final Map<String, StatsParLabel> _statsLabels = {};
  // ★ Seuils de confiance adaptatifs (l'IA les ajuste elle-même après chaque analyse)
  SeuilsConfianceAdaptatifs _seuils = SeuilsConfianceAdaptatifs();
  IaPoidsAdaptatifs _poids = IaPoidsAdaptatifs.defaut();
  bool _loaded = false;
  Completer<void>? _loadCompleter; // ★ v9.90 : évite le double chargement concurrent

  IaPoidsAdaptatifs       get poids     => _poids;
  List<IaPronostic>       get pronostics => List.unmodifiable(_pronostics);
  List<JournalEntree>     get journal    => List.unmodifiable(_journal.reversed);
  /// Rapports journaliers, du plus récent au plus ancien
  List<RapportJournalier> get rapports   =>
      List.unmodifiable(_rapports.reversed.toList());
  /// Dernier rapport disponible (null si aucune analyse effectuée)
  RapportJournalier?      get dernierRapport =>
      _rapports.isNotEmpty ? _rapports.last : null;
  /// ★ v9.91 : Bilans de semaine archivés (du plus récent au plus ancien)
  List<BilanSemaine>      get bilansSemaine =>
      List.unmodifiable(_bilansSemaine.reversed.toList());

  /// ★ v9.93 : Retourne le bilan semaine en attente d'affichage (bulle hebdo)
  /// et remet à null après lecture.
  BilanSemaine? consommerBilanHebdo() {
    final b = _pendingBilanHebdo;
    _pendingBilanHebdo = null;
    return b;
  }
  /// ★ v9.91 : Bilans de mois archivés (du plus récent au plus ancien)
  List<BilanMois>         get bilansMois =>
      List.unmodifiable(_bilansMois.reversed.toList());
  /// Stats cumulatives par type de pari (triées par ordre logique simple→complexe)
  List<StatsTypePari>     get statsParType {
    final list = _statsTypes.values.toList()
      ..sort((a, b) => a.ordreAffichage.compareTo(b.ordreAffichage));
    return list;
  }
  /// Précision IA par type de pari (données réelles)
  List<StatsPrecisionParType> get precisionParType {
    final list = _precisionParType.values
        .where((p) => p.typePari != 'Inconnu' && p.typePari.isNotEmpty) // ★ v9.84 : filtrer les types invalides
        .toList();
    list.sort((a, b) => a.ordreAffichage.compareTo(b.ordreAffichage));
    return list;
  }

  /// ★ v9.99 : Précision "Aujourd'hui" calculée directement depuis _pronostics
  /// (source de vérité temps réel) sans passer par historiqueComplet.
  /// historiqueComplet n'est mis à jour qu'après analyseJourneeComplete()
  /// → affichage 0/0 toute la journée avant l'analyse. Ce getter corrige ça :
  /// dès qu'un résultat est enregistré via enregistrerResultat(), il est
  /// immédiatement visible dans le filtre "Aujourd'hui".
  Map<String, Map<String, int>> get precisionAujourdhuiDepuisPronostics {
    final now = DateTime.now();
    final debutJour = DateTime(now.year, now.month, now.day);
    final finJour   = debutJour.add(const Duration(days: 1));

    // Collecter les pronostics résolus AUJOURD'HUI
    final pronosDuJour = _pronostics.where((p) =>
        p.resultatsReels &&
        p.datePronostic.isAfter(debutJour.subtract(const Duration(hours: 1))) &&
        p.datePronostic.isBefore(finJour)).toList();

    // Si rien aujourd'hui → essayer sur les dernières 48h (courses tardives)
    final source = pronosDuJour.isNotEmpty
        ? pronosDuJour
        : _pronostics.where((p) =>
            p.resultatsReels &&
            p.datePronostic.isAfter(now.subtract(const Duration(hours: 48))) &&
            p.datePronostic.isBefore(finJour)).toList();

    // Agréger par type de pari
    final Map<String, int> nb      = {};
    final Map<String, int> bons    = {};
    final Map<String, int> ordre   = {};
    final Map<String, int> desord  = {};

    for (final p in source) {
      final type = p.typePariConseille ?? '';
      if (type.isEmpty || type == 'Inconnu' || type == 'À surveiller') continue;
      nb[type]     = (nb[type]     ?? 0) + 1;
      if (_estBonConseilParType(p, type)) {
        bons[type] = (bons[type]   ?? 0) + 1;
        final ord  = _estOrdreExact(p, type);
        if (ord == true)  ordre[type]  = (ordre[type]  ?? 0) + 1;
        if (ord == false) desord[type] = (desord[type] ?? 0) + 1;
      }
    }

    // Construire le résultat { typePari → {nb, bons, ordre, desordre} }
    final result = <String, Map<String, int>>{};
    for (final type in nb.keys) {
      result[type] = {
        'nb':      nb[type]     ?? 0,
        'bons':    bons[type]   ?? 0,
        'ordre':   ordre[type]  ?? 0,
        'desordre':desord[type] ?? 0,
      };
    }
    return result;
  }
  /// ★ v10.25 : Données calendrier — agrège les pronostics résolus d'un mois donné
  /// par jour, et calcule le palier de couleur selon la logique typePariConseille.
  ///
  /// Paliers :
  ///  OR      : ≥ 1 pronostic correct sur Quinté+, Quarté+ ou Tiercé (ordre ou désordre)
  ///  VERT    : taux ≥ 40%
  ///  JAUNE   : taux ≥ 25%
  ///  ORANGE  : au moins 1 bon conseil (taux < 25%)
  ///  ROUGE   : courses mais 0 bon conseil
  ///  GRIS    : aucune course ce jour
  ///
  /// Retourne Map<jourDuMois, DonneeJourCalendrier>
  Map<int, DonneeJourCalendrier> donneesCalendrierJour(int annee, int mois) {
    final Map<int, _AgregJourCal> aggr = {};

    for (final p in _pronostics) {
      if (!p.resultatsReels) continue;
      final d = p.datePronostic;
      if (d.year != annee || d.month != mois) continue;

      final type = p.typePariConseille ?? '';
      if (type.isEmpty || type == 'Inconnu' || type == 'À surveiller') continue;

      final ag = aggr.putIfAbsent(d.day, () => _AgregJourCal());
      ag.nbCourses++;
      ag.pronostics.add(p);

      if (_estBonConseilParType(p, type)) {
        ag.nbBons++;
        final ord = _estOrdreExact(p, type);
        if (ord == true)  ag.nbOrdre++;
        if (ord == false) ag.nbDesordre++;
      }
    }

    // Convertir en DonneeJourCalendrier avec palier calculé
    final result = <int, DonneeJourCalendrier>{};
    for (final entry in aggr.entries) {
      final ag  = entry.value;
      final taux = ag.nbCourses > 0 ? ag.nbBons / ag.nbCourses : 0.0;

      // OR : ≥ 1 pronostic correct sur Quinté+, Quarté+ ou Tiercé (ordre ou désordre)
      const typesNoblesOr = {
        'Quinté+', 'Quinté+ Ordre', 'Quinté+ Désordre',
        'Quarté+', 'Quarté+ Ordre', 'Quarté+ Désordre',
        'Tiercé',  'Tiercé Ordre',  'Tiercé Désordre',
      };
      final bool aUnNobleReussi = ag.pronostics.any((p) {
        final t = p.typePariConseille ?? '';
        return typesNoblesOr.contains(t) && _estBonConseilParType(p, t);
      });

      final PalierCalendrier palier;
      if (ag.nbCourses == 0) {
        palier = PalierCalendrier.gris;
      } else if (aUnNobleReussi) {
        palier = PalierCalendrier.or;
      } else if (ag.nbBons == 0) {
        palier = PalierCalendrier.rouge;
      } else if (taux >= 0.40) {
        palier = PalierCalendrier.vert;
      } else if (taux >= 0.25) {
        palier = PalierCalendrier.jaune;
      } else {
        palier = PalierCalendrier.orange;
      }
      result[entry.key] = DonneeJourCalendrier(
        jour:       entry.key,
        nbCourses:  ag.nbCourses,
        nbBons:     ag.nbBons,
        nbOrdre:    ag.nbOrdre,
        nbDesordre: ag.nbDesordre,
        palier:     palier,
        pronostics: List.unmodifiable(ag.pronostics),
      );
    }
    return result;
  }

  /// ★ v9.0 : Stats par label IA (triées par nb décroissant)
  List<StatsParLabel> get statsParLabel {
    final list = _statsLabels.values.toList()
      ..sort((a, b) => b.nbTotal.compareTo(a.nbTotal));
    return list;
  }
  /// Seuils de confiance adaptatifs courants
  SeuilsConfianceAdaptatifs get seuilsConfiance => _seuils;
  List<IaPronostic>       get pronosticsAvecResultat =>
      _pronostics.where((p) => p.resultatsReels).toList();

  /// ★ v9.87 : Précision IA par hippodrome avec flag de fiabilité (tous hippos).
  /// Retourne { 'NomHippo': {'taux': double, 'nb': int, 'fiable': bool} }
  Map<String, Map<String, dynamic>> get precisionParHippodromeAvecFiabilite {
    final Map<String, int> total   = {};
    final Map<String, int> gagnes  = {};
    for (final p in _pronostics.where((p) => p.resultatsReels)) {
      final h = p.hippodrome;
      if (h.isEmpty) continue;
      total[h]  = (total[h]  ?? 0) + 1;
      gagnes[h] = (gagnes[h] ?? 0) + (p.rangFavoriIaDansArrivee == 1 ? 1 : 0);
    }
    final result = <String, Map<String, dynamic>>{};
    for (final h in total.keys) {
      final nb     = total[h]!;
      final taux   = (gagnes[h] ?? 0) / nb;
      result[h] = {'taux': taux, 'nb': nb, 'fiable': nb >= 5};
    }
    return result;
  }

  // ★ v9.92 POINT 4 : Matrice précision hippodrome × discipline
  // Clé : "HIPPODROME|DISCIPLINE" → {'nb': int, 'gagnes': int, 'top3': int}
  Map<String, Map<String, dynamic>> get precisionHippodromeXDiscipline {
    final Map<String, int> total  = {};
    final Map<String, int> gagnes = {};
    final Map<String, int> top3   = {};
    for (final p in _pronostics.where((p) => p.resultatsReels)) {
      if (p.hippodrome.isEmpty || p.discipline.isEmpty) continue;
      final key = '${p.hippodrome}|${p.discipline}';
      total[key]  = (total[key]  ?? 0) + 1;
      gagnes[key] = (gagnes[key] ?? 0) + (p.rangFavoriIaDansArrivee == 1 ? 1 : 0);
      top3[key]   = (top3[key]   ?? 0) + (p.rangFavoriIaDansArrivee != null && p.rangFavoriIaDansArrivee! <= 3 ? 1 : 0);
    }
    final result = <String, Map<String, dynamic>>{};
    for (final key in total.keys) {
      final nb = total[key]!;
      if (nb < 3) continue; // minimum 3 courses pour apparaître
      result[key] = {
        'nb':     nb,
        'gagnes': gagnes[key] ?? 0,
        'top3':   top3[key]   ?? 0,
        'tauxGagnant': (gagnes[key] ?? 0) / nb,
        'tauxTop3':    (top3[key]   ?? 0) / nb,
        'fiable': nb >= 5,
      };
    }
    return result;
  }

  // ★ v9.93 POINT 5 : Série chaude par type de pari
  // Analyse les derniers pronostics résolus pour détecter une série
  // de succès consécutifs sur un type de pari spécifique.
  // Retourne {'serie': N, 'type': 'Simple Gagnant', 'chaud': true/false}
  // ★ v9.93 POINT 2 : Annuler la pondération d'une journée atypique
  // Appelé depuis le journal IA quand l'utilisateur estime que l'IA
  // a eu tort de qualifier cette journée d'atypique.
  // Remet le compteur mensuel à la valeur précédente et relance
  // le gradient sur les pronostics du jour concerné avec facteur 1.0.
  Future<void> annulerJourneeAtypique(DateTime date) async {
    await _load();
    final moisKey = '${date.year}-${date.month}';
    final current = (_poids.dernierGradient['atypiques_$moisKey'] ?? 0.0);
    if (current > 0) {
      _poids.dernierGradient['atypiques_$moisKey'] = current - 1;
    }

    // Supprimer l'entrée du journal correspondant à cette journée atypique
    _journal.removeWhere((e) =>
        e.methode == 'journee_atypique' &&
        e.date.year == date.year &&
        e.date.month == date.month &&
        e.date.day == date.day);

    // Relancer le gradient avec facteur 1.0 sur les pronostics du jour
    final dateDebut = DateTime(date.year, date.month, date.day);
    final dateFin   = dateDebut.add(const Duration(days: 1));
    final pronosticsJour = _pronostics.where((p) =>
        p.resultatsReels &&
        p.datePronostic.isAfter(dateDebut.subtract(const Duration(hours: 1))) &&
        p.datePronostic.isBefore(dateFin)).toList();

    if (pronosticsJour.isNotEmpty) {
      await _apprendreParGradient(facteurAtypique: 1.0);
      final discVus = pronosticsJour.map((p) => p.discipline).toSet();
      for (final disc in discVus) {
        if (disc.isNotEmpty) await _apprendreParDiscipline(disc, facteurAtypique: 1.0);
      }
    }

    // Journaliser l'annulation
    _journal.add(JournalEntree(
      date:               DateTime.now(),
      nomCourse:          'Annulation — Journée ${date.day}/${date.month}/${date.year}',
      discipline:         'Toutes',
      nbCoursesAnalysees: pronosticsJour.length,
      diagnostic:         '✅ Journée atypique annulée manuellement. '
                          'Gradient recalculé avec facteur ×1.0 sur '
                          '${pronosticsJour.length} pronostics.',
      avant:              Map<String, double>.from(_poids.dernierGradient),
      apres:              Map<String, double>.from(_poids.dernierGradient),
      scorePerf:          0,
      methode:            'annulation_atypique',
    ));

    await _save();
    notifyListeners();
  }

  Map<String, dynamic>? serieChaudePourType(String typePari) {
    final resolus = _pronostics
        .where((p) => p.resultatsReels &&
            p.typePariConseille == typePari &&
            p.rangFavoriIaDansArrivee != null)
        .toList()
      ..sort((a, b) => b.datePronostic.compareTo(a.datePronostic));

    if (resolus.isEmpty) return null;

    int serieCourante = 0;
    bool isGagnant(IaPronostic p) {
      final rang = p.rangFavoriIaDansArrivee!;
      switch (typePari) {
        case 'Simple Gagnant':
        case 'Gagnant+Placé':   return rang == 1;
        case 'Simple Placé':
        case 'Couplé Placé':    return rang <= 3;
        case 'Couplé Gagnant':  return rang <= 2;
        case 'Tiercé':          return rang <= 3;
        case 'Quarté+':         return rang <= 4;
        case 'Quinté+':         return rang <= 5;
        default:                return rang == 1;
      }
    }

    for (final p in resolus) {
      if (isGagnant(p)) serieCourante++;
      else break;
    }

    if (serieCourante < 2) return null; // pas de série significative
    return {
      'serie': serieCourante,
      'type':  typePari,
      'chaud': serieCourante >= 3,
    };
  }

  static Future<void> init() async {
    await _instance._load();
  }

  /// ★ Lot 4 : Purge automatique des pronostics trop anciens sans résultat.
  /// Appelé lors de chaque _save si trop de pronostics sans résultat s'accumulent.
  void _purgerVieuxPronostics() {
    final now    = DateTime.now();
    final limite = now.subtract(const Duration(days: _maxPronosticsAge));
    final avant  = _pronostics.length;

    _pronostics.removeWhere((p) {
      // Ne supprimer que les pronostics SANS résultat réel ET trop anciens
      // Les pronostics avec résultat (pour l'apprentissage) sont conservés plus longtemps
      if (p.resultatsReels) return false; // garder les résultats réels
      return p.datePronostic.isBefore(limite);
    });

    final apres = _pronostics.length;
    if (apres < avant) {
      debugPrint('[IaMemory] 🧹 Purge : ${avant - apres} pronostics supprimés '
          '(> $_maxPronosticsAge jours sans résultat)');
    }
  }

  // ★ BOUTON PURGE MANUEL ─────────────────────────────────────────────────
  /// Purge IMMÉDIATE de tous les pronostics sans résultat réel.
  /// Appelé par le bouton "Purger courses sans résultat" dans ia_performance_screen.
  ///
  // ─── Résultat de la relance PMU ──────────────────────────────────────────
  // Retourné par relancerRecuperationPMU() pour afficher le journal détaillé.

  // ─── Relance manuelle de la récupération des résultats PMU ───────────────
  /// Cherche tous les pronostics PASSÉS sans résultat (courses déjà terminées)
  /// et tente de récupérer leur résultat sur l'API PMU.
  /// Ne supprime rien — seule la purge supprime.
  /// Retourne un rapport détaillé : {recuperes, introuvables, erreurs, details}
  Future<Map<String, dynamic>> relancerRecuperationPMU({
    void Function(String msg)? onProgress,
  }) async {
    await _load();
    final now = DateTime.now();

    // Sélectionner uniquement les pronostics PASSÉS sans résultat
    // "passé" = heureDepart < maintenant - 30 min
    final aRelancer = _pronostics.where((p) {
      if (p.resultatsReels) return false; // déjà traité
      final diff = p.datePronostic.difference(now).inMinutes;
      return diff <= -30; // course terminée depuis au moins 30 min
    }).toList()
      ..sort((a, b) => b.datePronostic.compareTo(a.datePronostic)); // plus récentes en premier

    if (aRelancer.isEmpty) {
      return {
        'recuperes': 0,
        'introuvables': 0,
        'erreurs': 0,
        'total': 0,
        'details': <String>[],
        'message': 'Aucun pronostic passé sans résultat trouvé.',
      };
    }

    onProgress?.call('🔍 ${aRelancer.length} course(s) à relancer…');

    int recuperes   = 0;
    int introuvables = 0;
    int erreurs     = 0;
    final details   = <String>[];

    for (int i = 0; i < aRelancer.length; i++) {
      final p = aRelancer[i];
      final courseKey = p.courseKey;

      // Parser le courseKey : R{numR}C{numC}_{JJMMAAAA}
      final match = RegExp(r'^R(\d+)C(\d+)_').firstMatch(courseKey);
      if (match == null) {
        erreurs++;
        details.add('❌ $courseKey : clé non reconnue');
        continue;
      }

      final numR = match.group(1)!;
      final numC = match.group(2)!;

      // Date depuis datePronostic (date réelle de la course)
      final d    = p.datePronostic;
      final jour  = d.day.toString().padLeft(2, '0');
      final mois  = d.month.toString().padLeft(2, '0');
      final annee = d.year.toString();
      final dateStr = '$jour$mois$annee';

      final nomCourt = p.nomCourse.length > 20
          ? '${p.nomCourse.substring(0, 20)}…'
          : p.nomCourse;
      onProgress?.call(
          '⚙️ (${i + 1}/${aRelancer.length}) $nomCourt — $jour/$mois');

      try {
        final url =
            'https://turfinfo.api.pmu.fr/rest/client/7'
            '/programme/$dateStr/R$numR/C$numC'
            '/rapports-definitifs?specialisation=INTERNET';

        final resp = await http
            .get(Uri.parse(url), headers: {'Accept': 'application/json'})
            .timeout(const Duration(seconds: 15));

        if (resp.statusCode != 200) {
          introuvables++;
          details.add('⏳ $nomCourt ($jour/$mois) : résultats PMU pas encore publiés (HTTP ${resp.statusCode})');
          continue;
        }

        final List<dynamic> rapports =
            jsonDecode(resp.body) as List<dynamic>;

        // Extraire l'arrivée officielle depuis les rapports PMU
        final List<int> arriveeOfficielle = [];

        for (final r in rapports) {
          final typePari = r['typePari'] as String? ?? '';
          final rList    = (r['rapports'] as List<dynamic>? ?? []);
          if (rList.isEmpty) continue;

          // Simple Gagnant → cheval N°1
          if (typePari == 'E_SIMPLE_GAGNANT' && arriveeOfficielle.isEmpty) {
            final rap = rList.first as Map<String, dynamic>;
            final n = int.tryParse(rap['combinaison']?.toString() ?? '');
            if (n != null && !arriveeOfficielle.contains(n)) {
              arriveeOfficielle.add(n);
            }
          }

          // Tiercé / Quarté / Quinté ordre → extraire la combinaison complète
          final isOrdre = (typePari.contains('TIERCE') ||
                           typePari.contains('TIERCÉ') ||
                           typePari.contains('QUARTE') ||
                           typePari.contains('QUINTE')) &&
                          !typePari.contains('DESORDRE') &&
                          !typePari.contains('DÉSORDRE') &&
                          !typePari.contains('4SUR5') &&
                          !typePari.contains('4_SUR_5');
          if (isOrdre && rList.isNotEmpty) {
            final rap   = rList.first as Map<String, dynamic>;
            final combo = rap['combinaison']?.toString() ?? '';
            for (final part in combo.split('-')) {
              final n = int.tryParse(part.trim());
              if (n != null && !arriveeOfficielle.contains(n)) {
                arriveeOfficielle.add(n);
              }
            }
          }

          // Simple Placé → top 3
          if (typePari == 'E_SIMPLE_PLACE') {
            for (final item in rList) {
              final n = int.tryParse(
                  (item as Map)['combinaison']?.toString() ?? '');
              if (n != null && !arriveeOfficielle.contains(n)) {
                arriveeOfficielle.add(n);
              }
            }
          }
        }

        if (arriveeOfficielle.isEmpty) {
          introuvables++;
          details.add('⏳ $nomCourt ($jour/$mois) : résultats PMU pas encore disponibles');
          continue;
        }

        // Enregistrer le résultat dans la mémoire IA
        final aj  = d.day.toString().padLeft(2, '0');
        final am  = d.month.toString().padLeft(2, '0');
        // Construire la memKey au même format qu'alert_service
        final memKey = '${courseKey}_$aj$am${d.year}';
        // Essayer d'abord avec le courseKey direct (format ia_memory)
        // puis avec la clé suffixée (format alert_service)
        final idxDirect = _pronostics.indexWhere((x) => x.courseKey == courseKey);
        final keyAUtiliser = idxDirect >= 0 ? courseKey : memKey;

        await enregistrerResultat(
          courseKey: keyAUtiliser,
          arriveeReelle: arriveeOfficielle,
        );

        recuperes++;
        details.add('✅ $nomCourt ($jour/$mois) : arrivée ${arriveeOfficielle.take(5).map((n) => "N°$n").join(" - ")} enregistrée');

      } catch (e) {
        erreurs++;
        details.add('❌ $nomCourt ($jour/$mois) : erreur réseau ($e)');
      }
    }

    // Sauvegarder et notifier
    if (recuperes > 0) {
      await _save();
      notifyListeners();
    }

    String message;
    if (recuperes == aRelancer.length) {
      message = '✅ $recuperes résultat(s) récupéré(s) sur ${aRelancer.length}';
    } else if (recuperes > 0) {
      message = '✅ $recuperes récupéré(s) · ⏳ $introuvables en attente PMU · ❌ $erreurs erreur(s)';
    } else if (introuvables > 0) {
      message = '⏳ Résultats PMU pas encore publiés pour ${introuvables} course(s) — réessayez après 20h';
    } else {
      message = '❌ Aucun résultat récupéré ($erreurs erreur(s) réseau)';
    }

    return {
      'recuperes':    recuperes,
      'introuvables': introuvables,
      'erreurs':      erreurs,
      'total':        aRelancer.length,
      'details':      details,
      'message':      message,
    };
  }

  /// Contrairement à _purgerVieuxPronostics() qui ne supprime qu'après 60 jours,
  /// cette méthode supprime TOUS les pronostics sans résultat quelle que soit
  /// leur ancienneté — utile pour nettoyer les courses étrangères accumulées.
  ///
  /// Retourne le nombre de pronostics supprimés.
  Future<int> purgerCoursesSansResultat() async {
    await _load();
    final avant = _pronostics.length;

    _pronostics.removeWhere((p) => !p.resultatsReels);

    final supprime = avant - _pronostics.length;
    if (supprime > 0) {
      await _save();
      debugPrint('[IaMemory] 🧹 Purge manuelle : $supprime pronostics sans résultat supprimés');
    }
    return supprime;
  }

  /// Retourne le nombre de pronostics sans résultat réel (pour affichage).
  int get nbPronosticsSansResultat =>
      _pronostics.where((p) => !p.resultatsReels).length;

  // ── Cache en mémoire des arrivées déjà récupérées (courseKey → List<int>) ──
  // Évite de rappeler l'API PMU à chaque rebuild (30s timer dans les écrans).
  final Map<String, List<int>> _arriveeCache = {};
  // Clés dont la récupération est EN COURS (évite les appels parallèles)
  final Set<String> _arriveeEnCours = {};

  /// Retourne l'arrivée connue pour une course (null = pas encore disponible).
  /// Cherche d'abord dans le cache RAM, puis dans les pronostics IA.
  List<int>? arriveeConnue(String courseKey) {
    if (_arriveeCache.containsKey(courseKey)) return _arriveeCache[courseKey];
    final p = _pronostics
        .where((p) => p.courseKey == courseKey && p.resultatsReels)
        .firstOrNull;
    if (p?.arriveeReelle != null && p!.arriveeReelle!.isNotEmpty) {
      _arriveeCache[courseKey] = p.arriveeReelle!;
      return p.arriveeReelle;
    }
    return null;
  }

  /// Récupère l'arrivée PMU directement pour n'importe quelle course terminée,
  /// même si aucun pronostic/pari n'a été enregistré pour elle.
  ///
  /// [courseKey]  : clé au format \"R{numR}C{numC}_{JJMMAAAA}\"
  /// [heureDepart]: heure réelle de la course (pour construire la date PMU)
  ///
  /// Retourne la liste des numéros dans l'ordre d'arrivée (vide si pas dispo).
  /// Le résultat est mis en cache RAM pour éviter les appels répétés.
  Future<List<int>> fetchArriveeDirecte({
    required String courseKey,
    required DateTime heureDepart,
  }) async {
    // Déjà en cache → retour immédiat
    if (_arriveeCache.containsKey(courseKey)) return _arriveeCache[courseKey]!;
    // Appel déjà en cours → ne pas doubler
    if (_arriveeEnCours.contains(courseKey)) return [];

    // Extraire numR et numC depuis courseKey (format R3C5_23042026)
    final match = RegExp(r'^R(\d+)C(\d+)_').firstMatch(courseKey);
    if (match == null) return [];
    final numR = match.group(1)!;
    final numC = match.group(2)!;

    final d = heureDepart;
    final dateStr =
        '${d.day.toString().padLeft(2, '0')}'
        '${d.month.toString().padLeft(2, '0')}'
        '${d.year}';

    _arriveeEnCours.add(courseKey);
    try {
      final url =
          'https://turfinfo.api.pmu.fr/rest/client/7'
          '/programme/$dateStr/R$numR/C$numC'
          '/rapports-definitifs?specialisation=INTERNET';

      final resp = await http
          .get(Uri.parse(url), headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        // Résultats PMU pas encore publiés — on réessaiera au prochain cycle
        _arriveeEnCours.remove(courseKey);
        return [];
      }

      final List<dynamic> rapports = jsonDecode(resp.body) as List<dynamic>;
      final List<int> arrivee = [];

      for (final r in rapports) {
        final typePari = r['typePari'] as String? ?? '';
        final rList = (r['rapports'] as List<dynamic>? ?? []);
        if (rList.isEmpty) continue;

        // Simple Gagnant → 1er cheval
        if (typePari == 'E_SIMPLE_GAGNANT' && arrivee.isEmpty) {
          final rap = rList.first as Map<String, dynamic>;
          final n = int.tryParse(rap['combinaison']?.toString() ?? '');
          if (n != null && !arrivee.contains(n)) arrivee.add(n);
        }

        // Simple Placé → top 3
        if (typePari == 'E_SIMPLE_PLACE') {
          for (final item in rList) {
            final n = int.tryParse(
                (item as Map)['combinaison']?.toString() ?? '');
            if (n != null && !arrivee.contains(n)) arrivee.add(n);
          }
        }

        // Tiercé / Quarté / Quinté ORDRE → arrivée complète
        final isOrdre = (typePari.contains('TIERCE') ||
                         typePari.contains('TIERCÉ') ||
                         typePari.contains('QUARTE') ||
                         typePari.contains('QUINTE')) &&
                        !typePari.contains('DESORDRE') &&
                        !typePari.contains('DÉSORDRE') &&
                        !typePari.contains('4SUR5') &&
                        !typePari.contains('4_SUR_5');
        if (isOrdre) {
          final rap = rList.first as Map<String, dynamic>;
          final combo = rap['combinaison']?.toString() ?? '';
          for (final part in combo.split('-')) {
            final n = int.tryParse(part.trim());
            if (n != null && !arrivee.contains(n)) arrivee.add(n);
          }
        }
      }

      if (arrivee.isNotEmpty) {
        // Mettre en cache RAM
        _arriveeCache[courseKey] = arrivee;
        if (kDebugMode) {
          debugPrint('[IaMemory] ✅ Arrivée directe $courseKey : '
              '${arrivee.take(5).map((n) => "N°$n").join(" - ")}');
        }
        // Si un pronostic IA existe pour cette course → mettre à jour aussi
        await _load();
        final idx = _pronostics.indexWhere((p) => p.courseKey == courseKey);
        if (idx >= 0 && !_pronostics[idx].resultatsReels) {
          await enregistrerResultat(
            courseKey: courseKey,
            arriveeReelle: arrivee,
          );
        }
        notifyListeners();
      }

      _arriveeEnCours.remove(courseKey);
      return arrivee;
    } catch (e) {
      if (kDebugMode) debugPrint('[IaMemory] fetchArriveeDirecte erreur $courseKey : $e');
      _arriveeEnCours.remove(courseKey);
      return [];
    }
  }

  /// Force le rechargement complet depuis SharedPreferences.
  /// Utilisé après une restauration backup pour mettre à jour
  /// la RAM avec les données restaurées (poids IA, pronostics, journal…).
  Future<void> recharger() async {
    _loaded = false;
    _loadCompleter = null; // ★ v9.90 : forcer un nouveau cycle de chargement
    _pronostics.clear();
    _journal.clear();
    _rapports.clear();
    _bilansSemaine.clear(); // ★ v9.91
    _bilansMois.clear();    // ★ v9.91
    _statsTypes.clear();
    _statsLabels.clear();    // ✅ Fix audit : doublon supprimé (était appelé 2× inutilement)
    _precisionParType.clear();
    _seuils = SeuilsConfianceAdaptatifs();
    _poids = IaPoidsAdaptatifs.defaut();
    await _load();
    notifyListeners();
  }

  Future<void> _load() async {
    if (_loaded) return;
    if (_loadCompleter != null) return _loadCompleter!.future;
    _loadCompleter = Completer<void>();
    try {
      final prefs = await SharedPreferences.getInstance();

      final poidsStr = prefs.getString(_poidsKey);
      if (poidsStr != null) {
        _poids = IaPoidsAdaptatifs.fromJson(
            json.decode(poidsStr) as Map<String, dynamic>);
      }

      // ★ Lot 4 : Tenter de charger la version compressée en premier
      final b64Gz = prefs.getString(_compressionKey);
      if (b64Gz != null && b64Gz.isNotEmpty) {
        try {
          final gzipped   = base64Decode(b64Gz);
          final bytes     = GZipCodec().decode(gzipped);
          final jsonStr   = utf8.decode(bytes);
          final List<dynamic> rawList = json.decode(jsonStr) as List<dynamic>;
          _pronostics.clear();
          for (final item in rawList) {
            try {
              _pronostics.add(IaPronostic.fromJson(item as Map<String, dynamic>));
            } catch (_) {}
          }
          debugPrint('[IaMemory] ✅ ${_pronostics.length} pronostics chargés (compressés)');
        } catch (e) {
          debugPrint('[IaMemory] ⚠️ Décompression échouée, fallback : $e');
          // Fallback vers ancienne clé non compressée
          final raw = prefs.getStringList(_pronosticsKey) ?? [];
          _pronostics.clear();
          for (final s in raw) {
            try {
              _pronostics.add(IaPronostic.fromJson(json.decode(s) as Map<String, dynamic>));
            } catch (_) {}
          }
        }
      } else {
        // Ancienne clé non compressée (migration depuis version antérieure)
        final raw = prefs.getStringList(_pronosticsKey) ?? [];
        _pronostics.clear();
        for (final s in raw) {
          try {
            _pronostics.add(IaPronostic.fromJson(json.decode(s) as Map<String, dynamic>));
          } catch (_) {}
        }
      }

      final jRaw = prefs.getStringList(_journalKey) ?? [];
      _journal.clear();
      for (final s in jRaw) {
        try {
          _journal.add(JournalEntree.fromJson(
              json.decode(s) as Map<String, dynamic>));
        } catch (_) {}
      }

      // ★ Chargement des rapports journaliers
      final rRaw = prefs.getStringList(_rapportsKey) ?? [];
      _rapports.clear();
      for (final s in rRaw) {
        try {
          _rapports.add(RapportJournalier.fromJson(
              json.decode(s) as Map<String, dynamic>));
        } catch (_) {}
      }

      // ★ v9.91 : Chargement des bilans semaine et mois
      final bsRaw = prefs.getStringList(_bilansSemaineKey) ?? [];
      _bilansSemaine.clear();
      for (final s in bsRaw) {
        try {
          _bilansSemaine.add(BilanSemaine.fromJson(
              json.decode(s) as Map<String, dynamic>));
        } catch (_) {}
      }
      final bmRaw = prefs.getStringList(_bilansMoisKey) ?? [];
      _bilansMois.clear();
      for (final s in bmRaw) {
        try {
          _bilansMois.add(BilanMois.fromJson(
              json.decode(s) as Map<String, dynamic>));
        } catch (_) {}
      }

      // ★ Chargement des stats par type de pari
      final stRaw = prefs.getStringList(_statsTypesKey) ?? [];
      _statsTypes.clear();
      for (final s in stRaw) {
        try {
          final st = StatsTypePari.fromJson(json.decode(s) as Map<String, dynamic>);
          _statsTypes[st.typePari] = st;
        } catch (_) {}
      }

      // ★ Chargement de la précision IA par type de pari
      final prStr = prefs.getString(_precisionIAKey);
      if (prStr != null) {
        try {
          final prMap = json.decode(prStr) as Map<String, dynamic>;
          _precisionParType.clear();
          for (final entry in prMap.entries) {
            try {
              _precisionParType[entry.key] =
                  StatsPrecisionParType.fromJson(entry.value as Map<String, dynamic>);
            } catch (_) {}
          }
        } catch (_) {}
      }
      // ★ v9.0 : Chargement des stats par label IA
      final labelsStr = prefs.getString(_statsLabelsKey);
      if (labelsStr != null) {
        try {
          final labelsMap = json.decode(labelsStr) as Map<String, dynamic>;
          _statsLabels.clear();
          for (final entry in labelsMap.entries) {
            try {
              _statsLabels[entry.key] =
                  StatsParLabel.fromJson(entry.value as Map<String, dynamic>);
            } catch (_) {}
          }
        } catch (_) {}
      }
      // ★ Chargement des seuils de confiance adaptatifs
      final seuilsStr = prefs.getString(_seuilsKey);
      if (seuilsStr != null) {
        try {
          _seuils = SeuilsConfianceAdaptatifs.fromJson(
              json.decode(seuilsStr) as Map<String, dynamic>);
        } catch (_) {}
      }

      // ★ v6.0 : synchroniser IaCalibrationRegistry au chargement
      IaCalibrationRegistry.update(_poids.calibrationScore);

      // ★ v9.95 : migration one-shot — recalcul de _precisionParType depuis
      // les pronostics bruts pour corriger le double-comptage historique.
      // Exécutée UNE SEULE FOIS grâce au flag 'ia_precision_migrated_v2'.
      final flagMigration = prefs.getBool('ia_precision_migrated_v2') ?? false;
      if (!flagMigration && _pronostics.any((p) => p.resultatsReels)) {
        await _recalculerPrecisionParTypeDepuisPronostics();
        await prefs.setBool('ia_precision_migrated_v2', true);
        if (kDebugMode) {
          debugPrint('[IaMemory] ✅ Flag ia_precision_migrated_v2 posé.');
        }
      }

      _loaded = true;
      _loadCompleter!.complete();
      _loadCompleter = null;
    } catch (e) {
      if (kDebugMode) debugPrint('IaMemoryService._load error: $e');
      _loadCompleter?.completeError(e);
      _loadCompleter = null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  ★ v9.91 : BASCULE AUTOMATIQUE — hiérarchie Journal
  //
  //  Règle semaine : chaque lundi matin, les rapports de la semaine
  //  précédente (lun→dim) basculent dans un BilanSemaine archivé.
  //  Ils restent dans _rapports mais ne s'affichent plus dans la vue
  //  principale du journal (le journal les retrouve via bilansSemaine).
  //
  //  Règle mois : le 1er de chaque mois, les BilanSemaine du mois
  //  précédent basculent dans un BilanMois archivé.
  // ═══════════════════════════════════════════════════════════════════════
  void _basculerBilans() {
    final now    = DateTime.now();
    final today  = DateTime(now.year, now.month, now.day);

    // ── 1. Bascule semaine ────────────────────────────────────────────────
    // Calculer le lundi de la semaine en cours
    final lundiCourant = today.subtract(Duration(days: today.weekday - 1));

    // Rapports qui appartiennent à des semaines PASSÉES (avant lundi courant)
    // et qui ne sont pas encore dans un BilanSemaine
    final rapportsArchives = <String>{};
    for (final bs in _bilansSemaine) {
      rapportsArchives.addAll(bs.rapportsJson);
    }

    // Grouper les rapports passés par semaine
    final Map<DateTime, List<RapportJournalier>> parSemaine = {};
    for (final r in _rapports) {
      final rDay = DateTime(r.date.year, r.date.month, r.date.day);
      if (rDay.isBefore(lundiCourant)) {
        // Calculer le lundi de cette semaine
        final lundi = rDay.subtract(Duration(days: rDay.weekday - 1));
        parSemaine.putIfAbsent(lundi, () => []).add(r);
      }
    }

    // Créer les BilanSemaine manquants
    for (final entry in parSemaine.entries) {
      final lundi    = entry.key;
      final dimanche = lundi.add(const Duration(days: 6));
      // Vérifier si ce bilan existe déjà
      final existe = _bilansSemaine.any((bs) =>
          bs.lundi.year  == lundi.year &&
          bs.lundi.month == lundi.month &&
          bs.lundi.day   == lundi.day);
      if (existe) continue;

      final rjs = entry.value..sort((a, b) => a.date.compareTo(b.date));
      int tc = 0, tr = 0, tg = 0, tt3 = 0;
      double sm = 0;
      final Map<String, int> discNb = {}, discGn = {};
      for (final r in rjs) {
        tc += r.nbCoursesAnalysees;
        tr += r.nbAvecResultat;
        tg += r.favoriGagnant;
        tt3+= r.favoriTop3;
        sm += r.scoreMoyenJour;
        for (final d in r.parDiscipline) {
          discNb[d.discipline] = (discNb[d.discipline] ?? 0) + d.nbCourses;
          discGn[d.discipline] = (discGn[d.discipline] ?? 0) + d.favoriGagnant;
        }
      }
      String md = ''; double mt = -1;
      discNb.forEach((disc, nb) {
        if (nb >= 2) {
          final t = (discGn[disc] ?? 0) / nb * 100;
          if (t > mt) { mt = t; md = disc; }
        }
      });

      final newBilan = BilanSemaine(
        lundi:          lundi,
        dimanche:       dimanche,
        rapportsJson:   rjs.map((r) => json.encode(r.toJson())).toList(),
        totalCourses:   tc,
        totalResultats: tr,
        totalGagnant:   tg,
        totalTop3:      tt3,
        scoreMoyen:     rjs.isNotEmpty ? sm / rjs.length : 0,
        meilleureDisc:  md,
        meilleurTaux:   mt < 0 ? 0 : mt,
      );
      _bilansSemaine.add(newBilan);
      // ★ v9.93 : Mémoriser pour bulle hebdo au prochain démarrage
      _pendingBilanHebdo = newBilan;
    }

    // Trier par date
    _bilansSemaine.sort((a, b) => a.lundi.compareTo(b.lundi));

    // ── 2. Bascule mois ───────────────────────────────────────────────────
    // Le 1er du mois courant, les semaines du mois précédent → BilanMois
    final moisCourant  = DateTime(now.year, now.month);

    // BilanSemaine du mois précédent qui ne sont pas encore dans un BilanMois
    final semainesArchivees = <DateTime>{};
    for (final bm in _bilansMois) {
      for (final bs in bm.semaines) {
        semainesArchivees.add(bs.lundi);
      }
    }

    final Map<String, List<BilanSemaine>> parMois = {};
    for (final bs in _bilansSemaine) {
      // Appartient au mois précédent ou avant ?
      final moisSemaine = DateTime(bs.lundi.year, bs.lundi.month);
      if (!moisSemaine.isBefore(moisCourant)) continue;
      if (semainesArchivees.contains(bs.lundi)) continue;
      final key = '${bs.lundi.year}-${bs.lundi.month}';
      parMois.putIfAbsent(key, () => []).add(bs);
    }

    for (final entry in parMois.entries) {
      final parts = entry.key.split('-');
      final annee = int.parse(parts[0]);
      final mois  = int.parse(parts[1]);
      final existe = _bilansMois.any((bm) =>
          bm.annee == annee && bm.mois == mois);
      if (existe) continue;

      final semaines = entry.value..sort((a, b) => a.lundi.compareTo(b.lundi));
      int tc = 0, tr = 0, tg = 0, tt3 = 0;
      double sm = 0;
      final Map<String, int> discNb = {}, discGn = {};
      for (final bs in semaines) {
        tc += bs.totalCourses;
        tr += bs.totalResultats;
        tg += bs.totalGagnant;
        tt3+= bs.totalTop3;
        sm += bs.scoreMoyen;
        if (bs.meilleureDisc.isNotEmpty) {
          discNb[bs.meilleureDisc] = (discNb[bs.meilleureDisc] ?? 0) + bs.totalCourses;
          discGn[bs.meilleureDisc] = (discGn[bs.meilleureDisc] ?? 0) + bs.totalGagnant;
        }
      }
      String md = ''; double mt = -1;
      discNb.forEach((disc, nb) {
        if (nb >= 3) {
          final t = (discGn[disc] ?? 0) / nb * 100;
          if (t > mt) { mt = t; md = disc; }
        }
      });

      _bilansMois.add(BilanMois(
        annee:          annee,
        mois:           mois,
        semaines:       semaines,
        totalCourses:   tc,
        totalResultats: tr,
        totalGagnant:   tg,
        totalTop3:      tt3,
        scoreMoyen:     semaines.isNotEmpty ? sm / semaines.length : 0,
        meilleureDisc:  md,
        meilleurTaux:   mt < 0 ? 0 : mt,
      ));
    }

    _bilansMois.sort((a, b) {
      final ca = a.annee * 100 + a.mois;
      final cb = b.annee * 100 + b.mois;
      return ca.compareTo(cb);
    });
  }

  Future<void> _save() async {
    try {
      // ★ Lot 4 : Purger les vieux pronostics avant sauvegarde
      _purgerVieuxPronostics();
      // ★ v9.91 : Bascule automatique des rapports dans la hiérarchie semaine/mois
      _basculerBilans();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_poidsKey, json.encode(_poids.toJson()));
      // ★ Lot 4 : Compression des pronostics si activée
      final pronosticsAsSauvegarder = _pronostics.take(_maxPronostics).toList();
      if (_useCompression && pronosticsAsSauvegarder.length > 20) {
        // Encoder en JSON unique puis compresser en gzip
        final jsonStr  = json.encode(pronosticsAsSauvegarder.map((p) => p.toJson()).toList());
        final bytes    = utf8.encode(jsonStr);
        final gzipped  = GZipCodec().encode(bytes);
        final b64      = base64Encode(gzipped);
        await prefs.setString(_compressionKey, b64);
        await prefs.remove(_pronosticsKey); // supprimer l'ancienne clé non compressée
      } else {
        await prefs.setStringList(_pronosticsKey,
            pronosticsAsSauvegarder.map((p) => json.encode(p.toJson())).toList());
        await prefs.remove(_compressionKey);
      }
      await prefs.setStringList(_journalKey,
          _journal.take(_maxJournal).map((e) => json.encode(e.toJson())).toList());
      // ★ Sauvegarde des rapports journaliers
      await prefs.setStringList(_rapportsKey,
          _rapports.take(_maxRapports).map((r) => json.encode(r.toJson())).toList());
      // ★ v9.91 : Sauvegarde des bilans semaine et mois
      await prefs.setStringList(_bilansSemaineKey,
          _bilansSemaine.map((s) => json.encode(s.toJson())).toList());
      await prefs.setStringList(_bilansMoisKey,
          _bilansMois.map((m) => json.encode(m.toJson())).toList());
      // ★ Sauvegarde des stats par type de pari
      await prefs.setStringList(_statsTypesKey,
          _statsTypes.values.map((s) => json.encode(s.toJson())).toList());
      // ★ Sauvegarde de la précision IA par type de pari
      await prefs.setString(_precisionIAKey, json.encode(
          _precisionParType.map((k, v) => MapEntry(k, v.toJson()))));
      // ★ Sauvegarde des seuils de confiance adaptatifs
      await prefs.setString(_seuilsKey, json.encode(_seuils.toJson()));
      // ★ v9.0 : Sauvegarde des stats par label IA
      await prefs.setString(_statsLabelsKey, json.encode(
          _statsLabels.map((k, v) => MapEntry(k, v.toJson()))));
    } catch (e) {
      if (kDebugMode) debugPrint('IaMemoryService._save error: $e');
    }
  }

  // ── Enregistrement d'un pronostic avec scores par critère ──────────────────

  Future<void> enregistrerPronostic({
    required String courseKey,
    required ZtCourse course,
    required List<ZtPartant> partantsClasses,
    Map<String, ScoresCriteres>? scoresCriteresMap,
    double? confiancePredite,
    String? typePariConseille,
  }) async {
    await _load();
    if (_pronostics.any((p) => p.courseKey == courseKey)) return;

    final scores = <String, double>{};
    for (final p in partantsClasses) {
      scores[p.numero] = p.scoreIA;
    }

    // Calculer la variance des scores pour mesurer la clarté du champ
    double? variance;
    if (scores.length >= 3) {
      final values = scores.values.toList();
      final mean = values.reduce((a, b) => a + b) / values.length;
      final squaredDiffs = values.map((v) => (v - mean) * (v - mean));
      variance = squaredDiffs.reduce((a, b) => a + b) / values.length;
    }

    // Extraire le hippodrome depuis les partants si disponible
    final hippo = partantsClasses.isNotEmpty
        ? (partantsClasses.first.hippodromeActuel.isNotEmpty
            ? partantsClasses.first.hippodromeActuel
            : course.nom.split('—').last.trim())
        : '';

    // ★ v5 : Calculer tauxReussiteAuMoment (taux historique du type de pari au moment T)
    double? tauxR;
    if (typePariConseille != null && _precisionParType.containsKey(typePariConseille)) {
      tauxR = _precisionParType[typePariConseille]!.tauxReussite;
    }

    // ★ v5 : Calculer precisionIA synthèse des 3 indices
    double? precIA;
    if (confiancePredite != null) {
      final bestScore = scores.values.isEmpty ? 0.0 : scores.values.reduce((a, b) => a > b ? a : b);
      precIA = _poids.poidsIndices.calculerPrecision(
        scoreCriteres: bestScore,
        confianceIA:   confiancePredite,
        tauxReussite:  tauxR ?? 50.0, // 50% neutre si pas d'historique
      );
    }

    // ★ v9.6 : Récupérer le nom du cheval favori IA
    final favoriNum = scores.isEmpty ? null
        : scores.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    final favoriPartant = favoriNum != null
        ? partantsClasses.where((p) => p.numero == favoriNum).firstOrNull
        : null;
    final favoriNom = favoriPartant?.nom;

    final pronostic = IaPronostic(
      courseKey: courseKey,
      nomCourse: course.nom.isNotEmpty ? course.nom : 'Course ${course.numCourse}',
      hippodrome: hippo,
      discipline: course.type,
      datePronostic: DateTime.now(),
      scoresIA: scores,
      scoresCriteres: scoresCriteresMap ?? {},
      varianceScores: variance,
      confiancePredite: confiancePredite,
      typePariConseille: typePariConseille,
      tauxReussiteAuMoment: tauxR,
      precisionIA: precIA,
      favoriIaNom: favoriNom,
    );

    _pronostics.insert(0, pronostic);
    if (_pronostics.length > _maxPronostics) _pronostics.removeLast();
    await _save();
    notifyListeners();
  }

  // ── Enregistrement batch de pronostics (sans save intermédiaire) ─────────
  // Utilisé par DataRefreshService pour enregistrer tous les pronostics du
  // jour en une seule passe — un seul appel _save() à la fin.
  Future<void> enregistrerPronosticsBatch(List<Map<String, dynamic>> items) async {
    await _load();
    int nbAjoutes = 0;

    for (final item in items) {
      final courseKey        = item['courseKey'] as String;
      final course           = item['course'] as ZtCourse;
      final partantsClasses  = item['partantsClasses'] as List<ZtPartant>;
      final scoresCriteres   = item['scoresCriteres'] as Map<String, ScoresCriteres>;
      final confiance        = (item['confiance'] as num).toDouble();
      final typePariItem     = item['typePariConseille'] as String?;

      // Anti-doublon
      if (_pronostics.any((p) => p.courseKey == courseKey)) continue;

      final scores = <String, double>{};
      for (final p in partantsClasses) {
        scores[p.numero] = p.scoreIA;
      }

      double? variance;
      if (scores.length >= 3) {
        final values = scores.values.toList();
        final mean = values.reduce((a, b) => a + b) / values.length;
        variance = values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / values.length;
      }

      final hippoB = partantsClasses.isNotEmpty
          ? (partantsClasses.first.hippodromeActuel.isNotEmpty
              ? partantsClasses.first.hippodromeActuel
              : '')
          : '';

      // ★ v5 : tauxReussiteAuMoment + precisionIA synthèse 3 indices
      double? tauxRB;
      if (typePariItem != null && _precisionParType.containsKey(typePariItem)) {
        tauxRB = _precisionParType[typePariItem]!.tauxReussite;
      }
      final bestScoreB = scores.values.isEmpty ? 0.0 : scores.values.reduce((a, b) => a > b ? a : b);
      final precIAB = _poids.poidsIndices.calculerPrecision(
        scoreCriteres: bestScoreB,
        confianceIA:   confiance,
        tauxReussite:  tauxRB ?? 50.0,
      );

      // ★ v9.6 : Nom du cheval favori IA
      final bFavoriNum = scores.isEmpty ? null
          : scores.entries.reduce((a, b) => a.value > b.value ? a : b).key;
      final bFavoriNom = bFavoriNum != null
          ? course.partants.where((p) => p.numero == bFavoriNum).firstOrNull?.nom
          : null;

      _pronostics.insert(0, IaPronostic(
        courseKey: courseKey,
        nomCourse: course.nom.isNotEmpty ? course.nom : 'Course ${course.numCourse}',
        hippodrome: hippoB,
        discipline: course.type,
        datePronostic: course.heureDateTime,
        scoresIA: scores,
        scoresCriteres: scoresCriteres,
        varianceScores: variance,
        confiancePredite: confiance,
        typePariConseille: typePariItem,
        tauxReussiteAuMoment: tauxRB,
        precisionIA: precIAB,
        favoriIaNom: bFavoriNom,
      ));
      if (_pronostics.length > _maxPronostics) _pronostics.removeLast();
      nbAjoutes++;
    }

    if (nbAjoutes > 0) {
      await _save();       // un seul save pour toutes les courses
      notifyListeners();
    }
  }

  // ── Enregistrement du résultat réel ────────────────────────────────────────

  /// Invalide un pronostic existant (suite à DQ/retrait/blessure) et le
  /// remplace par un nouveau pronostic recalculé sans les chevaux hors course.
  ///
  /// Si le pronostic a déjà un résultat réel (`resultatsReels == true`),
  /// on NE recalcule PAS (la course est terminée, rien à faire).
  Future<void> invaliderEtRecalculer({
    required String courseKey,
    required ZtCourse course,
    required List<ZtPartant> partantsClasses,
    required Map<String, ScoresCriteres> scoresCriteres,
    required double confiance,
    String raisonInvalidation = '',
  }) async {
    await _load();

    final idx = _pronostics.indexWhere((p) => p.courseKey == courseKey);

    // Si le pronostic existe et a déjà un résultat → ne pas toucher
    if (idx >= 0 && _pronostics[idx].resultatsReels) {
      debugPrint('[IaMem] invaliderEtRecalculer: $courseKey a déjà un résultat réel — ignoré');
      return;
    }

    // Calculer les nouveaux scores
    final scores = <String, double>{};
    for (final p in partantsClasses) {
      scores[p.numero] = p.scoreIA;
    }

    double? variance;
    if (scores.length >= 3) {
      final values = scores.values.toList();
      final mean = values.reduce((a, b) => a + b) / values.length;
      variance = values.map((v) => (v - mean) * (v - mean))
                       .reduce((a, b) => a + b) / values.length;
    }

    final hippoI = partantsClasses.isNotEmpty
        ? (partantsClasses.first.hippodromeActuel.isNotEmpty
            ? partantsClasses.first.hippodromeActuel
            : (idx >= 0 ? _pronostics[idx].hippodrome : ''))
        : (idx >= 0 ? _pronostics[idx].hippodrome : '');

    // ★ v82 : récupérer le typePariConseille de l'ancien pronostic et le taux de réussite actuel
    final ancienTypePari = idx >= 0 ? _pronostics[idx].typePariConseille : null;
    double? tauxRInval;
    if (ancienTypePari != null && _precisionParType.containsKey(ancienTypePari)) {
      tauxRInval = _precisionParType[ancienTypePari]!.tauxReussite;
    }
    final bestScoreInval = scores.values.isEmpty ? 0.0 : scores.values.reduce((a, b) => a > b ? a : b);
    final precIAInval = _poids.poidsIndices.calculerPrecision(
      scoreCriteres: bestScoreInval,
      confianceIA:   confiance,
      tauxReussite:  tauxRInval ?? 50.0,
    );

    final nouveauPronostic = IaPronostic(
      courseKey: courseKey,
      nomCourse: course.nom.isNotEmpty ? course.nom : 'Course ${course.numCourse}',
      hippodrome: hippoI,
      discipline: course.type,
      // Conserver la date originale si possible, sinon maintenant
      datePronostic: idx >= 0
          ? _pronostics[idx].datePronostic
          : course.heureDateTime,
      scoresIA: scores,
      scoresCriteres: scoresCriteres,
      varianceScores: variance,
      confiancePredite: confiance,
      // ★ v82 : préserver les champs d'apprentissage (typePari inchangé, taux mis à jour)
      typePariConseille:    ancienTypePari,
      tauxReussiteAuMoment: tauxRInval,
      precisionIA:          precIAInval,
      // ★ fix : recalculer favoriIaNom depuis les nouveaux scores (invalider = recalcul complet)
      favoriIaNom: scores.isEmpty ? null
          : partantsClasses
              .where((p) => p.numero == scores.entries
                  .reduce((a, b) => a.value > b.value ? a : b).key)
              .firstOrNull?.nom,
    );

    if (idx >= 0) {
      _pronostics[idx] = nouveauPronostic;
      debugPrint('[IaMem] Pronostic mis à jour (invalidé+recalculé): $courseKey'
          '${raisonInvalidation.isNotEmpty ? " — $raisonInvalidation" : ""}');
    } else {
      _pronostics.insert(0, nouveauPronostic);
      if (_pronostics.length > _maxPronostics) _pronostics.removeLast();
      debugPrint('[IaMem] Nouveau pronostic créé (post-DQ): $courseKey');
    }

    await _save();
    notifyListeners();
  }

  Future<void> enregistrerResultat({
    required String courseKey,
    required List<int> arriveeReelle,
  }) async {
    await _load();

    final idx = _pronostics.indexWhere((p) => p.courseKey == courseKey);
    if (idx < 0) return;

    final p = _pronostics[idx];
    if (p.resultatsReels) return;

    final topIA      = p.topNIA;
    final arriveeStr = arriveeReelle.map((n) => n.toString()).toList();

    final favori     = topIA.isNotEmpty ? topIA.first : null;
    final idxFavori  = favori != null ? arriveeStr.indexOf(favori) : -1;
    final rangFavori = idxFavori >= 0 ? idxFavori + 1 : null;

    final top3IA   = topIA.take(3).toSet();
    final top3Reel = arriveeStr.take(3).toSet();
    final nbTop3   = top3IA.intersection(top3Reel).length;

    final top5IA   = topIA.take(5).toSet();
    final top5Reel = arriveeStr.take(5).toSet();
    final nbTop5   = top5IA.intersection(top5Reel).length;

    // ★ v83 : pondération par taille du peloton
    // Un grand peloton (16+ partants) est plus difficile → bonus si IA réussit
    // Un petit peloton (≤5 partants) est plus facile → pas de bonus
    final nbPartants = arriveeStr.length.clamp(4, 20);
    final bonusPeloton = nbPartants >= 16 ? 1.15
        : nbPartants >= 12 ? 1.08
        : nbPartants >= 8  ? 1.03
        : 1.0; // peloton ≤7 : pas de bonus

    double scorePerfRaw = 0;
    if (rangFavori == 1)                       scorePerfRaw += 40;
    else if (rangFavori != null && rangFavori <= 3) scorePerfRaw += 20;
    else if (rangFavori != null && rangFavori <= 5) scorePerfRaw += 10;
    scorePerfRaw += nbTop3 * 15.0;
    scorePerfRaw += nbTop5 * 5.0;
    final scorePerf = (scorePerfRaw * bonusPeloton).clamp(0.0, 100.0);

    // ★ v82 : recalculer precisionIA avec les poids courants après résultat
    final bestScoreR = p.scoresIA.values.isEmpty ? 0.0 :
        p.scoresIA.values.reduce((a, b) => a > b ? a : b);
    final confR = p.confiancePredite ?? 65.0;
    final tauxMomentR = p.tauxReussiteAuMoment ?? 50.0;
    final precIAR = _poids.poidsIndices.calculerPrecision(
      scoreCriteres: bestScoreR,
      confianceIA:   confR,
      tauxReussite:  tauxMomentR,
    );

    // ★ v9.94 : générer le diagnostic par course au moment où le résultat est connu
    final diagCourse = _genererDiagnosticCourse(
      favoriNom:  p.favoriIaNom,
      rangFavori: rangFavori,
      nbTop3:     nbTop3,
      nbTop5:     nbTop5,
      scorePerf:  scorePerf,
      typePari:   p.typePariConseille,
    );

    _pronostics[idx] = IaPronostic(
      courseKey:              p.courseKey,
      nomCourse:              p.nomCourse,
      hippodrome:             p.hippodrome,
      discipline:             p.discipline,
      datePronostic:          p.datePronostic,
      scoresIA:               p.scoresIA,
      scoresCriteres:         p.scoresCriteres,
      varianceScores:         p.varianceScores,
      arriveeReelle:          arriveeReelle,
      dateResultat:           DateTime.now(),
      resultatsReels:         true,
      rangFavoriIaDansArrivee: rangFavori,
      nbTop3DansArriveeReelle: nbTop3,
      nbTop5DansArriveeReelle: nbTop5,
      scorePerformance:       scorePerf,
      confiancePredite:       p.confiancePredite,
      // ★ v80/v81 : préserver les champs d'apprentissage
      typePariConseille:      p.typePariConseille,
      tauxReussiteAuMoment:   p.tauxReussiteAuMoment,
      precisionIA:            precIAR,
      // ★ fix : préserver favoriIaNom (champ perdu avant ce fix)
      favoriIaNom:            p.favoriIaNom,
      // ★ v9.94 : diagnostic lisible par course (était toujours null avant ce fix)
      diagnosticApprentissage: diagCourse,
    );

    await _save();
    await _apprendreParGradient();
    await _apprendreParDiscipline(p.discipline);
    await _mettreAJourCalibration();
    // ★ v9.95 : suppression de l'appel _mettreAJourPrecisionIA ici.
    // analyseJourneeComplete() est la source UNIQUE de mise à jour de
    // _precisionParType via _mettreAJourPrecisionIA (uniquement les
    // pronostics nouvellement résolus). Appeler ici causait un
    // double-comptage pour tous les types de paris (×2 dans historiqueComplet).
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  MOTEUR D'APPRENTISSAGE GLOBAL PAR GRADIENT
  //
  //  Principe : pour chaque critère, on mesure s'il discrimine correctement
  //  les chevaux bien classés des chevaux mal classés.
  //
  //  Score de discrimination d'un critère X :
  //    discrim(X) = moyenne_score_X(chevaux_top3_réel) 
  //               - moyenne_score_X(chevaux_hors_top3_réel)
  //
  //  Si discrim > 0 → le critère identifie bien les bons chevaux → augmenter
  //  Si discrim ≈ 0 → le critère ne distingue pas → maintenir/réduire
  //  Si discrim < 0 → le critère trompe l'IA → réduire fortement
  //
  //  Le delta appliqué est proportionnel à la discrimination mesurée.
  // ══════════════════════════════════════════════════════════════════════════

  // ══════════════════════════════════════════════════════════════════════════
  //  DIAGNOSTIC PAR COURSE (v9.94)
  //
  //  Génère un texte lisible décrivant la performance de l'IA sur une course
  //  donnée, stocké dans IaPronostic.diagnosticApprentissage.
  //
  //  Paramètres :
  //   • favoriNom    : nom du cheval favori IA
  //   • rangFavori   : rang réel du favori dans l'arrivée (null = absent)
  //   • nbTop3       : combien de chevaux top3 IA sont dans le top3 réel
  //   • nbTop5       : combien de chevaux top5 IA sont dans le top5 réel
  //   • scorePerf    : score de performance calculé (0–100)
  //   • typePari     : type de pari conseillé
  // ══════════════════════════════════════════════════════════════════════════
  String _genererDiagnosticCourse({
    required String? favoriNom,
    required int? rangFavori,
    required int nbTop3,
    required int nbTop5,
    required double scorePerf,
    required String? typePari,
  }) {
    final buf = StringBuffer();

    // Ligne 1 : résultat du favori IA
    if (favoriNom != null && favoriNom.isNotEmpty) {
      if (rangFavori == 1) {
        buf.writeln('✅ Favori IA $favoriNom → 1er ');
      } else if (rangFavori != null && rangFavori <= 3) {
        buf.writeln('🟡 Favori IA $favoriNom → ${rangFavori}ème (placé)');
      } else if (rangFavori != null && rangFavori <= 5) {
        buf.writeln('🟠 Favori IA $favoriNom → ${rangFavori}ème (hors podium)');
      } else {
        buf.writeln('❌ Favori IA $favoriNom → absent du top 5');
      }
    } else {
      buf.writeln('⚪ Favori IA indéterminé');
    }

    // Ligne 2 : précision du groupe top3 / top5
    buf.writeln('Top 3 IA dans arrivée : $nbTop3/3 — Top 5 : $nbTop5/5');

    // Ligne 3 : lecture du score global
    final labelScore = scorePerf >= 75 ? '🏆 Excellente' :
                       scorePerf >= 55 ? '👍 Bonne' :
                       scorePerf >= 35 ? '🟡 Moyenne' :
                       '❌ Faible';
    buf.writeln('Performance : $labelScore (${scorePerf.toStringAsFixed(0)}/100)');

    // Ligne 4 : type de pari et verdict
    if (typePari != null && typePari.isNotEmpty) {
      final gagne = rangFavori != null && rangFavori <= 3;
      final verdict = gagne ? 'potentiellement gagnant' : 'non gagnant';
      buf.write('Pari conseillé : $typePari → $verdict');
    }

    return buf.toString().trim();
  }

  // ★ v9.93 POINT 4 : Calcul du facteur journée atypique ──────────────────
  //
  // Retourne 1.0 (gradient normal) ou 0.3 (gradient réduit si journée aberrante).
  //
  // GARDE-FOUS stricts pour éviter le biais de rationalisation :
  //   • Seuil très élevé : > 85% d'échecs (favori IA non classé 1-3)
  //   • Minimum 8 courses analysées avec résultat
  //   • Maximum 2 journées atypiques par mois calendaire
  //   • Les résultats bruts ne sont JAMAIS modifiés
  //   • Log obligatoire dans le journal IA
  double _calculerFacteurJourneeAtypique(
      List<IaPronostic> pronosticsJour, DateTime now) {
    final resolus = pronosticsJour
        .where((p) => p.resultatsReels && p.rangFavoriIaDansArrivee != null)
        .toList();

    // Garde-fou 1 : minimum 8 courses résolues
    if (resolus.length < 8) return 1.0;

    // Calculer le taux d'échec (favori IA non dans le top 3)
    final nbEchecs = resolus.where((p) =>
        p.rangFavoriIaDansArrivee == null ||
        p.rangFavoriIaDansArrivee! > 3).length;
    final tauxEchec = nbEchecs / resolus.length;

    // Garde-fou 2 : seuil très élevé (85%)
    if (tauxEchec < 0.85) return 1.0;

    // Garde-fou 3 : max 2 journées atypiques par mois
    final moisKey = '${now.year}-${now.month}';
    final nbAtypiquesMonth = _poids.dernierGradient['atypiques_$moisKey']?.toInt() ?? 0;
    if (nbAtypiquesMonth >= 2) {
      if (kDebugMode) debugPrint(
          '[Atypique] Quota mois atteint ($nbAtypiquesMonth/2) — gradient normal');
      return 1.0;
    }

    // Journée atypique confirmée — log + incrément compteur
    final pct = (tauxEchec * 100).toStringAsFixed(0);
    if (kDebugMode) debugPrint(
        '[Atypique] ⚠️ Journée aberrante détectée : $pct% d\'échecs '
        'sur ${resolus.length} courses — gradient ×0.3');

    // Enregistrer dans le compteur mensuel via dernierGradient (réutilisation de la map)
    _poids.dernierGradient['atypiques_$moisKey'] = (nbAtypiquesMonth + 1).toDouble();

    // Journaliser l'événement dans le journal IA
    _journal.add(JournalEntree(
      date:               now,
      nomCourse:          'Journée ${now.day}/${now.month}/${now.year}',
      discipline:         'Toutes',
      nbCoursesAnalysees: resolus.length,
      diagnostic:         '⚠️ Journée atypique détectée : $pct% d\'échecs '
                          'sur ${resolus.length} courses (seuil 85%). '
                          'Gradient réduit à ×0.3 — résultats conservés intacts.',
      avant:              Map<String, double>.from(_poids.dernierGradient),
      apres:              Map<String, double>.from(_poids.dernierGradient),
      scorePerf:          (1.0 - tauxEchec) * 100,
      methode:            'journee_atypique',
    ));

    return 0.3; // Gradient fortement réduit mais pas annulé
  }

  Future<void> _apprendreParGradient({double facteurAtypique = 1.0}) async {
    final avecResultat = pronosticsAvecResultat;
    final avecScores = avecResultat
        .where((p) => p.scoresCriteres.isNotEmpty)
        .toList();

    // ★ v9.1 : Seuil minimum de courses pour éviter le surapprentissage sur bruit
    // < 10 courses → poids figés, apprentissage par règles de base seulement
    // 10-30 courses → taux d'apprentissage réduit (×0.3)
    // > 30 courses  → taux d'apprentissage normal
    final nbAvecResultat = avecResultat.length;

    if (avecScores.length < 3 || nbAvecResultat < 10) {
      if (kDebugMode) debugPrint(
        '[IA Gradient] Poids figés — données insuffisantes ($nbAvecResultat/10 courses). '
        'Apprentissage par règles de base uniquement.');
      await _apprendreReglesBase(avecResultat.take(50).toList());
      return;
    }

    // ★ v9.92 POINT 1 : Fenêtre glissante 45 jours max
    // Les pronostics > 45j ont un poids dégressif puis nul — les courses
    // récentes sont bien plus représentatives des conditions actuelles.
    final maintenant = DateTime.now();
    final avecScoresRecents = avecScores.where((p) {
      final age = maintenant.difference(p.datePronostic).inDays;
      return age <= 45;
    }).toList();
    // Si pas assez dans 45j, élargir jusqu'à 90j avec poids réduit
    final fenetreBrute = avecScoresRecents.isNotEmpty
        ? avecScoresRecents
        : avecScores.where((p) =>
            maintenant.difference(p.datePronostic).inDays <= 90).toList();
    final fenetre = fenetreBrute.take(50).toList();
    final nb = fenetre.length;

    // ★ v9.1 : Facteur de stabilisation selon le nombre de courses disponibles
    // < 10  → bloqué ci-dessus
    // 10-30 → lr × 0.3 (apprentissage prudent, signal insuffisant)
    // > 30  → lr × 1.0 (apprentissage normal)
    final double stabilisationFactor;
    if (nbAvecResultat < 30) {
      stabilisationFactor = 0.3;
      if (kDebugMode) debugPrint(
        '[IA Gradient] Mode prudent ($nbAvecResultat courses) — lr × 0.3');
    } else {
      stabilisationFactor = 1.0;
    }

    final Map<String, List<double>> scoresBons    = {};
    final Map<String, List<double>> scoresMauvais = {};

    const criteres = ['forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline', 'distSpec', 'jockey', 'repos', 'hippo', 'entraineur', 'elo', 'terrain', 'divergence', 'poidsRel', 'progression', 'mouvCote', 'placeDepart']; // ★ v9.93 : 19 critères complets
    for (final c in criteres) {
      scoresBons[c]    = [];
      scoresMauvais[c] = [];
    }

    // ── Pondération par récence : les courses récentes comptent plus ──────────
    // Course la plus récente (index 0) → poids max, la plus ancienne → poids min
    // Formule : poids(i) = exp(-decay * i/nb) pour un decroissement exponentiel doux
    const decay = 1.2; // plus élevé = oubli plus rapide des vieilles courses

    for (int i = 0; i < fenetre.length; i++) {
      final pronostic = fenetre[i];
      final arrivee = pronostic.arriveeReelle ?? [];
      if (arrivee.isEmpty) continue;

      // Poids de récence : 1.0 pour la plus récente, ≈0.30 pour la 30ème
      final recenceWeight = math.exp(-decay * i / math.max(1, nb));

      // ★ v9.93 POINT 1 : Pondération par taille du champ
      // Une course à 16 partants est plus discriminante qu'une à 5.
      // Le pronostic IA y est plus méritoire (ou l'erreur plus significative).
      // Formule : log(nbPartants) / log(10)
      //   5 partants  → 0.70 (moins de signal, apprentissage réduit)
      //   8 partants  → 0.90
      //  10 partants  → 1.00 (référence neutre)
      //  16 partants  → 1.20 (grand champ, signal fort)
      //  20 partants  → 1.30
      // Clampé à [0.50, 1.40] pour éviter les extrêmes
      final nbP = pronostic.scoresIA.length; // nb partants analysés
      final champFactor = nbP >= 2
          ? (math.log(nbP) / math.log(10)).clamp(0.50, 1.40)
          : 1.0;
      final poids = recenceWeight * champFactor;

      // ★ v9.92 POINT 2 : Signal gradué selon rang réel du favori IA
      // Avant : binaire (bon/mauvais). Maintenant : continu selon rang.
      // Favori IA 1er  → signal fort positif (poids 1.0 dans bons)
      // Favori IA 2ème → signal faible positif (poids 0.6 bons, 0.4 mauvais)
      // Favori IA 3ème → signal neutre (poids 0.5/0.5)
      // Favori IA 4-5  → signal faible négatif (poids 0.3 bons, 0.7 mauvais)
      // Favori IA 6+   → signal fort négatif (poids 0.0 bons, 1.0 mauvais)
      final arriveeStr = arrivee.map((n) => n.toString()).toList();

      pronostic.scoresCriteres.forEach((numero, sc) {
        final rangReel = arriveeStr.indexOf(numero) + 1; // 0 si absent → non classé
        double poidsBon, poidsMauvais;

        if (rangReel == 1) {
          poidsBon = 1.0; poidsMauvais = 0.0;  // Gagnant : signal fort positif
        } else if (rangReel == 2) {
          poidsBon = 0.6; poidsMauvais = 0.4;  // 2ème : presque bon
        } else if (rangReel == 3) {
          poidsBon = 0.5; poidsMauvais = 0.5;  // 3ème : neutre
        } else if (rangReel <= 5 && rangReel > 0) {
          poidsBon = 0.3; poidsMauvais = 0.7;  // 4-5ème : faiblement mauvais
        } else {
          poidsBon = 0.0; poidsMauvais = 1.0;  // 6ème+ ou non classé : mauvais
        }

        for (final c in criteres) {
          final val = sc.valeurPourCritere(c) * poids; // ★ v9.93 : poids = récence × champ
          if (poidsBon > 0)     scoresBons[c]!.add(val * poidsBon);
          if (poidsMauvais > 0) scoresMauvais[c]!.add(val * poidsMauvais);
        }
      });
    }

    final totalBons = scoresBons['forme']?.length ?? 0;
    final totalMauvais = scoresMauvais['forme']?.length ?? 0;

    if (totalBons < 5 || totalMauvais < 5) {
      await _apprendreReglesBase(fenetre);
      return;
    }

    // Moyenne des valeurs pondérées
    double moyPond(List<double> list) {
      if (list.isEmpty) return 50.0;
      return (list.reduce((a, b) => a + b) / list.length).clamp(0.0, 100.0);
    }

    final Map<String, double> discriminations = {};
    for (final c in criteres) {
      final moyBon    = moyPond(scoresBons[c]!);
      final moyMauvais = moyPond(scoresMauvais[c]!);
      discriminations[c] = (moyBon - moyMauvais) / 100.0;
    }

    final poidsAvant = {
      'forme': _poids.forme, 'gains': _poids.gains, 'record': _poids.record,
      'cote': _poids.cote, 'constance': _poids.constance,
      'victoires': _poids.victoires, 'discipline': _poids.discipline,
      'distSpec': _poids.distSpec, 'jockey': _poids.jockey, 'repos': _poids.repos,
      'hippo': _poids.hippo,
      'entraineur': _poids.entraineur, // ★ v8.0
      'elo': _poids.elo,               // ★ v8.0
      'terrain':    _poids.terrain,    // ★ v9.0
      'divergence': _poids.divergence, // ★ v9.0
      'poidsRel':   _poids.poidsRel,   // ★ v9.0
      'progression':_poids.progression,// ★ v9.0
      'mouvCote':   _poids.mouvCote,   // ★ v9.93
      'placeDepart':_poids.placeDepart,// ★ v9.93
    };

    // Taux d'apprentissage adaptatif + momentum
    // Le momentum amortit les oscillations en mémorisant la tendance précédente
    // ★ v9.1 : multiplié par stabilisationFactor (0.3 si < 30 courses, 1.0 sinon)
    // ★ v9.93 : multiplié par facteurAtypique (0.3 si journée aberrante, 1.0 sinon)
    final lrBase = 0.08;
    final lrFactor = math.min(1.0, nb / 20.0);
    final lr = lrBase * lrFactor * stabilisationFactor * facteurAtypique;
    const momentumFactor = 0.3; // 30% de la mise à jour précédente

    // Récupérer le momentum (gradient précédent) stocké dans les poids
    final momentum = _poids.dernierGradient;

    // ★ v9.93 POINT 3 : Gel gradient sur critères corrélés
    // Si deux critères corrèlent r > 0.85 avec >= 50 courses dans la fenêtre,
    // le critère avec le POIDS LE PLUS FAIBLE est temporairement gelé.
    // Il ne reçoit pas de mise à jour gradient — seul l'autre apprend.
    // Le gel se lève automatiquement quand r passe sous 0.70.
    // GARDE-FOU : seulement si fenêtre >= 50 courses (signal fiable).
    final criteresGeles = <String>{};
    if (nb >= 50 && _poids.correlations.isNotEmpty) {
      for (final entry in _poids.correlations.entries) {
        final r = entry.value;
        if (r < 0.85) continue; // Seuil strict — corrélation très forte seulement
        final parts = entry.key.split('|');
        if (parts.length < 2) continue;
        final c1 = parts[0], c2 = parts[1];
        // Geler le critère avec le poids le plus faible (moins d'information unique)
        final p1 = _poids.getPoids(c1);
        final p2 = _poids.getPoids(c2);
        final aGeler = p1 <= p2 ? c1 : c2;
        criteresGeles.add(aGeler);
        if (kDebugMode) debugPrint(
            '[Gel gradient] $aGeler gelé (corrélé avec ${p1 <= p2 ? c2 : c1} à r=${r.toStringAsFixed(2)})');
      }
    }

    for (final c in criteres) {
      // ★ v9.93 : critère gelé → pas de mise à jour gradient
      if (criteresGeles.contains(c)) {
        momentum[c] = 0.0; // reset momentum pour éviter accumulation
        continue;
      }
      final grad = lr * discriminations[c]!;
      final gradAvecMomentum = grad + momentumFactor * (momentum[c] ?? 0.0);
      momentum[c] = gradAvecMomentum; // mémoriser pour la prochaine fois
      // Mise à jour des 19 critères adaptatifs :
      // — 7 critères de base : forme, gains, record, cote, constance, victoires, discipline
      // — 3 critères enrichis (v4.2) : distSpec (×0.5 doux), jockey (×0.5), repos (×0.3 très doux)
      // ★ v9.93 : mouvCote (×0.5) et placeDepart (×0.3) désormais adaptatifs
      switch (c) {
        case 'forme':       _poids.forme       += gradAvecMomentum; break;
        case 'gains':       _poids.gains       += gradAvecMomentum; break;
        case 'record':      _poids.record      += gradAvecMomentum; break;
        case 'cote':        _poids.cote        += gradAvecMomentum; break;
        case 'constance':   _poids.constance   += gradAvecMomentum; break;
        case 'victoires':   _poids.victoires   += gradAvecMomentum; break;
        case 'discipline':  _poids.discipline  += gradAvecMomentum; break;
        // ★ v4.2 : Critères enrichis désormais ADAPTATIFS (correction asymétrie gradient)
        case 'distSpec':    _poids.distSpec    += gradAvecMomentum * 0.5; break; // facteur 0.5 = ajustement doux
        case 'jockey':      _poids.jockey      += gradAvecMomentum * 0.5; break;
        case 'repos':       _poids.repos       += gradAvecMomentum * 0.3; break; // poids mineur, ajustement très doux
        case 'hippo':       _poids.hippo       += gradAvecMomentum * 0.4; break;
        // ★ v8.0 Lot 4 : nouveaux critères adaptatifs
        case 'entraineur':  _poids.entraineur  += gradAvecMomentum * 0.4; break; // entraîneur, ajustement modéré
        case 'elo':         _poids.elo         += gradAvecMomentum * 0.5; break; // ELO, ajustement normal
        // ★ v9.0 : 4 nouveaux critères
        case 'terrain':     _poids.terrain     += gradAvecMomentum * 0.5; break; // terrain, ajustement normal
        case 'divergence':  _poids.divergence  += gradAvecMomentum * 0.4; break; // coup préparé, prudent
        case 'poidsRel':    _poids.poidsRel    += gradAvecMomentum * 0.3; break; // poids, ajustement doux
        case 'progression': _poids.progression += gradAvecMomentum * 0.4; break; // progression, modéré
        // ★ v9.93 : 2 derniers critères enfin adaptatifs
        case 'mouvCote':    _poids.mouvCote    += gradAvecMomentum * 0.5; break; // signal argent informé, ajustement normal
        case 'placeDepart': _poids.placeDepart += gradAvecMomentum * 0.3; break; // place corde, ajustement doux
      }
    }
    _poids.dernierGradient = momentum;

    _poids.clamp();
    _poids.nbMisesAJour++;

    final scoreMoyFenetre = fenetre
        .map((p) => p.scorePerformance ?? 0)
        .reduce((a, b) => a + b) / fenetre.length;

    // ★ v9.1 : Inclure l'info de stabilisation dans le diagnostic
    final phaseStabilisation = nbAvecResultat < 30
        ? ' [Mode prudent : $nbAvecResultat courses, lr × 0.3]'
        : ' [Mode normal : $nbAvecResultat courses]';
    final diagLines = _genererDiagnosticGlobal(nb, totalBons, totalMauvais, discriminations, poidsAvant,
        suffixe: phaseStabilisation);

    final poidsApres = {
      'forme': _poids.forme, 'gains': _poids.gains, 'record': _poids.record,
      'cote': _poids.cote, 'constance': _poids.constance,
      'victoires': _poids.victoires, 'discipline': _poids.discipline,
      'distSpec': _poids.distSpec, 'jockey': _poids.jockey, 'repos': _poids.repos,
      'hippo': _poids.hippo,
      'entraineur': _poids.entraineur, // ★ v8.0
      'elo': _poids.elo,               // ★ v8.0
      'terrain':    _poids.terrain,    // ★ v9.0
      'divergence': _poids.divergence, // ★ v9.0
      'poidsRel':   _poids.poidsRel,   // ★ v9.0
      'progression':_poids.progression,// ★ v9.0
      'mouvCote':   _poids.mouvCote,   // ★ v9.93
      'placeDepart':_poids.placeDepart,// ★ v9.93
    };

    _journal.insert(0, JournalEntree(
      date: DateTime.now(),
      nomCourse: fenetre.first.nomCourse,
      discipline: '',
      nbCoursesAnalysees: nb,
      diagnostic: diagLines.join('\n'),
      avant: poidsAvant,
      apres: poidsApres,
      scorePerf: scoreMoyFenetre,
      methode: 'gradient',
    ));
    if (_journal.length > _maxJournal) _journal.removeLast();

    await _save();

    if (kDebugMode) {
      debugPrint('IA Gradient v3 Global: #${_poids.nbMisesAJour}\n${_poids.resume}');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  MOTEUR D'APPRENTISSAGE PAR DISCIPLINE (v3 - NOUVEAU)
  //
  //  Même principe que le gradient global, mais on apprend des poids
  //  spécifiques à chaque discipline (Trot Attelé, Plat, Obstacle, etc.)
  //
  //  Minimum requis : 3 courses de la même discipline avec scores de critères
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _apprendreParDiscipline(String disciplineCible,
      {double facteurAtypique = 1.0}) async {
    final discNorm = IaPoidsAdaptatifs.normaliseDiscipline(disciplineCible);

    // Filtrer les pronostics de cette discipline
    final parDisc = pronosticsAvecResultat
        .where((p) => IaPoidsAdaptatifs.normaliseDiscipline(p.discipline) == discNorm)
        .where((p) => p.scoresCriteres.isNotEmpty)
        .take(20)
        .toList();

    // ★ v9.1 : Seuil minimum par discipline
    // < 5  courses discipline → pas d'apprentissage du tout
    // 5-15 courses            → lr réduit (×0.3)
    // > 15 courses            → lr normal par phase
    final nbDisc = parDisc.length;

    if (nbDisc < 5) {
      if (kDebugMode) debugPrint(
        '[IA Discipline] Poids figés $discNorm — données insuffisantes ($nbDisc/5 courses)');
      return;
    }

    // Facteur de stabilisation discipline (analogue au gradient global)
    final double stabilisationFactorDisc = nbDisc < 15 ? 0.3 : 1.0;
    if (nbDisc < 15 && kDebugMode) debugPrint(
      '[IA Discipline] Mode prudent $discNorm ($nbDisc courses) — lr × 0.3');

    // ★ v5.0 : 10 critères complets pour l'apprentissage par discipline
    const criteres = ['forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline', 'distSpec', 'jockey', 'repos', 'hippo', 'entraineur', 'elo', 'terrain', 'divergence', 'poidsRel', 'progression', 'mouvCote', 'placeDepart']; // ★ v9.93 : 19 critères complets
    final Map<String, List<double>> scoresBons    = {};
    final Map<String, List<double>> scoresMauvais = {};

    for (final c in criteres) {
      scoresBons[c]    = [];
      scoresMauvais[c] = [];
    }

    for (int i = 0; i < parDisc.length; i++) {
      final pronostic = parDisc[i];
      final arrivee = pronostic.arriveeReelle ?? [];
      if (arrivee.isEmpty) continue;
      // Pondération par récence pour la discipline aussi
      final rw = math.exp(-1.2 * i / math.max(1, parDisc.length));
      final top3Reel = arrivee.take(3).map((n) => n.toString()).toSet();
      final top5Reel = arrivee.take(5).map((n) => n.toString()).toSet();

      pronostic.scoresCriteres.forEach((numero, sc) {
        final estTop3 = top3Reel.contains(numero);
        final estTop5 = top5Reel.contains(numero);
        if (estTop3) {
          for (final c in criteres) { scoresBons[c]!.add(sc.valeurPourCritere(c) * rw); }
        } else if (estTop5) {
          for (final c in criteres) {
            scoresBons[c]!.add(sc.valeurPourCritere(c) * rw * 0.5);
            scoresMauvais[c]!.add(sc.valeurPourCritere(c) * rw * 0.5);
          }
        } else {
          for (final c in criteres) { scoresMauvais[c]!.add(sc.valeurPourCritere(c) * rw); }
        }
      });
    }

    final totalBons = scoresBons['forme']?.length ?? 0;
    final totalMauvais = scoresMauvais['forme']?.length ?? 0;

    if (totalBons < 3 || totalMauvais < 3) return;

    double moy(List<double> list) =>
        list.isEmpty ? 50.0 : list.reduce((a, b) => a + b) / list.length;

    // Récupérer ou créer les poids pour cette discipline — 19 critères complets A→S
    // ★ v9.95 audit : init complétée à 19 critères (était 11, manquaient entraineur→placeDepart)
    final poidsDisc = _poids.poidsParDiscipline[discNorm] ?? {
      'forme':       _poids.forme,
      'gains':       _poids.gains,
      'record':      _poids.record,
      'cote':        _poids.cote,
      'constance':   _poids.constance,
      'victoires':   _poids.victoires,
      'discipline':  _poids.discipline,
      'distSpec':    _poids.distSpec,
      'jockey':      _poids.jockey,
      'repos':       _poids.repos,
      'hippo':       _poids.hippo,
      'entraineur':  _poids.entraineur, // ★ v8.0
      'elo':         _poids.elo,        // ★ v8.0
      'terrain':     _poids.terrain,    // ★ v9.0
      'divergence':  _poids.divergence, // ★ v9.0
      'poidsRel':    _poids.poidsRel,   // ★ v9.0
      'progression': _poids.progression,// ★ v9.0
      'mouvCote':    _poids.mouvCote,   // ★ v9.92
      'placeDepart': _poids.placeDepart,// ★ v9.93
    };

    final nb = nbDisc;

    // ★ v6.0 : lr adaptatif par discipline selon son historique propre
    // Phase 1 (3-7 courses)  : lr élevé → l'IA explore rapidement les spécificités
    // Phase 2 (8-15 courses) : lr moyen → ajustements progressifs
    // Phase 3 (16-30 courses): lr réduit → convergence fine, évite les oscillations
    // Phase 4 (>30 courses)  : lr minimal → micro-ajustements de précision
    final double lrDisc;
    if (nb < 8) {
      lrDisc = 0.09; // Phase 1 : exploration rapide
    } else if (nb < 16) {
      lrDisc = 0.07; // Phase 2 : ajustement progressif
    } else if (nb < 30) {
      lrDisc = 0.045; // Phase 3 : convergence fine
    } else {
      lrDisc = 0.025; // Phase 4 : micro-ajustements
    }

    // Facteur de confiance : plus de données = plus de confiance dans le signal
    // ★ v9.1 : multiplié par stabilisationFactorDisc
    // ★ v9.93 : multiplié par facteurAtypique (journée aberrante = ×0.3)
    final confianceFactor = math.min(1.0, nb / 12.0);
    final lr = lrDisc * confianceFactor * stabilisationFactorDisc * facteurAtypique;

    final poidsAvant = Map<String, double>.from(poidsDisc);

    for (final c in criteres) {
      final discrim = (moy(scoresBons[c]!) - moy(scoresMauvais[c]!)) / 100.0;
      // Facteur d'ajustement doux pour les critères enrichis (évite les oscillations)
      // ★ v9.93 : mouvCote (×0.5) et placeDepart (×0.3) désormais adaptatifs par discipline
      final facteur = (c == 'distSpec' || c == 'jockey' || c == 'elo' || c == 'terrain' || c == 'mouvCote') ? 0.5
                    : (c == 'repos' || c == 'poidsRel' || c == 'placeDepart') ? 0.3
                    : (c == 'hippo' || c == 'entraineur' || c == 'divergence' || c == 'progression') ? 0.4
                    : 1.0;
      poidsDisc[c] = (poidsDisc[c] ?? IaPoidsAdaptatifs.defauts[c] ?? 0.1) + lr * discrim * facteur;
    }

    IaPoidsAdaptatifs.clampDiscipline(poidsDisc);
    _poids.poidsParDiscipline[discNorm] = poidsDisc;

    // Générer diagnostic discipline
    final nomDisc = _nomLisibleDiscipline(discNorm);
    final critPrincipal = criteres.reduce((a, b) =>
        (poidsDisc[a] ?? 0) > (poidsDisc[b] ?? 0) ? a : b);
    // ★ v6.0 : phase d'apprentissage affichée dans le diagnostic
    final phaseDisc = nb < 8 ? '1-Exploration' : nb < 16 ? '2-Ajustement' : nb < 30 ? '3-Convergence' : '4-Précision';
    final diagDisc = [
      '[$nomDisc] Apprentissage sur ${parDisc.length} courses — Phase $phaseDisc (lr=${(lr * 100).toStringAsFixed(1)}%)',
      'Critère dominant : ${_labelCritere(critPrincipal)} (${((poidsDisc[critPrincipal] ?? 0) * 100).toStringAsFixed(0)}%)',
      ...criteres.where((c) {
        final avant = poidsAvant[c] ?? 0;
        final apres = poidsDisc[c] ?? 0;
        return (apres - avant).abs() > 0.005;
      }).map((c) {
        final avant = poidsAvant[c] ?? 0;
        final apres = poidsDisc[c] ?? 0;
        final diff = apres - avant;
        final sign = diff > 0 ? '+' : '';
        return '  ${_labelCritere(c)} : $sign${(diff * 100).toStringAsFixed(1)}%';
      }),
    ];

    _journal.insert(0, JournalEntree(
      date: DateTime.now(),
      nomCourse: parDisc.first.nomCourse,
      discipline: nomDisc,
      nbCoursesAnalysees: nb,
      diagnostic: diagDisc.join('\n'),
      avant: poidsAvant,
      apres: Map<String, double>.from(poidsDisc),
      scorePerf: parDisc.map((p) => p.scorePerformance ?? 0).reduce((a, b) => a + b) / nb,
      methode: 'discipline_gradient',
    ));
    if (_journal.length > _maxJournal) _journal.removeLast();

    await _save();
    if (kDebugMode) debugPrint('IA Discipline v3 [$nomDisc]: Mise à jour sur $nb courses');
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  CALIBRATION DE CONFIANCE (v3 - NOUVEAU)
  //
  //  Mesure si les prédictions de confiance de l'IA sont fiables :
  //  → Quand l'IA dit "haute confiance" (forte variance des scores),
  //    est-ce que ses prédictions sont réellement meilleures ?
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _mettreAJourCalibration() async {
    final avecResultat = pronosticsAvecResultat;
    if (avecResultat.length < 5) return;

    final avecVariance = avecResultat
        .where((p) => p.varianceScores != null && p.scorePerformance != null)
        .toList();

    if (avecVariance.length < 5) return;

    final medianVariance = _median(avecVariance.map((p) => p.varianceScores!).toList());
    final hautConfiance  = avecVariance.where((p) => p.varianceScores! >  medianVariance).toList();
    final basseConfiance = avecVariance.where((p) => p.varianceScores! <= medianVariance).toList();

    if (hautConfiance.isEmpty || basseConfiance.isEmpty) return;

    final scoreMoyHaut = hautConfiance.map((p) => p.scorePerformance!).reduce((a, b) => a + b) / hautConfiance.length;
    final scoreMoyBas  = basseConfiance.map((p) => p.scorePerformance!).reduce((a, b) => a + b) / basseConfiance.length;

    final delta    = scoreMoyHaut - scoreMoyBas;
    final newCalib = (50.0 + delta).clamp(10.0, 90.0);
    _poids.calibrationScore = newCalib;
    IaCalibrationRegistry.update(newCalib);

    // ★ v9.92 POINT 8 : Détection de corrélation entre critères
    // Si deux critères corrèlent fortement (r > 0.7), ils mesurent la même chose.
    // On stocke les corrélations les plus élevées dans les poids pour les afficher
    // dans l'onglet IA Stats (avertissement visuel, pas de modification des poids).
    _detecterCorrelationsCriteres(avecResultat);

    await _save();
    if (kDebugMode) debugPrint('IA Calibration: score=$newCalib (Haut=$scoreMoyHaut, Bas=$scoreMoyBas)');
  }

  // ★ v9.92 POINT 8 : Calcule les corrélations de Pearson entre critères
  // Stocke dans _poids.correlations les paires dont r > 0.65
  void _detecterCorrelationsCriteres(List<IaPronostic> pronostics) {
    final avecScores = pronostics
        .where((p) => p.scoresCriteres.isNotEmpty)
        .take(80) // limiter le calcul
        .toList();
    if (avecScores.length < 20) return;

    const criteres = ['forme', 'gains', 'record', 'cote', 'constance',
        'victoires', 'discipline', 'distSpec', 'jockey', 'repos', 'hippo',
        'entraineur', 'elo', 'terrain', 'divergence', 'poidsRel', 'progression',
        'mouvCote', 'placeDepart']; // ★ v9.93 : 19 critères complets

    // Construire les vecteurs de scores par critère (aplatir tous les partants)
    final Map<String, List<double>> vecteurs = {for (final c in criteres) c: []};

    for (final p in avecScores) {
      p.scoresCriteres.forEach((_, sc) {
        for (final c in criteres) {
          vecteurs[c]!.add(sc.valeurPourCritere(c));
        }
      });
    }

    // Pearson entre chaque paire
    double pearson(List<double> x, List<double> y) {
      final n = math.min(x.length, y.length);
      if (n < 10) return 0.0;
      final mx = x.take(n).reduce((a, b) => a + b) / n;
      final my = y.take(n).reduce((a, b) => a + b) / n;
      double num = 0, dx = 0, dy = 0;
      for (int i = 0; i < n; i++) {
        final ex = x[i] - mx, ey = y[i] - my;
        num += ex * ey;
        dx  += ex * ex;
        dy  += ey * ey;
      }
      final denom = math.sqrt(dx * dy);
      return denom > 0 ? num / denom : 0.0;
    }

    final Map<String, double> correlationsHautes = {};
    for (int i = 0; i < criteres.length; i++) {
      for (int j = i + 1; j < criteres.length; j++) {
        final ci = criteres[i], cj = criteres[j];
        final r  = pearson(vecteurs[ci]!, vecteurs[cj]!).abs();
        if (r >= 0.65) {
          correlationsHautes['$ci|$cj'] = double.parse(r.toStringAsFixed(3));
        }
      }
    }

    // Stocker dans les poids pour affichage dans IA Stats
    _poids.correlations = correlationsHautes;
    if (kDebugMode && correlationsHautes.isNotEmpty) {
      debugPrint('[IA Corrélation] ${correlationsHautes.length} paires corrélées détectées : $correlationsHautes');
    }
  }

  // ── Apprentissage par règles (fallback sans scores de critères) ───────────

  Future<void> _apprendreReglesBase(List<IaPronostic> fenetre) async {
    final nb = fenetre.length;
    if (nb < 3) return;

    int favoriGagne = 0, favoriTop3 = 0, mauvaisClass = 0;
    double scoreTotal = 0;

    for (final p in fenetre) {
      final rang = p.rangFavoriIaDansArrivee;
      if (rang == null) continue;
      if (rang == 1) favoriGagne++;
      if (rang <= 3) favoriTop3++;
      if (rang > 5) mauvaisClass++;
      scoreTotal += p.scorePerformance ?? 0;
    }

    final scoreMoy = scoreTotal / nb;
    final tauxGagne   = favoriGagne / nb;
    final tauxTop3    = favoriTop3 / nb;
    final tauxMauvais = mauvaisClass / nb;
    final bonTop3     = fenetre.where((p) => (p.nbTop3DansArriveeReelle ?? 0) >= 2).length;
    final tauxBonTop3 = bonTop3 / nb;

    const lr = 0.06;
    // ★ v82 : inclure les 10 critères dans poidsAvant (audit : 7 critères manquaient distSpec/jockey/repos)
    // ★ v9.0 audit : ajouter entraineur, elo, terrain, divergence, poidsRel, progression
    // ★ v9.95 audit : ajouter mouvCote (R) et placeDepart (S) — 19 critères complets
    final poidsAvant = {
      'forme': _poids.forme, 'gains': _poids.gains, 'record': _poids.record,
      'cote': _poids.cote, 'constance': _poids.constance,
      'victoires': _poids.victoires, 'discipline': _poids.discipline,
      'distSpec': _poids.distSpec, 'jockey': _poids.jockey, 'repos': _poids.repos,
      'hippo':       _poids.hippo,
      'entraineur':  _poids.entraineur, // ★ v8.0
      'elo':         _poids.elo,        // ★ v8.0
      'terrain':     _poids.terrain,    // ★ v9.0
      'divergence':  _poids.divergence, // ★ v9.0
      'poidsRel':    _poids.poidsRel,   // ★ v9.0
      'progression': _poids.progression,// ★ v9.0
      'mouvCote':    _poids.mouvCote,   // ★ v9.92
      'placeDepart': _poids.placeDepart,// ★ v9.93
    };

    if (tauxGagne > 0.38) {
      // Le favori gagne souvent → forme + cote sont fiables, jockey peut aider
      _poids.forme  += lr * 0.4;
      _poids.cote   += lr * 0.3;
      _poids.jockey += lr * 0.15; // ★ v82 : bonus jockey (souvent corrélé au gain)
    } else if (tauxMauvais > 0.35) {
      // Trop de mauvais classements → forme moins fiable, cote + distance spéciale plus pertinente
      _poids.forme    -= lr * 0.3;
      _poids.cote     += lr * 0.4;
      _poids.gains    += lr * 0.2;
      _poids.distSpec += lr * 0.15; // ★ v82 : la spécialité distance aide à filtrer
    }

    if (tauxBonTop3 > 0.55) {
      // Bonne sélection top3 → constance + record + repos fiables
      _poids.constance += lr * 0.25;
      _poids.record    += lr * 0.15;
      _poids.repos     += lr * 0.05; // ★ v82 : repos corrélé à la régularité
    } else if (tauxBonTop3 < 0.20) {
      // Top3 souvent raté → ajuster vers cote + spécialité distance
      _poids.forme    -= lr * 0.25;
      _poids.cote     += lr * 0.20;
      _poids.record   += lr * 0.15;
      _poids.distSpec += lr * 0.10; // ★ v82 : distance spéciale peut manquer
    }

    if (tauxTop3 > 0.70) {
      _poids.forme += lr * 0.1;
    }

    _poids.clamp();
    _poids.nbMisesAJour++;

    // ★ v82 : poidsApres complet sur 10 critères
    // ★ v9.0 audit : ajouter entraineur, elo, terrain, divergence, poidsRel, progression
    // ★ v9.95 audit : ajouter mouvCote (R) et placeDepart (S) — 19 critères complets
    final poidsApres = {
      'forme': _poids.forme, 'gains': _poids.gains, 'record': _poids.record,
      'cote': _poids.cote, 'constance': _poids.constance,
      'victoires': _poids.victoires, 'discipline': _poids.discipline,
      'distSpec': _poids.distSpec, 'jockey': _poids.jockey, 'repos': _poids.repos,
      'hippo':       _poids.hippo,
      'entraineur':  _poids.entraineur, // ★ v8.0
      'elo':         _poids.elo,        // ★ v8.0
      'terrain':     _poids.terrain,    // ★ v9.0
      'divergence':  _poids.divergence, // ★ v9.0
      'poidsRel':    _poids.poidsRel,   // ★ v9.0
      'progression': _poids.progression,// ★ v9.0
      'mouvCote':    _poids.mouvCote,   // ★ v9.92
      'placeDepart': _poids.placeDepart,// ★ v9.93
    };

    // Calcul du taux de réussite par type pour le diagnostic
    final bonParType = <String, int>{};
    final nbParType  = <String, int>{};
    for (final p in fenetre) {
      if (!p.resultatsReels) continue;
      final t = p.typePariConseille ?? 'Inconnu';
      nbParType[t]  = (nbParType[t]  ?? 0) + 1;
      if (_estBonConseilParType(p, t)) bonParType[t] = (bonParType[t] ?? 0) + 1;
    }
    final resumeTypes = nbParType.entries.map((e) {
      final bon = bonParType[e.key] ?? 0;
      final taux = e.value > 0 ? (bon / e.value * 100).round() : 0;
      return '${e.key}: $bon/${e.value} ($taux%)';
    }).join(', ');

    final diagLines = [
      '⚙️ Mode règles (données de critères insuffisantes)',
      'Favori IA gagnant : ${(tauxGagne*100).toStringAsFixed(0)}% / ${(nb*tauxGagne).round()} fois',
      'Favori IA top 3 : ${(tauxTop3*100).toStringAsFixed(0)}%',
      'Mauvais classement (>5ème) : ${(tauxMauvais*100).toStringAsFixed(0)}%',
      'Top 3 corrects (≥2/3) : ${(tauxBonTop3*100).toStringAsFixed(0)}%',
      if (resumeTypes.isNotEmpty) 'Réussite par type : $resumeTypes',
      _interpreterRegles(tauxGagne, tauxMauvais, tauxBonTop3),
    ];

    _journal.insert(0, JournalEntree(
      date: DateTime.now(),
      nomCourse: fenetre.isNotEmpty ? fenetre.first.nomCourse : '—',
      nbCoursesAnalysees: nb,
      diagnostic: diagLines.join('\n'),
      avant: poidsAvant,
      apres: poidsApres,
      scorePerf: scoreMoy,
      methode: 'regles',
    ));
    if (_journal.length > _maxJournal) _journal.removeLast();

    await _save();
  }

  // ── Statistiques pour l'affichage ──────────────────────────────────────────

  IaStats calculerStats() {
    final avecResultat = pronosticsAvecResultat;
    if (avecResultat.isEmpty) {
      return IaStats(
        totalCourses: _pronostics.length,
        coursesAvecResultat: 0,
        favoriGagnant: 0,
        favoriTop3: 0,
        favoriTop5: 0,
        nbTop3Correct2sur3: 0,
        nbTop5Correct4sur5: 0, // ★ v10.14 : seuil 4/5
        scoreMoyenPerformance: 0,
        parDiscipline: {},
        tauxParDiscipline: {},
        calibrationScore: _poids.calibrationScore,
      );
    }

    int fg = 0, ft3 = 0, ft5 = 0, t3c = 0, t5c = 0;
    double totalScore = 0;
    final parDisc = <String, int>{};
    final gainDisc = <String, int>{};

    for (final p in avecResultat) {
      final rang = p.rangFavoriIaDansArrivee;
      if (rang != null) {
        if (rang == 1) fg++;
        if (rang <= 3) ft3++;
        if (rang <= 5) ft5++;
      }
      if ((p.nbTop3DansArriveeReelle ?? 0) >= 2) t3c++;
      if ((p.nbTop5DansArriveeReelle ?? 0) >= 4) t5c++; // ★ v10.14 : seuil 4/5 (était 3/5)
      totalScore += p.scorePerformance ?? 0;

      final disc = p.discipline.isNotEmpty ? p.discipline : 'Inconnu';
      parDisc[disc] = (parDisc[disc] ?? 0) + 1;
      if (rang != null && rang <= 3) gainDisc[disc] = (gainDisc[disc] ?? 0) + 1;
    }

    final tauxDisc = <String, double>{};
    for (final disc in parDisc.keys) {
      tauxDisc[disc] = (gainDisc[disc] ?? 0) / (parDisc[disc] ?? 1) * 100;
    }

    return IaStats(
      totalCourses: _pronostics.length,
      coursesAvecResultat: avecResultat.length,
      favoriGagnant: fg,
      favoriTop3: ft3,
      favoriTop5: ft5,
      nbTop3Correct2sur3: t3c,
      nbTop5Correct4sur5: t5c, // ★ v10.14 : seuil 4/5
      scoreMoyenPerformance: totalScore / avecResultat.length,
      parDiscipline: parDisc,
      tauxParDiscipline: tauxDisc,
      calibrationScore: _poids.calibrationScore,
    );
  }

  /// Retourne les poids effectifs pour une discipline donnée
  Map<String, double> poidsEffectifsPour(String discipline) {
    return _poids.poidsEffectifsPourDiscipline(discipline);
  }

  /// Retourne les disciplines pour lesquelles l'IA a appris des poids spécifiques
  List<String> get disciplinesApprises =>
      _poids.poidsParDiscipline.keys.toList();

  // ══════════════════════════════════════════════════════════════════════════
  //  ANALYSE JOURNÉE COMPLÈTE — approche directe
  //
  //  LOGIQUE SIMPLE ET FIABLE :
  //  1. Lire les pronostics IA déjà en mémoire (créés par DataRefreshService)
  //  2. Pour chaque pronostic du jour sans résultat → récupérer le résultat
  //     PMU avec EXACTEMENT le même code que alert_service._fetchResultatAuto
  //  3. Calculer le delta pronostic IA vs arrivée réelle
  //  4. Déclencher l'apprentissage par gradient
  //
  //  PAS DE RE-PARSAGE DU PROGRAMME PMU — les pronostics sont déjà là !
  // ══════════════════════════════════════════════════════════════════════════

  Future<AnalyseJourneeResultat> analyseJourneeComplete({
    DateTime? date,
    void Function(int etape, int total, String msg)? onProgress,
    List<Map<String, dynamic>>? predictionsUtilisateur,
  }) async {
    await _load();
    final now = date ?? DateTime.now();

    int etape = 0;
    int nbCoursesAnalysees = 0;
    int nbNouveauxResultats = 0;
    int nbPronosticsAjoutes = 0;
    int nbCoursesEchouees   = 0;
    int nbSansResultat      = 0;
    int nbCoursesFutures    = 0;
    final List<String> coursesAnalysees = [];
    final List<String> erreurs          = [];

    try {
      // ── ÉTAPE 1 : Sélectionner les pronostics à analyser ─────────────────
      onProgress?.call(++etape, 4, '🧠 Lecture des pronostics IA en mémoire…');

      // ★ Amélioration 1 v9.6 : Sélection par date explicite
      // Si 'date' est fourni → analyser CE jour précis
      // Sinon → stratégie intelligente : aujourd'hui, puis J-1, J-2... jusqu'à 7j
      final dateDebut = DateTime(now.year, now.month, now.day, 0, 0);
      final dateFin   = dateDebut.add(const Duration(days: 1));
      // Garde la fenêtre élargie pour rétrocompatibilité
      final dateDebutElargi = dateDebut.subtract(const Duration(hours: 48));

      // LOG étape 1 : état de la mémoire
      final _totalPronostics = _pronostics.length;
      final _avecResultat    = _pronostics.where((p) => p.resultatsReels).length;
      final _sansResultat    = _totalPronostics - _avecResultat;
      onProgress?.call(etape, 4,
          '🧠 Mémoire : $_totalPronostics pronostics '
          '($_avecResultat avec résultat, $_sansResultat sans)');
      await Future.delayed(const Duration(milliseconds: 300));

      // 1er essai : pronostics du JOUR par date (00h00–23h59, 1h tolérance)
      var pronosticsJour = _pronostics.where((p) =>
          p.datePronostic.isAfter(dateDebut.subtract(const Duration(hours: 1))) &&
          p.datePronostic.isBefore(dateFin)).toList();

      onProgress?.call(etape, 4,
          '📅 Aujourd\'hui (${dateDebut.day}/${dateDebut.month}) : '
          '${pronosticsJour.length} pronostics trouvés');
      await Future.delayed(const Duration(milliseconds: 300));

      // ★ 2e essai amélioré : chercher jour par jour sur 7 jours en arrière
      // (au lieu d'une fenêtre 48h aveugle qui mélange 2 jours)
      if (pronosticsJour.isEmpty) {
        for (int joursEnArriere = 1; joursEnArriere <= 7; joursEnArriere++) {
          final jourCible = dateDebut.subtract(Duration(days: joursEnArriere));
          final jourFin   = jourCible.add(const Duration(days: 1));
          final pronosticsJourJ = _pronostics.where((p) =>
              p.datePronostic.isAfter(jourCible.subtract(const Duration(hours: 1))) &&
              p.datePronostic.isBefore(jourFin)).toList();

          if (pronosticsJourJ.isNotEmpty) {
            pronosticsJour = pronosticsJourJ;
            final labelDate =
                '${jourCible.day.toString().padLeft(2, '0')}/'
                '${jourCible.month.toString().padLeft(2, '0')}';
            onProgress?.call(etape, 4,
                '📅 Analyse des courses du $labelDate '
                '(J-$joursEnArriere) : ${pronosticsJour.length} pronostics');
            await Future.delayed(const Duration(milliseconds: 300));
            break;
          }
        }

        // Fenêtre large 48h comme fallback si aucun jour entier trouvé
        if (pronosticsJour.isEmpty) {
          final hierParDate = _pronostics.where((p) =>
              p.datePronostic.isAfter(dateDebutElargi) &&
              p.datePronostic.isBefore(dateFin)).toList();
          if (hierParDate.isNotEmpty) {
            pronosticsJour = hierParDate;
            onProgress?.call(etape, 4,
                '📅 Fenêtre 48h : ${hierParDate.length} pronostics trouvés');
            await Future.delayed(const Duration(milliseconds: 300));
          }
        }

        if (pronosticsJour.isEmpty) {
          // 3e essai : tous les pronostics sans résultat (quelle que soit la date)
          final toutSansResultat =
              _pronostics.where((p) => !p.resultatsReels).toList();

          onProgress?.call(etape, 4,
              '⚠️ Fenêtre 48h vide — fallback : '
              '${toutSansResultat.length} pronostics sans résultat');
          await Future.delayed(const Duration(milliseconds: 300));

          if (toutSansResultat.isNotEmpty) {
            pronosticsJour = toutSansResultat;
          } else if (_pronostics.isEmpty) {
            // Cas normal : installation le soir ou première utilisation
            // → pas une erreur, juste pas encore de données
            final heure = now.hour;
            final messageContextuel = heure >= 18
                ? '📋 Aucun pronostic pour aujourd\'hui.\n\n'
                  '⏰ Vous avez installé l\'application ce soir — c\'est tout à fait normal ! '
                  'Les pronostics IA se créent automatiquement chaque matin quand vous ouvrez '
                  'l\'onglet Programme.\n\n'
                  '✅ Demain matin, ouvrez Programme → revenez ici pour lancer l\'analyse.'
                : '📋 Aucun pronostic IA en mémoire.\n\n'
                  'L\'IA crée automatiquement les pronostics quand l\'application '
                  'charge le programme du matin. Ouvrez l\'onglet Programme puis '
                  'revenez ici pour analyser.';
            return AnalyseJourneeResultat.vide(messageContextuel);
          } else {
            // Tous déjà traités → prendre les 34 plus récents pour recalcul
            pronosticsJour = _pronostics.toList()
              ..sort((a, b) => b.datePronostic.compareTo(a.datePronostic));
            pronosticsJour = pronosticsJour.take(34).toList();
            onProgress?.call(etape, 4,
                '♻️ Tous déjà traités — recalcul sur les '
                '${pronosticsJour.length} plus récents');
          }
        }
      }

      // Séparer : déjà un résultat vs en attente
      final dejaResultat = pronosticsJour.where((p) => p.resultatsReels).length;
      final aTraiter     = pronosticsJour.where((p) => !p.resultatsReels).toList();

      // Date de référence = date la plus récente parmi les pronostics sélectionnés
      // (tri décroissant → premier = le plus récent)
      final _pronosticsTriesDesc = [...pronosticsJour]
          ..sort((a, b) => b.datePronostic.compareTo(a.datePronostic));
      final _dateAnalyseReelle = _pronosticsTriesDesc.isNotEmpty
          ? _pronosticsTriesDesc.first.datePronostic
          : now;

      // LOG VISIBLE : afficher exactement ce qu'on a trouvé
      final dateRefLog = _pronosticsTriesDesc.isNotEmpty
          ? '${_dateAnalyseReelle.day.toString().padLeft(2, "0")}'
            '/${_dateAnalyseReelle.month.toString().padLeft(2, "0")}'
          : '?';
      onProgress?.call(etape, 4,
          '📋 Trouvé ${pronosticsJour.length} pronostics (date: $dateRefLog) — '
          '${aTraiter.length} à analyser, $dejaResultat déjà traités');

      // ★ v9.95 : liste des pronostics résolus UNIQUEMENT dans cette passe
      // (évite le double-comptage avec les passesprécédentes dans historiqueComplet)
      final List<IaPronostic> nouveauxResolusParPasse = [];

      if (aTraiter.isEmpty) {
        // Tout est déjà traité → re-déclencher l'apprentissage + rapport
        onProgress?.call(++etape, 4,
            '✅ Les $dejaResultat résultats du $dateRefLog sont déjà enregistrés — '
            're-calcul des poids IA…');
        nbCoursesAnalysees = dejaResultat;
        // Passer directement à l'apprentissage
      } else {

        // ── ÉTAPE 2 : Récupérer les résultats PMU pour chaque pronostic ───────
        onProgress?.call(++etape, 4,
            '🔍 Récupération de ${aTraiter.length} résultats PMU…');

        for (int i = 0; i < aTraiter.length; i++) {
          final p = aTraiter[i];
          final courseKey = p.courseKey;

          onProgress?.call(etape, 4,
              '⚙️ (${i + 1}/${aTraiter.length}) ${p.nomCourse} — $courseKey');

          try {
            // Parser le courseKey pour extraire numR et numC
            // Format : R{numR}C{numC}_{jour}{mois}{annee}
            // IMPORTANT : on utilise 'now' pour la dateStr (évite l'ambiguïté
            // du parsing jour/mois quand ils sont en 1 chiffre)
            final match = RegExp(r'^R(\d+)C(\d+)_')
                .firstMatch(courseKey);

            if (match == null) {
              nbCoursesEchouees++;
              erreurs.add('$courseKey : format de clé non reconnu');
              continue;
            }

            final numR = match.group(1)!;
            final numC = match.group(2)!;

            // ── Détection intelligente du statut de la course ─────────────
            // diffMin > 0  : course pas encore démarrée  → "Course à venir"
            // diffMin 0..-30 : course en cours (< 30 min)  → "Course en cours"
            // diffMin < -30 : course terminée              → analyser
            final heureCourse = p.datePronostic;
            final diffMin = heureCourse.difference(now).inMinutes;
            if (diffMin > 0) {
              // Course strictement future : départ pas encore arrivé
              nbCoursesFutures++;
              final hh = heureCourse.hour.toString().padLeft(2, '0');
              final mm = heureCourse.minute.toString().padLeft(2, '0');
              coursesAnalysees.add('${p.nomCourse} 🕐 [Course à venir — départ $hh:$mm]');
              continue;
            }
            if (diffMin > -30) {
              // Course démarrée il y a moins de 30 min : résultat pas encore dispo
              nbCoursesFutures++;
              final hh = heureCourse.hour.toString().padLeft(2, '0');
              final mm = heureCourse.minute.toString().padLeft(2, '0');
              coursesAnalysees.add('${p.nomCourse} 🔄 [Course en cours — départ $hh:$mm, résultat bientôt]');
              continue;
            }
            // diffMin <= -30 → course terminée depuis au moins 30 min : on analyse

            // dateStr construit depuis p.datePronostic (date réelle de la course)
            // → corrige le bug "lendemain matin" : si on analyse le 20/05 des courses
            //   du 19/05, l'URL PMU doit pointer sur le 19/05, pas le 20/05
            final courseDateRef = p.datePronostic;
            final jour    = courseDateRef.day.toString().padLeft(2, '0');
            final mois    = courseDateRef.month.toString().padLeft(2, '0');
            final annee   = courseDateRef.year.toString();
            final dateStr = '$jour$mois$annee'; // JJMMAAAA

            // ── Récupérer rapports-définitifs (même URL qu'alert_service) ──
            final url =
                'https://turfinfo.api.pmu.fr/rest/client/7'
                '/programme/$dateStr/R$numR/C$numC'
                '/rapports-definitifs?specialisation=INTERNET';

            final resp = await http
                .get(Uri.parse(url), headers: {'Accept': 'application/json'})
                .timeout(const Duration(seconds: 15));

            if (resp.statusCode != 200) {
              nbSansResultat++;
              coursesAnalysees.add('${p.nomCourse} ⏳ [HTTP ${resp.statusCode}]');
              nbCoursesAnalysees++;
              continue;
            }

            // ── Parser l'arrivée (même logique qu'alert_service) ──────────
            final List<int> arrivee = [];
            try {
              final rapports = jsonDecode(resp.body) as List<dynamic>;
              for (final r in rapports) {
                final typePari = r['typePari'] as String? ?? '';
                final rList    = (r['rapports'] as List<dynamic>?) ?? [];
                if (rList.isEmpty) continue;

                // Simple Gagnant → cheval N°1
                if (typePari == 'E_SIMPLE_GAGNANT') {
                  final n = int.tryParse(
                      (rList.first as Map)['combinaison']?.toString().trim() ?? '');
                  if (n != null && !arrivee.contains(n)) arrivee.insert(0, n);
                }
                // Placés → top 3
                if (typePari == 'E_SIMPLE_PLACE') {
                  for (final pl in rList) {
                    final n = int.tryParse(
                        (pl as Map)['combinaison']?.toString().trim() ?? '');
                    if (n != null && !arrivee.contains(n)) arrivee.add(n);
                  }
                }
                // Tiercé / Quarté / Quinté → ordre complet
                if (typePari.contains('TIERCE') || typePari.contains('QUARTE') ||
                    typePari.contains('QUINTE')) {
                  final combo = (rList.first as Map)['combinaison']?.toString() ?? '';
                  for (final part in combo.split('-')) {
                    final n = int.tryParse(part.trim());
                    if (n != null && !arrivee.contains(n)) arrivee.add(n);
                  }
                }
              }
            } catch (_) {}

            if (arrivee.isEmpty) {
              nbSansResultat++;
              coursesAnalysees.add('${p.nomCourse} ⏳ [résultat PMU pas encore disponible]');
              nbCoursesAnalysees++;
              continue;
            }

            // ── DELTA : comparer pronostic IA vs arrivée réelle ───────────
            final idx = _pronostics.indexWhere((pr) => pr.courseKey == courseKey);
            if (idx >= 0 && !_pronostics[idx].resultatsReels) {
              final topIA    = _pronostics[idx].topNIA;
              final arriveeS = arrivee.map((n) => n.toString()).toList();

              final favori  = topIA.isNotEmpty ? topIA.first : null;
              final idxFav  = favori != null ? arriveeS.indexOf(favori) : -1;
              final rangFav = idxFav >= 0 ? idxFav + 1 : null;

              final top3IA = topIA.take(3).toSet();
              final top3R  = arriveeS.take(3).toSet();
              final top5IA = topIA.take(5).toSet();
              final top5R  = arriveeS.take(5).toSet();
              final nbTop3 = top3IA.intersection(top3R).length;
              final nbTop5 = top5IA.intersection(top5R).length;

              double perf = 0;
              if (rangFav == 1)                         perf += 40;
              else if (rangFav != null && rangFav <= 3) perf += 20;
              else if (rangFav != null && rangFav <= 5) perf += 10;
              perf += nbTop3 * 15.0 + nbTop5 * 5.0;

              // ★ v82 : recalculer precisionIA synthèse 3 indices avec les poids courants
              final pOld = _pronostics[idx];
              final bestScoreJ = pOld.scoresIA.values.isEmpty ? 0.0 :
                  pOld.scoresIA.values.reduce((a, b) => a > b ? a : b);
              final confJ = pOld.confiancePredite ?? 65.0;
              final tauxMomentJ = pOld.tauxReussiteAuMoment ?? 50.0;
              final precIAJ = _poids.poidsIndices.calculerPrecision(
                scoreCriteres: bestScoreJ,
                confianceIA:   confJ,
                tauxReussite:  tauxMomentJ,
              );

              // ★ v9.94 : diagnostic lisible par course (était toujours null avant ce fix)
              final diagJ = _genererDiagnosticCourse(
                favoriNom:  pOld.favoriIaNom,
                rangFavori: rangFav,
                nbTop3:     nbTop3,
                nbTop5:     nbTop5,
                scorePerf:  perf.clamp(0, 100),
                typePari:   pOld.typePariConseille,
              );

              _pronostics[idx] = IaPronostic(
                courseKey:              pOld.courseKey,
                nomCourse:              pOld.nomCourse,
                hippodrome:             pOld.hippodrome,
                discipline:             pOld.discipline,
                datePronostic:          pOld.datePronostic,
                scoresIA:               pOld.scoresIA,
                scoresCriteres:         pOld.scoresCriteres,
                varianceScores:         pOld.varianceScores,
                arriveeReelle:          arrivee,
                dateResultat:           now,
                resultatsReels:         true,
                rangFavoriIaDansArrivee: rangFav,
                nbTop3DansArriveeReelle: nbTop3,
                nbTop5DansArriveeReelle: nbTop5,
                scorePerformance:       perf.clamp(0, 100),
                confiancePredite:       pOld.confiancePredite,
                // ★ v80/v81 : préserver les champs d'apprentissage par type
                typePariConseille:      pOld.typePariConseille,
                tauxReussiteAuMoment:   pOld.tauxReussiteAuMoment,
                precisionIA:            precIAJ,
                // ★ fix : préserver favoriIaNom (champ perdu avant ce fix)
                favoriIaNom:            pOld.favoriIaNom,
                // ★ v9.94 : diagnostic lisible par course
                diagnosticApprentissage: diagJ,
              );
              // ★ v9.95 : tracker CE pronostic comme nouvellement résolu dans cette passe
              nouveauxResolusParPasse.add(_pronostics[idx]);
              nbNouveauxResultats++;
            }

            nbCoursesAnalysees++;
            final rang1 = arrivee.isNotEmpty ? arrivee[0] : '?';
            coursesAnalysees.add('${p.nomCourse} ✓ [1er: N°$rang1]');

          } catch (e) {
            nbCoursesEchouees++;
            erreurs.add('${p.nomCourse} ($courseKey) : $e');
            if (kDebugMode) debugPrint('AnalyseJournée erreur $courseKey: $e');
          }
        }
        // Pronostics déjà traités → aussi comptés
        nbCoursesAnalysees += dejaResultat;
      }

      // ── ÉTAPE 3 : Sauvegarder + Apprentissage ────────────────────────────
      // ★ PROTECTION APPRENTISSAGE : ne déclencher le gradient QUE si de nouveaux
      // résultats ont été obtenus. Évite de perturber l'apprentissage dynamique
      // lors d'un appui "bouton rattrapage" sans données nouvelles.
      onProgress?.call(++etape, 4,
          nbNouveauxResultats > 0
              ? '💾 Sauvegarde… puis apprentissage IA ($nbNouveauxResultats nouveaux résultats)'
              : '💾 Sauvegarde de l\'état… (pas de nouveaux résultats → apprentissage non modifié)');
      await _save();

      if (nbNouveauxResultats > 0) {
        // ★ v9.93 POINT 4 : Détection journée atypique avant le gradient
        // Garde-fous stricts pour éviter le sur-apprentissage :
        //   1. Seuil très élevé : > 85% d'échecs ET >= 8 courses
        //   2. Les résultats bruts sont TOUJOURS enregistrés — seul le gradient est réduit
        //   3. Max 2 journées atypiques par mois — au-delà, gradient normal
        //   4. Log obligatoire dans le journal IA
        final facteurGradient = _calculerFacteurJourneeAtypique(
            pronosticsJour, now);

        // Apprentissage avec facteur atypique (1.0 = normal, 0.3 = réduit)
        await _apprendreParGradient(facteurAtypique: facteurGradient);

        // Apprendre pour chaque discipline des pronostics du jour
        final discVus = pronosticsJour.map((p) => p.discipline).toSet();
        for (final disc in discVus) {
          if (disc.isNotEmpty) {
            await _apprendreParDiscipline(disc, facteurAtypique: facteurGradient);
          }
        }
      } else {
        if (kDebugMode) {
          debugPrint('[AnalyseJournée] Apprentissage ignoré : 0 nouveaux résultats '
              '(nbFutures=$nbCoursesFutures, nbAttente=$nbSansResultat, '
              'déjàTraités=$dejaResultat)');
        }
      }

      await _mettreAJourCalibration();

      // ★ Fix v9.6 : fusionner pronostics IA du jour + paris manuels
      final statsIa = pronosticsJour
          .where((p) => p.resultatsReels && p.typePariConseille != null &&
                        p.typePariConseille!.isNotEmpty)
          .map((p) => <String, dynamic>{
            'typePari':  p.typePariConseille,
            'isCorrect': p.rangFavoriIaDansArrivee != null &&
                         p.rangFavoriIaDansArrivee! <= 3,
            'gainNet':   0.0,
          }).toList();
      final statsManuel = predictionsUtilisateur ?? [];
      final statsFusionnees = [...statsManuel, ...statsIa];
      if (statsFusionnees.isNotEmpty) {
        await mettreAJourStatsTypes(statsFusionnees);
      }

      // ★ v9.95 : Précision IA par type — SOURCE UNIQUE, SANS DOUBLE-COMPTAGE
      // On passe UNIQUEMENT les pronostics nouvellement résolus dans CETTE passe
      // (nouveauxResolusParPasse). L'ancien code utilisait sourceResolus = tous
      // les résolus du jour, ce qui recomptait les résultats déjà comptés lors
      // des passes précédentes (via enregistrerResultat ou une passe antérieure
      // d'analyseJourneeComplete), gonflant les compteurs ×2 ou plus dans
      // historiqueComplet pour tous les types de paris.
      // Si aucun nouveau résultat dans cette passe, on n'appelle pas
      // _mettreAJourPrecisionIA → pas de double-comptage.
      if (nouveauxResolusParPasse.isNotEmpty) {
        await _mettreAJourPrecisionIA(nouveauxResolusParPasse, now);
      }

      // ★ v9.6 : Sauvegarder la date de la dernière analyse pour le Worker Kotlin
      try {
        final prefsAnalyse = await SharedPreferences.getInstance();
        final dateStr =
            '${now.day.toString().padLeft(2, '0')}'
            '${now.month.toString().padLeft(2, '0')}'
            '${now.year}';
        await prefsAnalyse.setString('ia_derniere_analyse_v1', dateStr);
      } catch (_) {}

      // ── ÉTAPE 4 : Rapport journalier ──────────────────────────────────────
      onProgress?.call(++etape, 4, '📊 Calcul du rapport journalier…');
      final rapport = _calculerRapportJournalier(
          now, nbCoursesAnalysees, nbPronosticsAjoutes, nbCoursesEchouees);
      _ajouterRapport(rapport);
      await _save();
      notifyListeners();

      // ★ v5.0 : poidsFinaux inclut les 10 critères adaptatifs
      // ★ v9.0 audit : complet sur 17 critères (terrain/divergence/poidsRel/progression manquaient)
      // ★ v9.95 audit : complet sur 19 critères (mouvCote R + placeDepart S manquaient)
      final poidsFinaux = {
        'forme':       _poids.forme,
        'gains':       _poids.gains,
        'record':      _poids.record,
        'cote':        _poids.cote,
        'constance':   _poids.constance,
        'victoires':   _poids.victoires,
        'discipline':  _poids.discipline,
        'distSpec':    _poids.distSpec,
        'jockey':      _poids.jockey,
        'repos':       _poids.repos,
        'hippo':       _poids.hippo,       // ★ v7.0
        'entraineur':  _poids.entraineur,  // ★ v8.0
        'elo':         _poids.elo,         // ★ v8.0
        'terrain':     _poids.terrain,     // ★ v9.0
        'divergence':  _poids.divergence,  // ★ v9.0
        'poidsRel':    _poids.poidsRel,    // ★ v9.0
        'progression': _poids.progression, // ★ v9.0
        'mouvCote':    _poids.mouvCote,    // ★ v9.92
        'placeDepart': _poids.placeDepart, // ★ v9.93
      };

      // Message résumé
      String? messageInfo;
      if (nbNouveauxResultats > 0) {
        messageInfo = '✅ $nbNouveauxResultats résultat(s) comparés'
            '${nbSansResultat > 0 ? ' · $nbSansResultat en attente PMU' : ''}'
            '${nbCoursesFutures > 0 ? ' · $nbCoursesFutures futures ignorées' : ''}';
      } else if (nbSansResultat > 0) {
        messageInfo = '⏳ $nbSansResultat course(s) passées — résultats PMU pas encore publiés. Réessayez après 20h.';
      } else if (nbCoursesFutures > 0 && nbCoursesAnalysees == 0) {
        messageInfo = 'ℹ️ Toutes les courses sont encore à venir ($nbCoursesFutures). Réessayez ce soir.';
      } else if (dejaResultat > 0 && nbNouveauxResultats == 0) {
        messageInfo = '✅ Les $dejaResultat résultats du $dateRefLog sont déjà enregistrés — IA à jour.';
      }

      return AnalyseJourneeResultat(
        succes: true,
        dateAnalysee: _dateAnalyseReelle, // date réelle des courses, pas now
        nbCoursesAnalysees: nbCoursesAnalysees,
        nbNouveauxResultats: nbNouveauxResultats,
        nbPronosticsAjoutes: nbPronosticsAjoutes,
        nbCoursesEchouees: nbCoursesEchouees,
        nbCoursesFutures: nbCoursesFutures,
        nbSansResultat: nbSansResultat,
        coursesAnalysees: coursesAnalysees,
        erreurs: erreurs,
        poidsApres: poidsFinaux,
        nbMisesAJour: _poids.nbMisesAJour,
        rapport: rapport,
        messageErreur: messageInfo,
      );

    } catch (e) {
      if (kDebugMode) debugPrint('analyseJourneeComplete erreur: $e');
      return AnalyseJourneeResultat.erreur('Erreur inattendue : $e');
    }
  }

  // ── Calcul et persistance du rapport journalier ────────────────────────────

  RapportJournalier _calculerRapportJournalier(
      DateTime date, int nbCoursesAnalysees, int nbPronosticsAjoutes, int nbEchouees) {

    final dateDebut = DateTime(date.year, date.month, date.day);
    final dateFin   = dateDebut.add(const Duration(days: 1));

    final pronosticsJour = _pronostics.where((p) =>
        p.resultatsReels &&
        p.datePronostic.isAfter(dateDebut.subtract(const Duration(hours: 1))) &&
        p.datePronostic.isBefore(dateFin)).toList();

    final source = pronosticsJour.isNotEmpty
        ? pronosticsJour
        : _pronostics.where((p) => p.resultatsReels)
            .take(nbCoursesAnalysees > 0 ? nbCoursesAnalysees : 10).toList();

    int fg = 0, ft3 = 0, ft5 = 0, t3c = 0, t5c = 0;
    double totalScore = 0;
    int nbAvecResultat = 0;

    final Map<String, _DiscStats> discStats = {};
    // ★ v9.6 : Détail cours par course
    final List<CourseDetailRapport> coursesDetail = [];
    // ★ v9.6 : Stats par type de pari du jour
    final Map<String, _TypePariStats> typeStats = {};

    for (final p in source) {
      final rang  = p.rangFavoriIaDansArrivee;
      final score = p.scorePerformance ?? 0;
      totalScore += score;
      nbAvecResultat++;

      if (rang != null) {
        if (rang == 1) fg++;
        if (rang <= 3) ft3++;
        if (rang <= 5) ft5++;
      }
      if ((p.nbTop3DansArriveeReelle ?? 0) >= 2) t3c++;
      if ((p.nbTop5DansArriveeReelle ?? 0) >= 4) t5c++; // ★ v10.14 : seuil 4/5 (était 3/5)

      final disc = p.discipline.isNotEmpty ? p.discipline : 'Inconnu';
      discStats.putIfAbsent(disc, () => _DiscStats(disc));
      discStats[disc]!.add(rang, score);

      // ★ v9.6 : Construire le détail de cette course
      final favori = p.favoriIA;
      final scoreIaFavori = favori != null ? (p.scoresIA[favori] ?? 0.0) : 0.0;
      final noteC = rang == 1 ? '✅ Excellent'
          : rang != null && rang <= 3 ? '👍 Bon'
          : rang != null && rang <= 5 ? '➖ Moyen'
          : '⚠️ Faible';

      // Extraire l'heure depuis la clé (format R1C2_03052026)
      final heureC = p.datePronostic.hour > 0
          ? '${p.datePronostic.hour.toString().padLeft(2,'0')}:${p.datePronostic.minute.toString().padLeft(2,'0')}'
          : '';

      coursesDetail.add(CourseDetailRapport(
        courseKey:         p.courseKey,
        nomCourse:         p.nomCourse,
        hippodrome:        p.hippodrome,
        heure:             heureC,
        discipline:        p.discipline,
        typePariConseille: p.typePariConseille ?? '',
        favoriIaNumero:    favori,
        favoriIaNom:       p.favoriIaNom, // ★ v9.6 nom du cheval favori
        scoreIA:           scoreIaFavori,
        arriveeReelle:     p.arriveeReelle ?? [],
        rangFavoriIa:      rang,
        nbTop3DansArrivee: p.nbTop3DansArriveeReelle ?? 0,
        nbTop5DansArrivee: p.nbTop5DansArriveeReelle ?? 0,
        scorePerformance:  score,
        noteCourseFlavour: noteC,
      ));

      // ★ v9.6 : Alimenter les stats par type de pari
      final tp = p.typePariConseille ?? 'Inconnu';
      typeStats.putIfAbsent(tp, () => _TypePariStats(tp));
      typeStats[tp]!.add(rang, scoreIaFavori);
    }

    // Trier les courses par heure
    coursesDetail.sort((a, b) => a.heure.compareTo(b.heure));

    final scoreMoyen  = nbAvecResultat > 0 ? totalScore / nbAvecResultat : 0.0;
    final tauxGagnant = nbAvecResultat > 0 ? fg / nbAvecResultat * 100    : 0.0;

    final parDiscipline = discStats.values
        .map((ds) => StatsDisciplineJour(
              discipline:    ds.discipline,
              nbCourses:     ds.nb,
              favoriGagnant: ds.fg,
              favoriTop3:    ds.ft3,
              favoriTop5:    ds.ft5,
              scoreMoyen:    ds.nb > 0 ? ds.totalScore / ds.nb : 0,
            ))
        .toList();

    // ★ v9.6 : Convertir typeStats en StatsTypePariJour
    final parTypePari = typeStats.values
        .map((ts) => StatsTypePariJour(
              typePari:        ts.type,
              nbPronostiques:  ts.nb,
              nbFavoriTop3:    ts.ft3,
              nbFavoriGagnant: ts.fg,
              scoreMoyen:      ts.nb > 0 ? ts.totalScore / ts.nb : 0,
            ))
        .toList()
      ..sort((a, b) => a.typePari.compareTo(b.typePari));

    final note = RapportJournalier.calculerNote(tauxGagnant, scoreMoyen);

    return RapportJournalier(
      date:                date,
      nbCoursesAnalysees:  nbCoursesAnalysees,
      nbAvecResultat:      nbAvecResultat,
      nbPronosticsAjoutes: nbPronosticsAjoutes,
      favoriGagnant:       fg,
      favoriTop3:          ft3,
      favoriTop5:          ft5,
      top3Correct2sur3:    t3c,
      top5Correct4sur5:    t5c, // ★ v10.14 : seuil 4/5
      scoreMoyenJour:      scoreMoyen,
      parDiscipline:       parDiscipline,
      nbMisesAJourPoids:   _poids.nbMisesAJour,
      heureAnalyse:        DateTime.now(),
      coursesDetail:       coursesDetail,
      parTypePari:         parTypePari,
      // ★ v87 audit : inclure les 11 critères dans le rapport (hippo manquait)
      // ★ v9.0 audit : complet sur 17 critères (entraineur/elo/terrain/divergence/poidsRel/progression manquaient)
      // ★ v9.95 audit : complet sur 19 critères (mouvCote R + placeDepart S manquaient)
      poidsApres: {
        'forme':       _poids.forme,
        'gains':       _poids.gains,
        'record':      _poids.record,
        'cote':        _poids.cote,
        'constance':   _poids.constance,
        'victoires':   _poids.victoires,
        'discipline':  _poids.discipline,
        'distSpec':    _poids.distSpec,
        'jockey':      _poids.jockey,
        'repos':       _poids.repos,
        'hippo':       _poids.hippo,       // ★ v7.0
        'entraineur':  _poids.entraineur,  // ★ v8.0
        'elo':         _poids.elo,         // ★ v8.0
        'terrain':     _poids.terrain,     // ★ v9.0
        'divergence':  _poids.divergence,  // ★ v9.0
        'poidsRel':    _poids.poidsRel,    // ★ v9.0
        'progression': _poids.progression, // ★ v9.0
        'mouvCote':    _poids.mouvCote,    // ★ v9.92
        'placeDepart': _poids.placeDepart, // ★ v9.93
      },
      nbCoursesEchouees:   nbEchouees,
      noteJournee:         note,
    );
  }

  void _ajouterRapport(RapportJournalier rapport) {
    // Remplacer le rapport du même jour s'il existe déjà
    _rapports.removeWhere((r) =>
        r.date.year  == rapport.date.year &&
        r.date.month == rapport.date.month &&
        r.date.day   == rapport.date.day);
    _rapports.add(rapport);
    // Garder les _maxRapports jours les plus récents (on garde les derniers insérés)
    if (_rapports.length > _maxRapports) {
      _rapports.removeAt(0); // supprimer le plus ancien
    }
  }

  // ── Helpers : noms lisibles ────────────────────────────────────────────────

  static String _labelCritere(String k) {
    const labels = {
      'forme':      'Forme récente',
      'gains':      'Gains carrière',
      'record':     'Record/Vitesse',
      'cote':       'Cote marché',
      'constance':  'Régularité',
      'victoires':  'Victoires',
      'discipline': 'Spécialisation',
      'distSpec':   'Dist. spécialisée',
      'jockey':     'Jockey/Driver',
      'repos':      'Repos physique',
      'hippo':      'Spéc. Hippodrome',
      'entraineur': 'Entraîneur',        // ★ v8.0
      'elo':        'ELO dynamique',     // ★ v8.0
      'terrain':    'Terrain',           // ★ v9.0
      'divergence': 'Coup préparé',      // ★ v9.0
      'poidsRel':   'Poids porté',       // ★ v9.0
      'progression':'Progression',       // ★ v9.0
    };
    return labels[k] ?? k;
  }

  static String _nomLisibleDiscipline(String disc) {
    switch (disc) {
      case 'trot_attele':  return 'Trot Attelé';
      case 'trot_monte':   return 'Trot Monté';
      case 'plat':         return 'Plat';
      case 'obstacle':     return 'Obstacle';
      default:             return disc.isNotEmpty ? disc : 'Inconnu';
    }
  }

  static double _median(List<double> list) {
    if (list.isEmpty) return 0;
    final sorted = List<double>.from(list)..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
  }

  static String _interpreterRegles(double tauxGagne, double tauxMauvais, double tauxBonTop3) {
    if (tauxGagne >= 0.35) return '🟢 IA très performante — le favori gagne souvent';
    if (tauxGagne >= 0.25) return '🟡 IA correcte — taux de victoire conforme aux attentes';
    if (tauxMauvais >= 0.4) return '🔴 IA à affiner — trop de mauvais classements';
    if (tauxBonTop3 >= 0.5) return '🟢 Bonne prédiction top-3 — continuer à apprendre';
    return '⚪ Données insuffisantes pour conclure';
  }

  List<String> _genererDiagnosticGlobal(
      int nb, int totalBons, int totalMauvais,
      Map<String, double> discriminations, Map<String, double> poidsAvant,
      {String suffixe = ''}) {
    // ★ v90 : labels complets (11 critères dont hippo) — utilise _labelCritere
    // pour éviter la duplication et assurer la cohérence
    final lines = <String>[
      'Gradient sur $nb courses — Bons: $totalBons / Mauvais: $totalMauvais$suffixe',
      _interpreterRegles(0, 0, 0),
    ];
    final sorted = discriminations.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    for (final e in sorted) {
      final label = _labelCritere(e.key); // ★ v90 : utilise _labelCritere (11 critères + hippo)
      final val   = e.value;
      final avant = poidsAvant[e.key] ?? 0;
      // ★ v90 : utiliser le poids actuel du critère (non plus _poids.forme pour tous)
      final apres = _poids.getPoids(e.key);
      final diff  = apres - avant;
      final sign  = diff >= 0 ? '+' : '';
      String emoji;
      if (val > 0.10)       emoji = '🟢';
      else if (val > 0.05)  emoji = '✅';
      else if (val < -0.10) emoji = '🔴';
      else                  emoji = '⚪';
      lines.add('$emoji $label : ${(val * 100).toStringAsFixed(1)}% ($sign${(diff * 100).toStringAsFixed(1)}%)');
    }
    return lines;
  }

  // ── Stats par type de pari (alias pour la compatibilité) ──────────────────

  Future<void> mettreAJourStatsTypes(List<Map<String, dynamic>> predictions) async {
    await _load();
    // ── RECALCUL DEPUIS ZÉRO ─────────────────────────────────────────────────
    // On reçoit la liste COMPLÈTE des paris à chaque appel (source de vérité).
    // On réinitialise _statsTypes avant de tout recalculer pour éviter le
    // double-comptage qui survenait quand la méthode était appelée plusieurs fois.
    _statsTypes.clear();
    for (final pred in predictions) {
      final type      = pred['typePari'] as String? ?? 'Inconnu';
      final isCorrect = pred['isCorrect'] as bool?;   // null = en attente
      final gainNet   = (pred['gainNet'] as num?)?.toDouble() ?? 0.0;

      // On ne compte que les paris avec un résultat connu (pas les "en attente")
      if (isCorrect == null) continue;

      if (_statsTypes.containsKey(type)) {
        final s = _statsTypes[type]!;
        s.nbJoues++;
        if (isCorrect) s.nbGagnes++; else s.nbPerdus++;
        s.gainNet += gainNet;
      } else {
        _statsTypes[type] = StatsTypePari(
          typePari: type,
          nbJoues:  1,
          nbGagnes: isCorrect ? 1 : 0,
          nbPerdus: isCorrect ? 0 : 1,
          gainNet:  gainNet,
        );
      }
    }
    await _save();
    notifyListeners();
  }

  // ── Précision IA par type de pari + seuils adaptatifs ────────────────────
  //
  //  Pour chaque course du jour :
  //   1. On récupère le typePariConseille stocké dans IaPronostic
  //   2. On regarde si le conseil était "bon" selon les règles métier
  //   3. On met à jour StatsPrecisionParType pour ce type
  //   4. On ajuste les seuils de confiance SeuilsConfianceAdaptatifs
  //      → si un type a un mauvais taux, son seuil monte (l'IA devient
  //        plus exigeante avant de conseiller ce type)
  //      → si un type a un bon taux, le seuil peut légèrement descendre
  //
  //  Les seuils adaptatifs sont ensuite lus par best_bet_screen.dart
  //  via IaMemoryService.instance.seuilsConfiance
  // ─────────────────────────────────────────────────────────────────────────────

  /// Wrapper public — utilisé par ia_performance_screen pour le dialogue Précision IA.
  /// Délègue à _estBonConseilParType sans modifier la logique d'apprentissage.
  bool estBonConseil(IaPronostic p, String typePari) =>
      _estBonConseilParType(p, typePari);

  // ★ v9.0 : Reconstruit le label IA d'un cheval depuis son rang et score
  // Miroir de IaPronosticEngine._determinerLabel
  static String _labelPourRangScore(int rang, double score, int total) {
    if (rang == 1 && score >= 70) return '🥇 FAVORI IA';
    if (rang == 1 && score >= 50) return '⭐ SÉLECTION IA';
    if (rang == 1)                return '🎯 CHOIX IA';
    if (rang == 2)                return '🥈 2ème choix';
    if (rang == 3)                return '🥉 3ème choix';
    if (rang <= 5)                return '✅ À surveiller';
    if (rang > total - 2)         return '⚠️ Outsider';
    return ''; // 'Dans le lot' → pas de stats (trop générique)
  }
  /// Détermine si le conseil de l'IA était bon pour un type de pari donné.
  /// Basé sur les résultats réels PMU stockés dans IaPronostic.
  bool _estBonConseilParType(IaPronostic p, String typePari) {
    final rang  = p.rangFavoriIaDansArrivee;
    final top3  = p.nbTop3DansArriveeReelle ?? 0;
    final top5  = p.nbTop5DansArriveeReelle ?? 0;

    switch (typePari) {
      case 'Simple Gagnant':
        return rang == 1;

      case 'Gagnant+Placé':
        // Gagné si 1er (gagnant) OU dans le top 3 (placé)
        return rang != null && rang <= 3;

      case 'Simple Placé':
        return rang != null && rang <= 3;

      case 'Couplé Gagnant':
        // Au moins 1 des 2 premiers IA est dans le top 2 réel
        return rang != null && rang <= 2;

      case 'Couplé Placé':
        // Au moins 1 des 2 premiers IA est dans le top 3 réel
        return rang != null && rang <= 3;

      case 'Tiercé':
        // ✅ VERT si au moins 2 des 3 chevaux IA sont dans le top 3 réel (ordre libre)
        // Exemple : IA donne N°3, N°7, N°11 → si N°3 et N°7 finissent dans les 3 premiers → OK
        return top3 >= 2;

      case 'Tiercé Ordre':
        // ✅ VERT uniquement si les 3 chevaux IA sont dans le top 3 ET dans l'ordre exact
        // Exemple : IA donne N°3 (1er), N°7 (2ème), N°11 (3ème) → ils doivent finir exactement dans cet ordre
        {
          final arrivee = p.arriveeReelle;
          if (arrivee == null || arrivee.length < 3) return top3 >= 2; // fallback si pas d'arrivée
          final topIA = p.topNIA.map((e) => int.tryParse(e)).whereType<int>().toList();
          if (topIA.length < 3) return top3 >= 2;
          // Ordre exact : cheval 1 IA = 1er réel, cheval 2 IA = 2ème réel, cheval 3 IA = 3ème réel
          return topIA[0] == arrivee[0] && topIA[1] == arrivee[1] && topIA[2] == arrivee[2];
        }

      case 'Quarté+':
        // ✅ VERT si au moins 3 des 4 chevaux IA sont dans le top 4 réel
        // Exemple : IA donne N°3, N°7, N°11, N°2 → si 3 d'entre eux finissent dans les 4 premiers → OK
        // CORRECTION v10.12 : on utilise nbTop3 (top4 = top3 + rang<=4)
        // top3 compte les chevaux IA dans les 3 premiers, on ajoute le rang pour le 4ème
        {
          final arrivee = p.arriveeReelle;
          if (arrivee == null || arrivee.length < 4) return top3 >= 2; // fallback
          final topIA = p.topNIA.map((e) => int.tryParse(e)).whereType<int>().toList();
          if (topIA.length < 4) return top3 >= 2;
          // Compter combien de chevaux IA sont dans le top 4 réel
          final top4Reel = arrivee.take(4).toSet();
          final nbDansTop4 = topIA.take(4).where((n) => top4Reel.contains(n)).length;
          return nbDansTop4 >= 3; // au moins 3 des 4 chevaux IA dans les 4 premiers réels
        }

      case 'Quinté+':
        // ✅ VERT si au moins 4 des 5 chevaux IA sont dans le top 5 réel
        // Exemple : IA donne N°3, N°7, N°11, N°2, N°9 → si 4 d'entre eux finissent dans les 5 premiers → OK
        // CORRECTION v10.12 : seuil 4/5 au lieu de 3/5 (3/5 était trop facile)
        {
          final arrivee = p.arriveeReelle;
          if (arrivee == null || arrivee.length < 5) return top5 >= 3; // fallback
          final topIA = p.topNIA.map((e) => int.tryParse(e)).whereType<int>().toList();
          if (topIA.length < 5) return top5 >= 3;
          // Compter combien de chevaux IA sont dans le top 5 réel
          final top5Reel = arrivee.take(5).toSet();
          final nbDansTop5 = topIA.take(5).where((n) => top5Reel.contains(n)).length;
          return nbDansTop5 >= 4; // au moins 4 des 5 chevaux IA dans les 5 premiers réels
        }

      default:
        // Fallback : le favori est dans les 3 premiers
        return rang != null && rang <= 3;
    }
  }

  /// Détermine si le bon conseil est en ORDRE EXACT ou en DÉSORDRE.
  /// Retourne true = ordre, false = désordre, null = pas applicable (Simple, Couplé, etc.)
  bool? _estOrdreExact(IaPronostic p, String typePari) {
    final arrivee = p.arriveeReelle;
    if (arrivee == null || arrivee.isEmpty) return null;
    final topIA = p.topNIA.map((e) => int.tryParse(e)).whereType<int>().toList();

    switch (typePari) {
      case 'Tiercé':
        if (topIA.length < 3 || arrivee.length < 3) return null;
        // Ordre exact : les 3 premiers IA = les 3 premiers réels dans le même ordre
        final ordreOk = topIA[0] == arrivee[0] && topIA[1] == arrivee[1] && topIA[2] == arrivee[2];
        if (ordreOk) return true;
        // Désordre : les 3 chevaux sont bons mais pas dans l'ordre
        final top3IA   = topIA.take(3).toSet();
        final top3Reel = arrivee.take(3).toSet();
        return top3IA.intersection(top3Reel).length >= 3 ? false : null;

      case 'Quarté+':
        if (topIA.length < 4 || arrivee.length < 4) return null;
        final ordreOk = topIA[0] == arrivee[0] && topIA[1] == arrivee[1] &&
                        topIA[2] == arrivee[2] && topIA[3] == arrivee[3];
        if (ordreOk) return true;
        // Désordre : au moins 3 des 4 premiers IA dans le top4 réel
        final top4IA   = topIA.take(4).toSet();
        final top4Reel = arrivee.take(4).toSet();
        return top4IA.intersection(top4Reel).length >= 3 ? false : null;

      case 'Quinté+':
        if (topIA.length < 5 || arrivee.length < 5) return null;
        final ordreOk = topIA[0] == arrivee[0] && topIA[1] == arrivee[1] &&
                        topIA[2] == arrivee[2] && topIA[3] == arrivee[3] && topIA[4] == arrivee[4];
        if (ordreOk) return true;
        // Désordre : au moins 3 des 5 premiers IA dans le top5 réel
        final top5IA   = topIA.take(5).toSet();
        final top5Reel = arrivee.take(5).toSet();
        return top5IA.intersection(top5Reel).length >= 3 ? false : null;

      default:
        return null; // Simple, Couplé → pas de notion ordre/désordre
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ v9.95 : RECALCUL COMPLET DE _precisionParType DEPUIS LES PRONOSTICS BRUTS
  //
  //  Appelée UNE SEULE FOIS au chargement (flag ia_precision_migrated_v2).
  //  Remet à zéro les compteurs gonflés par le double-comptage historique
  //  (analyseJourneeComplete + enregistrerResultat appelaient tous deux
  //  _mettreAJourPrecisionIA → ajouterJournee cumulait → ×2 ou plus).
  //
  //  Principe : on regroupe les IaPronostic résolus par date et par type de
  //  pari, puis on recalcule chaque entrée de historiqueComplet proprement,
  //  sans aucune accumulation. Les compteurs permanents (nbTotalAll, nbBonsAll)
  //  et la fenêtre 60j sont recalculés en conséquence.
  //
  //  NE TOUCHE PAS à : _apprendreParGradient, _apprendreParDiscipline,
  //  _statsLabels, _statsTypes, _seuils, _poids — apprentissage intact.
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _recalculerPrecisionParTypeDepuisPronostics() async {
    // Regrouper les pronostics résolus par date (YYYY-MM-DD) et par type
    final Map<String, Map<String, _AgregJour>> parDateType = {};
    // _AgregJour est une micro-structure locale : {nb, bon, ord, des}

    for (final p in _pronostics) {
      if (!p.resultatsReels) continue;
      final type = p.typePariConseille ?? 'Inconnu';
      if (type == 'Inconnu' || type == 'À surveiller' || type.isEmpty) continue;

      final d = p.datePronostic;
      final dateStr = '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

      parDateType[dateStr] ??= {};
      parDateType[dateStr]![type] ??= _AgregJour();
      final agg = parDateType[dateStr]![type]!;
      agg.nb++;
      if (_estBonConseilParType(p, type)) {
        agg.bon++;
        final estOrdre = _estOrdreExact(p, type);
        if (estOrdre == true)  agg.ord++;
        if (estOrdre == false) agg.des++;
      }
    }

    // Reconstruire _precisionParType depuis zéro
    _precisionParType.clear();

    for (final dateStr in parDateType.keys) {
      final parts = dateStr.split('-');
      final date  = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      final typesJour = parDateType[dateStr]!;

      for (final type in typesJour.keys) {
        final agg = typesJour[type]!;
        if (agg.nb == 0) continue;

        _precisionParType[type] ??= StatsPrecisionParType(typePari: type);
        _precisionParType[type]!.ajouterJournee(date, agg.nb, agg.bon,
            ordre: agg.ord, desordre: agg.des);
      }
    }

    // Sauvegarder le résultat recalculé
    await _save();
    if (kDebugMode) {
      debugPrint('[IaMemory] ✅ Migration v9.95 : _precisionParType recalculé '
          'depuis ${_pronostics.where((p) => p.resultatsReels).length} pronostics bruts. '
          'Types : ${_precisionParType.keys.join(', ')}');
    }
  }

  /// Met à jour la précision par type de pari et ajuste les seuils.
  /// Appelée par analyseJourneeComplete APRÈS le gradient standard.
  Future<void> _mettreAJourPrecisionIA(
      List<IaPronostic> pronosticsAvecResultats, DateTime date) async {
    if (pronosticsAvecResultats.isEmpty) return;

    // ── Étape 1 : mettre à jour la précision par type de pari ──────────────
    int nbTotal = 0;
    final Map<String, int> nbParType      = {};
    final Map<String, int> bonParType     = {};
    final Map<String, int> ordreParType   = {}; // ← ORDRE EXACT
    final Map<String, int> desordreParType = {}; // ← DÉSORDRE (bons chevaux mauvais ordre)

    for (final p in pronosticsAvecResultats) {
      if (!p.resultatsReels) continue;
      nbTotal++;

      final type = p.typePariConseille ?? 'Inconnu';
      // ★ fix : ignorer "Inconnu" et "À surveiller" dans les stats de précision
      // (type non déterminé = donnée invalide, ne doit pas polluer les stats)
      if (type == 'Inconnu' || type == 'À surveiller' || type.isEmpty) continue;
      nbParType[type] = (nbParType[type] ?? 0) + 1;

      if (_estBonConseilParType(p, type)) {
        bonParType[type] = (bonParType[type] ?? 0) + 1;
        // Calculer ordre vs désordre pour les paris multi-chevaux
        final estOrdre = _estOrdreExact(p, type);
        if (estOrdre == true) {
          ordreParType[type] = (ordreParType[type] ?? 0) + 1;
        } else if (estOrdre == false) {
          desordreParType[type] = (desordreParType[type] ?? 0) + 1;
        }
      }
    }

    if (nbTotal == 0) return;

    // Enregistrer les stats du jour dans l'historique de chaque type
    for (final type in nbParType.keys) {
      final nb      = nbParType[type]      ?? 0;
      final bons    = bonParType[type]     ?? 0;
      final ordre   = ordreParType[type]   ?? 0;
      final desordre = desordreParType[type] ?? 0;
      if (!_precisionParType.containsKey(type)) {
        _precisionParType[type] = StatsPrecisionParType(typePari: type);
      }
      _precisionParType[type]!.ajouterJournee(date, nb, bons,
          ordre: ordre, desordre: desordre);
    }

    // ★ v9.0 : Calculer les stats par label IA ──────────────────────────────
    // Pour chaque pronostic avec résultat, on regarde les labels attribués
    // aux chevaux et si ces chevaux sont arrivés dans le top1/3/5
    final Map<String, int> labelNb   = {};
    final Map<String, int> labelTop1 = {};
    final Map<String, int> labelTop3 = {};
    final Map<String, int> labelTop5 = {};

    for (final p in pronosticsAvecResultats) {
      if (!p.resultatsReels || p.arriveeReelle == null) continue;
      final arrivee = p.arriveeReelle!.map((n) => n.toString()).toList();

      // Retrouver les labels depuis scoresCriteres + scoresIA
      // On utilise les scoresIA pour reconstruire le classement et les labels
      final sorted = p.scoresIA.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      for (int rang = 0; rang < sorted.length; rang++) {
        final numero = sorted[rang].key;
        final score  = sorted[rang].value;

        // Reconstruire le label comme le fait IaPronosticEngine._determinerLabel
        final label = _labelPourRangScore(rang + 1, score, sorted.length);
        if (label.isEmpty) continue;

        // Aussi vérifier les labels spéciaux v9 depuis scoresCriteres
        final sc = p.scoresCriteres[numero];
        final labelsChemin = <String>[label];
        if (sc != null) {
          if (sc.divergence >= 80) labelsChemin.add('⚡ Coup préparé possible');
          if (sc.terrain >= 75)    labelsChemin.add('🌿 Bon terrain');
          if (sc.progression >= 72) labelsChemin.add('📈 Progression');
        }

        final isTop1 = arrivee.isNotEmpty && arrivee[0] == numero;
        final isTop3 = arrivee.take(3).contains(numero);
        final isTop5 = arrivee.take(5).contains(numero);

        for (final lbl in labelsChemin) {
          labelNb[lbl]   = (labelNb[lbl]   ?? 0) + 1;
          if (isTop1) labelTop1[lbl] = (labelTop1[lbl] ?? 0) + 1;
          if (isTop3) labelTop3[lbl] = (labelTop3[lbl] ?? 0) + 1;
          if (isTop5) labelTop5[lbl] = (labelTop5[lbl] ?? 0) + 1;
        }
      }
    }

    // Enregistrer les stats label du jour
    for (final lbl in labelNb.keys) {
      final nb   = labelNb[lbl]   ?? 0;
      if (nb == 0) continue;
      if (!_statsLabels.containsKey(lbl)) {
        _statsLabels[lbl] = StatsParLabel(label: lbl);
      }
      _statsLabels[lbl]!.ajouterJournee(
        date,
        nb,
        labelTop1[lbl] ?? 0,
        labelTop3[lbl] ?? 0,
        labelTop5[lbl] ?? 0,
      );
    }

    // ★ v9.0 : Ajustement gradient basé sur les stats labels
    // Si un label "⚡ Coup préparé" a un bon taux top3 → renforcer le critère divergence
    for (final stats in _statsLabels.values) {
      if (!stats.estFiable) continue;
      final critere = StatsParLabel.criterePourLabel(stats.label);
      if (critere == null) continue;
      // Gradient doux : si performance du label > 40% → légère augmentation du poids
      final perf = stats.scorePerformanceLabel;
      final delta = (perf - 40.0) / 1000.0; // très doux, max ±0.05
      switch (critere) {
        case 'divergence':  _poids.divergence  = (_poids.divergence  + delta).clamp(0.01, 0.10); break;
        case 'terrain':     _poids.terrain     = (_poids.terrain     + delta).clamp(0.01, 0.10); break;
        case 'progression': _poids.progression = (_poids.progression + delta).clamp(0.01, 0.08); break;
        case 'poidsRel':    _poids.poidsRel    = (_poids.poidsRel    + delta).clamp(0.01, 0.07); break;
      }
    }
    if (_statsLabels.values.any((s) => s.estFiable && StatsParLabel.criterePourLabel(s.label) != null)) {
      _poids.normaliser();
    }

    // ── Étape 2 : ajuster les seuils de confiance selon la précision ────────
    //
    //  Logique d'adaptation :
    //  • Si taux de réussite < seuilCible → seuil monte (+0.5 à +1.5 pts)
    //    L'IA sera plus sélective avant de proposer ce type de pari
    //  • Si taux de réussite > seuilCible + marge → seuil descend (-0.3 pts)
    //    L'IA peut proposer ce type un peu plus facilement
    //  • Variation max par journée : ±2.0 pts pour rester stable
    //
    const double lr = 0.015; // taux d'apprentissage des seuils (doux)

    for (final type in nbParType.keys) {
      final stat = _precisionParType[type];
      if (stat == null || stat.nbTotal < 3) continue; // min 3 cours analysées

      final taux = stat.tauxReussite;

      // Seuil cible par type (quel taux on veut atteindre minimum)
      final double seuilCibleTaux;
      switch (type) {
        case 'Simple Gagnant':
          seuilCibleTaux = 30.0; // gagner 30% du temps = bon
          break;
        case 'Gagnant+Placé':
          seuilCibleTaux = 35.0;
          break;
        case 'Simple Placé':
          seuilCibleTaux = 50.0; // placé plus facile → 50%
          break;
        case 'Couplé Gagnant':
          seuilCibleTaux = 35.0;
          break;
        case 'Couplé Placé':
          seuilCibleTaux = 45.0;
          break;
        case 'Tiercé':
          seuilCibleTaux = 40.0;
          break;
        case 'Quarté+':
          seuilCibleTaux = 35.0;
          break;
        case 'Quinté+':
          seuilCibleTaux = 30.0; // quinté difficile
          break;
        default:
          seuilCibleTaux = 40.0;
      }

      final delta = (seuilCibleTaux - taux) * lr;
      _seuils.ajusterSeuil(type, delta);

      if (kDebugMode) {
        debugPrint('[SeuilsIA] $type : taux=${taux.toStringAsFixed(1)}% '
            'cible=${seuilCibleTaux.toStringAsFixed(0)}% '
            'Δseuil=${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(2)}');
      }
    }

    // ── Étape 3 : calcul des 3 deltas (indices) pour apprendre les PoidsIndices ──
    //
    //  Pour chaque course résolue ce jour, on mesure :
    //  • Δ1 (critères)  : le favori IA (score multicritères le plus élevé) était-il bon ?
    //                     "Bon" = dans le top 3 réel → indicateur large de la qualité du scoring
    //  • Δ2 (confiance) : la confiance prédite était-elle justifiée ?
    //                     "Justifiée" = confiancePredite ≥ 65 ET rang ≤ 3 (bien confiant + bien classé)
    //                                  OU confiancePredite < 65 ET rang > 3 (pas confiant + pas dans top)
    //                     (calibration : confiance cohérente avec le résultat)
    //  • Δ3 (réussite)  : le type de pari conseillé était-il bon ?
    //                     Utilise _estBonConseilParType()
    //
    //  delta = fraction de courses où l'indice était prédictif (0.0 à 1.0)
    //  Le PoidsIndices est mis à jour avec ces 3 fractions.

    if (nbTotal >= 3) { // assez de données pour mettre à jour les poids
      int nbBonCriteres = 0;
      int nbBonConfiance = 0;
      int nbBonReussite = 0;

      for (final p in pronosticsAvecResultats) {
        if (!p.resultatsReels) continue;

        // Δ1 : critères (favori IA dans le top 3 ?)
        final rang = p.rangFavoriIaDansArrivee;
        if (rang != null && rang <= 3) nbBonCriteres++;

        // Δ2 : confiance (calibration correcte ?)
        final conf = p.confiancePredite ?? 65.0;
        final confJustifiee = (conf >= 65.0 && rang != null && rang <= 3) ||
                              (conf <  65.0 && (rang == null || rang > 3));
        if (confJustifiee) nbBonConfiance++;

        // Δ3 : réussite (conseil type pari correct ?)
        final type = p.typePariConseille ?? 'Inconnu';
        if (_estBonConseilParType(p, type)) nbBonReussite++;
      }

      final deltaCriteres  = nbBonCriteres  / nbTotal;
      final deltaConfiance = nbBonConfiance / nbTotal;
      final deltaReussite  = nbBonReussite  / nbTotal;

      _poids.poidsIndices.mettreAJourDepuisDeltas(
        deltasCriteres:  deltaCriteres,
        deltasConfiance: deltaConfiance,
        deltasReussite:  deltaReussite,
      );

      if (kDebugMode) {
        debugPrint('[PoidsIndices] Δ1(critères)=${(deltaCriteres*100).toStringAsFixed(1)}% '
            'Δ2(confiance)=${(deltaConfiance*100).toStringAsFixed(1)}% '
            'Δ3(réussite)=${(deltaReussite*100).toStringAsFixed(1)}%');
        debugPrint('[PoidsIndices] Nouveaux poids → ${_poids.poidsIndices.resume}');
      }

      // ── Étape 4 : recalculer precisionIA pour toutes les courses résolues ──────
      // Après avoir mis à jour les poids, recalculer la précisionIA pour toutes
      // les courses résolues (utilise les nouveaux poids appris)
      for (int i = 0; i < _pronostics.length; i++) {
        final p = _pronostics[i];
        if (!p.resultatsReels) continue;
        final bestScore = p.scoresIA.values.isEmpty ? 0.0 :
            p.scoresIA.values.reduce((a, b) => a > b ? a : b);
        final conf = p.confiancePredite ?? 65.0;
        final tauxR = p.tauxReussiteAuMoment ?? 50.0;
        p.precisionIA = _poids.poidsIndices.calculerPrecision(
          scoreCriteres: bestScore,
          confianceIA:   conf,
          tauxReussite:  tauxR,
        );
      }
    }

    await _save();

    if (kDebugMode) {
      debugPrint('[PrécisionIA] Journée $nbTotal courses analysées par type : '
          '${nbParType.entries.map((e) => "${e.key}=${bonParType[e.key] ?? 0}/${e.value}").join(", ")}');
    }
  }

  /// Getter pour les poids des 3 indices (exposé aux écrans)
  PoidsIndices get poidsIndices => _poids.poidsIndices;

  /// Méthode publique pour lire les seuils adaptatifs (appelée par best_bet_screen)
  SeuilsConfianceAdaptatifs getSeuilsAdaptatifs() => _seuils;

  // ── Méthodes utilitaires publiques ─────────────────────────────────────────

  /// Nombre de pronostics en mémoire
  int get pronosticsCount => _pronostics.length;

  /// ★ v9.6 : Recréer les pronostics manquants — stratégie intelligente :
  /// - Course déjà en mémoire          → ignorer
  /// - Course manquante, scoreIA > 0   → lire les scores existants
  /// - Course manquante, scoreIA = 0   → recalculer via IaPronosticEngine
  /// N'agit que sur la journée en cours
  Future<int> recreerPronosticsManquants(List<ZtReunion> reunions) async {
    int nbCrees = 0;
    final now = DateTime.now();
    final todayStr = '${now.day.toString().padLeft(2, '0')}'
        '${now.month.toString().padLeft(2, '0')}${now.year}';

    for (final reunion in reunions) {
      final code = reunion.code;
      final numRMatch = RegExp(r'R(\d+)').firstMatch(code);
      final numR = numRMatch != null
          ? int.tryParse(numRMatch.group(1) ?? '1') ?? 1 : 1;

      for (final course in reunion.courses) {
        if (course.partants.isEmpty) continue;

        final dep = course.heureDateTime;
        final dj = dep.day.toString().padLeft(2, '0');
        final dm = dep.month.toString().padLeft(2, '0');

        // ★ Uniquement la journée en cours
        if ('$dj$dm${dep.year}' != todayStr) continue;

        final courseKey = 'R${numR}C${course.numCourse}_$dj$dm${dep.year}';

        // Déjà en mémoire → ignorer
        if (_pronostics.any((p) => p.courseKey == courseKey)) continue;

        // ★ Stratégie : lire ou recalculer selon scoreIA disponible
        List<ZtPartant> partantsClasses;
        Map<String, ScoresCriteres> scoresCriteres = {};

        final scoresExistants = course.partants
            .where((p) => p.scoreIA > 0)
            .toList();

        if (scoresExistants.length >= 3) {
          // Cas 2 : scores déjà calculés à l'affichage → trier par scoreIA desc
          // ★ fix : tri par scoreIA (pas rang) — rang peut être 0 pour tous
          partantsClasses = [...course.partants]
            ..sort((a, b) => b.scoreIA.compareTo(a.scoreIA));
        } else {
          // Cas 3 : scores à 0 → recalculer via IaPronosticEngine
          final result = IaPronosticEngine.analyserCourseAvecCriteres(
            course, poidsOverride: _poids);
          partantsClasses = result.$1;
          scoresCriteres  = result.$2;
          if (partantsClasses.isEmpty) continue;
        }

        final scores = <String, double>{};
        for (final p in partantsClasses) {
          scores[p.numero] = p.scoreIA;
        }

        // Type de pari conseillé
        final scoreConf = partantsClasses.first.scoreIA;
        final score2nd  = partantsClasses.length >= 2
            ? partantsClasses[1].scoreIA : 0.0;
        final ecart12   = (scoreConf - score2nd).abs();
        final estEquil  = ecart12 <= 15 && scoreConf >= 60 && score2nd >= 50;
        final coteTop   = partantsClasses.first.coteDecimale;

        final String typePari;
        if (course.isQuinte) {
          typePari = 'Quinté+';
        } else if (course.isQuarte) {
          typePari = 'Quarté+';
        } else if (estEquil && scoreConf >= _seuils.seuilCoupleGagnant) {
          typePari = 'Couplé Gagnant';
        } else if (estEquil && scoreConf >= _seuils.seuilCouplePlace) {
          typePari = 'Couplé Placé';
        } else if (scoreConf >= _seuils.seuilSimpleGagnant && coteTop <= 8.0) {
          typePari = 'Simple Gagnant';
        } else if (scoreConf >= _seuils.seuilSimpleGagnant) {
          typePari = 'Gagnant+Placé';
        } else if (scoreConf >= _seuils.seuilSimplePlace) {
          typePari = 'Simple Placé';
        } else if (scoreConf >= _seuils.seuilGagnantPlace) {
          // ★ fix : branche seuilGagnantPlace manquante — alignement avec data_refresh_service
          typePari = 'Gagnant+Placé';
        } else if (scoreConf >= _seuils.seuilTierce) {
          typePari = 'Tiercé';
        } else {
          typePari = 'À surveiller';
        }

        // Favori IA = partant avec meilleur scoreIA
        final favoriNum = scores.isEmpty ? null
            : scores.entries.reduce((a, b) => a.value > b.value ? a : b).key;
        final favoriNom = favoriNum != null
            ? course.partants.where((p) => p.numero == favoriNum).firstOrNull?.nom
            : null;

        // Calculer la variance si les scores sont disponibles (Cas 3 recalcul)
        double? varianceRecree;
        if (scores.length >= 3) {
          final vals = scores.values.toList();
          final mean = vals.reduce((a, b) => a + b) / vals.length;
          varianceRecree = vals.map((v) => (v - mean) * (v - mean))
              .reduce((a, b) => a + b) / vals.length;
        }

        // Calculer tauxReussiteAuMoment et precisionIA au moment de la création
        double? tauxRAuMoment;
        if (_precisionParType.containsKey(typePari)) {
          tauxRAuMoment = _precisionParType[typePari]!.tauxReussite;
        }
        final bestScore = scores.values.isEmpty ? 0.0
            : scores.values.reduce((a, b) => a > b ? a : b);
        final precIA = _poids.poidsIndices.calculerPrecision(
          scoreCriteres: bestScore,
          confianceIA:   course.confianceIA,
          tauxReussite:  tauxRAuMoment ?? 50.0,
        );

        _pronostics.insert(0, IaPronostic(
          courseKey:            courseKey,
          nomCourse:            course.nom.isNotEmpty ? course.nom
                                : 'Course ${course.numCourse}',
          hippodrome:           reunion.lieu,
          discipline:           course.type,
          datePronostic:        dep,
          scoresIA:             scores,
          scoresCriteres:       scoresCriteres,
          varianceScores:       varianceRecree,
          confiancePredite:     course.confianceIA,
          typePariConseille:    typePari,
          tauxReussiteAuMoment: tauxRAuMoment,
          precisionIA:          precIA,
          favoriIaNom:          favoriNom,
        ));
        nbCrees++;
      }
    }

    if (nbCrees > 0) {
      await _save();
      notifyListeners();
    }
    return nbCrees;
  }

  IaPronostic? getPronostic(String courseKey) {
    try {
      return _pronostics.firstWhere((p) => p.courseKey == courseKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearHistory() async {
    await _load();
    _pronostics.clear();
    _journal.clear();
    await _save();
    notifyListeners();
  }

  Future<void> resetPoids() async {
    await _load();
    _poids = IaPoidsAdaptatifs();
    await _save();
    notifyListeners();
  }

  // ★ Lot 4 ── Statistiques de compression ─────────────────────────────────
  /// Retourne la taille estimée des données IA en mémoire (pour affichage profil)
  Future<Map<String, dynamic>> statsCompression() async {
    try {
      final prefs     = await SharedPreferences.getInstance();
      final b64Gz     = prefs.getString(_compressionKey) ?? '';
      final rawList   = prefs.getStringList(_pronosticsKey) ?? [];

      final sizeGz    = b64Gz.length;
      final sizeRaw   = rawList.fold(0, (s, e) => s + e.length);
      final ratio     = sizeRaw > 0 && sizeGz > 0
          ? (1 - sizeGz / sizeRaw) * 100 : 0.0;

      return {
        'nbPronostics':    _pronostics.length,
        'sizeGzBytes':     sizeGz,
        'sizeRawBytes':    sizeRaw,
        'ratioCompression': ratio.clamp(0.0, 99.0),
        'isCompressed':    b64Gz.isNotEmpty,
        'nbSansResultat':  _pronostics.where((p) => !p.resultatsReels).length,
        'nbAvecResultat':  _pronostics.where((p) =>  p.resultatsReels).length,
      };
    } catch (_) { return {}; }
  }
}

// ─── Classe interne : agrégat jour/type pour la migration v9.95 ───────────────
class _AgregJour {
  int nb = 0, bon = 0, ord = 0, des = 0;
}

// ─── Classe interne : stats par discipline pour le rapport journalier ─────────
class _TypePariStats {
  final String type;
  int nb = 0, fg = 0, ft3 = 0;
  double totalScore = 0;
  _TypePariStats(this.type);
  void add(int? rang, double score) {
    nb++;
    totalScore += score;
    if (rang != null) {
      if (rang == 1) fg++;
      if (rang <= 3) ft3++;
    }
  }
}

class _DiscStats {
  final String discipline;
  int nb = 0, fg = 0, ft3 = 0, ft5 = 0;
  double totalScore = 0;
  _DiscStats(this.discipline);
  void add(int? rang, double score) {
    nb++;
    totalScore += score;
    if (rang == null) return;
    if (rang == 1) fg++;
    if (rang <= 3) ft3++;
    if (rang <= 5) ft5++;
  }
}

// ─── Résultat de l'analyse journée ────────────────────────────────────────────
class AnalyseJourneeResultat {
  final bool succes;
  final DateTime? dateAnalysee;
  final int nbCoursesAnalysees;    // courses passées traitées (avec ou sans résultat)
  final int nbNouveauxResultats;   // courses avec résultat PMU comparé au pronostic IA
  final int nbPronosticsAjoutes;   // nouveaux pronostics IA créés par l'analyse
  final int nbCoursesEchouees;     // vraies erreurs réseau/parse
  final int nbCoursesFutures;      // courses ignorées car pas encore courues
  final int nbSansResultat;        // courses passées mais résultat PMU pas encore dispo
  final List<String> coursesAnalysees;
  final List<String> erreurs;
  final Map<String, double> poidsApres;
  final int nbMisesAJour;
  final String? messageErreur;
  final RapportJournalier? rapport;

  const AnalyseJourneeResultat({
    required this.succes,
    this.dateAnalysee,
    this.nbCoursesAnalysees = 0,
    this.nbNouveauxResultats = 0,
    this.nbPronosticsAjoutes = 0,
    this.nbCoursesEchouees = 0,
    this.nbCoursesFutures = 0,
    this.nbSansResultat = 0,
    this.coursesAnalysees = const [],
    this.erreurs = const [],
    this.poidsApres = const {},
    this.nbMisesAJour = 0,
    this.messageErreur,
    this.rapport,
  });

  factory AnalyseJourneeResultat.erreur(String msg) => AnalyseJourneeResultat(
    succes: false,
    messageErreur: msg,
  );

  /// Cas "pas encore de données" — pas une vraie erreur, juste vide (première utilisation / soir)
  factory AnalyseJourneeResultat.vide(String msg) => AnalyseJourneeResultat(
    succes: false,
    messageErreur: msg,
    nbCoursesFutures: -1, // sentinelle : -1 = cas "vide/info", pas une vraie erreur
  );

  /// Vrai si c'est un cas "vide/info" (pas une erreur réseau ou logique)
  bool get isVide => !succes && nbCoursesFutures == -1;
}

// ─── Stats cumulatives par type de pari (persistées, toujours à jour) ────────
//
//  Alimentées par chaque `validatePrediction` de l'utilisateur.
//  Stockées dans SharedPreferences (clé ia_stats_types_v1).
//  Représentent le taux de réussite réel de TOUS les paris de l'utilisateur
//  depuis le début, groupés par type.
//
//  Types gérés : Simple Gagnant, Placé, Gagnant+Placé, Couplé Gagnant,
//                Couplé Placé, Tiercé, Quarté+, Quinté+
// ─────────────────────────────────────────────────────────────────────────────

class StatsTypePari {
  final String typePari;
  int nbJoues;    // total de paris de ce type enregistrés par l'utilisateur
  int nbGagnes;   // paris marqués isCorrect = true
  int nbPerdus;   // paris marqués isCorrect = false
  double gainNet; // somme des gainNet de ce type

  StatsTypePari({
    required this.typePari,
    this.nbJoues  = 0,
    this.nbGagnes = 0,
    this.nbPerdus = 0,
    this.gainNet  = 0,
  });

  // Paris en attente (aucun résultat encore)
  int get nbEnAttente => nbJoues - nbGagnes - nbPerdus;

  // Taux de réussite sur les paris résolus seulement
  double get tauxReussite {
    final resolus = nbGagnes + nbPerdus;
    return resolus > 0 ? nbGagnes / resolus * 100 : 0;
  }

  // Emoji représentatif du type de pari
  String get emoji {
    switch (typePari) {
      case 'Simple Gagnant':   return '🥇';
      case 'Simple Placé':     return '🏅';
      case 'Placé':            return '🏅';
      case 'Gagnant+Placé':    return '🎯';
      case 'Couplé Gagnant':   return '🔗';
      case 'Couplé Placé':     return '🔗';
      case 'Couplé Ordre':     return '🔢';
      case 'Couplé Désordre':  return '🔄';
      case 'Tiercé':           return '🥉';
      case 'Tiercé Ordre':     return '🔢';
      case 'Tiercé Désordre':  return '🥉';
      case 'Quarté+':          return '4️⃣';
      case 'Quinté+':          return '5️⃣';
      default:                 return '🎰';
    }
  }

  // Ordre d'affichage logique (du plus simple au plus complexe)
  int get ordreAffichage {
    const ordre = [
      'Simple Gagnant', 'Simple Placé', 'Placé', 'Gagnant+Placé',
      'Couplé Gagnant', 'Couplé Placé', 'Couplé Ordre', 'Couplé Désordre',
      'Tiercé', 'Tiercé Ordre', 'Tiercé Désordre',
      'Quarté+', 'Quinté+',
    ];
    final idx = ordre.indexOf(typePari);
    return idx >= 0 ? idx : 99;
  }

  Map<String, dynamic> toJson() => {
    'tp': typePari,
    'nj': nbJoues,
    'ng': nbGagnes,
    'np': nbPerdus,
    'gn': gainNet,
  };

  factory StatsTypePari.fromJson(Map<String, dynamic> j) => StatsTypePari(
    typePari: j['tp'] as String? ?? '',
    nbJoues:  j['nj'] as int? ?? 0,
    nbGagnes: j['ng'] as int? ?? 0,
    nbPerdus: j['np'] as int? ?? 0,
    gainNet:  (j['gn'] as num?)?.toDouble() ?? 0,
  );
}

// ─── Précision IA réelle (basée sur les vrais résultats PMU) ──────────────────
//
//  LOGIQUE CORRECTE : l'IA produit un classement de chevaux par score (0-100).
//  On mesure 3 niveaux de précision RÉELS depuis les IaPronostic résolus :
//
//   • Niveau 1 "Gagnant"  → le favori IA (score le + haut) arrive 1er
//                           Indicateur pour : Simple Gagnant
//
//   • Niveau 2 "Placé"    → le favori IA arrive dans les 3 premiers
//                           Indicateur pour : Couplé, Tiercé, Gagnant+Placé
//
//   • Niveau 3 "Sélectif" → au moins 4 des 5 premiers IA sont dans le top 5 réel // ★ v10.15
//                           Indicateur pour : Quarté+, Quinté+
//
//  Ces 3 métriques sont cohérentes avec ce que l'IA fait vraiment.
//  Elles alimentent DIRECTEMENT l'ajustement des poids via le gradient :
//   → Si "Gagnant" est faible : booster le critère `cote` (cote révèle le gagnant)
//   → Si "Placé" est faible   : booster `forme` (forme prédit le top3)
//   → Si "Sélectif" est faible: booster `constance` (régularité prédit le top5)
//
//  Stocké dans SharedPreferences (clé ia_precision_v2).
//  Historique glissant 60 jours par niveau.
// ─────────────────────────────────────────────────────────────────────────────

// ─── Précision IA par type de pari (réelle, basée sur conseils IA vs PMU) ────
//
//  Pour chaque type de pari que l'IA conseille (Quinté+, Simple Gagnant, etc.)
//  on mesure combien de fois le conseil était bon selon les règles métier.
//
//  Alimentée automatiquement par analyseJourneeComplete via _mettreAJourPrecisionIA.
// ─────────────────────────────────────────────────────────────────────────────
class StatsPrecisionParType {
  final String typePari;

  // ── Fenêtre glissante 60j (pour l'affichage et l'apprentissage IA) ──────
  int nbTotal;    // nombre total de pronostics IA (60j glissants)
  int nbBons;     // bons conseils (60j)
  int nbOrdre;    // bons en ORDRE EXACT (60j) — Tiercé/Quarté+/Quinté+
  int nbDesordre; // bons en DÉSORDRE (60j)

  // ── Compteurs permanents depuis l'installation ──────────────────────────
  // Jamais effacés, même quand la fenêtre glissante tourne
  int nbTotalAll;    // total depuis l'installation
  int nbBonsAll;     // bons depuis l'installation
  int nbOrdreAll;    // ordre depuis l'installation
  int nbDesordreAll; // désordre depuis l'installation

  // ── Historique complet par jour (toutes dates, jamais tronqué) ──────────
  // {'d': 'YYYY-MM-DD', 'nb': N, 'bon': N, 'ord': N, 'des': N}
  final List<Map<String, dynamic>> historiqueComplet;

  // ── Fenêtre glissante 60j (vue filtrée de historiqueComplet) ─────────────
  final List<Map<String, dynamic>> historique;

  StatsPrecisionParType({
    required this.typePari,
    this.nbTotal       = 0,
    this.nbBons        = 0,
    this.nbOrdre       = 0,
    this.nbDesordre    = 0,
    this.nbTotalAll    = 0,
    this.nbBonsAll     = 0,
    this.nbOrdreAll    = 0,
    this.nbDesordreAll = 0,
    List<Map<String, dynamic>>? historique,
    List<Map<String, dynamic>>? historiqueComplet,
  })  : historique        = historique ?? [],
        historiqueComplet = historiqueComplet ?? [];

  /// Taux de réussite fenêtre 60j (pour l'IA)
  double get tauxReussite => nbTotal > 0 ? nbBons / nbTotal * 100 : 0;

  /// Taux de réussite global depuis l'installation
  double get tauxReussiteAll => nbTotalAll > 0 ? nbBonsAll / nbTotalAll * 100 : 0;

  /// Stats filtrées par période — retourne {nb, bons, ordre, desordre}
  Map<String, int> statsPourPeriode(DateTime debut, DateTime fin) {
    int nb = 0, bons = 0, ord = 0, des = 0;
    for (final e in historiqueComplet) {
      final ds = e['d'] as String? ?? '';
      if (ds.isEmpty) continue;
      final parts = ds.split('-');
      if (parts.length != 3) continue;
      final d = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      if (d.isBefore(debut) || d.isAfter(fin)) continue;
      nb   += e['nb']  as int? ?? 0;
      bons += e['bon'] as int? ?? 0;
      ord  += e['ord'] as int? ?? 0;
      des  += e['des'] as int? ?? 0;
    }
    return {'nb': nb, 'bons': bons, 'ordre': ord, 'desordre': des};
  }

  /// Liste des mois disponibles dans l'historique complet
  List<String> get moisDisponibles {
    final mois = <String>{};
    for (final e in historiqueComplet) {
      final ds = e['d'] as String? ?? '';
      if (ds.length >= 7) mois.add(ds.substring(0, 7)); // 'YYYY-MM'
    }
    final list = mois.toList()..sort((a, b) => b.compareTo(a)); // plus récent en premier
    return list;
  }

  /// Liste des jours disponibles dans l'historique complet (format 'YYYY-MM-DD')
  /// Utilisé pour les boutons de filtre par jour dans l'UI
  List<String> get joursDisponibles {
    final jours = <String>{};
    for (final e in historiqueComplet) {
      final ds = e['d'] as String? ?? '';
      if (ds.length == 10) jours.add(ds); // 'YYYY-MM-DD'
    }
    final list = jours.toList()..sort((a, b) => b.compareTo(a)); // plus récent en premier
    return list;
  }

  /// Tendance sur les 7 derniers jours (depuis historiqueComplet)
  double? get tendance7j {
    final sorted = [...historiqueComplet]
      ..sort((a, b) => (b['d'] as String).compareTo(a['d'] as String));
    if (sorted.length < 4) return null;
    final recent = sorted.take(3).toList();
    final old    = sorted.skip(3).take(4).toList();
    double moyR = 0, moyO = 0;
    for (final e in recent) {
      final nb = e['nb'] as int? ?? 0;
      if (nb > 0) moyR += (e['bon'] as int? ?? 0) / nb * 100;
    }
    for (final e in old) {
      final nb = e['nb'] as int? ?? 0;
      if (nb > 0) moyO += (e['bon'] as int? ?? 0) / nb * 100;
    }
    moyR /= math.max(1, recent.length);
    moyO /= math.max(1, old.length);
    return moyR - moyO;
  }

  /// Ordre d'affichage logique (du plus simple au plus complexe)
  int get ordreAffichage {
    const ordre = [
      'Simple Gagnant', 'Simple Placé', 'Gagnant+Placé',
      'Couplé Gagnant', 'Couplé Placé',
      'Tiercé', 'Quarté+', 'Quinté+', 'À surveiller', 'Inconnu'
    ];
    final idx = ordre.indexOf(typePari);
    return idx >= 0 ? idx : 99;
  }

  /// Emoji représentatif du type de pari
  String get emoji {
    switch (typePari) {
      case 'Simple Gagnant':  return '🥇';
      case 'Simple Placé':    return '🏅';
      case 'Gagnant+Placé':   return '🎖️';
      case 'Couplé Gagnant':  return '🔗';
      case 'Couplé Placé':    return '🔀';
      case 'Tiercé':          return '🎯';
      case 'Quarté+':         return '🃏';
      case 'Quinté+':         return '⭐';
      case 'À surveiller':    return '👁️';
      default:                return '📊';
    }
  }

  /// Enregistre une journée d'analyse
  /// - historiqueComplet : jamais tronqué (mémoire permanente)
  /// - historique        : fenêtre 60j glissants (pour l'IA)
  void ajouterJournee(DateTime date, int nb, int bons, {int ordre = 0, int desordre = 0}) {
    if (nb == 0) return;
    final dateStr = '${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}';

    // ★ v9.90 : FUSION au lieu d'écrasement — les résultats PMU arrivent
    // course par course dans la journée. Si on écrase, les résultats de la
    // passe précédente disparaissent. On cumule donc avec l'existant du jour.
    final existant = historiqueComplet.firstWhere(
      (e) => e['d'] == dateStr,
      orElse: () => <String, dynamic>{},
    );
    final entry = {
      'd':   dateStr,
      'nb':  nb  + (existant['nb']  as int? ?? 0),
      'bon': bons + (existant['bon'] as int? ?? 0),
      'ord': ordre + (existant['ord'] as int? ?? 0),
      'des': desordre + (existant['des'] as int? ?? 0),
    };

    // ── 1. Historique complet (permanent, jamais supprimé) ─────────────────
    historiqueComplet.removeWhere((e) => e['d'] == dateStr);
    historiqueComplet.add(entry);
    historiqueComplet.sort((a, b) => (a['d'] as String).compareTo(b['d'] as String));

    // ── 2. Mise à jour compteurs permanents (cumulatif depuis installation) ─
    nbTotalAll    = 0; nbBonsAll    = 0;
    nbOrdreAll    = 0; nbDesordreAll = 0;
    for (final e in historiqueComplet) {
      nbTotalAll    += e['nb']  as int? ?? 0;
      nbBonsAll     += e['bon'] as int? ?? 0;
      nbOrdreAll    += e['ord'] as int? ?? 0;
      nbDesordreAll += e['des'] as int? ?? 0;
    }

    // ── 3. Fenêtre glissante 60j (pour apprentissage IA) ──────────────────
    historique.removeWhere((e) => e['d'] == dateStr);
    historique.add(entry);
    if (historique.length > 60) {
      historique.sort((a, b) => (a['d'] as String).compareTo(b['d'] as String));
      historique.removeRange(0, historique.length - 60);
    }
    // Recalculer fenêtre 60j
    nbTotal = 0; nbBons = 0; nbOrdre = 0; nbDesordre = 0;
    for (final e in historique) {
      nbTotal    += e['nb']  as int? ?? 0;
      nbBons     += e['bon'] as int? ?? 0;
      nbOrdre    += e['ord'] as int? ?? 0;
      nbDesordre += e['des'] as int? ?? 0;
    }
  }

  Map<String, dynamic> toJson() => {
    'tp':   typePari,
    'nb':   nbTotal,
    'bn':   nbBons,
    'ord':  nbOrdre,
    'des':  nbDesordre,
    'nba':  nbTotalAll,
    'bna':  nbBonsAll,
    'orda': nbOrdreAll,
    'desa': nbDesordreAll,
    'h':    historique,
    'hc':   historiqueComplet,
  };

  factory StatsPrecisionParType.fromJson(Map<String, dynamic> j) {
    final hist  = ((j['h']  as List<dynamic>?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final histC = ((j['hc'] as List<dynamic>?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map)).toList();
    // Rétrocompat : si historiqueComplet vide mais historique présent, on recopie
    final hcFinal = histC.isNotEmpty ? histC : [...hist];
    final s = StatsPrecisionParType(
      typePari:          j['tp']   as String? ?? 'Inconnu',
      nbTotal:           j['nb']   as int? ?? 0,
      nbBons:            j['bn']   as int? ?? 0,
      nbOrdre:           j['ord']  as int? ?? 0,
      nbDesordre:        j['des']  as int? ?? 0,
      nbTotalAll:        j['nba']  as int? ?? 0,
      nbBonsAll:         j['bna']  as int? ?? 0,
      nbOrdreAll:        j['orda'] as int? ?? 0,
      nbDesordreAll:     j['desa'] as int? ?? 0,
      historique:        hist,
      historiqueComplet: hcFinal,
    );
    // Rétrocompat : si compteurs All à 0 mais historique présent, recalculer
    if (s.nbTotalAll == 0 && hcFinal.isNotEmpty) {
      for (final e in hcFinal) {
        s.nbTotalAll    += e['nb']  as int? ?? 0;
        s.nbBonsAll     += e['bon'] as int? ?? 0;
        s.nbOrdreAll    += e['ord'] as int? ?? 0;
        s.nbDesordreAll += e['des'] as int? ?? 0;
      }
    }
    return s;
  }
}

// ─── Seuils de confiance adaptatifs ──────────────────────────────────────────
//
//  Ces seuils remplacent les seuils hardcodés dans best_bet_screen.dart.
//  L'IA les ajuste automatiquement après chaque analyse de la journée :
//
//   • Si un type de pari a un mauvais taux de réussite → seuil monte
//     (l'IA sera plus exigeante avant de proposer ce pari)
//   • Si un type de pari a un bon taux de réussite → seuil peut descendre
//     (l'IA peut proposer ce pari un peu plus facilement)
//
//  Limites :
//   • Plage autorisée par type : défaut ± 15 points max
//   • Le seuil ne peut pas sortir de la plage absolue [25, 95]
// ─────────────────────────────────────────────────────────────────────────────
class SeuilsConfianceAdaptatifs {
  // Seuils par défaut (identiques aux seuils codés dans best_bet_screen)
  // Correspondent au scoreConf minimum pour conseiller ce type de pari
  double seuilSimpleGagnant;   // défaut 80 (+ cote ≤ 8)
  double seuilGagnantPlace;    // défaut 80 (+ cote > 8) ou 50
  double seuilSimplePlace;     // défaut 65
  double seuilCoupleGagnant;   // défaut 75 (+ équilibre)
  double seuilCouplePlace;     // défaut 60 (+ équilibre)
  double seuilTierce;          // défaut 35
  double seuilQuarte;          // défaut 80 (course Quarté officielle)
  double seuilQuinte;          // défaut 0  (course Quinté officielle → toujours)

  SeuilsConfianceAdaptatifs({
    this.seuilSimpleGagnant  = 80.0,
    this.seuilGagnantPlace   = 50.0,
    this.seuilSimplePlace    = 65.0,
    this.seuilCoupleGagnant  = 75.0,
    this.seuilCouplePlace    = 60.0,
    this.seuilTierce         = 35.0,
    this.seuilQuarte         = 80.0,
    this.seuilQuinte         = 0.0,
  });

  /// Ajuste le seuil pour un type de pari.
  /// delta positif → seuil monte (plus sélectif)
  /// delta négatif → seuil descend (moins sélectif)
  void ajusterSeuil(String typePari, double delta) {
    // Limiter la variation par appel à ±2.0 points (stabilité)
    final d = delta.clamp(-2.0, 2.0);
    switch (typePari) {
      case 'Simple Gagnant':
        seuilSimpleGagnant = (seuilSimpleGagnant + d).clamp(65.0, 92.0);
        break;
      case 'Gagnant+Placé':
        seuilGagnantPlace  = (seuilGagnantPlace  + d).clamp(40.0, 75.0);
        break;
      case 'Simple Placé':
        seuilSimplePlace   = (seuilSimplePlace   + d).clamp(50.0, 80.0);
        break;
      case 'Couplé Gagnant':
        seuilCoupleGagnant = (seuilCoupleGagnant + d).clamp(60.0, 88.0);
        break;
      case 'Couplé Placé':
        seuilCouplePlace   = (seuilCouplePlace   + d).clamp(45.0, 78.0);
        break;
      case 'Tiercé':
        seuilTierce        = (seuilTierce        + d).clamp(25.0, 55.0);
        break;
      case 'Quarté+':
        seuilQuarte        = (seuilQuarte        + d).clamp(65.0, 92.0);
        break;
      // Quinté+ : toujours conseillé quand course officielle → pas de seuil à ajuster
      default:
        break;
    }
  }

  Map<String, dynamic> toJson() => {
    'sg':  seuilSimpleGagnant,
    'gp':  seuilGagnantPlace,
    'sp':  seuilSimplePlace,
    'cg':  seuilCoupleGagnant,
    'cp':  seuilCouplePlace,
    'ti':  seuilTierce,
    'qa':  seuilQuarte,
    'qi':  seuilQuinte,
  };

  factory SeuilsConfianceAdaptatifs.fromJson(Map<String, dynamic> j) {
    return SeuilsConfianceAdaptatifs(
      seuilSimpleGagnant : (j['sg'] as num?)?.toDouble() ?? 80.0,
      seuilGagnantPlace  : (j['gp'] as num?)?.toDouble() ?? 50.0,
      seuilSimplePlace   : (j['sp'] as num?)?.toDouble() ?? 65.0,
      seuilCoupleGagnant : (j['cg'] as num?)?.toDouble() ?? 75.0,
      seuilCouplePlace   : (j['cp'] as num?)?.toDouble() ?? 60.0,
      seuilTierce        : (j['ti'] as num?)?.toDouble() ?? 35.0,
      seuilQuarte        : (j['qa'] as num?)?.toDouble() ?? 80.0,
      seuilQuinte        : (j['qi'] as num?)?.toDouble() ??  0.0,
    );
  }
}

// ─── Rapport journalier complet (persisté, glissant 60 jours) ─────────────────
//
//  Calculé à chaque "Analyse journée" depuis les IaPronostic du jour.
//  Stocké dans SharedPreferences (clé ia_rapports_v1), max 60 entrées.
//
//  Contient :
//   • Taux global de réussite du favori IA (gagnant / top3 / top5)
//   • Taux par discipline (Trot Attelé / Trot Monté / Plat / Obstacle)
//   • Score moyen de performance IA
//   • Nb courses analysées / avec résultat
//   • Nb mises à jour de poids (gradient)
//   • Note de qualité de la journée (A → F)
// ─────────────────────────────────────────────────────────────────────────────

class StatsDisciplineJour {
  final String discipline;
  final int nbCourses;
  final int favoriGagnant;
  final int favoriTop3;
  final int favoriTop5;
  final double scoreMoyen;

  const StatsDisciplineJour({
    required this.discipline,
    required this.nbCourses,
    required this.favoriGagnant,
    required this.favoriTop3,
    required this.favoriTop5,
    required this.scoreMoyen,
  });

  double get tauxGagnant => nbCourses > 0 ? favoriGagnant / nbCourses * 100 : 0;
  double get tauxTop3    => nbCourses > 0 ? favoriTop3    / nbCourses * 100 : 0;
  double get tauxTop5    => nbCourses > 0 ? favoriTop5    / nbCourses * 100 : 0;

  Map<String, dynamic> toJson() => {
    'disc': discipline,
    'nb': nbCourses,
    'fg': favoriGagnant,
    'ft3': favoriTop3,
    'ft5': favoriTop5,
    'sm': scoreMoyen,
  };

  factory StatsDisciplineJour.fromJson(Map<String, dynamic> j) => StatsDisciplineJour(
    discipline:    j['disc'] as String? ?? '',
    nbCourses:     j['nb']   as int? ?? 0,
    favoriGagnant: j['fg']   as int? ?? 0,
    favoriTop3:    j['ft3']  as int? ?? 0,
    favoriTop5:    j['ft5']  as int? ?? 0,
    scoreMoyen:    (j['sm']  as num?)?.toDouble() ?? 0,
  );
}

class RapportJournalier {
  final DateTime date;
  final int nbCoursesAnalysees;
  final int nbAvecResultat;
  final int nbPronosticsAjoutes;
  // ── Stats globales ──────────────────────────────────────────────────────────
  final int favoriGagnant;   // favori IA classé 1er
  final int favoriTop3;      // favori IA dans les 3 premiers
  final int favoriTop5;      // favori IA dans les 5 premiers
  final int top3Correct2sur3; // au moins 2 des 3 sélectionnés IA dans top3 réel
  final int top5Correct4sur5; // ★ v10.14 : au moins 4 des 5 sélectionnés IA dans top5 réel
  final double scoreMoyenJour;
  // ── Stats par discipline ────────────────────────────────────────────────────
  final List<StatsDisciplineJour> parDiscipline;
  // ── Infos apprentissage ─────────────────────────────────────────────────────
  final int nbMisesAJourPoids;
  final Map<String, double> poidsApres;
  // ── Éventuelles erreurs ──────────────────────────────────────────────────────
  final int nbCoursesEchouees;
  final String? noteJournee; // "Excellente", "Bonne", "Moyenne", "Faible"
  // ★ v9.6 : Détail par course + stats par type + heure analyse
  final DateTime? heureAnalyse;
  final List<CourseDetailRapport> coursesDetail;
  final List<StatsTypePariJour> parTypePari;

  const RapportJournalier({
    required this.date,
    required this.nbCoursesAnalysees,
    required this.nbAvecResultat,
    required this.nbPronosticsAjoutes,
    required this.favoriGagnant,
    required this.favoriTop3,
    required this.favoriTop5,
    required this.top3Correct2sur3,
    required this.top5Correct4sur5,
    required this.scoreMoyenJour,
    required this.parDiscipline,
    required this.nbMisesAJourPoids,
    required this.poidsApres,
    required this.nbCoursesEchouees,
    this.noteJournee,
    this.heureAnalyse,
    this.coursesDetail = const [],
    this.parTypePari   = const [],
  });

  // ── Taux calculés ────────────────────────────────────────────────────────────
  double get tauxGagnant     => nbAvecResultat > 0 ? favoriGagnant   / nbAvecResultat * 100 : 0;
  double get tauxTop3        => nbAvecResultat > 0 ? favoriTop3      / nbAvecResultat * 100 : 0;
  double get tauxTop5        => nbAvecResultat > 0 ? favoriTop5      / nbAvecResultat * 100 : 0;
  double get tauxTop3Correct => nbAvecResultat > 0 ? top3Correct2sur3 / nbAvecResultat * 100 : 0;
  double get tauxTop5Correct => nbAvecResultat > 0 ? top5Correct4sur5 / nbAvecResultat * 100 : 0;

  // ── Note de qualité automatique ──────────────────────────────────────────────
  static String calculerNote(double tauxGagnant, double scoreMoyen) {
    final score = tauxGagnant * 0.6 + scoreMoyen * 0.4;
    if (score >= 65) return 'Excellente ⭐';
    if (score >= 48) return 'Bonne 👍';
    if (score >= 32) return 'Moyenne ➖';
    return 'Faible ⚠️';
  }

  // ── Sérialisation ────────────────────────────────────────────────────────────
  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'nb': nbCoursesAnalysees,
    'nbR': nbAvecResultat,
    'nbP': nbPronosticsAjoutes,
    'fg': favoriGagnant,
    'ft3': favoriTop3,
    'ft5': favoriTop5,
    't3c': top3Correct2sur3,
    't5c': top5Correct4sur5,
    'sm': scoreMoyenJour,
    'disc': parDiscipline.map((d) => d.toJson()).toList(),
    'mpu': nbMisesAJourPoids,
    'poids': poidsApres,
    'nbE': nbCoursesEchouees,
    'note': noteJournee,
    'hre':  heureAnalyse?.toIso8601String(),
    'cdet': coursesDetail.map((c) => c.toJson()).toList(),
    'ptj':  parTypePari.map((s) => s.toJson()).toList(),
  };

  factory RapportJournalier.fromJson(Map<String, dynamic> j) => RapportJournalier(
    date:                 DateTime.parse(j['date'] as String),
    nbCoursesAnalysees:   j['nb']  as int? ?? 0,
    nbAvecResultat:       j['nbR'] as int? ?? 0,
    nbPronosticsAjoutes:  j['nbP'] as int? ?? 0,
    favoriGagnant:        j['fg']  as int? ?? 0,
    favoriTop3:           j['ft3'] as int? ?? 0,
    favoriTop5:           j['ft5'] as int? ?? 0,
    top3Correct2sur3:     j['t3c'] as int? ?? 0,
    top5Correct4sur5:     j['t5c'] as int? ?? 0,
    scoreMoyenJour:       (j['sm'] as num?)?.toDouble() ?? 0,
    parDiscipline:        ((j['disc'] as List<dynamic>?) ?? [])
        .map((e) => StatsDisciplineJour.fromJson(e as Map<String, dynamic>))
        .toList(),
    nbMisesAJourPoids:    j['mpu'] as int? ?? 0,
    poidsApres:           Map<String, double>.from(
        ((j['poids'] as Map<String, dynamic>?) ?? {})
            .map((k, v) => MapEntry(k, (v as num).toDouble()))),
    nbCoursesEchouees:    j['nbE'] as int? ?? 0,
    noteJournee:          j['note'] as String?,
    heureAnalyse:         j['hre'] != null
        ? DateTime.tryParse(j['hre'] as String) : null,
    coursesDetail:        ((j['cdet'] as List<dynamic>?) ?? [])
        .map((e) => CourseDetailRapport.fromJson(e as Map<String, dynamic>))
        .toList(),
    parTypePari:          ((j['ptj'] as List<dynamic>?) ?? [])
        .map((e) => StatsTypePariJour.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

}

// ── Extension IaMemoryService : méthodes rapport hebdo ★ v9.87 ───────────────
extension IaMemoryServiceRapportHebdo on IaMemoryService {
  /// Calcule un bilan sur la semaine en cours depuis les rapports journaliers.
  /// Retourne null si aucun rapport disponible cette semaine.
  /// ★ Fix v9.94 : seuil abaissé à 1 rapport (était < 2 → bilan invisible
  ///   en début de semaine ou quand un seul jour a été analysé).
  Map<String, dynamic>? calculerRapportHebdo() {
    final maintenant = DateTime.now();
    final lundi = maintenant.subtract(Duration(days: maintenant.weekday - 1));
    final debutSemaine = DateTime(lundi.year, lundi.month, lundi.day);

    // ★ Fix v9.94 : exclure les rapports déjà archivés dans un BilanSemaine
    // pour éviter le doublon avec les semaines passées.
    final archivesLundis = bilansSemaine.map((bs) => bs.lundi).toSet();
    final rapportsSemaine = rapports.where((r) {
      if (r.date.isBefore(debutSemaine)) return false;
      final rLundi = DateTime(r.date.year, r.date.month, r.date.day)
          .subtract(Duration(days: r.date.weekday - 1));
      return !archivesLundis.contains(rLundi);
    }).toList();

    if (rapportsSemaine.isEmpty) return null;

    int totalCourses   = 0;
    int totalResultats = 0;
    int totalGagnant   = 0;
    int totalTop3      = 0;
    double totalScore  = 0;
    final Map<String, int>    discCount   = {};
    final Map<String, int>    discGagnant = {};
    String meilleureNote = '';
    double meilleureNotePoids = -1;

    for (final r in rapportsSemaine) {
      totalCourses   += r.nbCoursesAnalysees;
      totalResultats += r.nbAvecResultat;
      totalGagnant   += r.favoriGagnant;
      totalTop3      += r.favoriTop3;
      totalScore     += r.scoreMoyenJour;
      for (final d in r.parDiscipline) {
        discCount[d.discipline]   = (discCount[d.discipline]   ?? 0) + d.nbCourses;
        discGagnant[d.discipline] = (discGagnant[d.discipline] ?? 0) + d.favoriGagnant;
      }
      final poids = r.noteJournee?.contains('Excellente') == true ? 3
                  : r.noteJournee?.contains('Bonne')      == true ? 2
                  : r.noteJournee?.contains('Moyenne')    == true ? 1
                  : 0;
      if (poids > meilleureNotePoids) {
        meilleureNotePoids = poids.toDouble();
        meilleureNote = r.noteJournee ?? '';
      }
    }

    final tauxGagnant = totalResultats > 0
        ? (totalGagnant / totalResultats * 100) : 0.0;
    final tauxTop3    = totalResultats > 0
        ? (totalTop3    / totalResultats * 100) : 0.0;
    final scoreMoyen  = rapportsSemaine.isNotEmpty
        ? (totalScore / rapportsSemaine.length) : 0.0;

    String meilleureDisc = '';
    double meilleurTaux  = -1;
    discCount.forEach((disc, nb) {
      if (nb >= 3) {
        final t = (discGagnant[disc] ?? 0) / nb * 100;
        if (t > meilleurTaux) { meilleurTaux = t; meilleureDisc = disc; }
      }
    });

    Map<String, double> evolutionPoids = {};
    if (rapportsSemaine.length >= 2) {
      final premier = rapportsSemaine.first;
      final dernier = rapportsSemaine.last;
      for (final k in dernier.poidsApres.keys) {
        final avant  = premier.poidsApres[k] ?? 0.0;
        final apres  = dernier.poidsApres[k] ?? 0.0;
        evolutionPoids[k] = apres - avant;
      }
    }

    return {
      'semaine':         '${debutSemaine.day.toString().padLeft(2,'0')}/${debutSemaine.month.toString().padLeft(2,'0')}',
      'nbJours':         rapportsSemaine.length,
      'totalCourses':    totalCourses,
      'totalResultats':  totalResultats,
      'totalGagnant':    totalGagnant,
      'totalTop3':       totalTop3,
      'tauxGagnant':     tauxGagnant,
      'tauxTop3':        tauxTop3,
      'scoreMoyen':      scoreMoyen,
      'meilleureDisc':   meilleureDisc,
      'meilleurTaux':    meilleurTaux,
      'meilleureNote':   meilleureNote,
      'evolutionPoids':  evolutionPoids,
      'dateGenere':      maintenant.toIso8601String(),
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  ★ v10.25 — Structures de données pour le Calendrier des performances
// ═══════════════════════════════════════════════════════════════════════════

/// Palier de couleur du calendrier — basé sur typePariConseille (pas "favori 1er")
enum PalierCalendrier {
  or,       // ≥60% ET ≥3 courses  → dorée  🥇
  vert,     // ≥40%                → vert foncé
  jaune,    // ≥25%                → jaune/ambre
  orange,   // ≥10% (≥1 bon)      → orange
  rouge,    // courses mais 0 bon  → rouge
  gris,     // aucune course       → gris neutre
}

/// Données agrégées pour une journée du calendrier
class DonneeJourCalendrier {
  final int                  jour;
  final int                  nbCourses;
  final int                  nbBons;
  final int                  nbOrdre;
  final int                  nbDesordre;
  final PalierCalendrier     palier;
  final List<IaPronostic>    pronostics; // pronostics gagnants du jour

  const DonneeJourCalendrier({
    required this.jour,
    required this.nbCourses,
    required this.nbBons,
    required this.nbOrdre,
    required this.nbDesordre,
    required this.palier,
    required this.pronostics,
  });

  double get taux => nbCourses > 0 ? nbBons / nbCourses : 0.0;
}

/// Agrégateur interne (usage privé dans donneesCalendrierJour)
class _AgregJourCal {
  int                nbCourses  = 0;
  int                nbBons     = 0;
  int                nbOrdre    = 0;
  int                nbDesordre = 0;
  List<IaPronostic>  pronostics = [];
}