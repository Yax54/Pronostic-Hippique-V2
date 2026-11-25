// ═══════════════════════════════════════════════════════════════════════════
//  BLOC 1 — PÉRIMÈTRE FINANCIER : PERSISTANCE + CHAÎNE OFFICIELLE UNIQUE
//
//  CE QUE CE FICHIER PROUVE
//  ────────────────────────────────────────────────────────────────────────
//  Il ne fabrique PAS une ancre correcte à la main. Il part du VÉRITABLE
//  producteur de données — `PmuApiService.fetchRapportsDefinitifs` et
//  `ZoneTurfService.chargerResultatsCourseComplet`, tous deux interceptés au
//  niveau HTTP par `http.runWithClient` + `MockClient`, exactement comme la
//  production les appelle — et il va jusqu'au CONSOMMATEUR financier, le
//  moteur officiel `resoudreGainTicketDepuisDonnees`, en passant par la
//  persistance partagée. C'est l'exigence §4 du mandat :
//
//    « Complète les tests existants par un test couvrant le véritable
//      producteur de données jusqu'au consommateur IA. Un test qui fabrique
//      directement une ancre correcte ne suffit pas. »
//
//  CE QU'IL NE PROUVE PAS — DIT HONNÊTEMENT
//  ────────────────────────────────────────────────────────────────────────
//   • Rien sur un appareil réel : tout est exécuté sur la VM Dart.
//   • Rien sur le réseau PMU réel : les réponses sont des fixtures au FORMAT
//     REÇU (mesuré sur les captures), pas des réponses live.
//   • Rien sur l'apprentissage : ce fichier ne le déclenche pas, et ne
//     prétend donc pas le vérifier au-delà de l'absence d'import.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/services/chaine_financiere_officielle.dart';
import 'package:pronostic_hippique/services/gain_calculator.dart'
    show RapportPmu;
import 'package:pronostic_hippique/services/resultat_officiel_repository.dart';
import 'package:pronostic_hippique/services/zone_turf_service.dart';

// ─────────────────────────── Constantes de scénario ─────────────────────────

/// Date de la course : 15 novembre 2026 (date réelle, pas un sentinelle).
final DateTime kDate = DateTime(2026, 11, 15);

/// ── ARRIVÉE OFFICIELLE AUTHENTIQUE ────────────────────────────────────────
///
/// Relevée sur la réponse RÉELLE du PMU, et non inventée :
///
///   GET .../programme/15112026/R01/C01?specialisation=INTERNET   → HTTP 200
///     ordreArrivee           = [[4],[6],[7],[9],[1],[3],[5]]
///     nombreDeclaresPartants = 9
///     statut                 = 'ARRIVEE_DEFINITIVE_COMPLETE'
///     arriveeDefinitive      = true
///     isArriveeDefinitive    = true
///
///   GET .../programme/15112026/R01/C01/participants?specialisation=INTERNET
///     → HTTP 200, 16 529 octets, 9 partants :
///       n°4 GORSTELLA       ordreArrivee 1   (1er)
///       n°6 CLARTE DU SOURIRE ordreArrivee 2
///       n°7 DINADAME        ordreArrivee 3
///       n°9 MENTION SPECIALE ordreArrivee 4
///       n°1 WEBCAM          ordreArrivee 5
///       n°3 KERMILLIS       ordreArrivee 6
///       n°5 CHOUCHOU D'ANJOU ordreArrivee 7
///       n°2 FAMILY SPEED    incident ARRETE, pas d'ordreArrivee
///       n°8 MERVEILLE ALLEN incident ARRETE, pas d'ordreArrivee
const List<int> kArrivee = <int>[4, 6, 7, 9, 1, 3, 5];

/// Les deux chevaux ARRÊTÉS (incident officiel `ARRETE`), hors classement.
const List<int> kArretes = <int>[2, 8];

/// Dividende Simple Gagnant RÉELLEMENT publié sur cette course, pour 1 € :
/// ×4,20. Source : `test/fixtures/recherche_pmu/rapports/R1C1.json`,
/// bloc `E_SIMPLE_GAGNANT` → `dividendePourUnEuro: 420`,
/// `libelle: "e-Simple Gagnant"`, `combinaison: "8"`, `rangCombinaisonPayable: 1`.
/// ⚠️ La `combinaison` publiée vaut « 8 ». C'est une donnée de fixture
///    authentique mais INCOHÉRENTE avec l'arrivée authentique du même fichier
///    (le 8 y est ARRÊTÉ). Le test ne s'appuie donc PAS sur ce bloc pour la
///    perdante : il construit le bloc Gagnant sur le VRAI vainqueur, le n°4,
///    et conserve le dividende réel de 4,20 €. Cette substitution est déclarée
///    ici, pas dissimulée.
const int kCentimesGagnant = 420;
const double kDividendeGagnant = 4.20;

/// Numéro réellement gagnant, d'après l'arrivée authentique.
const int kNumeroGagnant = 4;

/// Mise simulée.
const double kMise = 10.0;

/// Retour attendu pour un Simple Gagnant : 10 × 4,20 = 42,00 €.
/// ⚠️ `VerdictGain.total` est le GAIN BRUT (« Gain gagné »), sans déduction de
///    mise et sans remboursement : c'est la convention du moteur, pas un choix
///    de ce test.
const double kGainAttendu = kMise * kDividendeGagnant; // 42.0

// ───────────────────────── Faux serveur PMU (aucun réseau) ──────────────────

/// Une ligne de rapport, au format RÉEL de l'API : elle porte un `libelle`
/// officiel, une `combinaison`, un `dividendePourUnEuro` en CENTIMES et un
/// `rangCombinaisonPayable`.
///
/// ⚠️ Le `libelle` n'est pas décoratif. Mesuré : sans lui,
///    `varianteDepuisLibelle('')` rend `illisible`, donc
///    `rapportPublieDepuisApi` rend `null`, donc le rapport est ÉCARTÉ et le
///    moteur prononce `nonDetermine`. C'est le comportement voulu (on ne
///    devine pas ce qu'un rapport paie) — et le test C9 le vérifie
///    explicitement. Les fixtures de C1..C8 portent donc de vrais libellés,
///    comme le PMU les publie.
Map<String, dynamic> _ligne({
  required String combinaison,
  required String libelle,
  required int centimes,
  int? rang,
}) =>
    <String, dynamic>{
      'combinaison': combinaison,
      'libelle': libelle,
      'dividendePourUnEuro': centimes,
      if (rang != null) 'rangCombinaisonPayable': rang,
    };

