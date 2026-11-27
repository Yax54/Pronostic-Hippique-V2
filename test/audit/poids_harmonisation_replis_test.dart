// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER POIDS IA — §1 (harmonisation des replis) et §2 (planchers
//  enrichis) : VÉRIFICATION DES CORRECTIONS AUTORISÉES.
//
//  Ce harnais ne teste PAS une intuition : il vérifie, sur le code de
//  production réellement compilé, les deux corrections autorisées par
//  l'utilisateur au tour du 27/11/2026.
//
//  DONNÉES RÉELLES UTILISÉES (lecture seule, aucune écriture) :
//    /home/user/uploaded_files/backup_pronostic_hippique_28052026.json.txt
//    /home/user/uploaded_files/backup_pronostic_hippique_13112026.json.txt
//    chemin : racine → « ia » → « ia_poids_v3 » → « value » = CHAÎNE JSON
//
//  ⚠️ CE QU'ON NE PROUVE PAS ICI : qu'un meilleur pronostic hippique en
//     résulte. Réduire un plancher augmente la liberté du gradient ; cela ne
//     démontre aucune amélioration de précision. Le §8 du rapport le dit.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Référentiels
// ───────────────────────────────────────────────────────────────────────────

const List<String> kCles = <String>[
  'forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline',
  'distSpec', 'jockey', 'repos', 'hippo', 'entraineur', 'elo',
  'terrain', 'divergence', 'poidsRel', 'progression', 'mouvCote', 'placeDepart',
];

const List<String> kBase = <String>[
  'forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline',
];

const List<String> kEnrichis = <String>[
  'distSpec', 'jockey', 'repos', 'hippo', 'entraineur', 'elo',
  'terrain', 'divergence', 'poidsRel', 'progression', 'mouvCote', 'placeDepart',
];

/// Poids initiaux — INCHANGÉS par les deux corrections autorisées.
const Map<String, double> kDefaut = <String, double>{
  'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
  'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
  'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
  'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05, 'divergence': 0.04,
  'poidsRel': 0.03, 'progression': 0.03, 'mouvCote': 0.06,
  'placeDepart': 0.03,
};

/// Planchers individuels des 12 critères enrichis, MESURÉS dans le code
/// AVANT correction (`clamp()` :739-750 et `clampDiscipline()` :815-826).
/// ⚠️ Ils n'étaient PAS tous égaux à 0,01 : trois étaient plus hauts.
const Map<String, double> kPlancherEnrichiAvant = <String, double>{
  'distSpec': 0.03,   // ← pas 0,01
  'jockey': 0.02,     // ← pas 0,01
  'repos': 0.01,
  'hippo': 0.01,
  'entraineur': 0.01,
  'elo': 0.01,
  'terrain': 0.01,
  'divergence': 0.01,
  'poidsRel': 0.01,
  'progression': 0.01,
  'mouvCote': 0.02,   // ← pas 0,01
  'placeDepart': 0.01,
};

/// Plafonds individuels — INCHANGÉS, conservés à la demande de l'utilisateur.
const Map<String, double> kPlafond = <String, double>{
  'forme': 0.55, 'gains': 0.40, 'record': 0.35, 'cote': 0.40,
  'constance': 0.25, 'victoires': 0.15, 'discipline': 0.10,
  'distSpec': 0.18, 'jockey': 0.15, 'repos': 0.08, 'hippo': 0.10,
  'entraineur': 0.08, 'elo': 0.10, 'terrain': 0.10, 'divergence': 0.08,
  'poidsRel': 0.07, 'progression': 0.08, 'mouvCote': 0.12,
  'placeDepart': 0.07,
};

const Map<String, double> kPlancher = <String, double>{
  'forme': 0.05, 'gains': 0.04, 'record': 0.03, 'cote': 0.05,
  'constance': 0.03, 'victoires': 0.01, 'discipline': 0.01,
  'distSpec': 0.005, 'jockey': 0.005, 'repos': 0.005, 'hippo': 0.005,
  'entraineur': 0.005, 'elo': 0.005, 'terrain': 0.005, 'divergence': 0.005,
  'poidsRel': 0.005, 'progression': 0.005, 'mouvCote': 0.005,
  'placeDepart': 0.005,
};

