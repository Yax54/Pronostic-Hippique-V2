// ═══════════════════════════════════════════════════════════════════════════
//  IA USER PREFS SERVICE — v9.85
//  Déduit silencieusement les habitudes de l'utilisateur depuis ses paris
//  et adapte les conseils IA en conséquence.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class IaUserPrefs {
  // ── Types de paris favoris (fréquence) ──────────────────────────────────
  final Map<String, int> frequenceParType;   // ex: {'Quinté+': 12, 'Simple Gagnant': 5}
  // ── Hippodromes favoris (fréquence) ─────────────────────────────────────
  final Map<String, int> frequenceHippodrome; // ex: {'Le Bouscat': 8, 'Vincennes': 3}
  // ── Mises habituelles ───────────────────────────────────────────────────
  final List<double> misesUtilisees;          // historique des mises en €
  // ── Disciplines préférées ────────────────────────────────────────────────
  final Map<String, int> frequenceDiscipline; // ex: {'Plat': 10, 'Trot': 4}
  // ── Moment de la journée préféré ─────────────────────────────────────────
  final Map<int, int> frequenceHeure;         // ex: {14: 6, 15: 3} (heures)

  const IaUserPrefs({
    this.frequenceParType    = const {},
    this.frequenceHippodrome = const {},
    this.misesUtilisees      = const [],
    this.frequenceDiscipline = const {},
    this.frequenceHeure      = const {},
  });

  // ── Getters calculés ─────────────────────────────────────────────────────
  String get typeFavori {
    if (frequenceParType.isEmpty) return '';
    return frequenceParType.entries
        .reduce((a, b) => a.value > b.value ? a : b).key;
  }

  String get hippodromeFavori {
    if (frequenceHippodrome.isEmpty) return '';
    return frequenceHippodrome.entries
        .reduce((a, b) => a.value > b.value ? a : b).key;
  }

  double get miseMoyenne {
    if (misesUtilisees.isEmpty) return 5.0;
    return misesUtilisees.reduce((a, b) => a + b) / misesUtilisees.length;
  }

  double get miseHabituelle {
    if (misesUtilisees.isEmpty) return 5.0;
    // Mise la plus fréquente
    final freq = <double, int>{};
    for (final m in misesUtilisees) {
      final rounded = (m * 2).round() / 2; // arrondi à 0.5€
      freq[rounded] = (freq[rounded] ?? 0) + 1;
    }
    return freq.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  String get disciplineFavorite {
    if (frequenceDiscipline.isEmpty) return '';
    return frequenceDiscipline.entries
        .reduce((a, b) => a.value > b.value ? a : b).key;
  }

  // ── Sérialisation ─────────────────────────────────────────────────────────
  Map<String, dynamic> toJson() => {
    'parType':      frequenceParType,
    'hippodrome':   frequenceHippodrome,
    'mises':        misesUtilisees,
    'discipline':   frequenceDiscipline,
    'heure':        frequenceHeure.map((k, v) => MapEntry(k.toString(), v)),
  };

  factory IaUserPrefs.fromJson(Map<String, dynamic> j) {
    return IaUserPrefs(
      frequenceParType:    Map<String, int>.from(j['parType'] as Map? ?? {}),
      frequenceHippodrome: Map<String, int>.from(j['hippodrome'] as Map? ?? {}),
      misesUtilisees:      (j['mises'] as List? ?? []).map((e) => (e as num).toDouble()).toList(),
      frequenceDiscipline: Map<String, int>.from(j['discipline'] as Map? ?? {}),
      frequenceHeure:      (j['heure'] as Map? ?? {}).map((k, v) => MapEntry(int.parse(k.toString()), v as int)),
    );
  }
}

class IaUserPrefsService extends ChangeNotifier {
  static IaUserPrefsService? _instance;
  static IaUserPrefsService get instance {
    _instance ??= IaUserPrefsService._();
    return _instance!;
  }
  IaUserPrefsService._();

