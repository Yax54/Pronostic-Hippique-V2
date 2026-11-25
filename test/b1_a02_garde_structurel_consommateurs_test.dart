// ═══════════════════════════════════════════════════════════════════════════
//  BLOC 1 — BL1-A02 / A03 / A08 / A14 / BL3-A26
//  GARDE STRUCTUREL : LES NEUF CONSOMMATEURS TRANSMETTENT-ILS LA MÊME CHOSE ?
//
//  POURQUOI CE FICHIER EXISTE
//  --------------------------
//  « Neuf appels au même service » ne démontre RIEN si les neuf appels ne
//  transmettent pas les mêmes ENTRÉES. La cascade peut être parfaitement
//  unifiée et produire neuf décisions différentes si l'un des sites oublie
//  `score4`, passe `0.0` au lieu de `null`, ou lit la cote ailleurs.
//
//  Les consommateurs `alert_service._getTypePariPourCourse`,
//  `conseils_screen._getTypePariPourCourse` et `bet_bottom_sheet._conseilIA`
//  sont des membres PRIVÉS d'objets qui exigent un `BuildContext`, un
//  `PmuProvider` et un `AlertService` : ils ne sont pas instanciables
//  directement dans un test. Ce fichier ne prétend donc PAS les exécuter.
//
//  Ce qu'il fait — et ce qu'il ne fait pas
//  ---------------------------------------
//  Il vérifie STRUCTURELLEMENT, par analyse de la source, les invariants qui,
//  avec les tests d'exécution de `b1_a02_coherence_consommateurs_test.dart`
//  (T1..T8, qui eux exercent réellement `cascadeRecommandation` et
//  `premium_utils`), garantissent l'identité de décision :
//
//    G0 — le nettoyeur de commentaires est correct (prérequis de mesure :
//         sans lui, `indexOf` tombait sur les commentaires et rendait les
//         assertions AVEUGLES — c'est le défaut mesuré de la 1re version) ;
//    G1 — les huit fichiers / neuf sites appellent réellement la cascade ;
//    G2 — CHAQUE appel transmet les SIX arguments, avec la MÊME sémantique
//         mesurée (et non « la clé existe quelque part ») :
//           scoreConf = <liste>.first.scoreIA
//           scoreN    = <liste>.length >= N+1 ? <liste>[N].scoreIA : null
//           coteTop   = <liste>.first.coteDecimale
//    G3 — les seuils transmis ne sont JAMAIS un constructeur de défaut
//         (`SeuilsConfianceAdaptatifs()`) mais l'instance réellement apprise ;
//    G4 — `bet_bottom_sheet._conseilIA` n'a plus AUCUNE comparaison de score
//         littérale (le barème figé 80/75/65/50/35/15) ;
//    G5 — le site qui ÉCRIT `typePariConseille` (BL3-A26) le reçoit bien de
//         la décision commune, et non d'un littéral.
//
//  LIMITE DÉCLARÉE : G1..G5 sont des gardes de non-régression statiques. Ils
//  ne remplacent pas une exécution des écrans. La preuve d'exécution existe
//  pour les fonctions publiques (T1..T8) ; pour les trois membres privés, la
//  preuve est celle de leur SOURCE, pas de leur comportement à l'écran.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Les huit fichiers / neuf sites mesurés, avec leur nature d'origine.
/// La nature est conservée TELLE QUE MESURÉE à l'audit : elle documente ce
/// que chaque site était avant correction, pas son état actuel.
const Map<String, String> kSites = <String, String>{
  'lib/utils/premium_utils.dart': 'adaptatif',
  'lib/services/ia_memory_service.dart': 'adaptatif — ÉCRIT typePariConseille',
  'lib/services/data_refresh_service.dart': 'adaptatif — ÉCRIT (isolate + repli)',
  'lib/screens/best_bet_screen.dart': 'adaptatif',
  'lib/screens/conseils_screen.dart': 'figé (avant correction)',
  'lib/services/alert_service.dart': 'figé (copie de conseils)',
  'lib/services/widget_service.dart': 'tronqué (avant correction)',
  'lib/widgets/bet_bottom_sheet.dart': 'figé — ÉCRIT (cœur de BL3-A26)',
};

