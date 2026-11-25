// ═══════════════════════════════════════════════════════════════════════════
//  RESULTAT OFFICIEL REPOSITORY — persistance PARTAGÉE des résultats et
//  rapports officiels PMU, indexée par IDENTITÉ COMPLÈTE de course.
//
//  ★ CORRECTION BLOC 1 — périmètre financier (arbitrage utilisateur, point 3)
//
//  ───────────────────────────────────────────────────────────────────────────
//  POURQUOI CE FICHIER EXISTE — LA MESURE QUI L'IMPOSE
//  ───────────────────────────────────────────────────────────────────────────
//
//  Mesuré AVANT création (commandes rejouables) :
//
//    • `IaPronostic` ne porte AUCUN champ de rapport officiel : ses seuls
//      champs « financiers » sont `coteFavoriPmu` et `cotesPmuParNumero`
//      (`grep -n "coteFavoriPmu\|cotesPmuParNumero" ia_memory_models.dart`).
//    • `RapportPmu` n'avait AUCUN `toJson` (seulement un `fromJson` sans
//      appelant, et un `toString`). Un rapport reçu du PMU ne pouvait donc
//      pas être réécrit sur le stockage.
//    • La chaîne officielle existait entièrement en MÉMOIRE
//      (`PmuApiService.fetchRapportsDefinitifs` →
//      `ZoneTurfService.chargerResultatsCourseComplet` →
//      `chargerResultatOfficielCourse` → `resoudreGainTicketDepuisDonnees`)
//      mais n'était persistée NULLE PART : chaque outil de simulation devait
//      donc réinventer un calcul (cotes fixes 2.5 / 4.5, multiplicateurs
//      ×0.65 / ×0.7, `mise × (cote − 1)`).
//
//  Ce repository supprime la cause : les rapports officiels sont conservés
//  UNE fois, par course, et rejoués indéfiniment par la chaîne officielle.
//
//  ───────────────────────────────────────────────────────────────────────────
//  CE QUE CE FICHIER NE FAIT PAS — VOLONTAIREMENT
//  ───────────────────────────────────────────────────────────────────────────
//   • AUCUN calcul de gain. Il ne sait pas ce qu'est un ticket gagnant. Il
//     stocke et rend des RAPPORTS ; l'arbitrage appartient au moteur unique
//     (`moteur_gain_pmu.dart`, point 8 de l'arbitrage).
//   • AUCUN apprentissage. Il n'importe pas `ia_memory_service.dart` : il ne
//     peut donc ni appeler `enregistrerResultat`, ni toucher un seuil, ni
//     déclencher un gradient (point 9 de l'arbitrage).
//   • AUCUNE écriture dans les tickets réels (« Mes Paris »).
//   • AUCUNE requête réseau. La récupération est le rôle de
//     `chaine_financiere_officielle.dart` ; ce fichier ne connaît ni `http`
//     ni URL, et reste donc testable sans réseau.
//   • AUCUN écrasement d'un fait définitif par un autre. Voir
//     [ResultatEcritureResultat] : une divergence est SIGNALÉE, jamais
//     arbitrée en silence.
//
//  ───────────────────────────────────────────────────────────────────────────
//  MODÈLE DE STOCKAGE — copié sur `ArriveeOfficielleService`
//  ───────────────────────────────────────────────────────────────────────────
//
//  Shards MENSUELS, clé `resultat_officiel_pmu_v1_YYYY-MM`. Ce choix n'est pas
//  décoratif : il reproduit exactement le mécanisme déjà éprouvé des arrivées
//  (`arrivee_officielle_complete_v1_YYYY-MM`), ce qui apporte gratuitement :
//    • la découverte DYNAMIQUE des mois (`enumererClesSurStockage`) : un mois
//      ajouté par une version future reste lisible et sauvegardable ;
//    • la conservation SANS LIMITE de durée (aucun `removeWhere` par date) ;
//    • une file d'attente des écritures non confirmées qui survit au
//      redémarrage.
//
//  Aucune limite de rétention n'est appliquée ici, conformément au §11 du
//  mandat : « Tous les pronostics possédant un résultat officiel doivent être
//  conservés sans limite de durée. » Ce repository ne purge RIEN.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/date_utils.dart' show dateDepuisCourseKey;
import 'gain_calculator.dart' show RapportPmu;

// ═══════════════════════════════════════════════════════════════════════════
//  1. IDENTITÉ COMPLÈTE DE COURSE — date + réunion + course
// ═══════════════════════════════════════════════════════════════════════════

