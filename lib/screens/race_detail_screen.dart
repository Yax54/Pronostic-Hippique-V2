import 'package:flutter/material.dart';
import '../widgets/favori_button.dart'; // ★ v9.3
import 'package:provider/provider.dart';
import '../models/pmu_models.dart';
import '../providers/pmu_provider.dart';
import '../services/alert_service.dart';
import '../utils/format_euros.dart';

class RaceDetailScreen extends StatefulWidget {
  // On passe uniquement les clés — la course est relue depuis le provider à chaque rebuild
  final int numReunion;
  final int numOrdre;
  final String hippodrome;
  final String dateStr;
  // Optionnel : AlertService pour afficher les paris suivis sur cette course
  final AlertService? alertService;

  const RaceDetailScreen({
    super.key,
    required this.numReunion,
    required this.numOrdre,
    required this.hippodrome,
    required this.dateStr,
    this.alertService,
  });

  @override
  State<RaceDetailScreen> createState() => _RaceDetailScreenState();
}

class _RaceDetailScreenState extends State<RaceDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int? _selectedNum;
  String _betType = 'Simple Gagnant';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerLoad();
    });
  }

  void _triggerLoad() {
    final provider = Provider.of<PmuProvider>(context, listen: false);
    final course = _findCourse(provider);
    if (course == null) return;

    // Force le rechargement si la liste est vide (chargement initial raté)
    final forceReload = course.participants.isEmpty;
    provider.loadParticipants(course, forceReload: forceReload);

    // Pré-remplir si l'utilisateur a déjà un pronostic pour cette course
    final pred = provider.getPredictionForCourse(widget.numReunion, widget.numOrdre);
    if (pred != null) {
      setState(() {
        _selectedNum = pred.numeroCheval;
        _betType = pred.typePari;
        // Si pronostic existant → montrer l'onglet pronostics
        _tabController.animateTo(1);
      });
    } else {
      // Par défaut : onglet Partants & Cotes
      _tabController.animateTo(0);
    }
  }

  /// Retrouve la course depuis le provider avec les clés numReunion + numOrdre
  PmuCourse? _findCourse(PmuProvider provider) {
    for (final r in provider.reunions) {
      if (r.numOfficiel != widget.numReunion) continue;
      for (final c in r.courses) {
        if (c.numOrdre == widget.numOrdre) return c;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // context.watch déclenche un rebuild à chaque notifyListeners()
    final provider = context.watch<PmuProvider>();
    final course = _findCourse(provider);

    if (course == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D2818),
        appBar: AppBar(backgroundColor: const Color(0xFF0D2818), foregroundColor: Colors.white, title: const Text('Course introuvable')),
        body: const Center(child: Text('Course non disponible', style: TextStyle(color: Colors.white54))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D2818),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D2818),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(course.libelle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
        actions: [
          // ★ v9.3 : Bouton favori
          FavoriButton(
            numR:       widget.numReunion,
            numC:       widget.numOrdre,
            nomCourse:  course.libelle,
            hippodrome: widget.hippodrome,
            scoreIA:    0.0,
            heure:      course.heureStr,
            distance:   '${course.distance} m',
            prix:       course.libelleCourt,
            size: 24,
          ),
          Container(
            margin: const EdgeInsets.only(right: 10),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _statusColor(course.status).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _statusColor(course.status)),
            ),
            child: Text(course.statusLabel, style: TextStyle(color: _statusColor(course.status), fontSize: 14, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          _CourseInfoHeader(course: course, hippodrome: widget.hippodrome),
          // ★ Bandeau récapitulatif des paris sur cette course (si disponibles)
          if (widget.alertService != null)
            _BandeauParis(
              numReunion: widget.numReunion,
              numCourse: widget.numOrdre,
              alertService: widget.alertService!,
            ),
          Container(
            color: const Color(0xFF0D2818),
            child: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF4CAF7D),
              labelColor: const Color(0xFF4CAF7D),
              unselectedLabelColor: Colors.white54,
              tabs: const [Tab(text: 'Partants & Cotes'), Tab(text: 'Mes Pronostics')],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildParticipantsTab(course, provider),
                _buildPredictionTab(course, provider),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Onglet Partants & Cotes ──────────────────────────────────────────────

  Widget _buildParticipantsTab(PmuCourse course, PmuProvider provider) {
    // Encore en chargement
    if (!course.participantsLoaded) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF4CAF7D)),
            SizedBox(height: 14),
            Text('Chargement des partants…', style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    // Aucun partant même après chargement
    if (course.participants.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sentiment_dissatisfied, color: Colors.white24, size: 48),
            const SizedBox(height: 12),
            const Text('Partants pas encore disponibles', style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 6),
            const Text(
              'Les cotes seront publiées peu avant le départ',
              style: TextStyle(color: Colors.white30, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                // forceReload: true pour contourner le cache
                provider.loadParticipants(course, forceReload: true);
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Actualiser'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D52), foregroundColor: Colors.white),
            ),
          ],
        ),
      );
    }

    // Trier par score pronostic décroissant
    final sorted = List<PmuParticipant>.from(course.participants)
      ..sort((a, b) => b.scorePronostic.compareTo(a.scorePronostic));

    return Column(
      children: [
        // Bandeau informatif — données réelles PMU
        Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF1C2733).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Color(0xFF4CAF7D), size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${course.participants.length} partants PMU réels • Classés par score IA',
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ),
              GestureDetector(
                onTap: () => provider.loadParticipants(course, forceReload: true),
                child: const Icon(Icons.refresh, color: Colors.white38, size: 16),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: sorted.length,
            itemBuilder: (ctx, i) {
              final p = sorted[i];
              final isSelected = p.numero == _selectedNum;
              final rank = i + 1;
              // ── v9.53 fix : utiliser les couleurs de rang (or/argent/bronze)
              // au lieu du vert uniforme — _rankBorderColor/_rankBgColor définis
              // plus bas dans ce fichier (rank 1=or, 2=argent, 3=bronze, autres=gris)
              final rankBorder = _rankBorderColor(rank);
              final rankBg    = _rankBgColor(rank);
              return GestureDetector(
                onTap: course.status != CourseStatus.terminee
                    ? () => setState(() => _selectedNum = p.numero)
                    : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(bottom: 9),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF4CAF7D).withValues(alpha: 0.15)
                        : rankBg,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF4CAF7D)
                          : rankBorder.withValues(alpha: rank == 1 ? 0.9 : 0.55),
                      width: isSelected ? 1.8 : (rank == 1 ? 1.8 : 1.2),
                    ),
                  ),
                  child: _ParticipantRow(participant: p, isSelected: isSelected, rank: rank),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─── Onglet Mes Pronostics ────────────────────────────────────────────────

  Widget _buildPredictionTab(PmuCourse course, PmuProvider provider) {
    PmuParticipant? selected;
    if (_selectedNum != null && course.participantsLoaded) {
      try {
        selected = course.participants.firstWhere((p) => p.numero == _selectedNum);
      } catch (_) {}
    }

    // Top 3 favoris IA
    List<PmuParticipant> top3 = [];
    if (course.participantsLoaded && course.participants.isNotEmpty) {
      top3 = List<PmuParticipant>.from(course.participants)
        ..sort((a, b) => b.scorePronostic.compareTo(a.scorePronostic));
      top3 = top3.take(3).toList();
    }

    // Bouton "Valider" fixé en bas — hors du scroll
    // ★ Fix doublon : ne pas afficher si un pronostic existe déjà pour cette course
    Widget? validateBtn;
    final dejaEnregistre = provider.hasPredictionForCourse(course.numReunion, course.numOrdre);
    if (course.status != CourseStatus.terminee && selected != null) {
      final sel = selected;
      validateBtn = SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          color: const Color(0xFF0D2818),
          child: dejaEnregistre
              // ── Pari déjà enregistré : afficher un bandeau informatif ──
              ? Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A3A1A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF4CAF7D).withValues(alpha: 0.5)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: Color(0xFF4CAF7D), size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Pronostic déjà enregistré',
                        style: TextStyle(
                          color: Color(0xFF4CAF7D),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              // ── Pas encore enregistré : bouton Valider normal ──
              : SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      provider.addPrediction(UserPrediction(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        dateStr: provider.dateStr,
                        numReunion: course.numReunion,
                        numCourse: course.numOrdre,
                        nomCourse: course.libelle,
                        hippodrome: widget.hippodrome,
                        numeroCheval: sel.numero,
                        nomCheval: sel.nom,
                        cote: sel.coteAffichee,
                        typePari: _betType,
                        createdAt: DateTime.now(),
                      ));
                      // ★ v9.4 : stopper les alertes favori dès qu'un pari est placé
                      widget.alertService?.marquerFavoriCommeParI(
                        course.numReunion,
                        course.numOrdre,
                      );
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Row(children: [
                          const Icon(Icons.check_circle_rounded, color: Color(0xFFFFD700), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('Pronostic enregistré !',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                Text('N°${sel.numero} ${sel.nom}',
                                    style: const TextStyle(color: Color(0xFFFFD700), fontSize: 13)),
                              ],
                            ),
                          ),
                        ]),
                        backgroundColor: const Color(0xFF0D1B2A),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: Color(0xFFFFD700), width: 1),
                        ),
                        margin: const EdgeInsets.all(14),
                        duration: const Duration(seconds: 3),
                      ));
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.how_to_vote),
                    label: Text('Valider — N°${sel.numero} ${sel.nom}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A2E4A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFFFFD700), width: 1.5),
                      ),
                    ),
                  ),
                ),
        ),
      );
    }

    final scrollContent = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Spinner si partants pas encore chargés ──
          if (!course.participantsLoaded) ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Column(children: [
                  CircularProgressIndicator(color: Color(0xFF4CAF7D)),
                  SizedBox(height: 12),
                  Text('Chargement du pronostic IA…', style: TextStyle(color: Colors.white54)),
                ]),
              ),
            ),
          ] else ...[

            // ── Top 3 IA ──
            if (top3.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF1A2535), Color(0xFF0D1B2A)]),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2E7D52).withValues(alpha: 0.6)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.auto_awesome, color: Color(0xFFFFD700), size: 18),
                      SizedBox(width: 8),
                      Text('Pronostics IA', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      SizedBox(width: 6),
                      Text('Cotes + stats PMU', style: TextStyle(color: Colors.white38, fontSize: 14)),
                    ]),
                    const SizedBox(height: 4),
                    const Text('Appuyez sur un cheval pour le sélectionner', style: TextStyle(color: Colors.white30, fontSize: 13)),
                    const SizedBox(height: 12),
                    ...top3.asMap().entries.map((e) => _IaRow(
                      rank: e.key + 1,
                      participant: e.value,
                      isSelected: e.value.numero == _selectedNum,
                      onSelect: course.status != CourseStatus.terminee
                          ? () => setState(() => _selectedNum = e.value.numero)
                          : null,
                    )),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ── Type de pari + Cheval sélectionné
            // Masqués si pari déjà enregistré (inutile et mort depuis la vue historique)
            if (course.status != CourseStatus.terminee && !dejaEnregistre) ...[
              const Text('Type de pari', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['Simple Gagnant', 'Simple Placé', 'Gagnant+Placé', 'Couplé Gagnant', 'Tiercé', 'Quarté+', 'Quinté+'].map((t) => _BetTypeBtn(
                  label: t,
                  selected: _betType == t,
                  onTap: () => setState(() => _betType = t),
                )).toList(),
              ),
              const SizedBox(height: 20),

              // ── Cheval sélectionné ──
              const Text('Cheval sélectionné', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),

              if (selected == null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    // Fond ardoise neutre — plus de vert saturé
                    color: const Color(0xFF1C2733).withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.touch_app, color: Colors.white.withValues(alpha: 0.35)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Appuyez sur un cheval dans les pronostics IA ci-dessus ou dans l\'onglet "Partants & Cotes"',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.40)),
                        ),
                      ),
                    ],
                  ),
                )
              else
                _SelectedHorseCard(participant: selected, betType: _betType),

              const SizedBox(height: 8),
            ] else if (course.status == CourseStatus.terminee)
              const _FinishedMessage(),
          ],

          const SizedBox(height: 8),
        ],
      ),
    );

    return Column(
      children: [
        Expanded(child: scrollContent),
        if (validateBtn != null) validateBtn,
      ],
    );
  }

  Color _statusColor(CourseStatus status) {
    switch (status) {
      case CourseStatus.aVenir:   return const Color(0xFF4CAF7D);
      case CourseStatus.enCours:  return const Color(0xFFFFB74D);
      case CourseStatus.terminee: return const Color(0xFF9E9E9E);
    }
  }
}