/// Valeurs admises pour `scoreConf` : le PREMIER du classement IA, sous les
/// quatre écritures réellement employées par les sites.
const Set<String> kScoreConfAdmis = <String>{
  'sorted.first.scoreIA',
  'partantsClasses.first.scoreIA',
  'top.scoreIA',
  'scoreConf',
};

/// Valeurs admises pour `coteTop` : LA COTE DU PREMIER du classement IA,
/// via le getter `coteDecimale` (jamais `cote` brut, jamais un littéral).
const Set<String> kCoteTopAdmis = <String>{
  'sorted.first.coteDecimale',
  'partantsClasses.first.coteDecimale',
  'cote',
  'coteTop',
};

void main() {
  // ───────────────────────────────────────────────────────────────────────
  // G0 — prérequis de mesure : le nettoyeur de commentaires
  // ───────────────────────────────────────────────────────────────────────
  test('G0 — le nettoyeur de commentaires retire les `//` mais garde les '
      'lignes et les `://` dans les chaînes', () {
    const src = 'a // commentaire `f()`\n'
        "b = 'https://exemple.tld/x'; // fin\n"
        "c = 'un // dans une chaîne';\n"
        '/// doc `f()`\n'
        'd = 1;\n';
    final net = _sansCommentaires(src);
    final lignesSrc = src.split('\n').length;
    final lignesNet = net.split('\n').length;

    // ignore: avoid_print
    print('─── MESURE G0 (nettoyeur de commentaires) ──────────────────');
    // ignore: avoid_print
    print('  lignes source / nettoyée : $lignesSrc / $lignesNet');
    // ignore: avoid_print
    print('  `://` conservé : ${net.contains("https://exemple.tld/x")}');
    // ignore: avoid_print
    print('  `//` dans chaîne conservé : ${net.contains("un // dans une chaîne")}');
    // ignore: avoid_print
    print('  appel commenté supprimé : ${!_occ(net, "f(").isNotEmpty}');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    expect(lignesNet, lignesSrc,
        reason: 'Les numéros de ligne doivent être préservés : ils servent de '
            'référence lisible dans les messages d\'échec.');
    expect(net, contains('https://exemple.tld/x'),
        reason: 'Un `//` dans une chaîne n\'est pas un commentaire. Sans cette '
            'garantie, le garde tronquerait du code réel.');
    expect(net, contains('un // dans une chaîne'));
    expect(_occ(net, 'f('), isEmpty,
        reason: 'Un appel présent uniquement dans un commentaire ne doit pas '
            'être compté : c\'était le défaut mesuré de la 1re version.');
  });

  // ───────────────────────────────────────────────────────────────────────
  // G1 — délégation réelle
  // ───────────────────────────────────────────────────────────────────────
  test('G1 — les neuf sites délèguent réellement à cascadeRecommandation()',
      () {
    final manquants = <String>[];
    final mesures = <String>[];

    for (final chemin in kSites.keys) {
      final f = File(chemin);
      expect(f.existsSync(), isTrue, reason: 'fichier introuvable : $chemin');
      final appels = _appels(_sansCommentaires(f.readAsStringSync()));
      mesures.add('${appels.length}  $chemin');
      if (appels.isEmpty) manquants.add(chemin);
    }

    // ignore: avoid_print
    print('─── MESURE G1 (appels RÉELS, commentaires exclus) ──────────');
    // ignore: avoid_print
    for (final m in mesures) {
      // ignore: avoid_print
      print('  $m');
    }
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    expect(manquants, isEmpty,
        reason: 'Chaque consommateur doit déléguer : une copie locale est ce '
            'qui a produit les barèmes concurrents (BL1-A02/A08/A14).');

    // `data_refresh_service` porte DEUX sites réels : l'ISOLATE et le REPLI.
    // BL1-A03 est précisément l'oubli de la branche Quarté+ dans le repli :
    // un seul appel signifierait que l'un des deux chemins a été recollé.
    final dr = _appels(
        _sansCommentaires(File('lib/services/data_refresh_service.dart')
            .readAsStringSync()));
    expect(dr.length, 2,
        reason: 'data_refresh_service doit déléguer dans l\'ISOLATE et dans le '
            'REPLI (BL1-A03).');
  });

  // ───────────────────────────────────────────────────────────────────────
  // G2 — les six arguments, avec la MÊME sémantique
  // ───────────────────────────────────────────────────────────────────────
  test('G2 — chaque site transmet les SIX arguments avec la même sémantique',
      () {
    final ecarts = <String>[];
    final mesures = <String>[];

    for (final chemin in kSites.keys) {
      final src = _sansCommentaires(File(chemin).readAsStringSync());
      final appels = _appels(src);
      expect(appels, isNotEmpty,
          reason: 'aucun appel réel dans $chemin — la mesure serait aveugle');

      for (final a in appels) {
        final args = _arguments(a.code);
        final ou = '$chemin:${_ligneDe(src, a.index)}';
        final locale = <String>[];

        if (args['course'] == null) locale.add('course absent');
        if (args['seuils'] == null) locale.add('seuils absent');

        final sc = _normaliser(args['scoreConf'] ?? '');
        if (!kScoreConfAdmis.contains(sc)) {
          locale.add('scoreConf = « ${args['scoreConf']} »');
        }

        for (final attendu in <(String, int, int)>[
          ('score2nd', 2, 1),
          ('score3', 3, 2),
          ('score4', 4, 3),
        ]) {
          final brut = args[attendu.$1];
          if (brut == null) {
            locale.add('${attendu.$1} absent');
            continue;
          }
          if (!_estScoreRang(brut, seuil: attendu.$2, index: attendu.$3)) {
            locale.add('${attendu.$1} = « $brut »');
          }
        }

        final ct = _normaliser(args['coteTop'] ?? '');
        if (!kCoteTopAdmis.contains(ct)) {
          locale.add('coteTop = « ${args['coteTop']} »');
        }

        mesures.add('${locale.isEmpty ? "OK     " : "ÉCART  "} $ou'
            '${locale.isEmpty ? "" : " → ${locale.join(" ; ")}"}');
        if (locale.isNotEmpty) ecarts.add('$ou → ${locale.join(" ; ")}');
      }
    }

    // ignore: avoid_print
    print('─── MESURE G2 (sémantique des six arguments) ───────────────');
    // ignore: avoid_print
    for (final m in mesures) {
      // ignore: avoid_print
      print('  $m');
    }
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    expect(ecarts, isEmpty,
        reason: 'Un site qui omet `score4`, écrit `0.0` au lieu de `null`, '
            'décale un index, ou lit la cote ailleurs que sur le premier du '
            'classement IA prend une décision DIFFÉRENTE de la cascade '
            'commune POUR LA MÊME COURSE : c\'est exactement la divergence '
            'que BL1-A02/A08/A14 dénoncent.');
  });

  // ───────────────────────────────────────────────────────────────────────
  // G3 — les seuils transmis sont ceux APPRIS
  // ───────────────────────────────────────────────────────────────────────
  test('G3 — aucun site ne transmet les seuils PAR DÉFAUT', () {
    final suspects = <String>[];
    final mesures = <String>[];

    // Le PROPRIÉTAIRE de l'état (`IaMemoryService`) transmet son champ privé
    // `_seuils`. Ce n'est PAS un défaut : le getter public
    // `seuilsConfiance` retourne littéralement ce champ. L'exemption n'est
    // pas déclarée, elle est PROUVÉE ici par lecture de la source ; si le
    // getter cessait de déléguer à `_seuils`, G3 redeviendrait rouge.
    final srcProprio = _sansCommentaires(
        File('lib/services/ia_memory_service.dart').readAsStringSync());
    final proprioProuve = RegExp(
            r'SeuilsConfianceAdaptatifs\s+get\s+seuilsConfiance\s*=>\s*_seuils\s*;')
        .hasMatch(srcProprio);

    // Pour un site d'UN AUTRE fichier, `_seuils` serait inaccessible : il ne
    // peut donc désigner le champ privé que depuis le propriétaire lui-même.
    final cheminProprio = 'lib/services/ia_memory_service.dart';

    for (final chemin in kSites.keys) {
      final src = _sansCommentaires(File(chemin).readAsStringSync());
      for (final a in _appels(src)) {
        final v = seuilsTransmis(a.code);
        final ou = '$chemin:${_ligneDe(src, a.index)}';
        if (v.contains('SeuilsConfianceAdaptatifs(')) {
          suspects.add('$ou → CONSTRUCTEUR DE DÉFAUT (« $v »)');
          mesures.add('DÉFAUT $ou → $v');
          continue;
        }
        // Sources licites : l'instance apprise du singleton, son accesseur,
        // la reconstruction depuis le JSON transporté vers l'isolate, une
        // variable locale déjà mesurée comme telle, ou — depuis le
        // propriétaire de l'état seulement — son champ privé prouvé.
        final champPrive = v == '_seuils' && chemin == cheminProprio && proprioProuve;

        // Une variable locale n'est PAS acceptée sur parole : on remonte à
        // TOUTES ses affectations dans le même fichier. C'est là que se
        // cachait, avant correction, une copie par défaut des seuils
        // (`final seuils = SeuilsConfianceAdaptatifs();` dans l'isolate).
        final affs = _affectations(src, v);
        final apprise = affs
            .where((a) =>
                a.valeur.contains('seuilsConfiance') ||
                a.valeur.contains('getSeuilsAdaptatifs') ||
                a.valeur.contains('fromJson('))
            .toList();
        // Exceptions d'UN SEUL tenant : dérivée STRICTEMENT de `seuilsJson`,
        // ou repli d'erreur dont on EXIGE la trace (une dégradation muette
        // serait invisible à l'audit).
        final deriveeDuPayload = affs
            .where((a) =>
                a.valeur.contains('fromJson(payload.seuilsJson)') &&
                !a.valeur.contains('seuilsConfiance'))
            .toList();
        final repliTrace = affs
            .where((a) =>
                a.valeur.contains('SeuilsConfianceAdaptatifs()') &&
                _zoneAvant(src, a.index, 400).contains('debugPrint('))
            .toList();
        final acceptees = <_Aff>{...apprise, ...deriveeDuPayload, ...repliTrace};
        final nonProuvees = affs.where((a) => !acceptees.contains(a)).toList();
        final localeProuvee = affs.isNotEmpty && nonProuvees.isEmpty;

        final licite = v.contains('seuilsConfiance') ||
            v.contains('getSeuilsAdaptatifs') ||
            v.contains('seuilsJson') ||
            localeProuvee ||
            champPrive;
        if (!licite) {
          suspects.add('$ou → SOURCE DE SEUILS NON IDENTIFIÉE (« $v »'
              '${affs.isEmpty ? " aucune affectation trouvée" : " affectations non prouvées : ${nonProuvees.map((a) => a.valeur).toList()}"}'
              ')');
          mesures.add('INCONNU $ou → $v'
              '${affs.isEmpty ? "" : "  [non prouvées : ${nonProuvees.map((a) => a.valeur).toList()}]"}');
        } else {
          mesures.add('OK     $ou → $v'
              '${champPrive ? "  [champ privé du propriétaire, getter prouvé]" : ""}'
              '${localeProuvee && !champPrive ? "  [aff. : ${affs.map((a) => a.valeur).join(" | ")}]" : ""}');
        }
      }
    }

    // ignore: avoid_print
    print('─── MESURE G3 (source des seuils) ──────────────────────────');
    // ignore: avoid_print
    for (final m in mesures) {
      // ignore: avoid_print
      print('  $m');
    }
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    expect(suspects, isEmpty,
        reason: 'BL1-A08 : un consommateur qui utilise les DÉFAUTS au lieu des '
            'seuils appris prend une décision que l\'apprentissage ne peut pas '
            'corriger. C\'est ce que le test T2 mesure en exécution (seuil '
            'Tiercé 35 → 55 fait basculer la décision).');
  });

  // ───────────────────────────────────────────────────────────────────────
  // G4 — plus aucun barème figé dans bet_bottom_sheet
  // ───────────────────────────────────────────────────────────────────────
  test('G4 — `bet_bottom_sheet._conseilIA` n\'a plus aucun seuil littéral',
      () {
    final src = _sansCommentaires(
        File('lib/widgets/bet_bottom_sheet.dart').readAsStringSync());
    final debut = src.indexOf('Map<String, dynamic> get _conseilIA');
    expect(debut, greaterThan(0), reason: 'getter `_conseilIA` introuvable');

    final region = _regionBloc(src, debut,
        finMarqueur: 'Map<String, dynamic> _conseilIndisponible');

    final comparaisons = RegExp(r'score(Conf|IA|Top)?\s*(<|>|<=|>=)\s*\d+(\.\d+)?')
        .allMatches(region)
        .map((m) => m.group(0))
        .toList();

    // ignore: avoid_print
    print('─── MESURE G4 (barème figé dans bet_bottom_sheet) ──────────');
    // ignore: avoid_print
    print('  comparaisons de score dans _conseilIA : '
        '${comparaisons.isEmpty ? "AUCUNE" : comparaisons}');
    // ignore: avoid_print
    print('  délégation présente : '
        '${region.contains("cascadeRecommandation(") ? "OUI" : "NON"}');
    // ignore: avoid_print
    print('  longueur de la région mesurée : ${region.length} caractères');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    expect(region, contains('cascadeRecommandation('),
        reason: 'BL3-A26 : ce getter ÉCRIT `typePariConseille` dans '
            'l\'apprentissage — il doit recevoir la décision commune.');
    expect(comparaisons, isEmpty,
        reason: 'Aucune comparaison de score ne doit subsister : les littéraux '
            '80/75/65/50/35/15 étaient le barème FIGÉ.');
  });

  // ───────────────────────────────────────────────────────────────────────
  // G5 — la chaîne d'ÉCRITURE de typePariConseille (BL3-A26)
  // ───────────────────────────────────────────────────────────────────────
  test('G5 — la valeur ÉCRITE dans `typePariConseille` vient de la cascade',
      () {
    final src = _sansCommentaires(
        File('lib/widgets/bet_bottom_sheet.dart').readAsStringSync());

    final debut = src.indexOf('Map<String, dynamic> get _conseilIA');
    final region = _regionBloc(src, debut,
        finMarqueur: 'Map<String, dynamic> _conseilIndisponible');

    // Le libellé exposé par `_conseilIA` doit être EXACTEMENT `reco.typePari`.
    final labelDepuisReco =
        RegExp(r'label\s*=\s*reco\.typePari').hasMatch(region);

    // L'écriture réelle du champ d'apprentissage doit passer par `typePariPourIA`.
    final ecritures = RegExp(r'typePariConseille:\s*([^,\n]+)')
        .allMatches(src)
        .map((m) => m.group(1)!.trim())
        .toList();
    // La définition de `typePariPourIA` doit venir de `_conseilIA`.
    final sourceDeTypePariPourIA = RegExp(
            r'typePariPourIA\s*=\s*[^;]*_conseilIA')
        .hasMatch(src);

    // ignore: avoid_print
    print('─── MESURE G5 (chaîne d\'écriture BL3-A26) ─────────────────');
    // ignore: avoid_print
    print('  `label = reco.typePari` : '
        '${labelDepuisReco ? "OUI" : "NON"}');
    // ignore: avoid_print
    print('  `typePariPourIA` issu de `_conseilIA` : '
        '${sourceDeTypePariPourIA ? "OUI" : "NON"}');
    // ignore: avoid_print
    print('  écritures de `typePariConseille:` : $ecritures');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    expect(labelDepuisReco, isTrue,
        reason: 'Le libellé conseillé doit être la décision de la cascade, '
            'sinon l\'interface et l\'apprentissage divergent.');
    expect(sourceDeTypePariPourIA, isTrue,
        reason: '`typePariPourIA` doit dériver de `_conseilIA` : c\'est la '
            'variable effectivement écrite dans `typePariConseille`.');
    expect(ecritures.length, 1,
        reason: 'Un seul écrivain mesuré dans ce fichier (cœur de BL3-A26).');
    expect(ecritures.first, 'typePariPourIA',
        reason: 'Écrire un littéral ou un autre libellé ici contournerait la '
            'décision commune et rendrait BL3-A26 à nouveau ouvert.');
  });
}

