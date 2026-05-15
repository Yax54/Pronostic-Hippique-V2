import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../main.dart' show NavigationNotifier; // ★ v9.92 : navigation En attente → Suivi
import '../widgets/favori_button.dart'; // ★ v9.5
import '../services/data_refresh_service.dart';
import 'course_detail_screen.dart';
import '../providers/pmu_provider.dart';
import '../utils/format_euros.dart';
import '../models/pmu_models.dart';
import '../models/zt_models.dart';
import '../services/alert_service.dart';
import '../services/zone_turf_service.dart';
import '../services/gain_calculator.dart';
import '../services/pmu_api_service.dart';
import '../widgets/share_card_generator.dart';
import '../widgets/paris/paris_common_widgets.dart';
import '../widgets/paris/alert_widgets.dart';
import '../widgets/paris/resultat_dialog.dart';
import '../widgets/paris/direct_links_sheet.dart';
import '../widgets/paris/alert_settings_widgets.dart';
import 'paris_detail_screen.dart';

import '../services/ia_personality_service.dart'; // ★ v9.85 IA bulle
import '../widgets/ia/ia_bubble_widget.dart';      // ★ v9.85 IA bulle

// ★ v9.85 : deepLinkCourseKeyNotifier retiré de main.dart — notifier local
final deepLinkCourseKeyNotifier = ValueNotifier<String?>(null);

/// ═══════════════════════════════════════════════════════════════════════════
/// MesPariScreen — Suivi en temps réel des courses parisées v3.0
///
/// Fonctionnalités :
///  • Source de données : Zone-Turf (données réelles) + fallback PMU
///  • Demande de permission notifications Android 13+ intégrée
///  • Paramètres d'alertes complets et configurables
///  • Suivi en temps réel avec countdown live
///  • Liens directs PMU.fr / Equidia
///  • Centre de notifications in-app (historique)
///  • Saisie manuelle du résultat (gagnant / perdu + gain)
/// ═══════════════════════════════════════════════════════════════════════════

class MesPariScreen extends StatefulWidget {
  // ★ v9.92 : initialTab permet d'ouvrir directement un onglet spécifique
  // 0=Favoris 1=Suivi 2=Alertes 3=Historique
  final int initialTab;
  const MesPariScreen({super.key, this.initialTab = 0});

  @override
  State<MesPariScreen> createState() => _MesPariScreenState();
}

class _MesPariScreenState extends State<MesPariScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this,
        initialIndex: widget.initialTab.clamp(0, 3));
    // Rafraîchir le countdown chaque 30 secondes
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    // Vérifier l'état des permissions au démarrage
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AlertService.instance.checkPermissionStatus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ★ v9.92 fix : MesPariScreen est persistant (jamais recréé) — on écoute
    // didChangeDependencies qui est appelé à chaque fois que l'écran devient actif.
    // Quand NavigationNotifier.requestMesParisSuivi() est appelé, on bascule sur Suivi.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final navNotifier = context.read<NavigationNotifier>();
        final pending = navNotifier.mesParisPendingTab;
        if (pending > 0) {
          _tabCtrl.animateTo(pending.clamp(0, 3));
          navNotifier.clearMesParisPendingTab();
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: AlertService.instance,
      child: Consumer<AlertService>(
        builder: (context, alertSvc, _) {
          final unread = alertSvc.unreadCount;
          final hasPermission = alertSvc.hasNotificationPermission;
          final permStatus = alertSvc.permissionStatus;

          return Scaffold(
            backgroundColor: const Color(0xFF0A1628),
            appBar: AppBar(
              backgroundColor: const Color(0xFF0A1628),
              elevation: 0,
              title: const Row(children: [
                Text('🎯', style: TextStyle(fontSize: 20)),
                SizedBox(width: 8),
                Text('Mes Paris & Alertes',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ]),
              actions: [
                // Icône permission notifications
                if (permStatus != NotificationPermissionStatus.notChecked)
                  Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: IconButton(
                      icon: Icon(
                        hasPermission
                            ? Icons.notifications_active
                            : Icons.notifications_off,
                        color: hasPermission
                            ? const Color(0xFF4CAF7D)
                            : const Color(0xFFEF5350),
                        size: 22,
                      ),
                      onPressed: () => hasPermission
                          ? null
                          : _demanderPermissionsNotification(context, alertSvc),
                      tooltip: hasPermission
                          ? 'Notifications actives'
                          : 'Activer les notifications',
                    ),
                  ),
                // Badge alertes non lues
                Stack(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_outlined,
                          color: Color(0xFF4CAF7D)),
                      onPressed: () => _tabCtrl.animateTo(3), // ★ v10.1 : onglet Historique (index 3)
                      tooltip: 'Historique des alertes',
                    ),
                    if (unread > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF5350),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            unread > 9 ? '9+' : '$unread',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                  ],
                ),
                // Paramètres alertes
                IconButton(
                  icon: const Icon(Icons.tune, color: Color(0xFFFFD700)),
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    backgroundColor: const Color(0xFF0A1628),
                    shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                    isScrollControlled: true,
                    builder: (_) => ChangeNotifierProvider.value(
                      value: alertSvc,
                      child: const AlertSettingsSheet(),
                    ),
                  ),
                  tooltip: 'Paramètres alertes',
                ),
              ],
              bottom: TabBar(
                controller: _tabCtrl,
                indicatorColor: const Color(0xFFFFD700),
                labelColor: const Color(0xFFFFD700),
                unselectedLabelColor: Colors.white38,
                indicatorWeight: 3,
                tabs: [
                  const Tab(icon: Icon(Icons.star_rounded, size: 16), text: 'Favoris'),
                  const Tab(icon: Icon(Icons.track_changes, size: 16), text: 'Suivi'),
                  const Tab(icon: Icon(Icons.tune, size: 16), text: 'Alertes'),
                  Tab(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.notifications, size: 16),
                      const SizedBox(width: 4),
                      const Flexible(child: Text('Historique', overflow: TextOverflow.ellipsis)),
                      if (unread > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF5350),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('$unread',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ]),
                  ),
                ],
              ),
            ),
            body: TabBarView(
              controller: _tabCtrl,
              children: [
                _FavorisTab(alertSvc: alertSvc),
                _CoursesTab(alertSvc: alertSvc),
                AlertSettingsTab(alertSvc: alertSvc),
                AlertesTab(alertSvc: alertSvc),
              ],
            ),
            // FAB : ajouter une course depuis le programme PMU
            floatingActionButton: _tabCtrl.index == 0
                ? FloatingActionButton.extended(
                    backgroundColor: const Color(0xFF2E7D52),
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('Suivre une course',
                        style: TextStyle(color: Colors.white)),
                    onPressed: () => _showAjouterCourseDialog(context, alertSvc),
                  )
                : null,
          );
        },
      ),
    );
  }

  // ── Dialog ajout de course depuis Zone-Turf ──────────────────────────────
  void _showAjouterCourseDialog(BuildContext context, AlertService alertSvc) async {
    // Essayer d'abord Zone-Turf
    List<_CourseSuivi> courses = [];
    
    try {
      final reunions = await ZoneTurfService.chargerProgramme();
      final now = DateTime.now();
      
      for (final reunion in reunions) {
        for (final course in reunion.courses) {
          final dt = course.heureDateTime;
          if (dt.isAfter(now)) {
            courses.add(_CourseSuivi(
              numReunion: int.tryParse(reunion.code.replaceAll('R', '')) ?? 1,
              numCourse: course.numCourse,
              nomCourse: course.nom,
              hippodrome: reunion.lieu,
              heureDepart: dt,
              discipline: course.typeIcon,
              isQuinte: course.isQuinte,
              partantsIA: course.partants,
            ));
          }
        }
      }
    } catch (_) {}

    // Fallback PMU si Zone-Turf vide
    if (courses.isEmpty && context.mounted) {
      try {
        final provider = context.read<PmuProvider>();
        final pmuCourses = provider.allCourses
            .where((c) => c.status != CourseStatus.terminee)
            .toList()
          ..sort((a, b) => a.heureDepart.compareTo(b.heureDepart));
        
        courses = pmuCourses.map((c) {
          final reunion = provider.reunions.firstWhere(
            (r) => r.numOfficiel == c.numReunion,
            orElse: () => PmuReunion(
              numOfficiel: c.numReunion,
              hippodrome: 'Hippodrome',
              hippodromeCode: 'HIP',
              dateStr: '',
              courses: [],
            ),
          );
          return _CourseSuivi(
            numReunion: c.numReunion,
            numCourse: c.numOrdre,
            nomCourse: c.libelle,
            hippodrome: reunion.hippodrome,
            heureDepart: c.heureDepart,
            discipline: '🏇',
            isQuinte: false,
            partantsIA: [],
          );
        }).toList();
      } catch (_) {}
    }

    if (!context.mounted) return;

    if (courses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucune course à venir disponible. Réessayez dans quelques instants.'),
          backgroundColor: Color(0xFF1B5E20),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A1628),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (_) => _AjouterCourseSheet(
        courses: courses,
        alertSvc: alertSvc,
      ),
    );
  }

  // ── Demander les permissions de notification ──────────────────────────────
  void _demanderPermissionsNotification(BuildContext ctx, AlertService alertSvc) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0A1628),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(children: [
          Icon(Icons.notifications, color: Color(0xFFFFD700)),
          SizedBox(width: 8),
          Text('Notifications', style: TextStyle(color: Colors.white, fontSize: 16)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEF5350).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEF5350).withValues(alpha: 0.4)),
            ),
            child: const Column(children: [
              Icon(Icons.notifications_off, color: Color(0xFFEF5350), size: 36),
              SizedBox(height: 10),
              Text(
                'Les notifications sont désactivées',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                'Pour recevoir des alertes avant le départ des courses et connaître vos résultats, activez les notifications.',
                style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ]),
          ),
          const SizedBox(height: 14),
          const Text(
            '💡 Comment activer :\nParamètres → Applications → Pronostic Hippique → Notifications → Activer',
            style: TextStyle(color: Colors.white38, fontSize: 16, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Plus tard', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.settings, size: 16),
            label: const Text('Ouvrir les paramètres'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await alertSvc.ouvrirParametresNotification();
            },
          ),
        ],
      ),
    );
  }
}

