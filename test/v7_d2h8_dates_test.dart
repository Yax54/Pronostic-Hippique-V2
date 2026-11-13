// ═══════════════════════════════════════════════════════════════════════════
//  V7 — D2/H8 : gestion des dates
//
//  ⚠️  FICHIER DE TEST uniquement. AUCUNE modification de lib/.
//
//  Ces tests ne corrigent rien : ils MESURENT le comportement réel pour
//  établir le diagnostic avant toute décision.
//
//  Trois questions :
//    A. La date cible existe-t-elle réellement dans l'écran IA ?
//    B. Le comptage et la recréation peuvent-ils diverger ?
//    C. Le risque de « pronostic historique fabriqué » existe-t-il déjà ?
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/ia_pronostic_engine.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Outils
// ───────────────────────────────────────────────────────────────────────────

String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

String _aujourdhui() => _fmt(DateTime.now());
String _hier() => _fmt(DateTime.now().subtract(const Duration(days: 1)));
String _demain() => _fmt(DateTime.now().add(const Duration(days: 1)));

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

/// Reproduit `_calculerManquants()` (ia_performance_screen.dart:250)
/// à l'identique : renvoie (total, manquants) pour une date donnée.
(int, int) _compterManquants(List<ZtReunion> reunions, DateTime date) {
  final dateStr = _fmt(date);
  int total = 0;
  int manquants = 0;
  for (final reunion in reunions) {
    final m = RegExp(r'R(\d+)').firstMatch(reunion.code);
    final numR = m != null ? int.tryParse(m.group(1) ?? '1') ?? 1 : 1;
    for (final course in reunion.courses) {
      if (course.partants.isEmpty) continue;
      final dep = course.heureDateTime;
      if (_fmt(dep) != dateStr) continue;
      total++;
      final key = 'R${numR}C${course.numCourse}_${_fmt(dep)}';
      if (IaMemoryService.instance.getPronostic(key) == null) manquants++;
    }
  }
  return (total, manquants);
}

