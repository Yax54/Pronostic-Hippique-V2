import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ★ v9.84 : MethodChannel deep link
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'providers/pmu_provider.dart';
import 'screens/home_screen.dart';
import 'screens/programme_screen.dart';
import 'screens/races_screen.dart';
import 'screens/conseils_screen.dart';
import 'screens/best_bet_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/mes_paris_screen.dart';
import 'screens/ia_performance_screen.dart';
import 'services/alert_service.dart';
import 'services/ia_memory_service.dart';
import 'services/elo_service.dart';
import 'services/data_refresh_service.dart';
import 'services/ia_personality_service.dart'; // ★ v9.85
import 'services/ia_user_prefs_service.dart';  // ★ v9.85
import 'services/ia_badges_service.dart';      // ★ v9.85
import 'widgets/ia/ia_bubble_widget.dart';      // ★ v9.85

// ─── NavigationNotifier — remplace le GlobalKey fragile ──────────────────────
// Injecté dans le Provider : tout écran peut appeler
//   context.read<NavigationNotifier>().goTo(index)
// sans référence directe à l'état de MainNavigation.
class NavigationNotifier extends ChangeNotifier {
  int _index = 0;
  int get index => _index;

  void goTo(int index) {
    if (_index != index) {
      _index = index;
      notifyListeners();
    }
  }

  /// Raccourcis sémantiques pour les destinations fréquentes
  void goToMesParis()       => goTo(6);
  void goToMesParisSuivi()  => goTo(6); // ★ v9.92 : idem goToMesParis mais signale l'onglet Suivi
  void goToAccueil()        => goTo(0);
  void goToProgramme()      => goTo(2); // ★ v10.26 : Conseils déplacé en index 1 → Prog. passe en 2

  // ★ v9.92 : onglet interne demandé à l'ouverture de MesParis
  int _mesParisPendingTab = 0;
  int get mesParisPendingTab => _mesParisPendingTab;
  void requestMesParisSuivi() {
    _mesParisPendingTab = 1; // index 1 = Suivi
    goTo(6);
  }
  void clearMesParisPendingTab() {
    if (_mesParisPendingTab != 0) {
      _mesParisPendingTab = 0;
      // pas de notifyListeners ici — évite rebuild inutile
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AlertService.init();
  await IaMemoryService.init();
  await EloService.init();
  await IaPersonalityService.init(); // ★ v9.85
  await IaUserPrefsService.init();   // ★ v9.85
  await IaBadgesService.init();      // ★ v9.85
  // Lancement du rafraîchissement automatique (immédiat + toutes les 15 min)
  // Note : on lance sans await pour ne pas bloquer le démarrage de l'UI,
  // mais on s'assure bien que la Future est lancée via un ignore explicite.
  DataRefreshService.init().ignore();
  runApp(const PronosticHippiqueApp());
}

class PronosticHippiqueApp extends StatelessWidget {
  const PronosticHippiqueApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PmuProvider()),
        ChangeNotifierProvider(create: (_) => NavigationNotifier()),
        ChangeNotifierProvider.value(value: DataRefreshService.instance),
        ChangeNotifierProvider.value(value: AlertService.instance),         // ★ v10.40 : fix crash — context.watch<AlertService>()
        ChangeNotifierProvider.value(value: IaPersonalityService.instance), // ★ v9.85
        ChangeNotifierProvider.value(value: IaUserPrefsService.instance),   // ★ v9.85
        ChangeNotifierProvider.value(value: IaBadgesService.instance),      // ★ v9.85
        ChangeNotifierProvider.value(value: IaMemoryService.instance),      // ★ v10.7 : notif temps réel profil + IA
      ],
      child: MaterialApp(
        title: 'Pronostic Hippique',
        debugShowCheckedModeBanner: false,
        locale: const Locale('fr', 'FR'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('fr', 'FR'),
          Locale('en', 'US'),
        ],
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2E7D52),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF0D2818),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF0D2818),
            foregroundColor: Colors.white,
            elevation: 0,
            titleTextStyle: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          // ── Tailles de texte globales légèrement augmentées ──────────────
          textTheme: const TextTheme(
            // Titres principaux
            headlineLarge:  TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
            headlineMedium: TextStyle(fontSize: 23, fontWeight: FontWeight.bold, color: Colors.white),
            headlineSmall:  TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Colors.white),
            // Titres de section
            titleLarge:  TextStyle(fontSize: 18, fontWeight: FontWeight.bold,   color: Colors.white),
            titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,   color: Colors.white),
            titleSmall:  TextStyle(fontSize: 14, fontWeight: FontWeight.w600,   color: Colors.white),
            // Corps de texte
            bodyLarge:   TextStyle(fontSize: 16, color: Colors.white),
            bodyMedium:  TextStyle(fontSize: 14, color: Colors.white),
            bodySmall:   TextStyle(fontSize: 13, color: Colors.white70),
            // Labels / captions
            labelLarge:  TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
            labelMedium: TextStyle(fontSize: 13, color: Colors.white70),
            labelSmall:  TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ),
        home: IaBubbleOverlay(child: const MainNavigation()),
      ),
    );
  }
}


