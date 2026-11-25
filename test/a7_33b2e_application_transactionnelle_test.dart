// ═══════════════════════════════════════════════════════════════════════════
//  A7 / 3.3-B2-e — PROTECTION TRANSACTIONNELLE DE L'APPLICATION ELO
//
//  OBJET DU LOT
//  ────────────
//  Prouver, par la MESURE, que l'application ELO après arrivée :
//    1. AMORCE le registre `elo_registre_v3` quand il est absent (§6) ;
//    2. TRANSMET l'identité de course et REFUSE toute ré-application d'une
//       course déjà journalisée (§7) ;
//    3. PERSISTE une intention AVANT toute mutation de rating (§5, étape B) ;
//    4. FINALISE la même entrée après la sauvegarde des ratings (étape D) ;
//    5. PRÉSERVE les états incertains (aucune réparation automatique) ;
//    6. PRÉSERVE les mécanismes de concurrence et de reset (B1, B2-a).
//
//  ⚠️ CE QUE CE FICHIER NE FAIT **PAS** — À LIRE AVANT TOUTE INTERPRÉTATION
//  ──────────────────────────────────────────────────────────────────────
//  • il ne modifie AUCUNE formule ELO, aucun coefficient K, aucun seuil ;
//  • il ne « répare » jamais un registre divergent/corrompu : il VÉRIFIE que
//    le service refuse, ce qui est l'inverse ;
//  • il ne sème un registre cohérent QUE dans les groupes qui testent la
//    DÉTECTION DE DOUBLON sur un registre préexistant — jamais dans le test
//    bout-en-bout du §7, qui part d'un stockage VIDE (correctif méthodologique
//    du défaut relevé sur les tests B2-d2).
//
//  ⚠️ MESURE PRÉALABLE SUR LE HARNAIS — DÉFAUT CORRIGÉ ICI
//  ────────────────────────────────────────────────────────
//  `SharedPreferences.remove('<clé>')` transmet à la plateforme la clé DÉJÀ
//  PRÉFIXÉE `flutter.<clé>`. Un store de test qui indexe sur `flutter.<clé>`
//  ne supprime donc RIEN si on lui passe la clé nue : c'est un no-op
//  SILENCIEUX. Toutes les suppressions de ce fichier passent par
//  [_Store.supprimer], qui applique le préfixe.
//
//  ⚠️ MESURE PRÉALABLE SUR LE REDÉMARRAGE
//  ───────────────────────────────────────
//  `EloService._charger()` commence par `if (_charge) return;` et AUCUN point
//  public ne repasse `_charge` à `false` (mesuré : `grep -n "_charge"` →
//  l.722 déclaration, l.1447/1480/1507/1842/2608, et le commentaire l.2687 qui
//  l'exclut explicitement du reset). Un redémarrage ne peut donc PAS être
//  simulé par `EloService.init()` dans un même processus de test.
//
//  Le redémarrage est donc simulé LÀ OÙ IL EST OBSERVABLE, sans toucher au
//  code de production : on jette la RAM (`viderMemoirePourResetComplet`), on
//  invalide le cache SharedPreferences (`resetStatic`), puis on RELIT les deux
//  clés du disque avec les mêmes décodeurs que la production
//  (`jsonDecode` + `EloScore.fromJson`, `RegistreEloV3.decoder`). La
//  décision testée — « cette course a-t-elle déjà été journalisée ? » — repose
//  alors EXCLUSIVEMENT sur le contenu du disque, ce qui est précisément la
//  propriété à démontrer. Cette limite est assumée et signalée dans le
//  rapport : elle ne vaut pas preuve d'un redémarrage de processus réel.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/models/elo_registre_v3.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/utils/elo_empreinte.dart';

// ───────────────────────────────────────────────────────────────────────────
//  STORE INSTRUMENTÉ
//  Même contrat que B1 / B2-a / B2-b, PLUS le pilotage des échecs d'écriture
//  et de lecture, nécessaires aux tests transactionnels.
// ───────────────────────────────────────────────────────────────────────────

class _Store extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};
  final List<String> journal = <String>[];

  /// Clés dont l'écriture doit ÉCHOUER (rendre `false`).
  final Set<String> echecsEcriture = <String>{};

  /// Clés dont l'écriture doit LEVER.
  final Set<String> exceptionsEcriture = <String>{};

  /// Prochain `getAllWithParameters` doit LEVER (lecture indisponible).
  bool lectureDoitLever = false;

  String? cleSuspendue;
  Completer<void>? _entreeSuspendue;
  Completer<void>? _verrouSuspendu;

  // ★ B2e-9 — suspension de `getAllWithParameters`, SEUL moyen de retenir un
  // appelant À L'INTÉRIEUR de `SharedPreferences.getInstance()`.
  Completer<void>? _verrouGetAll;
  Completer<void>? _entreeGetAll;

  @override
  Future<bool> clear() async {
    journal.add('CLEAR');
    _valeurs.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<Map<String, Object>> getAllWithParameters(
      GetAllParameters parameters) async {
    journal.add('GETALL');
    final verrou = _verrouGetAll;
    if (verrou != null) {
      final entree = _entreeGetAll;
      _entreeGetAll = null;
      if (entree != null && !entree.isCompleted) entree.complete();
      await verrou.future;
    }
    if (lectureDoitLever) {
      lectureDoitLever = false;
      throw StateError('lecture du stockage impossible (simulée)');
    }
    final prefix = parameters.filter.prefix;
    return <String, Object>{
      for (final e in _valeurs.entries)
        if (e.key.startsWith(prefix)) e.key: e.value,
    };
  }

  @override
  Future<bool> remove(String key) async {
    journal.add('REM $key');
    _valeurs.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    journal.add('SET-ENTREE $key');
    // ÉGALITÉ STRICTE — jamais `contains`.
    if (cleSuspendue != null && key == cleSuspendue) {
      final entree = _entreeSuspendue;
      _entreeSuspendue = null;
      if (entree != null && !entree.isCompleted) entree.complete();
      final verrou = _verrouSuspendu;
      if (verrou != null) await verrou.future;
    }
    if (exceptionsEcriture.contains(key)) {
      throw StateError('écriture impossible (simulée) sur $key');
    }
    if (echecsEcriture.contains(key)) {
      journal.add('SET-REFUS $key');
      return false;
    }
    _valeurs[key] = value;
    journal.add('SET-OK $key');
    return true;
  }

  Future<void> armerSuspension(String cle) {
    final entree = Completer<void>();
    _entreeSuspendue = entree;
    cleSuspendue = cle;
    _verrouSuspendu = Completer<void>();
    return entree.future;
  }

  void libererSuspension() {
    final v = _verrouSuspendu;
    _verrouSuspendu = null;
    cleSuspendue = null;
    if (v != null && !v.isCompleted) v.complete();
  }

  void desarmer() {
    cleSuspendue = null;
    _entreeSuspendue = null;
    final v = _verrouSuspendu;
    _verrouSuspendu = null;
    if (v != null && !v.isCompleted) v.complete();
    // ★ B2e-9 : la suspension de `getInstance()` doit être relâchée, sinon le
    // `tearDown` laisserait une future pendante.
    final vg = _verrouGetAll;
    _verrouGetAll = null;
    _entreeGetAll = null;
    if (vg != null && !vg.isCompleted) vg.complete();
  }

  /// ★ B2e-9 — arme la suspension de `getAllWithParameters`, donc de
  /// `SharedPreferences.getInstance()`. Rend la future complétée à l'ENTRÉE de
  /// la suspension.
  Future<void> armerSuspensionGetAll() {
    final entree = Completer<void>();
    _entreeGetAll = entree;
    _verrouGetAll = Completer<void>();
    return entree.future;
  }

  void libererGetAll() {
    final v = _verrouGetAll;
    _verrouGetAll = null;
    if (v != null && !v.isCompleted) v.complete();
  }

  // ── Lecture / écriture avec préfixe, comme le fait la production ─────────

  Future<void> semer(String cle, Object valeur) async =>
      _valeurs['flutter.$cle'] = valeur;
  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');

  /// Lit la valeur BRUTE telle que la production la verrait.
  Object? lire(String cle) => _valeurs['flutter.$cle'];

  /// Suppression fidèle : `SharedPreferences.remove` préfixe déjà la clé.
  Future<bool> supprimer(String cle) => remove('flutter.$cle');

  Set<String> clesEcritesDepuis(int index) => journal
      .skip(index)
      .where((e) => e.startsWith('SET-OK '))
      .map((e) => e.substring('SET-OK '.length))
      .toSet();

  /// Écritures REFUSÉES depuis [index] — utile aux tests qui forcent un échec.
  Set<String> clesRefuseesDepuis(int index) => journal
      .skip(index)
      .where((e) => e.startsWith('SET-REFUS '))
      .map((e) => e.substring('SET-REFUS '.length))
      .toSet();
}

