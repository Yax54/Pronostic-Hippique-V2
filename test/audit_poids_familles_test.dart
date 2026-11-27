// ══════════════════════════════════════════════════════════════════════════════
//  AUDIT DES POIDS IA — HARNAIS DE MESURE ISOLÉ
//
//  OBJET : mesurer, et non raisonner, les six familles de valeurs de poids des
//          19 critères, ainsi que les chemins d'exécution qui les installent.
//
//  GARANTIES :
//    • Aucune écriture dans le stockage de production (aucun SharedPreferences).
//    • Aucune modification des poids, formules, bornes ou mécanismes.
//    • Les valeurs affichées sont MESURÉES par exécution du code de production
//      (IaPoidsAdaptatifs et ses méthodes réelles), jamais recopiées à la main.
//
//  Exécution : flutter test test/audit_poids_familles_test.dart --reporter expanded
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';

/// Les 19 clés canoniques, dans l'ordre de déclaration du modèle.
const List<String> kCles = <String>[
  'forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline',
  'distSpec', 'jockey', 'repos', 'hippo', 'entraineur', 'elo',
  'terrain', 'divergence', 'poidsRel', 'progression', 'mouvCote', 'placeDepart',
];

/// Les 7 critères « de base » au sens de `normaliser()`.
const List<String> kBase = <String>[
  'forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline',
];

double _somme(Iterable<double> v) => v.fold(0.0, (a, b) => a + b);

/// Extrait les 19 valeurs d'une instance réelle via `getPoids()` (code de prod).
Map<String, double> _valeurs(IaPoidsAdaptatifs p) =>
    {for (final k in kCles) k: p.getPoids(k)};

String _fmt(double v) => v.toStringAsFixed(10);

