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
import '../widgets/paris/gain_manuel_dialog.dart'; // ★ B1-T12 lot 2-A
import '../widgets/paris/direct_links_sheet.dart';
import '../widgets/paris/alert_settings_widgets.dart';
import 'paris_detail_screen.dart';

import '../services/ia_personality_service.dart'; // ★ v9.85 IA bulle
import '../widgets/ia/ia_bubble_widget.dart';      // ★ v9.85 IA bulle
import '../services/arrivee_officielle_service.dart'; // ★ A6 — lecture L0
import '../widgets/arrivee_officielle_groupes_widget.dart'; // ★ A6 — rendu ex æquo
import '../utils/type_pari_utils.dart'; // ★ A-0 — reconnaissance Gagnant+Placé
import '../services/branchement_verdict_course.dart'; // ★ B-4.5 — verdict officiel
import '../services/affichage_gain_structure.dart'; // ★ B-4.5 — affichage structuré
import '../services/gain_durable_vue.dart'; // ★ B1-T12 lot 2-C — vue durable
import '../services/resultat_ecriture_gain.dart'; // ★ B1-T12 lot 2-C — issue d'écriture

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
          // ★ B1-T12 / LOT 2-C — ABONNEMENT RÉEL À `PmuProvider`.
          //
          //   `listen: false` seul ne notifie PERSONNE : il faudrait un
          //   abonnement pour que la carte se reconstruise. Ce `Consumer`
          //   apporte exactement cela, avec une portée limitée À LA CARTE :
          //   aucun `setState` de l'écran, aucune reconstruction de la liste
          //   ni des onglets.
          //
          //   `PmuProvider` est DÉJÀ requis par cet écran (mesuré :
          //   `context.read<PmuProvider>()`), donc ce `Consumer` n'ajoute
          //   aucune dépendance nouvelle et ne peut pas échouer par absence.
          //
          //   Déclencheurs couverts : saisie et modification du gain manuel,
          //   acceptation et refus d'un gain officiel, restauration des
          //   données (`_loadSavedPredictions` → `notifyListeners`).
          child: Consumer<PmuProvider>(
            builder: (ctxCarte, pmu, _) => _TrackedCourseCard(
              course: entry.value,
              storageKey: entry.key,
              alertSvc: widget.alertSvc,
              predictionLiee: _predictionLieeDans(pmu, entry.key),
            ),
          ),
        );
      },
    );
  }

  /// ★ B1-T12 / LOT 2-C — RAPPROCHEMENT PAR IDENTIFIANT PERSISTANT SEUL.
  ///
  /// `UserPrediction.idTicketLie` porte la clé de persistance du `TrackedCourse`
  /// jumeau (mesuré : `bet_bottom_sheet.dart`, liaison écrite à la création).
  /// On ne déduit RIEN de la réunion, de la course, de la date ou du type de
  /// pari : deux paris sur la MÊME course restent donc totalement indépendants.
  ///
  /// Rend `null` quand aucune liaison certaine n'existe — un ancien ticket, ou
  /// un ticket créé par le chemin « Suivre une course » qui n'écrit aucune
  /// liaison. La carte conserve alors son affichage historique.
  UserPrediction? _predictionLieeDans(PmuProvider pmu, String storageKey) {
    for (final p in pmu.predictions) {
      if (p.idTicketLie == storageKey) return p;
    }
    return null;
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

  /// ★ B1-T12 / LOT 2-C — ticket durable rapproché par IDENTIFIANT PERSISTANT.
  ///
  /// `null` ⇒ aucune décision durable applicable ⇒ la carte conserve son
  /// comportement HISTORIQUE, sans un caractère de différence.
  final UserPrediction? predictionLiee;

  const _TrackedCourseCard({
    required this.course,
    required this.storageKey,
    required this.alertSvc,
    this.predictionLiee,
  });

  @override
  State<_TrackedCourseCard> createState() => _TrackedCourseCardState();
}

class _TrackedCourseCardState extends State<_TrackedCourseCard> {
  // État de la vérification automatique du résultat
  bool _checkingResult = false;
  List<int>? _arrivee; // ordre d'arrivée récupéré depuis l'API

  // ★ A6 : groupes d'ex æquo à afficher, ou `null`.
  //
  // PURE : `ArriveeOfficielleService.arrivee()` lit la RAM, rend une COPIE
  // PROFONDE et n'écrit rien. Cette méthode ne décide QUE de l'affichage :
  // elle n'alimente ni `_arrivee`, ni un calcul de gain, ni un apprentissage.
  //
  // Non nul UNIQUEMENT si L0 possède l'arrivée ET qu'au moins un groupe
  // contient 2 chevaux ou plus. Sans ex æquo, on retourne `null` et la carte
  // conserve son texte historique (exigence : affichage strictement inchangé).
  List<List<int>>? _groupesExAequoAffiches() {
    final groupes = ArriveeOfficielleService.instance.arrivee(widget.course.key);
    if (groupes == null || groupes.isEmpty) return null;
    if (groupes.any((g) => g.isEmpty)) return null;
    if (!arriveeAvecExAequo(groupes)) return null;
    return groupes;
  }
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

  /// ★ B-4.6 — une requête de rapports est déjà en vol.
  /// Empêche deux récupérations simultanées des mêmes rapports (déclencheur
  /// automatique + tap utilisateur) sans jamais bloquer un rafraîchissement
  /// légitime : le drapeau retombe dans un `finally`.
  bool _rapportEnVol = false;

  // ★ LOT B-4.6 — cause RÉELLE de l'absence de rapports, visible en release.
  //
  // Avant ce lot, huit situations distinctes (réponse vide, HTTP non-ok,
  // timeout, erreur réseau, JSON invalide, racine non-liste, aucun rapport
  // publié) s'affichaient toutes de la même façon : rien. La cause est
  // désormais conservée pour être montrée à l'utilisateur.
  CauseAbsenceRapports? _causeAbsenceRapports;
  int? _causeAbsenceCodeHttp;

  TrackedCourse get course => widget.course;
  AlertService get alertSvc => widget.alertSvc;

