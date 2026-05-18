// ═══════════════════════════════════════════════════════════════════════════
//  IaPerformanceScreen — Historique & performances de l'IA Pronostic Hippique
//
//  Affiche :
//   • Taux de réussite de l'IA (estimations basées sur données réelles ZT)
//   • Analyse des forces/faiblesses par discipline et hippodrome
//   • Conseils pour maximiser l'utilisation de l'IA
//   • Historique de vos paris et résultats
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/alert_service.dart';
import '../services/ia_memory_service.dart';
import '../services/ia_memory_models.dart';
import '../services/data_refresh_service.dart';
import '../services/ia_personality_service.dart'; // ★ v9.85
import '../services/ia_badges_service.dart';       // ★ v9.85
import '../services/ia_user_prefs_service.dart';   // ★ v9.85
import '../providers/pmu_provider.dart';
import '../utils/format_euros.dart';
import '../widgets/ia/ia_performance_dialogs.dart';
import '../widgets/ia/ia_widgets_communs.dart';     // ★ v9.90 découpage
import '../widgets/ia/ia_tab_stats.dart';           // ★ v9.90 découpage
import '../widgets/ia/ia_tab_methodologie.dart';    // ★ v9.90 découpage
import '../widgets/ia/ia_tab_conseils.dart';        // ★ v9.90 découpage
import '../widgets/ia/ia_tab_backtesting.dart';     // ★ v9.90 découpage
import '../widgets/ia/ia_bubble_widget.dart';        // ★ v9.93 bulles
import '../widgets/ia/ia_calendrier_tab.dart';       // ★ v10.25 calendrier performances
// import 'ia_journal_screen.dart'; // ★ v9.85 — conservé pour navigation (non utilisé directement)

part 'ia_perf_secondary_widgets.dart'; // ★ v9.93 : widgets secondaires

class IaPerformanceScreen extends StatefulWidget {
  final AlertService alertService;

  const IaPerformanceScreen({super.key, required this.alertService});

  // ★ v10.27 : raccourci depuis HomeScreen — ouvre l'onglet Calendrier (index 2)
  static _IaPerformanceScreenState? _instance;
  static void ouvrirOngletCalendrier() {
    _instance?._tabCtrl.animateTo(2, duration: Duration.zero); // ★ fix : duration zéro = téléportation sans animation
  }

  @override
  State<IaPerformanceScreen> createState() => _IaPerformanceScreenState();
}