/// Identité COMPLÈTE et canonique d'une course PMU.
///
/// Le mandat exige une clé « date + réunion + course ». Cette classe la rend
/// explicite plutôt que de la laisser implicite dans une chaîne :
///
///   • [numReunion] et [numCourse] sont des entiers, donc `R1` et `R01` sont
///     la MÊME course (ce qu'une comparaison de chaînes ne garantit pas) ;
///   • [date] est un [DateTime] normalisé au jour, donc une heure parasite ne
///     peut pas créer une seconde identité pour la même course.
///
/// [versCourseKey] rend la forme `R{numR}C{numC}_{ddmmyyyy}` — exactement le
/// format de `buildCourseKey()` (`arrivee_reelle_widget.dart:26`) et de
/// `TrackedCourse.key`. C'est ce qui permet de raccorder ce repository aux
/// pronostics existants SANS modifier ni leur clé, ni leur contenu.
class IdentiteCoursePmu {
  /// Numéro de réunion (1, 2, …). Strictement positif.
  final int numReunion;

  /// Numéro de course dans la réunion (1, 2, …). Strictement positif.
  final int numCourse;

  /// Date de la course, normalisée au jour.
  final DateTime date;

  const IdentiteCoursePmu({
    required this.numReunion,
    required this.numCourse,
    required this.date,
  });

  /// `true` si les trois composantes sont exploitables.
  bool get estValide =>
      numReunion > 0 &&
      numCourse > 0 &&
      date.year >= 1900 &&
      date.year <= 2200;

  /// Forme `R{numR}C{numC}_{ddmmyyyy}` — identique à `buildCourseKey()`.
  String get courseKey {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return 'R${numReunion}C${numCourse}_$d$m${date.year}';
  }

  /// Mois `YYYY-MM`, pour le shard mensuel. `null` si l'identité est invalide.
  String? get mois {
    if (!estValide) return null;
    final m = date.month.toString().padLeft(2, '0');
    return '${date.year}-$m';
  }

  /// Forme `ddmmyyyy` exigée par `PmuApiService` et `ZoneTurfService`.
  String get dateApi {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d$m${date.year}';
  }

  /// Lit une identité depuis une `courseKey` existante.
  ///
  /// Délègue ENTIÈREMENT à `dateDepuisCourseKey` (`utils/date_utils.dart`), qui
  /// refuse toute date calendaire invalide (31/02, 29/02 non bissextile…) et
  /// tolère les suffixes `_ia`, `_<millisecondes>`. Aucune date de
  /// remplacement n'est jamais fabriquée : une clé douteuse rend `null`.
  static IdentiteCoursePmu? depuisCourseKey(String courseKey) {
    final cle = courseKey.trim();
    if (cle.isEmpty) return null;

    final m = RegExp(r'^R(\d+)C(\d+)_').firstMatch(cle);
    if (m == null) return null;
    final numR = int.tryParse(m.group(1)!);
    final numC = int.tryParse(m.group(2)!);
    if (numR == null || numC == null) return null;

    final iso = dateDepuisCourseKey(cle);
    if (iso == null) return null;
    final parts = iso.split('-');
    if (parts.length != 3) return null;
    final annee = int.tryParse(parts[0]);
    final mois = int.tryParse(parts[1]);
    final jour = int.tryParse(parts[2]);
    if (annee == null || mois == null || jour == null) return null;

    final identite = IdentiteCoursePmu(
      numReunion: numR,
      numCourse: numC,
      date: DateTime(annee, mois, jour),
    );
    return identite.estValide ? identite : null;
  }

  /// Construit une identité depuis une [DateTime] et les deux numéros.
  /// Rend `null` si la date n'est pas un jour réel — aucune normalisation
  /// silencieuse n'est acceptée (contrôle par aller-retour).
  static IdentiteCoursePmu? construire({
    required DateTime? date,
    required int? numReunion,
    required int? numCourse,
  }) {
    if (date == null || numReunion == null || numCourse == null) return null;
    final jour = DateTime(date.year, date.month, date.day);
    if (jour.year != date.year ||
        jour.month != date.month ||
        jour.day != date.day) {
      return null;
    }
    final id = IdentiteCoursePmu(
      numReunion: numReunion,
      numCourse: numCourse,
      date: jour,
    );
    return id.estValide ? id : null;
  }

  @override
  bool operator ==(Object other) =>
      other is IdentiteCoursePmu &&
      other.numReunion == numReunion &&
      other.numCourse == numCourse &&
      other.date.year == date.year &&
      other.date.month == date.month &&
      other.date.day == date.day;

  @override
  int get hashCode =>
      Object.hash(numReunion, numCourse, date.year, date.month, date.day);

  @override
  String toString() => 'IdentiteCoursePmu($courseKey)';
}

// ═══════════════════════════════════════════════════════════════════════════
//  2. L'ENTRÉE PERSISTÉE
// ═══════════════════════════════════════════════════════════════════════════

/// Ce qui est conservé pour UNE course : l'arrivée officielle, les rapports
/// publiés, les statuts des partants, et l'état du drapeau « définitif ».
///
/// ⚠️ Cette entrée n'est PAS un verdict. Elle ne dit pas si un pari est
///    gagnant : elle dit ce que le PMU a PUBLIÉ. La différence est ce qui
///    permet de rejouer n'importe quel ticket, passé ou simulé, sans jamais
///    figer un résultat.
class EntreeResultatOfficiel {
  /// Identité de la course (porte `courseKey` par [IdentiteCoursePmu]).
  final IdentiteCoursePmu identite;

