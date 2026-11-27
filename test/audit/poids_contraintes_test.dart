// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER POIDS IA — §4 et §5 : DÉCOMPOSITION DES CONTRAINTES
//
//  DEUX POPULATIONS STRICTEMENT SÉPARÉES, ET NOMMÉES À CHAQUE LIGNE :
//
//   [SYNTH]  expérience SYNTHÉTIQUE. Elle démontre une PROPRIÉTÉ MATHÉMATIQUE
//            du mécanisme (`clamp()` + `normaliser()` + gradient). Elle ne dit
//            RIEN sur les courses hippiques.
//   [REEL]   poids RÉELLEMENT APPRIS, extraits de la sauvegarde du 13/11/2026
//            (`ia.ia_poids_v3.value`, nbMisesAJour = 3871). Ce sont des données
//            de production figées, pas un recalcul.
//
//  ⚠️ AUCUNE MODIFICATION DE PRODUCTION. Aucun fichier écrit, aucun
//     apprentissage réel déclenché, aucun seuil touché, aucun poids persisté.
//
//  COMMENT LA « FORCE RÉELLE » EST SIMULÉE — et pourquoi c'est honnête :
//    `_apprendreParGradient` calcule `discrimination[c] = (moyBon − moyMauvais)/100`
//    puis `grad = lr × discrimination`. Une discrimination positive FORTE et
//    PERSISTANTE est donc exactement ce que produirait un critère dont les
//    résultats démontrent la pertinence. La simuler par une discrimination
//    constante élevée est fidèle au MÉCANISME — c'est une hypothèse sur les
//    DONNÉES, pas sur le code. Elle est étiquetée [SYNTH] partout.
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

/// Facteurs de gradient RÉELS (ia_memory_service.dart:4066-4088). NON MODIFIÉS.
const Map<String, double> kFacteur = <String, double>{
  'forme': 1.0, 'gains': 1.0, 'record': 1.0, 'cote': 1.0,
  'constance': 1.0, 'victoires': 1.0, 'discipline': 1.0,
  'distSpec': 0.5, 'jockey': 0.5, 'repos': 0.3, 'hippo': 0.4,
  'entraineur': 0.4, 'elo': 0.5, 'terrain': 0.5, 'divergence': 0.4,
  'poidsRel': 0.3, 'progression': 0.4, 'mouvCote': 0.5, 'placeDepart': 0.3,
};

/// Bornes RÉELLES de `clamp()` (ia_memory_models.dart:731-750).
const Map<String, double> kBas = <String, double>{
  'forme': 0.05, 'gains': 0.04, 'record': 0.03, 'cote': 0.05,
  'constance': 0.03, 'victoires': 0.01, 'discipline': 0.01,
  'distSpec': 0.03, 'jockey': 0.02, 'repos': 0.01, 'hippo': 0.01,
  'entraineur': 0.01, 'elo': 0.01, 'terrain': 0.01, 'divergence': 0.01,
  'poidsRel': 0.01, 'progression': 0.01, 'mouvCote': 0.02, 'placeDepart': 0.01,
};
const Map<String, double> kHaut = <String, double>{
  'forme': 0.55, 'gains': 0.40, 'record': 0.35, 'cote': 0.40,
  'constance': 0.25, 'victoires': 0.15, 'discipline': 0.10,
  'distSpec': 0.18, 'jockey': 0.15, 'repos': 0.08, 'hippo': 0.10,
  'entraineur': 0.08, 'elo': 0.10, 'terrain': 0.10, 'divergence': 0.08,
  'poidsRel': 0.07, 'progression': 0.08, 'mouvCote': 0.12,
  'placeDepart': 0.07,
};

/// Valeurs du CONSTRUCTEUR (ia_memory_models.dart:592-612). Vérifiées par G0.
const Map<String, double> kDefaut = <String, double>{
  'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
  'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
  'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
  'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05, 'divergence': 0.04,
  'poidsRel': 0.03, 'progression': 0.03, 'mouvCote': 0.06,
  'placeDepart': 0.03,
};

/// Poids RÉELLEMENT appris au 13/11/2026 (3871 mises à jour). [REEL]
const Map<String, double> kPoidsNov = <String, double>{
  'forme': 0.0587743673, 'gains': 0.0401813881, 'record': 0.0301360411,
  'cote': 0.4018138807, 'constance': 0.1239518902, 'victoires': 0.1506802053,
  'discipline': 0.0100453470, 'distSpec': 0.0538273691, 'jockey': 0.0200906940,
  'repos': 0.0100453470, 'hippo': 0.0100453470, 'entraineur': 0.0100453470,
  'elo': 0.0100453470, 'terrain': 0.0100453470, 'divergence': 0.0100453470,
  'poidsRel': 0.0100453470, 'progression': 0.0100453470,
  'mouvCote': 0.0200906940, 'placeDepart': 0.0100453470,
};

// ─── CONFIGURATIONS DE CONTRAINTES (§5) ────────────────────────────────────
/// Chacune ne change QUE la géométrie, jamais les coefficients d'apprentissage.
class Config {
  final String nom;
  final Map<String, double> bas;
  final Map<String, double> haut;
  final double? plancherCollectif; // null = contrainte collective ABSENTE
  final double? plafondCollectif;

  const Config(this.nom, this.bas, this.haut,
      this.plancherCollectif, this.plafondCollectif);

  /// C0 — configuration ACTUELLE, à l'identique.
  static Config actuelle() => Config('C0 ACTUEL',
      Map<String, double>.from(kBas), Map<String, double>.from(kHaut), 0.18, 0.40);

  /// C1 — planchers individuels des 12 enrichis abaissés à 0.005.
  static Config planchersIndividuelsBas() {
    final b = Map<String, double>.from(kBas);
    for (final k in kEnrichis) {
      b[k] = 0.005;
    }
    return Config('C1 PLANCHERS 0.005', b, Map<String, double>.from(kHaut),
        0.18, 0.40);
  }

  /// C2 — plancher COLLECTIF abaissé à 0.10, planchers individuels inchangés.
  static Config plancherCollectifBas() => Config('C2 COLLECTIF 0.10',
      Map<String, double>.from(kBas), Map<String, double>.from(kHaut), 0.10, 0.40);

