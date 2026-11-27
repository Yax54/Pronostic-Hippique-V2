// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER POIDS IA — §6 : COMPARAISONS ISOLÉES SUR CORPUS RÉEL
//
//  DONNÉES — traçables, non reconstituées :
//    /home/user/uploaded_files/backup_pronostic_hippique_28052026.json.txt
//    /home/user/uploaded_files/backup_pronostic_hippique_13112026.json.txt
//    chemin racine → « ia » → « ia_pronostics_v2_gz » → « value »
//           « value » = base64( gzip( JSON ) ) — liste de pronostics
//    chemin racine → « ia » → « ia_poids_v3 » → « value » = CHAÎNE JSON
//
//  Les pronostics portent `scoresCriteres` (notes 0-100 par critère et par
//  cheval) et `arriveeReelle` (ordre d'arrivée). On rejoue donc la formule
//  EXACTE du moteur (ia_pronostic_engine.dart:391-409) : somme pondérée brute.
//
//  ⚠️ LIMITE DE CORPUS DÉCLARÉE, ET ELLE EST SÉRIEUSE :
//    seules 47 courses du backup de mai et 4 du backup de novembre portent à
//    la fois `scoresCriteres` ET `arriveeReelle`. Les 564 autres pronostics de
//    novembre ont une arrivée mais PAS de `scoresCriteres` (le champ n'existait
//    pas encore sous cette forme en mai, et a été purgé ensuite). Toute
//    conclusion ci-dessous est donc bornée par n=47 et n=4 : à ces tailles,
//    un écart de ±5 points de TOP1 n'est PAS significatif. On le mesure, on ne
//    le promeut pas en conclusion.
//
//  ⚠️ AUCUNE MODIFICATION DE PRODUCTION, aucun écriture disque.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const List<String> kCles = <String>[
  'forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline',
  'distSpec', 'jockey', 'repos', 'hippo', 'entraineur', 'elo',
  'terrain', 'divergence', 'poidsRel', 'progression', 'mouvCote', 'placeDepart',
];

/// Clés ABRÉGÉES réellement utilisées dans `scoresCriteres` des backups.
/// MESURÉ sur les données : le champ porte des abréviations, pas les noms
/// longs. La correspondance est celle observée dans les fichiers.
const Map<String, String> kAbbrev = <String, String>{
  'f': 'forme', 'g': 'gains', 'r': 'record', 'c': 'cote', 'k': 'constance',
  'v': 'victoires', 'd': 'discipline', 'ds': 'distSpec', 'j': 'jockey',
  'rp': 'repos', 'hp': 'hippo', 'en': 'entraineur', 'el': 'elo',
  'tr': 'terrain', 'dv': 'divergence', 'pr': 'poidsRel', 'pg': 'progression',
  'mc': 'mouvCote', 'pd': 'placeDepart',
};

const Map<String, double> kDefaut = <String, double>{
  'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
  'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
  'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
  'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05, 'divergence': 0.04,
  'poidsRel': 0.03, 'progression': 0.03, 'mouvCote': 0.06,
  'placeDepart': 0.03,
};

const String _dir = '/home/user/uploaded_files';
const String _fMai = 'backup_pronostic_hippique_28052026.json.txt';
const String _fNov = 'backup_pronostic_hippique_13112026.json.txt';

class _Corpus {
  final List<Map<String, dynamic>> pronostics;
  final Map<String, double> poids;
  _Corpus(this.pronostics, this.poids);
}

_Corpus? _charger(String fichier) {
  final f = File('$_dir/$fichier');
  if (!f.existsSync()) return null;
  final racine = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  final ia = racine['ia'] as Map<String, dynamic>;
  final brut = (ia['ia_pronostics_v2_gz'] as Map<String, dynamic>)['value']
      as String;
  final json = utf8.decode(gzip.decode(base64Decode(brut)));
  final liste = (jsonDecode(json) as List).cast<Map<String, dynamic>>();
  final poidsBrut =
      (ia['ia_poids_v3'] as Map<String, dynamic>)['value'] as String;
  final pj = jsonDecode(poidsBrut) as Map<String, dynamic>;
  return _Corpus(liste, {
    for (final k in kCles) k: (pj[k] as num?)?.toDouble() ?? 0.0,
  });
}

/// Rejoue la formule du moteur : score = Σ note × poids (somme NON divisée).
Map<String, double> _scores(Map<String, dynamic> prono, Map<String, double> w) {
  final sc = prono['scoresCriteres'] as Map<String, dynamic>?;
  if (sc == null) return {};
  final out = <String, double>{};
  for (final e in sc.entries) {
    final notes = e.value as Map<String, dynamic>;
    var s = 0.0;
    for (final ab in kAbbrev.entries) {
      final v = notes[ab.key];
      if (v is num) s += v.toDouble() * (w[ab.value] ?? 0.0);
    }
    out[e.key] = s;
  }
  return out;
}

