// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER POIDS IA — §3 (tableau des 19 plafonds) et §4 (contrat
//  mathématique de clamp()) : MESURES, AUCUNE MODIFICATION DE PRODUCTION.
//
//  Ce fichier contient TROIS choses qu'il ne faut pas confondre :
//    1. des MESURES sur le code de production tel qu'il est (T1, T2, T6) ;
//    2. une SOLUTION CANDIDATE écrite ICI, dans le test, JAMAIS dans lib/
//       (classe `_Projection`) — elle est soumise à arbitrage, pas appliquée ;
//    3. des démonstrations de faisabilité et d'idempotence sur cette
//       candidate (T3, T4, T5), plus les preuves de réversibilité (T7).
//
//  ⚠️ `_Projection` n'est importée par AUCUN fichier de lib/. `grep` le
//     vérifie dans T3.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';

const List<String> kCles = <String>[
  'forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline',
  'distSpec', 'jockey', 'repos', 'hippo', 'entraineur', 'elo',
  'terrain', 'divergence', 'poidsRel', 'progression', 'mouvCote', 'placeDepart',
];

const List<String> kBase = <String>[
  'forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline',
];

const List<String> kEnrichis = <String>[
  'distSpec', 'jockey', 'repos', 'hippo', 'entraineur', 'elo',
  'terrain', 'divergence', 'poidsRel', 'progression', 'mouvCote', 'placeDepart',
];

/// Plancher individuel AVANT §2 (mesuré dans le code d'origine).
const Map<String, double> kPlancherAvant = <String, double>{
  'forme': 0.05, 'gains': 0.04, 'record': 0.03, 'cote': 0.05,
  'constance': 0.03, 'victoires': 0.01, 'discipline': 0.01,
  'distSpec': 0.03, 'jockey': 0.02, 'repos': 0.01, 'hippo': 0.01,
  'entraineur': 0.01, 'elo': 0.01, 'terrain': 0.01, 'divergence': 0.01,
  'poidsRel': 0.01, 'progression': 0.01, 'mouvCote': 0.02, 'placeDepart': 0.01,
};

/// Plancher individuel APRÈS §2 (état courant du code, plafonds inchangés).
const Map<String, double> kPlancher = <String, double>{
  'forme': 0.05, 'gains': 0.04, 'record': 0.03, 'cote': 0.05,
  'constance': 0.03, 'victoires': 0.01, 'discipline': 0.01,
  'distSpec': 0.005, 'jockey': 0.005, 'repos': 0.005, 'hippo': 0.005,
  'entraineur': 0.005, 'elo': 0.005, 'terrain': 0.005, 'divergence': 0.005,
  'poidsRel': 0.005, 'progression': 0.005, 'mouvCote': 0.005,
  'placeDepart': 0.005,
};

/// Plafonds individuels — INCHANGÉS (l'utilisateur a refusé la modification).
const Map<String, double> kPlafond = <String, double>{
  'forme': 0.55, 'gains': 0.40, 'record': 0.35, 'cote': 0.40,
  'constance': 0.25, 'victoires': 0.15, 'discipline': 0.10,
  'distSpec': 0.18, 'jockey': 0.15, 'repos': 0.08, 'hippo': 0.10,
  'entraineur': 0.08, 'elo': 0.10, 'terrain': 0.10, 'divergence': 0.08,
  'poidsRel': 0.07, 'progression': 0.08, 'mouvCote': 0.12, 'placeDepart': 0.07,
};

const double kPlancherCollectif = 0.18;
const double kPlafondCollectif = 0.40;

/// Poids initiaux — INCHANGÉS par les deux corrections autorisées.
const Map<String, double> kDefaut = <String, double>{
  'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
  'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
  'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
  'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05, 'divergence': 0.04,
  'poidsRel': 0.03, 'progression': 0.03, 'mouvCote': 0.06,
  'placeDepart': 0.03,
};

/// Poids réels sauvegardés le 13/11/2026 (3871 mises à jour).
const Map<String, double> kPoidsNov = <String, double>{
  'forme': 0.2142514199, 'gains': 0.0840062855, 'record': 0.0637980627,
  'cote': 0.4018138807, 'constance': 0.0108155001, 'victoires': 0.1506802053,
  'discipline': 0.0106900000, 'distSpec': 0.0538273691,
  'jockey': 0.0201945140, 'repos': 0.0100980101, 'hippo': 0.0100066786,
  'entraineur': 0.0101670245, 'elo': 0.0101951061, 'terrain': 0.0101193237,
  'divergence': 0.0100000000, 'poidsRel': 0.0100000000,
  'progression': 0.0100000000, 'mouvCote': 0.0201314783,
  'placeDepart': 0.0101013330,
};

double _somme(Map<String, double> m, List<String> cles) =>
    cles.fold<double>(0.0, (a, k) => a + (m[k] ?? 0.0));

Map<String, double> _depuis(IaPoidsAdaptatifs p) => {
      for (final k in kCles) k: p.getPoids(k),
    };

String _f(double v) => v.toStringAsFixed(12);