// ─── Bandeau récapitulatif des paris sur cette course ────────────────────────

class _BandeauParis extends StatelessWidget {
  final int numReunion;
  final int numCourse;
  final AlertService alertService;

  const _BandeauParis({
    required this.numReunion,
    required this.numCourse,
    required this.alertService,
  });

  @override
  Widget build(BuildContext context) {
    // Chercher tous les paris TrackedCourse pour cette course
    final paris = alertService.trackedCourses.values
        .where((tc) => tc.numReunion == numReunion && tc.numCourse == numCourse)
        .toList()
      ..sort((a, b) => a.addedAt.compareTo(b.addedAt));

    if (paris.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1628),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700).withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(children: [
              const Icon(Icons.receipt_long, color: Color(0xFFFFD700), size: 16),
              const SizedBox(width: 8),
              Text(
                '${paris.length} pari${paris.length > 1 ? "s" : ""} placé${paris.length > 1 ? "s" : ""} sur cette course',
                style: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ]),
          ),
          // Liste des paris
          ...paris.asMap().entries.map((entry) {
            final tc = entry.value;

            // Couleur selon résultat
            final Color statColor;
            final String statEmoji;
            if (tc.isGagne == true) {
              statColor = const Color(0xFF4CAF7D);
              statEmoji = '✅';
            } else if (tc.isGagne == false) {
              statColor = const Color(0xFFEF5350);
              statEmoji = '❌';
            } else {
              statColor = const Color(0xFFFFB74D);
              statEmoji = '⏳';
            }

            final chevalStr = tc.numeroCheval != null && tc.numeroCheval! > 0
                ? 'N°${tc.numeroCheval}'
                : '';
            final nomChevalStr = (tc.nomCheval != null && tc.nomCheval!.isNotEmpty)
                ? ' — ${tc.nomCheval}'
                : '';
            final numerosStr = tc.numerosJoues.isNotEmpty
                ? tc.numerosJoues.map((n) => 'N°$n').join(' · ')
                : chevalStr;

            // Calcul gain potentiel
            // gainPotentiel = retour total du billet (ce que le billet rapporte)
            // gainNet       = bénéfice réel (profil/stats uniquement)
            final mise = tc.miseEngagee ?? 0;
            final gainPotentiel = tc.cote > 0 ? (mise * tc.cote) : 0.0;
            final gainNet = mise * (tc.cote > 0 ? tc.cote : 1) - mise;

            return Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              decoration: BoxDecoration(
                color: statColor.withValues(alpha: 0.04),
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                ),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Ligne 1 : type pari + mise + statut emoji
                Row(children: [
                  Text(statEmoji, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: statColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(tc.typePari,
                        style: TextStyle(color: statColor, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Mise : ${mise.toStringAsFixed(0)} €',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const Spacer(),
                  // Cote
                  if (tc.cote > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '×${tc.cote.toStringAsFixed(1)}',
                        style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                ]),

                // Ligne 2 : numéros joués
                if (numerosStr.isNotEmpty) ...[  
                  const SizedBox(height: 6),
                  Text(
                    '$numerosStr$nomChevalStr',
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                // Ligne 3 : GAIN bien mis en valeur
                const SizedBox(height: 10),
                if (tc.isGagne == true)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF7D).withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF4CAF7D).withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('✅ GAGNÉ', style: TextStyle(color: Color(0xFF4CAF7D), fontSize: 13, fontWeight: FontWeight.bold)),
                        Text(
                          '+${fmtEuros(gainNet)} €',
                          style: const TextStyle(color: Color(0xFF4CAF7D), fontSize: 20, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  )
                else if (tc.isGagne == false)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF5350).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFEF5350).withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('❌ PERDU', style: TextStyle(color: Color(0xFFEF5350), fontSize: 13, fontWeight: FontWeight.bold)),
                        Text(
                          '-${fmtEuros(mise)} €',
                          style: const TextStyle(color: Color(0xFFEF5350), fontSize: 20, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  )
                else if (tc.cote > 0)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('⏳ Gain potentiel', style: TextStyle(color: Color(0xFFFFD700), fontSize: 13, fontWeight: FontWeight.w600)),
                        Text(
                          '+${fmtEuros(gainPotentiel)} €',
                          style: const TextStyle(color: Color(0xFFFFD700), fontSize: 20, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
              ]),
            );
          }),
        ],
      ),
    );
  }
}

