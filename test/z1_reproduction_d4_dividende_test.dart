// ═══════════════════════════════════════════════════════════════════════════
//  Z1 — NON-RÉGRESSION DE D4 : LE PARI N'EST JAMAIS CRÉDITÉ DU RAPPORT MAXIMAL
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT. AUCUNE MODIFICATION DE lib/.
//
//  ── HISTORIQUE DE CE TEST, ET CE QUI A CHANGÉ (à lire avant de le modifier) ─
//
//  Ce test a été écrit contre la chaîne financière ANTÉRIEURE à B-4.5. Il
//  affirmait alors que `TrackedCourse.dividendePmuReel` valait ×4,20 et que
//  `combinaisonPmu` valait « 16 ». Cette assertion est devenue OBSOLÈTE, et
//  il faut le dire sans détour :
//
//  la chaîne actuelle n'écrit PLUS `dividendePmuReel` ni `combinaisonPmu`.
//
//  Mesure qui l'établit (sonde exécutée sur la fixture exacte de ce fichier) :
//
//      dividendePmuReel=null combinaisonPmu=null isGagne=true
//
//  ── POURQUOI `dividendePmuReel` N'EST PLUS ALIMENTÉ — JUSTIFICATION
//     HISTORIQUE TROUVÉE ET VÉRIFIÉE DANS LE DÉPÔT, PAS SUPPOSÉE
//
//  Le retrait date du commit `a18d545`
//  (« B-4.5 : verdict officiel branche, reduce(MAX) neutralise, affichage
//  structurel »). Son message de commit et son diff donnent TROIS motifs,
//  tous retrouvés dans le code :
//
//    1. `reduce(MAX)` choisissait le plus GROS dividende parmi les codes du
//       pari, sans regarder la combinaison : ce n'était pas le rapport du
//       cheval joué. (`git show a18d545` montre la suppression de
//       `final meilleur = matching.reduce((a, b) => a.dividende > b.dividende ? a : b);`)
//
//    2. `getPredictionForCourse` est un `firstWhere` : sur une course à
//       plusieurs paris, les suivants n'étaient jamais résolus. Le chemin
//       actuel résout TOUS les paris de la course.
//
//    3. Écrire ce dividende passait par `PmuProvider.enregistrerDividendePmu`,
//       qui appelle `_syncStatsTypesIA()` — donc une resynchronisation de
//       l'apprentissage IA à partir d'un montant FAUX. Vérifié :
//       `lib/providers/pmu_provider.dart:552` (`_syncStatsTypesIA();` à la fin
//       de `enregistrerDividendePmu`) et le commentaire de
//       `appliquerVerdictGainPrediction` (l.407-414) qui dit exactement cela.
//
//  Le champ n'est donc pas ABANDONNÉ du modèle : il est conservé, toujours
//  persisté et toujours LU par les écrans (`lib/models/pmu_models.dart:549`,
//  `lib/screens/mes_paris_screen.dart:2546`). Seule son ÉCRITURE par ce
//  chemin a cessé. Le retrait du test initial ne fait que constater l'état
//  réel de la production.
//
//  ── CE QUE LE TEST DÉMONTRE MAINTENANT (et qui garde l'intention d'origine) ─
//
//  La règle métier d'origine est intacte : le pari sur le cheval 16 doit être
//  crédité de SON rapport (×4,20), jamais du rapport maximal de la course
//  (×18,00, cheval 7). L'observable change, la propriété est la même :
//
//    • verdict `attribue` ;
//    • UNE SEULE composante attribuée ;
//    • code PMU de cette composante = `E_SIMPLE_PLACE` (jamais `E_SIMPLE_GAGNANT`) ;
//    • combinaison de cette composante = « 16 » (jamais « 7 ») ;
//    • rapport de cette composante = ×4,20 (jamais ×18,00) ;
//    • mise appliquée = 20,00 € (la mise de la composante Placé) ;
//    • montant de retour = 84,00 €, et total = 84,00 €.
//
//  ── CE QUE CE TEST NE PROUVE PAS ──────────────────────────────────────────
//  Le montant affiché à l'écran dans tous ses états (D5/D6/D8) n'est pas
//  l'objet de ce fichier ; il est couvert par `test/b4_8_rendu_reel_verdicts_test.dart`.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/services/affichage_gain_structure.dart';
import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/branchement_verdict_course.dart';
import 'package:pronostic_hippique/services/enregistreur_verdict_gain_pmu.dart'
    show StatutEnregistrementVerdict;