  static const _key = 'ia_user_prefs_v1';

  IaUserPrefs _prefs = const IaUserPrefs();
  IaUserPrefs get prefs => _prefs;

  // ── Init ──────────────────────────────────────────────────────────────────
  static Future<void> init() async {
    final svc   = instance;
    final sp    = await SharedPreferences.getInstance();
    final raw   = sp.getString(_key);
    if (raw != null) {
      try {
        svc._prefs = IaUserPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
  }

  // ── Mise à jour depuis l'historique des paris ─────────────────────────────
  /// Appelé après chaque nouveau pari ou résultat pour mettre à jour les prefs
  Future<void> analyserDepuisParis(List<dynamic> trackedCourses) async {
    final freqType    = <String, int>{};
    final freqHippo   = <String, int>{};
    final freqDisc    = <String, int>{};
    final freqHeure   = <int, int>{};
    final mises       = <double>[];

    for (final tc in trackedCourses) {
      // tc est un TrackedCourse — on accède via réflexion duck-typing
      try {
        final type    = tc.typePari as String? ?? '';
        final hippo   = tc.hippodrome as String? ?? '';
        final mise    = (tc.miseEngagee as double?) ?? 0.0;
        final heure   = (tc.heureDepart as DateTime?)?.hour ?? 0;

        if (type.isNotEmpty)  freqType[type]    = (freqType[type]   ?? 0) + 1;
        if (hippo.isNotEmpty) freqHippo[hippo]  = (freqHippo[hippo] ?? 0) + 1;
        if (mise > 0)         mises.add(mise);
        if (heure > 0)        freqHeure[heure]  = (freqHeure[heure] ?? 0) + 1;
      } catch (_) {}
    }

    // Garder max 50 mises pour le calcul de moyenne
    final misesRecentes = mises.length > 50 ? mises.sublist(mises.length - 50) : mises;

    _prefs = IaUserPrefs(
      frequenceParType:    freqType,
      frequenceHippodrome: freqHippo,
      misesUtilisees:      misesRecentes,
      frequenceDiscipline: freqDisc,
      frequenceHeure:      freqHeure,
    );

    await _sauvegarder();
    notifyListeners();
  }

  Future<void> _sauvegarder() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, jsonEncode(_prefs.toJson()));
  }

  // ── Conseils personnalisés ────────────────────────────────────────────────

  /// Mise suggérée selon la confiance IA (stratégie adaptative)
  double miseSuggeree(double scoreIA) {
    final base = _prefs.miseHabituelle > 0 ? _prefs.miseHabituelle : 5.0;
    if (scoreIA >= 88) return (base * 2.0).clamp(2.0, 200.0);
    if (scoreIA >= 75) return (base * 1.5).clamp(2.0, 200.0);
    if (scoreIA >= 60) return base.clamp(2.0, 200.0);
    return (base * 0.5).clamp(2.0, 200.0);
  }

  /// Message personnalisé selon les préférences
  String messagePersonnalise(String nomCourse, String hippodrome, String typePariConseille) {
    final parts = <String>[];

    // Hippodrome favori
    if (_prefs.hippodromeFavori.isNotEmpty &&
        hippodrome.toLowerCase().contains(_prefs.hippodromeFavori.toLowerCase())) {
      parts.add('C\'est ton hippodrome préféré — ${_prefs.hippodromeFavori}. Tu le connais bien.');
    }

    // Type de pari habituel
    if (_prefs.typeFavori.isNotEmpty && typePariConseille == _prefs.typeFavori) {
      parts.add('Je te suggère le ${_prefs.typeFavori} — ta stratégie habituelle.');
    }

    // Mise suggérée
    final miseBase = _prefs.miseHabituelle;
    if (miseBase > 0) {
      parts.add('Mise habituelle : ${miseBase.toStringAsFixed(0)} €.');
    }

    return parts.isEmpty ? '' : parts.join(' ');
  }

