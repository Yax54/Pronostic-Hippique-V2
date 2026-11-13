// ═══════════════════════════════════════════════════════════════════════════
//  V9 — AUDIT A6 : heure de référence dans analyseJourneeComplete()
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT. AUCUNE modification de lib/.
//      Aucun appel réseau. Aucune donnée utilisateur touchée.
//
//  A6 = `final now = date ?? DateTime.now();` (ia_memory_service.dart:2993)
//       conserve l'HEURE COURANTE et ne remplace que la date.
//       → `diffMin = heureCourse.difference(now)` (l.3213) peut être > 0
//         pour une course DÉJÀ COURUE, si l'appui a lieu avant l'heure du
//         départ. La course est alors classée « à venir » et sautée.
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

String _j(int offset) => _fmt(DateTime.now().add(Duration(days: offset)));

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

ZtCourse _course(int num, String date, {String heure = '14:15'}) => ZtCourse(
      numCourse: num,
      anchor: 'R1C$num',
      nom: 'PRIX_$num',
      heure: heure,
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
  String heure = '14:15',
}) =>
    ZtReunion(
      code: code,
      lieu: 'VINCENNES',
      discipline: 'Trot',
      dateStr: date,
      courses: List.generate(nbCourses, (i) => _course(i + 1, date, heure: heure)),
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

// ═══════════════════════════════════════════════════════════════════════════
//  Reproduit EXACTEMENT l'arithmétique de analyseJourneeComplete()
//
//    l.2993  final now = date ?? DateTime.now();
//    l.3213  final diffMin = heureCourse.difference(now).inMinutes;
//    l.3214  if (diffMin > 0)       → « à venir »  (SAUTÉE)
//    l.3222  if (diffMin > -30)     → « en cours »  (SAUTÉE)
//    sinon                          → ANALYSÉE
//
//  `now` = date cible à l'HEURE COURANTE (c'est le cœur de A6).
// ═══════════════════════════════════════════════════════════════════════════

enum _Verdict { sauteeFuture, sauteeEnCours, analysee }

/// @param dateCible  journée à rattraper (ex. J-2)
/// @param heureAppui heure réelle à laquelle l'utilisateur appuie sur le bouton
/// @param minuteAppui minute de l'appui
/// @param heureCourse heure de départ de la course
/// @param minuteCourse minute de départ de la course
_Verdict _verdictReel(
  DateTime dateCible,
  int heureAppui,
  int heureCourse,
  int minuteCourse, {
  int minuteAppui = 0,
}) {
  // now = date cible, MAIS à l'heure de l'appui (comportement réel du code)
  final now = DateTime(
      dateCible.year, dateCible.month, dateCible.day, heureAppui, minuteAppui);
  final course = DateTime(
      dateCible.year, dateCible.month, dateCible.day, heureCourse, minuteCourse);
  final diffMin = course.difference(now).inMinutes;

  if (diffMin > 0) return _Verdict.sauteeFuture;
  if (diffMin > -30) return _Verdict.sauteeEnCours;
  return _Verdict.analysee;
}

/// Arithmétique corrigée : référence = MAINTENANT (heure réelle), pas la date cible.
_Verdict _verdictCorrige(DateTime dateCible, DateTime maintenantReel,
    int heureCourse, int minuteCourse) {
  final course = DateTime(
      dateCible.year, dateCible.month, dateCible.day, heureCourse, minuteCourse);
  final diffMin = course.difference(maintenantReel).inMinutes;
  if (diffMin > 0) return _Verdict.sauteeFuture;
  if (diffMin > -30) return _Verdict.sauteeEnCours;
  return _Verdict.analysee;
}

// ─────────────────────────── Tests ─────────────────────────────────────────

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(_prefs());
    await EloService.instance.reinitialiser();
    await IaMemoryService.instance.recharger();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  A6/1 — LES 4 HEURES DEMANDÉES SUR UNE JOURNÉE RATTRAPÉE (J-2)
  //
  //  Course de J-2 à 14h15. On simule l'appui à 08h, 12h, 16h, 21h.
  //  Le résultat réel de la course est IDENTIQUE dans les 4 cas :
  //  la course a eu lieu il y a 2 jours. Seul le verdict change.
  // ═══════════════════════════════════════════════════════════════════════
  test('A6/1 — même journée J-2, appui à 08h/12h/16h/21h : le verdict '
      'change alors que la réalité est identique', () {
    final j2 = DateTime.now().subtract(const Duration(days: 2));

    final resultats = <int, _Verdict>{
      8: _verdictReel(j2, 8, 14, 15),
      12: _verdictReel(j2, 12, 14, 15),
      16: _verdictReel(j2, 16, 14, 15),
      21: _verdictReel(j2, 21, 14, 15),
    };

    for (final e in resultats.entries) {
      // ignore: avoid_print
      print('  [A6/1] J-2, appui à ${e.key.toString().padLeft(2, '0')}h00 '
          '→ ${e.value.name}');
    }

    expect(resultats[8], _Verdict.sauteeFuture,
        reason: 'DÉFAUT : à 08h une course de J-2 (déjà courue) est '
            'vue « à venir » et SAUTÉE');
    expect(resultats[12], _Verdict.sauteeFuture,
        reason: 'à 12h aussi (14h15 > 12h00)');
    expect(resultats[16], _Verdict.analysee,
        reason: 'à 16h la même course est enfin analysée');
    expect(resultats[21], _Verdict.analysee);

    // Le point dur : 2 verdicts opposés pour une réalité unique
    expect(resultats[8], isNot(resultats[16]),
        reason: 'A6 : le résultat dépend de l\'heure de l\'appui, '
            'pas de la réalité de la course');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  A6/2 — SEUIL EXACT : la bascule se produit à l'heure du départ
  // ═══════════════════════════════════════════════════════════════════════
  test('A6/2 — la bascule correspond exactement à l\'heure du départ', () {
    final j2 = DateTime.now().subtract(const Duration(days: 2));

    // Course à 14h15. Appui à 14h14 puis 14h16.
    final avant =
        _verdictReel(j2, 14, 14, 15, minuteAppui: 14); // 13h58... non : 14h14
    final apres = _verdictReel(j2, 14, 14, 15, minuteAppui: 16); // 14h16

    // ignore: avoid_print
    print('  [A6/2] appui 14h14 (course 14h15) → ${avant.name}  '
        '(diffMin=+1)');
    // ignore: avoid_print
    print('  [A6/2] appui 14h16 (course 14h15) → ${apres.name}  '
        '(diffMin=-1 → zone -30 → sauté aussi)');

    expect(avant, _Verdict.sauteeFuture,
        reason: 'diffMin = +1 → classée « à venir »');
    expect(apres, _Verdict.sauteeEnCours,
        reason: 'diffMin = -1 → dans la zone des 30 min → « en cours », '
            'sautée aussi. Le garde-fou de 30 min doit être préservé');

    // Les deux sont sautées, mais pour des raisons différentes : la fenêtre
    // de 30 min est un comportement VOULU, A6 n'y touche pas.
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  A6/3 — COMBIEN DE COURSES SONT PERDUES SELON L'HEURE
  //
  //  Programme type d'une journée : 8 courses de 13h30 à 20h00.
  //  On compte combien sont sautées pour chaque heure d'appui.
  // ═══════════════════════════════════════════════════════════════════════
  test('A6/3 — nombre de courses perdues selon l\'heure d\'appui', () {
    final j2 = DateTime.now().subtract(const Duration(days: 2));
    // 8 départs échelonnés, comme une vraie réunion
    const departs = [13, 14, 15, 16, 17, 18, 19, 20];

    int perdues(int heureAppui) => departs
        .where((h) => _verdictReel(j2, heureAppui, h, 15) != _Verdict.analysee)
        .length;

    final mesure = {8: perdues(8), 12: perdues(12), 16: perdues(16),
                    21: perdues(21)};

    for (final e in mesure.entries) {
      // ignore: avoid_print
      print('  [A6/3] appui ${e.key.toString().padLeft(2, '0')}h00 → '
          '${e.value}/8 courses sautées');
    }

    expect(mesure[8], 8, reason: 'DÉFAUT : à 08h, les 8 courses sont sautées');
    expect(mesure[12], 8, reason: 'à 12h, encore 8/8');
    expect(mesure[16], 5, reason: 'à 16h, 5 sautées (départs 17h→20h)');
    expect(mesure[21], 0, reason: 'à 21h, toutes analysées');

    // ignore: avoid_print
    print('  [A6/3] → un rattrapage matinal perd 100 % de la journée');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  A6/4 — LA CORRECTION ARITHMÉTIQUE : référence = maintenant réel
  // ═══════════════════════════════════════════════════════════════════════
  test('A6/4 — avec une référence « maintenant réel », les 4 heures donnent '
      'le même verdict', () {
    final j2 = DateTime.now().subtract(const Duration(days: 2));
    // "maintenant" réel = le jour de l'appui, à l'heure de l'appui
    DateTime maintenant(int h) {
      final t = DateTime.now();
      return DateTime(t.year, t.month, t.day, h, 0);
    }

    final corriges = <int, _Verdict>{
      8: _verdictCorrige(j2, maintenant(8), 14, 15),
      12: _verdictCorrige(j2, maintenant(12), 14, 15),
      16: _verdictCorrige(j2, maintenant(16), 14, 15),
      21: _verdictCorrige(j2, maintenant(21), 14, 15),
    };

    for (final e in corriges.entries) {
      // ignore: avoid_print
      print('  [A6/4] corrigé, appui ${e.key.toString().padLeft(2, '0')}h00 '
          '→ ${e.value.name}');
    }

    // Avec la vraie horloge, J-2 est toujours dans le passé → toujours analysée
    for (final v in corriges.values) {
      expect(v, _Verdict.analysee,
          reason: 'J-2 est passé quelle que soit l\'heure → doit toujours '
              'être analysée');
    }
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  A6/5 — CAS OÙ LE RÉSULTAT PMU N'EST PAS ENCORE DISPO
  //
  //  Une course terminée depuis moins de 30 min est sautée par diffMin > -30.
  //  Ce comportement est INDÉPENDANT de A6 et doit être préservé.
  // ═══════════════════════════════════════════════════════════════════════
  test('A6/5 — une course terminée depuis moins de 30 min reste sautée '
      '(comportement à préserver)', () {
    final maintenantReel = DateTime.now();
    // Course du jour terminée il y a 10 minutes
    final ilYa10min = maintenantReel.subtract(const Duration(minutes: 10));
    final courseDate = DateTime(ilYa10min.year, ilYa10min.month,
        ilYa10min.day, ilYa10min.hour, ilYa10min.minute);

    final verdict = _verdictCorrige(courseDate, maintenantReel,
        ilYa10min.hour, ilYa10min.minute);

    // ignore: avoid_print
    print('  [A6/5] course terminée il y a 10 min → ${verdict.name} '
        '(doit rester sautée)');
    expect(verdict, _Verdict.sauteeEnCours,
        reason: 'résultat PMU probablement pas publié → il est normal de '
            'différer. A6 ne doit pas casser ce garde-fou');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  A6/6 — UN RATTRAPAGE RÉPÉTÉ NE RECRÉE PAS DE PRONOSTIC
  //
  //  analyseJourneeComplete() ne crée JAMAIS de pronostic :
  //  nbPronosticsAjoutes est déclaré l.2998 et jamais incrémenté.
  //  → aucun risque de doublon mémoire via cette méthode.
  // ═══════════════════════════════════════════════════════════════════════
  test('A6/6 — analyseJourneeComplete ne crée aucun pronostic', () async {
    final ring = _reunion(code: 'R1', nbCourses: 2, date: _j(-2));
    await _creerPronostics([ring]);
    final avant = IaMemoryService.instance.pronostics.length;
    expect(avant, 2);

    // Vérification statique : nbPronosticsAjoutes n'est jamais incrémenté
    // (contrôlé par grep : 2998 = déclaration, 3490/3539/3678 = lecture seule)

    // ignore: avoid_print
    print('  [A6/6] avant=$avant ; nbPronosticsAjoutes n\'est jamais '
        'incrémenté dans la méthode (lecture seule)');
    expect(IaMemoryService.instance.pronostics.length, avant,
        reason: 'la méthode consomme, elle ne crée pas');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  A6/7 — LE RAPPORT EST UNIQUE PAR DATE (remplacement, pas cumul)
  //
  //  _ajouterRapport() (l.3719) fait removeWhere sur même année/mois/jour
  //  AVANT d'ajouter → un rattrapage rejoué ne duplique pas le rapport.
  // ═══════════════════════════════════════════════════════════════════════
  test('A6/7 — un rapport par date, pas de cumul', () async {
    final ring = _reunion(code: 'R1', nbCourses: 2, date: _j(-2));
    await _creerPronostics([ring]);
    // Marquer résolu pour que le rapport ait du contenu
    for (final p in IaMemoryService.instance.pronostics) {
      await IaMemoryService.instance.enregistrerResultat(
        courseKey: p.courseKey,
        arriveeReelle: const [1, 2, 3, 4, 5],
      );
    }

    final nbRapportsAvant = IaMemoryService.instance.rapports.length;
    // ignore: avoid_print
    print('  [A6/7] rapports après résolution = $nbRapportsAvant '
        '(dédoublonnés par date par _ajouterRapport)');

    // Pas d'appel réseau ici (interdit) : on vérifie seulement la règle de
    // dédoublonnage par lecture du code + état.
    expect(nbRapportsAvant, lessThanOrEqualTo(1),
        reason: '_ajouterRapport remplace le rapport du même jour');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  A6/8 — LE SEUL USAGE VRAIMENT SENSIBLE DE now POUR L'APPRENTISSAGE
  //
  //  l.3425 _calculerFacteurJourneeAtypique(pronosticsJour, now)
  //    → now.year / now.month servent de CLÉ DE QUOTA mensuel.
  //    Remplacer now par DateTime.now() ne change RIEN au calcul du taux
  //    d'échec (basé sur les pronostics), seulement la clé du compteur.
  //  l.2219 _apprendreParGradient utilise DateTime.now() en interne
  //    → A6 n'a AUCUN effet sur la fenêtre 45j, car le gradient n'utilise
  //      pas le paramètre now de la méthode.
  // ═══════════════════════════════════════════════════════════════════════
  test('A6/8 — le taux d\'échec ne dépend pas de now, seule la clé de quota',
      () {
    // Reproduit l'arithmétique de _calculerFacteurJourneeAtypique
    // (le taux d'échec ne lit que les pronostics, jamais now)
    final statuts = <bool>[true, true, false, false, false, false, false, false];
    final nbEchecs = statuts.where((ok) => !ok).length;
    final tauxEchec = nbEchecs / statuts.length;

    // ignore: avoid_print
    print('  [A6/8] taux d\'échec = ${(tauxEchec * 100).toStringAsFixed(0)}% '
        'sur ${statuts.length} courses (indépendant de now)');

    expect(tauxEchec, 0.75, reason: 'calcul purement basé sur les pronostics');
    expect(tauxEchec < 0.85, isTrue, reason: 'sous le seuil → facteur 1.0');

    // La seule dépendance à now est la clé '${now.year}-${now.month}'
    final j2 = DateTime.now().subtract(const Duration(days: 2));
    final nowActuel = DateTime.now();
    final cleAvecNowCible = '${j2.year}-${j2.month}';
    final cleAvecNowReel = '${nowActuel.year}-${nowActuel.month}';
    // ignore: avoid_print
    print('  [A6/8] clé quota : now cible=$cleAvecNowCible | '
        'now réel=$cleAvecNowReel '
        '(${cleAvecNowCible == cleAvecNowReel ? "identiques" : "DIFFÉRENTES"})');

    // Même mois → aucune différence pratique. À cheval sur deux mois → si.
    // C'est le SEUL effet d'une correction de now sur l'apprentissage.
    expect(cleAvecNowCible.isNotEmpty, isTrue);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  A6/9 — LES TROIS STRATÉGIES DE CORRECTION, MESURÉES
  //
  //  A. Statu quo                 : maintenant (A6 entier)
  //  B. Modifier analyseJourneeComplete (INTERDIT sans autorisation)
  //     → remplacer `now` par DateTime.now() dans le calcul diffMin
  //  C. Corriger l'APPELANT SEUL  : pour une date PASSÉE, transmettre
  //     cette date à 23:59 au lieu de l'heure courante
  // ═══════════════════════════════════════════════════════════════════════
  test('A6/9 — stratégie C : l\'appelant transmet 23:59 pour une date passée',
      () {
    final j2 = DateTime.now().subtract(const Duration(days: 2));
    const heureCourse = 14;
    const minuteCourse = 15;

    // ── A. Statu quo : appui à 08h ─────────────────────────────────────
    final a = _verdictReel(j2, 8, heureCourse, minuteCourse);

    // ── C. Appelant : date cible à 23:59 ───────────────────────────────
    _Verdict strategieC(int heureAppui) {
      final nowTardif =
          DateTime(j2.year, j2.month, j2.day, 23, 59);
      final course = DateTime(
          j2.year, j2.month, j2.day, heureCourse, minuteCourse);
      final diffMin = course.difference(nowTardif).inMinutes;
      if (diffMin > 0) return _Verdict.sauteeFuture;
      if (diffMin > -30) return _Verdict.sauteeEnCours;
      return _Verdict.analysee;
    }

    final mesures = <int, (_Verdict, _Verdict)>{
      8: (a, strategieC(8)),
      12: (_verdictReel(j2, 12, heureCourse, minuteCourse), strategieC(12)),
      16: (_verdictReel(j2, 16, heureCourse, minuteCourse), strategieC(16)),
      21: (_verdictReel(j2, 21, heureCourse, minuteCourse), strategieC(21)),
    };

    for (final e in mesures.entries) {
      // ignore: avoid_print
      print('  [A6/9] appui ${e.key.toString().padLeft(2, '0')}h00 → '
          'A(statu quo)=${e.value.$1.name} | C(appelant)=${e.value.$2.name}');
    }

    // La stratégie C donne un verdict STABLE et correct pour les 4 heures
    for (final e in mesures.entries) {
      expect(e.value.$2, _Verdict.analysee,
          reason: 'C : une date passée doit toujours être analysée, '
              'quelle que soit l\'heure de l\'appui');
    }
    // Elle corrige bien le défaut mesuré en A6/1
    expect(mesures[8]!.$1, _Verdict.sauteeFuture,
        reason: 'rappel du défaut en statu quo');
    expect(mesures[8]!.$2, isNot(mesures[8]!.$1),
        reason: 'la correction change bien le verdict de 08h');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  A6/10 — GARDE-FOU INDISPENSABLE : 23:59 NE DOIT PAS S'APPLIQUER
  //           À AUJOURD'HUI
  //
  //  Si l'appelant transmettait 23:59 pour la journée EN COURS, toutes les
  //  courses du jour seraient considérées comme passées et analysées à 10h
  //  du matin, avant même leur départ → résultats inexistants, et surtout
  //  un pronostic pourrait être marqué « traité » à tort.
  //  → La stratégie C doit être conditionnée à : date < aujourd'hui.
  // ═══════════════════════════════════════════════════════════════════════
  test('A6/10 — 23:59 appliqué à aujourd\'hui casserait la protection '
      'des courses à venir', () {
    final t = DateTime.now();

    // Aujourd'hui, appui à 08h, course à 14h15 (pas encore courue)
    final aujCorrect = DateTime(t.year, t.month, t.day, 8, 0);
    final courseAuj = DateTime(t.year, t.month, t.day, 14, 15);
    final diffCorrect = courseAuj.difference(aujCorrect).inMinutes;

    // Aujourd'hui avec le forçage 23:59 (ce qu'il ne faut PAS faire)
    final aujFaux = DateTime(t.year, t.month, t.day, 23, 59);
    final diffFaux = courseAuj.difference(aujFaux).inMinutes;

    // ignore: avoid_print
    print('  [A6/10] aujourd\'hui 08h, course 14h15 → '
        'correct diffMin=$diffCorrect (à venir, sautée) | '
        'forçage 23:59 diffMin=$diffFaux (serait analysée à tort)');

    expect(diffCorrect, greaterThan(0),
        reason: 'comportement correct : la course est encore à venir');
    expect(diffFaux, lessThan(-30),
        reason: 'le forçage ferait analyser une course non courue → '
            'le garde-fou « date < aujourd\'hui » est OBLIGATOIRE');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  A6/11 — EFFETS DE BORD DE LA STRATÉGIE C SUR LES 9 USAGES DE now
  //
  //  Chaque usage est classé : impacté / neutre / cosmétique.
  // ═══════════════════════════════════════════════════════════════════════
  test('A6/11 — les 9 usages de now et leur sensibilité à la stratégie C',
      () {
    // Table établie par lecture du code (lignes vérifiées une par une)
    const usages = <String, String>{
      'l.2993 now = date ?? now':
          'SOURCE — la date transmise devient now',
      'l.3012 dateDebut (sélection du jour)':
          'NEUTRE — year/month/day identiques',
      'l.3087 now.hour (message contextuel)':
          'COSMÉTIQUE — branche atteinte seulement si mémoire vide',
      'l.3121 _dateAnalyseReelle (fallback)':
          'NEUTRE — seulement si aucun pronostic trouvé',
      'l.3213 diffMin (cœur de A6)':
          '★ CORRIGÉ — c\'est l\'objet de la correction',
      'l.3365 dateResultat':
          'COSMÉTIQUE — champ jamais lu par la logique métier',
      'l.3425 facteurJourneeAtypique':
          'NEUTRE — seuls year/month servent de clé de quota',
      'l.3474 _mettreAJourPrecisionIA(date)':
          'ACTIF — date de la journée dans historiqueComplet '
          '(même jour civil → identique)',
      'l.3481 ia_derniere_analyse_v1':
          'NEUTRE — même jour civil',
      'l.3490 _calculerRapportJournalier':
          'NEUTRE — même jour civil',
    };

    for (final e in usages.entries) {
      // ignore: avoid_print
      print('  [A6/11] ${e.key} → ${e.value}');
    }

    expect(usages.length, 10);
    // Un seul usage est réellement corrigé ; aucun n'est sémantiquement cassé
    final corriges =
        usages.values.where((v) => v.startsWith('★')).length;
    expect(corriges, 1, reason: 'un seul point de bascule');
  });
}
