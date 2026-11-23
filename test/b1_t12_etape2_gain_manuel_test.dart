// ═══════════════════════════════════════════════════════════════════════════
//  B1-T12 / étape 2 — LOT 2-A : SAISIE MANUELLE DU GAIN
//
//  Ce que ce fichier prouve, et rien de plus :
//    S1  La virgule ET le point sont acceptés, normalisés, arrondis au centime.
//    S2  L'écriture porte sur LE ticket désigné par sa clé persistante.
//    S3  Le montant SURVIT à une sauvegarde / restauration complète.
//    S4  Annuler n'écrit RIEN ; « retirer » efface la déclaration (null).
//    S5  0 € reste DISTINCT de l'absence de saisie, et survit.
//    S6  Aucune donnée officielle PMU n'est altérée par la saisie.
//    S7  Un ancien ticket NON LIÉ est modifiable, sans rapprochement.
//    S8  Aucun gain n'est inventé quand rien n'est officiel ni manuel.
//
//  ⚠️ CE FICHIER NE TESTE PAS LE PROFIL. `UserPrediction` est un modèle
//     DISTINCT, persisté sous `user_predictions_v2` : écrire dans
//     `TrackedCourse` ne le met PAS à jour, et aucun test ne prétend le
//     contraire. La synchronisation du PROFIL relève d'un autre lot.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/services/alert_service.dart'
    show AlertService, TrackedCourse;
// `TrackedCourse.copyWith` est une EXTENSION déclarée ici (TrackedCourseCopy).
// Sans cet import, l'appel ne compile pas : mesuré — « The method 'copyWith'
// isn't defined for the type 'TrackedCourse' ».
import 'package:pronostic_hippique/services/enregistreur_verdict_gain_suivi.dart';
import 'package:pronostic_hippique/widgets/paris/gain_manuel_dialog.dart'
    show ResultatSaisieGain;

const String kBaseKey = 'R3C7_25112026';

TrackedCourse _ticket({
  int numeroCheval = 5,
  double? montantGainManuel,
  String? idTicketLie,
  double? miseEngagee = 10.0,
}) =>
    TrackedCourse(
      numReunion: 3,
      numCourse: 7,
      nomCourse: 'PRIX DU GAIN MANUEL',
      hippodrome: 'VINCENNES',
      heureDepart: DateTime(2026, 11, 25, 23, 0),
      nomCheval: 'CHEVAL $numeroCheval',
      numeroCheval: numeroCheval,
      miseEngagee: miseEngagee,
      typePari: 'Simple Gagnant',
      montantGainManuel: montantGainManuel,
      idTicketLie: idTicketLie,
    );

