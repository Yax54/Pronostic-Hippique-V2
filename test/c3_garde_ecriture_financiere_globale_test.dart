// ═══════════════════════════════════════════════════════════════════════════
//  C3 — GARDE D'ÉCRITURE FINANCIÈRE GLOBALE
//
//  POURQUOI CETTE GARDE EXISTE
//  ---------------------------
//  Les champs financiers d'un ticket (`montantOfficielPmu`, `remboursementPmu`,
//  `montantGainManuel`, `decisionGainPmu`) ne doivent avoir qu'une liste
//  FERMÉE d'écrivains. Un nouveau chemin d'écriture, même anodin, peut
//  contourner la voie sécurisée et fausser un gain réel.
//
//  CE QUI A CHANGÉ (et pourquoi)
//  ----------------------------
//  L'ancienne version identifiait chaque site par `chemin:ligne`. Elle était
//  donc sensible à la MISE EN FORME : les 166 corrections d'accolades du
//  BLOC 1 ont décalé les numéros et fait échouer quatre tests alors que
//  AUCUNE écriture financière n'avait bougé. Une garde qui signale un danger
//  inexistant est une garde qu'on apprend à ignorer — exactement l'inverse de
//  ce qu'on veut.
//
//  L'identité d'un site est désormais SYNTAXIQUE, établie sur l'AST officiel
//  du package `analyzer` en DÉPENDANCE DE DÉVELOPPEMENT seulement :
//
//      chemin  <  classe  <  méthode  <  champ  <  nature de l'écriture
//
//  Aucun numéro de ligne n'entre dans la décision. La ligne est conservée
//  UNIQUEMENT dans les messages, pour aller lire le code.
//
//  POURQUOI PAS SEULEMENT `chemin + méthode`
//  -----------------------------------------
//  Une telle clé autoriserait TOUTE nouvelle écriture de ce champ dans une
//  méthode déjà autorisée : une méthode qui écrit aujourd'hui deux champs
//  pourrait en écrire dix sans rien déclencher. Chaque (méthode, champ,
//  nature) est donc une entrée distincte.
//
//  LA LISTE N'EST JAMAIS DÉRIVÉE DU CODE
//  -------------------------------------
//  `autorisations` est une constante écrite à la main. Aucun code ne la
//  remplit depuis l'état courant : sinon elle suivrait automatiquement toute
//  nouvelle écriture et ne protégerait plus de rien.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  MODÈLE D'UN SITE D'ÉCRITURE
// ═══════════════════════════════════════════════════════════════════════════

/// Nature syntaxique d'une écriture de champ.
///
/// Deux natures différentes dans la même méthode sont deux entrées
/// distinctes : on ne peut pas « emprunter » l'autorisation d'un
/// constructeur pour écrire un champ par affectation.
enum NatureEcriture {
  /// Argument nommé dans un appel de constructeur ou de méthode
  /// (`TrackedCourse(montantGainManuel: x)`).
  argumentNomme,

  /// Argument nommé dans un `copyWith(...)`.
  argumentCopyWith,

  /// Affectation `obj.champ = valeur` ou `this.champ = valeur`.
  affectation,

  /// Argument nommé passé à `super(...)`.
  superArgument,
}

/// Un site d'écriture, identifié SANS numéro de ligne.
class SiteEcriture {
  const SiteEcriture({
    required this.chemin,
    required this.classe,
    required this.methode,
    required this.champ,
    required this.nature,
    required this.ligne,
  });

  /// Chemin relatif, ex. `lib/providers/pmu_provider.dart`.
  final String chemin;
  final String classe;
  final String methode;
  final String champ;
  final NatureEcriture nature;

  /// Uniquement pour les messages de diagnostic.
  final int ligne;

  /// Clé d'AUTORISATION — volontairement sans ligne.
  String get cle => '$chemin|$classe|$methode|$champ|${nature.name}';

  /// Clé lisible, pour les messages d'échec.
  String get libelle => '$chemin  $classe.$methode()  $champ  '
      '[${nature.name}]  (ligne $ligne)';

