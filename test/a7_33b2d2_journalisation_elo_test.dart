// ═══════════════════════════════════════════════════════════════════════════
//  A7 / 3.3-B2-d2 — JOURNALISATION DU TÉMOIN `elo_registre_v3`
//
//  OBJET DU LOT
//  ────────────
//  Après un import de sauvegarde, écrire DANS le registre une entrée
//  `horsCourse` de motif `importBackup` — et SEULEMENT si un point de contrôle
//  unique l'autorise. Le registre reste un TÉMOIN : aucune fonction de ce lot
//  ne rend de ratings, et `elo_service.dart` ne lit jamais le registre pour
//  reconstruire un rating (verrou T-S6).
//
//  CE QUE CE LOT NE FAIT **PAS** — À LIRE AVANT TOUTE INTERPRÉTATION
//  ─────────────────────────────────────────────────────────────────
//  • il ne modifie PAS le type de retour de `importerDepuisBackup`
//    (`Future<EtatPersistanceElo>`) : le résultat composite est publié à côté,
//    par `dernierResultatImport` ;
//  • il ne SUPPRIME jamais le registre, ne le RÉPARE jamais, ne le MIGRE jamais ;
//  • il n'écrit RIEN quand le registre est absent, divergent, corrompu,
//    incompatible, ou quand le diagnostic n'a pas pu être établi ;
//  • il ne revendique AUCUNE protection anti-double-application : en
//    `historiqueInconnu`, `protegeApres` vaut `false` PAR CONSTRUCTION ;
//  • il n'ajoute AUCUNE clé SharedPreferences (`_toutesLesCles` reste 108) ;
//  • il ne touche NI les formules ELO, NI les coefficients K, NI les
//    mécanismes d'apprentissage, NI les critères A–Q.
//
//  MESURES PRÉALABLES QUI FONDENT LES ASSERTIONS
//  ────────────────────────────────────────────
//  • `jsonDecode('1e400')` rend `double.infinity` (mesuré) : c'est le moyen
//    employé pour provoquer une sérialisation impossible SANS inventer de
//    valeur ;
//  • un registre portant une image `Infinity` se DÉCODE sans lever, et c'est
//    `encoder()` qui lève `JsonUnsupportedObjectError` (mesuré) : le cas
//    `serialisationImpossible` est donc atteignable depuis un disque réel ;
//  • `entree.id` négatif se décode sans lever (mesuré) : la validation
//    d'identifiant doit donc être faite par l'allocateur, pas supposée acquise ;
//  • `SharedPreferences.getString` lit le CACHE, d'où le `reload()` du service ;
//  • `setUp()` appelle `EloService.init()` → `_charger()`, qui écrit
//    `elo_orphelins_purges_v1`. Toute assertion sur le journal du store est
//    donc bornée par un index relevé au début du test — jamais absolue.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/elo_registre_v3.dart';
import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/utils/elo_empreinte.dart';

// ───────────────────────────────────────────────────────────────────────────
//  STORE INSTRUMENTÉ — même contrat que B1 / B2-a / B2-b / B2-d1, plus trois
//  capacités nécessaires ici :
//    • suspension d'ÉCRITURE (`setValue`) → prouver drain et suivi ;
//    • REFUS (`false`) et EXCEPTION ciblés → distinguer `refusee` de `echouee` ;
//    • EXCEPTION ciblée sur `getAllWithParameters` → éprouver les branches
//      « diagnostic NON ÉTABLI » (getInstance et reload).
// ───────────────────────────────────────────────────────────────────────────

