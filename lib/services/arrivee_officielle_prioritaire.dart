// ═══════════════════════════════════════════════════════════════════════════
//  ★ A6 — DÉCISION D'ARRIVÉE PARTAGÉE (P1, P2, P4, P5)
//
//  Objet : une seule fonction décide, POUR LES QUATRE CHEMINS, ce qui peut
//  être enregistré comme arrivée officielle. Elle rend toujours des GROUPES :
//  les ex æquo ne sont jamais transformés en classement plat.
//
//  ── Pourquoi un rendu de groupes et pas une liste plate ──────────────────
//  `[[7,12],[8]]` n'est pas `[7,12,8]`. Le premier signifie « 7 et 12
//  arrivent ensemble, 8 est troisième ». Le second invente un ordre entre 7
//  et 12. Aucune fonction d'apprentissage ne doit recevoir le second.
//
//  ── Trois issues, et trois seulement ─────────────────────────────────────
//  (1) L0 ABSENT        → repli sur le PMU ordonné (`analyserRapportsPmu`,
//      qui refuse déjà tout rapport non ordonné et toute arrivée de moins de
//      `kLongueurMinimaleArrivee` chevaux). Le repli ne prétend jamais
//      détecter une égalité inconnue : il ne peut pas produire de groupes.
//  (2) L0 AVEC EX ÆQUO  → les groupes sont RENDUS (affichage possible) mais
//      `peutEnregistrer` est FAUX : aucun apprentissage, aucun ELO.
//  (3) L0 PLAT          → groupes d'un cheval chacun ; enregistrable.
//
//  ── Contrôle d'appartenance ──────────────────────────────────────────────
//  Si une liste FIABLE de partants est fournie et non vide, tout numéro de
//  l'arrivée qui n'y figure pas fait REFUSER la décision. Une liste absente
//  ou vide n'est JAMAIS assimilée à une incohérence : c'est l'exigence
//  explicite du mandat (« ne pas assimiler l'absence de liste fiable à une
//  preuve d'incohérence »). Aucune liste n'est inventée à partir de la
//  longueur de l'arrivée.
//
//  ── Périmètre ────────────────────────────────────────────────────────────
//  Ce fichier est PUR : aucun réseau, aucun disque, aucun état, aucune
//  lecture L0 (elle est injectée par l'appelant), aucune écriture.
//  Il n'est importé par AUCUN rendu.
// ═══════════════════════════════════════════════════════════════════════════

import 'arrivee_pmu_ordonnee.dart';

/// D'où provient l'arrivée retenue.
enum SourceArriveeOfficielle {
  /// Groupes officiels lus dans L0 (`ArriveeOfficielleService`).
  l0,

  /// Repli : rapport PMU ORDONNÉ, aplati par construction (aucun ex æquo
  /// représentable). Ne permet pas de détecter une égalité inconnue.
  pmuOrdonne,

  /// Aucune arrivée exploitable pour l'instant.
  aucune,
}

/// Résultat PUR de la décision.
///
/// [groupes] n'est jamais `null` lorsque [source] != [aucune]. Il n'est
/// jamais aplati et jamais réordonné.
class DecisionArriveeOfficielle {
  final SourceArriveeOfficielle source;

  /// Groupes officiels, ex æquo préservés. Vide si [source] == aucune.
  final List<List<int>> groupes;

  /// `true` si et seulement si l'arrivée peut être transmise à
  /// l'apprentissage et à l'ELO, c'est-à-dire si elle ne contient AUCUN ex
  /// æquo. Un groupe de 2 chevaux ou plus interdit l'enregistrement :
  /// `IaPronostic.arriveeReelle` est `List<int>?` (ia_memory_models.dart:285)
  /// et un groupe y serait aplati, donc le rang du second cheval serait
  /// inventé, et `rangFavoriIaDansArrivee`, `nbTop3`, `nbTop5` puis
  /// `scorePerformance` seraient faux.
  final bool peutEnregistrer;

  /// Motif lisible : pourquoi l'arrivée est retenue, refusée, ou différée.
  final String motif;

  const DecisionArriveeOfficielle._({
    required this.source,
    required this.groupes,
    required this.peutEnregistrer,
    required this.motif,
  });

  /// `true` si une arrivée est disponible pour l'AFFICHAGE.
  bool get disponible => source != SourceArriveeOfficielle.aucune;

  /// `true` si l'arrivée contient au moins un ex æquo.
  bool get aDesExAequo => groupes.any((g) => g.length > 1);

  /// Aplatissement SANS PERTE, autorisé uniquement si `peutEnregistrer`.
  /// Rend la liste vide sinon : un appelant ne peut pas aplatir par erreur.
  List<int> get arriveePlate =>
      peutEnregistrer ? <int>[for (final g in groupes) ...g] : const <int>[];
}

