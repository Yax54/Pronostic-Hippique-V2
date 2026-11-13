// ═══════════════════════════════════════════════════════════════════════════
//  V8 — AUDIT PRÉALABLE D2/H8 : rattrapage des journées manquées
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT. AUCUNE modification de lib/.
//      Aucun appel réseau réel. Aucune donnée utilisateur touchée.
//
//  Ces tests MESURENT les chemins réels avant d'autoriser les paliers 1/2/3.
//  Scénario de référence :
//    ouverture le 09/11 → silence 10, 11, 12 → retour le 13/11
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/ia_pronostic_engine.dart';

// ─────────────────────────── Outils ────────────────────────────────────────

String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

String _j(int offsetJours) => _fmt(DateTime.now().add(Duration(days: offsetJours)));

ZtPartant _p(int n) => ZtPartant(
      numero: '$n',
      nom: 'CHEVAL_$n',
      driver: 'D$n',
      entraineur: 'E$n',
      proprietaire: 'P$n',
      gains: '${1000 * n}',
      record: '1\'10"0',
      musique: '1a2a3a4a5a',
      cote: '4.0',
      ageSexe: '5 M',
      poids: 57.0 + n,
      placeDepartInt: n,
      joursRepos: 10 + n,
      hippodromeActuel: 'VINCENNES',
      statsJockeyCsv: 'J|15|40|12',
      statsHippodromeCsv: 'V|20|45|15',
      statsEntraineurCsv: 'E|12|33|8',
      eloRating: 1500.0 + n * 10,
      eloNbCourses: 20,
      eloVariationMois: 5.0,
      statsTerrainCsv: 'bon|6|2|4',
      gainsDernierAn: n * 5000,
    );

ZtCourse _course(int num, String date) => ZtCourse(
      numCourse: num,
      anchor: 'R1C$num',
      nom: 'PRIX_$num',
      heure: '14:15',
      distance: '2700',
      prix: '50000',
      type: 'Trot Attelé',
      piste: 'Sable',
      categorie: 'D',
      isQuinte: true,
      pronosticZt: const [1, 2, 3, 4, 5],
      partants: List.generate(8, (j) => _p(j + 1)),
      dateStr: date,
    );

ZtReunion _reunion({
  String code = 'R1',
  int nbCourses = 2,
  required String date,
}) =>
    ZtReunion(
      code: code,
      lieu: 'VINCENNES',
      discipline: 'Trot',
      dateStr: date,
      courses: List.generate(nbCourses, (i) => _course(i + 1, date)),
    );

Map<String, Object> _prefs() => <String, Object>{
      'ia_precision_migrated_v3': true,
      'ia_poids_v3': json.encode({
        'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
        'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
        'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
        'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05,
        'divergence': 0.04, 'poidsRel': 0.03, 'progression': 0.03,
        'mouvCote': 0.06, 'placeDepart': 0.03,
        'nbMisesAJour': 0, 'calibrationScore': 50.0,
      }),
      'ia_seuils_v1': json.encode({}),
      'ia_precision_v2': json.encode({}),
      'ia_stats_labels_v1': json.encode({}),
      'ia_stats_types_v1': <String>[],
      'ia_journal_v2': <String>[],
    };

/// Crée des pronostics par le chemin BATCH réel (celui de DataRefreshService).
Future<void> _creerPronostics(List<ZtReunion> reunions) async {
  final batch = <Map<String, dynamic>>[];
  for (final r in reunions) {
    final m = RegExp(r'R(\d+)').firstMatch(r.code);
    final numR = m != null ? int.tryParse(m.group(1) ?? '1') ?? 1 : 1;
    for (final c in r.courses) {
      final key = 'R${numR}C${c.numCourse}_${_fmt(c.heureDateTime)}';
      if (IaMemoryService.instance.getPronostic(key) != null) continue;
      final (pc, sc) = IaPronosticEngine.analyserCourseAvecCriteres(c);
      batch.add({
        'courseKey': key, 'course': c, 'partantsClasses': pc,
        'scoresCriteres': sc, 'confiance': c.confianceIA,
        'typePariConseille': 'Quinté+',
      });
    }
  }
  await IaMemoryService.instance.enregistrerPronosticsBatch(batch);
}

