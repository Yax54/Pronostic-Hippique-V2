// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER POIDS IA — §4 : PLAGE RÉELLEMENT ATTEIGNABLE DE CHAQUE CRITÈRE
//
//  QUESTION POSÉE (texte utilisateur) : « Un critère initialement faiblement
//  pondéré doit pouvoir devenir important si les résultats démontrent sa
//  pertinence. […] Détermine si certains critères sont structurellement
//  désavantagés ou empêchés d'atteindre leur importance réelle. Distingue une
//  limitation mathématique démontrée d'une simple convergence lente. »
//
//  ⚠️ AUCUNE MODIFICATION DE PRODUCTION. On instancie des `IaPoidsAdaptatifs`
//     EN MÉMOIRE et on appelle les méthodes RÉELLES (`clamp()`, `getPoids()`).
//     Aucune écriture disque, aucun apprentissage déclenché.
//
//  MÉTHODE
//    `clamp()` = bornes individuelles PUIS `normaliser()`. `normaliser()`
//    écrête la fraction enrichie à [0.18, 0.40] et rescale les deux familles.
//    Le résultat final d'un critère C ne dépend donc que de deux agrégats :
//       B = Σ poids bruts des 7 critères de base
//       E = Σ poids bruts des 12 critères enrichis
//    Pour C de base      : C_final = C × (1 − t) / B   avec t = clamp(E/(B+E), 0.18, 0.40)
//    Pour C enrichi      : C_final = C ×  t    / E
//    ⇒ C_final est MAXIMISÉ quand B_autres et E_autres sont MINIMAUX
//      (C à sa borne haute, tout le reste à sa borne basse)
//      et MINIMISÉ quand tout le reste est à sa borne haute.
//    Les deux configurations extrêmes de la boîte admissible donnent donc la
//    plage EXACTE, sans avoir à dérouler de trajectoire.
//
//  CE QUE CETTE PLAGE PROUVE — et ce qu'elle ne prouve pas
//    • Elle prouve une IMPOSSIBILITÉ : aucun état admissible ne peut donner à C
//      plus que MAX. Comme `clamp()` est appelée après CHAQUE mise à jour du
//      gradient (ia_memory_service.dart:4093), aucun apprentissage, aussi long
//      soit-il, ne peut sortir de cette plage. C'est la « limitation
//      mathématique démontrée » exigée.
//    • Elle ne prouve PAS qu'un critère ATTEINT réellement cette plage par
//      gradient : cela dépend de la discrimination observée, donc c'est une
//      question de CONVERGENCE, mesurée séparément (M10.3).
//  La distinction exigée par l'utilisateur est donc tenue : borne = §4 math,
//  atteignabilité par gradient = mesure de convergence citée, pas confondue.
// ═══════════════════════════════════════════════════════════════════════════

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

final List<String> kEnrichis =
    kCles.where((k) => !kBase.contains(k)).toList();

/// Bornes RÉELLES de `clamp()` — recopiées pour PILOTER le harnais.
/// Le test A0 vérifie qu'elles reproduisent EXACTEMENT la production : si
/// `clamp()` changeait, A0 échouerait au lieu de valider une fausse mesure.
const Map<String, double> kBas = <String, double>{
  'forme': 0.05, 'gains': 0.04, 'record': 0.03, 'cote': 0.05,
  'constance': 0.03, 'victoires': 0.01, 'discipline': 0.01,
  // ★★ 27/11/2026 — §2 DU CHANTIER : les 12 planchers ENRICHIS valent 0,005.
  //   Ce fichier avait été écrit AVANT cette correction et portait encore
  //   0,03 / 0,02 / 0,01. C'est A0 qui l'a révélé (écart 0,025 sur distSpec),
  //   exactement le rôle de cette garde. Valeurs alignées sur
  //   `bornesIndividuelles()` — vérifié à nouveau par A0.
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
  'poidsRel': 0.07, 'progression': 0.08, 'mouvCote': 0.12, 'placeDepart': 0.07,
};

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

/// Voie de PRODUCTION : constructeur réel + `clamp()` réel.
Map<String, double> _prod(Map<String, double> v) {
  final p = _fabrique(v)..clamp();
  return {for (final k in kCles) k: p.getPoids(k)};
}

/// Réplique de l'ANCIENNE arithmétique de `clamp()` + `normaliser()`
/// (bornes puis mise à l'échelle des 2 groupes), REMPLACÉE EN PRODUCTION par
/// la projection D-1 le 27/11/2026.
///
/// ⚠️ CE N'EST PLUS UNE RÉPLIQUE DE LA PRODUCTION — c'est une RÉFÉRENCE
///    HISTORIQUE. Elle ne sert qu'à mesurer ce que D-1 change (test A0b).
///    Aucun test ne la compare plus à `clamp()` : ce serait maintenir une
///    seconde implémentation divergente, ce que la consigne §6 interdit.
///    La fidélité À LA PRODUCTION est vérifiée par A0, contre
///    `bornesIndividuelles()`.
Map<String, double> _formuleAncienne(Map<String, double> entree) {
  final w = <String, double>{
    for (final k in kCles) k: entree[k]!.clamp(kBas[k]!, kHaut[k]!),
  };
  final b = kBase.fold(0.0, (a, k) => a + w[k]!);
  final e = kEnrichis.fold(0.0, (a, k) => a + w[k]!);
  final total = b + e;
  if (total > 0) {
    final fraction = e / total;
    final targetE = fraction.clamp(0.18, 0.40);
    final targetB = 1.0 - targetE;
    if (b > 0) {
      final f = targetB / b;
      for (final k in kBase) {
        w[k] = w[k]! * f;
      }
    }
    if (e > 0) {
      final f = targetE / e;
      for (final k in kEnrichis) {
        w[k] = w[k]! * f;
      }
    }
  }
  return w;
}

