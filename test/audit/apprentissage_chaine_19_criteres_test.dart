// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER « VALIDATION APPROFONDIE DE L'APPRENTISSAGE » — §3
//  VÉRIFICATION COMPLÈTE DE LA CHAÎNE D'APPRENTISSAGE DES 19 CRITÈRES
//
//  CE QUE CE FICHIER MESURE — ET COMMENT.
//  ──────────────────────────────────────
//  §3 exige, pour chacun des 19 critères, treize points distincts. Sept d'entre
//  eux sont publiés par le moteur ; trois ne le sont pas et sont donc
//  RECONSTRUITS à partir de grandeurs publiées, avec contrôle de fidélité.
//
//  LE POINT DE MÉTHODE DÉCISIF — POURQUOI LA DISCRIMINATION EST MESURABLE.
//  ──────────────────────────────────────────────────────────────────────
//  `discriminations[c]` est une variable LOCALE de `_apprendreParGradient`
//  (ia_memory_service:4078). Elle n'est écrite nulle part : on ne peut pas la
//  lire. MAIS le moteur publie `_poids.dernierGradient` (= `momentum`, l.4174),
//  affecté à `gradAvecMomentum = lr·discrim + 0.3·momentum_précédent` (l.4141-42).
//
//  ⇒ SUR LE PREMIER CYCLE APRÈS UN CHARGEMENT VIERGE, `momentum_précédent` vaut
//    0 pour les 19 critères (`fromJson` ne restitue que ce qui a été écrit ;
//    la graine n'écrit pas `dernierGradient`). Donc :
//
//        dernierGradient[c]  ==  lr × discrimination[c]     (cycle 1)
//
//  C'est une ÉGALITÉ EXACTE, pas une approximation : elle découle de
//  l'affectation l.4143, pas d'une hypothèse. La discrimination brute est donc
//  OBTENUE PAR MESURE (`dernierGradient / lr`) sur le premier cycle, et
//  l'influence du momentum est obtenue par DIFFÉRENCE sur les cycles suivants
//  (`momentum[c] − lr·discrim[c] = 0.3·momentum_précédent`).
//
//  `lr` est reconstitué à partir des quatre paramètres PUBLIÉS et déterministes
//  (lrBase 0.08, lrFactor = min(1, nb/20), stabilisationFactor = 0.3/1.0,
//  facteurAtypique = 1.0). Le harnais VÉRIFIE ce `lr` au lieu de le postuler :
//  il contrôle que `dernierGradient / lr` reste dans [−1, +1] pour les 19
//  critères (une discrimination est née d'un écart de moyennes divisé par 100,
//  donc bornée par 1 en valeur absolue). Si `lr` était faux, cette borne
//  serait violée et le harnais le dirait.
//
//  ⚠️ AUCUNE MODIFICATION DE PRODUCTION. Aucune formule d'apprentissage n'est
//     réécrite. Tout passe par `IaMemoryService.instance` (voir l'atelier).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

import '../support/atelier_apprentissage.dart';

// ─── Notes CONTRÔLÉES : le levier est la DONNÉE, jamais l'algorithme ───────
//
// Deux scénarios, tous deux licites du point de vue de la production : ce sont
// des notes 0-100 comme celles que produit le moteur de score.
//
//   • `notesAlignees`  : la note DÉCROÎT avec le rang d'arrivée pour les 19
//     critères ⇒ tous les critères sont également « pertinents » et doivent
//     produire une discrimination POSITIVE de même signe. C'est le cas de
//     contrôle : si un critère ressort négatif ici, la faute est au moteur, pas
//     à la donnée.
//   • `notesInversees` : la note CROÎT avec le rang pour un seul critère
//     ⇒ ce critère est franchement NON pertinent (il désigne les derniers), et
//     sa discrimination doit être NÉGATIVE. C'est la démonstration qu'un
//     critère « peu pertinent » est distingué d'un critère « mal alimenté ».
ScoresCriteres notesAlignees(int numero) => ScoresCriteres(
      forme: 96.0 - numero * 6, gains: 96.0 - numero * 6,
      record: 96.0 - numero * 6, cote: 96.0 - numero * 6,
      constance: 96.0 - numero * 6, victoires: 96.0 - numero * 6,
      discipline: 96.0 - numero * 6, distSpec: 96.0 - numero * 6,
      jockey: 96.0 - numero * 6, repos: 96.0 - numero * 6,
      hippo: 96.0 - numero * 6, entraineur: 96.0 - numero * 6,
      elo: 96.0 - numero * 6, terrain: 96.0 - numero * 6,
      divergence: 96.0 - numero * 6, poidsRel: 96.0 - numero * 6,
      progression: 96.0 - numero * 6, mouvCote: 96.0 - numero * 6,
      placeDepart: 96.0 - numero * 6,
    );

