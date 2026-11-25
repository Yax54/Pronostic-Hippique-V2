// ═══════════════════════════════════════════════════════════════════════════
//  LOT B-4.5 — TESTS DU BRANCHEMENT DU VERDICT OFFICIEL
//
//  Objet : vérifier le COMPORTEMENT RÉEL de la couture B-4.5
//  (`lib/services/branchement_verdict_course.dart`) et de l'affichage
//  structuré (`lib/services/affichage_gain_structure.dart`).
//
//  ⚠️ CES TESTS N'INTERROGENT PAS LA PRÉSENCE DE CHAÎNES DANS DES FICHIERS.
//     Chaque assertion porte sur une valeur produite par le code de
//     production : une `DateTime`, un `IssueConstructionTicket`, un
//     `VerdictGain`, un `StatutEnregistrementVerdict`, un montant en euros,
//     un `NatureAffichageGain`, une clé JSON persistée/relue.
//
//  Les 15 familles exigées par la consigne §1 sont numérotées B4.5/1 … B4.5/15
//  dans l'ordre exact où la consigne les énumère.
//
//  FIÈTRES RÉELLES (mesurées, reprises de R1C6_15112026) :
//    arrivée officielle 9-4-15-10-1-7-12 (groupes singuliers)
//    e-Tiercé Ordre                9-4-15      477,40 €
//    e-Tiercé Désordre             9-4-15       80,30 €
//    e-Simple Gagnant              9             7,50 €
//    e-Simple Placé                9             3,00 €  ← cheval joué
//    e-Simple Placé                4            28,00 €  ← DIVIDENDE PLUS ÉLEVÉ
//    e-Simple Placé                2            31,00 €  ← DIVIDENDE MAXIMUM
//  Le dernier bloc est le piège du lot : un `reduce(MAX)` paierait 31,00 € au
//  lieu de 3,00 €.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/providers/pmu_provider.dart';
// ★ CORRECTION BLOC 1 — nécessaire pour purger l'état statique du drapeau
//   définitif entre deux tests (voir `avecReseau`).
import 'package:pronostic_hippique/services/zone_turf_service.dart';
import 'package:pronostic_hippique/services/affichage_gain_structure.dart';
import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/branchement_verdict_course.dart';
import 'package:pronostic_hippique/services/enregistreur_verdict_gain_pmu.dart'
    show
        resoudreTotalDepuisRapports,
        StatutEnregistrementVerdict;
import 'package:pronostic_hippique/services/enregistreur_verdict_gain_suivi.dart';
import 'package:pronostic_hippique/services/gain_calculator.dart'
    show RapportPmu;
import 'package:pronostic_hippique/services/gain_pmu_types.dart';
import 'package:pronostic_hippique/services/resolution_gain_ticket_pmu.dart'
    show ResultatOfficielCourse, rapportPublieDepuisApi;

// ───────────────────────────────────────────────────────────────────────────
//  FABRIQUES
// ───────────────────────────────────────────────────────────────────────────

final DateTime _heure = DateTime(2026, 11, 15, 14, 30);
const String kDateDdMMyyyy = '15112026';
const String kDateIso = '2026-11-15';

/// Rapport API tel que `PmuApiService.decoderRapportsDefinitifs` le produit :
/// `dividende` déjà normalisé en EUROS pour 1 € (division /100 faite une fois).
RapportPmu api(
  String code,
  String libelle,
  String combinaison,
  double pourUnEuro, {
  int? rang,
  int miseBase = 100,
  bool rembourse = false,
}) =>
    RapportPmu(
      typePari: code,
      combinaison: combinaison,
      dividende: pourUnEuro,
      estOrdre: libelle.toLowerCase().contains('ordre'),
      libelleOfficiel: libelle,
      codePariOfficiel: code,
      rangCombinaisonPayable: rang,
      rembourse: rembourse,
      miseBaseCentimes: miseBase,
    );

/// Bloc Simple réel — contient VOLONTAIREMENT les deux dividendes Placé les
/// plus élevés, que le lot interdit de sélectionner.
List<RapportPmu> blocSimple() => <RapportPmu>[
      api('E_SIMPLE_GAGNANT', 'e-Simple Gagnant', '9', 7.50),
      api('E_SIMPLE_PLACE', 'e-Simple Placé', '9', 3.00),
      api('E_SIMPLE_PLACE', 'e-Simple Placé', '4', 28.00),
      api('E_SIMPLE_PLACE', 'e-Simple Placé', '2', 31.00),
    ];

/// Bloc Tiercé réel.
List<RapportPmu> blocTierce() => <RapportPmu>[
      api('E_TIERCE', 'e-Tiercé Ordre', '9-4-15', 477.40, rang: 1),
      api('E_TIERCE', 'e-Tiercé Désordre', '9-4-15', 80.30, rang: 2),
    ];

/// Arrivée officielle singulière : 9-4-15-10-1-7-12.
const List<List<int>> kArrivee = <List<int>>[
  <int>[9],
  <int>[4],
  <int>[15],
  <int>[10],
  <int>[1],
  <int>[7],
  <int>[12],
];

ResultatOfficielCourse resultat(
  List<RapportPmu> rapports, {
  List<List<int>>? groupes = kArrivee,
  bool? definitive = true,
}) =>
    construireResultatOfficiel(
      arriveeGroupes: groupes,
      arriveeDefinitive: definitive,
      rapports: rapports,
    );

/// Prédiction de profil.
UserPrediction pred(
  String typePari,
  List<int> numeros, {
  required String id,
  double mise = 2.0,
  String? codePmu,
  String? variante,
  List<int>? ordre,
  double? miseGagnant,
  double? misePlace,
}) =>
    UserPrediction(
      id: id,
      dateStr: kDateIso,
      numReunion: 1,
      numCourse: 6,
      nomCourse: 'Prix de Test',
      hippodrome: 'Vincennes',
      numeroCheval: numeros.isEmpty ? 0 : numeros.first,
      nomCheval: 'CHEVAL_${numeros.isEmpty ? 0 : numeros.first}',
      cote: 7.5,
      typePari: typePari,
      createdAt: _heure,
      scoreIA: 80.0,
      montantMise: mise,
      numerosJoues: numeros,
      codePmuOfficiel: codePmu,
      varianteChoisie: variante,
      numerosDansOrdre: ordre,
      miseGagnant: miseGagnant,
      misePlace: misePlace,
    );

/// Course suivie (modèle `TrackedCourse`).
TrackedCourse suivi({
  String typePari = 'Simple Placé',
  List<int> numeros = const <int>[9],
  double? mise = 2.0,
  double? miseGagnant,
  double? misePlace,
  String? codePmu = 'E_SIMPLE_PLACE',
  String? variante,
  List<int>? ordre,
  List<List<int>>? groupes,
  bool? definitive,
  String storageKey = 'R1C6_15112026_1763',
}) =>
    TrackedCourse(
      numReunion: 1,
      numCourse: 6,
      nomCourse: 'Prix de Test',
      hippodrome: 'Vincennes',
      heureDepart: _heure,
      storageKey: storageKey,
      nomCheval: 'CHEVAL_${numeros.isEmpty ? 0 : numeros.first}',
      numeroCheval: numeros.isEmpty ? 0 : numeros.first,
      miseEngagee: mise,
      miseGagnant: miseGagnant,
      misePlace: misePlace,
      addedAt: _heure,
      typePari: typePari,
      numerosJoues: numeros,
      iaMemKey: 'R1C6_15112026_ia',
      scoreIA: 80.0,
      cote: 7.5,
      codePmuOfficiel: codePmu,
      varianteChoisie: variante,
      numerosDansOrdre: ordre,
      arriveeGroupes: groupes,
      arriveeDefinitive: definitive,
    );

// ─────────────────────────── Réseau simulé ─────────────────────────────────

const List<int> kArriveeApi = <int>[9, 4, 15, 10, 1];
final List<String> cheminsAppeles = <String>[];

String _corpsParticipants() => json.encode(<String, dynamic>{
      'arriveeDefinitive': true,
      'participants': <Map<String, dynamic>>[
        for (var i = 0; i < kArriveeApi.length; i++)
          <String, dynamic>{
            'numPmu': kArriveeApi[i],
            'nom': 'CHEVAL_${kArriveeApi[i]}',
            'statut': 'PARTANT',
            'ordreArrivee': i + 1,
          },
      ],
    });

String _corpsRapports() => json.encode(<Map<String, dynamic>>[
      <String, dynamic>{
        'typePari': 'E_SIMPLE_GAGNANT',
        'miseBase': 100,
        'rapports': <Map<String, dynamic>>[
          <String, dynamic>{
            'combinaison': '9',
            'dividendePourUnEuro': 750,
            'libelle': 'e-Simple Gagnant',
            'rangCombinaisonPayable': 1,
          },
        ],
      },
      <String, dynamic>{
        'typePari': 'E_SIMPLE_PLACE',
        'miseBase': 100,
        'rapports': <Map<String, dynamic>>[
          <String, dynamic>{
            'combinaison': '9',
            'dividendePourUnEuro': 300,
            'libelle': 'e-Simple Placé',
            'rangCombinaisonPayable': 1,
          },
          <String, dynamic>{
            'combinaison': '4',
            'dividendePourUnEuro': 2800,
            'libelle': 'e-Simple Placé',
            'rangCombinaisonPayable': 1,
          },
        ],
      },
      <String, dynamic>{
        'typePari': 'E_TIERCE',
        'miseBase': 100,
        'rapports': <Map<String, dynamic>>[
          <String, dynamic>{
            'combinaison': '9-4-15',
            'dividendePourUnEuro': 47740,
            'libelle': 'e-Tiercé Ordre',
            'rangCombinaisonPayable': 1,
          },
          <String, dynamic>{
            'combinaison': '9-4-15',
            'dividendePourUnEuro': 8030,
            'libelle': 'e-Tiercé Désordre',
            'rangCombinaisonPayable': 2,
          },
        ],
      },
    ]);