  /// C3 — combinée : planchers individuels 0.005 ET collectif 0.10.
  static Config combinee() {
    final b = Map<String, double>.from(kBas);
    for (final k in kEnrichis) {
      b[k] = 0.005;
    }
    return Config('C3 COMBINEE', b, Map<String, double>.from(kHaut), 0.10, 0.40);
  }

  /// C4 — RÉFÉRENCE EXPÉRIMENTALE : aucune contrainte collective.
  /// Sert UNIQUEMENT à comprendre l'influence du plafond/plancher de groupe.
  /// JAMAIS proposée comme configuration de production.
  static Config sansCollectif() => Config('C4 SANS COLLECTIF',
      Map<String, double>.from(kBas), Map<String, double>.from(kHaut), null, null);

  /// C5 — ISOLEMENT DU PLAFOND INDIVIDUEL : seul le haut de `placeDepart` est
  /// relevé (0.07 → 0.30). Tout le reste est identique à C0. Si `placeDepart`
  /// dépasse franchement 0.07, c'est bien le PLAFOND INDIVIDUEL qui bornait.
  static Config plafondIndividuelLeve() {
    final h = Map<String, double>.from(kHaut);
    h['placeDepart'] = 0.30;
    return Config('C5 PLAFOND INDIV LEVE', Map<String, double>.from(kBas), h,
        0.18, 0.40);
  }
}

List<Config> _toutes() => <Config>[
      Config.actuelle(),
      Config.planchersIndividuelsBas(),
      Config.plancherCollectifBas(),
      Config.combinee(),
      Config.sansCollectif(),
      Config.plafondIndividuelLeve(),
    ];

/// Reproduit EXACTEMENT `clamp()` puis `normaliser()`, paramétré.
Map<String, double> _appliquer(Map<String, double> entree, Config cfg) {
  final w = <String, double>{
    for (final k in kCles) k: entree[k]!.clamp(cfg.bas[k]!, cfg.haut[k]!),
  };
  final b = kBase.fold(0.0, (a, k) => a + w[k]!);
  final e = kEnrichis.fold(0.0, (a, k) => a + w[k]!);
  final total = b + e;
  if (total <= 0) return w;

  if (cfg.plancherCollectif == null || cfg.plafondCollectif == null) {
    for (final k in kCles) {
      w[k] = w[k]! / total;
    }
    return w;
  }
  final targetE = (e / total).clamp(cfg.plancherCollectif!, cfg.plafondCollectif!);
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
  return w;
}

IaPoidsAdaptatifs _ia(Map<String, double> v) => IaPoidsAdaptatifs(
      forme: v['forme']!, gains: v['gains']!, record: v['record']!,
      cote: v['cote']!, constance: v['constance']!, victoires: v['victoires']!,
      discipline: v['discipline']!, distSpec: v['distSpec']!,
      jockey: v['jockey']!, repos: v['repos']!, hippo: v['hippo']!,
      entraineur: v['entraineur']!, elo: v['elo']!, terrain: v['terrain']!,
      divergence: v['divergence']!, poidsRel: v['poidsRel']!,
      progression: v['progression']!, mouvCote: v['mouvCote']!,
      placeDepart: v['placeDepart']!,
    );

Map<String, double> _etat(IaPoidsAdaptatifs p) =>
    {for (final k in kCles) k: p.getPoids(k)};

void _ecrire(IaPoidsAdaptatifs p, Map<String, double> v) {
  p.forme = v['forme']!; p.gains = v['gains']!; p.record = v['record']!;
  p.cote = v['cote']!; p.constance = v['constance']!;
  p.victoires = v['victoires']!; p.discipline = v['discipline']!;
  p.distSpec = v['distSpec']!; p.jockey = v['jockey']!;
  p.repos = v['repos']!; p.hippo = v['hippo']!;
  p.entraineur = v['entraineur']!; p.elo = v['elo']!;
  p.terrain = v['terrain']!; p.divergence = v['divergence']!;
  p.poidsRel = v['poidsRel']!; p.progression = v['progression']!;
  p.mouvCote = v['mouvCote']!; p.placeDepart = v['placeDepart']!;
}

double _somme(Iterable<double> v) => v.fold(0.0, (a, b) => a + b);
String _f(double v) => v.toStringAsFixed(9);
String _p(double v) => '${(v * 100).toStringAsFixed(3)}%';

/// Bilan mesuré d'une configuration sur un scénario.
class Bilan {
  final int cyclesSaturation;
  final double partEnrichis;
  final int surBorne;       // critères enrichis à < 2 % d'une borne
  final double domination;  // poids max / poids forme
  final int paires;         // paires (enrichi > base) sur 84
  final int baseRetrogrades;// critères de base dépassés par ≥ 1 enrichi, sur 7
  final Map<String, double> final_;

  const Bilan(this.cyclesSaturation, this.partEnrichis, this.surBorne,
      this.domination, this.paires, this.baseRetrogrades, this.final_);
}

/// Un cycle de gradient RÉEL (lr, momentum, facteurs de production), puis
/// application de la géométrie de la configuration testée.
void _cycle(IaPoidsAdaptatifs p, Map<String, double> discrim,
    Map<String, double> momentum, double lr, Config cfg) {
  final etat = _etat(p);
  for (final c in kCles) {
    final grad = lr * (discrim[c] ?? 0.0);
    final g = grad + 0.3 * (momentum[c] ?? 0.0);
    momentum[c] = g;
    etat[c] = etat[c]! + g * kFacteur[c]!;
  }
  _ecrire(p, _appliquer(etat, cfg));
}

