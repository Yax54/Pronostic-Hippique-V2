// ═══════════════════════════════════════════════════════════════════════════
//  ★ FINALISATION A6 — DÉCISION D'ARRIVÉE ISSUE DES RAPPORTS OFFICIELS PMU.
//
//  POURQUOI CE FICHIER EXISTE.
//
//  Les quatre parseurs P1 (`IaMemoryService.analyseJourneeComplete`), P2
//  (`IaMemoryService.fetchArriveeDirecte`), P4
//  (`DataRefreshService._fetchArriveeOfficielle`) et P5
//  (`AlertService._fetchResultatAuto`) lisaient le même flux
//  `/rapports-definitifs?specialisation=INTERNET` avec QUATRE copies
//  divergentes de la même logique. Trois défauts communs en résultaient :
//
//    1. L'ORDRE DES RAPPORTS `E_SIMPLE_PLACE` ÉTAIT PRIS POUR UN CLASSEMENT.
//       L'API PMU renvoie les placés dans un ordre qui n'est pas celui de
//       l'arrivée officielle. Empiler `E_SIMPLE_GAGNANT` puis les placés
//       produisait donc un ordre inventé pour les rangs 2 et 3.
//
//    2. UNE ARRIVÉE PARTIELLE OU INCOHÉRENTE ÉTAIT ACCEPTÉE. Un seul cheval
//       (Simple Gagnant seul) devenait une « arrivée », ce qui nourrissait
//       ensuite `rangFavoriIA`, `nbTop3` et `scorePerformance` avec une
//       vérité incomplète, puis déclenchait l'apprentissage.
//
//    3. LE PREMIER CHEVAL D'UNE ARRIVÉE POUVAIT DEVENIR « GAGNANT » PAR
//       DÉFAUT, ce qui fabriquait un gain à partir d'un rapport non gagnant.
//
//  LA RÈGLE POSÉE ICI, ET NULLE PART AILLEURS.
//
//  Une arrivée n'est retenue QUE si elle provient d'un rapport ORDONNÉ
//  (Tiercé / Quarté / Quinté **ORDRE**, en excluant explicitement DÉSORDRE et
//  4 sur 5), qu'elle contient au moins [kLongueurMinimaleArrivee] chevaux
//  distincts, et qu'elle est COHÉRENTE avec le Simple Gagnant lorsqu'il est
//  présent. Dans tous les autres cas la décision est un REFUS motivé : aucun
//  résultat n'est enregistré, la course reste non résolue, donc récupérable
//  plus tard — c'est exactement l'exigence « préserver les possibilités de
//  récupération ultérieure lorsque les résultats officiels sont absents ».
//
//  CE QUE CE FICHIER NE FAIT PAS, ET NE DOIT PAS FAIRE :
//    • aucun accès réseau, aucun accès disque, aucun état : fonction PURE ;
//    • aucune lecture de L0 (`ArriveeOfficielleService`) — la contrainte
//      structurelle L2-1.8b interdit le symbole `sourceL0` dans les sept
//      services protégés, et P3 est le seul parseur autorisé à lire L0 ;
//    • aucun calcul d'apprentissage : ce fichier rend des NOMBRES, il ne
//      touche ni aux poids, ni aux seuils, ni à la calibration, ni à l'ELO.
//
//  ⚠️ SUR LES EX ÆQUO — LIMITE ASSUMÉE ET DOCUMENTÉE.
//  Une combinaison PMU est une chaîne plate du type `7-4-2-9-1` : elle ne
//  PEUT PAS exprimer un groupe d'ex æquo. La sécurité ex æquo du mandat est
//  donc traitée là où l'information existe réellement — dans L0, dont
//  `EntreeArrivee.rangs` est un `List<List<int>>` — et c'est P3 qui la
//  traite (différer + signaler, cf. A6 n° 2-b-3). Ici, aucun aplatissement
//  silencieux n'est possible puisque la source est déjà plate et officielle.
//  Prétendre le contraire serait une affirmation non mesurable ; elle n'est
//  pas faite.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

/// Longueur minimale d'une arrivée jugée exploitable.
///
/// JUSTIFICATION MESURABLE, ET NON ARBITRAIRE : le plus court rapport ordonné
/// que l'API PMU publie est le Tiercé, soit trois chevaux. En dessous de trois
/// l'ordre n'est vérifiable par AUCUN autre rapport officiel, et les
/// indicateurs dérivés dégénèrent — `nbTop3DansArriveeReelle` compare un top 3
/// IA à un « top 3 » qui n'existe pas, et `nbPartants` est ensuite borné par
/// `clamp(4, 20)`, donc une longueur 1 ou 2 n'a aucun sens physique.
const int kLongueurMinimaleArrivee = 3;

