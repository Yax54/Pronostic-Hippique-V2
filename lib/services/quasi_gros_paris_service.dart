// ═══════════════════════════════════════════════════════════════════════════
//  QuasiGrosParisService — Détection, stockage, helpers v10.74
//
//  Clé SharedPreferences : 'ia_quasi_gros_paris_v1'
//  Deux sous-clés JSON :
//    'signaux'       → List<GrosPariSurveiller>  (signaux avant course)
//    'quasiGagnants' → List<QuasiGagnant>        (résultats archivés)
//
//  Ne modifie JAMAIS : apprentissage IA, poids, premium officiel,
//  streaks, taux officiels, ROI, calendrier principal.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:math' show min;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/quasi_gros_paris_models.dart';
import '../models/zt_models.dart';
import '../widgets/arrivee_reelle_widget.dart' show buildCourseKey;
import '../services/ia_memory_models.dart' show IaPronostic;

export '../models/quasi_gros_paris_models.dart'
    show
        TypeGrosPari,
        SourceQuasiGagnant,
        NiveauFiabiliteGrosPari,
        couleurNiveau,
        ChevalScoreIA,
        ComparaisonCourseIA,
        comparerCourseIA,
        GrosPariSurveiller,
        QuasiGagnant;

class QuasiGrosParisService {
  QuasiGrosParisService._();
  static final instance = QuasiGrosParisService._();

  static const String storageKey = 'ia_quasi_gros_paris_v1';

  // ─── Données en mémoire ────────────────────────────────────────────────
  final List<GrosPariSurveiller> _signaux       = [];
  final List<QuasiGagnant>       _quasiGagnants = [];

  bool _charge = false;

  List<GrosPariSurveiller> get signaux       => List.unmodifiable(_signaux);
  List<QuasiGagnant>       get quasiGagnants => List.unmodifiable(_quasiGagnants);

  // ══════════════════════════════════════════════════════════════════════
  //  HELPERS STATIQUES
  // ══════════════════════════════════════════════════════════════════════

  static int nbChevauxPourType(TypeGrosPari type) {
    switch (type) {
      case TypeGrosPari.tierce: return 3;
      case TypeGrosPari.quarte: return 4;
      case TypeGrosPari.quinte: return 5;
    }
  }

  static int nbQuasiRequis(TypeGrosPari type) {
    switch (type) {
      case TypeGrosPari.tierce: return 2;
      case TypeGrosPari.quarte: return 3;
      case TypeGrosPari.quinte: return 4;
    }
  }

  static String labelType(TypeGrosPari type) {
    switch (type) {
      case TypeGrosPari.tierce: return 'Tiercé';
      case TypeGrosPari.quarte: return 'Quarté+';
      case TypeGrosPari.quinte: return 'Quinté+';
    }
  }

  static NiveauFiabiliteGrosPari niveauDepuisFiabilite(double f) {
    if (f >= 80) return NiveauFiabiliteGrosPari.fort;
    if (f >= 65) return NiveauFiabiliteGrosPari.surveiller;
    if (f >= 50) return NiveauFiabiliteGrosPari.speculatif;
    return NiveauFiabiliteGrosPari.eviter;
  }

  static Color couleurFiabilite(NiveauFiabiliteGrosPari niveau) =>
      couleurNiveau(niveau);

  static String explicationGrosPari(GrosPariSurveiller signal) {
    final label = labelType(signal.type);
    final nb    = nbChevauxPourType(signal.type);
    return "L'IA détecte $nb chevaux nettement au-dessus du reste pour un $label. "
        "L'écart avec le cheval suivant est de "
        "+${signal.ecartAvecSuivant.toStringAsFixed(1)} points, "
        "ce qui crée un signal intéressant mais spéculatif.";
  }

  // ══════════════════════════════════════════════════════════════════════
  //  PERSISTENCE
  // ══════════════════════════════════════════════════════════════════════

