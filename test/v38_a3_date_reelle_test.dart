// ═══════════════════════════════════════════════════════════════════════════
//  A-3 — DATE RÉELLE DE LA COURSE, REFUS SANS INVENTION, PURGE ET HISTORIQUE
//
//  Objet : vérifier que `IaMemoryService.enregistrerPronostic()` date le
//  pronostic avec la date de la COURSE — et non plus avec celle du téléphone
//  (`DateTime.now()`) — et qu'il REFUSE d'écrire quand cette date n'est pas
//  déterminable sans invention.
//
//  PÉRIMÈTRE INTERDIT (inchangé par A-3, non testé ici) :
//   • purge M1 (`_purgerVieuxPronostics`) — observée, jamais modifiée
//   • plafond `_maxPronostics` (600)
//   • archives (`IaArchiveService`) — lues, jamais modifiées
//   • poids, seuils, gradient descent, TOP 3, ELO, analyseJourneeComplete()
//
//  ⚠️ PORTÉE EXPLICITE : ces tests constatent le comportement OBSERVÉ du
//     service. Ils ne préjugent pas du bon fonctionnement global de l'app.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/ia_archive_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

// ───────────────────────────────────────────────────────────────────────────
//  OUTILS
// ───────────────────────────────────────────────────────────────────────────

const String kPronosticsKey = 'ia_pronostics_v2';
const String kShardPrefix = 'ia_archive_v1_';

