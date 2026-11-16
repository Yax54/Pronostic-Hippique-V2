// ═══════════════════════════════════════════════════════════════════════════
//  ArriveeOfficielleService — LOT L0 : stockage des arrivées officielles PMU
//
//  OBJET : conserver, de façon durable et indéfinie, l'ARRIVÉE COMPLÈTE que
//  l'API PMU publie au niveau de la COURSE (champ `ordreArrivee` de
//  `/programme/{DDMMYYYY}`), et non la reconstruction tronquée que l'on
//  obtient en recollant les rapports de paiement (`rapports-definitifs`).
//
//  CE SERVICE EST UN STOCKAGE PASSIF. Il n'écrit que dans ses propres clés.
//  Il ne lit, ne modifie et ne réécrit AUCUNE des données d'apprentissage :
//    • ni `_poids`, ni `_seuils`, ni les 19 critères ;
//    • ni `arriveeReelle` des pronostics ;
//    • ni le gradient, ni l'apprentissage par discipline, ni le TOP3 ;
//    • ni l'ELO, ni les statistiques, ni `analyseJourneeComplete()`.
//  Aucune fonction d'apprentissage ne l'appelle, et il n'appelle aucune d'elles.
//  Il ne notifie personne (pas de ChangeNotifier) : rien ne peut réagir à une
//  écriture et déclencher un recalcul.
//
//  ─── FORMAT DE STOCKAGE ───────────────────────────────────────────────────
//  Une clé SharedPreferences PAR MOIS :
//      arrivee_officielle_complete_v1_YYYY-MM
//  Contenu : base64( gzip( json ) ) — même codec que `ia_pronostics_v2_gz`
//  et que les shards de `IaArchiveService`, pour ne pas introduire un
//  troisième format dans l'application.
//
//      {"v":1,"arrivees":{"R1C2_16012025":{"rangs":[[10],[7],[2]],"declares":10}}}
//
//  ─── POURQUOI MENSUEL ET NON UNE CLÉ UNIQUE ───────────────────────────────
//  Mesuré (année 2025 complète, API PMU réelle) :
//    • volume identique à 2,2 % près (154 Ko vs 158 Ko en base64+gzip) ;
//    • coût CPU d'écriture : 67 973 µs (clé unique) contre 6 694 µs (mois),
//      soit x10,2 — et il CROÎT sans borne avec la clé unique alors qu'il
//      reste CONSTANT (~16 Ko) avec les clés mensuelles ;
//    • backend réel = SharedPreferences XML legacy, qui réécrit TOUT le
//      fichier à chaque écriture (SharedPreferencesPlugin.kt:313).
//  Le découpage n'est donc pas un choix de volume mais de granularité
//  d'écriture.
//
//  ─── EX ÆQUO ──────────────────────────────────────────────────────────────
//  `ordreArrivee` est NATIVEMENT un `List<List<int>>` : un groupe de plusieurs
//  numéros signifie « ex æquo à ce rang ». Le format est conservé TEL QUEL.
//  Ce service n'aplatit jamais les groupes, ne déduplique jamais les numéros
//  et ne réordonne jamais les rangs. Il n'utilise PAS le chemin
//  `ZoneTurfService.chargerResultatsCourseComplet()` dont la ligne
//  `rangParNumero[rangInt] = num` (zone_turf_service.dart:901) écrase un des
//  deux chevaux en cas d'ex æquo.
//
//  ─── RIEN N'EST INVENTÉ ───────────────────────────────────────────────────
//  Seul le statut `ARRIVEE_DEFINITIVE_COMPLETE` est accepté. Une arrivée
//  absente, vide, mal formée ou non définitive est REFUSÉE (retour `null` /
//  résultat en échec) : aucune reconstitution, aucun complément deviné, aucune
//  date fabriquée. Si la date de la course ne peut pas être lue dans la
//  `courseKey`, l'entrée est refusée plutôt que rangée sous une date inventée.
//
//  ─── RÉTENTION ────────────────────────────────────────────────────────────
//  AUCUNE purge temporelle. Même décision que `ia_premium_historique_v1`
//  (ia_memory_service.dart:97-98 : « plus AUCUNE purge temporelle —
//  l'historique est conservé indéfiniment »).
//
//  ─── FILE D'ATTENTE DURABLE (correctif 2) ─────────────────────────────────
//  Les entrées dont l'écriture n'a pas été confirmée sont conservées dans une
//  clé dédiée :
//      arrivee_officielle_pending_v1
//  Cette clé ne commence PAS par `kArriveeStoragePrefix` : la découverte
//  DYNAMIQUE des shards mensuels (`enumererClesSurStockage`) ne la voit donc
//  jamais, et elle ne peut pas être confondue avec un mois.
//
//  ORDRE D'ÉCRITURE IMPOSÉ (une écriture n'est jamais annoncée avant d'être
//  dans la file) :
//      1. file d'attente  → écrite en premier ;
//      2. shard mensuel   → écrit ensuite ;
//      3. file d'attente  → nettoyée en dernier.
//  Un arrêt brutal entre deux étapes laisse une file contenant une entrée
//  déjà écrite : le rejeu est IDEMPOTENT (même `courseKey` → même valeur), donc
//  cette situation est bénigne — jamais l'inverse.
//
//  ─── LIMITE ASSUMÉE : `apply()` ET LE CACHE OPTIMISTE ─────────────────────
//  Le backend réel est SharedPreferences XML legacy
//  (`SharedPreferencesPlugin.kt`, `edit().putString(...).apply()`). `apply()`
//  est ASYNCHRONE : le `true` rendu à Dart signifie « canal accepté », PAS
//  « écrit sur disque ». Un arrêt brutal dans cette fenêtre peut perdre la
//  dernière écriture. AUCUN mécanisme du magasin legacy ne ferme cette
//  fenêtre ; le prétendre serait faux.
//
//  Corollaire : `prefs.getString()` relit le CACHE DART optimiste, pas le
//  fichier. La relecture de contrôle de `_ecrireMois` est donc un garde de
//  COHÉRENCE (elle détecte un store qui altère la valeur), JAMAIS une preuve
//  de durabilité. Elle est présentée comme telle et ne doit pas être invoquée
//  comme garantie anti-crash.
//
//  Vérifié par mesure (sondes S1/S3/S4, hors projet) :
//    • store qui rend `true` sans écrire → `succes=true` alors que le disque
//      est vide : seule la réconciliation par `getKeys()` le verrait ;
//    • store qui altère la valeur → détecté par la relecture ;
//    • `setString` rendant `false` → intercepté par le garde `!ok` AVANT la
//      relecture, et le cache est pollué (la valeur fantôme reste lisible
//      jusqu'au redémarrage, sans jamais atteindre le disque).
//
//  ─── RÉINITIALISATION COMPLÈTE ────────────────────────────────────────────
//  Ce stockage est CONSERVÉ lors d'une réinitialisation, comme l'archive
//  `ia_archive_v1_*` (backup_service.dart:1655 : « archive historique
//  préservée »). Ses clés ne sont donc PAS ajoutées à `_toutesLesCles`.
//  `effacerTout()` existe pour un effacement EXPLICITE futur, mais n'est
//  appelé par aucun chemin de réinitialisation en L0.
//  Corollaire exigé : après une réinitialisation, ce service ne réinjecte
//  RIEN dans la mémoire active — ses données ne sont lues que par les écrans
//  qui demanderont explicitement une arrivée (L2).
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io'; // GZipCodec

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/date_utils.dart' show dateDepuisCourseKey;

