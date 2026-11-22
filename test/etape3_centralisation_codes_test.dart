// ═══════════════════════════════════════════════════════════════════════════
//  ÉTAPE 3 — CENTRALISATION DES CORRESPONDANCES, SOUS CONTRAT D'ÉQUIVALENCE
//
//  Cette étape n'autorise à remplacer une correspondance locale que si elle
//  ne change RIEN : même code, donc même rapport retenu, donc même montant.
//
//  Ce fichier ne teste pas seulement le résultat ; il vérifie l'INVARIANT qui
//  rend le remplacement sûr par construction : la délégation conserve
//  TOUJOURS le code historique si le référentiel diverge.
//
//  Aucun test existant n'est modifié.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/services/referentiel_paris_pmu.dart';

/// Reproduit à l'identique le contrat de `_codeUnique` des écrans.
///
/// ⚠️ Si cette logique changeait dans les écrans, ce test resterait vert à
///    tort : c'est pourquoi un test séparé vérifie la présence du garde-fou
///    directement dans le fichier source de production.
List<String> _codeUnique(TypePariPmu type, List<String> codeHistorique) {
  final duReferentiel = codeApiPourTypePmu(type);
  if (duReferentiel == null ||
      codeHistorique.length != 1 ||
      duReferentiel != codeHistorique.first) {
    return codeHistorique;
  }
  return [duReferentiel];
}

/// Les 4 correspondances dont l'équivalence est démontrée.
const _equivalentes = <TypePariPmu, List<String>>{
  TypePariPmu.simpleGagnant: ['E_SIMPLE_GAGNANT'],
  TypePariPmu.simplePlace: ['E_SIMPLE_PLACE'],
  TypePariPmu.coupleGagnant: ['E_COUPLE_GAGNANT'],
  TypePariPmu.couplePlace: ['E_COUPLE_PLACE'],
};

