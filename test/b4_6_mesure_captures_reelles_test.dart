// ═══════════════════════════════════════════════════════════════════════════
//  B-4.6 / D1 — MESURE SUR CAPTURES API RÉELLES (313 courses)
//
//  ⚠️  FICHIER DE MESURE UNIQUEMENT. Aucune modification de production.
//
//  OBJET : mesurer sur des données RÉELLES le taux de rejet du convertisseur
//  `rapportPublieDepuisApi`, et identifier la cause exacte de chaque rejet.
//  Aucune hypothèse n'est faite : tout est compté sur les 313 captures du
//  dossier `/home/user/recherche_pmu/multi`.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/services/gain_ticket_calculator.dart'
    show VarianteRapport, varianteDepuisLibelle;
import 'package:pronostic_hippique/services/pmu_api_service.dart';
import 'package:pronostic_hippique/services/resolution_gain_ticket_pmu.dart';
import 'fixtures/fixture_paths.dart';

final String kDossier = dossierMulti;

void main() {
  test('MESURE — taux de rejet du convertisseur sur les 313 captures réelles',
      () {
    final fichiers = Directory(kDossier)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    var nbBlocs = 0;
    var nbRapportsApi = 0;
    var nbConvertis = 0;
    var nbEcartes = 0;

    // Causes de rejet, comptées séparément.
    var causeCombinaisonVide = 0;
    var causeLibelleIllisible = 0;
    var causeCodeVide = 0;

    // Répartition par libellé rejeté (pour identifier une famille entière).
    final parLibelle = <String, int>{};
    // Répartition par code de bloc des rejets.
    final parCode = <String, int>{};

    var fichiersAvecZeroRapport = 0;
    var fichiersAvecToutEcartes = 0;

    for (final f in fichiers) {
      final corps = f.readAsStringSync();
      final rapports = PmuApiService.decoderRapportsDefinitifs(corps);
      if (rapports.isEmpty) {
        fichiersAvecZeroRapport++;
        continue;
      }
      nbRapportsApi += rapports.length;

      var convertisIci = 0;
      for (final r in rapports) {
        final p = rapportPublieDepuisApi(r);
        if (p != null) {
          convertisIci++;
          nbConvertis++;
          continue;
        }
        nbEcartes++;
        // Reproduit EXACTEMENT les trois gardes de `rapportPublieDepuisApi`.
        final libelle = r.libelleOfficiel.trim();
        final combinaison = r.combinaison.trim();
        if (combinaison.isEmpty) {
          causeCombinaisonVide++;
        } else if (varianteDepuisLibelle(libelle) == VarianteRapport.illisible) {
          causeLibelleIllisible++;
        } else {
          causeCodeVide++;
        }
        parLibelle[libelle.isEmpty ? '<VIDE>' : libelle] =
            (parLibelle[libelle.isEmpty ? '<VIDE>' : libelle] ?? 0) + 1;
        final code = r.codePariOfficiel.isEmpty ? r.typePari : r.codePariOfficiel;
        parCode[code.isEmpty ? '<VIDE>' : code] =
            (parCode[code.isEmpty ? '<VIDE>' : code] ?? 0) + 1;
      }
      final blocsIci = _compterBlocs(corps);
      nbBlocs += blocsIci;
      if (convertisIci == 0) fichiersAvecToutEcartes++;
    }

    final pct = nbRapportsApi == 0
        ? 0.0
        : (nbEcartes * 100.0) / nbRapportsApi;

    // ignore: avoid_print
    print('═══ MESURE SUR CAPTURES RÉELLES ═══');
    // ignore: avoid_print
    print('fichiers lus            : ${fichiers.length}');
    // ignore: avoid_print
    print('blocs API               : $nbBlocs');
    // ignore: avoid_print
    print('rapports API décodés    : $nbRapportsApi');
    // ignore: avoid_print
    print('rapports CONVERTIS       : $nbConvertis');
    // ignore: avoid_print
    print('rapports ÉCARTÉS         : $nbEcartes  (${pct.toStringAsFixed(2)} %)');
    // ignore: avoid_print
    print('  cause combinaison vide : $causeCombinaisonVide');
    // ignore: avoid_print
    print('  cause libellé illisible: $causeLibelleIllisible');
    // ignore: avoid_print
    print('  cause code vide        : $causeCodeVide');
    // ignore: avoid_print
    print('fichiers à 0 rapport     : $fichiersAvecZeroRapport');
    // ignore: avoid_print
    print('fichiers TOUT écarté     : $fichiersAvecToutEcartes');
    // ignore: avoid_print
    print('--- rejets par libellé ---');
    final libellesTries = parLibelle.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in libellesTries) {
      // ignore: avoid_print
      print('  ${e.value.toString().padLeft(4)} × "${e.key}"');
    }
    // ignore: avoid_print
    print('--- rejets par code de bloc ---');
    final codesTries = parCode.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in codesTries) {
      // ignore: avoid_print
      print('  ${e.value.toString().padLeft(4)} × ${e.key}');
    }

    // Garde-fou : la mesure doit être exploitable.
    expect(fichiers.length, greaterThan(300));
    expect(nbRapportsApi, greaterThan(0));
  });
}

int _compterBlocs(String corps) {
  try {
    final d = jsonDecode(corps);
    return d is List ? d.length : 0;
  } catch (_) {
    return 0;
  }
}