class _IaPerformanceScreenState extends State<IaPerformanceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  IaStats? _statsReelles;

  // ── État analyse journée ──────────────────────────────────────────────────
  bool _analyseEnCours  = false;
  bool _relanceEnCours  = false;
  String _analyseMessage = '';
  int _analyseEtape = 0;
  int _analyseTotal = 6;
  AnalyseJourneeResultat? _dernierResultat;
  // ★ v9.92 : Date+heure de la dernière analyse (persistée)
  DateTime? _derniereAnalyseHeure;
  // ★ v9.6 : Bouton recréer pronostics
  bool _recreationEnCours = false;
  int _nbManquants = 0;
  int _nbTotal = 0;

  // ★ v9.90 : variables _bt* migrées dans IaTabBacktesting (StatefulWidget autonome)

  // ── Filtre période Précision IA ───────────────────────────────────────────
  // null='60j' | 'all' | '7j' | 'today' | 'custom'
  String? _filtrePeriode;
  DateTime? _filtreDebut;
  DateTime? _filtreFin;

  // ★ v9.79 : Date d'analyse (défaut = aujourd'hui)
  DateTime _dateAnalyse = DateTime.now();

  // ★ v9.88 : Statut fichiers analyse par jour (clé = 'JJMMAAAA', valeur = 'ok'|'partiel'|'absent')
  // ignore: unused_field
  Map<String, String> _statutFichiers = {};

  static const _dark = Color(0xFF0D1B2A);
  static const _card = Color(0xFF111F30);
  static const _green = Color(0xFF4CAF7D);
  // ignore: unused_field
  static const _dgreen = Color(0xFF2E7D52);
  static const _gold = Color(0xFFFFD700);
  static const _purple = Color(0xFF7C4DFF);

  @override
  void initState() {
    super.initState();
    IaPerformanceScreen._instance = this; // ★ v10.27 : raccourci calendrier
    _tabCtrl = TabController(length: 6, vsync: this);
    _loadStats();
    IaMemoryService.instance.addListener(_loadStats);
    // ★ v9.90 : _chargerPrefsBt() migré dans IaTabBacktesting.initState()
    // ★ v9.84 : Auto-recréation au 1er chargement si mémoire vide
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoRecreerSiVide());
    // ★ v9.88 : Charger le statut des fichiers d'analyse au démarrage
    WidgetsBinding.instance.addPostFrameCallback((_) => _verifierFichiersJours());
    // ★ v9.92 : Charger la date/heure de la dernière analyse
    WidgetsBinding.instance.addPostFrameCallback((_) => _chargerDerniereAnalyseHeure());
  }

  /// ★ v9.84 : Lance la recréation automatiquement si c'est le 1er chargement
  /// du jour et que des pronostics sont manquants — évite le clic manuel.
  Future<void> _autoRecreerSiVide() async {
    final prefs = await SharedPreferences.getInstance();
    final now   = DateTime.now();
    final todayKey = 'auto_recreer_${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}';
    final dejaFait = prefs.getBool(todayKey) ?? false;
    if (dejaFait) return;

    // Attendre que _calculerManquants ait fini (setState est async)
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    if (_nbManquants > 0 && _nbTotal > 0 && !_recreationEnCours) {
      await prefs.setBool(todayKey, true);
      _recreerPronostics();
    }
  }

  // ★ v9.90 : _chargerPrefsBt() et _sauvegarderPrefsBt() migrés dans IaTabBacktesting

  void _loadStats() {
    // ★ v9.6 : Calculer les pronostics manquants
    _calculerManquants();
    if (!mounted) return;
    // ── Alimenter l'IA depuis tous les paris TrackedCourse résolus (isGagne != null) ──
    _syncTrackedCoursesToIa();
    setState(() {
      _statsReelles = IaMemoryService.instance.calculerStats();
    });
  }

  /// Synchronise les paris suivis (TrackedCourse) avec les stats IA.
  /// Tous les paris avec un résultat connu (isGagne != null) sont transmis.
  void _syncTrackedCoursesToIa() {
    final trackedCourses = widget.alertService.trackedCourses.values
        .where((tc) => tc.isGagne != null && (tc.miseEngagee ?? 0.0) > 0)
        .toList();

    if (trackedCourses.isEmpty) return;

    final predictions = trackedCourses.map((tc) {
      // Calculer le gain net : si gagné, on estime le retour selon la cote
      final mise = tc.miseEngagee ?? 0.0;
      final cote = tc.cote > 0 ? tc.cote : 2.0;
      final gainNet = tc.isGagne == true
          ? (mise * cote - mise) // gain = mise * cote - mise
          : -mise;              // perte = mise engagée
      return {
        'typePari':  tc.typePari,
        'isCorrect': tc.isGagne == true,
        'gainNet':   gainNet,
      };
    }).toList();

    // Mise à jour asynchrone sans bloquer l'UI
    IaMemoryService.instance.mettreAJourStatsTypes(predictions);
  }

  @override
  void dispose() {
    if (IaPerformanceScreen._instance == this) {
      IaPerformanceScreen._instance = null; // ★ v10.27
    }
    IaMemoryService.instance.removeListener(_loadStats);
    _tabCtrl.dispose();
    super.dispose();
  }

  // ── Lancer l'analyse journée ─────────────────────────────────────────────
  /// ★ v9.6 : Calculer combien de pronostics manquent pour aujourd'hui
  void _calculerManquants() {
    final svc = DataRefreshService.instance;
    final reunions = svc.reunions;
    final now = _dateAnalyse; // ★ v9.79 : date sélectionnée (pas forcément aujourd'hui)
    final todayStr = '${now.day.toString().padLeft(2, '0')}'
        '${now.month.toString().padLeft(2, '0')}${now.year}';

    int total = 0;
    int manquants = 0;

    for (final reunion in reunions) {
      final code = reunion.code;
      final numRMatch = RegExp(r'R(\d+)').firstMatch(code);
      final numR = numRMatch != null
          ? int.tryParse(numRMatch.group(1) ?? '1') ?? 1 : 1;

      for (final course in reunion.courses) {
        if (course.partants.isEmpty) continue;
        final dep = course.heureDateTime;
        final dj = dep.day.toString().padLeft(2, '0');
        final dm = dep.month.toString().padLeft(2, '0');
        if ('$dj$dm${dep.year}' != todayStr) continue;

        total++;
        final courseKey = 'R${numR}C${course.numCourse}_$dj$dm${dep.year}';
        if (IaMemoryService.instance.getPronostic(courseKey) == null) {
          manquants++;
        }
      }
    }

    if (mounted) {
      setState(() {
        _nbTotal = total;
        _nbManquants = manquants;
      });
    }
  }

  /// ★ v9.6 : Recréer les pronostics manquants depuis les partants affichés
  Future<void> _recreerPronostics() async {
    if (_recreationEnCours) return;
    setState(() => _recreationEnCours = true);

    try {
      final svc = DataRefreshService.instance;
      final nbCrees = await IaMemoryService.instance
          .recreerPronosticsManquants(svc.reunions);

      _calculerManquants();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(nbCrees > 0
              ? '✅ $nbCrees pronostic(s) recréé(s) avec succès !'
              : '✅ Tous les pronostics étaient déjà en mémoire'),
          backgroundColor: nbCrees > 0
              ? const Color(0xFF1B5E20)
              : const Color(0xFF1A3A5C),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Erreur : $e'),
          backgroundColor: const Color(0xFF5C1A1A),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _recreationEnCours = false);
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // ★ v9.88 : Gestion fichiers rapport journalier
  // Format : ia_analyse_JJMMAAAA_HHmm.json dans getApplicationDocumentsDirectory
  // ══════════════════════════════════════════════════════════════════════

  /// Retourne le dossier de stockage des rapports d'analyse
  Future<Directory> _dossierRapports() async {
    final base = await getApplicationDocumentsDirectory();
    final dir  = Directory('${base.path}/ia_analyses');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Nom du fichier pour une date + heure donnée
  String _nomFichierJour(DateTime date, {DateTime? heure}) {
    final jj = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    final aa = date.year.toString();
    if (heure != null) {
      final hh  = heure.hour.toString().padLeft(2, '0');
      final min = heure.minute.toString().padLeft(2, '0');
      return 'ia_analyse_${jj}${mm}${aa}_${hh}${min}.json';
    }
    return 'ia_analyse_${jj}${mm}${aa}';
  }

  /// Vérifie si un fichier complet existe pour une date donnée
  /// Retourne 'ok' | 'partiel' | 'absent'
  Future<String> _statutFichierJour(DateTime date) async {
    try {
      final dir   = await _dossierRapports();
      final prefix = _nomFichierJour(date);
      final files  = await dir.list().where(
        (f) => f.path.contains(prefix) && f.path.endsWith('.json')
      ).toList();
      if (files.isEmpty) return 'absent';
      // Vérifier que le fichier est complet (contient nbNouveauxResultats > 0)
      for (final f in files) {
        try {
          final content = await File(f.path).readAsString();
          final json    = jsonDecode(content) as Map<String, dynamic>;
          if ((json['nbNouveauxResultats'] as int? ?? 0) > 0) return 'ok';
          if ((json['nbCoursesAnalysees'] as int? ?? 0) > 0) return 'partiel';
        } catch (_) {}
      }
      return 'partiel';
    } catch (_) {
      return 'absent';
    }
  }

  /// Recharge le statut des 3 derniers jours
  Future<void> _verifierFichiersJours() async {
    final now = DateTime.now();
    final map = <String, String>{};
    for (final j in [0, 1, 2]) {
      final date   = now.subtract(Duration(days: j));
      final key    = _nomFichierJour(date);
      map[key]     = await _statutFichierJour(date);
    }
    if (mounted) setState(() => _statutFichiers = map);
  }

  // ── ★ v9.92 : Charger/sauvegarder la date+heure de la dernière analyse ──────

  Future<void> _chargerDerniereAnalyseHeure() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('ia_derniere_analyse_heure_v1');
    if (stored != null && mounted) {
      try {
        final dt = DateTime.parse(stored);
        setState(() => _derniereAnalyseHeure = dt);
      } catch (_) {}
    }
  }

  Future<void> _sauvegarderDerniereAnalyseHeure(DateTime dt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ia_derniere_analyse_heure_v1', dt.toIso8601String());
  }

  /// Sauvegarde le résultat d'une analyse dans un fichier JSON horodaté
  Future<void> _sauvegarderFichierRapport(AnalyseJourneeResultat resultat, DateTime dateAnalyse) async {
    try {
      final dir      = await _dossierRapports();
      final now      = DateTime.now();
      final nomFich  = _nomFichierJour(dateAnalyse, heure: now);
      final fichier  = File('${dir.path}/$nomFich');
      final contenu  = jsonEncode({
        'date':               '${dateAnalyse.day.toString().padLeft(2,'0')}/${dateAnalyse.month.toString().padLeft(2,'0')}/${dateAnalyse.year}',
        'heureAnalyse':       '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}',
        'nbCoursesAnalysees': resultat.nbCoursesAnalysees,
        'nbNouveauxResultats':resultat.nbNouveauxResultats,
        'nbSansResultat':     resultat.nbSansResultat,
        'nbCoursesFutures':   resultat.nbCoursesFutures,
        'nbMisesAJour':       resultat.nbMisesAJour,
        'succes':             resultat.succes,
        'complet':            resultat.nbNouveauxResultats > 0,
      });
      await fichier.writeAsString(contenu);
      // Rafraîchir le statut affiché
      await _verifierFichiersJours();
    } catch (e) {
      debugPrint('[ia_analyse] Erreur sauvegarde fichier : $e');
    }
  }

  /// ★ v9.79 : Sélecteur de date — réservé pour usage futur (déclenché programmatiquement)
  // ignore: unused_element
  Future<void> _choisirDateAnalyse() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateAnalyse,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now,
      locale: const Locale('fr', 'FR'),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary:   Color(0xFF00BCD4),
            onPrimary: Colors.white,
            surface:   Color(0xFF111F30),
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _dateAnalyse = picked);
      _calculerManquants();
    }
  }

  Future<void> _lancerAnalyseJournee() async {
    if (_analyseEnCours) return;
    setState(() {
      _analyseEnCours  = true;
      _analyseEtape    = 0;
      _analyseTotal    = 6;
      _analyseMessage  = '🚀 Initialisation…';
      _dernierResultat = null;
    });

    // ── Prédictions utilisateur (communes à toutes les analyses) ─────────────
    final pmuProvider = context.read<PmuProvider>();
    final predictionsFromPmu = pmuProvider.predictions
        .map((p) => {
              'typePari':  p.typePari,
              'isCorrect': p.isCorrect,
              'gainNet':   p.gainNet,
            })
        .toList();
    final predictionsFromTracked = widget.alertService.trackedCourses.values
        .where((tc) => tc.isGagne != null && (tc.miseEngagee ?? 0.0) > 0)
        .map((tc) {
          final mise    = tc.miseEngagee ?? 0.0;
          final cote    = tc.cote > 0 ? tc.cote : 2.0;
          final gainNet = tc.isGagne == true ? (mise * cote - mise) : -mise;
          return {
            'typePari':  tc.typePari,
            'isCorrect': tc.isGagne == true,
            'gainNet':   gainNet,
          };
        })
        .toList();
    final predictionsJson = [...predictionsFromPmu, ...predictionsFromTracked];

    // ── ★ v9.88 : Vérifier J-2 et J-1 via fichiers disque (plus fiable que RAM) ─
    final now            = DateTime.now();
    final joursManquants = <int>[];

    for (final j in [2, 1]) {
      final dateJ  = now.subtract(Duration(days: j));
      final statut = await _statutFichierJour(dateJ);
      // 'absent' ou 'partiel' → relancer
      if (statut != 'ok') joursManquants.add(j);
    }

    // Rattraper les jours manquants silencieusement
    final List<String> resumeRattrapage = [];
    for (final j in joursManquants) {
      final dateJ     = now.subtract(Duration(days: j));
      final labelDate = '${dateJ.day.toString().padLeft(2, "0")}/${dateJ.month.toString().padLeft(2, "0")}';
      if (!mounted) break;
      setState(() => _analyseMessage = '📅 Rattrapage J-$j ($labelDate)…');

      final res = await IaMemoryService.instance.analyseJourneeComplete(
        date: dateJ,
        predictionsUtilisateur: predictionsJson,
        onProgress: (etape, total, msg) {
          if (mounted) setState(() {
            _analyseEtape  = etape;
            _analyseTotal  = total;
            _analyseMessage = '[$labelDate] $msg';
          });
        },
      );

      if (res.succes && res.nbNouveauxResultats > 0) {
        resumeRattrapage.add('✅ $labelDate — ${res.nbNouveauxResultats} résultat(s) rattrapé(s)');
      } else if (res.succes && res.nbCoursesAnalysees > 0) {
        resumeRattrapage.add('☑️ $labelDate — déjà à jour');
      } else {
        resumeRattrapage.add('⏳ $labelDate — résultats PMU non disponibles');
      }
    }

    if (!mounted) return;

    // ── Analyse du jour cible (date sélectionnée dans le sélecteur) ──────────
    if (joursManquants.isNotEmpty) {
      setState(() => _analyseMessage = '🔍 Analyse du jour en cours…');
    }

    final resultat = await IaMemoryService.instance.analyseJourneeComplete(
      date: _dateAnalyse,
      onProgress: (etape, total, msg) {
        if (mounted) setState(() {
          _analyseEtape   = etape;
          _analyseTotal   = total;
          _analyseMessage = msg;
        });
      },
      predictionsUtilisateur: predictionsJson,
    );

    if (!mounted) return;
    setState(() {
      _analyseEnCours  = false;
      _dernierResultat = resultat;
      _statsReelles    = IaMemoryService.instance.calculerStats();
    });

    // ── Snackbar — compte-rendu complet ──────────────────────────────────────
    if (mounted) {
      String msg;
      Color color;

      // Construire le préfixe de rattrapage si des jours ont été traités
      final prefixRattrapage = resumeRattrapage.isNotEmpty
          ? '📅 Rattrapage jours précédents :\n' + resumeRattrapage.map((l) => '  $l').join('\n') + '\n\n📊 Aujourd\'hui :\n'
          : '';

      if (!resultat.succes) {
        msg   = '${prefixRattrapage}❌ ${resultat.messageErreur}';
        color = const Color(0xFF7F1919);
      } else if (resultat.nbNouveauxResultats > 0) {
        msg   = '${prefixRattrapage}✅ ${resultat.nbNouveauxResultats} résultats comparés · '
                '${resultat.nbCoursesAnalysees} courses traitées · '
                '${resultat.nbCoursesFutures} futures ignorées';
        color = const Color(0xFF1B5E20);
      } else if (resultat.nbSansResultat > 0) {
        msg   = '${prefixRattrapage}⏳ ${resultat.nbSansResultat} course(s) passées, résultats PMU pas encore publiés — réessayez après 20h';
        color = const Color(0xFF5D4037);
      } else if (resultat.nbCoursesAnalysees > 0) {
        final dateRef = resultat.dateAnalysee ?? _dateAnalyse;
        final label   = '${dateRef.day.toString().padLeft(2, "0")}/${dateRef.month.toString().padLeft(2, "0")}';
        msg   = '${prefixRattrapage}✅ ${resultat.nbCoursesAnalysees} courses du $label déjà traitées — IA à jour (mise à jour n°${resultat.nbMisesAJour})';
        color = const Color(0xFF1B5E20);
      } else if (resultat.nbCoursesFutures > 0) {
        msg   = '${prefixRattrapage}ℹ️ ${resultat.nbCoursesFutures} courses encore à venir — réessayez ce soir après les courses';
        color = const Color(0xFF1A237E);
      } else {
        msg   = '${prefixRattrapage}ℹ️ Aucune course trouvée — ouvrez l\'onglet Programme pour charger les pronostics';
        color = const Color(0xFF1A237E);
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 15)),
        backgroundColor: color,
        duration: const Duration(seconds: 8),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(12),
      ));
    }

    // ── ★ v9.88 : Sauvegarder fichier rapport + rafraîchir statut ────────────
    if (resultat.succes) {
      await _sauvegarderFichierRapport(resultat, _dateAnalyse);
      // ── ★ v9.92 : Sauvegarder la date+heure de cette analyse ─────────────
      final now92 = DateTime.now();
      await _sauvegarderDerniereAnalyseHeure(now92);
      if (mounted) setState(() => _derniereAnalyseHeure = now92);
    }

    // ── ★ v9.85 : Vérifier badges + sync préférences après analyse ───────────
    if (resultat.succes) {
      final stats    = IaMemoryService.instance.calculerStats();
      final ia       = IaPersonalityService.instance;
      final rapports = IaMemoryService.instance.rapports;
      final preds    = widget.alertService.trackedCourses.values.toList();
      final nbGagnes = preds.where((tc) => tc.isGagne == true).length;
      final gainsNets = preds.fold<double>(0.0, (sum, tc) {
        if (tc.isGagne == null) return sum;
        final mise = tc.miseEngagee ?? 0.0;
        final cote = tc.cote > 0 ? tc.cote : 2.0;
        return sum + (tc.isGagne == true ? (mise * cote - mise) : -mise);
      });

      await IaBadgesService.instance.verifierTout(
        nbCoursesAnalysees:  stats.coursesAvecResultat,
        nbAnalysesJournees:  rapports.length,
        tauxReussite:        stats.tauxFavoriGagnant,
        nbParisTotal:        preds.length,
        nbParisGagnes:       nbGagnes,
        gainsNets:           gainsNets,
        serieGagnante:       0,
        seriePerdante:       0,
        aGagneQuinte:        preds.any((tc) => tc.isGagne == true && tc.typePari == 'Quinté+'),
        aGagneOutsider:      preds.any((tc) => tc.isGagne == true && tc.cote > 10),
        ageIaEnJours:        ia.ageEnJours,
        prenomPersonnalise:  ia.prenom != 'Aria',
        backtestingLance:    false,
      );

      // ★ v9.93 : Bulle après analyse journée
      if (mounted && resultat.succes && resultat.nbNouveauxResultats > 0) {
        final tauxJour = resultat.nbCoursesAnalysees > 0
            ? (resultat.nbNouveauxResultats / resultat.nbCoursesAnalysees * 100).clamp(0.0, 100.0)
            : 0.0;
        final msgAnalyse = ia.messageApresAnalyse(
            resultat.nbCoursesAnalysees, tauxJour);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) IaBubbleOverlayState.afficher(msgAnalyse, type: 'analyse');
        });
      }

      // ★ v9.93 : Bulle montée de niveau
      // Compare le niveau avant et après pour détecter une progression
      final niveauAvant  = ia.niveau;
      ia.mettreAJourStats(
        coursesAvecResultat: stats.coursesAvecResultat,
        tauxReussite:        stats.tauxFavoriGagnant,
      );
      final niveauApres = ia.niveau;
      if (mounted && niveauApres.index > niveauAvant.index) {
        final msgNiveau = ia.messageMonteeNiveau(niveauApres);
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) IaBubbleOverlayState.afficher(msgNiveau, type: 'niveau');
        });
      }

      // ★ v9.93 : Bulle badge débloqué — brancher le callback
      IaBadgesService.instance.onNouveauBadge = (badge) {
        if (mounted) {
          Future.delayed(const Duration(seconds: 4), () {
            if (mounted) IaBubbleOverlayState.afficher(
              '🏆 Badge débloqué : ${badge.emoji} ${badge.titre} !\n${badge.description}',
              type: 'badge',
            );
          });
        }
      };

      // ★ v9.93 : Bulle résumé hebdomadaire (lundi matin seulement)
      final bilanHebdo = IaMemoryService.instance.consommerBilanHebdo();
      if (mounted && bilanHebdo != null) {
        final taux  = bilanHebdo.tauxGagnant.toStringAsFixed(0);
        final nb    = bilanHebdo.totalResultats;
        final disc  = bilanHebdo.meilleureDisc.isNotEmpty
            ? ' Meilleure discipline : ${bilanHebdo.meilleureDisc} (${bilanHebdo.meilleurTaux.toStringAsFixed(0)}%).'
            : '';
        final emoji = bilanHebdo.tauxGagnant >= 40 ? '🔥'
            : bilanHebdo.tauxGagnant >= 28 ? '📊' : '📉';
        Future.delayed(const Duration(seconds: 7), () {
          if (mounted) IaBubbleOverlayState.afficher(
            '$emoji Bilan de la semaine — $taux% de réussite sur $nb courses.$disc\n'
            'Consulte le journal pour tous les détails.',
            type: 'hebdo',
          );
        });
      }

      // Sync préférences utilisateur
      await IaUserPrefsService.instance.analyserDepuisParis(preds);
    }
  }

  // ★ v89 : _statsGlobales supprimé (données statiques inutilisées,
  // remplacées par les statistiques réelles de IaMemoryService.calculerStats())

  // Performance par discipline (données de référence — affichées dans IaTabStats)
  // ignore: unused_field
  static const _statsDiscipline = [
    {'nom': 'Trot Attelé', 'emoji': '🏇', 'tauxTop3': 73.2, 'tauxGagnant': 34.1, 'color': 0xFF4CAF7D},
    {'nom': 'Trot Monté', 'emoji': '🏇', 'tauxTop3': 68.5, 'tauxGagnant': 30.2, 'color': 0xFF66BB6A},
    {'nom': 'Plat', 'emoji': '🐎', 'tauxTop3': 70.8, 'tauxGagnant': 33.5, 'color': 0xFF42A5F5},
    {'nom': 'Obstacle', 'emoji': '🚧', 'tauxTop3': 65.3, 'tauxGagnant': 28.7, 'color': 0xFFFFB74D},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _dark,
      appBar: AppBar(
        backgroundColor: const Color(0xFF111F30),
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            const Icon(Icons.psychology, color: _purple, size: 18),
            const SizedBox(width: 6),
            const Text(
              'IA v2.0 — Performances',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            // Badge stats réelles / estimées
            Builder(builder: (ctx) {
              final s = _statsReelles;
              final hasData = s != null && s.coursesAvecResultat >= 3;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: hasData
                      ? _gold.withValues(alpha: 0.15)
                      : _purple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: hasData
                        ? _gold.withValues(alpha: 0.5)
                        : _purple.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  hasData ? '${s.coursesAvecResultat} courses' : 'Estimé',
                  style: TextStyle(
                    color: hasData ? _gold : _purple,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            }),
          ]),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: TabBar(
            controller: _tabCtrl,
            indicatorColor: _gold,
            indicatorWeight: 3.5,
            labelColor: _gold,
            unselectedLabelColor: Colors.white54,
            labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.3),
            unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            tabs: const [
              Tab(text: '🧠 Mémoire IA', height: 52),
              Tab(text: '🔬 Backtesting', height: 52),
              Tab(text: '📅 Calendrier', height: 52),
              Tab(text: '📊 Statistiques', height: 52),
              Tab(text: '⚙️ Algorithme', height: 52),
              Tab(text: '💡 Conseils', height: 52),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildTabMemoire(),
          const IaTabBacktesting(),
          const IaCalendrierTab(),
          IaTabStats(alertService: widget.alertService),
          const IaTabMethodologie(),
          const IaTabConseils(),
        ],
      ),
    );
  }

  // ── Bandeau stats rapides (en haut de chaque onglet) ─────────────────────
  Widget _buildBandeauStats() {
    final s = _statsReelles;
    final hasData = s != null && s.coursesAvecResultat >= 3;

    // ★ v6.0 : Utiliser calibrationScore (IA auto-calibrée) plutôt que confiancePredite
    // calibrationScore = 50 neutre, >50 = l'IA prédit mieux quand variance haute, <50 = sur-estimée
    final memBandeau = IaMemoryService.instance;
    final calibScore = memBandeau.poids.calibrationScore; // 10–90
    // Score de performance moyen sur les courses avec résultat
    final scorePerfMoyen = hasData ? s.scoreMoyenPerformance : 0.0;

    // Taux de réussite réel : favori IA était gagnant / total avec résultat
    final tauxReussiteReel = hasData ? s.tauxFavoriGagnant : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A0A3A), Color(0xFF0D1B2A)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasData ? _gold.withValues(alpha: 0.35) : _purple.withValues(alpha: 0.25),
        ),
      ),
      child: Column(children: [
        // Ligne 1 : stats de performance classiques
        // ★ v10.36 : libellés clarifiés — "Favori IA" = le cheval N°1 conseillé par l'IA
        Row(children: [
          _buildQuickStatSmall(
            hasData ? '${s.tauxFavoriTop3.toStringAsFixed(0)}%' : '~71%',
            'Top 3', _green,
          ),
          _buildQuickStatSmall(
            hasData ? '${s.tauxFavoriGagnant.toStringAsFixed(0)}%' : '~33%',
            'Gagnant', _gold,
          ),
          _buildQuickStatSmall(
            hasData ? '${s.tauxFavoriTop5.toStringAsFixed(0)}%' : '~84%',
            'Top 5', _purple,
          ),
          _buildQuickStatSmall(
            hasData ? '${s.coursesAvecResultat}' : '0',
            'Courses', const Color(0xFF42A5F5),
          ),
        ]),
        const SizedBox(height: 8),
        // Ligne 2 : Précision IA + Calibration IA
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            // ★ v10.36 : "Taux réussite" renommé "Précision IA" = % conseils bons
            Expanded(
              child: Row(children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: tauxReussiteReel >= 35 ? _green
                         : tauxReussiteReel >= 25 ? _gold
                         : const Color(0xFFEF5350),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    hasData ? '${tauxReussiteReel.toStringAsFixed(1)}%' : 'N/A',
                    style: TextStyle(
                      color: tauxReussiteReel >= 35 ? _green
                           : tauxReussiteReel >= 25 ? _gold
                           : hasData ? const Color(0xFFEF5350) : Colors.white38,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  // ★ v10.36 : libellé plus clair
                  const Text('Précision IA', style: TextStyle(color: Colors.white38, fontSize: 16)),
                ]),
              ]),
            ),
            // Séparateur
            Container(width: 1, height: 28, color: Colors.white12),
            const SizedBox(width: 8),
            // ★ v6.0 : Calibration IA (remplace confiancePredite qui était figée)
            Expanded(
              child: Row(children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: calibScore >= 60 ? _green
                         : calibScore >= 45 ? _gold
                         : const Color(0xFFFF9800),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    hasData
                        ? '${calibScore.toStringAsFixed(0)}/100'
                        : 'N/A',
                    style: TextStyle(
                      color: calibScore >= 60 ? _green
                           : calibScore >= 45 ? _gold
                           : const Color(0xFFFF9800),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text('Calibration IA', style: TextStyle(color: Colors.white38, fontSize: 16)),
                ]),
              ]),
            ),
            // Séparateur
            Container(width: 1, height: 28, color: Colors.white12),
            const SizedBox(width: 8),
            // ★ Score de performance moyen IA (reflète la qualité réelle des pronostics)
            Expanded(
              child: Row(children: [
                Icon(
                  scorePerfMoyen >= 60 ? Icons.trending_up
                      : scorePerfMoyen >= 40 ? Icons.trending_flat
                      : Icons.trending_down,
                  color: scorePerfMoyen >= 60 ? _green
                      : scorePerfMoyen >= 40 ? _gold
                      : hasData ? const Color(0xFFFF9800) : Colors.white38,
                  size: 12,
                ),
                const SizedBox(width: 4),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    hasData ? '${scorePerfMoyen.toStringAsFixed(0)}/100' : 'N/A',
                    style: TextStyle(
                      color: scorePerfMoyen >= 60 ? _green
                           : scorePerfMoyen >= 40 ? _gold
                           : hasData ? const Color(0xFFFF9800) : Colors.white38,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text('Score moyen IA', style: TextStyle(color: Colors.white38, fontSize: 16)),
                ]),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        // ★ v10.36 : note explicative des tuiles Top3/Gagnant/Top5
        Text(
          '▲ Favori IA = cheval N°1 sélectionné — % de fois où il finit gagnant / top3 / top5',
          style: TextStyle(color: Colors.white24, fontSize: 16),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Icon(
            hasData ? Icons.auto_awesome : Icons.info_outline,
            color: hasData ? _gold : _purple,
            size: 12,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              hasData
                  ? '🧠 Stats réelles — ${s.coursesAvecResultat} courses · Calibration ${calibScore >= 60 ? "✅ bonne" : calibScore >= 45 ? "⚠️ correcte" : "❌ à améliorer"} · Score moyen ${scorePerfMoyen.toStringAsFixed(0)}/100'
                  : 'Statistiques estimées — données réelles disponibles après analyse journée',
              style: TextStyle(
                color: hasData ? _gold : _purple,
                fontSize: 16,
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _buildQuickStatSmall(String value, String label, Color color) {
    return Expanded(
      child: Column(children: [
        Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 16)),
      ]),
    );
  }

  // ── Onglet 0 : Mémoire IA (nouvelles données réelles) ───────────────────────

  Widget _buildTabMemoire() {
    final mem    = IaMemoryService.instance;
    final stats  = _statsReelles ?? mem.calculerStats();
    final poids  = mem.poids;
    // Tous les pronostics avec résultat (pas de limite)
    final historique = mem.pronosticsAvecResultat.toList();
    // Tous les pronostics en attente (pas de limite)
    final enAttenteAll = mem.pronostics.where((p) => !p.resultatsReels).toList();
    final enAttenteTotal = enAttenteAll.length;
    // Tous les pronostics confondus triés par date (vue complète)
    final tousPronostics = [...mem.pronostics]
      ..sort((a, b) => b.datePronostic.compareTo(a.datePronostic));
    final journal = mem.journal.take(5).toList();
    final disciplinesApprises = mem.disciplinesApprises;

    final rapports = IaMemoryService.instance.rapports;
    final dernierRapport = IaMemoryService.instance.dernierRapport;

    // ── CAS MÉMOIRE COMPLÈTEMENT VIDE (installation récente / premier lancement) ──
    // Afficher un seul écran d'accueil propre — évite de cumuler les sections
    // vides + le bandeau d'erreur rouge qui créent la confusion sur le screenshot.
    final memoireVide = mem.pronostics.isEmpty;
    final analyseErreurVide = _dernierResultat != null &&
        !_dernierResultat!.succes &&
        _dernierResultat!.isVide;

    if (memoireVide) {
      // Vérifier si des courses sont déjà chargées dans DataRefreshService
      final drs = DataRefreshService.instance;
      final coursesDejaChargees = drs.reunions.isNotEmpty;
      final nbCourses = drs.reunions.fold<int>(0, (sum, r) => sum + r.courses.length);

      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        children: [
          // ── Icône centrale ────────────────────────────────────────────────
          Center(
            child: Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: coursesDejaChargees
                    ? const Color(0xFF4CAF7D).withValues(alpha: 0.12)
                    : const Color(0xFFFF9800).withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: coursesDejaChargees
                      ? const Color(0xFF4CAF7D).withValues(alpha: 0.35)
                      : const Color(0xFFFF9800).withValues(alpha: 0.35),
                  width: 2,
                ),
              ),
              child: Icon(
                coursesDejaChargees ? Icons.sync : Icons.psychology_outlined,
                color: coursesDejaChargees ? const Color(0xFF4CAF7D) : const Color(0xFFFF9800),
                size: 36,
              ),
            ),
          ),
          const SizedBox(height: 18),

          // ── Message principal ─────────────────────────────────────────────
          Center(
            child: Text(
              coursesDejaChargees
                  ? '🔄 Synchronisation nécessaire'
                  : '🧠 Mémoire IA vide',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),

          // ── Explication contextuelle ──────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: coursesDejaChargees
                  ? const Color(0xFF4CAF7D).withValues(alpha: 0.08)
                  : const Color(0xFFFF9800).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: coursesDejaChargees
                    ? const Color(0xFF4CAF7D).withValues(alpha: 0.28)
                    : const Color(0xFFFF9800).withValues(alpha: 0.28),
              ),
            ),
            child: Text(
              coursesDejaChargees
                  ? '✅ $nbCourses courses sont déjà chargées.\n\n'
                    'La mémoire IA a été réinitialisée (réinstallation). '
                    'Lance l\'analyse ci-dessous pour resynchroniser les stats IA avec les données actuelles.'
                  : '📱 L\'IA n\'a pas encore de données.\n\n'
                    'Ouvrez l\'onglet Programme pour charger les courses du jour. '
                    'L\'IA créera automatiquement ses pronostics, puis revenez ici pour lancer l\'analyse.',
              style: TextStyle(
                color: coursesDejaChargees
                    ? const Color(0xFFA5D6A7)
                    : const Color(0xFFFFCC80),
                fontSize: 14,
                height: 1.5,
              ),
              textAlign: TextAlign.left,
            ),
          ),
          const SizedBox(height: 24),

          // ── Bouton Analyser (toujours visible même si vide, pour retry) ───
          _buildCarteAnalyseJournee(),

          // ── Résultat si l'utilisateur a quand même tenté une analyse ─────
          if (analyseErreurVide) ...[
            const SizedBox(height: 12),
            _buildResumeAnalyse(_dernierResultat!),
          ],
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [

        // ── BANDEAU STATS RAPIDES ───────────────────────────────────────────
        _buildBandeauStats(),

        // ── BOUTON ANALYSE JOURNÉE ──────────────────────────────────────────
        _buildCarteAnalyseJournee(),
        const SizedBox(height: 16),

        // ── RAPPORT DU JOUR (si disponible) ────────────────────────────────
        if (dernierRapport != null) ...[
          iaSectionTitle('📋 Dernier rapport journalier'),
          const SizedBox(height: 10),
          _buildRapportJournalierComplet(dernierRapport),
          const SizedBox(height: 16),
        ],

        // ── HISTORIQUE DES RAPPORTS (30 jours glissants) ──────────────────
        if (rapports.length > 1) ...[
          iaSectionTitle('📈 Évolution sur ${rapports.length} jours'),
          const SizedBox(height: 10),
          _buildHistoriqueRapports(rapports),
          const SizedBox(height: 16),
        ],

        // ── STATS PAR TYPE DE PARI ─────────────────────────────────────────
        _buildSectionStatsTypesParis(),
        const SizedBox(height: 16),

        // ── PRÉCISION IA PAR TYPE DE COURSE ────────────────────────────────
        _buildSectionPrecisionIA(),
        const SizedBox(height: 16),

        // ── ★ v9.87 : PRÉCISION IA PAR HIPPODROME ──────────────────────────
        _buildSectionHippodrome(),

        // ── ★ v9.92 : PRÉCISION HIPPODROME × DISCIPLINE ────────────────────
        _buildSectionHippoXDisc(),
        const SizedBox(height: 16),

        // ── ★ v9.93 : CORRÉLATIONS ENTRE CRITÈRES ──────────────────────────
        _buildSectionCorrelations(),
        const SizedBox(height: 16),

        // ── ★ v9.0 : RÉSULTATS PAR LABEL IA ────────────────────────────────
        _buildSectionStatsLabels(),
        const SizedBox(height: 16),

        // ── Statut apprentissage ────────────────────────────────────────────
        _buildStatutApprentissage(poids, stats),
        const SizedBox(height: 16),

        // ★ v9.92 POINT 5 : Journal des critères en hausse/baisse
        _buildJournalCriteres(mem),
        const SizedBox(height: 16),

        // ── Poids adaptatifs globaux ────────────────────────────────────────
        iaSectionTitle('⚙️ Poids IA globaux (auto-ajustés)'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _gold.withValues(alpha: 0.3)),
          ),
          child: Column(children: [
            Row(children: [
              const Icon(Icons.auto_awesome, color: _gold, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  poids.nbMisesAJour == 0
                    ? 'L\'IA ajustera ses poids automatiquement après vos premières courses'
                    : 'L\'IA a ajusté ses poids ${poids.nbMisesAJour} fois — elle s\'améliore !',
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ),
              // Bouton reset
              GestureDetector(
                onTap: () async {
                  await mem.resetPoids();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Poids réinitialisés aux valeurs par défaut'), backgroundColor: Color(0xFF1B5E20)),
                    );
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                  ),
                  child: const Text('Reset', style: TextStyle(color: Colors.red, fontSize: 15)),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            // ★ v5.0 : 10 critères avec valeurs de référence correctes
            _buildPoidsBar('Forme récente',      poids.forme,      0.32, _green),
            _buildPoidsBar('Gains carrière',     poids.gains,      0.15, _gold),
            _buildPoidsBar('Record/Vitesse',     poids.record,     0.12, const Color(0xFF42A5F5)),
            _buildPoidsBar('Régularité',         poids.constance,  0.09, const Color(0xFFCE93D8)),
            _buildPoidsBar('Cote marché',        poids.cote,       0.08, const Color(0xFFFF9800)),
            _buildPoidsBar('Dist. spécialisée',  poids.distSpec,   0.08, const Color(0xFF26C6DA)),
            _buildPoidsBar('Jockey/Driver',      poids.jockey,     0.07, const Color(0xFFAB47BC)),
            _buildPoidsBar('Victoires récentes', poids.victoires,  0.04, const Color(0xFFEF5350)),
            _buildPoidsBar('Fraîcheur physique', poids.repos,      0.03, const Color(0xFF66BB6A)),
            _buildPoidsBar('Discipline',         poids.discipline, 0.02, Colors.teal),
            _buildPoidsBar('Hippodrome',         poids.hippo,      0.04, const Color(0xFF4DB6AC)),
            _buildPoidsBar('Entraîneur',         poids.entraineur, 0.04, const Color(0xFFFFB74D)),
            _buildPoidsBar('ELO dynamique',      poids.elo,        0.05, const Color(0xFFBA68C8)),
            _buildPoidsBar('Terrain',            poids.terrain,    0.05, const Color(0xFF81C784)),
            _buildPoidsBar('Coup préparé',       poids.divergence, 0.04, const Color(0xFFFF7043)),
            _buildPoidsBar('Poids porté',        poids.poidsRel,   0.03, const Color(0xFF90A4AE)),
            _buildPoidsBar('Progression',        poids.progression,0.03, const Color(0xFFF48FB1)),
            _buildPoidsBar('Mvt de cote',        poids.mouvCote,   0.06, const Color(0xFF00BCD4)), // ★ v9.92
            _buildPoidsBar('Place départ',       poids.placeDepart,0.03, const Color(0xFF80CBC4)), // ★ v9.93
          ]),
        ),
        const SizedBox(height: 16),

        // ── Poids par discipline (v3) ───────────────────────────────────────
        if (disciplinesApprises.isNotEmpty) ...[
          iaSectionTitle('🏇 Poids appris par discipline'),
          const SizedBox(height: 8),
          const Text(
            'L\'IA apprend des poids différents selon la discipline — elle sait que les critères n\'ont pas le même impact en Trot qu\'en Plat.',
            style: TextStyle(color: Colors.white38, fontSize: 16),
          ),
          const SizedBox(height: 10),
          ...disciplinesApprises.map((d) => _buildDisciplinePoidsCard(d, poids)),
          const SizedBox(height: 16),
        ],

        // ── Résumé de performance ───────────────────────────────────────────
        iaSectionTitle('📊 Performance réelle de l\'IA'),
        const SizedBox(height: 10),
        if (stats.coursesAvecResultat == 0)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              const Icon(Icons.hourglass_empty, color: Colors.white24, size: 40),
              const SizedBox(height: 8),
              const Text('Pas encore de données réelles', style: TextStyle(color: Colors.white38, fontSize: 16)),
              const SizedBox(height: 4),
              const Text(
                'Les statistiques se rempliront automatiquement\naprès vos premières courses suivies',
                style: TextStyle(color: Colors.white24, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ]),
          )
        else
          Column(children: [
            Row(children: [
              _buildStatCard('${stats.tauxFavoriGagnant.toStringAsFixed(0)}%', 'Favori\ngagnant', _gold),
              const SizedBox(width: 8),
              _buildStatCard('${stats.tauxFavoriTop3.toStringAsFixed(0)}%', 'Favori\ndans top 3', _green),
              const SizedBox(width: 8),
              _buildStatCard('${stats.tauxTop3Correct.toStringAsFixed(0)}%', '2/3 IA\ncorrects', _purple),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              _buildStatCard('${stats.coursesAvecResultat}', 'Courses\nanalysées', const Color(0xFF42A5F5)),
              const SizedBox(width: 8),
              _buildStatCard('${stats.scoreMoyenPerformance.toStringAsFixed(0)}/100', 'Score moyen\nIA', const Color(0xFFFF9800)),
              const SizedBox(width: 8),
              _buildStatCard('${stats.tauxTop5Correct.toStringAsFixed(0)}%', '4/5 IA\ncorrects', Colors.teal), // ★ v10.15
            ]),
          ]),
        const SizedBox(height: 20),

        // ── Journal d'apprentissage (v3) ────────────────────────────────────
        if (journal.isNotEmpty) ...[
          iaSectionTitle('📓 Journal d\'apprentissage (${mem.journal.length} entrées)'),
          const SizedBox(height: 8),
          ...journal.map((e) => _buildJournalCard(e)),
          const SizedBox(height: 20),
        ],

        // ── Historique COMPLET : tous les pronostics IA (gagnants, perdants, en attente)
        if (tousPronostics.isNotEmpty) ...[
          iaSectionTitle('📋 Tous les pronostics IA (${tousPronostics.length})'),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, color: Colors.white24, size: 13),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '✅ Avec résultat : ${historique.length}   ⏳ En attente : $enAttenteTotal — scroll pour tout voir',
                  style: const TextStyle(color: Colors.white38, fontSize: 16),
                ),
              ),
            ]),
          ),
          ...tousPronostics.map((p) => p.resultatsReels
              ? _buildPronosticCard(p)
              : _buildPronosticCardAttente(p)),
          const SizedBox(height: 20),
        ],

        // ── Effacer l'historique ────────────────────────────────────────────
        if (mem.pronostics.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: _card,
                  title: const Text('Effacer la mémoire IA ?', style: TextStyle(color: Colors.white)),
                  content: const Text('Cela supprimera tout l\'historique et réinitialisera les poids.', style: TextStyle(color: Colors.white54)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Effacer', style: TextStyle(color: Colors.red))),
                  ],
                ),
              );
              if (ok == true) {
                await mem.clearHistory();
                await mem.resetPoids();
              }
            },
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Effacer toute la mémoire IA'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: BorderSide(color: Colors.red.withValues(alpha: 0.3)),
            ),
          ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── Widget : Carte bouton Analyse Journée ──────────────────────────────────

  Widget _buildCarteAnalyseJournee() {
    final hasResultat = _dernierResultat != null;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A2A1A),
            const Color(0xFF0F1D2A),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _analyseEnCours
              ? _gold.withValues(alpha: 0.6)
              : _green.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _green.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Titre
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.query_stats_rounded, color: _green, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text(
                    '🧠 Analyse journée IA',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Récupère les résultats PMU, compare les pronostics IA et met à jour l\'apprentissage.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 14),
                  ),
                ]),
              ),
            ]),

            const SizedBox(height: 14),

            // Bloc info pédagogique
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _green.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.schedule_rounded, color: Color(0xFF4CAF7D), size: 16),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'À lancer après les dernières courses, idéalement après 20h30.',
                        style: TextStyle(color: Color(0xFF4CAF7D), fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  const _MiniListeAnalyse(),
                ],
              ),
            ),

            const SizedBox(height: 14),

            const SizedBox(height: 4),

            // Barre de progression (visible seulement pendant l'analyse)
            if (_analyseEnCours) ...[
              Row(children: [
                Expanded(
                  child: Stack(children: [
                    Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: _analyseTotal > 0
                          ? (_analyseEtape / _analyseTotal).clamp(0.0, 1.0)
                          : 0,
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF4CAF7D), Color(0xFFFFD700)],
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 10),
                Text(
                  '$_analyseEtape/$_analyseTotal',
                  style: const TextStyle(color: Colors.white54, fontSize: 16),
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4CAF7D)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _analyseMessage,
                    style: const TextStyle(color: Color(0xFF4CAF7D), fontSize: 16),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
              const SizedBox(height: 12),
            ],

            // Résumé du dernier résultat
            if (!_analyseEnCours && hasResultat) ...[
              _buildResumeAnalyse(_dernierResultat!),
              const SizedBox(height: 12),
            ],

            // Info rapide si aucune analyse encore
            if (!_analyseEnCours && !hasResultat) ...[
              const SizedBox(height: 4),
            ],

            // ★ v9.92 : Encadré "Dernière analyse" — date + heure
            _buildEncadreDerniereAnalyse(),
            const SizedBox(height: 10),

            // ★ v9.6 : Bouton recréer pronostics manquants (AVANT analyser)
            _buildBoutonRecreer(),
            const SizedBox(height: 8),

            // ★ Bouton principal — effet premium Teal dégradé
            GestureDetector(
              onTap: _analyseEnCours ? null : _lancerAnalyseJournee,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 52,
                decoration: BoxDecoration(
                  gradient: _analyseEnCours
                      ? LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.06),
                            Colors.white.withValues(alpha: 0.04),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : const LinearGradient(
                          colors: [Color(0xFF00897B), Color(0xFF00BCD4)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: _analyseEnCours ? [] : [
                    BoxShadow(
                      color: const Color(0xFF00BCD4).withValues(alpha: 0.40),
                      blurRadius: 18,
                      spreadRadius: 1,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: const Color(0xFF00897B).withValues(alpha: 0.25),
                      blurRadius: 8,
                      spreadRadius: 0,
                      offset: const Offset(0, 2),
                    ),
                  ],
                  border: _analyseEnCours ? null : Border.all(
                    color: const Color(0xFF80DEEA).withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_analyseEnCours)
                      const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white54),
                        ),
                      )
                    else
                      const Icon(Icons.auto_fix_high_rounded,
                          size: 20, color: Colors.white),
                    const SizedBox(width: 10),
                    Text(
                      _analyseEnCours ? 'Analyse en cours…' : '🔍 Analyser la journée',
                      style: TextStyle(
                        color: _analyseEnCours ? Colors.white38 : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 0.3,
                      ),
                    ),
                    if (!_analyseEnCours) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('IA',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // ── Bouton 1 : Relancer récupération PMU ─────────────────────
            if (!_analyseEnCours && !_relanceEnCours)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    setState(() => _relanceEnCours = true);
                    final mem = IaMemoryService.instance;

                    // Afficher le début dans le message de progression
                    if (mounted) {
                      setState(() => _analyseMessage =
                          '🔄 Relance récupération PMU…');
                    }

                    final rapport = await mem.relancerRecuperationPMU(
                      onProgress: (msg) {
                        if (mounted) setState(() => _analyseMessage = msg);
                      },
                    );

                    if (!mounted) return;
                    setState(() {
                      _relanceEnCours = false;
                      _analyseMessage = '';
                    });

                    // Afficher le résumé détaillé dans un dialog
                    final details = rapport['details'] as List<String>;
                    final recuperes    = rapport['recuperes']    as int;
                    final introuvables = rapport['introuvables'] as int;
                    final erreurs      = rapport['erreurs']      as int;
                    final total        = rapport['total']        as int;
                    final msgPrincipal = rapport['message']      as String;

                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: const Color(0xFF111F30),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        title: Row(children: [
                          Icon(
                            recuperes > 0
                                ? Icons.check_circle_outline
                                : Icons.info_outline,
                            color: recuperes > 0
                                ? const Color(0xFF4CAF7D)
                                : Colors.orange,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Récupération PMU',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ]),
                        content: SizedBox(
                          width: double.maxFinite,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Résumé chiffré
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(msgPrincipal,
                                        style: TextStyle(
                                          color: recuperes > 0
                                              ? const Color(0xFF4CAF7D)
                                              : Colors.orange,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        )),
                                    if (total > 0) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        '📊 $total course(s) analysée(s) · '
                                        '✅ $recuperes récupérée(s) · '
                                        '⏳ $introuvables en attente · '
                                        '❌ $erreurs erreur(s)',
                                        style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 16),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              // Journal détaillé
                              if (details.isNotEmpty) ...[  
                                const SizedBox(height: 10),
                                const Text('Journal :',
                                    style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxHeight: 200),
                                  child: SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: details
                                          .map((d) => Padding(
                                                padding: const EdgeInsets
                                                    .symmetric(vertical: 2),
                                                child: Text(d,
                                                    style: const TextStyle(
                                                        color: Colors.white54,
                                                        fontSize: 16)),
                                              ))
                                          .toList(),
                                    ),
                                  ),
                                ),
                              ],
                              // Conseil si tout en attente
                              if (introuvables > 0 && recuperes == 0) ...[  
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.orange.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: Colors.orange
                                            .withValues(alpha: 0.3)),
                                  ),
                                  child: const Text(
                                    '💡 Les résultats PMU sont publiés en général après 20h. '
                                    'Si le problème persiste le lendemain, utilisez "Purger" pour nettoyer.',
                                    style: TextStyle(
                                        color: Colors.orange, fontSize: 16),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Fermer',
                                style: TextStyle(color: Colors.white54)),
                          ),
                        ],
                      ),
                    );
                  },
                  icon: _relanceEnCours
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.blue))
                      : const Icon(Icons.refresh, size: 16),
                  label: Text(
                    _relanceEnCours
                        ? _analyseMessage.isNotEmpty
                            ? _analyseMessage
                            : 'Récupération en cours…'
                        : 'Relancer récupération PMU',
                    style: const TextStyle(fontSize: 16),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue,
                    side: BorderSide(
                        color: Colors.blue.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),

            const SizedBox(height: 6),

            // ── Bouton 2 : Purger (dernier recours) ──────────────────────
            if (!_analyseEnCours && !_relanceEnCours)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    // Confirmation avant purge
                    final confirme = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: const Color(0xFF111F30),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        title: const Text('Purger les courses sans résultat',
                            style: TextStyle(
                                color: Colors.white, fontSize: 15)),
                        content: const Text(
                          'Cette action supprime définitivement tous les pronostics '  
                          'sans résultat.\n\n'
                          '⚠️ Utilisez d\'abord "Relancer récupération PMU".\n'
                          'La purge est le dernier recours si l\'API PMU '  
                          'ne répond vraiment plus.',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 16),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Annuler',
                                style:
                                    TextStyle(color: Colors.white54)),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Purger quand même',
                                style: TextStyle(color: Colors.orange)),
                          ),
                        ],
                      ),
                    );
                    if (confirme != true) return;

                    final mem = IaMemoryService.instance;
                    final nb  = await mem.purgerCoursesSansResultat();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(nb > 0
                              ? '🗑️ $nb pronostic(s) sans résultat supprimé(s)'
                              : 'Aucun pronostic sans résultat à supprimer'),
                          backgroundColor: nb > 0
                              ? const Color(0xFF2E7D52)
                              : Colors.white24,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      setState(() {});
                    }
                  },
                  icon: const Icon(Icons.cleaning_services_outlined, size: 16),
                  label: const Text('Purger (dernier recours)',
                      style: TextStyle(fontSize: 16)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: BorderSide(
                        color: Colors.orange.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Widget : Résumé du résultat de l'analyse ──────────────────────────────

  Widget _buildResumeAnalyse(AnalyseJourneeResultat r) {
    if (!r.succes) {
      // ★ Cas "vide/info" (première utilisation ou installation le soir) :
      // → bandeau orange informatif, PAS rouge erreur
      final isVide = r.isVide;
      final bgColor    = isVide ? const Color(0xFFFF9800) : Colors.red;
      final iconWidget = isVide
          ? const Icon(Icons.info_outline, color: Color(0xFFFF9800), size: 18)
          : const Icon(Icons.error_outline, color: Colors.red, size: 18);
      final textColor  = isVide ? const Color(0xFFFFCC80) : Colors.redAccent;

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: bgColor.withValues(alpha: 0.30)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          iconWidget,
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              r.messageErreur ?? 'Erreur inconnue',
              style: TextStyle(color: textColor, fontSize: 14, height: 1.45),
            ),
          ),
        ]),
      );
    }

    final bool avecResultats = r.nbNouveauxResultats > 0;
    final bool toutEnAttente = r.nbNouveauxResultats == 0 && r.nbSansResultat > 0;
    final bool toutFutur = r.nbCoursesAnalysees == 0 && r.nbCoursesFutures > 0 && r.nbSansResultat == 0;

    Color bannerColor;
    IconData bannerIcon;
    String bannerText;
    if (avecResultats) {
      bannerColor = _green;
      bannerIcon = Icons.check_circle_outline;
      bannerText = '${r.nbNouveauxResultats} résultat(s) comparé(s) — IA mise à jour n°${r.nbMisesAJour}';
    } else if (toutEnAttente) {
      bannerColor = Colors.orange;
      bannerIcon = Icons.schedule_rounded;
      bannerText = 'Courses passées mais résultats PMU pas encore publiés';
    } else if (toutFutur) {
      bannerColor = Colors.blue;
      bannerIcon = Icons.upcoming_rounded;
      bannerText = 'Toutes les courses sont encore à venir aujourd\'hui';
    } else {
      bannerColor = _green;
      bannerIcon = Icons.check_circle_outline;
      bannerText = 'Analyse terminée — mise à jour n°${r.nbMisesAJour}';
    }

    return Column(children: [
      // Bannière de statut
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bannerColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: bannerColor.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Icon(bannerIcon, color: bannerColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              bannerText,
              style: TextStyle(color: bannerColor, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 10),

      // Message apprentissage clair
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: avecResultats
              ? const Color(0xFF4CAF7D).withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: avecResultats
                ? const Color(0xFF4CAF7D).withValues(alpha: 0.3)
                : Colors.white12,
          ),
        ),
        child: Row(children: [
          Text(
            avecResultats ? '🧠' : 'ℹ️',
            style: const TextStyle(fontSize: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              avecResultats
                  ? 'Apprentissage IA effectué sur ${r.nbNouveauxResultats} nouveau${r.nbNouveauxResultats > 1 ? 'x' : ''} résultat${r.nbNouveauxResultats > 1 ? 's' : ''}.'
                  : 'IA déjà à jour — aucun nouvel apprentissage déclenché.',
              style: TextStyle(
                color: avecResultats ? const Color(0xFF4CAF7D) : Colors.white54,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 10),

      // Grille de stats : 4 tuiles principales
      // Si nbNouveauxResultats==0 mais courses déjà traitées → afficher nbCoursesAnalysees en teal
      // pour éviter l'affichage trompeur "0 résultats comparés" quand tout est déjà à jour
      Builder(builder: (context) {
        final bool dejaAJour = r.nbNouveauxResultats == 0 && r.nbCoursesAnalysees > 0;
        final String valResultats = dejaAJour ? '${r.nbCoursesAnalysees}' : '${r.nbNouveauxResultats}';
        final String labelResultats = dejaAJour ? 'résultats\ndéjà à jour' : 'résultats\ncomparés';
        final Color couleurResultats = dejaAJour ? const Color(0xFF26A69A) : _gold;
        return Row(children: [
          _buildMiniStat(valResultats, labelResultats, couleurResultats),
          const SizedBox(width: 6),
          _buildMiniStat('${r.nbCoursesAnalysees}', 'courses\ntraitées', const Color(0xFF42A5F5)),
          const SizedBox(width: 6),
          _buildMiniStat('${r.nbPronosticsAjoutes}', 'pronostics\ncréés', _purple),
          const SizedBox(width: 6),
          _buildMiniStat('${r.nbCoursesFutures}', 'futures\nignorées', Colors.white38),
        ]);
      }),

      // Ligne secondaire : sans résultat + erreurs
      if (r.nbSansResultat > 0 || r.nbCoursesEchouees > 0) ...[
        const SizedBox(height: 6),
        Row(children: [
          if (r.nbSansResultat > 0) ...[
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                ),
                child: Row(children: [
                  const Icon(Icons.schedule, color: Colors.orange, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${r.nbSansResultat} en attente PMU',
                      style: const TextStyle(color: Colors.orange, fontSize: 14),
                    ),
                  ),
                ]),
              ),
            ),
          ],
          if (r.nbSansResultat > 0 && r.nbCoursesEchouees > 0)
            const SizedBox(width: 6),
          if (r.nbCoursesEchouees > 0) ...[
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${r.nbCoursesEchouees} erreur(s) réseau',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ]),
      ],

      // Message explicatif si tout en attente
      if (toutEnAttente) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
          ),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('💡', style: TextStyle(fontSize: 15)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'L\'IA a récupéré les partants et calculé ses pronostics pour toutes les courses passées. '
                'Les résultats officiels PMU ne sont pas encore publiés. '
                'Relancez l\'analyse après 20h00 pour comparer et déclencher l\'apprentissage.',
                style: TextStyle(color: Colors.white60, fontSize: 15),
              ),
            ),
          ]),
        ),
      ],

      // ── Détail par course (liste scrollable) ─────────────────────────────
      if (r.coursesAnalysees.isNotEmpty) ...[
        const SizedBox(height: 10),
        _buildDetailCoursesLignes(r.coursesAnalysees),
      ],

      // Poids dominants si apprentissage effectif
      if (r.poidsApres.isNotEmpty && avecResultats) ...[
        const SizedBox(height: 8),
        _buildResumePoidsApres(r.poidsApres),
      ],
    ]);
  }

  /// Liste détaillée des courses avec icône colorée selon statut
  Widget _buildDetailCoursesLignes(List<String> lignes) {
    // Trier : ✓ d'abord, puis ⏳, puis 🔄, puis 🕐/🔁
    int _priorite(String l) {
      if (l.contains('✓'))  return 0;
      if (l.contains('⏳')) return 1;
      if (l.contains('🔄')) return 2;
      if (l.contains('🕐')) return 3;
      return 4;
    }
    final sorted = [...lignes]..sort((a, b) => _priorite(a).compareTo(_priorite(b)));

    Color _couleur(String l) {
      if (l.contains('✓'))  return const Color(0xFF4CAF7D);   // vert  → analysé
      if (l.contains('⏳')) return Colors.orange;              // orange → en attente PMU
      if (l.contains('🔄')) return Colors.blueAccent;         // bleu  → en cours
      if (l.contains('🕐')) return Colors.white38;            // gris  → à venir
      return Colors.white38;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(children: [
              const Icon(Icons.list_alt_rounded, color: Colors.white38, size: 16),
              const SizedBox(width: 6),
              Text(
                'Détail des ${sorted.length} course(s)',
                style: const TextStyle(color: Colors.white54, fontSize: 14,
                    fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              // Légende compacte
              _legendePuce(const Color(0xFF4CAF7D), 'Analysé'),
              const SizedBox(width: 8),
              _legendePuce(Colors.orange, 'En attente'),
              const SizedBox(width: 8),
              _legendePuce(Colors.white38, 'À venir'),
            ]),
          ),
          const Divider(height: 1, color: Colors.white10),
          // Lignes
          ...sorted.asMap().entries.map((entry) {
            final i    = entry.key;
            final line = entry.value;
            final col  = _couleur(line);
            // Séparer nom de course et statut entre crochets
            final bracketIdx = line.indexOf('[');
            final nom    = bracketIdx > 0 ? line.substring(0, bracketIdx).trim() : line;
            final statut = bracketIdx > 0
                ? line.substring(bracketIdx).replaceAll(RegExp(r'[\[\]]'), '').trim()
                : '';
            return Container(
              decoration: BoxDecoration(
                color: i.isEven
                    ? Colors.transparent
                    : Colors.white.withValues(alpha: 0.015),
                border: Border(
                  bottom: i < sorted.length - 1
                      ? BorderSide(color: Colors.white.withValues(alpha: 0.04))
                      : BorderSide.none,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(children: [
                // Pastille couleur statut
                Container(
                  width: 7, height: 7,
                  decoration: BoxDecoration(
                    color: col,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                // Nom de la course
                Expanded(
                  child: Text(
                    nom,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                // Statut coloré
                if (statut.isNotEmpty)
                  Text(
                    statut,
                    style: TextStyle(
                      color: col,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ]),
            );
          }),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _legendePuce(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 7, height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(color: color, fontSize: 16)),
    ],
  );

  Widget _buildMiniStat(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(children: [
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 22)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 16), textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  Widget _buildResumePoidsApres(Map<String, double> poids) {
    // ★ v5.0 : labels pour les 10 critères
    const labels = {
      'forme': 'Forme', 'gains': 'Gains', 'record': 'Record',
      'cote': 'Cote', 'constance': 'Régul.', 'victoires': 'Victoires',
      'discipline': 'Disc.', 'distSpec': 'DistSpec', 'jockey': 'Jockey', 'repos': 'Repos',
    };
    final sorted = poids.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top3 = sorted.take(3).toList();

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.trending_up, color: Colors.white38, size: 16),
          SizedBox(width: 6),
          Text('Poids dominants :', style: TextStyle(color: Colors.white54, fontSize: 14)),
        ]),
        ...top3.map((e) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _gold.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _gold.withValues(alpha: 0.3)),
          ),
          child: Text(
            '${labels[e.key] ?? e.key} ${(e.value * 100).toStringAsFixed(0)}%',
            style: const TextStyle(color: _gold, fontSize: 14, fontWeight: FontWeight.bold),
          ),
        )),
      ],
    );
  }

  // ── ★ v9.0 : Widget : Résultats par label IA ─────────────────────────────

  Widget _buildSectionStatsLabels() {
    final labels = IaMemoryService.instance.statsParLabel;

    // Ne montrer que les labels avec au moins 2 occurrences
    final actifs = labels.where((l) => l.nbTotal >= 2).toList();

    if (actifs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(children: [
          const Icon(Icons.label_outline, color: Colors.white30, size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '🏷️ Résultats par label — données insuffisantes\n(au moins 2 courses avec résultat nécessaires)',
              style: TextStyle(color: Colors.white38, fontSize: 16),
            ),
          ),
        ]),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        iaSectionTitle('🏷️ Résultats par label IA'),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _gold.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: actifs.asMap().entries.map((entry) {
              final i = entry.key;
              final stats = entry.value;
              return _buildLigneStatsLabel(stats, isLast: i == actifs.length - 1);
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildLigneStatsLabel(StatsParLabel stats, {bool isLast = false}) {
    final fiable = stats.estFiable;
    final tendance = stats.tendance7j;
    final tendanceStr = tendance == null ? ''
        : tendance > 5  ? ' ↑'
        : tendance < -5 ? ' ↓'
        : ' →';
    final tendanceColor = tendance == null ? Colors.white38
        : tendance > 5  ? _green
        : tendance < -5 ? Colors.redAccent
        : Colors.white54;

    return Container(
      decoration: BoxDecoration(
        border: isLast ? null : Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ligne 1 : label + tendance + badge fiabilité
          Row(children: [
            Text(stats.emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                stats.label,
                style: TextStyle(
                  color: fiable ? Colors.white : Colors.white54,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (tendance != null)
              Text(tendanceStr, style: TextStyle(color: tendanceColor, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: (fiable ? _green : Colors.orange).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: (fiable ? _green : Colors.orange).withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                '${stats.nbTotal} courses',
                style: TextStyle(
                  color: fiable ? _green : Colors.orange,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          // Ligne 2 : barres de progression top1/top3/top5
          Row(children: [
            _cellLabel('1er', stats.nbTop1, stats.nbTotal, _gold),
            const SizedBox(width: 8),
            _cellLabel('Top 3', stats.nbTop3, stats.nbTotal, _green),
            const SizedBox(width: 8),
            _cellLabel('Top 5', stats.nbTop5, stats.nbTotal, _purple),
            if (!fiable) ...[
              const SizedBox(width: 10),
              const Text('⚠️ Données insuffisantes', style: TextStyle(color: Colors.white30, fontSize: 16)),
            ],
          ]),
        ],
      ),
    );
  }

  Widget _cellLabel(String label, int nb, int total, Color color) {
    final pct = total > 0 ? nb / total : 0.0;
    final pctStr = '${(pct * 100).toStringAsFixed(0)}%';
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ligne 1 : libellé + pourcentage (renvoi à la ligne si besoin)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(color: Colors.white54, fontSize: 14)),
              Text(pctStr,
                  style: TextStyle(
                      color: color.withValues(alpha: 0.9),
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          // Ligne 2 : compteur nb/total
          Text('$nb/$total',
              style: TextStyle(color: color, fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(color.withValues(alpha: 0.8)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Widget : Stats par type de pari ──────────────────────────────────────

  Widget _buildSectionStatsTypesParis() {
    final statsTypes = IaMemoryService.instance.statsParType;

    if (statsTypes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(children: [
          iaSectionTitle('🎰 Vos paris réels — taux de réussite'),
          const SizedBox(height: 10),
          const Row(children: [
            Icon(Icons.info_outline, color: Colors.white24, size: 15),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Les stats apparaîtront dès que vous enregistrez une mise (€ > 0) sur une course.',
                style: TextStyle(color: Colors.white38, fontSize: 16),
              ),
            ),
          ]),
        ]),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        iaSectionTitle('🎰 Stats par type de pari'),
        const SizedBox(height: 6),
        // ★ v9.6 : distinguer paris manuels vs pronostics IA
        Row(children: [
          const Icon(Icons.info_outline_rounded, color: Colors.white24, size: 13),
          const SizedBox(width: 6),
          Expanded(child: Text.rich(TextSpan(children: [
            TextSpan(
              text: '${statsTypes.fold(0, (s, t) => s + t.nbJoues)} entrées totales ',
              style: const TextStyle(color: Colors.white38, fontSize: 16)),
            TextSpan(
              text: '(vos paris + pronostics IA)',
              style: const TextStyle(color: Colors.white24, fontSize: 16,
                  fontStyle: FontStyle.italic)),
          ]))),
        ]),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            children: [
              // En-tête du tableau
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: const [
                  SizedBox(width: 26),
                  Expanded(flex: 3, child: Text('Type de pari', style: TextStyle(color: Colors.white38, fontSize: 15, fontWeight: FontWeight.bold))),
                  SizedBox(width: 6),
                  SizedBox(width: 36, child: Text('Misés', style: TextStyle(color: Colors.white38, fontSize: 15), textAlign: TextAlign.center)),
                  SizedBox(width: 6),
                  SizedBox(width: 36, child: Text('Gagnés', style: TextStyle(color: Colors.white38, fontSize: 15), textAlign: TextAlign.center)),
                  SizedBox(width: 6),
                  SizedBox(width: 44, child: Text('Taux', style: TextStyle(color: Colors.white38, fontSize: 15), textAlign: TextAlign.center)),
                  SizedBox(width: 6),
                  // ★ v9.6 : colonne IA (pronostics auto)
                  SizedBox(width: 32, child: Text('IA', style: TextStyle(color: Color(0xFF90CAF9), fontSize: 15, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                  SizedBox(width: 6),
                  SizedBox(width: 52, child: Text('Gain net', style: TextStyle(color: Colors.white38, fontSize: 15), textAlign: TextAlign.right)),
                ]),
              ),
              const Divider(height: 1, color: Colors.white12),
              ...statsTypes.asMap().entries.map((entry) {
                final idx = entry.key;
                final st  = entry.value;
                final isLast = idx == statsTypes.length - 1;
                return _buildLigneTypePari(st, isLast: isLast);
              }),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Meilleur type de pari
        _buildMeilleurTypePari(statsTypes),
      ],
    );
  }

  Widget _buildLigneTypePari(StatsTypePari st, {bool isLast = false}) {
    final taux = st.tauxReussite;
    final hasData = st.nbGagnes + st.nbPerdus > 0;
    final tauxColor = !hasData ? Colors.white24
        : taux >= 50 ? _green
        : taux >= 30 ? const Color(0xFFFFB74D)
        : const Color(0xFFEF5350);
    final gainColor = st.gainNet >= 0 ? _green : const Color(0xFFEF5350);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(children: [
          Text(st.emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(st.typePari, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
              if (st.nbEnAttente > 0)
                Text('${st.nbEnAttente} en attente', style: const TextStyle(color: Colors.white24, fontSize: 15)),
            ]),
          ),
          const SizedBox(width: 6),
          // Nb joués
          SizedBox(width: 36, child: Text('${st.nbJoues}', style: const TextStyle(color: Colors.white60, fontSize: 16), textAlign: TextAlign.center)),
          const SizedBox(width: 6),
          // Nb gagnés
          SizedBox(width: 36, child: Text('${st.nbGagnes}', style: TextStyle(color: st.nbGagnes > 0 ? _green : Colors.white38, fontSize: 16, fontWeight: st.nbGagnes > 0 ? FontWeight.bold : FontWeight.normal), textAlign: TextAlign.center)),
          const SizedBox(width: 6),
          // Taux
          SizedBox(
            width: 44,
            child: hasData
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: tauxColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: tauxColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      '${taux.toStringAsFixed(0)}%',
                      style: TextStyle(color: tauxColor, fontSize: 15, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  )
                : const Text('—', style: TextStyle(color: Colors.white24, fontSize: 16), textAlign: TextAlign.center),
          ),
          const SizedBox(width: 6),
          // ★ v9.6 : Nb pronostics IA (nbEnAttente = paris IA sans mise réelle)
          SizedBox(
            width: 32,
            child: st.nbEnAttente > 0
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2A4A),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: const Color(0xFF90CAF9).withValues(alpha: 0.4)),
                    ),
                    child: Text('${st.nbEnAttente}',
                      style: const TextStyle(color: Color(0xFF90CAF9), fontSize: 16,
                          fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center),
                  )
                : const Text('—', style: TextStyle(color: Colors.white12, fontSize: 16),
                    textAlign: TextAlign.center),
          ),
          const SizedBox(width: 6),
          // Gain net
          SizedBox(
            width: 52,
            child: Text(
              st.gainNet == 0 ? '—'
                  : '${st.gainNet >= 0 ? '+' : ''}${fmtEuros(st.gainNet)}€',
              style: TextStyle(color: st.gainNet == 0 ? Colors.white24 : gainColor, fontSize: 15, fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
          ),
        ]),
      ),
      if (!isLast) Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
    ]);
  }

  Widget _buildMeilleurTypePari(List<StatsTypePari> stats) {
    // Filtrer seulement ceux avec au moins 3 paris résolus
    final resolus = stats.where((s) => s.nbGagnes + s.nbPerdus >= 3).toList();
    if (resolus.isEmpty) return const SizedBox();

    // Meilleur taux
    final meilleur = resolus.reduce((a, b) => a.tauxReussite >= b.tauxReussite ? a : b);
    // Plus rentable (gain net max)
    final rentable = resolus.reduce((a, b) => a.gainNet >= b.gainNet ? a : b);

    return Row(children: [
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _green.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _green.withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            const Text('🏆', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Meilleur taux', style: TextStyle(color: Colors.white38, fontSize: 15)),
              Text('${meilleur.typePari} — ${meilleur.tauxReussite.toStringAsFixed(0)}%',
                  style: const TextStyle(color: _green, fontSize: 16, fontWeight: FontWeight.bold)),
            ])),
          ]),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _gold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _gold.withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            const Text('💰', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Plus rentable', style: TextStyle(color: Colors.white38, fontSize: 15)),
              Text(
                '${rentable.typePari} — ${rentable.gainNet >= 0 ? '+' : ''}${fmtEuros(rentable.gainNet)}€',
                style: TextStyle(color: rentable.gainNet >= 0 ? _gold : Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ])),
          ]),
        ),
      ),
    ]);
  }

  // ── Widget : Précision IA — 3 niveaux réels ──────────────────────────────
  //
  //  Affiche les 3 niveaux de précision IA calculés sur les vrais résultats PMU :
  //   • 🥇 Gagnant   : favori IA arrivé 1er       → signal pour Simple Gagnant
  //   • 🏅 Placé     : favori IA dans le top 3     → signal pour Couplé / Tiercé
  //   • 🎯 Sélectif  : ≥ 4 des 5 premiers IA dans le top 5 réel → signal pour Quinté+ // ★ v10.15
  //
  //  Chaque niveau alimente un ajustement complémentaire des poids IA.
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSectionPrecisionIA() {
    final prList = IaMemoryService.instance.precisionParType;
    final seuils = IaMemoryService.instance.seuilsConfiance;
    final poidsIdx = IaMemoryService.instance.poidsIndices;
    final hasData = prList.any((p) => p.nbTotal >= 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        iaSectionTitle('🎯 Précision IA — Synthèse des 3 Indices'),
        const SizedBox(height: 6),

        // ── Encart : les 3 indices et leurs poids actuels ───────────────────
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_purple.withValues(alpha: 0.12), _card],
              begin: Alignment.topLeft,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _purple.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Text('📐', style: TextStyle(fontSize: 15)),
                SizedBox(width: 6),
                Text('PrécisionIA = Indice 1 + Indice 2 + Indice 3',
                    style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 10),
              _buildIndiceRow(
                emoji: '📊',
                label: 'Indice 1 — Score multicritères',
                soustitre: '10 critères pondérés classent les chevaux',
                poids: poidsIdx.poidsCriteres,
                couleur: const Color(0xFF42A5F5),
              ),
              const SizedBox(height: 6),
              _buildIndiceRow(
                emoji: '🔮',
                label: 'Indice 2 — Confiance IA',
                soustitre: 'Variance des scores + domination du favori',
                poids: poidsIdx.poidsConfiance,
                couleur: const Color(0xFFAB47BC),
              ),
              const SizedBox(height: 6),
              _buildIndiceRow(
                emoji: '🏆',
                label: 'Indice 3 — Taux de Réussite',
                soustitre: 'Conseils IA corrects / total par type de pari',
                poids: poidsIdx.poidsReussite,
                couleur: _green,
              ),
              const SizedBox(height: 8),
              const Text(
                '💡 Les poids s\'ajustent automatiquement : l\'indice le plus prédictif gagne en influence.',
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // Note explicative Taux de Réussite
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: _green.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _green.withValues(alpha: 0.2)),
          ),
          child: Row(children: const [
            Icon(Icons.emoji_events_outlined, color: Color(0xFF66BB6A), size: 14),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                "🏆 Précision IA (30j glissants) : sur X courses conseillées Quinté+, combien l'IA avait-elle raison selon PMU ?\n"
                "Ex : 3 bons sur 5 Quinté+ = 60% de précision. ⚠️ Ces chiffres concernent les CONSEILS IA, pas vos paris.",
                // NB : le tableau 🎰 Taux de réussite par type (plus bas) concerne VOS paris enregistrés.
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),

        // ── Sélecteur de période ────────────────────────────────────────────
        if (prList.isNotEmpty) _buildFiltrePeriode(prList),

        const SizedBox(height: 10),

        if (!hasData)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(children: const [
              Icon(Icons.analytics_outlined, color: Colors.white24, size: 15),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "La précision s'affichera après la première analyse de la journée "
                  '(résultats PMU disponibles le soir).',
                  style: TextStyle(color: Colors.white38, fontSize: 14),
                ),
              ),
            ]),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(children: [
              // En-tête du tableau
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  Expanded(flex: 3, child: Text(
                    () {
                      const moisT = ['','Jan','Fév','Mar','Avr','Mai','Juin','Juil','Aoû','Sep','Oct','Nov','Déc'];
                      final nowT  = DateTime.now();
                      if (_filtrePeriode == null)       return '🏆 Précision IA — 60j glissants';
                      if (_filtrePeriode == 'all')      return '🏆 Précision IA — Depuis installation';
                      if (_filtrePeriode == '7j')       return '🏆 Précision IA — 7 derniers jours';
                      if (_filtrePeriode == 'today')    return "🏆 Précision IA — Aujourd'hui ${nowT.day} ${moisT[nowT.month]}";
                      if (_filtrePeriode == 'custom')   return '🏆 Précision IA — Période personnalisée';
                      return '🏆 Précision IA — ${_libelleFiltre(_filtrePeriode!)}';
                    }(),
                    style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
                  )),
                  const SizedBox(width: 4),
                  const SizedBox(width: 54, child: Text('Bons/Total', style: TextStyle(color: Colors.white38, fontSize: 16), textAlign: TextAlign.center)),
                  const SizedBox(width: 4),
                  const SizedBox(width: 46, child: Text('Taux', style: TextStyle(color: Colors.white38, fontSize: 16), textAlign: TextAlign.center)),
                  const SizedBox(width: 4),
                  const SizedBox(width: 24, child: Text('7j', style: TextStyle(color: Colors.white38, fontSize: 16), textAlign: TextAlign.center)),
                  const SizedBox(width: 14),
                ]),
              ),
              const Divider(height: 1, color: Colors.white12),
              // Lignes par type de pari
              ...prList.asMap().entries.map((entry) {
                final i = entry.key;
                final p = entry.value;
                return _buildLignePrecisionParType(p, isLast: i == prList.length - 1);
              }),
            ]),
          ),

        if (hasData) ...[
          const SizedBox(height: 10),
          // Section seuils adaptatifs courants
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Text('⚙️', style: TextStyle(fontSize: 14)),
                  SizedBox(width: 6),
                  Text('Seuils de confiance actuels (adaptatifs)',
                      style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 8),
                const Text(
                  'Ces seuils évoluent selon la précision réelle — '
                  "l'IA devient plus ou moins sélective par type de pari.",
                  style: TextStyle(color: Colors.white38, fontSize: 14),
                ),
                const SizedBox(height: 8),
                _buildLigneSeuilAdaptatif('🥇 Simple Gagnant',  seuils.seuilSimpleGagnant,  80.0),
                _buildLigneSeuilAdaptatif('🎖️ Gagnant+Placé',   seuils.seuilGagnantPlace,   50.0),
                _buildLigneSeuilAdaptatif('🏅 Simple Placé',    seuils.seuilSimplePlace,    65.0),
                _buildLigneSeuilAdaptatif('🔗 Couplé Gagnant',  seuils.seuilCoupleGagnant,  75.0),
                _buildLigneSeuilAdaptatif('🔀 Couplé Placé',    seuils.seuilCouplePlace,    60.0),
                _buildLigneSeuilAdaptatif('🎯 Tiercé',          seuils.seuilTierce,         35.0),
                _buildLigneSeuilAdaptatif('4️⃣ Quarté+',          seuils.seuilQuarte,         80.0),
                _buildLigneSeuilAdaptatif('⭐ Quinté+',          seuils.seuilQuinte,          0.0),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "💡 Après chaque analyse de la journée, les 3 indices et les poids IA s'ajustent automatiquement.",
            style: TextStyle(color: Colors.white24, fontSize: 14),
          ),
        ],
      ],
    );
  }

  // ── ★ v9.87 : Section précision par hippodrome ─────────────────────────────
  Widget _buildSectionHippodrome() {
    final data = IaMemoryService.instance.precisionParHippodromeAvecFiabilite;
    if (data.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          iaSectionTitle('📍 Précision IA par hippodrome'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: const Text(
              'Pas encore assez de données.\nAnalysez plus de courses pour voir votre précision par hippodrome.',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ),
        ],
      );
    }

    // Séparer fiables / insuffisants
    final fiables = data.entries
        .where((e) => e.value['fiable'] == true)
        .toList()
      ..sort((a, b) =>
          (b.value['taux'] as double).compareTo(a.value['taux'] as double));
    final insuffisants = data.entries
        .where((e) => e.value['fiable'] == false)
        .toList()
      ..sort((a, b) =>
          (b.value['nb'] as int).compareTo(a.value['nb'] as int));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        iaSectionTitle('📍 Précision IA par hippodrome'),
        const SizedBox(height: 8),

        // Hippodromes fiables (≥5 courses)
        if (fiables.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: const Text(
              'Pas encore 5 courses sur un même hippodrome.',
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              children: fiables.asMap().entries.map((entry) {
                final i    = entry.key;
                final e    = entry.value;
                final taux = (e.value['taux'] as double);
                final nb   = (e.value['nb'] as int);
                final pct  = (taux * 100).round();
                final color = taux >= 0.65
                    ? const Color(0xFF4CAF7D)
                    : taux >= 0.40
                        ? const Color(0xFFFFB74D)
                        : const Color(0xFFEF5350);
                final isLast = i == fiables.length - 1;
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      child: Row(
                        children: [
                          // Pastille couleur
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Nom hippodrome
                          Expanded(
                            child: Text(
                              e.key,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14),
                            ),
                          ),
                          // Barre de progression
                          SizedBox(
                            width: 70,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: taux,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.08),
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(color),
                                minHeight: 5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Pourcentage
                          SizedBox(
                            width: 36,
                            child: Text(
                              '$pct%',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: color,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Nb courses
                          Text(
                            '($nb)',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                    if (!isLast)
                      const Divider(height: 1, color: Colors.white10),
                  ],
                );
              }).toList(),
            ),
          ),

        // Hippodromes insuffisants — ExpansionTile collapsé
        if (insuffisants.isNotEmpty) ...[
          const SizedBox(height: 8),
          Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
            ),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 12),
              title: Text(
                '${insuffisants.length} hippodrome(s) — données insuffisantes (<5 courses)',
                style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                    fontStyle: FontStyle.italic),
              ),
              iconColor: Colors.white38,
              collapsedIconColor: Colors.white38,
              backgroundColor: _card.withValues(alpha: 0.5),
              collapsedBackgroundColor: _card.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Colors.white12)),
              collapsedShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Colors.white12)),
              children: insuffisants.map((e) {
                final nb  = (e.value['nb'] as int);
                final pct = ((e.value['taux'] as double) * 100).round();
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 5),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.white24,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(e.key,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 14)),
                      ),
                      Text(
                        '$pct% ($nb/5 courses)',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 16),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  /// Ligne affichant un indice de PrécisionIA avec son poids actuel et une barre de progression
  Widget _buildIndiceRow({
    required String emoji,
    required String label,
    required String soustitre,
    required double poids, // 0.0 à 1.0
    required Color couleur,
  }) {
    final pct = (poids * 100).round();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(label,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: couleur.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: couleur.withValues(alpha: 0.4)),
                  ),
                  child: Text('$pct%',
                      style: TextStyle(color: couleur, fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ]),
              const SizedBox(height: 3),
              Text(soustitre, style: const TextStyle(color: Colors.white38, fontSize: 14)),
              const SizedBox(height: 4),
              // Barre de progression du poids
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: poids.clamp(0.15, 0.55) / 0.55,
                  backgroundColor: Colors.white10,
                  valueColor: AlwaysStoppedAnimation<Color>(couleur.withValues(alpha: 0.7)),
                  minHeight: 4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Dialogue détail par type de pari ─────────────────────────────────────
  void _afficherDetailParType(StatsPrecisionParType p) {
    showDialog(
      context: context,
      builder: (ctx) => IaDialogDetailTypePari(
        stats: p,
        filtreInitial: _filtrePeriode,
        filtreDebutInitial: _filtreDebut,
        filtreFinInitial: _filtreFin,
        buildCarte: _buildCartePronostic,
        chipStat: _chipStat,
        green: _green,
      ),
    );
  }

  /// Liste scrollable de pronostics avec carte détaillée (conservée pour extension future)
  // ignore: unused_element
  Widget _buildListePronostics(List<IaPronostic> liste, String typePari,
      {required String emptyMsg}) {
    if (liste.isEmpty) {
      return Center(child: Text(emptyMsg,
          style: const TextStyle(color: Colors.white38, fontSize: 16),
          textAlign: TextAlign.center));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      itemCount: liste.length,
      itemBuilder: (_, i) => _buildCartePronostic(liste[i], typePari),
    );
  }

  /// Carte détaillée d'un pronostic IA
  Widget _buildCartePronostic(IaPronostic pr, String typePari) {
    final resolu     = pr.resultatsReels;
    final bonConseil = resolu && IaMemoryService.instance.estBonConseil(pr, typePari);
    final enAttente  = !resolu;

    final Color borderColor;
    final String icone;
    if (enAttente)       { borderColor = const Color(0xFFFFB74D); icone = '⏳'; }
    else if (bonConseil) { borderColor = _green;                  icone = '✅'; }
    else                 { borderColor = const Color(0xFFEF5350); icone = '❌'; }

    final d       = pr.datePronostic;
    final dateStr = '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
    final heureStr= '${d.hour.toString().padLeft(2,'0')}h${d.minute.toString().padLeft(2,'0')}';

    // Top N chevaux conseillés par l'IA (jusqu'à 5)
    final topIA = pr.topNIA;
    final nbAfficher = typePari == 'Quinté+' ? 5
        : typePari == 'Quarté+' ? 4
        : (typePari == 'Tiercé') ? 3
        : (typePari.contains('Couplé')) ? 2 : 1;
    final chevauxStr = topIA.take(nbAfficher).join(' - ');

    // Arrivée réelle PMU
    String arriveeStr = '';
    if (resolu && pr.arriveeReelle != null && pr.arriveeReelle!.isNotEmpty) {
      arriveeStr = pr.arriveeReelle!.take(nbAfficher + 2).join(' - ');
    }

    // Score confiance
    final conf = pr.confiancePredite;
    final confStr = conf != null ? '${conf.toStringAsFixed(0)} pts' : '—';

    // Rang favori + top3/top5
    String perf = '';
    if (resolu) {
      final rang = pr.rangFavoriIaDansArrivee;
      final top3 = pr.nbTop3DansArriveeReelle ?? 0;
      final top5 = pr.nbTop5DansArriveeReelle ?? 0;
      if (rang != null) {
        perf = rang == 1 ? '🥇 1er' : rang <= 3 ? '🏅 ${rang}e' : '${rang}e';
      }
      if (top3 > 0 || top5 > 0) perf += '  top3:$top3  top5:$top5';
    }

    // Ordre / Désordre
    String ordreLabel = '';
    if (resolu && bonConseil) {
      if (typePari == 'Tiercé' || typePari == 'Quarté+' || typePari == 'Quinté+') {
        final estOrdre = _verifierOrdreLocal(pr, typePari);
        if (estOrdre == true)       ordreLabel = '🎯 ORDRE';
        else if (estOrdre == false) ordreLabel = '🔀 DÉSORDRE';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: borderColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Ligne 1 : icone + nom course + date ───────────────────
          Row(children: [
            Text(icone, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(child: Text(pr.nomCourse,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis)),
            Text(dateStr, style: const TextStyle(color: Colors.white54, fontSize: 16)),
          ]),
          const SizedBox(height: 4),
          // ── Ligne 2 : hippodrome + heure + discipline ─────────────
          Row(children: [
            const SizedBox(width: 24),
            Text('📍 ${pr.hippodrome}  •  $heureStr  •  ${pr.discipline}',
                style: const TextStyle(color: Colors.white38, fontSize: 16)),
          ]),
          const SizedBox(height: 6),
          // ── Ligne 3 : chevaux conseillés IA ───────────────────────
          Row(children: [
            const SizedBox(width: 24),
            const Text('🤖 IA : ', style: TextStyle(color: Colors.white54, fontSize: 16)),
            Text(chevauxStr.isNotEmpty ? chevauxStr : '—',
                style: TextStyle(color: borderColor, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Text('($confStr)', style: const TextStyle(color: Colors.white38, fontSize: 16)),
          ]),
          // ── Ligne 4 : arrivée réelle PMU (si résolu) ──────────────
          if (resolu && arriveeStr.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(children: [
              const SizedBox(width: 24),
              const Text('🏁 PMU : ', style: TextStyle(color: Colors.white54, fontSize: 16)),
              Text(arriveeStr,
                  style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
            ]),
          ],
          // ── Ligne 5 : performance + ordre/désordre ─────────────────
          if (perf.isNotEmpty || ordreLabel.isNotEmpty) ...[
            const SizedBox(height: 5),
            Row(children: [
              const SizedBox(width: 24),
              if (perf.isNotEmpty)
                Text(perf, style: TextStyle(
                    color: bonConseil ? _green : Colors.white38,
                    fontSize: 16, fontWeight: FontWeight.w600)),
              if (ordreLabel.isNotEmpty) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: (ordreLabel.contains('ORDRE') && !ordreLabel.contains('DES'))
                        ? const Color(0xFF66BB6A).withValues(alpha: 0.15)
                        : const Color(0xFFFFB74D).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: (ordreLabel.contains('ORDRE') && !ordreLabel.contains('DES'))
                          ? const Color(0xFF66BB6A).withValues(alpha: 0.5)
                          : const Color(0xFFFFB74D).withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(ordreLabel,
                      style: TextStyle(
                          color: (ordreLabel.contains('ORDRE') && !ordreLabel.contains('DES'))
                              ? const Color(0xFF66BB6A)
                              : const Color(0xFFFFB74D),
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ]),
          ],
        ]),
      ),
    );
  }

  /// Vérifie ordre/désordre directement depuis IaPronostic (sans appel service)
  bool? _verifierOrdreLocal(IaPronostic pr, String typePari) {
    final arrivee = pr.arriveeReelle;
    if (arrivee == null || arrivee.isEmpty) return null;
    final topIA = pr.topNIA.map((e) => int.tryParse(e)).whereType<int>().toList();
    switch (typePari) {
      case 'Tiercé':
        if (topIA.length < 3 || arrivee.length < 3) return null;
        if (topIA[0]==arrivee[0] && topIA[1]==arrivee[1] && topIA[2]==arrivee[2]) return true;
        final ok = topIA.take(3).toSet().intersection(arrivee.take(3).toSet()).length >= 3;
        return ok ? false : null;
      case 'Quarté+':
        if (topIA.length < 4 || arrivee.length < 4) return null;
        if (topIA[0]==arrivee[0] && topIA[1]==arrivee[1] &&
            topIA[2]==arrivee[2] && topIA[3]==arrivee[3]) return true;
        final ok = topIA.take(4).toSet().intersection(arrivee.take(4).toSet()).length >= 3;
        return ok ? false : null;
      case 'Quinté+':
        if (topIA.length < 5 || arrivee.length < 5) return null;
        if (topIA[0]==arrivee[0] && topIA[1]==arrivee[1] && topIA[2]==arrivee[2] &&
            topIA[3]==arrivee[3] && topIA[4]==arrivee[4]) return true;
        final ok = topIA.take(5).toSet().intersection(arrivee.take(5).toSet()).length >= 3;
        return ok ? false : null;
      default: return null;
    }
  }

  Widget _chipStat(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(label,
            style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
      );

  /// ── v9.53 : ligne de détail utilisée dans le dialogue par type ──────────
  // _buildDetailRow supprimé en v9.55 : remplacé par _buildDetailRowIA
  // (source = IaPronostic au lieu de TrackedCourse — section Précision IA)

  Widget _buildLignePrecisionParType(StatsPrecisionParType p, {required bool isLast}) {
    final double seuilBon;
    final double seuilMoyen;
    switch (p.typePari) {
      case 'Simple Gagnant':   seuilBon = 30; seuilMoyen = 20; break;
      case 'Gagnant+Placé':    seuilBon = 35; seuilMoyen = 25; break;
      case 'Simple Placé':     seuilBon = 50; seuilMoyen = 35; break;
      case 'Couplé Gagnant':   seuilBon = 35; seuilMoyen = 25; break;
      case 'Couplé Placé':     seuilBon = 45; seuilMoyen = 30; break;
      case 'Tiercé':           seuilBon = 40; seuilMoyen = 25; break;
      case 'Quarté+':          seuilBon = 35; seuilMoyen = 22; break;
      case 'Quinté+':          seuilBon = 30; seuilMoyen = 18; break;
      default:                  seuilBon = 40; seuilMoyen = 25;
    }

    // ── Stats selon le filtre actif ─────────────────────────────────────────
    final stats   = _statsFiltre(p);
    final nb      = stats['nb']       ?? 0;
    final bons    = stats['bons']     ?? 0;
    final ordreF  = stats['ordre']    ?? 0;
    final desordF = stats['desordre'] ?? 0;

    final taux      = nb > 0 ? bons / nb * 100.0 : 0.0;
    final tauxColor = taux >= seuilBon   ? _green
        : taux >= seuilMoyen ? const Color(0xFFFFB74D)
        : nb > 0 ? const Color(0xFFEF5350) : Colors.white24;

    final tendance = p.tendance7j;
    String tendTxt = '→';
    Color tendColor = Colors.white38;
    if (tendance != null) {
      if (tendance > 2)       { tendTxt = '↑'; tendColor = _green; }
      else if (tendance < -2) { tendTxt = '↓'; tendColor = const Color(0xFFEF5350); }
    }

    final hasOrdreDesordre = (p.typePari == 'Tiercé' || p.typePari == 'Quarté+' || p.typePari == 'Quinté+')
        && (ordreF > 0 || desordF > 0);

    return Column(children: [
      GestureDetector(
        onTap: nb > 0 ? () => _afficherDetailParType(p) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Ligne principale ─────────────────────────────────────────
              Row(children: [
                Text(p.emoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(p.typePari,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                // Bons / Total selon filtre
                _cellStat('$bons/$nb',
                    bons > 0 ? _green : Colors.white38,
                    width: 54, bold: bons > 0),
                const SizedBox(width: 6),
                // Taux
                SizedBox(
                  width: 46,
                  child: nb > 0
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: tauxColor.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: tauxColor.withValues(alpha: 0.4)),
                          ),
                          child: Text('${taux.toStringAsFixed(0)}%',
                              style: TextStyle(color: tauxColor, fontSize: 16, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center),
                        )
                      : const SizedBox(),
                ),
                const SizedBox(width: 4),
                // Tendance 7j (toujours basée sur historique récent)
                SizedBox(width: 20,
                    child: Text(tendTxt,
                        style: TextStyle(color: tendColor, fontSize: 14, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center)),
                if (nb > 0)
                  const Icon(Icons.chevron_right, color: Colors.white24, size: 14),
              ]),
              // ── Sous-ligne Ordre / Désordre ──────────────────────────────
              if (hasOrdreDesordre)
                Padding(
                  padding: const EdgeInsets.only(left: 22, top: 4, bottom: 2),
                  child: Row(children: [
                    _badgeOrdre('🎯 Ordre', ordreF, const Color(0xFF66BB6A)),
                    const SizedBox(width: 8),
                    _badgeOrdre('🔀 Désordre', desordF, const Color(0xFFFFB74D)),
                    const SizedBox(width: 8),
                    if (bons > 0)
                      Text(
                        '(${ordreF + desordF}/$bons classés)',
                        style: const TextStyle(color: Colors.white24, fontSize: 16),
                      ),
                  ]),
                ),
            ],
          ),
        ),
      ),
      if (!isLast) const Divider(height: 1, color: Colors.white12, indent: 14, endIndent: 14),
    ]);
  }

  Widget _cellStat(String txt, Color color, {double width = 40, bool bold = false}) =>
      SizedBox(
        width: width,
        child: Text(txt,
            style: TextStyle(color: color, fontSize: 14,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal),
            textAlign: TextAlign.center),
      );

  Widget _badgeOrdre(String label, int count, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text('$label : $count',
            style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
      );

  // ── Sélecteur de période pour le tableau Précision IA ────────────────────
  // 5 boutons fixes : Tout | 60j IA | 7 jrs | Date du jour (dynamique) | Période
  Widget _buildFiltrePeriode(List<StatsPrecisionParType> prList) {
    final now = DateTime.now();
    // Jours en français
    const joursF = ['','Lun','Mar','Mer','Jeu','Ven','Sam','Dim'];
    const moisF  = ['','Jan','Fév','Mar','Avr','Mai','Juin','Juil','Aoû','Sep','Oct','Nov','Déc'];
    // Date du jour affichée en temps réel en français : ex « Mer 29 Avr »
    final jourSemaine = joursF[now.weekday];
    final libAuj = '$jourSemaine ${now.day} ${moisF[now.month]}';
    final libPeriode = (_filtrePeriode == 'custom' && _filtreDebut != null && _filtreFin != null)
        ? '${_filtreDebut!.day.toString().padLeft(2,'0')}/${_filtreDebut!.month.toString().padLeft(2,'0')}'
          ' → ${_filtreFin!.day.toString().padLeft(2,'0')}/${_filtreFin!.month.toString().padLeft(2,'0')}'
        : 'Période';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ★ v9.93 : Wrap sur 2 lignes — plus intuitif que le scroll horizontal
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _boutonFiltre('Tout',    'all',   icone: Icons.all_inclusive),
            _boutonFiltre('60j IA',  null,    icone: Icons.psychology),
            _boutonFiltre('7 jrs',   '7j',    icone: Icons.date_range),
            _boutonFiltre(libAuj,    'today', icone: Icons.today),
            // Bouton Période — ouvre le sélecteur de dates
            GestureDetector(
              onTap: () => _choisirPeriodePersonnalisee(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: _filtrePeriode == 'custom'
                      ? _purple.withValues(alpha: 0.22)
                      : const Color(0xFFFFD700).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _filtrePeriode == 'custom'
                        ? _purple
                        : const Color(0xFFFFD700),
                    width: _filtrePeriode == 'custom' ? 1.8 : 1.3,
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.calendar_month,
                      size: 12,
                      color: _filtrePeriode == 'custom'
                          ? _purple
                          : const Color(0xFFFFD700)),
                  const SizedBox(width: 4),
                  Text(libPeriode,
                      style: TextStyle(
                        color: _filtrePeriode == 'custom'
                            ? _purple
                            : const Color(0xFFFFD700),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      )),
                ]),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _buildResumePeriode(prList),
      ],
    );
  }

  // ── Bouton filtre : vert si sélectionné, jaune si non sélectionné — plus grand ─
  Widget _boutonFiltre(String label, String? valeur, {IconData? icone}) {
    final actif = _filtrePeriode == valeur;
    const vertActif    = Color(0xFF4CAF7D);
    const jauneInactif = Color(0xFFFFD700);
    return GestureDetector(
      onTap: () => setState(() => _filtrePeriode = valeur),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: actif
              ? vertActif.withValues(alpha: 0.22)
              : jauneInactif.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: actif ? vertActif : jauneInactif,
            width: actif ? 2.0 : 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icone != null) ...[
              Icon(icone, size: 14,
                  color: actif ? vertActif : jauneInactif),
              const SizedBox(width: 5),
            ],
            Text(label,
                style: TextStyle(
                  color: actif ? vertActif : jauneInactif,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                )),
          ],
        ),
      ),
    );
  }

  /// Résumé global toutes périodes confondues — total conseilsIA / bons
  Widget _buildResumePeriode(List<StatsPrecisionParType> prList) {
    int totalNb = 0, totalBons = 0;
    for (final p in prList) {
      final stats = _statsFiltre(p);
      totalNb   += stats['nb']   ?? 0;
      totalBons += stats['bons'] ?? 0;
    }
    if (totalNb == 0) return const SizedBox();
    final taux = totalNb > 0 ? totalBons / totalNb * 100 : 0.0;
    const moisR = ['','Jan','Fév','Mar','Avr','Mai','Juin','Juil','Aoû','Sep','Oct','Nov','Déc'];
    final now2  = DateTime.now();
    final label = _filtrePeriode == null
        ? '60j glissants'
        : _filtrePeriode == 'all'
            ? 'Depuis installation'
            : _filtrePeriode == '7j'
                ? '7 derniers jours'
                : _filtrePeriode == 'today'
                    ? "Aujourd'hui ${now2.day} ${moisR[now2.month]}"
                    : _filtrePeriode == 'custom'
                        ? 'Période personnalisée'
                        : _libelleFiltre(_filtrePeriode!);
    return Row(children: [
      const Icon(Icons.bar_chart, color: Colors.white38, size: 13),
      const SizedBox(width: 5),
      Text('$label : $totalBons/$totalNb conseils bons — ${taux.toStringAsFixed(0)}% tous types',
          style: const TextStyle(color: Colors.white38, fontSize: 14)),
    ]);
  }

  /// Retourne les stats selon le filtre actif pour un StatsPrecisionParType
  Map<String, int> _statsFiltre(StatsPrecisionParType p) {
    if (_filtrePeriode == null) {
      // 60j glissants (défaut)
      return {'nb': p.nbTotal, 'bons': p.nbBons, 'ordre': p.nbOrdre, 'desordre': p.nbDesordre};
    } else if (_filtrePeriode == 'all') {
      // Tout depuis l'installation
      return {'nb': p.nbTotalAll, 'bons': p.nbBonsAll, 'ordre': p.nbOrdreAll, 'desordre': p.nbDesordreAll};
    } else if (_filtrePeriode == '7j') {
      // 7 derniers jours glissants
      final fin   = DateTime.now();
      final debut = fin.subtract(const Duration(days: 7));
      return p.statsPourPeriode(debut, fin);
    } else if (_filtrePeriode == 'today') {
      // ★ v9.99 : Aujourd'hui — lecture directe depuis _pronostics (source temps réel)
      // statsPourPeriode() lisait historiqueComplet, mis à jour seulement après
      // analyseJourneeComplete() → affichait 0/0 toute la journée.
      // precisionAujourdhuiDepuisPronostics calcule en temps réel depuis les pronostics bruts.
      final aujodhui = IaMemoryService.instance.precisionAujourdhuiDepuisPronostics;
      return aujodhui[p.typePari] ?? {'nb': 0, 'bons': 0, 'ordre': 0, 'desordre': 0};
    } else if (_filtrePeriode == 'custom' && _filtreDebut != null && _filtreFin != null) {
      // Période personnalisée date à date
      return p.statsPourPeriode(_filtreDebut!, _filtreFin!);
    }
    return {'nb': p.nbTotal, 'bons': p.nbBons, 'ordre': p.nbOrdre, 'desordre': p.nbDesordre};
  }

  /// Libellé court d'un jour 'YYYY-MM-DD' → '26 Avr'
  String _libelleJour(String yyyyMMdd) {
    if (yyyyMMdd.length != 10) return yyyyMMdd;
    final parts = yyyyMMdd.split('-');
    const moisCourts = ['','Jan','Fév','Mar','Avr','Mai','Juin','Juil','Aoû','Sep','Oct','Nov','Déc'];
    final m = int.tryParse(parts[1]) ?? 0;
    final d = int.tryParse(parts[2]) ?? 0;
    return '$d ${m < moisCourts.length ? moisCourts[m] : parts[1]}';
  }

  /// Libellé du filtre actif (pour le résumé sous les boutons)
  String _libelleFiltre(String filtre) {
    if (filtre.length == 10) return _libelleJour(filtre);   // jour
    if (filtre.length == 7)  return _libelleMois(filtre);   // mois (rétrocompat)
    return filtre;
  }

  String _libelleMois(String yyyyMM) {
    if (yyyyMM.length < 7) return yyyyMM;
    final parts  = yyyyMM.split('-');
    const mois   = ['','Jan','Fév','Mar','Avr','Mai','Juin','Juil','Aoû','Sep','Oct','Nov','Déc'];
    final m      = int.tryParse(parts[1]) ?? 0;
    final y      = parts[0].substring(2);
    return '${m < mois.length ? mois[m] : parts[1]} $y';
  }

  Future<void> _choisirPeriodePersonnalisee() async {
    final now   = DateTime.now();
    final debut = await showDatePicker(
      context: context,
      initialDate: _filtreDebut ?? now,          // ★ date initiale = aujourd'hui
      firstDate: DateTime(2024),
      lastDate: now,
      helpText: 'DATE DE DÉBUT',
      confirmText: 'VALIDER',
      cancelText: 'ANNULER',
      fieldLabelText: 'Entrez la date',
      fieldHintText: 'jj/mm/aaaa',
      errorFormatText: 'Format invalide',
      errorInvalidText: 'Date invalide',
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: Color(0xFF4CAF7D)),
        ),
        child: child!,
      ),
    );
    if (debut == null || !mounted) return;
    final fin = await showDatePicker(
      context: context,
      initialDate: _filtreFin ?? now,            // ★ date initiale = aujourd'hui
      firstDate: debut,
      lastDate: now,
      helpText: 'DATE DE FIN',
      confirmText: 'VALIDER',
      cancelText: 'ANNULER',
      fieldLabelText: 'Entrez la date',
      fieldHintText: 'jj/mm/aaaa',
      errorFormatText: 'Format invalide',
      errorInvalidText: 'Date invalide',
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: Color(0xFF4CAF7D)),
        ),
        child: child!,
      ),
    );
    if (fin == null || !mounted) return;
    setState(() {
      _filtrePeriode = 'custom';
      _filtreDebut   = debut;
      _filtreFin     = fin;
    });
  }

  Widget _buildLigneSeuilAdaptatif(String label, double valeurActuelle, double valeurDefaut) {
    final delta = valeurActuelle - valeurDefaut;
    Color deltaColor = Colors.white38;
    String deltaTxt = '';
    if (delta.abs() >= 0.5) {
      deltaTxt = ' (${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)})';
      deltaColor = delta > 0 ? const Color(0xFFFFB74D) : _green;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(label,
            style: const TextStyle(color: Colors.white60, fontSize: 16))),
        Text(valeurActuelle.toStringAsFixed(1),
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        Text(deltaTxt, style: TextStyle(color: deltaColor, fontSize: 16)),
      ]),
    );
  }


  Widget _buildRapportJournalierComplet(RapportJournalier r) {
    final dateStr = '${r.date.day.toString().padLeft(2,'0')}/${r.date.month.toString().padLeft(2,'0')}/${r.date.year}';
    final noteColor = _couleurNote(r.noteJournee ?? '');

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [noteColor.withValues(alpha: 0.08), _card],
          begin: Alignment.topLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: noteColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── En-tête : date + note ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: noteColor.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              Icon(Icons.calendar_today_rounded, color: noteColor, size: 16),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dateStr,
                      style: TextStyle(color: noteColor, fontWeight: FontWeight.bold, fontSize: 16)),
                  // ★ v9.6 : heure d'analyse
                  if (r.heureAnalyse != null)
                    Text(
                      'Analysé à ${r.heureAnalyse!.hour.toString().padLeft(2,'0')}h${r.heureAnalyse!.minute.toString().padLeft(2,'0')}',
                      style: TextStyle(color: noteColor.withValues(alpha: 0.65), fontSize: 16),
                    ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: noteColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: noteColor.withValues(alpha: 0.5)),
                ),
                child: Text(r.noteJournee ?? '—',
                    style: TextStyle(color: noteColor, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ]),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // ── Stats globales du jour ──────────────────────────────────────
              Row(children: [
                _buildTuile('${r.tauxGagnant.toStringAsFixed(0)}%',
                    'Favori\ngagnant', _gold),
                const SizedBox(width: 8),
                _buildTuile('${r.tauxTop3.toStringAsFixed(0)}%',
                    'Favori\ntop 3', _green),
                const SizedBox(width: 8),
                _buildTuile('${r.tauxTop5.toStringAsFixed(0)}%',
                    'Favori\ntop 5', _purple),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                _buildTuile('${r.nbAvecResultat}',
                    'Courses\nanalysées', const Color(0xFF42A5F5)),
                const SizedBox(width: 8),
                _buildTuile('${r.scoreMoyenJour.toStringAsFixed(0)}/100',
                    'Score IA\nmoyen', const Color(0xFFFF9800)),
                const SizedBox(width: 8),
                _buildTuile('${r.tauxTop3Correct.toStringAsFixed(0)}%',
                    '2/3 IA\ncorrects', Colors.teal),
              ]),

              // ── Jauge visuelle du taux gagnant ──────────────────────────────
              const SizedBox(height: 14),
              _buildJaugeAvecLabel(
                'Favori IA 🥇 gagnant',
                r.tauxGagnant / 100,
                _gold,
                '${r.favoriGagnant}/${r.nbAvecResultat} courses',
              ),
              const SizedBox(height: 6),
              _buildJaugeAvecLabel(
                'Favori IA 🏆 dans le top 3',
                r.tauxTop3 / 100,
                _green,
                '${r.favoriTop3}/${r.nbAvecResultat} courses',
              ),
              const SizedBox(height: 6),
              _buildJaugeAvecLabel(
                'Score IA moyen',
                r.scoreMoyenJour / 100,
                const Color(0xFFFF9800),
                '${r.scoreMoyenJour.toStringAsFixed(1)}/100',
              ),

              // ── Stats par discipline ────────────────────────────────────────
              if (r.parDiscipline.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Par discipline', style: TextStyle(
                    color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...r.parDiscipline.where((d) => d.nbCourses > 0).map(
                  (d) => _buildLigneDisicpline(d),
                ),
              ],

              // ★ v9.6 : Détail course par course (expandable)
              if (r.coursesDetail.isNotEmpty) ...[
                const SizedBox(height: 16),
                // ★ v10.58 : passe nbCoursesAnalysees pour expliquer le delta
                _buildDetailCourses(r.coursesDetail, r.nbCoursesAnalysees),
              ],

              // ★ v9.6 : Stats par type de pari du jour
              if (r.parTypePari.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Par type de pari conseillé',
                    style: TextStyle(color: Colors.white70, fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...r.parTypePari.map((tp) => _buildLigneTypePariJour(tp)),
              ],

              // ── Poids appris aujourd'hui ─────────────────────────────────────
              if (r.poidsApres.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Divider(color: Colors.white12, height: 1),
                const SizedBox(height: 10),
                Row(children: [
                  const Icon(Icons.tune_rounded, color: Colors.white38, size: 14),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Poids IA après apprentissage (mise à jour n°${r.nbMisesAJourPoids})',
                      style: const TextStyle(color: Colors.white38, fontSize: 15))),
                ]),
                const SizedBox(height: 8),
                _buildPoidsMinimaux(r.poidsApres),
              ],

              // ── Message éventuel ─────────────────────────────────────────────
              if (r.nbCoursesEchouees > 0) ...[
                const SizedBox(height: 10),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.schedule, color: Colors.orange, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${r.nbCoursesEchouees} course(s) sans résultat officiel au moment de l\'analyse.\n'
                      'Normal si lancé en cours de journée — réanalysez après 20h30.',
                      style: const TextStyle(color: Colors.orange, fontSize: 14),
                    ),
                  ),
                ]),
              ],
              // Rapport "vide" : explication claire
              if (r.nbAvecResultat == 0 && r.nbCoursesAnalysees == 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                  ),
                  child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('💡', style: TextStyle(fontSize: 16)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'L\'API PMU ne publie pas encore les résultats officiels de la journée.\n'
                        'Relancez l\'analyse après 20h30 pour comparer les pronostics IA aux arrivées réelles et déclencher l\'apprentissage.',
                        style: TextStyle(color: Colors.white60, fontSize: 15),
                      ),
                    ),
                  ]),
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  // ── Widget : Historique des rapports (mini-cartes) ─────────────────────────

  Widget _buildHistoriqueRapports(List<RapportJournalier> rapports) {
    return Column(
      children: rapports.map((r) => _buildMiniCarteRapport(r)).toList(),
    );
  }

  Widget _buildMiniCarteRapport(RapportJournalier r) {
    final dateStr =
        '${r.date.day.toString().padLeft(2,'0')}/${r.date.month.toString().padLeft(2,'0')}';
    final noteColor = _couleurNote(r.noteJournee ?? '');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: noteColor.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        // Date
        SizedBox(
          width: 34,
          child: Text(dateStr,
              style: TextStyle(color: noteColor, fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
        ),
        const SizedBox(width: 10),
        // Mini jauges
        Expanded(
          child: Column(children: [
            _buildJaugeMini('Gagnant', r.tauxGagnant / 100, _gold),
            const SizedBox(height: 3),
            _buildJaugeMini('Top 3  ', r.tauxTop3    / 100, _green),
          ]),
        ),
        const SizedBox(width: 10),
        // Note + nb courses
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: noteColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              (r.noteJournee ?? '—').split(' ').first,
              style: TextStyle(color: noteColor, fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 3),
          Text('${r.nbAvecResultat} courses',
              style: const TextStyle(color: Colors.white24, fontSize: 15)),
        ]),
      ]),
    );
  }

  // ── Helpers visuels ─────────────────────────────────────────────────────────

  Color _couleurNote(String note) {
    if (note.contains('Excellente')) return const Color(0xFFFFD700);
    if (note.contains('Bonne'))      return const Color(0xFF4CAF7D);
    if (note.contains('Moyenne'))    return const Color(0xFFFFB74D);
    return const Color(0xFFEF5350);
  }

  Widget _buildTuile(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(children: [
          Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 15),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  Widget _buildJaugeAvecLabel(String label, double value, Color color, String detail) {
    // pct non utilisée directement dans ce widget (widthFactor utilise value)
    return Row(children: [
      SizedBox(
        width: 130,
        child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 15)),
      ),
      Expanded(
        child: Stack(children: [
          Container(height: 7, decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(4),
          )),
          FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(height: 7, decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            )),
          ),
        ]),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 58,
        child: Text(detail,
            style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold),
            textAlign: TextAlign.right),
      ),
    ]);
  }

  Widget _buildJaugeMini(String label, double value, Color color) {
    return Row(children: [
      SizedBox(
        width: 44,
        child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 15)),
      ),
      Expanded(
        child: Stack(children: [
          Container(height: 5, decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(3),
          )),
          FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(height: 5, decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            )),
          ),
        ]),
      ),
      const SizedBox(width: 6),
      Text('${(value * 100).toStringAsFixed(0)}%',
          style: TextStyle(color: color, fontSize: 15)),
    ]);
  }

  // ★ v9.6 : Ligne stats par type de pari du jour
  Widget _buildLigneTypePariJour(StatsTypePariJour tp) {
    final color = tp.tauxTop3 >= 40 ? const Color(0xFF4CAF7D)
        : tp.tauxTop3 >= 25 ? const Color(0xFFFFB74D)
        : const Color(0xFFEF5350);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Text(tp.emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tp.typePari,
                style: const TextStyle(color: Colors.white, fontSize: 14,
                    fontWeight: FontWeight.bold)),
            Text('${tp.nbPronostiques} cours pronostiquée${tp.nbPronostiques > 1 ? "s" : ""}',
                style: const TextStyle(color: Colors.white38, fontSize: 16)),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${tp.nbFavoriGagnant} gagnant${tp.nbFavoriGagnant > 1 ? "s" : ""}',
              style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
          Text('${tp.nbFavoriTop3} top3 (${tp.tauxTop3.toStringAsFixed(0)}%)',
              style: const TextStyle(color: Colors.white54, fontSize: 16)),
        ]),
      ]),
    );
  }

  // ★ v9.6 : Détail course par course (expandable)
  // ★ v10.58 : nbTotal = nbCoursesAnalysees (toutes courses traitées)
  //            courses.length = courses avec résultat exploitable (resultatsReels)
  //            Le delta (nbTotal - courses.length) = courses sans résultat officiel encore disponible
  Widget _buildDetailCourses(List<CourseDetailRapport> courses, [int nbTotal = 0]) {
    final int nbAnalysables = courses.length;
    final int nbExclues = nbTotal > nbAnalysables ? nbTotal - nbAnalysables : 0;

    // Titre clair : distingue analysables / totales si delta > 0
    final String titreCours = nbExclues > 0
        ? '$nbAnalysables courses analysables / $nbTotal totales'
        : 'Détail des $nbAnalysables courses';

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 4),
        title: Row(children: [
          const Icon(Icons.list_alt_rounded, color: Colors.white54, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(titreCours,
                style: const TextStyle(color: Colors.white70, fontSize: 15,
                    fontWeight: FontWeight.bold)),
          ),
        ]),
        iconColor: Colors.white38,
        collapsedIconColor: Colors.white24,
        children: [
          // ★ v10.58 : note d'exclusion si delta détecté
          if (nbExclues > 0)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline_rounded, color: Colors.orange, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$nbExclues course(s) exclue(s) : résultat officiel non disponible '
                    'au moment de l\'analyse (course annulée, non partante, '
                    'ou résultat incomplet).',
                    style: const TextStyle(color: Colors.orange, fontSize: 13),
                  ),
                ),
              ]),
            ),
          ...courses.map((c) => _buildLigneCourse(c)),
        ],
      ),
    );
  }

  Widget _buildLigneCourse(CourseDetailRapport c) {
    final rang  = c.rangFavoriIa;
    final type  = c.typePariConseille;

    // ★ v10.9 : succès défini par le TYPE DE PARI, pas juste top3 générique
    final bool gagn;
    final bool ok;
    switch (type) {
      case 'Simple Gagnant':
        gagn = rang == 1;
        ok   = false; // pas de "partiellement bon" pour Simple Gagnant
        break;
      case 'Gagnant+Placé':
        gagn = rang == 1;
        ok   = rang != null && rang <= 3; // placé = top3
        break;
      case 'Simple Placé':
        gagn = false;
        ok   = rang != null && rang <= 3;
        break;
      case 'Couplé Gagnant':
        // ★ fix : les 2 chevaux IA doivent TOUS DEUX être dans le top 2 réel
        // rang seul (= rang du 1er cheval IA) ne suffit pas
        {
          final arr = c.arriveeReelle;
          final n1  = int.tryParse(c.favoriIaNumero ?? '');
          final n2  = int.tryParse(c.favoriIaNumero2 ?? '');
          if (arr.length >= 2 && n1 != null && n2 != null) {
            final top2 = arr.take(2).toSet();
            gagn = top2.contains(n1) && top2.contains(n2);
            ok   = false; // pas de "partiellement bon" pour Couplé Gagnant
          } else {
            gagn = false;
            ok   = rang != null && rang <= 2; // fallback si données manquantes
          }
        }
        break;
      case 'Couplé Placé':
        // ★ fix : les 2 chevaux IA doivent TOUS DEUX être dans le top 3 réel
        {
          final arr = c.arriveeReelle;
          final n1  = int.tryParse(c.favoriIaNumero ?? '');
          final n2  = int.tryParse(c.favoriIaNumero2 ?? '');
          if (arr.length >= 3 && n1 != null && n2 != null) {
            final top3 = arr.take(3).toSet();
            gagn = false;
            ok   = top3.contains(n1) && top3.contains(n2);
          } else {
            gagn = false;
            ok   = rang != null && rang <= 3; // fallback si données manquantes
          }
        }
        break;
      case 'Tiercé':
        // ✅ VERT si au moins 2 des 3 chevaux IA sont dans le top 3 réel
        gagn = false;
        ok   = c.nbTop3DansArrivee >= 2;
        break;
      case 'Tiercé Ordre':
        // ✅ VERT uniquement si les 3 chevaux IA sont dans le top 3 dans l'ordre exact
        gagn = false;
        ok   = c.nbTop3DansArrivee >= 3; // les 3 bons ET dans l'ordre (vérifié en amont)
        break;
      case 'Quarté+':
        // ✅ VERT si au moins 3 des 4 chevaux IA sont dans le top 4 réel
        // nbTop3DansArrivee + nbTop5DansArrivee permettent d'approcher le top4
        gagn = false;
        ok   = c.nbTop3DansArrivee + (c.nbTop5DansArrivee - c.nbTop3DansArrivee) >= 3
               && (rang == null || rang <= 4);
        break;
      case 'Quinté+':
        // ✅ VERT si au moins 4 des 5 chevaux IA sont dans le top 5 réel
        // CORRECTION v10.12 : seuil 4/5 au lieu de favoriTop5 générique
        gagn = false;
        ok   = c.nbTop5DansArrivee >= 4;
        break;
      default:
        gagn = c.favoriGagnant;
        ok   = c.favoriTop3;
    }

    final color  = gagn ? const Color(0xFFFFD700)
        : ok  ? const Color(0xFF4CAF7D)
        : rang != null ? const Color(0xFFEF5350)
        : Colors.white38;
    final icon   = gagn ? '🥇' : ok ? '✅' : rang != null ? '❌' : '❌';
    final rangTxt = c.rangFavoriIa != null ? '${c.rangFavoriIa}ème' : '—';

    // ★ v10.58 : layout corrigé — Expanded pour les textes longs + Flexible pour la colonne droite
    //            fontSize réduit à 13/12 pour éviter le débordement
    //            maxLines + overflow: ellipsis sur tous les champs texte long
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Icône résultat (largeur fixe 22px) ──────────────────────
          SizedBox(
            width: 22,
            child: Text(icon, style: const TextStyle(fontSize: 15)),
          ),
          const SizedBox(width: 8),
          // ── Bloc texte central (Expanded pour prendre tout l'espace) ─
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nom course : maxLines 1 + ellipsis
                Text(
                  c.nomCourse.isNotEmpty ? c.nomCourse : '—',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                // Hippodrome · heure · type pari : maxLines 2 + ellipsis
                Text(
                  [
                    if (c.hippodrome.isNotEmpty) c.hippodrome,
                    if (c.heure.isNotEmpty) c.heure,
                    if (c.typePariConseille.isNotEmpty) c.typePariConseille,
                  ].join(' · '),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                ),
                const SizedBox(height: 4),
                // Favori IA + rang
                Text(
                  'N°${c.favoriIaNumero ?? "?"}'
                  '${c.favoriIaNom != null && c.favoriIaNom!.isNotEmpty ? " ${c.favoriIaNom}" : ""}'
                  ' → $rangTxt',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // ── Arrivée réelle (Flexible, alignée à droite) ──────────────
          if (c.arriveeReelle.isNotEmpty)
            Flexible(
              child: Text(
                'Arr:\n${c.arriveeReelle.take(5).join("-")}',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  // ── ★ v9.92 : Encadré "Dernière analyse" date + heure ────────────────────
  Widget _buildEncadreDerniereAnalyse() {
    final dt = _derniereAnalyseHeure;

    // Formater la date et l'heure
    String contenu;
    Color couleurBord;
    Color couleurIcon;
    IconData icone;

    if (dt == null) {
      contenu      = 'Aucune analyse effectuée — lancez une première analyse ci-dessous.';
      couleurBord  = Colors.white12;
      couleurIcon  = Colors.white24;
      icone        = Icons.history_rounded;
    } else {
      final now   = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final dtDay = DateTime(dt.year, dt.month, dt.day);
      final diff  = today.difference(dtDay).inDays;

      final heureStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      final dateStr  = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

      final String quand;
      if (diff == 0)       quand = 'Aujourd\'hui à $heureStr';
      else if (diff == 1)  quand = 'Hier ($dateStr) à $heureStr';
      else                 quand = 'Le $dateStr à $heureStr';

      contenu     = quand;
      couleurBord = const Color(0xFF4CAF7D).withValues(alpha: 0.55);
      couleurIcon = const Color(0xFF4CAF7D);
      icone       = Icons.check_circle_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: dt == null
            ? Colors.white.withValues(alpha: 0.03)
            : const Color(0xFF4CAF7D).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: couleurBord, width: 1),
      ),
      child: Row(
        children: [
          Icon(icone, color: couleurIcon, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dernière analyse',
                  style: TextStyle(
                    color: dt == null ? Colors.white24 : Colors.white54,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  contenu,
                  style: TextStyle(
                    color: dt == null ? Colors.white38 : Colors.white,
                    fontSize: 16,
                    fontWeight: dt == null ? FontWeight.normal : FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ★ v9.6 : Bouton recréer pronostics avec effet visuel
  Widget _buildBoutonRecreer() {
    final tousPresents = _nbManquants == 0 && _nbTotal > 0;
    final memoireVide  = _nbTotal > 0 && _nbManquants == _nbTotal;
    final partial      = _nbManquants > 0 && !memoireVide;

    // Couleurs selon l'état
    final Color couleurPrincipale;
    final Color couleurBord;
    final Color couleurTexte;
    final String label;
    final String emoji;

    if (tousPresents) {
      couleurPrincipale = const Color(0xFF0D3320);
      couleurBord       = const Color(0xFF1DE585);
      couleurTexte      = const Color(0xFF1DE585);
      label             = 'Pronostics en mémoire ($_nbTotal/$_nbTotal)';
      emoji             = '✅';
    } else if (memoireVide) {
      couleurPrincipale = const Color(0xFF3D0A0A);
      couleurBord       = const Color(0xFFFF4444);
      couleurTexte      = const Color(0xFFFF6666);
      label             = 'Mémoire vide — Recréer les $_nbTotal pronostics';
      emoji             = '❌';
    } else if (partial) {
      couleurPrincipale = const Color(0xFF2D1A00);
      couleurBord       = const Color(0xFFFFAA00);
      couleurTexte      = const Color(0xFFFFCC44);
      label             = '$_nbManquants manquant(s) sur $_nbTotal — Recréer';
      emoji             = '⚠️';
    } else {
      // Pas encore calculé
      couleurPrincipale = const Color(0xFF0D1B2A);
      couleurBord       = Colors.white12;
      couleurTexte      = Colors.white38;
      label             = 'Vérification en cours…';
      emoji             = '🔄';
    }

    final peutCliquer = !tousPresents && !_recreationEnCours && _nbTotal > 0;

    return GestureDetector(
      onTap: peutCliquer ? _recreerPronostics : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        height: 50,
        decoration: BoxDecoration(
          color: couleurPrincipale,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: couleurBord,
            width: (memoireVide || partial) ? 1.8 : 1.2,
          ),
          boxShadow: peutCliquer ? [
            BoxShadow(
              color: couleurBord.withValues(alpha: 0.35),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ] : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_recreationEnCours)
              SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(couleurTexte),
                ),
              )
            else
              Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                _recreationEnCours ? 'Recréation en cours…' : label,
                style: TextStyle(
                  color: couleurTexte,
                  fontSize: 14,
                  fontWeight: peutCliquer ? FontWeight.bold : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (peutCliquer) ...[
              const SizedBox(width: 8),
              Icon(Icons.refresh_rounded, color: couleurTexte, size: 18),
            ],
          ],
        ),
      ),
    );
  }


  Widget _buildLigneDisicpline(StatsDisciplineJour d) {
    final emoji = d.discipline.contains('Trot Att') ? '🏇'
        : d.discipline.contains('Trot Mon') ? '🏇'
        : d.discipline.contains('Plat') ? '🐎'
        : '🚧';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 6),
        SizedBox(
          width: 90,
          child: Text(d.discipline.length > 12 ? '${d.discipline.substring(0,12)}…' : d.discipline,
              style: const TextStyle(color: Colors.white60, fontSize: 15)),
        ),
        const SizedBox(width: 6),
        Expanded(child: Stack(children: [
          Container(height: 6, decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(3),
          )),
          FractionallySizedBox(
            widthFactor: (d.tauxTop3 / 100).clamp(0.0, 1.0),
            child: Container(height: 6, decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(3),
            )),
          ),
        ])),
        const SizedBox(width: 8),
        Text(
          '${d.tauxGagnant.toStringAsFixed(0)}% | top3: ${d.tauxTop3.toStringAsFixed(0)}%',
          style: const TextStyle(color: Colors.white38, fontSize: 15),
        ),
      ]),
    );
  }

  Widget _buildPoidsMinimaux(Map<String, double> poids) {
    // ★ v5.0 : labels pour les 10 critères
    const labels = {
      'forme': 'Forme', 'gains': 'Gains', 'record': 'Record',
      'cote': 'Cote', 'constance': 'Régul.', 'victoires': 'Vict.',
      'discipline': 'Disc.', 'distSpec': 'Dist.', 'jockey': 'Jockey', 'repos': 'Repos',
    };
    final sorted = poids.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: sorted.map((e) {
        final pct = (e.value * 100).toStringAsFixed(0);
        final isHigh = e.value == sorted.first.value;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: isHigh ? _gold.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: isHigh ? _gold.withValues(alpha: 0.4) : Colors.white12),
          ),
          child: Text(
            '${labels[e.key] ?? e.key} $pct%',
            style: TextStyle(
              color: isHigh ? _gold : Colors.white38,
              fontSize: 15,
              fontWeight: isHigh ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Widget : Journal des critères en hausse/baisse ★ v9.92 ──────────────────
  // → Délégué à IaPerfSecondaryWidgets (ia_perf_secondary_widgets.dart)
}

// ── Widget pédagogique — mini-liste des étapes de l'analyse ──────────────────
class _MiniListeAnalyse extends StatelessWidget {
  const _MiniListeAnalyse();

  static const _etapes = [
    (Icons.download_rounded,       Color(0xFF42A5F5), 'Résultats PMU récupérés'),
    (Icons.compare_arrows_rounded, Color(0xFF7C4DFF), 'Pronostics IA comparés'),
    (Icons.memory_rounded,         Color(0xFF4CAF7D), 'Mémoire IA mise à jour'),
    (Icons.tune_rounded,           Color(0xFFFFD700), 'Poids ajustés seulement si nouveaux résultats'),
    (Icons.rule_rounded,           Color(0xFFFF9800), 'Audit recalculé si besoin'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _etapes.map((e) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(e.$1, color: e.$2, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(e.$3,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 14)),
          ),
        ]),
      )).toList(),
    );
  }
}
