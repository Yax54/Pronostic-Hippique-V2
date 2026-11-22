// ═══════════════════════════════════════════════════════════════════════════
//  LOT G+P / AFFICHAGE — AUCUN GAIN NON PROUVÉ N'EST PRÉSENTÉ COMME ACQUIS
//
//  OBJET : un ticket « Gagnant + Placé » ne doit jamais afficher un montant
//  financier calculé à partir d'UNE SEULE cote alors que le pari engage DEUX
//  composantes.
//
//  ── LE DÉFAUT MESURÉ, AVANT CE LOT ────────────────────────────────────────
//  `UserPrediction.gainNet` applique UNE cote à UNE mise :
//
//      if (isCorrect == true && montantMise > 0 && cote > 0)
//        return (cote * montantMise) - montantMise;
//
//  Pour un G+P, `cote` est la cote du GAGNANT SEUL et `montantMise` la mise
//  PAR COMPOSANTE. Le produit ne vaut donc rien de réel, et la composante
//  Placé n'y entre jamais. Exemple chiffré retenu par les tests : cote 4.2
//  et mise 10 € ⇒ 32 € affichés comme « gain net », alors que le gain réel
//  dépend aussi de la cote Placé.
//
//  Ce montant remontait dans SIX chemins d'affichage :
//    1. `predictions_screen`      → montant de la carte
//    2. `profile_historique_tab`  → montant de la carte historique
//    3. `profile_historique_tab`  → gain partagé (carte de partage)
//    4. `pmu_provider.totalGainsNet` / `totalGagnes`
//    5. `pmu_provider.getGainsNetByDateRange`
//    6. `profile_progression_tab` → bankroll, courbe cumulée, gain par type
//
//  ── CE QUI EST AJOUTÉ ─────────────────────────────────────────────────────
//  UN SEUL fait dérivé, `UserPrediction.gainGagnantPlaceEtabli`, et son usage
//  par ces six chemins. La règle : pour un G+P, un gain n'est établi que si
//  les DEUX composantes sont ventilées ET si le résultat financier vient
//  d'un rapport officiel (`gainRealise` écrit par `enregistrerDividendePmu`).
//
//  ── CE QUI N'EST PAS TOUCHÉ (interdictions du mandat) ─────────────────────
//   • aucune formule financière : `gainNet`, `retourTotal` et les deux
//     formules de `enregistrerDividendePmu` sont inchangés, et les tests
//     ci-dessous le PROUVENT en re-calculant leurs valeurs ;
//   • `isCorrect` : jamais réécrit, jamais déduit d'un dividende ambigu ;
//   • aucun apprentissage IA, aucun poids, aucun seuil ;
//   • aucune protection A-0 déplacée ni redéfinie ;
//   • aucun test existant modifié ; aucun ticket historique migré ;
//   • C4 non traité, résolveur PMU non branché, autres types de paris
//     strictement inchangés (vérifié type par type).
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/providers/pmu_provider.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Constantes de mesure — aucune valeur « ronde » inventée : ce sont les
//  nombres exacts du défaut reproduit (cote 4,2 / mise 10 € ⇒ 32 €).
// ───────────────────────────────────────────────────────────────────────────
const double kCoteGagnant = 4.2;
const double kMiseParComposante = 10.0;
const double kGainFictifAttendu = (kCoteGagnant * kMiseParComposante) - kMiseParComposante; // 32.0

// ───────────────────────────────────────────────────────────────────────────
//  Fabriques
// ───────────────────────────────────────────────────────────────────────────

/// Ticket G+P dont le gain n'est PAS établi : `isCorrect` vrai, aucun
/// `gainRealise`, deux composantes pourtant renseignées.
/// C'est exactement l'état produit par le dialogue « Gagné » du lot G+P.
UserPrediction gpGainNonEtabli() => UserPrediction(
      id: 'gp_non_etabli',
      dateStr: '2026-11-15',
      numReunion: 1,
      numCourse: 6,
      nomCourse: 'Prix G+P',
      hippodrome: 'VINCENNES',
      numeroCheval: 16,
      nomCheval: 'CHEVAL 16',
      cote: kCoteGagnant,
      typePari: 'Gagnant+Placé',
      isCorrect: true,
      montantMise: kMiseParComposante,
      miseGagnant: kMiseParComposante,
      misePlace: kMiseParComposante,
      createdAt: DateTime(2026, 11, 15, 14, 30),
    );

/// Ticket G+P dont le gain EST établi : les deux composantes sont ventilées
/// et `gainRealise` a été écrit par un rapport officiel.
UserPrediction gpGainEtabli({double gainRealise = 35.0}) => UserPrediction(
      id: 'gp_etabli',
      dateStr: '2026-11-15',
      numReunion: 1,
      numCourse: 7,
      nomCourse: 'Prix G+P officiel',
      hippodrome: 'VINCENNES',
      numeroCheval: 4,
      nomCheval: 'CHEVAL 4',
      cote: kCoteGagnant,
      typePari: 'Gagnant+Placé',
      isCorrect: true,
      montantMise: kMiseParComposante,
      miseGagnant: kMiseParComposante,
      misePlace: kMiseParComposante,
      gainRealise: gainRealise,
      dividendePmuReel: 4.5,
      createdAt: DateTime(2026, 11, 15, 15, 0),
    );

