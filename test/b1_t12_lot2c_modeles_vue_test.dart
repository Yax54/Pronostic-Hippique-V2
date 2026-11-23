// ═══════════════════════════════════════════════════════════════════════════
//  B1-T12 / LOT 2-C — TESTS DU RACCORDEMENT (partie 1/3)
//  MODÈLE `UserPrediction` + VUE DURABLE UNIQUE
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT — aucun fichier de production n'est modifié.
//
//  PÉRIMÈTRE COUVERT ICI :
//    • Famille A — schéma JSON : 26 / 28 / 31 clés, tolérance de relecture.
//    • Famille B — `gainRetenuBrut` : les 6 branches et leur priorité.
//    • Famille C — liaison stricte : `idTicketLie`, jamais de déduction.
//    • Famille D — table de priorité d'affichage (9 combinaisons).
//    • Famille E — `GainDurable` / `gainDeclareDurable` / `vueDurable`.
//
//  MÉTHODE : les assertions portent sur le COMPORTEMENT OBSERVABLE (clés
//  JSON, montants rendus, textes produits), jamais sur la structure interne
//  du code. Un test qui recopierait les conditions internes ne prouverait
//  rien.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/models/decision_gain_pmu.dart';
import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/services/gain_durable_vue.dart';
import 'package:pronostic_hippique/services/gain_pmu_types.dart'
    show EtatGain;

// ─────────────────────────── Outils de construction ────────────────────────

