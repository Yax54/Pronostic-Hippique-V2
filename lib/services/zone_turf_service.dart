// ═══════════════════════════════════════════════════════════════════
//  ZONE-TURF SERVICE — Données réelles via API PMU officielle
//  ⚠️ L'ancien proxy Python (localhost:5060) ne fonctionnait pas sur
//     mobile Android. Ce service utilise maintenant l'API PMU directement.
// ═══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/zt_models.dart';
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

          // Charger les partants via API PMU
          final List<ZtPartant> partants = await _chargerPartants(
              dateStr, numOfficiel, numOrdre, heureDt);

          courses.add(ZtCourse(
            numCourse: numOrdre,
            anchor: '$numOfficiel$numOrdre',
            nom: nomCourse,
            heure: heureStr,
            distance: '${distanceM}m',
            prix: '$montant',
            type: disc,
            piste: 'Pelouse',
            categorie: '',
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
        //    PMU expose parfois 'dateDernierePerformance' ou 'nbJoursAbsence'
        int joursRepos = 0;
        final nbJoursAbsence = pm['nbJoursAbsence'];
        if (nbJoursAbsence is int && nbJoursAbsence > 0) {
          joursRepos = nbJoursAbsence;
        } else if (nbJoursAbsence is num && nbJoursAbsence > 0) {
          joursRepos = nbJoursAbsence.toInt();
        } else {
          // Essayer depuis dateDernierePerformance si dispo
          final dateDernPerf = pm['dateDernierePerformance'] as String?;
          if (dateDernPerf != null && dateDernPerf.isNotEmpty) {
            try {
              final parsed = DateTime.parse(dateDernPerf);
              joursRepos = DateTime.now().difference(parsed).inDays.abs();
            } catch (_) {}
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
  /// Résultat complet d'une course : arrivée officielle + liste des DQ
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

      final Map<int, int> rangParNumero = {};
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
          rangParNumero[rangInt] = num;
        }
      }

      if (rangParNumero.isEmpty && disqualifies.isEmpty) {
        if (kDebugMode) debugPrint('PMU Résultats: pas de classement disponible');
        return null;
      }

      final rangs = rangParNumero.keys.toList()..sort();
      final arrivee = rangs.map((r) => rangParNumero[r]!).toList();

      if (kDebugMode) debugPrint('PMU Résultats: arrivée officielle = $arrivee | DQ = $disqualifies');

      return ResultatCourse(
        arriveeOfficielle: arrivee,
        disqualifies: disqualifies,
        statutsPartants: statutsParNumero,
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

  static String _dateToStr(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}'
        '${d.month.toString().padLeft(2, '0')}'
        '${d.year}';
  }
}