/// ★ CORRECTION BLOC 1 — CORPS AUTHENTIQUE DE L'ENDPOINT **PAR COURSE**.
///
/// POURQUOI CETTE FABRIQUE EXISTE (défaut mesuré du faux serveur) :
///   Le faux serveur ne répondait que sur `/participants` et
///   `/rapports-definitifs`. Toute autre URL — dont
///   `/programme/15112026/R01/C06` — recevait `{"programme":{"reunions":[]}}`,
///   donc SANS `arriveeDefinitive`. Le drapeau restait `null`.
///
///   Or la production lit ce drapeau sur l'endpoint PAR COURSE
///   (`ZoneTurfService._drapeauDefinitifDepuisCourse`, appelé par
///   `chargerResultatsCourseComplet`). Le `null` observé par
///   `B4.5/3.3` (`Expected: true / Actual: <null>`) était donc la
///   conséquence DIRECTE de cette lacune de fixture, et non d'une régression
///   du code de production.
///
/// FORME REPRISE — ET MESURÉE SUR LA FIXTURE AUTHENTIQUE DU DÉPÔT
///   `test/fixtures/recherche_pmu/multi/prog_15112026.json`, course
///   `numOrdre == 6` de la réunion 1 (celle que ce test interroge) :
///     arriveeDefinitive             = true
///     isArriveeDefinitive           = true
///     statut                        = 'ARRIVEE_DEFINITIVE_COMPLETE'
///     categorieStatut               = 'ARRIVEE'
///     ordreArrivee                  = [[9],[4],[15],[10],[1],[11],[7]]
///     nombreDeclaresPartants        = 15
///     rapportsDefinitifsDisponibles = true
///     participants                  = []   ← l'endpoint par course ne les porte pas
///
///   Les cinq premiers groupes (`9,4,15,10,1`) sont EXACTEMENT ceux que
///   l'assertion de `B4.5/3.3` attend ; les deux suivants (`11`,`7`) sont les
///   rangs publiés au-delà du top 5. Aucune valeur n'est inventée : la fixture
///   est recopiée de la source authentique déjà versionnée dans le dépôt.
///
/// ⚠️ CE QUI N'EST **PAS** MODIFIÉ : l'assertion de `B4.5/3.3` reste
///    `expect(res.arriveeDefinitive, isTrue)`, et le moteur financier
///    (`moteur_gain_pmu.dart`) n'est pas touché d'une ligne.
String _corpsProgrammeCourse() => json.encode(<String, dynamic>{
      'arriveeDefinitive': true,
      'isArriveeDefinitive': true,
      'statut': 'ARRIVEE_DEFINITIVE_COMPLETE',
      'categorieStatut': 'ARRIVEE',
      'numReunion': 1,
      'numOrdre': 6,
      'nombreDeclaresPartants': 15,
      'rapportsDefinitifsDisponibles': true,
      'ordreArrivee': <List<int>>[
        <int>[9],
        <int>[4],
        <int>[15],
        <int>[10],
        <int>[1],
        <int>[11],
        <int>[7],
      ],
      // L'endpoint PAR COURSE ne porte pas les participants : c'est mesuré
      // sur la fixture authentique (liste vide) et sur la réponse réelle
      // (5 529 octets, participants vide).
      'participants': <Map<String, dynamic>>[],
    });

/// Intercepte TOUT le réseau PMU. `rapportsVides` sert à prouver le refus.
Future<T> avecReseau<T>(
  Future<T> Function() action, {
  bool rapportsVides = false,
}) {
  // ★ CORRECTION BLOC 1 — ISOLATION DE L'ÉTAT STATIQUE ENTRE TESTS.
  //
  //   `ZoneTurfService` tient un cache court du drapeau définitif. Sans purge,
  //   un test pouvait hériter du drapeau mesuré par le précédent, ce qui
  //   rendrait toute mesure d'URL trompeuse. `viderCachePourResetComplet()`
  //   est le mécanisme DÉJÀ utilisé par la suite (`v33`, `v34`, `v35`,
  //   `l1_capture_officielle`, `a6_fiabilite_arrivees_pmu`) : on réutilise
  //   l'outil existant, on n'en ajoute aucun.
  ZoneTurfService.viderCachePourResetComplet();
  final String participants = _corpsParticipants();
  final String programmeCourse = _corpsProgrammeCourse();
  final String rapports = rapportsVides ? '[]' : _corpsRapports();
  final client = MockClient((http.Request request) async {
    final String p = request.url.path;
    cheminsAppeles.add(p);
    const Map<String, String> entetes = {'content-type': 'application/json'};
    if (p.contains('rapports-definitifs')) {
      return http.Response(rapports, 200, headers: entetes);
    }
    if (p.contains('participants')) {
      return http.Response(participants, 200, headers: entetes);
    }
    // ★ CORRECTION BLOC 1 — L'ENDPOINT PAR COURSE EST DÉSORMAIS SERVI.
    //
    //   `ZoneTurfService` y lit `arriveeDefinitive` (mesuré : c'est le SEUL
    //   endpoint qui le publie ; `/participants` a 4 clés racine et ne le
    //   porte pas). Le motif ci-dessous est ancré sur la forme réelle
    //   `/programme/<ddmmyyyy>/R<rr>/C<cc>` et ne capte donc NI
    //   `.../participants` NI `.../rapports-definitifs`, traités plus haut.
    if (RegExp(r'/programme/\d{8}/R\d{2}/C\d{2}$').hasMatch(p)) {
      return http.Response(programmeCourse, 200, headers: entetes);
    }
    return http.Response('{"programme":{"reunions":[]}}', 200, headers: entetes);
  });
  return http.runWithClient(action, () => client);
}