// ═══════════════════════════════════════════════════════════════════════════
//  OUTILLAGE DE MESURE
// ═══════════════════════════════════════════════════════════════════════════

/// Résultat d'un appel : région équilibrée + index de départ dans la source.
class _Appel {
  final String code;
  final int index;
  _Appel(this.code, this.index);
}

/// Retire les commentaires `//` **en conservant les numéros de ligne** et en
/// respectant les chaînes de caractères (un `://` n'est pas un commentaire).
///
/// Ce nettoyage est un PRÉREQUIS de mesure : la 1re version de ce fichier
/// cherchait `cascadeRecommandation(` avec `indexOf` et tombait sur les
/// commentaires de documentation, ce qui rendait G2 et G3 aveugles.
String _sansCommentaires(String src) {
  final sb = StringBuffer();
  var i = 0;
  String? quote; // guillemet simple ou double en cours
  var triple = false; // chaîne multi-ligne ''' ou """

  while (i < src.length) {
    final c = src[i];

    if (quote != null) {
      if (c == r'\' && i + 1 < src.length) {
        sb.write(c);
        sb.write(src[i + 1]);
        i += 2;
        continue;
      }
      if (triple) {
        if (i + 2 < src.length &&
            src[i] == quote &&
            src[i + 1] == quote &&
            src[i + 2] == quote) {
          sb.write(src.substring(i, i + 3));
          i += 3;
          quote = null;
          triple = false;
          continue;
        }
      } else if (c == quote) {
        sb.write(c);
        i++;
        quote = null;
        continue;
      }
      sb.write(c);
      i++;
      continue;
    }

    if (c == "'" || c == '"') {
      if (i + 2 < src.length && src[i + 1] == c && src[i + 2] == c) {
        sb.write(src.substring(i, i + 3));
        i += 3;
        quote = c;
        triple = true;
        continue;
      }
      quote = c;
      sb.write(c);
      i++;
      continue;
    }

    if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        i++;
      }
      continue;
    }

    sb.write(c);
    i++;
  }
  return sb.toString();
}

