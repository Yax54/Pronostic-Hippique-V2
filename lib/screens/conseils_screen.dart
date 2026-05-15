// ═══════════════════════════════════════════════════════════════════
//  ONGLET CONSEILS IA — Recommandations par course (Zone-Turf)
//  v10.22 : Panneau filtres avancés (Type Paris multi, Confiance min,
//           Hippodrome multi, Discipline multi) + persistance prefs
// ═══════════════════════════════════════════════════════════════════
import '../widgets/type_pari_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/favori_button.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show NavigationNotifier;
import '../models/zt_models.dart';
import '../services/zone_turf_service.dart';
import '../services/data_refresh_service.dart';
import '../services/alert_service.dart';
import '../providers/pmu_provider.dart';
import '../widgets/bet_bottom_sheet.dart';
import '../widgets/arrivee_reelle_widget.dart';
import 'course_detail_screen.dart';

// ── Clés SharedPreferences ─────────────────────────────────────────
const _kTypesParis     = 'conseils_filtres_types_paris';
const _kConfianceMin   = 'conseils_filtres_confiance_min';
const _kHippodromes    = 'conseils_filtres_hippodromes';
const _kDisciplines    = 'conseils_filtres_disciplines';
const _kTriMode        = 'conseils_filtres_tri_mode'; // ★ v10.24 audit
const _kFiltresActifs  = 'conseils_filtres_actifs';   // ★ v9.93 : état ON/OFF

class ConseilsScreen extends StatefulWidget {
  /// Permet au Backtesting d'injecter des filtres (une seule fois, sans écraser
  /// les modifs manuelles ultérieures).
  final List<String>? initTypesParis;
  final int?          initConfianceMin;
  final List<String>? initHippodromes;
  final List<String>? initDisciplines;

  const ConseilsScreen({
    super.key,
    this.initTypesParis,
    this.initConfianceMin,
    this.initHippodromes,
    this.initDisciplines,
  });

  @override
  State<ConseilsScreen> createState() => _ConseilsScreenState();
}

class _ConseilsScreenState extends State<ConseilsScreen> {
  List<ZtReunion> _reunions = [];
  bool _loading = true;
  String? _error;
  String _triMode = 'Confiance';

  // ── Filtres ON/OFF global ─────────────────────────────────────────
  bool _filtresActifs = true; // true = filtres appliqués

  // ── Filtres avancés ───────────────────────────────────────────────
  final Set<String> _selectedTypesParis    = {};
  final Set<String> _selectedHippodromes   = {};
  final Set<String> _selectedDisciplines   = {};
  int    _confianceMin    = 0;   // 0 = pas de filtre
  final TextEditingController _confianceCtrl = TextEditingController(text: '0');

  // ── ★ v10.29 : écoute NavigationNotifier pour détecter l'arrivée sur cet onglet ──
  NavigationNotifier? _navNotifier;
  int _lastNavIndex = -1;

  @override
  void initState() {
    super.initState();
    _chargerPrefs().then((_) => _charger());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ★ v10.29 : abonnement au NavigationNotifier — UNE SEULE FOIS
    final nav = context.read<NavigationNotifier>();
    if (_navNotifier != nav) {
      _navNotifier?.removeListener(_onNavChanged);
      _navNotifier = nav;
      _navNotifier!.addListener(_onNavChanged);
    }
  }

  /// ★ v10.29 : appelé à chaque changement d'onglet
  void _onNavChanged() {
    final nav = _navNotifier;
    if (nav == null || !mounted) return;
    final newIndex = nav.index;
    // On est SUR l'onglet Conseils (index 1) et on y arrive depuis ailleurs
    if (newIndex == 1 && _lastNavIndex != 1) {
      _rechargerSiInjectPending();
    }
    _lastNavIndex = newIndex;
  }

  /// ★ v10.29 : lit le flag inject et applique les filtres si présents
  Future<void> _rechargerSiInjectPending() async {
    final prefs = await SharedPreferences.getInstance();
    final inject = prefs.getBool('conseils_inject_pending') ?? false;
    if (!inject) return;
    // Consommer le flag immédiatement
    await prefs.setBool('conseils_inject_pending', false);
    final types = prefs.getStringList(_kTypesParis)  ?? [];
    final hipps = prefs.getStringList(_kHippodromes) ?? [];
    final discs = prefs.getStringList(_kDisciplines) ?? [];
    final conf  = prefs.getInt(_kConfianceMin) ?? 0;
    if (!mounted) return;
    setState(() {
      _selectedTypesParis  ..clear()..addAll(types);
      _selectedHippodromes ..clear()..addAll(hipps);
      _selectedDisciplines ..clear()..addAll(discs);
      _confianceMin = conf;
      _confianceCtrl.text = conf == 0 ? '0' : '$conf';
      // Activer les filtres automatiquement si des critères sont présents
      if (types.isNotEmpty || hipps.isNotEmpty || discs.isNotEmpty || conf > 0) {
        _filtresActifs = true;
      }
    });
  }



  @override
  void dispose() {
    _navNotifier?.removeListener(_onNavChanged);
    _confianceCtrl.dispose();
    super.dispose();
  }