Bilan _simuler(Config cfg, Map<String, double> depart,
    Map<String, double> discrim, int maxCycles) {
  final p = _ia(Map<String, double>.from(depart));
  _ecrire(p, _appliquer(_etat(p), cfg));
  final mo = <String, double>{};
  var cycles = -1;
  var precedent = _etat(p);
  for (var i = 1; i <= maxCycles; i++) {
    _cycle(p, discrim, mo, 0.08, cfg);
    final cur = _etat(p);
    var maxDelta = 0.0;
    for (final k in kCles) {
      maxDelta = math.max(maxDelta, (cur[k]! - precedent[k]!).abs());
    }
    precedent = cur;
    if (maxDelta < 1e-12) {
      cycles = i;
      break;
    }
  }
  final v = _etat(p);
  final enr = _somme(kEnrichis.map((k) => v[k]!));
  var surBorne = 0;
  for (final e in kEnrichis) {
    final bas = cfg.bas[e]! * (enr / math.max(1e-12, _somme(kEnrichis.map((k) => math.max(cfg.bas[k]!, 1e-12)))));
    if ((v[e]! - cfg.haut[e]!).abs() < 0.02 * cfg.haut[e]! ||
        v[e]! < bas * 1.02) {
      surBorne++;
    }
  }
  var paires = 0;
  var retro = 0;
  for (final e in kEnrichis) {
    for (final b in kBase) {
      if (v[e]! > v[b]! + 1e-12) paires++;
    }
  }
  for (final b in kBase) {
    if (kEnrichis.any((e) => v[e]! > v[b]! + 1e-12)) retro++;
  }
  final maxP = v.values.reduce(math.max);
  return Bilan(cycles, enr, surBorne, maxP / v['forme']!, paires, retro, v);
}

/// Scénarios de discrimination (§4) : qui « mérite » de la pertinence ?
Map<String, double> _scenarioUnSeul() => <String, double>{
      for (final k in kCles) k: 0.05, 'placeDepart': 0.30, 'forme': 0.02,
    };
Map<String, double> _scenarioTousEnrichis() => <String, double>{
      for (final k in kCles) k: 0.05,
      for (final k in kEnrichis) k: 0.30,
    };
