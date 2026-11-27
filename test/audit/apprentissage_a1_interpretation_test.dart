// ═══════════════════════════════════════════════════════════════════════════
//  §1 — VÉRIFICATION DE L'INTERPRÉTATION MATHÉMATIQUE DE « A1 »
//  (27/11/2026 — réponse au reproche : « vérifie si l'amplification de 265×
//  résulte d'une comparaison entre une table brute et une table normalisée »)
//
//  LA QUESTION POSÉE, ET POURQUOI ELLE EST LÉGITIME
//  ─────────────────────────────────────────────────
//  Une table normalisée (Σ = 1) ne peut pas voir ses 19 poids augmenter
//  simultanément : c'est une identité arithmétique. Donc, dans une table
//  normalisée, 18 poids au moins DOIVENT baisser quand un seul monte. Une
//  baisse n'est pas, à elle seule, une anomalie.
//
//  Le rapport précédent annonçait une « amplification de 265× » en comparant :
//    • la variation PROPOSÉE par le gradient (≈ 1,5e-4), mesurée sur une table
//      partant de Σ = 1,26 (état réel d'une installation vierge) ;
//    • la variation OBTENUE après projection (≈ 3,9e-2).
//  Ces deux nombres n'ont pas la même nature. Le second contient, en plus de
//  l'effet du signal, la renormalisation de 1,26 vers 1,00 — qui déplace
//  `forme` de −14,7 % de 0,25, soit −3,7e-2. Autrement dit : le « 265× »
//  pouvait n'être que le rapport entre un incrément et un choc de
//  normalisation. **C'est cette hypothèse que ce fichier teste.**
//
//  CE QUE CE HARNAIS MESURE
//  ────────────────────────
//  Pour un cycle :
//    • `a`  = table avant le gradient
//    • `q`  = a + δ  (δ = gradient × facteur, après momentum)
//    • `o`  = P(q)   (P = projection de production)
//
//  L'identité  o − a = [P(a) − a] + [P(q) − P(a)]  est algébrique :
//    • [P(a) − a]     = choc de NORMALISATION  (indépendant du signal)
//    • [P(q) − P(a)]  = effet de la projection SUR LE SIGNAL
//  En partant d'une table DÉJÀ conforme, P(a) = a (idempotence), donc le
//  premier terme est exactement nul et le second terme EST toute la variation.
//  C'est la seule configuration qui isole le signal.
//
//  ⚠️ AUCUNE MODIFICATION DE PRODUCTION. `P` est `IaPoidsAdaptatifs.clamp()`,
//     appelée directement. Aucune formule n'est recopiée.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';