// ─── Course info header ───────────────────────────────────────────────────────

class _CourseInfoHeader extends StatelessWidget {
  final PmuCourse course;
  final String hippodrome;
  const _CourseInfoHeader({required this.course, required this.hippodrome});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E3A5F).withValues(alpha: 0.8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _InfoItem(
            icon: Icons.location_on,
            iconColor: const Color(0xFF64B5F6),
            label: 'Hippodrome',
            value: hippodrome.isNotEmpty ? hippodrome : '—',
          ),
          _InfoItemDivider(),
          _InfoItem(
            icon: Icons.straighten,
            iconColor: const Color(0xFFFFD700),
            label: 'Distance',
            value: '${course.distance}m',
          ),
          _InfoItemDivider(),
          _InfoItem(
            icon: Icons.emoji_events,
            iconColor: const Color(0xFFFFB74D),
            label: 'Dotation',
            value: course.montantPrix >= 1000
                ? '${(course.montantPrix / 1000).toStringAsFixed(0)}K€'
                : '${course.montantPrix}€',
          ),
          _InfoItemDivider(),
          _InfoItem(
            icon: Icons.groups,
            iconColor: const Color(0xFF4CAF7D),
            label: 'Partants',
            value: '${course.nombrePartants}',
          ),
        ],
      ),
    );
  }
}

