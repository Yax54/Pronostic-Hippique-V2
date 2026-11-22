// ═══════════════════════════════════════════════════════════════════════════
//  B-4.6 / ARBITRAGE — CONSÉQUENCES RÉELLES DES 534 RAPPORTS ÉCARTÉS
//
//  ⚠️  FICHIER DE MESURE UNIQUEMENT. Aucune modification de production.
//
//  OBJET : ne PAS confondre « rapports écartés » et « tickets affectés ».
//  Pour chaque ligne PUBLIÉE mais écartée par `dividendeNormalise > 0`, on
//  construit le ticket applicatif correspondant et on mesure DEUX verdicts :
//
//    • AUJOURD'HUI      — la chaîne réelle (rapports décodés AVEC le filtre)
//    • SI FILTRE RETIRÉ — la même chaîne, rapports reconstruits SANS le filtre
//
//  La différence entre les deux colonnes est exactement l'effet du filtre.
//  Le moteur B-3, l'arbitre et l'enregistreur ne sont PAS modifiés : on les
//  appelle tels quels.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/branchement_verdict_course.dart';
import 'package:pronostic_hippique/services/gain_calculator.dart';
import 'package:pronostic_hippique/services/pmu_api_service.dart';
import 'package:pronostic_hippique/services/resolution_gain_ticket_pmu.dart';

const String kDossier = '/home/user/recherche_pmu/multi';

/// Type applicatif + code PMU + taille, pour les blocs réellement publiés.
const Map<String, ({String type, String code, int taille})> kParCode = {
  'E_SIMPLE_GAGNANT': (
    type: 'Simple Gagnant',
    code: 'E_SIMPLE_GAGNANT',
    taille: 1
  ),
  'E_SIMPLE_PLACE': (type: 'Simple Placé', code: 'E_SIMPLE_PLACE', taille: 1),
  'E_COUPLE_GAGNANT': (
    type: 'Couplé Gagnant',
    code: 'E_COUPLE_GAGNANT',
    taille: 2
  ),
  'E_COUPLE_PLACE': (type: 'Couplé Placé', code: 'E_COUPLE_PLACE', taille: 2),
  'E_COUPLE_ORDRE': (type: 'Couplé Ordre', code: 'E_COUPLE_ORDRE', taille: 2),
  'E_TRIO': (type: 'Tiercé', code: 'E_TRIO', taille: 3),
  'E_TRIO_ORDRE': (type: 'Tiercé Ordre', code: 'E_TIERCE', taille: 3),
  'E_TIERCE': (type: 'Tiercé Ordre', code: 'E_TIERCE', taille: 3),
  'E_QUARTE_PLUS': (type: 'Quarté+', code: 'E_QUARTE_PLUS', taille: 4),
  'E_SUPER_QUATRE': (type: 'Quarté+', code: 'E_QUARTE_PLUS', taille: 4),
  'E_QUINTE_PLUS': (type: 'Quinté+', code: 'E_QUINTE_PLUS', taille: 5),
  'E_MULTI': (type: 'Quinté+', code: 'E_QUINTE_PLUS', taille: 5),
  'E_MINI_MULTI': (type: 'Quinté+', code: 'E_QUINTE_PLUS', taille: 5),
  'E_DEUX_SUR_QUATRE': (type: 'inconnu', code: '', taille: 2),
  'E_SUPER_PICK5': (type: 'inconnu', code: '', taille: 5),
  'EB5': (type: 'inconnu', code: '', taille: 5),
};

