// ═══════════════════════════════════════════════════════════════════════════
//  INITIALISATION EFFECTIVE DES POIDS — `IaPoidsAdaptatifs.effectif()`
//
//  OBJET — démontrer que les tables NOUVELLES (installation vierge,
//  réinitialisation complète, reset des poids, repli sans blob) sont créées à
//  Σ = 1,00 SANS toucher à une seule valeur historique, et SANS modifier
//  `defaut()` ni la projection.
//
//  CE QUE CE FICHIER N'EST PAS : ce n'est ni un second moteur, ni une réplique
//  arithmétique de la projection. Toutes les valeurs sont LUES sur le code de
//  production (`effectif()`, `clamp()`, `projeter()`, `fromJson`, le
//  singleton `IaMemoryService`). Les bornes et les valeurs de référence sont
//  recopiées uniquement pour être OPPOSÉES à la production : si la production
//  change, ces tests échouent au lieu de valider une mesure périmée.
//
//  VÉRIFICATIONS INDÉPENDANTES (exigence explicite) — les contraintes ne sont
//  pas contrôlées par comparaison d'`effectif()` à lui-même :
//    • Σ = 1,00 est mesurée par SOMME des 19 champs lus un par un ;
//    • chaque plancher et chaque plafond est vérifié CONTRE LA BORNE RECOPIÉE,
//      critère par critère, sans passer par `bornesIndividuelles()` ;
//    • la part enrichie est calculée à partir des 7 clés de base recopiées ;
//    • `defaut()` est opposé aux 19 littéraux de référence à 1e-15 ;
//    • le chemin de chargement est opposé à une table HISTORIQUE dont la somme
//      vaut 1,26 puis 0,90 (volontairement ≠ 1,00).
//
//  ⚠️ AUCUNE MODIFICATION DE PRODUCTION dans ce fichier. Aucun APK, aucune
//     réinitialisation réelle, aucun apprentissage déclenché.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

// ─── Référentiel recopié de la production — OPPOSÉ, jamais utilisé pour agir ──

const List<String> kCles = <String>[
  'forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline',
  'distSpec', 'jockey', 'repos', 'hippo', 'entraineur', 'elo',
  'terrain', 'divergence', 'poidsRel', 'progression', 'mouvCote', 'placeDepart',
];

const List<String> kBase = <String>[
  'forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline',
];

/// Les 19 valeurs de référence du constructeur (Σ = 1,26) — INCHANGÉES.
const Map<String, double> kReference = <String, double>{
  'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
  'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
  'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
  'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05, 'divergence': 0.04,
  'poidsRel': 0.03, 'progression': 0.03, 'mouvCote': 0.06,
  'placeDepart': 0.03,
};

/// Bornes individuelles recopiées de `bornesIndividuelles()` (models l.871).
/// Elles servent d'OPPOSITION : la vérification ne passe pas par la méthode.
const Map<String, List<double>> kBornes = <String, List<double>>{
  'forme':      <double>[0.05,  0.55],
  'gains':      <double>[0.04,  0.40],
  'record':     <double>[0.03,  0.35],
  'cote':       <double>[0.05,  0.40],
  'constance':  <double>[0.03,  0.25],
  'victoires':  <double>[0.01,  0.15],
  'discipline': <double>[0.01,  0.10],
  'distSpec':   <double>[0.005, 0.18],
  'jockey':     <double>[0.005, 0.15],
  'repos':      <double>[0.005, 0.08],
  'hippo':      <double>[0.005, 0.10],
  'entraineur': <double>[0.005, 0.08],
  'elo':        <double>[0.005, 0.10],
  'terrain':    <double>[0.005, 0.10],
  'divergence': <double>[0.005, 0.08],
  'poidsRel':   <double>[0.005, 0.07],
  'progression':<double>[0.005, 0.08],
  'mouvCote':   <double>[0.005, 0.12],
  'placeDepart':<double>[0.005, 0.07],
};

const double kPartMin = 0.18;
const double kPartMax = 0.40;

const String kPoidsKey = 'ia_poids_v3';

String f12(double v) => v.toStringAsFixed(12);

/// Les 19 poids lus UN PAR UN sur une instance — aucune agrégation cachée.
Map<String, double> lire19(IaPoidsAdaptatifs p) =>
    <String, double>{for (final k in kCles) k: p.getPoids(k)};

double somme19(Map<String, double> m) =>
    kCles.fold(0.0, (a, k) => a + (m[k] ?? 0.0));