  // ── Persistance ───────────────────────────────────────────────────
  Future<void> _chargerPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final types  = prefs.getStringList(_kTypesParis)  ?? [];
    final hipps  = prefs.getStringList(_kHippodromes) ?? [];
    final discs  = prefs.getStringList(_kDisciplines) ?? [];
    final conf   = prefs.getInt(_kConfianceMin) ?? 0;
    final tri    = prefs.getString(_kTriMode)   ?? 'Confiance';
    final actifs = prefs.getBool(_kFiltresActifs) ?? true; // ★ v9.93
    if (!mounted) return;
    setState(() {
      _selectedTypesParis  ..clear()..addAll(types);
      _selectedHippodromes ..clear()..addAll(hipps);
      _selectedDisciplines ..clear()..addAll(discs);
      _confianceMin = conf;
      _confianceCtrl.text = conf == 0 ? '0' : '$conf';
      _triMode = tri;
      _filtresActifs = actifs; // ★ v9.93 : restaurer l'état ON/OFF
    });
  }

  Future<void> _sauvegarderPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kTypesParis,   _selectedTypesParis.toList());
    await prefs.setStringList(_kHippodromes,  _selectedHippodromes.toList());
    await prefs.setStringList(_kDisciplines,  _selectedDisciplines.toList());
    await prefs.setInt(_kConfianceMin,        _confianceMin);
    await prefs.setString(_kTriMode,          _triMode);
    await prefs.setBool(_kFiltresActifs,      _filtresActifs); // ★ v9.93
  }

  // ── v10.29 : inject via SharedPreferences + listener NavigationNotifier ──
  // (appliquerFiltresBt supprimé — l'inject se fait désormais via _rechargerSiInjectPending)

  Future<void> _charger({bool refresh = false}) async {
    if (!refresh) {
      final svc = context.read<DataRefreshService>();
      if (svc.reunions.isNotEmpty) {
        if (mounted) setState(() { _reunions = svc.reunions; _loading = false; _error = null; });
        return;
      }
    }
    setState(() { _loading = true; _error = null; });
    try {
      final svc = context.read<DataRefreshService>();
      if (refresh) {
        await svc.refresh();
        if (mounted) setState(() { _reunions = svc.reunions; _loading = false; });
      } else {
        final r = await ZoneTurfService.chargerProgramme(forceRefresh: false);
        if (mounted) setState(() { _reunions = r; _loading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── Listes dynamiques depuis les données du jour ──────────────────
  List<String> get _hippodromesDisponibles {
    final set = <String>{};
    for (final r in _reunions) {
      if (r.lieu.isNotEmpty) set.add(r.lieu.toUpperCase());
    }
    return set.toList()..sort();
  }

  List<String> get _disciplinesDisponibles {
    final set = <String>{};
    for (final r in _reunions) {
      if (r.discipline.isNotEmpty) set.add(_capitalise(r.discipline));
    }
    return set.toList()..sort();
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

  // ── Accesseur filtré et trié ──────────────────────────────────────
  List<({ZtCourse course, ZtReunion reunion})> get _coursesAvecPartants {
    final list = <({ZtCourse course, ZtReunion reunion})>[];
    for (final r in _reunions) {
      for (final c in r.courses) {
        if (c.partants.isNotEmpty) list.add((course: c, reunion: r));
      }
    }

    // ── Filtres actifs (seulement si le toggle global est ON) ────────
    final filtered = list.where((item) {
      if (!_filtresActifs) return true; // toggle OFF → tout afficher
      final typePari = _getTypePariPourCourse(item.course);
      final scoreTop = item.course.partantsParRangIA.isNotEmpty
          ? item.course.partantsParRangIA.first.scoreIA
          : 0.0;
      final hippo = item.reunion.lieu.toUpperCase();
      final disc  = _capitalise(item.reunion.discipline);

      // Type de pari (multi)
      if (_selectedTypesParis.isNotEmpty && !_selectedTypesParis.contains(typePari)) return false;
      // Confiance min
      if (_confianceMin > 0 && scoreTop < _confianceMin) return false;
      // Hippodrome (multi)
      if (_selectedHippodromes.isNotEmpty && !_selectedHippodromes.contains(hippo)) return false;
      // Discipline (multi)
      if (_selectedDisciplines.isNotEmpty && !_selectedDisciplines.contains(disc)) return false;

      return true;
    }).toList();

    // ── Tri ──────────────────────────────────────────────────────────
    switch (_triMode) {
      case 'Confiance':
        filtered.sort((a, b) {
          final sA = a.course.partantsParRangIA.isNotEmpty ? a.course.partantsParRangIA.first.scoreIA : 0;
          final sB = b.course.partantsParRangIA.isNotEmpty ? b.course.partantsParRangIA.first.scoreIA : 0;
          return sB.compareTo(sA);
        });
        break;
      case 'Heure':
        filtered.sort((a, b) => a.course.heure.compareTo(b.course.heure));
        break;
    }
    return filtered;
  }

  // Toutes les courses (sans filtre) — pour les badges de comptage
  List<({ZtCourse course, ZtReunion reunion})> get _allCoursesWithPartants {
    final list = <({ZtCourse course, ZtReunion reunion})>[];
    for (final r in _reunions) {
      for (final c in r.courses) {
        if (c.partants.isNotEmpty) list.add((course: c, reunion: r));
      }
    }
    return list;
  }

  // ── Nombre de filtres actifs (pour le badge du bouton) ────────────
  int get _nbFiltresActifs {
    int n = 0;
    if (_selectedTypesParis.isNotEmpty)  n++;
    if (_confianceMin > 0)              n++;
    if (_selectedHippodromes.isNotEmpty) n++;
    if (_selectedDisciplines.isNotEmpty) n++;
    return n;
  }

  // ── Calcule le type de pari recommandé pour une course ────────────
  String _getTypePariPourCourse(ZtCourse course) {
    final sorted = course.partantsParRangIA;
    if (sorted.isEmpty) return 'À surveiller';
    final score  = sorted.first.scoreIA;
    final score2 = sorted.length >= 2 ? sorted[1].scoreIA : 0.0;
    final score3 = sorted.length >= 3 ? sorted[2].scoreIA : 0.0;
    final score4 = sorted.length >= 4 ? sorted[3].scoreIA : 0.0;
    final ecart12 = (score - score2).abs();
    final estEquilibre = !course.isQuinte && ecart12 <= 15 && score >= 60 && score2 >= 50;
    final cote = sorted.first.coteDecimale;

    // ★ v9.93 : Grande course classique sans Quarté/Quinté → limiter au Tiercé max
    if (course.isClassiqueSansMultiple) {
      if (score >= 75 && score2 >= 55 && score3 >= 45) return 'Tiercé';
      if (estEquilibre && score >= 75) return 'Couplé Gagnant';
      if (estEquilibre && score >= 60) return 'Couplé Placé';
      if (score >= 80 && cote <= 8.0)  return 'Simple Gagnant';
      if (score >= 80)                  return 'Gagnant+Placé';
      if (score >= 65)                  return 'Simple Placé';
      if (score >= 50)                  return 'Gagnant+Placé';
      return 'À surveiller';
    }

    if (course.isQuinte) {
      if (score >= 75 && score2 >= 60 && score3 >= 55) return 'Quinté+';
      if (score >= 65 && score2 >= 55) return 'Quarté+';
      if (score >= 55 && score2 >= 50) return 'Tiercé';
      if (score >= 45) return 'Couplé Gagnant';
      return 'À surveiller';
    } else if (course.isQuarte) {
      if (score >= 60 && score2 >= 50 && score3 >= 40 && score4 >= 35) return 'Quarté+';
      if (score >= 55 && score2 >= 45 && score3 >= 35) return 'Tiercé';
      if (score >= 45) return 'Couplé Gagnant';
      return 'À surveiller';
    } else if (score >= 65 && score2 >= 60 && score3 >= 55 && score4 >= 50 && course.partants.length >= 10) {
      return 'Quarté+';
    } else if (estEquilibre && score >= 75) {
      return 'Couplé Gagnant';
    } else if (estEquilibre && score >= 60) {
      return 'Couplé Placé';
    } else if (score >= 80 && cote <= 8.0) {
      return 'Simple Gagnant';
    } else if (score >= 80) {
      return 'Gagnant+Placé';
    } else if (score >= 65) {
      return 'Simple Placé';
    } else if (score >= 50) {
      return 'Gagnant+Placé';
    } else if (score >= 35) {
      return 'Tiercé';
    }
    return 'À surveiller';
  }

  // ── Définition statique des types de pari ─────────────────────────
  static const List<(String label, String icon, Color color)> _filtresParis = [
    ('Simple Gagnant', '🏆',   Color(0xFFFFD700)),
    ('Simple Placé',   '🎯',   Color(0xFF26C6DA)),
    ('Gagnant+Placé',  '🎯🏆', Color(0xFF7C4DFF)),
    ('Couplé Gagnant', '💑',   Color(0xFFFF7043)),
    ('Couplé Placé',   '💑🎯', Color(0xFFFFB74D)),
    ('Tiercé',         '3️⃣',  Color(0xFFAB47BC)),
    ('Quarté+',        '4️⃣',  Color(0xFF26A69A)),
    ('Quinté+',        '⭐',   Color(0xFFFFD700)),
    ('À surveiller',   '👁️',  Color(0xFF78909C)),
  ];

  // Statistiques globales (après filtres)
  int    get _totalCourses    => _coursesAvecPartants.length;
  double get _confianceMoyenne {
    if (_coursesAvecPartants.isEmpty) return 0;
    final scores = _coursesAvecPartants.map((i) {
      final top = i.course.partantsParRangIA;
      return top.isNotEmpty ? top.first.scoreIA : 0.0;
    });
    return scores.reduce((a, b) => a + b) / scores.length;
  }

  // ── Réinitialiser tous les filtres ───────────────────────────────
  void _resetFiltres() {
    setState(() {
      _selectedTypesParis.clear();
      _selectedHippodromes.clear();
      _selectedDisciplines.clear();
      _confianceMin = 0;
      _confianceCtrl.text = '0';
    });
    _sauvegarderPrefs();
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<DataRefreshService>();
    if (!_loading && svc.reunions.isNotEmpty && _reunions != svc.reunions) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() { _reunions = svc.reunions; });
      });
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (!_loading && _error == null && _reunions.isNotEmpty)
              _buildBandeauFiltres(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  // ── HEADER : toute la barre sur UNE seule ligne ─────────────────
  Widget _buildHeader() {
    final hasFiltres = _nbFiltresActifs > 0;
    final filtreColor = _filtresActifs && hasFiltres
        ? const Color(0xFF7C4DFF)
        : Colors.white54;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1A1A3A), Color(0xFF0D1B2A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [

          // ══ LIGNE 1 : icône + titre + sous-titre + spinner + refresh ══
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C4DFF).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.4)),
                ),
                child: const Text('✨', style: TextStyle(fontSize: 17)),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Conseils IA',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    if (!_loading && _reunions.isNotEmpty)
                      Text(
                        '$_totalCourses course${_totalCourses > 1 ? 's' : ''}'
                        ' analysées • confiance moy. ${_confianceMoyenne.round()}%',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      )
                    else
                      Text('Algorithme multi-critères PMU',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 11)),
                  ],
                ),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: Color(0xFF7C4DFF), strokeWidth: 2)),
                ),
              SizedBox(
                width: 34,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => _charger(refresh: true),
                  icon: const Icon(Icons.refresh,
                      color: Color(0xFF7C4DFF), size: 19),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ══ LIGNE 2 : Filtres | Confiance | Heure | ON/OFF ══
          Row(
            children: [
              // ── Bouton Filtres avec badge ──
              GestureDetector(
                onTap: _ouvrirPanneauFiltres,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: hasFiltres && _filtresActifs
                            ? const Color(0xFF7C4DFF).withValues(alpha: 0.22)
                            : const Color(0xFF1A2F3D),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: hasFiltres && _filtresActifs
                              ? const Color(0xFF7C4DFF)
                              : Colors.white.withValues(alpha: 0.15),
                          width: hasFiltres && _filtresActifs ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.tune, color: filtreColor, size: 15),
                          const SizedBox(width: 5),
                          Text('Filtres',
                              style: TextStyle(
                                  color: filtreColor,
                                  fontSize: 13,
                                  fontWeight: hasFiltres && _filtresActifs
                                      ? FontWeight.bold
                                      : FontWeight.normal)),
                        ],
                      ),
                    ),
                    if (hasFiltres)
                      Positioned(
                        top: -5, right: -4,
                        child: Container(
                          width: 17, height: 17,
                          decoration: BoxDecoration(
                            color: _filtresActifs
                                ? const Color(0xFFFF1744)
                                : Colors.white24,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text('$_nbFiltresActifs',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 7),

              // ── Tri Confiance / Heure ──
              ...['Confiance', 'Heure'].map((t) {
                final sel = _triMode == t;
                return GestureDetector(
                  onTap: () {
                    setState(() => _triMode = t);
                    _sauvegarderPrefs();
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 7),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: sel
                          ? const Color(0xFF00E5FF).withValues(alpha: 0.15)
                          : const Color(0xFF1A2F3D),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: sel
                            ? const Color(0xFF00E5FF)
                            : Colors.white.withValues(alpha: 0.13),
                        width: sel ? 1.5 : 1.0,
                      ),
                    ),
                    child: Text(t,
                        style: TextStyle(
                            color: sel
                                ? const Color(0xFF00E5FF)
                                : Colors.white38,
                            fontSize: 13,
                            fontWeight: sel
                                ? FontWeight.bold
                                : FontWeight.normal)),
                  ),
                );
              }),

              const Spacer(),

              // ── ON / OFF ──
              GestureDetector(
                onTap: () {
                  setState(() => _filtresActifs = !_filtresActifs);
                  _sauvegarderPrefs(); // ★ v9.93 : persister l'état ON/OFF
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _filtresActifs
                        ? const Color(0xFF4CAF7D).withValues(alpha: 0.18)
                        : const Color(0xFFEF5350).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: _filtresActifs
                          ? const Color(0xFF4CAF7D).withValues(alpha: 0.7)
                          : const Color(0xFFEF5350).withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _filtresActifs
                            ? Icons.toggle_on
                            : Icons.toggle_off,
                        color: _filtresActifs
                            ? const Color(0xFF4CAF7D)
                            : const Color(0xFFEF5350),
                        size: 17,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _filtresActifs ? 'ON' : 'OFF',
                        style: TextStyle(
                            color: _filtresActifs
                                ? const Color(0xFF4CAF7D)
                                : const Color(0xFFEF5350),
                            fontSize: 13,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ★ Bug 1 fix : Chips filtres actifs sur PLUSIEURS LIGNES (Wrap)
          if (hasFiltres && _filtresActifs) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (_confianceMin > 0)
                    _buildFiltreChip('≥ $_confianceMin% confiance',
                        const Color(0xFF00E5FF),
                        onRemove: () => setState(() {
                          _confianceMin = 0;
                          _confianceCtrl.text = '0';
                          _sauvegarderPrefs();
                        })),
                  ..._selectedTypesParis.map((t) => _buildFiltreChip(
                      t, const Color(0xFFFFD700),
                      onRemove: () => setState(() {
                        _selectedTypesParis.remove(t);
                        _sauvegarderPrefs();
                      }))),
                  ..._selectedHippodromes.map((h) => _buildFiltreChip(
                      h, const Color(0xFF4CAF7D),
                      onRemove: () => setState(() {
                        _selectedHippodromes.remove(h);
                        _sauvegarderPrefs();
                      }))),
                  ..._selectedDisciplines.map((d) => _buildFiltreChip(
                      d, const Color(0xFF7C4DFF),
                      onRemove: () => setState(() {
                        _selectedDisciplines.remove(d);
                        _sauvegarderPrefs();
                      }))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── BANDEAU filtres actifs : message contextuel uniquement ──────────
  // Les chips sont maintenant dans _buildHeader (Wrap multi-lignes)
  Widget _buildBandeauFiltres() {
    final hasFiltres = _nbFiltresActifs > 0;
    if (!hasFiltres) return const SizedBox.shrink();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      color: _filtresActifs
          ? const Color(0xFF7C4DFF).withValues(alpha: 0.07)
          : const Color(0xFFEF5350).withValues(alpha: 0.06),
      child: Row(
        children: [
          Text(
            _filtresActifs ? '🤖' : '⏸️',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              _filtresActifs
                  ? 'Filtres actifs — $_totalCourses course${_totalCourses != 1 ? 's' : ''} sur ${_allCoursesWithPartants.length} correspondent'
                  : 'Filtres désactivés — toutes les ${_allCoursesWithPartants.length} courses affichées',
              style: TextStyle(
                color: _filtresActifs
                    ? const Color(0xFF7C4DFF).withValues(alpha: 0.9)
                    : const Color(0xFFEF5350).withValues(alpha: 0.8),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: _resetFiltres,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFF1744).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFF1744).withValues(alpha: 0.4)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.filter_alt_off, color: Color(0xFFFF1744), size: 12),
                  SizedBox(width: 3),
                  Text('Reset',
                      style: TextStyle(
                          color: Color(0xFFFF1744),
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildFiltreChip(String label, Color color, {required VoidCallback onRemove}) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.fromLTRB(9, 3, 5, 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close, color: color.withValues(alpha: 0.7), size: 14),
          ),
        ],
      ),
    );
  }

  // ── BODY ──────────────────────────────────────────────────────────
  Widget _buildBody() {
    if (_loading) {
      return const Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFF7C4DFF)),
          SizedBox(height: 14),
          Text('Analyse IA en cours...', style: TextStyle(color: Colors.white54, fontSize: 15)),
          SizedBox(height: 6),
          Text('Calcul des scores multi-critères', style: TextStyle(color: Colors.white30, fontSize: 13)),
        ],
      ));
    }
    if (_error != null) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off, color: Color(0xFFEF5350), size: 44),
          const SizedBox(height: 12),
          const Text('Impossible de charger les données', style: TextStyle(color: Colors.white)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _charger(refresh: true),
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C4DFF)),
          ),
        ],
      ));
    }
    if (_coursesAvecPartants.isEmpty) {
      final filtrageActif = _nbFiltresActifs > 0;
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(filtrageActif ? '🔎' : '🤖', style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(
            filtrageActif ? 'Aucune course ne correspond' : 'Aucun conseil disponible',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            filtrageActif
                ? 'Essayez d\'élargir vos filtres ou de les réinitialiser.'
                : 'Les partants ne sont pas encore publiés.',
            style: const TextStyle(color: Colors.white38, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          if (filtrageActif) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _resetFiltres,
              icon: const Icon(Icons.filter_alt_off, size: 16),
              label: const Text('Voir toutes les courses'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C4DFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ],
      ));
    }

    final ouvrirPari = (ZtCourse course, ZtReunion reunion) {
      try {
        context.read<PmuProvider>();
        context.read<DataRefreshService>();
        showBetSheet(
          context,
          reunion: reunion,
          course: course,
          alertService: AlertService.instance,
          onBetPlaced: () => context.read<NavigationNotifier>().goTo(6),
        );
      } catch (e) {
        debugPrint('[Conseils] Parier erreur: $e');
      }
    };

    final courses = _coursesAvecPartants;

    return ColoredBox(
      color: const Color(0xFF0D1B2A),
      child: ListView.builder(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 100),
        itemCount: courses.length,
        itemBuilder: (ctx, i) {
          final item = courses[i];
          final terminee = item.course.heureDateTime.isBefore(DateTime.now());
          final sansCote = item.course.partants.isNotEmpty &&
              item.course.partants.every((p) => p.coteDecimale >= 99);
          return _ConseilCard(
            course: item.course,
            reunion: item.reunion,
            rang: i + 1,
            cotesDisponibles: !sansCote,
            onTap: () => Navigator.push(ctx, MaterialPageRoute(
              builder: (_) => CourseDetailScreen(course: item.course, reunion: item.reunion),
            )),
            onBet: terminee ? null : () => ouvrirPari(item.course, item.reunion),
          );
        },
      ),
    );
  }

  // ── PANNEAU FILTRES (Bottom Sheet) ────────────────────────────────
  void _ouvrirPanneauFiltres() {
    // Copies de travail pour ne valider qu'au "Appliquer"
    final tmpTypes  = Set<String>.from(_selectedTypesParis);
    final tmpHipps  = Set<String>.from(_selectedHippodromes);
    final tmpDiscs  = Set<String>.from(_selectedDisciplines);
    int tmpConf     = _confianceMin;
    final confCtrl  = TextEditingController(text: tmpConf == 0 ? '0' : '$tmpConf');

    final hippodromes = _hippodromesDisponibles;
    final disciplines = _disciplinesDisponibles;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          int nbResultats = _allCoursesWithPartants.where((item) {
            final typePari = _getTypePariPourCourse(item.course);
            final score    = item.course.partantsParRangIA.isNotEmpty
                ? item.course.partantsParRangIA.first.scoreIA : 0.0;
            final hippo    = item.reunion.lieu.toUpperCase();
            final disc     = _capitalise(item.reunion.discipline);
            if (tmpTypes.isNotEmpty && !tmpTypes.contains(typePari)) return false;
            if (tmpConf > 0 && score < tmpConf)                      return false;
            if (tmpHipps.isNotEmpty && !tmpHipps.contains(hippo))    return false;
            if (tmpDiscs.isNotEmpty && !tmpDiscs.contains(disc))     return false;
            return true;
          }).length;

          // ★ v10.29 : hauteur max = 90% de l'écran, avec scroll garanti
          final screenH = MediaQuery.of(ctx).size.height;
          return Container(
            margin: const EdgeInsets.only(top: 60),
            height: screenH * 0.90,
            decoration: const BoxDecoration(
              color: Color(0xFF111F30),
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              children: [
                // Poignée
                Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Titre
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.tune, color: Color(0xFF7C4DFF), size: 20),
                      const SizedBox(width: 8),
                      const Text('Mes filtres',
                          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setModal(() {
                            tmpTypes.clear(); tmpHipps.clear(); tmpDiscs.clear();
                            tmpConf = 0; confCtrl.text = '0';
                          });
                        },
                        child: const Text('Réinitialiser', style: TextStyle(color: Color(0xFFFF5252), fontSize: 13)),
                      ),
                    ],
                  ),
                ),
                Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),

                // Contenu scrollable — v10.29 : Expanded garantit le scroll
                Expanded(
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        // ── 1. TYPE DE PARIS ─────────────────────────────
                        _sectionTitre('1. Type de Paris', '🎲'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8, runSpacing: 8,
                          children: _filtresParis.map((item) {
                            final (label, icon, color) = item;
                            final sel = tmpTypes.contains(label);
                            return GestureDetector(
                              onTap: () => setModal(() {
                                if (sel) tmpTypes.remove(label);
                                else tmpTypes.add(label);
                              }),
                              child: _chip(label: '$icon $label', color: color, selected: sel),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 18),

                        // ── 2. CONFIANCE IA MIN ──────────────────────────
                        _sectionTitre('2. Confiance IA minimale', '📊'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: confCtrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  _RangeInputFormatter(0, 99),
                                ],
                                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                                decoration: InputDecoration(
                                  hintText: '0',
                                  hintStyle: TextStyle(color: Colors.white30),
                                  suffixText: '%',
                                  suffixStyle: const TextStyle(color: Color(0xFF00E5FF), fontSize: 16),
                                  filled: true,
                                  fillColor: const Color(0xFF1A2F3D),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 1.5),
                                  ),
                                ),
                                onChanged: (v) {
                                  final val = int.tryParse(v) ?? 0;
                                  setModal(() => tmpConf = val);
                                },
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                tmpConf == 0
                                    ? 'Pas de filtre confiance — toutes les courses'
                                    : 'Courses avec ≥ $tmpConf% de confiance IA',
                                style: TextStyle(
                                    color: tmpConf > 0
                                        ? const Color(0xFF00E5FF)
                                        : Colors.white38,
                                    fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        // Raccourcis rapides
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [50, 65, 75, 80, 85].map((v) {
                            final sel = tmpConf == v;
                            return GestureDetector(
                              onTap: () => setModal(() {
                                tmpConf = sel ? 0 : v;
                                confCtrl.text = sel ? '0' : '$v';
                              }),
                              child: _chip(label: '≥ $v%', color: const Color(0xFF00E5FF), selected: sel, small: true),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 18),

                        // ── 3. HIPPODROME ────────────────────────────────
                        _sectionTitre('3. Hippodrome', '🏟️'),
                        const SizedBox(height: 8),
                        hippodromes.isEmpty
                            ? Text('Aucun hippodrome disponible', style: TextStyle(color: Colors.white38, fontSize: 13))
                            : Wrap(
                                spacing: 8, runSpacing: 8,
                                children: hippodromes.map((h) {
                                  final sel = tmpHipps.contains(h);
                                  return GestureDetector(
                                    onTap: () => setModal(() {
                                      if (sel) tmpHipps.remove(h);
                                      else tmpHipps.add(h);
                                    }),
                                    child: _chip(label: h, color: const Color(0xFF4CAF7D), selected: sel),
                                  );
                                }).toList(),
                              ),
                        const SizedBox(height: 18),

                        // ── 4. DISCIPLINE ────────────────────────────────
                        _sectionTitre('4. Discipline', '🎠'),
                        const SizedBox(height: 8),
                        disciplines.isEmpty
                            ? Text('Aucune discipline disponible', style: TextStyle(color: Colors.white38, fontSize: 13))
                            : Wrap(
                                spacing: 8, runSpacing: 8,
                                children: disciplines.map((d) {
                                  final sel = tmpDiscs.contains(d);
                                  return GestureDetector(
                                    onTap: () => setModal(() {
                                      if (sel) tmpDiscs.remove(d);
                                      else tmpDiscs.add(d);
                                    }),
                                    child: _chip(label: d, color: const Color(0xFF7C4DFF), selected: sel),
                                  );
                                }).toList(),
                              ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),

                // ── Bouton Appliquer ─────────────────────────────────
                Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 12, 20,
                      16 + MediaQuery.of(ctx).padding.bottom),
                  child: Row(
                    children: [
                      // Compteur en temps réel
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A2F3D),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                        ),
                        child: Text(
                          '$nbResultats course${nbResultats > 1 ? 's' : ''}',
                          style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _selectedTypesParis  ..clear(); _selectedTypesParis  ..addAll(tmpTypes);
                              _selectedHippodromes ..clear(); _selectedHippodromes ..addAll(tmpHipps);
                              _selectedDisciplines ..clear(); _selectedDisciplines ..addAll(tmpDiscs);
                              _confianceMin = tmpConf;
                              _confianceCtrl.text = tmpConf == 0 ? '0' : '$tmpConf';
                            });
                            _sauvegarderPrefs();
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7C4DFF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            'Appliquer ($nbResultats)',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _sectionTitre(String titre, String emoji) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Text(titre,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _chip({
    required String label,
    required Color color,
    required bool selected,
    bool small = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 10 : 13, vertical: small ? 4 : 7),
      decoration: BoxDecoration(
        color: selected ? color.withValues(alpha: 0.22) : const Color(0xFF1A2F3D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? color : Colors.white.withValues(alpha: 0.15),
          width: selected ? 1.5 : 1.0,
        ),
      ),
      child: Text(label,
          style: TextStyle(
              color: selected ? color : Colors.white54,
              fontSize: small ? 12 : 13,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
    );
  }
}

// ── Formatter pour limiter la valeur entre min et max ────────────────
class _RangeInputFormatter extends TextInputFormatter {
  final int min, max;
  _RangeInputFormatter(this.min, this.max);
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue newVal) {
    if (newVal.text.isEmpty) return newVal;
    final v = int.tryParse(newVal.text);
    if (v == null) return old;
    if (v < min) return newVal.copyWith(text: '$min');
    if (v > max) return newVal.copyWith(text: '$max');
    return newVal;
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// CARTE CONSEIL
// ──────────────────────────────────────────────────────────────────────────────
class _ConseilCard extends StatelessWidget {
  final ZtCourse course;
  final ZtReunion reunion;
  final int rang;
  final VoidCallback onTap;
  final VoidCallback? onBet;
  final bool cotesDisponibles;

  const _ConseilCard({
    required this.course,
    required this.reunion,
    required this.rang,
    required this.onTap,
    this.onBet,
    this.cotesDisponibles = true,
  });

  @override
  Widget build(BuildContext context) {
    final nbSelectionAffiche = course.isQuinte ? 5 : (course.isQuarte ? 4 : 3);
    final top3 = course.partantsParRangIA.take(nbSelectionAffiche).toList();
    final top1 = top3.isNotEmpty ? top3.first : null;
    if (top1 == null) return const SizedBox();

    final score = top1.scoreIA;
    final confianceColor = score >= 80
        ? const Color(0xFF00E676)
        : score >= 65
            ? const Color(0xFFFFEA00)
            : score >= 50
                ? const Color(0xFFFF6D00)
                : const Color(0xFFFF1744);
    final confianceLabel = score >= 80 ? 'HAUTE' : score >= 65 ? 'BONNE' : score >= 50 ? 'MOY.' : 'FAIBLE';

    final String typePari;
    final String iconPari;
    String sousTitrePari = '';
    final top2   = course.partantsParRangIA.take(2).toList();
    final top4   = course.partantsParRangIA.take(4).toList();
    final score2 = top2.length >= 2 ? top2[1].scoreIA : 0.0;
    final score3 = course.partantsParRangIA.length >= 3 ? course.partantsParRangIA[2].scoreIA : 0.0;
    final score4 = top4.length >= 4 ? top4[3].scoreIA : 0.0;
    final ecart12 = score - score2;
    final estEcartFaible = !course.isQuinte && ecart12 < 10 && score < 80;
    final estEquilibre   = !course.isQuinte && ecart12 <= 15 && score >= 60 && score2 >= 50;
    final cote = top1.coteDecimale;

    if (course.isQuinte) {
      if (score >= 75 && score2 >= 60 && score3 >= 55) {
        typePari = 'Quinté+'; iconPari = '⭐'; sousTitrePari = 'IA confiante — jouer les 5';
      } else if (score >= 65 && score2 >= 55) {
        typePari = 'Quarté+'; iconPari = '4️⃣'; sousTitrePari = 'Confiance suffisante pour 4 chevaux';
      } else if (score >= 55 && score2 >= 50) {
        typePari = 'Tiercé'; iconPari = '3️⃣'; sousTitrePari = 'Confiance limitée — éviter Quinté+';
      } else if (score >= 45) {
        typePari = 'Couplé Gagnant'; iconPari = '⚠️'; sousTitrePari = 'Confiance trop faible pour Quinté+';
      } else {
        typePari = 'À surveiller'; iconPari = '🚫'; sousTitrePari = 'Scores insuffisants — passer';
      }
    } else if (course.isQuarte) {
      if (score >= 60 && score2 >= 50 && score3 >= 40 && score4 >= 35) {
        typePari = 'Quarté+'; iconPari = '4️⃣'; sousTitrePari = 'Course officielle Quarté+ — 4 candidats IA';
      } else if (score >= 55 && score2 >= 45 && score3 >= 35) {
        typePari = 'Tiercé'; iconPari = '3️⃣'; sousTitrePari = 'Quarté+ officiel — confiance limitée, jouer Tiercé';
      } else if (score >= 45) {
        typePari = 'Couplé Gagnant'; iconPari = '⚠️'; sousTitrePari = 'Quarté+ officiel — confiance faible, jouer le Couplé';
      } else {
        typePari = 'À surveiller'; iconPari = '🚫'; sousTitrePari = 'Scores insuffisants — passer';
      }
    } else if (score >= 65 && score2 >= 60 && score3 >= 55 && score4 >= 50 && course.partants.length >= 10) {
      typePari = 'Quarté+'; iconPari = '4️⃣'; sousTitrePari = '4 candidats fiables détectés';
    } else if (estEquilibre && score >= 75) {
      typePari = 'Couplé Gagnant'; iconPari = '💑';
    } else if (estEquilibre && score >= 60) {
      typePari = 'Couplé Placé'; iconPari = '💑🎯';
    } else if (score >= 80 && cote <= 8.0) {
      typePari = 'Simple Gagnant'; iconPari = '🏆';
    } else if (score >= 80) {
      typePari = 'Gagnant+Placé'; iconPari = '🎯🏆';
    } else if (score >= 65) {
      typePari = 'Simple Placé'; iconPari = '🎯';
    } else if (score >= 50) {
      typePari = 'Gagnant+Placé'; iconPari = '🎯🏆';
    } else if (score >= 35) {
      typePari = 'Tiercé'; iconPari = '📋';
    } else {
      typePari = 'À surveiller'; iconPari = '👁️';
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2F3D),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2)),
          ],
          border: Border.all(
            color: course.isQuinte
                ? const Color(0xFFFFD700).withValues(alpha: 0.5)
                : confianceColor.withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tête
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              decoration: BoxDecoration(
                color: course.isQuinte
                    ? const Color(0xFFFFD700).withValues(alpha: 0.08)
                    : confianceColor.withValues(alpha: 0.06),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(
                children: [
                  Text(course.typeIcon, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (course.isQuinte)
                              Container(
                                margin: const EdgeInsets.only(right: 5),
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('QUINTÉ+',
                                    style: TextStyle(color: Color(0xFFFFD700), fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            Expanded(
                              child: Text(course.nom,
                                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                        Text('${reunion.lieu} • ${course.heure} • ${course.distance}m',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: confianceColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(confianceLabel,
                            style: TextStyle(color: confianceColor, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 2),
                      Text('${score.round()}%',
                          style: TextStyle(color: confianceColor, fontSize: 14, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  FavoriButton(
                    numR:       int.tryParse(reunion.code.replaceAll('R', '')) ?? 1,
                    numC:       course.numCourse,
                    nomCourse:  course.nom,
                    hippodrome: reunion.lieu,
                    scoreIA:    score,
                    heure:      course.heure,
                    distance:   course.distance,
                    prix:       course.prix,
                    size: 22,
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top 3 IA
                  Row(
                    children: top3.asMap().entries.map((e) {
                      final medals  = ['🥇', '🥈', '🥉'];
                      final mColors = [const Color(0xFFFFD700), const Color(0xFFC0C0C0), const Color(0xFFCD7F32)];
                      final p = e.value;
                      return Expanded(
                        child: Container(
                          margin: EdgeInsets.only(right: e.key < 2 ? 6 : 0),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                          decoration: BoxDecoration(
                            color: mColors[e.key].withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: mColors[e.key].withValues(alpha: 0.2)),
                          ),
                          child: Column(
                            children: [
                              Text(medals[e.key], style: const TextStyle(fontSize: 14)),
                              Text('N°${p.numero}',
                                  style: TextStyle(color: mColors[e.key], fontSize: 13, fontWeight: FontWeight.bold)),
                              Text(p.nom.split(' ').first,
                                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              // ★ v10.24 : Score de forme récente
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('${p.scoreIA.round()}pts',
                                      style: const TextStyle(color: Colors.white30, fontSize: 11)),
                                  const SizedBox(width: 3),
                                  _buildFormeBadge(p.tendanceForme),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),

                  // Badge écart faible
                  if (estEcartFaible) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6D00).withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFF6D00).withValues(alpha: 0.45)),
                      ),
                      child: Row(
                        children: [
                          const Text('⚠️', style: TextStyle(fontSize: 13)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Écart faible (${ecart12.round()} pts) — favori peu marqué, pari risqué',
                              style: const TextStyle(color: Color(0xFFFF6D00), fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Recommandation
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: confianceColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Text(iconPari, style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // ★ v10.30 : badge cliquable global
                        TypePariBadge(
                          type:      typePari,
                          numeros:   course.partantsParRangIA
                              .take(() { switch (typePari) { case 'Quinté+': return 5; case 'Quarté+': return 4; case 'Tiercé': return 3; case 'Couplé Gagnant': case 'Couplé Placé': return 2; default: return 1; } }())
                              .map((p) => p.numero).toList(),
                          nomFavori: course.partantsParRangIA.isNotEmpty
                              ? course.partantsParRangIA.first.nom
                              : null,
                        ),
                              if (sousTitrePari.isNotEmpty)
                                Text(sousTitrePari,
                                    style: TextStyle(color: confianceColor.withValues(alpha: 0.7), fontSize: 11)),
                            ],
                          ),
                        ),
                        if (course.pronosticZt.isNotEmpty)
                          Text('ZT: ${course.pronosticZt.take(3).join("-")}',
                              style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                  ),

                  // Explication IA
                  if (top1.explicationIA.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(top1.explicationIA,
                        style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],

                  // Bouton Parier
                  if (onBet != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: !cotesDisponibles
                          ? Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1C2233),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFFFB74D).withValues(alpha: 0.4)),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB74D), size: 15),
                                  SizedBox(width: 6),
                                  Text('Cotes indisponibles — Revenez 1h avant',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFFFB74D))),
                                ],
                              ),
                            )
                          : ElevatedButton.icon(
                              onPressed: onBet,
                              icon: const Icon(Icons.euro, size: 14),
                              label: const Text('Parier sur cette course',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2E7D52),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 0,
                              ),
                            ),
                    ),
                  ],

                  // Arrivée réelle
                  Builder(builder: (_) {
                    final now = DateTime.now();
                    final isTerminee = course.heureDateTime.isBefore(now.subtract(const Duration(minutes: 90)));
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: ArriveReelleWidget(
                        courseKey: buildCourseKey(
                          reunionCode: reunion.code,
                          numCourse: course.numCourse,
                          dateStr: course.dateStr,
                        ),
                        isTerminee: isTerminee,
                        heureDepart: course.heureDateTime,
                        selectionIA: course.partantsParRangIA.take(5).map((p) => p.numero).toList(),
                      ),
                    );
                  }),

                  // Numéros sélection
                  if (top3.length >= 2) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          course.isQuinte ? 'Quinté+ : ' : (course.isQuarte ? 'Quarté+ : ' : 'Sélection : '),
                          style: const TextStyle(color: Colors.white30, fontSize: 12),
                        ),
                        ...top3.map((p) => Container(
                          margin: const EdgeInsets.only(right: 4),
                          width: 24, height: 24,
                          decoration: BoxDecoration(
                            color: const Color(0xFF7C4DFF).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.4)),
                          ),
                          child: Center(
                            child: Text(p.numero,
                                style: const TextStyle(color: Color(0xFF7C4DFF), fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        )),
                        const Spacer(),
                        const Text('Analyse complète →', style: TextStyle(color: Colors.white24, fontSize: 11)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ★ v10.24 : Badge de tendance de forme récente (📈/📉/➡️)
  static Widget _buildFormeBadge(TendanceForme forme) {
    switch (forme) {
      case TendanceForme.hausse:
        return const Text('📈', style: TextStyle(fontSize: 11));
      case TendanceForme.baisse:
        return const Text('📉', style: TextStyle(fontSize: 11));
      case TendanceForme.stable:
        return const Text('➡️', style: TextStyle(fontSize: 10));
      case TendanceForme.insuffisant:
        return const SizedBox.shrink();
    }
  }
}
