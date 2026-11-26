// ═══════════════════════════════════════════════════════════════════════════
//  HARNAIS DE REJEU — CORPUS PMU AUTHENTIQUE APPARIÉ
//
//  OBJET : rejouer la chaîne de PRODUCTION (`ZoneTurfService.chargerProgramme`)
//          en servant CHAQUE endpoint avec SA réponse réelle, afin de mesurer
//          ce que le producteur alimente réellement.
//
//  ⚠️ LE DÉFAUT DE MESURE PRÉCÉDENT (identifié, corrigé ici)
//     Le premier test A5 utilisait un `MockClient` qui renvoyait le corps de
//     `/participants` à TOUTE URL profonde, y compris
//     `/performances-detaillees/pretty`. Or ce dernier endpoint renvoie
//     `{allure, participants:[{numPmu, nomCheval, coursesCourues}]}`, une
//     structure TOTALEMENT DIFFÉRENTE : `coursesCourues` absent ⇒ historique
//     vide ⇒ `joursRepos`, `terrain`, `hippodrome` restaient à 0.
//     Ce n'était donc PAS un défaut du producteur, mais un défaut du HARNAIS.
//     Ce fichier corrige le harnais, pas la production.
//
//  SOURCE DU CORPUS : `test/fixtures_corpus/` — copies INTÉGRALES des réponses
//     `https://turfinfo.api.pmu.fr/rest/client/7/programme/{date}/R{n}/C{n}/
//      {participants|performances-detaillees/pretty}?specialisation=INTERNET`
//     récoltées le 2026-11-26/27 sur 309 courses / 10 journées.
//     Aucune clé ajoutée, aucune valeur modifiée, aucun champ synthétisé.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/zone_turf_service.dart';

/// Métadonnées d'une course du corpus.
class CorpusCourse {
  final String key;
  final String date; // DDMMYYYY
  final int numR;
  final int numC;
  final String discipline;
  final String specialite;
  final int distance;
  final String hippodrome;
  final String? typePiste;
  final String? categorie;
  final int nParticipants;

  const CorpusCourse({
    required this.key,
    required this.date,
    required this.numR,
    required this.numC,
    required this.discipline,
    required this.specialite,
    required this.distance,
    required this.hippodrome,
    required this.typePiste,
    required this.categorie,
    required this.nParticipants,
  });

  /// Date de départ réelle encodée dans la clé (DDMMYYYY).
  DateTime get dateReelle => DateTime(
        int.parse(date.substring(4, 8)),
        int.parse(date.substring(2, 4)),
        int.parse(date.substring(0, 2)),
      );
}

const String kCorpusDir = 'test/fixtures_corpus';

/// Charge le manifeste du corpus.
List<CorpusCourse> chargerManifeste() {
  final File f = File('$kCorpusDir/manifest.json');
  final List<dynamic> raw = jsonDecode(f.readAsStringSync()) as List<dynamic>;
  return raw.map((dynamic e) {
    final Map<String, dynamic> m = e as Map<String, dynamic>;
    return CorpusCourse(
      key: m['key'] as String,
      date: m['date'] as String,
      numR: m['numR'] as int,
      numC: m['numC'] as int,
      discipline: m['discipline'] as String,
      specialite: m['specialite'] as String,
      distance: m['distance'] as int,
      hippodrome: m['hippodrome'] as String,
      typePiste: m['typePiste'] as String?,
      categorie: m['categorie'] as String?,
      nParticipants: m['nParticipants'] as int,
    );
  }).toList();
}

/// Le manifeste filtré par discipline.
List<CorpusCourse> corpusDe(String discipline) =>
    chargerManifeste().where((CorpusCourse c) => c.discipline == discipline).toList();

Map<String, dynamic> _lire(String nom) =>
    jsonDecode(File('$kCorpusDir/$nom').readAsStringSync())
        as Map<String, dynamic>;

String _ddmmyyyy(DateTime d) => '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

