// ═══════════════════════════════════════════════════════════════════════════
//  IaArchiveService — C1-a / Étape E1 : archive permanente EN ÉCRITURE SEULE
//
//  RÔLE
//  ────
//  Conserver définitivement les pronostics évincés de la mémoire de travail IA
//  (limitée à 600) sans JAMAIS perturber l'apprentissage.
//
//  ISOLATION ABSOLUE (contrainte non négociable)
//  ──────────────────────────────────────────────
//  Ce service :
//   • n'est lu par AUCUNE fonction d'apprentissage ;
//   • ne modifie jamais _poids, _seuils, _pronostics ni le TOP3 ;
//   • ne réinjecte JAMAIS un ancien pronostic dans la mémoire de travail.
//  À E1, il n'est lu par aucun écran : le calendrier reste strictement inchangé.
//
//  GARANTIES DE CONSERVATION
//  ─────────────────────────
//   1. AUCUN ABANDON : ce fichier ne contient aucune instruction de
//      suppression, de plafonnement ni de renoncement sur la file d'échec.
//      On n'y trouve aucun removeWhere / take / sublist / clear sur cette file.
//   2. La référence est sécurisée de façon SYNCHRONE dans la file AVANT que
//      l'appelant ne retire l'objet de `_pronostics`. Il existe donc toujours
//      un instant où l'objet est référencé deux fois : par la mémoire de
//      travail ET par la file de conservation.
//   3. Un échec (bool false) comme une exception sont capturés : l'objet reste
//      dans la file, et le blob `ia_pronostics_v2_gz` est GELÉ (voir
//      doitGelerBlobPronostics) tant que la file n'est pas vidée. Rien n'est
//      détruit.
//   4. Un pronostic JAMAIS persisté (créé puis évincé avant tout _save) peut
//      être définitivement perdu si le stockage entier tombe en panne : aucune
//      récupération n'est promise dans ce cas. C'est reconnu explicitement.
//
//  DURABILITÉ : deux niveaux distincts, jamais confondus
//  ──────────────────────────────────────────────────────
//   • DURABILITÉ ANNONCÉE : setString/setStringList a renvoyé true, c'est-à-dire
//     « la couche plateforme déclare l'écriture réussie ». Ce n'est PAS une
//     garantie contre une coupure d'alimentation pendant le fsync, ni contre
//     une corruption ultérieure du stockage.
//   • DURABILITÉ CONSTATÉE : le shard est relu au démarrage suivant et se
//     décode correctement (voir VerificationArchive / réconciliation).
//  Le code ne vérifie JAMAIS une écriture par relecture : le cache de
//  shared_preferences est mis à jour AVANT le disque
//  (shared_preferences-2.5.3/lib/src/shared_preferences_legacy.dart:178-188),
//  une relecture ne prouverait donc rien.
//
//  IDENTITÉ / VERSIONS (C1-a validé)
//  ─────────────────────────────────
//   • Identité de prédiction = courseKey → sert au regroupement.
//   • Version = empreinte du CONTENU (courseKey + datePronostic + scoresIA +
//     scoresCriteres + résultat). Deux versions de même empreinte = no-op.
//   • Le motif technique (éviction / troncature) est un simple champ d'audit :
//     il n'entre PAS dans l'empreinte et ne crée jamais de doublon.
//   • Une SEULE version retenue par courseKey (ordre d'autorité total) ; les
//     autres sont conservées intégralement au journal de versions.
//   • Aucune recombinaison de champs entre deux versions : on sélectionne une
//     version ENTIÈRE. (Interdiction de la fabrication rétroactive.)
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io'; // GZipCodec — même dépendance que ia_memory_service.dart

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/connaissances/_archives/archives_segmentees.dart';
import '../data/connaissances/_core/empreinte_contenu.dart';
import 'ia_memory_models.dart';

// ─── Clés de persistance ────────────────────────────────────────────────────
const String kIaArchiveManifestKey = 'ia_archive_v1_manifest';
const String _kShardPrefix = 'ia_archive_v1_';

/// Version interne du format d'archive (distincte de la version de backup).
const int kIaArchiveFormatVersion = 1;

// ─── Motif d'archivage (audit uniquement — jamais dans l'empreinte) ─────────
class ArchiveReason {
  /// Retrait de la mémoire de travail (dépassement de la limite de 600).
  static const eviction = 'eviction';

  /// Excédent au moment de l'écriture du blob des pronostics.
  static const troncature = 'troncature';

  /// ★ E3 — version réintroduite depuis une sauvegarde (fusion protectrice).
  static const restauration = 'restauration';
}

// ─── Rapport de restauration d'archive (★ E3) ──────────────────────────────
class ResultatRestaurationArchive {
  final bool succes;

  /// Shards du backup réellement décodés.
  final int shardsLus;

  /// Shards du backup présents mais indécodables (ignorés, jamais substitués).
  final int shardsIllisibles;

  /// Versions ajoutées à l'archive locale.
  final int versionsAjoutees;

  /// Versions déjà connues (même empreinte) → aucun doublon créé.
  final int versionsDejaPresentes;

  /// Versions importées devenues la version retenue (plus autoritaires).
  final int predictionsAmeliorees;

  /// Versions importées conservées mais NON retenues : la version locale,
  /// plus autoritaire, n'a pas été rétrogradée.
  final int predictionsConservees;

  /// Mois dont l'écriture n'a pas été confirmée après la restauration.
  final int moisNonEcrits;

  final String? erreur;

  const ResultatRestaurationArchive({
    required this.succes,
    this.shardsLus = 0,
    this.shardsIllisibles = 0,
    this.versionsAjoutees = 0,
    this.versionsDejaPresentes = 0,
    this.predictionsAmeliorees = 0,
    this.predictionsConservees = 0,
    this.moisNonEcrits = 0,
    this.erreur,
  });

  factory ResultatRestaurationArchive.echec(String erreur) =>
      ResultatRestaurationArchive(succes: false, erreur: erreur);

  /// Résumé lisible de l'effet d'autorité (aucune rétrogradation possible).
  String get predictionsAmelioreesLabel =>
      '$predictionsAmeliorees améliorée(s), '
      '$predictionsConservees conservée(s) sans rétrogradation';

  @override
  String toString() => 'ResultatRestaurationArchive(succes=$succes, '
      'lus=$shardsLus, illisibles=$shardsIllisibles, '
      'ajoutees=$versionsAjoutees, doublons=$versionsDejaPresentes, '
      'ameliorees=$predictionsAmeliorees, conservees=$predictionsConservees, '
      'moisNonEcrits=$moisNonEcrits)';
}

// ─── État public de l'archive ───────────────────────────────────────────────
enum EtatArchive {
  /// File vide : tout ce qui devait être archivé l'a été.
  sain,

  /// File non vide, mais les derniers essais ne sont pas tous en échec.
  degrade,

  /// File non vide et ≥ 5 cycles consécutifs en échec : stockage indisponible.
  panne,
}

// ─── Rapport de réconciliation au démarrage ─────────────────────────────────
class VerificationArchive {
  final int shardsAttendus;
  final int shardsLus;
  final List<String> shardsPerdus; // clé absente du stockage
  final List<String> shardsIllisibles; // présente mais indécodable
  final bool manifesteReconstruit;

  const VerificationArchive({
    required this.shardsAttendus,
    required this.shardsLus,
    required this.shardsPerdus,
    required this.shardsIllisibles,
    required this.manifesteReconstruit,
  });

  bool get parfaite => shardsPerdus.isEmpty && shardsIllisibles.isEmpty;

  @override
  String toString() => 'VerificationArchive(attendus=$shardsAttendus, '
      'lus=$shardsLus, perdus=${shardsPerdus.length}, '
      'illisibles=${shardsIllisibles.length}, '
      'manifesteReconstruit=$manifesteReconstruit)';
}

// ═══════════════════════════════════════════════════════════════════════════
//  SERVICE
// ═══════════════════════════════════════════════════════════════════════════

class IaArchiveService extends ChangeNotifier {
  static final IaArchiveService _instance = IaArchiveService._();
  static IaArchiveService get instance => _instance;
  IaArchiveService._();

  // ── État en mémoire (chargé paresseusement) ──────────────────────────────
  bool _charge = false;
  Completer<void>? _loadCompleter;

  /// Mois (YYYY-MM) → versions archivées, déjà dédoublonnées par empreinte.
  /// ⚠️ Clé = mois du SHARD PHYSIQUE (mois d'écriture), pas de la date.
  final Map<String, List<IaPronostic>> _shards = {};

  /// ★ A4-3 — Index mensuel fondé sur la DATE EFFECTIVE (`_moisDe`).
  ///
  /// Pourquoi : `_shards` est partitionné par mois d'ÉCRITURE. Une version
  /// rangée dans un autre shard que celui de sa `datePronostic` était alors
  /// invisible des DEUX mois : absente du mois réel (elle n'y est pas rangée)
  /// et rejetée du mois de son shard (le filtre de date la refuse).
  ///
  /// Cet index est une SECONDE VUE du même contenu : il ne stocke aucune copie,
  /// seulement des références aux objets déjà présents dans `_shards`. Le
  /// rangement physique (`_shards`) et la date des pronostics ne sont jamais
  /// modifiés.
  ///
  /// Synchronisation — uniquement aux 3 points où `_shards` mute :
  ///   • `_decoderShard`     (chargement / redémarrage)
  ///   • `_integrerEnMemoire` (éviction, restauration)
  ///   • `_resetInMemory`    (réinitialisation, effacement total)
  final Map<String, List<IaPronostic>> _parDateEffective = {};

  /// courseKey → empreintes déjà présentes (dédoublonnage O(1)).
  final Map<String, Set<String>> _empreintesParCourse = {};