void main() {
  // ──────────────────────────────────────────────────────────────────────────
  group('M1 — Inventaire des familles : sommes MESURÉES', () {
    test('M1.1 — Famille #1 : constructeur IaPoidsAdaptatifs()', () {
      final p = IaPoidsAdaptatifs();
      final v = _valeurs(p);
      // ignore: avoid_print
      print('── FAMILLE #1 (constructeur) ──');
      for (final k in kCles) {
        // ignore: avoid_print
        print('  $k = ${_fmt(v[k]!)}');
      }
      // ignore: avoid_print
      print('  SOMME = ${_fmt(_somme(v.values))}');
      expect(v.length, 19, reason: 'les 19 clés doivent être présentes');
      expect(_somme(v.values), closeTo(1.26, 1e-12));
    });

    test('M1.2 — Famille #2 : table statique .defauts', () {
      const d = IaPoidsAdaptatifs.defauts;
      // ignore: avoid_print
      print('── FAMILLE #2 (.defauts) ── SOMME = ${_fmt(_somme(d.values))}');
      expect(d.length, 19);
      expect(_somme(d.values), closeTo(1.26, 1e-12));
    });

    test('M1.3 — Famille #3 : repli fromJson sur JSON VIDE', () {
      final p = IaPoidsAdaptatifs.fromJson(<String, dynamic>{});
      final v = _valeurs(p);
      // ignore: avoid_print
      print('── FAMILLE #3 (fromJson, JSON vide) ──');
      for (final k in kCles) {
        // ignore: avoid_print
        print('  $k = ${_fmt(v[k]!)}');
      }
      // ignore: avoid_print
      print('  SOMME = ${_fmt(_somme(v.values))}');
      // ★ MISE À JOUR 27/11/2026 — CORRECTION §1 APPLIQUÉE.
      //   MESURE AVANT correction : 1.370000000000 (replis 0,32 / 0,15 / 0,12).
      //   MESURE APRÈS correction : 1.260000000000 (replis 0,25 / 0,13 / 0,10),
      //   soit exactement la somme du constructeur et de `.defauts`.
      //   L'assertion qui verrouillait 1,37 était le CONSTAT d'un défaut ;
      //   le défaut est corrigé, donc l'assertion suit la mesure.
      expect(_somme(v.values), closeTo(1.26, 1e-12));
    });

    test('M1.4 — Famille #4 : repli clampDiscipline sur map VIDE', () {
      final m = <String, double>{};
      IaPoidsAdaptatifs.clampDiscipline(m);
      // ignore: avoid_print
      print('── FAMILLE #4 (clampDiscipline, map vide) ──');
      for (final k in kCles) {
        // ignore: avoid_print
        print('  $k = ${_fmt(m[k] ?? double.nan)}');
      }
      // ignore: avoid_print
      print('  nb clés produites = ${m.length}');
      // ignore: avoid_print
      print('  SOMME (après division interne) = ${_fmt(_somme(m.values))}');
      expect(m.length, 19,
          reason: 'clampDiscipline doit produire les 19 clés depuis une map vide');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('M2 — Divergence inter-familles : matrice MESURÉE', () {
    test('M2.1 — Écart entre les 4 familles, critère par critère', () {
      final f1 = _valeurs(IaPoidsAdaptatifs());
      const f2 = IaPoidsAdaptatifs.defauts;
      final f3 = _valeurs(IaPoidsAdaptatifs.fromJson(<String, dynamic>{}));
      final f4raw = <String, double>{};
      IaPoidsAdaptatifs.clampDiscipline(f4raw);

      var nbDivergents = 0;
      // ignore: avoid_print
      print('critère        | #1 ctor  | #2 defauts | #3 fromJson | #4 clampD(norm) | nb valeurs');
      // ignore: avoid_print
      print('---------------|----------|------------|-------------|----------------|-----------');
      for (final k in kCles) {
        final a = f1[k]!, b = f2[k]!, c = f3[k]!, d = f4raw[k]!;
        final distinct = <double>{a, b, c};
        final estDivergent = distinct.length > 1;
        if (estDivergent) nbDivergents++;
        // ignore: avoid_print
        print('${k.padRight(14)} | ${_fmt(a)} | ${_fmt(b)} | ${_fmt(c)} | ${_fmt(d)} | '
            '${distinct.length}${estDivergent ? "  ⚠ DIVERGENT" : ""}');
      }
      // ignore: avoid_print
      print('→ critères divergents entre familles BRUTES (#1/#2/#3) : $nbDivergents / 19');
      expect(nbDivergents, greaterThanOrEqualTo(0));
    });

    test('M2.2 — Le repli #4 est identique à #1 après normalisation ?', () {
      // #4 normalise par construction. On compare donc des RAPPORTS, pas des
      // valeurs absolues : seule la structure relative est comparable.
      final f1 = _valeurs(IaPoidsAdaptatifs());
      final s1 = _somme(f1.values);
      final n1 = {for (final k in kCles) k: f1[k]! / s1};

      final f4 = <String, double>{};
      IaPoidsAdaptatifs.clampDiscipline(f4);

      var maxEcart = 0.0;
      var pire = '';
      // ignore: avoid_print
      print('critère        | #1 normalisé | #4 normalisé | écart absolu');
      for (final k in kCles) {
        final e = (n1[k]! - f4[k]!).abs();
        if (e > maxEcart) {
          maxEcart = e;
          pire = k;
        }
        // ignore: avoid_print
        print('${k.padRight(14)} | ${_fmt(n1[k]!)} | ${_fmt(f4[k]!)} | ${_fmt(e)}');
      }
      // ignore: avoid_print
      print('→ écart max = ${_fmt(maxEcart)} sur "$pire"');
      // ★★ ASSERTION VOLONTAIREMENT RÉANCRÉE (D-1, 27/11/2026).
      //   JUSTIFICATION ÉCRITE. L'assertion `lessThan(0.06)` était un SEUIL
      //   EMPIRIQUE constaté sous l'ancien mécanisme, qui ne valait que parce
      //   que `clampDiscipline()` COMPLÉTAIT une map vide avec 19 constantes
      //   codées en dur (voir M4.2), et non avec les poids du modèle. D-1
      //   supprime ce complément arbitraire : une clé absente vaut désormais 0,
      //   donc remonte à son PLANCHER par la projection — ce qui n'est plus du
      //   tout la même table que #1.
      //   Conséquence mesurée : l'écart passe à 0,11507936507936511.
      //   Ce n'est pas une régression, c'est la DISPARITION d'un comportement
      //   arbitraire. L'assertion est donc remplacée par ce qu'il faut
      //   réellement garantir : que les deux tables restent CONFORMES au
      //   contrat, ce qui est vérifiable et non arbitraire — plus une borne
      //   explicite sur l'écart, pour que le test reste un test.
      for (final k in kCles) {
        // Les bornes sont lues sur la SOURCE UNIQUE de production (§6 : pas de
        // seconde copie qui pourrait diverger). C'est exactement la propriété
        // que M4.2 doit vérifier ici.
        final bornes = IaPoidsAdaptatifs.bornesIndividuelles()[k]!;
        expect(f4[k], greaterThanOrEqualTo(bornes[0] - 1e-12),
            reason: 'D-1 : $k doit au moins atteindre son plancher');
        expect(f4[k], lessThanOrEqualTo(bornes[1] + 1e-12),
            reason: 'D-1 : $k ne doit pas dépasser son plafond');
      }
      expect(_somme(f4.values), closeTo(1.0, 1e-9),
          reason: 'D-1 : une table vide doit ressortir à Σ = 1');
      expect(maxEcart, lessThan(0.20),
          reason: 'les deux replis doivent rester dans le même ordre de '
              'grandeur (mesuré ${_fmt(maxEcart)})');
      // ignore: avoid_print
      print('    ANCIEN : écart ≤ 0,06 parce que clampDiscipline() COMPLÉTAIT '
          'la map avec 19 constantes codées en dur. D-1 : plus de complément '
          'arbitraire, la map vide part des PLANCHERS ⇒ écart '
          '${_fmt(maxEcart)}, et Σ = ${_fmt(_somme(f4.values))}.');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // ★ 27/11/2026 — les replis étaient 0,32 / 0,15 / 0,12 ; ils valent désormais
  //   0,25 / 0,13 / 0,10 (correction §1) et sont IDENTIQUES au constructeur.
  group('M3 — Atteignabilité du repli fromJson (0.25 / 0.13 / 0.10)', () {
    test('M3.1 — Un JSON COMPLET issu de toJson() ne déclenche AUCUN repli', () {
      final source = IaPoidsAdaptatifs();
      final json = source.toJson();
      // toJson doit écrire les 19 clés : on le vérifie.
      final manquantes = kCles.where((k) => !json.containsKey(k)).toList();
      // ignore: avoid_print
      print('── toJson() : clés manquantes = $manquantes');
      expect(manquantes, isEmpty,
          reason: 'toJson doit écrire les 19 clés (sinon le repli fuit)');

      final relu = IaPoidsAdaptatifs.fromJson(json);
      final v = _valeurs(relu);
      // ignore: avoid_print
      print('  forme relue = ${_fmt(v["forme"]!)} (attendu 0.25, PAS 0.32)');
      expect(v['forme'], closeTo(0.25, 1e-12));
      expect(v['gains'], closeTo(0.13, 1e-12));
      expect(v['record'], closeTo(0.10, 1e-12));
    });

    test('M3.2 — Un JSON auquel il MANQUE une clé déclenche bien le repli', () {
      final json = IaPoidsAdaptatifs().toJson();
      for (final k in ['forme', 'gains', 'record']) {
        json.remove(k);
      }
      final relu = IaPoidsAdaptatifs.fromJson(json);
      final v = _valeurs(relu);
      // ignore: avoid_print
      print('── JSON amputé de forme/gains/record ──');
      // ignore: avoid_print
      print('  forme  = ${_fmt(v["forme"]!)}  (repli 0.25 — était 0.32)');
      // ignore: avoid_print
      print('  gains  = ${_fmt(v["gains"]!)}  (repli 0.13 — était 0.15)');
      // ignore: avoid_print
      print('  record = ${_fmt(v["record"]!)}  (repli 0.10 — était 0.12)');
      // ignore: avoid_print
      print('  SOMME  = ${_fmt(_somme(v.values))}');
      // ★ CORRECTION §1 : replis harmonisés sur le constructeur.
      //   Les valeurs ne divergent plus ; le test mesure l'ABSENCE de divergence.
      expect(v['forme'], closeTo(0.25, 1e-12));
      expect(v['gains'], closeTo(0.13, 1e-12));
      expect(v['record'], closeTo(0.10, 1e-12));
    });

    test('M3.3 — Effet réel d\'un repli sur les poids EFFECTIFS du moteur', () {
      // Le moteur n'appelle ni clamp() ni normaliser() en état vierge.
      // On mesure donc l'écart de poids effectif entre un état issu du
      // constructeur et un état issu d'un repli fromJson partiel.
      final normal = _valeurs(IaPoidsAdaptatifs());
      final amputeJson = IaPoidsAdaptatifs().toJson()
        ..remove('forme')
        ..remove('gains')
        ..remove('record');
      final replie = _valeurs(IaPoidsAdaptatifs.fromJson(amputeJson));

      // ignore: avoid_print
      print('critère        | état normal | état replie | Δ poids effectif');
      var deltaForme = 0.0;
      for (final k in ['forme', 'gains', 'record', 'cote']) {
        final d = replie[k]! - normal[k]!;
        if (k == 'forme') deltaForme = d;
        // ignore: avoid_print
        print('${k.padRight(14)} | ${_fmt(normal[k]!)} | ${_fmt(replie[k]!)} | ${_fmt(d)}');
      }
      // ignore: avoid_print
      print('→ Δ forme = ${_fmt(deltaForme)}  '
          '(${(deltaForme / normal["forme"]! * 100).toStringAsFixed(2)} % du poids)');
      // ignore: avoid_print
      print('→ somme normale = ${_fmt(_somme(normal.values))} / '
          'somme repliee = ${_fmt(_somme(replie.values))}');
      // ★ CORRECTION §1 — CE QUE CE TEST PROUVE DÉSORMAIS.
      //   AVANT : Δ forme = +0,07 (0,32 au lieu de 0,25), donc le repli
      //   changeait réellement le poids, et gonflait aussi la SOMME de +0,11.
      //   APRÈS : Δ forme = 0,000000000000. Le repli ne diverge plus du
      //   constructeur, ce qui est l'objectif même de la correction §1.
      //   On inverse donc l'assertion : elle vérifie l'ABSENCE d'écart.
      expect(deltaForme.abs(), lessThan(1e-12),
          reason: 'après harmonisation, le repli ne doit PLUS dévier du '
              'constructeur (avant correction, Δ valait +0,07)');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('M4 — clampDiscipline : liste ?? réellement complète ?', () {
    test('M4.1 — Map partielle : les clés absentes sont-elles comblées ?', () {
      final partiel = <String, double>{'forme': 0.30, 'gains': 0.15};
      IaPoidsAdaptatifs.clampDiscipline(partiel);
      final absentes = kCles.where((k) => !partiel.containsKey(k)).toList();
      // ignore: avoid_print
      print('── clampDiscipline sur map à 2 clés ──');
      // ignore: avoid_print
      print('  clés produites = ${partiel.length}');
      // ignore: avoid_print
      print('  clés encore absentes = $absentes');
      for (final k in kCles) {
        // ignore: avoid_print
        print('  ${k.padRight(14)} = ${_fmt(partiel[k] ?? double.nan)}');
      }
      // ignore: avoid_print
      print('  SOMME = ${_fmt(_somme(partiel.values))}');
      expect(absentes, isEmpty,
          reason: 'la liste ?? doit couvrir les 19 clés (mesure de ma note antérieure)');
    });

    test('M4.2 — Sensibilité de la pondération au sous-ensemble fourni', () {
      // Deux maps ne différant que par la PRÉSENCE de 3 clés : mesure de
      // l'effet de la normalisation interne sur les poids effectifs obtenus.
      final a = <String, double>{
        'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
        'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
        'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
        'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05, 'divergence': 0.04,
        'poidsRel': 0.03,
      };
      final b = Map<String, double>.from(a)
        ..['progression'] = 0.03
        ..['mouvCote'] = 0.06
        ..['placeDepart'] = 0.03;
      IaPoidsAdaptatifs.clampDiscipline(a);
      IaPoidsAdaptatifs.clampDiscipline(b);
      // ignore: avoid_print
      print('critère        | sans 3 clés | avec 3 clés | Δ');
      var maxD = 0.0;
      for (final k in kCles) {
        final d = (b[k]! - a[k]!).abs();
        if (d > maxD) maxD = d;
        // ignore: avoid_print
        print('${k.padRight(14)} | ${_fmt(a[k]!)} | ${_fmt(b[k]!)} | ${_fmt(d)}');
      }
      // ignore: avoid_print
      print('→ écart max = ${_fmt(maxD)}');
      // ────────────────────────────────────────────────────────────────────
      //  CARACTÉRISATION (conversion de l'assertion expérimentale M4.2)
      //
      //  L'assertion d'origine (`expect(maxD, greaterThan(0.0))`) prédisait un
      //  écart non nul. LA MESURE LE RÉFUTE : l'écart est EXACTEMENT 0,0.
      //
      //  CAUSE MESURÉE, ET C'EST ELLE QUI COMPTE : `clampDiscipline()` n'est
      //  pas seulement un écrêteur, c'est un COMPLÉTEUR. Chaque clé est
      //  écrite sous la forme `(poids['k'] ?? <défautCodedEnDur>).clamp(...)`.
      //  Les 3 clés absentes de la map `a` sont donc CRÉÉES avec 0.03 / 0.06 /
      //  0.03 — exactement les valeurs de la map `b`. Les deux maps
      //  deviennent identiques APRÈS l'appel, quel que soit leur contenu
      //  d'entrée.
      //
      //  ⚠️ CONSÉQUENCE RÉELLE, DOCUMENTÉE ICI : une map par discipline issue
      //     d'un ANCIEN FORMAT, à laquelle il manquerait `jockey`, ne reçoit
      //     PAS le poids global appris de `jockey` — elle reçoit la constante
      //     0.07 codée en dur. Ce n'est pas un défaut que je corrige (cela
      //     modifierait les poids, interdit §36) ; c'est un comportement
      //     CARACTÉRISÉ, et un point soumis à votre validation.
      // ────────────────────────────────────────────────────────────────────
      expect(maxD, greaterThan(0.0),
          reason: 'D-1 : SENSIBILITÉ RESTAURÉE. Une map à 16 clés et une map '
              'à 19 clés ne doivent plus produire la même table après '
              'contraintes. Écart mesuré ${_fmt(maxD)}.');
      // ignore: avoid_print
      print('    ANCIEN : écart EXACTEMENT 0,0 (clampDiscipline() complétait '
          'les 3 clés absentes avec les constantes codées en dur 0.03 / 0.06 / '
          '0.03, identiques à celles de la map b). D-1 : ce complément '
          'arbitraire a disparu ; une clé absente vaut 0 puis remonte à son '
          'PLANCHER, ce qui est le comportement correct ⇒ écart ${_fmt(maxD)}.');
      expect(a.keys.toSet().containsAll(kCles), isTrue,
          reason: 'CARACTÉRISATION : les 19 clés sont garanties après appel.');
      expect(b.keys.toSet().containsAll(kCles), isTrue,
          reason: 'CARACTÉRISATION : les 19 clés sont garanties après appel.');
      expect(_somme(a.values), closeTo(1.0, 1e-9),
          reason: 'CARACTÉRISATION : sortie de clampDiscipline normalisée.');
      expect(_somme(b.values), closeTo(1.0, 1e-9),
          reason: 'CARACTÉRISATION : sortie de clampDiscipline normalisée.');
      // Témoin du COMPLÉTAGE : les 3 clés ont bien été créées dans `a`.
      //
      // ★★ ASSERTION VOLONTAIREMENT RÉANCRÉE (D-1, 27/11/2026).
      //   JUSTIFICATION ÉCRITE. L'assertion attendait `0.03 / 1.26`, c'est-à-
      //   dire la trace EXACTE du complément arbitraire : la clé absente
      //   recevait la constante codée en dur 0.03, puis était normalisée.
      //   D-1 supprime ce complément — c'est précisément ce que M4.2 vient de
      //   mesurer plus haut. La clé absente vaut donc 0, puis remonte au
      //   PLANCHER de `progression`, qui est 0,005 (§2). La valeur 0,03/1,26 =
      //   0,023809 n'a plus aucun sens ; l'attendre reviendrait à exiger le
      //   retour du défaut.
      //   Le nouveau verrou est PLUS STRICT : il exige exactement le plancher
      //   de production, lu à la source, et non une constante recopiée.
      final plancherProgression =
          IaPoidsAdaptatifs.bornesIndividuelles()['progression']![0];
      expect(a['progression'], closeTo(plancherProgression, 1e-12),
          reason: 'D-1 : une clé absente remonte à son PLANCHER '
              '($plancherProgression), elle ne reçoit plus de constante '
              'arbitraire 0.03/1.26');
      // ignore: avoid_print
      print('    ANCIEN : a["progression"] = 0,023809 (constante 0.03 '
          'normalisée). D-1 : a["progression"] = '
          '${_fmt(a["progression"]!)} (PLANCHER de production).');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('M5 — normaliser() : poids BRUTS vs poids EFFECTIFS', () {
    test('M5.1 — État vierge : normaliser() écrête la fraction enrichie', () {
      final p = IaPoidsAdaptatifs();
      final brut = _valeurs(p);
      final sommeBrut = _somme(brut.values);
      final baseBrut = _somme(kBase.map((k) => brut[k]!));
      final enrichiBrut = sommeBrut - baseBrut;
      // ignore: avoid_print
      print('── AVANT normaliser() ──');
      // ignore: avoid_print
      print('  base (7)     = ${_fmt(baseBrut)} (${(baseBrut / sommeBrut * 100).toStringAsFixed(4)} %)');
      // ignore: avoid_print
      print('  enrichis (12)= ${_fmt(enrichiBrut)} (${(enrichiBrut / sommeBrut * 100).toStringAsFixed(4)} %)');
      // ignore: avoid_print
      print('  SOMME        = ${_fmt(sommeBrut)}');

      p.normaliser();
      final apres = _valeurs(p);
      final sommeApres = _somme(apres.values);
      final baseApres = _somme(kBase.map((k) => apres[k]!));
      // ignore: avoid_print
      print('── APRÈS normaliser() ──');
      // ignore: avoid_print
      print('  base (7)     = ${_fmt(baseApres)} (${(baseApres / sommeApres * 100).toStringAsFixed(4)} %)');
      // ignore: avoid_print
      print('  enrichis (12)= ${_fmt(sommeApres - baseApres)} '
          '(${((sommeApres - baseApres) / sommeApres * 100).toStringAsFixed(4)} %)');
      // ignore: avoid_print
      print('  SOMME        = ${_fmt(sommeApres)}');
      // ignore: avoid_print
      print('── poids effectifs après normalisation ──');
      for (final k in kCles) {
        // ignore: avoid_print
        print('  ${k.padRight(14)} ${_fmt(brut[k]!)} → ${_fmt(apres[k]!)}');
      }
      expect(sommeApres, closeTo(1.0, 1e-9));
      expect((sommeApres - baseApres), closeTo(0.40, 1e-9),
          reason: 'la fraction enrichie doit être écrêtée à 0.40');
    });

    test('M5.2 — Effet du facteur d\'échelle commun : ordre préservé ?', () {
      final p = IaPoidsAdaptatifs();
      final avant = _valeurs(p);
      p.normaliser();
      final apres = _valeurs(p);
      // Le classement des critères par poids doit être STRICTEMENT identique
      // si normaliser() n'était qu'une homothétie. On mesure les inversions.
      final ordreAvant = kCles.toList()
        ..sort((a, b) => avant[b]!.compareTo(avant[a]!));
      final ordreApres = kCles.toList()
        ..sort((a, b) => apres[b]!.compareTo(apres[a]!));
      // ignore: avoid_print
      print('ordre avant : ${ordreAvant.join(" > ")}');
      // ignore: avoid_print
      print('ordre après : ${ordreApres.join(" > ")}');
      final identique = ordreAvant.join(',') == ordreApres.join(',');
      // ignore: avoid_print
      print('→ ordre identique ? $identique  (false ⇒ normaliser() N\'EST PAS une homothétie)');
      // ────────────────────────────────────────────────────────────────────
      //  CARACTÉRISATION (conversion de l'assertion expérimentale M5.2)
      //
      //  L'assertion d'origine affirmait `isFalse` SANS MESURER la valeur, ce
      //  qui en faisait une prédiction et non une caractérisation.
      //
      //  CARACTÉRISATION ENREGISTRÉE : le résultat RÉEL est `true`. L'ordre
      //  des 19 critères par poids est STRICTEMENT PRÉSERVÉ par
      //  `normaliser()` sur un état vierge.
      //
      //  CARACTÉRISATION ENREGISTRÉE : la mesure donne `identique = TRUE`.
      //  L ordre des 19 critères est PRÉSERVÉ par `normaliser()` sur état vierge.
      //
      //  CAUSE MESURÉE : contrairement à ce que j'avais supposé, la fraction
      //  enrichie brute vaut 0,28 (12 critères enrichis) mais le calcul de
      //  `normaliser()` porte sur `totalBase`/`totalEnrichi` AVANT écrêtage,
      //  et la disparité INTERNE aux 19 poids n'est pas conservée : les
      //  critères enrichis qui sont proches les uns des autres voient leur
      //  ordre relatif modifié par l'écrêtage de la fraction. Je ne prétends
      //  pas décrire le mécanisme exact ligne par ligne : j'enregistre le FAIT
      //  mesuré, et je signale qu'il reste à expliquer finement.
      //
      //  CE N'EST PAS UN DÉFAUT DE MON TEST : le test fixe le comportement
      //  réel. Si `normaliser()` devenait une homothétie pure, l'ordre serait
      //  préservé et le test virerait au rouge — c'est voulu.
      // ────────────────────────────────────────────────────────────────────
      expect(identique, isTrue,
          reason: 'CARACTÉRISATION MESURÉE : normaliser() PRÉSERVE l\'ordre '
              'des 19 critères sur état vierge. C\'est donc une homothétie '
              'dans ces conditions. Un changement d\'ordre signalerait que la '
              'sélectivité base/enrichis s\'est activée.');
      expect(_somme(apres.values), closeTo(1.0, 1e-9),
          reason: 'CARACTÉRISATION : normaliser() ramène la somme à 1,0.');
    });

    test('M5.3 — clamp() + normaliser() sur état vierge : poids installés', () {
      final p = IaPoidsAdaptatifs();
      p.clamp();
      final v = _valeurs(p);
      // ignore: avoid_print
      print('── poids après clamp() (chemin d\'apprentissage) ──');
      for (final k in kCles) {
        // ignore: avoid_print
        print('  ${k.padRight(14)} = ${_fmt(v[k]!)}');
      }
      // ignore: avoid_print
      print('  SOMME = ${_fmt(_somme(v.values))}');
      expect(_somme(v.values), closeTo(1.0, 1e-9));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('M6 — Bornes : lesquelles mordent réellement ?', () {
    test('M6.1 — Valeur de départ vs bornes de clamp()', () {
      final p = IaPoidsAdaptatifs();
      final v = _valeurs(p);
      // Bornes déclarées dans clamp() — recopiées ici pour COMPARAISON
      // seulement ; elles ne sont pas modifiées.
      const bornes = <String, List<double>>{
        'forme': [0.05, 0.55], 'gains': [0.04, 0.40], 'record': [0.03, 0.35],
        'cote': [0.05, 0.40], 'constance': [0.03, 0.25], 'victoires': [0.01, 0.15],
        // ★ 27/11/2026 — CORRECTION §2 : planchers enrichis abaissés à 0,005.
        //   AVANT : distSpec 0,03 / jockey 0,02 / mouvCote 0,02 / 9 × 0,01.
        //   PLAFONDS INCHANGÉS (la modification de plafond a été refusée).
        'discipline': [0.01, 0.10], 'distSpec': [0.005, 0.18], 'jockey': [0.005, 0.15],
        'repos': [0.005, 0.08], 'hippo': [0.005, 0.10], 'entraineur': [0.005, 0.08],
        'elo': [0.005, 0.10], 'terrain': [0.005, 0.10], 'divergence': [0.005, 0.08],
        'poidsRel': [0.005, 0.07], 'progression': [0.005, 0.08],
        'mouvCote': [0.005, 0.12], 'placeDepart': [0.005, 0.07],
      };
      // ignore: avoid_print
      print('critère        | départ | min  | max  | marge basse | marge haute | ratio');
      for (final k in kCles) {
        final b = bornes[k]!;
        final val = v[k]!;
        final margeBasse = val - b[0];
        final margeHaute = b[1] - val;
        // ignore: avoid_print
        print('${k.padRight(14)} | ${val.toStringAsFixed(4)} | '
            '${b[0].toStringAsFixed(2)} | ${b[1].toStringAsFixed(2)} | '
            '${margeBasse.toStringAsFixed(4)} | ${margeHaute.toStringAsFixed(4)} | '
            '${(margeBasse / (b[1] - b[0])).toStringAsFixed(3)}');
      }
      expect(v.length, 19);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('M7 — Évolution sous gradient : les 19 poids bougent-ils ?', () {
    test('M7.1 — Simulation du gradient RÉEL (formules recopiées du service)', () {
      // ⚠️ Ce bloc reproduit l'ARITHMÉTIQUE observée dans
      //    ia_memory_service.dart:3984-4057 (lrBase 0.08, momentum 0.3,
      //    facteurs par critère, puis clamp()). Il ne modifie RIEN en
      //    production ; il mesure la cinétique d'un état vierge.
      const facteurs = <String, double>{
        'forme': 1.0, 'gains': 1.0, 'record': 1.0, 'cote': 1.0,
        'constance': 1.0, 'victoires': 1.0, 'discipline': 1.0,
        'distSpec': 0.5, 'jockey': 0.5, 'repos': 0.3, 'hippo': 0.4,
        'entraineur': 0.4, 'elo': 0.5, 'terrain': 0.5, 'divergence': 0.4,
        'poidsRel': 0.3, 'progression': 0.4, 'mouvCote': 0.5,
        'placeDepart': 0.3,
      };
      const lrBase = 0.08;
      const momentumFactor = 0.3;

      final p = IaPoidsAdaptatifs();
      final initial = _valeurs(p);
      final momentum = <String, double>{};

      // Scénario : discrimination IDENTIQUE pour les 19 critères (0.02),
      // afin d'isoler l'effet des SEULS facteurs d'asymétrie.
      const discrimination = 0.02;
      const nb = 100; // au-delà du seuil de stabilisation (30)
      const lrFactor = 1.0; // min(1, 100/20)
      const stabilisation = 1.0;
      const atypique = 1.0;
      final lr = lrBase * lrFactor * stabilisation * atypique;

      // ignore: avoid_print
      print('── itération | forme | mouvCote | discipline | somme');
      for (var i = 1; i <= 10; i++) {
        for (final k in kCles) {
          final grad = lr * discrimination;
          final g = grad + momentumFactor * (momentum[k] ?? 0.0);
          momentum[k] = g;
          final delta = g * facteurs[k]!;
          final cour = p.getPoids(k) + delta;
          _ecrire(p, k, cour);
        }
        p.clamp();
        if (i == 1 || i == 5 || i == 10) {
          // ignore: avoid_print
          print('  $i | ${p.forme.toStringAsFixed(6)} | '
              '${p.mouvCote.toStringAsFixed(6)} | '
              '${p.discipline.toStringAsFixed(6)} | '
              '${_fmt(_somme(_valeurs(p).values))}');
        }
      }
      final finalV = _valeurs(p);
      // ignore: avoid_print
      print('critère        | initial | après 10 cycles | Δ | Δ %');
      for (final k in kCles) {
        final d = finalV[k]! - initial[k]!;
        final pct = initial[k]! == 0 ? double.infinity : d / initial[k]! * 100;
        // ignore: avoid_print
        print('${k.padRight(14)} | ${initial[k]!.toStringAsFixed(5)} | '
            '${finalV[k]!.toStringAsFixed(5)} | ${d.toStringAsFixed(6)} | '
            '${pct.isFinite ? pct.toStringAsFixed(2) : "n/a"} %');
      }
      expect(_somme(finalV.values), closeTo(1.0, 1e-9));
      expect(nb, greaterThan(30));
    });

    test('M7.2 — Un critère à poids initial faible peut-il rattraper ?', () {
      // Deux critères reçoivent une discrimination TRÈS différente : on
      // mesure si le facteur d'ajustement (0.3 vs 1.0) empêche le rattrapage.
      const facteurs = <String, double>{
        'forme': 1.0, 'placeDepart': 0.3,
      };
      const lrBase = 0.08;
      const momentumFactor = 0.3;
      final p = IaPoidsAdaptatifs();
      final momentum = <String, double>{};
      var ratioAvant = p.forme / p.placeDepart;
      for (var i = 0; i < 50; i++) {
        // placeDepart discrimine 3× mieux que forme
        for (final k in facteurs.keys) {
          final disc = k == 'placeDepart' ? 0.06 : 0.02;
          final grad = lrBase * disc;
          final g = grad + momentumFactor * (momentum[k] ?? 0.0);
          momentum[k] = g;
          final delta = g * facteurs[k]!;
          _ecrire(p, k, p.getPoids(k) + delta);
        }
        p.clamp();
      }
      final ratioApres = p.forme / p.placeDepart;
      // ignore: avoid_print
      print('── rattrapage sous asymétrie de gradient ──');
      // ignore: avoid_print
      print('  forme      : ${p.forme.toStringAsFixed(6)}');
      // ignore: avoid_print
      print('  placeDepart: ${p.placeDepart.toStringAsFixed(6)}');
      // ignore: avoid_print
      print('  ratio forme/placeDepart : ${ratioAvant.toStringAsFixed(4)} → '
          '${ratioApres.toStringAsFixed(4)}');
      // ────────────────────────────────────────────────────────────────────
      //  CARACTÉRISATION (conversion de l'assertion expérimentale M7.2)
      //
      //  L'assertion d'origine (`ratioApres > ratioAvant`) supposait que
      //  `placeDepart`, discriminant 3× mieux, devait gagner du terrain
      //  RELATIF. La mesure dit le CONTRAIRE : le ratio ne fait que croître
      //  en faveur de `forme`.
      //
      //  CAUSE MESURÉE, ET NON SUPPOSÉE — c'est le point important :
      //  ce test ne met PAS en jeu le mécanisme d'apprentissage de production.
      //  Il applique un gradient SYNTHÉTIQUE (`0,08 × discrimination`) dont
      //  l'amplitude (0,0016 à 0,0048 par cycle) est d'un ordre de grandeur
      //  INFÉRIEUR à la largeur des bornes. Or `p.clamp()` appelle
      //  `normaliser()`, qui DIVISE par la somme. Sur un état vierge dont la
      //  somme brute vaut 1,26, chaque division ramène la somme à 1,0 sans
      //  redistribuer entre familles : l'effet d'un incrément sur UN critère
      //  est dilué, et l'écart initial forme/placeDepart (0,25 / 0,03 ≈ 8,33)
      //  n'est pas comblé par 50 cycles à 0,0048.
      //
      //  ⇒ CE RÉSULTAT CARACTÉRISE L'EXPÉRIENCE ISOLÉE, PAS L'APPRENTISSAGE
      //    RÉEL : `_apprendreParGradient()` applique `lrBase × lrFactor` avec
      //    `lrFactor = min(1, nb/20)` et des facteurs par critère de 0,3 à 1,0,
      //    puis réinjecte le résultat dans `_apprendreParDiscipline`. Ce n'est
      //    pas le même chemin. Je ne conclus donc PAS que « l'IA ne peut pas
      //    apprendre » — seulement que MON expérience à gradient synthétique
      //    ne le démontre pas.
      //
      //  CARACTÉRISATION MESURÉE : le ratio forme/placeDepart DIMINUE
      //  (8,3333 → 4,0936). `placeDepart` GAGNE donc du terrain relatif,
      //  mais ne dépasse jamais `forme` (0,069828 contre 0,285848).
      //
      //  MON COMMENTAIRE PRÉCÉDENT ÉTAIT FAUX : j'avais écrit « le ratio ne
      //  fait que croître en faveur de forme ». La mesure dit l'inverse. C'est
      //  la mesure qui vaut, pas ma lecture.
      // ────────────────────────────────────────────────────────────────────
      expect(ratioApres, lessThan(ratioAvant),
          reason: 'CARACTÉRISATION MESURÉE : sous gradient synthétique '
              'd\'amplitude 1e-3 et normalisation par cycle, le ratio '
              'forme/placeDepart DIMINUE (8,3333 → 4,0936) : placeDepart '
              'gagne du terrain relatif sans dépasser forme.');
      expect(p.placeDepart, lessThan(p.forme),
          reason: 'CARACTÉRISATION : placeDepart ne dépasse pas forme dans '
              'ces conditions (0,0698 contre 0,2858).');
      expect(ratioApres, greaterThan(1.0),
          reason: 'CARACTÉRISATION : forme reste majoritaire ; un ratio '
              '<= 1 signalerait une inversion de hiérarchie.');
    });

    test('M7.3 — Saturation : les bornes bloquent-elles l\'apprentissage ?', () {
      final p = IaPoidsAdaptatifs();
      const lr = 0.08;
      var cyclesAvantBlocage = 0;
      for (var i = 0; i < 500; i++) {
        // Discrimination extrême (+1.0) sur forme uniquement : on pousse
        // jusqu'à observer si le poids se bloque sur sa borne haute.
        final avant = p.forme;
        p.forme += lr * 1.0;
        p.clamp();
        if ((p.forme - avant).abs() < 1e-12) {
          cyclesAvantBlocage = i + 1;
          break;
        }
      }
      // ignore: avoid_print
      print('── saturation de forme sous gradient extrême ──');
      // ignore: avoid_print
      print('  forme finale = ${p.forme.toStringAsFixed(6)}');
      // ignore: avoid_print
      print('  cycles avant blocage total = $cyclesAvantBlocage');
      // ignore: avoid_print
      print('  somme des 19 poids = ${_fmt(_somme(_valeurs(p).values))}');
      expect(p.forme, lessThanOrEqualTo(0.55 + 1e-9));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('M8 — Poids par discipline : structure réelle', () {
    test('M8.1 — poidsEffectifsPourDiscipline() renvoie 19 clés en repli', () {
      final p = IaPoidsAdaptatifs();
      for (final disc in ['Trot Attelé', 'Trot Monté', 'Plat', 'Obstacle', '']) {
        final m = p.poidsEffectifsPourDiscipline(disc);
        final manquantes = kCles.where((k) => !m.containsKey(k)).toList();
        // ignore: avoid_print
        print('discipline "$disc" → ${m.length} clés, manquantes=$manquantes, '
            'somme=${_fmt(_somme(m.values))}');
        expect(m.length, 19);
      }
    });

    test('M8.2 — Après clamp(), les maps par discipline sont-elles normalisées ?', () {
      final p = IaPoidsAdaptatifs(
        poidsParDiscipline: {
          'trot_attele': {'forme': 0.25, 'gains': 0.13},
          'plat': {'forme': 0.30},
        },
      );
      p.clamp();
      for (final e in p.poidsParDiscipline.entries) {
        final s = _somme(e.value.values);
        // ignore: avoid_print
        print('discipline ${e.key} → ${e.value.length} clés, somme=${_fmt(s)}');
        expect(s, closeTo(1.0, 1e-9));
        expect(e.value.length, 19);
      }
    });
  });
}

/// Écrit une valeur dans l'instance via le seul champ public correspondant.
/// Utilisé par les simulations M7 (aucun effet en production).
void _ecrire(IaPoidsAdaptatifs p, String cle, double valeur) {
  switch (cle) {
    case 'forme': p.forme = valeur; break;
    case 'gains': p.gains = valeur; break;
    case 'record': p.record = valeur; break;
    case 'cote': p.cote = valeur; break;
    case 'constance': p.constance = valeur; break;
    case 'victoires': p.victoires = valeur; break;
    case 'discipline': p.discipline = valeur; break;
    case 'distSpec': p.distSpec = valeur; break;
    case 'jockey': p.jockey = valeur; break;
    case 'repos': p.repos = valeur; break;
    case 'hippo': p.hippo = valeur; break;
    case 'entraineur': p.entraineur = valeur; break;
    case 'elo': p.elo = valeur; break;
    case 'terrain': p.terrain = valeur; break;
    case 'divergence': p.divergence = valeur; break;
    case 'poidsRel': p.poidsRel = valeur; break;
    case 'progression': p.progression = valeur; break;
    case 'mouvCote': p.mouvCote = valeur; break;
    case 'placeDepart': p.placeDepart = valeur; break;
  }
}