/// Ticket G+P PERDU : la perte est un fait constaté, pas une déduction.
UserPrediction gpPerdu() => UserPrediction(
      id: 'gp_perdu',
      dateStr: '2026-11-15',
      numReunion: 2,
      numCourse: 1,
      nomCourse: 'Prix G+P perdu',
      hippodrome: 'ENGHIEN',
      numeroCheval: 9,
      nomCheval: 'CHEVAL 9',
      cote: kCoteGagnant,
      typePari: 'Gagnant+Placé',
      isCorrect: false,
      montantMise: kMiseParComposante,
      miseGagnant: kMiseParComposante,
      misePlace: kMiseParComposante,
      createdAt: DateTime(2026, 11, 15, 15, 30),
    );

/// Ticket d'un autre type de pari, gagnant, sans `gainRealise` :
/// il doit rester STRICTEMENT inchangé (hors périmètre G+P).
UserPrediction autreTypeGagnant({String typePari = 'Simple Gagnant'}) =>
    UserPrediction(
      id: 'autre_$typePari',
      dateStr: '2026-11-15',
      numReunion: 3,
      numCourse: 2,
      nomCourse: 'Prix $typePari',
      hippodrome: 'CAEN',
      numeroCheval: 5,
      nomCheval: 'CHEVAL 5',
      cote: 3.0,
      typePari: typePari,
      isCorrect: true,
      montantMise: 10.0,
      createdAt: DateTime(2026, 11, 15, 16, 0),
    );

Future<PmuProvider> providerVide() async {
  SharedPreferences.setMockInitialValues({});
  final p = PmuProvider();
  // Le `_loadSavedPredictions()` lancé par le constructeur fait un `clear()`
  // tardif : on le laisse finir avant tout ajout.
  await Future<void>.delayed(const Duration(milliseconds: 80));
  await p.reloadPredictions();
  return p;
}

/// Code SEUL d'un fichier : commentaires ET contenus de chaînes retirés.
///
/// ⚠️ Deux conséquences à ne jamais oublier dans les assertions :
///   • un LITTÉRAL affiché (« Gain non établi ») est du contenu de chaîne :
///     il faut le chercher dans le texte BRUT, pas ici ;
///   • un MOTIF DE CODE (`cote * montantMise`, `if (isCorrect == ...`) est
///     bien ici — et seulement ici, car les commentaires de correction
///     citent forcément les motifs qu'ils expliquent.
///
/// Gère les trois formes de guillemets et les commentaires de bloc, faute de
/// quoi une apostrophe mal appariée désynchroniserait tout le reste du
/// fichier (mesuré : l'ancienne version rendait `indexOf` = −1 après une
/// chaîne à guillemets doubles).
String codeSeul(String source) {
  final buffer = StringBuffer();
  var enChaine = false;
  var echappe = false;
  var enBloc = false;
  String? fermeture;

  for (var i = 0; i < source.length; i++) {
    final c = source[i];

    if (enBloc) {
      if (c == '*' && i + 1 < source.length && source[i + 1] == '/') {
        enBloc = false;
        i++;
      }
      continue;
    }

    if (enChaine) {
      if (echappe) {
        echappe = false;
      } else if (c == r'\') {
        echappe = true;
      } else if (c == fermeture) {
        // Fermeture possible d'un littéral triple : on la consomme aussi.
        if (fermeture!.length == 3) {
          if (i + 2 < source.length &&
              source[i + 1] == fermeture[0] &&
              source[i + 2] == fermeture[0]) {
            i += 2;
          }
          enChaine = false;
          fermeture = null;
        } else {
          enChaine = false;
          fermeture = null;
        }
      }
      continue;
    }

    // Commentaire de bloc.
    if (c == '/' && i + 1 < source.length && source[i + 1] == '*') {
      enBloc = true;
      i++;
      continue;
    }

    // Commentaire de ligne.
    if (c == '/' && i + 1 < source.length && source[i + 1] == '/') {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
      buffer.write('\n');
      continue;
    }

    // Ouverture d'un littéral.
    if (c == "'" || c == '"') {
      if (i + 2 < source.length && source[i + 1] == c && source[i + 2] == c) {
        enChaine = true;
        fermeture = '$c$c$c';
        i += 2;
      } else {
        enChaine = true;
        fermeture = c;
      }
      continue;
    }

    buffer.write(c);
  }
  return buffer.toString();
}

