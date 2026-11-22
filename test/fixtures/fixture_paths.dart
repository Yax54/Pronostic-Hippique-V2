// ═══════════════════════════════════════════════════════════════════════════
//  RÉSOLVEUR DE CHEMINS DES FIXTURES OFFICIELLES — LOT « TESTS REPRODUCTIBLES »
// ═══════════════════════════════════════════════════════════════════════════
//
//  ★ POURQUOI CE FICHIER
//
//  Treize fichiers de test lisaient des captures officielles PMU dans
//  `/home/user/recherche_pmu`, un dossier ABSENT du dépôt. Les tests ne
//  pouvaient donc pas être rejoués sur une autre machine : annoncer une suite
//  verte n'avait de sens que dans le sandbox qui avait produit les captures.
//
//  Les mêmes fichiers — octet pour octet, aucune donnée retouchée — sont
//  désormais versionnés sous `test/fixtures/recherche_pmu/`.
//
//  ★ CE QUE CE RÉSOLVEUR GARANTIT
//
//  1. Les captures du DÉPÔT sont utilisées en priorité (`test/fixtures/...`).
//  2. Si elles manquent, on retombe sur l'ancien emplacement absolu. Ce repli
//     n'est pas un confort : il évite qu'un environnement où seul l'ancien
//     dossier existe voie ses tests échouer pour une raison d'emplacement.
//  3. Le repli émet un avertissement visible, jamais silencieux.
//
//  ★ CE QU'IL NE FAIT PAS
//
//  Il ne modifie AUCUNE donnée, AUCUNE assertion, AUCUN résultat attendu. Il
//  ne fait que répondre à la question « où sont les fichiers ? ».
//
//  ★ UTILISATION
//
//      const String kDossier = kDossierMulti;   // au lieu du chemin absolu
//      const String kDossier = kDossierRapports;
//
//  Les constantes sont des `String` calculées à la compilation du test par
//  `dossierFixtures`, donc `const` n'est pas utilisable directement : voir
//  les variables `final` ci-dessous, ou appeler la fonction explicitement.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

/// Racine des fixtures versionnées, relative à la racine du projet.
const String _racineVersionnee = 'test/fixtures/recherche_pmu';

/// Ancien emplacement absolu, conservé uniquement en repli.
const String _racineSandbox = '/home/user/recherche_pmu';

/// Résout un sous-dossier de captures.
///
/// [sousDossier] vaut `'multi'` (captures complètes course + rapports) ou
/// `'rapports'` (captures de rapports non datées).
///
/// Retourne le chemin versionné s'il existe, sinon l'ancien chemin absolu.
/// Dans ce second cas, un avertissement est émis : le repli ne doit jamais
/// passer inaperçu, car il signifie que le test n'est PAS reproductible.
String dossierFixtures(String sousDossier) {
  final versionne = '$_racineVersionnee/$sousDossier';
  if (Directory(versionne).existsSync()) return versionne;

  final ancien = '$_racineSandbox/$sousDossier';
  if (Directory(ancien).existsSync()) {
    // ignore: avoid_print
    print('⚠️ FIXTURES : « $versionne » absent — repli sur « $ancien ». '
        'Ce test N\'EST PAS reproductible hors de cet environnement.');
    return ancien;
  }

  // Ni l'un ni l'autre : on rend le chemin versionné. Le test échouera avec
  // un message qui désigne l'emplacement ATTENDU, ce qui est plus utile
  // qu'un échec sur l'ancien chemin d'un sandbox qui n'existe plus.
  return versionne;
}

/// Captures complètes (course + rapports publiés).
String get dossierMulti => dossierFixtures('multi');

/// Captures de rapports non datées.
String get dossierRapports => dossierFixtures('rapports');
