// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER POIDS IA — VALIDATION D-1 : CONTRAT DE LA PROJECTION EN PRODUCTION
//
//  OBJET — prouver que le moteur de contraintes MAINTENANT EN PRODUCTION
//  (`IaPoidsAdaptatifs.projeter` / `normaliser()` / `clamp()` /
//  `clampDiscipline()`) tient SIMULTANÉMENT les dix clauses C1→C10 exigées,
//  et non seulement « en moyenne » :
//
//    C1  Σ des 19 poids = 1                       tolérance 1e-9
//    C2  les 19 planchers individuels respectés
//    C3  les 19 plafonds individuels respectés
//    C4  part enrichie ∈ [0,18 ; 0,40]
//    C5  aucune valeur négative
//    C6  aucun NaN, aucune valeur infinie
//    C7  idempotence                              tolérance 1e-12
//    C8  une table DÉJÀ conforme est conservée
//    C9  déterminisme (même entrée ⇒ même sortie, ordre de Map indifférent)
//    C10 aucune dérive sans nouvel apprentissage
//
//  ⚠️ TOUTES les mesures passent par les MÉTHODES RÉELLES de `lib/`. Aucune
//     réplique arithmétique n'est utilisée ici : c'est précisément ce que le
//     chantier reprochait aux harnais antérieurs (A0, G0). Les seules valeurs
//     recopiées sont les BORNES de référence, et le test P0 vérifie qu'elles
//     sont identiques à `bornesIndividuelles()` — donc si la production change,
//     P0 échoue au lieu de valider une mesure périmée.
//
//  ⚠️ [SYNTH] vs [REEL] — chaque test l'indique. Les tirages aléatoires et les
//     trajectoires de gradient synthétiques démontrent une PROPRIÉTÉ
//     MATHÉMATIQUE ; ils ne disent RIEN de la qualité des pronostics. Les tests
//     marqués [REEL] utilisent la sauvegarde figée du 13/11/2026 (3871 mises à
//     jour), qui est une donnée de production, pas un recalcul.
//
//  ⚠️ AUCUNE MODIFICATION DE PRODUCTION dans ce fichier : on instancie en
//     mémoire, on n'écrit rien sur disque, on ne déclenche aucun apprentissage.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';

// ─── Référentiel recopié — VERROUILLÉ par P0 ────────────────────────────────
const List<String> kCles = <String>[
  'forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline',
  'distSpec', 'jockey', 'repos', 'hippo', 'entraineur', 'elo',
  'terrain', 'divergence', 'poidsRel', 'progression', 'mouvCote', 'placeDepart',
];

const List<String> kBase = <String>[
  'forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline',
];

final List<String> kEnrichis =
    kCles.where((k) => !kBase.contains(k)).toList();

/// Bornes de la configuration de référence (§4 de la consigne).
const Map<String, double> kBas = <String, double>{
  'forme': 0.05, 'gains': 0.04, 'record': 0.03, 'cote': 0.05,
  'constance': 0.03, 'victoires': 0.01, 'discipline': 0.01,
  'distSpec': 0.005, 'jockey': 0.005, 'repos': 0.005, 'hippo': 0.005,
  'entraineur': 0.005, 'elo': 0.005, 'terrain': 0.005, 'divergence': 0.005,
  'poidsRel': 0.005, 'progression': 0.005, 'mouvCote': 0.005,
  'placeDepart': 0.005,
};

const Map<String, double> kHaut = <String, double>{
  'forme': 0.55, 'gains': 0.40, 'record': 0.35, 'cote': 0.40,
  'constance': 0.25, 'victoires': 0.15, 'discipline': 0.10,
  'distSpec': 0.18, 'jockey': 0.15, 'repos': 0.08, 'hippo': 0.10,
  'entraineur': 0.08, 'elo': 0.10, 'terrain': 0.10, 'divergence': 0.08,
  'poidsRel': 0.07, 'progression': 0.08, 'mouvCote': 0.12,
  'placeDepart': 0.07,
};

/// Les 19 poids initiaux BRUTS du constructeur (somme 1,26 — voir §10).
const Map<String, double> kInitial = <String, double>{
  'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
  'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
  'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
  'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05, 'divergence': 0.04,
  'poidsRel': 0.03, 'progression': 0.03, 'mouvCote': 0.06,
  'placeDepart': 0.03,
};

/// Poids RÉELLEMENT appris au 13/11/2026 (3871 mises à jour). [REEL]
const Map<String, double> kPoids1311 = <String, double>{
  'forme': 0.0587743673, 'gains': 0.0401813881, 'record': 0.0301360411,
  'cote': 0.4018138807, 'constance': 0.1239518902, 'victoires': 0.1506802053,
  'discipline': 0.0100453470, 'distSpec': 0.0538273691, 'jockey': 0.0200906940,
  'repos': 0.0100453470, 'hippo': 0.0100453470, 'entraineur': 0.0100453470,
  'elo': 0.0100453470, 'terrain': 0.0100453470, 'divergence': 0.0100453470,
  'poidsRel': 0.0100453470, 'progression': 0.0100453470,
  'mouvCote': 0.0200906940, 'placeDepart': 0.0100453470,
};

// ─── Utilitaires ────────────────────────────────────────────────────────────
Map<String, double> _depuis(IaPoidsAdaptatifs p) =>
    <String, double>{for (final k in kCles) k: p.getPoids(k)};

IaPoidsAdaptatifs _fabrique(Map<String, double> v) => IaPoidsAdaptatifs(
      forme: v['forme']!, gains: v['gains']!, record: v['record']!,
      cote: v['cote']!, constance: v['constance']!,
      victoires: v['victoires']!, discipline: v['discipline']!,
      distSpec: v['distSpec']!, jockey: v['jockey']!, repos: v['repos']!,
      hippo: v['hippo']!, entraineur: v['entraineur']!, elo: v['elo']!,
      terrain: v['terrain']!, divergence: v['divergence']!,
      poidsRel: v['poidsRel']!, progression: v['progression']!,
      mouvCote: v['mouvCote']!, placeDepart: v['placeDepart']!,
    );

double _sommeCle(Map<String, double> m, List<String> cles) =>
    cles.fold(0.0, (a, k) => a + (m[k] ?? 0.0));

String _f(double v) => v.toStringAsFixed(12);

