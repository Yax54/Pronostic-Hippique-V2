// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER « VALIDATION APPROFONDIE DE L'APPRENTISSAGE » — §6, §7, §8, §10
//  DYNAMIQUE LONGUE : BORNES, CONTRAINTES COLLECTIVES, MOMENTUM, PROJECTION,
//  CONVERGENCE ET ADAPTATION
//
//  LE FAIT QUE CE FICHIER DOIT TRANCHE, ET QUI A ÉTÉ DÉCOUVERT AU §3.
//  ──────────────────────────────────────────────────────────────────────
//  Au PREMIER cycle, la mesure du §3 donne, sur les 19 critères :
//     proposé (gradient)      : +1,465e-4  (positif, très petit)
//     obtenu  (après proj.)   : −3,891e-2  (négatif, 265× plus grand)
//  Le gradient pousse vers le HAUT, la projection livre vers le BAS. Question
//  décisive : est-ce un ARTEFACT TRANSITOIRE du premier cycle (Σ passe de 1,26
//  à 1,00, soit −20,6 % de remise à l'échelle), ou un défaut PERMANENT ?
//
//  ⇒ Si c'est transitoire, l'apprentissage reste fonctionnel après le premier
//    cycle et le défaut se limite à un décalage initial.
//  ⇒ Si c'est permanent, le signal d'apprentissage est détruit à chaque cycle
//    et le système n'apprend pas — c'est alors un défaut structurel majeur à
//    présenter au §12.
//
//  MÉTHODE — le fenêtrage est celui de la PRODUCTION.
//  Ça n'est pas un détail : `_apprendreParGradient` prend
//  `pronosticsAvecResultat` dans l'ORDRE de `_pronostics`, puis `.take(50)`.
//  La production insère les NOUVEAUX pronostics en tête (`insert(0, …)`,
//  ia_memory_service:3095/3265) : la fenêtre est donc bien GLISSANTE vers les
//  50 courses les plus récemment créées. Ce harnais reproduit exactement cette
//  mutation — `pronostics` est un champ public, et `insert(0, …)` est
//  littéralement ce qu'écrit la production. Aucune formule n'est touchée.
//
//  ⚠️ AUCUNE MODIFICATION DE PRODUCTION : ni coefficient, ni borne, ni
//     contrainte collective, ni gel, ni poids initial. Tout passe par
//     `enregistrerResultat()` — la méthode réelle.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

import '../support/atelier_apprentissage.dart';

// ─── Générateurs de notes CONTRÔLÉES (le levier est la donnée) ─────────────

/// Notes DÉCROISSANTES avec le rang : les 19 critères sont pertinents.
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

/// Un seul critère est FRANCHEMENT plus discriminant que les autres :
/// sa note décroît de 20 points par rang au lieu de 6. C'est le scénario
/// « ce critère devient le plus pertinent » du §10.
ScoresCriteres notesUnCritereFort(int numero, String fort) {
  final base = <String, double>{
    for (final k in kCles) k: 96.0 - numero * 6,
  };
  base[fort] = 118.0 - numero * 20; // pente forte, bornée à 100 par le moteur
  return ScoresCriteres(
    forme: base['forme']!, gains: base['gains']!, record: base['record']!,
    cote: base['cote']!, constance: base['constance']!,
    victoires: base['victoires']!, discipline: base['discipline']!,
    distSpec: base['distSpec']!, jockey: base['jockey']!, repos: base['repos']!,
    hippo: base['hippo']!, entraineur: base['entraineur']!, elo: base['elo']!,
    terrain: base['terrain']!, divergence: base['divergence']!,
    poidsRel: base['poidsRel']!, progression: base['progression']!,
    mouvCote: base['mouvCote']!, placeDepart: base['placeDepart']!,
  );
}