  // ═══════════════════════════════════════════════════════════════════════
  //  ★ B-4.7 — LE VERDICT OFFICIEL PILOTE LE BANDEAU DE RÉSULTAT
  // ═══════════════════════════════════════════════════════════════════════
  //
  //  ── DÉFAUT MESURÉ AVANT CE LOT ──────────────────────────────────────────
  //  Le bandeau de résultat était conditionné par `_resultMessage != null`.
  //  Or `enregistrerVerdictGainSuivi` ne touche JAMAIS `messageResultat`
  //  (ni `isGagne`) : un ticket `nonDetermine` persisté en production a donc
  //  ces deux champs à `null` et n'affichait STRICTEMENT RIEN. Le verdict
  //  indéterminé — pourtant enregistré et prouvé — était invisible.
  //
  //  ── CE QUI EST FAIT ICI ─────────────────────────────────────────────────
  //  Le bandeau est élargi à tout ticket porteur d'un `etatGain`. La source du
  //  texte est `affichageGainSuivi` (B-4.5), qui lit EXCLUSIVEMENT le verdict
  //  structuré quand il existe : aucun montant n'est recalculé, aucune règle
  //  financière n'est touchée, et les champs historiques ne peuvent pas
  //  contredire le verdict.
  //
  //  ── ANTI-DOUBLON ────────────────────────────────────────────────────────
  //  Si `_resultMessage` est absent, le libellé du verdict devient le TITRE et
  //  le bloc de gain est supprimé : le montant (« Gain gagné : 75 € brut »)
  //  reste visible DANS le titre, une seule fois. Quand `_resultMessage` existe
  //  (tickets historiques), le rendu est strictement inchangé (exigence A6).

  /// Verdict officiel structuré, ou `null` pour un ticket historique.
  AffichageGain? get _verdictOfficiel =>
      course.etatGain != null ? affichageGainSuivi(course) : null;

  /// Titre du bandeau : message historique s'il existe, sinon le verdict.
  String? get _titreResultat => _resultMessage ?? _verdictOfficiel?.libelle;

  /// `true` quand le titre porte DÉJÀ le libellé du verdict ⇒ le bloc de gain
  /// ne doit pas le répéter.
  bool get _verdictPorteLeTitre =>
      _resultMessage == null && _verdictOfficiel != null;

  /// `true` quand le verdict est un `nonDetermine` : teinte neutre/ambre, et
  /// surtout JAMAIS la teinte « perdu » (qui affirmerait une perte non établie).
  bool get _resultatIndetermine =>
      _verdictPorteLeTitre &&
      _verdictOfficiel!.nature == NatureAffichageGain.indetermine;

  Color get _couleurFondResultat => _resultatIndetermine
      ? const Color(0xFF3B2E0D)
      : (_isGagnant == true
          ? const Color(0xFF0D3B1F)
          : const Color(0xFF3B0D0D));

  Color get _couleurAccentResultat => _resultatIndetermine
      ? const Color(0xFFFFB300)
      : (_isGagnant == true
          ? const Color(0xFF4CAF7D)
          : const Color(0xFFEF5350));

  Color get _couleurTexteResultat => _resultatIndetermine
      ? const Color(0xFFFFD180)
      : (_isGagnant == true
          ? const Color(0xFF69F0AE)
          : const Color(0xFFEF9A9A));

  IconData get _iconeResultat => _resultatIndetermine
      ? Icons.help_outline
      : (_isGagnant == true ? Icons.emoji_events : Icons.cancel_outlined);

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
  // ★ LOT B-4.6 — traduction lisible d'une cause d'absence de rapports.
  //
  // Cette phrase est la SEULE information de diagnostic montrée à
  // l'utilisateur. Elle ne prétend jamais que la course n'a pas eu lieu, ni
  // qu'il n'y a pas eu de gagnant : elle dit seulement POURQUOI aucun rapport
  // n'a pu être obtenu, ce que l'application était incapable de dire avant.
  String _libelleCauseAbsence(CauseAbsenceRapports cause) {
    switch (cause) {
      case CauseAbsenceRapports.aucune:
        return '';
      case CauseAbsenceRapports.httpNonOk:
        final code = _causeAbsenceCodeHttp;
        return code == null
            ? 'Rapports indisponibles : le serveur PMU a refusé la demande.'
            : 'Rapports indisponibles : le serveur PMU a répondu HTTP $code.';
      case CauseAbsenceRapports.timeout:
        return 'Rapports non obtenus : le serveur PMU n\'a pas répondu à temps.';
      case CauseAbsenceRapports.reseau:
        return 'Rapports non obtenus : le réseau est indisponible.';
      case CauseAbsenceRapports.corpsNonJson:
        return 'Rapports illisibles : la réponse du serveur PMU n\'est pas du JSON.';
      case CauseAbsenceRapports.racineNonListe:
        return 'Rapports illisibles : la réponse reçue est un programme, pas une liste de rapports.';
      case CauseAbsenceRapports.aucunRapportPublie:
        return 'Aucun rapport publié pour cette course à cet instant.';
      case CauseAbsenceRapports.aucunRapportExploitable:
        // ★ B-4.6 — ne jamais dire « aucun rapport publié » ici : des rapports
        //   ONT été publiés, ils ne portent simplement aucun dividende
        //   exploitable (lignes à dividende nul, écartées par le filtre
        //   historique). Mesuré : 534 lignes réelles dans ce cas.
        return 'Rapports publiés, mais aucun dividende exploitable pour cette course.';
    }
  }