  /// Groupes d'arrivée officiels, ex æquo préservés. `null` = inconnus.
  final List<List<int>>? arriveeGroupes;

  /// `true` = définitif, `false` = provisoire, `null` = l'API est muette.
  final bool? arriveeDefinitive;

  /// Rapports officiels publiés, TELLS QUELS.
  final List<RapportPmu> rapports;

  /// Statuts bruts des partants (`numéro → statut PMU`), tels que la source
  /// les a donnés. `null` = information indisponible.
  final Map<int, String>? statutsPartants;

  /// Instant de la dernière écriture de cette entrée.
  final DateTime? dateRecuperation;

  const EntreeResultatOfficiel({
    required this.identite,
    required this.arriveeGroupes,
    required this.arriveeDefinitive,
    required this.rapports,
    this.statutsPartants,
    this.dateRecuperation,
  });

  /// `true` si l'entrée porte au moins un rapport officiel exploitable.
  bool get porteDesRapports => rapports.isNotEmpty;

  /// `true` si l'entrée porte une arrivée exploitable.
  bool get porteUneArrivee =>
      arriveeGroupes != null &&
      arriveeGroupes!.isNotEmpty &&
      arriveeGroupes!.every((g) => g.isNotEmpty);

  /// `true` si l'arrivée est explicitement provisoire.
  bool get estProvisoire => arriveeDefinitive == false;

  /// `true` si l'entrée peut fonder un calcul : arrivée + au moins un rapport.
  bool get estExploitable => porteUneArrivee && porteDesRapports;

  /// Empreinte de déduplication d'un rapport : deux rapports sont le MÊME
  /// rapport publié si et seulement si code, libellé, combinaison, rang et
  /// mise de base coïncident. Le montant est VOLONTAIREMENT exclu : un
  /// dividende corrigé par l'opérateur doit pouvoir remplacer l'ancien.
  static String empreinteRapport(RapportPmu r) =>
      '${r.codePariOfficiel}\u0001${r.libelleOfficiel}\u0001'
      '${r.combinaison}\u0001${r.rangCombinaisonPayable}\u0001'
      '${r.miseBaseCentimes}';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'numReunion': identite.numReunion,
        'numCourse': identite.numCourse,
        'date': identite.courseKey.substring(
            identite.courseKey.lastIndexOf('_') + 1),
        'arriveeGroupes': arriveeGroupes,
        'arriveeDefinitive': arriveeDefinitive,
        'rapports': rapports.map((r) => r.toJson()).toList(),
        // Clés JSON obligatoirement des chaînes : la conversion est faite ici
        // et défaite à la lecture. Aucune valeur n'est transformée.
        'statutsPartants': statutsPartants?.map((k, v) => MapEntry('$k', v)),
        'dateRecuperation': dateRecuperation?.toIso8601String(),
      };

  /// Lecture TOLÉRANTE : une entrée illisible rend `null` plutôt que d'être
  /// reconstruite par approximation. Une entrée partiellement lisible est
  /// acceptée avec ses seuls champs valides — jamais complétée.
  static EntreeResultatOfficiel? fromJson(
    Map<String, dynamic> j, {
    required String courseKeyFallback,
  }) {
    // Identité : reconstruite depuis les champs, à défaut depuis la clé.
    IdentiteCoursePmu? identite;
    final d = j['date'];
    final numR = (j['numReunion'] as num?)?.toInt();
    final numC = (j['numCourse'] as num?)?.toInt();
    if (d is String && d.length == 8) {
      identite = IdentiteCoursePmu.construire(
        date: IdentiteCoursePmu.depuisCourseKey('R1C1_$d')?.date,
        numReunion: numR,
        numCourse: numC,
      );
    }
    identite ??= IdentiteCoursePmu.depuisCourseKey(courseKeyFallback);
    if (identite == null) return null;

    List<List<int>>? groupes;
    final g = j['arriveeGroupes'];
    if (g is List) {
      final out = <List<int>>[];
      var ok = true;
      for (final groupe in g) {
        if (groupe is! List) {
          ok = false;
          break;
        }
        final nums = <int>[];
        for (final n in groupe) {
          final v = n is num ? n.toInt() : int.tryParse('$n');
          if (v == null) {
            ok = false;
            break;
          }
          nums.add(v);
        }
        if (!ok) break;
        out.add(nums);
      }
      if (ok) groupes = out;
    }

    final rapports = <RapportPmu>[];
    final rj = j['rapports'];
    if (rj is List) {
      for (final item in rj) {
        if (item is! Map) continue;
        try {
          rapports.add(RapportPmu.fromJson(Map<String, dynamic>.from(item)));
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[ResultatOfficielRepo] rapport illisible ignoré: $e');
          }
        }
      }
    }

    Map<int, String>? statuts;
    final sp = j['statutsPartants'];
    if (sp is Map) {
      final out = <int, String>{};
      sp.forEach((k, v) {
        final num = int.tryParse('$k');
        if (num != null && v is String) out[num] = v;
      });
      statuts = out;
    }

    final dr = j['dateRecuperation'];

    return EntreeResultatOfficiel(
      identite: identite,
      arriveeGroupes: groupes,
      arriveeDefinitive: j['arriveeDefinitive'] is bool
          ? j['arriveeDefinitive'] as bool
          : null,
      rapports: List<RapportPmu>.unmodifiable(rapports),
      statutsPartants: statuts,
      dateRecuperation: dr is String ? DateTime.tryParse(dr) : null,
    );
  }

  @override
  String toString() => 'EntreeResultatOfficiel(${identite.courseKey} | '
      '${arriveeGroupes?.length ?? 0} groupe(s) | '
      '${rapports.length} rapport(s) | '
      'definitif=${arriveeDefinitive ?? "?"})';
}