// ─── Constantes de persistance ──────────────────────────────────────────────

/// Préfixe des clés mensuelles : `arrivee_officielle_complete_v1_YYYY-MM`.
///
/// ⚠️ Constante de PERSISTANCE : ne jamais la faire varier sans migration.
/// C'est aussi le préfixe utilisé pour la découverte DYNAMIQUE des clés au
/// moment des sauvegardes et des restaurations (aucune liste figée).
const String kArriveeStoragePrefix = 'arrivee_officielle_complete_v1_';

/// Le SEUL statut accepté par ce stockage.
const String kStatutArriveeDefinitiveComplete = 'ARRIVEE_DEFINITIVE_COMPLETE';

/// Version du format interne des shards. Un shard d'une version supérieure
/// est conservé intact mais non interprété (voir `_decoderShard`).
const int kArriveeFormatVersion = 1;

/// Clé de la FILE D'ATTENTE durable (correctif 2).
///
/// ⚠️ Cette clé ne commence VOLONTAIREMENT pas par [kArriveeStoragePrefix] :
/// elle ne doit jamais être vue par la découverte dynamique des shards
/// mensuels, ni passer pour un mois. Elle est exportée et restaurée
/// EXPLICITEMENT (voir `exporterPourBackup` / `restaurerDepuisBackup`).
///
/// ⚠️ Constante de PERSISTANCE : ne jamais la faire varier sans migration.
const String kArriveePendingKey = 'arrivee_officielle_pending_v1';

/// Version du format de la file d'attente.
const int kArriveePendingVersion = 1;

/// Une entrée d'arrivée, déjà validée.
@immutable
class EntreeArrivee {
  /// Identité de la course, telle que l'application la manipule
  /// (`R{n}C{n}_DDMMYYYY`). Aucune normalisation : l'identité est conservée
  /// à l'octet près pour rester alignée sur `_pronostics`.
  final String courseKey;

  /// Rangs officiels, **groupes d'ex æquo conservés**.
  /// `[[10],[7],[2]]` = 10 puis 7 puis 2.
  /// `[[4,7],[2]]` = 4 et 7 ex æquo au 1er rang, puis 2.
  final List<List<int>> rangs;

  /// Nombre de partants DÉCLARÉS par le PMU (`nombreDeclaresPartants`).
  ///
  /// ⚠️ MÉTADONNÉE INFORMATIVE UNIQUEMENT. Elle est conservée parce qu'elle est
  /// factuelle, disponible sans coût réseau, et qu'un audit a établi qu'elle
  /// n'est PAS égale au nombre de groupes de `ordreArrivee` (les groupes
  /// excluent les disqualifiés). Elle n'est lue par AUCUNE fonction : en
  /// particulier, elle ne doit jamais alimenter le calcul de `nbPartants`
  /// de l'apprentissage (ia_memory_service.dart:2772) dans le cadre de L0.
  final int? declares;

  const EntreeArrivee({
    required this.courseKey,
    required this.rangs,
    this.declares,
  });

  /// Mois de rangement (YYYY-MM), déduit de la `courseKey`. `null` si la clé
  /// ne porte pas une date calendaire valide — dans ce cas l'entrée est
  /// refusée par le service : on n'invente pas de date.
  String? get mois => moisDepuisCourseKey(courseKey);

  /// Sérialisation COMPLÈTE, `courseKey` incluse (correctif 2).
  ///
  /// L'ancienne version omettait `courseKey` : une entrée exportée n'était pas
  /// réimportable. Le champ est désormais présent. Les shards mensuels n'en
  /// ont pas besoin (la clé y est la clé de la map `arrivees`), mais
  /// l'inclure est sans effet sur eux : `_decoderShard` ignore ce champ et
  /// utilise la clé de map.
  ///
  /// COMPATIBILITÉ ASCENDANTE : un ancien export sans `courseKey` reste lisible
  /// par `_entreeDepuisJson`, qui accepte alors une clé fournie par l'appelant
  /// (voir `exporterPourBackup` / `restaurerDepuisBackup`).
  Map<String, dynamic> toJson() => {
        'courseKey': courseKey,
        'rangs': rangs,
        if (declares != null) 'declares': declares,
      };

  /// Sérialisation pour un SHARD MENSUEL : `courseKey` est OMISE.
  ///
  /// Pourquoi ne pas réutiliser [toJson] : dans un shard, la `courseKey` est
  /// déjà la clé de la map `arrivees`. L'y répéter alourdirait chaque entrée
  /// d'environ 13 octets (mesuré : clé `R1C8_01012025` = 13 caractères), soit
  /// ~13 Ko par mois plein (1 008 courses) — et surtout cela CHANGERAIT les
  /// octets des shards déjà écrits, alors que la compatibilité avec les
  /// données L0 existantes est exigée. Le format des shards reste donc
  /// strictement inchangé.
  Map<String, dynamic> _toJsonShard() => {
        'rangs': rangs,
        if (declares != null) 'declares': declares,
      };

  @override
  String toString() => 'EntreeArrivee($courseKey, ${rangs.length} rang(s), '
      'declares=$declares)';

}

/// Résultat d'une écriture (simple ou groupée).
@immutable
class ResultatEcriture {
  final bool succes;
  final int nbEcrites;

  /// Entrées conservées en mémoire faute d'écriture confirmée. Jamais perdues :
  /// elles sont rejouées au prochain `persisterEnAttente()`.
  final int nbEnAttente;
  final List<String> moisEcrits;
  final List<String> moisEchoues;
  final String? erreur;

  const ResultatEcriture({
    required this.succes,
    this.nbEcrites = 0,
    this.nbEnAttente = 0,
    this.moisEcrits = const [],
    this.moisEchoues = const [],
    this.erreur,
  });

  @override
  String toString() => 'ResultatEcriture(succes=$succes, ecrites=$nbEcrites, '
      'enAttente=$nbEnAttente, moisEcrits=${moisEcrits.length}, '
      'moisEchoues=${moisEchoues.length}${erreur == null ? '' : ', erreur=$erreur'})';
}

/// Rapport de réconciliation au chargement.
@immutable
class VerificationArrivees {
  final int clesPresentes;
  final int clesLues;
  final List<String> clesIllisibles;
  final int nbEntrees;