/// Programme PMU reconstruit pour LA course du corpus.
///
/// ⚠️ Seules les clés RÉELLEMENT lues par `ZoneTurfService.chargerProgramme`
///    sont fournies. Les VALEURS de ces clés proviennent du manifeste, donc du
///    programme PMU authentique (discipline, spécialité, distance, hippodrome,
///    type de piste, catégorie). Aucune donnée de participant n'est fabriquée :
///    les participants viennent du fichier `_participants.json` réel.
Map<String, dynamic> programmeReconstruit(CorpusCourse c) {
  final DateTime depart = c.dateReelle.add(const Duration(hours: 13));
  return <String, dynamic>{
    'programme': <String, dynamic>{
      'date': _ddmmyyyy(depart),
      'reunions': <Map<String, dynamic>>[
        <String, dynamic>{
          'numOfficiel': c.numR,
          'dateReunion': depart.millisecondsSinceEpoch,
          'hippodrome': <String, dynamic>{
            'libelleCourt': c.hippodrome,
            'libelleLong': 'HIPPODROME DE ${c.hippodrome}',
          },
          'pays': <String, dynamic>{'code': 'FRA'},
          'courses': <Map<String, dynamic>>[
            <String, dynamic>{
              'numOrdre': c.numC,
              'numReunion': c.numR,
              'libelle': 'CORPUS ${c.key}',
              'distance': c.distance,
              'montantPrix': 40000,
              'discipline': c.discipline,
              'specialite': c.specialite,
              'heureDepart': depart.millisecondsSinceEpoch,
              if (c.typePiste != null) 'typePiste': c.typePiste,
              if (c.categorie != null) 'categorieParticularite': c.categorie,
              'paris': <Map<String, dynamic>>[
                <String, dynamic>{'typePari': 'E_SIMPLE_GAGNANT'},
              ],
            },
          ],
        },
      ],
    },
  };
}

/// Client qui sert CHAQUE endpoint avec sa réponse RÉELLE.
///
/// Routage STRICT sur le chemin :
///   • `.../participants`                  → `<key>_participants.json`
///   • `.../performances-detaillees/...`   → `<key>_perfdet.json` (404 si vide)
///   • `programme/{date}` (racine)          → programme reconstruit
/// Ce routage est le SEUL correctif apporté : il ne modifie aucune donnée.
http.Client clientPourCorpus(CorpusCourse c) {
  final Map<String, dynamic> parts = _lire('${c.key}_participants.json');
  final Map<String, dynamic> perf = _lire('${c.key}_perfdet.json');

  return MockClient((http.Request req) async {
    final String p = req.url.path;
    if (p.contains('performances-detaillees')) {
      // Réponse réelle : si le fichier est vide (`{}`), on rejoue une 404,
      // ce qui est le comportement authentique observé pour les courses sans
      // historique publié. On ne fabrique ni `participants` ni `allure`.
      if (perf.isEmpty) return http.Response('', 404);
      return http.Response(json.encode(perf), 200,
          headers: <String, String>{'content-type': 'application/json'});
    }
    if (p.contains('participants')) {
      return http.Response(json.encode(parts), 200,
          headers: <String, String>{'content-type': 'application/json'});
    }
    return http.Response(json.encode(programmeReconstruit(c)), 200,
        headers: <String, String>{'content-type': 'application/json'});
  });
}

/// Rejoue le producteur réel sur une course du corpus.
///
/// ⚠️ `ZoneTurfService.chargerProgramme` accepte une `date` : la date réelle de
///    la course est passée, de sorte que l'URL demandée corresponde à la clé.
///    Le client Mock ignore l'URL réelle et sert toujours le corpus demandé.
Future<List<ZtReunion>> rejouerCourse(CorpusCourse c) async {
  late List<ZtReunion> reunions;
  await http.runWithClient(() async {
    reunions = await ZoneTurfService.chargerProgramme(
      forceRefresh: true,
      date: c.dateReelle,
    );
  }, () => clientPourCorpus(c));
  return reunions;
}

/// Réinitialise les caches statiques du producteur entre deux rejeux.
void purgerProducteur() {
  ZoneTurfService.viderCachePourResetComplet();
}