// ═══════════════════════════════════════════════════════════════════════════
//  3. STATUT D'UNE ÉCRITURE — jamais d'écrasement silencieux
// ═══════════════════════════════════════════════════════════════════════════

/// Ce qui est arrivé à une écriture. Aucune de ces valeurs ne perd de donnée
/// en silence : chacune nomme précisément l'effet produit.
enum StatutEcritureResultat {
  /// Aucune entrée n'existait : elle a été créée.
  creee,

  /// Entrée existante enrichie (rapports ajoutés) sans rien perdre.
  enrichie,

  /// Entrée strictement identique : rien n'a été réécrit (déduplication).
  identique,

  /// Entrée provisoire remplacée par une entrée définitive. Mise à jour
  /// AUTORISÉE par le mandat (« mise à jour des résultats incomplets ou
  /// provisoires »).
  provisoireDevenueDefinitive,

  /// Deux entrées DÉFINITIVES divergent. L'entrée locale est CONSERVÉE, la
  /// nouvelle n'est pas écrite : on ne réécrit pas un fait officiel déjà
  /// établi. Le `courseKey` est signalé à l'appelant pour audit.
  conflitDefinitif,

  /// Écriture refusée : identité invalide, ou entrée sans rien d'exploitable.
  refusee,

  /// Échec technique d'écriture (stockage). La donnée reste en file d'attente.
  echecEcriture,
}

/// Résultat d'une écriture, avec le détail nécessaire à l'audit.
class ResultatEcritureResultat {
  final StatutEcritureResultat statut;
  final String? courseKey;
  final String? motif;

  const ResultatEcritureResultat(this.statut, {this.courseKey, this.motif});

  bool get estEcrit =>
      statut == StatutEcritureResultat.creee ||
      statut == StatutEcritureResultat.enrichie ||
      statut == StatutEcritureResultat.provisoireDevenueDefinitive;

  bool get estConflit => statut == StatutEcritureResultat.conflitDefinitif;

  @override
  String toString() => 'ResultatEcritureResultat(${statut.name}'
      '${courseKey == null ? '' : ' $courseKey'}'
      '${motif == null ? '' : ' — $motif'})';
}

// ═══════════════════════════════════════════════════════════════════════════
//  4. LE REPOSITORY
// ═══════════════════════════════════════════════════════════════════════════

/// Préfixe des clés de shard mensuel.
const String kResultatOfficielStoragePrefix = 'resultat_officiel_pmu_v1_';

/// Clé de la file d'attente des écritures non confirmées.
const String kResultatOfficielPendingKey = 'resultat_officiel_pending_v1';

/// Version du format sérialisé.
const int kResultatOfficielFormatVersion = 1;

/// Repository PARTAGÉ des résultats et rapports officiels.
///
/// Un seul exemplaire dans toute l'application : les outils de simulation
/// (backtesting, Martingale) et les écrans lisent donc la MÊME donnée
/// officielle, et une seule récupération réseau sert à tous. C'est la
/// condition d'unicité du moteur financier (point 8 de l'arbitrage).
class ResultatOfficielRepository {
  ResultatOfficielRepository._();
  static final ResultatOfficielRepository instance =
      ResultatOfficielRepository._();

  /// Shards décodés : mois (`YYYY-MM`) → (courseKey → entrée).
  final Map<String, Map<String, EntreeResultatOfficiel>> _shards = {};

  /// Entrées dont l'écriture n'a pas été confirmée. Jamais abandonnées.
  final Map<String, EntreeResultatOfficiel> _enAttente = {};

  bool _charge = false;
  Future<void>? _chargementEnCours;

  /// État public, en lecture seule, pour l'audit.
  String? derniereErreur;
  bool dernierEcritureConfirmee = true;

  /// Sérialise les écritures : deux écritures ne peuvent pas s'entrelacer.
  Future<void> _chaineEcriture = Future<void>.value();

  // ── Lecture d'état ──────────────────────────────────────────────────────

  bool get estCharge => _charge;

  /// Nombre total d'entrées conservées, tous mois confondus.
  int get nbEntrees => _shards.values.fold(0, (s, m) => s + m.length);