List<String> _cles() =>
    IaMemoryService.instance.pronostics.map((p) => p.courseKey).toList();

// ─────────────────────────── Tests ─────────────────────────────────────────

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(_prefs());
    await EloService.instance.reinitialiser();
    await IaMemoryService.instance.recharger();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R1 — LA FENÊTRE DE RATTRAPAGE EST BORNÉE À J-1 ET J-2
  //       ia_performance_screen.dart:499 → for (final j in [2, 1])
  //       Le 10/11 (J-3 vu du 13/11) n'est JAMAIS candidat.
  // ═══════════════════════════════════════════════════════════════════════
  test('R1 — le rattrapage ne considère que J-1 et J-2, jamais J-3', () {
    const fenetreCode = [2, 1];
    final aujourdhui = DateTime.now();
    final candidats = fenetreCode
        .map((j) => _fmt(aujourdhui.subtract(Duration(days: j))))
        .toList();

    // ignore: avoid_print
    print('  [R1] fenêtre codée en dur : $fenetreCode → candidats = $candidats');
    // ignore: avoid_print
    print('  [R1] journées silencieuses : J-3=${_j(-3)} J-2=${_j(-2)} '
        'J-1=${_j(-1)}');

    expect(candidats.length, 2, reason: 'seulement 2 journées rattrapables');
    expect(candidats.contains(_j(-3)), isFalse,
        reason: 'DÉFAUT : J-3 est structurellement hors de la fenêtre');
    expect(candidats.contains(_j(-2)), isTrue);
    expect(candidats.contains(_j(-1)), isTrue);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R2 — ORDRE DE TRAITEMENT : J-2 puis J-1 (chronologique)
  // ═══════════════════════════════════════════════════════════════════════
  test('R2 — l\'ordre est chronologique : J-2 traité avant J-1', () {
    const fenetre = [2, 1];
    final ordre = fenetre.map((j) => 'J-$j').toList();
    // ignore: avoid_print
    print('  [R2] ordre réel : $ordre');
    expect(ordre, ['J-2', 'J-1'],
        reason: 'du plus ancien au plus récent — correct pour '
            'l\'apprentissage séquentiel');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R3 — LE FICHIER RAPPORT N'EST JAMAIS ÉCRIT POUR UNE JOURNÉE RATTRAPÉE
  //       ia_performance_screen.dart:606 → _sauvegarderFichierRapport(
  //       resultat, _dateAnalyse) : UN SEUL appel, jamais pour J-1/J-2.
  //       → statut reste 'absent' → rattrapage rejoué à chaque appui.
  // ═══════════════════════════════════════════════════════════════════════
  test('R3 — rien ne mémorise qu\'une journée a déjà été rattrapée', () async {
    final dateJ2 = _j(-2);
    final reunions = [_reunion(code: 'R1', nbCourses: 2, date: dateJ2)];
    await _creerPronostics(reunions);
    // ignore: avoid_print
    print('  [R3] pronostics J-2 ($dateJ2) : ${_cles()}');

    // 2e passe identique (ce que produit un 2e appui sur le bouton)
    final nb2 =
        await IaMemoryService.instance.recreerPronosticsManquants(reunions);
    // ignore: avoid_print
    print('  [R3] 2e passe → nb=$nb2 (0 = pas de doublon)');

    expect(nb2, 0, reason: 'pas de doublon');
    expect(_cles().length, 2,
        reason: 'mais rien ne persiste l\'état « journée traitée » : le '
            'fichier rapport devait le faire et n\'est jamais écrit pour J-1/J-2');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R4 — LA RÉCUPÉRATION AUTO DES RÉSULTATS EST BORNÉE À 24 H
  //       data_refresh_service.dart:845 → if (courseDiff.inHours > 24) continue;
  // ═══════════════════════════════════════════════════════════════════════
  test('R4 — la récupération auto des résultats est bornée à 24 h', () {
    bool peutRecuperer(Duration age) {
      if (age.inMinutes < 10) return false;
      if (age.inHours > 24) return false;
      return true;
    }

    final cas = {
      'aujourd\'hui (2h)': const Duration(hours: 2),
      'J-1 (26h)': const Duration(hours: 26),
      'J-2 (50h)': const Duration(hours: 50),
      'J-3 (74h)': const Duration(hours: 74),
    };
    for (final e in cas.entries) {
      // ignore: avoid_print
      print('  [R4] ${e.key} → auto = ${peutRecuperer(e.value)}');
    }

    expect(peutRecuperer(const Duration(hours: 2)), isTrue);
    expect(peutRecuperer(const Duration(hours: 26)), isFalse,
        reason: 'J-1 est déjà exclu de la voie automatique');
    expect(peutRecuperer(const Duration(hours: 50)), isFalse);
    expect(peutRecuperer(const Duration(hours: 74)), isFalse);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R5 — RÉSULTATS SANS PRONOSTIC : journée invisible
  //       analyseJourneeComplete() part de `_pronostics` (l.3031).
  // ═══════════════════════════════════════════════════════════════════════
  test('R5 — sans pronostic, la journée est invisible pour l\'analyse', () {
    expect(IaMemoryService.instance.pronostics, isEmpty);

    final reunions = [_reunion(code: 'R1', nbCourses: 2, date: _j(-2))];
    final listeTravail = IaMemoryService.instance.pronostics
        .where((p) => !p.resultatsReels)
        .toList();

    // ignore: avoid_print
    print('  [R5] programme disponible : ${reunions.first.courses.length} '
        'courses ; pronostics mémoire : '
        '${IaMemoryService.instance.pronostics.length}');
    // ignore: avoid_print
    print('  [R5] → liste de travail = ${listeTravail.length} '
        '(aucune requête PMU possible)');

    expect(listeTravail, isEmpty,
        reason: 'DÉFAUT : sans pronostic, aucun résultat récupérable même '
            'si le programme et l\'arrivée PMU existent');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R6 — AUCUN DÉCLENCHEUR AUTOMATIQUE DU RATTRAPAGE
  //       _lancerAnalyseJournee() : 2 occurrences (déf. l.461, onTap l.1535)
  // ═══════════════════════════════════════════════════════════════════════
  test('R6 — le rattrapage exige un appui manuel', () {
    const appelants = <String>[
      'ia_performance_screen.dart:461 (définition)',
      'ia_performance_screen.dart:1535 (onTap bouton)',
    ];
    // ignore: avoid_print
    print('  [R6] appelants = $appelants');
    // ignore: avoid_print
    print('  [R6] → hors appui manuel, rien n\'est rattrapé');

    expect(appelants.length, 2);
    expect(
        appelants.any((a) =>
            a.contains('initState') ||
            a.contains('postFrameCallback') ||
            a.contains('Timer')),
        isFalse,
        reason: 'DÉFAUT : l\'utilisateur qui revient après 4 jours doit '
            'appuyer lui-même, sinon aucune journée n\'est rattrapée');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R7 — LES PARIS UTILISATEUR SONT RÉINJECTÉS À CHAQUE PASSE
  //       mais mettreAJourStatsTypes() fait clear() → pas de sur-comptage
  // ═══════════════════════════════════════════════════════════════════════
  test('R7 — paris utilisateur : pas de sur-comptage entre passes', () async {
    final predictions = [
      {'typePari': 'Simple Gagnant', 'isCorrect': true, 'gainNet': 12.0},
    ];
    // 3 passes avec la même liste (J-2, J-1, jour courant)
    for (var i = 0; i < 3; i++) {
      await IaMemoryService.instance.mettreAJourStatsTypes(predictions);
    }

    final sg = IaMemoryService.instance.statsParType
        .where((s) => s.typePari == 'Simple Gagnant')
        .firstOrNull;

    // ignore: avoid_print
    print('  [R7] 3 passes, 1 pari → nbJoues=${sg?.nbJoues} (attendu 1)');
    expect(sg?.nbJoues, 1,
        reason: 'clear() + recalcul depuis la liste complète → conforme');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R8 — UNE JOURNÉE REJOUÉE NE DOUBLE PAS LES RÉSULTATS
  //       protection : nouveauxResolusParPasse (l.3475) + resultatsReels
  // ═══════════════════════════════════════════════════════════════════════
  test('R8 — une journée rejouée ne double pas les résultats', () async {
    final date = _j(-2);
    final reunions = [_reunion(code: 'R1', nbCourses: 2, date: date)];
    await _creerPronostics(reunions);

    for (final k in _cles()) {
      await IaMemoryService.instance.enregistrerResultat(
        courseKey: k,
        arriveeReelle: const [1, 2, 3, 4, 5],
      );
    }
    final etat1 =
        IaMemoryService.instance.pronostics.where((p) => p.resultatsReels).length;

    final nb =
        await IaMemoryService.instance.recreerPronosticsManquants(reunions);
    final etat2 =
        IaMemoryService.instance.pronostics.where((p) => p.resultatsReels).length;

    // ignore: avoid_print
    print('  [R8] résolus avant=$etat1 après=$etat2 ; recréés=$nb');
    expect(nb, 0);
    expect(etat2, etat1, reason: 'état stable — pas de double résolution');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R9 — UNE JOURNÉE ANCIENNE N'ENTRE EN MÉMOIRE QUE PAR LE BATCH AUTO
  // ═══════════════════════════════════════════════════════════════════════
  test('R9 — journée ancienne : batch auto oui, recréation non', () async {
    final dateAncienne = _j(-2);

    final nbRecree = await IaMemoryService.instance
        .recreerPronosticsManquants(
            [_reunion(code: 'R1', nbCourses: 2, date: dateAncienne)]);
    // ignore: avoid_print
    print('  [R9] recreerPronosticsManquants(J-2) → $nbRecree (0 = refus)');
    expect(nbRecree, 0);

    await _creerPronostics(
        [_reunion(code: 'R1', nbCourses: 2, date: dateAncienne)]);
    // ignore: avoid_print
    print('  [R9] batch auto(J-2) → ${_cles().length} créés');
    expect(_cles().length, 2);

    // Conséquence : si l'app n'a jamais tourné ce jour-là, la journée n'a
    // aucun pronostic et ne peut PLUS en recevoir par la recréation.
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R10 — LE GARDE-FOU D2/H8 NE BLOQUE PAS LA LECTURE DES PRONOSTICS
  //        analyseJourneeComplete() lit `_pronostics`, ne crée jamais rien.
  // ═══════════════════════════════════════════════════════════════════════
  test('R10 — le futur garde-fou ne bloque pas la récupération des résultats',
      () async {
    await _creerPronostics(
        [_reunion(code: 'R1', nbCourses: 2, date: _j(-2))]);
    expect(_cles().length, 2);

    final consommes = IaMemoryService.instance.pronostics
        .where((p) => !p.resultatsReels)
        .length;

    // ignore: avoid_print
    print('  [R10] pronostics exploitables = $consommes');
    // ignore: avoid_print
    print('  [R10] → garde-fou = refus de CRÉER dans le passé ; '
        'la LECTURE reste intacte');

    expect(consommes, 2,
        reason: 'le garde-fou ne concerne que la création, pas la lecture');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R11 — `now = date ?? DateTime.now()` : l'HEURE COURANTE EST CONSERVÉE,
  //        seule la date est remplacée.
  //
  //  ia_memory_service.dart:2994  → final now = date ?? DateTime.now();
  //  ia_memory_service.dart:3213  → diffMin = heureCourse.difference(now)
  //
  //  Pour un rattrapage de J-2 à 10 h du matin :
  //      now  = J-2 à 10h00
  //      course = J-2 à 14h15  →  diffMin = +255  → « Course à venir »
  //                              → la course est SAUTÉE, aucun résultat
  //
  //  Le même appui à 20 h donnerait diffMin = -255 → analyse normale.
  //  → Une journée rattrapée le matin est définitivement perdue,
  //    alors qu'elle a déjà eu lieu.
  // ═══════════════════════════════════════════════════════════════════════
  test('R11 — rattraper J-2 le matin classe ses courses du passé en '
      '« à venir » et les saute', () {
    // Reproduit l'arithmétique exacte de la méthode
    int diffMinPour(DateTime dateCible, int heureCourante, int heureCourse) {
      final now = DateTime(dateCible.year, dateCible.month, dateCible.day,
          heureCourante, 0);
      final course = DateTime(dateCible.year, dateCible.month, dateCible.day,
          heureCourse, 15);
      return course.difference(now).inMinutes;
    }

    final j2 = DateTime.now().subtract(const Duration(days: 2));
    // Courses réelles de J-2 à 14h15 ; rattrapage lancé le 13/11 à 10h00
    final diffMatin = diffMinPour(j2, 10, 14);
    // Même rattrapage lancé à 20h00
    final diffSoir = diffMinPour(j2, 20, 14);

    final labelMatin = diffMatin > 0 ? '« à venir » → SAUTÉE' : 'analysée';
    final labelSoir = diffSoir > 0 ? '« à venir » → SAUTÉE' : 'analysée';

    // ignore: avoid_print
    print('  [R11] J-2 à 10h00 → diffMin=$diffMatin ($labelMatin)');
    // ignore: avoid_print
    print('  [R11] J-2 à 20h00 → diffMin=$diffSoir ($labelSoir)');

    expect(diffMatin, greaterThan(0),
        reason: 'DÉFAUT : à 10 h, une course de J-2 déjà courue est vue '
            'comme future → comptée nbCoursesFutures et ignorée');
    expect(diffSoir, lessThan(-30),
        reason: 'au soir, le même rattrapage fonctionne — le résultat dépend '
            'donc de l\'heure de l\'appui, pas de la réalité de la course');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R12 — CE QUI SURVIT À LA FERMETURE
  //
  //  Sauvegardé : pronostics, poids, seuils, stats, journal, rapports.
  //  NON sauvegardé : le statut « journée déjà rattrapée » — qui n'existe
  //  pas en mémoire, seulement le fichier rapport (jamais écrit pour J-1/J-2).
  //  → après redémarrage, la trace « cette journée a été traitée » est perdue.
  // ═══════════════════════════════════════════════════════════════════════
  test('R12 — les pronostics survivent, la marque « journée traitée » non',
      () async {
    final dateJ2 = _j(-2);
    final reunions = [_reunion(code: 'R1', nbCourses: 2, date: dateJ2)];
    await _creerPronostics(reunions);
    expect(_cles().length, 2);

    // Redémarrage : recharger() vide puis relit le disque
    await IaMemoryService.instance.recharger();
    final apresRedemarrage = _cles();

    // ignore: avoid_print
    print('  [R12] après redémarrage : $apresRedemarrage');

    expect(apresRedemarrage.length, 2,
        reason: 'les pronostics sont bien restaurés depuis le disque');

    // Ce qui manque : aucun indicateur persistant « J-2 déjà rattrapée ».
    // La seule marque prévue est le fichier ia_analyse_JJMMAAAA_*.json,
    // or _sauvegarderFichierRapport() n'est appelé que pour _dateAnalyse.
    // ignore: avoid_print
    print('  [R12] → aucune marque « journée traitée » en mémoire : '
        'seul le fichier rapport la porterait, et il n\'est pas écrit '
        'pour J-1/J-2');
  });
}