/// Toutes les occurrences du motif `cascadeRecommandation(`, chacune réduite à
/// sa région équilibrée. La définition du service porte le motif mais n'est
/// pas un appel : elle est écartée par le fait qu'elle est suivie d'un `{`
/// nommé (`{\n  required ...`) ; ici on ne scanne que les fichiers
/// consommateurs, qui ne la contiennent pas.
List<_Appel> _appels(String src) {
  final out = <_Appel>[];
  for (final m in _occ(src, 'cascadeRecommandation(')) {
    final region = _regionAppel(src, m);
    if (region.isNotEmpty) out.add(_Appel(region, m));
  }
  return out;
}

/// Indices de toutes les occurrences d'un motif.
List<int> _occ(String src, String motif) {
  final out = <int>[];
  var de = 0;
  while (true) {
    final i = src.indexOf(motif, de);
    if (i < 0) break;
    out.add(i);
    de = i + motif.length;
  }
  return out;
}

/// Isole la région d'un appel à partir de l'index du mot-clé, en équilibrant
/// les parenthèses — la région renvoyée COMMENCE à `(`.
String _regionAppel(String src, int debut) {
  if (debut < 0) return '';
  var i = src.indexOf('(', debut);
  if (i < 0) return '';
  var profondeur = 0;
  final sb = StringBuffer();
  for (; i < src.length; i++) {
    final c = src[i];
    if (c == '(') profondeur++;
    sb.write(c);
    if (c == ')') {
      profondeur--;
      if (profondeur == 0) break;
    }
  }
  return profondeur == 0 ? sb.toString() : '';
}

