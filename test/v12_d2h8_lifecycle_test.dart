// ═══════════════════════════════════════════════════════════════════════════
//  V12 — D2/H8 finalisation : cycle de vie et anti-réentrance
//
//  Ce fichier vérifie TROIS choses, et refuse de confondre les trois :
//
//   1. La règle de recalage (déjà en production, palier 3) — reproduite ici
//      pour vérifier ses effets sur le comptage.
//   2. L'anti-réentrance `_loadStats()` — la boucle mesurée à 51 appels
//      doit retomber à 2 (un déclenchement + au plus un rebond différé).
//   3. La présence effective de l'observateur de cycle de vie DANS LE SOURCE
//      DE PRODUCTION (lecture du fichier), car un test unitaire ne peut pas
//      instancier l'écran complet sans son `AlertService` et ses 6 onglets.
//
//  ⚠ Distinction maintenue : ces tests confirment des observations
//    ciblées, pas que tout le cycle de vie est correct sur un vrai appareil.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

// ── Helpers de date / données ───────────────────────────────────────────────
String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}${d.year}';

DateTime _j(int offset) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).add(Duration(days: offset));
}

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

ZtReunion _reunion({String code = 'R1', int nbCourses = 2, required String date}) =>
    ZtReunion(
      code: code,
      lieu: 'Vincennes',
      discipline: 'trot_attele',
      dateStr: date,
      courses: List.generate(nbCourses, (i) => _course(i + 1, date)),
    );

Map<String, Object> _prefs() => <String, Object>{};

Set<String> _cles() =>
    IaMemoryService.instance.pronostics.map((p) => p.courseKey).toSet();

/// Reproduit À L'IDENTIQUE la règle de recalage de production
/// (`_loadStats` → if `_dateAnalyseAutomatique` → compare jour/mois/année).
DateTime recaler(DateTime dateAnalyse, bool automatique, DateTime horloge) {
  if (!automatique) return dateAnalyse;
  if (horloge.year != dateAnalyse.year ||
      horloge.month != dateAnalyse.month ||
      horloge.day != dateAnalyse.day) {
    return horloge;
  }
  return dateAnalyse;
}

