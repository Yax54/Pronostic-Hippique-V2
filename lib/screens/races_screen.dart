// ═══════════════════════════════════════════════════════════════════
//  ONGLET COURSES — Programme Zone-Turf (toutes réunions + courses)
// ═══════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import '../widgets/favori_button.dart'; // ★ v9.5
import 'package:provider/provider.dart';
import '../main.dart' show NavigationNotifier;
import '../models/zt_models.dart';
import '../services/zone_turf_service.dart';
import '../services/data_refresh_service.dart';
import '../services/alert_service.dart';
import '../providers/pmu_provider.dart';
import '../services/ia_pronostic_engine.dart';
import '../widgets/bet_bottom_sheet.dart';
import '../widgets/arrivee_reelle_widget.dart';

import 'course_detail_screen.dart';

class RacesScreen extends StatefulWidget {
  const RacesScreen({super.key});
  @override
  State<RacesScreen> createState() => _RacesScreenState();
}

class _RacesScreenState extends State<RacesScreen> {
  List<ZtReunion> _reunions = [];
  bool _loading = true;
  String? _error;
  String _filtre = 'Toutes';        // Toutes / À venir / Terminées
  String _discipline = 'Toutes';    // Toutes / Trot / Plat / Obstacle
  DateTime _dateChoisie = DateTime.now(); // aujourd'hui par défaut

  @override
  void initState() {
    super.initState();
    _charger();
  }

  /// Vérifie si la date choisie est aujourd'hui
  bool get _estAujourdhui {
    final now = DateTime.now();
    return _dateChoisie.year == now.year &&
        _dateChoisie.month == now.month &&
        _dateChoisie.day == now.day;
  }

