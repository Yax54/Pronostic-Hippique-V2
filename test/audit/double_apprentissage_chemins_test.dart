// ═══════════════════════════════════════════════════════════════════════════
//  §3 — ABSENCE DE DOUBLE APPRENTISSAGE SUR LES SEPT CHEMINS D'ENTRÉE
//
//  OBJET : R-7 avait prouvé l'absence de double apprentissage sur le SEUL
//  chemin `enregistrerResultat`. Ce fichier complète la preuve en MESURANT les
//  deux chemins restants qui écrivent des résultats officiels et déclenchent
//  l'apprentissage :
//      • `IaMemoryService.relancerRecuperationPMU(...)` (ia_memory_service:1241)
//      • `IaMemoryService.analyseJourneeComplete(...)`  (ia_memory_service:4652)
//
//  ⚠️ AUCUN ALGORITHME N'EST MODIFIÉ. On ne touche ni au gradient, ni aux
//     poids, ni aux seuils, ni à la calibration, ni au TOP3 Learning, ni à
//     l'ELO. On LIT leurs effets et on compte.
//
//  ── COMMENT « UN APPRENTISSAGE » EST COMPTÉ (compteurs RÉELS) ────────────
//  Aucune instrumentation n'a été ajoutée pour ce test. Deux compteurs de
//  production existent déjà et sont lus tels quels :
//    1. `IaMemoryService.instance.poids.nbMisesAJour` — incrémenté par
//       `_apprendreParGradient()` ET `_apprendreReglesBase()`.
//    2. `IaMemoryService.instance.journal` — UNE `JournalEntree` par exécution
//       d'apprentissage, étiquetée `methode` : 'gradient' | 'regles' |
//       'discipline_gradient'.
//  ⚠️ `nbMisesAJour` seul ne suffit pas : `IaPoidsAdaptatifs` NORMALISE les
//     poids après le gradient, si bien que la VALEUR d'un poids peut revenir à
//     son niveau antérieur alors qu'un apprentissage a bien eu lieu. Le journal
//     est donc le compteur de référence, `nbMisesAJour` le corroborant.
//
//  ── CONTRÔLES POSITIFS (obligatoires) ────────────────────────────────────
//  Mesurer « 0 apprentissage » ne prouve rien si le montage ne PEUT pas
//  apprendre. Chaque scénario comporte donc un contrôle positif qui démontre
//  qu'une exécution SUPPLÉMENTAIRE, elle, incrémente réellement les compteurs.
//  Sans lui, un faux négatif (héritage de test, graine inopérante, seuil de
//  données non atteint) passerait pour une réussite.
//
//  ── PORTÉE RÉELLE DE LA PREUVE — MISE À JOUR APRÈS COUVERTURE ───────────
//  Le commit be406da laissait B-2 OUVERT. C'est désormais FERMÉ, et voici
//  comment, sans embellissement :
//    • CHEMIN A : contrôle positif réel (A-2) — `enregistrerResultat` rend
//      `true`, Δjournal=+1, méthode='regles', nbMisesAJour 12→13.
//    • CHEMIN B : contrôle positif réel et PROBANT (B-2). Le PMU simulé
//      (`http.runWithClient` + `MockClient`, harnais repris de
//      `v10_a6s_production_path_test.dart:167-189`) sert une arrivée
//      ORDONNÉE Quinté ORDRE de 5 chevaux. MESURÉ :
//        nouveaux=1 requêtes=1 arrivée=[2,3,4,5,6]
//        méthodes=[gradient, discipline_gradient]  ← LE GRADIENT, pas les règles
//        Δjournal=2  ΔnbMisesAJour=1
//        rejeu : nouveaux=0  Δjournal=0
//      Le log `[IA Gradient] Mode prudent (13 courses) — lr × 0.3` atteste que
//      `_apprendreParGradient` a bien exécuté son corps, et non délégué à
//      `_apprendreReglesBase` (ce qui arrive quand `avecScores < 3`, l.3864).
//      C'est précisément pourquoi l'historique porte des `scoresCriteres`
//      RENSEIGNÉS : sans eux, un « oui » obtenu par les règles de base
//      n'aurait rien prouvé sur le gradient.
//    • B-4 couvre la contrainte « plusieurs chemins sur les mêmes résultats » :
//      après que B a résolu la course, le chemin A rend `recuperes=0` et
//      Δjournal=0, et le rejeu de B ne consigne rien.
//  ⚠️ CE QUI RESTE HORS PORTÉE : ces mesures utilisent un réseau SIMULÉ. Elles
//     prouvent le fonctionnement des CHEMINS et des GARDES, pas la
//     disponibilité réelle des rapports PMU en production.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/ia_pronostic_engine.dart';