class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  List<Widget> _screens = [];
  static const _deepLinkChannel = MethodChannel('com.racepredictor.predict/deep_link');

  @override
  void initState() {
    super.initState();
    final alertSvc = AlertService.instance;
    _screens = [
      const HomeScreen(),       // 0 — Accueil
      const ConseilsScreen(),   // 1 — Conseils (★ v10.26 : déplacé après Accueil)
      const ProgrammeScreen(),  // 2 — Prog.
      const RacesScreen(),      // 3 — Courses
      const BestBetScreen(),    // 4 — Best Bet
      IaPerformanceScreen(alertService: alertSvc), // 5 — IA Stats
      const MesPariScreen(),    // 6 — Mes Paris
      const ProfileScreen(),    // 7 — Profil
    ];
    Future.microtask(() {
      if (mounted) {
        final pmuProvider = context.read<PmuProvider>();
        AlertService.instance.setPmuProvider(pmuProvider);
      }
    });

    // ★ v10.1 : Deep link — naviguer vers le pari concerné depuis une notification
    // Ouvre l'onglet Suivi (index 1) ET scrolle vers le paris concerné
    _deepLinkChannel.setMethodCallHandler((call) async {
      if (call.method == 'openCourse') {
        final tab       = call.arguments['tab']       as String? ?? '';
        final courseKey = call.arguments['courseKey'] as String? ?? '';
        if (!mounted) return;
        if (tab == 'mes_paris') {
          final navNotifier = context.read<NavigationNotifier>();
          // 1. Vérifier si le courseKey est dans les courses suivies
          final isSuivi = AlertService.instance.trackedCourses.keys.any(
            (k) => k.contains(courseKey) || courseKey.contains(k.split('_').first),
          );
          if (isSuivi) {
            // ★ v10.1 : Paris trouvé dans "Suivi" → ouvrir onglet Suivi (index 1)
            navNotifier.requestMesParisSuivi(); // navigue vers index 6 + demande onglet 1
          } else {
            // Sinon aller juste sur Mes Paris (onglet Favoris par défaut)
            navNotifier.goTo(6);
          }
          // 2. Déclencher le scroll vers le pari concerné (délai pour laisser la nav s'établir)
          if (courseKey.isNotEmpty) {
            Future.delayed(const Duration(milliseconds: 500), () {
              deepLinkCourseKeyNotifier.value = courseKey;
            });
          }
        }
      }
    });
  }

  // ★ v10.26 : Onglets reordonnés + couleurs uniques par destination
  // Ordre : Accueil | Conseils | Prog. | Courses | Best Bet | IA Stats | Mes Paris | Profil
  static const List<_NavDef> _navItems = [
    _NavDef(icon: Icons.home_outlined,           activeIcon: Icons.home,             label: 'Accueil',   color: Color(0xFF4CAF7D)), // Vert app
    _NavDef(icon: Icons.auto_awesome_outlined,   activeIcon: Icons.auto_awesome,     label: 'Conseils',  color: Color(0xFF7C4DFF)), // Violet IA
    _NavDef(icon: Icons.calendar_today_outlined, activeIcon: Icons.calendar_today,   label: 'Prog.',     color: Color(0xFF29B6F6)), // Bleu ciel
    _NavDef(icon: Icons.sports_outlined,         activeIcon: Icons.sports,           label: 'Courses',   color: Color(0xFFFF7043)), // Orange sport
    _NavDef(icon: Icons.emoji_events_outlined,   activeIcon: Icons.emoji_events,     label: 'Best Bet',  color: Color(0xFFFFD700)), // Or trophée
    _NavDef(icon: Icons.psychology_outlined,     activeIcon: Icons.psychology,       label: 'IA Stats',  color: Color(0xFFE040FB)), // Rose/Magenta cerveau
    _NavDef(icon: Icons.track_changes_outlined,  activeIcon: Icons.track_changes,    label: 'Mes Paris', color: Color(0xFF00BCD4)), // Cyan suivi
    _NavDef(icon: Icons.person_outline,          activeIcon: Icons.person,           label: 'Profil',    color: Color(0xFFB0BEC5)), // Argent neutre
  ];

  @override
  Widget build(BuildContext context) {
    // Écoute le NavigationNotifier pour changer d'onglet
    final currentIndex = context.watch<NavigationNotifier>().index;
    return Scaffold(
      body: IndexedStack(index: currentIndex, children: _screens),
      bottomNavigationBar: _buildBottomNav(currentIndex),
    );
  }

  Widget _buildBottomNav(int currentIndex) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF071510),
        border: Border(
          top: BorderSide(
            color: const Color(0xFF4CAF7D).withValues(alpha: 0.5),
            width: 2,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4CAF7D).withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.8),
            blurRadius: 16,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildScrollIndicator(currentIndex),
            SizedBox(
              height: 78,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final screenWidth = constraints.maxWidth;
                  const itemMinWidth = 76.0;
                  final totalMinWidth = _navItems.length * itemMinWidth;
                  final needsScroll = totalMinWidth > screenWidth;

                  if (!needsScroll) {
                    final itemWidth = screenWidth / _navItems.length;
                    return Row(
                      children: [
                        for (int i = 0; i < _navItems.length; i++)
                          SizedBox(
                            width: itemWidth,
                            child: _NavItem(
                              def: _navItems[i],
                              index: i,
                              current: currentIndex,
                              onTap: (idx) => context.read<NavigationNotifier>().goTo(idx),
                            ),
                          ),
                      ],
                    );
                  }

                  return ScrollConfiguration(
                    behavior: _NoGlowScrollBehavior(),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          for (int i = 0; i < _navItems.length; i++)
                            SizedBox(
                              width: itemMinWidth,
                              child: _NavItem(
                                def: _navItems[i],
                                index: i,
                                current: currentIndex,
                                onTap: (idx) => context.read<NavigationNotifier>().goTo(idx),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrollIndicator(int currentIndex) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_navItems.length, (i) {
          final isActive = i == currentIndex;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: isActive ? 16 : 4,
            height: 3,
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF4CAF7D)
                  : Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}

class _NoGlowScrollBehavior extends ScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}

class _NavDef {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final Color color; // ★ v10.26 : couleur unique par onglet
  const _NavDef({required this.icon, required this.activeIcon, required this.label, required this.color});
}

class _NavItem extends StatelessWidget {
  final _NavDef def;
  final int index;
  final int current;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.def,
    required this.index,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = current == index;

    // ★ v10.26 : couleur unique par onglet
    final activeColor = def.color;
    final inactiveColor = const Color(0xFF6B7B8A); // gris bleuté discret

    // Badge orange sur Mes Paris (index 6)
    final isMesParis = index == 6;
    final nbParisEnAttente = isMesParis
        ? context.select<PmuProvider, int>(
            (p) => p.predictions.where((pr) => pr.isCorrect == null).length)
        : 0;
    final showBadge = isMesParis && !isActive && nbParisEnAttente > 0;

    // Badge rouge sur Mes Paris si alertes non lues
    final nbAlertesNonLues = isMesParis
        ? AlertService.instance.unreadCount
        : 0;
    final showIaBadge = isMesParis && !isActive && nbAlertesNonLues > 0;

    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        decoration: BoxDecoration(
          // ★ v10.26 : fond teinté de la couleur propre à l'onglet
          color: isActive
              ? activeColor.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: isActive
              ? Border.all(color: activeColor.withValues(alpha: 0.75), width: 1.5)
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                // ★ v10.26 : icône colorée même à l'état inactif (mais plus sombre)
                Icon(
                  isActive ? def.activeIcon : def.icon,
                  color: isActive
                      ? activeColor
                      : inactiveColor,
                  size: 25,
                ),
                if (showBadge)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9800),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        nbParisEnAttente > 99 ? '99+' : '$nbParisEnAttente',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                if (showIaBadge)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE53935),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        nbAlertesNonLues > 99 ? '99+' : '$nbAlertesNonLues',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              def.label,
              style: TextStyle(
                // ★ v10.26 : label coloré quand actif, gris discret sinon
                color: isActive ? activeColor : inactiveColor,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