// ── Modèle interne pour une course à suivre ──────────────────────────────────
class _CourseSuivi {
  final int numReunion;
  final int numCourse;
  final String nomCourse;
  final String hippodrome;
  final DateTime heureDepart;
  final String discipline;
  final bool isQuinte;
  final List<ZtPartant> partantsIA;

  const _CourseSuivi({
    required this.numReunion,
    required this.numCourse,
    required this.nomCourse,
    required this.hippodrome,
    required this.heureDepart,
    required this.discipline,
    required this.isQuinte,
    required this.partantsIA,
  });

  String get heureStr {
    return '${heureDepart.hour.toString().padLeft(2, '0')}h${heureDepart.minute.toString().padLeft(2, '0')}';
  }

  String get dateStr {
    final d = heureDepart;
    const jours = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    return '${jours[d.weekday - 1]} ${d.day}/${d.month}';
  }

  /// Clé avec date (format ddmmyyyy) — même format que TrackedCourse.key et buildCourseKey()
  String get key {
    final d = heureDepart;
    final ds = '${d.day.toString().padLeft(2,'0')}${d.month.toString().padLeft(2,'0')}${d.year}';
    return 'R${numReunion}C${numCourse}_$ds';
  }

  ZtPartant? get favoriIA {
    if (partantsIA.isEmpty) return null;
    return partantsIA.reduce((a, b) => a.scoreIA >= b.scoreIA ? a : b);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Onglet 1 : Courses suivies
// ══════════════════════════════════════════════════════════════════════════════


// ══════════════════════════════════════════════════════════════════════════════
// _FavorisTab — Liste des courses mises en favoris ★ v9.5
// ══════════════════════════════════════════════════════════════════════════════
class _FavorisTab extends StatefulWidget {
  final dynamic alertSvc;
  const _FavorisTab({required this.alertSvc});
  @override
  State<_FavorisTab> createState() => _FavorisTabState();
}

class _FavorisTabState extends State<_FavorisTab> {
  // Clé centralisée dans AlertService — on utilise la même constante pour cohérence
  static const _prefsKey = AlertService.favoritesKey;
  List<Map<String, dynamic>> _favoris = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _charger();
    // ★ Se rafraîchir quand une étoile change dans un autre écran
    FavoriButton.syncNotifier.addListener(_onFavoriChange);
  }

  @override
  void dispose() {
    FavoriButton.syncNotifier.removeListener(_onFavoriChange);
    super.dispose();
  }

  void _onFavoriChange() {
    if (mounted) _charger();
  }

  Future<void> _charger() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey) ?? '[]';
      final list = (json.decode(raw) as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      // Trier par heure si disponible
      list.sort((a, b) {
        final ha = a['heure'] as String? ?? '';
        final hb = b['heure'] as String? ?? '';
        return ha.compareTo(hb);
      });
      if (mounted) setState(() { _favoris = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _supprimer(int index) async {
    final fav = _favoris[index];
    setState(() => _favoris.removeAt(index));
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey) ?? '[]';
      final list = (json.decode(raw) as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      list.removeWhere((e) =>
          e['numR'] == fav['numR'] && e['numC'] == fav['numC']);
      await prefs.setString(_prefsKey, json.encode(list));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700)));
    }

    if (_favoris.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.star_outline_rounded, color: Colors.white24, size: 64),
              const SizedBox(height: 16),
              const Text('Aucun favori',
                  style: TextStyle(color: Colors.white54, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                "Appuyez sur l'étoile ⭐ sur n'importe quelle course pour l'ajouter ici.",
                style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _charger,
      color: const Color(0xFFFFD700),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
        itemCount: _favoris.length,
        itemBuilder: (ctx, i) => _buildFavoriCard(ctx, _favoris[i], i),
      ),
    );
  }

  void _ouvrirCours(BuildContext context, int numR, int numC) {
    // Chercher la course dans DataRefreshService (données chargées en mémoire)
    final reunions = DataRefreshService.instance.reunions;
    for (final reunion in reunions) {
      final numOfficiel = int.tryParse(reunion.code.replaceAll('R', '')) ?? 0;
      if (numOfficiel != numR) continue;
      for (final course in reunion.courses) {
        if (course.numCourse == numC) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => CourseDetailScreen(course: course, reunion: reunion),
          ));
          return;
        }
      }
    }
    // Course non trouvée (données pas encore chargées)
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Course non disponible — rechargez le programme'),
      backgroundColor: const Color(0xFF1A1A2E),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Widget _buildFavoriCard(BuildContext context, Map<String, dynamic> fav, int index) {
    final nomCourse  = fav['nomCourse']  as String? ?? 'Course';
    final hippodrome = fav['hippodrome'] as String? ?? '';
    final heure      = fav['heure']      as String? ?? '';
    final scoreIA    = (fav['scoreIA']   as num?)?.toDouble() ?? 0.0;
    final dejaParI   = fav['dejaParI']   as bool? ?? false;
    final numR       = fav['numR']       as int? ?? 0;
    final numC       = fav['numC']       as int? ?? 0;

    return Dismissible(
      key: Key('fav_${numR}_$numC'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, color: Colors.redAccent, size: 24),
            SizedBox(height: 4),
            Text('Supprimer', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
          ],
        ),
      ),
      onDismissed: (_) => _supprimer(index),
      child: GestureDetector(
        onTap: () => _ouvrirCours(context, numR, numC),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFFFFD700).withValues(alpha: 0.10),
                const Color(0xFF0D1B2A),
              ],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: dejaParI
                  ? Colors.green.withValues(alpha: 0.4)
                  : const Color(0xFFFFD700).withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              // Icône étoile
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                  border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.4)),
                ),
                child: Center(child: Text(
                  dejaParI ? '✅' : '⭐',
                  style: const TextStyle(fontSize: 20))),
              ),
              const SizedBox(width: 12),
              // Infos course
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nomCourse,
                      style: const TextStyle(
                        color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(Icons.location_on_rounded, color: Colors.white38, size: 13),
                      const SizedBox(width: 3),
                      Text(hippodrome,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
                      if (heure.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Icon(Icons.access_time_rounded, color: const Color(0xFF4CAF7D), size: 13),
                        const SizedBox(width: 3),
                        Text(heure,
                          style: const TextStyle(color: Color(0xFF4CAF7D),
                              fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ]),
                    if (dejaParI)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Paris placé',
                          style: TextStyle(color: Colors.green.withValues(alpha: 0.8),
                              fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              ),
              // Score IA + flèche
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (scoreIA > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.4)),
                      ),
                      child: Text('${scoreIA.round()}/100',
                        style: const TextStyle(
                          color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  const SizedBox(height: 4),
                  const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoursesTab extends StatefulWidget {
  final AlertService alertSvc;
  const _CoursesTab({required this.alertSvc});

  @override
  State<_CoursesTab> createState() => _CoursesTabState();
}

class _CoursesTabState extends State<_CoursesTab> {
  final ScrollController _scrollCtrl = ScrollController();
  // Une GlobalKey par item pour pouvoir mesurer sa position
  final Map<String, GlobalKey> _itemKeys = {};

  @override
  void initState() {
    super.initState();
    // ★ v9.84 : Écouter le deep link courseKey et scroller vers le pari concerné
    deepLinkCourseKeyNotifier.addListener(_onDeepLink);
  }

  @override
  void dispose() {
    deepLinkCourseKeyNotifier.removeListener(_onDeepLink);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onDeepLink() {
    final courseKey = deepLinkCourseKeyNotifier.value;
    if (courseKey == null || courseKey.isEmpty) return;
    // Consommer la valeur pour éviter un double scroll
    deepLinkCourseKeyNotifier.value = null;
    // Attendre que le ListView soit rendu avant de scroller
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCourse(courseKey));
  }

  void _scrollToCourse(String courseKey) {
    // Chercher la clé qui correspond (storageKey contient courseKey comme préfixe)
    final matchKey = _itemKeys.entries.firstWhere(
      (e) => e.key.contains(courseKey) || courseKey.contains(e.key.split('_').first),
      orElse: () => _itemKeys.entries.isNotEmpty ? _itemKeys.entries.first : MapEntry('', GlobalKey()),
    );
    if (matchKey.key.isEmpty) return;

    final ctx = matchKey.value.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      alignment: 0.1, // afficher en haut avec une petite marge
    );
  }

  @override
  Widget build(BuildContext context) {
    // ★ Fix option A : utiliser .entries pour conserver la clé de stockage réelle
    // (avec timestamp) — nécessaire pour retirerSuivi correct quand plusieurs
    // paris existent sur la même course.
    final entries = widget.alertSvc.trackedCourses.entries.toList()
      ..sort((a, b) => a.value.heureDepart.compareTo(b.value.heureDepart));

    if (entries.isEmpty) {
      return const EmptyTrackedView();
    }

    // Synchroniser les GlobalKeys avec les entrées actuelles
    _itemKeys.removeWhere((k, _) => !entries.any((e) => e.key == k));
    for (final e in entries) {
      _itemKeys.putIfAbsent(e.key, () => GlobalKey());
    }

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
      itemCount: entries.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) return _InfoBannerSuivi(alertSvc: widget.alertSvc);
        final entry = entries[i - 1];
        return KeyedSubtree(
          key: _itemKeys[entry.key],
          child: _TrackedCourseCard(
            course: entry.value,
            storageKey: entry.key,
            alertSvc: widget.alertSvc,
          ),
        );
      },
    );
  }
}

class _InfoBannerSuivi extends StatelessWidget {
  final AlertService alertSvc;
  const _InfoBannerSuivi({required this.alertSvc});

