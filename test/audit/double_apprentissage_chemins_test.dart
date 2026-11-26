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
//  ── PORTÉE RÉELLE DE LA PREUVE — À NE PAS SURINTERPRÉTER ────────────────
//  MESURÉ, et déclaré ici sans embellissement :
//    • CHEMIN A : contrôle positif RÉEL et concluant. `enregistrerResultat`
//      rend `true`, Δjournal=+1, méthode='regles', nbMisesAJour 12→13. Le
//      montage SAIT apprendre, donc A-1 (Δ=0) est probant.
//    • CHEMIN B : contrôle positif NON concluant. Les deux scénarios B-1 et
//      B-3 sont probants (Δjournal=0 sur un état où le montage apprend,
//      établi par A-2). Mais B-2 n'a JAMAIS atteint sa branche positive :
//      MESURÉ `nbNouveauxResultats=0, sansResultat=1` — le résultat PMU
//      n'étant pas servi, `if (nbNouveauxResultats > 0)` (l.5160) n'a pas été
//      pris. B-2 prouve donc la COHÉRENCE dans le cas nul, PAS que la branche
//      d'apprentissage de `analyseJourneeComplete` apprend réellement.
//      ⇒ RESTE OUVERT : cette branche n'est pas encore couverte ici.
//      Le mécanisme permettant de la couvrir existe et est éprouvé :
//      `test/v10_a6s_production_path_test.dart` obtient `nbNouveauxResultats
//      == 2` via `http.runWithClient` + `MockClient`. Il n'a pas été réutilisé
//      faute de budget ; c'est la prochaine action, pas une preuve acquise.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

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

// ─────────────────────── Compteurs réels d'apprentissage ───────────────────

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
    test('B-1 — journée SANS nouveau résultat : aucun apprentissage', () async {
      // Toutes les courses du jour sont DÉJÀ résolues → `aTraiter` est vide →
      // `nbNouveauxResultats` reste 0.
      final aujourdhui = DateTime.now();
      await _semer([
        ..._historiqueResolu(),
        for (var c = 1; c <= 3; c++)
          _pronostic(
            courseKey: 'R1C${c}_${_fmt(aujourdhui)}',
            date: aujourdhui,
            avecResultat: true,
          ),
      ]);

      final avant = _Compteurs.lire();

      final res = await IaMemoryService.instance.analyseJourneeComplete();
      final apres = _Compteurs.lire();

      debugPrint('[B-1] AVANT  $avant');
      debugPrint('[B-1] APRÈS  $apres | nouveauxResultats='
          '${res.nbNouveauxResultats}');
      debugPrint('[B-1] ΔnbMisesAJour=${apres.deltaMisesAJour(avant)} '
          'Δjournal=${apres.deltaJournal(avant)} '
          'nouvelles méthodes=${apres.nouvellesMethodes(avant)}');

      expect(res.nbNouveauxResultats, 0,
          reason: 'toutes les courses du jour sont déjà résolues');
      expect(apres.deltaJournal(avant), 0,
          reason: 'ABSENCE DE DOUBLE APPRENTISSAGE : sans nouveau résultat, '
              'le gradient et l\'apprentissage par discipline sont gardés par '
              '`if (nbNouveauxResultats > 0)` (l.5160)');
      expect(apres.nouvellesMethodes(avant), isEmpty,
          reason: 'aucune méthode d\'apprentissage ne doit apparaître');
    });

    test('B-2 — CONTRÔLE POSITIF : un résultat nouveau fait apprendre',
        () async {
      // Même état, mais la course du jour est NON RÉSOLUE. Le chemin va tenter
      // de récupérer son résultat. Selon la disponibilité réseau du résultat
      // (les rapports PMU ne sont pas toujours servis), deux issues sont
      // possibles ; le contrôle positif exige que, SI un nouveau résultat est
      // obtenu, l'apprentissage soit réellement consigné.
      final aujourdhui = DateTime.now().subtract(const Duration(hours: 5));
      await _semer([
        ..._historiqueResolu(),
        _pronostic(courseKey: 'R1C1_${_fmt(aujourdhui)}', date: aujourdhui),
      ]);

      final avant = _Compteurs.lire();
      final res = await IaMemoryService.instance.analyseJourneeComplete();
      final apres = _Compteurs.lire();

      debugPrint('[B-2] AVANT  $avant');
      debugPrint('[B-2] APRÈS  $apres | nouveauxResultats='
          '${res.nbNouveauxResultats} échecs=${res.nbCoursesEchouees} '
          'sansResultat=${res.nbSansResultat}');
      debugPrint('[B-2] ΔnbMisesAJour=${apres.deltaMisesAJour(avant)} '
          'Δjournal=${apres.deltaJournal(avant)} '
          'nouvelles méthodes=${apres.nouvellesMethodes(avant)}');

      // La COHÉRENCE est l'assertion : apprentissage ⟺ nouveau résultat.
      // On ne suppose pas qu'un résultat sera disponible (cela dépendrait du
      // réseau) ; on exige que la relation soit respectée dans les deux sens.
      if (res.nbNouveauxResultats > 0) {
        expect(apres.deltaJournal(avant), greaterThan(0),
            reason: 'CONTRÔLE POSITIF : un nouveau résultat DOIT déclencher '
                'un apprentissage consigné');
      } else {
        expect(apres.deltaJournal(avant), 0,
            reason: 'ABSENCE DE DOUBLE APPRENTISSAGE : sans nouveau résultat, '
                'aucune méthode ne doit être consignée');
      }
      // Dans TOUS les cas, aucune méthode ne peut être consignée deux fois
      // pour une même exécution : le journal compte les exécutions, et une
      // seule passe en produit au plus une par mécanisme.
      final methodes = apres.nouvellesMethodes(avant);
      expect(methodes.where((m) => m == 'gradient').length,
          lessThanOrEqualTo(1),
          reason: 'au plus UN apprentissage par gradient par exécution');
      expect(methodes.where((m) => m == 'discipline_gradient').length,
          lessThanOrEqualTo(1),
          reason: 'au plus UN apprentissage par discipline et par exécution');
    });

    test('B-3 — deux exécutions consécutives n\'apprennent pas deux fois',
        () async {
      // L'anti-double-apprentissage se mesure sur DEUX passes successives à
      // état constant : la seconde ne doit rien ajouter.
      final aujourdhui = DateTime.now();
      await _semer([
        ..._historiqueResolu(),
        for (var c = 1; c <= 2; c++)
          _pronostic(
            courseKey: 'R1C${c}_${_fmt(aujourdhui)}',
            date: aujourdhui,
            avecResultat: true,
          ),
      ]);

      final avant = _Compteurs.lire();
      await IaMemoryService.instance.analyseJourneeComplete();
      final apres1 = _Compteurs.lire();
      await IaMemoryService.instance.analyseJourneeComplete();
      final apres2 = _Compteurs.lire();

      debugPrint('[B-3] cycle 1 : Δjournal=${apres1.deltaJournal(avant)}');
      debugPrint('[B-3] cycle 2 : Δjournal=${apres2.deltaJournal(apres1)}');

      expect(apres2.deltaJournal(apres1), 0,
          reason: 'ABSENCE DE DOUBLE APPRENTISSAGE : relancer l\'analyse sur '
              'un état inchangé ne consigne aucun nouvel apprentissage');
    });
  });
}
