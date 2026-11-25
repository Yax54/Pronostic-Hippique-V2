// ═══════════════════════════════════════════════════════════════════════════
//  B-4.6 — MESURE DU MOTEUR SUR ARRIVÉES RÉELLES
//
//  ⚠️  FICHIER DE MESURE UNIQUEMENT. Aucune modification de production.
//
//  OBJET : les captures `multi/` contiennent les RAPPORTS
//  (`R{r}C{c}_{date}.json`) ET, dans les fichiers `prog_{date}.json`,
//  l'ARRIVÉE OFFICIELLE (`programme.reunions[].courses[].ordreArrivee`,
//  déjà au format groupé). La jointure (date, réunion, course) est donc
//  possible pour la première fois.
//
//  On mesure alors trois choses jamais mesurées jusqu'ici :
//    M1 — les rapports publiés à 0 € : que sont-ils exactement ?
//    M2 — le moteur, joué sur la VRAIE arrivée, rend-il le verdict attendu ?
//    M3 — effet réel de la divergence de codes Quarté+/Quinté+
//         (E_QUARTE_PLUS vs E_SUPER_QUATRE, E_QUINTE_PLUS vs E_MULTI).
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/branchement_verdict_course.dart';
import 'package:pronostic_hippique/services/pmu_api_service.dart';
import 'package:pronostic_hippique/services/resolution_gain_ticket_pmu.dart';
import 'fixtures/fixture_paths.dart';

final String kDossier = dossierMulti;

/// (codePmu, taille de combinaison) des types de l'application.
const Map<String, ({String code, int taille})> kTypes = {
  'Simple Gagnant': (code: 'E_SIMPLE_GAGNANT', taille: 1),
  'Simple Placé': (code: 'E_SIMPLE_PLACE', taille: 1),
  'Couplé Gagnant': (code: 'E_COUPLE_GAGNANT', taille: 2),
  'Couplé Placé': (code: 'E_COUPLE_PLACE', taille: 2),
  'Tiercé Ordre': (code: 'E_TIERCE', taille: 3),
  'Quarté+': (code: 'E_QUARTE_PLUS', taille: 4),
  'Quinté+': (code: 'E_QUINTE_PLUS', taille: 5),
};

final DateTime _heure = DateTime.utc(2026, 11, 15, 14, 30);

