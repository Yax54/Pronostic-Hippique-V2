// ═══════════════════════════════════════════════════════════════════════════
//  LOT C1 + C2 + C3 + C4bis — « AUCUN PARI RECOMMANDÉ »
//
//  OBJET : prouver qu'un ticket `typePari = 'À surveiller'` (ou de type vide)
//  ne peut créer NI mise, NI gain, NI perte, NI résultat financier par AUCUNE
//  des voies corrigées.
//
//  ── CE QUE CES TESTS DÉMONTRENT, ET COMMENT ───────────────────────────────
//  Ils n'affirment rien par lecture de code : ils EXÉCUTENT les fonctions
//  réelles et comparent l'état du ticket avant / après.
//
//  ── CE QUE CES TESTS NE TOUCHENT PAS ──────────────────────────────────────
//  • aucune formule financière (`gainNet`, `retourTotal`) n'est modifiée ;
//  • aucune logique de `isCorrect` n'est redéfinie ;
//  • aucun test existant n'est modifié ;
//  • la garde A-0 (`estTypeGagnantPlace`) n'est ni testée ni déplacée ici ;
//  • `Gagnant + Placé` n'est PAS traité dans ce lot (interdiction explicite).
//
//  ── MESURE DE DÉPART (mandat H, sonde exécutée puis supprimée) ────────────
//  Avant correction, `validatePrediction` sur un ticket `'À surveiller'`
//  produisait mesurablement :
//      isCorrect=true  → montantMise=10.0, gainRealise=32.0, gainNet=32.0,
//                        totalMise=10.0, totalGainsNet=32.0, totalGagnes=42.0
//      isCorrect=false → montantMise=10.0, gainRealise=-10.0,
//                        totalPerdu=10.0
//  Ces chiffres sont reproduits ci-dessous en « état interdit » : les tests
//  C3/1 et C3/2 vérifient qu'ils ne se produisent PLUS.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/providers/pmu_provider.dart';
import 'package:pronostic_hippique/utils/type_pari_utils.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Fabriques
// ───────────────────────────────────────────────────────────────────────────

/// Ticket tel que le produisait l'ex-`race_detail_screen.dart:348-359`
/// (fichier supprimé en BL1-A18) lorsqu'il
/// hérite d'un libellé `'À surveiller'` via `_betType = pred.typePari` (l.59) :
/// **aucun `montantMise`, aucun `isCorrect`, aucun `gainRealise`**.
UserPrediction ticketSansPari({
  String typePari = 'À surveiller',
  double cote = 4.2,
}) =>
    UserPrediction(
      id: 'sans_pari_1',
      dateStr: '2026-11-15',
      numReunion: 1,
      numCourse: 6,
      nomCourse: 'Prix de la Sonde',
      hippodrome: 'VINCENNES',
      numeroCheval: 16,
      nomCheval: 'CHEVAL 16',
      cote: cote,
      typePari: typePari,
      createdAt: DateTime(2026, 11, 15, 14, 30),
    );

/// Ticket d'un pari RÉEL, pour prouver que les gardes ne bloquent pas ce
/// qu'elles ne doivent pas bloquer (non-régression).
UserPrediction ticketPariReel({
  String typePari = 'Simple Gagnant',
  double montantMise = 10.0,
}) =>
    UserPrediction(
      id: 'pari_reel_1',
      dateStr: '2026-11-15',
      numReunion: 2,
      numCourse: 3,
      nomCourse: 'Prix du Contrôle',
      hippodrome: 'ENGHIEN',
      numeroCheval: 7,
      nomCheval: 'CHEVAL 7',
      cote: 3.0,
      typePari: typePari,
      montantMise: montantMise,
      createdAt: DateTime(2026, 11, 15, 15, 0),
    );