  Future<void> _charger({bool refresh = false}) async {
    // Pour aujourd'hui : charger immédiatement depuis le cache du service
    if (_estAujourdhui && !refresh) {
      final svc = context.read<DataRefreshService>();
      if (svc.reunions.isNotEmpty) {
        // Données disponibles immédiatement → pas de loader bloquant
        if (mounted) setState(() { _reunions = svc.reunions; _loading = false; _error = null; });
        return;
      }
    }

    setState(() { _loading = true; _error = null; });
    try {
      List<ZtReunion> r;
      if (_estAujourdhui) {
        // Pour aujourd'hui : utiliser le DataRefreshService (données en cache partagé)
        final svc = context.read<DataRefreshService>();
        if (refresh) await svc.refresh();
        r = svc.reunions.isNotEmpty
            ? svc.reunions
            : await ZoneTurfService.chargerProgramme(forceRefresh: refresh, date: _dateChoisie);
      } else {
        // Pour une autre date : appel direct (pas dans le cache global)
        r = await ZoneTurfService.chargerProgramme(
          forceRefresh: refresh,
          date: _dateChoisie,
        );
      }
      if (mounted) setState(() { _reunions = r; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _choisirDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateChoisie,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 7)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF4CAF7D),
            onPrimary: Colors.white,
            surface: Color(0xFF1A3A5C),
            onSurface: Colors.white,
          ),
          dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF0D1B2A)),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _dateChoisie = picked);
      _charger(refresh: true);
    }
  }

  // Toutes les courses aplaties avec leur réunion
  List<({ZtCourse course, ZtReunion reunion})> get _toutesLesCourses {
    final list = <({ZtCourse course, ZtReunion reunion})>[];
    for (final r in _reunions) {
      for (final c in r.courses) {
        list.add((course: c, reunion: r));
      }
    }
    // Tri par heure
    list.sort((a, b) => a.course.heure.compareTo(b.course.heure));
    return list;
  }

  List<({ZtCourse course, ZtReunion reunion})> get _coursesFiltrees {
    final all = _toutesLesCourses;

    return all.where((item) {
      final c = item.course;
      final r = item.reunion;

      // Filtre discipline
      if (_discipline != 'Toutes') {
        final spec = r.discipline.toUpperCase();
        if (_discipline == 'Trot' && !spec.contains('TROT')) return false;
        if (_discipline == 'Plat' && !spec.contains('PLAT') && !spec.contains('GALOP')) return false;
        if (_discipline == 'Obstacle' && !spec.contains('OBSTACLE') && !spec.contains('HAIE') && !spec.contains('STEEPLE')) return false;
      }

      // Filtrage par statut
      if (_filtre == 'À venir') {
        return c.heureDateTime.isAfter(DateTime.now());
      }
      if (_filtre == 'Terminées') {
        return c.heureDateTime.isBefore(DateTime.now());
      }

      return true;
    }).toList();
  }

  bool _estTerminee(ZtCourse c) {
    return c.heureDateTime.isBefore(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    // Si on est sur la date d'aujourd'hui, on écoute le DataRefreshService
    // pour se reconstruire automatiquement à chaque refresh de 15 min
    if (_estAujourdhui) {
      final svc = context.watch<DataRefreshService>();
      // Synchroniser les réunions si le service a de nouvelles données
      if (!svc.loading && svc.reunions.isNotEmpty && svc.lastError == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _estAujourdhui) {
            setState(() {
              _reunions = svc.reunions;
              _loading = false;
              _error = null;
            });
          }
        });
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildFiltres(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final total = _toutesLesCourses.length;
    final jours = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    final mois = ['Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin', 'Juil', 'Août', 'Sep', 'Oct', 'Nov', 'Déc'];
    final dateLabel = '${jours[_dateChoisie.weekday - 1]} ${_dateChoisie.day} ${mois[_dateChoisie.month - 1]}';
    final demain = DateTime.now().add(const Duration(days: 1));
    final estDemain = _dateChoisie.day == demain.day &&
        _dateChoisie.month == demain.month &&
        _dateChoisie.year == demain.year;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D1B2A), Color(0xFF1A3A5C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF7D).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('🏁', style: TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Programme des Courses',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                    Text('$total courses • PMU FR',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 13)),
                  ],
                ),
              ),
              if (_loading)
                const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(color: Color(0xFF4CAF7D), strokeWidth: 2)),
              IconButton(
                onPressed: () => _charger(refresh: true),
                icon: const Icon(Icons.refresh, color: Color(0xFF4CAF7D), size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Sélecteur de date
          Row(
            children: [
              // Bouton date précédente
              GestureDetector(
                onTap: () {
                  final prev = _dateChoisie.subtract(const Duration(days: 1));
                  if (prev.isAfter(DateTime.now().subtract(const Duration(days: 1)))) {
                    setState(() => _dateChoisie = prev);
                    _charger(refresh: true);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2F3D),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.chevron_left, color: Color(0xFF4CAF7D), size: 18),
                ),
              ),
              const SizedBox(width: 8),
              // Bouton date principale (ouvre le picker)
              Expanded(
                child: GestureDetector(
                  onTap: _choisirDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF7D).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF4CAF7D).withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.calendar_today, color: Color(0xFF4CAF7D), size: 14),
                        const SizedBox(width: 6),
                        Text(
                          estDemain ? '📅 Demain — $dateLabel' : '📅 $dateLabel',
                          style: const TextStyle(
                            color: Color(0xFF4CAF7D),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (!estDemain) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.edit, color: Color(0xFF4CAF7D), size: 12),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Bouton date suivante
              GestureDetector(
                onTap: () {
                  final next = _dateChoisie.add(const Duration(days: 1));
                  if (next.isBefore(DateTime.now().add(const Duration(days: 8)))) {
                    setState(() => _dateChoisie = next);
                    _charger(refresh: true);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2F3D),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.chevron_right, color: Color(0xFF4CAF7D), size: 18),
                ),
              ),
              // Bouton retour à demain (si on n'est pas déjà sur demain)
              if (!estDemain) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    setState(() => _dateChoisie = demain);
                    _charger(refresh: true);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2F3D),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: const Text('J+1', style: TextStyle(color: Colors.white54, fontSize: 14)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFiltres() {
    return Column(
      children: [
        // Filtre statut
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Row(
            children: ['Toutes', 'À venir', 'Terminées'].map((f) {
              final sel = _filtre == f;
              return GestureDetector(
                onTap: () => setState(() => _filtre = f),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? const Color(0xFF4CAF7D).withValues(alpha: 0.2) : const Color(0xFF1A2F3D),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: sel ? const Color(0xFF4CAF7D) : Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Text(f, style: TextStyle(
                      color: sel ? const Color(0xFF4CAF7D) : Colors.white54,
                      fontSize: 14, fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                ),
              );
            }).toList(),
          ),
        ),
        // Filtre discipline
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Row(
            children: ['Toutes', 'Trot', 'Plat', 'Obstacle'].map((d) {
              final sel = _discipline == d;
              final icons = {'Toutes': '🏆', 'Trot': '🐎', 'Plat': '🏇', 'Obstacle': '🚧'};
              return GestureDetector(
                onTap: () => setState(() => _discipline = d),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: sel ? const Color(0xFF7C4DFF).withValues(alpha: 0.2) : const Color(0xFF1A2F3D),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: sel ? const Color(0xFF7C4DFF) : Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Text('${icons[d]} $d', style: TextStyle(
                      color: sel ? const Color(0xFF7C4DFF) : Colors.white38,
                      fontSize: 13, fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFF4CAF7D)),
          SizedBox(height: 14),
          Text('Chargement PMU...', style: TextStyle(color: Colors.white54)),
        ],
      ));
    }
    if (_error != null) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off, color: Color(0xFFEF5350), size: 44),
          const SizedBox(height: 12),
          const Text('Impossible de charger le programme', style: TextStyle(color: Colors.white, fontSize: 15)),
          const SizedBox(height: 6),
          Text(_error!, style: const TextStyle(color: Colors.white38, fontSize: 14), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _charger(refresh: true),
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D52)),
          ),
        ],
      ));
    }

    final courses = _coursesFiltrees;
    if (courses.isEmpty) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🏇', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text('Aucune course $_filtre', style: const TextStyle(color: Colors.white54, fontSize: 14)),
        ],
      ));
    }

    // ★ Fix écran gris : capturer les Providers ici (contexte Scaffold avec Providers)
    // avant d'entrer dans le ListView.builder dont le ctx n'a pas accès aux Providers.
    final ouvrirPari = (ZtCourse course, ZtReunion reunion) {
      try {
        context.read<PmuProvider>();
        context.read<DataRefreshService>();
        showBetSheet(
          context,
          reunion: reunion,
          course: course,
          alertService: AlertService.instance,
          onBetPlaced: () => context.read<NavigationNotifier>().goToMesParis(),
        );
      } catch (e) {
        debugPrint('[Races] Parier erreur: $e');
      }
    };

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
      itemCount: courses.length,
      itemBuilder: (ctx, i) {
        final item = courses[i];
        final sansCote = item.course.partants.isNotEmpty &&
            item.course.partants.every((p) => p.coteDecimale >= 99);
        return _CourseCard(
          course: item.course,
          reunion: item.reunion,
          terminee: _estTerminee(item.course),
          cotesDisponibles: !sansCote,
          onTap: () => Navigator.push(ctx, MaterialPageRoute(
            builder: (_) => CourseDetailScreen(course: item.course, reunion: item.reunion),
          )),
          onBet: _estTerminee(item.course) ? null : () => ouvrirPari(item.course, item.reunion),
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
class _CourseCard extends StatelessWidget {
  final ZtCourse course;
  final ZtReunion reunion;
  final bool terminee;
  final VoidCallback onTap;
  final VoidCallback? onBet;
  final bool cotesDisponibles;

  const _CourseCard({
    required this.course,
    required this.reunion,
    required this.terminee,
    required this.onTap,
    this.onBet,
    this.cotesDisponibles = true,
  });

  @override
  Widget build(BuildContext context) {
    final discColor = Color(reunion.disciplineColor);
    final top3 = course.partantsParRangIA.take(3).toList();

    // Calcul statut précis
    final heure = course.heureDateTime;
    final now = DateTime.now();
    final diffMin = heure.difference(now).inMinutes;
    final enCours = diffMin <= 0 && diffMin >= -90;   // 0 à -90 min = en cours
    final vraiTerminee = diffMin < -90;                // > 90 min passés = terminée

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2F3D),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: course.isQuinte
                ? const Color(0xFFFFD700).withValues(alpha: 0.5)
                : terminee
                    ? Colors.white.withValues(alpha: 0.08)
                    : discColor.withValues(alpha: 0.3),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ligne 1 : heure + nom + statut
              Row(
                children: [
                  // Heure
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: terminee
                          ? Colors.white.withValues(alpha: 0.06)
                          : discColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      course.heure,
                      style: TextStyle(
                        color: terminee ? Colors.white38 : discColor,
                        fontSize: 15, fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      children: [
                        if (course.isQuinte)
                          Container(
                            margin: const EdgeInsets.only(right: 5),
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('Q+', style: TextStyle(color: Color(0xFFFFD700), fontSize: 14, fontWeight: FontWeight.bold)),
                          ),
                        Expanded(
                          child: Text(course.nom,
                              style: TextStyle(
                                color: terminee ? Colors.white54 : Colors.white,
                                fontSize: 16, fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                  // ★ v9.5 : Bouton favori
                  FavoriButton(
                    numR:      int.tryParse(reunion.code.replaceAll('R', '')) ?? 1,
                    numC:      course.numCourse,
                    nomCourse: course.nom,
                    hippodrome: reunion.lieu,
                    scoreIA:   course.partantsParRangIA.isNotEmpty
                        ? course.partantsParRangIA.first.scoreIA : 0.0,
                    heure:     course.heure,
                    distance:  course.distance,
                    prix:      course.prix,
                    size: 20,
                  ),
                  const SizedBox(width: 4),
                  // Badge statut — carré blanc cassé + barre rouge diagonale pour terminée
                  Builder(builder: (_) {
                    if (vraiTerminee) {
                      return SizedBox(
                        width: 36,
                        height: 36,
                        child: CustomPaint(
                          painter: _TermineeBadgePainter(),
                        ),
                      );
                    }
                    if (enCours) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFB300).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFFB300).withValues(alpha: 0.7)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.radio_button_checked, color: Color(0xFFFFB300), size: 9),
                            SizedBox(width: 4),
                            Text('EN COURS', style: TextStyle(
                              color: Color(0xFFFFB300), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                          ],
                        ),
                      );
                    }
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF29B6F6).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF29B6F6).withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        diffMin > 60
                            ? '${(diffMin / 60).floor()}h${(diffMin % 60).toString().padLeft(2,'0')}'
                            : '${diffMin}min',
                        style: const TextStyle(
                          color: Color(0xFF29B6F6), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 7),

              // Ligne 2 : lieu + discipline + distance + dotation + partants
              Wrap(
                spacing: 10,
                runSpacing: 4,
                children: [
                  _info(reunion.disciplineIcon, reunion.lieu),
                  _info('📏', '${course.distance}m'),
                  if (course.prix.isNotEmpty && course.prix != '0' && course.prix != '0€')
                    _info('💰', course.prix),
                  _info('🐴', '${course.partants.length} partants'),
                  if (course.type.isNotEmpty)
                    _info('🏷️', course.type),
                ],
              ),

              // Ligne 3 : Top 3 IA + badge confiance
              if (top3.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C4DFF).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Ligne 1 : label IA + badge confiance (TOUJOURS visible)
                      Row(
                        children: [
                          const Text('🤖 IA', style: TextStyle(color: Color(0xFF7C4DFF), fontSize: 14, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 6),
                          // Badge confiance — PRIORITÉ visuelle
                          _confianceBadge(course.confianceIA),
                          const Spacer(),
                          // Score top1 si disponible
                          if (top3.isNotEmpty && top3.first.scoreIA > 0)
                            Text(
                              'N°${top3.first.numero} — ${top3.first.scoreIA.round()}/100',
                              style: const TextStyle(color: Colors.white38, fontSize: 13),
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      // Ligne 2 : chips top3 chevaux
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: top3.asMap().entries.map((e) {
                          final medals = ['🥇', '🥈', '🥉'];
                          final p = e.value;
                          return _iaChip(
                            '${medals[e.key]} N°${p.numero}',
                            p.nom.split(' ').first,
                            p.scoreIA,
                          );
                        }).toList(),
                      ),
                      // Ligne pronostic PMU — toujours affichée
                      const SizedBox(height: 6),
                      Builder(builder: (ctx) {
                        final pmu = course.pronosticPMU;
                        if (pmu.isEmpty) {
                          // Pas encore de cotes : afficher message
                          return Row(children: [
                            const Text('🏇 PMU : ', style: TextStyle(
                              color: Color(0xFFFFD700), fontSize: 14,
                              fontWeight: FontWeight.bold)),
                            const Text('cotes disponibles avant la course',
                              style: TextStyle(color: Colors.white30, fontSize: 12,
                                fontStyle: FontStyle.italic)),
                          ]);
                        }
                        return Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: [
                            const Text('🏇 PMU : ', style: TextStyle(
                              color: Color(0xFFFFD700), fontSize: 14,
                              fontWeight: FontWeight.bold)),
                            ...pmu.take(5).toList().asMap().entries.map((e) {
                              final isFirst = e.key == 0;
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isFirst
                                      ? const Color(0xFFFFD700).withValues(alpha: 0.2)
                                      : Colors.white.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isFirst
                                        ? const Color(0xFFFFD700).withValues(alpha: 0.6)
                                        : Colors.white24,
                                  ),
                                ),
                                child: Text('N°${e.value}',
                                  style: TextStyle(
                                    color: isFirst ? const Color(0xFFFFD700) : Colors.white60,
                                    fontSize: 13, fontWeight: isFirst ? FontWeight.bold : FontWeight.normal,
                                  )),
                              );
                            }),
                          ],
                        );
                      }),
                      // ── Conseil IA — type de pari recommandé ──────────────
                      const SizedBox(height: 8),
                      Builder(builder: (_) {
                        if (top3.isEmpty) return const SizedBox.shrink();
                        final conseil = IaPronosticEngine.determinerConseilPublic(course);
                        // Couleur selon type de pari
                        final Color conseilColor;
                        final IconData conseilIcon;
                        final cl = conseil.toLowerCase();
                        if (cl.contains('quinté')) {
                          conseilColor = const Color(0xFFFFD700);
                          conseilIcon = Icons.star;
                        } else if (cl.contains('quarté') || cl.contains('tiercé')) {
                          conseilColor = const Color(0xFF4CAF7D);
                          conseilIcon = Icons.emoji_events;
                        } else if (cl.contains('couplé')) {
                          conseilColor = const Color(0xFF29B6F6);
                          conseilIcon = Icons.looks_two;
                        } else {
                          conseilColor = const Color(0xFFFF9800);
                          conseilIcon = Icons.looks_one;
                        }
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: conseilColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: conseilColor.withValues(alpha: 0.40)),
                          ),
                          child: Row(
                            children: [
                              Icon(conseilIcon, color: conseilColor, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  conseil,
                                  style: TextStyle(
                                    color: conseilColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],

              // ── Arrivée réelle PMU ──
              ArriveReelleWidget(
                courseKey: buildCourseKey(
                  reunionCode: reunion.code,
                  numCourse: course.numCourse,
                  dateStr: course.dateStr,
                ),
                isTerminee: vraiTerminee,
                heureDepart: course.heureDateTime, // ★ v9.6
                selectionIA: course.partantsParRangIA
                    .take(5)
                    .map((p) => p.numero)
                    .toList(),
              ),

              // ── Bouton Parier ──
              if (!terminee && onBet != null) ...[          
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
                            Text(
                              'Cotes indisponibles — Revenez 1h avant',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFFFB74D)),
                            ),
                          ],
                        ),
                      )
                    : ElevatedButton.icon(
                        onPressed: onBet,
                        icon: const Icon(Icons.euro, size: 15),
                        label: const Text(
                          'Parier sur cette course',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _info(String icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(icon, style: const TextStyle(fontSize: 13)),
      const SizedBox(width: 3),
      Text(text, style: const TextStyle(color: Colors.white54, fontSize: 13)),
    ],
  );

  /// Chip IA pour un cheval (médaille + nom + score)
  Widget _iaChip(String medal, String nom, double score) {
    final Color scoreColor = score >= 80
        ? const Color(0xFF4CAF7D)
        : score >= 65
            ? const Color(0xFFFFD54F)
            : score >= 50
                ? const Color(0xFFFF9800)
                : const Color(0xFFEF5350);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: scoreColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scoreColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(medal, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 4),
          Text(
            nom.length > 9 ? '${nom.substring(0, 9)}…' : nom,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if (score > 0) ...[ 
            const SizedBox(width: 5),
            Text(
              '${score.toStringAsFixed(0)}%',
              style: TextStyle(color: scoreColor, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ],
      ),
    );
  }

  /// Badge confiance globale IA — toujours affiché
  /// Palette : vert fort / jaune / orange / rouge — JAMAIS vert pâle ou cyan (réservés au statut)
  Widget _confianceBadge(double confiance) {
    // Si pas de données IA, badge neutre
    if (confiance <= 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white12),
        ),
        child: const Text('IA en calc.', style: TextStyle(color: Colors.white30, fontSize: 12)),
      );
    }

    // Palette distincte : PAS de vert (#4CAF7D = réservé IA score haut)
    // Utilise des teintes plus saturées / contrastées
    final Color badgeColor;
    final String label;
    final IconData icon;

    if (confiance >= 80) {
      badgeColor = const Color(0xFF00E676); // vert vif néon
      label = 'FORTE';
      icon = Icons.trending_up;
    } else if (confiance >= 65) {
      badgeColor = const Color(0xFFFFEA00); // jaune vif
      label = 'BONNE';
      icon = Icons.trending_flat;
    } else if (confiance >= 50) {
      badgeColor = const Color(0xFFFF6D00); // orange vif
      label = 'MOY.';
      icon = Icons.trending_down;
    } else {
      badgeColor = const Color(0xFFFF1744); // rouge vif
      label = 'FAIBLE';
      icon = Icons.trending_down;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeColor.withValues(alpha: 0.7), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: badgeColor, size: 13),
          const SizedBox(width: 4),
          Text(
            '${confiance.toStringAsFixed(0)}% $label',
            style: TextStyle(
              color: badgeColor,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  CustomPainter — carré blanc cassé avec barre rouge diagonale
// ═══════════════════════════════════════════════════════════
class _TermineeBadgePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rectPaint = Paint()
      ..color = const Color(0xFFF5F0E8) // blanc cassé
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = const Color(0xFFCCC5B5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final linePaint = Paint()
      ..color = const Color(0xFFD32F2F) // rouge
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(6),
    );
    canvas.drawRRect(rect, rectPaint);
    canvas.drawRRect(rect, borderPaint);
    // Barre diagonale (haut-gauche → bas-droit)
    canvas.drawLine(
      Offset(size.width * 0.12, size.height * 0.12),
      Offset(size.width * 0.88, size.height * 0.88),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