void main() {
  // ─── M1 : que sont les rapports publiés à 0 € ? ─────────────────────────
  test('M1 — les rapports publiés à 0 € : nature exacte', () {
    var lignesTotales = 0;
    var lignesZero = 0;
    var lignesZeroSansNP = 0;
    var blocsTotal = 0;
    var blocsRembourseTrue = 0;
    var lignesZeroNombreGagnantsZero = 0;
    final parLibelle = <String, int>{};
    final parCombinaisonSansNp = <String, int>{};
    final exemplesSansNp = <String>[];

    for (final f in _fichiers(kDossier)) {
      final racine = _racine(f);
      if (racine == null) continue;
      for (final b in racine) {
        if (b is! Map) continue;
        blocsTotal++;
        if (b['rembourse'] == true) blocsRembourseTrue++;
        final liste = b['rapports'];
        if (liste is! List) continue;
        for (final r in liste) {
          if (r is! Map) continue;
          lignesTotales++;
          final v = _valeurDividende(r);
          if (v == null || v != 0) continue;
          lignesZero++;
          if (r['nombreGagnants'] == 0 || r['nombreGagnants'] == 0.0) {
            lignesZeroNombreGagnantsZero++;
          }
          final lib = r['libelle']?.toString() ?? '<sans libellé>';
          parLibelle[lib] = (parLibelle[lib] ?? 0) + 1;
          final comb = r['combinaison']?.toString() ?? '';
          if (!comb.toUpperCase().contains('NP')) {
            lignesZeroSansNP++;
            parCombinaisonSansNp[comb] = (parCombinaisonSansNp[comb] ?? 0) + 1;
            if (exemplesSansNp.length < 6) {
              exemplesSansNp.add('$lib | $comb | '
                  '${b['typePari']} | rang ${r['rangCombinaisonPayable']}');
            }
          }
        }
      }
    }

    // ignore: avoid_print
    print('═══ M1 — RAPPORTS PUBLIÉS À 0 € ═══');
    // ignore: avoid_print
    print('blocs analysés                : $blocsTotal');
    // ignore: avoid_print
    print('blocs avec rembourse = true   : $blocsRembourseTrue');
    // ignore: avoid_print
    print('lignes de rapport publiées    : $lignesTotales');
    // ignore: avoid_print
    print('lignes à dividende 0          : $lignesZero');
    // ignore: avoid_print
    print('  dont nombreGagnants = 0     : $lignesZeroNombreGagnantsZero');
    // ignore: avoid_print
    print('  dont combinaison SANS "NP"  : $lignesZeroSansNP');
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('─── lignes à 0 €, par libellé ───');
    final libs = parLibelle.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in libs) {
      // ignore: avoid_print
      print('  ${e.value.toString().padLeft(5)} × ${e.key}');
    }
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('─── lignes à 0 € à combinaison SANS "NP" (donc comparable) ───');
    final combs = parCombinaisonSansNp.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in combs.take(12)) {
      // ignore: avoid_print
      print('  ${e.value.toString().padLeft(5)} × ${e.key}');
    }
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('─── exemples bruts (sans NP) ───');
    for (final e in exemplesSansNp) {
      // ignore: avoid_print
      print('  $e');
    }

    expect(lignesTotales, greaterThanOrEqualTo(4684));
    expect(blocsTotal, greaterThanOrEqualTo(1891));
  });

  // ─── M2 : le moteur sur la VRAIE arrivée ────────────────────────────────
  test('M2 — moteur sur arrivées réelles : verdict par type', () {
    final arrivees = _chargerArrivees();
    var coursesJointes = 0;
    var coursesRapports = 0;

    final verdictsParType = <String, Map<String, int>>{};
    final motifsParType = <String, Map<String, int>>{};
    final statutsParType = <String, Map<String, int>>{};

    for (final f in _fichiers(kDossier)) {
      final nom = f.uri.pathSegments.last;
      final m = RegExp(r'^R(\d+)C(\d+)_(\d{8})\.json$').firstMatch(nom);
      if (m == null) continue; // fichier programme : pas une capture de rapports
      coursesRapports++;

      final date = m.group(3)!;
      final numR = int.parse(m.group(1)!);
      final numC = int.parse(m.group(2)!);
      final groupes = arrivees['$date|$numR|$numC'];
      if (groupes == null) continue;
      coursesJointes++;

      final rapportsApi = PmuApiService.decoderRapportsDefinitifs(
          f.readAsStringSync());
      if (rapportsApi.isEmpty) continue;

      final resultat = ResultatOfficielCourse(
        arriveeGroupes: groupes,
        arriveeDefinitive: true,
        rapports: rapportsApi,
      );

      final plats = <int>[for (final g in groupes) ...g];

      for (final entry in kTypes.entries) {
        final t = entry.value;
        if (plats.length < t.taille) continue;
        final numeros = plats.take(t.taille).toList();

        final ticket = TrackedCourse(
          numReunion: numR,
          numCourse: numC,
          nomCourse: 'MESURE',
          hippodrome: 'MESURE',
          heureDepart: _heure,
          storageKey: 'MESURE',
          nomCheval: 'MESURE',
          numeroCheval: numeros.first,
          miseEngagee: 2.0,
          typePari: entry.key,
          numerosJoues: numeros,
          codePmuOfficiel: t.code,
          varianteChoisie: entry.key.contains('Ordre') ? 'ordre' : null,
          numerosDansOrdre: numeros,
        );

        final res = resoudreSuivi(ticket: ticket, resultat: resultat);
        final etat = res.verdict?.etat.name ?? 'aucun';
        final motif = res.verdict?.motif?.name ?? '-';
        final statut = res.enregistrement?.statut.name ?? 'aucun';

        verdictsParType.putIfAbsent(entry.key, () => <String, int>{});
        verdictsParType[entry.key]![etat] =
            (verdictsParType[entry.key]![etat] ?? 0) + 1;

        motifsParType.putIfAbsent(entry.key, () => <String, int>{});
        motifsParType[entry.key]![motif] =
            (motifsParType[entry.key]![motif] ?? 0) + 1;

        statutsParType.putIfAbsent(entry.key, () => <String, int>{});
        statutsParType[entry.key]![statut] =
            (statutsParType[entry.key]![statut] ?? 0) + 1;
      }
    }

    // ignore: avoid_print
    print('═══ M2 — MOTEUR SUR ARRIVÉES RÉELLES ═══');
    // ignore: avoid_print
    print('captures de rapports          : $coursesRapports');
    // ignore: avoid_print
    print('jointes à une arrivée réelle  : $coursesJointes');
    // ignore: avoid_print
    print('');
    for (final type in kTypes.keys) {
      // ignore: avoid_print
      print('─── $type ───');
      final v = verdictsParType[type];
      if (v == null) {
        // ignore: avoid_print
        print('  (aucun cas)');
        continue;
      }
      final ve = v.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      for (final e in ve) {
        // ignore: avoid_print
        print('  ${e.value.toString().padLeft(5)} × verdict=${e.key}');
      }
      final mo = motifsParType[type]!;
      final moe = mo.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      for (final e in moe) {
        if (e.key == '-') continue;
        // ignore: avoid_print
        print('  ${e.value.toString().padLeft(5)}   motif ${e.key}');
      }
      final st = statutsParType[type]!;
      final ste = st.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      for (final e in ste) {
        // ignore: avoid_print
        print('  ${e.value.toString().padLeft(5)}   statut ${e.key}');
      }
    }

    expect(coursesJointes, greaterThan(300));
  });

  // ─── M3 : divergence des codes Quarté+ / Quinté+ ────────────────────────
  test('M3 — Quarté+/Quinté+ : le code cherché est-il celui publié ?', () {
    var courses = 0;
    var quartePublieCodeCherche = 0;
    var quarteSeulementAutreCode = 0;
    var quintePublieCodeCherche = 0;
    var quinteSeulementAutreCode = 0;
    final codesPublies = <String, int>{};

    for (final f in _fichiers(kDossier)) {
      final racine = _racine(f);
      if (racine == null) continue;
      courses++;
      final codes = <String>{};
      for (final b in racine) {
        if (b is! Map) continue;
        final code = b['typePari']?.toString() ?? '';
        if (code.isEmpty) continue;
        codes.add(code);
        codesPublies[code] = (codesPublies[code] ?? 0) + 1;
      }
      if (codes.contains('E_QUARTE_PLUS')) {
        quartePublieCodeCherche++;
      } else if (codes.contains('E_SUPER_QUATRE')) {
        quarteSeulementAutreCode++;
      }
      if (codes.contains('E_QUINTE_PLUS')) {
        quintePublieCodeCherche++;
      } else if (codes.contains('E_MULTI') || codes.contains('E_MINI_MULTI')) {
        quinteSeulementAutreCode++;
      }
    }

    // ignore: avoid_print
    print('═══ M3 — DIVERGENCE DE CODES ═══');
    // ignore: avoid_print
    print('captures de rapports : $courses');
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('Quarté+  code cherché E_QUARTE_PLUS publié : '
        '$quartePublieCodeCherche / $courses');
    // ignore: avoid_print
    print('Quarté+  seul E_SUPER_QUATRE publié        : '
        '$quarteSeulementAutreCode / $courses');
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('Quinté+  code cherché E_QUINTE_PLUS publié : '
        '$quintePublieCodeCherche / $courses');
    // ignore: avoid_print
    print('Quinté+  seul E_MULTI/E_MINI_MULTI publié  : '
        '$quinteSeulementAutreCode / $courses');
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('─── tous les codes de blocs publiés ───');
    final cp = codesPublies.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in cp) {
      // ignore: avoid_print
      print('  ${e.value.toString().padLeft(5)} × ${e.key}');
    }

    expect(courses, greaterThan(300));
  });
}