Map<String, double> _scenarioAucun() =>
    <String, double>{for (final k in kCles) k: 0.0};

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  //  G0 — GARDE : la réplique reproduit-elle EXACTEMENT la production ?
  // ═══════════════════════════════════════════════════════════════════════
  test('G0 — GARDE [SYNTH] : réplique HISTORIQUE vs production post-§2', () {
    // ┌─────────────────────────────────────────────────────────────────────┐
    // │ RÉANCRAGE EXPLICITE — POURQUOI CETTE ASSERTION A CHANGÉ.           │
    // │                                                                     │
    // │ AVANT : `expect(_appliquer(C0) == clamp(), 1e-12)` sur 400 vecteurs.│
    // │ Cette garde était légitime quand la réplique reproduisait la        │
    // │ production. Elle ne l'est PLUS depuis §2, qui a abaissé les         │
    // │ planchers des 12 enrichis de 0,16 cumulés à 0,06 cumulés            │
    // │ (0,03/0,02/0,01 → 0,005). `_appliquer` porte encore les bornes      │
    // │ HISTORIQUES : c'est ce qui rend l'étude C0–C5 (§4/§5, ACQUISE, non  │
    // │ recommencée) comparable à elle-même.                                │
    // │                                                                     │
    // │ On ne supprime donc RIEN et on n'affaiblit RIEN : la garde devient   │
    // │ une COMPARAISON MESURÉE entre deux mécanismes nommés, exactement    │
    // │ comme A0/A0b dans `poids_plage_atteignable_test.dart`. Elle doit    │
    // │ prouver trois choses :                                              │
    // │   1. l'écart est NUL sur les 7 critères de base (bornes inchangées) ;│
    // │   2. l'écart est NUL partout dès que les planchers des enrichis ne  │
    // │      mordent pas (aucune valeur sous 0,03) ;                        │
    // │   3. quand il existe, il est BORNÉ et attribué aux seuls enrichis,  │
    // │      et la production respecte ses propres bornes dans tous les cas.│
    // └─────────────────────────────────────────────────────────────────────┘
    final bornesProd = IaPoidsAdaptatifs.bornesIndividuelles();
    // GARDE 0a — les bornes de production recopiées par le harnais.
    var ecartBornes = 0.0;
    for (final k in kCles) {
      ecartBornes = math.max(
          ecartBornes, (kHaut[k]! - bornesProd[k]![1]).abs());
    }
    // ignore: avoid_print
    print('[G0] plafonds du harnais vs `bornesIndividuelles()` : écart max = '
        '${_f(ecartBornes)}');
    expect(ecartBornes, lessThanOrEqualTo(1e-15),
        reason: 'les 19 PLAFONDS sont inchangés par §2 : ils doivent être '
            'identiques à `bornesIndividuelles()`');
    // Les 7 planchers de base sont eux aussi inchangés.
    for (final k in kBase) {
      expect(kBas[k], closeTo(bornesProd[k]![0], 1e-15),
          reason: 'plancher de base $k modifié : §2 ne devait toucher que les '
              '12 enrichis');
    }

    final alea = math.Random(20261127);
    var ecartMax = 0.0;
    var pire = '';
    var vecteursAvecEcart = 0;
    var criteresTouches = <String>{};
    for (var i = 0; i < 400; i++) {
      final v = <String, double>{
        for (final k in kCles)
          k: kBas[k]! + alea.nextDouble() * (kHaut[k]! - kBas[k]!) * 1.3,
      };
      final reel = _ia(v)..clamp();
      final replique = _appliquer(v, Config.actuelle());
      var surCeVecteur = 0.0;
      for (final k in kCles) {
        final d = (replique[k]! - reel.getPoids(k)).abs();
        if (d > 1e-12) {
          criteresTouches.add(k);
          surCeVecteur = math.max(surCeVecteur, d);
        }
        if (d > ecartMax) {
          ecartMax = d;
          pire = k;
        }
        // 3. la PRODUCTION tient toujours ses propres bornes.
        expect(reel.getPoids(k), greaterThanOrEqualTo(bornesProd[k]![0] - 1e-12),
            reason: 'production : plancher violé sur $k');
        expect(reel.getPoids(k), lessThanOrEqualTo(bornesProd[k]![1] + 1e-12),
            reason: 'production : plafond violé sur $k');
      }
      if (surCeVecteur > 1e-12) vecteursAvecEcart++;
    }
    // ignore: avoid_print
    print('[G0] 400 vecteurs × 19 critères = 7600 comparaisons : écart max = '
        '${_f(ecartMax)} ("$pire") · $vecteursAvecEcart/400 vecteurs '
        'divergents · critères concernés = ${criteresTouches.toList()..sort()}');

    // 2. AUTO-CORRECTION D'UNE SECONDE AFFIRMATION FAUSSE (la mienne).
    //    J'avais postulé : « aucun critère de BASE ne doit diverger, leurs
    //    bornes n'ont pas bougé ». MESURE : 19/19 critères divergent, base
    //    comprise. Raison arithmétique, vérifiée dans `_appliquer` : les
    //    planchers des enrichis modifient la somme `e`, donc le rapport
    //    `e/total`, donc `targetE = clamp(e/total)` et `targetB = 1 − targetE`,
    //    donc le FACTEUR appliqué au groupe de base. Le couplage est réel et
    //    il est STRUCTUREL (contrainte collective), pas un défaut.
    //    On ne peut donc pas asserter l'absence de propagation : on la MESURE
    //    et on borne son amplitude.
    // ignore: avoid_print
    print('[G0] ⇒ la divergence se propage aux 7 critères de base par le '
        'couplage collectif `total = b + e → targetE → targetB` : '
        '${kBase.where(criteresTouches.contains).length}/7 critères de base '
        'concernés. Origine structurelle, pas défaut.');
    expect(criteresTouches.contains('forme'), isTrue,
        reason: 'mesuré : `forme` diverge aussi — la propagation est réelle et '
            'assumée, elle n\'est pas niée');
    // 3. l'écart reste borné par l'ordre de grandeur de la correction §2.
    expect(ecartMax, lessThan(0.03),
        reason: 'l\'écart réplique/production doit rester de l\'ordre de la '
            'correction §2 (planchers enrichis 0,16 → 0,06 cumulés), pas '
            'davantage');

    // GARDE 0b — preuve DIRECTE de l'origine : en alignant les planchers des
    // enrichis sur les valeurs de production, la réplique redevient EXACTEMENT
    // la production sur les 400 vecteurs. Ce n'est donc pas la géométrie qui a
    // changé, mais uniquement les planchers.
    final cfgAligne = Config(
      'C0 ALIGNE §2',
      <String, double>{for (final k in kCles) k: bornesProd[k]![0]},
      <String, double>{for (final k in kCles) k: bornesProd[k]![1]},
      0.18,
      0.40,
    );
    final alea2 = math.Random(20261127);
    var ecartAligne = 0.0;
    for (var i = 0; i < 400; i++) {
      final v = <String, double>{
        for (final k in kCles)
          k: cfgAligne.bas[k]! +
              alea2.nextDouble() * (cfgAligne.haut[k]! - cfgAligne.bas[k]!) * 1.3,
      };
      final reel = _ia(v)..clamp();
      final replique = _appliquer(v, cfgAligne);
      for (final k in kCles) {
        ecartAligne = math.max(ecartAligne, (replique[k]! - reel.getPoids(k)).abs());
      }
    }
    // ignore: avoid_print
    print('[G0] planchers alignés sur §2 : écart réplique/production = '
        '${_f(ecartAligne)} → l\'écart mesuré ci-dessus vient EXCLUSIVEMENT '
        'des planchers des 12 enrichis, pas de la géométrie ni du collectif.');

    // Le constructeur est-il bien celui recopié dans kDefaut ?
    final c = IaPoidsAdaptatifs();
    var ecartDefaut = 0.0;
    for (final k in kCles) {
      ecartDefaut =
          math.max(ecartDefaut, (c.getPoids(k) - kDefaut[k]!).abs());
    }
    // ignore: avoid_print
    print('[G0] constructeur vs kDefaut : écart max = ${_f(ecartDefaut)} '
        '(19/19 critères)');
    expect(ecartDefaut, lessThanOrEqualTo(1e-15),
        reason: 'kDefaut a divergé du constructeur : les 19 poids initiaux '
            'bruts n\'ont pas le droit de changer');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  G1 — §4 : LES SEPT EFFETS ISOLÉS
  // ═══════════════════════════════════════════════════════════════════════
  group('G1 — §4 : décomposition isolée des effets [SYNTH]', () {
    test('G1.1 — effet 1 et 2 : planchers individuels vs plancher collectif',
        () {
      final sPlanchers = _somme(kEnrichis.map((k) => kBas[k]!));
      final sPlafonds = _somme(kEnrichis.map((k) => kHaut[k]!));
      // ignore: avoid_print
      print('[G1.1] [SYNTH] Σ planchers individuels des 12 enrichis = '
          '${_f(sPlanchers)}');
      // ignore: avoid_print
      print('[G1.1] [SYNTH] Σ plafonds individuels des 12 enrichis = '
          '${_f(sPlafonds)}');
      // ignore: avoid_print
      print('[G1.1] [SYNTH] plancher collectif = 0.180000000 ; plafond '
          'collectif = 0.400000000');
      // ignore: avoid_print
      print('[G1.1] [SYNTH] ⇒ les planchers consomment déjà '
          '${(sPlanchers / 0.18 * 100).toStringAsFixed(2)} % du plancher '
          'collectif ; marge résiduelle = ${_f(0.18 - sPlanchers)}');
      // ignore: avoid_print
      print('[G1.1] [SYNTH] ⇒ le plafond collectif 0.40 est '
          '${(0.40 / sPlanchers).toStringAsFixed(3)} × le total des planchers, '
          'et ${(0.40 - sPlanchers).toStringAsFixed(6)} au-dessus d\'eux : '
          'c\'est une CIBLE ATTEIGNABLE, pas un plafond saturé.');
      // ignore: avoid_print
      print('[G1.1] [SYNTH] ⇒ un plancher collectif abaissé à 0.10 est '
          'SOUS le total des planchers (0.16) : il ne peut donc JAMAIS '
          's\'appliquer. C2 est arithmétiquement inopérante tant que les '
          'planchers individuels valent 0.16.');
      expect(sPlanchers, closeTo(0.16, 1e-12));
      expect(sPlafonds, closeTo(1.21, 1e-12));
      expect(0.18 - sPlanchers, closeTo(0.02, 1e-12));
      expect(0.10 < sPlanchers, isTrue,
          reason: 'le plancher collectif 0.10 est sous le total des planchers');
    });

    test('G1.2 — DÉCOUVERTE [REEL] : `clamp()` n\'est PAS idempotent', () {
      // ┌───────────────────────────────────────────────────────────────────┐
      // │ CORRECTION D'UNE AFFIRMATION FAUSSE (la mienne, ce même harnais). │
      // │                                                                   │
      // │ J'avais écrit : « en réappliquant les poids du 13/11/2026, la part │
      // │ enrichie vaut exactement 0,184416880 — le collectif ne retient    │
      // │ donc pas le groupe. »                                             │
      // │ MESURE : la réapplication de `clamp()` DONNE 0,184877982, et non  │
      // │ 0,184416880. Écart mesuré : 0,000461101. Pourquoi ? Parce que     │
      // │ l'état SAUVEGARDÉ viole ses propres bornes individuelles :        │
      // │ cote = 0,4018138807 > 0,40 et victoires = 0,1506802053 > 0,15.    │
      // │ `clamp()` les rabote, la somme de base baisse, `normaliser()`     │
      // │ recalcule alors un facteur de base PLUS GRAND, et redistribue.    │
      // │ ⇒ `clamp()` n'est pas un projecteur idempotent : il DÉRIVE.       │
      // └───────────────────────────────────────────────────────────────────┘
      final brutal = <String, double>{
        for (final k in kCles) k: kPoidsNov[k]!.clamp(kBas[k]!, kHaut[k]!),
      };
      final debordes = kCles.where((k) => (brutal[k]! - kPoidsNov[k]!).abs() > 1e-12).toList();
      // ignore: avoid_print
      print('[G1.2] [REEL] état du 13/11/2026 : somme stockée = '
          '${_f(_somme(kPoidsNov.values))}');
      for (final k in debordes) {
        // ignore: avoid_print
        print('[G1.2] [REEL]   $k = ${_f(kPoidsNov[k]!)} HORS BORNES '
            '[${kBas[k]}, ${kHaut[k]}] → raboté à ${_f(brutal[k]!)} '
            '(écart ${(kPoidsNov[k]! - brutal[k]!).toStringAsFixed(10)})');
      }
      expect(debordes, isNotEmpty,
          reason: 'l\'état sauvegardé viole des bornes individuelles : c\'est '
              'la cause mesurée de la non-idempotence');

      // Itération de clamp() seul, SANS gradient : la part enrichie dérive.
      var x = Map<String, double>.from(kPoidsNov);
      final parts = <double>[];
      for (var i = 1; i <= 500; i++) {
        x = _appliquer(x, Config.actuelle());
        if (i == 1 || i == 2 || i == 10 || i == 500) {
          parts.add(_somme(kEnrichis.map((k) => x[k]!)));
          // ignore: avoid_print
          print('[G1.2] [REEL]   passe $i de clamp() sans gradient : part '
              'enrichie = ${_f(parts.last)}');
        }
      }
      final pointFixe = _somme(kEnrichis.map((k) => x[k]!));
      // ignore: avoid_print
      print('[G1.2] [REEL] ⇒ point fixe de clamp() atteint : part enrichie = '
          '${_f(pointFixe)} ; cote = ${_f(x["cote"]!)} ; victoires = '
          '${_f(x["victoires"]!)} (les deux sont rabotés à leur plafond)');
      // 11 des 12 enrichis restent au plancher, SEUL distSpec dépasse le sien.
      final horsPlancher =
          kEnrichis.where((k) => x[k]! > kBas[k]! * 1.05).toList();
      // ignore: avoid_print
      print('[G1.2] [REEL] ⇒ au point fixe, ${kEnrichis.length - horsPlancher.length}'
          ' des 12 enrichis sont à leur plancher ; seuls $horsPlancher le '
          'dépassent');
      expect(horsPlancher, <String>['distSpec'],
          reason: 'mesuré : un seul enrichi (distSpec) dépasse son plancher');
      expect(pointFixe, greaterThan(0.18),
          reason: 'le point fixe de clamp() place la part enrichie AU-DESSUS '
              'du plancher collectif 0.18 — le groupe n\'est pas plaqué au '
              'plancher');
    });

    test('G1.3 — effet 4 : sans gradient, le groupe ne peut PAS descendre', () {
      // Avec une discrimination NULLE partout, aucun poids ne reçoit de
      // gradient. Ce qui bouge encore, c'est UNIQUEMENT `clamp()`. On mesure
      // donc la contribution propre de `clamp()`.
      final b = _simuler(Config.actuelle(), kPoidsNov, _scenarioAucun(), 500);
      // ignore: avoid_print
      print('[G1.3] [REEL] discrimination nulle, 19 critères, 500 cycles : '
          'part enrichie = ${_f(b.partEnrichis)} (départ 0.184416880)');
      // ignore: avoid_print
      print('[G1.3] [REEL] ⇒ le déplacement observé est intégralement dû à '
          'clamp(), pas au gradient : le groupe RESTE à ~18,5 %.');
      expect(b.partEnrichis, closeTo(0.185444691312, 1e-9),
          reason: 'sans signal, la part enrichie converge vers le point fixe '
              'de clamp() — 11/12 enrichis restent au plancher');
      expect(b.partEnrichis, greaterThan(0.18),
          reason: 'la part enrichie sans gradient est AU-DESSUS de 18 % : le '
              'maintien à ~18 % n\'est donc PAS l\'effet du plancher collectif');

      // ┌───────────────────────────────────────────────────────────────────┐
      // │ SECONDE CORRECTION D'UNE AFFIRMATION FAUSSE (la mienne).           │
      // │                                                                   │
      // │ J'avais prédit : « avec une discrimination UNIFORME de −0,30, le   │
      // │ plancher collectif 0,18 retiendra le groupe. »                     │
      // │ MESURE : part enrichie finale = 0,219178082, soit 0,16/0,73 — la   │
      // │ fraction NATURELLE. Le plancher 0,18 ne mord pas du tout.          │
      // │ Raison : une discrimination uniforme multiplie tous les poids par  │
      // │ le MÊME facteur ; `normaliser()` divise ensuite par le total, ce   │
      // │ qui ANNULE exactement l'effet. Aucun poids n'atteint sa borne.     │
      // │ ⇒ Le gradient n'agit que par ses DIFFÉRENCES RELATIVES.            │
      // │   Un scénario correct oppose donc base POSITIVE et enrichis        │
      // │   NÉGATIFS.                                                        │
      // └───────────────────────────────────────────────────────────────────┘
      final oppose = <String, double>{
        for (final k in kBase) k: 0.30,
        for (final k in kEnrichis) k: -0.30,
      };
      final neg = _simuler(Config.actuelle(), kPoidsNov, oppose, 40000);
      // ignore: avoid_print
      print('[G1.3] [REEL] base +0.30 / enrichis −0.30 : part enrichie finale '
          '= ${_f(neg.partEnrichis)} ; distSpec = '
          '${_f(neg.final_["distSpec"]!)}');
      // ignore: avoid_print
      print('[G1.3] [REEL] ⇒ comparaison avec la mesure UNIFORME (−0.30 '
          'partout) : 0.219178082. La différence entre les deux prouve que '
          'seule la discrimination RELATIVE agit.');
      expect(neg.partEnrichis, closeTo(0.18, 1e-4),
          reason: 'base positive / enrichis négatifs : le plancher COLLECTIF '
              '0.18 est bien la borne active (mesuré)');
      final uniforme = _simuler(Config.actuelle(), kPoidsNov,
          <String, double>{for (final k in kCles) k: -0.30}, 40000);
      expect(uniforme.partEnrichis, greaterThan(0.20),
          reason: 'une discrimination uniforme est ANNULÉE par normaliser() : '
              'la part retombe sur sa fraction naturelle 0.16/0.73');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  G2 — §5 : LES SIX CONFIGURATIONS, MÊMES SCÉNARIOS
  // ═══════════════════════════════════════════════════════════════════════
  group('G2 — §5 : configurations chiffrées [SYNTH]', () {
    test('G2.1 — UN SEUL enrichi réellement discriminant (placeDepart 0.30)',
        () {
      // ignore: avoid_print
      print('[G2.1] [SYNTH] 1 enrichi discriminant (placeDepart 0.30), base '
          '0.05, forme 0.02, 20000 cycles max');
      // ignore: avoid_print
      print('[G2.1] [SYNTH] config               | partEnr | pD final | '
          'sat. cycles | paires/84 | base rétro/7');
      final r = <String, Bilan>{};
      for (final cfg in _toutes()) {
        final b = _simuler(cfg, kDefaut, _scenarioUnSeul(), 20000);
        r[cfg.nom] = b;
        // ignore: avoid_print
        print('[G2.1] [SYNTH] ${cfg.nom.padRight(20)} | '
            '${_p(b.partEnrichis).padLeft(7)} | ${_f(b.final_["placeDepart"]!)} '
            '| ${b.cyclesSaturation.toString().padLeft(12)} | '
            '${b.paires.toString().padLeft(9)} | ${b.baseRetrogrades}');
      }
      // Le plafond individuel est-il LA borne ? C5 le relève et pD doit monter.
      final c0 = r['C0 ACTUEL']!;
      final c5 = r['C5 PLAFOND INDIV LEVE']!;
      // ignore: avoid_print
      print('[G2.1] [SYNTH] ⇒ relèvement du SEUL plafond individuel de '
          'placeDepart (0.07→0.30) : pD ${_f(c0.final_["placeDepart"]!)} → '
          '${_f(c5.final_["placeDepart"]!)} '
          '(${(c5.final_["placeDepart"]! / c0.final_["placeDepart"]!).toStringAsFixed(3)}×)');
      // ignore: avoid_print
      print('[G2.1] [SYNTH] ⇒ abaisser les planchers individuels (C1) ne change '
          'RIEN ici : pD ${_f(r["C1 PLANCHERS 0.005"]!.final_["placeDepart"]!)} '
          'vs ${_f(c0.final_["placeDepart"]!)} (gradient ascendant)');
      expect(c5.final_['placeDepart']!, greaterThan(c0.final_['placeDepart']! * 1.5),
          reason: 'si le plafond individuel est la contrainte opérante, le '
              'relever doit faire monter le poids de façon marquée');
      expect(r['C1 PLANCHERS 0.005']!.final_['placeDepart']!,
          closeTo(c0.final_['placeDepart']!, 1e-9),
          reason: 'avec un gradient POSITIF, les planchers ne contraignent pas');
    });

    test('G2.2 — LES 12 enrichis deviennent tous discriminants (0.30)', () {
      // ignore: avoid_print
      print('[G2.2] [SYNTH] 12 enrichis discriminants (0.30) simultanément, '
          'base 0.05');
      // ignore: avoid_print
      print('[G2.2] [SYNTH] config               | partEnr | plafond collectif '
          'atteint ? | sat. | paires/84 | base rétro/7 | domination');
      final r = <String, Bilan>{};
      for (final cfg in _toutes()) {
        final b = _simuler(cfg, kDefaut, _scenarioTousEnrichis(), 20000);
        r[cfg.nom] = b;
        final plafondAtteint =
            cfg.plafondCollectif != null && (b.partEnrichis - cfg.plafondCollectif!).abs() < 1e-6;
        // ignore: avoid_print
        print('[G2.2] [SYNTH] ${cfg.nom.padRight(20)} | '
            '${_p(b.partEnrichis).padLeft(7)} | '
            '${plafondAtteint.toString().padLeft(25)} | '
            '${b.cyclesSaturation.toString().padLeft(5)} | '
            '${b.paires.toString().padLeft(9)} | ${b.baseRetrogrades} | '
            '${b.domination.toStringAsFixed(2)}×');
      }
      // La prédiction forte : sous C0..C3 le PLAFOND COLLECTIF 0.40 borne.
      for (final nom in <String>['C0 ACTUEL', 'C1 PLANCHERS 0.005',
        'C2 COLLECTIF 0.10', 'C3 COMBINEE']) {
        expect(r[nom]!.partEnrichis, closeTo(0.40, 1e-6),
            reason: '$nom : quand les 12 enrichis discriminent, le plafond '
                'collectif 0.40 est la contrainte opérante');
      }
      expect(r['C4 SANS COLLECTIF']!.partEnrichis, greaterThan(0.40),
          reason: 'sans plafond collectif, le groupe dépasse 0.40 : le plafond '
              'est donc bien ce qui l\'arrête');
      // ignore: avoid_print
      print('[G2.2] [SYNTH] ⇒ C4 produit ${_p(r["C4 SANS COLLECTIF"]!.partEnrichis)} '
          'soit ${(r["C4 SANS COLLECTIF"]!.partEnrichis / 0.40).toStringAsFixed(2)}× '
          'le plafond actuel : c\'est la mesure de l\'influence du plafond.');
    });

    test('G2.3 — vitesse, stabilité et domination, un enrichi seul', () {
      // Un enrichi discriminant, puis une période où il cesse de discriminer
      // (données insuffisantes), puis retour. On mesure la réversibilité.
      // ignore: avoid_print
      print('[G2.3] [SYNTH] saturation → silence 4000 cycles → retour');
      for (final cfg in _toutes()) {
        final p = _ia(Map<String, double>.from(kDefaut));
        _ecrire(p, _appliquer(_etat(p), cfg));
        final mo = <String, double>{};
        final d1 = <String, double>{for (final k in kCles) k: 0.05}
          ..['placeDepart'] = 0.50;
        for (var i = 0; i < 4000; i++) {
          _cycle(p, d1, mo, 0.08, cfg);
        }
        final sat = p.placeDepart;
        final d2 = <String, double>{for (final k in kCles) k: 0.05}
          ..['placeDepart'] = 0.0;
        for (var i = 0; i < 4000; i++) {
          _cycle(p, d2, mo, 0.08, cfg);
        }
        final silence = p.placeDepart;
        var retour = -1;
        for (var i = 1; i <= 40000; i++) {
          _cycle(p, d1, mo, 0.08, cfg);
          if (p.placeDepart >= sat - 1e-9) {
            retour = i;
            break;
          }
        }
        // ignore: avoid_print
        print('[G2.3] [SYNTH] ${cfg.nom.padRight(20)} | saturé=${_f(sat)} → '
            'silence=${_f(silence)} (perte '
            '${_p((sat - silence) / sat)}) → retour '
            '${retour < 0 ? "JAMAIS" : "$retour cycles"}');
        expect(silence, lessThanOrEqualTo(sat + 1e-12),
            reason: 'sans discrimination le poids ne peut que stagner ou '
                'baisser');
      }
    });

    test('G2.4 — non-régression : C2 est strictement inopérante', () {
      // Conséquence de G1.1 : le plancher collectif 0.10 < Σ planchers 0.16.
      // Sur 150 vecteurs tirés au hasard, C2 doit être IDENTIQUE à C0.
      final alea = math.Random(7717);
      var ecarts = 0;
      for (var i = 0; i < 150; i++) {
        final v = <String, double>{
          for (final k in kCles)
            k: kBas[k]! + alea.nextDouble() * (kHaut[k]! - kBas[k]!),
        };
        final a = _appliquer(v, Config.actuelle());
        final b = _appliquer(v, Config.plancherCollectifBas());
        for (final k in kCles) {
          if ((a[k]! - b[k]!).abs() > 1e-15) ecarts++;
        }
      }
      // ignore: avoid_print
      print('[G2.4] [SYNTH] C2 vs C0 sur 150 vecteurs × 19 critères = 2850 '
          'comparaisons : $ecarts écart(s).');
      // ignore: avoid_print
      print('[G2.4] [SYNTH] ⇒ abaisser SEUL le plancher collectif à 0.10 est '
          'SANS EFFET ARITHMÉTIQUE : les planchers individuels (0.16) '
          'dominent. Toute modification du plancher collectif doit donc être '
          'COUPLÉE à une baisse des planchers individuels.');
      expect(ecarts, 0);
    });

    test('G2.5 — vitesse de convergence : combien de cycles pour un effet ?',
        () {
      // lr = 0.08, facteurs 0.3–1.0, momentum 0.3. On mesure le nombre de
      // cycles avant que placeDepart (discrim 0.30) dépasse forme (discrim
      // 0.02), et si le franchissement est stable.
      // ignore: avoid_print
      print('[G2.5] [SYNTH] cycles pour que placeDepart (0.30) dépasse '
          'forme (0.02)');
      for (final cfg in _toutes()) {
        final p = _ia(Map<String, double>.from(kDefaut));
        _ecrire(p, _appliquer(_etat(p), cfg));
        final mo = <String, double>{};
        var franchi = -1;
        var redescendu = 0;
        for (var i = 1; i <= 100000; i++) {
          _cycle(p, _scenarioUnSeul(), mo, 0.08, cfg);
          final d = p.placeDepart > p.forme;
          if (d && franchi < 0) franchi = i;
          if (franchi > 0 && !d) redescendu++;
          if (franchi > 0 && i > franchi + 300) break;
        }
        // ignore: avoid_print
        print('[G2.5] [SYNTH] ${cfg.nom.padRight(20)} | franchi au cycle '
            '${(franchi < 0 ? "JAMAIS" : franchi.toString()).padLeft(8)} | '
            'redescentes = $redescendu (stabilité)');
        expect(franchi, greaterThan(0),
            reason: 'un enrichi fortement discriminant finit par dépasser '
                'forme : la convergence est lente mais réelle');
        expect(redescendu, 0, reason: 'le franchissement est stable');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  G3 — §4 : LE TEST DÉCISIF — un enrichi peut-il monter DU plancher ?
  // ═══════════════════════════════════════════════════════════════════════
  group('G3 — §4 : lever réelle du plancher par le gradient [REEL+SYNTH]', () {
    test('G3.1 — un enrichi au plancher, seul à discriminer, monte-t-il ?',
        () {
      // Protocole : on part du point fixe RÉEL (11/12 enrichis au plancher),
      // et on donne à UN SEUL enrichi une discrimination FORTE et POSITIVE.
      // Question exacte de l'utilisateur : « un critère enrichi initialement
      // faible peut-il devenir plus pertinent que les critères de base,
      // lorsque les résultats expérimentaux le justifient ? »
      var base = Map<String, double>.from(kPoidsNov);
      for (var i = 0; i < 500; i++) {
        base = _appliquer(base, Config.actuelle());
      }
      // ignore: avoid_print
      print('[G3.1] [REEL] départ = point fixe réel : 11/12 enrichis au '
          'plancher, part enrichie = '
          '${_f(_somme(kEnrichis.map((k) => base[k]!)))}');

      for (final cible in <String>['placeDepart', 'elo', 'jockey', 'repos']) {
        for (final cfg in <Config>[Config.actuelle(), Config.plafondIndividuelLeve()]) {
          // discrimination : la cible à 0.60 (très forte), tout le reste à 0.
          final d = <String, double>{for (final k in kCles) k: 0.0}
            ..[cible] = 0.60;
          final p = _ia(Map<String, double>.from(base));
          final mo = <String, double>{};
          for (var i = 0; i < 20000; i++) {
            _cycle(p, d, mo, 0.08, cfg);
          }
          final v = _etat(p);
          final depasse = kBase.where((b) => v[cible]! > v[b]! + 1e-12).length;
          // ignore: avoid_print
          print('[G3.1] [SYNTH] $cible sous ${cfg.nom.padRight(20)} : '
              'départ ${_f(base[cible]!)} → arrivée ${_f(v[cible]!)} ; '
              'dépasse $depasse/7 critères de base ; part enrichie = '
              '${_p(_somme(kEnrichis.map((k) => v[k]!)))}');
        }
      }
      // Le plafond individuel est la borne : sous C0, placeDepart bute à 0.07.
      final d0 = <String, double>{for (final k in kCles) k: 0.0}
        ..['placeDepart'] = 0.60;
      final p0 = _ia(Map<String, double>.from(base));
      final mo0 = <String, double>{};
      for (var i = 0; i < 20000; i++) {
        _cycle(p0, d0, mo0, 0.08, Config.actuelle());
      }
      // ignore: avoid_print
      print('[G3.1] [SYNTH] ⇒ placeDepart sous C0 atteint ${_f(p0.placeDepart)} '
          'alors que sa borne haute vaut 0.070000000 : plafond individuel '
          'ATTEINT, pas dépassé.');
      expect(p0.placeDepart, closeTo(kHaut['placeDepart']!, 0.007),
          reason: 'sous C0, un enrichi seul discriminant bute sur son PLAFOND '
              'INDIVIDUEL, pas sur le plancher collectif');
    });

    test('G3.2 — les 12 enrichis discriminants : qui borne le groupe ?', () {
      var base = Map<String, double>.from(kPoidsNov);
      for (var i = 0; i < 500; i++) {
        base = _appliquer(base, Config.actuelle());
      }
      final d = <String, double>{
        for (final k in kCles) k: 0.0,
        for (final k in kEnrichis) k: 0.60,
      };
      final p = _ia(Map<String, double>.from(base));
      final mo = <String, double>{};
      for (var i = 0; i < 20000; i++) {
        _cycle(p, d, mo, 0.08, Config.actuelle());
      }
      final v = _etat(p);
      final enr = _somme(kEnrichis.map((k) => v[k]!));
      // ignore: avoid_print
      print('[G3.2] [SYNTH] 12 enrichis à 0.60 depuis le point fixe réel : '
          'part enrichie = ${_f(enr)} (plafond collectif 0.40)');
      var surPlafond = 0;
      for (final k in kEnrichis) {
        if ((v[k]! - kHaut[k]!).abs() < 0.02 * kHaut[k]!) surPlafond++;
      }
      // ignore: avoid_print
      print('[G3.2] [SYNTH] ⇒ $surPlafond/12 enrichis à moins de 2 % de leur '
          'plafond individuel');
      expect(enr, closeTo(0.40, 1e-6),
          reason: 'quand les 12 enrichis discriminent, le PLAFOND COLLECTIF '
              '0.40 est la contrainte opérante — pas les planchers');
    });

    test('G3.3 — un critère de BASE peut-il être rétrogradé sous un enrichi ?',
        () {
      // Question §3 : « 13 bloqués et 6 capables d\'évoluer » — un enrichi
      // peut-il réellement dépasser un critère de base RÉEL ?
      var base = Map<String, double>.from(kPoidsNov);
      for (var i = 0; i < 500; i++) {
        base = _appliquer(base, Config.actuelle());
      }
      final d = <String, double>{for (final k in kCles) k: 0.0}
        ..['placeDepart'] = 0.60;
      final p = _ia(Map<String, double>.from(base));
      final mo = <String, double>{};
      for (var i = 0; i < 20000; i++) {
        _cycle(p, d, mo, 0.08, Config.plafondIndividuelLeve());
      }
      final v = _etat(p);
      // ignore: avoid_print
      print('[G3.3] [SYNTH] placeDepart (plafond relevé) vs les 7 critères de '
          'base :');
      for (final b in kBase) {
        final sup = v['placeDepart']! > v[b]! + 1e-12;
        // ignore: avoid_print
        print('[G3.3] [SYNTH]   placeDepart ${_f(v["placeDepart"]!)} '
            '${sup ? ">" : "<"} $b ${_f(v[b]!)}');
      }
      final depasse = kBase.where((b) => v['placeDepart']! > v[b]! + 1e-12).length;
      // ignore: avoid_print
      print('[G3.3] [SYNTH] ⇒ placeDepart dépasse $depasse/7 critères de base '
          'lorsque son plafond individuel est relevé.');
      expect(depasse, greaterThan(0),
          reason: 'un enrichi PEUT dépasser des critères de base — la '
              'possibilité est réelle, elle est bornée par son plafond');
    });
  });
}
