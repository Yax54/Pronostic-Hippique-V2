// ═══════════════════════════════════════════════════════════════════════════
//  B1-T12 / LOT 2-C — DÉTECTION DES GAINS OFFICIELS TARDIFS
// ═══════════════════════════════════════════════════════════════════════════
//
//  ★ CE QUE CE FICHIER FAIT — ET CE QU'IL NE FAIT PAS
//
//  Il DÉTECTE : il interroge ZoneTurf et PMU pour les courses portées par des
//  tickets DÉJÀ PERSISTÉS, il CLASSE la réponse, et il décide QUAND réessayer.
//
//  Il n'écrit AUCUNE donnée financière, il ne calcule AUCUN montant, et il
//  n'importe AUCUN type du socle des gains PMU : le garde-fou B-0
//  tient une liste FERMÉE de neuf importateurs (comparée par ÉGALITÉ) et ce
//  fichier n'a aucune raison d'en être le dixième.
//
//  ⚠️ POURQUOI AUCUN MONTANT ICI : la conversion verdict → montant officiel
//     vit dans `enregistreur_verdict_gain_pmu.dart` (déjà importateur autorisé,
//     qui nomme `EtatGain` et `VerdictGain`). L'écriture vit dans
//     `PmuProvider`. Trois responsabilités, trois fichiers, aucun moteur
//     financier en double.
//
//  ⚠️ LA DÉTECTION EST INDÉPENDANTE DE `TrackedCourse`. `TrackedCourse` est
//     TEMPORAIRE (purgé à 24 h) et ne peut donc pas fonder une récupération
//     qui doit pouvoir aboutir des jours plus tard. La source est ici
//     l'IDENTITÉ DE COURSE portée par les tickets persistés :
//     `(dateStr, numReunion, numCourse)`.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/zt_models.dart' show ResultatCourse;
import '../services/pmu_api_service.dart'
    show PmuApiService, CauseAbsenceRapports, DiagnosticRapports;
import '../services/zone_turf_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  0. SOURCES INJECTABLES — testabilité SANS réseau, production INCHANGÉE
// ═══════════════════════════════════════════════════════════════════════════

/// Lit les rapports d'une course. Signature EXACTEMENT celle de
/// `PmuApiService.fetchRapportsAvecDiagnostic`.
typedef SourceRapports = Future<DiagnosticRapports> Function(
    String dateStr, int numReunion, int numCourse);

/// Lit l'arrivée d'une course. Signature EXACTEMENT celle de
/// `ZoneTurfService.chargerResultatsCourseComplet`.
typedef SourceArrivee = Future<ResultatCourse?> Function({
  required DateTime heureDepart,
  required int numReunion,
  required int numCourse,
});

/// ⚠️ CES DEUX DÉLÉGUÉS EXISTENT POUR UNE SEULE RAISON : rendre la
///    classification VÉRIFIABLE. Sans eux, tester « 404 ⇒ indisponible » ou
///    « arrivée provisoire ⇒ aucune écriture » exigerait un vrai serveur, et
///    le test ne prouverait rien de reproductible.
///
///    Leurs valeurs par DÉFAUT sont les fonctions statiques réelles : le
///    détecteur en production appelle donc EXACTEMENT les mêmes méthodes
///    qu'avant, avec le même comportement et le même réseau. Aucune
///    valeur par défaut « neutre » n'est fournie : un appelant qui oublierait
///    d'injecter n'obtient pas un détecteur muet, il obtient le vrai.

// ═══════════════════════════════════════════════════════════════════════════
//  1. IDENTITÉ DE COURSE — regroupement par (dateStr, numReunion, numCourse)
// ═══════════════════════════════════════════════════════════════════════════

/// L'identité EXACTE d'une course, telle que la portent les tickets persistés.
///
/// Elle est l'unité de regroupement ET l'unité de bornage : une course
/// interrogée une fois ne l'est pas deux fois dans le même cycle, et trois
/// courses distinctes au maximum sont traitées par cycle.
@immutable
class IdentiteCourseTardive {
  /// Date au format `DDMMYYYY`, exactement celui de `UserPrediction.dateStr`.
  final String dateStr;
  final int numReunion;
  final int numCourse;

  const IdentiteCourseTardive({
    required this.dateStr,
    required this.numReunion,
    required this.numCourse,
  });

  /// Clé stable, utilisée pour la persistance du backoff.
  ///
  /// ⚠️ La date est incluse : deux courses de mêmes numéros à des dates
  ///    différentes sont DEUX courses. L'omettre ferait partager un backoff
  ///    entre deux courses distinctes.
  String get cle => '${dateStr}_R${numReunion}C$numCourse';

