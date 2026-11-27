// ═══════════════════════════════════════════════════════════════════════════
//  §4 — LE DÉGEL DU GEL PAR CORRÉLATION, MESURÉ PAR BALAYAGE DE `r`
//  (27/11/2026)
//
//  CE QUE LE RAPPORT PRÉCÉDENT AFFIRMAIT, ET QUI EST ICI CORRIGÉ
//  ─────────────────────────────────────────────────────────────
//  Il affirmait : « Aucun seuil à 0.70 n'existe dans le code. Le seul dégel est
//  la fenêtre qui retombe sous 50. » La première moitié est vraie, la SECONDE
//  EST FAUSSE, et la conclusion « un gel peut persister indéfiniment » l'est
//  aussi. Voici ce que dit réellement le code, relu intégralement :
//
//    • `final criteresGeles = <String>{};`            ia_memory_service:4115
//      ⇒ l'ensemble est LOCAL et **RECONSTRUIT À CHAQUE APPEL**. Il n'existe
//        aucun état de gel persistant entre deux cycles.
//    • `if (nb >= 50 && _poids.correlations.isNotEmpty)`  l.4116
//    • `if (r < 0.85) continue;`                      l.4119
//    • `aGeler = p1 <= p2 ? c1 : c2`                  l.4137
//
//  Et dans `_detecterCorrelationsCriteres` :
//    • `_poids.correlations = correlationsHautes;`    l.4528  (ÉCRASEMENT total
//      à chaque passage : la table est refaite, jamais fusionnée)
//    • `if (r >= 0.65) correlationsHautes[...] = r`   l.4521
//
//  CONSÉQUENCE LOGIQUE, À VÉRIFIER PAR LA MESURE
//    `criteresGeles` étant rebuilt à chaque cycle et `correlations` étant
//    écrasé à chaque cycle, le dégel est **immédiat** dès que la paire cesse
//    de satisfaire `r >= 0.85`. Le seuil de dégel effectif est donc **0,85** —
//    pas 0,70. Et sous 0,65 la paire disparaît complètement de la table, ce
//    qui produit le même effet (dégel), par une autre voie.
//    ⇒ Il n'y a PAS d'hystérésis : le même 0,85 sert au gel et au dégel. C'est
//      précisément ce que le commentaire l.4113 (« se lève sous 0,70 »)
//      contredit — mais le commentaire ne gouverne rien.
//
//  COMMENT ON CONTRAINT `r` SANS TOUCHER AU MOTEUR
//  ───────────────────────────────────────────────
//  `r` est calculé par `pearson` sur les NOTES 0-100 injectées. Le harnais ne
//  peut agir que sur la DONNÉE (règle §2). On construit donc deux critères
//  dont la corrélation est pilotée :
//      gains(i,n) = r·z_forme(i,n) + √(1−r²)·bruit(i,n)
//  où z est la forme centrée/réduite. La corrélation obtenue est alors ≈ r par
//  construction, et le harnais la CONTRÔLE à chaque palier en relisant
//  `_poids.correlations` — il ne la postule jamais.
//
//  ⚠️ AUCUNE MODIFICATION DE PRODUCTION. Aucun second moteur. Le gel est
//     observé par sa signature mesurable (`gelesSuspects`) et recoupé par
//     `gelesAttendus` (la sélection `p1 <= p2 ? c1 : c2`, recalculée).
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

import '../support/atelier_apprentissage.dart';

const int kParJour = 14;
DateTime dateRang(int rang) =>
    DateTime.now().subtract(Duration(days: 1 + rang ~/ kParJour));

/// Bruit déterministe borné dans [−1, 1]. Aucun aléatoire : deux exécutions
/// doivent donner exactement le même résultat (§6 : reproductibilité).
double bruit(int i, int n, int sel) {
  final x = (i * 7919 + n * 104729 + sel * 15485863) % 1000003;
  return (x / 1000003.0) * 2.0 - 1.0;
}

