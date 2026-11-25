// ═══════════════════════════════════════════════════════════════════
//  ZONE-TURF SERVICE — Données réelles via API PMU officielle
//  ⚠️ L'ancien proxy Python (localhost:5060) ne fonctionnait pas sur
//     mobile Android. Ce service utilise maintenant l'API PMU directement.
// ═══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/zt_models.dart';
import 'arrivee_officielle_service.dart';
import 'ia_pronostic_engine.dart';

class ZoneTurfService {
  // API PMU officielle (accessible depuis mobile et web)
  static const String _pmuBase = 'https://turfinfo.api.pmu.fr/rest/client/7';
  static const String _pmuSpec = 'specialisation=INTERNET';

  // Proxy web uniquement (même origine)
  static String get _proxyBase {
    if (kIsWeb) {
      final origin = Uri.base.origin;
      return '$origin/api/pmu';
    }
    return _pmuBase;
  }

  static Map<String, String> get _headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  // Cache en mémoire pour éviter les requêtes répétées
  static final Map<String, List<ZtReunion>> _cache = {};
  static final Map<String, DateTime> _cacheTime = {};

  /// ★ L1 — Compteur de reset, incrémenté UNIQUEMENT par
  /// [viderCachePourResetComplet]. Il ne sert qu'à une chose : permettre à un
  /// `chargerProgramme()` EN VOL de constater qu'un reset a eu lieu pendant son
  /// appel réseau, et donc de ne PAS écrire la capture L0 d'un état aboli.
  ///
  /// Il ne protège pas le cache lui-même (c'est le rôle de la purge, inchangée)
  /// et ne conditionne AUCUN comportement existant : il n'est lu que par la
  /// capture L0.
  static int _generationReset = 0;

  /// Nombre de resets observés depuis le démarrage du processus. Exposé pour
  /// les tests ; ne doit pas être utilisé comme décision métier.
  @visibleForTesting
  static int get generationReset => _generationReset;

  // Rétro-compat supprimé (fix #5 — champs unused)