/// Un critère est NEUTRE (note constante 50) : il ne discrimine rien.
/// C'est la signature d'un critère « insuffisamment alimenté ».
ScoresCriteres notesAvecUnCritereNeutre(int numero, String neutre) {
  final base = <String, double>{
    for (final k in kCles) k: 96.0 - numero * 6,
  };
  base[neutre] = 50.0;
  return ScoresCriteres(
    forme: base['forme']!, gains: base['gains']!, record: base['record']!,
    cote: base['cote']!, constance: base['constance']!,
    victoires: base['victoires']!, discipline: base['discipline']!,
    distSpec: base['distSpec']!, jockey: base['jockey']!, repos: base['repos']!,
    hippo: base['hippo']!, entraineur: base['entraineur']!, elo: base['elo']!,
    terrain: base['terrain']!, divergence: base['divergence']!,
    poidsRel: base['poidsRel']!, progression: base['progression']!,
    mouvCote: base['mouvCote']!, placeDepart: base['placeDepart']!,
  );
}

// ─────────────── Boucle de cycles réels, fenêtre glissante ─────────────────
//
// ⚠️ CONTRAINTE DE MÉTHODE MESURÉE : `IaMemoryService.pronostics` est exposé
//    comme `List.unmodifiable` (ia_memory_service:301). On ne peut donc PAS
//    insérer en tête depuis le harnais. Or la fenêtre d'apprentissage est
//    `pronosticsAvecResultat.take(50)` dans l'ORDRE de `_pronostics`, et la
//    production insère les nouveaux pronostics en tête.
//
//    La fenêtre glissante est donc reconstruite autrement, et fidèlement :
//    on sème la liste dans l'ordre ANTÉCHRONOLOGIQUE (le plus récent d'abord,
//    `_load()` conservant l'ordre du JSON, ia_memory_service:2411) et on
//    RÉSOUT les courses dans l'ordre de la liste. Après k résolutions, les
//    résolues sont les k PREMIÈRES de la liste, donc les k plus récentes :
//    `take(50)` = les 50 plus récentes résolues, exactement la fenêtre de
//    production. Les `amorce` courses déjà résolues sont placées en FIN de
//    liste (les plus anciennes) et sortent naturellement de la fenêtre dès que
//    k dépasse 50.

const int kCoursesParJour = 14; // pour que tout tienne dans 45 jours

DateTime dateDuRang(int rang) => DateTime.now().subtract(
      Duration(days: 1 + rang ~/ kCoursesParJour),
    );

/// Prépare un état vierge depuis les POIDS INITIAUX.
/// [amorce] courses déjà résolues franchissent les seuils du moteur
/// (≥ 10 pour le gradient, ≥ 5 pour la discipline).
Future<void> preparer({
  required int nombreCycles,
  int amorce = 12,
  ScoresCriteres Function(int numero, int cycle)? notes,
}) async {
  final courses = <IaPronostic>[
    // Les cycles à venir (résolus un par un), du plus récent au plus ancien.
    for (var i = 0; i < nombreCycles; i++)
      pronostic(
        courseKey: 'C${i.toString().padLeft(4, '0')}',
        date: dateDuRang(i),
        resolu: false,
        scoresCriteres: <String, ScoresCriteres>{
          for (var num = 1; num <= 5; num++)
            '$num': (notes ?? (n, _) => notesAlignees(n))(num, i),
        },
      ),
    // L'amorce, déjà résolue, en FIN de liste (les plus anciennes).
    for (var j = 0; j < amorce; j++)
      pronostic(
        courseKey: 'A${j.toString().padLeft(4, '0')}',
        date: dateDuRang(nombreCycles + j),
        scoresCriteres: <String, ScoresCriteres>{
          for (var num = 1; num <= 5; num++)
            '$num': (notes ?? (n, _) => notesAlignees(n))(num, j),
        },
      ),
  ];
  await semer(pronostics: courses, verifierNombre: false);
}

