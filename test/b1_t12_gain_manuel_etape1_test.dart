// ═══════════════════════════════════════════════════════════════════════════
//  B1-T12 / ÉTAPE 1 — GAIN MANUEL, GAIN RETENU, LIAISON CERTAINE
//
//  Ce que ce fichier PROUVE, et comment :
//    G1  Un gain manuel est prioritaire sur le PMU arbitrairement.
//    G2  Un gain manuel de 0 € est DISTINGUABLE de l'absence de saisie.
//    G3  Sans gain manuel, le PMU fait foi (jamais écrasé).
//    G4  Sans rien de fiable, `gainRetenu` est INDÉTERMINÉ (null), pas 0.
//    G5  Le net se déduit du brut MOINS la mise réellement engagée.
//    G6  Mise inconnue ⇒ brut conservé, net null (aucun net inventé).
//    G6b Mise à 0 € ⇒ traitée comme non renseignée (parité des deux modèles).
//    G7  `gainNet` historique est INCHANGÉ (aucune formule touchée).
//    J1  JSON : un ancien ticket garde EXACTEMENT 26 / 28 clés.
//    J2  JSON : avec un gain manuel, les deux clés apparaissent.
//    J3  JSON : 0.0 survit à l'aller-retour (pas confondu avec null).
//    J4  JSON : aller-retour complet bit-à-bit (idempotence).
//    L1  Liaison : `idTicketLie` est persisté des deux côtés.
//    L2  Deux paris sur la MÊME course restent INDÉPENDANTS.
//    L3  Un ancien ticket reste non lié (null) et garde son gain manuel.
//
//  ⚠️ Ce fichier n'ajoute AUCUNE infrastructure : il réutilise
//     SharedPreferences.setMockInitialValues, comme a0_02.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/services/alert_service.dart' show TrackedCourse;
// ★ `TrackedCourse.copyWith` est fourni par une EXTENSION déclarée dans
//   `enregistreur_verdict_gain_suivi.dart` (classe `TrackedCourseCopy`), et
//   non par la classe elle-même. Sans cet import, l'appel ne compile pas :
//   mesuré — « The method 'copyWith' isn't defined for the type
//   'TrackedCourse' ».
import 'package:pronostic_hippique/services/enregistreur_verdict_gain_suivi.dart';

// ── Nombres mesurés, jamais inventés ───────────────────────────────────────
const double kMiseComposante = 10.0; // une composante G+P
const double kMiseTotaleGP = 20.0;   // les deux composantes
const double kCoteGagnant = 18.00;
const double kBrutManuel = 250.00;   // ce que l'utilisateur déclare recevoir
const double kNetAttendu = 230.00;   // 250 − 20

UserPrediction _gpSansGainManuel() => UserPrediction(
      id: 'pred_gp_1',
      dateStr: '2026-11-25',
      numReunion: 1,
      numCourse: 6,
      nomCourse: 'PRIX TEST',
      hippodrome: 'VINCENNES',
      numeroCheval: 16,
      nomCheval: 'CHEVAL 16',
      cote: kCoteGagnant,
      typePari: 'Gagnant+Placé',
      createdAt: DateTime(2026, 11, 25, 14, 30),
      isCorrect: true,
      montantMise: kMiseComposante,
      miseGagnant: kMiseComposante,
      misePlace: kMiseComposante,
    );