class _InfoItemDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1, height: 32,
      color: Colors.white.withValues(alpha: 0.08),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  const _InfoItem({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Icon(icon, color: iconColor, size: 17),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
      Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11)),
    ]);
  }
}

// ─── Couleurs de rang ─────────────────────────────────────────────────────────

Color _rankBorderColor(int rank) {
  switch (rank) {
    case 1: return const Color(0xFFFFD700);   // or
    case 2: return const Color(0xFFB0BEC5);   // argent
    case 3: return const Color(0xFFCD7F32);   // bronze
    default: return const Color(0xFF1E3A5F);  // bleu nuit discret
  }
}

Color _rankBgColor(int rank) {
  switch (rank) {
    case 1: return const Color(0xFFFFD700).withValues(alpha: 0.08);
    case 2: return const Color(0xFFB0BEC5).withValues(alpha: 0.06);
    case 3: return const Color(0xFFCD7F32).withValues(alpha: 0.06);
    default: return const Color(0xFF0D1B2A);
  }
}

Color _scoreColor(double score) {
  if (score >= 70) return const Color(0xFFFFD700);
  if (score >= 50) return const Color(0xFFFF9800);
  if (score >= 35) return const Color(0xFFFF6D00);
  return const Color(0xFFEF5350);
}

// ─── Ligne partant ────────────────────────────────────────────────────────────

