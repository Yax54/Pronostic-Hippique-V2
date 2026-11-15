// ═══════════════════════════════════════════════════════════════════════════
//  A4-2 — RÉSULTAT OFFICIEL D'UN PRONOSTIC DÉJÀ ÉVINCÉ → ARCHIVE SEULE
//
//  Objet : vérifier que `enregistrerResultat()` consigne le résultat officiel
//  d'une course qui n'est plus dans la mémoire active (évincée par le plafond
//  600), SANS jamais la réinjecter dans `_pronostics` et SANS déclencher
//  d'apprentissage.
//
//  PÉRIMÈTRE INTERDIT (non modifié par A4-2, non testé ici comme modifiable) :
//   • purge M1 (`_purgerVieuxPronostics`) et son seuil de 90 jours ;
//   • plafond `_maxPronostics` (600) ;
//   • `IaArchiveService` (lu, jamais modifié) ;
//   • écrans et filtres du calendrier ;
//   • calculs métier de réussite, règles Premium et Gros Paris ;
//   • gradient descent, `_poids`, `_seuils`, TOP 3, ELO, `analyseJourneeComplete()`.
//
//  A4-1, A4-3, A4-4 et A4-5 ne sont PAS traités ici.
//
//  ⚠️ PORTÉE EXPLICITE : ces tests constatent le comportement OBSERVÉ du
//     service. Ils ne préjugent pas du bon fonctionnement global de l'app.
//
//  ⚠️ NEUTRALISATION DE M1 : le flag `ia_precision_migrated_v3` est posé à
//     `true` dans le store simulé. Sans lui, la migration one-shot déclenche
//     un `_save()` pendant `_load()`, donc la purge M1, qui détruirait la
//     cible avant l'éviction. A4-1 n'étant pas corrigée (décision explicite),
//     ce positionnement est nécessaire pour isoler A4-2.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/ia_archive_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

// ───────────────────────────────────────────────────────────────────────────
//  CONSTANTES ET OUTILS
// ───────────────────────────────────────────────────────────────────────────

const String kPronosticsKey = 'ia_pronostics_v2';
const String kFlagMigration  = 'ia_precision_migrated_v3';

/// Date du jour, sans composante horaire : les tests restent valables
/// quel que soit le jour d'exécution.
DateTime get aujourdhui {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

String ddMmYyyy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

/// Jour de la cible : volontairement ISOLÉ (aucun autre pronostic ce mois-là)
/// pour que la visibilité calendrier soit parfaitement discriminante.
final DateTime jourCible = DateTime(2024, 6, 15);
const String cleCible = 'R1C600_15062024';

/// Arrivée où les 5 premiers chevaux IA sont exactement placés → GAGNANT.
const List<int> arriveeGagnante = <int>[3, 7, 1, 5, 2];

/// Arrivée où AUCUN cheval IA ({3,7,1,5,2}) n'est placé → PERDANT.
/// 9, 8, 6, 4, 10 : aucun de ces numéros ne figure parmi les scores IA.
const List<int> arriveePerdante = <int>[9, 8, 6, 4, 10];

/// Pronostic synthétique au format de persistance.
/// `scoresCriteres` vide pour rester léger : `completudeDe` compte alors
/// 4 champs, ce qui suffit à mesurer la progression.
Map<String, dynamic> prono({
  required DateTime jour,
  required int numCourse,
  bool resolu = true,
  String typePari = 'Quinté+',
}) =>
    IaPronostic(
      courseKey: 'R1C${numCourse}_${ddMmYyyy(jour)}',
      nomCourse: 'Course audit $numCourse',
      hippodrome: 'Vincennes',
      discipline: 'Trot Attelé',
      datePronostic: jour,
      dateResultat: resolu ? jour : null,
      scoresIA: const <String, double>{
        '3': 92.0, '7': 84.0, '1': 76.0, '5': 68.0, '2': 60.0,
      },
      scoresCriteres: const <String, ScoresCriteres>{},
      resultatsReels: resolu,
      arriveeReelle: resolu ? arriveeGagnante : null,
      typePariConseille: typePari,
      confiancePredite: 71.0,
      varianceScores: 12.5,
      favoriIaNom: 'Cheval 3',
      coteFavoriPmu: 3.4,
      cotesPmuParNumero: const <String, double>{'3': 3.4, '7': 6.1},
    ).toJson();

ZtCourse courseNouvelle() => ZtCourse(
      numCourse: 900,
      anchor: 'c900',
      nom: 'Prix de poussée',
      dateStr: ddMmYyyy(aujourdhui),
      heure: '15:30',
      distance: '2700',
      prix: '50000',
      type: 'Attelé',
      piste: 'Grande piste',
      categorie: 'Course D',
      isQuinte: false,
      pronosticZt: const <int>[],
      partants: <ZtPartant>[],
    );

/// Redémarrage complet à partir d'un store simulé.
Future<void> amorcer(List<Map<String, dynamic>> liste) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'flutter.$kPronosticsKey': liste.map((m) => json.encode(m)).toList(),
    'flutter.$kFlagMigration': true,
  });
  SharedPreferences.resetStatic();
  await IaArchiveService.instance.reinitialiserMemoirePourTest();
  await IaMemoryService.instance.recharger();
  await IaArchiveService.instance.charger();
}