  const VerificationArrivees({
    required this.clesPresentes,
    required this.clesLues,
    required this.clesIllisibles,
    required this.nbEntrees,
  });

  bool get parfaite => clesIllisibles.isEmpty;

  @override
  String toString() => 'VerificationArrivees(presentes=$clesPresentes, '
      'lues=$clesLues, illisibles=${clesIllisibles.length}, '
      'entrees=$nbEntrees)';
}

/// Résultat d'une restauration depuis une sauvegarde.
@immutable
class ResultatRestaurationArrivees {
  final bool succes;
  final int shardsLus;
  final int shardsIllisibles;
  final int entreesAjoutees;

  /// Courses déjà présentes localement avec une arrivée **IDENTIQUE**.
  /// Ce sont de vrais doublons : rien à faire, rien à signaler.
  final int entreesDejaPresentes;

  /// Courses déjà présentes localement avec une arrivée **DIFFÉRENTE**
  /// (correctif 1). Les `courseKey` sont listés explicitement.
  ///
  /// ⚠️ AUCUNE résolution automatique : l'arrivée LOCALE est conservée, celle
  /// de la sauvegarde n'est ni écrite, ni fusionnée, ni supprimée. Le conflit
  /// est SIGNALÉ, pas tranché. Une arrivée officielle est un fait : la
  /// remplacer silencieusement serait réécrire l'histoire, et la remplacer
  /// automatiquement par la sauvegarde serait tout aussi arbitraire.
  final List<String> conflits;

  final int moisNonEcrits;
  final String? erreur;

  const ResultatRestaurationArrivees({
    required this.succes,
    this.shardsLus = 0,
    this.shardsIllisibles = 0,
    this.entreesAjoutees = 0,
    this.entreesDejaPresentes = 0,
    this.conflits = const [],
    this.moisNonEcrits = 0,
    this.erreur,
  });

  factory ResultatRestaurationArrivees.echec(String erreur) =>
      ResultatRestaurationArrivees(succes: false, erreur: erreur);

  /// `true` si au moins une divergence a été détectée.
  bool get aDesConflits => conflits.isNotEmpty;

  @override
  String toString() => 'ResultatRestaurationArrivees(succes=$succes, '
      'shardsLus=$shardsLus, illisibles=$shardsIllisibles, '
      'ajoutees=$entreesAjoutees, doublons=$entreesDejaPresentes, '
      'conflits=${conflits.length}, moisNonEcrits=$moisNonEcrits'
      '${erreur == null ? '' : ', erreur=$erreur'})';
}

// ─── Helpers de date (publics, testables) ───────────────────────────────────

/// Extrait le mois `YYYY-MM` d'une `courseKey`. `null` si non déterminable.
///
/// S'appuie sur `dateDepuisCourseKey`, qui refuse toute date calendaire
/// invalide. Aucune date de remplacement n'est jamais fabriquée.
String? moisDepuisCourseKey(String courseKey) {
  final iso = dateDepuisCourseKey(courseKey);
  if (iso == null || iso.length < 7) return null;
  return iso.substring(0, 7);
}

/// Clé de stockage mensuelle : `arrivee_officielle_complete_v1_YYYY-MM`.
String cleStockageMois(String mois) => '$kArriveeStoragePrefix$mois';

/// `true` si `cle` est une clé mensuelle de ce stockage, et retourne le mois.
/// Renvoie `null` si le suffixe n'a pas la forme stricte `YYYY-MM`.
String? moisDepuisCleStockage(String cle) {
  if (!cle.startsWith(kArriveeStoragePrefix)) return null;
  final mois = cle.substring(kArriveeStoragePrefix.length);
  if (mois.length != 7 || mois[4] != '-') return null;
  final annee = mois.substring(0, 4);
  final m = mois.substring(5, 7);
  if (int.tryParse(annee) == null || int.tryParse(m) == null) return null;
  final mi = int.parse(m);
  if (mi < 1 || mi > 12) return null;
  return mois;
}

/// Contrôle du statut PMU. Seul `ARRIVEE_DEFINITIVE_COMPLETE` est accepté.
///
/// `isArriveeDefinitive` et `arriveeDefinitive` sont vérifiés S'ILS SONT
/// PRÉSENTS : un drapeau explicitement `false` fait refuser l'arrivée, même si
/// le statut porte le bon libellé. Absents, ils ne bloquent pas : c'est le
/// statut qui fait foi (comportement observé sur l'API réelle, où les deux
/// drapeaux valent `true` sur cet état).
bool estArriveeDefinitiveComplete({
  required String? statut,
  bool? isArriveeDefinitive,
  bool? arriveeDefinitive,
}) {
  if (statut != kStatutArriveeDefinitiveComplete) return false;
  if (isArriveeDefinitive == false) return false;
  if (arriveeDefinitive == false) return false;
  return true;
}

// ─── Service ────────────────────────────────────────────────────────────────

class ArriveeOfficielleService {
  static final ArriveeOfficielleService _instance =
      ArriveeOfficielleService._();
  static ArriveeOfficielleService get instance => _instance;
  ArriveeOfficielleService._();

  /// Shards décodés en mémoire : mois (YYYY-MM) → (courseKey → entrée).
  final Map<String, Map<String, EntreeArrivee>> _shards = {};

  /// Entrées dont l'écriture n'a PAS été confirmée. Aucune limite, aucun
  /// abandon : elles sont rejouées tant qu'elles ne sont pas écrites.
  ///
  /// Miroir EN MÉMOIRE de la clé [kArriveePendingKey]. Toute mutation passe par
  /// `_persisterFile()`, qui écrit d'abord sur le stockage : la file survit donc
  /// à un redémarrage (correctif 2).
  final Map<String, EntreeArrivee> _enAttente = {};

  /// État public, en lecture seule, pour l'audit et les écrans de diagnostic.
  String? derniereErreur;
  bool dernierEcritureConfirmee = true;

  /// Chaîne d'écriture sérialisée : deux écritures ne peuvent pas s'entrelacer
  /// et produire un shard partiel.
  Future<void> _chaineEcriture = Future<void>.value();

  bool _charge = false;
  Future<void>? _chargementEnCours;

  /// Le rejeu de la file n'est tenté qu'UNE fois par processus (correctif L1).
  /// Évite qu'un appel répété de `charger()` rejoue la file en boucle.
  bool _rejeuFileEffectue = false;

  // ── Lecture d'état ────────────────────────────────────────────────────────

  bool get estCharge => _charge;

  int get nbEntrees =>
      _shards.values.fold(0, (s, m) => s + m.length);

  /// Entrées en attente d'écriture confirmée (0 = tout est écrit).
  ///
  /// Persistées dans [kArriveePendingKey] : elles survivent à un redémarrage
  /// (correctif 2). Cette valeur est le miroir mémoire de cette clé.
  int get nbEnAttente => _enAttente.length;

