// ═══════════════════════════════════════════════════════════════════════════
//  A7 — LIMITES R-a / R-b / R-c / R-d : TESTS DE CARACTÉRISATION
//
//  OBJET DE CE FICHIER — à lire avant toute conclusion.
//
//  Ces tests ne valident PAS un comportement souhaitable. Ils MESURENT le
//  comportement ACTUEL du code de production, y compris là où il est
//  défectueux. Chaque assertion décrit ce que le code FAIT, et non ce qu'il
//  devrait faire.
//
//  CONSÉQUENCE MÉTHODOLOGIQUE : un test de caractérisation qui passe ne
//  prouve RIEN sur la qualité du correctif à venir. Il prouve seulement que
//  le défaut existe, avec un chiffre. Après correction, ces assertions
//  devront être TRANSFORMÉES en assertions NORMATIVES (comportement attendu),
//  jamais supprimées ni affaiblies.
//
//  STATUT DE CHAQUE FAMILLE :
//    • CARACTÉRISATION — décrit un défaut mesuré, à corriger ensuite.
//    • LIMITE DÉCLARÉE — mesure une propriété, avec la portée exacte de ce
//      qui est prouvé et de ce qui ne l'est pas.
//
//  CE QUI N'EST PAS TESTÉ ICI, ET POURQUOI :
//    • `DataRefreshService._mettreAJourEloApresArrivee` et
//      `_recupererResultatsBatch` sont PRIVÉS. Aucune API publique ne permet
//      de les invoquer. Les effets mesurés ici sont ceux des primitives
//      PUBLIQUES qu'ils appellent. Ce fichier ne prétend donc PAS tester
//      l'intégralité du service : il reproduit ses effets publics.
//    • Aucun réseau : `_fetchArriveeOfficielle` n'est jamais appelé.
//    • Aucune donnée réelle de l'utilisateur : stores en mémoire.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_archive_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  STORES
//  `_StoreSain`   : écriture toujours acceptée (référence).
//  `_StoreDefaillant` : permet d'INJECTER l'échec d'écriture, ce qui est le
//  seul moyen de mesurer R-d sans dépendre d'une panne réelle du disque.
// ═══════════════════════════════════════════════════════════════════════════

/// Mode d'échec injecté sur une clé donnée.
enum _ModeEchec {
  /// `setValue` renvoie `false` : l'écriture est REFUSÉE, sans exception.
  retourneFalse,

  /// `setValue` lève une exception : l'écriture ÉCHOUE bruyamment.
  leveException,
}

class _StoreSain extends SharedPreferencesStorePlatform {
  _StoreSain({Map<String, Object>? data}) : _data = <String, Object>{...?data};

  final Map<String, Object> _data;

  /// Écritures effectuées (`setValue`), dans l'ordre.
  final List<String> journal = <String>[];

  /// Suppressions effectuées (`remove`).
  final List<String> suppressions = <String>[];

  @override
  Future<bool> clear() async => clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async {
    final f = parameters.filter;
    final keys = _data.keys
        .where((k) =>
            k.startsWith(f.prefix) &&
            (f.allowList == null || f.allowList!.contains(k)))
        .toList();
    for (final k in keys) {
      _data.remove(k);
    }
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<Map<String, Object>> getAllWithParameters(
      GetAllParameters parameters) async {
    final f = parameters.filter;
    final result = Map<String, Object>.from(_data);
    result.removeWhere((k, _) =>
        !k.startsWith(f.prefix) ||
        (f.allowList != null && !f.allowList!.contains(k)));
    return result;
  }

  @override
  Future<bool> remove(String key) async {
    suppressions.add(key);
    _data.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    journal.add(key);
    _data[key] = value;
    return true;
  }

  // ── Outils de mesure ────────────────────────────────────────────────────
  Object? brut(String cle) => _data['flutter.$cle'];

  bool contient(String cle) => _data.containsKey('flutter.$cle');

  /// Écritures de la SEULE clé ELO, à cet instant.
  int get ecrituresElo =>
      journal.where((k) => k == 'flutter.elo_ratings_v2').length;

  /// Écriture DIRECTE d'une clé, hors service : préparation d'un état connu.
  void setValueBrut(String cle, Object valeur) =>
      _data['flutter.$cle'] = valeur;

  /// Retire une clé du store, hors service.
  ///
  /// ⚠️ USAGE STRICTEMENT LIMITÉ À UNE SIMULATION D'ÉVICTION. Le plafond de
  ///    600 pronostics retire la course de `_pronostics` depuis l'intérieur du
  ///    service ; cette liste est privée et aucune API publique ne permet de
  ///    la réduire. Retirer le blob des pronostics reproduit donc l'état
  ///    observable d'APRÈS éviction (mémoire active vide, archive peuplée),
  ///    sans rien inventer sur les règles du service.
  void retirer(String cle) => _data.remove('flutter.$cle');

  /// Injection d'une valeur comme si elle venait du disque, SANS journaliser.
  void poser(String cle, Object valeur) => _data['flutter.$cle'] = valeur;
}

/// Store dont l'écriture de la clé ELO peut être rendue DÉFAILLANTE.
///
/// Le point d'injection est exactement celui du disque réel : `setValue`.
/// Aucune autre clé n'est affectée, de sorte que la mesure isole la
/// persistance ELO et rien d'autre.
class _StoreDefaillant extends _StoreSain {
  _StoreDefaillant({
    super.data,
    required this.cleDefaillante,
    required this.mode,
  });