/// 600 pronostics : 593 quotidiens résolus + 6 du 26→31 mars 2025
/// + la CIBLE en dernière position (la plus ancienne → victime du plafond).
List<Map<String, dynamic>> liste600({bool cibleResolue = false}) {
  final liste = <Map<String, dynamic>>[];
  for (int i = 0; i < 593; i++) {
    liste.add(prono(
        jour: aujourdhui.subtract(Duration(days: i)), numCourse: i));
  }
  for (int d = 31; d >= 26; d--) {
    liste.add(prono(jour: DateTime(2025, 3, d), numCourse: 700 + d));
  }
  liste.add(prono(jour: jourCible, numCourse: 600, resolu: cibleResolue));
  return liste;
}

/// Pousse un 601ᵉ pronostic : déclenche `_evincerAuDelaDeLaLimite()`.
Future<void> evincerParPlafond() async {
  await IaMemoryService.instance.enregistrerPronostic(
    courseKey: 'R1C900_${ddMmYyyy(aujourdhui)}',
    course: courseNouvelle(),
    partantsClasses: const <ZtPartant>[],
    typePariConseille: 'Quinté+',
  );
}

/// Relit tout le store et relance un cycle complet (redémarrage dur).
Future<void> redemarrer() async {
  final prefs = await SharedPreferences.getInstance();
  final snapshot = <String, Object>{};
  for (final k in prefs.getKeys()) {
    final v = prefs.get(k);
    if (v is String) snapshot['flutter.$k'] = v;
    if (v is List<String>) snapshot['flutter.$k'] = v;
    if (v is bool) snapshot['flutter.$k'] = v;
  }
  SharedPreferences.setMockInitialValues(snapshot);
  SharedPreferences.resetStatic();
  await IaArchiveService.instance.reinitialiserMemoirePourTest();
  await IaMemoryService.instance.recharger();
  await IaArchiveService.instance.charger();
}

/// Le jour du calendrier contient-il bien LA course ciblée ?
bool jourContientCible(int annee, int mois, int jour) {
  final dd = IaMemoryService.instance.donneesCalendrierJour(annee, mois)[jour];
  return dd != null && dd.pronostics.any((p) => p.courseKey == cleCible);
}

int occurrencesCalendrier(int annee, int mois, int jour) {
  final dd = IaMemoryService.instance.donneesCalendrierJour(annee, mois)[jour];
  if (dd == null) return 0;
  return dd.pronostics.where((p) => p.courseKey == cleCible).length;
}