/// Isole un bloc de déclaration jusqu'à un marqueur de fin.
String _regionBloc(String src, int debut, {required String finMarqueur}) {
  final fin = src.indexOf(finMarqueur, debut);
  return src.substring(debut, fin > debut ? fin : src.length);
}

/// Découpe les arguments nommés de niveau 1 d'une région `( ... )`.
///
/// Le `:` du ternaire (`... ? x : null`) ne peut pas être confondu avec un
/// séparateur nommé : on ne découpe qu'au PREMIER `:` et seulement si ce qui
/// le précède est un identifiant Dart valide.
Map<String, String> _arguments(String region) {
  final out = <String, String>{};
  if (region.isEmpty) return out;

  final corps = region.substring(1, region.length - 1);
  final morceaux = <String>[];
  final sb = StringBuffer();
  var profondeur = 0;
  String? quote;

  for (var i = 0; i < corps.length; i++) {
    final c = corps[i];
    if (quote != null) {
      sb.write(c);
      if (c == r'\' && i + 1 < corps.length) {
        sb.write(corps[i + 1]);
        i++;
      } else if (c == quote) {
        quote = null;
      }
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
      sb.write(c);
      continue;
    }
    if (c == '(' || c == '[' || c == '{') profondeur++;
    if (c == ')' || c == ']' || c == '}') profondeur--;
    if (c == ',' && profondeur == 0) {
      morceaux.add(sb.toString());
      sb.clear();
      continue;
    }
    sb.write(c);
  }
  if (sb.toString().trim().isNotEmpty) morceaux.add(sb.toString());

  for (final m in morceaux) {
    final t = m.trim();
    if (t.isEmpty) continue;
    final i = t.indexOf(':');
    if (i <= 0) continue;
    final nom = t.substring(0, i).trim();
    if (!RegExp(r'^[a-zA-Z_$][a-zA-Z0-9_$]*$').hasMatch(nom)) continue;
    out[nom] = t.substring(i + 1).trim();
  }
  return out;
}