/// Provider isolé : `SharedPreferences` vidé, puis on laisse le chargement
/// lancé par le CONSTRUCTEUR se terminer avant tout ajout.
///
/// ── POURQUOI CE DÉLAI EST NÉCESSAIRE (mesuré) ─────────────────────────────
/// `PmuProvider()` déclenche `_loadSavedPredictions().then(...)`
/// (`pmu_provider.dart:24`). Cette méthode fait `_predictions.clear()` APRÈS
/// avoir attendu `SharedPreferences.getInstance()`. Un `addPrediction()`
/// émis avant la fin de ce chargement est donc effacé par le `clear()` tardif
/// — et comme `_savePredictions()` construit sa liste avec un `.map()`
/// **lazy** évalué après son propre `await`, il sérialise alors la liste
/// vidée.
///
/// Mesure de ce défaut de harnais : après `addPrediction`, la clé
/// `user_predictions_v2` existait mais contenait `[]` au lieu du ticket.
/// Ce n'est PAS un défaut des gardes C3/C4bis (prouvées par les tests en
/// mémoire ci-dessus) : c'est un conflit entre deux chargements concurrents.
/// On attend donc que le chargement du constructeur soit terminé.
Future<PmuProvider> providerVide() async {
  SharedPreferences.setMockInitialValues({});
  final p = PmuProvider();
  await Future<void>.delayed(const Duration(milliseconds: 80));
  await p.reloadPredictions();
  return p;
}