  /// `DateTime` correspondante, ou `null` si [dateStr] n'est pas exploitable.
  ///
  /// Aucune date n'est inventée : un format inattendu rend `null`, et la
  /// course sera simplement écartée du cycle.
  DateTime? get date {
    final s = dateStr.trim();
    if (s.length != 8) return null;
    for (var i = 0; i < 8; i++) {
      final c = s.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) return null;
    }
    final jour = int.parse(s.substring(0, 2));
    final mois = int.parse(s.substring(2, 4));
    final annee = int.parse(s.substring(4, 8));
    if (annee < 1900 || annee > 2200) return null;
    if (mois < 1 || mois > 12) return null;
    if (jour < 1 || jour > 31) return null;
    final d = DateTime(annee, mois, jour);
    // Relecture : une composante réécrite par le constructeur = date inventée.
    if (d.year != annee || d.month != mois || d.day != jour) return null;
    return d;
  }

  @override
  bool operator ==(Object other) =>
      other is IdentiteCourseTardive &&
      other.dateStr == dateStr &&
      other.numReunion == numReunion &&
      other.numCourse == numCourse;

  @override
  int get hashCode => Object.hash(dateStr, numReunion, numCourse);

  @override
  String toString() => cle;
}

// ═══════════════════════════════════════════════════════════════════════════
//  2. CLASSIFICATION D'UNE RÉPONSE — cinq cas DISTINCTS, aucun confondu
// ═══════════════════════════════════════════════════════════════════════════

/// Ce qu'un cycle a réellement obtenu pour UNE course.
///
/// ⚠️ CES CINQ CAS NE SONT PAS INTERCHANGEABLES. Les confondre était le défaut
///    de `chargerResultatOfficielCourse`, qui rend `null` pour « réseau », pour
///    « aucun rapport publié » ET pour « arrivée illisible » : l'appelant ne
///    pouvait alors ni distinguer une panne passagère d'une course non réglée,
///    ni décider s'il fallait réessayer.
enum ClassificationCourseTardive {
  /// Arrivée officielle exploitable ET au moins un rapport officiel publié.
  /// C'est le SEUL cas qui autorise une tentative d'écriture.
  exploitable,

  /// L'API répond, mais l'arrivée est explicitement PROVISOIRE.
  /// Ne jamais écrire un verdict sur une arrivée provisoire : on réessaiera.
  arriveeProvisoire,

  /// L'API répond correctement, mais aucun rapport n'est encore publié
  /// (`aucunRapportPublie`). La course n'est pas réglée : on réessaiera.
  rapportsAbsents,

  /// L'API répond, publie des lignes, mais toutes sont inexploitables
  /// (`aucunRapportExploitable`). On réessaiera : le contenu peut changer.
  rapportsInexploitables,

  /// Panne : réseau, timeout, HTTP non 200, corps non JSON, racine non liste,
  /// OU arrivée illisible. Aucune conclusion sur le fond n'est possible, donc
  /// on réessaie en respectant le backoff.
  indisponible;

  /// `true` seulement pour [exploitable].
  bool get permetEcriture => this == ClassificationCourseTardive.exploitable;

  /// `true` si le fait est susceptible de CHANGER sans intervention humaine.
  ///
  /// [rapportsInexploitables] en fait partie : des lignes publiées à dividende
  /// nul peuvent être complétées par l'opérateur. Aucun cas n'est donc un
  /// abandon définitif — c'est l'exigence explicite du lot.
  bool get reessayable => true;
}

/// Résultat d'un cycle de détection pour une course.
@immutable
class ResultatDetectionCourse {
  final IdentiteCourseTardive identite;
  final ClassificationCourseTardive classification;

  /// Cause brute d'absence de rapports quand elle est connue. Conservée pour
  /// l'audit : elle n'entre dans aucune décision financière.
  final CauseAbsenceRapports? causeRapports;

  /// Message d'erreur éventuel, pour le diagnostic uniquement.
  final String? erreur;

  const ResultatDetectionCourse({
    required this.identite,
    required this.classification,
    this.causeRapports,
    this.erreur,
  });

  @override
  String toString() => 'ResultatDetectionCourse(${identite.cle} → '
      '${classification.name}'
      '${causeRapports == null ? '' : ' | ${causeRapports!.name}'})';
}