  @override
  String toString() => libelle;
}

// ═══════════════════════════════════════════════════════════════════════════
//  COLLECTE AST
// ═══════════════════════════════════════════════════════════════════════════

/// Les quatre champs financiers protégés.
const Set<String> kChampsFinanciers = <String>{
  'montantOfficielPmu',
  'remboursementPmu',
  'montantGainManuel',
  'decisionGainPmu',
};

/// Collecte les sites d'écriture d'une unité déjà analysée.
///
/// Le contexte (classe, méthode) est tenu par une PILE, ce qui traite
/// correctement les classes imbriquées et les fonctions anonymes : on
/// remonte toujours au nom réellement englobant.
class _Collecteur extends RecursiveAstVisitor<void> {
  _Collecteur(this.chemin, this.ligneDe);

  final String chemin;
  final int Function(int offset) ligneDe;

  final List<String> _classes = <String>[];
  final List<String> _methodes = <String>[];
  final List<SiteEcriture> sites = <SiteEcriture>[];

  String get _classe => _classes.isEmpty ? '<top-level>' : _classes.join('.');
  String get _methode =>
      _methodes.isEmpty ? '<initialisation>' : _methodes.join('>');

  void _ajouter(String champ, NatureEcriture nature, AstNode n) {
    sites.add(SiteEcriture(
      chemin: chemin,
      classe: _classe,
      methode: _methode,
      champ: champ,
      nature: nature,
      ligne: ligneDe(n.offset),
    ));
  }

  // ── Contextes nommés ────────────────────────────────────────────────────
  @override
  void visitClassDeclaration(ClassDeclaration n) {
    _classes.add(n.name.lexeme);
    super.visitClassDeclaration(n);
    _classes.removeLast();
  }

  @override
  void visitMixinDeclaration(MixinDeclaration n) {
    _classes.add(n.name.lexeme);
    super.visitMixinDeclaration(n);
    _classes.removeLast();
  }

  @override
  void visitEnumDeclaration(EnumDeclaration n) {
    _classes.add(n.name.lexeme);
    super.visitEnumDeclaration(n);
    _classes.removeLast();
  }

  @override
  void visitExtensionDeclaration(ExtensionDeclaration n) {
    _classes.add(n.name?.lexeme ?? '<extension>');
    super.visitExtensionDeclaration(n);
    _classes.removeLast();
  }

  void _dans(String nom, AstNode n, void Function() corps) {
    _methodes.add(nom);
    corps();
    _methodes.removeLast();
  }

  @override
  void visitMethodDeclaration(MethodDeclaration n) {
    _dans(n.name.lexeme, n, () => super.visitMethodDeclaration(n));
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration n) {
    final nom = n.name == null
        ? '<constructeur>'
        : '<constructeur.${n.name!.lexeme}>';
    _dans(nom, n, () => super.visitConstructorDeclaration(n));
  }

  // ★ `factory X.fromJson(...)` n'est PAS un ConstructorDeclaration :
  //   c'est une MethodDeclaration dont `isFactory` vaut true. Sans cette
  //   branche, ses écritures tombaient dans `<initialisation>` et perdaient
  //   leur identité. Mesuré sur `TrackedCourse.fromJson`.
  @override
  void visitFunctionDeclaration(FunctionDeclaration n) {
    _dans(n.name.lexeme, n, () => super.visitFunctionDeclaration(n));
  }

  // ── Sites d'écriture ────────────────────────────────────────────────────
  @override
  void visitNamedExpression(NamedExpression n) {
    final champ = n.name.label.name;
    if (kChampsFinanciers.contains(champ)) {
      // La nature dépend du parent : `copyWith(...)` n'est pas un
      // constructeur ordinaire, et `super(...)` n'est ni l'un ni l'autre.
      final nature = _nature(n);
      if (nature != null) _ajouter(champ, nature, n);
    }
    super.visitNamedExpression(n);
  }