// Type privé volontaire : le dispositif reste local à ce fichier.
// ignore: library_private_types_in_public_api
late _Store store;

void _installerStore() {
  store = _Store();
  SharedPreferencesStorePlatform.instance = store;
  SharedPreferences.resetStatic();
}

/// Vidage BORNÉ de la boucle d'événements (nombre de tours, jamais une durée).
Future<void> _laisserProgresser([int tours = 32]) async {
  for (var i = 0; i < tours; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

// ── Constantes partagées avec les lots B1 / B2-a / B2-b ────────────────────

const String kDisc = 'Trot Attelé';
const String kCleElo = 'elo_ratings_v2';
const String kCleTs = 'elo_ratings_v2_ts';
const String kCleRegistre = 'elo_registre_v3';
const String kJournalElo = 'flutter.$kCleElo';

/// ⚠️ Date ANCRÉE DANS LE PASSÉ. Depuis l'étape A de B2-e, une clé portant une
/// date postérieure au LENDEMAIN de l'instant courant est refusée
/// (`datePosterieure`). Utiliser une date future testerait ce refus, pas
/// l'application. Mesure de la date système au moment de l'écriture du lot :
/// 2026-11-18.
const String kCleCourse = 'R1C1_01112026';

/// ★ B2e-8 — identités supplémentaires pour les scénarios de reset concurrent.
/// Chaque course distincte a sa propre clé ; toutes sont dans le PASSÉ.
const String kCleCourse1 = 'R1C1_01112026';
const String kCleCourse2 = 'R2C2_02112026';

ZtPartant _partant(int num) => ZtPartant(
      numero: '$num',
      nom: 'CHEVAL_$num',
      driver: 'DRIVER_$num',
      entraineur: 'ENTR_$num',
      proprietaire: 'PROP_$num',
      gains: '${num * 10000}',
      record: '1\'1${num % 10}"0',
      musique: '1a2a3a4a5a',
      cote: '4.0',
      ageSexe: '5 M',
      poids: 57.0 + num,
      placeDepartInt: num,
      joursRepos: 10 + num,
      hippodromeActuel: 'VINCENNES',
      statsJockeyCsv: 'JOCKEY_$num|15|40|12',
      statsHippodromeCsv: 'VINCENNES|20|45|15',
      statsEntraineurCsv: 'ENTR_$num|12|33|8',
      eloRating: 1500.0,
      eloNbCourses: 20,
      eloVariationMois: 5.0,
      statsTerrainCsv: 'bon|6|2|4',
      gainsDernierAn: num * 5000,
    );

final List<ZtPartant> kPartants = List.generate(6, (i) => _partant(i + 1));
const List<int> kArrivee = <int>[1, 2, 3];

/// Relit les ratings EN SÉRIALISÉS sur le disque, avec le décodeur EXACT de
/// la production (`jsonDecode` + `EloScore.fromJson`).
///
/// ⚠️ Ce n'est pas un redémarrage de processus : voir l'en-tête. C'est une
///    lecture du DISQUE, ce qui est la seule chose que la décision de doublon
///    consulte réellement.
Map<String, EloScore> _ratingsSurDisque() {
  final brut = store.lire(kCleElo);
  if (brut is! String) return <String, EloScore>{};
  final map = jsonDecode(brut) as Map<String, dynamic>;
  final out = <String, EloScore>{};
  map.forEach((k, v) {
    out[k] = EloScore.fromJson(v as Map<String, dynamic>);
  });
  return out;
}

/// Relit le registre SUR LE DISQUE, avec le décodeur EXACT de la production.
RegistreEloV3? _registreSurDisque() {
  final brut = store.lire(kCleRegistre);
  if (brut is! String) return null;
  return RegistreEloV3.decoder(brut);
}

/// Empreinte des ratings TELS QU'ILS SONT SUR LE DISQUE.
String _empreinteDisque() => empreinte64Ratings(_ratingsSurDisque());

/// Simule l'arrêt puis le REDÉMARRAGE du processus.
///
/// ⚠️ POURQUOI CE N'EST PAS SEULEMENT `viderMemoirePourResetComplet()`.
///    Mesuré : `_mettreAJourApresArrivee` appelle `if (!_charge) await
///    _charger()` (l.1842). Or `viderMemoirePourResetComplet()` vide `_ratings`
///    SANS toucher `_charge` (comportement documenté, l.2687). Le service
///    verrait donc `_charge == true` avec une RAM VIDE : un état que la
///    production ne produit JAMAIS au démarrage, puisque `_charger()` y
///    remplit `_ratings` depuis le disque.
///
///    Un premier essai de ce fichier a mesuré exactement ce défaut de harnais :
///    l'opération d'après « redémarrage » rendait `registreNonCoherent` parce
///    que l'empreinte était calculée sur une RAM vide.
///
///    La simulation fidèle consiste donc à vider la RAM puis à la RECHARGER
///    depuis le disque, avec le décodeur exact de la production. C'est ce que
///    fait `_charger()` (branche v2 : `jsonDecode` + `EloScore.fromJson`).
void _simulerRedemarrage() {
  final elo = EloService.instance;
  elo.viderMemoirePourResetComplet();
  // Le cache des instances SharedPreferences porte `_preferenceCache` : on
  // l'invalide pour que toute lecture ultérieure repasse par le STORE.
  SharedPreferences.resetStatic();
  // Rechargement depuis le DISQUE, comme au démarrage de l'application.
  elo.chargerDepuisMapIsolate(_ratingsSurDisqueJson());
}

/// Relit la map de ratings du disque au format JSON brut attendu par
/// `chargerDepuisMapIsolate`.
Map<String, dynamic> _ratingsSurDisqueJson() {
  final brut = store.lire(kCleElo);
  if (brut is! String) return <String, dynamic>{};
  return jsonDecode(brut) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _installerStore();
    await EloService.init();
    EloService.instance.viderMemoirePourResetComplet();
  });

  tearDown(() {
    store.desarmer();
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2e-1 — SCÉNARIO BOUT-EN-BOUT DU §7, SANS REGISTRE PRÉ-INJECTÉ
  //
  //  C'est LE test du mandat. Il ne sème AUCUN registre : le stockage est
  //  vide au départ. Tout ce qui apparaît doit avoir été produit par le
  //  service lui-même.
  //
  //  Séquence imposée : stockage vide → amorçage → première application ELO →
  //  sauvegarde → redémarrage → seconde présentation de la même course → refus.
  //
  //  ⚠️ CE TEST CORRIGE LE DÉFAUT MÉTHODOLOGIQUE DE B2-d2, dont les tests
  //     semaient un registre cohérent — un état que la production ne produisait
  //     jamais (cercle vicieux CS-4/CS-5).
  // ═════════════════════════════════════════════════════════════════════════
  group('B2e-1 — bout-en-bout §7 sans registre pré-injecté', () {
    test('B2e-1a — stockage vide → amorçage → application → persistance → '
        'redémarrage → refus de la même course', () async {
      final elo = EloService.instance;

      // ── 0. Le stockage est VIDE. On le prouve, on ne le suppose pas. ─────
      expect(store.contient(kCleRegistre), isFalse,
          reason: 'postulat du §7 : AUCUN registre pré-injecté');
      expect(store.contient(kCleElo), isFalse,
          reason: 'postulat du §7 : AUCUN rating pré-injecté');
      expect(elo.nbChevauxSuivis, 0, reason: 'RAM vide');

      // ── 1. Première application : le registre doit être AMORCÉ puis l'ELO
      //        appliqué puis journalisé, en une seule opération. ────────────
      final etat1 = await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse,
      );
      await _laisserProgresser();

      final res1 = elo.dernierResultatMiseAJour;
      // ignore: avoid_print
      print('[B2e-1a] op1 → $etat1 | $res1');

      expect(etat1, EtatPersistanceElo.persistee,
          reason: 'les ratings sont écrits et confirmés');
      expect(res1, isNotNull);
      expect(res1!.motifRefus, isNull, reason: 'aucun refus : rien à refuser');
      expect(res1.amorcageEffectue, isTrue,
          reason: '§6 : le registre ABSENT est amorcé par le service lui-même');
      expect(res1.origineAvant, OrigineRegistreElo.courante,
          reason: 'RAM vide ⇒ Cas A : `origine: courante`');
      expect(res1.journalisationConfirmee, isTrue,
          reason: 'l\'entrée `course` est persistée ET finalisée');
      expect(res1.etapeEntree, EtapeEntreeRegistre.appliquee);
      expect(res1.protectionEffective, isTrue);

      // ── 2. Les faits sont VÉRIFIÉS SUR LE DISQUE, pas dans la RAM. ──────
      final reg1 = _registreSurDisque();
      expect(reg1, isNotNull,
          reason: 'le registre existe désormais sur le disque — il a été créé '
              'par le service, aucun test ne l\'a semé');
      expect(reg1!.entrees.length, 1,
          reason: 'exactement une entrée : l\'amorçage n\'invente aucune entrée '
              'historique');
      final entree1 = reg1.entrees.single;
      expect(entree1.type, TypeEntreeRegistre.course);
      expect(entree1.cle, kCleCourse);
      expect(entree1.etape, EtapeEntreeRegistre.appliquee);
      expect(entree1.issue, IssueEcritureElo.persistee);
      expect(entree1.tsFinal, isNotNull);
      expect(entree1.empreinteAvant, isNot(entree1.empreinteApres),
          reason: 'la mutation a bien changé les ratings');

      // Le registre déclare l'empreinte RÉELLEMENT persistée : c'est ce qui
      // le rendra `coherent` au rechargement suivant.
      expect(reg1.empreinteRatings, _empreinteDisque(),
          reason: 'cohérence disque ↔ registre, mesurée');

      // Les ratings ont réellement bougé.
      final disque1 = _ratingsSurDisque();
      expect(disque1, isNotEmpty);
      expect(disque1.values.any((s) => s.rating != 1500.0), isTrue);

      // ── 3. REDÉMARRAGE. ─────────────────────────────────────────────────
      _simulerRedemarrage();
      expect(elo.nbChevauxSuivis, greaterThan(0),
          reason: 'au redémarrage, les ratings sont RECHARGÉS depuis le disque '
              '— c\'est l\'état réel de production');

      // Relecture du disque, avec les décodeurs de production.
      final regApresRedemarrage = _registreSurDisque();
      expect(regApresRedemarrage, isNotNull,
          reason: 'le registre SURVIT au redémarrage');
      expect(regApresRedemarrage!.entreePourCle(kCleCourse), isNotNull,
          reason: 'la course est retrouvée par sa clé, depuis le disque seul');

      // ── 4. Seconde présentation de LA MÊME COURSE : refus. ──────────────
      final etat2 = await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse,
      );
      await _laisserProgresser();

      final res2 = elo.dernierResultatMiseAJour;
      // ignore: avoid_print
      print('[B2e-1a] op2 → $etat2 | $res2');

      expect(etat2, EtatPersistanceElo.nonTentee,
          reason: '§7 : la seconde présentation est REFUSÉE');
      expect(res2!.motifRefus, MotifRefusApplicationElo.courseDejaJournalisee,
          reason: 'motif exact du refus');
      expect(res2.amorcageEffectue, isFalse,
          reason: 'le registre existait : aucun nouvel amorçage');
      expect(res2.refusee, isTrue);
      expect(res2.protectionEffective, isFalse);

      // ── 5. Le refus n'a RIEN muté : ni RAM, ni disque. ──────────────────
      // ⚠️ `nbChevauxSuivis` vaut 3, PAS 0 : le redémarrage a rechargé les
      //    ratings depuis le disque (état réel de production). Ce qui doit être
      //    prouvé est que ce nombre est INCHANGÉ par le refus, pas qu'il est nul.
      expect(elo.nbChevauxSuivis, disque1.length,
          reason: 'le refus ne crée ni ne retire aucun cheval : la RAM après '
              'refus contient exactement les ratings du disque');
      final disque2 = _ratingsSurDisque();
      expect(disque1.keys.toSet(), disque2.keys.toSet(),
          reason: 'aucune clé de rating ajoutée ou retirée');
      for (final k in disque1.keys) {
        expect(disque2[k]!.rating, disque1[k]!.rating,
            reason: 'le rating de $k est INCHANGÉ par le refus');
        expect(disque2[k]!.nbCourses, disque1[k]!.nbCourses,
            reason: 'nbCourses de $k est INCHANGÉ — aucun second comptage');
      }
      // L'empreinte du disque est identique : preuve globale de non-mutation.
      expect(_empreinteDisque(), reg1.empreinteRatings,
          reason: 'l\'empreinte des ratings sur disque est celle d\'avant la '
              'seconde présentation');
      // Le registre n'a pas reçu de seconde entrée.
      expect(_registreSurDisque()!.entrees.length, 1,
          reason: 'aucune entrée supplémentaire n\'est journalisée');
    });

    test('B2e-1b — deux courses DISTINCTES sont toutes deux appliquées', () async {
      final elo = EloService.instance;

      final etat1 = await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: 'R1C1_01112026',
      );
      await _laisserProgresser();
      expect(etat1, EtatPersistanceElo.persistee);

      final etat2 = await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: 'R1C2_02112026',
      );
      await _laisserProgresser();

      final reg = _registreSurDisque()!;
      // ignore: avoid_print
      print('[B2e-1b] entrées=${reg.entrees.map((e) => e.cle).toList()}');

      expect(etat2, EtatPersistanceElo.persistee,
          reason: 'une course DIFFÉRENTE n\'est pas un doublon');
      expect(reg.entrees.length, 2,
          reason: 'deux entrées distinctes, une par course');
      expect(reg.entrees.map((e) => e.cle).toSet(),
          <String>{'R1C1_01112026', 'R1C2_02112026'});
      expect(reg.entrees.map((e) => e.id).toSet().length, 2,
          reason: 'deux identifiants DIFFÉRENTS : l\'allocation n\'a pas été '
              'réutilisée');
      expect(reg.horloge, greaterThan(0),
          reason: 'l\'horloge progresse à chaque entrée');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2e-2 — AMORÇAGE : CAS A / CAS B, ET REFUS DES REGISTRES DÉGRADÉS
  // ═════════════════════════════════════════════════════════════════════════
  group('B2e-2 — amorçage du registre', () {
    test('B2e-2a — CAS A : stockage vide ⇒ `origine: courante`, aucune entrée '
        'historique inventée', () async {
      final elo = EloService.instance;

      await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse,
      );
      await _laisserProgresser();

      final reg = _registreSurDisque()!;
      expect(reg.origine, OrigineRegistreElo.courante);
      expect(reg.entrees.length, 1,
          reason: 'une seule entrée : celle de la course appliquée. Aucun '
              'historique n\'est fabriqué.');
      expect(reg.entrees.single.type, TypeEntreeRegistre.course);
    });

    test('B2e-2b — CAS B : ratings préexistants SANS registre ⇒ '
        '`historiqueInconnu`, ratings INTACTS', () async {
      final elo = EloService.instance;

      // On sème des ratings comme le ferait une restauration de sauvegarde
      // antérieure au registre. Valeurs volontairement ≠ 1500.
      const seme = <String, double>{
        'CHEVAL_1|TROT_ATTELE': 1712.5,
        'CHEVAL_2|TROT_ATTELE': 1388.25,
      };
      await store.semer(
          kCleElo,
          jsonEncode(<String, dynamic>{
            for (final e in seme.entries)
              e.key: <String, dynamic>{
                'nom': e.key.split('|').first,
                'rating': e.value,
                'nb': 7,
                'var': 12.5,
              },
          }));
      _simulerRedemarrage();

      expect(store.contient(kCleRegistre), isFalse,
          reason: 'postulat : le registre est ABSENT');
      expect(elo.nbChevauxSuivis, 2, reason: 'les ratings sont chargés');

      final etat = await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse,
      );
      await _laisserProgresser();

      final res = elo.dernierResultatMiseAJour;
      // ignore: avoid_print
      print('[B2e-2b] → $etat | $res');

      expect(etat, EtatPersistanceElo.persistee);
      expect(res!.amorcageEffectue, isTrue,
          reason: '§6 : registre absent ⇒ amorçage');
      expect(res.origineAvant, OrigineRegistreElo.historiqueInconnu,
          reason: 'CAS B : des ratings existent, l\'historique est INCONNU — '
              'et ce n\'est PAS un motif de refus (option 1 arbitrée)');
      expect(res.motifRefus, isNull,
          reason: '`historiqueInconnu` n\'interdit JAMAIS une nouvelle '
              'application');

      final reg = _registreSurDisque()!;
      expect(reg.origine, OrigineRegistreElo.historiqueInconnu);
      expect(reg.entrees.length, 1,
          reason: 'aucune entrée rétroactive n\'est inventée pour les ratings '
              'antérieurs');
      expect(reg.entrees.single.cle, kCleCourse);
    });

    test('B2e-2c — un registre DIVERGENT est REFUSÉ et n\'est NI réparé, NI '
        'remplacé', () async {
      final elo = EloService.instance;

      // Ratings sur le disque …
      await store.semer(
          kCleElo,
          jsonEncode(<String, dynamic>{
            'X|PLAT': <String, dynamic>{
              'nom': 'X',
              'rating': 1600.0,
              'nb': 3,
              'var': 1.0,
            },
          }));
      // … et un registre dont l'empreinte NE CORRESPOND PAS.
      final divergent = RegistreEloV3.vierge(empreinteRatings: 'deadbeefdeadbeef')
          .encoder();
      await store.semer(kCleRegistre, divergent);
      final avant = store.lire(kCleRegistre);
      _simulerRedemarrage();

      final etat = await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse,
      );
      await _laisserProgresser();

      final res = elo.dernierResultatMiseAJour;
      // ignore: avoid_print
      print('[B2e-2c] → $etat | $res');

      expect(etat, EtatPersistanceElo.nonTentee);
      expect(res!.motifRefus, MotifRefusApplicationElo.registreNonCoherent,
          reason: 'un registre divergent est refusé, jamais réparé');
      expect(res.amorcageEffectue, isFalse,
          reason: '§4/§11 : un registre PRÉSENT mais non cohérent n\'est JAMAIS '
              'remplacé par un amorçage');
      expect(store.lire(kCleRegistre), avant,
          reason: 'le registre sur le disque est BYTE POUR BYTE inchangé');
      expect(_ratingsSurDisque().length, 1,
          reason: 'les ratings existants ne sont pas modifiés');
      expect(store.lire(kCleElo), isNotNull);
      expect(elo.nbChevauxSuivis, 1,
          reason: 'aucune mutation RAM : le seul rating est celui restauré');
    });

    test('B2e-2d — un registre CORROMPU est REFUSÉ et reste tel quel', () async {
      final elo = EloService.instance;

      await store.semer(kCleRegistre, '{ceci n\'est pas du JSON');
      final avant = store.lire(kCleRegistre);
      _simulerRedemarrage();

      final etat = await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse,
      );
      await _laisserProgresser();

      expect(etat, EtatPersistanceElo.nonTentee);
      expect(elo.dernierResultatMiseAJour!.motifRefus,
          MotifRefusApplicationElo.registreNonCoherent);
      expect(store.lire(kCleRegistre), avant,
          reason: 'ni suppression, ni réécriture : le contenu corrompu est '
              'conservé pour l\'audit');
      expect(elo.nbChevauxSuivis, 0, reason: 'aucune mutation');
    });

    test('B2e-2e — un registre de SCHEMA INCOMPATIBLE est REFUSÉ et reste tel '
        'quel', () async {
      final elo = EloService.instance;

      final incompatible = jsonEncode(<String, dynamic>{
        'schema': 99, // schéma inconnu
        'version': 1,
        'horloge': 0,
        'empreinteRatings': '0000000000000000',
        'origine': 'courante',
        'entrees': <dynamic>[],
      });
      await store.semer(kCleRegistre, incompatible);
      _simulerRedemarrage();

      final etat = await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse,
      );
      await _laisserProgresser();

      expect(etat, EtatPersistanceElo.nonTentee);
      expect(elo.dernierResultatMiseAJour!.motifRefus,
          MotifRefusApplicationElo.registreNonCoherent);
      expect(store.lire(kCleRegistre), incompatible,
          reason: 'aucune migration automatique n\'est entreprise');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2e-3 — ÉTATS INCERTAINS : TOUS BLOQUANTS, AUCUNE RÉPARATION
  // ═════════════════════════════════════════════════════════════════════════
  group('B2e-3 — états incertains bloquants', () {
    /// Sème un registre COHÉRENT (empreinte calculée depuis le disque) portant
    /// une entrée pour [kCleCourse] à l'étape [etape].
    Future<void> semerEntreeIncertaise(EtapeEntreeRegistre etape) async {
      const ratings = <String, double>{'CHEVAL_1|TROT_ATTELE': 1520.0};
      await store.semer(
          kCleElo,
          jsonEncode(<String, dynamic>{
            for (final e in ratings.entries)
              e.key: <String, dynamic>{
                'nom': e.key.split('|').first,
                'rating': e.value,
                'nb': 2,
                'var': 3.0,
              },
          }));
      // L'empreinte doit être celle des ratings RÉELLEMENT semés, sinon le
      // registre serait `divergent` et le test ne prouverait pas ce qu'il dit.
      final empreinte = empreinte64Ratings(<String, EloScore>{
        for (final e in ratings.entries)
          e.key: EloScore(
            nomCheval: e.key.split('|').first,
            rating: e.value,
            nbCourses: 2,
            variationMois: 3.0,
          ),
      });
      final entree = EntreeRegistreElo(
        id: 0,
        type: TypeEntreeRegistre.course,
        cle: kCleCourse,
        numR: 1,
        numC: 1,
        date: '2026-11-01',
        discipline: 'TROT_ATTELE',
        etape: etape,
        // ⚠️ LES INVARIANTS DU MODÈLE SONT STRICTS — mesuré, `fromJson` lève
        //    (`elo_registre_v3.dart` l.391) :
        //      `intention`    ⇒ issue == null        ET tsFinal == null
        //      `appliquee`    ⇒ issue == persistee   ET tsFinal != null
        //      `nonConfirmee` ⇒ issue ∈ {refusee, echouee} ET tsFinal == null
        //    Une entrée `appliquee` avec `issue` nulle fait LEVER le décodeur :
        //    le registre serait alors lu comme « corrompu » et le test
        //    mesurerait un autre refus que celui qu'il annonce.
        issue: switch (etape) {
          EtapeEntreeRegistre.appliquee => IssueEcritureElo.persistee,
          EtapeEntreeRegistre.nonConfirmee => IssueEcritureElo.refusee,
          EtapeEntreeRegistre.intention => null,
        },
        tsIntention: 1762000000000,
        tsFinal:
            etape == EtapeEntreeRegistre.appliquee ? 1762000000001 : null,
        empreinteAvant: empreinte,
        empreinteApres: empreinte,
      );
      final reg = RegistreEloV3.vierge(empreinteRatings: empreinte)
          .copyWith(horloge: 0, entrees: <EntreeRegistreElo>[entree]);
      await store.semer(kCleRegistre, reg.encoder());
      _simulerRedemarrage();
    }

    test('B2e-3a — entrée `intention` (issue inconnue) ⇒ refus, registre '
        'INTACT', () async {
      await semerEntreeIncertaise(EtapeEntreeRegistre.intention);
      final avant = store.lire(kCleRegistre);

      final etat = await EloService.instance.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse,
      );
      await _laisserProgresser();

      final res = EloService.instance.dernierResultatMiseAJour;
      // ignore: avoid_print
      print('[B2e-3a] → $etat | $res');

      expect(etat, EtatPersistanceElo.nonTentee);
      expect(res!.motifRefus, MotifRefusApplicationElo.courseDejaJournalisee,
          reason: 'une intention dont l\'issue est INCONNUE bloque');
      expect(store.lire(kCleRegistre), avant,
          reason: 'l\'entrée incertaine n\'est NI supprimée, NI réparée');
      expect(EloService.instance.nbChevauxSuivis, 1,
          reason: 'aucune mutation : le rating restauré reste seul');
    });

    test('B2e-3b — entrée `nonConfirmee` (issue refusée) ⇒ refus, '
        'registre INTACT', () async {
      await semerEntreeIncertaise(EtapeEntreeRegistre.nonConfirmee);
      final avant = store.lire(kCleRegistre);

      final etat = await EloService.instance.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse,
      );
      await _laisserProgresser();

      expect(etat, EtatPersistanceElo.nonTentee);
      expect(EloService.instance.dernierResultatMiseAJour!.motifRefus,
          MotifRefusApplicationElo.courseDejaJournalisee,
          reason: 'ni preuve d\'écriture ni preuve d\'absence ⇒ bloque');
      expect(store.lire(kCleRegistre), avant);
    });

    test('B2e-3c — entrée `appliquee` préexistante ⇒ refus', () async {
      await semerEntreeIncertaise(EtapeEntreeRegistre.appliquee);
      final avant = store.lire(kCleRegistre);

      final etat = await EloService.instance.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse,
      );
      await _laisserProgresser();

      expect(etat, EtatPersistanceElo.nonTentee);
      expect(EloService.instance.dernierResultatMiseAJour!.motifRefus,
          MotifRefusApplicationElo.courseDejaJournalisee);
      expect(store.lire(kCleRegistre), avant);
    });

    test('B2e-3d — une entrée `course` pour une AUTRE clé ne bloque pas',
        () async {
      await semerEntreeIncertaise(EtapeEntreeRegistre.appliquee);

      final etat = await EloService.instance.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: 'R1C9_05112026',
      );
      await _laisserProgresser();

      final reg = _registreSurDisque()!;
      final res = EloService.instance.dernierResultatMiseAJour;
      // ignore: avoid_print
      print('[B2e-3d] → $etat | $res | entrées=${reg.entrees.length}');

      expect(etat, EtatPersistanceElo.persistee,
          reason: 'le blocage porte sur LA clé, pas sur le registre entier');
      expect(reg.entrees.length, 2);
      expect(reg.entreePourCle(kCleCourse), isNotNull,
          reason: 'l\'entrée préexistante est PRÉSERVÉE');
      expect(reg.entreePourCle('R1C9_05112026'), isNotNull);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2e-4 — TRANSACTIONNEL : L'INTENTION PRÉCÈDE LA MUTATION
  // ═════════════════════════════════════════════════════════════════════════
  group('B2e-4 — intention persistée avant mutation', () {
    test('B2e-4a — échec d\'écriture du registre ⇒ AUCUNE mutation, AUCUNE '
        'sauvegarde de ratings', () async {
      final elo = EloService.instance;
      final index = store.journal.length;
      store.echecsEcriture.add('flutter.$kCleRegistre');

      final etat = await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse,
      );
      await _laisserProgresser();

      final res = elo.dernierResultatMiseAJour;
      // ignore: avoid_print
      print('[B2e-4a] → $etat | $res | refusées='
          '${store.clesRefuseesDepuis(index)}');

      expect(etat, EtatPersistanceElo.nonTentee,
          reason: '§5 : sans intention persistée, rien n\'est tenté');
      expect(res!.motifRefus, MotifRefusApplicationElo.amorcageNonPersiste,
          reason: 'l\'amorçage échoue avant même l\'intention — l\'ordre '
              'amorçage → intention est respecté');
      expect(store.clesRefuseesDepuis(index).contains('flutter.$kCleRegistre'),
          isTrue,
          reason: 'TÉMOIN : l\'écriture du registre a bien été REFUSÉE');
      expect(elo.nbChevauxSuivis, 0,
          reason: 'AUCUNE mutation RAM : `_ratings` reste vide');
      // Aucune écriture de ratings n'a été TENTÉE.
      expect(store.clesEcritesDepuis(index).contains(kJournalElo), isFalse,
          reason: 'aucun `setString` sur les ratings : la sauvegarde n\'a pas '
              'été appelée');
      expect(store.contient(kCleElo), isFalse,
          reason: 'le disque ne porte aucun rating');
    });

    test('B2e-4b — exception à l\'écriture du registre ⇒ AUCUNE mutation',
        () async {
      final elo = EloService.instance;
      store.exceptionsEcriture.add('flutter.$kCleRegistre');

      final etat = await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse,
      );
      await _laisserProgresser();

      expect(etat, EtatPersistanceElo.nonTentee);
      expect(elo.dernierResultatMiseAJour!.motifRefus,
          MotifRefusApplicationElo.amorcageNonPersiste);
      expect(elo.nbChevauxSuivis, 0, reason: 'aucune mutation malgré '
          'l\'exception');
      expect(store.contient(kCleElo), isFalse);
    });

    test('B2e-4c — après un échec d\'intention, une NOUVELLE tentative '
        'aboutit (aucun état bloquant fantôme)', () async {
      final elo = EloService.instance;
      store.echecsEcriture.add('flutter.$kCleRegistre');
      await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse,
      );
      await _laisserProgresser();
      expect(store.contient(kCleRegistre), isFalse,
          reason: 'aucune entrée fantôme n\'a été écrite');

      store.echecsEcriture.clear();
      final etat = await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse,
      );
      await _laisserProgresser();

      expect(etat, EtatPersistanceElo.persistee,
          reason: 'l\'échec précédent n\'a laissé AUCUN verrou');
      expect(elo.dernierResultatMiseAJour!.journalisationConfirmee, isTrue);
      expect(_registreSurDisque()!.entrees.length, 1);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2e-5 — EMPREINTES : LA PROMESSE « APRÈS » EST EXACTE
  // ═════════════════════════════════════════════════════════════════════════
  group('B2e-5 — empreintes', () {
    test('B2e-5a — l\'empreinte `avant` de l\'entrée est celle du disque AVANT '
        'l\'opération', () async {
      final elo = EloService.instance;
      final empreinteAvant = _empreinteDisque();
      expect(empreinteAvant, empreinte64Ratings(<String, EloScore>{}),
          reason: 'TÉMOIN : l\'empreinte d\'une map vide est bien un calcul, '
              'pas `null`');

      await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse,
      );
      await _laisserProgresser();

      final entree = _registreSurDisque()!.entrees.single;
      expect(entree.empreinteAvant, empreinteAvant,
          reason: 'l\'empreinte « avant » est EXACTEMENT celle du disque avant '
              'mutation');
    });

    test('B2e-5b — l\'empreinte `apres` de l\'entrée est EXACTEMENT celle des '
        'ratings écrits', () async {
      final elo = EloService.instance;

      await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse,
      );
      await _laisserProgresser();

      final entree = _registreSurDisque()!.entrees.single;
      expect(entree.empreinteApres, _empreinteDisque(),
          reason: 'la promesse calculée AVANT la mutation coïncide avec le '
              'disque APRÈS : c\'est ce qui rend la vérification non '
              'circulaire');
      expect(entree.empreinteApres, isNot(entree.empreinteAvant));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2e-6 — CONCURRENCE ET RESET : MÉCANISMES PRÉSERVÉS
  // ═════════════════════════════════════════════════════════════════════════
  group('B2e-6 — concurrence et reset préservés', () {
    test('B2e-6a — deux applications SIMULTANÉES de la même course : une seule '
        'aboutit', () async {
      final elo = EloService.instance;

      final f1 = elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse,
      );
      final f2 = elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse,
      );

      final e1 = await f1;
      final e2 = await f2;
      await _laisserProgresser();

      final reg = _registreSurDisque()!;
      // ignore: avoid_print
      print('[B2e-6a] e1=$e1 | e2=$e2 | entrées=${reg.entrees.length} | '
          'horloge=${reg.horloge}');

      expect(<EtatPersistanceElo>{e1, e2}.length, 2,
          reason: 'la FIFO sérialise : les deux issues sont observables');
      expect(
          <EtatPersistanceElo>{e1, e2},
          <EtatPersistanceElo>{
            EtatPersistanceElo.persistee,
            EtatPersistanceElo.nonTentee
          },
          reason: 'une seule application aboutit, la seconde est refusée — '
              'c\'est la protection anti-double-application en conditions '
              'concurrentes');
      expect(reg.entrees.length, 1,
          reason: 'UNE SEULE entrée de journal, et non deux');
      expect(reg.horloge, 1,
          reason: 'l\'horloge n\'a progressé que d\'un cran : aucune entrée '
              'n\'a été écrite deux fois');
    });

    test('B2e-6b — un reset pendant l\'opération : aucune résurrection du '
        'registre', () async {
      final elo = EloService.instance;

      final entree = store.armerSuspension(kJournalElo);
      final f1 = elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse,
      );
      await entree;

      final reset = elo.executerResetComplet(() async {
        await store.supprimer(kCleElo);
        await store.supprimer(kCleTs);
        await store.supprimer(kCleRegistre);
      });

      store.libererSuspension();
      await reset;
      final etat = await f1;
      await _laisserProgresser();

      // ignore: avoid_print
      print('[B2e-6b] → $etat | registre=${store.contient(kCleRegistre)}');

      expect(store.contient(kCleRegistre), isFalse,
          reason: 'SCÉNARIO V29-A : une écriture du registre ne doit JAMAIS '
              'recréer la clé après son effacement');
      expect(elo.nbEcrituresPersistantesEnCours, 0,
          reason: 'le drain a bien vidé le registre des écritures en vol');
      expect(elo.nbChevauxSuivis, 0, reason: 'la RAM est vidée par le reset');
      // ⚠️ NE PAS asserter `nbRefusParReset > 0` : l'issue dépend de
      //    l'ENTRELACEMENT. Mesuré ici : l'opération avait déjà achevé ses deux
      //    écritures avant que le reset n'atteigne le drain, donc `persistee`
      //    et AUCUN refus n'est compté. Ce qui doit être prouvé est
      //    l'ABSENCE DE RÉSURRECTION, pas le passage par un compteur.
      expect(<String>['persistee', 'abandonneeParReset'], contains(etat.name),
          reason: 'l\'issue est soit nominale (écriture déjà achevée), soit un '
              'abandon — jamais autre chose');
      // Le second point du contrat de reset : après lui, une NOUVELLE opération
      // est traitée normalement, avec un registre ré-amorcé.
      final etatApres = await elo.mettreAJourApresArrivee(
        arrivee: <int>[1, 2],
        partants: <ZtPartant>[_partant(1), _partant(2)],
        discipline: kDisc,
        courseKey: 'R1C5_05112026',
      );
      await _laisserProgresser();
      // ignore: avoid_print
      print('[B2e-6b] après reset → $etatApres | '
          'registre=${store.contient(kCleRegistre)}');
      expect(etatApres, EtatPersistanceElo.persistee,
          reason: 'la barrière est bien relâchée : le service reste utilisable');
      expect(store.contient(kCleRegistre), isTrue,
          reason: 'le registre est ré-amorcé pour l\'opération postérieure');
    });

    test('B2e-6c — les compteurs B2-a gardent leur sémantique', () async {
      final elo = EloService.instance;
      final refusResetAvant = elo.nbRefusParReset;
      final refusGenAvant = elo.nbRefusParGeneration;

      await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse,
      );
      await _laisserProgresser();

      expect(elo.nbEcrituresEnCours, 0);
      expect(elo.nbEcrituresPersistantesEnCours, 0);
      expect(elo.nbRefusParReset, refusResetAvant);
      expect(elo.nbRefusParGeneration, refusGenAvant);
      expect(elo.nbPersistees, greaterThan(0),
          reason: 'les ratings ont bien été comptés comme persistés');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2e-8 — ★ DÉFAUT DE RÉSURRECTION DU REGISTRE : REPRODUCTION ET PREUVE
  //
  //  DÉFAUT MESURÉ AVANT CORRECTIF : une opération NÉE PENDANT un reset capturait
  //  la génération DÉJÀ incrémentée par ce reset. Le contrôle de génération la
  //  laissait donc passer, et `_persisterRegistre` — qui n'avait AUCUN équivalent
  //  du contrôle 1 de `_sauvegarder()` — écrivait `elo_registre_v3` APRÈS le
  //  `remove` du reset : la clé était RECRÉÉE.
  //
  //  Ces tests reproduisent le scénario initial et bornent la correction.
  //  Ils ne remplacent aucun test existant : ils COUVRENT le défaut.
  // ═════════════════════════════════════════════════════════════════════════
  group('B2e-8 — non-résurrection du registre pendant un reset', () {
    test('B2e-8a — reset PENDANT la préparation d\'une intention : le registre '
        'n\'est pas recréé', () async {
      final elo = EloService.instance;

      // Le reset est suspendu DANS sa suppression : toute opération née à ce
      // moment-là naît « pendant le reset ».
      final entree = Completer<void>();
      final liberation = Completer<void>();
      final reset = elo.executerResetComplet(() async {
        await store.supprimer(kCleElo);
        await store.supprimer(kCleTs);
        await store.supprimer(kCleRegistre);
        if (!entree.isCompleted) entree.complete();
        await liberation.future;
      });
      await entree.future;

      expect(store.contient(kCleRegistre), isFalse,
          reason: 'TÉMOIN : le reset a bien effacé le registre');

      final indexPendant = store.journal.length;
      final etat = await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse,
      );
      await _laisserProgresser();

      final ecrituresRegistre = store.journal
          .skip(indexPendant)
          .where((e) => e.contains(kCleRegistre) && e.startsWith('SET'))
          .toList();

      // ignore: avoid_print
      print('[B2e-8a] etat=${etat.name} | registre='
          '${store.contient(kCleRegistre)} | ecritures=$ecrituresRegistre');

      // ⚠️ MESURE, ET NON SUPPOSITION : le correctif SAUTE l'écriture physique
      //    du registre quand `_resetEnCours` est vrai, mais ACQUITTE l'appel.
      //    L'état final reste décidé par `_sauvegarder()` (contrôle 1), pour que
      //    les contrats T8 / V29-I / V29-H restent intacts.
      expect(ecrituresRegistre, isEmpty,
          reason: 'CORRECTION : AUCUNE écriture du registre n\'est tentée '
              'pendant le reset — c\'est la cause exacte de la résurrection');
      expect(store.contient(kCleRegistre), isFalse,
          reason: 'CORRECTION : la clé n\'est pas recréée par l\'opération née '
              'pendant l\'effacement');

      liberation.complete();
      await reset;

      expect(store.contient(kCleRegistre), isFalse,
          reason: 'APRÈS la fin du reset, le registre ne réapparaît pas : '
              'aucune écriture tardive ne l\'a ressuscité');
      expect(elo.nbChevauxSuivis, 0, reason: 'la RAM est vidée par le reset');
      expect(elo.nbEcrituresPersistantesEnCours, 0,
          reason: 'le drain a tout vu : aucune écriture persistante en vol');
    });

    test('B2e-8b — reset pendant une écriture ASYNCHRONE du registre : la clé '
        'n\'est pas ressuscitée', () async {
      final elo = EloService.instance;

      // Première opération : elle AMORCE puis journalise le registre.
      await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse1,
      );
      await _laisserProgresser();
      expect(store.contient(kCleRegistre), isTrue,
          reason: 'TÉMOIN : le registre existe avant le reset');

      // Seconde opération, suspendue PENDANT l'écriture des ratings : à ce
      // stade elle a déjà écrit son intention et muté la RAM.
      final entree = store.armerSuspension(kJournalElo);
      final f = elo.mettreAJourApresArrivee(
        arrivee: <int>[1, 2],
        partants: <ZtPartant>[_partant(1), _partant(2)],
        discipline: kDisc,
        courseKey: kCleCourse2,
      );
      await entree;

      final reset = elo.executerResetComplet(() async {
        await store.supprimer(kCleElo);
        await store.supprimer(kCleTs);
        await store.supprimer(kCleRegistre);
      });

      store.libererSuspension();
      await reset;
      await f;
      await _laisserProgresser();

      // ignore: avoid_print
      print('[B2e-8b] registre=${store.contient(kCleRegistre)} | '
          'ratings=${store.contient(kCleElo)} | RAM=${elo.nbChevauxSuivis}');

      expect(store.contient(kCleRegistre), isFalse,
          reason: 'CORRECTION : ni l\'intention déjà écrite, ni la '
              'finalisation ne recréent la clé après son effacement');
      expect(store.contient(kCleElo), isFalse,
          reason: 'CORRECTION : les ratings ne sont pas ressuscités non plus');
      expect(elo.nbChevauxSuivis, 0,
          reason: 'CORRECTION : la RAM reste vide après le reset');
      expect(elo.nbEcrituresPersistantesEnCours, 0,
          reason: 'le drain a attendu toutes les écritures engagées');
    });

    test('B2e-8c — après le reset, la PREMIÈRE nouvelle course est autorisée '
        'et le registre est ré-amorcé', () async {
      final elo = EloService.instance;

      await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse1,
      );
      await _laisserProgresser();

      await elo.executerResetComplet(() async {
        await store.supprimer(kCleElo);
        await store.supprimer(kCleTs);
        await store.supprimer(kCleRegistre);
      });

      expect(store.contient(kCleRegistre), isFalse, reason: 'reset effectué');
      expect(elo.nbChevauxSuivis, 0, reason: 'RAM vidée');

      final etat = await elo.mettreAJourApresArrivee(
        arrivee: <int>[1, 2],
        partants: <ZtPartant>[_partant(1), _partant(2)],
        discipline: kDisc,
        courseKey: kCleCourse2,
      );
      await _laisserProgresser();

      // ignore: avoid_print
      print('[B2e-8c] après reset : etat=${etat.name} | '
          'registre=${store.contient(kCleRegistre)}');

      expect(etat, EtatPersistanceElo.persistee,
          reason: 'la barrière est relâchée : le service reste opérationnel');
      expect(store.contient(kCleRegistre), isTrue,
          reason: 'le registre est ré-amorcé pour cette nouvelle course');
      expect(elo.nbChevauxSuivis, greaterThan(0),
          reason: 'les ratings de la nouvelle course sont bien appliqués');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2e-7 — IDENTITÉ INEXPLOITABLE : REFUS, AUCUNE MUTATION, AUCUNE ÉCRITURE
  // ═════════════════════════════════════════════════════════════════════════
  group('B2e-7 — identité inexploitable', () {
    test('B2e-7a — `courseKey` absente ⇒ refus explicite, aucun accès disque',
        () async {
      final elo = EloService.instance;
      final index = store.journal.length;

      final etat = await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
      );
      await _laisserProgresser();

      expect(etat, EtatPersistanceElo.nonTentee);
      expect(elo.dernierResultatMiseAJour!.motifRefus,
          MotifRefusApplicationElo.identiteNonExploitable);
      expect(elo.nbChevauxSuivis, 0);
      expect(store.clesEcritesDepuis(index), isEmpty,
          reason: 'AUCUNE écriture : le refus est rendu avant tout accès au '
              'stockage');
      expect(store.contient(kCleRegistre), isFalse,
          reason: 'aucun registre n\'est créé par une opération refusée');
    });

    test('B2e-7b — date POSTÉRIEURE au lendemain ⇒ refus `datePosterieure`',
        () async {
      final elo = EloService.instance;

      // Une course ne peut pas être déjà disputée si sa date est dans le futur
      // lointain. La borne est le LENDEMAIN, pour tolérer un fuseau en avance.
      final futur = DateTime.now().add(const Duration(days: 400));
      final cle = 'R1C1_'
          '${futur.day.toString().padLeft(2, '0')}'
          '${futur.month.toString().padLeft(2, '0')}'
          '${futur.year}';

      final etat = await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: cle,
      );
      await _laisserProgresser();

      final res = elo.dernierResultatMiseAJour;
      // ignore: avoid_print
      print('[B2e-7b] clé=$cle → $etat | $res');

      expect(etat, EtatPersistanceElo.nonTentee);
      expect(res!.motifRefus, MotifRefusApplicationElo.datePosterieure,
          reason: 'la garde d\'ANTÉRIORITÉ s\'applique');
      expect(res.amorcageEffectue, isTrue,
          reason: 'l\'amorçage a eu lieu : le refus porte sur la DATE, pas sur '
              'le registre — ce qui prouve que les deux contrôles sont '
              'indépendants');
      expect(elo.nbChevauxSuivis, 0, reason: 'aucune mutation');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2e-9 — ★ A-2 : RÉSURRECTION POST-BARRIÈRE
  //
  //  DÉFAUT AUDITÉ (arbitrage A-2) : une opération NÉE PENDANT un reset
  //  capture la génération DÉJÀ incrémentée par ce reset. Le contrôle G est donc
  //  inerte pour elle, et `_resetEnCours` était sa SEULE protection. Si elle est
  //  suspendue sur une attente de `SharedPreferences.getInstance()` qui se
  //  résout APRÈS la réouverture de la barrière, cette protection est retombée :
  //  l'écriture atteint le disque APRÈS `supprimerLesCles()` et le drain ne l'a
  //  jamais vue (elle n'était pas encore au registre).
  //
  //  Ces tests sont DÉTERMINISTES : la suspension est armée sur
  //  `getAllWithParameters`, seul point d'entrée de `getInstance()` ; le reset
  //  est mené à son TERME pendant la suspension ; la reprise a donc lieu avec
  //  `_resetEnCours == false`.
  // ═════════════════════════════════════════════════════════════════════════
  group('B2e-9 — A-2 : opération née pendant le reset, reprise après la barrière',
      () {
    test('B2e-9a — A-2 REPRODUIT : aucune résurrection des ratings ni du '
        'registre après réouverture de la barrière', () async {
      final elo = EloService.instance;

      // ── On force un passage réel par `getInstance()` : sans cela, le cache
      //    statique de `SharedPreferences` est chaud et l'attente n'existe pas.
      SharedPreferences.resetStatic();
      final entreeGetAll = store.armerSuspensionGetAll();

      // ── Reset retenu dans son EFFACEMENT : la barrière reste FERMÉE tant que
      //    `liberation` n'est pas complétée, et l'opération ci-dessous naît donc
      //    PENDANT le reset. La première `getInstance()` de l'opération sera
      //    suspendue APRÈS le début du reset.
      final entreeEffacement = Completer<void>();
      final liberation = Completer<void>();
      final reset = elo.executerResetComplet(() async {
        // Effacement réel des trois clés ELO, comme le fait `BackupService`.
        await store.supprimer(kCleElo);
        await store.supprimer(kCleTs);
        await store.supprimer(kCleRegistre);
        if (!entreeEffacement.isCompleted) entreeEffacement.complete();
        await liberation.future;
      });
      await entreeEffacement.future;

      expect(store.contient(kCleRegistre), isFalse,
          reason: 'TÉMOIN : le reset a effacé le registre');
      expect(store.contient(kCleElo), isFalse,
          reason: 'TÉMOIN : le reset a effacé les ratings');

      final generationPendant = elo.generationCache;

      // ── L'opération NAGE PENDANT le reset. Elle capture la génération DÉJÀ
      //    incrémentée : le contrôle G sera donc inerte pour elle.
      final maj = elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse1,
      );
      final suspendue = await _attendreEntreeOuFin(entreeGetAll, maj);
      expect(suspendue, isTrue,
          reason: 'TÉMOIN DE PRÉPARATION : l\'opération est retenue DANS '
              '`SharedPreferences.getInstance()`');
      expect(elo.generationCache, generationPendant,
          reason: 'FAIT : la génération capturée par l\'opération est celle '
              'DÉJÀ incrémentée par le reset — le contrôle G la laisse passer');

      // ── Le reset va À SON TERME : la barrière se referme (false). ────────
      liberation.complete();
      await reset;
      expect(elo.nbChevauxSuivis, 0, reason: 'TÉMOIN : le `finally` a vidé la RAM');

      // ── REPRISE : l'opération se débloque alors que `_resetEnCours` est
      //    redevenu `false`. C'est exactement la fenêtre décrite par A-2.
      final indexReprise = store.journal.length;
      store.libererGetAll();
      final etat = await maj;
      await _laisserProgresser();

      final ecritures = store.journal
          .skip(indexReprise)
          .where((e) => e.startsWith('SET-OK '))
          .toList();

      // ignore: avoid_print
      print('[B2e-9a] etat=${etat.name} | '
          'ratings=${store.contient(kCleElo)} | '
          'registre=${store.contient(kCleRegistre)} | '
          'RAM=${elo.nbChevauxSuivis} | ecritures=$ecritures');

      // ── Les TROIS garanties exigées par l'arbitrage A-2. ─────────────────
      expect(store.contient(kCleElo), isFalse,
          reason: 'A-2 : les ratings ne sont PAS ressuscités par une opération '
              'née pendant le reset');
      expect(store.contient(kCleRegistre), isFalse,
          reason: 'A-2 : le registre n\'est PAS ressuscité non plus');
      expect(elo.nbChevauxSuivis, 0,
          reason: 'A-2 : la RAM de la génération effacée n\'est pas repeuplée');
      // ⚠️ CONTRAT RÉEL, PLUS STRICT QUE L'ASSERTION INITIALE : une opération
      //    née pendant un reset ACHEVÉ est REFUSÉE explicitement (`nonTentee` +
      //    motif), et non plus laissée filer jusqu'au contrôle 1. `nonTentee`
      //    est ici employé au sens exact que le fichier lui donne partout
      //    ailleurs (l.663, 693, 725…) : « rien n'a été tenté ».
      expect(etat, EtatPersistanceElo.nonTentee,
          reason: 'A-2 : l\'opération est REFUSÉE, pas appliquée');
      final res = elo.dernierResultatMiseAJour;
      expect(res, isNotNull,
          reason: 'A-2 : le refus est PUBLIÉ, jamais silencieux');
      expect(res!.refusee, isTrue,
          reason: 'A-2 : un motif de refus est renseigné');
      expect(res.ratingsPersistes, isFalse,
          reason: 'A-2 : aucun rating n\'est déclaré persisté');
      expect(res.protectionEffective, isFalse,
          reason: 'A-2 : aucune protection ELO n\'est revendiquée');
      expect(res.journalisationConfirmee, isFalse,
          reason: 'A-2 : aucune entrée n\'est journalisée comme appliquée');
    });

    test('B2e-9b — A-2 : aucune écriture n\'est même TENTÉE après la barrière',
        () async {
      final elo = EloService.instance;

      SharedPreferences.resetStatic();
      final entreeGetAll = store.armerSuspensionGetAll();

      final entreeEffacement = Completer<void>();
      final liberation = Completer<void>();
      final reset = elo.executerResetComplet(() async {
        await store.supprimer(kCleElo);
        await store.supprimer(kCleTs);
        await store.supprimer(kCleRegistre);
        if (!entreeEffacement.isCompleted) entreeEffacement.complete();
        await liberation.future;
      });
      await entreeEffacement.future;

      final maj = elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse1,
      );
      await _attendreEntreeOuFin(entreeGetAll, maj);

      liberation.complete();
      await reset;

      final indexReprise = store.journal.length;
      store.libererGetAll();
      await maj;
      await _laisserProgresser();

      final ecrituresApres = store.journal.skip(indexReprise).toList();

      // ignore: avoid_print
      print('[B2e-9b] ecritures après reprise=$ecrituresApres');

      expect(
          ecrituresApres.where((e) => e.startsWith('SET-ENTREE ')), isEmpty,
          reason: 'A-2 : AUCUNE écriture n\'est engagée après la barrière — '
              'ni ratings, ni registre, ni témoin');
    });

    test('B2e-9e — opération née AVANT le reset : contrat historique préservé '
        '(`abandonneeParReset`, `nbRefusParReset` +1)', () async {
      final elo = EloService.instance;

      // ── État de départ : ratings et registre présents sur le disque. ─────
      await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse1,
      );
      await _laisserProgresser();
      expect(store.contient(kCleElo), isTrue, reason: 'TÉMOIN : disque peuplé');

      // ── L'opération NAÎT AVANT le reset, puis est suspendue DANS son
      //    écriture des ratings : elle n'est donc pas encore au registre des
      //    écritures persistantes quand le reset démarre.
      SharedPreferences.resetStatic();
      final entreeGetAll = store.armerSuspensionGetAll();
      final refusResetAvant = elo.nbRefusParReset;

      final maj = elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse2,
      );
      final suspendue = await _attendreEntreeOuFin(entreeGetAll, maj);
      expect(suspendue, isTrue,
          reason: 'TÉMOIN DE PRÉPARATION : opération retenue dans '
              '`getInstance()`');

      // ── Le reset court et se TERMINE pendant la suspension. ──────────────
      await elo.executerResetComplet(() async {
        await store.supprimer(kCleElo);
        await store.supprimer(kCleTs);
        await store.supprimer(kCleRegistre);
      });
      expect(store.contient(kCleElo), isFalse, reason: 'TÉMOIN : disque effacé');

      // ── Reprise APRÈS fermeture de la barrière. ─────────────────────────
      final indexReprise = store.journal.length;
      store.libererGetAll();
      final etat = await maj;
      await _laisserProgresser();

      final ecritures = store.journal
          .skip(indexReprise)
          .where((e) => e.startsWith('SET-OK '))
          .toList();
      final deltaReset = elo.nbRefusParReset - refusResetAvant;

      // ignore: avoid_print
      print('[B2e-9e] etat=${etat.name} | deltaReset=$deltaReset | '
          'ratings=${store.contient(kCleElo)} | '
          'registre=${store.contient(kCleRegistre)} | ecritures=$ecritures');

      // ── Le contrôle de GÉNÉRATION historique doit faire son travail. ─────
      expect(etat, EtatPersistanceElo.abandonneeParReset,
          reason: 'CONTRÔLE 2 : une opération née AVANT le reset est '
              'abandonnée par la génération — contrat V29-G préservé');
      expect(store.contient(kCleElo), isFalse,
          reason: 'aucune résurrection des ratings');
      expect(store.contient(kCleRegistre), isFalse,
          reason: 'aucune résurrection du registre');
      expect(elo.nbChevauxSuivis, 0, reason: 'la RAM reste vide');
      expect(ecritures, isEmpty,
          reason: 'aucune écriture n\'est tentée après la barrière');
    });

    test('B2e-9c — TÉMOIN NÉGATIF : hors reset, la MÊME opération écrit '
        'normalement', () async {
      final elo = EloService.instance;

      // Aucun reset : la barrière n\'a jamais été fermée. Le service doit
      // fonctionner exactement comme avant B2-e.
      final etat = await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse1,
      );
      await _laisserProgresser();

      // ignore: avoid_print
      print('[B2e-9c] etat=${etat.name} | '
          'ratings=${store.contient(kCleElo)} | '
          'registre=${store.contient(kCleRegistre)}');

      expect(etat, EtatPersistanceElo.persistee,
          reason: 'TÉMOIN NÉGATIF : la correction ne bloque PAS le cas nominal');
      expect(store.contient(kCleElo), isTrue);
      expect(store.contient(kCleRegistre), isTrue);
      expect(elo.nbChevauxSuivis, greaterThan(0));
    });

    test('B2e-9d — ★ A-1 : `amorcageEffectue` ne vaut JAMAIS true sans '
        'écriture confirmée', () async {
      final elo = EloService.instance;

      SharedPreferences.resetStatic();
      final entreeGetAll = store.armerSuspensionGetAll();

      final entreeEffacement = Completer<void>();
      final liberation = Completer<void>();
      final reset = elo.executerResetComplet(() async {
        await store.supprimer(kCleElo);
        await store.supprimer(kCleTs);
        await store.supprimer(kCleRegistre);
        if (!entreeEffacement.isCompleted) entreeEffacement.complete();
        await liberation.future;
      });
      await entreeEffacement.future;

      // Le registre est ABSENT : l'opération va emprunter la branche d'AMORÇAGE
      // (caller A) — c'est précisément le chemin où `amorcageEffectue` a été
      // mesuré à `true` sans écriture.
      final maj = elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse1,
      );
      await _attendreEntreeOuFin(entreeGetAll, maj);

      liberation.complete();
      await reset;
      store.libererGetAll();
      await maj;
      await _laisserProgresser();

      final res = elo.dernierResultatMiseAJour;
      // ignore: avoid_print
      print('[B2e-9d] → $res');

      // ⚠️ L'observable ne doit pas affirmer un amorçage qui n'a pas eu lieu.
      expect(res!.amorcageEffectue, isFalse,
          reason: 'A-1 : aucun registre n\'a été écrit, donc AUCUN amorçage '
              'n\'est confirmé — `amorcageEffectue` décrit un FAIT, pas une '
              'intention');
    });
  });
}

/// ★ B2e-9 — attend soit l'entrée en suspension, soit la fin de [operation].
///
/// Rend `true` si la suspension a été atteinte AVANT la fin : c'est le témoin
/// de préparation qui rend les tests B2e-9 déterministes plutôt que probables.
Future<bool> _attendreEntreeOuFin(
    Future<void> entree, Future<void> operation) async {
  var fini = false;
  final fin = Completer<void>();
  operation.whenComplete(() {
    fini = true;
    if (!fin.isCompleted) fin.complete();
  }).ignore();
  await Future.any<void>([entree, fin.future]);
  return !fini;
}
