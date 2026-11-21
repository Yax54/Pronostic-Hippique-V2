// ═══════════════════════════════════════════════════════════════════════════
//  LOT G+P — LES DEUX DIALOGUES N'INVENTENT PLUS DE MISE
//
//  OBJET : prouver que la validation manuelle d'un ticket « Gagnant + Placé »
//  ne fabrique jamais de mise, et qu'elle est REFUSÉE quand les deux mises
//  réellement engagées ne sont pas établies.
//
//  ── LE DÉFAUT CORRIGÉ (mesuré avant ce lot) ───────────────────────────────
//  `predictions_screen._validerDialog` et
//  `profile_historique_tab._validerDialog` faisaient tous deux :
//
//      double mise = pred.montantMise > 0 ? pred.montantMise : 10.0;
//
//  Pour un Gagnant+Placé (`montantMise` = 0, le champ n'étant pas passé par
//  `race_detail_screen.dart:348`) : 10 € INVENTÉS, alors que le pari engage
//  DEUX composantes enregistrées dans `miseGagnant` / `misePlace`.
//  Et `profile_historique_tab` ajoutait `mise * 1.5` quand `cote <= 1.0`,
//  soit un gain fabriqué de toutes pièces.
//
//  ── CE QUE CES TESTS PROUVENT ─────────────────────────────────────────────
//   G1  le module de décision : tous les cas de mises
//   G2  les DEUX dialogues : garde structurelle (plus de repli 10 €)
//   G3  mises distinctes : 10 + 10 = 20 € engagés, jamais 10 €
//   G4  données incomplètes : refus explicite, aucun montant exposé
//   G5  anciens tickets : aucun n'est réécrit
//   G6  non-régressions : les paris simples restent validables
//
//  ── CE QUI N'EST PAS TOUCHÉ ───────────────────────────────────────────────
//  Aucune formule financière, aucune logique de `isCorrect`, aucune garde A-0,
//  aucun apprentissage IA, aucun ticket existant, aucun test existant.
//  Le résolveur PMU n'est pas branché. C4 n'est pas traité.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/providers/pmu_provider.dart';
import 'package:pronostic_hippique/services/gain_mise_calculator.dart';
import 'package:pronostic_hippique/utils/validation_manuelle_ticket.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Fabriques
// ───────────────────────────────────────────────────────────────────────────

/// Ticket Gagnant+Placé COMPLET : les deux mises sont distinctes et connues.
/// C'est ce que produit `bet_bottom_sheet.dart:2901-2904` (B2-A) ou
/// `mes_paris_screen.dart:3097-3100`.
UserPrediction gpComplet({
  double? miseGagnant = 10.0,
  double? misePlace = 10.0,
  double montantMise = 0.0,
  double cote = 4.2,
}) =>
    UserPrediction(
      id: 'gp_complet',
      dateStr: '2026-11-15',
      numReunion: 1,
      numCourse: 6,
      nomCourse: 'Prix G+P',
      hippodrome: 'VINCENNES',
      numeroCheval: 16,
      nomCheval: 'CHEVAL 16',
      cote: cote,
      typePari: 'Gagnant+Placé',
      montantMise: montantMise,
      miseGagnant: miseGagnant,
      misePlace: misePlace,
      createdAt: DateTime(2026, 11, 15, 14, 30),
    );

/// Ticket Gagnant+Placé INCOMPLET (une seule composante, ou aucune).
UserPrediction gpIncomplet({double? miseGagnant, double? misePlace}) =>
    UserPrediction(
      id: 'gp_incomplet',
      dateStr: '2026-11-15',
      numReunion: 1,
      numCourse: 7,
      nomCourse: 'Prix G+P incomplet',
      hippodrome: 'VINCENNES',
      numeroCheval: 3,
      nomCheval: 'CHEVAL 3',
      cote: 3.0,
      typePari: 'Gagnant+Placé',
      miseGagnant: miseGagnant,
      misePlace: misePlace,
      createdAt: DateTime(2026, 11, 15, 15, 0),
    );

/// Ticket d'un pari simple mono-composante, avec une mise réelle.
UserPrediction simple({
  String typePari = 'Simple Gagnant',
  double montantMise = 10.0,
  double cote = 3.0,
}) =>
    UserPrediction(
      id: 'simple_1',
      dateStr: '2026-11-15',
      numReunion: 2,
      numCourse: 3,
      nomCourse: 'Prix Simple',
      hippodrome: 'ENGHIEN',
      numeroCheval: 7,
      nomCheval: 'CHEVAL 7',
      cote: cote,
      typePari: typePari,
      montantMise: montantMise,
      createdAt: DateTime(2026, 11, 15, 15, 30),
    );

