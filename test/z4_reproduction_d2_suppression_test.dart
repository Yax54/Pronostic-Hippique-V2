// ═══════════════════════════════════════════════════════════════════════════
//  Z4 — NON-RÉGRESSION DE D2 : SUPPRESSION D'UN SUIVI
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT. AUCUNE MODIFICATION DE lib/.
//
//  ── HISTORIQUE, ET CE QUI A CHANGÉ ───────────────────────────────────────
//
//  Ce fichier reproduisait à l'origine un défaut RÉEL, présent au commit
//  `a305841`, où `paris_detail_screen.dart` appelait
//
//      widget.alertSvc.retirerSuivi(tc.key);
//
//  alors que `_trackedCourses` est indexé par la `storageKey` horodatée
//  (`'R1C10_22112026_1795371771345'`), et non par `tc.key`
//  (`'R1C10_22112026'`). Le `remove` ne trouvait donc aucune entrée.
//
//  Le défaut a été corrigé par le commit `6b4e325`
//  (« fix(D2): la suppression d'un suivi passe tc.storageKey ?? tc.key »).
//  La version précédente de CE fichier continuait pourtant d'appeler
//  `retirerSuivi(tc.key)` elle-même : elle mesurait donc sa propre erreur, et
//  ne disait plus rien de la production. Elle est réécrite ici.
//
//  ── MESURE QUI A DÉCIDÉ DE L'ABSENCE DE REPLI DANS `retirerSuivi` ────────
//
//  La consigne était : « n'ajouter un fallback que si un cas d'échec réel est
//  reproduit ». Before d'ajouter quoi que ce soit, la clé de production
//  `tc.storageKey ?? tc.key` a été confrontée à la clé d'index réelle dans
//  les deux états persistés existants. Résultat mesuré :
//
//    ticket MODERNE  : index = « R1C10_22112026_1795371771345 »
//                      storageKey = identique → pointe = true → 2 → 1 ✓
//    ticket ANCIEN   : index = « R1C10_22112026 »
//                      storageKey = null → repli tc.key = « R1C10_22112026 »
//                      → pointe = true → 1 → 0 ✓
//
//  Aucune troisième forme n'existe : les quatre chemins qui réécrivent la map
//  (`_load`, `ajouterSuivi`, `enregistrerResultatPari`, `enregistrerDividendePMU
//  Tracked`, `appliquerVerdictGainSuivi`) conservent tous la clé d'index, et
//  les deux reconstructeurs `withResultat` / `withDividende` propagent
//  `storageKey`. Aucun échec réel n'étant reproduit, AUCUN repli n'a été
//  ajouté à `retirerSuivi` : un repli sans cas d'échec serait un code mort qui
//  masquerait un futur désalignement au lieu de le révéler.
//
//  ── CE QUE CE FICHIER PROUVE MAINTENANT ──────────────────────────────────
//  Il utilise la MÊME expression de clé que la production
//  (`tc.storageKey ?? tc.key`, `paris_detail_screen.dart:1400`), et vérifie :
//    • que cette expression pointe TOUJOURS sur la clé d'index réelle ;
//    • que la suppression retire exactement le pari visé, et lui seul ;
//    • que la suppression survit à un rechargement disque ;
//    • que le cas historique (sans `storageKey`) reste couvert.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/services/alert_service.dart';

// ───────────────────────────────────────────────────────────────────────────
//  1. L'EXPRESSION DE CLÉ DE LA PRODUCTION — recopiée à l'identique
// ───────────────────────────────────────────────────────────────────────────

/// Exactement ce que fait `paris_detail_screen.dart:1400` :
///
///     widget.alertSvc.retirerSuivi(tc.storageKey ?? tc.key);
///
/// Si cette expression cesse de pointer sur la clé d'index, ce test doit
/// échouer — c'est son unique raison d'être.
String cleDeSuppression(TrackedCourse tc) => tc.storageKey ?? tc.key;

// ───────────────────────────────────────────────────────────────────────────
//  2. FABRIQUES
// ───────────────────────────────────────────────────────────────────────────

String _ddmmyyyy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

