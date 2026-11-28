// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER POIDS IA — D-3 : PREUVE SUR LE VÉRITABLE CHEMIN `_load()`
//
//  OBJET : établir, par MESURE, que la politique de récupération arbitrée le
//  27/11/2026 est réellement appliquée quand une pondération est corrompue
//  DANS UN BLOB DE SAUVEGARDE, rechargé par le chemin de production
//  (`recharger()` → `_load()` → `fromJson`) — et non par un appel direct au
//  désérialiseur.
//
//  POLITIQUE ARBITRÉE (rappel intégral) :
//    1. Récupérer la dernière valeur authentique connue SI une source
//       existante, fiable et directement exploitable existe.
//       → ARBITRAGE : aucune n'existe (`ia_journal_v2` écarté explicitement,
//         aucune clé secondaire créée). La priorité 1 est donc SANS OBJET
//         aujourd'hui ; elle reste applicable si une telle source apparaissait.
//    2. Sinon : valeur INITIALE DU CONSTRUCTEUR pour le seul critère corrompu.
//       Aucune valeur neutre arbitraire.
//    3. Toutes les autres pondérations valides sont conservées STRICTEMENT.
//    4. La récupération est TRACÉE : critère, discipline, motif, valeur.
//
//  ⚠️ CE QUI ÉTAIT FAUX AVANT CETTE CORRECTION — MESURÉ, PAS SUPPOSÉ :
//     le chemin par discipline **supprimait** la clé corrompue au lieu de la
//     remplacer. `poidsEffectifsPourDiscipline` la comblait ensuite avec la
//     valeur **GLOBALE** du même critère : le consommateur recevait donc une
//     valeur appartenant à un AUTRE périmètre, ce que la politique interdit
//     (« aucune récupération d'une valeur appartenant à une autre discipline
//     ou à un autre critère »). Le test D3-a ci-dessous mesure les deux
//     comportements possibles et exige le comportement arbitré.
//
//  ⚠️ AUCUNE SAUVEGARDE ORIGINALE N'EST TOUCHÉE. Les blobs de ce harnais sont
//     construits en mémoire avec les sérialiseurs de PRODUCTION, puis écrits
//     dans `SharedPreferences` SIMULÉ. Les fichiers de
//     `/home/user/uploaded_files/` ne sont ni lus en écriture ni modifiés.
//
//  ⚠️ AUCUN APPRENTISSAGE N'EST DÉCLENCHÉ PAR CE HARNAIS : on ne fait que
//     charger. C'est précisément ce qui permet de vérifier que le compteur
//     d'apprentissage n'est pas réinitialisé par la récupération.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/services/ia_archive_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

const List<String> kCles = <String>[
  'forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline',
  'distSpec', 'jockey', 'repos', 'hippo', 'entraineur', 'elo',
  'terrain', 'divergence', 'poidsRel', 'progression', 'mouvCote', 'placeDepart',
];

const String kPoidsKey = 'ia_poids_v3';

/// Poids GLOBAUX du test : volontairement DIFFÉRENTS de la valeur initiale du
/// constructeur sur les 19 critères, afin qu'une confusion entre « valeur
/// globale » et « valeur initiale » soit IMMÉDIATEMENT visible dans les
/// mesures.
///
/// ⚠️ MONTAGE CORRIGÉ (27/11/2026) — DEUX DÉFAUTS DE MONTAGE MESURÉS, PAS
///    SUPPOSÉS :
///      (1) la somme valait 1,02 en centièmes : l'assertion
///          `closeTo(1.0, 1e-9)` échouait avec `Actual: 1.0200000000000005`.
///          Un montage à 1,02 n'est pas une table de poids plausible et
///          brouillait la lecture de la mesure.
///      (2) `discipline` (0,02) et `placeDepart` (0,03) étaient EXACTEMENT
///          égales aux valeurs initiales du constructeur : pour ces deux
///          critères, « remplacé par l'initiale » et « laissé intact »
///          devenaient indiscernables. La garde D3-g l'a détecté (`Actual: 2`)
///          et c'est précisément son rôle.
///    Somme vérifiée ci-dessous : 21+11+7+6+7+3+1+7+5+2+3+3+4+4+3+2+2+5+4
///    = 100 centièmes = 1,00.
const Map<String, double> kGlobauxTest = <String, double>{
  'forme': 0.2100, 'gains': 0.1100, 'record': 0.0700, 'cote': 0.0600,
  'constance': 0.0700, 'victoires': 0.0300, 'discipline': 0.0100,
  'distSpec': 0.0700, 'jockey': 0.0500, 'repos': 0.0200, 'hippo': 0.0300,
  'entraineur': 0.0300, 'elo': 0.0400, 'terrain': 0.0400, 'divergence': 0.0300,
  'poidsRel': 0.0200, 'progression': 0.0200, 'mouvCote': 0.0500,
  'placeDepart': 0.0400,
};

