// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER POIDS IA — §4 : VALIDATION FONCTIONNELLE DES CHEMINS RÉELS
//
//  CE QUE CE FICHIER PROUVE — ET CE QU'IL NE PROUVE PAS.
//
//  Les harnais `poids_projection_test` et `poids_demarrage_comparatif_test`
//  démontrent des PROPRIÉTÉS MATHÉMATIQUES sur les méthodes de production.
//  Ils ne démontrent pas que les CHEMINS RÉELS d'apprentissage produisent ces
//  évolutions. C'est l'objet de ce fichier.
//
//  ⚠️ AUCUN SECOND MOTEUR D'APPRENTISSAGE. Tout passe par
//     `IaMemoryService.instance` : `_load()` réel, `fromJson`/`toJson` réels,
//     `_save()` réel, `_apprendreParGradient` réel, `_apprendreParDiscipline`
//     réel, `clamp()`/`projeter()` réels. Aucun algorithme n'est réécrit et
//     aucune assertion ne s'appuie sur une réplique du mécanisme.
//
//  ⚠️ POINT DE MÉTHODE — POURQUOI LA GRAINE PASSE PAR LE STOCKAGE.
//     `enregistrerPronostic()` exige un `ZtCourse` + `List<ZtPartant>` et
//     REFUSE d'écrire si la date de course n'est pas déterminable (A-3).
//     Elle ne permet donc pas de fabriquer un historique « déjà résolu ».
//     On utilise donc exactement le chemin qu'emprunte un TÉLÉPHONE AU
//     DÉMARRAGE : un blob `ia_pronostics_v2` / `ia_poids_v3` écrit avec les
//     sérialiseurs de PRODUCTION, puis `recharger()` → `_load()` → `fromJson`.
//     Le déclenchement de l'apprentissage, lui, passe par la méthode de
//     production `enregistrerResultat()`. Aucune étape de l'apprentissage
//     n'est simulée.
//
//  ⚠️ VALIDATION FONCTIONNELLE ≠ EFFICACITÉ HIPPIQUE. Ce fichier mesure que le
//     SYSTÈME fonctionne : les poids évoluent, persistent, se restituent, ne
//     bougent pas sans apprentissage, n'apprennent pas deux fois, et restent
//     conformes au contrat C1–C10. Il ne dit RIEN de la qualité hippique des
//     pronostics. La validation hippique prospective reste à faire.
//
//  ⚠️ MESURÉ — LA FENÊTRE D'APPRENTISSAGE EST BORNÉE À 45 JOURS.
//     `_apprendreParGradient` (ia_memory_service.dart:3946-3956) filtre les
//     courses à `age <= 45` jours, avec repli à 90 jours. Un historique plus
//     ancien laisse `fenetre` VIDE, et `scoreMoyFenetre` lève alors
//     `Bad state: No element` sur `reduce` d'un itérable vide. L'historique
//     de ce harnais est donc placé DANS la fenêtre (J−40 → J−27). Ce n'est pas
//     un assouplissement : c'est la condition réelle pour que le gradient
//     s'exécute.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

// ─── Référentiel (recopié de la production, gardé par F0) ───────────────────
const List<String> kCles = <String>[
  'forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline',
  'distSpec', 'jockey', 'repos', 'hippo', 'entraineur', 'elo',
  'terrain', 'divergence', 'poidsRel', 'progression', 'mouvCote', 'placeDepart',
];
const List<String> kBase = <String>[
  'forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline',
];
final List<String> kEnrichis =
    kCles.where((k) => !kBase.contains(k)).toList(growable: false);

/// Les 19 poids INITIAUX du constructeur de production (somme 1,26).
const Map<String, double> kInitial = <String, double>{
  'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
  'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
  'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
  'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05, 'divergence': 0.04,
  'poidsRel': 0.03, 'progression': 0.03, 'mouvCote': 0.06,
  'placeDepart': 0.03,
};

const String kDisc = 'Trot Attelé';

double _sommeCle(Map<String, double> m, List<String> ks) =>
    ks.fold(0.0, (a, k) => a + (m[k] ?? 0.0));

