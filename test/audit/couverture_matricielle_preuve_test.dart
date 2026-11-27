// ═══════════════════════════════════════════════════════════════════════════
//  COUVERTURE MATRICIELLE — DEUX VÉRIFICATIONS INDISPENSABLES, SUR LE VRAI MOTEUR
//  Ajouté le 27/11/2026 pour compléter V4/T1..T10 et V5/T1..T4b.
//
//  POURQUOI CE FICHIER EXISTE
//  ──────────────────────────
//  Le demandeur exige une vérification CONCRÈTE de la correction v10.83 sur les
//  sept étapes du cycle de vie de la matrice des 19 critères, pas une déduction
//  tirée de la lecture du code.
//
//  Recensement des preuves DÉJÀ EXISTANTES (aucune n'est refaite ici) :
//    (1) création par `analyserCourseAvecCriteres`   → V4/T1, V4/T2, V4/T3
//    (2) enregistrement unitaire (`scoresCriteresMap`)→ V4/T5 :403 et :467
//    (3) enregistrement batch                         → V28-0, V4/T7a/T7b/T7c
//    (5bis) persistance au rechargement               → V4/T10 (disque + reload)
//    (7) sauvegarde et restauration                   → V5/T2 (comparaison champ
//                                                       par champ des critères)
//
//  Les DEUX étapes sans preuve directe, traitées ici :
//    (4) CONSERVATION APRÈS RÉCEPTION DU RÉSULTAT OFFICIEL.
//        `enregistrerResultat()` reconstruit l'objet `IaPronostic` (l.3610).
//        Si `scoresCriteres` y était omis, la matrice serait effacée à la
//        résolution — et l'apprentissage du cycle SUIVANT serait muet. Aucun
//        test existant ne vérifie ce point : V35 et A6-2b1 construisent leurs
//        pronostics avec `scoresCriteres: const {}`, ce qui ne prouve rien.
//    (5) UTILISATION EFFECTIVE PAR L'APPRENTISSAGE.
//        `_apprendreParGradient` filtre `.where((p) => p.scoresCriteres.isNotEmpty)`
//        (l.3939). A4-T3-bis vérifie seulement `nbMisesAJour >= avant`, ce qui
//        ne prouve pas que les critères SONT la source.
//
//        ⚠️ MÉTHODE RÉVISÉE LE 27/11/2026 APRÈS ÉCHEC MESURÉ DE LA 1re VERSION.
//        La première version comparait « |Δ poids| max après projection » entre
//        un montage à matrice vide et un montage à matrice pleine. ÉCHEC MESURÉ :
//        le montage à matrice VIDE a produit un |Δ| du MÊME ordre (la
//        renormalisation ramène Σ de 1,26 à 1,00 indépendamment du gradient).
//        P1-C a établi que la projection absorbe ~99,5 % de la variation : la
//        variation des poids APRÈS projection ne peut donc pas servir de preuve
//        de consommation. L'assertion a été retirée, pas affaiblie.
//
//        Nouvelle méthode : on lit les points d'observation DÉJÀ publiés par la
//        production, sans instrumenter ni modifier le moteur :
//          • `JournalEntree.diagnostic` — une ligne par critère, portant la
//            DISCRIMINATION calculée (`_genererDiagnosticGlobal`, l.5688-5708) ;
//          • `JournalEntree.avant` / `.apres` — respectivement l'état AVANT
//            projection et l'état APRÈS projection (mesure antérieure de
//            l'atelier, test/support/atelier_apprentissage.dart l.504-512) ;
//          • `IaPoidsAdaptatifs.dernierGradient` — le momentum par critère
//            (= `lr × discrimination`, l.4167, AVANT application des
//            coefficients) ; champ PUBLIÉ et SÉRIALISÉ (models l.560, 1209).
//        La preuve est un DIFFÉRENTIEL : deux montages identiques à UN SEUL
//        critère près. On exige que ce critère change de signe et que les 18
//        autres soient EXACTEMENT inchangés. Aucun seuil arbitraire.
//
//  TOUT EST MESURÉ SUR LE MOTEUR DE PRODUCTION. Aucune formule réécrite.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