class _ParticipantRow extends StatelessWidget {
  final PmuParticipant participant;
  final bool isSelected;
  final int rank;
  const _ParticipantRow({required this.participant, required this.isSelected, required this.rank});

  @override
  Widget build(BuildContext context) {
    final p = participant;
    final cote = p.coteAffichee;
    final coteStr = cote > 0 ? cote.toStringAsFixed(1) : '-';

    // ── Détection cheval hors course ──────────────────────────────────────
    final statut = (p.statut).toUpperCase();
    final estHorsCourse = statut == 'DISQUALIFIE' || statut == 'DISQUALIFIED' ||
        statut == 'NON_PARTANT' || statut == 'RETRAIT' ||
        statut == 'ARRETE'      || statut == 'TOMBE';
    final badgeDisqLabel = statut == 'DISQUALIFIE' || statut == 'DISQUALIFIED'
        ? 'DISQ'
        : statut == 'ARRETE' ? 'ARRÊTÉ'
        : statut == 'TOMBE'  ? 'TOMBÉ'
        : 'N.P.';

    final borderColor = estHorsCourse ? Colors.grey.shade700
        : isSelected ? const Color(0xFF4CAF7D)
        : _rankBorderColor(rank);
    final bgColor = estHorsCourse ? const Color(0xFF1A1A1A)
        : isSelected ? const Color(0xFF4CAF7D).withValues(alpha: 0.10)
        : _rankBgColor(rank);
    final scoreCol = _scoreColor(p.scorePronostic);

    Color coteColor;
    if (estHorsCourse) {
      coteColor = Colors.grey;
    } else if (cote > 0 && cote <= 5) {
      coteColor = const Color(0xFF4CAF7D);
    } else if (cote <= 10) {
      coteColor = const Color(0xFFFFB74D);
    } else {
      coteColor = const Color(0xFFEF9A9A);
    }

    return Opacity(
      opacity: estHorsCourse ? 0.5 : 1.0,
      child: Row(
        children: [
          // Numéro + médaille IA
          Column(
            children: [
              Container(
                width: rank == 1 ? 42 : 36,
                height: rank == 1 ? 42 : 36,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: borderColor, width: rank == 1 ? 2.0 : 1.2),
                ),
                child: Center(
                  child: Text(
                    '${p.numero}',
                    style: TextStyle(
                      color: estHorsCourse ? Colors.grey
                          : rank == 1 ? const Color(0xFFFFD700)
                          : isSelected ? const Color(0xFF4CAF7D)
                          : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: rank == 1 ? 17 : 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              if (estHorsCourse)
                Text(badgeDisqLabel,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold))
              else
                Text(rank == 1 ? '🥇' : rank == 2 ? '🥈' : rank == 3 ? '🥉' : '',
                    style: const TextStyle(fontSize: 13)),
            ],
          ),
          const SizedBox(width: 10),

          // Infos cheval
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(p.nom,
                      style: TextStyle(
                        color: rank == 1 ? Colors.white : Colors.white.withValues(alpha: 0.88),
                        fontWeight: rank == 1 ? FontWeight.w800 : FontWeight.bold,
                        fontSize: rank == 1 ? 14 : 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _PronosticBadge(label: p.pronosticLabel),
                ]),
                Text(
                  '${p.driver}${p.entraineur.isNotEmpty ? " · ${p.entraineur}" : ""}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  children: [
                    _MiniChip(label: '${p.age} ans', color: const Color(0xFF1E3A5F)),
                    if (p.robe.isNotEmpty) _MiniChip(label: p.robe, color: const Color(0xFF1E3A5F)),
                    if (p.formRecente.isNotEmpty)
                      Text('Forme: ${p.formRecente}',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Cote + score IA
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: coteColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: coteColor, width: 1.5),
                ),
                child: Text(coteStr,
                    style: TextStyle(color: coteColor, fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              const SizedBox(height: 4),
              _ScoreBar(score: p.scorePronostic, scoreColor: scoreCol),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScoreBar extends StatelessWidget {
  final double score;
  final Color? scoreColor;
  const _ScoreBar({required this.score, this.scoreColor});

  @override
  Widget build(BuildContext context) {
    final pct = (score / 100).clamp(0.0, 1.0);
    final color = scoreColor ?? _scoreColor(score);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${score.toStringAsFixed(0)} pts',
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 3),
        SizedBox(
          width: 56,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: Colors.white.withValues(alpha: 0.07),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 5,
            ),
          ),
        ),
      ],
    );
  }
}

class _PronosticBadge extends StatelessWidget {
  final String label;
  const _PronosticBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (label) {
      case 'FAVORI':      color = const Color(0xFF4CAF7D); break;
      case 'OUTSIDER':    color = const Color(0xFFFFB74D); break;
      case 'À SURVEILLER': color = const Color(0xFF64B5F6); break;
      default:            color = const Color(0xFF9E9E9E);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final Color color;
  const _MiniChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color),
      ),
      child: Text(label, style: const TextStyle(color: Colors.white60, fontSize: 14)),
    );
  }
}