  /// ★ E3 — clés de shards RÉELLEMENT présentes sur le stockage (noms complets).
  /// Alimentée par énumération au chargement et par chaque écriture confirmée.
  final Set<String> _clesShardsConnues = {};

  /// courseKey → empreinte de la version retenue.
  final Map<String, String> _versionRetenue = {};

  /// courseKey → version retenue (objet complet).
  final Map<String, IaPronostic> _retenues = {};

  /// État de la dernière consultation ciblée du miroir (voir
  /// [etatDerniereConsultationArchive]). Tenu ici pour que le repli soit
  /// OBSERVABLE et jamais confondu avec une lecture réussie.
  ConsultationArchive? _derniereConsultationArchive;

  /// Compteurs de mesure : combien de consultations, combien repliées.
  int _nbConsultationsArchive = 0;
  int _nbConsultationsRepliees = 0;

  /// Journal d'audit : courseKey → {empreinte, motif, retenue}. Rien n'est détruit.
  final Map<String, List<Map<String, String>>> _journalVersions = {};

  /// File des évictions dont l'archivage n'a pas été confirmé.
  /// AUCUNE LIMITE. AUCUN ABANDON.
  final List<IaPronostic> _evictionsNonArchivees = [];

  /// Objets en file pas encore indexés en mémoire (intégration différée après
  /// le chargement, car `enregistrerEviction` est synchrone).
  final List<_EntreeFile> _aIntegrer = [];

  /// ★ E3 — mois dont l'écriture n'a PAS été confirmée après une restauration.
  /// Conservés en mémoire ET rejoués au prochain `persisterEnAttente()` :
  /// une restauration interrompue ne perd rien, elle est simplement reprise.
  final Set<String> _moisARepersister = {};

  /// Chaîne d'écriture sérialisée : empêche tout entrelacement de shards.
  Future<void> _writeChain = Future<void>.value();

  // ── État public (consultable, sans effet sur l'apprentissage) ────────────
  bool dernierArchivageConfirme = true;
  String? derniereErreurArchive;
  int cyclesEchecConsecutifs = 0;
  bool alerteMemoireArchive = false;
  VerificationArchive? derniereVerificationArchive;

  int get nbEvictionsNonArchivees => _evictionsNonArchivees.length;

  EtatArchive get etatArchive {
    if (_evictionsNonArchivees.isEmpty) return EtatArchive.sain;
    if (cyclesEchecConsecutifs >= 5) return EtatArchive.panne;
    return EtatArchive.degrade;
  }

  /// `true` si l'appelant doit GELER l'écriture du blob des pronostics.
  ///
  /// Le gel couvre DEUX cas, pas un :
  ///  • une éviction attend son archivage (E1) ;
  ///   → le blob de travail ne peut pas être réécrit sans elle ;
  ///  • un mois restauré n'a pas confirmé son écriture (E3).
  ///   N'inclure que le premier laisserait un `_save()` ultérieur réécrire
  ///   le blob alors qu'une restauration n'est pas encore durable.
  bool get doitGelerBlobPronostics =>
      _evictionsNonArchivees.isNotEmpty || _moisARepersister.isNotEmpty;

  /// Nombre total de versions archivées (toutes courses, tous mois).
  int get nbVersionsArchivees => _shards.values.fold(0, (s, l) => s + l.length);

  /// Nombre de prédictions distinctes (courseKey) représentées.
  int get nbPredictionsDistinctes => _retenues.length;

  /// Clés de stockage réellement présentes (manifeste + tous les shards vus).
  ///
  /// ★ E3 : cette liste est alimentée par ÉNUMÉRATION du stockage au chargement
  /// ET par chaque écriture réussie — et non par `_shards.keys`. Un shard
  /// présent sur le disque mais indécodable n'apparaît pas dans `_shards` ;
  /// il doit malgré tout figurer ici pour qu'une réinitialisation complète
  /// l'efface vraiment.
  List<String> get clesPersistees =>
      [kIaArchiveManifestKey, ...(_clesShardsConnues.toList()..sort())];

  /// Énumère directement le stockage : indépendant de l'état de chargement.
  /// C'est cette liste qu'utilisent les réinitialisations : elle ne peut pas
  /// « oublier » un shard présent sur le disque.
  Future<List<String>> enumererClesSurStockage() async {
    final prefs = await SharedPreferences.getInstance();
    final cles = prefs
        .getKeys()
        .where((k) => k == kIaArchiveManifestKey || k.startsWith(_kShardPrefix))
        .toList()
      ..sort();
    return cles;
  }

