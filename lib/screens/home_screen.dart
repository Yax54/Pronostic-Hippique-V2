// ═══════════════════════════════════════════════════════════════════
//  HOME SCREEN — PMU IA : courses à jour + conseil IA + meilleur pari
// ═══════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import '../widgets/favori_button.dart';
import 'package:provider/provider.dart';
import '../models/zt_models.dart';
import '../services/data_refresh_service.dart';
import '../services/ia_personality_service.dart';  // ★ v9.85
import '../services/ia_memory_service.dart';       // ★ v9.89
import '../widgets/ia/ia_bubble_widget.dart';       // ★ v9.85
import '../widgets/ia/ia_speech_widget.dart';       // ★ v9.85
import '../widgets/arrivee_reelle_widget.dart';
import 'programme_screen.dart';
import 'course_detail_screen.dart';
import 'fiche_cheval_screen.dart';
import 'ia_journal_screen.dart';                // ★ v9.89
import '../services/alert_service.dart';         // ★ v10.23
import '../main.dart' show NavigationNotifier;   // ★ v10.23
import 'ia_performance_screen.dart';             // ★ v10.27 : raccourci calendrier


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Les données viennent désormais du DataRefreshService (Provider global)

  // ★ fix #3 : _reunions lit depuis le service sans context.read hors build
  List<ZtReunion> get _reunions =>
      DataRefreshService.instance.reunions;

  // ★ fix #7 : cache pour éviter recalcul O(n²) à chaque rebuild
  List<ZtReunion>? _cachedReunionsPourCalc;
  ({ZtCourse? course, ZtPartant? cheval, ZtReunion? reunion})? _cachedMeilleurPari;
  ({ZtCourse? course, List<ZtPartant> top3, ZtReunion? reunion})? _cachedConseilIA;

  ({ZtCourse? course, ZtPartant? cheval, ZtReunion? reunion}) get _meilleurPariCached {
    final reunions = _reunions;
    if (_cachedMeilleurPari != null && identical(_cachedReunionsPourCalc, reunions)) {
      return _cachedMeilleurPari!;
    }
    _cachedReunionsPourCalc = reunions;
    _cachedMeilleurPari = _meilleurPari;
    _cachedConseilIA = null; // invalider l'autre cache aussi
    return _cachedMeilleurPari!;
  }

  ({ZtCourse? course, List<ZtPartant> top3, ZtReunion? reunion}) get _conseilIACached {
    final reunions = _reunions;
    if (_cachedConseilIA != null && identical(_cachedReunionsPourCalc, reunions)) {
      return _cachedConseilIA!;
    }
    _cachedReunionsPourCalc = reunions;
    _cachedConseilIA = _conseilIA;
    _cachedMeilleurPari = null; // invalider l'autre cache aussi
    return _cachedConseilIA!;
  }

  Future<void> _charger({bool refresh = false}) async {
    if (refresh) {
      await DataRefreshService.instance.refresh();
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────
  List<ZtCourse> get _toutesLesCourses =>
      _reunions.expand((r) => r.courses).toList();

  List<ZtCourse> get _prochainesCourses {
    final now = DateTime.now();
    final courses = _toutesLesCourses.where((c) {
      final h = c.heureDateTime;
      return h.isAfter(now.subtract(const Duration(minutes: 30)));
    }).toList();
    courses.sort((a, b) {
      final ha = a.heureDateTime, hb = b.heureDateTime;
      return ha.compareTo(hb);
    });
    return courses;
  }

  /// Meilleur pari du jour : course avec partant #1 IA le plus confiant
  ({ZtCourse? course, ZtPartant? cheval, ZtReunion? reunion}) get _meilleurPari {
    ZtCourse? bestCourse;
    ZtPartant? bestCheval;
    ZtReunion? bestReunion;
    double bestScore = -1;

    for (final reunion in _reunions) {
      for (final course in reunion.courses) {
        if (course.partants.isEmpty) continue;
        final sorted = course.partantsParRangIA;
        if (sorted.isNotEmpty) {
          final top = sorted.first;
          if (top.scoreIA > bestScore) {
            bestScore = top.scoreIA;
            bestCheval = top;
            bestCourse = course;
            bestReunion = reunion;
          }
        }
      }
    }
    return (course: bestCourse, cheval: bestCheval, reunion: bestReunion);
  }

  /// Conseil IA du Jour — ★ v9.6 : fixé pour TOUTE la journée
  /// Logique : meilleur équilibre score IA + dotation + confiance
  ///   1. Score IA ≥ 85/100 obligatoire
  ///   2. Quinté+ EN PRIORITÉ si score ≥ 85
  ///   3. Sinon : meilleur score IA × dotation combinés
  ///   4. Si égalité : course la plus tôt (plus de temps pour se préparer)
  ///   5. Affichée toute la journée même si la course est terminée
  ({ZtCourse? course, List<ZtPartant> top3, ZtReunion? reunion}) get _conseilIA {
    ZtCourse? selected;
    ZtReunion? selectedReunion;
    double bestScore = -1;

    // ── Étape 1 : Quinté+ avec score IA ≥ 85 ──────────────────────────
    for (final reunion in _reunions) {
      for (final course in reunion.courses) {
        if (!course.isQuinte) continue;
        if (course.partants.isEmpty) continue;
        final top = course.partantsParRangIA;
        if (top.isEmpty) continue;
        final scoreIA = top.first.scoreIA;
        if (scoreIA < 85) continue; // Score minimum requis
        // Score pondéré : score IA + bonus dotation
        final scorePondere = scoreIA + (course.dotationInt > 100000 ? 8.0 : 3.0);
        if (scorePondere > bestScore) {
          bestScore = scorePondere;
          selected = course;
          selectedReunion = reunion;
        }
      }
    }

    // ── Étape 2 : Toutes courses avec score IA ≥ 85 ───────────────────
    if (selected == null) {
      bestScore = -1;
      for (final reunion in _reunions) {
        for (final course in reunion.courses) {
          if (course.partants.isEmpty) continue;
          final top = course.partantsParRangIA;
          if (top.isEmpty) continue;
          final scoreIA = top.first.scoreIA;
          if (scoreIA < 85) continue;
          // Score pondéré : score IA + dotation + heure (courses tôt favorisées)
          final heureBonus = course.heureDateTime.hour < 15 ? 2.0 : 0.0;
          final scorePondere = scoreIA
              + (course.dotationInt > 200000 ? 10.0 : course.dotationInt > 100000 ? 5.0 : 0.0)
              + heureBonus;
          if (scorePondere > bestScore) {
            bestScore = scorePondere;
            selected = course;
            selectedReunion = reunion;
          }
        }
      }
    }

    // ── Étape 3 : Fallback — meilleur score IA sans seuil minimum ─────
    if (selected == null) {
      bestScore = -1;
      for (final reunion in _reunions) {
        for (final course in reunion.courses) {
          if (course.partants.isEmpty) continue;
          final top = course.partantsParRangIA;
          if (top.isEmpty) continue;
          final scoreIA = top.first.scoreIA;
          final scorePondere = scoreIA
              + (course.isQuinte ? 15.0 : 0.0)
              + (course.dotationInt > 100000 ? 5.0 : 0.0);
          if (scorePondere > bestScore) {
            bestScore = scorePondere;
            selected = course;
            selectedReunion = reunion;
          }
        }
      }
    }

    if (selected == null) return (course: null, top3: [], reunion: null);
    final top3 = selected.partantsParRangIA.take(3).toList();
    return (course: selected, top3: top3, reunion: selectedReunion);
  }

  @override
  void initState() {
    super.initState();
    // ★ v9.85 : Bulle matinale de l'IA au 1er chargement du jour
    WidgetsBinding.instance.addPostFrameCallback((_) => _declencherBulleMatinale());
  }

  Future<void> _declencherBulleMatinale() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    final svc       = IaPersonalityService.instance;
    final reunions  = DataRefreshService.instance.reunions;
    final nbCourses = reunions.fold<int>(0, (sum, r) => sum + r.courses.length);
    final conseil   = _conseilIACached;

    // ★ v10.23 : recalcul immédiat + résumé Conseil IA matinal
    final nbConseil = await AlertService.instance.recalculerCoursesConseilIA(reunions);
    final messageConseil = await AlertService.instance.verifierCoursesConseilIA(reunions);

    // Message bulle principal de l'IA
    final message = svc.messageBulle(
      nbCourses:    nbCourses,
      courseDuJour: conseil.course?.nom,
    );
    IaBubbleOverlayState.afficher(message);

    // ★ v10.23 : si message Conseil IA différent, l'afficher après 4 secondes
    if (messageConseil != null && messageConseil.isNotEmpty) {
      await Future.delayed(const Duration(seconds: 4));
      if (!mounted) return;
      IaBubbleOverlayState.afficher(messageConseil);
    }
    // Ignorer nbConseil — seulement pour déclencher le recalcul
    debugPrint('[HomeScreen] Conseil IA : $nbConseil courses trouvées');
  }

  @override
  Widget build(BuildContext context) {
    // Écoute le DataRefreshService pour se reconstruire automatiquement
    final svc = context.watch<DataRefreshService>();
    final loading = svc.loading;
    final error = svc.lastError;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF4CAF7D),
          backgroundColor: const Color(0xFF1A3A5C),
          onRefresh: () => _charger(refresh: true),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                // ── Indicateur de rafraîchissement discret ──────────────
                // Affiché en haut SEULEMENT si aucune donnée locale n'est
                // disponible (premier démarrage ou cache expiré).
                // Si le cache local est chargé, on montre les données
                // immédiatement et l'indicateur spinning du header suffit.
                if (loading && _reunions.isEmpty) _buildLoader(),
                // ── Erreur réseau (seulement si pas de données en cache) ─
                if (!loading && error != null && _reunions.isEmpty) _buildError(),
                // ── Données disponibles (cache local ou réseau) ──────────
                if (_reunions.isNotEmpty) ...[
                  // Bandeau discret "Mise à jour en cours..." si rafraîchissement réseau actif
                  if (loading) _buildRefreshBanner(),
                  _buildStatsBanner(),
                  const SizedBox(height: 16),
                  _buildJournalIACard(),            // ★ v9.89
                  const SizedBox(height: 8),
                  _buildRaccourciCalendrier(),      // ★ v10.27
                  const SizedBox(height: 10),
                  _buildBandeauConseilIA(),         // ★ v10.23
                  const SizedBox(height: 10),
                  _buildJourneeExpress(),           // ★ v10.24
                  const SizedBox(height: 10),
                  _buildConseilIA(),
                  const SizedBox(height: 20),
                  _buildMeilleurPari(),
                  const SizedBox(height: 20),
                  _buildProchainesCourses(),
                  const SizedBox(height: 20),
                  _buildReunions(),
                  const SizedBox(height: 24),
                ],
                // ── Vide : seulement si chargement terminé et vraiment 0 course ─
                if (!loading && _reunions.isEmpty)
                  _buildVide(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────
  Widget _buildHeader() {
    final now = DateTime.now();
    final jours = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    final mois = ['Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin', 'Juil', 'Août', 'Sep', 'Oct', 'Nov', 'Déc'];
    final jourNom = jours[now.weekday - 1];
    final moisNom = mois[now.month - 1];

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D1B2A), Color(0xFF1A3A5C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF7D).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF4CAF7D).withValues(alpha: 0.4)),
            ),
            child: const Text('🏇', style: TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pronostic Hippique',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                Text('$jourNom ${now.day} $moisNom ${now.year} • PMU IA',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 14)),
              ],
            ),
          ),
          if (context.watch<DataRefreshService>().loading)
            const SizedBox(
              width: 22, height: 22,
              child: CircularProgressIndicator(color: Color(0xFF4CAF7D), strokeWidth: 2),
            ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _charger(refresh: true),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF1A3A5C),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF4CAF7D).withValues(alpha: 0.4)),
              ),
              child: const Icon(Icons.refresh, color: Color(0xFF4CAF7D), size: 18),
            ),
          ),
        ],
      ),
    );
  }

  // ── Stats Banner ──────────────────────────────────────────────────
  Widget _buildStatsBanner() {
    final totalCourses = _toutesLesCourses.length;
    final totalChevaux = _toutesLesCourses.fold(0, (s, c) => s + c.partants.length);
    final totalReunions = _reunions.length;
    final quinte = _toutesLesCourses.where((c) => c.isQuinte).length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A3A5C), Color(0xFF0D2235)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF4CAF7D).withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _stat('🏟️', '$totalReunions', 'Réunions'),
          _dividerV(),
          _stat('🏁', '$totalCourses', 'Courses'),
          _dividerV(),
          _stat('🐴', '$totalChevaux', 'Chevaux'),
          _dividerV(),
          _stat('⭐', '$quinte', 'Quinté+'),
        ],
      ),
    );
  }

  Widget _stat(String emoji, String value, String label) => Column(
    children: [
      Text(emoji, style: const TextStyle(fontSize: 16)),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 13)),
    ],
  );

  Widget _dividerV() => Container(width: 1, height: 38, color: const Color(0xFF2A4A6A));

  // ── ★ v9.89 : Journal IA — carte Accueil ─────────────────────────
  Widget _buildJournalIACard() {
    final rapports = IaMemoryService.instance.rapports;
    final ia       = IaPersonalityService.instance;

    // Dernier rapport dispo (ou null si aucune analyse)
    final dernierRapport = rapports.isNotEmpty ? rapports.first : null;

    // Texte d'aperçu : première ligne du journal ou message par défaut
    final String apercu;
    if (dernierRapport == null) {
      apercu = 'Pas encore de journal — lance une analyse journée dans l\'onglet IA Stats.';
    } else {
      final nbResultats = dernierRapport.nbAvecResultat;
      final taux        = dernierRapport.tauxGagnant.toStringAsFixed(0);
      if (nbResultats == 0) {
        apercu = 'Dernière entrée : pas encore de résultats officiels pour valider mes pronostics.';
      } else {
        apercu = 'Dernière entrée : $nbResultats course${nbResultats > 1 ? "s" : ""} analysée${nbResultats > 1 ? "s" : ""}, $taux% de réussite.';
      }
    }

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const IaJournalScreen()),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1A3A), Color(0xFF0D1B2A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            // Avatar IA
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF7C4DFF).withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.5)),
              ),
              child: Center(
                child: Text(ia.avatarEmoji, style: const TextStyle(fontSize: 22)),
              ),
            ),
            const SizedBox(width: 12),
            // Texte
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📓 Journal de ${ia.prenom}',
                    style: const TextStyle(
                      color: Color(0xFF7C4DFF),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    apercu,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.70),
                      fontSize: 13,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios, color: Color(0xFF7C4DFF), size: 14),
          ],
        ),
      ),
    );
  }

  // ── ★ v10.27 : Raccourci compact "Calendrier IA Stat" ───────────
  Widget _buildRaccourciCalendrier() {
    return GestureDetector(
      onTap: () {
        context.read<NavigationNotifier>().goTo(5); // IA Stats = index 5
        Future.delayed(const Duration(milliseconds: 150), () {
          IaPerformanceScreen.ouvrirOngletCalendrier();
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF111F30),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: const Color(0xFF7C4DFF).withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF7C4DFF).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.4)),
              ),
              child: const Center(
                child: Text('📅', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Calendrier IA Stat',
                    style: TextStyle(
                      color: Color(0xFFB39DDB), // violet clair
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                    ),
                  ),
                  SizedBox(height: 1),
                  Text(
                    'Historique de performance par journée',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF4CAF7D), size: 16),
          ],
        ),
      ),
    );
  }

  // ── ★ v10.23 : Bandeau dynamique Conseil IA ──────────────────────
  Widget _buildBandeauConseilIA() {
    // ★ fix : context.watch pour rebuild automatique quand AlertService notifie
    final alertSvc = context.watch<AlertService>();
    final courses  = alertSvc.coursesConseilIA;

    return FutureBuilder<Map<String, dynamic>>(
      future: alertSvc.getCriteresConseilIA(),
      builder: (context, snap) {
        final criteres   = snap.data;
        final filtresActifs = criteres != null && (criteres['actifs'] as bool? ?? false);
        final nb         = courses.length;

        // ── Résumé des critères actifs pour l'affichage ──────────────
        String criteresLabel = '';
        if (filtresActifs) {
          final parts = <String>[];
          final types  = (criteres['types']  as List?)?.cast<String>() ?? [];
          final hippos = (criteres['hippos'] as List?)?.cast<String>() ?? [];
          final discs  = (criteres['discs']  as List?)?.cast<String>() ?? [];
          final conf   = criteres['confMin'] as int? ?? 0;
          if (types.isNotEmpty)  parts.add(types.take(2).join(' / '));
          if (conf > 0)          parts.add('≥$conf%');
          if (hippos.isNotEmpty) parts.add(hippos.take(2).join(' / '));
          if (discs.isNotEmpty)  parts.add(discs.take(2).join(' / '));
          criteresLabel = parts.join(' · ');
        }

        // ── État : filtres non activés ───────────────────────────────
        if (!filtresActifs) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF111F30),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                const Text('⚙️', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Filtres critères non activés — configure-les dans Conseils IA',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12),
                  ),
                ),
                GestureDetector(
                  onTap: () => context.read<NavigationNotifier>().goTo(1),
                  child: const Text('Configurer →',
                      style: TextStyle(color: Color(0xFF7C4DFF), fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }

        // ── État : filtres actifs, 0 course ─────────────────────────
        if (nb == 0) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF111F30),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFF6D00).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Text('😶', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Aucune course actuelle dans tes critères',
                          style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w600)),
                      if (criteresLabel.isNotEmpty)
                        Text(criteresLabel,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        // ── État : filtres actifs, X courses ─────────────────────────
        return GestureDetector(
          onTap: () => context.read<NavigationNotifier>().goTo(3),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF1A3A2A),
                  const Color(0xFF0D2218),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF4CAF7D).withValues(alpha: 0.6), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4CAF7D).withValues(alpha: 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Icône + compteur
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF7D).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF4CAF7D).withValues(alpha: 0.5)),
                  ),
                  child: Center(
                    child: Text('$nb',
                        style: const TextStyle(
                            color: Color(0xFF4CAF7D),
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                // Texte
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🎯 $nb course${nb > 1 ? 's correspondent' : ' correspond'} à tes critères',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      if (criteresLabel.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(criteresLabel,
                            style: TextStyle(
                                color: const Color(0xFF4CAF7D).withValues(alpha: 0.8),
                                fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
                // Flèche
                const Icon(Icons.arrow_forward_ios, color: Color(0xFF4CAF7D), size: 14),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Conseil IA ────────────────────────────────────────────────────
  Widget _buildConseilIA() {
    final conseil = _conseilIACached;
    if (conseil.course == null) return const SizedBox();
    final course = conseil.course!;
    final reunion = conseil.reunion;
    final top3 = conseil.top3;
    final lieu = reunion?.lieu ?? '';
    // ── Statut course : terminée si l'heure de départ est passée ──
    final courseTerminee = course.heureDateTime.isBefore(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('🤖 Conseil IA du Jour'),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A1A3A), Color(0xFF0D1B2A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // En-tête course
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C4DFF).withValues(alpha: 0.15),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Text(course.typeIcon, style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (course.isQuinte)
                                Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: const Color(0xFFFFD700)),
                                  ),
                                  child: const Text('QUINTÉ+', style: TextStyle(color: Color(0xFFFFD700), fontSize: 14, fontWeight: FontWeight.bold)),
                                ),
                              Expanded(
                                child: Text(course.nom,
                                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                          Text(
                            '$lieu • ${course.distance}m • ${course.prix}',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // ★ v9.5 : Bouton favori Conseil IA
                            if (reunion != null)
                              FavoriButton(
                                numR:      int.tryParse(reunion.code.replaceAll('R', '')) ?? 1,
                                numC:      course.numCourse,
                                nomCourse: course.nom,
                                hippodrome: lieu,
                                scoreIA:   course.confianceIA,
                                heure:     course.heure,
                                distance:  course.distance,
                                prix:      course.prix,
                                size: 24,
                              ),
                            Text(
                              course.heure,
                              style: TextStyle(
                                color: courseTerminee ? Colors.white38 : const Color(0xFF4CAF7D),
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                decoration: courseTerminee ? TextDecoration.lineThrough : null,
                              ),
                            ),
                          ],
                        ),
                        // ── Badge Terminée / Départ ──
                        if (courseTerminee)
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF5350).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFEF5350).withValues(alpha: 0.5)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.flag, color: Color(0xFFEF5350), size: 11),
                                SizedBox(width: 3),
                                Text('Terminée',
                                    style: TextStyle(color: Color(0xFFEF5350),
                                        fontSize: 11, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          )
                        else
                          const Text('Départ', style: TextStyle(color: Colors.white38, fontSize: 14)),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Bannière "Course terminée" si l'heure est passée ──
              if (courseTerminee)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.flag, color: Colors.white38, size: 16),
                      SizedBox(width: 8),
                      Text('Course terminée — Paris fermés',
                          style: TextStyle(color: Colors.white38, fontSize: 13,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),

              // Sélection IA
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7C4DFF).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('🧠 SÉLECTION IA', style: TextStyle(color: Color(0xFF7C4DFF), fontSize: 13, fontWeight: FontWeight.bold)),
                        ),
                        const Spacer(),
                        // Badge confiance globale de la course
                        _confianceBadgeHome(course.confianceIA),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Ligne PMU si cotes disponibles
                    if (course.pronosticPMU.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.3)),
                        ),
                        child: Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: [
                            const Text('🏇 PMU : ', style: TextStyle(color: Color(0xFFFFD700), fontSize: 12, fontWeight: FontWeight.bold)),
                            ...course.pronosticPMU.take(4).map((n) =>
                              Text('N°$n', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600))
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 4),
                    ...top3.asMap().entries.map((e) {
                      final i = e.key;
                      final p = e.value;
                      final medals = ['🥇', '🥈', '🥉'];
                      final colors = [const Color(0xFFFFD700), const Color(0xFFC0C0C0), const Color(0xFFCD7F32)];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors[i].withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: colors[i].withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          children: [
                            Text(medals[i], style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: 8),
                            Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                color: colors[i].withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(p.numero, style: TextStyle(color: colors[i], fontSize: 14, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.nom, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                                  if (p.driver.isNotEmpty)
                                    Text(p.driver, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                _iaBadge(p.scoreIA),
                                if (p.cote.isNotEmpty && p.cote != '?')
                                  Text('Cote: ${p.cote}', style: const TextStyle(color: Colors.white38, fontSize: 14)),
                                const SizedBox(height: 4),
                                // ★ v9.80 : Bouton Fiche cheval
                                GestureDetector(
                                  onTap: () => Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => FicheChevalScreen(partant: p, courseActuelle: course),
                                  )),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: colors[i].withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: colors[i].withValues(alpha: 0.35)),
                                    ),
                                    child: Text('Fiche', style: TextStyle(color: colors[i], fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                    if (top3.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7C4DFF).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.auto_awesome, color: Color(0xFF7C4DFF), size: 14),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                top3.first.explicationIA.isNotEmpty
                                    ? top3.first.explicationIA
                                    : '${top3.first.nom} est notre favori IA pour cette course.',
                                style: const TextStyle(color: Colors.white70, fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // ★ v9.87 : Phrase IA non-binaire + calibration hippodrome
                      const SizedBox(height: 6),
                      IaSpeechWidget(
                        score:     top3.first.scoreIA,
                        nomCheval: top3.first.nom,
                        hippodrome: lieu,
                      ),
                    ],
                    // Arrivée réelle PMU
                    Builder(builder: (_) {
                      final isTerminee = course.heureDateTime
                          .isBefore(DateTime.now().subtract(const Duration(minutes: 90)));
                      final courseKey = reunion != null
                          ? buildCourseKey(
                              reunionCode: reunion.code,
                              numCourse: course.numCourse,
                              dateStr: course.dateStr,
                            )
                          : '';
                      if (courseKey.isEmpty) return const SizedBox();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ArriveReelleWidget(
                          courseKey: courseKey,
                          isTerminee: isTerminee,
                          heureDepart: course.heureDateTime, // ★ v9.6
                          selectionIA: course.partantsParRangIA
                              .take(5)
                              .map((p) => p.numero)
                              .toList(),
                        ),
                      );
                    }),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _ouvrirCourse(course, reunion),
                        icon: const Icon(Icons.analytics, size: 14),
                        label: const Text('Voir l\'analyse complète', style: TextStyle(fontSize: 14)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: courseTerminee ? Colors.white38 : const Color(0xFF7C4DFF),
                          side: BorderSide(color: courseTerminee ? Colors.white12 : const Color(0xFF7C4DFF)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Meilleur Pari ─────────────────────────────────────────────────
  Widget _buildMeilleurPari() {
    final pari = _meilleurPariCached;
    if (pari.course == null || pari.cheval == null) return const SizedBox();
    final course = pari.course!;
    final cheval = pari.cheval!;
    final reunion = pari.reunion;
    final lieu = reunion?.lieu ?? '';

    // Calcul confiance v5.0 — utilise exclusivement confianceIA (formule enrichie 10 critères)
    // La nouvelle formule combine : qualité absolue favori (40%) + domination (40%) + cohésion top3 (20%)
    // → cohérence garantie avec la page détail (même getter confianceIA)
    final confianceCourse = course.confianceIA;
    final confiance = confianceCourse > 0 ? confianceCourse.round() : cheval.scoreIA.round();
    final confianceColor = confiance >= 80
        ? const Color(0xFF00E676)
        : confiance >= 65
            ? const Color(0xFFFFEA00)
            : confiance >= 50
                ? const Color(0xFFFF6D00)
                : const Color(0xFFFF1744);
    final confianceLabel = confiance >= 80 ? 'FORTE' : confiance >= 65 ? 'BONNE' : confiance >= 50 ? 'MOY.' : 'FAIBLE';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('⭐ Meilleur Pari du Jour'),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFFFFD700).withValues(alpha: 0.12),
                const Color(0xFF0D1B2A),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Badge + course
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.6)),
                      ),
                      child: const Row(
                        children: [
                          Text('⭐', style: TextStyle(fontSize: 14)),
                          SizedBox(width: 4),
                          Text('BEST BET', style: TextStyle(color: Color(0xFFFFD700), fontSize: 14, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // ★ v9.5 : Bouton favori Meilleur Pari
                    if (reunion != null)
                      FavoriButton(
                        numR:      int.tryParse(reunion.code.replaceAll('R', '')) ?? 1,
                        numC:      course.numCourse,
                        nomCourse: course.nom,
                        hippodrome: lieu,
                        scoreIA:   cheval.scoreIA,
                        heure:     course.heure,
                        distance:  course.distance,
                        prix:      course.prix,
                        size: 22,
                      ),
                    Text(course.heure,
                        style: const TextStyle(color: Color(0xFF4CAF7D), fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),

                // Cheval star
                Row(
                  children: [
                    Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFFA000)]),
                        boxShadow: [BoxShadow(color: const Color(0xFFFFD700).withValues(alpha: 0.4), blurRadius: 12)],
                      ),
                      child: Center(
                        child: Text(cheval.numero,
                            style: const TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(cheval.nom,
                              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                          if (cheval.driver.isNotEmpty)
                            Text(cheval.driver,
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 14)),
                          const SizedBox(height: 4),
                          Text('${course.nom} • $lieu',
                              style: const TextStyle(color: Colors.white38, fontSize: 13),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Métriques
                Row(
                  children: [
                    _metrique('Score IA', '${cheval.scoreIA.round()}/100', confianceColor),
                    const SizedBox(width: 12),
                    _metrique('Confiance', confianceLabel, confianceColor),
                    const SizedBox(width: 12),
                    if (cheval.cote.isNotEmpty && cheval.cote != '?')
                      _metrique('Cote', '×${cheval.cote}', Colors.white70),
                  ],
                ),

                if (cheval.explicationIA.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      cheval.explicationIA,
                      style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                    ),
                  ),
                ],

                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _ouvrirCourse(course, reunion),
                    icon: const Icon(Icons.bar_chart, size: 16),
                    label: const Text('Voir la course complète'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD700),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _metrique(String label, String value, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Column(
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 14)),
      ],
    ),
  );

  // ── Prochaines Courses ────────────────────────────────────────────
  Widget _buildProchainesCourses() {
    final courses = _prochainesCourses.take(6).toList();
    if (courses.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('⏰ Prochaines Courses', action: 'Programme complet', onAction: _allerProgramme),
        ...courses.map((c) {
          final reunion = _reunions.firstWhere(
            (r) => r.courses.any((rc) => rc.numCourse == c.numCourse),
            orElse: () => ZtReunion(code: '?', lieu: '?', discipline: '', dateStr: '', courses: []),
          );
          final top1 = c.partantsParRangIA.isNotEmpty ? c.partantsParRangIA.first : null;
          return _ProchainesCourseRow(
            course: c,
            lieu: reunion.lieu,
            top1: top1,
            onTap: () => _ouvrirCourse(c, reunion),
          );
        }),
      ],
    );
  }

  // ── Réunions rapides ──────────────────────────────────────────────
  Widget _buildReunions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('🏟️ Réunions du Jour', action: 'Voir tout', onAction: _allerProgramme),
        SizedBox(
          height: 130,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _reunions.length,
            itemBuilder: (ctx, i) => _ReunionCard(
              reunion: _reunions[i],
              onTap: () => _allerProgramme(),
            ),
          ),
        ),
      ],
    );
  }

  // ── Loader / Error / Vide ─────────────────────────────────────────
  Widget _buildLoader() => const Padding(
    padding: EdgeInsets.all(60),
    child: Column(
      children: [
        CircularProgressIndicator(color: Color(0xFF4CAF7D)),
        SizedBox(height: 16),
        Text('Chargement PMU...', style: TextStyle(color: Colors.white54)),
      ],
    ),
  );

  /// Bandeau discret affiché pendant la mise à jour réseau
  /// quand le cache local est déjà visible (pas de blocage UI)
  Widget _buildRefreshBanner() => Container(
    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFF1A3A5C),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFF4CAF7D).withValues(alpha: 0.3)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 14, height: 14,
          child: CircularProgressIndicator(
            color: Color(0xFF4CAF7D),
            strokeWidth: 1.8,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Mise à jour PMU en cours…',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 12,
          ),
        ),
      ],
    ),
  );

  Widget _buildError() => Padding(
    padding: const EdgeInsets.all(24),
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFEF5350).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEF5350).withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          const Icon(Icons.wifi_off, color: Color(0xFFEF5350), size: 44),
          const SizedBox(height: 12),
          const Text('Impossible de charger le programme PMU',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(context.read<DataRefreshService>().lastError ?? '', style: const TextStyle(color: Colors.white54, fontSize: 14), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _charger(refresh: true),
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D52)),
          ),
        ],
      ),
    ),
  );

  Widget _buildVide() => const Padding(
    padding: EdgeInsets.all(60),
    child: Column(
      children: [
        Text('🏇', style: TextStyle(fontSize: 48)),
        SizedBox(height: 12),
        Text('Aucune course disponible', style: TextStyle(color: Colors.white54, fontSize: 15)),
      ],
    ),
  );

  // ── Utils ─────────────────────────────────────────────────────────
  Widget _sectionTitle(String title, {String? action, VoidCallback? onAction}) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        if (action != null)
          GestureDetector(
            onTap: onAction,
            child: Text(action, style: const TextStyle(color: Color(0xFF4CAF7D), fontSize: 14)),
          ),
      ],
    ),
  );

  Widget _iaBadge(double score) {
    final color = score >= 80
        ? const Color(0xFF00E676)
        : score >= 65
            ? const Color(0xFFFFEA00)
            : score >= 50
                ? const Color(0xFFFF6D00)
                : score > 0
                    ? const Color(0xFFFF1744)
                    : Colors.white24;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        score > 0 ? '${score.round()}/100' : '—',
        style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold),
      ),
    );
  }

  /// Badge confiance globale pour la page Accueil
  Widget _confianceBadgeHome(double confiance) {
    if (confiance <= 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: const Text('IA en calcul…', style: TextStyle(color: Colors.white30, fontSize: 11)),
      );
    }
    final Color c;
    final String lbl;
    if (confiance >= 80) { c = const Color(0xFF00E676); lbl = '🔥 FORTE'; }
    else if (confiance >= 65) { c = const Color(0xFFFFEA00); lbl = '✅ BONNE'; }
    else if (confiance >= 50) { c = const Color(0xFFFF6D00); lbl = '⚠️ MOY.'; }
    else { c = const Color(0xFFFF1744); lbl = '❌ FAIBLE'; }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.7), width: 1.5),
      ),
      child: Text(
        '${confiance.toStringAsFixed(0)}% $lbl',
        style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _ouvrirCourse(ZtCourse course, ZtReunion? reunion) {
    if (reunion == null) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => CourseDetailScreen(course: course, reunion: reunion),
    ));
  }

  void _allerProgramme() {
    // Naviguer vers l'onglet Programme (index 1 dans la nav)
    // On push simplement ProgrammeScreen
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ProgrammeScreen()));
  }

  // ★ v10.24 — Carte "Journée Express" : top 3 courses selon critères Conseils IA
  // (déplacée ici depuis _ReunionCard — nécessite _reunions et context de _HomeScreenState)
  Widget _buildJourneeExpress() {
    final now = DateTime.now();
    final isMatin = now.hour < 13;
    final alertSvc = AlertService.instance;
    final conseilCourses = alertSvc.coursesConseilIA;

    final List<({ZtCourse course, ZtReunion reunion})> top3;
    if (conseilCourses.isNotEmpty) {
      top3 = conseilCourses
          .where((e) => e.course.heureDateTime.isAfter(now.subtract(const Duration(minutes: 30))))
          .toList()
        ..sort((a, b) {
          final sA = a.course.partantsParRangIA.isNotEmpty ? a.course.partantsParRangIA.first.scoreIA : 0.0;
          final sB = b.course.partantsParRangIA.isNotEmpty ? b.course.partantsParRangIA.first.scoreIA : 0.0;
          return sB.compareTo(sA);
        });
    } else {
      final all = <({ZtCourse course, ZtReunion reunion})>[];
      for (final r in _reunions) {
        for (final c in r.courses) {
          if (c.partants.isNotEmpty &&
              c.heureDateTime.isAfter(now.subtract(const Duration(minutes: 30)))) {
            all.add((course: c, reunion: r));
          }
        }
      }
      all.sort((a, b) {
        final sA = a.course.partantsParRangIA.isNotEmpty ? a.course.partantsParRangIA.first.scoreIA : 0.0;
        final sB = b.course.partantsParRangIA.isNotEmpty ? b.course.partantsParRangIA.first.scoreIA : 0.0;
        return sB.compareTo(sA);
      });
      top3 = all;
    }

    if (top3.isEmpty) return const SizedBox.shrink();

    final items = top3.take(3).toList();
    final source = conseilCourses.isNotEmpty ? '🎯 Selon tes critères' : '🏆 Meilleures scores IA';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F2027), Color(0xFF1A1A3A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(isMatin ? '☀️' : '🌤️', style: const TextStyle(fontSize: 16)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Journée Express',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(source,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11)),
                ]),
              ),
              GestureDetector(
                onTap: () => context.read<NavigationNotifier>().goTo(3),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C4DFF).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.5)),
                  ),
                  child: const Text('Tout voir →',
                      style: TextStyle(color: Color(0xFF7C4DFF), fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ),
          const Divider(height: 1, color: Colors.white12),
          ...items.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            final top = item.course.partantsParRangIA;
            final p1 = top.isNotEmpty ? top.first : null;
            final score = p1?.scoreIA ?? 0.0;
            final scoreColor = score >= 80
                ? const Color(0xFF4CAF7D)
                : score >= 65 ? const Color(0xFFFFEA00) : const Color(0xFFFF9800);
            final diffMin = item.course.heureDateTime.difference(now).inMinutes;
            final isTerminee = item.course.heureDateTime.isBefore(now);
            final String heureLabel;
            if (isTerminee) {
              heureLabel = 'Terminée';
            } else if (diffMin < 60) {
              heureLabel = 'Dans ${diffMin}min';
            } else {
              heureLabel = item.course.heure;
            }

            return GestureDetector(
              onTap: () {
                // ★ v9.93 : naviguer directement vers la course (sans async gap)
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CourseDetailScreen(
                      course:  item.course,
                      reunion: item.reunion,
                    ),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
                decoration: BoxDecoration(
                  border: i < items.length - 1
                      ? const Border(bottom: BorderSide(color: Colors.white12))
                      : null,
                ),
                child: Row(children: [
                  Container(
                    width: 22, height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scoreColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Text('${i + 1}',
                        style: TextStyle(color: scoreColor, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(item.course.nom,
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        if (item.course.isQuinte)
                          Container(
                            margin: const EdgeInsets.only(left: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text('Q+',
                                style: TextStyle(color: Color(0xFFFFD700), fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                      ]),
                      Row(children: [
                        Text('${item.reunion.lieu} • $heureLabel',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11)),
                        if (p1 != null) ...[
                          const SizedBox(width: 5),
                          Text('N°${p1.numero} ${p1.nom.split(' ').first}',
                              style: const TextStyle(color: Colors.white38, fontSize: 11),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(width: 3),
                          _buildFormeBadgeInline(p1.tendanceForme),
                        ],
                      ]),
                    ]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: scoreColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${score.round()}%',
                        style: TextStyle(color: scoreColor, fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ]),
              ),
            );
          }),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            child: Row(children: [
              const Icon(Icons.info_outline, color: Colors.white24, size: 12),
              const SizedBox(width: 5),
              Text(
                '${items.length} course${items.length > 1 ? 's' : ''} — appuie pour voir les conseils',
                style: const TextStyle(color: Colors.white24, fontSize: 11),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  static Widget _buildFormeBadgeInline(TendanceForme forme) {
    switch (forme) {
      case TendanceForme.hausse:      return const Text('📈', style: TextStyle(fontSize: 10));
      case TendanceForme.baisse:      return const Text('📉', style: TextStyle(fontSize: 10));
      case TendanceForme.stable:      return const Text('➡️', style: TextStyle(fontSize: 9));
      case TendanceForme.insuffisant: return const SizedBox.shrink();
    }
  }
}

// ══════════════════════════════════════════════════════════════════════
// WIDGET : Ligne prochaine course
// ══════════════════════════════════════════════════════════════════════
class _ProchainesCourseRow extends StatelessWidget {
  final ZtCourse course;
  final String lieu;
  final ZtPartant? top1;
  final VoidCallback onTap;

  const _ProchainesCourseRow({
    required this.course,
    required this.lieu,
    required this.top1,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2F3D).withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: course.isQuinte
                ? const Color(0xFFFFD700).withValues(alpha: 0.4)
                : const Color(0xFF4CAF7D).withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          children: [
            // Heure
            Container(
              width: 52, height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFF0D1B2A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(course.heure,
                      style: const TextStyle(color: Color(0xFF4CAF7D), fontSize: 14, fontWeight: FontWeight.bold)),
                  Text('C${course.numCourse}',
                      style: const TextStyle(color: Colors.white38, fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Infos course
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (course.isQuinte)
                        Container(
                          margin: const EdgeInsets.only(right: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text('Q+', style: TextStyle(color: Color(0xFFFFD700), fontSize: 14, fontWeight: FontWeight.bold)),
                        ),
                      Expanded(
                        child: Text(course.nom,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  Text(
                    '$lieu • ${course.distance}m • ${course.type} • ${course.partants.length}🐴',
                    style: const TextStyle(color: Colors.white38, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Favori IA
            if (top1 != null) ...[
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C4DFF).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('N°${top1!.numero}', style: const TextStyle(color: Color(0xFF7C4DFF), fontSize: 14, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 2),
                  Text('${top1!.scoreIA.round()}pts', style: const TextStyle(color: Colors.white30, fontSize: 14)),
                ],
              ),
            ],
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Colors.white24, size: 16),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// WIDGET : Carte réunion
// ══════════════════════════════════════════════════════════════════════
class _ReunionCard extends StatelessWidget {
  final ZtReunion reunion;
  final VoidCallback onTap;
  const _ReunionCard({required this.reunion, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = Color(reunion.disciplineColor);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2F3D),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(reunion.disciplineIcon, style: const TextStyle(fontSize: 18)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(reunion.code, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reunion.lieu,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('${reunion.courses.length} course${reunion.courses.length > 1 ? 's' : ''}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
                Text('${reunion.totalPartants} chevaux',
                    style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 13)),
              ],
            ),
          ],
        ),
      ),
    );
  }

}