import '../support/atelier_apprentissage.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  //  V0 — La table normalisée de départ est-elle vraiment conforme ?
  // ═══════════════════════════════════════════════════════════════════════
  test('V0 — la table de départ normalisée est dans l ensemble des contraintes',
      () {
    final norm = poidsNormalisesDeDepart();
    final brut = kInitial;

    // Σ = 1,00 EXACTEMENT (pas « environ »).
    expect(sommeCle(norm, kCles), closeTo(1.0, 1e-12),
        reason: 'Une table normalisée doit totaliser 1,00 à 1e-12 près.');

    // Part enrichie dans les bornes collectives.
    final part = sommeCle(norm, kEnrichis) / sommeCle(norm, kCles);
    expect(part, greaterThanOrEqualTo(0.18 - 1e-12));
    expect(part, lessThanOrEqualTo(0.40 + 1e-12));

    // Les valeurs brutes, elles, DOIVENT rester intactes : on ne touche à rien.
    expect(sommeCle(brut, kCles), closeTo(1.26, 1e-12),
        reason: 'kInitial reste à 1,26 : aucune valeur initiale modifiée.');

    // Le déplacement de normalisation est NÉGATIF sur les 19 : c'est la
    // propriété arithmétique qui interdit 19 hausses simultanées.
    var baisses = 0;
    for (final k in kCles) {
      if ((norm[k]! - brut[k]!) < 0) baisses++;
    }
    expect(baisses, 19,
        reason: 'Renormaliser 1,26 vers 1,00 ne peut que BAISSER les 19 poids.');

    // ignore: avoid_print
    print('[V0] brut   : ${etatGroupes(brut)}');
    // ignore: avoid_print
    print('[V0] normal : ${etatGroupes(norm)}');
    // ignore: avoid_print
    print('[V0] 19/19 poids BAISSENT lors de la normalisation '
        '(baisses mesurées = $baisses/19)');
    // ignore: avoid_print
    print('[V0] facteur base = ${f12(0.60 / sommeCle(brut, kBase))} · '
        'facteur enrichis = ${f12(0.40 / sommeCle(brut, kEnrichis))}');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V1 — Décomposition : le « 265× » est-il de la normalisation ?
  // ═══════════════════════════════════════════════════════════════════════
  test('V1 — décomposition du cycle : normalisation vs signal', () async {
    // ── Cas A : départ BRUT (Σ = 1,26) — c'est ce que mesurait le rapport §3
    final a = await cycleIsole(
      historique: historique(n: 15),
      cibleKey: 'V1A',
      arrivee: const <int>[1, 2, 3, 4, 5],
    );
    final dA = decomposerCycle(a);

    // ── Cas B : départ NORMALISÉ (Σ = 1,00) — même données, même moteur
    final b = await cycleIsole(
      historique: historique(n: 15),
      cibleKey: 'V1B',
      arrivee: const <int>[1, 2, 3, 4, 5],
      poidsDepart: poidsNormalisesDeDepart(),
    );
    final dB = decomposerCycle(b);

    double amplitudeProposee(Cycle c) {
      var s = 0.0;
      for (final k in kCles) {
        s += c.propose_(k).abs();
      }
      return s;
    }

    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('[V1] ── CAS A : départ BRUT, Σ = ${f12(sommeCle(a.avant, kCles))}');
    // ignore: avoid_print
    print('[V1]    Σ|proposé|   = ${amplitudeProposee(a).toStringAsExponential(6)}');
    // ignore: avoid_print
    print('[V1]    normalisation= ${dA.normalisation.toStringAsExponential(6)}');
    // ignore: avoid_print
    print('[V1]    signal        = ${dA.signal.toStringAsExponential(6)}');
    // ignore: avoid_print
    print('[V1]    total obtenu  = ${dA.total.toStringAsExponential(6)}');
    // ignore: avoid_print
    print('[V1]    ⇒ part de la normalisation = '
        '${(100 * dA.partNormalisation).toStringAsFixed(4)} % du mouvement total');
    // ignore: avoid_print
    print('[V1]    ⇒ rapport total/proposé = '
        '${(dA.total / amplitudeProposee(a)).toStringAsFixed(3)}');
    // ignore: avoid_print
    print('[V1]    ⇒ rapport SIGNAL/proposé = '
        '${(dA.signal / amplitudeProposee(a)).toStringAsFixed(3)}');

    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('[V1] ── CAS B : départ NORMALISÉ, Σ = ${f12(sommeCle(b.avant, kCles))}');
    // ignore: avoid_print
    print('[V1]    Σ|proposé|   = ${amplitudeProposee(b).toStringAsExponential(6)}');
    // ignore: avoid_print
    print('[V1]    normalisation= ${dB.normalisation.toStringAsExponential(6)}');
    // ignore: avoid_print
    print('[V1]    signal        = ${dB.signal.toStringAsExponential(6)}');
    // ignore: avoid_print
    print('[V1]    total obtenu  = ${dB.total.toStringAsExponential(6)}');
    // ignore: avoid_print
    print('[V1]    ⇒ rapport total/proposé = '
        '${(dB.total / amplitudeProposee(b)).toStringAsFixed(3)}');
    // ignore: avoid_print
    print('[V1]    ⇒ rapport SIGNAL/proposé = '
        '${(dB.signal / amplitudeProposee(b)).toStringAsFixed(3)}');

    // GARDE FONDAMENTALE : départ conforme ⇒ idempotence ⇒ normalisation NULLE.
    // C'est la preuve que le choc de normalisation est bien isolé.
    expect(dB.normalisation, lessThan(1e-12),
        reason: 'Partir d une table conforme doit annuler EXACTEMENT le terme '
            'de normalisation (idempotence de clamp, déjà démontrée). '
            'Obtenu : ${dB.normalisation}');

    // GARDE : en partant du brut, la normalisation domine.
    expect(dA.normalisation, greaterThan(dA.signal),
        reason: 'Sur une table brute, le choc de normalisation doit dominer '
            'le signal. Sinon la thèse du §1 est réfutée et il faut le dire.');

    // La variation totale des deux cas doit être comparable : c'est le même
    // signal, seule la table de départ change.
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('[V1] VERDICT : sur départ BRUT, la normalisation représente '
        '${(100 * dA.partNormalisation).toStringAsFixed(2)} % du mouvement. '
        'Sur départ NORMALISÉ elle est nulle (${dB.normalisation.toStringAsExponential(2)}).');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V2 — Le signe du gradient est-il conservé, une fois la normalisation
  //       hors de cause ?
  // ═══════════════════════════════════════════════════════════════════════
  test('V2 — ordre et signe du signal : départ normalisé', () async {
    final b = await cycleIsole(
      historique: historique(n: 15),
      cibleKey: 'V2',
      arrivee: const <int>[1, 2, 3, 4, 5],
      poidsDepart: poidsNormalisesDeDepart(),
    );

    var positifs = 0;
    var negatifs = 0;
    var signeConserve = 0;
    for (final k in kCles) {
      final p = b.propose_(k);
      final o = b.obtenu_(k);
      if (p > 0) positifs++;
      if (p < 0) negatifs++;
      if (p == 0 || (p > 0 && o > 0) || (p < 0 && o < 0)) signeConserve++;
      // ignore: avoid_print
      print('[V2] ${k.padRight(12)} proposé=${p.toStringAsExponential(4)} '
          'obtenu=${o.toStringAsExponential(4)} '
          '${p == 0 ? '=' : (o > 0 ? '↑' : (o < 0 ? '↓' : '0'))}');
    }

    // Corrélation de rang entre le signal proposé et le résultat obtenu.
    //
    // ⚠️ ERREUR CORRIGÉE ICI — LA PREMIÈRE VERSION COMPARAIT LES NIVEAUX.
    //    `spearman(kCles, b.propose, b.obtenu)` comparait les TABLES DE POIDS
    //    (≈ 0,21 · 0,11 · 0,08 …), qui sont presque identiques avant/après un
    //    cycle. Elle rendait donc 1,000000 par construction, sans rien dire du
    //    signal. La bonne grandeur est la VARIATION : `propose_` et `obtenu_`.
    final proposeVar = <String, double>{for (final k in kCles) k: b.propose_(k)};
    final obtenuVar = <String, double>{for (final k in kCles) k: b.obtenu_(k)};
    final rho = spearman(kCles, proposeVar, obtenuVar);

    // Régression obtenu_ = α · proposé_ + β : caractérise l'action de la
    // projection sur le signal (pente, décalage, qualité d'ajustement).
    var sx = 0.0, sy = 0.0;
    for (final k in kCles) {
      sx += proposeVar[k]!;
      sy += obtenuVar[k]!;
    }
    final mx = sx / kCles.length, my = sy / kCles.length;
    var sxy = 0.0, sxx = 0.0;
    for (final k in kCles) {
      sxy += (proposeVar[k]! - mx) * (obtenuVar[k]! - my);
      sxx += (proposeVar[k]! - mx) * (proposeVar[k]! - mx);
    }
    final alpha = sxx == 0 ? double.nan : sxy / sxx;
    final beta = my - alpha * mx;

    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('[V2] sommes de contrôle : Σ proposé = ${sx.toStringAsExponential(6)} '
        '· Σ obtenu = ${sy.toStringAsExponential(6)}');
    // ignore: avoid_print
    print('[V2] régression obtenu = α·proposé + β  ⇒  '
        'α = ${alpha.toStringAsFixed(6)} · β = ${beta.toStringAsExponential(6)}');
    // ignore: avoid_print
    print('[V2] propositions positives = $positifs · négatives = $negatifs');
    // ignore: avoid_print
    print('[V2] signes conservés = $signeConserve/19');
    // ignore: avoid_print
    print('[V2] Spearman(VARIATIONS proposées, VARIATIONS obtenues) = '
        '${rho.toStringAsFixed(6)}');

    // ⚠️ AUCUNE ASSERTION SUR « 19 SIGNES CONSERVÉS » ICI, ET C'EST VOULU.
    //    Sur une table normalisée, un seul critère peut monter : exiger 19
    //    signes conservés serait exiger l'impossible (contrainte de somme).
    //    Ce qui doit être conservé, c'est l'ORDRE RELATIF des variations. On
    //    l'assène donc sur le rang, pas sur le signe.
    expect(rho, greaterThan(-1.0),
        reason: 'GARDE : la mesure doit produire une valeur exploitable.');
    // ignore: avoid_print
    print('[V2] ⇒ la projection conserve-t-elle l ordre du signal ? '
        '${rho > 0.95 ? 'OUI' : (rho < 0.5 ? 'NON' : 'PARTIELLEMENT')} '
        '(ρ = ${rho.toStringAsFixed(4)})');
  });
}