class _Store extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};
  final List<String> journal = <String>[];

  String? cleSuspendue;
  Completer<void>? _entreeSuspendue;
  Completer<void>? _verrouSuspendu;

  /// Clés dont `setValue` doit rendre `false`.
  final Set<String> refuse = <String>{};

  /// Clés dont `setValue` doit LEVER.
  final Set<String> leve = <String>{};

  /// Si vrai, le PROCHAIN `getAllWithParameters` lève (une seule fois).
  bool _leverProchainGetAll = false;

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
    if (_leverProchainGetAll) {
      _leverProchainGetAll = false;
      journal.add('GETALL-LEVE');
      throw StateError('panne de lecture simulée');
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
    if (leve.contains(key)) {
      journal.add('SET-LEVE $key');
      throw StateError('panne de stockage simulée sur $key');
    }
    if (refuse.contains(key)) {
      journal.add('SET-REFUS $key');
      return false;
    }
    _valeurs[key] = value;
    journal.add('SET-OK $key');
    return true;
  }

  /// Arme une suspension d'écriture sur [cle] (forme AVEC préfixe `flutter.`).
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

  /// Fait lever le PROCHAIN `getAllWithParameters`.
  void leverProchaineLecture() => _leverProchainGetAll = true;

  void desarmer() {
    cleSuspendue = null;
    _entreeSuspendue = null;
    final v = _verrouSuspendu;
    _verrouSuspendu = null;
    if (v != null && !v.isCompleted) v.complete();
    _leverProchainGetAll = false;
  }

  void semer(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;
  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');
  Object? lire(String cle) => _valeurs['flutter.$cle'];

  Set<String> clesEcritesDepuis(int index) => journal
      .skip(index)
      .where((e) => e.startsWith('SET-OK '))
      .map((e) => e.substring('SET-OK '.length))
      .toSet();

  bool aSupprimeDepuis(int index) =>
      journal.skip(index).any((e) => e.startsWith('REM '));
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
Future<void> _laisserProgresser([int tours = 24]) async {
  for (var i = 0; i < tours; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

// ── Constantes ──────────────────────────────────────────────────────────────

const String kCleElo = 'elo_ratings_v2';
const String kCleTs = 'elo_ratings_v2_ts';
const String kCleRegistre = 'elo_registre_v3';

/// Empreinte de la map VIDE — documentée dans `elo_empreinte.dart`.
const String kEmpreinteVide = '16ed60fcfaed47f4';

/// Borne de l'allocateur, recopiée ici pour être VÉRIFIÉE et non supposée.
const int kHorlogeMax = 9007199254740992;

// ───────────────────────────────────────────────────────────────────────────
//  HELPERS DE SEMIS
// ───────────────────────────────────────────────────────────────────────────

/// Map d'`EloScore` de référence. `nbCourses = 20` et `variationMois = 5.0`
/// sont FIXES : l'empreinte ne dépend que de la clé, du rating, de `nbCourses`
/// et de `variationMois` (`canoniqueRatings`), ce qui rend les empreintes
/// attendues calculables sans supposition.
Map<String, EloScore> _mapElo(Map<String, double> ratings) {
  final map = <String, EloScore>{};
  ratings.forEach((cle, rating) {
    final nom = cle.contains('|') ? cle.split('|').first : cle;
    map[cle] = EloScore(
      nomCheval: nom,
      rating: rating,
      nbCourses: 20,
      variationMois: 5.0,
    );
  });
  return map;
}

Map<String, dynamic> _payloadElo(Map<String, double> ratings) {
  final data = <String, dynamic>{};
  _mapElo(ratings).forEach((cle, score) => data[cle] = score.toJson());
  return data;
}

String _empreinteDe(Map<String, double> ratings) =>
    empreinte64Ratings(_mapElo(ratings));

void _semerRatings(Map<String, double> ratings) {
  store.semer(kCleElo, jsonEncode(_payloadElo(ratings)));
}

void _semerRegistre(String valeur) => store.semer(kCleRegistre, valeur);

/// Registre LISIBLE et COHÉRENT avec [ratings], construit par le MODÈLE.
String _registreCoherent(Map<String, double> ratings) {
  final empreinte = _empreinteDe(ratings);
  return RegistreEloV3.vierge(empreinteRatings: empreinte).copyWith(
    empreinteRatings: empreinte,
    origine: OrigineRegistreElo.courante,
    entrees: const <EntreeRegistreElo>[],
  ).encoder();
}

/// Registre COHÉRENT portant en plus [entrees] et une `horloge` donnée.
/// Sert à prouver que l'ajout est APPEND-ONLY et que l'allocation progresse.
String _registreCoherentAvecEntrees({
  required Map<String, double> ratings,
  required List<EntreeRegistreElo> entrees,
  int horloge = 0,
  OrigineRegistreElo origine = OrigineRegistreElo.courante,
}) {
  final empreinte = _empreinteDe(ratings);
  return RegistreEloV3.vierge(empreinteRatings: empreinte).copyWith(
    empreinteRatings: empreinte,
    origine: origine,
    horloge: horloge,
    entrees: entrees,
  ).encoder();
}

/// Entrée INCERTAINE (jamais supprimable) de type `course`.
EntreeRegistreElo _entreeCourseIncertaine({required int id}) =>
    EntreeRegistreElo(
      id: id,
      type: TypeEntreeRegistre.course,
      cle: 'INCERTAIN|PLAT',
      numR: 1,
      numC: 1,
      date: '2026-04-17',
      discipline: 'PLAT',
      etape: EtapeEntreeRegistre.nonConfirmee,
      issue: IssueEcritureElo.echouee,
      tsIntention: 1776000000000,
      empreinteAvant: kEmpreinteVide,
      empreinteApres: kEmpreinteVide,
    );

/// Registre DIVERGENT : déclare l'empreinte d'une map VIDE, impossible à
/// confondre avec l'empreinte de ratings non vides. Divergence CONSTRUITE.
String _registreDivergent() =>
    RegistreEloV3.vierge(empreinteRatings: kEmpreinteVide).encoder();

/// Registre CORROMPU : JSON valide, champs obligatoires absents.
const String kRegistreCorrompu =
    '{"version":3,"operations":{"R1C1_20260417":{"etat":"temoin"}}}';

/// Registre INCOMPATIBLE : structure complète, `schema` étranger.
String _registreIncompatible() => jsonEncode(<String, dynamic>{
      'schema': 99,
      'version': 1,
      'horloge': 3,
      'empreinteRatings': kEmpreinteVide,
      'origine': 'courante',
      'entrees': <dynamic>[],
    });

/// Registre COHÉRENT dont une image porte `Infinity`, donc dont le
/// RÉ-ENCODAGE lève. Construit sur la valeur `1e400`, mesurée comme rendant
/// `double.infinity` — aucune valeur n'est inventée.
///
/// Le registre est lisible ET cohérent : le refus vient donc bien de la
/// sérialisation, pas du diagnostic.
String _registreCoherentAvecInfini(Map<String, double> ratings) {
  final empreinte = _empreinteDe(ratings);
  // ⚠️ CORRECTION MESURÉE : `jsonEncode` refuse d'encoder `Infinity`, donc
  //    construire la map en Dart puis l'encoder LEVAIT dans le harnais lui-même
  //    (trace : `Converting object to an encodable object failed: Infinity`,
  //    ligne 321). On écrit donc le littéral JSON `1e400`, dont la mesure a
  //    montré que `jsonDecode` le rend en `double.infinity`. Le registre obtenu
  //    est LISIBLE et COHÉRENT ; seul son RÉ-ENCODAGE lèvera.
  return '{"schema":3,"version":1,"horloge":1,'
      '"empreinteRatings":"$empreinte",'
      '"origine":"courante",'
      '"entrees":[{"id":5,"type":"course","etape":"appliquee",'
      '"issue":"persistee","tsIntention":1776000000000,'
      '"tsFinal":1776000000001,"empreinteAvant":"$empreinte",'
      '"empreinteApres":"$empreinte","cle":"INFINI|PLAT","numR":1,"numC":1,'
      '"date":"2026-04-17","discipline":"PLAT","chevaux":[{"cle":"INFINI|PLAT",'
      '"nom":"INFINI","avant":null,"apres":{"rating":1e400,"nb":3,"var":1.0}}]}]}';
}

/// Registre brut portant une `horloge` ou des `entrees` choisies — utilisé
/// pour éprouver l'ALLOCATEUR sur des registres anormaux mais décodables.
String _registreBrut({
  required String empreinte,
  int horloge = 0,
  List<Map<String, dynamic>> entrees = const <Map<String, dynamic>>[],
  String origine = 'courante',
}) =>
    jsonEncode(<String, dynamic>{
      'schema': 3,
      'version': 1,
      'horloge': horloge,
      'empreinteRatings': empreinte,
      'origine': origine,
      'entrees': entrees,
    });

Map<String, dynamic> _entreeHorsCourseBrute({
  required int id,
  String empreinte = kEmpreinteVide,
}) =>
    <String, dynamic>{
      'id': id,
      'type': 'horsCourse',
      'etape': 'appliquee',
      'issue': 'persistee',
      'tsIntention': 1776000000000,
      'tsFinal': 1776000000001,
      'empreinteAvant': empreinte,
      'empreinteApres': empreinte,
      'motif': 'importBackup',
      'nbChevauxAvant': 0,
      'nbChevauxApres': 0,
    };

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
  //  B2d2-1 — LE POINT DE CONTRÔLE UNIQUE REFUSE, ET RIEN N'EST ÉCRIT
  //
  //  Chaque refus a UN motif nommé. Aucun de ces cas ne doit écrire le
  //  registre, ni le modifier, ni le supprimer.
  // ═════════════════════════════════════════════════════════════════════════

  group('B2d2-1 — refus nommés du point de contrôle', () {
    /// Vérifie un scénario de refus : motif attendu, aucune écriture, valeur
    /// brute du registre INCHANGÉE, aucun témoin produit.
    Future<void> verifierRefus({
      required String libelle,
      required String? registreSeme,
      required MotifNonEcritureTemoin motifAttendu,
      Map<String, double> disque = const <String, double>{'ALPHA|PLAT': 1600.0},
      Map<String, double> importe = const <String, double>{'BETA|PLAT': 1500.0},
      void Function()? avant,
    }) async {
      _semerRatings(disque);
      if (registreSeme != null) _semerRegistre(registreSeme);
      avant?.call();

      final index = store.journal.length;
      final etat = await EloService.instance.importerDepuisBackup(
          _payloadElo(importe));
      await _laisserProgresser();

      final res = EloService.instance.dernierResultatImport!;
      // ignore: avoid_print
      print('[B2d2-1/$libelle] etat=${etat.name} | $res');

      expect(res.etatRatings, etat,
          reason: 'le résultat publie EXACTEMENT l\'état rendu à l\'appelant');
      expect(res.motifNonEcriture, motifAttendu);
      expect(res.issueTemoin, isNull,
          reason: 'aucun témoin n\'a été TENTÉ : l\'issue reste nulle');
      expect(res.operationSecurisee, isFalse);
      expect(store.clesEcritesDepuis(index).contains('flutter.$kCleRegistre'),
          isFalse,
          reason: 'le registre ne doit PAS être écrit dans ce scénario');
      expect(store.aSupprimeDepuis(index), isFalse,
          reason: 'le registre ne doit JAMAIS être supprimé par ce lot');
      if (registreSeme != null) {
        expect(store.lire(kCleRegistre), registreSeme,
            reason: 'la valeur brute du registre est INCHANGÉE');
      } else {
        expect(store.contient(kCleRegistre), isFalse,
            reason: 'aucun registre ne doit être CRÉÉ');
      }
    }

    test('1a — registre absent : motif registreAbsent', () async {
      await verifierRefus(
        libelle: 'absent',
        registreSeme: null,
        motifAttendu: MotifNonEcritureTemoin.registreAbsent,
      );
    });

    test('1b — registre divergent : motif dejaDivergent', () async {
      await verifierRefus(
        libelle: 'divergent',
        registreSeme: _registreDivergent(),
        motifAttendu: MotifNonEcritureTemoin.dejaDivergent,
      );
    });

    test('1c — registre corrompu : motif corrompu', () async {
      await verifierRefus(
        libelle: 'corrompu',
        registreSeme: kRegistreCorrompu,
        motifAttendu: MotifNonEcritureTemoin.corrompu,
      );
    });

    test('1d — registre incompatible : motif schemaIncompatible', () async {
      await verifierRefus(
        libelle: 'incompatible',
        registreSeme: _registreIncompatible(),
        motifAttendu: MotifNonEcritureTemoin.schemaIncompatible,
      );
    });

    test('1e — diagnostic non établi : motif diagnosticNonEtabli', () async {
      // La clé des ratings n'est pas textuelle : le diagnostic DOIT refuser
      // de s'établir, et l'absence de diagnostic ne doit JAMAIS autoriser.
      await verifierRefus(
        libelle: 'diagnosticNonEtabli',
        registreSeme: _registreCoherent(<String, double>{'ALPHA|PLAT': 1600.0}),
        motifAttendu: MotifNonEcritureTemoin.diagnosticNonEtabli,
        avant: () => store.semer(kCleElo, 42),
      );
    });

    test('1f — ratings non persistés : motif ratingsNonPersistes', () async {
      // Le registre est COHÉRENT et l'empreinte changerait : seul l'échec de
      // persistance des ratings doit provoquer le refus.
      store.refuse.add('flutter.$kCleElo');
      await verifierRefus(
        libelle: 'ratingsNonPersistes',
        registreSeme: _registreCoherent(<String, double>{'ALPHA|PLAT': 1600.0}),
        motifAttendu: MotifNonEcritureTemoin.ratingsNonPersistes,
      );
      final res = EloService.instance.dernierResultatImport!;
      expect(res.etatRatings, EtatPersistanceElo.refusee,
          reason: 'témoin : c\'est bien le refus de stockage qui a eu lieu');
      expect(res.ratingsSeulsPersistes, isFalse,
          reason: 'rien n\'est persisté, donc l\'état « à moitié sécurisé » '
              'ne doit pas être revendiqué non plus');
    });

    test('1g — import sans changement : motif aucunChangement', () async {
      const identique = <String, double>{'GAMMA|PLAT': 1500.0};
      await verifierRefus(
        libelle: 'aucunChangement',
        registreSeme: _registreCoherent(identique),
        motifAttendu: MotifNonEcritureTemoin.aucunChangement,
        disque: identique,
        importe: identique,
      );
      final res = EloService.instance.dernierResultatImport!;
      expect(res.empreinteAvant, res.empreinteApres,
          reason: 'témoin : les deux empreintes sont IDENTIQUES par '
              'construction, ce qui rend `aucunChangement` incontestable');
      expect(res.etatRatings, EtatPersistanceElo.persistee,
          reason: 'témoin : les ratings sont bien persistés ici — le refus '
              'vient du seul critère « rien n\'a changé »');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2d2-2 — ÉCRITURE AUTORISÉE : CONTENU EXACT DU TÉMOIN
  // ═════════════════════════════════════════════════════════════════════════

  group('B2d2-2 — contenu du témoin écrit', () {
    test('2a — une entrée horsCourse/importBackup, appliquée et persistée',
        () async {
      const disque = <String, double>{'DELTA|PLAT': 1650.0, 'ECHO|PLAT': 1550.0};
      _semerRatings(disque);
      _semerRegistre(_registreCoherent(disque));

      final etat = await EloService.instance.importerDepuisBackup(
          _payloadElo(<String, double>{'FOXTROT|PLAT': 1400.0}));
      final res = EloService.instance.dernierResultatImport!;
      // ignore: avoid_print
      print('[B2d2-2a] etat=${etat.name} | $res');

      expect(etat, EtatPersistanceElo.persistee,
          reason: 'le retour d\'`importerDepuisBackup` est INCHANGÉ');
      expect(res.issueTemoin, IssueEcritureElo.persistee);
      expect(res.motifNonEcriture, isNull,
          reason: 'un motif nul SIGNIFIE « témoin persisté », jamais « rien à '
              'signaler » sur un échec');
      expect(res.operationSecurisee, isTrue,
          reason: 'les DEUX persistances ont été confirmées');

      final brut = store.lire(kCleRegistre);
      expect(brut, isA<String>(), reason: 'le registre doit être sur le disque');
      final relu = RegistreEloV3.decoder(brut! as String);

      expect(relu.entrees, hasLength(1),
          reason: 'le registre était vide, une seule entrée est ajoutée');
      final entree = relu.entrees.single;
      expect(entree.type, TypeEntreeRegistre.horsCourse);
      expect(entree.motif, MotifHorsCourse.importBackup);
      expect(entree.etape, EtapeEntreeRegistre.appliquee);
      expect(entree.issue, IssueEcritureElo.persistee,
          reason: 'l\'entrée n\'est écrite qu\'APRÈS confirmation des ratings');
      expect(entree.tsFinal, isNotNull,
          reason: 'invariant du modèle : `appliquee` exige `tsFinal` non nul');
      expect(entree.chevaux, isEmpty,
          reason: 'invariant du modèle : `horsCourse` n\'a AUCUNE image par '
              'cheval');
      expect(relu.origine, OrigineRegistreElo.historiqueInconnu,
          reason: 'jamais `courante` après un import');
      expect(res.origineAppliquee, OrigineRegistreElo.historiqueInconnu);
    });

    test('2b — l\'empreinte déclarée devient celle des ratings persistés',
        () async {
      const disque = <String, double>{'GOLF|PLAT': 1700.0};
      const importe = <String, double>{'HOTEL|PLAT': 1450.0};
      _semerRatings(disque);
      _semerRegistre(_registreCoherent(disque));

      await EloService.instance.importerDepuisBackup(_payloadElo(importe));

      final relu =
          RegistreEloV3.decoder(store.lire(kCleRegistre)! as String);
      final empreinteAttendue = _empreinteDe(importe);

      expect(relu.empreinteRatings, empreinteAttendue,
          reason: 'le registre doit décrire l\'état RÉELLEMENT persisté');
      expect(relu.empreinteRatings,
          empreinte64Ratings(EloService.instance.exporterPourBackup().map(
              (k, v) => MapEntry(k, EloScore.fromJson(v)))),
          reason: 'l\'empreinte déclarée est EXACTEMENT celle des ratings en '
              'mémoire persistée — vérification non circulaire');
      expect(EloService.instance.dernierResultatImport!.empreinteApres,
          empreinteAttendue);
    });

    test('2c — chaîne d\'empreintes : `avant` est celle que le registre '
        'déclarait, donc celle du DISQUE', () async {
      const disque = <String, double>{'INDIA|PLAT': 1620.0};
      const importe = <String, double>{'JULIET|PLAT': 1520.0};
      _semerRatings(disque);
      _semerRegistre(_registreCoherent(disque));

      // La RAM est volontairement DIFFÉRENTE du disque : si le témoin prenait
      // son « avant » dans la RAM, la chaîne serait rompue et ce test le
      // verrait.
      EloService.instance.chargerDepuisMapIsolate(
          _payloadElo(<String, double>{'RAMSEUL|PLAT': 1100.0}));

      await EloService.instance.importerDepuisBackup(_payloadElo(importe));

      final diag = EloService.instance.dernierDiagnosticPreImport!;
      final relu =
          RegistreEloV3.decoder(store.lire(kCleRegistre)! as String);
      final entree = relu.entrees.single;

      // ignore: avoid_print
      print('[B2d2-2c] diag.empreintePersistee=${diag.empreintePersistee} | '
          'entree.avant=${entree.empreinteAvant} | '
          'entree.apres=${entree.empreinteApres}');

      expect(diag.ramIdentiqueAuDisque, isFalse,
          reason: 'témoin : la RAM n\'était PAS le disque');
      expect(entree.empreinteAvant, _empreinteDe(disque),
          reason: 'l\'image « avant » est celle du DISQUE, jamais celle de la '
              'RAM remplacée');
      expect(entree.empreinteAvant, diag.empreintePersistee,
          reason: 'la chaîne exige l\'égalité avec ce que le registre '
              'déclarait déjà');
      expect(entree.empreinteAvant, isNot(_empreinteDe(<String, double>{
        'RAMSEUL|PLAT': 1100.0,
      })));
      expect(entree.empreinteApres, _empreinteDe(importe));
    });

    test('2d — APPEND-ONLY : une entrée incertaine survit intacte', () async {
      const disque = <String, double>{'KILO|PLAT': 1600.0};
      _semerRatings(disque);
      _semerRegistre(_registreCoherentAvecEntrees(
        ratings: disque,
        horloge: 7,
        entrees: <EntreeRegistreElo>[_entreeCourseIncertaine(id: 42)],
      ));

      await EloService.instance.importerDepuisBackup(
          _payloadElo(<String, double>{'LIMA|PLAT': 1500.0}));

      final relu =
          RegistreEloV3.decoder(store.lire(kCleRegistre)! as String);
      // ignore: avoid_print
      print('[B2d2-2d] ${relu.toString()} | horloge=${relu.horloge}');

      expect(relu.entrees, hasLength(2),
          reason: 'une entrée ajoutée, aucune supprimée');
      final ancienne = relu.entrees.first;
      expect(ancienne.id, 42, reason: 'l\'ancienne entrée est intacte');
      expect(ancienne.etape, EtapeEntreeRegistre.nonConfirmee,
          reason: 'une entrée INCERTAINE n\'est jamais normalisée ni purgée');
      expect(ancienne.issue, IssueEcritureElo.echouee,
          reason: 'ni son issue ni son absence de `tsFinal` ne sont réécrites');
      expect(ancienne.tsFinal, isNull);
      expect(relu.entreesIncertaines, hasLength(1),
          reason: 'le modèle confirme lui-même que l\'entrée reste incertaine');

      final neuve = relu.entrees.last;
      expect(neuve.type, TypeEntreeRegistre.horsCourse);
      expect(neuve.id, 43, reason: 'max(id) + 1, aucun identifiant réutilisé');
      expect(relu.horloge, 8, reason: 'horloge + 1, une unité par entrée');
    });

    test('2e — les cardinaux sont ceux du DISQUE avant, puis de l\'import',
        () async {
      const disque = <String, double>{
        'MIKE|PLAT': 1600.0,
        'NOVEMBER|PLAT': 1550.0,
        'OSCAR|PLAT': 1500.0,
      };
      const importe = <String, double>{'PAPA|PLAT': 1450.0};
      _semerRatings(disque);
      _semerRegistre(_registreCoherent(disque));
      // RAM délibérément vide de contenu : si le cardinal « avant » venait
      // d'elle, il vaudrait 1 au lieu de 3.
      EloService.instance.chargerDepuisMapIsolate(
          _payloadElo(<String, double>{'PAPA|PLAT': 1450.0}));

      await EloService.instance.importerDepuisBackup(_payloadElo(importe));

      final entree = RegistreEloV3.decoder(store.lire(kCleRegistre)! as String)
          .entrees
          .single;
      // ignore: avoid_print
      print('[B2d2-2e] avant=${entree.nbChevauxAvant} | '
          'après=${entree.nbChevauxApres}');

      expect(entree.nbChevauxAvant, 3,
          reason: 'le cardinal « avant » est celui des ratings PERSISTÉS');
      expect(entree.nbChevauxApres, 1,
          reason: 'un import REMPLACE la map, il ne fusionne pas');
    });

    test('2f — aucune protection anti-double-application n\'est revendiquée',
        () async {
      const disque = <String, double>{'QUEBEC|PLAT': 1650.0};
      _semerRatings(disque);
      _semerRegistre(_registreCoherent(disque));

      await EloService.instance.importerDepuisBackup(
          _payloadElo(<String, double>{'ROMEO|PLAT': 1550.0}));

      final res = EloService.instance.dernierResultatImport!;
      final diag = EloService.instance.dernierDiagnosticPreImport!;

      // ⚠️ CORRECTION AVANT EXÉCUTION (mon assertion initiale était fausse).
      //    Le registre semé est d'origine `courante` ET cohérent, donc
      //    `protegeContreDoubleApplication` vaut `true` AVANT l'import
      //    (modèle l.713-715 : `coherent && origine == courante`). C'est
      //    précisément ce qui rend la vérification suivante utile : le témoin
      //    fait PASSER le registre en `historiqueInconnu`, donc la protection
      //    tombe à `false` APRÈS — et c'est cette transition qui doit être
      //    démontrée, pas une absence de protection initiale inventée.
      expect(diag.protegeContreDoubleApplication, isTrue,
          reason: 'témoin de non-vacuité : la protection EXISTAIT avant');
      expect(diag.origine, OrigineRegistreElo.courante);

      expect(res.protegeApres, isFalse,
          reason: 'en `historiqueInconnu`, la protection est impossible PAR '
              'CONSTRUCTION : la revendiquer serait mentir. C\'est un FAIT '
              'mesuré, pas une omission.');
      expect(EloService.instance.dernierResultatImport!.operationSecurisee,
          isTrue,
          reason: 'les deux persistances ont réussi — ce qui ne doit jamais '
              'être lu comme une protection');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2d2-3 — ALLOCATION : PROGRESSION, COLLISION, DÉBORDEMENT
  // ═════════════════════════════════════════════════════════════════════════

  group('B2d2-3 — allocation des identifiants', () {
    test('3a — registre vide : id 0 et horloge 0 + 1', () async {
      const disque = <String, double>{'SIERRA|PLAT': 1600.0};
      _semerRatings(disque);
      _semerRegistre(_registreCoherent(disque));

      await EloService.instance.importerDepuisBackup(
          _payloadElo(<String, double>{'TANGO|PLAT': 1500.0}));

      final relu =
          RegistreEloV3.decoder(store.lire(kCleRegistre)! as String);
      expect(relu.entrees.single.id, 0);
      expect(relu.horloge, 1,
          reason: '`vierge()` part de 0 : la première entrée donne 1');
    });

    test('3b — deux imports successifs : aucun identifiant réutilisé',
        () async {
      const disque = <String, double>{'UNIFORM|PLAT': 1600.0};
      _semerRatings(disque);
      _semerRegistre(_registreCoherent(disque));

      final elo = EloService.instance;
      await elo.importerDepuisBackup(
          _payloadElo(<String, double>{'VICTOR|PLAT': 1610.0}));
      final premier = elo.dernierResultatImport!;
      expect(premier.issueTemoin, IssueEcritureElo.persistee);

      // Le second import part du registre écrit par le premier. La RAM est
      // resynchronisée sur le disque pour que la chaîne reste cohérente.
      elo.chargerDepuisMapIsolate(
          _payloadElo(<String, double>{'VICTOR|PLAT': 1610.0}));
      await elo.importerDepuisBackup(
          _payloadElo(<String, double>{'WHISKY|PLAT': 1520.0}));
      final second = elo.dernierResultatImport!;

      final relu =
          RegistreEloV3.decoder(store.lire(kCleRegistre)! as String);
      // ignore: avoid_print
      print('[B2d2-3b] ids=${relu.entrees.map((e) => e.id).toList()} | '
          'horloge=${relu.horloge} | second=$second');

      expect(relu.entrees.map((e) => e.id).toList(), <int>[0, 1],
          reason: 'suite STRICTEMENT croissante : `entreePourCle` élit la plus '
              'récente par `id >`, donc l\'unicité est structurante');
      expect(relu.entrees.map((e) => e.id).toSet(), hasLength(2),
          reason: 'aucune collision');
      expect(relu.horloge, 2, reason: 'une unité d\'horloge par entrée');
      expect(second.issueTemoin, IssueEcritureElo.persistee,
          reason: 'le second import est autorisé : le registre est cohérent');
    });

    test('3c — identifiant NÉGATIF présent : motif allocationImpossible',
        () async {
      const disque = <String, double>{'XRAY|PLAT': 1600.0};
      _semerRatings(disque);
      final registre = _registreBrut(
        empreinte: _empreinteDe(disque),
        horloge: 2,
        entrees: <Map<String, dynamic>>[_entreeHorsCourseBrute(id: -1)],
      );
      _semerRegistre(registre);

      final index = store.journal.length;
      final etat = await EloService.instance.importerDepuisBackup(
          _payloadElo(<String, double>{'YANKEE|PLAT': 1500.0}));
      final res = EloService.instance.dernierResultatImport!;
      // ignore: avoid_print
      print('[B2d2-3c] etat=${etat.name} | $res');

      expect(res.etatRatings, EtatPersistanceElo.persistee,
          reason: 'les ratings, eux, ont bien été persistés');
      expect(res.issueTemoin, isNull);
      expect(res.motifNonEcriture, MotifNonEcritureTemoin.allocationImpossible,
          reason: 'un registre portant un id négatif est SUSPECT : refus, pas '
              'devinette');
      expect(res.ratingsSeulsPersistes, isTrue,
          reason: 'état « à moitié sécurisé » : il ne doit jamais être '
              'présenté comme un succès complet');
      expect(store.lire(kCleRegistre), registre,
          reason: 'le registre anormal est PRÉSERVÉ tel quel');
      expect(store.clesEcritesDepuis(index).contains('flutter.$kCleRegistre'),
          isFalse);
    });

    test('3d — horloge à la borne : motif allocationImpossible', () async {
      const disque = <String, double>{'ZULU|PLAT': 1600.0};
      _semerRatings(disque);
      final registre = _registreBrut(
        empreinte: _empreinteDe(disque),
        horloge: kHorlogeMax,
      );
      _semerRegistre(registre);

      final etat = await EloService.instance.importerDepuisBackup(
          _payloadElo(<String, double>{'ANCHOR|PLAT': 1500.0}));
      final res = EloService.instance.dernierResultatImport!;
      // ignore: avoid_print
      print('[B2d2-3d] etat=${etat.name} | $res');

      expect(res.etatRatings, EtatPersistanceElo.persistee);
      expect(res.motifNonEcriture, MotifNonEcritureTemoin.allocationImpossible,
          reason: '`horloge + 1` cesserait d\'être exactement représentable : '
              'on n\'écrit pas un identifiant faux');
      expect(store.lire(kCleRegistre), registre);
    });

    test('3e — horloge négative : motif allocationImpossible', () async {
      const disque = <String, double>{'BRAVO2|PLAT': 1600.0};
      _semerRatings(disque);
      final registre = _registreBrut(
        empreinte: _empreinteDe(disque),
        horloge: -3,
      );
      _semerRegistre(registre);

      await EloService.instance.importerDepuisBackup(
          _payloadElo(<String, double>{'CHARLIE2|PLAT': 1500.0}));
      final res = EloService.instance.dernierResultatImport!;

      expect(res.motifNonEcriture, MotifNonEcritureTemoin.allocationImpossible,
          reason: 'une horloge négative n\'est pas un registre sain');
      expect(store.lire(kCleRegistre), registre);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2d2-4 — ÉCHECS DE L'ÉCRITURE DU TÉMOIN
  //
  //  Trois familles distinctes, et il faut les distinguer : refus explicite du
  //  stockage, exception, sérialisation impossible. Les confondre rendrait le
  //  diagnostic d'incident inutilisable.
  // ═════════════════════════════════════════════════════════════════════════

  group('B2d2-4 — échecs d\'écriture du témoin', () {
    test('4a — refus explicite du stockage : refusee + refuseeParStockage',
        () async {
      const disque = <String, double>{'DELTA2|PLAT': 1600.0};
      _semerRatings(disque);
      final registre = _registreCoherent(disque);
      _semerRegistre(registre);
      store.refuse.add('flutter.$kCleRegistre');

      final etat = await EloService.instance.importerDepuisBackup(
          _payloadElo(<String, double>{'ECHO2|PLAT': 1500.0}));
      final res = EloService.instance.dernierResultatImport!;
      // ignore: avoid_print
      print('[B2d2-4a] etat=${etat.name} | $res');

      expect(etat, EtatPersistanceElo.persistee,
          reason: 'le retour principal ne change PAS : c\'est le résultat '
              'composite qui porte l\'échec du témoin');
      expect(res.issueTemoin, IssueEcritureElo.refusee);
      expect(res.motifNonEcriture, MotifNonEcritureTemoin.refuseeParStockage);
      expect(res.operationSecurisee, isFalse);
      expect(res.ratingsSeulsPersistes, isTrue);
      expect(res.origineAppliquee, isNull,
          reason: 'aucune origine n\'est appliquée puisque rien n\'a été écrit');
      expect(store.lire(kCleRegistre), registre,
          reason: 'le registre existant n\'est PAS prouvé inchangé par un '
              'refus, mais il est bien resté la valeur d\'origine ici');
    });

    test('4b — exception du stockage : echouee + echoueeParException',
        () async {
      const disque = <String, double>{'FOXTROT2|PLAT': 1600.0};
      _semerRatings(disque);
      final registre = _registreCoherent(disque);
      _semerRegistre(registre);
      store.leve.add('flutter.$kCleRegistre');

      await EloService.instance.importerDepuisBackup(
          _payloadElo(<String, double>{'GOLF2|PLAT': 1500.0}));
      final res = EloService.instance.dernierResultatImport!;
      // ignore: avoid_print
      print('[B2d2-4b] $res');

      expect(res.issueTemoin, IssueEcritureElo.echouee);
      expect(res.motifNonEcriture, MotifNonEcritureTemoin.echoueeParException,
          reason: 'une exception n\'est PAS un refus : les deux motifs sont '
              'distincts et le restent');
      expect(res.operationSecurisee, isFalse);
      expect(store.lire(kCleRegistre), registre);
    });

    test('4c — sérialisation impossible : serialisationImpossible', () async {
      const disque = <String, double>{'HOTEL2|PLAT': 1600.0};
      _semerRatings(disque);
      // Registre LISIBLE et COHÉRENT, mais dont une image vaut `Infinity` :
      // le diagnostic passe, c'est le ré-encodage qui lève.
      final registre = _registreCoherentAvecInfini(disque);
      _semerRegistre(registre);

      final index = store.journal.length;
      final etat = await EloService.instance.importerDepuisBackup(
          _payloadElo(<String, double>{'INDIA2|PLAT': 1500.0}));
      final res = EloService.instance.dernierResultatImport!;
      // ignore: avoid_print
      print('[B2d2-4c] etat=${etat.name} | $res');

      expect(res.etatRatings, EtatPersistanceElo.persistee);
      expect(res.coherenceAvant, DiagnosticCoherenceElo.coherent,
          reason: 'témoin DÉCISIF : le registre était cohérent, donc le refus '
              'ne vient PAS du diagnostic mais de la sérialisation');
      expect(res.issueTemoin, isNull,
          reason: 'rien n\'a été TENTÉ : l\'exception précède l\'écriture');
      expect(res.motifNonEcriture,
          MotifNonEcritureTemoin.serialisationImpossible);
      expect(store.clesEcritesDepuis(index).contains('flutter.$kCleRegistre'),
          isFalse);
      expect(store.lire(kCleRegistre), registre,
          reason: 'le registre est PRÉSERVÉ, jamais réparé');
    });

    test('4d — un échec du témoin ne fait jamais échouer l\'import', () async {
      const disque = <String, double>{'JULIET2|PLAT': 1600.0};
      const importe = <String, double>{'KILO2|PLAT': 1400.0};
      _semerRatings(disque);
      _semerRegistre(_registreCoherent(disque));
      store.leve.add('flutter.$kCleRegistre');

      final etat = await EloService.instance.importerDepuisBackup(
          _payloadElo(importe));
      await _laisserProgresser();

      expect(etat, EtatPersistanceElo.persistee,
          reason: 'le contrat de retour est INCHANGÉ : l\'échec du témoin ne '
              'dégrade pas la persistance des ratings');
      expect(EloService.instance.nbChevauxSuivis, 1);
      expect(EloService.instance.exporterPourBackup().keys.toSet(),
          importe.keys.toSet(),
          reason: 'les ratings importés sont bien ceux de la charge utile');
      expect(EloService.instance.nbEcrituresPersistantesEnCours, 0,
          reason: 'le suivi est vidé, même quand l\'écriture a levé');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2d2-5 — SUIVI DES ÉCRITURES : LE TÉMOIN COMPTE DANS LE SEUL ENSEMBLE
  //            PERSISTANT
  //
  //  Exigence d'arbitrage n°2 : `_ecrituresEnCours` garde exactement sa
  //  signification B2-a. C'est ce groupe qui le PROUVE, et non le commentaire.
  // ═════════════════════════════════════════════════════════════════════════

  group('B2d2-5 — suivi et drain', () {
    test('5a — pendant l\'écriture du témoin : 0 historique, 1 persistante',
        () async {
      const disque = <String, double>{'LIMA2|PLAT': 1600.0};
      _semerRatings(disque);
      _semerRegistre(_registreCoherent(disque));

      final entree = store.armerSuspension('flutter.$kCleRegistre');
      final future = EloService.instance.importerDepuisBackup(
          _payloadElo(<String, double>{'MIKE2|PLAT': 1500.0}));
      await entree;

      final elo = EloService.instance;
      // ignore: avoid_print
      print('[B2d2-5a] pendant : historiques=${elo.nbEcrituresEnCours} | '
          'persistentes=${elo.nbEcrituresPersistantesEnCours}');

      expect(elo.nbEcrituresEnCours, 0,
          reason: 'l\'écriture des ratings est TERMINÉE : le compteur '
              'HISTORIQUE doit être vide. Le témoin ne doit PAS y entrer.');
      expect(elo.nbEcrituresPersistantesEnCours, 1,
          reason: 'le témoin est en vol et doit être vu par le drain');

      store.libererSuspension();
      final etat = await future;
      await _laisserProgresser();

      expect(etat, EtatPersistanceElo.persistee);
      expect(elo.nbEcrituresEnCours, 0);
      expect(elo.nbEcrituresPersistantesEnCours, 0,
          reason: 'le suivi est vidé après l\'écriture');
    });

    test('5b — le drain ATTEND le témoin, puis efface : aucune résurrection',
        () async {
      const disque = <String, double>{'NOVEMBER2|PLAT': 1600.0};
      _semerRatings(disque);
      _semerRegistre(_registreCoherent(disque));

      final entree = store.armerSuspension('flutter.$kCleRegistre');
      final future = EloService.instance.importerDepuisBackup(
          _payloadElo(<String, double>{'OSCAR2|PLAT': 1500.0}));
      await entree;

      var effacements = 0;
      var resetTermine = false;
      final reset = EloService.instance.executerResetComplet(() async {
        effacements++;
        // ★ CORRECTION B2-d2 : les clés du store sont indexées AVEC le préfixe
        //   `flutter.` (`semer` fait `_valeurs['flutter.$cle']`). Les versions
        //   précédentes passaient `kCleElo` / `kCleRegistre` SANS préfixe :
        //   `remove` ne supprimait donc RIEN, et le test échouait sur une
        //   assertion qui accusait à tort la production. Le harnais est
        //   désormais aligné sur le modèle de clés du store.
        await store.remove('flutter.$kCleElo');
        await store.remove('flutter.$kCleTs');
        await store.remove('flutter.$kCleRegistre');
      });
      reset.whenComplete(() => resetTermine = true).ignore();

      await _laisserProgresser();

      // ignore: avoid_print
      print('[B2d2-5b] pendant : effacements=$effacements | '
          'resetTermine=$resetTermine | '
          'persistentes=${EloService.instance.nbEcrituresPersistantesEnCours}');

      expect(resetTermine, isFalse,
          reason: 'TÉMOIN DU DRAIN : le reset ne peut pas se terminer tant que '
              'l\'écriture du registre est en vol');
      expect(effacements, 0,
          reason: 'aucune suppression ne commence avant la libération');

      store.libererSuspension();
      await future;
      await reset;
      await _laisserProgresser();

      // ignore: avoid_print
      print('[B2d2-5b] après : effacements=$effacements | '
          'registre=${store.contient(kCleRegistre)}');

      expect(effacements, 1, reason: 'ANTI-BLOCAGE : le drain a abouti');
      expect(store.contient(kCleRegistre), isFalse,
          reason: 'AUCUNE RÉSURRECTION : l\'écriture drainée ne recrée pas la '
              'clé après son effacement (transposition de V29-A)');
      expect(EloService.instance.nbEcrituresPersistantesEnCours, 0);
      expect(EloService.instance.nbEcrituresEnCours, 0);
    });

    test('5c — reset démarré pendant la persistance des ratings : le témoin '
        'est ABANDONNÉ et rien n\'est recréé', () async {
      const disque = <String, double>{'PAPA2|PLAT': 1600.0};
      _semerRatings(disque);
      _semerRegistre(_registreCoherent(disque));

      final entree = store.armerSuspension('flutter.$kCleElo');
      final future = EloService.instance.importerDepuisBackup(
          _payloadElo(<String, double>{'QUEBEC2|PLAT': 1500.0}));
      await entree;

      // Le reset démarre pendant que les ratings sont en vol : sa barrière
      // incrémente la génération AVANT le drain.
      // ★ CORRECTION B2-d2 : préfixe `flutter.` requis (voir 5b).
      final reset = EloService.instance.executerResetComplet(() async {
        await store.remove('flutter.$kCleElo');
        await store.remove('flutter.$kCleTs');
        await store.remove('flutter.$kCleRegistre');
      });

      store.libererSuspension();
      await future;
      await reset;
      await _laisserProgresser();

      final res = EloService.instance.dernierResultatImport;
      // ignore: avoid_print
      print('[B2d2-5c] res=$res | registre=${store.contient(kCleRegistre)}');

      expect(res, isNotNull,
          reason: 'l\'import est allé jusqu\'à publier un résultat');
      expect(res!.etatRatings, EtatPersistanceElo.persistee,
          reason: 'l\'écriture des ratings était déjà engagée et a abouti');
      expect(res.issueTemoin, isNull);
      expect(res.motifNonEcriture, MotifNonEcritureTemoin.abandonneParReset,
          reason: 'le contrôle de génération refuse AVANT d\'écrire : écrire '
              'recréerait la clé qu\'un reset est en train d\'effacer');
      expect(store.contient(kCleRegistre), isFalse,
          reason: 'le registre reste effacé');
      expect(res.operationSecurisee, isFalse,
          reason: 'seule la sauvegarde des ratings a réussi : l\'opération '
              'entière ne doit JAMAIS être déclarée sécurisée');
      expect(res.ratingsSeulsPersistes, isTrue);
    });

    test('5d — une écriture en échec est retirée du suivi épuisé', () async {
      const disque = <String, double>{'ROMEO2|PLAT': 1600.0};
      _semerRatings(disque);
      _semerRegistre(_registreCoherent(disque));
      store.leve.add('flutter.$kCleRegistre');

      await EloService.instance.importerDepuisBackup(
          _payloadElo(<String, double>{'SIERRA2|PLAT': 1500.0}));
      await _laisserProgresser();

      expect(EloService.instance.nbEcrituresPersistantesEnCours, 0,
          reason: 'un échec ne doit pas laisser une future fantôme dans le '
              'suivi — sinon le drain suivant boucle sur une erreur');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2d2-6 — BRANCHES « DIAGNOSTIC NON ÉTABLI »
  //
  //  Une lecture qui échoue ne doit jamais produire `coherent`. Chaque branche
  //  est éprouvée séparément, et le motif exact est vérifié.
  // ═════════════════════════════════════════════════════════════════════════

  group('B2d2-6 — diagnostic non établi', () {
    /// Vérifie qu'un diagnostic non établi REFUSE le témoin et n'écrit rien.
    Future<void> verifierNonEtabli(String libelle, String motifAttendu) async {
      const disque = <String, double>{'TANGO2|PLAT': 1600.0};
      _semerRatings(disque);
      _semerRegistre(_registreCoherent(disque));
      final index = store.journal.length;

      final etat = await EloService.instance.importerDepuisBackup(
          _payloadElo(<String, double>{'UNIFORM2|PLAT': 1500.0}));
      await _laisserProgresser();

      final diag = EloService.instance.dernierDiagnosticPreImport;
      final res = EloService.instance.dernierResultatImport!;
      // ignore: avoid_print
      print('[B2d2-6/$libelle] etat=${etat.name} | diag=$diag | res=$res');

      expect(diag, isNotNull);
      expect(diag!.etabli, isFalse);
      expect(diag.etablissementImpossible, contains(motifAttendu),
          reason: 'la raison EXACTE doit être conservée, jamais résumée');
      expect(diag.coherence, isNull,
          reason: 'un diagnostic non établi n\'a AUCUNE cohérence — surtout '
              'pas `coherent` par défaut');
      expect(res.motifNonEcriture, MotifNonEcritureTemoin.diagnosticNonEtabli,
          reason: 'l\'absence de diagnostic ne doit JAMAIS autoriser une '
              'écriture');
      expect(res.issueTemoin, isNull);
      expect(store.clesEcritesDepuis(index).contains('flutter.$kCleRegistre'),
          isFalse);
      expect(store.contient(kCleRegistre), isTrue,
          reason: 'le registre semé reste présént : rien n\'est supprimé');
    }

    test('6a — `getInstance()` lève : SharedPreferences indisponible',
        () async {
      // Le cache est invalidé pour forcer un vrai `getInstance()` qui lira.
      SharedPreferences.resetStatic();
      store.leverProchaineLecture();
      await verifierNonEtabli('getInstance', 'SharedPreferences indisponible');
    });

    test('6b — `reload()` lève : cache non actualisé', () async {
      // ★ CORRECTION B2-d2 (défaut mesuré).
      //   Version précédente : le cache était laissé intact en croyant que
      //   `getInstance()` ne lirait pas. FAUX — `getInstance()` a CONSOMMÉ la
      //   lecture suspendue, et l'échec est survenu dans la branche
      //   « SharedPreferences indisponible », jamais dans « reload() ».
      //   Le test était donc vert par accident sur un autre chemin.
      //
      //   Pour atteindre RÉELLEMENT `reload()`, il faut que le cache soit
      //   PEUPLÉ (donc `getInstance()` réussit sans lire) tout en gardant un
      //   `_prefsFuture` valide. On matérialise donc ce cache AVANT d'armer
      //   l'échec de lecture.
      final prefs = await SharedPreferences.getInstance();
      // Témoin : le cache est bien peuplé, donc `getInstance()` répondra sans
      // passer par le store.
      expect(prefs.getKeys(), isNotNull);

      // À partir d'ici, seule la PROCHAINE lecture du store échouera : c'est
      // exactement celle de `reload()`.
      store.leverProchaineLecture();
      await verifierNonEtabli('reload', 'reload() impossible');
    });

    test('6c — `_prefsKey` porte un objet JSON : diagnostic refusé', () async {
      const disque = <String, double>{'VICTOR2|PLAT': 1600.0};
      _semerRatings(disque);
      _semerRegistre(_registreCoherent(disque));
      // Un tableau JSON n'est pas un objet : la lecture doit le DIRE.
      store.semer(kCleElo, '[1,2,3]');

      final index = store.journal.length;
      await EloService.instance.importerDepuisBackup(
          _payloadElo(<String, double>{'WHISKY2|PLAT': 1500.0}));

      final diag = EloService.instance.dernierDiagnosticPreImport!;
      final res = EloService.instance.dernierResultatImport!;
      // ignore: avoid_print
      print('[B2d2-6c] diag=$diag | res=$res');

      expect(diag.etabli, isFalse);
      expect(diag.etablissementImpossible, contains('objet JSON attendu'));
      expect(res.motifNonEcriture, MotifNonEcritureTemoin.diagnosticNonEtabli);
      expect(store.clesEcritesDepuis(index).contains('flutter.$kCleRegistre'),
          isFalse);
    });

    test('6d — `_prefsKey` illisible : diagnostic refusé', () async {
      const disque = <String, double>{'XRAY2|PLAT': 1600.0};
      _semerRatings(disque);
      _semerRegistre(_registreCoherent(disque));
      store.semer(kCleElo, '{ceci n\'est pas du JSON');

      await EloService.instance.importerDepuisBackup(
          _payloadElo(<String, double>{'YANKEE2|PLAT': 1500.0}));

      final diag = EloService.instance.dernierDiagnosticPreImport!;
      final res = EloService.instance.dernierResultatImport!;
      // ignore: avoid_print
      print('[B2d2-6d] diag=$diag | res=$res');

      expect(diag.etabli, isFalse);
      expect(diag.etablissementImpossible, contains('JSON illisible'));
      expect(res.motifNonEcriture, MotifNonEcritureTemoin.diagnosticNonEtabli);
    });

    test('6e — `kCleRegistreElo` non textuelle : diagnostic refusé', () async {
      const disque = <String, double>{'ZULU2|PLAT': 1600.0};
      _semerRatings(disque);
      store.semer(kCleRegistre, 42);

      final index = store.journal.length;
      await EloService.instance.importerDepuisBackup(
          _payloadElo(<String, double>{'ANCHOR2|PLAT': 1500.0}));

      final diag = EloService.instance.dernierDiagnosticPreImport!;
      final res = EloService.instance.dernierResultatImport!;
      // ignore: avoid_print
      print('[B2d2-6e] diag=$diag | res=$res');

      expect(diag.etabli, isFalse);
      expect(diag.etablissementImpossible,
          contains('n\'est pas une chaîne'));
      expect(res.motifNonEcriture, MotifNonEcritureTemoin.diagnosticNonEtabli);
      expect(store.lire(kCleRegistre), 42,
          reason: 'la valeur non textuelle est PRÉSERVÉE, ni écrasée ni réparée');
      expect(store.clesEcritesDepuis(index).contains('flutter.$kCleRegistre'),
          isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2d2-7 — AUCUNE CLÉ NOUVELLE, AUCUN COMPTEUR DÉTOURNÉ
  // ═════════════════════════════════════════════════════════════════════════

  group('B2d2-7 — périmètre du stockage et des compteurs', () {
    test('7a — aucun témoin ne crée de clé hors des trois clés ELO', () async {
      const disque = <String, double>{'BRAVO3|PLAT': 1600.0};
      _semerRatings(disque);
      _semerRegistre(_registreCoherent(disque));

      final index = store.journal.length;
      await EloService.instance.importerDepuisBackup(
          _payloadElo(<String, double>{'CHARLIE3|PLAT': 1500.0}));
      await _laisserProgresser();

      expect(store.clesEcritesDepuis(index), <String>{
        'flutter.$kCleElo',
        'flutter.$kCleTs',
        'flutter.$kCleRegistre',
      }, reason: 'trois clés, toutes préexistantes : AUCUNE clé ajoutée');
    });

    test('7b — les compteurs de persistance gardent leur sémantique', () async {
      const disque = <String, double>{'DELTA3|PLAT': 1600.0};
      _semerRatings(disque);
      _semerRegistre(_registreCoherent(disque));
      final elo = EloService.instance;

      final persistees = elo.nbPersistees;
      final refusees = elo.nbRefuseesStockage;
      final echouees = elo.nbEchouees;
      final refusReset = elo.nbRefusParReset;
      final refusGen = elo.nbRefusParGeneration;

      await elo.importerDepuisBackup(
          _payloadElo(<String, double>{'ECHO3|PLAT': 1500.0}));
      await _laisserProgresser();

      expect(elo.nbPersistees, persistees + 1,
          reason: 'seule la persistance des RATINGS est comptée ici');
      expect(elo.nbRefuseesStockage, refusees,
          reason: 'le témoin a réussi : aucun refus à compter');
      expect(elo.nbEchouees, echouees);
      expect(elo.nbRefusParReset, refusReset);
      expect(elo.nbRefusParGeneration, refusGen,
          reason: 'l\'écriture du témoin n\'entre PAS dans `_sauvegarder` : '
              'elle ne peut pas gonfler ces compteurs');
      expect(elo.nbAbandonsFileParGeneration, 0);
    });

    test('7c — `dernierResultatImport` repart à null au début de chaque import',
        () async {
      const disque = <String, double>{'FOXTROT3|PLAT': 1600.0};
      _semerRatings(disque);
      _semerRegistre(_registreCoherent(disque));
      final elo = EloService.instance;

      await elo.importerDepuisBackup(
          _payloadElo(<String, double>{'GOLF3|PLAT': 1500.0}));
      final premier = elo.dernierResultatImport;
      expect(premier, isNotNull);

      await elo.importerDepuisBackup(
          _payloadElo(<String, double>{'HOTEL3|PLAT': 1510.0}));
      final second = elo.dernierResultatImport;

      expect(identical(premier, second), isFalse,
          reason: 'le champ est REMPLACÉ, jamais conservé');
    });
  });
}
