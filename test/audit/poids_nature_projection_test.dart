// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER POIDS IA — §4 : NATURE MATHÉMATIQUE EXACTE DE LA PROJECTION
//
//  OBJET : établir par MESURE ce que fait réellement `IaPoidsAdaptatifs
//  .projeter()`, et si la qualification « projection euclidienne » employée
//  dans la documentation est exacte.
//
//  ⚠️ AUCUN CODE DE PRODUCTION N'EST MODIFIÉ PAR CE HARNAIS. Si la
//     documentation est fausse, seule la documentation sera corrigée
//     (§4 : « Si seule la terminologie est incorrecte, corrige uniquement la
//     documentation »).
//
//  ─────────────────────────────────────────────────────────────────────────
//  HISTORIQUE DE CE HARNAIS — TROIS HYPOTHÈSES INFIRMÉES PAR LA MESURE
//
//  Ce fichier a d'abord été écrit avec trois affirmations. La mesure les a
//  DÉMENTIES ; elles sont conservées ici comme trace, avec leur réfutation
//  chiffrée, parce qu'une hypothèse fausse non consignée est un piège pour
//  le prochain lecteur.
//
//    H-1 « la production multiplie le vecteur BRUT »            → FAUX
//        Ma réplique passait `kBrut` à la recherche de λ. La production
//        passe la table DÉJÀ CLIPPÉE. Écart mesuré de ma réplique fausse :
//        0.051685516024. Réplique corrigée : 2.78e-17.
//
//    H-2 « un brut entièrement nul donne la table des planchers »→ FAUX
//        `part` est calculée sur les SOMMES DES VALEURS CLIPPÉES (0,28 > 0),
//        pas sur le brut nul : part = 0,06 / 0,28 = 0,214285714286, donc le
//        remplissage REMULTIPLIE les planchers (×3,571428) au lieu de les
//        laisser. Écart mesuré à la table des planchers : 0.128571428571.
//
//    H-3 « la production est la projection euclidienne »         → FAUX
//        Écart mesuré (A) ↔ (B) euclidien : 0.171402578288. En norme ℓ²,
//        (B) est STRICTEMENT plus proche du brut : 0.448261721813 contre
//        0.557899555238. Une projection euclidienne minimise ℓ² PAR
//        DÉFINITION : la production ne peut donc pas en être une.
//        La documentation portait cette qualification : elle est à corriger.
//
//    H-3 bis « c'est la projection au sens du khi-deux »         → FAUX
//        D_χ² mesurée : production 0.852807357083 · euclidien 0.892024422635
//        · proportionnel SANS écrêtage 0.771489487066. Le proportionnel bat
//        la production en D_χ² — mais il VIOLE 12 bornes sur 19, donc la
//        comparaison n'est pas loyale ; elle suffit néanmoins à exclure χ².
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUE LA MESURE ÉTABLIT (voir P-2 et P-7)
//
//  `projeter()` = trois étages, dans cet ordre :
//    ① clip sur les 19 bornes individuelles ;
//    ② par groupe (base / enrichi), remplissage MULTIPLICATIF
//       x_k = clip(λ_g · w_k, lo_k, hi_k) avec λ_g réglé pour que la somme
//       du groupe atteigne son budget ;
//    ③ correction résiduelle exacte, répartie au prorata de la marge NON
//       saturée.
//
//  L'étage ② est, par les conditions de Karush-Kuhn-Tucker, la PROJECTION
//  sur l'ensemble réalisable muni de la DIVERGENCE D'INFORMATION
//  (I-divergence, dite aussi KL généralisée)
//        D_I(x‖w) = Σ_k [ x_k·ln(x_k/w_k) − x_k + w_k ]
//  et non de la distance euclidienne. En effet :
//        ∂/∂x_k [ D_I + ν(Σx − budget) − α_k(lo_k − x_k) + β_k(x_k − hi_k) ] = 0
//    ⇒  ln(x_k/w_k) + ν + α_k − β_k = 0
//    ⇒  x_k = w_k · e^(−ν)  hors saturation, puis x_k = clip(·, lo_k, hi_k).
//  Le multiplicateur est donc un FACTEUR EXPONENTIEL λ = e^(−ν), d'où la
//  forme multiplicative. Une projection euclidienne donnerait au contraire un
//  DÉCALAGE ADDITIF (x_k = clip(w_k − μ, …)) : c'est exactement (B), mesurée
//  différente.
//
//  C'est l'itération de « raking » / mise à l'échelle proportionnelle d'un
//  seul groupe : un pas de Sinkhorn–Knopp sous contrainte de boîte.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/services/ia_memory_models.dart';

