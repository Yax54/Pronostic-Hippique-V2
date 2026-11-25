// ═══════════════════════════════════════════════════════════════════════════
//  BLOC 1 — BEST BET : LE VERROU DE RÉSOLUTION OFFICIELLE
//  (non-régression du couple « ne jamais figer » / « ne jamais boucler »)
//
//  DÉFAUTS MESURÉS QUE CE FICHIER PROTÈGE
//  --------------------------------------
//  D1 — GEL DÉFINITIF. `_resolutionOfficielleTerminee` était posé à `true`
//       dans le `finally` de `_resoudreGainsOfficiels`, donc AUSSI quand une
//       exception interrompait la boucle ou quand la source ne répondait pas.
//       La garde du `build` étant
//           `if (!_resolutionOfficielleTerminee && !_resolutionOfficielleLancee)`
//       un incident réseau au premier rendu supprimait TOUTE tentative
//       ultérieure dans la vie de l'écran : les gains restaient indéterminés
//       jusqu'au redémarrage de l'application.
//
//  D2 — PORTE DE SORTIE INATTEIGNABLE. `_rafraichirGainsOfficiels`, écrite
//       précisément pour rattraper D1, n'avait AUCUN appelant.
//
//  D3 — BOUCLE RÉSEAU (défaut INDUIT par la correction de D1). Le `setState`
//       du `finally` provoque un `build`, qui relance une passe, qui échoue,
//       qui reprovoque un `build`… Sans plafond, une source durablement muette
//       est interrogée sans fin.
//
//  CE QUE CE FICHIER PROUVE, ET COMMENT
//  ------------------------------------
//  Trois niveaux, volontairement séparés :
//
//    1. EXÉCUTION de `EtatResolutionGainsOfficiels` — la décision réelle
//       consommée par l'écran, énumérée sur tous ses chemins. Ce n'est pas une
//       réimplémentation de test : c'est la classe de production.
//    2. SOURCE — le câblage de l'écran : plus aucun verrou posé dans un
//       `finally` sans condition, bouton réellement branché, plafond réellement
//       consulté.
//    3. LIMITE DÉCLARÉE — ce fichier n'exécute PAS `BestBetScreen` (il exige
//       un `PmuProvider`, un `IaMemoryService` initialisé et un réseau). Aucun
//       test ici ne constitue une validation sur téléphone réel.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/services/etat_resolution_gains_officiels.dart';

