// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER « VALIDATION APPROFONDIE DE L'APPRENTISSAGE » — §5 (GEL) et §4
//  (COEFFICIENTS)
//
//  ⚠️ AVERTISSEMENT DE MÉTHODE — UNE PREMIÈRE VERSION DE CE FICHIER ÉTAIT FAUSSE.
//     Elle mesurait le gel avec des notes CONSTANTES (96 pour tous les partants
//     et tous les critères). Or un vecteur constant a une VARIANCE NULLE, et
//     `pearson` (ia_memory_service:4513) renvoie `0.0` quand `denom == 0`.
//     Aucune corrélation n'était donc calculable, et le « gel ne se déclenche
//     pas » mesuré alors n'était qu'un artefact du montage.
//     Le montage correct — et celui utilisé ici — donne une note QUI DÉCROÎT
//     AVEC LE RANG : les 19 critères sont alors, par construction, des vecteurs
//     IDENTIQUES, donc de corrélation EXACTEMENT 1,0 entre eux. C'est le cas
//     extrême qui doit déclencher le gel. C'est aussi la situation réelle d'un
//     jeu de critères redondants, que le gel est censé traiter.
//
//  QUESTION 1 (§5) — LA CHAÎNE DU GEL, MESURÉE ÉTAPE PAR ÉTAPE
//    (1) `_poids.correlations` est-il peuplé ?          [l.4528, seuil 0,65]
//    (2) les paires atteignent-elles 0,85 ?             [l.4119]
//    (3) la fenêtre atteint-elle 50 courses ?           [l.4116]
//    (4) un critère reçoit-il effectivement le gel ?    [l.4137]
//
//  QUESTION 2 (§4) — L'ÉQUILIBRE EST-IL FIXÉ PAR LE COEFFICIENT OU PAR LE
//  SIGNAL ? On donne à `jockey` (coefficient 0,5) un signal FORT et aux 18
//  autres un signal NUL, puis on compare à une expérience où TOUS les signaux
//  sont nuls. Les témoins sont `distSpec`, `elo`, `terrain`, `mouvCote` : même
//  coefficient 0,5, donc même résolution.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

import '../support/atelier_apprentissage.dart';

const int kCoursesParJour = 14;
DateTime dateDuRang(int rang) =>
    DateTime.now().subtract(Duration(days: 1 + rang ~/ kCoursesParJour));

/// Construit des notes à partir d'une NOTE DE BASE PAR CRITÈRE et d'une PENTE
/// PAR CRITÈRE. La note du partant [numero] vaut `base[k] − (numero−1)·pente[k]`.
/// Une pente nulle ⇒ note constante ⇒ variance nulle ⇒ Pearson indéfini ⇒
/// corrélation 0. Une pente identique partout ⇒ critères PARFAITEMENT corrélés.
ScoresCriteres notesAvecPente(
    Map<String, double> base, Map<String, double> pente, int numero) {
  double v(String k) => base[k]! - (numero - 1) * (pente[k] ?? 0.0);
  return ScoresCriteres(
    forme: v('forme'), gains: v('gains'), record: v('record'), cote: v('cote'),
    constance: v('constance'), victoires: v('victoires'),
    discipline: v('discipline'), distSpec: v('distSpec'), jockey: v('jockey'),
    repos: v('repos'), hippo: v('hippo'), entraineur: v('entraineur'),
    elo: v('elo'), terrain: v('terrain'), divergence: v('divergence'),
    poidsRel: v('poidsRel'), progression: v('progression'),
    mouvCote: v('mouvCote'), placeDepart: v('placeDepart'),
  );
}

/// Variance des scores par course. MESURÉ — ELLE DOIT VARIER.
///
/// `_mettreAJourCalibration` (ia_memory_service:4440-4471) est le SEUL appelant
/// de `_detecterCorrelationsCriteres`, et il sort AVANT cet appel si
/// `hautConfiance.isEmpty`. Or `hautConfiance` ne retient que les courses dont
/// `varianceScores > medianVariance` : si toutes les courses ont la MÊME
/// variance, la médiane vaut cette variance, aucune course n'est STRICTEMENT
/// au-dessus, `hautConfiance` est vide, et les corrélations ne sont JAMAIS
/// calculées. C'est la deuxième cause mesurée de mon montage initial faux.
double varianceDuRang(int rang) => 10.0 + (rang % 9);