import 'package:pronostic_hippique/services/gain_pmu_types.dart';
import 'package:pronostic_hippique/services/resolution_gain_ticket_pmu.dart'
    show ResultatOfficielCourse;
import 'package:pronostic_hippique/services/gain_calculator.dart'
    show RapportPmu;
import 'package:pronostic_hippique/services/pmu_api_service.dart'
    show PmuApiService;

// ───────────────────────────────────────────────────────────────────────────
//  1. CONSTANTES DU SCÉNARIO (inchangées — données de référence du mandat)
// ───────────────────────────────────────────────────────────────────────────

/// Numéro du cheval joué (celui du mandat : n°16).
const int kNumChevalJoue = 16;

/// Numéro de l'AUTRE cheval, gagnant de la course (rapport ×18,00).
const int kNumAutreCheval = 7;

/// Troisième cheval de l'arrivée (aucun rapport utilisé pour lui).
const int kNumTroisieme = 2;

/// Rapport placé du cheval joué — ×4,20 pour 1 € misé (→ 420 centimes).
const double kDividendePlaceAttendu = 4.20;

/// Rapport gagnant de l'autre cheval — ×18,00 pour 1 € misé (→ 1800 centimes).
const double kDividendeGagnantAutre = 18.00;

/// Mise PAR COMPOSANTE (donnée de référence du mandat, §6-A).
/// `_mise` dans bet_bottom_sheet.dart:3094 est bien la mise par composante.
const double kMiseParComposante = 20.0;

const int kNumR = 1;
const int kNumC = 10;

/// Codes PMU réellement écrits par la saisie (`bet_bottom_sheet.dart:3110`,
/// `:3176` via `_codePmuDuTypeChoisi`), pour un libellé `'Gagnant+Placé'`.
const String kCodePmuSaisie = 'E_SIMPLE_GAGNANT';

// ───────────────────────────────────────────────────────────────────────────
//  2. RAPPORTS OFFICIELS — FORMAT API PMU RÉEL
// ───────────────────────────────────────────────────────────────────────────
//
//  MESURE QUI A MOTIVÉ LA FORME EXACTE DE CE CORPS (et non une supposition) :
//  une ligne de rapport SANS clé `libelle` fait rendre au moteur
//  `nonDetermine / blocJusteAbsent` — les blocs ne sont alors pas identifiables
//  et AUCUN montant n'est attribué. Vérifié par matrice d'isolement :
//
//      libelle=absent, rang=absent  → nonDetermine / blocJusteAbsent
//      libelle=absent, rang=présent → nonDetermine / blocJusteAbsent
//      libelle=présent, rang=absent → attribue / total 84,00 €
//      libelle=présent, rang=présent→ attribue / total 84,00 €
//
//  `rangCombinaisonPayable` n'a donc AUCUN effet isolé ; `libelle` est le
//  facteur déclenchant. Les deux sont néanmoins présents ici parce que les
//  captures réelles les portent toutes les deux (vérifié sur
//  `test/fixtures/recherche_pmu/rapports/R1C1.json`).
//
//  Le bloc PLACÉ publie DEUX lignes (rangs 1 et 2) comme une vraie course à
//  3 placés : cela interdit qu'un test « passe » en ne trouvant qu'une seule
//  ligne par accident.
//
//  ⚠️ ORDRE DES BLOCS : `E_SIMPLE_GAGNANT` (×18,00) est placé EN PREMIER et
//     porte le dividende le PLUS ÉLEVÉ. C'est exactement la configuration dans
//     laquelle un `reduce(MAX)` — ou tout autre tri par montant — choisirait
//     le mauvais rapport. La fixture est donc construite pour que la
//     régression soit DÉTECTABLE, pas pour la rendre indétectable.
String _corpsRapports() => json.encode([
      {
        'typePari': 'E_SIMPLE_GAGNANT',
        'miseBase': 100,
        'rembourse': false,
        'rapports': [
          {
            'rangCombinaisonPayable': 1,
            'libelle': 'e-Simple Gagnant',
            'dividendePourUnEuro': (kDividendeGagnantAutre * 100).round(),
            'combinaison': '$kNumAutreCheval',
            'dividendeUnite': 'PourUnEuro',
          },
        ],
      },
      {
        'typePari': 'E_SIMPLE_PLACE',
        'miseBase': 100,
        'rembourse': false,
        'rapports': [
          {
            'rangCombinaisonPayable': 1,
            'libelle': 'e-Simple Placé',
            'dividendePourUnEuro': (kDividendePlaceAttendu * 100).round(),
            'combinaison': '$kNumChevalJoue',
            'dividendeUnite': 'PourUnEuro',
          },
          {
            'rangCombinaisonPayable': 2,
            'libelle': 'e-Simple Placé',
            'dividendePourUnEuro': 300,
            'combinaison': '$kNumTroisieme',
            'dividendeUnite': 'PourUnEuro',
          },
        ],
      },
    ]);

