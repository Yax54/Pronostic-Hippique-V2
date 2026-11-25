// ═══════════════════════════════════════════════════════════════════════════
//  B-4.6 — SUJET 3 (rapports à dividende nul) & SUJET 2 (Ordre / Désordre)
//
//  Deux défauts mesurés, deux corrections minimales, deux preuves.
//
//  SUJET 3 — « ne pas présenter un rapport publié comme inexistant »
//    Le filtre `dividendeNormalise > 0` agit PENDANT le décodage. Une liste
//    vide ne prouve donc pas que le PMU n'a rien publié. Avant correction,
//    une réponse dont TOUTES les lignes sont à dividende nul produisait la
//    cause `aucunRapportPublie`, donc le message « Aucun rapport publié pour
//    cette course à cet instant. » — faux.
//
//  SUJET 2 — « ne jamais fusionner arbitrairement des paris différents »
//    `estOrdre` valait `!combinaison.contains('NP') && !combinaison
//    .contains('D')`. Mesuré : AUCUNE combinaison réelle ne contient « D ».
//    Les blocs Ordre/Désordre publient la MÊME combinaison : le libellé est
//    le seul discriminant. 70 lignes « Désordre » étaient donc affichées
//    « Dans l'ordre ».
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:pronostic_hippique/services/pmu_api_service.dart';
import 'fixtures/fixture_paths.dart';

final String kDossier = dossierMulti;
final String kDossierNonDatees = dossierRapports;

/// Corps réel : un bloc, deux lignes, toutes deux à dividende NUL.
const String _corpsToutNul = '''
[
  {
    "typePari": "E_QUARTE_PLUS",
    "miseBase": 200,
    "rembourse": false,
    "rapports": [
      {"libelle": "e-Quarté+ Ordre",    "combinaison": "6-4-13-10",
       "dividendePourUnEuro": 0, "nombreGagnants": 0.0, "rangCombinaisonPayable": 1},
      {"libelle": "e-Quarté+ Désordre", "combinaison": "6-4-13-10",
       "dividendePourUnEuro": 0, "nombreGagnants": 0.0, "rangCombinaisonPayable": 2}
    ]
  }
]
''';

/// Même forme, mais un dividende exploitable : une ligne retenue, une écartée.
const String _corpsPartiel = '''
[
  {
    "typePari": "E_QUARTE_PLUS",
    "rapports": [
      {"libelle": "e-Quarté+ Ordre",    "combinaison": "6-4-13-10",
       "dividendePourUnEuro": 32540},
      {"libelle": "e-Quarté+ Désordre", "combinaison": "6-4-13-10",
       "dividendePourUnEuro": 0}
    ]
  }
]
''';