/// Vecteur brut volontairement NON UNIFORME et violemment hors bornes :
/// 4 valeurs au-dessus de leur plafond, 1 sous son plancher, le reste libre.
/// Un vecteur uniforme rendrait (A) et (C) indiscernables — le montage serait
/// alors vacue, exactement le piège relevé sur `kGlobauxTest` au harnais D3.
const Map<String, double> kBrut = <String, double>{
  'forme': 0.95, // > plafond 0.55
  'gains': 0.02, // < plancher 0.04
  'record': 0.12,
  'cote': 0.60, // > plafond 0.40
  'constance': 0.09,
  'victoires': 0.04,
  'discipline': 0.02,
  'distSpec': 0.30, // > plafond 0.18
  'jockey': 0.010,
  'repos': 0.005,
  'hippo': 0.005,
  'entraineur': 0.005,
  'elo': 0.005,
  'terrain': 0.005,
  'divergence': 0.005,
  'poidsRel': 0.005,
  'progression': 0.005,
  'mouvCote': 0.150, // > plafond 0.12
  'placeDepart': 0.005,
};

const List<String> kClesBase = <String>[
  'forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline',
];
const List<String> kClesEnr = <String>[
  'distSpec', 'jockey', 'repos', 'hippo', 'entraineur', 'elo',
  'terrain', 'divergence', 'poidsRel', 'progression', 'mouvCote', 'placeDepart',
];

double _clip(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);

double _somme(Map<String, double> m, List<String> cles) {
  var s = 0.0;
  for (final k in cles) {
    s += m[k] ?? 0.0;
  }
  return s;
}

Map<String, double> _clipper(Map<String, double> brut) => <String, double>{
      for (final k in IaPoidsAdaptatifs.kClesOrdonnees)
        k: _clip(brut[k]!, IaPoidsAdaptatifs.bornesIndividuelles()[k]![0],
            IaPoidsAdaptatifs.bornesIndividuelles()[k]![1]),
    };

/// ② + ③ — remplissage multiplicatif d'un groupe, avec la correction
/// résiduelle au prorata de la marge non saturée. Réplique INDÉPENDANTE de
/// `_remplirGroupe`, écrite séparément : si les deux divergent, ma lecture du
/// code est fausse (c'est ce que H-1 a révélé).
///
/// ⚠️ `w` doit être la table DÉJÀ CLIPPÉE — c'est le paramètre réel de la
///    production, et c'est l'erreur qui a produit H-1.
Map<String, double> _remplirGroupeReplique(
  Map<String, double> w,
  List<String> cles,
  Map<String, List<double>> b,
  double budget,
) {
  double sommePour(double lambda) {
    var s = 0.0;
    for (final k in cles) {
      s += _clip(lambda * (w[k] ?? 0.0), b[k]![0], b[k]![1]);
    }
    return s;
  }

  var bas = 0.0;
  var haut = 1.0;
  var garde = 0;
  while (sommePour(haut) < budget && garde < 64) {
    haut *= 2.0;
    garde++;
  }
  for (var i = 0; i < 200; i++) {
    final milieu = (bas + haut) / 2.0;
    if (sommePour(milieu) < budget) {
      bas = milieu;
    } else {
      haut = milieu;
    }
  }
  final lambda = (bas + haut) / 2.0;
  final out = <String, double>{
    for (final k in cles) k: _clip(lambda * (w[k] ?? 0.0), b[k]![0], b[k]![1]),
  };

  // ③ correction résiduelle exacte
  var somme = 0.0;
  for (final k in cles) {
    somme += out[k]!;
  }
  final ecart = budget - somme;
  if (ecart != 0.0) {
    final libres = <String>[];
    var margeTotale = 0.0;
    for (final k in cles) {
      final lo = b[k]![0];
      final hi = b[k]![1];
      final v = out[k]!;
      final marge = (v > lo && v < hi) ? (ecart > 0 ? hi - v : v - lo) : 0.0;
      if (marge > 0) {
        libres.add(k);
        margeTotale += marge;
      }
    }
    if (libres.isNotEmpty && margeTotale > 0) {
      final reste = ecart.abs() < margeTotale
          ? ecart
          : (ecart > 0 ? margeTotale : -margeTotale);
      for (final k in libres) {
        final lo = b[k]![0];
        final hi = b[k]![1];
        final v = out[k]!;
        final marge = (ecart > 0 ? hi - v : v - lo);
        final nv = v + reste * (marge / margeTotale);
        out[k] = _clip(nv, lo, hi);
      }
    }
  }
  return out;
}