  /// Clés des entrées en attente, triées. Utile au diagnostic et aux tests.
  List<String> get clesEnAttente => _enAttente.keys.toList()..sort();

  /// Réconcilie la file d'attente avec les clés RÉELLEMENT présentes sur le
  /// stockage.
  ///
  /// C'est le SEUL contrôle indépendant du cache Dart : `getKeys()` interroge
  /// le magasin natif, tandis que `getString()` relit le cache optimiste. Cette
  /// méthode ne prouve pas la durabilité d'une écriture (voir la limite
  /// `apply()` documentée en tête de fichier) : elle compte les clés de shard
  /// présentes et signale un éventuel décalage.
  Future<VerificationArrivees> reconcilierAvecLeStockage() async {
    final prefs = await SharedPreferences.getInstance();
    final cles = await enumererClesSurStockage();
    var lues = 0;
    final illisibles = <String>[];
    for (final cle in cles) {
      final mois = moisDepuisCleStockage(cle);
      if (mois == null) {
        illisibles.add(cle);
        continue;
      }
      final shard = _decoderShard(prefs.getString(cle), mois);
      if (shard == null) {
        illisibles.add(cle);
      } else {
        _shards[mois] = shard;
        lues++;
      }
    }
    final v = VerificationArrivees(
      clesPresentes: cles.length,
      clesLues: lues,
      clesIllisibles: illisibles,
      nbEntrees: nbEntrees,
    );
    derniereVerification = v;
    return v;
  }

  /// Mois connus en mémoire, triés.
  List<String> get moisConnus => _shards.keys.toList()..sort();

  // ── Chargement ────────────────────────────────────────────────────────────

  /// Charge tous les shards mensuels. Idempotent, absorbe ses erreurs.
  /// Ne lève jamais : une panne de stockage ne doit pas bloquer l'application.
  Future<void> charger() {
    if (_charge) return Future<void>.value();
    final enCours = _chargementEnCours;
    if (enCours != null) return enCours;
    final future = _chargerInterne();
    _chargementEnCours = future;
    return future;
  }

  Future<void> _chargerInterne() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cles = await enumererClesSurStockage();
      var lues = 0;
      final illisibles = <String>[];

      for (final cle in cles) {
        final mois = moisDepuisCleStockage(cle);
        if (mois == null) {
          illisibles.add(cle);
          continue;
        }
        final shard = _decoderShard(prefs.getString(cle), mois);
        if (shard == null) {
          illisibles.add(cle);
        } else {
          _shards[mois] = shard;
          lues++;
        }
      }

      derniereVerification = VerificationArrivees(
        clesPresentes: cles.length,
        clesLues: lues,
        clesIllisibles: illisibles,
        nbEntrees: nbEntrees,
      );

      if (kDebugMode && illisibles.isNotEmpty) {
        debugPrint('[ArriveeOfficielle] ⚠️ ${illisibles.length} shard(s) '
            'illisible(s), conservés intacts : ${illisibles.join(', ')}');
      }

