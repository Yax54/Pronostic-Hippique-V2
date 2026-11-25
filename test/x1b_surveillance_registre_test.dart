// ═══════════════════════════════════════════════════════════════════════════
//  X1-b-code — SURVEILLANCE DE LA TAILLE DU REGISTRE ELO
//
//  OBJET
//  ─────
//  Prouver que la surveillance ajoutée à `elo_service.dart` :
//    • NE MODIFIE RIEN — ni entrée, ni image avant/après, ni empreinte, ni
//      décision de blocage, ni résultat ELO ;
//    • NE SUPPRIME RIEN — aucune compaction, aucune purge ;
//    • N'INTRODUIT AUCUN REFUS, même au niveau `saturation` ;
//    • N'AJOUTE AUCUNE CLÉ SharedPreferences ;
//    • MESURE EXACTEMENT au chargement, et ESTIME (minorant) après écriture ;
//    • REDESCEND après une restauration plus petite, MONTE après une plus
//      volumineuse, est RECALCULÉE depuis le stockage après redémarrage,
//      REVIENT à `normal` après un reset complet ;
//    • ne déclare « exact » que ce qui l'est réellement.
//
//  ⚠️ QUATRE FAITS MESURÉS QUI GOUVERNENT CE HARNAIS (lus dans le code réel)
//  ─────────────────────────────────────────────────────────────────────────
//  1) P1 (`_hydraterNiveauRegistre`) est dans `_chargerOuAmorcerRegistre`
//     (l.1451). Ce chemin est atteint par `mettreAJourApresArrivee` APRÈS les
//     retours « rien à faire » de l.2824 (`partants.isEmpty`) et l.2835
//     (`arrivee.length < 2`) et APRÈS le refus d'identité de l.2850.
//     ⇒ Un appel SANS `courseKey`, ou avec moins de 2 partants ou moins de
//       2 arrivants, n'exécute JAMAIS P1. Le harnais appelle donc TOUJOURS
//       avec une identité VALIDE, 2 partants et 2 arrivants.
//
//  2) Le format de `courseKey` est contraint par `dateDepuisCourseKey`
//     (`date_utils.dart` l.145-170) : `R{numR}C{numC}_{jjmmaaaa}` OU
//     `R{numR}C{numC}_{AAAA-MM-JJ}`, avec numR >= 1 et numC >= 1
//     (`IdentiteCourseElo.tenter`, l.180-213).
//     ⚠️ PIÈGE MESURÉ : `20240510` est lu au format `jjmmaaaa` (jour=20,
//        mois=24) => date invalide => `null` => `identiteNonExploitable`
//        => P1 jamais atteint. Il faut `10052024`, ou la forme ISO.
//     Le harnais utilise donc `R$rC$c_10052024`.
//
//  3) Une application n'est POSSIBLE que si le registre est `coherent` :
//     `registre.empreinteRatings == empreinte64Ratings(ratings du disque)`
//     (`elo_registre_v3.dart` l.812-820). Un registre dont l'empreinte est
//     arbitraire rend `divergent` => `registreNonCoherent` => `nonTentee` et
//     AUCUNE écriture. Le harnais sème donc une empreinte CALCULÉE depuis les
//     ratings réellement posés.
//
//  4) `_charge` n'est JAMAIS remis à `false` par une API publique
//     (le vidage l.4286 ne vide que `_ratings` ; `EloService._()` est privé,
//     l.846). Un « redémarrage » ne peut donc PAS être simulé sur l'instance
//     singleton. Le harnais ne le prétend pas : il mesure une mémoire vidée
//     **plus un stockage neuf et identique**, ce qui force P1 à recalculer
//     depuis le stockage — c'est la propriété exigée, sur un état d'entrée
//     identique.
//
//  ⚠️ CE QUE CES TESTS N'ASSERTENT JAMAIS
//  ──────────────────────────────────────
//  • Le store est EN MÉMOIRE : `setString → true` ne prouve aucune écriture
//    physique sur disque Android. Aucune assertion ne prétend le contraire.
//  • Les compteurs comptent les appels RÉELS au store instrumenté ; ils ne
//    prétendent pas prouver l'absence de tout travail interne au SDK.
//
//  PORTÉE : aucun test ne touche aux formules ELO, coefficients K, poids,
//  seuils IA, TOP3, gradient descent ou critères A–Q.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/elo_registre_v3.dart'
    show
        ChevalJournalise,
        EntreeRegistreElo,
        EtapeEntreeRegistre,
        ImageRatingElo,
        IssueEcritureElo,
        NiveauRetentionElo,
        OrigineRegistreElo,
        RegistreEloV3,
        TypeEntreeRegistre,
        classerRetention,
        kSeuilAlerteOctets,
        kSeuilSaturationOctets,
        kSeuilVeilleOctets;
import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/utils/elo_empreinte.dart'
    show octetsUtf8, empreinte64Ratings;

const String kCleElo = 'elo_ratings_v2';
const String kCleTs = 'elo_ratings_v2_ts';
const String kCleRegistre = 'elo_registre_v3';

/// Marqueur de portée enrichie dans le groupe `elo_service` d'une sauvegarde
/// (`elo_service.dart` l.749). Sans lui, `_importerDepuisBackup` prend le
/// chemin HISTORIQUE et la restitution verbatim (P4) n'est jamais atteinte.
const String kMarqueurRegistre = '_elo_registre';

/// Date franchement passée, au format `jjmmaaaa` réellement attendu par
/// `dateDepuisCourseKey` : `10052024` = 10/05/2024, donc 2024-05-10.
///
/// ⚠️ PIÈGE MESURÉ : `20240510` est lu comme jour=20, mois=24 — une date
///    INVALIDE, qui rend `null` et fait refuser l'identité.
const String kDatePassee = '10052024';

/// Course dont le registre semé contient DÉJÀ une entrée `appliquee`.
///
/// C'est le seul moyen d'OBSERVER sans écrire : l'appel traverse P1 (mesure
/// exacte) puis est refusé par `entreePourCle` AVANT toute mutation. Un appel
/// avec une course NOUVELLE, lui, applique réellement et écrit le registre.
const String kCleRefus = 'R99C99_10052024';

// ───────────────────────────────────────────────────────────────────────────
//  STORE INSTRUMENTÉ — même contrat que a7_32b / a7_33b2b
// ───────────────────────────────────────────────────────────────────────────