double sommeGroupe(Map<String, double> m, List<String> cles) =>
    cles.fold(0.0, (a, k) => a + (m[k] ?? 0.0));

double partEnrichie(Map<String, double> m) {
  final total = somme19(m);
  if (total == 0) return 0.0;
  return (total - sommeGroupe(m, kBase)) / total;
}

/// Vérifie les contraintes CONTRE LES VALEURS RECOPIÉES (pas contre la prod).
void verifierContraintes(Map<String, double> m, {required String contexte}) {
  expect(somme19(m), closeTo(1.0, 1e-12),
      reason: '$contexte : Σ des 19 poids lus un par un doit valoir 1,00');
  for (final k in kCles) {
    final v = m[k]!;
    final b = kBornes[k]!;
    expect(v.isNaN, isFalse, reason: '$contexte : $k est NaN');
    expect(v.isFinite, isTrue, reason: '$contexte : $k est infini');
    expect(v, greaterThanOrEqualTo(b[0] - 1e-12),
        reason: '$contexte : $k = $v sous son plancher recopié ${b[0]}');
    expect(v, lessThanOrEqualTo(b[1] + 1e-12),
        reason: '$contexte : $k = $v au-dessus de son plafond recopié ${b[1]}');
  }
  final part = partEnrichie(m);
  expect(part, greaterThanOrEqualTo(kPartMin - 1e-12),
      reason: '$contexte : part enrichie $part sous 0,18');
  expect(part, lessThanOrEqualTo(kPartMax + 1e-12),
      reason: '$contexte : part enrichie $part au-dessus de 0,40');
}