// ─────────────────────────── Graine de l'état mémoire ──────────────────────

// ⚠️ TYPE `Map<String, dynamic>` ET NON `Map<String, double>` — MESURÉ :
//    avec `Map<String, double>`, Dart convertit l'entier `12` en `12.0`, et
//    `IaPoidsAdaptatifs.fromJson` échoue sur `j['nbMisesAJour'] as int?`
//    (« type 'double' is not a subtype of type 'int?' »), ce qui fait tomber
//    `_load()` en erreur et laisse la mémoire VIDE : tous les compteurs
//    restaient à 0 et les cinq scénarios échouaient pour une raison de harnais.
//    La production, elle, écrit bien un `int` (`nbMisesAJour++` sur un champ
//    `int`, puis `toJson()` recopie ce champ). Aucun défaut de production ici.
const Map<String, dynamic> _poidsDefaut = {
  'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
  'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
  'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
  'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05,
  'divergence': 0.04, 'poidsRel': 0.03, 'progression': 0.03,
  'mouvCote': 0.06, 'placeDepart': 0.03,
  // 12 courses déjà résolues : au-dessus du seuil de 10 exigé par le calcul
  // du gradient, afin que le contrôle positif puisse réellement apprendre.
  'nbMisesAJour': 12,
  'calibrationScore': 50.0,
};

String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

IaPronostic _pronostic({
  required String courseKey,
  required DateTime date,
  bool avecResultat = false,
  List<int>? arrivee,
}) =>
    IaPronostic(
      courseKey: courseKey,
      nomCourse: 'PRIX $courseKey',
      hippodrome: 'VINCENNES',
      discipline: 'Trot Attelé',
      datePronostic: date,
      scoresIA: const {
        '1': 100.0, '2': 92.0, '3': 84.0, '4': 76.0, '5': 68.0,
      },
      scoresCriteres: const <String, ScoresCriteres>{},
      varianceScores: 12.0,
      confiancePredite: 70.0,
      typePariConseille: 'Simple Gagnant',
      favoriIaNom: 'CHEVAL_1',
      arriveeReelle: avecResultat ? (arrivee ?? const [1, 2, 3, 4, 5]) : null,
      dateResultat: avecResultat ? date.add(const Duration(hours: 2)) : null,
      resultatsReels: avecResultat,
      scorePerformance: avecResultat ? 50.0 : null,
    );

/// Sème la mémoire avec [pronostics] puis recharge le service.
///
/// ⚠️ GARDE ANTI-FAUX-NÉGATIF : on VÉRIFIE que la graine est réellement
/// chargée. Sans ce contrôle, un `_load()` en erreur laisserait une mémoire
/// VIDE, tous les compteurs à 0, et chaque assertion « Δjournal == 0 »
/// réussirait sans rien prouver — le pire faux positif possible pour ce
/// fichier. La vérification est donc faite ICI, à la source.
Future<void> _semer(List<IaPronostic> pronostics) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'ia_precision_migrated_v3': true,
    'ia_poids_v3': json.encode(_poidsDefaut),
    'ia_seuils_v1': json.encode(<String, dynamic>{}),
    'ia_precision_v2': json.encode(<String, dynamic>{}),
    'ia_stats_labels_v1': json.encode(<String, dynamic>{}),
    'ia_stats_types_v1': <String>[],
    'ia_journal_v2': <String>[],
    'ia_pronostics_v2': pronostics.map((p) => json.encode(p.toJson())).toList(),
  });
  SharedPreferences.resetStatic();
  await IaMemoryService.instance.recharger();

  final mem = IaMemoryService.instance;
  expect(mem.poids.nbMisesAJour, 12,
      reason: 'GARDE : la graine des poids doit être chargée, sinon toute '
          'mesure d\'absence d\'apprentissage serait un faux positif');
  expect(mem.pronostics.length, pronostics.length,
      reason: 'GARDE : les ${pronostics.length} pronostics semés doivent être '
          'chargés (obtenu : ${mem.pronostics.length})');
}

/// 12 courses RÉSOLUES réparties sur les mois précédents : elles constituent
/// l'historique minimal permettant au gradient de s'exécuter (seuil 10).
List<IaPronostic> _historiqueResolu() {
  final base = DateTime.now().subtract(const Duration(days: 200));
  return [
    for (var i = 0; i < 12; i++)
      _pronostic(
        courseKey: 'R${1 + i % 3}C${1 + i % 7}_${_fmt(base.add(Duration(days: i)))}',
        date: base.add(Duration(days: i)),
        avecResultat: true,
        arrivee: const [1, 2, 3, 4, 5],
      ),
  ];
}