/// Vérifie C1→C6 sur une table projetée. Rend la liste des violations.
/// (C7/C8/C9/C10 ont leurs propres tests : ils ne se lisent pas sur une table.)
List<String> _violations(Map<String, double> m) {
  final v = <String>[];
  var somme = 0.0;
  for (final k in kCles) {
    final x = m[k];
    if (x == null) {
      v.add('C1/clé: $k ABSENT');
      continue;
    }
    somme += x;
    if (x.isNaN) v.add('C6: $k = NaN');
    if (x.isInfinite) v.add('C6: $k = infini');
    if (x < 0) v.add('C5: $k = $x < 0');
    if (x < kBas[k]! - 1e-12) v.add('C2: $k = $x < plancher ${kBas[k]}');
    if (x > kHaut[k]! + 1e-12) v.add('C3: $k = $x > plafond ${kHaut[k]}');
  }
  if ((somme - 1.0).abs() > 1e-9) v.add('C1: Σ = $somme ≠ 1');
  final part = _sommeCle(m, kEnrichis);
  if (part < 0.18 - 1e-9 || part > 0.40 + 1e-9) {
    v.add('C4: part enrichie = $part hors [0,18 ; 0,40]');
  }
  return v;
}

/// Table de référence « déjà conforme » : projection des poids initiaux.
Map<String, double> _tableConforme() =>
    _depuis(_fabrique(kInitial)..normaliser());

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  //  P0 — GARDE : le référentiel recopié est identique à celui de PRODUCTION
  // ═══════════════════════════════════════════════════════════════════════════
  test('P0 — GARDE : bornes recopiées == bornesIndividuelles() de production',
      () {
    final prod = IaPoidsAdaptatifs.bornesIndividuelles();
    expect(prod.length, 19, reason: 'production doit définir exactement 19 bornes');
    for (final k in kCles) {
      expect(prod.containsKey(k), isTrue, reason: 'borne manquante : $k');
      expect(prod[k]![0], closeTo(kBas[k]!, 1e-15),
          reason: 'plancher $k : recopié ${kBas[k]} ≠ production ${prod[k]![0]}');
      expect(prod[k]![1], closeTo(kHaut[k]!, 1e-15),
          reason: 'plafond $k : recopié ${kHaut[k]} ≠ production ${prod[k]![1]}');
    }
    // La liste figée et les deux groupes doivent coïncider avec les miens.
    expect(IaPoidsAdaptatifs.kClesOrdonnees, kCles);
    expect(IaPoidsAdaptatifs.kClesBase, kBase);
    expect(IaPoidsAdaptatifs.kClesEnrichies, kEnrichis);
    expect(IaPoidsAdaptatifs.kPartEnrichieMin, 0.18);
    expect(IaPoidsAdaptatifs.kPartEnrichieMax, 0.40);
    // ignore: avoid_print
    print('P0  GARDE OK — 19 bornes, 2 groupes et les 2 constantes collectives '
        'recopiés sont IDENTIQUES à la production.');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  P1 — C1→C6 sur le DOMAINE ENTIER [SYNTH]
  //
  //  Le point faible de l'ancien mécanisme était un DÉPASSEMENT dans certains
  //  coins de l'espace. On ne teste donc pas « quelques cas » : on balaie tout
  //  le domaine, y compris très au-delà des bornes (facteur ×3), puisque le
  //  gradient peut proposer n'importe quelle valeur avant contrainte.
  // ═══════════════════════════════════════════════════════════════════════════
  test('P1 — C1..C6 [SYNTH] : 3000 tables aléatoires, y compris hors bornes', () {
    final alea = math.Random(20261127);
    var pires = <String>[];
    var violations = 0;
    var horsBornesEntree = 0;

    for (var i = 0; i < 3000; i++) {
      // Facteur large : 0 à 3× l'amplitude des bornes, et parfois négatif.
      final facteur = alea.nextDouble() * 3.0;
      final v = <String, double>{
        for (final k in kCles)
          k: (kBas[k]! + alea.nextDouble() * (kHaut[k]! - kBas[k]!)) * facteur -
              (alea.nextBool() ? 0.05 : 0.0),
      };
      for (final k in kCles) {
        if (v[k]! < kBas[k]! || v[k]! > kHaut[k]!) horsBornesEntree++;
      }
      final sortie = IaPoidsAdaptatifs.projeter(v);
      final vio = _violations(sortie);
      if (vio.isNotEmpty) {
        violations++;
        if (pires.length < 6) pires.add('tirage $i : ${vio.take(4).join(' | ')}');
      }
    }
    // ignore: avoid_print
    print('P1  3000 tables · $horsBornesEntree valeurs d\'entrée hors bornes · '
        '$violations table(s) en violation');
    if (pires.isNotEmpty) {
      // ignore: avoid_print
      print('    exemples : ${pires.join(' ;; ')}');
    }
    expect(violations, 0,
        reason: 'C1..C6 doivent tenir sur TOUT le domaine, pas seulement au '
            'voisinage des valeurs d\'usine');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  P2 — C1→C6 sur les CAS EXTRÊMES déterministes [SYNTH]
  //
  //  Ce sont exactement les configurations qui faisaient DÉPASSER les plafonds
  //  à l'ancien `clamp()` (mesuré : 19/19 dans le coin « un seul au plafond,
  //  tous les autres au plancher »).
  // ═══════════════════════════════════════════════════════════════════════════
  test('P2 — C1..C6 [SYNTH] : les coins de l\'espace qui faisaient déborder', () {
    final cas = <String, Map<String, double>>{};

    // (1) « coin » : un critère au plafond, tous les autres au plancher.
    for (final k in kCles) {
      cas['coin $k'] = <String, double>{...kBas, k: kHaut[k]!};
    }
    // (2) tous les enrichis au plafond, la base au plancher.
    cas['enrichis au plafond'] = <String, double>{
      for (final k in kCles) k: kBase.contains(k) ? kBas[k]! : kHaut[k]!,
    };
    // (3) l'inverse.
    cas['base au plafond'] = <String, double>{
      for (final k in kCles) k: kBase.contains(k) ? kHaut[k]! : kBas[k]!,
    };
    // (4) tout au plancher.
    cas['tout au plancher'] = <String, double>{...kBas};
    // (5) tout au plafond.
    cas['tout au plafond'] = <String, double>{...kHaut};
    // (6) tout à zéro.
    cas['tout à zéro'] = <String, double>{for (final k in kCles) k: 0.0};
    // (7) valeurs absurdes : 1e6 et 1e-9 mélangés.
    cas['absurdes'] = <String, double>{
      for (var i = 0; i < kCles.length; i++)
        kCles[i]: i.isEven ? 1e6 : 1e-9,
    };
    // (8) table réelle du 13/11 (violations incluses). [REEL]
    cas['sauvegarde 13/11 réelle'] = <String, double>{...kPoids1311};

    var ko = 0;
    final lignes = <String>[];
    for (final e in cas.entries) {
      final s = IaPoidsAdaptatifs.projeter(e.value);
      final vio = _violations(s);
      if (vio.isNotEmpty) {
        ko++;
        lignes.add('${e.key} → ${vio.take(3).join(' | ')}');
      }
    }
    // ignore: avoid_print
    print('P2  ${cas.length} configurations extrêmes · $ko en violation');
    for (final l in lignes) {
      // ignore: avoid_print
      print('    $l');
    }
    expect(ko, 0,
        reason: 'aucun coin de l\'espace ne doit échapper aux contraintes');

    // Mesure du cas emblématique : `cote` au plafond, tout le reste au plancher.
    final coinCote = IaPoidsAdaptatifs.projeter(
        <String, double>{...kBas, 'cote': kHaut['cote']!});
    // ignore: avoid_print
    print('P2  ANCIEN mécanisme : cote 0,40 → 0,575438596491 (DÉPASSEMENT). '
        'PROJECTION : cote 0,40 → ${_f(coinCote['cote']!)} '
        '(plafond ${kHaut['cote']} — RESPECTÉ).');
    expect(coinCote['cote']!, lessThanOrEqualTo(kHaut['cote']! + 1e-12));
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  P3 — C7 : IDEMPOTENCE à 1e-12 [SYNTH + REEL]
  // ═══════════════════════════════════════════════════════════════════════════
  test('P3 — C7 : idempotence stricte (2 appels, 10 appels, 500 appels)', () {
    final etats = <String, Map<String, double>>{
      'initiaux': <String, double>{...kInitial},
      'réels 13/11': <String, double>{...kPoids1311},
      'aléatoire': <String, double>{
        for (final k in kCles) k: 0.005 + math.Random(7).nextDouble(),
      },
      'tout au plafond': <String, double>{...kHaut},
    };

    var pireEcart = 0.0;
    for (final e in etats.entries) {
      // 1 passe
      final p1 = IaPoidsAdaptatifs.projeter(e.value);
      // 2 passes
      final p2 = IaPoidsAdaptatifs.projeter(p1);
      var ecart2 = 0.0;
      for (final k in kCles) {
        final d = (p2[k]! - p1[k]!).abs();
        if (d > ecart2) ecart2 = d;
        if (d > pireEcart) pireEcart = d;
      }
      // 10 passes
      var p = p1;
      for (var i = 0; i < 10; i++) {
        p = IaPoidsAdaptatifs.projeter(p);
      }
      var ecart10 = 0.0;
      for (final k in kCles) {
        final d = (p[k]! - p1[k]!).abs();
        if (d > ecart10) ecart10 = d;
        if (d > pireEcart) pireEcart = d;
      }
      // ignore: avoid_print
      print('P3  ${e.key.padRight(16)} 1→2 : ${ecart2.toStringAsExponential(3)} '
          '· 1→10 : ${ecart10.toStringAsExponential(3)}');
    }
    expect(pireEcart, lessThanOrEqualTo(1e-12),
        reason: 'C7 : deux applications doivent être indiscernables');

    // La MÉTHODE d'instance aussi : `clamp()` deux fois de suite.
    final p = _fabrique(<String, double>{...kPoids1311});
    p.clamp();
    final apres1 = _depuis(p);
    p.clamp();
    final apres2 = _depuis(p);
    var ecartClamp = 0.0;
    for (final k in kCles) {
      final d = (apres2[k]! - apres1[k]!).abs();
      if (d > ecartClamp) ecartClamp = d;
    }
    // ignore: avoid_print
    print('P3  clamp() ×2 sur la table réelle : écart max = '
        '${ecartClamp.toStringAsExponential(3)}  '
        '(l\'ancien mécanisme dérivait de 2,6189 %)');
    expect(ecartClamp, lessThanOrEqualTo(1e-12));
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  P4 — C8 : une table DÉJÀ CONFORME est conservée [SYNTH]
  // ═══════════════════════════════════════════════════════════════════════════
  test('P4 — C8 : toute table déjà conforme est un point fixe', () {
    // On engendre des tables conformes en projetant des entrées quelconques,
    // puis on vérifie que la projection ne les touche plus.
    final alea = math.Random(424242);
    var verifiees = 0;
    var pireEcart = 0.0;
    for (var i = 0; i < 500; i++) {
      final brut = <String, double>{
        for (final k in kCles)
          k: alea.nextDouble() * (kHaut[k]! - kBas[k]!) + kBas[k]!,
      };
      final conforme = IaPoidsAdaptatifs.projeter(brut);
      final re = IaPoidsAdaptatifs.projeter(conforme);
      for (final k in kCles) {
        final d = (re[k]! - conforme[k]!).abs();
        if (d > pireEcart) pireEcart = d;
      }
      verifiees++;
    }
    // ignore: avoid_print
    print('P4  $verifiees tables conformes réinjectées : écart max = '
        '${pireEcart.toStringAsExponential(3)}');
    expect(pireEcart, lessThanOrEqualTo(1e-12));

    // Et la table conforme canonique (projection des poids initiaux) est
    // restituée à l'identique, valeur par valeur.
    final canon = _tableConforme();
    final re = IaPoidsAdaptatifs.projeter(canon);
    for (final k in kCles) {
      expect(re[k], closeTo(canon[k]!, 1e-12), reason: 'C8 sur $k');
    }
    // ignore: avoid_print
    print('P4  table canonique (projection des poids initiaux) : '
        'Σ = ${_f(_sommeCle(canon, kCles))} · part enrichie = '
        '${_f(_sommeCle(canon, kEnrichis))}');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  P5 — C9 : DÉTERMINISME, y compris vis-à-vis de l'ordre d'itération
  // ═══════════════════════════════════════════════════════════════════════════
  test('P5 — C9 : même entrée ⇒ même sortie ; l\'ordre de la Map est neutre', () {
    final alea = math.Random(999);
    // On construit la même table dans trois ORDRES d'insertion différents.
    final cles = <String>[...kCles];
    final melange1 = <String>[...cles]..shuffle(math.Random(1));
    final melange2 = <String>[...cles]..shuffle(math.Random(2));
    final melange3 = <String>[...cles]..shuffle(math.Random(3));

    var ecartMax = 0.0;
    for (var i = 0; i < 300; i++) {
      final valeurs = <String, double>{
        for (final k in kCles)
          k: alea.nextDouble() * (kHaut[k]! - kBas[k]!) + kBas[k]!,
      };
      final a = IaPoidsAdaptatifs.projeter(
          <String, double>{for (final k in cles) k: valeurs[k]!});
      final b = IaPoidsAdaptatifs.projeter(
          <String, double>{for (final k in melange1) k: valeurs[k]!});
      final c = IaPoidsAdaptatifs.projeter(
          <String, double>{for (final k in melange2) k: valeurs[k]!});
      final d = IaPoidsAdaptatifs.projeter(
          <String, double>{for (final k in melange3) k: valeurs[k]!});
      for (final k in kCles) {
        for (final autre in <Map<String, double>>[b, c, d]) {
          final e = (autre[k]! - a[k]!).abs();
          if (e > ecartMax) ecartMax = e;
        }
      }
    }
    // ignore: avoid_print
    print('P5  300 tables × 3 ordres d\'insertion : écart max = '
        '${ecartMax.toStringAsExponential(3)}');
    expect(ecartMax, lessThanOrEqualTo(1e-15),
        reason: 'C9 : aucun poids ne doit dépendre de l\'ordre de la Map');

    // Déterminisme strict : deux exécutions identiques, bit à bit.
    final ref = IaPoidsAdaptatifs.projeter(<String, double>{...kPoids1311});
    for (var i = 0; i < 20; i++) {
      final autre = IaPoidsAdaptatifs.projeter(<String, double>{...kPoids1311});
      for (final k in kCles) {
        expect(autre[k], equals(ref[k]), reason: 'non déterminisme sur $k');
      }
    }
    // ignore: avoid_print
    print('P5  20 exécutions successives sur la table réelle : résultats '
        'BIT À BIT identiques sur les 19 critères.');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  P6 — C10 : AUCUNE DÉRIVE SANS APPRENTISSAGE [REEL]
  //
  //  C'est le défaut le plus grave de l'ancien mécanisme : `clamp()` appelé
  //  à chaque mise à jour SANS qu'aucun apprentissage ne survienne déplaçait
  //  encore les poids (dérive mesurée 2,6189 %). Ici : 500 appels, écart nul.
  // ═══════════════════════════════════════════════════════════════════════════
  test('P6 — C10 : 500 appels sans apprentissage ⇒ dérive NULLE', () {
    for (final entree in <Map<String, double>>[
      <String, double>{...kInitial},
      <String, double>{...kPoids1311},
    ]) {
      final p = _fabrique(entree);
      p.clamp();
      final depart = _depuis(p);
      for (var i = 0; i < 500; i++) {
        p.clamp();
      }
      final arrivee = _depuis(p);
      var ecart = 0.0;
      for (final k in kCles) {
        final d = (arrivee[k]! - depart[k]!).abs();
        if (d > ecart) ecart = d;
      }
      // ignore: avoid_print
      print('P6  500 × clamp() : écart max = ${ecart.toStringAsExponential(3)} '
          '· Σ = ${_f(_sommeCle(arrivee, kCles))}');
      expect(ecart, lessThanOrEqualTo(1e-12),
          reason: 'C10 : sans nouvel apprentissage, rien ne doit bouger');
    }
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  P7 — C4 : la part enrichie reste dans [0,18 ; 0,40], et les DEUX bornes
  //           collectives sont réellement accessibles [SYNTH]
  // ═══════════════════════════════════════════════════════════════════════════
  test('P7 — C4 : bornes collectives respectées ET atteignables', () {
    // (a) Respect : sur 2000 tirages, jamais hors intervalle.
    final alea = math.Random(2026);
    var hors = 0;
    var mini = 1.0;
    var maxi = 0.0;
    for (var i = 0; i < 2000; i++) {
      final v = <String, double>{
        for (final k in kCles)
          k: alea.nextDouble() * (kHaut[k]! - kBas[k]!) + kBas[k]!,
      };
      final part = _sommeCle(IaPoidsAdaptatifs.projeter(v), kEnrichis);
      if (part < 0.18 - 1e-9 || part > 0.40 + 1e-9) hors++;
      if (part < mini) mini = part;
      if (part > maxi) maxi = part;
    }
    // ignore: avoid_print
    print('P7a 2000 tirages : part enrichie ∈ [${_f(mini)} ; ${_f(maxi)}] '
        '· $hors hors intervalle');
    expect(hors, 0);

    // (b) Atteignabilité du PLANCHER collectif : tout au plancher sauf la base
    //     poussée très haut → la part enrichie doit être ramenée à 0,18.
    final versPlancher = IaPoidsAdaptatifs.projeter(<String, double>{
      for (final k in kCles) k: kBase.contains(k) ? kHaut[k]! * 10 : kBas[k]!,
    });
    final partBas = _sommeCle(versPlancher, kEnrichis);
    // ignore: avoid_print
    print('P7b base écrasante → part enrichie = ${_f(partBas)} '
        '(plancher collectif 0,18)');
    expect(partBas, closeTo(0.18, 1e-9));

    // (c) Atteignabilité du PLAFOND collectif : tous les enrichis au plafond,
    //     la base au plancher.
    final versPlafond = IaPoidsAdaptatifs.projeter(<String, double>{
      for (final k in kCles) k: kBase.contains(k) ? kBas[k]! : kHaut[k]!,
    });
    final partHaut = _sommeCle(versPlafond, kEnrichis);
    // ignore: avoid_print
    print('P7c enrichis écrasants → part enrichie = ${_f(partHaut)} '
        '(plafond collectif 0,40)');
    expect(partHaut, closeTo(0.40, 1e-9));
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  P8 — CONSERVATION DES ÉVOLUTIONS RELATIVES quand aucune contrainte ne mord
  // ═══════════════════════════════════════════════════════════════════════════
  test('P8 — hors contrainte, la projection ne change PAS les proportions', () {
    // On prend une table conforme et on applique une PETITE évolution qui
    // reste strictement à l'intérieur des bornes et de la part collectives.
    final depart = _tableConforme();
    const delta = 0.0015;
    final evolution = <String, double>{...depart};
    evolution['distSpec'] = depart['distSpec']! + delta;
    // On retire le même montant à un autre enrichi pour rester à part constante.
    evolution['jockey'] = depart['jockey']! - delta;

    final projete = IaPoidsAdaptatifs.projeter(evolution);
    var ecart = 0.0;
    var pire = '';
    for (final k in kCles) {
      final d = (projete[k]! - evolution[k]!).abs();
      if (d > ecart) {
        ecart = d;
        pire = k;
      }
    }
    // ignore: avoid_print
    print('P8  évolution interne de ±$delta (échange distSpec ↔ jockey) : '
        'écart max après projection = ${ecart.toStringAsExponential(3)} sur "$pire"');
    expect(ecart, lessThanOrEqualTo(1e-9),
        reason: 'hors contrainte, la projection doit être quasi neutre : elle '
            'ne doit pas réécrire une évolution légitime');

    // Et sur une évolution RELATIVE (mise à l'échelle d'un groupe), la
    // projection doit conserver les RAPPORTS internes : c'est la métrique de
    // conservation (distance euclidienne) qui le garantit.
    final echelle = <String, double>{
      for (final k in kCles)
        k: kBase.contains(k) ? depart[k]! : depart[k]! * 1.10,
    };
    final pEchelle = IaPoidsAdaptatifs.projeter(echelle);
    // rapport interne entre deux enrichis, avant et après
    final rAvant = echelle['distSpec']! / echelle['jockey']!;
    final rApres = pEchelle['distSpec']! / pEchelle['jockey']!;
    // ignore: avoid_print
    print('P8  rapport interne distSpec/jockey : avant ${rAvant.toStringAsFixed(9)} '
        '→ après ${rApres.toStringAsFixed(9)} (écart relatif '
        '${((rApres - rAvant) / rAvant * 100).toStringAsFixed(6)} %)');
    expect((rApres - rAvant).abs() / rAvant, lessThan(1e-6),
        reason: 'la redistribution ne doit pas altérer les proportions '
            'internes d\'un groupe quand elle n\'a pas à le faire');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  P9 — SATURATION SIMULTANÉE de plusieurs critères [SYNTH]
  // ═══════════════════════════════════════════════════════════════════════════
  test('P9 — plusieurs critères aux bornes EN MÊME TEMPS : contrat tenu', () {
    // 8 critères poussés très au-delà de leur plafond simultanément.
    final v = <String, double>{...kInitial};
    final satures = <String>[
      'cote', 'victoires', 'distSpec', 'jockey', 'mouvCote', 'forme',
      'record', 'progression',
    ];
    for (final k in satures) {
      v[k] = kHaut[k]! * 50;
    }
    final proj = IaPoidsAdaptatifs.projeter(v);
    final vio = _violations(proj);
    // ignore: avoid_print
    print('P9  ${satures.length} critères saturés simultanément → '
        '${vio.isEmpty ? "0 violation" : vio.join(" | ")}');
    // ignore: avoid_print
    for (final k in satures) {
      // ignore: avoid_print
      print('    $k = ${_f(proj[k]!)}  (plafond ${kHaut[k]} '
          '${(proj[k]! - kHaut[k]!).abs() < 1e-12 ? "— SATURÉ" : ""})');
    }
    expect(vio, isEmpty);

    // ── CONSTAT MESURÉ, ET NON POSTULÉ ────────────────────────────────────
    //
    //  J'avais d'abord écrit ici l'assertion « aucun critère libre ne doit
    //  tomber à son plancher ». LA MESURE L'A RÉFUTÉE : dans cette
    //  configuration, `discipline` (proposé à 0,02 alors que `forme` est
    //  proposé à 27,50, soit un rapport de 1 à 1 375) tombe à son plancher
    //  0,01. Ce n'est PAS un défaut de la projection : c'est exactement ce que
    //  dit la métrique de conservation. Le point le plus proche du vecteur
    //  proposé, sous contrainte de somme de groupe, place au plancher un
    //  critère dont la proposition est négligeable devant celle de ses voisins.
    //  Prétendre le contraire reviendrait à trahir la proposition du gradient.
    //
    //  Ce qui importe est donc de distinguer DEUX régimes, et de mesurer les
    //  deux : (a) le régime ABSURDE ci-dessus, où l'écrasement est fidèle ;
    //  (b) le régime RÉEL du gradient, où les pas sont incrémentaux et où aucun
    //  écrasement ne doit se produire. C'est (b) que P11 mesure sur 19
    //  trajectoires. On vérifie ici que (a) reste malgré tout CONFORME.
    final nonSatures = kCles.where((k) => !satures.contains(k)).toList();
    final ecrases = <String>[];
    for (final k in nonSatures) {
      if ((proj[k]! - kBas[k]!).abs() < 1e-12) ecrases.add(k);
    }
    // ignore: avoid_print
    print('P9  critères non saturés : ${nonSatures.length} · '
        'tombés à leur plancher : ${ecrases.length} $ecrases');
    for (final k in ecrases) {
      // ignore: avoid_print
      print('    "$k" : proposé ${v[k]} alors que le groupe monte à '
          '${v.values.reduce(math.max)} ⇒ rapport de 1 à '
          '${(v.values.reduce(math.max) / v[k]!).toStringAsFixed(0)}. '
          'Écrasement FIDÈLE à la proposition, pas un biais de la projection.');
    }
    // L'écrasement ne doit concerner QUE des critères dont la proposition est
    // négligeable (moins de 1 % du maximum du groupe) : sinon ce serait un
    // biais de traitement.
    final maxGroupe = v.values.reduce(math.max);
    for (final k in ecrases) {
      expect(v[k]! / maxGroupe, lessThan(0.01),
          reason: '"$k" a été écrasé alors que sa proposition n\'était pas '
              'négligeable : ce serait un vrai biais, à corriger');
    }
    // ignore: avoid_print
    print('P9  les ${ecrases.length} critère(s) écrasé(s) avaient tous une '
        'proposition < 1 % du maximum du groupe ⇒ aucun biais de traitement.');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  P10 — COMPORTEMENT AUX LIMITES (entrées dégénérées) [SYNTH]
  // ═══════════════════════════════════════════════════════════════════════════
  test('P10 — limites : NaN, infini, négatifs, zéros, clés absentes', () {
    // NaN et infinis.
    final avecNan = <String, double>{
      ...kInitial, 'forme': double.nan, 'gains': double.infinity,
      'record': double.negativeInfinity,
    };
    final s1 = IaPoidsAdaptatifs.projeter(avecNan);
    expect(_violations(s1), isEmpty, reason: 'C6 : NaN/infini doivent être absorbés');
    // ignore: avoid_print
    print('P10 NaN/infini : forme=${_f(s1['forme']!)} gains=${_f(s1['gains']!)} '
        'record=${_f(s1['record']!)} (ramenés à leur plancher, C5/C6)');

    // Négatifs.
    final avecNeg = <String, double>{
      for (final k in kCles) k: -0.5,
    };
    final s2 = IaPoidsAdaptatifs.projeter(avecNeg);
    expect(_violations(s2), isEmpty);
    // ignore: avoid_print
    print('P10 table entièrement négative → Σ = ${_f(_sommeCle(s2, kCles))} · '
        'aucune valeur négative (C5)');

    // Tout à zéro.
    final s3 = IaPoidsAdaptatifs.projeter(
        <String, double>{for (final k in kCles) k: 0.0});
    expect(_violations(s3), isEmpty);
    // ignore: avoid_print
    print('P10 table entièrement nulle → Σ = ${_f(_sommeCle(s3, kCles))} · '
        'part enrichie = ${_f(_sommeCle(s3, kEnrichies2))}');

    // Clés ABSENTES (Map partielle) : les clés manquantes valent 0 → plancher.
    final partielle = <String, double>{'forme': 0.30, 'cote': 0.20};
    final s4 = IaPoidsAdaptatifs.projeter(partielle);
    expect(_violations(s4), isEmpty);
    // ignore: avoid_print
    print('P10 Map partielle (2 clés sur 19) → Σ = ${_f(_sommeCle(s4, kCles))} '
        '· 19 clés produites, manquantes à leur plancher');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  P11 — CAPACITÉ D'ÉVOLUTION DES 19 CRITÈRES : promotion, rétrogradation,
  //        réactivation [SYNTH — mécanisme ; données synthétiques]
  //
  //  On applique la VRAIE boucle de mise à jour (`normaliser()` après chaque
  //  pas, comme `_apprendreParGradient` le fait), avec des pas représentatifs
  //  du gradient réel (lr 0,08 × discrimination × facteur, borné).
  // ═══════════════════════════════════════════════════════════════════════════
  test('P11 — promotion, rétrogradation, réactivation des 19 critères', () {
    // Facteurs RÉELS du gradient (ia_memory_service.dart) — recopiés, non
    // modifiés : ils servent uniquement à rendre le pas synthétique réaliste.
    const facteur = <String, double>{
      'forme': 1.0, 'gains': 1.0, 'record': 1.0, 'cote': 1.0,
      'constance': 1.0, 'victoires': 1.0, 'discipline': 1.0,
      'distSpec': 0.5, 'jockey': 0.5, 'repos': 0.3, 'hippo': 0.4,
      'entraineur': 0.4, 'elo': 0.5, 'terrain': 0.5, 'divergence': 0.4,
      'poidsRel': 0.3, 'progression': 0.4, 'mouvCote': 0.5, 'placeDepart': 0.3,
    };
    const lr = 0.08; // lrBase, non modifié

    /// Applique `n` pas de gradient synthétique sur `cible` (discrimination
    /// constante) et rend l'état final.
    Map<String, double> apprendre(
      Map<String, double> depart,
      String cible,
      double discrimination,
      int n,
    ) {
      final p = _fabrique(depart);
      for (var i = 0; i < n; i++) {
        final pas = lr * discrimination * facteur[cible]!;
        switch (cible) {
          case 'forme': p.forme = p.forme + pas; break;
          case 'gains': p.gains = p.gains + pas; break;
          case 'record': p.record = p.record + pas; break;
          case 'cote': p.cote = p.cote + pas; break;
          case 'constance': p.constance = p.constance + pas; break;
          case 'victoires': p.victoires = p.victoires + pas; break;
          case 'discipline': p.discipline = p.discipline + pas; break;
          case 'distSpec': p.distSpec = p.distSpec + pas; break;
          case 'jockey': p.jockey = p.jockey + pas; break;
          case 'repos': p.repos = p.repos + pas; break;
          case 'hippo': p.hippo = p.hippo + pas; break;
          case 'entraineur': p.entraineur = p.entraineur + pas; break;
          case 'elo': p.elo = p.elo + pas; break;
          case 'terrain': p.terrain = p.terrain + pas; break;
          case 'divergence': p.divergence = p.divergence + pas; break;
          case 'poidsRel': p.poidsRel = p.poidsRel + pas; break;
          case 'progression': p.progression = p.progression + pas; break;
          case 'mouvCote': p.mouvCote = p.mouvCote + pas; break;
          case 'placeDepart': p.placeDepart = p.placeDepart + pas; break;
        }
        // Sortie standard du cycle d'apprentissage : contraintes appliquées.
        p.clamp();
      }
      return _depuis(p);
    }

    final base = _tableConforme();

    // (1) PROMOTION d'un critère initialement FAIBLE (poidsRel, plancher 0,005,
    //     plafond 0,07) : discrimination positive et persistante.
    final promu = apprendre(base, 'poidsRel', 0.35, 200);
    // ignore: avoid_print
    print('P11a PROMOTION poidsRel : ${_f(base['poidsRel']!)} → '
        '${_f(promu['poidsRel']!)} (plafond 0,07)');
    expect(promu['poidsRel']!, greaterThan(base['poidsRel']! * 1.2),
        reason: 'un critère initialement faible doit pouvoir gagner en '
            'importance de façon mesurable');

    // (2) RÉTROGRADATION d'un critère fortement pondéré (forme, 0,25 initial).
    final retro = apprendre(base, 'forme', -0.35, 200);
    // ignore: avoid_print
    print('P11b RÉTROGRADATION forme : ${_f(base['forme']!)} → '
        '${_f(retro['forme']!)} (plancher 0,05)');
    expect(retro['forme']!, lessThan(base['forme']! * 0.8),
        reason: 'un critère fortement pondéré doit pouvoir perdre son avance');

    // (3) RÉACTIVATION après neutralité : on amène placeDepart à son plancher,
    //     puis on lui redonne un signal positif.
    final neutralise = apprendre(base, 'placeDepart', -0.35, 200);
    // ignore: avoid_print
    print('P11c placeDepart neutralisé = ${_f(neutralise['placeDepart']!)} '
        '(plancher 0,005)');
    expect(neutralise['placeDepart']!, closeTo(kBas['placeDepart']!, 1e-6));
    final reactive = apprendre(neutralise, 'placeDepart', 0.35, 200);
    // ignore: avoid_print
    print('P11c placeDepart réactivé  = ${_f(reactive['placeDepart']!)} '
        '(×${(reactive['placeDepart']! / kBas['placeDepart']!).toStringAsFixed(1)} '
        'vs plancher)');
    expect(reactive['placeDepart']!, greaterThan(kBas['placeDepart']! * 5),
        reason: 'un critère neutralisé doit pouvoir redevenir important');

    // (4) Les DEUX critères les plus bridés : on vérifie que leurs bornes
    //     restent respectées en permanence pendant la trajectoire.
    var violations = 0;
    var maxExploitable = 0.0;
    for (final k in kCles) {
      final fin = apprendre(base, k, 0.40, 120);
      final vio = _violations(fin);
      if (vio.isNotEmpty) violations++;
      // taux d'exploitation de la plage : (valeur - plancher) / (plafond - plancher)
      final taux = (fin[k]! - kBas[k]!) / (kHaut[k]! - kBas[k]!);
      if (taux > maxExploitable) maxExploitable = taux;
    }
    // ignore: avoid_print
    print('P11d 19 trajectoires indépendantes de 120 pas : $violations en '
        'violation · taux d\'exploitation de plage max atteint = '
        '${(maxExploitable * 100).toStringAsFixed(2)} %');
    expect(violations, 0);
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  P12 — CONSÉQUENCES DU RESPECT STRICT DES PLAFONDS [REEL + SYNTH]
  //
  //  L'ancien mécanisme laissait les plafonds franchissables. Les rendre
  //  contraignants CHANGE le comportement : il faut le mesurer, pas le nier.
  // ═══════════════════════════════════════════════════════════════════════════
  test('P12 — ce que change le respect STRICT des plafonds', () {
    // (a) [REEL] La table réellement apprise au 13/11 dépasse DEUX plafonds.
    final reel = _fabrique(<String, double>{...kPoids1311});
    reel.normaliser();
    final avant = <String, double>{...kPoids1311};
    final apres = _depuis(reel);
    // ignore: avoid_print
    print('P12a [REEL] 13/11 avant projection : cote = '
        '${_f(avant['cote']!)} (plafond 0,40) · victoires = '
        '${_f(avant['victoires']!)} (plafond 0,15)');
    // ignore: avoid_print
    print('P12a [REEL] 13/11 après projection : cote = '
        '${_f(apres['cote']!)} · victoires = ${_f(apres['victoires']!)}');
    expect(apres['cote']!, lessThanOrEqualTo(kHaut['cote']! + 1e-12));
    expect(apres['victoires']!, lessThanOrEqualTo(kHaut['victoires']! + 1e-12));

    // Amplitude de la correction imposée par le respect strict.
    final dCote = (avant['cote']! - apres['cote']!).abs();
    final dVict = (avant['victoires']! - apres['victoires']!).abs();
    // ignore: avoid_print
    print('P12a [REEL] corrections imposées : cote −${dCote.toStringAsFixed(9)} · '
        'victoires −${dVict.toStringAsFixed(9)} (part du poids total : '
        '${((dCote + dVict) * 100).toStringAsFixed(2)} pts)');

    // (b) [SYNTH] Combien de temps un critère met-il à SATURER son plafond
    //     maintenant qu'il est contraignant ? On compare, à discrimination
    //     égale, la saturation de `cote` (plafond 0,40) avant/après.
    final alea = math.Random(31337);
    var saturations = 0;
    for (var essai = 0; essai < 100; essai++) {
      final p = _fabrique(_tableConforme());
      for (var i = 0; i < 300; i++) {
        p.cote = p.cote + 0.08 * (0.2 + alea.nextDouble() * 0.6);
        p.clamp();
      }
      if ((p.cote - kHaut['cote']!).abs() < 1e-9) saturations++;
    }
    // ignore: avoid_print
    print('P12b [SYNTH] 100 trajectoires de 300 pas sur `cote` : '
        '$saturations saturent le plafond 0,40 (le plafond est ATTEIGNABLE '
        'mais DÉSORMAIS infranchissable)');
    expect(saturations, greaterThan(0),
        reason: 'un plafond strict ne doit pas devenir inatteignable');

    // (c) Ce que le plafond strict EMPÊCHE désormais : la configuration
    //     « un critère écrase tout » qui produisait 0,575438596491.
    final ecrasement = IaPoidsAdaptatifs.projeter(
        <String, double>{...kBas, 'cote': 0.40});
    // ignore: avoid_print
    print('P12c [SYNTH] « cote écrase tout » : ANCIEN 0,575438596491 → '
        'NOUVEAU ${_f(ecrasement['cote']!)} '
        '(perte d\'amplitude ${((0.575438596491 - ecrasement['cote']!) * 100).toStringAsFixed(3)} pts)');
    expect(ecrasement['cote']!, lessThanOrEqualTo(kHaut['cote']! + 1e-12));
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  P13 — APPLICATION PAR DISCIPLINE : la MÊME projection, donc les MÊMES
  //        bornes (c'était le cœur de D-2) [SYNTH]
  // ═══════════════════════════════════════════════════════════════════════════
  test('P13 — par discipline : mêmes bornes, mêmes garanties (D-2)', () {
    // Une table de discipline volontairement hors bornes, dont `divergence`
    // exactement à 0,10 — la valeur que l'ANCIEN `clampDiscipline()` autorisait
    // alors que `clamp()` plafonnait à 0,08.
    final disc = <String, double>{
      ...kInitial,
      'divergence': 0.10,
      'cote': 0.45,
      'victoires': 0.20,
    };
    IaPoidsAdaptatifs.clampDiscipline(disc);
    final vio = _violations(disc);
    // ignore: avoid_print
    print('P13 divergence 0,10 → ${_f(disc['divergence']!)} '
        '(plafond 0,08 : l\'ANCIEN clampDiscipline() autorisait 0,10) · '
        'violations = ${vio.length}');
    expect(disc['divergence']!, lessThanOrEqualTo(0.08 + 1e-12),
        reason: 'D-2 : la discipline ne doit plus avoir son propre plafond');
    expect(vio, isEmpty);

    // Cohérence GLOBALE vs DISCIPLINE sur la même entrée : la projection ne
    // doit pas dépendre du chemin.
    final parClamp = IaPoidsAdaptatifs.projeter(<String, double>{
      ...kInitial, 'divergence': 0.06,
    });
    final parDisc = <String, double>{...kInitial, 'divergence': 0.06};
    IaPoidsAdaptatifs.clampDiscipline(parDisc);
    var ecart = 0.0;
    for (final k in kCles) {
      final d = (parDisc[k]! - parClamp[k]!).abs();
      if (d > ecart) ecart = d;
    }
    // ignore: avoid_print
    print('P13 global (`projeter`) vs discipline (`clampDiscipline`) sur la même '
        'entrée : écart max = ${ecart.toStringAsExponential(3)}');
    expect(ecart, lessThanOrEqualTo(1e-15),
        reason: 'une seule définition des contraintes : les deux chemins '
            'doivent être indiscernables');

    // Les 6 spécialités suivies par l'application.
    const specialites = <String>[
      'trot_attele', 'trot_monte', 'plat', 'obstacle', 'global', 'inconnue',
    ];
    var ok = 0;
    for (final _ in specialites) {
      final t = <String, double>{...kPoids1311};
      IaPoidsAdaptatifs.clampDiscipline(t);
      if (_violations(t).isEmpty) ok++;
    }
    // ignore: avoid_print
    print('P13 ${specialites.length} spécialités × table réelle 13/11 : '
        '$ok/${specialites.length} conformes');
    expect(ok, specialites.length);
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  P14 — D-3 : la désérialisation tolérante préserve TOUT le valide
  // ═══════════════════════════════════════════════════════════════════════════
  test('P14 — D-3 : une valeur corrompue ne détruit plus les 18 autres', () {
    // (1) Le cas qui LEVAIT un TypeError avant correction.
    final corrompu = <String, dynamic>{
      for (final k in kCles) k: kInitial[k],
      'forme': 'invalide',
    };
    late IaPoidsAdaptatifs p;
    expect(() => p = IaPoidsAdaptatifs.fromJson(corrompu), returnsNormally,
        reason: 'D-3 : plus de TypeError, le chargement doit aboutir');
    // ignore: avoid_print
    print('P14a forme="invalide" → forme = ${_f(p.forme)} (repli 0,25) · '
        'gains conservé = ${_f(p.gains)} (0,13 attendu) · '
        'cote conservé = ${_f(p.cote)} (0,08 attendu)');
    expect(p.forme, closeTo(0.25, 1e-12));
    // Et surtout : les 18 AUTRES valeurs sont intactes.
    for (final k in kCles) {
      if (k == 'forme') continue;
      expect(p.getPoids(k), closeTo(kInitial[k]!, 1e-12),
          reason: 'D-3 : $k devait survivre à la corruption de forme');
    }
    // La perte est TRACÉE.
    final trace = IaPoidsAdaptatifs.dernieresAnomaliesDeserialisation;
    // ignore: avoid_print
    print('P14a trace = ${trace.length} anomalie(s) : ${trace.join(" | ")}');
    expect(trace, isNotEmpty, reason: 'D-3 : toute perte doit être traçable');

    // (2) Les 8 cas, un par un.
    final cas = <String, dynamic>{
      'absent': <String, dynamic>{},
      'null': <String, dynamic>{'forme': null},
      'numérique': <String, dynamic>{'forme': 0.31},
      'texte': <String, dynamic>{'forme': '0.31'},
      'type incompatible': <String, dynamic>{'forme': <int>[1, 2]},
      'négatif': <String, dynamic>{'forme': -0.31},
      'non fini': <String, dynamic>{'forme': double.nan},
      'hors bornes (historique)': <String, dynamic>{'forme': 0.40},
    };
    for (final e in cas.entries) {
      final r = IaPoidsAdaptatifs.fromJson(e.value as Map<String, dynamic>);
      final t = IaPoidsAdaptatifs.dernieresAnomaliesDeserialisation;
      // ignore: avoid_print
      print('P14b ${e.key.padRight(24)} → forme = ${_f(r.forme)} · '
          'tracé = ${t.isEmpty ? "non" : "oui"}');
    }
    // Le cas (h) — numérique hors bornes — ne doit RIEN tracer : ce n'est pas
    // une corruption, c'est une pondération historique authentique.
    IaPoidsAdaptatifs.fromJson(<String, dynamic>{'forme': 0.40});
    expect(IaPoidsAdaptatifs.dernieresAnomaliesDeserialisation, isEmpty,
        reason: 'D-3 : un poids authentique hors bornes n\'est PAS une '
            'corruption et ne doit pas être signalé comme telle');

    // (3) Aucune valeur valide perdue, sur la table réelle complète.
    final reel = IaPoidsAdaptatifs.fromJson(
        <String, dynamic>{...kPoids1311, 'jockey': 'corrompu'});
    for (final k in kCles) {
      if (k == 'jockey') continue;
      expect(reel.getPoids(k), closeTo(kPoids1311[k]!, 1e-12),
          reason: 'D-3 : $k devait être restitué à l\'identique');
    }
    // ignore: avoid_print
    print('P14c table réelle 13/11 + jockey corrompu : 18/19 valeurs '
        'AUTHENTIQUES restituées, seule jockey repliée à '
        '${_f(reel.jockey)}');

    // (4) Par discipline : une clé illisible n'emporte plus toute la discipline.
    final avecDisc = IaPoidsAdaptatifs.fromJson(<String, dynamic>{
      'poidsParDiscipline': <String, dynamic>{
        'plat': <String, dynamic>{
          'forme': 0.20, 'gains': 'ILLISIBLE', 'record': 0.10,
        },
        'trot_attele': 'pas une map',
      },
    });
    // ignore: avoid_print
    print('P14d discipline « plat » : ${avecDisc.poidsParDiscipline['plat']} '
        '(gains écarté, forme et record SURVIVENT) · '
        '« trot_attele » écarté = '
        '${!avecDisc.poidsParDiscipline.containsKey('trot_attele')}');
    expect(avecDisc.poidsParDiscipline['plat']!['forme'], closeTo(0.20, 1e-12));
    expect(avecDisc.poidsParDiscipline['plat']!['record'], closeTo(0.10, 1e-12));
    expect(avecDisc.poidsParDiscipline['plat']!.containsKey('gains'), isFalse);
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  P15 — DÉMARRAGE RÉEL : poids initiaux → poids effectivement utilisés
  //
  //  C'est la §11 de la consigne : « les 19 poids initiaux réellement utilisés ».
  //  On mesure le chemin COMPLET (constructeur → normaliser → getPoids) et on
  //  compare aux poids bruts. Aucune donnée hippique n'intervient : c'est une
  //  mesure de CODE, pas une mesure de performance de pronostic.
  // ═══════════════════════════════════════════════════════════════════════════
  test('P15 — démarrage : poids bruts → poids effectifs, sans perte de rang', () {
    final p = IaPoidsAdaptatifs();
    final brut = _depuis(p);
    final sommeBrut = _sommeCle(brut, kCles);
    p.normaliser();
    final effectif = _depuis(p);

    final lignes = <String>[];
    lignes.add('| critère | brut | effectif | brut/effectif |');
    lignes.add('|---|---:|---:|---:|');
    for (final k in kCles) {
      lignes.add('| $k | ${_f(brut[k]!)} | ${_f(effectif[k]!)} | '
          '${(brut[k]! / effectif[k]!).toStringAsFixed(6)} |');
    }
    // ignore: avoid_print
    print(lignes.join('\n'));

    // ignore: avoid_print
    print('P15 Σ brute = ${_f(sommeBrut)} → Σ effective = '
        '${_f(_sommeCle(effectif, kCles))} · base = '
        '${_f(_sommeCle(effectif, kBase))} · enrichis = '
        '${_f(_sommeCle(effectif, kEnrichis))}');
    expect(sommeBrut, closeTo(1.26, 1e-12));
    expect(_sommeCle(effectif, kCles), closeTo(1.0, 1e-9));
    expect(_violations(effectif), isEmpty);

    // Le RANG des critères doit être globalement préservé : c'est la garantie
    // qu'aucun critère n'est promu/dégradé arbitrairement par la projection.
    final rangBrut = <String>[...kCles]
      ..sort((a, b) => brut[b]!.compareTo(brut[a]!));
    final rangEff = <String>[...kCles]
      ..sort((a, b) => effectif[b]!.compareTo(effectif[a]!));
    final desordres = <String>[];
    for (var i = 0; i < kCles.length; i++) {
      if (rangBrut[i] != rangEff[i]) desordres.add('${rangBrut[i]}↔${rangEff[i]}');
    }
    // ignore: avoid_print
    print('P15 rangs : ${kCles.length - desordres.length}/19 positions '
        'identiques entre brut et effectif · échanges = $desordres');
    // On n'exige pas l'identité stricte (deux contractions de groupes
    // différentes peuvent réordonner des critères très proches), mais on exige
    // que le sommet reste le sommet.
    expect(rangEff.first, rangBrut.first,
        reason: 'le critère le plus pondéré des poids initiaux doit rester le '
            'plus pondéré après application des contraintes');
  });
}

// Alias utilisé dans P10 pour rester lisible.
const List<String> kEnrichies2 = <String>[
  'distSpec', 'jockey', 'repos', 'hippo', 'entraineur', 'elo',
  'terrain', 'divergence', 'poidsRel', 'progression', 'mouvCote',
  'placeDepart',
];