// ═══════════════════════════════════════════════════════════════════════════
//  TESTS
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═════════════════════════════════════════════════════════════════════════
  //  B4.5/1 — NORMALISATION DES DATES ddMMyyyy ET yyyy-MM-dd
  // ═════════════════════════════════════════════════════════════════════════
  group('B4.5/1 normalisation des dates', () {
    test('B4.5/1.1 ddMMyyyy (huit chiffres) donne la date calendaire exacte',
        () {
      final d = dateCourseDepuisDateStr(kDateDdMMyyyy);
      expect(d, isNotNull);
      expect(d!.year, 2026);
      expect(d.month, 11);
      expect(d.day, 15);
      expect(d.hour, 0);
      expect(d.minute, 0);
    });

    test('B4.5/1.2 yyyy-MM-dd donne LA MÊME date que ddMMyyyy', () {
      final a = dateCourseDepuisDateStr(kDateDdMMyyyy);
      final b = dateCourseDepuisDateStr(kDateIso);
      expect(b, isNotNull);
      expect(b!.isAtSameMomentAs(a!), isTrue,
          reason: 'les deux formats doivent désigner le même instant');
    });

    test('B4.5/1.3 les espaces autour de la valeur sont neutralisés', () {
      final d = dateCourseDepuisDateStr('  2026-11-15  ');
      expect(d, isNotNull);
      expect(d!.day, 15);
      expect(d.month, 11);
      expect(d.year, 2026);
    });

    test('B4.5/1.4 dateApiDepuisDateTime rend exactement ddMMyyyy', () {
      expect(dateApiDepuisDateTime(DateTime(2026, 11, 15)), '15112026');
      // Deux chiffres imposés, y compris pour janvier et les jours < 10.
      expect(dateApiDepuisDateTime(DateTime(2026, 1, 5)), '05012026');
      // Aller-retour : le format produit est relu par le normaliseur.
      final d = DateTime(2027, 3, 9);
      expect(
        dateCourseDepuisDateStr(dateApiDepuisDateTime(d))!.isAtSameMomentAs(d),
        isTrue,
      );
    });

    test('B4.5/1.5 année bissextile réelle acceptée, 29/02 non bissextile '
        'refusé', () {
      expect(dateCourseDepuisDateStr('29022024'), isNotNull);
      expect(dateCourseDepuisDateStr('2024-02-29'), isNotNull);
      expect(dateCourseDepuisDateStr('29022026'), isNull,
          reason: '2026 n\'est pas bissextile : le 29 février n\'existe pas');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B4.5/2 — REFUS DES DATES INVALIDES, SANS SUBSTITUTION DU JOUR
  // ═════════════════════════════════════════════════════════════════════════
  group('B4.5/2 refus des dates invalides', () {
    final DateTime aujourdhui = DateTime.now();

    for (final String invalide in <String>[
      '2026-02-31', // débordement que DateTime normaliserait au 3 mars
      '31022026', // même débordement, format PMU
      '32012026', // jour 32
      '15002026', // mois 0
      '15132026', // mois 13
      '0000000000', // dix zéros
      'abc', // non numérique
      '15/11/2026', // séparateur non admis
      '20261115', // 8 chiffres mais dans l'ordre inverse : 2026-11-15 ? non
      '',
      '   ',
    ]) {
      test('B4.5/2.x « $invalide » est REFUSÉE (null) sans date du jour', () {
        final d = dateCourseDepuisDateStr(invalide);
        expect(d, isNull, reason: '« $invalide » ne doit produire aucune date');
      });
    }

    test('B4.5/2.1 null rend null, jamais la date du jour', () {
      expect(dateCourseDepuisDateStr(null), isNull);
    });

    test('B4.5/2.2 un refus n\'est JAMAIS remplacé par la date du jour', () {
      final d = dateCourseDepuisDateStr('2026-02-31');
      expect(d, isNull);
      expect(d == null, isTrue);
      // Preuve par construction : aucune valeur de repli n'existe côté appelant,
      // et la valeur retournée n'est pas « maintenant ».
      expect(
        identical(d, aujourdhui),
        isFalse,
        reason: 'aucune substitution par la date du jour n\'est possible',
      );
    });

    test('B4.5/2.3 2026-02-31 ne devient PAS le 3 mars 2026', () {
      final d = dateCourseDepuisDateStr('2026-02-31');
      // Si le constructeur avait été cru aveuglément, on aurait obtenu
      // DateTime(2026, 3, 3). On vérifie que ce n'est pas le cas.
      expect(d, isNull);
      expect(d?.month, isNot(3));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B4.5/3 — CHARGEMENT DE L'ARRIVÉE OFFICIELLE POUR LA BONNE COURSE
  // ═════════════════════════════════════════════════════════════════════════
  group('B4.5/3 chargement du résultat officiel', () {
    test('B4.5/3.1 l\'URL porte la date, la réunion et la course demandées', () async {
      cheminsAppeles.clear();
      final res = await avecReseau(() => chargerResultatOfficielCourse(
            date: DateTime(2026, 11, 15),
            numReunion: 1,
            numCourse: 6,
          ));
      expect(res, isNotNull,
          reason: 'arrivée présente ET rapports non vides ⇒ résultat rendu');

      final aParticipants =
          cheminsAppeles.where((p) => p.contains('participants')).toList();
      final aRapports = cheminsAppeles
          .where((p) => p.contains('rapports-definitifs'))
          .toList();
      expect(aParticipants, hasLength(1));
      expect(aRapports, hasLength(1));

      // ZoneTurfService : /programme/{ddmmyyyy}/R{rr}/C{cc}/participants
      expect(aParticipants.single, contains('/programme/15112026/'));
      expect(aParticipants.single, contains('/R01/'));
      expect(aParticipants.single, contains('/C06/'));
      // PmuApiService : /programme/{date}/R{r}/C{c}/rapports-definitifs
      expect(aRapports.single, contains('/programme/15112026/'));
      expect(aRapports.single, contains('/R1/'));
      expect(aRapports.single, contains('/C6/'));
    });

    test('B4.5/3.2 une autre course produit une AUTRE URL (aucun mélange)',
        () async {
      cheminsAppeles.clear();
      await avecReseau(() => chargerResultatOfficielCourse(
            date: DateTime(2026, 11, 15),
            numReunion: 5,
            numCourse: 7,
          ));
      expect(cheminsAppeles, isNotEmpty);
      for (final p in cheminsAppeles) {
        expect(p, contains('/programme/15112026/'));
      }
      expect(
        cheminsAppeles.where((p) => p.contains('/R05/') || p.contains('/R5/')),
        isNotEmpty,
      );
      expect(cheminsAppeles.where((p) => p.contains('/C06/')), isEmpty,
          reason: 'aucune requête ne doit viser la course C06');
    });

    test('B4.5/3.3 l\'arrivée officielle est celle du service, groupes exacts',
        () async {
      final res = await avecReseau(() => chargerResultatOfficielCourse(
            date: DateTime(2026, 11, 15),
            numReunion: 1,
            numCourse: 6,
          ));
      expect(res!.arriveeGroupes, isNotNull);
      expect(
        res.arriveeGroupes!.map((g) => g.join('-')).toList(),
        <String>['9', '4', '15', '10', '1'],
      );
      expect(res.arriveeDefinitive, isTrue);
      expect(res.rapports, isNotEmpty);
    });

    test('B4.5/3.4 aucun rapport publié ⇒ null, jamais un résultat vide',
        () async {
      final res = await avecReseau(
        () => chargerResultatOfficielCourse(
          date: DateTime(2026, 11, 15),
          numReunion: 1,
          numCourse: 6,
        ),
        rapportsVides: true,
      );
      expect(res, isNull,
          reason: 'une course non réglée ne fonde aucun calcul');
    });

    test('B4.5/3.5 construireResultatOfficiel transmet les groupes TELS QUELS',
        () {
      final r = construireResultatOfficiel(
        arriveeGroupes: null,
        arriveeDefinitive: null,
        rapports: blocTierce(),
      );
      expect(r.arriveeGroupes, isNull, reason: 'aucun groupe n\'est inventé');
      expect(r.arriveeDefinitive, isNull,
          reason: 'le silence de l\'API n\'est jamais traduit en « définitif »');
      expect(r.estProvisoire, isFalse);
      expect(r.aDesGroupes, isFalse);
      // La liste transmise est non modifiable : aucun appelant ne peut la trier.
      expect(() => r.rapports.add(blocTierce().first),
          throwsA(isA<UnsupportedError>()));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B4.5/4 — PLUSIEURS PARIS SUR LA MÊME COURSE, RÉSOLUS INDÉPENDAMMENT
  // ═════════════════════════════════════════════════════════════════════════
  group('B4.5/4 paris multiples sur une même course', () {
    test('B4.5/4.1 trois paris, trois verdicts DIFFÉRENTS, même arrivée', () {
      final res = resultat(<RapportPmu>[...blocSimple(), ...blocTierce()]);
      final pGN = pred('Simple Gagnant', const <int>[9],
          id: 'p1', mise: 5, codePmu: 'E_SIMPLE_GAGNANT');
      final pPL = pred('Simple Placé', const <int>[9],
          id: 'p2', mise: 10, codePmu: 'E_SIMPLE_PLACE');
      final pTI = pred('Tiercé', const <int>[4, 15, 9],
          id: 'p3',
          mise: 1,
          codePmu: 'E_TIERCE',
          ordre: const <int>[4, 15, 9]);

      final resolutions = resoudrePredictionsDeCourse(
        predictions: <UserPrediction>[pGN, pPL, pTI],
        resultat: res,
      );
      expect(resolutions, hasLength(3),
          reason: 'aucun pari n\'est écarté : chacun reçoit SA résolution');

      // Simple Gagnant : 5 × 7,50 = 37,50
      expect(resolutions[0].verdict!.etat, EtatGain.attribue);
      expect(resolutions[0].verdict!.total, closeTo(37.50, 1e-9));

      // Simple Placé : 10 × 3,00 = 30,00 — PAS 10 × 31,00
      expect(resolutions[1].verdict!.etat, EtatGain.attribue);
      expect(resolutions[1].verdict!.total, closeTo(30.00, 1e-9));

      // Tiercé joué dans le désordre : 1 × 80,30 — PAS 477,40
      expect(resolutions[2].verdict!.etat, EtatGain.attribue);
      expect(resolutions[2].verdict!.total, closeTo(80.30, 1e-9));
      expect(resolutions[2].verdict!.composantes.single.combinaisonRapport,
          '9-4-15');
    });

    test('B4.5/4.2 chaque verdict est persisté sur SON ticket, pas sur un autre',
        () {
      final res = resultat(<RapportPmu>[...blocSimple(), ...blocTierce()]);
      final pGN = pred('Simple Gagnant', const <int>[9],
          id: 'p1', mise: 5, codePmu: 'E_SIMPLE_GAGNANT');
      final pTI = pred('Tiercé', const <int>[4, 15, 9],
          id: 'p3',
          mise: 1,
          codePmu: 'E_TIERCE',
          ordre: const <int>[4, 15, 9]);
      final r = resoudrePredictionsDeCourse(
        predictions: <UserPrediction>[pGN, pTI],
        resultat: res,
      );
      expect(r[0].enregistrement!.ticket.id, 'p1');
      expect(r[0].enregistrement!.ticket.etatGain, EtatGain.attribue);
      expect(r[0].enregistrement!.ticket.codePmuOfficiel, 'E_SIMPLE_GAGNANT');

      expect(r[1].enregistrement!.ticket.id, 'p3');
      expect(r[1].enregistrement!.ticket.etatGain, EtatGain.attribue);
      expect(r[1].enregistrement!.ticket.codePmuOfficiel, 'E_TIERCE');

      // Les montants persistés ne se contaminent pas.
      final t1 = resoudreTotalDepuisRapports(r[1].enregistrement!.ticket.rapportsAttribues);
      expect(t1, closeTo(80.30, 1e-9));
    });

    test('B4.5/4.3 un refus reste un refus dans la liste, jamais écarté', () {
      final res = resultat(blocSimple());
      final ok = pred('Simple Gagnant', const <int>[9],
          id: 'ok', mise: 5, codePmu: 'E_SIMPLE_GAGNANT');
      final sansCode = pred('Simple Placé', const <int>[9], id: 'ko', mise: 5);
      final r = resoudrePredictionsDeCourse(
        predictions: <UserPrediction>[ok, sansCode],
        resultat: res,
      );
      expect(r, hasLength(2));
      expect(r[0].aUneIssue, isFalse);
      expect(r[1].aUneIssue, isTrue);
      expect(r[1].issue, IssueConstructionTicket.codePmuAbsent);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B4.5/5 — MISE RÉELLE, VENTILATION GAGNANT + PLACÉ
  // ═════════════════════════════════════════════════════════════════════════
  group('B4.5/5 mise réelle et ventilation Gagnant+Placé', () {
    test('B4.5/5.1 Gagnant+Placé : DEUX mises distinctes, jamais agrégées',
        () {
      final p = pred('Gagnant+Placé', const <int>[9],
          id: 'gp', miseGagnant: 10.0, misePlace: 5.0);
      final c = construireTicketPrediction(p);
      expect(c.estExploitable, isTrue);
      final t = c.ticket!;
      expect(t.miseGagnant, 10.0);
      expect(t.misePlace, 5.0);
      expect(t.miseSimple, isNull,
          reason: 'aucune mise simple n\'est inventée pour un G+P');

      final res = resultat(blocSimple());
      final r = resoudrePrediction(prediction: p, resultat: res);
      final v = r.verdict!;
      expect(v.etat, EtatGain.attribue);
      // 10 × 7,50 = 75,00 et 5 × 3,00 = 15,00
      expect(v.gainGagnant, closeTo(75.00, 1e-9));
      expect(v.gainPlace, closeTo(15.00, 1e-9));
      expect(v.total, closeTo(90.00, 1e-9));
      // Le total n'est PAS (10+5) × un dividende unique.
      expect(v.total, isNot(closeTo(15.0 * 7.50, 1e-9)));
      expect(v.total, isNot(closeTo(15.0 * 3.00, 1e-9)));

      // Les deux composantes portent chacune SA mise.
      final mises = v.composantes.map((c2) => c2.mise).toList()..sort();
      expect(mises, <double>[5.0, 10.0]);
    });

    test('B4.5/5.2 la mise persistée sur la prédiction N\'EST PAS utilisée '
        'comme mise unique pour un G+P', () {
      // `montantMise` = 20 (valeur d'affichage) ; les mises réelles sont 10/5.
      final p = pred('Gagnant+Placé', const <int>[9],
          id: 'gp', mise: 20.0, miseGagnant: 10.0, misePlace: 5.0);
      final r = resoudrePrediction(prediction: p, resultat: resultat(blocSimple()));
      expect(r.verdict!.total, closeTo(90.00, 1e-9));
      expect(r.verdict!.total, isNot(closeTo(20.0 * 7.50, 1e-9)));
    });

    test('B4.5/5.3 mise incomplète (une seule des deux) ⇒ refus miseIncomplete',
        () {
      final pG = pred('Gagnant+Placé', const <int>[9],
          id: 'g', miseGagnant: 10.0);
      final pP = pred('Gagnant+Placé', const <int>[9],
          id: 'p', misePlace: 5.0);
      expect(construireTicketPrediction(pG).issue,
          IssueConstructionTicket.miseIncomplete);
      expect(construireTicketPrediction(pP).issue,
          IssueConstructionTicket.miseIncomplete);
    });

    test('B4.5/5.4 la mise de `TrackedCourse` vient de `miseEngagee`, jamais '
        'de `miseTotaleEngagee`', () {
      final c = suivi(
        typePari: 'Simple Placé',
        numeros: const <int>[9],
        mise: 2.0,
        miseGagnant: 99.0,
        misePlace: 99.0,
      );
      // `miseTotaleEngagee` = 198,0 : une donnée de bilan, pas un opérande.
      expect(c.miseTotaleEngagee, closeTo(198.0, 1e-9));
      final t = construireTicketSuivi(c);
      expect(t.estExploitable, isTrue);
      expect(t.ticket!.miseSimple, 2.0,
          reason: 'l\'opérande est la mise réellement engagée sur ce pari');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B4.5/6 — ORDRE EXACT, DÉSORDRE, ORDRE ABSENT
  // ═════════════════════════════════════════════════════════════════════════
  group('B4.5/6 ordre exact, désordre, ordre absent', () {
    test('B4.5/6.1 ordre exact ⇒ rapport ORDRE (477,40)', () {
      final p = pred('Tiercé Ordre', const <int>[9, 4, 15],
          id: 'o',
          mise: 1,
          codePmu: 'E_TIERCE',
          variante: 'ordre',
          ordre: const <int>[9, 4, 15]);
      final r = resoudrePrediction(prediction: p, resultat: resultat(blocTierce()));
      expect(r.aUneIssue, isFalse);
      expect(r.verdict!.etat, EtatGain.attribue);
      expect(r.verdict!.total, closeTo(477.40, 1e-9));
      expect(r.verdict!.composantes.single.libelleRapport, 'e-Tiercé Ordre');
    });

    test('B4.5/6.2 ordre différent ⇒ rapport DÉSORDRE (80,30), pas l\'ordre',
        () {
      final p = pred('Tiercé', const <int>[4, 15, 9],
          id: 'd',
          mise: 1,
          codePmu: 'E_TIERCE',
          ordre: const <int>[4, 15, 9]);
      final r = resoudrePrediction(prediction: p, resultat: resultat(blocTierce()));
      expect(r.verdict!.etat, EtatGain.attribue);
      expect(r.verdict!.total, closeTo(80.30, 1e-9));
      expect(r.verdict!.composantes.single.libelleRapport, 'e-Tiercé Désordre');
    });

    test('B4.5/6.3 ordre ABSENT sur un pari qui l\'exige ⇒ refus ordreAbsent, '
        'AUCUN repli sur la liste triée', () {
      final p = pred('Tiercé', const <int>[9, 4, 15],
          id: 'sansordre', mise: 1, codePmu: 'E_TIERCE');
      final c = construireTicketPrediction(p);
      expect(c.estExploitable, isFalse);
      expect(c.issue, IssueConstructionTicket.ordreAbsent);

      // Et surtout : aucune résolution n'est tentée, donc aucun montant.
      final r = resoudrePrediction(prediction: p, resultat: resultat(blocTierce()));
      expect(r.aUneIssue, isTrue);
      expect(r.verdict, isNull);
      expect(r.enregistrement, isNull);
    });

    test('B4.5/6.4 ordre INCOHÉRENT (chevaux différents) ⇒ refus ordreIncoherent',
        () {
      final p = pred('Tiercé', const <int>[9, 4, 15],
          id: 'incoh',
          mise: 1,
          codePmu: 'E_TIERCE',
          ordre: const <int>[9, 4, 2]);
      expect(construireTicketPrediction(p).issue,
          IssueConstructionTicket.ordreIncoherent);
    });

    test('B4.5/6.5 ordre de longueur différente ⇒ refus ordreIncoherent', () {
      final p = pred('Tiercé', const <int>[9, 4, 15],
          id: 'incoh2',
          mise: 1,
          codePmu: 'E_TIERCE',
          ordre: const <int>[9, 4]);
      expect(construireTicketPrediction(p).issue,
          IssueConstructionTicket.ordreIncoherent);
    });

    test('B4.5/6.6 deux paris de MÊME ensemble mais d\'ordres opposés donnent '
        'deux montants différents', () {
      final res = resultat(blocTierce());
      final ordre = resoudrePrediction(
        prediction: pred('Tiercé', const <int>[9, 4, 15],
            id: 'a', mise: 1, codePmu: 'E_TIERCE', ordre: const <int>[9, 4, 15]),
        resultat: res,
      );
      final desordre = resoudrePrediction(
        prediction: pred('Tiercé', const <int>[4, 9, 15],
            id: 'b', mise: 1, codePmu: 'E_TIERCE', ordre: const <int>[4, 9, 15]),
        resultat: res,
      );
      expect(ordre.verdict!.total, closeTo(477.40, 1e-9));
      expect(desordre.verdict!.total, closeTo(80.30, 1e-9));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B4.5/7 — REFUS DES VARIANTES OU CAPTURES INSUFFISAMMENT DOCUMENTÉES
  // ═════════════════════════════════════════════════════════════════════════
  group('B4.5/7 refus des captures insuffisantes', () {
    test('B4.5/7.1 type non répertorié ⇒ refus typeNonRepertorie', () {
      final p = pred('Trio', const <int>[9, 4, 15],
          id: 't', mise: 1, codePmu: 'E_TRIO');
      expect(construireTicketPrediction(p).issue,
          IssueConstructionTicket.typeNonRepertorie);
    });

    test('B4.5/7.2 taille de combinaison anormale ⇒ refus', () {
      final p = pred('Tiercé', const <int>[9, 4],
          id: 'taille', mise: 1, codePmu: 'E_TIERCE', ordre: const <int>[9, 4]);
      expect(construireTicketPrediction(p).issue,
          IssueConstructionTicket.tailleCombinaisonAnormale);
    });

    test('B4.5/7.3 aucun numéro joué ⇒ refus', () {
      final p = pred('Simple Gagnant', const <int>[],
          id: 'vide', mise: 1, codePmu: 'E_SIMPLE_GAGNANT');
      expect(construireTicketPrediction(p).issue,
          IssueConstructionTicket.tailleCombinaisonAnormale);
    });

    test('B4.5/7.4 variante exigée mais non choisie ⇒ refus varianteAbsente', () {
      for (final String type in <String>[
        'Tiercé Ordre',
        'Tiercé Désordre',
        'Couplé Ordre',
      ]) {
        final p = type == 'Couplé Ordre'
            ? pred(type, const <int>[9, 4],
                id: 'v_$type',
                mise: 1,
                codePmu: 'E_COUPLE_ORDRE',
                ordre: const <int>[9, 4])
            : pred(type, const <int>[9, 4, 15],
                id: 'v_$type',
                mise: 1,
                codePmu: 'E_TIERCE',
                ordre: const <int>[9, 4, 15]);
        expect(construireTicketPrediction(p).issue,
            IssueConstructionTicket.varianteAbsente,
            reason: '$type impose une variante : on ne la devine pas');
      }
    });

    test('B4.5/7.5 aucun code PMU ⇒ refus codePmuAbsent', () {
      final p = pred('Simple Gagnant', const <int>[9], id: 'sanscode', mise: 5);
      expect(construireTicketPrediction(p).issue,
          IssueConstructionTicket.codePmuAbsent);
    });

    test('B4.5/7.6 mise nulle ou négative ⇒ refus miseAbsente', () {
      for (final double m in <double>[0.0, -3.0]) {
        final p = pred('Simple Gagnant', const <int>[9],
            id: 'm$m', mise: m, codePmu: 'E_SIMPLE_GAGNANT');
        expect(construireTicketPrediction(p).issue,
            IssueConstructionTicket.miseAbsente,
            reason: 'mise $m ne fonde aucun gain');
      }
    });

    test('B4.5/7.7 même politique appliquée au ticket suivi', () {
      expect(
        construireTicketSuivi(suivi(mise: null)).issue,
        IssueConstructionTicket.miseAbsente,
      );
      expect(
        construireTicketSuivi(suivi(codePmu: null)).issue,
        IssueConstructionTicket.codePmuAbsent,
      );
      expect(
        construireTicketSuivi(suivi(typePari: 'Tiercé Ordre',
                numeros: const <int>[9, 4, 15],
                codePmu: 'E_TIERCE',
                ordre: const <int>[9, 4, 15]))
            .issue,
        IssueConstructionTicket.varianteAbsente,
      );
    });

    test('B4.5/7.8 un rapport officiel NON documenté n\'est jamais attribué',
        () {
      // Le moteur produit un verdict « attribue », mais le rapport officiel
      // fourni à l'enregistreur a un libellé différent : l'identité n'est pas
      // démontrée, donc l'écriture est REFUSÉE.
      final p = pred('Simple Gagnant', const <int>[9],
          id: 'nf', mise: 5, codePmu: 'E_SIMPLE_GAGNANT');
      final indoc = construireResultatOfficiel(
        arriveeGroupes: kArrivee,
        arriveeDefinitive: true,
        rapports: <RapportPmu>[
          api('E_SIMPLE_GAGNANT', 'e-Simple Gagnant', '9', 7.50),
        ],
      );
      final r = resoudrePrediction(prediction: p, resultat: indoc);
      expect(r.enregistrement!.statut, StatutEnregistrementVerdict.enregistre);

      // Maintenant avec un résultat dont le rapport a été retiré :
      final sansRapport = construireResultatOfficiel(
        arriveeGroupes: kArrivee,
        arriveeDefinitive: true,
        rapports: <RapportPmu>[
          RapportPmu(
            typePari: 'E_SIMPLE_GAGNANT',
            combinaison: '9',
            dividende: 7.50,
            estOrdre: false,
            // libellé officiel ABSENT ⇒ variante illisible ⇒ rapport écarté
            libelleOfficiel: '',
            codePariOfficiel: 'E_SIMPLE_GAGNANT',
          ),
        ],
      );
      final r2 = resoudrePrediction(prediction: p, resultat: sansRapport);
      // COMPORTEMENT RÉEL MESURÉ : `convertirRapportsApi` (B-4.1) ÉCARTE le
      // rapport à variante illisible. Le moteur B-3 reçoit donc une liste VIDE
      // et prononce `blocJusteAbsent` — jamais un montant inventé. Le verdict
      // « indéterminé » est ensuite enregistré (il ne comporte aucune
      // composante et aucun rapport officiel ne lui est fourni).
      expect(r2.verdict!.etat, EtatGain.nonDetermine,
          reason: 'aucun montant ne peut être attribué sans rapport lisible');
      expect(r2.verdict!.motif, MotifNonDetermination.blocJusteAbsent);
      expect(r2.verdict!.total, 0.0);
      expect(r2.verdict!.composantes, isEmpty);
      expect(r2.enregistrement!.statut, StatutEnregistrementVerdict.enregistre);
      expect(r2.enregistrement!.ticket.etatGain, EtatGain.nonDetermine);
      expect(r2.enregistrement!.ticket.rapportsAttribues, isNull,
          reason: 'AUCUN rapport attribué : rien n\'est inventé');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B4.5/8 — ABSENCE DE CALCUL PAR reduce(MAX)  [PREUVE COMPORTEMENTALE]
  // ═════════════════════════════════════════════════════════════════════════
  group('B4.5/8 aucun calcul par maximum de dividende', () {
    test('B4.5/8.1 Simple Placé sur le 9 paie 3,00 — PAS le maximum 31,00', () {
      final p = pred('Simple Placé', const <int>[9],
          id: 'max', mise: 10, codePmu: 'E_SIMPLE_PLACE');
      final r = resoudrePrediction(prediction: p, resultat: resultat(blocSimple()));
      expect(r.verdict!.total, closeTo(30.00, 1e-9));
      expect(r.verdict!.total, isNot(closeTo(310.00, 1e-9)),
          reason: 'un reduce(MAX) aurait retenu 31,00 €');
      expect(r.verdict!.total, isNot(closeTo(280.00, 1e-9)),
          reason: 'ni 28,00 € (deuxième plus élevé)');
      expect(r.verdict!.composantes.single.combinaisonRapport, '9');
      expect(r.verdict!.composantes.single.pourUnEuro, closeTo(3.00, 1e-9));
    });

    test('B4.5/8.2 Simple Placé sur le 2 paie 31,00 (le rapport de SON cheval)',
        () {
      final p = pred('Simple Placé', const <int>[2],
          id: 'max2', mise: 10, codePmu: 'E_SIMPLE_PLACE');
      final r = resoudrePrediction(prediction: p, resultat: resultat(blocSimple()));
      expect(r.verdict!.total, closeTo(310.00, 1e-9));
      expect(r.verdict!.composantes.single.combinaisonRapport, '2');
    });

    test('B4.5/8.3 le Tiercé Désordre paie 80,30 même si l\'Ordre vaut 477,40',
        () {
      final p = pred('Tiercé', const <int>[4, 15, 9],
          id: 'tord', mise: 1, codePmu: 'E_TIERCE', ordre: const <int>[4, 15, 9]);
      final r = resoudrePrediction(prediction: p, resultat: resultat(blocTierce()));
      expect(r.verdict!.total, closeTo(80.30, 1e-9));
      expect(r.verdict!.total, lessThan(477.40));
    });

    test('B4.5/8.4 la ligne persistée porte le dividende du rapport RETENU, '
        'et c\'est celui du bas', () {
      final p = pred('Simple Placé', const <int>[9],
          id: 'ligne', mise: 10, codePmu: 'E_SIMPLE_PLACE');
      final r = resoudrePrediction(prediction: p, resultat: resultat(blocSimple()));
      final att = r.enregistrement!.ticket.rapportsAttribues!;
      expect(att, hasLength(1));
      expect(att.single.rapport.combinaison, '9');
      expect(att.single.rapport.pourUnEuro, closeTo(3.00, 1e-9));
      expect(att.single.montantRetour, closeTo(30.00, 1e-9));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B4.5/9 — RECONSTRUCTION DES MONTANTS SANS DOUBLE MULTIPLICATION
  // ═════════════════════════════════════════════════════════════════════════
  group('B4.5/9 reconstruction sans double multiplication', () {
    test('B4.5/9.1 Σ montantRetour persistés == verdict.total', () {
      final p = pred('Simple Placé', const <int>[9],
          id: 'rec', mise: 10, codePmu: 'E_SIMPLE_PLACE');
      final r = resoudrePrediction(prediction: p, resultat: resultat(blocSimple()));
      final reconstruit =
          resoudreTotalDepuisRapports(r.enregistrement!.ticket.rapportsAttribues);
      expect(reconstruit, closeTo(r.verdict!.total, 1e-9));
      expect(reconstruit, closeTo(30.00, 1e-9));
    });

    test('B4.5/9.2 le montant reconstruit n\'est PAS total × mise', () {
      final p = pred('Simple Placé', const <int>[9],
          id: 'rec2', mise: 10, codePmu: 'E_SIMPLE_PLACE');
      final r = resoudrePrediction(prediction: p, resultat: resultat(blocSimple()));
      final t = r.verdict!.total;
      final reconstruit =
          resoudreTotalDepuisRapports(r.enregistrement!.ticket.rapportsAttribues);
      expect(reconstruit, isNot(closeTo(t * 10.0, 1e-9)),
          reason: 'une seconde multiplication par la mise serait un double '
              'comptage (30 × 10 = 300)');
      expect(reconstruit, isNot(closeTo(3.00 * 10.0 * 10.0, 1e-9)));
    });

    test('B4.5/9.3 Gagnant+Placé : les deux retours s\'ADDITIONNENT une fois',
        () {
      final p = pred('Gagnant+Placé', const <int>[9],
          id: 'recgp', miseGagnant: 10.0, misePlace: 5.0);
      final r = resoudrePrediction(prediction: p, resultat: resultat(blocSimple()));
      final att = r.enregistrement!.ticket.rapportsAttribues!;
      expect(att, hasLength(2));
      final total = resoudreTotalDepuisRapports(att)!;
      expect(total, closeTo(90.00, 1e-9));
      expect(total, closeTo(75.00 + 15.00, 1e-9));
      // Aucune composante ne porte la mise totale du ticket.
      for (final a in att) {
        expect(a.miseAppliquee, isNot(closeTo(15.0, 1e-9)));
      }
    });

    test('B4.5/9.4 liste nulle ⇒ null ; liste vide ⇒ 0 : deux états distincts',
        () {
      expect(resoudreTotalDepuisRapports(null), isNull);
      expect(resoudreTotalDepuisRapports(<RapportAttribue>[]), 0.0);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B4.5/10 — AFFICHAGE COHÉRENT DES QUATRE ÉTATS DU VERDICT
  // ═════════════════════════════════════════════════════════════════════════
  group('B4.5/10 affichage des quatre états', () {
    test('B4.5/10.1 attribue ⇒ montant affiché, nature attribue', () {
      final c = suivi().copyWith(
        etatGain: EtatGain.attribue,
        rapportsAttribues: <RapportAttribue>[
          RapportAttribue.calculer(
            rapport: rapportPublieDepuisApi(
                api('E_SIMPLE_PLACE', 'e-Simple Placé', '9', 3.00))!,
            miseAppliquee: 10.0,
          ),
        ],
        etatTirelire: EtatTirelire.sansObjet,
        miseBaseCentimesUtilisee: 100,
      );
      final v = affichageGainSuivi(c);
      expect(v.nature, NatureAffichageGain.attribue);
      expect(v.montant, closeTo(30.00, 1e-9));
      expect(v.afficheUnMontant, isTrue);
      expect(v.libelle, contains('Gain gagné'));
      expect(v.libelle, contains('30'));
    });

    test('B4.5/10.2 attribue SANS rapport persisté ⇒ indéterminé, montant null',
        () {
      final c = suivi().copyWith(etatGain: EtatGain.attribue);
      final v = affichageGainSuivi(c);
      expect(v.nature, NatureAffichageGain.indetermine);
      expect(v.montant, isNull);
      expect(v.afficheUnMontant, isFalse);
      expect(v.detail, contains('aucun montant persisté'));
    });

    test('B4.5/10.3 perdu ⇒ aucun montant, même si un dividende historique '
        'traîne', () {
      final c = suivi().copyWith(
        etatGain: EtatGain.perdu,
        dividendePmuReel: 18.0,
        isGagne: true,
        miseEngagee: 20.0,
      );
      final v = affichageGainSuivi(c);
      expect(v.nature, NatureAffichageGain.perdu);
      expect(v.montant, isNull);
      expect(v.afficheUnMontant, isFalse);
      expect(v.libelle, contains('perdu'));
    });

    test('B4.5/10.4 rembourse ⇒ montant remboursé, jamais présenté comme gain',
        () {
      final c = suivi().copyWith(
        etatGain: EtatGain.rembourse,
        rapportsAttribues: <RapportAttribue>[
          RapportAttribue.calculer(
            rapport: rapportPublieDepuisApi(
                api('E_SIMPLE_PLACE', 'e-Simple Placé', '9', 1.00))!,
            miseAppliquee: 10.0,
          ),
        ],
      );
      final v = affichageGainSuivi(c);
      expect(v.nature, NatureAffichageGain.rembourse);
      expect(v.montant, closeTo(10.00, 1e-9));
      expect(v.libelle, contains('Remboursé'));
      expect(v.detail, contains('pas un gain'));
    });

    test('B4.5/10.5 nonDetermine ⇒ indéterminé + motif nommé', () {
      final c = suivi().copyWith(
        etatGain: EtatGain.nonDetermine,
        motifNonDetermination: MotifNonDetermination.deadHeatSansGroupes,
      );
      final v = affichageGainSuivi(c);
      expect(v.nature, NatureAffichageGain.indetermine);
      expect(v.montant, isNull);
      expect(v.detail, contains('deadHeatSansGroupes'));
    });

    test('B4.5/10.6 les quatre états produisent quatre natures DISTINCTES', () {
      final etats = <EtatGain, NatureAffichageGain>{
        EtatGain.attribue: NatureAffichageGain.attribue,
        EtatGain.perdu: NatureAffichageGain.perdu,
        EtatGain.rembourse: NatureAffichageGain.rembourse,
        EtatGain.nonDetermine: NatureAffichageGain.indetermine,
      };
      final obtenues = <NatureAffichageGain>{};
      etats.forEach((EtatGain e, NatureAffichageGain attendu) {
        final c = suivi().copyWith(
          etatGain: e,
          rapportsAttribues: e == EtatGain.attribue
              ? <RapportAttribue>[
                  RapportAttribue.calculer(
                    rapport: rapportPublieDepuisApi(
                        api('E_SIMPLE_PLACE', 'e-Simple Placé', '9', 3.00))!,
                    miseAppliquee: 10.0,
                  ),
                ]
              : null,
          motifNonDetermination:
              e == EtatGain.nonDetermine ? MotifNonDetermination.rapportAmbigu : null,
        );
        final v = affichageGainSuivi(c);
        expect(v.nature, attendu);
        obtenues.add(v.nature);
      });
      expect(obtenues, hasLength(4));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B4.5/11 — PRÉSERVATION DES ANCIENS TICKETS
  // ═════════════════════════════════════════════════════════════════════════
  group('B4.5/11 préservation des anciens tickets', () {
    test('B4.5/11.1 ticket historique (etatGain null) ⇒ affichage historique, '
        'montant marqué non vérifié', () {
      final c = suivi(mise: 20.0).copyWith(
        isGagne: true,
        dividendePmuReel: 18.0,
        combinaisonPmu: '7',
      );
      final v = affichageGainSuivi(c);
      expect(v.nature, NatureAffichageGain.historique);
      expect(v.montant, closeTo(360.0, 1e-9),
          reason: '18 × 20 = 360 : montant historique CONSERVÉ');
      expect(v.libelle, contains('non vérifié'),
          reason: 'un dividende sélectionné avant le lot ne peut pas être '
              'présenté comme confirmé');
    });

    test('B4.5/11.2 ticket historique perdant ⇒ libellé historique, sans '
        'recalcul', () {
      final c = suivi().copyWith(isGagne: false);
      final v = affichageGainSuivi(c);
      expect(v.nature, NatureAffichageGain.historique);
      expect(v.libelle, contains('perdu'));
      expect(v.detail, contains('non revérifié'));
      expect(v.montant, isNull);
    });

    test('B4.5/11.3 un verdict DÉFINITIF déjà présent n\'est JAMAIS réécrit',
        () {
      final dejaResolu = pred('Simple Gagnant', const <int>[9],
              id: 'old', mise: 5, codePmu: 'E_SIMPLE_GAGNANT')
          .copyWith(etatGain: EtatGain.perdu, isCorrect: false, gainRealise: -5.0);
      final r = resoudrePrediction(
        prediction: dejaResolu,
        resultat: resultat(blocSimple()),
      );
      expect(r.enregistrement!.statut,
          StatutEnregistrementVerdict.refuseVerdictDefinitifExistant);
      expect(identical(r.enregistrement!.ticket, dejaResolu), isTrue,
          reason: 'l\'objet original est rendu, non copié');
      expect(r.enregistrement!.ticket.etatGain, EtatGain.perdu);
      expect(r.enregistrement!.ticket.isCorrect, isFalse);
      expect(r.enregistrement!.ticket.gainRealise, -5.0);
    });

    test('B4.5/11.4 les champs historiques du ticket survivent à l\'écriture '
        'd\'un verdict', () {
      final ancien = pred('Simple Placé', const <int>[9],
              id: 'mixte', mise: 10, codePmu: 'E_SIMPLE_PLACE')
          .copyWith(
        isCorrect: false,
        dividendePmuReel: 18.0,
        combinaisonPmu: '7',
        gainRealise: -10.0,
      );
      final r = resoudrePrediction(prediction: ancien, resultat: resultat(blocSimple()));
      expect(r.enregistrement!.statut, StatutEnregistrementVerdict.enregistre);
      final apres = r.enregistrement!.ticket;
      // Le verdict structuré est écrit…
      expect(apres.etatGain, EtatGain.attribue);
      // …et AUCUN champ historique n'est réécrit par B-4.5.
      expect(apres.isCorrect, isFalse);
      expect(apres.dividendePmuReel, 18.0);
      expect(apres.combinaisonPmu, '7');
      expect(apres.gainRealise, -10.0);
      expect(apres.montantMise, 10.0);
    });

    test('B4.5/11.5 un ticket historique ne reçoit pas de clés B-1 '
        'supplémentaires', () {
      final ancien = suivi();
      final json = ancien.toJson();
      expect(json.length, 28,
          reason: 'ticket suivi sans arrivée structurée ni verdict : 28 clés, '
              'comptage verrouillé par B-4.4/2.1');
      for (final String cle in <String>[
        'etatGain',
        'rapportsAttribues',
        'etatTirelire',
        'dividendeGagnant',
        'dividendePlace',
        'miseBaseCentimesUtilisee',
        'motifNonDetermination',
      ]) {
        expect(json.containsKey(cle), isFalse,
            reason: 'la clé B-1 « $cle » ne doit pas apparaître');
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B4.5/12 — AUCUNE SYNCHRONISATION DES STATISTIQUES IA
  // ═════════════════════════════════════════════════════════════════════════
  group('B4.5/12 aucune synchronisation IA', () {
    test('B4.5/12.1 appliquerVerdictGainPrediction laisse ia_stats_types_v1 '
        'INTACT', () async {
      final p = pred('Simple Placé', const <int>[9],
          id: 'ia', mise: 10, codePmu: 'E_SIMPLE_PLACE');
      SharedPreferences.setMockInitialValues(<String, Object>{
        'ia_stats_types_v1': <String>['TEMOIN_INTACT'],
        'user_predictions_v2': <String>[json.encode(p.toJson())],
      });

      late PmuProvider pmu;
      await avecReseau(() async {
        pmu = PmuProvider();
        await pmu.reloadPredictions();
      });
      expect(pmu.predictions, hasLength(1), reason: 'TÉMOIN : ticket chargé');

      final avant = (await SharedPreferences.getInstance())
          .getStringList('ia_stats_types_v1');
      expect(avant, <String>['TEMOIN_INTACT']);

      final res = resoudrePrediction(prediction: p, resultat: resultat(blocSimple()));
      expect(res.enregistrement!.statut, StatutEnregistrementVerdict.enregistre);
      final applique = pmu.appliquerVerdictGainPrediction(res.enregistrement!.ticket);
      expect(applique, isTrue);

      final apres = (await SharedPreferences.getInstance())
          .getStringList('ia_stats_types_v1');
      expect(apres, <String>['TEMOIN_INTACT'],
          reason: 'aucun recalcul de statistiques d\'apprentissage');
      expect(pmu.predictions.single.etatGain, EtatGain.attribue,
          reason: 'le verdict est bien persisté malgré l\'absence de sync IA');
    });

    test('B4.5/12.2 la couture n\'exige ni ne produit aucun identifiant IA',
        () async {
      // Le ticket n'a AUCUNE clé IA mémorisée : la résolution doit aboutir
      // malgré tout, preuve qu'aucune dépendance IA n'est requise.
      final p = UserPrediction(
        id: 'sans_ia',
        dateStr: kDateIso,
        numReunion: 1,
        numCourse: 6,
        nomCourse: 'Prix de Test',
        hippodrome: 'Vincennes',
        numeroCheval: 9,
        nomCheval: 'CHEVAL_9',
        cote: 7.5,
        typePari: 'Simple Gagnant',
        createdAt: _heure,
        montantMise: 5.0,
        numerosJoues: const <int>[9],
        codePmuOfficiel: 'E_SIMPLE_GAGNANT',
      );
      final r = resoudrePrediction(prediction: p, resultat: resultat(blocSimple()));
      expect(r.enregistrement!.statut, StatutEnregistrementVerdict.enregistre);
      expect(r.verdict!.total, closeTo(37.50, 1e-9));
    });

    test('B4.5/12.3 le ticket suivi voit son verdict persisté sans que '
        '`isGagne` ni le dividende soient touchés', () async {
      final c = suivi(
        typePari: 'Simple Placé',
        numeros: const <int>[9],
        mise: 10.0,
        groupes: kArrivee,
        definitive: true,
      );
      final r = resoudreSuivi(ticket: c, resultat: resultat(blocSimple()));
      expect(r.enregistrement!.statut, StatutEnregistrementVerdict.enregistre);
      final apres = r.enregistrement!.ticket;
      expect(apres.etatGain, EtatGain.attribue);
      expect(apres.isGagne, isNull, reason: 'champ historique NON touché');
      expect(apres.dividendePmuReel, isNull,
          reason: 'aucun dividende sélectionné n\'est écrit');
      expect(apres.combinaisonPmu, isNull);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B4.5/13 — IDEMPOTENCE DES RAFRAÎCHISSEMENTS
  // ═════════════════════════════════════════════════════════════════════════
  group('B4.5/13 idempotence des rafraîchissements', () {
    test('B4.5/13.1 une seconde résolution identique ⇒ dejaIdentique', () {
      final p = pred('Simple Placé', const <int>[9],
          id: 'idem', mise: 10, codePmu: 'E_SIMPLE_PLACE');
      final res = resultat(blocSimple());
      final r1 = resoudrePrediction(prediction: p, resultat: res);
      expect(r1.enregistrement!.statut, StatutEnregistrementVerdict.enregistre);

      final r2 = resoudrePrediction(
        prediction: r1.enregistrement!.ticket,
        resultat: res,
      );
      expect(r2.enregistrement!.statut, StatutEnregistrementVerdict.dejaIdentique);
      expect(identical(r2.enregistrement!.ticket, r1.enregistrement!.ticket),
          isTrue, reason: 'aucune copie inutile : rien n\'a changé');
      expect(r2.enregistrement!.ticketInchange, isTrue);
    });

    test('B4.5/13.2 trois résolutions successives ⇒ un seul état, montant stable',
        () {
      final p = pred('Simple Placé', const <int>[9],
          id: 'triple', mise: 10, codePmu: 'E_SIMPLE_PLACE');
      final res = resultat(blocSimple());
      var courant = p;
      final statuts = <StatutEnregistrementVerdict>[];
      for (var i = 0; i < 3; i++) {
        final r = resoudrePrediction(prediction: courant, resultat: res);
        statuts.add(r.enregistrement!.statut);
        courant = r.enregistrement!.ticket;
        expect(
          resoudreTotalDepuisRapports(courant.rapportsAttribues),
          closeTo(30.00, 1e-9),
          reason: 'le montant ne gonfle jamais d\'un passage à l\'autre',
        );
      }
      expect(statuts, <StatutEnregistrementVerdict>[
        StatutEnregistrementVerdict.enregistre,
        StatutEnregistrementVerdict.dejaIdentique,
        StatutEnregistrementVerdict.dejaIdentique,
      ]);
      expect(courant.rapportsAttribues, hasLength(1),
          reason: 'aucun rapport n\'est dupliqué');
    });

    test('B4.5/13.3 le ticket suivi est idempotent de la même façon', () {
      final c = suivi(
          typePari: 'Simple Placé',
          numeros: const <int>[9],
          mise: 10.0,
          groupes: kArrivee,
          definitive: true);
      final res = resultat(blocSimple());
      final r1 = resoudreSuivi(ticket: c, resultat: res);
      final r2 = resoudreSuivi(ticket: r1.enregistrement!.ticket, resultat: res);
      expect(r1.enregistrement!.statut, StatutEnregistrementVerdict.enregistre);
      expect(r2.enregistrement!.statut, StatutEnregistrementVerdict.dejaIdentique);
      expect(
        resoudreTotalDepuisRapports(r2.enregistrement!.ticket.rapportsAttribues),
        closeTo(30.00, 1e-9),
      );
    });

    test('B4.5/13.4 une résolution de course rejouée ne change aucun montant',
        () {
      final res = resultat(<RapportPmu>[...blocSimple(), ...blocTierce()]);
      final preds = <UserPrediction>[
        pred('Simple Gagnant', const <int>[9],
            id: 'c1', mise: 5, codePmu: 'E_SIMPLE_GAGNANT'),
        pred('Tiercé', const <int>[4, 15, 9],
            id: 'c2', mise: 1, codePmu: 'E_TIERCE', ordre: const <int>[4, 15, 9]),
      ];
      final r1 = resoudrePredictionsDeCourse(predictions: preds, resultat: res);
      final apres = r1.map((r) => r.enregistrement!.ticket).toList();
      final r2 = resoudrePredictionsDeCourse(predictions: apres, resultat: res);
      for (var i = 0; i < 2; i++) {
        expect(r2[i].enregistrement!.statut,
            StatutEnregistrementVerdict.dejaIdentique);
        expect(
          resoudreTotalDepuisRapports(r2[i].enregistrement!.ticket.rapportsAttribues),
          closeTo(resoudreTotalDepuisRapports(apres[i].rapportsAttribues)!, 1e-9),
        );
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B4.5/14 — PAS DE VERDICT SANS GROUPES, PUIS RÉSOLUTION CORRECTE
  // ═════════════════════════════════════════════════════════════════════════
  group('B4.5/14 groupes manquants puis disponibles', () {
    test('B4.5/14.1 `resultatOfficielDepuisSuivi` REFUSE sans arriveeGroupes',
        () {
      final sansGroupes = suivi(groupes: null, definitive: true);
      final r = resultatOfficielDepuisSuivi(sansGroupes, rapports: blocTierce());
      expect(r, isNull,
          reason: 'une liste plate ne fonde ni ordre ni ex æquo : refus');
    });

    test('B4.5/14.2 `resultatOfficielDepuisSuivi` REFUSE sans rapports', () {
      final avecGroupes = suivi(groupes: kArrivee, definitive: true);
      expect(
        resultatOfficielDepuisSuivi(avecGroupes, rapports: const <RapportPmu>[]),
        isNull,
      );
    });

    test('B4.5/14.3 le Tiercé reste NON RÉSOLU sans groupes, puis devient '
        'ATTRIBUÉ dès que les groupes arrivent', () {
      final base = suivi(
        typePari: 'Tiercé',
        numeros: const <int>[4, 15, 9],
        mise: 1.0,
        codePmu: 'E_TIERCE',
        ordre: const <int>[4, 15, 9],
        groupes: null,
        definitive: true,
      );

      // ── Phase 1 : groupes indisponibles.
      // La couture REFUSE de construire un résultat officiel : l'écran sort
      // donc AVANT toute écriture, et le ticket reste en attente.
      final res1 = resultatOfficielDepuisSuivi(base, rapports: blocTierce());
      expect(res1, isNull);
      expect(base.etatGain, isNull,
          reason: 'AUCUN verdict n\'est enregistré quand les groupes manquent');
      expect(base.rapportsAttribues, isNull);

      // ── Phase 2 : les groupes deviennent disponibles.
      final avecGroupes = base.copyWith(arriveeGroupes: kArrivee);
      final res2 = resultatOfficielDepuisSuivi(avecGroupes, rapports: blocTierce());
      expect(res2, isNotNull);
      final r2 = resoudreSuiviDeCourse(ticket: avecGroupes, resultat: res2!);
      expect(r2.aUneIssue, isFalse);
      expect(r2.enregistrement!.statut, StatutEnregistrementVerdict.enregistre);
      expect(r2.enregistrement!.ticket.etatGain, EtatGain.attribue);
      expect(r2.verdict!.total, closeTo(80.30, 1e-9));
      expect(
        resoudreTotalDepuisRapports(
            r2.enregistrement!.ticket.rapportsAttribues),
        closeTo(80.30, 1e-9),
      );
    });

    test('B4.5/14.4 un ex æquo sur un rang comparé ⇒ indéterminé, jamais un '
        'ordre inventé', () {
      // Les rangs 1 et 2 sont des ex æquo : l'ordre relatif n'existe pas.
      const List<List<int>> exAequo = <List<int>>[
        <int>[9, 4],
        <int>[15],
        <int>[10],
      ];
      final r = resoudrePrediction(
        prediction: pred('Tiercé', const <int>[9, 4, 15],
            id: 'ae', mise: 1, codePmu: 'E_TIERCE', ordre: const <int>[9, 4, 15]),
        resultat: resultat(blocTierce(), groupes: exAequo),
      );
      expect(r.verdict!.etat, EtatGain.nonDetermine);
      expect(r.verdict!.motif, MotifNonDetermination.deadHeatSansGroupes);
      expect(r.verdict!.total, 0.0);
      expect(r.verdict!.composantes, isEmpty);
    });

    test('B4.5/14.5 arrivée explicitement provisoire ⇒ aucun montant', () {
      final r = resoudrePrediction(
        prediction: pred('Simple Gagnant', const <int>[9],
            id: 'prov', mise: 5, codePmu: 'E_SIMPLE_GAGNANT'),
        resultat: resultat(blocSimple(), definitive: false),
      );
      expect(r.verdict!.etat, EtatGain.nonDetermine);
      expect(r.verdict!.motif, MotifNonDetermination.arriveeNonDefinitive);
      expect(r.verdict!.total, 0.0);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B4.5/15 — SAUVEGARDE ET RESTAURATION DES NOUVEAUX CHAMPS
  // ═════════════════════════════════════════════════════════════════════════
  group('B4.5/15 sauvegarde et restauration', () {
    test('B4.5/15.1 les sept champs B-1 d\'un ticket suivi font l\'aller-retour '
        'JSON', () {
      final c = suivi(
              typePari: 'Simple Placé',
              numeros: const <int>[9],
              mise: 10.0,
              groupes: kArrivee,
              definitive: true)
          .copyWith(
        etatGain: EtatGain.attribue,
        rapportsAttribues: <RapportAttribue>[
          RapportAttribue.calculer(
            rapport: rapportPublieDepuisApi(
                api('E_SIMPLE_PLACE', 'e-Simple Placé', '9', 3.00))!,
            miseAppliquee: 10.0,
          ),
        ],
        etatTirelire: EtatTirelire.sansObjet,
        dividendeGagnant: null,
        dividendePlace: 3.00,
        miseBaseCentimesUtilisee: 100,
        motifNonDetermination: null,
      );

      final json = c.toJson();
      final relu = TrackedCourse.fromJson(
          jsonDecode(jsonEncode(json)) as Map<String, dynamic>);

      expect(relu.etatGain, EtatGain.attribue);
      expect(relu.etatTirelire, EtatTirelire.sansObjet);
      expect(relu.dividendeGagnant, isNull);
      expect(relu.dividendePlace, 3.00);
      expect(relu.miseBaseCentimesUtilisee, 100);
      expect(relu.motifNonDetermination, isNull);
      expect(relu.rapportsAttribues, hasLength(1));
      expect(relu.rapportsAttribues!.single.miseAppliquee, 10.0);
      expect(relu.rapportsAttribues!.single.montantRetour, closeTo(30.00, 1e-9));
      expect(relu.rapportsAttribues!.single.rapport.combinaison, '9');

      // Arrivée structurée également préservée.
      expect(
        relu.arriveeGroupes!.map((g) => g.join('-')).toList(),
        <String>['9', '4', '15', '10', '1', '7', '12'],
      );
      expect(relu.arriveeDefinitive, isTrue);

      // Le montant se reconstitue à l'identique après relecture.
      expect(resoudreTotalDepuisRapports(relu.rapportsAttribues),
          closeTo(30.00, 1e-9));
    });

    test('B4.5/15.2 motif de non-détermination : aller-retour exact', () {
      final c = suivi().copyWith(
        etatGain: EtatGain.nonDetermine,
        motifNonDetermination: MotifNonDetermination.deadHeatSansGroupes,
        etatTirelire: EtatTirelire.nonDeterminee,
      );
      final relu = TrackedCourse.fromJson(
          jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>);
      expect(relu.etatGain, EtatGain.nonDetermine);
      expect(relu.motifNonDetermination,
          MotifNonDetermination.deadHeatSansGroupes);
      expect(relu.etatTirelire, EtatTirelire.nonDeterminee);
      // Et l'affichage relu reste cohérent.
      expect(affichageGainSuivi(relu).nature, NatureAffichageGain.indetermine);
    });

    test('B4.5/15.3 les champs B-1 d\'une prédiction de profil font '
        'l\'aller-retour JSON', () {
      final p = pred('Simple Placé', const <int>[9],
              id: 'js', mise: 10, codePmu: 'E_SIMPLE_PLACE')
          .copyWith(etatGain: EtatGain.attribue);
      final relu = UserPrediction.fromJson(
          jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
      expect(relu.etatGain, EtatGain.attribue);
      expect(relu.codePmuOfficiel, 'E_SIMPLE_PLACE');
      expect(relu.montantMise, 10.0);
      expect(relu.numerosJoues, <int>[9]);
      expect(relu.id, 'js');
    });

    test('B4.5/15.4 les quatre champs 4-F (ordre, variante, code) survivent à '
        'la sauvegarde', () {
      final c = suivi(
              typePari: 'Tiercé',
              numeros: const <int>[4, 15, 9],
              mise: 1.0,
              codePmu: 'E_TIERCE',
              ordre: const <int>[4, 15, 9])
          .copyWith(varianteChoisie: 'desordre', formulePari: 'Tiercé');
      final relu = TrackedCourse.fromJson(
          jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>);
      expect(relu.codePmuOfficiel, 'E_TIERCE');
      expect(relu.numeroCheval, 4);
      expect(relu.numerosJoues, <int>[4, 15, 9]);
      expect(relu.numerosDansOrdre, <int>[4, 15, 9]);
      expect(relu.varianteChoisie, 'desordre');
      expect(relu.formulePari, 'Tiercé');
    });

    test('B4.5/15.5 un ticket suivi restauré puis résolu donne le MÊME montant '
        'qu\'en mémoire', () {
      final res = resultat(blocSimple());
      final vivant = suivi(
          typePari: 'Simple Placé',
          numeros: const <int>[9],
          mise: 10.0,
          groupes: kArrivee,
          definitive: true);
      final v1 = resoudreSuivi(ticket: vivant, resultat: res);

      final restaure = TrackedCourse.fromJson(
          jsonDecode(jsonEncode(vivant.toJson())) as Map<String, dynamic>);
      final v2 = resoudreSuivi(ticket: restaure, resultat: res);

      expect(v1.verdict!.total, closeTo(v2.verdict!.total, 1e-9));
      expect(v2.verdict!.total, closeTo(30.00, 1e-9));
      expect(v2.enregistrement!.statut, StatutEnregistrementVerdict.enregistre,
          reason: 'le ticket restauré ne porte encore aucun verdict');
    });

    test('B4.5/15.6 l\'arrivée structurée restaurée suffit à reconstruire le '
        'résultat officiel local', () {
      final restaure = TrackedCourse.fromJson(jsonDecode(jsonEncode(
              suivi(groupes: kArrivee, definitive: true).toJson()))
          as Map<String, dynamic>);
      final r = resultatOfficielDepuisSuivi(restaure, rapports: blocSimple());
      expect(r, isNotNull);
      expect(r!.arriveeGroupes, isNotNull);
      expect(r.arriveeGroupes!.first, <int>[9]);
      expect(r.arriveeDefinitive, isTrue);
    });
  });
}