  @override
  Widget build(BuildContext context) {
    final hasPermission = alertSvc.hasNotificationPermission;

    return Column(children: [
      // Bannière permission si nécessaire
      if (!hasPermission &&
          alertSvc.permissionStatus != NotificationPermissionStatus.notChecked)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFEF5350).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFEF5350).withValues(alpha: 0.4)),
          ),
          child: Row(children: [
            const Icon(Icons.notifications_off, color: Color(0xFFEF5350), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Notifications désactivées',
                    style: TextStyle(
                        color: Color(0xFFEF5350),
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                const Text(
                  'Activez les notifications pour recevoir les alertes de départ et résultats.',
                  style: TextStyle(color: Colors.white54, fontSize: 16, height: 1.3),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => alertSvc.ouvrirParametresNotification(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF5350).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFEF5350).withValues(alpha: 0.5)),
                ),
                child: const Text('Activer',
                    style: TextStyle(
                        color: Color(0xFFEF5350),
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),

      // Bannière info + bouton rafraîchissement manuel
      Consumer<DataRefreshService>(
        builder: (ctx, svc, _) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF162033),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline, color: Color(0xFF64B5F6), size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text(
                  'Suivez vos courses et recevez des alertes automatiques avant le départ, '
                  'à l\'arrivée et pour le résultat.',
                  style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.3),
                ),
                const SizedBox(height: 4),
                Text(
                  'Données : ${svc.lastRefreshLabel}  •  Chevaux, jockeys et cotes synchronisés',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: svc.loading ? null : () => svc.refresh(),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF64B5F6).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF64B5F6).withValues(alpha: 0.4)),
                ),
                child: svc.loading
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF64B5F6)))
                    : const Icon(Icons.refresh, color: Color(0xFF64B5F6), size: 16),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}

class _TrackedCourseCard extends StatefulWidget {
  final TrackedCourse course;
  final String storageKey; // clé réelle avec timestamp
  final AlertService alertSvc;

  const _TrackedCourseCard({required this.course, required this.storageKey, required this.alertSvc});

  @override
  State<_TrackedCourseCard> createState() => _TrackedCourseCardState();
}

class _TrackedCourseCardState extends State<_TrackedCourseCard> {
  // État de la vérification automatique du résultat
  bool _checkingResult = false;
  List<int>? _arrivee; // ordre d'arrivée récupéré depuis l'API
  List<int> _disqualifies = []; // numéros des chevaux disqualifiés
  bool? _isGagnant;   // résultat calculé localement
  String? _resultMessage;
  // Timer pour re-vérifier automatiquement toutes les 2 min si pas encore de résultat
  Timer? _autoRetryTimer;
  int _retryCount = 0;
  static const int _maxRetries = 15; // max 30 min de tentatives

  // Dividendes PMU officiels après course
  List<RapportPmu> _rapportsPmu = [];
  bool _chargementRapports = false;

  TrackedCourse get course => widget.course;
  AlertService get alertSvc => widget.alertSvc;