// ─────────────────────── Scores de critères AUTHENTIQUES ───────────────────
//
//  ⚠️ POURQUOI CE BLOC EXISTE — MESURÉ, pas supposé.
//
//  `_apprendreParGradient()` exige DEUX conditions (ia_memory_service:3864) :
//     `avecScores.length >= 3`  ← pronostics dont `scoresCriteres` est NON VIDE
//     `nbAvecResultat >= 10`    ← pronostics avec résultat
//  Si `avecScores.length < 3`, la méthode ne fait PAS de gradient : elle
//  délègue à `_apprendreReglesBase()` (l.3871). C'est exactement ce que mon
//  premier montage produisait (`méthode='regles'`), et cela masquait la
//  question posée : « la branche d'apprentissage de `analyseJourneeComplete`
//  apprend-elle réellement ? » — un « oui » obtenu par les règles de base ne
//  prouverait rien sur le gradient.
//
//  On construit donc un historique dont les `scoresCriteres` sont RENSEIGNÉS,
//  avec des valeurs DISCRIMINANTES : celles du favori sont systématiquement
//  hautes et celles du dernier systématiquement basses, si bien que la
//  discrimination par critère est non nulle et que le gradient a de quoi
//  s'appliquer. Aucune formule, aucun poids, aucun seuil n'est touché : on
//  fournit seulement des DONNÉES d'entrée à un algorithme inchangé.

/// Scores de critère d'un cheval, discriminants par NUMÉRO.
ScoresCriteres _scoresPour(int numero) {
  // 1 → 92.0, 5 → 52.0 : décroissance linéaire, bornée.
  final base = 100.0 - numero * 8.0;
  return ScoresCriteres(
    forme: base,
    gains: base,
    record: base,
    cote: base,
    constance: base,
    victoires: base,
    discipline: base,
    distSpec: base,
    jockey: base,
    repos: base,
    hippo: base,
    entraineur: base,
    elo: base,
    terrain: base,
    divergence: base,
    poidsRel: base,
    progression: base,
    mouvCote: base,
    placeDepart: base,
  );
}

/// Scores par NUMÉRO de partant, tels que stockés dans `IaPronostic`.
Map<String, ScoresCriteres> _scoresParNumero() => {
      for (var n = 1; n <= 12; n++) '$n': _scoresPour(n),
    };

// ─────────────────────── Faux serveur PMU (repris de v10) ──────────────────
//
//  Harnais identique à `test/v10_a6s_production_path_test.dart:167-189`, dont
//  l'efficacité est DÉJÀ MESURÉE (`nbNouveauxResultats == 2`). Aucun appel
//  réseau réel : `http.runWithClient` + `MockClient` interceptent tout.

/// Réponse `rapports-definitifs` plausible : Quinté ORDRE → arrivée retenue.
String _reponsePmu(int numGagnant) => json.encode([
      {
        'typePari': 'E_SIMPLE_GAGNANT',
        'rapports': [
          {'combinaison': '$numGagnant', 'dividendePourUnEuro': 350},
        ],
      },
      {
        'typePari': 'E_QUINTE_ORDRE',
        'rapports': [
          {
            'combinaison': '$numGagnant-${numGagnant + 1}-'
                '${numGagnant + 2}-${numGagnant + 3}-${numGagnant + 4}',
          },
        ],
      },
    ]);

/// Exécute [action] avec le PMU simulé.
Future<T> _avecPmuSimule<T>(
  Future<T> Function() action, {
  bool resultatDisponible = true,
  List<Uri>? urlsVues,
}) {
  final client = MockClient((request) async {
    urlsVues?.add(request.url);
    final m = RegExp(r'/C(\d+)/').firstMatch(request.url.path);
    final numC = m != null ? int.tryParse(m.group(1) ?? '0') ?? 0 : 0;
    final corps = resultatDisponible ? _reponsePmu(1 + (numC % 5)) : '[]';
    return http.Response(corps, 200,
        headers: {'content-type': 'application/json'});
  });
  return http.runWithClient(action, () => client);
}

// ─────────────────────── Décor : journée + réunion ────────────────────────

ZtPartant _partant(int n) => ZtPartant(
      numero: '$n',
      nom: 'CHEVAL_$n',
      driver: 'D$n',
      entraineur: 'E$n',
      proprietaire: 'P$n',
      gains: '${1000 * n}',
      record: '1\'10"0',
      musique: '1a2a3a4a5a',
      cote: '${4.0 + n}',
      ageSexe: '5 M',
      poids: 57.0 + n,
      placeDepartInt: n,
      joursRepos: 10 + n,
      hippodromeActuel: 'VINCENNES',
      statsJockeyCsv: 'J|15|40|12',
      statsHippodromeCsv: 'V|20|45|15',
      statsEntraineurCsv: 'E|12|33|8',
      eloRating: 1500.0 + n * 10,
      eloNbCourses: 20,
      eloVariationMois: 5.0,
      statsTerrainCsv: 'bon|6|2|4',
      gainsDernierAn: n * 5000,
    );

