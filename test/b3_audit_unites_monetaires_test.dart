// ═══════════════════════════════════════════════════════════════════════════
//  AUDIT B-3 §2 — UNITÉS MONÉTAIRES — LECTURE SEULE
//
//  DECISION UTILISATEUR (arbitrage) : « Je demande un audit ciblé, en lecture
//  seule, avant la clôture de B-3. [...] Ne modifier aucun calcul sans preuve
//  d'une erreur. »
//
//  Ce fichier ne produit AUCUNE modification de `lib/`. Il MESURE et il
//  IMPRIME. Les invariants affirmés ici sont ceux que la chaîne Dart actuelle
//  doit respecter ; si l'un tombait, il y aurait une preuve d'erreur — et
//  c'est exactement ce qu'un audit doit pouvoir démontrer.
//
//  Sources : captures API RÉELLES de /home/user/recherche_pmu/multi/.
//  Aucune valeur n'est inventée : chaque ligne du tableau imprimé est lue
//  dans un fichier, jamais recopiée de mémoire.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/services/arbitre_variante_pmu.dart';
import 'package:pronostic_hippique/services/gain_pmu_types.dart';
import 'package:pronostic_hippique/services/gain_ticket_calculator.dart';
import 'package:pronostic_hippique/services/moteur_gain_pmu.dart';
import 'package:pronostic_hippique/services/pmu_api_service.dart';
import 'package:pronostic_hippique/services/resolveur_rapport_pmu.dart';

const String _dossier = '/home/user/recherche_pmu/multi';

String _corps(String fichier) =>
    File('$_dossier/$fichier').readAsStringSync();

/// Tous les blocs bruts d'une capture (la racine est une LISTE).
List<Map<String, dynamic>> _blocsBruts(String fichier) {
  final d = jsonDecode(_corps(fichier));
  if (d is! List) return const <Map<String, dynamic>>[];
  return d.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
}

/// Le rapport brut, avec son bloc, pour un libellé donné.
({Map<String, dynamic> bloc, Map<String, dynamic> rapport})? _brut(
    String fichier, String libelle) {
  for (final b in _blocsBruts(fichier)) {
    for (final r in (b['rapports'] as List? ?? const [])) {
      if (r is Map && r['libelle'] == libelle) {
        return (bloc: b, rapport: r.cast<String, dynamic>());
      }
    }
  }
  return null;
}