Future<PmuProvider> providerVide() async {
  SharedPreferences.setMockInitialValues({});
  final p = PmuProvider();
  // Laisser le chargement lancé par le constructeur se terminer : son
  // `_predictions.clear()` tardif écraserait sinon un ajout immédiat.
  await Future<void>.delayed(const Duration(milliseconds: 80));
  await p.reloadPredictions();
  return p;
}

Map<String, Object?> photo(UserPrediction p) => <String, Object?>{
      'typePari': p.typePari,
      'isCorrect': p.isCorrect,
      'montantMise': p.montantMise,
      'gainRealise': p.gainRealise,
      'gainNet': p.gainNet,
      'retourTotal': p.retourTotal,
      'statutLabel': p.statutLabel,
      'miseGagnant': p.miseGagnant,
      'misePlace': p.misePlace,
      'coteGagnant': p.coteGagnant,
      'cotePlace': p.cotePlace,
      'dividendePmuReel': p.dividendePmuReel,
    };

/// Code SEUL d'un fichier Dart : lignes de commentaire retirées, commentaires
/// de fin de ligne retirés, contenus de chaînes (simples, doubles et gabarits)
/// neutralisés.
///
/// Pourquoi c'est indispensable ici : ces tests vérifient que des MOTIFS DE
/// CODE ont disparu (`: 10.0`, `mise * 1.5`) ou qu'un MOTIF existe
/// (`isCorrect`). Or la correction elle-même est expliquée en commentaire, et
/// ces explications citent forcément les motifs supprimés. Chercher dans le
/// texte brut confondrait donc « la ligne de code a été supprimée » avec
/// « le commentaire qui raconte sa suppression a été écrit ».
///
/// Ce n'est PAS un analyseur syntaxique : c'est un filtre volontairement
/// conservateur, suffisant pour distinguer code et prose sur ces fichiers.
String codeSeul(String source) {
  final buffer = StringBuffer();
  var enChaine = false;
  var echappe = false;

  for (var i = 0; i < source.length; i++) {
    final c = source[i];

    if (enChaine) {
      if (echappe) {
        echappe = false;
      } else if (c == r'\') {
        echappe = true;
      } else if (c == "'") {
        enChaine = false;
      }
      // Le contenu des chaînes n'est pas du code : on ne l'écrit pas.
      continue;
    }

    if (c == "'") {
      enChaine = true;
      continue;
    }

    // Commentaire de fin de ligne : tout sauter jusqu'au saut de ligne.
    if (c == '/' && i + 1 < source.length && source[i + 1] == '/') {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
      buffer.write('\n');
      continue;
    }

    buffer.write(c);
  }

  // Lignes d'en-tête `//` déjà retirées par la boucle ci-dessus ; on retire
  // aussi les blocs `///` de documentation, qui commencent par `//`.
  return buffer.toString();
}