/// Liste JSON valide, mais aucun bloc ne publie de ligne.
const String _corpsListeVide = '[]';

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  group('B4.6 / S3 — un rapport publié n\'est jamais dit « inexistant »', () {
    test('S3-1 le corps porte 2 lignes, le décodeur en retient 0', () {
      final retenus = PmuApiService.decoderRapportsDefinitifs(_corpsToutNul);
      expect(retenus, isEmpty,
          reason: 'le filtre historique doit rester en place');
      final brut = jsonDecode(_corpsToutNul) as List;
      expect((brut.first as Map)['rapports'], hasLength(2),
          reason: 'deux lignes ont bien été PUBLIÉES');
    });

    test('S3-2 la cause distingue « rien publié » de « rien d\'exploitable »',
        () async {
      // (a) corps sans aucune ligne → aucunRapportPublie
      final a = await _diagnostic(_corpsListeVide);
      expect(a.cause, CauseAbsenceRapports.aucunRapportPublie);
      expect(a.lignesPubliees, 0);

      // (b) corps avec lignes, toutes écartées → aucunRapportExploitable
      final b = await _diagnostic(_corpsToutNul);
      expect(b.cause, CauseAbsenceRapports.aucunRapportExploitable,
          reason: 'AVANT CORRECTION : aucunRapportPublie (FAUX)');
      expect(b.lignesPubliees, 2);
      expect(b.rapports, isEmpty,
          reason: 'le filtre `dividendeNormalise > 0` reste inchangé');

      // (c) les deux causes sont bien distinctes
      expect(a.cause, isNot(b.cause));
    });

    test('S3-3 un corps partiellement exploitable reste « aucune »', () async {
      final d = await _diagnostic(_corpsPartiel);
      expect(d.cause, CauseAbsenceRapports.aucune);
      expect(d.rapports, hasLength(1));
      expect(d.lignesPubliees, 2, reason: 'les 2 lignes sont publiées');
    });

    test('S3-4 MESURE sur 358 captures réelles : 0 cas aveugle, 0 corps vide',
        () {
      // Périmètre = les DEUX dossiers : 308 `multi/` + 50 `rapports/`.
      // Sur `multi/` seul : 4684 lignes, 4262 retenus, 422 écartés.
      final fichiers = _toutesCaptures();
      expect(fichiers, hasLength(358), reason: 'captures réelles absentes');

      var lignes = 0, retenus = 0, aveugles = 0, vides = 0;
      for (final f in fichiers) {
        final corps = f.readAsStringSync();
        final retenusF = PmuApiService.decoderRapportsDefinitifs(corps);
        retenus += retenusF.length;

        var n = 0;
        final brut = jsonDecode(corps);
        if (brut is List) {
          for (final bloc in brut) {
            if (bloc is! Map) continue;
            final l = bloc['rapports'];
            if (l is! List) continue;
            n += l.whereType<Map>().length;
          }
        }
        lignes += n;
        if (n > 0 && retenusF.isEmpty) aveugles++;
        if (n == 0) vides++;
      }

      debugPrint('S3-4  fichiers=${fichiers.length} lignes=$lignes '
          'retenus=$retenus écartés=${lignes - retenus} '
          'aveugles=$aveugles vides=$vides');

      expect(lignes, 5523);
      expect(retenus, 4989);
      expect(lignes - retenus, 534,
          reason: 'les 534 rapports écartés, mesurés');
      expect(aveugles, 0,
          reason: 'aucune course réelle ne perd TOUS ses rapports');
      expect(vides, 0, reason: 'aucune capture réelle n\'est vide');
    });

    test('S3-5 les 534 lignes écartées portent toutes un dividende nul', () {
      // ⚠️ Périmètre : les DEUX dossiers de captures (5523 lignes au total).
      // Sur `multi/` seul (4684 lignes) seules 422 lignes sont nulles : c'est
      // la mesure publiée par `b4_6_moteur_sur_arrivees_reelles_test.dart`.
      var aDividendeNul = 0, rembourse = 0, negatif = 0, lignes = 0;
      for (final f in _toutesCaptures()) {
        final brut = jsonDecode(f.readAsStringSync());
        if (brut is! List) continue;
        for (final bloc in brut) {
          if (bloc is! Map) continue;
          if (bloc['rembourse'] == true) rembourse++;
          final l = bloc['rapports'];
          if (l is! List) continue;
          for (final r in l.whereType<Map>()) {
            lignes++;
            final v = r['dividendePourUnEuro'] ?? r['dividende'];
            final d = v is num ? v.toDouble() / 100.0 : 0.0;
            if (d < 0) negatif++;
            if (d == 0) aDividendeNul++;
          }
        }
      }
      debugPrint('S3-5  lignes=$lignes  dividendeNul=$aDividendeNul  '
          'rembourses=$rembourse  negatifs=$negatif');
      expect(lignes, 5523);
      expect(aDividendeNul, 534);
      expect(negatif, 0, reason: 'aucun dividende négatif réel');
      expect(rembourse, 0,
          reason: 'aucune capture ne marque un bloc remboursé');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  group('B4.6 / S2 — Ordre et Désordre ne sont jamais fusionnés', () {
    test('S2-1 MESURE : aucune combinaison réelle ne contient « D »', () {
      var avecD = 0, avecNP = 0, total = 0;
      for (final f in _captures()) {
        final brut = jsonDecode(f.readAsStringSync());
        if (brut is! List) continue;
        for (final bloc in brut) {
          if (bloc is! Map) continue;
          final l = bloc['rapports'];
          if (l is! List) continue;
          for (final r in l.whereType<Map>()) {
            total++;
            final c = (r['combinaison'] ?? '').toString();
            if (c.contains('D') || c.contains('d')) avecD++;
            if (c.contains('NP')) avecNP++;
          }
        }
      }
      debugPrint('S2-1  lignes=$total  contientD=$avecD  contientNP=$avecNP');
      expect(avecD, 0,
          reason: 'le terme `!combinaison.contains(\'D\')` ne distinguait RIEN');
      expect(total, 4684);
    });

    test('S2-2 MESURE : Ordre et Désordre publient la MÊME combinaison', () {
      var paires = 0, identiques = 0;
      for (final f in _captures()) {
        final brut = jsonDecode(f.readAsStringSync());
        if (brut is! List) continue;
        for (final bloc in brut) {
          if (bloc is! Map) continue;
          final parLibelle = <String, Set<String>>{};
          final l = bloc['rapports'];
          if (l is! List) continue;
          for (final r in l.whereType<Map>()) {
            parLibelle
                .putIfAbsent((r['libelle'] ?? '').toString(), () => <String>{})
                .add((r['combinaison'] ?? '').toString());
          }
          for (final lab in parLibelle.keys) {
            final L = lab.toLowerCase();
            if (!L.contains('ordre') || L.contains('sordre')) continue;
            final base = lab.replaceAll(' Ordre', '').replaceAll(' ordre', '');
            for (final lab2 in parLibelle.keys) {
              final l2 = lab2.toLowerCase();
              if (!l2.contains('sordre')) continue;
              final base2 =
                  lab2.replaceAll(' Désordre', '').replaceAll(' désordre', '');
              if (base2 != base) continue;
              paires++;
              if (parLibelle[lab]!.length == parLibelle[lab2]!.length &&
                  parLibelle[lab]!.containsAll(parLibelle[lab2]!)) {
                identiques++;
              }
            }
          }
        }
      }
      debugPrint('S2-2  paires Ordre/Désordre=$paires  combinaisons identiques=$identiques');
      expect(paires, greaterThan(0));
      expect(identiques, paires,
          reason: 'seul le libellé sépare Ordre et Désordre');
    });

    test('S2-3 le libellé officiel tranche, et seulement quand il tranche', () {
      // Le défaut mesuré : 70 lignes annoncées « Dans l'ordre ».
      expect(estOrdreDepuisLibelleOfficiel('e-Tiercé Désordre'),
          isFalse);
      expect(estOrdreDepuisLibelleOfficiel('e-Tiercé Ordre'),
          isTrue);
      expect(
          estOrdreDepuisLibelleOfficiel('e-Quarté+ Désordre'),
          isFalse);
      expect(
          estOrdreDepuisLibelleOfficiel('e-Quinté+ Désordre'),
          isFalse);
      // « Super Désordre » contient « ordre » : doit rester Désordre.
      expect(
          estOrdreDepuisLibelleOfficiel(
              'e-Super Pick5 Super Désordre'),
          isFalse);
      // Libellés qui ne tranchent PAS → null (heuristique historique gardée).
      for (final l in <String>[
        'e-Simple Placé',
        'e-Simple Gagnant',
        'e-2sur4',
        'e-Trio',
        'e-Couplé Placé',
        'e-Multi en 6',
        'e-Super4',
        'e-Bonus 4sur5',
        'Big 5',
        '',
      ]) {
        expect(estOrdreDepuisLibelleOfficiel(l), isNull,
            reason: '« $l » ne doit rien forcer');
      }
    });

    test('S2-4 MESURE : la correction ne touche que 73 lignes sur 4684', () {
      final modifiees = <String, int>{};
      var total = 0;
      for (final f in _captures()) {
        final brut = jsonDecode(f.readAsStringSync());
        if (brut is! List) continue;
        for (final bloc in brut) {
          if (bloc is! Map) continue;
          final code = (bloc['typePari'] ?? '').toString();
          final l = bloc['rapports'];
          if (l is! List) continue;
          for (final r in l.whereType<Map>()) {
            total++;
            final c = (r['combinaison'] ?? '').toString();
            final lab = (r['libelle'] ?? '').toString();
            final ancien =
                !c.contains('NP') && !c.contains('D') && !c.contains('d');
            final nouveau = estOrdreDepuisLibelleOfficiel(lab) ??
                ancien;
            if (nouveau != ancien) {
              modifiees['$code | $lab'] =
                  (modifiees['$code | $lab'] ?? 0) + 1;
            }
          }
        }
      }
      debugPrint('S2-4  lignes=$total  modifiées=${modifiees.values.fold(0, (a, b) => a + b)}  $modifiees');
      expect(total, 4684);
      // Périmètre MESURÉ, code par code. Décomposition :
      //   70 lignes explicitement « Désordre » (classées à tort « ordre »)
      //    3 lignes « e-Trio Ordre 1 NP » (classées à tort « désordre »)
      //       → la mention « Ordre » est explicite, elle prime sur « NP ».
      expect(modifiees, <String, int>{
        'E_SUPER_PICK5 | e-Super Pick5 Super Désordre': 50,
        'E_TIERCE | e-Tiercé Désordre': 5,
        'E_QUARTE_PLUS | e-Quarté+ Désordre': 5,
        'E_QUINTE_PLUS | e-Quinté+ Désordre': 5,
        'E_SUPER_PICK5 | e-Super Pick5 Désordre': 5,
        'E_TRIO_ORDRE | e-Trio Ordre 1 NP': 3,
      });
      expect(modifiees.values.fold<int>(0, (a, b) => a + b), 73);
      expect(
          modifiees.keys.every((k) {
            final l = k.toLowerCase();
            return l.contains('sordre') || l.contains('ordre');
          }),
          isTrue,
          reason: 'aucune ligne sans mention explicite ne doit changer');
    });

    test('S2-5 décodage réel d\'une ligne « Désordre » : estOrdre == false', () {
      final retenus = PmuApiService.decoderRapportsDefinitifs(_corpsPartiel);
      expect(retenus, hasLength(1));
      expect(retenus.single.libelleOfficiel, 'e-Quarté+ Ordre');
      expect(retenus.single.estOrdre, isTrue);
    });

    test('S2-6 non-régression : sans libellé, l\'heuristique historique gagne',
        () {
      const corpsSansLibelle = '''
      [
        {"typePari": "E_TRIO", "rapports": [
          {"combinaison": "3-14",    "dividendePourUnEuro": 2100},
          {"combinaison": "4-3-NP",  "dividendePourUnEuro": 500}
        ]}
      ]
      ''';
      final r = PmuApiService.decoderRapportsDefinitifs(corpsSansLibelle);
      expect(r, hasLength(2));
      expect(r[0].estOrdre, isTrue, reason: 'aucun libellé → heuristique');
      expect(r[1].estOrdre, isFalse, reason: 'NP → désordre, comme avant');
    });
  });
}

// ─── Utilitaires ────────────────────────────────────────────────────────────

List<File> _captures() {
  final d = Directory(kDossier);
  if (!d.existsSync()) return const <File>[];
  return d
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .where((f) => f.path.contains('C'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

/// Les DEUX dossiers de captures : `multi/R{r}C{c}_{date}.json` (308) et
/// `rapports/R{r}C{c}.json` (50). Total mesuré : 5523 lignes, 534 à dividende nul.
List<File> _toutesCaptures() {
  final out = <File>[];
  for (final dossier in <String>[kDossier, kDossierNonDatees]) {
    final d = Directory(dossier);
    if (!d.existsSync()) continue;
    out.addAll(d
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .where((f) => f.path.contains('C')));
  }
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}

/// Exécute la récupération réelle avec un client HTTP simulé.
Future<DiagnosticRapports> _diagnostic(String corps) {
  return http.runWithClient(
    () => PmuApiService.fetchRapportsAvecDiagnostic('01012026', 1, 1),
    () => MockClient((_) async => http.Response(corps, 200)),
  );
}