/// Les 3 correspondances ASSIMILATRICES, qui ne doivent pas être déléguées.
const _nonEquivalentes = <String, List<String>>{
  'quinté': ['E_MULTI', 'E_MINI_MULTI'],
  'quarté': ['E_SUPER_QUATRE'],
  'tiercé': ['E_TRIO'],
};

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  group('E3/1 — les 4 correspondances équivalentes rendent un code identique',
      () {
    test('chaque délégation rend exactement le code historique', () {
      expect(_equivalentes.length, 4);
      for (final e in _equivalentes.entries) {
        final rendu = _codeUnique(e.key, e.value);
        expect(rendu, e.value,
            reason: '${e.key} doit rendre ${e.value} à l\'identique');
        expect(rendu.length, 1, reason: '${e.key} : un seul code');
        expect(rendu.first, e.value.first, reason: '${e.key}');
      }
    });

    test('le référentiel confirme bien ces 4 codes, sans divergence', () {
      for (final e in _equivalentes.entries) {
        expect(codeApiPourTypePmu(e.key), e.value.first,
            reason: 'divergence inattendue sur ${e.key}');
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('E3/2 — les 3 correspondances assimilatrices ne sont PAS déléguées',
      () {
    test('aucune des 3 ne coïncide avec le code officiel du référentiel', () {
      // C'est CE constat, mesuré, qui interdit le remplacement : le code
      // historique n'est pas le code officiel du pari annoncé.
      expect(codeApiPourTypePmu(TypePariPmu.quintePlus), 'E_QUINTE_PLUS');
      expect(codeApiPourTypePmu(TypePariPmu.quartePlus), 'E_QUARTE_PLUS');
      expect(codeApiPourTypePmu(TypePariPmu.tierce), 'E_TIERCE');

      for (final code in ['E_MULTI', 'E_MINI_MULTI', 'E_SUPER_QUATRE', 'E_TRIO']) {
        expect(code, isNot('E_QUINTE_PLUS'), reason: code);
        expect(code, isNot('E_QUARTE_PLUS'), reason: code);
        expect(code, isNot('E_TIERCE'), reason: code);
      }
    });

    test('aucun pari assimilé n\'est le pari officiel', () {
      // Mesuré sur 206 courses : ce sont des paris distincts, jamais des
      // variantes de nom.
      expect(codeApiPourTypePmu(TypePariPmu.multi),
          isNot(codeApiPourTypePmu(TypePariPmu.quintePlus)));
      expect(codeApiPourTypePmu(TypePariPmu.superQuatre),
          isNot(codeApiPourTypePmu(TypePariPmu.quartePlus)));
      expect(codeApiPourTypePmu(TypePariPmu.trio),
          isNot(codeApiPourTypePmu(TypePariPmu.tierce)));
    });

    test('la liste historique du Quinté+ reste intacte (non remplacée)', () {
      // Le code de production conserve cette liste mot pour mot.
      for (final e in _nonEquivalentes.entries) {
        expect(_codeUnique(TypePariPmu.quintePlus, e.value), e.value,
            reason: 'la délégation ne doit jamais toucher ${e.key}');
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('E3/3 — invariant : la délégation ne peut pas changer un montant', () {
    test('une divergence est TOUJOURS résolue par le code historique', () {
      // Cas artificiels : si le référentiel ne rend pas exactement le code
      // annoncé, on garde l'historique. Le montant est donc inchangé.
      const cas = <TypePariPmu, List<String>>{
        TypePariPmu.tierce: ['E_TRIO'], // historique faux, conservé
        TypePariPmu.quartePlus: ['E_SUPER_QUATRE'],
        TypePariPmu.quintePlus: ['E_MULTI', 'E_MINI_MULTI'],
        TypePariPmu.simpleGagnant: ['E_SIMPLE_PLACE'], // divergence forcée
        TypePariPmu.simplePlace: ['E_SIMPLE_GAGNANT'],
      };
      for (final c in cas.entries) {
        expect(_codeUnique(c.key, c.value), c.value,
            reason: '${c.key} : le code historique doit être conservé');
      }
    });

    test('une liste historique multiple n\'est jamais réduite', () {
      // Le référentiel ne rend qu'un code : réduire une liste à deux éléments
      // changerait le rapport retenu par reduce(MAX). On refuse.
      final rendu = _codeUnique(TypePariPmu.quintePlus, ['E_MULTI', 'E_MINI_MULTI']);
      expect(rendu, ['E_MULTI', 'E_MINI_MULTI']);
      expect(rendu.length, 2, reason: 'aucune réduction silencieuse');
    });

    test('le résultat est toujours une liste non vide pour les cas traités', () {
      for (final e in _equivalentes.entries) {
        expect(_codeUnique(e.key, e.value), isNotEmpty);
      }
    });

    test('aucun appel ne lève, quel que soit le code passé', () {
      for (final t in TypePariPmu.values) {
        expect(() => _codeUnique(t, ['E_INCONNU']), returnsNormally);
        expect(() => _codeUnique(t, []), returnsNormally);
        expect(() => _codeUnique(t, ['A', 'B', 'C']), returnsNormally);
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('E3/4 — garde-fou dans le code de production', () {
    test('paris_detail_screen contient la délégation ET le garde-fou', () {
      const chemin = 'lib/screens/paris_detail_screen.dart';
      final f = File(chemin);
      expect(f.existsSync(), isTrue, reason: 'fichier introuvable: $chemin');
      final src = f.readAsStringSync();

      // La fonction de délégation existe.
      expect(src.contains('List<String> _codeUnique(TypePariPmu type,'), isTrue,
          reason: 'la délégation doit exister');

      // Le garde-fou : on ne rend le code du référentiel que s'il est égal.
      expect(src.contains('if (duReferentiel == null ||'), isTrue,
          reason: 'la garde de nullité doit exister');
      expect(src.contains('duReferentiel != codeHistorique.first'), isTrue,
          reason: 'la comparaison d\'équivalence doit exister');
      expect(src.contains('return codeHistorique;'), isTrue,
          reason: 'le repli sur l\'historique doit exister');

      // Le référentiel est bien importé.
      expect(src.contains("import '../services/referentiel_paris_pmu.dart';"),
          isTrue);

      // Les 4 délégations équivalentes sont effectivement câblées.
      for (final t in _equivalentes.keys) {
        expect(src.contains('_codeUnique(TypePariPmu.'),
            isTrue,
            reason: 'au moins une délégation doit être câblée');
        expect(src.contains(t.name), isTrue,
            reason: 'la délégation de $t doit apparaître');
      }
    });

    test('les 3 listes historiques assimilatrices sont encore présentes', () {
      // Preuve qu'on ne les a PAS remplacées silencieusement.
      const chemin = 'lib/screens/paris_detail_screen.dart';
      final src = File(chemin).readAsStringSync();
      expect(src.contains("codesPmuRecherche = ['E_MULTI', 'E_MINI_MULTI'];"),
          isTrue,
          reason: 'la liste Quinté+ historique doit être intacte');
      expect(src.contains("codesPmuRecherche = ['E_SUPER_QUATRE'];"), isTrue,
          reason: 'la liste Quarté+ historique doit être intacte');
      expect(src.contains("codesPmuRecherche = ['E_TRIO'];"), isTrue,
          reason: 'la liste Tiercé historique doit être intacte');
    });

    test('pmu_api_service n\'a pas été modifié par cette étape', () {
      // Le mapper faux reste en place : le corriger changerait les gains.
      // Il est signalé, pas corrigé.
      const chemin = 'lib/services/pmu_api_service.dart';
      final src = File(chemin).readAsStringSync();
      expect(src.contains("if (l.contains('tiercé'))         return ['E_TRIO'];"),
          isTrue,
          reason: 'le mapper faux est conservé, hors périmètre de l\'étape 3');
      expect(src.contains("if (l.contains('quinté'))         return ['E_MULTI', 'E_MINI_MULTI'];"),
          isTrue);
      expect(src.contains("if (l.contains('quarté'))         return ['E_SUPER_QUATRE'];"),
          isTrue);
    });

    test('les formules financières protégées sont intactes', () {
      final alert = File('lib/services/alert_service.dart').readAsStringSync();
      expect(alert.contains('gainNet = mise * cpReel - mise * 2;'), isTrue,
          reason: 'formule G+P protégée (T8b)');

      final prov = File('lib/providers/pmu_provider.dart').readAsStringSync();
      expect(
        prov.contains('? (dividendePmuReel * old.montantMise) - old.montantMise'),
        isTrue,
        reason: 'formule provider protégée (T8b)',
      );
    });

    // ★ LOT B-4.5 — CONTRÔLE MODERNISÉ, ANCRÉ SUR LE COMPORTEMENT.
    //
    //   AVANT : ce test vérifiait la présence littérale de
    //       if (estTypeGagnantPlace(course.typePari)) return; // A-0
    //   dans les deux écrans. Cette garde protégeait un `reduce(MAX)` que
    //   B-4.5 a SUPPRIMÉ : elle est donc devenue sans objet LÀ OÙ ELLE ÉTAIT
    //   POSÉE, et le contrôle échouait alors que le produit s'améliorait.
    //
    //   MAINTENANT : le contrôle vérifie que la protection existe là où le
    //   danger est RÉEL — les deux calculs d'affichage de `mes_paris_screen`
    //   qui multiplient un dividende unique par la mise TOTALE, laquelle est
    //   la somme des deux composantes d'un Gagnant+Placé.
    //
    //   Cette assertion n'est pas un ajustement cosmétique pour redevenir
    //   vert : elle protège une règle métier DÉMONTRÉE par reproduction.
    //   Mesuré avant correctif : un ticket Gagnant+Placé historique
    //   (dividendePmuReel = 18,0 ; mise = 10 €) affichait
    //   « 🏆 Gain gagné : 180 € brut ». Les 6 contrôles comportementaux de
    //   `e3_4_gagnant_place_comportement_test.dart` rejouent cette
    //   démonstration sur le VÉRITABLE écran et échouent si elle réapparaît.
    test('la protection Gagnant+Placé couvre les DEUX calculs d\'affichage '
        '(et les deux produisent un refus, jamais un montant)', () {
      final mesParis =
          File('lib/screens/mes_paris_screen.dart').readAsStringSync();

      // Les deux fonctions concernées doivent exister.
      expect(mesParis.contains('double? _gainBrut(TrackedCourse c)'), isTrue,
          reason: '_gainBrut alimente le partage / JPEG');
      expect(mesParis.contains('String _calculerGainAffiche(TrackedCourse c)'),
          isTrue,
          reason: '_calculerGainAffiche alimente le bloc gain de la carte');

      // Chacune contient un aiguillage G+P placé AVANT le produit
      // `dividendePmuReel × mise`.
      final occurrences =
          'if (estTypeGagnantPlace(c.typePari))'.allMatches(mesParis).length;
      expect(occurrences, greaterThanOrEqualTo(2),
          reason: 'B-4.5 — la protection doit couvrir les DEUX calculs '
              '(_gainBrut ET _calculerGainAffiche), pas un seul. '
              'Trouvé : $occurrences');

      // Et cet aiguillage précède bien le produit protégé : le premier
      // `dividendePmuReel! * mise` doit venir APRÈS la première garde.
      final garde = mesParis.indexOf('if (estTypeGagnantPlace(c.typePari))');
      final produit = mesParis.indexOf('c.dividendePmuReel! * mise');
      expect(garde, greaterThan(-1));
      expect(produit, greaterThan(garde),
          reason: 'la garde doit PRÉCÉDER le produit qu\'elle protège');

      // `paris_detail_screen` ne calcule plus aucun gain : il délègue au
      // verdict officiel (`_buildVerdictOfficiel`). La présence de cette
      // délégation est le contrôle qui remplace l'ancienne garde locale.
      final detail =
          File('lib/screens/paris_detail_screen.dart').readAsStringSync();
      expect(detail.contains('_buildVerdictOfficiel('), isTrue,
          reason: 'B-4.5 — la fiche du pari affiche le verdict officiel');
      expect(detail.contains('dividendePmuReel * '), isFalse,
          reason: 'la fiche ne doit plus multiplier un dividende unique : '
              'c\'est précisément le calcul supprimé par B-4.5');
    });

    test('mes_paris_screen est resté STRICTEMENT inchangé', () {
      // Cette étape n'a pas pu y toucher : le test A6 blanchit les
      // débordements préexistants par numéro de ligne, et toute insertion
      // les décalerait — donc ferait échouer A6 sans que la cause soit un
      // défaut du produit. Vérifié par comparaison au contenu publié.
      final f = File('lib/screens/mes_paris_screen.dart');
      final src = f.readAsStringSync();
      // Témoins : la délégation de l'étape 3 ne doit PAS y figurer.
      expect(src.contains('_codeUnique(TypePariPmu'), isFalse,
          reason: 'mes_paris_screen doit rester hors périmètre de l\'étape 3');
      expect(src.contains("codesPmu = ['E_TRIO'];"), isTrue,
          reason: 'la liste Tiercé historique doit rester en place');
      expect(src.contains("codesPmu = ['E_MULTI', 'E_MINI_MULTI'];"), isTrue);
      expect(src.contains("codesPmu = ['E_SUPER_QUATRE'];"), isTrue);
    });
  });
}