/// Vrai si [typePari] désigne un rapport DONT LA COMBINAISON EST ORDONNÉE.
///
/// Les exclusions ne sont pas décoratives : un `DÉSORDRE` porte les cinq
/// mêmes chevaux dans un ordre QUELCONQUE, et un `4 sur 5` ne désigne pas une
/// place. Les inclure reviendrait à inventer un classement — exactement ce que
/// le mandat interdit. La même exclusion existe déjà à l'identique dans P1,
/// P2, P3, P4 et P5 ; elle est ici factorisée, pas réinventée.
bool estTypePariOrdonne(String typePari) {
  final estTierceQuarteQuinte = typePari.contains('TIERCE') ||
      typePari.contains('TIERCÉ') ||
      typePari.contains('QUARTE') ||
      typePari.contains('QUARTÉ') ||
      typePari.contains('QUINTE') ||
      typePari.contains('QUINTÉ');
  if (!estTierceQuarteQuinte) return false;
  if (typePari.contains('DESORDRE')) return false;
  if (typePari.contains('DÉSORDRE')) return false;
  if (typePari.contains('4SUR5')) return false;
  if (typePari.contains('4_SUR_5')) return false;
  if (typePari.contains('4/5')) return false;
  return true;
}

/// Analyse PURE des rapports PMU aboutissant à une décision d'arrivée.
///
/// Le champ [ordre] vaut `null` en cas de refus ; [motif] explique alors
/// pourquoi, en clair, pour que le refus soit diagnosticable et jamais
/// silencieux.
class DecisionArriveePmu {
  const DecisionArriveePmu._({
    required this.ordre,
    required this.motif,
    required this.gagnant,
    required this.places,
    required this.cotes,
    required this.typeRapportRetenu,
  });

  /// Arrivée officielle aplatie, ou `null` si elle est refusée.
  final List<int>? ordre;

  /// Motif lisible : « retenue depuis E_QUARTE_PLUS » ou la raison du refus.
  final String motif;

  /// Numéro du Simple Gagnant, `null` si le rapport est absent.
  final int? gagnant;

  /// Places officielles (`E_SIMPLE_PLACE`), dans l'ordre fourni par l'API.
  /// ⚠️ Ce n'est PAS un classement : ne jamais en faire une arrivée.
  final List<int> places;

  /// Cotes Simple Gagnant par numéro (dividende pour 1 € déjà divisé par 100).
  final Map<String, double> cotes;

  /// Type du rapport ordonné effectivement retenu (`''` si aucun).
  final String typeRapportRetenu;

  /// Vrai si une arrivée officielle exploitable a été produite.
  bool get retenue => ordre != null;

  @override
  String toString() =>
      'DecisionArriveePmu(ordre=$ordre, motif=$motif, gagnant=$gagnant, '
      'places=$places, type=$typeRapportRetenu)';
}