  /// Résumé des préférences pour l'affichage dans le profil
  String get resumePreferences {
    final parts = <String>[];
    if (_prefs.typeFavori.isNotEmpty)       parts.add(_prefs.typeFavori);
    if (_prefs.hippodromeFavori.isNotEmpty) parts.add(_prefs.hippodromeFavori);
    if (_prefs.miseHabituelle > 0)         parts.add('${_prefs.miseHabituelle.toStringAsFixed(0)} €/course');
    return parts.isEmpty ? 'Aucune préférence détectée' : parts.join(' · ');
  }

  // ══════════════════════════════════════════════════════════════════════
  //  ★ B5c — Vidage RAM pour reset complet
  // ══════════════════════════════════════════════════════════════════════

  /// Remet les préférences à leur valeur par défaut SANS écrire sur le disque.
  ///
  /// Appelé exclusivement par `BackupService.reinitialiserComplet()`, APRÈS
  /// que `ia_user_prefs_v1` a été supprimée du stockage.
  ///
  /// Réinitialisation par une instance `const IaUserPrefs()` VIDES et non un
  /// `clear()` de collection : `_prefs` est un objet immuable remplacé en bloc
  /// (l.137), pas une collection mutable.
  ///
  /// Pourquoi ce vidage est nécessaire : `_prefs` est lu par 3 widgets
  /// (profile_profil_tab.dart:685, profile_progression_tab.dart:230 et :263).
  /// Sans ce vidage, la section « Préférences détectées » continuait d'afficher
  /// l'ancien hippodrome favori, l'ancienne mise habituelle et les anciennes
  /// suggestions de mise — alors que le disque était vide.
  ///
  /// Pourquoi il n'y a AUCUN flag `_charge` à réarmer : ce service n'a pas de
  /// lecteur paresseux. `init()` (l.99) n'est appelé qu'une fois, au démarrage
  /// (main.dart:72), et n'est jamais rejoué après un reset.
  ///
  /// ⚠️ Risque RÉSIDUEL RÉEL, NON corrigé à cette étape (voir R-8) :
  ///   après ce vidage, un `analyserDepuisParis()` qui s'exécuterait AVANT que
  ///   `AlertService` (source de `preds`) n'ait été vidé pourrait recalculer
  ///   des préférences depuis des données périmées et les réécrire. En pratique
  ///   le risque est neutralisé : `analyserDepuisParis` est TOUJOURS appelé APRÈS
  ///   le vidage d'`AlertService` dans le même méthode `_lancerAnalyseJournee`,
  ///   et `verifierTout` (qui dure bien plus longtemps) s'intercale entre les
  ///   deux. Sans correctif sur `AlertService` (étape 5), cette garantie
  ///   n'est pas démontrable — voir le rapport B5c-4.
  ///
  /// ⚠️ Pas de résurrection DISQUE possible par ce service : `_sauvegarder()`
  ///   (l.149) a UN SEUL appelant, `analyserDepuisParis()` (l.145), qui
  ///   REMPLACE `_prefs` (l.137) par un recalcul complet. Ce service ne fait
  ///   JAMAIS de fusion avec l'ancien état. Ce n'est pas le défaut des
  ///   étapes 1, 2 et 3.
  void viderMemoirePourResetComplet() {
    final avait = _prefs.frequenceParType.isNotEmpty ||
        _prefs.frequenceHippodrome.isNotEmpty ||
        _prefs.misesUtilisees.isNotEmpty ||
        _prefs.frequenceDiscipline.isNotEmpty ||
        _prefs.frequenceHeure.isNotEmpty;
    _prefs = const IaUserPrefs();
    if (kDebugMode) {
      debugPrint('[IaUserPrefs] 🧹 Préférences réinitialisées '
          '(reset complet, disque non réécrit — avait des données : $avait)');
    }
    notifyListeners();
  }

  static const List<String> keysBackup = [_key];
}