/// Construit une décision « aucune arrivée ».
DecisionArriveeOfficielle _aucune(String motif) =>
    DecisionArriveeOfficielle._(
      source: SourceArriveeOfficielle.aucune,
      groupes: const <List<int>>[],
      peutEnregistrer: false,
      motif: motif,
    );

/// Vérifie que tous les numéros appartiennent à [partants].
///
/// PURE. Rend `null` si le contrôle est IMPOSSIBLE (liste absente ou vide) :
/// l'absence de liste fiable n'est jamais une preuve d'incohérence.
/// Rend la liste des numéros ÉTRANGERS sinon (vide = tout est conforme).
List<int>? numerosEtrangers(
  List<List<int>> groupes,
  Set<int>? partants,
) {
  if (partants == null || partants.isEmpty) return null;
  final etrangers = <int>[];
  for (final g in groupes) {
    for (final n in g) {
      if (!partants.contains(n) && !etrangers.contains(n)) {
        etrangers.add(n);
      }
    }
  }
  return etrangers;
}

/// Décide de l'arrivée officielle d'une course.
///
/// [groupesL0] : groupes lus par l'appelant dans L0 (`null` si absent).
/// [rapportsPmu] : corps déjà décodé de `/rapports-definitifs`, ou `null`.
/// [partants] : ensemble FIABLE des numéros partants, ou `null`.
///
/// L0 est PRIORITAIRE. Le repli PMU n'est consulté que si L0 est absent.
DecisionArriveeOfficielle deciderArriveeOfficielle({
  List<List<int>>? groupesL0,
  List<dynamic>? rapportsPmu,
  Set<int>? partants,
}) {
  // ── 1. L0 prioritaire ────────────────────────────────────────────────────
  if (groupesL0 != null && groupesL0.isNotEmpty) {
    // Aucun groupe vide : on ne fabrique aucun trou.
    if (groupesL0.any((g) => g.isEmpty)) {
      return _aucune('L0 contient un rang vide — arrivée non exploitable');
    }

    final etrangers = numerosEtrangers(groupesL0, partants);
    if (etrangers != null && etrangers.isNotEmpty) {
      return _aucune('L0 contient des numéros absents des partants '
          '(${etrangers.join(', ')}) — arrivée refusée');
    }

    final exAequo = groupesL0.any((g) => g.length > 1);
    if (exAequo) {
      // RENDUS pour l'affichage, JAMAIS enregistrables : aplatir inventerait
      // un classement entre chevaux arrivés simultanément.
      return DecisionArriveeOfficielle._(
        source: SourceArriveeOfficielle.l0,
        groupes: List<List<int>>.unmodifiable(
            groupesL0.map((g) => List<int>.unmodifiable(g))),
        peutEnregistrer: false,
        motif: 'L0 avec ex æquo — affichage autorisé, enregistrement différé '
            'pour ne pas inventer un ordre entre chevaux ex æquo',
      );
    }

    return DecisionArriveeOfficielle._(
      source: SourceArriveeOfficielle.l0,
      groupes: List<List<int>>.unmodifiable(
          groupesL0.map((g) => List<int>.unmodifiable(g))),
      peutEnregistrer: true,
      motif: 'L0 complète sans ex æquo',
    );
  }

  // ── 2. Repli PMU ordonné ────────────────────────────────────────────────
  if (rapportsPmu == null) {
    return _aucune('L0 absent et aucun rapport PMU fourni');
  }

  final DecisionArriveePmu pmu;
  try {
    pmu = analyserRapportsPmu(rapportsPmu);
  } catch (e) {
    return _aucune('rapports PMU illisibles ($e)');
  }

  if (!pmu.retenue) {
    return _aucune('repli PMU refusé : ${pmu.motif}');
  }

  // Le repli est PLAT par construction : une combinaison PMU est une chaîne
  // « 7-4-2-9-1 », qui ne peut pas exprimer un groupe d'ex æquo.
  final groupes = <List<int>>[
    for (final n in pmu.ordre!) <int>[n],
  ];

  final etrangers = numerosEtrangers(groupes, partants);
  if (etrangers != null && etrangers.isNotEmpty) {
    return _aucune('repli PMU contient des numéros absents des partants '
        '(${etrangers.join(', ')}) — arrivée refusée');
  }

  return DecisionArriveeOfficielle._(
    source: SourceArriveeOfficielle.pmuOrdonne,
    groupes: List<List<int>>.unmodifiable(
        groupes.map((g) => List<int>.unmodifiable(g))),
    peutEnregistrer: true,
    motif: 'repli PMU ordonné (${pmu.motif}) — aucune égalité détectable '
        'dans une combinaison plate',
  );
}