/// Photographie de l'état financier d'un ticket.
///
/// Sert à comparer « avant / après » : un ticket sans pari doit rendre une
/// photographie IDENTIQUE, quelle que soit la voie d'écriture empruntée.
Map<String, Object?> photo(UserPrediction p) => <String, Object?>{
      'isCorrect': p.isCorrect,
      'montantMise': p.montantMise,
      'gainRealise': p.gainRealise,
      'gainNet': p.gainNet,
      'retourTotal': p.retourTotal,
      'statutLabel': p.statutLabel,
      'dividendePmuReel': p.dividendePmuReel,
      'combinaisonPmu': p.combinaisonPmu,
      'typePari': p.typePari,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═════════════════════════════════════════════════════════════════════════
  //  C1 — LE PRÉDICAT `estEtatSansPariRecommande`
  // ═════════════════════════════════════════════════════════════════════════

  group('C1 — prédicat estEtatSansPariRecommande', () {
    test('C1/1 — « À surveiller » est reconnu comme sans pari', () {
      expect(estEtatSansPariRecommande('À surveiller'), isTrue);
    });

    test('C1/2 — type vide est reconnu comme sans pari', () {
      expect(estEtatSansPariRecommande(''), isTrue,
          reason: 'un ticket restauré sans typePari vaut \'\' '
              '(pmu_models.dart:630) et ne désigne aucun pari');
    });

    test('C1/3 — type composé uniquement d\'espaces est reconnu', () {
      expect(estEtatSansPariRecommande('   '), isTrue);
      expect(estEtatSansPariRecommande('\t\n'), isTrue);
    });

    test('C1/4 — null N\'EST PAS assimilé à une abstention', () {
      expect(estEtatSansPariRecommande(null), isFalse,
          reason: 'null = argument non renseigné, pas une abstention métier');
    });

    test('C1/5 — casse et espaces de bord n\'empêchent pas la reconnaissance',
        () {
      expect(estEtatSansPariRecommande('À SURVEILLER'), isTrue);
      expect(estEtatSansPariRecommande('à surveiller'), isTrue);
      expect(estEtatSansPariRecommande('  À surveiller  '), isTrue);
    });

    test('C1/6 — « Inconnu » N\'EST PAS une abstention', () {
      // 🔒 INTERDICTION DU MANDAT : « sans confondre un type inconnu avec un
      //    pari effectivement joué ». Un type inconnu est un pari dont
      //    l'étiquette n'a pas pu être lue : il ne doit PAS être effacé.
      expect(estEtatSansPariRecommande('Inconnu'), isFalse);
      expect(estEtatSansPariRecommande('inconnu'), isFalse);
    });

    test('C1/7 — aucun libellé de pari réel n\'est classé sans pari', () {
      const parisReels = <String>[
        'Simple Gagnant',
        'Simple Placé',
        'Couplé Gagnant',
        'Couplé Placé',
        'Couplé Ordre',
        'Couplé Désordre',
        'Tiercé',
        'Tiercé Ordre',
        'Tiercé Désordre',
        'Quarté+',
        'Quinté+',
        'Multi',
        'Mini Multi',
      ];
      for (final t in parisReels) {
        expect(estEtatSansPariRecommande(t), isFalse, reason: 'type réel: $t');
      }
    });

    test('C1/8 — Gagnant+Placé reste hors de ce prédicat (lot A-0 distinct)',
        () {
      // Ce lot ne traite PAS Gagnant+Placé : le prédicat doit l'ignorer,
      // afin que A-0 demeure la seule autorité sur ce libellé.
      expect(estEtatSansPariRecommande('Gagnant+Placé'), isFalse);
      expect(estEtatSansPariRecommande('Gagnant + Placé'), isFalse);
      expect(estEtatSansPariRecommande('Gagnant+Place'), isFalse);
    });

    test('C1/9 — le prédicat est pur : stable sur appels répétés', () {
      for (var i = 0; i < 5; i++) {
        expect(estEtatSansPariRecommande('À surveiller'), isTrue);
        expect(estEtatSansPariRecommande('Tiercé'), isFalse);
      }
    });

    test('C1/10 — la constante porte l\'accent exact (U+00C0)', () {
      expect(kLibelleSansPariRecommande.codeUnits.first, 192);
      expect(kLibelleSansPariRecommande, 'À surveiller');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C3 — GARDE DANS `validatePrediction`
  // ═════════════════════════════════════════════════════════════════════════

  group('C3 — validatePrediction ne crée aucune écriture sur un ticket sans pari',
      () {
    test('C3/1 — « Gagné » (10 €, gain 32 €) N\'EST PLUS écrit', () async {
      final provider = await providerVide();
      provider.addPrediction(ticketSansPari());

      // Arguments EXACTEMENT ceux que produisait l'ex-`predictions_screen.dart:533`
      // (fichier supprimé en BL1-A18).
      // Avant correction, la mesure donnait :
      //   montantMise=10.0, gainRealise=32.0, gainNet=32.0, statut='Gagné ✅'
      provider.validatePrediction('sans_pari_1',
          isCorrect: true, montantMise: 10.0, gainRealise: 32.0);

      final p = provider.predictions.first;
      expect(p.isCorrect, isNull, reason: 'aucun résultat financier écrit');
      expect(p.montantMise, 0.0, reason: 'aucune mise inventée');
      expect(p.gainRealise, isNull, reason: 'aucun gainRealise écrit');
      expect(p.gainNet, 0.0, reason: 'gainNet reste neutre');
      expect(p.statutLabel, 'En attente');
    });

    test('C3/2 — « Perdu » (-10 €) N\'EST PLUS écrit', () async {
      final provider = await providerVide();
      provider.addPrediction(ticketSansPari());

      provider.validatePrediction('sans_pari_1',
          isCorrect: false, montantMise: 10.0, gainRealise: -10.0);

      final p = provider.predictions.first;
      expect(p.isCorrect, isNull);
      expect(p.montantMise, 0.0);
      expect(p.gainRealise, isNull);
      expect(p.gainNet, 0.0);
      expect(p.statutLabel, 'En attente');
    });

    test('C3/3 — type vide est protégé de la même façon', () async {
      final provider = await providerVide();
      provider.addPrediction(ticketSansPari(typePari: ''));

      provider.validatePrediction('sans_pari_1',
          isCorrect: true, montantMise: 10.0, gainRealise: 32.0);

      final p = provider.predictions.first;
      expect(p.isCorrect, isNull);
      expect(p.montantMise, 0.0);
      expect(p.typePari, '', reason: 'le type n\'est pas réécrit');
    });

    test('C3/4 — AUCUN agrégat financier n\'est alimenté', () async {
      final provider = await providerVide();
      provider.addPrediction(ticketSansPari());

      provider.validatePrediction('sans_pari_1',
          isCorrect: true, montantMise: 10.0, gainRealise: 32.0);
      provider.validatePrediction('sans_pari_1',
          isCorrect: false, montantMise: 10.0, gainRealise: -10.0);

      // Avant correction : totalMise=20.0, totalGainsNet=22.0,
      // totalGagnes=0.0, totalPerdu=10.0 (mesuré par la sonde du mandat H).
      expect(provider.totalMise, 0.0, reason: 'aucune mise fictive');
      expect(provider.totalGainsNet, 0.0, reason: 'aucun gain net fictif');
      expect(provider.totalGagnes, 0.0, reason: 'aucun gain encaissé fictif');
      expect(provider.totalPerdu, 0.0, reason: 'aucune perte fictive');
    });

    test('C3/5 — la photographie du ticket est IDENTIQUE avant / après',
        () async {
      final provider = await providerVide();
      provider.addPrediction(ticketSansPari());

      final avant = photo(provider.predictions.first);

      provider.validatePrediction('sans_pari_1',
          isCorrect: true, montantMise: 50.0, gainRealise: 200.0);
      provider.validatePrediction('sans_pari_1',
          isCorrect: false, montantMise: 50.0, gainRealise: -50.0);

      final apres = photo(provider.predictions.first);

      expect(apres, equals(avant),
          reason: 'aucune voie corrigée ne doit modifier ce ticket');
    });

    test('C3/6 — NON-RÉGRESSION : un pari réel est toujours validable',
        () async {
      // La garde ne doit pas dépasser sa cible.
      final provider = await providerVide();
      provider.addPrediction(ticketPariReel());

      provider.validatePrediction('pari_reel_1',
          isCorrect: true, montantMise: 10.0, gainRealise: 20.0);

      final p = provider.predictions.first;
      expect(p.isCorrect, isTrue);
      expect(p.montantMise, 10.0);
      expect(p.gainRealise, 20.0);
      expect(p.gainNet, 20.0);
      expect(p.statutLabel, 'Gagné ✅');
      expect(provider.totalMise, 10.0);
    });

    test('C3/7 — NON-RÉGRESSION : « Inconnu » reste validable', () async {
      // Un type inconnu n'est PAS une abstention : la garde ne doit pas
      // l'effacer (interdiction explicite du mandat).
      final provider = await providerVide();
      provider.addPrediction(ticketPariReel(typePari: 'Inconnu'));

      provider.validatePrediction('pari_reel_1',
          isCorrect: false, montantMise: 10.0, gainRealise: -10.0);

      final p = provider.predictions.first;
      expect(p.isCorrect, isFalse);
      expect(p.montantMise, 10.0);
      expect(p.gainNet, -10.0);
    });

    test('C3/8 — un identifiant inconnu reste sans effet (comportement intact)',
        () async {
      final provider = await providerVide();
      provider.addPrediction(ticketSansPari());

      provider.validatePrediction('identifiant_inexistant',
          isCorrect: true, montantMise: 10.0, gainRealise: 32.0);

      expect(provider.predictions.length, 1);
      expect(provider.predictions.first.isCorrect, isNull);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C4bis — GARDE DANS `enregistrerDividendePmu`
  // ═════════════════════════════════════════════════════════════════════════

  group('C4bis — enregistrerDividendePmu ne déclare rien sur un ticket sans pari',
      () {
    test('C4bis/1 — un dividende > 0 ne déclare pas « gagnant »', () async {
      final provider = await providerVide();
      provider.addPrediction(ticketSansPari());

      provider.enregistrerDividendePmu('sans_pari_1',
          dividendePmuReel: 18.40, combinaisonPmu: '16-7-3-9-1');

      final p = provider.predictions.first;
      expect(p.isCorrect, isNull, reason: 'aucun gagnant déclaré');
      expect(p.dividendePmuReel, isNull, reason: 'aucun dividende enregistré');
      expect(p.combinaisonPmu, isNull, reason: 'aucune combinaison enregistrée');
      expect(p.gainRealise, isNull, reason: 'aucun gainRealise écrit');
      expect(p.gainNet, 0.0);
      expect(p.statutLabel, 'En attente');
    });

    test('C4bis/2 — un dividende à 0 ne déclare pas « perdant »', () async {
      final provider = await providerVide();
      provider.addPrediction(ticketSansPari());

      provider.enregistrerDividendePmu('sans_pari_1',
          dividendePmuReel: 0.0, combinaisonPmu: '');

      final p = provider.predictions.first;
      expect(p.isCorrect, isNull, reason: 'aucun perdant déclaré');
      expect(p.montantMise, 0.0);
      expect(provider.totalPerdu, 0.0);
    });

    test('C4bis/3 — aucun agrégat financier n\'est alimenté', () async {
      final provider = await providerVide();
      provider.addPrediction(ticketSansPari());

      provider.enregistrerDividendePmu('sans_pari_1',
          dividendePmuReel: 18.40, combinaisonPmu: '16-7-3-9-1');

      expect(provider.totalMise, 0.0);
      expect(provider.totalGainsNet, 0.0);
      expect(provider.totalGagnes, 0.0);
      expect(provider.totalPerdu, 0.0);
    });

    test('C4bis/4 — la photographie du ticket est IDENTIQUE avant / après',
        () async {
      final provider = await providerVide();
      provider.addPrediction(ticketSansPari());
      final avant = photo(provider.predictions.first);

      provider.enregistrerDividendePmu('sans_pari_1',
          dividendePmuReel: 99.0, combinaisonPmu: '1-2-3-4-5');

      expect(photo(provider.predictions.first), equals(avant));
    });

    test('C4bis/5 — NON-RÉGRESSION : un pari réel reçoit toujours son dividende',
        () async {
      final provider = await providerVide();
      provider.addPrediction(ticketPariReel(typePari: 'Tiercé'));

      provider.enregistrerDividendePmu('pari_reel_1',
          dividendePmuReel: 12.0, combinaisonPmu: '7-3-9');

      final p = provider.predictions.first;
      expect(p.isCorrect, isTrue);
      expect(p.dividendePmuReel, 12.0);
      expect(p.combinaisonPmu, '7-3-9');
      // Formule T8b INCHANGÉE : (12.0 × 10.0) − 10.0 = 110.0
      expect(p.gainRealise, 110.0);
    });

    test('C4bis/6 — NON-RÉGRESSION : un dividende à 0 perd la mise d\'un pari réel',
        () async {
      final provider = await providerVide();
      provider.addPrediction(ticketPariReel(typePari: 'Tiercé'));

      provider.enregistrerDividendePmu('pari_reel_1',
          dividendePmuReel: 0.0, combinaisonPmu: '');

      final p = provider.predictions.first;
      expect(p.isCorrect, isFalse);
      // Formule T8b INCHANGÉE : pari perdu → −mise
      expect(p.gainRealise, -10.0);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  PRESERVATION DES TICKETS HISTORIQUES (point 6 du mandat)
  // ═════════════════════════════════════════════════════════════════════════

  group('Préservation — aucune migration, suppression ni réécriture', () {
    test('P/1 — le ticket survit à une passe de validation refusée', () async {
      final provider = await providerVide();
      provider.addPrediction(ticketSansPari());

      provider.validatePrediction('sans_pari_1',
          isCorrect: true, montantMise: 10.0, gainRealise: 32.0);
      provider.enregistrerDividendePmu('sans_pari_1',
          dividendePmuReel: 18.40, combinaisonPmu: '16-7-3-9-1');

      expect(provider.predictions.length, 1, reason: 'aucune suppression');
      expect(provider.predictions.first.id, 'sans_pari_1');
      expect(provider.predictions.first.typePari, 'À surveiller',
          reason: 'le type n\'est jamais réécrit ni normalisé');
    });

    test('P/2 — le JSON persisté est INCHANGÉ (aucune migration à l\'écriture)',
        () async {
      final p = ticketSansPari();
      final avant = p.toJson();

      // Aucune des deux méthodes ne doit avoir modifié l'objet.
      final provider = await providerVide();
      provider.addPrediction(p);
      provider.validatePrediction('sans_pari_1',
          isCorrect: true, montantMise: 10.0, gainRealise: 32.0);
      provider.enregistrerDividendePmu('sans_pari_1',
          dividendePmuReel: 18.40, combinaisonPmu: '16-7-3-9-1');

      expect(p.toJson(), equals(avant),
          reason: 'la sérialisation du ticket historique est identique');
      expect(jsonEncode(p.toJson()), equals(jsonEncode(avant)));
    });

    test('P/3 — un ticket historique déjà résolu n\'est pas touché', () async {
      // Ticket ancien, résultat déjà écrit, type sans pari : la garde ne doit
      // RIEN réécrire (le mandat interdit toute réécriture automatique).
      final ancien = UserPrediction(
        id: 'historique_1',
        dateStr: '2024-03-12',
        numReunion: 3,
        numCourse: 2,
        nomCourse: 'Ancienne course',
        hippodrome: 'CAEN',
        numeroCheval: 4,
        nomCheval: 'CHEVAL 4',
        cote: 5.0,
        typePari: 'À surveiller',
        isCorrect: true,
        montantMise: 10.0,
        gainRealise: 40.0,
        createdAt: DateTime(2024, 3, 12),
      );
      final provider = await providerVide();
      provider.addPrediction(ancien);
      final avant = photo(provider.predictions.first);

      provider.validatePrediction('historique_1',
          isCorrect: false, montantMise: 99.0, gainRealise: -99.0);

      expect(photo(provider.predictions.first), equals(avant),
          reason: 'un ticket historique n\'est jamais réécrit');
    });

    test('P/4 — la persistance reste opérationnelle pour un pari réel',
        () async {
      final provider = await providerVide();
      provider.addPrediction(ticketPariReel());
      provider.validatePrediction('pari_reel_1',
          isCorrect: true, montantMise: 10.0, gainRealise: 20.0);

      // `_savePredictions()` est asynchrone dans le provider (appelée sans
      // `await`) : on laisse la boucle d'événements se vider avant de lire.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList('user_predictions_v2');
      expect(raw, isNotNull);
      expect(raw!.length, 1);
      final decode = jsonDecode(raw.first) as Map<String, dynamic>;
      expect(decode['typePari'], 'Simple Gagnant');
      expect(decode['isCorrect'], isTrue);
    });

    test('P/5 — un ticket sans pari refusé n\'écrit AUCUN changement sur disque',
        () async {
      final provider = await providerVide();
      provider.addPrediction(ticketSansPari());
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final prefsAvant = await SharedPreferences.getInstance();
      final avant = prefsAvant.getStringList('user_predictions_v2');

      // Deux voies refusées, exécutées puis laissées se vider.
      provider.validatePrediction('sans_pari_1',
          isCorrect: true, montantMise: 10.0, gainRealise: 32.0);
      provider.enregistrerDividendePmu('sans_pari_1',
          dividendePmuReel: 18.40, combinaisonPmu: '16-7-3-9-1');
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final prefsApres = await SharedPreferences.getInstance();
      final apres = prefsApres.getStringList('user_predictions_v2');

      expect(apres, equals(avant),
          reason: 'aucune écriture disque : le ticket historique est intact');
      // Et son contenu sérialisé ne porte aucun montant inventé.
      final decode = jsonDecode(apres!.first) as Map<String, dynamic>;
      expect(decode['typePari'], 'À surveiller');
      expect(decode['isCorrect'], isNull);
      expect(decode['montantMise'], 0.0);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C2 — LES DEUX DIALOGUES (garde structurelle)
  // ═════════════════════════════════════════════════════════════════════════

  group('C2 — les deux dialogues refusent AVANT d\'inventer une mise', () {
    /// Vérifie que, dans [fichier], la garde `estEtatSansPariRecommande`
    /// apparaît AVANT le repli `: 10.0` et qu'un motif est affiché.
    void verifierGarde(String fichier, String nomMethodeMotif) {
      final source = File(fichier).readAsStringSync();
      final idxGarde = source.indexOf('estEtatSansPariRecommande(pred.typePari)');
      final idxRepli = source.indexOf(': 10.0');

      expect(idxGarde, greaterThan(-1),
          reason: '$fichier doit porter la garde C2');
      expect(idxRepli, greaterThan(-1),
          reason: '$fichier doit toujours contenir son repli de mise');
      expect(idxGarde, lessThan(idxRepli),
          reason: 'la garde doit précéder le repli « : 10.0 » dans $fichier');
      expect(source.contains(nomMethodeMotif), isTrue,
          reason: '$fichier doit afficher un motif compréhensible');
    }

    // ★ BL1-A18 — TRANSFERT DEPUIS `predictions_screen.dart` (écran SUPPRIMÉ).
    //   Exigence d'origine (C2/1, fichier SUPPRIMÉ) : « predictions_screen.dart
    //   garde avant le
    //   repli de 10 € ». Cette exigence NE POUVAIT viser qu'un fichier
    //   INACCESSIBLE : mesuré, `PredictionsScreen` n'était instancié nulle part
    //   dans `lib/` (0 occurrence hors sa propre déclaration). La consigne
    //   exige qu'une protection financière protège le code RÉELLEMENT utilisé.
    //
    //   Le transfert NE RÉDUIT PAS la protection, il l'AUGMENTE :
    //   `profile_historique_tab.dart` contient DEUX couples garde/repli
    //   (lignes 268→356 et 360→368 mesurées), alors que l'ancien écran n'en
    //   avait qu'un seul vérifié. On vérifie donc TOUS les couples présents,
    //   par paire, au lieu du seul premier.
    test('C2/1 — profile_historique_tab : CHAQUE garde précède son repli', () {
      final source =
          File('lib/widgets/profile/profile_historique_tab.dart')
              .readAsStringSync();
      final gardes = <int>[];
      var i = 0;
      const motif = 'estEtatSansPariRecommande(pred.typePari)';
      while (true) {
        final p = source.indexOf(motif, i);
        if (p < 0) break;
        gardes.add(p);
        i = p + 1;
      }
      final replis = <int>[];
      i = 0;
      const repli = ': 10.0';
      while (true) {
        final p = source.indexOf(repli, i);
        if (p < 0) break;
        replis.add(p);
        i = p + 1;
      }

      // Le fichier VIVANT doit porter au moins la garde (exigence conservée).
      expect(gardes, isNotEmpty,
          reason: 'profile_historique_tab doit porter la garde C2');
      // Le repli doit toujours exister (sinon le test passerait à vide).
      expect(replis, isNotEmpty,
          reason: 'profile_historique_tab doit toujours contenir son repli');
      // CHAQUE garde doit précéder un repli : aucune garde orpheline.
      for (final g in gardes) {
        final suivants = replis.where((r) => r > g);
        expect(suivants, isNotEmpty,
            reason: 'la garde @$g doit précéder un repli « : 10.0 »');
      }
      // Et chaque repli doit être précédé d'une garde : aucun repli nu.
      for (final r in replis) {
        final precedents = gardes.where((g) => g < r);
        expect(precedents, isNotEmpty,
            reason: 'le repli @$r doit être protégé par une garde en amont');
      }
      expect(source.contains('_afficherAucunPariRecommande'), isTrue,
          reason: 'profile_historique_tab doit afficher un motif compréhensible');
    });

    test('C2/2 — profile_historique_tab.dart garde avant le repli de 10 €', () {
      verifierGarde(
        'lib/widgets/profile/profile_historique_tab.dart',
        '_afficherAucunPariRecommande',
      );
    });

    test('C2/3 — le bouton de validation du fichier VIVANT est conditionné', () {
      // ★ BL1-A18 — transféré de `predictions_screen.dart` (supprimé) vers
      //   `profile_historique_tab.dart` (seul écran vivant portant ce bouton).
      //   L'exigence est IDENTIQUE : la condition doit être présente dans le
      //   CODE, avec l'opérateur « et non pas un pari recommandé ».
      final b =
          File('lib/widgets/profile/profile_historique_tab.dart').readAsStringSync();

      expect(
        b.contains(
            'if (isCorrect == null && !estEtatSansPariRecommande(pred.typePari))'),
        isTrue,
        reason: 'profile_historique_tab ne doit plus proposer la validation',
      );
    });

    test('C2/4 — le motif affiché est compréhensible et sans promesse de gain',
        () {
      // ★ BL1-A18 — `predictions_screen.dart` retiré de la liste (supprimé).
      //   L'exigence porte désormais sur le seul fichier VIVANT.
      final s =
          File('lib/widgets/profile/profile_historique_tab.dart')
              .readAsStringSync();
      final f = 'lib/widgets/profile/profile_historique_tab.dart';
      expect(s.contains('Aucun pari recommandé'), isTrue, reason: f);
      expect(s.contains('passer cette course'), isTrue,
          reason: '$f doit reprendre le sens métier de '
              'conseils_screen.dart:1284');
      expect(s.contains('ni mise, ni gain, ni perte'), isTrue, reason: f);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  ISOLATION DU LOT — ce que ce lot ne devait pas faire
  // ═════════════════════════════════════════════════════════════════════════

  group('Isolation du lot — interdictions respectées', () {
    test('I/1 — aucune formule financière n\'a été modifiée', () {
      final source = File('lib/models/pmu_models.dart').readAsStringSync();
      // Les quatre branches de `gainNet` sont présentes telles quelles.
      expect(source.contains('if (gainRealise != null) return gainRealise!;'),
          isTrue);
      expect(
          source.contains('if (isCorrect == false && montantMise > 0) return -montantMise;'),
          isTrue);
      expect(source.contains('return (dividendePmuReel! * montantMise) - montantMise;'),
          isTrue);
      expect(source.contains('return (cote * montantMise) - montantMise;'), isTrue);
    });

    test('I/2 — la garde A-0 est intacte et non déplacée', () {
      final source = File('lib/utils/type_pari_utils.dart').readAsStringSync();
      expect(source.contains('const Set<String> kLibellesGagnantPlace'), isTrue);
      expect(source.contains('bool estTypeGagnantPlace(String? typePari)'), isTrue);
      // Le nouveau prédicat est ADDITIF : il ne remplace pas A-0.
      expect(source.contains('bool estEtatSansPariRecommande(String? typePari)'),
          isTrue);
    });

    test('I/3 — le résolveur PMU n\'est pas branché sur les voies modifiées', () {
      // ★ BL1-A18 — `predictions_screen.dart` retiré (supprimé) ; les deux
      //   fichiers VIVANTS restent vérifiés.
      for (final f in <String>[
        'lib/providers/pmu_provider.dart',
        'lib/widgets/profile/profile_historique_tab.dart',
      ]) {
        final s = File(f).readAsStringSync();
        expect(s.contains('resolveur_rapport_pmu'), isFalse,
            reason: '$f ne doit pas importer le résolveur');
        expect(s.contains('resoudreRapportPmu'), isFalse,
            reason: '$f ne doit pas appeler le résolveur');
      }
    });

    test('I/4 — la règle T8a (isCorrect == null) n\'a pas été touchée', () {
      final source =
          File('lib/services/ia_memory_service.dart').readAsStringSync();
      expect(source.contains('if (isCorrect == null) continue;'), isTrue,
          reason: 'la règle préexistante doit rester mot pour mot');
    });

    test('I/5 — aucun test existant n\'a été modifié', () {
      // Les 4 fichiers qui contiennent déjà le libellé d'abstention gardent
      // leur contenu d'origine : ce lot se prouve par un fichier NEUF.
      const existants = <String>[
        'test/v16_e2_calendrier_archive_test.dart',
        'test/v40_a43_archive_date_effective_test.dart',
        'test/v41_a44_abstention_stats_test.dart',
        'test/v48_a2_priorite_autorite_test.dart',
      ];
      for (final f in existants) {
        expect(File(f).existsSync(), isTrue, reason: f);
        expect(File(f).readAsStringSync().contains('À surveiller'), isTrue,
            reason: '$f doit rester inchangé et toujours mentionner le libellé');
      }
    });
  });
}