class _Store extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};
  final List<String> journal = <String>[];

  final Set<String> refus = <String>{};
  final Set<String> levent = <String>{};

  /// Clés dont la SUPPRESSION doit être REFUSÉE : `remove()` rend `false` et
  /// la valeur RESTE stockée. C'est le mode d'échec SILENCIEUX décrit par le
  /// contrat C1-a de `backup_service.dart` : `SharedPreferences.remove()`
  /// vide d'abord son cache, PUIS appelle `_store.remove()` et rend son
  /// booléen tel quel — « le cache est donc déjà vidé même quand la
  /// suppression disque a échoué : la clé SURVIT sur le disque alors que la
  /// RAM croit le contraire ». C'est exactement le cas que X1b-5f doit
  /// couvrir, sans jamais contourner le chemin de production.
  final Set<String> refusRemove = <String>{};

  int nbGetAll = 0;
  int nbEcrituresRegistre = 0;
  int nbEcrituresElo = 0;

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
    nbGetAll++;
    final prefix = parameters.filter.prefix;
    return <String, Object>{
      for (final e in _valeurs.entries)
        if (e.key.startsWith(prefix)) e.key: e.value,
    };
  }

  @override
  Future<bool> remove(String key) async {
    journal.add('REM $key');
    if (refusRemove.contains(key)) {
      // Échec SILENCIEUX : la valeur survit, le booléen dit `false`.
      return false;
    }
    _valeurs.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    journal.add('SET $key');
    if (levent.contains(key)) {
      throw StateError('panne simulée sur $key');
    }
    if (refus.contains(key)) return false;
    if (key == 'flutter.$kCleRegistre') nbEcrituresRegistre++;
    if (key == 'flutter.$kCleElo') nbEcrituresElo++;
    _valeurs[key] = value;
    return true;
  }

  void poser(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;
  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');
  Object? lire(String cle) => _valeurs['flutter.$cle'];
  void effacer(String cle) => _valeurs.remove('flutter.$cle');

  Set<String> cles() => <String>{
        for (final k in _valeurs.keys)
          if (k.startsWith('flutter.')) k.substring('flutter.'.length),
      };

  void remettreCompteursAZero() {
    nbGetAll = 0;
    nbEcrituresRegistre = 0;
    nbEcrituresElo = 0;
    journal.clear();
  }
}

// ignore: library_private_types_in_public_api
late _Store _store;

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.tmpPath);
  final String tmpPath;
  @override
  Future<String?> getTemporaryPath() async => tmpPath;
}

class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this._result);
  final FilePickerResult? _result;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      _result;
}

void _installerStore() {
  _store = _Store();
  SharedPreferencesStorePlatform.instance = _store;
  SharedPreferences.resetStatic();
  EloService.instance.viderMemoirePourResetComplet();
  SharedPreferences.resetStatic();
}

String _cleElo(String nom) => '${nom.toUpperCase()}|TROT_ATTELE';

/// Deux ratings à 1600 / 12 courses / +2,5 — valeurs réelles et réalistes.
Map<String, dynamic> _payloadElo() => <String, dynamic>{
      for (final n in <String>['X1B ALPHA', 'X1B BRAVO'])
        _cleElo(n): <String, dynamic>{
          'nom': n,
          'rating': 1600.0,
          'nb': 12,
          'var': 2.5,
        },
    };

// ───────────────────────────────────────────────────────────────────────────
//  SEMIS D'UN ÉTAT ELO COHÉRENT
// ───────────────────────────────────────────────────────────────────────────

/// Pose un état ELO COHÉRENT (RAM + disque) et rend l'empreinte RÉELLE des
/// ratings — celle qu'un registre doit déclarer pour être `coherent`.
Future<String> _semerEtatElo() async {
  await EloService.instance.importerDepuisBackup(_payloadElo());

  final Map<String, dynamic> ramJson =
      EloService.instance.exporterPourBackup();
  _store.poser(kCleElo, jsonEncode(ramJson));
  _store.poser(kCleTs, 1763500000000);

  final Map<String, EloScore> ratings = <String, EloScore>{
    for (final e in ramJson.entries)
      e.key: EloScore.fromJson(e.value as Map<String, dynamic>),
  };
  return empreinte64Ratings(ratings);
}

/// Redémarrage SIMULÉ complet : mémoire vidée ET surveillance ramenée à son
/// état de naissance (`normal`, non exact). Sans cette seconde partie, la
/// valeur mesurée avant le redémarrage survivrait au vidage — c'est
/// précisément le défaut que corrigerait un `max` historique, et c'est
/// pourquoi le test X1b-5a doit repartir d'un indicateur NON établi.
Future<void> _redemarrer() async {
  await _remettreSurveillanceAZero();
}

/// Retire le registre du stockage SANS passer par le service : c'est le seul
/// moyen d'obtenir un disque sans registre tout en gardant les ratings.
void _viderDisqueRegistre() {
  _store.effacer(kCleRegistre);
  _store.remettreCompteursAZero();
}

/// Remet la surveillance dans son état INITIAL, celui d'un service qui n'a
/// jamais rien mesuré : `niveauRegistre == normal` et `niveauRegistreEstExact
/// == false`.
///
/// ⚠️ NÉCESSAIRE ET MESURÉ : `_niveauRegistre` est un champ d'un SINGLETON.
///    `viderMemoirePourResetComplet()` (l.4286) ne vide que `_ratings` et ne
///    touche pas à la surveillance. Sans cette remise à zéro, la valeur mesurée
///    par un test FUITERAIT dans le suivant — c'est exactement ce qui a produit
///    des `Expected: normal / Actual: alerte` lors de la mise au point.
///    Le seul état « jamais mesuré » accessible publiquement est celui qui
///    suit un reset complet (P5, via `executerResetComplet`).
Future<void> _remettreSurveillanceAZero() async {
  await EloService.instance.executerResetComplet(() async {});
  _store.remettreCompteursAZero();
}

// ───────────────────────────────────────────────────────────────────────────
//  CONSTRUCTION D'UN REGISTRE RÉEL, de taille et d'empreinte choisies
// ───────────────────────────────────────────────────────────────────────────

EntreeRegistreElo _entree(int id, int nbChevaux, {bool incertaine = false}) {
  final chevaux = <ChevalJournalise>[];
  for (var i = 0; i < nbChevaux; i++) {
    chevaux.add(ChevalJournalise(
      cle: 'X1B$i|TROT_ATTELE',
      nom: 'X1B$i',
      avant:
          ImageRatingElo(rating: 1500.0 + i, nbCourses: 12, variationMois: 3.5),
      apres:
          ImageRatingElo(rating: 1512.5 + i, nbCourses: 13, variationMois: 16.0),
    ));
  }
  return EntreeRegistreElo(
    id: id,
    type: TypeEntreeRegistre.course,
    cle: 'X1B-ARCHIVE-$id',
    numR: 1,
    numC: id,
    date: '2026-11-18',
    discipline: 'TROT_ATTELE',
    etape: incertaine
        ? EtapeEntreeRegistre.intention
        : EtapeEntreeRegistre.appliquee,
    issue: incertaine ? null : IssueEcritureElo.persistee,
    tsIntention: 1763500000000 + id,
    tsFinal: incertaine ? null : 1763500000500 + id,
    empreinteAvant: '0123456789abcdef',
    empreinteApres: 'fedcba9876543210',
    chevaux: chevaux,
  );
}

