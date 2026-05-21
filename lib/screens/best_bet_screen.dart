// ═══════════════════════════════════════════════════════════════════
//  ONGLET BEST BET — Meilleur Pari du Jour (Zone-Turf + IA)
// ═══════════════════════════════════════════════════════════════════
import '../widgets/type_pari_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import '../widgets/favori_button.dart'; // ★ v9.3
import 'package:provider/provider.dart';
import '../main.dart' show NavigationNotifier;
import '../models/zt_models.dart';
import '../utils/format_euros.dart';
import '../services/zone_turf_service.dart';
import '../services/data_refresh_service.dart';
import '../services/alert_service.dart';
import '../services/ia_memory_service.dart' show IaMemoryService;
import '../services/ia_memory_models.dart' show PremiumPronosticDuJour, PremiumStreak, SelectionWidgetPremiumDuJour;
import '../services/gain_calculator.dart';  // ★ v9.93 : Kelly Criterion
import '../widgets/bet_bottom_sheet.dart';
import '../widgets/arrivee_reelle_widget.dart';
import '../utils/premium_utils.dart' show nbNumerosPourTypePari; // ★ v10.55
import '../utils/premium_streak_ui.dart';        // ★ v10.61 : phrase série premium commune
import '../services/quasi_gros_paris_service.dart'; // ★ v10.72 : Gros paris à surveiller

import 'course_detail_screen.dart';

// ── Modèle d'opportunité de pari ─────────────────────────────────
class _BetOpp {
  final ZtCourse course;
  final ZtReunion reunion;
  final ZtPartant favori;
  final double scoreComposite;   // confiance × gain potentiel
  final double scoreConfiance;
  final double scoreGain;
  final String typePari;
  final String conseil;
  final bool estTerminee;        // true si l'heure de départ est passée
  // ★ v10.37 : numéros conseillés dans l'ordre IA (pour validation étoile ⭐ v2)
  final List<String> numeros;

  const _BetOpp({
    required this.course,
    required this.reunion,
    required this.favori,
    required this.scoreComposite,
    required this.scoreConfiance,
    required this.scoreGain,
    required this.typePari,
    required this.conseil,
    required this.numeros,
    required this.estTerminee,
  });
}

class BestBetScreen extends StatefulWidget {
  const BestBetScreen({super.key});
  @override
  State<BestBetScreen> createState() => _BestBetScreenState();
}

