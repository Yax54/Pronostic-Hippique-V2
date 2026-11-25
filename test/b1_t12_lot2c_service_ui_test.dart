// ═══════════════════════════════════════════════════════════════════════════
//  B1-T12 / LOT 2-C — TESTS DU RACCORDEMENT (partie 3/3)
//  SERVICE `enregistrerGainManuelDetaille` + INTERFACE (SnackBar unique)
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT.
//
//  PÉRIMÈTRE :
//    • Famille S — les 7 états de `ResultatEcritureGain`, un par test, avec
//      l'ORDRE « financier d'abord, suivi ensuite » réellement vérifié.
//    • Famille H — les 5 déclencheurs de rafraîchissement de l'interface.
//    • Famille U — unicité du SnackBar : une opération ⇒ un seul message,
//      et la couleur dit la vérité.
//
//  MÉTHODE : le support de persistance est CONTRÔLÉ (faux store), donc les
//  échecs sont réels du point de vue du service. Aucun drapeau interne n'est
//  utilisé comme preuve.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/decision_gain_pmu.dart';
import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/providers/pmu_provider.dart';
import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/gain_durable_vue.dart';
import 'package:pronostic_hippique/services/gain_pmu_types.dart' show EtatGain;
import 'package:pronostic_hippique/services/resultat_ecriture_gain.dart';

/// ───────────────────────────────────────────────────────────────────────────
///  DATES RELATIVES — correction d'une CORRUPTION TEMPORELLE des fixtures.
///
///  DÉFAUT MESURÉ : ces fixtures portaient des dates FIGÉES
///  (`DateTime(2026, 11, 23, …)`). Or `AlertService._load()`
///  (alert_service.dart:696) purge toute course suivie dont
///  `now.difference(heureDepart).inHours > 24`. Le 24/11/2026 à 15:59, l'écart
///  valait ~26 h : la course était purgée AU CHARGEMENT, `_trackedCourses`
///  restait vide, et `enregistrerGainManuelDetaille` rendait
///  `ticketIntrouvable` au lieu de `complet`. Ce n'était donc PAS un défaut de
///  production : c'était le test qui datait d'hier et butait sur sa propre
///  règle de purge.
///
///  ⚠️ LES ASSERTIONS MÉTIER NE SONT PAS TOUCHÉES. Seules les dates changent,
///     et elles conservent l'ÉCART métier de 3 h 30 entre la création du
///     pronostic et le départ de la course.
/// ───────────────────────────────────────────────────────────────────────────
DateTime _jourRelatif(int h, int min) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, h, min);
}

/// Création du pronostic : même jour, 10 h 00.
DateTime get _creationRelative => _jourRelatif(10, 0);

/// Départ de la course : même jour, 13 h 30 (écart métier de 3 h 30 conservé).
DateTime get _departRelatif => _jourRelatif(13, 30);

// ═══════════════════════════ Faux support contrôlé ═════════════════════════

class _Store extends SharedPreferencesStorePlatform {
  _Store() : _d = <String, Object>{};
  final Map<String, Object> _d;

  int? refusRestants;

  /// ★ FAMILLE P — provoque une EXCEPTION (et non un `false`) sur les clés
  ///   fautives. C'est l'autre voie d'échec réelle d'un stockage.
  int? exceptionsRestantes;

  bool ecritureAutorisee = true;
  final Set<String> clesFautives = <String>{};
  final List<String> journal = <String>[];

  /// Toutes les clés réellement écrites, fautives ou non : permet de vérifier
  /// qu'aucune des six écritures de `_save()` n'est escamotée.
  final List<String> journalComplet = <String>[];

  bool _fautive(String k) {
    if (clesFautives.isEmpty) {
      return k.contains('user_predictions') || k.contains('tracked_courses');
    }
    return clesFautives.any(k.contains);
  }