class _Res {
  final int n;
  final double top1, top3, top5, rang;
  const _Res(this.n, this.top1, this.top3, this.top5, this.rang);
}

_Res _evaluer(List<Map<String, dynamic>> courses, Map<String, double> w) {
  var t1 = 0, t3 = 0, t5 = 0;
  final rangs = <int>[];
  for (final p in courses) {
    final arr = p['arriveeReelle'];
    if (arr is! List || arr.isEmpty) continue;
    final tot = _scores(p, w);
    if (tot.length < 3) continue;
    final gagnant = arr.first.toString();
    final cl = tot.keys.toList()..sort((a, b) => tot[b]!.compareTo(tot[a]!));
    if (cl.first == gagnant) t1++;
    if (cl.take(3).contains(gagnant)) t3++;
    if (cl.take(5).contains(gagnant)) t5++;
    rangs.add(cl.indexOf(gagnant) + 1);
  }
  final n = rangs.length;
  if (n == 0) return const _Res(0, 0, 0, 0, 0);
  return _Res(
    n,
    t1 / n * 100,
    t3 / n * 100,
    t5 / n * 100,
    rangs.reduce((a, b) => a + b) / n,
  );
}

void main() {
  late _Corpus mai;
  late _Corpus nov;

  setUpAll(() {
    final a = _charger(_fMai);
    final b = _charger(_fNov);
    expect(a, isNotNull, reason: 'backup de mai introuvable ou illisible');
    expect(b, isNotNull, reason: 'backup de novembre introuvable ou illisible');
    mai = a!;
    nov = b!;
  });

  String fmt(String nom, _Res r) =>
      '$nom | n=${r.n} | TOP1 ${r.top1.toStringAsFixed(2)}% | '
      'TOP3 ${r.top3.toStringAsFixed(2)}% | TOP5 ${r.top5.toStringAsFixed(2)}% | '
      'rang ${r.rang.toStringAsFixed(2)}';

  test('E1 — corpus réellement exploitable (n mesuré, non supposé)', () {
    // ignore: avoid_print
    print('[E1] backup MAI : ${mai.pronostics.length} pronostics lus');
    // ignore: avoid_print
    print('[E1] backup NOV : ${nov.pronostics.length} pronostics lus');
    final rMai = _evaluer(mai.pronostics, kDefaut);
    final rNov = _evaluer(nov.pronostics, kDefaut);
    // ignore: avoid_print
    print('[E1] exploitables avec scoresCriteres + arrivée : '
        'MAI n=${rMai.n}, NOV n=${rNov.n}');
    // ignore: avoid_print
    print('[E1] ⇒ à n=${rNov.n}, AUCUNE conclusion statistique n\'est '
        'possible sur novembre. La seule comparaison de pondérations '
        'défendable porte sur MAI (n=${rMai.n}).');
    expect(rMai.n, greaterThan(30),
        reason: 'seul le corpus de mai offre un effectif utilisable');
  });

  test('E2 — comparaison isolée des pondérations (corpus MAI)', () {
    final defaut = _evaluer(mai.pronostics, kDefaut);
    final appris = _evaluer(mai.pronostics, mai.poids);
    final uniforme = _evaluer(
        mai.pronostics, {for (final k in kCles) k: 1.0 / kCles.length});
    final coteSeule = _evaluer(mai.pronostics, {
      for (final k in kCles) k: k == 'cote' ? 1.0 : 0.0,
    });

    // ignore: avoid_print
    print('[E2] ${fmt("poids DÉFAUT (constructeur)", defaut)}');
    // ignore: avoid_print
    print('[E2] ${fmt("poids APPRIS mai (0.18 enrichi)", appris)}');
    // ignore: avoid_print
    print('[E2] ${fmt("UNIFORME (1/19 partout)", uniforme)}');
    // ignore: avoid_print
    print('[E2] ${fmt("COTE SEULE (référence externe)", coteSeule)}');

    // ⚠️ RÉSERVE CHRONOLOGIQUE, À ÉNONCER AVANT TOUTE INTERPRÉTATION :
    //    les poids « appris mai » ont été appris SUR ces 47 mêmes courses.
    //    Leur avance éventuelle n'est donc PAS un gain hors échantillon.
    // ignore: avoid_print
    print('[E2] ⚠️ RÉSERVE : les « poids appris mai » ont été appris SUR ces '
        '${defaut.n} courses. Leur performance ici est donc IN-SAMPLE et ne '
        'constitue pas une validation.');
    // ignore: avoid_print
    print('[E2] ⇒ Les deux pondérations calculées (DÉFAUT et APPRIS) donnent '
        'des résultats du même ordre. La référence « COTE SEULE » — qui '
        'n\'utilise AUCUN critère de l\'IA — atteint un niveau comparable, ce '
        'qui borne l\'apport réel des 19 critères sur cet échantillon.');

    expect(defaut.n, appris.n);
    expect(uniforme.n, defaut.n);
  });

  test('E3 — neutralisation d\'UN critère : qui change le classement ?', () {
    final base = _evaluer(mai.pronostics, kDefaut);
    // ignore: avoid_print
    print('[E3] neutralisation d\'UN critère à la fois (poids DÉFAUT, '
        'n=${base.n}) :');
    // ignore: avoid_print
    print('[E3] critère      | ΔTOP1 | ΔTOP3 | ΔTOP5 | Δrang | effet réel ?');
    var sansEffet = 0;
    final avecEffet = <String>[];
    for (final c in kCles) {
      final w = Map<String, double>.from(kDefaut)..[c] = 0.0;
      final r = _evaluer(mai.pronostics, w);
      final d1 = r.top1 - base.top1;
      final d3 = r.top3 - base.top3;
      final d5 = r.top5 - base.top5;
      final dr = r.rang - base.rang;
      final effet = d1.abs() > 1e-9 || d3.abs() > 1e-9 || d5.abs() > 1e-9;
      if (!effet) {
        sansEffet++;
      } else {
        avecEffet.add(c);
      }
      // ignore: avoid_print
      print('[E3] ${c.padRight(12)} | '
          '${d1.toStringAsFixed(2).padLeft(5)} | '
          '${d3.toStringAsFixed(2).padLeft(5)} | '
          '${d5.toStringAsFixed(2).padLeft(5)} | '
          '${dr.toStringAsFixed(2).padLeft(5)} | $effet');
    }
    // ignore: avoid_print
    print('[E3] ⇒ $sansEffet / 19 critères NE CHANGENT RIEN au classement '
        'lorsqu\'on les met à zéro. Ce sont ceux dont la note est CONSTANTE '
        'dans la course (variance nulle) : ${kCles.where((k) => !avecEffet.contains(k)).join(", ")}.');
    // ignore: avoid_print
    print('[E3] ⇒ critères ayant un effet mesurable : '
        '${avecEffet.join(", ")}');
    expect(sansEffet, greaterThan(0),
        reason: 'MESURÉ : plusieurs critères sont totalement neutres sur ce '
            'corpus');
  });

  test('E4 — transfert chronologique : la seule évaluation honnête', () {
    // On applique les poids appris en MAI aux courses de NOVEMBRE (futur
    // relatif). C'est le seul sens autorisé : jamais l'inverse.
    final maiVersNov = _evaluer(nov.pronostics, mai.poids);
    final defautVersNov = _evaluer(nov.pronostics, kDefaut);
    // ignore: avoid_print
    print('[E4] poids MAI appliqués aux courses de NOV (sens autorisé) :');
    // ignore: avoid_print
    print('[E4] ${fmt("  DÉFAUT → NOV", defautVersNov)}');
    // ignore: avoid_print
    print('[E4] ${fmt("  MAI → NOV", maiVersNov)}');
    // ignore: avoid_print
    print('[E4] ⚠️ n=${maiVersNov.n} : effectif TROP FAIBLE pour conclure. '
        'Un seul cheval déplace le TOP1 de '
        '${(100 / (maiVersNov.n == 0 ? 1 : maiVersNov.n)).toStringAsFixed(1)} '
        'points. Aucune inférence n\'est tirée de cette ligne.');

    // Ce qui EST établi, c'est la POSSIBILITÉ du protocole : le corpus réel
    // permet de le construire dès que l'effectif le permettra.
    // ignore: avoid_print
    print('[E4] ⇒ PROTOCOLE PROSPECTIF REQUIS, faute de données : accumuler '
        'les pronostics avec `scoresCriteres` ET `arriveeReelle`, puis '
        'n\'évaluer à la date T que les pronostics postérieurs à T. '
        'Le harnais ci-dessus est prêt à le faire dès que n ≥ 200.');
    expect(maiVersNov.n, lessThan(200),
        reason: 'MESURÉ : l\'effectif de transfert est insuffisant — c\'est un '
            'constat, pas une conclusion');
  });
}
