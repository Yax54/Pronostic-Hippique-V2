// ═══════════════════════════════════════════════════════════════════════════
//  LOT B1 — MODÈLE : REPRÉSENTATION DES DEUX COMPOSANTES GAGNANT + PLACÉ
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT — AUCUNE MODIFICATION DE lib/ AU-DELÀ DE B1.
//
//  ── RÈGLE MÉTIER VÉRIFIÉE ICI ─────────────────────────────────────────────
//  La mise saisie s'applique SÉPARÉMENT à chaque composante :
//      10 € saisis = 10 € Gagnant + 10 € Placé = 20 € engagés.
//  `miseTotaleEngagee` ne divise jamais, ne fusionne jamais, et ne calcule
//  JAMAIS une mise totale à partir d'une seule composante.
//
//  ── CE QUE CE FICHIER PROUVE ──────────────────────────────────────────────
//   1. sérialisation / désérialisation des 4 nouveaux champs ;
//   2. compatibilité ascendante : un JSON d'avant B1 reste lisible ;
//   3. la règle des trois cas de `miseTotaleEngagee` ;
//   4. NON-RÉGRESSION du calcul historique (`gainNet`, `retourTotal`).
//
//  ── CE QU'IL NE PROUVE PAS, ET NE DOIT PAS PROUVER ────────────────────────
//  B1 est une évolution de MODÈLE. Le Gagnant + Placé reste FINANCIÈREMENT
//  FAUX après B1 : `gainNet` d'un G+P gagnant vaut toujours 170,00 € au lieu
//  de 202,00 €, parce que la composante Placé n'entre pas encore dans le
//  calcul. C'est l'objet de B4. B1-T12 fige ce comportement pour qu'on ne
//  puisse pas le « corriger » par inadvertance, et pour qu'il échoue
//  bruyamment le jour de B4.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/models/pmu_models.dart';

// ─────────────────────────── Constantes du scénario ────────────────────────

/// Mise SAISIE. Elle s'applique à CHAQUE composante, jamais une demi-fois.
const double kMiseSaisie = 10.0;

/// Cotes de référence : celles des tests A-0, donc comparables.
const double kCoteGagnant = 18.00;
const double kCotePlace = 4.20;

/// Retour réel d'un G+P gagnant : 10×18,00 + 10×4,20 = 180 + 42 = 222 €.
/// Gain net réel : 222 − 20 = 202 €.  (Attendu en B4 — PAS encore en B1.)
const double kRetourReelGP = 222.0;
const double kGainNetReelGP = 202.0;

// ─────────────────────────── Fixtures ──────────────────────────────────────

/// Pari SIMPLE : aucune composante renseignée. C'est la forme d'avant B1.
Map<String, dynamic> _jsonSimple() => <String, dynamic>{
      'id': 'simple_1',
      'dateStr': '20/11/2026',
      'numReunion': 1,
      'numCourse': 10,
      'nomCourse': 'PRIX B1',
      'hippodrome': 'VINCENNES',
      'numeroCheval': 7,
      'nomCheval': 'CHEVAL_7',
      'cote': kCoteGagnant,
      'typePari': 'Simple Gagnant',
      'createdAt': '2026-11-20T14:30:00.000',
      'isCorrect': null,
      'scoreIA': 70.0,
      'montantMise': 20.0,
      'gainRealise': null,
      'numerosJoues': <int>[7],
      'dividendePmuReel': null,
      'combinaisonPmu': null,
    };

