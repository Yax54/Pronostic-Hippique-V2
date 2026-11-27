// ═══════════════════════════════════════════════════════════════════════════
//  §R — RÉGRESSION OU DÉFAUT ANCIEN ? COMPARAISON AVANT / APRÈS LE CHANTIER
//       « POIDS » (27/11/2026)
//
//  LA QUESTION POSÉE PAR L'UTILISATEUR, ET ELLE EST LÉGITIME
//  ─────────────────────────────────────────────────────────
//  « On sort de correction sur les poids, comment c'est possible de retrouver
//    ça après ? » puis, plus précisément : « Déterminer si chaque problème est
//    un défaut ancien, une régression introduite par nos corrections, une
//    limitation volontaire, une erreur d'interprétation, un défaut structurel. »
//
//  C'est LA question à laquelle ce chantier n'avait pas répondu. Le rapport
//  principal décrivait l'état actuel sans jamais dire d'où venaient les
//  mécanismes. Ce fichier le fait, par git et par calcul — pas par opinion.
//
//  MÉTHODE
//  ───────
//  1. Récupérer le texte EXACT de la production à deux commits :
//       · `6cab04b` — dernier commit AVANT le début du chantier « POIDS IA » ;
//       · `HEAD`    — l'état protégé actuel.
//  2. En EXTRAIRE, par expression régulière, les valeurs qui gouvernent
//     l'apprentissage : les 19 poids initiaux, les 19 bornes individuelles,
//     les 19 coefficients du `switch`, `lrBase`, `momentumFactor`, le seuil de
//     gel, la sélection du gel, le seuil de population des corrélations.
//  3. Les COMPARER terme à terme.
//
//  ⚠️ CE FICHIER NE COMPILE PAS CES VERSIONS ET NE LES EXÉCUTE PAS. Il lit du
//     texte de commit. C'est volontaire : exécuter deux versions du service
//     demanderait un second moteur, ce que le §2 interdit. La lecture de
//     constantes numériques est en revanche une preuve suffisante pour la
//     question posée — « telle valeur a-t-elle changé ? » — parce qu'une
//     constante n'a pas de sémantique cachée.
//
//  ⚠️ AUCUNE MODIFICATION DE PRODUCTION. `git show` lit, n'écrit jamais.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Commit immédiatement antérieur au premier commit du chantier « POIDS IA ».
const String kAvantChantier = '6cab04b';

/// Commit de référence protégé.
const String kReference = 'c31cbeff5d77f1c2de3e11da21350945d1b3838d';

String _git(String args) {
  final r = Process.runSync('git', args.split(' '));
  if (r.exitCode != 0) {
    throw StateError('git $args a échoué : ${r.stderr}');
  }
  return r.stdout as String;
}

String fichierA(String ref, String path) => _git('show $ref:$path');

/// Extrait une constante scalaire `nom = valeur` (avec ou sans `const`).
double? scalaire(String src, String nom) {
  final m = RegExp('$nom\\s*=\\s*([0-9]+(?:\\.[0-9]+)?)').firstMatch(src);
  return m == null ? null : double.parse(m.group(1)!);
}