// ───────────────────────────────────────────────────────────────────────────

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(_prefs());
    await EloService.instance.reinitialiser();
    await IaMemoryService.instance.recharger();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  H8/A — La « date cible » de l'écran n'existe pas en pratique
  //
  //  `_dateAnalyse` est initialisé à `DateTime.now()` et n'est modifiable
  //  que par `_choisirDateAnalyse()`, qui n'a AUCUN appelant dans lib/.
  //  (Vérifiable par : grep -rn "_choisirDateAnalyse" lib/ → 1 seul résultat,
  //   la définition elle-même. La méthode porte // ignore: unused_element.)
  //
  //  Donc : aucune date sélectionnable, aucune divergence possible via l'UI.
  //  Ce test fige cette observation au niveau service.
  // ═══════════════════════════════════════════════════════════════════════
  test('H8/A — le comptage utilise une date figée, la recréation une date '
      'fraîche : ils peuvent diverger au passage de minuit', () async {
    // Une réunion "hier" et une "aujourd'hui"
    final rHier = _reunion(code: 'R1', nbCourses: 2, date: _hier());
    final rAuj = _reunion(code: 'R2', nbCourses: 2, date: _aujourdhui());
    final reunions = [rHier, rAuj];

    // ── État 1 : l'écran a été construit HIER (sa date est figée) ────────
    final dateEcran = DateTime.now().subtract(const Duration(days: 1));
    final (totalEcran, manquantsEcran) =
        _compterManquants(reunions, dateEcran);

    // ── La recréation, elle, utilise DateTime.now() en interne ───────────
    final nbCrees =
        await IaMemoryService.instance.recreerPronosticsManquants(reunions);

    // ignore: avoid_print
    print('  [H8/A] écran figé sur ${_fmt(dateEcran)} → '
        'total=$totalEcran, manquants=$manquantsEcran');
    // ignore: avoid_print
    print('  [H8/A] recreerPronosticsManquants a créé : $nbCrees '
        '(sur ${_aujourdhui()})');

    // La recréation ignore totalement la date de l'écran
    expect(nbCrees, 2,
        reason: 'elle crée uniquement les courses d\'aujourd\'hui');
    expect(manquantsEcran, 2,
        reason: 'l\'écran, figé sur hier, compte 2 manquants sur cette date');

    // ✗ Divergence : l'écran annonce 2 manquants « hier »,
    //   la recréation en crée 2 « aujourd'hui » → l'écran reste à 2.
    final (_, manquantsApres) = _compterManquants(reunions, dateEcran);
    // ignore: avoid_print
    print('  [H8/A] après recréation, l\'écran (figé sur hier) affiche '
        'encore $manquantsApres manquant(s)');

    expect(manquantsApres, 2,
        reason: 'DÉFAUT : la recréation ne réduit pas le compteur affiché');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  H8/B — L'enregistrement AUTO des courses de demain (à CONSERVER)
  //
  //  Décision utilisateur n°1 : « oui, si le programme de demain est
  //  disponible, il ne faut pas supprimer cette possibilité ».
  //  On vérifie que le batch auto accepte bien les 3 dates.
  // ═══════════════════════════════════════════════════════════════════════
  test('H8/B — l\'enregistrement automatique accepte aujourd\'hui, demain '
      'et hier (comportement à préserver)', () async {
    final dates = {'hier': _hier(), 'aujourdhui': _aujourdhui(),
                   'demain': _demain()};
    final reunions = <ZtReunion>[
      _reunion(code: 'R1', nbCourses: 1, date: dates['hier']!),
      _reunion(code: 'R2', nbCourses: 1, date: dates['aujourdhui']!),
      _reunion(code: 'R3', nbCourses: 1, date: dates['demain']!),
    ];

    // Reproduit le batch auto (aucun filtre de date)
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

    final cles = IaMemoryService.instance.pronostics
        .map((p) => p.courseKey)
        .toList();

    // ignore: avoid_print
    print('  [H8/B] batch auto a enregistré ${cles.length} courses : $cles');

    for (final entry in dates.entries) {
      final attendu = 'R${reunions.indexWhere((r) => r.dateStr == entry.value) + 1}'
          'C1_${entry.value}';
      expect(cles.contains(attendu), isTrue,
          reason: '${entry.key} doit être enregistré par le chemin auto');
    }
    expect(cles.length, 3);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  H8/C — Le risque de « pronostic historique fabriqué » N'EXISTE PAS
  //
  //  C'est le point rassurant du diagnostic : `recreerPronosticsManquants()`
  //  ne traite QUE aujourd'hui. Une date passée ne produit rien.
  //  Le garde-fou demandé est donc DÉJÀ en place, par construction.
  //
  //  ⚠️ Conséquence : ajouter naïvement un paramètre `dateCible` SANS garde
  //  introduirait le risque que l'utilisateur veut éviter.
  // ═══════════════════════════════════════════════════════════════════════
  test('H8/C — aucune création rétroactive possible aujourd\'hui', () async {
    // Programme d'il y a 10 jours
    final ancien = _fmt(DateTime.now().subtract(const Duration(days: 10)));
    final r = _reunion(code: 'R1', nbCourses: 3, date: ancien);

    final nb = await IaMemoryService.instance.recreerPronosticsManquants([r]);

    // ignore: avoid_print
    print('  [H8/C] réunion du $ancien → nbCrees=$nb '
        '(0 = aucune fabrication rétroactive)');

    expect(nb, 0,
        reason: 'une date passée ne doit rien créer : le filtre « aujourd\'hui » '
            'joue déjà le rôle de garde-fou');
    expect(IaMemoryService.instance.pronostics, isEmpty);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  H8/D — Les pronostics déjà enregistrés survivent, quelle que soit
  //  leur date (décision utilisateur n°4)
  // ═══════════════════════════════════════════════════════════════════════
  test('H8/D — une recréation ne supprime jamais les pronostics d\'autres '
      'dates', () async {
    // On enregistre hier + demain via le batch (chemin qui accepte tout)
    final rHier = _reunion(code: 'R1', nbCourses: 1, date: _hier());
    final rDemain = _reunion(code: 'R2', nbCourses: 1, date: _demain());

    final batch = <Map<String, dynamic>>[];
    for (final r in [rHier, rDemain]) {
      final m = RegExp(r'R(\d+)').firstMatch(r.code);
      final numR = m != null ? int.tryParse(m.group(1) ?? '1') ?? 1 : 1;
      final c = r.courses.first;
      final (pc, sc) = IaPronosticEngine.analyserCourseAvecCriteres(c);
      batch.add({
        'courseKey': 'R${numR}C${c.numCourse}_${_fmt(c.heureDateTime)}',
        'course': c, 'partantsClasses': pc, 'scoresCriteres': sc,
        'confiance': c.confianceIA, 'typePariConseille': 'Quinté+',
      });
    }
    await IaMemoryService.instance.enregistrerPronosticsBatch(batch);
    final avant = IaMemoryService.instance.pronostics
        .map((p) => p.courseKey)
        .toSet();
    expect(avant.length, 2);

    // Recréation pour aujourd'hui
    await IaMemoryService.instance.recreerPronosticsManquants(
        [_reunion(code: 'R3', nbCourses: 2, date: _aujourdhui())]);

    final apres = IaMemoryService.instance.pronostics
        .map((p) => p.courseKey)
        .toSet();

    // ignore: avoid_print
    print('  [H8/D] avant=$avant');
    // ignore: avoid_print
    print('  [H8/D] après=$apres');

    expect(avant.difference(apres), isEmpty,
        reason: 'aucun pronostic préexistant ne doit disparaître');
    expect(apres.length, 4, reason: '2 d\'avant + 2 créés');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  H8/E — La courseKey encode déjà la date
  //
  //  Point technique central pour la correction : `recreerPronosticsManquants`
  //  dérive la date de `course.heureDateTime`, elle-même issue de
  //  `course.dateStr`. Un appelant peut donc déjà cibler une date, à
  //  condition de lui passer des réunions portant cette `dateStr`.
  //
  //  → Transmettre une date cible ne nécessite AUCUN changement d'API :
  //    il suffit de filtrer les réunions en amont. C'est la correction
  //    minimale.
  // ═══════════════════════════════════════════════════════════════════════
  test('H8/E — la date est déjà portée par courseKey et dateStr', () async {
    final d = _aujourdhui();
    await IaMemoryService.instance
        .recreerPronosticsManquants([_reunion(nbCourses: 2, date: d)]);

    for (final p in IaMemoryService.instance.pronostics) {
      // ignore: avoid_print
      print('  [H8/E] ${p.courseKey} — datePronostic=${p.datePronostic}');
      expect(p.courseKey.endsWith(d), isTrue,
          reason: 'la date est encodée dans la clé');
      expect(_fmt(p.datePronostic), d,
          reason: 'datePronostic reflète la course, pas la date du calcul');
    }
  });
}