  /// Mois connus, triés.
  List<String> get moisConnus => _shards.keys.toList()..sort();

  /// Toutes les entrées conservées. COPIE : l'appelant ne peut pas muter l'état.
  List<EntreeResultatOfficiel> get toutesLesEntrees =>
      List<EntreeResultatOfficiel>.unmodifiable(
        _shards.values.expand((m) => m.values),
      );

  /// Toutes les entrées EXPLOITABLES (arrivée + au moins un rapport).
  List<EntreeResultatOfficiel> get entreesExploitables =>
      List<EntreeResultatOfficiel>.unmodifiable(
        toutesLesEntrees.where((e) => e.estExploitable),
      );

  // ── Helpers de clé ──────────────────────────────────────────────────────

  static String cleStockageMois(String mois) =>
      '$kResultatOfficielStoragePrefix$mois';

  /// Mois d'une clé de stockage, ou `null` si la forme n'est pas stricte.
  static String? moisDepuisCleStockage(String cle) {
    if (!cle.startsWith(kResultatOfficielStoragePrefix)) return null;
    final mois = cle.substring(kResultatOfficielStoragePrefix.length);
    if (mois.length != 7 || mois[4] != '-') return null;
    final annee = mois.substring(0, 4);
    final m = mois.substring(5, 7);
    if (int.tryParse(annee) == null) return null;
    final mi = int.tryParse(m);
    if (mi == null || mi < 1 || mi > 12) return null;
    return mois;
  }