/// Table de discipline `trot_attele` : 19 critères, valeurs distinctes des
/// globales ET des initiales, pour tracer sans ambiguïté l'origine de chaque
/// valeur restituée.
const Map<String, double> kDiscAttelle = <String, double>{
  'forme': 0.3000, 'gains': 0.1200, 'record': 0.0600, 'cote': 0.0400,
  'constance': 0.0500, 'victoires': 0.0200, 'discipline': 0.0100,
  'distSpec': 0.0500, 'jockey': 0.0400, 'repos': 0.0200, 'hippo': 0.0200,
  'entraineur': 0.0200, 'elo': 0.0300, 'terrain': 0.0300, 'divergence': 0.0300,
  'poidsRel': 0.0200, 'progression': 0.0200, 'mouvCote': 0.1000,
  'placeDepart': 0.0400,
};

/// Seconde discipline, INTACTE : elle doit survivre octet pour octet.
/// ⚠️ `mouvCote` porté de 0,060 à 0,065 : à 0,060 il était EXACTEMENT égal à la
///    valeur initiale du constructeur (0,06), donc indiscernable. Détecté par la
///    garde D3-g (`plat : 1/19`). Aucune autre valeur n'a été retouchée.
const Map<String, double> kDiscPlat = <String, double>{
  'forme': 0.2700, 'gains': 0.1400, 'record': 0.0700, 'cote': 0.0500,
  'constance': 0.0600, 'victoires': 0.0300, 'discipline': 0.0150,
  'distSpec': 0.0400, 'jockey': 0.0350, 'repos': 0.0150, 'hippo': 0.0250,
  'entraineur': 0.0250, 'elo': 0.0350, 'terrain': 0.0350, 'divergence': 0.0250,
  'poidsRel': 0.0250, 'progression': 0.0250, 'mouvCote': 0.0650,
  'placeDepart': 0.0200,
};

/// Compteur d'apprentissage NON NUL : s'il revenait à 0, la mesure le verrait.
const int kMisesAJour = 437;

String _f(double v) => v.toStringAsFixed(12);

double _somme(Map<String, double> m) => m.values.fold(0.0, (a, b) => a + b);

IaPronostic _pronostic(String key, DateTime date) => IaPronostic(
      courseKey: key,
      nomCourse: 'PRIX $key',
      hippodrome: 'VINCENNES',
      discipline: 'Trot Attelé',
      datePronostic: date,
      scoresIA: const {'1': 100.0, '2': 90.0, '3': 80.0},
      scoresCriteres: <String, ScoresCriteres>{
        for (var n = 1; n <= 3; n++)
          '$n': ScoresCriteres(
            forme: 90.0 - n, gains: 80.0 - n, record: 70.0 - n,
            cote: 60.0 - n, constance: 50.0 + n, victoires: 40.0 + n,
            discipline: 30.0 + n, distSpec: 88.0 - n, jockey: 72.0 - n,
            repos: 55.0 + n, hippo: 68.0 - n, entraineur: 62.0 + n,
            elo: 78.0 - n, terrain: 70.0 + n, divergence: 50.0 + n,
            poidsRel: 66.0 - n, progression: 74.0 + n, mouvCote: 58.0 + n,
            placeDepart: 64.0 - n,
          ),
      },
      varianceScores: 10.0,
      confiancePredite: 70.0,
      typePariConseille: 'Simple Gagnant',
      favoriIaNom: 'CHEVAL_1',
    );

String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}${d.year}';