// ─── Ligne IA (top 3) ─────────────────────────────────────────────────────────

class _IaRow extends StatelessWidget {
  final int rank;
  final PmuParticipant participant;
  final bool isSelected;
  final VoidCallback? onSelect;
  const _IaRow({required this.rank, required this.participant, required this.isSelected, this.onSelect});

  @override
  Widget build(BuildContext context) {
    final p = participant;
    final medals = ['🥇', '🥈', '🥉'];
    final borderColor = isSelected ? const Color(0xFF4CAF7D) : _rankBorderColor(rank);
    final scoreCol = _scoreColor(p.scorePronostic);
    final cote = p.coteAffichee;
    final coteStr = cote > 0 ? '×${cote.toStringAsFixed(1)}' : '—';

    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF4CAF7D).withValues(alpha: 0.10)
              : _rankBgColor(rank),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: borderColor, width: rank == 1 ? 1.8 : 1.2),
        ),
        child: Row(
          children: [
            // Médaille
            Text(medals[rank - 1], style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            // Numéro
            Container(
              width: rank == 1 ? 34 : 28,
              height: rank == 1 ? 34 : 28,
              decoration: BoxDecoration(
                color: _rankBorderColor(rank).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: _rankBorderColor(rank), width: 1.5),
              ),
              child: Center(
                child: Text(
                  '${p.numero}',
                  style: TextStyle(
                    color: _rankBorderColor(rank),
                    fontSize: rank == 1 ? 16 : 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Nom + cote
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.nom,
                    style: TextStyle(
                      color: rank == 1 ? Colors.white : Colors.white.withValues(alpha: 0.85),
                      fontSize: rank == 1 ? 14 : 13,
                      fontWeight: rank == 1 ? FontWeight.w800 : FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(children: [
                    Text(
                      coteStr,
                      style: TextStyle(
                        color: cote > 0 && cote <= 5
                            ? const Color(0xFF4CAF7D)
                            : cote <= 10 ? const Color(0xFFFFB74D) : Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _PronosticBadge(label: p.pronosticLabel),
                  ]),
                ],
              ),
            ),
            // Score IA
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: scoreCol.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: scoreCol.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    '${p.scorePronostic.toStringAsFixed(0)}/100',
                    style: TextStyle(color: scoreCol, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                if (isSelected)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Icon(Icons.check_circle, color: Color(0xFF4CAF7D), size: 14),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Carte cheval sélectionné ─────────────────────────────────────────────────

class _SelectedHorseCard extends StatelessWidget {
  final PmuParticipant participant;
  final String betType;
  const _SelectedHorseCard({required this.participant, required this.betType});

  @override
  Widget build(BuildContext context) {
    final p = participant;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        // Fond ardoise sobre — accent vert uniquement sur la bordure
        color: const Color(0xFF151F2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF4CAF7D).withValues(alpha: 0.7), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFF0D2818),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF4CAF7D), width: 2),
            ),
            child: Center(child: Text('${p.numero}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.nom, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                Text('${p.driver} · ${p.entraineur}', style: const TextStyle(color: Colors.white60, fontSize: 14)),
                const SizedBox(height: 4),
                Text('Forme: ${p.formRecente}', style: const TextStyle(color: Colors.white38, fontSize: 14)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Cote', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
              Text(
                p.coteAffichee > 0 ? p.coteAffichee.toStringAsFixed(1) : '-',
                style: const TextStyle(color: Color(0xFF4CAF7D), fontSize: 24, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.5)),
                ),
                child: Text(betType, style: const TextStyle(color: Color(0xFFFFD700), fontSize: 14, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BetTypeBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _BetTypeBtn({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2E7D52) : const Color(0xFF1C2733).withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFF4CAF7D) : Colors.white.withValues(alpha: 0.15),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white54,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _FinishedMessage extends StatelessWidget {
  const _FinishedMessage();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF9E9E9E).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF9E9E9E).withValues(alpha: 0.3)),
      ),
      child: const Column(
        children: [
          Icon(Icons.flag, color: Color(0xFF9E9E9E), size: 40),
          SizedBox(height: 10),
          Text('Course terminée', style: TextStyle(color: Colors.white54, fontSize: 16)),
          SizedBox(height: 6),
          Text('Consultez les résultats officiels sur PMU.fr',
              style: TextStyle(color: Colors.white30, fontSize: 14), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
