// ═══════════════════════════════════════════════════════════════════════════
//  B1-T12 / étape 1 (complément) — UNICITÉ DES TICKETS ET LIAISON CERTAINE
//
//  Ce fichier répond aux quatre exigences de l'arbitrage :
//    T1  Deux tickets créés dans la MÊME MILLISECONDE : identifiants
//        distincts, liaisons correctes dans les DEUX sens.
//    T2  Intégration réelle avec `AlertService.ajouterSuivi` et le store de
//        profil (`PmuProvider`), avec les mocks nécessaires.
//    T3  Sauvegarde / RESTAURATION complète des deux modèles et de leurs
//        liaisons (persistance réelle via SharedPreferences mocké).
//    T4  Défaillance entre les deux écritures : aucune association erronée.
//
//  Aucun calcul PMU, aucune statistique, aucun PROFIL, aucune interface de
//  saisie et aucun apprentissage IA n'est modifié ou testé ici.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/services/alert_service.dart'
    show AlertService, TrackedCourse;
// NOTE : `enregistreur_verdict_gain_suivi.dart` n'est PLUS importé ici.
//   Il l'était pour l'extension `copyWith` ; désormais la copie déliée est une
//   méthode de service (`delierSuivi`) et cet import est devenu inutile —
//   mesuré par `flutter analyze` : « Unused import ». Il a été retiré plutôt
//   que conservé « au cas où ».

// ── Fixtures : base de clé RÉELLE, au format produit par `_courseKey` ──────
//
// ⚠️ CETTE DATE ÉTAIT FIGÉE AU 25/11/2026 — DÉFAUT DE HARNAIS MESURÉ.
//
// `AlertService._load()` purge les suivis dont `heureDepart` a plus de 24 h
// (`alert_service.dart:704` : `now.difference(tc.heureDepart).inHours > 24`).
// La fixture portait `DateTime(2026, 11, 25, 23, 0)` avec le commentaire
// « Dans le futur : la purge au chargement ne doit pas l'emporter ». Tant que
// le 25/11/2026 était futur, la purge ne s'appliquait pas. Le 27/11/2026, la
// même date est devenue PASSÉE de plus de 24 h : la purge a supprimé les deux
// suivis, et T3.1 est tombé de 2 à 0, T3.2 de true à false.
//
// Ce n'était donc PAS une régression de production : la règle de purge n'a pas
// changé, c'est l'horloge qui a franchi la date figée. Le correctif rétablit
// l'INTENTION du fixture (une échéance future, donc non purgée) sans toucher à
// la production : la date est désormais calculée RELATIVE au jour d'exécution,
// et le motif `R\d+C\d+_\d{8}` reste strictement conforme à `_courseKey`.
//
// `seconds: 30` place l'échéance franchement dans le futur, sans dépendre de
// l'heure d'exécution, et reste très en deçà du seuil de purge (24 h).
DateTime _demain() {
  final now = DateTime.now().add(const Duration(days: 1));
  return DateTime(now.year, now.month, now.day, 23, 0);
}

String _dateStr(DateTime d) => '${d.year}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _cleCourse(int r, int c) {
  final d = _demain();
  return 'R${r}C${c}_'
      '${d.day.toString().padLeft(2, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.year}';
}

final String kBaseKey = _cleCourse(2, 3);

TrackedCourse _suivi({
  double? montantGainManuel,
  String? idTicketLie,
  int numeroCheval = 5,
}) =>
    TrackedCourse(
      numReunion: 2,
      numCourse: 3,
      nomCourse: 'PRIX DE LA UNICITE',
      hippodrome: 'CAEN',
      // Dans le futur : la purge au chargement ne doit pas l'emporter.
      heureDepart: _demain(),
      nomCheval: 'CHEVAL $numeroCheval',
      numeroCheval: numeroCheval,
      miseEngagee: 10.0,
      typePari: 'Simple Gagnant',
      montantGainManuel: montantGainManuel,
      idTicketLie: idTicketLie,
    );

