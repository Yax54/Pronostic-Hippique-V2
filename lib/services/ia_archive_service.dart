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

import 'ia_memory_models.dart';

// ─── Clés de persistance ────────────────────────────────────────────────────
const String kIaArchiveManifestKey = 'ia_archive_v1_manifest';
const String _kShardPrefix         = 'ia_archive_v1_';

/// Version interne du format d'archive (distincte de la version de backup).
const int kIaArchiveFormatVersion = 1;

// ─── Motif d'archivage (audit uniquement — jamais dans l'empreinte) ─────────
class ArchiveReason {
  /// Retrait de la mémoire de travail (dépassement de la limite de 600).
  static const eviction   = 'eviction';

  /// Excédent au moment de l'écriture du blob des pronostics.
  static const troncature = 'troncature';
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
  final List<String> shardsPerdus;     // clé absente du stockage
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
  final Map<String, List<IaPronostic>> _shards = {};

  /// courseKey → empreintes déjà présentes (dédoublonnage O(1)).
  final Map<String, Set<String>> _empreintesParCourse = {};

  /// courseKey → empreinte de la version retenue.
  final Map<String, String> _versionRetenue = {};

  /// courseKey → version retenue (objet complet).
  final Map<String, IaPronostic> _retenues = {};

  /// Journal d'audit : courseKey → {empreinte, motif, retenue}. Rien n'est détruit.
  final Map<String, List<Map<String, String>>> _journalVersions = {};

  /// File des évictions dont l'archivage n'a pas été confirmé.
  /// AUCUNE LIMITE. AUCUN ABANDON.
  final List<IaPronostic> _evictionsNonArchivees = [];

  /// Objets en file pas encore indexés en mémoire (intégration différée après
  /// le chargement, car `enregistrerEviction` est synchrone).
  final List<_EntreeFile> _aIntegrer = [];

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
  bool get doitGelerBlobPronostics => _evictionsNonArchivees.isNotEmpty;

  /// Nombre total de versions archivées (toutes courses, tous mois).
  int get nbVersionsArchivees =>
      _shards.values.fold(0, (s, l) => s + l.length);

  /// Nombre de prédictions distinctes (courseKey) représentées.
  int get nbPredictionsDistinctes => _retenues.length;

  /// Clés de stockage utilisées (pour E3 : backup/restauration).
  List<String> get clesPersistees =>
      [kIaArchiveManifestKey, ..._nomsDeShards()..sort()];

  // ═══════════════════════════════════════════════════════════════════════
  //  CHARGEMENT (idempotent, sûr en concurrence)
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _load() async {
    if (_charge) return;
    if (_loadCompleter != null) return _loadCompleter!.future;
    _loadCompleter = Completer<void>();
    try {
      await _chargerDepuisStockage();
      _charge = true;
    } finally {
      _loadCompleter!.complete();
      _loadCompleter = null;
    }
  }

  Future<void> _chargerDepuisStockage() async {
    final prefs = await SharedPreferences.getInstance();

    final clesPresentes = prefs
        .getKeys()
        .where((k) => k.startsWith(_kShardPrefix))
        .where((k) => k != kIaArchiveManifestKey)
        .toList();

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
      _shards[mois] = versions;
      for (final p in versions) {
        _enregistrerIndex(p);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  void _resetInMemory() {
    _charge = false;
    _loadCompleter = null;
    _shards.clear();
    _empreintesParCourse.clear();
    _versionRetenue.clear();
    _retenues.clear();
    _journalVersions.clear();
    _evictionsNonArchivees.clear();
    _aIntegrer.clear();
    _writeChain = Future<void>.value();
    dernierArchivageConfirme = true;
    derniereErreurArchive = null;
    cyclesEchecConsecutifs = 0;
    alerteMemoireArchive = false;
    derniereVerificationArchive = null;
  }

  /// Simule un redémarrage : vide l'état RAM, puis relit le stockage.
  @visibleForTesting
  Future<void> reinitialiserMemoirePourTest() async {
    _resetInMemory();
    await _load();
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

  /// Empreinte STABLE du CONTENU (FNV-1a 64 bits, identique d'un processus à
  /// l'autre). Le motif technique n'y figure pas : une éviction et une
  /// troncature du même objet produisent la même empreinte.
  static String empreinteDe(IaPronostic p) {
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
    _enregistrerIndex(p);
    _journalVersions.putIfAbsent(p.courseKey, () => []).add({
      'empreinte': emp,
      'motif': motif,
      'retenue': _versionRetenue[p.courseKey] == emp ? '1' : '0',
    });
    return true;
  }

  static String _moisDe(IaPronostic p) =>
      '${p.datePronostic.year}-'
      '${p.datePronostic.month.toString().padLeft(2, '0')}';

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
    if (_evictionsNonArchivees.isEmpty) return true;
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

      var toutEcrit = true;
      for (final entry in parMois.entries) {
        final ok = await _persisterShard(entry.key);
        if (ok) {
          // Archivage CONFIRMÉ → retrait de la file (la copie durable reste).
          for (final p in entry.value) {
            _evictionsNonArchivees.remove(p);
          }
        } else {
          toutEcrit = false;
        }
      }

      if (toutEcrit && _evictionsNonArchivees.isEmpty) {
        dernierArchivageConfirme = true;
        cyclesEchecConsecutifs = 0;
      } else {
        _signalerEchec('persisterEnAttente : '
            '${_evictionsNonArchivees.length} éviction(s) non confirmée(s)');
      }
      return _evictionsNonArchivees.isEmpty;
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
    final jsonStr = json.encode(versions.map((p) => p.toJson()).toList());
    final b64 = base64Encode(GZipCodec().encode(utf8.encode(jsonStr)));
    // Le bool représente une durabilité ANNONCÉE (pas une garantie physique).
    final ok = await prefs.setString('$_kShardPrefix$mois', b64);
    if (ok) await _ecrireManifeste();
    return ok;
  }

  Future<void> _ecrireManifeste() async {
    final prefs = await SharedPreferences.getInstance();
    final mois = _shards.keys.toList()..sort();
    await prefs.setString(
      kIaArchiveManifestKey,
      json.encode({'version': kIaArchiveFormatVersion, 'mois': mois}),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  RELECTURE — destinée aux tests et à E2. Jamais utilisée par l'apprentissage.
  // ═══════════════════════════════════════════════════════════════════════

  /// Version retenue pour une course (une seule par courseKey).
  IaPronostic? versionRetenue(String courseKey) => _retenues[courseKey];

  /// Toutes les versions archivées d'une course (y compris écartées).
  List<IaPronostic> toutesLesVersions(String courseKey) => List.unmodifiable(
      _shards.values.expand((l) => l).where((p) => p.courseKey == courseKey));

  /// Versions archivées d'un mois ('YYYY-MM').
  List<IaPronostic> versionsDuMois(String mois) =>
      List.unmodifiable(_shards[mois] ?? const <IaPronostic>[]);

  /// Toutes les versions archivées.
  List<IaPronostic> toutesLesVersionsArchivees() =>
      List.unmodifiable(_shards.values.expand((l) => l).toList());

  /// Nombre de versions distinctes pour une course.
  int nbVersions(String courseKey) => _empreintesParCourse[courseKey]?.length ?? 0;

  /// Mois connus ('YYYY-MM').
  List<String> get moisConnus => List.unmodifiable(_shards.keys.toList()..sort());

  List<String> _nomsDeShards() =>
      _shards.keys.map((m) => '$_kShardPrefix$m').toList();

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