// ═══════════════════════════════════════════════════════════════════════════
//  3. BACKOFF PERSISTANT — 15 min, 1 h, 6 h, 24 h, puis 48 h SANS ABANDON
// ═══════════════════════════════════════════════════════════════════════════

/// L'état de suivi d'une course : combien de tentatives, et quand réessayer.
///
/// ⚠️ CET ÉTAT EST DÉTACHÉ DE TOUT VERDICT. Il ne dit pas « le ticket est
///    réglé » — cela, seul le ticket persisté le dit, et B-4.3 le garantit par
///    `_verdictEstDefinitif`. Il dit seulement « quand ne pas réinterroger le
///    réseau ». Le confondre avec une preuve financière serait l'erreur que le
///    lot interdit (« jamais un drapeau d'écriture comme preuve de succès »).
@immutable
class EtatSuiviCourse {
  /// Nombre de cycles où cette course a été interrogée.
  final int tentatives;

  /// Instant du dernier essai, pour le calcul de l'échéance.
  final DateTime? dernierEssai;

  /// Dernière classification observée (audit + pilotage du backoff).
  final ClassificationCourseTardive? derniereClassification;

  const EtatSuiviCourse({
    this.tentatives = 0,
    this.dernierEssai,
    this.derniereClassification,
  });

  /// Délais du backoff, dans l'ordre. Le DERNIER est un plancher : il n'y a
  /// jamais d'abandon définitif, on continue à 48 h indéfiniment.
  static const List<Duration> delais = <Duration>[
    Duration(minutes: 15),
    Duration(hours: 1),
    Duration(hours: 6),
    Duration(hours: 24),
    Duration(hours: 48),
  ];

  /// Délai applicable APRÈS `n` tentatives (indexation bornée au dernier).
  static Duration delaiApres(int tentatives) {
    if (tentatives <= 0) return Duration.zero;
    final i = tentatives - 1;
    if (i >= delais.length) return delais.last;
    return delais[i];
  }

  /// L'échéance à partir de laquelle un nouvel essai est permis.
  ///
  /// `null` = jamais essayé, donc immédiatement éligible.
  DateTime? get prochainEssai {
    final dernier = dernierEssai;
    if (dernier == null) return null;
    return dernier.add(delaiApres(tentatives));
  }

  bool estEligibleA(DateTime maintenant) {
    final echeance = prochainEssai;
    if (echeance == null) return true;
    return !maintenant.isBefore(echeance);
  }

  EtatSuiviCourse apresEssai(
    DateTime quand,
    ClassificationCourseTardive classification,
  ) =>
      EtatSuiviCourse(
        tentatives: tentatives + 1,
        dernierEssai: quand,
        derniereClassification: classification,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'tentatives': tentatives,
        'dernierEssai': dernierEssai?.toIso8601String(),
        'derniereClassification': derniereClassification?.name,
      };

  static EtatSuiviCourse fromJson(Map<String, dynamic> j) {
    final brut = j['derniereClassification'] as String?;
    ClassificationCourseTardive? c;
    for (final v in ClassificationCourseTardive.values) {
      if (v.name == brut) {
        c = v;
        break;
      }
    }
    return EtatSuiviCourse(
      tentatives: (j['tentatives'] as num?)?.toInt() ?? 0,
      dernierEssai: DateTime.tryParse(j['dernierEssai'] as String? ?? ''),
      derniereClassification: c,
    );
  }
}

/// Persistance du backoff. Clé DÉDIÉE : elle ne touche ni aux tickets, ni à
/// `tracked_courses_v1`, ni à aucune clé financière.
class BackoffTardifStore {
  static const String clePrefs = 'gains_tardifs_backoff_v1';

  final SharedPreferences _prefs;

  BackoffTardifStore(this._prefs);

  static Future<BackoffTardifStore> ouvrir() async =>
      BackoffTardifStore(await SharedPreferences.getInstance());

  /// Tous les états connus. Un contenu illisible rend une carte vide plutôt
  /// qu'une exception : le backoff est un CONFORT, pas une garantie financière,
  /// et une donnée de confort corrompue ne doit pas bloquer l'application.
  Map<String, EtatSuiviCourse> lireTout() {
    final brut = _prefs.getString(clePrefs);
    if (brut == null || brut.isEmpty) return <String, EtatSuiviCourse>{};
    try {
      final decode = jsonDecode(brut);
      if (decode is! Map) return <String, EtatSuiviCourse>{};
      final out = <String, EtatSuiviCourse>{};
      decode.forEach((k, v) {
        if (k is! String || v is! Map) return;
        out[k] = EtatSuiviCourse.fromJson(Map<String, dynamic>.from(v));
      });
      return out;
    } catch (_) {
      return <String, EtatSuiviCourse>{};
    }
  }