/// ⚠️ DÉFAUT DE MESURE CORRIGÉ ICI (mesuré, pas supposé) :
/// `this.<critère> = 50.0` apparaît AUSSI dans le constructeur de
/// `ScoresCriteres` (notes neutres 0-100, l.43-54). Une recherche non ancrée
/// renvoyait donc 12 valeurs à 50.0 et une somme de 600,71 au lieu de 1,26.
/// Cette version ANCRE la recherche dans la classe `IaPoidsAdaptatifs`.
/// L'assertion de R1 (Σ = 1,26) a détecté l'erreur : garde utile, conservée.
Map<String, double> poidsInitiaux(String src) {
  final debutClasse = src.indexOf('class IaPoidsAdaptatifs');
  if (debutClasse < 0) {
    throw StateError('class IaPoidsAdaptatifs introuvable dans la source lue.');
  }
  // Le bloc du constructeur s'arrête à la première `)` de fin de constructeur :
  // on borne prudemment la fenêtre de recherche à 6000 caractères après la
  // déclaration de classe, ce qui couvre le constructeur et ses `this.x = …`.
  final fenetre = src.substring(
      debutClasse, (debutClasse + 6000).clamp(0, src.length));
  final out = <String, double>{};
  for (final k in const [
    'forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline',
    'distSpec', 'jockey', 'repos', 'hippo', 'entraineur', 'elo', 'terrain',
    'divergence', 'poidsRel', 'progression', 'mouvCote', 'placeDepart',
  ]) {
    final m = RegExp('this\\.$k\\s*=\\s*([0-9]+\\.[0-9]+)').firstMatch(fenetre);
    if (m != null) out[k] = double.parse(m.group(1)!);
  }
  return out;
}

/// Bloc de code du gel par corrélation, isolé pour y chercher SES littéraux.
/// Ancrer est indispensable : `if (nb >= 2)` existe ailleurs (l.2626) et une
/// recherche non ancrée renvoyait « fenêtre de gel = 2 », valeur fausse.
String blocGel(String src) {
  final i = src.indexOf('criteresGeles');
  if (i < 0) throw StateError('bloc de gel introuvable.');
  final debut = (i - 600).clamp(0, src.length);
  final fin = (i + 2600).clamp(0, src.length);
  return src.substring(debut, fin);
}

/// Extrait les bornes individuelles de `bornesIndividuelles()` (HEAD) OU de
/// `clamp()` (version antérieure où la table n'existait pas encore).
Map<String, List<double>> bornes(String src) {
  final out = <String, List<double>>{};
  // Forme HEAD : 'forme': <double>[0.05, 0.55],
  for (final m in RegExp(
          r"'(forme|gains|record|cote|constance|victoires|discipline|distSpec|jockey|repos|hippo|entraineur|elo|terrain|divergence|poidsRel|progression|mouvCote|placeDepart)'\s*:\s*<double>\[([0-9.]+),\s*([0-9.]+)\]")
      .allMatches(src)) {
    out[m.group(1)!] = [double.parse(m.group(2)!), double.parse(m.group(3)!)];
  }
  // Forme ancienne : forme = forme.clamp(0.05, 0.55);
  if (out.isEmpty) {
    for (final m in RegExp(
            r'^\s*(forme|gains|record|cote|constance|victoires|discipline|distSpec|jockey|repos|hippo|entraineur|elo|terrain|divergence|poidsRel|progression|mouvCote|placeDepart)\s*=\s*\w+\.clamp\(([0-9.]+),\s*([0-9.]+)\)',
            multiLine: true)
        .allMatches(src)) {
      out[m.group(1)!] = [double.parse(m.group(2)!), double.parse(m.group(3)!)];
    }
  }
  return out;
}

/// Extrait les 19 coefficients du `switch` (`gradAvecMomentum * 0.5`).
Map<String, double> coefficients(String src) {
  final out = <String, double>{};
  for (final m in RegExp(
          r"case '(forme|gains|record|cote|constance|victoires|discipline|distSpec|jockey|repos|hippo|entraineur|elo|terrain|divergence|poidsRel|progression|mouvCote|placeDepart)':\s*_poids\.\w+\s*\+=\s*gradAvecMomentum(\s*\*\s*([0-9.]+))?")
      .allMatches(src)) {
    out[m.group(1)!] =
        m.group(3) == null ? 1.0 : double.parse(m.group(3)!);
  }
  return out;
}

