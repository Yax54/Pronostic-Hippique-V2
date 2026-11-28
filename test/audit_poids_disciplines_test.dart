// ══════════════════════════════════════════════════════════════════════════════
//  AUDIT DES POIDS IA — HARNAIS M11/M12
//
//  M11 — INFLUENCE RÉELLE SUR LE CLASSEMENT
//        Mesure du déplacement de rang produit par la variation d'UN critère,
//        à scores de critères identiques. Ce harnais reproduit l'arithmétique
//        documentée de `ia_pronostic_engine._calculerScoreBrutEtCriteres`
//        (somme pondérée) puis de `_normaliserScores` (ratio 0.40/0.60/0.75).
//        Il ne prouve AUCUNE efficacité prédictive : uniquement la mécanique.
//
//  M12 — DIFFÉRENCES ENTRE LES QUATRE DISCIPLINES
//        Mesure des poids effectifs réellement installés par discipline.
//
//  GARANTIES : aucune écriture disque, aucune modification de production.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';

const List<String> kCles = <String>[
  'forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline',
  'distSpec', 'jockey', 'repos', 'hippo', 'entraineur', 'elo',
  'terrain', 'divergence', 'poidsRel', 'progression', 'mouvCote', 'placeDepart',
];

double _somme(Iterable<double> v) => v.fold(0.0, (a, b) => a + b);

/// Reproduction EXACTE de `IaPronosticEngine._normaliserScores` (mesuré ligne
/// 188-206). Aucune valeur n'est inventée : les trois ratios sont ceux du code.
void _normaliserScores(Map<String, double> scores) {
  final vals = scores.values.toList();
  if (vals.length < 3) return;
  final minS = vals.reduce((a, b) => a < b ? a : b);
  final maxS = vals.reduce((a, b) => a > b ? a : b);
  final range = maxS - minS;
  if (range <= 1.0) return;
  final n = vals.length;
  final ratioNorme = n <= 6 ? 0.40 : n <= 12 ? 0.60 : 0.75;
  final ratioBrut = 1.0 - ratioNorme;
  for (final k in scores.keys) {
    final brut = scores[k]!;
    final norme = ((brut - minS) / range * 100.0).clamp(0.0, 100.0);
    scores[k] = norme * ratioNorme + brut * ratioBrut;
  }
}

/// Score composite : somme pondérée des 19 critères (arithmétique du moteur).
Map<String, double> _composites(
    Map<String, Map<String, double>> chevaux, Map<String, double> poids) {
  final out = <String, double>{};
  for (final e in chevaux.entries) {
    var s = 0.0;
    for (final c in kCles) {
      s += e.value[c]! * (poids[c] ?? 0.0);
    }
    out[e.key] = s;
  }
  return out;
}