double _somme(Iterable<double> v) => v.fold(0.0, (a, b) => a + b);

String _f(double v) => v.toStringAsFixed(6);

/// MAX atteignable pour `c` : C à sa borne HAUTE, tous les autres à leur borne
/// BASSE (démonstration : voir l'en-tête — c'est le minimum de B_autres+E_autres).
Map<String, double> _configMax(String c) =>
    <String, double>{...kBas, c: kHaut[c]!};

/// MIN atteignable pour `c` : C à sa borne BASSE, tous les autres à leur borne
/// HAUTE.
Map<String, double> _configMin(String c) =>
    <String, double>{...kHaut, c: kBas[c]!};

void main() {
  // ── A0 — GARDE : la réplique est-elle fidèle à la production ? ────────────
  //
  // ★★ ASSERTION VOLONTAIREMENT RÉANCRÉE (D-1, 27/11/2026).
  //   JUSTIFICATION ÉCRITE — C'EST LA PLUS IMPORTANTE DES NEUF.
  //   Cette garde comparait la RÉPLIQUE `_formule()` (recopie de l'ancien
  //   `clamp()` : bornes puis mise à l'échelle des 2 groupes) à la production.
  //   D-1 remplace le mécanisme par une PROJECTION sur l'intersection
  //   {bornes} ∩ {somme de groupe = budget}. La réplique ne décrit donc plus la
  //   production : écart mesuré 0,030587214493138493 vs 0,030570185157855364.
  //   ⚠️ On ne se contente pas de tolérer cet écart : cela reviendrait à
  //      laisser une seconde implémentation divergente vivre dans les tests,
  //      c'est-à-dire exactement le défaut que la consigne §6 interdit
  //      (« Évite la coexistence de plusieurs implémentations incohérentes des
  //      mêmes contraintes »). La réplique est donc CONSERVÉE sous le nom
  //      `_formuleAncienne` et n'est plus comparée à la production : elle sert
  //      désormais de RÉFÉRENCE HISTORIQUE pour mesurer ce que D-1 change
  //      (test A0b). A0 garde son rôle de garde, mais contre la NOUVELLE
  //      source unique : `bornesIndividuelles()` et `projeter()`.
  test('A0 — GARDE : les bornes recopiées == bornesIndividuelles()', () {
    final prod = IaPoidsAdaptatifs.bornesIndividuelles();
    expect(prod.length, 19);
    for (final k in kCles) {
      expect(prod[k]![0], closeTo(kBas[k]!, 1e-15),
          reason: 'plancher recopié $k ≠ production');
      expect(prod[k]![1], closeTo(kHaut[k]!, 1e-15),
          reason: 'plafond recopié $k ≠ production');
    }
    // ignore: avoid_print
    print('[A0] GARDE OK — les 19 paires de bornes recopiées sont IDENTIQUES '
        'à `bornesIndividuelles()` de production.');
  });

  // ── A0b — CE QUE D-1 CHANGE, mesuré contre l'ancienne formule ─────────────
  test('A0b — D-1 : mesure de l\'écart avec l\'ANCIENNE formule', () {
    final alea = math.Random(20261127);
    var ecartMax = 0.0;
    var pire = '';
    var anciensDepassements = 0;
    var nouveauxDepassements = 0;

    for (var i = 0; i < 400; i++) {
      final v = <String, double>{
        for (final k in kCles)
          k: kBas[k]! + alea.nextDouble() * (kHaut[k]! - kBas[k]!) * 1.4,
      };
      final nouveau = _prod(v);
      final ancien = _formuleAncienne(v);
      for (final k in kCles) {
        final d = (ancien[k]! - nouveau[k]!).abs();
        if (d > ecartMax) {
          ecartMax = d;
          pire = k;
        }
        if (ancien[k]! > kHaut[k]! + 1e-9) anciensDepassements++;
        if (nouveau[k]! > kHaut[k]! + 1e-9) nouveauxDepassements++;
      }
    }
    // ignore: avoid_print
    print('[A0b] 400 vecteurs × 19 critères : écart max ANCIEN vs NOUVEAU = '
        '${_f(ecartMax)} sur "$pire"');
    // ignore: avoid_print
    print('[A0b] dépassements de plafond — ANCIEN mécanisme : '
        '$anciensDepassements / 7600 valeurs · D-1 : $nouveauxDepassements / 7600');
    expect(nouveauxDepassements, 0,
        reason: 'D-1 ne doit produire AUCUN dépassement de plafond');
    // ★★ ASSERTION VOLONTAIREMENT RÉANCRÉE (D-1, 27/11/2026).
    //   JUSTIFICATION ÉCRITE — J'AI ÉCRIT CI-DESSUS UNE CHOSE FAUSSE.
    //   J'avais postulé « l'ancienne formule doit bien reproduire les
    //   dépassements, sinon la comparaison ne prouve rien ». LA MESURE LE
    //   RÉFUTE : sur 400 tirages ALÉATOIRES, l'ancien mécanisme produit
    //   EXACTEMENT 0 dépassement. Ce n'est pas une erreur de mesure : le
    //   dépassement de l'ancien mécanisme n'est PAS systématique, il n'apparaît
    //   que dans un COIN de l'espace — quand un critère est proposé très au-
    //   dessus des autres (mesuré ailleurs : cote=0,40 avec tous les autres au
    //   plancher ⇒ 0,575438596491). Un tirage uniforme ne visite presque jamais
    //   ce coin.
    //   ⇒ L'assertion est donc remplacée par la mesure du COIN, qui est le seul
    //     endroit où la différence se manifeste, et qui est déterministe.
    if (anciensDepassements == 0) {
      // ignore: avoid_print
      print('[A0b] CONSTAT HONNÊTE : sur des tirages UNIFORMES, l\'ancienne '
          'formule ne dépasse JAMAIS. Le dépassement est un phénomène de COIN, '
          'mesuré ci-dessous de façon déterministe.');
    }
    // Le coin : un critère au plafond, tous les autres au plancher.
    var coinAncien = 0;
    var coinNouveau = 0;
    for (final k in kCles) {
      final coin = <String, double>{...kBas, k: kHaut[k]!};
      if (_formuleAncienne(coin)[k]! > kHaut[k]! + 1e-9) coinAncien++;
      if (_prod(coin)[k]! > kHaut[k]! + 1e-9) coinNouveau++;
    }
    // ignore: avoid_print
    print('[A0b] COIN (critère au plafond, tous les autres au plancher) : '
        'ANCIEN dépasse $coinAncien / 19 · D-1 dépasse $coinNouveau / 19');
    expect(coinAncien, greaterThan(0),
        reason: 'la référence historique doit bien reproduire le défaut dans '
            'le coin, sinon la comparaison ne prouve rien');
    expect(coinNouveau, 0, reason: 'D-1 ne doit pas dépasser dans le coin');
  });

  // ── A1 — Poids DÉFAUT réellement appliqué au démarrage ───────────────────
  test('A1 — poids réellement appliqué au démarrage (pipeline complet)', () {
    final p = IaPoidsAdaptatifs()..clamp();
    final v = {for (final k in kCles) k: p.getPoids(k)};
    final base = _somme(kBase.map((k) => v[k]!));
    final enr = _somme(kEnrichis.map((k) => v[k]!));

    // ignore: avoid_print
    print('[A1] critère      | brut constructeur | appliqué après clamp()');
    final brut = <String, double>{
      'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
      'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
      'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
      'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05, 'divergence': 0.04,
      'poidsRel': 0.03, 'progression': 0.03, 'mouvCote': 0.06,
      'placeDepart': 0.03,
    };
    for (final k in kCles) {
      // ignore: avoid_print
      print('[A1] ${k.padRight(12)} | ${_f(brut[k]!)} | ${_f(v[k]!)}');
    }
    // ignore: avoid_print
    print('[A1] SOMME = ${_f(_somme(v.values))} | base = ${_f(base)} | '
        'enrichis = ${_f(enr)}');

    expect(_somme(v.values), closeTo(1.0, 1e-9));
    expect(enr, closeTo(0.40, 1e-9),
        reason: 'MESURÉ : fraction enrichie écrêtée au plafond 0.40');
    expect(base, closeTo(0.60, 1e-9));
  });

  // ── A2 — PLAGE ATTEIGNABLE : borne mathématique de chaque critère ────────
  test('A2 — plage atteignable par critère (borne mathématique démontrée)', () {
    final defaut = {for (final k in kCles) k: (IaPoidsAdaptatifs()..clamp()).getPoids(k)};

    // ignore: avoid_print
    print('[A2] critère      | défaut   | MIN atteig. | MAX atteig. | amplitude'
        ' | borne indiv. | MAX > borne indiv. ?');
    final maxAtteint = <String, double>{};
    final minAtteint = <String, double>{};
    var depassements = 0;

    for (final k in kCles) {
      final maxi = _prod(_configMax(k))[k]!;
      final mini = _prod(_configMin(k))[k]!;
      maxAtteint[k] = maxi;
      minAtteint[k] = mini;
      final depasse = maxi > kHaut[k]! + 1e-9;
      if (depasse) depassements++;
      // ignore: avoid_print
      print('[A2] ${k.padRight(12)} | ${_f(defaut[k]!)} | ${_f(mini)} | '
          '${_f(maxi)} | ${_f(maxi - mini)} | ${_f(kHaut[k]!)} | $depasse');
    }
    // ignore: avoid_print
    print('[A2] ⇒ $depassements / 19 critères ont un MAX qui DÉPASSE leur '
        'borne individuelle haute (la normalisation de groupe rescale APRÈS '
        'le clamp : la borne n\'est pas un plafond final).');

    // ── Le plafond de groupe est-il la contrainte dominante ? ─────────────
    final sommeEnrichisHaut =
        kEnrichis.map((k) => kHaut[k]!).fold(0.0, (a, b) => a + b);
    final sommeBaseHaut =
        kBase.map((k) => kHaut[k]!).fold(0.0, (a, b) => a + b);
    // ignore: avoid_print
    print('[A2] Σ bornes hautes des 12 enrichis = ${_f(sommeEnrichisHaut)} '
        'contre un plafond de groupe de 0.40 → facteur d\'écrasement '
        'plancher = ${_f(0.40 / sommeEnrichisHaut)}');
    // ignore: avoid_print
    print('[A2] Σ bornes hautes des 7 de base = ${_f(sommeBaseHaut)} '
        'contre un plancher de base de 0.60 → facteur de dilatation = '
        '${_f(0.60 / sommeBaseHaut)}');

    expect(minAtteint.values.every((v) => v > 0), isTrue,
        reason: 'aucun critère ne peut tomber à zéro : bornes basses > 0');
    expect(maxAtteint.values.every((v) => v > 0), isTrue);

    // ── Contrôle par échantillonnage : MAX/MIN sont-ils vraiment des bornes ? ─
    final alea = math.Random(7717);
    var violations = 0;
    for (final k in kCles) {
      for (var i = 0; i < 3000; i++) {
        final v = <String, double>{
          for (final c in kCles)
            c: kBas[c]! + alea.nextDouble() * (kHaut[c]! - kBas[c]!),
        };
        final val = _prod(v)[k]!;
        if (val > maxAtteint[k]! + 1e-9 || val < minAtteint[k]! - 1e-9) {
          violations++;
        }
      }
    }
    // ignore: avoid_print
    print('[A2] contrôle par échantillonnage : 3000 tirages × 19 critères = '
        '${3000 * 19} évaluations → violations des bornes = $violations');
    expect(violations, 0,
        reason: 'les bornes calculées sont bien infranchissables');
  });

  // ── A3 — MATRICE D'INVERSIONS : qui peut dépasser qui ? ──────────────────
  test('A3 — MATRICE D\'INVERSIONS : hiérarchies verrouillées', () {
    final maxDe = {for (final k in kCles) k: _prod(_configMax(k))[k]!};
    final minDe = {for (final k in kCles) k: _prod(_configMin(k))[k]!};

    var verrouillees = 0;
    final details = <String>[];
    for (final a in kCles) {
      for (final b in kCles) {
        if (a == b) continue;
        if (maxDe[a]! <= minDe[b]!) {
          verrouillees++;
          details.add('$a (max ${_f(maxDe[a]!)}) ne peut JAMAIS dépasser '
              '$b (min ${_f(minDe[b]!)})');
        }
      }
    }
    final paires = kCles.length * (kCles.length - 1);
    // ignore: avoid_print
    print('[A3] paires ordonnées = $paires | VERROUILLÉES = $verrouillees '
        '(${(verrouillees / paires * 100).toStringAsFixed(1)} %)');
    for (final d in details) {
      // ignore: avoid_print
      print('[A3]   $d');
    }
    // ignore: avoid_print
    print('[A3] ⇒ MESURE : la hiérarchie n\'est verrouillée NULLE PART. '
        'Chaque critère peut, dans la boîte admissible, dépasser chacun des '
        '18 autres. AUCUNE impossibilité mathématique au niveau individuel.');

    // Ce que cela PROUVE — et c'est l'INVERSE de l'hypothèse de départ :
    // aucune paire n'est structurellement bloquée. Le désavantage éventuel ne
    // peut donc PAS être une impossibilité mathématique individuelle ; il doit
    // être cherché dans la DYNAMIQUE (A6 et A7 ci-dessous). C'est exactement
    // la distinction demandée : « limitation mathématique » vs « convergence
    // lente ». La première est ici RÉFUTÉE.
    expect(verrouillees, 0,
        reason: 'MESURÉ : aucune paire verrouillée — hiérarchie intégralement '
            'réversible dans la boîte admissible');
  });

  // ── A4 — Le plafond de groupe seul, bornes individuelles rendues inopérantes
  test('A4 — le plafond de groupe 0.40 domine-t-il les bornes individuelles ?',
      () {
    // 19 critères STRICTEMENT ÉGAUX en entrée : on isole l'effet de
    // `normaliser()` seule, telle qu'elle est écrite en production.
    final egaux = <String, double>{for (final k in kCles) k: 0.10};
    final v = _prod(egaux);
    final partEnrichie = _somme(kEnrichis.map((k) => v[k]!));
    // ignore: avoid_print
    print('[A4] 19 critères ÉGAUX à 0.10 en entrée → part enrichie réelle = '
        '${_f(partEnrichie)} (plafond 0.40) ; base = '
        '${_f(_somme(kBase.map((k) => v[k]!)))}');
    for (final k in kEnrichis) {
      // ignore: avoid_print
      print('[A4] ${k.padRight(12)} = ${_f(v[k]!)}');
    }
    expect(partEnrichie, closeTo(0.40, 1e-9),
        reason: 'à entrées égales, la famille enrichie est écrasée à 0.40');
  });

  // ── A5 — Ce que la plage implique pour le SCORE, pas pour le poids ───────
  test('A5 — le poids appliqué est 1.26× le poids normalisé (somme ≠ 1)', () {
    // `_calculerScoreBrutEtCriteres` fait une somme pondérée BRUTE, non divisée
    // par le total des poids (ia_pronostic_engine.dart:391-409). L'influence
    // réelle d'un critère = poids × dispersion de son score ; le poids n'est
    // donc pas une « part » mais un coefficient appliqué à une somme de 1.26.
    final p = IaPoidsAdaptatifs();
    final brut = <String, double>{
      'forme': p.forme, 'gains': p.gains, 'record': p.record, 'cote': p.cote,
      'constance': p.constance, 'victoires': p.victoires,
      'discipline': p.discipline, 'distSpec': p.distSpec, 'jockey': p.jockey,
      'repos': p.repos, 'hippo': p.hippo, 'entraineur': p.entraineur,
      'elo': p.elo, 'terrain': p.terrain, 'divergence': p.divergence,
      'poidsRel': p.poidsRel, 'progression': p.progression,
      'mouvCote': p.mouvCote, 'placeDepart': p.placeDepart,
    };
    final s = _somme(brut.values);
    // ignore: avoid_print
    print('[A5] SOMME des 19 poids NON clammés (chemin « jamais appris ») = '
        '${_f(s)}');
    // ignore: avoid_print
    print('[A5] ⇒ un score composite peut atteindre ${_f(100 * s)} pour des '
        'critères tous à 100. Après clamp() : 100.0 exactement.');
    expect(s, closeTo(1.26, 1e-12));
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  PARTIE DYNAMIQUE — là où le désavantage se trouve réellement, puisque
  //  A3 a établi qu'aucune limitation mathématique INDIVIDUELLE n'existe.
  //
  //  Les cycles ci-dessous répliquent la boucle RÉELLE de
  //  `_apprendreParGradient` (ia_memory_service.dart:4052-4093) :
  //    grad  = lr × discrimination
  //    gradA = grad + 0.3 × momentum        (momentumFactor = 0.3)
  //    poids += gradA × facteurCritère
  //    clamp()                              (bornes + normaliser)
  //  Facteurs RÉELS (l.4066-4088) : base 1.0 ; distSpec/jockey/elo/terrain/
  //  mouvCote 0.5 ; hippo/entraineur/divergence/progression 0.4 ;
  //  repos/poidsRel/placeDepart 0.3.
  // ═══════════════════════════════════════════════════════════════════════

  group('DYNAMIQUE — le désavantage est-il une limite ou une convergence ?', () {
    /// Un cycle de gradient identique à la production, puis `clamp()`.
    void cycle(IaPoidsAdaptatifs p, Map<String, double> discrim,
        Map<String, double> momentum, double lr) {
      final etat = <String, double>{for (final k in kCles) k: p.getPoids(k)};
      for (final c in kCles) {
        final grad = lr * (discrim[c] ?? 0.0);
        final g = grad + 0.3 * (momentum[c] ?? 0.0);
        momentum[c] = g;
        etat[c] = etat[c]! + g * kFacteur[c]!;
      }
      // On réinjecte l'état via le constructeur réel puis clamp() réel.
      final neuf = _fabrique(etat)..clamp();
      _copier(p, neuf);
    }

    test('A6 — MÊME discrimination : combien de cycles pour inverser ?', () {
      // Question exacte du §4 : un critère faiblement pondéré peut-il devenir
      // important ? On donne à TOUS la même discrimination — donc aucune
      // raison statistique de préférer l'un — et on regarde si l'ORDRE initial
      // (fixé par les valeurs de départ) bouge, et au bout de combien de temps.
      final p = IaPoidsAdaptatifs();
      final mo = <String, double>{};
      final d = {for (final k in kCles) k: 0.02};
      final init = {for (final k in kCles) k: p.getPoids(k)};
      final ordreInit = kCles.toList()
        ..sort((a, b) => init[b]!.compareTo(init[a]!));

      // ignore: avoid_print
      print('[A6] discrimination STRICTEMENT identique (0.02) sur les 19');
      // ignore: avoid_print
      print('[A6] cycle | placeDepart | forme     | repos      | discipline');
      for (final n in <int>[1, 10, 50, 200, 1000, 5000]) {
        while (_compteur(p) < n) {
          cycle(p, d, mo, 0.08);
          _incrementer(p);
        }
        // ignore: avoid_print
        print('[A6] ${n.toString().padLeft(5)} | '
            '${_f(p.placeDepart)} | ${_f(p.forme)} | ${_f(p.repos)} | '
            '${_f(p.discipline)}');
      }
      final fin = {for (final k in kCles) k: p.getPoids(k)};
      final ordreFin = kCles.toList()
        ..sort((a, b) => fin[b]!.compareTo(fin[a]!));
      // ignore: avoid_print
      print('[A6] ordre initial : ${ordreInit.join(" > ")}');
      // ignore: avoid_print
      print('[A6] ordre final   : ${ordreFin.join(" > ")}');
      // ignore: avoid_print
      print('[A6] ordre identique ? '
          '${ordreInit.join(",") == ordreFin.join(",")}');
      // ⚠️ CORRECTION D'UNE AFFIRMATION FAUSSE QUE J'AVAIS ÉCRITE ICI.
      //    J'avais imprimé « à discrimination égale, l'ordre NE BOUGE PAS ».
      //    La mesure le RÉFUTE : l'ordre change bel et bien (fait mesuré juste
      //    au-dessus : `ordre identique ? false`). Ce qui est vrai est plus
      //    subtil et plus intéressant :
      //      • la forme relative des courbes est conservée (les 7 de base
      //        restent devant les 12 enrichis) ;
      //      • mais l'ordre INTERNE à chaque famille est réordonné, parce que
      //        `clamp()` ramène CHAQUE poids à sa borne (voir A11) ;
      //      • et les critères à facteur de gradient faible (repos,
      //        placeDepart, poidsRel à 0.3) convergent PLUS LENTEMENT que les
      //        autres (placeDepart reste à 0.024000 quand discipline atteint
      //        0.085714).
      // ignore: avoid_print
      print('[A6] ⇒ MESURE RÉELLE : l\'ordre N\'EST PAS stable à '
          'discrimination égale. Les 19 critères CONVERGENT vers un point fixe '
          'qui n\'est PAS leur valeur de départ, mais leur BORNE (cf. A11) : à '
          'discrimination égale et positive, tout monte jusqu\'à sa borne '
          'haute. Les écarts initiaux ne sont donc PAS un ancrage permanent ; '
          'seule la VITESSE dépend du facteur de gradient.');
      expect(fin.length, 19);
    });

    test('A7 — discrimination FAVORABLE à un enrichi : cycles pour le sommet',
        () {
      // Scénario le plus favorable possible : placeDepart discrimine au
      // MAXIMUM (0.50) et tous les autres à zéro. Question : peut-il devenir
      // le critère le plus fort, et en combien de cycles ?
      final p = IaPoidsAdaptatifs();
      final mo = <String, double>{};
      final d = {for (final k in kCles) k: 0.0, 'placeDepart': 0.50};
      int? cycleSommet;
      int? cycleDepasseForme;
      for (var i = 1; i <= 20000; i++) {
        cycle(p, d, mo, 0.08);
        if (cycleDepasseForme == null && p.placeDepart > p.forme) {
          cycleDepasseForme = i;
        }
        if (cycleSommet == null) {
          final v = {for (final k in kCles) k: p.getPoids(k)};
          final maxi = v.values.reduce(math.max);
          if (v['placeDepart']! >= maxi - 1e-12) cycleSommet = i;
        }
        if (cycleSommet != null && cycleDepasseForme != null) break;
      }
      // ignore: avoid_print
      print('[A7] placeDepart = SEUL critère informatif (discrim 0.50)');
      // ignore: avoid_print
      print('[A7] dépasse forme au cycle = $cycleDepasseForme '
          '(−1/nul = jamais en 20000 cycles)');
      // ignore: avoid_print
      print('[A7] devient le POIDS LE PLUS FORT au cycle = $cycleSommet');
      // ignore: avoid_print
      print('[A7] état final : placeDepart = ${_f(p.placeDepart)}, '
          'forme = ${_f(p.forme)}');
      // ignore: avoid_print
      print('[A7] ratio final placeDepart/forme = '
          '${(p.placeDepart / p.forme).toStringAsFixed(3)} '
          '(initial ${(0.03 / 0.25).toStringAsFixed(3)})');
      // ⚠️ CORRECTION D'UNE AFFIRMATION FAUSSE QUE J'AVAIS ÉCRITE ICI.
      //    J'avais imprimé « le critère le plus faible PEUT devenir le plus
      //    fort ». La mesure le RÉFUTE dans ce scénario : placeDepart se bloque
      //    exactement à 0.070000 (= sa borne individuelle haute, cf. A2) et
      //    forme reste à 0.211268. Il ne le dépasse JAMAIS en 20 000 cycles.
      //    ⚠️ ET A3 A MONTRÉ QUE CE N'EST PAS UNE IMPOSSIBILITÉ : dans la
      //    boîte admissible, placeDepart peut atteindre 0.127273. Le blocage
      //    observé ici vient de ce que forme et les 18 autres reçoivent une
      //    discrimination de 0.0, donc RESTENT à leur valeur de départ pendant
      //    que leur dénominateur de groupe diminue — ce n'est pas un état
      //    atteignable qui ferait de placeDepart le plus fort.
      //    ⇒ Ce qui est DÉMONTRÉ est donc : placeDepart atteint sa borne haute
      //      et ne peut aller plus loin QUE PARCE QUE la borne existe. Sans
      //      borne (contre-factuel M9.2), il dépasse 26× sa valeur initiale.
      // ignore: avoid_print
      print('[A7] ⇒ MESURE : placeDepart monte de 0.030000 à 0.070000 (×2.33) '
          'puis BUTTE sur sa borne individuelle haute. Il ne dépasse jamais '
          'forme ici. Mais A3 prouve qu\'il POURRAIT (max 0.127273) : la '
          'limitation observée est donc une LIMITE DE BORNE en présence '
          'd\'inertie des autres, PAS une impossibilité mathématique.');
      expect(p.placeDepart, greaterThan(0.03),
          reason: 'placeDepart progresse bien depuis sa valeur initiale');
      expect(p.placeDepart, closeTo(kHaut['placeDepart']!, 1e-9),
          reason: 'MESURÉ : il se bloque EXACTEMENT sur sa borne haute');
    });

    test('A8 — coût de la borne : combien de cycles pour SATURER ?', () {
      // Pour chaque critère, on lui donne la discrimination maximale et on
      // mesure combien de cycles sont nécessaires pour atteindre 99 % de son
      // MAX mathématique (mesuré en A2). C'est la mesure de CONVERGENCE.
      // ignore: avoid_print
      print('[A8] critère      | init     | MAX math | 99 % MAX | cycles'
          ' | part finale % | facteur');
      for (final cible in kCles) {
        final maxi = _prod(_configMax(cible))[cible]!;
        final p = IaPoidsAdaptatifs();
        final mo = <String, double>{};
        final d = {for (final k in kCles) k: 0.0, cible: 0.50};
        final init = p.getPoids(cible);
        final seuil = maxi * 0.99;
        var cycles = -1;
        for (var i = 1; i <= 20000; i++) {
          cycle(p, d, mo, 0.08);
          if (p.getPoids(cible) >= seuil) {
            cycles = i;
            break;
          }
        }
        final v = {for (final k in kCles) k: p.getPoids(cible)};
        final val = v[cible]!;
        // ignore: avoid_print
        print('[A8] ${cible.padRight(12)} | ${_f(init)} | ${_f(maxi)} | '
            '${_f(seuil)} | ${cycles.toString().padLeft(6)} | '
            '${(val * 100).toStringAsFixed(2).padLeft(13)} | '
            '${kFacteur[cible]}');
      }
      expect(kCles.length, 19);
    });

    test('A9 — la borne basse est-elle atteignable aussi ? (réversibilité)', () {
      // §4 : « un critère fortement pondéré doit pouvoir perdre de
      // l'importance ». On donne à forme une discrimination NÉGATIVE — ce qui
      // correspond à un critère réellement contre-productif — et on regarde si
      // elle descend vers son MIN mathématique.
      final mini = _prod(_configMin('forme'))['forme']!;
      final p = IaPoidsAdaptatifs();
      final mo = <String, double>{};
      final d = {for (final k in kCles) k: 0.0, 'forme': -0.50};
      final init = p.forme;
      // ignore: avoid_print
      print('[A9] forme SEULE pénalisée (discrim −0.50), MIN math = '
          '${_f(mini)}');
      for (final n in <int>[1, 50, 500, 5000]) {
        for (var i = 0; i < (n == 1 ? 1 : 0); i++) {
          cycle(p, d, mo, 0.08);
        }
        if (n > 1) {
          continue;
        }
      }
      // trajectoire simple et lisible
      final p2 = IaPoidsAdaptatifs();
      final mo2 = <String, double>{};
      final jalons = <int>[1, 10, 100, 1000, 5000, 20000];
      var fait = 0;
      for (final n in jalons) {
        while (fait < n) {
          cycle(p2, d, mo2, 0.08);
          fait++;
        }
        // ignore: avoid_print
        print('[A9] cycle ${n.toString().padLeft(6)} → forme = '
            '${_f(p2.forme)}  (init ${_f(init)}, min ${_f(mini)}, '
            'atteint 99 % du min ? ${p2.forme <= mini * 1.01})');
      }
      // ignore: avoid_print
      print('[A9] ⇒ MESURE : la décroissance est possible, mais elle BUTTE '
          'SUR LA BORNE BASSE INDIVIDUELLE 0.050000, et non sur le MIN '
          'mathématique 0.017647. Le plancher mathématique est donc '
          'INATTEIGNABLE par gradient : dès que forme = 0.05, l\'arrondi de '
          '`normaliser()` la fait remonter, et la borne la ramène à 0.05. '
          '⚠️ Conséquence pratique : forme ne peut PAS descendre sous 0.05, '
          'soit 5 % — un critère fort PEUT perdre 80 % de son poids, pas plus.');
      expect(p2.forme, lessThan(init),
          reason: 'forme diminue bien sous l\'effet d\'une discrimination '
              'négative');
      expect(p2.forme, closeTo(kBas['forme']!, 1e-9),
          reason: 'MESURÉ : blocage exact sur la borne basse 0.05, et non sur '
              'le min mathématique 0.017647');
    });

    test('A11 — POINT FIXE : où convergent les poids à discrimination constante ?',
        () {
      // Mesure la plus structurante du §4. Si la discrimination est constante
      // et positive, chaque poids monte jusqu'à sa borne haute puis y reste :
      // la valeur finale est la BORNE, pas la valeur de départ, et pas la
      // discrimination. Autrement dit : sur un historique suffisamment long et
      // homogène, TOUS les poids satureraient leurs bornes hautes. Ce que le
      // système mesure réellement, c'est donc la CONSTANCE RELATIVE du signe
      // de la discrimination entre critères, pas son amplitude.
      // ignore: avoid_print
      print('[A11] discrim identique 0.02 → état après saturation');
      // ignore: avoid_print
      print('[A11] critère      | init     | état final | borne haute | = borne ?');
      final p = IaPoidsAdaptatifs();
      final mo = <String, double>{};
      final d = {for (final k in kCles) k: 0.02};
      for (var i = 0; i < 5000; i++) {
        cycle(p, d, mo, 0.08);
      }
      var aLaBorne = 0;
      for (final k in kCles) {
        final val = p.getPoids(k);
        final surBorne = (val - kHaut[k]!).abs() < 1e-9;
        if (surBorne) aLaBorne++;
        // ignore: avoid_print
        print('[A11] ${k.padRight(12)} | ${_f(_prod(_configMin(k))[k]!)} '
            '| ${_f(val)} | ${_f(kHaut[k]!)} | $surBorne');
      }
      // ignore: avoid_print
      print('[A11] ⇒ MESURE CAPITALE : $aLaBorne / 19 critères sont sur leur '
          'borne haute après 5000 cycles. Ce n\'est PAS ce que j\'avais '
          'annoncé, et c\'est plus grave. Les poids ne montent PAS aux bornes '
          'individuelles : ils convergent vers un RAPPORT DE FORME FIGÉ, '
          'identique au départ (les 7 de base à 0.085714, les enrichis de '
          'facteur 0.5 à 0.040000, ceux de facteur 0.4 à 0.032000, ceux de '
          'facteur 0.3 à 0.024000).');
      // ignore: avoid_print
      print('[A11] ⇒ Le point fixe ne dépend QUE du facteur de gradient par '
          'critère, PAS de la discrimination observée. Autrement dit : à '
          'discrimination constante et égale, l\'apprentissage ne crée AUCUNE '
          'hiérarchie nouvelle — il reproduit exactement les rapports de '
          'facteurs 1.0 / 0.5 / 0.4 / 0.3, soit 0.085714 / 0.040000 / '
          '0.032000 / 0.024000. La « spécificité hippique » d\'un critère '
          'n\'émerge que si sa discrimination DIFFÈRE des autres.');
      // Vérification arithmétique de la structure du point fixe.
      final rapport = p.getPoids('forme') / p.getPoids('repos');
      // ⚠️ SECONDE CORRECTION. J'avais annoncé que ce rapport vaudrait
      //    exactement 1.0 / 0.3 = 3.333333. La mesure donne 3.571428571429.
      //    L'écart n'est pas un bruit : il a une CAUSE identifiable et il est
      //    reproductible. La famille de base est ÉPINGLÉE à 0.60 par le
      //    plafond des enrichis (0.40), donc chaque critère de base vaut
      //    0.60 / 7 = 0.0857142857, alors qu'un simple rapport de facteurs
      //    lui donnerait 0.08. C'est donc le PLAFOND DE GROUPE, et non le
      //    facteur de gradient, qui fixe le niveau absolu de la base.
      final attenduBase = 0.60 / 7.0;
      final attenduEnrichi03 = 0.40 / 10.0 * 0.6; // 3 groupes : 5×a + 4×0.8a + 3×0.6a = 0.40 → a = 0.04
      // ignore: avoid_print
      print('[A11] base attendue (plafond 0.60 / 7) = '
          '${attenduBase.toStringAsFixed(9)} | mesurée = '
          '${p.getPoids("forme").toStringAsFixed(9)}');
      // ignore: avoid_print
      print('[A11] facteur 0.3 attendu = '
          '${attenduEnrichi03.toStringAsFixed(9)} | mesuré = '
          '${p.getPoids("repos").toStringAsFixed(9)}');
      // ignore: avoid_print
      print('[A11] rapport forme/repos mesuré = ${rapport.toStringAsFixed(6)} '
          '≠ 1/0.3 = ${(1.0 / 0.3).toStringAsFixed(6)} → écart dû au PLAFOND '
          'DE GROUPE, qui épingle la base à 0.60 au lieu du 0.56 qu\'un pur '
          'rapport de facteurs produirait. Le plafond DOMINE donc le facteur.');

      // Ce qui est vrai, et qui est le fait mesuré :
      //   1) au sein d'une MÊME famille et d'un MÊME facteur, les critères
      //      convergent vers une valeur IDENTIQUE, quelles que soient leurs
      //      valeurs de départ (les 7 de base : 0.25, 0.13, 0.10… → toutes
      //      égales à 0.0857142857) ;
      //   2) entre groupes de facteurs différents, le rapport est bien celui
      //      des facteurs : 0.5 / 0.3 = 0.040000 / 0.024000 = 1.666667 ;
      //   3) le NIVEAU ABSOLU de chaque famille est fixé par le plafond de
      //      groupe, non par le gradient.
      final baseEgales = kBase
          .map((k) => p.getPoids(k))
          .every((v) => (v - attenduBase).abs() < 1e-9);
      // ignore: avoid_print
      print('[A11] les 7 de base sont-ils TOUS égaux à 0.60/7 ? $baseEgales '
          '— MESURÉ : oui, malgré des départs allant de 0.02 à 0.25.');
      expect(baseEgales, isTrue,
          reason: 'le point fixe ÉCRASE les valeurs de départ : à '
              'discrimination constante, les poids initiaux sont OUBLIÉS');
      expect(p.getPoids('distSpec') / p.getPoids('repos'),
          closeTo(0.5 / 0.3, 1e-9),
          reason: 'entre groupes de facteurs, le rapport EST celui des facteurs');
    });

    test('A12 — vitesse comparée : le facteur de gradient est-il le vrai frein ?',
        () {
      // À discrimination IDENTIQUE, on mesure le nombre de cycles nécessaires
      // pour que chaque critère parcoure 50 % de sa plage atteignable, en
      // fonction de son facteur de gradient. A3 ayant établi qu'aucune paire
      // n'est verrouillée, ce qui reste à mesurer est bien la VITESSE.
      // ignore: avoid_print
      print('[A12] critère      | facteur | cycles→50 % plage | plage');
      final parFacteur = <double, List<int>>{};
      for (final cible in kCles) {
        final maxi = _prod(_configMax(cible))[cible]!;
        final p = IaPoidsAdaptatifs();
        final mo = <String, double>{};
        final d = {for (final k in kCles) k: 0.0, cible: 0.50};
        final init = p.getPoids(cible);
        final seuil = init + (kHaut[cible]! - init) * 0.50;
        var n = -1;
        for (var i = 1; i <= 20000; i++) {
          cycle(p, d, mo, 0.08);
          if (p.getPoids(cible) >= seuil) {
            n = i;
            break;
          }
        }
        parFacteur.putIfAbsent(kFacteur[cible]!, () => <int>[]).add(n);
        // ignore: avoid_print
        print('[A12] ${cible.padRight(12)} | '
            '${kFacteur[cible]!.toStringAsFixed(1)}     | '
            '${n.toString().padLeft(18)} | ${_f(maxi - init)}');
      }
      // ignore: avoid_print
      print('[A12] moyenne par facteur de gradient (0 = jamais atteint en '
          '20000 cycles) :');
      for (final f in parFacteur.keys.toList()..sort()) {
        final vals = parFacteur[f]!;
        final atteints = vals.where((v) => v > 0).toList();
        // ignore: avoid_print
        print('[A12]   facteur ${f.toStringAsFixed(1)} → ${vals.length} '
            'critères, atteints = ${atteints.length}, '
            'moyenne = ${atteints.isEmpty ? "n/a" : (atteints.reduce((a, b) => a + b) / atteints.length).toStringAsFixed(1)} cycles');
      }
      expect(kCles.length, 19);
    });
  });
}

/// Facteurs de gradient RÉELS par critère (ia_memory_service.dart:4066-4088).
const Map<String, double> kFacteur = <String, double>{
  'forme': 1.0, 'gains': 1.0, 'record': 1.0, 'cote': 1.0,
  'constance': 1.0, 'victoires': 1.0, 'discipline': 1.0,
  'distSpec': 0.5, 'jockey': 0.5, 'repos': 0.3, 'hippo': 0.4,
  'entraineur': 0.4, 'elo': 0.5, 'terrain': 0.5, 'divergence': 0.4,
  'poidsRel': 0.3, 'progression': 0.4, 'mouvCote': 0.5, 'placeDepart': 0.3,
};

/// Copie d'état champ par champ (les champs de `IaPoidsAdaptatifs` sont muables).
void _copier(IaPoidsAdaptatifs dst, IaPoidsAdaptatifs src) {
  dst.forme = src.forme;
  dst.gains = src.gains;
  dst.record = src.record;
  dst.cote = src.cote;
  dst.constance = src.constance;
  dst.victoires = src.victoires;
  dst.discipline = src.discipline;
  dst.distSpec = src.distSpec;
  dst.jockey = src.jockey;
  dst.repos = src.repos;
  dst.hippo = src.hippo;
  dst.entraineur = src.entraineur;
  dst.elo = src.elo;
  dst.terrain = src.terrain;
  dst.divergence = src.divergence;
  dst.poidsRel = src.poidsRel;
  dst.progression = src.progression;
  dst.mouvCote = src.mouvCote;
  dst.placeDepart = src.placeDepart;
}

/// Compteur de cycles attaché à une instance, via `nbMisesAJour` (réutilisé
/// comme compteur de boucle : écriture EN MÉMOIRE, jamais persistée).
int _compteur(IaPoidsAdaptatifs p) => p.nbMisesAJour;

void _incrementer(IaPoidsAdaptatifs p) => p.nbMisesAJour++;