/// Pari G+P entièrement renseigné, tel que B2 devra le produire.
UserPrediction _gpComplet({
  double? miseGagnant = kMiseSaisie,
  double? misePlace = kMiseSaisie,
  double montantMise = kMiseSaisie,
}) =>
    UserPrediction(
      id: 'gp_1',
      dateStr: '20/11/2026',
      numReunion: 1,
      numCourse: 10,
      nomCourse: 'PRIX B1',
      hippodrome: 'VINCENNES',
      numeroCheval: 7,
      nomCheval: 'CHEVAL_7',
      cote: kCoteGagnant,
      typePari: 'Gagnant+Placé',
      createdAt: DateTime(2026, 11, 20, 14, 30),
      scoreIA: 70.0,
      montantMise: montantMise,
      numerosJoues: const <int>[7],
      miseGagnant: miseGagnant,
      misePlace: misePlace,
      coteGagnant: kCoteGagnant,
      cotePlace: kCotePlace,
    );

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  //  B1-T1 — ALLER-RETOUR COMPLET
  // ═══════════════════════════════════════════════════════════════════════
  test('B1-T1 — toJson puis fromJson conserve les 4 composantes à l\'identique',
      () {
    final UserPrediction src = _gpComplet();
    final UserPrediction relu = UserPrediction.fromJson(src.toJson());

    // ignore: avoid_print
    print('─── MESURE B1-T1 ────────────────────────────────────────────');
    // ignore: avoid_print
    print('  miseGagnant=${relu.miseGagnant} misePlace=${relu.misePlace}');
    // ignore: avoid_print
    print('  coteGagnant=${relu.coteGagnant} cotePlace=${relu.cotePlace}');
    // ignore: avoid_print
    print('  miseTotaleEngagee=${relu.miseTotaleEngagee}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    expect(relu.miseGagnant, kMiseSaisie);
    expect(relu.misePlace, kMiseSaisie);
    expect(relu.coteGagnant, kCoteGagnant);
    expect(relu.cotePlace, kCotePlace);
    // `montantMise` conserve son sens : ce n'est PAS la mise totale.
    expect(relu.montantMise, kMiseSaisie,
        reason: 'B1 : montantMise garde sa signification historique');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B1-T2 — les 4 clés sont réellement ÉCRITES (et valent null pour un simple)
  // ═══════════════════════════════════════════════════════════════════════
  test('B1-T2 — toJson écrit les 4 clés ; null pour un pari simple', () {
    final Map<String, dynamic> gp = _gpComplet().toJson();
    for (final String k in <String>[
      'miseGagnant',
      'misePlace',
      'coteGagnant',
      'cotePlace',
    ]) {
      expect(gp.containsKey(k), isTrue,
          reason: 'B1 : la clé « $k » doit être sérialisée');
      expect(gp[k], isNotNull, reason: 'B1 : « $k » renseignée pour un G+P');
    }

    final Map<String, dynamic> simple =
        UserPrediction.fromJson(_jsonSimple()).toJson();
    for (final String k in <String>[
      'miseGagnant',
      'misePlace',
      'coteGagnant',
      'cotePlace',
    ]) {
      expect(simple.containsKey(k), isTrue,
          reason: 'B1 : la clé « $k » est écrite même à null');
      expect(simple[k], isNull,
          reason: 'B1 : un pari simple n\'a AUCUNE composante');
    }
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B1-T3 — un double? à null survit à l'aller-retour
  // ═══════════════════════════════════════════════════════════════════════
  test('B1-T3 — null traverse la sérialisation sans devenir 0,0', () {
    final UserPrediction p = UserPrediction.fromJson(_jsonSimple());
    final UserPrediction relu = UserPrediction.fromJson(p.toJson());
    expect(relu.miseGagnant, isNull);
    expect(relu.misePlace, isNull);
    expect(relu.coteGagnant, isNull);
    expect(relu.cotePlace, isNull,
        reason: 'B1 : null n\'est PAS confondu avec 0,0');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B1-T4 — COMPATIBILITÉ : JSON d'AVANT B1, sans aucune des 4 clés.
  //
  //  C'est le test central de la non-régression : `user_predictions_v2`
  //  contient aujourd'hui des JSON qui n'ont jamais connu ces clés.
  // ═══════════════════════════════════════════════════════════════════════
  test('B1-T4 — un JSON d\'avant B1 reste lisible, champs existants intacts',
      () {
    final Map<String, dynamic> avant = _jsonSimple();
    // Précondition : ce JSON ne contient AUCUNE des 4 nouvelles clés.
    expect(avant.containsKey('miseGagnant'), isFalse);
    expect(avant.containsKey('misePlace'), isFalse);
    expect(avant.containsKey('coteGagnant'), isFalse);
    expect(avant.containsKey('cotePlace'), isFalse);

    final UserPrediction p = UserPrediction.fromJson(avant);

    // ignore: avoid_print
    print('─── MESURE B1-T4 (compatibilité) ───────────────────────────');
    // ignore: avoid_print
    print('  montantMise=${p.montantMise} cote=${p.cote} '
        'typePari=${p.typePari} numerosJoues=${p.numerosJoues}');
    // ignore: avoid_print
    print('  miseTotaleEngagee=${p.miseTotaleEngagee} '
        '(doit retomber sur montantMise)');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    // Les champs historiques sont relus à l'identique.
    expect(p.id, 'simple_1');
    expect(p.numReunion, 1);
    expect(p.numCourse, 10);
    expect(p.numeroCheval, 7);
    expect(p.cote, kCoteGagnant);
    expect(p.typePari, 'Simple Gagnant');
    expect(p.montantMise, 20.0);
    expect(p.numerosJoues, equals(<int>[7]));
    expect(p.scoreIA, 70.0);

    // Les nouveaux champs valent null, sans exception.
    expect(p.miseGagnant, isNull);
    expect(p.misePlace, isNull);
    expect(p.coteGagnant, isNull);
    expect(p.cotePlace, isNull);

    // Comportement historique préservé : pas d'invention de donnée.
    expect(p.miseTotaleEngagee, 20.0,
        reason: 'B1 : sans composantes, on retombe sur montantMise');
    expect(p.misesGagnantPlaceIncompletes, isFalse);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B1-T5 — JSON PARTIEL : seules les mises, cotes absentes → état incomplet
  // ═══════════════════════════════════════════════════════════════════════
  test('B1-T5 — mises seules présentes : cotes null, aucune exception', () {
    final Map<String, dynamic> partiel = <String, dynamic>{
      ..._jsonSimple(),
      'typePari': 'Gagnant+Placé',
      'miseGagnant': 10.0,
      'misePlace': 10.0,
    };
    final UserPrediction p = UserPrediction.fromJson(partiel);
    expect(p.miseGagnant, 10.0);
    expect(p.misePlace, 10.0);
    expect(p.coteGagnant, isNull);
    expect(p.cotePlace, isNull,
        reason: 'B1 : une cote absente reste null, elle n\'est pas devinée');
    expect(p.miseTotaleEngagee, 20.0,
        reason: 'B1 : les deux MISES suffisent à la mise totale');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B1-T6 — TYPE INATTENDU : `as num?` est TOLÉRANT à l'absence, PAS au type.
  //
  //  ⚠️ Correction du plan initial : une chaîne "10" ne devient PAS null.
  //  Mesuré : `{'x':'10'}['x'] as num?` lève `_TypeError`.
  //  Clé absente  → null.  Clé présente de type String → exception.
  //  Ce test DOCUMENTE le comportement réel, il ne le loue pas.
  // ═══════════════════════════════════════════════════════════════════════
  test('B1-T6 — clé absente → null ; valeur String → _TypeError (comportement '
      'réel de `as num?`, identique aux 8 autres champs optionnels)', () {
    // (a) Clé ABSENTE : tolérée.
    final Map<String, dynamic> absent = <String, dynamic>{..._jsonSimple()};
    absent.remove('miseGagnant');
    expect(UserPrediction.fromJson(absent).miseGagnant, isNull,
        reason: 'B1 : clé absente → null');

    // (b) Clé PRÉSENTE mais String : lève, exactement comme `cote`, `scoreIA`…
    final Map<String, dynamic> chaine = <String, dynamic>{
      ..._jsonSimple(),
      'miseGagnant': '10',
    };
    expect(
      () => UserPrediction.fromJson(chaine),
      throwsA(isA<TypeError>()),
      reason: 'B1 : `as num?` ne convertit PAS une chaîne — il lève. '
          'Comportement identique à `cote`/`scoreIA`/`montantMise`.',
    );

    // ignore: avoid_print
    print('─── MESURE B1-T6 ────────────────────────────────────────────');
    // ignore: avoid_print
    print('  clé absente      → null (toléré)');
    // ignore: avoid_print
    print('  valeur String    → _TypeError (strict sur le type)');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B1-T7 — LA RÈGLE MÉTIER : 10 + 10 = 20
  // ═══════════════════════════════════════════════════════════════════════
  test('B1-T7 — miseTotaleEngagee = 10 + 10 = 20, jamais 10 ni 5', () {
    final UserPrediction p = _gpComplet();
    // ignore: avoid_print
    print('─── MESURE B1-T7 (règle métier) ────────────────────────────');
    // ignore: avoid_print
    print('  miseGagnant=10 misePlace=10 → miseTotaleEngagee='
        '${p.miseTotaleEngagee}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    expect(p.miseTotaleEngagee, 20.0,
        reason: 'B1 : 10 € saisis = 10 G + 10 P = 20 € engagés');
    expect(p.miseTotaleEngagee, isNot(kMiseSaisie),
        reason: 'B1 : la mise totale n\'est PAS la mise saisie');
    expect(p.miseTotaleEngagee, isNot(kMiseSaisie / 2),
        reason: 'B1 : aucune division par deux');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B1-T8 — un SIMPLE reste à sa mise simple
  // ═══════════════════════════════════════════════════════════════════════
  test('B1-T8 — un pari simple garde miseTotaleEngagee = montantMise', () {
    final UserPrediction p = UserPrediction.fromJson(_jsonSimple());
    expect(p.miseTotaleEngagee, 20.0,
        reason: 'B1 : comportement historique conservé');
    expect(p.misesGagnantPlaceIncompletes, isFalse);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B1-T9 — montantMise n'est PAS altéré par les composantes
  // ═══════════════════════════════════════════════════════════════════════
  test('B1-T9 — montantMise (10) reste distinct de miseTotaleEngagee (20)', () {
    final UserPrediction p = _gpComplet(montantMise: kMiseSaisie);
    expect(p.montantMise, 10.0,
        reason: 'B1 : montantMise conserve son sens');
    expect(p.miseTotaleEngagee, 20.0);
    expect(p.montantMise, isNot(p.miseTotaleEngagee),
        reason: 'B1 : les deux notions sont DISTINCTES, pas fusionnées');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B1-T10 — UNE SEULE mise présente → null, état incomplet signalé
  //
  //  Exigence explicite du mandat : ne pas calculer une fausse mise totale.
  // ═══════════════════════════════════════════════════════════════════════
  test('B1-T10 — une seule composante renseignée → miseTotaleEngagee null '
      '(état incomplet signalé, aucune mise inventée)', () {
    final UserPrediction gagnantSeul =
        _gpComplet(miseGagnant: 10.0, misePlace: null);
    final UserPrediction placeSeul =
        _gpComplet(miseGagnant: null, misePlace: 10.0);

    // ignore: avoid_print
    print('─── MESURE B1-T10 (état incomplet) ─────────────────────────');
    // ignore: avoid_print
    print('  miseGagnant=10, misePlace=null → miseTotaleEngagee='
        '${gagnantSeul.miseTotaleEngagee} '
        'incomplet=${gagnantSeul.misesGagnantPlaceIncompletes}');
    // ignore: avoid_print
    print('  miseGagnant=null, misePlace=10 → miseTotaleEngagee='
        '${placeSeul.miseTotaleEngagee} '
        'incomplet=${placeSeul.misesGagnantPlaceIncompletes}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    expect(gagnantSeul.miseTotaleEngagee, isNull,
        reason: 'B1 : une seule mise → AUCUNE mise totale calculée');
    expect(placeSeul.miseTotaleEngagee, isNull);
    expect(gagnantSeul.misesGagnantPlaceIncompletes, isTrue);
    expect(placeSeul.misesGagnantPlaceIncompletes, isTrue);

    // Et surtout : on ne retombe PAS sur montantMise (ce serait masquer
    // l'incohérence), et on n'invente pas la composante manquante.
    expect(gagnantSeul.miseTotaleEngagee, isNot(kMiseSaisie));
    expect(gagnantSeul.miseTotaleEngagee, isNot(kMiseSaisie * 2));
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B1-T11 — NON-RÉGRESSION du calcul historique (doit être identique avant
  //  et après B1 : B1 ne touche aucun calcul).
  // ═══════════════════════════════════════════════════════════════════════
  test('B1-T11 — gainNet et retourTotal d\'un Simple Gagnant sont INCHANGÉS',
      () {
    final UserPrediction simple = UserPrediction.fromJson(_jsonSimple())
      ..isCorrect = true;

    // ignore: avoid_print
    print('─── MESURE B1-T11 (non-régression calcul) ──────────────────');
    // ignore: avoid_print
    print('  Simple Gagnant : mise=20 cote=18 → gainNet=${simple.gainNet} '
        'retourTotal=${simple.retourTotal}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    expect(simple.gainNet, closeTo(340.0, 1e-9),
        reason: 'B1 : (18,00 × 20) − 20 = 340,00 € — inchangé');
    expect(simple.retourTotal, closeTo(360.0, 1e-9),
        reason: 'B1 : 18,00 × 20 = 360,00 € — inchangé');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B1-T12 — LE G+P RESTE FINANCIÈREMENT FAUX APRÈS B1.
  //
  //  ⚠️ CE TEST FIGE VOLONTAIREMENT UN COMPORTEMENT INCORRECT.
  //
  //  `gainNet` d'un G+P gagnant vaut 170,00 € alors que la règle métier
  //  impose 202,00 € (10×18,00 + 10×4,20 − 20). La composante Placé n'entre
  //  pas encore dans le calcul : c'est l'objet de B4.
  //
  //  Ce test est un TÉMOIN DE DETTE, pas une validation. Il existe pour :
  //    - interdire qu'on « corrige » gainNet par inadvertance pendant B2/B3 ;
  //    - échouer bruyamment le jour de B4, ce qui forcera à le remplacer
  //      par les valeurs réelles plutôt qu'à le supprimer en silence.
  //
  //  ATTENDU DE B4 : gainNet == 202,00 €  (ce test DOIT alors être réécrit).
  // ═══════════════════════════════════════════════════════════════════════
  test('B1-T12 — [DETTE B4] G+P : gainNet vaut encore 170,00 € au lieu de '
      '202,00 € — comportement TEMPORAIREMENT INCORRECT, figé volontairement',
      () {
    final UserPrediction gp = _gpComplet()..isCorrect = true;

    // ignore: avoid_print
    print('─── MESURE B1-T12 (DETTE B4) ───────────────────────────────');
    // ignore: avoid_print
    print('  G+P gagnant : montantMise=10 cote=18');
    // ignore: avoid_print
    print('  gainNet ACTUEL  = ${gp.gainNet}  (composante Placé IGNORÉE)');
    // ignore: avoid_print
    print('  gainNet ATTENDU = $kGainNetReelGP  (= 10×18 + 10×4,20 − 20)');
    // ignore: avoid_print
    print('  écart mesuré    = ${kGainNetReelGP - gp.gainNet} € '
        '(sous-évaluation de l\'utilisateur)');
    // ignore: avoid_print
    print('  miseTotaleEngagee = ${gp.miseTotaleEngagee} '
        '(B1 la connaît, le calcul ne l\'utilise pas encore)');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    // Ce qui est VRAI après B1 : la donnée est disponible…
    expect(gp.miseTotaleEngagee, 20.0);
    expect(gp.cotePlace, kCotePlace);
    // …mais le calcul ne s'en sert pas encore. Comportement figé.
    expect(gp.gainNet, closeTo(170.0, 1e-9),
        reason: 'DETTE B4 : (18,00 × 10) − 10 = 170,00 € — la composante '
            'Placé est ignorée. Doit devenir 202,00 € en B4.');
    expect(gp.gainNet, isNot(closeTo(kGainNetReelGP, 1e-9)),
        reason: 'DETTE B4 : le gain réel 202,00 € n\'est PAS encore produit');
    // Corollaire : le retour est lui aussi sous-évalué (180 au lieu de 222).
    expect(gp.retourTotal, closeTo(180.0, 1e-9),
        reason: 'DETTE B4 : 18,00 × 10 = 180,00 € au lieu de 222,00 €');
    expect(kRetourReelGP, isNot(closeTo(gp.retourTotal, 1e-9)));
  });
}