/// Décide de l'arrivée officielle à partir du corps JSON des rapports PMU.
///
/// Fonction PURE : aucun `await`, aucun effet de bord, aucune dépendance
/// d'état. Le corps peut être une liste déjà décodée, telle que rendue par
/// `jsonDecode`. Un corps qui n'est pas une liste produit un refus motivé,
/// jamais une exception : aucun parseur ne doit mourir sur un flux inattendu.
DecisionArriveePmu analyserRapportsPmu(List<dynamic> rapports) {
  int? gagnant;
  final List<int> places = <int>[];
  final Map<String, double> cotes = <String, double>{};
  List<int>? ordre;
  String typeRetenu = '';
  String motifRefus = 'aucun rapport ordonné (Tiercé / Quarté / Quinté ORDRE)';

  for (final r in rapports) {
    if (r is! Map) continue;
    final typePari = r['typePari']?.toString() ?? '';
    final rList = (r['rapports'] as List<dynamic>?) ?? const <dynamic>[];
    if (rList.isEmpty) continue;

    // ── Simple Gagnant : gagnant officiel + cotes de tous les partants ────
    if (typePari == 'E_SIMPLE_GAGNANT') {
      for (final rap in rList) {
        if (rap is! Map) continue;
        final n = int.tryParse(rap['combinaison']?.toString().trim() ?? '');
        if (n == null) continue;
        // Le PREMIER rapport E_SIMPLE_GAGNANT est le cheval gagnant ; les
        // suivants ne servent qu'à porter les cotes.
        gagnant ??= n;
        final rawDiv = rap['dividendePourUnEuro'] ?? rap['dividende'];
        if (rawDiv is num) {
          final cote = rawDiv.toDouble() / 100.0;
          if (cote > 1.0) cotes[n.toString()] = cote;
        }
      }
      continue;
    }

    // ── Simple Placé : places officielles, JAMAIS un classement ──────────
    if (typePari == 'E_SIMPLE_PLACE') {
      for (final rap in rList) {
        if (rap is! Map) continue;
        final n = int.tryParse(rap['combinaison']?.toString().trim() ?? '');
        if (n != null && !places.contains(n)) places.add(n);
      }
      continue;
    }

    // ── Rapport ORDONNÉ : la SEULE source d'arrivée autorisée ────────────
    if (estTypePariOrdonne(typePari)) {
      if (ordre != null) continue; // le premier rapport ordonné fait foi
      final rap = rList.first;
      if (rap is! Map) {
        motifRefus = 'combinaison ordonnée illisible (rapport non-objet)';
        continue;
      }
      final combo = rap['combinaison']?.toString() ?? '';
      final lus = <int>[];
      for (final part in combo.split('-')) {
        final n = int.tryParse(part.trim());
        if (n != null && !lus.contains(n)) lus.add(n);
      }
      if (lus.isEmpty) {
        motifRefus = 'combinaison ordonnée illisible (« $combo »)';
        continue;
      }
      ordre = lus;
      typeRetenu = typePari;
    }
  }

  // ── Contrôles de validité. Chaque refus est MOTIVÉ. ────────────────────
  if (ordre == null) {
    return DecisionArriveePmu._(
      ordre: null,
      motif: 'refusée — $motifRefus',
      gagnant: gagnant,
      places: places,
      cotes: cotes,
      typeRapportRetenu: '',
    );
  }

  if (ordre.length < kLongueurMinimaleArrivee) {
    return DecisionArriveePmu._(
      ordre: null,
      motif: 'refusée — arrivée partielle : ${ordre.length} cheval(aux) '
          'distinct(s) < $kLongueurMinimaleArrivee ($typeRetenu)',
      gagnant: gagnant,
      places: places,
      cotes: cotes,
      typeRapportRetenu: typeRetenu,
    );
  }

  if (gagnant != null && !ordre.contains(gagnant)) {
    return DecisionArriveePmu._(
      ordre: null,
      motif: 'refusée — incohérente : gagnant N°$gagnant absent du rapport '
          'ordonné $typeRetenu (${ordre.join("-")})',
      gagnant: gagnant,
      places: places,
      cotes: cotes,
      typeRapportRetenu: typeRetenu,
    );
  }

  if (gagnant != null && gagnant != ordre.first) {
    return DecisionArriveePmu._(
      ordre: null,
      motif: 'refusée — incohérente : gagnant N°$gagnant ≠ 1er du rapport '
          'ordonné (N°${ordre.first}, $typeRetenu ${ordre.join("-")})',
      gagnant: gagnant,
      places: places,
      cotes: cotes,
      typeRapportRetenu: typeRetenu,
    );
  }

  return DecisionArriveePmu._(
    ordre: ordre,
    motif: 'retenue depuis $typeRetenu (${ordre.length} chevaux)',
    gagnant: gagnant,
    places: places,
    cotes: cotes,
    typeRapportRetenu: typeRetenu,
  );
}

/// Variante tolérante au corps brut : décode puis délègue.
///
/// Un corps vide, non-JSON ou non-liste produit un refus motivé — jamais une
/// exception — afin qu'un flux PMU inattendu ne fasse pas échouer un cycle de
/// récupération entier.
DecisionArriveePmu analyserCorpsRapportsPmu(String corps) {
  List<dynamic> rapports;
  try {
    final decode = jsonDecode(corps);
    if (decode is! List) {
      return const DecisionArriveePmu._(
        ordre: null,
        motif: 'refusée — corps PMU non tabulaire',
        gagnant: null,
        places: <int>[],
        cotes: <String, double>{},
        typeRapportRetenu: '',
      );
    }
    rapports = decode;
  } catch (_) {
    return const DecisionArriveePmu._(
      ordre: null,
      motif: 'refusée — corps PMU illisible',
      gagnant: null,
      places: <int>[],
      cotes: <String, double>{},
      typeRapportRetenu: '',
    );
  }
  return analyserRapportsPmu(rapports);
}