String _f(double v) => v.toStringAsFixed(12);

String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

/// Lit les 19 poids EFFECTIFS du service — chemin de production (`getPoids`).
Map<String, double> _poidsEffectifs() => <String, double>{
      for (final k in kCles) k: IaMemoryService.instance.poids.getPoids(k),
    };

/// Compare deux tables sur les 19 clés ; rend (écart max, clé la plus décalée,
/// nombre de critères ayant bougé au-delà de [seuil]).
(double, String, int) _ecart(Map<String, double> a, Map<String, double> b,
    {double seuil = 1e-12}) {
  var maxi = 0.0;
  var pire = '';
  var bouges = 0;
  for (final k in kCles) {
    final d = ((a[k] ?? 0) - (b[k] ?? 0)).abs();
    if (d > seuil) bouges++;
    if (d > maxi) {
      maxi = d;
      pire = k;
    }
  }
  return (maxi, pire, bouges);
}

// ─────────────────── Pronostic de PRODUCTION (sérialisé réel) ───────────────

/// `scoresCriteres` RENSEIGNÉ et DISCRIMINANT : sans lui, `_apprendreParGradient`
/// délègue à `_apprendreReglesBase` (`avecScores < 3`, ia_memory_service:3931)
/// et l'on ne testerait pas le gradient.
IaPronostic _pronostic({
  required String courseKey,
  required DateTime date,
  bool resolu = true,
  String discipline = kDisc,
}) =>
    IaPronostic(
      courseKey: courseKey,
      nomCourse: 'PRIX $courseKey',
      hippodrome: 'VINCENNES',
      discipline: discipline,
      datePronostic: date,
      scoresIA: const {
        '1': 100.0, '2': 92.0, '3': 84.0, '4': 76.0, '5': 68.0,
      },
      scoresCriteres: <String, ScoresCriteres>{
        for (var n = 1; n <= 5; n++)
          '$n': ScoresCriteres(
            forme: 92.0 - n * 4, gains: 82.0 - n * 3, record: 72.0 - n * 2,
            cote: 86.0 - n * 5, constance: 76.0 - n, victoires: 66.0 + n,
            discipline: 61.0 + n * 2, distSpec: 89.0 - n * 6,
            jockey: 73.0 - n, repos: 56.0 + n, hippo: 69.0 - n * 2,
            entraineur: 63.0 + n, elo: 79.0 - n * 3, terrain: 71.0 + n,
            divergence: 51.0 + n * 4, poidsRel: 67.0 - n,
            progression: 75.0 + n * 2, mouvCote: 59.0 + n * 3,
            placeDepart: 65.0 - n * 2,
          ),
      },
      varianceScores: 12.0,
      confiancePredite: 70.0,
      typePariConseille: 'Simple Gagnant',
      favoriIaNom: 'CHEVAL_1',
      arriveeReelle: resolu ? const <int>[1, 2, 3, 4, 5] : null,
      dateResultat: resolu ? date.add(const Duration(hours: 2)) : null,
      resultatsReels: resolu,
      scorePerformance: resolu ? 50.0 : null,
    );

/// Historique de 15 courses RÉSOLUES, DANS la fenêtre de 45 jours du gradient
/// (J−40 → J−26), toutes de la même discipline pour que
/// `_apprendreParDiscipline` ait aussi de quoi s'exécuter (seuil 5).
List<IaPronostic> _historique() {
  final base = DateTime.now().subtract(const Duration(days: 40));
  return [
    for (var i = 0; i < 15; i++)
      _pronostic(
        courseKey: 'H${1 + i % 3}C${1 + i % 7}_${_fmt(base.add(Duration(days: i)))}',
        date: base.add(Duration(days: i)),
      ),
  ];
}

// ─────────────────────────── Graine = état téléphone ───────────────────────

const String kPoidsKey = 'ia_poids_v3'; // = IaMemoryService._poidsKey