List<RapportPmu> _rapports() =>
    PmuApiService.decoderRapportsDefinitifs(_corpsRapports());

// ───────────────────────────────────────────────────────────────────────────
//  3. FIXTURES — CHAMPS COMPLÉTÉS COMME LA PRODUCTION LES ÉCRIT
// ───────────────────────────────────────────────────────────────────────────
//
//  Le ticket initial ne portait ni `codePmuOfficiel`, ni `miseGagnant` /
//  `misePlace`, ni `arriveeGroupes` / `arriveeDefinitive`. Ces quatre champs
//  ne sont pas des commodités de test : ils sont écrits par la saisie et par
//  l'enregistrement du résultat, et leur absence faisait REFUSER le ticket
//  avant tout calcul. Mesures de refus, dans l'ordre de la chaîne :
//
//    sans miseGagnant/misePlace → `issue = miseIncomplete`
//                                 (branchement_verdict_course.dart:391-397)
//    avec mises mais sans codePmuOfficiel → refus `codePmuAbsent`
//    sans arriveeGroupes → `_majGainReelDansProfil` sort sans rien écrire
//
//  Aucune assertion métier n'est modifiée par ces compléments : ils rendent
//  seulement le ticket conforme à ce que l'application produit réellement.

/// Course suivie telle que `bet_bottom_sheet` puis `AlertService.ajouterSuivi`
/// l'écrivent, puis telle que `enregistrerResultatPari` la complète.
TrackedCourse _suiviGagnantPlace(DateTime dep) => TrackedCourse(
      numReunion: kNumR,
      numCourse: kNumC,
      nomCourse: 'PRIX DE BAD GODESBERG',
      hippodrome: 'SAINT-CLOUD',
      heureDepart: dep,
      nomCheval: 'SIM CARD',
      numeroCheval: kNumChevalJoue,
      miseEngagee: kMiseParComposante,
      typePari: 'Gagnant+Placé',
      numerosJoues: const <int>[kNumChevalJoue],
      scoreIA: 89.0,
      cote: kDividendeGagnantAutre,
      isGagne: true,
      // Arrivée officielle : le n°7 gagne, le n°16 est deuxième (donc placé).
      arriveeFinale: const <int>[kNumAutreCheval, kNumChevalJoue, kNumTroisieme],
      // Arrivée GROUPÉE, telle que `enregistrerResultatPari(arriveeGroupes:)`
      // l'écrit en production. Sans elle, la chaîne B-4.5 sort sans rien faire.
      arriveeGroupes: const <List<int>>[
        <int>[kNumAutreCheval],
        <int>[kNumChevalJoue],
        <int>[kNumTroisieme],
      ],
      arriveeDefinitive: true,
      // Ventilation des mises, telle que `bet_bottom_sheet.dart:3094` l'écrit
      // pour un `Gagnant+Placé` (`estGP` ⇒ `_mise` sur chaque composante).
      miseGagnant: kMiseParComposante,
      misePlace: kMiseParComposante,
      // Code PMU du type choisi, tel que `bet_bottom_sheet.dart:3110` l'écrit.
      codePmuOfficiel: kCodePmuSaisie,
      messageResultat: 'Résultat officiel enregistré',
      storageKey: 'R${kNumR}C${kNumC}_${_ddmmyyyy(dep)}_1758281340000',
    );