ZtCourse _course(int num, DateTime quand) => ZtCourse(
      numCourse: num,
      anchor: 'R1C$num',
      nom: 'PRIX_$num',
      heure: '${quand.hour.toString().padLeft(2, '0')}:'
          '${quand.minute.toString().padLeft(2, '0')}',
      distance: '2700',
      prix: '50000',
      type: 'Trot Attelé',
      piste: 'Sable',
      categorie: 'D',
      isQuinte: true,
      pronosticZt: const [1, 2, 3, 4, 5],
      partants: List.generate(12, (j) => _partant(j + 1)),
      dateStr: _fmt(quand),
    );

ZtReunion _reunion(List<DateTime> departs) => ZtReunion(
      code: 'R1',
      lieu: 'VINCENNES',
      discipline: 'Trot',
      dateStr: _fmt(departs.first),
      courses: [
        for (var i = 0; i < departs.length; i++)
          _course(i + 1, departs[i]),
      ],
    );

/// Crée les pronostics par le chemin de production RÉEL, ce qui garantit des
/// `scoresCriteres` renseignés PAR LE MOTEUR (et non fabriqués par le test).
Future<void> _creerPronostics(List<ZtReunion> reunions) async {
  final batch = <Map<String, dynamic>>[];
  for (final r in reunions) {
    final m = RegExp(r'R(\d+)').firstMatch(r.code);
    final numR = m != null ? int.tryParse(m.group(1) ?? '1') ?? 1 : 1;
    for (final c in r.courses) {
      final key = 'R${numR}C${c.numCourse}_${_fmt(c.heureDateTime)}';
      if (IaMemoryService.instance.getPronostic(key) != null) continue;
      final (pc, sc) = IaPronosticEngine.analyserCourseAvecCriteres(c);
      batch.add({
        'courseKey': key,
        'course': c,
        'partantsClasses': pc,
        'scoresCriteres': sc,
        'confiance': c.confianceIA,
        'typePariConseille': 'Quinté+',
      });
    }
  }
  await IaMemoryService.instance.enregistrerPronosticsBatch(batch);
}


class _Compteurs {
  final int misesAJour;
  final int journal;
  // `JournalEntree.methode` est nullable dans le modèle de production : on
  // conserve le type exact, sans le normaliser, pour ne rien inventer.
  final List<String?> methodes;

  const _Compteurs(this.misesAJour, this.journal, this.methodes);

  static _Compteurs lire() => _Compteurs(
        IaMemoryService.instance.poids.nbMisesAJour,
        IaMemoryService.instance.journal.length,
        IaMemoryService.instance.journal
            .map((e) => e.methode)
            .toList(growable: false),
      );

  int deltaMisesAJour(_Compteurs avant) => misesAJour - avant.misesAJour;
  int deltaJournal(_Compteurs avant) => journal - avant.journal;

  /// Méthodes d'apprentissage APPARUES entre [avant] et maintenant.
  List<String?> nouvellesMethodes(_Compteurs avant) {
    final vues = avant.methodes.length;
    return methodes.skip(vues).toList(growable: false);
  }