      // ── FILE D'ATTENTE DURABLE (correctif 2) ───────────────────────────────
      // Rechargée APRÈS les shards : une entrée déjà présente dans un shard
      // confirmé ne doit pas revenir dans la file (elle y aurait été laissée
      // par un arrêt brutal entre l'étape 2 et l'étape 3 de l'ordre d'écriture).
      // Ce filtrage rend le rejeu IDEMPOTENT.
      final fileBrute = prefs.getString(kArriveePendingKey);
      if (fileBrute != null && fileBrute.isNotEmpty) {
        final decodees = _decoderFile(fileBrute);
        if (decodees == null) {
          // File illisible : elle est CONSERVÉE INTACTE sur le disque, jamais
          // écrasée ni supprimée. On ne devine pas son contenu.
          derniereErreur = 'file d\'attente illisible, conservée intacte';
          if (kDebugMode) {
            debugPrint('[ArriveeOfficielle] ⚠️ File d\'attente illisible, '
                'conservée intacte sur le disque ($kArriveePendingKey)');
          }
        } else {
          var reprises = 0;
          for (final e in decodees.values) {
            final mois = e.mois;
            if (mois == null) continue;
            // Déjà écrite dans un shard confirmé → rien à rejouer.
            if (_shards[mois]?.containsKey(e.courseKey) ?? false) continue;
            _enAttente[e.courseKey] = e;
            reprises++;
          }
          if (kDebugMode && reprises > 0) {
            debugPrint('[ArriveeOfficielle] ♻️ $reprises entrée(s) en attente '
                'reprise(s) après redémarrage');
          }
        }
      }
    } catch (e) {
      // Aucun shard n'est détruit : l'état en mémoire reste ce qu'il était.
      derniereErreur = 'charger() : $e';
      if (kDebugMode) {
        debugPrint('[ArriveeOfficielle] charger() échec absorbé : $e');
      }
    } finally {
      _charge = true;
      _chargementEnCours = null;
    }

    // ── REJEU IDEMPOTENT DE LA FILE (L1) ────────────────────────────────────
    // UN SEUL point d'initialisation : ce `finally` de chargement. Aucun autre
    // chemin n'appelle `persisterEnAttente()` automatiquement.
    //
    // Hors du `try` principal, dans son propre `catch` : un échec du rejeu ne
    // doit jamais faire passer `charger()` pour en échec, ni empêcher
    // l'application de démarrer.
    //
    // `_rejeuFileEffectue` garantit une tentative PAR PROCESSUS : une file qui
    // échoue reste en place et n'est pas rejouée en boucle à chaque appel.
    if (!_rejeuFileEffectue && _enAttente.isNotEmpty) {
      _rejeuFileEffectue = true;
      try {
        final rejeu = await persisterEnAttente();
        if (kDebugMode && rejeu.nbEcrites > 0) {
          debugPrint('[ArriveeOfficielle] ♻️ Rejeu : ${rejeu.nbEcrites} entrée(s) '
              'écrite(s) dans leur shard mensuel');
        }
      } catch (e) {
        derniereErreur = 'rejeu file : $e';
        if (kDebugMode) {
          debugPrint('[ArriveeOfficielle] Rejeu file échec absorbé : $e');
        }
      }
    }
  }

  VerificationArrivees? derniereVerification;

  /// Énumère le stockage : découverte DYNAMIQUE des clés mensuelles.
  /// Indépendant de l'état de chargement — sert aux sauvegardes, aux
  /// restaurations et à un éventuel effacement explicite.
  Future<List<String>> enumererClesSurStockage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs
        .getKeys()
        .where((k) => k.startsWith(kArriveeStoragePrefix))
        .toList()
      ..sort();
  }

  // ── Lecture d'une arrivée ─────────────────────────────────────────────────

  /// Retourne l'arrivée complète d'une course, ou `null` si elle n'est pas
  /// stockée. Retourne une COPIE PROFONDE : aucun appelant ne peut altérer
  /// l'état interne, ni par mutation de groupe, ni par ajout de rang.
  List<List<int>>? arrivee(String courseKey) {
    final mois = moisDepuisCourseKey(courseKey);
    if (mois == null) return null;
    final e = _shards[mois]?[courseKey] ?? _enAttente[courseKey];
    if (e == null) return null;
    return _copie(e.rangs);
  }

  /// Nombre de partants DÉCLARÉS, tel que stocké. Métadonnée informative.
  int? declares(String courseKey) {
    final mois = moisDepuisCourseKey(courseKey);
    if (mois == null) return null;
    return (_shards[mois]?[courseKey] ?? _enAttente[courseKey])?.declares;
  }

  /// `true` si une arrivée est stockée pour cette course.
  bool contient(String courseKey) => arrivee(courseKey) != null;

  static List<List<int>> _copie(List<List<int>> src) =>
      src.map((g) => List<int>.unmodifiable(g)).toList(growable: false);

  // ── Lecture DIRECTE du JSON PMU ───────────────────────────────────────────

  /// Construit une entrée depuis l'objet COURSE de `/programme/{DDMMYYYY}`.
  ///
  /// C'est le chemin de lecture DIRECTE exigé : `ordreArrivee` est lu tel quel,
  /// en `List<List<int>>`. Aucun passage par `rangParNumero`, aucune
  /// reconstruction par addition de groupes, aucun aplatissement.
  ///
  /// Retourne `null` — et n'invente rien — si :
  ///   • le statut n'est pas `ARRIVEE_DEFINITIVE_COMPLETE` ;
  ///   • `ordreArrivee` est absent, vide, ou n'est pas une liste de listes ;
  ///   • un rang contient un numéro qui n'est pas un entier > 0 ;
  ///   • un rang est vide ;
  ///   • la date de la course n'est pas lisible dans `courseKey`.
  static EntreeArrivee? depuisJsonCourse(
    Map<String, dynamic> course, {
    required String courseKey,
  }) {
    if (!estArriveeDefinitiveComplete(
      statut: course['statut'] as String?,
      isArriveeDefinitive: course['isArriveeDefinitive'] as bool?,
      arriveeDefinitive: course['arriveeDefinitive'] as bool?,
    )) {
      return null;
    }

    final rangs = lireOrdreArrivee(course['ordreArrivee']);
    if (rangs == null) return null;

    if (moisDepuisCourseKey(courseKey) == null) return null;

    final declaresBrut = course['nombreDeclaresPartants'];
    final declares = declaresBrut is int && declaresBrut > 0
        ? declaresBrut
        : (declaresBrut is num && declaresBrut > 0
            ? declaresBrut.toInt()
            : null);

    return EntreeArrivee(
      courseKey: courseKey,
      rangs: rangs,
      declares: declares,
    );
  }

  /// Convertit un `ordreArrivee` brut en `List<List<int>>`, en CONSERVANT les
  /// groupes d'ex æquo. Retourne `null` si la structure n'est pas exploitable.
  ///
  /// Aucune tolérance silencieuse : un seul groupe invalide fait refuser
  /// l'arrivée entière. Mieux vaut ne rien stocker que stocker une arrivée
  /// partielle qui serait ensuite présentée comme complète.
  static List<List<int>>? lireOrdreArrivee(Object? brut) {
    if (brut is! List || brut.isEmpty) return null;
    final out = <List<int>>[];
    for (final g in brut) {
      if (g is! List || g.isEmpty) return null;
      final groupe = <int>[];
      for (final n in g) {
        if (n is int && n > 0) {
          groupe.add(n);
        } else if (n is num && n > 0 && n == n.toInt()) {
          groupe.add(n.toInt());
        } else {
          return null;
        }
      }
      out.add(List<int>.unmodifiable(groupe));
    }
    return List<List<int>>.unmodifiable(out);
  }

  // ── Écriture ──────────────────────────────────────────────────────────────

  /// Écriture GROUPÉE : une seule écriture par mois concerné.
  ///
  /// C'est la garantie de coût : 62 courses d'une même journée en décembre
  /// coûtent UNE écriture de ~16 Ko, pas 62 écritures de 16 Ko.
  ///
  /// ORDRE D'ÉCRITURE (correctif 2) — imposé par `_executerAvecFile` :
  ///   1. les entrées sont d'abord AJOUTÉES à la file durable et celle-ci est
  ///      écrite sur le stockage ;
  ///   2. les shards mensuels sont écrits ;
  ///   3. les entrées confirmées sont RETIRÉES de la file, qui est réécrite.
  /// Un arrêt brutal entre 1 et 3 laisse une file non vide : la donnée est
  /// reprise au démarrage, et le rejeu est idempotent.
  ///
  /// Fiabilité : si l'écriture d'un mois échoue (exception OU retour `false`),
  /// les entrées de ce mois restent dans la file — rien n'est perdu, rien
  /// n'est déclaré écrit à tort. `resultat.succes` vaut `false` et
  /// `moisEchoues` nomme le mois.
  Future<ResultatEcriture> enregistrerGroupe(
    List<EntreeArrivee> entrees,
  ) async {
    if (entrees.isEmpty) {
      return const ResultatEcriture(succes: true);
    }

    final parMois = <String, Map<String, EntreeArrivee>>{};
    for (final e in entrees) {
      final mois = e.mois;
      if (mois == null) {
        // Refus explicite : aucune date n'est inventée. On ne perd pas
        // l'information silencieusement pour autant : l'appelant est prévenu.
        return ResultatEcriture(
          succes: false,
          nbEnAttente: _enAttente.length,
          erreur: 'courseKey sans date calendaire exploitable : ${e.courseKey}',
        );
      }
      parMois.putIfAbsent(mois, () => {})[e.courseKey] = e;
    }

    return _serialiser(() async {
      final moisEcrits = <String>[];
      final moisEchoues = <String>[];
      final erreurs = <String>[];
      var ecrites = 0;

      // ── ÉTAPE 1 : file d'attente AVANT toute écriture de shard ─────────────
      // Si cette étape échoue, on n'écrit AUCUN shard : mieux vaut ne rien
      // écrire que d'écrire sans file de secours. Les entrées restent en
      // mémoire et l'appelant est prévenu.
      final aMettreEnFile = <String, EntreeArrivee>{
        ..._enAttente,
        for (final m in parMois.keys) ...parMois[m]!,
      };
      final fileOk = await _persisterFile(aMettreEnFile, erreurs);
      _enAttente
        ..clear()
        ..addAll(aMettreEnFile);

      if (!fileOk) {
        // Aucun shard écrit. Rien n'est PERDU dans ce processus : les entrées
        // sont dans `_enAttente` et visibles. Mais la file n'est pas durable.
        dernierEcritureConfirmee = false;
        derniereErreur = erreurs.isEmpty ? null : erreurs.join(' | ');
        return ResultatEcriture(
          succes: false,
          nbEcrites: 0,
          nbEnAttente: _enAttente.length,
          moisEcrits: const [],
          moisEchoues: parMois.keys.toList(),
          erreur: 'file d\'attente non écrite — aucun shard écrit : '
              '${erreurs.join(' | ')}',
        );
      }

      // ── ÉTAPE 2 : shards mensuels ─────────────────────────────────────────
      for (final mois in parMois.keys) {
        final aEcrire = <String, EntreeArrivee>{
          for (final e in _enAttente.values)
            if (e.mois == mois) e.courseKey: e,
        };

        final ok = await _ecrireMois(mois, aEcrire, erreurs);
        if (ok) {
          moisEcrits.add(mois);
          ecrites += parMois[mois]!.length;
          for (final k in aEcrire.keys) {
            _enAttente.remove(k);
          }
        } else {
          moisEchoues.add(mois);
          // Les entrées RESTENT dans la file : rien n'est perdu.
        }
      }

      // ── ÉTAPE 3 : nettoyage de la file, EN DERNIER ────────────────────────
      // Une entrée ne quitte la file qu'une fois son shard confirmé. Si ce
      // nettoyage échoue, la file reste « trop pleine » : le rejeu étant
      // idempotent, c'est sans conséquence — jamais l'inverse.
      final fileFinaleOk = await _persisterFile(_enAttente, erreurs);
      if (!fileFinaleOk && moisEchoues.isEmpty) {
        // Tout est écrit, seule la trace de file est en retard. On le dit
        // sans transformer cela en échec d'écriture des arrivées.
        erreurs.add('file d\'attente non nettoyée (données déjà écrites)');
      }

      dernierEcritureConfirmee = moisEchoues.isEmpty;
      derniereErreur = erreurs.isEmpty ? null : erreurs.join(' | ');

      return ResultatEcriture(
        succes: moisEchoues.isEmpty,
        nbEcrites: ecrites,
        nbEnAttente: _enAttente.length,
        moisEcrits: moisEcrits,
        moisEchoues: moisEchoues,
        erreur: erreurs.isEmpty ? null : erreurs.join(' | '),
      );
    });
  }

  /// Écriture d'une entrée unique. Délègue au chemin groupé : un seul code
  /// d'écriture existe, donc un seul comportement à prouver.
  Future<ResultatEcriture> enregistrer(EntreeArrivee entree) =>
      enregistrerGroupe([entree]);

  /// Rejoue les entrées en attente. À appeler après un échec de stockage.
  Future<ResultatEcriture> persisterEnAttente() async {
    if (_enAttente.isEmpty) {
      return const ResultatEcriture(succes: true);
    }
    final aRejouer = _enAttente.values.toList(growable: false);
    return enregistrerGroupe(aRejouer);
  }

  /// Écrit la FILE D'ATTENTE sur le stockage. Retourne `true` si le stockage a
  /// confirmé l'écriture.
  ///
  /// ⚠️ MÊME LIMITE QUE POUR LES SHARDS : `setString` peut rendre `true` avant
  /// le flush disque (`apply()`). Ce `true` signifie « canal accepté », pas
  /// « durable sur le fichier ». La relecture qui suit est un garde de
  /// COHÉRENCE (elle attrape un store qui altère la valeur), jamais une
  /// preuve de durabilité.
  Future<bool> _persisterFile(
    Map<String, EntreeArrivee> contenu,
    List<String> erreurs,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final String? b64 = _encoderFile(contenu);
    if (b64 == null) {
      erreurs.add('file d\'attente : encodage impossible');
      return false;
    }

    try {
      // File vide → on SUPPRIME la clé plutôt que d'écrire « vide » : aucune
      // clé résiduelle ne peut être confondue avec une file en attente.
      if (contenu.isEmpty) {
        if (prefs.getKeys().contains(kArriveePendingKey)) {
          final ok = await prefs.remove(kArriveePendingKey);
          if (!ok) {
            erreurs.add('file d\'attente : remove a retourné false');
            return false;
          }
        }
        return true;
      }

      final ok = await prefs.setString(kArriveePendingKey, b64);
      if (!ok) {
        erreurs.add('file d\'attente : setString a retourné false');
        return false; // ← garde le plus fort : intercepte AVANT la relecture
      }
      final relu = prefs.getString(kArriveePendingKey);
      if (relu == null || relu.isEmpty) {
        erreurs.add('file d\'attente : écriture non relisible');
        return false;
      }
      if (relu != b64) {
        erreurs.add('file d\'attente : contenu relu différent de l\'écrit');
        return false;
      }
      return true;
    } catch (e) {
      erreurs.add('file d\'attente : $e');
      return false;
    }
  }

  /// Sérialise la file d'attente (base64+gzip, comme les shards).
  String? _encoderFile(Map<String, EntreeArrivee> contenu) {
    try {
      final cles = contenu.keys.toList()..sort();
      final payload = <String, dynamic>{
        'v': kArriveePendingVersion,
        'arrivees': [for (final k in cles) contenu[k]!.toJson()],
      };
      final bytes = utf8.encode(jsonEncode(payload));
      return base64Encode(gzip.encode(bytes));
    } catch (e) {
      derniereErreur = 'encodage file : $e';
      return null;
    }
  }

  /// Décode la file d'attente. `null` si illisible.
  ///
  /// COMPATIBILITÉ : accepte la forme LISTE (`{'v':1,'arrivees':[ {...} ]}`) —
  /// celle écrite par cette version, seule à porter `courseKey`. Une entrée
  /// sans `courseKey` exploitable est IGNORÉE (elle n'est pas rejouable) mais
  /// n'empêche pas de décoder les autres.
  Map<String, EntreeArrivee>? _decoderFile(String b64) {
    if (b64.isEmpty) return null;
    try {
      final jsonStr = utf8.decode(gzip.decode(base64Decode(b64)));
      final j = json.decode(jsonStr);
      if (j is! Map) return null;

      final version = j['v'];
      if (version is num && version.toInt() > kArriveePendingVersion) {
        return null; // version future : conservée intacte, non interprétée
      }

      final arrivees = j['arrivees'];
      if (arrivees is! List) return null;

      final out = <String, EntreeArrivee>{};
      for (final item in arrivees) {
        if (item is! Map) continue;
        final courseKey = item['courseKey'];
        if (courseKey is! String) continue;
        if (moisDepuisCourseKey(courseKey) == null) continue;
        final rangs = lireOrdreArrivee(item['rangs']);
        if (rangs == null) continue;
        final d = item['declares'];
        out[courseKey] = EntreeArrivee(
          courseKey: courseKey,
          rangs: rangs,
          declares: d is num && d > 0 ? d.toInt() : null,
        );
      }
      return out;
    } catch (e) {
      derniereErreur = 'décodage file : $e';
      return null;
    }
  }

  /// Écrit un shard mensuel complet. Retourne `true` UNIQUEMENT si le stockage
  /// a confirmé l'écriture.
  Future<bool> _ecrireMois(
    String mois,
    Map<String, EntreeArrivee> entrees,
    List<String> erreurs,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final cle = cleStockageMois(mois);

    // Le contenu déjà présent sur le disque pour ce mois est conservé : on
    // n'écrase jamais une arrivée confirmée par une absence.
    final fusion = <String, EntreeArrivee>{
      ...?_shards[mois],
      ...entrees,
    };

    final String? b64 = _encoderShard(fusion);
    if (b64 == null) {
      erreurs.add('$mois : encodage impossible');
      return false;
    }

    try {
      final ok = await prefs.setString(cle, b64);
      if (!ok) {
        erreurs.add('$mois : setString a retourné false');
        return false;
      }
      // Relecture de contrôle : on ne déclare écrit que ce qui est relisible.
      final relu = prefs.getString(cle);
      if (relu == null || relu.isEmpty) {
        erreurs.add('$mois : écriture non relisible');
        return false;
      }
      if (relu != b64) {
        erreurs.add('$mois : contenu relu différent de l\'écrit');
        return false; // le shard n'est PAS adopté en mémoire
      }

      _shards[mois] = fusion;
      return true;
    } catch (e) {
      erreurs.add('$mois : $e');
      return false;
    }
  }

  /// Sérialise un shard en base64(gzip(json)). `null` en cas d'échec.
  String? _encoderShard(Map<String, EntreeArrivee> entrees) {
    try {
      final cles = entrees.keys.toList()..sort();
      final payload = <String, dynamic>{
        'v': kArriveeFormatVersion,
        'arrivees': {
          for (final k in cles) k: entrees[k]!._toJsonShard(),
        },
      };
      final bytes = utf8.encode(jsonEncode(payload));
      return base64Encode(gzip.encode(bytes));
    } catch (e) {
      derniereErreur = 'encodage : $e';
      return null;
    }
  }

  /// Décode un shard. `null` si illisible ou de version inconnue — le shard
  /// reste alors INTACT sur le disque, il n'est ni écrasé ni supprimé.
  Map<String, EntreeArrivee>? _decoderShard(String? b64, String mois) {
    if (b64 == null || b64.isEmpty) return null;
    try {
      final jsonStr = utf8.decode(gzip.decode(base64Decode(b64)));
      final j = json.decode(jsonStr);
      if (j is! Map) return null;

      final version = j['v'];
      if (version is num && version.toInt() > kArriveeFormatVersion) {
        // Version future : on ne l'interprète pas, on ne la détruit pas.
        return null;
      }

      final arrivees = j['arrivees'];
      if (arrivees is! Map) return null;

      final out = <String, EntreeArrivee>{};
      for (final e in arrivees.entries) {
        final courseKey = e.key;
        if (courseKey is! String) continue;
        final v = e.value;
        if (v is! Map) continue;

        final rangs = lireOrdreArrivee(v['rangs']);
        if (rangs == null) continue; // entrée invalide ignorée, pas inventée
        // Une entrée rangée sous un autre mois que celui de sa clé est
        // incohérente : elle est ignorée plutôt que déplacée d'office.
        if (moisDepuisCourseKey(courseKey) != mois) continue;

        final d = v['declares'];
        out[courseKey] = EntreeArrivee(
          courseKey: courseKey,
          rangs: rangs,
          declares: d is num && d > 0 ? d.toInt() : null,
        );
      }
      return out;
    } catch (e) {
      derniereErreur = 'décodage $mois : $e';
      return null;
    }
  }

  /// Sérialise les écritures en une chaîne : jamais deux écritures simultanées.
  Future<T> _serialiser<T>(Future<T> Function() action) {
    final resultat = _chaineEcriture.then((_) => action());
    _chaineEcriture = resultat.then<void>((_) {}, onError: (_) {});
    return resultat;
  }

  // ── Sauvegarde / restauration ─────────────────────────────────────────────

  /// Exporte tous les shards ET la file d'attente pour la sauvegarde.
  ///
  /// Découverte DYNAMIQUE des clés (`enumererClesSurStockage`) : un mois écrit
  /// par une version future de l'application est exporté tel quel, sans que
  /// ce service ait besoin de le comprendre.
  ///
  /// CORRECTIF 2 : la file d'attente est exportée depuis le STOCKAGE
  /// (`kArriveePendingKey`), pas seulement depuis la mémoire — une file laissée
  /// par une session précédente serait sinon absente de la sauvegarde. Chaque
  /// entrée porte désormais `courseKey`, ce qui la rend RÉIMPORTABLE ; un
  /// export antérieur au correctif 2 n'en portait pas et reste accepté en
  /// lecture (voir `restaurerDepuisBackup`).
  Future<Map<String, dynamic>> exporterPourBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final cles = await enumererClesSurStockage();
    final shards = <String, String>{};
    for (final cle in cles) {
      final v = prefs.getString(cle);
      if (v != null && v.isNotEmpty) shards[cle] = v;
    }

    // File d'attente : union de la mémoire et du disque. Le disque fait foi
    // pour une ancienne session ; la mémoire pour une écriture en cours.
    final file = <String, EntreeArrivee>{..._enAttente};
    final fileBrute = prefs.getString(kArriveePendingKey);
    if (fileBrute != null && fileBrute.isNotEmpty) {
      final duDisque = _decoderFile(fileBrute);
      if (duDisque != null) {
        for (final e in duDisque.values) {
          file.putIfAbsent(e.courseKey, () => e);
        }
      }
    }

    return {
      'version': kArriveeFormatVersion,
      'nbClefs': shards.length,
      'shards': shards,
      'enAttente': file.values.map((e) => e.toJson()).toList(),
    };
  }

  /// Compare deux arrivées, groupes d'ex æquo compris.
  ///
  /// Deux arrivées sont identiques si elles ont le même nombre de groupes, et
  /// si chaque groupe contient les mêmes numéros **dans le même ordre**. Un
  /// ex æquo `[4,7]` et `[7,4]` sont donc considérés DIFFÉRENTS : l'ordre
  /// publié par le PMU est un fait, on ne le normalise pas.
  static bool memeArrivee(List<List<int>> a, List<List<int>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].length != b[i].length) return false;
      for (var j = 0; j < a[i].length; j++) {
        if (a[i][j] != b[i][j]) return false;
      }
    }
    return true;
  }

  /// Restaure depuis une sauvegarde.
  ///
  /// Règle « local préservé » : une arrivée déjà présente localement n'est
  /// jamais remplacée. On n'ajoute que les courses absentes. Une arrivée est
  /// un fait officiel : en cas de divergence, on ne réécrit pas l'histoire.
  ///
  /// CORRECTIF 1 — les deux situations autrefois confondues sont désormais
  /// DISTINGUÉES :
  ///   • arrivée locale identique → `entreesDejaPresentes` (vrai doublon) ;
  ///   • arrivée locale divergente → `conflits` (liste des `courseKey`).
  /// Un conflit est SIGNALÉ, jamais résolu : l'arrivée locale est conservée
  /// telle quelle, celle de la sauvegarde n'est ni écrite, ni fusionnée, ni
  /// supprimée. Voir [ResultatRestaurationArrivees.aDesConflits].
  ///
  /// Les entrées en attente sont comparées AUSSI : une course présente dans la
  /// file mais pas encore écrite est traitée comme présente localement (elle
  /// l'est, en mémoire durable).
  ///
  /// Un shard indécodable côté sauvegarde est COMPTÉ et IGNORÉ — jamais
  /// substitué, jamais inventé.
  Future<ResultatRestaurationArrivees> restaurerDepuisBackup(
    Map<String, dynamic> backup,
  ) async {
    try {
      await charger();
      final brut = backup['shards'];
      if (brut is! Map) {
        return ResultatRestaurationArrivees.echec('clé "shards" absente ou mal typée');
      }

      var lus = 0;
      var illisibles = 0;
      var ajoutees = 0;
      var dejaPresentes = 0;
      final conflits = <String>[];
      var moisNonEcrits = 0;

      for (final e in brut.entries) {
        final cle = e.key;
        final valeur = e.value;
        if (cle is! String || valeur is! String) {
          illisibles++;
          continue;
        }
        final mois = moisDepuisCleStockage(cle);
        if (mois == null) {
          illisibles++;
          continue;
        }
        final shardSauvegarde = _decoderShard(valeur, mois);
        if (shardSauvegarde == null) {
          illisibles++;
          continue;
        }
        lus++;

        final local = _shards[mois] ?? <String, EntreeArrivee>{};
        final aAjouter = <EntreeArrivee>[];
        for (final entree in shardSauvegarde.values) {
          final locale = local[entree.courseKey] ??
              _enAttente[entree.courseKey];

          if (locale == null) {
            aAjouter.add(entree);
          } else if (memeArrivee(locale.rangs, entree.rangs)) {
            // Vrai doublon : identique. Rien à faire, rien à signaler.
            dejaPresentes++;
          } else {
            // CONFLIT : divergence réelle. On CONSERVE le local et on SIGNALE.
            // Aucune écriture, aucune fusion, aucune suppression.
            conflits.add(entree.courseKey);
            dejaPresentes++;
          }
        }

        if (aAjouter.isEmpty) continue;

        final res = await enregistrerGroupe(aAjouter);
        if (res.succes) {
          ajoutees += aAjouter.length;
        } else {
          moisNonEcrits++;
          // Les entrées sont dans la file durable : rejouables.
        }
      }

      // ── File d'attente de la sauvegarde (correctif 2) ─────────────────────
      // Restaurée ADDITIVEMENT, avec la même règle : une entrée locale prime.
      final fileSauvegarde = backup['enAttente'];
      if (fileSauvegarde is List && fileSauvegarde.isNotEmpty) {
        final aMettreEnFile = <EntreeArrivee>[];
        for (final item in fileSauvegarde) {
          if (item is! Map) continue;
          final courseKey = item['courseKey'];
          // COMPATIBILITÉ : un export antérieur au correctif 2 ne porte pas
          // `courseKey`. Ces entrées ne sont pas réimportables et sont
          // IGNORÉES (jamais devinées) — sans invalider les autres.
          if (courseKey is! String) continue;
          final mois = moisDepuisCourseKey(courseKey);
          if (mois == null) continue;
          final rangs = lireOrdreArrivee(item['rangs']);
          if (rangs == null) continue;
          if (_shards[mois]?.containsKey(courseKey) ?? false) continue;
          if (_enAttente.containsKey(courseKey)) continue;
          final d = item['declares'];
          aMettreEnFile.add(EntreeArrivee(
            courseKey: courseKey,
            rangs: rangs,
            declares: d is num && d > 0 ? d.toInt() : null,
          ));
        }
        if (aMettreEnFile.isNotEmpty) {
          final res = await enregistrerGroupe(aMettreEnFile);
          if (res.succes) {
            ajoutees += aMettreEnFile.length;
          } else {
            moisNonEcrits++;
          }
        }
      }

      return ResultatRestaurationArrivees(
        succes: moisNonEcrits == 0,
        shardsLus: lus,
        shardsIllisibles: illisibles,
        entreesAjoutees: ajoutees,
        entreesDejaPresentes: dejaPresentes,
        conflits: List<String>.unmodifiable(conflits),
        moisNonEcrits: moisNonEcrits,
        erreur: moisNonEcrits == 0
            ? null
            : '$moisNonEcrits mois non confirmé(s), entrées conservées en attente',
      );
    } catch (e) {
      return ResultatRestaurationArrivees.echec('restauration : $e');
    }
  }

  // ── Effacement explicite (NON branché sur la réinitialisation en L0) ─────

  /// Efface DÉFINITIVEMENT toutes les arrivées (stockage + mémoire).
  ///
  /// ⚠️ Volontairement NON appelée par `BackupService.reinitialiserComplet()` :
  /// décision validée, ce stockage est conservé lors d'une réinitialisation,
  /// comme l'archive `ia_archive_v1_*`. Cette méthode existe pour un effacement
  /// EXPLICITE futur ; elle ne réinjecte rien dans la mémoire active.
  Future<int> effacerTout() async {
    final prefs = await SharedPreferences.getInstance();
    final cles = await enumererClesSurStockage();
    var effacees = 0;
    for (final cle in cles) {
      try {
        if (await prefs.remove(cle)) effacees++;
      } catch (e) {
        derniereErreur = 'effacerTout($cle) : $e';
      }
    }
    // La file d'attente fait partie de CE stockage : un effacement explicite
    // l'efface aussi, sinon des entrées orphelines seraient rejouées après.
    if (prefs.getKeys().contains(kArriveePendingKey)) {
      try {
        if (await prefs.remove(kArriveePendingKey)) effacees++;
      } catch (e) {
        derniereErreur = 'effacerTout($kArriveePendingKey) : $e';
      }
    }
    _shards.clear();
    _enAttente.clear();
    _charge = true;
    return effacees;
  }

  /// Vide la mémoire sans toucher au disque. Utilisé par les tests et par un
  /// éventuel rechargement forcé. Ne réinjecte rien nulle part.
  @visibleForTesting
  void viderMemoireSeulement() {
    _shards.clear();
    _enAttente.clear();
    _charge = false;
    _chargementEnCours = null;
    _rejeuFileEffectue = false;
    derniereVerification = null;
    derniereErreur = null;
    dernierEcritureConfirmee = true;
  }
}
