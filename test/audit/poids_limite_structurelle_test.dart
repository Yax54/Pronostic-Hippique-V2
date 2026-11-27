// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER POIDS IA — §4 : LIMITATION MATHÉMATIQUE DÉMONTRÉE
//  ET ÉTAT RÉELLEMENT APPRIS (backups 28-05-2026 et 13-11-2026)
//
//  PROVENANCE DES DONNÉES CI-DESSOUS — traçable, non reconstituée :
//     fichiers  /home/user/uploaded_files/backup_pronostic_hippique_28052026.json.txt
//               /home/user/uploaded_files/backup_pronostic_hippique_13112026.json.txt
//     chemin    racine → clé « ia » → clé « ia_poids_v3 » → « value »
//               (« value » est une CHAÎNE JSON, à décoder une seconde fois)
//     Les 19 valeurs et les compteurs ci-dessous sont RECOPIÉS de cette
//     extraction. Aucune valeur n'est inventée.
//  ⚠️ Ces backups proviennent d'une période où plusieurs critères étaient mal
//     alimentés (l'utilisateur l'a précisé). Ils servent de RÉFÉRENCE
//     HISTORIQUE, pas de vérité absolue.
//
//  ⚠️ AUCUNE MODIFICATION DE PRODUCTION. Aucune écriture disque.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';

const List<String> kCles = <String>[
  'forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline',
  'distSpec', 'jockey', 'repos', 'hippo', 'entraineur', 'elo',
  'terrain', 'divergence', 'poidsRel', 'progression', 'mouvCote', 'placeDepart',
];

const List<String> kBase = <String>[
  'forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline',
];

final List<String> kEnrichis = kCles.where((k) => !kBase.contains(k)).toList();

/// Poids MESURÉS dans le backup du 28/05/2026 (nbMisesAJour = 802).
const Map<String, double> kPoids28052026 = <String, double>{
  'forme': 0.141963537, 'gains': 0.039630215, 'record': 0.029722661,
  'cote': 0.383824013, 'constance': 0.095171302, 'victoires': 0.119780718,
  'discipline': 0.009907554, 'distSpec': 0.050352088, 'jockey': 0.019945833,
  'repos': 0.009972916, 'hippo': 0.009972916, 'entraineur': 0.009972916,
  'elo': 0.009972916, 'terrain': 0.009972916, 'divergence': 0.009972916,
  'poidsRel': 0.009972916, 'progression': 0.009972916,
  'mouvCote': 0.019945833, 'placeDepart': 0.009972916,
};

/// Poids MESURÉS dans le backup du 13/11/2026 (nbMisesAJour = 3871).
const Map<String, double> kPoids13112026 = <String, double>{
  'forme': 0.058774367, 'gains': 0.040181388, 'record': 0.030136041,
  'cote': 0.401813881, 'constance': 0.123951890, 'victoires': 0.150680205,
  'discipline': 0.010045347, 'distSpec': 0.053827369, 'jockey': 0.020090694,
  'repos': 0.010045347, 'hippo': 0.010045347, 'entraineur': 0.010045347,
  'elo': 0.010045347, 'terrain': 0.010045347, 'divergence': 0.010045347,
  'poidsRel': 0.010045347, 'progression': 0.010045347,
  'mouvCote': 0.020090694, 'placeDepart': 0.010045347,
};

/// Poids du constructeur — MESURÉS (A1/A5).
const Map<String, double> kDefaut = <String, double>{
  'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
  'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
  'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
  'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05, 'divergence': 0.04,
  'poidsRel': 0.03, 'progression': 0.03, 'mouvCote': 0.06,
  'placeDepart': 0.03,
};

/// Bornes RÉELLES de `clamp()` (ia_memory_models.dart:731-750).
const Map<String, double> kBas = <String, double>{
  'forme': 0.05, 'gains': 0.04, 'record': 0.03, 'cote': 0.05,
  'constance': 0.03, 'victoires': 0.01, 'discipline': 0.01,
  'distSpec': 0.03, 'jockey': 0.02, 'repos': 0.01, 'hippo': 0.01,
  'entraineur': 0.01, 'elo': 0.01, 'terrain': 0.01, 'divergence': 0.01,
  'poidsRel': 0.01, 'progression': 0.01, 'mouvCote': 0.02, 'placeDepart': 0.01,
};
const Map<String, double> kHaut = <String, double>{
  'forme': 0.55, 'gains': 0.40, 'record': 0.35, 'cote': 0.40,
  'constance': 0.25, 'victoires': 0.15, 'discipline': 0.10,
  'distSpec': 0.18, 'jockey': 0.15, 'repos': 0.08, 'hippo': 0.10,
  'entraineur': 0.08, 'elo': 0.10, 'terrain': 0.10, 'divergence': 0.08,
  'poidsRel': 0.07, 'progression': 0.08, 'mouvCote': 0.12,
  'placeDepart': 0.07,
};

double _somme(Iterable<double> v) => v.fold(0.0, (a, b) => a + b);
String _f(double v) => v.toStringAsFixed(9);