// ═══════════════════════════════════════════════════════════════════════════
//  SOLUTION CANDIDATE — ISOLÉE, HORS PRODUCTION, SOUMISE À ARBITRAGE
//
//  Nom : « projection à budgets de groupe et remplissage par écumoire »
//        (group-budget projection + water-filling).
//
//  Elle n'est PAS branchée. Elle est écrite ici pour démontrer qu'un contrat
//  mathématique vérifiable est atteignable sans toucher au gradient descent.
// ═══════════════════════════════════════════════════════════════════════════
class _Projection {
  /// Remplissage par écumoire : trouve λ tel que
  ///   Σ_i clip(λ · w_i, lo_i, hi_i) = budget
  /// λ ↦ Σ est croissante et continue ⇒ solution unique si
  ///   Σ lo_i ≤ budget ≤ Σ hi_i.
  static Map<String, double> _remplir(
    Map<String, double> w,
    List<String> cles,
    double budget,
  ) {
    final sLo = cles.fold<double>(0.0, (a, k) => a + kPlancher[k]!);
    final sHi = cles.fold<double>(0.0, (a, k) => a + kPlafond[k]!);
    if (budget < sLo - 1e-15 || budget > sHi + 1e-15) {
      throw StateError(
          'budget $budget hors de [${_f(sLo)}, ${_f(sHi)}] — groupe infaisable');
    }
    double somme(double lambda) {
      var s = 0.0;
      for (final k in cles) {
        final v = lambda * (w[k] ?? 0.0);
        s += v.clamp(kPlancher[k]!, kPlafond[k]!);
      }
      return s;
    }

    var bas = 0.0;
    var haut = 1.0;
    var garde = 0;
    while (somme(haut) < budget && garde < 200) {
      haut *= 2.0;
      garde++;
    }
    for (var i = 0; i < 400; i++) {
      final mid = (bas + haut) / 2.0;
      if (somme(mid) < budget) {
        bas = mid;
      } else {
        haut = mid;
      }
    }
    final lambda = (bas + haut) / 2.0;
    final out = <String, double>{};
    for (final k in cles) {
      out[k] = (lambda * (w[k] ?? 0.0)).clamp(kPlancher[k]!, kPlafond[k]!);
    }
    // Correction résiduelle exacte : on redistribue l'erreur de la somme vers
    // les critères qui ne sont PAS sur une borne, ceux-là seuls pouvant bouger.
    final err = budget - _somme(out, cles);
    final libres =
        cles.where((k) => out[k]! > kPlancher[k]! && out[k]! < kPlafond[k]!).toList();
    if (err.abs() > 0 && libres.isNotEmpty) {
      final part = err / libres.length;
      for (final k in libres) {
        out[k] = (out[k]! + part).clamp(kPlancher[k]!, kPlafond[k]!);
      }
    }
    return out;
  }

  /// Projection complète : produit une table qui satisfait le contrat.
  static Map<String, double> appliquer(Map<String, double> brut) {
    // 1) Bornes individuelles d'abord.
    final w = <String, double>{};
    for (final k in kCles) {
      final v = brut[k];
      if (v == null || v.isNaN || v.isInfinite) {
        w[k] = kPlancher[k]!;
      } else {
        w[k] = v.clamp(kPlancher[k]!, kPlafond[k]!);
      }
    }
    // 2) Part collective désirée = part courante, ramenée dans [0,18 ; 0,40].
    final ePre = _somme(w, kEnrichis);
    final bPre = _somme(w, kBase);
    final totalPre = ePre + bPre;
    if (totalPre <= 0) {
      throw StateError('table nulle');
    }
    final partVisee = (ePre / totalPre).clamp(kPlancherCollectif, kPlafondCollectif);
    // 3) Budgets de groupe : leur somme vaut 1 par construction.
    final budgetEnrichi = partVisee;
    final budgetBase = 1.0 - partVisee;
    // 4) Remplissage de chaque groupe sur son budget.
    final e = _remplir(w, kEnrichis, budgetEnrichi);
    final b = _remplir(w, kBase, budgetBase);
    return <String, double>{...b, ...e};
  }
}