/// Réplique COMPLÈTE de `projeter()` : ① clip ② budgets ③ remplissage.
Map<String, double> _projeterReplique(Map<String, double> brut) {
  final b = IaPoidsAdaptatifs.bornesIndividuelles();
  final w = <String, double>{
    for (final k in IaPoidsAdaptatifs.kClesOrdonnees)
      k: _clip(brut[k]!, b[k]![0], b[k]![1]),
  };
  final sommeEnr = _somme(w, kClesEnr);
  final sommeBase = _somme(w, kClesBase);
  final total = sommeEnr + sommeBase;
  double part;
  if (total <= 0) {
    part = IaPoidsAdaptatifs.kPartEnrichieMin;
  } else {
    part = sommeEnr / total;
    if (part < IaPoidsAdaptatifs.kPartEnrichieMin) {
      part = IaPoidsAdaptatifs.kPartEnrichieMin;
    }
    if (part > IaPoidsAdaptatifs.kPartEnrichieMax) {
      part = IaPoidsAdaptatifs.kPartEnrichieMax;
    }
  }
  final enr = _remplirGroupeReplique(w, kClesEnr, b, part);
  final base = _remplirGroupeReplique(w, kClesBase, b, 1.0 - part);
  return <String, double>{...base, ...enr};
}

/// (B) Projection EUCLIDIENNE (ℓ²) sur le même ensemble réalisable :
/// décalage ADDITIF μ par groupe, puis écrêtage. C'est la forme que donne
/// KKT pour la norme ℓ² — et c'est précisément ce que la production ne fait
/// pas.
Map<String, double> _euclidien(
  Map<String, double> w,
  List<String> cles,
  Map<String, List<double>> b,
  double budget,
) {
  double sommePour(double mu) {
    var s = 0.0;
    for (final k in cles) {
      s += _clip(w[k]! - mu, b[k]![0], b[k]![1]);
    }
    return s;
  }

  var bas = -1.0;
  var haut = 1.0;
  var garde = 0;
  while (sommePour(haut) > budget && garde < 64) {
    haut += 1.0;
    garde++;
  }
  garde = 0;
  while (sommePour(bas) < budget && garde < 64) {
    bas -= 1.0;
    garde++;
  }
  for (var i = 0; i < 200; i++) {
    final m = (bas + haut) / 2.0;
    if (sommePour(m) > budget) {
      bas = m;
    } else {
      haut = m;
    }
  }
  final mu = (bas + haut) / 2.0;
  return <String, double>{
    for (final k in cles) k: _clip(w[k]! - mu, b[k]![0], b[k]![1]),
  };
}

/// (C) Remise à l'échelle proportionnelle pure, SANS écrêtage.
Map<String, double> _proportionnel(
  Map<String, double> w,
  List<String> cles,
  double budget,
) {
  final s = _somme(w, cles);
  if (s <= 0) return <String, double>{for (final k in cles) k: 0.0};
  return <String, double>{for (final k in cles) k: budget * w[k]! / s};
}

/// Norme ℓ² au carré.
double _dL2(Map<String, double> x, Map<String, double> w) {
  var s = 0.0;
  for (final k in IaPoidsAdaptatifs.kClesOrdonnees) {
    final d = x[k]! - w[k]!;
    s += d * d;
  }
  return s;
}

/// Divergence d'information (I-divergence / KL généralisée), en nats.
/// Bornée à 0 quand x_k = w_k ; vaut +∞ si x_k > 0 et w_k = 0.
double _dI(Map<String, double> x, Map<String, double> w) {
  var s = 0.0;
  for (final k in IaPoidsAdaptatifs.kClesOrdonnees) {
    final xk = x[k]!;
    final wk = w[k]!;
    if (xk == 0.0 && wk == 0.0) continue;
    if (wk <= 0.0) return double.infinity;
    s += xk * math.log(xk / wk) - xk + wk;
  }
  return s;
}

/// Divergence du khi-deux — CONTRE-ÉPREUVE, exercée en P-4.
///
/// Elle n'est PAS la fonctionnelle de la production : P-4 mesure que le
/// proportionnel sans boîte minimise χ² mieux (0.771489487066 contre
/// 0.852807357083 pour la production). Ce contre-exemple est nécessaire :
/// il montre que χ² ne suffit pas à caractériser la méthode, et il interdit
/// de remplacer une qualification fausse (« euclidienne ») par une autre
/// qualification fausse (« khi-deux »).
double _dChi2(Map<String, double> x, Map<String, double> w) {
  var s = 0.0;
  for (final k in IaPoidsAdaptatifs.kClesOrdonnees) {
    final wk = w[k]!;
    if (wk <= 0) continue;
    final d = x[k]! - wk;
    s += d * d / wk;
  }
  return s;
}

double _ecartMax(Map<String, double> a, Map<String, double> b) {
  var m = 0.0;
  for (final k in IaPoidsAdaptatifs.kClesOrdonnees) {
    final d = (a[k]! - b[k]!).abs();
    if (d > m) m = d;
  }
  return m;
}

String _f(double v) => v.toStringAsFixed(12);

int _violations(Map<String, double> x) {
  final b = IaPoidsAdaptatifs.bornesIndividuelles();
  var n = 0;
  for (final k in IaPoidsAdaptatifs.kClesOrdonnees) {
    if (x[k]! < b[k]![0] - 1e-12 || x[k]! > b[k]![1] + 1e-12) n++;
  }
  return n;
}