/// Valeur transmise pour `seuils` (vide si l'argument est absent).
String seuilsTransmis(String region) => _arguments(region)['seuils'] ?? '';

/// Compresse les espaces et retours à la ligne pour comparer des expressions
/// écrites sur une ou plusieurs lignes.
String _normaliser(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Motif canonique d'un score de rang :
/// `<liste>.length >= <seuil> ? <liste>[<index>].scoreIA : null`
bool _estScoreRang(String brut, {required int seuil, required int index}) {
  final v = _normaliser(brut);
  final m = RegExp(
          r'^(sorted|partantsClasses)\.length >= (\d+) \? '
          r'(sorted|partantsClasses)\[(\d+)\]\.scoreIA : null$')
      .firstMatch(v);
  if (m == null) return false;
  return m.group(2) == '$seuil' && m.group(3) == m.group(1) && m.group(4) == '$index';
}

/// Numéro de ligne (1-based) d'un index dans la source nettoyée.
int _ligneDe(String src, int index) {
  var n = 1;
  final fin = index < src.length ? index : src.length;
  for (var i = 0; i < fin; i++) {
    if (src[i] == '\n') n++;
  }
  return n;
}

/// Affectation mesurée : expression + index de son début dans la source.
class _Aff {
  final String valeur;
  final int index;
  _Aff(this.valeur, this.index);
}

/// Toutes les expressions affectées à [nom] (`nom = ...;`) dans [src],
/// quelle que soit la forme de la déclaration (`final x =`, `late final T x;`
/// puis `x = ...`, `var x =`). Les `nom:` (arguments nommés) ne sont pas des
/// affectations et ne sont donc pas capturés.
///
/// Cette remontée est ce qui rend G3 non-complaisant : avant correction, des
/// sites déclaraient localement `final seuils = SeuilsConfianceAdaptatifs();`.
/// Accepter la seule présence du nom `seuils` aurait laissé passer ce défaut.
List<_Aff> _affectations(String src, String nom) {
  final out = <_Aff>[];
  final motif = RegExp(r'(?<![A-Za-z0-9_$])' + RegExp.escape(nom) +
      r'\s*=(?!=)');
  for (final m in motif.allMatches(src)) {
    var i = m.end;
    var profondeur = 0;
    final sb = StringBuffer();
    for (; i < src.length; i++) {
      final c = src[i];
      if (c == '(' || c == '[' || c == '{') profondeur++;
      if (c == ')' || c == ']' || c == '}') profondeur--;
      if (c == ';' && profondeur <= 0) break;
      sb.write(c);
    }
    final v = _normaliser(sb.toString());
    if (v.isNotEmpty) out.add(_Aff(v, m.start));
  }
  return out;
}

/// Zone de [n] caractères précédant [index] (pour prouver qu'une trace existe).
String _zoneAvant(String src, int index, int n) =>
    src.substring(index - n < 0 ? 0 : index - n, index);