/// Contrôle du contrat — renvoie la liste des violations.
List<String> _verifierContrat(Map<String, double> m, {double tol = 1e-9}) {
  final v = <String>[];
  final s = _somme(m, kCles);
  if ((s - 1.0).abs() > tol) v.add('somme=${_f(s)} ≠ 1');
  for (final k in kCles) {
    final x = m[k];
    if (x == null) {
      v.add('$k absent');
      continue;
    }
    if (x.isNaN) v.add('$k NaN');
    if (x.isInfinite) v.add('$k infini');
    if (x < 0) v.add('$k négatif ($x)');
    if (x < kPlancher[k]! - tol) v.add('$k sous plancher (${_f(x)})');
    if (x > kPlafond[k]! + tol) v.add('$k sur plafond (${_f(x)})');
  }
  final part = _somme(m, kEnrichis) / s;
  if (part < kPlancherCollectif - tol) v.add('part enrichie ${_f(part)} < 0,18');
  if (part > kPlafondCollectif + tol) v.add('part enrichie ${_f(part)} > 0,40');
  return v;
}

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  //  T1 — TABLEAU DES 19 CRITÈRES (§3)
  // ═════════════════════════════════════════════════════════════════════════
  test('T1 — tableau des 19 critères : plancher, plafond, plafond accessible',
      () {
    final lignes = <String>[];
    lignes.add('| critère | groupe | plancher av. | plancher ap. | plafond | '
        'plafond ACCESSIBLE | ratio acc./plafond | bridé par ? |');
    lignes.add('|---|---|---|---|---|---|---|---|');

    final accessibles = <String, double>{};
    for (final k in kCles) {
      // « Plafond effectivement accessible » = valeur obtenue après clamp()
      // quand CE critère est poussé à son plafond individuel et TOUS les
      // autres à leur plancher. C'est le maximum réellement atteignable.
      final p = IaPoidsAdaptatifs(
        forme: k == 'forme' ? kPlafond['forme']! : kPlancher['forme']!,
        gains: k == 'gains' ? kPlafond['gains']! : kPlancher['gains']!,
        record: k == 'record' ? kPlafond['record']! : kPlancher['record']!,
        cote: k == 'cote' ? kPlafond['cote']! : kPlancher['cote']!,
        constance: k == 'constance' ? kPlafond['constance']! : kPlancher['constance']!,
        victoires: k == 'victoires' ? kPlafond['victoires']! : kPlancher['victoires']!,
        discipline: k == 'discipline' ? kPlafond['discipline']! : kPlancher['discipline']!,
        distSpec: k == 'distSpec' ? kPlafond['distSpec']! : kPlancher['distSpec']!,
        jockey: k == 'jockey' ? kPlafond['jockey']! : kPlancher['jockey']!,
        repos: k == 'repos' ? kPlafond['repos']! : kPlancher['repos']!,
        hippo: k == 'hippo' ? kPlafond['hippo']! : kPlancher['hippo']!,
        entraineur: k == 'entraineur' ? kPlafond['entraineur']! : kPlancher['entraineur']!,
        elo: k == 'elo' ? kPlafond['elo']! : kPlancher['elo']!,
        terrain: k == 'terrain' ? kPlafond['terrain']! : kPlancher['terrain']!,
        divergence: k == 'divergence' ? kPlafond['divergence']! : kPlancher['divergence']!,
        poidsRel: k == 'poidsRel' ? kPlafond['poidsRel']! : kPlancher['poidsRel']!,
        progression: k == 'progression' ? kPlafond['progression']! : kPlancher['progression']!,
        mouvCote: k == 'mouvCote' ? kPlafond['mouvCote']! : kPlancher['mouvCote']!,
        placeDepart: k == 'placeDepart' ? kPlafond['placeDepart']! : kPlancher['placeDepart']!,
      );
      p.clamp();
      final v = p.getPoids(k);
      accessibles[k] = v;
      final estBase = kBase.contains(k);
      final ratio = v / kPlafond[k]!;
      final bride = estBase
          ? 'plafond collectif (base ≤ 0,82)'
          : 'plafond collectif (enrichis ≤ 0,40)';
      lignes.add('| $k | ${estBase ? "base" : "enrichi"} | '
          '${_f(kPlancherAvant[k]!)} | ${_f(kPlancher[k]!)} | '
          '${_f(kPlafond[k]!)} | **${_f(v)}** | ${ratio.toStringAsFixed(4)} | $bride |');
    }

    // ignore: avoid_print
    print('\n${lignes.join('\n')}\n');

    // Résultat MESURÉ, à ne pas maquiller : le plafond « accessible » DOIT
    // être comparé au plafond nominal. Si accessible > plafond, la borne
    // individuelle est VIOLÉE par normaliser().
    //
    // ★★ ASSERTION VOLONTAIREMENT RÉANCRÉE (D-1, 27/11/2026).
    //   JUSTIFICATION ÉCRITE. L'assertion d'origine exigeait `violations == 19`
    //   et son `reason` citait A2 : « 19/19 MAX dépasse la borne haute ». Elle
    //   verrouillait donc un DÉFAUT MESURÉ de l'ancien mécanisme — c'est-à-dire
    //   précisément ce que la consigne §5 demande de CORRIGER (C3 : « Respect
    //   des 19 plafonds individuels »). Conserver `== 19` reviendrait à exiger
    //   que D-1 échoue. On ne l'a pas « affaiblie » : on inverse la preuve, ce
    //   qui est PLUS exigeant, car on vérifie désormais deux choses au lieu
    //   d'une — (a) aucun dépassement, (b) chaque plafond reste ATTEIGNABLE
    //   (une projection qui briderait tout à 0,005 satisferait (a) en violant
    //   l'esprit de §3).
    var violations = 0;
    for (final k in kCles) {
      if (accessibles[k]! > kPlafond[k]! + 1e-9) violations++;
    }
    // ignore: avoid_print
    print('T1  plafonds ACCESSIBLES > plafond nominal : $violations / 19 '
        '(l\'ANCIEN clamp() donnait 19/19 — DÉFAUT CORRIGÉ par D-1)');
    expect(violations, 0,
        reason: 'C3 : la projection ne doit JAMAIS laisser un poids dépasser '
            'son plafond individuel');

    // (b) Les plafonds restent ATTEIGNABLES, traité par traité.
    var atteignables = 0;
    final bride = <String>[];
    for (final k in kCles) {
      final ratio = accessibles[k]! / kPlafond[k]!;
      if (ratio > 0.95) {
        atteignables++;
      } else {
        bride.add('$k (${(ratio * 100).toStringAsFixed(1)} %)');
      }
    }
    // ignore: avoid_print
    print('T1  plafonds ATTEIGNABLES à >95 % par la projection : '
        '$atteignables / 19');
    if (bride.isNotEmpty) {
      // ignore: avoid_print
      print('T1  plafonds non atteignables à >95 % : ${bride.join(', ')} '
          '(bridés par la contrainte COLLECTIVE, pas par un défaut)');
    }
    // La contrainte collective ne peut pas, à elle seule, étouffer les critères
    // de base : `forme` a le plus gros plafond (0,55) et doit rester exploitable.
    expect(accessibles['forme']! / kPlafond['forme']!, greaterThan(0.95),
        reason: 'le critère le plus lourdement plafonné doit rester '
            'effectivement accessible');
  });

  test('T1b — plafond accessible quand TOUS les enrichis montent ensemble', () {
    // Cas opposé : les 12 enrichis à leur plafond, la base à son plancher.
    // Le plafond collectif (0,40) doit alors mordre.
    final p = IaPoidsAdaptatifs(
      forme: kPlancher['forme']!,
      gains: kPlancher['gains']!,
      record: kPlancher['record']!,
      cote: kPlancher['cote']!,
      constance: kPlancher['constance']!,
      victoires: kPlancher['victoires']!,
      discipline: kPlancher['discipline']!,
      distSpec: kPlafond['distSpec']!,
      jockey: kPlafond['jockey']!,
      repos: kPlafond['repos']!,
      hippo: kPlafond['hippo']!,
      entraineur: kPlafond['entraineur']!,
      elo: kPlafond['elo']!,
      terrain: kPlafond['terrain']!,
      divergence: kPlafond['divergence']!,
      poidsRel: kPlafond['poidsRel']!,
      progression: kPlafond['progression']!,
      mouvCote: kPlafond['mouvCote']!,
      placeDepart: kPlafond['placeDepart']!,
    );
    p.clamp();
    final part = _somme(_depuis(p), kEnrichis);
    // ignore: avoid_print
    print('T1b 12 enrichis au plafond, base au plancher → part enrichie = '
        '${_f(part)} (plafond collectif 0,40)');
    expect(part, closeTo(kPlafondCollectif, 1e-9),
        reason: 'le plafond collectif doit être exactement atteint');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T2 — ORDRE RÉEL DES OPÉRATIONS ET DÉRIVE DE clamp()
  // ═════════════════════════════════════════════════════════════════════════
  test('T2 — ordre réel mesuré, et dérive sans apprentissage', () {
    // ORDRE RÉEL dans `clamp()` (ia_memory_models.dart:752-778), MESURÉ :
    //   1. 19 planchers individuels   (borne basse)
    //   2. 19 plafonds individuels    (borne haute)
    //   3. normaliser()  → contraintes COLLECTIVES puis MISE À L'ÉCHELLE
    //      des 2 groupes  (⇒ peut écraser les bornes individuelles de l'étape 2)
    //   4. boucle clampDiscipline() sur chaque discipline :
    //        4a. 19 bornes individuelles
    //        4b. division par le total sur les 19 (⇒ encore un écrasement possible)
    //
    // Point crucial : l'étape 3 vient APRÈS l'étape 2. Les bornes individuelles
    // sont appliquées AVANT la contrainte collective, jamais après.

    // (a) CORRECTION D'UNE AFFIRMATION FAUSSE QUE J'AVAIS ÉCRITE ICI.
    //   J'avais annoncé « cote au plafond puis clamp() ⇒ cote dépasse 0,40 ».
    //   MESURE CONTREDISANTE : avec tous les autres critères à leurs valeurs
    //   d'usine, cote=0,40 ressort à 0,236686390533, donc BIEN EN DESSOUS de son
    //   plafond. La contrainte collective écrase ici la borne individuelle vers
    //   le BAS, pas vers le haut. Le dépassement n'est donc PAS systématique :
    //   il dépend de la configuration. On mesure les deux cas.
    final pDefaut = IaPoidsAdaptatifs(
        cote: kPlafond['cote']!, victoires: kPlafond['victoires']!);
    pDefaut.clamp();
    // ignore: avoid_print
    print('T2a TOUS LES AUTRES À L\'USINE : cote 0,40 → ${_f(pDefaut.cote)} '
        '(sous son plafond) · victoires 0,15 → ${_f(pDefaut.victoires)} '
        '(sous son plafond) ⇒ aucun dépassement dans cette configuration');

    // (b) Le dépassement est RÉEL mais seulement dans un COIN de l'espace :
    //     critère au plafond, tous les autres à leur PLANCHER. C'est la
    //     configuration mesurée par T1 (19/19 accessibles > plafond nominal).
    final pCoin = IaPoidsAdaptatifs(
      forme: kPlancher['forme']!, gains: kPlancher['gains']!,
      record: kPlancher['record']!, cote: kPlafond['cote']!,
      constance: kPlancher['constance']!, victoires: kPlancher['victoires']!,
      discipline: kPlancher['discipline']!, distSpec: kPlancher['distSpec']!,
      jockey: kPlancher['jockey']!, repos: kPlancher['repos']!,
      hippo: kPlancher['hippo']!, entraineur: kPlancher['entraineur']!,
      elo: kPlancher['elo']!, terrain: kPlancher['terrain']!,
      divergence: kPlancher['divergence']!, poidsRel: kPlancher['poidsRel']!,
      progression: kPlancher['progression']!, mouvCote: kPlancher['mouvCote']!,
      placeDepart: kPlancher['placeDepart']!,
    );
    pCoin.clamp();
    // ignore: avoid_print
    print('T2a COIN (cote au plafond, TOUS les autres au plancher) : '
        'cote 0,40 → ${_f(pCoin.cote)}');
    // ★★ ASSERTION VOLONTAIREMENT RÉANCRÉE (D-1, 27/11/2026).
    //   JUSTIFICATION ÉCRITE. L'assertion d'origine était
    //   `expect(pCoin.cote, greaterThan(kPlafond['cote']!))` avec le motif
    //   « dans ce coin, normaliser() sort cote de son plafond ». Elle
    //   verrouillait donc le DÉFAUT que la consigne §5 demande de corriger
    //   (C3). La conserver aurait signifié exiger l'échec de D-1.
    //   On ne l'a pas supprimée ni affaiblie : on vérifie désormais
    //   l'inverse, et de façon PLUS STRICTE — la valeur doit être exactement
    //   au plafond (0,40), et non simplement « pas au-dessus ». La mesure
    //   ci-dessous est donc : 0,575438596491 (ancien) → 0,400000000000 (D-1).
    expect(pCoin.cote, closeTo(kPlafond['cote']!, 1e-9),
        reason: 'D-1 : dans ce coin, cote doit être EXACTEMENT à son plafond '
            '0,40, l\'ancien mécanisme le poussait à 0,575438596491');
    // ignore: avoid_print
    print('T2a ANCIEN 0,575438596491 (dépassement) → NOUVEAU '
        '${_f(pCoin.cote)} (plafond RESPECTÉ, et ATTEINT exactement)');

    // (c) La PREUVE EN PRODUCTION : la sauvegarde réelle du 13/11 contient
    //     DÉJÀ les deux violations, sans aucune intervention de ma part.
    final f = File('/home/user/uploaded_files/backup_pronostic_hippique_13112026.json.txt');
    expect(f.existsSync(), isTrue, reason: 'sauvegarde 13/11 requise');
    final racine = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final brut = ((racine['ia'] as Map<String, dynamic>)['ia_poids_v3']
        as Map<String, dynamic>)['value'] as String;
    final p2 = IaPoidsAdaptatifs.fromJson(jsonDecode(brut) as Map<String, dynamic>);
    expect(p2.cote, greaterThan(kPlafond['cote']! + 1e-9));
    expect(p2.victoires, greaterThan(kPlafond['victoires']! + 1e-9));
    // ignore: avoid_print
    print('T2b sauvegarde 13/11 : cote ${_f(p2.cote)} > 0,40 ET '
        'victoires ${_f(p2.victoires)} > 0,15 — DÉJÀ hors bornes, '
        'c\'est la preuve en production');

    // (d) Dérive par appels successifs SANS aucun apprentissage.
    final etat = IaPoidsAdaptatifs.fromJson(Map<String, dynamic>.from(kPoidsNov));
    final partSauvee = _somme(_depuis(etat), kEnrichis);
    // ★★ MESURE CORRIGÉE (D-1, 27/11/2026) — J'AI COMPARÉ DEUX CHOSES DIFFÉRENTES.
    //   Ma première version prenait `parts.first` AVANT tout appel, donc la part
    //   SAUVEGARDÉE (0,184840837400), et la comparait au point fixe (0,180000000000).
    //   L'écart de 0,004840837400 qu'elle mesurait n'était PAS une dérive : c'était
    //   la CORRECTION LÉGITIME appliquée une seule fois à la table sauvegardée pour
    //   la ramener dans le domaine. La dérive, elle, se mesure entre DEUX APPELS
    //   SUCCESSIFS sans apprentissage — c'est-à-dire entre l'état APRÈS 1 appel et
    //   l'état APRÈS N appels. C'est ce que fait le test ci-dessous.
    etat.clamp();
    final parts = <double>[_somme(_depuis(etat), kEnrichis)];
    for (var i = 0; i < 11; i++) {
      etat.clamp();
      parts.add(_somme(_depuis(etat), kEnrichis));
    }
    // On pousse à 500 pour chercher le point fixe.
    for (var i = 0; i < 500; i++) {
      etat.clamp();
    }
    final fixe = _somme(_depuis(etat), kEnrichis);
    // ignore: avoid_print
    print('T2c part enrichie : SAUVEGARDÉE ${_f(partSauvee)} → après 1 passe '
        '${_f(parts.first)} → 11 passes ${_f(parts.last)} → point fixe 500 '
        '${_f(fixe)}');
    final amplitude = (fixe - parts.first).abs();
    // ignore: avoid_print
    print('    amplitude de dérive ENTRE APPELS = ${_f(amplitude)} '
        '(${(amplitude / parts.first * 100).toStringAsFixed(6)} %)');
    // ★★ ASSERTION VOLONTAIREMENT RÉANCRÉE (D-1, 27/11/2026).
    //   JUSTIFICATION ÉCRITE. L'assertion d'origine exigeait que la dérive soit
    //   RÉELLE et non nulle (`greaterThan(1e-4)`), avec le motif « la dérive
    //   doit être RÉELLE et non nulle ». C'était une CARACTÉRISATION du défaut
    //   (C7/C10 violés), et la consigne §5 exige précisément « Idempotence à
    //   1e-12 » et « Absence de dérive sans nouvel apprentissage ». Les deux
    //   exigences sont incompatibles : on ne peut pas verrouiller la dérive ET
    //   l'idempotence.
    //   Le nouveau verrou est PLUS FORT : il exige zéro (à 1e-12), au lieu de
    //   constater un déplacement quelconque. La valeur historiquement mesurée
    //   est CONSERVÉE ci-dessous, à l'écran, pour que la comparaison reste
    //   possible.
    expect(amplitude, lessThanOrEqualTo(1e-12),
        reason: 'C10 : les appels successifs de clamp() sans apprentissage ne '
            'doivent produire AUCUNE dérive (l\'ancien mécanisme dérivait de '
            '2,6189 % entre la 1re passe et le point fixe)');
    // ignore: avoid_print
    print('    ANCIEN mécanisme : dérive 2,6189 % (part 0,184840837400 → '
        '0,180000000000), cote saturée 0,400000000000, victoires 0,150000000000. '
        'D-1 : ${(amplitude / parts.first * 100).toStringAsFixed(6)} %.');

    // Le point fixe reste le plancher collectif 0,18 : la table réelle du 13/11
    // est ramenée à 0,18 en UNE seule passe, puis n'en bouge plus.
    expect(fixe, closeTo(kPlancherCollectif, 1e-9),
        reason: 'mesuré ${_f(fixe)}');
    // Et la projection tient le contrat complet sur le point fixe.
    final violFixe = _verifierContrat(_depuis(etat), tol: 1e-9);
    expect(violFixe, isEmpty,
        reason: 'le point fixe doit satisfaire C1→C6 : $violFixe');

    // ★ CONSÉQUENCE MESURÉE DE LA CORRECTION §2 — À DOCUMENTER, PAS À CACHER.
    //   Point fixe AVANT §2 (planchers enrichis Σ 0,16) : part enrichie
    //     0,185444691312, cote saturée à 0,400000000000 EXACTEMENT,
    //     victoires saturée à 0,150000000000 EXACTEMENT.
    //   Point fixe APRÈS §2 (planchers enrichis Σ 0,06) : la part enrichie
    //     tombe à 0,180000000000 (le plancher collectif MORD désormais) et
    //     cote vaut 0,342084344962765, donc SOUS son plafond de 0,40.
    //   ⇒ La réduction des planchers n'est pas cosmétique : elle change le
    //     point d'équilibre de clamp(). C'est un effet structurel réel, qui
    //     n'est pas une amélioration prouvée de précision hippique.
    // ignore: avoid_print
    print('T2c point fixe après §2 : cote ${_f(etat.cote)} (plafond 0,40 — '
        'n\'est plus saturé) · victoires ${_f(etat.victoires)} (plafond 0,15 — '
        '${etat.victoires > kPlafond['victoires']! ? "encore au-dessus" : "résorbé"})');
    // ignore: avoid_print
    print('    AVANT §2 le point fixe était : part 0,185444691312 · cote saturée '
        '0,400000000000 · victoires saturée 0,150000000000');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T3 — SOLUTION CANDIDATE : contrat respecté + preuve d'isolement
  // ═════════════════════════════════════════════════════════════════════════
  test('T3 — la projection candidate respecte le contrat sur le réel', () {
    // Preuve d'ISOLEMENT : le nom `_Projection` n'existe nulle part dans lib/.
    final hits = <String>[];
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is File && e.path.endsWith('.dart')) {
        final c = e.readAsStringSync();
        if (c.contains('_Projection') || c.contains('group-budget')) {
          hits.add(e.path);
        }
      }
    }
    expect(hits, isEmpty,
        reason: 'la solution candidate ne doit apparaître NULLE PART dans lib/');
    // ignore: avoid_print
    print('T3a isolement vérifié : 0 occurrence de la candidate dans lib/ '
        '(${Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')).length} fichiers .dart parcourus)');

    // Contrat sur l'état réel du 13/11, qui VIOLE aujourd'hui ses bornes.
    final projete = _Projection.appliquer(kPoidsNov);
    final viol = _verifierContrat(projete);
    // ignore: avoid_print
    print('T3b état 13/11 projeté : Σ=${_f(_somme(projete, kCles))} · '
        'part enrichie=${_f(_somme(projete, kEnrichis))} · violations=${viol.length}');
    expect(viol, isEmpty, reason: 'le contrat doit être vérifié : $viol');

    // Et sur 400 tirages aléatoires reproductibles.
    final rnd = math.Random(20261127);
    var ok = 0;
    for (var i = 0; i < 400; i++) {
      final brut = <String, double>{
        for (final k in kCles) k: rnd.nextDouble() * 0.5,
      };
      final out = _Projection.appliquer(brut);
      if (_verifierContrat(out).isEmpty) ok++;
    }
    // ignore: avoid_print
    print('T3c 400 tables aléatoires → contrat respecté : $ok / 400');
    expect(ok, 400, reason: 'toutes les tables doivent satisfaire le contrat');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T4 — IDEMPOTENCE : aucun dérive sur appels successifs
  // ═════════════════════════════════════════════════════════════════════════
  test('T4 — la projection candidate est IDEMPOTENTE (0 dérive)', () {
    final p1 = _Projection.appliquer(kPoidsNov);
    final p2 = _Projection.appliquer(p1);
    final p10 = () {
      var m = p1;
      for (var i = 0; i < 9; i++) {
        m = _Projection.appliquer(m);
      }
      return m;
    }();

    var d1 = 0.0;
    var d10 = 0.0;
    for (final k in kCles) {
      d1 = math.max(d1, (p2[k]! - p1[k]!).abs());
      d10 = math.max(d10, (p10[k]! - p1[k]!).abs());
    }
    // ignore: avoid_print
    print('T4  écart max 1→2 passes : ${_f(d1)} · 1→10 passes : ${_f(d10)}');
    expect(d1, lessThan(1e-12), reason: 'la projection doit être idempotente');
    expect(d10, lessThan(1e-12));

    // Sur 400 tables aléatoires : 2e passage = no-op exact.
    final rnd = math.Random(7);
    var maxEcart = 0.0;
    for (var i = 0; i < 400; i++) {
      final brut = <String, double>{
        for (final k in kCles) k: rnd.nextDouble() * 0.5,
      };
      final a = _Projection.appliquer(brut);
      final b = _Projection.appliquer(a);
      for (final k in kCles) {
        maxEcart = math.max(maxEcart, (b[k]! - a[k]!).abs());
      }
    }
    // ignore: avoid_print
    print('T4b 400 tables × 2 passages → écart max ${_f(maxEcart)}');
    expect(maxEcart, lessThan(1e-12));
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T5 — CONSERVATION DES POIDS DÉJÀ CONFORMES
  // ═════════════════════════════════════════════════════════════════════════
  test('T5 — une table déjà conforme est rendue quasi inchangée', () {
    // On part du point fixe de clamp() (donc conforme aux bornes ET au
    // collectif), et on mesure ce que la projection y change.
    final etat = IaPoidsAdaptatifs.fromJson(Map<String, dynamic>.from(kPoidsNov));
    for (var i = 0; i < 500; i++) {
      etat.clamp();
    }
    final conforme = _depuis(etat);
    final viol = _verifierContrat(conforme, tol: 1e-8);
    // ignore: avoid_print
    print('T5  point fixe de clamp() est-il conforme ? violations=${viol.length} '
        '${viol.isEmpty ? "" : viol}');

    final proj = _Projection.appliquer(conforme);
    var maxEcart = 0.0;
    for (final k in kCles) {
      maxEcart = math.max(maxEcart, (proj[k]! - conforme[k]!).abs());
    }
    // ignore: avoid_print
    print('T5  projection d\'une table conforme : écart max ${_f(maxEcart)}');
    expect(maxEcart, lessThan(1e-12),
        reason: 'une table conforme doit être un point fixe de la projection');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T6 — CHEMINS DE PRODUCTION RÉELS ET DISTINCTION SAUVÉ / NOUVEAU
  // ═════════════════════════════════════════════════════════════════════════
  test('T6 — les 4 chemins de mutation et la frontière sauvegardé/nouveau', () {
    // Relevé par grep dans lib/ — MESURÉ, pas supposé :
    //   ia_memory_service.dart:4093  _poids.clamp()      ← fin de _apprendreParGradient   (gradient)
    //   ia_memory_service.dart:4288  clampDiscipline()   ← fin de _apprendreParDiscipline (par discipline)
    //   ia_memory_service.dart:4507  _poids.clamp()      ← fin de _apprendreReglesBase    (règles de base)
    //   ia_memory_service.dart:6015  _poids.normaliser() ← fin de _mettreAJourPrecisionIA (stats label)
    //   ia_memory_service.dart:6008-6011  4 .clamp(0.01, …) directs (piste stats label)
    //   fromJson : AUCUN clamp, AUCUNE normalisation.
    final svc = File('lib/services/ia_memory_service.dart').readAsStringSync();
    expect(RegExp(r'_poids\.clamp\(\);').allMatches(svc).length, 2,
        reason: '2 appels à _poids.clamp() attendus (4093, 4507)');
    expect(RegExp(r'_poids\.normaliser\(\);').allMatches(svc).length, 1,
        reason: '1 appel à _poids.normaliser() attendu (6015)');
    expect(RegExp(r'IaPoidsAdaptatifs\.clampDiscipline\(').allMatches(svc).length, 1,
        reason: '1 appel à clampDiscipline attendu (4288)');
    // ★ 27/11/2026 — DÉFINITION #3 : les 4 planchers de la piste « stats par
    //   label » ont été abaissés à 0,005 (autorisation §2, « définitions
    //   dupliquées »). Leurs PLAFONDS sont inchangés.
    expect(RegExp(r'\.clamp\(0\.01, 0\.(10|08|07)\)').allMatches(svc).length, 0,
        reason: 'plus aucun plancher 0,01 sur la piste stats-label');
    expect(RegExp(r'\.clamp\(0\.005, 0\.(10|08|07)\)').allMatches(svc).length, 4,
        reason: 'les 4 planchers stats-label doivent valoir 0,005');

    // Frontière : fromJson ne mute rien.
    // ★ CORRECTION D'UNE AFFIRMATION FAUSSE : j'avais d'abord testé
    //   `corps.contains('clamp')`, qui renvoyait TRUE parce que MES PROPRES
    //   COMMENTAIRES dans le corps de `fromJson` contiennent le mot « clamp ».
    //   On filtre donc les lignes de commentaire avant de conclure.
    final modele = File('lib/services/ia_memory_models.dart').readAsStringSync();
    final debut = modele.indexOf('factory IaPoidsAdaptatifs.fromJson');
    final fin = modele.indexOf('factory IaPoidsAdaptatifs.defaut()');
    expect(debut, greaterThan(0));
    expect(fin, greaterThan(debut));
    final corps = modele
        .substring(debut, fin)
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(corps.contains('.clamp('), isFalse,
        reason: 'fromJson ne doit contenir AUCUN appel à clamp()');
    expect(corps.contains('normaliser('), isFalse,
        reason: 'fromJson ne doit contenir AUCUN appel à normaliser()');

    // ignore: avoid_print
    print('T6  2×_poids.clamp() · 1×normaliser() · 1×clampDiscipline() · '
        '4 bornes stats-label intactes · fromJson SANS clamp ni normaliser');
    // ignore: avoid_print
    print('    ⇒ un poids SAUVEGARDÉ n\'est jamais re-projeté à la lecture ; '
        'seuls les poids NOUVEAUX passent par l\'une des 4 sorties ci-dessus');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T7 — RÉVERSIBILITÉ : promotion / rétrogradation / retour
  // ═════════════════════════════════════════════════════════════════════════
  test('T7 — promotion, rétrogradation et retour après neutralité (§7)', () {
    // Cycle d'apprentissage RÉEL : on applique 12 pas de gradient sur un
    // critère donné puis clamp(), et on observe son poids effectif.
    Map<String, double> cycle(Map<String, double> depart, String critere,
        double delta, int n) {
      final p = IaPoidsAdaptatifs.fromJson(Map<String, dynamic>.from(depart));
      for (var i = 0; i < n; i++) {
        // On reproduit l'effet d'un pas de gradient : +delta sur le critère,
        // puis la sortie standard du cycle d'apprentissage.
        final cle = critere;
        final nouveau = p.getPoids(cle) + delta;
        switch (cle) {
          case 'distSpec': p.distSpec = nouveau; break;
          case 'jockey': p.jockey = nouveau; break;
          case 'placeDepart': p.placeDepart = nouveau; break;
          case 'forme': p.forme = nouveau; break;
          default: break;
        }
        p.clamp();
      }
      return _depuis(p);
    }

    final base = IaPoidsAdaptatifs().let((p) {
      p.clamp();
      return _depuis(p);
    });

    // 1) PROMOTION d'un critère pertinent.
    final promu = cycle(base, 'distSpec', 0.02, 12);
    // ignore: avoid_print
    print('T7a distSpec : ${_f(base['distSpec']!)} → ${_f(promu['distSpec']!)} '
        '(plafond ${kPlafond['distSpec']}) — PROMOTION');
    expect(promu['distSpec']!, greaterThan(base['distSpec']!));

    // 2) RÉTROGRADATION d'un critère peu pertinent.
    final retro = cycle(base, 'jockey', -0.02, 12);
    // ignore: avoid_print
    print('T7b jockey : ${_f(base['jockey']!)} → ${_f(retro['jockey']!)} '
        '(plancher ${kPlancher['jockey']}) — RÉTROGRADATION');
    expect(retro['jockey']!, lessThan(base['jockey']!));

    // 3) RETOUR à une importance significative après neutralité.
    //    On amène placeDepart au plancher, on le maintient, puis on relance.
    final neutralise = cycle(base, 'placeDepart', -0.05, 20);
    final auPlancher = neutralise['placeDepart']!;
    final revenu = cycle(neutralise, 'placeDepart', 0.01, 10);
    // ignore: avoid_print
    print('T7c placeDepart : neutralisé ${_f(auPlancher)} → après reprise '
        '${_f(revenu['placeDepart']!)} — RETOUR');
    expect(revenu['placeDepart']!, greaterThan(auPlancher),
        reason: 'un critère neutralisé doit pouvoir retrouver du poids');

    // 4) Aucune modification des composants protégés : le gradient n'est pas
    //    touché — ses constantes sont vérifiées par lecture de source.
    final svc = File('lib/services/ia_memory_service.dart').readAsStringSync();
    expect(svc.contains('lrBase = 0.08'), isTrue,
        reason: 'lrBase 0,08 doit être intact');
    expect(svc.contains('momentumFactor'), isTrue);
    // ★★ ASSERTION VOLONTAIREMENT RÉANCRÉE (D-1, 27/11/2026).
    //   JUSTIFICATION ÉCRITE. L'assertion cherchait la chaîne
    //   `fractionEnrichi.clamp(0.18, 0.40)` : le NOM d'une variable interne de
    //   l'ancien `normaliser()`, que D-1 remplace. La contrainte, elle, est
    //   intacte et vaut toujours 0,18 / 0,40 — ce sont les constantes
    //   `kPartEnrichieMin` / `kPartEnrichieMax`. Vérifier un nom de variable
    //   n'était pas vérifier la contrainte ; on vérifie maintenant la valeur.
    final modele = File('lib/services/ia_memory_models.dart').readAsStringSync();
    expect(modele.contains('kPartEnrichieMin = 0.18'), isTrue,
        reason: 'plancher collectif enrichi 0,18 absent du modèle');
    expect(modele.contains('kPartEnrichieMax = 0.40'), isTrue,
        reason: 'plafond collectif enrichi 0,40 absent du modèle');
    expect(IaPoidsAdaptatifs.kPartEnrichieMin, 0.18);
    expect(IaPoidsAdaptatifs.kPartEnrichieMax, 0.40);
    // ignore: avoid_print
    print('T7d protections : lrBase 0,08 intact · momentum intact · '
        'collectif 0,18/0,40 intact');
  });

  t8();
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

// ═══════════════════════════════════════════════════════════════════════════
//  T8 — §6 : COHÉRENCE D'ÉCHELLE DES CHEMINS DE PRODUCTION APRÈS §1
//
//  Question posée par l'utilisateur : « l'harmonisation des trois replis
//  laisse-t-elle subsister une incohérence d'échelle NON EXPLIQUÉE entre les
//  chemins de production ? » On ne répond pas par une opinion : on mesure
//  chaque chemin et on nomme la cause de chaque écart.
// ═══════════════════════════════════════════════════════════════════════════
void t8() {
  test('T8 — échelle des 6 chemins de production, cause de chaque écart', () {
    final mesures = <String, double>{};

    // Chemin A — instance neuve (constructeur), état vierge, AUCUN clamp.
    //   C'est ce que reçoit le moteur au tout premier lancement.
    final a = IaPoidsAdaptatifs();
    mesures['A constructeur brut'] = _somme(_depuis(a), kCles);

    // Chemin B — fromJson({}) : repli complet. Doit désormais ÉGALER A.
    final b = IaPoidsAdaptatifs.fromJson(<String, dynamic>{});
    mesures['B fromJson({})'] = _somme(_depuis(b), kCles);

    // Chemin C — fromJson d'un toJson() complet (aller-retour).
    final c = IaPoidsAdaptatifs.fromJson(
        jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
    mesures['C aller-retour'] = _somme(_depuis(c), kCles);

    // Chemin D — après clamp() : sortie standard d'un cycle d'apprentissage.
    final d = IaPoidsAdaptatifs();
    d.clamp();
    mesures['D après clamp()'] = _somme(_depuis(d), kCles);

    // Chemin E — poidsEffectifsPourDiscipline sans discipline apprise.
    final eff = a.poidsEffectifsPourDiscipline('Plat');
    mesures['E effectifs (19 clés)'] =
        eff.values.fold<double>(0.0, (x, y) => x + y);

    // Chemin F — table par discipline passée par clampDiscipline().
    final f = <String, double>{for (final k in kCles) k: kDefaut[k]!};
    IaPoidsAdaptatifs.clampDiscipline(f);
    mesures['F clampDiscipline'] = _somme(f, kCles);

    for (final e in mesures.entries) {
      // ignore: avoid_print
      print('T8  ${e.key.padRight(24)} Σ = ${_f(e.value)}');
    }

    // ── Conclusions EXIGÉES par la mesure, pas par l'intuition ─────────────
    // 1) Les 3 chemins « bruts » (A, B, C, E) somment 1,26 : COHÉRENTS entre eux.
    for (final cle in <String>[
      'A constructeur brut', 'B fromJson({})', 'C aller-retour',
      'E effectifs (19 clés)',
    ]) {
      expect(mesures[cle]!, closeTo(1.26, 1e-12),
          reason: '$cle doit sommer 1,26 — mesuré ${_f(mesures[cle]!)}');
    }
    // 2) Les 2 chemins « normalisés » (D, F) somment 1,00 : COHÉRENTS entre eux.
    expect(mesures['D après clamp()']!, closeTo(1.0, 1e-12));
    expect(mesures['F clampDiscipline']!, closeTo(1.0, 1e-12));
    // 3) L'écart 1,26 ↔ 1,00 est EXPLIQUÉ, et il n'est PAS uniforme de 1,26 :
    //    c'est un facteur PAR GROUPE, parce que `normaliser()` applique la
    //    contrainte collective séparément à la base et aux enrichis.
    //    ★ CORRECTION D'UNE AFFIRMATION FAUSSE : j'avais d'abord posé par
    //      calcul 0,82/Σbase = 1,183333. MESURE : Σbase des poids initiaux
    //      vaut 0,71 (0,25+0,13+0,10+0,08+0,09+0,04+0,02), donc le facteur
    //      réel est 0,82/0,71 = 1,154929577, et non 1,183333. On mesure au
    //      lieu de dériver.
    final base26 = kBase.fold<double>(0.0, (x, k) => x + kDefaut[k]!);
    final enr26 = kEnrichis.fold<double>(0.0, (x, k) => x + kDefaut[k]!);
    expect(base26 + enr26, closeTo(1.26, 1e-12));
    final dMap = _depuis(d);
    final baseApres = _somme(dMap, kBase);
    final enrApres = _somme(dMap, kEnrichis);
    final facteurBase = baseApres / base26;
    final facteurEnr = enrApres / enr26;
    // ignore: avoid_print
    print('T8  base  ${_f(base26)} → ${_f(baseApres)} = ×'
        '${facteurBase.toStringAsFixed(12)}');
    // ignore: avoid_print
    print('T8  enr.  ${_f(enr26)} → ${_f(enrApres)} = ×'
        '${facteurEnr.toStringAsFixed(12)}');
    // ★ CORRECTION D'UNE SECONDE AFFIRMATION FAUSSE.
    //   J'avais d'abord écrit que passer de 1,26 à 1,00 DILATAIT la base
    //   (facteur 1,183333). MESURE EXACTE, imprimée ci-dessus :
    //     base     0,710000000000 → 0,600000000000 = ×0,845070422535
    //     enrichis 0,550000000000 → 0,400000000000 = ×0,727272727273
    //   LES DEUX FACTEURS SONT INFÉRIEURS À 1. `normaliser()` ne dilate rien :
    //   la table 1,26 a une fraction enrichie de 0,550/1,26 = 0,436507937 qui
    //   est ÉCRÊTÉE à 0,40 ; la base est donc ramenée à 0,60 (au lieu de 0,71)
    //   et les enrichis à 0,40 (au lieu de 0,55). C'est une CONTRACTION, et
    //   elle est INÉGALE entre les deux groupes — d'où la variation du rapport
    //   de score d'un partant à l'autre.
    expect(facteurBase, closeTo(0.60 / 0.71, 1e-12),
        reason: 'facteur base mesuré = 0,60 / 0,71');
    expect(facteurEnr, closeTo(0.40 / 0.55, 1e-12),
        reason: 'facteur enrichis mesuré = 0,40 / 0,55 (écrêtage de 0,436507937)');
    expect(facteurBase, lessThan(1.0));
    expect(facteurEnr, lessThan(1.0));
    // Les deux facteurs sont DIFFÉRENTS : l'écart 1,26 → 1,00 n'est donc pas
    // une simple homothétie.
    expect((facteurBase - facteurEnr).abs(), greaterThan(0.01),
        reason: 'les deux facteurs doivent être distincts');
    // ignore: avoid_print
    print('    écart 1,26→1,00 EXPLIQUÉ : DEUX facteurs de CONTRACTION '
        'distincts (×${facteurBase.toStringAsFixed(9)} base / '
        '×${facteurEnr.toStringAsFixed(9)} enrichis) — écart entre les deux '
        '${(facteurBase - facteurEnr).abs().toStringAsFixed(9)}');
    // 4) AUCUN chemin ne produit un résultat hors de [1,00 ; 1,26] : la
    //    dilatation maximale est 26 %, et elle est CONNUE.
    for (final e in mesures.entries) {
      expect(e.value, greaterThanOrEqualTo(1.0 - 1e-12));
      expect(e.value, lessThanOrEqualTo(1.26 + 1e-12));
    }
    // ignore: avoid_print
    print('T8  aucun chemin hors de [1,00 ; 1,26] · dilatation max connue = 26 % '
        '(était 37 % avant §1)');
  });
}