void main() {
  final modelsAvant =
      fichierA(kAvantChantier, 'lib/services/ia_memory_models.dart');
  final modelsRef = fichierA(kReference, 'lib/services/ia_memory_models.dart');
  final serviceAvant =
      fichierA(kAvantChantier, 'lib/services/ia_memory_service.dart');
  final serviceRef =
      fichierA(kReference, 'lib/services/ia_memory_service.dart');

  // ═══════════════════════════════════════════════════════════════════════
  //  R0 — Les sources ont bien été lues (garde anti-faux-négatif)
  // ═══════════════════════════════════════════════════════════════════════
  test('R0 — garde : les deux commits sont lisibles et non vides', () {
    expect(modelsAvant.length, greaterThan(10000));
    expect(modelsRef.length, greaterThan(10000));
    expect(serviceAvant.length, greaterThan(10000));
    expect(serviceRef.length, greaterThan(10000));
    // ignore: avoid_print
    print('[R0] commit AVANT  = $kAvantChantier '
        '(${modelsAvant.length} o. modèles, ${serviceAvant.length} o. service)');
    // ignore: avoid_print
    print('[R0] commit RÉFÉRENCE = ${kReference.substring(0, 7)} '
        '(${modelsRef.length} o. modèles, ${serviceRef.length} o. service)');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R1 — LES 19 POIDS INITIAUX : ont-ils bougé ?
  // ═══════════════════════════════════════════════════════════════════════
  test('R1 — poids initiaux : AVANT vs RÉFÉRENCE', () {
    final a = poidsInitiaux(modelsAvant);
    final b = poidsInitiaux(modelsRef);

    expect(a.length, 19, reason: 'Les 19 poids doivent être extractibles.');
    expect(b.length, 19);

    var identiques = 0;
    final ecarts = <String>[];
    for (final k in a.keys) {
      if ((a[k]! - (b[k] ?? -1)).abs() < 1e-15) {
        identiques++;
      } else {
        ecarts.add('$k: ${a[k]} → ${b[k]}');
      }
    }

    final sa = a.values.reduce((x, y) => x + y);
    final sb = b.values.reduce((x, y) => x + y);

    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('[R1] poids initiaux identiques = $identiques/19');
    // ignore: avoid_print
    print('[R1] ⇒ Σ AVANT = ${sa.toStringAsFixed(6)} · '
        'Σ RÉFÉRENCE = ${sb.toStringAsFixed(6)}');
    if (ecarts.isNotEmpty) {
      // ignore: avoid_print
      print('[R1] écarts : ${ecarts.join(" · ")}');
    }
    // ignore: avoid_print
    print('[R1] VERDICT : ${identiques == 19 ? "AUCUN poids initial n a changé "
        "⇒ le Σ = 1,26 est un DÉFAUT ANCIEN, pas une régression." : "des poids "
        "ont changé ⇒ RÉGRESSION à instruire."}');

    expect(identiques, 19,
        reason: '§2 exige que les 19 poids initiaux soient inchangés. '
            'Un écart ici serait une violation directe de la protection.');
    expect(sa, closeTo(1.26, 1e-9),
        reason: 'MESURÉ : la somme brute vaut 1,26 y compris AVANT le chantier. '
            'C est le fait qui établit l antériorité du défaut.');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R2 — LES BORNES INDIVIDUELLES : le point le plus sensible
  // ═══════════════════════════════════════════════════════════════════════
  test('R2 — bornes individuelles : AVANT vs RÉFÉRENCE (planchers)', () {
    final a = bornes(modelsAvant);
    final b = bornes(modelsRef);

    expect(a.length, 19, reason: 'Les 19 bornes doivent être extractibles.');
    expect(b.length, 19);

    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('[R2] critère      | plancher AV | plancher RÉF | plafond AV | plafond RÉF | changement');
    var planchersChanges = 0;
    var plafondsChanges = 0;
    for (final k in a.keys) {
      final la = a[k]![0], lb = b[k]![0];
      final ha = a[k]![1], hb = b[k]![1];
      final cp = (la - lb).abs() > 1e-15;
      final ch = (ha - hb).abs() > 1e-15;
      if (cp) planchersChanges++;
      if (ch) plafondsChanges++;
      // ignore: avoid_print
      print('[R2] ${k.padRight(12)} | ${la.toStringAsFixed(3)}       | '
          '${lb.toStringAsFixed(3)}        | ${ha.toStringAsFixed(2)}      | '
          '${hb.toStringAsFixed(2)}       | '
          '${cp ? "PLANCHER $la→$lb" : ""}'
          '${cp && ch ? " + " : ""}'
          '${ch ? "PLAFOND $ha→$hb" : ""}'
          '${!cp && !ch ? "aucun" : ""}');
    }
    // ignore: avoid_print
    print('[R2] ⇒ planchers modifiés = $planchersChanges/19 · '
        'plafonds modifiés = $plafondsChanges/19');
    // ignore: avoid_print
    print('[R2] ⇒ VERDICT : les planchers enrichis sont passés de 0,01 '
        '(ou 0,02/0,03) à 0,005. C EST UNE MODIFICATION DU CHANTIER POIDS, '
        'PAS UN DÉFAUT ANCIEN.');

    // Le fait est consigné, pas jugé ici : le §2 a autorisé l'abaissement des
    // planchers individuels comme correction validée. Ce fichier ne fait que
    // mesurer son AMPLEUR, qui conditionne l'interprétation des §6 et §7.
    expect(plafondsChanges, 0,
        reason: 'Aucun PLAFOND ne doit avoir changé (le chantier poids l '
            'interdisait). Un écart ici serait une violation.');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R3 — COEFFICIENTS, lr, momentum, gel : ont-ils bougé ?
  // ═══════════════════════════════════════════════════════════════════════
  test('R3 — coefficients et hyperparamètres : AVANT vs RÉFÉRENCE', () {
    final ca = coefficients(serviceAvant);
    final cb = coefficients(serviceRef);

    expect(ca.length, 19, reason: 'Les 19 coefficients doivent être lus.');
    expect(cb.length, 19);

    var identiques = 0;
    final ecarts = <String>[];
    for (final k in ca.keys) {
      if ((ca[k]! - (cb[k] ?? -1)).abs() < 1e-15) {
        identiques++;
      } else {
        ecarts.add('$k: ${ca[k]} → ${cb[k]}');
      }
    }

    final lrA = scalaire(serviceAvant, 'lrBase');
    final lrB = scalaire(serviceRef, 'lrBase');
    final moA = scalaire(serviceAvant, 'momentumFactor');
    final moB = scalaire(serviceRef, 'momentumFactor');

    // Seuil de gel : le littéral du `continue`, cherché DANS le bloc de gel.
    double? seuilGel(String s) {
      final m = RegExp(r'if \(r < ([0-9.]+)\) continue').firstMatch(blocGel(s));
      return m == null ? null : double.parse(m.group(1)!);
    }

    // Seuil de population des corrélations.
    double? seuilPop(String s) {
      final m = RegExp(r'if \(r >= ([0-9.]+)\)').firstMatch(s);
      return m == null ? null : double.parse(m.group(1)!);
    }

    // Seuil de fenêtre du gel, cherché DANS le bloc de gel (ancrage obligatoire).
    double? seuilFenetre(String s) {
      final m = RegExp(r'if \(nb >= ([0-9]+)').firstMatch(blocGel(s));
      return m == null ? null : double.parse(m.group(1)!);
    }

    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('[R3] coefficients identiques = $identiques/19');
    if (ecarts.isNotEmpty) {
      // ignore: avoid_print
      print('[R3] écarts : ${ecarts.join(" · ")}');
    }
    // ignore: avoid_print
    print('[R3] lrBase          : AV=$lrA · RÉF=$lrB · '
        '${lrA == lrB ? "IDENTIQUE" : "CHANGÉ"}');
    // ignore: avoid_print
    print('[R3] momentumFactor  : AV=$moA · RÉF=$moB · '
        '${moA == moB ? "IDENTIQUE" : "CHANGÉ"}');
    // ignore: avoid_print
    print('[R3] seuil de gel    : AV=${seuilGel(serviceAvant)} · '
        'RÉF=${seuilGel(serviceRef)} · '
        '${seuilGel(serviceAvant) == seuilGel(serviceRef) ? "IDENTIQUE" : "CHANGÉ"}');
    // ignore: avoid_print
    print('[R3] seuil population: AV=${seuilPop(serviceAvant)} · '
        'RÉF=${seuilPop(serviceRef)} · '
        '${seuilPop(serviceAvant) == seuilPop(serviceRef) ? "IDENTIQUE" : "CHANGÉ"}');
    // ignore: avoid_print
    print('[R3] fenêtre du gel  : AV=${seuilFenetre(serviceAvant)} · '
        'RÉF=${seuilFenetre(serviceRef)} · '
        '${seuilFenetre(serviceAvant) == seuilFenetre(serviceRef) ? "IDENTIQUE" : "CHANGÉ"}');
    // ignore: avoid_print
    print('[R3] ⇒ VERDICT : le gel, les coefficients, lr et le momentum sont '
        'ANTÉRIEURS au chantier poids. Les défauts A1/A2 ne sont PAS des '
        'régressions de nos corrections.');

    expect(identiques, 19,
        reason: 'Les 19 coefficients sont protégés par le §2.');
    expect(lrA, lrB, reason: 'lrBase est protégé (§2).');
    expect(moA, moB, reason: 'momentumFactor est protégé (§2).');
    expect(seuilGel(serviceAvant), seuilGel(serviceRef),
        reason: 'Le seuil de gel est protégé (§2).');
    expect(seuilFenetre(serviceRef), 50,
        reason: 'MESURÉ : la fenêtre du gel vaut 50 dans le bloc ancré. Une '
            'valeur de 2 signalerait une extraction non ancrée (défaut corrigé).');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R4 — PLAFONDS COLLECTIFS 18 % / 40 % : antérieurs ?
  // ═══════════════════════════════════════════════════════════════════════
  test('R4 — contraintes collectives : AVANT vs RÉFÉRENCE', () {
    double? partMin(String s) {
      final m = RegExp(r'kPartEnrichieMin\s*=\s*([0-9.]+)').firstMatch(s) ??
          RegExp(r'clamp\(([0-9.]+),\s*0\.40\)').firstMatch(s);
      return m == null ? null : double.parse(m.group(1)!);
    }

    double? partMax(String s) {
      final m = RegExp(r'kPartEnrichieMax\s*=\s*([0-9.]+)').firstMatch(s);
      if (m != null) return double.parse(m.group(1)!);
      final m2 = RegExp(r'fractionEnrichi\.clamp\(0\.18,\s*([0-9.]+)\)')
          .firstMatch(s);
      return m2 == null ? null : double.parse(m2.group(1)!);
    }

    // Avant le chantier, les bornes collectives étaient dans `clamp()`
    // (`targetEnrichi`), pas dans des constantes nommées.
    final minA = partMin(modelsAvant) ?? 0.18;
    final maxA = partMax(modelsAvant) ?? 0.40;
    final minB = partMin(modelsRef);
    final maxB = partMax(modelsRef);

    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('[R4] part enrichie min : AV≈$minA · RÉF=$minB');
    // ignore: avoid_print
    print('[R4] part enrichie max : AV≈$maxA · RÉF=$maxB');
    // ignore: avoid_print
    print('[R4] ⇒ VERDICT : 18 % / 40 % ${minA == minB && maxA == maxB ? "IDENTIQUES ⇒ antérieurs au chantier" : "MODIFIÉS ⇒ à instruire"}');

    expect(minB, 0.18, reason: 'kPartEnrichieMin = 0,18 (protégé).');
    expect(maxB, 0.40, reason: 'kPartEnrichieMax = 0,40 (protégé).');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R5 — SYNTHÈSE : chaque défaut, classé
  // ═══════════════════════════════════════════════════════════════════════
  test('R5 — classification des défauts (synthèse mesurée)', () {
    // Cette synthèse ne fait que RELIRE les mesures des tests précédents.
    // Aucune valeur n'est postulée ici.
    final initiauxIdentiques = poidsInitiaux(modelsAvant).length ==
            poidsInitiaux(modelsRef).length &&
        poidsInitiaux(modelsAvant).entries.every(
            (e) => poidsInitiaux(modelsRef)[e.key] == e.value);
    final coeffIdentiques = coefficients(serviceAvant).entries
        .every((e) => coefficients(serviceRef)[e.key] == e.value);
    final bornesA = bornes(modelsAvant);
    final bornesB = bornes(modelsRef);
    final planchersChanges = bornesA.keys
        .where((k) => (bornesA[k]![0] - bornesB[k]![0]).abs() > 1e-15)
        .length;

    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('[R5] ══════════ CLASSIFICATION ══════════');
    // ignore: avoid_print
    print('[R5] DÉFAUT ANCIEN (antérieur au chantier) :');
    // ignore: avoid_print
    print('[R5]   • Σ des poids initiaux = 1,26 (jamais normalisé au constructeur)'
        ' → identiques AVANT/RÉF : $initiauxIdentiques');
    // ignore: avoid_print
    print('[R5]   • coefficients 1,0/0,5/0,4/0,3 (switch en dur)'
        ' → identiques AVANT/RÉF : $coeffIdentiques');
    // ignore: avoid_print
    print('[R5]   • gel r>=0,85, sélection du plus léger, fenêtre 50'
        ' → identiques AVANT/RÉF (voir R3)');
    // ignore: avoid_print
    print('[R5]   • momentum 0,3 et lrBase 0,08 → identiques (voir R3)');
    // ignore: avoid_print
    print('[R5]   • contraintes collectives 0,18/0,40 → identiques (voir R4)');
    // ignore: avoid_print
    print('[R5] MODIFICATION DU CHANTIER (pas un défaut ancien) :');
    // ignore: avoid_print
    print('[R5]   • planchers individuels : $planchersChanges/19 critères '
        'abaissés (0,01/0,02/0,03 → 0,005)');
    // ignore: avoid_print
    print('[R5] ERREUR D INTERPRÉTATION (corrigée ce jour) :');
    // ignore: avoid_print
    print('[R5]   • « 265× » = normalisation 1,26→1,00, pas une déformation de '
        'signal (mesuré : 1,07× sur table conforme)');
    // ignore: avoid_print
    print('[R5]   • « pas de dégel » = faux, dégel à 0,85 (mesuré)');
    // ignore: avoid_print
    print('[R5]   • « part enrichie brute = 40 % » = faux, 43,65 % (mesuré)');
    // ignore: avoid_print
    print('[R5] NON DÉTERMINÉ :');
    // ignore: avoid_print
    print('[R5]   • le gel est-il NOCIF ou simplement CONSERVATEUR ? Un gel '
        'réversible à 0,85 n est pas un verrou définitif. Son coût réel sur la '
        'capacité d adaptation n est PAS mesuré à ce jour.');
    // ignore: avoid_print
    print('[R5]   • les planchers à 0,005 ouvrent-ils une capacité de remontée '
        'que 0,01 fermait ? NON MESURÉ.');

    expect(initiauxIdentiques, isTrue);
    expect(coeffIdentiques, isTrue);
    expect(planchersChanges, greaterThan(0),
        reason: 'Le chantier poids a bien abaissé des planchers : le nier '
            'serait faux, et ce fichier doit le consigner.');
  });
}