TrackedCourse _courseSansGainManuel() => TrackedCourse(
      numReunion: 1,
      numCourse: 6,
      nomCourse: 'PRIX TEST',
      hippodrome: 'VINCENNES',
      heureDepart: DateTime(2026, 11, 25, 14, 30),
      typePari: 'Gagnant+Placé',
      miseEngagee: kMiseComposante,
      miseGagnant: kMiseComposante,
      misePlace: kMiseComposante,
      storageKey: 'R1C6_25112026_1700000000000',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  G — LE GAIN RETENU : PRIORITÉ ET BRUT/NET
  // ═════════════════════════════════════════════════════════════════════════

  group('G — gainRetenu : priorité, brut et net', () {
    test('G1 — le gain manuel est prioritaire, des deux côtés', () {
      final p = _gpSansGainManuel().copyWith(montantGainManuel: kBrutManuel);
      final c = _courseSansGainManuel().copyWith(montantGainManuel: kBrutManuel);

      expect(p.aGainManuel, isTrue);
      expect(p.gainRetenuBrut, kBrutManuel);
      expect(c.aGainManuel, isTrue);
      expect(c.gainRetenuBrut, kBrutManuel);
    });

    test('G2 — 0 € déclaré est DISTINCT de « pas de saisie »', () {
      // Sans saisie : `null`, même si le ticket est gagnant.
      final sans = _gpSansGainManuel();
      expect(sans.montantGainManuel, isNull);
      expect(sans.aGainManuel, isFalse);

      // Avec 0 € déclaré : c'est un MONTANT, pas une absence.
      final zero = sans.copyWith(montantGainManuel: 0.0);
      expect(zero.montantGainManuel, 0.0);
      expect(zero.aGainManuel, isTrue,
          reason: '0.0 est une déclaration, null est une absence');
      expect(zero.gainRetenuBrut, 0.0,
          reason: 'un 0 € explicite ne retombe PAS sur le calcul PMU');

      // Preuve de non-confusion : les deux états diffèrent.
      expect(zero.montantGainManuel, isNot(sans.montantGainManuel));
    });

    test('G3 — sans gain manuel, le PMU fait foi et n\'est pas écrasé', () {
      // Ticket G+P dont le PMU a établi un gain officiel de 35 € net.
      final p = _gpSansGainManuel().copyWith(gainRealise: 35.0);
      // gainRealise est un NET ; le brut annoncé par le PMU = 35 + 20 = 55 €.
      expect(p.gainRetenuBrut, 55.0,
          reason: 'le net PMU est reconverti en brut en ré-ajoutant la mise');
      // Les champs officiels restent intacts.
      expect(p.gainRealise, 35.0);
      expect(p.montantGainManuel, isNull,
          reason: 'le PMU n\'écrit jamais dans le champ manuel');
    });

    test('G4 — sans rien de fiable, le gain est INDÉTERMINÉ (null, pas 0)', () {
      // G+P gagné, mais AUCUN gain officiel et AUCUNE saisie : c'est
      // exactement l'état que produit le défaut B1-T12.
      final p = _gpSansGainManuel();
      expect(p.gainRetenuBrut, isNull,
          reason: 'on n\'affirme rien ; surtout pas la cote × mise');
      expect(p.gainRetenuNet, isNull);

      final c = _courseSansGainManuel();
      expect(c.gainRetenuBrut, isNull);
      expect(c.gainRetenuNet, isNull);
    });

    test('G5 — le net = brut − mise TOTALE engagée (les deux composantes)', () {
      final p = _gpSansGainManuel().copyWith(montantGainManuel: kBrutManuel);
      expect(p.miseTotaleEngagee, kMiseTotaleGP,
          reason: 'un G+P engage 10 + 10, jamais 10');
      expect(p.gainRetenuNet, kNetAttendu,
          reason: '250 − 20 = 230 : la mise des DEUX composantes est déduite');
    });

    test('G6 — mise inconnue : brut conservé, net null (rien d\'inventé)', () {
      // Ticket sans aucune mise renseignée.
      final sansMise = UserPrediction(
        id: 'pred_sans_mise',
        dateStr: '2026-11-25',
        numReunion: 2,
        numCourse: 1,
        nomCourse: 'PRIX SANS MISE',
        hippodrome: 'CAEN',
        numeroCheval: 5,
        nomCheval: 'CHEVAL 5',
        cote: 3.0,
        typePari: 'Simple Gagnant',
        createdAt: DateTime(2026, 11, 25),
        isCorrect: true,
        montantGainManuel: 40.0,
      );
      // ★ MESURÉ, PAS SUPPOSÉ : `montantMise` est un `double` NON NULLABLE de
      //   défaut `0.0` (pmu_models.dart:798). `miseTotaleEngagee` ne peut donc
      //   JAMAIS rendre `null` dans ce modèle — ma première assertion
      //   (`isNull`) était fausse et c'est elle qui échouait, pas la règle
      //   métier. La mesure donne `0.0`.
      expect(sansMise.montantMise, 0.0,
          reason: 'défaut du modèle : la mise absente se présente comme 0.0');
      expect(sansMise.miseTotaleEngagee, 0.0,
          reason: 'aucune composante G+P ⇒ repli sur montantMise');
      // L'ASSERTION MÉTIER, elle, est inchangée et reste l'enjeu du test :
      // une mise de 0 € ne doit pas produire « 40 − 0 = 40 ».
      expect(sansMise.gainRetenuBrut, 40.0,
          reason: 'le brut est un FAIT : il reste affichable');
      expect(sansMise.gainRetenuNet, isNull,
          reason: 'sans mise, aucun net ne peut être calculé');
    });

    test('G6b — 0 € de mise reste distinguable de « mise connue à 0 »',
        () {
      // Le corollaire de G6 : `mise <= 0` est traité comme NON RENSEIGNÉE,
      // donc le net est indéterminé même quand le brut est connu et positif.
      final miseZero = UserPrediction(
        id: 'pred_mise_zero',
        dateStr: '2026-11-25',
        numReunion: 2,
        numCourse: 2,
        nomCourse: 'PRIX MISE ZERO',
        hippodrome: 'CAEN',
        numeroCheval: 7,
        nomCheval: 'CHEVAL 7',
        cote: 3.0,
        typePari: 'Simple Gagnant',
        createdAt: DateTime(2026, 11, 25),
        isCorrect: true,
        montantMise: 0.0,
        montantGainManuel: 0.0,
      );
      expect(miseZero.aGainManuel, isTrue,
          reason: 'un manuel de 0 € EST une déclaration');
      expect(miseZero.gainRetenuBrut, 0.0,
          reason: 'le 0 € déclaré est prioritaire sur tout calcul PMU');
      expect(miseZero.gainRetenuNet, isNull,
          reason: 'mise non renseignée ⇒ net indéterminé, pas « 0 − 0 »');
      expect(miseZero.gainNet, 0.0,
          reason: 'gainNet historique intact (montantMise > 0 exigé)');
    });

    test('G7 — gainNet historique est INCHANGÉ (aucune formule touchée)', () {
      // La branche ④ historique : (18 × 10) − 10 = 170.
      final p = _gpSansGainManuel();
      expect(p.gainNet, 170.0,
          reason: 'la formule historique n\'est pas modifiée par cette étape');
      expect(p.retourTotal, 180.0);

      // Et le gain manuel ne la change pas non plus.
      final avecManuel =
          p.copyWith(montantGainManuel: kBrutManuel);
      expect(avecManuel.gainNet, 170.0,
          reason: 'gainRetenu vit à côté de gainNet, il ne le remplace pas');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  J — COMPATIBILITÉ JSON
  // ═════════════════════════════════════════════════════════════════════════

  group('J — JSON : anciens formats préservés, nouveaux conditionnels', () {
    test('J1 — un ANCIEN ticket garde exactement 26 / 28 clés', () {
      // Aucune des deux nouvelles clés n'est renseignée.
      final p = _gpSansGainManuel();
      expect(p.toJson().length, 26,
          reason: 'sans gain manuel, la forme historique est intacte');
      expect(p.toJson().containsKey('montantGainManuel'), isFalse);
      expect(p.toJson().containsKey('idTicketLie'), isFalse);

      final c = _courseSansGainManuel();
      expect(c.toJson().length, 28,
          reason: 'sans gain manuel, la forme historique est intacte');
      expect(c.toJson().containsKey('montantGainManuel'), isFalse);
      expect(c.toJson().containsKey('idTicketLie'), isFalse);
    });

    test('J2 — avec un gain manuel, 28 / 30 clés (les deux ajoutées)', () {
      final p =
          _gpSansGainManuel().copyWith(montantGainManuel: kBrutManuel);
      expect(p.toJson().length, 28, reason: '26 + 2');
      final c =
          _courseSansGainManuel().copyWith(montantGainManuel: kBrutManuel);
      expect(c.toJson().length, 30, reason: '28 + 2');
    });

    test('J3 — 0.0 survit à l\'aller-retour, distinct de l\'absence', () {
      final p = _gpSansGainManuel().copyWith(montantGainManuel: 0.0);
      final relu = UserPrediction.fromJson(
          json.decode(json.encode(p.toJson())) as Map<String, dynamic>);
      expect(relu.montantGainManuel, 0.0,
          reason: 'un 0 € déclaré ne doit PAS redevenir null');
      expect(relu.aGainManuel, isTrue);
      expect(relu.toJson().length, 28);
    });

    test('J4 — aller-retour idempotent (forme stable sur 3 relectures)', () {
      final p = _gpSansGainManuel()
          .copyWith(montantGainManuel: kBrutManuel, idTicketLie: 'R1C6_x');
      final j1 = p.toJson();

      final r1 = UserPrediction.fromJson(
          json.decode(json.encode(j1)) as Map<String, dynamic>);
      final j2 = r1.toJson();
      final r2 = UserPrediction.fromJson(
          json.decode(json.encode(j2)) as Map<String, dynamic>);
      final j3 = r2.toJson();

      expect(j2.length, j1.length, reason: 'aucune clé ajoutée par relecture');
      expect(j3.length, j1.length);
      expect(json.encode(j2), json.encode(j3),
          reason: 'la forme est stable : aucune dérive');
      expect(r1.montantGainManuel, kBrutManuel);
      expect(r1.idTicketLie, 'R1C6_x');
    });

    test('J5 — un ancien JSON sans les clés reste lisible (null, pas 0)', () {
      // Forme historique exacte : aucune clé nouvelle.
      final ancien = <String, dynamic>{
        'id': 'ancien_1',
        'dateStr': '2023-06-01',
        'numReunion': 1,
        'numCourse': 1,
        'nomCourse': 'C',
        'hippodrome': 'H',
        'numeroCheval': 2,
        'nomCheval': 'C2',
        'cote': 4.0,
        'typePari': 'Simple Gagnant',
        'isCorrect': true,
        'montantMise': 5.0,
        'createdAt': DateTime(2023, 6, 1).toIso8601String(),
      };
      final p = UserPrediction.fromJson(ancien);
      expect(p.montantGainManuel, isNull,
          reason: 'clé absente ⇒ null, jamais 0.0');
      expect(p.idTicketLie, isNull);
      expect(p.aGainManuel, isFalse);
      expect(p.toJson().length, 26,
          reason: 'relu puis réécrit : la forme historique est conservée');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L — LIAISON DES TICKETS
  // ═════════════════════════════════════════════════════════════════════════

  group('L — liaison certaine, jamais déduite', () {
    test('L1 — idTicketLie est persisté des deux côtés', () {
      const cleSuivi = 'R1C6_25112026_1700000000000';
      const idProfil = 'R1C6_25112026_1700000000000';

      final suivi = _courseSansGainManuel().copyWith(
        idTicketLie: idProfil,
        montantGainManuel: kBrutManuel,
      );
      final profil = _gpSansGainManuel().copyWith(
        idTicketLie: cleSuivi,
        montantGainManuel: kBrutManuel,
      );

      // Relecture JSON des deux côtés.
      final suiviRelu = TrackedCourse.fromJson(
          json.decode(json.encode(suivi.toJson())) as Map<String, dynamic>);
      final profilRelu = UserPrediction.fromJson(
          json.decode(json.encode(profil.toJson())) as Map<String, dynamic>);

      expect(suiviRelu.idTicketLie, idProfil);
      expect(profilRelu.idTicketLie, cleSuivi);
      expect(suiviRelu.estLieAuProfil, isTrue);
      expect(profilRelu.estLieAuTicket, isTrue);
      // Le gain manuel survit aussi.
      expect(suiviRelu.montantGainManuel, kBrutManuel);
      expect(profilRelu.montantGainManuel, kBrutManuel);
    });

    test('L2 — deux paris sur la MÊME course restent INDÉPENDANTS', () {
      // Même réunion, même course, même jour : bases IDENTIQUES.
      // Seul l'horodatage distingue les deux paris.
      final pariA = _gpSansGainManuel().copyWith(
        id: 'R1C6_25112026_1000',
        idTicketLie: 'R1C6_25112026_1000',
        montantGainManuel: 250.0,
      );
      final pariB = _gpSansGainManuel().copyWith(
        id: 'R1C6_25112026_2000',
        idTicketLie: 'R1C6_25112026_2000',
        // pas de gain manuel : l'autre pari ne doit rien recevoir
      );

      // Leurs bases de course sont bien identiques — c'est le piège.
      expect(pariA.numReunion, pariB.numReunion);
      expect(pariA.numCourse, pariB.numCourse);

      // Mais leurs liaisons et leurs gains sont disjoints.
      expect(pariA.idTicketLie, isNot(pariB.idTicketLie));
      expect(pariA.montantGainManuel, 250.0);
      expect(pariB.montantGainManuel, isNull,
          reason: 'le gain de A ne doit JAMAIS atteindre B');
      expect(pariB.gainRetenuBrut, isNull);
      expect(pariB.aGainManuel, isFalse);
    });

    test('L3 — un ANCIEN ticket reste non lié et garde son gain manuel', () {
      // Aucune liaison : c'est la vérité pour un ticket historique.
      final ancien = _courseSansGainManuel();
      expect(ancien.idTicketLie, isNull);
      expect(ancien.estLieAuProfil, isFalse,
          reason: 'non lié est une information, pas un défaut');

      // Il peut néanmoins porter SON gain manuel.
      final avecGain = ancien.copyWith(montantGainManuel: 88.0);
      expect(avecGain.idTicketLie, isNull,
          reason: 'aucune liaison n\'est inventée par la saisie d\'un gain');
      expect(avecGain.gainRetenuBrut, 88.0);
      expect(avecGain.gainRetenuNet, 68.0, reason: '88 − 20');
    });

    test('L4 — copyWith peut ANNULER un gain manuel (sentinelle)', () {
      final avec = _gpSansGainManuel().copyWith(montantGainManuel: 250.0);
      expect(avec.aGainManuel, isTrue);

      // Retour au calcul automatique : null doit être ÉCRIT, pas ignoré.
      final annule = avec.copyWith(montantGainManuel: null);
      expect(annule.montantGainManuel, isNull,
          reason: 'la sentinelle permet d\'écrire null explicitement');
      expect(annule.aGainManuel, isFalse);

      // Et l'absence d'argument, elle, CONSERVE la valeur.
      final conserve = avec.copyWith(nomCourse: 'AUTRE');
      expect(conserve.montantGainManuel, 250.0,
          reason: 'argument omis ⇒ valeur conservée, pas effacée');
    });
  });
}