  /// Découverte DYNAMIQUE des clés de shard présentes sur le stockage.
  Future<List<String>> enumererClesSurStockage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs
        .getKeys()
        .where((k) => k.startsWith(kResultatOfficielStoragePrefix))
        .toList()
      ..sort();
  }

  // ── Chargement ──────────────────────────────────────────────────────────

  /// Charge tous les shards mensuels. Idempotent, n'échoue jamais bruyamment :
  /// une panne de stockage ne doit pas bloquer l'application.
  Future<void> charger() {
    if (_charge) return Future<void>.value();
    final enCours = _chargementEnCours;
    if (enCours != null) return enCours;
    final future = _chargerInterne();
    _chargementEnCours = future;
    return future;
  }

  Future<void> _chargerInterne() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cles = await enumererClesSurStockage();
      for (final cle in cles) {
        final mois = moisDepuisCleStockage(cle);
        if (mois == null) continue;
        final brut = prefs.getString(cle);
        if (brut == null || brut.isEmpty) continue;
        final shard = _decoderShard(brut, mois);
        if (shard == null) {
          derniereErreur = 'shard $cle indécodable';
          continue;
        }
        _shards[mois] = shard;
      }
      // File d'attente : miroir du disque.
      final fileBrute = prefs.getString(kResultatOfficielPendingKey);
      if (fileBrute != null && fileBrute.isNotEmpty) {
        final map = _decoderMapEntrees(fileBrute);
        if (map != null) _enAttente.addAll(map);
      }
      _charge = true;
    } catch (e) {
      derniereErreur = '$e';
      _charge = true; // ne jamais bloquer
    } finally {
      _chargementEnCours = null;
    }
  }

  Map<String, EntreeResultatOfficiel>? _decoderShard(String brut, String mois) {
    try {
      final decode = jsonDecode(brut);
      if (decode is! Map) return null;
      // Le shard est `{version, entrees: {courseKey: {...}}}`. On déballe
      // `entrees` S'IL EST PRÉSENT ; sinon on retombe sur une map plate, ce
      // qui garde lisibles les shards d'un format antérieur.
      final source = decode['entrees'] is Map ? decode['entrees'] as Map : decode;
      final out = <String, EntreeResultatOfficiel>{};
      source.forEach((k, v) {
        if (v is! Map) return;
        final e = _entreeDepuisMap(Map<String, dynamic>.from(v), '$k');
        if (e != null) out['$k'] = e;
      });
      return out;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ResultatOfficielRepo] shard $mois illisible: $e');
      }
      return null;
    }
  }

  Map<String, EntreeResultatOfficiel>? _decoderMapEntrees(String brut) {
    try {
      final decode = jsonDecode(brut);
      if (decode is! Map) return null;
      final out = <String, EntreeResultatOfficiel>{};
      decode.forEach((k, v) {
        if (v is! Map) return;
        final e = _entreeDepuisMap(Map<String, dynamic>.from(v), '$k');
        if (e != null) out['$k'] = e;
      });
      return out;
    } catch (_) {
      return null;
    }
  }

  EntreeResultatOfficiel? _entreeDepuisMap(
      Map<String, dynamic> map, String cle) {
    return EntreeResultatOfficiel.fromJson(map, courseKeyFallback: cle);
  }

  // ── Lecture d'une course ────────────────────────────────────────────────

  /// L'entrée d'une course, ou `null` si elle n'est pas conservée.
  ///
  /// L'identité est relue DEPUIS la clé fournie ; une clé sans date réelle
  /// rend `null` — aucune entrée n'est devinée par ressemblance.
  EntreeResultatOfficiel? entreePourCourseKey(String courseKey) {
    final identite = IdentiteCoursePmu.depuisCourseKey(courseKey);
    if (identite == null) return null;
    return entreePourIdentite(identite);
  }

  /// L'entrée d'une course désignée par son identité complète.
  EntreeResultatOfficiel? entreePourIdentite(IdentiteCoursePmu identite) {
    final mois = identite.mois;
    if (mois == null) return null;
    final cle = identite.courseKey;
    return _shards[mois]?[cle] ?? _enAttente[cle];
  }

  /// `true` si une entrée exploitable est conservée pour cette course.
  bool contient(String courseKey) =>
      entreePourCourseKey(courseKey)?.estExploitable ?? false;

  // ── Écriture ────────────────────────────────────────────────────────────

  /// Enregistre (ou enrichit) le résultat officiel d'une course.
  ///
  /// Politique d'écriture — chacune des branches est une garantie :
  ///
  ///   • aucune entrée locale            → création ;
  ///   • local provisoire, nouveau déf.  → remplacement (autorisé) ;
  ///   • local et nouveau définitifs, arrivées IDENTIQUES
  ///                                     → fusion des rapports (enrichissement) ;
  ///   • local et nouveau définitifs, arrivées DIFFÉRENTES
  ///                                     → CONFLIT signalé, local conservé ;
  ///   • local définitif, nouveau provisoire
  ///                                     → le fait établi est conservé.
  ///
  /// Dans TOUS les cas, les rapports sont dédupliqués par [empreinteRapport] :
  /// un rapport déjà connu n'est jamais dupliqué, et un rapport déjà connu mais
  /// dont le DIVIDENDE a changé est mis à jour (l'opérateur peut corriger).
  Future<ResultatEcritureResultat> enregistrer({
    required EntreeResultatOfficiel entree,
  }) async {
    await charger();

    final identite = entree.identite;
    if (!identite.estValide) {
      return const ResultatEcritureResultat(
        StatutEcritureResultat.refusee,
        motif: 'identité de course invalide',
      );
    }
    if (!entree.porteUneArrivee && !entree.porteDesRapports) {
      return ResultatEcritureResultat(
        StatutEcritureResultat.refusee,
        courseKey: identite.courseKey,
        motif: 'ni arrivée ni rapport : rien à conserver',
      );
    }

    final mois = identite.mois!;
    final cle = identite.courseKey;
    final existante = _shards[mois]?[cle] ?? _enAttente[cle];

    late final EntreeResultatOfficiel aEcrire;
    late final StatutEcritureResultat statut;

    if (existante == null) {
      aEcrire = _horodater(entree);
      statut = StatutEcritureResultat.creee;
    } else if (existante.estProvisoire && !entree.estProvisoire) {
      // Provisoire → définitif : remplacement explicitement autorisé.
      aEcrire = _horodater(entree);
      statut = StatutEcritureResultat.provisoireDevenueDefinitive;
    } else if (!existante.estProvisoire && entree.estProvisoire) {
      // Le fait établi prime sur un provisoire : on n'écrase pas l'histoire,
      // mais on récupère les rapports nouveaux (enrichissement sans régression).
      final fusion = _fusionnerRapports(existante, entree);
      if (fusion.ajouts == 0 && fusion.misesAJour == 0) {
        return ResultatEcritureResultat(
          StatutEcritureResultat.identique,
          courseKey: cle,
          motif: 'entrée définitive locale conservée face à un provisoire',
        );
      }
      aEcrire = fusion.entree;
      statut = StatutEcritureResultat.enrichie;
    } else if (existante.porteUneArrivee &&
        entree.porteUneArrivee &&
        !_memesGroupes(existante.arriveeGroupes!, entree.arriveeGroupes!)) {
      // Deux arrivées officielles divergentes : CONFLIT. On signale, on ne
      // tranche pas. L'arrivée locale reste, les rapports nouveaux sont ajoutés
      // (ils ne contredisent pas un fait de course, seulement un dividende).
      final fusion = _fusionnerRapports(existante, entree);
      if (fusion.ajouts > 0 || fusion.misesAJour > 0) {
        aEcrire = fusion.entree;
        await _ecrireDansShard(mois, cle, aEcrire);
      }
      return ResultatEcritureResultat(
        StatutEcritureResultat.conflitDefinitif,
        courseKey: cle,
        motif: 'arrivées officielles divergentes : '
            '${existante.arriveeGroupes} vs ${entree.arriveeGroupes}',
      );
    } else {
      // Même fait de course : fusion des rapports.
      final fusion = _fusionnerRapports(existante, entree);
      if (fusion.ajouts == 0 && fusion.misesAJour == 0) {
        return ResultatEcritureResultat(
          StatutEcritureResultat.identique,
          courseKey: cle,
        );
      }
      aEcrire = fusion.entree;
      statut = StatutEcritureResultat.enrichie;
    }

    final ok = await _ecrireDansShard(mois, cle, aEcrire);
    return ResultatEcritureResultat(
      ok ? statut : StatutEcritureResultat.echecEcriture,
      courseKey: cle,
      motif: ok ? null : 'échec de persistance : entrée mise en file',
    );
  }

  EntreeResultatOfficiel _horodater(EntreeResultatOfficiel e) =>
      EntreeResultatOfficiel(
        identite: e.identite,
        arriveeGroupes: e.arriveeGroupes,
        arriveeDefinitive: e.arriveeDefinitive,
        rapports: e.rapports,
        statutsPartants: e.statutsPartants,
        dateRecuperation: DateTime.now(),
      );

  ({EntreeResultatOfficiel entree, int ajouts, int misesAJour}) _fusionnerRapports(
    EntreeResultatOfficiel existante,
    EntreeResultatOfficiel nouvelle,
  ) {
    final parEmpreinte = <String, RapportPmu>{};
    for (final r in existante.rapports) {
      parEmpreinte[EntreeResultatOfficiel.empreinteRapport(r)] = r;
    }
    var ajouts = 0;
    var misesAJour = 0;
    for (final r in nouvelle.rapports) {
      final cle = EntreeResultatOfficiel.empreinteRapport(r);
      final ancien = parEmpreinte[cle];
      if (ancien == null) {
        parEmpreinte[cle] = r;
        ajouts++;
      } else if (ancien.dividende != r.dividende ||
          ancien.rembourse != r.rembourse) {
        // Le DIVIDENDE est une donnée que l'opérateur peut corriger ; deux
        // rapports de même identité mais de montant différent ne sont pas
        // deux rapports, c'est une correction. On retient la plus récente.
        parEmpreinte[cle] = r;
        misesAJour++;
      }
    }
    final statuts = <int, String>{
      ...?existante.statutsPartants,
      ...?nouvelle.statutsPartants,
    };
    return (
      entree: EntreeResultatOfficiel(
        identite: existante.identite,
        arriveeGroupes: existante.arriveeGroupes ?? nouvelle.arriveeGroupes,
        arriveeDefinitive:
            existante.arriveeDefinitive ?? nouvelle.arriveeDefinitive,
        rapports: List<RapportPmu>.unmodifiable(parEmpreinte.values),
        statutsPartants: statuts.isEmpty ? null : statuts,
        dateRecuperation: DateTime.now(),
      ),
      ajouts: ajouts,
      misesAJour: misesAJour,
    );
  }

  static bool _memesGroupes(List<List<int>> a, List<List<int>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].length != b[i].length) return false;
      for (var j = 0; j < a[i].length; j++) {
        if (a[i][j] != b[i][j]) return false;
      }
    }
    return true;
  }

  /// Écrit réellement l'entrée, en sérialisant les écritures.
  Future<bool> _ecrireDansShard(
    String mois,
    String cle,
    EntreeResultatOfficiel entree,
  ) {
    return _serialiser(() async {
      _shards.putIfAbsent(mois, () => <String, EntreeResultatOfficiel>{});
      _shards[mois]![cle] = entree;
      return _persisterShard(mois);
    });
  }

  Future<T> _serialiser<T>(Future<T> Function() action) {
    final resultat = _chaineEcriture.then((_) => action());
    _chaineEcriture = resultat.then<void>((_) {}, onError: (_) {});
    return resultat;
  }

  Future<bool> _persisterShard(String mois) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final contenu = <String, dynamic>{
        'version': kResultatOfficielFormatVersion,
        'entrees': {
          for (final e in _shards[mois]!.entries) e.key: e.value.toJson(),
        },
      };
      final ok =
          await prefs.setString(cleStockageMois(mois), jsonEncode(contenu));
      dernierEcritureConfirmee = ok;
      if (!ok) derniereErreur = 'setString($mois) a rendu false';
      return ok;
    } catch (e) {
      dernierEcritureConfirmee = false;
      derniereErreur = '$e';
      if (kDebugMode) {
        debugPrint('[ResultatOfficielRepo] échec écriture shard $mois: $e');
      }
      return false;
    }
  }

  // ── Sauvegarde / restauration ───────────────────────────────────────────

  /// Exporte TOUS les shards présents sur le stockage.
  ///
  /// Découverte DYNAMIQUE (`enumererClesSurStockage`) : un mois écrit par une
  /// version future est exporté tel quel, sans que ce service ait besoin de le
  /// comprendre. La conservation est SANS LIMITE : rien n'est filtré par date.
  Future<Map<String, dynamic>> exporterPourBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final cles = await enumererClesSurStockage();
    final shards = <String, String>{};
    for (final cle in cles) {
      final v = prefs.getString(cle);
      if (v != null && v.isNotEmpty) shards[cle] = v;
    }
    return <String, dynamic>{
      'version': kResultatOfficielFormatVersion,
      'nbClefs': shards.length,
      'shards': shards,
      'enAttente':
          _enAttente.values.map((e) => e.toJson()).toList(growable: false),
    };
  }

  /// Restaure depuis une sauvegarde.
  ///
  /// Règle identique à celle des arrivées : un fait local est PRÉSERVÉ. On
  /// n'ajoute que les courses ABSENTES ; une divergence est comptée, jamais
  /// arbitrée. Un shard indécodable est COMPTÉ et IGNORÉ — jamais substitué.
  Future<ResultatRestaurationResultats> restaurerDepuisBackup(
    Map<String, dynamic> backup,
  ) async {
    try {
      await charger();
      final brut = backup['shards'];
      if (brut is! Map) {
        return ResultatRestaurationResultats.echec('clé "shards" absente');
      }
      var lus = 0;
      var illisibles = 0;
      var ajoutees = 0;
      var doublons = 0;
      final conflits = <String>[];
      final moisTouches = <String>{};

      for (final entry in brut.entries) {
        final cle = '${entry.key}';
        final mois = moisDepuisCleStockage(cle);
        if (mois == null) {
          illisibles++;
          continue;
        }
        final contenu = entry.value;
        if (contenu is! String || contenu.isEmpty) {
          illisibles++;
          continue;
        }
        final shard = _decoderShard(contenu, mois);
        if (shard == null) {
          illisibles++;
          continue;
        }
        lus++;
        _shards.putIfAbsent(mois, () => <String, EntreeResultatOfficiel>{});
        for (final e in shard.entries) {
          final locale = _shards[mois]![e.key];
          if (locale == null) {
            _shards[mois]![e.key] = e.value;
            ajoutees++;
            moisTouches.add(mois);
            continue;
          }
          final memeArrivee = locale.porteUneArrivee && e.value.porteUneArrivee
              ? _memesGroupes(locale.arriveeGroupes!, e.value.arriveeGroupes!)
              : locale.arriveeGroupes == e.value.arriveeGroupes;
          if (memeArrivee) {
            final fusion = _fusionnerRapports(locale, e.value);
            if (fusion.ajouts > 0 || fusion.misesAJour > 0) {
              _shards[mois]![e.key] = fusion.entree;
              moisTouches.add(mois);
            } else {
              doublons++;
            }
          } else {
            conflits.add(e.key);
          }
        }
      }

      var nonEcrits = 0;
      for (final mois in moisTouches) {
        if (!await _persisterShard(mois)) nonEcrits++;
      }

      return ResultatRestaurationResultats(
        succes: true,
        shardsLus: lus,
        shardsIllisibles: illisibles,
        entreesAjoutees: ajoutees,
        entreesDejaPresentes: doublons,
        conflits: conflits,
        moisNonEcrits: nonEcrits,
      );
    } catch (e) {
      return ResultatRestaurationResultats.echec('$e');
    }
  }

  /// Efface tout (réservé aux tests et à la réinitialisation EXPLICITE).
  ///
  /// ⚠️ N'est appelé par AUCUN chemin de production : ce repository ne purge
  ///    jamais rien de lui-même (§11 du mandat).
  Future<void> viderPourTest() async {
    final prefs = await SharedPreferences.getInstance();
    final cles = await enumererClesSurStockage();
    for (final cle in cles) {
      await prefs.remove(cle);
    }
    if (prefs.getKeys().contains(kResultatOfficielPendingKey)) {
      await prefs.remove(kResultatOfficielPendingKey);
    }
    _shards.clear();
    _enAttente.clear();
    _charge = false;
    dernierEcritureConfirmee = true;
    derniereErreur = null;
  }

  /// Oublie l'état de chargement (tests uniquement).
  void oublierChargementPourTest() {
    _shards.clear();
    _enAttente.clear();
    _charge = false;
  }
}