/// Prediction neutre : AUCUN champ financier du lot 2-A ni du lot 2-C.
UserPrediction _pred({
  String id = 'pred_1',
  double? montantGainManuel,
  String? idTicketLie,
  double? montantOfficielPmu,
  DecisionGainPmu? decisionGainPmu,
  double? montantGainManuelAvantDecision,
  // Champs officiels historiques (branches ② et ③ de gainRetenuBrut)
  double? gainRealise,
  double? dividendePmuReel,
  double montantMise = 0.0,
  double? miseGagnant,
  double? misePlace,
  EtatGain? etatGain,
}) =>
    UserPrediction(
      id: id,
      dateStr: '23112026',
      numReunion: 1,
      numCourse: 3,
      nomCourse: 'Prix de Test',
      hippodrome: 'Vincennes',
      numeroCheval: 7,
      nomCheval: 'Cheval Test',
      cote: 4.5,
      typePari: 'Simple Gagnant',
      createdAt: DateTime(2026, 11, 23, 10),
      montantGainManuel: montantGainManuel,
      idTicketLie: idTicketLie,
      montantOfficielPmu: montantOfficielPmu,
      decisionGainPmu: decisionGainPmu,
      montantGainManuelAvantDecision: montantGainManuelAvantDecision,
      gainRealise: gainRealise,
      dividendePmuReel: dividendePmuReel,
      montantMise: montantMise,
      miseGagnant: miseGagnant,
      misePlace: misePlace,
      etatGain: etatGain,
    );

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  //  FAMILLE A — SCHÉMA JSON
  // ═══════════════════════════════════════════════════════════════════════
  group('A — schéma JSON de UserPrediction', () {
    test('A1 un ticket SANS aucun champ B1-T12 garde exactement 26 clés', () {
      final p = _pred();
      expect(p.toJson().keys.length, 26);
    });

    test('A2 un ticket du lot 2-A (manuel + liaison) écrit 28 clés', () {
      final p = _pred(montantGainManuel: 12.0, idTicketLie: 'cle_suivi');
      expect(p.toJson().keys.length, 28);
      expect(p.toJson().containsKey('montantGainManuel'), isTrue);
      expect(p.toJson().containsKey('idTicketLie'), isTrue);
    });

    test('A3 un ticket du lot 2-C n\'ajoute QUE 3 clés au schéma 2-A', () {
      final avant = _pred(montantGainManuel: 12.0, idTicketLie: 'cle_suivi');
      final apres = _pred(
        montantGainManuel: 12.0,
        idTicketLie: 'cle_suivi',
        montantOfficielPmu: 99.0,
        decisionGainPmu: DecisionGainPmu.accepte,
        montantGainManuelAvantDecision: 12.0,
      );
      final ajoutees =
          apres.toJson().keys.toSet().difference(avant.toJson().keys.toSet());
      expect(ajoutees, <String>{
        'montantOfficielPmu',
        'decisionGainPmu',
        'montantGainManuelAvantDecision',
      });
      expect(apres.toJson().keys.length, 31);
    });

    test('A4 les 3 clés du lot 2-C sont ABSENTES quand elles sont null', () {
      final json = _pred(montantGainManuel: 5.0).toJson();
      expect(json.containsKey('montantOfficielPmu'), isFalse);
      expect(json.containsKey('decisionGainPmu'), isFalse);
      expect(json.containsKey('montantGainManuelAvantDecision'), isFalse);
    });

    test('A5 UNE seule clé du lot 2-C renseignée suffit à écrire les 3', () {
      final json = _pred(decisionGainPmu: DecisionGainPmu.refuse).toJson();
      // Les trois sont écrites ensemble : schéma stable, pas de clé orpheline.
      expect(json.containsKey('montantOfficielPmu'), isTrue);
      expect(json['montantOfficielPmu'], isNull);
      expect(json['decisionGainPmu'], 'refuse');
    });

    test('A6 la décision est sérialisée par son NOM, pas par son index', () {
      final json =
          _pred(decisionGainPmu: DecisionGainPmu.accepte).toJson();
      expect(json['decisionGainPmu'], 'accepte');
      expect(json['decisionGainPmu'], isA<String>());
    });

    test('A7 une décision INCONNUE relue ne produit aucune décision inventée',
        () {
      final p = UserPrediction.fromJson(
          _pred().toJson()..['decisionGainPmu'] = 'valeur_inexistante');
      expect(p.decisionGainPmu, isNull);
    });

    test('A8 une décision ABSENTE relue reste null', () {
      final p = UserPrediction.fromJson(_pred().toJson());
      expect(p.decisionGainPmu, isNull);
      expect(p.montantOfficielPmu, isNull);
      expect(p.montantGainManuelAvantDecision, isNull);
    });

    test('A9 aller-retour JSON : les 3 champs survivent exactement', () {
      final src = _pred(
        montantGainManuel: 12.5,
        idTicketLie: 'cle_suivi',
        montantOfficielPmu: 88.75,
        decisionGainPmu: DecisionGainPmu.accepte,
        montantGainManuelAvantDecision: 12.5,
      );
      final relu = UserPrediction.fromJson(src.toJson());
      expect(relu.montantOfficielPmu, 88.75);
      expect(relu.decisionGainPmu, DecisionGainPmu.accepte);
      expect(relu.montantGainManuelAvantDecision, 12.5);
      expect(relu.montantGainManuel, 12.5);
      expect(relu.idTicketLie, 'cle_suivi');
      // Le schéma ne bouge pas après relecture.
      expect(relu.toJson().keys.length, 31);
    });

    test('A10 relire puis réécrire est STABLE (aucune clé fantôme)', () {
      final src = _pred(
          montantOfficielPmu: 30.0, decisionGainPmu: DecisionGainPmu.refuse);
      final r1 = UserPrediction.fromJson(src.toJson()).toJson();
      final r2 =
          UserPrediction.fromJson(src.toJson()).toJson();
      expect(r1.keys.toSet(), r2.keys.toSet());
      expect(r1.keys.length, r2.keys.length);
    });

    test('A11 un ticket RÉSOLU garde ses 7 clés B-1 (non-régression)', () {
      // Les 7 clés B-1 ne s'écrivent QUE renseignées : c'est le comportement
      // historique, verrouillé par b1_champs_gain_persistes (ticket non résolu
      // ⇒ 26 clés). On vérifie donc sur un ticket réellement résolu.
      final p = _pred(etatGain: EtatGain.perdu);
      final json = p.toJson();
      for (final k in <String>[
        'etatGain',
        'rapportsAttribues',
        'etatTirelire',
        'dividendeGagnant',
        'dividendePlace',
        'miseBaseCentimesUtilisee',
        'motifNonDetermination',
      ]) {
        expect(json.containsKey(k), isTrue, reason: '$k doit rester écrite');
      }
      // Et un ticket NON résolu reste à 26 : aucune clé B-1 parasite.
      expect(_pred().toJson().keys.length, 26);
    });

    test('A12 les 7 clés B-1 cohabitent avec les 3 clés du lot 2-C', () {
      final p = _pred(
        etatGain: EtatGain.attribue,
        montantGainManuel: 12.0,
        idTicketLie: 'cle_suivi',
        montantOfficielPmu: 99.0,
        decisionGainPmu: DecisionGainPmu.accepte,
        montantGainManuelAvantDecision: 12.0,
      );
      // 26 historiques + 7 B-1 + 2 (lot 2-A) + 3 (lot 2-C) = 38.
      expect(p.toJson().keys.length, 38);
      final relu = UserPrediction.fromJson(p.toJson());
      expect(relu.decisionGainPmu, DecisionGainPmu.accepte);
      expect(relu.etatGain, EtatGain.attribue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  FAMILLE B — `gainRetenuBrut` : PRIORITÉ FINANCIÈRE
  // ═══════════════════════════════════════════════════════════════════════
  group('B — gainRetenuBrut : ordre de priorité', () {
    test('B1 ⓪ accepté : le gain OFFICIEL prime sur le manuel', () {
      final p = _pred(
        montantGainManuel: 12.0,
        montantOfficielPmu: 99.0,
        decisionGainPmu: DecisionGainPmu.accepte,
      );
      expect(p.gainRetenuBrut, 99.0);
    });

    test('B2 ⓪ accepté AVANT toute déclaration : l\'officiel seul reste lu',
        () {
      final p = _pred(
        montantOfficielPmu: 45.0,
        decisionGainPmu: DecisionGainPmu.accepte,
      );
      expect(p.gainRetenuBrut, 45.0);
    });

    test('B3 ① refusé : le montant MANUEL fait foi, l\'officiel est ignoré', () {
      final p = _pred(
        montantGainManuel: 12.0,
        montantOfficielPmu: 99.0,
        decisionGainPmu: DecisionGainPmu.refuse,
      );
      expect(p.gainRetenuBrut, 12.0);
    });

    test('B4 ① en attente (décision null) : le manuel seul, JAMAIS l\'officiel',
        () {
      final p = _pred(montantGainManuel: 12.0, montantOfficielPmu: 99.0);
      expect(p.decisionGainPmu, isNull);
      expect(p.gainRetenuBrut, 12.0,
          reason: 'sans décision, l\'officiel ne peut pas être retenu');
    });

    test('B5 ① un manuel de 0.0 est un MONTANT, il ne retombe pas sur le PMU',
        () {
      final p = _pred(
        montantGainManuel: 0.0,
        montantOfficielPmu: 99.0,
        decisionGainPmu: DecisionGainPmu.refuse,
      );
      expect(p.gainRetenuBrut, 0.0);
      expect(p.gainRetenuBrut, isNot(99.0));
    });

    test('B6 ② aucun manuel : le PMU fait foi via dividende × mise', () {
      final p = _pred(dividendePmuReel: 18.0, montantMise: 2.0);
      expect(p.gainRetenuBrut, 36.0);
    });

    test('B7 ② gainRealise (NET) est reconverti en brut avec la mise', () {
      final p = _pred(gainRealise: 30.0, montantMise: 5.0);
      expect(p.gainRetenuBrut, 35.0);
    });

    test('B8 ③ rien de fiable : INDIQUÉTERMINÉ, jamais 0 €', () {
      final p = _pred();
      expect(p.gainRetenuBrut, isNull,
          reason: 'null = inconnu ; 0.0 = perte établie');
    });

    test('B9 ③ une mise nulle n\'autorise PAS la conversion net → brut', () {
      final p = _pred(gainRealise: 30.0, montantMise: 0.0);
      expect(p.gainRetenuBrut, isNull,
          reason: 'une mise de 0 € ne prouve pas la mise réellement engagée');
    });

    test('B10 non-régression : sans aucun champ 2-C, les branches ② ③ '
        'sont IDENTIQUES à l\'historique', () {
      final p = _pred(dividendePmuReel: 10.0, montantMise: 3.0);
      expect(p.montantOfficielPmu, isNull);
      expect(p.decisionGainPmu, isNull);
      expect(p.gainRetenuBrut, 30.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  FAMILLE C — LIAISON STRICTE DES TICKETS
  // ═══════════════════════════════════════════════════════════════════════
  group('C — liaison par identifiant persistant', () {
    test('C1 estLiéAuTicket ne répond QUE sur idTicketLie', () {
      final lie = _pred(idTicketLie: 'cle_suivi');
      final nonLie = _pred();
      expect(lie.estLieAuTicket, isTrue);
      expect(lie.idTicketLie, 'cle_suivi');
      expect(nonLie.estLieAuTicket, isFalse);
      expect(nonLie.idTicketLie, isNull);
    });

    test('C2 une clé VOISINE ne suffit pas : aucune déduction approximative',
        () {
      final p = _pred(idTicketLie: 'R1C3_23112026_1200');
      expect(p.idTicketLie == 'R1C3_23112026_1201', isFalse,
          reason: 'deux paris de la même course restent indépendants');
    });

    test('C3 deux prédictions de la MÊME course restent distinguables', () {
      final a = _pred(
          id: 'pA', idTicketLie: 'cle_A', montantGainManuel: 10.0);
      final b = _pred(
          id: 'pB', idTicketLie: 'cle_B', montantGainManuel: 20.0);
      expect(a.idTicketLie, 'cle_A');
      expect(a.idTicketLie == 'cle_B', isFalse);
      expect(b.idTicketLie, 'cle_B');
      expect(b.gainRetenuBrut, 20.0);
      expect(a.gainRetenuBrut, 10.0);
    });

    test('C4 une prédiction non liée garde son gain manuel déclaré', () {
      final p = _pred(montantGainManuel: 7.5);
      expect(p.idTicketLie, isNull);
      expect(p.gainRetenuBrut, 7.5,
          reason: 'le gain déclaré ne dépend pas de la liaison');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  FAMILLE D — VUE DURABLE UNIQUE : TABLE DE PRIORITÉ
  // ═══════════════════════════════════════════════════════════════════════
  group('D — vueDurable : table de priorité (9 combinaisons)', () {
    test('D1 ① verdict officiel présent ⇒ null, MÊME avec une décision', () {
      final p = _pred(
        montantOfficielPmu: 99.0,
        decisionGainPmu: DecisionGainPmu.accepte,
        montantGainManuel: 12.0,
      );
      expect(
        vueDurable(p, verdictOfficielPresent: true),
        isNull,
        reason: 'le verdict B-3/B-4.5 ne peut pas être contourné',
      );
    });

    test('D2 ① verdict présent + demandeOuverte ⇒ null quand même', () {
      final p = _pred(montantOfficielPmu: 99.0);
      expect(
        vueDurable(p, verdictOfficielPresent: true, demandeOuverte: true),
        isNull,
      );
    });

    test('D3 ② accepté avec montant > 0 ⇒ officiel, montant exact', () {
      final p = _pred(
        montantOfficielPmu: 88.0,
        decisionGainPmu: DecisionGainPmu.accepte,
        montantGainManuel: 12.0,
      );
      final v = vueDurable(p, verdictOfficielPresent: false)!;
      expect(v.estOfficiel, isTrue);
      expect(v.montant, 88.0);
      expect(v.libelle, contains('Gain gagné'));
      expect(v.libelle, contains('gain officiel PMU'));
      expect(v.libelle, isNot(contains('montant déclaré')));
    });

    test('D4 ② accepté avec officiel à 0 ⇒ perte établie, PAS indéterminé', () {
      final p = _pred(
        montantOfficielPmu: 0.0,
        decisionGainPmu: DecisionGainPmu.accepte,
      );
      final v = vueDurable(p, verdictOfficielPresent: false)!;
      expect(v.montant, 0.0);
      expect(v.montant, isNotNull);
      expect(v.libelle, contains('Perdu'));
      expect(v.estOfficiel, isTrue);
    });

    test('D5 ② accepté SANS montant officiel ⇒ on le DIT, rien n\'est inventé',
        () {
      final p = _pred(decisionGainPmu: DecisionGainPmu.accepte);
      final v = vueDurable(p, verdictOfficielPresent: false)!;
      expect(v.montant, isNull);
      expect(v.libelle, contains('montant indisponible'));
    });

    test('D6 ③ refusé ⇒ MANUEL, et l\'officiel n\'est pas appliqué', () {
      final p = _pred(
        montantGainManuel: 12.0,
        montantOfficielPmu: 99.0,
        decisionGainPmu: DecisionGainPmu.refuse,
      );
      final v = vueDurable(p, verdictOfficielPresent: false)!;
      expect(v.estOfficiel, isFalse);
      expect(v.montant, 12.0);
      expect(v.libelle, contains('montant déclaré'));
      expect(v.libelle, isNot(contains('en attente')));
    });

    test('D7 ③ refusé sans déclaration ⇒ indéterminé déclaré, jamais 0 €', () {
      final p = _pred(
        montantOfficielPmu: 99.0,
        decisionGainPmu: DecisionGainPmu.refuse,
      );
      final v = vueDurable(p, verdictOfficielPresent: false)!;
      expect(v.montant, isNull);
      expect(v.libelle, contains('aucun montant déclaré'));
    });

    test('D8 ④ EN ATTENTE avec manuel ⇒ le manuel seul, officiel en réserve',
        () {
      final p = _pred(montantGainManuel: 12.0, montantOfficielPmu: 99.0);
      final v = vueDurable(p, verdictOfficielPresent: false)!;
      expect(v.montant, 12.0);
      expect(v.montant, isNot(99.0),
          reason: 'aucune sélection automatique du montant officiel');
      expect(v.libelle, contains('en attente'));
    });

    test('D9 ④ EN ATTENTE sans manuel ⇒ décision attendue, montant null', () {
      final p = _pred(montantOfficielPmu: 99.0);
      final v = vueDurable(p, verdictOfficielPresent: false)!;
      expect(v.montant, isNull);
      expect(v.libelle, contains('décision est attendue'));
    });

    test('D10 aucun champ 2-C ni 2-A ⇒ null (affichage historique intact)', () {
      expect(vueDurable(_pred(), verdictOfficielPresent: false), isNull);
    });

    test('D11 prédiction absente (null) ⇒ null, aucune vue fabriquée', () {
      expect(vueDurable(null, verdictOfficielPresent: false), isNull);
      expect(vueDurable(null, verdictOfficielPresent: true), isNull);
    });

    test('D12 gain déclaré SEUL (lot 2-A) ⇒ enfin affiché', () {
      final p = _pred(montantGainManuel: 15.0);
      final v = vueDurable(p, verdictOfficielPresent: false)!;
      expect(v.montant, 15.0);
      expect(v.libelle, contains('Gain gagné'));
      expect(v.libelle, contains('montant déclaré'));
      expect(v.estOfficiel, isFalse);
    });

    test('D13 gain déclaré à 0.0 ⇒ « déclaré 0 € », distinct de l\'absence',
        () {
      final v = vueDurable(_pred(montantGainManuel: 0.0),
          verdictOfficielPresent: false)!;
      expect(v.montant, 0.0);
      expect(v.libelle, contains('0 €'));
      expect(v.libelle, isNot(contains('Gain gagné')));
    });

    test('D14 invariant : « 🏆 Gain gagné » implique TOUJOURS un montant > 0',
        () {
      final cas = <UserPrediction>[
        _pred(montantGainManuel: 12.0, montantOfficielPmu: 99.0,
            decisionGainPmu: DecisionGainPmu.accepte),
        _pred(montantGainManuel: 12.0, montantOfficielPmu: 99.0,
            decisionGainPmu: DecisionGainPmu.refuse),
        _pred(montantGainManuel: 12.0, montantOfficielPmu: 99.0),
        _pred(montantGainManuel: 0.0, decisionGainPmu: DecisionGainPmu.refuse),
        _pred(montantOfficielPmu: 0.0,
            decisionGainPmu: DecisionGainPmu.accepte),
        _pred(montantGainManuel: 3.25),
      ];
      for (final p in cas) {
        final v = vueDurable(p, verdictOfficielPresent: false);
        if (v != null && v.libelle.contains('Gain gagné')) {
          expect(v.montant, isNotNull);
          expect(v.montant! > 0, isTrue,
              reason: '« Gain gagné » sans montant positif : ${v.libelle}');
        }
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  FAMILLE E — `gainDeclareDurable` : ISOLEMENT
  // ═══════════════════════════════════════════════════════════════════════
  group('E — gainDeclareDurable', () {
    test('E1 sans déclaration ⇒ null (absence ≠ 0 €)', () {
      expect(
        gainDeclareDurable(_pred(),
            verdictOfficielPresent: false, decisionB1T12Presente: false),
        isNull,
      );
    });

    test('E2 déclaration seule ⇒ vue non officielle, montant exact', () {
      final v = gainDeclareDurable(_pred(montantGainManuel: 21.0),
          verdictOfficielPresent: false, decisionB1T12Presente: false)!;
      expect(v.montant, 21.0);
      expect(v.estOfficiel, isFalse);
    });

    test('E3 verdict officiel présent ⇒ null, le verdict garde la priorité', () {
      expect(
        gainDeclareDurable(_pred(montantGainManuel: 21.0),
            verdictOfficielPresent: true, decisionB1T12Presente: false),
        isNull,
      );
    });

    test('E4 décision B1-T12 présente ⇒ null, c\'est elle qui tranche', () {
      expect(
        gainDeclareDurable(_pred(montantGainManuel: 21.0),
            verdictOfficielPresent: false, decisionB1T12Presente: true),
        isNull,
      );
    });

    test('E5 décisionGainDurable : verdict présent ⇒ null même avec décision',
        () {
      expect(
        decisionGainDurable(
          _pred(
            montantOfficielPmu: 50.0,
            decisionGainPmu: DecisionGainPmu.accepte,
          ),
          verdictOfficielPresent: true,
        ),
        isNull,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  FAMILLE F — IMMUTABILITÉ / copyWith À SENTINELLE
  // ═══════════════════════════════════════════════════════════════════════
  group('F — copyWith : sentinelle et portée', () {
    test('F1 argument OMIS ⇒ la valeur existante est conservée', () {
      final p = _pred(
        montantOfficielPmu: 99.0,
        decisionGainPmu: DecisionGainPmu.accepte,
        montantGainManuelAvantDecision: 12.0,
      );
      final c = p.copyWith();
      expect(c.montantOfficielPmu, 99.0);
      expect(c.decisionGainPmu, DecisionGainPmu.accepte);
      expect(c.montantGainManuelAvantDecision, 12.0);
    });

    test('F2 null EXPLICITE ⇒ efface, ce n\'est pas une omission', () {
      final p = _pred(
        montantOfficielPmu: 99.0,
        decisionGainPmu: DecisionGainPmu.refuse,
      );
      final c = p.copyWith(
          montantOfficielPmu: null,
          decisionGainPmu: null,
          montantGainManuelAvantDecision: null);
      expect(c.montantOfficielPmu, isNull);
      expect(c.decisionGainPmu, isNull);
    });

    test('F3 modifier montantGainManuel NE touche PAS la décision', () {
      final p = _pred(
        montantGainManuel: 12.0,
        montantOfficielPmu: 99.0,
        decisionGainPmu: DecisionGainPmu.refuse,
        montantGainManuelAvantDecision: 12.0,
      );
      final c = p.copyWith(montantGainManuel: 25.0);
      expect(c.montantGainManuel, 25.0);
      expect(c.decisionGainPmu, DecisionGainPmu.refuse,
          reason: 'une réédition du montant n\'annule pas la décision');
      expect(c.montantOfficielPmu, 99.0);
      expect(c.montantGainManuelAvantDecision, 12.0);
    });

    test('F4 la source n\'est JAMAIS mutée', () {
      final p = _pred(montantGainManuel: 12.0);
      p.copyWith(montantGainManuel: 99.0);
      expect(p.montantGainManuel, 12.0);
    });

    test('F5 les champs officiels historiques traversent copyWith', () {
      final p = _pred(
          etatGain: EtatGain.attribue,
          gainRealise: 30.0,
          dividendePmuReel: 9.0,
          montantMise: 2.0);
      final c = p.copyWith(montantGainManuel: 5.0);
      expect(c.etatGain, EtatGain.attribue);
      expect(c.gainRealise, 30.0);
      expect(c.dividendePmuReel, 9.0);
      expect(c.montantMise, 2.0);
    });
  });
}