  NatureEcriture? _nature(NamedExpression n) {
    final parent = n.parent;
    if (parent is! ArgumentList) return null;
    final invoque = parent.parent;
    if (invoque is SuperConstructorInvocation) return NatureEcriture.superArgument;
    if (invoque is ConstructorDeclaration) return NatureEcriture.argumentNomme;
    if (invoque is MethodInvocation) {
      if (invoque.methodName.name == 'copyWith') {
        return NatureEcriture.argumentCopyWith;
      }
      return NatureEcriture.argumentNomme;
    }
    return NatureEcriture.argumentNomme;
  }

  // ── Affectations ────────────────────────────────────────────────────────
  @override
  void visitAssignmentExpression(AssignmentExpression n) {
    final cible = n.leftHandSide;
    final nom = _nomDeCible(cible);
    if (nom != null && kChampsFinanciers.contains(nom)) {
      _ajouter(nom, NatureEcriture.affectation, n);
    }
    super.visitAssignmentExpression(n);
  }

  /// Nom du champ visé par `x`, `this.x`, `obj.x`.
  String? _nomDeCible(Expression e) {
    if (e is SimpleIdentifier) return e.name;
    if (e is PrefixedIdentifier) return e.identifier.name;
    if (e is PropertyAccess) return e.propertyName.name;
    return null;
  }

  // ── Constructeurs de classes : `Classe(champ: v)` sans `new` ───────────
  // `InstanceCreationExpression` est déjà couvert par `visitNamedExpression`
  // (les arguments nommés sont des NamedExpression).
}

