// ═══════════════════════════════════════════════════════════════════════════
//  BLOC 1 — BL1-A02 / A03 / A08 / A14 / BL3-A26
//  COHÉRENCE RÉELLE ENTRE LES CONSOMMATEURS DE LA CASCADE UNIQUE
//
//  OBJET : « neuf appels au même service » ne démontre PAS que les neuf
//          consommateurs transmettent les mêmes informations. Ce fichier
//          exerce donc les VRAIES fonctions consommatrices accessibles, et
//          mesure que la décision est identique quand l'entrée est identique,
//          et qu'elle CHANGE quand les seuils appris changent.
//
//  Les points vérifiés, un par un (§2 de la consigne) :
//    T1 — même `ZtCourse` ⇒ même `typePari` par TOUS les consommateurs
//         accessibles sans BuildContext (`premium_utils`, et la cascade
//         directement).
//    T2 — SEUILS APPRIS RÉELLEMENT TRANSMIS : on MUTE `seuilTierce` du
//         singleton et l'on exige que la décision suive. Si les consommateurs
//         n'utilisaient que les valeurs PAR DÉFAUT, ce test échouerait.
//    T3 — COTE INCONNUE : aucune recommandation `Gagnant+Placé` automatique,
//         et `coteDisponible == false` propagé.
//    T4 — COTE CONNUE : `Gagnant+Placé` redevient atteignable — preuve que
//         T3 n'est pas obtenu en supprimant une branche.
//    T5 — ABSTENTION : scores insuffisants ⇒ `À surveiller`, 0 numéro.
//    T6 — PERSISTANCE DU TYPE : `regleNbNumerosPourTypePari` cohérent avec
//         `RecommandationPari.nbNumeros` pour les 8 types réels.
//    T7 — AUCUN NUMÉRO INVENTÉ : `typePariEtNumerosPourCourse` rend au plus
//         `nbNumeros` numéros, tous présents dans la course.
//
//  Aucune écriture d'apprentissage, aucune persistance, aucun reset :
//  `IaMemoryService._save()` n'est jamais atteint (seule la valeur EN MÉMOIRE
//  du seuil est ajustée, et le fichier de test est isolé).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart'
    show SeuilsConfianceAdaptatifs;
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/recommandation_pari_service.dart';
import 'package:pronostic_hippique/utils/premium_utils.dart';

// ─── Fabrique de course : aucun score n'est « inventé » au sens du mandat —
//     ce sont les ENTRÉES du test, pas des résultats d'apprentissage. Ce qui
//     est interdit, c'est de fabriquer une DONNÉE DE PRODUCTION (ancre, cote,
//     mouvement) pour faire passer une assertion. Ici les scores sont l'entrée
//     explicite du calcul, comme le ferait n'importe quel test unitaire.
ZtPartant _partant(String numero, double score, int rang, String cote) =>
    ZtPartant(
      numero: numero,
      nom: 'CHEVAL $numero',
      driver: 'D$numero',
      entraineur: 'E$numero',
      proprietaire: 'P$numero',
      gains: '10000',
      record: "1'15\"0",
      musique: '1a2a3a1a5a',
      cote: cote,
      ageSexe: 'H5',
      scoreIA: score,
      rang: rang,
    );