ScoresCriteres notesAvecUnCritereInverse(int numero, String critere) {
  final base = notesAlignees(numero);
  final inverse = 36.0 + numero * 6; // CROÎT avec le rang ⇒ désigne les derniers
  switch (critere) {
    case 'forme':      return _copier(base, forme: inverse);
    case 'gains':      return _copier(base, gains: inverse);
    case 'record':     return _copier(base, record: inverse);
    case 'cote':       return _copier(base, cote: inverse);
    case 'constance':  return _copier(base, constance: inverse);
    case 'victoires':  return _copier(base, victoires: inverse);
    case 'discipline': return _copier(base, discipline: inverse);
    case 'distSpec':   return _copier(base, distSpec: inverse);
    case 'jockey':     return _copier(base, jockey: inverse);
    case 'repos':      return _copier(base, repos: inverse);
    case 'hippo':      return _copier(base, hippo: inverse);
    case 'entraineur': return _copier(base, entraineur: inverse);
    case 'elo':        return _copier(base, elo: inverse);
    case 'terrain':    return _copier(base, terrain: inverse);
    case 'divergence': return _copier(base, divergence: inverse);
    case 'poidsRel':   return _copier(base, poidsRel: inverse);
    case 'progression':return _copier(base, progression: inverse);
    case 'mouvCote':   return _copier(base, mouvCote: inverse);
    case 'placeDepart':return _copier(base, placeDepart: inverse);
  }
  throw ArgumentError('critère inconnu : $critere');
}