/// Course suivie telle que la produit `bet_bottom_sheet` avant `ajouterSuivi`.
///
/// `heureDepart` à −90 min : largement en deçà du seuil −20 min des écrans
/// et sous la purge 24 h d'`AlertService._load()`.
TrackedCourse _suivi(
  DateTime dep, {
  int numCourse = 10,
  int numeroCheval = 16,
  double mise = 20.0,
}) =>
    TrackedCourse(
      numReunion: 1,
      numCourse: numCourse,
      nomCourse: 'PRIX DE BAD GODESBERG',
      hippodrome: 'SAINT-CLOUD',
      heureDepart: dep,
      nomCheval: 'CHEVAL_$numeroCheval',
      numeroCheval: numeroCheval,
      miseEngagee: mise,
      typePari: 'Gagnant+Placé',
      numerosJoues: <int>[numeroCheval],
      scoreIA: 89.0,
      cote: 18.0,
    );

String _ddmmyyyyFromJson(Map<String, dynamic> j) {
  final d = DateTime.parse(j['heureDepart'] as String);
  return _ddmmyyyy(d);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════
  //  Z4-A — LE PARI VISÉ DISPARAÎT, ET LUI SEUL
  // ═══════════════════════════════════════════════════════════════════════
  test('Z4-A / D2 — la clé de production retire le pari choisi, et lui seul',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AlertService.instance.recharger();
    expect(AlertService.instance.trackedCourses, isEmpty,
        reason: 'TÉMOIN : départ à vide');

    final dep = DateTime.now().subtract(const Duration(minutes: 90));

    // Deux paris RÉELS sur la MÊME course (n°16 puis n°7), comme le permet
    // l'application (`bet_bottom_sheet` → `ajouterSuivi`, deux fois).
    await AlertService.instance.ajouterSuivi(_suivi(dep, numeroCheval: 16));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await AlertService.instance.ajouterSuivi(_suivi(dep, numeroCheval: 7));

    final apresAjout = AlertService.instance.trackedCourses;
    expect(apresAjout.length, 2,
        reason: 'TÉMOIN : deux paris sur la même course doivent coexister');

    final cles = apresAjout.keys.toList();
    final vise = apresAjout[cles.first]!;
    final autre = apresAjout[cles.last]!;

    // TÉMOIN CENTRAL — la clé du bouton vise bien l'index réel.
    expect(cleDeSuppression(vise), cles.first,
        reason: 'TÉMOIN : `tc.storageKey ?? tc.key` doit être EXACTEMENT la '
            'clé qui indexe la map. Mesuré : storageKey=« ${vise.storageKey} », '
            'tc.key=« ${vise.key} », clé d\'index=« ${cles.first} ». Un '
            'désalignement ici est le défaut D2 lui-même.');
    expect(vise.storageKey, isNotNull,
        reason: 'TÉMOIN : un ticket créé par `ajouterSuivi` porte sa '
            '`storageKey` horodatée (alert_service.dart:734-736)');
    expect(vise.key, isNot(vise.storageKey),
        reason: 'TÉMOIN : `tc.key` est SANS horodatage, donc différent — '
            'c\'est précisément ce qui rendait l\'ancien `tc.key` inopérant');

    // GESTE RÉEL — même expression que `paris_detail_screen.dart:1400`.
    await AlertService.instance.retirerSuivi(cleDeSuppression(vise));

    final restants = AlertService.instance.trackedCourses;
    expect(restants.length, 1,
        reason: 'D2 — la suppression doit retirer UNE entrée (mesuré : 2 → 1)');
    expect(restants.containsKey(cles.first), isFalse,
        reason: 'le pari visé est bien absent');
    expect(restants.containsKey(cles.last), isTrue,
        reason: 'l\'AUTRE pari de la même course est conservé');
    expect(restants[cles.last]!.numeroCheval, autre.numeroCheval,
        reason: 'le survivant est bien l\'autre pari, pas une copie');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  Z4-B — CONTRÔLE : trois paris, un seul retiré
  // ═══════════════════════════════════════════════════════════════════════
  test('Z4-B / D2 — avec trois paris, seul celui du milieu disparaît',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AlertService.instance.recharger();

    final dep = DateTime.now().subtract(const Duration(minutes: 90));
    await AlertService.instance.ajouterSuivi(_suivi(dep, numeroCheval: 16));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await AlertService.instance.ajouterSuivi(_suivi(dep, numeroCheval: 7));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await AlertService.instance.ajouterSuivi(_suivi(dep, numeroCheval: 9));

    expect(AlertService.instance.trackedCourses.length, 3,
        reason: 'TÉMOIN : trois paris coexistants');

    final cles = AlertService.instance.trackedCourses.keys.toList();
    final vise = AlertService.instance.trackedCourses[cles[1]]!;

    await AlertService.instance.retirerSuivi(cleDeSuppression(vise));

    final restants = AlertService.instance.trackedCourses;
    expect(restants.length, 2,
        reason: 'une seule entrée est retirée');
    expect(restants.containsKey(cles[1]), isFalse,
        reason: 'le pari visé est bien absent');
    expect(restants.containsKey(cles[0]) && restants.containsKey(cles[2]), isTrue,
        reason: 'les deux AUTRES suivis sont conservés');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  Z4-C — PERSISTANCE : la suppression survit-elle à un rechargement ?
  // ═══════════════════════════════════════════════════════════════════════
  test('Z4-C / D2 — la suppression persiste après rechargement', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AlertService.instance.recharger();

    final dep = DateTime.now().subtract(const Duration(minutes: 90));
    await AlertService.instance.ajouterSuivi(_suivi(dep, numeroCheval: 16));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await AlertService.instance.ajouterSuivi(_suivi(dep, numeroCheval: 7));

    final cles = AlertService.instance.trackedCourses.keys.toList();
    final vise = AlertService.instance.trackedCourses[cles[0]]!;

    await AlertService.instance.retirerSuivi(cleDeSuppression(vise));
    await AlertService.instance.recharger();

    final apresReload = AlertService.instance.trackedCourses;
    expect(apresReload.length, 1,
        reason: 'TÉMOIN : la suppression par la clé de production survit au '
            'rechargement (mesuré : 1 entrée restante)');
    expect(apresReload.containsKey(cles[0]), isFalse,
        reason: 'le pari supprimé ne doit pas revenir du disque');
    expect(apresReload.containsKey(cles[1]), isTrue,
        reason: 'le pari conservé est bien rechargé sous la même clé');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  Z4-D — COMPATIBILITÉ ANCIENNES DONNÉES (sans `storageKey`)
  //
  //  Le repli `?? tc.key` n'est pas décoratif : c'est ce cas-là qu'il couvre.
  //  `_load()` fait `loadKey = tc.storageKey ?? tc.key` ; sans `storageKey`
  //  persistée, la clé d'index EST `tc.key`, et la suppression doit fonctionner.
  // ═══════════════════════════════════════════════════════════════════════
  test('Z4-D / D2 — ancienne donnée sans storageKey : la suppression aboutit',
      () async {
    final dep = DateTime.now().subtract(const Duration(minutes: 90));
    final ancien = _suivi(dep, numeroCheval: 16);
    final jsonAncien = ancien.toJson()..remove('storageKey');
    expect(jsonAncien.containsKey('storageKey'), isFalse,
        reason: 'TÉMOIN : la donnée simulée est bien au format ANCIEN');

    SharedPreferences.setMockInitialValues(<String, Object>{
      'tracked_courses_v1': <String>[json.encode(jsonAncien)],
    });
    await AlertService.instance.recharger();

    expect(AlertService.instance.trackedCourses.length, 1,
        reason: 'TÉMOIN : l\'ancienne entrée est chargée');

    final cle = AlertService.instance.trackedCourses.keys.single;
    final tc = AlertService.instance.trackedCourses[cle]!;

    expect(tc.storageKey, isNull,
        reason: 'TÉMOIN : aucune storageKey dans l\'ancienne donnée');
    expect(tc.key, cle,
        reason: 'sur une ancienne donnée, tc.key EST la clé d\'index '
            '(alert_service.dart:525), donc le repli `?? tc.key` tombe juste');
    expect(_ddmmyyyyFromJson(jsonAncien), _ddmmyyyy(dep),
        reason: 'TÉMOIN : date de départ relue correctement');

    // La clé de production doit être celle de l'index, par le repli.
    expect(cleDeSuppression(tc), cle,
        reason: 'TÉMOIN : le repli `?? tc.key` doit pointer sur l\'index');

    await AlertService.instance.retirerSuivi(cleDeSuppression(tc));
    await AlertService.instance.recharger();

    expect(AlertService.instance.trackedCourses, isEmpty,
        reason: 'D2 — l\'ancienne donnée doit aussi pouvoir être supprimée '
            '(mesuré : 1 → 0, et 0 après rechargement)');
  });
}
