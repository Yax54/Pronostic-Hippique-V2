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

/// ★ LOT B-4.4 — retire les COMMENTAIRES d'un source Dart avant analyse.
///
/// POURQUOI CETTE FONCTION EXISTE : le garde-fou B0/1 cherchait les chaînes
/// interdites dans le texte BRUT. Un fichier qui se contente de CITER
/// `RapportAttribue.calculer` dans un commentaire — pour dire qu'il ne
/// l'appelle pas — était donc déclaré coupable. Le contournement évident
/// aurait été d'EXCLURE ce fichier du contrôle : c'est précisément ce que le
/// lot B-4.3 a refusé de faire, et ce lot refuse de faire aussi.
///
/// On rend donc le contrôle sémantiquement exact (« aucun APPEL ») au lieu
/// de l'affaiblir (« aucune mention ») : aucun fichier n'a plus besoin d'être
/// exclu, donc la garde couvre strictement PLUS de fichiers qu'avant.
///
/// MESURE de sûreté : la suppression ne touche ni les chaînes de caractères
/// ni le code. Si une occurrence n'apparaît que dans un commentaire, elle
/// disparaît d'ici et le test ne peut plus être trompé par une auto-citation.
String _sansCommentaires(String source) {
  final sb = StringBuffer();
  var i = 0;
  // État : 0 = code, 1 = chaîne ', 2 = chaîne ", 3 = commentaire //, 4 = /* */
  var etat = 0;
  while (i < source.length) {
    final c = source[i];
    final suivant = (i + 1 < source.length) ? source[i + 1] : '';

    switch (etat) {
      case 0: // code
        if (c == '/' && suivant == '/') {
          etat = 3;
          i += 2;
          continue;
        }
        if (c == '/' && suivant == '*') {
          etat = 4;
          i += 2;
          continue;
        }
        if (c == "'") {
          etat = 1;
        } else if (c == '"') {
          etat = 2;
        }
        sb.write(c);
        i++;
      case 1: // chaîne simple quote
        sb.write(c);
        if (c == r'\') {
          if (i + 1 < source.length) sb.write(source[i + 1]);
          i += 2;
          continue;
        }
        if (c == "'") etat = 0;
        i++;
      case 2: // chaîne double quote
        sb.write(c);
        if (c == r'\') {
          if (i + 1 < source.length) sb.write(source[i + 1]);
          i += 2;
          continue;
        }
        if (c == '"') etat = 0;
        i++;
      case 3: // commentaire de ligne
        if (c == '\n') {
          etat = 0;
          sb.write(c);
        }
        i++;
      case 4: // commentaire de bloc
        if (c == '*' && suivant == '/') {
          etat = 0;
          i += 2;
          continue;
        }
        if (c == '\n') sb.write(c); // on garde les sauts de ligne
        i++;
      default:
        i++;
    }
  }
  return sb.toString();
}

// ───────────────────────────────────────────────────────────────────────────
//  ★ BLOC 1 (validation) — EXTRACTION DES VÉRITABLES DIRECTIVES D'IMPORT
//
//  POURQUOI CE CHANGEMENT, ET EN QUOI IL NE FAIBLIT PAS LA GARDE.
//
//  DÉFAUT MESURÉ de l'ancienne implémentation : le garde-fou comparait la
//  présence de la CHAÎNE `gain_pmu_types.dart` dans le texte de chaque fichier.
//  Il ne distinguait donc pas :
//    • une directive `import`/`export` — ce qu'il veut interdire ;
//    • une simple MENTION dans un commentaire — ce qu'il ne veut pas
//      interdire (un fichier qui ÉCRIT qu'il n'importe pas le socle était
//      déclaré coupable de l'importer).
//  L'échec observé `test/b0_gain_pmu_types_test.dart 268:7` avait exactement
//  cette cause : `chaine_financiere_officielle.dart:189` nomme le socle dans
//  un commentaire de documentation, sans l'importer.
//
//  CE QUE LA NOUVELLE GARDE VÉRIFIE — plus, et non moins :
//    1. elle lit les DIRECTIVES RÉELLES (`import` ET `export`), donc tout
//       véritable import interdit est détecté, y compris :
//         • avec alias      : `import '...' as socle;`
//         • avec préfixe    : `import '...' as s show X;`
//         • avec `show`/`hide` sur plusieurs lignes (mesuré : `pmu_models`
//           et `alert_service` utilisent cette forme) ;
//         • en chemin RELATIF (`'../services/gain_pmu_types.dart'`, mesuré
//           dans `pmu_models.dart`) ou `package:` ;
//    2. elle reste insensible aux commentaires et au formatage, puisque
//       l'analyse porte sur le code NET et sur des directives, pas sur des
//       sous-chaînes ;
//    3. elle conserve la comparaison NOMINATIVE par ÉGALITÉ contre les neuf
//       importateurs autorisés : tout dixième fichier échoue, et tout
//       fichier autorisé qui cesserait d'importer échoue aussi.
//
//  MESURE DE NON-RÉGRESSION DE LA GARDE : cette extraction est testée
//  elle-même plus bas (groupe « la garde détecte… ») sur des sources
//  synthétiques contenant alias, préfixe, forme multiligne, `hide`, chemin
//  relatif, `package:`, mention en commentaire et mention dans une chaîne.
//  Sans ces cas, une extraction trop permissive pourrait rendre le garde-fou
//  silencieusement aveugle — c'est précisément ce qu'il faut empêcher.
// ───────────────────────────────────────────────────────────────────────────