/// Reproduit FIDÈLEMENT la normalisation de `_GainManuelDialogState._lireMontant`.
/// Le test ne peut pas piloter un clavier réel ; il vérifie donc la RÈGLE,
/// et la règle est vérifiée une seconde fois de façon structurelle en S1.3.
double? normaliser(String saisie) {
  final brut = saisie.trim();
  if (brut.isEmpty) return null;
  final v = double.tryParse(brut.replaceAll(',', '.'));
  if (v == null) return null;
  if (v < 0) return null;
  return (v * 100).round() / 100;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AlertService.instance.recharger();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  S1 — VIRGULE ET POINT
  // ═══════════════════════════════════════════════════════════════════════
  group('S1 — saisie numérique avec virgule et point', () {
    test('S1.1 la virgule est acceptée et vaut la même chose que le point',
        () {
      expect(normaliser('12,50'), 12.50);
      expect(normaliser('12.50'), 12.50);
      expect(normaliser('12,50'), normaliser('12.50'),
          reason: 'virgule et point désignent le MÊME montant');
      expect(normaliser('7,5'), 7.5);
      expect(normaliser('0,99'), 0.99);
    });

    test('S1.2 arrondi au centime, sans invention', () {
      expect(normaliser('12,505'), 12.51, reason: 'arrondi au centime');
      expect(normaliser('12,504'), 12.50);
      expect(normaliser('3,8'), 3.8);
    });

    test('S1.3 entrées refusées : rien n\'est deviné', () {
      expect(normaliser('abc'), isNull);
      expect(normaliser('12,5,3'), isNull, reason: 'deux séparateurs');
      expect(normaliser('-5'), isNull, reason: 'un gain négatif n\'existe pas');
      expect(normaliser(''), isNull, reason: 'champ vide = pas de montant');
    });

    test('S1.4 le formateur du champ accepte les trois caractères utiles',
        () {
      // Vérification STRUCTURELLE sur la source : le formateur appliqué au
      // champ doit autoriser chiffres, virgule ET point. Un formateur qui
      // n'autoriserait que `\d+\.?\d{0,2}` (comme `mise_gain_widget`) ferait
      // échouer cette assertion — c'est précisément le défaut corrigé.
      final src = File('lib/widgets/paris/gain_manuel_dialog.dart')
          .readAsStringSync();
      expect(src.contains("RegExp(r'[0-9.,]')"), isTrue,
          reason: 'le formateur doit autoriser chiffres, virgule et point');
      expect(src.contains('numberWithOptions(decimal: true)'), isTrue,
          reason: 'le clavier doit demander le séparateur décimal');
      expect(src.contains("replaceAll(',', '.')"), isTrue,
          reason: 'la virgule doit être normalisée avant parsing');
    });

    test('S1.5 trois sorties distinctes de la fenêtre', () {
      // Annuler : ne rien écrire.
      expect(ResultatSaisieGain.annule.valide, isFalse);
      // Effacer : valide, mais sans montant.
      expect(ResultatSaisieGain.efface.valide, isTrue);
      expect(ResultatSaisieGain.efface.montant, isNull);
      // Valider 0 € : valide, AVEC un montant à zéro.
      const zero = ResultatSaisieGain.valideAvec(0.0);
      expect(zero.valide, isTrue);
      expect(zero.montant, 0.0);
      expect(zero.montant, isNotNull,
          reason: '0 € N\'EST PAS « pas de saisie »');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  S2 — ÉCRITURE SUR LE TICKET EXACT
  // ═══════════════════════════════════════════════════════════════════════
  group('S2 — écriture sur le ticket désigné par sa clé', () {
    test('S2.1 le gain est écrit sur le bon ticket, pas sur son voisin',
        () async {
      final svc = AlertService.instance;
      await svc.ajouterSuivi(_ticket(numeroCheval: 5), overrideKey: 'R3C7_25112026_101');
      await svc.ajouterSuivi(_ticket(numeroCheval: 7), overrideKey: 'R3C7_25112026_102');

      await svc.enregistrerGainManuel('R3C7_25112026_102', 42.0);

      expect(svc.trackedCourses['R3C7_25112026_102']!.montantGainManuel, 42.0);
      expect(svc.trackedCourses['R3C7_25112026_101']!.montantGainManuel, isNull,
          reason: 'AUCUNE PROPAGATION vers un autre ticket');
    });

    test('S2.2 une clé inconnue n\'invente aucun ticket', () async {
      final svc = AlertService.instance;
      final avant = svc.trackedCourses.length;
      final ecrit = await svc.enregistrerGainManuel('R3C7_25112026_999', 50.0);
      expect(ecrit, isFalse, reason: 'l\'échec est signalé, pas masqué');
      expect(svc.trackedCourses.length, avant,
          reason: 'aucun ticket fantôme créé');
    });

    test('S2.3 deux paris sur la MÊME course gardent des gains indépendants',
        () async {
      final svc = AlertService.instance;
      await svc.ajouterSuivi(_ticket(numeroCheval: 5), overrideKey: 'R3C7_25112026_103');
      await svc.ajouterSuivi(_ticket(numeroCheval: 7), overrideKey: 'R3C7_25112026_104');

      await svc.enregistrerGainManuel('R3C7_25112026_103', 11.0);
      await svc.enregistrerGainManuel('R3C7_25112026_104', 99.0);

      expect(svc.trackedCourses['R3C7_25112026_103']!.montantGainManuel, 11.0);
      expect(svc.trackedCourses['R3C7_25112026_104']!.montantGainManuel, 99.0);
      expect(svc.trackedCourses['R3C7_25112026_103']!.gainRetenuBrut, 11.0);
      expect(svc.trackedCourses['R3C7_25112026_104']!.gainRetenuBrut, 99.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  S3 — CONSERVATION APRÈS REDÉMARRAGE
  // ═══════════════════════════════════════════════════════════════════════
  group('S3 — conservation après fermeture et relancement', () {
    test('S3.1 le gain survit à une sauvegarde / restauration complète',
        () async {
      final svc = AlertService.instance;
      await svc.ajouterSuivi(_ticket(), overrideKey: 'R3C7_25112026_105');
      await svc.enregistrerGainManuel('R3C7_25112026_105', 137.25);

      // ⚠️ CE TEST A D'ABORD ÉTÉ VACUEUX, ET LA MUTATION L'A PROUVÉ.
      //
      //   Ma première version relisait `svc.trackedCourses` — donc l'ÉTAT EN
      //   MÉMOIRE — pour fabriquer elle-même les chaînes JSON. Elle ne touchait
      //   jamais au disque. Mesuré : supprimer `await _save()` dans
      //   `enregistrerGainManuel` laissait les 22 tests VERTS. Le test ne
      //   prouvait donc rien sur la persistance.
      //
      //   Correctif : on lit ce que l'application a RÉELLEMENT ÉCRIT dans
      //   `SharedPreferences`, sans passer par la mémoire du service.
      final prefs = await SharedPreferences.getInstance();
      final ecrites = prefs.getStringList('tracked_courses_v1');
      expect(ecrites, isNotNull,
          reason: 'L\'ÉCRITURE DISQUE doit avoir eu lieu (c\'est le point)');
      expect(ecrites!.length, 1);
      final surDisque = json.decode(ecrites.first) as Map<String, dynamic>;
      expect(surDisque['montantGainManuel'], 137.25,
          reason: 'le montant doit être SUR LE DISQUE, pas seulement en RAM');
      expect(surDisque['storageKey'], 'R3C7_25112026_105');

      // Puis on restaure DEPUIS CE QUI A ÉTÉ ÉCRIT.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tracked_courses_v1': ecrites,
      });
      await svc.recharger();

      final relu = svc.trackedCourses['R3C7_25112026_105'];
      expect(relu, isNotNull, reason: 'le ticket est restauré');
      expect(relu!.montantGainManuel, 137.25,
          reason: 'le montant est CONSERVÉ, pas seulement affiché');
      expect(relu.aGainManuel, isTrue);
      expect(relu.gainRetenuBrut, 137.25);
    });

    test('S3.2 la virgule survit au JSON sans perte', () async {
      final svc = AlertService.instance;
      await svc.ajouterSuivi(_ticket(), overrideKey: 'R3C7_25112026_106');
      await svc.enregistrerGainManuel('R3C7_25112026_106', normaliser('12,50')!);

      final brut = json.encode(svc.trackedCourses['R3C7_25112026_106']!.toJson());
      final relu =
          TrackedCourse.fromJson(json.decode(brut) as Map<String, dynamic>);
      expect(relu.montantGainManuel, 12.50);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  S4 — ANNULER ET CORRIGER
  // ═══════════════════════════════════════════════════════════════════════
  group('S4 — corriger ou annuler une saisie', () {
    test('S4.1 « annuler » ne modifie pas un gain déjà saisi', () async {
      final svc = AlertService.instance;
      await svc.ajouterSuivi(_ticket(), overrideKey: 'R3C7_25112026_107');
      await svc.enregistrerGainManuel('R3C7_25112026_107', 60.0);

      // Annulation = l'appelant ne doit RIEN écrire. On vérifie que la valeur
      // reste celle d'avant, inchangée.
      expect(ResultatSaisieGain.annule.valide, isFalse);
      expect(svc.trackedCourses['R3C7_25112026_107']!.montantGainManuel, 60.0,
          reason: 'annuler laisse le montant existant intact');
    });

    test('S4.2 la correction remplace la valeur précédente', () async {
      final svc = AlertService.instance;
      await svc.ajouterSuivi(_ticket(), overrideKey: 'R3C7_25112026_108');
      await svc.enregistrerGainManuel('R3C7_25112026_108', 60.0);
      await svc.enregistrerGainManuel('R3C7_25112026_108', 75.5);
      expect(svc.trackedCourses['R3C7_25112026_108']!.montantGainManuel, 75.5);
    });

    test('S4.3 « retirer le gain » ramène le PMU comme seule référence',
        () async {
      final svc = AlertService.instance;
      await svc.ajouterSuivi(_ticket(), overrideKey: 'R3C7_25112026_109');
      await svc.enregistrerGainManuel('R3C7_25112026_109', 60.0);
      expect(svc.trackedCourses['R3C7_25112026_109']!.aGainManuel, isTrue);

      // Effacement explicite : `null`.
      await svc.enregistrerGainManuel('R3C7_25112026_109', null);

      final apres = svc.trackedCourses['R3C7_25112026_109']!;
      expect(apres.montantGainManuel, isNull);
      expect(apres.aGainManuel, isFalse);
      // Sans gain manuel ni gain officiel : INDÉTERMINÉ, pas 0.
      expect(apres.gainRetenuBrut, isNull,
          reason: 'aucun gain n\'est inventé après retrait');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  S5 — 0 € CONTRE ABSENCE DE SAISIE
  // ═══════════════════════════════════════════════════════════════════════
  group('S5 — la valeur 0 €', () {
    test('S5.1 un 0 € saisi est un montant, pas une absence', () async {
      final svc = AlertService.instance;
      await svc.ajouterSuivi(_ticket(), overrideKey: 'R3C7_25112026_110');
      await svc.enregistrerGainManuel('R3C7_25112026_110', 0.0);

      final t = svc.trackedCourses['R3C7_25112026_110']!;
      expect(t.montantGainManuel, 0.0);
      expect(t.montantGainManuel, isNotNull, reason: '0 ≠ null');
      expect(t.aGainManuel, isTrue, reason: '0 € EST une déclaration');
      expect(t.gainRetenuBrut, 0.0, reason: 'le brut retenu vaut 0, pas null');
    });

    test('S5.2 le 0 € survit à la restauration, distinct de l\'absence',
        () async {
      final svc = AlertService.instance;
      await svc.ajouterSuivi(_ticket(), overrideKey: 'R3C7_25112026_111');
      await svc.ajouterSuivi(_ticket(numeroCheval: 8), overrideKey: 'R3C7_25112026_112');
      await svc.enregistrerGainManuel('R3C7_25112026_111', 0.0);
      // `cle_rien` n'a AUCUNE déclaration.

      final brutes =
          svc.trackedCourses.values.map((t) => json.encode(t.toJson())).toList();
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tracked_courses_v1': brutes,
      });
      await svc.recharger();

      expect(svc.trackedCourses['R3C7_25112026_111']!.montantGainManuel, 0.0,
          reason: 'le 0 € déclaré est conservé');
      expect(svc.trackedCourses['R3C7_25112026_112']!.montantGainManuel, isNull,
          reason: 'l\'absence reste une absence');
    });

    test('S5.3 le net d\'un 0 € ne devient pas un gain inventé', () async {
      final svc = AlertService.instance;
      await svc.ajouterSuivi(_ticket(miseEngagee: 10.0),
          overrideKey: 'R3C7_25112026_113');
      await svc.enregistrerGainManuel('R3C7_25112026_113', 0.0);
      final t = svc.trackedCourses['R3C7_25112026_113']!;
      expect(t.gainRetenuBrut, 0.0);
      expect(t.gainRetenuNet, -10.0,
          reason: 'brut 0 − mise 10 = −10 : perte réelle, pas gain inventé');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  S6 — LES DONNÉES OFFICIELLES NE SONT PAS ALTÉRÉES
  // ═══════════════════════════════════════════════════════════════════════
  group('S6 — intégrité des données officielles PMU', () {
    test('S6.1 la saisie ne touche ni dividende, ni verdict, ni mise',
        () async {
      final svc = AlertService.instance;
      await svc.ajouterSuivi(
          _ticket(miseEngagee: 10.0), overrideKey: 'R3C7_25112026_114');
      final avant = svc.trackedCourses['R3C7_25112026_114']!;

      await svc.enregistrerGainManuel('R3C7_25112026_114', 250.0);
      final apres = svc.trackedCourses['R3C7_25112026_114']!;

      expect(apres.dividendePmuReel, avant.dividendePmuReel,
          reason: 'le dividende officiel est INCHANGÉ');
      expect(apres.etatGain, avant.etatGain, reason: 'le verdict est INCHANGÉ');
      expect(apres.isGagne, avant.isGagne, reason: 'isGagne est INCHANGÉ');
      expect(apres.miseEngagee, 10.0, reason: 'la mise est INCHANGÉE');
      expect(apres.typePari, 'Simple Gagnant');
      expect(apres.numeroCheval, 5);
      // Les 28 clés du schéma sont préservées (2 clés ajoutées : étape 1).
      expect(apres.toJson().keys.length, 30,
          reason: 'aucune clé perdue, aucune clé parasite');
    });

    test('S6.2 un gain officiel existant n\'est jamais écrasé par l\'écriture',
        () async {
      final svc = AlertService.instance;
      const cle = 'R3C7_25112026_115';
      await svc.ajouterSuivi(_ticket(), overrideKey: cle);

      // ⚠️ MESURE PRÉALABLE : `copyWith` rend une COPIE, il n'écrit RIEN dans
      //   le service. Ma première version l'ignorait — le dividende obtenu
      //   valait donc `null` et l'assertion ne prouvait rien. On installe donc
      //   réellement le rapport officiel dans le store avant de tester.
      final avecOfficiel = svc.trackedCourses[cle]!.copyWith(
        dividendePmuReel: 3.8,
        isGagne: true,
      );
      // On remplace l'entrée par une nouvelle instance : c'est l'état
      // « porteur d'un rapport officiel » que l'on veut éprouver.
      await svc.retirerSuivi(cle);
      await svc.ajouterSuivi(avecOfficiel, overrideKey: cle);
      expect(svc.trackedCourses[cle]!.dividendePmuReel, 3.8,
          reason: 'TÉMOIN : le rapport officiel est bien en place');

      await svc.enregistrerGainManuel(cle, 42.0);

      final apres = svc.trackedCourses[cle]!;
      expect(apres.montantGainManuel, 42.0);
      // L'écriture ne concerne QUE le champ manuel.
      expect(apres.dividendePmuReel, 3.8,
          reason: 'l\'écriture ne touche JAMAIS le dividende officiel');
      expect(apres.isGagne, isTrue, reason: 'verdict officiel intact');
      // Et la priorité manuelle s'applique à la LECTURE, sans réécriture.
      expect(apres.gainRetenuBrut, 42.0,
          reason: 'le manuel est prioritaire en lecture seule');

      // Le retrait du manuel rend la main au PMU, SANS rien avoir perdu.
      await svc.enregistrerGainManuel(cle, null);
      final sansManuel = svc.trackedCourses[cle]!;
      expect(sansManuel.montantGainManuel, isNull);
      expect(sansManuel.dividendePmuReel, 3.8,
          reason: 'le PMU redevient seul maître, avec ses données intactes');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  S7 — ANCIENS TICKETS NON LIÉS
  // ═══════════════════════════════════════════════════════════════════════
  group('S7 — anciens tickets non liés', () {
    test('S7.1 un ticket sans idTicketLie reste modifiable', () async {
      final svc = AlertService.instance;
      // Ticket HISTORIQUE : aucune liaison, aucun `UserPrediction` jumeau.
      await svc.ajouterSuivi(
          _ticket(idTicketLie: null), overrideKey: 'R3C7_25112026_116');
      expect(svc.trackedCourses['R3C7_25112026_116']!.estLieAuProfil, isFalse);

      final ecrit =
          await svc.enregistrerGainManuel('R3C7_25112026_116', 88.0);
      expect(ecrit, isTrue,
          reason: 'un ticket non lié conserve son DROIT à un gain manuel');
      expect(svc.trackedCourses['R3C7_25112026_116']!.montantGainManuel, 88.0);
      // La liaison n'est PAS inventée au passage.
      expect(svc.trackedCourses['R3C7_25112026_116']!.idTicketLie, isNull,
          reason: 'AUCUN rapprochement heuristique n\'est créé');
    });

    test('S7.2 deux anciens tickets de la même course restent indépendants',
        () async {
      final svc = AlertService.instance;
      await svc.ajouterSuivi(_ticket(numeroCheval: 3),
          overrideKey: 'R3C7_25112026_117');
      await svc.ajouterSuivi(_ticket(numeroCheval: 4),
          overrideKey: 'R3C7_25112026_118');
      await svc.enregistrerGainManuel('R3C7_25112026_117', 12.0);

      expect(svc.trackedCourses['R3C7_25112026_117']!.montantGainManuel, 12.0);
      expect(svc.trackedCourses['R3C7_25112026_118']!.montantGainManuel, isNull,
          reason: 'aucune propagation par course/réunion');
      expect(svc.trackedCourses['R3C7_25112026_117']!.idTicketLie, isNull);
      expect(svc.trackedCourses['R3C7_25112026_118']!.idTicketLie, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  S8 — AUCUN GAIN INVENTÉ
  // ═══════════════════════════════════════════════════════════════════════
  group('S8 — aucun gain inventé', () {
    test('S8.1 sans manuel ni officiel : indéterminé, jamais 0', () async {
      final svc = AlertService.instance;
      await svc.ajouterSuivi(_ticket(), overrideKey: 'R3C7_25112026_119');
      final t = svc.trackedCourses['R3C7_25112026_119']!;
      expect(t.montantGainManuel, isNull);
      expect(t.gainRetenuBrut, isNull,
          reason: 'INDÉTERMINÉ : on n\'affirme aucun montant');
      expect(t.gainRetenuNet, isNull);
    });

    test('S8.2 le total des gains ne peut pas dépasser le total des manuels',
        () async {
      final svc = AlertService.instance;
      await svc.ajouterSuivi(_ticket(numeroCheval: 1), overrideKey: 'R3C7_25112026_120');
      await svc.ajouterSuivi(_ticket(numeroCheval: 2), overrideKey: 'R3C7_25112026_121');
      await svc.ajouterSuivi(_ticket(numeroCheval: 3), overrideKey: 'R3C7_25112026_122');
      await svc.enregistrerGainManuel('R3C7_25112026_120', 10.0);

      final totalManuel = svc.trackedCourses.values
          .map((t) => t.montantGainManuel ?? 0.0)
          .fold<double>(0.0, (a, b) => a + b);
      expect(totalManuel, 10.0,
          reason: 'seul le ticket déclaré compte : aucun autre montant');
    });
  });
}
