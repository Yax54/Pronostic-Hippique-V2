// ═══════════════════════════════════════════════════════════════════════════
//  A-0 / T2-T3-T8 — Vérification STRUCTURELLE des gardes dans le source
//
//  ⚠️  POURQUOI STRUCTUREL ET NON COMPORTEMENTAL.
//      Les trois voies automatiques vivent dans des écrans (`mes_paris_screen`,
//      `profile_profil_tab`) et un service singleton (`AlertService`) qui
//      exigent un `BuildContext`, un `PmuProvider` monté et un cache réseau.
//      Les monter dans un test unitaire produirait un test faux (harnais
//      simulé) au lieu d'une preuve. La méthode employée ici est celle déjà
//      utilisée par `v12_d2h8_lifecycle_test.dart:347` : lecture du fichier
//      de production et vérification de la présence ET de la POSITION de la
//      garde par rapport à l'écriture qu'elle protège.
//
//  Ce que ces tests PROUVENT :
//    - chaque garde existe, est placée AVANT l'écriture financière, et
//      utilise le helper unique (pas une comparaison de chaîne locale) ;
//    - P4/P5 font un `return` qui ne précède AUCUNE écriture d'affichage ;
//    - P6/P7 conservent les entrées (pas de `.where(...)` excluant G+P).
//
//  Ce que ces tests NE PROUVENT PAS :
//    - l'exécution réelle des écrans sur appareil. Signalé en risque résiduel.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Lit un fichier de production et échoue explicitement s'il est absent.
String _lire(String chemin) {
  final f = File(chemin);
  expect(f.existsSync(), isTrue, reason: 'fichier introuvable: $chemin');
  return f.readAsStringSync();
}

/// Vrai si [aiguille] apparaît AVANT [avant] dans [source].
void _attendreAvant(String source, String aiguille, String avant,
    {required String motif}) {
  final iAiguille = source.indexOf(aiguille);
  final iAvant = source.indexOf(avant);
  expect(iAiguille, greaterThanOrEqualTo(0),
      reason: '$motif — aiguille absente: $aiguille');
  expect(iAvant, greaterThanOrEqualTo(0),
      reason: '$motif — repère absent: $avant');
  expect(iAiguille, lessThan(iAvant),
      reason: '$motif — la garde doit précéder l\'écriture protégée');
}