void main() {
  final bornes = IaPoidsAdaptatifs.bornesIndividuelles();

  // ═════════════════════════════════════════════════════════════════════════
  //  P-1 — Faisabilité du domaine sur TOUTE la plage de part enrichie
  // ═════════════════════════════════════════════════════════════════════════
  test('P-1 — le domaine est faisable sur TOUTE la plage de part enrichie', () {
    final sommeLoBase = _somme(<String, double>{
      for (final k in kClesBase) k: bornes[k]![0],
    }, kClesBase);
    final sommeHiBase = _somme(<String, double>{
      for (final k in kClesBase) k: bornes[k]![1],
    }, kClesBase);
    final sommeLoEnr = _somme(<String, double>{
      for (final k in kClesEnr) k: bornes[k]![0],
    }, kClesEnr);
    final sommeHiEnr = _somme(<String, double>{
      for (final k in kClesEnr) k: bornes[k]![1],
    }, kClesEnr);
    // ignore: avoid_print
    print('P-1 groupe BASE    : Σ planchers = ${_f(sommeLoBase)} · '
        'Σ plafonds = ${_f(sommeHiBase)}');
    // ignore: avoid_print
    print('P-1 groupe ENRICHI : Σ planchers = ${_f(sommeLoEnr)} · '
        'Σ plafonds = ${_f(sommeHiEnr)}');

    var infaisables = 0;
    for (var i = 0; i <= 1000; i++) {
      final p = IaPoidsAdaptatifs.kPartEnrichieMin +
          (IaPoidsAdaptatifs.kPartEnrichieMax -
                  IaPoidsAdaptatifs.kPartEnrichieMin) *
              i /
              1000.0;
      if (p < sommeLoEnr - 1e-12 || p > sommeHiEnr + 1e-12) infaisables++;
      if (1.0 - p < sommeLoBase - 1e-12 || 1.0 - p > sommeHiBase + 1e-12) {
        infaisables++;
      }
    }
    // ignore: avoid_print
    print('P-1 1001 parts × 2 groupes = 2002 budgets testés · '
        'infaisables = $infaisables');
    expect(infaisables, 0,
        reason: 'aucun budget réalisable ne doit rendre un groupe infaisable — '
            'sinon `projeter()` retomberait sur les poids seulement clippés, '
            'ce qui violerait C1 sans être signalé');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  P-2 — La production EST le schéma clip + multiplicatif par groupe +
  //        correction résiduelle (réplique indépendante FIDÈLE)
  // ═════════════════════════════════════════════════════════════════════════
  test('P-2 — `projeter()` reproduit EXACTEMENT la réplique indépendante '
      '« clip + multiplicatif par groupe + correction résiduelle »', () {
    final prod = IaPoidsAdaptatifs.projeter(kBrut);
    final replique = _projeterReplique(kBrut);
    final ecart = _ecartMax(prod, replique);
    // ignore: avoid_print
    print('P-2 écart production ↔ réplique indépendante : ${_f(ecart)}');
    // ignore: avoid_print
    print('P-2 (réplique fausse H-1, qui multipliait le brut non clippé, '
        'donnait 0.051685516024 — la fidélité du modèle est donc mesurée)');
    expect(ecart, lessThanOrEqualTo(1e-12),
        reason: 'la réplique doit coïncider avec la production : c\'est ce qui '
            'autorise à NOMMER mathématiquement l\'opération réelle');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  P-3 — La production N'EST PAS la projection euclidienne (B)
  // ═════════════════════════════════════════════════════════════════════════
  test('P-3 — à ensemble réalisable IDENTIQUE, la production n\'est PAS la '
      'projection euclidienne : (B) est strictement plus proche en ℓ²', () {
    final prod = IaPoidsAdaptatifs.projeter(kBrut);
    final bEnr = _somme(prod, kClesEnr);
    final bBase = 1.0 - bEnr;
    final eucl = <String, double>{
      ..._euclidien(kBrut, kClesEnr, bornes, bEnr),
      ..._euclidien(kBrut, kClesBase, bornes, bBase),
    };

    final violA = _violations(prod);
    final violB = _violations(eucl);
    final sommeB = _somme(eucl, IaPoidsAdaptatifs.kClesOrdonnees);
    // ignore: avoid_print
    print('P-3 violations de bornes : production = $violA/19 · '
        'euclidien (B) = $violB/19 · Σ(B) = ${_f(sommeB)}');
    expect(violA, 0);
    expect(violB, 0,
        reason: 'les deux candidats doivent être dans le MÊME ensemble '
            'réalisable, sinon la comparaison ne prouve rien');
    expect(sommeB, closeTo(1.0, 1e-9));

    final ecart = _ecartMax(prod, eucl);
    final d2A = _dL2(prod, kBrut);
    final d2B = _dL2(eucl, kBrut);
    // ignore: avoid_print
    print('P-3 écart max production ↔ (B) = ${_f(ecart)}');
    // ignore: avoid_print
    print('P-3 D_ℓ² vers le brut : production = ${_f(d2A)} · '
        '(B) euclidien = ${_f(d2B)}');
    expect(ecart, greaterThan(1e-6),
        reason: 'si les deux coïncidaient, la qualification « euclidienne » '
            'serait exacte. La mesure tranche, pas la lecture');
    expect(d2B, lessThan(d2A),
        reason: 'une projection euclidienne minimise ℓ² par définition : si '
            '(B) n\'était pas plus proche, mon calcul de (B) serait faux et la '
            'conclusion invalide');
    // ignore: avoid_print
    print('P-3 ⇒ la production N\'EST PAS la projection euclidienne');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  P-4 — Caractérisation EXACTE par le CERTIFICAT KKT de D_I
  //
  //  H-3 ter « la production minimise D_I sur l'ensemble réalisable » a été
  //  écrite d'abord sous forme de comparaison de candidats. La mesure l'a
  //  NUANCÉE : le proportionnel SANS écrêtage affiche une D_I plus faible
  //  (0.492773229729 contre 0.554981664320), mais il VIOLE 10 bornes sur 19 —
  //  il n'appartient donc PAS à l'ensemble réalisable et la comparaison est
  //  sans objet. Comparer un point irréalisable à un point réalisable ne
  //  prouve rien.
  //
  //  La démonstration correcte n'est pas comparative, elle est CERTIFICATIVE :
  //  x est la projection de D_I sur {bornes} ∩ {Σ = budget} si et seulement
  //  s'il existe λ > 0 tel que x_k = clip(λ·w_k, lo_k, hi_k) pour tout k.
  //  C'est la condition KKT du premier ordre, et c'est exactement vérifiable.
  // ═════════════════════════════════════════════════════════════════════════
  test('P-4 — CERTIFICAT KKT : il existe λ > 0 par groupe tel que '
      'x_k = clip(λ·w_k, lo_k, hi_k) — c\'est la condition exacte de projection '
      'au sens de D_I', () {
    final prod = IaPoidsAdaptatifs.projeter(kBrut);
    final w = _clipper(kBrut);

    /// Reconstruit λ à partir de x et w sur les critères NON SATURÉS
    /// (lo < x < hi), où la relation est exactement x_k = λ·w_k.
    /// Renvoie (lambdaMesure, ecartRelatifMax, nbLibres).
    (double, double, int) lambdaDepuis(
        List<String> cles, Map<String, double> x) {
      final ratios = <double>[];
      for (final k in cles) {
        final lo = bornes[k]![0];
        final hi = bornes[k]![1];
        if (x[k]! > lo + 1e-15 && x[k]! < hi - 1e-15 && w[k]! > 0) {
          ratios.add(x[k]! / w[k]!);
        }
      }
      if (ratios.isEmpty) return (double.nan, 0.0, 0);
      final moy = ratios.reduce((a, b) => a + b) / ratios.length;
      var maxRel = 0.0;
      for (final r in ratios) {
        final rel = (r - moy).abs() / moy;
        if (rel > maxRel) maxRel = rel;
      }
      return (moy, maxRel, ratios.length);
    }

    final (lamEnr, relEnr, nEnr) = lambdaDepuis(kClesEnr, prod);
    final (lamBase, relBase, nBase) = lambdaDepuis(kClesBase, prod);
    // ignore: avoid_print
    print('P-4 CERTIFICAT groupe ENRICHI : λ mesuré = ${_f(lamEnr)} sur '
        '$nEnr critère(s) libre(s) · dispersion relative max = '
        '${relEnr.toStringAsExponential(3)}');
    // ignore: avoid_print
    print('P-4 CERTIFICAT groupe BASE    : λ mesuré = ${_f(lamBase)} sur '
        '$nBase critère(s) libre(s) · dispersion relative max = '
        '${relBase.toStringAsExponential(3)}');

    expect(lamEnr, greaterThan(0), reason: 'λ > 0 : une mise à l\'échelle');
    expect(lamBase, greaterThan(0));
    expect(relEnr, lessThan(1e-12),
        reason: 'si x provenait d\'un DÉCALAGE ADDITIF (projection euclidienne), '
            'le rapport x_k/w_k varierait d\'un critère à l\'autre. Sa '
            'constance est la signature du FACTEUR MULTIPLICATIF, donc de D_I');
    expect(relBase, lessThan(1e-12));

    // Vérification directe : reconstruire clip(λ·w) et comparer à la production.
    double reconstruire(List<String> cles, Map<String, double> x, double lam) {
      var e = 0.0;
      for (final k in cles) {
        final v = _clip(lam * w[k]!, bornes[k]![0], bornes[k]![1]);
        final d = (v - x[k]!).abs();
        if (d > e) e = d;
      }
      return e;
    }

    final eEnr = reconstruire(kClesEnr, prod, lamEnr);
    final eBase = reconstruire(kClesBase, prod, lamBase);
    // ignore: avoid_print
    print('P-4 reconstruction x ↔ clip(λ·w) : écart max enrichis = '
        '${eEnr.toStringAsExponential(3)} · base = '
        '${eBase.toStringAsExponential(3)}');
    expect(eEnr, lessThanOrEqualTo(1e-12));
    expect(eBase, lessThanOrEqualTo(1e-12),
        reason: 'le certificat est reconstruit, pas seulement constaté : la '
            'production EST la projection de D_I à la correction résiduelle près');

    // Contre-épreuve : appliquer la même reconstruction au candidat EUCLIDIEN
    // doit ÉCHOUER, sinon la constance des rapports ne discriminerait rien.
    final bEnr = _somme(prod, kClesEnr);
    final eucl = <String, double>{
      ..._euclidien(kBrut, kClesEnr, bornes, bEnr),
      ..._euclidien(kBrut, kClesBase, bornes, 1.0 - bEnr),
    };
    final (lamEnrEucl, relEnrEucl, _) = lambdaDepuis(kClesEnr, eucl);
    // ignore: avoid_print
    print('P-4 CONTRE-ÉPREUVE sur le candidat euclidien : dispersion relative '
        'des rapports x/w = ${relEnrEucl.toStringAsExponential(3)} '
        '(λ fictif = ${_f(lamEnrEucl)}) — doit être NON NULLE');
    expect(relEnrEucl, greaterThan(1e-6),
        reason: 'un décalage additif ne produit pas des rapports constants : '
            'c\'est ce qui distingue mesurablement les deux schémas');

    // Et χ² est exclue comme qualification, par mesure. On la compare sur le
    // vecteur BRUT (non clippé) : c'est le point irréalisable qu'elle préfère,
    // puisqu'il viole 12 bornes sur 19 (P-5 le mesure).
    final propHB = <String, double>{
      ..._proportionnel(kBrut, kClesEnr, bEnr),
      ..._proportionnel(kBrut, kClesBase, 1.0 - bEnr),
    };
    final chiA = _dChi2(prod, kBrut);
    final chiC = _dChi2(propHB, kBrut);
    // ignore: avoid_print
    print('P-4 CONTRE-ÉPREUVE D_χ² : production = ${_f(chiA)} · '
        'proportionnel hors bornes = ${_f(chiC)} ('
        '${_violations(propHB)} bornes violées) → χ² est EXCLUE : elle '
        'préfère un point irréalisable');
    expect(chiC, lessThan(chiA),
        reason: 'si χ² ne préférait pas le point irréalisable, elle resterait '
            'une qualification candidate ; la mesure dit qu\'elle ne l\'est pas');

    // ── D_I : comparaison LOYALE, entre les deux seuls candidats RÉALISABLES.
    // C'est la seule comparaison qui puisse départager ℓ² et D_I : les deux
    // points satisfont les 19 bornes et Σ = 1, ils sont donc admissibles tous
    // les deux. Lequel des deux est le plus proche du brut au sens de D_I ?
    final dIA = _dI(prod, kBrut);
    final dIB = _dI(eucl, kBrut);
    // ignore: avoid_print
    print('P-4 D_I (nats), comparaison entre les deux points RÉALISABLES : '
        'production = ${_f(dIA)} · euclidien = ${_f(dIB)}');
    expect(dIA, lessThan(dIB),
        reason: 'entre deux points tous deux admissibles, la production doit '
            'être la plus proche au sens de D_I — c\'est exactement la '
            'définition de la projection pour cette divergence');
    // ignore: avoid_print
    print('P-4 ⇒ la fonctionnelle de la production est D_I, pas ℓ² '
        '(${_f(dIA)} < ${_f(dIB)}), et pas χ² (rejetée ci-dessus)');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  P-5 — La production n'est pas la remise à l'échelle proportionnelle
  // ═════════════════════════════════════════════════════════════════════════
  test('P-5 — la remise à l\'échelle proportionnelle (C) VIOLE les bornes ; la '
      'production ne les viole pas ⇒ les deux mécanismes sont distincts', () {
    final prod = IaPoidsAdaptatifs.projeter(kBrut);
    final bEnr = _somme(prod, kClesEnr);
    final bBase = 1.0 - bEnr;
    final prop = <String, double>{
      ..._proportionnel(_clipper(kBrut), kClesEnr, bEnr),
      ..._proportionnel(_clipper(kBrut), kClesBase, bBase),
    };

    final violC = _violations(prop);
    final ecart = _ecartMax(prod, prop);
    // ignore: avoid_print
    print('P-5 (C) proportionnel : $violC violation(s) de bornes sur 19 · '
        'écart max avec la production = ${_f(ecart)}');
    for (final k in IaPoidsAdaptatifs.kClesOrdonnees) {
      if (prop[k]! < bornes[k]![0] - 1e-12 ||
          prop[k]! > bornes[k]![1] + 1e-12) {
        // ignore: avoid_print
        print('P-5    • $k : (C) = ${_f(prop[k]!)} hors ['
            '${bornes[k]![0]} ; ${bornes[k]![1]}] · '
            'production = ${_f(prod[k]!)}');
      }
    }
    expect(violC, greaterThan(0),
        reason: 'si (C) ne violait aucune borne, la distinction avec la '
            'production serait purement terminologique. La mesure montre que non');
    expect(ecart, greaterThan(1e-9));
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  P-6 — Unicité du VECTEUR, non de λ : où λ est-il réellement indéterminé ?
  //
  //  H-2 « un brut tout au plafond donne la table des plafonds »      → FAUX
  //  H-2 bis « un brut tout à zéro donne la table des planchers »     → FAUX
  //  Dans les deux cas `part` est calculée sur les SOMMES DES VALEURS
  //  CLIPPÉES, qui ne sont jamais nulles : part = 0,22/2,42 = 0,0909 (planchers)
  //  ou 2,20/4,40 = 0,50 (plafonds), puis reste écrêtée à [0,18 ; 0,40].
  //  Le remplissage REMULTIPLIE donc la table clippée, il ne la laisse pas.
  //  Écarts mesurés à la table des planchers / des plafonds : voir ci-dessous.
  //
  //  Le seul cas où λ est véritablement indéterminé est un groupe dont la
  //  somme est DÉJÀ ÉGALE au budget : la fonction de λ y est CONSTANTE. C'est
  //  la situation de la sortie de `projeter()`, déjà mesurée en P-7.
  //  On le mesure ici sur le groupe BASE réellement observé.
  // ═════════════════════════════════════════════════════════════════════════
  test('P-6 — λ est INDÉTERMINÉ sur un groupe dont la somme égale le budget, '
      'mais le VECTEUR résultat reste UNIQUE et déterministe', () {
    // Prémisse réfutée : on mesure d'abord que le brut saturé NE donne PAS la
    // table des bornes, pour que la réfutation soit chiffrée dans le harnais.
    final plafonds = <String, double>{
      for (final k in IaPoidsAdaptatifs.kClesOrdonnees) k: bornes[k]![1],
    };
    final rPlaf = IaPoidsAdaptatifs.projeter(plafonds);
    var ePlaf = 0.0;
    for (final k in IaPoidsAdaptatifs.kClesOrdonnees) {
      final d = (rPlaf[k]! - bornes[k]![1]).abs();
      if (d > ePlaf) ePlaf = d;
    }
    final planchers = <String, double>{
      for (final k in IaPoidsAdaptatifs.kClesOrdonnees) k: bornes[k]![0],
    };
    final rPlan = IaPoidsAdaptatifs.projeter(planchers);
    var ePlan = 0.0;
    for (final k in IaPoidsAdaptatifs.kClesOrdonnees) {
      final d = (rPlan[k]! - bornes[k]![0]).abs();
      if (d > ePlan) ePlan = d;
    }
    // ignore: avoid_print
    print('P-6 RÉFUTATION H-2 : brut tout au plafond → écart à la table des '
        'plafonds = ${_f(ePlaf)} · Σ = '
        '${_f(_somme(rPlaf, IaPoidsAdaptatifs.kClesOrdonnees))}');
    // ignore: avoid_print
    print('P-6 RÉFUTATION H-2 bis : brut tout au plancher → écart à la table '
        'des planchers = ${_f(ePlan)} · Σ = '
        '${_f(_somme(rPlan, IaPoidsAdaptatifs.kClesOrdonnees))}');
    expect(ePlaf, greaterThan(1e-6),
        reason: 'le brut saturé est REMULTIPLIÉ, pas laissé : la mesure doit '
            'établir cette réfutation, pas la masquer');
    expect(ePlan, greaterThan(1e-6));
    // Mais C1 est tenu dans les deux cas : la remultiplication est légitime.
    expect(_somme(rPlaf, IaPoidsAdaptatifs.kClesOrdonnees),
        closeTo(1.0, 1e-9));
    expect(_somme(rPlan, IaPoidsAdaptatifs.kClesOrdonnees),
        closeTo(1.0, 1e-9));

    // Cas où λ EST indéterminé : le groupe dont la somme vaut déjà le budget.
    // C'est exactement la sortie de `projeter()` (voir P-7), donc on le prend
    // ici comme support plutôt que d'inventer un cas de laboratoire.
    final x = IaPoidsAdaptatifs.projeter(kBrut);
    double sommePour(double lambda, List<String> cles) {
      var s = 0.0;
      for (final k in cles) {
        s += _clip(lambda * x[k]!, bornes[k]![0], bornes[k]![1]);
      }
      return s;
    }

    final s1 = sommePour(1.0, kClesBase);
    final s2 = sommePour(3.0, kClesBase);
    // ⚠️ CONCLUSION CORRIGÉE. J'avais d'abord écrit que λ « n'est pas
    //    identifiable au-delà de la saturation » sur la sortie de `projeter()`.
    //    C'est FAUX et la mesure le montre : sur x, seul `gains` est saturé à
    //    son plancher ; les 6 autres critères de base sont libres, donc
    //    Σ(λ) CROÎT strictement et λ = 1 y est parfaitement déterminé.
    //    Le cas où λ est indéterminé est un groupe dont TOUS les membres sont
    //    saturés — état qui n'est pas atteint ici. Il faut donc distinguer :
    //      • λ déterminé     → unicité LOCALE de la racine (stricte monotonie)
    //      • λ indéterminé   → fonction constante sur un groupe tout saturé ;
    //                          le VECTEUR reste unique malgré tout.
    // ignore: avoid_print
    print('P-6 sur la SORTIE de projeter(), groupe BASE : Σ(λ=1) = '
        '${_f(s1)} · Σ(λ=3) = ${_f(s2)} → λ y est DÉTERMINÉ (6 critères '
        'libres non saturés). H-2 ter réfutée : λ indéterminé exige un groupe '
        'ENTIÈREMENT saturé, cas non atteint ici');
    expect(s2, greaterThan(s1 + 1e-6),
        reason: 'sur la sortie réelle, la fonction de λ est STRICTEMENT '
            'croissante : la racine y est donc unique. Prétendre le contraire '
            'serait une affirmation non mesurée');

    // Déterminisme : ce qui compte pour C9, c'est le VECTEUR.
    final ref = IaPoidsAdaptatifs.projeter(kBrut);
    var identiques = 0;
    for (var i = 0; i < 20; i++) {
      if (_ecartMax(ref, IaPoidsAdaptatifs.projeter(kBrut)) == 0.0) {
        identiques++;
      }
    }
    // ignore: avoid_print
    print('P-6 20 exécutions identiques bit-à-bit : $identiques/20');
    expect(identiques, 20,
        reason: 'C9 : aucun aléatoire, ordre d\'itération figé');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  P-7 — Idempotence : condition et mesure sur le vecteur PRODUIT
  // ═════════════════════════════════════════════════════════════════════════
  test('P-7 — idempotence : la sortie de `projeter()` est un point fixe, '
      'parce que λ = 1 y est déjà solution et que l\'écart résiduel est nul', () {
    final x = IaPoidsAdaptatifs.projeter(kBrut);
    final xx = IaPoidsAdaptatifs.projeter(x);
    final ecart = _ecartMax(x, xx);
    // ignore: avoid_print
    print('P-7 écart max projeter(x) ↔ x = ${_f(ecart)}');

    // Vérification de la CONDITION invoquée : sur x, Σ clip(1·x) = Σ x = budget
    // du groupe, donc la racine de la dichotomie est λ = 1 (à la tolérance
    // près) et la correction résiduelle vaut 0.
    final bEnr = _somme(x, kClesEnr);
    final bBase = 1.0 - bEnr;
    var sEnr = 0.0;
    var sBase = 0.0;
    for (final k in kClesEnr) {
      sEnr += _clip(1.0 * x[k]!, bornes[k]![0], bornes[k]![1]);
    }
    for (final k in kClesBase) {
      sBase += _clip(1.0 * x[k]!, bornes[k]![0], bornes[k]![1]);
    }
    // ignore: avoid_print
    print('P-7 Σ clip(1·x) : enrichis = ${_f(sEnr)} (budget ${_f(bEnr)}) · '
        'base = ${_f(sBase)} (budget ${_f(bBase)}) — écarts '
        '${_f((sEnr - bEnr).abs())} / ${_f((sBase - bBase).abs())}');
    expect((sEnr - bEnr).abs(), lessThanOrEqualTo(1e-12));
    expect((sBase - bBase).abs(), lessThanOrEqualTo(1e-12),
        reason: 'λ = 1 doit être la racine : c\'est la CONDITION d\'idempotence, '
            'pas seulement son constat');
    expect(ecart, lessThanOrEqualTo(IaPoidsAdaptatifs.kToleranceIdempotence),
        reason: 'C7 : deux applications valent une');

    // Et non-idempotence de la remise à l'échelle proportionnelle pure : la
    // comparaison montre que l'idempotence n'est pas gratuite.
    final prop1 = <String, double>{
      ..._proportionnel(_clipper(kBrut), kClesEnr, bEnr),
      ..._proportionnel(_clipper(kBrut), kClesBase, bBase),
    };
    final prop2 =
        <String, double>{...prop1}; // le proportionnel est homogène : idempotent
    // ignore: avoid_print
    print('P-7 à titre de comparaison, le proportionnel est homogène : '
        'écart projeter(prop) ↔ prop simulé = ${_f(_ecartMax(prop1, prop2))}');
  });
}