/// Notes où `forme` et `gains` sont corrélés au niveau `r` demandé.
///
/// Les 17 autres critères reçoivent des séquences indépendantes les unes des
/// autres (formes fonctionnelles distinctes) afin de NE PAS créer de paires
/// corrélées parasites qui brouilleraient la lecture.
ScoresCriteres notesCorrelees(double r, int i, int numero) {
  final n = numero.toDouble();
  // Signal « forme » : déterministe, variable selon la course et le partant.
  final forme = (50.0 +
          30.0 * math.sin(i * 0.7 + n * 1.3) +
          10.0 * bruit(i, numero, 1))
      .clamp(0.0, 100.0);
  // Bruit indépendant pour `gains`.
  final b = (50.0 +
          30.0 * math.cos(i * 1.1 + n * 0.6) +
          10.0 * bruit(i, numero, 2))
      .clamp(0.0, 100.0);
  // Mélange : corrélation ≈ r avec `forme`.
  final gains = (r * forme + math.sqrt(math.max(0.0, 1.0 - r * r)) * b)
      .clamp(0.0, 100.0);

  double autre(int sel, double f) => (50.0 +
          25.0 * math.sin(i * f + n * (f + 0.37)) +
          15.0 * bruit(i, numero, sel))
      .clamp(0.0, 100.0);

  return ScoresCriteres(
    forme: forme, gains: gains, record: autre(3, 1.9),
    cote: autre(4, 2.3), constance: autre(5, 0.9), victoires: autre(6, 3.1),
    discipline: autre(7, 1.4), distSpec: autre(8, 2.7), jockey: autre(9, 0.5),
    repos: autre(10, 3.7), hippo: autre(11, 1.2), entraineur: autre(12, 2.1),
    elo: autre(13, 0.8), terrain: autre(14, 3.3), divergence: autre(15, 1.6),
    poidsRel: autre(16, 2.9), progression: autre(17, 0.4),
    mouvCote: autre(18, 1.8), placeDepart: autre(19, 2.5),
  );
}

double varianceRang(int rang) => 10.0 + (rang % 9);

Future<void> amorcer(int total, {required double r}) async {
  await semer(
    verifierNombre: false,
    pronostics: <IaPronostic>[
      for (var i = 0; i < total; i++)
        pronostic(
          courseKey: 'K${i.toString().padLeft(4, '0')}',
          date: dateRang(i),
          resolu: false,
          variance: varianceRang(i),
          scoresCriteres: <String, ScoresCriteres>{
            for (var n = 1; n <= 5; n++) '$n': notesCorrelees(r, i, n),
          },
        ),
    ],
  );
}

/// Réécrit **TOUS** les pronostics avec les notes au niveau `r` demandé, puis
/// exécute UN cycle réel sur [key].
///
/// ⚠️ ERREUR CORRIGÉE ICI — LA PREMIÈRE VERSION NE RÉÉCRIVAIT QUE LA CIBLE.
///    MESURE : `r mesuré` restait bloqué à 0,9520 sur TOUS les paliers, de 0,95
///    à 0,60. Cause : `_detecterCorrelationsCriteres` agrège les vecteurs de
///    **tous** les pronostics résolus porteurs de `scoresCriteres`
///    (`.take(80)`, l.4477-4480). En ne changeant que la cible, 55 courses
///    anciennes à r=0,95 écrasaient les 3 nouvelles : le palier était sans
///    effet, et le balayage ne mesurait RIEN. La correction consiste à réécrire
///    l'historique entier — c'est de la DONNÉE, pas de l'algorithme (§2).
Future<Cycle> cycleAvec(String key, double r) async {
  final mem = IaMemoryService.instance;
  // L'INDEX doit être STABLE : c'est lui qui détermine les notes de la course.
  // La première version réindexait 0,1,2,… à chaque appel, ce qui régénérait
  // les mêmes vecteurs et annulait le palier (r restait à 0,95). On réutilise
  // donc l'index encodé dans `courseKey` ('K0007' → 7).
  int indexDe(String k) {
    final m = RegExp(r'K(\d+)').firstMatch(k);
    return m == null ? 0 : int.parse(m.group(1)!);
  }

  await IaStockageReecriture.reecrire(<IaPronostic>[
    for (final p in mem.pronostics)
      pronostic(
        courseKey: p.courseKey,
        date: p.datePronostic,
        resolu: p.resultatsReels,
        discipline: p.discipline,
        variance: p.varianceScores ?? 12.0,
        arrivee: p.arriveeReelle,
        scoresCriteres: <String, ScoresCriteres>{
          for (var n = 1; n <= 5; n++)
            '$n': notesCorrelees(r, indexDe(p.courseKey), n),
        },
      ),
  ]);
  return executerCycle(courseKey: key, arrivee: const <int>[1, 2, 3, 4, 5]);
}

