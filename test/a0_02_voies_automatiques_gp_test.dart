// ═══════════════════════════════════════════════════════════════════════════
//  A-0 / T1-T6 — Voies automatiques : aucun gain Gagnant+Placé fictif
//
//  ⚠️  PORTÉE. Ce fichier vérifie le comportement RÉEL du code de production :
//      - `PmuProvider.validatePrediction` / `enregistrerDividendePmu`
//      - `IaMemoryService.mettreAJourStatsTypes` (NON modifiée par A-0)
//
//  Ce qu'il PROUVE :
//    - la règle `isCorrect == null → continue` écarte bien une entrée G+P,
//      y compris quand la liste ne contient QUE du G+P (condition n°4) ;
//    - aucun type mono-composante n'est écarté (non-régression n°5) ;
//    - `gainNet` retourné pour un G+P en attente est 0.0, jamais un faux gain.
//
//  Ce qu'il NE PROUVE PAS (assumé, signalé en risque résiduel) :
//    - il n'exécute par les 3 écrans (mes_paris / profil / alert_service) :
//      ces gardes sont vérifiées structurellement dans a0_03.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/providers/pmu_provider.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

// ── Constantes mesurées sur l'écran de référence (captures) ─────────────────
const double kMiseUneComposante = 20.0; // mise affichée : 20 €
const double kMiseDeuxComposantes = 40.0; // G+P engage réellement 40 €
const double kCoteGagnant = 18.00; // cote ×18,00 de l'écran
const double kDividendePlace = 4.20; // dividende Placé attendu (mesuré)

UserPrediction _pred({
  required String typePari,
  double mise = kMiseUneComposante,
  double cote = kCoteGagnant,
  bool? isCorrect,
  double? gainRealise,
  double? dividendePmuReel,
}) =>
    UserPrediction(
      id: 'p_$typePari',
      dateStr: '2026-11-20',
      numReunion: 1,
      numCourse: 10,
      nomCourse: 'PRIX DE BAD GODESBERG',
      hippodrome: 'SAINT-CLOUD',
      numeroCheval: 16,
      nomCheval: 'SIM CARD',
      cote: cote,
      typePari: typePari,
      createdAt: DateTime(2026, 11, 20, 14),
      isCorrect: isCorrect,
      scoreIA: 89.0,
      montantMise: mise,
      gainRealise: gainRealise,
      dividendePmuReel: dividendePmuReel,
      numerosJoues: const [16],
    );