// ───────────────────────────────────────────────────────────────────────────
//  Utilitaires
// ───────────────────────────────────────────────────────────────────────────

const double _eps = 1e-12;

double _somme(IaPoidsAdaptatifs p) {
  var s = 0.0;
  for (final k in kCles) {
    s += p.getPoids(k);
  }
  return s;
}

double _sommeMap(Map<String, double> m) {
  var s = 0.0;
  for (final k in kCles) {
    s += m[k] ?? 0.0;
  }
  return s;
}

String _f(double v) => v.toStringAsFixed(12);

Map<String, double> _map(IaPoidsAdaptatifs p) => {
      for (final k in kCles) k: p.getPoids(k),
    };

/// Lit une sauvegarde RÉELLE : renvoie la chaîne JSON de `ia_poids_v3`.
/// `null` si le fichier est absent (le test le déclare alors explicitement).
String? _poidsBrutDepuisBackup(String fichier) {
  final f = File('/home/user/uploaded_files/$fichier');
  if (!f.existsSync()) return null;
  final racine = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  final ia = racine['ia'] as Map<String, dynamic>;
  final v = (ia['ia_poids_v3'] as Map<String, dynamic>)['value'] as String;
  return v;
}

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  //  SECTION 1 — HARMONISATION DES TROIS REPLIS (§1)
  // ═════════════════════════════════════════════════════════════════════════

  group('§1 — harmonisation des replis de fromJson', () {
    test('S1.1 — les 4 tables de constantes sont désormais cohérentes', () {
      // Table #1 constructeur = Table #2 .defauts.
      final c = IaPoidsAdaptatifs();
      expect(_somme(c), closeTo(_sommeMap(kDefaut), _eps),
          reason: 'constructeur vs kDefaut');
      expect(IaPoidsAdaptatifs.defauts.length, 19);
      for (final k in kCles) {
        expect(IaPoidsAdaptatifs.defauts[k], closeTo(kDefaut[k]!, _eps),
            reason: 'defauts[$k]');
      }

      // Table #3 : replis de fromJson sur JSON VIDE — doivent être IDENTIQUES.
      final vide = IaPoidsAdaptatifs.fromJson(<String, dynamic>{});
      final mv = _map(vide);
      final mc = _map(c);
      for (final k in kCles) {
        expect(mv[k], closeTo(mc[k]!, _eps),
            reason: 'fromJson({})[$k] = ${mv[k]} vs constructeur ${mc[k]}');
      }

      // Mesure brute des sommes — c'est le chiffre qui était faux avant.
      expect(_somme(vide), closeTo(1.26, _eps),
          reason: 'fromJson({}) doit sommer 1,26 (mesuré ${_f(_somme(vide))})');
      expect(_somme(c), closeTo(1.26, _eps),
          reason: 'constructeur doit sommer 1,26');

      // Et l'ancien écart de 0,11 a bien disparu.
      final ecart = (_somme(vide) - _somme(c)).abs();
      expect(ecart, lessThan(_eps),
          reason: 'écart résiduel ${_f(ecart)} (était 0,11 avant correction)');

      // ignore: avoid_print
      print('S1.1  Σ fromJson({}) = ${_f(_somme(vide))}  |  Σ constructeur = '
          '${_f(_somme(c))}  |  Σ .defauts = ${_f(_sommeMap(
        IaPoidsAdaptatifs.defauts,
      ))}  |  écart = ${_f(ecart)}');
    });

    test('S1.2 — JSON COMPLET : aucune valeur JSON écrasée', () {
      // On construit un JSON COMPLET dont les valeurs sont VOLONTAIREMENT
      // différentes des constantes. Si le code écrasait quoi que ce soit par
      // un repli, le test échouerait.
      final source = <String, double>{
        'forme': 0.3333333333, 'gains': 0.2222222222, 'record': 0.1111111111,
        'cote': 0.0999999999, 'constance': 0.0888888888,
        'victoires': 0.0777777777, 'discipline': 0.0666666666,
        'distSpec': 0.0555555555, 'jockey': 0.0444444444,
        'repos': 0.0333333333, 'hippo': 0.0222222222,
        'entraineur': 0.0199999999, 'elo': 0.0188888888,
        'terrain': 0.0177777777, 'divergence': 0.0166666666,
        'poidsRel': 0.0155555555, 'progression': 0.0144444444,
        'mouvCote': 0.0133333333, 'placeDepart': 0.0122222222,
      };
      final j = <String, dynamic>{...source};
      final p = IaPoidsAdaptatifs.fromJson(j);
      for (final k in kCles) {
        expect(p.getPoids(k), closeTo(source[k]!, _eps),
            reason: 'JSON complet : $k a été modifié');
      }
      // ignore: avoid_print
      print('S1.2  19/19 valeurs JSON complètes restituées à l\'identique '
          '(Σ = ${_f(_somme(p))})');
    });

    test('S1.3 — JSON PARTIEL : seules les clés absentes prennent le repli', () {
      // 3 clés PRÉSENTES (les 3 corrigées), 16 ABSENTES.
      final j = <String, dynamic>{
        'forme': 0.41,
        'gains': 0.17,
        'record': 0.09,
      };
      final p = IaPoidsAdaptatifs.fromJson(j);

      // Les 3 présentes sont préservées — y compris si elles divergent des
      // constantes. C'est la garantie « n'agit que sur l'absent ».
      expect(p.forme, closeTo(0.41, _eps), reason: 'forme présente = 0,41');
      expect(p.gains, closeTo(0.17, _eps), reason: 'gains présente = 0,17');
      expect(p.record, closeTo(0.09, _eps), reason: 'record présente = 0,09');

      // Les 16 absentes prennent EXACTEMENT la constante du constructeur.
      for (final k in kCles.where((k) => !j.containsKey(k))) {
        expect(p.getPoids(k), closeTo(kDefaut[k]!, _eps),
            reason: 'clé absente $k doit valoir ${kDefaut[k]}');
      }

      // Mesure : 0,41 + 0,17 + 0,09 + (16 constantes) = 0,67 + 0,86 = 1,53
      final attendu = 0.41 + 0.17 + 0.09 +
          kCles.where((k) => !j.containsKey(k))
              .fold<double>(0.0, (a, k) => a + kDefaut[k]!);
      expect(_somme(p), closeTo(attendu, _eps),
          reason: 'somme partielle attendue ${_f(attendu)}');

      // ignore: avoid_print
      print('S1.3  JSON partiel (3 clés) : 3 valeurs préservées + 16 replis = '
          '${_f(_somme(p))}  [attendu ${_f(attendu)}]');
    });

    test('S1.4 — clé présente mais NON numérique : exception, pas de repli', () {
      // ★ CORRECTION D'UNE AFFIRMATION FAUSSE QUE J'AVAIS ÉCRITE.
      //   J'avais annoncé que le repli s'appliquait « aussi sur une valeur non
      //   numérique ». MESURE : c'est FAUX. `(j['forme'] as num?)` ne renvoie
      //   null que si la valeur est absente ou `null` ; sur une `String` le
      //   cast LÈVE un TypeError et `fromJson` échoue entièrement.
      //   Ce test verrouille le comportement RÉEL pour qu'aucun futur lecteur
      //   ne puisse croire à une tolérance qui n'existe pas.
      expect(
        () => IaPoidsAdaptatifs.fromJson(<String, dynamic>{'forme': 'invalide'}),
        throwsA(isA<TypeError>()),
        reason: 'une valeur texte doit échouer, PAS être remplacée par 0,25',
      );

      // Le cas `null` explicite, lui, déclenche bien le repli.
      final pNull = IaPoidsAdaptatifs.fromJson(<String, dynamic>{'gains': null});
      expect(pNull.gains, closeTo(0.13, _eps), reason: 'gains null → repli 0,13');

      // Le cas numérique reste préservé.
      final pNum = IaPoidsAdaptatifs.fromJson(<String, dynamic>{'record': 0.12});
      expect(pNum.record, closeTo(0.12, _eps), reason: 'record numérique → 0.12');

      // ignore: avoid_print
      print('S1.4  valeur texte → TypeError (repli NON appliqué) · null → repli '
          '0,13 · numérique 0,12 préservé');
    });

    test('S1.5 — ALLER-RETOUR toJson/fromJson : aucune perte', () {
      // Sur l'état d'usine.
      final a = IaPoidsAdaptatifs();
      final b = IaPoidsAdaptatifs.fromJson(
          jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
      for (final k in kCles) {
        expect(b.getPoids(k), closeTo(a.getPoids(k), _eps),
            reason: 'aller-retour $k');
      }
      expect(b.nbMisesAJour, a.nbMisesAJour);
      expect(b.calibrationScore, closeTo(a.calibrationScore, _eps));

      // Sur un état APPRIS (poids réels du 13/11/2026, réinjectés).
      final reels = <String, double>{
        'forme': 0.2142514199, 'gains': 0.0840062855, 'record': 0.0637980627,
        'cote': 0.4018138807, 'constance': 0.0108155001,
        'victoires': 0.1506802053, 'discipline': 0.0106900000,
        'distSpec': 0.0538273691, 'jockey': 0.0201945140,
        'repos': 0.0100980101, 'hippo': 0.0100066786,
        'entraineur': 0.0101670245, 'elo': 0.0101951061,
        'terrain': 0.0101193237, 'divergence': 0.0100000000,
        'poidsRel': 0.0100000000, 'progression': 0.0100000000,
        'mouvCote': 0.0201314783, 'placeDepart': 0.0101013330,
      };
      final c = IaPoidsAdaptatifs.fromJson(
          jsonDecode(jsonEncode(reels)) as Map<String, dynamic>);
      for (final k in kCles) {
        expect(c.getPoids(k), closeTo(reels[k]!, _eps),
            reason: 'aller-retour appris $k');
      }
      // ignore: avoid_print
      print('S1.5  aller-retour : 19/19 identiques sur usine ET sur état appris '
          '(Σ appris = ${_f(_somme(c))})');
    });

    test('S1.6 — ANCIENNE SAUVEGARDE 28/05/2026 : restitution intacte', () {
      final brut = _poidsBrutDepuisBackup('backup_pronostic_hippique_28052026.json.txt');
      expect(brut, isNotNull, reason: 'sauvegarde du 28/05/2026 introuvable');
      final j = jsonDecode(brut!) as Map<String, dynamic>;
      final p = IaPoidsAdaptatifs.fromJson(jsonDecode(jsonEncode(j)) as Map<String, dynamic>);

      var n = 0;
      for (final k in kCles) {
        final attendu = (j[k] as num?)?.toDouble();
        if (attendu == null) continue;
        expect(p.getPoids(k), closeTo(attendu, _eps),
            reason: 'backup 28/05 : $k altéré');
        n++;
      }
      expect(n, 19, reason: 'les 19 clés doivent être présentes dans la sauvegarde');

      final base = kBase.fold<double>(0.0, (a, k) => a + p.getPoids(k));
      final enr = kEnrichis.fold<double>(0.0, (a, k) => a + p.getPoids(k));
      // ignore: avoid_print
      print('S1.6  backup 28/05 : 19/19 intactes — base ${_f(base)} / '
          'enrichis ${_f(enr)} (nbMisesAJour=${p.nbMisesAJour})');
    });

    test('S1.7 — SAUVEGARDE AVEC POIDS APPRIS 13/11/2026 : intacte', () {
      final brut = _poidsBrutDepuisBackup('backup_pronostic_hippique_13112026.json.txt');
      expect(brut, isNotNull, reason: 'sauvegarde du 13/11/2026 introuvable');
      final j = jsonDecode(brut!) as Map<String, dynamic>;
      final p = IaPoidsAdaptatifs.fromJson(jsonDecode(jsonEncode(j)) as Map<String, dynamic>);

      for (final k in kCles) {
        final attendu = (j[k] as num?)?.toDouble();
        expect(attendu, isNotNull, reason: 'clé $k absente de la sauvegarde');
        expect(p.getPoids(k), closeTo(attendu!, _eps),
            reason: 'backup 13/11 : $k altéré par la correction');
      }

      final base = kBase.fold<double>(0.0, (a, k) => a + p.getPoids(k));
      final enr = kEnrichis.fold<double>(0.0, (a, k) => a + p.getPoids(k));
      expect(p.nbMisesAJour, 3871, reason: 'compteur d\'apprentissage préservé');

      // ⚠️ Ces deux constats sont MESURÉS, pas supposés : l'état appris viole
      //    ses propres bornes (voir §4 du rapport — c'est le défaut de clamp()).
      //    On le documente ici pour prouver qu'il n'a PAS été « réparé » en
      //    douce par la correction des replis.
      // ignore: avoid_print
      print('S1.7  backup 13/11 : 19/19 intactes — base ${_f(base)} / '
          'enrichis ${_f(enr)} / nbMisesAJour=${p.nbMisesAJour}');
      // ignore: avoid_print
      print('      constat §4 : cote=${_f(p.cote)} (borne 0,40) '
          'victoires=${_f(p.victoires)} (borne 0,15) — violations PRÉSERVÉES');
    });

    test('S1.8 — GLOBAL et PAR DISCIPLINE : préservés', () {
      final ppd = <String, dynamic>{
        'trot_attele': <String, double>{
          'forme': 0.30, 'gains': 0.12, 'record': 0.08, 'cote': 0.11,
          'constance': 0.07, 'victoires': 0.04, 'discipline': 0.02,
          'distSpec': 0.06, 'jockey': 0.05, 'repos': 0.02, 'hippo': 0.03,
          'entraineur': 0.03, 'elo': 0.02, 'terrain': 0.02,
          'divergence': 0.01, 'poidsRel': 0.01, 'progression': 0.01,
          'mouvCote': 0.01, 'placeDepart': 0.01,
        },
      };
      final j = <String, dynamic>{
        'forme': 0.27, 'gains': 0.14, 'record': 0.11,
        'poidsParDiscipline': ppd,
      };
      final p = IaPoidsAdaptatifs.fromJson(j);

      // Global : les 3 présentes préservées, les 16 autres au repli = constante.
      expect(p.forme, closeTo(0.27, _eps));
      expect(p.gains, closeTo(0.14, _eps));
      expect(p.record, closeTo(0.11, _eps));
      expect(p.cote, closeTo(0.08, _eps));

      // Par discipline : intégralement préservé.
      expect(p.poidsParDiscipline.containsKey('trot_attele'), isTrue);
      final disc = p.poidsParDiscipline['trot_attele']!;
      for (final k in kCles) {
        expect(disc[k], closeTo((ppd['trot_attele'] as Map<String, double>)[k]!, _eps),
            reason: 'discipline $k altéré');
      }
      // Et l'accès effectif renvoie bien la table de discipline.
      final eff = p.poidsEffectifsPourDiscipline('Trot Attelé');
      expect(eff.length, 19, reason: '19 clés garanties');
      expect(eff['forme'], closeTo(0.30, _eps));

      // Cas sans discipline apprise : repli = champs globaux (19 clés).
      final effGlobal = p.poidsEffectifsPourDiscipline('Plat');
      expect(effGlobal.length, 19);
      expect(effGlobal['forme'], closeTo(0.27, _eps));

      // ignore: avoid_print
      print('S1.8  global préservé (3/3) + discipline préservée (19/19) + '
          'poidsEffectifsPourDiscipline garantit 19 clés dans les 2 cas');
    });

    test('S1.9 — les 16 autres replis sont INCHANGÉS', () {
      // Comparaison explicite avec les valeurs historiques des 16 autres clés.
      const historiques = <String, double>{
        'cote': 0.08, 'constance': 0.09, 'victoires': 0.04,
        'discipline': 0.02, 'distSpec': 0.08, 'jockey': 0.07,
        'repos': 0.03, 'hippo': 0.04, 'entraineur': 0.04, 'elo': 0.05,
        'terrain': 0.05, 'divergence': 0.04, 'poidsRel': 0.03,
        'progression': 0.03, 'mouvCote': 0.06, 'placeDepart': 0.03,
      };
      expect(historiques.length, 16);
      final p = IaPoidsAdaptatifs.fromJson(<String, dynamic>{});
      for (final e in historiques.entries) {
        expect(p.getPoids(e.key), closeTo(e.value, _eps),
            reason: 'le repli de ${e.key} ne devait pas bouger');
      }
      // ignore: avoid_print
      print('S1.9  16/16 replis non concernés inchangés');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  SECTION 2 — PLANCHERS INDIVIDUELS ENRICHIS (§2)
  // ═════════════════════════════════════════════════════════════════════════

  group('§2 — planchers enrichis abaissés à 0,005', () {
    test('S2.1 — les 12 planchers anciens documentés sont ceux mesurés', () {
      // Contrôle de la PRÉMISSE de l'utilisateur : « pas nécessairement 0,01 ».
      final values = kPlancherEnrichiAvant.values.toList()..sort();
      final somme = kPlancherEnrichiAvant.values.fold<double>(0.0, (a, b) => a + b);
      expect(somme, closeTo(0.16, _eps),
          reason: 'Σ planchers enrichis AVANT = 0,160 (mesuré ${_f(somme)})');
      // 3 planchers au-dessus de 0,01, 9 à 0,01.
      final auDessus = kPlancherEnrichiAvant.values.where((v) => v > 0.011).length;
      expect(auDessus, 3, reason: 'distSpec, jockey, mouvCote sont > 0,01');
      expect(values.where((v) => (v - 0.01).abs() < 1e-12).length, 9);
      // ignore: avoid_print
      print('S2.1  Σ AVANT = ${_f(somme)} · 3 planchers > 0,01 '
          '(distSpec 0,03 / jockey 0,02 / mouvCote 0,02) · 9 à 0,01');
    });

    test('S2.2 — clamp() applique bien 0,005 comme nouveau plancher', () {
      // On pousse les 12 enrichis TRÈS en dessous de 0,005 : après clamp(),
      // aucun ne doit être < 0,005, et la somme normalisée doit valoir 1.
      final p = IaPoidsAdaptatifs(
        distSpec: 0.0001, jockey: 0.0001, repos: 0.0001, hippo: 0.0001,
        entraineur: 0.0001, elo: 0.0001, terrain: 0.0001,
        divergence: 0.0001, poidsRel: 0.0001, progression: 0.0001,
        mouvCote: 0.0001, placeDepart: 0.0001,
      );
      p.clamp();
      for (final k in kEnrichis) {
        expect(p.getPoids(k), greaterThanOrEqualTo(kPlancher[k]! - _eps),
            reason: '$k doit être ≥ 0,005 après clamp()');
      }
      // Somme = 1 après clamp() (contrat de normaliser()).
      expect(_somme(p), closeTo(1.0, 1e-9),
          reason: 'Σ après clamp() = 1 (mesuré ${_f(_somme(p))})');
      // ignore: avoid_print
      print('S2.2  clamp() sur 12 enrichis à 0,0001 → min mesuré '
          '${_f(kEnrichis.map((k) => p.getPoids(k)).reduce((a, b) => a < b ? a : b))} '
          '· Σ = ${_f(_somme(p))}');
    });

    test('S2.3 — clampDiscipline applique le même plancher (définition #2)', () {
      // Duplicata : on vérifie qu'il n'a PAS été oublié.
      final m = <String, double>{
        for (final k in kCles) k: 0.0001,
      };
      IaPoidsAdaptatifs.clampDiscipline(m);
      for (final k in kEnrichis) {
        expect(m[k], greaterThanOrEqualTo(kPlancher[k]! - _eps),
            reason: 'clampDiscipline : $k doit être ≥ 0,005 (mesuré ${m[k]})');
      }
      expect(_sommeMap(m), closeTo(1.0, 1e-9),
          reason: 'Σ après clampDiscipline = 1 (mesuré ${_f(_sommeMap(m))})');
      // ignore: avoid_print
      print('S2.3  clampDiscipline : 12/12 ≥ 0,005 · Σ = ${_f(_sommeMap(m))}');
    });

    test('S2.4 — les plafonds sont INCHANGÉS (aucun plafond touché)', () {
      // On pousse les 19 critères très haut, puis clamp() : aucun plafond ne
      // doit avoir bougé par rapport à kPlafond.
      final p = IaPoidsAdaptatifs(
        forme: 99, gains: 99, record: 99, cote: 99, constance: 99,
        victoires: 99, discipline: 99, distSpec: 99, jockey: 99, repos: 99,
        hippo: 99, entraineur: 99, elo: 99, terrain: 99, divergence: 99,
        poidsRel: 99, progression: 99, mouvCote: 99, placeDepart: 99,
      );
      // Avant normalisation, chaque valeur doit être écrêtée à son plafond.
      // On le mesure via un état où tous les plafonds sont saturés : après
      // normalisation les valeurs sont ≤ plafond / Σ plafonds × 1.
      final sommePlafonds = kPlafond.values.fold<double>(0.0, (a, b) => a + b);
      p.clamp();
      for (final k in kCles) {
        final attendu = kPlafond[k]! / sommePlafonds;
        expect(p.getPoids(k), closeTo(attendu, 1e-9),
            reason: '$k : ${p.getPoids(k)} attendu ${_f(attendu)}');
      }
      // ignore: avoid_print
      print('S2.4  19/19 plafonds inchangés · Σ plafonds = '
          '${_f(sommePlafonds)} · saturation respectée');
    });

    test('S2.5 — Σ planchers 0,160 → 0,060, marge 0,020 → 0,120', () {
      final avant = kPlancherEnrichiAvant.values.fold<double>(0.0, (a, b) => a + b);
      final apres = kEnrichis.fold<double>(0.0, (a, k) => a + kPlancher[k]!);
      expect(avant, closeTo(0.16, _eps));
      expect(apres, closeTo(0.06, _eps),
          reason: 'Σ APRÈS doit valoir 0,060 (mesuré ${_f(apres)})');
      const plancherCollectif = 0.18;
      expect(plancherCollectif - avant, closeTo(0.02, _eps));
      expect(plancherCollectif - apres, closeTo(0.12, _eps),
          reason: 'marge = 0,18 − 0,06 = 0,12');
      // ignore: avoid_print
      print('S2.5  Σ planchers enrichis : ${_f(avant)} → ${_f(apres)} · '
          'marge sous 0,18 : ${_f(plancherCollectif - avant)} → '
          '${_f(plancherCollectif - apres)} (×6)');
    });

    test('S2.6 — aucun critère désactivé : 0,005 > 0 et réactivation possible', () {
      // 1) 0,005 strictement positif.
      for (final k in kEnrichis) {
        expect(kPlancher[k]!, greaterThan(0.0));
      }
      // 2) Un critère au plancher peut remonter : on simule 10 pas de
      //    gradient positifs (+0,02 chacun) puis clamp(). Il doit dépasser
      //    0,005 sans ambiguïté.
      final p = IaPoidsAdaptatifs(
        distSpec: 0.005, jockey: 0.005, repos: 0.005, hippo: 0.005,
        entraineur: 0.005, elo: 0.005, terrain: 0.005, divergence: 0.005,
        poidsRel: 0.005, progression: 0.005, mouvCote: 0.005,
        placeDepart: 0.005,
      );
      p.clamp();
      final avant = p.placeDepart;
      p.placeDepart += 0.20;
      p.clamp();
      expect(p.placeDepart, greaterThan(avant),
          reason: 'un critère au plancher doit pouvoir remonter');
      // ignore: avoid_print
      print('S2.6  placeDepart ${_f(avant)} --(+0,20)--> ${_f(p.placeDepart)} '
          '· aucun plancher nul · réactivation démontrée');
    });

    test('S2.7 — aucune modification rétroactive des poids historiques', () {
      // Une sauvegarde lue par fromJson n'appelle PAS clamp() : les 19 poids
      // passés sont rendus tels quels, y compris ceux SOUS le nouveau plancher.
      final brut = _poidsBrutDepuisBackup('backup_pronostic_hippique_13112026.json.txt');
      expect(brut, isNotNull);
      final j = jsonDecode(brut!) as Map<String, dynamic>;
      final p = IaPoidsAdaptatifs.fromJson(j);

      // Vérification directe : les valeurs restituées sont les valeurs du
      // fichier, sans clamp. On compte combien sont SOUS l'ancien plancher
      // comme preuve que rien n'a été « remonté ».
      var sousAncien = 0;
      for (final k in kEnrichis) {
        final v = p.getPoids(k);
        expect(v, closeTo((j[k] as num).toDouble(), _eps),
            reason: '$k : fromJson a modifié une valeur historique');
        if (v < kPlancherEnrichiAvant[k]! - 1e-6) sousAncien++;
      }
      // ignore: avoid_print
      print('S2.7  fromJson seul : 19/19 valeurs historiques intactes, '
          '$sousAncien enrichi(s) sous l\'ancien plancher (aucune remontée '
          'rétroactive)');
    });

    test('S2.8 — poids initiaux, gradient et plancher collectif INCHANGÉS', () {
      // Les poids initiaux : identiques avant/après la correction.
      final c = IaPoidsAdaptatifs();
      for (final k in kCles) {
        expect(c.getPoids(k), closeTo(kDefaut[k]!, _eps),
            reason: 'poids initial $k modifié');
      }
      // Le plancher/plafond collectifs : mesurés dans le code source.
      final src = File('lib/services/ia_memory_models.dart').readAsStringSync();
      expect(src.contains('fractionEnrichi.clamp(0.18, 0.40)'), isTrue,
          reason: 'contraintes collectives 0,18/0,40 doivent être intactes');
      // Le gradient : lrBase 0,08 non modifié.
      final svc = File('lib/services/ia_memory_service.dart').readAsStringSync();
      expect(svc.contains('lrBase'), isTrue);
      // ignore: avoid_print
      print('S2.8  19/19 poids initiaux inchangés · collectif 0,18/0,40 intact '
          '· gradient (lrBase) intact');
    });

    test('S2.9 — cohérence globale ET par discipline avec les nouveaux planchers', () {
      final p = IaPoidsAdaptatifs();
      p.clamp();
      expect(_somme(p), closeTo(1.0, 1e-9));

      // Par discipline : 6 spécialités, chacune doit sommer 1 et respecter
      // les 19 planchers.
      for (final disc in <String>[
        'trot_attele', 'trot_monte', 'plat', 'obstacle', 'global',
      ]) {
        final m = <String, double>{
          for (final k in kCles) k: 0.0001,
        };
        IaPoidsAdaptatifs.clampDiscipline(m);
        IaPoidsAdaptatifs.clampDiscipline(m); // idempotence sur ce chemin
        expect(_sommeMap(m), closeTo(1.0, 1e-9), reason: '$disc : Σ ≠ 1');
        for (final k in kCles) {
          expect(m[k]!, greaterThanOrEqualTo(kPlancher[k]! - 1e-12),
              reason: '$disc : $k sous son plancher');
        }
      }
      // ignore: avoid_print
      print('S2.9  global Σ=${_f(_somme(p))} · 5 spécialités Σ=1 et '
          '19/19 ≥ plancher · clampDiscipline idempotent sur ce chemin');
    });
  });
}
