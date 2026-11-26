import 'dart:async';

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
import 'screens/audit_screen.dart';
import 'screens/simulation_screen.dart';
import 'services/alert_service.dart';
import 'services/ia_memory_service.dart';
import 'services/elo_service.dart';
import 'services/reprise_restauration_service.dart';
import 'services/data_refresh_service.dart';
import 'services/ia_personality_service.dart'; // ★ v9.85
import 'services/ia_user_prefs_service.dart';  // ★ v9.85
import 'services/ia_badges_service.dart';      // ★ v9.85
import 'services/ia_archive_service.dart';      // ★ A1/R1 — archive des pronostics évincés
import 'services/arrivee_officielle_service.dart'; // ★ L2-1 — arrivées officielles complètes (L0)
import 'services/quasi_gros_paris_service.dart' show QuasiGrosParisService; // ★ v10.75b
import 'services/planificateur_gains_tardifs.dart'; // ★ CHANTIER 2/3 — déclencheurs du rattrapage
import 'services/service_gains_tardifs.dart';        // ★ CHANTIER 2/3 — orchestrateur du rattrapage
import 'services/gains_tardifs_en_attente.dart'
    show aDesDecisionsEnAttente, decisionsEnAttente; // ★ CHANTIER 2/3
import 'widgets/bloc_decision_gain_tardif.dart'; // ★ CHANTIER 2/3 — Accepter/Refuser
import 'widgets/ia/ia_bubble_widget.dart';      // ★ v9.85
import 'screens/roi_value_screen.dart';          // ★ v10.46 ROI/Value

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
  void goToSimulation()     => goTo(7); // ★ Laboratoire IA
  void goToRoiValue()        => goTo(8); // ★ v10.46 ROI/Value analytics
  void goToAudit()          => goTo(9); // ★ Audit IA section principale

  // ★ v9.92 : onglet interne demandé à l'ouverture de MesParis
  int _mesParisPendingTab = 0;
  int get mesParisPendingTab => _mesParisPendingTab;
  void requestMesParisSuivi() {
    _mesParisPendingTab = 1; // index 1 = Suivi
    goTo(6); // Mes Paris reste à l'index 6
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
  // ★ A1/R1 — L'archive est chargée AVANT `runApp()` afin que les séries
  //   Premium (Home, Best Bet) retrouvent les pronostics évincés dès le
  //   PREMIER rendu. Sans ce chargement, le repli d'A1 reste sans effet
  //   (`versionRetenue` renvoie null) : le calendrier était le seul écran à
  //   déclencher `charger()`, et seulement à son ouverture.
  //   • `charger()` est idempotent : l'appel du calendrier devient un no-op.
  //   • Aucun chargement disque répétitif (mesuré : 2e appel ≈ 0,1 ms).
  //   • Il absorbe ses erreurs : une panne de stockage ne bloque pas le
  //     démarrage, le comportement redevient celui d'avant A1.
  //   • Lecture seule : rien n'est réinjecté dans les 600 pronostics actifs.
  await IaArchiveService.instance.charger();
  // ★ L2-1 — Initialisation de L0 AVANT `runApp()`.
  //
  //   `ArriveeOfficielleService.arrivee()` lit UNIQUEMENT la RAM (`_shards`)
  //   et ne déclenche AUCUN chargement. Sans cet appel, le service resterait
  //   `_charge == false` tant qu'aucune arrivée n'aurait été capturée dans le
  //   cycle courant (`zone_turf_service.dart:293` sort AVANT `charger()` si
  //   `entrees` est vide). L'affichage L0 retournerait alors `null` en
  //   silence, alors que les arrivées sont bien sur le disque.
  //
  //   • `charger()` est idempotent : l'appel de `zone_turf_service` devient
  //     un no-op (mesuré : retour immédiat si `_charge`).
  //   • Il absorbe ses erreurs : une panne de stockage ne bloque pas le
  //     démarrage.
  //   • Il peut REJOUER la file d'attente déjà persistée (`persisterEnAttente`)
  //     — reprise d'entrées préexistantes, jamais création. Rejeu par
  //     processus, gardé par `_rejeuFileEffectue`.
  //   • AUCUN effet sur l'IA : pas d'apprentissage, pas de poids, pas de
  //     seuil, pas d'ELO, aucun appel réseau, aucune arrivée créée.
  await ArriveeOfficielleService.instance.charger();
  await EloService.init();
  // ★ Reprise d'une restauration interrompue (§1).
  //
  //   Placée APRÈS `EloService.init()` parce qu'elle a besoin du dépôt
  //   structuré ouvert, et AVANT `runApp()` parce qu'il serait dangereux
  //   d'afficher un état que la reprise va corriger : l'utilisateur verrait des
  //   données périmées, croirait à un échec, et relancerait une opération.
  //
  //   Ne lève jamais : une reprise impossible est constatée et journalisée,
  //   elle ne bloque pas le démarrage. N'écrit que si un travail a réellement
  //   été interrompu — le cas normal ne coûte qu'une lecture de méta.
  await RepriseRestaurationService.instance.executerAuDemarrage();
  await IaPersonalityService.init(); // ★ v9.85
  await IaUserPrefsService.init();   // ★ v9.85
  await IaBadgesService.init();      // ★ v9.85
  // ★ v10.76 : Migration one-shot gros paris (idempotente, jamais bloquante)
  // Doit être après IaMemoryService.init() (enregistrement du provider arrivées PMU)
  // Retourne MigrationGrosParisResult avec logs signaux/gagnants/quasiSupprimes
  QuasiGrosParisService.instance.migrerGrosParisDesordreSiBesoin().ignore();
  // ★ v10.77 : Migration stats v2 — force réinjection gros paris dans
  // PronosticResultatsRepository pour visibilité dans IA Stats / Calendrier / Précision.
  // Idempotente : protégée par flag 'ia_migration_gros_paris_stats_v2_done'.
  QuasiGrosParisService.instance.migrerGrosParisStatsSiBesoin().ignore();
  // ★ v10.79 : Migration types dérivés — évalue Tiercé/Quarté+/Quinté+ séparément
  // pour chaque signal Gros Paris. Écrit gagnants ET perdants dans le repository
  // afin que les stats par type soient correctes (Tiercé gagnant même si signal=Quinté+).
  // Idempotente : protégée par flag 'ia_migration_gros_paris_types_derives_v1_done'.
  QuasiGrosParisService.instance.migrerStatsParTypesSiBesoin().ignore();
  // ★ v10.80 : Migration suite IA classique — réussites dérivées depuis topNIA figé.
  // Alimente le repository avec Tiercé/Quarté+/Quinté+ gagnants issus des pronostics IA.
  // source = 'suiteIAClassique', utilisableApprentissage = false (jamais gradient).
  // Idempotente : protégée par flag 'ia_migration_suite_ia_classique_v1_done'.
  IaMemoryService.instance.migrerSuiteIAClassiqueSiBesoin().ignore();
  // ★ v10.77 : Diagnostic preuve injection — log 4 métriques au démarrage (debug only)
  // [1] chargés repo [2] injectés stats [3] Tiercé 21/05 [4] 0 violation gradient
  Future.delayed(const Duration(seconds: 3), () {
    IaMemoryService.instance.diagnosticPronosticRepository(
      dateVerif: DateTime(2026, 5, 21),
    );
  });
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

class _MainNavigationState extends State<MainNavigation>
    with WidgetsBindingObserver {
  List<Widget> _screens = [];
  static const _deepLinkChannel = MethodChannel('com.racepredictor.predict/deep_link');

  /// ★ CHANTIER 2/3 — déclencheurs du rattrapage des gains officiels tardifs.
  /// Construit paresseusement : `SharedPreferences` n'est pas encore ouvert au
  /// premier `initState`, la fabrique s'en charge donc à l'appel.
  PlanificateurGainsTardifs? _planificateur;

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
      const MesPariScreen(),      // 6 — Mes Paris
      const SimulationScreen(),    // 7 — Labo IA Simulation
      const RoiValueScreen(),        // 8 — ROI/Value ★ v10.46
      const AuditScreen(),         // 9 — Audit IA
      const ProfileScreen(),       // 10 — Profil
    ];
    Future.microtask(() {
      if (mounted) {
        final pmuProvider = context.read<PmuProvider>();
        AlertService.instance.setPmuProvider(pmuProvider);
      }
    });

    // ★ CHANTIER 2/3 — DÉCLENCHEURS DU RATTRAPAGE DES GAINS TARDIFS.
    //
    // ① OUVERTURE DE L'APPLICATION : un cycle part dès que le provider est
    //    disponible, puis le minuteur périodique (③) est armé.
    // ② RETOUR AU PREMIER PLAN : traité dans [didChangeAppLifecycleState].
    //
    // ⚠️ POURQUOI UN `microtask` ET NON UN APPEL DIRECT :
    //    `Provider.of`/`context.read` n'est pas lisible avant que le premier
    //    build n'ait eu lieu. Le `microtask` laisse passer le build courant.
    //
    // ⚠️ AUCUNE EXCEPTION NE REMONTE : `demarrer()` capture tout. Une panne
    //    de rattrapage ne doit jamais empêcher l'application de démarrer.
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() async {
      if (!mounted) return;
      final pmuProvider = context.read<PmuProvider>();
      final planificateur = PlanificateurGainsTardifs(
        fabrique: () => ServiceGainsTardifs.creer(pmuProvider),
      );
      _planificateur = planificateur;
      await planificateur.demarrer();
      // ★ CHANTIER 2/3 — présentation des décisions en attente APRÈS le premier
      //   cycle : une décision peut avoir été découverte pendant ce cycle.
      //   `_presenterDecisionsEnAttenteSiBesoin` est idempotente par session et
      //   ne fait rien s'il n'y a rien à décider.
      _presenterDecisionsEnAttenteSiBesoin();
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
  // ★ v10.46 : ROI/Value inséré en index 8 — Audit→9, Profil→10
  // Ordre : 0=Accueil | 1=Conseils | 2=Programme | 3=Courses | 4=BestBet | 5=IAStats | 6=MesParis | 7=LaboIA | 8=ROI/Value | 9=Audit | 10=Profil
  static const List<_NavDef> _navItems = [
    _NavDef(icon: Icons.home_outlined,           activeIcon: Icons.home,             label: 'Accueil',   color: Color(0xFF4CAF7D)), // Vert app
    _NavDef(icon: Icons.auto_awesome_outlined,   activeIcon: Icons.auto_awesome,     label: 'Conseils',  color: Color(0xFF7C4DFF)), // Violet IA
    _NavDef(icon: Icons.calendar_today_outlined, activeIcon: Icons.calendar_today,   label: 'Prog.',     color: Color(0xFF29B6F6)), // Bleu ciel
    _NavDef(icon: Icons.sports_outlined,         activeIcon: Icons.sports,           label: 'Courses',   color: Color(0xFFFF7043)), // Orange sport
    _NavDef(icon: Icons.emoji_events_outlined,   activeIcon: Icons.emoji_events,     label: 'Best Bet',  color: Color(0xFFFFD700)), // Or trophée
    _NavDef(icon: Icons.psychology_outlined,     activeIcon: Icons.psychology,       label: 'IA Stats',  color: Color(0xFFE040FB)), // Rose/Magenta cerveau
    _NavDef(icon: Icons.track_changes_outlined,  activeIcon: Icons.track_changes,    label: 'Mes Paris', color: Color(0xFF00BCD4)), // Cyan suivi
    _NavDef(icon: Icons.science_outlined,        activeIcon: Icons.science,          label: 'Labo IA',   color: Color(0xFF00E5FF)), // Cyan — Labo Simulation
    _NavDef(icon: Icons.trending_up_outlined,    activeIcon: Icons.trending_up,      label: 'ROI/Value', color: Color(0xFF4CAF50)), // Vert ROI ★ v10.46
    _NavDef(icon: Icons.find_in_page_outlined,   activeIcon: Icons.find_in_page,     label: 'Audit',     color: Color(0xFFFFD700)), // Or — Audit IA
    _NavDef(icon: Icons.person_outline,          activeIcon: Icons.person,           label: 'Profil',    color: Color(0xFFB0BEC5)), // Argent neutre
  ];

  // ★ CHANTIER 2/3 — DÉCLENCHEUR ② : RETOUR AU PREMIER PLAN.
  //
  // `resumed` est le seul état où l'utilisateur REGARDE l'application : c'est
  // donc le seul moment où un gain officiel arrivé pendant l'absence a un sens
  // à être remonté. On ne relance rien en `inactive`/`paused`/`hidden`, ce qui
  // évite des cycles dans le dos de l'utilisateur.
  //
  // ⚠️ Le planificateur applique sa propre distance minimale : un aller-retour
  //    rapide entre deux applications ne produit pas deux cycles.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) return;
    final planificateur = _planificateur;
    if (planificateur == null) return;
    // Aucun `await` : on ne bloque pas le cycle de vie. Les erreurs sont déjà
    // capturées à l'intérieur du planificateur.
    unawaited(planificateur.retourPremierPlan());
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ CHANTIER 2/3 — PRÉSENTATION DES DÉCISIONS EN ATTENTE À L'OUVERTURE
  // ══════════════════════════════════════════════════════════════════════════
  //
  //  Exigence : « Une présentation initiale peut être fermée sans imposer une
  //  décision immédiate ; le ticket reste accessible ensuite. »
  //
  //  ⚠️ FERMER CETTE FEUILLE NE DÉCIDE RIEN. Aucun appel d'écriture n'a lieu
  //     ici. Si l'utilisateur ferme, le ticket reste dans la liste des
  //     décisions en attente (`decisionsEnAttente`) et dans Mes Paris.
  //
  //  ⚠️ ELLE NE S'OUVRE QU'UNE FOIS PAR SESSION : un drapeau en mémoire suffit,
  //     car rouvrir la feuille à chaque retour au premier plan serait
  //     harcelant, et persister ce drapeau empêcherait la présentation au
  //     démarrage suivant alors que la décision est toujours en attente.
  bool _decisionsPresentees = false;

  void _presenterDecisionsEnAttenteSiBesoin() {
    if (_decisionsPresentees) return;
    if (!mounted) return;
    final provider = context.read<PmuProvider>();
    final attentes = decisionsEnAttente(provider.predictions);
    if (attentes.isEmpty) return;
    _decisionsPresentees = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: const Color(0xFF0F1E2E),
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          maxChildSize: 0.9,
          builder: (ctx2, scrollController) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              Row(children: [
                const Icon(Icons.emoji_events,
                    color: Color(0xFFFFD700), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    attentes.length == 1
                        ? '1 décision vous attend'
                        : '${attentes.length} décisions vous attendent',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  tooltip: 'Fermer (la décision reste disponible)',
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ]),
              const Text(
                'Vous pouvez fermer cette fenêtre : votre choix reste '
                'possible depuis Mes Paris, à tout moment.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 10),
              for (final d in attentes)
                BlocDecisionGainTardif(
                  decision: d,
                  provider: provider,
                  compact: true,
                  onDecisionConfirmee: () {
                    if (mounted) setState(() {});
                  },
                ),
            ],
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _planificateur?.arreter();
    super.dispose();
  }

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

    // Badge orange sur Mes Paris (index 6) — Labo=7, ROI/Value=8, Audit=9, Profil=10 ★ v10.46
    final isMesParis = index == 6;
    // ★ CHANTIER 2/3 — une décision financière en attente compte comme un pari
    //   « en attente » : elle attend effectivement une action de l'utilisateur.
    //   La condition de sélection est la MÊME que celle des écrans
    //   (`attendDecisionGain`), donc la pastille ne peut pas annoncer une
    //   décision que les écrans ne montreraient pas — et inversement.
    final nbParisEnAttente = isMesParis
        ? context.select<PmuProvider, int>((p) =>
            p.predictions.where((pr) => pr.isCorrect == null).length +
            (aDesDecisionsEnAttente(p.predictions) ? 1 : 0))
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
            // ★ F1 — LE LIBELLÉ NE DOIT JAMAIS SE REPLIER.
            //   Sans contrainte, un libellé plus large que la place disponible
            //   se replie sur 2 lignes et fait déborder la `Column` du bas de
            //   la barre de navigation (mesuré : 6,0 px puis 3,0 px par onglet,
            //   soit les 9 erreurs de `test/widget_test.dart`). Le repli
            //   dépendait de la police du harnais (Ahem, 1 caractère = 1 em),
            //   mais le chemin non défilant de `_buildBottomNav` (écrans
            //   ≥ 836 dp) produit une troncature SILENCIEUSE en production.
            //   `maxLines: 1` + `softWrap: false` fixent la hauteur du libellé
            //   à une ligne ; `ellipsis` rend la troncature explicite au lieu
            //   de la couper net. Police, taille, couleur, graisse, données et
            //   navigation : INCHANGÉES. Hauteur de barre : 78 dp inchangée.
            Text(
              def.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
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


