// AUDIT §3.5 — Famille « global » de `poidsParDiscipline`
//
// OBJECTIF : établir EMPIRIQUEMENT (pas par lecture) si la clé `'global'` est
// ou non une clé RÉELLEMENT STOCKABLE de `IaPoidsAdaptatifs.poidsParDiscipline`,
// et quelles sont les conséquences exactes sur la résolution des poids.
//
// ⚠️ Ce fichier ne modifie AUCUN mécanisme de production : il n'emploie que
//    les API publiques (`normaliseDiscipline`, `poidsEffectifsPourDiscipline`,
//    `clampDiscipline`, `fromJson`/`toJson`). Aucun seuil, aucun poids, aucune
//    formule n'est touché (§36).

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';

void main() {
  group('G — normaliseDiscipline : couverture des libellés réels', () {
    // Libellés RÉELLEMENT émis par `ZoneTurfService._pmuDisciplineToZt`
    // (seul producteur de `course.type` → `pronostic.discipline`).
    const libellesProducteur = <String, String>{
      'Plat': 'plat',
      'Haies': 'obstacle',
      'Steeple Chase': 'obstacle',
      'Attelé': 'trot_attele',
      'Monté': 'trot_monte',
      'Cross': 'obstacle',
    };

    test('G1 — les 6 libellés du producteur sont tous reconnus', () {
      libellesProducteur.forEach((libelle, attendu) {
        expect(
          IaPoidsAdaptatifs.normaliseDiscipline(libelle),
          equals(attendu),
          reason: 'libellé producteur « $libelle »',
        );
      });
    });

    test('G2 — « global » est le repli des chaînes NON reconnues', () {
      // La chaîne vide est la valeur par défaut de `IaPronostic.discipline`
      // dans `fromJson` (`j['discipline'] as String? ?? ''`).
      expect(IaPoidsAdaptatifs.normaliseDiscipline(''), equals('global'));
      expect(IaPoidsAdaptatifs.normaliseDiscipline('Inconnu'), equals('global'));
      expect(IaPoidsAdaptatifs.normaliseDiscipline('TROT'), equals('trot_attele'));
    });
  });

  group('H — « global » comme clé stockée de poidsParDiscipline', () {
    test('H1 — la clé « global » est persistée par toJson/fromJson', () {
      // Écriture d'une clé 'global' comme le ferait `_apprendreParDiscipline`
      // (ligne 4253 : `_poids.poidsParDiscipline[discNorm] = poidsDisc;`
      //  où discNorm = normaliseDiscipline(p.discipline)).
      final Map<String, double> vingt = <String, double>{
        'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
        'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
        'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
        'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05,
        'divergence': 0.04, 'poidsRel': 0.03, 'progression': 0.03,
        'mouvCote': 0.06, 'placeDepart': 0.03,
      };
      IaPoidsAdaptatifs.clampDiscipline(vingt);

      final p = IaPoidsAdaptatifs(poidsParDiscipline: <String, Map<String, double>>{
        'global': vingt,
      });

      final json = p.toJson();
      expect(json['poidsParDiscipline'], isA<Map<String, dynamic>>());

      final relu = IaPoidsAdaptatifs.fromJson(json);
      expect(relu.poidsParDiscipline.containsKey('global'), isTrue,
          reason: 'la clé « global » survit à un cycle toJson → fromJson');
    });

    test('H2 — si « global » est stockée, elle est SERVIE à toute discipline inconnue', () {
      final Map<String, double> vingt = <String, double>{
        'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
        'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
        'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
        'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05,
        'divergence': 0.04, 'poidsRel': 0.03, 'progression': 0.03,
        'mouvCote': 0.06, 'placeDepart': 0.03,
      };
      IaPoidsAdaptatifs.clampDiscipline(vingt);
      final Map<String, double> servi = Map<String, double>.from(vingt);

      final p = IaPoidsAdaptatifs(poidsParDiscipline: <String, Map<String, double>>{
        'global': servi,
      });

      // Une discipline inconnue → normaliseDiscipline renvoie 'global'
      // → poidsParDiscipline['global'] est TROUVÉE → c'est elle qui est servie.
      final res = p.poidsEffectifsPourDiscipline('');
      expect(res['forme'], closeTo(servi['forme']!, 1e-12),
          reason: 'la map « global » stockée prime sur les champs d\'instance');

      // Et pour une discipline CONNUE (plat), ce n'est PAS « global » qui sert :
      // aucune clé 'plat' n'existe → repli sur les champs d'instance.
      final resPlat = p.poidsEffectifsPourDiscipline('Plat');
      expect(resPlat.containsKey('forme'), isTrue);
      expect(resPlat.length, equals(19));
    });
  });

  group('I — État « vierge » : quels poids la production sert-elle ?', () {
    test('I1 — sans aucune clé de discipline, le repli sert les 19 champs d\'instance', () {
      final p = IaPoidsAdaptatifs();
      expect(p.poidsParDiscipline, isEmpty);

      for (final libelle in <String>['Plat', 'Haies', 'Steeple Chase', 'Attelé', 'Monté', 'Cross', '']) {
        final res = p.poidsEffectifsPourDiscipline(libelle);
        expect(res.length, equals(19),
            reason: 'discipline « $libelle » → 19 critères servis');
        double somme = 0.0;
        for (final v in res.values) {
          somme += v;
        }
        // On DOCUMENTE la somme réellement servie (elle n'est pas imposée à 1.0
        // par ce chemin — c'est un fait mesuré, pas une correction).
        expect(somme, greaterThan(0.0));
      }
    });

    test('I2 — la somme effective servie par le repli est mesurée, non supposée', () {
      final p = IaPoidsAdaptatifs();
      final res = p.poidsEffectifsPourDiscipline('Plat');
      double somme = 0.0;
      for (final v in res.values) {
        somme += v;
      }
      // Valeur mesurée sur l'état constructeur (documentaire, non normative).
      expect(somme, closeTo(1.26, 1e-9),
          reason: 'le repli sert la somme des champs d\'instance, ici 1.26');
    });
  });
}