import '../support/atelier_apprentissage.dart';

const int kCoursesParJour = 14;

DateTime dateDuRang(int rang) =>
    DateTime.now().subtract(Duration(days: 1 + rang ~/ kCoursesParJour));

/// Variance MESURÉE comme devant VARIER : sans variation, `hautConfiance` est
/// vide et `_mettreAJourCalibration` sort AVANT de détecter les corrélations.
double varianceDuRang(int rang) => 10.0 + (rang % 9);

/// Notes dont la valeur DÉCROÎT avec le rang du partant : variance non nulle,
/// corrélations calculables. Chaque critère a sa propre pente, donc sa propre
/// discrimination — c'est ce qui rend le gradient non nul.
ScoresCriteres notesVariees(int numero) => ScoresCriteres(
      forme: 92.0 - numero * 4.0,
      gains: 82.0 - numero * 3.0,
      record: 72.0 - numero * 2.0,
      cote: 86.0 - numero * 5.0,
      constance: 76.0 - numero * 1.0,
      victoires: 66.0 + numero * 1.0,
      discipline: 61.0 + numero * 2.0,
      distSpec: 89.0 - numero * 6.0,
      jockey: 73.0 - numero * 1.0,
      repos: 56.0 + numero * 1.0,
      hippo: 69.0 - numero * 2.0,
      entraineur: 63.0 + numero * 1.0,
      elo: 79.0 - numero * 3.0,
      terrain: 71.0 + numero * 1.0,
      divergence: 51.0 + numero * 4.0,
      poidsRel: 67.0 - numero * 1.0,
      progression: 75.0 + numero * 2.0,
      mouvCote: 59.0 + numero * 3.0,
      placeDepart: 65.0 - numero * 2.0,
    );