  Widget _buildCauseAbsenceRapports() {
    final cause = _causeAbsenceRapports;
    if (cause == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: _chargerRapportsPmu,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1408),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: const Color(0xFFFFA726).withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline, color: Color(0xFFFFA726), size: 15),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              _libelleCauseAbsence(cause),
              style: const TextStyle(color: Colors.white70, fontSize: 11.5),
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.refresh, color: Colors.white38, size: 15),
        ]),
      ),
    );
  }

  Future<void> _chargerRapportsPmu() async {
    // ✅ Fix: si _chargementRapports est bloqué (timeout précédent), on le réinitialise
    if (_rapportsPmu.isNotEmpty) return;
    // ★ B-4.6 — GARDE DE RÉ-ENTRANCE.
    //   Deux déclencheurs existent en parallèle : l'appel automatique posé par
    //   `initState` (course terminée depuis > 5 min) et le tap de l'utilisateur
    //   sur « Afficher les dividendes PMU officiels ». Sans ce garde, deux
    //   requêtes identiques partaient en même temps et la seconde écrasait
    //   l'état de la première. Aucun état n'est modifié ici : on refuse
    //   seulement une SECONDE requête simultanée, la première reste libre.
    if (_rapportEnVol) return;
    final diff = course.heureDepart.difference(DateTime.now());
    // Autoriser si terminée (≤ -20 min) OU si résultat déjà enregistré
    final courseTerminee = diff.inMinutes <= -20 || course.isGagne != null;
    if (!courseTerminee) return;
    if (!mounted) return;
    _rapportEnVol = true;
    setState(() => _chargementRapports = true);
    try {
      final dep = course.heureDepart;
      final dateStr =
          '${dep.day.toString().padLeft(2, '0')}${dep.month.toString().padLeft(2, '0')}${dep.year}';
      // ✅ Fix: timeout explicite de 15s — jamais de spinner infini
      // ★ LOT B-4.6 — on demande la CAUSE, pas seulement la liste.
      DiagnosticRapports? diagnostic;
      List<RapportPmu> rapports = const <RapportPmu>[];
      try {
        diagnostic = await PmuApiService.fetchRapportsAvecDiagnostic(
                dateStr, course.numReunion, course.numCourse)
            .timeout(const Duration(seconds: 15));
        rapports = diagnostic.rapports;
      } on TimeoutException {
        // ★ B-4.6 — le timeout du service et celui de l'écran valent tous deux
        //   15 s : le second peut donc gagner la course APRÈS que le service a
        //   déjà obtenu une réponse valide. Écraser un résultat non vide par
        //   « délai dépassé » serait un mensonge. On ne déclare le délai que si
        //   aucune donnée n'est arrivée.
        rapports = _rapportsPmu;
        diagnostic = rapports.isEmpty
            ? const DiagnosticRapports(
                rapports: <RapportPmu>[],
                cause: CauseAbsenceRapports.timeout,
              )
            : const DiagnosticRapports(
                rapports: <RapportPmu>[],
                cause: CauseAbsenceRapports.aucune,
              );
      }
      if (!mounted) return;
      setState(() {
        _rapportsPmu = rapports;
        _chargementRapports = false;
        _causeAbsenceRapports = diagnostic?.cause;
        _causeAbsenceCodeHttp = diagnostic?.codeHttp;
      });
      // ✅ Fix audit : appliquer le dividende réel au profil si rapports disponibles
      if (rapports.isNotEmpty && mounted) {
        // ★ B1-T12 / LOT 2-C — l'écriture du verdict est désormais ASYNCHRONE
        //   et CONFIRMÉE : elle attend la sauvegarde puis relit le disque.
        //   On l'attend réellement — sinon un message de réussite pourrait
        //   précéder un échec d'écriture.
        await _majGainReelDansProfil(rapports);
      }
    } catch (e) {
      // ✅ Fix: toujours remettre _chargementRapports à false en cas d'erreur
      if (mounted) setState(() => _chargementRapports = false);
      if (kDebugMode) debugPrint('[MesParis] Erreur chargement rapports: $e');
    } finally {
      _rapportEnVol = false;
    }
  }

  /// ★ LOT B-4.5 — Applique le VERDICT OFFICIEL, sans sélection de montant.
  ///
  /// ── CE QUI A ÉTÉ RETIRÉ, ET POURQUOI (défaut mesuré) ─────────────────────
  /// Cette méthode contenait, jusqu'à B-4.5, un `reduce(MAX)` :
  ///
  ///     final meilleur = matching
  ///         .reduce((a, b) => a.dividende > b.dividende ? a : b);
  ///
  /// Il choisissait le PLUS GROS dividende parmi les codes du pari, puis
  /// l'écrivait comme gain du ticket. Trois défauts, tous mesurés :
  ///   1. le montant retenu n'était pas celui du rapport du pari joué, mais le
  ///      maximum publié pour un code approché (`'tiercé'` → `E_TRIO`, etc.) ;
  ///   2. le pari était résolu par `getPredictionForCourse`, un `firstWhere` :
  ///      sur une course à plusieurs paris, les suivants n'étaient jamais
  ///      résolus (ni gagnés, ni perdus) ;
  ///   3. écrire ce dividende déclenchait `PmuProvider.enregistrerDividendePmu`
  ///      → `_syncStatsTypesIA()`, donc une resynchronisation de l'apprentissage
  ///      à partir d'un montant faux.
  ///
  /// Le `reduce(MAX)` est SUPPRIMÉ. Aucune sélection de montant ne subsiste.
  ///
  /// ── CE QUI LE REMPLACE ───────────────────────────────────────────────────
  /// Le verdict vient exclusivement du moteur B-3, via la couture B-4.5 :
  /// l'arrivée officielle est celle de LA course, et CHAQUE pari de cette
  /// course est résolu avec ses propres numéros et sa propre mise. Aucun pari
  /// n'est choisi à la place d'un autre, aucun montant n'est propagé.
  ///
  /// L'ISOLATION IA EST STRUCTURELLE : ni `enregistrerDividendePmu`, ni
  /// `_syncStatsTypesIA` ne sont appelés ici. Les gains déjà calculés, les
  /// poids, les seuils, le TOP3, le ROI, les statistiques et l'ELO restent
  /// strictement inchangés.
  ///
  /// ── PÉRIMÈTRE RÉEL, SANS EMBELLISSEMENT ──────────────────────────────────
  /// Le chemin ne s'exécute que si `rapports` est non vide ET que l'écran
  /// connaît l'arrivée officielle. `_arriveeGroupesOfficiels` rend `null`
  /// quand l'API n'a pas fourni de groupes : l'arbitre prononcerait alors
  /// `deadHeatSansGroupes`, c'est-à-dire un indéterminé qui pourrait être
  /// levé plus tard. Or un `nonDetermine` est DÉFINITIF pour B-4.3 (transition
  /// refusée) : on refuse donc de l'écrire, et le ticket reste en attente.
  List<List<int>>? get _arriveeGroupesOfficiels {
    final groupes = course.arriveeGroupes;
    if (groupes == null || groupes.isEmpty) return null;
    return groupes;
  }

  Future<void> _majGainReelDansProfil(List<RapportPmu> rapports) async {
    if (!mounted) return;

    final groupes = _arriveeGroupesOfficiels;
    if (groupes == null) return;
    if (rapports.isEmpty) return;

    final resultat = construireResultatOfficiel(
      arriveeGroupes: groupes,
      arriveeDefinitive: course.arriveeDefinitive,
      rapports: rapports,
    );

    try {
      final provider = context.read<PmuProvider>();

      // ── 1. TOUS les paris de CETTE course, chacun avec ses propres données ──
      // `getAllPredictionsForCourse` remplace le `firstWhere` qui ne résolvait
      // que le premier pari. Aucun appariement n'est fait entre les deux
      // modèles : chacun est résolu séparément.
      final predictions = provider.getAllPredictionsForCourse(
          course.numReunion, course.numCourse);
      for (final pred in predictions) {
        if (pred.etatGain != null) continue; // verdict déjà écrit : ne pas rejouer
        // ★ B1-T12 / LOT 2-C — ÉCRITURE SÉCURISÉE ET CONFIRMÉE.
        //   L'ancienne voie (`resoudrePrediction` sur l'instantané + remplacement
        //   d'objet entier) écrasait une saisie manuelle survenue pendant
        //   l'attente réseau (défaut D1, mesuré). La nouvelle relit l'état FRAIS,
        //   fusionne les champs financiers, ATTEND la sauvegarde puis RELIT le
        //   disque. Son issue n'est jamais supposée : elle est rendue.
        await provider.appliquerVerdictGainPredictionSecurise(pred.id, resultat);
      }

      // ── 2. Le ticket SUIVI de cet écran, avec ses propres données ───────────
      if (course.etatGain == null) {
        final resolution = resoudreSuivi(
          ticket: course,
          resultat: resultat,
        );
        if (resolution.enregistrement != null &&
            resolution.enregistrement!.estEnregistre) {
          alertSvc.appliquerVerdictGainSuivi(
            widget.storageKey,
            resolution.enregistrement!.ticket,
          );
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[MesParis] Erreur verdict officiel: $e');
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
      // ★ LOT B-2 bis — groupes OFFICIELS EXACTS, ou `null` si l'API ne les a
      //   pas fournis. Ils ne sont JAMAIS déduits de `arrivee` (liste plate) :
      //   ce serait reconstruire des ex æquo par déduction.
      final groupes = resultat?.arriveeGroupes;
      final definitive = resultat?.arriveeDefinitive;

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
          // ★ LOT B-2 bis : mêmes règles que le chemin principal. Une arrivée
          //   provisoire n'est jamais enregistrée comme définitive, et les
          //   groupes ne sont jamais déduits de la liste plate.
          alertSvc.enregistrerResultatPari(
            widget.storageKey,
            isGagne: false,
            arrivee: arrivee,
            message: msg,
            arriveeGroupes: definitive == false ? null : groupes,
            arriveeDefinitive: definitive,
          );
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
        //
        // ★ LOT B-2 bis — les groupes officiels sont transmis au ticket.
        //   RÈGLE ABSOLUE : une arrivée explicitement PROVISOIRE n'est jamais
        //   enregistrée comme définitive. Si `definitive == false`, on ne
        //   transmet AUCUN groupe (`null` = inconnu) et le drapeau `false`
        //   est conservé tel quel : le ticket saura que son arrivée n'est pas
        //   définitive, au lieu de la présenter comme telle.
        //   Si `definitive == null` (API muette), les groupes sont transmis —
        //   ce sont des données factuelles — et le drapeau reste `null`.
        final groupesAEnregistrer = definitive == false ? null : groupes;
        alertSvc.enregistrerResultatPari(
          widget.storageKey,
          isGagne: gagnant,
          arrivee: arrivee,
          message: msg,
          arriveeGroupes: groupesAEnregistrer,
          arriveeDefinitive: definitive,
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
            // ★ LOT A-0 : Gagnant+Placé = 2 composantes financières.
            //   Tant que le Lot B n'a pas traité les deux composantes, aucune
            //   écriture financière automatique ne peut produire un gain G+P
            //   exact (la cote enregistrée est celle du Gagnant seul).
            //   On n'écrit donc RIEN : `isCorrect` reste null → pari
            //   « en attente » → exclu des statistiques par la règle
            //   préexistante `ia_memory_service.dart:5493`.
            //   Le RÉSULTAT SPORTIF n'est pas perdu : il est porté par
            //   `_arrivee` / `_isGagnant` / `_resultMessage` (setState l.1405)
            //   et par la mémoire IA (alert_service.dart:2719).
            if (estTypeGagnantPlace(pred.typePari)) continue; // A-0
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
            // ═══════════════════════════════════════════════════════════════
            // ★ B1-T12 / LOT 2-C — BADGE DU GAIN DURABLE, HORS DE TOUTE
            //   DÉPENDANCE AU VERDICT.
            //
            // ── DÉFAUT MESURÉ, ET SA CAUSE EXACTE ──────────────────────────
            //   Le libellé de gain existait à UN SEUL endroit : le bloc
            //   historique, lui-même imbriqué dans
            //   `] else if (_titreResultat != null) ...[`.
            //   `_titreResultat` vaut `_resultMessage ?? _verdictOfficiel?.libelle`
            //   (mesuré, `:1061`), donc il est NON NUL SEULEMENT quand un
            //   verdict existe. Un pari qui porte un gain DÉCLARÉ (lot 2-A)
            //   sans verdict n'avait donc AUCUN libellé construit — même en
            //   dehors de la garde `_isGagnant != null`.
            //
            //   Mesuré sur l'écran réel, avant ce correctif : carte rendue
            //   (« Prix Test », « Vincennes • R1C3 », 19 `Text`),
            //   `isGagne = null`, et **0** occurrence de « Gain gagné » comme
            //   de « En attente ». Le montant persisté n'était affiché nulle
            //   part. C'était le défaut de fond du lot 2-A.
            //
            // ── EXCLUSIVITÉ, DÉFINIE EXPLICITEMENT (pas de doublon) ────────
            //   Le badge historique et celui-ci ne peuvent JAMAIS coexister :
            //     • badge historique  ⇔ `_porteBadgeHistorique`  (voir getter)
            //     • badge durable     ⇔ `_afficherBadgeDurable`
            //   et `_afficherBadgeDurable` exige `!_porteBadgeHistorique`.
            //   Les deux conditions sont COMPLÉMENTAIRES, donc une seule
            //   branche s'exécute pour un ticket donné.
            //
            // ── CE QUE CE BLOC NE FAIT PAS ────────────────────────────────
            //   • il ne touche NI au bandeau de verdict, NI à sa logique ;
            //   • il ne modifie NI `affichageGainSuivi`, NI un moteur PMU,
            //     NI une formule, NI l'IA ;
            //   • il n'écrit rien et n'accepte rien : il LIT `_vueDurable()`,
            //     qui rend `null` dès qu'un verdict officiel structuré existe
            //     (défense en profondeur, testée séparément) ;
            //   • il n'invente aucun montant : `_gainBrut`/`_calculerGainAffiche`
            //     restent seuls maîtres du texte, via la même vue unique.
            if (_afficherBadgeDurable) ...[
              const SizedBox(height: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _ouvrirSaisieGainManuel(),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.attach_money,
                        color: Color(0xFFFFD700), size: 16),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _calculerGainAffiche(course),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
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
                          // ★ SOUS-LOT B : mise TOTALE réellement engagée.
                          //   Un Gagnant+Placé à 10 €/composante engage 20 € :
                          //   afficher « Mise : 10 € » sous-estimait le coût
                          //   réel du ticket d'un facteur 2.
                          if (course.miseTotaleEngagee != null &&
                              course.miseTotaleEngagee! > 0)
                            Text(
                              estTypeGagnantPlace(course.typePari)
                                  ? 'Mise : ${course.miseTotaleEngagee!.toStringAsFixed(0)} € (G+P)'
                                  : 'Mise : ${course.miseTotaleEngagee!.toStringAsFixed(0)} €',
                              style: const TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600),
                            )
                          else if (course.misesGagnantPlaceIncompletes)
                            const Text(
                              'Mise : incomplète',
                              style: TextStyle(
                                  color: Color(0xFFFFB300),
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
            ] else if (_titreResultat != null) ...[ 
              const SizedBox(height: 10),
              // Bandeau résultat principal
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _couleurFondResultat,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _couleurAccentResultat,
                    width: 1.5,
                  ),
                  boxShadow: [BoxShadow(
                    color: _couleurAccentResultat.withValues(alpha: 0.2),
                    blurRadius: 10,
                  )],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(
                      _iconeResultat,
                      color: _resultatIndetermine
                          ? const Color(0xFFFFB300)
                          : (_isGagnant == true ? const Color(0xFFFFD700) : const Color(0xFFEF5350)),
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _titreResultat!,
                        style: TextStyle(
                          color: _couleurTexteResultat,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ]),
                  // ★ B-4.7 — Motif du verdict quand il est compréhensible.
                  //   Affiché UNIQUEMENT si le titre porte le verdict (sinon le
                  //   détail ferait doublon avec le bloc de gain, qui lit déjà
                  //   `affichageGainSuivi`).
                  if (_verdictPorteLeTitre && _verdictOfficiel!.detail != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _verdictOfficiel!.detail!,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12, height: 1.35),
                    ),
                  ],
                  // ★ v91 : Gain OU Perte affiché directement sur le ticket
                  // ★ B-4.7 : aucune garde ajoutée ici. Un ticket `nonDetermine`
                  //   a `_isGagnant == null` (l'enregistreur n'écrit jamais
                  //   `isGagne`), donc ce bloc n'est déjà pas rendu ; et quand
                  //   `_resultMessage` existe, `_verdictPorteLeTitre` est faux.
                  //   La condition reste donc BYTE-IDENTIQUE à l'ancre A6.
                  if (_isGagnant != null && course.miseEngagee != null && course.miseEngagee! > 0) ...[
                    const SizedBox(height: 8),
                    // ★ B1-T12 / étape 2 (lot 2-A) — LE MONTANT DU GAIN DEVIENT
                    //   CLIQUABLE. Le bloc est inchangé visuellement : on ne fait
                    //   qu'ENVELOPPER le `Container` existant. Aucun libellé n'est
                    //   modifié, aucun calcul n'est touché : `_calculerGainAffiche`
                    //   reste seul maître du TEXTE affiché.
                    //
                    //   Le `GestureDetector` porte sur la valeur RÉELLE de la clé
                    //   du ticket (`widget.storageKey`, la clé d'index de
                    //   `trackedCourses`), jamais sur une clé reconstituée : un
                    //   ancien ticket NON LIÉ à un `UserPrediction` est donc
                    //   modifiable normalement, sans aucun rapprochement.
                    //
                    //   `behavior: opaque` pour que toute la surface réponde,
                    //   pas seulement le texte.
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _ouvrirSaisieGainManuel(),
                      child: Container(
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
                        // ★ SOUS-LOT B : `Flexible` + ellipsis. Les libellés
                        //   « Gain potentiel » / « Gain gagné » sont plus longs
                        //   que l'ancien texte et débordaient en 320 dp
                        //   (régression mesurée sur A6-E3/E4/E5/E6).
                        Flexible(
                          child: Text(
                            _calculerGainAffiche(course),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _isGagnant == true ? const Color(0xFFFFD700) : const Color(0xFFEF9A9A),
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ]),
                    ),
                    ),
                  ],
                  // Ordre arrivée
                  if (_arrivee != null && _arrivee!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    // ★ A6 : L0 d'abord (lecture pure, ex æquo préservés).
                    // `groupesExAequo` n'est NON NULL que si L0 possède
                    // l'arrivée ET qu'elle contient un ex æquo réel. Dans
                    // tous les autres cas, le texte historique ci-dessous
                    // reste STRICTEMENT identique à avant A6.
                    if (_groupesExAequoAffiches() != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ★ A6 — LISIBILITÉ : `Wrap` et non `Row`.
                          // Un `Row` ne peut pas se replier : sur un petit
                          // écran (320 dp) ou avec un texte agrandi par les
                          // réglages d'accessibilité, il déborde. `Wrap`
                          // renvoie le badge à la ligne SANS réduire la
                          // taille des caractères (mesuré : 209 px de
                          // débordement sur un rendu comparable).
                          //
                          // ★ B-2 bis — l'encadré « Ex æquo » n'est PLUS placé
                          // ici : la spécification validée le veut SOUS chaque
                          // cheval ex æquo, et sous lui seul. Il est donc rendu
                          // par `LigneArriveeExAequo._buildNumero`. Le titre
                          // retrouve sa présentation historique.
                          const Text('Arrivée officielle :',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                          const SizedBox(height: 4),
                          LigneArriveeExAequo(
                            groupes: _groupesExAequoAffiches()!,
                            fontSize: 12,
                          ),
                        ],
                      )
                    else
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
              else if (_causeAbsenceRapports != null &&
                  _causeAbsenceRapports != CauseAbsenceRapports.aucune)
                _buildCauseAbsenceRapports()
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
                      // ★ SOUS-LOT B : mise TOTALE engagée (20 € pour un
                      //   Gagnant+Placé à 10 €/composante), et aucun montant
                      //   fictif : `_gainBrut` rend null si non calculable.
                      miseTotal: course.miseTotaleEngagee ?? 0.0,
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
                      // ★ SOUS-LOT B : mise TOTALE engagée (20 € pour un
                      //   Gagnant+Placé à 10 €/composante), et aucun montant
                      //   fictif : `_gainBrut` rend null si non calculable.
                      miseTotal: course.miseTotaleEngagee ?? 0.0,
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
  /// Calcule le retour BRUT (mise incluse) pour affichage.
  ///
  /// ★ SOUS-LOT B : plus AUCUN multiplicateur fictif. L'ancien repli
  ///   `return mise * 2.0` inventait un retour de 20 € pour 10 € misés dès
  ///   qu'aucun dividende ni aucune cote n'était connu. Il est supprimé :
  ///   sans rapport ni cote, la fonction rend `null` (« non calculable »),
  ///   ce qui est sémantiquement différent de 0 € (« perdu »).
  ///
  /// Ordre de priorité conservé :
  ///  1. dividende PMU officiel (rapport réellement identifié) ;
  ///  2. cote enregistrée (gain potentiel, AVANT le résultat officiel) ;
  ///  3. sinon `null` — jamais un montant inventé.
  /// ★ B1-T12 / LOT 2-C — LA SEULE ENTRÉE D'AFFICHAGE DURABLE DE CETTE CARTE.
  ///
  /// Rend `null` si aucune preuve durable ne s'applique, ce qui laisse les
  /// appelants sur leur chaîne HISTORIQUE sans un caractère de différence.
  ///
  /// ── POURQUOI UN VERDICT EST CHERCHÉ SUR **LES DEUX** MODÈLES ─────────────
  ///   `etatGain` existe sur `TrackedCourse` **et** sur `UserPrediction`
  ///   (mesuré). Un verdict posé sur le profil durable doit donc lui aussi
  ///   interdire à une décision B1-T12 de réécrire l'affichage : sinon un
  ///   verdict B-3/B-4.5 pourrait être contourné par un simple gain déclaré.
  ///
  /// ── `demandeOuverte` ────────────────────────────────────────────────────
  ///   Vrai quand un montant OFFICIEL est connu sans qu'aucune décision ne
  ///   soit prise. C'est le seul cas où l'écran doit annoncer qu'une décision
  ///   est attendue — et il ne l'annonce que si le montant existe réellement.
  GainDurable? _vueDurable() {
    final pred = widget.predictionLiee;
    final verdictOfficielPresent =
        widget.course.etatGain != null || pred?.etatGain != null;
    final demandeOuverte =
        pred?.montantOfficielPmu != null && pred?.decisionGainPmu == null;
    return vueDurable(
      pred,
      verdictOfficielPresent: verdictOfficielPresent,
      demandeOuverte: demandeOuverte,
    );
  }

  /// ★ B1-T12 / LOT 2-C — la carte porte-t-elle DÉJÀ le badge historique ?
  ///
  /// C'est EXACTEMENT la condition de la ligne de garde ancrée par la barrière
  /// A6 (mesurée : `mes_paris_screen.dart:2175`), reproduite ici sans la
  /// modifier. Elle sert UNIQUEMENT à définir l'EXCLUSIVITÉ des deux badges.
  ///
  /// ⚠️ Aucune duplication de logique métier : c'est une simple conjonction de
  ///    trois tests de nullité/positivité, recopiée à l'identique pour rester
  ///    synchronisée avec la garde historique.
  bool get _porteBadgeHistorique =>
      _isGagnant != null &&
      widget.course.miseEngagee != null &&
      widget.course.miseEngagee! > 0;

  /// ★ B1-T12 / LOT 2-C — faut-il construire le badge de gain durable ?
  ///
  /// EXCLUSIVITÉ EXPLICITE, ET C'EST LA SEULE RÈGLE DE CETTE MÉTHODE :
  ///   • `_porteBadgeHistorique` vrai  ⇒ le badge historique s'affiche déjà
  ///     (dans le bandeau de verdict) et il affiche DÉJÀ le libellé durable,
  ///     puisque `_calculerGainAffiche` consulte la même vue unique.
  ///     ⇒ on ne construit RIEN ici. Jamais deux badges, jamais deux montants.
  ///   • `_porteBadgeHistorique` faux  ⇒ aucun badge n'existe ; si une vue
  ///     durable est applicable, on l'affiche ici, MÊME SANS VERDICT.
  ///
  /// `_vueDurable()` porte les garanties de fond :
  ///   • verdict officiel présent (sur l'un OU l'autre modèle) ⇒ `null`,
  ///     donc AUCUN badge : la priorité B-3/B-4.5 est respectée ;
  ///   • aucune décision ET aucun montant déclaré ⇒ `null`, donc aucun badge :
  ///     on n'affiche jamais un gain inexistant ;
  ///   • `0.0` déclaré ⇒ `GainDurable` NON nul (libellé « ❌ Gain déclaré :
  ///     0 € ») : le montant EXISTE et vaut zéro, ce qui est distinct de
  ///     « inconnu » (`null`). La présence du montant, et non sa positivité,
  ///     gouverne l'affichage — c'est la règle demandée ;
  ///   • décision en attente ⇒ libellé « décision PMU en attente » portant le
  ///     montant DÉCLARÉ : l'officiel ne remplace jamais le manuel sans
  ///     acceptation explicite.
  ///
  /// ⚠️ Un montant manuel n'est JAMAIS traité comme un verdict officiel :
  ///    `estOfficiel` reste faux dans toute vue déclarée, et `_isGagnant`
  ///    n'est pas alimenté ici (aucune écriture, aucun état).
  bool get _afficherBadgeDurable =>
      !_porteBadgeHistorique && _vueDurable() != null;

  double? _gainBrut(TrackedCourse c) {
    // ★ B1-T12 / LOT 2-C — DÉCISION DURABLE D'ABORD, MÊME AVANT LE VERDICT.
    //
    //   Sans cette garde, un pari dont l'utilisateur a ACCEPTÉ le gain officiel
    //   continuait d'afficher ici le montant de la branche `dividendePmuReel`,
    //   c'est-à-dire un AUTRE nombre que celui du libellé de la carte. Les deux
    //   surfaces se contredisaient pour le même pari.
    //
    //   La garde rend `null` dans TROIS cas, et `null` signifie « je n'ai rien
    //   de durable à dire » : l'appelant retombe alors sur la chaîne
    //   HISTORIQUE, à l'identique (aucune régression d'affichage).
    final durable = _vueDurable();
    if (durable != null) return durable.montant;

    // ★ LOT B-4.5 — Un ticket qui porte un VERDICT OFFICIEL ne se calcule plus
    //   ici : le montant est celui du verdict, reconstruit par
    //   `affichageGainSuivi` à partir des `montantRetour` DÉJÀ persistés.
    //   Aucune multiplication n'est refaite (ce serait le double comptage que
    //   le lot élimine), et un dividende sélectionné par l'ancien `reduce(MAX)`
    //   ne peut plus être présenté comme un gain confirmé.
    if (c.etatGain != null) {
      final vue = affichageGainSuivi(c);
      return vue.nature == NatureAffichageGain.attribue ||
              vue.nature == NatureAffichageGain.rembourse
          ? vue.montant
          : null;
    }

    final mise = c.miseTotaleEngagee;
    if (mise == null || mise <= 0) return null;
    // ★ LOT B-4.5 / A-0 — AUCUN GAIN MONO-DIVIDENDE POUR UN GAGNANT+PLACÉ.
    //
    //   ── DÉFAUT MESURÉ (reproduit par test) ────────────────────────────────
    //   Un Gagnant+Placé engage DEUX composantes : `miseTotaleEngagee` est la
    //   SOMME des deux mises, alors que `dividendePmuReel` — écrit par l'ancien
    //   moteur — est le dividende d'UNE seule composante (le Gagnant). Le
    //   produit `dividendePmuReel × miseTotaleEngagee` ne vaut donc rien de
    //   réel : mesuré sur un ticket historique 18,00 × 10 € = « 180 € ».
    //
    //   ── CE QUI EST FAIT ICI ───────────────────────────────────────────────
    //   On ne calcule RIEN (retour `null`), et surtout on n'invente rien :
    //   ni zéro, ni perte, ni gain. La valeur historique `dividendePmuReel`
    //   n'est ni effacée ni réécrite — elle reste sur le ticket.
    //
    //   ── CE QUI N'EST PAS TOUCHÉ ───────────────────────────────────────────
    //   • un ticket porteur d'un VERDICT officiel est traité plus haut, par
    //     `affichageGainSuivi` (le moteur B-3 garde la priorité) ;
    //   • les paris MONO-COMPOSANTE (Simple, Couplé, Tiercé…) gardent
    //     exactement le calcul ci-dessous.
    if (estTypeGagnantPlace(c.typePari)) return null;
    // Priorité 1 : dividende PMU réel récupéré après course
    if (c.dividendePmuReel != null && c.dividendePmuReel! > 0) {
      return c.dividendePmuReel! * mise;
    }
    // Priorité 2 : cote enregistrée (Simple Gagnant/Placé) — gain potentiel
    if (c.cote > 1.0) {
      return c.cote * mise;
    }
    // Priorité 3 : aucune donnée ⇒ non calculable. AUCUN ×2 de repli.
    return null;
  }

  /// Textes VOLONTAIREMENT COURTS : la carte doit tenir en 320 dp sans
  /// débordement (contrainte A6 mesurée). Le détail complet (retour brut,
  /// net, multiplicateur) reste disponible dans la fiche du pari.
  /// ★ B1-T12 / étape 2 (lot 2-A) — Ouvre la saisie manuelle du gain.
  ///
  /// Écrit sur `widget.storageKey` : LA clé qui indexe réellement le ticket
  /// dans `AlertService.trackedCourses`. Aucune déduction par réunion, course
  /// ou heure, donc aucune propagation possible vers un autre ticket de la
  /// même course, et aucun rapprochement heuristique avec un ancien ticket.
  ///
  /// `Navigator.push` sur un `DialogRoute` (via `showDialog`) laisse l'écran
  /// EN PLACE sous la fenêtre : au retour, la liste, son défilement et son
  /// état sont ceux d'avant l'ouverture. On ne pousse aucune route plein écran.
  ///
  /// ⚠️ CE QUE CETTE MÉTHODE N'ÉCRIT PAS : rien dans le modèle de PROFIL
  /// (`UserPrediction`). Le PROFIL est un modèle distinct, persisté sous une
  /// autre clé ; sa synchronisation n'est PAS assurée ici et ne doit pas être
  /// présentée comme telle.
  Future<void> _ouvrirSaisieGainManuel() async {
    final resultat = await showDialog<ResultatSaisieGain>(
      context: context,
      builder: (_) => GainManuelDialog(
        montantActuel: widget.course.montantGainManuel,
        nomCourse: widget.course.nomCourse,
        nomCheval: widget.course.nomCheval,
      ),
    );
    // Annulation : on n'écrit RIEN (ni 0, ni effacement).
    if (resultat == null || !resultat.valide) return;
    if (!mounted) return;

    // ★ LOT 2-C — L'ISSUE NOMMÉE REMPLACE LE BOOLÉEN.
    //
    //   `enregistrerGainManuel` réduisait quatre situations distinctes à
    //   `true`/`false`, et le booléen était ensuite traduit en un SnackBar
    //   VERT (« enregistré ») même quand seule la copie temporaire, purgée au
    //   bout de 24 h, avait été écrite. Une seule opération pouvait donc
    //   afficher deux messages successifs, dont un mensonger.
    //
    //   Ici : UN SEUL message, produit par `_snackBarIssueGain`, et qui ne dit
    //   « enregistré » que si le disque le confirme.
    final issue = await widget.alertSvc
        .enregistrerGainManuelDetaille(widget.storageKey, resultat.montant);
    if (!mounted) return;

    setState(() {}); // rafraîchit le libellé du ticket, sans changer d'écran.
    _snackBarIssueGain(issue, resultat.montant);
  }

  /// ★ B1-T12 / LOT 2-C — UN SEUL SnackBar PAR OPÉRATION, ET IL DIT LA VÉRITÉ.
  ///
  /// COULEURS — une seule par opération, jamais de vert suivi d'un orange :
  ///   • vert   : le gain a été écrit DURABLEMENT (il survivra à la purge) ;
  ///   • orange : la saisie est prise en compte, mais sa conservation est
  ///              LIMITÉE et la limite est écrite noir sur blanc ;
  ///   • rouge  : rien n'a été enregistré, ou l'issue est incertaine.
  ///
  /// ⚠️ AUCUN ÉTAT N'EST ANNONCÉ « ENREGISTRÉ » SANS PREUVE D'ÉCRITURE.
  void _snackBarIssueGain(ResultatEcritureGain issue, double? montant) {
    final String texte;
    final Color couleur;

    switch (issue) {
      case ResultatEcritureGain.complet:
        texte = montant == null
            ? 'Gain déclaré retiré et enregistré durablement : '
                'le rapport officiel fait de nouveau foi.'
            : 'Gain déclaré enregistré durablement : ${fmtEuros(montant)} € brut.';
        couleur = const Color(0xFF2E7D52); // vert

      case ResultatEcritureGain.durableSeul:
        texte = 'Gain enregistré durablement, mais l\'affichage du suivi n\'a '
            'pas pu être mis à jour. Le montant est conservé.';
        couleur = const Color(0xFFE08A00); // orange

      case ResultatEcritureGain.nonLie:
        // Ticket créé par « Suivre une course » : aucune liaison durable.
        texte = 'Gain enregistré pour ce suivi UNIQUEMENT : ce ticket n\'est pas '
            'lié à un pari du profil, il sera donc supprimé au bout de 24 h.';
        couleur = const Color(0xFFE08A00); // orange

      case ResultatEcritureGain.echecFinancier:
        texte = 'Gain NON enregistré : l\'écriture a échoué.';
        couleur = const Color(0xFFB71C1C); // rouge

      case ResultatEcritureGain.ticketIntrouvable:
        texte = 'Ticket introuvable : le gain n\'a pas été enregistré.';
        couleur = const Color(0xFFB71C1C); // rouge

      case ResultatEcritureGain.remplaceeParPlusRecente:
        texte = 'Gain NON enregistré : une saisie plus récente sur ce même '
            'ticket a pris le dessus.';
        couleur = const Color(0xFFE08A00); // orange

      case ResultatEcritureGain.echecNonReconcilie:
        texte = 'Gain NON enregistré, et la cohérence n\'a pas pu être '
            'rétablie. Vérifiez le montant affiché avant de réessayer.';
        couleur = const Color(0xFFB71C1C); // rouge
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texte), backgroundColor: couleur),
    );
  }

  String _calculerGainAffiche(TrackedCourse c) {
    // ★ B1-T12 / LOT 2-C — DÉCISION DURABLE D'ABORD.
    //
    //   Le gain déclaré par l'utilisateur (lot 2-A) était persisté mais
    //   affiché NULLE PART : la carte continuait d'annoncer « ⏳ En attente du
    //   rapport officiel » alors que le montant était enregistré. La branche ①
    //   ci-dessous le rend enfin visible, et rend aussi l'effet d'une décision
    //   Accepter/Refuser.
    //
    //   ⚠️ LA GARDE NE S'ACTIVE QUE SUR PREUVE DURABLE. `vueDurable` rend
    //      `null` quand un verdict officiel existe (les branches ② à ⑦
    //      historiques reprennent alors la main), quand aucune décision ni
    //      déclaration n'existe, et quand aucun `UserPrediction` n'est lié.
    //      Un ticket qui n'a jamais connu le lot 2-C garde donc exactement
    //      son libellé d'avant.
    final durable = _vueDurable();
    if (durable != null) return durable.libelle;

    // ★ LOT B-4.5 — Vérité OFFICIELLE d'abord. Un ticket qui porte un verdict
    //   (`etatGain != null`) est décrit EXCLUSIVEMENT par ce verdict : les
    //   quatre états sont distingués, et le montant affiché est une somme de
    //   `montantRetour` déjà persistés. `isGagne` et `dividendePmuReel` ne sont
    //   alors même pas lus, donc l'historique ne peut pas contredire le verdict.
    if (c.etatGain != null) {
      return affichageGainSuivi(c).libelle;
    }

    final mise = c.miseTotaleEngagee;
    if (mise == null || mise <= 0) {
      return _isGagnant == true ? '🏆 Pari gagnant' : '❌ Perdu';
    }
    if (_isGagnant == false) {
      return '❌ Perdu : -${fmtEuros(mise)} €';
    }
    // ★ LOT B-4.5 / A-0 — INTERDICTION DU FAUX GAIN GAGNANT+PLACÉ.
    //
    //   Même raison que dans `_gainBrut` : `dividendePmuReel` est le dividende
    //   d'UNE composante, `miseTotaleEngagee` la somme des DEUX. Leur produit
    //   n'est pas un gain. Mesuré : « 🏆 Gain gagné : 180 € brut » sur un
    //   ticket historique 18,00 × 10 €.
    //
    //   Le libellé « Gain gagné » est une AFFIRMATION de gain confirmé : il
    //   est donc interdit ici. On ne bascule PAS pour autant vers « 0 € » ni
    //   vers « Perdu » : on annonce l'état réel, indéterminé, sans montant.
    //   La donnée historique reste intacte sur le ticket.
    if (estTypeGagnantPlace(c.typePari)) {
      return '⏳ Gain Gagnant+Placé non établi : deux composantes distinctes';
    }
    if (c.dividendePmuReel != null && c.dividendePmuReel! > 0) {
      // Gain GAGNÉ : rapport officiel identifié.
      final retour = c.dividendePmuReel! * mise;
      return '🏆 Gain gagné : ${fmtEuros(retour)} € brut';
    }
    if (c.cote > 1.0) {
      // Gain POTENTIEL : ce n'est pas un gain officiellement acquis.
      return '📐 Gain potentiel : ${fmtEuros(c.cote * mise)} € brut';
    }
    return '⏳ En attente du rapport officiel';
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
          // ★ FIX A6 : `Flexible` + `softWrap`.
          //   À 320 dp, le libellé « À venir dans 5h30min » dépassait la
          //   largeur utile de la carte (`RenderFlex overflowed`). Le texte
          //   passe désormais à la ligne au lieu de déborder.
          //   ❗Aucun `ellipsis`, aucune information retirée : le libellé
          //   complet reste affiché, simplement sur deux lignes si besoin.
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              softWrap: true,
              style: TextStyle(
                color: statutColor,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
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
        // ★ FIX A6 : `Flexible` + `softWrap`.
        //   À 320 dp, « Confiance IA : 78/100 — Élevée » dépassait la largeur
        //   de la carte. Le texte passe désormais à la ligne.
        //   ❗Aucun `ellipsis`, aucun retrait du score ni du qualificatif.
        Flexible(
          child: Text(
            score <= 0
                ? 'Confiance IA : —'
                : 'Confiance IA : ${score.round()}/100 — $label',
            softWrap: true,
            style: TextStyle(color: couleur, fontSize: 12, fontWeight: FontWeight.w600),
          ),
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
  // ★ SOUS-LOT B : mise NULLABLE. Une mise absente ou illisible n'est plus
  //   remplacée par 10 € — c'était une mise inventée qui faussait tout le
  //   calcul du ticket. `null` ⇒ l'ajout est refusé avec un message explicite.
  double? _mise = 10.0;
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
                    // ★ SOUS-LOT B : plus de repli à 10 €. Un champ vide ou
                    //   illisible ⇒ _mise = null (mise non renseignée).
                    onChanged: (v) {
                      final parsed = double.tryParse(v.trim());
                      setState(() => _mise = (parsed != null && parsed > 0) ? parsed : null);
                    },
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
                        // ★ SOUS-LOT B : sans mise valide, on n'enregistre PAS
                        //   de ticket financier — plutôt que d'inventer 10 €.
                        final miseSaisie = _mise;
                        if (miseSaisie == null || miseSaisie <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Mise invalide : saisissez un montant supérieur à 0 €.'),
                              backgroundColor: Color(0xFFB71C1C),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        widget.alertSvc.ajouterSuivi(TrackedCourse(
                          numReunion: c.numReunion,
                          numCourse: c.numCourse,
                          nomCourse: c.nomCourse,
                          hippodrome: c.hippodrome,
                          heureDepart: c.heureDepart,
                          nomCheval: _nomCheval,
                          numeroCheval: _numCheval,
                          miseEngagee: miseSaisie,
                          typePari: _typePari,
                          // ★ LOT B2-C : Gagnant+Placé engage DEUX mises distinctes.
                          //   Règle impérative : 10 € saisis = 10 € Gagnant
                          //   + 10 € Placé = 20 € engagés. La mise saisie n'est
                          //   JAMAIS divisée par deux. Autres paris : null.
                          miseGagnant: estTypeGagnantPlace(_typePari)
                              ? miseSaisie
                              : null,
                          misePlace: estTypeGagnantPlace(_typePari)
                              ? miseSaisie
                              : null,
                          // ★ SOUS-LOT B : aucune cote n'est disponible dans ce
                          //   formulaire (saisie manuelle sans partants chargés).
                          //   On enregistre null plutôt qu'une cote inventée :
                          //   le « Gain potentiel » restera « non calculable ».
                          coteGagnant: null,
                          cotePlace: null,
                          // ★ ÉTAPE 4-F : la capture du pari réellement joué est
                          //   transmise au ticket. À ce stade (étape 1) les
                          //   sélecteurs ne renseignent pas encore ces valeurs :
                          //   elles restent `null`, ce qui est l'état attendu
                          //   d'un ticket non capturé. Les étapes 2 à 4 les
                          //   alimenteront. Les écrire ICI dès maintenant évite
                          //   d'oublier cette propagation, qui est le point de
                          //   perte identifié par le diagnostic 4-F.
                          codePmuOfficiel: null,
                          varianteChoisie: null,
                          numerosDansOrdre: null,
                          formulePari: null,
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
