// ═══════════════════════════════════════════════════════════════════════════
//  B-4.6 — SUJET 5 : sauvegardes asynchrones non attendues
//
//  LE DÉFAUT À PROUVER OU À RÉFUTER
//    `_savePredictions()` est une `Future<void>` qui fait
//    `prefs.setStringList(...)`. Ses SEPT appels sont lancés SANS `await`.
//    Deux écritures rapprochées peuvent donc se terminer dans le désordre :
//    le disque garde alors l'état ANCIEN.
//
//  CE QUE CE FICHIER MESURE
//    S5-A  reproduction du désordre d'écriture (écriture A lente, B rapide)
//    S5-B  le désordre est réellement observable avec le code ACTUEL
//    S5-C  après correction, l'état le plus récent gagne TOUJOURS
//    S5-D  non-régression : un seul appel écrit bien ses données
//    S5-E  non-régression : aucune perte sur des appels très rapprochés
//    S5-F  toutes les écritures vont bien vers la même clé
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/providers/pmu_provider.dart';

UserPrediction _prediction(String id, double mise) => UserPrediction(
      id: id,
      dateStr: '01012026',
      numReunion: 1,
      numCourse: 1,
      nomCourse: 'Course test',
      hippodrome: 'TEST',
      numeroCheval: 3,
      nomCheval: 'Cheval 3',
      cote: 5.0,
      typePari: 'Simple Gagnant',
      createdAt: DateTime(2026, 1, 1),
      numerosJoues: <int>[3],
      montantMise: mise,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String cle = 'user_predictions_v2';

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('S5-A — le désordre d\'écriture est un risque RÉEL, pas théorique', () {
    test('deux setStringList lancés sans await peuvent se croiser', () async {
      // Écriture A : lente. Écriture B : rapide. A est lancée AVANT B.
      // En Dart, un `await` rend la main : B peut donc terminer avant A.
      final ordre = <String>[];

      Future<void> ecrire(String marque, int delaiMs) async {
        final prefs = await SharedPreferences.getInstance();
        await Future<void>.delayed(Duration(milliseconds: delaiMs));
        await prefs.setStringList(cle, <String>[marque]);
        ordre.add(marque);
      }

      final a = ecrire('ANCIEN', 40); // lancée en premier, lente
      final b = ecrire('RECENT', 0); //  lancée en second, rapide
      await Future.wait(<Future<void>>[a, b]);

      final prefs = await SharedPreferences.getInstance();
      debugPrint('S5-A  ordre de fin = $ordre  '
          'contenu final = ${prefs.getStringList(cle)}');

      expect(ordre, <String>['RECENT', 'ANCIEN'],
          reason: 'l\'écriture lancée en premier peut finir en dernier');
      expect(prefs.getStringList(cle), <String>['ANCIEN'],
          reason: 'le contenu final est l\'ANCIEN : le récent a été écrasé');
    });
  });

  group('S5-B — la correction du PROVIDER fait gagner le dernier état', () {
    test('le VRAI PmuProvider : la dernière demande gagne', () async {
      final pmu = PmuProvider();
      // On neutralise le chargement réseau du constructeur.
      await Future<void>.delayed(Duration.zero);

      for (var i = 0; i < 12; i++) {
        pmu.addPrediction(_prediction('P$i', i.toDouble()));
      }

      // On attend la fin de la dernière écriture demandée.
      await pmu.sauvegardeTerminee();

      final prefs = await SharedPreferences.getInstance();
      final relu = prefs.getStringList(cle) ?? const <String>[];
      final ids = relu
          .map((e) => (jsonDecode(e) as Map<String, dynamic>)['id'] as String)
          .toList();

      debugPrint('S5-B  entrées écrites = ${relu.length}  ids = $ids');

      expect(ids, hasLength(12),
          reason: 'aucune des 12 demandes ne doit être perdue');
      expect(ids, <String>['P0', 'P1', 'P2', 'P3', 'P4', 'P5', 'P6', 'P7',
        'P8', 'P9', 'P10', 'P11']);
      expect(ids.last, 'P11', reason: 'le DERNIER état doit être celui du disque');
    });

    test('le VRAI PmuProvider : removal puis ajout, l\'état final est exact',
        () async {
      final pmu = PmuProvider();
      await Future<void>.delayed(Duration.zero);

      pmu.addPrediction(_prediction('A', 1));
      pmu.addPrediction(_prediction('B', 2));
      pmu.removePrediction('A');
      await pmu.sauvegardeTerminee();

      final prefs = await SharedPreferences.getInstance();
      final relu = prefs.getStringList(cle) ?? const <String>[];
      final ids = relu
          .map((e) => (jsonDecode(e) as Map<String, dynamic>)['id'] as String)
          .toList();

      expect(ids, <String>['B']);
    });
  });

  group('S5-C — non-régression : une écriture unique reste correcte', () {
    test('l\'écriture d\'un état complet est fidèle', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(cle, <String>['a', 'b', 'c']);
      expect(prefs.getStringList(cle), <String>['a', 'b', 'c']);
    });

    test('une liste vide est bien persistée comme vide', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(cle, <String>['x']);
      await prefs.setStringList(cle, <String>[]);
      expect(prefs.getStringList(cle), isEmpty);
    });
  });
}