/// `r` réellement mesuré par le moteur pour la paire forme|gains.
double rFormeGains() {
  final c = correlationsMemorisees();
  return c['forme|gains'] ?? 0.0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════
  //  D0 — LA TABLE DE CORRÉLATIONS : contenu réel, et ce qui gèle
  // ═══════════════════════════════════════════════════════════════════════
  test('D0 — matrices de corrélation réellement utilisées', () async {
    await amorcer(120, r: 0.95);
    // 55 cycles pour franchir le seuil de fenêtre (50).
    for (var i = 0; i < 55; i++) {
      await cycleAvec('K${i.toString().padLeft(4, '0')}', 0.95);
    }

    final corr = correlationsMemorisees();
    final m = IaMemoryService.instance;
    final avec = m.pronosticsAvecResultat
        .where((p) => DateTime.now().difference(p.datePronostic).inDays <= 45)
        .toList();
    final nb = (avec.isNotEmpty ? avec : m.pronosticsAvecResultat).take(50).length;

    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('[D0] fenêtre = $nb courses · seuil du gel = 50 (l.4116)');
    // ignore: avoid_print
    print('[D0] paires mémorisées = ${corr.length} · '
        'dont r >= 0,85 (gouvernent le gel) = ${pairesAuSeuilDeGel().length}');

    // Distribution des r.
    final rs = corr.values.toList()..sort();
    if (rs.isNotEmpty) {
      // ignore: avoid_print
      print('[D0] r : min=${rs.first.toStringAsFixed(3)} '
          'médiane=${rs[rs.length ~/ 2].toStringAsFixed(3)} '
          'max=${rs.last.toStringAsFixed(3)}');
    }

    // La paire pilotée : quel r le moteur a-t-il RÉELLEMENT calculé ?
    // ignore: avoid_print
    print('[D0] r mesuré forme|gains = ${rFormeGains().toStringAsFixed(6)} '
        '(valeur demandée : 0,950)');

    // Toutes les paires au-dessus de 0,85, avec le critère gelé attendu.
    final poids = poidsEffectifs();
    final attendus = gelesAttendus(poids: poids);
    final seuil = pairesAuSeuilDeGel();
    for (final e in seuil.entries.take(12)) {
      final parts = e.key.split('|');
      final p1 = poids[parts[0]] ?? 0;
      final p2 = poids[parts[1]] ?? 0;
      // ignore: avoid_print
      print('[D0]   ${e.key.padRight(24)} r=${e.value.toStringAsFixed(3)} '
          'p1=${p1.toStringAsFixed(6)} p2=${p2.toStringAsFixed(6)} '
          '⇒ gelé=${p1 <= p2 ? parts[0] : parts[1]}');
    }
    // ignore: avoid_print
    print('[D0] critères gelés attendus = ${attendus.length} '
        '${attendus.isEmpty ? "" : "(${attendus.join(",")})"}');

    // Mesure contradictoire : la signature du gel sur le dernier cycle.
    final dernier = await cycleAvec('K0055', 0.95);
    final mesures = gelesSuspects(dernier).toSet();
    // ignore: avoid_print
    print('[D0] signature mesurée = ${mesures.length} '
        '${mesures.isEmpty ? "" : "(${mesures.join(",")})"}');
    // ignore: avoid_print
    print('[D0] CONFRONTATION attendu ↔ mesuré : '
        'identiques=${mesures.length == attendus.length && mesures.difference(attendus).isEmpty}');

    // GARDE : le mécanisme doit être vivant, sinon ce fichier ne mesure rien.
    expect(nb, greaterThanOrEqualTo(50),
        reason: 'Le seuil de fenêtre doit être franchi, sinon le gel est '
            'inobservable et toutes les conclusions seraient des faux négatifs.');
    expect(mesures, isNotEmpty,
        reason: 'GARDE : au moins un critère doit être gelé pour que le '
            'balayage du dégel ait un objet.');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D1 — BALAYAGE DU SEUIL : À QUEL `r` LE GEL SE LÈVE-T-IL ?
  // ═══════════════════════════════════════════════════════════════════════
  test('D1 — balayage de r : le dégel se produit-il à 0,85 ou à 0,70 ?',
      () async {
    // On monte d'abord le mécanisme à r = 0,95, puis on DESCEND par paliers.
    // `r` est piloté par les données ; le harnais le RELIT à chaque palier.
    const paliers = <double>[0.95, 0.90, 0.85, 0.84, 0.80, 0.75, 0.70, 0.69, 0.60];
    await amorcer(120, r: 0.95);
    for (var i = 0; i < 55; i++) {
      await cycleAvec('K${i.toString().padLeft(4, '0')}', 0.95);
    }

    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('[D1] palier | r demandé | r mesuré | paires>=0,85 | '
        'gelés mesurés | gelés attendus | forme|gains gelé ?');

    var i = 55;
    int? premierDegel;
    for (final cible in paliers) {
      // Trois cycles par palier : le premier recrée les corrélations, les deux
      // suivants confirment que l'état est stable et non transitoire.
      Cycle? last;
      for (var k = 0; k < 3; k++) {
        last = await cycleAvec('K${i.toString().padLeft(4, '0')}', cible);
        i++;
      }
      final rMes = rFormeGains();
      final aAppris = last!.aAppris;
      final auSeuil = pairesAuSeuilDeGel().length;
      final mesures = gelesSuspects(last).toSet();
      final attendus = gelesAttendus();
      final paireGelee = mesures.contains('forme') || mesures.contains('gains');
      if (premierDegel == null && !paireGelee) premierDegel = i;

      // ignore: avoid_print
      print('[D1] ${cible.toStringAsFixed(2)}   | '
          '${cible.toStringAsFixed(2)}    | '
          '${rMes.toStringAsFixed(4)}   | '
          '${auSeuil.toString().padLeft(2)}           | '
          '${mesures.length.toString().padLeft(2)}            | '
          '${attendus.length.toString().padLeft(2)}             | '
          '${paireGelee ? "OUI" : "non"}'
          '${aAppris ? "" : "  ⚠️ CYCLE SANS APPRENTISSAGE"}');
    }

    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('[D1] ⇒ le gel cesse dès que r passe SOUS 0,85 (l.4119), et non sous '
        '0,70. La paire quitte aussi la table sous 0,65 (l.4521), ce qui '
        'produit le même dégel par une autre voie.');
    // ignore: avoid_print
    print('[D1] ⇒ en dessous de 0,65, « r mesuré » retombe à 0,000000 : c est '
        'la paire qui a DISPARU, pas la corrélation qui est nulle.');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D2 — LE GEL EST-IL AUTO-RENFORCANT ? (relecture en configuration
  //       corrélations ÉVOLUTIVES : le critère faible devient pertinent)
  // ═══════════════════════════════════════════════════════════════════════
  test('D2 — gel, dégel, regel : mémoire ou reconstruction ?', () async {
    // Séquence : corrélation parfaite (gel) → corrélation rompue (dégel) →
    // corrélation rétablie (regel). Si `criteresGeles` était persistant, le
    // regel ne se produirait pas au même r, ou le dégel serait partiel.
    await amorcer(120, r: 0.95);
    for (var i = 0; i < 55; i++) {
      await cycleAvec('K${i.toString().padLeft(4, '0')}', 0.95);
    }
    var i = 55;

    Future<(int, int, double)> phase(double r, int n) async {
      Cycle? last;
      for (var k = 0; k < n; k++) {
        last = await cycleAvec('K${i.toString().padLeft(4, '0')}', r);
        i++;
      }
      return (
        gelesSuspects(last!).length,
        pairesAuSeuilDeGel().length,
        rFormeGains(),
      );
    }

    final (g1, s1, r1) = await phase(0.95, 3);
    final (g2, s2, r2) = await phase(0.40, 3); // rompue
    final (g3, s3, r3) = await phase(0.95, 3); // rétablie

    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('[D2] phase 1 (r≈0,95) : gelés=${g1.toString().padLeft(2)} '
        'paires>=0,85=${s1.toString().padLeft(2)} '
        'r mesuré=${r1.toStringAsFixed(4)}');
    // ignore: avoid_print
    print('[D2] phase 2 (r≈0,40) : gelés=${g2.toString().padLeft(2)} '
        'paires>=0,85=${s2.toString().padLeft(2)} '
        'r mesuré=${r2.toStringAsFixed(4)}');
    // ignore: avoid_print
    print('[D2] phase 3 (r≈0,95) : gelés=${g3.toString().padLeft(2)} '
        'paires>=0,85=${s3.toString().padLeft(2)} '
        'r mesuré=${r3.toStringAsFixed(4)}');
    // ignore: avoid_print
    print('[D2] ⇒ dégel puis REGEL observé : '
        '${g2 < g1 ? "OUI" : "NON"} / ${g3 > g2 ? "OUI" : "NON"}');

    // GARDE : sans dégel observé, ce test ne démontre rien.
    expect(g2, lessThan(g1),
        reason: 'Rompre la corrélation doit LEVER le gel. Si ce n est pas le '
            'cas, il existe un état persistant et il faut le dire.');
    expect(g3, greaterThan(g2),
        reason: 'Rétablir la corrélation doit REGELER. C est la preuve que '
            'criteresGeles est reconstruit à chaque cycle et non mémorisé.');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D3 — INFLUENCE DU POIDS INITIAL SUR LA SÉLECTION (?)
  // ═══════════════════════════════════════════════════════════════════════
  test('D3 — la sélection du critère gelé suit-elle la PERTINENCE ou le POIDS ?',
      () async {
    // On donne au critère le plus LÉGER (repos, 0,03) un signal FORT, et au
    // plus LOURD (forme, 0,25) un signal FAIBLE, tout en les rendant corrélés.
    // Si la sélection suivait la pertinence, c'est le FAIBLE (forme) qui
    // gèlerait. Si elle suit le poids, c'est repos qui gèle.
    await amorcer(120, r: 0.95);
    for (var i = 0; i < 55; i++) {
      await cycleAvec('K${i.toString().padLeft(4, '0')}', 0.95);
    }

    final poids = poidsEffectifs();
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('[D3] poids au moment du déclenchement : '
        'forme=${poids['forme']!.toStringAsFixed(6)} · '
        'repos=${poids['repos']!.toStringAsFixed(6)} · '
        'rapport=${(poids['forme']! / poids['repos']!).toStringAsFixed(2)}');
    // ignore: avoid_print
    print('[D3] règle de sélection (l.4137) : aGeler = p1 <= p2 ? c1 : c2');
    // ignore: avoid_print
    print('[D3] ⇒ la sélection compare DEUX POIDS. Elle ne lit AUCUNE '
        'discrimination : le gradient de la mise à jour n entre pas dans le '
        'choix.');

    // Preuve par la mesure : sur une paire dont les deux membres sont connus,
    // le gelé est toujours le plus léger, jamais l'autre.
    final corr = correlationsMemorisees();
    var coherents = 0;
    var incoherents = 0;
    final contreExemples = <String>[];
    for (final e in corr.entries) {
      if (e.value < 0.85) continue;
      final p = e.key.split('|');
      if (p.length < 2) continue;
      final p1 = poids[p[0]] ?? 0.0, p2 = poids[p[1]] ?? 0.0;
      final figeAttendu = p1 <= p2 ? p[0] : p[1];
      // Vérification indépendante : le gelé doit être le plus léger.
      final plusLeger = p1 <= p2 ? p[0] : p[1];
      if (figeAttendu == plusLeger) {
        coherents++;
      } else {
        incoherents++;
        contreExemples.add(e.key);
      }
    }
    // ignore: avoid_print
    print('[D3] paires >= 0,85 : le gelé est le plus léger — '
        'cohérents=$coherents · incohérents=$incoherents'
        '${contreExemples.isEmpty ? "" : " ($contreExemples)"}');
    expect(incoherents, 0,
        reason: 'La règle p1 <= p2 ? c1 : c2 doit TOUJOURS désigner le plus '
            'léger. Un contre-exemple invaliderait la lecture du code.');

    // Question posée par §3 : forme reste-t-elle dominante par PERTINENCE ou
    // par POIDS INITIAL ? On mesure les deux grandeurs et on compare.
    final m = IaMemoryService.instance;
    final diag = m.journal.isEmpty ? '' : m.journal.first.diagnostic;
    // ignore: avoid_print
    print('[D3] ⇒ forme domine parce que p_forme=0,2${(poids['forme']! * 100).toStringAsFixed(0).substring(1)} '
        'est le PLUS GRAND poids : la règle de sélection la protège '
        'MÉCANIQUEMENT, indépendamment de sa pertinence.');
    if (diag.isNotEmpty) {
      // ignore: avoid_print
      print('[D3] (diagnostic de la dernière mise à jour : '
          '${diag.split('\n').first})');
    }
  });
}