// ─── Résultat de restauration ───────────────────────────────────────────────

/// Bilan d'une restauration. Aucun champ n'est « deviné » : ce qui n'a pas été
/// restauré est COMPTÉ, et les divergences sont NOMMÉES.
class ResultatRestaurationResultats {
  final bool succes;
  final int shardsLus;
  final int shardsIllisibles;
  final int entreesAjoutees;
  final int entreesDejaPresentes;
  final List<String> conflits;
  final int moisNonEcrits;
  final String? erreur;

  ResultatRestaurationResultats({
    required this.succes,
    this.shardsLus = 0,
    this.shardsIllisibles = 0,
    this.entreesAjoutees = 0,
    this.entreesDejaPresentes = 0,
    this.conflits = const [],
    this.moisNonEcrits = 0,
    this.erreur,
  });

  factory ResultatRestaurationResultats.echec(String erreur) =>
      ResultatRestaurationResultats(succes: false, erreur: erreur);

  bool get aDesConflits => conflits.isNotEmpty;

  @override
  String toString() => 'ResultatRestaurationResultats(succes=$succes, '
      'shardsLus=$shardsLus, illisibles=$shardsIllisibles, '
      'ajoutees=$entreesAjoutees, doublons=$entreesDejaPresentes, '
      'conflits=${conflits.length}, moisNonEcrits=$moisNonEcrits'
      '${erreur == null ? '' : ', erreur=$erreur'})';
}