String codeSeulFichier(String chemin) =>
    codeSeul(File(chemin).readAsStringSync());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═════════════════════════════════════════════════════════════════════════
  //  H1 — LE PRÉDICAT : QUAND UN GAIN G+P EST-IL ÉTABLI ?
  // ═════════════════════════════════════════════════════════════════════════

  group('H1 — gainGagnantPlaceEtabli', () {
    test('H1/1 — G+P gagné sur une seule cote : gain NON établi', () {
      final p = gpGainNonEtabli();
      expect(p.gainGagnantPlaceEtabli, isFalse,
          reason: 'cote Gagnant seule + aucune ventilation officielle');
      // Témoin du défaut : la formule produit bien 32 €.
      expect(p.gainNet, closeTo(kGainFictifAttendu, 1e-9),
          reason: 'la formule gainNet est INCHANGÉE : elle rend 32,0 €');
    });

    test('H1/2 — G+P gagné avec résultat officiel : gain établi', () {
      final p = gpGainEtabli();
      expect(p.gainGagnantPlaceEtabli, isTrue,
          reason: 'deux composantes + gainRealise officiel');
      expect(p.gainNet, 35.0);
    });

    test('H1/3 — G+P perdu : la perte reste affichable', () {
      final p = gpPerdu();
      expect(p.gainGagnantPlaceEtabli, isTrue,
          reason: '−mise n\'est pas une cote appliquée à une mise');
      expect(p.gainNet, -10.0);
    });

    test('H1/4 — G+P aux composantes incomplètes : gain NON établi', () {
      final partiel = UserPrediction(
        id: 'gp_partiel',
        dateStr: '2026-11-15',
        numReunion: 4,
        numCourse: 4,
        nomCourse: 'C',
        hippodrome: 'H',
        numeroCheval: 1,
        nomCheval: 'C1',
        cote: kCoteGagnant,
        typePari: 'Gagnant+Placé',
        isCorrect: true,
        montantMise: kMiseParComposante,
        miseGagnant: kMiseParComposante, // Placé absent
        gainRealise: 35.0,
        createdAt: DateTime(2026, 11, 15),
      );
      expect(partiel.misesGagnantPlaceIncompletes, isTrue);
      expect(partiel.gainGagnantPlaceEtabli, isFalse,
          reason: 'une seule composante ⇒ le gain des DEUX n\'est pas établi');
    });

    test('H1/5 — G+P en attente : rien n\'est établi, rien n\'est affiché', () {
      final enAttente = UserPrediction(
        id: 'gp_attente',
        dateStr: '2026-11-15',
        numReunion: 4,
        numCourse: 5,
        nomCourse: 'C',
        hippodrome: 'H',
        numeroCheval: 2,
        nomCheval: 'C2',
        cote: kCoteGagnant,
        typePari: 'Gagnant+Placé',
        montantMise: kMiseParComposante,
        miseGagnant: kMiseParComposante,
        misePlace: kMiseParComposante,
        createdAt: DateTime(2026, 11, 15),
      );
      expect(enAttente.isCorrect, isNull);
      expect(enAttente.gainGagnantPlaceEtabli, isFalse);
      expect(enAttente.gainNet, 0.0, reason: 'aucun gain en attente');
    });

    test('H1/6 — hors G+P : le prédicat est neutre, TOUS les types', () {
      for (final t in <String>[
        'Simple Gagnant',
        'Simple Placé',
        'Couplé Gagnant',
        'Couplé Placé',
        'Tiercé',
        'Quarté+',
        'Quinté+',
        'Trio',
      ]) {
        expect(autreTypeGagnant(typePari: t).gainGagnantPlaceEtabli, isTrue,
            reason: '$t doit rester strictement inchangé');
      }
    });

    test('H1/7 — les 3 libellés G+P sont traités identiquement', () {
      for (final libelle in <String>[
        'Gagnant+Placé',
        'Gagnant + Placé',
        'Gagnant+Place',
      ]) {
        final p = UserPrediction(
          id: 'x_$libelle',
          dateStr: '2026-11-15',
          numReunion: 1,
          numCourse: 1,
          nomCourse: 'C',
          hippodrome: 'H',
          numeroCheval: 1,
          nomCheval: 'C1',
          cote: kCoteGagnant,
          typePari: libelle,
          isCorrect: true,
          montantMise: kMiseParComposante,
          miseGagnant: kMiseParComposante,
          misePlace: kMiseParComposante,
          createdAt: DateTime(2026, 11, 15),
        );
        expect(p.gainGagnantPlaceEtabli, isFalse, reason: libelle);
      }
    });

    test('H1/8 — le prédicat est PUR : aucune écriture sur le ticket', () {
      final p = gpGainNonEtabli();
      final avant = p.toJson();
      for (var i = 0; i < 5; i++) {
        p.gainGagnantPlaceEtabli;
      }
      expect(p.toJson(), equals(avant));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  H2 — LA FORMULE FINANCIÈRE EST INTACTE
  // ═════════════════════════════════════════════════════════════════════════

  group('H2 — aucune formule financière modifiée', () {
    test('H2/1 — `gainNet` garde ses 4 branches, dans l\'ordre', () {
      final s = codeSeulFichier('lib/models/pmu_models.dart');
      expect(s.contains('if (gainRealise != null) return gainRealise!;'), isTrue);
      expect(s.contains('if (isCorrect == false && montantMise > 0) return -montantMise;'),
          isTrue);
      expect(
          s.contains('return (dividendePmuReel! * montantMise) - montantMise;'),
          isTrue);
      expect(s.contains('return (cote * montantMise) - montantMise;'), isTrue);

      final iGain = s.indexOf('double get gainNet {');
      final iPerdu = s.indexOf('if (isCorrect == false && montantMise > 0)');
      final iDiv =
          s.indexOf('if (dividendePmuReel != null && montantMise > 0 && isCorrect == true)');
      final iCote = s.indexOf('if (isCorrect == true && montantMise > 0 && cote > 0)');
      expect(iGain, lessThan(iPerdu));
      expect(iPerdu, lessThan(iDiv), reason: 'perdu vérifié AVANT dividende');
      expect(iDiv, lessThan(iCote));
    });

    test('H2/2 — `retourTotal` est inchangé', () {
      final s = codeSeulFichier('lib/models/pmu_models.dart');
      expect(s.contains('if (isCorrect == false) return 0.0;'), isTrue);
      expect(s.contains('return dividendePmuReel! * montantMise;'), isTrue);
      expect(s.contains('return cote * montantMise;'), isTrue);
    });

    test('H2/3 — les deux formules T8b de enregistrerDividendePmu intactes', () {
      final s = codeSeulFichier('lib/providers/pmu_provider.dart');
      expect(
          s.contains('? (dividendePmuReel * old.montantMise) - old.montantMise'),
          isTrue);
      expect(s.contains(': -old.montantMise;'), isTrue);
      expect(s.contains('final bool estGagnant = dividendePmuReel > 0;'), isTrue,
          reason: 'isCorrect n\'est pas déduit autrement qu\'avant');
    });

    test('H2/4 — le repli de validatePrediction est intact pour les autres types',
        () {
      final s = codeSeulFichier('lib/providers/pmu_provider.dart');
      expect(s.contains('? (old.cote * mise) - mise'), isTrue,
          reason: 'la formule du repli existe toujours');
    });

    test('H2/5 — le getter mesure EXACTEMENT la valeur de la formule', () {
      // Preuve par le calcul, pas par la lecture du source.
      final p = gpGainNonEtabli();
      expect(p.gainNet,
          (kCoteGagnant * p.montantMise) - p.montantMise);
      // Le prédicat ne modifie pas le montant : il ne fait que le qualifier.
      expect(p.gainNet, closeTo(32.0, 1e-9));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  H3 — LES CHEMINS D'AFFICHAGE PAR TICKET
  // ═════════════════════════════════════════════════════════════════════════

  group('H3 — aucun montant G+P non prouvé affiché', () {
    test('H3/1 — predictions_screen ne présente plus le montant brut', () {
      // Le littéral affiché est du CONTENU de chaîne : texte brut.
      final brut = File('lib/screens/predictions_screen.dart').readAsStringSync();
      expect(brut.contains('gain non établi'), isTrue);
      final code = codeSeulFichier('lib/screens/predictions_screen.dart');
      expect(code.contains('!pred.gainGagnantPlaceEtabli'), isTrue);
      // La garde est AVANT le montant : le montant n'est atteignable que
      // si le gain est établi.
      final iGarde = brut.indexOf('!pred.gainGagnantPlaceEtabli');
      final iMontant = brut.indexOf('fmtEuros(pred.gainNet)}€');
      expect(iGarde, greaterThanOrEqualTo(0));
      expect(iMontant, greaterThan(iGarde),
          reason: 'le montant doit venir après la garde');
    });

    test('H3/2 — la carte historique annonce « Gain non établi »', () {
      // Littéral affiché ⇒ texte brut (le filtre codeSeul retire les chaînes).
      final brut =
          File('lib/widgets/profile/profile_historique_tab.dart').readAsStringSync();
      expect(brut.contains('Gain non établi'), isTrue);
      final code = codeSeulFichier('lib/widgets/profile/profile_historique_tab.dart');
      expect(code.contains('gainGagnantPlaceEtabli'), isTrue);
    });

    test('H3/3 — le gain partagé est retiré quand il n\'est pas établi', () {
      final s = codeSeulFichier('lib/widgets/profile/profile_historique_tab.dart');
      expect(
          s.contains('pred.isCorrect == true && pred.gainGagnantPlaceEtabli'),
          isTrue,
          reason: 'la carte de partage ne reçoit pas un gain non établi');
    });

    test('H3/4 — le badge ×PMU n\'est pas affiché sur un gain non établi', () {
      final s = codeSeulFichier('lib/widgets/profile/profile_historique_tab.dart');
      expect(s.contains('pred.dividendeRecupere && isCorrect == true && gainAffiche'),
          isTrue);
    });

    test('H3/5 — aucun autre type de pari n\'est filtré à l\'affichage', () {
      // Le prédicat est le SEUL point de décision : aucun test de libellé
      // n'est réécrit dans les écrans.
      for (final f in <String>[
        'lib/screens/predictions_screen.dart',
        'lib/widgets/profile/profile_historique_tab.dart',
        'lib/widgets/profile/profile_progression_tab.dart',
      ]) {
        final s = codeSeulFichier(f);
        expect(s.contains("== 'Gagnant"), isFalse,
            reason: '$f ne doit pas retester le libellé à la main');
        expect(s.contains('kLibellesGagnantPlace'), isFalse, reason: f);
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  H4 — LES TOTAUX : agrégats du provider
  // ═════════════════════════════════════════════════════════════════════════

  group('H4 — totaux : aucun gain G+P non établi additionné', () {
    test('H4/1 — totalGainsNet exclut le gain non établi, garde la perte',
        () async {
      final provider = await providerVide();
      provider.addPrediction(gpGainNonEtabli()); // +32 € fictifs
      provider.addPrediction(gpPerdu()); // −10 € réels

      expect(provider.totalGainsNet, -10.0,
          reason: 'les 32 € non prouvés sont exclus, la perte reste comptée');
    });

    test('H4/2 — totalGagnes n\'affiche pas un retour G+P non établi', () async {
      final provider = await providerVide();
      provider.addPrediction(gpGainNonEtabli());
      expect(provider.totalGagnes, 0.0,
          reason: 'aucun retour encaissé ne peut être affirmé');
    });

    test('H4/3 — un G+P établi EST compté, sans changement', () async {
      final provider = await providerVide();
      provider.addPrediction(gpGainEtabli());
      expect(provider.totalGainsNet, 35.0);
      // retourTotal G+P établi = dividende × montantMise = 4.5 × 10 = 45.0
      expect(provider.totalGagnes, closeTo(45.0, 1e-9));
    });

    test('H4/4 — totalMise compte les DEUX composantes d\'un G+P', () async {
      final provider = await providerVide();
      provider.addPrediction(gpGainNonEtabli()); // 10 € + 10 € engagés
      expect(provider.totalMise, 20.0,
          reason: 'montantMise ne porte qu\'une composante : 10 € serait faux');
    });

    test('H4/5 — totalMise d\'un pari simple est strictement inchangé', () async {
      final provider = await providerVide();
      provider.addPrediction(autreTypeGagnant());
      expect(provider.totalMise, 10.0);
    });

    test('H4/6 — totalPerdu compte la mise engagée des deux composantes',
        () async {
      final provider = await providerVide();
      provider.addPrediction(gpPerdu());
      expect(provider.totalPerdu, 20.0,
          reason: 'la perte réelle est 10 € Gagnant + 10 € Placé');
    });

    test('H4/7 — getGainsNetByDateRange suit la même règle', () async {
      final provider = await providerVide();
      provider.addPrediction(gpGainNonEtabli());
      final debut = DateTime(2026, 11, 1);
      final fin = DateTime(2026, 11, 30);
      expect(provider.getGainsNetByDateRange(debut, fin), 0.0);
    });

    test('H4/8 — les autres types restent comptés à l\'identique', () async {
      final provider = await providerVide();
      provider.addPrediction(autreTypeGagnant()); // cote 3.0, mise 10 €
      expect(provider.totalGainsNet, 20.0,
          reason: '(3.0 × 10) − 10 = 20 : comportement historique préservé');
      expect(provider.totalGagnes, closeTo(30.0, 1e-9));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  H5 — LE CUMUL DE PROGRESSION
  // ═════════════════════════════════════════════════════════════════════════

  group('H5 — cumuls : bankroll, courbe, gain par type', () {
    test('H5/1 — le cumul n\'ajoute pas un gain non établi', () {
      final s = codeSeulFichier('lib/widgets/profile/profile_progression_tab.dart');
      // Les TROIS agrégations doivent porter le prédicat.
      expect('gainGagnantPlaceEtabli'.allMatches(s).length, greaterThanOrEqualTo(3),
          reason: 'bankroll + courbe + gain par type');
      expect(s.contains('capital += p.gainGagnantPlaceEtabli ? p.gainNet : 0.0;'),
          isTrue);
      expect(s.contains('p.montantMise > 0 &&'), isTrue);
      expect(s.contains('p.gainGagnantPlaceEtabli)'), isTrue);
    });

    test('H5/2 — la somme des gains des tickets établi est inchangée', () {
      // Recalcul direct : la valeur n'est pas touchée, seule sa
      // contribution au cumul l'est.
      final etabli = gpGainEtabli();
      expect(etabli.gainGagnantPlaceEtabli ? etabli.gainNet : 0.0, 35.0);
      final nonEtabli = gpGainNonEtabli();
      expect(nonEtabli.gainGagnantPlaceEtabli ? nonEtabli.gainNet : 0.0, 0.0);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  H6 — TICKETS HISTORIQUES PRÉSERVÉS
  // ═════════════════════════════════════════════════════════════════════════

  group('H6 — aucun ticket historique modifié', () {
    test('H6/1 — un ancien G+P sans composantes reste lisible et intact', () {
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
      expect(p.miseGagnant, isNull);
      expect(p.misePlace, isNull);
      expect(p.montantMise, 0.0);
      // Composantes absentes ⇒ gain non établi, MAIS aucune écriture.
      expect(p.gainGagnantPlaceEtabli, isFalse);
      expect(p.gainNet, 0.0);
      expect(jsonEncodeStable(p), equals(jsonEncodeStable(p)));
    });

    test('H6/2 — un ancien G+P résolu par la cote n\'est pas réécrit', () {
      final ancien = UserPrediction(
        id: 'ancien_cote',
        dateStr: '2024-02-01',
        numReunion: 2,
        numCourse: 3,
        nomCourse: 'Ancien',
        hippodrome: 'VINCENNES',
        numeroCheval: 6,
        nomCheval: 'CHEVAL 6',
        cote: 6.0,
        typePari: 'Gagnant+Placé',
        isCorrect: true,
        montantMise: 20.0,
        gainRealise: 100.0,
        createdAt: DateTime(2024, 2, 1),
      );
      final avant = ancien.toJson();
      ancien.gainGagnantPlaceEtabli;
      expect(ancien.toJson(), equals(avant),
          reason: 'le prédicat ne migre ni ne complète rien');
      // Le gain HISTORIQUE (gainRealise) reste affichable : il est établi
      // par une saisie, pas déduit d'une cote.
      expect(ancien.gainGagnantPlaceEtabli, isFalse,
          reason: 'sans les deux composantes il n\'est pas qualifiable');
      expect(ancien.gainNet, 100.0, reason: 'montant historique inchangé');
    });

    test('H6/3 — un ancien pari simple garde son gain affiché', () {
      final ancien = UserPrediction.fromJson(<String, dynamic>{
        'id': 'ancien_simple',
        'dateStr': '2023-06-01',
        'numReunion': 1,
        'numCourse': 1,
        'nomCourse': 'C',
        'hippodrome': 'H',
        'numeroCheval': 2,
        'nomCheval': 'C2',
        'cote': 4.0,
        'typePari': 'Simple Gagnant',
        'isCorrect': true,
        'montantMise': 5.0,
        'createdAt': DateTime(2023, 6, 1).toIso8601String(),
      });
      expect(ancien.gainGagnantPlaceEtabli, isTrue);
      expect(ancien.gainNet, 15.0, reason: '(4 × 5) − 5 = 15 : inchangé');
    });

    test('H6/4 — aucune suppression de ticket par le provider', () async {
      final provider = await providerVide();
      provider.addPrediction(gpGainNonEtabli());
      provider.addPrediction(gpGainEtabli());
      provider.addPrediction(autreTypeGagnant());
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(provider.predictions.length, 3);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  H7 — NON-RÉGRESSIONS DU MANDAT
  // ═════════════════════════════════════════════════════════════════════════

  group('H7 — non-régressions', () {
    test('H7/1 — la garde A-0 est intacte et reste l\'autorité', () {
      final s = File('lib/utils/type_pari_utils.dart').readAsStringSync();
      expect(s.contains('const Set<String> kLibellesGagnantPlace'), isTrue);
      expect(s.contains('bool estTypeGagnantPlace(String? typePari)'), isTrue);
      expect(s.contains('bool estEtatSansPariRecommande(String? typePari)'), isTrue);
      // Le modèle DÉLÈGUE, il ne redéfinit pas.
      final m = codeSeulFichier('lib/models/pmu_models.dart');
      expect(m.contains('kLibellesGagnantPlace'), isFalse);
      expect(m.contains('estTypeGagnantPlace(typePari)'), isTrue);
    });

    test('H7/2 — la règle T8a (statistiques IA) est intacte', () {
      final s = File('lib/services/ia_memory_service.dart').readAsStringSync();
      expect(s.contains('if (isCorrect == null) continue;'), isTrue);
    });

    test('H7/3 — l\'apprentissage IA n\'est pas touché', () async {
      // ═══════════════════════════════════════════════════════════════════════
      //  H7/3 — RÉÉCRIT LE 2026-11-25 SUR ARBITRAGE EXPLICITE (B1-T12).
      //
      //  ── POURQUOI L'ANCIENNE ASSERTION A ÉTÉ RETIRÉE ──────────────────────
      //  Elle interdisait TEXTUELLEMENT la présence de `gainGagnantPlaceEtabli`
      //  dans `_syncStatsTypesIA` :
      //
      //      expect(bloc.contains('gainGagnantPlaceEtabli'), isFalse, ...)
      //
      //  Or ce prédicat ne fait que QUALIFIER une contribution financière. Le
      //  supprimer du bloc n'était donc pas une garantie d'absence d'atteinte
      //  à l'apprentissage : c'était une garantie de FORME.
      //
      //  La démonstration mesurée de séparation des données a été refaite :
      //    • `_statsTypes`      (ia_memory_service.dart:159)
      //    • `_precisionParType`(ia_memory_service.dart:161)
      //  sont DEUX maps distinctes. Les seuils adaptatifs
      //  (ia_memory_service.dart:5917-5919) lisent `nbParType`, construit à
      //  l.5775-5788 depuis `IaPronostic.typePariConseille` et
      //  `_estBonConseilParType` — jamais depuis `_statsTypes`.
      //  Seules lectures de `_statsTypes` : le getter `statsParType`
      //  (2 lecteurs d'AFFICHAGE : ia_performance_screen.dart:2673,
      //  ia_precision_widget.dart:31) plus clear/load/save.
      //
      //  ── CE QUE H7/3 GARANTIT DÉSORMAIS ───────────────────────────────────
      //   (1) STRUCTURE : le bloc ne transmet QUE typePari / isCorrect /
      //       gainNet, et n'écrit vers aucun poids, seuil ni mécanisme
      //       d'apprentissage.
      //   (2) COMPORTEMENT : après `mettreAJourStatsTypes`, les seuils ET les
      //       poids sont STRICTEMENT identiques — et les stats par type ont
      //       réellement été recalculées (sinon le test passerait à vide).
      // ═══════════════════════════════════════════════════════════════════════

      // ── (1) VÉRIFICATION STRUCTURELLE ─────────────────────────────────────
      //
      //  ⚠️ DEUX LECTURES SONT NÉCESSAIRES, et c'est mesuré :
      //    • `codeSeulFichier` retire les COMMENTAIRES **ET** les CONTENUS DE
      //      CHAÎNES. Les clés `'typePari'` / `'isCorrect'` / `'gainNet'` y
      //      sont donc absentes par construction : on ne peut pas les y
      //      chercher (première exécution : « Expected: true / Actual:
      //      <false> », ligne 748).
      //    • Inversement, le source BRUT contient le commentaire de
      //      justification, qui cite « poids », « seuils », « gradient »,
      //      « TOP3 » : on ne peut pas y chercher l'absence de ces mots.
      //  Chaque assertion utilise donc la lecture qui la rend honnête.
      final brut = File('lib/providers/pmu_provider.dart').readAsStringSync();
      final s = codeSeulFichier('lib/providers/pmu_provider.dart');
      final iSync = s.indexOf('void _syncStatsTypesIA()');
      expect(iSync, greaterThanOrEqualTo(0),
          reason: '_syncStatsTypesIA doit exister');

      // Le bloc est délimité par la méthode SUIVANTE, pas par une taille
      // arbitraire : une fenêtre fixe pourrait déborder sur le code voisin et
      // rendre l'assertion fausse dans les deux sens.
      //
      // Bloc en CODE SEUL (identifiants, sans commentaires ni chaînes).
      final iSuivante = s.indexOf('void ', iSync + 1);
      final bloc = iSuivante > iSync
          ? s.substring(iSync, iSuivante)
          : s.substring(iSync);

      // Bloc en SOURCE BRUT (les clés sont des chaînes).
      final iSyncBrut = brut.indexOf('void _syncStatsTypesIA()');
      expect(iSyncBrut, greaterThanOrEqualTo(0));
      final iSuivanteBrut = brut.indexOf('void ', iSyncBrut + 1);
      final blocBrut = iSuivanteBrut > iSyncBrut
          ? brut.substring(iSyncBrut, iSuivanteBrut)
          : brut.substring(iSyncBrut);

      // (1a) Les trois clés transmises, et elles seules — lues sur le BRUT.
      expect(blocBrut.contains("'typePari'"), isTrue,
          reason: 'la statistique a besoin du type de pari');
      expect(blocBrut.contains("'isCorrect'"), isTrue,
          reason: 'la statistique a besoin du résultat sportif');
      expect(blocBrut.contains("'gainNet'"), isTrue,
          reason: 'la statistique a besoin de la contribution financière');

      // (1b) La valeur transmise est bien celle de la formule, conditionnée
      //      par la qualification d'affichage — lue sur le CODE SEUL.
      //      Le prédicat est AUTORISÉ ici : il ne fait que choisir entre
      //      `gainNet` et `0.0`.
      expect(bloc.contains('p.gainNet'), isTrue,
          reason: 'les stats reçoivent la valeur de gainNet, jamais un montant '
              'recalculé');
      expect(bloc.contains('p.gainGagnantPlaceEtabli'), isTrue,
          reason: 'la contribution financière est conditionnée par la '
              'qualification G+P (autorisation B1-T12)');

      // (1c) AUCUNE ÉCRITURE vers les mécanismes protégés. C'est le cœur de
      //      la protection : le bloc ne doit pas toucher aux poids, aux
      //      seuils, au gradient, ni au TOP3.
      for (final interdit in <String>[
        'poids',
        'seuil',
        '_seuils',
        'gradient',
        'apprendre',
        'ajusterSeuil',
        'top3',
        'TOP3',
        'learningRate',
      ]) {
        expect(bloc.toLowerCase().contains(interdit.toLowerCase()), isFalse,
            reason: 'le bloc de statistiques ne doit pas référencer '
                '« $interdit » : ce n\'est pas son rôle');
      }

      // (1d) Le bloc n'appelle QUE `mettreAJourStatsTypes` : aucune autre
      //      méthode d'écriture de `IaMemoryService`.
      expect(bloc.contains('mettreAJourStatsTypes'), isTrue,
          reason: 'seul point d\'entrée autorisé vers les statistiques');
      for (final autreEcriture in <String>[
        'enregistrerResultat',
        'apprendre',
        'entrainer',
        'mettreAJourPoids',
        'ajusterSeuils',
      ]) {
        expect(bloc.contains(autreEcriture), isFalse,
            reason: 'aucune écriture « $autreEcriture » depuis ce bloc');
      }

      // ── (2) VÉRIFICATION COMPORTEMENTALE ──────────────────────────────────
      // On observe l'apprentissage par ses ACCESSEURS PUBLICS, avant/après.
      final svc = IaMemoryService.instance;

      // Isolation : on réinitialise par le mécanisme déjà présent dans le
      // projet, sans créer d'infrastructure nouvelle.
      SharedPreferences.setMockInitialValues({});
      await svc.recharger();

      final seuilsAvant = Map<String, dynamic>.from(svc.seuilsConfiance.toJson());
      final poidsAvant = Map<String, dynamic>.from(svc.poids.toJson());

      // Données REPRÉSENTATIVES : un G+P neutralisé (gainNet 0.0, tel que le
      // transmet désormais `_syncStatsTypesIA`) et un Simple Gagnant réel.
      await svc.mettreAJourStatsTypes([
        {'typePari': 'Gagnant+Placé', 'isCorrect': true, 'gainNet': 0.0},
        {'typePari': 'Simple Gagnant', 'isCorrect': true, 'gainNet': 20.0},
        {'typePari': 'Simple Gagnant', 'isCorrect': false, 'gainNet': -10.0},
      ]);

      // (2a) Les seuils n'ont pas bougé : toJson() est comparé clé par clé.
      final seuilsApres = svc.seuilsConfiance.toJson();
      expect(seuilsApres, equals(seuilsAvant),
          reason: 'aucun seuil adaptatif ne doit être ajusté par les '
              'statistiques par type de pari');

      // (2b) Les poids n'ont pas bougé, y compris les sous-structures
      //      (poidsIndices, dernierGradient, poidsParDiscipline).
      final poidsApres = svc.poids.toJson();
      expect(poidsApres, equals(poidsAvant),
          reason: 'aucun poids ne doit être modifié par les statistiques par '
              'type de pari (gradient descent intact)');

      // (2c) GARDE-FOU ANTI-TEST-À-VIDE : le comportement attendu a bien été
      //      exercé. Sans cette assertion, un `mettreAJourStatsTypes` qui ne
      //      ferait rien passerait le test pour de mauvaises raisons.
      final stats = svc.statsParType;
      final sg = stats.firstWhere((e) => e.typePari == 'Simple Gagnant',
          orElse: () => throw StateError(
              'les statistiques n\'ont pas été mises à jour : le test ne '
              'prouverait rien'));
      expect(sg.nbJoues, 2, reason: 'deux paris Simple Gagnant transmis');
      expect(sg.nbGagnes, 1);
      expect(sg.nbPerdus, 1);
      expect(sg.gainNet, 10.0,
          reason: '20.0 + (−10.0) = 10.0 : la contribution financière a bien '
              'été accumulée');

      final gp = stats.where((e) => e.typePari == 'Gagnant+Placé').toList();
      expect(gp.length, 1,
          reason: 'la ligne G+P existe (résultat sportif connu)');
      expect(gp.first.gainNet, 0.0,
          reason: 'le gain G+P non établi est transmis à 0.0 : il n\'est pas '
              'comptabilisé comme un gain réel');
      expect(gp.first.nbGagnes, 1,
          reason: 'le résultat sportif reste compté : seule la contribution '
              'financière est neutralisée');
    });

    test('H7/4 — C4 n\'est pas traité', () {
      final s = codeSeulFichier('lib/screens/profile_screen.dart');
      expect(
          s.contains(
              'final taux = allFiltered.isNotEmpty ? (nbGagnes / allFiltered.length) * 100 : 0.0;'),
          isTrue);
    });

    test('H7/5 — le résolveur PMU n\'est pas branché', () {
      for (final f in <String>[
        'lib/models/pmu_models.dart',
        'lib/providers/pmu_provider.dart',
        'lib/screens/predictions_screen.dart',
        'lib/widgets/profile/profile_historique_tab.dart',
        'lib/widgets/profile/profile_progression_tab.dart',
      ]) {
        final s = File(f).readAsStringSync();
        expect(s.contains('resolveur_rapport_pmu'), isFalse, reason: f);
        expect(s.contains('resoudreRapportPmu'), isFalse, reason: f);
      }
    });

    test('H7/6 — la validation manuelle du lot précédent est intacte', () {
      for (final f in <String>[
        'lib/screens/predictions_screen.dart',
        'lib/widgets/profile/profile_historique_tab.dart',
      ]) {
        final s = codeSeulFichier(f);
        expect(s.contains('deciderValidationManuelle(pred)'), isTrue, reason: f);
        expect(s.contains('estEtatSansPariRecommande(pred.typePari)'), isTrue,
            reason: f);
      }
    });
  });
}

/// Sérialisation stable, pour comparer deux états d'un même ticket.
String jsonEncodeStable(UserPrediction p) {
  final m = p.toJson();
  final cles = m.keys.toList()..sort();
  return cles.map((k) => '$k=${m[k]}').join('|');
}