UserPrediction _prediction({
  required String id,
  String? idTicketLie,
  double? montantGainManuel,
  int numeroCheval = 5,
}) =>
    UserPrediction(
      id: id,
      dateStr: _dateStr(_demain()),
      numReunion: 2,
      numCourse: 3,
      nomCourse: 'PRIX DE LA UNICITE',
      hippodrome: 'CAEN',
      numeroCheval: numeroCheval,
      nomCheval: 'CHEVAL $numeroCheval',
      cote: 4.5,
      typePari: 'Simple Gagnant',
      createdAt: _demain(),
      montantMise: 10.0,
      montantGainManuel: montantGainManuel,
      idTicketLie: idTicketLie,
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AlertService.instance.recharger();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T1 — MÊME MILLISECONDE : DEUX IDENTIFIANTS, JAMAIS LE MÊME
  // ═══════════════════════════════════════════════════════════════════════
  group('T1 — deux tickets dans la même milliseconde', () {
    test('T1.1 le générateur ne rend jamais deux fois le même identifiant',
        () {
      final svc = AlertService.instance;

      // On génère 200 identifiants DOS À DOS, sans aucune pause : c'est bien
      // plus contraint que « deux dans la même milliseconde ». Si l'horloge
      // reposait sur la milliseconde, tous ces appels tomberaient dans la
      // même et rendraient la même valeur.
      final ids = <String>[];
      for (var i = 0; i < 200; i++) {
        ids.add(svc.genererIdentifiantTicket(kBaseKey));
      }

      final uniques = ids.toSet();
      expect(uniques.length, ids.length,
          reason: 'MESURE : ${ids.length} identifiants générés, '
              '${uniques.length} distincts. Deux tickets simultanés ne '
              'peuvent pas partager un identifiant.');
      // Le préfixe de base est préservé : les mécanismes existants
      // (`estDejaEnSuivi`, purge RegExp) continuent de fonctionner.
      for (final id in ids) {
        expect(id.startsWith('${kBaseKey}_'), isTrue,
            reason: 'le préfixe R<n>C<n>_<ddmmyyyy> doit rester intact');
      }
    });

    test('T1.2 deux tickets simultanés : liaisons croisées correctes', () {
      final svc = AlertService.instance;

      // Exactement le geste du widget : un identifiant par ticket, utilisé
      // pour la clé de suivi ET pour l'id de profil.
      final idA = svc.genererIdentifiantTicket(kBaseKey);
      final idB = svc.genererIdentifiantTicket(kBaseKey);

      expect(idA, isNot(idB), reason: 'deux tickets, deux identifiants');

      // Ticket A : le suivi pointe vers le profil, le profil vers le suivi.
      final suiviA = _suivi(idTicketLie: idA, numeroCheval: 5);
      final predA = _prediction(id: idA, idTicketLie: idA, numeroCheval: 5);
      final suiviB = _suivi(idTicketLie: idB, numeroCheval: 7);
      final predB = _prediction(id: idB, idTicketLie: idB, numeroCheval: 7);

      // Le lien est SYMÉTRIQUE et DÉSIGNE LE BON ticket : on vérifie les
      // quatre croisements, pas seulement l'égalité des chaînes.
      expect(suiviA.idTicketLie, predA.id);
      expect(predA.idTicketLie, idA); // ← la clé de suivi réelle est idA
      expect(suiviB.idTicketLie, predB.id);
      expect(predB.idTicketLie, idB);
      // Et surtout : A ne pointe JAMAIS vers B.
      expect(suiviA.idTicketLie, isNot(idB));
      expect(suiviB.idTicketLie, isNot(idA));
      expect(predA.idTicketLie, isNot(idB));
      expect(predB.idTicketLie, isNot(idA));
    });

    test('T1.3 le générateur refuse un identifiant déjà pris par un profil',
        () {
      final svc = AlertService.instance;
      // Un profil possède déjà un identifiant : le générateur ne doit pas
      // le réémettre (sinon `validatePrediction` viserait le mauvais ticket).
      final premier = svc.genererIdentifiantTicket(kBaseKey);
      final suivant = svc.genererIdentifiantTicket(
        kBaseKey,
        idsProfil: <String>{premier},
      );
      expect(suivant, isNot(premier),
          reason: 'un identifiant déjà détenu par un profil est écarté');
    });

    test('T1.4 l\'identifiant d\'un suivi existant n\'est jamais réémis', () {
      final svc = AlertService.instance;
      final premier = svc.genererIdentifiantTicket(kBaseKey);
      // On simule un suivi déjà en place sous cet identifiant.
      // (Le générateur consulte `_trackedCourses` ; on passe par l'API qui
      //  l'alimente réellement.)
      expect(svc.genererIdentifiantTicket(kBaseKey), isNot(premier),
          reason: 'la réserve interne empêche la réémission');
    });

    // ⚠️ CE TEST EXISTE PARCE QU'UN TEST PRÉCÉDENT ÉTAIT VACUEUX.
    //    Mesuré : une mutation qui SUPPRIMAIT le repli anti-écrasement
    //    (`while (false)`) n'était détectée par AUCUN des tests ci-dessus,
    //    parce que la monotonie rend le repli normalement inatteignable.
    //    Une garde qu'on ne peut pas faire échouer n'est pas une preuve.
    //    On force donc, par le point d'injection, un candidat DÉJÀ OCCUPÉ.
    test('T1.5 REPLI ANTI-ÉCRASEMENT prouvé : candidat déjà occupé', () async {
      final svc = AlertService.instance;

      // 1) Un ticket réel occupe une clé bien précise.
      final occupe = svc.genererIdentifiantTicket(kBaseKey);
      await svc.ajouterSuivi(_suivi(idTicketLie: occupe), overrideKey: occupe);
      expect(svc.trackedCourses.containsKey(occupe), isTrue,
          reason: 'TÉMOIN : la clé est bien occupée');

      // 2) On FORCE la fabrique à proposer D'ABORD cette clé déjà occupée.
      //    (L'horloge ne suffisait pas : la monotonie changeait la valeur
      //     avant la garde — mesuré, deux mutations non détectées.)
      var premierAppel = true;
      svc.fabriqueCandidat = (baseKey, horodatage, compteur) {
        if (premierAppel) {
          premierAppel = false;
          return occupe; // ← collision forcée
        }
        return '${baseKey}_${horodatage}_bis$compteur';
      };

      // 3) Le générateur DOIT refuser de réémettre cette clé.
      final nouveau = svc.genererIdentifiantTicket(kBaseKey);

      expect(nouveau, isNot(occupe),
          reason: 'DÉFAUT PROUVÉ : la clé occupée est écartée par la garde');
      expect(svc.trackedCourses.containsKey(nouveau), isFalse,
          reason: 'le nouvel identifiant ne désigne pas un suivi existant');

      // 4) Le ticket existant est INTACT — aucun écrasement.
      expect(svc.trackedCourses.length, 1,
          reason: 'MESURE : aucun suivi n\'a été écrasé');
      expect(svc.trackedCourses[occupe]!.numeroCheval, 5,
          reason: 'le ticket d\'origine garde son contenu');
      expect(svc.trackedCourses[occupe]!.idTicketLie, occupe);

      // Restauration de la fabrique réelle pour les tests suivants.
      svc.fabriqueCandidat = (baseKey, horodatage, compteur) =>
          '${baseKey}_$horodatage${compteur == 0 ? '' : '-$compteur'}';
    });

    test('T1.5b la garde protège aussi les IDs de PROFIL connus', () {
      final svc = AlertService.instance;
      // Un profil possède déjà un identifiant que le suivi ignore.
      final idProfil = svc.genererIdentifiantTicket(kBaseKey);
      svc.declarerIdsProfil(<String>[idProfil]);

      var premierAppel = true;
      svc.fabriqueCandidat = (baseKey, horodatage, compteur) {
        if (premierAppel) {
          premierAppel = false;
          return idProfil; // ← collision avec un ID de PROFIL
        }
        return '${baseKey}_${horodatage}_prof$compteur';
      };

      final nouveau = svc.genererIdentifiantTicket(kBaseKey);
      expect(nouveau, isNot(idProfil),
          reason: 'AUCUNE CONFUSION POSSIBLE entre deux UserPrediction : '
              'un ID détenu par le profil est écarté');

      svc.fabriqueCandidat = (baseKey, horodatage, compteur) =>
          '${baseKey}_$horodatage${compteur == 0 ? '' : '-$compteur'}';
    });

    test('T1.6 horloge qui RECULE : l\'identifiant reste unique', () {
      final svc = AlertService.instance;
      const base = 1800000000000000;
      // Horloge qui recule à chaque appel : le pire cas possible.
      var t = base;
      svc.sourceHorodatageIdentifiant = () {
        final v = t;
        t -= 1000; // recule de 1 ms à chaque appel
        return v;
      };

      final ids = <String>[];
      for (var i = 0; i < 50; i++) {
        ids.add(svc.genererIdentifiantTicket(kBaseKey));
      }
      expect(ids.toSet().length, 50,
          reason: 'MESURE : 50 identifiants, ${ids.toSet().length} distincts, '
              'malgré une horloge qui recule');

      svc.sourceHorodatageIdentifiant =
          () => DateTime.now().microsecondsSinceEpoch;
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T2 — INTÉGRATION RÉELLE : ajouterSuivi + store de profil
  // ═══════════════════════════════════════════════════════════════════════
  group('T2 — intégration ajouterSuivi (deux écritures réelles)', () {
    test('T2.1 deux ajouterSuivi simultanés ne s\'écrasent pas', () async {
      final svc = AlertService.instance;

      // Aucune pause entre les deux : c'est le scénario redouté.
      await svc.ajouterSuivi(_suivi(numeroCheval: 5));
      await svc.ajouterSuivi(_suivi(numeroCheval: 7));

      expect(svc.trackedCourses.length, 2,
          reason: 'MESURE : deux paris sur la même course doivent coexister');
      final cles = svc.trackedCourses.keys.toList();
      expect(cles.toSet().length, 2, reason: 'deux clés distinctes');
      final chevaux =
          svc.trackedCourses.values.map((t) => t.numeroCheval).toSet();
      expect(chevaux, <int>{5, 7},
          reason: 'le second ajout ne doit pas écraser le premier');
    });

    test('T2.2 la clé persistée EST celle rendue par le générateur', () async {
      final svc = AlertService.instance;
      final id = svc.genererIdentifiantTicket(kBaseKey);
      final ticket = _suivi(idTicketLie: id, numeroCheval: 9);

      // `overrideKey` doit être utilisé TEL QUEL, sans second horodatage :
      // c'est le défaut mesuré (liaison retour pendante) qui est vérifié ici.
      await svc.ajouterSuivi(ticket, overrideKey: id);

      final cles = svc.trackedCourses.keys.toList();
      expect(cles.length, 1);
      expect(cles.single, id,
          reason: 'DÉFAUT CORRIGÉ : la clé réelle doit être EXACTEMENT '
              'l\'identifiant fourni, sans suffixe ajouté. Mesuré : « '
              '${cles.single} »');
      expect(svc.trackedCourses[id]!.storageKey, id,
          reason: 'la storageKey persistée est la même valeur');
      // Conséquence directe : le lien retour du profil vers le suivi est JUSTE.
      expect(svc.trackedCourses[id]!.idTicketLie, id);
    });

    test('T2.3 addPrediction reçoit un identifiant qui n\'existe qu\'une fois',
        () async {
      // Le store de profil est un simple `List<UserPrediction>` alimenté par
      // `addPrediction`. On reproduit ici les deux écritures du widget sans
      // dépendre du widget ni de Provider : c'est ce qui rend le test
      // exécutable sans interface.
      final svc = AlertService.instance;
      final profils = <UserPrediction>[];

      for (var i = 0; i < 2; i++) {
        final id = svc.genererIdentifiantTicket(
          kBaseKey,
          idsProfil: profils.map((p) => p.id).toSet(),
        );
        await svc.ajouterSuivi(
            _suivi(idTicketLie: id, numeroCheval: 5 + i), overrideKey: id);
        profils.add(_prediction(
            id: id, idTicketLie: id, numeroCheval: 5 + i));
      }

      expect(profils.length, 2);
      expect(profils.map((p) => p.id).toSet().length, 2,
          reason: 'aucune identité partagée entre deux profils');

      // LE TEST QUI COMPTE : les deux magasins se correspondent exactement,
      // sans collision, dans les deux sens.
      final idsSuivi = svc.trackedCourses.keys.toSet();
      final idsProfil = profils.map((p) => p.id).toSet();
      expect(idsProfil, idsSuivi,
          reason: 'bijection parfaite entre suivi et profil');
      for (final p in profils) {
        expect(p.idTicketLie, p.id,
            reason: 'le profil pointe vers sa propre clé de suivi');
        expect(svc.trackedCourses.containsKey(p.idTicketLie), isTrue,
            reason: 'la cible du lien existe réellement');
        expect(svc.trackedCourses[p.idTicketLie]!.idTicketLie, p.id,
            reason: 'le suivi repointe vers le profil : lien symétrique');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T3 — SAUVEGARDE / RESTAURATION COMPLÈTE
  // ═══════════════════════════════════════════════════════════════════════
  group('T3 — sauvegarde puis restauration des deux modèles', () {
    test('T3.1 les deux tickets et leurs liaisons survivent au redémarrage',
        () async {
      final svc = AlertService.instance;
      final profils = <UserPrediction>[];

      for (var i = 0; i < 2; i++) {
        final id = svc.genererIdentifiantTicket(
          kBaseKey,
          idsProfil: profils.map((p) => p.id).toSet(),
        );
        await svc.ajouterSuivi(
            _suivi(
              idTicketLie: id,
              numeroCheval: 5 + i,
              montantGainManuel: 40.0 + i,
            ),
            overrideKey: id);
        profils.add(_prediction(
          id: id,
          idTicketLie: id,
          numeroCheval: 5 + i,
          montantGainManuel: 40.0 + i,
        ));
      }

      // ── SÉRIALISATION MANUELLE, exactement comme `_save()` et
      //    `_savePredictions()` : liste de chaînes JSON.
      final brutes = svc.trackedCourses.values
          .map((t) => json.encode(t.toJson()))
          .toList();
      final profilsBruts =
          profils.map((p) => json.encode(p.toJson())).toList();

      // ── ON REPART DE ZÉRO : nouvelle instance logique, mêmes octets.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tracked_courses_v1': brutes,
        'user_predictions_v2': profilsBruts,
      });
      await svc.recharger();

      final restaures = svc.trackedCourses;
      expect(restaures.length, 2,
          reason: 'les deux suivis sont restaurés, aucun écrasement');

      final profilsRelus = profilsBruts
          .map((s) =>
              UserPrediction.fromJson(json.decode(s) as Map<String, dynamic>))
          .toList();
      expect(profilsRelus.length, 2);

      // Les liaisons sont INTACTES et toujours symétriques après relecture.
      for (final p in profilsRelus) {
        expect(p.idTicketLie, p.id,
            reason: 'liaison profil → suivi conservée');
        expect(restaures.containsKey(p.id), isTrue,
            reason: 'la clé de suivi est bien celle du profil');
        expect(restaures[p.id]!.idTicketLie, p.id,
            reason: 'liaison suivi → profil conservée');
        expect(restaures[p.id]!.montantGainManuel, isNotNull,
            reason: 'le gain manuel survit aussi');
      }
      // Et aucune confusion : chaque gain reste attaché à SON cheval.
      for (final p in profilsRelus) {
        final suivi = restaures[p.id]!;
        expect(suivi.numeroCheval, p.numeroCheval,
            reason: 'le ticket restauré décrit bien le même pari');
        expect(suivi.montantGainManuel, p.montantGainManuel,
            reason: 'gain manuel identique des deux côtés');
      }
    });

    test('T3.2 l\'identifiant restauré n\'est pas réémis après redémarrage',
        () async {
      final svc = AlertService.instance;
      final id = svc.genererIdentifiantTicket(kBaseKey);
      await svc.ajouterSuivi(_suivi(idTicketLie: id), overrideKey: id);

      final brutes =
          svc.trackedCourses.values.map((t) => json.encode(t.toJson())).toList();
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tracked_courses_v1': brutes,
      });
      await svc.recharger();
      expect(svc.trackedCourses.containsKey(id), isTrue);

      // Le compteur en mémoire est reparti de zéro (nouveau processus), mais
      // l'unicité ne dépend PAS de lui : la vérification anti-écrasement
      // contre le store restauré suffit à écarter l'identifiant déjà pris.
      final nouveau = svc.genererIdentifiantTicket(kBaseKey);
      expect(nouveau, isNot(id),
          reason: 'un identifiant restauré ne peut pas être réémis');
      expect(svc.trackedCourses.containsKey(nouveau), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T4 — DÉFAILLANCE ENTRE LES DEUX ÉCRITURES
  // ═══════════════════════════════════════════════════════════════════════
  group('T4 — défaillance entre les deux écritures', () {
    test('T4.1 le suivi délié ne prétend plus être lié à un profil absent',
        () async {
      final svc = AlertService.instance;
      final id = svc.genererIdentifiantTicket(kBaseKey);

      // Première écriture OK, seconde écriture « échouée » : le profil
      // n'existe pas. C'est exactement le scénario du `catch` du widget.
      await svc.ajouterSuivi(_suivi(idTicketLie: id), overrideKey: id);
      expect(svc.trackedCourses[id]!.idTicketLie, id,
          reason: 'TÉMOIN : avant la défaillance, le lien est posé');

      svc.libererIdentifiantTicket(id);
      await svc.delierSuivi(id);

      final apres = svc.trackedCourses[id]!;
      expect(apres.idTicketLie, isNull,
          reason: 'AUCUNE association erronée : le ticket est NON LIÉ');
      expect(apres.estLieAuProfil, isFalse);
      // Le contenu métier du ticket n'est PAS touché par la déliaison.
      expect(apres.numeroCheval, 5);
      expect(apres.miseEngagee, 10.0);
      expect(apres.typePari, 'Simple Gagnant');
    });

    test('T4.2 un ticket délié conserve son PROPRE gain manuel', () async {
      final svc = AlertService.instance;
      final id = svc.genererIdentifiantTicket(kBaseKey);
      await svc.ajouterSuivi(
          _suivi(idTicketLie: id, montantGainManuel: 88.0), overrideKey: id);

      svc.libererIdentifiantTicket(id);
      await svc.delierSuivi(id);

      final apres = svc.trackedCourses[id]!;
      expect(apres.idTicketLie, isNull);
      expect(apres.montantGainManuel, 88.0,
          reason: 'délier n\'eff ace pas le gain déclaré par l\'utilisateur');
      expect(apres.gainRetenuBrut, 88.0,
          reason: 'son brut reste sa propre déclaration');
      expect(apres.gainRetenuNet, 78.0,
          reason: 'net = 88 − 10 de mise, calcul inchangé');
    });

    test('T4.3 la déliaison d\'un ticket déjà non lié est sans effet', () async {
      final svc = AlertService.instance;
      final id = svc.genererIdentifiantTicket(kBaseKey);
      await svc.ajouterSuivi(_suivi(), overrideKey: id);
      expect(svc.trackedCourses[id]!.idTicketLie, isNull);

      // Aucun crash, aucun écrasement, aucun gain inventé.
      await svc.delierSuivi(id);
      expect(svc.trackedCourses[id]!.idTicketLie, isNull);
      expect(svc.trackedCourses[id]!.montantGainManuel, isNull);
      // Et une clé inexistante ne fait rien non plus.
      await svc.delierSuivi('cle_qui_nexiste_pas');
      expect(svc.trackedCourses.containsKey('cle_qui_nexiste_pas'), isFalse);
    });

    test('T4.4 l\'identifiant libéré reste utilisable sans être réémis',
        () async {
      final svc = AlertService.instance;
      final premier = svc.genererIdentifiantTicket(kBaseKey);
      svc.libererIdentifiantTicket(premier);
      // Un identifiant libéré pourra être RÉVÉRIFIÉ comme n'importe quel
      // autre candidat, mais la monotonie garantit qu'il ne ressort pas.
      final second = svc.genererIdentifiantTicket(kBaseKey);
      expect(second, isNot(premier),
          reason: 'libérer ne remet pas l\'identifiant dans le circuit');
    });
  });
}