/// Registre de `nbEntrees` entrées ARCHIVÉES, d'empreinte `empreinte`.
/// Leurs clés `X1B-ARCHIVE-n` ne peuvent jamais entrer en collision avec une
/// `courseKey` réelle de test : le blocage de doublon reste donc mesuré sur
/// les seules courses réellement journalisées.
/// Le registre contient TOUJOURS l'entrée [kCleRefus] : elle permet aux tests
/// d'OBSERVER (refus de doublon, donc aucune écriture) sans jamais appliquer.
String _jsonRegistre(
  int nbEntrees,
  String empreinte, {
  int chevauxParEntree = 0,
  int depart = 1,
}) {
  final reg = RegistreEloV3(
    schema: 3,
    version: 1,
    horloge: depart + nbEntrees,
    empreinteRatings: empreinte,
    origine: OrigineRegistreElo.courante,
    entrees: <EntreeRegistreElo>[
      for (var i = depart; i < depart + nbEntrees; i++)
        _entree(i, chevauxParEntree),
      _entreeReference,
    ],
  );
  return reg.encoder();
}

/// L'entrée qui matérialise [kCleRefus].
final EntreeRegistreElo _entreeReference = EntreeRegistreElo(
  id: 900000,
  type: TypeEntreeRegistre.course,
  cle: kCleRefus,
  numR: 99,
  numC: 99,
  date: '2024-05-10',
  discipline: 'TROT_ATTELE',
  etape: EtapeEntreeRegistre.appliquee,
  issue: IssueEcritureElo.persistee,
  tsIntention: 1763500900000,
  tsFinal: 1763500900500,
  empreinteAvant: '0123456789abcdef',
  empreinteApres: 'fedcba9876543210',
  chevaux: const <ChevalJournalise>[],
);

/// Croît en nombre d'entrées jusqu'à dépasser `minOctets` OCTETS réels.
String _jsonDauMoins(
  int minOctets,
  String empreinte, {
  int chevauxParEntree = 0,
}) {
  var n = 1;
  while (true) {
    final s = _jsonRegistre(n, empreinte, chevauxParEntree: chevauxParEntree);
    if (utf8.encode(s).length >= minOctets) return s;
    n = n < 16 ? n + 1 : (n * 1.5).ceil();
  }
}

/// Taille nécessaire pour atteindre (et dépasser) un niveau donné.
int _octetsPourNiveau(NiveauRetentionElo niveau) => switch (niveau) {
      NiveauRetentionElo.normal => 200,
      NiveauRetentionElo.veille => kSeuilVeilleOctets + 5000,
      NiveauRetentionElo.alerte => kSeuilAlerteOctets + 5000,
      NiveauRetentionElo.saturation => kSeuilSaturationOctets + 5000,
    };

/// Point d'entrée UNIQUE vers P1 : identité VALIDE, 2 partants, 2 arrivants.
///
/// [courseKey] `null` fait volontairement court-circuiter P1 (refus d'identité
/// l.2850) : c'est le témoin négatif du groupe 3.
Future<EtatPersistanceElo> _appelerService({String? courseKey}) =>
    EloService.instance.mettreAJourApresArrivee(
      arrivee: <int>[1, 2],
      partants: _partants(),
      discipline: 'TROT_ATTELE',
      courseKey: courseKey,
    );

/// Une course DISTINCTE, au format réellement accepté par le service.
String _cleCourse(int r, int c) => 'R${r}C${c}_$kDatePassee';

/// OBSERVATION SANS ÉCRITURE : la course [kCleRefus] est déjà journalisée,
/// donc `entreePourCle` refuse AVANT toute mutation — mais APRÈS P1.
///
/// C'est le seul appel qui permet de mesurer sans écrire. Un appel avec une
/// course nouvelle, lui, applique réellement et passe l'indicateur en ESTIMÉ.
Future<EtatPersistanceElo> _observer() =>
    _appelerService(courseKey: kCleRefus);