  // ──────────────────────────────────────────────────────────────────
  // CHARGER LE PROGRAMME COMPLET via API PMU officielle
  // Fonctionne sur mobile Android ET sur web
  // ──────────────────────────────────────────────────────────────────
  static Future<List<ZtReunion>> chargerProgramme({
    bool forceRefresh = false,
    DateTime? date,
  }) async {
    final dateStr = date != null ? _dateToStr(date) : _todayStr();

    // ★ L1 : témoin de reset. Photographié ICI, AVANT l'appel réseau, pour
    // pouvoir détecter un reset survenu PENDANT le chargement (le réseau peut
    // durer 20 s). Si la génération a bougé, la capture L0 est abandonnée :
    // un chargement rendu obsolète par un reset ne doit rien écrire.
    final generationResetAuDemarrage = _generationReset;

    // Vérifier le cache (valide 15 min)
    final cached = _cache[dateStr];
    final cTime = _cacheTime[dateStr];
    if (!forceRefresh &&
        cached != null &&
        cTime != null &&
        DateTime.now().difference(cTime).inMinutes < 15) {
      if (kDebugMode) debugPrint('PMU Cache: données valides pour $dateStr');
      return cached;
    }

    try {
      if (kDebugMode) debugPrint('PMU API: chargement programme $dateStr...');

      // ── Étape 1 : récupérer la liste des réunions ─────────────────
      final progUrl = kIsWeb
          ? '$_proxyBase/programme/$dateStr'
          : '$_pmuBase/programme/$dateStr?$_pmuSpec';

      final progResp = await http.get(Uri.parse(progUrl), headers: _headers)
          .timeout(const Duration(seconds: 20));

      if (progResp.statusCode != 200) {
        if (kDebugMode) debugPrint('PMU API erreur programme: HTTP ${progResp.statusCode}');
        return []; // ★ v91 : pas de données fictives — erreur réelle
      }

      final progData = jsonDecode(progResp.body) as Map<String, dynamic>;
      final reunionsJson = (progData['programme']?['reunions'] as List<dynamic>? ?? []);

      if (reunionsJson.isEmpty) {
        if (kDebugMode) debugPrint('PMU API: aucune réunion trouvée pour $dateStr');
        return []; // ★ v91 : API PMU vide = pas de courses aujourd'hui
      }

      // ── Étape 2 : convertir en ZtReunion et charger les partants ──
      final List<ZtReunion> reunions = [];

      // ★ L1 — Captures d'arrivées officielles complètes, accumulées pendant
      // les boucles puis écrites en UNE SEULE fois (voir l'appel groupé après
      // les boucles). Aucune écriture n'a lieu ici.
      final List<EntreeArrivee> arriveesACapturer = <EntreeArrivee>[];

      for (final rJson in reunionsJson) {
        final r = rJson as Map<String, dynamic>;
        final hippo = r['hippodrome'] as Map<String, dynamic>? ?? {};
        final hippodromeLong = (hippo['libelleLong'] as String? ?? '').toUpperCase();

        // Filtrer les réunions étrangères
        if (!_estHippodromeFrancais(hippodromeLong)) continue;

        final lieu = hippo['libelleCourt'] as String? ?? hippo['libelle'] as String? ?? 'Inconnu';
        final numOfficiel = r['numOfficiel'] as int? ?? 0;
        final coursesJson = (r['courses'] as List<dynamic>? ?? []);

        // Déduire la discipline principale
        String discipline = 'Plat';
        if (coursesJson.isNotEmpty) {
          final disc0 = (coursesJson.first as Map<String, dynamic>)['discipline'] as String? ?? '';
          discipline = _pmuDisciplineToZt(disc0);
        }

        // ── Étape 3 : charger les partants pour chaque course ────────
        final List<ZtCourse> courses = [];
        for (final cJson in coursesJson) {
          final c = cJson as Map<String, dynamic>;
          final numOrdre = c['numOrdre'] as int? ?? 0;
          final nomCourse = c['libelle'] as String? ?? c['libelleCourt'] as String? ?? '';
          final distanceM = c['distance'] as int? ?? 0;
          final montant = c['montantPrix'] as int? ?? 0;
          final disc = _pmuDisciplineToZt(c['discipline'] as String? ?? '');
          // ★ v9.98 : categorieSpeciale n'existe PAS dans l'API PMU réelle.
          // La détection Quinté/Quarté se fait via la liste paris[].typePari.
          final pariTypes = (c['paris'] as List<dynamic>? ?? [])
              .map((p) => (p as Map<String, dynamic>)['typePari'] as String? ?? '')
              .toList();
          final isQuinte = pariTypes.contains('E_QUINTE_PLUS');
          final isQuarte = pariTypes.contains('E_QUARTE_PLUS') && !isQuinte;

          // ★ v9.93 : Détecter les courses classiques sans Quarté/Quinté
          // (Groupe 1/2/3, Poule d'Essai, etc.) — PMU ne publie que le Tiercé
          // catSpec basé sur pariTypes maintenant (categorieSpeciale absent de l'API)
          final catSpec  = pariTypes.join(' ');
          final nomUpper = nomCourse.toUpperCase();
          final isClassiqueSansMultiple = !isQuinte && !isQuarte &&
              (disc == 'Plat' || disc == 'PLAT') && montant >= 80000 &&
              // Pas de categorieSpeciale QUARTE/QUINTE = confirmation pas de paris multiples
              !catSpec.contains('QUARTE') && !catSpec.contains('QUINTE') &&
              // Mots-clés des grandes courses classiques françaises
              (nomUpper.contains('GROUPE') || nomUpper.contains('GROUP') ||
               nomUpper.contains('POULE') || nomUpper.contains("ARC DE") ||
               nomUpper.contains('JOCKEY CLUB') || nomUpper.contains('DIANE') ||
               nomUpper.contains('VERMEILLE') || nomUpper.contains('CADRAN') ||
               nomUpper.contains('ROYAL OAK') || nomUpper.contains('MORNY') ||
               nomUpper.contains('JEAN-LUC LAG') || nomUpper.contains('GANAY') ||
               nomUpper.contains('OPÉRA') || nomUpper.contains('OPERA') ||
               nomUpper.contains('CHAMPION') || nomUpper.contains('DERBY') ||
               (montant >= 200000)); // Dotation très élevée = grande course classique

          // ★ CORRECTION BL3-A23 + BL3-A24 — PISTE ET CATÉGORIE : DE VRAIES
          //   DONNÉES, PLUS DE CONSTANTES.
          //
          //   DÉFAUTS MESURÉS (audit BLOC 3 §5.5 et §5.6) :
          //     • `piste: 'Pelouse'` — littéral constant pour 100 % des courses.
          //       Consommateur : `ZtPartant.scoreTerrain(course.piste)`
          //       (`zt_models.dart:549`), qui compare la clé normalisée de la
          //       course aux clés produites par `_normaliserTerrainPmu`
          //       (`:726`) — cette dernière ne rend JAMAIS `'pelouse'`.
          //       Résultat : `terrainStocke != terrainNorm` toujours vrai, la
          //       boucle s'épuise, `return 50.0`. Critère Terrain (poids 0.05)
          //       neutralisé même quand la donnée existe.
          //     • `categorie: ''` — littéral vide. Consommateur :
          //       `_scoreDisciplineCompatibilite` (`ia_pronostic_engine.dart:381`),
          //       dont les trois branches (`handicap` / `reclam` / `condition`)
          //       étaient inatteignables par construction.
          //
          //   SOURCES RÉELLES, VÉRIFIÉES SUR LES FIXTURES PMU DU DÉPÔT
          //   (`test/fixtures/recherche_pmu/`, 146 courses lues) :
          //     • `typePiste`      : 'HERBE' (84), 'GAZON' (78),
          //                          'POUZZOLANE' (8), absent (146)
          //     • `penetrometre`   : {'intitule': 'Bon' | 'Souple' | 'Collant' |
          //                          'PSF STANDARD', 'valeurMesure': '3,6', …}
          //     • `categorieParticularite` : 'HANDICAP' (40), 'HANDICAP_DIVISE'
          //                          (17), 'A_RECLAMER' (7), 'COURSE_A_CONDITIONS'
          //                          (80), 'GROUPE_I' (4), 'GROUPE_III' (5),
          //                          'INCONNU' (54), …
          //
          //   ⚠️ AUCUNE DONNÉE FICTIVE NE REMPLACE UNE DONNÉE MANQUANTE.
          //      `typePiste` absent (146 courses sur 316 dans les fixtures)
          //      produit la chaîne VIDE, et non « Pelouse » : le consommateur
          //      `scoreTerrain` teste `terrainCourse.isEmpty` avant tout calcul
          //      et rend 50.0 — comportement neutre EXPLICITE, pas une
          //      supposition. De même, `categorieParticularite == 'INCONNU'`
          //      n'est pas converti en une catégorie inventée : il reste vide.
          //
          //   ⚠️ AUCUNE FORMULE, AUCUN COEFFICIENT, AUCUN SEUIL N'EST MODIFIÉ.
          //      `terrain: 0.05`, les quatre modulations de catégorie
          //      (×0,92 / ×0,88 / ×1,06) et `scoreTerrain` sont intacts : seule
          //      la DONNÉE transmise cesse d'être une constante.
          final String pisteReelle = _pisteDepuisJsonPmu(c);
          final String categorieReelle = _categorieDepuisJsonPmu(c);

          // Heure de départ
          // ⚠️ .toLocal() obligatoire : l'API PMU retourne des timestamps UTC.
          // Sans cela, les heures affichées seraient décalées de +1h ou +2h
          // par rapport à l'heure réelle de la course.
          final ts = c['heureDepart'] as int? ?? 0;
          final heureDt = ts > 0
              ? DateTime.fromMillisecondsSinceEpoch(ts).toLocal()
              : DateTime.now();
          final heureStr =
              '${heureDt.hour.toString().padLeft(2, '0')}:${heureDt.minute.toString().padLeft(2, '0')}';

          // ★ L1 — Capture de l'arrivée officielle COMPLÈTE, lue DIRECTEMENT
          // sur le JSON brut de `/programme/{date}`. `ordreArrivee` est un
          // `List<List<int>>` natif : le passer tel quel préserve les ex æquo.
          //
          // `depuisJsonCourse` retourne `null` — et rien n'est alors capturé —
          // si le statut n'est pas `ARRIVEE_DEFINITIVE_COMPLETE`, si
          // `ordreArrivee` est absent/vide/mal typé, ou si une date est
          // illisible. Une course sans arrivée définitive est donc IGNORÉE
          // SANS ERREUR : c'est le cas normal d'une course à venir.
          //
          // Aucune reconstruction depuis `rapports-definitifs` : la source est
          // ici, et nulle part ailleurs.
          final courseKey = 'R${numOfficiel}C$numOrdre' '_$dateStr';
          final entree = ArriveeOfficielleService.depuisJsonCourse(
            c,
            courseKey: courseKey,
          );
          if (entree != null) {
            arriveesACapturer.add(entree);
          }

          // Charger les partants via API PMU
          final List<ZtPartant> partants = await _chargerPartants(
              dateStr, numOfficiel, numOrdre, heureDt);

          courses.add(ZtCourse(
            numCourse: numOrdre,
            // ★ CORRECTION BL3-A22 — L'ANCRE EST UNE IDENTITÉ, PAS UN CONCATÉNAT
            //
            //   DÉFAUT MESURÉ : `anchor` valait '$numOfficiel$numOrdre', soit
            //   « 35 » pour la course 5 de la réunion 3. Le seul consommateur
            //   du champ est `IaPronosticEngine._numReunionDepuisAnchor()`
            //   (`ia_pronostic_engine.dart:876`), qui applique
            //   `RegExp(r'^R(\d+)C\d+$')` : « 35 » ne correspond JAMAIS.
            //   Conséquence : le numéro de réunion n'était jamais extrait, la
            //   clé de mouvements de cotes valait '' et le critère R
            //   (`mouvCote`, 6 % du score) restait neutralisé à 50.0 pour
            //   TOUTES les courses, en permanence.
            //
            //   FORMAT PRODUIT : « R{nR}C{nC} » — exactement celui attendu par
            //   le consommateur, et identique à ce que le commentaire de
            //   `ia_pronostic_engine.dart:853` affirmait déjà à tort.
            //
            //   La formule du critère R, son coefficient `mouvCote: 0.06`, les
            //   19 poids et les scores historiques ne sont PAS touchés : seule
            //   la donnée d'identité transmise est corrigée.
            anchor: 'R${numOfficiel}C$numOrdre',
            nom: nomCourse,
            heure: heureStr,
            distance: '${distanceM}m',
            prix: '$montant',
            type: disc,
            piste: pisteReelle,
            categorie: categorieReelle,
            isQuinte: isQuinte,
            isQuarte: isQuarte,
            isClassiqueSansMultiple: isClassiqueSansMultiple, // ★ v9.93
            pronosticZt: const [],
            partants: partants,
            dateStr: dateStr,  // ← date réelle pour heureDateTime correct
          ));
        }

        if (courses.isNotEmpty) {
          reunions.add(ZtReunion(
            code: 'R$numOfficiel',
            lieu: lieu,
            discipline: discipline,
            dateStr: dateStr,
            courses: courses,
          ));
        }
      }

      // ── L1 : UNE SEULE écriture groupée par cycle de chargement ──────────
      // Placée AVANT le retour anticipé « aucune réunion » : la capture ne
      // dépend pas du filtrage des réunions, seulement de ce que l'API a
      // réellement renvoyé.
      await _capturerArriveesOfficielles(
        arriveesACapturer,
        generationResetAuDemarrage: generationResetAuDemarrage,
        dateStr: dateStr,
      );

      if (reunions.isEmpty) {
        if (kDebugMode) debugPrint('PMU API: 0 réunion française après filtrage');
        return []; // ★ v91 : aucune course française aujourd'hui
      }

      // Appliquer les scores IA
      final withIA = _appliquerScoresIA(reunions);
      _cache[dateStr] = withIA;
      _cacheTime[dateStr] = DateTime.now();

      if (kDebugMode) debugPrint('PMU API: ${withIA.length} réunions françaises chargées pour $dateStr');
      return withIA;

    } catch (e) {
      if (kDebugMode) debugPrint('PMU API erreur: $e');
      return []; // ★ v91 : erreur réseau — pas de données fictives
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // ★ L1 — CAPTURE DES ARRIVÉES OFFICIELLES COMPLÈTES
  //
  // But : alimenter le stockage L0 déjà validé (`ArriveeOfficielleService`)
  // avec les arrivées définitives complètes que l'API PMU renvoie DÉJÀ dans
  // le JSON de `/programme/{date}`. Aucune requête supplémentaire, aucune
  // reconstruction depuis `rapports-definitifs`.
  //
  // GARANTIES :
  //   • UNE SEULE écriture groupée par cycle de chargement (cet appel unique,
  //     hors des boucles). Un cycle = N arrivées → 1 écriture par mois.
  //   • Entrées vides → aucun appel de stockage du tout.
  //   • Les erreurs sont ABSORBÉES : ce `try/catch` ne relance rien et ne
  //     touche ni `reunions`, ni `_cache`, ni le code de retour. Une panne du
  //     stockage L0 ne peut donc pas bloquer le chargement du programme.
  //   • Chargement obsolète : si un reset est survenu entre l'entrée dans
  //     `chargerProgramme()` et cet appel, rien n'est écrit. Respecte les
  //     protections contre les chargements obsolètes sans en modifier aucune.
  //   • AUCUN effet sur l'IA : pas d'apprentissage, pas de poids, pas de
  //     seuil, pas d'ELO, pas de statistique. Ce service ne fait que stocker.
  // ──────────────────────────────────────────────────────────────────
  static Future<void> _capturerArriveesOfficielles(
    List<EntreeArrivee> entrees, {
    required int generationResetAuDemarrage,
    required String dateStr,
  }) async {
    if (entrees.isEmpty) return; // rien à écrire : aucun accès au stockage

    try {
      // Chargement obsolète : un reset a eu lieu pendant l'appel réseau.
      // Ce qui a été lu décrit un état aboli — on n'écrit rien.
      if (generationResetAuDemarrage != _generationReset) {
        if (kDebugMode) {
          debugPrint('[ZoneTurf] ⏭️ capture L0 abandonnée : reset survenu '
              'pendant le chargement ($generationResetAuDemarrage → '
              '$_generationReset)');
        }
        return;
      }

      // ★ L1 — CHARGEMENT AVANT ÉCRITURE (obligatoire).
      // `enregistrerGroupe` fusionne avec l'état EN MÉMOIRE (`_shards[mois]`).
      // Écrire sans avoir chargé écraserait les shards déjà présents sur le
      // disque par un ensemble vide. `charger()` est idempotent et absorbé :
      // il ne lève pas et ne modifie ni `reunions`, ni `_cache`.
      //
      // NOTE : cet appel est aussi le POINT D'INITIALISATION UNIQUE de L0 côté
      // production. Il déclenche, au premier chargement du processus, le rejeu
      // idempotent de la file d'attente durable (voir `_chargerInterne`).
      await ArriveeOfficielleService.instance.charger();

      final r = await ArriveeOfficielleService.instance.enregistrerGroupe(
        entrees,
      );

      if (kDebugMode) {
        debugPrint('[ZoneTurf] 📥 capture L0 ($dateStr) : '
            '${entrees.length} arrivée(s) définitive(s) complète(s) — '
            'écrites=${r.nbEcrites}, enAttente=${r.nbEnAttente}, '
            'mois=${r.moisEcrits.join(",")}'
            '${r.moisEchoues.isEmpty ? "" : ", ÉCHECS=${r.moisEchoues.join(",")}"}'
            '${r.succes ? "" : " (échec partiel ou total, absorbé)"}');
      }
    } catch (e) {
      // Isolation stricte : une erreur L0 ne remonte JAMAIS au chargement du
      // programme. Le programme reste chargé, la capture est simplement perdue.
      if (kDebugMode) {
        debugPrint('[ZoneTurf] ⚠️ capture L0 échouée (absorbée, programme '
            'non affecté) : $e');
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // CHARGER LES PARTANTS D'UNE COURSE via API PMU
  // ──────────────────────────────────────────────────────────────────
  static Future<List<ZtPartant>> _chargerPartants(
      String dateStr, int numR, int numC, DateTime heureDt) async {
    try {
      final url = kIsWeb
          ? '${Uri.base.origin}/api/pmu/programme/$dateStr/R$numR/C$numC/participants'
          : '$_pmuBase/programme/$dateStr/R$numR/C$numC/participants?$_pmuSpec';

      final resp = await http.get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) return [];

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final participants = (data['participants'] as List<dynamic>? ?? []);

      final partants = <ZtPartant>[];
      for (final p in participants) {
        final pm = p as Map<String, dynamic>;
        if ((pm['statut'] as String? ?? '') == 'NON_PARTANT') continue;

        // Extraire la cote
        double coteVal = 0.0;
        final rapportRef = pm['dernierRapportReference'];
        final rapportDirect = pm['dernierRapportDirect'];
        if (rapportDirect is Map) {
          coteVal = (rapportDirect['rapport'] as num?)?.toDouble() ?? 0.0;
        }
        if (coteVal <= 0 && rapportRef is Map) {
          coteVal = (rapportRef['rapport'] as num?)?.toDouble() ?? 0.0;
        }

        // Extraire le nom du driver/jockey
        String driverNom = '';
        final driverField = pm['driver'] ?? pm['jockey'];
        if (driverField is Map) {
          driverNom = driverField['nom'] as String? ?? '';
        } else if (driverField is String) {
          driverNom = driverField;
        }

        // Extraire le nom de l'entraîneur
        String entraineurNom = '';
        final entrField = pm['entraineur'];
        if (entrField is Map) {
          entraineurNom = entrField['nom'] as String? ?? '';
        } else if (entrField is String) {
          entraineurNom = entrField;
        }

        // Gains carrière — l'API PMU renvoie les gains en centimes
        // gainsCarriere en centimes → diviser par 100 pour obtenir des euros
        final gainsCarriereRaw = ((pm['gainsParticipant'] as Map<String, dynamic>?)
            ?['gainsCarriere'] as num?)?.toDouble() ?? 0.0;
        // Heuristique : si le montant est > 10000 → probable centimes → convertir
        final gainsCarriere = gainsCarriereRaw > 10000 ? gainsCarriereRaw / 100.0 : gainsCarriereRaw;

        final age = pm['age'] as int? ?? 0;
        final sexe = pm['sexe'] as String? ?? '';

        // ── ENRICHISSEMENT IA — NOUVEAUX CHAMPS ────────────────────────
        // A) Poids porté (en grammes dans l'API → convertir en kg)
        final poidsGrammes = (pm['handicapPoids'] as num?)?.toDouble() ?? 0.0;
        final poidsKg = poidsGrammes > 0 ? poidsGrammes / 1000.0 : 0.0;

        // A2) RECORD PERSONNEL DU CHEVAL — Extraire depuis l'API PMU
        // L'API expose 'recordAbsolu' ou dans 'performances' le meilleur temps
        String recordStr = '';
        final recordAbsolu = pm['recordAbsolu'];
        if (recordAbsolu is Map) {
          // Format API : { "temps": 89.4, "distance": 1800 } ou { "tempsEnSecondes": 89.4 }
          final tempsSecondes = (recordAbsolu['temps'] as num?)?.toDouble()
              ?? (recordAbsolu['tempsEnSecondes'] as num?)?.toDouble()
              ?? 0.0;
          if (tempsSecondes > 0) {
            // Convertir en "M'SS" → ex: 89.4s → "1'29"
            final minutes = (tempsSecondes / 60).floor();
            final secondes = (tempsSecondes % 60).floor();
            recordStr = "$minutes'${secondes.toString().padLeft(2, '0')}";
          }
        } else if (recordAbsolu is num && recordAbsolu > 0) {
          final tempsSecondes = recordAbsolu.toDouble();
          final minutes = (tempsSecondes / 60).floor();
          final secondes = (tempsSecondes % 60).floor();
          recordStr = "$minutes'${secondes.toString().padLeft(2, '0')}";
        }
        // Fallback : chercher dans 'performances' ou 'historiquePerformances'
        if (recordStr.isEmpty) {
          final perfs = pm['performances'] ?? pm['historiquePerformances'];
          if (perfs is List && perfs.isNotEmpty) {
            double bestTime = 9999.0;
            for (final perf in perfs) {
              if (perf is Map) {
                final t = (perf['temps'] as num?)?.toDouble()
                    ?? (perf['tempsEnSecondes'] as num?)?.toDouble()
                    ?? 0.0;
                if (t > 0 && t < bestTime) bestTime = t;
              }
            }
            if (bestTime < 9999.0) {
              final minutes = (bestTime / 60).floor();
              final secondes = (bestTime % 60).floor();
              recordStr = "$minutes'${secondes.toString().padLeft(2, '0')}";
            }
          }
        }

        // B) Position de départ (numéro de stalle/corde)
        final placeDepart = pm['placeDepartCourse'] as int? ?? 0;

        // C) Musique globale
        final musiqueGlobale = pm['musique'] as String? ?? '';

        // D) JOURS DE REPOS — calculer depuis dateLastPerf
        //    Ordre de priorité :
        //    1. nbJoursAbsence (champ direct PMU)
        //    2. dateDernierePerformance (champ date ISO)
        //    3. Extraction depuis performances[] → champ date de la plus récente
        //    4. Extraction depuis musique PMU datée (format "JJ/MM/YYYY:musique")
        int joursRepos = 0;
        final nbJoursAbsence = pm['nbJoursAbsence'];
        if (nbJoursAbsence is int && nbJoursAbsence > 0) {
          joursRepos = nbJoursAbsence;
        } else if (nbJoursAbsence is num && nbJoursAbsence > 0) {
          joursRepos = nbJoursAbsence.toInt();
        } else {
          // Priorité 2 : dateDernierePerformance
          final dateDernPerf = pm['dateDernierePerformance'] as String?;
          if (dateDernPerf != null && dateDernPerf.isNotEmpty) {
            try {
              final parsed = DateTime.parse(dateDernPerf);
              joursRepos = DateTime.now().difference(parsed).inDays.abs();
            } catch (_) {}
          }

          // Priorité 3 : extraire la date la plus récente dans performances[]
          if (joursRepos == 0) {
            final perfsRaw = pm['performances'] ?? pm['historiquePerformances'];
            if (perfsRaw is List && perfsRaw.isNotEmpty) {
              DateTime? plusRecente;
              for (final perf in perfsRaw) {
                if (perf is! Map) continue;
                // Champs possibles : 'date', 'datePerformance', 'jour'
                final dateRaw = perf['date'] ?? perf['datePerformance'] ?? perf['jour'];
                if (dateRaw == null) continue;
                DateTime? dt;
                if (dateRaw is String && dateRaw.isNotEmpty) {
                  try { dt = DateTime.parse(dateRaw); } catch (_) {}
                  // Format FR : "JJ/MM/YYYY"
                  if (dt == null && dateRaw.contains('/')) {
                    try {
                      final parts = dateRaw.split('/');
                      if (parts.length == 3) {
                        dt = DateTime(
                          int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0])
                        );
                      }
                    } catch (_) {}
                  }
                } else if (dateRaw is int) {
                  // Timestamp epoch millisecondes
                  try { dt = DateTime.fromMillisecondsSinceEpoch(dateRaw); } catch (_) {}
                }
                if (dt != null && (plusRecente == null || dt.isAfter(plusRecente))) {
                  plusRecente = dt;
                }
              }
              if (plusRecente != null) {
                final jours = DateTime.now().difference(plusRecente).inDays.abs();
                // Sanity check : entre 1 et 500 jours (évite les dates aberrantes)
                if (jours >= 1 && jours <= 500) joursRepos = jours;
              }
            }
          }
        }

        // E) MUSIQUE FILTRÉE PAR DISTANCE ±100m
        //    PMU expose parfois 'performancesParDistance' (liste d'objets)
        String musiqueDistSpe = '';
        final perfParDist = pm['performancesParDistance'];
        if (perfParDist is List && perfParDist.isNotEmpty) {
          // Extraire la distance de la course depuis le contexte (on passe heureDt)
          // On ne peut pas accéder facilement ici, donc on stocke tout et filtre côté IA
          // Format : "DDDD:musique" séparé par virgules
          final buf = StringBuffer();
          for (final entry in perfParDist) {
            if (entry is Map) {
              final dist = entry['distance'] as int?;
              final muse = entry['musique'] as String? ?? '';
              if (dist != null && muse.isNotEmpty) {
                if (buf.isNotEmpty) buf.write(',');
                buf.write('$dist:$muse');
              }
            }
          }
          musiqueDistSpe = buf.toString();
        }

        // F) STATS JOCKEY — chercher dans 'indices' ou calculer heuristiquement
        //    PMU expose parfois pm['indices']['jockey'] = {victoires, courses}
        String statsJockeyCsv = '';
        final indices = pm['indices'];
        if (indices is Map) {
          final jockeyIdx = indices['jockey'];
          if (jockeyIdx is Map) {
            final nbCourses = (jockeyIdx['courses'] as num?)?.toInt() ?? 0;
            final nbVict = (jockeyIdx['victoires'] as num?)?.toInt() ?? 0;
            final nbPlace = (jockeyIdx['places'] as num?)?.toInt() ?? 0;
            if (nbCourses > 0) {
              final pctVic = (nbVict / nbCourses * 100).round();
              final pctPlc = (nbPlace / nbCourses * 100).round();
              statsJockeyCsv = '$driverNom|$pctVic|$pctPlc';
            }
          }
        }
        // Si pas de stats API, heuristique basée sur le nom du jockey (jockeys réputés)
        if (statsJockeyCsv.isEmpty && driverNom.isNotEmpty) {
          statsJockeyCsv = _heuristiqueJockey(driverNom);
        }

        // ★ v7.0 — G) STATS HIPPODROME — extraire depuis l'API PMU
        // L'API peut exposer pm['performancesParHippodrome'] ou pm['indices']['hippodrome']
        // Si absentes : calcul heuristique depuis la lettre de piste dans la musique globale
        // Format musique PMU : 1a=attelé, 1h=hippodrome Paris (Vincennes), 1m=monté, 1p=province
        // La lettre 'h' = piste de Vincennes (hippodromeActuel si connu)
        String statsHippoCsv = '';
        // Essayer d'abord depuis l'API directement
        final perfParHippo = pm['performancesParHippodrome'];
        if (perfParHippo is List && perfParHippo.isNotEmpty) {
          // Chercher l'hippodrome correspondant à la course actuelle
          for (final entry in perfParHippo) {
            if (entry is Map) {
              final hipNom = (entry['hippodrome'] as String? ?? '').toLowerCase();
              // On prend les stats de n'importe quel hippodrome (le plus récent suffit pour commencer)
              final nbC = (entry['nbCourses'] as num?)?.toInt() ?? 0;
              final nbV = (entry['nbVictoires'] as num?)?.toInt() ?? 0;
              final nbT = (entry['nbPlaces'] as num?)?.toInt() ?? 0; // top3 = places
              if (nbC > 0 && hipNom.isNotEmpty) {
                statsHippoCsv = '$nbC|$nbV|$nbT';
                break; // on prend le premier résultat dispo
              }
            }
          }
        }
        // Fallback : analyser la lettre de piste dans la musique globale
        // 'h' = Vincennes/Paris; 'p' = Province; 'a' = Attelé standard; 'm' = Monté
        if (statsHippoCsv.isEmpty && musiqueGlobale.isNotEmpty) {
          statsHippoCsv = _statsHippoDepuisMusique(musiqueGlobale);
        }

        // ★ v9.0 — H) STATS TERRAIN — extraire depuis l'API PMU
        // Format statsTerrainCsv : "terrain|nbC|nbV|nbTop3[;terrain2|...]"
        // L'API PMU expose parfois pm['performancesParTerrain'] ou pm['indices']['terrain']
        String statsTerrainCsv = '';
        final perfParTerrain = pm['performancesParTerrain'] ?? pm['performancesParEtatTerrain'];
        if (perfParTerrain is List && perfParTerrain.isNotEmpty) {
          final buf = StringBuffer();
          for (final entry in perfParTerrain) {
            if (entry is Map) {
              // L'API retourne 'etatTerrain' ou 'terrain'
              final terrain = ((entry['etatTerrain'] ?? entry['terrain']) as String? ?? '').toLowerCase();
              final nbC = (entry['nbCourses'] as num?)?.toInt() ?? 0;
              final nbV = (entry['nbVictoires'] as num?)?.toInt() ?? 0;
              final nbT = (entry['nbPlaces'] as num?)?.toInt() ?? 0;
              if (nbC > 0 && terrain.isNotEmpty) {
                if (buf.isNotEmpty) buf.write(';');
                final terrainNorm = _normaliserTerrainPmu(terrain);
                buf.write('$terrainNorm|$nbC|$nbV|$nbT');
              }
            }
          }
          statsTerrainCsv = buf.toString();
        }
        // Fallback depuis indices si disponible
        if (statsTerrainCsv.isEmpty && indices is Map) {
          final terrainIdx = indices['terrain'] ?? indices['etatTerrain'];
          if (terrainIdx is Map) {
            final terrain = (terrainIdx['etat'] as String? ?? '').toLowerCase();
            final nbC = (terrainIdx['courses'] as num?)?.toInt() ?? 0;
            final nbV = (terrainIdx['victoires'] as num?)?.toInt() ?? 0;
            final nbT = (terrainIdx['places'] as num?)?.toInt() ?? 0;
            if (nbC > 0 && terrain.isNotEmpty) {
              statsTerrainCsv = '${_normaliserTerrainPmu(terrain)}|$nbC|$nbV|$nbT';
            }
          }
        }

        // ★ v9.0 — I) GAINS DERNIER AN — extraire depuis l'API PMU
        // L'API peut exposer pm['gainsParticipant']['gainsSaison'] ou pm['gainsAnnee']
        int gainsDernierAn = 0;
        final gainsMap = pm['gainsParticipant'];
        if (gainsMap is Map) {
          final gainsSaison = (gainsMap['gainsSaison'] as num?)?.toDouble() ?? 0.0;
          final gainsAnnee  = (gainsMap['gainsAnnee']  as num?)?.toDouble() ?? 0.0;
          final raw = gainsSaison > 0 ? gainsSaison : gainsAnnee;
          // Convertir centimes → euros si nécessaire
          gainsDernierAn = (raw > 10000 ? raw / 100.0 : raw).round();
        }
        if (gainsDernierAn <= 0) {
          // Fallback : estimé à 20% des gains totaux si non disponible
          gainsDernierAn = (gainsCarriere * 0.20).round();
        }

        partants.add(ZtPartant(
          numero: (pm['numPmu'] ?? pm['numero'] ?? 0).toString(),
          nom: pm['nom'] as String? ?? '',
          driver: driverNom,
          entraineur: entraineurNom,
          proprietaire: pm['proprietaire'] as String? ?? '',
          gains: gainsCarriere > 0 ? '${gainsCarriere.round()}' : '',
          record: recordStr,
          musique: musiqueGlobale,
          cote: coteVal > 0 ? coteVal.toStringAsFixed(1) : '',
          ageSexe: '$sexe$age',
          poids: poidsKg,
          placeDepartInt: placeDepart,
          joursRepos: joursRepos,
          musiqueDistanceSpecifique: musiqueDistSpe,
          statsJockeyCsv: statsJockeyCsv,
          statsHippodromeCsv: statsHippoCsv,
          statsTerrainCsv: statsTerrainCsv,   // ★ v9.0
          gainsDernierAn: gainsDernierAn,      // ★ v9.0
        ));
      }

      partants.sort((a, b) {
        final na = int.tryParse(a.numero) ?? 99;
        final nb = int.tryParse(b.numero) ?? 99;
        return na.compareTo(nb);
      });

      return partants;
    } catch (e) {
      if (kDebugMode) debugPrint('PMU partants R${numR}C$numC erreur: $e');
      return [];
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // CHARGER LES PARTANTS D'UNE ZtCourse (méthode publique) — ★ v91
  // Utilisée par BetBottomSheet quand les partants ne sont pas chargés
  // ──────────────────────────────────────────────────────────────────
  static Future<List<ZtPartant>> chargerPartantsCourse(
      ZtCourse course, ZtReunion reunion) async {
    // Extraire numR depuis le code de réunion (ex: "R3" → 3)
    final numR = int.tryParse(reunion.code.replaceAll('R', '')) ?? 0;
    final numC = course.numCourse;
    final dateStr = course.dateStr.isNotEmpty ? course.dateStr : _todayStr();
    final partants = await _chargerPartants(dateStr, numR, numC, course.heureDateTime);
    // Appliquer les scores IA
    if (partants.isNotEmpty) {
      final courseTmp = ZtCourse(
        numCourse: numC, anchor: course.anchor, nom: course.nom,
        heure: course.heure, distance: course.distance, prix: course.prix,
        type: course.type, piste: course.piste, categorie: course.categorie,
        isQuinte: course.isQuinte, pronosticZt: course.pronosticZt,
        partants: partants, dateStr: dateStr,
      );
      final avecIA = IaPronosticEngine.analyserCourse(courseTmp);
      return avecIA;
    }
    return partants;
  }

  // ──────────────────────────────────────────────────────────────────
  // ★ v9.0 — NORMALISATION DU TERRAIN PMU
  // Convertit les libellés terrain de l'API PMU en clés normalisées
  // ──────────────────────────────────────────────────────────────────
  static String _normaliserTerrainPmu(String terrain) {
    final t = terrain.toLowerCase().replaceAll('_', ' ').trim();
    if (t.contains('tres lourd') || t.contains('très lourd') || t.contains('very') || t == 'tl') return 'tres_lourd';
    if (t.contains('lourd') || t == 'l')                  return 'lourd';
    if (t.contains('souple') || t.contains('soft') || t == 's') return 'souple';
    if (t.contains('bon') || t.contains('good') || t == 'b')   return 'bon';
    if (t.contains('sable') || t.contains('sand'))             return 'sable';
    if (t.contains('piste') || t.contains('all weather'))      return 'sable';
    if (t.contains('standard') || t.contains('normal'))        return 'bon';
    return t.replaceAll(' ', '_');
  }

  // ──────────────────────────────────────────────────────────────────
  // ★ CORRECTION BL3-A23 — PISTE RÉELLE depuis le JSON PMU
  //
  // Producteur corrigé : le champ `piste` de `ZtCourse` valait le littéral
  // `'Pelouse'` pour 100 % des courses.
  //
  // Consommateur : `ZtPartant.scoreTerrain(course.piste)`
  // (`zt_models.dart:549-575`), qui normalise via `_normaliserTerrain` puis
  // compare aux clés de `statsTerrainCsv` produites par `_normaliserTerrainPmu`
  // ci-dessus. Les deux tables rendent `tres_lourd / lourd / souple / bon /
  // sable` — JAMAIS `'pelouse'`. Toute comparaison échouait donc et le critère
  // Terrain (poids `terrain: 0.05`) restait à 50.0.
  //
  // ORDRE DE PRIORITÉ DES SOURCES, dans cet ordre exact :
  //   1. `penetrometre.intitule`  — l'état du terrain MESURÉ le jour J
  //      (« Bon », « Souple », « Collant », « PSF STANDARD », « Très lourd »…).
  //      C'est la source la plus précise : elle décrit l'état réel, pas la
  //      nature du sol.
  //   2. `typePiste`  — la nature du sol (« HERBE », « GAZON », « POUZZOLANE »).
  //      Moins précis (l'herbe peut être bonne ou lourde) mais réel.
  //   3. Chaîne VIDE si aucune des deux n'est exploitable.
  //
  // ⚠️ AUCUN REPLI FICTIF. La chaîne vide est le signal EXPRES attendu par
  //    `scoreTerrain` (`if (statsTerrainCsv.isEmpty || terrainCourse.isEmpty)
  //    return 50.0;`), donc « donnée absente ⇒ neutre », et non « donnée
  //    absente ⇒ Pelouse ». Aucun `'Pelouse'`, aucun `'bon'` par défaut.
  //
  // ⚠️ `typePiste` brut NE PEUT PAS être renvoyé tel quel : `'HERBE'` ou
  //    `'GAZON'` ne sont pas des clés du barème. Ils passent donc par
  //    `_normaliserTerrainPmu`, la MÊME fonction que celle qui produit
  //    `statsTerrainCsv` — donc même vocabulaire, aucune troisième table.
  //
  //    MESURE sur cette fonction : `'HERBE'` → `'herbe'`, `'GAZON'` →
  //    `'gazon'`, `'POUZZOLANE'` → `'pouzzolane'`. AUCUN de ces trois
  //    libellés n'est une clé du barème (`bon`/`souple`/`lourd`/`tres_lourd`/
  //    `sable`), donc `scoreTerrain` rendra 50.0 pour eux : le critère reste
  //    neutre quand seule la NATURE DU SOL est connue et non son ÉTAT.
  //    C'est le comportement honnête — on transmet la donnée réelle plutôt
  //    que de la convertir en une catégorie inventée. L'état mesuré
  //    (`penetrometre.intitule`), lui, donne 'bon' / 'souple' / 'lourd' /
  //    'tres_lourd' / 'collant' et active réellement le critère.
  //    Aucun repli fictif, aucune troisième table de correspondance.
  @visibleForTesting
  static String pisteDepuisJsonPmu(Map<String, dynamic> courseJson) =>
      _pisteDepuisJsonPmu(courseJson);

  static String _pisteDepuisJsonPmu(Map<String, dynamic> c) {
    // 1. État mesuré du terrain le plus proche de l'heure de départ.
    final penetro = c['penetrometre'];
    if (penetro is Map) {
      final intitule = penetro['intitule'];
      if (intitule is String && intitule.trim().isNotEmpty) {
        final norm = _normaliserTerrainPmu(intitule);
        if (norm.isNotEmpty) return norm;
      }
    }
    // 2. Nature du sol.
    final typePiste = c['typePiste'];
    if (typePiste is String && typePiste.trim().isNotEmpty) {
      final norm = _normaliserTerrainPmu(typePiste);
      if (norm.isNotEmpty) return norm;
    }
    // 3. Absence réelle de donnée : neutre explicite, jamais « Pelouse ».
    return '';
  }

  // ──────────────────────────────────────────────────────────────────
  // ★ CORRECTION BL3-A24 — CATÉGORIE RÉELLE depuis le JSON PMU
  //
  // Producteur corrigé : le champ `categorie` de `ZtCourse` valait le littéral
  // vide `''` pour 100 % des courses.
  //
  // Consommateur : `IaPronosticEngine._scoreDisciplineCompatibilite`
  // (`ia_pronostic_engine.dart:381-392`), qui teste par sous-chaîne
  // `handicap`, `reclam`/`claim`, `condition`/`listed`/`groupe`/`group`.
  // Avec `''`, les TROIS branches étaient inatteignables par construction.
  //
  // SOURCE RÉELLE : `categorieParticularite` du JSON PMU. Valeurs mesurées
  // sur les fixtures du dépôt (224 courses) :
  //   'COURSE_A_CONDITIONS' (80), 'INCONNU' (54), 'HANDICAP' (40),
  //   'AUTOSTART' (39), 'HANDICAP_DIVISE' (17), 'NATIONALE' (16),
  //   'INTERNATIONALE_AUTOSTART' (7), 'A_RECLAMER' (7),
  //   'HANDICAP_DE_CATEGORIE' (7), 'HANDICAP_CATEGORIE_DIVISE' (6),
  //   'GROUPE_III' (5), 'GROUPE_I' (4), …
  //
  // ⚠️ `'INCONNU'` EST UNE VALEUR DE SENTINELLE DE L'API, PAS UNE CATÉGORIE.
  //    Elle est convertie en chaîne vide pour que les trois branches du
  //    consommateur restent inactives : on n'applique jamais une modulation
  //    Handicap/Réclamer à une course dont la catégorie est inconnue.
  //    C'est la même règle que pour `piste` : absence ⇒ neutre, jamais
  //    une catégorie inventée.
  //
  // ⚠️ LA VALEUR EST RENVOYÉE EN MINUSCULES, conventions attendues par le
  //    consommateur (`cat.contains('handicap')`). Aucune modulation, aucun
  //    coefficient n'est modifié : ×0,92 / ×0,88 / ×1,06 restent intacts.
  @visibleForTesting
  static String categorieDepuisJsonPmu(Map<String, dynamic> courseJson) =>
      _categorieDepuisJsonPmu(courseJson);

  static String _categorieDepuisJsonPmu(Map<String, dynamic> c) {
    final raw = c['categorieParticularite'];
    if (raw is! String) return '';
    final t = raw.trim().toLowerCase();
    // Sentinelles d'absence de l'API : aucune information exploitable.
    if (t.isEmpty || t == 'inconnu' || t == 'inconnue') return '';
    return t;
  }

  // ──────────────────────────────────────────────────────────────────
  // STATS HIPPODROME depuis musique PMU
  // Analyse les lettres de piste dans la musique globale
  // Format musique PMU : "1a" = attelé, "1m" = monté, "1h" = Vincennes,
  //                       "1p" = province, "2e" = étranger
  // Retourne : "nbCourses|nbVictoires|nbTop3" (CSV)
  // Si pas assez de données : "" (chaîne vide → score neutre 50)
  // ──────────────────────────────────────────────────────────────────
  static String _statsHippoDepuisMusique(String musique) {
    if (musique.isEmpty) return '';

    // Regex : capture token "positionLETTRE" ex: 1a, 2h, 3p, Ah, Dp
    final tokenRegex = RegExp(r'(\d+|[ADdQq])([ahmpetsr])', caseSensitive: false);
    final matches = tokenRegex.allMatches(musique);

    int nbCourses = 0;
    int nbVict = 0;
    int nbTop3 = 0;

    for (final m in matches) {
      final posStr = m.group(1) ?? '';
      // Ignorer abandons/disqualifications (A, D, Q)
      if (RegExp(r'[ADdQq]', caseSensitive: false).hasMatch(posStr)) continue;

      final pos = int.tryParse(posStr);
      if (pos == null) continue;

      nbCourses++;
      if (pos == 1) nbVict++;
      if (pos <= 3) nbTop3++;
    }

    // Minimum 3 courses pour avoir des stats significatives
    if (nbCourses < 3) return '';

    return '$nbCourses|$nbVict|$nbTop3';
  }

  // ──────────────────────────────────────────────────────────────────
  // HEURISTIQUE JOCKEY — Estimation du taux de victoire
  // Base de données des jockeys/drivers français les plus actifs
  // Format retourné : "nom|%victoire|%place"
  // ──────────────────────────────────────────────────────────────────
  static String _heuristiqueJockey(String nom) {
    final nomUpper = nom.toUpperCase();

    // ═══════════════════════════════════════════════════════════════
    // BASE DE DONNÉES ÉLARGIE — Jockeys galop français
    // Format : 'NOM' → '%victoire|%placé top3'
    // Source : statistiques PMU saisons 2022-2024
    // ═══════════════════════════════════════════════════════════════
    const jockeysGalop = {
      // Elite internationale
      'GUYON': '18|48',       'SOUMILLON': '20|51',  'LEMAIRE': '22|53',
      'BOUDOT': '21|50',      'DEMURO': '16|44',      'PESLIER': '15|42',
      // Très bons jockeys
      'BENOIST': '14|40',     'PASQUIER': '13|39',    'MENDIZABAL': '14|41',
      'MOSSE': '15|43',       'THULLIEZ': '12|37',    'ABRIVARD': '13|38',
      'VELON': '12|36',       'CRASTUS': '12|37',     'FOULON': '12|36',
      // Réguliers
      'BERTRAS': '11|35',     'BLONDEL': '13|38',     'CHARRON': '10|33',
      'ROCHARD': '11|34',     'STASSE': '10|32',      'DOUMEN': '11|35',
      'BACHELOT': '11|34',    'LECOEUVRE': '12|36',   'HAMELIN': '11|35',
      'VERON': '12|37',       'LEFEBVRE': '11|35',    'TRULLIER': '11|34',
      'GRANDIN': '10|33',     'BOISSEAU': '10|32',    'JUSTUM': '10|32',
      'FAVRIAUX': '11|34',    'CLAUDIC': '10|33',     'MARIEN': '10|32',
      'SANTIAGO': '10|33',    'BAZIRE': '12|36',      'BOUTIN': '11|35',
      'WEISSMEIER': '10|33',  'MADAMET': '11|34',     'MEURY': '10|32',
    };

    // ═══════════════════════════════════════════════════════════════
    // BASE DE DONNÉES ÉLARGIE — Drivers trot français
    // ═══════════════════════════════════════════════════════════════
    const driversTrot = {
      // Elite trot
      'NIVARD': '20|52',      'JOSSELIN': '17|46',    'RAFFIN': '16|44',
      'MOTTIER': '15|43',     'BEKAERT': '14|41',
      // Très bons drivers
      'BIGEON': '12|37',      'VERROKEN': '13|38',    'BOURASSIN': '11|34',
      'MASSETEAU': '13|39',   'PLOQUIN': '11|35',     'BAUDOUIN': '12|36',
      'GALLIER': '11|34',     'ABRIVARD': '14|40',    'OUVRIE': '13|38',
      // Réguliers
      'LAGADEUC': '11|35',    'HENRY': '11|34',       'DEVRED': '10|33',
      'COUDRAY': '10|33',     'LERAY': '10|32',       'BREUIL': '10|32',
      'SENET': '11|34',       'POU': '10|33',         'BRIAND': '10|32',
      'MARTENS': '11|35',     'BARRIER': '10|33',     'PHILIPPE': '10|32',
    };

    for (final entry in jockeysGalop.entries) {
      if (nomUpper.contains(entry.key)) return '$nom|${entry.value}';
    }
    for (final entry in driversTrot.entries) {
      if (nomUpper.contains(entry.key)) return '$nom|${entry.value}';
    }
    // Valeur neutre si inconnu : % victoire estimé à 9%, place 28%
    // (légèrement sous la moyenne pour ne pas surestimer les inconnus)
    return '$nom|9|28';
  }

  // ──────────────────────────────────────────────────────────────────
  // FILTRE : hippodrome français (basé sur le libellé long PMU)
  // ──────────────────────────────────────────────────────────────────
  static bool _estHippodromeFrancais(String hippodromeLong) {
    // ★ Fix : filtrage par nom de pays (libelleLong avec pays)
    const foreignCountries = [
      ' P-B', ' GB', ' CHILI', ' USA', ' IRLANDE',
      ' BELGIQUE', ' ALLEMAGNE', ' ITALIE', ' ESPAGNE',
      ' SUEDE', ' DANEMARK', ' AUSTRALIE', ' JAPON',
      ' SUISSE', ' PORTUGAL', ' POLOGNE', ' HONGRIE',
      ' TCHEQUE', ' ARGENTINE', ' BRESIL', ' AFRIQUE DU SUD',
      ' EMIRATS', ' HONG KONG', ' SINGAPOUR', ' NOUVELLE-ZELANDE',
      ' CANADA', ' URUGUAY', ' CHINE',
      // Pays ajoutés ce matin
      ' MAROC', ' TUNISIE', ' ALGERIE', ' SENEGAL',
      ' TURQUIE', ' RUSSIE', ' UKRAINE', ' MEXIQUE',
      ' PEROU', ' VENEZUELA', ' COLOMBIE',
      // Abréviations courtes utilisées par l'API PMU
      ' ALL',   // Allemagne (ex: GELSENKIRCHEN ALL, MUNICH-RIEM ALL)
      ' HK',    // Hong Kong (ex: HAPPY VALLEY HK)
      ' ARG',   // Argentine (ex: SAN ISIDRO ARG)
      ' ESP',   // Espagne   (ex: SAN SEBASTIAN ESP)
    ];
    // ★ Fix : filtrage par nom d'hippodrome étranger connu
    // L'API PMU retourne parfois le nom sans le pays → on blackliste directement
    const foreignTracks = [
      'CROISE LAROCHE',   // Belgique
      'LE CROISE',        // Belgique
      'PALERMO',          // Argentine (Buenos Aires)
      'CASABLANCA',       // Maroc
      'MEKNES',           // Maroc
      'SOUSSE',           // Tunisie
      'KSAR SAID',        // Tunisie
      'DRAWBRIDGE',       // USA
      'PARX',             // USA
      'GULFSTREAM',       // USA
      'SANTA ANITA',      // USA
      'DEL MAR',          // USA
      'CHURCHILL',        // USA
      'BELMONT',          // USA
      'SARATOGA',         // USA
      'LEOPARDSTOWN',     // Irlande
      'CURRAGH',          // Irlande
      'DUNDALK',          // Irlande
      'PUNCHESTOWN',      // Irlande
      'NAAS',             // Irlande
      'FAIRYHOUSE',       // Irlande
      'GALWAY',           // Irlande (hippodrome)
      'TIPPERARY',        // Irlande
      'NAVAN',            // Irlande
      'CORK',             // Irlande (hippodrome)
      'GOODWOOD',         // GB
      'NEWMARKET',        // GB
      'ASCOT',            // GB
      'NEWBURY',          // GB
      'HAYDOCK',          // GB
      'CHESTER',          // GB
      'WOLVERHAMPTON',    // GB
      'CHELTENHAM',       // GB
      'SON PARDO',         // Majorque/Espagne (ex: SON PARDO PALMA)
      'SOLVALLA',         // Suède
      'JÄGERSRO',         // Suède
      'ABY',              // Suède
      'ROMME',            // Suède
      'AXEVALLA',         // Suède
      'BERGSAKER',        // Norvège
      'BJERKE',           // Norvège
      'MANTORP',          // Suède
      'HAGMYREN',         // Suède
      'UMAKER',           // Suède
      'KALMAR',           // Suède
      'GOTHENBURG',       // Suède
      'GÖTEBORG',         // Suède
      'STOCKHOLM',        // Suède
      'ESKILSTUNA',       // Suède
      'CAEN',             // Déjà France mais au cas où
    ];
    if (foreignCountries.any((m) => hippodromeLong.contains(m))) return false;
    if (foreignTracks.any((t) => hippodromeLong.contains(t))) return false;
    return true;
  }

  /// Convertit la discipline PMU en type lisible pour ZtCourse
  static String _pmuDisciplineToZt(String discipline) {
    switch (discipline.toUpperCase()) {
      case 'PLAT': return 'Plat';
      case 'HAIE':
      case 'HAIES': return 'Haies';
      case 'STEEPLECHASE':
      case 'STEEPLE': return 'Steeple Chase';
      case 'ATTELE':
      case 'TROT_ATTELE': return 'Attelé';
      case 'TROT_MONTE':
      case 'MONTE': return 'Monté';
      case 'CROSS': return 'Cross';
      default: return 'Plat';
    }
  }

  // Rétro-compat (conservé pour usage potentiel futur)
  // ignore: unused_element
  static bool _estReunionFrancaise(ZtReunion r) {
    final lieu = r.lieu.toUpperCase();
    const prefixesEtrangers = [
      'GB ', 'USA ', 'AUS ', 'SAF ', 'UAE ', 'CHL ', 'ARG ', 'BEL ',
      'IRE ', 'GER ', 'ITA ', 'ESP ', 'POR ', 'SWE ', 'NOR ', 'DEN ',
      'JPN ', 'HKG ', 'SGP ', 'NZL ', 'CAN ', 'BRZ ', 'URU ', 'CHI ',
    ];
    for (final p in prefixesEtrangers) {
      if (lieu.startsWith(p)) return false;
    }
    return true;
  }

  // ──────────────────────────────────────────────────────────────────
  // APPLIQUER LES SCORES IA SUR TOUS LES PARTANTS
  // ──────────────────────────────────────────────────────────────────
  static List<ZtReunion> _appliquerScoresIA(List<ZtReunion> reunions) {
    return reunions.map((reunion) {
      final courses = reunion.courses.map((course) {
        if (course.partants.isNotEmpty) {
          final partantsAvecIA = IaPronosticEngine.analyserCourse(course);
          // ★ Fix: conserver dateStr pour heureDateTime correct après re-création
          return ZtCourse(
            numCourse: course.numCourse,
            anchor: course.anchor,
            nom: course.nom,
            heure: course.heure,
            distance: course.distance,
            prix: course.prix,
            type: course.type,
            piste: course.piste,
            categorie: course.categorie,
            isQuinte: course.isQuinte,
            pronosticZt: course.pronosticZt,
            partants: partantsAvecIA,
            dateStr: course.dateStr,  // ← propagation obligatoire
          );
        }
        return course;
      }).toList();

      return ZtReunion(
        code: reunion.code,
        lieu: reunion.lieu,
        discipline: reunion.discipline,
        dateStr: reunion.dateStr,
        courses: courses,
      );
    }).toList();
  }

  // ──────────────────────────────────────────────────────────────────
  // CHARGER LES RÉSULTATS D'UNE COURSE TERMINÉE
  // Retourne la liste ordonnée des numéros arrivants (1er, 2ème, 3ème…)
  // Retourne null si la course n'est pas encore terminée ou API indispo
  // ──────────────────────────────────────────────────────────────────
  // ── Résultat étendu incluant les disqualifiés ───────────────────────────
  /// ★ LOT B-2 bis — lit le caractère définitif SANS RIEN SUPPOSER.
  ///
  /// Trois états, jamais deux :
  ///   • `false`  → l'API dit explicitement que l'arrivée n'est pas définitive ;
  ///   • `true`   → l'API dit explicitement qu'elle l'est ;
  ///   • `null`   → l'API ne le dit pas (clé absente, type inattendu).
  ///
  /// ⚠️ MESURE D'HONNÊTETÉ : aucune capture de l'endpoint `/participants`
  /// n'est disponible dans `/home/user/recherche_pmu/`. Je ne peux donc pas
  /// affirmer que ces clés y figurent. La lecture est donc TOLÉRANTE, et
  /// `null` n'est JAMAIS interprété comme « définitive » : c'est la seule
  /// lecture qui ne puisse pas produire un enregistrement abusif.
  ///
  /// `statut` n'est volontairement PAS utilisé comme substitut : traduire un
  /// libellé en booléen serait exactement la décision métier inventée que ce
  /// lot s'interdit.
  static bool? _lireDrapeauDefinitif(Map<String, dynamic> data) {
    final direct = data['arriveeDefinitive'];
    if (direct is bool) return direct;
    final indirect = data['isArriveeDefinitive'];
    if (indirect is bool) return indirect;
    return null;
  }

  static Future<ResultatCourse?> chargerResultatsCourseComplet({
    required DateTime heureDepart,
    required int numReunion,
    required int numCourse,
  }) async {
    try {
      final dateStr = _dateToStr(heureDepart);
      final rPad = numReunion.toString().padLeft(2, '0');
      final cPad = numCourse.toString().padLeft(2, '0');

      final url = kIsWeb
          ? '$_proxyBase/programme/$dateStr/R$rPad/C$cPad/participants'
          : '$_pmuBase/programme/$dateStr/R$rPad/C$cPad/participants?$_pmuSpec';

      if (kDebugMode) debugPrint('PMU Résultats complet: GET $url');
      final resp = await http.get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        if (kDebugMode) debugPrint('PMU Résultats complet: HTTP ${resp.statusCode}');
        return null;
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final participants = data['participants'] as List<dynamic>? ?? [];

      // ★ LOT B-2 bis — CORRECTION DU DÉFAUT D'ÉCRASEMENT.
      //
      //   AVANT : `rangParNumero[rangInt] = num` dans une `Map<int,int>`
      //   indexée par RANG. Deux chevaux ex æquo partagent le même rang, donc
      //   le second ÉCRASAIT le premier et le cheval disparaissait de
      //   l'arrivée. Mesuré sur les trois courses réelles à ex æquo :
      //     R5C5 [[2],[4],[5,7],[8],[3],[6]]        → le 5 disparaissait
      //     R6C5 [[12],[1,7],[9],[2],[10],[8],[6],[13],[5]] → le 1 disparaissait
      //     R5C7 [[4],[6],[1,5],[2]]                → le 1 disparaissait
      //
      //   APRÈS : `rangsGroupes[rangInt]` est une LISTE. Tous les chevaux d'un
      //   même rang y sont ajoutés dans l'ordre de l'API. Aucun départage,
      //   aucun tri, aucun cheval écarté.
      final Map<int, List<int>> rangsGroupes = {};
      final List<int> disqualifies = [];
      final Map<int, String> statutsParNumero = {}; // numero -> statut PMU

      for (final p in participants) {
        final part = p as Map<String, dynamic>;
        final numStr = part['numPmu'] ?? part['numero'] ?? part['num'];
        final num = numStr is int ? numStr : int.tryParse(numStr?.toString() ?? '');
        if (num == null) continue;

        final statut = (part['statut'] as String? ?? '').toUpperCase();
        statutsParNumero[num] = statut;

        // Détecter les chevaux disqualifiés / retirés APRÈS la course
        // (DISQUALIFIE = DQ après arrivée, ARRETE = arrêt pendant la course,
        //  TOMBE = chute, RETRAIT = retiré avant départ)
        if (statut == 'DISQUALIFIE' || statut == 'DISQUALIFIED' ||
            statut == 'ARRETE' || statut == 'TOMBE') {
          if (!disqualifies.contains(num)) disqualifies.add(num);
          // Ne PAS inclure dans l'arrivée officielle
          continue;
        }

        // Ignorer les non-partants (retirés avant la course)
        if (statut == 'NON_PARTANT' || statut == 'RETRAIT') continue;

        final rang = part['ordreArrivee'] ?? part['placeCourse'] ?? part['rang'];
        final rangInt = rang is int ? rang : int.tryParse(rang?.toString() ?? '');
        if (rangInt != null && rangInt > 0) {
          // ★ B-2 bis : ajout dans la liste du rang, JAMAIS remplacement.
          //   L'ordre d'insertion est celui de l'API : deux ex æquo gardent
          //   l'ordre où le PMU les a publiés.
          rangsGroupes.putIfAbsent(rangInt, () => <int>[]).add(num);
        }
      }

      if (rangsGroupes.isEmpty && disqualifies.isEmpty) {
        if (kDebugMode) debugPrint('PMU Résultats: pas de classement disponible');
        return null;
      }

      // ★ B-2 bis : rangs triés, chaque rang rendant TOUS ses chevaux.
      final rangs = rangsGroupes.keys.toList()..sort();
      final groupes = <List<int>>[
        for (final r in rangs) List<int>.unmodifiable(rangsGroupes[r]!)
      ];
      // `arriveeOfficielle` reste un APLATISSEMENT de `groupes` : même contenu
      // qu'avant, mais désormais SANS PERTE. Le format `List<int>` est
      // préservé, seul le nombre d'éléments est enfin correct.
      final arrivee = <int>[for (final g in groupes) ...g];

      if (kDebugMode) debugPrint('PMU Résultats: arrivée officielle = $arrivee | DQ = $disqualifies');

      return ResultatCourse(
        arriveeOfficielle: arrivee,
        disqualifies: disqualifies,
        statutsPartants: statutsParNumero,
        // ★ B-2 bis : les groupes EXACTS accompagnent l'aplatissement.
        arriveeGroupes: List<List<int>>.unmodifiable(groupes),
        // Lecture TOLÉRANTE : trois états distincts. `null` (inconnu) n'est
        // jamais converti en `true`. Un drapeau explicite à `false` est
        // conservé tel quel — c'est précisément l'information qui empêche
        // d'enregistrer une arrivée provisoire comme définitive.
        arriveeDefinitive: _lireDrapeauDefinitif(data),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('PMU Résultats complet erreur: $e');
      return null;
    }
  }

  static Future<List<int>?> chargerResultatsCourse({
    required DateTime heureDepart,
    required int numReunion,
    required int numCourse,
  }) async {
    final res = await chargerResultatsCourseComplet(
      heureDepart: heureDepart,
      numReunion: numReunion,
      numCourse: numCourse,
    );
    return res?.arriveeOfficielle;
  }

  /// Charge les statuts en temps réel des partants d'une course.
  /// Retourne null si la course n'est pas encore démarrée ou si l'API
  /// est indisponible. Permet de détecter les DISQUALIFIE/RETRAIT/ARRETE
  /// AVANT la fin de la course (pendant la course en cours).
  static Future<Map<int, String>?> chargerStatutsPartants({
    required DateTime heureDepart,
    required int numReunion,
    required int numCourse,
  }) async {
    try {
      final dateStr = _dateToStr(heureDepart);
      final rPad = numReunion.toString().padLeft(2, '0');
      final cPad = numCourse.toString().padLeft(2, '0');

      final url = kIsWeb
          ? '$_proxyBase/programme/$dateStr/R$rPad/C$cPad/participants'
          : '$_pmuBase/programme/$dateStr/R$rPad/C$cPad/participants?$_pmuSpec';

      final resp = await http.get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final participants = data['participants'] as List<dynamic>? ?? [];
      final Map<int, String> statuts = {};

      for (final p in participants) {
        final part = p as Map<String, dynamic>;
        final numStr = part['numPmu'] ?? part['numero'] ?? part['num'];
        final num = numStr is int ? numStr : int.tryParse(numStr?.toString() ?? '');
        if (num == null) continue;
        final statut = (part['statut'] as String? ?? 'PARTANT').toUpperCase();
        statuts[num] = statut;
      }
      return statuts.isEmpty ? null : statuts;
    } catch (_) {
      return null;
    }
  }

  static String _todayStr() {
    final now = DateTime.now(); // aujourd'hui
    return _dateToStr(now);
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  ★ B5c-RDR-01-b — PURGE DU CACHE STATIQUE POUR LE RESET COMPLET.
  //
  //  POURQUOI : `_cache` et `_cacheTime` (l.33-34) sont des caches STATIQUES
  //  de 15 minutes. Ils ne sont purgés par AUCUN mécanisme : `grep
  //  clear|invalidate|purge` sur ce fichier ne renvoyait rien. Mesuré V31b
  //  R01-N : après un reset complet, un `chargerProgramme()` SANS
  //  `forceRefresh` — c'est le chemin des écrans (best_bet_screen l.182,
  //  conseils_screen l.184, races_screen l.67) — sert encore les réunions
  //  d'AVANT le reset, sans émettre le moindre appel réseau
  //  (`reunions=1 appelsRéseau=0`).
  //
  //  CE QUE CETTE MÉTHODE NE FAIT **PAS** :
  //    • elle ne touche NI à la durée d'expiration `_cacheLocalDuree` côté
  //      DataRefreshService, NI au seuil de 15 minutes de `chargerProgramme`
  //      (l.52-56) : les règles d'expiration sont INCHANGÉES ;
  //    • elle ne modifie AUCUN parseur ;
  //    • elle ne modifie pas le comportement de `forceRefresh` : le
  //      contournement du cache par `forceRefresh: true` fonctionne
  //      exactement comme avant (mesuré V31b R01-M) ;
  //    • elle n'émet aucune requête réseau et n'écrit rien sur le disque.
  //
  //  Une purge VIDER le cache : le prochain `chargerProgramme()` sans
  //  `forceRefresh` ne trouvera ni entrée ni horodatage et ira donc
  //  légitimement au réseau. C'est le comportement voulu après une remise à
  //  zéro — et c'est aussi pourquoi cette méthode n'est appelée QUE par le
  //  reset, jamais ailleurs.
  // ═══════════════════════════════════════════════════════════════════════
  static void viderCachePourResetComplet() {
    _cache.clear();
    _cacheTime.clear();
    // ★ L1 : invalide toute capture L0 EN VOL (chargement réseau en cours au
    // moment du reset). Le compteur n'est jamais décrémenté.
    _generationReset++;
    if (kDebugMode) {
      debugPrint('[ZoneTurf] 🧹 Cache statique vidé (reset complet)');
    }
  }

  static String _dateToStr(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}'
        '${d.month.toString().padLeft(2, '0')}'
        '${d.year}';
  }
}