/// Écrit sur le stockage simulé EXACTEMENT ce qu'écrit un téléphone, puis
/// recharge par le chemin réel (`recharger()` → `_load()` → `fromJson`).
///
/// GARDE ANTI-FAUX-NÉGATIF : on vérifie que la graine est réellement chargée.
/// Sans ce contrôle, un `_load()` en erreur laisserait une mémoire vide et
/// toutes les mesures « aucun apprentissage » seraient des faux positifs.
Future<void> _semerVierge(List<IaPronostic> pronostics) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'ia_precision_migrated_v3': true,
    // Poids INITIAUX BRUTS, exactement ceux du constructeur : Σ = 1,26.
    kPoidsKey: json.encode(<String, dynamic>{
      ...kInitial,
      'nbMisesAJour': 0,
      'calibrationScore': 50.0,
    }),
    'ia_seuils_v1': json.encode(<String, dynamic>{}),
    'ia_precision_v2': json.encode(<String, dynamic>{}),
    'ia_stats_labels_v1': json.encode(<String, dynamic>{}),
    'ia_stats_types_v1': <String>[],
    'ia_journal_v2': <String>[],
    'ia_pronostics_v2':
        pronostics.map((p) => json.encode(p.toJson())).toList(),
  });
  SharedPreferences.resetStatic();
  await IaMemoryService.instance.recharger();

  final mem = IaMemoryService.instance;
  expect(mem.poids.nbMisesAJour, 0,
      reason: 'GARDE : la mémoire doit être VIERGE (0 mise à jour)');
  expect(mem.pronostics.length, pronostics.length,
      reason: 'GARDE : les ${pronostics.length} pronostics semés doivent être '
          'chargés (obtenu : ${mem.pronostics.length})');
  // GARDE CRUCIALE : `fromJson` ne projette pas. Si Σ valait 1,00 ici, D-1
  // aurait été appliqué AU CHARGEMENT — ce qui est interdit.
  final somme = _sommeCle(_poidsEffectifs(), kCles);
  expect(somme, closeTo(1.26, 1e-9),
      reason: 'GARDE : au chargement, Σ doit valoir 1,26 (poids bruts)');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════════
  //  F0 — GARDE : les constantes recopiées sont bien celles de la production
  // ═══════════════════════════════════════════════════════════════════════════
  test('F0 — les constantes du harnais sont celles de la production', () {
    expect(IaPoidsAdaptatifs.kClesOrdonnees, kCles);
    expect(IaPoidsAdaptatifs.kClesBase, kBase);
    expect(IaPoidsAdaptatifs.kClesEnrichies, kEnrichis);
    final defaut = IaPoidsAdaptatifs.defaut();
    var ecart = 0.0;
    for (final k in kCles) {
      final d = (defaut.getPoids(k) - kInitial[k]!).abs();
      if (d > ecart) ecart = d;
    }
    // ignore: avoid_print
    print('F0  constructeur vs table du harnais : écart max = ${_f(ecart)} · '
        'Σ = ${_f(_sommeCle(<String, double>{for (final k in kCles) k: defaut.getPoids(k)}, kCles))}');
    expect(ecart, lessThanOrEqualTo(1e-12),
        reason: 'les 19 poids initiaux du constructeur doivent être EXACTEMENT '
            'ceux recopiés ici, sinon toutes les mesures porteraient sur une '
            'autre table');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  F1 — DÉMARRAGE SANS ANCIEN APPRENTISSAGE
  // ═══════════════════════════════════════════════════════════════════════════
  test('F1 — démarrage : les 19 poids bruts du constructeur, sans projection',
      () async {
    await _semerVierge(_historique());
    final p = _poidsEffectifs();
    final (ecart, pire, _) = _ecart(p, kInitial);
    // ignore: avoid_print
    print('F1  19 poids chargés vs constructeur : écart max = ${_f(ecart)} '
        '("$pire") · Σ = ${_f(_sommeCle(p, kCles))} '
        '(base ${_f(_sommeCle(p, kBase))} · enrichis '
        '${_f(_sommeCle(p, kEnrichis))}) · nbMisesAJour = '
        '${IaMemoryService.instance.poids.nbMisesAJour}');
    expect(ecart, lessThanOrEqualTo(1e-12),
        reason: 'au démarrage, les 19 poids doivent être EXACTEMENT ceux du '
            'constructeur — le chargement ne doit rien contraindre');
    expect(_sommeCle(p, kCles), closeTo(1.26, 1e-9),
        reason: 'Σ brute au démarrage = 1,26 : D-1 n\'est pas appliqué au '
            'chargement');
    expect(IaMemoryService.instance.journal, isEmpty,
        reason: 'un démarrage sans apprentissage ne doit consigner aucun '
            'apprentissage');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  F2 — PREMIER APPRENTISSAGE RÉEL : évolution + projection
  // ═══════════════════════════════════════════════════════════════════════════
  test('F2 — premier apprentissage réel : les poids évoluent, puis sont projetés',
      () async {
    final hist = _historique();
    final cible = _pronostic(
      courseKey: 'CIBLE_${_fmt(DateTime.now().subtract(const Duration(days: 2)))}',
      date: DateTime.now().subtract(const Duration(days: 2)),
      resolu: false, // pronostic EN ATTENTE : c'est `enregistrerResultat` qui apprend
    );
    await _semerVierge(<IaPronostic>[...hist, cible]);

    final mem = IaMemoryService.instance;
    final avant = _poidsEffectifs();
    final j0 = mem.journal.length;
    final nb0 = mem.poids.nbMisesAJour;

    // CHEMIN DE PRODUCTION : `enregistrerResultat` → `_save()`,
    // `_apprendreParGradient()`, `_apprendreParDiscipline()`.
    final ecrit = await mem.enregistrerResultat(
      courseKey: cible.courseKey,
      arriveeReelle: const <int>[1, 2, 3, 4, 5],
    );

    final apres = _poidsEffectifs();
    final (ecartMax, pire, bouges) = _ecart(apres, avant);
    final methodes = mem.journal
        .map((e) => e.methode)
        .whereType<String>()
        .toList(growable: false);
    // ignore: avoid_print
    print('F2  enregistrerResultat=$ecrit · journal $j0 → ${mem.journal.length} '
        '· méthodes apparues = ${methodes.take(mem.journal.length - j0).toList()}');
    // ignore: avoid_print
    print('F2  critères déplacés : $bouges/19 · écart max = ${_f(ecartMax)} '
        '("$pire") · Σ après = ${_f(_sommeCle(apres, kCles))} · base '
        '${_f(_sommeCle(apres, kBase))} · enrichis '
        '${_f(_sommeCle(apres, kEnrichis))}');

    expect(ecrit, isTrue, reason: 'le résultat doit être accepté');
    expect(mem.journal.length, greaterThan(j0),
        reason: 'un apprentissage réel doit consigner une entrée de journal');
    expect(mem.poids.nbMisesAJour, greaterThan(nb0),
        reason: 'le gradient doit incrémenter nbMisesAJour');

    // ★ Le cœur de §4 : les poids ont RÉELLEMENT bougé — et pas seulement
    //   « au moins un », on mesure combien.
    expect(bouges, greaterThan(0),
        reason: 'un apprentissage réel doit DÉPLACER des poids');

    // Le contrat C1–C6 est tenu APRÈS apprentissage : c'est le moment où la
    // projection entre en jeu pour de vrai.
    expect(_sommeCle(apres, kCles), closeTo(1.0, 1e-9),
        reason: 'C1 après apprentissage réel : Σ = 1');
    final bornes = IaPoidsAdaptatifs.bornesIndividuelles();
    for (final k in kCles) {
      expect(apres[k]!, greaterThanOrEqualTo(bornes[k]![0] - 1e-9),
          reason: 'C2 : plancher violé sur $k après apprentissage réel');
      expect(apres[k]!, lessThanOrEqualTo(bornes[k]![1] + 1e-9),
          reason: 'C3 : plafond violé sur $k après apprentissage réel');
      expect(apres[k]!.isFinite, isTrue, reason: 'C6 : $k non fini');
      expect(apres[k]!, greaterThanOrEqualTo(0.0), reason: 'C5 : $k négatif');
    }
    final partEnr = _sommeCle(apres, kEnrichis);
    expect(partEnr, inInclusiveRange(0.18 - 1e-9, 0.40 + 1e-9),
        reason: 'C4 : la part enrichie doit rester dans [0,18 ; 0,40]');
    // Aucune anomalie de projection en fonctionnement normal.
    expect(mem.anomaliesProjection, isEmpty,
        reason: 'un apprentissage sain ne doit produire aucune anomalie de '
            'projection (sinon la trace serait bavarde et sans valeur)');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  F3 — PERSISTANCE PUIS RESTITUTION APRÈS REDÉMARRAGE
  // ═══════════════════════════════════════════════════════════════════════════
  test('F3 — les poids appris sont écrits par _save() et restitués à l\'identique',
      () async {
    final hist = _historique();
    final cible = _pronostic(
      courseKey: 'PERSIST_${_fmt(DateTime.now().subtract(const Duration(days: 3)))}',
      date: DateTime.now().subtract(const Duration(days: 3)),
      resolu: false,
    );
    await _semerVierge(<IaPronostic>[...hist, cible]);
    final mem = IaMemoryService.instance;

    await mem.enregistrerResultat(
      courseKey: cible.courseKey,
      arriveeReelle: const <int>[1, 2, 3, 4, 5],
    );
    final appris = _poidsEffectifs();
    final nbAppris = mem.poids.nbMisesAJour;

    // Le blob est écrit par `_save()` de production, appelé dans
    // `enregistrerResultat` ET dans `_apprendreParGradient`.
    SharedPreferences.resetStatic();
    final prefs = await SharedPreferences.getInstance();
    final blob = prefs.getString(kPoidsKey);
    // ignore: avoid_print
    print('F3  blob "$kPoidsKey" après apprentissage : '
        '${blob == null ? "ABSENT" : "${blob.length} octets"}');
    expect(blob, isNotNull, reason: 'les poids appris doivent être persistés');

    // REDÉMARRAGE : on relit le stockage SANS rien réinitialiser d'autre.
    await mem.recharger();
    final relus = _poidsEffectifs();
    final (ecart, pire, _) = _ecart(relus, appris);
    // ignore: avoid_print
    print('F3  après redémarrage : écart max = ${_f(ecart)} ("$pire") · '
        'nbMisesAJour $nbAppris → ${mem.poids.nbMisesAJour} · '
        'Σ = ${_f(_sommeCle(relus, kCles))}');
    expect(ecart, lessThanOrEqualTo(1e-12),
        reason: 'les poids appris doivent être restitués À L\'IDENTIQUE : le '
            'chargement ne doit ni re-projeter ni re-normaliser');
    expect(mem.poids.nbMisesAJour, nbAppris,
        reason: 'aucune réinitialisation silencieuse du compteur d\'apprentissage');
    expect(_sommeCle(relus, kCles), closeTo(1.0, 1e-9));
    // Et les pronostics/archives restent accessibles après ce cycle.
    expect(mem.pronostics, isNotEmpty,
        reason: 'les pronostics doivent rester accessibles après redémarrage');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  F4 — AUCUNE MODIFICATION SANS APPRENTISSAGE (chemin réel)
  // ═══════════════════════════════════════════════════════════════════════════
  test('F4 — cinq rechargements sans apprentissage ne changent RIEN', () async {
    final hist = _historique();
    final cible = _pronostic(
      courseKey: 'STABLE_${_fmt(DateTime.now().subtract(const Duration(days: 4)))}',
      date: DateTime.now().subtract(const Duration(days: 4)),
      resolu: false,
    );
    await _semerVierge(<IaPronostic>[...hist, cible]);
    final mem = IaMemoryService.instance;
    await mem.enregistrerResultat(
      courseKey: cible.courseKey,
      arriveeReelle: const <int>[1, 2, 3, 4, 5],
    );

    final reference = _poidsEffectifs();
    final jRef = mem.journal.length;
    final nbRef = mem.poids.nbMisesAJour;

    var ecartCumule = 0.0;
    for (var i = 0; i < 5; i++) {
      await mem.recharger();
      final (d, _, _) = _ecart(_poidsEffectifs(), reference);
      if (d > ecartCumule) ecartCumule = d;
    }
    final (ecart, pire, _) = _ecart(_poidsEffectifs(), reference);
    // ignore: avoid_print
    print('F4  5 cycles recharger : écart max = ${_f(ecart)} ("$pire") · '
        'écart cumulé max = ${_f(ecartCumule)} · journal $jRef → '
        '${mem.journal.length} · nbMisesAJour $nbRef → ${mem.poids.nbMisesAJour}');
    expect(ecart, lessThanOrEqualTo(1e-12),
        reason: 'C10 mesuré sur le CHEMIN RÉEL : sans apprentissage, aucun '
            'poids ne bouge — même après cinq cycles de lecture');
    expect(mem.journal.length, jRef,
        reason: 'une relecture ne doit déclencher aucun apprentissage');
    expect(mem.poids.nbMisesAJour, nbRef,
        reason: 'une relecture ne doit pas incrémenter le compteur');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  F5 — ÉVOLUTION DES POIDS PAR DISCIPLINE (chemin réel)
  // ═══════════════════════════════════════════════════════════════════════════
  test('F5 — par discipline : table créée, projetée, conforme aux 19 bornes',
      () async {
    final hist = _historique();
    final cible = _pronostic(
      courseKey: 'DISC_${_fmt(DateTime.now().subtract(const Duration(days: 5)))}',
      date: DateTime.now().subtract(const Duration(days: 5)),
      resolu: false,
    );
    await _semerVierge(<IaPronostic>[...hist, cible]);
    final mem = IaMemoryService.instance;

    expect(mem.poids.poidsParDiscipline, isEmpty,
        reason: 'GARDE : au démarrage, aucune table de discipline');

    await mem.enregistrerResultat(
      courseKey: cible.courseKey,
      arriveeReelle: const <int>[1, 2, 3, 4, 5],
    );

    final ppd = mem.poids.poidsParDiscipline;
    final bornes = IaPoidsAdaptatifs.bornesIndividuelles();
    // ignore: avoid_print
    print('F5  disciplines apprises après apprentissage réel : '
        '${ppd.keys.toList()}');
    expect(ppd, isNotEmpty,
        reason: '`_apprendreParDiscipline` doit créer une table pour la '
            'discipline de la course résolue (15 courses ≥ seuil 5)');

    for (final e in ppd.entries) {
      final t = e.value;
      final somme = _sommeCle(t, kCles);
      var violations = 0;
      for (final k in kCles) {
        final v = t[k];
        if (v == null) continue;
        if (v < bornes[k]![0] - 1e-9 || v > bornes[k]![1] + 1e-9) violations++;
      }
      // ignore: avoid_print
      print('F5  ${e.key.padRight(12)} : ${t.length} clés · Σ=${_f(somme)} · '
          'part enrichie ${_f(_sommeCle(t, kEnrichis))} · violations=$violations '
          '· divergence=${_f(t['divergence'] ?? -1)}');
      expect(somme, closeTo(1.0, 1e-9),
          reason: 'C1 : la table de discipline ${e.key} doit sommer à 1');
      expect(violations, 0,
          reason: 'C2/C3 : la table de discipline ${e.key} doit respecter les '
              'MÊMES 19 bornes que le global (D-2)');
      expect(t['divergence']!, lessThanOrEqualTo(0.08 + 1e-9),
          reason: 'D-2 : la discipline ne doit plus autoriser divergence à 0,10');
      final part = _sommeCle(t, kEnrichis);
      expect(part, inInclusiveRange(0.18 - 1e-9, 0.40 + 1e-9),
          reason: 'C4 : part enrichie de la discipline hors intervalle');
    }

    // Le chemin CONSOMMATEUR reçoit bien 19 clés utilisables.
    final eff = mem.poids.poidsEffectifsPourDiscipline(kDisc);
    // ignore: avoid_print
    print('F5  poidsEffectifsPourDiscipline("$kDisc") : ${eff.length} clés · '
        'Σ=${_f(_sommeCle(eff, kCles))}');
    expect(eff.length, 19,
        reason: 'le chemin consommateur doit recevoir les 19 critères');
    for (final k in kCles) {
      expect(eff[k], isNotNull, reason: '$k manquant dans la table effective');
    }
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  F6 — AUCUN DOUBLE APPRENTISSAGE (contrôle positif inclus)
  // ═══════════════════════════════════════════════════════════════════════════
  test('F6 — rejouer la même arrivée n\'apprend pas deux fois', () async {
    final hist = _historique();
    final cible = _pronostic(
      courseKey: 'ONCE_${_fmt(DateTime.now().subtract(const Duration(days: 6)))}',
      date: DateTime.now().subtract(const Duration(days: 6)),
      resolu: false,
    );
    await _semerVierge(<IaPronostic>[...hist, cible]);
    final mem = IaMemoryService.instance;

    final j0 = mem.journal.length;
    final nb0 = mem.poids.nbMisesAJour;
    final ok1 = await mem.enregistrerResultat(
      courseKey: cible.courseKey,
      arriveeReelle: const <int>[1, 2, 3, 4, 5],
    );
    final j1 = mem.journal.length;
    final nb1 = mem.poids.nbMisesAJour;
    // ignore: avoid_print
    print('F6  1er enregistrement : ok=$ok1 · journal +${j1 - j0} · '
        'nbMisesAJour $nb0 → $nb1');
    // CONTRÔLE POSITIF : sans lui, « pas de second apprentissage » ne prouverait
    // rien (un montage incapable d'apprendre passerait le test).
    expect(ok1, isTrue);
    expect(j1, greaterThan(j0),
        reason: 'CONTRÔLE POSITIF : le premier enregistrement DOIT apprendre');

    final poidsRef = _poidsEffectifs();
    final ok2 = await mem.enregistrerResultat(
      courseKey: cible.courseKey,
      arriveeReelle: const <int>[1, 2, 3, 4, 5],
    );
    final j2 = mem.journal.length;
    final (ecart, pire, _) = _ecart(_poidsEffectifs(), poidsRef);
    // ignore: avoid_print
    print('F6  rejeu : ok=$ok2 · journal +${j2 - j1} · écart des poids = '
        '${_f(ecart)} ("$pire")');
    expect(ok2, isFalse,
        reason: 'le rejeu doit être refusé (`p.resultatsReels` déjà vrai)');
    expect(j2, j1,
        reason: 'le rejeu ne doit consigner AUCUN apprentissage');
    expect(ecart, lessThanOrEqualTo(1e-12),
        reason: 'le rejeu ne doit pas déplacer les poids');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  F7 — §3 : UNE VALEUR INVALIDE EST ABSORBÉE **ET TRACÉE**, JAMAIS MUETTE
  // ═══════════════════════════════════════════════════════════════════════════
  test('F7 — NaN / infini / négatif : absorbés, tracés, jamais silencieux',
      () async {
    await _semerVierge(_historique());
    final mem = IaMemoryService.instance;

    // (a) Aucune anomalie en fonctionnement normal (pas de bruit de trace).
    expect(mem.anomaliesProjection, isEmpty);

    // (b) Injection dans `projeter()` — méthode de PRODUCTION — d'un NaN, d'un
    //     infini et d'un négatif, sur une instance LOCALE de la classe de
    //     production (jamais un vecteur nu) : le contrat doit tenir et la trace
    //     doit se déclencher. On n'utilise pas le singleton ici afin de ne pas
    //     altérer l'état appris.
    final local = IaPoidsAdaptatifs.defaut();
    local.forme = double.nan;
    local.cote = double.infinity;
    local.gains = -0.4;
    final sentinelleAvant = IaPoidsAdaptatifs.dernierNumeroProjectionAvecAnomalie;
    local.clamp();
    final sentinelleApres = IaPoidsAdaptatifs.dernierNumeroProjectionAvecAnomalie;
    final trace = IaPoidsAdaptatifs.dernieresAnomaliesProjection;
    final sommeLocale = _sommeCle(
        <String, double>{for (final k in kCles) k: local.getPoids(k)}, kCles);
    // ignore: avoid_print
    print('F7  injection NaN/infini/négatif → ${trace.length} anomalie(s) '
        'tracée(s) : ${trace.join(" | ")}');
    // ignore: avoid_print
    print('F7  valeurs récupérées : forme=${_f(local.forme)} · '
        'cote=${_f(local.cote)} · gains=${_f(local.gains)} · Σ = '
        '${_f(sommeLocale)} · sentinelle $sentinelleAvant → $sentinelleApres');
    expect(trace, isNotEmpty,
        reason: '§3 : une valeur invalide doit être TRACÉE, sinon un '
            'dérèglement du mécanisme d\'apprentissage resterait muet');
    expect(trace.any((t) => t.contains('forme') && t.contains('NaN')), isTrue,
        reason: 'le NaN doit être nommé dans la trace');
    expect(trace.any((t) => t.contains('cote') && t.contains('infini')), isTrue,
        reason: 'l\'infini doit être nommé dans la trace');
    expect(trace.any((t) => t.contains('gains') && t.contains('NÉGATIF')), isTrue,
        reason: 'le négatif doit être nommé dans la trace');
    expect(sentinelleApres, greaterThan(sentinelleAvant),
        reason: 'la sentinelle de projection doit avancer');
    // Les valeurs sont absorbées : le système reste calculable (C5/C6).
    expect(local.forme.isFinite, isTrue);
    expect(local.cote.isFinite, isTrue);
    expect(local.gains, greaterThanOrEqualTo(0.0));
    expect(sommeLocale, closeTo(1.0, 1e-9));
    // Un simple dépassement de plafond n'est PAS une anomalie : c'est le
    // fonctionnement normal de la contrainte.
    final sentinelleBis = IaPoidsAdaptatifs.dernierNumeroProjectionAvecAnomalie;
    final local2 = IaPoidsAdaptatifs.defaut()..forme = 0.95; // > plafond 0,55
    local2.clamp();
    // ignore: avoid_print
    print('F7  dépassement de plafond (forme=0,95) : nouvelle anomalie ? '
        '${IaPoidsAdaptatifs.dernierNumeroProjectionAvecAnomalie != sentinelleBis} '
        '· forme ramenée à ${_f(local2.forme)}');
    expect(IaPoidsAdaptatifs.dernierNumeroProjectionAvecAnomalie, sentinelleBis,
        reason: 'un dépassement de BORNE n\'est pas une anomalie : il ne doit '
            'pas polluer la trace');

    // (c) La trace est bien RELAYÉE par le chemin d'apprentissage de production.
    //     L'injection ci-dessus a fait avancer la sentinelle GLOBALE
    //     `dernierNumeroProjectionAvecAnomalie`. Le prochain gradient constatera
    //     qu'elle dépasse `_dernierNumeroProjectionVu` et recopiera la trace
    //     dans le service — c'est ce relais qu'on mesure ici.
    final anomaliesServiceAvant = mem.anomaliesProjection.length;
    final cible = _pronostic(
      courseKey: 'RELAIS_${_fmt(DateTime.now().subtract(const Duration(days: 7)))}',
      date: DateTime.now().subtract(const Duration(days: 7)),
      resolu: false,
    );
    await _semerVierge(<IaPronostic>[..._historique(), cible]);
    await mem.enregistrerResultat(
      courseKey: cible.courseKey,
      arriveeReelle: const <int>[1, 2, 3, 4, 5],
    );
    // ignore: avoid_print
    print('F7  relais par l\'apprentissage : anomaliesProjection '
        '$anomaliesServiceAvant → ${mem.anomaliesProjection.length} · '
        '${mem.anomaliesProjection.take(3).toList()}');
    // Le service doit avoir RELAYÉ l'anomalie, sans quoi le défaut ne
    // remonterait jamais à l'utilisateur ni aux diagnostics.
    expect(mem.anomaliesProjection, isNotEmpty,
        reason: '§3 : `_apprendreParGradient` doit relayer les anomalies de '
            'projection rencontrées (relais mesuré, pas supposé)');
  });
}