/// Bloc `{typePari, rapports[]}` au format RÉEL de l'API.
Map<String, dynamic> _bloc(
  String type,
  List<Map<String, dynamic>> lignes, {
  int? miseBase,
}) =>
    <String, dynamic>{
      'typePari': type,
      if (miseBase != null) 'miseBase': miseBase,
      'rapports': lignes,
    };

/// Corps de `/rapports-definitifs`, tel que l'API le rend.
///
/// Libellés RÉELS mesurés sur les captures : « e-Simple Gagnant »,
/// « e-Simple Placé ».
String _corpsRapports() => json.encode(<dynamic>[
      _bloc(
          'E_SIMPLE_GAGNANT',
          <Map<String, dynamic>>[
            _ligne(
              combinaison: '$kNumeroGagnant',
              libelle: 'e-Simple Gagnant',
              centimes: kCentimesGagnant,
              rang: 1,
            ),
          ],
          miseBase: 100),
      // Bloc Placé : les trois premiers de l'arrivée AUTHENTIQUE (4, 6, 7).
      _bloc(
          'E_SIMPLE_PLACE',
          <Map<String, dynamic>>[
            for (var i = 0; i < 3; i++)
              _ligne(
                combinaison: '${kArrivee[i]}',
                libelle: 'e-Simple Placé',
                centimes: 210,
                rang: i + 1,
              ),
          ],
          miseBase: 100),
    ]);

/// Variante du faux serveur : AUCUN rapport ne porte de libellé.
/// Sert à prouver que l'absence de libellé produit « non déterminé » et
/// JAMAIS une perte.
String _corpsRapportsSansLibelle() => json.encode(<dynamic>[
      _bloc('E_SIMPLE_GAGNANT', <Map<String, dynamic>>[
        <String, dynamic>{
          'combinaison': '$kNumeroGagnant',
          'dividendePourUnEuro': kCentimesGagnant,
        },
      ]),
    ]);

/// Corps de `/participants`, au FORMAT ET AU CONTENU REÇUS.
///
/// C'est la réponse dont `ZoneTurfService` tire l'arrivée officielle ET les
/// statuts. Les 9 partants, leurs rangs et les deux incidents `ARRETE` sont
/// ceux de la réponse authentique (voir les constantes en tête de fichier).
///
/// ⚠️ Clés racine : `participants`, `ecuries`, `spriteCasaques`, `cached`.
///    C'est TOUT. Il n'y a pas de drapeau d'arrivée définitive ici — et c'est
///    précisément ce que la correction BLOC 1 a dû prendre en compte.
String _corpsParticipants() => json.encode(<String, dynamic>{
      'participants': <Map<String, dynamic>>[
        for (var i = 0; i < kArrivee.length; i++)
          {
            'numPmu': kArrivee[i],
            'statut': 'PARTANT',
            'ordreArrivee': i + 1,
          },
        for (final n in kArretes)
          {
            'numPmu': n,
            'statut': 'PARTANT',
            'incident': 'ARRETE',
          },
      ],
      'ecuries': <dynamic>[],
      'spriteCasaques': <String, dynamic>{},
      'cached': false,
    });

/// Corps de l'endpoint PAR COURSE `…/$date/R$r/C$c` — celui qui PORTE
/// réellement le drapeau d'arrivée définitive (mesuré : 71 clés racine, dont
/// `arriveeDefinitive`, `isArriveeDefinitive`, `statut`, `ordreArrivee`).
///
/// [definitif] reproduit les TROIS états observables :
///   • `true`  → le PMU affirme l'arrivée définitive ;
///   • `false` → le PMU l'infirme (arrivée provisoire) ;
///   • `null`  → le PMU est MUET : clé absente du JSON, comme sur 8 des 316
///               courses des fixtures authentiques du dépôt.
String _corpsCourse({required bool? definitif}) {
  final corps = <String, dynamic>{
    'numReunion': 1,
    'numOrdre': 1,
    'nombreDeclaresPartants': 9,
    'ordreArrivee': [
      for (final n in kArrivee) <int>[n],
    ],
  };
  if (definitif != null) {
    corps['arriveeDefinitive'] = definitif;
    corps['isArriveeDefinitive'] = definitif;
    corps['statut'] = definitif ? 'ARRIVEE_DEFINITIVE_COMPLETE' : 'FIN_COURSE';
  }
  // `statut` seul n'est JAMAIS traduit en booléen par la production : quand le
  // drapeau est `null`, on peut donc le publier sans qu'il serve de substitut.
  return json.encode(corps);
}

/// Compteur d'appels réseau par type de chemin : c'est ce qui permet de
/// PROUVER qu'une seconde demande ne repart pas sur le réseau.
class _Compteur {
  int rapports = 0;
  int participants = 0;

  /// Appels à l'endpoint PAR COURSE (`…/programme/{date}/Rxx/Cxx`), celui qui
  /// porte le drapeau d'arrivée définitive. Compté séparément pour pouvoir
  /// PROUVER le nombre exact d'échanges réseau de la correction.
  int courses = 0;
  int autres = 0;
  int get total => rapports + participants + courses + autres;
}

/// Faux serveur PMU. Il reproduit les TROIS endpoints que la production
/// appelle réellement, avec les MÊMES gardes d'ordre que la réalité impose.
///
/// [definitif] pilote l'état du drapeau servi par l'endpoint par course :
/// `true`, `false`, ou `null` (le PMU est muet — clé absente).
/// [courseInjoignable] simule une panne de CET endpoint seulement (HTTP 503).
MockClient _client(
  _Compteur c, {
  bool servirRapports = true,
  bool libellesPresents = true,
  bool? definitif = true,
  bool courseInjoignable = false,
}) =>
    MockClient((http.Request r) async {
      final String p = r.url.path;
      const Map<String, String> entetes = {'content-type': 'application/json'};

      // ⚠️ L'ordre des tests est significatif : « rapports-definitifs » d'abord,
      //    car tous ces chemins contiennent « programme ».
      if (p.contains('rapports-definitifs')) {
        c.rapports++;
        if (!servirRapports) {
          return http.Response('[]', 200, headers: entetes);
        }
        return http.Response(
          libellesPresents ? _corpsRapports() : _corpsRapportsSansLibelle(),
          200,
          headers: entetes,
        );
      }
      if (p.contains('participants')) {
        c.participants++;
        return http.Response(_corpsParticipants(), 200, headers: entetes);
      }
      // Endpoint PAR COURSE : le chemin se termine par /Rxx/Cxx, sans suffixe.
      if (RegExp(r'/R\d+/C\d+$').hasMatch(p)) {
        c.courses++;
        if (courseInjoignable) {
          return http.Response('indisponible', 503, headers: entetes);
        }
        return http.Response(_corpsCourse(definitif: definitif), 200,
            headers: entetes);
      }
      c.autres++;
      return http.Response('{}', 200, headers: entetes);
    });