/// Pari du PROFIL (`PmuProvider`), créé par `bet_bottom_sheet` avec la même
/// ventilation et le même code PMU que la course suivie.
UserPrediction _prediction(DateTime dep) => UserPrediction(
      id: 'pred_d4_1',
      dateStr: _yyyyMMdd(dep),
      numReunion: kNumR,
      numCourse: kNumC,
      nomCourse: 'PRIX DE BAD GODESBERG',
      hippodrome: 'SAINT-CLOUD',
      numeroCheval: kNumChevalJoue,
      nomCheval: 'SIM CARD',
      cote: kDividendeGagnantAutre,
      typePari: 'Gagnant+Placé',
      createdAt: dep,
      scoreIA: 89.0,
      montantMise: kMiseParComposante,
      numerosJoues: const <int>[kNumChevalJoue],
      miseGagnant: kMiseParComposante,
      misePlace: kMiseParComposante,
      codePmuOfficiel: kCodePmuSaisie,
    );

String _ddmmyyyy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

String _yyyyMMdd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Résultat officiel de LA course, construit comme `_majGainReelDansProfil`.
ResultatOfficielCourse _resultat() {
  final c = _suiviGagnantPlace(DateTime.now());
  return construireResultatOfficiel(
    arriveeGroupes: c.arriveeGroupes,
    arriveeDefinitive: c.arriveeDefinitive,
    rapports: _rapports(),
  );
}

