// ═══════════════════════════════════════════════════════════════════════════
//  Z4 — REPRODUCTION DE D2 : SUPPRESSION D'UN SUIVI
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT. AUCUNE MODIFICATION DE lib/.
//      Aucun commit. Aucun push. Aucune correction appliquée.
//
//  ── CE QUI EST REPRODUIT ─────────────────────────────────────────────────
//  Le geste réel « Supprimer ce suivi » de l'écran de détail d'un pari :
//
//      paris_detail_screen.dart:1294
//        widget.alertSvc.retirerSuivi(tc.key);
//
//  et les deux méthodes réelles d'`AlertService` :
//
//      ajouterSuivi()  (alert_service.dart:709-771)
//        → baseKey   = overrideKey ?? course.key     ('R1C10_20112026')
//        → storageKey = '${baseKey}_${millisecondsSinceEpoch}'
//        → _trackedCourses[storageKey] = copie portant storageKey
//
//      retirerSuivi()  (alert_service.dart:763-767)
//        → _trackedCourses.remove(key)
//
//  Le défaut : la clé qui INDEXE la map est la storageKey horodatée, mais le
//  bouton lui passe `tc.key` (sans horodatage). Le `remove` ne trouve rien.
//
//  ── POURQUOI CE N'EST PAS UNE COPIE SIMPLIFIÉE ──────────────────────────
//  Aucun accès aux champs privés : tout passe par `ajouterSuivi`,
//  `retirerSuivi`, `recharger` et `trackedCourses` (API publique réelle).
//  Les clés sont produites par le code de production, jamais recalculées ici.
//
//  ── STATUT ATTENDU : ROUGE ───────────────────────────────────────────────
//  Rouge pour la BONNE raison : les TÉMOINS (deux paris coexistants, clés
//  distinctes, chargement disque) passent AVANT l'assertion métier.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/services/alert_service.dart';

// ───────────────────────────────────────────────────────────────────────────
//  FABRIQUES
// ───────────────────────────────────────────────────────────────────────────

String _ddmmyyyy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