/// Table HISTORIQUE volontairement hors Σ = 1,00 (0,90) : sert à prouver que
/// le chargement ne renormalise RIEN.
Map<String, dynamic> tableHistorique09() {
  const facteur = 0.90 / 1.26;
  return <String, dynamic>{
    for (final k in kCles) k: kReference[k]! * facteur,
    'nbMisesAJour': 137,
    'calibrationScore': 68.3125,
    'dernierGradient': <String, double>{'forme': 0.0125, 'elo': -0.0075},
    'correlations': <String, double>{'forme|cote': 0.4125},
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═════════════════════════════════════════════════════════════════════════
  //  E-1 — `defaut()` EST ET RESTE LA RÉFÉRENCE BRUTE
  // ═════════════════════════════════════════════════════════════════════════
  test('E-1 — defaut() inchangé : Σ = 1,26 et 19 valeurs de référence', () {
    final p = IaPoidsAdaptatifs.defaut();
    final m = lire19(p);

    final s = somme19(m);
    // ignore: avoid_print
    print('[E-1] defaut() : Σ = $s · base = ${f12(sommeGroupe(m, kBase))} '
        '· enrichis = ${f12(sommeGroupe(
            m, kCles.where((k) => !kBase.contains(k)).toList()))}');

    // Somme brute TOUJOURS 1,26 : le contrat de `defaut()` n'est pas déplacé.
    expect(s, closeTo(1.26, 1e-12),
        reason: 'defaut() doit rester la référence BRUTE, Σ = 1,26');
    // Et les 19 littéraux sont opposés un par un.
    for (final k in kCles) {
      expect(m[k]!, closeTo(kReference[k]!, 1e-15),
          reason: 'defaut()[$k] doit être EXACTEMENT la référence '
              '${kReference[k]} (obtenu ${m[k]})');
    }
    // Aucune projection : aucune valeur n'a bougé de son littéral.
    expect(m.length, 19);
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  E-2 — `effectif()` PRODUIT UNE TABLE CONFORME, VÉRIFIÉE INDÉPENDAMMENT
  // ═════════════════════════════════════════════════════════════════════════
  test('E-2 — effectif() : Σ = 1,00, bornes et part enrichie vérifiées '
      'contre les valeurs recopiées', () {
    final m = lire19(IaPoidsAdaptatifs.effectif());
    // ignore: avoid_print
    print('[E-2] effectif() : Σ = ${f12(somme19(m))} · part enrichie = '
        '${f12(partEnrichie(m))}');
    for (final k in kCles) {
      // ignore: avoid_print
      print('[E-2]   ${k.padRight(12)} = ${f12(m[k]!)} '
          '(bornes ${kBornes[k]![0]} … ${kBornes[k]![1]})');
    }
    // Contrôle indépendant : bornes recopiées, somme calculée à la main.
    verifierContraintes(m, contexte: 'effectif()');
    expect(m.length, 19, reason: 'les 19 clés doivent être présentes');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  E-3 — `effectif()` EST EXACTEMENT `defaut()` PROJETÉ, ET IDEMPOTENT
  // ═════════════════════════════════════════════════════════════════════════
  test('E-3 — effectif() == defaut()..clamp(), et projection idempotente', () {
    final a = lire19(IaPoidsAdaptatifs.effectif());
    final manuel = IaPoidsAdaptatifs.defaut()..clamp();
    final b = lire19(manuel);

    var ecart = 0.0;
    var pire = '';
    for (final k in kCles) {
      final d = (a[k]! - b[k]!).abs();
      if (d > ecart) { ecart = d; pire = k; }
    }
    // ignore: avoid_print
    print('[E-3] effectif() vs defaut()..clamp() : écart max = '
        '${ecart.toStringAsExponential(6)} (pire="$pire")');
    expect(ecart, lessThanOrEqualTo(1e-15),
        reason: 'effectif() doit réutiliser la MÊME projection que clamp(), '
            'sans formule propre');

    // Idempotence de la projection réutilisée : re-clamper ne bouge rien.
    final rejoue = IaPoidsAdaptatifs.effectif()..clamp();
    final c = lire19(rejoue);
    var ecart2 = 0.0;
    for (final k in kCles) {
      final d = (a[k]! - c[k]!).abs();
      if (d > ecart2) ecart2 = d;
    }
    // ignore: avoid_print
    print('[E-3] effectif()..clamp() : écart max = '
        '${ecart2.toStringAsExponential(6)}');
    expect(ecart2, lessThanOrEqualTo(1e-15),
        reason: 'la projection doit être idempotente sur une table conforme');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  E-4 — L'INITIALISATION NE TOUCHE NI AUX COMPTEURS NI AUX MÉTADONNÉES
  // ═════════════════════════════════════════════════════════════════════════
  test('E-4 — effectif() : nbMisesAJour 0, calibration 50,0, momentum et '
      'disciplines VIDES', () {
    final p = IaPoidsAdaptatifs.effectif();
    // ignore: avoid_print
    print('[E-4] nbMisesAJour=${p.nbMisesAJour} '
        'calibrationScore=${p.calibrationScore} '
        'dernierGradient=${p.dernierGradient.length} '
        'correlations=${p.correlations.length} '
        'poidsParDiscipline=${p.poidsParDiscipline.length}');

    expect(p.nbMisesAJour, 0,
        reason: 'une nouvelle table n\'a subi aucune mise à jour');
    expect(p.calibrationScore, 50.0,
        reason: 'calibration neutre d\'usine');
    expect(p.dernierGradient, isEmpty,
        reason: 'le momentum initial doit rester VIDE (aucune mise à jour)');
    expect(p.correlations, isEmpty,
        reason: 'aucune corrélation apprise sur une table neuve');
    expect(p.poidsParDiscipline, isEmpty,
        reason: 'aucune table de discipline apprise');
    // Les indices de synthèse restent ceux du constructeur : la projection ne
    // les touche pas (elle ne concerne QUE les 19 poids).
    expect(p.poidsIndices.poidsCriteres, closeTo(0.40, 1e-15),
        reason: 'indices de synthèse non modifiés par l\'initialisation');
    expect(p.poidsIndices.poidsConfiance, closeTo(0.35, 1e-15));
    expect(p.poidsIndices.poidsReussite, closeTo(0.25, 1e-15));
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  E-5 — LE CHARGEMENT NE PROJETTE PAS : tables historiques préservées
  // ═════════════════════════════════════════════════════════════════════════
  test('E-5 — fromJson préserve EXACTEMENT une table historique, y compris '
      'de somme ≠ 1,00', () {
    // CAS 1 : table brute à Σ = 1,26.
    final brut1 = lire19(IaPoidsAdaptatifs.fromJson(
        <String, dynamic>{...kReference, 'nbMisesAJour': 0}));
    // ignore: avoid_print
    print('[E-5] fromJson(Σ=1,26) → Σ = ${f12(somme19(brut1))}');
    expect(somme19(brut1), closeTo(1.26, 1e-12),
        reason: 'fromJson ne projette pas : la somme écrite doit être rendue');
    for (final k in kCles) {
      expect(brut1[k]!, closeTo(kReference[k]!, 1e-15),
          reason: 'fromJson[$k] doit rendre la valeur écrite telle quelle');
    }

    // CAS 2 : table historique à Σ = 0,90 — une renormalisation serait visible.
    final histo = tableHistorique09();
    final brut2 = lire19(IaPoidsAdaptatifs.fromJson(histo));
    // ignore: avoid_print
    print('[E-5] fromJson(Σ=0,90) → Σ = ${f12(somme19(brut2))}');
    expect(somme19(brut2), closeTo(0.90, 1e-12),
        reason: 'une table historique de somme 0,90 doit être restituée à '
            '0,90 EXACTEMENT — toute projection au chargement serait un défaut');
    for (final k in kCles) {
      expect(brut2[k]!, closeTo(histo[k]! as double, 1e-15),
          reason: 'fromJson doit rendre $k identique à la valeur historique');
    }

    // TÉMOIN NÉGATIF : cette même table, projetée explicitement, change bien.
    final projete = IaPoidsAdaptatifs.fromJson(histo)..clamp();
    final mp = lire19(projete);
    final ecart = somme19(mp) > 0 ? (somme19(mp) - 0.90).abs() : 0.0;
    // ignore: avoid_print
    print('[E-5] témoin : la même table APRÈS clamp() → Σ = '
        '${f12(somme19(mp))} (écart à 0,90 = ${ecart.toStringAsExponential(6)})');
    expect(ecart, greaterThan(1e-6),
        reason: 'témoin : sans ce contraste, on ne saurait pas distinguer '
            '"non projeté" de "projection sans effet"');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  E-6 — LE VRAI SERVICE S'INITIALISE À Σ = 1,00 SANS AUCUNE TABLE
  //         (installation vierge), et ne projette PAS un blob existant
  // ═════════════════════════════════════════════════════════════════════════
  test('E-6 — installation vierge : le service sert Σ = 1,00 dès le premier '
      'pronostic ; avec blob, il sert la table du fichier', () async {
    // ── CHEMIN 1 : l'INITIALISEUR DE CHAMP, saisi AVANT toute autre action ─
    //    `_instance` est un `static final` initialisé paresseusement : le
    //    PREMIER accès à `IaMemoryService.instance` dans cet isolate construit
    //    le singleton et exécute `IaPoidsAdaptatifs _poids =
    //    IaPoidsAdaptatifs.effectif();`. C'est le seul instant où ce chemin est
    //    observable, donc on le capture ici, avant `recharger()`.
    final champ = lire19(IaMemoryService.instance.poids);
    // ignore: avoid_print
    print('[E-6] initialiseur de champ : Σ = ${f12(somme19(champ))} · '
        'forme = ${f12(champ['forme']!)}');
    verifierContraintes(champ, contexte: 'initialiseur de champ');
    expect((champ['forme']! - 0.21126760563380267).abs(), lessThan(1e-12),
        reason: 'l\'initialiseur de champ doit poser la table PROJETÉE : '
            'forme = 0,21126760563380267 et non la valeur brute 0,25');

    // ── CAS VIERGE : aucune clé `ia_poids_v3` sur le disque simulé ────────
    SharedPreferences.setMockInitialValues(<String, Object>{
      'ia_precision_migrated_v3': true,
    });
    SharedPreferences.resetStatic();
    await IaMemoryService.instance.recharger();

    final mem = IaMemoryService.instance;
    final vierge = lire19(mem.poids);
    // ignore: avoid_print
    print('[E-6] vierge : Σ = ${f12(somme19(vierge))} · part enrichie = '
        '${f12(partEnrichie(vierge))} · nbMisesAJour = '
        '${mem.poids.nbMisesAJour}');
    verifierContraintes(vierge, contexte: 'service vierge');
    expect(mem.poids.nbMisesAJour, 0,
        reason: 'aucune mise à jour ne doit avoir eu lieu à l\'initialisation');

    // Les poids SERVIS sont bien ceux de `effectif()`, et non ceux de
    // `defaut()` : c'est la vérification « dès le premier pronostic ».
    final attendu = lire19(IaPoidsAdaptatifs.effectif());
    var ecart = 0.0;
    for (final k in kCles) {
      final d = (vierge[k]! - attendu[k]!).abs();
      if (d > ecart) ecart = d;
    }
    // ignore: avoid_print
    print('[E-6] vierge vs effectif() : écart max = '
        '${ecart.toStringAsExponential(6)}');
    expect(ecart, lessThanOrEqualTo(1e-15),
        reason: 'le service doit servir EXACTEMENT effectif() sur une '
            'installation vierge — c\'est le chemin de production');

    // ── CAS BLOB HISTORIQUE : la table du fichier est servie TELLE QUELLE ──
    final histo = tableHistorique09();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'ia_precision_migrated_v3': true,
      kPoidsKey: json.encode(histo),
    });
    SharedPreferences.resetStatic();
    await IaMemoryService.instance.recharger();

    final servi = lire19(IaMemoryService.instance.poids);
    // ignore: avoid_print
    print('[E-6] blob Σ=0,90 : servi = ${f12(somme19(servi))} '
        '(attendu 0,900000000000)');
    expect(somme19(servi), closeTo(0.90, 1e-12),
        reason: 'un chargement ne doit JAMAIS projeter : la somme du fichier '
            'doit être servie telle quelle');
    for (final k in kCles) {
      expect(servi[k]!, closeTo(histo[k]! as double, 1e-15),
          reason: 'le poids historique $k doit être servi à l\'identique');
    }
    // Les métadonnées historiques sont préservées.
    expect(IaMemoryService.instance.poids.nbMisesAJour, 137,
        reason: 'nbMisesAJour historique préservé');
    expect(IaMemoryService.instance.poids.calibrationScore, 68.3125,
        reason: 'calibration historique préservée');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  E-7 — LES QUATRE CHEMINS MODIFIÉS PRODUISENT LA MÊME TABLE EFFECTIVE
  //
  //    Chemin 1 (initialiseur de champ, l.194) : mesuré en E-6, avant tout
  //    appel — c'est le seul instant où il est observable.
  //    Chemins 2/3/4 mesurés ici : `executerResetComplet` (l.2213),
  //    `recharger` (l.2308), `resetPoids` (l.6698).
  // ═════════════════════════════════════════════════════════════════════════
  test('E-7 — les 4 chemins d\'initialisation donnent effectif() à l\'identique',
      () async {
    final reference = lire19(IaPoidsAdaptatifs.effectif());
    final mem = IaMemoryService.instance;

    // ── Chemin 3 — repli de `recharger()` (l.2308) ────────────────────────
    //    Disque sans `ia_poids_v3` : le champ réécrit par `recharger()` est ce
    //    qui reste après `_load()`. C'est donc bien le repli qui est servi.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'ia_precision_migrated_v3': true,
    });
    SharedPreferences.resetStatic();
    await mem.recharger();
    final c3 = lire19(mem.poids);

    // ── Chemin 4 — `resetPoids()` explicite (l.6698) ──────────────────────
    //    On part d'un disque portant une table HISTORIQUE, pour que le reset
    //    soit non trivial : sans lui, `_load()` servirait cette table.
    final histo = tableHistorique09();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'ia_precision_migrated_v3': true,
      kPoidsKey: json.encode(histo),
    });
    SharedPreferences.resetStatic();
    await mem.recharger();
    // TÉMOIN : avant le reset, le service sert bien la table historique.
    expect(somme19(lire19(mem.poids)), closeTo(0.90, 1e-12),
        reason: 'TÉMOIN : avant `resetPoids()`, la table chargée est à 0,90 — '
            'sans ce témoin, l\'assertion serait vraie même sans reset');
    await mem.resetPoids();
    final c4 = lire19(mem.poids);

    // ── Chemin 2 — `executerResetComplet` étape 5 (l.2213) ────────────────
    //    Signature réelle : un callback d'effacement est requis.
    final prefs = await SharedPreferences.getInstance();
    await mem.executerResetComplet(() async {
      await prefs.remove(kPoidsKey);
      await prefs.remove('ia_seuils_v1');
    });
    final c2 = lire19(mem.poids);

    for (final e in <(String, Map<String, double>)>[
      ('recharger/repli', c3),
      ('resetPoids', c4),
      ('resetComplet', c2),
    ]) {
      var ecart = 0.0;
      var pire = '';
      for (final k in kCles) {
        final d = (e.$2[k]! - reference[k]!).abs();
        if (d > ecart) { ecart = d; pire = k; }
      }
      // ignore: avoid_print
      print('[E-7] ${e.$1.padRight(16)} Σ = ${f12(somme19(e.$2))} · '
          'écart à effectif() = ${ecart.toStringAsExponential(6)} '
          '(pire="$pire")');
      verifierContraintes(e.$2, contexte: 'chemin ${e.$1}');
      expect(ecart, lessThanOrEqualTo(1e-15),
          reason: 'le chemin ${e.$1} doit produire EXACTEMENT effectif()');
      expect((e.$2['forme']! - 0.21126760563380267).abs(), lessThan(1e-12),
          reason: 'le chemin ${e.$1} doit servir la table projetée, pas la '
              'table brute (forme brute = 0,25)');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