final List<String> champsPersistes = <String>[
  'courseKey', 'nomCourse', 'hippodrome', 'discipline', 'datePronostic',
  'scoresIA', 'scoresCriteres', 'varianceScores', 'arriveeReelle',
  'dateResultat', 'resultatsReels', 'rangFavoriIaDansArrivee',
  'nbTop3DansArriveeReelle', 'nbTop5DansArriveeReelle', 'scorePerformance',
  'diagnosticApprentissage', 'confiancePredite', 'typePariConseille',
  'tauxReussiteAuMoment', 'precisionIA', 'favoriIaNom', 'coteFavoriPmu',
  'cotesPmuParNumero',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ══════════════════════════════════════════════════════════════════════════
  //  A4-2-1 — Pronostic NON RÉSOLU évincé au-delà du plafond 600
  // ══════════════════════════════════════════════════════════════════════════
  test('A4-2-1 — non résolu évincé par le plafond : hors mémoire, dans l\'archive',
      () async {
    await amorcer(liste600());

    // Contrôle du montage : la cible est bien en mémoire, non résolue.
    final avant = IaMemoryService.instance.getPronostic(cleCible);
    expect(avant, isNotNull, reason: 'cible présente avant éviction');
    expect(avant!.resultatsReels, isFalse, reason: 'cible NON résolue');
    expect(IaMemoryService.instance.pronostics, hasLength(600));
    expect(IaArchiveService.instance.toutesLesVersionsArchivees(), isEmpty,
        reason: 'archive vide au départ');

    await evincerParPlafond();

    // Évincée de la mémoire active…
    expect(IaMemoryService.instance.getPronostic(cleCible), isNull,
        reason: 'la cible a quitté la mémoire active');
    expect(IaMemoryService.instance.pronostics, hasLength(600),
        reason: 'le plafond 600 est maintenu');

    // …mais présente dans l'archive, encore NON résolue.
    final archivee = IaArchiveService.instance.versionRetenue(cleCible);
    expect(archivee, isNotNull, reason: 'archivée AVANT le retrait');
    expect(archivee!.resultatsReels, isFalse,
        reason: 'la copie archivée est celle d\'avant le résultat');
    expect(IaArchiveService.rangDe(archivee), 0);

    if (kDebugMode) {
      debugPrint('A4-2-1 mémoire=${IaMemoryService.instance.pronostics.length} '
          '| archive résolu=${archivee.resultatsReels} '
          '| mois=${IaArchiveService.instance.moisConnus}');
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  A4-2-2 — Arrivée officielle reçue APRÈS éviction
  // ══════════════════════════════════════════════════════════════════════════
  test('A4-2-2 — arrivée officielle après éviction : consignée, pas ignorée',
      () async {
    await amorcer(liste600());
    await evincerParPlafond();

    final avant = IaArchiveService.instance.versionRetenue(cleCible)!;
    expect(avant.resultatsReels, isFalse);
    expect(avant.arriveeReelle, isNull);

    await IaMemoryService.instance.enregistrerResultat(
      courseKey: cleCible,
      arriveeReelle: arriveeGagnante,
    );

    final apres = IaArchiveService.instance.versionRetenue(cleCible)!;
    expect(apres.resultatsReels, isTrue,
        reason: 'le résultat ne doit plus être perdu');
    expect(apres.arriveeReelle, arriveeGagnante);
    expect(apres.dateResultat, isNotNull);
    expect(IaArchiveService.rangDe(apres), 2, reason: 'résolu complet');

    // Aucune réinjection.
    expect(IaMemoryService.instance.getPronostic(cleCible), isNull,
        reason: 'jamais réinjectée en mémoire active');

    if (kDebugMode) {
      debugPrint('A4-2-2 archive résolu=${apres.resultatsReels} '
          'rang=${IaArchiveService.rangDe(apres)} '
          'arrivee=${apres.arriveeReelle}');
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  A4-2-3 — Version résolue enregistrée dans l'archive
  // ══════════════════════════════════════════════════════════════════════════
  test('A4-2-3 — version résolue écrite dans le bon shard mensuel', () async {
    await amorcer(liste600());
    await evincerParPlafond();
    await IaMemoryService.instance
        .enregistrerResultat(courseKey: cleCible, arriveeReelle: arriveeGagnante);

    final a = IaArchiveService.instance;
    final shard = a.versionsDuMois('2024-06');
    expect(a.moisConnus, contains('2024-06'),
        reason: 'le shard est dérivé de datePronostic');
    expect(shard.map((p) => p.courseKey), contains(cleCible));
    expect(
        shard.where((p) => p.courseKey == cleCible).any((p) => p.resultatsReels),
        isTrue,
        reason: 'une version RÉSOLUE figure dans le shard');

    if (kDebugMode) {
      debugPrint('A4-2-3 shard 2024-06 : ${shard.length} version(s) '
          '| résolues=${shard.where((p) => p.resultatsReels).length}');
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  A4-2-4 — Résultat retrouvé après redémarrage
  // ══════════════════════════════════════════════════════════════════════════
  test('A4-2-4 — le résultat survit à un redémarrage complet', () async {
    await amorcer(liste600());
    await evincerParPlafond();
    await IaMemoryService.instance
        .enregistrerResultat(courseKey: cleCible, arriveeReelle: arriveeGagnante);

    await redemarrer();

    final v = IaArchiveService.instance.versionRetenue(cleCible);
    expect(v, isNotNull, reason: 'présente après redémarrage');
    expect(v!.resultatsReels, isTrue, reason: 'toujours résolue');
    expect(v.arriveeReelle, arriveeGagnante, reason: 'arrivée conservée');
    expect(IaArchiveService.rangDe(v), 2);

    if (kDebugMode) {
      debugPrint('A4-2-4 après redémarrage : résolu=${v.resultatsReels} '
          'arrivee=${v.arriveeReelle} | mois=${IaArchiveService.instance.moisConnus}');
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  A4-2-5 — Affichage de la réussite au BON jour
  // ══════════════════════════════════════════════════════════════════════════
  test('A4-2-5 — la réussite apparaît au jour exact de la course', () async {
    await amorcer(liste600());
    await evincerParPlafond();
    await IaMemoryService.instance
        .enregistrerResultat(courseKey: cleCible, arriveeReelle: arriveeGagnante);

    final cal = IaMemoryService.instance.donneesCalendrierJour(2024, 6);
    expect(cal.keys.toList()..sort(), <int>[15],
        reason: 'seul le 15 juin 2024 doit apparaître dans ce mois');

    final dd = cal[15]!;
    expect(dd.nbCourses, 1);
    expect(dd.nbBons, 1, reason: 'Quinté+ avec 5/5 → course gagnante comptée');
    expect(dd.pronostics.any((p) => p.courseKey == cleCible), isTrue);

    // Le mois voisin ne doit rien contenir.
    expect(IaMemoryService.instance.donneesCalendrierJour(2024, 5), isEmpty);
    expect(IaMemoryService.instance.donneesCalendrierJour(2024, 7), isEmpty);

    if (kDebugMode) {
      debugPrint('A4-2-5 jour 15 : nbCourses=${dd.nbCourses} '
          'nbBons=${dd.nbBons} nbOrdre=${dd.nbOrdre} palier=${dd.palier}');
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  A4-2-6 — Second appel identique : aucune nouvelle version
  // ══════════════════════════════════════════════════════════════════════════
  test('A4-2-6 — idempotence : un second appel identique n\'ajoute rien',
      () async {
    await amorcer(liste600());
    await evincerParPlafond();
    await IaMemoryService.instance
        .enregistrerResultat(courseKey: cleCible, arriveeReelle: arriveeGagnante);

    final a = IaArchiveService.instance;
    final nb1 = a.nbVersions(cleCible);
    final tot1 = a.toutesLesVersions(cleCible).length;
    final emp1 = IaArchiveService.empreinteDe(a.versionRetenue(cleCible)!);

    await IaMemoryService.instance
        .enregistrerResultat(courseKey: cleCible, arriveeReelle: arriveeGagnante);
    await IaMemoryService.instance
        .enregistrerResultat(courseKey: cleCible, arriveeReelle: arriveeGagnante);

    final nb3 = a.nbVersions(cleCible);
    final tot3 = a.toutesLesVersions(cleCible).length;
    final emp3 = IaArchiveService.empreinteDe(a.versionRetenue(cleCible)!);

    expect(nb3, nb1, reason: 'aucune version ajoutée');
    expect(tot3, tot1, reason: 'aucune entrée ajoutée');
    expect(emp3, emp1, reason: 'la version retenue est inchangée');

    if (kDebugMode) {
      debugPrint('A4-2-6 nbVersions $nb1 → $nb3 | versions $tot1 → $tot3');
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  A4-2-7 — Aucun doublon visible
  // ══════════════════════════════════════════════════════════════════════════
  test('A4-2-7 — aucun doublon : ni dans le calendrier, ni doublon d\'identité',
      () async {
    await amorcer(liste600());
    await evincerParPlafond();
    await IaMemoryService.instance
        .enregistrerResultat(courseKey: cleCible, arriveeReelle: arriveeGagnante);
    await IaMemoryService.instance
        .enregistrerResultat(courseKey: cleCible, arriveeReelle: arriveeGagnante);

    // Le calendrier ne présente JAMAIS deux fois la même course.
    expect(occurrencesCalendrier(2024, 6, 15), 1,
        reason: 'une seule occurrence de la course dans le jour');
    expect(IaMemoryService.instance.donneesCalendrierJour(2024, 6)[15]!.nbCourses,
        1,
        reason: 'la course ne compte qu\'une fois');

    // L'archive est VERSIONNÉE (une version = un contenu distinct) : la
    // coexistence de la version non résolue et de la version résolue est le
    // modèle attendu, pas un doublon d'identité. Une seule version retenue.
    final versions = IaArchiveService.instance.toutesLesVersions(cleCible);
    expect(versions.where((p) => p.resultatsReels).length, 1,
        reason: 'une seule version résolue');
    expect(IaArchiveService.instance.versionRetenue(cleCible)!.resultatsReels,
        isTrue, reason: 'la retenue est la résolue');

    if (kDebugMode) {
      debugPrint('A4-2-7 occurrences calendrier=1 | versions archivées='
          '${versions.length} (dont résolues='
          '${versions.where((p) => p.resultatsReels).length})');
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  A4-2-8 — Aucun remplacement d'une version déjà résolue
  // ══════════════════════════════════════════════════════════════════════════
  test('A4-2-8 — une version déjà résolue n\'est jamais rétrogradée', () async {
    // Cible DÉJÀ résolue avant l'éviction.
    await amorcer(liste600(cibleResolue: true));
    await evincerParPlafond();

    final avant = IaArchiveService.instance.versionRetenue(cleCible)!;
    expect(avant.resultatsReels, isTrue);
    final empAvant = IaArchiveService.empreinteDe(avant);
    final nbAvant = IaArchiveService.instance.nbVersions(cleCible);

    // Résultat DIFFÉRENT et moins bon : ne doit rien changer.
    await IaMemoryService.instance.enregistrerResultat(
      courseKey: cleCible,
      arriveeReelle: arriveePerdante,
    );

    final apres = IaArchiveService.instance.versionRetenue(cleCible)!;
    expect(IaArchiveService.empreinteDe(apres), empAvant,
        reason: 'la version retenue est rigoureusement inchangée');
    expect(apres.arriveeReelle, arriveeGagnante,
        reason: 'l\'arrivée d\'origine est préservée');
    expect(IaArchiveService.instance.nbVersions(cleCible), nbAvant,
        reason: 'aucune version ajoutée');

    if (kDebugMode) {
      debugPrint('A4-2-8 empreinte inchangée, arrivée retenue='
          '${apres.arriveeReelle}, nbVersions=$nbAvant');
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  A4-2-9 — Pronostic absent de la mémoire ET de l'archive : aucune écriture
  // ══════════════════════════════════════════════════════════════════════════
  test('A4-2-9 — course inconnue partout : aucune invention, aucune écriture',
      () async {
    await amorcer(liste600());
    await evincerParPlafond();

    final a = IaArchiveService.instance;
    final nbAvant = a.toutesLesVersionsArchivees().length;
    final moisAvant = List<String>.from(a.moisConnus);
    const inconnue = 'R9C9_01012024';

    await IaMemoryService.instance.enregistrerResultat(
      courseKey: inconnue,
      arriveeReelle: arriveeGagnante,
    );

    expect(a.versionRetenue(inconnue), isNull,
        reason: 'aucune version inventée');
    expect(a.toutesLesVersions(inconnue), isEmpty,
        reason: 'aucune entrée inventée');
    expect(a.toutesLesVersionsArchivees(), hasLength(nbAvant),
        reason: 'l\'archive n\'a pas grossi');
    expect(a.moisConnus, moisAvant, reason: 'aucun shard créé');
    expect(IaMemoryService.instance.getPronostic(inconnue), isNull,
        reason: 'aucune réinjection');

    if (kDebugMode) {
      debugPrint('A4-2-9 versions archive $nbAvant → '
          '${a.toutesLesVersionsArchivees().length} (inchangé)');
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  A4-2-10 — Aucune réinjection dans les 600 pronostics actifs
  // ══════════════════════════════════════════════════════════════════════════
  test('A4-2-10 — la mémoire active reste à 600 et la cible n\'y revient pas',
      () async {
    await amorcer(liste600());
    await evincerParPlafond();

    final memAvant = IaMemoryService.instance.pronostics.length;
    final clesAvant =
        IaMemoryService.instance.pronostics.map((p) => p.courseKey).toList();

    await IaMemoryService.instance
        .enregistrerResultat(courseKey: cleCible, arriveeReelle: arriveeGagnante);
    await redemarrer();

    final memApres = IaMemoryService.instance.pronostics;
    expect(memApres.length, memAvant,
        reason: 'le nombre de pronostics actifs est inchangé');
    expect(memApres.map((p) => p.courseKey).toList(), clesAvant,
        reason: 'la composition de la mémoire est inchangée');
    expect(IaMemoryService.instance.getPronostic(cleCible), isNull,
        reason: 'la cible ne revient JAMAIS dans les 600 actifs');

    if (kDebugMode) {
      debugPrint('A4-2-10 mémoire $memAvant → ${memApres.length} '
          '| cible réinjectée ? ${memApres.any((p) => p.courseKey == cleCible)}');
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  A4-2-11 — Parité des champs et des calculs avec `enregistrerResultat`
  // ══════════════════════════════════════════════════════════════════════════
  test('A4-2-11 — parité stricte des 23 champs avec le chemin normal',
      () async {
    // ── Référence : pronostic EN MÉMOIRE, résolu par le chemin normal ──
    await amorcer(<Map<String, dynamic>>[
      prono(jour: jourCible, numCourse: 600, resolu: false),
    ]);
    await IaMemoryService.instance
        .enregistrerResultat(courseKey: cleCible, arriveeReelle: arriveeGagnante);
    final ref = IaMemoryService.instance.getPronostic(cleCible);
    expect(ref, isNotNull, reason: 'référence résolue par le chemin normal');
    final refJ = ref!.toJson();

    // ── Candidat : pronostic ÉVINCÉ, complété par A4-2 ──
    await amorcer(liste600());
    await evincerParPlafond();
    await IaMemoryService.instance
        .enregistrerResultat(courseKey: cleCible, arriveeReelle: arriveeGagnante);
    final cand = IaArchiveService.instance.versionRetenue(cleCible)!;
    final candJ = cand.toJson();

    final divergents = <String>[];
    for (final k in champsPersistes) {
      if (json.encode(refJ[k]) == json.encode(candJ[k])) continue;
      // `dateResultat` est un horodatage : il diffère par nature.
      if (k == 'dateResultat') continue;
      divergents.add('$k : ref=${json.encode(refJ[k])} '
          '| archive=${json.encode(candJ[k])}');
    }
    for (final d in divergents) {
      debugPrint('A4-2-11 ⚠️ DIVERGENCE $d');
    }

    expect(divergents, isEmpty,
        reason: 'les 22 autres champs doivent être identiques');

    if (kDebugMode) {
      debugPrint('A4-2-11 ${champsPersistes.length - 1}/'
          '${champsPersistes.length - 1} champs identiques '
          '(hors dateResultat, horodatage)');
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  A4-2-12 — Aucun changement des poids, seuils et mécanismes d'apprentissage
  // ══════════════════════════════════════════════════════════════════════════
  test('A4-2-12 — poids et seuils strictement inchangés, aucun apprentissage',
      () async {
    await amorcer(liste600());
    await evincerParPlafond();

    // Captures AVANT (lecture seule).
    final poidsAvant = json.encode(IaMemoryService.instance.poids.toJson());
    final seuilsAvant =
        json.encode(IaMemoryService.instance.seuilsConfiance.toJson());
    final memAvant = IaMemoryService.instance.pronostics.length;

    await IaMemoryService.instance
        .enregistrerResultat(courseKey: cleCible, arriveeReelle: arriveeGagnante);

    final poidsApres = json.encode(IaMemoryService.instance.poids.toJson());
    final seuilsApres =
        json.encode(IaMemoryService.instance.seuilsConfiance.toJson());

    expect(poidsApres, poidsAvant, reason: 'poids INCHANGÉS');
    expect(seuilsApres, seuilsAvant, reason: 'seuils INCHANGÉS');
    expect(IaMemoryService.instance.pronostics.length, memAvant,
        reason: 'aucune course ajoutée → aucun apprentissage possible');

    if (kDebugMode) {
      debugPrint('A4-2-12 poids identiques=${poidsApres == poidsAvant} '
          'seuils identiques=${seuilsApres == seuilsAvant}');
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  A4-2-13 — Pronostic PERDANT : traitement inchangé
  // ══════════════════════════════════════════════════════════════════════════
  test('A4-2-13 — pronostic PERDANT : parité stricte avec le chemin normal',
      () async {
    // ── Référence : perdant résolu par le chemin normal ──
    await amorcer(<Map<String, dynamic>>[
      prono(jour: jourCible, numCourse: 600, resolu: false),
    ]);
    await IaMemoryService.instance
        .enregistrerResultat(courseKey: cleCible, arriveeReelle: arriveePerdante);
    final ddRef = IaMemoryService.instance.donneesCalendrierJour(2024, 6)[15];
    expect(ddRef, isNotNull);
    expect(ddRef!.nbBons, 0, reason: 'un perdant n\'est pas compté réussi');

    // ── Candidat : perdant évincé puis complété par A4-2 ──
    await amorcer(liste600());
    await evincerParPlafond();
    await IaMemoryService.instance
        .enregistrerResultat(courseKey: cleCible, arriveeReelle: arriveePerdante);

    final v = IaArchiveService.instance.versionRetenue(cleCible)!;
    expect(v.resultatsReels, isTrue, reason: 'le résultat est bien consigné');
    expect(v.arriveeReelle, arriveePerdante);
    expect(v.rangFavoriIaDansArrivee, isNull,
        reason: 'le favori IA est absent de l\'arrivée');
    expect(v.nbTop3DansArriveeReelle, 0);
    expect(v.nbTop5DansArriveeReelle, 0);

    final ddCor = IaMemoryService.instance.donneesCalendrierJour(2024, 6)[15];
    expect(ddCor, isNotNull, reason: 'le jour existe (le pronostic est résolu)');
    expect(ddCor!.nbCourses, ddRef.nbCourses);
    expect(ddCor.nbBons, ddRef.nbBons, reason: 'même décompte de réussites');
    expect(ddCor.nbOrdre, ddRef.nbOrdre);
    expect(ddCor.palier, ddRef.palier, reason: 'même palier de couleur');

    if (kDebugMode) {
      debugPrint('A4-2-13 PERDANT — ref: nbBons=${ddRef.nbBons} '
          'palier=${ddRef.palier} | correctif: nbBons=${ddCor.nbBons} '
          'palier=${ddCor.palier} → PARITÉ '
          '${ddRef.nbBons == ddCor.nbBons && ddRef.palier == ddCor.palier}');
    }
  });
}
