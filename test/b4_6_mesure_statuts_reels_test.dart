// ═══════════════════════════════════════════════════════════════════════════
//  B-4.6 / D1 — MESURE DU CHEMIN RÉEL : verdict produit → statut d'écriture
//
//  ⚠️  FICHIER DE MESURE UNIQUEMENT. Aucune modification de production.
//
//  OBJET : sur les 313 captures API RÉELLES, construire pour CHAQUE type de
//  pari un ticket GAGNANT (en jouant la combinaison du rapport officiel
//  réellement publié), calculer son verdict par la chaîne réelle
//  `resoudreSuivi`, et COMPTER les statuts d'écriture obtenus.
//
//  Question tranchée : un `nonDetermine` est-il réellement PERSISTÉ en
//  production, ou bien la branche C l'empêche-t-elle systématiquement ?
//
//  ⚠️ Les captures ne contiennent PAS l'arrivée : elles contiennent les
//  rapports. On reconstitue donc une arrivée COHÉRENTE à partir des
//  combinaisons publiées, ce qui suffit pour l'arbitrage de variante.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/branchement_verdict_course.dart';
import 'package:pronostic_hippique/services/enregistreur_verdict_gain_pmu.dart';
import 'package:pronostic_hippique/services/gain_pmu_types.dart';
import 'package:pronostic_hippique/services/pmu_api_service.dart';
import 'package:pronostic_hippique/services/resolution_gain_ticket_pmu.dart';
import 'fixtures/fixture_paths.dart';

final String kDossier = dossierMulti;

final DateTime _heure = DateTime.utc(2026, 11, 15, 14, 30);

TrackedCourse _ticket({
  required String typePari,
  required String code,
  required List<int> numeros,
}) =>
    TrackedCourse(
      numReunion: 1,
      numCourse: 1,
      nomCourse: 'MESURE',
      hippodrome: 'MESURE',
      heureDepart: _heure,
      storageKey: 'MESURE',
      nomCheval: 'MESURE',
      numeroCheval: numeros.first,
      miseEngagee: 2.0,
      typePari: typePari,
      numerosJoues: numeros,
      codePmuOfficiel: code,
      varianteChoisie: typePari.contains('Désordre') ? 'desordre' : 'ordre',
      numerosDansOrdre: numeros,
    );

/// Les types de l'application, avec leur code PMU réel et leur taille.
const Map<String, ({String code, int taille})> kTypes = {
  'Simple Gagnant': (code: 'E_SIMPLE_GAGNANT', taille: 1),
  'Simple Placé': (code: 'E_SIMPLE_PLACE', taille: 1),
  'Couplé Gagnant': (code: 'E_COUPLE_GAGNANT', taille: 2),
  'Couplé Placé': (code: 'E_COUPLE_PLACE', taille: 2),
  'Tiercé Ordre': (code: 'E_TIERCE', taille: 3),
  'Quarté+': (code: 'E_QUARTE_PLUS', taille: 4),
  'Quinté+': (code: 'E_QUINTE_PLUS', taille: 5),
};

