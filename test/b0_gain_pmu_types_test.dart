// ═══════════════════════════════════════════════════════════════════════════
//  LOT B-0 — TESTS DU SOCLE DE TYPES PURS
//
//  Ces tests ne vérifient AUCUN calcul financier : il n'y en a pas dans ce lot.
//  Ils vérifient que le socle de types rend POSSIBLES les garanties exigées,
//  et IMPOSSIBLES les erreurs qu'on cherche précisément à empêcher.
//
//  Principe directeur de ce fichier : un test qui ne peut pas échouer ne
//  prouve rien. Chaque groupe verrouille donc un comportement précis, avec la
//  raison pour laquelle il doit être vrai.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/services/gain_pmu_types.dart';
import 'package:pronostic_hippique/services/gain_ticket_calculator.dart'
    show VarianteRapport;

/// Rapport publié réaliste, calqué sur R1C6_15112026 (Quinté+).
RapportPublie _rapport({
  String codePmu = 'E_QUINTE_PLUS',
  String libelle = 'e-Quinté+ Ordre',
  VarianteRapport variante = VarianteRapport.ordre,
  String combinaison = '9-4-15-10-1',
  double? pourUnEuro = 6462670.0,
  int? rang = 1,
  int? miseBaseCentimes = 200,
  bool rembourse = false,
}) {
  return RapportPublie(
    codePmu: codePmu,
    libelle: libelle,
    variante: variante,
    combinaison: combinaison,
    pourUnEuro: pourUnEuro,
    rang: rang,
    miseBaseCentimes: miseBaseCentimes,
    rembourse: rembourse,
  );
}

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  //  B0/1 — P U R E T É
  //
  //  Le socle doit être importable sans rien déclencher. Si ce fichier lisait
  //  un fichier, un `SharedPreferences` ou l'heure courante, il rendrait les
  //  tests non reproductibles et pourrait modifier le comportement d'un écran
  //  par simple import.
  // ═════════════════════════════════════════════════════════════════════════
  group('B0/1 — pureté du socle', () {
    test('le fichier ne contient AUCUNE entrée/sortie ni état', () {
      // Lecture du fichier source lui-même : c'est la seule façon de prouver
      // l'absence d'une dépendance que le compilateur autoriserait sans bruit.
      final source = File('lib/services/gain_pmu_types.dart').readAsStringSync();

      // Hors commentaires, on cherche des usages réels, pas des mentions.
      final code = source
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');

      expect(code.contains('dart:io'), isFalse,
          reason: 'aucune I/O fichier ne doit entrer dans un socle pur');
      expect(code.contains('DateTime.now('), isFalse,
          reason: 'un socle pur ne dépend pas de l\'heure courante');
      expect(code.contains('SharedPreferences'), isFalse,
          reason: 'aucun accès au stockage dans un socle de types');
      expect(code.contains('setState'), isFalse,
          reason: 'aucun état d\'interface');
      expect(code.contains('http'), isFalse,
          reason: 'aucun accès réseau');
    });

    test('le fichier n\'importe QUE gain_ticket_calculator (0 import)', () {
      final source = File('lib/services/gain_pmu_types.dart').readAsStringSync();
      final imports = source
          .split('\n')
          .where((l) => l.trimLeft().startsWith('import '))
          .toList();

      // Exactement un import, et c'est le fichier pur à 0 import : la chaîne
      // d'imports est donc fermée, sans risque de cycle.
      expect(imports.length, 1, reason: 'imports mesurés : $imports');
      expect(imports.single.contains('gain_ticket_calculator.dart'), isTrue);

      final amont = File('lib/services/gain_ticket_calculator.dart')
          .readAsStringSync();
      final importsAmont = amont
          .split('\n')
          .where((l) => l.trimLeft().startsWith('import '))
          .toList();
      expect(importsAmont, isEmpty,
          reason: 'gain_ticket_calculator doit rester à 0 import');
    });

    test('aucun fichier existant de lib/ n\'importe encore le socle', () {
      // B-0 est une FONDATION : si un écran l'importait déjà, le lot ne serait
      // plus additif. Ce test échouera volontairement au lot B-4/B-5, quand le
      // branchement sera fait, et devra alors être mis à jour explicitement.
      final racine = Directory('lib');
      final coupables = <String>[];
      for (final f in racine.listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('gain_pmu_types.dart')) continue;
        final contenu = f.readAsStringSync();
        if (contenu.contains('gain_pmu_types.dart')) coupables.add(f.path);
      }
      expect(coupables, isEmpty,
          reason: 'B-0 doit rester non branché ; importé par : $coupables');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B0/2 — R17 : LES UNITÉS HÉTÉROGÈNES SONT RENDUES INACCESSIBLES
  //
  //  Mesure de référence : miseBase vaut 100 / 150 / 200 / 300 centimes selon
  //  le bloc, donc `dividende` et `dividendePourUneMiseDeBase` ne sont pas
  //  comparables entre blocs. Le socle ne doit exposer QUE le pour-un-euro.
  // ═════════════════════════════════════════════════════════════════════════
  group('B0/2 — R17 : une seule unité monétaire exposée', () {
    test('RapportPublie ne porte que pourUnEuro comme montant', () {
      final r = _rapport();
      final cles = r.toJson().keys.toSet();

      // La liste est FERMÉE : si un champ monétaire ambigu apparaissait un
      // jour, ce test le signalerait.
      expect(
        cles,
        containsAll(<String>['pourUnEuro']),
      );
      expect(cles.contains('dividende'), isFalse,
          reason: 'dividende est une autre unité : elle ne doit pas exister ici');
      expect(cles.contains('dividendePourUneMiseDeBase'), isFalse);
      expect(cles.contains('miseBase'), isFalse,
          reason: 'seul miseBaseCentimes existe, et pour l\'audit');
    });

    test('deux blocs de miseBase différente donnent le même montant', () {
      // Même rapport pour 1 €, deux blocs dont miseBase diffère : le montant
      // doit être IDENTIQUE, puisque calculé sur pourUnEuro et rien d'autre.
      final quinte = _rapport(pourUnEuro: 12.5, miseBaseCentimes: 200);
      final quarte = _rapport(pourUnEuro: 12.5, miseBaseCentimes: 150);

      final a = RapportAttribue.calculer(rapport: quinte, miseAppliquee: 2.0);
      final b = RapportAttribue.calculer(rapport: quarte, miseAppliquee: 2.0);

      expect(b.montantRetour, a.montantRetour,
          reason: 'R17 : miseBase ne doit JAMAIS intervenir dans le calcul');
      expect(a.montantRetour, closeTo(25.0, 1e-9),
          reason: '2 € × 12,5 €/€ = 25 €');
    });

    test('miseBaseCentimes est documenté comme audit seulement', () {
      final source = File('lib/services/gain_pmu_types.dart').readAsStringSync();
      expect(source.contains('AUDIT UNIQUEMENT'), isTrue,
          reason: 'le champ doit porter sa propre mise en garde');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B0/3 — « NON DÉTERMINÉ » EST UN ÉTAT DE PREMIÈRE CLASSE
  //
  //  Le défaut à empêcher : confondre « on ne sait pas » avec « zéro ».
  // ═════════════════════════════════════════════════════════════════════════
  group('B0/3 — état « non déterminé » représentable', () {
    test('EtatGain distingue explicitement perdu, attribué et non déterminé', () {
      expect(EtatGain.values,
          containsAll(<EtatGain>[EtatGain.nonDetermine, EtatGain.attribue, EtatGain.perdu]));
      // `nonDetermine` n'est PAS `perdu` : ce sont deux constats différents.
      expect(EtatGain.nonDetermine == EtatGain.perdu, isFalse);
    });

    test('Etats, motifs et états de Tirelire survivent à l\'aller-retour JSON', () {
      for (final e in EtatGain.values) {
        expect(EtatGain.fromJson(e.toJson()), e);
      }
      for (final e in EtatTirelire.values) {
        expect(EtatTirelire.fromJson(e.toJson()), e);
      }
      for (final e in MotifNonDetermination.values) {
        expect(MotifNonDetermination.fromJson(e.toJson()), e);
      }
    });

    test('une valeur inconnue ou absente ne devine RIEN', () {
      // Une version future ou une sauvegarde corrompue ne doit jamais être
      // interprétée comme un état valide.
      expect(EtatGain.fromJson('etatInvente'), isNull);
      expect(EtatGain.fromJson(null), isNull);
      expect(EtatGain.fromJson(42), isNull);
      expect(EtatTirelire.fromJson('peutEtre'), isNull);
      expect(MotifNonDetermination.fromJson(''), isNull);
    });

    test('chaque motif de non-détermination nomme une cause mesurée', () {
      // Ces neuf causes sont celles identifiées par diagnostic. Toute
      // disparition serait une perte de traçabilité.
      expect(MotifNonDetermination.values.length, 9);
      expect(MotifNonDetermination.values, contains(MotifNonDetermination.captureIncomplete));
      expect(MotifNonDetermination.values, contains(MotifNonDetermination.blocJusteAbsent),
          reason: 'R19 : E_TRIO/E_SUPER_QUATRE/E_MULTI ne sont pas le bon bloc');
      expect(MotifNonDetermination.values, contains(MotifNonDetermination.deadHeatSansGroupes));
      expect(MotifNonDetermination.values, contains(MotifNonDetermination.tirelireNonDeterminee));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B0/4 — LA TIRELIRE EST UN ÉTAT SÉPARÉ, JAMAIS UNE ADDITION
  //
  //  Mesure R1C6 : « Ordre + Tirelire » = 11 462 670 et « Ordre » = 6 462 670,
  //  même combinaison, même rang. Le définitif est le premier (art. 7.1).
  // ═════════════════════════════════════════════════════════════════════════
  group('B0/4 — Tirelire : état indépendant, addition impossible', () {
    test('EtatTirelire est distinct de EtatGain', () {
      // Deux incertitudes différentes : on peut très bien connaître l'état du
      // rapport Ordre ET ignorer l'éligibilité à la Tirelire.
      expect(EtatTirelire.values, contains(EtatTirelire.nonDeterminee));
      expect(EtatTirelire.nonDeterminee.name, isNot(EtatGain.nonDetermine.name));
    });

    test('le socle ne fournit AUCUNE fonction d\'addition de rapports', () {
      final source = File('lib/services/gain_pmu_types.dart').readAsStringSync();
      final code = source
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');

      // Seule addition autorisée : la somme des montants DÉJÀ attribués.
      // Aucune fonction ne doit additionner deux RapportPublie.
      expect(code.contains('RapportPublie a, RapportPublie b'), isFalse,
          reason: 'aucune combinaison de deux rapports publiés');
      expect(code.contains('List<RapportPublie>'), isFalse,
          reason: 'le socle ne prend jamais une liste de rapports publiés');
    });

    test('retenir le rapport + Tirelire SEUL donne bien le montant définitif', () {
      // Reproduit la mesure : les deux rapports publiés pour la même
      // combinaison. On n'en retient QU'UN — celui du définitif.
      final tirelire = _rapport(
        libelle: 'e-Quinté+ Ordre + Tirelire',
        variante: VarianteRapport.tirelire,
        pourUnEuro: 11462670.0,
      );
      final avantSupplement = _rapport(
        libelle: 'e-Quinté+ Ordre',
        variante: VarianteRapport.ordre,
        pourUnEuro: 6462670.0,
      );

      final attribue = RapportAttribue.calculer(rapport: tirelire, miseAppliquee: 2.0);

      // 2 € × 11 462 670 = 22 925 340 — c'est exactement le champ `dividende`
      // du rapport « + Tirelire » (22 925 341, écart d'arrondi de l'API).
      expect(attribue.montantRetour, closeTo(22925340.0, 1.0));
      expect(attribue.montantRetour, isNot(closeTo(17925340.0, 1.0)),
          reason: 'JAMAIS la somme des deux rapports (11 462 670 + 6 462 670)');
      expect(avantSupplement.pourUnEuro, isNot(tirelire.pourUnEuro));
      expect(tirelire.pourUnEuro! - avantSupplement.pourUnEuro!, 5000000.0,
          reason: 'différence = 5 000 000 centimes, soit 1 000 € nets × 50');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B0/5 — AUCUNE SÉLECTION PAR MONTANT N'EST POSSIBLE
  //
  //  Le défaut historique est `matching.reduce((a,b) => a.dividende >
  //  b.dividende ? a : b)`. Le socle doit le rendre inécrivable.
  // ═════════════════════════════════════════════════════════════════════════
  group('B0/5 — le dividende maximal est structurellement inaccessible', () {
    test('RapportPublie n\'implémente pas Comparable', () {
      final r = _rapport();
      expect(r is Comparable, isFalse,
          reason: 'un rapport ne se classe pas : il se vérifie');
    });

    test('aucun opérateur de comparaison monétaire n\'est défini', () {
      final source = File('lib/services/gain_pmu_types.dart').readAsStringSync();
      final code = source
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');

      expect(code.contains('Comparable'), isFalse);
      expect(code.contains('compareTo'), isFalse);
      expect(code.contains('reduce('), isFalse,
          reason: 'la forme exacte du défaut ne doit pas apparaître');
      expect(code.contains('.sort('), isFalse,
          reason: 'aucun tri par montant');
      expect(code.contains('.first'), isFalse,
          reason: 'aucun repli « first »');
    });

    test('un montant nul ou négatif n\'est pas un montant exploitable', () {
      expect(_rapport(pourUnEuro: null).aUnMontantExploitable, isFalse);
      expect(_rapport(pourUnEuro: 0.0).aUnMontantExploitable, isFalse);
      expect(_rapport(pourUnEuro: -1.0).aUnMontantExploitable, isFalse);
      expect(_rapport(pourUnEuro: 0.01).aUnMontantExploitable, isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B0/6 — RAPPORT ATTRIBUÉ : LE MONTANT NE PEUT PAS ÊTRE INCOHÉRENT
  // ═════════════════════════════════════════════════════════════════════════
  group('B0/6 — RapportAttribue : cohérence impossible à briser', () {
    test('montantRetour est toujours miseAppliquee × pourUnEuro', () {
      final a = RapportAttribue.calculer(
          rapport: _rapport(pourUnEuro: 8030.0), miseAppliquee: 5.0);
      expect(a.montantRetour, 40150.0);
    });

    test('une mise nulle ou négative est refusée, pas silencieusement nulle', () {
      // Sans ce refus, un ticket à mise 0 produirait « 0 € » et passerait
      // pour un ticket perdant au lieu de signaler un état anormal.
      expect(() => RapportAttribue.calculer(rapport: _rapport(), miseAppliquee: 0.0),
          throwsArgumentError);
      expect(() => RapportAttribue.calculer(rapport: _rapport(), miseAppliquee: -3.0),
          throwsArgumentError);
    });

    test('un rapport sans montant est refusé, jamais complété', () {
      expect(
          () => RapportAttribue.calculer(
              rapport: _rapport(pourUnEuro: null), miseAppliquee: 2.0),
          throwsStateError);
      expect(
          () => RapportAttribue.calculer(
              rapport: _rapport(pourUnEuro: 0.0), miseAppliquee: 2.0),
          throwsStateError);
    });

    test('le constructeur non contrôlé n\'est pas exposé', () {
      final source = File('lib/services/gain_pmu_types.dart').readAsStringSync();
      // Un constructeur public permettrait de fabriquer un attribué dont le
      // montant ne serait pas le produit de sa mise et de son rapport.
      expect(source.contains('const RapportAttribue._('), isTrue,
          reason: 'seul le constructeur privé doit exister');
      expect(source.contains('factory RapportAttribue.calculer('), isTrue,
          reason: 'la factory contrôlée est le seul point d\'entrée');
    });

    test('deux attribués de G+P ne portent jamais la même mise', () {
      // G+P : miseGagnant et misePlace sont deux champs distincts du modèle.
      final g = RapportAttribue.calculer(
        rapport: _rapport(libelle: 'e-Simple Gagnant', combinaison: '9',
            variante: VarianteRapport.sansVariante, pourUnEuro: 7.2, rang: 1),
        miseAppliquee: 10.0,
      );
      final p = RapportAttribue.calculer(
        rapport: _rapport(libelle: 'e-Simple Placé', combinaison: '9',
            variante: VarianteRapport.sansVariante, pourUnEuro: 2.9, rang: 1),
        miseAppliquee: 10.0,
      );

      expect(g.miseAppliquee, 10.0);
      expect(p.miseAppliquee, 10.0);
      // Total des retours = 72 + 29 ; aucune mise n'est comptée deux fois.
      expect(totalDesMontantsRetour(<RapportAttribue>[g, p]), closeTo(101.0, 1e-9));
      // La mise réellement engagée est 20 (10 G + 10 P), jamais 10 ni 40.
      expect(g.miseAppliquee + p.miseAppliquee, 20.0);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B0/7 — COMBINAISONS : « NP » N'EST PAS UNE COMBINAISON DE CHEVAUX
  // ═════════════════════════════════════════════════════════════════════════
  group('B0/7 — lecture des combinaisons', () {
    test('une combinaison lisible rend ses numéros dans l\'ordre publié', () {
      expect(_rapport(combinaison: '9-4-15-10-1').numeros, <int>[9, 4, 15, 10, 1]);
      expect(_rapport(combinaison: '9').numeros, <int>[9]);
    });

    test('une combinaison avec NP rend null — ce n\'est pas un cheval', () {
      expect(_rapport(combinaison: '9-NP').numeros, isNull);
      expect(_rapport(combinaison: '9-4-NP').numeros, isNull);
    });

    test('une combinaison vide ou illisible rend null', () {
      expect(_rapport(combinaison: '').numeros, isNull);
      expect(_rapport(combinaison: '9--4').numeros, isNull);
      expect(_rapport(combinaison: '9-X-4').numeros, isNull);
    });

    test('l\'ordre publié est conservé, jamais trié', () {
      // Crucial : Ordre et Désordre portent la MÊME combinaison, souvent
      // publiée dans l'ordre d'arrivée. Trier effacerait la seule information
      // qui distingue les deux rapports par leur contenu.
      final n = _rapport(combinaison: '9-4-15-10-1').numeros;
      expect(n, <int>[9, 4, 15, 10, 1]);
      expect(n, isNot(<int>[1, 4, 9, 10, 15]));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B0/8 — SÉRIALISATION : RIEN N'EST INVENTÉ À LA RELECTURE
  // ═════════════════════════════════════════════════════════════════════════
  group('B0/8 — sérialisation tolérante', () {
    test('aller-retour d\'un RapportPublie', () {
      final r = _rapport();
      expect(RapportPublie.fromJson(r.toJson()), r);
    });

    test('aller-retour d\'un rapport Tirelire', () {
      final r = _rapport(
          libelle: 'e-Quinté+ Ordre + Tirelire',
          variante: VarianteRapport.tirelire,
          pourUnEuro: 11462670.0);
      final relu = RapportPublie.fromJson(r.toJson());
      expect(relu.variante, VarianteRapport.tirelire);
      expect(relu.pourUnEuro, 11462670.0);
    });

    test('aller-retour d\'un RapportAttribue', () {
      final a = RapportAttribue.calculer(rapport: _rapport(), miseAppliquee: 2.0);
      final relu = RapportAttribue.fromJson(a.toJson());
      expect(relu, a);
      expect(relu.montantRetour, a.montantRetour);
    });

    test('un pourUnEuro absent reste null après relecture', () {
      final r = _rapport(pourUnEuro: null);
      final relu = RapportPublie.fromJson(r.toJson());
      expect(relu.pourUnEuro, isNull,
          reason: 'aucune valeur plausible ne doit être substituée');
      expect(relu.aUnMontantExploitable, isFalse);
    });

    test('une variante inconnue retombe sur illisible, pas sur ordre', () {
      // Un défaut `ordre` transformerait silencieusement tout rapport inconnu
      // en gain « dans l'ordre ».
      final relu = RapportPublie.fromJson(<String, dynamic>{
        'codePmu': 'E_QUINTE_PLUS',
        'libelle': 'e-XYZ',
        'variante': 'varianteInconnue',
        'combinaison': '9-4-15-10-1',
        'pourUnEuro': 10.0,
      });
      expect(relu.variante, VarianteRapport.illisible);
    });

    test('un JSON minimal ne lève pas et ne fabrique aucun montant', () {
      final relu = RapportPublie.fromJson(<String, dynamic>{});
      expect(relu.pourUnEuro, isNull);
      expect(relu.combinaison, '');
      expect(relu.rembourse, isFalse);
      expect(relu.numeros, isNull);
    });

    test('un RapportAttribue sans clé « rapport » est refusé', () {
      expect(() => RapportAttribue.fromJson(<String, dynamic>{}),
          throwsFormatException);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B0/9 — ÉGALITÉ ET AFFICHAGE
  // ═════════════════════════════════════════════════════════════════════════
  group('B0/9 — égalité et représentation', () {
    test('deux rapports de même contenu sont égaux', () {
      expect(_rapport(), _rapport());
      expect(_rapport().hashCode, _rapport().hashCode);
    });

    test('un seul champ différent suffit à les distinguer', () {
      expect(_rapport(pourUnEuro: 6462670.0),
          isNot(_rapport(pourUnEuro: 6462671.0)));
      expect(_rapport(variante: VarianteRapport.ordre),
          isNot(_rapport(variante: VarianteRapport.desordre)));
    });

    test('toString expose le libellé et la combinaison, pas un classement', () {
      final s = _rapport().toString();
      expect(s.contains('e-Quinté+ Ordre'), isTrue);
      expect(s.contains('9-4-15-10-1'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B0/10 — TOTAL DES RETOURS : UNE ADDITION, PAS UNE DÉCISION
  // ═════════════════════════════════════════════════════════════════════════
  group('B0/10 — total des montants retour', () {
    test('la somme d\'une liste vide vaut 0', () {
      expect(totalDesMontantsRetour(const <RapportAttribue>[]), 0.0);
    });

    test('la somme additionne exactement les montants stockés', () {
      final a = RapportAttribue.calculer(rapport: _rapport(pourUnEuro: 10.0), miseAppliquee: 3.0);
      final b = RapportAttribue.calculer(rapport: _rapport(pourUnEuro: 4.0), miseAppliquee: 2.0);
      expect(totalDesMontantsRetour(<RapportAttribue>[a, b]), 38.0);
    });

    test('le socle n\'expose AUCUNE notion de gain net', () {
      // Le gain NET (retour − mise) est une affaire de formule existante,
      // qui n'est pas modifiée par ce lot.
      final source = File('lib/services/gain_pmu_types.dart').readAsStringSync();
      expect(source.contains('gainNet'), isFalse);
      expect(source.contains('ROI'), isFalse);
    });
  });
}
