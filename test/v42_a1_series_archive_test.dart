// ═══════════════════════════════════════════════════════════════════════════
//  V42 — A : SÉRIES PREMIUM ET ARCHIVES (A1) + CHARGEMENT AU DÉMARRAGE (R1)
//
//  OBJET
//  ─────
//  Prouver que les séries Premium retrouvent les pronostics GAGNANTS qui ne
//  sont plus dans la mémoire de travail (plafond 600) mais conservés dans
//  l'archive, SANS jamais :
//   • inventer une victoire (résultat absent, sélection absente, versions
//     multiples) ;
//   • modifier les pronostics actifs, le plafond 600 ou la purge 90 jours ;
//   • toucher aux règles de réussite (`_estPremiumExactGagnantStrict`
//     INCHANGÉE) ;
//   • absorber A2 (version active NON RÉSOLUE prioritaire sur l'archive
//     résolue : comportement actuel conservé).
//
//  ★ A2 CORRIGÉ (V48) : le repli n'est plus un simple `??` d'ABSENCE mais un
//  ARBITRAGE PAR AUTORITÉ (`_versionLaPlusAutoritaire`). Le bloc A1-E a été
//  réécrit : une fiche active NON RÉSOLUE ne masque plus une fiche archivée
//  RÉSOLUE. Les garanties de ce fichier — aucune victoire inventée, aucune
//  réinjection, règles de réussite intactes — sont strictement préservées.
//
//  R1 : l'archive doit être chargée AVANT le premier rendu, sinon le repli
//  d'A1 est sans effet (`versionRetenue` renvoie null). Ce fichier vérifie
//  le chargement, son idempotence, et l'absence de blocage en cas d'erreur.
//
//  MÉTHODE : les shards d'archive sont écrits « à la main » dans le store
//  simulé, au format réel `base64(gzip(json))`, sous la clé
//  `ia_archive_v1_YYYY-MM` (mois de `datePronostic`), plus le manifeste.
//  Le service les décode donc exactement comme au démarrage de l'application.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/services/ia_archive_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/utils/premium_streak_ui.dart';

// ───────────────────────────────────────────────────────────────────────────
//  CONSTANTES
// ───────────────────────────────────────────────────────────────────────────

const String kPronosticsKey = 'ia_pronostics_v2';
const String kFlagMigration = 'ia_precision_migrated_v3';
const String kPremiumKey = 'ia_premium_historique_v1';
const String kShardPrefix = 'ia_archive_v1_';
const String kManifestKey = 'ia_archive_v1_manifest';

/// Arrivée où le favori IA (n°3) gagne → Tiercé {3,7,1} = GAGNANT.
const List<int> kArriveeGagnante = <int>[3, 7, 1, 5, 2];

/// Arrivée où aucun cheval IA n'est placé → Tiercé {3,7,1} = PERDANT.
const List<int> kArriveePerdante = <int>[9, 8, 6, 4, 10];

const Map<String, double> kScoresIA = <String, double>{
  '3': 92.0, '7': 84.0, '1': 76.0, '5': 68.0, '2': 60.0,
};

/// Numéros de la sélection Best Bet enregistrée (Tiercé gagnant).
const List<String> kNumerosTierce = <String>['3', '7', '1'];

// ───────────────────────────────────────────────────────────────────────────
//  OUTILS
// ───────────────────────────────────────────────────────────────────────────