  EtatSuiviCourse lire(String cle) =>
      lireTout()[cle] ?? const EtatSuiviCourse();

  Future<bool> ecrireTout(Map<String, EtatSuiviCourse> etats) async {
    try {
      final encode = <String, dynamic>{
        for (final e in etats.entries) e.key: e.value.toJson(),
      };
      return await _prefs.setString(clePrefs, jsonEncode(encode));
    } catch (_) {
      return false;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  4. LE DÉTECTEUR — bornage, non-concurrence, classification
// ═══════════════════════════════════════════════════════════════════════════

/// Le maximum de courses DISTINCTES traitées par cycle. Exigence du lot : trois.
const int kMaxCoursesParCycle = 3;

/// Interroge les courses et classe les réponses, sans jamais écrire de verdict.
class DetecteurGainsTardifs {
  final BackoffTardifStore store;

  /// Horloge injectable : aucun `DateTime.now()` en dur, donc testable.
  final DateTime Function() horloge;

  /// Sources injectables — par DÉFAUT les appels réels (voir [SourceRapports]).
  final SourceRapports sourceRapports;
  final SourceArrivee sourceArrivee;

  /// Courses DÉJÀ en cours d'interrogation. C'est la garantie
  /// « aucune interrogation concurrente d'une même course » : la clé est
  /// posée AVANT le premier `await` et retirée dans un `finally`.
  final Set<String> _enVol = <String>{};

  DetecteurGainsTardifs({
    required this.store,
    DateTime Function()? horloge,
    SourceRapports? sourceRapports,
    SourceArrivee? sourceArrivee,
  })  : horloge = horloge ?? DateTime.now,
        sourceRapports = sourceRapports ??
            PmuApiService.fetchRapportsAvecDiagnostic,
        sourceArrivee = sourceArrivee ??
            ZoneTurfService.chargerResultatsCourseComplet;

  /// Une course est-elle déjà en cours d'interrogation ?
  bool estEnVol(String cle) => _enVol.contains(cle);

  /// Sélectionne AU PLUS [kMaxCoursesParCycle] courses éligibles.
  ///
  /// L'ordre est DÉTERMINISTE : par échéance croissante, puis par clé. Un ordre
  /// non déterministe rendrait les tests instables et le comportement
  /// irreproductible.
  List<IdentiteCourseTardive> selectionner(
    Iterable<IdentiteCourseTardive> candidates, {
    int maximum = kMaxCoursesParCycle,
  }) {
    final maintenant = horloge();
    final etats = store.lireTout();

    final eligibles = <IdentiteCourseTardive>[];
    final vues = <String>{};
    for (final c in candidates) {
      if (!vues.add(c.cle)) continue; // dédoublonnage par identité
      if (c.date == null) continue; // date inexploitable : écartée
      if (_enVol.contains(c.cle)) continue; // jamais deux fois en parallèle
      final etat = etats[c.cle] ?? const EtatSuiviCourse();
      if (!etat.estEligibleA(maintenant)) continue;
      eligibles.add(c);
    }

    eligibles.sort((a, b) {
      final ea = etats[a.cle]?.prochainEssai;
      final eb = etats[b.cle]?.prochainEssai;
      if (ea == null && eb == null) return a.cle.compareTo(b.cle);
      if (ea == null) return -1; // jamais essayée : prioritaire
      if (eb == null) return 1;
      final cmp = ea.compareTo(eb);
      return cmp != 0 ? cmp : a.cle.compareTo(b.cle);
    });

    if (eligibles.length > maximum) {
      return eligibles.sublist(0, maximum);
    }
    return eligibles;
  }

  /// Interroge UNE course et la classe.
  ///
  /// ⚠️ NE LÈVE JAMAIS : toute panne est CLASSÉE (`indisponible`), jamais
  ///    propagée. Un cycle de détection ne doit pas faire tomber l'appelant.
  Future<ResultatDetectionCourse> interroger(IdentiteCourseTardive id) async {
    // Le verrou est posé AVANT tout `await`, et retiré quoi qu'il arrive.
    _enVol.add(id.cle);
    try {
      return await _interrogerSansVerrou(id);
    } finally {
      _enVol.remove(id.cle);
    }
  }

  Future<ResultatDetectionCourse> _interrogerSansVerrou(
      IdentiteCourseTardive id) async {
    final date = id.date;
    if (date == null) {
      return ResultatDetectionCourse(
        identite: id,
        classification: ClassificationCourseTardive.indisponible,
        erreur: 'dateStr inexploitable',
      );
    }

    // ── ① Les rapports d'abord : leur diagnostic est le plus riche. ────────
    DiagnosticRapports diag;
    try {
      diag = await sourceRapports(id.dateStr, id.numReunion, id.numCourse);
    } catch (e) {
      return ResultatDetectionCourse(
        identite: id,
        classification: ClassificationCourseTardive.indisponible,
        erreur: 'rapports: $e',
      );
    }

    switch (diag.cause) {
      case CauseAbsenceRapports.aucune:
        break; // au moins un rapport exploitable : on continue
      case CauseAbsenceRapports.aucunRapportPublie:
        return ResultatDetectionCourse(
          identite: id,
          classification: ClassificationCourseTardive.rapportsAbsents,
          causeRapports: diag.cause,
        );
      case CauseAbsenceRapports.aucunRapportExploitable:
        return ResultatDetectionCourse(
          identite: id,
          classification: ClassificationCourseTardive.rapportsInexploitables,
          causeRapports: diag.cause,
        );
      case CauseAbsenceRapports.httpNonOk:
      case CauseAbsenceRapports.timeout:
      case CauseAbsenceRapports.reseau:
      case CauseAbsenceRapports.corpsNonJson:
      case CauseAbsenceRapports.racineNonListe:
        // Aucune conclusion sur le FOND : la course peut très bien être réglée
        // et l'API en panne. Ne jamais classer ce cas « rapports absents ».
        return ResultatDetectionCourse(
          identite: id,
          classification: ClassificationCourseTardive.indisponible,
          causeRapports: diag.cause,
        );
    }

    // ── ② L'arrivée ensuite. Illisible ou provisoire ⇒ pas d'écriture. ────
    try {
      final resultat = await sourceArrivee(
        heureDepart: date,
        numReunion: id.numReunion,
        numCourse: id.numCourse,
      );
      if (resultat == null) {
        return ResultatDetectionCourse(
          identite: id,
          classification: ClassificationCourseTardive.indisponible,
          causeRapports: diag.cause,
          erreur: 'arrivée illisible',
        );
      }
      if (resultat.arriveeDefinitive == false) {
        return ResultatDetectionCourse(
          identite: id,
          classification: ClassificationCourseTardive.arriveeProvisoire,
          causeRapports: diag.cause,
        );
      }
      // `arriveeDefinitive == null` (API muette) n'est PAS converti en
      // « définitif » : on exige l'absence d'un démenti explicite, comme le
      // fait le moteur, mais on ne prétend pas que l'arrivée est confirmée.
      final groupes = resultat.arriveeGroupes;
      if (groupes == null || groupes.isEmpty) {
        return ResultatDetectionCourse(
          identite: id,
          classification: ClassificationCourseTardive.indisponible,
          causeRapports: diag.cause,
          erreur: 'groupes vides',
        );
      }
    } catch (e) {
      return ResultatDetectionCourse(
        identite: id,
        classification: ClassificationCourseTardive.indisponible,
        causeRapports: diag.cause,
        erreur: 'arrivée: $e',
      );
    }

    return ResultatDetectionCourse(
      identite: id,
      classification: ClassificationCourseTardive.exploitable,
      causeRapports: diag.cause,
    );
  }

  /// Exécute UN cycle borné : sélection, interrogations SÉQUENTIELLES,
  /// persistance du backoff. Rend les résultats obtenus.
  ///
  /// ⚠️ SÉQUENTIEL ET NON PARALLÈLE : les appels réseau d'un même cycle sont
  ///    enchaînés, ce qui rend le comportement reproductible et évite de
  ///    saturer l'API. Le bornage à trois courses rend ce choix peu coûteux.
  Future<List<ResultatDetectionCourse>> executerCycle(
    Iterable<IdentiteCourseTardive> candidates,
  ) async {
    final selection = selectionner(candidates);
    if (selection.isEmpty) return const <ResultatDetectionCourse>[];

    final etats = store.lireTout();
    final resultats = <ResultatDetectionCourse>[];

    for (final id in selection) {
      final r = await interroger(id);
      resultats.add(r);
      final avant = etats[id.cle] ?? const EtatSuiviCourse();
      etats[id.cle] = avant.apresEssai(horloge(), r.classification);
    }

    await store.ecrireTout(etats);
    return List<ResultatDetectionCourse>.unmodifiable(resultats);
  }
}