/// Écrit un blob de poids où `poidsParDiscipline.trot_attele.constance` est
/// CORROMPU (valeur texte, inexploitable), et sème pronostics + seuils.
///
/// On passe par `json.encode` sur une map Dart : le blob est donc un JSON
/// RÉEL, comme celui d'un téléphone. La corruption est une valeur `String`
/// là où un nombre est attendu — exactement un cas de fichier abîmé.
Future<void> _semerAvecCorruption({
  required Object valeurCorrompue,
  required List<IaPronostic> pronostics,
}) async {
  final discAttelleCorrompu = <String, Object>{
    ...kDiscAttelle,
    'constance': valeurCorrompue, // ← LA seule valeur corrompue
  };
  final blob = <String, Object>{
    ...kGlobauxTest,
    'poidsParDiscipline': <String, Object>{
      'trot_attele': discAttelleCorrompu,
      'plat': <String, Object>{...kDiscPlat},
    },
    'nbMisesAJour': kMisesAJour,
    'calibrationScore': 50.0,
  };

  SharedPreferences.setMockInitialValues(<String, Object>{
    'ia_precision_migrated_v3': true,
    kPoidsKey: json.encode(blob),
    // Seuils : valeurs NON par défaut pour prouver leur conservation.
    'ia_seuils_v1': json.encode(<String, dynamic>{
      'sg': 66.0,   // seuilSimpleGagnant  (défaut 80)
      'ti': 41.0,   // seuilTierce         (défaut 35)
      'qi': 7.0,    // seuilQuinte         (défaut  0)
    }),
    'ia_precision_v2': json.encode(<String, dynamic>{}),
    'ia_stats_labels_v1': json.encode(<String, dynamic>{}),
    'ia_stats_types_v1': <String>[],
    'ia_journal_v2': <String>[],
    'ia_pronostics_v2':
        pronostics.map((p) => json.encode(p.toJson())).toList(),
  });
  SharedPreferences.resetStatic();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════
  //  GARDE — le montage lui-même est-il sain ?
  // ═══════════════════════════════════════════════════════════════════════
  test('D3-g — garde : les valeurs du montage sont DISTINCTES des initiales', () {
    var identiques = 0;
    for (final k in kCles) {
      if ((kDiscAttelle[k]! - IaPoidsAdaptatifs.defauts[k]!).abs() < 1e-12) {
        identiques++;
      }
    }
    // ignore: avoid_print
    print('D3-g valeurs de discipline identiques à la valeur initiale : '
        '$identiques/19 (0 attendu : sinon « remplacé par l\'initiale » et '
        '« laissé intact » seraient indiscernables)');
    expect(identiques, 0,
        reason: 'le montage doit rendre les deux hypothèses mesurablement '
            'distinctes, sinon la preuve serait vacue');
    expect(kDiscAttelle.length, 19);
    expect(kDiscPlat.length, 19);
    expect(kGlobauxTest.length, 19);
    // Les globales doivent aussi être distinctes des initiales.
    var idGlob = 0;
    for (final k in kCles) {
      if ((kGlobauxTest[k]! - IaPoidsAdaptatifs.defauts[k]!).abs() < 1e-12) {
        idGlob++;
      }
    }
    // ⚠️ DÉFAUT DE MONTAGE MESURÉ ET CORRIGÉ : `kGlobauxTest` somme désormais
    //    EXACTEMENT 1,00 (en centièmes) dans les deux définitions. Un montage à
    //    1,02 rendait l'assertion `closeTo(1.0, 1e-9)` de D3-a fausse pour une
    //    raison de FIXTURE, pas de production — la cause a été isolée, pas
    //    contournée.
    final sommeGlob = _somme(kGlobauxTest);
    // ignore: avoid_print
    print('D3-g Σ des poids globaux du montage = ${_f(sommeGlob)} (1,00 exigé)');
    expect(sommeGlob, closeTo(1.0, 1e-12),
        reason: 'le montage doit être une table de poids plausible');
    // ignore: avoid_print
    print('D3-g valeurs globales identiques à la valeur initiale : '
        '$idGlob/19');
    expect(idGlob, 0);
    // La seconde discipline doit elle aussi être intégralement distincte.
    var idPlat = 0;
    for (final k in kCles) {
      if ((kDiscPlat[k]! - IaPoidsAdaptatifs.defauts[k]!).abs() < 1e-12) {
        idPlat++;
      }
    }
    // ignore: avoid_print
    print('D3-g valeurs de "plat" identiques à la valeur initiale : $idPlat/19');
    expect(idPlat, 0);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D3-a — LE CŒUR : corruption par discipline sur le VRAI chemin `_load()`
  // ═══════════════════════════════════════════════════════════════════════
  test('D3-a — _load() : une pondération de discipline corrompue est REMPLACÉE '
      'par la valeur initiale, tout le reste est conservé', () async {
    final base = DateTime.now().subtract(const Duration(days: 10));
    final pronostics = <IaPronostic>[
      for (var i = 0; i < 3; i++)
        _pronostic('R1C${i + 1}_${_fmt(base.add(Duration(days: i)))}',
            base.add(Duration(days: i))),
    ];
    await _semerAvecCorruption(
        valeurCorrompue: 'CORROMPU', pronostics: pronostics);

    // ★ CHEMIN DE PRODUCTION : `recharger()` → `_load()` → `fromJson`.
    await IaMemoryService.instance.recharger();
    final mem = IaMemoryService.instance;

    final anomalies = mem.anomaliesRestaurationPoids;
    final ppd = mem.poids.poidsParDiscipline;

    // ── Traçabilité ────────────────────────────────────────────────────────
    // ignore: avoid_print
    print('D3-a anomalies de restauration (${anomalies.length}) :');
    for (final a in anomalies) {
      // ignore: avoid_print
      print('D3-a    • $a');
    }
    expect(anomalies, isNotEmpty,
        reason: 'la récupération doit être TRACÉE, sinon elle est muette');
    final traceConstance =
        anomalies.where((a) => a.contains('constance')).toList();
    expect(traceConstance, isNotEmpty,
        reason: 'le critère corrompu doit être nommé dans la trace');
    final trace = traceConstance.first;
    // Trace complète exigée : critère + discipline + motif + valeur.
    expect(trace.contains('trot_attele'), isTrue,
        reason: 'la DISCIPLINE doit figurer dans la trace : « $trace »');
    expect(trace.contains('constance'), isTrue,
        reason: 'le CRITÈRE doit figurer dans la trace : « $trace »');
    expect(trace.contains('non numérique'), isTrue,
        reason: 'le MOTIF doit figurer dans la trace : « $trace »');
    expect(trace.contains('${IaPoidsAdaptatifs.defauts['constance']}'), isTrue,
        reason: 'la VALEUR DE REMPLACEMENT doit figurer dans la trace : '
            '« $trace »');
    // Le montant exact d'anomalies : UNE seule valeur corrompue dans tout le
    // blob. Toute anomalie supplémentaire signalerait une récupération
    // intempestive touchant des valeurs saines.
    // ignore: avoid_print
    print('D3-a nombre d\'anomalies tracées = ${anomalies.length} '
        '(1 attendu : une seule valeur était corrompue)');
    expect(anomalies.length, 1,
        reason: 'seule la valeur corrompue doit produire une anomalie — '
            'les 37 autres pondérations (19 globales + 2×19 discipline moins '
            'la corrompue) sont valides et ne doivent pas être touchées');

    // ── Le critère corrompu est REMPLACÉ par la valeur initiale ────────────
    expect(ppd['trot_attele'], isNotNull,
        reason: 'la discipline doit survivre à la corruption');
    final attelle = ppd['trot_attele']!;
    final remplacee = attelle['constance'];
    // ignore: avoid_print
    print('D3-a trot_attele.constance : valeur restituée = '
        '${remplacee == null ? "ABSENTE" : _f(remplacee)} · '
        'valeur initiale du constructeur = '
        '${_f(IaPoidsAdaptatifs.defauts['constance']!)} · '
        'valeur GLOBALE du même critère = ${_f(kGlobauxTest['constance']!)}');
    expect(remplacee, isNotNull,
        reason: 'la clé corrompue ne doit PAS disparaître : elle doit être '
            'remplacée (avant correction elle était supprimée, puis comblée '
            'par la valeur GLOBALE via `poidsEffectifsPourDiscipline`)');
    expect(remplacee, closeTo(IaPoidsAdaptatifs.defauts['constance']!, 1e-12),
        reason: 'la valeur de remplacement doit être la valeur INITIALE DU '
            'CONSTRUCTEUR pour ce seul critère');
    expect((remplacee! - kGlobauxTest['constance']!).abs(), greaterThan(1e-6),
        reason: 'la valeur de remplacement ne doit PAS provenir du périmètre '
            'GLOBAL : ce serait une récupération d\'une valeur appartenant à '
            'un autre périmètre, expressément interdite');

    // ── TOUTES les autres valeurs de CETTE discipline sont conservées ──────
    var ecartDisc = 0.0;
    var autresTouchees = 0;
    for (final k in kCles) {
      if (k == 'constance') continue;
      final d = (attelle[k]! - kDiscAttelle[k]!).abs();
      if (d > 1e-12) autresTouchees++;
      if (d > ecartDisc) ecartDisc = d;
    }
    // ignore: avoid_print
    print('D3-a trot_attele : ${19 - 1 - autresTouchees}/18 autres critères '
        'conservés exactement · écart max = ${_f(ecartDisc)} · '
        'clés présentes = ${attelle.length}');
    expect(autresTouchees, 0,
        reason: 'les 18 autres pondérations de la discipline doivent être '
            'conservées STRICTEMENT');
    expect(attelle.length, 19,
        reason: 'la table doit conserver ses 19 clés');

    // ── L'AUTRE discipline est intacte octet pour octet ────────────────────
    final plat = ppd['plat']!;
    var ecartPlat = 0.0;
    for (final k in kCles) {
      final d = (plat[k]! - kDiscPlat[k]!).abs();
      if (d > ecartPlat) ecartPlat = d;
    }
    // ignore: avoid_print
    print('D3-a plat (discipline intacte) : écart max = ${_f(ecartPlat)} · '
        'clés = ${plat.length}');
    expect(ecartPlat, lessThanOrEqualTo(1e-12),
        reason: 'une corruption dans UNE discipline ne doit pas toucher les '
            'autres disciplines');

    // ── Les 19 poids GLOBAUX sont intacts ──────────────────────────────────
    var ecartGlob = 0.0;
    for (final k in kCles) {
      final d = (mem.poids.getPoids(k) - kGlobauxTest[k]!).abs();
      if (d > ecartGlob) ecartGlob = d;
    }
    // ignore: avoid_print
    print('D3-a poids globaux : écart max = ${_f(ecartGlob)} · Σ = '
        '${_f(_somme(<String, double>{for (final k in kCles) k: mem.poids.getPoids(k)}))}');
    expect(ecartGlob, lessThanOrEqualTo(1e-12),
        reason: 'une corruption dans une discipline ne doit pas toucher les '
            'poids GLOBAUX');
    // Et la somme globale n'est pas re-projetée au chargement.
    expect(
        _somme(<String, double>{for (final k in kCles) k: mem.poids.getPoids(k)}),
        closeTo(1.0, 1e-9),
        reason: 'Σ globale du montage = 1,00 : le chargement ne doit pas la '
            'modifier (`fromJson` n\'appelle jamais `clamp()`)');

    // ── Le compteur d'apprentissage n'est PAS réinitialisé ─────────────────
    // ignore: avoid_print
    print('D3-a nbMisesAJour = ${mem.poids.nbMisesAJour} '
        '(attendu $kMisesAJour)');
    expect(mem.poids.nbMisesAJour, kMisesAJour,
        reason: 'la récupération ne doit pas toucher au compteur '
            'd\'apprentissage');

    // ── Les pronostics sont conservés ──────────────────────────────────────
    // ignore: avoid_print
    print('D3-a pronostics chargés = ${mem.pronostics.length} '
        '(attendu ${pronostics.length})');
    expect(mem.pronostics.length, pronostics.length,
        reason: 'les pronostics doivent rester accessibles malgré la '
            'corruption des poids');

    // ── Les seuils sont conservés ──────────────────────────────────────────
    final seuils = mem.getSeuilsAdaptatifs();
    // ignore: avoid_print
    print('D3-a seuils : seuilSimpleGagnant=${seuils.seuilSimpleGagnant} '
        '(saisi 66, défaut 80) · seuilTierce=${seuils.seuilTierce} '
        '(saisi 41, défaut 35) · seuilQuinte=${seuils.seuilQuinte} '
        '(saisi 7, défaut 0)');
    expect(seuils.seuilSimpleGagnant, closeTo(66.0, 1e-9),
        reason: 'les seuils adaptatifs doivent être conservés (valeur saisie '
            '66, distincte du défaut 80 : la mesure n\'est pas vacue)');
    expect(seuils.seuilTierce, closeTo(41.0, 1e-9),
        reason: 'les seuils adaptatifs doivent être conservés (41 vs défaut 35)');
    expect(seuils.seuilQuinte, closeTo(7.0, 1e-9),
        reason: 'les seuils adaptatifs doivent être conservés (7 vs défaut 0)');

    // ── Aucun apprentissage déclenché : le journal reste vide ──────────────
    expect(mem.journal, isEmpty,
        reason: 'une lecture ne doit jamais déclencher d\'apprentissage');
    // ── Aucune anomalie de projection (on n\'a pas projeté) ────────────────
    expect(mem.anomaliesProjection, isEmpty);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D3-b — même preuve pour NaN (corruption binaire, pas seulement texte)
  // ═══════════════════════════════════════════════════════════════════════
  test('D3-b — _load() : un NaN dans une discipline est remplacé, pas propagé',
      () async {
    final base = DateTime.now().subtract(const Duration(days: 10));
    // `json.encode` refuse NaN (non fini) : on écrit le JSON à la main pour
    // simuler exactement un blob binaire abîmé, comme le ferait un fichier
    // tronqué ou un octet corrompu sur disque.
    final blob = <String, Object>{
      ...kGlobauxTest,
      'poidsParDiscipline': <String, Object>{
        'trot_attele': <String, Object>{...kDiscAttelle},
        'plat': <String, Object>{...kDiscPlat},
      },
      'nbMisesAJour': kMisesAJour,
      'calibrationScore': 50.0,
    };
    var brut = json.encode(blob);
    // On remplace la valeur de discipline par un littéral non fini.
    brut = brut.replaceFirst(
        '"trot_attele":{"forme":0.3', '"trot_attele":{"forme":NaN');

    SharedPreferences.setMockInitialValues(<String, Object>{
      'ia_precision_migrated_v3': true,
      kPoidsKey: brut,
      'ia_seuils_v1': json.encode(<String, dynamic>{}),
      'ia_precision_v2': json.encode(<String, dynamic>{}),
      'ia_stats_labels_v1': json.encode(<String, dynamic>{}),
      'ia_stats_types_v1': <String>[],
      'ia_journal_v2': <String>[],
      'ia_pronostics_v2': <IaPronostic>[
        _pronostic('R1C1_${_fmt(base)}', base),
      ].map((p) => json.encode(p.toJson())).toList(),
    });
    SharedPreferences.resetStatic();

    await IaMemoryService.instance.recharger();
    final mem = IaMemoryService.instance;

    final anomalies = mem.anomaliesRestaurationPoids;
    // ignore: avoid_print
    print('D3-b NaN injecté (JSON non conforme) → anomalies = '
        '${anomalies.length} : ${anomalies.isEmpty ? "(aucune)" : anomalies.first}');
    // ⚠️ Un JSON littéralement non conforme est illisible pour `json.decode` :
    //    le blob entier est alors écarté et la table par défaut conservée.
    //    C'est le comportement D-3 documenté, et il est TRACÉ. On le mesure
    //    sans le maquiller.
    if (anomalies.isNotEmpty) {
      expect(anomalies.first.contains('illisible'), isTrue,
          reason: 'un blob non décodable doit être signalé comme illisible');
      // La table par défaut est utilisée. ⚠️ DEPUIS LA CLÔTURE (28/11/2026),
      //   le repli de `_load()` n'est PLUS la table BRUTE `defaut()` : le champ
      //   est initialisé à `IaPoidsAdaptatifs.effectif()` (table EFFECTIVE,
      //   Σ = 1,00) et il est CONSERVÉ tel quel quand le blob est illisible.
      //   La référence attendue est donc `effectif()`, et non `defauts` (qui
      //   reste la table brute de référence, Σ = 1,26).
      var ecartInit = 0.0;
      final effectif = IaPoidsAdaptatifs.effectif();
      for (final k in kCles) {
        final d = (mem.poids.getPoids(k) - effectif.getPoids(k)).abs();
        if (d > ecartInit) ecartInit = d;
      }
      // ignore: avoid_print
      print('D3-b blob illisible → table EFFECTIVE d\'usine conservée, écart '
          'à effectif() = ${_f(ecartInit)}');
      expect(ecartInit, lessThanOrEqualTo(1e-12),
          reason: 'blob illisible → table EFFECTIVE d\'usine complète, jamais '
              'partielle');
      // TÉMOIN : la table servie n'est pas la table BRUTE — sans quoi
      // l'assertion précédente serait indiscernable d'une absence de projection.
      var ecartBrut = 0.0;
      for (final k in kCles) {
        final d =
            (mem.poids.getPoids(k) - IaPoidsAdaptatifs.defauts[k]!).abs();
        if (d > ecartBrut) ecartBrut = d;
      }
      // ignore: avoid_print
      print('D3-b écart à la table BRUTE (`defauts`) = ${_f(ecartBrut)} '
          '(doit être ≠ 0 : la table servie est projetée)');
      expect(ecartBrut, greaterThan(1e-6),
          reason: 'TÉMOIN : la table servie est bien la table EFFECTIVE, pas '
              'la table brute — `defauts` reste la référence brute');
      // Et les pronostics restent chargés : l\'échec est CONFINÉ aux poids.
      expect(mem.pronostics, isNotEmpty,
          reason: 'un blob de poids illisible ne doit pas faire perdre les '
              'pronostics');
    } else {
      throw StateError('montage inattendu : le blob a été décodé alors qu\'il '
          'contient un littéral non conforme — la mesure doit être revue');
    }
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D3-c — une pondération HORS BORNES n'est PAS une corruption
  // ═══════════════════════════════════════════════════════════════════════
  test('D3-c — _load() : une valeur authentique hors des nouvelles bornes est '
      'CONSERVÉE, jamais remplacée', () async {
    final base = DateTime.now().subtract(const Duration(days: 10));
    // `cote` de la discipline à 0,90 : très au-dessus du plafond 0,40.
    final attelleHorsBornes = <String, Object>{
      ...kDiscAttelle,
      'cote': 0.90,
    };
    final blob = <String, Object>{
      ...kGlobauxTest,
      'poidsParDiscipline': <String, Object>{
        'trot_attele': attelleHorsBornes,
        'plat': <String, Object>{...kDiscPlat},
      },
      'nbMisesAJour': kMisesAJour,
      'calibrationScore': 50.0,
    };
    SharedPreferences.setMockInitialValues(<String, Object>{
      'ia_precision_migrated_v3': true,
      kPoidsKey: json.encode(blob),
      'ia_seuils_v1': json.encode(<String, dynamic>{}),
      'ia_precision_v2': json.encode(<String, dynamic>{}),
      'ia_stats_labels_v1': json.encode(<String, dynamic>{}),
      'ia_stats_types_v1': <String>[],
      'ia_journal_v2': <String>[],
      'ia_pronostics_v2': <IaPronostic>[
        _pronostic('R1C1_${_fmt(base)}', base),
      ].map((p) => json.encode(p.toJson())).toList(),
    });
    SharedPreferences.resetStatic();

    await IaMemoryService.instance.recharger();
    final mem = IaMemoryService.instance;
    final attelle = mem.poids.poidsParDiscipline['trot_attele']!;
    final anomalies = mem.anomaliesRestaurationPoids;

    // ignore: avoid_print
    print('D3-c trot_attele.cote = ${_f(attelle['cote']!)} (saisi 0,90, '
        'plafond de référence 0,40) · anomalies = ${anomalies.length}');
    expect(attelle['cote'], closeTo(0.90, 1e-12),
        reason: 'une pondération AUTHENTIQUE hors des nouvelles bornes n\'est '
            'pas une donnée corrompue : elle doit être conservée telle quelle');
    expect(anomalies, isEmpty,
        reason: 'aucune anomalie ne doit être tracée pour une valeur hors '
            'bornes : ce n\'est pas une corruption');
    expect(mem.poids.nbMisesAJour, kMisesAJour);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D3-d — les ARCHIVES survivent à une corruption des poids
  // ═══════════════════════════════════════════════════════════════════════
  test('D3-d — _load() avec poids corrompus : les archives restent accessibles',
      () async {
    final base = DateTime.now().subtract(const Duration(days: 40));
    final archive = _pronostic('ARCH_${_fmt(base)}', base);
    await _semerAvecCorruption(
        valeurCorrompue: 'CORROMPU',
        pronostics: <IaPronostic>[_pronostic('R1C1_${_fmt(base)}', base)]);

    // On ajoute une version d'archive par le chemin PUBLIC de production.
    final ok = await IaArchiveService.instance
        .securiser(archive, motif: ArchiveReason.eviction);

    await IaMemoryService.instance.recharger();

    // L'archive doit être relisible après le rechargement de la mémoire IA.
    final versions = await IaArchiveService.instance
        .versionsArchiveesPourCourse(archive.courseKey);
    // ignore: avoid_print
    print('D3-d archivage confirmé = $ok · versions relues pour '
        '"${archive.courseKey}" = ${versions.length}');
    expect(ok, isTrue, reason: 'l\'archivage doit réussir');
    expect(versions, isNotEmpty,
        reason: 'les archives doivent rester accessibles malgré la corruption '
            'des poids');
    // Et la récupération des poids a bien eu lieu en parallèle.
    expect(IaMemoryService.instance.anomaliesRestaurationPoids, isNotEmpty);
    expect(IaMemoryService.instance.poids.poidsParDiscipline['trot_attele'],
        isNotNull);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D3-e — GARDE : sans corruption, AUCUNE anomalie et rien n'est touché
  // ═══════════════════════════════════════════════════════════════════════
  test('D3-e — sans corruption : aucune anomalie, aucune valeur modifiée',
      () async {
    final base = DateTime.now().subtract(const Duration(days: 10));
    final blob = <String, Object>{
      ...kGlobauxTest,
      'poidsParDiscipline': <String, Object>{
        'trot_attele': <String, Object>{...kDiscAttelle},
        'plat': <String, Object>{...kDiscPlat},
      },
      'nbMisesAJour': kMisesAJour,
      'calibrationScore': 50.0,
    };
    SharedPreferences.setMockInitialValues(<String, Object>{
      'ia_precision_migrated_v3': true,
      kPoidsKey: json.encode(blob),
      'ia_seuils_v1': json.encode(<String, dynamic>{}),
      'ia_precision_v2': json.encode(<String, dynamic>{}),
      'ia_stats_labels_v1': json.encode(<String, dynamic>{}),
      'ia_stats_types_v1': <String>[],
      'ia_journal_v2': <String>[],
      'ia_pronostics_v2': <IaPronostic>[
        _pronostic('R1C1_${_fmt(base)}', base),
      ].map((p) => json.encode(p.toJson())).toList(),
    });
    SharedPreferences.resetStatic();

    await IaMemoryService.instance.recharger();
    final mem = IaMemoryService.instance;
    // ignore: avoid_print
    print('D3-e sans corruption : anomalies = '
        '${mem.anomaliesRestaurationPoids.length} (0 attendu)');
    expect(mem.anomaliesRestaurationPoids, isEmpty,
        reason: 'sans corruption, la trace doit rester VIDE — sinon elle serait '
            'bavarde et sans valeur diagnostique');
    // Les 19+19+19 valeurs sont restituées exactement.
    var ecart = 0.0;
    for (final k in kCles) {
      ecart = (mem.poids.getPoids(k) - kGlobauxTest[k]!).abs() > ecart
          ? (mem.poids.getPoids(k) - kGlobauxTest[k]!).abs()
          : ecart;
      ecart = (mem.poids.poidsParDiscipline['trot_attele']![k]! -
                      kDiscAttelle[k]!)
                  .abs() >
              ecart
          ? (mem.poids.poidsParDiscipline['trot_attele']![k]! - kDiscAttelle[k]!)
              .abs()
          : ecart;
      ecart = (mem.poids.poidsParDiscipline['plat']![k]! - kDiscPlat[k]!).abs() >
              ecart
          ? (mem.poids.poidsParDiscipline['plat']![k]! - kDiscPlat[k]!).abs()
          : ecart;
    }
    // ignore: avoid_print
    print('D3-e écart max sur 57 pondérations restituées = ${_f(ecart)}');
    expect(ecart, lessThanOrEqualTo(1e-12),
        reason: 'sans corruption, les 57 pondérations doivent être restituées '
            'à l\'identique');
  });
}