  Future<void> charger() async {
    if (_charge) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(storageKey);
      if (raw != null && raw.isNotEmpty) {
        final map = json.decode(raw) as Map<String, dynamic>;

        _signaux.clear();
        for (final item in (map['signaux'] as List? ?? [])) {
          try {
            _signaux.add(GrosPariSurveiller.fromJson(item as Map<String, dynamic>));
          } catch (e) {
            if (kDebugMode) debugPrint('[QuasiGros] signal corrompu ignoré: $e');
          }
        }

        _quasiGagnants.clear();
        for (final item in (map['quasiGagnants'] as List? ?? [])) {
          try {
            _quasiGagnants.add(QuasiGagnant.fromJson(item as Map<String, dynamic>));
          } catch (e) {
            if (kDebugMode) debugPrint('[QuasiGros] quasi-gagnant corrompu ignoré: $e');
          }
        }

        if (kDebugMode) {
          debugPrint('[QuasiGros] Chargé : ${_signaux.length} signaux, '
              '${_quasiGagnants.length} quasi-gagnants');
        }
      }
      _charge = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[QuasiGros] Erreur chargement (ignoré): $e');
      _charge = true; // ne jamais bloquer
    }
  }

  Future<void> _sauvegarder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = {
        'signaux':       _signaux.map((s) => s.toJson()).toList(),
        'quasiGagnants': _quasiGagnants.map((q) => q.toJson()).toList(),
      };
      await prefs.setString(storageKey, json.encode(map));
    } catch (e) {
      if (kDebugMode) debugPrint('[QuasiGros] Erreur sauvegarde: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  //  DÉTECTION — signal avant course (Best Bet)
  // ══════════════════════════════════════════════════════════════════════

  /// Détecte si une [course] correspond à un signal "Gros pari à surveiller"
  /// pour le [type] demandé. Retourne null si seuils non atteints.
  GrosPariSurveiller? detecterGrosPariPourCourse({
    required ZtCourse  course,
    required ZtReunion reunion,
    required TypeGrosPari type,
  }) {
    final nb       = nbChevauxPourType(type);
    final partants = [...course.partants]
      ..sort((a, b) => b.scoreIA.compareTo(a.scoreIA));

    if (partants.length <= nb) return null;

    final selection        = partants.take(nb).toList();
    final suivant          = partants[nb];
    final scoreMinSelection = selection.map((p) => p.scoreIA).reduce(min);
    final ecart            = scoreMinSelection - suivant.scoreIA;

    // Seuils prudents
    const seuilScoreMin = 65.0;
    const seuilEcart    = 10.0;

    if (scoreMinSelection < seuilScoreMin) return null;
    if (ecart < seuilEcart) return null;

    final scoreMoyen = selection.map((p) => p.scoreIA).reduce((a, b) => a + b) /
        selection.length;
    final fiabilite  = ((scoreMoyen * 0.7) + (ecart * 2.0)).clamp(0.0, 100.0);
    final niveau     = niveauDepuisFiabilite(fiabilite);

    final courseKey = buildCourseKey(
      reunionCode: reunion.code,
      numCourse:   course.numCourse,
      dateStr:     course.dateStr,
    );

    // ★ v10.74 : snapshot classement IA complet au moment du signal
    // Tous les partants triés par score décroissant, rang 1 = meilleur
    final classementComplet = <ChevalScoreIA>[];
    for (int i = 0; i < partants.length; i++) {
      final p = partants[i];
      classementComplet.add(ChevalScoreIA(
        numero: p.numero,
        nom:    p.nom,
        score:  p.scoreIA,
        rangIA: i + 1,
      ));
    }

    return GrosPariSurveiller(
      id:                   '${courseKey}_${type.name}',
      courseKey:            courseKey,
      dateCourse:           course.heureDateTime,
      nomCourse:            course.nom,
      hippodrome:           reunion.lieu,
      heure:                course.heure,
      discipline:           reunion.discipline,
      type:                 type,
      numeros:              selection.map((p) => p.numero).toList(),
      scoresParNumero:      {for (final p in selection) p.numero: p.scoreIA},
      scoreMoyenSelection:  scoreMoyen,
      ecartAvecSuivant:     ecart,
      fiabilite:            fiabilite,
      niveau:               niveau,
      createdAt:            DateTime.now(),
      classementCompletIA:  classementComplet, // ★ v10.74
    );
  }

  /// Calcule tous les signaux du jour pour toutes les réunions données.
  /// Déduplication : une même course garde au plus 1 signal
  /// (priorité Quinté+ > Quarté+ > Tiercé).
  List<GrosPariSurveiller> calculerSignauxDuJour(List<ZtReunion> reunions) {
    final Map<String, GrosPariSurveiller> meilleurParCourse = {};

    for (final reunion in reunions) {
      for (final course in reunion.courses) {
        // Priorité décroissante : Quinté+ > Quarté+ > Tiercé
        for (final type in [TypeGrosPari.quinte, TypeGrosPari.quarte, TypeGrosPari.tierce]) {
          if (type == TypeGrosPari.quinte && !course.isQuinte) continue;
          if (type == TypeGrosPari.quarte && !course.isQuarte) continue;

          final signal = detecterGrosPariPourCourse(
            course:  course,
            reunion: reunion,
            type:    type,
          );
          if (signal != null) {
            final existing = meilleurParCourse[signal.courseKey];
            if (existing == null ||
                nbChevauxPourType(signal.type) > nbChevauxPourType(existing.type)) {
              meilleurParCourse[signal.courseKey] = signal;
            }
            break; // 1 seul signal par course (meilleur niveau trouvé en premier)
          }
        }
      }
    }

    final resultats = meilleurParCourse.values.toList()
      ..sort((a, b) => b.fiabilite.compareTo(a.fiabilite));

    if (kDebugMode) debugPrint('[QuasiGros] Signaux calculés : ${resultats.length}');
    return resultats;
  }

  // ══════════════════════════════════════════════════════════════════════
  //  DÉTECTION — quasi gagnant après résultat
  // ══════════════════════════════════════════════════════════════════════

  /// Détecte un quasi-gagnant (comparaison sans ordre).
  /// Retourne null si pari déjà gagné ou seuil non atteint.
  QuasiGagnant? detecterQuasiGagnant({
    required String             courseKey,
    required DateTime           dateCourse,
    required String             nomCourse,
    required String             hippodrome,
    required String             heure,
    required String             discipline,
    required TypeGrosPari       type,
    required SourceQuasiGagnant source,
    required List<String>       numerosIA,
    required List<String>       arriveeReelle,
    required double             fiabilite,
  }) {
    final nb     = nbChevauxPourType(type);
    final requis = nbQuasiRequis(type);

    if (numerosIA.length    < nb) return null;
    if (arriveeReelle.length < nb) return null;

    final ia      = numerosIA.take(nb).map((e) => e.toString()).toSet();
    final arrivee = arriveeReelle.take(nb).map((e) => e.toString()).toSet();

    final trouves   = ia.intersection(arrivee).toList();
    final manquants = ia.difference(arrivee).toList();

    // Pari déjà gagné en totalité → ne pas afficher en quasi
    if (trouves.length == nb) return null;
    // Pas assez trouvé → pas de quasi
    if (trouves.length != requis) return null;

    return QuasiGagnant(
      id:               '${courseKey}_${source.name}_${type.name}',
      courseKey:        courseKey,
      dateCourse:       dateCourse,
      nomCourse:        nomCourse,
      hippodrome:       hippodrome,
      heure:            heure,
      discipline:       discipline,
      type:             type,
      source:           source,
      numerosIA:        ia.toList(),
      arriveeReelle:    arrivee.toList(),
      numerosTrouves:   trouves,
      numerosManquants: manquants,
      nbTrouves:        trouves.length,
      nbRequis:         nb,
      fiabilite:        fiabilite,
      createdAt:        DateTime.now(),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  CALCUL QUASI GAGNANTS — source Programme IA
  // ══════════════════════════════════════════════════════════════════════

  /// Calcule les quasi gagnants depuis les pronostics IA pour un mois donné.
  /// Déduplication par courseKey (meilleur niveau gardé).
  /// ★ v10.73 : surcharge avec filtre DateTimeRange optionnel
  List<QuasiGagnant> calculerQuasiGagnantsDepuisPronostics({
    required List<IaPronostic> pronostics,
    int? annee,
    int? mois,
    DateTimeRange? periode, // ★ v10.73 : filtre période calendrier
  }) {
    final Map<String, QuasiGagnant> meilleurParCourse = {};

    for (final p in pronostics) {
      final date = p.datePronostic;
      // Filtre : période explicite prioritaire, sinon année/mois, sinon tout
      if (periode != null) {
        if (date.isBefore(periode.start) || date.isAfter(periode.end)) continue;
      } else if (annee != null && mois != null) {
        if (date.year != annee || date.month != mois) continue;
      }
      final arrivee = p.arriveeReelle;
      if (arrivee == null || arrivee.isEmpty)  continue;

      final arriveeStr = arrivee.map((e) => e.toString()).toList();
      final typePari   = p.typePariConseille ?? '';

      TypeGrosPari? type;
      if (typePari.contains('Quinté'))      type = TypeGrosPari.quinte;
      else if (typePari.contains('Quarté')) type = TypeGrosPari.quarte;
      else if (typePari.contains('Tiercé')) type = TypeGrosPari.tierce;
      if (type == null) continue;

      // Numéros IA : top N selon scoresIA
      final nbVoulus = nbChevauxPourType(type);
      final numerosIA = (p.scoresIA.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .take(nbVoulus)
          .map((e) => e.key)
          .toList();

      final qg = detecterQuasiGagnant(
        courseKey:     p.courseKey,
        dateCourse:    date,
        nomCourse:     p.nomCourse,
        hippodrome:    p.hippodrome,
        heure:         '',
        discipline:    p.discipline,
        type:          type,
        source:        SourceQuasiGagnant.programme,
        numerosIA:     numerosIA,
        arriveeReelle: arriveeStr,
        fiabilite:     p.confiancePredite ?? 0.0,
      );

      if (qg != null) {
        final existing = meilleurParCourse[p.courseKey];
        if (existing == null ||
            nbChevauxPourType(qg.type) > nbChevauxPourType(existing.type)) {
          meilleurParCourse[p.courseKey] = qg;
        }
      }
    }

    return meilleurParCourse.values.toList()
      ..sort((a, b) => b.dateCourse.compareTo(a.dateCourse));
  }

  // ══════════════════════════════════════════════════════════════════════
  //  CALCUL QUASI GAGNANTS — source Best Bet
  // ══════════════════════════════════════════════════════════════════════

  /// Calcule les quasi gagnants depuis les signaux Best Bet archivés,
  /// en les croisant avec les arrivées réelles fournies.
  /// ★ v10.73 : filtre DateTimeRange optionnel
  List<QuasiGagnant> calculerQuasiGagnantsBestBet({
    required Map<String, List<int>> arriveesParcourseKey,
    int? annee,
    int? mois,
    DateTimeRange? periode, // ★ v10.73 : filtre période calendrier
  }) {
    final Map<String, QuasiGagnant> meilleurParCourse = {};

    if (kDebugMode) {
      debugPrint('[QUASI_GAGNANTS_FILTER] BestBet — ${_signaux.length} signaux en mémoire, '
          'periode=${periode?.start.toIso8601String() ?? "null"} → '
          '${periode?.end.toIso8601String() ?? "null"}');
    }

    for (final signal in _signaux) {
      // Filtre : période explicite prioritaire, sinon année/mois, sinon tout
      if (periode != null) {
        if (signal.dateCourse.isBefore(periode.start) ||
            signal.dateCourse.isAfter(periode.end)) continue;
      } else if (annee != null && mois != null) {
        if (signal.dateCourse.year  != annee) continue;
        if (signal.dateCourse.month != mois)  continue;
      }

      final arrivee = arriveesParcourseKey[signal.courseKey];
      if (arrivee == null || arrivee.isEmpty) continue;

      final arriveeStr = arrivee.map((e) => e.toString()).toList();
      final qg = detecterQuasiGagnant(
        courseKey:     signal.courseKey,
        dateCourse:    signal.dateCourse,
        nomCourse:     signal.nomCourse,
        hippodrome:    signal.hippodrome,
        heure:         signal.heure,
        discipline:    signal.discipline,
        type:          signal.type,
        source:        SourceQuasiGagnant.grosParisSurveiller,
        numerosIA:     signal.numeros,
        arriveeReelle: arriveeStr,
        fiabilite:     signal.fiabilite,
      );

      if (qg != null) {
        final existing = meilleurParCourse[signal.courseKey];
        if (existing == null ||
            nbChevauxPourType(qg.type) > nbChevauxPourType(existing.type)) {
          meilleurParCourse[signal.courseKey] = qg;
        }
      }
    }

    return meilleurParCourse.values.toList()
      ..sort((a, b) => b.dateCourse.compareTo(a.dateCourse));
  }

  // ══════════════════════════════════════════════════════════════════════
  //  GESTION DES SIGNAUX
  // ══════════════════════════════════════════════════════════════════════

  /// Ajoute plusieurs signaux en batch (idempotent sur l'id).
  /// ★ v10.73 : MERGE — ne supprime jamais les anciens signaux du jour.
  /// Purge automatique des signaux > 90 jours.
  Future<void> ajouterSignauxBatch(List<GrosPariSurveiller> signaux) async {
    await charger();
    // Merge : anciens + nouveaux, les nouveaux écrasent par id
    final map = <String, GrosPariSurveiller>{
      for (final s in _signaux) s.id: s,
    };
    for (final s in signaux) {
      map[s.id] = s; // écrase si même id, sinon ajoute
    }
    _signaux
      ..clear()
      ..addAll(map.values);
    // Purge > 90 jours
    final limite = DateTime.now().subtract(const Duration(days: 90));
    _signaux.removeWhere((s) => s.dateCourse.isBefore(limite));
    await _sauvegarder();
    if (kDebugMode) {
      debugPrint('[QUASI_GROS_PARIS_SAVE] ${_signaux.length} signaux sauvegardés '
          '(batch: ${signaux.length})');
    }
  }

  /// ★ v10.73 : Sauvegarde immédiate des signaux du jour (appelé depuis BestBetScreen).
  /// Utilise le même merge que ajouterSignauxBatch pour ne pas écraser l'historique.
  Future<void> sauvegarderSignauxGrosParisDuJour(
    List<GrosPariSurveiller> signaux,
  ) async {
    if (signaux.isEmpty) return;
    await ajouterSignauxBatch(signaux); // délègue le merge + persistance
    if (kDebugMode) {
      debugPrint('[QUASI_GROS_PARIS_SAVE] Sauvegarde immédiate : '
          '${signaux.length} signaux du jour');
    }
  }

  /// ★ v10.73 : Charge les signaux depuis SharedPreferences (accès direct).
  /// Utile pour lecture sans passer par l'état mémoire (_signaux).
  Future<List<GrosPariSurveiller>> chargerSignauxGrosParis() async {
    await charger();
    if (kDebugMode) {
      debugPrint('[QUASI_GROS_PARIS_LOAD] ${_signaux.length} signaux en mémoire');
    }
    return List.unmodifiable(_signaux);
  }

  /// Retourne les signaux d'aujourd'hui, triés par fiabilité décroissante.
  /// ★ v10.73 : masque le niveau "eviter" (trop spéculatif pour l'affichage)
  List<GrosPariSurveiller> signauxAujourdhui() {
    final today = DateTime.now();
    return _signaux
        .where((s) =>
            s.dateCourse.year  == today.year &&
            s.dateCourse.month == today.month &&
            s.dateCourse.day   == today.day &&
            s.niveau != NiveauFiabiliteGrosPari.eviter) // ★ v10.73 : masquer "éviter"
        .toList()
      ..sort((a, b) => b.fiabilite.compareTo(a.fiabilite));
  }

  /// ★ v10.73 : helpers de déduplication avec priorité Type + Source
  static int _prioriteType(TypeGrosPari type) {
    switch (type) {
      case TypeGrosPari.quinte: return 3;
      case TypeGrosPari.quarte: return 2;
      case TypeGrosPari.tierce: return 1;
    }
  }

  static int _prioriteSource(SourceQuasiGagnant source) {
    switch (source) {
      case SourceQuasiGagnant.grosParisSurveiller: return 2;
      case SourceQuasiGagnant.programme:           return 1;
    }
  }

  /// ★ v10.73 : Fusionne et déduplique par courseKey.
  /// Priorité : TypeGrosPari décroissant, puis SourceQuasiGagnant décroissante.
  static List<QuasiGagnant> dedoublonnerQuasiGagnants(
    List<QuasiGagnant> items,
  ) {
    final map = <String, QuasiGagnant>{};
    for (final qg in items) {
      final old = map[qg.courseKey];
      if (old == null) {
        map[qg.courseKey] = qg;
        continue;
      }
      final betterType =
          _prioriteType(qg.type) > _prioriteType(old.type);
      final sameTypeBetterSource =
          _prioriteType(qg.type) == _prioriteType(old.type) &&
          _prioriteSource(qg.source) > _prioriteSource(old.source);
      if (betterType || sameTypeBetterSource) {
        map[qg.courseKey] = qg;
      }
    }
    return map.values.toList();
  }

  // ══════════════════════════════════════════════════════════════════════
  //  BACKUP
  // ══════════════════════════════════════════════════════════════════════

  Map<String, dynamic> exporterPourBackup() => {
    'signaux':       _signaux.map((s) => s.toJson()).toList(),
    'quasiGagnants': _quasiGagnants.map((q) => q.toJson()).toList(),
  };

  Future<void> importerDepuisBackup(Map<String, dynamic> data) async {
    try {
      _signaux.clear();
      for (final item in (data['signaux'] as List? ?? [])) {
        try {
          _signaux.add(GrosPariSurveiller.fromJson(item as Map<String, dynamic>));
        } catch (_) {}
      }
      _quasiGagnants.clear();
      for (final item in (data['quasiGagnants'] as List? ?? [])) {
        try {
          _quasiGagnants.add(QuasiGagnant.fromJson(item as Map<String, dynamic>));
        } catch (_) {}
      }
      _charge = true;
      await _sauvegarder();
      if (kDebugMode) {
        debugPrint('[QuasiGros] Backup importé : ${_signaux.length} signaux, '
            '${_quasiGagnants.length} quasi-gagnants');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[QuasiGros] Erreur import backup (ignoré): $e');
    }
  }
}
