// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER 3 — GARDE STRUCTURELLE GLOBALE DE L'ÉCRITURE FINANCIÈRE
// ═══════════════════════════════════════════════════════════════════════════
//
//  ★ POURQUOI CE FICHIER
//
//  Le lot 2-C a interdit le chemin d'écriture dangereux
//  (`PmuProvider.appliquerVerdictGainPrediction`, qui affecte un OBJET ENTIER
//  et écrase donc une saisie manuelle concurrente) — mais la garde existante
//  (`test/b4_3_enregistreur_verdict_test.dart`) ne vérifiait que DEUX écrans :
//  `mes_paris_screen.dart` et `paris_detail_screen.dart`.
//
//  Mesure de départ de ce chantier : `lib/` compte bien plus de deux fichiers
//  susceptibles d'écrire un montant. Un troisième écran, un nouveau service ou
//  un futur refactor pouvait emprunter le chemin interdit SANS qu'aucun test
//  ne le signale. C'était une garde partielle présentée comme globale.
//
//  Ce fichier ferme cette brèche : il balaie **TOUT `lib/`**, commentaires
//  retirés, et vérifie trois propriétés mesurables.
//
//  ★ CE QUE CE FICHIER DÉMONTRE
//
//    ① Aucun fichier de `lib/` n'APPELLE `appliquerVerdictGainPrediction(`
//      (hors sa propre déclaration). Le chemin dangereux est mort.
//    ② Les champs financiers (`montantOfficielPmu`, `remboursementPmu`,
//      `montantGainManuel`, `decisionGainPmu`) ne sont écrits QUE par une
//      liste FERMÉE de sites, nominativement énumérés ci-dessous. Tout
//      nouveau site d'écriture fait échouer ce test — c'est le but : un ajout
//      doit être un CHOIX conscient, documenté, pas un effet de bord.
//    ③ Le seul écrivain de `montantOfficielPmu` dans `PmuProvider` est la
//      fusion défensive de `appliquerVerdictGainPredictionSecurise`. Aucune
//      autre méthode du provider ne peut poser un montant officiel.
//
//  ★ CE QUE CE FICHIER NE PRÉTEND PAS
//
//    Il ne prouve pas qu'un montant est JUSTE — cela relève du moteur B-3 et
//    de l'enregistreur B-4.3, déjà couverts par leurs suites respectives. Il
//    prouve qu'aucun NOUVEAU chemin d'écriture n'est apparu.
//
//    Il n'inspecte pas les commentaires : le code est lu en source NETTE
//    (lignes `//` retirées), donc un chemin interdit CITÉ dans une
//    documentation ne produit pas de faux positif — et, symétriquement, un
//    chemin interdit ne peut pas se cacher derrière un commentaire.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tous les fichiers `.dart` de `lib/`, triés pour un rapport stable.
List<File> _fichiersLib() {
  final out = <File>[];
  for (final e in Directory('lib').listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) out.add(e);
  }
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}

/// Source du fichier, lignes de commentaire `//` retirées.
///
/// ⚠️ On ne retire QUE les lignes dont le premier caractère non blanc est
///    `//`. Les commentaires de fin de ligne sont conservés : une chaîne
///    interdite placée en fin de ligne reste détectée, ce qui est le sens
///    prudent de l'erreur.
String _codeSansCommentaires(File f) {
  final gardees = <String>[];
  for (final l in f.readAsStringSync().split('\n')) {
    if (l.trimLeft().startsWith('//')) continue;
    gardees.add(l);
  }
  return gardees.join('\n');
}