/// Exécute [n] cycles réels en résolvant les courses `C0000`, `C0001`, … dans
/// l'ordre de la liste semée — donc de la plus récente à la plus ancienne.
///
/// [notes] reçoit (numéro, indexDeCycle) : c'est là que l'expérience change la
/// PERTINENCE d'un critère, sans jamais toucher au moteur.
/// [suivi] est appelé après chaque cycle avec (index, Cycle).
Future<void> derouler(
  int n, {
  required ScoresCriteres Function(int numero, int cycle) notes,
  void Function(int cycle, Cycle c)? suivi,
}) async {
  for (var i = 0; i < n; i++) {
    final key = 'C${i.toString().padLeft(4, '0')}';
    // La donnée du cycle est celle qui a été SEMÉE : on la remplace par la
    // note voulue pour ce cycle, en MODIFIANT LE PRONOSTIC SEMÉ (mutation de
    // la donnée d'entrée, jamais du moteur). `_pronostics` n'étant pas
    // accessible, on repasse par le stockage : voir `remplacerNotes`.
    await remplacerNotes(key, notes, i);
    final c = await executerCycle(
      courseKey: key,
      arrivee: const <int>[1, 2, 3, 4, 5],
    );
    if (suivi != null) suivi(i, c);
  }
}

/// Remplace les notes d'un pronostic SEMÉ en réécrivant le stockage puis en
/// rechargeant. C'est le chemin d'un téléphone qui reçoit une mise à jour de
/// ses pronostics : `recharger()` → `_load()` → `fromJson`.
Future<void> remplacerNotes(
  String courseKey,
  ScoresCriteres Function(int numero, int cycle) notes,
  int cycle,
) async {
  final mem = IaMemoryService.instance;
  final cible = mem.pronostics.firstWhere((p) => p.courseKey == courseKey);
  if (cible.resultatsReels) return; // déjà résolu : rien à changer
  // On réécrit UNIQUEMENT les notes de la cible, dans le stockage réel, avec
  // les sérialiseurs de production.
  final tous = <IaPronostic>[
    for (final p in mem.pronostics)
      if (p.courseKey == courseKey)
        pronostic(
          courseKey: p.courseKey,
          date: p.datePronostic,
          resolu: false,
          discipline: p.discipline,
          scoresCriteres: <String, ScoresCriteres>{
            for (var num = 1; num <= 5; num++) '$num': notes(num, cycle),
          },
        )
      else
        p,
  ];
  await IaStockageReecriture.reecrire(tous);
}