/// Course ORDINAIRE (ni Quinté, ni Quarté, ni classique sans multiple) : c'est
/// la section qui utilise les seuils ADAPTATIFS — la seule où l'on peut
/// démontrer que les seuils appris sont réellement transmis.
ZtCourse _courseOrdinaire({
  required List<double> scores,
  String cote = '12.0',
}) {
  final partants = <ZtPartant>[];
  for (int i = 0; i < scores.length; i++) {
    partants.add(_partant('${i + 1}', scores[i], i + 1, cote));
  }
  return ZtCourse(
    numCourse: 3,
    anchor: 'R2C3',
    nom: 'PRIX DE LA COHERENCE',
    heure: '15:15',
    distance: '2400m',
    prix: '30000',
    type: 'Plat',
    piste: 'bon',
    categorie: '',
    isQuinte: false,
    isQuarte: false,
    isClassiqueSansMultiple: false,
    pronosticZt: const <int>[],
    partants: partants,
    dateStr: '25112026',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─────────────────────────────────────────────────────────────────────────
  //  T1 — LE MÊME TYPE DE PARI POUR LA MÊME COURSE, PARTOUT
  // ─────────────────────────────────────────────────────────────────────────
  test('T1 — premium_utils et la cascade directe rendent la MÊME décision', () {
    // Course à fort score et cote longue : branche « Gagnant+Placé ».
    final course = _courseOrdinaire(scores: [88.0, 55.0, 50.0, 45.0], cote: '12.0');
    final seuils = IaMemoryService.instance.seuilsConfiance;

    final reco = cascadeRecommandation(
      course: course,
      seuils: seuils,
      scoreConf: 88.0,
      score2nd: 55.0,
      score3: 50.0,
      score4: 45.0,
      coteTop: 12.0,
    );
    final viaPremium = typePariEtNumerosPourCourse(course);

    // ignore: avoid_print
    print('─── MESURE T1 ──────────────────────────────────────────────');
    // ignore: avoid_print
    print('  cascadeRecommandation  → « ${reco.typePari} » (${reco.nbNumeros} numéros)');
    // ignore: avoid_print
    print('  premium_utils          → « ${viaPremium.tp} » (${viaPremium.nums.length} numéros)');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    expect(viaPremium.tp, reco.typePari,
        reason: 'Deux consommateurs, une seule décision : c\'est l\'objet de '
            'la source unique (BL1-A02/A08/A14/BL3-A26).');
    expect(viaPremium.nums, hasLength(reco.nbNumeros));
    // Les numéros rendus doivent exister dans la course.
    final numerosCourse = course.partants.map((p) => p.numero).toSet();
    for (final n in viaPremium.nums) {
      expect(numerosCourse, contains(n),
          reason: 'Aucun numéro ne doit être inventé (T7).');
    }
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  T2 — LES SEUILS APPRIS SONT RÉELLEMENT TRANSMIS (pas les défauts)
  // ─────────────────────────────────────────────────────────────────────────
  test('T2 — muter un seuil APPRIS change la décision du consommateur', () {
    // Score intermédiaire : sous le défaut Tiercé (35) il donne Tiercé ;
    // si le seuil appris monte à 55, la décision doit changer.
    final course = _courseOrdinaire(scores: [40.0, 30.0, 25.0, 20.0], cote: '30.0');
    final SeuilsConfianceAdaptatifs seuils =
        IaMemoryService.instance.getSeuilsAdaptatifs();

    final double seuilAvant = seuils.seuilTierce;
    final String decisionAvant = typePariEtNumerosPourCourse(course).tp;

    // MUTATION EN MÉMOIRE du seuil appris, par le MÉCANISME EXISTANT
    // (`ajusterSeuil`, clamp ±2,0 par appel — on l'appelle donc plusieurs fois).
    // Aucune formule n'est touchée : on se sert de l'API d'apprentissage telle
    // qu'elle existe. Aucune persistance n'est déclenchée.
    for (int i = 0; i < 10; i++) {
      seuils.ajusterSeuil('Tiercé', 2.0);
    }
    final double seuilApres = seuils.seuilTierce;
    final String decisionApres = typePariEtNumerosPourCourse(course).tp;

    // ignore: avoid_print
    print('─── MESURE T2 (seuils réellement transmis) ─────────────────');
    // ignore: avoid_print
    print('  seuilTierce avant = $seuilAvant  → décision = « $decisionAvant »');
    // ignore: avoid_print
    print('  seuilTierce après = $seuilApres  → décision = « $decisionApres »');
    // ignore: avoid_print
    print('  scoreConf de la course = 40.0');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    // TÉMOIN : la mutation a réellement eu lieu (bornes 25–55 de ajusterSeuil).
    expect(seuilApres, greaterThan(seuilAvant),
        reason: 'TÉMOIN : ajusterSeuil doit avoir monté le seuil.');
    expect(seuilAvant, 35.0, reason: 'Défaut mesuré du seuil Tiercé.');
    expect(seuilApres, 55.0, reason: 'Borne haute mesurée de ajusterSeuil.');

    // PREUVE : le consommateur SUIT le seuil appris.
    expect(decisionAvant, 'Tiercé',
        reason: 'Avec seuilTierce = 35 et scoreConf = 40, la cascade ordinaire '
            'doit atteindre la branche Tiercé.');
    expect(decisionApres, isNot('Tiercé'),
        reason: 'Avec seuilTierce = 55 et scoreConf = 40, la branche Tiercé '
            'doit être FERMÉE. Si le consommateur utilisait les valeurs PAR '
            'DÉFAUT au lieu des seuils appris, la décision resterait '
            '« Tiercé » et ce test échouerait — c\'est exactement ce que '
            'démontre BL1-A08.');
    expect(decisionApres, 'À surveiller',
        reason: 'Score 40 sous TOUS les autres seuils ⇒ abstention.');

    // Remise en état : on restaure la valeur d'origine par le même mécanisme,
    // pour ne pas laisser d'état modifié derrière ce test.
    for (int i = 0; i < 10; i++) {
      seuils.ajusterSeuil('Tiercé', -2.0);
    }
    expect(seuils.seuilTierce, seuilAvant,
        reason: 'Le test doit rendre l\'état qu\'il a trouvé.');
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  T3 — COTE INCONNUE : PAS DE « GAGNANT+PLACÉ » AUTOMATIQUE
  // ─────────────────────────────────────────────────────────────────────────
  test('T3 — cote absente : jamais « Gagnant+Placé », coteDisponible = false', () {
    // `cote: ''` ⇒ `coteDecimale` renvoie 99.0 (`zt_models.dart:331`), valeur
    // réelle du producteur quand PMU n'expose pas de rapport. Ce n'est donc pas
    // une valeur de test arbitraire : c'est CE QUE LA PRODUCTION PRODUIT.
    final course = _courseOrdinaire(scores: [88.0, 55.0, 50.0, 45.0], cote: '');
    final seuils = IaMemoryService.instance.seuilsConfiance;

    expect(course.partantsParRangIA.first.coteDecimale, 99.0,
        reason: 'TÉMOIN : cote absente ⇒ 99.0, sentinelle du producteur.');

    final reco = cascadeRecommandation(
      course: course,
      seuils: seuils,
      scoreConf: 88.0,
      score2nd: 55.0,
      score3: 50.0,
      score4: 45.0,
      coteTop: course.partantsParRangIA.first.coteDecimale,
    );

    // ignore: avoid_print
    print('─── MESURE T3 (cote inconnue) ──────────────────────────────');
    // ignore: avoid_print
    print('  cote = « » → coteDecimale = 99.0 → coteConnue = false');
    // ignore: avoid_print
    print('  décision = « ${reco.typePari} », coteDisponible = ${reco.coteDisponible}');
    // ignore: avoid_print
    print('  (cote connue, la même course donnerait « Gagnant+Placé »)');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    expect(reco.coteDisponible, isFalse,
        reason: 'La décision doit PORTER l\'indisponibilité de la cote, pour '
            'qu\'aucun consommateur n\'affiche un gain chiffré.');
    expect(reco.typePari, isNot('Gagnant+Placé'),
        reason: 'BLOC 1 §12 : la branche Gagnant+Placé est la branche '
            '« score élevé + COTE LONGUE ». Sans cote, sa prémisse est '
            'indémontrable : recommander un pari à DEUX mises dont le rapport '
            'est inconnu serait injustifié.');
    expect(reco.typePari, 'Simple Placé',
        reason: 'Repli sur le pari SCORE-SEULEMENT le moins engageant : une '
            'seule mise, aucune dépendance à la cote. Aucun seuil changé.');
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  T4 — COTE CONNUE : « Gagnant+Placé » reste atteignable
  // ─────────────────────────────────────────────────────────────────────────
  test('T4 — même course AVEC cote : « Gagnant+Placé » revient (T3 non obtenu '
      'en supprimant la branche)', () {
    final course = _courseOrdinaire(scores: [88.0, 55.0, 50.0, 45.0], cote: '12.0');
    final seuils = IaMemoryService.instance.seuilsConfiance;

    final reco = cascadeRecommandation(
      course: course,
      seuils: seuils,
      scoreConf: 88.0,
      score2nd: 55.0,
      score3: 50.0,
      score4: 45.0,
      coteTop: 12.0,
    );

    // ignore: avoid_print
    print('─── MESURE T4 (cote connue) ────────────────────────────────');
    // ignore: avoid_print
    print('  cote = 12.0 → décision = « ${reco.typePari} », '
        'coteDisponible = ${reco.coteDisponible}');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    expect(reco.coteDisponible, isTrue);
    expect(reco.typePari, 'Gagnant+Placé',
        reason: 'CONTRE-ÉPREUVE de T3 : la branche existe toujours et '
            's\'active dès que sa prémisse (cote longue) est démontrable.');
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  T5 — ABSTENTION EXPLICITE
  // ─────────────────────────────────────────────────────────────────────────
  test('T5 — scores insuffisants : « À surveiller » et ZÉRO numéro', () {
    final course = _courseOrdinaire(scores: [20.0, 15.0, 10.0, 5.0], cote: '12.0');
    final seuils = IaMemoryService.instance.seuilsConfiance;

    final reco = cascadeRecommandation(
      course: course,
      seuils: seuils,
      scoreConf: 20.0,
      score2nd: 15.0,
      score3: 10.0,
      score4: 5.0,
      coteTop: 12.0,
    );
    final viaPremium = typePariEtNumerosPourCourse(course);

    // ignore: avoid_print
    print('─── MESURE T5 (abstention) ─────────────────────────────────');
    // ignore: avoid_print
    print('  décision = « ${reco.typePari} », nbNumeros = ${reco.nbNumeros}');
    // ignore: avoid_print
    print('  premium_utils → « ${viaPremium.tp} », ${viaPremium.nums.length} numéros');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    expect(reco.estAbstention, isTrue);
    expect(reco.nbNumeros, 0,
        reason: 'Une abstention ne doit proposer AUCUN numéro : sinon le '
            'formulaire de mise la transformerait en pari.');
    expect(viaPremium.tp, 'À surveiller');
    expect(viaPremium.nums, isEmpty);
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  T6 — PERSISTANCE DU TYPE : nbNumeros cohérent avec la règle existante
  // ─────────────────────────────────────────────────────────────────────────
  test('T6 — regleNbNumerosPourTypePari est la SEULE définition du nombre', () {
    const attendus = <String, int>{
      'Quinté+': 5,
      'Quarté+': 4,
      'Tiercé': 3,
      'Tiercé Ordre': 3,
      'Tiercé Désordre': 3,
      'Couplé Gagnant': 2,
      'Couplé Placé': 2,
      'Simple Gagnant': 1,
      'Simple Placé': 1,
      'Gagnant+Placé': 1,
      'À surveiller': 1, // aucun numéro n'est joué, mais la règle rend 1
    };

    // ignore: avoid_print
    print('─── MESURE T6 (nombre de numéros par type) ────────────────');
    attendus.forEach((type, n) {
      final viaService = regleNbNumerosPourTypePari(type);
      final viaPremium = nbNumerosPourTypePari(type);
      // ignore: avoid_print
      print('  $type → service=$viaService, premium_utils=$viaPremium');
      expect(viaService, n, reason: 'règle du service pour $type');
      expect(viaPremium, viaService,
          reason: 'premium_utils doit déléguer, pas redéfinir ($type).');
    });
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');
  });
}