  /// Efface DÉFINITIVEMENT l'archive (stockage + mémoire).
  /// Appelée uniquement par les réinitialisations explicites de l'utilisateur ;
  /// aucune autre fonction de l'application ne l'utilise.
  Future<void> effacerTout() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in await enumererClesSurStockage()) {
      await prefs.remove(k);
    }
    _resetInMemory();
    _charge = true;
  }

  /// Nombre de shards connus sur le stockage (y compris illisibles).
  int get nbShardsSurDisque => _clesShardsConnues.length;

  // ═══════════════════════════════════════════════════════════════════════
  //  CHARGEMENT (idempotent, sûr en concurrence)
  // ═══════════════════════════════════════════════════════════════════════

  /// ★ E2 — vrai lorsque les shards sont réellement disponibles en mémoire.
  /// Distinct de `_charge` qui n'est mis à `true` qu'après un chargement
  /// RÉUSSI : un échec laisse `_charge = false` et autorise une nouvelle
  /// tentative (condition 6 de l'autorisation E2).
  bool get archiveDisponible => _charge;

  /// Dernière erreur de chargement (null si le dernier chargement a réussi).
  String? derniereErreurChargement;

  /// ★ E2 — Chargement public destiné à l'affichage (calendrier).
  ///
  /// Garanties (condition 6) :
  ///   • AUCUN chargement concurrent : deux appels simultanés partagent la
  ///     même `_loadCompleter` (idempotence déjà assurée par `_load`).
  ///   • NOTIFICATION APRÈS DISPONIBILITÉ RÉELLE : la notification est émise
  ///     APRÈS la fin effective du chargement (jamais avant), et l'état publié
  ///     est l'état RÉEL — `archiveDisponible` vaut `true` si les shards ont
  ///     effectivement été chargés, `false` sinon. Un simple
  ///     `notifyListeners()` dans un `finally` annoncerait « c'est fini » sans
  ///     garantir que l'état soit exploitable ; ici l'écouteur peut toujours
  ///     trancher sur `archiveDisponible`.
  ///   • ÉCHEC RÉCUPÉRABLE : l'exception est absorbée, mémorisée dans
  ///     [derniereErreurChargement], `_charge` reste `false` → l'appelant
  ///     peut relancer [charger] et réussir. On notifie quand même (une fois)
  ///     pour qu'un écouteur ayant déjà affiché l'état mémoire seul ne reste
  ///     pas suspendu : il verra `archiveDisponible == false` et pourra
  ///     proposer une nouvelle tentative.
  Future<void> charger() async {
    if (_charge) return;
    // Un chargement est-il DÉJÀ piloté par un autre appelant ? Si oui, on
    // attend le future partagé et on lui laisse l'unique notification.
    final dejaEnCours = _loadCompleter != null;
    try {
      await _load();
    } catch (e) {
      // `_load` a déjà mémorisé l'erreur ; on la conserve pour l'affichage.
      if (kDebugMode) {
        debugPrint('[IaArchive] chargement en échec : $e');
      }
    }
    if (dejaEnCours) return; // une seule notification par cycle de chargement
    // Notification unique, post-chargement. `archiveDisponible` indique si les
    // données sont réellement exploitables ; `derniereErreurChargement` est
    // null en cas de succès, renseignée en cas d'échec.
    notifyListeners();
  }

  Future<void> _load() async {
    if (_charge) return;
    if (_loadCompleter != null) return _loadCompleter!.future;
    final completer = Completer<void>();
    _loadCompleter = completer;
    try {
      await _chargerDepuisStockage();
      _charge = true;
      derniereErreurChargement = null;
      completer.complete();
      _loadCompleter = null;
    } catch (e) {
      // ★ E2 : l'échec est mémorisé et l'exception remonte à l'appelant
      // initiateur — un export/restauration ne doit JAMAIS continuer
      // silencieusement sur une archive incomplète. `_charge` reste `false`,
      // donc une nouvelle tentative est possible. Les appelants concurrents
      // reçoivent une complétion normale mais constatent `_charge == false`.
      derniereErreurChargement = e.toString();
      completer.complete();
      _loadCompleter = null;
      rethrow;
    }
  }

  Future<void> _chargerDepuisStockage() async {
    final prefs = await SharedPreferences.getInstance();

    // Correspondance V1 → V2 : rechargée AVANT les shards, afin qu'elle soit
    // disponible pour tout audit ultérieur. Elle ne conditionne aucune
    // décision d'identité (le canonique V2 est autonome).
    await _chargerCorrespondanceEmpreintes(prefs);

    final clesPresentes = prefs
        .getKeys()
        .where((k) => k.startsWith(_kShardPrefix))
        .where((k) => k != kIaArchiveManifestKey)
        .toList();

    // ★ E3 : la liste des clés réellement sur le disque est mémorisée TELLE
    // QUELLE (y compris les shards indécodables) : elle sert à l'export
    // fidèle et à la réinitialisation complète.
    _clesShardsConnues
      ..clear()
      ..addAll(clesPresentes);

    // Manifeste : sert à DÉTECTER les shards manquants, jamais à les inventer.
    final attendus = <String>{};
    final manifesteBrut = prefs.getString(kIaArchiveManifestKey);
    if (manifesteBrut != null && manifesteBrut.isNotEmpty) {
      try {
        final j = json.decode(manifesteBrut) as Map<String, dynamic>;
        for (final m in (j['mois'] as List<dynamic>? ?? [])) {
          attendus.add(m.toString());
        }
      } catch (_) {
        // Manifeste illisible → reconstruit par énumération.
      }
    }

    final perdus = <String>[];
    final illisibles = <String>[];
    var lus = 0;

    for (final cle in clesPresentes) {
      final mois = cle.substring(_kShardPrefix.length);
      if (_decoderShard(prefs, cle, mois)) {
        lus++;
      } else {
        illisibles.add(cle);
      }
    }

    for (final mois in attendus) {
      if (!clesPresentes.contains('$_kShardPrefix$mois')) {
        perdus.add('$_kShardPrefix$mois');
      }
    }

    final manifesteReconstruit = attendus.isEmpty && clesPresentes.isNotEmpty;
    if (manifesteReconstruit) await _ecrireManifeste();

    derniereVerificationArchive = VerificationArchive(
      shardsAttendus: attendus.length,
      shardsLus: lus,
      shardsPerdus: perdus,
      shardsIllisibles: illisibles,
      manifesteReconstruit: manifesteReconstruit,
    );

    if (kDebugMode && !derniereVerificationArchive!.parfaite) {
      debugPrint('[IaArchive] ⚠️ Réconciliation : ${perdus.length} perdu(s), '
          '${illisibles.length} illisible(s). Aucune reconstitution.');
    }
  }

  bool _decoderShard(SharedPreferences prefs, String cle, String mois) {
    final b64 = prefs.getString(cle);
    if (b64 == null || b64.isEmpty) return false;
    final versions = _decoderVersions(b64);
    if (versions == null) return false;
    _shards[mois] = versions;
    for (final p in versions) {
      _enregistrerIndex(p);
      _indexerParDateEffective(p);
    }
    return true;
  }

  /// Décode `base64(gzip(json))` en liste de pronostics.
  /// Retourne `null` si l'enveloppe est indécodable. Une ENTRÉE individuelle
  /// corrompue est ignorée sans détruire les autres.
  static List<IaPronostic>? _decoderVersions(String b64) {
    if (b64.isEmpty) return null;
    try {
      final bytes = base64Decode(b64);
      final jsonStr = utf8.decode(GZipCodec().decode(bytes));
      final raw = json.decode(jsonStr) as List<dynamic>;
      final versions = <IaPronostic>[];
      for (final item in raw) {
        try {
          versions.add(IaPronostic.fromJson(item as Map<String, dynamic>));
        } catch (_) {
          // Une entrée corrompue ne détruit pas les autres.
        }
      }
      return versions;
    } catch (_) {
      return null;
    }
  }

  static String _encoderVersions(List<IaPronostic> versions) {
    final jsonStr = json.encode(versions.map((p) => p.toJson()).toList());
    return base64Encode(GZipCodec().encode(utf8.encode(jsonStr)));
  }

  void _resetInMemory() {
    _charge = false;
    _loadCompleter = null;
    _shards.clear();
    _parDateEffective.clear();
    _empreintesParCourse.clear();
    _clesShardsConnues.clear();
    _versionRetenue.clear();
    _retenues.clear();
    _journalVersions.clear();
    _evictionsNonArchivees.clear();
    _aIntegrer.clear();
    _moisARepersister.clear();
    _writeChain = Future<void>.value();
    dernierArchivageConfirme = true;
    derniereErreurArchive = null;
    cyclesEchecConsecutifs = 0;
    alerteMemoireArchive = false;
    derniereVerificationArchive = null;
    // ★ E2 : l'erreur de chargement fait partie de l'état RAM remis à zéro.
    derniereErreurChargement = null;
  }

  /// Simule un redémarrage : vide l'état RAM, puis relit le stockage.
  @visibleForTesting
  Future<void> reinitialiserMemoirePourTest() async {
    _resetInMemory();
    await _load();
  }

  /// ★ E2 — Vide l'état RAM SANS relire le stockage.
  ///
  /// Permet de tester le cycle réel `charger()` (aucun chargement préalable).
  /// N'affecte aucun comportement de production : réservé aux tests.
  @visibleForTesting
  void oublierChargementPourTest() {
    _resetInMemory();
  }

  /// Remise à zéro complète (mémoire + stockage) — utilisé par les tests.
  @visibleForTesting
  Future<void> viderPourTest() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys().toList()) {
      if (k.startsWith(_kShardPrefix)) await prefs.remove(k);
    }
    _resetInMemory();
    _charge = true;
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  EMPREINTE / IDENTITÉ / AUTORITÉ
  // ═══════════════════════════════════════════════════════════════════════

  /// ═════════════════════════════════════════════════════════════════════════
  ///  EMPREINTE DE CONTENU — DEUX CANONIQUES VERSIONNÉS
  ///
  ///  DÉFAUT MESURÉ (R-3bis), cause exacte :
  ///  le canonique **V1** ne couvrait que 7 champs — `courseKey`,
  ///  `datePronostic`, `scoresIA`, `scoresCriteres`, `resultatsReels`,
  ///  `arriveeReelle`, `dateResultat`. Il ignorait notamment
  ///  `rangFavoriIaDansArrivee`, `typePariConseille`,
  ///  `nbTop3/Top5DansArriveeReelle`, `favoriIaNom`, `varianceScores`,
  ///  `confiancePredite`, `scorePerformance`, `precisionIA`,
  ///  `tauxReussiteAuMoment`, `diagnosticApprentissage`, `coteFavoriPmu`,
  ///  `cotesPmuParNumero`.
  ///  Mesure du défaut :
  ///    `[DIAG] rang 1         -> 51b1b1687572ce2c`
  ///    `[DIAG] rang 3         -> 51b1b1687572ce2c`
  ///    `[DIAG] type différent -> 51b1b1687572ce2c`
  ///  Trois contenus AUTHENTIQUEMENT DIFFÉRENTS recevaient la MÊME empreinte :
  ///  le second était rejeté comme doublon et **silencieusement perdu**. C'est
  ///  la violation de l'arbitrage : « une règle d'autorité ne doit jamais
  ///  entraîner la perte d'une autre version authentique ».
  ///
  ///  CORRECTIF — V2 :
  ///  l'empreinte devient le SHA-256 du `toJson()` COMPLET, normalisé et
  ///  sérialisé canoniquement par `_core/empreinte_contenu.dart`. C'est
  ///  **exactement** la fonction déjà employée par le miroir consultable
  ///  (`ArchivesSegmenteess` → `empreinteValeur`). Les deux couches partagent
  ///  enfin la même notion d'identité au lieu d'en avoir deux divergentes.
  ///  `toJson()` couvre tous les champs significatifs, et la sérialisation
  ///  canonique neutralise l'ordre des clés : deux contenus sémantiquement
  ///  identiques restent donc déduplicables quelle que soit leur
  ///  représentation technique.
  ///
  ///  COMPATIBILITÉ :
  ///  V1 est CONSERVÉ à l'identique (`empreinteV1De`) et reste calculable, ce
  ///  qui permet de reconnaître les empreintes historiques sans les remplacer
  ///  brutalement. Voir `migrerEmpreintesV1VersV2()`.
  ///
  ///  Le motif technique (éviction / troncature) n'entre dans AUCUN des deux
  ///  canoniques : une éviction et une troncature du même contenu restent une
  ///  seule et même version.
  /// ═════════════════════════════════════════════════════════════════════════

  /// Longueur d'une empreinte V1 (FNV-1a 64 bits en hexadécimal).
  static const int kLongueurEmpreinteV1 = 16;

  /// Longueur d'une empreinte V2 (SHA-256 en hexadécimal).
  static const int kLongueurEmpreinteV2 = 64;

  /// Version d'empreinte utilisée pour toute NOUVELLE écriture.
  static const int kVersionEmpreinte = 2;

  /// Empreinte courante (V2) : SHA-256 du contenu COMPLET canonique.
  ///
  /// Alignée sur `_core/empreinte_contenu.dart`, donc sur le miroir
  /// `ArchivesSegmenteess`. Deux contenus identiques → même empreinte ; deux
  /// contenus différents → empreintes différentes, sans exception.
  static String empreinteDe(IaPronostic p) => empreinteV2De(p);

  /// Champs de PRÉSENTATION exclus du canonique — décision architecturale
  /// PRÉEXISTANTE, pas une facilité de mesure.
  ///
  /// `nomCourse` est un libellé d'affichage, jamais une donnée de contenu :
  ///   • `completudeDe` ne le compte pas (voir sa définition) ;
  ///   • `v48_a2_priorite_autorite_test.dart` (A2-T6) l'utilise explicitement
  ///     comme « marqueur observable » pour savoir QUELLE fiche est retenue,
  ///     en documentant : « `nomCourse` n'entre ni dans `empreinteDe` ni dans
  ///     `completudeDe` ».
  /// L'inclure dans V2 aurait inventé une différence de contenu là où il n'y
  /// a qu'une différence de libellé, et cassé un contrat existant. Tous les
  /// autres champs de `toJson()` restent couverts.
  static const Set<String> kChampsNonSignificatifs = <String>{'nomCourse'};

  /// Empreinte V2 — SHA-256 du `toJson()` complet, sérialisé canoniquement.
  ///
  /// Seuls [kChampsNonSignificatifs] sont retirés. Ce sont des libellés
  /// d'affichage, pas des données : le contenu historique reste intégralement
  /// distingué par ailleurs.
  static String empreinteV2De(IaPronostic p) {
    final contenu = p.toJson()
      ..removeWhere((cle, _) => kChampsNonSignificatifs.contains(cle));
    return empreinteValeur(contenu);
  }

  /// Empreinte V1 — FNV-1a 64 bits sur le canonique HISTORIQUE partiel.
  ///
  /// Conservée SANS AUCUNE CORRECTION, pour deux raisons :
  ///   • reconnaître les empreintes déjà persistées (journal, miroir, backups) ;
  ///   • ne jamais modifier une donnée historique.
  /// Elle n'est PLUS utilisée pour décider de l'identité d'une nouvelle
  /// version : c'est précisément elle qui causait la perte.
  static String empreinteV1De(IaPronostic p) {
    final scoresIA = p.scoresIA.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final criteres = p.scoresCriteres.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final arrivee = (p.arriveeReelle ?? const <int>[]).join(',');

    final canonique = StringBuffer()
      ..write(p.courseKey)
      ..write('|')
      ..write(p.datePronostic.toIso8601String())
      ..write('|')
      ..write(scoresIA.map((e) => '${e.key}=${e.value}').join(';'))
      ..write('|')
      ..write(criteres
          .map((e) => '${e.key}=${e.value.toJson().values.join(",")}')
          .join(';'))
      ..write('|')
      ..write(p.resultatsReels ? '1' : '0')
      ..write('|')
      ..write(arrivee)
      ..write('|')
      ..write(p.dateResultat?.toIso8601String() ?? '');

    return _fnv1a64(canonique.toString());
  }

  /// Version d'une empreinte, déduite de sa LONGUEUR.
  ///
  /// Les deux canoniques produisent des longueurs disjointes (16 vs 64) : le
  /// test est donc sûr et ne peut pas se tromper de version. Une empreinte de
  /// longueur inattendue retourne 0 et n'est **jamais** réinterprétée de force.
  static int versionEmpreinte(String empreinte) {
    if (empreinte.length == kLongueurEmpreinteV2) return 2;
    if (empreinte.length == kLongueurEmpreinteV1) return 1;
    return 0;
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  MIGRATION DES EMPREINTES V1 → V2
  //
  //  PRINCIPE : la migration ne modifie AUCUNE donnée historique. Elle
  //  construit une table de correspondance `V1 → {V2...}` à partir des
  //  versions réellement présentes, et la persiste pour être reprise et
  //  auditable. C'est une opération PUREMENT DÉRIVÉE :
  //    • idempotente (ensembles) ;
  //    • reprenable (rien à moitié écrit : la table est réécrite en entier) ;
  //    • sans perte (aucune version n'est touchée) ;
  //    • sans réinitialisation.
  //
  //  AMBIGUÏTÉ : une empreinte V1 peut correspondre à PLUSIEURS empreintes V2,
  //  précisément à cause du défaut corrigé. Ces cas sont ENREGISTRÉS comme
  //  ambigus et ne sont JAMAIS résolus arbitrairement : aucune référence
  //  persistée n'est réinterprétée de force.
  //
  //  PORTÉE RÉELLE (établie par lecture du code, pas supposée) :
  //    • `_versionRetenue` n'est PAS persisté — il est reconstruit à chaque
  //      `_load()` par `_enregistrerIndex` (ordre d'autorité total). Aucune
  //      référence persistée n'en dépend.
  //    • le bloc `empreintes` exporté par la sauvegarde n'est JAMAIS relu par
  //      `restaurerDepuisBackup()` (seuls `shards` et `enAttente` le sont).
  //    • le miroir `ArchivesSegmenteess` calcule déjà ses empreintes avec
  //      `empreinteValeur`, c'est-à-dire le canonique V2.
  //  La correspondance est donc une garantie d'AUDIT et de COMPATIBILITÉ, pas
  //  un prérequis de correction : aucun consommateur ne lit une empreinte V1
  //  pour décider quoi que ce soit. C'est dit ici explicitement pour qu'aucune
  //  dépendance cachée ne soit ultérieurement supposée.
  // ═══════════════════════════════════════════════════════════════════════

  /// Clé de persistance de la table de correspondance.
  static const String _kCorrespondanceEmpreintesKey =
      'ia_archive_empreintes_v1_v2';

  /// V1 → ensemble des V2 réellement observées.
  final Map<String, Set<String>> _v1VersV2 = {};

  /// V1 observées correspondant à PLUSIEURS V2 : ambiguïtés conservées.
  final Map<String, Set<String>> _v1Ambigues = {};

  @visibleForTesting
  Map<String, Set<String>> get correspondanceEmpreintesPourTest =>
      Map<String, Set<String>>.unmodifiable(
          _v1VersV2.map((k, v) => MapEntry(k, Set<String>.unmodifiable(v))));

  @visibleForTesting
  Map<String, Set<String>> get ambiguitesEmpreintesPourTest =>
      Map<String, Set<String>>.unmodifiable(
          _v1Ambigues.map((k, v) => MapEntry(k, Set<String>.unmodifiable(v))));

  /// Construit (ou reprend) la table de correspondance V1 → V2.
  ///
  /// Retourne un rapport chiffré. **Ne modifie aucune version**, n'écrit aucun
  /// shard, ne touche ni à l'autorité ni à la version retenue.
  Future<Map<String, int>> migrerEmpreintesV1VersV2() async {
    await _load();

    var examinees = 0;
    var ajoutees = 0;
    for (final liste in _shards.values) {
      for (final p in liste) {
        examinees++;
        final v1 = empreinteV1De(p);
        final v2 = empreinteV2De(p);
        final avant = _v1VersV2[v1]?.length ?? 0;
        _v1VersV2.putIfAbsent(v1, () => <String>{}).add(v2);
        if ((_v1VersV2[v1]?.length ?? 0) > avant) ajoutees++;
      }
    }

    // Les ambiguïtés sont dérivées, jamais inventées : ce sont exactement les
    // V1 qui portent plus d'une V2.
    _v1Ambigues.clear();
    for (final e in _v1VersV2.entries) {
      if (e.value.length > 1) _v1Ambigues[e.key] = e.value;
    }

    await _persisterCorrespondanceEmpreintes();

    final rapport = <String, int>{
      'versionsExaminees': examinees,
      'correspondancesTotal': _v1VersV2.length,
      'correspondancesAjoutees': ajoutees,
      'ambiguites': _v1Ambigues.length,
    };
    if (kDebugMode) {
      debugPrint('[IaArchive] Migration empreintes V1→V2 : '
          '$examinees version(s), ${_v1VersV2.length} correspondance(s), '
          '${_v1Ambigues.length} ambiguïté(s)');
    }
    return rapport;
  }

  Future<void> _persisterCorrespondanceEmpreintes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final charge = <String, dynamic>{
        'version': 2,
        'fenetre': kIaArchiveFormatVersion,
        'v1VersV2': {
          for (final e in _v1VersV2.entries) e.key: e.value.toList()..sort()
        },
        'ambigus': _v1Ambigues.keys.toList()..sort(),
      };
      await prefs.setString(_kCorrespondanceEmpreintesKey, json.encode(charge));
    } catch (e) {
      // La correspondance est une garantie d'audit : son échec d'écriture ne
      // doit jamais empêcher l'application de fonctionner.
      if (kDebugMode) {
        debugPrint('[IaArchive] ⚠️ correspondance empreintes non persistée : $e');
      }
    }
  }

  /// Recharge la correspondance persistée, si elle existe.
  Future<void> _chargerCorrespondanceEmpreintes(SharedPreferences prefs) async {
    final brut = prefs.getString(_kCorrespondanceEmpreintesKey);
    if (brut == null || brut.isEmpty) return;
    try {
      final j = json.decode(brut) as Map<String, dynamic>;
      final v1v2 = j['v1VersV2'];
      if (v1v2 is Map) {
        for (final e in v1v2.entries) {
          final set = _v1VersV2.putIfAbsent(e.key.toString(), () => <String>{});
          final liste = e.value;
          if (liste is List) {
            for (final v in liste) {
              set.add(v.toString());
            }
          }
        }
      }
      final ambigus = j['ambigus'];
      if (ambigus is List) {
        for (final a in ambigus) {
          final v1 = a.toString();
          final set = _v1VersV2[v1];
          if (set != null && set.length > 1) {
            _v1Ambigues[v1] = <String>{...set};
          }
        }
      }
    } catch (_) {
      // Correspondance illisible : on repart d'une table vide. Aucune version
      // n'est perdue, la table est entièrement dérivable.
    }
  }

  static String _fnv1a64(String s) {
    // FNV-1a sur deux accumulateurs 32 bits.
    // ⚠️ Un accumulateur 64 bits serait SIGNÉ en Dart : 0xFFFFFFFFFFFFFFFF
    // vaut -1, et toRadixString(16) produirait une chaîne négative.
    // Deux mots de 32 bits garantissent exactement 16 caractères hexadécimaux,
    // déterministes d'une exécution à l'autre (pas de hashCode).
    const int p = 0x01000193;
    var a = 0x811c9dc5; // offset basis FNV-1a 32
    var b = 0x7fed3c85; // second accumulateur, base distincte
    for (final unit in s.codeUnits) {
      a = ((a ^ (unit & 0xff)) * p) & 0xffffffff;
      b = ((b ^ (unit >> 8)) * p) & 0xffffffff;
      b = ((b ^ (unit & 0xff)) * p) & 0xffffffff;
    }
    return a.toRadixString(16).padLeft(8, '0') +
        b.toRadixString(16).padLeft(8, '0');
  }

  /// Rang d'autorité : 2 = résolu complet, 1 = résolu incomplet, 0 = non résolu.
  static int rangDe(IaPronostic p) {
    if (!p.resultatsReels) return 0;
    final a = p.arriveeReelle;
    if (a == null || a.isEmpty) return 1;
    return 2;
  }

  /// Score de complétude de la fiche (nombre de champs renseignés).
  static int completudeDe(IaPronostic p) {
    var n = 0;
    if (p.scoresCriteres.isNotEmpty) n++;
    if (p.cotesPmuParNumero.isNotEmpty) n++;
    if (p.confiancePredite != null) n++;
    if (p.varianceScores != null) n++;
    if (p.scorePerformance != null) n++;
    if (p.rangFavoriIaDansArrivee != null) n++;
    if (p.nbTop3DansArriveeReelle != null) n++;
    if (p.nbTop5DansArriveeReelle != null) n++;
    if (p.favoriIaNom != null && p.favoriIaNom!.isNotEmpty) n++;
    return n;
  }

  /// Ordre d'autorité TOTAL et déterministe, indépendant de l'ordre d'arrivée.
  /// > 0 si `a` est plus autoritaire que `b`.
  ///
  /// ORDRE EXACT (contrainte utilisateur : « ne jamais remplacer une fiche
  /// complète par une version incomplète ») :
  ///   1. RANG          — résolu complet > résolu incomplet > non résolu.
  ///   2. COMPLÉTUDE    — AVANT la date : une fiche plus riche ne peut jamais
  ///                      être écrasée par une fiche plus pauvre, même plus
  ///                      récente. C'est le point dur de l'exigence.
  ///   3. DATE RÉSULTAT — à complétude égale, la plus récente l'emporte.
  ///   4. EMPREINTE     — départage reproductible des ex æquo.
  static int comparerAutorite(IaPronostic a, IaPronostic b) {
    final ra = rangDe(a), rb = rangDe(b);
    if (ra != rb) return ra.compareTo(rb);

    final ca = completudeDe(a), cb = completudeDe(b);
    if (ca != cb) return ca.compareTo(cb);

    final da = a.dateResultat, db = b.dateResultat;
    if (da != null && db != null && da != db) return da.compareTo(db);
    if (da != null && db == null) return 1;
    if (da == null && db != null) return -1;

    return empreinteDe(a).compareTo(empreinteDe(b));
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  INDEX EN MÉMOIRE
  // ═══════════════════════════════════════════════════════════════════════

  /// Indexe une version et met à jour la version retenue. Aucun champ n'est
  /// recombiné : on choisit une version ENTIÈRE.
  void _enregistrerIndex(IaPronostic p) {
    final emp = empreinteDe(p);
    _empreintesParCourse.putIfAbsent(p.courseKey, () => <String>{}).add(emp);

    final actuelleEmp = _versionRetenue[p.courseKey];
    if (actuelleEmp == null) {
      _versionRetenue[p.courseKey] = emp;
      _retenues[p.courseKey] = p;
      return;
    }
    if (actuelleEmp == emp) return; // déjà vue

    final actuelle = _retenues[p.courseKey]!;
    if (comparerAutorite(p, actuelle) > 0) {
      _versionRetenue[p.courseKey] = emp;
      _retenues[p.courseKey] = p;
    }
  }

  /// Intègre un pronostic en mémoire. Retourne `true` s'il s'agit d'une
  /// nouvelle version, `false` si l'empreinte existait déjà (no-op).
  bool _integrerEnMemoire(IaPronostic p, String motif) {
    final emp = empreinteDe(p);
    final connues = _empreintesParCourse[p.courseKey] ?? <String>{};
    if (connues.contains(emp)) return false; // aucune duplication

    final mois = _moisDe(p);
    _shards.putIfAbsent(mois, () => []).add(p);
    _indexerParDateEffective(p);
    _enregistrerIndex(p);
    _journalVersions.putIfAbsent(p.courseKey, () => []).add({
      'empreinte': emp,
      'motif': motif,
      'retenue': _versionRetenue[p.courseKey] == emp ? '1' : '0',
    });
    return true;
  }

  static String _moisDe(IaPronostic p) => '${p.datePronostic.year}-'
      '${p.datePronostic.month.toString().padLeft(2, '0')}';

  /// ★ A4-3 — Alimente l'index par date effective.
  ///
  /// Ajout STRICTEMENT parallèle à celui de `_shards` : les deux index
  /// reçoivent le même objet au même instant. Aucune copie, aucune
  /// modification de `p`, aucune écriture sur le stockage.
  void _indexerParDateEffective(IaPronostic p) {
    _parDateEffective.putIfAbsent(_moisDe(p), () => <IaPronostic>[]).add(p);
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  ÉVICTION — point d'entrée unique, en deux temps
  //
  //  TEMPS 1 (synchrone, aucun await) : enregistrerEviction()
  //     → la référence entre dans la file. Il n'existe AUCUN instant où
  //       l'objet serait retiré de _pronostics sans être déjà dans la file.
  //  TEMPS 2 (asynchrone) : persisterEnAttente()
  //     → écriture durable, gestion explicite du false ET des exceptions.
  // ═══════════════════════════════════════════════════════════════════════

  /// TEMPS 1 — synchrone. À appeler AVANT `_pronostics.removeLast()`.
  /// Ne lève jamais, ne supprime jamais, n'écrit rien sur le disque.
  void enregistrerEviction(
    IaPronostic p, {
    String motif = ArchiveReason.eviction,
  }) {
    // 1. La référence est sécurisée ICI, avant toute éviction.
    _evictionsNonArchivees.add(p);

    // 2. Intégration en mémoire : seulement si le stockage est déjà cartographié,
    //    sinon différée après _load() (on ne peut pas attendre ici).
    if (_charge) {
      _integrerEnMemoire(p, motif);
    } else {
      _aIntegrer.add(_EntreeFile(p, motif));
    }
  }

  /// TEMPS 2 — écriture durable de tout ce qui est en file.
  /// Retourne `true` si la file est intégralement vidée.
  /// Ne lève jamais : toute exception devient un échec signalé, sans perte.
  Future<bool> persisterEnAttente() async {
    if (_evictionsNonArchivees.isEmpty && _moisARepersister.isEmpty) {
      return true;
    }
    try {
      await _load();

      // Intégration différée des objets arrivés avant le chargement.
      if (_aIntegrer.isNotEmpty) {
        for (final e in _aIntegrer) {
          _integrerEnMemoire(e.pronostic, e.motif);
        }
        _aIntegrer.clear();
      }

      // Regrouper les objets en file par shard.
      final Map<String, List<IaPronostic>> parMois = {};
      for (final p in _evictionsNonArchivees) {
        parMois.putIfAbsent(_moisDe(p), () => []).add(p);
      }
      // ★ E3 : les mois dont une restauration n'a pas confirmé l'écriture sont
      // rejoués ici — la reprise est donc automatique au prochain _save().
      for (final mois in _moisARepersister) {
        parMois.putIfAbsent(mois, () => const <IaPronostic>[]);
      }

      var toutEcrit = true;
      for (final entry in parMois.entries) {
        final ok = await _persisterShard(entry.key);
        if (ok) {
          // Archivage CONFIRMÉ → retrait de la file (la copie durable reste).
          for (final p in entry.value) {
            _evictionsNonArchivees.remove(p);
          }
          _moisARepersister.remove(entry.key);
        } else {
          toutEcrit = false;
        }
      }

      if (toutEcrit &&
          _evictionsNonArchivees.isEmpty &&
          _moisARepersister.isEmpty) {
        dernierArchivageConfirme = true;
        cyclesEchecConsecutifs = 0;
      } else {
        _signalerEchec('persisterEnAttente : '
            '${_evictionsNonArchivees.length} éviction(s) non confirmée(s), '
            '${_moisARepersister.length} mois non confirmé(s)');
      }
      return _evictionsNonArchivees.isEmpty && _moisARepersister.isEmpty;
    } catch (e) {
      _signalerEchec('exception persisterEnAttente : $e');
      return false;
    }
  }

  /// Raccourci asynchrone : sécurise puis persiste. Retourne `true` si la
  /// version est durablement archivée.
  Future<bool> securiser(
    IaPronostic p, {
    String motif = ArchiveReason.eviction,
  }) async {
    enregistrerEviction(p, motif: motif);
    final ok = await persisterEnAttente();
    return ok && !_evictionsNonArchivees.contains(p);
  }

  void _signalerEchec(String motif) {
    dernierArchivageConfirme = false;
    cyclesEchecConsecutifs++;
    derniereErreurArchive = '${DateTime.now().toIso8601String()} — $motif';
    if (_evictionsNonArchivees.length > 100) alerteMemoireArchive = true;
    if (kDebugMode) debugPrint('[IaArchive] ❌ $motif');
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  ÉCRITURE SÉRIALISÉE (jamais d'entrelacement)
  // ═══════════════════════════════════════════════════════════════════════

  Future<bool> _persisterShard(String mois) {
    final completer = Completer<bool>();
    _writeChain = _writeChain.then((_) async {
      try {
        completer.complete(await _ecrireShardMois(mois));
      } catch (_) {
        completer.complete(false);
      }
    });
    return completer.future;
  }

  Future<bool> _ecrireShardMois(String mois) async {
    final versions = _shards[mois];
    if (versions == null || versions.isEmpty) return true;
    final prefs = await SharedPreferences.getInstance();
    final b64 = _encoderVersions(versions);
    // Le bool représente une durabilité ANNONCÉE (pas une garantie physique).
    final ok = await prefs.setString('$_kShardPrefix$mois', b64);
    if (ok) {
      _clesShardsConnues.add('$_kShardPrefix$mois');
      await _ecrireManifeste();
      // Miroir consultable — voir la documentation de _mirroirSegmentes.
      await _mirroirSegmentes(mois, versions);
    }
    return ok;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  MIROIR CONSULTABLE DES ARCHIVES — §4 : UN SEUL MAGASIN AUTORITAIRE
  //
  //  ⚠️ LE PROBLÈME QUE CE BLOC RÉSOUT
  //
  //  Les versions archivées vivaient dans des shards SharedPreferences, une
  //  chaîne base64 PAR MOIS, décodée INTÉGRALEMENT au démarrage par
  //  `_chargerDepuisStockage`. Deux conséquences, toutes deux mesurables :
  //     • la consultation d'UNE course exigeait de décoder tous les mois ;
  //     • la mémoire de travail portait tout l'historique archivé, alors que
  //       ces versions en sont précisément sorties pour ne plus y peser.
  //
  //  Le service `ArchivesSegmenteess` apporte exactement ce qui manquait :
  //  fichiers compressés par segment, index de ciblage, lecture en FLUX. Il ne
  //  remplace pas les shards — il les REND CONSULTABLES sans les charger.
  //
  //  ⚠️ QUI FAIT AUTORITÉ, ET POURQUOI CE N'EST PAS AMBIGU
  //
  //  SharedPreferences reste la SOURCE DE VÉRITÉ de l'archive :
  //    • la sauvegarde (`exporterPourBackup`) part des shards ;
  //    • la restauration (`restaurerDepuisBackup`) écrit dans les shards ;
  //    • la réconciliation (`VerificationArchive`) compte les shards.
  //  Les segments sont un MIROIR dérivé, en AJOUT SEUL :
  //    • ils ne sont JAMAIS relus par `_chargerDepuisStockage` ;
  //    • aucune décision d'apprentissage ne les consulte ;
  //    • une divergence (miroir incomplet, dossier supprimé) ne peut donc pas
  //      changer l'état logique — au pire elle appauvrit la consultation.
  //
  //  C'est ce qui évite le « second magasin produisant un état divergent » :
  //  un magasin qui n'est jamais lu pour décider ne peut pas diverger.
  //
  //  ⚠️ POURQUOI LE MIROIR NE FAIT PAS ÉCHOUER L'ARCHIVAGE
  //
  //  Écrire un miroir est un CONFORT de consultation. Si le disque refuse, la
  //  version est malgré tout durablement archivée dans son shard : l'échec est
  //  journalisé, jamais propagé, et ne retire rien à ce qui vient d'être écrit.
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _mirroirSegmentes(String mois, List<IaPronostic> versions) async {
    try {
      final entrees = <EntreeArchive>[];
      for (final p in versions) {
        final encode = _encoderUnPronosticPourMiroir(p);
        if (encode == null) continue;
        entrees.add(EntreeArchive(
          // Identité de CONTENU : deux versions de même empreinte sont la même
          // version. Le miroir étant en ajout seul, rejouer n'ajoute rien.
          empreinte: encode.$1,
          cleCourse: p.courseKey,
          dateCourse: _dateIsoDe(p.datePronostic),
          contenu: encode.$2,
          resultatOfficiel: p.resultatsReels && p.arriveeReelle != null
              ? p.arriveeReelle!.join('-')
              : null,
        ));
      }
      if (entrees.isEmpty) return;
      final res = await ArchivesSegmenteess.instance.archiver(entrees);
      if (!res.succes) {
        // Le miroir est en retard, PAS l'archive. On le dit, on ne le cache pas.
        if (kDebugMode) {
          debugPrint('[IaArchive] ⚠️ miroir segmenté non écrit pour $mois '
              '(${res.erreur}) — les shards restent la référence intacte');
        }
      } else if (kDebugMode && res.ecrites > 0) {
        debugPrint('[IaArchive] miroir segmenté : ${res.ecrites} entrée(s) '
            'ajoutée(s) pour $mois');
      }
    } catch (e) {
      // Aucune propagation : l'archivage durable a réussi, le miroir est un
      // accélérateur de consultation.
      if (kDebugMode) {
        debugPrint('[IaArchive] ⚠️ miroir segmenté indisponible ($e)');
      }
    }
  }

  /// Sérialise un pronostic archivé pour le miroir, avec son empreinte de
  /// CONTENU. Rend `null` si l'objet n'est pas sérialisable — auquel cas il
  /// reste archivé dans son shard, simplement absent du miroir.
  (String, String)? _encoderUnPronosticPourMiroir(IaPronostic p) {
    try {
      final j = p.toJson();
      final contenu = json.encode(j);
      final empreinte = empreinteValeur(<String, Object?>{
        'courseKey': p.courseKey,
        'date': _dateIsoDe(p.datePronostic),
        'scoresIA': p.scoresIA,
        'contenu': contenu,
      });
      return (empreinte, contenu);
    } catch (_) {
      return null;
    }
  }

  static String _dateIsoDe(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ═══════════════════════════════════════════════════════════════════════
  //  CONSULTATION CIBLÉE — SANS CHARGER L'INTÉGRALITÉ DE L'ARCHIVE
  //
  //  ⚠️ LE DÉFAUT QUE CE BLOC CORRIGE, ET SA MESURE
  //
  //  `_chargerDepuisStockage` décode TOUS les shards au démarrage : chaque mois
  //  est une chaîne base64+gzip qui est intégralement décompressée et dont
  //  chaque pronostic est désérialisé. La mémoire de travail porte donc tout
  //  l'historique archivé, alors que ces versions en sont précisément sorties
  //  pour ne plus y peser.
  //
  //  Conséquence mesurée sur une base de démonstration : consulter UNE course
  //  exigeait de décoder l'ensemble des mois. Le coût de la consultation était
  //  proportionnel à la taille TOTALE de l'archive, et non à ce qui était
  //  demandé.
  //
  //  ⚠️ CE QUI EST AJOUTÉ, ET RIEN DE PLUS
  //
  //  Une lecture CIBLÉE qui passe par le miroir segmenté (`ArchivesSegmenteess`),
  //  lequel indexe par `cleCourse` et par période, et lit en FLUX. Elle ne
  //  charge que les entrées demandées.
  //
  //  ⚠️ CE QUE CETTE LECTURE N'EST PAS
  //
  //  • elle n'est PAS l'autorité : les shards le restent. Une divergence du
  //    miroir (dossier effacé, écriture interrompue) appauvrit la consultation
  //    mais ne peut pas changer l'état logique ;
  //  • elle n'est JAMAIS lue par l'apprentissage — aucun `_poids`, aucun seuil,
  //    aucun gradient n'y accède (§3) ;
  //  • elle ne réinjecte RIEN dans la mémoire de travail (§3, §17) : elle rend
  //    des objets `IaPronostic` à l'appelant, sans les intégrer à `_pronostics`.
  // ═══════════════════════════════════════════════════════════════════════

  /// Versions archivées d'UNE course, lues SANS charger toute l'archive.
  ///
  /// ⚠️ ARBITRAGE APPLIQUÉ : le repli vers `_retenues[courseKey]` n'est exercé
  ///    QUE si la consultation ciblée n'a pas abouti, et il est alors
  ///    OBSERVABLE. Il ne peut donc jamais se faire passer pour l'archive.
  ///
  /// Le repli est refusé — et la liste reste vide — dans les trois cas
  /// suivants, parce qu'y répondre par autre chose produirait un résultat
  /// faux :
  ///
  /// • **[EtatLectureArchive.absent]** — aucune archive n'a jamais été écrite pour
  ///   cette course. La version retenue en mémoire est la version courante et
  ///   sera archivée plus tard ; la présenter comme archivée serait un
  ///   mensonge. Elle reste consultable par les accesseurs normaux.
  ///
  /// • **[EtatLectureArchive.corrompu]** — une archive existe mais son contenu est
  ///   inexploitable. Rendre une version en mémoire donnerait à l'appelant
  ///   l'illusion d'une reconstitution à l'identique alors que des versions
  ///   antérieures ont pu être perdues. On signale l'état, on ne substitue pas.
  ///
  /// • **contenu illisible** — le miroir a rendu des entrées mais aucune ne se
  ///   décode. Rendre la version mémoire reviendrait à masquer une
  ///   désérialisation défaillante derrière une réponse d'apparence complète.
  ///
  /// Une version rendue par repli est COMPLÈTE (c'est l'objet d'origine, pas
  /// une projection partielle) et n'est JAMAIS réinjectée : elle est rendue à
  /// l'appelant, jamais ajoutée à `_pronostics` ni `_retenues` (§3, §17).
  Future<List<IaPronostic>> versionsArchiveesPourCourse(
      String courseKey) async {
    if (courseKey.isEmpty) {
      _derniereConsultationArchive = null;
      return const <IaPronostic>[];
    }

    final consultation =
        await ArchivesSegmenteess.instance.consulterParCourse(courseKey);
    _derniereConsultationArchive = consultation;
    _nbConsultationsArchive++;

    if (consultation.aboutie) {
      final resultat = _decoderEntrees(consultation.entrees);
      // 0 entrée lisible ⇒ archive réellement vide : c'est un FAIT, et il
      // ne justifie aucun repli (la version mémoire n'est pas archivée).
      // > 0 entrées mais 0 décodable ⇒ désérialisation défaillante : on le
      // dit, on ne le masque pas.
      return resultat;
    }

    // ⚠️ `absent` n'est PAS une panne, mais ce n'est pas davantage le droit de
    //    présenter la version COURANTE comme une version ARCHIVÉE. Une archive
    //    absente signifie « rien n'a encore été archivé pour cette course » ;
    //    rendre la version retenue reviendrait à dater l'archive d'aujourd'hui.
    if (!repliAutorisePour(consultation.etat)) {
      // `absent` et `corrompu` : aucun repli. Sur `corrompu`, substituer
      // cacherait une perte possible de versions antérieures illisibles.
      return const <IaPronostic>[];
    }

    // Seul cas de repli admis : archive INACCESSIBLE (droits, E/S) — les
    // connaissances peuvent exister, on ne peut pas les lire. La version
    // retenue en mémoire est alors le seul accès, et le repli reste OBSERVABLE
    // via `etatDerniereConsultationArchive` et `nbConsultationsRepliees`.
    final retenue = _retenues[courseKey];
    _nbConsultationsRepliees++;
    return retenue == null ? const <IaPronostic>[] : <IaPronostic>[retenue];
  }

  /// État de la dernière consultation ciblée effectuée (diagnostic).
  ///
  /// Permet à l'interface de rendre le repli VISIBLE au lieu de laisser croire
  /// que tout a été lu dans l'archive. `null` = aucune consultation effectuée.
  EtatLectureArchive? get etatDerniereConsultationArchive =>
      _derniereConsultationArchive?.etat;

  /// Compteurs de repli, pour prouver par mesure qu'il n'est pas silencieux.
  int get nbConsultationsArchive => _nbConsultationsArchive;
  int get nbConsultationsRepliees => _nbConsultationsRepliees;

  /// Force l'état observé de la dernière consultation. RÉSERVÉ AUX TESTS.
  @visibleForTesting
  void simulerEtatConsultationPourTest(EtatLectureArchive etat) {
    _derniereConsultationArchive =
        ConsultationArchive(etat: etat, entrees: const <EntreeArchive>[]);
  }

  /// DÉCIDE si un repli vers la version mémoire est autorisé pour un état donné.
  ///
  /// C'est la RÈGLE DE L'ARBITRAGE, écrite une seule fois et mesurable
  /// directement : un repli n'est admis QUE sur `inaccessible`.
  ///
  /// Justification état par état — aucun autre cas n'est tolérable :
  /// • `lisible`      → l'archive répond ; un repli cacherait sa réponse.
  /// • `absent`       → rien n'est archivé ; le repli daterait l'archive
  ///                    d'aujourd'hui et présenterait le courant comme ancien.
  /// • `corrompu`     → du contenu a existé mais est perdu ; le repli ferait
  ///                    croire à une reconstitution à l'identique.
  /// • `inaccessible` → les connaissances existent, on ne peut pas les lire ;
  ///                    la mémoire est le seul accès, et le repli est exposé
  ///                    par `etatDerniereConsultationArchive` et le compteur.
  @visibleForTesting
  static bool repliAutorisePour(EtatLectureArchive etat) =>
      etat == EtatLectureArchive.inaccessible;

  /// Décode une liste d'entrées de miroir, en ignorant les illisibles.
  List<IaPronostic> _decoderEntrees(List<EntreeArchive> entrees) {
    final resultat = <IaPronostic>[];
    for (final e in entrees) {
      final p = _decoderPronosticArchive(e.contenu);
      if (p != null) resultat.add(p);
    }
    return resultat;
  }

  /// Entrées archivées dont la date appartient à `[du, au]`, en lecture ciblée.
  ///
  /// [du] et [au] sont au format ISO `AAAA-MM-JJ`, bornes INCLUSES.
  ///
  /// ⚠️ Utilisé par les bilans et les agrégats historiques, JAMAIS par
  ///    l'apprentissage. Aucune réinjection : les objets rendus ne sont pas
  ///    ajoutés à `_pronostics`.
  Future<List<IaPronostic>> versionsArchiveesPeriode(
      String du, String au) async {
    final consultation =
        await ArchivesSegmenteess.instance.consulterParPeriode(du, au);
    _derniereConsultationArchive = consultation;
    _nbConsultationsArchive++;
    return _decoderEntrees(consultation.entrees);
  }

  /// Entrées archivées disposant d'un RÉSULTAT OFFICIEL, en lecture ciblée.
  ///
  /// Sert aux agrégats historiques : un pronostic sans résultat n'alimente
  /// aucun bilan, et le charger serait un coût sans contrepartie.
  Future<List<IaPronostic>> versionsArchiveesAvecResultat() async {
    final consultation =
        await ArchivesSegmenteess.instance.consulterAvecResultatOfficiel();
    _derniereConsultationArchive = consultation;
    _nbConsultationsArchive++;
    return _decoderEntrees(consultation.entrees);
  }

  /// Bilan MESURÉ de l'archive : segments, entrées, octets, état de l'index.
  ///
  /// Rend `null` si le miroir n'est pas exploitable — auquel cas il n'existe
  /// aucune mesure à annoncer, et en inventer une serait pire que l'absence.
  Future<BilanArchives?> bilanMiroir() async {
    try {
      return await ArchivesSegmenteess.instance.bilan();
    } catch (e) {
      if (kDebugMode) debugPrint('[IaArchive] bilan indisponible : $e');
      return null;
    }
  }

  /// Décode le contenu VERBATIM d'une entrée de miroir.
  ///
  /// Rend `null` — et rien d'autre — si le contenu n'est pas un JSON objet
  /// exploitable. Aucune reconstruction approximative : mieux vaut une entrée
  /// absente qu'une entrée inventée (§9).
  IaPronostic? _decoderPronosticArchive(String contenu) {
    try {
      final j = json.decode(contenu);
      if (j is! Map<String, dynamic>) return null;
      return IaPronostic.fromJson(j);
    } catch (_) {
      return null;
    }
  }

  Future<void> _ecrireManifeste() async {
    final prefs = await SharedPreferences.getInstance();
    // ★ E3 : le manifeste décrit ce qui est RÉELLEMENT écrit (écritures
    // confirmées + shards trouvés sur le disque), jamais l'intention. Ainsi
    // une restauration partiellement échouée ne peut pas produire un manifeste
    // annonçant des shards qui n'existent pas.
    final mois = <String>[];
    for (final cle in _clesShardsConnues) {
      if (cle.startsWith(_kShardPrefix)) {
        final m = cle.substring(_kShardPrefix.length);
        if (m != kIaArchiveManifestKey) mois.add(m);
      }
    }
    mois.sort();
    await prefs.setString(
      kIaArchiveManifestKey,
      json.encode({'version': kIaArchiveFormatVersion, 'mois': mois}),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  ★ E3 — SAUVEGARDE / RESTAURATION DE L'ARCHIVE
  //
  //  PRINCIPES (exigences E3)
  //  ────────────────────────
  //   1. EXPORT INTÉGRAL : manifeste + TOUS les shards (octets exacts,
  //      gzip+base64 inchangés) + fiches détaillées complètes (le payload de
  //      chaque pronostic est son `toJson()` entier) + table d'empreintes pour
  //      contrôle d'intégrité. Les shards indécodables sont exportés TELS QUELS
  //      (aucune donnée inventée, aucun octet perdu).
  //   2. RESTAURATION SANS PERTE : union. Aucune suppression locale, aucune
  //      écriture destructive, aucun `clear()`.
  //   3. SANS DOUBLON : dédoublonnage par EMPREINTE de contenu.
  //   4. SANS RÉTROGRADATION : `comparerAutorite()` décide seule de la version
  //      retenue (rang → complétude → date → empreinte). Une fiche locale plus
  //      complète n'est jamais remplacée par une fiche importée plus pauvre.
  //   5. FUSION PROTECTRICE PAR DÉFAUT : il n'existe AUCUN mode destructif.
  //      L'absence de ce mode est une décision, pas un oubli.
  //   6. INTERRUPTION : un mois dont l'écriture n'est pas confirmée entre dans
  //      `_moisARepersister` et reste dans l'archive en mémoire ; il est rejoué
  //      au prochain `persisterEnAttente()`. Rien n'est perdu, rien n'est
  //      annoncé à tort.
  //   7. AUCUNE RÉINJECTION : ces méthodes ne touchent ni `_pronostics`, ni
  //      `_poids`, ni `_seuils`, ni le TOP3, ni l'apprentissage. L'archive
  //      restaurée reste en lecture seule pour E2.
  // ═══════════════════════════════════════════════════════════════════════

  /// Exporte l'intégralité de l'archive sous une forme JSON-compatible.
  /// Lecture seule sur le stockage : cette méthode n'écrit que ce qui était
  /// déjà en attente (via `persisterEnAttente()`), jamais de réécriture de
  /// shard déjà durable.
  Future<Map<String, dynamic>> exporterPourBackup() async {
    await _load();
    // Les évictions en attente deviennent durables si possible ; sinon elles
    // sont embarquées plus bas → l'export ne perd jamais rien.
    await persisterEnAttente();

    final prefs = await SharedPreferences.getInstance();

    final shards = <String, String>{};
    final nbVersionsParMois = <String, int>{};
    final illisibles = <String>[];
    final empreintesParCourse = <String, List<String>>{};
    var totalVersions = 0;
    var totalPredictions = 0;

    for (final cle in (_clesShardsConnues.toList()..sort())) {
      final brut = prefs.getString(cle);
      if (brut == null || brut.isEmpty) continue;
      final mois = cle.substring(_kShardPrefix.length);
      shards[mois] = brut; // octets exacts, aucune re-sérialisation
      final versions = _decoderVersions(brut);
      if (versions == null) {
        illisibles.add(cle);
        continue;
      }
      nbVersionsParMois[mois] = versions.length;
      totalVersions += versions.length;
      for (final p in versions) {
        empreintesParCourse
            .putIfAbsent(p.courseKey, () => <String>[])
            .add(empreinteDe(p));
      }
    }
    totalPredictions = empreintesParCourse.length;
    for (final e in empreintesParCourse.entries) {
      final vus = <String>{};
      e.value.removeWhere((emp) => !vus.add(emp));
    }

    // Évictions dont l'écriture n'a PAS été confirmée : elles doivent figurer
    // dans la sauvegarde, sinon elles seraient perdues au changement d'appareil.
    final enAttente = <Map<String, dynamic>>[
      for (final p in _evictionsNonArchivees) p.toJson(),
    ];

    final manifeste = <String, dynamic>{
      'version': kIaArchiveFormatVersion,
      'mois': shards.keys.toList()..sort(),
    };

    if (kDebugMode) {
      debugPrint('[IaArchive] Export : ${shards.length} shard(s), '
          '$totalVersions version(s), $totalPredictions prédiction(s), '
          '${enAttente.length} en attente, ${illisibles.length} illisible(s)');
    }

    return {
      'format': kIaArchiveFormatVersion,
      'version': kIaArchiveFormatVersion,
      'manifeste': manifeste,
      'shards': shards,
      'nbShards': shards.length,
      'nbVersions': totalVersions,
      'nbVersionsParMois': nbVersionsParMois,
      'nbPredictions': totalPredictions,
      'empreintes': empreintesParCourse,
      'shardsIllisibles': illisibles,
      'enAttente': enAttente,
      'nbEnAttente': enAttente.length,
    };
  }

  /// Restaure l'archive d'une sauvegarde par FUSION PROTECTRICE.
  ///
  /// Ne supprime jamais un shard ni une version locale. Si `data` est absent,
  /// null ou inexploitable, l'archive locale reste intacte et la méthode le
  /// signale (`succes: false`) sans rien modifier.
  Future<ResultatRestaurationArchive> restaurerDepuisBackup(
    Map<String, dynamic>? data,
  ) async {
    if (data == null || data.isEmpty) {
      return ResultatRestaurationArchive.echec('archiveIA absente');
    }

    try {
      await _load();

      final shardsBruts = <String, String>{};
      final dataShards = data['shards'];
      if (dataShards is Map) {
        for (final e in dataShards.entries) {
          final v = e.value;
          if (v is String && v.isNotEmpty) {
            shardsBruts[e.key.toString()] = v;
          }
        }
      }

      // Une sauvegarde peut aussi ne transporter que les versions en attente.
      final aRestaurer = <IaPronostic>[];
      final dataEnAttente = data['enAttente'];
      if (dataEnAttente is List) {
        for (final item in dataEnAttente) {
          try {
            aRestaurer.add(IaPronostic.fromJson(item as Map<String, dynamic>));
          } catch (_) {}
        }
      }

      var shardsLus = 0;
      var shardsIllisibles = 0;
      var versionsAjoutees = 0;
      var versionsDejaPresentes = 0;
      var predictionsAmeliorees = 0;
      var predictionsConservees = 0;
      var moisNonEcrits = 0;
      final moisModifies = <String>{};

      // ── 1. Décodage des shards du backup (AUCUNE écriture, AUCUN effacement)
      final candidats = <IaPronostic>[];
      for (final entry in shardsBruts.entries) {
        final versions = _decoderVersions(entry.value);
        if (versions == null) {
          // Shard illisible : ignoré, JAMAIS substitué au shard local.
          shardsIllisibles++;
          continue;
        }
        shardsLus++;
        candidats.addAll(versions);
      }
      candidats.addAll(aRestaurer);

      // ── 2. Fusion en mémoire : union par empreinte, sans rétrogradation ──
      for (final p in candidats) {
        final emp = empreinteDe(p);
        if ((_empreintesParCourse[p.courseKey] ?? const <String>{})
            .contains(emp)) {
          versionsDejaPresentes++; // contenu identique → aucun doublon
          continue;
        }
        // Version retenue AVANT l'import : sert à mesurer l'effet d'autorité.
        final retenueAvant = _versionRetenue[p.courseKey];
        if (!_integrerEnMemoire(p, ArchiveReason.restauration)) {
          versionsDejaPresentes++;
          continue;
        }
        versionsAjoutees++;
        moisModifies.add(_moisDe(p));

        final retenueApres = _versionRetenue[p.courseKey];
        if (retenueApres == emp) {
          // L'import devient la version retenue de cette prédiction.
          if (retenueAvant != emp) predictionsAmeliorees++;
        } else {
          // La version LOCALE reste retenue : elle était plus autoritaire.
          // La version importée est intégralement conservée au journal.
          predictionsConservees++;
        }
      }

      // ── 2. Écriture, mois par mois, des seuls shards réellement modifiés ─
      for (final mois in moisModifies) {
        final ok = await _persisterShard(mois);
        if (!ok) {
          _moisARepersister.add(mois);
          moisNonEcrits++;
        }
      }
      if (moisNonEcrits == 0 && moisModifies.isNotEmpty) {
        await _ecrireManifeste();
      }

      if (moisNonEcrits > 0) {
        _signalerEchec('restaurerDepuisBackup : $moisNonEcrits mois non '
            'confirmé(s) — reprise au prochain _save()');
      }

      final resultat = ResultatRestaurationArchive(
        succes: moisNonEcrits == 0,
        shardsLus: shardsLus,
        shardsIllisibles: shardsIllisibles,
        versionsAjoutees: versionsAjoutees,
        versionsDejaPresentes: versionsDejaPresentes,
        predictionsAmeliorees: predictionsAmeliorees,
        predictionsConservees: predictionsConservees,
        moisNonEcrits: moisNonEcrits,
      );
      if (kDebugMode) debugPrint('[IaArchive] Restauration -> $resultat');
      return resultat;
    } catch (e) {
      _signalerEchec('exception restaurerDepuisBackup : $e');
      return ResultatRestaurationArchive.echec(e.toString());
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  RELECTURE — destinée aux tests et à E2. Jamais utilisée par l'apprentissage.
  // ═══════════════════════════════════════════════════════════════════════

  /// Version retenue pour une course (une seule par courseKey).
  IaPronostic? versionRetenue(String courseKey) => _retenues[courseKey];

  /// ★ CORRECTION BLOC 1 (BL1-A10) — TOUTES LES VERSIONS RETENUES, en lecture.
  ///
  /// POURQUOI CE GETTER EXISTE
  /// ─────────────────────────
  /// `IaMemoryService._pronostics` est plafonné à 600 entrées et ses entrées
  /// sans résultat sont purgées à 90 jours. Tout pronostic évincé était
  /// jusqu'ici ARCHIVÉ (correctement, ce service ne perd rien) mais **jamais
  /// relu** : `pronosticsAvecResultat` ne parcourt que la fenêtre vive. Les
  /// statistiques, le ROI/Value, le profil et le calendrier ne voyaient donc
  /// qu'une tranche glissante, alors que les données étaient sur le disque.
  ///
  /// CE QUE CE GETTER N'EST PAS
  /// ──────────────────────────
  /// • Il n'est lu par AUCUNE fonction d'apprentissage. Le gradient, les
  ///   seuils et la calibration continuent de lire la fenêtre vive via
  ///   `IaMemoryService.pronosticsAvecResultat`, INCHANGÉE. Élargir ce getter
  ///   partagé aurait silencieusement modifié les fenêtres d'apprentissage,
  ///   ce que le mandat interdit explicitement.
  /// • Il ne modifie rien : `List.unmodifiable` sur les valeurs de l'index
  ///   d'autorité. Aucun shard, aucune date, aucune autorité n'est touché.
  /// • Il ne fabrique rien : une seule version par course, celle que
  ///   l'autorité existante (`_retenues`) a retenue. Aucune recombinaison.
  List<IaPronostic> get versionsRetenues =>
      List<IaPronostic>.unmodifiable(_retenues.values);

  /// Toutes les versions archivées d'une course (y compris écartées).
  List<IaPronostic> toutesLesVersions(String courseKey) => List.unmodifiable(
      _shards.values.expand((l) => l).where((p) => p.courseKey == courseKey));

  /// Versions archivées d'un mois ('YYYY-MM').
  List<IaPronostic> versionsDuMois(String mois) =>
      List.unmodifiable(_shards[mois] ?? const <IaPronostic>[]);

  /// ★ A4-3 — Versions archivées dont la **DATE EFFECTIVE** appartient au mois.
  ///
  /// Différence avec [versionsDuMois] : celle-ci lit le mois du SHARD PHYSIQUE
  /// (mois d'écriture), alors que la présente lit `datePronostic`. Une version
  /// rangée dans un autre shard que celui de sa date est donc retrouvée ici,
  /// et uniquement ici.
  ///
  /// Garanties :
  ///   • **UNE SEULE ENTRÉE PAR COURSE** : on retourne la version retenue par
  ///     l'index d'autorité existant (`_retenues`), jamais une version écartée.
  ///     Si la course n'a pas de retenue (impossible en pratique), la version
  ///     est ignorée plutôt que devinée — aucun fallback heuristique.
  ///   • **AUCUN DOUBLON** : dédoublonnage par `courseKey`.
  ///   • **LECTURE SEULE** : aucune date, aucun shard, aucune autorité modifiés.
  ///   • **O(1) amorti** : simple lecture de l'index, sans parcours des shards.
  ///   • Équivalente à [versionsDuMois] quand le rangement est correct.
  List<IaPronostic> versionsDuMoisParDate(String mois) {
    final candidates = _parDateEffective[mois];
    if (candidates == null || candidates.isEmpty) {
      return List.unmodifiable(const <IaPronostic>[]);
    }
    final vues = <String>{};
    final resultat = <IaPronostic>[];
    for (final p in candidates) {
      if (!vues.add(p.courseKey)) continue;
      // Une seule version par course : celle que l'autorité a retenue.
      final retenue = _retenues[p.courseKey];
      if (retenue == null) continue;
      resultat.add(retenue);
    }
    return List.unmodifiable(resultat);
  }

  /// Toutes les versions archivées.
  List<IaPronostic> toutesLesVersionsArchivees() =>
      List.unmodifiable(_shards.values.expand((l) => l).toList());

  /// Nombre de versions distinctes pour une course.
  int nbVersions(String courseKey) =>
      _empreintesParCourse[courseKey]?.length ?? 0;

  /// Mois connus ('YYYY-MM').
  List<String> get moisConnus =>
      List.unmodifiable(_shards.keys.toList()..sort());

  @visibleForTesting
  Future<void> chargerPourTest() => _load();

  @visibleForTesting
  List<IaPronostic> get fileEchecPourTest =>
      List.unmodifiable(_evictionsNonArchivees);

  @visibleForTesting
  List<Map<String, String>> journalVersionsPourTest(String courseKey) =>
      List.unmodifiable(_journalVersions[courseKey] ?? const []);
}

// ─── Entrée différée de la file ────────────────────────────────────────────
class _EntreeFile {
  final IaPronostic pronostic;
  final String motif;
  const _EntreeFile(this.pronostic, this.motif);
}