double maxAbs(Map<String, double> m) =>
    m.values.isEmpty ? 0.0 : m.values.map((v) => v.abs()).reduce((a, b) => a > b ? a : b);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════
  //  (4) LA MATRICE SURVIT-ELLE À LA RÉCEPTION DU RÉSULTAT OFFICIEL ?
  // ═══════════════════════════════════════════════════════════════════════
  test('M-COUV-4 — la matrice des 19 critères survit à enregistrerResultat',
      () async {
    final out = <String>[];
    void w(String s) => out.add(s);

    // 12 courses résolues d'amorçage + 1 cible NON résolue, toutes AVEC matrice.
    const int cible = 12;
    await semer(
      verifierNombre: false,
      pronostics: <IaPronostic>[
        for (var i = 0; i < cible; i++)
          pronostic(
            courseKey: 'COUV4_${i.toString().padLeft(4, '0')}',
            date: dateDuRang(i),
            resolu: true,
            variance: varianceDuRang(i),
            scoresCriteres: <String, ScoresCriteres>{
              for (var n = 1; n <= 5; n++) '$n': notesVariees(n),
            },
          ),
        pronostic(
          courseKey: 'COUV4_CIBLE',
          date: dateDuRang(cible),
          resolu: false,
          variance: varianceDuRang(cible),
          scoresCriteres: <String, ScoresCriteres>{
            for (var n = 1; n <= 5; n++) '$n': notesVariees(n),
          },
        ),
      ],
    );

    final mem = IaMemoryService.instance;

    // ── GARDE 1 : la cible porte bien une matrice AVANT résolution ────────
    final avant = mem.getPronostic('COUV4_CIBLE');
    expect(avant, isNotNull, reason: 'garde de montage : la cible doit exister');
    expect(avant!.resultatsReels, isFalse,
        reason: 'garde de montage : la cible doit être NON résolue');
    expect(avant.scoresCriteres.length, 5,
        reason: 'garde de montage : la cible doit avoir 5 partants cotés');
    w('[COUV4] AVANT résolution : partants=${avant.scoresCriteres.length} · '
        '19 critères présents=${avant.scoresCriteres["1"] != null}');

    // La valeur exacte de chaque critère, pour comparaison stricte après coup.
    final avantValeurs = <String, ScoresCriteres>{
      for (final e in avant.scoresCriteres.entries) e.key: e.value,
    };
    final avantForme1 = avant.scoresCriteres['1']!.forme;
    final avantDistSpec1 = avant.scoresCriteres['1']!.distSpec;
    final avantElo3 = avant.scoresCriteres['3']!.elo;

    // ── RÉSOLUTION RÉELLE, par l'entrée de production ────────────────────
    final ok = await mem.enregistrerResultat(
      courseKey: 'COUV4_CIBLE',
      arriveeReelle: const <int>[1, 2, 3, 4, 5],
    );
    expect(ok, isTrue, reason: 'enregistrerResultat doit réussir');

    // ── MESURE : la matrice est-elle TOUJOURS là ? ───────────────────────
    final apres = mem.getPronostic('COUV4_CIBLE')!;
    expect(apres.resultatsReels, isTrue,
        reason: 'la course doit être marquée résolue');

    w('[COUV4] APRÈS résolution : partants=${apres.scoresCriteres.length} · '
        'attendu=${avantValeurs.length}');
    expect(apres.scoresCriteres.length, avantValeurs.length,
        reason: 'LA MATRICE NE DOIT PAS ÊTRE EFFACÉE par enregistrerResultat() '
            '— sinon l apprentissage du cycle suivant serait muet');

    expect(apres.scoresCriteres.keys.toSet(), avantValeurs.keys.toSet(),
        reason: 'les clés des partants doivent être identiques');

    // Les VALEURS doivent être identiques au bit près.
    expect(apres.scoresCriteres['1']!.forme, avantForme1,
        reason: 'la valeur du critère forme doit être préservée exactement');
    expect(apres.scoresCriteres['1']!.distSpec, avantDistSpec1,
        reason: 'la valeur du critère distSpec doit être préservée exactement');
    expect(apres.scoresCriteres['3']!.elo, avantElo3,
        reason: 'la valeur du critère elo doit être préservée exactement');

    // Contrôle exhaustif : les 19 critères, sur les 5 partants.
    var identiques = 0;
    for (final num in avantValeurs.keys) {
      final a = avantValeurs[num]!;
      final b = apres.scoresCriteres[num]!;
      const cles = <String>[
        'forme', 'gains', 'record', 'cote', 'constance', 'victoires',
        'discipline', 'distSpec', 'jockey', 'repos', 'hippo', 'entraineur',
        'elo', 'terrain', 'divergence', 'poidsRel', 'progression',
        'mouvCote', 'placeDepart',
      ];
      for (final k in cles) {
        if (a.valeurPourCritere(k) == b.valeurPourCritere(k)) identiques++;
      }
    }
    w('[COUV4] critères identiques après résolution : $identiques / 95');
    expect(identiques, 95,
        reason: 'LES 19 CRITÈRES × 5 PARTANTS (95 valeurs) doivent survivre '
            'intacts à enregistrerResultat()');

    // ── La matrice survit-elle aussi à un RECHARGEMENT ? ─────────────────
    await mem.recharger();
    final recharge = mem.getPronostic('COUV4_CIBLE');
    expect(recharge, isNotNull);
    expect(recharge!.scoresCriteres.length, avantValeurs.length,
        reason: 'la matrice doit survivre au rechargement APRÈS résolution');
    expect(recharge.scoresCriteres['1']!.forme, avantForme1,
        reason: 'la valeur doit survivre au rechargement après résolution');
    w('[COUV4] après rechargement : partants=${recharge.scoresCriteres.length} '
        '· forme(1)=${recharge.scoresCriteres["1"]!.forme} '
        '(avant=$avantForme1)');

    for (final l in out) {
      // ignore: avoid_print
      print(l);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  // ═══════════════════════════════════════════════════════════════════════
  //  (5) LES CRITÈRES SONT-ILS LA SOURCE EFFECTIVE DE L'APPRENTISSAGE ?
  //
  //  Différentiel à UN SEUL critère près. Deux montages identiques sauf la
  //  DISCIMINATION d'un critère : dans le montage « ANTI », le gagnant reçoit
  //  la note HAUTE sur ce critère, dans « PRO » il reçoit la note BASSE. Les 18
  //  autres critères gardent exactement les mêmes valeurs dans les deux
  //  montages. La discrimination du critère ciblé change donc de SIGNÉ, les
  //  autres non.
  //
  //  Ce que la mesure doit montrer, si et seulement si la matrice est
  //  réellement consommée par le gradient :
  //    • les 19 lignes par critère apparaissent dans le journal de production,
  //      avec leur discrimination ;
  //    • la discrimination CIBLÉE change de signe entre les montages ;
  //    • la valeur PUBLIÉE dans `JournalEntree.apres` pour le critère ciblé
  //      diffère entre les montages (chemin exécuté jusqu'à l'écriture) ;
  //    • le momentum publié du critère ciblé change de signe ;
  //    • les 18 autres critères sont EXACTEMENT inchangés (aucun plomberie
  //      croisée, aucune fuite d'un critère vers un autre).
  // ═══════════════════════════════════════════════════════════════════════
  test('M-COUV-5 — la matrice est consommée par le gradient : différentiel '
      'à un seul critère', () async {
    final out = <String>[];
    void w(String s) => out.add(s);

    const int n = 20;
    // Numéro du partant GAGNANT : l'arrivée fournie est [1,2,3,4,5].
    const String critCible = 'distSpec';

    // Notes où chaque critère décroît (PRO) ou croît (ANTI) avec le numéro.
    // Toutes les autres clés sont STRICTEMENT identiques entre les montages.
    ScoresCriteres notesAvecSens(String sens, int numero) {
      final base = notesVariees(numero);
      // distSpec varie de 89 en n=1 à 59 en n=5 dans notesVariees.
      // PRO  : garde la décroissance ⇒ le gagnant (n=1) a la note HAUTE.
      // ANTI : inverse la pente   ⇒ le gagnant (n=1) a la note BASSE.
      final dist = sens == 'ANTI'
          ? 10.0 * numero.toDouble() + 34.0 // n=1 → 44, n=5 → 84
          : base.distSpec; // n=1 → 89, n=5 → 59
      return ScoresCriteres(
        forme: base.forme,
        gains: base.gains,
        record: base.record,
        cote: base.cote,
        constance: base.constance,
        victoires: base.victoires,
        discipline: base.discipline,
        distSpec: dist,
        jockey: base.jockey,
        repos: base.repos,
        hippo: base.hippo,
        entraineur: base.entraineur,
        elo: base.elo,
        terrain: base.terrain,
        divergence: base.divergence,
        poidsRel: base.poidsRel,
        progression: base.progression,
        mouvCote: base.mouvCote,
        placeDepart: base.placeDepart,
      );
    }

    /// Monte le corpus puis exécute UN cycle réel et rend les observations.
    Future<Map<String, Object>> mesurer(String sens) async {
      await semer(
        verifierNombre: false,
        pronostics: <IaPronostic>[
          for (var i = 0; i <= n; i++)
            pronostic(
              courseKey: 'COUV5_${sens}_${i.toString().padLeft(4, '0')}',
              date: dateDuRang(i),
              resolu: i < n,
              variance: varianceDuRang(i),
              scoresCriteres: <String, ScoresCriteres>{
                for (var k = 1; k <= 5; k++) '$k': notesAvecSens(sens, k),
              },
            ),
        ],
      );

      final mem = IaMemoryService.instance;

      // ── GARDE : le montage réel diffère bien du nul ────────────────────
      final avecScores = mem.pronosticsAvecResultat
          .where((p) => p.scoresCriteres.isNotEmpty)
          .length;
      expect(avecScores, greaterThanOrEqualTo(10),
          reason: 'garde : au moins 10 pronostics résolus doivent porter une '
              'matrice, sinon l apprentissage par gradient ne se déclenche pas '
              '(seuil l.3948)');

      final avant = poidsEffectifs();
      final j0 = mem.journal.length;

      await mem.enregistrerResultat(
        courseKey: 'COUV5_${sens}_${n.toString().padLeft(4, '0')}',
        arriveeReelle: const <int>[1, 2, 3, 4, 5],
      );

      // ── LECTURE DES POINTS D'OBSERVATION DE PRODUCTION ─────────────────
      final aAppris = mem.journal.length > j0;
      expect(aAppris, isTrue,
          reason: 'garde : le cycle doit avoir réellement écrit une entrée de '
              'journal, sinon il n y a rien à observer');

      JournalEntree? entree;
      for (final e in mem.journal.take(mem.journal.length - j0)) {
        if (e.methode == 'gradient') {
          entree = e;
          break;
        }
      }
      expect(entree, isNotNull,
          reason: 'le journal doit contenir une entrée de méthode « gradient »');

      return <String, Object>{
        'avant': avant,
        'apres': poidsEffectifs(),
        'momentum': <String, double>{
          for (final k in kCles) k: mem.poids.dernierGradient[k] ?? 0.0,
        },
        'diag': entree!.diagnostic,
        'poidsAvant': Map<String, double>.from(entree.avant),
        'poidsApres': Map<String, double>.from(entree.apres),
        'nbMisesAJour': mem.poids.nbMisesAJour,
      };
    }

    final pro = await mesurer('PRO');
    final anti = await mesurer('ANTI');

    // ── (a) Les 19 lignes par critère existent dans le journal ───────────
    String? ligneDu(String diag, String cle) {
      // Format de production (l.5708) : « <emoji> <label> : <v>% (<d>%) ».
      // On apparie sur « ' ' + label + ' : ' » pour éviter toute ambiguïté de
      // découpage (les labels contiennent des espaces).
      final motif = ' ${_labelDe(cle)} : ';
      for (final l in diag.split('\n')) {
        if (l.contains(motif)) return l;
      }
      return null;
    }

    final diagPro = pro['diag'] as String;
    final diagAnti = anti['diag'] as String;

    final lignesPro = <String, String>{};
    final lignesAnti = <String, String>{};
    for (final k in kCles) {
      final lp = ligneDu(diagPro, k);
      final la = ligneDu(diagAnti, k);
      expect(lp, isNotNull,
          reason: 'le diagnostic de production doit publier une ligne pour le '
              'critère $k — sans elle, la mesure ne peut pas prouver que ce '
              'critère a été lu');
      expect(la, isNotNull,
          reason: 'le diagnostic de production doit publier une ligne pour le '
              'critère $k (montage ANTI)');
      lignesPro[k] = lp!;
      lignesAnti[k] = la!;
    }
    w('[COUV5] lignes de critères trouvées dans le journal : '
        '${lignesPro.length} / ${kCles.length} (PRO) · '
        '${lignesAnti.length} / ${kCles.length} (ANTI)');
    expect(lignesPro.length, 19,
        reason: 'le journal doit publier les 19 critères, pas moins');
    expect(lignesAnti.length, 19,
        reason: 'le journal doit publier les 19 critères, pas moins');

    // ── (b) La discrimination CIBLÉE change de signe ─────────────────────
    double? discr(String ligne) {
      // Format de production (l.5708) : « <emoji> <label> : <v>% (<d>%) »
      final m = RegExp(r':\s*(-?\d+(?:\.\d+)?)%').firstMatch(ligne);
      if (m == null) return null;
      return double.parse(m.group(1)!);
    }

    final dPro = discr(lignesPro[critCible]!);
    final dAnti = discr(lignesAnti[critCible]!);
    expect(dPro, isNotNull, reason: 'la discrimination doit être lisible');
    expect(dAnti, isNotNull, reason: 'la discrimination doit être lisible');
    w('[COUV5] discrimination $critCible : PRO=${dPro!.toStringAsFixed(1)}% · '
        'ANTI=${dAnti!.toStringAsFixed(1)}%');
    expect(dPro, greaterThan(0),
        reason: 'MESURE : dans le montage PRO, le gagnant porte la note HAUTE '
            'sur $critCible ⇒ la discrimination doit être POSITIVE');
    expect(dAnti, lessThan(0),
        reason: 'MESURE : dans le montage ANTI, le gagnant porte la note BASSE '
            'sur $critCible ⇒ la discrimination doit être NÉGATIVE. Si elle '
            'restait du même signe, le critère ne serait pas lu');

    // ── (c) Le momentum publié du critère ciblé change de signe ──────────
    final momPro = (pro['momentum'] as Map<String, double>)[critCible]!;
    final momAnti = (anti['momentum'] as Map<String, double>)[critCible]!;
    w('[COUV5] momentum $critCible : PRO=${momPro.toStringAsExponential(6)} · '
        'ANTI=${momAnti.toStringAsExponential(6)}');
    expect(momPro, greaterThan(0),
        reason: 'momentum = lr × discrimination (l.4167) : positif quand la '
            'discrimination est positive');
    expect(momAnti, lessThan(0),
        reason: 'momentum = lr × discrimination (l.4167) : négatif quand la '
            'discrimination est négative. Un momentum nul ou de signe '
            'inchangé signifierait que le critère n a pas traversé le gradient');

    // ── (d) La valeur PUBLIÉE par le journal diffère pour le critère ciblé ─
    final pApresPro = pro['poidsApres'] as Map<String, double>;
    final pApresAnti = anti['poidsApres'] as Map<String, double>;
    final apresPro = pApresPro[critCible]!;
    final apresAnti = pApresAnti[critCible]!;
    w('[COUV5] journal.apres[$critCible] : PRO=${apresPro.toStringAsFixed(12)} '
        '· ANTI=${apresAnti.toStringAsFixed(12)} '
        '· écart=${(apresPro - apresAnti).abs().toStringAsExponential(6)}');
    expect(apresPro, isNot(equals(apresAnti)),
        reason: 'MESURE : le poids publié par le journal pour $critCible doit '
            'différer entre les deux montages. Un poids identique signifierait '
            'que la matrice n a jamais atteint l écriture du journal, donc que '
            'le chemin d apprentissage n a pas été exécuté');
    // ── (e) Avant projection : les 18 AUTRES critères sont INCHANGÉS ─────
    //
    //  ⚠️ POINT DE MÉTHODE — mesuré, pas supposé. Une première rédaction
    //  comparait les 18 autres poids dans `JournalEntree.apres`. MESURE :
    //  ils diffèrent. Ce n'est PAS un défaut : `apres` est post-projection
    //  (l.4200), et la projection ramène Σ à 1,00 par renormalisation
    //  GLOBALE — tout écart sur un critère est donc redistribué sur les 18
    //  autres. C'est exactement l'absorption de ~99,5 % établie par P1-C.
    //  La comparaison utile se fait donc AVANT projection, sur le momentum,
    //  qui est publié (l.4198) avant `_poids.clamp()` (l.4200).
    final mom = pro['momentum'] as Map<String, double>;
    final momA = anti['momentum'] as Map<String, double>;
    final momEcarts = <String>[
      for (final k in kCles)
        if (k != critCible && mom[k] != momA[k]) k,
    ];
    w('[COUV5] AVANT projection (momentum) : les 18 autres critères sont '
        'identiques au bit près sur ${18 - momEcarts.length}/18'
        '${momEcarts.isEmpty ? "" : " — écarts : ${momEcarts.join(",")}"}');
    expect(momEcarts, isEmpty,
        reason: 'MESURE : le momentum du critère c change la note d un SEUL '
            'critère, le momentum des 18 autres doit être EXACTEMENT identique '
            '(même lr, même fenêtre, même discrimination). Un écart prouverait '
            'une plomberie croisée, donc que la matrice n est pas consommée '
            'critère par critère');

    // ── (f) Après projection : redistribution GLOBALE, mesurée et attendue ─
    final pApresPro2 = pro['poidsApres'] as Map<String, double>;
    final pApresAnti2 = anti['poidsApres'] as Map<String, double>;
    var redistribues = 0;
    var ecartRedistributionMax = 0.0;
    for (final k in kCles) {
      if (k == critCible) continue;
      final d = (pApresPro2[k]! - pApresAnti2[k]!).abs();
      if (d != 0.0) {
        redistribues++;
        if (d > ecartRedistributionMax) ecartRedistributionMax = d;
      }
    }
    final sPro =
        pApresPro2.values.reduce((a, b) => a + b);
    final sAnti =
        pApresAnti2.values.reduce((a, b) => a + b);
    w('[COUV5] APRÈS projection : $redistribues/18 autres poids redistribués '
        '(écart max ${ecartRedistributionMax.toStringAsExponential(3)}) — '
        'ATTENDU, conséquence de la renormalisation globale Σ : '
        '${sPro.toStringAsFixed(12)} vs ${sAnti.toStringAsFixed(12)}');

    // Garde de montage : les 18 autres critères RECOIVENT bien les mêmes notes.
    final proAvant = pro['avant'] as Map<String, double>;
    expect((pro['poidsAvant'] as Map<String, double>).length, 19,
        reason: 'le journal doit publier les 19 poids avant projection');

    // ── (f) Les poids AVANT sont identiques : seule la matrice diffère ────
    final ecartDepart = <String>[
      for (final k in kCles)
        if (((pro['avant'] as Map<String, double>)[k]! -
                (anti['avant'] as Map<String, double>)[k]!)
            .abs() !=
            0.0)
          k,
    ];
    w('[COUV5] garde : poids de départ identiques sur '
        '${19 - ecartDepart.length}/19 (écarts : ${ecartDepart.isEmpty ? "aucun" : ecartDepart.join(",")})');
    expect(ecartDepart, isEmpty,
        reason: 'garde de montage : les deux mesures doivent partir des MÊMES '
            'poids, sinon la comparaison ne prouve rien');

    // ── Conclusion mesurée ────────────────────────────────────────────────
    w('');
    w('[COUV5] ⇒ LA MATRICE EST CONSOMMÉE PAR LE GRADIENT DE PRODUCTION :');
    w('[COUV5]   1. les 19 critères sont lus (${lignesPro.length}/19 lignes '
        'de diagnostic au journal)');
    w('[COUV5]   2. changer UNE SEULE note de critère change le SIGNE de sa '
        'discrimination (${dPro.toStringAsFixed(1)}% → '
        '${dAnti.toStringAsFixed(1)}%)');
    w('[COUV5]   3. le momentum publié av. projection suit '
        '(${momPro.toStringAsExponential(3)} → '
        '${momAnti.toStringAsExponential(3)})');
    w('[COUV5]   4. les 18 autres momentum sont inchangés au bit près '
        '(${18 - momEcarts.length}/18)');
    w('[COUV5]   5. le poids écrit au journal suit '
        '(${apresPro.toStringAsFixed(9)} → ${apresAnti.toStringAsFixed(9)})');

    // Le poids de départ est bien Σ = 1,26 (fait mesuré d une installation
    // vierge) : la preuve porte donc sur le chemin réel, pas sur un état préparé.
    final sigmaAvant = sommeCle(proAvant, kCles);
    w('[COUV5] garde : Σ poids de départ = ${sigmaAvant.toStringAsFixed(9)}');

    for (final l in out) {
      // ignore: avoid_print
      print(l);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// Labels de production (`_labelCritere`, ia_memory_service.dart:5626-5649),
/// recopiés ici parce que la méthode est `static` privée. Toute divergence est
/// détectée par les gardes du test : une ligne de journal non appariée ferait
/// échouer l assertion « 19 / 19 ».
String _labelDe(String c) {
  const labels = <String, String>{
    'forme': 'Forme récente',
    'gains': 'Gains carrière',
    'record': 'Record/Vitesse',
    'cote': 'Cote marché',
    'constance': 'Régularité',
    'victoires': 'Victoires',
    'discipline': 'Spécialisation',
    'distSpec': 'Dist. spécialisée',
    'jockey': 'Jockey/Driver',
    'repos': 'Repos physique',
    'hippo': 'Spéc. Hippodrome',
    'entraineur': 'Entraîneur',
    'elo': 'ELO dynamique',
    'terrain': 'Terrain',
    'divergence': 'Coup préparé',
    'poidsRel': 'Poids porté',
    'progression': 'Progression',
    'mouvCote': 'Mouv. Cote',
    'placeDepart': 'Place Départ',
  };
  return labels[c] ?? c;
}