class _BestBetScreenState extends State<BestBetScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<ZtReunion> _reunions = [];
  bool _loading = true;
  String? _error;
  double _mise      = 10.0;
  double _bankroll  = 200.0; // ★ v9.93 : bankroll pour Kelly Criterion

  // ★ v10.72 : Signaux "Gros paris à surveiller"
  List<GrosPariSurveiller> _signauxGrosParis = [];

  // ★ v10.69 : Sélections figées du jour pour les 3 widgets BestBet
  // CLÉ : l'UI lit ces sélections EN PRIORITÉ 1 avant tout recalcul.
  Map<String, SelectionWidgetPremiumDuJour> _selectionsFigees = {};
  bool _selectionsFigeesChargees = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _charger();
    _chargerSelectionsFigees();
    _chargerSignauxPersistants(); // ★ v10.73 : charge les signaux sauvegardés au démarrage
  }

  /// ★ v10.73 : Charge les signaux Gros Paris déjà persistés (pour survie après fermeture app).
  Future<void> _chargerSignauxPersistants() async {
    try {
      final svc = QuasiGrosParisService.instance;
      await svc.charger(); // s'assure que la mémoire est peuplée depuis SharedPreferences
      if (!mounted) return;
      final signaux = svc.signauxAujourdhui();
      if (kDebugMode) {
        debugPrint('[QUASI_GROS_PARIS_LOAD] ${signaux.length} signaux chargés depuis persistance');
      }
      setState(() { _signauxGrosParis = signaux; });
    } catch (e) {
      if (kDebugMode) debugPrint('[QUASI_GROS_PARIS_LOAD] Erreur chargement persistance: $e');
    }
  }

  /// Charge les sélections figées du jour depuis SharedPreferences.
  Future<void> _chargerSelectionsFigees() async {
    try {
      final sels = await IaMemoryService.instance
          .chargerSelectionsWidgetsPremiumDuJour(DateTime.now());
      if (!mounted) return;
      setState(() {
        _selectionsFigees = sels;
        _selectionsFigeesChargees = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _selectionsFigeesChargees = true; });
    }
  }

  /// Recherche la [_BetOpp] figée du jour pour un [sourceWidget] donné.
  /// Retourne null si absente ou si la course n'est pas dans `_reunions`.
  _BetOpp? _trouverOppFigee(String sourceWidget) {
    if (!_selectionsFigeesChargees) return null;
    final sel = _selectionsFigees[sourceWidget];
    if (sel == null || !sel.estValide) return null;
    try {
      for (final r in _reunions) {
        for (final c in r.courses) {
          final key = buildCourseKey(
            reunionCode: r.code,
            numCourse: c.numCourse,
            dateStr: c.dateStr,
          );
          if (key == sel.courseKey) {
            // Retrouvé → reconstruire un _BetOpp minimal depuis la course figée
            final partants = c.partantsParRangIA;
            if (partants.isEmpty) return null;
            final top = partants.first;
            return _BetOpp(
              course:         c,
              reunion:        r,
              favori:         top,
              scoreComposite: top.scoreIA,
              scoreConfiance: top.scoreIA,
              scoreGain:      top.scoreIA,
              typePari:       sel.typePari,
              conseil:        'Sélection figée du ${sel.dateKey}',
              numeros:        sel.numeros,
              estTerminee:    c.heureDateTime.isBefore(DateTime.now()),
            );
          }
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _charger({bool refresh = false}) async {
    // ★ v10.72 : Charger les signaux depuis le stockage
    await QuasiGrosParisService.instance.charger();
    // Charger immédiatement depuis le cache du DataRefreshService
    if (!refresh) {
      final svc = context.read<DataRefreshService>();
      if (svc.reunions.isNotEmpty) {
        if (mounted) setState(() { _reunions = svc.reunions; _loading = false; _error = null; });
        _enregistrerBestBetsPremium();
        _calculerEtSauvegarderSignaux();
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
      _enregistrerBestBetsPremium();
      _calculerEtSauvegarderSignaux();
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ★ v10.72 : Calcule et sauvegarde les signaux "Gros paris à surveiller" du jour
  Future<void> _calculerEtSauvegarderSignaux() async {
    try {
      final svc = QuasiGrosParisService.instance;
      final signaux = svc.calculerSignauxDuJour(_reunions);
      await svc.ajouterSignauxBatch(signaux);
      if (mounted) setState(() { _signauxGrosParis = svc.signauxAujourdhui(); });
      debugPrint('[GrosParis] ${signaux.length} signaux calculés');
    } catch (e) {
      debugPrint('[GrosParis] Erreur calcul signaux: $e');
    }
  }

  // ★ v10.37 v2 : Enregistrer les 3 Best Bets avec courseKey + typePari + numéros
  // ★ v10.62 : +figeage des 3 widgets premium BestBet (get-or-create, idempotent)
  Future<void> _enregistrerBestBetsPremium() async {
    try {
      final opps = _calculerOpportunites();
      if (opps.isEmpty) return;
      // Top Équilibre = trié par scoreComposite → first
      final trieComposite = List<_BetOpp>.from(opps)
        ..sort((a, b) => b.scoreComposite.compareTo(a.scoreComposite));
      final topEquilibre = trieComposite.isNotEmpty ? trieComposite.first : null;
      // Plus Sûr = trié par scoreConfiance → first
      final trieSur = List<_BetOpp>.from(opps)
        ..sort((a, b) => b.scoreConfiance.compareTo(a.scoreConfiance));
      final plusSur = trieSur.isNotEmpty ? trieSur.first : null;
      // Plus Rentable = trié par scoreGain → first
      final trieRentable = List<_BetOpp>.from(opps)
        ..sort((a, b) => b.scoreGain.compareTo(a.scoreGain));
      final plusRentable = trieRentable.isNotEmpty ? trieRentable.first : null;

      final premiums = <PremiumPronosticDuJour>[];

      // Chaque widget source est identifié explicitement pour l'historique étoile ⭐
      // ★ v10.54 : log debug ajouté — trace sourceWidget/courseKey/typePari/numeros
      void ajouterPremium(_BetOpp? opp, String sourceWidget) {
        if (opp == null) return;
        final key = buildCourseKey(
          reunionCode: opp.reunion.code,
          numCourse:   opp.course.numCourse,
          dateStr:     opp.course.dateStr,
        );
        if (key.isEmpty) return;
        premiums.add(PremiumPronosticDuJour(
          courseKey:    key,
          typePari:     opp.typePari,
          numeros:      opp.numeros,
          sourceWidget: sourceWidget,
        ));
        // ★ v10.54 : log debug enregistrement premium
        debugPrint('[Premium][$sourceWidget] courseKey=$key'
            ' | typePari=${opp.typePari}'
            ' | numeros=${opp.numeros} (${opp.numeros.length} cheval(aux))');
      }

      ajouterPremium(topEquilibre, 'topEquilibre');
      ajouterPremium(plusSur,      'plusSur');
      ajouterPremium(plusRentable, 'plusRentable');
      if (premiums.isNotEmpty) {
        IaMemoryService.instance.enregistrerPronosticsPremiumDuJour(premiums);
      }

      // ★ v10.62 — Figeage des 3 widgets premium BestBet (get-or-create)
      // Sécurité : ne fige que si courseKey + typePari + numeros sont valides.
      final aujourd = DateTime.now();
      final dateKeyAujourd = '${aujourd.year}-${aujourd.month.toString().padLeft(2,'0')}-${aujourd.day.toString().padLeft(2,'0')}';

      Future<void> figerBetOpp(_BetOpp? opp, String sourceWidget) async {
        if (opp == null) return;
        final key = buildCourseKey(
          reunionCode: opp.reunion.code,
          numCourse:   opp.course.numCourse,
          dateStr:     opp.course.dateStr,
        );
        if (key.isEmpty || opp.typePari.isEmpty || opp.numeros.isEmpty) return;
        await IaMemoryService.instance.obtenirOuCreerSelectionWidgetPremiumDuJour(
          date:         aujourd,
          sourceWidget: sourceWidget,
          calculerSelection: () => SelectionWidgetPremiumDuJour(
            dateKey:      dateKeyAujourd,
            sourceWidget: sourceWidget,
            courseKey:    key,
            typePari:     opp.typePari,
            numeros:      opp.numeros,
            nomCourse:    opp.course.nom,
            hippodrome:   opp.reunion.lieu,
            heure:        opp.course.heure,
            chevalNom:    opp.favori.nom,
            score:        opp.scoreConfiance,
            createdAt:    aujourd,
          ),
        );
      }

      await figerBetOpp(topEquilibre, 'topEquilibre');
      await figerBetOpp(plusSur,      'plusSur');
      await figerBetOpp(plusRentable, 'plusRentable');
      // — Fin figeage v10.62 —

      // ★ v10.69 : recharger les sélections figées APRÈS leur création
      // pour que _sortedBy() les lise immédiatement au prochain build.
      _chargerSelectionsFigees();

    } catch (_) {}
  }

  // ── Calcul des opportunités ───────────────────────────────────────
  List<_BetOpp> _calculerOpportunites() {
    final opps  = <_BetOpp>[];
    final seuils = IaMemoryService.instance.seuilsConfiance;
    final ia     = IaMemoryService.instance;

    // ★ v9.92 : Seuil de données minimum
    // Si l'IA a moins de 15 mises à jour, ses poids ne sont pas encore fiables.
    // On remonte le seuil minimum de 70 → 80 pour éviter les faux signaux.
    // Si moins de 5 mises à jour, on bloque entièrement (liste vide → message dédié).
    final nbMaj = ia.poids.nbMisesAJour;
    if (nbMaj < 5) return []; // Trop peu de données — message dédié affiché
    final seuilMinScore = nbMaj < 15 ? 80.0 : 70.0; // Plus strict si IA jeune
    for (final reunion in _reunions) {
      for (final course in reunion.courses) {
        if (course.partants.isEmpty) continue;
        // ── Toutes les courses sont incluses (passées aussi pour l'IA) ──
        final sorted = course.partantsParRangIA;
        if (sorted.isEmpty) continue;
        final top = sorted.first;

        // ★ v9.92 : seuil adaptatif selon maturité de l'IA
        if (top.scoreIA < seuilMinScore && !course.isQuinte && !course.isQuarte) continue;

        final scoreConf = top.scoreIA;
        // Score gain = basé sur la cote si dispo, sinon estimation via rang IA
        final cote = top.coteDecimale;
        final double scoreGainRaw;
        if (cote > 0 && cote < 99) {
          scoreGainRaw = (cote.clamp(1.1, 15.0) / 15.0 * 100).clamp(0.0, 100.0);
        } else {
          // Estimation : les favoris IA ont souvent une cote autour de 2-5
          // On estime en fonction du score IA inversé
          scoreGainRaw = (100.0 - top.scoreIA).clamp(20.0, 80.0);
        }

        // Composite : 65% confiance + 35% gain potentiel
        // Aligné sur la philosophie BestBetEngine (confiance = critère dominant)
        final composite = scoreConf * 0.65 + scoreGainRaw * 0.35;

        // ── Type de pari recommandé — seuils ADAPTATIFS (appris par l'IA) ──
        // Les seuils évoluent après chaque "Analyser la journée" selon la
        // précision réelle de l'IA pour chaque type de pari conseillé.
        final coteTop = top.coteDecimale;
        final score2nd = sorted.length >= 2 ? sorted[1].scoreIA : 0.0;
        final ecart12 = (scoreConf - score2nd).abs();
        final estEquilibre = ecart12 <= 15 && scoreConf >= 60 && score2nd >= 50;

        final String typePari;
        final String conseil;
        if (course.isQuinte) {
          typePari = 'Quinté+';
          final s5 = sorted.take(5).map((p) => 'N°${p.numero}').join(' - ');
          conseil = 'Course Quinté+ officielle. Sélection IA : $s5.';
        } else if (course.isQuarte) {
          typePari = 'Quarté+';
          final s4 = sorted.take(4).map((p) => 'N°${p.numero}').join(' - ');
          conseil = 'Course Quarté+ officielle. Sélection IA (4 chevaux) : $s4.';
        } else if (estEquilibre && scoreConf >= seuils.seuilCoupleGagnant) {
          typePari = 'Couplé Gagnant';
          conseil = 'Deux favoris très proches (${scoreConf.round()} vs ${score2nd.round()}/100). '
              'Couplé Gagnant : N°${top.numero} ${top.nom} + N°${sorted[1].numero} ${sorted[1].nom}.';
        } else if (estEquilibre && scoreConf >= seuils.seuilCouplePlace) {
          typePari = 'Couplé Placé';
          conseil = 'Course équilibrée. Couplé Placé : N°${top.numero} + N°${sorted[1].numero} dans le top 3.';
        } else if (scoreConf >= seuils.seuilSimpleGagnant && coteTop <= 8.0) {
          typePari = 'Simple Gagnant';
          conseil = 'Confiance très haute (${scoreConf.round()}/100). Misez sur N°${top.numero} ${top.nom} en Simple Gagnant.';
        } else if (scoreConf >= seuils.seuilSimpleGagnant && coteTop > 8.0) {
          typePari = 'Gagnant+Placé';
          conseil = 'Score élevé mais cote longue (×${coteTop.toStringAsFixed(1)}). '
              'Gagnant+Placé sécurise la mise sur N°${top.numero} ${top.nom}.';
        } else if (scoreConf >= seuils.seuilSimplePlace) {
          typePari = 'Simple Placé';
          conseil = 'Bon profil (${scoreConf.round()}/100). N°${top.numero} ${top.nom} en Simple Placé (top 3).';
        } else if (scoreConf >= seuils.seuilGagnantPlace) {
          typePari = 'Gagnant+Placé';
          final s2 = sorted.length > 1 ? 'N°${sorted[1].numero}' : '?';
          conseil = 'Score moyen (${scoreConf.round()}/100). Gagnant+Placé sur N°${top.numero}, '
              'ou Couplé avec $s2 pour couvrir les 2 cas.';
        } else if (scoreConf >= seuils.seuilTierce) {
          typePari = 'Tiercé';
          final s = sorted.take(3).map((p) => 'N°${p.numero}').join(' - ');
          conseil = 'Course incertaine (${scoreConf.round()}/100). Tiercé IA en désordre : $s.';
        } else {
          typePari = 'À surveiller';
          conseil = 'Course très ouverte (${scoreConf.round()}/100). Mise minimale ou abstention conseillée.';
        }

        // ★ v10.55 : délègue à premium_utils (source unique de vérité)
        final numeros = sorted
            .take(nbNumerosPourTypePari(typePari))
            .map((p) => p.numero)
            .toList();

        opps.add(_BetOpp(
          course: course,
          reunion: reunion,
          favori: top,
          scoreComposite: composite,
          scoreConfiance: scoreConf,
          scoreGain: scoreGainRaw,
          typePari: typePari,
          conseil: conseil,
          numeros: numeros,
          estTerminee: course.heureDateTime.isBefore(DateTime.now()),
        ));
      }
    }
    return opps;
  }

  List<_BetOpp> _sortedBy(int tab, List<_BetOpp> all) {
    // ★ v10.69 : PRIORITÉ 1 — sélection figée du jour pour ce tab
    // Si elle existe et est valide, elle est forcée en tête de liste.
    // Les autres opportunités suivent normalement (résultat inchangé pour tout sauf la carte TOP).
    final String sourceWidget = tab == 0 ? 'topEquilibre'
                              : tab == 1 ? 'plusSur'
                              :             'plusRentable';
    final oppFigee = _trouverOppFigee(sourceWidget);

    final list = List<_BetOpp>.from(all);
    switch (tab) {
      case 0: list.sort((a, b) => b.scoreComposite.compareTo(a.scoreComposite)); break;
      case 1: list.sort((a, b) => b.scoreConfiance.compareTo(a.scoreConfiance)); break;
      case 2: list.sort((a, b) => b.scoreGain.compareTo(a.scoreGain)); break;
    }

    if (oppFigee == null) return list;

    // La sélection figée est valide : la mettre en position 0.
    // Clé de la course figée pour dédoublonner dans la liste dynamique.
    final keyFigee = buildCourseKey(
      reunionCode: oppFigee.reunion.code,
      numCourse:   oppFigee.course.numCourse,
      dateStr:     oppFigee.course.dateStr,
    );
    // Retirer cette course de la liste dynamique si elle y est déjà (doublon)
    list.removeWhere((o) {
      final key = buildCourseKey(
        reunionCode: o.reunion.code,
        numCourse: o.course.numCourse,
        dateStr: o.course.dateStr,
      );
      return key == keyFigee;
    });
    return [oppFigee, ...list];
  }

  @override
  Widget build(BuildContext context) {
    // Écoute le DataRefreshService → se reconstruit automatiquement à chaque refresh
    final svc = context.watch<DataRefreshService>();
    if (!_loading && svc.reunions.isNotEmpty && _reunions != svc.reunions) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() { _reunions = svc.reunions; });
          // ★ v10.69 : recharger les sélections figées après mise à jour des réunions
          // pour que _trouverOppFigee() retrouve les courses dans le nouveau _reunions
          _chargerSelectionsFigees();
        }
      });
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1A1400), Color(0xFF0D1B2A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Ligne 1 : icône + titre + spinner + refresh ────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.4)),
                ),
                child: const Text('🏆', style: TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Meilleur Pari du Jour',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold)),
                    Text('Sélection IA PMU optimisée',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 14)),
                  ],
                ),
              ),
              if (_loading)
                const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Color(0xFFFFD700), strokeWidth: 2)),
              IconButton(
                onPressed: () => _charger(refresh: true),
                icon: const Icon(Icons.refresh,
                    color: Color(0xFFFFD700), size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),

          // ── Ligne 2 : mise + Kelly côte à côte ────────────────────
          const SizedBox(height: 10),
          Builder(builder: (ctx) {
            final opps = _calculerOpportunites();
            final showKelly = opps.isNotEmpty &&
                opps.first.favori.coteDecimale > 0 &&
                opps.first.favori.coteDecimale < 99;
            final kelly = showKelly
                ? GainCalculator.miseConseilleeKelly(
                    bankroll: _bankroll,
                    cote: opps.first.favori.coteDecimale,
                    probabiliteIA: opps.first.scoreConfiance,
                  )
                : 0.0;

            return Row(
              children: [
                // ── Mise simulée ──────────────────────────────────
                Expanded(
                  child: GestureDetector(
                    onTap: _changerMise,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0xFFFFD700).withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.edit,
                              color: Color(0xFFFFD700), size: 13),
                          const SizedBox(width: 5),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${_mise.toStringAsFixed(0)} €',
                                  style: const TextStyle(
                                      color: Color(0xFFFFD700),
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold)),
                              const Text('Mise simulée',
                                  style: TextStyle(
                                      color: Colors.white38, fontSize: 14)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Kelly ─────────────────────────────────────────
                if (showKelly && kelly > 0) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: _configurerBankroll,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF7D).withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: const Color(0xFF4CAF7D).withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.auto_graph,
                                color: Color(0xFF4CAF7D), size: 13),
                            const SizedBox(width: 5),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${fmtEuros(kelly)} €',
                                    style: const TextStyle(
                                        color: Color(0xFF4CAF7D),
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold)),
                                const Text('Mise Kelly',
                                    style: TextStyle(
                                        color: Colors.white38, fontSize: 14)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    // ★ v10.74 : titre complet ⊠ Gros paris à surveiller, badge si signaux > 0
    final nbSignaux = _signauxGrosParis.length;
    final tabGrosParis = Tab(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 14),
              const SizedBox(width: 3),
              const Text('⚠️ Gros paris', style: TextStyle(fontSize: 11)),
              if (nbSignaux > 0) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9800),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$nbSignaux',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const Text('à surveiller', style: TextStyle(fontSize: 10)),
        ],
      ),
    );

    return Container(
      color: const Color(0xFF0D1B2A),
      child: TabBar(
        controller: _tabCtrl,
        isScrollable: false,
        tabs: [
          const Tab(icon: Icon(Icons.balance, size: 16), text: 'Top Équilibre'),
          const Tab(icon: Icon(Icons.verified_outlined, size: 16), text: 'Plus Sûr'),
          const Tab(icon: Icon(Icons.trending_up, size: 16), text: 'Plus Rentable'),
          tabGrosParis,
        ],
        labelColor: const Color(0xFFFFD700),
        unselectedLabelColor: Colors.white38,
        indicatorColor: const Color(0xFFFFD700),
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFFFFD700)),
          SizedBox(height: 14),
          Text('Analyse des meilleures opportunités...', style: TextStyle(color: Colors.white54, fontSize: 15)),
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
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFB8860B)),
          ),
        ],
      ));
    }

    final opps = _calculerOpportunites();
    final nbMaj = IaMemoryService.instance.poids.nbMisesAJour;

    if (opps.isEmpty) {
      // ★ v9.92 : message différencié selon la cause
      final String emoji, titre, sousTitre;
      if (nbMaj < 5) {
        emoji    = '🧠';
        titre    = 'IA en apprentissage';
        sousTitre = 'Votre IA a effectué $nbMaj mise${nbMaj > 1 ? "s" : ""} à jour '
            '— il en faut au moins 5 pour générer un Best Bet fiable.\n'
            'Lancez "Analyser la journée" après chaque course pour accélérer l\'apprentissage.';
      } else if (nbMaj < 15) {
        emoji    = '📊';
        titre    = 'Données insuffisantes aujourd\'hui';
        sousTitre = 'L\'IA a $nbMaj mises à jour — elle est encore en rodage. '
            'Le seuil de confiance est relevé à 80/100 pour éviter les faux signaux. '
            'Aucune course ne dépasse ce seuil aujourd\'hui.';
      } else {
        emoji    = '🔍';
        titre    = 'Aucune course assez fiable';
        sousTitre = 'Les partants ne sont pas encore disponibles ou aucune course '
            'ne dépasse le seuil de confiance de ${70}/100 aujourd\'hui.';
      }
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(emoji, style: const TextStyle(fontSize: 52)),
          const SizedBox(height: 14),
          Text(titre, style: const TextStyle(color: Colors.white,
              fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(sousTitre, style: const TextStyle(color: Colors.white38, fontSize: 14),
              textAlign: TextAlign.center),
          if (nbMaj < 15) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF7C4DFF).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.4)),
              ),
              child: Text('Progression : $nbMaj / 15 analyses',
                  style: const TextStyle(color: Color(0xFF7C4DFF),
                      fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ],
        ]),
      ));
    }

    return TabBarView(
      controller: _tabCtrl,
      children: [
        // Onglets 0-2 : Best Bet classiques
        ...[0, 1, 2].map((tab) {
          final sorted = _sortedBy(tab, opps);
          return _buildListe(sorted, tab);
        }),
        // ★ v10.72 : Onglet 3 — Gros paris à surveiller
        _buildListeGrosParis(),
      ],
    );
  }

  Widget _buildListe(List<_BetOpp> opps, int tab) {
    // Séparer : cours à venir (non terminées) en haut, terminées en bas
    final aVenir    = opps.where((o) => !o.estTerminee).toList();
    final terminees = opps.where((o) =>  o.estTerminee).toList();

    // La carte TOP = première course à venir, sinon première terminée
    final top = aVenir.isNotEmpty ? aVenir.first : (terminees.isNotEmpty ? terminees.first : null);
    final autresAVenir    = aVenir.length > 1 ? aVenir.skip(1).toList() : <_BetOpp>[];
    final autresTerminees = (top != null && top.estTerminee)
        ? terminees.skip(1).toList()
        : terminees;

    VoidCallback? _onBet(_BetOpp opp) {
      if (opp.estTerminee) return null;
      return () { try { showBetSheet(
        context,
        reunion: opp.reunion,
        course: opp.course,
        alertService: AlertService.instance,
        chevalSuggere: opp.favori,
        onBetPlaced: () => context.read<NavigationNotifier>().goToMesParis(),
      ); } catch(e) { debugPrint('[BestBet] Parier erreur: \$e'); } };
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
      children: [
        // ─ Carte TOP du moment ─
        if (top != null)
          _TopBetCard(
            opp: top, mise: _mise, tab: tab,
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => CourseDetailScreen(course: top.course, reunion: top.reunion))),
            onChangerMise: _changerMise,
            onBet: _onBet(top),
          ),
        const SizedBox(height: 16),

        // ─ Sous-titre courses à venir ─
        if (autresAVenir.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              tab == 0 ? '📊 Opportunités à venir (équilibre)' :
              tab == 1 ? '🛡️ Par ordre de confiance IA' :
                         '💰 Par gain potentiel',
              style: const TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
          ...autresAVenir.map((opp) => _BetRow(
            opp: opp, mise: _mise,
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => CourseDetailScreen(course: opp.course, reunion: opp.reunion))),
            onBet: _onBet(opp),
          )),
          const SizedBox(height: 8),
        ],

        // ─ Séparateur + courses terminées ─
        if (autresTerminees.isNotEmpty) ...[
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2A1A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                const Icon(Icons.history, color: Colors.white38, size: 16),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Courses terminées — Analyse IA conservée pour apprentissage',
                    style: TextStyle(color: Colors.white38, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          ...autresTerminees.map((opp) => _BetRow(
            opp: opp, mise: _mise,
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => CourseDetailScreen(course: opp.course, reunion: opp.reunion))),
            onBet: null, // Parier bloqué — course terminée
          )),
        ],
      ],
    );
  }

  // ★ v9.93 : Configurer le bankroll pour Kelly
  void _configurerBankroll() {
    double temp = _bankroll;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1B2A),
        title: const Text('💰 Mon bankroll', style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'Votre capital total disponible pour les paris.\n'
            'Kelly calcule la mise optimale pour maximiser\nla croissance sans ruiner le bankroll.',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: TextEditingController(text: temp.toStringAsFixed(0)),
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              suffixText: '€',
              suffixStyle: const TextStyle(color: Color(0xFF4CAF7D)),
              filled: true,
              fillColor: const Color(0xFF111F30),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none),
            ),
            onChanged: (v) => temp = double.tryParse(v) ?? temp,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Annuler', style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF7D)),
            onPressed: () {
              setState(() => _bankroll = temp.clamp(10.0, 100000.0));
              Navigator.pop(context);
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  void _changerMise() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        double temp = _mise;
        return StatefulBuilder(
          builder: (ctx, setSt) {
            final cote = _calculerOpportunites().isNotEmpty
                ? () {
                    final opp = _calculerOpportunites().first;
                    final c = opp.favori.coteDecimale;
                    return (c > 0 && c < 99) ? c : 2.5;
                  }()
                : 2.5;
            final gainEstime = fmtEuros(temp * cote);
            return AlertDialog(
              backgroundColor: const Color(0xFF0D1B2A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              title: Row(
                children: [
                  const Icon(Icons.euro, color: Color(0xFFFFD700), size: 22),
                  const SizedBox(width: 8),
                  const Text('Définir ma mise', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  // Montant affiché en grand
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2F3D),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${temp.toStringAsFixed(0)} €',
                          style: const TextStyle(color: Color(0xFFFFD700), fontSize: 36, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Gain estimé : ~$gainEstime €  (cote ×${cote.toStringAsFixed(1)})',
                          style: const TextStyle(color: Colors.white38, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Curseur
                  Slider(
                    value: temp.clamp(2, 200),
                    min: 2, max: 200, divisions: 99,
                    activeColor: const Color(0xFFFFD700),
                    inactiveColor: const Color(0xFF1A3A2A),
                    onChanged: (v) => setSt(() => temp = v),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text('2 €', style: TextStyle(color: Colors.white24, fontSize: 14)),
                      Text('100 €', style: TextStyle(color: Colors.white24, fontSize: 14)),
                      Text('200 €', style: TextStyle(color: Colors.white24, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Boutons rapides
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Montants rapides :', style: TextStyle(color: Colors.white38, fontSize: 14)),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0].map((v) =>
                      GestureDetector(
                        onTap: () => setSt(() => temp = v),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: temp == v
                                ? const Color(0xFFFFD700).withValues(alpha: 0.25)
                                : const Color(0xFF1A2F3D),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: temp == v
                                  ? const Color(0xFFFFD700)
                                  : const Color(0xFF2A4A5A),
                            ),
                          ),
                          child: Text(
                            '${v.toInt()} €',
                            style: TextStyle(
                              color: temp == v ? const Color(0xFFFFD700) : Colors.white60,
                              fontWeight: temp == v ? FontWeight.bold : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ).toList(),
                  ),
                ],
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              actions: [
                SizedBox(
                  width: double.infinity,
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white54,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Annuler'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            setState(() => _mise = temp);
                            Navigator.pop(ctx);
                          },
                          icon: const Icon(Icons.check, size: 16),
                          label: Text('Valider — ${temp.toStringAsFixed(0)} €',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D52),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ v10.72 — ONGLET GROS PARIS À SURVEILLER
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildListeGrosParis() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFF9800)));
    }

    // Bandeau prudence obligatoire
    final bandeau = Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x22FF9800),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x66FFB74D)),
      ),
      child: const Row(children: [
        Icon(Icons.warning_amber_rounded, color: Color(0xFFFFCC80), size: 18),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Signal à surveiller — ne remplace pas les pronostics Premium officiels.',
            style: TextStyle(color: Color(0xFFFFCC80), fontSize: 13, fontWeight: FontWeight.w600, height: 1.35),
          ),
        ),
      ]),
    );

    if (_signauxGrosParis.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
        children: [
          bandeau,
          const SizedBox(height: 30),
          const Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('⚠️', style: TextStyle(fontSize: 44)),
              SizedBox(height: 12),
              Text('Aucun signal détecté aujourd\'hui',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              SizedBox(height: 8),
              Text(
                'Les signaux apparaissent quand l\'IA détecte\nN chevaux nettement au-dessus du reste\navec un écart ≥ 10 pts.',
                style: TextStyle(color: Colors.white38, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ]),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
      children: [
        bandeau,
        ..._signauxGrosParis.map((signal) => _carteGrosPari(signal)),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  ★ v10.74 — CARTE Gros Pari enrichie
  // ══════════════════════════════════════════════════════════════════════
  Widget _carteGrosPari(GrosPariSurveiller signal) {
    final color          = QuasiGrosParisService.couleurFiabilite(signal.niveau);
    final label          = QuasiGrosParisService.labelType(signal.type);
    final courseTerminee = signal.dateCourse.isBefore(DateTime.now());
    final nbChevaux      = QuasiGrosParisService.nbChevauxPourType(signal.type);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _ouvrirDetailGrosPari(signal),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF142030),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.65), width: 1.4),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.16), blurRadius: 14, offset: const Offset(0, 6)),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── En-tête : titre + badge terminée + force signal ──────────
          Row(children: [
            const Text('⚠️', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$label à surveiller',
                style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ),
            if (courseTerminee)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                child: const Text('Terminée', style: TextStyle(color: Colors.white38, fontSize: 11)),
              ),
            // Force signal : fiabilité arrondie /100
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Text(
                '${signal.fiabilite.round()}/100',
                style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          // ── Nom de la course ──────────────────────────────────────────
          Text(
            signal.nomCourse,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            '${signal.hippodrome} · ${signal.heure} · ${signal.discipline}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
          ),
          const Divider(height: 16, color: Colors.white10),
          // ── Force signal + sélection ──────────────────────────────────
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  'Force du signal',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  '${signal.fiabilite.round()}/100',
                  style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ]),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  'Sélection IA',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  signal.numeros.join(' - '),
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          // ── Écart IA ──────────────────────────────────────────────────
          Row(children: [
            Icon(Icons.trending_up, color: color, size: 15),
            const SizedBox(width: 5),
            Text(
              'Écart IA : +${signal.ecartAvecSuivant.toStringAsFixed(1)} pts avec le cheval suivant',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
            ),
          ]),
          const SizedBox(height: 6),
          // ── Explication courte ────────────────────────────────────────
          Text(
            'Pourquoi surveiller ? $nbChevaux chevaux ressortent nettement du reste du peloton.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 6),
          // ── Tap hint ─────────────────────────────────────────────────
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Text(
              'Voir classement complet IA →',
              style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 11),
            ),
          ]),
        ]),
      ),
    );
  }

  void _ouvrirDetailGrosPari(GrosPariSurveiller signal) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.88,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0F1722),
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: _FicheDetailGrosPari(
            signal:     signal,
            scrollCtrl: scrollCtrl,
            reunions:   _reunions,
            onParier:   () {
              Navigator.pop(context);
              _preRemplirPariGrosPari(signal);
            },
          ),
        ),
      ),
    );
  }

  /// ★ v10.72 : Prérempli une entrée dans Mes Paris depuis un signal Gros Pari.
  /// Ne valide PAS automatiquement — l'utilisateur confirme ensuite.
  void _preRemplirPariGrosPari(GrosPariSurveiller signal) {
    // Chercher la course correspondante dans _reunions pour ouvrir le bet sheet
    for (final reunion in _reunions) {
      for (final course in reunion.courses) {
        final key = buildCourseKey(
          reunionCode: reunion.code,
          numCourse:   course.numCourse,
          dateStr:     course.dateStr,
        );
        if (key == signal.courseKey && course.partants.isNotEmpty) {
          // Trouver le premier cheval de la sélection signal
          final partantSignal = course.partants.firstWhere(
            (p) => signal.numeros.contains(p.numero),
            orElse: () => course.partants.first,
          );
          try {
            showBetSheet(
              context,
              reunion: reunion,
              course: course,
              alertService: AlertService.instance,
              chevalSuggere: partantSignal,
              onBetPlaced: () => context.read<NavigationNotifier>().goToMesParis(),
            );
          } catch (e) {
            debugPrint('[GrosParis] Parier erreur: $e');
          }
          return;
        }
      }
    }
    // Course non trouvée dans les réunions actuelles
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Course non disponible dans le programme actuel.'),
        backgroundColor: Color(0xFF2A1200),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  ★ v10.74 — FICHE DÉTAIL GROS PARI — bottom sheet scrollable
// ══════════════════════════════════════════════════════════════════════════════
class _FicheDetailGrosPari extends StatelessWidget {
  final GrosPariSurveiller signal;
  final ScrollController    scrollCtrl;
  final List<ZtReunion>     reunions;
  final VoidCallback        onParier;

  const _FicheDetailGrosPari({
    required this.signal,
    required this.scrollCtrl,
    required this.reunions,
    required this.onParier,
  });

  @override
  Widget build(BuildContext context) {
    final color          = QuasiGrosParisService.couleurFiabilite(signal.niveau);
    final label          = QuasiGrosParisService.labelType(signal.type);
    final courseTerminee = signal.dateCourse.isBefore(DateTime.now());
    final nbChevaux      = QuasiGrosParisService.nbChevauxPourType(signal.type);

    // Cheval suivant = le premier hors sélection dans le classement complet
    final String? numeroSuivant = signal.classementCompletIA.length > nbChevaux
        ? signal.classementCompletIA[nbChevaux].numero
        : null;

    // Arrivée PMU si course terminée — chercher dans les pronostics IA
    final arrivee = _trouverArriveePMU();
    final comparaison = (courseTerminee && arrivee != null && arrivee.isNotEmpty)
        ? comparerCourseIA(
            selectionIA:  signal.numeros,
            arriveePMU:   arrivee,
            nb:           nbChevaux,
          )
        : null;

    return SafeArea(
      top: false,
      child: ListView(
        controller: scrollCtrl,
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
        children: [
          // ── Poignée ──────────────────────────────────────────────────
          Center(
            child: Container(
              width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),

          // ── Titre ─────────────────────────────────────────────────────
          Row(children: [
            const Text('⚠️', style: TextStyle(fontSize: 24)),
            const SizedBox(width: 10),
            Expanded(
              child: Text('$label à surveiller',
                  style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w900)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('${signal.fiabilite.round()}/100',
                  style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w900)),
            ),
          ]),
          const SizedBox(height: 14),

          // ── Infos course ──────────────────────────────────────────────
          Text(signal.nomCourse,
              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('${signal.hippodrome} · ${signal.heure} · ${signal.discipline}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
          const SizedBox(height: 16),

          // ── Sélection IA ──────────────────────────────────────────────
          _sectionTitre('Sélection IA du pari'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: signal.numeros.map((n) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.6)),
              ),
              child: Text('N°$n',
                  style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900)),
            )).toList(),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.trending_up, color: color, size: 14),
            const SizedBox(width: 5),
            Text(
              'Écart IA : +${signal.ecartAvecSuivant.toStringAsFixed(1)} pts avec le cheval suivant',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            QuasiGrosParisService.explicationGrosPari(signal),
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 20),

          // ── Classement IA complet ─────────────────────────────────────
          _sectionTitre('Classement IA complet'),
          const SizedBox(height: 10),
          if (signal.classementCompletIA.isEmpty)
            _avisu('Classement complet IA indisponible pour cet ancien signal.')
          else
            ...signal.classementCompletIA.map((c) => _ligneClassementIA(
              cheval:        c,
              selection:     signal.numeros,
              numeroSuivant: numeroSuivant,
              couleur:       color,
            )),
          const SizedBox(height: 20),

          // ── Comparaison PMU (si terminée) ─────────────────────────────
          if (courseTerminee) ...[
            _sectionTitre('Comparaison PMU'),
            const SizedBox(height: 10),
            if (comparaison == null)
              _avisu('Arrivée PMU non disponible.')
            else
              _buildComparaisonPMU(comparaison, color),
            const SizedBox(height: 20),
          ],

          // ── Bandeau prudence ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0x22FF9800),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x66FFB74D)),
            ),
            child: const Text(
              '⚠️ Signal à surveiller avec prudence. Ce pari ne remplace pas les pronostics Premium officiels.',
              style: TextStyle(color: Color(0xFFFFCC80), fontSize: 13, height: 1.35, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 18),

          // ── Bouton Parier ─────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: courseTerminee ? null : onParier,
              icon: const Icon(Icons.add_circle_outline),
              label: Text(courseTerminee ? 'Course terminée' : 'Parier'),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.black,
                disabledBackgroundColor: Colors.white12,
                disabledForegroundColor: Colors.white38,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Cherche l'arrivée PMU dans les pronostics IA mémorisés.
  List<String>? _trouverArriveePMU() {
    final pronostics = IaMemoryService.instance.pronostics;
    for (final p in pronostics) {
      if (p.courseKey == signal.courseKey && p.arriveeReelle != null) {
        return p.arriveeReelle!.map((e) => e.toString()).toList();
      }
    }
    return null;
  }

  Widget _sectionTitre(String titre) => Text(
    titre,
    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
  );

  Widget _avisu(String msg) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(msg, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
  );

  Widget _ligneClassementIA({
    required ChevalScoreIA cheval,
    required List<String>  selection,
    required String?       numeroSuivant,
    required Color         couleur,
  }) {
    final isSelected = selection.contains(cheval.numero);
    final isNext     = cheval.numero == numeroSuivant;
    final bgColor    = isSelected
        ? couleur.withValues(alpha: 0.18)
        : isNext
            ? const Color(0xFF4FC3F7).withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.04);
    final borderColor = isSelected
        ? couleur.withValues(alpha: 0.55)
        : isNext
            ? const Color(0xFF4FC3F7).withValues(alpha: 0.4)
            : Colors.white.withValues(alpha: 0.08);

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(children: [
        // Rang IA
        SizedBox(
          width: 24,
          child: Text('${cheval.rangIA}.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
        ),
        // Numéro
        Text('N°${cheval.numero}',
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
        const SizedBox(width: 10),
        // Nom
        Expanded(
          child: Text(cheval.nom,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
        ),
        // Score
        Text('${cheval.score.round()} pts',
            style: TextStyle(
              color: isSelected ? couleur : Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            )),
        // Badge
        if (isSelected) ...[const SizedBox(width: 6), const Text('✅', style: TextStyle(fontSize: 14))],
        if (isNext)     ...[const SizedBox(width: 6), const Text('👀', style: TextStyle(fontSize: 14))],
      ]),
    );
  }

  Widget _buildComparaisonPMU(ComparaisonCourseIA c, Color couleurSignal) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // IA vs PMU
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Sélection IA', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
          const SizedBox(height: 3),
          Text(c.selectionIA.join(' - '),
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
        ])),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Arrivée PMU', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
          const SizedBox(height: 3),
          Text(c.arriveePMU.take(8).join(' - '),
              style: const TextStyle(color: Color(0xFF66BB6A), fontSize: 15, fontWeight: FontWeight.w800)),
        ])),
      ]),
      const SizedBox(height: 14),
      // Classement réel de chaque cheval IA
      ...c.selectionIA.map((n) {
        final rang    = c.rangReelParNumero[n];
        final trouve  = c.trouves.contains(n);
        final icon    = trouve ? '✅' : '❌';
        final couleur = trouve ? const Color(0xFF66BB6A) : const Color(0xFFEF5350);
        final rangStr = rang == null ? 'non classé / hors arrivée connue' : 'arrivé ${rang}e';
        return Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(children: [
            Text(icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Text('N°$n', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Text('→ $rangStr',
                style: TextStyle(color: couleur, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        );
      }),
      const SizedBox(height: 10),
      // Manquant + remplaçant
      if (c.manquantsIA.isNotEmpty) ...[
        Row(children: [
          const Text('🔴 ', style: TextStyle(fontSize: 14)),
          Text('Manquant IA : ',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
          Text(c.manquantsIA.map((n) => 'N°$n').join(', '),
              style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 4),
      ],
      if (c.remplacantsPMU.isNotEmpty)
        Row(children: [
          const Text('🔵 ', style: TextStyle(fontSize: 14)),
          Text('Remplaçant PMU : ',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
          Text(c.remplacantsPMU.map((n) => 'N°$n').join(', '),
              style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
    ]);
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// CARTE TOP BET
// ──────────────────────────────────────────────────────────────────────────────
class _TopBetCard extends StatelessWidget {
  final _BetOpp opp;
  final double mise;
  final int tab;
  final VoidCallback onTap;
  final VoidCallback? onChangerMise;
  final VoidCallback? onBet;

  const _TopBetCard({required this.opp, required this.mise, required this.tab, required this.onTap, this.onChangerMise, this.onBet});

  @override
  Widget build(BuildContext context) {
    final p = opp.favori;
    final score = tab == 0 ? opp.scoreComposite : tab == 1 ? opp.scoreConfiance : opp.scoreGain;

    // ★ v10.61 — Streak INDÉPENDANT par widget (chaque _TopBetCard reçoit son propre tab)
    // Tab 0 = Top Équilibre → 'topEquilibre'
    // Tab 1 = Plus Sûr      → 'plusSur'
    // Tab 2 = Plus Rentable → 'plusRentable'
    // Aucun partage entre les 3 : streakCetteCarteUniquement est local à ce build()
    final String _sourceWidgetCetteCarte = tab == 0 ? 'topEquilibre'
                                         : tab == 1 ? 'plusSur'
                                         :             'plusRentable';
    final PremiumStreak streakCetteCarteUniquement = streakPourSource(
      sourceWidget:  _sourceWidgetCetteCarte,
      dateReference: DateTime.now(),
    );

    final confianceColor = opp.scoreConfiance >= 80
        ? const Color(0xFF00E676)
        : opp.scoreConfiance >= 65
            ? const Color(0xFFFFEA00)
            : opp.scoreConfiance >= 50
                ? const Color(0xFFFF6D00)
                : const Color(0xFFFF1744);

    // Gain estimé : cote réelle si dispo, sinon estimation basée sur score IA
    final cote = p.coteDecimale;
    final double coteEffective;
    if (cote > 0 && cote < 99) {
      coteEffective = cote;
    } else {
      // Estimation cote : favori IA à 100pts ≈ cote 2.5, score 50 ≈ cote 5.0
      coteEffective = (2.0 + (100.0 - opp.scoreConfiance) / 20.0).clamp(1.5, 8.0);
    }
    final gainEstime = '~${fmtEuros(mise * coteEffective)}€';
    final coteLabelStr = cote > 0 && cote < 99 ? cote.toStringAsFixed(1) : '~${coteEffective.toStringAsFixed(1)}';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFFFD700).withValues(alpha: 0.15),
              const Color(0xFF0D1B2A),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.6)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Badge + heure
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.6)),
                    ),
                    child: Row(
                      children: [
                        const Text('⭐', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 4),
                        Text(
                          tab == 0 ? 'TOP ÉQUILIBRE' : tab == 1 ? 'PLUS SÛR' : 'PLUS RENTABLE',
                          style: const TextStyle(color: Color(0xFFFFD700), fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  // ★ v9.3 : Bouton favori
                  FavoriButton(
                    numR:      int.tryParse(opp.reunion.code.replaceAll('R', '')) ?? 1,
                    numC:      opp.course.numCourse,
                    nomCourse: opp.course.nom,
                    hippodrome: opp.reunion.lieu,
                    scoreIA:   opp.scoreConfiance,
                    heure:     opp.course.heure,
                    distance:  opp.course.distance,
                    prix:      opp.course.prix,
                    size: 22,
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        opp.course.heure,
                        style: TextStyle(
                          color: opp.estTerminee ? Colors.white38 : const Color(0xFF4CAF7D),
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          decoration: opp.estTerminee ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (opp.estTerminee)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF5350).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: const Color(0xFFEF5350).withValues(alpha: 0.4)),
                          ),
                          child: const Text('Terminée',
                              style: TextStyle(color: Color(0xFFEF5350), fontSize: 14, fontWeight: FontWeight.bold)),
                        )
                      else
                        Text(opp.reunion.lieu,
                            style: const TextStyle(color: Colors.white38, fontSize: 14)),
                    ],
                  ),
                ],
              ),
              // ★ v10.61 — Phrase série premium PROPRE À CETTE CARTE (si streak ≥ 2)
              buildPremiumStreakPhrase(streak: streakCetteCarteUniquement),
              const SizedBox(height: 14),

              // Cheval
              Row(
                children: [
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFFA000)]),
                      boxShadow: [BoxShadow(color: const Color(0xFFFFD700).withValues(alpha: 0.3), blurRadius: 10)],
                    ),
                    child: Center(
                      child: Text(p.numero,
                          style: const TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.nom,
                            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        if (p.driver.isNotEmpty)
                          Text(p.driver, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(opp.course.nom,
                            style: const TextStyle(color: Colors.white30, fontSize: 14),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Métriques — Wrap pour petit écran
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _metric('Score', '${score.round()}', confianceColor),
                  _metric('Confiance', '${opp.scoreConfiance.round()}%', confianceColor),
                  _metric('Cote', coteLabelStr, Colors.white60),
                  _metric('Gain estimé', gainEstime, const Color(0xFFFFD700)),
                ],
              ),
              const SizedBox(height: 10),

              // Type de pari + conseil
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // ★ v10.30 : badge cliquable global
                        TypePariBadge(
                          type:      opp.typePari,
                          numeros:   opp.course.partantsParRangIA.take(
                            opp.typePari == 'Quinté+' ? 5 :
                            opp.typePari == 'Quarté+' ? 4 :
                            opp.typePari == 'Tiercé'  ? 3 :
                            opp.typePari.contains('Couplé') ? 2 : 1
                          ).map((p) => p.numero).toList(),
                          nomFavori: opp.favori.nom,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(opp.conseil, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4)),
                    // ★ v9.93 POINT 5 : Série chaude
                    Builder(builder: (ctx) {
                      final serie = IaMemoryService.instance.serieChaudePourType(opp.typePari);
                      if (serie == null) return const SizedBox();
                      final n      = serie['serie'] as int;
                      final chaud  = serie['chaud'] as bool;
                      final emoji  = chaud ? '🔥' : '✅';
                      final color  = chaud ? const Color(0xFFFF6D00) : const Color(0xFF4CAF7D);
                      // ★ v10.42 : libellé explicitement "Série IA récente" pour
                      // éviter la confusion — c'est une statistique historique par
                      // type de pari, pas une promesse sur la course affichée.
                      final label  = chaud
                          ? '$emoji Série IA récente : $n succès en ${opp.typePari} !'
                          : '$emoji Série IA récente : $n succès en ${opp.typePari}';
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: color.withValues(alpha: 0.35)),
                          ),
                          child: Text(label,
                              style: TextStyle(color: color, fontSize: 14,
                                  fontWeight: FontWeight.bold)),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // ── Arrivée réelle PMU ────────────────────────────────────
              ArriveReelleWidget(
                courseKey: buildCourseKey(
                  reunionCode: opp.reunion.code,
                  numCourse: opp.course.numCourse,
                  dateStr: opp.course.dateStr,
                ),
                isTerminee: opp.estTerminee,
                heureDepart: opp.course.heureDateTime, // ★ v9.6
                selectionIA: opp.course.partantsParRangIA
                    .take(5)
                    .map((p) => p.numero)
                    .toList(),
              ),
              const SizedBox(height: 10),

              // ── Bouton MISE + Bouton ANALYSE ─────────────────────────
              if (opp.estTerminee) ...[
                // Course terminée : bannière + analyse uniquement
                Container(
                  width: double.infinity,
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
                          style: TextStyle(color: Colors.white38, fontSize: 14, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.bar_chart, size: 15),
                    label: const Text('Voir l\'analyse IA', style: TextStyle(fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A2F3D),
                      foregroundColor: Colors.white60,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Colors.white12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ] else
                Row(
                  children: [
                    // Bouton PARIER (BetSheet universel)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onBet ?? onChangerMise,
                        icon: const Icon(Icons.euro, size: 16),
                        label: Text(
                          '💰 Parier ${mise.toStringAsFixed(0)}€',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D52),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Bouton VOIR ANALYSE
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onTap,
                        icon: const Icon(Icons.bar_chart, size: 15),
                        label: const Text('Analyse', style: TextStyle(fontSize: 14)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFD700),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metric(String label, String value, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Column(
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.white30, fontSize: 14)),
      ],
    ),
  );
}

// ──────────────────────────────────────────────────────────────────────────────
// LIGNE BET (liste secondaire)
// ──────────────────────────────────────────────────────────────────────────────
class _BetRow extends StatelessWidget {
  final _BetOpp opp;
  final double mise;
  final VoidCallback onTap;
  final VoidCallback? onBet;

  const _BetRow({required this.opp, required this.mise, required this.onTap, this.onBet});

  @override
  Widget build(BuildContext context) {
    final p = opp.favori;
    final confianceColor = opp.scoreConfiance >= 80
        ? const Color(0xFF00E676)
        : opp.scoreConfiance >= 65
            ? const Color(0xFFFFEA00)
            : opp.scoreConfiance >= 50
                ? const Color(0xFFFF6D00)
                : const Color(0xFFFF1744);
    final cote = p.coteDecimale;
    final double coteEff = cote > 0 && cote < 99
        ? cote
        : (2.0 + (100.0 - opp.scoreConfiance) / 20.0).clamp(1.5, 8.0);
    final gainEstime = '~${fmtEuros(mise * coteEff)}€';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2F3D),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: confianceColor.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
          children: [
            // N° cheval
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: confianceColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: confianceColor.withValues(alpha: 0.4)),
              ),
              child: Center(
                child: Text(p.numero, style: TextStyle(color: confianceColor, fontSize: 14, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.nom, style: TextStyle(
                      color: opp.estTerminee ? Colors.white54 : Colors.white,
                      fontSize: 14, fontWeight: FontWeight.w600),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text('${opp.course.nom} • ${opp.reunion.lieu} • ${opp.course.heure}',
                      style: const TextStyle(color: Colors.white38, fontSize: 14),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Row(
                    children: [
                      Flexible(child: Text(opp.typePari, style: TextStyle(
                          color: opp.estTerminee ? Colors.white38 : confianceColor,
                          fontSize: 14, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                      if (opp.estTerminee) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF5350).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFEF5350).withValues(alpha: 0.35)),
                          ),
                          child: const Text('🏁 Terminée',
                              style: TextStyle(color: Color(0xFFEF5350), fontSize: 14)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${opp.scoreConfiance.round()}%',
                    style: TextStyle(
                        color: opp.estTerminee ? Colors.white38 : confianceColor,
                        fontSize: 14, fontWeight: FontWeight.bold)),
                Text(gainEstime,
                    style: TextStyle(
                        color: opp.estTerminee ? Colors.white24 : const Color(0xFFFFD700),
                        fontSize: 14, fontWeight: FontWeight.bold)),
                const Text('gain est.', style: TextStyle(color: Colors.white24, fontSize: 14)),
              ],
            ),
            const SizedBox(width: 4),
            // Bouton Parier rapide — bloqué si terminée
            if (opp.estTerminee)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Icon(Icons.lock, color: Colors.white24, size: 16),
              )
            else if (onBet != null)
              GestureDetector(
                onTap: onBet,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D52).withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('💰', style: TextStyle(fontSize: 16)),
                ),
              )
            else
              const Icon(Icons.chevron_right, color: Colors.white24, size: 16),
          ],
          ),
        ),
        // Arrivée réelle compacte sous la ligne
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: ArriveReelleWidget(
          courseKey: buildCourseKey(
            reunionCode: opp.reunion.code,
            numCourse: opp.course.numCourse,
            dateStr: opp.course.dateStr,
          ),
          isTerminee: opp.estTerminee,
          heureDepart: opp.course.heureDateTime, // ★ v9.6
          selectionIA: opp.course.partantsParRangIA
              .take(5)
              .map((p) => p.numero)
              .toList(),
          ),
        ),
          ],
        ),
      ),
    );
  }
}