/// Clé de date `YYYY-MM-DD` (format lu par `calculerStreakPremium`).
String dk(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Mois `YYYY-MM` (clé physique d'un shard d'archive = mois de `datePronostic`).
String moisDe(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

/// `courseKey` au format `R1C1_DDMMYYYY` — format attendu par `dateDepuisCourseKey`.
String cleCourse(int r, int c, DateTime d) => 'R${r}C${c}_'
    '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

IaPronostic prono({
  required String courseKey,
  required DateTime date,
  bool resolu = true,
  List<int>? arrivee,
  String typePari = 'Tiercé',
}) =>
    IaPronostic(
      courseKey: courseKey,
      nomCourse: 'Course $courseKey',
      hippodrome: 'Vincennes',
      discipline: 'Trot Attelé',
      datePronostic: date,
      dateResultat: resolu ? date : null,
      scoresIA: kScoresIA,
      scoresCriteres: const <String, ScoresCriteres>{},
      resultatsReels: resolu,
      arriveeReelle: resolu ? (arrivee ?? kArriveeGagnante) : null,
      typePariConseille: typePari,
      confiancePredite: resolu ? 71.0 : 30.0,
      varianceScores: 12.5,
      favoriIaNom: 'Cheval 3',
      rangFavoriIaDansArrivee: resolu ? 1 : null,
      nbTop3DansArriveeReelle: resolu ? 3 : 0,
      nbTop5DansArriveeReelle: resolu ? 5 : 0,
      coteFavoriPmu: 3.4,
      cotesPmuParNumero: const <String, double>{'3': 3.4, '7': 6.1},
    );

/// Entrée d'historique premium (sélection Best Bet enregistrée un jour donné).
Map<String, dynamic> premiumJson({
  required String courseKey,
  required String source,
  String typePari = 'Tiercé',
  List<String> numeros = kNumerosTierce,
}) =>
    <String, dynamic>{
      'courseKey': courseKey,
      'typePari': typePari,
      'numeros': numeros,
      'sourceWidget': source,
    };

/// Encode une liste de versions au format réel du shard : base64(gzip(json)).
String encoderShard(List<IaPronostic> versions) {
  final jsonStr =
      json.encode(versions.map((p) => p.toJson()).toList(growable: false));
  return base64Encode(GZipCodec().encode(utf8.encode(jsonStr)));
}

/// Construit le contenu du store simulé.
///
/// [enMemoire]      : pronostics présents dans la mémoire de travail (600 max).
/// [enArchive]      : pronostics présents UNIQUEMENT dans l'archive.
/// [premiumParDate] : historique premium (`ia_premium_historique_v1`).
Map<String, Object> construireStore({
  List<IaPronostic> enMemoire = const <IaPronostic>[],
  List<IaPronostic> enArchive = const <IaPronostic>[],
  Map<String, List<Map<String, dynamic>>> premiumParDate =
      const <String, List<Map<String, dynamic>>>{},
}) {
  final store = <String, Object>{
    'flutter.$kPronosticsKey':
        enMemoire.map((p) => json.encode(p.toJson())).toList(growable: false),
    'flutter.$kFlagMigration': true,
    'flutter.$kPremiumKey': json.encode(<String, dynamic>{
      'entries': premiumParDate,
    }),
  };

  // Regroupement par mois de `datePronostic` : c'est la clé physique du shard.
  final parMois = <String, List<IaPronostic>>{};
  for (final p in enArchive) {
    parMois.putIfAbsent(moisDe(p.datePronostic), () => <IaPronostic>[]).add(p);
  }
  final mois = <String>[];
  for (final e in parMois.entries) {
    store['flutter.$kShardPrefix${e.key}'] = encoderShard(e.value);
    mois.add(e.key);
  }
  if (mois.isNotEmpty) {
    store['flutter.$kManifestKey'] = json.encode(<String, dynamic>{'mois': mois});
  }
  return store;
}

/// Installe le store puis recharge la mémoire de travail.
///
/// [chargerArchive] = false  → état du démarrage AVANT R1 (archive non chargée).
/// [chargerArchive] = true   → état après R1 (archive chargée avant rendu).
Future<void> amorcer(
  Map<String, Object> store, {
  required bool chargerArchive,
}) async {
  SharedPreferences.setMockInitialValues(store);
  SharedPreferences.resetStatic();
  IaArchiveService.instance.oublierChargementPourTest();
  await IaMemoryService.instance.recharger();
  if (chargerArchive) {
    await IaArchiveService.instance.charger();
  }
}

/// Série lue pour une sous-catégorie, à une date de référence donnée.
int serie(String source, DateTime dateReference) => IaMemoryService.instance
    .calculerStreakPremium(sourceWidget: source, dateReference: dateReference)
    .jours;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  /// Jour J-n (n jours avant aujourd'hui), sans dérive d'heure.
  DateTime j(int n) => today.subtract(Duration(days: n));

  // ═══════════════════════════════════════════════════════════════════════
  //  BLOC A1-A — SEUIL D'ACTIVATION (2 JOURS)
  // ═══════════════════════════════════════════════════════════════════════

  group('A1-A — seuil d\'activation', () {
    test('A1-T1 — 1 jour gagnant : série de 1, INACTIVE', () async {
      await amorcer(
        construireStore(
          enMemoire: [prono(courseKey: cleCourse(1, 1, j(1)), date: j(1))],
          premiumParDate: {
            dk(j(1)): [premiumJson(courseKey: cleCourse(1, 1, j(1)), source: 'conseilJour')],
          },
        ),
        chargerArchive: false,
      );

      final s = IaMemoryService.instance.calculerStreakPremium(
          sourceWidget: 'conseilJour', dateReference: j(1));
      expect(s.jours, 1);
      expect(s.actif, isFalse, reason: 'une série de 1 jour ne s\'affiche pas');
    });

    test('A1-T2 — 2 jours consécutifs : série de 2, ACTIVE', () async {
      await amorcer(
        construireStore(
          enMemoire: [
            prono(courseKey: cleCourse(1, 1, j(1)), date: j(1)),
            prono(courseKey: cleCourse(1, 2, j(2)), date: j(2)),
          ],
          premiumParDate: {
            dk(j(1)): [premiumJson(courseKey: cleCourse(1, 1, j(1)), source: 'conseilJour')],
            dk(j(2)): [premiumJson(courseKey: cleCourse(1, 2, j(2)), source: 'conseilJour')],
          },
        ),
        chargerArchive: false,
      );

      final s = IaMemoryService.instance.calculerStreakPremium(
          sourceWidget: 'conseilJour', dateReference: j(1));
      expect(s.jours, 2);
      expect(s.actif, isTrue, reason: '2 jours = seuil d\'affichage');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  BLOC A1-B — ARCHIVES (cœur d'A1)
  // ═══════════════════════════════════════════════════════════════════════

  group('A1-B — pronostics archivés', () {
    test('A1-T3 — 3 jours gagnants ARCHIVÉS : série de 3', () async {
      await amorcer(
        construireStore(
          enArchive: [
            prono(courseKey: cleCourse(2, 1, j(1)), date: j(1)),
            prono(courseKey: cleCourse(2, 2, j(2)), date: j(2)),
            prono(courseKey: cleCourse(2, 3, j(3)), date: j(3)),
          ],
          premiumParDate: {
            dk(j(1)): [premiumJson(courseKey: cleCourse(2, 1, j(1)), source: 'conseilJour')],
            dk(j(2)): [premiumJson(courseKey: cleCourse(2, 2, j(2)), source: 'conseilJour')],
            dk(j(3)): [premiumJson(courseKey: cleCourse(2, 3, j(3)), source: 'conseilJour')],
          },
        ),
        chargerArchive: true,
      );

      expect(serie('conseilJour', j(1)), 3,
          reason: 'A1 : les 3 victoires archivées doivent être retrouvées');
    });

    test('A1-T3b — même situation SANS chargement d\'archive : série de 0',
        () async {
      // Verrouille la réserve R1 : le repli d'A1 seul est inerte.
      await amorcer(
        construireStore(
          enArchive: [
            prono(courseKey: cleCourse(2, 1, j(1)), date: j(1)),
            prono(courseKey: cleCourse(2, 2, j(2)), date: j(2)),
            prono(courseKey: cleCourse(2, 3, j(3)), date: j(3)),
          ],
          premiumParDate: {
            dk(j(1)): [premiumJson(courseKey: cleCourse(2, 1, j(1)), source: 'conseilJour')],
            dk(j(2)): [premiumJson(courseKey: cleCourse(2, 2, j(2)), source: 'conseilJour')],
            dk(j(3)): [premiumJson(courseKey: cleCourse(2, 3, j(3)), source: 'conseilJour')],
          },
        ),
        chargerArchive: false,
      );

      expect(IaArchiveService.instance.archiveDisponible, isFalse);
      expect(serie('conseilJour', j(1)), 0,
          reason: 'sans charger(), versionRetenue renvoie null → la série '
              'est perdue (comportement d\'avant A1). C\'est pourquoi R1 '
              'est indispensable.');
    });

    test('A1-T4 — 2 jours ACTIFS + 2 jours ARCHIVÉS : série de 4', () async {
      await amorcer(
        construireStore(
          enMemoire: [
            prono(courseKey: cleCourse(3, 1, j(1)), date: j(1)),
            prono(courseKey: cleCourse(3, 2, j(2)), date: j(2)),
          ],
          enArchive: [
            prono(courseKey: cleCourse(3, 3, j(3)), date: j(3)),
            prono(courseKey: cleCourse(3, 4, j(4)), date: j(4)),
          ],
          premiumParDate: {
            dk(j(1)): [premiumJson(courseKey: cleCourse(3, 1, j(1)), source: 'conseilJour')],
            dk(j(2)): [premiumJson(courseKey: cleCourse(3, 2, j(2)), source: 'conseilJour')],
            dk(j(3)): [premiumJson(courseKey: cleCourse(3, 3, j(3)), source: 'conseilJour')],
            dk(j(4)): [premiumJson(courseKey: cleCourse(3, 4, j(4)), source: 'conseilJour')],
          },
        ),
        chargerArchive: true,
      );

      expect(serie('conseilJour', j(1)), 4,
          reason: 'mémoire ET archive doivent contribuer à la même série');
    });

    test('A1-T5 — jour PERDANT : la série s\'interrompt', () async {
      await amorcer(
        construireStore(
          enMemoire: [
            prono(courseKey: cleCourse(4, 1, j(1)), date: j(1)),
            // j(2) : sélection perdante → série cassée.
            prono(
              courseKey: cleCourse(4, 2, j(2)),
              date: j(2),
              arrivee: kArriveePerdante,
            ),
            prono(courseKey: cleCourse(4, 3, j(3)), date: j(3)),
          ],
          premiumParDate: {
            dk(j(1)): [premiumJson(courseKey: cleCourse(4, 1, j(1)), source: 'conseilJour')],
            dk(j(2)): [premiumJson(courseKey: cleCourse(4, 2, j(2)), source: 'conseilJour')],
            dk(j(3)): [premiumJson(courseKey: cleCourse(4, 3, j(3)), source: 'conseilJour')],
          },
        ),
        chargerArchive: true,
      );

      expect(serie('conseilJour', j(1)), 1,
          reason: 'j(2) perdant coupe la série : 1 seul jour consécutif');
      expect(serie('conseilJour', j(2)), 0,
          reason: 'le jour même est perdant');
      expect(serie('conseilJour', j(3)), 1,
          reason: 'la victoire du jour j(3) existe mais reste isolée');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  BLOC A1-C — INDÉPENDANCE DES SOUS-CATÉGORIES
  // ═══════════════════════════════════════════════════════════════════════

  group('A1-C — indépendance des sous-catégories', () {
    test('A1-T6 — Top Équilibre / Plus Sûr / Plus Rentable sont séparés',
        () async {
      await amorcer(
        construireStore(
          enArchive: [
            // Top Équilibre gagne j(1) et j(2).
            prono(courseKey: cleCourse(5, 1, j(1)), date: j(1)),
            prono(courseKey: cleCourse(5, 2, j(2)), date: j(2)),
            // Plus Sûr gagne j(1) à j(4).
            prono(courseKey: cleCourse(5, 3, j(1)), date: j(1)),
            prono(courseKey: cleCourse(5, 4, j(2)), date: j(2)),
            prono(courseKey: cleCourse(5, 5, j(3)), date: j(3)),
            prono(courseKey: cleCourse(5, 6, j(4)), date: j(4)),
          ],
          premiumParDate: {
            dk(j(1)): [
              premiumJson(courseKey: cleCourse(5, 1, j(1)), source: 'topEquilibre'),
              premiumJson(courseKey: cleCourse(5, 3, j(1)), source: 'plusSur'),
            ],
            dk(j(2)): [
              premiumJson(courseKey: cleCourse(5, 2, j(2)), source: 'topEquilibre'),
              premiumJson(courseKey: cleCourse(5, 4, j(2)), source: 'plusSur'),
            ],
            dk(j(3)): [
              premiumJson(courseKey: cleCourse(5, 5, j(3)), source: 'plusSur'),
            ],
            dk(j(4)): [
              premiumJson(courseKey: cleCourse(5, 6, j(4)), source: 'plusSur'),
            ],
          },
        ),
        chargerArchive: true,
      );

      expect(serie('topEquilibre', j(1)), 2, reason: 'Top Équilibre : 2 jours');
      expect(serie('plusSur', j(1)), 4, reason: 'Plus Sûr : 4 jours');
      expect(serie('plusRentable', j(1)), 0,
          reason: 'une victoire Top Équilibre n\'étend JAMAIS Plus Rentable');
      expect(serie('meilleurPari', j(1)), 0,
          reason: 'aucune sélection meilleurPari enregistrée');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  BLOC A1-D — AUCUNE VICTOIRE INVENTÉE
  // ═══════════════════════════════════════════════════════════════════════

  group('A1-D — aucune invention', () {
    test('A1-T7 — sélection Best Bet NON enregistrée : série de 0', () async {
      await amorcer(
        construireStore(
          enArchive: [
            prono(courseKey: cleCourse(6, 1, j(1)), date: j(1)),
            prono(courseKey: cleCourse(6, 2, j(2)), date: j(2)),
          ],
          // Historique premium VIDE : aucune sélection enregistrée.
        ),
        chargerArchive: true,
      );

      expect(serie('conseilJour', j(1)), 0,
          reason: 'sans sélection enregistrée, aucune victoire n\'est déduite');
      expect(serie('plusSur', j(1)), 0);
    });

    test('A1-T8 — résultat officiel ABSENT : série de 0', () async {
      await amorcer(
        construireStore(
          enArchive: [
            prono(courseKey: cleCourse(7, 1, j(1)), date: j(1), resolu: false),
            prono(courseKey: cleCourse(7, 2, j(2)), date: j(2), resolu: false),
          ],
          premiumParDate: {
            dk(j(1)): [premiumJson(courseKey: cleCourse(7, 1, j(1)), source: 'conseilJour')],
            dk(j(2)): [premiumJson(courseKey: cleCourse(7, 2, j(2)), source: 'conseilJour')],
          },
        ),
        chargerArchive: true,
      );

      expect(serie('conseilJour', j(1)), 0,
          reason: 'aucune arrivée réelle → aucune victoire déduite');
    });

    test('A1-T9 — plusieurs versions archivées : aucune victoire inventée',
        () async {
      // Deux versions CONCURRENTES de la même course : une gagnante, une
      // perdante. L'archive n'en retient qu'UNE (ordre d'autorité). La série
      // doit refléter EXACTEMENT la version retenue — ni plus, ni moins.
      final cle = cleCourse(8, 1, j(1));
      await amorcer(
        construireStore(
          enArchive: [
            prono(courseKey: cle, date: j(1)),
            prono(courseKey: cle, date: j(1), arrivee: kArriveePerdante),
          ],
          premiumParDate: {
            dk(j(1)): [premiumJson(courseKey: cle, source: 'conseilJour')],
          },
        ),
        chargerArchive: true,
      );

      final archive = IaArchiveService.instance;
      final retenue = archive.versionRetenue(cle);
      expect(retenue, isNotNull);

      // La victoire est celle de la version RETENUE, jamais une synthèse.
      final retenueGagne = IaMemoryService.instance.estPremiumGagnantStrict(
        premium: PremiumPronosticDuJour(
          courseKey: cle,
          typePari: 'Tiercé',
          numeros: kNumerosTierce,
          sourceWidget: 'conseilJour',
        ),
        prono: retenue!,
      );
      final s = serie('conseilJour', j(1));
      expect(s, retenueGagne ? 1 : 0,
          reason: 'la série doit être la conséquence EXACTE de la version '
              'retenue, jamais une fabrication');
      expect(s, lessThanOrEqualTo(1),
          reason: 'deux versions d\'une même course ne peuvent produire '
              'deux victoires');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  BLOC A1-E — ARBITRAGE PAR AUTORITÉ (A2, corrigé en V48)
  // ═══════════════════════════════════════════════════════════════════════

  // ★ A2 — Le test A1-T10 verrouillait la règle ANTÉRIEURE : `getPronostic(...)
  //   ?? versionRetenue(...)`, où une fiche ACTIVE non résolue masquait une
  //   fiche ARCHIVÉE résolue, et la série retombait à 0.
  //   Depuis V48, la sélection passe par `_versionLaPlusAutoritaire`
  //   (règle 4 : actif non résolu + archive résolue → archive). L'assertion
  //   est réécrite pour décrire la NOUVELLE règle métier. Ce qui reste
  //   interdit et est toujours vérifié : aucune victoire inventée, aucune
  //   réinjection, aucune modification de la règle de victoire elle-même.
  group('A1-E — arbitrage par autorité (A2)', () {
    test('A1-T10 — version active NON RÉSOLUE + archive RÉSOLUE : la série '
        'est retrouvée', () async {
      final cle = cleCourse(9, 1, j(1));
      await amorcer(
        construireStore(
          // Mémoire : la même course, NON résolue.
          enMemoire: [prono(courseKey: cle, date: j(1), resolu: false)],
          // Archive : la même course, RÉSOLUE ET GAGNANTE.
          enArchive: [prono(courseKey: cle, date: j(1))],
          premiumParDate: {
            dk(j(1)): [premiumJson(courseKey: cle, source: 'conseilJour')],
          },
        ),
        chargerArchive: true,
      );

      // Prérequis : la mémoire active est bien restée non résolue ET l'archive
      // contient bien la version résolue — c'est exactement la règle 4.
      expect(IaMemoryService.instance.getPronostic(cle)?.resultatsReels, isFalse,
          reason: 'la fiche active est non résolue (aucune réinjection)');
      expect(IaArchiveService.instance.versionRetenue(cle)?.resultatsReels,
          isTrue, reason: 'l\'archive contient bien la version résolue');
      expect(IaArchiveService.rangDe(
              IaArchiveService.instance.versionRetenue(cle)!),
          2, reason: 'la version archivée est résolue complète (rang 2)');

      expect(serie('conseilJour', j(1)), 1,
          reason: 'A2 : la fiche active NON RÉSOLUE ne masque plus la fiche '
              'archivée RÉSOLUE — la victoire est retrouvée et la série ne '
              'retombe plus à 0');

      // Non-régression : la règle de victoire n'a pas été touchée, et la
      // mémoire active n'a pas été modifiée par la lecture.
      expect(
        IaMemoryService.instance.estPremiumGagnantStrict(
          premium: PremiumPronosticDuJour(
            courseKey: cle,
            typePari: 'Tiercé',
            numeros: kNumerosTierce,
            sourceWidget: 'conseilJour',
          ),
          prono: IaArchiveService.instance.versionRetenue(cle)!,
        ),
        isTrue,
        reason: 'la victoire vient de la règle INCHANGÉE appliquée à la fiche '
            'archivée, jamais d\'une fabrication',
      );
      expect(IaMemoryService.instance.getPronostic(cle)?.resultatsReels, isFalse,
          reason: 'aucune complétion sur place de la fiche active');
    });

    test('A1-T10b — archive RÉSOLUE mais PERDANTE : la série reste à 0',
        () async {
      final cle = cleCourse(9, 2, j(1));
      await amorcer(
        construireStore(
          enMemoire: [prono(courseKey: cle, date: j(1), resolu: false)],
          // Résolue, mais arrivée sans aucun cheval de la sélection premium.
          enArchive: [
            prono(courseKey: cle, date: j(1), arrivee: kArriveePerdante),
          ],
          premiumParDate: {
            dk(j(1)): [premiumJson(courseKey: cle, source: 'conseilJour')],
          },
        ),
        chargerArchive: true,
      );

      expect(serie('conseilJour', j(1)), 0,
          reason: 'A2 change la SOURCE de la fiche, jamais la règle de '
              'victoire : une fiche résolue perdante ne produit rien');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  BLOC A1-F — LIMITES (90 JOURS) ET PLAFOND (600)
  // ═══════════════════════════════════════════════════════════════════════

  group('A1-F — limites inchangées', () {
    test('A1-T11 — série bornée à 90 jours', () async {
      // 95 jours gagnants consécutifs, tous archivés.
      final archives = <IaPronostic>[];
      final premiums = <String, List<Map<String, dynamic>>>{};
      for (var n = 1; n <= 95; n++) {
        final d = j(n);
        final k = cleCourse(10, n, d);
        archives.add(prono(courseKey: k, date: d));
        premiums[dk(d)] = [premiumJson(courseKey: k, source: 'conseilJour')];
      }

      await amorcer(
        construireStore(enArchive: archives, premiumParDate: premiums),
        chargerArchive: true,
      );

      expect(serie('conseilJour', j(1)), 90,
          reason: 'la boucle de balayage reste bornée à 90 jours');
    });

    test('A1-T12 — le plafond 600 et les pronostics actifs sont intacts',
        () async {
      // 600 pronostics actifs en mémoire, dont 2 gagnants premium.
      final memoire = <IaPronostic>[
        prono(courseKey: cleCourse(11, 1, j(1)), date: j(1)),
        prono(courseKey: cleCourse(11, 2, j(2)), date: j(2)),
      ];
      for (var i = memoire.length; i < 600; i++) {
        memoire.add(prono(courseKey: 'FILL${i}_${cleCourse(11, 3, j(30))}',
            date: j(30)));
      }

      await amorcer(
        construireStore(
          enMemoire: memoire,
          enArchive: [
            prono(courseKey: cleCourse(11, 4, j(3)), date: j(3)),
            prono(courseKey: cleCourse(11, 5, j(4)), date: j(4)),
          ],
          premiumParDate: {
            dk(j(1)): [premiumJson(courseKey: cleCourse(11, 1, j(1)), source: 'conseilJour')],
            dk(j(2)): [premiumJson(courseKey: cleCourse(11, 2, j(2)), source: 'conseilJour')],
            dk(j(3)): [premiumJson(courseKey: cleCourse(11, 4, j(3)), source: 'conseilJour')],
            dk(j(4)): [premiumJson(courseKey: cleCourse(11, 5, j(4)), source: 'conseilJour')],
          },
        ),
        chargerArchive: true,
      );

      final avant = IaMemoryService.instance.pronostics.length;
      final s = serie('conseilJour', j(1));
      final apres = IaMemoryService.instance.pronostics.length;

      expect(avant, 600, reason: 'jeu d\'essai : plafond atteint');
      expect(apres, avant,
          reason: 'le calcul de série ne réinjecte RIEN dans les pronostics');
      expect(s, 4,
          reason: '2 victoires actives + 2 victoires archivées, sans doublon');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  BLOC R1 — CHARGEMENT AVANT LE PREMIER RENDU
  // ═══════════════════════════════════════════════════════════════════════

  group('R1 — chargement de l\'archive', () {
    test('R1-T1 — l\'archive est chargée et exploitable avant tout écran',
        () async {
      await amorcer(
        construireStore(
          enArchive: [
            prono(courseKey: cleCourse(12, 1, j(1)), date: j(1)),
            prono(courseKey: cleCourse(12, 2, j(2)), date: j(2)),
          ],
          premiumParDate: {
            dk(j(1)): [premiumJson(courseKey: cleCourse(12, 1, j(1)), source: 'conseilJour')],
            dk(j(2)): [premiumJson(courseKey: cleCourse(12, 2, j(2)), source: 'conseilJour')],
          },
        ),
        chargerArchive: true,
      );

      expect(IaArchiveService.instance.archiveDisponible, isTrue);
      expect(IaArchiveService.instance.derniereErreurChargement, isNull);
      expect(
        IaArchiveService.instance.versionRetenue(cleCourse(12, 1, j(1))),
        isNotNull,
      );
      expect(serie('conseilJour', j(1)), 2);
    });

    test('R1-T2 — charger() est IDEMPOTENT : un seul cycle, aucune relecture',
        () async {
      await amorcer(
        construireStore(
          enArchive: [prono(courseKey: cleCourse(13, 1, j(1)), date: j(1))],
          premiumParDate: {
            dk(j(1)): [premiumJson(courseKey: cleCourse(13, 1, j(1)), source: 'conseilJour')],
          },
        ),
        chargerArchive: false,
      );

      var notifications = 0;
      void ecouteur() => notifications++;
      IaArchiveService.instance.addListener(ecouteur);
      try {
        await IaArchiveService.instance.charger();
        expect(notifications, 1, reason: 'une notification par cycle');
        await IaArchiveService.instance.charger();
        await IaArchiveService.instance.charger();
        expect(notifications, 1,
            reason: 'les appels suivants ne rechargent ni ne notifient');
      } finally {
        IaArchiveService.instance.removeListener(ecouteur);
      }
      expect(IaArchiveService.instance.archiveDisponible, isTrue);
      expect(serie('conseilJour', j(1)), 1);
    });

    test('R1-T3 — trois appels concurrents : un seul cycle partagé', () async {
      await amorcer(
        construireStore(
          enArchive: [prono(courseKey: cleCourse(14, 1, j(1)), date: j(1))],
        ),
        chargerArchive: false,
      );

      var notifications = 0;
      void ecouteur() => notifications++;
      IaArchiveService.instance.addListener(ecouteur);
      try {
        await Future.wait<void>(<Future<void>>[
          IaArchiveService.instance.charger(),
          IaArchiveService.instance.charger(),
          IaArchiveService.instance.charger(),
        ]);
      } finally {
        IaArchiveService.instance.removeListener(ecouteur);
      }
      expect(notifications, 1, reason: 'un seul cycle partagé');
      expect(IaArchiveService.instance.archiveDisponible, isTrue);
    });

    test('R1-T4 — erreur de stockage : le démarrage n\'est PAS bloqué',
        () async {
      final store = _PanneStore();
      SharedPreferencesStorePlatform.instance = store;
      // SharedPreferences met l'instance en CACHE STATIQUE : sans ce reset,
      // l'instance saine des tests précédents serait réutilisée et la panne
      // ne serait jamais atteinte.
      SharedPreferences.resetStatic();
      IaArchiveService.instance.oublierChargementPourTest();

      Object? leve;
      try {
        // C'est exactement ce que fait main() : un `await` qui ne doit
        // jamais lever, sinon `runApp()` ne serait pas atteint.
        await IaArchiveService.instance.charger();
      } catch (e) {
        leve = e;
      }

      expect(leve, isNull,
          reason: 'charger() absorbe l\'erreur : runApp() est toujours atteint');
      expect(IaArchiveService.instance.archiveDisponible, isFalse);
      expect(IaArchiveService.instance.derniereErreurChargement, isNotNull,
          reason: 'l\'échec est mémorisé, donc diagnosticable');

      // L'application reste utilisable : la mémoire seule est visible.
      expect(
        IaMemoryService.instance
            .donneesCalendrierJour(today.year, today.month),
        isEmpty,
      );
    });

    test('R1-T5 — main.dart charge l\'archive APRÈS IaMemoryService.init()',
        () {
      // Vérification de source : le contrat de R1 ne peut pas être prouvé par
      // un test unitaire (main() appelle runApp). On vérifie donc l'ordre réel
      // dans le fichier de démarrage.
      final source = File('lib/main.dart').readAsStringSync();
      final iInit = source.indexOf('await IaMemoryService.init();');
      final iArchive = source.indexOf('await IaArchiveService.instance.charger();');
      // Le PREMIER `runApp(` du fichier est le point de démarrage réel.
      final iRunApp = source.indexOf('  runApp(');

      expect(iInit, greaterThan(-1), reason: 'IaMemoryService.init() présent');
      expect(iArchive, greaterThan(-1),
          reason: 'charger() présent dans main() — correctif R1');
      expect(iRunApp, greaterThan(-1), reason: 'runApp() présent');
      expect(iArchive, greaterThan(iInit),
          reason: 'chargement APRÈS l\'init des pronostics');
      expect(iArchive, lessThan(iRunApp),
          reason: 'chargement AVANT le premier rendu : c\'est tout R1');
      expect(source.contains("import 'services/ia_archive_service.dart';"), isTrue,
          reason: 'l\'import de IaArchiveService est nécessaire');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  BLOC R1-NAV — COHÉRENCE ENTRE LES TROIS ÉCRANS
  // ═══════════════════════════════════════════════════════════════════════

  group('R1-Navigation — Home / Best Bet / Calendrier', () {
    test('R1-T6 — la même série est lue par les trois écrans', () async {
      await amorcer(
        construireStore(
          enArchive: [
            prono(courseKey: cleCourse(15, 1, j(1)), date: j(1)),
            prono(courseKey: cleCourse(15, 2, j(2)), date: j(2)),
            prono(courseKey: cleCourse(15, 3, j(3)), date: j(3)),
          ],
          premiumParDate: {
            dk(j(1)): [premiumJson(courseKey: cleCourse(15, 1, j(1)), source: 'topEquilibre')],
            dk(j(2)): [premiumJson(courseKey: cleCourse(15, 2, j(2)), source: 'topEquilibre')],
            dk(j(3)): [premiumJson(courseKey: cleCourse(15, 3, j(3)), source: 'topEquilibre')],
          },
        ),
        chargerArchive: true,
      );

      // Home et Best Bet passent par `streakPourSource` avec DateTime.now().
      // Le calendrier passe par le MÊME helper, avec la date de la bulle.
      // Ici la date de bulle = dernière victoire : les trois lectures doivent
      // être identiques, car il n'existe qu'une seule implémentation.
      final home = streakPourSource(
          sourceWidget: 'topEquilibre', dateReference: j(1)).jours;
      final bestBet = streakPourSource(
          sourceWidget: 'topEquilibre', dateReference: j(1)).jours;
      final calendrier = streakPourSource(
          sourceWidget: 'topEquilibre', dateReference: j(1)).jours;

      expect(home, 3);
      expect(bestBet, home, reason: 'Best Bet lit la même série que Home');
      expect(calendrier, home, reason: 'Calendrier lit la même série');
    });

    test('R1-T7 — la série ne dépend pas de l\'ordre de visite des écrans',
        () async {
      // Best Bet AVANT le calendrier : plus aucun ordre n'a d'importance
      // puisque l'archive est chargée au démarrage (R1).
      await amorcer(
        construireStore(
          enArchive: [
            prono(courseKey: cleCourse(16, 1, j(1)), date: j(1)),
            prono(courseKey: cleCourse(16, 2, j(2)), date: j(2)),
          ],
          premiumParDate: {
            dk(j(1)): [premiumJson(courseKey: cleCourse(16, 1, j(1)), source: 'plusRentable')],
            dk(j(2)): [premiumJson(courseKey: cleCourse(16, 2, j(2)), source: 'plusRentable')],
          },
        ),
        chargerArchive: true,
      );

      // Lecture « Home » d'abord.
      final avant = serie('plusRentable', j(1));
      // Le calendrier charge : no-op.
      await IaArchiveService.instance.charger();
      // Lecture « Calendrier » ensuite.
      final apres = serie('plusRentable', j(1));

      expect(avant, 2);
      expect(apres, avant, reason: 'ordre de visite indifférent');
    });
  });
}

// ───────────────────────────────────────────────────────────────────────────
//  FAUX STORE EN PANNE
// ───────────────────────────────────────────────────────────────────────────

class _PanneStore extends SharedPreferencesStorePlatform {
  @override
  Future<bool> clear() async => clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async =>
      throw StateError('panne de stockage simulée');

  @override
  Future<Map<String, Object>> getAll() async => getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<Map<String, Object>> getAllWithParameters(
          GetAllParameters parameters) async =>
      throw StateError('panne de stockage simulée');

  @override
  Future<bool> remove(String key) async =>
      throw StateError('panne de stockage simulée');

  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      throw StateError('panne de stockage simulée');
}