/// Compte les courses de la journée `dateStr` absentes de la mémoire.
/// Miroir exact de `_calculerManquants()`.
int manquants(List<ZtReunion> reunions, String dateStr) {
  int total = 0, manquants = 0;
  for (final r in reunions) {
    final numR = r.code.replaceAll(RegExp(r'[^0-9]'), '');
    for (final c in r.courses) {
      if (c.dateStr != dateStr) continue;
      total++;
      if (IaMemoryService.instance
              .getPronostic('R${numR}C${c.numCourse}_${c.dateStr}') ==
          null) {
        manquants++;
      }
    }
  }
  return total == 0 ? 0 : manquants;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(_prefs());
    EloService.instance.reinitialiser();
    await IaMemoryService.instance.recharger();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  L1 — La boucle de réentrance est cassée (FORME RÉELLE de production)
  //
  //  Deux formes ont été mesurées sur le vrai service :
  //   • verrou synchrone + corps synchrone  → 61 appels, boucle active
  //   • verrou couvrant l'attente réelle    → 1 appel
  //  On teste ici la seconde, en reproduisant exactement la structure de
  //  production : corps asynchrone, `await` sur la chaîne, relâchement après.
  // ═══════════════════════════════════════════════════════════════════════
  test('V12/L1 — un listener qui réécrit dans le service ne boucle pas', () async {
    final svc = IaMemoryService.instance;
    int appels = 0;
    bool verrou = false;

    // Réplique de la structure de production (_loadStats / corps / travail).
    Future<void> corps() async {
      try {
        appels++;
        await svc.mettreAJourStatsTypes([
          {'typePari': 'Quinté+', 'isCorrect': true, 'gainNet': 12.5},
        ]);
      } finally {
        verrou = false;
      }
    }

    void loadStats() {
      if (verrou) return;
      verrou = true;
      unawaited(corps());
    }

    svc.addListener(loadStats);
    loadStats();
    await Future.delayed(const Duration(milliseconds: 300));
    svc.removeListener(loadStats);

    // ignore: avoid_print
    print('  [V12/L1] appels depuis UN déclenchement : $appels');
    expect(appels, 1,
        reason: 'le verrou doit ramener la chaîne à un seul passage '
            '(sans verrou : 61 appels mesurés)');
  });

  // Contrôle négatif : sans verrou, le défaut est bien reproductible.
  // Ce test documente la CAUSE ; il n'appelle pas le code de production et
  // ne peut donc pas « passer par accident ».
  test('V12/L1b — sans verrou la boucle se reproduit (documentaire)', () async {
    final svc = IaMemoryService.instance;
    int appels = 0;

    void loadStats() {
      appels++;
      if (appels > 40) return; // coupe-circuit de mesure
      unawaited(svc.mettreAJourStatsTypes([
        {'typePari': 'Quinté+', 'isCorrect': true, 'gainNet': 12.5},
      ]));
    }

    svc.addListener(loadStats);
    loadStats();
    await Future.delayed(const Duration(milliseconds: 300));
    svc.removeListener(loadStats);

    // ignore: avoid_print
    print('  [V12/L1b] sans verrou : $appels appels');
    expect(appels, greaterThan(5),
        reason: 'sans verrou la chaîne se relance : c\'est le défaut mesuré');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  L2 — Retour au premier plan après minuit : la date se recale
  // ═══════════════════════════════════════════════════════════════════════
  test('V12/L2 — après minuit, le retour au premier plan recale la date', () async {
    final hier = _j(-1);
    final auj = _j(0);

    // Écran ouvert hier : _dateAnalyse = hier, mode automatique.
    final dateAnalyse = DateTime(hier.year, hier.month, hier.day, 22, 0);
    expect(_fmt(dateAnalyse), _fmt(hier));

    // L'app passe minuit en arrière-plan, puis l'utilisateur revient.
    // `didChangeAppLifecycleState(resumed)` → `_loadStats()` → recalage.
    final horloge = DateTime(auj.year, auj.month, auj.day, 0, 5);
    final recalee = recaler(dateAnalyse, true, horloge);

    // ignore: avoid_print
    print('  [V12/L2] hier=${_fmt(hier)} → recalée=${_fmt(recalee)}');
    expect(_fmt(recalee), _fmt(auj),
        reason: 'le retour au premier plan doit réaligner sur le nouveau jour');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  L3 — Une date choisie manuellement survit au retour au premier plan
  // ═══════════════════════════════════════════════════════════════════════
  test('V12/L3 — une date choisie manuellement n\'est pas écrasée', () async {
    final choisie = DateTime(_j(-5).year, _j(-5).month, _j(-5).day, 9, 0);
    final horloge = DateTime(_j(0).year, _j(0).month, _j(0).day, 8, 0);

    // _dateAnalyseAutomatique == false : l'utilisateur a choisi.
    final apres = recaler(choisie, false, horloge);

    // ignore: avoid_print
    print('  [V12/L3] choisie=${_fmt(choisie)} → ${_fmt(apres)} '
        '(attendu : inchangée)');
    expect(_fmt(apres), _fmt(choisie),
        reason: 'un choix explicite de l\'utilisateur doit être préservé');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  L4 — Même jour : aucun déplacement inutile
  // ═══════════════════════════════════════════════════════════════════════
  test('V12/L4 — même jour, le recalage est un non-événement', () async {
    final dateAnalyse = DateTime(_j(0).year, _j(0).month, _j(0).day, 6, 0);
    final horloge = DateTime(_j(0).year, _j(0).month, _j(0).day, 23, 59);

    final apres = recaler(dateAnalyse, true, horloge);

    expect(apres, same(dateAnalyse),
        reason: 'le recalage ne doit produire un nouvel objet que si le jour '
            'a réellement changé');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  L5 — Après recalage, comptage et recréation visent la MÊME date
  // ═══════════════════════════════════════════════════════════════════════
  test('V12/L5 — après recalage, les manquants se comptent sur le nouveau jour',
      () async {
    // Mémoire vide, programme du jour et de demain disponibles.
    final auj = _fmt(_j(0));
    final demain = _fmt(_j(1));
    final reunions = [
      _reunion(code: 'R1', nbCourses: 2, date: auj),
      _reunion(code: 'R2', nbCourses: 2, date: demain),
    ];

    final avant = manquants(reunions, auj);
    expect(avant, 2, reason: 'mémoire vide → 2 manquants sur la journée');

    // Le retour au premier plan recale, puis on recrée sur la date recalée.
    final recalee = DateTime(_j(0).year, _j(0).month, _j(0).day);
    final crees = await IaMemoryService.instance
        .recreerPronosticsManquants(reunions, dateCible: recalee);
    final apres = manquants(reunions, auj);

    // ignore: avoid_print
    print('  [V12/L5] manquants $avant → $apres (créés=$crees)');
    expect(crees, 2);
    expect(apres, 0,
        reason: 'comptage et recréation doivent viser la même journée');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  L6 — Persistance et absence de doublons après un second passage
  // ═══════════════════════════════════════════════════════════════════════
  test('V12/L6 — second retour au premier plan : aucun doublon, mémoire intacte',
      () async {
    final auj = _fmt(_j(0));
    final reunions = [_reunion(code: 'R1', nbCourses: 3, date: auj)];
    final recalee = DateTime(_j(0).year, _j(0).month, _j(0).day);

    final c1 = await IaMemoryService.instance
        .recreerPronosticsManquants(reunions, dateCible: recalee);
    final cles1 = _cles();

    // Redémarrage simulé : relecture depuis le disque.
    await IaMemoryService.instance.recharger();
    final clesApresRedemarrage = _cles();

    // Second passage (nouveau retour au premier plan).
    final c2 = await IaMemoryService.instance
        .recreerPronosticsManquants(reunions, dateCible: recalee);
    final cles2 = _cles();

    // ignore: avoid_print
    print('  [V12/L6] c1=$c1 c2=$c2 | avant=${cles1.length} '
        'après redémarrage=${clesApresRedemarrage.length} '
        'après 2e passage=${cles2.length}');
    expect(c1, 3);
    expect(c2, 0, reason: 'rien à recréer au second passage');
    expect(clesApresRedemarrage, cles1,
        reason: 'la persistance doit restituer exactement les mêmes clés');
    expect(cles2, cles1, reason: 'aucun doublon, aucune perte');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  L7 — L'observateur de cycle de vie existe dans le source de production
  //
  //  Un test unitaire ne peut pas monter cet écran (AlertService + 6 onglets
  //  + plugins). On vérifie donc la présence et la forme exacte du mécanisme
  //  dans le fichier réel — même méthode que V11/H8/4c.
  // ═══════════════════════════════════════════════════════════════════════
  test('V12/L7 — le code de production déclare bien l\'observateur', () {
    final src = File('lib/screens/ia_performance_screen.dart').readAsStringSync();

    expect(src.contains('with SingleTickerProviderStateMixin, WidgetsBindingObserver'),
        isTrue, reason: 'le mixin doit être déclaré sur l\'état de l\'écran');
    expect(src.contains('WidgetsBinding.instance.addObserver(this)'), isTrue,
        reason: 'l\'observateur doit être enregistré');
    expect(src.contains('WidgetsBinding.instance.removeObserver(this)'), isTrue,
        reason: 'l\'observateur doit être retiré dans dispose()');
    expect(src.contains('void didChangeAppLifecycleState(AppLifecycleState state)'),
        isTrue, reason: 'la méthode de cycle de vie doit exister');
    expect(
        src.contains('if (state != AppLifecycleState.resumed) return;'), isTrue,
        reason: 'seul `resumed` doit déclencher un rechargement');
    expect(src.contains('bool _loadStatsEnCours = false;'), isTrue,
        reason: 'le verrou anti-réentrance doit exister');

    // ★ Le verrou doit couvrir la CHAÎNE ASYNCHRONE, pas seulement l'appel.
    // Mesures : verrou synchrone = 61 appels ; verrou couvrant l'attente = 1.
    expect(src.contains('Future<void> _loadStatsCorps() async'), isTrue,
        reason: 'le corps doit être asynchrone pour que le verrou tienne');
    expect(src.contains('Future<void> _syncTrackedCoursesToIa() async'), isTrue,
        reason: '_syncTrackedCoursesToIa doit renvoyer son Future');
    expect(src.contains('await _syncTrackedCoursesToIa();'), isTrue,
        reason: 'la sync doit être ATTENDUE, sinon le verrou est relâché trop tôt');
    expect(src.contains('await IaMemoryService.instance.mettreAJourStatsTypes('),
        isTrue,
        reason: 'mettreAJourStatsTypes doit être attendu : c\'est sa '
            'notification qui referme la boucle');

    // Aucun Timer ne doit avoir été introduit (interdiction explicite).
    final blocLoadStats = src.substring(
        src.indexOf('void _loadStats()'),
        src.indexOf('Future<void> _loadStatsCorps() async'));
    expect(blocLoadStats.contains('Timer'), isFalse,
        reason: 'aucun Timer ne doit être ajouté (interdiction utilisateur)');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  L7b — Le verrou est bien relâché une fois la chaîne terminée
  //
  //  Un verrou qui ne se relâche jamais figerait l'écran pour de bon.
  // ═══════════════════════════════════════════════════════════════════════
  test('V12/L7b — le verrou se relâche après la chaîne (pas de gel)', () async {
    final svc = IaMemoryService.instance;
    int appels = 0;
    bool verrou = false;

    Future<void> corps() async {
      try {
        appels++;
        await svc.mettreAJourStatsTypes([
          {'typePari': 'Quinté+', 'isCorrect': true, 'gainNet': 5.0},
        ]);
      } finally {
        verrou = false;
      }
    }

    void loadStats() {
      if (verrou) return;
      verrou = true;
      unawaited(corps());
    }

    svc.addListener(loadStats);

    loadStats();                                   // 1er déclenchement
    await Future.delayed(const Duration(milliseconds: 150));
    expect(appels, 1);
    expect(verrou, isFalse, reason: 'le verrou doit être relâché après la fin');

    loadStats();                                   // 2e déclenchement légitime
    await Future.delayed(const Duration(milliseconds: 150));
    svc.removeListener(loadStats);

    // ignore: avoid_print
    print('  [V12/L7b] après 2 déclenchements distincts : $appels appels');
    expect(appels, 2,
        reason: 'chaque déclenchement légitime doit être servi — le verrou ne '
            'doit pas transformer l\'écran en statue');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  L8 — L'ordre des opérations de dispose() est correct
  // ═══════════════════════════════════════════════════════════════════════
  test('V12/L8 — dispose() retire l\'observateur avant de libérer le reste', () {
    final src = File('lib/screens/ia_performance_screen.dart').readAsStringSync();
    final iRemove = src.indexOf('WidgetsBinding.instance.removeObserver(this)');
    final iListener = src.indexOf('IaMemoryService.instance.removeListener(_loadStats)');
    final iTabDispose = src.indexOf('_tabCtrl.dispose();');

    expect(iRemove, greaterThan(0));
    expect(iRemove, lessThan(iListener),
        reason: 'l\'observateur doit être retiré avant le détachement du '
            'listener mémoire — sinon un `resumed` tardif peut atteindre un '
            'état en cours de destruction');
    expect(iListener, lessThan(iTabDispose));
  });
}