// ─── Utilitaires ──────────────────────────────────────────────────────────

List<File> _fichiers(String dossier) => Directory(dossier)
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.json'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

/// Racine JSON quand c'est une liste (captures de rapports). null sinon.
List<dynamic>? _racine(File f) {
  try {
    final d = jsonDecode(f.readAsStringSync());
    return d is List ? d : null;
  } catch (_) {
    return null;
  }
}

/// Valeur de dividende telle que le décodeur la lit (centimes, sans /100).
num? _valeurDividende(Map r) {
  final a = r['dividendePourUnEuro'];
  if (a is num) return a;
  final b = r['dividende'];
  if (b is num) return b;
  return null;
}

/// Arrivées réelles : clé « date|R|C » → arrivée GROUPÉE.
Map<String, List<List<int>>> _chargerArrivees() {
  final out = <String, List<List<int>>>{};
  for (final f in _fichiers(kDossier)) {
    final nom = f.uri.pathSegments.last;
    final m = RegExp(r'^prog_(\d{8})\.json$').firstMatch(nom);
    if (m == null) continue;
    final date = m.group(1)!;
    Map<String, dynamic> racine;
    try {
      racine = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      continue;
    }
    final prog = racine['programme'];
    if (prog is! Map) continue;
    final reunions = prog['reunions'];
    if (reunions is! List) continue;
    for (final r in reunions) {
      if (r is! Map) continue;
      final numR = r['numOfficiel'];
      if (numR is! num) continue;
      final courses = r['courses'];
      if (courses is! List) continue;
      for (final c in courses) {
        if (c is! Map) continue;
        final arr = c['ordreArrivee'];
        if (arr is! List || arr.isEmpty) continue;
        final groupes = <List<int>>[];
        var ok = true;
        for (final g in arr) {
          if (g is! List || g.isEmpty) {
            ok = false;
            break;
          }
          final nums = <int>[];
          for (final n in g) {
            if (n is! num) {
              ok = false;
              break;
            }
            nums.add(n.toInt());
          }
          if (!ok) break;
          groupes.add(nums);
        }
        if (!ok || groupes.isEmpty) continue;
        final numC = c['numOrdre'] ?? c['numExterne'];
        if (numC is! num) continue;
        out['$date|${numR.toInt()}|${numC.toInt()}'] = groupes;
      }
    }
  }
  return out;
}
