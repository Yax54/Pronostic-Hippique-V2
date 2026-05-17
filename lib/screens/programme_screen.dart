// ═══════════════════════════════════════════════════════════════════
//  PROGRAMME SCREEN — Liste complète des réunions et courses du jour
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/favori_button.dart'; // ★ v9.3
import 'package:provider/provider.dart';
import '../main.dart' show NavigationNotifier;
import '../models/zt_models.dart';
import '../services/data_refresh_service.dart';
import '../services/ia_pronostic_engine.dart';
import '../services/alert_service.dart';
import '../widgets/bet_bottom_sheet.dart';
import '../widgets/arrivee_reelle_widget.dart';

import '../providers/pmu_provider.dart';
import 'course_detail_screen.dart';

class ProgrammeScreen extends StatefulWidget {
  const ProgrammeScreen({super.key});

  @override
  State<ProgrammeScreen> createState() => _ProgrammeScreenState();
}

class _ProgrammeScreenState extends State<ProgrammeScreen>
    with SingleTickerProviderStateMixin {
  List<ZtReunion> _reunions = [];
  bool _loading = true;
  String? _error;
  late TabController _tabController;
  int _activeTab = 0;

  // ── Timer pour actualiser les statuts en temps réel ──────────────
  // Rafraîchit l'affichage toutes les 30 secondes pour que le badge
  // "EN COURS" et le masquage du bouton "Parier" soient immédiats.
  Timer? _statutTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    // Actualisation périodique des statuts (EN COURS / TERMINÉE)
    _statutTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {}); // Recalcule diffMin pour chaque course
    });
    // Charger les données immédiatement depuis le cache du DataRefreshService
    // (disponibles instantanément si le cache local a été restauré)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chargerDonnees();
    });
  }

  @override
  void dispose() {
    _statutTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _chargerDonnees({bool refresh = false}) async {
    final svc = context.read<DataRefreshService>();

    // ÉTAPE 1 : charger immédiatement depuis le cache local du service
    // (disponible en < 5ms si le cache a été restauré au démarrage)
    if (svc.reunions.isNotEmpty && !refresh) {
      if (mounted) {
        final reunions = svc.reunions;
        setState(() {
          _reunions = reunions;
          _loading = svc.loading; // false si déjà chargé, true si en cours
          _error = svc.lastError;
          if (_tabController.length != reunions.length && reunions.isNotEmpty) {
            _tabController.dispose();
            _tabController = TabController(length: reunions.length, vsync: this);
          }
        });
      }
      if (!refresh) return; // Données du cache suffisantes, pas besoin d'attendre le réseau
    }

    if (refresh) {
      await svc.refresh();
    }
    if (mounted) {
      final reunions = svc.reunions;
      setState(() {
        _reunions = reunions;
        _loading = false;
        _error = svc.lastError;
        if (_tabController.length != reunions.length && reunions.isNotEmpty) {
          _tabController.dispose();
          _tabController = TabController(length: reunions.length, vsync: this);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Synchroniser les données avec le DataRefreshService
    final svc = context.watch<DataRefreshService>();
    // Mise à jour locale à chaque rebuild (rafraîchissement auto 15 min inclus)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Synchroniser si les données du service ont changé (longueur différente ou liste vide)
      final svcReunions = svc.reunions;
      final needsUpdate = svcReunions.isNotEmpty &&
          (_reunions.isEmpty ||
           _reunions.length != svcReunions.length ||
           (!svc.loading && _loading));
      if (needsUpdate) {
        setState(() {
          _reunions = svcReunions;
          _loading = svc.loading;
          _error = svc.lastError;
          if (_tabController.length != _reunions.length && _reunions.isNotEmpty) {
            _tabController.dispose();
            _tabController = TabController(length: _reunions.length, vsync: this);
          }
        });
      } else if (_loading && !svc.loading) {
        setState(() {
          _loading = false;
          _error = svc.lastError;
        });
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (!_loading && _error == null && _reunions.isNotEmpty)
              _buildReunionTabs(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // HEADER
  // ──────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    // Utiliser la date de la première réunion chargée si disponible, sinon aujourd'hui
    DateTime dateRef = DateTime.now();
    if (_reunions.isNotEmpty && _reunions.first.dateStr.length == 8) {
      final ds = _reunions.first.dateStr;
      try {
        dateRef = DateTime(
          int.parse(ds.substring(4, 8)),
          int.parse(ds.substring(2, 4)),
          int.parse(ds.substring(0, 2)),
        );
      } catch (_) {}
    }
    final jours = ['Lun','Mar','Mer','Jeu','Ven','Sam','Dim'];
    final mois = ['Jan','Fév','Mar','Avr','Mai','Juin','Juil','Août','Sep','Oct','Nov','Déc'];
    final jourNom = jours[dateRef.weekday - 1];
    final moisNom = mois[dateRef.month - 1];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D1B2A), Color(0xFF1A3A5C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          // Icône et titre
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF7D).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF4CAF7D).withValues(alpha: 0.4)),
            ),
            child: const Text('🏇', style: TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Programme Courses',
                    style: TextStyle(color: Colors.white, fontSize: 16,
                        fontWeight: FontWeight.bold)),
                Text('$jourNom ${dateRef.day} $moisNom ${dateRef.year} • Zone-Turf',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 14)),
              ],
            ),
          ),
          // Refresh avec statut DataRefreshService
          Consumer<DataRefreshService>(
            builder: (ctx, svc, _) => svc.loading
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        color: Color(0xFF4CAF7D), strokeWidth: 2))
                : IconButton(
                    onPressed: () => _chargerDonnees(refresh: true),
                    icon: const Icon(Icons.refresh, color: Color(0xFF4CAF7D)),
                    tooltip: 'Actualiser (${svc.lastRefreshLabel})',
                  ),
          ),
          // Stats rapides
          if (_reunions.isNotEmpty)
            _buildQuickStats(),
        ],
      ),
    );
  }

  Widget _buildQuickStats() {
    final totalCourses = _reunions.fold(0, (a, r) => a + r.courses.length);
    final totalChevaux = _reunions.fold(0, (a, r) => a + r.totalPartants);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF4CAF7D).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('$totalCourses courses',
              style: const TextStyle(color: Color(0xFF4CAF7D), fontSize: 14,
                  fontWeight: FontWeight.bold)),
          Text('$totalChevaux chevaux',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 16)),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // ONGLETS RÉUNIONS
  // ──────────────────────────────────────────────────────────────────
  Widget _buildReunionTabs() {
    return Container(
      height: 68,
      color: const Color(0xFF0D1B2A),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        itemCount: _reunions.length,
        itemBuilder: (ctx, i) {
          final r = _reunions[i];
          final selected = _activeTab == i;
          return GestureDetector(
            onTap: () => setState(() => _activeTab = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: selected
                    ? Color(r.disciplineColor)
                    : const Color(0xFF1A2F3D),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? Color(r.disciplineColor)
                      : Colors.white.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(r.disciplineIcon, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 5),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.code,
                          style: TextStyle(
                              color: selected ? Colors.white : Colors.white70,
                              fontSize: 13, fontWeight: FontWeight.bold)),
                      Text(r.lieu.length > 8 ? '${r.lieu.substring(0, 8)}.' : r.lieu,
                          style: TextStyle(
                              color: selected
                                  ? Colors.white.withValues(alpha: 0.8)
                                  : Colors.white38,
                              fontSize: 11)),
                    ],
                  ),
                  if (r.courses.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${r.courses.length}',
                          style: const TextStyle(color: Colors.white,
                              fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // CORPS PRINCIPAL
  // ──────────────────────────────────────────────────────────────────
  Widget _buildBody() {
    // Si données disponibles (cache ou réseau) : afficher même pendant le refresh
    if (_reunions.isNotEmpty) {
      final reunion = _reunions[_activeTab < _reunions.length ? _activeTab : 0];
      return _buildReunionDetail(reunion);
    }
    // Seulement si vraiment aucune donnée : afficher loader ou erreur
    if (_loading) return _buildLoader();
    if (_error != null) return _buildError();
    return _buildEmpty();
  }

  Widget _buildLoader() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1A3A5C),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const CircularProgressIndicator(
              color: Color(0xFF4CAF7D), strokeWidth: 3),
        ),
        const SizedBox(height: 20),
        const Text('Chargement du programme...', 
            style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 6),
        Text('PMU • Données temps réel',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4),
                fontSize: 14)),
      ],
    ),
  );

  Widget _buildError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.signal_wifi_off, color: Color(0xFFFF6D00), size: 52),
          const SizedBox(height: 16),
          const Text('Connexion impossible', 
              style: TextStyle(color: Colors.white, fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Utilisation des données de démonstration',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 16)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => _chargerDonnees(refresh: true),
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF7D),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildEmpty() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('🏇', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 16),
        const Text('Aucune course disponible',
            style: TextStyle(color: Colors.white70, fontSize: 16)),
      ],
    ),
  );

  // ──────────────────────────────────────────────────────────────────
  // DÉTAIL RÉUNION — Liste des courses
  // ──────────────────────────────────────────────────────────────────
  Widget _buildReunionDetail(ZtReunion reunion) {
    if (reunion.courses.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(reunion.disciplineIcon, style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(reunion.lieu, style: const TextStyle(color: Colors.white,
                fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Données en cours de chargement...',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
          ],
        ),
      );
    }

    // Trier les courses par heure
    final coursesSorted = [...reunion.courses]
      ..sort((a, b) => a.heureDateTime.compareTo(b.heureDateTime));

    return RefreshIndicator(
      onRefresh: () => _chargerDonnees(refresh: true),
      color: const Color(0xFF4CAF7D),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Banner réunion
          _buildReunionBanner(reunion),
          const SizedBox(height: 12),
          // Liste des courses
          ...coursesSorted.map((course) => _buildCourseCard(course, reunion)),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildReunionBanner(ZtReunion reunion) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(reunion.disciplineColor).withValues(alpha: 0.3),
            Color(reunion.disciplineColor).withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Color(reunion.disciplineColor).withValues(alpha: 0.5),
        ),
      ),
      // ★ v10.52 : Row responsif — chips en Wrap + SizedBox fixe compteur
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icône discipline
          Text(reunion.disciplineIcon, style: const TextStyle(fontSize: 36)),
          const SizedBox(width: 14),
          // Zone centrale : nom + badges (Expanded pour absorber la largeur variable)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reunion.lieu.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 18,
                        fontWeight: FontWeight.w800, letterSpacing: 1),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                // Wrap : les badges se replient sur la ligne suivante si besoin
                // → plus jamais de chevauchement avec le compteur droite
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _chip(reunion.code, const Color(0xFF4CAF7D)),
                    _chip(reunion.discipline, Color(reunion.disciplineColor)),
                    _chip('${reunion.courses.length} course${reunion.courses.length > 1 ? 's' : ''}', Colors.white24),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Compteur chevaux : largeur fixe pour ne jamais être poussé
          SizedBox(
            width: 72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${reunion.totalPartants}',
                    style: const TextStyle(color: Colors.white, fontSize: 28,
                        fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text('chevaux',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 13),
                    maxLines: 1),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 16,
          fontWeight: FontWeight.w600)),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // CARTE COURSE
  // ──────────────────────────────────────────────────────────────────
  Widget _buildCourseCard(ZtCourse course, ZtReunion reunion) {
    final topIA = course.partantsParRangIA.take(3).toList();
    final hasPronos = course.pronosticZt.isNotEmpty || topIA.isNotEmpty;

    // Calcul statut en temps réel
    // ★ v94 : Paris fermés dès le départ (diffMin ≤ 0), pas à -40 min.
    // Une course de 1200m dure ~1,5 min : le PMU ferme les paris au départ.
    // "EN COURS" = entre 0 et -40 min ; "TERMINÉE" = après -40 min.
    // Le bouton Parier est masqué dès que la course a démarré (diffMin ≤ 0).
    final now = DateTime.now();
    final heure = course.heureDateTime;
    final diffMin = heure.difference(now).inMinutes;
    final vraiTerminee = diffMin < -40;          // badge TERMINÉE (grisé)
    final enCours     = diffMin < 0 && diffMin >= -40; // badge EN COURS
    final parisOuverts = diffMin > 0;             // paris possibles (avant départ)

    return GestureDetector(
      onTap: () => _ouvrirCourse(course, reunion),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: vraiTerminee
              ? const Color(0xFF0D1520)
              : const Color(0xFF132035),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: course.isQuinte
                ? const Color(0xFFFFD700).withValues(alpha: 0.6)
                : vraiTerminee
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.white.withValues(alpha: 0.08),
          ),
          boxShadow: course.isQuinte && !vraiTerminee
              ? [BoxShadow(color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                  blurRadius: 12, spreadRadius: 1)]
              : null,
        ),
        child: Column(
          children: [
            // Header course
            _buildCourseHeader(course, reunion, vraiTerminee, enCours, diffMin),
            // Pronostics IA si disponibles
            if (hasPronos) ...[
              const Divider(height: 1, color: Color(0xFF1E3A4A)),
              _buildPronosticsRow(course, topIA),
            ],
            // Partants (barre d'aperçu)
            if (course.partants.isNotEmpty)
              _buildPartantsApercu(course),
            // Bouton Parier — visible UNIQUEMENT avant le départ (diffMin > 0)
            // ★ v94 : masqué dès que la course commence (EN COURS ou TERMINÉE)
            if (parisOuverts)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // ★ Fix écran gris : capturer les Providers AVANT showBetSheet
                      // Dans un ListView builder le context n'a pas accès aux Providers
                      try {
                        // Pré-lecture du provider pour forcer le contexte Provider
                        // avant d'ouvrir le sheet (fix écran gris dans ListView)
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
                        debugPrint('[Programme] Parier erreur : $e');
                      }
                    },
                    icon: const Icon(Icons.euro, size: 15),
                    label: const Text(
                      'Parier',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D52),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),
                ),
              ),
            // Arrivée réelle PMU — affichée quand la course est terminée
            if (vraiTerminee)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: ArriveReelleWidget(
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
              ),
            // Badge "Paris fermés" affiché pendant EN COURS (course démarrée)
            if (enCours)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB300).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFFFFB300).withValues(alpha: 0.35)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_clock, color: Color(0xFFFFB300), size: 15),
                      SizedBox(width: 6),
                      Text(
                        'Course en cours — Paris fermés',
                        style: TextStyle(
                          color: Color(0xFFFFB300),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCourseHeader(ZtCourse course, ZtReunion reunion, bool vraiTerminee, bool enCours, int diffMin) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          // Heure ou badge terminée
          vraiTerminee
              ? SizedBox(
                  width: 56,
                  height: 44,
                  child: CustomPaint(painter: _TermineeBadgePainterProg()),
                )
              : Container(
                  width: 56,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: enCours
                        ? const Color(0xFFFFB300).withValues(alpha: 0.15)
                        : const Color(0xFF1A3A5C),
                    borderRadius: BorderRadius.circular(8),
                    border: enCours
                        ? Border.all(color: const Color(0xFFFFB300).withValues(alpha: 0.6))
                        : null,
                  ),
                  child: Column(
                    children: [
                      Text(course.heure,
                          style: TextStyle(
                              color: enCours
                                  ? const Color(0xFFFFB300)
                                  : const Color(0xFF4CAF7D),
                              fontSize: 16, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center),
                      if (enCours)
                        const Text('EN COURS',
                            style: TextStyle(color: Color(0xFFFFB300), fontSize: 8,
                                fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center),
                    ],
                  ),
                ),
          const SizedBox(width: 12),
          // Numéro + nom
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF7D).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('C${course.numCourse}',
                          style: const TextStyle(color: Color(0xFF4CAF7D),
                              fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                    if (course.isQuinte) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: const Color(0xFFFFD700).withValues(alpha: 0.5)),
                        ),
                        child: const Text('QUINTÉ+',
                            style: TextStyle(color: Color(0xFFFFD700),
                                fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(course.nom.isNotEmpty ? course.nom : 'Course ${course.numCourse}',
                    style: TextStyle(
                        color: vraiTerminee ? Colors.white54 : Colors.white,
                        fontSize: 16, fontWeight: FontWeight.w600),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          // Stats droite
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${course.partants.length}',
                  style: TextStyle(
                      color: vraiTerminee ? Colors.white38 : Colors.white,
                      fontSize: 20, fontWeight: FontWeight.bold)),
              Text('partants',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 16)),
              const SizedBox(height: 4),
              Text(course.distance,
                  style: const TextStyle(color: Color(0xFF80DEEA), fontSize: 14)),
              if (course.prix.isNotEmpty && course.prix != '?')
                Text('${course.prix}€',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 16)),
            ],
          ),
          // ★ v9.3 : Bouton favori
          FavoriButton(
            numR:       int.tryParse(reunion.code.replaceAll('R', '')) ?? 1,
            numC:       course.numCourse,
            nomCourse:  course.nom.isNotEmpty ? course.nom : 'Course \${course.numCourse}',
            hippodrome: reunion.lieu,
            scoreIA:    course.partantsParRangIA.isNotEmpty
                ? course.partantsParRangIA.first.scoreIA : 0.0,
            heure:      course.heure,
            distance:   course.distance,
            prix:       course.prix,
            size: 22,
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
        ],
      ),
    );
  }

  Widget _buildPronosticsRow(ZtCourse course, List<ZtPartant> topIA) {
    // Badge confiance IA
    Widget _confianceProgBadge(double confiance) {
      final Color badgeColor;
      final String label;
      if (confiance >= 80) {
        badgeColor = const Color(0xFF00E676);
        label = 'FORTE';
      } else if (confiance >= 65) {
        badgeColor = const Color(0xFFFFEA00);
        label = 'BONNE';
      } else if (confiance >= 50) {
        badgeColor = const Color(0xFFFF6D00);
        label = 'MOY.';
      } else {
        badgeColor = const Color(0xFFFF1744);
        label = 'BASSE';
      }
      // Si pas encore calculé, prendre le score du top1
      final double displayConf = confiance > 0
          ? confiance
          : (topIA.isNotEmpty ? topIA.first.scoreIA : 0.0);
      if (displayConf <= 0) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text('IA…', style: TextStyle(color: Colors.white38, fontSize: 10)),
        );
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: badgeColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: badgeColor.withValues(alpha: 0.6), width: 1),
        ),
        child: Text(
          '${displayConf.toStringAsFixed(0)}% $label',
          style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.bold),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        children: [
          // Pronostic IA
          if (topIA.isNotEmpty) ...[
            // Ligne 1 : badge confiance
            Row(
              children: [
                const Text('🤖', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 4),
                Text('IA :',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 13)),
                const SizedBox(width: 6),
                ...topIA.take(3).map((p) => _horseBadge(p, showScore: true)),
                const Spacer(),
                _confianceProgBadge(course.confianceIA),
              ],
            ),
          ],
          // Pronostic Zone-Turf
          if (course.pronosticZt.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 5,
              runSpacing: 4,
              children: [
                const Text('📊', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Text('ZT :',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 14)),
                const SizedBox(width: 8),
                ...course.pronosticZt.take(5).map((n) => _numBadge(n)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _horseBadge(ZtPartant p, {bool showScore = false}) {
    final color = Color(IaPronosticEngine.scoreColor(p.scoreIA));
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Text(p.numero,
          style: TextStyle(color: color, fontSize: 14,
              fontWeight: FontWeight.bold)),
    );
  }

  Widget _numBadge(int num) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF7B68EE).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: const Color(0xFF7B68EE).withValues(alpha: 0.5), width: 0.8),
      ),
      child: Text('$num',
          style: const TextStyle(color: Color(0xFF7B68EE), fontSize: 14,
              fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildPartantsApercu(ZtCourse course) {
    final partantsIA = course.partantsParRangIA.take(3).toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF0D1B2A),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 3 cartes chevaux — Expanded pour partager équitablement la largeur
          ...partantsIA.map((p) {
            final scoreColor = Color(IaPronosticEngine.scoreColor(p.scoreIA));
            return Expanded(
              child: Container(
                margin: const EdgeInsets.only(right: 5),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF132035),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scoreColor.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Numéro + nom sur 2 lignes pour éviter la troncature
                    Row(children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: scoreColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Center(
                          child: Text(p.numero,
                              style: TextStyle(
                                  color: scoreColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 3),
                    Text(p.nom,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1),
                    if (p.driver.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(p.driver,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1),
                    ],
                    // Barre de score IA
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: p.scoreIA / 100,
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                        valueColor: AlwaysStoppedAnimation(scoreColor),
                        minHeight: 3,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
          // ── Bouton "voir tout"
          GestureDetector(
            onTap: () => _ouvrirCourse(
                course,
                _reunions[_activeTab < _reunions.length ? _activeTab : 0]),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF7D).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFF4CAF7D).withValues(alpha: 0.3)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${course.partants.length}',
                      style: const TextStyle(
                          color: Color(0xFF4CAF7D),
                          fontSize: 14,
                          fontWeight: FontWeight.bold)),
                  const Text('voir\ntout',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                      textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _ouvrirCourse(ZtCourse course, ZtReunion reunion) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CourseDetailScreen(
          course: course,
          reunion: reunion,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  CustomPainter — carré blanc cassé + barre rouge diagonale (Prog)
// ═══════════════════════════════════════════════════════════
class _TermineeBadgePainterProg extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rectPaint = Paint()
      ..color = const Color(0xFFF5F0E8)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = const Color(0xFFCCC5B5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final linePaint = Paint()
      ..color = const Color(0xFFD32F2F)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(8),
    );
    canvas.drawRRect(rect, rectPaint);
    canvas.drawRRect(rect, borderPaint);
    canvas.drawLine(
      Offset(size.width * 0.12, size.height * 0.12),
      Offset(size.width * 0.88, size.height * 0.88),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