/// Le rapport tel que la CHAÎNE DART le construit (conversion appliquée).
RapportOfficiel? _officiel(String fichier, String libelle) {
  for (final o in PmuApiService.decoderRapportsOfficiels(_corps(fichier))) {
    if (o.libelle == libelle) return o;
  }
  return null;
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  //  AUDIT/1 — LES DEUX CONVENTIONS `dividendeUnite` COEXISTENT
  // ══════════════════════════════════════════════════════════════════════════
  group('AUDIT/1 — les deux conventions dividendeUnite', () {
    test('AUDIT/1.1 les deux valeurs existent réellement dans les captures',
        () {
      final vues = <String>{};
      for (final f in Directory(_dossier).listSync()) {
        if (f is! File || !f.path.endsWith('.json')) continue;
        for (final b in _blocsBruts(f.uri.pathSegments.last)) {
          final u = b['dividendeUnite'];
          if (u != null) vues.add(u.toString());
        }
      }
      // ignore: avoid_print
      print('│ dividendeUnite observés : $vues');
      expect(vues, containsAll(<String>['PourUnEuro', 'PourUneMiseDeBase']),
          reason: 'les deux conventions doivent être attestées par les données');
    });

    test('AUDIT/1.2 « PourUnEuro » : dividende == dividendePourUnEuro', () {
      // Mesuré sur 3148 rapports. Ici on l'atteste sur un cas nommé.
      final c = _brut('R11C1_15112026.json', 'e-Simple Gagnant')!;
      expect(c.bloc['dividendeUnite'], 'PourUnEuro');
      expect(c.bloc['miseBase'], 100);
      expect(c.rapport['dividende'], c.rapport['dividendePourUnEuro']);
      expect(c.rapport['dividende'], c.rapport['dividendePourUneMiseDeBase']);
      // ignore: avoid_print
      print('│ PourUnEuro : dividende=${c.rapport['dividende']} '
          'pe=${c.rapport['dividendePourUnEuro']} '
          'pbd=${c.rapport['dividendePourUneMiseDeBase']}');
    });

    test('AUDIT/1.3 « PourUneMiseDeBase » : dividende == pourUneMiseDeBase',
        () {
      // Mesuré sur 1292 rapports à miseBase=300.
      final c = _brut('R1C1_16112026.json', 'e-2sur4')!;
      expect(c.bloc['dividendeUnite'], 'PourUneMiseDeBase');
      expect(c.bloc['miseBase'], 300);
      expect(c.rapport['dividende'], c.rapport['dividendePourUneMiseDeBase']);
      // ignore: avoid_print
      print('│ PourUneMiseDeBase : dividende=${c.rapport['dividende']} '
          'pe=${c.rapport['dividendePourUnEuro']} '
          'pbd=${c.rapport['dividendePourUneMiseDeBase']}');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  AUDIT/2 — COHÉRENCE INTERNE DE L'API, SUR TOUTES LES CAPTURES
  // ══════════════════════════════════════════════════════════════════════════
  group('AUDIT/2 — cohérence interne de l\'API', () {
    test('AUDIT/2.1 pbd == pe × miseBase / 100 sur toutes les captures', () {
      var controles = 0;
      var coherents = 0;
      final ecarts = <String>[];
      for (final f in Directory(_dossier).listSync()) {
        if (f is! File || !f.path.endsWith('.json')) continue;
        final nom = f.uri.pathSegments.last;
        for (final b in _blocsBruts(nom)) {
          final mb = b['miseBase'];
          if (mb is! num || mb == 0) continue;
          for (final r in (b['rapports'] as List? ?? const [])) {
            if (r is! Map) continue;
            final pe = r['dividendePourUnEuro'];
            final pbd = r['dividendePourUneMiseDeBase'];
            if (pe is! num || pbd is! num) continue;
            controles++;
            final attendu = pe * mb / 100.0;
            // Tolérance : l'API arrondit au centime (mesuré : 1 écart sur 4684,
            // dû à l'arrondi du supplément Tirelire, cf. AUDIT/2.2).
            if ((attendu - pbd).abs() <= 1.0) {
              coherents++;
            } else {
              ecarts.add('$nom | ${r['libelle']} | mb=$mb pe=$pe '
                  'pbd=$pbd attendu=$attendu');
            }
          }
        }
      }
      // ignore: avoid_print
      print('│ cohérence pbd = pe × miseBase/100 : $coherents / $controles');
      for (final e in ecarts.take(5)) {
        // ignore: avoid_print
        print('│   ÉCART : $e');
      }
      expect(controles, greaterThan(4000),
          reason: 'l\'audit doit porter sur un volume significatif');
      expect(coherents, controles,
          reason: 'une incohérence interne de l\'API doit être vue, pas lissée');
    });

    test('AUDIT/2.2 le seul écart mesuré est l\'arrondi de la Tirelire', () {
      // Le supplément Tirelire est un multiple entier de 1 000 € (règlement),
      // ce qui rend pbd non divisible exactement par miseBase/100.
      final c = _brut('R1C6_15112026.json', 'e-Quinté+ Ordre + Tirelire')!;
      final pe = (c.rapport['dividendePourUnEuro'] as num).toDouble();
      final pbd = (c.rapport['dividendePourUneMiseDeBase'] as num).toDouble();
      final attendu = pe * 200 / 100.0;
      final ecart = (pbd - attendu).abs();
      // ignore: avoid_print
      print('│ Tirelire : pbd=$pbd attendu=$attendu écart=$ecart');
      expect(ecart, lessThanOrEqualTo(1.0),
          reason: 'l\'écart doit rester dans l\'arrondi au centime');
    });

    test('AUDIT/2.3 le supplément Tirelire est un multiple entier de 1 000 €',
        () {
      // Preuve arithmétique sur données réelles : si l'unité brute est le
      // centime, alors la différence (Ordre+Tirelire) − (Ordre) doit être un
      // multiple entier de 100 000 centimes (= 1 000 €).
      final avec = _brut('R1C6_15112026.json', 'e-Quinté+ Ordre + Tirelire')!;
      final sans = _brut('R1C6_15112026.json', 'e-Quinté+ Ordre')!;
      final dAvec = (avec.rapport['dividendePourUnEuro'] as num).toInt();
      final dSans = (sans.rapport['dividendePourUnEuro'] as num).toInt();
      final supplement = dAvec - dSans;
      // ignore: avoid_print
      print('│ supplement brut = $dAvec − $dSans = $supplement (centimes) '
          '= ${supplement / 100} € ; modulo 100000 = ${supplement % 100000}');
      expect(supplement % 100000, 0,
          reason: 'le supplément doit être un multiple entier de 1 000 €, '
              'ce qui n\'est vrai que si l\'unité brute est le centime');
      expect(supplement, greaterThan(0),
          reason: 'le supplément doit s\'AJOUTER, jamais se soustraire');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  AUDIT/3 — LA CONVERSION DART, CAS PAR CAS (tableau demandé)
  // ══════════════════════════════════════════════════════════════════════════
  group('AUDIT/3 — conversion Dart et montant attendu', () {
    test('AUDIT/3.1 tableau complet : brut → unité → conversion → montant', () {
      final cas = <({String fichier, String libelle})>[
        (fichier: 'R11C1_15112026.json', libelle: 'e-Simple Gagnant'),
        (fichier: 'R1C6_15112026.json', libelle: 'e-Quinté+ Ordre'),
        (fichier: 'R1C6_15112026.json', libelle: 'e-Quinté+ Désordre'),
        (fichier: 'R1C6_15112026.json', libelle: 'e-Bonus 4sur5'),
        (fichier: 'R1C6_15112026.json', libelle: 'e-Quarté+ Désordre'),
        (fichier: 'R1C6_15112026.json', libelle: 'e-Tiercé Désordre'),
        (fichier: 'R1C1_16112026.json', libelle: 'e-2sur4'),
      ];

      // ignore: avoid_print
      print('│ fichier | libellé | unite | miseBase | brut pe | brut pbd | '
          'Dart pourUnEuro | ×5 € | ×20 €');

      for (final c in cas) {
        final brut = _brut(c.fichier, c.libelle);
        if (brut == null) {
          // Un libellé absent est SIGNALÉ, jamais remplacé par un autre.
          // ignore: avoid_print
          print('│ ${c.fichier} | ${c.libelle} | ABSENT de la capture');
          continue;
        }
        final off = _officiel(c.fichier, c.libelle);
        expect(off, isNotNull,
            reason: 'le décodeur Dart doit produire le rapport présent en brut');
        final pe = (brut.rapport['dividendePourUnEuro'] as num).toDouble();
        final pbd =
            (brut.rapport['dividendePourUneMiseDeBase'] as num?)?.toDouble();
        final mb = (brut.bloc['miseBase'] as num?)?.toDouble();
        // Un pourUnEuro null serait une INFORMATION MANQUANTE, pas un zéro.
        expect(off!.rapportPourUnEuro, isNotNull,
            reason: 'le décodeur doit rendre un montant exploitable');
        final dart = off.rapportPourUnEuro!;

        // ignore: avoid_print
        print('│ ${c.fichier} | ${c.libelle} | ${brut.bloc['dividendeUnite']} '
            '| ${mb?.toInt()} | $pe | $pbd | $dart | '
            '${(5 * dart).toStringAsFixed(2)} € | '
            '${(20 * dart).toStringAsFixed(2)} €');

        // ── La conversion appliquée doit être EXACTEMENT /100 ────────────────
        expect(dart, closeTo(pe / 100.0, 1e-9),
            reason: 'la chaîne Dart doit convertir les centimes en euros, '
                'une fois et une seule');

        // ── Le montant rendu doit être mise × pourUnEuro, sans autre facteur ─
        for (final mise in <double>[0.5, 1, 2, 5, 10, 20, 100]) {
          final montant = mise * dart;
          expect(montant, closeTo(mise * pe / 100.0, 1e-9),
              reason: 'montant($mise) doit valoir mise × pourUnEuro');
        }
      }
    });

    test('AUDIT/3.2 indépendance à miseBase : deux blocs, même pourUnEuro euro',
        () {
      // Deux paris de miseBase DIFFÉRENTE : le pour-un-euro Dart doit rester
      // comparable, sans quoi la mise serait multipliée par un facteur caché.
      final quinte = _officiel('R1C6_15112026.json', 'e-Quinté+ Ordre')!;
      final simple = _officiel('R11C1_15112026.json', 'e-Simple Gagnant')!;

      final quinteBrut = _brut('R1C6_15112026.json', 'e-Quinté+ Ordre')!;
      final simpleBrut = _brut('R11C1_15112026.json', 'e-Simple Gagnant')!;

      // ignore: avoid_print
      print('│ Quinté+ (miseBase=${quinteBrut.bloc['miseBase']}) : '
          'pbd=${quinteBrut.rapport['dividendePourUneMiseDeBase']} '
          '→ Dart ${quinte.rapportPourUnEuro}');
      // ignore: avoid_print
      print('│ Simple (miseBase=${simpleBrut.bloc['miseBase']}) : '
          'pbd=${simpleBrut.rapport['dividendePourUneMiseDeBase']} '
          '→ Dart ${simple.rapportPourUnEuro}');

      // La mise n'est JAMAIS multipliée par miseBase : une mise de 1 € sur un
      // Quinté+ rapporte le pour-un-euro, pas le pour-une-mise-de-base.
      expect(quinte.rapportPourUnEuro, closeTo(64626.70, 1e-6));
      expect(simple.rapportPourUnEuro, closeTo(7.20, 1e-6));

      // Contrôle par l'absurde : si la chaîne avait retourné le pour-une-mise-
      // de-base, on aurait 129253.40 et 7.20 — le Quinté+ serait doublé.
      expect(quinte.rapportPourUnEuro, isNot(closeTo(129253.40, 1e-6)),
          reason: 'la mise de base ne doit pas être réappliquée par-dessus');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  AUDIT/4 — ABSENCE DE DOUBLE CONVERSION, DE BOUT EN BOUT
  // ══════════════════════════════════════════════════════════════════════════
  group('AUDIT/4 — absence de double conversion', () {
    test('AUDIT/4.1 rapportPublieDepuisJson ne reconvertit pas', () {
      final brut = _brut('R1C6_15112026.json', 'e-Quinté+ Désordre')!;
      final publie = rapportPublieDepuisJson(
        brut.rapport,
        codePmu: 'E_QUINTE_PLUS',
        miseBaseCentimes: (brut.bloc['miseBase'] as num).toInt(),
      )!;
      final peBrut = (brut.rapport['dividendePourUnEuro'] as num).toDouble();
      // ignore: avoid_print
      print('│ Désordre : brut=$peBrut → RapportPublie.pourUnEuro='
          '${publie.pourUnEuro}');
      expect(publie.pourUnEuro, closeTo(peBrut / 100.0, 1e-9),
          reason: '/100 exactement une fois');
      // Si une seconde conversion existait, on lirait pe/10000.
      expect(publie.pourUnEuro, isNot(closeTo(peBrut / 10000.0, 1e-9)));
    });

    test('AUDIT/4.2 le montant final du moteur vaut mise × pourUnEuro', () {
      // Bout en bout sur un cas réellement payé : Tiercé Ordre, arrivée
      // singulière (aucun ex æquo).
      final rapports = <RapportPublie>[];
      for (final o in PmuApiService.decoderRapportsOfficiels(
          _corps('R1C6_15112026.json'))) {
        if (!o.typePari.startsWith('E_TIERCE')) continue;
        final b = _blocsBruts('R1C6_15112026.json')
            .firstWhere((x) => x['typePari'] == o.typePari);
        final r = (b['rapports'] as List)
            .cast<Map>()
            .firstWhere((m) => m['libelle'] == o.libelle);
        rapports.add(rapportPublieDepuisJson(
          r.cast<String, dynamic>(),
          codePmu: o.typePari,
          miseBaseCentimes: (b['miseBase'] as num).toInt(),
        )!);
      }

      final etat = EtatCourseOfficiel(
        arriveeGroupes: const [
          [9], [4], [15], [10], [1], [7], [12]
        ],
        arriveeDefinitive: true,
        rapports: rapports,
      );

      for (final mise in <double>[1, 2, 5, 10.50, 100]) {
        final v = resoudreGainTicket(
          libelleTypePari: 'Tiercé',
          numerosJoues: const [9, 4, 15],
          mise: MiseEngagee.simple(mise),
          etat: etat,
        );
        final attendu = mise * 477.40;
        // ignore: avoid_print
        print('│ Tiercé Ordre, mise $mise € → '
            '${v.estGagne ? v.composantes.single.montantRetour : v.motif} '
            '(attendu $attendu)');
        expect(v.estGagne, isTrue,
            reason: 'Tiercé Ordre sur arrivée singulière doit être attribué');
        expect(v.composantes.single.montantRetour, closeTo(attendu, 1e-9),
            reason: 'montant = mise × pourUnEuro, sans facteur caché');
        // Probité : avoir ajouté /100 deux fois donnerait 100× moins.
        expect(v.composantes.single.montantRetour,
            isNot(closeTo(attendu / 100.0, 1e-6)));
      }
    });

    test('AUDIT/4.3 le résolveur reçoit des euros, pas des centimes', () {
      final o = _officiel('R1C6_15112026.json', 'e-Tiercé Ordre')!;
      // ignore: avoid_print
      print('│ RapportOfficiel.rapportPourUnEuro = ${o.rapportPourUnEuro}');
      expect(o.rapportPourUnEuro, closeTo(477.40, 1e-6),
          reason: 'le résolveur travaille en euros ; 47740 serait des centimes');
      // Le résolveur ne fait que sélectionner : il ne multiplie pas.
      final res = resoudreRapportPmu(
        libelleTypePari: 'Tiercé',
        numerosJoues: const [9, 4, 15],
        rapports: [o],
      );
      expect(res.trouve, isTrue);
      expect(res.rapport!.rapportPourUnEuro, closeTo(477.40, 1e-6));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  AUDIT/5 — CHAMP D'APPLICATION : EN LIGNE vs POINT DE VENTE
  // ══════════════════════════════════════════════════════════════════════════
  group('AUDIT/5 — en ligne vs point de vente', () {
    test('AUDIT/5.1 les libellés API portent le préfixe « e- » (en ligne)', () {
      var avecE = 0;
      var sansE = 0;
      final sansEListe = <String>{};
      for (final f in Directory(_dossier).listSync()) {
        if (f is! File || !f.path.endsWith('.json')) continue;
        for (final b in _blocsBruts(f.uri.pathSegments.last)) {
          for (final r in (b['rapports'] as List? ?? const [])) {
            if (r is! Map) continue;
            final lib = '${r['libelle']}';
            if (lib.startsWith('e-')) {
              avecE++;
            } else {
              sansE++;
              sansEListe.add('${b['typePari']} → $lib');
            }
          }
        }
      }
      // ignore: avoid_print
      print('│ libellés avec « e- » : $avecE | sans : $sansE');
      for (final s in sansEListe) {
        // ignore: avoid_print
        print('│   sans préfixe : $s');
      }
      // Les paris modélisés par B-3 sont tous des paris « e- » (en ligne).
      expect(avecE, greaterThan(4500));
    });

    test('AUDIT/5.2 la Tirelire de notre API est bien la « e-Tirelire »', () {
      final c = _brut('R1C6_15112026.json', 'e-Quinté+ Ordre + Tirelire');
      expect(c, isNotNull,
          reason: 'une seule course des captures publie la Tirelire');
      // ignore: avoid_print
      print('│ libellé exact publié par l\'API : « ${c!.rapport['libelle']} »');
      // Correspondance avec le règlement EN LIGNE (art. 7.1) : le texte y
      // nomme « e-Tirelire » et le rapport « e-Quinté+ Ordre » définitif.
      // Le règlement PDV (ANJ, art. 129) nomme la même mécanique sans « e- » :
      // « Quinté Plus Ordre + Tirelire ». C'est la MÊME mécanique, deux
      // réseaux de distribution.
      expect('${c.rapport['libelle']}', contains('Tirelire'));
      expect('${c.rapport['libelle']}', startsWith('e-'));
    });
  });
}