void main() {
  group('A-0 / T2 — les 3 gardes existent et précèdent l\'écriture', () {
    test('T2a — P1 : mes_paris_screen garde avant validatePrediction', () {
      final src = _lire('lib/screens/mes_paris_screen.dart');
      _attendreAvant(
        src,
        'if (estTypeGagnantPlace(pred.typePari)) continue; // A-0',
        'pmuProvider.validatePrediction(',
        motif: 'P1',
      );
    });

    test('T2b — P2 : profile_profil_tab garde avant validatePrediction', () {
      final src = _lire('lib/widgets/profile/profile_profil_tab.dart');
      _attendreAvant(
        src,
        'if (estTypeGagnantPlace(pred.typePari)) continue; // A-0',
        'widget.provider.validatePrediction(',
        motif: 'P2',
      );
    });

    test('T2c — P3 : alert_service garde avant validatePrediction', () {
      final src = _lire('lib/services/alert_service.dart');
      _attendreAvant(
        src,
        'if (estTypeGagnantPlace(pred.typePari)) continue; // A-0',
        '_pmuProvider!.validatePrediction(',
        motif: 'P3',
      );
    });

    test('T2d — P4 (B-4.5) : mes_paris_screen n\'écrit plus de dividende MAX',
        () {
      // ★ LOT B-4.5 — la garde T2d protégeait le `reduce(MAX)` : elle exigeait
      // que la garde G+P précède `provider.enregistrerDividendePmu(`. B-4.5
      // SUPPRIME cette écriture (et donc le `reduce` qu'elle protégeait) : la
      // propriété à défendre est désormais plus forte — l'écriture n'existe
      // plus du tout, donc aucun G+P ne peut recevoir un dividende MAX.
      final src = _lire('lib/screens/mes_paris_screen.dart');
      expect(src.contains('provider.enregistrerDividendePmu('), isFalse,
          reason: 'P4 — plus aucune injection de dividende MAX');
      expect(src.contains('enregistrerDividendePmuTracked('), isFalse,
          reason: 'P4 — plus aucune écriture Tracked de dividende MAX');
      // ⚠️ La chaîne 'reduce((a, b) => a.dividende > b.dividende' ne peut PAS
      // être cherchée ici : elle est CITÉE dans le commentaire de documentation
      // qui explique sa suppression. La vérification exacte, en source NETTE de
      // commentaires, est faite par B4.3/7.5 (test/b4_3_enregistreur_verdict_test.dart).
      // Le verdict officiel remplace ce chemin.
      // ★ B1-T12 / LOT 2-C — ANCRE MISE À JOUR, INTENTION CONSERVÉE.
      //   La garde exigeait `resoudrePrediction(` DANS l'écran. La résolution
      //   a été déplacée DANS `PmuProvider.appliquerVerdictGainPredictionSecurise`
      //   (défaut D1 : l'écran résolvait sur un instantané capturé avant
      //   l'attente réseau, donc une saisie manuelle concurrente était écrasée).
      //   L'écran n'exécute donc plus la résolution LUI-MÊME : il délègue.
      //   La propriété défendue est INCHANGÉE et plus stricte — aucun dividende
      //   n'est sélectionné par l'écran, le verdict vient toujours du moteur
      //   officiel B-3 via l'enregistreur B-4.3.
      expect(src.contains('appliquerVerdictGainPredictionSecurise'), isTrue,
          reason: 'B-4.5 / 2-C — le verdict officiel est écrit via la voie '
              'sécurisée du provider');
      expect(src.contains('resoudreSuivi('), isTrue, reason: 'B-4.5');
    });

    test('T2e — P5 (B-4.5) : paris_detail_screen n\'écrit plus de dividende MAX',
        () {
      // ★ LOT B-4.5 — même raison que T2d.
      final src = _lire('lib/screens/paris_detail_screen.dart');
      expect(src.contains('provider.enregistrerDividendePmu('), isFalse,
          reason: 'P5 — plus aucune injection de dividende MAX');
      expect(src.contains('enregistrerDividendePmuTracked('), isFalse,
          reason: 'P5 — plus aucune écriture Tracked de dividende MAX');
      // ⚠️ La chaîne 'reduce((a, b) => a.dividende > b.dividende' ne peut PAS
      // être cherchée ici : elle est CITÉE dans le commentaire de documentation
      // qui explique sa suppression. La vérification exacte, en source NETTE de
      // commentaires, est faite par B4.3/7.5 (test/b4_3_enregistreur_verdict_test.dart).
      // ★ B1-T12 / LOT 2-C — même mise à jour d'ancre que T2d, même intention :
      //   la résolution a migré dans `PmuProvider` pour ne plus travailler sur
      //   un instantané périmé. L'écran délègue, il ne résout plus lui-même.
      expect(src.contains('appliquerVerdictGainPredictionSecurise'), isTrue,
          reason: 'B-4.5 / 2-C — écriture du verdict via la voie sécurisée');
      expect(src.contains('resoudreSuivi('), isTrue, reason: 'B-4.5');
    });

    test('T2f — P6 et P7 : les entrées G+P sont CONSERVÉES (S2)', () {
      final src = _lire('lib/screens/ia_performance_screen.dart');
      // La neutralisation doit apparaître exactement 2 fois (P6 + P7).
      final occurrences = RegExp(r"'isCorrect': null, // en attente du Lot B")
          .allMatches(src)
          .length;
      expect(occurrences, 2,
          reason: 'P6 et P7 doivent tous deux neutraliser isCorrect');
      // Et aucune exclusion de type par .where(...) ne doit avoir été ajoutée.
      expect(
        RegExp(r'\.where\([^)]*estTypeGagnantPlace').hasMatch(src),
        isFalse,
        reason: 'S2 interdit d\'exclure les entrées : on neutralise, on ne filtre pas',
      );
      // gainNet neutralisé, jamais un montant.
      final gainNeutralise =
          RegExp(r"'gainNet':   0\.0").allMatches(src).length;
      expect(gainNeutralise, 2,
          reason: 'les deux sites doivent forcer gainNet à 0.0');
    });
  });

  group('A-0 / T3 — P4/P5 ne bloquent AUCUN affichage', () {
    test('T3a — P4 se trouve dans _majGainReelDansProfil, pas dans le rendu',
        () {
      final src = _lire('lib/screens/mes_paris_screen.dart');
      // ★ B-4.5 — MESURE : la méthode `_majGainReelDansProfil` existe toujours,
      //   mais elle ne fait plus d'écriture financière : la garde A-0 n'a donc
      //   plus d'objet. On vérifie que la méthode est bien là (pas supprimée en
      //   silence) et que son corps ne contient plus aucune écriture.
      // ★ LOT 2-C / DERNIER VERROU — ANCRE DÉPLACÉE, INTENTION CONSERVÉE.
      //   La méthode est devenue `Future<void> ... async` : elle ATTEND
      //   désormais la confirmation de l'écriture du verdict au lieu de la
      //   lancer sans preuve. La garde porte sur sa PRÉSENCE et sur l'ABSENCE
      //   d'écriture de dividende dans son corps — les deux sont inchangées,
      //   et la vérification reste STRICTE (aucune écriture financière).
      expect(
          src.contains(
              'Future<void> _majGainReelDansProfil(List<RapportPmu> rapports) async {'),
          isTrue,
          reason: 'la méthode doit rester présente');
      final debut = src.indexOf(
          'Future<void> _majGainReelDansProfil(List<RapportPmu> rapports) async {');
      final fin = src.indexOf('void _verifierResultatAuto()');
      final corps = src.substring(debut, fin > debut ? fin : src.length);
      expect(corps.contains('enregistrerDividendePmu'), isFalse,
          reason: 'P4 — le corps ne doit plus écrire de dividende');
      // ★ B-4.5 — les DEUX écritures financières de cette méthode ont disparu.
      expect(src.contains('alertSvc.enregistrerDividendePmuTracked('), isFalse,
          reason: 'P4 — l\'écriture Tracked du dividende MAX est supprimée');
    });

    test('T3b — le chargement des rapports reste AVANT l\'écriture financière',
        () {
      final src = _lire('lib/screens/mes_paris_screen.dart');
      // `_rapportsPmu = rapports` doit être affecté avant l'appel à la
      // méthode qui contient P4 → l'affichage des rapports reste intact.
      _attendreAvant(
        src,
        '_rapportsPmu = rapports;',
        '_majGainReelDansProfil(rapports);',
        motif: 'T3 — les rapports sont posés avant la garde financière',
      );
    });

    test('T3c — l\'arrivée officielle n\'est jamais conditionnée par A-0', () {
      final src = _lire('lib/screens/mes_paris_screen.dart');
      // Aucune ligne posant l'arrivée ne doit contenir une garde G+P.
      for (final ligne in src.split('\n')) {
        if (ligne.contains('_arrivee =') ||
            ligne.contains('_isGagnant =') ||
            ligne.contains('_resultMessage =') ||
            ligne.contains('_disqualifies =')) {
          expect(ligne.contains('estTypeGagnantPlace'), isFalse,
              reason: 'A-0 ne doit pas toucher au résultat sportif : $ligne');
        }
      }
      // …et ces affectations existent toujours (témoin d'absence de régression).
      expect(src.contains('_arrivee = arrivee;'), isTrue);
      expect(src.contains('_isGagnant = gagnant;'), isTrue);
    });

    test('T3d — le bloc G+P sportif conserve ses 3 cas', () {
      final src = _lire('lib/screens/mes_paris_screen.dart');
      // Témoins du bloc l.1299-1315 : 1er / placé / non placé.
      expect(src.contains('gagne les 2 paris (Gagnant + Placé)'), isTrue,
          reason: 'le cas « 1er » du G+P doit subsister');
      expect(src.contains('Placé ✓ / Gagnant ✗'), isTrue,
          reason: 'le cas « placé non gagnant » doit subsister');
      expect(src.contains('non placé'), isTrue);
      // Le bloc sportif ne doit pas contenir de garde A-0.
      final iBloc = src.indexOf("case 'gagnant+placé':");
      final iGardeSuivante =
          src.indexOf('if (estTypeGagnantPlace(pred.typePari)) continue;');
      expect(iBloc, greaterThanOrEqualTo(0));
      expect(iGardeSuivante, greaterThan(iBloc),
          reason: 'la garde financière doit être APRÈS le bloc sportif');
    });
  });

  group('A-0 / T8 — les mécanismes interdits sont intacts', () {
    test('T8a — analyseJourneeComplete et mettreAJourStatsTypes inchangés', () {
      final src = _lire('lib/services/ia_memory_service.dart');
      expect(src.contains('if (isCorrect == null) continue;'), isTrue,
          reason: 'la règle préexistante doit être intacte');
      expect(src.contains('_statsTypes.clear();'), isTrue);
      expect(src.contains('Future<AnalyseJourneeResultat> analyseJourneeComplete({'),
          isTrue);
    });

    test('T8b — aucune formule de gain PMU modifiée', () {
      // Les 3 formules sensibles doivent être dans leur état d\'origine.
      final alert = _lire('lib/services/alert_service.dart');
      expect(alert.contains('gainNet = mise * cpReel - mise * 2;'), isTrue,
          reason: 'la formule G+P de alert_service ne doit pas être touchée');
      expect(alert.contains('gainNet = mise * cote - mise;'), isTrue);

      final provider = _lire('lib/providers/pmu_provider.dart');
      expect(provider.contains('? (old.cote * mise) - mise'), isTrue,
          reason: 'validatePrediction ne doit pas être modifiée');
      expect(
          provider.contains('? (dividendePmuReel * old.montantMise) - old.montantMise'),
          isTrue,
          reason: 'enregistrerDividendePmu ne doit pas être modifiée');
    });

    test('T8c — le helper est le SEUL point de décision', () {
      // Aucun des fichiers du diff ne doit réimplémenter le test de chaîne.
      const fichiers = [
        'lib/screens/mes_paris_screen.dart',
        'lib/widgets/profile/profile_profil_tab.dart',
        'lib/services/alert_service.dart',
        'lib/screens/paris_detail_screen.dart',
        'lib/screens/ia_performance_screen.dart',
      ];
      for (final f in fichiers) {
        final src = _lire(f);
        // Interdit : 'gagnant+placé' écrit en dur hors du helper.
        expect(src.contains("== 'gagnant+placé'"), isFalse,
            reason: '$f ne doit pas réimplémenter la reconnaissance');
        // Obligatoire : le helper est importé et utilisé — SAUF pour
        // `paris_detail_screen.dart` depuis B-4.5.
        //
        // ★ LOT B-4.5 — MESURE : sa seule utilisation du helper était la garde
        //   `estTypeGagnantPlace(widget.tracked.typePari)` qui protégeait le
        //   `reduce(MAX)`. Ce `reduce` est supprimé, donc la garde aussi, donc
        //   l'import devient inutilisé (`flutter analyze` le signale). Le G+P
        //   n'est plus EXCLU du calcul : il est résolu par le moteur B-3, qui
        //   traite ses deux composantes séparément — ce qui est le but même du
        //   lot. La contrepartie est vérifiée ci-dessous : l'écran ne
        //   réimplémente pas la reconnaissance en dur.
        if (f == 'lib/screens/paris_detail_screen.dart') {
          expect(src.contains('type_pari_utils.dart'), isFalse,
              reason: '$f ne doit plus importer un helper devenu inutile');
          expect(src.contains('estTypeGagnantPlace('), isFalse,
              reason: '$f ne doit plus filtrer le G+P');
        } else {
          expect(src.contains('type_pari_utils.dart'), isTrue,
              reason: '$f doit importer le helper');
          expect(src.contains('estTypeGagnantPlace('), isTrue,
              reason: '$f doit utiliser le helper');
        }
      }
    });

    test('T8d — calendrier et grosses combinaisons hors du diff', () {
      // Ces fichiers ne doivent contenir AUCUNE trace de la garde A-0.
      const horsPerimetre = [
        'lib/widgets/ia/ia_calendrier_tab.dart',
        'lib/models/quasi_gros_paris_models.dart',
        'lib/services/quasi_gros_paris_service.dart',
        'lib/screens/home_screen.dart',
        'lib/services/data_refresh_service.dart',
        'lib/services/zone_turf_service.dart',
        'lib/services/arrivee_officielle_service.dart',
      ];
      for (final f in horsPerimetre) {
        final src = _lire(f);
        expect(src.contains('estTypeGagnantPlace'), isFalse,
            reason: '$f est hors périmètre A-0 et ne doit pas être modifié');
      }
    });
  });
}