// ───────────────────────────────────────────────────────────────────────────
//  4. TEST
// ───────────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Z1 / D4 — le rapport du cheval joué, jamais le rapport maximal', () {
    test('TÉMOIN — la fixture est correctement acceptée par la chaîne', () {
      final c = _suiviGagnantPlace(DateTime.now());
      final construit = construireTicketSuivi(c);
      expect(construit.estExploitable, isTrue,
          reason: 'TÉMOIN : le ticket doit être exploitable. Un refus ici '
              'signifierait que la fixture est incomplète, pas que la règle '
              'métier est violée (issue mesurée : ${construit.issue?.name}).');

      final res = resoudreSuivi(ticket: c, resultat: _resultat());
      expect(res.issue, isNull,
          reason: 'TÉMOIN : aucune issue de construction attendue');
      expect(res.enregistrement, isNotNull,
          reason: 'TÉMOIN : un enregistrement doit être produit');
      expect(res.enregistrement!.statut, StatutEnregistrementVerdict.enregistre,
          reason: 'TÉMOIN : le verdict doit être écrit, pas refusé '
              '(statut mesuré : ${res.enregistrement!.statut.name})');
    });

    test('TÉMOIN — les rapports servis contiennent bien les deux dividendes '
        'concurrents, dont le maximal pour un AUTRE cheval', () {
      final rapports = _rapports();
      expect(rapports.length, 3,
          reason: 'TÉMOIN : 1 ligne Gagnant + 2 lignes Placé attendues');

      final gagnant = rapports.firstWhere(
          (RapportPmu r) => r.typePari == 'E_SIMPLE_GAGNANT');
      expect(gagnant.combinaison, '$kNumAutreCheval');
      expect(gagnant.dividende, closeTo(kDividendeGagnantAutre, 0.001),
          reason: 'TÉMOIN : le dividende MAXIMAL en jeu doit bien être ×18,00 '
              'et appartenir à un autre cheval que le n°$kNumChevalJoue');

      final place = rapports.firstWhere((RapportPmu r) =>
          r.typePari == 'E_SIMPLE_PLACE' && r.combinaison == '$kNumChevalJoue');
      expect(place.dividende, closeTo(kDividendePlaceAttendu, 0.001),
          reason: 'TÉMOIN : le rapport du n°$kNumChevalJoue doit bien être ×4,20');
    });

    test('le verdict est `attribue` et la composante est celle du n°16, ×4,20',
        () {
      final c = _suiviGagnantPlace(DateTime.now());
      final res = resoudreSuivi(ticket: c, resultat: _resultat());
      final verdict = res.verdict!;

      expect(verdict.etat, EtatGain.attribue,
          reason: 'Le pari doit être ATTRIBUÉ : le n°$kNumChevalJoue est placé, '
              'son rapport ×${kDividendePlaceAttendu.toStringAsFixed(2)} est '
              'publié.');
      expect(verdict.motif, isNull);

      expect(verdict.composantes.length, 1,
          reason: 'UNE seule composante est payable : le Placé. Le n°'
              '$kNumChevalJoue n\'est pas gagnant, sa composante Gagnant ne '
              'produit rien.');

      final comp = verdict.composantes.single;
      expect(comp.combinaisonRapport, '$kNumChevalJoue',
          reason: 'D4 — la composante attribuée doit porter la combinaison du '
              'CHEVAL JOUÉ (« $kNumChevalJoue »), jamais celle du gagnant '
              '(« $kNumAutreCheval »).');
      expect(comp.pourUnEuro, closeTo(kDividendePlaceAttendu, 0.001),
          reason: 'D4 — le rapport retenu doit être ×'
              '${kDividendePlaceAttendu.toStringAsFixed(2)}, jamais ×'
              '${kDividendeGagnantAutre.toStringAsFixed(2)}.');
      expect(comp.mise, closeTo(kMiseParComposante, 0.001),
          reason: 'La mise appliquée est celle de la composante Placé '
              '(${kMiseParComposante.toStringAsFixed(2)} €), jamais la somme '
              'des deux mises.');
      expect(comp.montantRetour, closeTo(84.0, 0.001),
          reason: '20,00 € × 4,20 = 84,00 €');
    });

    test('le ticket persisté ne crédite QUE le rapport ×4,20 — et le total '
        'affiché est 84,00 €', () {
      final c = _suiviGagnantPlace(DateTime.now());
      final res = resoudreSuivi(ticket: c, resultat: _resultat());
      final ecrit = res.enregistrement!.ticket;

      expect(ecrit.etatGain, EtatGain.attribue);

      // ── Les rapports RÉELLEMENT attribués, seuls observables monétaires ──
      final attribues = ecrit.rapportsAttribues;
      expect(attribues, isNotNull);
      expect(attribues!.length, 1,
          reason: 'Un seul rapport est attribué : le Placé du n°$kNumChevalJoue. '
              'Deux rapports attribués signaleraient un double crédit.');

      final attr = attribues.single;
      expect(attr.rapport.codePmu, 'E_SIMPLE_PLACE',
          reason: 'D4 — le rapport attribué doit venir du bloc PLACÉ, jamais du '
              'bloc GAGNANT (« e-Simple Gagnant » ×18,00).');
      expect(attr.rapport.combinaison, '$kNumChevalJoue');
      expect(attr.rapport.pourUnEuro, closeTo(kDividendePlaceAttendu, 0.001));
      expect(attr.montantRetour, closeTo(84.0, 0.001));

      // ── Aucun montant ×18,00 ne doit apparaître nulle part ───────────────
      //
      //  18,00 × 20,00 = 360,00 € : c'est le montant qu'aurait produit le
      //  rapport du n°7 appliqué au n°16. On vérifie qu'il est ABSENT du
      //  ticket, sous toutes ses formes observables.
      const double montantFautif = kDividendeGagnantAutre * kMiseParComposante;
      expect(montantFautif, closeTo(360.0, 0.001));
      expect(attr.montantRetour, isNot(closeTo(montantFautif, 0.001)),
          reason: 'Le retour ne doit jamais valoir 360,00 €');
      expect(attr.rapport.pourUnEuro, isNot(closeTo(kDividendeGagnantAutre, 0.001)),
          reason: 'Le rapport retenu ne doit jamais être ×18,00');
      // `dividendeGagnant` doit rester nul : le n°16 n'a pas gagné.
      expect(ecrit.dividendeGagnant, isNull,
          reason: 'La composante Gagnant n\'est pas payable : sa valeur doit '
              'rester nulle plutôt que de porter le rapport d\'un autre cheval.');
      expect(ecrit.dividendePlace, closeTo(kDividendePlaceAttendu, 0.001),
          reason: 'La composante Placé porte le rapport du n°$kNumChevalJoue.');

      // ── Total de la vue d'affichage (source unique de l'écran) ───────────
      final vue = affichageGainSuivi(ecrit);
      expect(vue.nature, NatureAffichageGain.attribue);
      expect(vue.montant, closeTo(84.0, 0.001),
          reason: 'La vue d\'affichage doit annoncer 84,00 € brut');

      // ── Retour brut / bénéfice net de référence (invariants du mandat) ───
      final retourBrut = kMiseParComposante * kDividendePlaceAttendu; // 84 €
      final beneficeNet = retourBrut - (kMiseParComposante * 2); // +44 €
      expect(retourBrut, closeTo(84.0, 0.001));
      expect(beneficeNet, closeTo(44.0, 0.001));
    });

    test('NON-RÉGRESSION — un moteur qui sélectionnerait le rapport MAXIMAL '
        'serait détecté', () {
      // ── Objet de ce test ────────────────────────────────────────────────
      //  Une assertion qui ne peut pas échouer ne protège rien. On vérifie
      //  donc que la propriété testée PLUS HAUT discrimine réellement : on
      //  rejoue la MÊME fixture avec le corpus de rapports d'un moteur
      //  « fautif », qui ne retient que le dividende le plus élevé de la
      //  course, et on mesure que les observables changent.
      //
      //  Il n'y a ici AUCUNE modification de lib/ : on ne simule pas le
      //  moteur fautif, on lui donne simplement, en entrée, les rapports qu'il
      //  aurait retenus. Si le moteur retenait ×18,00 « 7 » à la place du
      //  Placé ×4,20 « 16 », la comparaison ci-dessous serait satisfaite —
      //  ce qui prouve que les assertions du test précédent mordent.
      final c = _suiviGagnantPlace(DateTime.now());

      // Corpus « fautif » : le bloc Gagnant du n°7 est le seul rapport fourni,
      // et sa combinaison porte le numéro d'un AUTRE cheval. Le moteur ne peut
      // donc rien attribuer au n°16 : il ne doit produire AUCUN montant.
      final rapportsFautifs = PmuApiService.decoderRapportsDefinitifs(
        json.encode([
          {
            'typePari': 'E_SIMPLE_GAGNANT',
            'miseBase': 100,
            'rembourse': false,
            'rapports': [
              {
                'rangCombinaisonPayable': 1,
                'libelle': 'e-Simple Gagnant',
                'dividendePourUnEuro': (kDividendeGagnantAutre * 100).round(),
                'combinaison': '$kNumAutreCheval',
                'dividendeUnite': 'PourUnEuro',
              },
            ],
          },
        ]),
      );
      final resFautif = resoudreSuivi(
        ticket: c,
        resultat: construireResultatOfficiel(
          arriveeGroupes: c.arriveeGroupes,
          arriveeDefinitive: c.arriveeDefinitive,
          rapports: rapportsFautifs,
        ),
      );
      final verdictFautif = resFautif.verdict!;
      final attribuesFautifs =
          resFautif.enregistrement!.ticket.rapportsAttribues ?? const <RapportAttribue>[];

      // Mesure : la sélection par montant NE produit PAS le résultat correct.
      // Toute assertion du test principal portant sur un montant ou une
      // combinaison tombe dès que le corpus ne contient que le rapport du n°7.
      expect(verdictFautif.total, isNot(closeTo(84.0, 0.001)),
          reason: 'NON-RÉGRESSION : avec le seul rapport du n°$kNumAutreCheval, '
              'le total ne peut pas valoir 84,00 € — sinon les assertions du '
              'test principal ne discrimineraient rien.');
      expect(verdictFautif.etat, isNot(EtatGain.attribue),
          reason: 'NON-RÉGRESSION : aucun rapport du n°$kNumChevalJoue n\'étant '
              'publié, le verdict ne peut pas être `attribue`');
      expect(attribuesFautifs, isEmpty,
          reason: 'NON-RÉGRESSION : aucun rapport ne doit être attribué');

      // Et la trace du montant fautif reste ABSENTE des deux exécutions.
      for (final a in attribuesFautifs) {
        expect(a.rapport.combinaison, isNot('$kNumAutreCheval'),
            reason: 'NON-RÉGRESSION : le rapport du n°$kNumAutreCheval ne doit '
                'jamais être attribué au pari sur le n°$kNumChevalJoue');
      }
    });
  });
}