void main() {
  test('MESURE — verdicts et statuts d\'écriture sur 313 captures réelles', () {
    final fichiers = Directory(kDossier)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final parStatut = <String, int>{};
    final matrice = <String, Map<String, int>>{};
    var nonDetermineEcrit = 0;
    var nonDetermineRefuse = 0;
    var nonDetermineTotal = 0;
    var casListeConvertieVide = 0;
    var casListeApiVide = 0;
    var fichiersExploites = 0;

    // Combien de courses publient réellement le bloc du type joué ?
    final coursesAvecBloc = <String, int>{};

    for (final f in fichiers) {
      final corps = f.readAsStringSync();
      final rapportsApi = PmuApiService.decoderRapportsDefinitifs(corps);
      if (rapportsApi.isEmpty) {
        casListeApiVide++;
        continue;
      }
      fichiersExploites++;

      final conversion = convertirRapportsApi(rapportsApi);
      if (conversion.rapports.isEmpty) casListeConvertieVide++;

      // Arrivée reconstituée : combinaison du premier rapport lisible.
      final groupes = _groupesDepuisRapports(rapportsApi);
      if (groupes == null) continue;

      final resultat = ResultatOfficielCourse(
        arriveeGroupes: groupes,
        arriveeDefinitive: true,
        rapports: rapportsApi,
      );

      for (final entry in kTypes.entries) {
        final t = entry.value;

        // Le bloc du type joué est-il publié dans cette course ?
        final blocPresent = rapportsApi.any(
            (r) => (r.codePariOfficiel.isNotEmpty ? r.codePariOfficiel : r.typePari) == t.code);
        if (blocPresent) {
          coursesAvecBloc[entry.key] = (coursesAvecBloc[entry.key] ?? 0) + 1;
        }

        // On joue la combinaison du rapport gagnant si le bloc existe,
        // sinon une combinaison plausible (les `taille` premiers de l'arrivée).
        List<int> numeros;
        final duBloc = rapportsApi.firstWhere(
          (r) =>
              (r.codePariOfficiel.isNotEmpty
                  ? r.codePariOfficiel
                  : r.typePari) ==
              t.code,
          orElse: () => rapportsApi.first,
        );
        final nums = _numeros(duBloc.combinaison);
        if (nums != null && nums.length == t.taille) {
          numeros = nums;
        } else {
          final plats = <int>[for (final g in groupes) ...g];
          if (plats.length < t.taille) continue;
          numeros = plats.take(t.taille).toList();
        }

        final ticket = _ticket(
          typePari: entry.key,
          code: t.code,
          numeros: numeros,
        );

        final resolution = resoudreSuivi(ticket: ticket, resultat: resultat);
        final statut = resolution.enregistrement?.statut.name ?? 'aucun';
        final verdictEtat = resolution.verdict?.etat.name ?? 'aucun';

        parStatut[statut] = (parStatut[statut] ?? 0) + 1;
        matrice.putIfAbsent(verdictEtat, () => <String, int>{});
        matrice[verdictEtat]![statut] =
            (matrice[verdictEtat]![statut] ?? 0) + 1;

        if (verdictEtat == EtatGain.nonDetermine.name) {
          nonDetermineTotal++;
          if (statut == StatutEnregistrementVerdict.enregistre.name) {
            nonDetermineEcrit++;
          } else {
            nonDetermineRefuse++;
          }
        }
      }
    }

    // ignore: avoid_print
    print('═══ VERDICTS & STATUTS SUR CAPTURES RÉELLES ═══');
    // ignore: avoid_print
    print('fichiers lus              : ${fichiers.length}');
    // ignore: avoid_print
    print('fichiers avec rapports    : $fichiersExploites');
    // ignore: avoid_print
    print('fichiers API VIDE         : $casListeApiVide');
    // ignore: avoid_print
    print('cas liste CONVERTIE vide  : $casListeConvertieVide');
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('─── courses publiant le bloc joué ───');
    for (final e in kTypes.keys) {
      // ignore: avoid_print
      print('  ${(coursesAvecBloc[e] ?? 0).toString().padLeft(4)} / '
          '$fichiersExploites × $e');
    }
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('─── nonDetermine ───');
    // ignore: avoid_print
    print('total produits            : $nonDetermineTotal');
    // ignore: avoid_print
    print('  dont ÉCRITS             : $nonDetermineEcrit');
    // ignore: avoid_print
    print('  dont REFUSÉS            : $nonDetermineRefuse');
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('─── statuts d\'écriture (tous verdicts) ───');
    final st = parStatut.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in st) {
      // ignore: avoid_print
      print('  ${e.value.toString().padLeft(5)} × ${e.key}');
    }
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('─── matrice verdict → statut ───');
    final ve = matrice.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    for (final e in ve) {
      // ignore: avoid_print
      print('  ${e.key} :');
      final s = e.value.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final x in s) {
        // ignore: avoid_print
        print('      ${x.value.toString().padLeft(5)} × ${x.key}');
      }
    }

    expect(fichiers.length, greaterThan(300));
  });
}

List<int>? _numeros(String combinaison) {
  final out = <int>[];
  for (final p in combinaison.trim().split('-')) {
    final t = p.trim();
    if (t.isEmpty || t.toUpperCase() == 'NP') return null;
    final n = int.tryParse(t);
    if (n == null || n <= 0) return null;
    out.add(n);
  }
  return out.isEmpty ? null : out;
}

/// Arrivée reconstituée : on prend les combinaisons publiées, du plus long au
/// plus court, et on les concatène en singletons. Ce n'est PAS l'arrivée
/// officielle : c'est une arrivée COHÉRENTE avec les rapports, suffisante pour
/// que l'arbitre de variante puisse conclure.
List<List<int>>? _groupesDepuisRapports(List<dynamic> rapports) {
  final nums = <int>[];
  final tries = <Map<String, dynamic>>[];
  for (final r in rapports) {
    final m = r as dynamic;
    final c = m.combinaison as String;
    final parsed = _numeros(c);
    if (parsed != null) tries.add(<String, dynamic>{'c': parsed});
  }
  tries.sort((a, b) =>
      (b['c'] as List).length.compareTo((a['c'] as List).length));
  for (final t in tries) {
    for (final n in t['c'] as List) {
      if (!nums.contains(n)) nums.add(n as int);
    }
    if (nums.length >= 5) break;
  }
  if (nums.length < 3) return null;
  return <List<int>>[for (final n in nums) <int>[n]];
}