void main() {
  group('C3-G1 — le chemin d\'écriture dangereux est mort dans TOUT lib/', () {
    test('G1.1 aucun appel à appliquerVerdictGainPrediction( hors déclaration',
        () {
      final coupables = <String>[];
      for (final f in _fichiersLib()) {
        final code = _codeSansCommentaires(f);
        if (!code.contains('appliquerVerdictGainPrediction(')) continue;
        // La DÉCLARATION est licite : c'est elle qui définit la méthode
        // historique. Seul l'APPEL est interdit.
        final estDeclaration = RegExp(
          r'bool\s+appliquerVerdictGainPrediction\s*\(\s*UserPrediction',
        ).hasMatch(code);
        if (!estDeclaration) {
          coupables.add(f.path);
        }
      }
      expect(coupables, isEmpty,
          reason: 'le chemin qui remplace un OBJET ENTIER ne doit plus être '
              'appelé nulle part : $coupables');
    });

    test('G1.2 la déclaration existe encore (compatibilité ascendante)', () {
      // ⚠️ La MÉTHODE est conservée : des tests historiques l'exercent encore
      //    (b4_5, b1_t12_lot2c_*) et sa suppression n'apporterait rien. Ce
      //    test constate sa présence pour que sa disparition soit un CHOIX
      //    explicite et non une conséquence accidentelle d'un refactor.
      final src = _codeSansCommentaires(
          File('lib/providers/pmu_provider.dart'));
      expect(
          RegExp(r'bool\s+appliquerVerdictGainPrediction\s*\(').hasMatch(src),
          isTrue,
          reason: 'méthode historique conservée pour compatibilité de test');
    });

    test('G1.3 les deux écrans de production délèguent à la voie sécurisée',
        () {
      for (final ecran in <String>[
        'lib/screens/mes_paris_screen.dart',
        'lib/screens/paris_detail_screen.dart',
      ]) {
        final code = _codeSansCommentaires(File(ecran));
        expect(code.contains('appliquerVerdictGainPredictionSecurise'), isTrue,
            reason: '$ecran doit écrire via la voie sécurisée');
      }
    });
  });

  group('C3-G2 — les champs financiers n\'ont qu\'une liste FERMÉE d\'écrivains',
      () {
    /// Liste NOMINATIVE des sites autorisés à écrire chaque champ financier.
    ///
    /// Chaque entrée est `chemin:ligne`. La ligne est vérifiée : un décalage
    /// fait échouer le test, ce qui force à relire CE site lors de tout
    /// changement — c'est exactement la propriété recherchée.
    ///
    /// ⚠️ Ces trois entrées de `pmu_models.dart` ne sont PAS des écritures
    ///    métier : ce sont (a) la désérialisation JSON, (b) et (c) les
    ///    sentinelles `copyWith`. Les lister explicitement évite de les
    ///    confondre avec une écriture de calcul.
    const Map<String, List<String>> ecrivainsAutorises = <String, List<String>>{
      'montantOfficielPmu:': <String>[
        // (a) désérialisation
        'lib/models/pmu_models.dart:753',
        // (b) sentinelle copyWith
        'lib/models/pmu_models.dart:915',
        // (c) rétablissement après échec de sauvegarde (verdict)
        'lib/providers/pmu_provider.dart:745',
        // (d) fusion défensive du verdict sécurisé
        'lib/providers/pmu_provider.dart:834',
        // (e) conversion verdict → ticket
        'lib/providers/pmu_provider.dart:916',
      ],
      'remboursementPmu:': <String>[
        'lib/models/pmu_models.dart:754',
        'lib/models/pmu_models.dart:918',
        'lib/providers/pmu_provider.dart:746',
        'lib/providers/pmu_provider.dart:917',
        'lib/services/alert_service.dart:653',
        'lib/services/alert_service.dart:2785',
        'lib/services/alert_service.dart:2831',
        'lib/services/alert_service.dart:2963',
        'lib/services/enregistreur_verdict_gain_pmu.dart:555',
        'lib/services/enregistreur_verdict_gain_suivi.dart:170',
        'lib/services/enregistreur_verdict_gain_suivi.dart:259',
      ],
      'montantGainManuel:': <String>[
        'lib/models/pmu_models.dart:751',
        'lib/models/pmu_models.dart:909',
        // seule écriture métier du gain manuel
        'lib/providers/pmu_provider.dart:494',
        // seul rétablissement (rollback) du gain manuel
        'lib/providers/pmu_provider.dart:535',
        // fusion défensive
        'lib/providers/pmu_provider.dart:833',
        'lib/services/alert_service.dart:651',
        'lib/services/alert_service.dart:2783',
        'lib/services/alert_service.dart:2829',
        'lib/services/alert_service.dart:2961',
        'lib/services/enregistreur_verdict_gain_suivi.dart:164',
        'lib/services/enregistreur_verdict_gain_suivi.dart:179',
      ],
      'decisionGainPmu:': <String>[
        'lib/models/pmu_models.dart:755',
        'lib/models/pmu_models.dart:921',
        // seule écriture métier de la décision
        'lib/providers/pmu_provider.dart:425',
        // fusion défensive
        'lib/providers/pmu_provider.dart:835',
      ],
    };

    /// Recalcule, champ par champ, l'ensemble réel des sites d'écriture.
    Map<String, List<String>> sitesReels() {
      final res = <String, List<String>>{};
      for (final champ in ecrivainsAutorises.keys) {
        final sites = <String>[];
        for (final f in _fichiersLib()) {
          final lignes = _codeSansCommentaires(f).split('\n');
          for (var i = 0; i < lignes.length; i++) {
            if (lignes[i].contains(champ)) {
              sites.add('${f.path}:${i + 1}');
            }
          }
        }
        sites.sort();
        res[champ] = sites;
      }
      return res;
    }

    for (final champ in ecrivainsAutorises.keys) {
      test('G2 $champ — liste fermée respectée', () {
        final reels = sitesReels()[champ]!;
        final attendus = <String>[...ecrivainsAutorises[champ]!]..sort();

        // ① Aucun site INATTENDU : c'est la propriété centrale. Un nouveau
        //    chemin d'écriture doit être un choix, jamais un effet de bord.
        final nouveaux = reels.where((s) => !attendus.contains(s)).toList();
        expect(nouveaux, isEmpty,
            reason: 'nouveau(x) site(s) d\'écriture de $champ non déclaré(s) : '
                '$nouveaux — les ajouter sciemment à ecrivainsAutorises après '
                'vérification qu\'ils passent par la voie sécurisée.');

        // ② Aucun site DÉCLARÉ ne doit avoir disparu sans mise à jour de la
        //    liste : sinon la liste mentirait sur l'état du code.
        final disparus = attendus.where((s) => !reels.contains(s)).toList();
        expect(disparus, isEmpty,
            reason: 'site(s) déclaré(s) mais absent(s) du code — la liste doit '
                'suivre le code : $disparus');
      });
    }
  });

  group('C3-G3 — le montant officiel n\'est écrit que par la voie sécurisée',
      () {
    test('G3.1 appliquerVerdictGainPrediction n\'écrit AUCUN montant officiel',
        () {
      // La méthode historique ne touche que l'objet entier. On vérifie qu'elle
      // ne contient AUCUNE affectation de champ financier : si elle en
      // contenait une, ce serait un SECOND chemin d'écriture, donc interdit.
      final lignes = File('lib/providers/pmu_provider.dart')
          .readAsStringSync()
          .split('\n');
      // Bornes de la méthode historique.
      var debut = -1;
      for (var i = 0; i < lignes.length; i++) {
        if (RegExp(r'bool\s+appliquerVerdictGainPrediction\s*\(')
            .hasMatch(lignes[i])) {
          debut = i;
          break;
        }
      }
      expect(debut, greaterThanOrEqualTo(0), reason: 'méthode historique');

      // ⚠️ `trim()`, PAS `trimRight()` : l'accolade fermante d'une méthode est
      //    INDENTÉE («   } »). `trimRight()` laisserait l'indentation et la
      //    boucle ne s'arrêterait jamais — elle absorberait la fin du fichier
      //    et le test signalerait un faux positif (mesuré lors de la première
      //    exécution de cette garde).
      final corps = <String>[];
      for (var i = debut; i < lignes.length; i++) {
        corps.add(lignes[i]);
        if (lignes[i].trim() == '}') break;
      }
      final texte = corps.join('\n');

      for (final champ in <String>[
        'montantOfficielPmu:',
        'remboursementPmu:',
        'decisionGainPmu:',
      ]) {
        expect(texte.contains(champ), isFalse,
            reason: 'la méthode historique ne doit écrire aucun champ '
                'financier ($champ) : l\'écriture passe par la voie sécurisée');
      }
    });

    test('G3.2 la voie sécurisée est le SEUL point d\'entrée exposé', () {
      final src = _codeSansCommentaires(
          File('lib/providers/pmu_provider.dart'));
      expect(src.contains('Future<IssueEcritureGain> '
          'appliquerVerdictGainPredictionSecurise('), isTrue,
          reason: 'la voie sécurisée doit exister et rendre une issue à '
              'quatre états');
      // Elle doit être la SEULE à recevoir un `ResultatOfficielCourse` pour
      // écrire un verdict : aucun second résolveur concurrent.
      final ecrivainsVerdict = <String>[];
      for (final f in _fichiersLib()) {
        final code = _codeSansCommentaires(f);
        if (!code.contains('ResultatOfficielCourse resultat')) continue;
        if (!code.contains('montantOfficielPmu:')) continue;
        ecrivainsVerdict.add(f.path);
      }
      expect(ecrivainsVerdict, <String>['lib/providers/pmu_provider.dart'],
          reason: 'un seul fichier doit convertir un résultat officiel en '
              'montant officiel : pas de second moteur concurrent');
    });
  });
}