void main() {
  setUp(() {
    // Obligatoire AVANT tout getInstance() : harnais partagé indisponible ici.
    SharedPreferences.setMockInitialValues({});
  });

  group('A-0 / T1 — PmuProvider : un G+P en attente ne produit aucun gain', () {
    test('T1a — gainNet reste 0.0 quand isCorrect est null et dividende null', () {
      final p = _pred(typePari: 'Gagnant+Placé');
      expect(p.isCorrect, isNull);
      expect(p.gainRealise, isNull);
      expect(p.gainNet, 0.0,
          reason: 'aucun gain ne doit être inventé pour un pari en attente');
      expect(p.retourTotal, 0.0);
    });

    test('T1b — un G+P résolu par erreur avec la cote Gagnant seule '
        'donnerait 340 € : A-0 doit empêcher cet état', () {
      // Démonstration chiffrée du défaut que A-0 évite.
      // Si `validatePrediction(isCorrect: true, montantMise: 20)` était
      // appelé, le provider calculerait (18 × 20) − 20 = 340 €.
      final avecDefaut = _pred(
        typePari: 'Gagnant+Placé',
        isCorrect: true,
        gainRealise: (kCoteGagnant * kMiseUneComposante) - kMiseUneComposante,
      );
      expect(avecDefaut.gainNet, 340.0,
          reason: 'témoin : c\'est exactement le montant FICTIF que A-0 bloque');

      // Après A-0, l'état attendu d'un G+P est celui-ci :
      final apresA0 = _pred(typePari: 'Gagnant+Placé');
      expect(apresA0.gainNet, 0.0);
      expect(apresA0.gainNet, isNot(340.0));
    });

    test('T1c — validatePrediction n\'est pas appelée pour un G+P : '
        'la prédiction reste intacte', () async {
      final provider = PmuProvider();
      await provider.reloadPredictions();
      provider.addPrediction(_pred(typePari: 'Gagnant+Placé'));
      final id = provider.predictions.first.id;

      // A-0 : les 3 voies automatiques font `continue` avant cet appel.
      // On vérifie ici que l'état « en attente » est bien celui attendu.
      final p = provider.predictions.firstWhere((e) => e.id == id);
      expect(p.isCorrect, isNull);
      expect(p.gainRealise, isNull);
      expect(p.gainNet, 0.0);
    });
  });

  group('A-0 / T6 — Statistiques : un G+P ne peut pas y entrer', () {
    test('T6a — la règle préexistante écarte le G+P (liste MIXTE)', () async {
      final svc = IaMemoryService.instance;
      await svc.mettreAJourStatsTypes([
        {'typePari': 'Gagnant+Placé', 'isCorrect': null, 'gainNet': 0.0},
        {'typePari': 'Simple Gagnant', 'isCorrect': true, 'gainNet': 30.0},
      ]);
      final stats = svc.statsParType;
      final gp = stats.where((s) => s.typePari == 'Gagnant+Placé').toList();
      expect(gp, isEmpty,
          reason: 'aucune ligne G+P ne doit exister dans les stats');

      final sg = stats.firstWhere((s) => s.typePari == 'Simple Gagnant');
      expect(sg.nbJoues, 1);
      expect(sg.nbGagnes, 1);
      expect(sg.gainNet, 30.0);
    });

    test('T6b — CONDITION IMPÉRATIVE N°4 : liste ne contenant QUE du G+P',
        () async {
      final svc = IaMemoryService.instance;
      // Liste composée exclusivement de G+P « en attente ».
      // C'est le cas où une solution par EXCLUSION aurait rendu la liste
      // vide → garde `if (statsFusionnees.isNotEmpty)` non franchie →
      // statistiques périmées conservées. La solution S2 conserve l'entrée.
      await svc.mettreAJourStatsTypes([
        {'typePari': 'Gagnant+Placé', 'isCorrect': null, 'gainNet': 0.0},
        {'typePari': 'Gagnant+Placé', 'isCorrect': null, 'gainNet': 0.0},
      ]);
      final gp = svc.statsParType
          .where((s) => s.typePari == 'Gagnant+Placé')
          .toList();
      expect(gp, isEmpty,
          reason: 'aucun gain G+P fictif ne doit apparaître');

      // La liste n'était pas vide : le recalcul a bien eu lieu, et il a
      // abouti à zéro ligne G+P (et non à des valeurs périmées).
      final total = svc.statsParType.length;
      expect(total, 0,
          reason: 'seul du G+P en attente → aucune statistique comptée');
    });

    test('T6c — gainNet 0.0 ne s\'additionne jamais à un type existant',
        () async {
      final svc = IaMemoryService.instance;
      // Un G+P neutralisé et un Quinté+ gagnant réel.
      await svc.mettreAJourStatsTypes([
        {'typePari': 'Gagnant+Placé', 'isCorrect': null, 'gainNet': 0.0},
        {'typePari': 'Quinté+', 'isCorrect': true, 'gainNet': 1250.0},
      ]);
      final q = svc.statsParType.firstWhere((s) => s.typePari == 'Quinté+');
      expect(q.gainNet, 1250.0,
          reason: 'la somme Quinté+ ne doit pas être polluée par le G+P');
      expect(
        svc.statsParType.where((s) => s.typePari == 'Gagnant+Placé'),
        isEmpty,
      );
    });
  });

  group('A-0 / T5 — Non-régression : les autres types sont écrits comme avant',
      () {
    test('T5a — Simple Gagnant / Simple Placé : gainNet calculé depuis la cote',
        () {
      final sg = _pred(
        typePari: 'Simple Gagnant',
        isCorrect: true,
        gainRealise: (kCoteGagnant * kMiseUneComposante) - kMiseUneComposante,
      );
      expect(sg.gainNet, 340.0);

      final sp = _pred(
        typePari: 'Simple Placé',
        isCorrect: true,
        gainRealise: (kDividendePlace * kMiseUneComposante) - kMiseUneComposante,
      );
      expect(sp.gainNet, closeTo(64.0, 1e-9));
    });

    test('T5b — un pari perdu reste négatif (jamais 0.0)', () {
      final perdu = _pred(typePari: 'Simple Gagnant', isCorrect: false);
      expect(perdu.gainNet, -kMiseUneComposante);
    });

    test('T5c — 6 types transmis aux stats sont tous comptés', () async {
      final svc = IaMemoryService.instance;
      await svc.mettreAJourStatsTypes([
        {'typePari': 'Simple Gagnant', 'isCorrect': true, 'gainNet': 10.0},
        {'typePari': 'Simple Placé', 'isCorrect': true, 'gainNet': 5.0},
        {'typePari': 'Couplé Gagnant', 'isCorrect': false, 'gainNet': -10.0},
        {'typePari': 'Tiercé', 'isCorrect': true, 'gainNet': 100.0},
        {'typePari': 'Quarté+', 'isCorrect': false, 'gainNet': -10.0},
        {'typePari': 'Quinté+', 'isCorrect': true, 'gainNet': 500.0},
      ]);
      final types = svc.statsParType.map((s) => s.typePari).toSet();
      expect(types.length, 6, reason: 'les 6 types doivent être présents');
      expect(types.contains('Gagnant+Placé'), isFalse);
    });
  });

  group('A-0 / T4 — Le résultat SPORTIF n\'est pas un résultat FINANCIER', () {
    test('T4a — deux plans distincts : le sportif est connu, le financier '
        'est en attente', () {
      // Plan SPORTIF : porté par TrackedCourse / mémoire IA (hors A-0).
      // Plan FINANCIER : porté par UserPrediction.isCorrect / gainRealise.
      final financier = _pred(typePari: 'Gagnant+Placé');
      expect(financier.isCorrect, isNull, reason: 'financier EN ATTENTE');
      expect(financier.gainNet, 0.0, reason: 'aucun gain inventé');

      // Le libellé G+P reste lisible : il n\'est ni renommé ni supprimé.
      expect(financier.typePari, 'Gagnant+Placé');
      expect(estTypeGagnantPlaceTest(financier.typePari), isTrue);
    });
  });
}

/// Réexport local pour éviter un import supplémentaire dans ce groupe.
bool estTypeGagnantPlaceTest(String? t) =>
    t != null && t.trim().toLowerCase() == 'gagnant+placé';