/// Course suivie telle que la produit `bet_bottom_sheet` avant `ajouterSuivi`.
///
/// `heureDepart` à −90 min : largement en deçà du seuil −20 min des écrans
/// et sous la purge 24 h d'`AlertService._load()` (l.517-523).
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
  //  Z4-A — LE BOUTON RÉEL (`tc.key`) NE SUPPRIME RIEN
  // ═══════════════════════════════════════════════════════════════════════
  test('Z4-A / D2 — « Supprimer ce suivi » doit retirer le pari choisi', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AlertService.instance.recharger();
    expect(AlertService.instance.trackedCourses, isEmpty,
        reason: 'TÉMOIN : départ à vide');

    final dep = DateTime.now().subtract(const Duration(minutes: 90));

    // Deux paris RÉELS sur la MÊME course (n°16 puis n°7), comme le permet
    // l'application (bet_bottom_sheet → ajouterSuivi, deux fois).
    await AlertService.instance.ajouterSuivi(_suivi(dep, numeroCheval: 16));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await AlertService.instance.ajouterSuivi(_suivi(dep, numeroCheval: 7));

    final apresAjout = AlertService.instance.trackedCourses;
    expect(apresAjout.length, 2,
        reason: 'TÉMOIN : deux paris sur la même course doivent coexister');

    final cles = apresAjout.keys.toList();
    // ignore: avoid_print
    print('─── MESURE Z4 / D2 ───────────────────────────────────────────');
    // ignore: avoid_print
    print('  clés réelles de stockage : $cles');

    // Le pari que l'utilisateur a ouvert (paris_detail_screen reçoit
    // `tracked: course` = la valeur de la map, donc porteuse de storageKey).
    final tcOuvert = apresAjout[cles.first]!;
    // ignore: avoid_print
    print('  tc.key (utilisé par le bouton) : ${tcOuvert.key}');
    // ignore: avoid_print
    print('  tc.storageKey (clé d\'index)   : ${tcOuvert.storageKey}');
    // ignore: avoid_print
    print('  tc.key == storageKey ? ${tcOuvert.key == tcOuvert.storageKey}');

    // GESTE RÉEL — paris_detail_screen.dart:1294
    await AlertService.instance.retirerSuivi(tcOuvert.key);

    final apresSuppression = AlertService.instance.trackedCourses;
    // ignore: avoid_print
    print('  après retirerSuivi(tc.key)     : ${apresSuppression.length} entrée(s)');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    expect(apresSuppression.length, 1,
        reason: 'D2 (paris_detail_screen.dart:1294) — le bouton passe `tc.key` '
            '(« ${tcOuvert.key} ») alors que la map est indexée par '
            '`storageKey` (« ${tcOuvert.storageKey} ») : `Map.remove()` ne '
            'trouve aucune entrée, AUCUN suivi n\'est supprimé.');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  Z4-B — AVEC LA storageKey, LA BONNE ENTRÉE EST SUPPRIMÉE
  //
  //  Ce test est le CONTRÔLE du précédent : il montre que le défaut est bien
  //  l'identifiant utilisé, et non la suppression elle-même. Il doit être
  //  VERT dès aujourd'hui (aucune correction n'est appliquée).
  // ═══════════════════════════════════════════════════════════════════════
  test('Z4-B / D2 — avec la storageKey, seul le pari visé disparaît', () async {
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

    await AlertService.instance.retirerSuivi(vise.storageKey!);

    final restants = AlertService.instance.trackedCourses;
    expect(restants.length, 2,
        reason: 'avec la bonne clé, une seule entrée est retirée');
    expect(restants.containsKey(vise.storageKey), isFalse,
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

    // ✓ Avec la storageKey : suppression réelle, puis relecture disque.
    await AlertService.instance.retirerSuivi(vise.storageKey!);
    await AlertService.instance.recharger();
    expect(AlertService.instance.trackedCourses.length, 1,
        reason: 'TÉMOIN : la suppression par storageKey survit au rechargement');

    // ✗ Avec la clé du bouton : aucune suppression, donc rien ne persiste
    //   non plus. On repart d'un état à deux paris pour le mesurer.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AlertService.instance.recharger();
    await AlertService.instance.ajouterSuivi(_suivi(dep, numeroCheval: 16));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await AlertService.instance.ajouterSuivi(_suivi(dep, numeroCheval: 7));

    final cles2 = AlertService.instance.trackedCourses.keys.toList();
    final vise2 = AlertService.instance.trackedCourses[cles2[0]]!;
    await AlertService.instance.retirerSuivi(vise2.key);
    await AlertService.instance.recharger();

    // ignore: avoid_print
    print('  Z4-C : après retirerSuivi(tc.key) + rechargement → '
        '${AlertService.instance.trackedCourses.length} entrée(s)');
    expect(AlertService.instance.trackedCourses.length, 1,
        reason: 'D2 — aucune suppression n\'a eu lieu, donc le rechargement '
            'restaure bien les DEUX paris.');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  Z4-D — COMPATIBILITÉ ANCIENNES DONNÉES (sans storageKey)
  //
  //  Ce test explique POURQUOI le défaut est invisible sur les paris
  //  anciens : `_load()` fait `loadKey = tc.storageKey ?? tc.key` (l.507).
  //  Sans storageKey persistée, la clé d'index EST `tc.key`, donc le bouton
  //  tombait juste. Le défaut n'apparaît que sur les paris récents.
  // ═══════════════════════════════════════════════════════════════════════
  test('Z4-D / D2 — ancienne donnée sans storageKey : la clé du bouton suffit', () async {
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
    // ignore: avoid_print
    print('  Z4-D : clé d\'index d\'une ancienne donnée = « $cle »');

    final tc = AlertService.instance.trackedCourses[cle]!;
    expect(tc.storageKey, isNull,
        reason: 'TÉMOIN : aucune storageKey dans l\'ancienne donnée');
    expect(tc.key, cle,
        reason: 'sur une ancienne donnée, tc.key EST la clé d\'index '
            '(alert_service.dart:507) — d\'où l\'absence de symptôme');
    expect(_ddmmyyyyFromJson(jsonAncien), _ddmmyyyy(dep),
        reason: 'TÉMOIN : date de départ relue correctement');
  });
}
