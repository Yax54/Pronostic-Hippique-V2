// ═══════════════════════════════════════════════════════════════════
//  ZONE-TURF SERVICE — Données réelles via API PMU officielle
//  ⚠️ L'ancien proxy Python (localhost:5060) ne fonctionnait pas sur
//     mobile Android. Ce service utilise maintenant l'API PMU directement.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/zt_models.dart';
import '../data/connaissances/_services/corpus_performances.dart';
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

  // ── Cache des HISTORIQUES DÉTAILLÉS (`performances-detaillees/pretty`) ──
  //
  //   MESURES QUI JUSTIFIENT CE CACHE (mesurées le 26/11/2026, pas supposées):
  //     • `/programme/{date}/R{n}/performances-detaillees/pretty`  → HTTP 420
  //     • `/programme/{date}/performances-detaillees/pretty`       → HTTP 420
  //     • `/programme/{date}/R{n}/C{n}/performances-detaillees/pretty` → HTTP 200
  //   ⇒ AUCUNE mutualisation par réunion ni par journée n'est possible. Le seul
  //     niveau servi est celui de la COURSE (~47 Ko dans le cas mesuré).
  //
  //   CONSÉQUENCE ASSUMÉE ET MESURÉE : l'enrichissement coûte UN appel réseau
  //   supplémentaire PAR COURSE. Sans ce cache, un simple rafraîchissement de
  //   l'écran d'accueil (qui relit tout le programme) rejouerait 50 requêtes
  //   pour un programme de 50 courses. Le cache évite cela : une même course
  //   n'est téléchargée qu'une fois par fenêtre de validité.
  //
  //   Clé = `{dateStr}/R{nR}/C{nC}` — même identité que l'URL, donc aucune
  //   collision entre deux courses de même numéro sur des dates différentes.
  static final Map<String, Map<String, _HistoCheval>> _cachePerfDetail = {};
  static final Map<String, DateTime> _cachePerfDetailTime = {};

  // Composition des courses : PLUS AUCUN FICHIER.
  //
  // Historique de la correction, parce qu'elle est instructive :
  //   1. la composition vivait d'abord dans une map en mémoire → vidée par
  //      tout reset, corpus inexploitable hors ligne (mesuré : 0 critère
  //      alimenté sur 14 partants) ;
  //   2. elle a été déplacée dans `cache/index_noms_partants.json` → le
  //      problème du reset était réglé, mais la connaissance permanente
  //      dépendait d'un dossier JETABLE, ce qui est une faute de conception :
  //      vider `cache/` rendait le corpus muet ;
  //   3. elle est désormais stockée en SQLite, dans la table `observations`
  //      (déclarée PERMANENTE : jamais purgée, sauvegardée et restaurée avec
  //      le reste, indexée sur `id_course`).
  //
  // Elle est donc AUTOMATIQUEMENT RECONSTRUCTIBLE depuis la base : aucun
  // fichier temporaire n'est nécessaire, et aucun nettoyage de cache ne peut
  // rendre les connaissances inaccessibles.

  /// Durée de validité du cache d'historiques. Alignée sur la sémantique du
  /// cache de programme (15 min) : un historique de courses PASSÉES ne change
  /// plus, mais le cache reste borné pour ne pas retenir indéfiniment un
  /// programme dont la journée est terminée.
  static const Duration _ttlPerfDetail = Duration(minutes: 20);

  /// Nombre d'appels réseau réellement effectués vers
  /// `performances-detaillees/pretty` depuis le démarrage du processus.
  /// Sert UNIQUEMENT à mesurer le coût réel de l'enrichissement (tests et
  /// rapport d'audit). Ne conditionne aucune décision métier.
  static int _nbAppelsPerfDetail = 0;
  @visibleForTesting
  static int get nbAppelsPerfDetail => _nbAppelsPerfDetail;
  @visibleForTesting
  static void reinitialiserCompteurPerfDetail() {
    _nbAppelsPerfDetail = 0;
  }

  /// Hippodrome de la course en cours de chargement, renseigné par
  /// `chargerProgramme` juste avant d'appeler `_chargerPartants`.
  ///
  /// Pourquoi un champ statique plutôt qu'un paramètre : `_chargerPartants`
  /// est appelé depuis la boucle de `chargerProgramme`, qui dispose déjà du
  /// libellé de la réunion (`lieu`). Ajouter un paramètre aurait modifié la
  /// signature d'une méthode appelée depuis un seul endroit, mais ce champ
  /// évite de propager un 5ᵉ argument à travers un appel déjà dense. Il est
  /// réinitialisé à chaque réunion pour ne jamais fuiter d'une course à
  /// l'autre.
  static String? _hippodromeCourant;

  /// Distance (en mètres) de la course en cours de chargement, renseignée par
  /// `chargerProgramme` avant l'appel à `_chargerPartants`. Sert au filtre
  /// ±100 m de la musique par distance.
  static int? _distanceCourante;

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

      final progResp = await http
          .get(Uri.parse(progUrl), headers: _headers)
          .timeout(const Duration(seconds: 20));

      if (progResp.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('PMU API erreur programme: HTTP ${progResp.statusCode}');
        }
        return []; // ★ v91 : pas de données fictives — erreur réelle
      }

      final progData = jsonDecode(progResp.body) as Map<String, dynamic>;
      final reunionsJson =
          (progData['programme']?['reunions'] as List<dynamic>? ?? []);

      if (reunionsJson.isEmpty) {
        if (kDebugMode) {
          debugPrint('PMU API: aucune réunion trouvée pour $dateStr');
        }
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
        final hippodromeLong =
            (hippo['libelleLong'] as String? ?? '').toUpperCase();

        // Filtrer les réunions étrangères
        if (!_estHippodromeFrancais(hippodromeLong)) continue;

        final lieu = hippo['libelleCourt'] as String? ??
            hippo['libelle'] as String? ??
            'Inconnu';
        final numOfficiel = r['numOfficiel'] as int? ?? 0;
        final coursesJson = (r['courses'] as List<dynamic>? ?? []);

        // ★ ENRICHISSEMENT — hippodrome RÉEL de la réunion, exposé au
        //   chargement des partants pour alimenter le critère `hippodrome`.
        //   Source : `hippodrome.libelleCourt` du JSON `/programme/{date}`,
        //   c'est-à-dire exactement le même libellé que celui publié dans
        //   `coursesCourues[].hippodrome` des historiques détaillés (mesuré :
        //   « PORNICHET » dans les deux sources pour la même réunion).
        _hippodromeCourant = lieu;

        // Déduire la discipline principale
        String discipline = 'Plat';
        if (coursesJson.isNotEmpty) {
          final disc0 = (coursesJson.first
                  as Map<String, dynamic>)['discipline'] as String? ??
              '';
          discipline = _pmuDisciplineToZt(disc0);
        }

        // ── Étape 3 : charger les partants pour chaque course ────────
        final List<ZtCourse> courses = [];
        for (final cJson in coursesJson) {
          final c = cJson as Map<String, dynamic>;
          final numOrdre = c['numOrdre'] as int? ?? 0;
          final nomCourse =
              c['libelle'] as String? ?? c['libelleCourt'] as String? ?? '';
          final distanceM = c['distance'] as int? ?? 0;
          final montant = c['montantPrix'] as int? ?? 0;
          final disc = _pmuDisciplineToZt(c['discipline'] as String? ?? '');
          // ★ v9.98 : categorieSpeciale n'existe PAS dans l'API PMU réelle.
          // La détection Quinté/Quarté se fait via la liste paris[].typePari.
          final pariTypes = (c['paris'] as List<dynamic>? ?? [])
              .map((p) =>
                  (p as Map<String, dynamic>)['typePari'] as String? ?? '')
              .toList();
          final isQuinte = pariTypes.contains('E_QUINTE_PLUS');
          final isQuarte = pariTypes.contains('E_QUARTE_PLUS') && !isQuinte;

          // ★ v9.93 : Détecter les courses classiques sans Quarté/Quinté
          // (Groupe 1/2/3, Poule d'Essai, etc.) — PMU ne publie que le Tiercé
          // catSpec basé sur pariTypes maintenant (categorieSpeciale absent de l'API)
          final catSpec = pariTypes.join(' ');
          final nomUpper = nomCourse.toUpperCase();
          final isClassiqueSansMultiple = !isQuinte &&
              !isQuarte &&
              (disc == 'Plat' || disc == 'PLAT') &&
              montant >= 80000 &&
              // Pas de categorieSpeciale QUARTE/QUINTE = confirmation pas de paris multiples
              !catSpec.contains('QUARTE') &&
              !catSpec.contains('QUINTE') &&
              // Mots-clés des grandes courses classiques françaises
              (nomUpper.contains('GROUPE') ||
                  nomUpper.contains('GROUP') ||
                  nomUpper.contains('POULE') ||
                  nomUpper.contains("ARC DE") ||
                  nomUpper.contains('JOCKEY CLUB') ||
                  nomUpper.contains('DIANE') ||
                  nomUpper.contains('VERMEILLE') ||
                  nomUpper.contains('CADRAN') ||
                  nomUpper.contains('ROYAL OAK') ||
                  nomUpper.contains('MORNY') ||
                  nomUpper.contains('JEAN-LUC LAG') ||
                  nomUpper.contains('GANAY') ||
                  nomUpper.contains('OPÉRA') ||
                  nomUpper.contains('OPERA') ||
                  nomUpper.contains('CHAMPION') ||
                  nomUpper.contains('DERBY') ||
                  (montant >=
                      200000)); // Dotation très élevée = grande course classique

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
          _distanceCourante = distanceM;
          final List<ZtPartant> partants =
              await _chargerPartants(dateStr, numOfficiel, numOrdre, heureDt);

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
            dateStr: dateStr, // ← date réelle pour heureDateTime correct
            // ★ CORRECTION BLOC 1 — le drapeau définitif est capturé ICI, sur
            //   l'objet course du JSON, donc là où le PMU le publie. Aucune
            //   requête supplémentaire : `c` EST déjà le JSON de la course.
            arriveeDefinitive: _lireDrapeauDefinitif(c),
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
        if (kDebugMode) {
          debugPrint('PMU API: 0 réunion française après filtrage');
        }
        return []; // ★ v91 : aucune course française aujourd'hui
      }

      // Appliquer les scores IA
      final withIA = _appliquerScoresIA(reunions);
      _cache[dateStr] = withIA;
      _cacheTime[dateStr] = DateTime.now();

      if (kDebugMode) {
        debugPrint(
            'PMU API: ${withIA.length} réunions françaises chargées pour $dateStr');
      }
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
      // ★ ENRICHISSEMENT — HISTORIQUES DÉTAILLÉS (`performances-detaillees`)
      //
      //   Chargé AVANT la boucle des partants, une seule fois par course, et
      //   servi depuis le cache si la course a déjà été vue dans la fenêtre
      //   de validité (voir `_chargerPerformancesDetaillees`).
      //
      //   ⚠️ COÛT RÉEL ASSUMÉ : +1 requête réseau PAR COURSE (mesuré : la
      //      mutualisation par réunion et par journée renvoie HTTP 420). Le
      //      cache garantit qu'un rafraîchissement ne rejoue pas ces requêtes.
      //
      //   ⚠️ DÉGRADATION MAÎTRISÉE : cette map peut être VIDE (réseau, délai,
      //      JSON). Dans ce cas les critères concernés restent neutres selon
      //      leur définition, sans qu'aucune valeur ne soit inventée.
      final histos = await _chargerPerformancesDetaillees(
        dateStr,
        numR,
        numC,
        // Noms mémorisés lors d'un chargement précédent de CETTE course,
        // relus depuis l'INDEX DURABLE : ils survivent au reset du cache et au
        // redémarrage, et rendent le repli local réellement opérant.
        nomsParNumero: await CorpusPerformancesService.instance
            .chargerComposition(dateStr: dateStr, numR: numR, numC: numC),
      );

      // Hippodrome RÉEL de la course analysée, nécessaire au critère
      // `hippodrome` (comparer le passé sur le MÊME hippodrome). Renseigné par
      // `chargerProgramme` avant l'appel ; vide = non déterminé.
      final hippodromeCourse = _hippodromeCourant ?? '';

      final url = kIsWeb
          ? '${Uri.base.origin}/api/pmu/programme/$dateStr/R$numR/C$numC/participants'
          : '$_pmuBase/programme/$dateStr/R$numR/C$numC/participants?$_pmuSpec';

      final resp = await http
          .get(Uri.parse(url), headers: _headers)
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
        final gainsCarriereRaw = ((pm['gainsParticipant']
                    as Map<String, dynamic>?)?['gainsCarriere'] as num?)
                ?.toDouble() ??
            0.0;
        // Heuristique : si le montant est > 10000 → probable centimes → convertir
        final gainsCarriere = gainsCarriereRaw > 10000
            ? gainsCarriereRaw / 100.0
            : gainsCarriereRaw;

        final age = pm['age'] as int? ?? 0;
        final sexe = pm['sexe'] as String? ?? '';

        // ── ENRICHISSEMENT IA — NOUVEAUX CHAMPS ────────────────────────
        // A) POIDS PORTÉ — `handicapPoids` est en DIXIÈMES DE KILOGRAMME.
        //
        //    ⚠️ DÉFAUT MESURÉ ET CORRIGÉ : le code divisait par 1000, ce qui
        //       produisait des poids de 0,58 kg — manifestement incohérent et
        //       souligné au §10 du mandat.
        //
        //    PREUVE DE L'UNITÉ, PAR RECOUPEMENT AVEC UNE SOURCE INDÉPENDANTE.
        //    La course du 14/11/2026 R6C6 (PORNICHET, 1 700 m, PLAT) est la
        //    dernière course réellement disputée par VIKTOR RAPIDE. Pour cette
        //    MÊME course, deux sources PMU distinctes publient :
        //      • `/participants`          → `handicapPoids` (entier)
        //      • `performances-detaillees` → `poidsJockey` (réel, en kg)
        //    Résultat mesuré, 6 chevaux présents dans les deux sources :
        //
        //      MELEKS          580 → 58.0  | poidsJockey réel 58.0  ✔
        //      VIKTOR RAPIDE   580 → 58.0  | poidsJockey réel 58.0  ✔
        //      YES OR NO       565 → 56.5  | poidsJockey réel 56.5  ✔
        //      ACQUIRED        565 → 56.5  | poidsJockey réel 56.5  ✔
        //      VENETIAN BELLE  565 → 56.5  | poidsJockey réel 56.5  ✔
        //      BREIZH STORY    565 → 56.5  | poidsJockey réel 56.5  ✔
        //
        //    6 concordances sur 6. Une division par 100 donnerait 5,8 kg
        //    (enfant), par 1000 donnerait 0,58 kg (absurde). L'unité est donc
        //    le dixième de kilogramme, et la division correcte est par 10.
        //    Recoupement complémentaire : le trot monté publie 630, 620, 560,
        //    valeurs dans la plage réelle des poids de monte.
        //
        //    ⚠️ DISTINCTION EXIGÉE PAR LE §10, CONSERVÉE :
        //      • `handicapPoids`      = POIDS PORTÉ (ce qui est lu ici) ;
        //      • `handicapValeur`     = VALEUR de handicap (ex. 23,5) — ce
        //                               n'est PAS un poids, jamais converti ;
        //      • `poidsConditionMonte`= poids de condition (ex. 555 → 55,5 kg),
        //                               distinct et plus léger (mesuré : 530
        //                               pour ACQUIRED contre 565 de poids porté).
        //      Seul `handicapPoids` alimente `poids`, donc `scorePoids`.
        //
        //    ⚠️ AUCUNE FORMULE TOUCHÉE. `scorePoids`, son coefficient
        //       `poidsRel: 0.03` et sa neutralité hors galop sont intacts.
        //       Seule la CONVERSION D'UNITÉ est corrigée.
        final poidsDixiemesKg = (pm['handicapPoids'] as num?)?.toDouble() ?? 0.0;
        final poidsKg = poidsDixiemesKg > 0 ? poidsDixiemesKg / 10.0 : 0.0;

        // A2) RECORD PERSONNEL DU CHEVAL — Extraire depuis l'API PMU
        // L'API expose 'recordAbsolu' ou dans 'performances' le meilleur temps
        String recordStr = '';
        final recordAbsolu = pm['recordAbsolu'];
        if (recordAbsolu is Map) {
          // Format API : { "temps": 89.4, "distance": 1800 } ou { "tempsEnSecondes": 89.4 }
          final tempsSecondes = (recordAbsolu['temps'] as num?)?.toDouble() ??
              (recordAbsolu['tempsEnSecondes'] as num?)?.toDouble() ??
              0.0;
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
                final t = (perf['temps'] as num?)?.toDouble() ??
                    (perf['tempsEnSecondes'] as num?)?.toDouble() ??
                    0.0;
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

        // B) POSITION AU DÉPART — `placeCorde`
        //
        //    ⚠️ DÉFAUT MESURÉ ET CORRIGÉ : le code lisait `placeDepartCourse`,
        //       clé qui N'EXISTE PAS dans `/participants` (mesuré : 0/98
        //       participants sur 8 courses / 4 disciplines). Le critère
        //       `placeDepart` était donc TOUJOURS à 0, donc toujours neutre.
        //
        //    SOURCE AUTHENTIQUE : `placeCorde`, publiée par le PMU.
        //    Mesures sur la journée du 26/11/2026 (50 courses) :
        //      • présent sur 330 participants ;
        //      • valeurs observées formant une PERMUTATION 1..n sur les
        //        courses où il est publié — donc ce n'est PAS le numéro du
        //        cheval. Contre-exemple mesuré : R2C1, le cheval n° 1 a
        //        `placeCorde = 6` ;
        //      • disciplines où il apparaît : PLAT et ATTELE (mesuré).
        //
        //    ⚠️ CORRECTION D'UNE DE MES AFFIRMATIONS ANTÉRIEURES : j'avais
        //       écrit « absent en TROT ATTELE (0/16) ». C'était FAUX — mesuré
        //       sur une seule course à départ volté, puis généralisé à tort.
        //       Le 26/11/2026, R1C5 (ATTELE, 2 100 m, AUTOSTART) publie bien
        //       `placeCorde` = 1..6. La présence dépend du MODE DE DÉPART,
        //       pas de la discipline.
        //
        //    ⚠️ LIMITE DÉCLARÉE, NON MASQUÉE : `placeCorde` est la position à
        //       la CORDE sur un hippodrome de galop. Elle ne représente NI la
        //       position derrière l'autostart, NI la première/deuxième ligne,
        //       NI les échelons de distance. Le §11 exige de distinguer ces
        //       notions : elles ne sont donc PAS fusionnées ici. En trot, le
        //       PMU publie `handicapDistance` (la distance réelle du cheval,
        //       ex. 2 850 m), qui encode le recul — mais `_scorePlaceDepart`
        //       n'a aucun paramètre pour l'exploiter, et l'inventer ici
        //       reviendrait à modifier la définition du critère.
        //
        //    ⇒ CE QUI EST FAIT : lecture de la clé authentique, sans
        //      substitution. Ce qui reste à décider (exploitation du recul en
        //      trot) est remonté au rapport final comme décision à valider.
        //
        //    ⚠️ LE CRITÈRE N'EST PAS SUPPRIMÉ EN TROT (§11) : si `placeCorde`
        //       est absent, la valeur reste 0 et `_scorePlaceDepart` rend sa
        //       neutralité documentée de 50.0.
        final int placeDepart = (pm['placeCorde'] as num?)?.toInt() ?? 0;

        // C) Musique globale
        final musiqueGlobale = pm['musique'] as String? ?? '';

        // D) JOURS DE REPOS
        //
        //    ⚠️ ÉTAT MESURÉ AVANT CORRECTION : les trois premières sources
        //       étaient TOUTES absentes de `/participants` — `nbJoursAbsence`
        //       0/98, `dateDernierePerformance` 0/98, `performances` et
        //       `historiquePerformances` 0/98. La valeur restait donc à 0 pour
        //       100 % des partants, et `scoreRepos` rendait 50.0
        //       (`if (joursRepos <= 0) return 50.0`).
        //
        //    SOURCE AUTHENTIQUE AJOUTÉE : la date de la dernière course
        //    EFFECTIVEMENT DISPUTÉE, lue dans
        //    `performances-detaillees/coursesCourues[].date`.
        //
        //    ⚠️ CE QUI N'EST PAS FAIT, CONFORMÉMENT AU §5 :
        //      • aucune écriture de zéro pour représenter une donnée inconnue.
        //        Un cheval DÉBUTANT (aucune course passée) reçoit `null`, donc
        //        `joursRepos` reste 0 et le critère rend sa neutralité LÉGITIME
        //        de 50.0 — laquelle est explicitement distinguée d'un repos de
        //        0 jour par la définition même de `scoreRepos`.
        //      • `coursesCourues` ne contient que des courses courues : une
        //        inscription, un non-partant ou une course future ne peuvent
        //        pas s'y trouver. Il n'y a donc rien à filtrer d'autre.
        //
        //    Ordre de priorité conservé, enrichi en dernier recours :
        //    1. `nbJoursAbsence` (champ direct, absent en pratique)
        //    2. `dateDernierePerformance` (absent en pratique)
        //    3. dates dans `performances[]` (absent en pratique)
        //    4. ★ NOUVEAU — historique détaillé `coursesCourues[].date`
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
                final dateRaw =
                    perf['date'] ?? perf['datePerformance'] ?? perf['jour'];
                if (dateRaw == null) continue;
                DateTime? dt;
                if (dateRaw is String && dateRaw.isNotEmpty) {
                  try {
                    dt = DateTime.parse(dateRaw);
                  } catch (_) {}
                  // Format FR : "JJ/MM/YYYY"
                  if (dt == null && dateRaw.contains('/')) {
                    try {
                      final parts = dateRaw.split('/');
                      if (parts.length == 3) {
                        dt = DateTime(int.parse(parts[2]), int.parse(parts[1]),
                            int.parse(parts[0]));
                      }
                    } catch (_) {}
                  }
                } else if (dateRaw is int) {
                  // Timestamp epoch millisecondes
                  try {
                    dt = DateTime.fromMillisecondsSinceEpoch(dateRaw);
                  } catch (_) {}
                }
                if (dt != null &&
                    (plusRecente == null || dt.isAfter(plusRecente))) {
                  plusRecente = dt;
                }
              }
              if (plusRecente != null) {
                final jours =
                    DateTime.now().difference(plusRecente).inDays.abs();
                // Sanity check : entre 1 et 500 jours (évite les dates aberrantes)
                if (jours >= 1 && jours <= 500) joursRepos = jours;
              }
            }
          }

          // ★ Priorité 4 — NOUVEAU : historique détaillé authentique.
          //   N'écrase jamais une valeur déjà obtenue par une source amont.
          if (joursRepos == 0) {
            final histo = histos[(pm['numPmu'] ?? pm['numero'] ?? 0).toString()];
            final jours = _joursReposDepuisHistorique(histo);
            if (jours != null) joursRepos = jours;
          }
        }

        // E) MUSIQUE FILTRÉE PAR DISTANCE ±100 m
        //
        //    ⚠️ ÉTAT MESURÉ AVANT CORRECTION : le code lisait
        //       `performancesParDistance`, clé ABSENTE de `/participants`
        //       (mesuré 0/98). Le champ restait donc vide pour 100 % des
        //       partants, et `_scoreDistanceSpecialite` tombait TOUJOURS sur
        //       son repli `p.scoreForme * 0.90` — le double comptage de la
        //       forme dénoncé au §8. Ce repli n'est PAS modifié.
        //
        //    SOURCE AUTHENTIQUE AJOUTÉE : `coursesCourues[].distance` +
        //    `coursesCourues[].place`, qui permettent de ne retenir que les
        //    courses passées à ±100 m de la distance du jour.
        //
        //    ⚠️ LE FORMAT PRODUIT EST CELUI ATTENDU PAR LES CONSOMMATEURS,
        //       ET CELA A ÉTÉ MESURÉ, PAS SUPPOSÉ. Une de mes affirmations
        //       antérieures qualifiait ce format d'« inanalysable » : c'était
        //       une déduction de lecture, et elle était FAUSSE. Le test
        //       `test/audit_dist_spec_format_test.dart` (F1) mesure que
        //       `"1700:0p9p4p4p0p6p7p"` et `"0p9p4p4p0p6p7p"` produisent
        //       EXACTEMENT le même score : 43.26315789473684 dans les deux cas.
        //       Le préfixe `distance:` est donc neutre pour le décodage.
        //
        //    ⚠️ CE QUI RESTE À VALIDER (remonté au rapport final) : le repli
        //       `forme × 0.90` lui-même reste intact, et il s'appliquera
        //       encore à un cheval dont AUCUNE course passée ne tombe à ±100 m.
        String musiqueDistSpe = '';
        final histoPourDist =
            histos[(pm['numPmu'] ?? pm['numero'] ?? 0).toString()];
        if (histoPourDist != null && histoPourDist.courses.isNotEmpty) {
          // La distance de la course du jour est passée par `_chargerPartants`
          // via le champ statique, comme l'hippodrome.
          musiqueDistSpe = _musiqueDistDepuisHistorique(
              histoPourDist, _distanceCourante ?? 0);
        }

        // F) STATS JOCKEY — AUCUNE STATISTIQUE INVENTÉE
        //
        //    ⚠️ DÉFAUT MESURÉ ET CORRIGÉ : `_heuristiqueJockey` renvoyait des
        //       pourcentages fabriqués, présentés comme réels, avec un en-tête
        //       affirmant « Source : statistiques PMU saisons 2022-2024 » —
        //       source qui n'existe ni dans l'API ni dans le dépôt. Pour un
        //       jockey inconnu de la table, la fonction renvoyait littéralement
        //       `'$nom|9|28'`, c'est-à-dire 9 % de victoires et 28 % de places
        //       inventés. Mesure : `statsJockeyCsv` était renseigné pour
        //       41/41 partants, TOUS par cette table.
        //
        //    ⚠️ CE QUI REMPLACE CES VALEURS : la chaîne VIDE.
        //       `ZtPartant.jockeyTauxVictoire` rend alors -1, et
        //       `IaPronosticEngine._scoreJockey` rend 50.0 dès la première
        //       ligne (`if (tauxVic < 0) return 50.0;`). Le critère devient
        //       donc NEUTRE et l'ANNONCE honnêtement comme non alimenté,
        //       au lieu d'afficher un chiffre sans fondement.
        //
        //    ⚠️ CONFORMITÉ AU §9 : « Ne remplace pas une statistique inventée
        //       par une autre estimation arbitraire. » Aucune estimation n'est
        //       substituée. Les pistes de remplacement (statistiques locales
        //       calculées sur des historiques suffisamment complets) et leurs
        //       limites sont présentées au rapport final comme décisions à
        //       valider : elles changeraient la MÉTHODE du critère.
        //
        //    ⚠️ Le canal `indices.jockey` est conservé : s'il devenait un jour
        //       publié par le PMU, il serait exploité tel quel. Mesure actuelle
        //       : `indices` est absent de /participants (0/98).
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

        // G) STATS HIPPODROME
        //
        //    ⚠️ DÉFAUT MESURÉ ET CORRIGÉ : à défaut de
        //       `performancesParHippodrome` (clé ABSENTE, mesurée 0/98), le code
        //       appelait `_statsHippoDepuisMusique`, qui comptait les LETTRES de
        //       la musique comme des hippodromes. Or ces lettres sont les
        //       DISCIPLINES. Preuve mesurée à Lignières R2 : la même réunion
        //       héberge plat et obstacle sur le MÊME hippodrome, et la musique
        //       donne `{'p': 27}` côté plat contre `{'s': 55, 'h': 17, 'c': 7}`
        //       côté obstacle. Le commentaire d'origine du code affirmait
        //       « 'h' = Vincennes, 'p' = province » : c'est factuellement faux.
        //
        //    SOURCE AUTHENTIQUE : `coursesCourues[].hippodrome`, présent sur
        //    100 % des courses passées mesurées. On compte les courses, les
        //    victoires et les top 3 du cheval sur l'hippodrome DE LA COURSE
        //    ANALYSÉE, ce qui est exactement la définition du critère.
        //
        //    ⚠️ Le canal `performancesParHippodrome` est conservé en priorité
        //       s'il apparaît un jour : il n'est pas supprimé, seulement
        //       remplacé comme source de repli.
        String statsHippoCsv = '';
        final perfParHippo = pm['performancesParHippodrome'];
        if (perfParHippo is List && perfParHippo.isNotEmpty) {
          for (final entry in perfParHippo) {
            if (entry is Map) {
              final nbC = (entry['nbCourses'] as num?)?.toInt() ?? 0;
              final nbV = (entry['nbVictoires'] as num?)?.toInt() ?? 0;
              final nbT = (entry['nbPlaces'] as num?)?.toInt() ?? 0;
              if (nbC > 0) {
                statsHippoCsv = '$nbC|$nbV|$nbT';
                break;
              }
            }
          }
        }
        if (statsHippoCsv.isEmpty) {
          final histo =
              histos[(pm['numPmu'] ?? pm['numero'] ?? 0).toString()];
          statsHippoCsv =
              _statsHippoDepuisHistorique(histo, hippodromeCourse);
        }

        // H) STATS TERRAIN
        //
        //    ⚠️ ÉTAT MESURÉ AVANT CORRECTION : le code lisait
        //       `performancesParTerrain` / `performancesParEtatTerrain` (les
        //       DEUX absentes, mesurées 0/98) puis `indices.terrain` (absent,
        //       `indices` lui-même absent 0/98). `statsTerrainCsv` était donc
        //       TOUJOURS vide et `scoreTerrain` rendait 50.0 — alors même que
        //       la correction BL3-A23 avait rendu `course.piste` exploitable.
        //
        //    SOURCE AUTHENTIQUE : `coursesCourues[].etatTerrain`, l'ÉTAT réel
        //    du terrain de chaque course passée.
        //
        //    ⚠️ LES DEUX EXIGENCES DU §7 SONT RESPECTÉES :
        //      ① surface ≠ état. On lit `etatTerrain` (« Bon », « Souple »,
        //         « PSF Standard »), JAMAIS `typePiste` (HERBE/GAZON/
        //         POUZZOLANE), qui est la nature du sol.
        //      ② pas de terrain forcé en trot. Mesure : `etatTerrain` est
        //         présent sur 100 % des courses passées en Plat/Obstacle/Cross
        //         mais sur 1 à 5 % seulement en Trot. En trot, la chaîne reste
        //         donc vide et le critère rend sa neutralité de 50.0. Aucune
        //         valeur de terrain n'est inventée pour le trot.
        //
        //    ⚠️ La normalisation employée est celle du CONSOMMATEUR
        //       (`ZtPartant._normaliserTerrain`), reproduite à l'identique par
        //       `_normaliserTerrainPourStockage`, sinon la comparaison
        //       d'égalité stricte de `scoreTerrain` échouerait.
        String statsTerrainCsv = '';
        final perfParTerrain =
            pm['performancesParTerrain'] ?? pm['performancesParEtatTerrain'];
        if (perfParTerrain is List && perfParTerrain.isNotEmpty) {
          final buf = StringBuffer();
          for (final entry in perfParTerrain) {
            if (entry is Map) {
              // L'API retournerait 'etatTerrain' ou 'terrain'
              final terrain =
                  ((entry['etatTerrain'] ?? entry['terrain']) as String? ?? '')
                      .toLowerCase();
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
              statsTerrainCsv =
                  '${_normaliserTerrainPmu(terrain)}|$nbC|$nbV|$nbT';
            }
          }
        }
        // ★ NOUVEAU — source authentique : historique détaillé.
        if (statsTerrainCsv.isEmpty) {
          final histo =
              histos[(pm['numPmu'] ?? pm['numero'] ?? 0).toString()];
          statsTerrainCsv = _statsTerrainDepuisHistorique(histo);
        }

        // ★ v9.0 — I) GAINS DERNIER AN — extraire depuis l'API PMU
        //
        //    ⚠️ DÉCISION D-10 APPLIQUÉE (§4). L'ancien code fabriquait une
        //       valeur : `gainsDernierAn = (gainsCarriere * 0.20).round()`
        //       quand l'API ne fournissait rien. C'était une donnée INVENTÉE
        //       présentée comme une observation, et elle alimentait le critère
        //       de progression (`scoreProgression`, ratio gains 12 mois /
        //       gains carrière). Le fallback est SUPPRIMÉ.
        //
        //    ⚠️ DISTINCTION ABSENT / ZÉRO AUTHENTIQUE (§9, D-10) :
        //       `gainsDernierAnDisponible` porte cette distinction. Un zéro
        //       fourni par l'API est un zéro AUTHENTIQUE : il est conservé tel
        //       quel et n'est pas remplacé. Une absence n'est pas un zéro : le
        //       critère garde alors son comportement neutre existant
        //       (`scoreProgression` n'applique pas le bloc ratio, la formule
        //       n'est pas touchée).
        //
        //    ⚠️ AUCUNE FORMULE MODIFIÉE (§3) : seule la FABRICATION de la
        //       donnée d'entrée disparaît. Le calcul de `scoreProgression`
        //       reste identique, il reçoit simplement une entrée honnête.
        //
        //    ⚠️ ANNÉE CIVILE ≠ 12 DERNIERS MOIS (D-10) : `gainsSaison` est la
        //       seule grandeur réellement fournie par le PMU. On ne la
        //       présente pas comme « 12 derniers mois » : le champ
        //       `gainsDernierAnSource` conserve la provenance exacte, ce qui
        //       rend la limite visible au lieu de la masquer.
        int gainsDernierAn = 0;
        bool gainsDernierAnDisponible = false;
        String gainsDernierAnSource = 'absent';
        final gainsMap = pm['gainsParticipant'];
        if (gainsMap is Map) {
          final gainsSaison =
              (gainsMap['gainsSaison'] as num?)?.toDouble() ?? 0.0;
          final gainsAnnee =
              (gainsMap['gainsAnnee'] as num?)?.toDouble() ?? 0.0;
          if (gainsSaison > 0 || gainsAnnee > 0) {
            final raw = gainsSaison > 0 ? gainsSaison : gainsAnnee;
            // Convertir centimes → euros si nécessaire
            gainsDernierAn = (raw > 10000 ? raw / 100.0 : raw).round();
            gainsDernierAnDisponible = true;
            gainsDernierAnSource =
                gainsSaison > 0 ? 'pmu_gainsSaison' : 'pmu_gainsAnnee';
          }
        }
        // Aucun fallback : une absence reste une absence.

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
          statsTerrainCsv: statsTerrainCsv, // ★ v9.0
          gainsDernierAn: gainsDernierAn, // ★ v9.0
          gainsDernierAnDisponible: gainsDernierAnDisponible, // D-10
          gainsDernierAnSource: gainsDernierAnSource, // D-10
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
    final partants =
        await _chargerPartants(dateStr, numR, numC, course.heureDateTime);
    // Appliquer les scores IA
    if (partants.isNotEmpty) {
      final courseTmp = ZtCourse(
        numCourse: numC,
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
        partants: partants,
        dateStr: dateStr,
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
    if (t.contains('tres lourd') ||
        t.contains('très lourd') ||
        t.contains('very') ||
        t == 'tl') {
      return 'tres_lourd';
    }
    if (t.contains('lourd') || t == 'l') return 'lourd';
    if (t.contains('souple') || t.contains('soft') || t == 's') return 'souple';
    if (t.contains('bon') || t.contains('good') || t == 'b') return 'bon';
    if (t.contains('sable') || t.contains('sand')) return 'sable';
    if (t.contains('piste') || t.contains('all weather')) return 'sable';
    if (t.contains('standard') || t.contains('normal')) return 'bon';
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
  // SOURCE RÉELLE : `categorieParticularite` du JSON PMU. Valeurs RE-MESURÉES
  // par `grep -rho '"categorieParticularite"' test/fixtures/ | sort | uniq -c`
  // sur l'ENSEMBLE des fixtures du dépôt — 316 occurrences, 24 valeurs
  // distinctes :
  //   'COURSE_A_CONDITIONS' (80), 'INCONNU' (54), 'HANDICAP' (40),
  //   'AUTOSTART' (39), 'HANDICAP_DIVISE' (17), 'NATIONALE' (16),
  //   'INTERNATIONALE_AUTOSTART' (7), 'HANDICAP_DE_CATEGORIE' (7),
  //   'A_RECLAMER' (7), 'HANDICAP_CATEGORIE_DIVISE' (6), 'GROUPE_III' (5),
  //   'EUROPEENNE' (5), 'AMATEURS' (5), 'GROUPE_I' (4),
  //   'APPRENTIS_LADS_JOCKEYS_AUTOSTART' (4), 'APPRENTIS_LADS_JOCKEYS' (4),
  //   'AMATEURS_AUTOSTART' (4), 'INTERNATIONALE' (3), 'EUROPEENNE_AUTOSTART' (3),
  //   'COURSE_A_CONDITION_QUALIF_HP' (2), 'QUALIFICATION_ACCAF' (1),
  //   'HANDICAP_A_RECLAMER' (1), 'AMATEURS_PRIORITE_AUX_PROPRIETAIRES' (1),
  //   'AMATEURS_NATIONALE' (1).
  //   ⚠️ Une version antérieure de ce commentaire annonçait « 224 courses » :
  //      c'était FAUX (mesure incomplète). Corrigé ici, sans changement de code.
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
  // ══════════════════════════════════════════════════════════════════════
  //  ⛔ `_statsHippoDepuisMusique` — DÉSARMÉE, CONSERVÉE POUR TRAÇABILITÉ
  // ══════════════════════════════════════════════════════════════════════
  //
  //  CETTE FONCTION N'EST PLUS APPELÉE (mesuré : 0 appelant dans `lib/`).
  //
  //  POURQUOI ELLE EST CONSERVÉE PLUTÔT QUE SUPPRIMÉE
  //    Elle reposait sur une prémisse FAUSSE, mesurée comme telle : compter
  //    les LETTRES de la musique comme des identifiants d'HIPPODROMES.
  //
  //    La musique PMU code la DISCIPLINE, pas le lieu. Preuve mesurée à
  //    Lignières R2, où plat et obstacle se courent sur le MÊME hippodrome :
  //      • musique côté PLAT     → {'p': 27}
  //      • musique côté OBSTACLE → {'s': 55, 'h': 17, 'c': 7}
  //    Si 'p', 's', 'h', 'c' étaient des hippodromes, la même réunion
  //    désignerait quatre lieux différents : c'est absurde.
  //
  //    Le commentaire d'origine du code affirmait « 'h' = Vincennes,
  //    'p' = province » : cette affirmation est factuellement fausse.
  //
  //  ⚠️ La fonction est conservée pour que la démonstration du défaut reste
  //     lisible dans le code, mais elle n'alimente plus AUCUN champ.
  //     La source authentique est `coursesCourues[].hippodrome` (100 % de
  //     présence mesurée), exploitée par `_statsHippoDepuisHistorique`.
  //
  //  ⚠️ NE PAS LA REBRANCHER.
  // ignore: unused_element
  static String _statsHippoDepuisMusique(String musique) {
    if (musique.isEmpty) return '';

    // Regex : capture token "positionLETTRE" ex: 1a, 2h, 3p, Ah, Dp
    final tokenRegex =
        RegExp(r'(\d+|[ADdQq])([ahmpetsr])', caseSensitive: false);
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
  // ══════════════════════════════════════════════════════════════════════
  //  ⛔ `_heuristiqueJockey` — DÉSARMÉE, CONSERVÉE POUR TRAÇABILITÉ
  // ══════════════════════════════════════════════════════════════════════
  //
  //  CETTE FONCTION N'EST PLUS APPELÉE (mesuré : 0 appelant dans `lib/`).
  //
  //  POURQUOI ELLE EST CONSERVÉE PLUTÔT QUE SUPPRIMÉE
  //    Le §9 du mandat interdit de présenter des pourcentages sans source
  //    vérifiable comme des statistiques réelles. La fonction fabriquait
  //    exactement cela :
  //      • un en-tête affirmant « Source : statistiques PMU saisons 2022-2024 »
  //        alors qu'aucune source de ce type n'existe dans l'API ni dans le
  //        dépôt (mesuré : `/jockeys` → HTTP 420, `/entraineurs` → HTTP 400,
  //        `/statistiques/*` → HTTP 420) ;
  //      • pour tout nom absent de ses deux tables, un retour littéral
  //        `'$nom|9|28'`, soit 9 % de victoires et 28 % de places INVENTÉS.
  //
  //    La supprimer effacerait la preuve du défaut. La laisser branchée
  //    perpétuerait une donnée fabriquée. Elle est donc CONSERVÉE mais
  //    CÂBLÉE À RIEN : le code qui l'appelait renvoie désormais la chaîne
  //    vide, ce qui rend `scoreJockey` neutre à 50.0 et l'annonce comme
  //    non alimenté.
  //
  //  ⚠️ NE PAS LA REBRANCHER. Si une source authentique de statistiques
  //     jockey devient disponible, elle doit être lue depuis cette source et
  //     non depuis cette table.
  // ignore: unused_element
  static String _heuristiqueJockey(String nom) {
    final nomUpper = nom.toUpperCase();

    // ═══════════════════════════════════════════════════════════════
    // BASE DE DONNÉES ÉLARGIE — Jockeys galop français
    // Format : 'NOM' → '%victoire|%placé top3'
    // Source : statistiques PMU saisons 2022-2024
    // ═══════════════════════════════════════════════════════════════
    const jockeysGalop = {
      // Elite internationale
      'GUYON': '18|48', 'SOUMILLON': '20|51', 'LEMAIRE': '22|53',
      'BOUDOT': '21|50', 'DEMURO': '16|44', 'PESLIER': '15|42',
      // Très bons jockeys
      'BENOIST': '14|40', 'PASQUIER': '13|39', 'MENDIZABAL': '14|41',
      'MOSSE': '15|43', 'THULLIEZ': '12|37', 'ABRIVARD': '13|38',
      'VELON': '12|36', 'CRASTUS': '12|37', 'FOULON': '12|36',
      // Réguliers
      'BERTRAS': '11|35', 'BLONDEL': '13|38', 'CHARRON': '10|33',
      'ROCHARD': '11|34', 'STASSE': '10|32', 'DOUMEN': '11|35',
      'BACHELOT': '11|34', 'LECOEUVRE': '12|36', 'HAMELIN': '11|35',
      'VERON': '12|37', 'LEFEBVRE': '11|35', 'TRULLIER': '11|34',
      'GRANDIN': '10|33', 'BOISSEAU': '10|32', 'JUSTUM': '10|32',
      'FAVRIAUX': '11|34', 'CLAUDIC': '10|33', 'MARIEN': '10|32',
      'SANTIAGO': '10|33', 'BAZIRE': '12|36', 'BOUTIN': '11|35',
      'WEISSMEIER': '10|33', 'MADAMET': '11|34', 'MEURY': '10|32',
    };

    // ═══════════════════════════════════════════════════════════════
    // BASE DE DONNÉES ÉLARGIE — Drivers trot français
    // ═══════════════════════════════════════════════════════════════
    const driversTrot = {
      // Elite trot
      'NIVARD': '20|52', 'JOSSELIN': '17|46', 'RAFFIN': '16|44',
      'MOTTIER': '15|43', 'BEKAERT': '14|41',
      // Très bons drivers
      'BIGEON': '12|37', 'VERROKEN': '13|38', 'BOURASSIN': '11|34',
      'MASSETEAU': '13|39', 'PLOQUIN': '11|35', 'BAUDOUIN': '12|36',
      'GALLIER': '11|34', 'ABRIVARD': '14|40', 'OUVRIE': '13|38',
      // Réguliers
      'LAGADEUC': '11|35', 'HENRY': '11|34', 'DEVRED': '10|33',
      'COUDRAY': '10|33', 'LERAY': '10|32', 'BREUIL': '10|32',
      'SENET': '11|34', 'POU': '10|33', 'BRIAND': '10|32',
      'MARTENS': '11|35', 'BARRIER': '10|33', 'PHILIPPE': '10|32',
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
      ' ALL', // Allemagne (ex: GELSENKIRCHEN ALL, MUNICH-RIEM ALL)
      ' HK', // Hong Kong (ex: HAPPY VALLEY HK)
      ' ARG', // Argentine (ex: SAN ISIDRO ARG)
      ' ESP', // Espagne   (ex: SAN SEBASTIAN ESP)
    ];
    // ★ Fix : filtrage par nom d'hippodrome étranger connu
    // L'API PMU retourne parfois le nom sans le pays → on blackliste directement
    const foreignTracks = [
      'CROISE LAROCHE', // Belgique
      'LE CROISE', // Belgique
      'PALERMO', // Argentine (Buenos Aires)
      'CASABLANCA', // Maroc
      'MEKNES', // Maroc
      'SOUSSE', // Tunisie
      'KSAR SAID', // Tunisie
      'DRAWBRIDGE', // USA
      'PARX', // USA
      'GULFSTREAM', // USA
      'SANTA ANITA', // USA
      'DEL MAR', // USA
      'CHURCHILL', // USA
      'BELMONT', // USA
      'SARATOGA', // USA
      'LEOPARDSTOWN', // Irlande
      'CURRAGH', // Irlande
      'DUNDALK', // Irlande
      'PUNCHESTOWN', // Irlande
      'NAAS', // Irlande
      'FAIRYHOUSE', // Irlande
      'GALWAY', // Irlande (hippodrome)
      'TIPPERARY', // Irlande
      'NAVAN', // Irlande
      'CORK', // Irlande (hippodrome)
      'GOODWOOD', // GB
      'NEWMARKET', // GB
      'ASCOT', // GB
      'NEWBURY', // GB
      'HAYDOCK', // GB
      'CHESTER', // GB
      'WOLVERHAMPTON', // GB
      'CHELTENHAM', // GB
      'SON PARDO', // Majorque/Espagne (ex: SON PARDO PALMA)
      'SOLVALLA', // Suède
      'JÄGERSRO', // Suède
      'ABY', // Suède
      'ROMME', // Suède
      'AXEVALLA', // Suède
      'BERGSAKER', // Norvège
      'BJERKE', // Norvège
      'MANTORP', // Suède
      'HAGMYREN', // Suède
      'UMAKER', // Suède
      'KALMAR', // Suède
      'GOTHENBURG', // Suède
      'GÖTEBORG', // Suède
      'STOCKHOLM', // Suède
      'ESKILSTUNA', // Suède
      'CAEN', // Déjà France mais au cas où
    ];
    if (foreignCountries.any((m) => hippodromeLong.contains(m))) return false;
    if (foreignTracks.any((t) => hippodromeLong.contains(t))) return false;
    return true;
  }

  /// Convertit la discipline PMU en type lisible pour ZtCourse
  static String _pmuDisciplineToZt(String discipline) {
    switch (discipline.toUpperCase()) {
      case 'PLAT':
        return 'Plat';
      case 'HAIE':
      case 'HAIES':
        return 'Haies';
      case 'STEEPLECHASE':
      case 'STEEPLE':
        return 'Steeple Chase';
      case 'ATTELE':
      case 'TROT_ATTELE':
        return 'Attelé';
      case 'TROT_MONTE':
      case 'MONTE':
        return 'Monté';
      case 'CROSS':
        return 'Cross';
      default:
        return 'Plat';
    }
  }

  // Rétro-compat (conservé pour usage potentiel futur)
  // ignore: unused_element
  static bool _estReunionFrancaise(ZtReunion r) {
    final lieu = r.lieu.toUpperCase();
    const prefixesEtrangers = [
      'GB ',
      'USA ',
      'AUS ',
      'SAF ',
      'UAE ',
      'CHL ',
      'ARG ',
      'BEL ',
      'IRE ',
      'GER ',
      'ITA ',
      'ESP ',
      'POR ',
      'SWE ',
      'NOR ',
      'DEN ',
      'JPN ',
      'HKG ',
      'SGP ',
      'NZL ',
      'CAN ',
      'BRZ ',
      'URU ',
      'CHI ',
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
            dateStr: course.dateStr, // ← propagation obligatoire
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
  /// Lit le caractère définitif SANS RIEN SUPPOSER.
  ///
  /// Trois états, jamais deux :
  ///   • `false`  → l'API dit explicitement que l'arrivée n'est pas définitive ;
  ///   • `true`   → l'API dit explicitement qu'elle l'est ;
  ///   • `null`   → l'API ne le dit pas (clé absente, type inattendu).
  ///
  /// ⚠️ `statut` n'est volontairement PAS utilisé comme substitut : traduire un
  /// libellé en booléen serait exactement la décision métier inventée que ce
  /// lot s'interdit.
  static bool? _lireDrapeauDefinitif(Map<String, dynamic> data) {
    final direct = data['arriveeDefinitive'];
    if (direct is bool) return direct;
    final indirect = data['isArriveeDefinitive'];
    if (indirect is bool) return indirect;
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  ★ CORRECTION BLOC 1 — DÉFAUT D'ALIMENTATION DU DRAPEAU DÉFINITIF
  //
  //  DÉFAUT MESURÉ (et non supposé). Chaîne de preuve :
  //
  //   1. `chargerResultatsCourseComplet` appliquait `_lireDrapeauDefinitif`
  //      au corps de l'endpoint `/participants`.
  //   2. Réponse AUTHENTIQUE de cet endpoint, relevée le 25/11/2026 :
  //        GET .../programme/15112026/R01/C01/participants?specialisation=INTERNET
  //        → HTTP 200, 16 529 octets.
  //        Clés racine : ['participants', 'ecuries', 'spriteCasaques', 'cached'].
  //      Il n'y a NI `arriveeDefinitive` NI `isArriveeDefinitive` dans ce
  //      corps. `_lireDrapeauDefinitif` y rendait donc TOUJOURS `null`.
  //   3. `moteur_gain_pmu.dart` (`_blocEstDemontreComplet`) exige
  //      `etat.arriveeDefinitive == true` pour établir une perte.
  //   4. CONSÉQUENCE : par cette chaîne, une perte ne pouvait JAMAIS être
  //      établie, même sur une arrivée définitive et un bloc démontré complet.
  //
  //  LE DRAPEAU EXISTE AILLEURS, et c'est mesuré :
  //    GET .../programme/15112026/R01/C01?specialisation=INTERNET
  //      → HTTP 200. Clés racine : 71, dont
  //        `arriveeDefinitive`      = true
  //        `isArriveeDefinitive`    = true
  //        `statut`                 = 'ARRIVEE_DEFINITIVE_COMPLETE'
  //        `ordreArrivee`           = [[4],[6],[7],[9],[1],[3],[5]]
  //        `nombreDeclaresPartants` = 9
  //    Et sur les fixtures authentiques du dépôt
  //    (`test/fixtures/recherche_pmu/multi/prog_*.json`, 316 courses) :
  //        arriveeDefinitive → {True: 308, absent: 8}
  //
  //  CE QUE CETTE CORRECTION FAIT — et ne fait pas :
  //   • elle lit le drapeau là où le PMU le publie RÉELLEMENT ;
  //   • elle conserve `null` quand le PMU ne le dit pas (les 8/316 mesurés) :
  //     `null` n'est JAMAIS converti en `true` ni en `false` ;
  //   • elle n'invente aucune valeur depuis `statut` ;
  //   • elle ne touche NI le moteur (`moteur_gain_pmu.dart`), NI ses
  //     protections : la seule chose qui change est la DONNÉE fournie.
  //
  //  COÛT RÉSEAU — MESURÉ, ET VOLONTAIREMENT MINIMAL :
  //   • L'endpoint PAR COURSE `…/$dateStr/R$r/C$c` pèse 5 529 octets et porte
  //     `arriveeDefinitive` à sa racine. Il ne coûte donc qu'un petit GET, et
  //     seulement pour une course DÉJÀ TERMINÉE (l'appelant n'arrive ici
  //     qu'après avoir obtenu un classement).
  //   • Le programme du JOUR (≈ 400 Ko) n'est JAMAIS demandé pour ce drapeau.
  //   • Cache court (2 min) par course : un même écran qui résout plusieurs
  //     paris d'une même course ne relit qu'une fois.
  // ═══════════════════════════════════════════════════════════════════════

  /// Cache court du drapeau définitif, par identité de course.
  ///
  /// Volontairement SÉPARÉ de `_cache` (qui porte les listes de réunions) : la
  /// durée de validité n'a rien à voir, et un programme en cache ne doit pas
  /// faire croire que le drapeau d'une course a été relu.
  static final Map<String, ({bool? valeur, DateTime luLe})>
      _cacheDrapeauDefinitif = {};

  /// Durée de validité du drapeau. Courte : une arrivée provisoire doit pouvoir
  /// devenir définitive sans attendre 15 minutes.
  static const Duration _validiteDrapeauDefinitif = Duration(minutes: 2);

  /// Lit le caractère définitif sur l'endpoint PAR COURSE, là où le PMU le
  /// publie réellement.
  ///
  /// Résultat triple, et volontairement distingué :
  ///   • `sourceIndisponible == false` + `valeur == null`
  ///       → la source a RÉPONDU et ne publie pas le drapeau : le PMU est muet.
  ///         C'est une information, on ne la « complète » pas.
  ///   • `sourceIndisponible == false` + `valeur == true/false`
  ///       → le PMU l'affirme, on le transmet tel quel.
  ///   • `sourceIndisponible == true`
  ///       → on n'a pas pu joindre la source (HTTP ≠ 200, délai, exception).
  ///         On ne sait rien. Le cache local est alors consulté UNIQUEMENT pour
  ///         ne pas perdre un drapeau déjà mesuré — jamais pour en inventer un.
  ///
  /// On ne dérive JAMAIS le drapeau de `statut` : ce serait une décision métier
  /// inventée. Mesuré : `FIN_COURSE` existe (1 course sur 316 fixtures) à côté
  /// de `ARRIVEE_DEFINITIVE_COMPLETE` (93) ; les deux vocabulaires ne se
  /// traduisent pas l'un en l'autre.
  /// ★ CORRECTION BLOC 1 (validation financière) — CACHE DES ARRIVÉES
  ///   PROVISOIRES ET MUETTES, ET ACCÈS CONCURRENTS.
  ///
  /// DÉFAUT MESURÉ (test `8.1` puis `8.2` de
  /// `b1_fin_perimetre_financier_test.dart`, tous deux ROUGES) :
  ///   l'ancienne version mettait en cache TOUTE valeur lue, y compris
  ///   `false` (« arrivée provisoire ») et `null` (« le PMU ne le dit pas »),
  ///   pendant `_validiteDrapeauDefinitif` = 2 minutes. Conséquence : dès
  ///   qu'une course était vue provisoire, sa résolution financière restait
  ///   `nonDeterminee` pendant 2 minutes, MÊME si le PMU publiait l'arrivée
  ///   définitive entre-temps. C'est exactement ce que le mandat interdit :
  ///   « une indisponibilité temporaire de la source ne doit pas bloquer
  ///   définitivement la résolution ».
  ///
  /// RÈGLE CORRIGÉE — asymétrie justifiée par la nature de l'information :
  ///   • `true`  est STABLE : une arrivée définitive ne redevient pas
  ///     provisoire. On le met en cache — mais avec la MÊME validité de 2 min,
  ///     précisément pour préserver la possibilité d'une RECTIFICATION
  ///     OFFICIELLE ultérieure (correction d'arrivée, disqualification
  ///     tardive). Un cache éternel interdirait cette rectification ;
  ///   • `false` et `null` sont INSTABLES : ils décrivent un état transitoire
  ///     ou une ignorance. Ils ne sont JAMAIS mis en cache. Le coût est une
  ///     requête par appel, ce qui est le prix de la justesse — et il reste
  ///     borné, car l'appel est déjà dédupliqué par le cache de résultat
  ///     (`chargerResultatsCourseComplet`) en amont.
  ///
  /// MAÎTRISE DES ACCÈS CONCURRENTS (exigée explicitement) :
  ///   `_enVolDrapeauDefinitif` mémorise la requête EN COURS par clé. Deux
  ///   appels simultanés sur la même course PARTAGENT la même `Future` : une
  ///   seule requête réseau part, quel que soit le nombre d'appelants. Sans
  ///   cela, un écran qui reconstruit sa liste pendant un rafraîchissement
  ///   pouvait lancer N requêtes identiques.
  static final Map<String, Future<({bool? valeur, bool sourceIndisponible})>>
      _enVolDrapeauDefinitif = {};

  static Future<({bool? valeur, bool sourceIndisponible})>
      _drapeauDefinitifDepuisCourse({
    required String dateStr,
    required int numReunion,
    required int numCourse,
  }) {
    final rPad = numReunion.toString().padLeft(2, '0');
    final cPad = numCourse.toString().padLeft(2, '0');
    final cleCache = '$dateStr/R$rPad/C$cPad';

    // 0. Déduplication : si une requête est déjà en vol pour cette course,
    //    on partage son résultat au lieu d'en lancer une seconde.
    final enVol = _enVolDrapeauDefinitif[cleCache];
    if (enVol != null) return enVol;

    final future = _lireDrapeauDefinitifReseau(
      cleCache: cleCache,
      dateStr: dateStr,
      rPad: rPad,
      cPad: cPad,
    );
    _enVolDrapeauDefinitif[cleCache] = future;
    // Nettoyage garanti, succès comme échec : sans cela, une exception
    // laisserait la clé « en vol » pour toujours et bloquerait toute
    // résolution ultérieure de cette course.
    return future.whenComplete(() {
      _enVolDrapeauDefinitif.remove(cleCache);
    });
  }

  /// Corps réel de la lecture, après déduplication.
  static Future<({bool? valeur, bool sourceIndisponible})>
      _lireDrapeauDefinitifReseau({
    required String cleCache,
    required String dateStr,
    required String rPad,
    required String cPad,
  }) async {
    // 1. Cache court : uniquement pour une valeur STABLE (`true`).
    final enCache = _cacheDrapeauDefinitif[cleCache];
    if (enCache != null &&
        enCache.valeur == true &&
        DateTime.now().difference(enCache.luLe) < _validiteDrapeauDefinitif) {
      return (valeur: enCache.valeur, sourceIndisponible: false);
    }

    // 2. Une seule tentative réseau, sur l'endpoint par course.
    final url = kIsWeb
        ? '$_proxyBase/programme/$dateStr/R$rPad/C$cPad'
        : '$_pmuBase/programme/$dateStr/R$rPad/C$cPad?$_pmuSpec';
    try {
      if (kDebugMode) debugPrint('PMU drapeau définitif: GET $url');
      final resp = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('PMU drapeau définitif: HTTP ${resp.statusCode} '
              '→ source indisponible, valeur non inventée');
        }
        // Une panne ne doit pas détruire une mesure STABLE déjà obtenue ;
        // elle ne doit pas non plus la rafraîchir artificiellement.
        return (
          valeur: enCache?.valeur == true ? enCache!.valeur : null,
          sourceIndisponible: true,
        );
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      // Lecture TOLÉRANTE : `null` si le PMU ne le dit pas. `false` explicite
      // est conservé tel quel — c'est l'information qui empêche de traiter une
      // arrivée provisoire comme définitive.
      final valeur = _lireDrapeauDefinitif(data);

      // ★ SEUL `true` EST CACHÉ. Voir le bloc de commentaire ci-dessus.
      if (valeur == true) {
        _cacheDrapeauDefinitif[cleCache] =
            (valeur: valeur, luLe: DateTime.now());
      } else {
        // `false` / `null` : état instable. On PURGE toute valeur antérieure
        // afin qu'aucune lecture suivante ne puisse resservir un état périmé.
        _cacheDrapeauDefinitif.remove(cleCache);
      }
      return (valeur: valeur, sourceIndisponible: false);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PMU drapeau définitif: lecture impossible ($e) '
            '→ source indisponible');
      }
      return (
        valeur: enCache?.valeur == true ? enCache!.valeur : null,
        sourceIndisponible: true,
      );
    }
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
      final resp = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('PMU Résultats complet: HTTP ${resp.statusCode}');
        }
        return null;
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final participants = data['participants'] as List<dynamic>? ?? [];

      // ★ CORRECTION BLOC 1 — LECTURE DU DRAPEAU DÉFINITIF À LA BONNE SOURCE.
      //
      //   Le corps de CET endpoint ne le porte pas (mesuré : 4 clés racine
      //   ['participants','ecuries','spriteCasaques','cached']). On le lit donc
      //   sur l'objet COURSE de `/programme`, via le cache 15 min existant.
      //
      //   `sourceIndisponible` n'est vrai QUE si la source n'a pas pu être
      //   jointe. Un drapeau absent d'une source jointe reste `null` et n'est
      //   PAS requalifié : le PMU est muet, on ne comble pas son silence.
      final lectureDrapeau = await _drapeauDefinitifDepuisCourse(
        dateStr: dateStr,
        numReunion: numReunion,
        numCourse: numCourse,
      );

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
        final num =
            numStr is int ? numStr : int.tryParse(numStr?.toString() ?? '');
        if (num == null) continue;

        final statut = (part['statut'] as String? ?? '').toUpperCase();
        statutsParNumero[num] = statut;

        // Détecter les chevaux disqualifiés / retirés APRÈS la course
        // (DISQUALIFIE = DQ après arrivée, ARRETE = arrêt pendant la course,
        //  TOMBE = chute, RETRAIT = retiré avant départ)
        if (statut == 'DISQUALIFIE' ||
            statut == 'DISQUALIFIED' ||
            statut == 'ARRETE' ||
            statut == 'TOMBE') {
          if (!disqualifies.contains(num)) disqualifies.add(num);
          // Ne PAS inclure dans l'arrivée officielle
          continue;
        }

        // Ignorer les non-partants (retirés avant la course)
        if (statut == 'NON_PARTANT' || statut == 'RETRAIT') continue;

        final rang =
            part['ordreArrivee'] ?? part['placeCourse'] ?? part['rang'];
        final rangInt =
            rang is int ? rang : int.tryParse(rang?.toString() ?? '');
        if (rangInt != null && rangInt > 0) {
          // ★ B-2 bis : ajout dans la liste du rang, JAMAIS remplacement.
          //   L'ordre d'insertion est celui de l'API : deux ex æquo gardent
          //   l'ordre où le PMU les a publiés.
          rangsGroupes.putIfAbsent(rangInt, () => <int>[]).add(num);
        }
      }

      if (rangsGroupes.isEmpty && disqualifies.isEmpty) {
        if (kDebugMode) {
          debugPrint('PMU Résultats: pas de classement disponible');
        }
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

      if (kDebugMode) {
        debugPrint(
            'PMU Résultats: arrivée officielle = $arrivee | DQ = $disqualifies');
      }

      return ResultatCourse(
        arriveeOfficielle: arrivee,
        disqualifies: disqualifies,
        statutsPartants: statutsParNumero,
        // ★ B-2 bis : les groupes EXACTS accompagnent l'aplatissement.
        arriveeGroupes: List<List<int>>.unmodifiable(groupes),
        // ★ CORRECTION BLOC 1 — le drapeau définitif est désormais lu LÀ OÙ LE
        //   PMU LE PUBLIE, c'est-à-dire sur l'objet COURSE de `/programme`.
        //
        //   AVANT : `_lireDrapeauDefinitif(data)` était appliqué au corps de
        //   `/participants`. Mesuré sur la réponse authentique (HTTP 200,
        //   16 529 octets) : ce corps n'a que 4 clés racine
        //   ['participants','ecuries','spriteCasaques','cached'] — le drapeau
        //   n'y figure pas, donc `null` était rendu SYSTÉMATIQUEMENT, et le
        //   moteur refusait toute perte (`_blocEstDemontreComplet` exige
        //   `arriveeDefinitive == true`).
        //
        //   APRÈS : la lecture se fait sur l'endpoint PAR COURSE, celui qui
        //   publie réellement `arriveeDefinitive`. Les trois états sont
        //   préservés : `true`, `false`, `null`. `null` reste `null`.
        //
        //   `sourceIndisponible` distingue honnêtement deux causes que le seul
        //   `null` confondait :
        //     • source JOINTE et drapeau absent → le PMU est muet sur cette
        //       course : `null` est la vérité, pas un manque d'information ;
        //     • source INJOIGNABLE → on ignore ce que dit le PMU ; on conserve
        //       alors une valeur DÉJÀ mesurée en cache, jamais une valeur
        //       inventée. `null` s'il n'y en a aucune.
        //   Aucune de ces deux branches n'invente `true`.
        arriveeDefinitive: lectureDrapeau.valeur,
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

      final resp = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final participants = data['participants'] as List<dynamic>? ?? [];
      final Map<int, String> statuts = {};

      for (final p in participants) {
        final part = p as Map<String, dynamic>;
        final numStr = part['numPmu'] ?? part['numero'] ?? part['num'];
        final num =
            numStr is int ? numStr : int.tryParse(numStr?.toString() ?? '');
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
    // ★ CORRECTION BLOC 1 : le cache court du drapeau définitif fait partie de
    //   l'état en mémoire. Un reset doit l'effacer, sinon une valeur mesurée
    //   AVANT le reset pourrait être servie APRÈS — exactement ce qu'un reset
    //   doit rendre impossible.
    _cacheDrapeauDefinitif.clear();
    // ★ CORRECTION BLOC 1 (validation financière) : les requêtes EN VOL sont
    //   abandonnées elles aussi. Sans cette purge, une lecture lancée AVANT le
    //   reset pourrait, à son retour, réécrire dans le cache une valeur
    //   mesurée avant le reset — le reset ne serait alors que partiel.
    _enVolDrapeauDefinitif.clear();
    // ★ ENRICHISSEMENT : le cache d'historiques détaillés fait partie de
    //   l'état en mémoire. Un reset doit l'effacer, pour la même raison que
    //   les autres : aucune donnée mesurée avant un reset ne doit être servie
    //   après.
    _cachePerfDetail.clear();
    _cachePerfDetailTime.clear();
    // La composition n'est plus un état mémoire : elle est lue depuis SQLite
    // (table permanente `observations`). Rien à invalider ici, donc rien ne
    // peut être perdu par un reset.
    _hippodromeCourant = null;
    _distanceCourante = null;
    // ★ L1 : invalide toute capture L0 EN VOL (chargement réseau en cours au
    // moment du reset). Le compteur n'est jamais décrémenté.
    _generationReset++;
    if (kDebugMode) {
      debugPrint('[ZoneTurf] 🧹 Cache statique vidé (reset complet)');
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // HISTORIQUES DÉTAILLÉS — chargement mutualisé et mis en cache
  // ──────────────────────────────────────────────────────────────────
  //
  //  Retourne une map `numPmu (String) → _HistoCheval`.
  //
  //  ⚠️ CETTE MÉTHODE NE LÈVE JAMAIS D'EXCEPTION et ne bloque jamais
  //     l'analyse : en cas d'erreur réseau, de délai dépassé, de code HTTP
  //     non-200 ou de JSON illisible, elle renvoie une map VIDE. Les critères
  //     concernés restent alors dans leur comportement neutre documenté
  //     (repos = 0 jour → neutre, hippodrome = 50.0, terrain = 50.0).
  //     C'est le comportement exigé par le §3 : « gestion des erreurs réseau,
  //     gestion des réponses partielles, fonctionnement avec une connexion
  //     dégradée ».
  static Future<Map<String, _HistoCheval>> _chargerPerformancesDetaillees(
    String dateStr,
    int numR,
    int numC, {
    /// Noms des partants, utilisés UNIQUEMENT pour le repli sur le corpus
    /// local quand le PMU ne répond rien. Vide ⇒ aucun repli possible, ce qui
    /// est le comportement d'avant (map vide) et jamais une régression.
    Map<String, String> nomsParNumero = const <String, String>{},
  }) async {
    final cle = '$dateStr/R$numR/C$numC';

    // ① Cache : une course déjà téléchargée dans la fenêtre n'est pas rejouée.
    final enCache = _cachePerfDetail[cle];
    final tEnCache = _cachePerfDetailTime[cle];
    if (enCache != null &&
        tEnCache != null &&
        DateTime.now().difference(tEnCache) < _ttlPerfDetail) {
      return enCache;
    }

    try {
      final url = kIsWeb
          ? '${Uri.base.origin}/api/pmu/programme/$dateStr/R$numR/C$numC'
              '/performances-detaillees/pretty'
          : '$_pmuBase/programme/$dateStr/R$numR/C$numC'
              '/performances-detaillees/pretty?$_pmuSpec';

      _nbAppelsPerfDetail++;
      final resp = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) {
        // Réponse partielle / indisponible.
        //
        // ENSEMBLE 2 : on ne rend plus systématiquement une map vide alors que
        // le corpus local peut contenir la connaissance déjà payée. Le repli
        // est explicite et tracé ; il ne remplace JAMAIS une réponse
        // authentique (il n'intervient que sur échec), donc l'acquisition de
        // nouvelles connaissances PMU reste prioritaire.
        final noms = nomsParNumero.isNotEmpty
            ? nomsParNumero
            : await CorpusPerformancesService.instance.chargerComposition(
                dateStr: dateStr, numR: numR, numC: numC);
        final repli = await _histosDepuisCorpus(noms);
        _cachePerfDetail[cle] = repli;
        // TTL court conservé : la donnée PMU peut redevenir disponible, il faut
        // retenter. Le repli local, lui, ne périme pas — il sera reconstruit.
        _cachePerfDetailTime[cle] =
            DateTime.now().subtract(_ttlPerfDetail - const Duration(minutes: 5));
        return repli;
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final participants = data['participants'];
      final resultat = <String, _HistoCheval>{};
      // Noms RÉELLEMENT rencontrés dans CETTE réponse. Une réponse partielle
      // (certains partants manquants) ne doit pas faire chercher au corpus des
      // chevaux qu'elle n'a pas nommés.
      final nomsDecouverts = <String, String>{};

      if (participants is List) {
        for (final raw in participants) {
          if (raw is! Map) continue;
          // ⚠️ NE PAS nommer cette variable `num` : cela masquerait le TYPE
          //    Dart `num` et casserait tous les `is num` / `as num` de la
          //    portée (mesuré : 5 erreurs `type_test_with_non_type`).
          final numPmu = raw['numPmu'];
          final nom = raw['nomCheval'] as String? ?? '';
          final cc = raw['coursesCourues'];
          if (numPmu == null || cc is! List) continue;

          final courses = <_CoursePassee>[];
          for (final cr in cc) {
            if (cr is! Map) continue;

            // ── Date : millisecondes + timezoneOffset, en heure locale ──
            final tsMs = cr['date'];
            final tzMs = cr['timezoneOffset'];
            if (tsMs is! num) continue;
            final offset = tzMs is num ? tzMs.toInt() : 0;
            final dateLocale = DateTime.fromMillisecondsSinceEpoch(
              tsMs.toInt() + offset,
              isUtc: true,
            );

            // ── Place RÉELLE du cheval étudié dans cette course passée ──
            //    On ne lit QUE l'entrée `itsHim == true`. Une entrée absente
            //    signifie « le PMU n'a pas publié le détail » : la place reste
            //    0, ce qui n'est compté NI en victoire NI en top 3, mais la
            //    course est bien comptée comme disputée (elle a une date).
            int place = 0;
            final partants = cr['participants'];
            if (partants is List) {
              for (final q in partants) {
                if (q is! Map) continue;
                if (q['itsHim'] != true) continue;
                final pl = q['place'];
                if (pl is Map) {
                  final pv = pl['place'];
                  if (pv is num) place = pv.toInt();
                } else if (pl is num) {
                  place = pl.toInt();
                }
                break;
              }
            }

            courses.add(_CoursePassee(
              dateLocale: dateLocale,
              hippodrome: (cr['hippodrome'] as String? ?? '').trim(),
              discipline: (cr['discipline'] as String? ?? '').toUpperCase(),
              distance: (cr['distance'] as num?)?.toInt() ?? 0,
              etatTerrain: (cr['etatTerrain'] as String? ?? '').trim(),
              place: place,
            ));
          }

          final cleNum = numPmu.toString();
          resultat[cleNum] = _HistoCheval(nomCheval: nom, courses: courses);
          nomsDecouverts[cleNum] = nom;
        }
      }

      // ══════════════════════════════════════════════════════════════════
      //  ENSEMBLE 2 — PERSISTANCE DE CE QUE LE PMU VIENT DE PUBLIER
      //
      //  Avant ce raccordement, `resultat` vivait uniquement en mémoire avec
      //  un TTL de 20 minutes : au redémarrage, toute la connaissance
      //  historique était reperdue, et la même course était retéléchargée
      //  indéfiniment. La table `performances` existait dans le schéma mais
      //  n'était jamais écrite.
      //
      //  Ce qui est écrit : EXACTEMENT ce que le PMU a publié, sans
      //  interprétation, sans calcul de critère, sans fusion d'entités.
      //
      //  ⚠️ CE QUI N'EST JAMAIS ÉCRIT :
      //    • une place non publiée (0 chez le producteur) reste `null` en base,
      //      elle ne devient pas « dernier » (§9) ;
      //    • une distance absente reste `null`, elle ne devient pas 0 ;
      //    • un état de terrain absent reste vide.
      //
      //  L'écriture est idempotente (clé primaire déterministe) : rejouer la
      //  même course n'ajoute rien, mais une correction officielle du PMU est
      //  bien enregistrée (REPLACE, pas IGNORE).
      //
      //  Elle est aussi NON BLOQUANTE : `enregistrer` absorbe toute erreur
      //  SQLite et rend 0. Une panne du corpus ne casse donc jamais l'analyse
      //  d'une course en cours.
      // ══════════════════════════════════════════════════════════════════
      // Mémorisation des noms RÉELLEMENT vus : c'est ce qui rendra le repli
      // local possible plus tard, y compris après un redémarrage suivi d'une
      // coupure réseau (le corpus existerait sinon sans être interrogeable).
      // Écriture STRUCTURÉE en base (table permanente `observations`), plus
      // aucun fichier : la composition est reconstructible depuis SQLite.
      unawaited(CorpusPerformancesService.instance.enregistrerComposition(
        dateStr: dateStr,
        numR: numR,
        numC: numC,
        nomsParNumero: nomsDecouverts,
      ));

      // Écriture en tâche de fond, ASSUMÉE et documentée : elle ne bloque pas
      // l'analyse en cours d'une course. Si le processus est tué avant la fin
      // de l'écriture, aucune connaissance n'est perdue DÉFINITIVEMENT —
      // l'écriture est idempotente et sera rejouée au prochain chargement de
      // cette course ; seul le moment de la persistance est différé.
      unawaited(_persisterCorpus(dateStr, numR, numC, resultat));

      _cachePerfDetail[cle] = resultat;
      _cachePerfDetailTime[cle] = DateTime.now();
      return resultat;
    } catch (e) {
      // Panne réseau, délai dépassé, JSON invalide.
      //
      // ENSEMBLE 2 : repli sur le CORPUS LOCAL avant de déclarer l'absence de
      // connaissance. Conserver la connaissance déjà acquise est explicitement
      // exigé ; la perdre parce que le réseau est coupé ne l'est pas.
      if (kDebugMode) {
        debugPrint('PMU perf-detail R${numR}C$numC indisponible: $e');
      }
      final noms = nomsParNumero.isNotEmpty
          ? nomsParNumero
          : await CorpusPerformancesService.instance.chargerComposition(
              dateStr: dateStr, numR: numR, numC: numC);
      final repli = await _histosDepuisCorpus(noms);
      _cachePerfDetail[cle] = repli;
      _cachePerfDetailTime[cle] =
          DateTime.now().subtract(_ttlPerfDetail - const Duration(minutes: 5));
      return repli;
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  //  ENSEMBLE 2 — RACCORDEMENT PRODUCTEUR → CORPUS LOCAL
  // ══════════════════════════════════════════════════════════════════════


  /// Convertit l'historique décodé en format de transport et l'enregistre.
  ///
  /// Cette méthode ne fait AUCUN calcul : elle transporte. La conversion
  /// « place 0 ⇒ null » est la seule transformation, et elle est requise par
  /// le §9 : chez le producteur, `place` vaut 0 aussi bien pour « non publié »
  /// que pour « non classé ». Écrire 0 en base reviendrait à affirmer une
  /// dernière place qui n'a jamais été constatée.
  static Future<void> _persisterCorpus(
    String dateStr,
    int numR,
    int numC,
    Map<String, _HistoCheval> histos,
  ) async {
    if (histos.isEmpty) return;
    try {
      final parNumero = <String, List<PerformancePmu>>{};
      histos.forEach((numPmu, histo) {
        if (histo.courses.isEmpty) return;
        parNumero[numPmu] = <PerformancePmu>[
          for (final c in histo.courses)
            PerformancePmu(
              nomCheval: histo.nomCheval,
              // Date locale sans fuseau : c'est ce que le producteur a résolu,
              // et le corpus ne prétend pas mieux savoir que lui.
              dateIso: _isoDateDe(c.dateLocale),
              hippodrome: c.hippodrome,
              discipline: c.discipline,
              distance: c.distance > 0 ? c.distance : null,
              // 0 chez le producteur = « non publié / non classé » ⇒ null (§9).
              place: c.place > 0 ? c.place : null,
              reductionKm: null,
              gains: null,
              etatTerrain: c.etatTerrain,
              chargeBrute: '{"origine":"performances-detaillees",'
                  '"R":$numR,"C":$numC,"numPmu":$numPmu}',
            ),
        ];
      });

      await CorpusPerformancesService.instance.enregistrer(
        dateStr: dateStr,
        numR: numR,
        numC: numC,
        parNumero: parNumero,
        source: 'pmu_performances_detaillees',
      );
    } catch (e) {
      // Aucune panne du corpus ne doit remonter : l'analyse continue.
      if (kDebugMode) debugPrint('[ZoneTurf] corpus non persisté : $e');
    }
  }

  /// `AAAA-MM-JJ` à partir d'une date locale. `null` si la date est absurde.
  static String? _isoDateDe(DateTime d) {
    if (d.year < 1900 || d.year > 2200) return null;
    final m = d.month.toString().padLeft(2, '0');
    final j = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$j';
  }

  /// Reconstruit un historique exploitable depuis le CORPUS LOCAL.
  ///
  /// Utilisée **uniquement** quand le PMU n'a rien pu fournir (réseau coupé,
  /// délai dépassé, réponse illisible). Elle ne remplace jamais une réponse
  /// authentique : la source PMU reste prioritaire, conformément à l'exigence
  /// « la présence de connaissances locales ne doit pas empêcher l'acquisition
  /// de nouvelles connaissances PMU ».
  ///
  /// Elle restitue `place` à 0 quand la base porte `null`, ce qui est la
  /// convention du producteur pour « non publié » et laisse les critères dans
  /// leur comportement neutre documenté — aucune victoire ni top 3 inventés.
  static Future<Map<String, _HistoCheval>> _histosDepuisCorpus(
    Map<String, String> nomParNumero,
  ) async {
    if (nomParNumero.isEmpty) return const <String, _HistoCheval>{};
    try {
      final resultat = <String, _HistoCheval>{};
      for (final entree in nomParNumero.entries) {
        final lignes = await CorpusPerformancesService.instance.charger(
          nomBrut: entree.value,
          limite: 30,
        );
        if (lignes.isEmpty) continue;
        final courses = <_CoursePassee>[];
        for (final l in lignes) {
          final date = DateTime.tryParse(l.datePerf ?? '');
          if (date == null) continue;
          courses.add(_CoursePassee(
            dateLocale: date,
            hippodrome: l.hippodrome,
            discipline: l.discipline.toUpperCase(),
            distance: l.distanceMetres ?? 0,
            etatTerrain: l.etatTerrain,
            place: l.place ?? 0,
          ));
        }
        if (courses.isEmpty) continue;
        resultat[entree.key] =
            _HistoCheval(nomCheval: entree.value, courses: courses);
      }
      if (resultat.isNotEmpty && kDebugMode) {
        debugPrint('[ZoneTurf] historique reconstitué depuis le CORPUS LOCAL '
            'pour ${resultat.length} cheval(aux) — PMU indisponible');
      }
      return resultat;
    } catch (e) {
      if (kDebugMode) debugPrint('[ZoneTurf] repli corpus impossible : $e');
      return const <String, _HistoCheval>{};
    }
  }

  /// Agrège l'historique d'un cheval en `statsHippodromeCsv`
  /// au format attendu par `ZtPartant.scoreHippodrome` : `nbCourses|nbVict|nbTop3`.
  ///
  /// ⚠️ CE N'EST PAS UNE STATISTIQUE « À L'HIPPODROME DE LA COURSE ACTUELLE ».
  ///    C'est la statistique du cheval sur l'hippodrome de la course analysée,
  ///    EXACTEMENT comme le demande la définition du critère (comparer les
  ///    performances passées sur le MÊME hippodrome). `hippodromeCible` est
  ///    donc le libellé court de l'hippodrome du jour.
  ///
  ///    Justification de la source : les lettres de la musique ne sont PAS des
  ///    hippodromes (mesuré à Lignières R2 : plat = {'p': 27} et obstacle =
  ///    {'s': 55, 'h': 17, 'c': 7} sur le MÊME hippodrome). L'ancienne
  ///    `_statsHippoDepuisMusique` construisait donc une statistique fausse.
  ///    La source authentique est `coursesCourues[].hippodrome` (100 %).
  ///
  /// ⚠️ Si l'hippodrome cible est inconnu, on renvoie la chaîne VIDE :
  ///    `scoreHippodrome` rend alors 50.0 (neutre explicite), et non une
  ///    statistique sur un hippodrome quelconque.
  static String _statsHippoDepuisHistorique(
    _HistoCheval? histo,
    String hippodromeCible,
  ) {
    if (histo == null || histo.courses.isEmpty) return '';
    final cible = _cleHippodrome(hippodromeCible);
    if (cible.isEmpty) return '';

    int nbC = 0, nbV = 0, nbT3 = 0;
    for (final c in histo.courses) {
      // ⚠️ PAS d'égalité stricte : voir `_memeHippodrome` (défaut mesuré,
      //    4,3 % seulement de correspondances en égalité stricte).
      if (!_memeHippodrome(c.hippodrome, hippodromeCible)) continue;
      nbC++;
      if (c.place == 1) nbV++;
      if (c.place >= 1 && c.place <= 3) nbT3++;
    }
    if (nbC == 0) return '';
    return '$nbC|$nbV|$nbT3';
  }

  /// Agrège l'historique d'un cheval en `statsTerrainCsv`
  /// au format `terrain|nbC|nbV|nbTop3` séparé par `;`.
  ///
  /// ⚠️ DEUX EXIGENCES DU §7 SONT ICI RESPECTÉES LITTÉRALEMENT :
  ///
  ///  ① « Ne confonds pas la surface de la piste avec son état. »
  ///     Le champ lu est `etatTerrain` (« Bon », « Souple », « PSF Standard »…),
  ///     c'est-à-dire l'ÉTAT. La surface (`typePiste` : HERBE, GAZON,
  ///     POUZZOLANE) n'est PAS utilisée ici : elle ne renseigne pas l'état.
  ///
  ///  ② « Ne force pas l'alimentation du critère terrain en trot si les
  ///     données disponibles ne permettent pas une interprétation fiable. »
  ///     Mesure : `etatTerrain` est présent sur 100 % des courses passées en
  ///     Plat / Obstacle / Cross, mais sur 1 à 5 % seulement en Trot. Le code
  ///     n'invente donc rien : en trot, aucune entrée n'est produite et la
  ///     chaîne reste vide ⇒ `scoreTerrain` rend 50.0 (neutre explicite).
  ///     Aucune règle ne dit « si trot alors terrain = X ».
  ///
  /// ⚠️ La normalisation appliquée est celle du CONSOMMATEUR
  ///    (`ZtPartant._normaliserTerrain`), reprise à l'identique ci-dessous
  ///    via `_normaliserTerrainPourStockage`, afin que la chaîne stockée
  ///    puisse être comparée avec égalité stricte par `scoreTerrain`.
  static String _statsTerrainDepuisHistorique(_HistoCheval? histo) {
    if (histo == null || histo.courses.isEmpty) return '';

    final parTerrain = <String, List<int>>{}; // clé → [nbC, nbV, nbT3]
    for (final c in histo.courses) {
      if (c.etatTerrain.trim().isEmpty) continue;
      final norm = _normaliserTerrainPourStockage(c.etatTerrain);
      if (norm.isEmpty) continue;
      final acc = parTerrain.putIfAbsent(norm, () => <int>[0, 0, 0]);
      acc[0]++;
      if (c.place == 1) acc[1]++;
      if (c.place >= 1 && c.place <= 3) acc[2]++;
    }
    if (parTerrain.isEmpty) return '';

    final buf = StringBuffer();
    parTerrain.forEach((terrain, acc) {
      if (buf.isNotEmpty) buf.write(';');
      buf.write('$terrain|${acc[0]}|${acc[1]}|${acc[2]}');
    });
    return buf.toString();
  }

  /// Normalisation IDENTIQUE à `ZtPartant._normaliserTerrain`
  /// (`zt_models.dart`). Elle est dupliquée ici parce que le producteur ne
  /// peut pas importer la méthode privée du modèle ; toute divergence rendrait
  /// la comparaison d'égalité stricte de `scoreTerrain` inopérante.
  /// ⚠️ Toute modification doit être répercutée des DEUX côtés.
  static String _normaliserTerrainPourStockage(String t) {
    final lower = t.toLowerCase();
    if (lower.contains('tres') && lower.contains('lourd')) return 'tres_lourd';
    if (lower.contains('lourd')) return 'lourd';
    if (lower.contains('souple')) return 'souple';
    if (lower.contains('bon')) return 'bon';
    if (lower.contains('sable')) return 'sable';
    if (lower.contains('piste')) return 'sable';
    return lower.replaceAll(' ', '_');
  }

  /// Clé de comparaison d'hippodrome : minuscules, sans accents, sans espaces
  /// superflus. « PORNICHET » et « Pornichet » désignent le même lieu.
  static String _cleHippodrome(String s) {
    const accents = {
      'à': 'a', 'â': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'î': 'i', 'ï': 'i', 'ô': 'o', 'ö': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'œ': 'oe', 'æ': 'ae',
    };
    var t = s.toLowerCase().trim();
    accents.forEach((k, v) => t = t.replaceAll(k, v));
    t = t.replaceAll('-', ' ').replaceAll("'", ' ');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Décide si le libellé d'hippodrome d'une course PASSÉE désigne le MÊME
  /// hippodrome que celui de la course du jour.
  ///
  /// ⚠️ DÉFAUT MESURÉ ET CORRIGÉ — L'ÉGALITÉ STRICTE NE FONCTIONNE PAS.
  ///
  ///   Les deux sources PMU n'emploient pas la même convention de nommage :
  ///
  ///     • `/programme/{date}` → `hippodrome.libelleCourt`
  ///         « VINCENNES », « LE BOUSCAT », « BORELY », « SAINT GALMIER »
  ///     • `/performances-detaillees` → `coursesCourues[].hippodrome`
  ///         « PARIS-VINCENNES », « BORDEAUX-LE BOUSCAT »,
  ///         « MARSEILLE-BORELY », « LYON-PARILLY », « PARISLONGCHAMP »
  ///
  ///   MESURE sur le corpus de 309 courses / 10 journées (26-27/11/2026) :
  ///     • égalité stricte : 706 correspondances sur 16 579 courses passées
  ///       = **4,3 %** ; **57 %** des courses du corpus n'obtenaient AUCUNE
  ///       correspondance ⇒ `statsHippodromeCsv` restait vide ⇒ critère
  ///       `hippodrome` neutre (50.0) même quand l'historique existait.
  ///
  ///   RÈGLE RETENUE, ET MESURÉE AVANT D'ÊTRE ÉCRITE — inclusion d'ensembles
  ///   de JETONS (l'un des deux ensembles de mots contient l'autre) :
  ///     • couverture : **26 / 27** libellés d'hippodrome du corpus ;
  ///     • ambiguïtés (un libellé historique qui désignerait PLUSIEURS
  ///       hippodromes du jour) : **0** ;
  ///     • seul cas non couvert : « LA CÉPIÈRE », absent du corpus
  ///       d'historiques — donc non mesurable, laissé explicitement non résolu
  ///       (le critère reste neutre) plutôt que rapproché par approximation.
  ///
  ///   ⚠️ AUCUNE STATISTIQUE GÉOGRAPHIQUE N'EST INVENTÉE ICI (§6) : on ne
  ///      fusionne que deux libellés qui désignent le même lieu par inclusion
  ///      de jetons, sans table de correspondance écrite à la main.
  static bool _memeHippodrome(String libelleHistorique, String libelleJour) {
    final a = _cleHippodrome(libelleHistorique);
    final b = _cleHippodrome(libelleJour);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    final ja = a.split(' ').where((String w) => w.isNotEmpty).toSet();
    final jb = b.split(' ').where((String w) => w.isNotEmpty).toSet();
    if (ja.isEmpty || jb.isEmpty) return false;
    return ja.containsAll(jb) || jb.containsAll(ja);
  }

  /// Musique filtrée sur les courses passées à ±100 m de la distance du jour.
  ///
  /// FORMAT PRODUIT : `"distance:musique,distance:musique,..."` — exactement
  /// celui que `IaPronosticEngine._scoreDistanceSpecialite` sait lire
  /// (`entry.split(':')`, tolérance ±100 m) et que
  /// `ZtPartant.scoreFormeDistanceSpecifique` sait décoder comme une musique.
  ///
  /// ⚠️ CE FORMAT A ÉTÉ **MESURÉ**, PAS SUPPOSÉ. Une de mes affirmations
  ///    antérieures prétendait ce format « inanalysable ». C'était une
  ///    déduction de lecture, et elle était FAUSSE : mesuré par le test
  ///    `test/audit_dist_spec_format_test.dart` (F1), la musique préfixée
  ///    `"1700:0p9p4p4p0p6p7p"` donne EXACTEMENT le même score que la musique
  ///    nue (`43.26315789473684` dans les deux cas). Le préfixe est neutre.
  ///
  /// ⚠️ La musique d'une course passée est RECONSTRUITE à partir de la place
  ///    réelle, et non recopiée d'un champ texte : `coursesCourues` ne publie
  ///    pas la musique de chaque course, seulement la place. Le token produit
  ///    est `{place}{lettre de discipline}` — c'est la forme exacte d'une
  ///    musique PMU (`1a`, `3p`, `0m`…). Une place non classée produit `0`.
  static String _musiqueDistDepuisHistorique(
    _HistoCheval? histo,
    int distanceCourse,
  ) {
    if (histo == null || histo.courses.isEmpty || distanceCourse <= 0) {
      return '';
    }
    final buf = StringBuffer();
    for (final c in histo.courses) {
      if (c.distance <= 0) continue;
      if ((c.distance - distanceCourse).abs() > 100) continue;
      final lettre = _lettreDisciplineMusique(c.discipline);
      if (lettre.isEmpty) continue;
      if (buf.isNotEmpty) buf.write(',');
      buf.write('${c.distance}:${c.place}$lettre');
    }
    return buf.toString();
  }

  /// Lettre de discipline au format musique PMU.
  /// `a` = attelé, `m` = monté, `p` = plat, `h` = haies, `s` = steeple,
  /// `c` = cross. Chaîne vide pour une discipline non identifiable : aucun
  /// token n'est alors produit, plutôt qu'un token faux.
  static String _lettreDisciplineMusique(String disciplinePmu) {
    final d = disciplinePmu.toUpperCase();
    if (d.contains('ATTELE')) return 'a';
    if (d.contains('MONTE')) return 'm';
    if (d.contains('PLAT')) return 'p';
    if (d.contains('HAIE')) return 'h';
    if (d.contains('STEEPLE')) return 's';
    if (d.contains('CROSS')) return 'c';
    return '';
  }

  /// Compteur de jours de repos depuis la dernière course EFFECTIVEMENT
  /// disputée avant la course analysée.
  ///
  /// ⚠️ EXIGENCES DU §5 RESPECTÉES :
  ///  • la date retenue est la PLUS RÉCENTE des courses passées publiées ;
  ///  • une inscription, un non-partant ou une course future ne peuvent pas y
  ///    figurer, car `coursesCourues` ne contient que des courses courues ;
  ///  • un cheval DÉBUTANT (aucune course passée) ne reçoit PAS zéro : la
  ///    méthode renvoie `null`, et l'appelant conserve alors 0 — valeur que
  ///    `ZtPartant.scoreRepos` traite comme « inconnu ⇒ neutre 50.0 »
  ///    (`if (joursRepos <= 0) return 50.0`). Aucun zéro arbitraire n'est
  ///    fabriqué pour représenter une donnée absente.
  static int? _joursReposDepuisHistorique(_HistoCheval? histo) {
    final d = histo?.dateDerniereCourse;
    if (d == null) return null;
    // Bornage de sécurité : une date aberrante (future, ou antérieure à
    // l'ouverture du service) ne doit pas produire un repos négatif.
    final jours = DateTime.now().difference(d).inDays;
    if (jours < 0 || jours > 2000) return null;
    return jours;
  }

  static String _dateToStr(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}'
        '${d.month.toString().padLeft(2, '0')}'
        '${d.year}';
  }
}

// ══════════════════════════════════════════════════════════════════════
//  HISTORIQUES DÉTAILLÉS PMU — DÉCODAGE DE `performances-detaillees/pretty`
// ══════════════════════════════════════════════════════════════════════
//
//  ORIGINE DES DONNÉES — établie par mesure, pas par documentation.
//
//  Requête mesurée (HTTP 200, 46 675 octets pour R2C1 du 26/11/2026) :
//    GET /programme/{JJMMAAAA}/R{n}/C{n}/performances-detaillees/pretty
//        ?specialisation=INTERNET
//
//  Structure racine mesurée : `{'allure': 'GALOP'|'TROT', 'participants': [...]}`
//
//  Un élément de `participants` porte EXACTEMENT trois clés :
//    numPmu (int), nomCheval (String), coursesCourues (List)
//
//  Un élément de `coursesCourues` porte :
//    date            (int)  — timestamp en MILLISECONDES, minuit LOCAL encodé
//                             en UTC. Mesure : 1794610800000 → 2026-11-13T23:00Z
//                             avec `timezoneOffset` 3600000 ms ⇒ 14/11/2026
//                             00:00 heure locale. La date locale s'obtient par
//                             `DateTime.fromMillisecondsSinceEpoch(date + offset, isUtc: true)`.
//    timezoneOffset  (int)  — décalage en millisecondes
//    hippodrome      (String) — libellé COURT réel (« PORNICHET »). Mesuré 100 %
//                             de présence sur 9 courses / 4 disciplines.
//    nomPrix         (String)
//    discipline      (String) — 'PLAT' | 'STEEPLE_CHASE' | ... (majuscules)
//    allocation      (int)
//    distance        (int)  — en MÈTRES
//    nbParticipants  (int)
//    tempsDuPremier  (int)  — MILLISECONDES du vainqueur (106 660 ms sur 1 700 m)
//    etatTerrain     (String) — ÉTAT du terrain (« PSF Standard », « Bon »…).
//                             Couverture mesurée : 100 % en Plat/Obstacle/Cross,
//                             mais seulement 1 à 5 % en Trot. Le décodage ci-dessous
//                             ne fabrique donc RIEN en trot : il laisse vide.
//    participants    (List) — les partants de CETTE course passée, chacun avec :
//        numPmu, place {place, rawValue, statusArrivee}, nomCheval, nomJockey,
//        poidsJockey (kg, réel), corde (int), distanceAvecPrecedent,
//        itsHim (bool) ← identifie LE cheval étudié, reductionKilometrique (int),
//        distanceParcourue, oeillere
//
//  ⚠️ `reductionKilometrique` est en MILLISECONDES PAR KILOMÈTRE du VAINQUEUR,
//     et non un temps propre. Vérifié arithmétiquement : 106 660 ms ÷ 1,7 km
//     = 62 740, exactement la valeur publiée. Il est IDENTIQUE pour tous les
//     partants d'une même course : ce n'est donc PAS une donnée individuelle.
//     Le champ n'est utilisé ici que pour la statistique de TERRAIN agrégée
//     (nombre de courses / victoires / top 3), jamais pour alimenter un record
//     personnel — voir le §4 du mandat : « N'invente pas un record personnel
//     à partir d'une information qui ne représente pas ce record. »
//
//  ⚠️ `participants` d'une course passée est TRONQUÉ par le PMU : mesuré
//     6 entrées pour `nbParticipants = 12`. La liste n'est donc pas exhaustive,
//     MAIS elle contient toujours l'entrée marquée `itsHim = true` dès lors que
//     le cheval étudié a bien participé. C'est cette entrée, et elle seule, qui
//     est utilisée pour déterminer place / victoire / top 3.
// ══════════════════════════════════════════════════════════════════════

/// Une course passée d'un cheval, réduite à ce qui est réellement exploitable
/// par les critères existants. Aucun champ dérivé n'est stocké.
class _CoursePassee {
  /// Date LOCALE de la course (heure locale, sans fuseau stocké).
  final DateTime dateLocale;

  /// Libellé court de l'hippodrome (« PORNICHET »). Chaîne vide si absent.
  final String hippodrome;

  /// Discipline PMU brute, en majuscules (« PLAT », « ATTELE », « MONTE »…).
  final String discipline;

  /// Distance en mètres. 0 si absente.
  final int distance;

  /// État du terrain tel que publié (« PSF Standard », « Bon »…).
  /// Chaîne VIDE si le PMU ne le publie pas (cas majoritaire en trot).
  final String etatTerrain;

  /// Place réelle du cheval étudié à cette course (0 si non classé / absent).
  final int place;

  _CoursePassee({
    required this.dateLocale,
    required this.hippodrome,
    required this.discipline,
    required this.distance,
    required this.etatTerrain,
    required this.place,
  });
}

/// Historique décodé d'UN cheval pour UNE course.
class _HistoCheval {
  final String nomCheval;
  final List<_CoursePassee> courses;

  _HistoCheval({required this.nomCheval, required this.courses});

  /// Dernière course EFFECTIVEMENT disputée avant la course analysée.
  ///
  /// ⚠️ Le PMU ne publie dans `coursesCourues` que des courses PASSÉES et
  ///    déjà courues : une inscription, un non-partant ou une course future
  ///    n'y figure pas. Il n'y a donc rien à filtrer d'autre que les entrées
  ///    dont la date est illisible. Le tri est décroissant sur la date.
  DateTime? get dateDerniereCourse {
    DateTime? d;
    for (final c in courses) {
      if (d == null || c.dateLocale.isAfter(d)) d = c.dateLocale;
    }
    return d;
  }
}