// ───────────────────────────────────────────────────────────────────────────
// 1. EXÉCUTION — la décision de production, chemin par chemin
// ───────────────────────────────────────────────────────────────────────────
void main() {
  group('E0 — invariants de base', () {
    test('l\'état initial est OUVERT : rien n\'a encore été tenté', () {
      expect(EtatResolutionGainsOfficiels.initial.tentativesAuto, 0);
      expect(EtatResolutionGainsOfficiels.initial.verrouille, isFalse);
      expect(
        EtatResolutionGainsOfficiels.initial.doitRelancerAutomatiquement,
        isTrue,
      );
    });

    test('le plafond vaut 3 et n\'est pas nul (sinon D1 reviendrait)', () {
      expect(kMaxTentativesResolutionAuto, 3);
      expect(kMaxTentativesResolutionAuto, greaterThan(1));
    });
  });

  group('E1 — succès complet : la résolution se referme', () {
    test('une passe complète sans indéterminé pose le verrou', () {
      final e = EtatResolutionGainsOfficiels.initial.apresPasse(
        passeComplete: true,
        resteIndetermine: false,
      );
      expect(e.tentativesAuto, 0);
      expect(e.verrouille, isFalse);
      // Le verrou effectif de l'écran est `succesComplet || verrouille` : ici
      // c'est le succès complet qui le pose, et il est vérifié en source (S3).
    });

    test('un succès complet REMET le compteur à zéro', () {
      // Trois échecs, puis un succès : un futur incident doit retrouver ses
      // trois passes, sinon un seul échec tardif désarmerait l'écran pour de bon.
      var e = EtatResolutionGainsOfficiels.initial;
      for (var i = 0; i < kMaxTentativesResolutionAuto; i++) {
        e = e.apresPasse(passeComplete: false, resteIndetermine: true);
      }
      expect(e.verrouille, isTrue);
      e = e.apresPasse(passeComplete: true, resteIndetermine: false);
      expect(e.tentativesAuto, 0);
      expect(e.verrouille, isFalse);
    });
  });

  group('E2 — D1 : un incident NE FIGE PAS définitivement', () {
    test('passe incomplète (exception) : le verrou n\'est pas encore posé', () {
      final e = EtatResolutionGainsOfficiels.initial.apresPasse(
        passeComplete: false,
        resteIndetermine: true,
      );
      expect(e.verrouille, isFalse,
          reason: 'après un seul échec, la résolution doit rester ouvable');
      expect(e.doitRelancerAutomatiquement, isTrue);
    });

    test('source muette mais boucle allée au bout : idem', () {
      final e = EtatResolutionGainsOfficiels.initial.apresPasse(
        passeComplete: true,
        resteIndetermine: true,
      );
      expect(e.verrouille, isFalse);
    });

    test('un seul indéterminé suffit à laisser la résolution ouverte', () {
      // `resteIndetermine` est un OU sur toutes les opportunités terminées :
      // dès qu'une seule n'a pas de sort établi, il ne faut pas se refermer.
      final e = EtatResolutionGainsOfficiels.initial.apresPasse(
        passeComplete: true,
        resteIndetermine: true,
      );
      expect(e.verrouille, isFalse);
    });
  });

  group('E3 — D3 : la reprise automatique est BORNÉE', () {
    test('exactement kMaxTentativesResolutionAuto passes sont autorisées', () {
      var e = EtatResolutionGainsOfficiels.initial;
      var passe = 0;
      while (e.doitRelancerAutomatiquement) {
        passe++;
        e = e.apresPasse(passeComplete: false, resteIndetermine: true);
        expect(passe, lessThanOrEqualTo(1000),
            reason: 'garde anti-boucle du test lui-même');
      }
      expect(passe, kMaxTentativesResolutionAuto);
      expect(e.verrouille, isTrue);
    });

    test('une fois le plafond atteint, l\'état est STABLE', () {
      var e = EtatResolutionGainsOfficiels.initial;
      for (var i = 0; i < kMaxTentativesResolutionAuto; i++) {
        e = e.apresPasse(passeComplete: false, resteIndetermine: true);
      }
      final fige = e;
      // Dix appels supplémentaires ne doivent plus rien changer : sans cela,
      // un `build` déclenché par le `setState` du `finally` relancerait encore.
      for (var i = 0; i < 10; i++) {
        e = e.apresPasse(passeComplete: false, resteIndetermine: true);
      }
      expect(e.tentativesAuto, fige.tentativesAuto);
      expect(e.verrouille, isTrue);
    });

    test('le compteur ne recule jamais sur un échec', () {
      final e = EtatResolutionGainsOfficiels.initial
          .apresPasse(passeComplete: false, resteIndetermine: true);
      final apres = e.apresPasse(passeComplete: false, resteIndetermine: true);
      expect(apres.tentativesAuto, greaterThan(e.tentativesAuto));
    });
  });

  group('E4 — le rafraîchissement MANUEL reste toujours possible', () {
    test('il est autorisé même plafond atteint (sinon D2 reviendrait)', () {
      var e = EtatResolutionGainsOfficiels.initial;
      for (var i = 0; i < 10; i++) {
        e = e.apresPasse(passeComplete: false, resteIndetermine: true);
      }
      expect(e.verrouille, isTrue);
      // La méthode ne lève pas et ne verrouille rien de plus : l'action
      // explicite de l'utilisateur n'est jamais bloquée par le plafond.
      final apresManuel = e.apresRafraichissementManuel();
      expect(apresManuel.verrouille, isTrue,
          reason: 'un clic ne réarme pas la reprise AUTOMATIQUE');
      expect(apresManuel.tentativesAuto, e.tentativesAuto);
    });

    test('il ne réarme pas non plus la reprise automatique', () {
      final e = EtatResolutionGainsOfficiels.initial
          .apresPasse(passeComplete: false, resteIndetermine: true)
          .apresPasse(passeComplete: false, resteIndetermine: true)
          .apresPasse(passeComplete: false, resteIndetermine: true);
      final apresManuel = e.apresRafraichissementManuel();
      expect(apresManuel.doitRelancerAutomatiquement,
          e.doitRelancerAutomatiquement,
          reason: 'le clic ne doit pas rouvrir une boucle spontanée');
    });
  });

  group('E5 — immuabilité : aucun état partagé modifié en place', () {
    test('chaque passe produit un NOUVEL objet', () {
      final depart = EtatResolutionGainsOfficiels.initial;
      final suivant =
          depart.apresPasse(passeComplete: false, resteIndetermine: true);
      expect(identical(depart, suivant), isFalse);
      expect(depart.tentativesAuto, 0, reason: 'l\'objet de départ est intact');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 2. SOURCE — le câblage réel de l'écran
  // ─────────────────────────────────────────────────────────────────────────
  group('S — le câblage de best_bet_screen.dart', () {
    late String src;

    setUpAll(() {
      src = _sansCommentaires(
        File('lib/screens/best_bet_screen.dart').readAsStringSync(),
      );
    });

    test('S1 — plus aucun verrou posé inconditionnellement dans le finally', () {
      // Le défaut D1 était cette forme exacte :
      //     setState(() => _resolutionOfficielleTerminee = true);
      // dans le `finally`. On refuse toute affectation de `true` LITTÉRAL.
      expect(
        src.contains('_resolutionOfficielleTerminee = true'),
        isFalse,
        reason: 'le verrou ne doit plus être posé sans condition de succès',
      );
    });

    test('S2 — le verrou dépend du succès complet ET du plafond', () {
      expect(src.contains('_etatResolution.apresPasse('), isTrue,
          reason: 'la décision doit passer par la classe testée en E1..E5');
      expect(src.contains('_etatResolution.verrouille'), isTrue);
      expect(
        RegExp(r'_resolutionOfficielleTerminee\s*=\s*succesComplet\s*\|\|')
            .hasMatch(src),
        isTrue,
        reason: 'le verrou doit rester conditionné par succesComplet',
      );
    });

    test('S3 — `succesComplet` exige la passe complète ET zéro indéterminé',
        () {
      expect(
        RegExp(r'final succesComplet\s*=\s*passeComplete\s*&&\s*!resteIndetermine')
            .hasMatch(src),
        isTrue,
      );
      expect(
        RegExp(r'var passeComplete\s*=\s*false').hasMatch(src),
        isTrue,
        reason: 'la passe n\'est déclarée complète qu\'après la boucle',
      );
      expect(
        RegExp(r'passeComplete\s*=\s*true').hasMatch(src),
        isTrue,
        reason: 'la complétion n\'est déclarée QUE hors du try de la boucle',
      );
    });

    test('S4 — D2 : la fonction de rafraîchissement a un appelant réel', () {
      expect(src.contains('Future<void> _rafraichirGainsOfficiels()'), isTrue);
      // Au moins un site d'APPEL, distinct de la déclaration.
      final appels = _occ(src, '_rafraichirGainsOfficiels');
      expect(appels.length, greaterThanOrEqualTo(2),
          reason: 'déclaration + au moins un appel : sinon D2 revient');
    });

    test('S5 — le bouton de reprise des gains est branché ET conditionné', () {
      // PIÈGE MESURÉ : une première version de cette garde cherchait la chaîne
      // « Réessayer ». Elle était VERTE AVANT la correction, parce que l'écran
      // contenait DÉJÀ un « Réessayer » — celui de l'erreur de chargement, qui
      // appelle `_charger(refresh: true)` et ne résout AUCUN gain officiel.
      // La garde ne visait donc pas la liaison réelle : elle est maintenant
      // ancrée sur la référence à la fonction, ce qui est falsifiable.
      expect(
        RegExp(r'onPressed:\s*_resolutionOfficielleLancee\s*\?\s*null\s*:\s*'
                r'_rafraichirGainsOfficiels')
            .hasMatch(src),
        isTrue,
        reason: 'le bouton doit appeler la résolution des gains, pas _charger',
      );
      expect(src.contains('autresTerminees.any(_gainIndeterminePour)'), isTrue,
          reason: 'aucun bouton inutile quand tout est établi');
      expect(
        RegExp(r'bool _gainIndeterminePour\(_BetOpp opp\)').hasMatch(src),
        isTrue,
      );
      expect(
        src.contains('if (!opp.estTerminee) return false;'),
        isTrue,
        reason: 'une course non terminée n\'est pas « indéterminée »',
      );
    });

    test('S6 — un gain DÉTERMINÉ n\'est jamais redemandé', () {
      expect(
        RegExp(r'if \(deja != null && deja.estDetermine\) continue;')
            .hasMatch(src),
        isTrue,
        reason: 'aucune requête réseau répétée sur un résultat établi',
      );
      expect(
        RegExp(r'_gainsOfficiels.removeWhere\(\(_, v\) => !v.estDetermine\)')
            .hasMatch(src),
        isTrue,
        reason: 'le rafraîchissement ne purge que les indéterminés',
      );
    });

    test('S7 — les passes concurrentes sont refusées', () {
      expect(
        RegExp(r'if \(_resolutionOfficielleLancee\) return;').hasMatch(src),
        isTrue,
      );
      expect(
        src.contains('if (_gainsOfficielsEnCours.contains(key)) continue;'),
        isTrue,
      );
    });

    test('S8 — le compteur automatique est alimenté par la classe testée', () {
      expect(src.contains('EtatResolutionGainsOfficiels.initial'), isTrue);
      expect(src.contains('apresRafraichissementManuel()'), isTrue);
    });
  });
}

// ───────────────────────────────────────────────────────────────────────────
// 3. OUTILS DE MESURE (repris de test/b1_a02_garde_structurel_consommateurs_test.dart)
// ───────────────────────────────────────────────────────────────────────────

/// Retire les commentaires `//` en respectant les chaînes de caractères.
///
/// PRÉREQUIS DE MESURE : sans ce nettoyage, S1 tombait sur le commentaire qui
/// DÉCRIT le défaut corrigé (`_resolutionOfficielleTerminee` était mis à
/// `true`) et rendait la garde aveugle en la faisant échouer à tort.
String _sansCommentaires(String src) {
  final sb = StringBuffer();
  var i = 0;
  String? quote;
  var triple = false;

  while (i < src.length) {
    final c = src[i];

    if (quote != null) {
      if (c == r'\' && i + 1 < src.length) {
        sb.write(c);
        sb.write(src[i + 1]);
        i += 2;
        continue;
      }
      if (triple) {
        if (i + 2 < src.length &&
            src[i] == quote &&
            src[i + 1] == quote &&
            src[i + 2] == quote) {
          sb.write(src.substring(i, i + 3));
          i += 3;
          quote = null;
          triple = false;
          continue;
        }
      } else if (c == quote) {
        sb.write(c);
        i++;
        quote = null;
        continue;
      }
      sb.write(c);
      i++;
      continue;
    }

    if (c == "'" || c == '"') {
      if (i + 2 < src.length && src[i + 1] == c && src[i + 2] == c) {
        sb.write(src.substring(i, i + 3));
        i += 3;
        quote = c;
        triple = true;
        continue;
      }
      quote = c;
      sb.write(c);
      i++;
      continue;
    }

    if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        i++;
      }
      continue;
    }

    sb.write(c);
    i++;
  }
  return sb.toString();
}

/// Indices de toutes les occurrences d'un motif.
List<int> _occ(String src, String motif) {
  final out = <int>[];
  var de = 0;
  while (true) {
    final i = src.indexOf(motif, de);
    if (i < 0) {
      break;
    }
    out.add(i);
    de = i + motif.length;
  }
  return out;
}