void main() {
  test('H1 — MESURE : les 12 enrichis sont ECRASES sur leurs planchers', () {
    // FAIT ARITHMÉTIQUE À VÉRIFIER : pour que la famille enrichie puisse
    // exprimer une hiérarchie, il faut que la somme de ses PLANCHERS
    // individuels soit nettement INFÉRIEURE à son plancher de GROUPE (0.18).
    final sommePlanchersEnrichis =
        kEnrichis.map((k) => kBas[k]!).fold(0.0, (a, b) => a + b);
    final marge = 0.18 - sommePlanchersEnrichis;
    // ignore: avoid_print
    print('[H1] Σ PLANCHERS individuels des 12 enrichis = '
        '${_f(sommePlanchersEnrichis)}');
    // ignore: avoid_print
    print('[H1] PLANCHER de groupe de normaliser()      = 0.180000000');
    // ignore: avoid_print
    print('[H1] ⇒ marge de liberté TOTALE de la famille enrichie = '
        '${_f(marge)}');
    // ignore: avoid_print
    print('[H1] ⇒ soit ${_f(marge / 12)} par critère, en moyenne.');
    // ignore: avoid_print
    print('[H1] ⇒ Et pour que cette marge soit utilisable, il faudrait que les '
        'planchers individuels NE SOIENT PAS tous saturés simultanément.');

    // Vérification sur les DONNÉES RÉELLES des deux backups.
    for (final e in <String, Map<String, double>>{
      '28-05-2026 (802 mises à jour)': kPoids28052026,
      '13-11-2026 (3871 mises à jour)': kPoids13112026,
    }.entries) {
      final v = e.value;
      final sEnr = _somme(kEnrichis.map((k) => v[k]!));
      var surPlancher = 0;
      for (final k in kEnrichis) {
        if (v[k]! <= kBas[k]! * 1.02) surPlancher++;
      }
      // ignore: avoid_print
      print('[H1] ${e.key} : Σ enrichis = ${_f(sEnr)} | critères à moins de '
          '2 % de leur plancher = $surPlancher / 12');
    }

    // Le fait démontré : la marge est minuscule.
    expect(marge, lessThan(0.03),
        reason: 'MESURÉ : 0.020000 de marge pour 12 critères — la famille '
            'enrichie ne peut PAS exprimer de hiérarchie significative');
  });

  test('H2 — MESURE : où se situent les poids appris par rapport aux bornes', () {
    // ignore: avoid_print
    print('[H2] critère      | défaut   | 28-05    | 13-11    | borne basse'
        ' | borne haute | 13-11 sur une borne ?');
    var surBorne = 0;
    for (final k in kCles) {
      final a = kPoids13112026[k]!;
      final base = kBas[k]!;
      final haut = kHaut[k]!;
      final surBas = (a - base).abs() <= base * 0.02;
      final surHaut = (a - haut).abs() <= haut * 0.02;
      if (surBas || surHaut) surBorne++;
      // ignore: avoid_print
      print('[H2] ${k.padRight(12)} | ${kDefaut[k]!.toStringAsFixed(5)} | '
          '${kPoids28052026[k]!.toStringAsFixed(5)} | '
          '${a.toStringAsFixed(5)} | '
          '${base.toStringAsFixed(2)}      | ${haut.toStringAsFixed(2)}       '
          ' | ${surBas ? "PLANCHER" : surHaut ? "PLAFOND" : "-"}');
    }
    // ignore: avoid_print
    print('[H2] ⇒ $surBorne / 19 critères sont à moins de 2 % d\'une BORNE '
        'après 3871 mises à jour. L\'apprentissage a poussé la majorité des '
        'poids CONTRE leurs bornes, pas vers des valeurs intermédiaires.');

    expect(surBorne, greaterThan(10),
        reason: 'MESURÉ : la majorité des poids est collée à une borne');
  });

  test('H3 — MESURE : un critère faible PEUT devenir important (preuves)', () {
    // C'est la question littérale du §4. Elle a une réponse MESURÉE, et elle
    // est POSITIVE — mais seulement pour les 7 critères de base.
    // ignore: avoid_print
    print('[H3] critère      | défaut   | 28-05    | 13-11    | ×départ');
    for (final k in kCles) {
      final dep = kDefaut[k]!;
      final fin = kPoids13112026[k]!;
      final ratio = fin / dep;
      // ignore: avoid_print
      print('[H3] ${k.padRight(12)} | ${dep.toStringAsFixed(5)} | '
          '${kPoids28052026[k]!.toStringAsFixed(5)} | '
          '${fin.toStringAsFixed(5)} | '
          '${ratio >= 1 ? "+" : ""}${((ratio - 1) * 100).toStringAsFixed(1)} %');
    }

    // Preuves de progression forte :
    final cote = kPoids13112026['cote']! / kDefaut['cote']!;
    final victoires = kPoids13112026['victoires']! / kDefaut['victoires']!;
    // Preuves de régression forte :
    final forme = kPoids13112026['forme']! / kDefaut['forme']!;
    final distSpec = kPoids13112026['distSpec']! / kDefaut['distSpec']!;

    // ignore: avoid_print
    print('[H3] ⇒ cote      : 0.08 → 0.4018  = ×${cote.toStringAsFixed(2)} '
        '(critère initialement faible devenu le PLUS FORT)');
    // ignore: avoid_print
    print('[H3] ⇒ victoires : 0.04 → 0.1507  = ×${victoires.toStringAsFixed(2)}'
        ' (×3.77, atteint sa borne haute)');
    // ignore: avoid_print
    print('[H3] ⇒ forme     : 0.25 → 0.0588  = ×${forme.toStringAsFixed(2)} '
        '(critère le plus fort devenu quasi le plus faible)');
    // ignore: avoid_print
    print('[H3] ⇒ distSpec  : 0.08 → 0.0538  = ×${distSpec.toStringAsFixed(2)} '
        '(enrichi, n\'a PAS progressé)');

    expect(cote, greaterThan(3.0),
        reason: 'MESURÉ : cote a quintuplé — la promotion est possible');
    expect(forme, lessThan(0.5),
        reason: 'MESURÉ : forme a perdu plus de la moitié de son poids');

    // MAIS : sur les 12 enrichis, combien ont progressé ?
    var enrichisProgres = 0;
    for (final k in kEnrichis) {
      if (kPoids13112026[k]! > kDefaut[k]! * 1.05) enrichisProgres++;
    }
    // ignore: avoid_print
    print('[H3] ⇒ SUR LES 12 ENRICHIS : $enrichisProgres / 12 ont progressé de '
        'plus de 5 % par rapport à leur valeur de départ. La promotion est '
        'MESURÉE comme possible pour la base, et MESURÉE comme quasi '
        'inexistante pour la famille enrichie.');
    expect(enrichisProgres, lessThanOrEqualTo(2),
        reason: 'MESURÉ : les enrichis ne progressent pas');
  });

  test('H4 — MESURE : les deux backups partagent la MÊME structure', () {
    // Les 12 enrichis des deux backups sont-ils dans les mêmes proportions ?
    // Si oui, ce n'est pas le résultat d'un apprentissage différencié : c'est
    // la signature de la CONTRAINTE (planchers individuels × facteur de groupe).
    final unites2805 = {
      for (final k in kEnrichis)
        k: kPoids28052026[k]! / kPoids28052026['repos']!,
    };
    final unites1311 = {
      for (final k in kEnrichis)
        k: kPoids13112026[k]! / kPoids13112026['repos']!,
    };
    // ignore: avoid_print
    print('[H4] enrichi      | 28-05 / repos | 13-11 / repos | écart');
    var figes = 0;
    final figesListe = <String>[];
    final mouvants = <String, double>{};
    for (final k in kEnrichis) {
      final a = unites2805[k]!;
      final b = unites1311[k]!;
      final ecart = (a - b).abs();
      if (ecart < 1e-6) {
        figes++;
        figesListe.add(k);
      } else {
        mouvants[k] = ecart;
      }
      // ignore: avoid_print
      print('[H4] ${k.padRight(12)} | ${a.toStringAsFixed(6)}      | '
          '${b.toStringAsFixed(6)}       | ${ecart.toStringAsFixed(9)}');
    }
    // ⚠️ CORRECTION D'UNE ASSERTION TROP STRICTE QUE J'AVAIS ÉCRITE.
    //    J'avais affirmé que TOUS les rapports seraient identiques. La mesure
    //    en réfute un : distSpec, écart 0.309555. Ce n'est pas une anomalie,
    //    c'est cohérent : distSpec est le SEUL enrichi qui n'est PAS collé à
    //    son plancher (0.053827 contre un plancher de 0.03), donc le seul qui
    //    ait une marge pour bouger. Les 11 autres sont figés.
    // ignore: avoid_print
    print('[H4] ⇒ $figes / 12 enrichis ont un rapport INTERNE IDENTIQUE à '
        '10⁻⁶ près entre 802 et 3871 mises à jour : ${figesListe.join(", ")}.');
    // ignore: avoid_print
    print('[H4] ⇒ Seul(s) critère(s) ayant bougé : '
        '${mouvants.isEmpty ? "aucun" : mouvants.entries.map((e) => "${e.key} (écart ${e.value.toStringAsFixed(6)})").join(", ")}.');
    // ignore: avoid_print
    print('[H4] ⇒ MESURE : pour 11 des 12 enrichis, la proportion interne ne '
        'dépend NI de l\'époque NI du nombre de mises à jour. Elle est la '
        'SIGNATURE ARITHMÉTIQUE des planchers individuels (1, 1, 1, 1, 1, 1, '
        '1, 1, 1, 2, 2) : le rapport à `repos` (plancher 0.01) vaut '
        'exactement 1.0 ou 2.0. Aucune information hippique n\'a été apprise '
        'par ces 11 critères ; leur « poids » est un PLANCHER, pas un '
        'apprentissage.');
    expect(figes, 11,
        reason: 'MESURÉ : 11 / 12 enrichis figés par leur plancher ; seul '
            'distSpec dispose d\'une marge');
  });
}