final DateTime _heure = DateTime.utc(2026, 11, 15, 14, 30);

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  //  C1 — les 534 lignes : ce que la chaîne en fait, ticket par ticket
  // ═══════════════════════════════════════════════════════════════════════
  test('C1 — 534 lignes écartées : verdict RÉEL vs verdict SI FILTRE RETIRÉ',
      () {
    final arrivees = _chargerArrivees();

    var lignesEcartees = 0;
    var lignesSansCombinaisonJouable = 0; // NP ou illisible → aucun ticket
    var ticketsConstruits = 0;
    var coursesJointes = 0;

    // Verdicts produits par les DEUX scénarios, sur les mêmes tickets.
    final avecFiltre = <String, int>{};
    final sansFiltre = <String, int>{};
    final transitions = <String, int>{};

    // Cas où le filtre change quelque chose : à détailler.
    final casDifferents = <String>[];

    for (final f in _fichiers(kDossier)) {
      final nom = f.uri.pathSegments.last;
      final m = RegExp(r'^R(\d+)C(\d+)_(\d{8})\.json$').firstMatch(nom);
      if (m == null) continue;
      final date = m.group(3)!;
      final numR = int.parse(m.group(1)!);
      final numC = int.parse(m.group(2)!);
      final groupes = arrivees['$date|$numR|$numC'];
      if (groupes == null) continue;
      coursesJointes++;

      final corps = f.readAsStringSync();

      // Les DEUX jeux de rapports : avec filtre (production) et sans filtre.
      final rapportsAvecFiltre = PmuApiService.decoderRapportsDefinitifs(corps);
      final rapportsSansFiltre = _decoderSansFiltre(corps);

      final resultatAvec = ResultatOfficielCourse(
        arriveeGroupes: groupes,
        arriveeDefinitive: true,
        rapports: rapportsAvecFiltre,
      );
      final resultatSans = ResultatOfficielCourse(
        arriveeGroupes: groupes,
        arriveeDefinitive: true,
        rapports: rapportsSansFiltre,
      );

      // Les lignes écartées de CETTE capture.
      for (final ligne in _lignesEcartees(corps)) {
        lignesEcartees++;
        final comb = ligne.combinaison.trim();
        final nums = _numeros(comb);
        final mapping = kParCode[ligne.codeBloc];
        if (nums == null || mapping == null) {
          lignesSansCombinaisonJouable++;
          continue;
        }
        if (nums.length != mapping.taille) {
          lignesSansCombinaisonJouable++;
          continue;
        }
        ticketsConstruits++;

        final ticket = TrackedCourse(
          numReunion: numR,
          numCourse: numC,
          nomCourse: 'MESURE',
          hippodrome: 'MESURE',
          heureDepart: _heure,
          storageKey: 'MESURE',
          nomCheval: 'MESURE',
          numeroCheval: nums.first,
          miseEngagee: 2.0,
          typePari: mapping.type,
          numerosJoues: nums,
          codePmuOfficiel: mapping.code,
          varianteChoisie: _variante(mapping.code),
          numerosDansOrdre: nums,
        );

        final a = resoudreSuivi(ticket: ticket, resultat: resultatAvec);
        final s = resoudreSuivi(ticket: ticket, resultat: resultatSans);

        final ka = _cle(a);
        final ks = _cle(s);
        avecFiltre[ka] = (avecFiltre[ka] ?? 0) + 1;
        sansFiltre[ks] = (sansFiltre[ks] ?? 0) + 1;
        if (ka != ks) {
          transitions['$ka  →  $ks'] = (transitions['$ka  →  $ks'] ?? 0) + 1;
          if (casDifferents.length < 30) {
            casDifferents.add('$nom | ${ligne.codeBloc} | «${ligne.libelle}» '
                '| $comb | rang ${ligne.rang} | A=$ka | S=$ks');
          }
        }
      }
    }

    // ignore: avoid_print
    print('═══ C1 — 534 LIGNES ÉCARTÉES : EFFET RÉEL SUR LES TICKETS ═══');
    // ignore: avoid_print
    print('captures jointes à une arrivée : $coursesJointes');
    // ignore: avoid_print
    print('lignes écartées (publiées à 0) : $lignesEcartees');
    // ignore: avoid_print
    print('  sans combinaison jouable     : $lignesSansCombinaisonJouable');
    // ignore: avoid_print
    print('  tickets réellement construits: $ticketsConstruits');
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('─── AUJOURD\'HUI (filtre actif) ───');
    _afficher(avecFiltre);
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('─── SI LE FILTRE ÉTAIT RETIRÉ ───');
    _afficher(sansFiltre);
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('─── TRANSITIONS provoquées par le filtre ───');
    if (transitions.isEmpty) {
      // ignore: avoid_print
      print('  AUCUNE : le filtre ne change aucun verdict sur ces tickets.');
    } else {
      final t = transitions.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in t) {
        // ignore: avoid_print
        print('  ${e.value.toString().padLeft(4)} × ${e.key}');
      }
      // ignore: avoid_print
      print('');
      // ignore: avoid_print
      print('─── cas détaillés ───');
      for (final c in casDifferents) {
        // ignore: avoid_print
        print('  $c');
      }
    }

    expect(ticketsConstruits, greaterThan(0));
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  C2 — Quarté+ / Super4 : la contamination Ordre ←→ Désordre
  // ═══════════════════════════════════════════════════════════════════════
  test('C2 — Quarté+/Super4 : un ticket ORDRE peut-il recevoir le DÉSORDRE ?',
      () {
    final arrivees = _chargerArrivees();

    final lignes = <String>[];
    var examinees = 0;
    var gainOrdreSurOrdre = 0;
    var indetermines = 0;
    var perdus = 0;

    for (final f in _fichiers(kDossier)) {
      final nom = f.uri.pathSegments.last;
      final m = RegExp(r'^R(\d+)C(\d+)_(\d{8})\.json$').firstMatch(nom);
      if (m == null) continue;
      final date = m.group(3)!;
      final numR = int.parse(m.group(1)!);
      final numC = int.parse(m.group(2)!);
      final groupes = arrivees['$date|$numR|$numC'];
      if (groupes == null) continue;

      final corps = f.readAsStringSync();
      final rapports = PmuApiService.decoderRapportsDefinitifs(corps);
      final resultat = ResultatOfficielCourse(
        arriveeGroupes: groupes,
        arriveeDefinitive: true,
        rapports: rapports,
      );

      for (final ligne in _lignesEcartees(corps)) {
        if (ligne.rang != 1) continue;
        if (ligne.codeBloc != 'E_QUARTE_PLUS' &&
            ligne.codeBloc != 'E_SUPER_QUATRE' &&
            ligne.codeBloc != 'E_QUINTE_PLUS') {
          continue;
        }
        final nums = _numeros(ligne.combinaison);
        if (nums == null || nums.length != 4 && nums.length != 5) continue;
        examinees++;

        // Ticket « dans l'ordre » joué sur la combinaison publiée au rang 1.
        final ticketOrdre = TrackedCourse(
          numReunion: numR,
          numCourse: numC,
          nomCourse: 'MESURE',
          hippodrome: 'MESURE',
          heureDepart: _heure,
          storageKey: 'MESURE',
          nomCheval: 'MESURE',
          numeroCheval: nums.first,
          miseEngagee: 2.0,
          typePari: nums.length == 4 ? 'Quarté+' : 'Quinté+',
          numerosJoues: nums,
          codePmuOfficiel:
              nums.length == 4 ? 'E_QUARTE_PLUS' : 'E_QUINTE_PLUS',
          varianteChoisie: 'ordre',
          numerosDansOrdre: nums,
        );

        final res = resoudreSuivi(ticket: ticketOrdre, resultat: resultat);
        final etat = res.verdict?.etat.name ?? 'aucun';
        final motif = res.verdict?.motif?.name ?? '-';
        final total = res.verdict?.total ?? 0.0;
        final statut = res.enregistrement?.statut.name ?? 'aucun';

        if (etat == 'attribue') {
          gainOrdreSurOrdre++;
        } else if (etat == 'nonDetermine') {
          indetermines++;
        } else if (etat == 'perdu') {
          perdus++;
        }

        lignes.add('$nom | ${ligne.codeBloc} | «${ligne.libelle}» | '
            '${ligne.combinaison} | arrivée=${_plats(groupes, nums.length)} '
            '→ verdict=$etat motif=$motif total=${total.toStringAsFixed(2)} '
            'statut=$statut');
      }
    }

    // ignore: avoid_print
    print('═══ C2 — TICKET « ORDRE » SUR LA COMBINAISON PUBLIÉE AU RANG 1 ═══');
    // ignore: avoid_print
    print('cas examinés                                 : $examinees');
    // ignore: avoid_print
    print('verdict attribue (gain attribué)             : $gainOrdreSurOrdre');
    // ignore: avoid_print
    print('verdict nonDetermine                         : $indetermines');
    // ignore: avoid_print
    print('verdict perdu                                : $perdus');
    // ignore: avoid_print
    print('');
    for (final l in lignes) {
      // ignore: avoid_print
      print('  $l');
    }

    expect(examinees, greaterThan(0));
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  C3 — la combinaison gagnante ORDRE est-elle payée en DÉSORDRE ?
  //
  //  Le ticket « Ordre » n'a AUCUN rapport : le prouver. Mais le même pari,
  //  joué en Désordre, doit-il être payé ? C'est le vrai enjeu financier.
  // ═══════════════════════════════════════════════════════════════════════
  test('C3 — même combinaison jouée en Désordre : gain payé ou non ?', () {
    final arrivees = _chargerArrivees();

    var examinees = 0;
    var attribues = 0;
    var indetermines = 0;
    var perdus = 0;
    var rembourses = 0;
    final details = <String>[];

    for (final f in _fichiers(kDossier)) {
      final nom = f.uri.pathSegments.last;
      final m = RegExp(r'^R(\d+)C(\d+)_(\d{8})\.json$').firstMatch(nom);
      if (m == null) continue;
      final date = m.group(3)!;
      final numR = int.parse(m.group(1)!);
      final numC = int.parse(m.group(2)!);
      final groupes = arrivees['$date|$numR|$numC'];
      if (groupes == null) continue;

      final corps = f.readAsStringSync();
      final resultat = ResultatOfficielCourse(
        arriveeGroupes: groupes,
        arriveeDefinitive: true,
        rapports: PmuApiService.decoderRapportsDefinitifs(corps),
      );

      for (final ligne in _lignesEcartees(corps)) {
        if (ligne.rang != 1) continue;
        final nums = _numeros(ligne.combinaison);
        if (nums == null) continue;
        if (nums.length != 4 && nums.length != 5) continue;
        // On ne garde que les blocs d'un type applicatif connu.
        final mapping = kParCode[ligne.codeBloc];
        if (mapping == null || mapping.code.isEmpty) continue;
        if (nums.length != mapping.taille) continue;
        examinees++;

        final ticket = TrackedCourse(
          numReunion: numR,
          numCourse: numC,
          nomCourse: 'MESURE',
          hippodrome: 'MESURE',
          heureDepart: _heure,
          storageKey: 'MESURE',
          nomCheval: 'MESURE',
          numeroCheval: nums.first,
          miseEngagee: 2.0,
          typePari: mapping.type,
          numerosJoues: nums,
          codePmuOfficiel: mapping.code,
          varianteChoisie: 'desordre',
          numerosDansOrdre: nums,
        );

        final res = resoudreSuivi(ticket: ticket, resultat: resultat);
        final etat = res.verdict?.etat.name ?? 'aucun';
        final motif = res.verdict?.motif?.name ?? '-';
        final total = res.verdict?.total ?? 0.0;
        final statut = res.enregistrement?.statut.name ?? 'aucun';

        switch (etat) {
          case 'attribue':
            attribues++;
          case 'nonDetermine':
            indetermines++;
          case 'perdu':
            perdus++;
          case 'rembourse':
            rembourses++;
        }

        details.add('$nom | ${ligne.codeBloc} | ${ligne.combinaison} | '
            'type=${mapping.type} | → $etat motif=$motif '
            'total=${total.toStringAsFixed(2)} statut=$statut');
      }
    }

    // ignore: avoid_print
    print('═══ C3 — MÊME COMBINAISON JOUÉE EN DÉSORDRE ═══');
    // ignore: avoid_print
    print('cas examinés          : $examinees');
    // ignore: avoid_print
    print('verdict attribue      : $attribues');
    // ignore: avoid_print
    print('verdict nonDetermine  : $indetermines');
    // ignore: avoid_print
    print('verdict perdu         : $perdus');
    // ignore: avoid_print
    print('verdict rembourse     : $rembourses');
    // ignore: avoid_print
    print('');
    for (final d in details) {
      // ignore: avoid_print
      print('  $d');
    }

    expect(examinees, greaterThan(0));
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  C4 — LE VRAI SCÉNARIO À RISQUE : même ensemble, ORDRE DIFFÉRENT
  //
  //  C3 ne prouvait rien : l'arbitre établit la variante depuis l'ARRIVÉE,
  //  pas depuis la variante choisie par le joueur. Il faut donc un ticket dont
  //  l'ensemble est gagnant mais l'ordre différent, joué en Désordre.
  //
  //  Question : le rapport Désordre (rang 2, montant POSITIF) est-il payé ?
  //  Un « gain erroné » est ici possible si le montant retenu est faux.
  // ═══════════════════════════════════════════════════════════════════════
  test('C4 — ensemble gagnant, ordre différent, joué en Désordre', () {
    final arrivees = _chargerArrivees();

    var examinees = 0;
    final parResultat = <String, int>{};
    final details = <String>[];

    for (final f in _fichiers(kDossier)) {
      final nom = f.uri.pathSegments.last;
      final m = RegExp(r'^R(\d+)C(\d+)_(\d{8})\.json$').firstMatch(nom);
      if (m == null) continue;
      final date = m.group(3)!;
      final numR = int.parse(m.group(1)!);
      final numC = int.parse(m.group(2)!);
      final groupes = arrivees['$date|$numR|$numC'];
      if (groupes == null) continue;

      final corps = f.readAsStringSync();
      final rapports = PmuApiService.decoderRapportsDefinitifs(corps);
      final resultat = ResultatOfficielCourse(
        arriveeGroupes: groupes,
        arriveeDefinitive: true,
        rapports: rapports,
      );

      // On cherche un bloc Quarté+ / Quinté+ dont le rang 2 « Désordre » est
      // payable, et dont la combinaison est celle de l'arrivée.
      for (final b in (jsonDecode(corps) as List)) {
        if (b is! Map) continue;
        final code = b['typePari']?.toString() ?? '';
        if (code != 'E_QUARTE_PLUS' && code != 'E_QUINTE_PLUS') continue;
        final liste = b['rapports'];
        if (liste is! List) continue;
        Map? desordre;
        for (final r in liste) {
          if (r is! Map) continue;
          final lib = r['libelle']?.toString() ?? '';
          if (!lib.toLowerCase().contains('désordre') &&
              !lib.toLowerCase().contains('desordre')) {
            continue;
          }
          final v = r['dividendePourUnEuro'];
          if (v is num && v > 0) desordre = r;
        }
        if (desordre == null) continue;

        final combOfficielle = _numeros(desordre['combinaison']?.toString() ?? '');
        if (combOfficielle == null) continue;
        final taille = combOfficielle.length;

        // Le set officiel doit être exactement les `taille` premiers plats.
        final plats = <int>[for (final g in groupes) ...g];
        if (plats.length < taille) continue;
        final premiers = plats.take(taille).toList();
        final setOfficiel = {...combOfficielle};
        final setArrivee = {...premiers};
        if (setOfficiel.length != setArrivee.length) continue;
        if (!setOfficiel.containsAll(setArrivee)) continue;

        // Ordre joué DIFFÉRENT de l'ordre officiel : on inverse les deux 1ers.
        final joues = <int>[...combOfficielle];
        final tmp = joues[0];
        joues[0] = joues[1];
        joues[1] = tmp;
        if (joues.join('-') == combOfficielle.join('-')) continue;

        examinees++;

        final ticket = TrackedCourse(
          numReunion: numR,
          numCourse: numC,
          nomCourse: 'MESURE',
          hippodrome: 'MESURE',
          heureDepart: _heure,
          storageKey: 'MESURE',
          nomCheval: 'MESURE',
          numeroCheval: joues.first,
          miseEngagee: 2.0,
          typePari: taille == 4 ? 'Quarté+' : 'Quinté+',
          numerosJoues: joues,
          codePmuOfficiel:
              taille == 4 ? 'E_QUARTE_PLUS' : 'E_QUINTE_PLUS',
          varianteChoisie: 'desordre',
          numerosDansOrdre: joues,
        );

        final res = resoudreSuivi(ticket: ticket, resultat: resultat);
        final etat = res.verdict?.etat.name ?? 'aucun';
        final motif = res.verdict?.motif?.name ?? '-';
        final total = res.verdict?.total ?? 0.0;
        final statut = res.enregistrement?.statut.name ?? 'aucun';

        // Montant attendu : mise × dividende du rapport Désordre retenu.
        final pourUnEuro = (desordre['dividendePourUnEuro'] as num) / 100.0;
        final attendu = 2.0 * pourUnEuro;

        final cle = '$etat/$motif';
        parResultat[cle] = (parResultat[cle] ?? 0) + 1;

        details.add('$nom | $code | officiel=${combOfficielle.join('-')} '
            '| joué(désordre)=${joues.join('-')} '
            '| rapport Désordre=${pourUnEuro.toStringAsFixed(2)} '
            '| ATTENDU=${attendu.toStringAsFixed(2)} '
            '| OBTENU=$etat $motif total=${total.toStringAsFixed(2)} '
            '| statut=$statut');
      }
    }

    // ignore: avoid_print
    print('═══ C4 — ENSEMBLE GAGNANT, ORDRE DIFFÉRENT, JOUÉ DÉSORDRE ═══');
    // ignore: avoid_print
    print('cas examinés : $examinees');
    // ignore: avoid_print
    print('');
    final pr = parResultat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in pr) {
      // ignore: avoid_print
      print('  ${e.value.toString().padLeft(4)} × ${e.key}');
    }
    // ignore: avoid_print
    print('');
    for (final d in details.take(15)) {
      // ignore: avoid_print
      print('  $d');
    }

    expect(examinees, greaterThan(0));
  });
}

// ─── Outils de mesure ─────────────────────────────────────────────────────

String _cle(ResolutionTicketSuivi resolution) {
  final e = resolution.verdict?.etat.name ?? 'aucun';
  final mo = resolution.verdict?.motif?.name ?? '-';
  final st = resolution.enregistrement?.statut.name ?? 'aucun';
  return '$e/$mo/$st';
}

void _afficher(Map<String, int> m) {
  final e = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  for (final x in e) {
    // ignore: avoid_print
    print('  ${x.value.toString().padLeft(4)} × ${x.key}');
  }
}

String? _variante(String code) {
  if (code == 'E_TIERCE') return 'ordre';
  if (code == 'E_COUPLE_ORDRE') return 'ordre';
  return null;
}

String _plats(List<List<int>> groupes, int n) =>
    <int>[for (final g in groupes) ...g].take(n).join('-');

List<File> _fichiers(String dossier) => Directory(dossier)
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.json'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

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

/// Une ligne publiée écartée par le filtre `dividende > 0`.
class _LigneEcartee {
  _LigneEcartee({
    required this.codeBloc,
    required this.libelle,
    required this.combinaison,
    required this.rang,
    required this.nombreGagnants,
    required this.dividendeCentimes,
  });
  final String codeBloc;
  final String libelle;
  final String combinaison;
  final int? rang;
  final num? nombreGagnants;
  final num dividendeCentimes;
}

List<_LigneEcartee> _lignesEcartees(String corps) {
  final out = <_LigneEcartee>[];
  final data = jsonDecode(corps);
  if (data is! List) return out;
  for (final item in data) {
    if (item is! Map) continue;
    final code = item['typePari'] as String? ?? '';
    final liste = item['rapports'];
    if (liste is! List) continue;
    for (final r in liste) {
      if (r is! Map) continue;
      final a = r['dividendePourUnEuro'];
      final b = r['dividende'];
      final num? v = a is num ? a : (b is num ? b : null);
      if (v == null) continue;
      if (v > 0) continue; // conservé par le filtre
      out.add(_LigneEcartee(
        codeBloc: code,
        libelle: r['libelle']?.toString() ?? '',
        combinaison: r['combinaison']?.toString() ?? '',
        rang: r['rangCombinaisonPayable'] is num
            ? (r['rangCombinaisonPayable'] as num).toInt()
            : null,
        nombreGagnants: r['nombreGagnants'] is num
            ? r['nombreGagnants'] as num
            : null,
        dividendeCentimes: v,
      ));
    }
  }
  return out;
}

/// Reproduit fidèlement `decoderRapportsDefinitifs` SANS le filtre `> 0`.
/// Sert uniquement à mesurer ce qui se passerait si le filtre disparaissait.
List<RapportPmu> _decoderSansFiltre(String corps) {
  final out = <RapportPmu>[];
  final data = jsonDecode(corps);
  if (data is! List) return out;
  for (final item in data) {
    if (item is! Map) continue;
    final typePari = item['typePari'] as String? ?? '';
    final liste = item['rapports'] as List<dynamic>? ?? const [];
    final rembourseBloc = item['rembourse'] == true;
    final miseBaseBrute = item['miseBase'];
    final miseBase = miseBaseBrute is num ? miseBaseBrute.toInt() : null;
    final uniteBloc = item['dividendeUnite']?.toString() ?? '';

    for (final r in liste) {
      if (r is! Map) continue;
      final combinaison = r['combinaison'] as String? ?? '';
      final rawA = r['dividendePourUnEuro'];
      final rawB = r['dividende'];
      double d = 0.0;
      if (rawA is num) {
        d = rawA.toDouble() / 100.0;
      } else if (rawB is num) {
        d = rawB.toDouble() / 100.0;
      }
      // ─── AUCUN FILTRE ICI : c'est l'objet de la mesure ───
      final rangBrut = r['rangCombinaisonPayable'];
      out.add(RapportPmu(
        typePari: typePari,
        combinaison: combinaison,
        dividende: d,
        estOrdre: !combinaison.contains('NP') &&
            !combinaison.contains('D') &&
            !combinaison.contains('d'),
        libelleOfficiel: r['libelle']?.toString() ?? '',
        codePariOfficiel: typePari,
        rangCombinaisonPayable: rangBrut is num ? rangBrut.toInt() : null,
        rembourse: rembourseBloc,
        miseBaseCentimes: miseBase,
        dividendeUnite: (r['dividendeUnite']?.toString().isNotEmpty ?? false)
            ? r['dividendeUnite'].toString()
            : uniteBloc,
      ));
    }
  }
  return out;
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