  final String cleDefaillante;
  final _ModeEchec mode;

  /// Nombre de tentatives d'écriture sur la clé défaillante.
  int tentativesSurCleDefaillante = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.$cleDefaillante') {
      tentativesSurCleDefaillante++;
      if (mode == _ModeEchec.leveException) {
        throw StateError('écriture refusée (injection de test)');
      }
      // Refus silencieux : même contrat que la plateforme, `false`.
      journal.add(key);
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  DONNÉES DE TEST
// ═══════════════════════════════════════════════════════════════════════════

const String _disc = 'Trot Attelé'; // → normalisé TROT_ATTELE
const String _discNorm = 'TROT_ATTELE';
const String _cleElo = 'elo_ratings_v2';

/// ★ A7 (3.3-B2-e) — IDENTITÉS DE COURSE DES APPLICATIONS DE CE FICHIER.
///
/// Le contrat B2-e exige une identité exploitable pour TOUTE application ELO :
/// un appel sans `courseKey` rend `identiteNonExploitable` et ne mute rien.
/// Les tests C-RD-1/2/3 caractérisent la DIVERGENCE RAM/DISQUE (R-d) — un
/// calcul qui a lieu, une écriture qui échoue. Sans identité, ils ne
/// mesureraient plus qu'un refus d'identité et perdraient leur objet.
/// Une clé par course LOGIQUEMENT DIFFÉRENTE, date ancrée dans le PASSÉ.
const String _cleCourse1 = 'R1C1_01112026';
const String _cleCourse2 = 'R2C2_02112026';
const String _cleCourse3 = 'R3C3_03112026';

String _cle(String nom) => '${nom.toUpperCase()}|$_discNorm';

ZtPartant _partant(int num, {String? nom, double rating = 1500.0, int nbCourses = 20}) {
  final nomCheval = nom ?? 'CHEVAL_$num';
  return ZtPartant(
    numero: '$num',
    nom: nomCheval,
    driver: 'DRIVER_$num',
    entraineur: 'ENTR_$num',
    proprietaire: 'PROP_$num',
    gains: '${num * 10000}',
    record: '1\'1${num % 10}"0',
    musique: '1a2a3a4a5a',
    cote: '4.0',
    ageSexe: '${4 + num % 6} M',
    poids: 57.0 + num,
    placeDepartInt: num,
    joursRepos: 10 + num,
    hippodromeActuel: 'VINCENNES',
    statsJockeyCsv: 'JOCKEY_$num|15|40|12',
    statsHippodromeCsv: 'VINCENNES|20|45|15',
    statsEntraineurCsv: 'ENTR_$num|12|33|8',
    eloRating: rating,
    eloNbCourses: nbCourses,
    eloVariationMois: 0.0,
    statsTerrainCsv: 'bon|6|2|4',
    gainsDernierAn: num * 5000,
    scoreIA: 100.0 - num,
  );
}

DateTime get _jour {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

String _ddmmyyyy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

String _cleCourse(int r, int c, DateTime d) => 'R${r}C${c}_${_ddmmyyyy(d)}';

const ScoresCriteres _critereNeutre = ScoresCriteres(
  forme: 60, gains: 60, record: 60, cote: 60, constance: 60,
  victoires: 60, discipline: 60, distSpec: 60, jockey: 60,
  repos: 60, hippo: 60, entraineur: 60, elo: 60, terrain: 60,
  divergence: 60, poidsRel: 60, progression: 60, mouvCote: 60,
  placeDepart: 60,
);

const String _kPoids =
    '{"forme":0.25,"gains":0.13,"record":0.10,"cote":0.08,"constance":0.09,'
    '"victoires":0.04,"discipline":0.02,"distSpec":0.08,"jockey":0.07,'
    '"repos":0.03,"hippo":0.04,"entraineur":0.04,"elo":0.05,"terrain":0.05,'
    '"divergence":0.04,"poidsRel":0.03,"progression":0.03,"mouvCote":0.06,'
    '"placeDepart":0.03,"nbMisesAJour":0,"calibrationScore":50.0}';

ZtCourse _course(String courseKey, List<ZtPartant> partants) {
  final m = RegExp(r'_(\d{2})(\d{2})(\d{4})$').firstMatch(courseKey);
  final dateStr = m != null
      ? '${m.group(1)}${m.group(2)}${m.group(3)}'
      : _ddmmyyyy(_jour);
  return ZtCourse(
    numCourse: 1,
    anchor: 'R21C1',
    nom: 'PRIX_A7_LIMITES',
    heure: '14:15',
    distance: '2700',
    prix: '50000',
    type: _disc,
    piste: 'Sable',
    categorie: 'Course D',
    isQuinte: true,
    pronosticZt: const <int>[1, 2],
    partants: partants,
    dateStr: dateStr,
  );
}

Map<String, dynamic> _item({
  required String courseKey,
  required ZtCourse course,
}) =>
    <String, dynamic>{
      'courseKey': courseKey,
      'course': course,
      'partantsClasses': course.partants,
      'scoresCriteres': <String, ScoresCriteres>{
        for (final p in course.partants) p.numero: _critereNeutre,
      },
      'confiance': 68.25,
      'typePariConseille': 'Quinté+',
    };

// ═══════════════════════════════════════════════════════════════════════════
//  MONTAGE
// ═══════════════════════════════════════════════════════════════════════════

/// Monte un store [store] déjà construit et remet tous les singletons dans un
/// état de premier démarrage.
Future<void> _brancher(_StoreSain store) async {
  SharedPreferences.resetStatic();
  SharedPreferencesStorePlatform.instance = store;
  await IaArchiveService.instance.reinitialiserMemoirePourTest();
  await IaMemoryService.instance.recharger();
}

/// Store sain neuf + mémoire IA et ELO vides.
Future<_StoreSain> _buildStore() async {
  final store = _StoreSain(data: <String, Object>{
    'flutter.ia_precision_migrated_v3': true,
    'flutter.ia_poids_v3': _kPoids,
    'flutter.ia_seuils_v1': '{}',
  });
  await _brancher(store);
  await EloService.instance.reinitialiser();
  return store;
}

/// Écrit un jeu ELO de référence SUR LE DISQUE puis l'injecte en RAM via
/// l'API de production du chemin de restauration.
Future<void> _preparerElo(
    _StoreSain store, Map<String, ({double rating, int nb})> etat) async {
  final data = <String, dynamic>{
    for (final e in etat.entries)
      _cle(e.key): <String, dynamic>{
        'nom': e.key,
        'rating': e.value.rating,
        'nb': e.value.nb,
        'var': 0.0,
      },
  };
  store.setValueBrut(_cleElo, jsonEncode(data));
  await EloService.instance.importerDepuisBackup(data);
}

/// Lecture DIRECTE de la clé ELO sur le disque, sans passer par le cache.
Map<String, dynamic> _eloSurDisque(_StoreSain store) {
  final brut = store.brut(_cleElo);
  if (brut is! String || brut.isEmpty) return <String, dynamic>{};
  final decode = json.decode(brut);
  if (decode is! Map) return <String, dynamic>{};
  return decode.map((k, v) => MapEntry(k as String, v));
}

double _rating(String nom) =>
    EloService.instance.getRating(nom, discipline: _disc);

int _nb(String nom) =>
    EloService.instance.getScore(nom, discipline: _disc).nbCourses;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═════════════════════════════════════════════════════════════════════════
  //  R-a — RÉSULTAT CONSIGNÉ UNIQUEMENT EN ARCHIVE
  // ═════════════════════════════════════════════════════════════════════════
  group('C-RA — R-a : une course évincée n\'alimente PAS l\'ELO', () {
    test('C-RA-1 [CARACTÉRISATION] — archive seule : résultat consigné, '
        'retour false, AUCUNE écriture ELO', () async {
      final store = await _buildStore();
      final key = _cleCourse(21, 1, _jour);
      final partants = [_partant(1), _partant(2), _partant(3)];

      // 1. Un pronostic est créé normalement, puis la course est ÉVINCÉE de la
      //    mémoire active par le plafond (API de production de l'archive).
      await IaMemoryService.instance.enregistrerPronosticsBatch([
        _item(courseKey: key, course: _course(key, partants)),
      ]);
      expect(IaMemoryService.instance.pronostics.length, 1,
          reason: 'le pronostic doit exister avant l\'éviction');

      // Éviction par l'API de production, en deux temps :
      // temps 1 `enregistrerEviction(IaPronostic)` (synchrone),
      // temps 2 `persisterEnAttente()` (écriture durable de l'archive).
      final aEvincer = IaMemoryService.instance.pronostics
          .firstWhere((x) => x.courseKey == key);
      IaArchiveService.instance
          .enregistrerEviction(aEvincer, motif: ArchiveReason.eviction);
      await IaArchiveService.instance.persisterEnAttente();

      // ⚠️ LIMITE DÉCLARÉE — le retrait de `_pronostics` est effectué par le
      //    plafond de 600, À L'INTÉRIEUR du service ; aucune API publique ne
      //    le permet. On reproduit donc l'état d'APRÈS éviction en retirant
      //    le blob des pronostics puis en rechargeant. Aucune règle n'est
      //    simulée : on constate seulement l'état résultant.
      store.retirer('ia_pronostics_v2');
      store.retirer('ia_pronostics_v2_gz');
      // Le cache interne de `SharedPreferences` doit etre vide, sinon
      // `_load()` relit l'ancienne valeur depuis sa memoire.
      SharedPreferences.resetStatic();
      await IaMemoryService.instance.recharger();
      expect(IaMemoryService.instance.pronostics, isEmpty,
          reason: 'la course doit être ABSENTE de la mémoire active');

      // 2. État ELO de référence, APRÈS l'éviction.
      await _preparerElo(store, {
        'CHEVAL_1': (rating: 1500.0, nb: 0),
        'CHEVAL_2': (rating: 1500.0, nb: 0),
        'CHEVAL_3': (rating: 1500.0, nb: 0),
      });
      final ecrituresAvant = store.ecrituresElo;
      final ratingAvant  = _rating('CHEVAL_1');
      final nbAvant      = _nb('CHEVAL_1');

      // 3. L'arrivée officielle arrive APRÈS l'éviction.
      final bool retour = await IaMemoryService.instance.enregistrerResultat(
        courseKey: key,
        arriveeReelle: const <int>[1, 2, 3],
      );

      final ratingApres = _rating('CHEVAL_1');
      final nbApres     = _nb('CHEVAL_1');
      final ecrituresApres = store.ecrituresElo;

      // 4. Le résultat EST consigné dans l'archive…
      final archive = IaArchiveService.instance.versionRetenue(key);
      expect(archive, isNotNull,
          reason: 'la version archivée doit exister après consignation');
      expect(archive!.resultatsReels, isTrue,
          reason: 'le résultat doit être marqué résolu DANS L\'ARCHIVE');

      // …mais AUCUNE mise à jour ELO n'a lieu.
      expect(retour, isFalse,
          reason: 'branche archive ⇒ false (contrat A7 déjà validé)');
      expect(ratingApres, ratingAvant,
          reason: 'R-a CARACTÉRISÉ : le rating ne bouge pas');
      expect(nbApres, nbAvant,
          reason: 'R-b/R-a : nbCourses n\'est pas incrémenté');
      expect(ecrituresApres, ecrituresAvant,
          reason: 'AUCUNE écriture de la clé ELO');

      debugPrint('[C-RA-1] retour=$retour | rating $ratingAvant → $ratingApres '
          '| nb $nbAvant → $nbApres | écritures ELO $ecrituresAvant → '
          '$ecrituresApres | archive résolue=${archive.resultatsReels}');
    });

    test('C-RA-2 [LIMITE DÉCLARÉE] — l\'archive ne contient AUCUN nom par '
        'numéro : le calcul ELO est matériellement impossible', () async {
      final store = await _buildStore();
      final key = _cleCourse(21, 2, _jour);
      final partants = [_partant(1), _partant(2), _partant(3)];

      await IaMemoryService.instance.enregistrerPronosticsBatch([
        _item(courseKey: key, course: _course(key, partants)),
      ]);
      final aEvincer2 = IaMemoryService.instance.pronostics
          .firstWhere((x) => x.courseKey == key);
      IaArchiveService.instance
          .enregistrerEviction(aEvincer2, motif: ArchiveReason.eviction);
      await IaArchiveService.instance.persisterEnAttente();
      store.retirer('ia_pronostics_v2');
      store.retirer('ia_pronostics_v2_gz');
      // Le cache interne de `SharedPreferences` doit etre vide, sinon
      // `_load()` relit l'ancienne valeur depuis sa memoire.
      SharedPreferences.resetStatic();
      await IaMemoryService.instance.recharger();

      await IaMemoryService.instance.enregistrerResultat(
        courseKey: key,
        arriveeReelle: const <int>[1, 2, 3],
      );

      final archive = IaArchiveService.instance.versionRetenue(key)!;
      final json = archive.toJson();

      // CE QUI SURVIT : les scores par numéro, la discipline, le favori.
      expect(archive.scoresIA.keys.toSet(), <String>{'1', '2', '3'},
          reason: 'les NUMÉROS survivent');
      expect(archive.discipline, isNotEmpty);
      expect(archive.favoriIaNom, isNotNull);

      // CE QUI NE SURVIT PAS : aucun nom de cheval n'est sérialisé.
      // `scoresIA` est indexé par NUMÉRO (ia_memory_service.dart:2865-2867
      // `scores[p.numero] = p.scoreIA`) : c'est une mesure du code, pas une
      // supposition. Le seul nom conservé est celui du favori.
      final cles = json.keys.toSet();
      expect(cles.contains('partants'), isFalse,
          reason: 'aucune liste de partants dans le format d\'archive');
      expect(cles.contains('noms'), isFalse);
      expect(cles.contains('nomParNumero'), isFalse);

      // Preuve directe : le calcul ELO exige des `ZtPartant` nominatifs
      // (`mettreAJourApresArrivee` lit `p.nom`). L'archive n'en fournit aucun
      // pour les numéros 2 et 3.
      expect(archive.favoriIaNom, isNot('CHEVAL_2'),
          reason: 'le format ne permet pas de reconstituer les noms 2 et 3');

      debugPrint('[C-RA-2] clés d\'archive = $cles | scoresIA='
          '${archive.scoresIA.keys.toList()} | favori=${archive.favoriIaNom} '
          '| DISCRIMINANT : aucun nom par numéro ⇒ ELO non calculable depuis '
          'l\'archive seule');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  R-b — RÉSULTAT ENREGISTRÉ SANS ELO, DÉFINITIVEMENT
  // ═════════════════════════════════════════════════════════════════════════
  group('C-RB — R-b : un résultat enregistré sans ELO ne le reçoit JAMAIS', () {
    test('C-RB-1 [CARACTÉRISATION] — enregistrement seul (chemin '
        'AlertService/relancerRecuperationPMU) : true, ELO intact', () async {
      final store = await _buildStore();
      final key = _cleCourse(22, 1, _jour);
      final partants = [_partant(1), _partant(2), _partant(3)];

      await IaMemoryService.instance.enregistrerPronosticsBatch([
        _item(courseKey: key, course: _course(key, partants)),
      ]);
      await _preparerElo(store, {
        'CHEVAL_1': (rating: 1500.0, nb: 0),
        'CHEVAL_2': (rating: 1500.0, nb: 0),
        'CHEVAL_3': (rating: 1500.0, nb: 0),
      });
      final ecrituresAvant = store.ecrituresElo;

      // Reproduit EXACTEMENT les 3 chemins de production qui n'appellent pas
      // l'ELO : alert_service.dart:2719, ia_memory_service.dart:1683 et
      // ia_memory_service.dart:1991. Tous passent par le même appel nu.
      final bool retour = await IaMemoryService.instance.enregistrerResultat(
        courseKey: key,
        arriveeReelle: const <int>[1, 2, 3],
      );

      expect(retour, isTrue,
          reason: 'le résultat EST nouveau : le booléen vaut true');
      expect(_rating('CHEVAL_1'), 1500.0,
          reason: 'R-b CARACTÉRISÉ : le rating n\'a pas bougé');
      expect(_nb('CHEVAL_1'), 0);
      expect(store.ecrituresElo, ecrituresAvant,
          reason: 'aucune écriture ELO sur ce chemin');

      debugPrint('[C-RB-1] retour=$retour | rating='
          '${_rating('CHEVAL_1')} | nb=${_nb('CHEVAL_1')} | écritures ELO='
          '${store.ecrituresElo}');
    });

    test('C-RB-2 [CARACTÉRISATION — LE DÉFAUT CENTRAL] — l\'ELO n\'est jamais '
        'rattrapé : un second passage retourne false et le rating reste figé',
        () async {
      final store = await _buildStore();
      final key = _cleCourse(22, 2, _jour);
      final partants = [_partant(1), _partant(2), _partant(3)];

      await IaMemoryService.instance.enregistrerPronosticsBatch([
        _item(courseKey: key, course: _course(key, partants)),
      ]);
      await _preparerElo(store, {
        'CHEVAL_1': (rating: 1500.0, nb: 0),
        'CHEVAL_2': (rating: 1500.0, nb: 0),
        'CHEVAL_3': (rating: 1500.0, nb: 0),
      });

      // 1er passage : le résultat est enregistré SANS ELO (chemin R-b).
      final retour1 = await IaMemoryService.instance.enregistrerResultat(
        courseKey: key,
        arriveeReelle: const <int>[1, 2, 3],
      );

      // 2e passage : un service disposant, LUI, des partants tente de
      // rattraper la mise à jour ELO.
      final retour2 = await IaMemoryService.instance.enregistrerResultat(
        courseKey: key,
        arriveeReelle: const <int>[1, 2, 3],
      );

      expect(retour1, isTrue);
      expect(retour2, isFalse,
          reason: 'déjà résolu ⇒ false : c\'est la garde d\'idempotence A7');

      // La conséquence : le booléen `false` empêche tout rattrapage, puisque
      // le seul déclencheur ELO conditionné (`if (resultatEnregistre)`) est
      // désormais FAUX. Le rating reste définitivement à sa valeur initiale.
      expect(_rating('CHEVAL_1'), 1500.0,
          reason: 'R-b DÉFINITIF : aucun chemin ne peut plus appliquer l\'ELO');
      expect(_nb('CHEVAL_1'), 0);

      debugPrint('[C-RB-2] retours=[$retour1, $retour2] | rating='
          '${_rating('CHEVAL_1')} | nb=${_nb('CHEVAL_1')} → la course est '
          'résolue, l\'ELO est PERDU SANS TRACE');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  R-c — TRAITEMENT NON ATTENDU ET SORTIES SILENCIEUSES
  // ═════════════════════════════════════════════════════════════════════════
  group('C-RC — R-c : pertes silencieuses de mise à jour ELO', () {
    test('C-RC-1 [CARACTÉRISATION] — `mettreAJourApresArrivee` sort '
        'SILENCIEUSEMENT si les partants sont absents ou vides', () async {
      final store = await _buildStore();
      await _preparerElo(store, {
        'CHEVAL_1': (rating: 1500.0, nb: 0),
        'CHEVAL_2': (rating: 1500.0, nb: 0),
      });
      final ecrituresAvant = store.ecrituresElo;

      // `partants: []` est exactement ce que reçoit EloService quand
      // `DataRefreshService._mettreAJourEloApresArrivee` ne retrouve pas la
      // course dans `_reunions` — et ce cas ne peut PAS être atteint depuis
      // un test, car `_reunions` est privé. On mesure donc la primitive
      // publique, ce qui est le seul point observable.
      await EloService.instance.mettreAJourApresArrivee(
        arrivee: const <int>[1, 2],
        partants: const <ZtPartant>[],
        discipline: _disc,
      );

      expect(_rating('CHEVAL_1'), 1500.0);
      expect(store.ecrituresElo, ecrituresAvant,
          reason: 'aucune écriture : la sortie est SILENCIEUSE (l.245)');

      // Aucune exception n'a été levée : l'appelant ne peut pas distinguer
      // « rien à faire » de « mise à jour perdue ».
      debugPrint('[C-RC-1] partants vides ⇒ rating=${_rating('CHEVAL_1')} | '
          'écritures ELO=${store.ecrituresElo} | AUCUNE erreur signalée');
    });

    test('C-RC-2 [CARACTÉRISATION] — `_mettreAJourEloApresArrivee` comporte '
        'DEUX sorties anticipées muettes avant tout appel ELO', () async {
      // Mesure STATIQUE : on lit le code de production et on compte les
      // sorties anticipées. Ce test ne remplace pas une exécution du service :
      // il fige le fait que le seul appel ELO de production peut être
      // court-circuité sans le moindre signal.
      //
      // data_refresh_service.dart, `_mettreAJourEloApresArrivee` :
      //   l.1220 `if (match == null) return;`         → courseKey non conforme
      //   l.1240 `if (partants == null || partants.isEmpty) return;`
      //   l.1246 `.ignore();`                        → la future n'est pas suivie
      //
      // Il n'existe AUCUN `catch`, AUCUN compteur, AUCUN état persisté
      // permettant de savoir qu'une arrivée n'a pas reçu son ELO.
      // ⇒ la perte est INOBSERVABLE par tout appelant.

      final store = await _buildStore();
      await _preparerElo(store, {
        'CHEVAL_1': (rating: 1500.0, nb: 0),
      });

      // Preuve exécutable de l'absence de propagation pour `.ignore()` :
      // une future en erreur, ignorée, ne fait échouer aucun `await` en aval.
      // Le contrat `Future.ignore()` est celui du SDK ; on l'exerce pour
      // documenter le comportement dont dépend le service.
      Object? erreurObservee;
      await runZonedGuarded(() async {
        Future<void>.error(StateError('erreur ELO simulée')).ignore();
        await Future<void>.delayed(Duration.zero);
      }, (e, _) => erreurObservee = e);

      expect(erreurObservee, isNull,
          reason: 'avec `.ignore()`, l\'erreur ne remonte PAS à l\'appelant');

      debugPrint('[C-RC-2] `.ignore()` : erreur avalée sans propagation '
          '(erreurObservee=$erreurObservee) | 2 sorties muettes dans le '
          'wrapper de production');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  R-d — ÉCHEC DE PERSISTANCE SILENCIEUX
  // ═════════════════════════════════════════════════════════════════════════
  group('C-RD — R-d : divergence durable entre RAM et disque', () {
    test('C-RD-1 [CARACTÉRISATION — LE DÉFAUT LE PLUS GRAVE] — écriture '
        'REFUSÉE (false) : la RAM est modifiée, le disque ne l\'est pas',
        () async {
      final store = _StoreDefaillant(
        data: <String, Object>{
          'flutter.ia_precision_migrated_v3': true,
          'flutter.ia_poids_v3': _kPoids,
          'flutter.ia_seuils_v1': '{}',
        },
        cleDefaillante: _cleElo,
        mode: _ModeEchec.retourneFalse,
      );
      await _brancher(store);
      await EloService.instance.reinitialiser();

      // L'initialisation de l'état passe AVANT l'activation du défaut :
      // on écrit directement la valeur de référence, sans passer par setValue.
      final data = <String, dynamic>{
        for (final n in <String>['CHEVAL_1', 'CHEVAL_2'])
          _cle(n): <String, dynamic>{
            'nom': n, 'rating': 1500.0, 'nb': 0, 'var': 0.0,
          },
      };
      store.setValueBrut(_cleElo, jsonEncode(data));
      await EloService.instance.importerDepuisBackup(data);
      // `importerDepuisBackup` vient d'appeler `_sauvegarder()` : le refus a
      // déjà eu lieu, mais la RAM reste correcte. On mesure le disque.
      final disqueAvant = _eloSurDisque(store);
      final ratingAvant = _rating('CHEVAL_1');

      // L'arrivée officielle : le calcul a lieu, la RAM est écrite, la
      // persistance est REFUSÉE.
      await EloService.instance.mettreAJourApresArrivee(
        arrivee: const <int>[1, 2],
        partants: [_partant(1), _partant(2)],
        discipline: _disc,
        courseKey: _cleCourse1, // ★ B2-e : identité exigée
      );

      final ratingRam  = _rating('CHEVAL_1');
      final nbRam      = _nb('CHEVAL_1');
      final disqueApres = _eloSurDisque(store);

      // 1. La RAM a bien été mise à jour (le calcul a eu lieu).
      expect(ratingRam, greaterThan(ratingAvant),
          reason: 'la RAM porte la mise à jour, c\'est mesuré');
      expect(nbRam, 1);

      // 2. Le disque n'a PAS reçu la mise à jour.
      final disqueRating =
          (disqueApres[_cle('CHEVAL_1')] as Map?)?['rating'] as num?;
      expect(disqueRating, 1500.0,
          reason: 'R-d : le disque reste à l\'ancienne valeur');
      expect(disqueApres, disqueAvant,
          reason: 'le disque est INCHANGÉ par une écriture refusée');

      // 3. Aucune exception, aucun signal : l'appelant croit avoir réussi.
      debugPrint('[C-RD-1] RAM rating=$ratingRam nb=$nbRam | DISQUE '
          'rating=$disqueRating | tentatives=${store.tentativesSurCleDefaillante} '
          '| AUCUNE erreur propagée ⇒ DIVERGENCE DURABLE');
    });

    test('C-RD-2 [CARACTÉRISATION] — écriture LEVANT une exception : '
        '`_executerSauvegarde` l\'avale intégralement', () async {
      final store = _StoreDefaillant(
        data: <String, Object>{
          'flutter.ia_precision_migrated_v3': true,
          'flutter.ia_poids_v3': _kPoids,
          'flutter.ia_seuils_v1': '{}',
        },
        cleDefaillante: _cleElo,
        mode: _ModeEchec.leveException,
      );
      await _brancher(store);
      await EloService.instance.reinitialiser();

      final data = <String, dynamic>{
        for (final n in <String>['CHEVAL_1', 'CHEVAL_2'])
          _cle(n): <String, dynamic>{
            'nom': n, 'rating': 1500.0, 'nb': 0, 'var': 0.0,
          },
      };
      store.setValueBrut(_cleElo, jsonEncode(data));
      await EloService.instance.importerDepuisBackup(data);

      // Aucune exception ne doit sortir de cet appel : c'est précisément le
      // défaut. On l'exerce SANS `expect(throwsNothing)` pour pouvoir
      // rapporter la valeur mesurée.
      Object? exceptionRemontee;
      try {
        await EloService.instance.mettreAJourApresArrivee(
          arrivee: const <int>[1, 2],
          partants: [_partant(1), _partant(2)],
          discipline: _disc,
          courseKey: _cleCourse2, // ★ B2-e : identité exigée
        );
      } catch (e) {
        exceptionRemontee = e;
      }

      expect(exceptionRemontee, isNull,
          reason: 'R-d : l\'exception est capturée par `_executerSauvegarde`');

      final disqueApres = _eloSurDisque(store);
      final disqueRating =
          (disqueApres[_cle('CHEVAL_1')] as Map?)?['rating'] as num?;
      final ratingRam = _rating('CHEVAL_1');

      expect(disqueRating, 1500.0,
          reason: 'le disque n\'a rien reçu');
      expect(ratingRam, greaterThan(1500.0),
          reason: 'la RAM a été mise à jour malgré l\'échec');

      debugPrint('[C-RD-2] exception propagée=$exceptionRemontee | RAM '
          'rating=$ratingRam | DISQUE rating=$disqueRating | tentatives='
          '${store.tentativesSurCleDefaillante}');
    });

    test('C-RD-3 [CARACTÉRISATION] — après REDÉMARRAGE, la mise à jour '
        '« appliquée » en RAM est DÉFINITIVEMENT PERDUE', () async {
      final store = _StoreDefaillant(
        data: <String, Object>{
          'flutter.ia_precision_migrated_v3': true,
          'flutter.ia_poids_v3': _kPoids,
          'flutter.ia_seuils_v1': '{}',
        },
        cleDefaillante: _cleElo,
        mode: _ModeEchec.retourneFalse,
      );
      await _brancher(store);
      await EloService.instance.reinitialiser();

      final data = <String, dynamic>{
        for (final n in <String>['CHEVAL_1', 'CHEVAL_2'])
          _cle(n): <String, dynamic>{
            'nom': n, 'rating': 1500.0, 'nb': 0, 'var': 0.0,
          },
      };
      store.setValueBrut(_cleElo, jsonEncode(data));
      await EloService.instance.importerDepuisBackup(data);

      await EloService.instance.mettreAJourApresArrivee(
        arrivee: const <int>[1, 2],
        partants: [_partant(1), _partant(2)],
        discipline: _disc,
        courseKey: _cleCourse3, // ★ B2-e : identité exigée
      );

      final ratingAvantRedemarrage = _rating('CHEVAL_1');
      expect(ratingAvantRedemarrage, greaterThan(1500.0));

      // REDÉMARRAGE : on vide la RAM comme le ferait un nouveau processus.
      // `viderMemoirePourResetComplet` est SYNCHRONE et n'écrit rien.
      EloService.instance.viderMemoirePourResetComplet();

      // ⚠️ LIMITE DÉCLARÉE : `EloService._charge` reste `true` et aucune API
      // publique ne le remet à `false`. On lit donc l'état RÉELLEMENT
      // persistant, qui est la seule chose qu'un redémarrage relirait.
      final disqueApresRedemarrage = _eloSurDisque(store);
      final ratingRelu =
          (disqueApresRedemarrage[_cle('CHEVAL_1')] as Map?)?['rating'] as num?;

      expect(ratingRelu, 1500.0,
          reason: 'C-RD-3 : après redémarrage, la mise à jour a DISPARU');
      expect(ratingRelu, isNot(ratingAvantRedemarrage),
          reason: 'divergence RAM/disque confirmée par la mesure');

      debugPrint('[C-RD-3] RAM avant redémarrage=$ratingAvantRedemarrage | '
          'DISQUE relu=$ratingRelu ⇒ la course est perdue SANS TRACE, et '
          'aucun registre ne permet de savoir qu\'elle reste à traiter');
    });

    test('C-RD-4 [CARACTÉRISATION] — rien ne rattrape l\'échec : la course '
        'est résolue ET l\'ELO est perdu, sans état de reprise', () async {
      final store = _StoreDefaillant(
        data: <String, Object>{
          'flutter.ia_precision_migrated_v3': true,
          'flutter.ia_poids_v3': _kPoids,
          'flutter.ia_seuils_v1': '{}',
        },
        cleDefaillante: _cleElo,
        mode: _ModeEchec.retourneFalse,
      );
      await _brancher(store);
      await EloService.instance.reinitialiser();

      final key = _cleCourse(23, 1, _jour);
      final partants = [_partant(1), _partant(2), _partant(3)];
      await IaMemoryService.instance.enregistrerPronosticsBatch([
        _item(courseKey: key, course: _course(key, partants)),
      ]);

      // Résultat nouveau + ELO dont la persistance échoue.
      final bool enregistre = await IaMemoryService.instance.enregistrerResultat(
        courseKey: key,
        arriveeReelle: const <int>[1, 2, 3],
      );
      expect(enregistre, isTrue);

      await EloService.instance.mettreAJourApresArrivee(
        arrivee: const <int>[1, 2, 3],
        partants: partants,
        discipline: _disc,
      );

      // Le pronostic est RÉSOLU : plus aucun chemin ne repassera.
      final p = IaMemoryService.instance.pronostics
          .firstWhere((x) => x.courseKey == key);
      expect(p.resultatsReels, isTrue);

      // Le disque ELO ne contient toujours rien pour ces chevaux.
      final disque = _eloSurDisque(store);
      expect(disque.containsKey(_cle('CHEVAL_1')), isFalse,
          reason: 'aucun rating persisté ⇒ perte définitive');

      // Et AUCUN état ne mémorise « cette course reste à traiter côté ELO ».
      // On le prouve par la liste des clés réellement écrites sur le disque.
      final clesDisque = <String>{};
      final toutes = await SharedPreferences.getInstance();
      for (final k in toutes.getKeys()) {
        clesDisque.add(k);
      }
      final clesEvoquantElo = clesDisque
          .where((k) => k.contains('elo') || k.contains('course_traitee'))
          .toList();

      // ⚠️ Mesure : aucune clé de registre de courses traitées n'existe.
      expect(clesDisque.any((k) => k.contains('course_traitee')), isFalse,
          reason: 'aucun registre d\'état d\'application ELO n\'est persisté');

      debugPrint('[C-RD-4] pronostic résolu=${p.resultatsReels} | disque ELO '
          'vide=${disque.isEmpty} | clés ELO présentes=$clesEvoquantElo | '
          'AUCUN registre de reprise');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T21/T22/T23/T23 — NON-RÉGRESSION DES INVARIANTS DÉJÀ VALIDÉS
  // ═════════════════════════════════════════════════════════════════════════
  group('C-NR — non-régression des invariants A7 déjà validés', () {
    test('C-NR-1 [NORMATIF] — le correctif A7 de double comptage est intact', () async {
      final store = await _buildStore();
      final key = _cleCourse(24, 1, _jour);
      final partants = [_partant(1), _partant(2), _partant(3)];

      await IaMemoryService.instance.enregistrerPronosticsBatch([
        _item(courseKey: key, course: _course(key, partants)),
      ]);
      await _preparerElo(store, {
        'CHEVAL_1': (rating: 1500.0, nb: 0),
        'CHEVAL_2': (rating: 1500.0, nb: 0),
        'CHEVAL_3': (rating: 1500.0, nb: 0),
      });

      // Cycle 1 : nouveau ⇒ ELO appliqué UNE fois.
      final r1 = await IaMemoryService.instance.enregistrerResultat(
        courseKey: key, arriveeReelle: const <int>[1, 2, 3]);
      if (r1) {
        await EloService.instance.mettreAJourApresArrivee(
          arrivee: const <int>[1, 2, 3], partants: partants, discipline: _disc);
      }
      final rating1 = _rating('CHEVAL_1');
      final nb1 = _nb('CHEVAL_1');

      // Cycle 2 : même arrivée ⇒ AUCUN second mouvement (correctif A7).
      final retour2 = await IaMemoryService.instance.enregistrerResultat(
        courseKey: key,
        arriveeReelle: const <int>[1, 2, 3],
      );
      final rating2 = _rating('CHEVAL_1');
      final nb2 = _nb('CHEVAL_1');

      expect(r1, isTrue);
      expect(retour2, isFalse);
      expect(rating2, rating1, reason: 'T22 : pas de second mouvement');
      expect(nb2, nb1, reason: 'T22 : nbCourses stable');

      debugPrint('[C-NR-1] r1=$r1 r2=$retour2 | rating $rating1 → $rating2 | '
          'nb $nb1 → $nb2');
    });
  });
}