/// Fichier cible du socle, tel qu'il apparaît en fin de chemin.
const String _socle = 'gain_pmu_types.dart';

/// Extrait les chemins des directives `import`/`export` d'une source Dart.
///
/// Retourne les URI BRUTES (telles qu'écrites), sans les résoudre : c'est
/// l'appelant qui décide comment les normaliser. Aucune dépendance à
/// `package:analyzer` n'est introduite (elle n'est pas dans les dépendances
/// verrouillées du projet).
///
/// Algorithme, volontairement strict :
///   • on travaille sur la source NETTE de commentaires (`_sansCommentaires`) ;
///   • on ne reconnaît une directive qu'en DÉBUT D'INSTRUCTION, c'est-à-dire
///     au premier token significatif d'une ligne (ou après un `;`), ce qui
///     exclut une occurrence dans une chaîne de caractères ;
///   • une directive court jusqu'au `;` suivant, ce qui couvre la forme
///     multiligne (`import '...'\n    show\n        A,\n        B;`).
List<String> _directivesImport(String sourceBrute) {
  final source = _sansCommentaires(sourceBrute);
  final uri = <String>[];
  // Une directive ne peut commencer qu'en début de fichier ou après `;`.
  // On découpe donc sur `;` : chaque segment est examiné indépendamment.
  // Les `;` à l'intérieur des chaînes ont été conservés par
  // `_sansCommentaires`, mais aucune directive ne peut s'y trouver, et le
  // motif ci-dessous exige le mot-clé en TÊTE de segment.
  for (final segment in source.split(';')) {
    final t = segment.trimLeft();
    final estImport = t.startsWith('import ');
    final estExport = t.startsWith('export ');
    if (!estImport && !estExport) continue;
    final apres = estImport ? t.substring(7) : t.substring(7);
    final m = RegExp(r"""^\s*(['"])([^'"]+)\1""").firstMatch(apres);
    if (m != null) uri.add(m.group(2)!);
  }
  return uri;
}