  @override
  String toString() => 'nbMisesAJour=$misesAJour journal=$journal '
      'méthodes=$methodes';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═════════════════════════════════════════════════════════════════════════
  //  CHEMIN A — `relancerRecuperationPMU`
  //
  //  Ce chemin sélectionne les pronostics PASSÉS sans résultat, interroge le
  //  PMU, puis appelle `enregistrerResultat(...)` (l.1766). L'apprentissage est
  //  donc déclenché par `enregistrerResultat` — mais il faut PROUVER qu'il ne
  //  l'est qu'UNE fois, et qu'un second passage sur le même état n'apprend
  //  rien de plus.
  // ═════════════════════════════════════════════════════════════════════════
  group('CHEMIN A — relancerRecuperationPMU', () {
    test('A-1 — un pronostic déjà résolu ne déclenche AUCUN apprentissage',
        () async {
      // État : historiques résolus + UN pronostic DÉJÀ résolu et récent.
      // Ce pronostic est exclu par le filtre `if (p.resultatsReels) return
      // false;` (l.1252) : il ne peut donc pas être réenregistré.
      final recent = DateTime.now().subtract(const Duration(hours: 2));
      final cle = 'R1C1_${_fmt(recent)}';
      await _semer([
        ..._historiqueResolu(),
        _pronostic(
            courseKey: cle, date: recent, avecResultat: true),
      ]);

      final avant = _Compteurs.lire();

      final res = await IaMemoryService.instance.relancerRecuperationPMU();
      final apres = _Compteurs.lire();

      debugPrint('[A-1] AVANT  $avant');
      debugPrint('[A-1] APRÈS  $apres | résultat du chemin = $res');
      debugPrint('[A-1] ΔnbMisesAJour=${apres.deltaMisesAJour(avant)} '
          'Δjournal=${apres.deltaJournal(avant)} '
          'nouvelles méthodes=${apres.nouvellesMethodes(avant)}');

      // Aucun pronostic passé SANS résultat → le chemin n'a rien à faire.
      expect(res['recuperes'], 0,
          reason: 'aucun pronostic en attente : rien ne peut être récupéré');
      expect(apres.deltaJournal(avant), 0,
          reason: 'ABSENCE DE DOUBLE APPRENTISSAGE : un pronostic déjà résolu '
              'est exclu en amont, donc `enregistrerResultat` n\'est pas '
              'appelé et le journal d\'apprentissage ne bouge pas');
      expect(apres.nouvellesMethodes(avant), isEmpty,
          reason: 'aucune méthode d\'apprentissage ne doit apparaître');
    });

    test('A-2 — CONTRÔLE POSITIF : une exécution supplémentaire apprend',
        () async {
      // Le contrôle positif est indispensable : sans lui, A-1 pourrait réussir
      // parce que le montage est incapable d'apprendre, et ne prouverait rien.
      //
      // On établit un état où `enregistrerResultat` est réellement atteignable
      // — un pronostic RÉSOLU est enregistré une première fois — puis on
      // vérifie que les compteurs BOUGENT. La mesure porte sur `enregistrerResultat`
      // lui-même, seule partie apprenante du chemin A, ce qui isole la preuve
      // de toute dépendance réseau.
      final recent = DateTime.now().subtract(const Duration(hours: 2));
      final cle = 'R2C2_${_fmt(recent)}';
      await _semer([
        ..._historiqueResolu(),
        _pronostic(courseKey: cle, date: recent),
      ]);

      final avant = _Compteurs.lire();
      debugPrint('[A-2] AVANT  $avant');

      // L'enregistrement d'un résultat NOUVEAU est exactement ce que le
      // chemin A fait à la ligne 1766 après une récupération réussie.
      final ecrit = await IaMemoryService.instance.enregistrerResultat(
        courseKey: cle,
        arriveeReelle: const [1, 2, 3, 4, 5],
      );

      final apres = _Compteurs.lire();
      debugPrint('[A-2] APRÈS  $apres | enregistrerResultat=$ecrit');
      debugPrint('[A-2] ΔnbMisesAJour=${apres.deltaMisesAJour(avant)} '
          'Δjournal=${apres.deltaJournal(avant)} '
          'nouvelles méthodes=${apres.nouvellesMethodes(avant)}');

      // CONTRÔLE POSITIF : le montage SAIT apprendre.
      expect(ecrit, isTrue,
          reason: 'CONTRÔLE POSITIF : le résultat nouveau doit être accepté');
      expect(apres.deltaJournal(avant), greaterThan(0),
          reason: 'CONTRÔLE POSITIF : un apprentissage doit réellement être '
              'consigné. Si ce test échouait, A-1 ne prouverait rien');

      // Un SECOND enregistrement de la même arrivée ne doit rien réapprendre.
      final avant2 = _Compteurs.lire();
      final ecrit2 = await IaMemoryService.instance.enregistrerResultat(
        courseKey: cle,
        arriveeReelle: const [1, 2, 3, 4, 5],
      );
      final apres2 = _Compteurs.lire();
      debugPrint('[A-2] REJEU  Δjournal=${apres2.deltaJournal(avant2)} '
          'enregistrerResultat=$ecrit2');

      expect(ecrit2, isFalse,
          reason: 'un résultat DÉJÀ connu est refusé par la garde '
              'd\'idempotence d\'`enregistrerResultat`');
      expect(apres2.deltaJournal(avant2), 0,
          reason: 'ABSENCE DE DOUBLE APPRENTISSAGE : le rejeu ne consigne '
              'aucun nouvel apprentissage');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  CHEMIN B — `analyseJourneeComplete`
  //
  //  Ce chemin N'APPELLE PAS `enregistrerResultat` : il écrit directement
  //  `_pronostics[idx]` (l.5107) puis déclenche `_apprendreParGradient` /
  //  `_apprendreParDiscipline` UNIQUEMENT si `nbNouveauxResultats > 0`
  //  (l.5160). C'est donc un chemin d'apprentissage INDÉPENDANT, qu'il fallait
  //  mesurer séparément.
  // ═════════════════════════════════════════════════════════════════════════
  group('CHEMIN B — analyseJourneeComplete', () {
    // ── Historique permettant au GRADIENT de s'exécuter réellement ────────
    // 12 courses RÉSOLUES et dotées de `scoresCriteres` RENSEIGNÉS (sinon
    // `avecScores.length < 3` ⇒ délégation aux règles de base, l.3871).
    List<IaPronostic> historiqueGradient() {
      final base = DateTime.now().subtract(const Duration(days: 200));
      return [
        for (var i = 0; i < 12; i++)
          IaPronostic(
            courseKey:
                'R${1 + i % 3}C${1 + i % 7}_${_fmt(base.add(Duration(days: i)))}',
            nomCourse: 'PRIX HIST $i',
            hippodrome: 'VINCENNES',
            discipline: 'Trot Attelé',
            datePronostic: base.add(Duration(days: i)),
            scoresIA: const {
              '1': 100.0, '2': 92.0, '3': 84.0, '4': 76.0, '5': 68.0,
            },
            // ★ SCORES RENSEIGNÉS : condition `avecScores >= 3` satisfaite.
            scoresCriteres: _scoresParNumero(),
            varianceScores: 12.0,
            confiancePredite: 70.0,
            typePariConseille: 'Simple Gagnant',
            favoriIaNom: 'CHEVAL_1',
            arriveeReelle: const [1, 2, 3, 4, 5],
            dateResultat: base.add(Duration(days: i, hours: 2)),
            resultatsReels: true,
            scorePerformance: 50.0,
          ),
      ];
    }

    /// Prépare une journée passée (J-1) dont les courses peuvent être
    /// analysées : départ à 14h15, largement au-delà des 30 min requises.
    Future<DateTime> preparerJournee(List<ZtReunion> out) async {
      final j1 = DateTime.now().subtract(const Duration(days: 1));
      final depart = DateTime(j1.year, j1.month, j1.day, 14, 15);
      final reunion = _reunion([depart]);
      out.add(reunion);
      await _creerPronostics([reunion]);
      return depart;
    }

    test('B-1 — journée SANS nouveau résultat : aucun apprentissage', () async {
      final aujourdhui = DateTime.now();
      await _semer([
        ..._historiqueResolu(),
        for (var c = 1; c <= 3; c++)
          _pronostic(
              courseKey: 'R1C${c}_${_fmt(aujourdhui)}',
              date: aujourdhui,
              avecResultat: true),
      ]);

      final avant = _Compteurs.lire();
      final res = await _avecPmuSimule(
          () => IaMemoryService.instance.analyseJourneeComplete());
      final apres = _Compteurs.lire();

      debugPrint('[B-1] AVANT  $avant');
      debugPrint('[B-1] APRÈS  $apres | nouveaux='
          '${res.nbNouveauxResultats}');
      debugPrint('[B-1] ΔnbMisesAJour=${apres.deltaMisesAJour(avant)} '
          'Δjournal=${apres.deltaJournal(avant)} '
          'méthodes=${apres.nouvellesMethodes(avant)}');

      expect(res.nbNouveauxResultats, 0,
          reason: 'toutes les courses du jour sont déjà résolues');
      expect(apres.deltaJournal(avant), 0,
          reason: 'ABSENCE DE DOUBLE APPRENTISSAGE : sans nouveau résultat, '
              'la garde `if (nbNouveauxResultats > 0)` (l.5160) empêche '
              'TOUT apprentissage');
      expect(apres.nouvellesMethodes(avant), isEmpty);
    });

    test('B-2 — BRANCHE POSITIVE : un nouveau résultat fait RÉELLEMENT '
        'apprendre, mesuré sur le GRADIENT', () async {
      // ═══════════════════════════════════════════════════════════════════
      //  C'est LE scénario que le commit be406da avait laissé ouvert : il
      //  mesurait `nbNouveauxResultats=0` et n'exécutait donc jamais la
      //  branche d'apprentissage. Ici le PMU simulé sert une arrivée
      //  ORDONNÉE (Quinté ORDRE, 5 chevaux ≥ kLongueurMinimaleArrivee),
      //  le pronostic est réellement résolu, `nbNouveauxResultats` > 0, et
      //  l'apprentissage est déclenché pour de bon.
      // ═══════════════════════════════════════════════════════════════════
      final reunions = <ZtReunion>[];
      await _semer(historiqueGradient());
      final depart = await preparerJournee(reunions);
      expect(IaMemoryService.instance.pronostics.length, 13,
          reason: 'GARDE : 12 d\'historique + 1 du jour');

      final avant = _Compteurs.lire();
      final urls = <Uri>[];
      final res = await _avecPmuSimule(
        () => IaMemoryService.instance.analyseJourneeComplete(date: depart),
        urlsVues: urls,
      );
      final apres = _Compteurs.lire();
      final prono = IaMemoryService.instance
          .pronostics
          .firstWhere((p) => p.datePronostic.day == depart.day);

      debugPrint('[B-2] AVANT  $avant');
      debugPrint('[B-2] APRÈS  $apres | nouveaux='
          '${res.nbNouveauxResultats} réussies=${res.nbCoursesAnalysees} '
          'échouées=${res.nbCoursesEchouees} sansRésultat='
          '${res.nbSansResultat} requêtes=${urls.length}');
      debugPrint('[B-2] ΔnbMisesAJour=${apres.deltaMisesAJour(avant)} '
          'Δjournal=${apres.deltaJournal(avant)} '
          'méthodes=${apres.nouvellesMethodes(avant)}');
      debugPrint('[B-2] résultat enregistré : resultatsReels='
          '${prono.resultatsReels} arrivée=${prono.arriveeReelle}');

      // ── 1. RÉCUPÉRATION EFFECTIVE d'un résultat officiel ──────────────
      expect(urls, isNotEmpty,
          reason: 'la production doit avoir interrogé le PMU');
      expect(res.nbNouveauxResultats, greaterThan(0),
          reason: 'CONTRÔLE POSITIF — CONDITION D\'ENTRÉE DE LA BRANCHE : '
              'sans nouveau résultat, `if (nbNouveauxResultats > 0)` '
              '(l.5160) n\'est pas pris et ce test ne prouverait rien');
      expect(prono.resultatsReels, isTrue,
          reason: 'le résultat officiel doit être réellement enregistré');
      expect(prono.arriveeReelle, isNotNull);
      expect(prono.arriveeReelle!.length, greaterThanOrEqualTo(3),
          reason: 'arrivée ORDONNÉE retenue par la décision partagée');

      // ── 2. DÉCLENCHEMENT RÉEL de l'apprentissage ──────────────────────
      expect(apres.deltaJournal(avant), greaterThan(0),
          reason: 'CONTRÔLE POSITIF : la branche d\'apprentissage de '
              '`analyseJourneeComplete` doit réellement consigner');
      final methodes = apres.nouvellesMethodes(avant);
      expect(methodes, isNotEmpty);
      // ★ MESURE DÉCISIVE : le GRADIENT, pas seulement les règles de base.
      //   Présence de `scoresCriteres` sur l'historique ⇒ `avecScores >= 3`
      //   ⇒ le gradient s'exécute au lieu de déléguer (l.3864-3871).
      expect(methodes.contains('gradient'), isTrue,
          reason: 'MESURÉ : méthodes consignées = $methodes. La présence de '
              '"gradient" prouve que la branche a exécuté le VRAI gradient '
              '— "regles" seul signifierait que le seuil `avecScores >= 3` '
              'n\'était pas atteint et n\'établirait rien sur le gradient');
      expect(methodes.where((m) => m == 'gradient').length, 1,
          reason: 'EXACTEMENT UN apprentissage par gradient par exécution : '
              'un second déclenchement serait un double apprentissage');

      // ── 3. ÉVOLUTION DES COMPTEURS DE PRODUCTION ──────────────────────
      expect(apres.deltaMisesAJour(avant), greaterThan(0),
          reason: '`nbMisesAJour` doit corroborer le journal');
      expect(res.nbMisesAJour, greaterThan(0),
          reason: 'le compteur du résultat d\'analyse doit être non nul');
      expect(res.succes, isTrue);

      // ── 4. REJEU : aucun nouvel apprentissage ─────────────────────────
      final avantRejeu = _Compteurs.lire();
      final res2 = await _avecPmuSimule(
          () => IaMemoryService.instance.analyseJourneeComplete(date: depart));
      final apresRejeu = _Compteurs.lire();
      debugPrint('[B-2] REJEU nouveaux=${res2.nbNouveauxResultats} '
          'Δjournal=${apresRejeu.deltaJournal(avantRejeu)}');

      expect(res2.nbNouveauxResultats, 0,
          reason: 'le rejeu des MÊMES résultats ne produit rien de nouveau');
      expect(apresRejeu.deltaJournal(avantRejeu), 0,
          reason: 'ABSENCE DE DOUBLE APPRENTISSAGE : le rejeu ne consigne '
              'aucun apprentissage supplémentaire');
      expect(apresRejeu.nouvellesMethodes(avantRejeu), isEmpty);
      expect(apresRejeu.deltaMisesAJour(avantRejeu), 0);

      // ── 5. Pas de double traitement : un seul pronostic résolu ────────
      final nbResolus = IaMemoryService.instance.pronostics
          .where((p) => p.resultatsReels)
          .length;
      expect(nbResolus, 13,
          reason: 'MESURÉ : 12 d\'historique + 1 du jour, pas 14 — un double '
              'traitement créerait un doublon');
      expect(IaMemoryService.instance.pronostics.length, 13,
          reason: 'aucun pronostic créé par l\'analyse');
    });

    test('B-3 — deux exécutions consécutives n\'apprennent pas deux fois',
        () async {
      final reunions = <ZtReunion>[];
      await _semer(historiqueGradient());
      final depart = await preparerJournee(reunions);

      final avant = _Compteurs.lire();
      await _avecPmuSimule(
          () => IaMemoryService.instance.analyseJourneeComplete(date: depart));
      final apres1 = _Compteurs.lire();
      await _avecPmuSimule(
          () => IaMemoryService.instance.analyseJourneeComplete(date: depart));
      final apres2 = _Compteurs.lire();

      debugPrint('[B-3] cycle 1 : Δjournal=${apres1.deltaJournal(avant)} '
          'méthodes=${apres1.nouvellesMethodes(avant)}');
      debugPrint('[B-3] cycle 2 : Δjournal=${apres2.deltaJournal(apres1)} '
          'méthodes=${apres2.nouvellesMethodes(apres1)}');

      // CONTRÔLE POSITIF : le 1er cycle a bien appris.
      expect(apres1.deltaJournal(avant), greaterThan(0),
          reason: 'CONTRÔLE POSITIF : sans apprentissage au cycle 1, '
              'l\'absence au cycle 2 ne prouverait rien');
      expect(apres2.deltaJournal(apres1), 0,
          reason: 'ABSENCE DE DOUBLE APPRENTISSAGE : relancer l\'analyse sur '
              'un état inchangé ne consigne RIEN de plus');
    });

    test('B-4 — deux CHEMINS de production sur les mêmes résultats : '
        'aucune double prise en compte', () async {
      // ═══════════════════════════════════════════════════════════════════
      //  Obligation « absence de double traitement lorsque plusieurs chemins
      //  accèdent aux mêmes résultats ».
      //  On résout la course par `analyseJourneeComplete` (chemin B), puis on
      //  demande à `relancerRecuperationPMU` (chemin A) de traiter la MÊME
      //  course, puis on rejoue une analyse. Chaque chemin doit constater
      //  que le résultat est DÉJÀ connu et n'apprendre rien.
      // ═══════════════════════════════════════════════════════════════════
      final reunions = <ZtReunion>[];
      await _semer(historiqueGradient());
      final depart = await preparerJournee(reunions);

      // 1) Chemin B résout la course.
      final resB = await _avecPmuSimule(
          () => IaMemoryService.instance.analyseJourneeComplete(date: depart));
      expect(resB.nbNouveauxResultats, greaterThan(0),
          reason: 'CONTRÔLE POSITIF : le chemin B doit avoir résolu');
      final apresB = _Compteurs.lire();

      // 2) Chemin A sur le même état → la course est déjà résolue.
      final resA = await _avecPmuSimule(
          () => IaMemoryService.instance.relancerRecuperationPMU());
      final apresA = _Compteurs.lire();
      debugPrint('[B-4] après B : journal=${apresB.journal} mises='
          '${apresB.misesAJour} | chemin A recuperes=${resA['recuperes']} '
          'Δjournal=${apresA.deltaJournal(apresB)}');

      expect(resA['recuperes'], 0,
          reason: 'le chemin A ne doit rien récupérer : le résultat est déjà '
              'connu — c\'est exactement la protection anti-double-traitement');
      expect(apresA.deltaJournal(apresB), 0,
          reason: 'ABSENCE DE DOUBLE TRAITEMENT ENTRE CHEMINS : le passage de '
              'A après B ne consigne aucun apprentissage');

      // 3) Rejeu du chemin B → toujours rien.
      final resB2 = await _avecPmuSimule(
          () => IaMemoryService.instance.analyseJourneeComplete(date: depart));
      final apresB2 = _Compteurs.lire();
      debugPrint('[B-4] rejeu B nouveaux=${resB2.nbNouveauxResultats} '
          'Δjournal=${apresB2.deltaJournal(apresA)}');

      expect(resB2.nbNouveauxResultats, 0);
      expect(apresB2.deltaJournal(apresA), 0);

      // Le résultat n'a été compté qu'UNE fois.
      final nbResolus = IaMemoryService.instance.pronostics
          .where((p) => p.resultatsReels)
          .length;
      expect(nbResolus, 13,
          reason: 'un seul enregistrement, quel que soit le nombre de chemins');
    });
  });
}