/// Partants minimaux mais réels, ratings déjà semés à 1600.
List<ZtPartant> _partants() => <ZtPartant>[
      ZtPartant(
        numero: '1',
        nom: 'X1B ALPHA',
        driver: '',
        entraineur: '',
        proprietaire: '',
        gains: '',
        record: '',
        musique: '',
        cote: '3.0',
        ageSexe: '5',
      ),
      ZtPartant(
        numero: '2',
        nom: 'X1B BRAVO',
        driver: '',
        entraineur: '',
        proprietaire: '',
        gains: '',
        record: '',
        musique: '',
        cote: '9.0',
        ageSexe: '5',
      ),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _installerStore();
    // Isolement TOTAL entre tests : la surveillance est un champ de singleton.
    await _remettreSurveillanceAZero();
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE 1 — INTÉGRITÉ : la surveillance ne modifie RIEN
  // ═════════════════════════════════════════════════════════════════════════

  group('X1b-1 · intégrité du registre', () {
    test('X1b-1a · toutes les entrées sont conservées, octet pour octet',
        () async {
      final fp = await _semerEtatElo();
      final json = _jsonRegistre(400, fp, chevauxParEntree: 12);
      _store.poser(kCleRegistre, json);
      _store.remettreCompteursAZero();

      // 50 OBSERVATIONS RÉELLES : chacune traverse P1 (identité valide, deux
      // partants, deux arrivants) puis est refusée par le verrou de doublon.
      // Aucune n'est une écriture.
      for (var i = 0; i < 50; i++) {
        final etat = await _observer();
        expect(etat, EtatPersistanceElo.nonTentee,
            reason: 'la course de référence est déjà journalisée');
      }

      final apres = _store.lire(kCleRegistre) as String?;
      expect(apres, isNotNull, reason: 'la clé registre doit exister');
      expect(apres, json,
          reason: 'aucune observation ne doit modifier le registre');
      expect(RegistreEloV3.decoder(apres!).entrees.length, 401,
          reason: 'les 400 entrées archive + la référence sont conservées');
      expect(_store.nbEcrituresRegistre, 0,
          reason: 'une observation n\'écrit JAMAIS le registre');
    });

    test('X1b-1b · les images avant/après de chaque cheval sont conservées',
        () async {
      final fp = await _semerEtatElo();
      final json = _jsonRegistre(20, fp, chevauxParEntree: 12);
      final reg = RegistreEloV3.decoder(json);

      for (final e in reg.entrees) {
        // `_entreeReference` n'a volontairement aucun cheval : c'est un simple
        // verrou de doublon. On ne l'inclut pas dans la preuve de conservation.
        if (e.cle == kCleRefus) continue;
        expect(e.chevaux.length, 12,
            reason: 'aucune compaction ne doit vider `chevaux`');
        for (final c in e.chevaux) {
          expect(c.avant, isNotNull,
              reason: 'l\'image AVANT est la preuve : jamais supprimée');
          expect(c.avant!.rating, isNotNull);
          expect(c.apres.rating, isNotNull);
        }
      }
    });

    test('X1b-1c · les entrées incertaines sont conservées', () async {
      final fp = await _semerEtatElo();
      final reg = RegistreEloV3(
        schema: 3,
        version: 1,
        horloge: 5,
        empreinteRatings: fp,
        origine: OrigineRegistreElo.courante,
        entrees: <EntreeRegistreElo>[
          for (var i = 1; i <= 4; i++) _entree(i, 12),
          _entree(5, 12, incertaine: true),
        ],
      );
      final relu = RegistreEloV3.decoder(reg.encoder());

      expect(relu.entrees.length, 5);
      expect(relu.entreesIncertaines.length, 1,
          reason: 'une entrée incertaine ne doit jamais disparaître');
      expect(relu.entreesIncertaines.first.chevaux.length, 12,
          reason: 'ses `chevaux` sont sa seule preuve : jamais compactés');
    });

    test('X1b-1d · l\'empreinte des ratings est conservée', () async {
      final fp = await _semerEtatElo();
      final json = _jsonRegistre(10, fp);
      expect(RegistreEloV3.decoder(json).empreinteRatings, fp);
      expect(fp.length, 16, reason: 'empreinte de 16 hexadécimaux');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE 2 — PROTECTIONS : aucune régression
  // ═════════════════════════════════════════════════════════════════════════

  group('X1b-2 · protections anti-double-application', () {
    test('X1b-2a · une course déjà journalisée reste bloquée', () async {
      final fp = await _semerEtatElo();
      _store.poser(kCleRegistre, _jsonRegistre(3, fp));
      _store.remettreCompteursAZero();

      final courseKey = _cleCourse(1, 7);

      final e1 = await _appelerService(courseKey: courseKey);
      expect(e1, EtatPersistanceElo.persistee,
          reason: 'première application : elle doit passer');
      final ecrituresApresPremiere = _store.nbEcrituresRegistre;

      // Seconde application de la MÊME course : doit être refusée.
      final e2 = await _appelerService(courseKey: courseKey);
      expect(e2, EtatPersistanceElo.nonTentee,
          reason: 'la surveillance ne doit pas affaiblir le blocage de doublon');
      expect(EloService.instance.dernierResultatMiseAJour!.motifRefus,
          MotifRefusApplicationElo.courseDejaJournalisee);
      expect(_store.nbEcrituresRegistre, ecrituresApresPremiere,
          reason: 'le refus de doublon n\'écrit rien de plus');
    });

    test('X1b-2b · le niveau `saturation` n\'introduit AUCUN refus', () async {
      final fp = await _semerEtatElo();
      final enorme = _jsonDauMoins(kSeuilSaturationOctets + 5000, fp);
      expect(utf8.encode(enorme).length,
          greaterThanOrEqualTo(kSeuilSaturationOctets),
          reason: 'le registre dépasse bien 6 Mio');
      _store.poser(kCleRegistre, enorme);
      _store.remettreCompteursAZero();

      final etat = await _appelerService(courseKey: _cleCourse(9, 42));

      expect(etat, EtatPersistanceElo.persistee,
          reason: 'AU-DELÀ DE 6 Mio l\'application doit RESTER possible');
      expect(EloService.instance.niveauRegistre,
          NiveauRetentionElo.saturation,
          reason: 'le niveau a bien été mesuré à `saturation`');
      expect(EloService.instance.dernierResultatMiseAJour!.motifRefus, isNull,
          reason: 'aucun motif de refus : la saturation est INFORMATIVE');
    });

    test('X1b-2c · aucune nouvelle clé SharedPreferences', () async {
      final fp = await _semerEtatElo();
      _store.poser(kCleRegistre, _jsonRegistre(3, fp));

      await _observer();

      final cles = _store.cles();
      expect(
        cles,
        <String>{kCleElo, kCleTs, kCleRegistre},
        reason: 'exactement trois clés : ratings, horodatage et registre',
      );
      expect(cles.length, 3,
          reason: 'la surveillance vit en RAM, jamais sur le disque');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE 3 — MESURE EXACTE AU CHARGEMENT
  // ═════════════════════════════════════════════════════════════════════════

  group('X1b-3 · exactitude au chargement', () {
    test('X1b-3a · registre représentatif : niveau exact', () async {
      final fp = await _semerEtatElo();
      final json =
          _jsonDauMoins(_octetsPourNiveau(NiveauRetentionElo.alerte), fp);
      _store.poser(kCleRegistre, json);

      await _observer();

      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.alerte);
      expect(EloService.instance.niveauRegistreEstExact, isTrue,
          reason: 'au chargement l\'indicateur doit dire EXACT');
      expect(EloService.instance.niveauRegistre,
          classerRetention(octetsUtf8(json)),
          reason: 'la valeur doit être celle du JSON du disque, exactement');
    });

    test('X1b-3b · TÉMOIN NÉGATIF : sans identité, P1 n\'est jamais atteint',
        () async {
      final fp = await _semerEtatElo();
      final json =
          _jsonDauMoins(_octetsPourNiveau(NiveauRetentionElo.saturation), fp);
      _store.poser(kCleRegistre, json);
      // Le semis lui-même écrit `elo_ratings_v2` : on isole la mesure.
      _store.remettreCompteursAZero();

      // État initial, garanti par setUp (reset complet => P5) : le niveau est
      // `normal` alors que le disque porte un registre de niveau `saturation`.
      // C'est la référence du TÉMOIN NÉGATIF.
      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.normal,
          reason: 'référence : rien n\'a encore été mesuré sur ce disque');

      // Sans `courseKey`, l'identité est `null` => refus AVANT le chargement
      // du registre (l.2850). On le prouve par le MOTIF et par le fait que
      // RIEN n'est écrit — pas par une valeur de niveau.
      final etat = await _appelerService(courseKey: null);
      expect(etat, EtatPersistanceElo.nonTentee);
      expect(EloService.instance.dernierResultatMiseAJour!.motifRefus,
          MotifRefusApplicationElo.identiteNonExploitable);
      expect(_store.nbEcrituresRegistre, 0,
          reason: 'TÉMOIN : un refus d\'identité n\'écrit rien');
      expect(_store.nbEcrituresElo, 0,
          reason: 'TÉMOIN : et ne touche à aucun rating');
      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.normal,
          reason: 'TÉMOIN NÉGATIF DÉCISIF : le disque porte `saturation`, '
              'or le niveau est RESTÉ `normal` => P1 n\'a pas été atteint');

      // TÉMOIN POSITIF : avec identité, P1 mesure le disque, EXACTEMENT.
      await _observer();
      expect(EloService.instance.niveauRegistre,
          classerRetention(octetsUtf8(json)),
          reason: 'TÉMOIN : avec identité, le niveau est mesuré');
      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.saturation);
      expect(EloService.instance.niveauRegistreEstExact, isTrue);
    });

    test('X1b-3c · octetsUtf8 : exact sur le BMP, surestimé hors BMP', () {
      // ── Contenu BMP — DOIT être exact ────────────────────────────────────
      for (final s in <String>[
        'A',
        'É', // latin-1 : 2 octets
        '€', // 3 octets
        'TROT_ATTELE|ÉTOILE DU NORD|2026-11-18',
        '{"a":"b"}',
      ]) {
        expect(octetsUtf8(s), utf8.encode(s).length,
            reason: 'sur le BMP, octetsUtf8 est EXACT : "$s"');
      }

      // Un registre réel, entièrement ASCII.
      final ascii = _jsonRegistre(20, '0123456789abcdef');
      expect(octetsUtf8(ascii), utf8.encode(ascii).length,
          reason: 'un registre sans accent est exactement mesuré');

      // ── Contenu HORS BMP — DOIT surestimer, PAS être exact ───────────────
      // 3 octets facturés par unité surrogate => 6 pour un caractère de 4 o.
      for (final s in <String>['\u{1D538}', '\u{1F40E}']) {
        expect(s.length, 2, reason: 'un caractère hors BMP = 2 unités UTF-16');
        expect(utf8.encode(s).length, 4, reason: 'mais 4 octets UTF-8 réels');
        expect(octetsUtf8(s), 6,
            reason: 'octetsUtf8 SURESTIME hors BMP — direction fail-safe');
        expect(octetsUtf8(s), greaterThan(utf8.encode(s).length));
      }
    });

    test('X1b-3d · le minorant ne SURESTIME jamais, il sous-estime', () {
      final fp = '0123456789abcdef';
      final cas = <String>[
        _jsonRegistre(100, fp, chevauxParEntree: 12),
        _jsonRegistre(300, fp, chevauxParEntree: 12),
        _jsonRegistre(5, fp, chevauxParEntree: 12),
        '{"a":"b"}',
        'ÉÉÉÉ',
        '\u{1D538}',
      ];
      for (final s in cas) {
        expect(octetsUtf8(s), greaterThanOrEqualTo(s.length),
            reason: 'invariant fondateur : octets >= unités');
        expect(
          classerRetention(s.length).index,
          lessThanOrEqualTo(classerRetention(octetsUtf8(s)).index),
          reason: 'le minorant RETARDE le niveau, jamais ne l\'avance',
        );
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE 4 — ESTIMATION APRÈS ÉCRITURE
  // ═════════════════════════════════════════════════════════════════════════

  group('X1b-4 · estimation après écriture', () {
    test('X1b-4a · après écriture, l\'indicateur passe à ESTIMÉ', () async {
      final fp = await _semerEtatElo();
      _store.poser(kCleRegistre, _jsonRegistre(3, fp));
      _store.remettreCompteursAZero();

      // Observation sans écriture => exact.
      await _observer();
      expect(EloService.instance.niveauRegistreEstExact, isTrue);

      // Écriture confirmée => estimé.
      final etat = await _appelerService(courseKey: _cleCourse(3, 21));
      expect(etat, EtatPersistanceElo.persistee);
      expect(_store.nbEcrituresRegistre, greaterThanOrEqualTo(1),
          reason: 'le registre a bien été écrit');
      expect(EloService.instance.niveauRegistreEstExact, isFalse,
          reason: 'après écriture la valeur est un MINORANT, donc ESTIMÉE');
    });

    test('X1b-4b · le niveau annoncé est le minorant de la chaîne écrite',
        () async {
      final fp = await _semerEtatElo();
      _store.poser(kCleRegistre, _jsonRegistre(3, fp));
      _store.remettreCompteursAZero();

      await _appelerService(courseKey: _cleCourse(4, 31));

      final ecrit = _store.lire(kCleRegistre) as String;
      expect(EloService.instance.niveauRegistre,
          classerRetention(ecrit.length),
          reason: 'la valeur annoncée est bien `brut.length` classé');
      expect(EloService.instance.niveauRegistre,
          classerRetention(octetsUtf8(ecrit)),
          reason: 'sur du contenu ASCII, minorant et mesure exacte coïncident');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE 5 — LES QUATRE SCÉNARIOS DE RESTAURATION + LE RESET
  // ═════════════════════════════════════════════════════════════════════════

  group('X1b-5 · restauration et reset', () {
    test('X1b-5a · redémarrage : recalculée depuis les données stockées',
        () async {
      final fp = await _semerEtatElo();
      final json =
          _jsonDauMoins(_octetsPourNiveau(NiveauRetentionElo.saturation), fp);
      _store.poser(kCleRegistre, json);

      await _observer();
      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.saturation);
      expect(EloService.instance.niveauRegistreEstExact, isTrue);

      // Redémarrage simulé. ⚠️ P5 (reset) remet TOUJOURS `exact = true` : il
      // n'existe donc aucun état publiquement atteignable où le niveau serait
      // « non établi » alors que le disque porte un registre. La preuve est
      // donc DIFFÉRENTIELLE : le disque d'abord VIDÉ de sa clé (donc
      // obligatoirement `normal`), puis RÉTABLI à l'identique.
      _viderDisqueRegistre();
      await _redemarrer();
      await _observer();
      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.normal,
          reason: 'sans registre sur le disque, le niveau ne peut que redescendre');

      _store.poser(kCleRegistre, json); // le disque est la SEULE source
      await _redemarrer();
      await _observer();
      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.saturation,
          reason: 'le même redémarrage, avec le registre sur le disque, '
              'RECALCULE `saturation` : la valeur vient bien du stockage');

      await _observer();
      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.saturation,
          reason: 'le niveau est RECALCULÉ depuis le stockage');
      expect(EloService.instance.niveauRegistreEstExact, isTrue);
      expect(_store.nbEcrituresRegistre, 0,
          reason: 'un recalcul ne réécrit jamais le registre');
    });

    test('X1b-5b · restauration plus volumineuse : le niveau MONTE', () async {
      final fp = await _semerEtatElo();

      _store.poser(kCleRegistre,
          _jsonDauMoins(_octetsPourNiveau(NiveauRetentionElo.veille), fp));
      await _observer();
      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.veille);

      _store.poser(kCleRegistre,
          _jsonDauMoins(_octetsPourNiveau(NiveauRetentionElo.saturation), fp));
      await _observer();
      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.saturation);
      expect(EloService.instance.niveauRegistreEstExact, isTrue);
    });

    test('X1b-5c · restauration plus petite : le niveau REDESCEND', () async {
      final fp = await _semerEtatElo();

      _store.poser(kCleRegistre,
          _jsonDauMoins(_octetsPourNiveau(NiveauRetentionElo.saturation), fp));
      await _observer();
      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.saturation);

      // Registre nettement plus petit, toujours cohérent.
      _store.poser(kCleRegistre, _jsonRegistre(5, fp));
      await _observer();
      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.normal,
          reason: 'AUCUN maximum historique : le niveau doit REDESCENDRE');
      expect(EloService.instance.niveauRegistreEstExact, isTrue);
    });

    test('X1b-5d · reset complet : le niveau revient à `normal`', () async {
      final fp = await _semerEtatElo();
      _store.poser(kCleRegistre,
          _jsonDauMoins(_octetsPourNiveau(NiveauRetentionElo.saturation), fp));
      await _observer();
      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.saturation);

      await EloService.instance.executerResetComplet(() async {
        _store.effacer(kCleElo);
        _store.effacer(kCleTs);
        _store.effacer(kCleRegistre);
      });

      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.normal,
          reason: 'après reset, registre absent => niveau normal');
      expect(EloService.instance.niveauRegistreEstExact, isTrue);
      expect(_store.contient(kCleRegistre), isFalse,
          reason: 'la clé a bien été effacée');
    });

    test('X1b-5e · après reset, un rechargement repart de `normal`', () async {
      final fp = await _semerEtatElo();
      _store.poser(kCleRegistre,
          _jsonDauMoins(_octetsPourNiveau(NiveauRetentionElo.alerte), fp));
      await _observer();
      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.alerte);

      await EloService.instance.executerResetComplet(() async {
        _store.effacer(kCleElo);
        _store.effacer(kCleTs);
        _store.effacer(kCleRegistre);
      });
      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.normal);

      // Redémarrage après reset : le disque ne porte plus de registre.
      expect(_store.contient(kCleRegistre), isFalse);
      await _redemarrer();

      // 1er appel : registre ABSENT => P1 hydrate `normal`, PUIS l'amorçage
      // écrit, donc l'indicateur repasse en ESTIMÉ. Le NIVEAU reste `normal`.
      await _observer();
      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.normal,
          reason: 'après un reset, le registre est à nouveau minuscule');
      expect(_store.contient(kCleRegistre), isTrue,
          reason: 'l\'amorçage a bien reposé la clé');
      expect(_store.nbEcrituresRegistre, greaterThanOrEqualTo(1));
      expect(EloService.instance.niveauRegistreEstExact, isFalse,
          reason: 'après une écriture confirmée, la valeur est ESTIMÉE');

      // 2e appel : la course est désormais journalisée => refus, donc P1
      // s'exécute SANS écrire : la mesure redevient EXACTE.
      await _observer();
      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.normal);
      expect(EloService.instance.niveauRegistreEstExact, isTrue,
          reason: 'une observation sans écriture rend la mesure EXACTE');
    });

    // ───────────────────────────────────────────────────────────────────────
    //  X1b-5f — DÉFAUT MESURÉ PUIS CORRIGÉ
    //
    //  AVANT correctif, `_hydraterNiveauRegistre(null)` était exécuté dans le
    //  `finally` de `executerResetComplet` SANS condition. Un reset dont
    //  l'effacement ÉCHOUE annonçait donc `normal` + `exact = true` alors que
    //  `elo_registre_v3` était TOUJOURS sur le disque. Valeurs réellement
    //  relevées par la sonde de fraîcheur, avant correction :
    //
    //    [D2] annonce=normal | exact=true | disque=saturation | octets=7144737
    //    [E2] annonce=normal | exact=true | disque=saturation | octets=7144737
    //
    //  C'est exactement ce que l'exigence « ne jamais présenter comme exacte
    //  et actuelle une mesure devenue obsolète » interdit.
    //
    //  TROIS SCÉNARIOS, tous par un chemin de PRODUCTION :
    //   A) effacement qui LÈVE (témoin direct du `finally`) ;
    //   B) `BackupService.reinitialiserComplet()` avec `remove()` rendant
    //      `false` sur la clé du registre — mode d'échec SILENCIEUX C1-a où
    //      le cache est vidé mais la clé SURVIT sur le disque ;
    //   C) reset RÉUSSI : comportement strictement inchangé.
    // ───────────────────────────────────────────────────────────────────────

    test(
        'X1b-5f · Reset avec échec d\'effacement : '
        'mesure jamais annoncée exacte à tort', () async {
      final fp = await _semerEtatElo();

      // 1. Un registre supérieur à 6 Mio (seuil de saturation).
      final enorme = _jsonDauMoins(kSeuilSaturationOctets + 5000, fp);
      expect(utf8.encode(enorme).length, greaterThan(kSeuilSaturationOctets),
          reason: 'le registre dépasse bien 6 Mio, mesuré en octets réels');
      _store.poser(kCleRegistre, enorme);
      await _observer();
      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.saturation);
      expect(EloService.instance.niveauRegistreEstExact, isTrue,
          reason: 'état de départ : mesure EXACTE de 6,8 Mio');

      // ── SCÉNARIO A : l'effacement LÈVE, la clé du registre survit ────────
      // 2. Un effacement qui échoue par exception (après avoir supprimé les
      //    ratings, pour que le disque soit dans l'état INTERMÉDIAIRE que
      //    décrit le contrat C1-a : « les suppressions déjà réussies ne sont
      //    PAS annulées »).
      Object? erreur;
      try {
        await EloService.instance.executerResetComplet(() async {
          _store.effacer(kCleElo);
          _store.effacer(kCleTs);
          throw StateError('effacement disque refusé (simulation)');
        });
      } catch (e) {
        erreur = e;
      }
      expect(erreur, isA<StateError>(),
          reason: 'l\'exception remonte TELLE QUELLE, sans être avalée');

      // 3. Une clé reste présente sur le disque.
      expect(_store.contient(kCleRegistre), isTrue,
          reason: 'la clé du registre SURVIT à l\'effacement en échec');

      // 4. `niveauRegistreEstExact` reste FAUX : plus jamais « exact » à
      //    l'aveugle. Et le niveau n'est PAS artificiellement ramené à
      //    `normal` : aucune valeur inventée n'est annoncée.
      expect(EloService.instance.niveauRegistreEstExact, isFalse,
          reason: 'un effacement NON confirmé interdit toute mention EXACTE');
      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.saturation,
          reason: 'le niveau n\'est PAS réécrit en `normal` : il reste la '
              'dernière mesure connue, désormais marquée NON EXACTE');

      // 5. Rétablissement de la mesure correcte au prochain chargement : P1
      //    relit le disque et redevient EXACT et concordant.
      await _observer();
      final int octetsDisque = utf8.encode(enorme).length;
      expect(EloService.instance.niveauRegistreEstExact, isTrue,
          reason: 'P1 remesure depuis le disque : la mesure redevient EXACTE');
      expect(EloService.instance.niveauRegistre, classerRetention(octetsDisque),
          reason: 'la mesure rétablie correspond au registre réellement '
              'présent sur le disque ($octetsDisque octets)');
      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.saturation);

      // ── SCÉNARIO B : `remove()` rend `false` — chemin de PRODUCTION ──────
      //    On repart d'un état sain, puis on refuse la SEULE suppression de
      //    la clé du registre. `BackupService.reinitialiserComplet()` est le
      //    vrai point d'entrée utilisé par l'application (l.1952).
      _store.poser(kCleRegistre, enorme);
      await _observer();
      expect(EloService.instance.niveauRegistreEstExact, isTrue);

      _store.refusRemove.add('flutter.$kCleRegistre');

      Object? erreurBis;
      try {
        await BackupService.instance.reinitialiserComplet();
      } catch (e) {
        erreurBis = e;
      }
      expect(erreurBis, isA<StateError>(),
          reason: 'C1-a : un reset incomplet LÈVE, il ne s\'annonce pas réussi');
      expect((erreurBis! as StateError).message, contains(kCleRegistre),
          reason: 'le diagnostic NOMME la clé qui a survécu');
      expect(_store.contient(kCleRegistre), isTrue,
          reason: 'échec silencieux : la clé n\'a pas été supprimée du disque');

      expect(EloService.instance.niveauRegistreEstExact, isFalse,
          reason: 'reset par le chemin RÉEL en échec => mesure NON EXACTE');
      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.saturation,
          reason: 'aucune annonce artificielle de registre vide');

      // Rétablissement, là encore par une relecture réelle du disque.
      await _observer();
      expect(EloService.instance.niveauRegistreEstExact, isTrue);
      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.saturation);

      // ── SCÉNARIO C : reset RÉUSSI — comportement INCHANGÉ ────────────────
      _store.refusRemove.clear();
      await EloService.instance.executerResetComplet(() async {
        _store.effacer(kCleElo);
        _store.effacer(kCleTs);
        _store.effacer(kCleRegistre);
      });
      expect(_store.contient(kCleRegistre), isFalse,
          reason: 'reset réussi : la clé a bien été effacée');
      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.normal,
          reason: 'reset réussi : registre ABSENT => niveau `normal`');
      expect(EloService.instance.niveauRegistreEstExact, isTrue,
          reason: 'reset réussi : le registre est absent, la mesure EST exacte');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE 6 — RESTAURATION PAR backup_service : chemin RÉEL + LIMITE
  //
  //  Chemin exigé : `backup_service` l.1459 → `importerDepuisBackup` →
  //  `_importerDepuisBackup` l.3903 → `_restaurerRegistreSauvegarde` l.4074 →
  //  `_ecrireRegistreVerbatim` (P4). Il exige une sauvegarde de PORTÉE
  //  ENRICHIE, c'est-à-dire contenant le marqueur `_elo_registre` (l.749,
  //  testé l.3953). Sans ce marqueur le chemin est HISTORIQUE et P4 n'est
  //  jamais atteint : c'est ce que le test X1b-6d mesure explicitement.
  // ═════════════════════════════════════════════════════════════════════════

  group('X1b-6 · restauration par backup_service', () {
    Future<void> restaurerBackup({
      String? registreJson,
      Map<String, dynamic>? ratings,
    }) async {
      final tmp = Directory.systemTemp.createTempSync('x1b_');
      PathProviderPlatform.instance = _FakePathProvider(tmp.path);
      final f = File('${tmp.path}/backup_x1b.json');
      f.writeAsStringSync(json.encode(<String, dynamic>{
        'appName': 'Pronostic Hippique',
        'version': '9.1',
        'dateBackup': '2026-01-15T10:00:00.000',
        'profil': <String, dynamic>{
          'profil_nom': <String, dynamic>{
            'type': 'String',
            'value': 'PROFIL X1B',
          },
        },
        'elo_service': <String, dynamic>{
          ...(ratings ?? _payloadElo()),
          if (registreJson != null) kMarqueurRegistre: registreJson,
        },
      }));
      final octets = Uint8List.fromList(f.readAsBytesSync());
      FilePicker.platform = _FakeFilePicker(FilePickerResult(<PlatformFile>[
        PlatformFile(
            name: 'backup_x1b.json', size: octets.length, bytes: octets),
      ]));
      await BackupService.instance.importerDepuisFichier();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    }

    test('X1b-6a · la restitution verbatim (P4) est bien atteinte', () async {
      final fp = await _semerEtatElo();
      _store.poser(kCleRegistre, _jsonRegistre(3, fp));
      _store.remettreCompteursAZero();
      await _observer();
      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.normal);
      expect(EloService.instance.niveauRegistreEstExact, isTrue);

      final gros =
          _jsonDauMoins(_octetsPourNiveau(NiveauRetentionElo.saturation), fp);
      await restaurerBackup(registreJson: gros);

      // P4 a écrit la chaîne verbatim : le disque la contient, à l'octet près.
      expect(_store.lire(kCleRegistre), gros,
          reason: 'la restitution est VERBATIM (aucune compaction)');
      expect(_store.nbEcrituresRegistre, greaterThanOrEqualTo(1),
          reason: 'le registre a bien été écrit par la restauration');
      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.saturation,
          reason: 'P4 met à jour l\'indicateur après écriture confirmée');
      expect(EloService.instance.niveauRegistreEstExact, isFalse,
          reason: 'cette mesure reste ESTIMÉE (minorant), jamais exacte');
    });

    test('X1b-6b · restauration plus petite : l\'indicateur REDESCEND',
        () async {
      final fp = await _semerEtatElo();
      _store.poser(kCleRegistre,
          _jsonDauMoins(_octetsPourNiveau(NiveauRetentionElo.saturation), fp));
      await _observer();
      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.saturation);

      // Restauration d'un registre COHÉRENT beaucoup plus petit.
      await restaurerBackup(registreJson: _jsonRegistre(4, fp));

      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.normal,
          reason: 'une restauration plus petite fait REDESCENDRE le niveau');
    });

    test('X1b-6c · après restauration, un chargement rétablit la vérité',
        () async {
      final fp = await _semerEtatElo();
      _store.poser(kCleRegistre,
          _jsonDauMoins(_octetsPourNiveau(NiveauRetentionElo.alerte), fp));
      await _observer();

      await restaurerBackup(
          registreJson: _jsonDauMoins(
              _octetsPourNiveau(NiveauRetentionElo.saturation), fp));

      // Le mécanisme de rattrapage : le chargement suivant mesure le disque.
      await _observer();
      final disque = _store.lire(kCleRegistre)! as String;

      expect(EloService.instance.niveauRegistreEstExact, isTrue,
          reason: 'après un chargement la valeur est de nouveau EXACTE');
      expect(EloService.instance.niveauRegistre,
          classerRetention(octetsUtf8(disque)),
          reason: 'et elle correspond octet pour octet au disque');
    });

    test(
        'X1b-6d · LIMITE MESURÉE : sans marqueur, aucun P4, donc aucune '
        'mise à jour par la restauration', () async {
      final fp = await _semerEtatElo();
      _store.poser(kCleRegistre,
          _jsonDauMoins(_octetsPourNiveau(NiveauRetentionElo.saturation), fp));
      await _observer();
      expect(EloService.instance.niveauRegistre, NiveauRetentionElo.saturation);
      expect(EloService.instance.niveauRegistreEstExact, isTrue);

      // Sauvegarde SANS marqueur : chemin HISTORIQUE, donc P4 jamais atteint.
      final avant = _store.lire(kCleRegistre) as String?;
      _store.remettreCompteursAZero();
      await restaurerBackup(registreJson: null);

      final disque = _store.lire(kCleRegistre) as String?;
      // MESURE : sur ce chemin, la surveillance n'est PAS alimentée par une
      // écriture verbatim. On enregistre donc le fait observable.
      // ignore: avoid_print
      print('[X1b-6d] P4 atteint=${_store.nbEcrituresRegistre > 0} | '
          'registre identique=${disque == avant} | '
          'niveau=${EloService.instance.niveauRegistre.name} | '
          'exact=${EloService.instance.niveauRegistreEstExact}');
      expect(disque, avant,
          reason: 'le chemin historique ne restitue pas le registre verbatim');
      if (disque == null) {
        // La clé a disparu : l'indicateur ne peut plus décrire le disque.
        expect(EloService.instance.niveauRegistreEstExact, isFalse,
            reason: 'sans mesure possible, il doit être marqué ESTIMÉ');
      } else {
        final attendu = classerRetention(octetsUtf8(disque));
        if (EloService.instance.niveauRegistreEstExact) {
          expect(EloService.instance.niveauRegistre, attendu,
              reason: 's\'il se déclare EXACT il doit l\'être réellement');
        } else {
          expect(EloService.instance.niveauRegistreEstExact, isFalse,
              reason: 'sinon il est ESTIMÉ : aucune fraîcheur revendiquée');
        }
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE 7 — ABSENCE DE TRAVAIL SUPPLÉMENTAIRE
  // ═════════════════════════════════════════════════════════════════════════

  group('X1b-7 · aucun décodage ni sérialisation supplémentaire', () {
    test('X1b-7a · une observation ne mesure qu\'une fois et n\'écrit rien',
        () async {
      final fp = await _semerEtatElo();
      final json = _jsonRegistre(50, fp);
      _store.poser(kCleRegistre, json);
      _store.remettreCompteursAZero();

      await _observer();

      expect(EloService.instance.niveauRegistre,
          classerRetention(octetsUtf8(json)));
      expect(EloService.instance.niveauRegistreEstExact, isTrue);
      expect(_store.nbEcrituresRegistre, 0,
          reason: 'une observation ne doit rien écrire sur le registre');
      // Le registre est lu par `prefs.get` sur le cache après `reload()` :
      // aucune lecture supplémentaire n'est imputable à X1-b.
      expect(_store.nbGetAll, lessThanOrEqualTo(1),
          reason: 'aucune lecture supplémentaire imputable à la surveillance');
    });

    test('X1b-7b · une application réussie écrit chaque clé UNE seule fois',
        () async {
      final fp = await _semerEtatElo();
      _store.poser(kCleRegistre, _jsonRegistre(3, fp));
      _store.remettreCompteursAZero();

      final etat = await _appelerService(courseKey: _cleCourse(5, 51));

      expect(etat, EtatPersistanceElo.persistee);
      expect(_store.nbEcrituresElo, 1,
          reason: 'une écriture des ratings, comme avant X1-b');
      expect(_store.nbEcrituresRegistre, greaterThanOrEqualTo(1),
          reason: 'le registre est écrit autant qu\'avant X1-b');
      // La surveillance ne réécrit jamais pour « mesurer » : aucune écriture
      // supplémentaire n'est imputable au comptage d'octets.
      expect(_store.nbEcrituresRegistre + _store.nbEcrituresElo,
          lessThanOrEqualTo(3));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE 8 — LES NOTES ELO SONT INCHANGÉES
  // ═════════════════════════════════════════════════════════════════════════

  group('X1b-8 · notes ELO inchangées', () {
    test('X1b-8a · 20 observations ne modifient aucun rating', () async {
      final fp = await _semerEtatElo();
      _store.poser(kCleRegistre, _jsonRegistre(3, fp));
      _store.remettreCompteursAZero();

      // Journalise UNE course, pour disposer ensuite d'un refus de doublon :
      // ce refus traverse P1 (donc la surveillance) sans jamais écrire.
      await _observer();
      _store.remettreCompteursAZero();

      final avant = <String, double>{
        for (final n in <String>['X1B ALPHA', 'X1B BRAVO'])
          n: EloService.instance.getScore(n, discipline: 'TROT_ATTELE').rating,
      };

      for (var i = 0; i < 20; i++) {
        final etat = await _observer();
        expect(etat, EtatPersistanceElo.nonTentee,
            reason: 'la course est déjà journalisée : refus attendu');
      }

      final apres = <String, double>{
        for (final n in <String>['X1B ALPHA', 'X1B BRAVO'])
          n: EloService.instance.getScore(n, discipline: 'TROT_ATTELE').rating,
      };
      expect(apres, avant,
          reason: '20 traversées de la surveillance ne touchent aucune note');
      expect(_store.nbEcrituresRegistre, 0,
          reason: 'aucune observation n\'écrit le registre');
      expect(_store.nbEcrituresElo, 0, reason: 'ni les ratings');
    });

    test('X1b-8b · une application ELO donne le résultat attendu', () async {
      final fp = await _semerEtatElo();
      _store.poser(kCleRegistre, _jsonRegistre(3, fp));
      _store.remettreCompteursAZero();

      final avant =
          EloService.instance.getScore('X1B ALPHA', discipline: 'TROT_ATTELE');
      final avantB =
          EloService.instance.getScore('X1B BRAVO', discipline: 'TROT_ATTELE');
      expect(avant.rating, 1600.0);
      expect(avantB.rating, 1600.0);

      final etat = await _appelerService(courseKey: _cleCourse(6, 61));
      expect(etat, EtatPersistanceElo.persistee);

      final apres =
          EloService.instance.getScore('X1B ALPHA', discipline: 'TROT_ATTELE');
      final apresB =
          EloService.instance.getScore('X1B BRAVO', discipline: 'TROT_ATTELE');

      expect(apres.rating, greaterThan(avant.rating),
          reason: 'le vainqueur progresse — formule ELO intacte');
      expect(apresB.rating, lessThan(avantB.rating),
          reason: 'le battu régresse — formule ELO intacte');
      // Signature structurelle : à deux chevaux partis à égalité, les deux
      // deltas sont opposés, donc leur somme est nulle. Aucun coefficient K
      // n'a été modifié.
      expect((apres.rating - avant.rating) + (apresB.rating - avantB.rating),
          closeTo(0.0, 1e-9),
          reason: 'somme des deltas nulle : aucun coefficient K modifié');
      // Les compteurs de courses progressent, eux aussi, normalement.
      expect(apres.nbCourses, greaterThan(avant.nbCourses));
    });
  });
}