// ─────────────────────────────── Outils ────────────────────────────────────

IdentiteCoursePmu _identite() => IdentiteCoursePmu(
      numReunion: 6,
      numCourse: 3,
      date: kDate,
    );

/// Remet le repository dans un état vierge ET le stockage à zéro.
Future<void> _vierge() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  // ★ MESURE : `ZoneTurfService` garde des caches STATIQUES (15 min pour le
  //   programme, 2 min pour le drapeau définitif, + `_cacheDrapeauDefinitif`).
  //   Sans purge, un test hériterait du drapeau mesuré par le précédent et le
  //   compteur réseau ne mesurerait plus ce qu'il prétend mesurer. On purge donc
  //   l'état statique au démarrage de chaque test.
  ZoneTurfService.viderCachePourResetComplet();
  final repo = ResultatOfficielRepository.instance;
  repo.oublierChargementPourTest();
  await repo.viderPourTest();
  repo.oublierChargementPourTest();
  await repo.charger();
}

/// Simule un REDÉMARRAGE de l'application : on jette tout l'état mémoire du
/// repository, en CONSERVANT le stockage, puis on recharge.
Future<void> _redemarrer() async {
  final repo = ResultatOfficielRepository.instance;
  repo.oublierChargementPourTest();
  await repo.charger();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═════════════════════════════════════════════════════════════════════════
  //  R1..R4 — LE REPOSITORY ET LA SÉRIALISATION
  // ═════════════════════════════════════════════════════════════════════════

  group(
      'R1 — RapportPmu.toJson : les DIX champs officiels font l\'aller-retour',
      () {
    test('aucun champ officiel n\'est perdu, aucun n\'est inventé', () {
      const original = RapportPmu(
        typePari: 'E_QUINTE_PLUS',
        combinaison: '9-4-15-10-1',
        dividende: 6.42,
        estOrdre: true,
        libelleOfficiel: 'e-Quinté+ Ordre + Tirelire',
        codePariOfficiel: 'E_QUINTE_PLUS',
        rangCombinaisonPayable: 1,
        rembourse: true,
        miseBaseCentimes: 200,
        dividendeUnite: 'PourUnEuro',
      );

      final json = original.toJson();
      final relu = RapportPmu.fromJson(json);

      // Preuve par ÉGALITÉ CHAMP À CHAMP (pas une simple « non-nullité »).
      expect(relu.typePari, 'E_QUINTE_PLUS');
      expect(relu.combinaison, '9-4-15-10-1');
      expect(relu.dividende, 6.42);
      expect(relu.estOrdre, isTrue);
      expect(relu.libelleOfficiel, 'e-Quinté+ Ordre + Tirelire');
      expect(relu.codePariOfficiel, 'E_QUINTE_PLUS');
      expect(relu.rangCombinaisonPayable, 1);
      expect(relu.rembourse, isTrue);
      expect(relu.miseBaseCentimes, 200);
      expect(relu.dividendeUnite, 'PourUnEuro');
    });

    test('un champ absent n\'est JAMAIS deviné', () {
      // JSON minimal : seuls les quatre champs historiques.
      final relu = RapportPmu.fromJson(<String, dynamic>{
        'typePari': 'E_TIERCE',
        'combinaison': '3-1-8',
        'dividende': 25.0,
      });
      expect(relu.libelleOfficiel, '');
      expect(relu.codePariOfficiel, '');
      expect(relu.rangCombinaisonPayable, isNull);
      expect(relu.rembourse, isFalse);
      expect(relu.miseBaseCentimes, isNull);
      expect(relu.dividendeUnite, '');
      expect(relu.estOrdre, isFalse);
    });

    test('un estOrdre PERSISTÉ fait foi sur la valeur par défaut', () {
      // Si la valeur écrite était écrasée par le défaut, un rapport Ordre
      // relu deviendrait Désordre — exactement le défaut que R16 combat.
      final relu = RapportPmu.fromJson(
        const RapportPmu(
          typePari: 'E_TIERCE',
          combinaison: '3-1-8',
          dividende: 25.0,
          estOrdre: true,
        ).toJson(),
        estOrdre: false, // valeur par défaut hostile, doit perdre
      );
      expect(relu.estOrdre, isTrue);
    });
  });

  group('R2 — Identité complète de course : date + réunion + course', () {
    test(
        'deux écritures de la MÊME identité sont égales, quel que soit le zéro',
        () {
      final a = IdentiteCoursePmu(numReunion: 1, numCourse: 3, date: kDate);
      final b = IdentiteCoursePmu(
          numReunion: 1, numCourse: 3, date: DateTime(2026, 11, 15, 14, 30));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.courseKey, 'R1C3_15112026');
    });

    test('une clé sans date réelle ne produit AUCUNE identité', () {
      // Aucune date de remplacement n'est fabriquée.
      expect(IdentiteCoursePmu.depuisCourseKey('R1C3'), isNull);
      expect(IdentiteCoursePmu.depuisCourseKey('R1C3_'), isNull);
      expect(IdentiteCoursePmu.depuisCourseKey('R1C1_31022026'), isNull);
      expect(IdentiteCoursePmu.depuisCourseKey('KEY_PERSONNALISEE'), isNull);
    });

    test('une clé avec suffixe reste lisible, la date seule est lue', () {
      final id = IdentiteCoursePmu.depuisCourseKey('R4C7_23042026_ia');
      expect(id, isNotNull);
      expect(id!.numReunion, 4);
      expect(id.numCourse, 7);
      expect(id.date, DateTime(2026, 4, 23));
    });

    test(
        'une date normalisée par le constructeur Dart ne peut PAS être '
        'détectée après coup — le contrôle porte donc sur les bornes', () {
      // ⚠️ HONNÊTETÉ SUR LA LIMITE DU CONTRÔLE : `DateTime(2026, 2, 30)` est
      // normalisé par Dart en 2026-03-02 AVANT d'entrer dans `construire`.
      // L'aller-retour compare donc 2026-03-02 à 2026-03-02 et ne peut, par
      // construction, pas repérer l'intention « 30 février ». Ce test ne
      // prétend pas le contraire.
      final normalisee = IdentiteCoursePmu.construire(
        date: DateTime(2026, 2, 30),
        numReunion: 1,
        numCourse: 1,
      );
      expect(normalisee, isNotNull,
          reason: 'la normalisation a déjà eu lieu : le contrôle ne peut pas '
              'la défaire');
      expect(normalisee!.date, DateTime(2026, 3, 2));

      // En revanche, les BORNES sont réellement contrôlées : un numéro nul ou
      // une année hors bornes est refusé, et c'est ce qui protège l'identité.
      expect(
        IdentiteCoursePmu.construire(date: kDate, numReunion: 0, numCourse: 1),
        isNull,
      );
      expect(
        IdentiteCoursePmu.construire(date: kDate, numReunion: 1, numCourse: 0),
        isNull,
      );
      expect(
        IdentiteCoursePmu.construire(
            date: DateTime(1600, 1, 1), numReunion: 1, numCourse: 1),
        isNull,
      );
      // Une date ABSENTE ne produit aucune identité — aucune date du jour
      // n'est substituée.
      expect(
        IdentiteCoursePmu.construire(date: null, numReunion: 1, numCourse: 1),
        isNull,
      );
    });
  });

  group('R3 — Persistance : redémarrage, déduplication, mise à jour', () {
    setUp(_vierge);

    test('R3-1 : une entrée écrite est RELUE après redémarrage', () async {
      final repo = ResultatOfficielRepository.instance;
      final ecriture = await repo.enregistrer(
        entree: EntreeResultatOfficiel(
          identite: _identite(),
          arriveeGroupes: const <List<int>>[
            <int>[7],
            <int>[4],
            <int>[2],
          ],
          arriveeDefinitive: true,
          rapports: const <RapportPmu>[
            RapportPmu(
              typePari: 'E_SIMPLE_GAGNANT',
              combinaison: '7',
              dividende: kDividendeGagnant,
              estOrdre: true,
              libelleOfficiel: 'e-Simple Gagnant',
              codePariOfficiel: 'E_SIMPLE_GAGNANT',
              rangCombinaisonPayable: 1,
              miseBaseCentimes: 100,
            ),
          ],
        ),
      );
      expect(ecriture.statut, StatutEcritureResultat.creee);

      // ── REDÉMARRAGE ──────────────────────────────────────────────────────
      await _redemarrer();

      final relue = repo.entreePourIdentite(_identite());
      expect(relue, isNotNull,
          reason: 'la donnée doit survivre au redémarrage');
      expect(relue!.rapports.length, 1);
      expect(relue.rapports.first.dividende, kDividendeGagnant);
      expect(relue.rapports.first.libelleOfficiel, 'e-Simple Gagnant');
      expect(relue.arriveeGroupes, <List<int>>[
        <int>[7],
        <int>[4],
        <int>[2],
      ]);
      expect(relue.arriveeDefinitive, isTrue);
    });

    test('R3-2 : réécrire la MÊME entrée ne duplique rien', () async {
      final repo = ResultatOfficielRepository.instance;
      final entree = EntreeResultatOfficiel(
        identite: _identite(),
        arriveeGroupes: const <List<int>>[
          <int>[7],
          <int>[4],
        ],
        arriveeDefinitive: true,
        rapports: const <RapportPmu>[
          RapportPmu(
            typePari: 'E_SIMPLE_GAGNANT',
            combinaison: '7',
            dividende: 18.0,
            estOrdre: true,
            codePariOfficiel: 'E_SIMPLE_GAGNANT',
            libelleOfficiel: 'e-Simple Gagnant',
          ),
        ],
      );

      expect((await repo.enregistrer(entree: entree)).statut,
          StatutEcritureResultat.creee);
      final seconde = await repo.enregistrer(entree: entree);
      expect(seconde.statut, StatutEcritureResultat.identique);

      await _redemarrer();
      final relue = repo.entreePourIdentite(_identite());
      expect(relue!.rapports.length, 1, reason: 'aucun doublon');
    });

    test('R3-3 : un rapport NOUVEAU enrichit sans écraser', () async {
      final repo = ResultatOfficielRepository.instance;
      await repo.enregistrer(
        entree: EntreeResultatOfficiel(
          identite: _identite(),
          arriveeGroupes: const <List<int>>[
            <int>[7],
            <int>[4],
          ],
          arriveeDefinitive: true,
          rapports: const <RapportPmu>[
            RapportPmu(
              typePari: 'E_SIMPLE_GAGNANT',
              combinaison: '7',
              dividende: 18.0,
              estOrdre: true,
              codePariOfficiel: 'E_SIMPLE_GAGNANT',
              libelleOfficiel: 'e-Simple Gagnant',
            ),
          ],
        ),
      );

      final seconde = await repo.enregistrer(
        entree: EntreeResultatOfficiel(
          identite: _identite(),
          arriveeGroupes: const <List<int>>[
            <int>[7],
            <int>[4],
          ],
          arriveeDefinitive: true,
          rapports: const <RapportPmu>[
            RapportPmu(
              typePari: 'E_SIMPLE_PLACE',
              combinaison: '7',
              dividende: 4.2,
              estOrdre: false,
              codePariOfficiel: 'E_SIMPLE_PLACE',
              libelleOfficiel: 'e-Simple Placé',
            ),
          ],
        ),
      );
      expect(seconde.statut, StatutEcritureResultat.enrichie);

      await _redemarrer();
      final relue = repo.entreePourIdentite(_identite());
      expect(relue!.rapports.length, 2,
          reason: 'le rapport existant est CONSERVÉ, le nouveau est AJOUTÉ');
    });

    test('R3-4 : provisoire → définitif est une mise à jour AUTORISÉE',
        () async {
      final repo = ResultatOfficielRepository.instance;
      await repo.enregistrer(
        entree: EntreeResultatOfficiel(
          identite: _identite(),
          arriveeGroupes: const <List<int>>[
            <int>[7],
            <int>[4],
          ],
          arriveeDefinitive: false, // PROVISOIRE
          rapports: const <RapportPmu>[
            RapportPmu(
              typePari: 'E_SIMPLE_GAGNANT',
              combinaison: '7',
              dividende: 99.0, // dividende provisoire, volontairement faux
              estOrdre: true,
              codePariOfficiel: 'E_SIMPLE_GAGNANT',
              libelleOfficiel: 'e-Simple Gagnant',
            ),
          ],
        ),
      );

      final maj = await repo.enregistrer(
        entree: EntreeResultatOfficiel(
          identite: _identite(),
          arriveeGroupes: const <List<int>>[
            <int>[7],
            <int>[4],
          ],
          arriveeDefinitive: true, // DÉFINITIF
          rapports: const <RapportPmu>[
            RapportPmu(
              typePari: 'E_SIMPLE_GAGNANT',
              combinaison: '7',
              dividende: 18.0,
              estOrdre: true,
              codePariOfficiel: 'E_SIMPLE_GAGNANT',
              libelleOfficiel: 'e-Simple Gagnant',
            ),
          ],
        ),
      );
      expect(maj.statut, StatutEcritureResultat.provisoireDevenueDefinitive);

      await _redemarrer();
      final relue = repo.entreePourIdentite(_identite())!;
      expect(relue.arriveeDefinitive, isTrue);
      expect(relue.rapports.single.dividende, 18.0,
          reason: 'le montant provisoire doit être REMPLACÉ, pas conservé');
    });

    test(
        'R3-5 : deux arrivées DÉFINITIVES divergentes = CONFLIT signalé, '
        'le fait local est conservé', () async {
      final repo = ResultatOfficielRepository.instance;
      await repo.enregistrer(
        entree: EntreeResultatOfficiel(
          identite: _identite(),
          arriveeGroupes: const <List<int>>[
            <int>[7],
            <int>[4],
          ],
          arriveeDefinitive: true,
          rapports: const <RapportPmu>[
            RapportPmu(
              typePari: 'E_SIMPLE_GAGNANT',
              combinaison: '7',
              dividende: 18.0,
              estOrdre: true,
              codePariOfficiel: 'E_SIMPLE_GAGNANT',
              libelleOfficiel: 'e-Simple Gagnant',
            ),
          ],
        ),
      );

      final conflit = await repo.enregistrer(
        entree: EntreeResultatOfficiel(
          identite: _identite(),
          arriveeGroupes: const <List<int>>[
            <int>[9], // ⚠️ ARRIVÉE DIFFÉRENTE
            <int>[4],
          ],
          arriveeDefinitive: true,
          rapports: const <RapportPmu>[
            RapportPmu(
              typePari: 'E_SIMPLE_GAGNANT',
              combinaison: '9',
              dividende: 55.0,
              estOrdre: true,
              codePariOfficiel: 'E_SIMPLE_GAGNANT',
              libelleOfficiel: 'e-Simple Gagnant',
            ),
          ],
        ),
      );

      expect(conflit.statut, StatutEcritureResultat.conflitDefinitif);
      expect(conflit.estConflit, isTrue);
      expect(conflit.courseKey, _identite().courseKey);
      expect(conflit.motif, isNotNull);

      await _redemarrer();
      final relue = repo.entreePourIdentite(_identite())!;
      expect(relue.arriveeGroupes!.first, <int>[7],
          reason: 'l\'arrivée locale est un fait établi : elle est CONSERVÉE');
    });

    test('R3-6 : une entrée sans arrivée NI rapport est REFUSÉE', () async {
      final repo = ResultatOfficielRepository.instance;
      final r = await repo.enregistrer(
        entree: EntreeResultatOfficiel(
          identite: _identite(),
          arriveeGroupes: null,
          arriveeDefinitive: null,
          rapports: const <RapportPmu>[],
        ),
      );
      expect(r.statut, StatutEcritureResultat.refusee);
      expect(repo.nbEntrees, 0);
    });

    test('R3-7 : une identité invalide est REFUSÉE', () async {
      final repo = ResultatOfficielRepository.instance;
      final r = await repo.enregistrer(
        entree: EntreeResultatOfficiel(
          identite: IdentiteCoursePmu(
              numReunion: 0, numCourse: 3, date: kDate), // réunion 0
          arriveeGroupes: const <List<int>>[
            <int>[7],
          ],
          arriveeDefinitive: true,
          rapports: const <RapportPmu>[
            RapportPmu(
                typePari: 'E_SIMPLE_GAGNANT',
                combinaison: '7',
                dividende: 1.0,
                estOrdre: true),
          ],
        ),
      );
      expect(r.statut, StatutEcritureResultat.refusee);
    });

    test('R3-8 : aucun purge par ancienneté — 400 jours restent conservés',
        () async {
      final repo = ResultatOfficielRepository.instance;
      final ancienne = IdentiteCoursePmu(
        numReunion: 2,
        numCourse: 5,
        date: DateTime(2025, 10, 1), // > 400 jours avant nov. 2026
      );
      await repo.enregistrer(
        entree: EntreeResultatOfficiel(
          identite: ancienne,
          arriveeGroupes: const <List<int>>[
            <int>[1],
          ],
          arriveeDefinitive: true,
          rapports: const <RapportPmu>[
            RapportPmu(
                typePari: 'E_SIMPLE_GAGNANT',
                combinaison: '1',
                dividende: 3.0,
                estOrdre: true),
          ],
        ),
      );
      await _redemarrer();
      expect(repo.entreePourIdentite(ancienne), isNotNull,
          reason: '§11 : conservation SANS LIMITE de durée des données '
              'officielles');
    });

    test(
        'R3-9 : le caractère DÉFINITIF survit à la persistance, au redémarrage '
        'et à la restauration — les TROIS états restent distincts', () async {
      final repo = ResultatOfficielRepository.instance;

      // Trois courses distinctes, un état de drapeau chacune.
      final definitif = IdentiteCoursePmu(
          numReunion: 1, numCourse: 2, date: DateTime(2026, 11, 15));
      final provisoire = IdentiteCoursePmu(
          numReunion: 1, numCourse: 3, date: DateTime(2026, 11, 15));
      final muet = IdentiteCoursePmu(
          numReunion: 1, numCourse: 4, date: DateTime(2026, 11, 15));

      Future<void> ecrire(IdentiteCoursePmu id, bool? drapeau) =>
          repo.enregistrer(
            entree: EntreeResultatOfficiel(
              identite: id,
              arriveeGroupes: const <List<int>>[
                <int>[1],
                <int>[2],
              ],
              arriveeDefinitive: drapeau,
              rapports: const <RapportPmu>[
                RapportPmu(
                    typePari: 'E_SIMPLE_GAGNANT',
                    combinaison: '1',
                    dividende: 5.0,
                    estOrdre: true),
              ],
            ),
          );

      await ecrire(definitif, true);
      await ecrire(provisoire, false);
      await ecrire(muet, null);

      // 1) En mémoire, immédiatement après écriture.
      expect(repo.entreePourIdentite(definitif)!.arriveeDefinitive, isTrue);
      expect(repo.entreePourIdentite(provisoire)!.arriveeDefinitive, isFalse);
      expect(repo.entreePourIdentite(muet)!.arriveeDefinitive, isNull,
          reason: 'NULL reste NULL : il ne devient jamais false ni true');

      // 2) Après REDÉMARRAGE (mémoire jetée, stockage conservé).
      await _redemarrer();
      expect(repo.entreePourIdentite(definitif)!.arriveeDefinitive, isTrue);
      expect(repo.entreePourIdentite(provisoire)!.arriveeDefinitive, isFalse);
      expect(repo.entreePourIdentite(muet)!.arriveeDefinitive, isNull,
          reason: 'la sérialisation ne doit pas perdre l\'état « inconnu »');

      // 3) Après EXPORT puis RESTAURATION dans un repository vierge.
      final sauvegarde = await repo.exporterPourBackup();
      await _vierge();
      final restauration = await repo.restaurerDepuisBackup(sauvegarde);
      expect(restauration.succes, isTrue);
      expect(repo.entreePourIdentite(definitif)!.arriveeDefinitive, isTrue);
      expect(repo.entreePourIdentite(provisoire)!.arriveeDefinitive, isFalse);
      expect(repo.entreePourIdentite(muet)!.arriveeDefinitive, isNull,
          reason: 'une sauvegarde/restauration ne doit pas fabriquer un '
              'caractère définitif que la source n\'a jamais publié');
    });
  });

  group('R4 — Sauvegarde / restauration', () {
    setUp(_vierge);

    test('R4-1 : l\'export contient les shards, la restauration les remet',
        () async {
      final repo = ResultatOfficielRepository.instance;
      await repo.enregistrer(
        entree: EntreeResultatOfficiel(
          identite: _identite(),
          arriveeGroupes: const <List<int>>[
            <int>[7],
            <int>[4],
          ],
          arriveeDefinitive: true,
          rapports: const <RapportPmu>[
            RapportPmu(
                typePari: 'E_SIMPLE_GAGNANT',
                combinaison: '7',
                dividende: 18.0,
                estOrdre: true,
                codePariOfficiel: 'E_SIMPLE_GAGNANT',
                libelleOfficiel: 'e-Simple Gagnant'),
          ],
        ),
      );

      final backup = await repo.exporterPourBackup();
      expect(backup['version'], kResultatOfficielFormatVersion);
      expect((backup['shards'] as Map).isNotEmpty, isTrue);

      // Perte totale, puis restauration.
      await repo.viderPourTest();
      repo.oublierChargementPourTest();
      await repo.charger();
      expect(repo.nbEntrees, 0);

      final restauration = await repo.restaurerDepuisBackup(backup);
      expect(restauration.succes, isTrue);

      await _redemarrer();
      final relue = repo.entreePourIdentite(_identite());
      expect(relue, isNotNull);
      expect(relue!.rapports.single.dividende, 18.0);
      expect(relue.arriveeGroupes, <List<int>>[
        <int>[7],
        <int>[4],
      ]);
    });

    test('R4-2 : restaurer deux fois ne duplique rien', () async {
      final repo = ResultatOfficielRepository.instance;
      await repo.enregistrer(
        entree: EntreeResultatOfficiel(
          identite: _identite(),
          arriveeGroupes: const <List<int>>[
            <int>[7],
          ],
          arriveeDefinitive: true,
          rapports: const <RapportPmu>[
            RapportPmu(
                typePari: 'E_SIMPLE_GAGNANT',
                combinaison: '7',
                dividende: 18.0,
                estOrdre: true),
          ],
        ),
      );
      final backup = await repo.exporterPourBackup();
      final r2 = await repo.restaurerDepuisBackup(backup);
      expect(r2.succes, isTrue);
      expect(repo.nbEntrees, 1);
    });

    test('R4-3 : un shard illisible est COMPTÉ, jamais inventé', () async {
      final repo = ResultatOfficielRepository.instance;
      final r = await repo.restaurerDepuisBackup(<String, dynamic>{
        'version': kResultatOfficielFormatVersion,
        'shards': <String, dynamic>{
          'resultat_officiel_pmu_v1_2026-11': 'ceci-n-est-pas-du-json',
        },
      });
      expect(r.succes, isTrue);
      expect(r.shardsIllisibles, 1);
      expect(r.entreesAjoutees, 0);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C1..C6 — LA CHAÎNE COMPLÈTE, DU RÉSEAU AU CONSOMMATEUR FINANCIER
  // ═════════════════════════════════════════════════════════════════════════

  group('C — Chaîne complète : producteur HTTP → persistance → moteur', () {
    setUp(_vierge);

    test(
        'C1 : un Simple Gagnant sur le 4 (vainqueur réel) rend EXACTEMENT '
        'le dividende publié', () async {
      final compteur = _Compteur();
      final client = _client(compteur);

      await http.runWithClient(() async {
        final resolution = await resoudrePariSimule(
          identite: _identite(),
          libelleTypePari: 'Simple Gagnant',
          numerosJoues: const <int>[kNumeroGagnant],
          mise: kMise,
          autoriserReseau: true,
        );

        expect(resolution.estDeterminee, isTrue,
            reason: 'cause éventuelle : ${resolution.explication}');
        expect(resolution.estGagnant, isTrue);
        expect(resolution.gain, closeTo(kGainAttendu, 1e-9));
        expect(resolution.verdict!.total, closeTo(kGainAttendu, 1e-9));
        // Le verdict vient du moteur officiel, pas d'un calcul local.
        expect(resolution.verdict!.etat.name, 'attribue');
      }, () => client);

      expect(compteur.rapports, 1, reason: 'un seul appel aux rapports');
      expect(compteur.participants, 1,
          reason: 'un seul appel aux participants');
    });

    test(
        'C2 : la donnée est PERSISTÉE — le second appel ne va PAS sur le réseau',
        () async {
      final compteur = _Compteur();
      final client = _client(compteur);

      await http.runWithClient(() async {
        final r1 = await resoudrePariSimule(
          identite: _identite(),
          libelleTypePari: 'Simple Gagnant',
          numerosJoues: const <int>[kNumeroGagnant],
          mise: kMise,
          autoriserReseau: true,
        );
        expect(r1.estGagnant, isTrue);
        expect(r1.servieDepuisStockage, isFalse);

        final apres1 = compteur.total;
        expect(apres1, greaterThan(0));

        // ── Deuxième demande : autoriserReseau vaut true, MAIS la donnée
        //    persistée est exploitable → elle doit être servie sans réseau.
        final r2 = await resoudrePariSimule(
          identite: _identite(),
          libelleTypePari: 'Simple Gagnant',
          numerosJoues: const <int>[kNumeroGagnant],
          mise: kMise,
          autoriserReseau: true,
        );
        expect(r2.estGagnant, isTrue);
        expect(r2.servieDepuisStockage, isTrue);
        expect(r2.gain, closeTo(kGainAttendu, 1e-9));
        // Mesure HONNÊTE : ce n'est pas le total cumulé qui prouve l'absence
        // d'appel, c'est le DELTA. On photographie donc le compteur juste avant
        // la seconde demande et on compare après.
        expect(compteur.total, apres1,
            reason: 'aucune requête répétitive inutile (§4 du mandat) : '
                'le second appel doit être servi depuis le stockage');
      }, () => client);
    });

    test(
        'C2b : après REDÉMARRAGE, la résolution est encore possible hors réseau',
        () async {
      final compteur = _Compteur();
      await http.runWithClient(() async {
        await resoudrePariSimule(
          identite: _identite(),
          libelleTypePari: 'Simple Gagnant',
          numerosJoues: const <int>[kNumeroGagnant],
          mise: kMise,
          autoriserReseau: true,
        );
      }, () => _client(compteur));

      await _redemarrer();

      // Réseau INTERDIT : la seule source possible est le stockage.
      final resolution = await resoudrePariSimule(
        identite: _identite(),
        libelleTypePari: 'Simple Gagnant',
        numerosJoues: const <int>[kNumeroGagnant],
        mise: kMise,
        autoriserReseau: false,
      );
      expect(resolution.estDeterminee, isTrue,
          reason: 'la persistance doit suffire après redémarrage');
      expect(resolution.gain, closeTo(kGainAttendu, 1e-9));
      expect(resolution.servieDepuisStockage, isTrue);
    });

    // ── C3 — LES TROIS SITUATIONS DU CARACTÈRE DÉFINITIF ───────────────────
    //
    //  Ces trois tests sont le cœur de la correction BLOC 1 sur ce point. Ils
    //  ne testent PAS le moteur (qui est correct et n'a pas été touché) : ils
    //  testent que la DONNÉE qui lui est fournie est enfin la bonne.
    //
    //  Avant correction, la situation 1 rendait « non déterminé » — et non
    //  « perdu » — parce que le drapeau était lu sur un endpoint qui ne le
    //  publie pas. C'était un défaut d'ALIMENTATION, pas de décision.

    test('C3-a : arrivée DÉFINITIVE + bloc démontré complet → PERTE ÉTABLIE',
        () async {
      final compteur = _Compteur();
      await http.runWithClient(() async {
        final resolution = await resoudrePariSimule(
          identite: _identite(),
          libelleTypePari: 'Simple Gagnant',
          // Le 5 est réellement 7e de l'arrivée authentique : il a couru, il
          // n'a pas gagné. Ce n'est ni un non-partant ni un arrêté — la perte
          // est donc démontrable, et non simplement « probable ».
          numerosJoues: const <int>[5],
          mise: kMise,
          autoriserReseau: true,
        );
        expect(resolution.estDeterminee, isTrue,
            reason: 'une arrivée définitive et un bloc complet établissent '
                'le sort du pari : « non déterminé » serait un recul');
        expect(resolution.estPerdant, isTrue);
        expect(resolution.estGagnant, isFalse);
        expect(resolution.gain, 0.0,
            reason: 'une perte ÉTABLIE rend un gain de 0, jamais null');
      }, () => _client(compteur));
      // La correction n'a pas multiplié les échanges : un GET de programme par
      // course, et rien de plus.
      expect(compteur.courses, 1,
          reason:
              'le drapeau se lit sur l\'endpoint par course, une seule fois');
    });

    test(
        'C3-b : arrivée PROVISOIRE (drapeau explicitement false) → '
        'NON DÉTERMINÉ, jamais perdu', () async {
      final compteur = _Compteur();
      await http.runWithClient(() async {
        final resolution = await resoudrePariSimule(
          identite: _identite(),
          libelleTypePari: 'Simple Gagnant',
          numerosJoues: const <int>[5],
          mise: kMise,
          autoriserReseau: true,
        );
        expect(resolution.estNonDeterminee, isTrue,
            reason: 'une arrivée provisoire ne peut pas établir une perte');
        expect(resolution.estPerdant, isFalse,
            reason: 'PROVISOIRE ne doit JAMAIS devenir « perdu »');
        expect(resolution.gain, isNull,
            reason: 'non déterminé ⇒ gain inconnu, donc null — pas 0.0');
        expect(resolution.montantReverse, isNull);
      }, () => _client(compteur, definitif: false));
    });

    test(
        'C3-c : caractère définitif INCONNU (drapeau absent) → '
        'NON DÉTERMINÉ, jamais perdu', () async {
      final compteur = _Compteur();
      await http.runWithClient(() async {
        final resolution = await resoudrePariSimule(
          identite: _identite(),
          libelleTypePari: 'Simple Gagnant',
          numerosJoues: const <int>[5],
          mise: kMise,
          autoriserReseau: true,
        );
        expect(resolution.estNonDeterminee, isTrue,
            reason: 'le PMU est muet (8 courses sur 316 mesurées) : '
                'l\'absence de preuve ne vaut pas preuve de perte');
        expect(resolution.estPerdant, isFalse);
        expect(resolution.gain, isNull);
      }, () => _client(compteur, definitif: null));
    });

    test(
        'C3-d : source du drapeau INJOIGNABLE (HTTP 503) → NON DÉTERMINÉ, '
        'et surtout PAS « perdu » par défaut', () async {
      final compteur = _Compteur();
      await http.runWithClient(() async {
        final resolution = await resoudrePariSimule(
          identite: _identite(),
          libelleTypePari: 'Simple Gagnant',
          numerosJoues: const <int>[5],
          mise: kMise,
          autoriserReseau: true,
        );
        expect(resolution.estNonDeterminee, isTrue);
        expect(resolution.estPerdant, isFalse,
            reason: 'une panne de la source ne fabrique jamais une perte');
        // Contrôle direct de la lecture à la source, sans passer par le moteur.
        final drapeau = await ZoneTurfService.chargerResultatsCourseComplet(
          heureDepart: kDate,
          numReunion: 6,
          numCourse: 3,
        );
        expect(drapeau, isNotNull,
            reason: 'les participants répondent, seule la course est en panne');
        expect(drapeau!.arriveeDefinitive, isNull,
            reason: '503 sur la source du drapeau ⇒ inconnu, pas false');
        expect(drapeau.arriveeOfficielle, isNotEmpty);
      }, () => _client(compteur, courseInjoignable: true));
    });

    test(
        'C4 : sans réseau ET sans stockage, la résolution est NON DÉTERMINÉE '
        'avec une cause explicite — aucun gain, aucune perte', () async {
      final resolution = await resoudrePariSimule(
        identite: _identite(),
        libelleTypePari: 'Simple Gagnant',
        numerosJoues: const <int>[kNumeroGagnant],
        mise: kMise,
        autoriserReseau: false,
      );

      expect(resolution.estNonDeterminee, isTrue);
      expect(resolution.verdict, isNull);
      expect(resolution.gain, isNull,
          reason: 'JAMAIS 0.0 : un montant ne doit pas exister');
      expect(resolution.montantReverse, isNull);
      expect(resolution.remboursement, isNull);
      expect(resolution.cause,
          CauseNonDetermination.resultatAbsentSansRecuperation);
      // Ni gain ni perte ne doit pouvoir être déduit.
      expect(resolution.estGagnant, isFalse);
      expect(resolution.estPerdant, isFalse);
    });

    test('C5 : réseau autorisé mais PMU muet → NON DÉTERMINÉ, jamais une perte',
        () async {
      final compteur = _Compteur();
      await http.runWithClient(() async {
        final resolution = await resoudrePariSimule(
          identite: _identite(),
          libelleTypePari: 'Simple Gagnant',
          numerosJoues: const <int>[kNumeroGagnant],
          mise: kMise,
          autoriserReseau: true,
        );
        expect(resolution.estNonDeterminee, isTrue);
        expect(resolution.cause, CauseNonDetermination.resultatIndisponible);
        expect(resolution.gain, isNull);
        expect(resolution.estPerdant, isFalse);
      }, () => _client(compteur, servirRapports: false));
    });

    test('C6 : Gagnant+Placé refuse une mise agrégée', () async {
      final resolution = await resoudrePariGagnantPlace(
        identite: _identite(),
        libelleTypePari: 'Gagnant+Placé',
        numerosJoues: const <int>[kNumeroGagnant],
        miseGagnant: 10.0,
        misePlace: 0.0, // ⚠️ une des deux manque
        autoriserReseau: false,
      );
      expect(resolution.estNonDeterminee, isTrue);
      expect(resolution.cause, CauseNonDetermination.ticketNonConstructible);
      expect(resolution.gain, isNull);
    });

    test('C7 : une mise nulle est refusée AVANT toute récupération', () async {
      final compteur = _Compteur();
      await http.runWithClient(() async {
        final resolution = await resoudrePariSimule(
          identite: _identite(),
          libelleTypePari: 'Simple Gagnant',
          numerosJoues: const <int>[kNumeroGagnant],
          mise: 0.0,
          autoriserReseau: true,
        );
        expect(resolution.estNonDeterminee, isTrue);
        expect(resolution.cause, CauseNonDetermination.ticketNonConstructible);
      }, () => _client(compteur));
      expect(compteur.total, 0,
          reason: 'un refus de ticket ne doit déclencher AUCUN réseau');
    });

    test(
        'C9 : un rapport SANS libellé officiel est ÉCARTÉ — la résolution '
        'reste non déterminée, jamais une perte', () async {
      final compteur = _Compteur();
      await http.runWithClient(() async {
        final resolution = await resoudrePariSimule(
          identite: _identite(),
          libelleTypePari: 'Simple Gagnant',
          numerosJoues: const <int>[kNumeroGagnant],
          mise: kMise,
          autoriserReseau: true,
        );
        // C'est le comportement VOULU : sans libellé, la variante est
        // illisible, donc le rapport est écarté et le moteur refuse de
        // trancher. Il ne déclare NI gain NI perte.
        expect(resolution.estNonDeterminee, isTrue);
        expect(resolution.gain, isNull);
        expect(resolution.estPerdant, isFalse);
        expect(resolution.cause, CauseNonDetermination.rapportsAbsents);
      }, () => _client(compteur, libellesPresents: false));
    });

    test('C8 : une identité indeterminable ne déclenche AUCUN réseau',
        () async {
      final compteur = _Compteur();
      await http.runWithClient(() async {
        // Clé sans date réelle → pas d'identité.
        expect(IdentiteCoursePmu.depuisCourseKey('R6C3'), isNull);
      }, () => _client(compteur));
      expect(compteur.total, 0);
    });
  });
}