/// Code SEUL des lignes qui ne sont ni `//` ni `///` : redondant avec
/// [codeSeul] pour les commentaires de ligne, mais explicite pour la lecture.
String codeSeulFichier(String chemin) =>
    codeSeul(File(chemin).readAsStringSync());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═════════════════════════════════════════════════════════════════════════
  //  G1 — MODULE DE DÉCISION
  // ═════════════════════════════════════════════════════════════════════════

  group('G1 — deciderValidationManuelle', () {
    test('G1/1 — G+P avec les deux mises : autorisé, total = 20 €', () {
      final d = deciderValidationManuelle(gpComplet());
      expect(d, isA<ValidationManuelleAutorisee>());
      final a = d as ValidationManuelleAutorisee;
      expect(a.miseTotale, 20.0,
          reason: '10 € Gagnant + 10 € Placé = 20 € engagés, jamais 10 €');
      expect(a.deuxComposantes, isTrue);
    });

    test('G1/2 — G+P avec des mises différentes : la somme réelle', () {
      final d = deciderValidationManuelle(
          gpComplet(miseGagnant: 5.0, misePlace: 20.0));
      expect((d as ValidationManuelleAutorisee).miseTotale, 25.0);
    });

    test('G1/3 — G+P sans aucune mise : REFUS, aucun montant', () {
      final d = deciderValidationManuelle(gpIncomplet());
      expect(d, isA<ValidationManuelleRefusee>());
      expect(d.autorisee, isFalse);
      // Un type non autorisé n'expose AUCUN champ de montant.
      expect(d is ValidationManuelleAutorisee, isFalse);
    });

    test('G1/4 — G+P avec la seule mise Gagnant : REFUS nommant le Placé', () {
      final d = deciderValidationManuelle(gpIncomplet(miseGagnant: 10.0))
          as ValidationManuelleRefusee;
      expect(d.motif, contains('Placé'));
      expect(d.motif, contains('inventé'));
    });

    test('G1/5 — G+P avec la seule mise Placé : REFUS nommant le Gagnant', () {
      final d = deciderValidationManuelle(gpIncomplet(misePlace: 10.0))
          as ValidationManuelleRefusee;
      expect(d.motif, contains('Gagnant'));
      expect(d.motif, contains('inventé'));
    });

    test('G1/6 — G+P avec une mise à zéro : REFUS', () {
      expect(deciderValidationManuelle(gpComplet(miseGagnant: 0.0)),
          isA<ValidationManuelleRefusee>());
      expect(deciderValidationManuelle(gpComplet(misePlace: 0.0)),
          isA<ValidationManuelleRefusee>());
    });

    test('G1/7 — G+P avec une mise négative : REFUS', () {
      expect(deciderValidationManuelle(gpComplet(miseGagnant: -5.0)),
          isA<ValidationManuelleRefusee>());
    });

    test('G1/8 — G+P : le motif ne contient AUCUN montant inventé', () {
      for (final d in <DecisionValidationManuelle>[
        deciderValidationManuelle(gpIncomplet()),
        deciderValidationManuelle(gpIncomplet(miseGagnant: 10.0)),
        deciderValidationManuelle(gpIncomplet(misePlace: 10.0)),
        deciderValidationManuelle(gpComplet(miseGagnant: 0.0)),
      ]) {
        final motif = (d as ValidationManuelleRefusee).motif;
        expect(motif.contains('10'), isFalse,
            reason: 'aucun montant ne doit apparaître dans un motif de refus');
        expect(motif.contains('20'), isFalse,
            reason: 'aucun montant ne doit apparaître dans un motif de refus');
      }
    });

    test('G1/9 — les 3 libellés G+P sont traités de la même façon', () {
      for (final libelle in <String>[
        'Gagnant+Placé',
        'Gagnant + Placé',
        'Gagnant+Place',
      ]) {
        final p = UserPrediction(
          id: 'x', dateStr: '2026-11-15', numReunion: 1, numCourse: 1,
          nomCourse: 'C', hippodrome: 'H', numeroCheval: 1, nomCheval: 'C1',
          cote: 2.0, typePari: libelle, createdAt: DateTime(2026, 11, 15),
        );
        expect(deciderValidationManuelle(p), isA<ValidationManuelleRefusee>(),
            reason: 'sans mises, $libelle doit être refusé');
      }
    });

    test('G1/10 — pari simple avec mise réelle : autorisé, mise inchangée', () {
      final d = deciderValidationManuelle(simple());
      final a = d as ValidationManuelleAutorisee;
      expect(a.miseTotale, 10.0);
      expect(a.deuxComposantes, isFalse);
    });

    test('G1/11 — pari simple SANS mise : REFUS (plus de repli à 10 €)', () {
      final d = deciderValidationManuelle(simple(montantMise: 0.0));
      expect(d, isA<ValidationManuelleRefusee>());
      expect((d as ValidationManuelleRefusee).motif, contains('Aucune mise'));
    });

    test('G1/12 — la décision est PURE et déterministe', () {
      final p = gpComplet();
      final avant = p.toJson();
      for (var i = 0; i < 5; i++) {
        final d = deciderValidationManuelle(p) as ValidationManuelleAutorisee;
        expect(d.miseTotale, 20.0);
      }
      expect(p.toJson(), equals(avant),
          reason: 'aucune écriture sur le ticket');
    });

    test('G1/13 — réutilisation du calculateur B : même total que lui', () {
      // Le module ne recalcule rien : il délègue. On vérifie que la valeur
      // rendue est exactement celle de `miseTotaleEngagee` (calculateur B).
      final comp = composantesDepuisTicket(
        estGagnantPlace: true,
        miseEngagee: 0.0,
        miseGagnant: 10.0,
        misePlace: 10.0,
        rapport: null,
      );
      expect(miseTotaleEngagee(comp), 20.0);
      expect(
        (deciderValidationManuelle(gpComplet()) as ValidationManuelleAutorisee)
            .miseTotale,
        20.0,
      );
    });

    test('G1/14 — le module n\'invente aucun dividende ni résultat', () {
      final source = codeSeulFichier('lib/utils/validation_manuelle_ticket.dart');
      // Aucune des méthodes qui écrivent un résultat financier n'est appelée.
      expect(source.contains('enregistrerDividendePmu'), isFalse);
      expect(source.contains('validatePrediction'), isFalse);
      expect(source.contains('dividendePmuReel'), isFalse,
          reason: 'le module ne lit aucun dividende');
      expect(source.contains('isCorrect'), isFalse,
          reason: 'le module ne décide ni gagnant ni perdant');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  G2 — LES DEUX DIALOGUES (garde structurelle)
  // ═════════════════════════════════════════════════════════════════════════

  group('G2 — les deux dialogues n\'inventent plus de mise', () {
    const fichiers = <String>[
      'lib/screens/predictions_screen.dart',
      'lib/widgets/profile/profile_historique_tab.dart',
    ];

    test('G2/1 — le repli « : 10.0 » a disparu des deux dialogues', () {
      // On cherche dans le CODE, pas dans les commentaires qui racontent la
      // correction (ils citent forcément l'ancienne formule).
      for (final f in fichiers) {
        final s = codeSeulFichier(f);
        expect(s.contains('montantMise > 0 ? pred.montantMise : 10.0'), isFalse,
            reason: '$f ne doit plus contenir le repli de 10 €');
        expect(s.contains(': 10.0'), isFalse,
            reason: '$f ne doit plus contenir de repli « : 10.0 »');
      }
    });

    test('G2/2 — les deux dialogues appellent le module de décision', () {
      for (final f in fichiers) {
        final s = File(f).readAsStringSync();
        expect(s.contains('deciderValidationManuelle(pred)'), isTrue,
            reason: '$f doit déléguer la décision');
        expect(s.contains('ValidationManuelleAutorisee'), isTrue, reason: f);
        expect(s.contains('ValidationManuelleRefusee'), isTrue, reason: f);
      }
    });

    test('G2/3 — un motif explicite est affiché en cas de refus', () {
      for (final f in fichiers) {
        // Texte brut ici : on vérifie bien la présence d'un LITTÉRAL affiché.
        final s = File(f).readAsStringSync();
        expect(s.contains('_afficherValidationRefusee'), isTrue, reason: f);
        expect(s.contains('Validation impossible'), isTrue, reason: f);
        // ⚠️ Le source contient `Rien n\'a été enregistré` : l'apostrophe y est
        //    échappée pour Dart. Un `contains("Rien n'a …")` en Dart ne
        //    matcherait donc jamais (mesuré : 0 occurrence des deux formes).
        //    On cherche la forme réellement écrite dans le fichier.
        expect(s.contains(r"Rien n\'a été enregistré"), isTrue,
            reason: '$f doit afficher explicitement qu\'aucune écriture '
                'n\'a eu lieu');
        expect(s.contains('Aucun montant'), isTrue, reason: f);
      }
    });

    test('G2/4 — le gain de repli `mise * 1.5` a disparu', () {
      // Code seul : l'explication de la suppression cite évidemment le motif.
      final s = codeSeulFichier('lib/widgets/profile/profile_historique_tab.dart');
      expect(s.contains('mise * 1.5'), isFalse,
          reason: 'le gain fabriqué quand cote <= 1.0 doit avoir disparu');
    });

    test('G2/5 — la garde C1 (aucun pari recommandé) reste en place', () {
      // Non-régression du lot précédent, dans les DEUX fichiers.
      for (final f in fichiers) {
        final s = codeSeulFichier(f);
        expect(s.contains('estEtatSansPariRecommande(pred.typePari)'), isTrue,
            reason: f);
        final idxGarde = s.indexOf('estEtatSansPariRecommande(pred.typePari)');
        final idxDecision = s.indexOf('deciderValidationManuelle(pred)');
        expect(idxGarde, lessThan(idxDecision),
            reason: 'la garde C1 doit rester AVANT la décision G+P dans $f');
      }
    });

    test('G2/6 — les deux dialogues affichent la ventilation des mises', () {
      for (final f in fichiers) {
        final s = File(f).readAsStringSync();
        expect(s.contains('Gagnant + Placé : '), isTrue, reason: f);
        expect(s.contains('engagés'), isTrue, reason: f);
        expect(s.contains('pred.miseGagnant!'), isTrue, reason: f);
        expect(s.contains('pred.misePlace!'), isTrue, reason: f);
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  G3 — MISES DISTINCTES : validation bout en bout via le provider
  // ═════════════════════════════════════════════════════════════════════════

  group('G3 — mises distinctes : 20 € engagés, jamais 10 €', () {
    test('G3/1 — validation G+P : mise par composante préservée, aucun gain écrit',
        () async {
      final provider = await providerVide();
      provider.addPrediction(gpComplet());

      final d = deciderValidationManuelle(provider.predictions.first)
          as ValidationManuelleAutorisee;
      expect(d.miseTotale, 20.0);

      // Ce que fait le dialogue « Gagné » : il transmet le RÉSULTAT SPORTIF,
      // et aucun montant (ni mise, ni gain) pour un G+P.
      provider.validatePrediction(
        'gp_complet',
        isCorrect: true,
        montantMise: null,
        gainRealise: null,
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final p = provider.predictions.first;
      expect(p.isCorrect, isTrue, reason: 'le résultat sportif est enregistré');

      // ★ CONTRAT B2-A : pour un G+P, `montantMise` porte la mise PAR
      //   COMPOSANTE (10 €), et `miseTotaleEngagee` vaut `montantMise × 2`.
      //   Écrire la somme (20 €) dans `montantMise` ferait afficher 40 €.
      expect(p.montantMise, 0.0,
          reason: 'mise par composante préservée (ici non renseignée)');
      expect(p.miseGagnant, 10.0, reason: 'composante Gagnant intacte');
      expect(p.misePlace, 10.0, reason: 'composante Placé intacte');
      expect(p.miseTotaleEngagee, 20.0,
          reason: 'la mise réellement engagée reste lisible : 10 + 10 = 20 €');

      // ★ Point 6 : aucun gain n'est déduit d'une cote Gagnant seule.
      expect(p.gainRealise, isNull,
          reason: 'aucun gain déduit d\'un dividende ambigu');
      expect(p.gainNet, 0.0,
          reason: 'gainRealise null ⇒ gainNet neutre (aucun montant fabriqué)');
    });

    test('G3/1b — validatePrediction n\'invente plus de gain depuis la cote '
        'pour un G+P', () async {
      // Ticket G+P historique dont `montantMise` porte une mise par composante.
      final historique = UserPrediction(
        id: 'gp_cote',
        dateStr: '2026-11-15',
        numReunion: 1,
        numCourse: 6,
        nomCourse: 'Prix G+P',
        hippodrome: 'VINCENNES',
        numeroCheval: 16,
        nomCheval: 'CHEVAL 16',
        cote: 4.2,
        typePari: 'Gagnant+Placé',
        montantMise: 10.0,
        miseGagnant: 10.0,
        misePlace: 10.0,
        createdAt: DateTime(2026, 11, 15, 14, 30),
      );
      final provider = await providerVide();
      provider.addPrediction(historique);

      provider.validatePrediction('gp_cote', isCorrect: true);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final p = provider.predictions.first;
      expect(p.isCorrect, isTrue);
      // Sans la garde ajoutée, le provider calculait (4.2 × 10) − 10 = 32.0 €
      // à partir de la SEULE cote Gagnant : un gain G+P fictif.
      expect(p.gainRealise, isNull,
          reason: 'aucun gain G+P calculé depuis la cote Gagnant seule');

      // ⚠️ RÉSIDUEL MESURÉ, HORS PÉRIMÈTRE DE CE LOT : la formule `gainNet`
      //    de `pmu_models.dart` applique encore la cote au `montantMise` quand
      //    `isCorrect == true`. Elle est une FORMULE FINANCIÈRE protégée par
      //    le mandat et n'est pas modifiée ici. On la mesure pour ne pas la
      //    dissimuler.
      expect(p.gainNet, closeTo((4.2 * 10.0) - 10.0, 1e-9),
          reason: 'résiduel mesuré, non corrigé : `gainNet` applique la cote '
              'au montantMise ; aucune formule financière n\'est touchée ici');
    });

    test('G3/2 — perte G+P : la mise engagée des DEUX composantes est comptée',
        () async {
      final provider = await providerVide();
      provider.addPrediction(gpComplet(miseGagnant: 5.0, misePlace: 15.0));
      final d = deciderValidationManuelle(provider.predictions.first)
          as ValidationManuelleAutorisee;

      // Dialogue « Perdu » : `gainRealise` explicite = −(mise totale affichée).
      provider.validatePrediction('gp_complet',
          isCorrect: false, montantMise: null, gainRealise: -d.miseTotale);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final p = provider.predictions.first;
      expect(p.isCorrect, isFalse);
      expect(p.gainRealise, -20.0,
          reason: 'la perte est la mise totale : 5 + 15 = 20 €, jamais 10 €');
      expect(p.gainNet, -20.0);
    });

    test('G3/3 — miseTotaleEngagee du modèle reste cohérente', () {
      // Le getter dérivé existant n'est pas modifié par ce lot.
      expect(gpComplet().miseTotaleEngagee, 20.0);
      expect(gpIncomplet(miseGagnant: 10.0).miseTotaleEngagee, isNull,
          reason: 'état incomplet ⇒ null, jamais une valeur inventée');
      expect(gpIncomplet(miseGagnant: 10.0).misesGagnantPlaceIncompletes, isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  G4 — DONNÉES INCOMPLÈTES : refus sans écriture
  // ═════════════════════════════════════════════════════════════════════════

  group('G4 — données incomplètes : rien n\'est écrit', () {
    test('G4/1 — G+P incomplet : la décision refuse, le ticket reste intact',
        () async {
      final provider = await providerVide();
      provider.addPrediction(gpIncomplet(miseGagnant: 10.0));

      final d = deciderValidationManuelle(provider.predictions.first);
      expect(d, isA<ValidationManuelleRefusee>());

      // Le dialogue n'appelle alors PAS validatePrediction. On vérifie donc
      // que le ticket n'a subi AUCUNE écriture, et qu'il reste « En attente ».
      final p = provider.predictions.first;
      expect(p.isCorrect, isNull);
      expect(p.montantMise, 0.0);
      expect(p.gainRealise, isNull);
      expect(p.statutLabel, 'En attente');
      expect(p.miseGagnant, 10.0, reason: 'la composante connue est préservée');
      expect(p.misePlace, isNull, reason: 'la composante absente reste absente');
    });

    test('G4/2 — G+P sans mises : aucun montant ne peut être exposé', () {
      final d = deciderValidationManuelle(gpIncomplet());
      expect(d, isA<ValidationManuelleRefusee>());
      // Le type scellé garantit l'absence de champ montant côté refus.
      expect(d.autorisee, isFalse);
    });

    test('G4/3 — un ticket simple sans mise ne reçoit pas 10 €', () {
      final d = deciderValidationManuelle(simple(montantMise: 0.0));
      expect(d, isA<ValidationManuelleRefusee>());
    });

    test('G4/4 — refus : photo du ticket identique avant / après', () async {
      final provider = await providerVide();
      provider.addPrediction(gpIncomplet(misePlace: 20.0));
      final avant = photo(provider.predictions.first);

      final d = deciderValidationManuelle(provider.predictions.first);
      expect(d, isA<ValidationManuelleRefusee>());
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(photo(provider.predictions.first), equals(avant));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  G5 — ANCIENS TICKETS : aucune réécriture
  // ═════════════════════════════════════════════════════════════════════════

  group('G5 — anciens tickets préservés', () {
    test('G5/1 — un G+P historique sans mises reste lisible et intact', () {
      // Ticket d'avant B2-A : les 4 champs n'existaient pas.
      final json = <String, dynamic>{
        'id': 'ancien_gp',
        'dateStr': '2024-03-12',
        'numReunion': 3,
        'numCourse': 2,
        'nomCourse': 'Ancienne course',
        'hippodrome': 'CAEN',
        'numeroCheval': 4,
        'nomCheval': 'CHEVAL 4',
        'cote': 5.0,
        'typePari': 'Gagnant+Placé',
        'createdAt': DateTime(2024, 3, 12).toIso8601String(),
      };
      final p = UserPrediction.fromJson(json);
      expect(p.typePari, 'Gagnant+Placé', reason: 'type jamais réécrit');
      expect(p.miseGagnant, isNull, reason: 'champ absent reste null');
      expect(p.misePlace, isNull);
      expect(p.montantMise, 0.0);
      expect(deciderValidationManuelle(p), isA<ValidationManuelleRefusee>(),
          reason: 'un ancien ticket incomplet est REFUSÉ, pas complété');
    });

    test('G5/2 — la sérialisation d\'un ancien ticket est inchangée', () {
      final json = <String, dynamic>{
        'id': 'ancien_gp2',
        'dateStr': '2024-05-01',
        'numReunion': 1,
        'numCourse': 1,
        'nomCourse': 'C',
        'hippodrome': 'H',
        'numeroCheval': 1,
        'nomCheval': 'C1',
        'cote': 2.0,
        'typePari': 'Gagnant+Placé',
        'createdAt': DateTime(2024, 5, 1).toIso8601String(),
      };
      final p = UserPrediction.fromJson(json);
      final avant = jsonEncode(p.toJson());
      // Une décision de refus ne modifie rien.
      deciderValidationManuelle(p);
      expect(jsonEncode(p.toJson()), equals(avant));
    });

    test('G5/3 — un ancien ticket G+P déjà résolu n\'est JAMAIS réécrit par le '
        'dialogue', () async {
      // Ticket d'avant ce lot, déjà résolu et déjà soldé.
      final ancien = UserPrediction(
        id: 'ancien_resolu',
        dateStr: '2024-01-10',
        numReunion: 5,
        numCourse: 4,
        nomCourse: 'Déjà résolu',
        hippodrome: 'VINCENNES',
        numeroCheval: 8,
        nomCheval: 'CHEVAL 8',
        cote: 6.0,
        typePari: 'Gagnant+Placé',
        isCorrect: true,
        montantMise: 20.0,
        gainRealise: 35.0,
        createdAt: DateTime(2024, 1, 10),
      );
      final provider = await providerVide();
      provider.addPrediction(ancien);
      final avant = photo(provider.predictions.first);

      // ★ La protection réelle est en amont, dans les DEUX dialogues et dans
      //   leur garde d'accès : `isCorrect != null` ⇒ le bouton « Valider »
      //   n'existe pas et `_validerDialog` n'est jamais atteint.
      final lib = codeSeulFichier('lib/screens/predictions_screen.dart');
      expect(lib.contains('if (pred.isCorrect == null &&'), isTrue,
          reason: 'un ticket déjà résolu n\'offre aucun bouton de validation');
      final prof =
          codeSeulFichier('lib/widgets/profile/profile_historique_tab.dart');
      expect(prof.contains('if (isCorrect == null &&'), isTrue, reason: prof);

      // ★ MESURÉ, NON MASQUÉ : `validatePrediction` n'a AUCUNE garde sur un
      //   ticket déjà résolu. Si on l'appelait par un autre chemin, l'ancien
      //   ticket serait réécrit. Ce constat dépasse ce lot (ce serait une
      //   nouvelle garantie sur une méthode partagée par 5 appelants) : on le
      //   mesure ici plutôt que de l'affirmer corrigé.
      provider.validatePrediction('ancien_resolu',
          isCorrect: false, montantMise: 99.0, gainRealise: -99.0);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(photo(provider.predictions.first), isNot(equals(avant)),
          reason: 'témoin du résiduel : la méthode n\'est pas protégée, '
              'seuls les dialogues le sont');
    });

    test('G5/4 — aucun ticket n\'est supprimé', () async {
      final provider = await providerVide();
      provider.addPrediction(gpComplet());
      provider.addPrediction(gpIncomplet());
      provider.addPrediction(simple());
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(provider.predictions.length, 3);

      for (final id in <String>['gp_complet', 'gp_incomplet', 'simple_1']) {
        deciderValidationManuelle(
            provider.predictions.firstWhere((p) => p.id == id));
      }
      expect(provider.predictions.length, 3, reason: 'aucune suppression');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  G6 — NON-RÉGRESSIONS
  // ═════════════════════════════════════════════════════════════════════════

  group('G6 — non-régressions', () {
    test('G6/1 — un pari simple reste validable avec sa mise réelle', () async {
      final provider = await providerVide();
      provider.addPrediction(simple());
      final d = deciderValidationManuelle(provider.predictions.first)
          as ValidationManuelleAutorisee;
      provider.validatePrediction('simple_1',
          isCorrect: true, montantMise: d.miseTotale, gainRealise: 20.0);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final p = provider.predictions.first;
      expect(p.isCorrect, isTrue);
      expect(p.montantMise, 10.0);
      expect(p.gainRealise, 20.0);
      expect(p.gainNet, 20.0);
    });

    test('G6/2 — le ticket G+P conserve ses deux composantes après validation',
        () async {
      final provider = await providerVide();
      provider.addPrediction(gpComplet(miseGagnant: 7.0, misePlace: 13.0));
      final d = deciderValidationManuelle(provider.predictions.first)
          as ValidationManuelleAutorisee;
      provider.validatePrediction('gp_complet',
          isCorrect: true, montantMise: d.miseTotale);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final p = provider.predictions.first;
      expect(p.miseGagnant, 7.0);
      expect(p.misePlace, 13.0);
      expect(p.montantMise, 20.0);
    });

    test('G6/3 — la garde A-0 n\'a pas été modifiée', () {
      final s = File('lib/utils/type_pari_utils.dart').readAsStringSync();
      expect(s.contains('const Set<String> kLibellesGagnantPlace'), isTrue);
      expect(s.contains('bool estTypeGagnantPlace(String? typePari)'), isTrue);
      expect(s.contains('bool estEtatSansPariRecommande(String? typePari)'),
          isTrue);

      // A-0 reste l'autorité : le module G+P l'utilise, il ne la redéfinit pas.
      final m = codeSeulFichier('lib/utils/validation_manuelle_ticket.dart');
      expect(m.contains('kLibellesGagnantPlace'), isFalse,
          reason: 'aucune redéfinition locale de la liste A-0');
      expect(m.contains('estTypeGagnantPlace(pred.typePari)'), isTrue);

      // Le provider consomme A-0 au lieu de retester les libellés à la main.
      final prov = codeSeulFichier('lib/providers/pmu_provider.dart');
      expect(prov.contains('estTypeGagnantPlace(old.typePari)'), isTrue,
          reason: 'validatePrediction doit déléguer la reconnaissance à A-0');
    });

    test('G6/4 — aucune formule financière modifiée', () {
      final s = File('lib/models/pmu_models.dart').readAsStringSync();
      expect(s.contains('if (gainRealise != null) return gainRealise!;'), isTrue);
      expect(
          s.contains('if (isCorrect == false && montantMise > 0) return -montantMise;'),
          isTrue);
      expect(s.contains('return (dividendePmuReel! * montantMise) - montantMise;'),
          isTrue);
      expect(s.contains('return (cote * montantMise) - montantMise;'), isTrue);
      // Le getter dérivé B1/B2-A est intact.
      expect(s.contains('double? get miseTotaleEngagee'), isTrue);
      expect(s.contains('bool get misesGagnantPlaceIncompletes'), isTrue);
    });

    test('G6/5 — le calculateur B n\'a pas été modifié', () {
      final s = File('lib/services/gain_mise_calculator.dart').readAsStringSync();
      expect(s.contains('double? miseTotaleEngagee(List<ComposanteMise> composantes)'),
          isTrue);
      expect(s.contains('List<ComposanteMise> composantesDepuisTicket('), isTrue);
      expect(s.contains('ResultatGain calculerGain({'), isTrue);
      expect(s.contains('ResultatGain calculerGainPotentiel({'), isTrue);
    });

    test('G6/6 — le résolveur PMU n\'est pas branché', () {
      for (final f in <String>[
        'lib/screens/predictions_screen.dart',
        'lib/widgets/profile/profile_historique_tab.dart',
        'lib/utils/validation_manuelle_ticket.dart',
      ]) {
        final s = File(f).readAsStringSync();
        expect(s.contains('resolveur_rapport_pmu'), isFalse, reason: f);
        expect(s.contains('resoudreRapportPmu'), isFalse, reason: f);
      }
    });
    test('G6/7 — C4 n\'est pas traité : profile_screen.dart intact', () {
      final s = File('lib/screens/profile_screen.dart').readAsStringSync();
      expect(s.contains('final taux = allFiltered.isNotEmpty ? (nbGagnes / allFiltered.length) * 100 : 0.0;'),
          isTrue,
          reason: 'C4 est hors périmètre : le dénominateur n\'est pas modifié');
    });

    test('G6/8 — la règle T8a n\'a pas été touchée', () {
      final s = File('lib/services/ia_memory_service.dart').readAsStringSync();
      expect(s.contains('if (isCorrect == null) continue;'), isTrue);
    });
  });
}