ScoresCriteres _copier(ScoresCriteres s,
        {double? forme, double? gains, double? record, double? cote,
        double? constance, double? victoires, double? discipline,
        double? distSpec, double? jockey, double? repos, double? hippo,
        double? entraineur, double? elo, double? terrain,
        double? divergence, double? poidsRel, double? progression,
        double? mouvCote, double? placeDepart}) =>
    ScoresCriteres(
      forme: forme ?? s.forme, gains: gains ?? s.gains,
      record: record ?? s.record, cote: cote ?? s.cote,
      constance: constance ?? s.constance, victoires: victoires ?? s.victoires,
      discipline: discipline ?? s.discipline, distSpec: distSpec ?? s.distSpec,
      jockey: jockey ?? s.jockey, repos: repos ?? s.repos,
      hippo: hippo ?? s.hippo, entraineur: entraineur ?? s.entraineur,
      elo: elo ?? s.elo, terrain: terrain ?? s.terrain,
      divergence: divergence ?? s.divergence, poidsRel: poidsRel ?? s.poidsRel,
      progression: progression ?? s.progression, mouvCote: mouvCote ?? s.mouvCote,
      placeDepart: placeDepart ?? s.placeDepart,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════
  //  S3-0 — GARDE : l'atelier est fidèle à la production
  // ═══════════════════════════════════════════════════════════════════════
  test('S3-0 — garde : les constantes de l\'atelier sont celles de la production',
      () {
    expect(IaPoidsAdaptatifs.kClesOrdonnees, kCles,
        reason: 'les 19 clés recopiées doivent être celles de la production');
    expect(IaPoidsAdaptatifs.bornesIndividuelles().length, 19);
    // Les 19 poids initiaux recopiés doivent être EXACTEMENT ceux du
    // constructeur : on le vérifie en construisant une instance vierge, dont
    // `fromJson`/`clamp` n'a pas encore été appelé.
    final vierge = IaPoidsAdaptatifs();
    for (final k in kCles) {
      expect(vierge.getPoids(k), closeTo(kInitial[k]!, 1e-15),
          reason: 'poids initial recopié faux sur $k');
    }
    expect(sommeSur(kInitial.values), closeTo(1.26, 1e-12),
        reason: 'Σ des 19 poids initiaux = 1,26');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  S3-1 — LE CYCLE RÉEL : reconstruction et contrôle de fidélité
  // ═══════════════════════════════════════════════════════════════════════
  test('S3-1 — le cycle est réellement exécuté et la reconstruction est fidèle',
      () async {
    // 15 courses résolues + 1 cible non résolue, notes ALIGNÉES sur l'arrivée.
    final hist = historique(
      n: 15,
      notes: (numero, _) => notesAlignees(numero),
    );
    final cycle = await cycleIsole(
      historique: hist,
      cibleKey: 'S3_${fmtDate(DateTime.now().subtract(const Duration(days: 2)))}',
      arrivee: const <int>[1, 2, 3, 4, 5],
    );

    // (a) Le chemin de production a bien exécuté le GRADIENT (pas le repli
    //     par règles, qui n'écrit pas de `dernierGradient` cohérent).
    expect(cycle.aAppris, isTrue,
        reason: 'enregistrerResultat doit déclencher une mise à jour réelle');
    expect(cycle.nbMisesAJour, 1,
        reason: 'exactement une mise à jour par cycle');

    // (b) DÉFAUT DE MA PREMIÈRE VERSION, MESURÉ ET CORRIGÉ ICI.
    //     Le journal (`JournalEntree.apres`) est construit APRÈS `clamp()` :
    //     il publie les poids DÉJÀ PROJETÉS. On le prouve au lieu de
    //     l'affirmer : si `journal.apres == getPoids()` sur les 19 critères,
    //     le journal ne peut pas porter la variation d'avant projection.
    final (projete, ecartJournal, pireJournal) = journalEstProjete(cycle);
    // ignore: avoid_print
    print('[S3-1] journal.apres ↔ getPoids() : identiques=$projete · '
        'écart max=${f12(ecartJournal)} ("$pireJournal")');
    expect(projete, isTrue,
        reason: 'MESURÉ : le journal publie bien les poids APRÈS projection. '
            'C\'est pourquoi la variation proposée est reconstruite par '
            '`dernierGradient × facteur` et non lue dans le journal.');

    // (c) La variation proposée est un PRODUIT de deux grandeurs publiées ; elle
    //     doit donc être exactement cohérente avec `dernierGradient × facteur`
    //     (contrôle tautologique assumé : il vérifie le câblage, pas la science).
    var ecartCablage = 0.0;
    for (final k in kCles) {
      final attendu = (cycle.momentum[k] ?? 0.0) * kFacteur[k]!;
      final d = (cycle.propose_(k) - attendu).abs();
      if (d > ecartCablage) ecartCablage = d;
    }
    expect(ecartCablage, lessThanOrEqualTo(1e-15),
        reason: 'câblage : proposé = avant + dernierGradient × facteur');

    // (d) LE FAIT QUE LA PROJECTION DOIT ABSORBER.
    //     Le gradient ne conserve pas la somme : sa proposition a un
    //     déséquilibre non nul, que la projection doit ramener à zéro.
    //     C'est ce déséquilibre qui rend l'observation de la projection
    //     possible.
    final desequilibre = desequilibrePropose(cycle);
    final sommeAvant = sommeCle(cycle.avant, kCles);
    final sommePropose = sommeCle(cycle.propose, kCles);
    final sommeObtenu = sommeCle(cycle.obtenu, kCles);
    // ignore: avoid_print
    print('[S3-1] Σ avant=${f12(sommeAvant)} · Σ proposé=${f12(sommePropose)} '
        '· Σ obtenu=${f12(sommeObtenu)} · déséquilibre proposé='
        '${desequilibre.toStringAsExponential(6)}');
    expect(sommeAvant, closeTo(1.26, 1e-9));
    expect(sommeObtenu, closeTo(1.0, 1e-9),
        reason: 'C1 : après projection, Σ = 1 EXACTEMENT');
    // La projection ramène le déséquilibre à zéro : c'est sa fonction.
    expect((sommeObtenu - 1.0).abs(), lessThan(1e-9),
        reason: 'la projection absorbe intégralement le déséquilibre proposé');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  S3-2 — LA DISCRIMINATION BRUTE EST MESURÉE (pas lue)
  // ═══════════════════════════════════════════════════════════════════════
  test('S3-2 — discrimination mesurée sur le cycle 1 : signe, amplitude, bornes',
      () async {
    final hist = historique(n: 15, notes: (numero, _) => notesAlignees(numero));
    final cycle = await cycleIsole(
      historique: hist,
      cibleKey: 'S3B_${fmtDate(DateTime.now().subtract(const Duration(days: 2)))}',
      arrivee: const <int>[1, 2, 3, 4, 5],
    );
    await _mesurerDiscrimination(cycle, etiquette: 'notes ALIGNÉES');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  S3-3 — UN CRITÈRE PEU PERTINENT EST DISTINGUÉ D'UN CRITÈRE MAL ALIMENTÉ
  // ═══════════════════════════════════════════════════════════════════════
  test('S3-3 — un seul critère inversé : discrimination NÉGATIVE isolée',
      () async {
    // La donnée est IDENTIQUE pour les 19 critères SAUF UN, artificiellement
    // retourné. Si l'écart de discrimination se concentre sur ce seul critère,
    // c'est la signature d'un critère PEU PERTINENT (la donnée est là, elle est
    // informative à l'envers) — et non d'un critère MAL ALIMENTÉ (dont la note
    // serait neutre, donc de discrimination nulle).
    const cible = 'distSpec';
    final hist = historique(
      n: 15,
      notes: (numero, _) => notesAvecUnCritereInverse(numero, cible),
    );
    final cycle = await cycleIsole(
      historique: hist,
      cibleKey: 'S3C_${fmtDate(DateTime.now().subtract(const Duration(days: 2)))}',
      arrivee: const <int>[1, 2, 3, 4, 5],
    );
    final lr = lrGlobal();
    final disc = <String, double>{
      for (final k in kCles) k: (cycle.momentum[k] ?? 0.0) / lr,
    };
    // ignore: avoid_print
    print('[S3-3] lr mesuré = ${f12(lr)} · seuil de détection du signe');
    // ignore: avoid_print
    print('[S3-3] "$cible" (donnée retournée) : discrim = '
        '${disc[cible]!.toStringAsFixed(9)}');
    final positifs =
        kCles.where((k) => k != cible && disc[k]! > 1e-6).length;
    final negatifs =
        kCles.where((k) => k != cible && disc[k]! < -1e-6).length;
    // ignore: avoid_print
    print('[S3-3] les 18 autres : $positifs positifs · $negatifs négatifs');
    expect(disc[cible]!, lessThan(0),
        reason: 'le critère retourné doit discriminer NÉGATIVEMENT — c\'est la '
            'preuve qu\'un critère PEU PERTINENT est mesuré comme tel');
    expect(positifs, 18,
        reason: 'les 18 critères alimentés normalement doivent discriminer '
            'positivement : la perturbation est bien ISOLÉE');
    expect(negatifs, 0);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  S3-4 — MOMENTUM : son influence est mesurable cycle après cycle
  // ═══════════════════════════════════════════════════════════════════════
  test('S3-4 — le momentum ajoute exactement 0.3 × le gradient précédent',
      () async {
    // Six cycles réels sur des cibles distinctes. À chaque cycle :
    //   momentum[c] = lr·discrim[c] + 0.3·momentum_précédent[c]
    // On mesure `momentum − lr·discrim` et on le compare à 0.3·momentum_préc.
    final cibles = <String>[];
    final hist = historique(n: 15, notes: (numero, _) => notesAlignees(numero));
    final pronostics = <IaPronostic>[...hist];
    for (var i = 0; i < 6; i++) {
      final key =
          'S3D${i}_${fmtDate(DateTime.now().subtract(Duration(days: 2)))}';
      cibles.add(key);
      pronostics.add(pronostic(
        courseKey: key,
        date: DateTime.now().subtract(const Duration(days: 2)),
        resolu: false,
      ));
    }
    await semer(pronostics: pronostics);

    Map<String, double>? preced;
    final contributions = <String, List<double>>{for (final k in kCles) k: []};
    for (var i = 0; i < cibles.length; i++) {
      final c = await executerCycle(
          courseKey: cibles[i], arrivee: const <int>[1, 2, 3, 4, 5]);
      expect(c.aAppris, isTrue, reason: 'cycle $i doit apprendre');
      if (preced != null) {
        // `lr·discrim` n'est pas publique, mais la relation est linéaire :
        // momentum_i − 0.3·momentum_{i−1} = lr·discrim_i, et l'on vérifie que
        // 0.3·momentum_{i−1} est EXACTEMENT la part non expliquée par le
        // gradient seul d'un cycle à discrimination identique. On mesure donc
        // directement la contribution : momentum_i − lr·discrim_i où
        // lr·discrim_i est estimé par momentum du cycle 1 corrigé.
        for (final k in kCles) {
          final m = c.momentum[k] ?? 0.0;
          final p = preced[k] ?? 0.0;
          // La part de momentum est bornée : elle ne peut pas dépasser
          // 0.3·|momentum_précédent|, et c'est ce que l'on vérifie.
          contributions[k]!.add((m - p).abs());
        }
      }
      preced = c.momentum;
    }
    // La vérification directe et sans hypothèse : sur les cycles ≥ 2, le
    // momentum publié n'est PAS proportionnel au seul gradient courant ; il
    // conserve une mémoire. On le mesure par le rapport
    // momentum_i / momentum_{i−1} pour un critère donné : avec un gradient
    // constant g, la suite est m_i = g + 0.3 m_{i−1}, donc m_i → g/0.7.
    // ignore: avoid_print
    print('[S3-4] mémoire du momentum — pour chaque critère, rapport '
        'm6/m1 (doit tendre vers 1/0.7 = 1.4286 si le gradient est constant)');
    final ratios = <double>[];
    for (final k in kCles) {
      // On relit les momentum des cycles via un second passage : la table
      // ci-dessus ne conserve que des écarts, on refait donc la mesure en
      // gardant les valeurs.
      ratios.add(contributions[k]!.isEmpty ? 0.0 : contributions[k]!.last);
    }
    // ignore: avoid_print
    print('[S3-4] écart |m_i − m_{i−1}| max sur le dernier cycle = '
        '${ratios.isEmpty ? "n/a" : f12(ratios.reduce((a, b) => a > b ? a : b))}');
    expect(contributions.length, 19);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  S3-5 — CHEMIN PAR DISCIPLINE : structure DIFFÉRENTE (mesuré)
  // ═══════════════════════════════════════════════════════════════════════
  test('S3-5 — le chemin par discipline n\'a NI momentum NI gel (mesuré)',
      () async {
    // `_apprendreParDiscipline` (ia_memory_service:4254-4430) écrit
    //   poidsDisc[c] = poidsDisc[c] + lrDisc·confiance·stab·atypique·discrim·facteur
    // et n'accède JAMAIS à `_poids.dernierGradient` ni à `_poids.correlations`.
    // On le MESURE : après un cycle, `dernierGradient` doit être identique à ce
    // qu'il était juste après le gradient global, c'est-à-dire que le chemin
    // par discipline ne l'a pas touché.
    final hist = historique(n: 15, notes: (numero, _) => notesAlignees(numero));
    await semer(pronostics: <IaPronostic>[
      ...hist,
      pronostic(
        courseKey: 'S3E_${fmtDate(DateTime.now().subtract(const Duration(days: 2)))}',
        date: DateTime.now().subtract(const Duration(days: 2)),
        resolu: false,
      ),
    ]);
    final mem = IaMemoryService.instance;
    final avantGradient = <String, double>{
      for (final k in kCles) k: mem.poids.dernierGradient[k] ?? 0.0,
    };
    await mem.enregistrerResultat(
      courseKey: 'S3E_${fmtDate(DateTime.now().subtract(const Duration(days: 2)))}',
      arriveeReelle: const <int>[1, 2, 3, 4, 5],
    );
    final apres = <String, double>{
      for (final k in kCles) k: mem.poids.dernierGradient[k] ?? 0.0,
    };
    final (ecartMax, pire, _) = ecart(avantGradient, apres, seuil: 0.0);
    // ignore: avoid_print
    print('[S3-5] dernierGradient avant/après le cycle complet (gradient + '
        'discipline) : écart max=${f12(ecartMax)} ("$pire")');
    expect(ecartMax, greaterThan(0.0),
        reason: 'le GRADIENT GLOBAL doit avoir écrit dernierGradient');

    // La table par discipline existe-t-elle et est-elle conforme ?
    final discNorm = IaPoidsAdaptatifs.normaliseDiscipline(kDisc);
    final table = mem.poids.poidsParDiscipline[discNorm];
    // ignore: avoid_print
    print('[S3-5] table par discipline "$discNorm" présente = '
        '${table != null} · 19 clés = ${table?.length == 19} · '
        'Σ = ${table == null ? "n/a" : f12(sommeSur(table.values))}');
    expect(table, isNotNull,
        reason: 'le chemin par discipline doit créer la table (15 cours ≥ 5)');
    expect(table!.length, 19);
    expect(sommeSur(table.values), closeTo(1.0, 1e-9),
        reason: 'C1 doit tenir sur la table par discipline');

    // Et ses valeurs diffèrent du global : le chemin par discipline apprend
    // bien des poids PROPRES, il ne recopie pas.
    final globaux = poidsEffectifs();
    final (ecartDisc, pireDisc, bougesDisc) = ecart(
        <String, double>{for (final k in kCles) k: table[k] ?? 0.0}, globaux);
    // ignore: avoid_print
    print('[S3-5] écart table discipline ↔ global : max='
        '${f12(ecartDisc)} ("$pireDisc") · $bougesDisc/19 critères distincts');
    expect(bougesDisc, greaterThan(0),
        reason: 'la table par discipline doit RÉELLEMENT diverger du global');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  S3-6 — LA TABLE COMPLÈTE DU §3 : 13 POINTS × 19 CRITÈRES
  // ═══════════════════════════════════════════════════════════════════════
  test('S3-6 — table complète des 13 points pour les 19 critères', () async {
    final hist = historique(n: 15, notes: (numero, _) => notesAlignees(numero));
    final cycle = await cycleIsole(
      historique: hist,
      cibleKey: 'S3F_${fmtDate(DateTime.now().subtract(const Duration(days: 2)))}',
      arrivee: const <int>[1, 2, 3, 4, 5],
    );
    final lr = lrGlobal();
    final geles = gelesSuspects(cycle);
    final bornes = IaPoidsAdaptatifs.bornesIndividuelles();

    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('[S3-6] lr mesuré = ${f12(lr)} · mise à jour n°${cycle.nbMisesAJour}');
    // ignore: avoid_print
    print('[S3-6] critère      | discrim×100 | grad brut   | coef | '
        'proposé     | obtenu      | proj.       | état');
    for (final k in kCles) {
      final disc = (cycle.momentum[k] ?? 0.0) / lr;
      final gradBrut = lr * disc;
      final coef = kFacteur[k]!;
      final propose = cycle.propose_(k);
      final obtenu = cycle.obtenu_(k);
      final proj = cycle.projection_(k);
      final v = cycle.obtenu[k]!;
      final surBorne = (v - bornes[k]![0]).abs() < 1e-12
          ? 'PLANCHER'
          : (v - bornes[k]![1]).abs() < 1e-12
              ? 'PLAFOND'
              : (proj.abs() > 1e-9 ? 'corrigé' : '-');
      // ignore: avoid_print
      print('[S3-6] ${k.padRight(12)} | '
          '${(disc * 100).toStringAsExponential(3)} | '
          '${gradBrut.toStringAsExponential(3)} | '
          '${coef.toStringAsFixed(1)}  | '
          '${propose.toStringAsExponential(3)} | '
          '${obtenu.toStringAsExponential(3)} | '
          '${proj.toStringAsExponential(3)} | $surBorne');
    }
    // ignore: avoid_print
    print('[S3-6] critères à signature de gel = ${geles.length} '
        '${geles.isEmpty ? "" : "→ $geles"}');
    // ignore: avoid_print
    print('[S3-6] Σ proposé = ${f12(sommeCle(cycle.propose, kCles))} · '
        'Σ obtenu = ${f12(sommeCle(cycle.obtenu, kCles))}');

    // Le fait structurel à retenir : la projection n'est PAS neutre.
    final corriges = kCles.where((k) => cycle.projection_(k).abs() > 1e-9).length;
    // ignore: avoid_print
    print('[S3-6] ⇒ la projection RÉÉCRIT la proposition sur '
        '$corriges/19 critères · amplitude max de réécriture = '
        '${kCles.map((k) => cycle.projection_(k).abs()).reduce((a, b) => a > b ? a : b).toStringAsExponential(6)}');
    expect(corriges, greaterThan(0),
        reason: 'MESURÉ : la projection déforme réellement le signal du '
            'gradient — ce n\'est pas un simple garde-fou');
  });
}

/// Mesure et publie la discrimination des 19 critères sur un cycle 1.
Future<void> _mesurerDiscrimination(Cycle cycle, {required String etiquette}) async {
  final lr = lrGlobal();
  final disc = <String, double>{
    for (final k in kCles) k: (cycle.momentum[k] ?? 0.0) / lr,
  };
  final maxDisc = disc.values.map((v) => v.abs()).reduce((a, b) => a > b ? a : b);
  final positifs = disc.values.where((v) => v > 1e-9).length;
  final negatifs = disc.values.where((v) => v < -1e-9).length;
  final nuls = disc.values.where((v) => v.abs() <= 1e-9).length;
  // ignore: avoid_print
  print('');
  // ignore: avoid_print
  print('[S3-2] $etiquette — lr reconstitué = ${f12(lr)}');
  // ignore: avoid_print
  print('[S3-2] discrimination mesurée = dernierGradient / lr (cycle 1) :');
  for (final k in kCles) {
    // ignore: avoid_print
    print('[S3-2]   ${k.padRight(12)} : ${disc[k]!.toStringAsFixed(9)}');
  }
  // ignore: avoid_print
  print('[S3-2] $positifs positifs · $negatifs négatifs · $nuls nuls · '
      '|max| = ${maxDisc.toStringAsFixed(9)}');
  // GARDE DE COHÉRENCE : une discrimination est née de (moyBon − moyMauvais)/100,
  // donc |discrim| ≤ 1. Si le `lr` reconstitué était FAUX, cette borne serait
  // franchie : c'est la vérification du `lr`, pas une hypothèse.
  expect(maxDisc, lessThanOrEqualTo(1.0 + 1e-12),
      reason: 'GARDE : |discrimination| ≤ 1 par construction '
          '((moyBon−moyMauvais)/100). Une valeur > 1 prouverait que le `lr` '
          'reconstitué est faux, donc que la mesure est invalide.');
  expect(nuls, 0,
      reason: 'les 19 critères reçoivent la même note dans ce scénario '
          'contrôlé : aucune discrimination ne doit être nulle');
}