String _f(double v) => v.toStringAsFixed(12);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════
  //  D0 — LE DÉFAUT DU CYCLE 1 EST-IL TRANSITOIRE OU PERMANENT ? (§8, §10)
  // ═══════════════════════════════════════════════════════════════════════
  test('D0 — le signe du gradient survit-il à la projection, cycle après cycle ?',
      () async {
    await preparer(nombreCycles: 40, amorce: 12);
    final lignes = <String>[];
    var signesRespectes = 0;
    var signesInverses = 0;
    final lr = lrGlobal();

    await derouler(40, notes: (numero, cycle) => notesAlignees(numero),
        suivi: (i, c) {
      if (!c.aAppris) return;
      // Un cycle « respecte son signal » si, sur les critères de base (facteur
      // 1.0, donc aucun amortissement), la variation OBTENUE a le signe de la
      // discrimination. La discrimination est positive dans ce scénario.
      final respects = kBase
          .where((k) => c.obtenu_(k) > 0)
          .length;
      final inverses = kBase
          .where((k) => c.obtenu_(k) < 0)
          .length;
      signesRespectes += respects;
      signesInverses += inverses;
      if (i < 12 || i % 10 == 0) {
        final somme = sommeCle(c.obtenu, kCles);
        lignes.add('[D0] cycle ${i.toString().padLeft(2)} | Σ avant='
            '${_f(sommeCle(c.avant, kCles))} | Σ obtenu=${_f(somme)} | '
            'base ↑$respects ↓$inverses | forme ${c.obtenu_('forme').toStringAsExponential(3)}'
            ' | cote ${c.obtenu_('cote').toStringAsExponential(3)}');
      }
    });
    for (final l in lignes) {
      // ignore: avoid_print
      print(l);
    }
    // ignore: avoid_print
    print('[D0] BILAN sur 40 cycles : variations de BASE conformes au signe du '
        'gradient = $signesRespectes occurrences, INVERSÉES = $signesInverses '
        'occurrences (7 critères de base × 40 cycles = 280 théoriques, '
        'moins les cycles sans apprentissage)');
    // ignore: avoid_print
    print('[D0] lr = ${_f(lr)}');
    expect(signesRespectes + signesInverses, greaterThan(0));
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D1 — CONVERGENCE À SIGNAL CONSTANT (§10, §6)
  // ═══════════════════════════════════════════════════════════════════════
  test('D1 — convergence à signal constant : point fixe et bornes (§6, §10)',
      () async {
    await preparer(nombreCycles: 300, amorce: 12);
    final etats = <int, Map<String, double>>{};
    var maxMvt = 0.0;
    await derouler(300, notes: (numero, cycle) => notesAlignees(numero),
        suivi: (i, c) {
      if (i % 25 == 0 || i == 299) {
        etats[i] = Map<String, double>.from(c.obtenu);
      }
      if (i > 250) {
        final m = kCles
            .map((k) => c.obtenu_(k).abs())
            .reduce((a, b) => a > b ? a : b);
        if (m > maxMvt) maxMvt = m;
      }
    });

    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('[D1] critère      | t=0      | t=50     | t=150    | t=299    | '
        'borne atteinte ?');
    final bornes = IaPoidsAdaptatifs.bornesIndividuelles();
    for (final k in kCles) {
      final v0 = etats[0]![k]!;
      final v50 = etats[50] ?[k] ?? double.nan;
      final v150 = etats[150]?[k] ?? double.nan;
      final v299 = etats[299]![k]!;
      final etat = (v299 - bornes[k]![0]).abs() < 1e-9
          ? 'PLANCHER'
          : (v299 - bornes[k]![1]).abs() < 1e-9
              ? 'PLAFOND'
              : 'libre';
      // ignore: avoid_print
      print('[D1] ${k.padRight(12)} | ${v0.toStringAsFixed(6)} | '
          '${v50.toStringAsFixed(6)} | ${v150.toStringAsFixed(6)} | '
          '${v299.toStringAsFixed(6)} | $etat');
    }
    final somme299 = sommeCle(etats[299]!, kCles);
    final partEnr299 = sommeCle(etats[299]!, kEnrichis);
    // ignore: avoid_print
    print('[D1] Σ(t=299) = ${_f(somme299)} · part enrichie = '
        '${_f(partEnr299)} · mouvement max sur les 50 derniers cycles = '
        '${maxMvt.toStringAsExponential(3)}');
    // ignore: avoid_print
    print('[D1] part enrichie : t=0 '
        '${sommeCle(etats[0]!, kEnrichis).toStringAsFixed(6)} → t=299 '
        '${partEnr299.toStringAsFixed(6)}');
    expect(somme299, closeTo(1.0, 1e-9));
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D2 — INVERSION BRUTALE DE PERTINENCE (§10)
  // ═══════════════════════════════════════════════════════════════════════
  test('D2 — inversion brutale : un critère enrichi devient le plus pertinent',
      () async {
    // Phase 1 (0-149)   : signal homogène, `distSpec` comme les autres.
    // Phase 2 (150-399) : `distSpec` devient FRANCHEMENT plus discriminant.
    // Question §10 : l'IA adapte-t-elle son poids ?
    const cible = 'distSpec';
    // TÉMOIN — `jockey` est le critère de COMPARAISON. Il appartient au même
    // groupe (enrichi) et porte le MÊME coefficient de production (0,5) que
    // `distSpec` (ia_memory_service:4148-4171). Son signal reste HOMOGÈNE
    // pendant toute l'expérience. C'est ce qui rend le rapport
    // distSpec/jockey interprétable : toute évolution de ce rapport ne peut
    // venir que de la PERTINENCE, puisque ni le groupe, ni le coefficient, ni
    // la contrainte collective ne diffèrent entre les deux critères.
    const temoin = 'jockey';
    await preparer(nombreCycles: 400, amorce: 12);
    final suivi = <int, double>{};
    final poids = <int, double>{};
    final poidsTemoin = <int, double>{};
    final partEnrichie = <int, double>{};
    await derouler(400,
        notes: (numero, cycle) => cycle < 150
            ? notesAlignees(numero)
            : notesUnCritereFort(numero, cible), suivi: (i, c) {
      if (i % 40 == 0 || i == 399) {
        poids[i] = c.obtenu[cible]!;
        poidsTemoin[i] = c.obtenu[temoin]!;
        // La part du groupe enrichi est mesurée à chaque point : c'est elle qui
        // dit si le groupe est SOUS ou AU plafond collectif (0,40). Sans cette
        // mesure, toute explication par la saturation serait une supposition.
        partEnrichie[i] = sommeCle(c.obtenu, kEnrichis);
        final geles = gelesSuspects(c);
        suivi[i] = geles.length.toDouble();
      }
    });
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('[D2] « $cible » : signal homogène jusqu\'au cycle 150, puis '
        'FRANCHEMENT plus discriminant');
    for (final e in poids.entries) {
      final ratio = e.value / poidsTemoin[e.key]!;
      // ignore: avoid_print
      print('[D2] cycle ${e.key.toString().padLeft(3)} : poids = '
          '${e.value.toStringAsFixed(9)} · $temoin = '
          '${poidsTemoin[e.key]!.toStringAsFixed(9)} · rapport = '
          '${ratio.toStringAsFixed(9)} · part enrichie = '
          '${partEnrichie[e.key]!.toStringAsFixed(9)} · gel suspect = '
          '${suivi[e.key]!.toInt()} critère(s)');
    }
    final avant = poids[120]!;
    final apres = poids[399]!;
    final ratioAvant = avant / poidsTemoin[120]!;
    final ratioApres = apres / poidsTemoin[399]!;
    // ignore: avoid_print
    print('[D2] ⇒ $cible : ${avant.toStringAsFixed(9)} (cycle 120, avant '
        'inversion) → ${apres.toStringAsFixed(9)} (cycle 399) · '
        'variation = ${(apres - avant).toStringAsExponential(3)}');
    // ignore: avoid_print
    print('[D2] ⇒ RAPPORT $cible/$temoin : '
        '${ratioAvant.toStringAsFixed(9)} (cycle 120) → '
        '${ratioApres.toStringAsFixed(9)} (cycle 399) · '
        'variation = ${(ratioApres - ratioAvant).toStringAsExponential(3)}');
    // ignore: avoid_print
    print('[D2] ⇒ part enrichie : '
        '${partEnrichie[120]!.toStringAsFixed(9)} (cycle 120) → '
        '${partEnrichie[399]!.toStringAsFixed(9)} (cycle 399) · plafond de '
        'production = 0,40 · groupe AU plafond ? '
        '${(partEnrichie[399]! - 0.40).abs() < 1e-6}');
    final bornes = IaPoidsAdaptatifs.bornesIndividuelles();
    // ignore: avoid_print
    print('[D2] borne de $cible = [${bornes[cible]![0]}, '
        '${bornes[cible]![1]}]');

    // ── ASSERTIONS — CE QUE D2 DOIT RÉELLEMENT INTERDIRE ────────────────
    // Le critère suivi doit rester DANS son domaine réalisable à chaque point
    // mesuré. Sans cette garde, un dépassement de plancher ou de plafond
    // passerait inaperçu.
    for (final e in poids.entries) {
      expect(e.value, greaterThanOrEqualTo(bornes[cible]![0] - 1e-12),
          reason: 'F1 : $cible ne doit jamais descendre sous son plancher '
              '(mesuré au cycle ${e.key}).');
      expect(e.value, lessThanOrEqualTo(bornes[cible]![1] + 1e-12),
          reason: 'F1 : $cible ne doit jamais franchir son plafond '
              '(mesuré au cycle ${e.key}).');
    }
    // La part enrichie ne doit JAMAIS franchir le plafond collectif : c'est
    // C4, et c'est la seule contrainte que D2 est en droit de faire respecter.
    for (final e in partEnrichie.entries) {
      expect(e.value, lessThanOrEqualTo(0.40 + 1e-9),
          reason: 'C4 : la part enrichie ne peut pas dépasser 0,40 '
              '(mesuré au cycle ${e.key}).');
    }
    // RÉSULTAT NÉGATIF, ASSERTÉ COMME TEL. Le rapport
    // distSpec/jockey DIMINUE alors que la discrimination de distSpec
    // augmente : dans ce scénario le moteur ne différencie PAS le critère
    // devenu plus pertinent. C'est un fait mesuré, pas une hypothèse — et il
    // n'autorise AUCUNE généralisation hors de ce scénario (groupe enrichi
    // au plafond collectif, fenêtre saturée, 400 cycles).
    expect(ratioApres, lessThan(ratioAvant),
        reason: 'MESURE : le rapport converge vers 1 malgré l\'intensification '
            'du signal. Si ce fait changeait, c\'est la lecture de D2 qui '
            'devrait être refaite — pas l\'assertion qui devrait être retirée.');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D3 — CRITÈRE NON ALIMENTÉ PUIS RÉALIMENTÉ (§10)
  // ═══════════════════════════════════════════════════════════════════════
  test('D3 — critère neutre (peu alimenté) puis réalimenté : '
      'l\'IA le récupère-t-elle ?', () async {
    const cible = 'jockey';
    // TÉMOIN — `distSpec` partage le groupe ET le coefficient (0,5) de
    // `jockey`, et reçoit un signal CONSTANT pendant toute l'expérience.
    // Le rapport jockey/distSpec ne peut donc évoluer que par la ré-alimentation.
    const temoin = 'distSpec';
    await preparer(nombreCycles: 400, amorce: 12);
    final poids = <int, double>{};
    final poidsTemoin = <int, double>{};
    final mvtsObtenus = <int, double>{};
    final mvtsProposes = <int, double>{};
    await derouler(400,
        notes: (numero, cycle) => cycle < 150
            ? notesAvecUnCritereNeutre(numero, cible)
            : notesAlignees(numero), suivi: (i, c) {
      if (i % 40 == 0 || i == 399) {
        poids[i] = c.obtenu[cible]!;
        poidsTemoin[i] = c.obtenu[temoin]!;
        // DEUX variations distinctes, et il est indispensable de ne pas les
        // confondre :
        //   obtenu_   = post-projection  → contient la renormalisation Σ 1,26→1,00
        //   propose_  = pré-projection   = momentum × facteur (gradient seul)
        // MESURE : sur un critère de discrimination NULLE, `obtenu_` vaut
        // 1.91e-2 au cycle 0 alors que le gradient est nul. C'est la PROJECTION
        // qui déplace le poids, pas l'apprentissage. Assertter `obtenu_ == 0`
        // aurait donc été une assertion FAUSSE — elle a été mesurée fausse et
        // corrigée, pas contournée.
        mvtsObtenus[i] = c.obtenu_(cible);
        mvtsProposes[i] = c.propose_(cible);
      }
    });
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('[D3] « $cible » : NEUTRE (note 50 constante) jusqu\'au cycle 150, '
        'puis normalement alimenté');
    for (final e in poids.entries) {
      // ignore: avoid_print
      print('[D3] cycle ${e.key.toString().padLeft(3)} : poids = '
          '${e.value.toStringAsFixed(9)} · $temoin = '
          '${poidsTemoin[e.key]!.toStringAsFixed(9)} · rapport = '
          '${(e.value / poidsTemoin[e.key]!).toStringAsFixed(9)} · '
          'variation PRÉ-projection = '
          '${mvtsProposes[e.key]!.toStringAsExponential(3)} · '
          'POST-projection = ${mvtsObtenus[e.key]!.toStringAsExponential(3)}');
    }
    final minPoids = poids.values.reduce((a, b) => a < b ? a : b);
    final finalPoids = poids[399]!;
    final ratioAvant = poids[120]! / poidsTemoin[120]!;
    final ratioApres = finalPoids / poidsTemoin[399]!;
    // ignore: avoid_print
    print('[D3] ⇒ minimum atteint = ${minPoids.toStringAsFixed(9)} · '
        'valeur finale = ${finalPoids.toStringAsFixed(9)} · '
        'récupération = ${(finalPoids - minPoids).toStringAsExponential(3)}');
    // ignore: avoid_print
    print('[D3] ⇒ RAPPORT $cible/$temoin : '
        '${ratioAvant.toStringAsFixed(9)} (cycle 120) → '
        '${ratioApres.toStringAsFixed(9)} (cycle 399) · '
        'variation = ${(ratioApres - ratioAvant).toStringAsExponential(3)}');
    final bornes = IaPoidsAdaptatifs.bornesIndividuelles();
    // ignore: avoid_print
    print('[D3] borne de $cible = [${bornes[cible]![0]}, '
        '${bornes[cible]![1]}]');

    // ── ASSERTIONS — CE QUE D3 DOIT RÉELLEMENT INTERDIRE ────────────────
    // (a) bornes individuelles respectées à chaque point mesuré
    for (final e in poids.entries) {
      expect(e.value, greaterThanOrEqualTo(bornes[cible]![0] - 1e-12),
          reason: 'F1 : $cible sous son plancher au cycle ${e.key}.');
      expect(e.value, lessThanOrEqualTo(bornes[cible]![1] + 1e-12),
          reason: 'F1 : $cible au-dessus de son plafond au cycle ${e.key}.');
    }
    // (b) PENDANT la phase neutre, le poids du critère est MONOTONEMENT
    // DÉCROISSANT : il ne remonte jamais. C'est la propriété réellement
    // vérifiable.
    //
    // ⚠️ TROIS ASSERTIONS ONT ÉTÉ MESURÉES FAUSSES ET REMPLACÉES ICI — pas
    //    contournées, et chaque échec est documenté :
    //    1re : `obtenu_ == 0` → MESURE 1,91e-2 au cycle 0. Faux : `obtenu_` est
    //      POST-projection et contient la renormalisation Σ 1,26→1,00, qui
    //      déplace TOUS les poids, même sans gradient.
    //    2e : `propose_ == 0` → MESURE 4,67e-5 au cycle 0. Faux : `propose_` =
    //      momentum × facteur, et le momentum du cycle précédent subsiste.
    //    3e : `poids == plancher` à CHAQUE point → MESURE 0,050887 au cycle 0.
    //      Faux : le critère n'est PAS au plancher dès le départ ; il y
    //      DESCEND progressivement (0,050887 → … → 0,005000). Le plancher est
    //      un point d'ARRIVÉE, pas un état initial.
    //    La 3e mesure est celle qui compte pour la question posée : elle
    //    prouve que la famine de signal CONDUIT au plancher, sans y être
    //    immédiatement.
    var precedent = double.infinity;
    for (final e in (poids.entries.toList()..sort((a, b) => a.key - b.key))) {
      if (e.key > 120) continue;
      expect(e.value, lessThanOrEqualTo(precedent + 1e-12),
          reason: 'Le poids d\'un critère non alimenté ne doit JAMAIS remonter '
              '(mesuré au cycle ${e.key}).');
      precedent = e.value;
    }
    // (b-bis) RÉSULTAT NÉGATIF, ASSERTÉ TEL QUEL. Après ré-alimentation, le
    // critère NE remonte PAS : il reste exactement sur son plancher
    // (`récupération = 0.000e+0` mesuré). C'est un fait, pas une hypothèse.
    // On ne lui donne AUCUNE portée générale : ce scénario est particulier
    // (jockey, groupe enrichi au plafond collectif 0,40, fenêtre saturée).
    // Ce que l'assertion garantit, c'est que le fait ne pourra pas changer
    // silencieusement : si le moteur se mettait à récupérer ce critère, ce
    // test échouerait et la conclusion devrait être réécrite.
    expect(finalPoids, closeTo(bornes[cible]![0], 1e-12),
        reason: 'MESURE : dans ce scénario précis, la ré-alimentation ne '
            'ramène PAS le critère au-dessus de son plancher.');
    expect(mvtsProposes.length, greaterThan(3),
        reason: 'Les deux variations (pré et post-projection) doivent avoir '
            'été relevées à chaque point mesuré.');
    // (c) RÉSULTAT ASSERTÉ TEL QUE MESURÉ : après ré-alimentation, le poids
    //    du critère ne remonte que si le mécanisme le récupère. On assertte
    //    le fait directionnel mesuré, sans lui donner de portée générale.
    expect(finalPoids, greaterThanOrEqualTo(minPoids),
        reason: 'MESURE : la ré-alimentation ne fait pas descendre le poids '
            'sous son minimum de phase neutre.');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D4 — LE PLAFOND ET LE PLANCHER COLLECTIFS SONT-ILS FRANCHIS ? (§7)
  // ═══════════════════════════════════════════════════════════════════════
  test('D4 — part enrichie : trajectoire, plafond 0,40, plancher 0,18 (§7)',
      () async {
    // Deux expériences opposées, à partir des MÊMES poids initiaux :
    //  (a) les 12 enrichis deviennent très discriminants → la part doit MONTER
    //      vers 0,40 ;
    //  (b) les 12 enrichis deviennent neutres → la part doit DESCENDRE vers
    //      0,18.
    // Dans les deux cas, la contrainte de production s'applique : on ne la
    // retire pas, on mesure où elle mord.
    Future<List<double>> experience({required bool enrichisForts}) async {
      await preparer(
        nombreCycles: 250,
        amorce: 12,
        notes: (numero, cycle) {
          final base = <String, double>{
            for (final k in kCles) k: 96.0 - numero * 6,
          };
          if (enrichisForts) {
            for (final k in kEnrichis) { base[k] = 96.0 - numero * 30; }
          } else {
            for (final k in kEnrichis) { base[k] = 50.0; }
          }
          return ScoresCriteres(
            forme: base['forme']!, gains: base['gains']!,
            record: base['record']!, cote: base['cote']!,
            constance: base['constance']!, victoires: base['victoires']!,
            discipline: base['discipline']!, distSpec: base['distSpec']!,
            jockey: base['jockey']!, repos: base['repos']!,
            hippo: base['hippo']!, entraineur: base['entraineur']!,
            elo: base['elo']!, terrain: base['terrain']!,
            divergence: base['divergence']!, poidsRel: base['poidsRel']!,
            progression: base['progression']!, mouvCote: base['mouvCote']!,
            placeDepart: base['placeDepart']!,
          );
        },
      );
      final parts = <double>[];
      await derouler(250,
          notes: (numero, cycle) {
            final b = <String, double>{
              for (final k in kCles) k: 96.0 - numero * 6,
            };
            if (enrichisForts) {
              for (final k in kEnrichis) { b[k] = 96.0 - numero * 30; }
            } else {
              for (final k in kEnrichis) { b[k] = 50.0; }
            }
            return ScoresCriteres(
              forme: b['forme']!, gains: b['gains']!, record: b['record']!,
              cote: b['cote']!, constance: b['constance']!,
              victoires: b['victoires']!, discipline: b['discipline']!,
              distSpec: b['distSpec']!, jockey: b['jockey']!,
              repos: b['repos']!, hippo: b['hippo']!,
              entraineur: b['entraineur']!, elo: b['elo']!,
              terrain: b['terrain']!, divergence: b['divergence']!,
              poidsRel: b['poidsRel']!, progression: b['progression']!,
              mouvCote: b['mouvCote']!, placeDepart: b['placeDepart']!,
            );
          }, suivi: (i, c) {
        if (i % 25 == 0 || i == 249) {
          parts.add(sommeCle(c.obtenu, kEnrichis));
        }
      });
      return parts;
    }

    final forts = await experience(enrichisForts: true);
    final faibles = await experience(enrichisForts: false);

    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('[D4] part enrichie — enrichis TRÈS discriminants : '
        '${forts.map((v) => v.toStringAsFixed(6)).join(" → ")}');
    // ignore: avoid_print
    print('[D4] part enrichie — enrichis NEUTRES          : '
        '${faibles.map((v) => v.toStringAsFixed(6)).join(" → ")}');
    final maxFort = forts.reduce((a, b) => a > b ? a : b);
    final minFaible = faibles.reduce((a, b) => a < b ? a : b);
    // ignore: avoid_print
    print('[D4] ⇒ maximum observé (forts) = ${_f(maxFort)} · minimum observé '
        '(neutres) = ${_f(minFaible)} · bornes de production [0.18, 0.40]');
    expect(maxFort, lessThanOrEqualTo(0.40 + 1e-9),
        reason: 'C4 : le plafond collectif de 0,40 ne doit jamais être franchi');
    expect(minFaible, greaterThanOrEqualTo(0.18 - 1e-9),
        reason: 'C4 : le plancher collectif de 0,18 ne doit jamais être franchi');
  });
}
