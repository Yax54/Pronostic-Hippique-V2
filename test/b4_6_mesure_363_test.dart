// ═══════════════════════════════════════════════════════════════════════════
//  B-4.6 — MESURE ÉTENDUE : 363 captures réelles + limites de l'échantillon
//
//  ⚠️  FICHIER DE MESURE UNIQUEMENT. Aucune modification de production.
//
//  OBJET : couvrir les DEUX jeux de captures du sandbox, et relever
//  explicitement les LIMITES de l'échantillon (dates, absence d'arrivée).
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/services/gain_ticket_calculator.dart'
    show VarianteRapport, varianteDepuisLibelle;
import 'package:pronostic_hippique/services/pmu_api_service.dart';
import 'package:pronostic_hippique/services/resolution_gain_ticket_pmu.dart';

const String kDossierMulti = '/home/user/recherche_pmu/multi';
const String kDossierRapports = '/home/user/recherche_pmu/rapports';

void main() {
  test('MESURE — 363 captures : conversion, dates, limites', () {
    final multi = _fichiers(kDossierMulti);
    final rapports = _fichiers(kDossierRapports);
    final tous = <File>[...multi, ...rapports];

    var nbRapportsApi = 0;
    var nbConvertis = 0;
    var nbEcartes = 0;
    var fichiersVides = 0;
    var fichiersIllisibles = 0;

    final dates = <String, int>{};
    final libellesRejetes = <String, int>{};
    final codesRejetes = <String, int>{};

    for (final f in tous) {
      final corps = f.readAsStringSync();

      // L'API renvoie-t-elle de l'arrivée dans ces fichiers ?
      if (corps.contains('"arrivee"') || corps.contains('"chevaux"')) {
        dates['_A_ARRIVEE_'] = (dates['_A_ARRIVEE_'] ?? 0) + 1;
      }
      // Date extraite du nom quand elle existe (format _ddmmyyyy.json).
      final m = RegExp(r'_(\d{8})\.json$').firstMatch(f.path);
      if (m != null) {
        dates[m.group(1)!] = (dates[m.group(1)!] ?? 0) + 1;
      }

      List<dynamic>? data;
      try {
        final d = jsonDecode(corps);
        if (d is List) data = d;
      } catch (_) {
        fichiersIllisibles++;
      }
      if (data == null) continue;

      final decoded = PmuApiService.decoderRapportsDefinitifs(corps);
      if (decoded.isEmpty) {
        fichiersVides++;
        continue;
      }
      nbRapportsApi += decoded.length;

      for (final r in decoded) {
        final p = rapportPublieDepuisApi(r);
        if (p != null) {
          nbConvertis++;
          continue;
        }
        nbEcartes++;
        final libelle = r.libelleOfficiel.trim();
        final combinaison = r.combinaison.trim();
        final cle = combinaison.isEmpty
            ? '<COMBINAISON VIDE>'
            : varianteDepuisLibelle(libelle) == VarianteRapport.illisible
                ? '<LIBELLE "${libelle}">'
                : '<CODE>';
        libellesRejetes[cle] = (libellesRejetes[cle] ?? 0) + 1;
        final code =
            r.codePariOfficiel.isEmpty ? r.typePari : r.codePariOfficiel;
        codesRejetes[code.isEmpty ? '<VIDE>' : code] =
            (codesRejetes[code.isEmpty ? '<VIDE>' : code] ?? 0) + 1;
      }
    }

    dates.remove('_A_ARRIVEE_');

    // ignore: avoid_print
    print('═══ MESURE ÉTENDUE — 363 CAPTURES ═══');
    // ignore: avoid_print
    print('multi/     : ${multi.length} fichiers');
    // ignore: avoid_print
    print('rapports/  : ${rapports.length} fichiers');
    // ignore: avoid_print
    print('TOTAL      : ${tous.length} fichiers');
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('fichiers illisibles (JSON) : $fichiersIllisibles');
    // ignore: avoid_print
    print('fichiers à 0 rapport       : $fichiersVides');
    // ignore: avoid_print
    print('rapports API décodés       : $nbRapportsApi');
    // ignore: avoid_print
    print('rapports CONVERTIS          : $nbConvertis');
    // ignore: avoid_print
    print('rapports ÉCARTÉS            : $nbEcartes');
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('─── COUVERTURE TEMPORELLE (dates lisibles dans les noms) ───');
    final ds = dates.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    for (final e in ds) {
      // ignore: avoid_print
      print('  ${e.value.toString().padLeft(4)} × ${e.key}');
    }
    // ignore: avoid_print
    print('  (rapports/ : noms sans date → non datables)');
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('─── ARRIVÉE dans les fichiers ? ───');
    final aArrivee = tous.where((f) {
      final c = f.readAsStringSync();
      return c.contains('"arrivee"') || c.contains('"chevaux"');
    }).length;
    // ignore: avoid_print
    print('  fichiers contenant une arrivée : $aArrivee / ${tous.length}');
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('─── REJETS PAR CAUSE ───');
    if (libellesRejetes.isEmpty) {
      // ignore: avoid_print
      print('  AUCUN REJET');
    } else {
      for (final e in libellesRejetes.entries) {
        // ignore: avoid_print
        print('  ${e.value.toString().padLeft(4)} × ${e.key}');
      }
    }

    expect(tous.length, greaterThan(350));
    expect(nbRapportsApi, greaterThan(0));
  });
}

List<File> _fichiers(String dossier) => Directory(dossier)
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.json'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));