Future<void> preparer(int nombreCycles, int amorce,
    {required ScoresCriteres Function(int numero) notes}) async {
  await semer(
    verifierNombre: false,
    pronostics: <IaPronostic>[
      for (var i = 0; i < nombreCycles; i++)
        pronostic(
          courseKey: 'C${i.toString().padLeft(4, '0')}',
          date: dateDuRang(i),
          resolu: false,
          variance: varianceDuRang(i),
          scoresCriteres: <String, ScoresCriteres>{
            for (var n = 1; n <= 5; n++) '$n': notes(n),
          },
        ),
      for (var j = 0; j < amorce; j++)
        pronostic(
          courseKey: 'A${j.toString().padLeft(4, '0')}',
          date: dateDuRang(nombreCycles + j),
          variance: varianceDuRang(nombreCycles + j),
          scoresCriteres: <String, ScoresCriteres>{
            for (var n = 1; n <= 5; n++) '$n': notes(n),
          },
        ),
    ],
  );
}

/// Réécrit la donnée du pronostic cible (jamais le moteur), puis exécute un
/// cycle réel et rapporte l'état.
Future<Cycle> cycle(String key, ScoresCriteres Function(int numero) notes) async {
  final mem = IaMemoryService.instance;
  await IaStockageReecriture.reecrire(<IaPronostic>[
    for (final p in mem.pronostics)
      if (p.courseKey == key && !p.resultatsReels)
        pronostic(
          courseKey: p.courseKey,
          date: p.datePronostic,
          resolu: false,
          discipline: p.discipline,
          variance: p.varianceScores ?? 12.0,
          scoresCriteres: <String, ScoresCriteres>{
            for (var n = 1; n <= 5; n++) '$n': notes(n),
          },
        )
      else
        p,
  ]);
  return executerCycle(courseKey: key, arrivee: const <int>[1, 2, 3, 4, 5]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════
  //  G0 — LA CHAÎNE DU GEL, MESURÉE ÉTAPE PAR ÉTAPE (§5)
  // ═══════════════════════════════════════════════════════════════════════
  test('G0 — gel par corrélation : corrélations parfaites (r = 1,00)',
      () async {
    // PENTE IDENTIQUE (6) SUR LES 19 CRITÈRES, note de base identique (96).
    // ⇒ les 19 vecteurs de notes sont IDENTIQUES ⇒ r = 1,000000 entre chaque
    //   paire. C'est le cas extrême du mécanisme.
    ScoresCriteres notes(int numero) => notesAvecPente(
          {for (final k in kCles) k: 96.0},
          {for (final k in kCles) k: 6.0},
          numero,
        );

    await preparer(120, 12, notes: notes);
    final mem = IaMemoryService.instance;
    var maxPaires = 0;
    var maxR = 0.0;
    var cyclesFenetre50 = 0;
    var cyclesAvecGel = 0;
    var totalGeles = 0;
    final journal = <String>[];

    for (var i = 0; i < 120; i++) {
      final key = 'C${i.toString().padLeft(4, '0')}';
      final c = await cycle(key, notes);

      final corr = mem.poids.correlations;
      if (corr.length > maxPaires) maxPaires = corr.length;
      for (final r in corr.values) {
        if (r > maxR) maxR = r;
      }
      final avec = mem.pronosticsAvecResultat;
      final recents = avec
          .where((p) => DateTime.now().difference(p.datePronostic).inDays <= 45)
          .toList();
      final nb = (recents.isNotEmpty ? recents : avec).take(50).length;
      if (nb >= 50) cyclesFenetre50++;

      final geles = gelesSuspects(c);
      if (geles.isNotEmpty) {
        cyclesAvecGel++;
        totalGeles += geles.length;
      }
      if (i < 3 || i % 15 == 0 || (geles.isNotEmpty && journal.length < 16)) {
        journal.add('[G0] cycle ${i.toString().padLeft(3)} | fenêtre=$nb | '
            'paires=${corr.length} | r max=${corr.isEmpty ? "n/a" : corr.values.reduce((a, b) => a > b ? a : b).toStringAsFixed(6)}'
            ' | gel=${geles.length} ${geles.isEmpty ? "" : "(${geles.take(4).join(",")}${geles.length > 4 ? "…" : ""})"}');
      }
    }
    for (final l in journal) {
      // ignore: avoid_print
      print(l);
    }
    // ignore: avoid_print
    print('[G0] BILAN : paires mémorisées max = $maxPaires (171 paires '
        'possibles sur 19 critères) · r max = ${maxR.toStringAsFixed(6)}');
    // ignore: avoid_print
    print('[G0] cycles où la fenêtre atteint 50 courses = $cyclesFenetre50/120 '
        '· cycles avec ≥ 1 gel = $cyclesAvecGel/120 · total critères gelés = '
        '$totalGeles');
    // ignore: avoid_print
    print('[G0] seuils réels : peuplement r ≥ 0,65 (l.4521) · gel r ≥ 0,85 '
        '(l.4119) · fenêtre ≥ 50 (l.4116)');
    expect(maxPaires, greaterThan(0),
        reason: 'GARDE POSITIVE : les corrélations DOIVENT être calculées. Sans '
            'cette garde, un « pas de gel » pourrait n\'être qu\'un défaut de '
            'montage — c\'est exactement l\'erreur de ma première version.');
    expect(maxR, greaterThan(0.99),
        reason: 'postulat du montage : des vecteurs identiques doivent donner '
            'r = 1,0 (mesuré ${maxR.toStringAsFixed(6)})');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  G1 — L'ÉQUILIBRE EST-IL FIXÉ PAR LE COEFFICIENT OU PAR LE SIGNAL ? (§4)
  // ═══════════════════════════════════════════════════════════════════════
  test('G1 — un critère à coefficient 0,5 très discriminant dépasse-t-il ses '
      'paires de même coefficient ? (§4, §10)', () async {
    // Expérience A : les 19 critères ont une note CONSTANTE (pente 0) ⇒
    //                discrimination NULLE partout.
    // Expérience B : identique, SAUF `jockey` dont la note décroît de 25 par
    //                rang ⇒ discrimination FORTE et positive.
    ScoresCriteres notesNeutres(int numero) => notesAvecPente(
          {for (final k in kCles) k: 90.0},
          {for (final k in kCles) k: 0.0},
          numero,
        );
    ScoresCriteres notesAvecJockeyFort(int numero) => notesAvecPente(
          {for (final k in kCles) k: 90.0},
          {for (final k in kCles) k: 0.0, 'jockey': 25.0},
          numero,
        );

    Future<Map<String, double>> executer(
        ScoresCriteres Function(int) notes) async {
      await preparer(220, 12, notes: notes);
      final mem = IaMemoryService.instance;
      for (var i = 0; i < 220; i++) {
        await cycle('C${i.toString().padLeft(4, '0')}', notes);
      }
      return <String, double>{for (final k in kCles) k: mem.poids.getPoids(k)};
    }

    final sansSignal = await executer(notesNeutres);
    final avecSignal = await executer(notesAvecJockeyFort);

    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('[G1] équilibre à 220 cycles — signal NUL partout vs signal FORT '
        'sur jockey seulement');
    // ignore: avoid_print
    print('[G1] critère      | coef | SANS signal | AVEC signal | écart');
    for (final k in kCles) {
      // ignore: avoid_print
      print('[G1] ${k.padRight(12)} | ${kFacteur[k]!.toStringAsFixed(1)}  | '
          '${sansSignal[k]!.toStringAsFixed(9)} | '
          '${avecSignal[k]!.toStringAsFixed(9)} | '
          '${(avecSignal[k]! - sansSignal[k]!).toStringAsExponential(3)}');
    }
    const temoins = <String>['distSpec', 'elo', 'terrain', 'mouvCote'];
    final moyTemoins =
        temoins.map((k) => avecSignal[k]!).reduce((a, b) => a + b) /
            temoins.length;
    final forme = avecSignal['forme']!;
    // ignore: avoid_print
    print('[G1] ⇒ jockey (signal MAX, coef 0,5) = '
        '${avecSignal['jockey']!.toStringAsFixed(9)} · moyenne de ses 4 témoins '
        'de coefficient 0,5 = ${moyTemoins.toStringAsFixed(9)} · rapport = '
        '${(avecSignal['jockey']! / moyTemoins).toStringAsFixed(4)}');
    // ignore: avoid_print
    print('[G1] ⇒ jockey SANS signal = ${sansSignal['jockey']!.toStringAsFixed(9)}'
        ' · effet propre du signal = '
        '${(avecSignal['jockey']! - sansSignal['jockey']!).toStringAsExponential(3)}');
    // ignore: avoid_print
    print('[G1] ⇒ forme (signal NUL, coef 1,0) = ${forme.toStringAsFixed(9)} '
        '· rapport jockey/forme = '
        '${(avecSignal['jockey']! / forme).toStringAsFixed(4)}');
    expect(sansSignal.length, 19);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  G2 — LE VERROU : QUI N'EST JAMAIS GELÉ, ET POURQUOI (§5)
  // ═══════════════════════════════════════════════════════════════════════
  test('G2 — le critère le plus lourd est-il le seul à ne jamais geler ? (§5)',
      () async {
    // Le gel choisit `aGeler = p1 <= p2 ? c1 : c2` (l.4126) : dans CHAQUE paire,
    // c'est le critère au poids le PLUS FAIBLE qui est gelé. Sur 171 paires à
    // r = 1,0, le critère de poids MAXIMAL n'est donc jamais choisi. Comme son
    // poids ne peut que croître pendant que les autres sont figés, il reste le
    // plus lourd — et n'est donc JAMAIS gelé : c'est un VERROU AUTO-RENFORCÉ.
    ScoresCriteres notes(int numero) => notesAvecPente(
          {for (final k in kCles) k: 96.0},
          {for (final k in kCles) k: 6.0},
          numero,
        );
    await preparer(140, 12, notes: notes);

    final jamaisGeles = <String, int>{for (final k in kCles) k: 0};
    final nbGeles = <String, int>{for (final k in kCles) k: 0};
    var cyclesAvecGel = 0;
    var gelStable = 0;
    List<String>? dernierGel;

    for (var i = 0; i < 140; i++) {
      final c = await cycle('C${i.toString().padLeft(4, '0')}', notes);
      final geles = gelesSuspects(c);
      if (geles.isEmpty) continue;
      cyclesAvecGel++;
      if (dernierGel != null &&
          geles.join(',') == dernierGel.join(',')) {
        gelStable++;
      }
      dernierGel = geles;
      for (final k in kCles) {
        if (geles.contains(k)) {
          nbGeles[k] = nbGeles[k]! + 1;
        } else {
          jamaisGeles[k] = jamaisGeles[k]! + 1;
        }
      }
    }

    final mem = IaMemoryService.instance;
    final poids = <String, double>{
      for (final k in kCles) k: mem.poids.getPoids(k),
    };
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('[G2] cycles avec gel = $cyclesAvecGel/140 · cycles où la liste '
        'gelée est IDENTIQUE à la précédente = $gelStable');
    // ignore: avoid_print
    print('[G2] critère      | gelé (cycles) | non gelé | poids final | rang');
    final ordre = kCles.toList()
      ..sort((a, b) => poids[b]!.compareTo(poids[a]!));
    for (final k in kCles) {
      // ignore: avoid_print
      print('[G2] ${k.padRight(12)} | ${nbGeles[k].toString().padLeft(13)} | '
          '${jamaisGeles[k].toString().padLeft(8)} | '
          '${poids[k]!.toStringAsFixed(9)} | '
          '${(ordre.indexOf(k) + 1).toString().padLeft(2)}/19');
    }
    final nonGeles = kCles.where((k) => nbGeles[k] == 0).toList();
    // ignore: avoid_print
    print('[G2] ⇒ critères JAMAIS gelés sur 140 cycles = ${nonGeles.length} '
        '${nonGeles.isEmpty ? "" : "→ $nonGeles"}');
    // ignore: avoid_print
    print('[G2] ⇒ ce sont les plus lourds ? '
        '${nonGeles.isNotEmpty && ordre.take(nonGeles.length).toSet().containsAll(nonGeles)}');
    // ignore: avoid_print
    print('[G2] ⇒ poids du plus lourd = ${poids[ordre.first]!.toStringAsFixed(9)}'
        ' ("${ordre.first}") · poids du plus léger = '
        '${poids[ordre.last]!.toStringAsFixed(9)} ("${ordre.last}") · '
        'rapport = ${(poids[ordre.first]! / poids[ordre.last]!).toStringAsFixed(2)}');
    expect(cyclesAvecGel, greaterThan(0),
        reason: 'le gel doit s\'être déclenché pour que la mesure ait un sens');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  G3 — SCÉNARIO EXIGÉ PAR §5 : UN CRITÈRE GELÉ DEVIENT PLUS PERTINENT
  // ═══════════════════════════════════════════════════════════════════════
  test('G3 — un critère gelé peut-il regagner l\'influence que son nouveau '
      'pouvoir discriminant justifie ? (§5)', () async {
    // MONTAGE : les 19 critères sont fortement corrélés jusqu'au cycle 80
    // (pente 6 partout) ⇒ le gel s'installe à partir du cycle ~37.
    // À partir du cycle 80, `placeDepart` devient le SEUL critère informatif :
    // les 18 autres prennent une pente NULLE (note constante), lui garde une
    // pente FORTE. Sa discrimination passe donc de « égale aux autres » à
    // « seul à discriminer ».
    // Question §5 : son poids suit-il ?
    ScoresCriteres correles(int numero) => notesAvecPente(
          {for (final k in kCles) k: 96.0},
          {for (final k in kCles) k: 6.0},
          numero,
        );
    ScoresCriteres seulInformatif(int numero) => notesAvecPente(
          {for (final k in kCles) k: 96.0},
          {for (final k in kCles) k: 0.0, 'placeDepart': 18.0},
          numero,
        );

    await preparer(300, 12, notes: correles);
    final poids = <int, double>{};
    final geles = <int, int>{};
    for (var i = 0; i < 300; i++) {
      final c = await cycle('C${i.toString().padLeft(4, '0')}',
          i < 80 ? correles : seulInformatif);
      if (i == 20 || i == 40 || i == 60 || i == 79 ||
          i == 100 || i == 150 || i == 200 || i == 299) {
        poids[i] = c.obtenu['placeDepart']!;
        geles[i] = gelesSuspects(c).length;
      }
    }
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('[G3] « placeDepart » — corrélé à tout le monde jusqu\'au cycle 80, '
        'puis SEUL critère informatif');
    for (final e in poids.entries) {
      // ignore: avoid_print
      print('[G3] cycle ${e.key.toString().padLeft(3)} : poids de '
          'placeDepart = ${e.value.toStringAsFixed(9)} · '
          'critères gelés = ${geles[e.key]}');
    }
    final avantInversion = poids[79]!;
    final apres = poids[299]!;
    final gain = apres - avantInversion;
    // ignore: avoid_print
    print('[G3] ⇒ avant inversion (cycle 79) = '
        '${avantInversion.toStringAsFixed(9)} · après 220 cycles de signal '
        'EXCLUSIF = ${apres.toStringAsFixed(9)} · gain = '
        '${gain.toStringAsExponential(3)}');
    final bornes = IaPoidsAdaptatifs.bornesIndividuelles();
    // ignore: avoid_print
    print('[G3] ⇒ bornes de placeDepart = [${bornes['placeDepart']![0]}, '
        '${bornes['placeDepart']![1]}] · '
        '${gain.abs() < 1e-9 ? "AUCUN gain : le critère est resté figé" : "le critère a bougé"}');
    expect(poids.length, greaterThan(3));
  });
}