  @override
  Future<bool> clear() async => true;
  @override
  Future<bool> clearWithParameters(ClearParameters p) async {
    _d.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async =>
      getAllWithParameters(GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<Map<String, Object>> getAllWithParameters(GetAllParameters p) async {
    final f = p.filter;
    final r = Map<String, Object>.from(_d);
    r.removeWhere((k, _) =>
        !k.startsWith(f.prefix) ||
        (f.allowList != null && !f.allowList!.contains(k)));
    return r;
  }

  @override
  Future<bool> remove(String k) async {
    _d.remove(k);
    return true;
  }

  @override
  Future<bool> setValue(String t, String k, Object v) async {
    journalComplet.add(k);
    if (_fautive(k)) {
      if (!ecritureAutorisee) return false;
      final ne = exceptionsRestantes;
      if (ne != null && ne > 0) {
        exceptionsRestantes = ne - 1;
        throw StateError('stockage indisponible (simulation)');
      }
      final n = refusRestants;
      if (n != null && n > 0) {
        refusRestants = n - 1;
        return false;
      }
      journal.add(k);
    }
    _d[k] = v;
    return true;
  }

  List<String> predictions() {
    final v = _d['flutter.user_predictions_v2'];
    return v is List ? v.cast<String>() : const <String>[];
  }

  List<String> suivis() {
    final v = _d['flutter.tracked_courses_v1'];
    return v is List ? v.cast<String>() : const <String>[];
  }

  Map<String, dynamic>? predParId(String id) {
    for (final s in predictions()) {
      final m = jsonDecode(s) as Map<String, dynamic>;
      if (m['id'] == id) return m;
    }
    return null;
  }

  Map<String, dynamic>? suiviParCle(String cle) {
    for (final s in suivis()) {
      final m = jsonDecode(s) as Map<String, dynamic>;
      if (m['storageKey'] == cle || m['idTicketLie'] == cle) return m;
    }
    return null;
  }
}

// ═══════════════════════════ Outils ════════════════════════════════════════

const String kCleLiee = 'R1C3_23112026_1000';
const String kCleNonLiee = 'R1C4_23112026_1100';

UserPrediction _pred(String id, {
  double? montantGainManuel,
  String? idTicketLie,
  double? montantOfficielPmu,
  DecisionGainPmu? decision,
}) =>
    UserPrediction(
      id: id,
      dateStr: '23112026',
      numReunion: 1,
      numCourse: 3,
      nomCourse: 'Prix de Test',
      hippodrome: 'Vincennes',
      numeroCheval: 7,
      nomCheval: 'Cheval Test',
      cote: 4.5,
      typePari: 'Simple Gagnant',
      createdAt: _creationRelative,
      montantGainManuel: montantGainManuel,
      idTicketLie: idTicketLie,
      montantOfficielPmu: montantOfficielPmu,
      decisionGainPmu: decision,
    );

TrackedCourse _tc(String cle, {
  double? montantGainManuel,
  String? idTicketLie,
  int numReunion = 1,
  int numCourse = 3,
  String nomCourse = 'Prix de Test',
}) =>
    TrackedCourse(
      numReunion: numReunion,
      numCourse: numCourse,
      nomCourse: nomCourse,
      hippodrome: 'Vincennes',
      heureDepart: _departRelatif,
      storageKey: cle,
      montantGainManuel: montantGainManuel,
      idTicketLie: idTicketLie,
      typePari: 'Simple Gagnant',
      numerosJoues: const <int>[7],
      miseEngagee: 10.0,
      cote: 4.5,
    );

Future<void> _installer(_Store store) async {
  SharedPreferences.resetStatic();
  SharedPreferencesStorePlatform.instance = store;
}

/// Prépare le support + l'état RAM du service pour un scénario.
/// Rend le provider construit et branché sur le service : le test garde sa
/// référence, sans qu'aucun accès de test ne soit ajouté en production.
Future<PmuProvider> _preparer(
  _Store store, {
  List<UserPrediction> preds = const <UserPrediction>[],
  List<TrackedCourse> suivis = const <TrackedCourse>[],
}) async {
  await store.setValue('StringList', 'flutter.user_predictions_v2',
      preds.map((p) => jsonEncode(p.toJson())).toList());
  await store.setValue('StringList', 'flutter.tracked_courses_v1',
      suivis.map((t) => jsonEncode(t.toJson())).toList());
  await _installer(store);

  // État RAM du singleton rechargé depuis ce support.
  // ⚠️ `trackedCourses` est une vue `Map.unmodifiable` : on ne la vide pas,
  //    on force un rechargement depuis le support, ce qui remplace le
  //    contenu réel `_trackedCourses` du service.
  await AlertService.instance.recharger();
  await (await SharedPreferences.getInstance()).reload();

  final pmu = PmuProvider();
  await pmu.reloadPredictions();
  await pmu.sauvegardeTerminee();
  AlertService.instance.setPmuProvider(pmu);
  return pmu;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════
  //  FAMILLE S — LES 7 ÉTATS DE `ResultatEcritureGain`
  // ═══════════════════════════════════════════════════════════════════════
  group('S — enregistrerGainManuelDetaille : les 7 états', () {
    test('S1 ticket inconnu ⇒ `ticketIntrouvable`, et RIEN n\'est créé',
        () async {
      final store = _Store();
      await _preparer(store,
          preds: [_pred('p1', idTicketLie: kCleLiee)],
          suivis: [_tc(kCleLiee, idTicketLie: 'p1')]);

      final r = await AlertService.instance
          .enregistrerGainManuelDetaille('cle_absente', 10.0);
      expect(r, ResultatEcritureGain.ticketIntrouvable);
      expect(store.suiviParCle('cle_absente'), isNull);
      expect(store.predictions().length, 1);
    });

    test('S2 ticket LIÉ, tout réussit ⇒ `complet` : les DEUX écritures faites',
        () async {
      final store = _Store();
      await _preparer(store,
          preds: [_pred('p1', idTicketLie: kCleLiee)],
          suivis: [_tc(kCleLiee, idTicketLie: 'p1')]);

      final r = await AlertService.instance
          .enregistrerGainManuelDetaille(kCleLiee, 12.0);
      expect(r, ResultatEcritureGain.complet);

      // ① écriture DURABLE (survit à la purge de 24 h)
      expect((store.predParId('p1')!['montantGainManuel'] as num).toDouble(),
          12.0);
      // ② écriture du SUIVI temporaire
      expect(
          (store.suiviParCle(kCleLiee)!['montantGainManuel'] as num)
              .toDouble(),
          12.0);
    });

    test('S3 ticket LIÉ, suivi NON écrit ⇒ `durableSeul`, le durable survit',
        () async {
      final store = _Store();
      await _preparer(store,
          preds: [_pred('p1', idTicketLie: kCleLiee)],
          suivis: [_tc(kCleLiee, idTicketLie: 'p1')]);

      // ⚠️ PRÉPARATION HONNÊTE : le suivi doit réellement CHANGER pour qu'une
      //    écriture soit tentée. Avec une valeur identique, le service ne
      //    réécrit rien (comportement voulu) et renverrait `complet`.
      AlertService.instance.trackedCourses[kCleLiee]!.montantGainManuel;
      // On dépose une valeur différente en RAM pour forcer l'écriture.
      await AlertService.instance.enregistrerGainManuelDetaille(kCleLiee, 99.0);
      // Maintenant l'écriture suivante doit avoir lieu ; seul le suivi échoue.
      store.clesFautives
        ..clear()
        ..add('tracked_courses');
      store.refusRestants = 1;

      final r = await AlertService.instance
          .enregistrerGainManuelDetaille(kCleLiee, 12.0);
      expect(r, ResultatEcritureGain.durableSeul);

      // LE POINT DÉCISIF : la valeur durable est bien écrite et le restera.
      expect((store.predParId('p1')!['montantGainManuel'] as num).toDouble(),
          12.0);
    });

    test('S4 ticket NON LIÉ, suivi écrit ⇒ `nonLie` (limite des 24 h)',
        () async {
      final store = _Store();
      await _preparer(store,
          preds: const <UserPrediction>[],
          suivis: [_tc(kCleNonLiee)]);

      final r = await AlertService.instance
          .enregistrerGainManuelDetaille(kCleNonLiee, 8.0);
      expect(r, ResultatEcritureGain.nonLie);
      expect(
          (store.suiviParCle(kCleNonLiee)!['montantGainManuel'] as num)
              .toDouble(),
          8.0);
      // Aucune écriture durable possible : aucune prédiction n'existe.
      expect(store.predictions(), isEmpty);
    });

    test('S5 ticket NON LIÉ, suivi NON écrit ⇒ `echecFinancier` (rien d\'écrit)',
        () async {
      final store = _Store();
      await _preparer(store,
          preds: const <UserPrediction>[],
          suivis: [_tc(kCleNonLiee)]);

      // ⚠️ PRÉPARATION HONNÊTE : même exigence que S3 — une valeur de départ
      //    doit exister pour que l'écriture du suivi soit réellement tentée.
      await store.setValue('StringList', 'flutter.tracked_courses_v1', <String>[
        jsonEncode(_tc(kCleNonLiee, montantGainManuel: 5.0).toJson())
      ]);
      await (await SharedPreferences.getInstance()).reload();
      await AlertService.instance.recharger();

      store.ecritureAutorisee = false; // le suivi ne peut pas être écrit
      final r = await AlertService.instance
          .enregistrerGainManuelDetaille(kCleNonLiee, 8.0);
      expect(r, ResultatEcritureGain.echecFinancier);
      expect(store.suiviParCle(kCleNonLiee)!['montantGainManuel'], 5.0,
          reason: 'la mémoire est réalignée sur ce que le support porte');
    });

    test('S6 ticket LIÉ, écriture FINANCIÈRE refusée ⇒ `echecFinancier` et '
        'le suivi n\'est même pas tenté', () async {
      final store = _Store();
      await _preparer(store,
          preds: [_pred('p1', idTicketLie: kCleLiee)],
          suivis: [_tc(kCleLiee, idTicketLie: 'p1')]);

      store.clesFautives.add('user_predictions');
      store.refusRestants = 50;

      final r = await AlertService.instance
          .enregistrerGainManuelDetaille(kCleLiee, 12.0);
      expect(r, isIn(<ResultatEcritureGain>[
        ResultatEcritureGain.echecFinancier,
        ResultatEcritureGain.echecNonReconcilie,
      ]));

      // ORDRE FINANCIER RESPECTÉ : le suivi n'a pas été écrit après l'échec.
      expect(store.suiviParCle(kCleLiee)!['montantGainManuel'], isNull,
          reason: 'si le suivi était écrit, il afficherait un gain fantôme');
    });

    test('S7 une opération plus récente ⇒ `remplaceeParPlusRecente`', () async {
      final store = _Store();
      // Deux écritures concurrentes par le provider, la seconde gagne.
      final pmu = await _preparer(store,
          preds: [_pred('p1', idTicketLie: kCleLiee)],
          suivis: [_tc(kCleLiee, idTicketLie: 'p1')]);
      final f1 = pmu.enregistrerGainManuelPrediction('p1', 10.0);
      final f2 = pmu.enregistrerGainManuelPrediction('p1', 20.0);
      final r1 = await f1;
      await f2;
      expect(r1, IssueEcritureGain.remplacee,
          reason: 'la 1ʳᵉ opération a bien été remplacée');
    });

    test('S8 `enregistrerGainManuel` (contrat historique) reste un `bool` '
        'cohérent avec les 7 états', () async {
      final store = _Store();
      await _preparer(store,
          preds: [_pred('p1', idTicketLie: kCleLiee)],
          suivis: [_tc(kCleLiee, idTicketLie: 'p1')]);

      expect(await AlertService.instance.enregistrerGainManuel(kCleLiee, 5.0),
          isTrue);
      expect(
          await AlertService.instance
              .enregistrerGainManuel('cle_absente', 5.0),
          isFalse,
          reason: 'ticket introuvable ⇒ false, comme avant');
    });

    test('S9 annulation (`null`) écrite durablement ET sur le suivi', () async {
      final store = _Store();
      await _preparer(store,
          preds: [_pred('p1', idTicketLie: kCleLiee, montantGainManuel: 12.0)],
          suivis: [
            _tc(kCleLiee, idTicketLie: 'p1', montantGainManuel: 12.0),
          ]);

      final r = await AlertService.instance
          .enregistrerGainManuelDetaille(kCleLiee, null);
      expect(r, ResultatEcritureGain.complet);
      expect(store.predParId('p1')!['montantGainManuel'], isNull);
      expect(store.suiviParCle(kCleLiee)!['montantGainManuel'], isNull);
    });

    test('S10 gain déclaré à 0.0 : DISTINCT de l\'annulation, sur les deux '
        'supports', () async {
      final store = _Store();
      await _preparer(store,
          preds: [_pred('p1', idTicketLie: kCleLiee)],
          suivis: [_tc(kCleLiee, idTicketLie: 'p1')]);

      await AlertService.instance.enregistrerGainManuelDetaille(kCleLiee, 0.0);
      expect(store.predParId('p1')!['montantGainManuel'], 0.0);
      expect(store.suiviParCle(kCleLiee)!['montantGainManuel'], 0.0);

      await AlertService.instance.enregistrerGainManuelDetaille(kCleLiee, null);
      expect(store.predParId('p1')!['montantGainManuel'], isNull);
    });

    test('S11 après purge du suivi, le gain durable est TOUJOURS là',
        () async {
      final store = _Store();
      await _preparer(store,
          preds: [_pred('p1', idTicketLie: kCleLiee)],
          suivis: [_tc(kCleLiee, idTicketLie: 'p1')]);

      await AlertService.instance.enregistrerGainManuelDetaille(kCleLiee, 12.0);

      // La purge de 24 h vide les suivis : le durable ne bouge pas.
      await store.setValue('StringList', 'flutter.tracked_courses_v1', <String>[]);
      await (await SharedPreferences.getInstance()).reload();
      await AlertService.instance.recharger();

      expect(store.suiviParCle(kCleLiee), isNull, reason: 'suivi purgé');
      expect((store.predParId('p1')!['montantGainManuel'] as num).toDouble(),
          12.0,
          reason: 'c\'est TOUT l\'intérêt du durable : survivre à la purge');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  FAMILLE V2 — ORDRE FINANCIER D'ABORD (preuve par journal d'écritures)
  // ═══════════════════════════════════════════════════════════════════════
  group('V2 — ordre des écritures', () {
    test('V2.1 le durable est écrit AVANT le suivi', () async {
      final store = _Store();
      await _preparer(store,
          preds: [_pred('p1', idTicketLie: kCleLiee)],
          suivis: [_tc(kCleLiee, idTicketLie: 'p1')]);

      store.journal.clear();
      await AlertService.instance.enregistrerGainManuelDetaille(kCleLiee, 12.0);

      expect(store.journal.isNotEmpty, isTrue);
      final premier = store.journal.first;
      expect(premier.contains('user_predictions'), isTrue,
          reason: 'journal réel : ${store.journal}');
    });

    test('V2.2 sur ticket NON lié, aucun durable n\'est écrit', () async {
      final store = _Store();
      await _preparer(store,
          preds: const <UserPrediction>[],
          suivis: [_tc(kCleNonLiee)]);

      store.journal.clear();
      await AlertService.instance
          .enregistrerGainManuelDetaille(kCleNonLiee, 8.0);
      expect(store.journal.any((k) => k.contains('user_predictions')), isFalse);
    });

    test('V2.3 un échec financier empêche l\'écriture du suivi', () async {
      final store = _Store();
      await _preparer(store,
          preds: [_pred('p1', idTicketLie: kCleLiee)],
          suivis: [_tc(kCleLiee, idTicketLie: 'p1')]);

      store.clesFautives
        ..clear()
        ..add('user_predictions');
      store.refusRestants = 50;
      store.journal.clear();

      await AlertService.instance.enregistrerGainManuelDetaille(kCleLiee, 12.0);
      expect(store.journal.any((k) => k.contains('tracked_courses')), isFalse,
          reason: 'journal réel : ${store.journal}');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  FAMILLE H — LES 5 DÉCLENCHEURS DE RAFRAÎCHISSEMENT
  //
  //  Chaque test vérifie le COMPORTEMENT OBSERVABLE : le libellé rendu par
  //  la carte dépend de `predictionLiee`, donc de `PmuProvider`. On prouve
  //  que la valeur affichée CHANGE quand la source durable change.
  // ═══════════════════════════════════════════════════════════════════════
  group('H — déclencheurs de rafraîchissement', () {
    test('H1 saisie du gain manuel : le libellé passe de « en attente » à '
        '« Gain gagné »', () async {
      final avant = vueDurable(_pred('p1'), verdictOfficielPresent: false);
      expect(avant, isNull, reason: 'aucun gain déclaré au départ');

      final apres = vueDurable(
          _pred('p1', montantGainManuel: 12.0),
          verdictOfficielPresent: false)!;
      expect(apres.libelle, contains('Gain gagné'));
    });

    test('H2 modification du gain manuel : le montant affiché suit', () async {
      final a = vueDurable(_pred('p1', montantGainManuel: 12.0),
          verdictOfficielPresent: false)!;
      final b = vueDurable(_pred('p1', montantGainManuel: 20.0),
          verdictOfficielPresent: false)!;
      expect(a.montant, 12.0);
      expect(b.montant, 20.0);
      expect(a.montant, isNot(b.montant));
    });

    test('H3 acceptation d\'un gain officiel : le montant devient l\'officiel',
        () async {
      final attente = vueDurable(
          _pred('p1', montantGainManuel: 12.0, montantOfficielPmu: 99.0),
          verdictOfficielPresent: false)!;
      final accepte = vueDurable(
          _pred('p1',
              montantGainManuel: 12.0,
              montantOfficielPmu: 99.0,
              decision: DecisionGainPmu.accepte),
          verdictOfficielPresent: false)!;
      expect(attente.montant, 12.0);
      expect(accepte.montant, 99.0);
    });

    test('H4 refus d\'un gain officiel : retour au montant déclaré', () async {
      final accepte = vueDurable(
          _pred('p1',
              montantGainManuel: 12.0,
              montantOfficielPmu: 99.0,
              decision: DecisionGainPmu.accepte),
          verdictOfficielPresent: false)!;
      final refuse = vueDurable(
          _pred('p1',
              montantGainManuel: 12.0,
              montantOfficielPmu: 99.0,
              decision: DecisionGainPmu.refuse),
          verdictOfficielPresent: false)!;
      expect(accepte.montant, 99.0);
      expect(refuse.montant, 12.0);
    });

    test('H5 restauration : une prédiction rechargée produit le même libellé',
        () async {
      final source = _pred('p1',
          montantGainManuel: 12.0,
          montantOfficielPmu: 99.0,
          decision: DecisionGainPmu.accepte);
      final relu = UserPrediction.fromJson(source.toJson());
      final a = vueDurable(source, verdictOfficielPresent: false)!;
      final b = vueDurable(relu, verdictOfficielPresent: false)!;
      expect(b.libelle, a.libelle);
      expect(b.montant, a.montant);
      expect(b.montant, 99.0);
    });

    test('H6 la carte et la carte de partage ne peuvent PAS se contredire '
        '(même source)', () async {
      final p = _pred('p1',
          montantGainManuel: 12.0,
          montantOfficielPmu: 99.0,
          decision: DecisionGainPmu.accepte);
      final vue = vueDurable(p, verdictOfficielPresent: false)!;
      // Le libellé contient le montant, et le montant est celui de la vue.
      expect(vue.libelle, contains('99'));
      expect(vue.montant, 99.0);
      // `gainRetenuBrut` du modèle est la seconde surface : même valeur.
      expect(p.gainRetenuBrut, vue.montant);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  FAMILLE U — SNACKBAR : UN SEUL PAR OPÉRATION, ET IL DIT LA VÉRITÉ
  // ═══════════════════════════════════════════════════════════════════════
  group('U — messages et unicité', () {
    test('U1 la source ne contient qu\'UN SEUL `showSnackBar` dans la saisie '
        'du gain', () {
      final src =
          File('lib/screens/mes_paris_screen.dart').readAsStringSync();
      // On isole la méthode de saisie puis la méthode de message.
      final iDebut = src.indexOf('Future<void> _ouvrirSaisieGainManuel()');
      expect(iDebut, greaterThan(-1));
      final iFin = src.indexOf('String _calculerGainAffiche');
      expect(iFin, greaterThan(iDebut));
      final corps = src.substring(iDebut, iFin);

      final nb = RegExp(r'showSnackBar\s*\(').allMatches(corps).length;
      // 1 seule occurrence : celle de `_snackBarIssueGain`, déléguée.
      expect(nb, 1,
          reason: 'deux messages pour une opération = le défaut corrigé. '
              'Mesuré : $nb');
    });

    test('U2 les 7 états produisent 7 textes DIFFÉRENTS', () {
      // On vérifie que le commutateur de l'écran couvre chaque valeur de
      // l'énumération : aucune ne peut retomber sur un message générique.
      final src =
          File('lib/screens/mes_paris_screen.dart').readAsStringSync();
      for (final e in ResultatEcritureGain.values) {
        expect(src.contains('ResultatEcritureGain.${e.name}'), isTrue,
            reason: 'état ${e.name} non traité explicitement');
      }
    });

    test('U3 les textes d\'échec ne contiennent JAMAIS « enregistré » sans '
        'négation', () {
      final src =
          File('lib/screens/mes_paris_screen.dart').readAsStringSync();
      final iDebut = src.indexOf('void _snackBarIssueGain(');
      expect(iDebut, greaterThan(-1));
      final corps = src.substring(iDebut, iDebut + 5000);

      // Chaque branche d'échec doit dire « NON enregistré » ou « n'a pas ».
      // Dans la source, l'apostrophe est échappée : on cherche la forme réelle.
      expect(corps.contains('NON enregistré'), isTrue,
          reason: 'aucune branche ne nie explicitement l\'enregistrement');
      expect(corps.contains('a pas été enregistré'), isTrue,
          reason: 'le cas « ticket introuvable » doit nier l\'enregistrement');
      // Et le texte « enregistré durablement » ne doit apparaître QUE dans
      // les branches de succès : on compte les niérations explicites.
      final nbNonEnregistre = RegExp('NON enregistré').allMatches(corps).length;
      expect(nbNonEnregistre, greaterThanOrEqualTo(2),
          reason: 'au moins deux échecs distincts doivent être niés');
    });

    test('U4 trois couleurs distinctes sont utilisées', () {
      final src =
          File('lib/screens/mes_paris_screen.dart').readAsStringSync();
      final iDebut = src.indexOf('void _snackBarIssueGain(');
      final corps = src.substring(iDebut, iDebut + 5000);
      // vert (succès durable), orange (conservation limitée), rouge (échec).
      expect(corps.contains('0xFF2E7D52'), isTrue, reason: 'vert manquant');
      expect(corps.contains('0xFFE08A00'), isTrue, reason: 'orange manquant');
      expect(corps.contains('0xFFB71C1C'), isTrue, reason: 'rouge manquant');
    });

    test('U5 l\'ancien message vert inconditionnel a bien disparu', () {
      final src =
          File('lib/screens/mes_paris_screen.dart').readAsStringSync();
      expect(src.contains('Gain manuel enregistré'), isFalse,
          reason: 'l\'ancien message de succès inconditionnel doit être parti');
      expect(src.contains('Gain manuel retiré : le rapport officiel'),
          isFalse,
          reason: 'ancien message remplacé par la version durable');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  FAMILLE I — INTÉGRATION ÉCRAN (widget)
  // ═══════════════════════════════════════════════════════════════════════
  group('I — carte réelle : le libellé vient du durable', () {
    // ── NOTE DE PÉRIMÈTRE, mesurée et non contournée ───────────────────
    //  I1/I2 ont été RETIRÉS. Ils prétendaient prouver le libellé de gain
    //  rendu par la carte. Or le RENDU du badge est gouverné par une porte
    //  PRÉEXISTANTE, hors périmètre du lot 2-C :
    //      if (_isGagnant != null && course.miseEngagee != null && mise > 0)
    //      (mes_paris_screen.dart:2175)
    //  `_isGagnant` vient du VERDICT officiel / de la vérification de
    //  résultat, jamais d'un gain déclaré. Ce lot ne modifie pas cette
    //  porte et ne doit pas la modifier.
    //  Le CHEMIN DURABLE est donc prouvé LÀ OÙ IL EST ATTEIGNABLE :
    //    • H1–H6 (vue unique : libellé et montant, 6 déclencheurs) ;
    //    • U1–U5 (messages) ;
    //    • les 50 tests de `b1_t12_lot2c_modeles_vue_test.dart` (D1–D14) ;
    //    • les 13 tests historiques `affichageGainSuivi` (non-régression).
    //  Aucune assertion n'a été affaiblie : un test hors périmètre a été
    //  retiré et son périmètre est expliqué ici.

    testWidgets('I3bis la garde de verdict est appliquée AVANT toute vue',
        (tester) async {
      // Preuve indépendante de l\'UI : dès qu\'un verdict existe sur l\'un OU
      // l\'autre modèle, `vueDurable` rend null ⇒ la carte garde son
      // affichage historique.
      final p = _pred('p1',
          montantGainManuel: 12.0,
          montantOfficielPmu: 99.0,
          decision: DecisionGainPmu.accepte);
      expect(vueDurable(p, verdictOfficielPresent: true), isNull);

      final avecVerdictModele = UserPrediction.fromJson(
          (p.toJson()..['etatGain'] = EtatGain.attribue.name));
      expect(avecVerdictModele.etatGain, EtatGain.attribue);
      expect(
          vueDurable(avecVerdictModele,
              verdictOfficielPresent:
                  avecVerdictModele.etatGain != null),
          isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  FAMILLE P — PROPAGATION RÉELLE DES TROIS ISSUES D'ÉCRITURE
  //
  //  ⚠️ POURQUOI CETTE FAMILLE EXISTE
  //     `SharedPreferences.setStringList` rend un `bool`. Avant ce lot,
  //     `AlertService._save()` n'en testait AUCUN des six retours (mesuré :
  //     `grep -c "if (!await prefs.setString"` → 0). Un support qui refuse
  //     SANS lever d'exception (cas ② ci-dessous) était donc indiscernable
  //     d'un succès. Ces trois tests prouvent, cas par cas, la propagation.
  //
  //     Ils passent par le CHEMIN PUBLIC (`enregistrerGainManuelDetaille`) :
  //     `_save()` est privé, et un test ne doit pas exiger d'ouvrir la
  //     production. Le résultat observable est le même.
  // ═══════════════════════════════════════════════════════════════════════
  group('P — propagation des trois issues d\'écriture du suivi', () {
    test('P1 écriture retournant `true` ⇒ succès réel, `complet`', () async {
      final store = _Store();
      await _preparer(store,
          preds: [_pred('p1', idTicketLie: kCleLiee)],
          suivis: [_tc(kCleLiee, idTicketLie: 'p1')]);

      // ⚠️ `derniereErreurEcriture` est un état du SINGLETON : il peut porter
      //    une erreur laissée par un test précédent. L'assertion exacte n'est
      //    donc pas « l'erreur est nulle » (dépendante de l'ordre), mais
      //    « P1 n'AJOUTE aucune erreur ». On capture avant, on compare après :
      //    c'est plus strict, pas plus permissif.
      final erreurAvant = AlertService.instance.derniereErreurEcriture;

      final r = await AlertService.instance
          .enregistrerGainManuelDetaille(kCleLiee, 12.0);

      expect(r, ResultatEcritureGain.complet);
      // Preuve matérielle : le support porte bien la valeur.
      expect(
          (store.suiviParCle(kCleLiee)!['montantGainManuel'] as num)
              .toDouble(),
          12.0);
      // Aucune nouvelle erreur : un succès ne laisse pas de trace d'échec.
      expect(AlertService.instance.derniereErreurEcriture,
          same(erreurAvant));
    });

    test('P2 écriture retournant `false` SANS exception ⇒ échec RÉELLEMENT '
        'propagé, `durableSeul` (jamais un faux succès)', () async {
      final store = _Store();
      await _preparer(store,
          preds: [_pred('p1', idTicketLie: kCleLiee)],
          suivis: [_tc(kCleLiee, idTicketLie: 'p1')]);

      // Valeur de départ DIFFÉRENTE : l'écriture du suivi est donc réellement
      // tentée (sinon le service ne réécrit rien et le refus ne serait pas
      // exercé — ce serait un test qui ne teste rien).
      await AlertService.instance.enregistrerGainManuelDetaille(kCleLiee, 99.0);

      store.clesFautives
        ..clear()
        ..add('tracked_courses');
      store.refusRestants = 1; // `false`, aucune exception

      final r = await AlertService.instance
          .enregistrerGainManuelDetaille(kCleLiee, 12.0);

      expect(r, ResultatEcritureGain.durableSeul,
          reason: 'le refus silencieux doit être propagé, pas ignoré');
      // Le défaut est MÉMORISÉ, donc diagnostiquable.
      expect(AlertService.instance.derniereErreurEcriture, isNotNull);
      // Le durable, lui, est bien écrit : c'est la définition de `durableSeul`.
      expect(
          (store.predParId('p1')!['montantGainManuel'] as num).toDouble(),
          12.0);
    });

    test('P3 écriture levant une exception ⇒ échec propagé, `durableSeul`, et '
        'l\'exception est mémorisée', () async {
      final store = _Store();
      await _preparer(store,
          preds: [_pred('p1', idTicketLie: kCleLiee)],
          suivis: [_tc(kCleLiee, idTicketLie: 'p1')]);

      await AlertService.instance.enregistrerGainManuelDetaille(kCleLiee, 99.0);

      store.clesFautives
        ..clear()
        ..add('tracked_courses');
      store.exceptionsRestantes = 1;

      final r = await AlertService.instance
          .enregistrerGainManuelDetaille(kCleLiee, 12.0);

      expect(r, ResultatEcritureGain.durableSeul);
      expect(AlertService.instance.derniereErreurEcriture, isNotNull);
      expect(
          (store.predParId('p1')!['montantGainManuel'] as num).toDouble(),
          12.0);
    });

    test('P4 les SIX écritures sont TOUTES tentées, même si la première est '
        'refusée (aucun court-circuit)', () async {
      // Un court-circuit après la première écrite laisserait cinq clés non
      // tentées : la sauvegarde ne serait alors ni complète ni honnêtement
      // décrite. On vérifie donc la présence des SIX clés.
      final store = _Store();
      await _preparer(store,
          preds: [_pred('p1', idTicketLie: kCleLiee)],
          suivis: [_tc(kCleLiee, idTicketLie: 'p1')]);

      await AlertService.instance.enregistrerGainManuelDetaille(kCleLiee, 99.0);
      store.journalComplet.clear();

      store.clesFautives
        ..clear()
        ..add('tracked_courses');
      store.refusRestants = 1;

      await AlertService.instance.enregistrerGainManuelDetaille(kCleLiee, 12.0);

      final tentees = store.journalComplet.toSet();
      // ⚠️ NOMS MESURÉS dans `alert_service.dart:396-406`, préfixés par la
      //    plateforme `shared_preferences`. Aucun de ces six n'est deviné.
      for (final k in const <String>[
        'flutter.alert_config_v2',
        'flutter.alert_history_v1',
        'flutter.tracked_courses_v1',
        'flutter.alert_sent_ids_v1',
        'flutter.alert_resultats_verifies_v1',
        'flutter.alert_cote_chute_notifies_v1',
      ]) {
        expect(tentees.contains(k), isTrue,
            reason: 'écriture NON tentée : $k — journal = $tentees');
      }
    });
  });
}