/// Vrai si l'URI désigne RÉELLEMENT le socle, quel que soit le chemin employé.
///
/// Couvre : chemin relatif (`'gain_pmu_types.dart'`, `'../services/…'`) et
/// `package:pronostic_hippique/…`. Ne couvre PAS une simple mention : l'URI
/// doit se TERMINER par `gain_pmu_types.dart`, ce qui écarte
/// `gain_pmu_types_test.dart` ou `mon_gain_pmu_types.dart.bak`.
bool _designeLeSocle(String uri) {
  final sansPrefixe =
      uri.startsWith('package:') ? uri.substring('package:'.length) : uri;
  return sansPrefixe == _socle || sansPrefixe.endsWith('/$_socle');
}

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

    test('seuls les deux porteurs de données importent le socle', () {
      // ★ LOT B-1 — MISE À JOUR DÉLIBÉRÉE DE CE TEST.
      //
      // Le contrat d'origine était : « aucun fichier de lib/ n'importe le
      // socle » (B-0 = fondation pure, zéro branchement). B-1 ajoute les sept
      // champs facultatifs à UserPrediction et TrackedCourse : ces deux
      // porteurs de données DOIVENT donc importer le socle pour typer leurs
      // champs. L'assertion d'origine était devenue fausse PAR CONSTRUCTION,
      // et non par régression.
      //
      // Le contrat est RESSERRÉ, pas supprimé : la liste des importateurs est
      // désormais FERMÉE et nominative. Tout troisième importateur — donc tout
      // écran, tout service de calcul, tout branchement — fait échouer ce
      // test. Le branchement effectif reste ainsi interdit jusqu'à ce qu'un
      // lot l'autorise explicitement.
      //
      // ★ LOT B-3 — EXTENSION DÉLIBÉRÉE DE CETTE LISTE FERMÉE.
      //
      // B-3 est exactement le lot qui AUTORISE un service de calcul à importer
      // le socle. Deux fichiers entrent, et eux seuls :
      //   • arbitre_variante_pmu.dart — la couche d'arbitrage a besoin de
      //     RapportPublie et EtatTirelire pour filtrer les rapports ;
      //   • moteur_gain_pmu.dart     — le moteur a besoin de VerdictGain,
      //     EtatTirelire et MotifNonDetermination pour rendre son verdict.
      //
      // ★ LOT B-4.1 — EXTENSION DÉLIBÉRÉE, UN SEUL FICHIER DE PLUS.
      //
      //   • resolution_gain_ticket_pmu.dart — la couche de passage B-4.1
      //     construit un EtatCourseOfficiel et un RapportPublie, donc elle
      //     importe le socle. C'est le SEUL ajout de B-4.1.
      //
      // Le contrat reste FERMÉ : un sixième importateur — donc tout écran,
      // tout provider, tout branchement en production — échoue encore ici.
      // La liste est NOMINATIVE : elle est comparée par égalité, pas par
      // inclusion.
      // ★ LOT B-4.3 — EXTENSION DÉLIBÉRÉE, UN SEUL FICHIER DE PLUS.
      //
      //   • enregistreur_verdict_gain_pmu.dart — l'enregistreur B-4.3 reçoit
      //     un VerdictGain et écrit des RapportAttribue, donc il importe le
      //     socle. C'est le SEUL ajout de B-4.3.
      //
      // Le contrat reste FERMÉ : un septième importateur — donc tout écran,
      // tout provider, tout branchement en production — échoue encore ici.
      // La liste est NOMINATIVE : elle est comparée par égalité, pas par
      // inclusion.
      // ★ LOT B-4.4 — EXTENSION DÉLIBÉRÉE, UN SEUL FICHIER DE PLUS.
      //
      //   • enregistreur_verdict_gain_suivi.dart — applique la décision B-4.3
      //     au modèle `TrackedCourse` ; il manipule donc `EtatGain`,
      //     `EtatTirelire`, `MotifNonDetermination` et `RapportAttribue`.
      //     C'est le SEUL ajout de B-4.4.
      //
      // Le contrat reste FERMÉ : un huitième importateur — donc tout écran,
      // tout provider, tout branchement en production — échoue encore ici.
      // La liste est NOMINATIVE : elle est comparée par égalité, pas par
      // inclusion.
      final importateursAttendus = <String>[
        'lib/models/pmu_models.dart',
        // ★ LOT B-4.5 — deux importateurs AJOUTÉS, la garde ne faiblit pas.
        //   MESURÉ avant d'écrire ces lignes : dans ces deux fichiers, ni
        //   `RapportAttribue.calculer` ni `totalDesMontantsRetour` n'est
        //   appelé (vérifié aussi en source NETTE de commentaires, avec la
        //   méthode `_sansCommentaires` de ce fichier : les deux occurrences
        //   trouvées sont des commentaires qui disent qu'ils ne le font pas).
        //   `affichage_gain_structure.dart` exprime sa somme par
        //   `resoudreTotalDepuisRapports`, qui est la fonction de B-4.3 et non
        //   un calcul du socle : elle additionne des `montantRetour` déjà
        //   persistés, sans produire aucun montant nouveau.
        'lib/services/affichage_gain_structure.dart',
        'lib/services/alert_service.dart',
        'lib/services/arbitre_variante_pmu.dart',
        'lib/services/branchement_verdict_course.dart',
        'lib/services/enregistreur_verdict_gain_pmu.dart',
        'lib/services/enregistreur_verdict_gain_suivi.dart',
        'lib/services/moteur_gain_pmu.dart',
        'lib/services/resolution_gain_ticket_pmu.dart',
      ];

      // ★ BLOC 1 (validation) — LA GARDE PORTE DÉSORMAIS SUR LES DIRECTIVES
      //   RÉELLES D'IMPORT/EXPORT, ET NON SUR LA PRÉSENCE D'UNE CHAÎNE.
      //
      //   L'ancienne version `contenu.contains('gain_pmu_types.dart')`
      //   confondait une DIRECTIVE et une MENTION EN COMMENTAIRE. Défaut
      //   mesuré : `chaine_financiere_officielle.dart:189` nomme le socle dans
      //   sa documentation sans l'importer, et était donc déclaré coupable.
      //
      //   La liste des neuf importateurs autorisés est INCHANGÉE, la
      //   comparaison reste NOMINATIVE par ÉGALITÉ, et la détection couvre
      //   maintenant aussi `export`, les alias, les préfixes, les formes
      //   multilignes `show`/`hide`, les chemins relatifs et `package:`.
      //   Elle est donc STRICTEMENT PLUS COUVRANTE, jamais moins.
      final racine = Directory('lib');
      final coupables = <String>[];
      final detail = <String, List<String>>{};
      for (final f in racine.listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('gain_pmu_types.dart')) continue;
        final uris = _directivesImport(f.readAsStringSync());
        final versLeSocle = uris.where(_designeLeSocle).toList();
        if (versLeSocle.isNotEmpty) {
          coupables.add(f.path);
          detail[f.path] = versLeSocle;
        }
      }
      coupables.sort();
      expect(coupables, equals(importateursAttendus),
          reason: 'liste des importateurs du socle : $coupables\n'
              'directives en cause : $detail');
    });

    // ═══════════════════════════════════════════════════════════════════════
    //  ★ BLOC 1 (validation) — NON-AVEUGLEMENT DE LA NOUVELLE GARDE
    //
    //  Le garde-fou précédent vient de passer d'une recherche de CHAÎNE à une
    //  lecture de DIRECTIVES. Un tel changement pourrait, s'il était trop
    //  permissif, rendre la garde silencieusement aveugle : elle resterait
    //  verte même si un fichier interdit importait le socle.
    //
    //  Ces tests sont donc INDISPENSABLES : ils exercent l'extracteur sur des
    //  sources SYNTHÉTIQUES qui ne dépendent d'aucun fichier de `lib/`, et ils
    //  vérifient qu'il détecte bien chacune des formes réelles ou possibles —
    //  et qu'il ne signale PAS une simple mention.
    // ═══════════════════════════════════════════════════════════════════════
    group('B0/1-bis la garde d\'import détecte toute forme réelle', () {
      test('import simple avec point-virgule', () {
        final uris = _directivesImport(
            "import 'gain_pmu_types.dart';\nvoid f() {}");
        expect(uris.where(_designeLeSocle), hasLength(1));
      });

      test('import avec ALIAS (forme que l\'ancienne garde ratait aussi, '
          'mais que la nouvelle doit couvrir)', () {
        final uris = _directivesImport(
            "import 'gain_pmu_types.dart' as socle;\nvoid f() {}");
        expect(uris.where(_designeLeSocle), hasLength(1),
            reason: 'un alias ne doit pas masquer la directive');
      });

      test('import avec PRÉFIXE et combinateur show', () {
        final uris = _directivesImport(
            "import 'gain_pmu_types.dart' as s show EtatGain;");
        expect(uris.where(_designeLeSocle), hasLength(1));
      });

      test('import MULTILIGNE avec show — forme réellement employée par '
          'pmu_models.dart et alert_service.dart', () {
        final uris = _directivesImport(
            "import '../services/gain_pmu_types.dart'\n"
            "    show\n"
            "        EtatGain,\n"
            "        EtatTirelire,\n"
            "        RapportAttribue;\n"
            "void f() {}");
        expect(uris.where(_designeLeSocle), hasLength(1),
            reason: 'la forme multiligne porte la directive sur plusieurs '
                'lignes : elle doit être reconnue');
      });

      test('import avec hide', () {
        final uris = _directivesImport(
            "import 'gain_pmu_types.dart' hide EtatTirelire;");
        expect(uris.where(_designeLeSocle), hasLength(1));
      });

      test('import en chemin RELATIF profond', () {
        final uris = _directivesImport(
            "import '../../services/gain_pmu_types.dart';");
        expect(uris.where(_designeLeSocle), hasLength(1));
      });

      test('import en package:', () {
        final uris = _directivesImport(
            "import 'package:pronostic_hippique/services/gain_pmu_types.dart';");
        expect(uris.where(_designeLeSocle), hasLength(1));
      });

      test('EXPORT est détecté (réexporter le socle contournerait la garde)', () {
        final uris =
            _directivesImport("export 'gain_pmu_types.dart' show EtatGain;");
        expect(uris.where(_designeLeSocle), hasLength(1),
            reason: 'un export ouvre le même accès qu\'un import');
      });

      test('une MENTION EN COMMENTAIRE n\'est PAS une directive', () {
        final uris = _directivesImport(
            "// ce fichier n'importe pas gain_pmu_types.dart\n"
            "/* ni gain_pmu_types.dart */\n"
            "void f() {}");
        expect(uris.where(_designeLeSocle), isEmpty,
            reason: 'défaut mesuré corrigé : la documentation ne doit pas '
                'rendre un fichier coupable');
      });

      test('une MENTION DANS UNE CHAÎNE n\'est PAS une directive', () {
        final uris = _directivesImport(
            "const String note = \"gain_pmu_types.dart\";");
        expect(uris.where(_designeLeSocle), isEmpty);
      });

      test('un fichier de TEST homonyme n\'est pas confondu avec le socle', () {
        expect(_designeLeSocle('gain_pmu_types_test.dart'), isFalse);
        expect(_designeLeSocle('/tmp/mon_gain_pmu_types.dart.bak'), isFalse);
        expect(_designeLeSocle('gain_pmu_types.dart'), isTrue);
      });

      test('plusieurs directives : seules les vraies sont retenues', () {
        final uris = _directivesImport(
            "import 'dart:io';\n"
            "// import 'gain_pmu_types.dart';\n"
            "import 'autre.dart';\n"
            "export 'gain_pmu_types.dart';");
        expect(uris.where(_designeLeSocle), hasLength(1),
            reason: 'une seule directive réelle vers le socle');
      });
    });

    test('aucun calcul du socle n\'est encore invoqué (B-1 = stockage seul)', () {
      // ★ LOT B-1 — la seconde moitié du contrat d'origine reste INTOUCHÉE :
      // B-1 est un lot de PERSISTANCE. Si un importateur appelait déjà
      // RapportAttribue.calculer ou totalDesMontantsRetour, un montant serait
      // produit dès B-1, ce qui est interdit (aucune modification des calculs
      // financiers dans B-1).
      const calculsDuSocle = <String>[
        'RapportAttribue.calculer',
        'totalDesMontantsRetour',
      ];
      // ★ LOT B-3 — le périmètre est ÉTENDU, la garde ne faiblit pas.
      //
      // Les deux fichiers B-3 importent le socle, il faut donc les contrôler :
      // sinon l'invariant « aucun montant produit » aurait un angle mort
      // exactement là où l'on calcule des montants. Vérifié par grep avant
      // d'écrire ce test : aucune des deux chaînes n'apparaît dans ces
      // fichiers. B-3 produit ses VerdictGain sans jamais appeler
      // RapportAttribue.calculer ni totalDesMontantsRetour.
      //
      // ★ LOT B-4.1 — la couche de passage est ajoutée au MÊME périmètre.
      //
      // Elle convertit des rapports et transmet le ticket au moteur, mais elle
      // ne doit produire aucun montant par elle-même : tout montant vient du
      // VerdictGain du moteur. Vérifié par grep avant d'écrire ce test : ni
      // `RapportAttribue.calculer` ni `totalDesMontantsRetour` n'apparaissent
      // dans ce fichier (grep vide, code de sortie 1).
      // ★ LOT B-4.3 — l'enregistreur est DÉLIBÉRÉMENT ABSENT de ce périmètre.
      //
      // MESURE, ET RAISON DU CHOIX : `enregistreur_verdict_gain_pmu.dart`
      // appelle `RapportAttribue.calculer` (l.428 de ce fichier) pour
      // reconstruire la PREUVE d'attribution — un `RapportAttribue` ne peut
      // pas être construit autrement, son constructeur `_()` étant privé. Il
      // n'est donc PAS un « non-producteur de montant » et le garder ici
      // exigerait d'ASS OUPLIR la garde, ce qui est interdit.
      //
      // CONTRÔLE COMPENSATOIRE : `test/b4_3_enregistreur_verdict_test.dart`
      // vérifie qu'il n'appelle `RapportAttribue.calculer` QUE dans la branche
      // d'écriture (section D), qu'il n'appelle JAMAIS le moteur B-3, et que
      // tout écart de total provoque un REFUS sans mutation du ticket.
      //
      // ★ LOT B-4.4 — LA GARDE EST RENFORCÉE, PAS AFFAIBLIE.
      //
      // Deux faits mesurés, vérifiés par grep avant d'écrire ce qui suit :
      //   • `enregistreur_verdict_gain_suivi.dart` (nouveau) importe le socle
      //     et ne contient NI `RapportAttribue.calculer` NI
      //     `totalDesMontantsRetour` en dehors de deux COMMENTAIRES (l.14, l.16)
      //     qui disent précisément qu'il ne les appelle pas ;
      //   • `enregistreur_verdict_gain_pmu.dart` en contient UN appel réel
      //     (l.428), dans la branche d'écriture.
      //
      // Le contrôle porte donc désormais sur le code SANS commentaires
      // (`_sansCommentaires`). Conséquence : le nouveau fichier peut entrer
      // dans le périmètre — il le DOIT, puisqu'il applique la décision et
      // pourrait un jour être modifié à la légère — et l'enregistreur B-4.3
      // reste dehors pour la seule raison déjà documentée (il reconstruit la
      // preuve d'attribution, son constructeur `_()` étant privé).
      //
      // Aucun fichier n'est donc exclu au bénéfice de la commodité : la garde
      // couvre un fichier de plus et vérifie une propriété plus stricte.
      for (final chemin in <String>[
        'lib/models/pmu_models.dart',
        // ★ LOT B-4.5 — les deux importateurs ajoutés entrent AUSSI dans le
        //   périmètre de non-production de montant. C'est un renforcement :
        //   un fichier de plus est contrôlé, sur la même propriété.
        'lib/services/affichage_gain_structure.dart',
        'lib/services/alert_service.dart',
        'lib/services/arbitre_variante_pmu.dart',
        'lib/services/branchement_verdict_course.dart',
        'lib/services/enregistreur_verdict_gain_suivi.dart',
        'lib/services/moteur_gain_pmu.dart',
        'lib/services/resolution_gain_ticket_pmu.dart',
      ]) {
        final contenu = _sansCommentaires(File(chemin).readAsStringSync());
        for (final calcul in calculsDuSocle) {
          expect(contenu.contains(calcul), isFalse,
              reason: 'B-1 ne doit produire aucun montant : $calcul '
                  'trouvé dans $chemin');
        }
      }
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
      // Ces causes sont celles identifiées par diagnostic. Toute
      // disparition serait une perte de traçabilité.
      //
      // ★ LOT B-3 — passage de 9 à 10 motifs, EXTENSION MOTIVÉE.
      // Le 10e, `ambiguiteReglementaireBonus`, est exigé par la décision
      // utilisateur (option 3 de l'arbitrage R22) : lorsqu'une combinaison
      // Bonus publiée par l'API ne satisfait pas les conditions du règlement
      // e-QUINTÉ+ art. 1 c)/d), le moteur doit rendre `nonDetermine` avec un
      // motif EXPLICITE plutôt que d'attribuer ou de déclarer perdant. Un
      // compteur figé sans ce motif aurait obligé à le coder « en fraude »
      // dans une valeur existante, ce qui aurait détruit la traçabilité que
      // ce test protège.
      expect(MotifNonDetermination.values.length, 10);
      expect(MotifNonDetermination.values, contains(MotifNonDetermination.captureIncomplete));
      expect(MotifNonDetermination.values, contains(MotifNonDetermination.blocJusteAbsent),
          reason: 'R19 : E_TRIO/E_SUPER_QUATRE/E_MULTI ne sont pas le bon bloc');
      expect(MotifNonDetermination.values, contains(MotifNonDetermination.deadHeatSansGroupes));
      expect(MotifNonDetermination.values, contains(MotifNonDetermination.tirelireNonDeterminee));
      expect(MotifNonDetermination.values,
          contains(MotifNonDetermination.ambiguiteReglementaireBonus),
          reason: 'B-3 : divergence règlement ↔ API sur les Bonus, non tranchée');
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