  @override
  void initState() {
    super.initState();
    // ★ Charger le résultat persisté s'il existe déjà
    if (course.isGagne != null) {
      _isGagnant = course.isGagne;
      _arrivee = course.arriveeFinale.isNotEmpty ? course.arriveeFinale : null;
      _resultMessage = course.messageResultat;
    }

    // Vérification automatique si la course est terminée
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final diff = course.heureDepart.difference(DateTime.now());
      // ★ Fix seuil : lancer dès -5 min (résultats PMU disponibles rapidement)
      // L'ancienne valeur -20 retardait trop la clôture automatique du pari.
      // Si le résultat est déjà persisté, pas besoin de re-vérifier.
      if (diff.inMinutes <= -5 && _arrivee == null) {
        _verifierResultatAuto();
        _demarrerAutoRetry();
      } else if (diff.inMinutes <= 0 && _arrivee == null) {
        // Course commencée mais < 5 min : attendre puis lancer
        Future.delayed(const Duration(minutes: 5), () {
          if (mounted && _arrivee == null) {
            _verifierResultatAuto();
            _demarrerAutoRetry();
          }
        });
      }
      // Charger les dividendes PMU si course terminée depuis > 5 min
      // OU si le résultat est déjà connu (isGagne != null) — évite le délai de 20 min
      if (diff.inMinutes <= -5 || course.isGagne != null) {
        _chargerRapportsPmu();
      }
    });
  }

  void _demarrerAutoRetry() {
    _autoRetryTimer?.cancel();
    _autoRetryTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (!mounted || _arrivee != null || _retryCount >= _maxRetries) {
        _autoRetryTimer?.cancel();
        return;
      }
      _retryCount++;
      _verifierResultatAuto();
    });
  }

  @override
  void dispose() {
    _autoRetryTimer?.cancel();
    super.dispose();
  }

  /// Charge les dividendes PMU officiels après la course
  Future<void> _chargerRapportsPmu() async {
    // ✅ Fix: si _chargementRapports est bloqué (timeout précédent), on le réinitialise
    if (_rapportsPmu.isNotEmpty) return;
    final diff = course.heureDepart.difference(DateTime.now());
    // Autoriser si terminée (≤ -20 min) OU si résultat déjà enregistré
    final courseTerminee = diff.inMinutes <= -20 || course.isGagne != null;
    if (!courseTerminee) return;
    if (!mounted) return;
    setState(() => _chargementRapports = true);
    try {
      final dep = course.heureDepart;
      final dateStr =
          '${dep.day.toString().padLeft(2, '0')}${dep.month.toString().padLeft(2, '0')}${dep.year}';
      // ✅ Fix: timeout explicite de 15s — jamais de spinner infini
      final rapports = await PmuApiService.fetchRapportsDefinitifs(
          dateStr, course.numReunion, course.numCourse)
          .timeout(const Duration(seconds: 15), onTimeout: () => []);
      if (!mounted) return;
      setState(() {
        _rapportsPmu = rapports;
        _chargementRapports = false;
      });
      // ✅ Fix audit : appliquer le dividende réel au profil si rapports disponibles
      if (rapports.isNotEmpty && mounted) {
        _majGainReelDansProfil(rapports);
      }
    } catch (e) {
      // ✅ Fix: toujours remettre _chargementRapports à false en cas d'erreur
      if (mounted) setState(() => _chargementRapports = false);
      if (kDebugMode) debugPrint('[MesParis] Erreur chargement rapports: $e');
    }
  }

  /// Met à jour le vrai gain PMU dans le profil utilisateur (PmuProvider + AlertService).
  /// ✅ Fix audit : cette méthode était absente dans mes_paris_screen — dividendes jamais
  /// enregistrés sauf si l'utilisateur ouvrait manuellement l'écran paris_detail_screen.
  /// UNIQUEMENT si le pari est réellement gagnant (isGagne == true).
  void _majGainReelDansProfil(List<RapportPmu> rapports) {
    if (!mounted) return;
    // CRITIQUE : enregistrer SEULEMENT si isGagne == true (pas null, pas false)
    if (course.isGagne != true) return;
    try {
      final provider = context.read<PmuProvider>();
      final pred = provider.getPredictionForCourse(course.numReunion, course.numCourse);
      if (pred == null || pred.dividendeRecupere) return;

      final typePariLower = course.typePari.toLowerCase();
      List<String> codesPmu = [];
      if (typePariLower.contains('gagnant+placé') || typePariLower.contains('gagnant + placé') || typePariLower.contains('gagnant+place')) {
        codesPmu = ['E_SIMPLE_GAGNANT', 'E_SIMPLE_PLACE'];
      } else if (typePariLower.contains('couplé gagnant')) {
        codesPmu = ['E_COUPLE_GAGNANT'];
      } else if (typePariLower.contains('couplé placé')) {
        codesPmu = ['E_COUPLE_PLACE'];
      } else if (typePariLower.contains('quinté')) {
        codesPmu = ['E_MULTI', 'E_MINI_MULTI'];
      } else if (typePariLower.contains('quarté')) {
        codesPmu = ['E_SUPER_QUATRE'];
      } else if (typePariLower.contains('tiercé')) {
        codesPmu = ['E_TRIO'];
      } else if (typePariLower.contains('simple gagnant')) {
        codesPmu = ['E_SIMPLE_GAGNANT'];
      } else if (typePariLower.contains('simple placé')) {
        codesPmu = ['E_SIMPLE_PLACE'];
      } else if (typePariLower.contains('gagnant')) {
        codesPmu = ['E_SIMPLE_GAGNANT'];
      } else if (typePariLower.contains('placé')) {
        codesPmu = ['E_SIMPLE_PLACE'];
      }
      if (codesPmu.isEmpty) return;

      final matching = rapports.where((r) => codesPmu.contains(r.typePari)).toList();
      if (matching.isEmpty) return;
      final meilleur = matching.reduce((a, b) => a.dividende > b.dividende ? a : b);

      // 1. Mettre à jour UserPrediction dans PmuProvider (profil / historique)
      provider.enregistrerDividendePmu(
        pred.id,
        dividendePmuReel: meilleur.dividende,
        combinaisonPmu: meilleur.combinaison,
      );
      // 2. Mettre à jour TrackedCourse dans AlertService (mes paris / sauvegarde)
      final storageKey = widget.storageKey;
      alertSvc.enregistrerDividendePmuTracked(
        storageKey,
        dividende: meilleur.dividende,
        combinaison: meilleur.combinaison,
      );
      if (kDebugMode) {
        debugPrint('[MesParis] ✅ Dividende PMU appliqué au profil: ×${meilleur.dividende.toStringAsFixed(2)}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[MesParis] Erreur maj gain réel: $e');
    }
  }

  /// Filtre les rapports PMU pour ne garder que le type de pari joué
  /// Codes réels API PMU : E_TRIO (Tiercé), E_SUPER_QUATRE (Quarté+),
  /// E_MULTI / E_MINI_MULTI (Quinté+), E_COUPLE_GAGNANT, E_COUPLE_PLACE,
  /// E_SIMPLE_GAGNANT, E_SIMPLE_PLACE
  /// ★ v9.84 : Filtre les rapports par type de pari ET par numéro de cheval
  /// Pour Simple Placé / Gagnant+Placé : ne garder que l'arrivée qui contient
  /// le cheval joué (évite d'afficher arr.1 / arr.2 / arr.7 si N°4 a joué placé)
  List<RapportPmu> _filtrerRapportsParTypeEtCheval(
      List<RapportPmu> rapports, String typePari, int? numeroCheval) {
    final filtered = _filtrerRapportsParType(rapports, typePari);
    if (numeroCheval == null || numeroCheval <= 0) return filtered;

    // Chercher les rapports dont la combinaison contient le numéro du cheval
    final avecCheval = filtered.where((r) {
      if (r.combinaison.isEmpty) return true;
      final nums = r.combinaison.split('-').map((s) => int.tryParse(s.trim())).whereType<int>().toList();
      return nums.contains(numeroCheval);
    }).toList();

    // Si aucun rapport ne contient le cheval (pari perdu) → garder tout
    return avecCheval.isNotEmpty ? avecCheval : filtered;
  }

  List<RapportPmu> _filtrerRapportsParType(List<RapportPmu> rapports, String typePari) {
    final t = typePari.toLowerCase();
    List<String> codesPmu = [];

    // Ordre important : plus spécifique en premier
    if (t.contains('gagnant+placé') || t.contains('gagnant + placé') || t.contains('gagnant+place')) {
      codesPmu = ['E_SIMPLE_GAGNANT', 'E_SIMPLE_PLACE'];
    } else if (t.contains('couplé gagnant')) {
      codesPmu = ['E_COUPLE_GAGNANT'];
    } else if (t.contains('couplé placé')) {
      codesPmu = ['E_COUPLE_PLACE'];
    } else if (t.contains('quinté') || t.contains('quinte')) {
      // ★ L'API PMU peut retourner E_MULTI ou E_QUINTE selon la réunion
      codesPmu = ['E_MULTI', 'E_MINI_MULTI'];
    } else if (t.contains('quarté') || t.contains('quarte')) {
      // ★ L'API PMU peut retourner E_SUPER_QUATRE selon la réunion
      codesPmu = ['E_SUPER_QUATRE'];
    } else if (t.contains('tiercé') || t.contains('tierce')) {
      // ★ L'API PMU retourne E_TRIO pour le Tiercé (pas E_TIERCE)
      // On filtre UNIQUEMENT E_TRIO pour n'afficher que le dividende Tiercé
      // et non pas les Simple Gagnant/Placé/Couplé de la même course
      codesPmu = ['E_TRIO'];
    } else if (t.contains('simple gagnant')) {
      codesPmu = ['E_SIMPLE_GAGNANT'];
    } else if (t.contains('simple placé')) {
      codesPmu = ['E_SIMPLE_PLACE'];
    } else if (t.contains('gagnant')) {
      codesPmu = ['E_SIMPLE_GAGNANT'];
    } else if (t.contains('placé')) {
      codesPmu = ['E_SIMPLE_PLACE'];
    }

    if (codesPmu.isEmpty) return [];
    final filtered = rapports.where((r) => codesPmu.contains(r.typePari)).toList();

    // ★ Si aucun rapport E_TRIO trouvé pour un Tiercé, chercher les variantes
    // (certaines réunions PMU utilisent des codes légèrement différents)
    if (filtered.isEmpty && (t.contains('tiercé') || t.contains('tierce'))) {
      final fallbackTierce = rapports.where((r) {
        final code = r.typePari.toUpperCase();
        return code.contains('TRIO') || code.contains('TIERCE') || code.contains('TIERCÉ');
      }).toList();
      if (fallbackTierce.isNotEmpty) return fallbackTierce;
    }
    // ★ Idem pour Quarté+
    if (filtered.isEmpty && (t.contains('quarté') || t.contains('quarte'))) {
      final fallbackQuarte = rapports.where((r) {
        final code = r.typePari.toUpperCase();
        return code.contains('QUATRE') || code.contains('QUARTE') || code.contains('QUARTÉ');
      }).toList();
      if (fallbackQuarte.isNotEmpty) return fallbackQuarte;
    }
    // ★ Idem pour Quinté+
    if (filtered.isEmpty && (t.contains('quinté') || t.contains('quinte'))) {
      final fallbackQuinte = rapports.where((r) {
        final code = r.typePari.toUpperCase();
        return code.contains('MULTI') || code.contains('QUINTE') || code.contains('QUINTÉ');
      }).toList();
      if (fallbackQuinte.isNotEmpty) return fallbackQuinte;
    }

    return filtered;
  }

  /// Libellé lisible pour un rapport PMU
  String _labelRapportSuivi(RapportPmu r) {
    final t = r.typePari.toUpperCase();
    // Tiercé — tous les codes PMU possibles
    if (t == 'E_TRIO' || t == 'E_TRIO_ORDRE' || t == 'E_TIERCE' || t.contains('TRIO')) {
      return r.estOrdre ? 'Tiercé — Dans l\'ordre' : 'Tiercé — Désordre';
    }
    // Quarté+
    if (t == 'E_SUPER_QUATRE' || t == 'E_QUARTE' || t.contains('QUATRE') || t.contains('QUARTE')) {
      return r.estOrdre ? 'Quarté+ — Dans l\'ordre' : 'Quarté+ — Désordre';
    }
    // Quinté+
    if (t == 'E_MULTI' || t.contains('QUINTE') || t.contains('QUINTÉ')) {
      return r.estOrdre ? 'Quinté+ — Dans l\'ordre' : 'Quinté+ — Désordre';
    }
    if (t == 'E_MINI_MULTI') {
      return r.estOrdre ? 'Quinté+ Mini — Dans l\'ordre' : 'Quinté+ Mini — Désordre';
    }
    // Couplé
    if (t == 'E_COUPLE_GAGNANT' || t == 'E_COUPLE_ORDRE' || t == 'E_COUPLE') {
      return 'Couplé Gagnant';
    }
    if (t == 'E_COUPLE_PLACE' || t == 'E_COUPLE_PLACE_ORDRE') return 'Couplé Placé';
    // Simples
    if (t == 'E_SIMPLE_GAGNANT') return 'Simple Gagnant';
    if (t == 'E_SIMPLE_PLACE')   return 'Simple Placé';
    if (t == 'E_DEUX_SUR_QUATRE') return '2 sur 4';
    // Fallback lisible : supprimer E_ et formater
    final clean = t.replaceAll('E_', '').replaceAll('_', ' ').toLowerCase();
    return clean.split(' ').map((w) => w.isEmpty ? '' : '\${w[0].toUpperCase()}\${w.substring(1)}').join(' ');
  }

  /// Vérifie automatiquement le résultat depuis l'API PMU
  Future<void> _verifierResultatAuto() async {
    if (_checkingResult) return;
    if (!mounted) return;
    setState(() => _checkingResult = true);

    try {
      // ★ Utiliser chargerResultatsCourseComplet pour récupérer aussi les DQ
      final resultat = await ZoneTurfService.chargerResultatsCourseComplet(
        heureDepart: course.heureDepart,
        numReunion: course.numReunion,
        numCourse: course.numCourse,
      );
      final arrivee = resultat?.arriveeOfficielle;
      final disqualifies = resultat?.disqualifies ?? [];

      if (!mounted) return;

      if (arrivee != null && arrivee.isNotEmpty) {
        final monNumero = course.numeroCheval ?? 0;
        bool gagnant = false;
        String msg = '';

        final typeLower = course.typePari.toLowerCase().trim();
        // ★ Inclure les DQ dans l'affichage
        final arriveeStr = '${arrivee.take(5).map((n) => 'N°$n').join(' - ')}'
            '${disqualifies.isNotEmpty ? ' | DISQ: ${disqualifies.map((n) => "N°$n").join(", ")}' : ''}';

        // ★ Si notre cheval est DQ → pari automatiquement perdu
        if (disqualifies.contains(monNumero)) {
          gagnant = false;
          msg = '⛔ N°$monNumero disqualifié — pari annulé. Arrivée officielle : $arriveeStr';
          setState(() {
            _arrivee = arrivee;
            _disqualifies = disqualifies;
            _isGagnant = false;
            _resultMessage = msg;
            _checkingResult = false;
          });
          alertSvc.enregistrerResultatPari(course.key, isGagne: false, arrivee: arrivee, message: msg);
          _autoRetryTimer?.cancel();
          return;
        }

        switch (typeLower) {
          case 'simple gagnant':
            gagnant = arrivee.isNotEmpty && arrivee[0] == monNumero;
            msg = gagnant
                ? '🏆 Gagnant ! N°$monNumero 1er !'
                : '❌ N°$monNumero non 1er — Arrivée : $arriveeStr';
            break;

          case 'placé':
          case 'simple placé':
            final nbPartants = course.numerosJoues.length;
            final topPlace = nbPartants >= 8 ? 3 : (nbPartants >= 5 ? 3 : 2);
            gagnant = arrivee.take(topPlace).contains(monNumero);
            final posPlace = arrivee.indexOf(monNumero) + 1;
            msg = gagnant
                ? '✅ Placé ! N°$monNumero ${posPlace}ème !'
                : '❌ Non placé — Arrivée : $arriveeStr';
            break;

          // ── GAGNANT+PLACÉ : 2 paris sur le même cheval ─────────────
          case 'gagnant+placé':
          case 'gagnant + placé':
          case 'gagnant+place':
            final est1er = arrivee.isNotEmpty && arrivee[0] == monNumero;
            final estPlace = arrivee.take(3).contains(monNumero);
            final posGP = arrivee.indexOf(monNumero) + 1;
            if (est1er) {
              gagnant = true;
              msg = '🏆 1er ! N°$monNumero gagne les 2 paris (Gagnant + Placé) !';
            } else if (estPlace) {
              gagnant = true; // le Placé est gagnant même si pas 1er
              msg = '✅ N°$monNumero ${posGP}ème — Placé ✓ / Gagnant ✗ — Arrivée : $arriveeStr';
            } else {
              gagnant = false;
              msg = '❌ N°$monNumero non placé — Arrivée : $arriveeStr';
            }
            break;

          case 'couplé gagnant':
            if (course.numerosJoues.length >= 2) {
              final n1 = course.numerosJoues[0];
              final n2 = course.numerosJoues[1];
              gagnant = arrivee.take(2).contains(n1) && arrivee.take(2).contains(n2);
              msg = gagnant
                  ? '🏆 Couplé gagnant ! N°$n1 & N°$n2 dans les 2 premiers !'
                  : '❌ Couplé perdu — Arrivée : $arriveeStr';
            } else {
              gagnant = arrivee.isNotEmpty && arrivee[0] == monNumero;
              msg = gagnant ? '🏆 Gagnant !' : '❌ Perdu';
            }
            break;

          case 'couplé placé':
            if (course.numerosJoues.length >= 2) {
              final n1 = course.numerosJoues[0];
              final n2 = course.numerosJoues[1];
              gagnant = arrivee.take(3).contains(n1) && arrivee.take(3).contains(n2);
              msg = gagnant
                  ? '🏆 Couplé placé ! N°$n1 & N°$n2 dans les 3 premiers !'
                  : '❌ Couplé placé perdu — Arrivée : $arriveeStr';
            } else {
              gagnant = arrivee.take(3).contains(monNumero);
              msg = gagnant ? '✅ Placé !' : '❌ Perdu';
            }
            break;

          case 'tiercé':
            if (course.numerosJoues.length >= 3) {
              final top3 = arrivee.take(3).toSet();
              final selTop3 = course.numerosJoues.take(3).toSet();
              gagnant = selTop3.every((n) => top3.contains(n));
              // Vérifier si dans l'ordre exact aussi
              final dansOrdre = arrivee.length >= 3 &&
                  course.numerosJoues.length >= 3 &&
                  arrivee[0] == course.numerosJoues[0] &&
                  arrivee[1] == course.numerosJoues[1] &&
                  arrivee[2] == course.numerosJoues[2];
              msg = gagnant
                  ? (dansOrdre
                      ? '🏆 Tiercé dans l\'ordre ! ${selTop3.map((n) => 'N°$n').join('-')} !'
                      : '✅ Tiercé désordre ! ${selTop3.map((n) => 'N°$n').join('-')} !')
                  : '❌ Tiercé perdu — Arrivée : $arriveeStr';
            } else {
              gagnant = false;
              msg = '❌ Données insuffisantes pour vérifier le Tiercé';
            }
            break;

          case 'quarté+':
          case 'quarte+':
            if (course.numerosJoues.length >= 4) {
              final top4 = arrivee.take(4).toSet();
              gagnant = course.numerosJoues.take(4).every((n) => top4.contains(n));
              msg = gagnant
                  ? '🏆 Quarté+ ! ${course.numerosJoues.take(4).map((n) => 'N°$n').join('-')} !'
                  : '❌ Quarté+ perdu — Arrivée : $arriveeStr';
            } else {
              gagnant = false;
              msg = '❌ Données insuffisantes';
            }
            break;

          case 'quinté+':
          case 'quinte+':
            if (course.numerosJoues.length >= 5) {
              final top5 = arrivee.take(5).toSet();
              final selTop5 = course.numerosJoues.take(5).toSet();
              final dans5 = selTop5.every((n) => top5.contains(n));
              final dans4 = selTop5.where((n) => top5.contains(n)).length >= 4;
              gagnant = dans5 || dans4;
              msg = dans5
                  ? '🏆 Quinté+ ! Tous les 5 dans les 5 premiers !'
                  : dans4
                    ? '✅ Bonus 4/5 du Quinté+ — Arrivée : $arriveeStr'
                    : '❌ Quinté+ perdu — Arrivée : $arriveeStr';
            } else {
              gagnant = false;
              msg = '❌ Données insuffisantes';
            }
            break;

          default:
            gagnant = arrivee.isNotEmpty && arrivee[0] == monNumero;
            msg = gagnant ? '🏆 Gagnant !' : '❌ N°$monNumero non 1er — Arrivée : $arriveeStr';
        }

        setState(() {
          _arrivee = arrivee;
          _disqualifies = disqualifies;
          _isGagnant = gagnant;
          _resultMessage = msg;
          _checkingResult = false;
        });

        // ★ Persister le résultat dans TrackedCourse pour ne pas le perdre à la navigation
        alertSvc.enregistrerResultatPari(
          course.key,
          isGagne: gagnant,
          arrivee: arrivee,
          message: msg,
        );

        // ★ Synchroniser le résultat dans PmuProvider (Profil/Stats)
        // Sans ça, le Profil affiche tous les paris comme perdus
        try {
          final pmuProvider = context.read<PmuProvider>();
          final courseKeyStr = course.key;
          final matchingPred = pmuProvider.predictions.where((p) {
            final pk = 'R${p.numReunion}C${p.numCourse}';
            return courseKeyStr.startsWith(pk);
          }).toList();
          for (final pred in matchingPred) {
            if (pred.isCorrect == null) {
              pmuProvider.validatePrediction(
                pred.id,
                isCorrect: gagnant,
                montantMise: course.miseEngagee,
                gainRealise: null, // calculé automatiquement par PmuProvider selon cote
              );
            }
          }
        } catch (e) {
          debugPrint('[MesParis] Sync PmuProvider erreur : \$e');
        }

        // ★ v9.85 : Bulle IA victoire / défaite
        try {
          final iaSvc = IaPersonalityService.instance;
          // Récupérer le nom du cheval favori IA (si dispo dans le TrackedCourse)
          final String nomCheval = (widget.course.nomCheval ?? '').isNotEmpty
              ? widget.course.nomCheval!
              : 'ce cheval';
          final msg = gagnant
              ? iaSvc.messageVictoire(nomCheval)
              : iaSvc.messageDefaite(nomCheval);
          IaBubbleOverlayState.afficher(
            msg,
            type: gagnant ? 'victoire' : 'defaite',
          );
        } catch (_) {}

        // ★ Stopper l'auto-retry : résultat obtenu
        _autoRetryTimer?.cancel();
      } else {
        setState(() => _checkingResult = false);
      }
    } catch (e) {
      if (mounted) setState(() => _checkingResult = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statut = course.statutLabel;
    final statutColor = course.statutColor;
    final diff = course.heureDepart.difference(DateTime.now());
    // ★ Fix seuils cohérents avec TrackedCourse.statutLabel
    final isEnCours = diff.inMinutes <= 0 && diff.inMinutes > -20;
    final isTerminee = diff.inMinutes <= -20 || course.isGagne != null;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ParisDetailScreen(
            tracked: course,
            alertSvc: alertSvc,
          ),
        ),
      ),
      child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1A2B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEnCours
              ? const Color(0xFFEF5350).withValues(alpha: 0.6)
              : statutColor.withValues(alpha: 0.4),
          width: isEnCours ? 1.5 : 1.0,
        ),
        boxShadow: isEnCours
            ? [BoxShadow(
                color: const Color(0xFFEF5350).withValues(alpha: 0.15),
                blurRadius: 12,
              )]
            : [],
      ),
      child: Column(children: [
        // ── En-tête ──────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            color: statutColor.withValues(alpha: 0.09),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(children: [
            // Icône statut
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: statutColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: statutColor.withValues(alpha: 0.3)),
              ),
              child: Center(
                child: isEnCours
                    ? const PulsingDot()
                    : Icon(
                        isTerminee ? Icons.flag : Icons.timer,
                        color: statutColor,
                        size: 22,
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  course.nomCourse,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      height: 1.2),
                ),
                const SizedBox(height: 3),
                Text(
                  '${course.hippodrome} • R${course.numReunion}C${course.numCourse}',
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ]),
            ),
            // Date + Heure + statut
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(
                _formatDateCourte(course.heureDepart),
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
              Text(
                '${course.heureDepart.hour.toString().padLeft(2, '0')}h${course.heureDepart.minute.toString().padLeft(2, '0')}',
                style: TextStyle(
                    color: statutColor,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statutColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statutColor.withValues(alpha: 0.4)),
                ),
                child: Text(statut,
                    style: TextStyle(
                        color: statutColor, fontSize: 14, fontWeight: FontWeight.bold)),
              ),
            ]),
          ]),
        ),

        // ── Badge DQ (si des chevaux ont été disqualifiés/retirés) ──────
        Builder(builder: (ctx) {
          final disqNums = alertSvc.disqPourCourse(course.key);
          if (disqNums.isEmpty) return const SizedBox.shrink();
          return Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6F00).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFF6F00).withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFFF6F00), size: 15),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    '⚠️ DQ/Retrait : ${disqNums.map((n) => "N°$n").join(", ")}  •  Pronostic IA recalculé',
                    style: const TextStyle(
                      color: Color(0xFFFF6F00),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }),

        // ── Détails cheval + mise ────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(children: [
            if (course.nomCheval != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1628),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFF2E5F8A).withValues(alpha: 0.6)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A3A5C).withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF64B5F6)),
                      ),
                      child: Center(
                        child: Text(
                          '${course.numeroCheval ?? "?"}',
                          style: const TextStyle(
                              color: Color(0xFF64B5F6),
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          course.nomCheval!,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 17),
                        ),
                        Row(children: [
                          if (course.miseEngagee != null)
                            Text(
                              'Mise : ${course.miseEngagee!.toStringAsFixed(0)} €',
                              style: const TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600),
                            ),
                          // Badge type de pari — fond or, texte sombre, toujours visible
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFD700),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFC8880A), width: 1.2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Text(
                              course.typePari,
                              style: const TextStyle(
                                color: Color(0xFF1A1000),
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ]),
                      ]),
                    ),
                    const Icon(Icons.emoji_events_outlined,
                        color: Color(0xFFFFD700), size: 20),
                  ]),
                  // ── Badge de confiance IA — toujours affiché ──────────
                  const SizedBox(height: 8),
                  _buildScoreIABadge(course.scoreIA),
                  // ── Pronostic PMU (favoris par cote) ────────────────────
                  _buildPronosticPMU(context),
                  // ★ v9.93 : Afficher "Votre pari" + numéros pour Tiercé/Quarté/Quinté
                  if (course.numerosJoues.length > 1) ...[
                    const SizedBox(height: 8),
                    Builder(builder: (ctx) {
                      // Favori IA = cheval principal enregistré au moment du pari
                      String? favoriIANumero;
                      if (course.numeroCheval != null) {
                        final numStr = course.numeroCheval.toString();
                        if (course.numerosJoues.contains(int.tryParse(numStr) ?? -1)) {
                          favoriIANumero = numStr;
                        }
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Label "Votre pari"
                          Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Row(children: [
                              const Icon(Icons.confirmation_number_outlined,
                                  color: Color(0xFFFFD700), size: 13),
                              const SizedBox(width: 5),
                              Text(
                                'Votre pari — ${course.typePari} :',
                                style: const TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ]),
                          ),
                          // Numéros joués
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: course.numerosJoues.asMap().entries.map((entry) {
                              final idx = entry.key;
                              final num = entry.value;
                              final isMain = favoriIANumero != null && num.toString() == favoriIANumero;
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isMain
                                      ? const Color(0xFF1A3A5C)
                                      : const Color(0xFF162033),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isMain
                                        ? const Color(0xFF64B5F6)
                                        : Colors.white24,
                                  ),
                                ),
                                child: Text(
                                  '${idx + 1}. N°$num',
                                  style: TextStyle(
                                    color: isMain ? const Color(0xFF90CAF9) : Colors.white70,
                                    fontSize: 12,
                                    fontWeight: isMain ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      );
                    }),
                  ],
                ]),
              ),

            const SizedBox(height: 12),

            // ── Countdown ────────────────────────────────────────────────
            _buildCountdownBanner(diff, isEnCours, isTerminee, statutColor),

            // ── RÉSULTAT AUTOMATIQUE (affiché quand course terminée) ──────
            if (_checkingResult) ...[ 
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0E1A2B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF64B5F6))),
                  SizedBox(width: 10),
                  Text('Vérification du résultat...', style: TextStyle(color: Colors.white54, fontSize: 13)),
                ]),
              ),
            ] else if (_resultMessage != null) ...[ 
              const SizedBox(height: 10),
              // Bandeau résultat principal
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _isGagnant == true
                      ? const Color(0xFF0D3B1F)
                      : const Color(0xFF3B0D0D),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isGagnant == true
                        ? const Color(0xFF4CAF7D)
                        : const Color(0xFFEF5350),
                    width: 1.5,
                  ),
                  boxShadow: [BoxShadow(
                    color: (_isGagnant == true
                        ? const Color(0xFF4CAF7D)
                        : const Color(0xFFEF5350)).withValues(alpha: 0.2),
                    blurRadius: 10,
                  )],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(
                      _isGagnant == true ? Icons.emoji_events : Icons.cancel_outlined,
                      color: _isGagnant == true ? const Color(0xFFFFD700) : const Color(0xFFEF5350),
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _resultMessage!,
                        style: TextStyle(
                          color: _isGagnant == true ? const Color(0xFF69F0AE) : const Color(0xFFEF9A9A),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ]),
                  // ★ v91 : Gain OU Perte affiché directement sur le ticket
                  if (_isGagnant != null && course.miseEngagee != null && course.miseEngagee! > 0) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _isGagnant == true
                            ? const Color(0xFFFFD700).withValues(alpha: 0.12)
                            : const Color(0xFFEF5350).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _isGagnant == true
                              ? const Color(0xFFFFD700).withValues(alpha: 0.4)
                              : const Color(0xFFEF5350).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                          _isGagnant == true ? Icons.attach_money : Icons.money_off,
                          color: _isGagnant == true ? const Color(0xFFFFD700) : const Color(0xFFEF5350),
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _calculerGainAffiche(course),
                          style: TextStyle(
                            color: _isGagnant == true ? const Color(0xFFFFD700) : const Color(0xFFEF9A9A),
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ]),
                    ),
                  ],
                  // Ordre arrivée
                  if (_arrivee != null && _arrivee!.isNotEmpty) ...[ 
                    const SizedBox(height: 8),
                    Text(
                      'Arrivée officielle : ${_arrivee!.take(5).map((n) => 'N°$n').join(' - ')}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    // ★ Badge DQ si des chevaux ont été disqualifiés
                    if (_disqualifies.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.redAccent, width: 1),
                          ),
                          child: Text(
                            '⛔ DISQ : ${_disqualifies.map((n) => 'N°$n').join(', ')}',
                            style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ]),
                    ],
                  ],
                ]),
              ),
            ] else if (isTerminee && _arrivee == null) ...[ 
              const SizedBox(height: 10),
              // Bouton pour relancer la vérification manuellement
              GestureDetector(
                onTap: _verifierResultatAuto,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2F3D),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.refresh, color: Color(0xFF64B5F6), size: 16),
                    SizedBox(width: 6),
                    Text('Vérifier le résultat', style: TextStyle(color: Color(0xFF64B5F6), fontSize: 13)),
                  ]),
                ),
              ),
            ],

            // ── Dividendes PMU officiels après course ─────────────────────
            if (isTerminee) ...[ 
              const SizedBox(height: 10),
              if (_chargementRapports)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A1A0A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: const Row(children: [
                    SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF4CAF7D))),
                    SizedBox(width: 10),
                    Text('Récupération des dividendes PMU…',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ]),
                )
              else if (_rapportsPmu.isNotEmpty)
                _buildDividendesSuivi(
                    _filtrerRapportsParTypeEtCheval(
                      _rapportsPmu,
                      course.typePari,
                      course.numeroCheval,
                    ),
                    course.miseEngagee ?? 0,
                    estPerdu: _isGagnant == false)
              else
                GestureDetector(
                  onTap: _chargerRapportsPmu,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1F0D),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFF4CAF7D).withValues(alpha: 0.4)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.download_outlined,
                          color: Color(0xFF4CAF7D), size: 15),
                      const SizedBox(width: 7),
                      const Expanded(
                        child: Text(
                          'Afficher les dividendes PMU officiels',
                          style: TextStyle(
                              color: Color(0xFF4CAF7D),
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          color: Color(0xFF4CAF7D), size: 16),
                    ]),
                  ),
                ),
            ],

            const SizedBox(height: 10),

            // ── Actions — Ligne 1 : Direct + Résultat ────────────────────
            Row(children: [
              // Suivre en direct
              Expanded(
                child: ActionButton(
                  icon: Icons.live_tv,
                  label: 'Direct',
                  color: const Color(0xFF64B5F6),
                  onTap: () => _ouvrirDirect(context, course),
                ),
              ),
              // Bouton Résultat : affiché SEULEMENT si le résultat n'est pas encore connu
              // (évite le doublon d'alerte quand l'auto-détection a déjà fait son travail)
              if (_isGagnant == null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: ActionButton(
                    icon: Icons.edit_note,
                    label: 'Résultat',
                    color: const Color(0xFF4CAF7D),
                    onTap: () => _saisirResultat(context, course),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 8),

            // ── Actions — Ligne 2 : Partage + JPEG + Supprimer ───────────
            Row(children: [
              // Partager ce pari
              Expanded(
                child: ActionButton(
                  icon: Icons.share,
                  label: 'Partager',
                  color: const Color(0xFFFFD700),
                  onTap: () => ShareCardService.partagerCourse(
                    context,
                    data: ShareCardData(
                      typePariLabel: course.typePari,
                      paris: [course],
                      miseTotal: course.miseEngagee ?? 0.0,
                      gainTotal: _isGagnant == true ? _gainBrut(course) : null,
                      estGagnant: _isGagnant,
                      scoreIA: course.scoreIA,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Sauvegarder en JPEG
              Expanded(
                child: ActionButton(
                  icon: Icons.image_outlined,
                  label: 'JPEG',
                  color: const Color(0xFF26C6DA),
                  onTap: () => ShareCardService.sauvegarderEnJpeg(
                    context,
                    data: ShareCardData(
                      typePariLabel: course.typePari,
                      paris: [course],
                      miseTotal: course.miseEngagee ?? 0.0,
                      gainTotal: _isGagnant == true ? _gainBrut(course) : null,
                      estGagnant: _isGagnant,
                      scoreIA: course.scoreIA,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Supprimer le suivi
              Expanded(
                child: ActionButton(
                  icon: Icons.delete_outline,
                  label: 'Supprimer',
                  color: const Color(0xFFEF5350),
                  onTap: () => _confirmerSuppression(context, course),
                ),
              ),
            ]),
          ]),
        ),
      ]),
      ), // fin GestureDetector
    );
  }

  /// Dialogue de confirmation avant suppression du suivi
  /// ★ Bug fix #4 : protège les données collectées et propose de valider le résultat
  Future<void> _confirmerSuppression(BuildContext context, TrackedCourse c) async {
    final diff = c.heureDepart.difference(DateTime.now());
    final isTerminee = diff.inMinutes <= -20 || c.isGagne != null;
    // Si la course est terminée et le résultat local connu, proposer de l'enregistrer
    if (isTerminee && _resultMessage != null && _isGagnant != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF0A1628),
          title: const Text('Supprimer ce suivi ?',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
              '⚠️ La course est terminée. Les données IA collectées (pronostics, mémoire) sont conservées, mais le suivi sera retiré de cette liste.',
              style: TextStyle(color: Colors.white60, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (_isGagnant! ? const Color(0xFF1B5E20) : const Color(0xFF7F1919)).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: (_isGagnant! ? const Color(0xFF4CAF7D) : const Color(0xFFEF5350)).withValues(alpha: 0.5)),
              ),
              child: Text(
                'Résultat : $_resultMessage',
                style: TextStyle(
                  color: _isGagnant! ? const Color(0xFF69F0AE) : const Color(0xFFEF9A9A),
                  fontSize: 13,
                ),
              ),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler', style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF5350),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Supprimer le suivi', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        alertSvc.retirerSuivi(widget.storageKey);
      }
    } else {
      // Course pas encore terminée ou résultat inconnu → confirmation simple
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF0A1628),
          title: const Text('Supprimer ce suivi ?',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Text(
            '${c.nomCourse} — ${c.hippodrome}\n\nLes données IA collectées (mémoire, pronostics) sont conservées.',
            style: const TextStyle(color: Colors.white60, fontSize: 14, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler', style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF5350),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Supprimer', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        alertSvc.retirerSuivi(widget.storageKey);
      }
    }
  }

  /// Calcule le gain brut (retour total) pour affichage
  /// Priorité : dividende PMU réel > cote enregistrée > estimation
  double _gainBrut(TrackedCourse c) {
    if (c.miseEngagee == null || c.miseEngagee! <= 0) return 0.0;
    final mise = c.miseEngagee!;
    // Priorité 1 : dividende PMU réel récupéré après course
    if (c.dividendePmuReel != null && c.dividendePmuReel! > 0) {
      return c.dividendePmuReel! * mise;
    }
    // Priorité 2 : cote enregistrée (Simple Gagnant/Placé)
    if (c.cote > 1.0) {
      return c.cote * mise;
    }
    // Fallback : estimation ×2
    return mise * 2.0;
  }

  /// Texte du gain ou perte affiché directement sur le ticket
  String _calculerGainAffiche(TrackedCourse c) {
    final mise = c.miseEngagee ?? 0.0;
    if (mise <= 0) {
      return _isGagnant == true ? '🏆 Pari gagnant !' : '❌ Pari perdu';
    }
    // ── PARI PERDU ──────────────────────────────────────────────────────
    if (_isGagnant == false) {
      return 'Perdu : -${fmtEuros(mise)} €';
    }
    // ── PARI GAGNANT — dividende PMU réel disponible ────────────────────
    if (c.dividendePmuReel != null && c.dividendePmuReel! > 0) {
      final retour = c.dividendePmuReel! * mise;
      final gainNet = retour - mise;
      return '🏆 Gagné : +${fmtEuros(gainNet)} € (retour ${fmtEuros(retour)} €, ×${c.dividendePmuReel!.toStringAsFixed(2)} PMU officiel)';
    }
    // ── PARI GAGNANT — cote enregistrée (Simple Gagnant/Placé) ─────────
    if (c.cote > 1.0) {
      final retour = c.cote * mise;
      final gainNet = retour - mise;
      return 'Gagné : +${fmtEuros(gainNet)} € (retour ${fmtEuros(retour)} €, ×${c.cote.toStringAsFixed(1)})';
    }
    return '🏆 Gagnant ! (gain à valider dans Mon Profil)';
  }

  /// Bloc dividendes PMU dans la vue Suivi (compact, coloré)
  Widget _buildDividendesSuivi(List<RapportPmu> rapports, double mise,
      {bool estPerdu = false}) {
    // Couleur d'accent header : ambre pour pari perdu (hypothétique), vert validé sinon
    final headerColor = estPerdu
        ? const Color(0xFFFFB300)
        : const Color(0xFF4CAF7D);

    return Container(
      padding: const EdgeInsets.fromLTRB(11, 11, 11, 7),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1422),  // bleu nuit neutre
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: headerColor.withValues(alpha: 0.45), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // En-tête
        Row(children: [
          Icon(
            estPerdu ? Icons.emoji_events_outlined : Icons.verified_outlined,
            color: headerColor, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              estPerdu
                  ? 'SI TU AVAIS GAGNÉ — DIVIDENDES PMU'
                  : 'DIVIDENDES PMU OFFICIELS',
              style: TextStyle(
                  color: headerColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5),
            ),
          ),
          if (estPerdu)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF7F1919).withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                    color: const Color(0xFFEF5350).withValues(alpha: 0.5)),
              ),
              child: const Text('PERDU',
                  style: TextStyle(
                      color: Color(0xFFEF9A9A),
                      fontSize: 9,
                      fontWeight: FontWeight.bold)),
            ),
        ]),
        if (estPerdu) ...[
          const SizedBox(height: 2),
          Text(
            'Avec ta mise de ${mise > 0 ? "${mise.toStringAsFixed(0)} €" : "ta mise"}',
            style: const TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontStyle: FontStyle.italic)),
        ],
        const SizedBox(height: 8),
        const Divider(color: Colors.white10, height: 1),
        const SizedBox(height: 8),
        // Lignes de dividendes
        ...rapports.map((RapportPmu r) {
          final effectiveMise = mise > 0 ? mise : 1.0;
          final gainNet = r.gainNetPourMise(effectiveMise);
          final retour = r.retourPourMise(effectiveMise);
          final label = _labelRapportSuivi(r);
          // Couleurs selon vrais codes API PMU
          final t = r.typePari.toUpperCase();
          Color labelColor;
          Color bgColor;
          Color borderColor;
          String icon;
          if (t == 'E_MULTI' || t == 'E_MINI_MULTI') {
            icon = '🌟'; labelColor = const Color(0xFFFFD700);
            bgColor = const Color(0xFF2D1B00); borderColor = const Color(0xFFFFD700);
          } else if (t == 'E_SUPER_QUATRE') {
            icon = '🎰'; labelColor = const Color(0xFFCE93D8);
            bgColor = const Color(0xFF1A0D2E); borderColor = const Color(0xFFAB47BC);
          } else if (t == 'E_TRIO') {
            if (r.estOrdre) {
              icon = '🥇'; labelColor = const Color(0xFF81C784);
              bgColor = const Color(0xFF0A2B18); borderColor = const Color(0xFF4CAF7D);
            } else {
              icon = '🥈'; labelColor = const Color(0xFF80CBC4);
              bgColor = const Color(0xFF102018); borderColor = const Color(0xFF26A69A);
            }
          } else if (t == 'E_COUPLE_GAGNANT' || t == 'E_COUPLE_PLACE') {
            icon = '🤝'; labelColor = const Color(0xFF81D4FA);
            bgColor = const Color(0xFF001A2E); borderColor = const Color(0xFF29B6F6);
          } else {
            // Simple Gagnant, Simple Placé, etc.
            icon = '🏇'; labelColor = const Color(0xFFFFCC80);
            bgColor = const Color(0xFF1A1500); borderColor = const Color(0xFFFFB74D);
          }

          // Couleur du montant : doré pour pari perdu (hypothétique), vert vif pour gagné
          final gainColor = estPerdu
              ? const Color(0xFFFFD54F)   // doré/ambre chaud
              : const Color(0xFF69F0AE);  // vert vif
          final retourColor = estPerdu
              ? const Color(0xFFFFCC80)   // orange clair
              : const Color(0xFF80CBC4);  // cyan clair

          return Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Container(
              padding: const EdgeInsets.all(0),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                    color: borderColor.withValues(alpha: 0.65), width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        Text(icon,
                            style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(label,
                              style: TextStyle(
                                  color: labelColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ]),
                      if (r.combinaison.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text('Arr. ${r.combinaison}',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 10)),
                      ],
                      Text('×${r.dividende.toStringAsFixed(2)} / 1 €',
                          style: TextStyle(
                              color: labelColor.withValues(alpha: 0.55),
                              fontSize: 10)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  // Badge montant coloré
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: gainColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                            color: gainColor.withValues(alpha: 0.5), width: 1),
                      ),
                      child: Text(
                        mise > 0
                            ? '${gainNet >= 0 ? "+" : ""}${fmtEuros(gainNet)} €'
                            : '×${r.dividende.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: gainColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 19,
                        ),
                      ),
                    ),
                    if (mise > 0) ...[
                      const SizedBox(height: 3),
                      Text('retour ${fmtEuros(retour)} €',
                          style: TextStyle(
                              color: retourColor, fontSize: 10)),
                    ],
                  ]),
                ]),
              ),
            ),
          );
        }),
      ]),
    );
  }

  /// Bandeau countdown coloré
  Widget _buildCountdownBanner(Duration diff, bool isEnCours, bool isTerminee, Color statutColor) {
    String label;
    IconData icon;
    if (isTerminee) {
      label = 'Course terminée';
      icon = Icons.flag_outlined;
    } else if (isEnCours) {
      label = '🔴 En cours maintenant !';
      icon = Icons.sports_score;
    } else {
      final totalMin = diff.inMinutes;
      if (totalMin < 60) {
        label = 'Dans $totalMin min';
      } else {
        final h = diff.inHours;
        final m = totalMin - (h * 60);
        label = m > 0 ? 'Dans ${h}h${m.toString().padLeft(2,'0')}min' : 'Dans ${h}h';
      }
      icon = Icons.timer_outlined;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: statutColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: statutColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: statutColor, size: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: statutColor,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  /// Pronostic PMU : numéros favoris par cote, récupérés depuis DataRefreshService
  Widget _buildPronosticPMU(BuildContext context) {
    // Chercher la course ZtCourse correspondante dans le programme chargé
    final svc = DataRefreshService.instance;
    ZtCourse? ztCourse;
    for (final reunion in svc.reunions) {
      if (reunion.code == 'R${course.numReunion}') {
        for (final c in reunion.courses) {
          if (c.numCourse == course.numCourse) {
            ztCourse = c;
            break;
          }
        }
        if (ztCourse != null) break;
      }
    }

    final pmu = ztCourse?.pronosticPMU ?? [];
    if (pmu.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFFD700).withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Text(
              '🏇 PMU : ',
              style: TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            Expanded(
              child: Wrap(
                spacing: 5,
                children: pmu.take(5).toList().asMap().entries.map((entry) {
                  final isFirst = entry.key == 0;
                  final num = entry.value;
                  final isMyHorse = num == course.numeroCheval;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: isMyHorse
                          ? const Color(0xFFFFD700).withValues(alpha: 0.3)
                          : isFirst
                              ? const Color(0xFFFFD700).withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: isMyHorse
                            ? const Color(0xFFFFD700)
                            : isFirst
                                ? const Color(0xFFFFD700).withValues(alpha: 0.5)
                                : Colors.white24,
                        width: isMyHorse ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      isMyHorse ? '★N°$num' : 'N°$num',
                      style: TextStyle(
                        color: isMyHorse
                            ? const Color(0xFFFFD700)
                            : isFirst
                                ? const Color(0xFFFFD700).withValues(alpha: 0.9)
                                : Colors.white54,
                        fontSize: 11,
                        fontWeight: isFirst || isMyHorse ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const Text(
              'favoris',
              style: TextStyle(color: Colors.white30, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  /// Badge affichant le score de confiance IA — toujours visible avec code couleur
  Widget _buildScoreIABadge(double score) {
    Color couleur;
    String label;
    IconData icone;
    // score == 0 : pari sans score enregistré (ancien pari)
    if (score <= 0) {
      couleur = Colors.white30;
      label = 'Non disponible';
      icone = Icons.psychology_alt;
    } else if (score >= 80) {
      couleur = const Color(0xFF4CAF7D);  // 🟢 vert
      label = 'Très haute';
      icone = Icons.psychology;
    } else if (score >= 65) {
      couleur = const Color(0xFF8BC34A);  // 🟡 vert-jaune
      label = 'Haute';
      icone = Icons.psychology;
    } else if (score >= 50) {
      couleur = const Color(0xFFFFB74D);  // 🟠 orange
      label = 'Moyenne';
      icone = Icons.psychology_alt;
    } else {
      couleur = const Color(0xFFEF9A9A);  // 🔴 rouge
      label = 'Faible';
      icone = Icons.psychology_alt;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: couleur.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icone, color: couleur, size: 14),
        const SizedBox(width: 5),
        Text(
          score <= 0
              ? 'Confiance IA : —'
              : 'Confiance IA : ${score.round()}/100 — $label',
          style: TextStyle(color: couleur, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }

  /// Formate la date de manière courte : "Auj.", "Dem." ou "jj/mm"
  String _formatDateCourte(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(dt.year, dt.month, dt.day);
    final diff = dateOnly.difference(today).inDays;
    if (diff == 0) return "Aujourd'hui";
    if (diff == 1) return 'Demain';
    if (diff == -1) return 'Hier';
    final jours = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    return '${jours[dt.weekday - 1]} ${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}';
  }

  void _ouvrirDirect(BuildContext context, TrackedCourse course) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A1628),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,        // ← permet au sheet de prendre sa hauteur naturelle
      builder: (_) => DirectLinksSheet(course: course),
    );
  }

  void _saisirResultat(BuildContext context, TrackedCourse course) {
    // ★ Si le résultat automatique est déjà connu, le pré-remplir dans le dialog
    showDialog(
      context: context,
      builder: (_) => ResultatDialog(
        course: course,
        alertSvc: alertSvc,
        preselectedGagnant: _isGagnant,  // pré-sélection auto
        prefilledArrivee: _arrivee,       // arrivée pré-remplie
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Onglet 2 : Paramètres des alertes
// ══════════════════════════════════════════════════════════════════════════════

// AlertSettingsTab, AlertSettingsSheet → déplacés dans lib/widgets/paris/alert_settings_widgets.dart

class _AjouterCourseSheet extends StatefulWidget {
  final List<_CourseSuivi> courses;
  final AlertService alertSvc;

  const _AjouterCourseSheet({
    required this.courses,
    required this.alertSvc,
  });

  @override
  State<_AjouterCourseSheet> createState() => _AjouterCourseSheetState();
}

class _AjouterCourseSheetState extends State<_AjouterCourseSheet> {
  _CourseSuivi? _selected;
  String? _nomCheval;
  int? _numCheval;
  double _mise = 10.0;
  String _typePari = 'Simple Gagnant';
  final _miseCtrl = TextEditingController(text: '10');

  static const List<String> _typesPariDisponibles = [
    'Simple Gagnant',
    'Simple Placé',
    'Gagnant+Placé',
    'Couplé Gagnant',
    'Couplé Placé',
    'Couplé Ordre',
    'Couplé Désordre',
    'Tiercé',
    'Tiercé Ordre',
    'Tiercé Désordre',
    'Quarté+',
    'Quinté+',
  ];

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scroll) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: const BoxDecoration(
            color: Color(0xFF0A1628),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.add_circle, color: Color(0xFF4CAF7D)),
              const SizedBox(width: 8),
              const Text('Suivre une course',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
              const Spacer(),
              // Badge source données
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF7D).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF4CAF7D).withValues(alpha: 0.4)),
                ),
                child: const Text('PMU IA',
                    style: TextStyle(color: Color(0xFF4CAF7D), fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 14),
            Expanded(
              child: ListView(controller: scroll, children: [
                const Text('Choisissez une course à venir :',
                    style: TextStyle(color: Colors.white54, fontSize: 15)),
                const SizedBox(height: 8),
                ...widget.courses.map((c) {
                  final isSel = _selected?.key == c.key;
                  final dejasuivi = widget.alertSvc.isSuivi(c.key);
                  return GestureDetector(
                    onTap: dejasuivi ? null : () => setState(() => _selected = c),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isSel
                            ? const Color(0xFF2E7D52).withValues(alpha: 0.2)
                            : dejasuivi
                                ? Colors.white.withValues(alpha: 0.03)
                                : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSel
                              ? const Color(0xFF4CAF7D)
                              : dejasuivi
                                  ? Colors.white12
                                  : Colors.white12,
                        ),
                      ),
                      child: Row(children: [
                        // Icône sélection
                        if (isSel)
                          const Icon(Icons.check_circle, color: Color(0xFF4CAF7D), size: 18)
                        else if (dejasuivi)
                          const Icon(Icons.bookmark, color: Color(0xFFFFD700), size: 18)
                        else
                          const Icon(Icons.radio_button_unchecked, color: Colors.white24, size: 18),
                        const SizedBox(width: 10),
                        
                        // Infos course
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              if (c.isQuinte)
                                Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.6)),
                                  ),
                                  child: const Text('Q+', style: TextStyle(color: Color(0xFFFFD700), fontSize: 14, fontWeight: FontWeight.bold)),
                                ),
                              Expanded(
                                child: Text(c.nomCourse,
                                    style: TextStyle(
                                        color: dejasuivi ? Colors.white30 : Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ]),
                            const SizedBox(height: 2),
                            Row(children: [
                              Text('${c.discipline} ${c.hippodrome}',
                                  style: const TextStyle(color: Colors.white38, fontSize: 16)),
                              if (dejasuivi)
                                const Text(' • Déjà suivi',
                                    style: TextStyle(color: Color(0xFFFFD700), fontSize: 16)),
                            ]),
                            // Favori IA si disponible
                            if (c.favoriIA != null && !dejasuivi)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Row(children: [
                                  const Icon(Icons.auto_awesome, size: 10, color: Color(0xFF4CAF7D)),
                                  const SizedBox(width: 3),
                                  Text('IA: N°${c.favoriIA!.numero} ${c.favoriIA!.nom} (${c.favoriIA!.scoreIA.toStringAsFixed(0)}pts)',
                                      style: const TextStyle(color: Color(0xFF4CAF7D), fontSize: 15)),
                                ]),
                              ),
                          ]),
                        ),
                        
                        // Heure + date
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(c.heureStr,
                              style: const TextStyle(color: Color(0xFF4CAF7D), fontSize: 14, fontWeight: FontWeight.bold)),
                          Text(c.dateStr,
                              style: const TextStyle(color: Colors.white38, fontSize: 15)),
                        ]),
                      ]),
                    ),
                  );
                }),

                if (_selected != null) ...[
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 12),

                  // Suggestion du favori IA
                  if (_selected!.favoriIA != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF7D).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF4CAF7D).withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.auto_awesome, color: Color(0xFF4CAF7D), size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('Favori IA suggéré :',
                                style: TextStyle(color: Colors.white54, fontSize: 16)),
                            Text(
                              'N°${_selected!.favoriIA!.numero} ${_selected!.favoriIA!.nom} — Score ${_selected!.favoriIA!.scoreIA.toStringAsFixed(0)}/100',
                              style: const TextStyle(color: Color(0xFF4CAF7D), fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ]),
                        ),
                        GestureDetector(
                          onTap: () => setState(() {
                            _nomCheval = _selected!.favoriIA!.nom;
                            _numCheval = int.tryParse(_selected!.favoriIA!.numero);
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2E7D52),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('Utiliser', style: TextStyle(color: Colors.white, fontSize: 16)),
                          ),
                        ),
                      ]),
                    ),
                  ],

                  const Text('Votre cheval (optionnel) :',
                      style: TextStyle(color: Colors.white54, fontSize: 15)),
                  const SizedBox(height: 8),
                  TextField(
                    style: const TextStyle(color: Colors.white),
                    controller: _nomCheval != null ? TextEditingController(text: _nomCheval) : null,
                    decoration: InputDecoration(
                      hintText: 'Nom du cheval...',
                      hintStyle: const TextStyle(color: Colors.white24),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF2E7D52)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF4CAF7D)),
                      ),
                    ),
                    onChanged: (v) => _nomCheval = v.isEmpty ? null : v,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                    controller: _numCheval != null ? TextEditingController(text: '$_numCheval') : null,
                    decoration: InputDecoration(
                      hintText: 'Numéro du cheval...',
                      hintStyle: const TextStyle(color: Colors.white24),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF2E7D52)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF4CAF7D)),
                      ),
                    ),
                    onChanged: (v) => _numCheval = int.tryParse(v),
                  ),
                  const SizedBox(height: 10),
                  // ── Sélecteur de type de pari ─────────────────────────────
                  const Text('Type de pari :',
                      style: TextStyle(color: Colors.white54, fontSize: 15)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF4CAF7D).withValues(alpha: 0.5)),
                    ),
                    child: DropdownButton<String>(
                      value: _typePari,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF0D2035),
                      underline: const SizedBox.shrink(),
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF4CAF7D)),
                      items: _typesPariDisponibles.map((type) {
                        return DropdownMenuItem<String>(
                          value: type,
                          child: Text(type, style: const TextStyle(color: Colors.white)),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _typePari = v ?? 'Simple Gagnant'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // ── Mise ─────────────────────────────────────────────────
                  TextField(
                    controller: _miseCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Mise (€)',
                      labelStyle: const TextStyle(color: Colors.white38),
                      prefixText: '€ ',
                      prefixStyle: const TextStyle(color: Color(0xFFFFD700)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF2E7D52)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFFFD700)),
                      ),
                    ),
                    onChanged: (v) => _mise = double.tryParse(v) ?? 10.0,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add_alert, color: Colors.white),
                      label: const Text('Ajouter le suivi',
                          style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D52),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        final c = _selected!;
                        widget.alertSvc.ajouterSuivi(TrackedCourse(
                          numReunion: c.numReunion,
                          numCourse: c.numCourse,
                          nomCourse: c.nomCourse,
                          hippodrome: c.hippodrome,
                          heureDepart: c.heureDepart,
                          nomCheval: _nomCheval,
                          numeroCheval: _numCheval,
                          miseEngagee: _mise,
                          typePari: _typePari,
                        ));
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✅ Suivi activé pour ${c.nomCourse}'),
                            backgroundColor: const Color(0xFF1B5E20),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ]),
            ),
          ]),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Sheet : Liens pour suivre en direct
// ══════════════════════════════════════════════════════════════════════════════

// DirectLinksSheet, DirectLink, LinkTile → déplacés dans lib/widgets/paris/direct_links_sheet.dart
// ResultatDialog → déplacé dans lib/widgets/paris/resultat_dialog.dart
// AlertesTab, AlertTile → déplacés dans lib/widgets/paris/alert_widgets.dart
// EmptyTrackedView, ActionButton, PulsingDot
// → déplacés dans lib/widgets/paris/paris_common_widgets.dart