/// Analyse un fichier et rend ses sites d'écriture.
///
/// [contenu] permet d'injecter une variante (mutations de robustesse) sans
/// toucher au fichier sur disque.
List<SiteEcriture> collecter(String chemin, {String? contenu}) {
  final src = contenu ?? File(chemin).readAsStringSync();
  final resultat = parseString(content: src, path: chemin);
  if (resultat.errors.isNotEmpty) {
    fail('Analyse impossible de $chemin : ${resultat.errors.first.message}');
  }
  // Table de correspondance offset -> numéro de ligne (diagnostic seulement).
  final debuts = <int>[0];
  for (var i = 0; i < src.length; i++) {
    if (src.codeUnitAt(i) == 0x0A) debuts.add(i + 1);
  }
  int ligneDe(int offset) {
    var lo = 0, hi = debuts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (debuts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo + 1;
  }

  final v = _Collecteur(chemin, ligneDe);
  resultat.unit.accept(v);
  return v.sites;
}

/// Tous les fichiers `.dart` de `lib/`, triés.
List<String> fichiersLib() {
  final out = <String>[];
  for (final e in Directory('lib').listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) out.add(e.path);
  }
  out.sort();
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

/// MULTIENSEMBLE des clés d'écriture réellement présentes dans `lib/`.
///
/// ⚠️ Un multiensemble et non un ensemble : deux écritures du même champ
///    dans la même méthode produisent la MÊME clé. Avec un simple ensemble,
///    une duplication passerait inaperçue. La valeur est le NOMBRE
///    d'occurrences, et c'est elle qui est comparée.
Map<String, int> occurrencesReelles() {
  final res = <String, int>{};
  for (final f in fichiersLib()) {
    for (final s in collecter(f)) {
      res[s.cle] = (res[s.cle] ?? 0) + 1;
    }
  }
  return res;
}

/// Tous les sites réels, pour les messages de diagnostic.
List<SiteEcriture> sitesDiagnostic() {
  final out = <SiteEcriture>[];
  for (final f in fichiersLib()) {
    out.addAll(collecter(f));
  }
  out.sort((a, b) => a.cle.compareTo(b.cle));
  return out;
}

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  //  C3-G1 — LE CHEMIN D'ÉCRITURE DANGEREUX EST MORT (protection conservée
  //  à l'identique de la version précédente)
  // ═════════════════════════════════════════════════════════════════════════
  group('C3-G1 — le chemin d\'écriture dangereux est mort dans TOUT lib/', () {
    test('G1.1 aucun appel à appliquerVerdictGainPrediction( hors déclaration',
        () {
      final coupables = <String>[];
      for (final f in fichiersLib()) {
        final code = _codeSansCommentaires(File(f));
        if (!code.contains('appliquerVerdictGainPrediction(')) continue;
        // La DÉCLARATION est licite : c'est elle qui définit la méthode
        // historique. Seul l'APPEL est interdit.
        final estDeclaration = RegExp(
          r'bool\s+appliquerVerdictGainPrediction\s*\(\s*UserPrediction',
        ).hasMatch(code);
        if (!estDeclaration) {
          coupables.add(f);
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

  // ═════════════════════════════════════════════════════════════════════════
  //  T1 — ROBUSTESSE À LA MISE EN FORME
  // ═════════════════════════════════════════════════════════════════════════
  group('T1 — la collecte est INSENSIBLE à la mise en forme', () {
    const reference = '''
class Ticket {
  final double? montantOfficielPmu;
  final double? remboursementPmu;
  const Ticket({this.montantOfficielPmu, this.remboursementPmu});
  Ticket copyWith({double? montantOfficielPmu}) =>
      Ticket(montantOfficielPmu: montantOfficielPmu);
}
''';

    /// Ce que la référence produit, sous forme de clés SANS ligne.
    Set<String> cles(String src) =>
        collecter('lib/x.dart', contenu: src).map((s) => s.cle).toSet();

    final base = cles(reference);

    test('T1.1 ajout de COMMENTAIRES : identité inchangée', () {
      final mute = reference
          .replaceFirst('class Ticket {',
              '// un commentaire\nclass Ticket { // un autre')
          .replaceFirst('final double? montantOfficielPmu;',
              '/* bloc */ final double? montantOfficielPmu; // fin de ligne')
          .replaceFirst('Ticket copyWith({',
              '/// doc\n  Ticket copyWith({');
      expect(cles(mute), base);
    });

    test('T1.2 ajout de LIGNES VIDES : identité inchangée', () {
      final mute = reference
          .replaceAll('\n', '\n\n   \n')
          .replaceFirst('class Ticket {', '\n\n\nclass Ticket {\n\n');
      expect(cles(mute), base);
    });

    test('T1.3 REFORMATAGE (retours à la ligne déplacés, indentation ×2)',
        () {
      // Même code, mise en page entièrement différente : arguments éclatés
      // sur plusieurs lignes, indentation doublée. C'est ce que produit
      // `dart format` quand une ligne devient trop longue.
      const mute = '''
class Ticket {
    final double? montantOfficielPmu;
    final double? remboursementPmu;
    const Ticket({
        this.montantOfficielPmu,
        this.remboursementPmu,
    });
    Ticket copyWith({
        double? montantOfficielPmu,
    }) =>
        Ticket(
            montantOfficielPmu: montantOfficielPmu,
        );
}
''';
      expect(cles(mute), base);
    });

    test('T1.4 AJOUT D\'ACCOLADES sans changement fonctionnel : identique',
        () {
      // Le cas exact qui faisait échouer l'ancienne garde.
      const avecAccolades = '''
class Ticket {
  final double? montantOfficielPmu;
  final double? remboursementPmu;
  const Ticket({this.montantOfficielPmu, this.remboursementPmu});
  Ticket copyWith({double? montantOfficielPmu}) {
    return Ticket(montantOfficielPmu: montantOfficielPmu);
  }
}
''';
      expect(cles(avecAccolades), base);
    });

    test('T1.5 la LIGNE change, la CLÉ non', () {
      final decale = '\n\n\n\n\n$reference';
      final a = collecter('lib/x.dart', contenu: reference);
      final b = collecter('lib/x.dart', contenu: decale);
      expect(b.map((s) => s.cle).toList(), a.map((s) => s.cle).toList());
      // La ligne, elle, DOIT avoir bougé : c'est le diagnostic.
      expect(b.first.ligne, a.first.ligne + 5);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T2 — FALSIFIABILITÉ : la garde DOIT refuser
  // ═════════════════════════════════════════════════════════════════════════
  group('T2 — la collecte DÉTECTE réellement les écritures nouvelles', () {
    const reference = '''
class Ticket {
  double? montantOfficielPmu;
  Ticket copyWith({double? montantOfficielPmu}) =>
      Ticket(montantOfficielPmu: montantOfficielPmu);
  void autre() {}
}
''';

    Set<String> cles(String src) =>
        collecter('lib/x.dart', contenu: src).map((s) => s.cle).toSet();

    final base = cles(reference);

    test('T2.1 écriture SUPPLÉMENTAIRE dans une méthode déjà autorisée', () {
      // Le piège que la clé `chemin + méthode` seule ne verrait PAS.
      final mute = reference.replaceFirst('void autre() {}',
          'void autre() { montantOfficielPmu = 1.0; }');
      expect(cles(mute), isNot(base));
      expect(cles(mute).difference(base).length, 1);
      expect(cles(mute).difference(base).first, contains('autre'));
    });

    test('T2.2 DUPLICATION d\'une écriture autorisée', () {
      // Deux constructions du MÊME champ dans la MÊME méthode : les clés se
      // répètent, donc l'ENSEMBLE des clés est inchangé. Seul le COMPTAGE
      // peut l'attraper — c'est précisément pourquoi T3.1 compare des
      // MULTISENSIBLES et non des ensembles.
      final mute = reference.replaceFirst(
          'Ticket copyWith({double? montantOfficielPmu}) =>\n'
              '      Ticket(montantOfficielPmu: montantOfficielPmu);',
          'Ticket copyWith({double? montantOfficielPmu}) =>\n'
              '      montantOfficielPmu == 0.0\n'
              '          ? Ticket(montantOfficielPmu: 1.0)\n'
              '          : Ticket(montantOfficielPmu: montantOfficielPmu);');
      final sitesApres = collecter('lib/x.dart', contenu: mute);
      final sitesAvant = collecter('lib/x.dart', contenu: reference);
      expect(sitesApres.length, sitesAvant.length + 1,
          reason: 'une écriture supplémentaire doit se compter');
      // Même clé deux fois : le comptage le voit, l'ensemble ne le verrait pas.
      final clesApres = sitesApres.map((s) => s.cle).toList();
      expect(clesApres.length, clesApres.toSet().length + 1);
    });

    test('T2.3 écriture DÉPLACÉE dans une autre méthode', () {
      final mute = reference.replaceFirst(
          'void autre() {}',
          'void autre() {}\n  Ticket copie({double? montantOfficielPmu}) =>\n      Ticket(montantOfficielPmu: montantOfficielPmu);');
      final nouvelles = cles(mute).difference(base);
      expect(nouvelles, isNotEmpty);
      expect(nouvelles.first, contains('copie'));
    });

    test('T2.4 CHAMP différent (écriture d\'un champ protégé non autorisé)',
        () {
      final mute = reference.replaceFirst('void autre() {}',
          'void autre() { remboursementPmu = 2.0; }');
      expect(cles(mute), isNot(base));
    });

    test('T2.5 affectation par `this.` détectée comme la même méthode', () {
      final mute = reference.replaceFirst('void autre() {}',
          'void autre() { this.montantOfficielPmu = 3.0; }');
      final diff = cles(mute).difference(base);
      expect(diff, isNotEmpty);
      expect(diff.first, contains('autre'));
    });

    test('T2.6 une LECTURE n\'est pas une écriture', () {
      final mute = reference.replaceFirst(
          'void autre() {}',
          'double? lire() => montantOfficielPmu;');
      // Aucun site ajouté : une lecture ne modifie rien.
      expect(collecter('lib/x.dart', contenu: mute).length,
          collecter('lib/x.dart', contenu: reference).length);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T3 — LA GARDE RÉELLE SUR LE DÉPÔT
  // ═════════════════════════════════════════════════════════════════════════
  group('T3 — liste fermée des écrivains financiers du dépôt', () {
    /// Liste NOMINATIVE ET MANUELLE des sites autorisés.
    ///
    /// Clé : `chemin|classe|méthode|champ|nature`.
    /// AUCUNE ligne. AUCUNE dérivation depuis le code courant.
    ///
    /// ⚠️ Écrite à la main, et c'est volontaire : si un programme la remplissait
    ///    depuis l'état courant, elle suivrait automatiquement toute nouvelle
    ///    écriture et ne protégerait plus de rien.
    ///
    /// ⚠️ Le MULTIENSEMBLE compte : chaque entrée autorise EXACTEMENT une
    ///    occurrence. Ajouter une deuxième écriture du même champ dans la même
    ///    méthode exige donc une deuxième ligne ici — impossible à faire par
    ///    inadvertance.
    ///
    /// ⚠️ Chaque entrée a été RELUE pour vérifier qu'elle passe par la voie
    ///    sûre. La colonne « rôle » est rappelée en commentaire.
    ///
    /// Cette liste a été confrontée à la garde précédente (texte, `chemin:ligne`)
    /// qui comptait 31 sites dans `lib/`. L'AST en compte 31 également : aucune
    /// protection n'a été perdue lors de la migration.
    const List<String> autorisations = <String>[
      // ═══════════════════════════════════════════════════════════════════════
      //  lib/models/pmu_models.dart — `UserPrediction` : DÉSÉRIALISATION et
      //  SENTINELLES `copyWith`. Aucune de ces écritures n'est un calcul
      //  financier : elles recopient un champ existant, ou restituent `null`
      //  quand l'appelant n'a pas fourni de sentinelle.
      // ═══════════════════════════════════════════════════════════════════════
      // (a) désérialisation JSON — restitution du champ persisté
      'lib/models/pmu_models.dart|UserPrediction|<constructeur.fromJson>|montantGainManuel|argumentNomme',
      'lib/models/pmu_models.dart|UserPrediction|<constructeur.fromJson>|montantOfficielPmu|argumentNomme',
      'lib/models/pmu_models.dart|UserPrediction|<constructeur.fromJson>|remboursementPmu|argumentNomme',
      'lib/models/pmu_models.dart|UserPrediction|<constructeur.fromJson>|decisionGainPmu|argumentNomme',
      // (b) sentinelles `copyWith` — un champ non fourni est remis à `null`
      'lib/models/pmu_models.dart|UserPrediction|copyWith|montantGainManuel|argumentNomme',
      'lib/models/pmu_models.dart|UserPrediction|copyWith|montantOfficielPmu|argumentNomme',
      'lib/models/pmu_models.dart|UserPrediction|copyWith|remboursementPmu|argumentNomme',
      'lib/models/pmu_models.dart|UserPrediction|copyWith|decisionGainPmu|argumentNomme',

      // ═══════════════════════════════════════════════════════════════════════
      //  lib/providers/pmu_provider.dart — `PmuProvider` : écritures MÉTIER.
      //  Chacune est un `copyWith` limité aux champs financiers, jamais un
      //  remplacement d'objet entier (c'est précisément ce que le lot 2-C a
      //  interdit, cf. C3-G1).
      // ═══════════════════════════════════════════════════════════════════════
      // seule écriture métier de la décision de gain
      'lib/providers/pmu_provider.dart|PmuProvider|_ecrireDecisionGain|decisionGainPmu|argumentCopyWith',
      // seule écriture métier du gain saisi à la main
      'lib/providers/pmu_provider.dart|PmuProvider|enregistrerGainManuelPrediction|montantGainManuel|argumentCopyWith',
      // unique rétablissement (rollback) du gain manuel
      'lib/providers/pmu_provider.dart|PmuProvider|_rollbackCible|montantGainManuel|argumentCopyWith',
      // rétablissement du verdict officiel après échec de sauvegarde
      'lib/providers/pmu_provider.dart|PmuProvider|_retablirVerdictApresEchec|montantOfficielPmu|argumentCopyWith',
      'lib/providers/pmu_provider.dart|PmuProvider|_retablirVerdictApresEchec|remboursementPmu|argumentCopyWith',
      // fusion défensive : la VOIE SÛRE (résolution officielle → ticket)
      'lib/providers/pmu_provider.dart|PmuProvider|appliquerVerdictGainPredictionSecurise|montantGainManuel|argumentCopyWith',
      'lib/providers/pmu_provider.dart|PmuProvider|appliquerVerdictGainPredictionSecurise|montantOfficielPmu|argumentCopyWith',
      'lib/providers/pmu_provider.dart|PmuProvider|appliquerVerdictGainPredictionSecurise|decisionGainPmu|argumentCopyWith',
      // fusion défensive du montant officiel (ne jamais écraser une saisie)
      'lib/providers/pmu_provider.dart|PmuProvider|_fusionnerMontantOfficiel|montantOfficielPmu|argumentCopyWith',
      'lib/providers/pmu_provider.dart|PmuProvider|_fusionnerMontantOfficiel|remboursementPmu|argumentCopyWith',

      // ═══════════════════════════════════════════════════════════════════════
      //  lib/services/alert_service.dart — construction / recopie de
      //  `TrackedCourse`. Ce sont des TRANSFERTS de valeur déjà calculée.
      // ═══════════════════════════════════════════════════════════════════════
      // création du suivi à partir d'un pari — recopie de la saisie
      'lib/services/alert_service.dart|AlertService|ajouterSuivi|montantGainManuel|argumentNomme',
      'lib/services/alert_service.dart|AlertService|ajouterSuivi|remboursementPmu|argumentNomme',
      // recopie lors du calcul du résultat
      'lib/services/alert_service.dart|TrackedCourse|withResultat|montantGainManuel|argumentNomme',
      'lib/services/alert_service.dart|TrackedCourse|withResultat|remboursementPmu|argumentNomme',
      // recopie lors de l'application d'un dividende officiel
      'lib/services/alert_service.dart|TrackedCourse|withDividende|montantGainManuel|argumentNomme',
      'lib/services/alert_service.dart|TrackedCourse|withDividende|remboursementPmu|argumentNomme',
      // désérialisation JSON
      'lib/services/alert_service.dart|TrackedCourse|<constructeur.fromJson>|montantGainManuel|argumentNomme',
      'lib/services/alert_service.dart|TrackedCourse|<constructeur.fromJson>|remboursementPmu|argumentNomme',

      // ═══════════════════════════════════════════════════════════════════════
      //  lib/services/enregistreur_verdict_gain_pmu.dart — test AVEUGLE
      //  publié de l'enregistreur (sans Flutter), sur un `copyWith`.
      // ═══════════════════════════════════════════════════════════════════════
      'lib/services/enregistreur_verdict_gain_pmu.dart|<top-level>|enregistrerVerdictGain|remboursementPmu|argumentCopyWith',

      // ═══════════════════════════════════════════════════════════════════════
      //  lib/services/enregistreur_verdict_gain_suivi.dart — jumeau pour les
      //  courses suivies.
      // ═══════════════════════════════════════════════════════════════════════
      // `copyWith` du modèle réduit (recopie)
      'lib/services/enregistreur_verdict_gain_suivi.dart|TrackedCourseCopy|copyWith|montantGainManuel|argumentNomme',
      'lib/services/enregistreur_verdict_gain_suivi.dart|TrackedCourseCopy|copyWith|remboursementPmu|argumentNomme',
      // report d'un gain saisi à la main
      'lib/services/enregistreur_verdict_gain_suivi.dart|TrackedCourseCopy|copieAvecGainManuel|montantGainManuel|argumentCopyWith',
      // test aveugle publié de l'enregistreur de suivi
      'lib/services/enregistreur_verdict_gain_suivi.dart|<top-level>|enregistrerVerdictGainSuivi|remboursementPmu|argumentCopyWith',
    ];

    test('T3.0 la liste n\'est jamais vide (sinon le test serait tautologique)',
        () {
      expect(autorisations, isNotEmpty);
    });

    test('T3.1 aucun site NON autorisé, et aucun site en surnombre', () {
      // `autorisations` est un MULTIENSEMBLE : une clé déclarée deux fois
      // autorise exactement deux occurrences, pas « au moins une ».
      final declare = <String, int>{};
      for (final c in autorisations) {
        declare[c] = (declare[c] ?? 0) + 1;
      }
      final reels = occurrencesReelles();

      final inconnus = reels.keys.where((c) => !declare.containsKey(c)).toList()
        ..sort();
      final surnombre = <String>[];
      for (final c in declare.keys) {
        final attendu = declare[c]!;
        final trouve = reels[c] ?? 0;
        if (trouve > attendu) surnombre.add('$c (déclaré $attendu, trouvé $trouve)');
      }
      surnombre.sort();

      if (inconnus.isNotEmpty || surnombre.isNotEmpty) {
        // Diagnostic AVEC lignes, pour aller lire le code — jamais pour décider.
        final details = sitesDiagnostic()
            .where((s) =>
                inconnus.contains(s.cle) ||
                surnombre.any((x) => x.startsWith('${s.cle} (')))
            .map((s) => '    ${s.libelle}')
            .toList();
        fail('${inconnus.length} site(s) NON autorisé(s), '
            '${surnombre.length} site(s) en SURNOMBRE :\n'
            '  non autorisés : ${inconnus.join('\n                  ')}\n'
            '  surnombre     : ${surnombre.join('\n                  ')}\n'
            '  occurrences   :\n${details.join('\n')}\n'
            '  → les déclarer SCIEMMENT dans `autorisations` après avoir '
            'vérifié qu\'ils passent par la voie sécurisée.');
      }
    });

    test('T3.2 aucun site autorisé ne doit avoir disparu sans mise à jour', () {
      final reels = occurrencesReelles();
      final disparus =
          autorisations.where((c) => !reels.containsKey(c)).toList()..sort();
      expect(disparus, isEmpty,
          reason: 'site(s) déclaré(s) mais absent(s) — la liste doit suivre '
              'le code : $disparus');
    });

    test('T3.3 la liste ne contient aucune clé en double', () {
      expect(autorisations.length, autorisations.toSet().length);
    });

    test('T3.4 aucune clé ne contient un numéro de ligne', () {
      for (final c in autorisations) {
        expect(RegExp(r':\d+').hasMatch(c), isFalse,
            reason: 'une clé porte un numéro de ligne : $c');
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C3-G3 — LE MONTANT OFFICIEL N'EST ÉCRIT QUE PAR LA VOIE SÉCURISÉE
  //  (protection conservée à l'identique de la version précédente)
  // ═════════════════════════════════════════════════════════════════════════
  group('C3-G3 — le montant officiel n\'est écrit que par la voie sécurisée',
      () {
    test('G3.1 appliquerVerdictGainPrediction n\'écrit AUCUN montant officiel',
        () {
      // La méthode historique ne touche que l'objet entier. On vérifie qu'elle
      // ne contient AUCUNE écriture de champ financier : si elle en contenait
      // une, ce serait un SECOND chemin d'écriture, donc interdit.
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
      //
      // ⚠️ Cette lecture par bornes de texte SUBSISTE volontairement : elle
      //    cherche l'ABSENCE d'un motif dans un corps de méthode, pas un site
      //    d'écriture à autoriser. Un ajout d'accolade à l'intérieur du corps
      //    ne peut pas la fausser ; seule une écriture réelle la déclenche.
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
      for (final f in fichiersLib()) {
        final code = _codeSansCommentaires(File(f));
        if (!code.contains('ResultatOfficielCourse resultat')) continue;
        if (!code.contains('montantOfficielPmu:')) continue;
        ecrivainsVerdict.add(f);
      }
      expect(ecrivainsVerdict, <String>['lib/providers/pmu_provider.dart'],
          reason: 'un seul fichier doit convertir un résultat officiel en '
              'montant officiel : pas de second moteur concurrent');
    });
  });
}