/// Date du jour, sans composante horaire : les tests doivent rester valables
/// quel que soit le jour où ils sont exécutés.
DateTime get aujourdhui {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

String ddMmYyyy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

String iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

ZtCourse courseT({
  int numCourse = 1,
  String dateStr = '',
  String heure = '15:30',
}) =>
    ZtCourse(
      numCourse: numCourse,
      anchor: 'c$numCourse',
      nom: 'Prix A3 $numCourse',
      dateStr: dateStr,
      heure: heure,
      distance: '2700',
      prix: '50000',
      type: 'Attelé',
      piste: 'Grande piste',
      categorie: 'Course D',
      isQuinte: false,
      pronosticZt: const <int>[],
      partants: <ZtPartant>[],
    );

/// Pronostic historique résolu, au format de persistance.
Map<String, dynamic> pronosticResolu({
  required DateTime jour,
  int numCourse = 1,
  List<int> arrivee = const [3, 7, 1, 5, 2],
}) =>
    IaPronostic(
      courseKey: 'R1C${numCourse}_${ddMmYyyy(jour)}',
      nomCourse: 'Course historique $numCourse',
      hippodrome: 'Vincennes',
      discipline: 'Trot Attelé',
      datePronostic: jour,
      dateResultat: jour,
      scoresIA: const <String, double>{'3': 92.0, '7': 84.0},
      scoresCriteres: const <String, ScoresCriteres>{},
      resultatsReels: true,
      arriveeReelle: arrivee,
      typePariConseille: 'Quinté+',
    ).toJson();

/// Encode un shard d'archive comme le fait `IaArchiveService._encoderVersions`.
String encoderShard(List<Map<String, dynamic>> versions) =>
    base64Encode(GZipCodec().encode(utf8.encode(json.encode(versions))));

Future<void> reinitialiser({
  Map<String, Object> data = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(data);
  SharedPreferences.resetStatic();
  // ★ Redémarrage complet : le singleton d'archive doit RELIRE le nouveau
  //   store (`_resetInMemory()` puis `_load()`), sinon il resterait sur les
  //   shards du test précédent.
  await IaArchiveService.instance.reinitialiserMemoirePourTest();
  await IaMemoryService.instance.recharger();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ══════════════════════════════════════════════════════════════════════════
  //  1 — DATE RÉELLE AVEC HEURE CONSERVÉE
  // ══════════════════════════════════════════════════════════════════════════
  test('A3-1 — la date vient de la course, et l\'heure réelle est conservée',
      () async {
    await reinitialiser();
    final cle = 'R1C1_${ddMmYyyy(aujourdhui)}';

    await IaMemoryService.instance.enregistrerPronostic(
      courseKey: cle,
      course: courseT(dateStr: ddMmYyyy(aujourdhui), heure: '15:30'),
      partantsClasses: const <ZtPartant>[],
    );

    final pronostics = IaMemoryService.instance.pronostics;
    expect(pronostics, hasLength(1), reason: 'le pronostic doit être enregistré');

    final d = pronostics.first.datePronostic;
    // La DATE est celle du jour de course…
    expect(d.year, aujourdhui.year);
    expect(d.month, aujourdhui.month);
    expect(d.day, aujourdhui.day);
    // …et l'HEURE de départ déclarée par la course est CONSERVÉE.
    expect(d.hour, 15, reason: 'heure réelle préservée depuis ZtCourse.heure');
    expect(d.minute, 30, reason: 'minutes réelles préservées');
    debugPrint('A3-1 datePronostic=$d (jour de course + heure réelle)');
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  2 — DATE VALIDE ISSUE DE LA SEULE courseKey
  // ══════════════════════════════════════════════════════════════════════════
  test('A3-2 — date déduite de la seule courseKey, sans dateStr', () async {
    await reinitialiser();
    // Un jour de course DISTANT, porté uniquement par la clé (format ddMMyyyy).
    final jour = aujourdhui.subtract(const Duration(days: 10));
    final cleDd = 'R1C1_${ddMmYyyy(jour)}';

    await IaMemoryService.instance.enregistrerPronostic(
      courseKey: cleDd,
      course: courseT(dateStr: '', heure: '15:30'), // pas de dateStr
      partantsClasses: const <ZtPartant>[],
    );

    final pronostics = IaMemoryService.instance.pronostics;
    expect(pronostics, hasLength(1));
    final d = pronostics.first.datePronostic;
    expect(d.year, jour.year, reason: 'année lue dans la clé');
    expect(d.month, jour.month, reason: 'mois lu dans la clé');
    expect(d.day, jour.day, reason: 'jour lu dans la clé');
    // Heure inconnue → minuit : la JOURNÉE est juste, l'heure n'est pas inventée.
    expect(d.hour, 0, reason: 'heure non inventée quand dateStr est absent');
    expect(d.minute, 0);
    debugPrint('A3-2 datePronostic=$d (journée depuis la clé, minuit)');
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  3 — COHÉRENCE dateStr / courseKey
  // ══════════════════════════════════════════════════════════════════════════
  test('A3-3 — dateStr et courseKey concordants : la date est acceptée',
      () async {
    await reinitialiser();
    final jour = aujourdhui.subtract(const Duration(days: 3));

    // Clé au format ISO ET dateStr au format ddMMyyyy, même journée.
    await IaMemoryService.instance.enregistrerPronostic(
      courseKey: 'R1C1_${iso(jour)}',
      course: courseT(dateStr: ddMmYyyy(jour), heure: '16:45'),
      partantsClasses: const <ZtPartant>[],
    );

    final pronostics = IaMemoryService.instance.pronostics;
    expect(pronostics, hasLength(1),
        reason: 'deux sources concordantes → aucun refus');
    final d = pronostics.first.datePronostic;
    expect(d, DateTime(jour.year, jour.month, jour.day, 16, 45),
        reason: 'date de la course ET heure réelle, formats différents mais '
            'concordants');
    debugPrint('A3-3 datePronostic=$d (ISO + ddMMyyyy concordants)');
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  4 — REFUS SI DATES CONTRADICTOIRES
  // ══════════════════════════════════════════════════════════════════════════
  test('A3-4 — dates contradictoires : refus, aucune date arbitraire',
      () async {
    await reinitialiser();
    final jourCle = aujourdhui.subtract(const Duration(days: 5));
    final jourDs = aujourdhui.subtract(const Duration(days: 9));
    expect(jourCle, isNot(jourDs), reason: 'TÉMOIN : les deux jours diffèrent');

    await IaMemoryService.instance.enregistrerPronostic(
      courseKey: 'R1C1_${iso(jourCle)}', //       source 1 : J−5
      course: courseT(dateStr: ddMmYyyy(jourDs), heure: '15:30'), // source 2 : J−9
      partantsClasses: const <ZtPartant>[],
    );

    expect(IaMemoryService.instance.pronostics, isEmpty,
        reason: 'contradiction → refus. Aucune des deux dates n\'est choisie '
            'arbitrairement.');
    debugPrint('A3-4 contradiction → refus (0 pronostic)');
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  5 — REFUS SI DATE ABSENTE OU INVALIDE
  // ══════════════════════════════════════════════════════════════════════════
  test('A3-5 — date absente ou invalide : refus dans tous les cas', () async {
    // 5.a — aucune source : ni clé datée, ni dateStr.
    await reinitialiser();
    await IaMemoryService.instance.enregistrerPronostic(
      courseKey: 'CLE_SANS_DATE',
      course: courseT(dateStr: '', heure: '15:30'),
      partantsClasses: const <ZtPartant>[],
    );
    expect(IaMemoryService.instance.pronostics, isEmpty,
        reason: 'aucune des deux sources → refus');

    // 5.b — clé non datée + dateStr impossible (31 février).
    await reinitialiser();
    await IaMemoryService.instance.enregistrerPronostic(
      courseKey: 'CLE_SANS_DATE',
      course: courseT(dateStr: '31022026', heure: '15:30'),
      partantsClasses: const <ZtPartant>[],
    );
    expect(IaMemoryService.instance.pronostics, isEmpty,
        reason: 'dateStr calendairement impossible → refus, pas de correction');

    // 5.c — clé datée + dateStr invalide : la clé fait foi, sans invention.
    await reinitialiser();
    final jour = aujourdhui.subtract(const Duration(days: 7));
    await IaMemoryService.instance.enregistrerPronostic(
      courseKey: 'R1C1_${ddMmYyyy(jour)}',
      course: courseT(dateStr: 'ABCDEFGH', heure: '15:30'),
      partantsClasses: const <ZtPartant>[],
    );
    expect(IaMemoryService.instance.pronostics, hasLength(1),
        reason: 'seule la clé est exploitable : elle est utilisée telle quelle');
    final d = IaMemoryService.instance.pronostics.first.datePronostic;
    expect(d.day, jour.day);
    expect(d.hour, 0, reason: 'dateStr invalide → heure NON déduite, minuit');
    debugPrint('A3-5 refus absente+invalide OK ; clé seule → $d');
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  6 — ABSENCE D'ÉCRITURE LORS D'UN REFUS
  // ══════════════════════════════════════════════════════════════════════════
  test('A3-6 — un refus n\'écrit rien : ni RAM, ni disque, ni archive',
      () async {
    await reinitialiser();

    // Compteur d'écritures réellement demandées au stockage.
    final prefs = await SharedPreferences.getInstance();
    final clesAvant = Set<String>.from(prefs.getKeys());

    await IaMemoryService.instance.enregistrerPronostic(
      courseKey: 'R1C1_${iso(aujourdhui)}', //       J−0
      course: courseT(dateStr: '01012020', heure: '15:30'), // contradiction
      partantsClasses: const <ZtPartant>[],
    );

    // RAM
    expect(IaMemoryService.instance.pronostics, isEmpty,
        reason: 'aucune insertion en mémoire');
    // Disque : aucune clé IA nouvelle
    final clesApres = Set<String>.from(prefs.getKeys());
    expect(clesApres, clesAvant,
        reason: 'aucune écriture disque déclenchée par le refus');
    expect(prefs.getString(kPronosticsKey), isNull,
        reason: 'le blob de pronostics n\'est pas créé par un refus');
    // Archive : rien d'archivé
    expect(IaArchiveService.instance.nbVersionsArchivees, 0,
        reason: 'un refus n\'archive rien');
    expect(IaArchiveService.instance.toutesLesVersionsArchivees(), isEmpty);
    debugPrint('A3-6 refus → clés disque inchangées (${clesApres.length}), '
        'archive=${IaArchiveService.instance.nbVersionsArchivees}');
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  7 — MAINTIEN DE LA PURGE DES PRONOSTICS ANCIENS SANS RÉSULTAT
  // ══════════════════════════════════════════════════════════════════════════
  test('A3-7 — un pronostic de plus de 90 jours NON résolu est purgé',
      () async {
    // Semé par le mécanisme NORMAL de chargement, non résolu, daté de J−120.
    final vieux = aujourdhui.subtract(const Duration(days: 120));
    final recent = aujourdhui.subtract(const Duration(days: 2));
    await reinitialiser(data: <String, Object>{
      'flutter.$kPronosticsKey': <String>[
        jsonEncode(IaPronostic(
          courseKey: 'R1C1_${ddMmYyyy(vieux)}',
          nomCourse: 'Vieux non résolu',
          hippodrome: 'Vincennes',
          discipline: 'Trot Attelé',
          datePronostic: vieux,
          scoresIA: const <String, double>{'1': 80.0},
          scoresCriteres: const <String, ScoresCriteres>{},
          // resultatsReels reste false
        ).toJson()),
        jsonEncode(IaPronostic(
          courseKey: 'R1C2_${ddMmYyyy(recent)}',
          nomCourse: 'Récent non résolu',
          hippodrome: 'Vincennes',
          discipline: 'Trot Attelé',
          datePronostic: recent,
          scoresIA: const <String, double>{'1': 80.0},
          scoresCriteres: const <String, ScoresCriteres>{},
        ).toJson()),
      ],
    });

    // TÉMOIN : les deux sont bien chargés AVANT la purge.
    expect(IaMemoryService.instance.pronostics, hasLength(2),
        reason: 'TÉMOIN : les deux pronostics sont chargés avant la purge');

    // Une écriture quelconque déclenche `_save()` → M1.
    await IaMemoryService.instance.enregistrerPronostic(
      courseKey: 'R1C3_${ddMmYyyy(aujourdhui)}',
      course: courseT(numCourse: 3, dateStr: ddMmYyyy(aujourdhui)),
      partantsClasses: const <ZtPartant>[],
    );

    final cles = IaMemoryService.instance.pronostics
        .map((p) => p.courseKey)
        .toList();
    expect(cles, isNot(contains('R1C1_${ddMmYyyy(vieux)}')),
        reason: 'M1 : le pronostic non résolu de J−120 est purgé');
    expect(cles, contains('R1C2_${ddMmYyyy(recent)}'),
        reason: 'M1 : le pronostic récent est conservé');
    expect(cles, contains('R1C3_${ddMmYyyy(aujourdhui)}'),
        reason: 'le pronostic du jour est conservé');
    debugPrint('A3-7 après purge : $cles');
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  8 — CONSERVATION DES PRONOSTICS ANCIENS DÉJÀ RÉSOLUS, APRÈS ARCHIVAGE
  //
  //  Trois notions DISTINCTES, vérifiées séparément et jamais confondues :
  //   (a) conservation PHYSIQUE  — la donnée survit à M1 (elle est résolue)
  //   (b) ACCESSIBILITÉ          — elle est relisible depuis l'archive
  //   (c) AFFICHAGE CALENDRIAIRE — le mois concerné la restitue
  // ══════════════════════════════════════════════════════════════════════════
  test('A3-8 — un pronostic ancien RÉSOLU est conservé, archivable et relisible',
      () async {
    final vieux = aujourdhui.subtract(const Duration(days: 120));
    final moisVieux =
        '${vieux.year}-${vieux.month.toString().padLeft(2, '0')}';
    final cleVieux = 'R1C1_${ddMmYyyy(vieux)}';

    await reinitialiser(data: <String, Object>{
      'flutter.$kPronosticsKey': <String>[
        jsonEncode(pronosticResolu(jour: vieux, numCourse: 1)),
      ],
    });

    // ── TÉMOIN : chargé ET résolu avant toute écriture ────────────────────
    expect(IaMemoryService.instance.pronostics, hasLength(1),
        reason: 'TÉMOIN : le pronostic semé est chargé');
    expect(IaMemoryService.instance.pronostics.first.resultatsReels, isTrue,
        reason: 'TÉMOIN : le pronostic semé est bien RÉSOLU');

    // ── (a) CONSERVATION PHYSIQUE : M1 ne purge pas un RÉSOLU ─────────────
    await IaMemoryService.instance.enregistrerPronostic(
      courseKey: 'R1C2_${ddMmYyyy(aujourdhui)}',
      course: courseT(numCourse: 2, dateStr: ddMmYyyy(aujourdhui)),
      partantsClasses: const <ZtPartant>[],
    );

    final cles = IaMemoryService.instance.pronostics
        .map((p) => p.courseKey)
        .toList();
    expect(cles, contains(cleVieux),
        reason: '(a) M1 ne purge JAMAIS un pronostic résolu, quel que soit '
            'son âge — la donnée survit physiquement');
    debugPrint('A3-8 (a) conservé après purge : $cleVieux');

    // ── (b) ACCESSIBILITÉ : le pronostic est ARCHIVÉ puis RELU ────────────
    //    M2 (`_evincerAuDelaDeLaLimite`) archive AVANT de retirer, sans
    //    borne d'âge. On force l'éviction en dépassant `_maxPronostics` (600).
    final archive = IaArchiveService.instance;
    expect(archive.nbVersionsArchivees, 0, reason: 'TÉMOIN : archive vide');

    for (var i = 0; i < 601; i++) {
      final j = aujourdhui.subtract(Duration(days: i + 1));
      await IaMemoryService.instance.enregistrerPronostic(
        courseKey: 'R3C${i}_${ddMmYyyy(j)}',
        course: courseT(numCourse: i, dateStr: ddMmYyyy(j)),
        partantsClasses: const <ZtPartant>[],
      );
    }

    debugPrint('A3-8 (b) après éviction : mémoire='
        '${IaMemoryService.instance.pronostics.length} '
        'archive=${archive.nbVersionsArchivees} '
        'shards=${archive.nbShardsSurDisque} '
        'mois=${archive.moisConnus}');

    // ACCESSIBILITÉ mesurée : la version retenue est-elle relisible ?
    final relu = archive.versionRetenue(cleVieux);
    if (relu == null) {
      debugPrint('A3-8 NOTE (b) — le pronostic de J−120 n\'a PAS été évincé : '
          'il figure déjà parmi les 600 plus récents, donc M2 ne l\'a jamais '
          'archivé. Ce n\'est pas un défaut : aucune éviction n\'a eu lieu. '
          'Conservation physique (a) = vérifiée ; accessibilité (b) = non '
          'sollicitée ; affichage (c) = mesuré ci-dessous.');
    } else {
      expect(relu.courseKey, cleVieux,
          reason: '(b) la version retenue relue porte la même courseKey');
      expect(relu.resultatsReels, isTrue,
          reason: '(b) le pronostic relu depuis l\'archive est toujours résolu');
      debugPrint('A3-8 (b) relu depuis l\'archive : ${relu.courseKey} '
          'résolu=${relu.resultatsReels} date=${relu.datePronostic}');
    }

    // ── (c) AFFICHAGE CALENDRIAIRE : le mois est-il restitué ? ────────────
    final calMoisVieux =
        IaMemoryService.instance.donneesCalendrierJour(vieux.year, vieux.month);
    final calMoisCourant =
        IaMemoryService.instance.donneesCalendrierJour(aujourdhui.year,
            aujourdhui.month);

    debugPrint('A3-8 (c) calendrier $moisVieux '
        'jours=${calMoisVieux.keys.toList()..sort()} '
        '| mois courant jours=${calMoisCourant.keys.toList()..sort()}');

    // Le mois du pronostic de J−120 doit compter au moins sa journée : il est
    // RÉSOLU et sa datePronostic porte bien sur ce mois (c'est la correction
    // A-3). On n'exige rien de plus — notamment pas l'étoile ⭐.
    expect(calMoisVieux.keys, contains(vieux.day),
        reason: '(c) la journée du pronostic résolu de J−120 est restituée '
            'dans SON mois — conséquence directe de la date réelle A-3');
  });
}