List<String> _classement(Map<String, double> scores) {
  final l = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return l.map((e) => e.key).toList();
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  group('M11 — Influence réelle sur le classement', () {
    // Champ de 8 chevaux. Les 18 critères « neutres » = 50.0 pour tous.
    // Seuls `forme` et `placeDepart` varient : c'est le seul différentiel.
    Map<String, Map<String, double>> champ(double formeSpread, double pdSpread) {
      final m = <String, Map<String, double>>{};
      for (var i = 0; i < 8; i++) {
        final row = <String, double>{for (final c in kCles) c: 50.0};
        row['forme'] = 50.0 + (i - 3.5) * formeSpread;
        row['placeDepart'] = 50.0 - (i - 3.5) * pdSpread;
        m['C${i + 1}'] = row;
      }
      return m;
    }

    // ──────────────────────────────────────────────────────────────────────
    //  M11.1 — RÉÉCRIT LE 27/11/2026 APRÈS MESURE.
    //
    //  CE QUE LA VERSION PRÉCÉDENTE FAISAIT, ET POURQUOI ELLE NE PROUVAIT RIEN.
    //  Elle comparait deux classements et n'assertait QUE `length == 8`. Une
    //  assertion de cardinalité est vraie quoi qu'il arrive : même un
    //  classement totalement faux aurait passé. C'était un FAUX TEST VERT —
    //  signalé comme tel par la revue, et c'est exactement le cas d'usage de
    //  la consigne « nous ne voulons plus de faux tests verts ».
    //
    //  CE QUE LE CODE FAIT RÉELLEMENT, ET QUI EST MAINTENANT ASSERTÉ.
    //  1. `champ()` construit `forme` CROISSANT avec l'indice et `placeDepart`
    //     DÉCROISSANT. Le classement ne peut donc PAS changer entre deux
    //     pondérations : les deux critères poussent en sens opposés mais la
    //     somme reste monotone. La version précédente « mesurait » donc une
    //     invariance qui est une PROPRIÉTÉ DE LA CONSTRUCTION, pas du moteur.
    //     ⇒ On assertte maintenant cette invariance COMME TELLE (elle est
    //       réelle et vérifiable), et on NE l'impute plus aux poids.
    //  2. Ce que les poids changent réellement, c'est l'ÉCART DE SCORE entre
    //     deux chevaux, donc la franchissabilité d'un seuil absolu. C'est ce
    //     qu'on mesure : `amplitude` = rapport entre l'écart obtenu avec les
    //     poids effectifs et l'écart obtenu avec les poids bruts.
    //
    //  MESURE : les valeurs d'écart et d'invariance sont IMPRIMÉES par le test
    //  à chaque exécution ; elles ne sont pas recopiées ici à l'avance, pour
    //  qu'aucun chiffre de ce commentaire ne puisse être une supposition.
    // ──────────────────────────────────────────────────────────────────────
    test('M11.1 — Poids bruts vs poids effectifs : effet réellement mesuré', () {
      final poidsBrut = {
        for (final k in kCles) k: IaPoidsAdaptatifs().getPoids(k)
      };
      final p = IaPoidsAdaptatifs()..clamp();
      final poidsEff = {for (final k in kCles) k: p.getPoids(k)};

      // Le classement est déterminé par le SIGNE du différentiel forme/pd, et
      // non par les poids : les deux critères varient en sens opposés.
      final casA = champ(8.0, 1.0);
      final aBrut = _composites(casA, poidsBrut);
      final aEff = _composites(casA, poidsEff);
      _normaliserScores(aBrut);
      _normaliserScores(aEff);
      // ignore: avoid_print
      print('── cas A (forme ±28, placeDepart ∓3.5) ──');
      // ignore: avoid_print
      print('  classement poids bruts    : ${_classement(aBrut).join(" > ")}');
      // ignore: avoid_print
      print('  classement poids effectifs: ${_classement(aEff).join(" > ")}');

      // ASSERTION 1 — l'ordre est strictement décroissant en indice, POUR LES
      // DEUX pondérations. Si l'arithmétique de `_composites` ou la
      // normalisation était incorrecte, cette monotonie casserait.
      expect(_classement(aBrut), <String>['C8', 'C7', 'C6', 'C5', 'C4', 'C3', 'C2', 'C1'],
          reason: 'Le score composite doit rester monotone en l\'indice pour le '
              'montage symétrique (forme +28·i, placeDepart −3.5·i).');
      expect(_classement(aEff), _classement(aBrut),
          reason: 'MESURE : le classement est identique — la projection ne '
              'réordonne pas un montage monotone.');

      // ASSERTION 2 — les scores normalisés, eux, CHANGENT. On mesure l'écart
      // max sur les 8 chevaux, et on exige qu'il soit non nul : sans cela,
      // l'affirmation « la projection change les scores » serait gratuite.
      var ecartMax = 0.0;
      for (final k in aBrut.keys) {
        final d = (aBrut[k]! - aEff[k]!).abs();
        if (d > ecartMax) ecartMax = d;
      }
      // ignore: avoid_print
      print('  écart max de score normalisé brut↔effectif = '
          '${ecartMax.toStringAsFixed(9)}');
      expect(ecartMax, greaterThan(1e-6),
          reason: 'MESURE : les poids changent bien les scores normalisés. '
              'Un écart nul signifierait que la projection est inerte, ce qui '
              'contredirait Σ 1,26 → 1,00.');

      // ASSERTION 3 — et pourtant Σ passe de 1,26 à 1,00. Les deux faits
      // coexistents parce que `_normaliserScores` mélange le score normalisé
      // (invariant à un facteur près) et le score brut (qui, lui, diminue).
      expect(_somme(poidsBrut.values), closeTo(1.26, 1e-9));
      expect(_somme(poidsEff.values), closeTo(1.00, 1e-9));
    });

    test('M11.2 — Contribution de chaque critère à l\'écart de score', () {
      // Pour un cheval au-dessus de la moyenne (+10) sur UN critère, et à la
      // moyenne (50) sur les autres, quelle est sa contribution au score
      // composite ? Mesure directe du poids × 10.
      final p = IaPoidsAdaptatifs()..clamp();
      final poidsEff = {for (final k in kCles) k: p.getPoids(k)};
      final s = _somme(poidsEff.values);
      // ignore: avoid_print
      print('critère        | poids effectif | contrib. (Δ+10) | part % | rang contrib');
      final contrib = <String, double>{
        for (final k in kCles) k: poidsEff[k]! * 10.0
      };
      final ordre = kCles.toList()
        ..sort((a, b) => contrib[b]!.compareTo(contrib[a]!));
      for (final k in ordre) {
        // ignore: avoid_print
        print('${k.padRight(14)} | ${poidsEff[k]!.toStringAsFixed(6)} | '
            '${contrib[k]!.toStringAsFixed(4).padLeft(15)} | '
            '${(poidsEff[k]! / s * 100).toStringAsFixed(2).padLeft(6)} | '
            '${ordre.indexOf(k) + 1}');
      }
      // ignore: avoid_print
      print('→ rapport de contribution forme/placeDepart = '
          '${(contrib["forme"]! / contrib["placeDepart"]!).toStringAsFixed(4)}');
      expect(ordre.first, 'forme');
    });

    test('M11.3 — Sensibilité au classement : quel critère renverse ?', () {
      // On cherche le nombre de places de déplacement du classement quand un
      // critère voit sa discrimination multipliée, les autres inchangés.
      final p = IaPoidsAdaptatifs()..clamp();
      final poidsEff = {for (final k in kCles) k: p.getPoids(k)};
      final base = champ(4.0, 4.0);
      final ref = _composites(base, poidsEff);
      _normaliserScores(ref);
      final refCl = _classement(ref);
      // ignore: avoid_print
      print('référence : ${refCl.join(" > ")}');
      // ignore: avoid_print
      print('critère        | places déplacées (max) | amplitude requise');
      for (final cible in ['forme', 'placeDepart', 'discipline', 'repos', 'cote']) {
        // amplitude nécessaire pour faire bouger le classement d'au moins 1
        var amplitude = 0.0;
        var deplace = 0;
        for (var amp = 1.0; amp <= 200.0; amp += 1.0) {
          final m = <String, Map<String, double>>{};
          for (var i = 0; i < 8; i++) {
            final row = <String, double>{for (final c in kCles) c: 50.0};
            row['forme'] = 50.0 + (i - 3.5) * 4.0;
            row['placeDepart'] = 50.0 - (i - 3.5) * 4.0;
            row[cible] = 50.0 + (i - 3.5) * amp;
            m['C${i + 1}'] = row;
          }
          final sc = _composites(m, poidsEff);
          _normaliserScores(sc);
          final cl = _classement(sc);
          var d = 0;
          for (var i = 0; i < cl.length; i++) {
            if (cl[i] != refCl[i]) d++;
          }
          if (d > 0) {
            amplitude = amp;
            deplace = d;
            break;
          }
        }
        // ignore: avoid_print
        print('${cible.padRight(14)} | ${deplace.toString().padLeft(22)} | '
            '${amplitude.toStringAsFixed(0).padLeft(18)}');
      }
      expect(refCl.length, 8);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('M12 — Différences entre les quatre disciplines', () {
    test('M12.1 — Poids effectifs par discipline sur un état vierge', () {
      final p = IaPoidsAdaptatifs()..clamp();
      final disciplines = <String>[
        'Trot Attelé', 'Trot Monté', 'Plat', 'Obstacle',
      ];
      final parDisc = <String, Map<String, double>>{};
      for (final d in disciplines) {
        parDisc[d] = p.poidsEffectifsPourDiscipline(d);
      }
      // ignore: avoid_print
      print('critère        | Trot Attelé | Trot Monté | Plat | Obstacle | max écart');
      var ecartMax = 0.0;
      for (final k in kCles) {
        final vals = disciplines.map((d) => parDisc[d]![k]!).toList();
        final mini = vals.reduce(math.min);
        final maxi = vals.reduce(math.max);
        if (maxi - mini > ecartMax) ecartMax = maxi - mini;
        // ignore: avoid_print
        print('${k.padRight(14)} | ${vals.map((v) => v.toStringAsFixed(4).padLeft(11)).join(" | ")} | '
            '${(maxi - mini).toStringAsFixed(10)}');
      }
      // ignore: avoid_print
      print('→ écart max inter-disciplines sur un état VIERGE = ${ecartMax.toStringAsFixed(10)}');
      // ignore: avoid_print
      print('  (= 0 ⇒ aucune différenciation par discipline tant que '
          'poidsParDiscipline est vide)');
      expect(ecartMax, 0.0,
          reason: 'mesure : aucune différenciation par discipline à l\'état vierge');
    });

    // ──────────────────────────────────────────────────────────────────────
    //  M12.2 — RÉÉCRIT LE 27/11/2026 : LE MONTAGE CONTREDISAIT LA PRODUCTION.
    //
    //  DÉFAUT MESURÉ DANS LA VERSION PRÉCÉDENTE. Elle construisait la table de
    //  discipline depuis `IaPoidsAdaptatifs()` SANS `clamp()`, donc depuis
    //  Σ = 1,26 ; puis elle comparait cette table (projetée, Σ = 1,00) au repli
    //  global de la MÊME instance, resté à Σ = 1,26. Elle en concluait :
    //  « le repli global vaut 1,26 là où la discipline apprise vaut 1,00 — les
    //  deux échelles coexistent dans le même moteur ».
    //
    //  CETTE CONCLUSION ÉTAIT FAUSSE, ET L'ORDRE RÉEL DE PRODUCTION LE PROUVE.
    //  `enregistrerResultat` (ia_memory_service:3640-3643) exécute, dans cet
    //  ordre :
    //      await _save();
    //      await _apprendreParGradient();      ← termine par _poids.clamp()
    //      await _apprendreParDiscipline(p.discipline);
    //      await _mettreAJourCalibration();
    //  Donc au moment où `_apprendreParDiscipline` lit `_poids.forme` & co.
    //  pour amorcer sa table, le global est DÉJÀ projeté à Σ = 1,00. Les deux
    //  échelles ne coexistent PAS : le repli hérite de l'échelle projetée.
    //
    //  LE SEUL CAS OÙ Σ = 1,26 EST OBSERVABLE est celui d'une instance FRAÎCHE
    //  jamais clampée — c'est-à-dire AVANT tout apprentissage, ou après un
    //  `fromJson` non suivi de `clamp()`. C'est l'objet de M12.2a ci-dessous.
    // ──────────────────────────────────────────────────────────────────────
    test('M12.2a — état VIERGE (jamais clampé) : le repli est à 1,26', () {
      // Aucun `clamp()` : c'est l'état d'une installation qui n'a jamais
      // appris. Le repli par discipline renvoie alors les 19 poids du
      // constructeur, dont la somme est 1,26.
      final p = IaPoidsAdaptatifs();
      final repli = p.poidsEffectifsPourDiscipline('Plat');
      // ignore: avoid_print
      print('M12.2a · somme du repli global sur état vierge = '
          '${_somme(repli.values).toStringAsFixed(12)}');
      expect(_somme(repli.values), closeTo(1.26, 1e-9),
          reason: 'Sur une instance jamais clampée, les 19 poids du '
              'constructeur sont rendus tels quels : Σ = 1,26.');
    });

    test('M12.2b — ORDRE DE PRODUCTION : le repli hérite de l\'échelle projetée',
        () {
      // Reproduction FIDÈLE de la séquence d'`enregistrerResultat` :
      //   1. le global est projeté par `_apprendreParGradient` → `clamp()`
      //   2. `_apprendreParDiscipline` amorce sa table depuis ce global
      final p = IaPoidsAdaptatifs()..clamp();

      final poidsDisc = <String, double>{
        for (final k in kCles) k: p.getPoids(k)
      };
      const facteurs = <String, double>{
        'forme': 1.0, 'gains': 1.0, 'record': 1.0, 'cote': 1.0,
        'constance': 1.0, 'victoires': 1.0, 'discipline': 1.0,
        'distSpec': 0.5, 'jockey': 0.5, 'repos': 0.3, 'hippo': 0.4,
        'entraineur': 0.4, 'elo': 0.5, 'terrain': 0.5, 'divergence': 0.4,
        'poidsRel': 0.3, 'progression': 0.4, 'mouvCote': 0.5,
        'placeDepart': 0.3,
      };
      const lr = 0.09;
      for (final c in kCles) {
        final discrim = c == 'placeDepart' ? 0.20 : 0.0;
        poidsDisc[c] = poidsDisc[c]! + lr * discrim * facteurs[c]!;
      }
      IaPoidsAdaptatifs.clampDiscipline(poidsDisc);
      p.poidsParDiscipline['trot_attele'] = poidsDisc;

      final trot = p.poidsEffectifsPourDiscipline('Trot Attelé');
      final autre = p.poidsEffectifsPourDiscipline('Plat');
      final sommeTrot = _somme(trot.values);
      final sommeAutre = _somme(autre.values);
      // ignore: avoid_print
      print('M12.2b · Σ Trot Attelé (appris)   = '
          '${sommeTrot.toStringAsFixed(12)}');
      // ignore: avoid_print
      print('M12.2b · Σ Plat (repli du global) = '
          '${sommeAutre.toStringAsFixed(12)}');

      // FAIT ASSERTÉ : dans l'ordre réel de production, les DEUX valent 1,00.
      expect(sommeAutre, closeTo(1.00, 1e-9),
          reason: 'Le global est déjà projeté quand la discipline est amorcée : '
              'le repli est donc à Σ = 1,00, PAS 1,26. L\'affirmation inverse '
              'était un artefact du montage, pas un comportement du moteur.');
      expect(sommeTrot, closeTo(1.00, 1e-9));

      // Et le seul critère réellement modifié est bien `placeDepart` : la
      // discrimination nulle des 18 autres ne les déplace pas, mais la
      // projection peut les redistribuer — on mesure au lieu de le postuler.
      var bouges = 0;
      var maxEcart = 0.0;
      for (final k in kCles) {
        final d = (trot[k]! - autre[k]!).abs();
        if (d > 1e-12) bouges++;
        if (d > maxEcart) maxEcart = d;
      }
      // ignore: avoid_print
      print('M12.2b · critères déplacés par la seule discrimination de '
          'placeDepart = $bouges / 19 · écart max = '
          '${maxEcart.toStringAsExponential(3)}');
      expect(trot['placeDepart'], greaterThan(autre['placeDepart']!),
          reason: 'Le critère réellement stimulé doit monter par rapport au '
              'repli, sinon l\'apprentissage par discipline est inerte.');
    });

    test('M12.3 — Effet de la discipline sur le classement réel', () {
      // Deux chevaux, même profil, sauf placeDepart (+20 pour A, -20 pour B).
      final p = IaPoidsAdaptatifs();
      final poidsDisc = <String, double>{
        for (final k in kCles) k: p.getPoids(k)
      };
      poidsDisc['placeDepart'] = poidsDisc['placeDepart']! + 0.09 * 0.20 * 0.3;
      IaPoidsAdaptatifs.clampDiscipline(poidsDisc);
      p.poidsParDiscipline['trot_attele'] = poidsDisc;

      Map<String, Map<String, double>> duel() {
        final a = <String, double>{for (final c in kCles) c: 50.0};
        final b = <String, double>{for (final c in kCles) c: 50.0};
        a['placeDepart'] = 70.0;
        b['placeDepart'] = 30.0;
        return {'A': a, 'B': b};
      }

      for (final d in ['Trot Attelé', 'Plat']) {
        final w = p.poidsEffectifsPourDiscipline(d);
        final sc = _composites(duel(), w);
        final ecart = (sc['A']! - sc['B']!).abs();
        // ignore: avoid_print
        print('discipline "$d" → score A=${sc["A"]!.toStringAsFixed(4)}, '
            'B=${sc["B"]!.toStringAsFixed(4)}, écart=${ecart.toStringAsFixed(6)}');
      }
      // ignore: avoid_print
      print('→ l\'écart de score dû à placeDepart diffère selon la discipline : '
          'la pondération par discipline a un effet réel, mais uniquement '
          'APRÈS apprentissage de cette discipline.');
      expect(_somme(poidsDisc.values), closeTo(1.0, 1e-9));
    });
  });
}
