// ═══════════════════════════════════════════════════════════════════════════
//  IA CALENDRIER TAB — ★ v10.26
//  Onglet autonome "📅 Calendrier" dans IaPerformanceScreen.
//
//  Logique paliers calibrée sur données réelles (271 analyses, ~26-31% moy.) :
//   🥇 OR      : ≥ 1 Tiercé/Quarté+/Quinté+ réussi (ordre ou désordre)
//   🟢 VERT    : taux ≥ 30%
//   🟡 JAUNE   : taux 25–29%
//   🟠 ORANGE  : taux 20–24%
//   🔴 ROUGE   : taux < 20%
//   ⬜ GRIS    : aucune course ce jour
//
//  Navigation : 24 mois max en arrière, vue mensuelle + annuelle.
//  Tap case → liste pronostics gagnants → dialog détail IA custom.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import '../type_pari_badge.dart'; // ★ v10.30
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/ia_memory_service.dart';
import '../../services/ia_memory_models.dart';
import '../../utils/premium_utils.dart' // ★ v10.55 — détection premium gagnant strict
    show
        estPremiumGagnantPourCarte,
        sourcePremiumPourCarte;
import '../../utils/premium_streak_ui.dart'; // ★ v10.61 — helper commun phrase série
// Note : PremiumPronosticDuJour vient de ia_memory_models.dart (déjà importé)
// Note : labelSourcePremium, decorationCartePremium, badgePremium remplacés par code inline v10.59
import 'ia_widgets_communs.dart';

// ── Constantes couleurs ────────────────────────────────────────────────────
const Color _cDark    = Color(0xFF0D1B2A);
const Color _cCard    = Color(0xFF111F30);
const Color _cGold    = Color(0xFFFFD700);
const Color _cGoldBg  = Color(0xFF2A2000);
const Color _cGreen   = Color(0xFF4CAF7D);
const Color _cGreenBg = Color(0xFF0F2A1A);
const Color _cYellow  = Color(0xFFFFB74D);
const Color _cYellBg  = Color(0xFF2A1E00);
const Color _cOrange  = Color(0xFFFF7043);
const Color _cOraBg   = Color(0xFF2A1200);
const Color _cRed     = Color(0xFFEF5350);
const Color _cRedBg   = Color(0xFF2A0A0A);
const Color _cGrey    = Color(0xFF1A2535);
const Color _cGreyTxt = Color(0xFF3A4A5A);

// ── Données palier ─────────────────────────────────────────────────────────
extension PalierExt on PalierCalendrier {
  Color get bg {
    switch (this) {
      case PalierCalendrier.or:     return _cGoldBg;
      case PalierCalendrier.vert:   return _cGreenBg;
      case PalierCalendrier.jaune:  return _cYellBg;
      case PalierCalendrier.orange: return _cOraBg;
      case PalierCalendrier.rouge:  return _cRedBg;
      case PalierCalendrier.gris:   return _cGrey;
    }
  }

  Color get fg {
    switch (this) {
      case PalierCalendrier.or:     return _cGold;
      case PalierCalendrier.vert:   return _cGreen;
      case PalierCalendrier.jaune:  return _cYellow;
      case PalierCalendrier.orange: return _cOrange;
      case PalierCalendrier.rouge:  return _cRed;
      case PalierCalendrier.gris:   return _cGreyTxt;
    }
  }

  Color get border {
    switch (this) {
      case PalierCalendrier.or:     return _cGold.withValues(alpha: 0.7);
      case PalierCalendrier.vert:   return _cGreen.withValues(alpha: 0.5);
      case PalierCalendrier.jaune:  return _cYellow.withValues(alpha: 0.4);
      case PalierCalendrier.orange: return _cOrange.withValues(alpha: 0.4);
      case PalierCalendrier.rouge:  return _cRed.withValues(alpha: 0.3);
      case PalierCalendrier.gris:   return Colors.transparent;
    }
  }

  String get emoji {
    switch (this) {
      case PalierCalendrier.or:     return '🥇';
      case PalierCalendrier.vert:   return '✓';
      case PalierCalendrier.jaune:  return '~';
      case PalierCalendrier.orange: return '·';
      case PalierCalendrier.rouge:  return '✗';
      case PalierCalendrier.gris:   return '';
    }
  }

  String get label {
    switch (this) {
      case PalierCalendrier.or:     return '🥇 Tiercé/Quarté/Quinté réussi';
      case PalierCalendrier.vert:   return '✅ Bonne journée (≥30%)';
      case PalierCalendrier.jaune:  return '📊 Dans la norme (25-29%)';
      case PalierCalendrier.orange: return '⚠️ En dessous (20-24%)';
      case PalierCalendrier.rouge:  return '❌ Journée ratée (<20%)';
      case PalierCalendrier.gris:   return '💤 Aucune course';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  WIDGET PRINCIPAL
// ═══════════════════════════════════════════════════════════════════════════

class IaCalendrierTab extends StatefulWidget {
  const IaCalendrierTab({super.key});

  @override
  State<IaCalendrierTab> createState() => _IaCalendrierTabState();
}

class _IaCalendrierTabState extends State<IaCalendrierTab>
    with SingleTickerProviderStateMixin {

  // ── State ─────────────────────────────────────────────────────────────
  late DateTime _moisRef;          // mois actuellement affiché
  late final TabController _modeTabs;

  static const int _maxMoisArriere = 24;

  // ★ v10.27 : Seuils dynamiques des paliers (modifiables par l'utilisateur)
  static const _keySeuilsCalendrier = 'ia_calendrier_seuils_v1';
  double _seuilVert   = 30.0;
  double _seuilJaune  = 25.0;
  double _seuilOrange = 20.0;

  // ★ v10.31 : _ctrlVert/Jaune/Orange + _editVert/Jaune/Orange supprimés
  //            (unused_field après suppression de _buildLegende)
  //            L'édition des seuils reste dans _SeuilsParamsSheet.

  // ★ v10.26 : Indicateur de rafraîchissement temps réel
  // ignore: unused_field
  bool _showRefreshFlash = false; // ★ v10.26d : _flashKey/_dernierRefresh supprimés (unused_field)

  // ── Noms mois / jours ─────────────────────────────────────────────────
  static const _nomsMois = [
    '', 'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
    'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre',
  ];
  static const _nomsJoursCourts = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _moisRef  = DateTime(now.year, now.month, 1);
    _modeTabs = TabController(length: 2, vsync: this);
    _modeTabs.addListener(() => setState(() {}));
    IaMemoryService.instance.addListener(_onMemChange);
    _chargerSeuils();
  }

  @override
  void dispose() {
    _modeTabs.dispose();
    IaMemoryService.instance.removeListener(_onMemChange);
    super.dispose();
  }

  void _onMemChange() {
    if (!mounted) return;
    setState(() {
      _showRefreshFlash = true;
    });
    // Flash disparaît après 800ms
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showRefreshFlash = false);
    });
  }

  // ── Seuils dynamiques — chargement / sauvegarde ───────────────────────
  Future<void> _chargerSeuils() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_keySeuilsCalendrier);
    if (raw != null) {
      // Format compact : "30.0|25.0|20.0"
      final parts = raw.split('|');
      if (parts.length == 3) {
        final v = double.tryParse(parts[0]);
        final j = double.tryParse(parts[1]);
        final o = double.tryParse(parts[2]);
        if (v != null && j != null && o != null && v > j && j > o && o > 0) {
          if (mounted) setState(() {
            _seuilVert   = v;
            _seuilJaune  = j;
            _seuilOrange = o;
          });
        }
      }
    }
  }

  Future<void> _sauvegarderSeuils() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keySeuilsCalendrier,
      '$_seuilVert|$_seuilJaune|$_seuilOrange',
    );
  }

  // ── Calcul palier dynamique (utilise les seuils éditables) ────────────
  PalierCalendrier _getPalierDynamique(DonneeJourCalendrier dd) {
    // OR est immuable — déterminé par l'IA, indépendant des seuils
    if (dd.palier == PalierCalendrier.or) return PalierCalendrier.or;
    if (dd.nbCourses == 0)               return PalierCalendrier.gris;
    final pct = dd.taux * 100;
    if (pct >= _seuilVert)   return PalierCalendrier.vert;
    if (pct >= _seuilJaune)  return PalierCalendrier.jaune;
    if (pct >= _seuilOrange) return PalierCalendrier.orange;
    return PalierCalendrier.rouge;
  }

  // ── Navigation mois ───────────────────────────────────────────────────
  bool get _peutReculer {
    final limite = DateTime(
      DateTime.now().year,
      DateTime.now().month - _maxMoisArriere + 1,
      1,
    );
    return _moisRef.isAfter(limite);
  }

  bool get _peutAvancer {
    final now = DateTime.now();
    return _moisRef.isBefore(DateTime(now.year, now.month, 1));
  }

  void _reculer() {
    if (!_peutReculer) return;
    setState(() => _moisRef = DateTime(_moisRef.year, _moisRef.month - 1, 1));
  }

  void _avancer() {
    if (!_peutAvancer) return;
    setState(() => _moisRef = DateTime(_moisRef.year, _moisRef.month + 1, 1));
  }

  void _allerAujourdhui() {
    final now = DateTime.now();
    setState(() {
      _moisRef = DateTime(now.year, now.month, 1);
    });
    _modeTabs.animateTo(0); // revient en vue mensuelle
  }

  // ── Build racine ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Calcul unique : évite 4 appels séparés dans les sous-widgets (★ a2)
    final data = _modeTabs.index == 0
        ? IaMemoryService.instance
            .donneesCalendrierJour(_moisRef.year, _moisRef.month)
        : const <int, DonneeJourCalendrier>{};

    return Container(
      color: _cDark,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 32),
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          // ★ v10.30 : Toggle + légende compacts fusionnés
          _buildToggleEtLegendeFusionnes(),
          const SizedBox(height: 12),
          if (_modeTabs.index == 0) ...[
            _buildCalendrierMensuel(data),
            const SizedBox(height: 20),
            _buildBilanMois(data),
            const SizedBox(height: 20),
            _buildStatsByType(data),
            const SizedBox(height: 20),
            _buildTendanceJours(data),
          ] else ...[
            _buildVueAnnuelle(),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  HEADER — navigation mois
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildHeader() {
    final estMoisCourant = !_peutAvancer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        color: _cCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(children: [
        // ◀ Précédent
        _navBtn(Icons.chevron_left, _peutReculer ? _reculer : null),

        // Titre mois
        Expanded(
          child: GestureDetector(
            onTap: _allerAujourdhui,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
              Text(
                '${_nomsMois[_moisRef.month]} ${_moisRef.year}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
              if (!estMoisCourant) ...[
                const SizedBox(height: 2),
                Text(
                  'Tap → mois courant',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _cGold.withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                ),
              ],
            ]),
          ),
        ),

        // ▶ Suivant
        _navBtn(Icons.chevron_right, _peutAvancer ? _avancer : null),

        // ★ v10.51/v10.52 : Bouton admin reset étoile — couleur visible
        const SizedBox(width: 4),
        Tooltip(
          message: 'Reset étoile premium',
          child: GestureDetector(
            onTap: () => _ouvrirResetEtoile(context),
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD54F).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFFFD54F).withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.cleaning_services,
                color: Color(0xFFFFD54F),
                size: 20,
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ★ v10.51 — Reset étoile premium (outil admin/debug)
  // Accessible via l'icône 🧹 dans le header du calendrier.
  // NE TOUCHE PAS : mémoire IA, poids, apprentissage, pronostics.
  Future<void> _ouvrirResetEtoile(BuildContext context) async {
    // ── Étape 1 : choix du mode ──────────────────────────────────────────
    final choix = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF0D1B2A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Icon(Icons.cleaning_services, color: Color(0xFFFFB74D), size: 18),
                SizedBox(width: 8),
                Text(
                  'Reset étoile premium',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 4),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Ne touche pas à la mémoire IA ni à l\'apprentissage.',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(color: Colors.white12, height: 1),
            ListTile(
              leading: const Icon(Icons.event, color: Color(0xFF42A5F5)),
              title: const Text(
                'Réinitialiser une date',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Choisir un jour précis',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
              onTap: () => Navigator.pop(_, 'date'),
            ),
            ListTile(
              leading: const Icon(Icons.warning_amber, color: Color(0xFFEF5350)),
              title: const Text(
                'Réinitialiser toutes les étoiles premium',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Efface tout l\'historique premium',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
              onTap: () => Navigator.pop(_, 'all'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted) return;

    // ── Étape 2a : reset d'une date précise ─────────────────────────────
    if (choix == 'date') {
      final date = await showDatePicker(
        context: context,
        initialDate: _moisRef.copyWith(day: 1),
        firstDate: DateTime(2024),
        lastDate: DateTime.now().add(const Duration(days: 1)),
        builder: (ctx, child) => Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFFFB74D),
              onPrimary: Colors.black,
              surface: Color(0xFF111F30),
              onSurface: Colors.white,
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: Color(0xFF0D1B2A),
            ),
          ),
          child: child!,
        ),
      );

      if (!mounted || date == null) return;

      final j   = date.day.toString().padLeft(2, '0');
      final m   = date.month.toString().padLeft(2, '0');
      final an  = date.year.toString();

      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF0A1628),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.star_border, color: Color(0xFFFFB74D)),
            SizedBox(width: 8),
            Text('Confirmer', style: TextStyle(color: Colors.white, fontSize: 17)),
          ]),
          content: Text(
            'Supprimer uniquement l\'étoile premium du $j/$m/$an ?\n\n'
            'Les autres jours, la mémoire IA et l\'apprentissage '
            'ne sont pas modifiés.',
            style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(_, false),
              child: const Text('Annuler', style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(_, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB74D),
              ),
              child: const Text('Supprimer',
                  style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (!mounted || ok != true) return;

      await IaMemoryService.instance.resetPremiumPourDate(date);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Étoile premium du $j/$m/$an réinitialisée.'),
          backgroundColor: const Color(0xFFFFB74D),
          duration: const Duration(seconds: 3),
        ),
      );
      setState(() {});
    }

    // ── Étape 2b : reset de TOUTES les étoiles ───────────────────────────
    if (choix == 'all') {
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF0A1628),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.warning_amber, color: Color(0xFFEF5350)),
            SizedBox(width: 8),
            Text('Zone dangereuse',
                style: TextStyle(color: Colors.white, fontSize: 17)),
          ]),
          content: const Text(
            'Supprimer TOUTES les étoiles premium historiques ?\n\n'
            'Cette action est irréversible.\n'
            'La mémoire IA, les poids et l\'apprentissage '
            'ne sont PAS modifiés.',
            style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(_, false),
              child: const Text('Annuler', style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(_, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF5350),
              ),
              child: const Text('Tout supprimer',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (!mounted || ok != true) return;

      await IaMemoryService.instance.resetToutesEtoilesPremium();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Toutes les étoiles premium ont été réinitialisées.'),
          backgroundColor: Color(0xFFEF5350),
          duration: Duration(seconds: 3),
        ),
      );
      setState(() {});
    }
  }

  Widget _navBtn(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: onTap != null
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon,
          color: onTap != null ? Colors.white70 : Colors.white12,
          size: 22,
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  ★ v10.33 : TOGGLE MENSUEL/ANNUEL + LÉGENDE CLIQUABLE
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildToggleEtLegendeFusionnes() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(children: [

        // ── Ligne 1 : Toggle Mensuel / Annuel ──
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: _cDark,
            borderRadius: BorderRadius.circular(10),
          ),
          child: TabBar(
            controller: _modeTabs,
            indicator: BoxDecoration(
              color: _cGold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _cGold.withValues(alpha: 0.45)),
            ),
            labelColor: _cGold,
            unselectedLabelColor: Colors.white38,
            labelStyle: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.normal),
            dividerColor: Colors.transparent,
            tabAlignment: TabAlignment.fill,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            indicatorPadding: EdgeInsets.zero,
            tabs: const [
              Tab(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('📅 Mensuel', overflow: TextOverflow.visible, softWrap: false),
                ),
              ),
              Tab(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('📆 Annuel', overflow: TextOverflow.visible, softWrap: false),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── Ligne 2 : Légende cliquable — chaque puce ouvre son sheet ──
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _legendePuce(PalierCalendrier.or,     '🥇', 'Noble',    null),
            _legendePuce(PalierCalendrier.vert,   '✅', '≥${_seuilVert.toStringAsFixed(0)}%',   PalierCalendrier.vert),
            _legendePuce(PalierCalendrier.jaune,  '📊', '≥${_seuilJaune.toStringAsFixed(0)}%',  PalierCalendrier.jaune),
            _legendePuce(PalierCalendrier.orange, '⚠️', '≥${_seuilOrange.toStringAsFixed(0)}%', PalierCalendrier.orange),
            _legendePuce(PalierCalendrier.rouge,  '❌', '<${_seuilOrange.toStringAsFixed(0)}%',  PalierCalendrier.rouge),
            _legendePuce(PalierCalendrier.gris,   '💤', 'Repos',    null),
          ],
        ),
        // ★ v10.37/v10.52 : Légende étoile Best Bet — Expanded pour éviter overflow
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('⭐', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Best Bet — Conseil IA, Meilleur Pari ou Best Bet du jour réussi',
                style: TextStyle(color: _cGold.withValues(alpha: 0.75), fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
              ),
            ),
          ],
        ),
      ]),
    );
  }

  /// Puce de légende — cliquable si palierEditable != null
  Widget _legendePuce(PalierCalendrier p, String emoji, String label,
      PalierCalendrier? palierEditable) {
    final isEditable = palierEditable != null &&
        palierEditable != PalierCalendrier.rouge; // rouge = dérivé de orange
    return GestureDetector(
      onTap: isEditable
          ? () => _ouvrirSeuilPourPalier(palierEditable)
          : null,
      child: Column(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: p.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isEditable
                  ? p.fg.withValues(alpha: 0.6)
                  : p.border.withValues(alpha: 0.4),
              width: isEditable ? 1.5 : 0.8,
            ),
          ),
          child: Center(child: Text(emoji,
              style: const TextStyle(fontSize: 15))),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(
            color: isEditable ? p.fg.withValues(alpha: 0.9) : Colors.white38,
            fontSize: 14,
            fontWeight: isEditable ? FontWeight.w700 : FontWeight.w500)),
      ]),
    );
  }

  /// Ouvre le sheet de paramétrage pour un palier spécifique
  void _ouvrirSeuilPourPalier(PalierCalendrier palier) {
    // ★ v10.34 : Dialog centré au milieu de l'écran
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: _SeuilUniquSheet(
        palier:      palier,
        seuilVert:   _seuilVert,
        seuilJaune:  _seuilJaune,
        seuilOrange: _seuilOrange,
        onApply: (v, j, o) {
          setState(() {
            _seuilVert   = v;
            _seuilJaune  = j;
            _seuilOrange = o;
          });
          _sauvegarderSeuils();
        },
      )),  // ferme _SeuilUniquSheet + Dialog
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  CALENDRIER MENSUEL — grille 7 colonnes
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildCalendrierMensuel(Map<int, DonneeJourCalendrier> data) {
    final now       = DateTime.now();
    final dernierJ  = DateTime(_moisRef.year, _moisRef.month + 1, 0).day;
    final premierWd = DateTime(_moisRef.year, _moisRef.month, 1).weekday; // 1=Lun
    final decalage  = premierWd - 1;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(children: [
        // Labels jours semaine
        Row(children: _nomsJoursCourts.map((l) => Expanded(
          child: Text(l,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        )).toList()),
        const SizedBox(height: 8),

        // Grille
        _buildGrille(
          data:       data,
          decalage:   decalage,
          dernierJ:   dernierJ,
          moisRef:    _moisRef,
          now:        now,
        ),
      ]),
    );
  }

  Widget _buildGrille({
    required Map<int, DonneeJourCalendrier> data,
    required int decalage,
    required int dernierJ,
    required DateTime moisRef,
    required DateTime now,
  }) {
    final List<Widget> rows  = [];
    final List<Widget> cells = [];

    // Cases vides avant le 1er
    for (int i = 0; i < decalage; i++) {
      cells.add(const Expanded(child: SizedBox(height: 42)));
    }

    for (int jour = 1; jour <= dernierJ; jour++) {
      final dd      = data[jour];
      final estAuj  = now.year == moisRef.year &&
                      now.month == moisRef.month &&
                      now.day == jour;
      final estFut  = DateTime(moisRef.year, moisRef.month, jour).isAfter(now);
      // ★ v10.27 : Palier calculé dynamiquement avec les seuils éditables
      final palier  = estFut || dd == null
          ? PalierCalendrier.gris
          : _getPalierDynamique(dd);
      final estGris = palier == PalierCalendrier.gris;

      cells.add(Expanded(
        child: GestureDetector(
          onTap: (!estGris && !estFut && dd != null && dd.nbCourses > 0)
              ? () => _ouvrirDetailJour(context, dd, moisRef)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: _buildCase(
              jour:      jour,
              dd:        dd,
              palier:    palier,
              estAuj:    estAuj,
              estFut:    estFut,
            ),
          ),
        ),
      ));

      if ((decalage + jour) % 7 == 0 || jour == dernierJ) {
        // Compléter dernière ligne
        while (cells.length < 7) {
          cells.add(const Expanded(child: SizedBox(height: 42)));
        }
        rows.add(Row(children: List.from(cells)));
        rows.add(const SizedBox(height: 3));
        cells.clear();
      }
    }

    return Column(children: rows);
  }

  Widget _buildCase({
    required int                     jour,
    required DonneeJourCalendrier?   dd,
    required PalierCalendrier        palier,
    required bool                    estAuj,
    required bool                    estFut,
  }) {
    final hasCourses = dd != null && dd.nbCourses > 0 && !estFut;
    // ignore: unused_local_variable
    final fgColor    = estFut ? Colors.white12 : (hasCourses ? palier.fg : _cGreyTxt);
    final bgColor    = estFut ? _cGrey : palier.bg;
    final bordColor  = estAuj
        ? _cGold.withValues(alpha: 0.9)
        : (hasCourses ? palier.border : Colors.transparent);
    // ★ v10.36 : Best Bet — pronostic de haute qualité ce jour
    final hasBestBet = hasCourses && (dd.hasBestBet);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      height: 42,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: bordColor, width: estAuj ? 1.8 : 0.8),
        boxShadow: palier == PalierCalendrier.or && hasCourses
            ? [BoxShadow(
                color: _cGold.withValues(alpha: 0.25),
                blurRadius: 6,
                spreadRadius: 1,
              )]
            : hasBestBet
            ? [BoxShadow(
                color: _cGold.withValues(alpha: 0.18),
                blurRadius: 4,
                spreadRadius: 0,
              )]
            : null,
      ),
      child: Stack(alignment: Alignment.center, children: [
        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(
            '$jour',
            style: TextStyle(
              color: estAuj
                  ? _cGold
                  : (hasCourses ? Colors.white : _cGreyTxt),
              fontSize: 14,
              fontWeight: estAuj || palier == PalierCalendrier.or
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),
          if (hasCourses && dd.nbCourses > 0)
            Text(
              '${dd.nbBons}/${dd.nbCourses}',
              style: TextStyle(
                color: palier == PalierCalendrier.gris
                    ? _cGreyTxt
                    : Colors.white.withValues(alpha: 0.85),
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
        ]),

        // ★ v10.36 : Étoile ⭐ Best Bet en haut à gauche
        // Visible sur tous les paliers sauf OR (qui a déjà ★ à droite)
        if (hasBestBet && palier != PalierCalendrier.or)
          Positioned(
            top: 2, left: 3,
            child: Text('⭐',
              style: const TextStyle(fontSize: 8),
            ),
          ),

        // Indicateur OR ★ en haut à droite (inchangé)
        if (palier == PalierCalendrier.or && hasCourses)
          Positioned(
            top: 2, right: 3,
            child: Text('★',
              style: TextStyle(
                color: _cGold,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  BILAN DU MOIS
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildBilanMois(Map<int, DonneeJourCalendrier> data) {
    if (data.isEmpty) {
      return _emptyState('Aucune donnée pour ce mois');
    }

    int totalC = 0, totalB = 0, joursOr = 0, joursVert = 0,
        joursJaune = 0, joursOrange = 0, joursRouge = 0;
    for (final d in data.values) {
      totalC     += d.nbCourses;
      totalB     += d.nbBons;
      switch (d.palier) {
        case PalierCalendrier.or:     joursOr++;     break;
        case PalierCalendrier.vert:   joursVert++;   break;
        case PalierCalendrier.jaune:  joursJaune++;  break;
        case PalierCalendrier.orange: joursOrange++; break;
        case PalierCalendrier.rouge:  joursRouge++;  break;
        case PalierCalendrier.gris:   break;
      }
    }
    final joursActifs = data.values.where((d) => d.nbCourses > 0).length;
    final taux        = totalC > 0 ? (totalB / totalC * 100) : 0.0;
    final tauxColor   = taux >= 30 ? _cGreen
                       : taux >= 25 ? _cYellow
                       : taux >= 20 ? _cOrange
                       : _cRed;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      iaSectionTitle('📊 Bilan du mois'),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _cCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Column(children: [
          // Ligne stats principales
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _statBox('$joursActifs', 'jours actifs', const Color(0xFF42A5F5)),
            _divV(),
            _statBox('$totalC', 'courses', Colors.white54),
            _divV(),
            _statBox('$totalB', 'bons conseils', _cGreen),
            _divV(),
            _statBox('${taux.toStringAsFixed(0)}%', 'réussite', tauxColor),
          ]),
          const SizedBox(height: 14),

          // Barre de répartition des paliers
          if (joursActifs > 0) ...[
            _buildRepartitionBar(
              joursOr, joursVert, joursJaune, joursOrange, joursRouge, joursActifs,
            ),
            const SizedBox(height: 12),
            _buildCommentaireMois(taux, joursOr, joursVert, joursRouge, joursActifs),
          ],
        ]),
      ),
    ]);
  }

  Widget _buildRepartitionBar(
    int or_, int vert, int jaune, int orange, int rouge, int total,
  ) {
    if (total == 0) return const SizedBox();
    final parts = [
      (or_,    _cGold),
      (vert,   _cGreen),
      (jaune,  _cYellow),
      (orange, _cOrange),
      (rouge,  _cRed),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Répartition des journées',
        style: TextStyle(color: Colors.white54, fontSize: 14)),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Row(
          children: parts.where((p) => p.$1 > 0).map((p) {
            return Expanded(
              flex: p.$1,
              child: Container(
                height: 8,
                color: p.$2,
              ),
            );
          }).toList(),
        ),
      ),
      const SizedBox(height: 8),
      // Mini légende
      Wrap(spacing: 12, runSpacing: 4, children: parts.where((p) => p.$1 > 0).map((p) {
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8,
            decoration: BoxDecoration(color: p.$2, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 4),
          Text('${p.$1}j', style: TextStyle(color: p.$2, fontSize: 14, fontWeight: FontWeight.bold)),
        ]);
      }).toList()),
    ]);
  }

  Widget _buildCommentaireMois(
    double taux, int joursOr, int joursVert, int joursRouge, int joursActifs,
  ) {
    String commentaire;
    Color  couleurComm;
    String emoji;

    // ★ v10.26 : Commentaire aligné sur les nouveaux seuils calibrés
    // VERT≥30% | JAUNE 25-29% | ORANGE 20-24% | ROUGE<20%
    if (joursOr >= 1 && taux >= 30) {
      commentaire = 'Mois exceptionnel 🔥 — Tiercé/Quarté/Quinté réussis + excellente précision !';
      couleurComm = _cGold;
      emoji       = '🏆';
    } else if (joursOr >= 1) {
      commentaire = 'Bon mois — Au moins un pari noble réussi (Tiercé/Quarté+/Quinté+).';
      couleurComm = _cGold;
      emoji       = '🥇';
    } else if (taux >= 30) {
      commentaire = 'Très bon mois — L\'IA dépasse 30% de réussite. Continue !';
      couleurComm = _cGreen;
      emoji       = '✅';
    } else if (taux >= 25) {
      commentaire = 'Mois dans la norme — Performance attendue (25–29%).';
      couleurComm = _cYellow;
      emoji       = '📊';
    } else if (taux >= 20) {
      commentaire = 'Mois en dessous — Taux 20–24%, l\'IA accumule encore des données.';
      couleurComm = _cOrange;
      emoji       = '⚠️';
    } else if (joursRouge > joursActifs * 0.5) {
      commentaire = 'Mois difficile — Plus de 50% de journées ratées. Normal en phase d\'apprentissage.';
      couleurComm = _cRed;
      emoji       = '📉';
    } else {
      commentaire = 'Mois faible — Taux < 20%. L\'IA a besoin de plus d\'analyses pour progresser.';
      couleurComm = _cRed;
      emoji       = '❌';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: couleurComm.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: couleurComm.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(commentaire,
            style: TextStyle(color: couleurComm, fontSize: 14)),
        ),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  STATS PAR TYPE DE PARI — barres visuelles
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildStatsByType(Map<int, DonneeJourCalendrier> data) {
    // Agréger par type de pari
    final Map<String, int> nbByType   = {};
    final Map<String, int> bonsbyType = {};

    for (final d in data.values) {
      for (final p in d.pronostics) {
        final t = p.typePariConseille ?? '';
        if (t.isEmpty || t == 'Inconnu' || t == 'À surveiller') continue;
        nbByType[t]    = (nbByType[t]    ?? 0) + 1;
        if (IaMemoryService.instance.estBonConseil(p, t)) {
          bonsbyType[t] = (bonsbyType[t] ?? 0) + 1;
        }
      }
    }

    if (nbByType.isEmpty) return const SizedBox();

    // Trier par nb décroissant
    final types = nbByType.keys.toList()
      ..sort((a, b) => (nbByType[b] ?? 0).compareTo(nbByType[a] ?? 0));

    // ★ v10.57 — Libellé de filtre actif pour éviter la confusion "8/14 = 814"
    const _nomsMoisStats = [
      '', 'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
      'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre',
    ];
    final now           = DateTime.now();
    final estMoisActuel = _moisRef.year == now.year && _moisRef.month == now.month;
    final labelPeriode  = estMoisActuel
        ? "Aujourd'hui — ${_nomsMoisStats[_moisRef.month]} ${_moisRef.year}"
        : '${_nomsMoisStats[_moisRef.month]} ${_moisRef.year}';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      iaSectionTitle('🎯 Précision par type de pari'),
      const SizedBox(height: 6),
      // ★ v10.57 — En-tête filtre actif
      Text(
        'Filtre : $labelPeriode',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13),
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _cCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Column(
          children: types.map((t) {
            final nb   = nbByType[t]   ?? 0;
            final bons = bonsbyType[t] ?? 0;
            final tx   = nb > 0 ? bons / nb : 0.0;
            final col  = tx >= 0.30 ? _cGreen
                       : tx >= 0.25 ? _cYellow
                       : tx >= 0.20 ? _cOrange
                       : _cRed;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(t,
                      style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  ),
                  // ★ v10.57 : "$bons gagnants / $nb" au lieu de "$bons/$nb"
                  Text('$bons / $nb',
                    style: TextStyle(
                      color: col,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    )),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 44,
                    child: Text('${(tx * 100).toStringAsFixed(0)}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: col, fontSize: 14, fontWeight: FontWeight.bold)),
                  ),
                ]),
                const SizedBox(height: 3),
                // ★ v10.57 — Sous-libellé "N gagnants / M pronostics"
                Text(
                  '$bons gagnant${bons > 1 ? 's' : ''} sur $nb pronostic${nb > 1 ? 's' : ''}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.38), fontSize: 12),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: tx.clamp(0.0, 1.0),
                    minHeight: 5,
                    backgroundColor: Colors.white.withValues(alpha: 0.07),
                    valueColor: AlwaysStoppedAnimation<Color>(col),
                  ),
                ),
              ]),
            );
          }).toList(),
        ),
      ),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════
  //  TENDANCE JOUR PAR JOUR — sparkline textuel
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildTendanceJours(Map<int, DonneeJourCalendrier> data) {
    final joursActifs = data.entries
        .where((e) => e.value.nbCourses > 0)
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (joursActifs.length < 3) return const SizedBox();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      iaSectionTitle('📈 Tendance du mois'),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _cCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Column(children: [
          // Sparkline des taux jour par jour
          SizedBox(
            height: 60,
            child: CustomPaint(
              size: const Size(double.infinity, 60),
              painter: _SparklinePainter(
                values: joursActifs.map((e) => e.value.taux).toList(),
                color:  _cGreen,
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Étiquettes jours
          Row(
            children: joursActifs.take(joursActifs.length <= 7 ? joursActifs.length : 7).map((e) {
              return Expanded(
                child: Text(
                  '${e.key}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 9),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          // Tendance calculée
          _buildTendanceTexte(joursActifs),
        ]),
      ),
    ]);
  }

  Widget _buildTendanceTexte(
    List<MapEntry<int, DonneeJourCalendrier>> jours,
  ) {
    if (jours.length < 4) return const SizedBox();

    final moitie   = jours.length ~/ 2;
    final premiere = jours.take(moitie).map((e) => e.value.taux).toList();
    final seconde  = jours.skip(moitie).map((e) => e.value.taux).toList();
    final moy1     = premiere.reduce((a, b) => a + b) / premiere.length;
    final moy2     = seconde.reduce((a, b) => a + b) / seconde.length;
    final delta    = moy2 - moy1;

    String txt; Color col; String emoji;
    if (delta > 0.10) {
      txt = 'En nette progression (+${(delta * 100).toStringAsFixed(0)}%)';
      col = _cGreen; emoji = '📈';
    } else if (delta > 0.03) {
      txt = 'Légère amélioration (+${(delta * 100).toStringAsFixed(0)}%)';
      col = _cYellow; emoji = '↗️';
    } else if (delta < -0.10) {
      txt = 'Régression notable (${(delta * 100).toStringAsFixed(0)}%)';
      col = _cRed; emoji = '📉';
    } else if (delta < -0.03) {
      txt = 'Légère baisse (${(delta * 100).toStringAsFixed(0)}%)';
      col = _cOrange; emoji = '↘️';
    } else {
      txt = 'Performance stable (±${(delta.abs() * 100).toStringAsFixed(0)}%)';
      col = Colors.white54; emoji = '→';
    }

    return Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 16)),
      const SizedBox(width: 8),
      Expanded(child: Text(txt, style: TextStyle(color: col, fontSize: 14))),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════
  //  VUE ANNUELLE — grille 12 mois miniaturisée
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildVueAnnuelle() {
    final annee    = _moisRef.year;
    final moisMax  = _moisRef.year == DateTime.now().year
        ? DateTime.now().month
        : 12;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      iaSectionTitle('📆 Vue annuelle — $annee'),
      const SizedBox(height: 10),
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.05,
        children: List.generate(12, (i) {
          final mois = i + 1;
          if (mois > moisMax) return _miniMoisVide(mois);
          final data = IaMemoryService.instance.donneesCalendrierJour(annee, mois);
          return _miniMois(annee, mois, data);
        }),
      ),
    ]);
  }

  Widget _miniMois(int annee, int mois, Map<int, DonneeJourCalendrier> data) {
    int tc = 0, tb = 0;
    for (final d in data.values) { tc += d.nbCourses; tb += d.nbBons; }
    final taux   = tc > 0 ? tb / tc : 0.0;
    final col    = tc == 0 ? Colors.white12
                 : taux >= 0.30 ? _cGreen
                 : taux >= 0.25 ? _cYellow
                 : taux >= 0.20 ? _cOrange
                 : _cRed;
    final estSel = annee == _moisRef.year && mois == _moisRef.month
                   && _modeTabs.index == 0;

    return GestureDetector(
      onTap: () {
        setState(() {
          _moisRef = DateTime(annee, mois, 1);
          _modeTabs.animateTo(0);
        });
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: estSel ? _cGold.withValues(alpha: 0.1) : _cCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: estSel ? _cGold.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.07),
            width: estSel ? 1.5 : 0.8,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_nomsMois[mois].substring(0, 3),
              style: TextStyle(
                color: estSel ? _cGold : Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              )),
            const SizedBox(height: 6),
            Text(tc == 0 ? '—' : '${(taux * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: col,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              )),
            const SizedBox(height: 2),
            Text(tc == 0 ? 'Aucune' : '$tb/$tc',
              style: TextStyle(color: col.withValues(alpha: 0.7), fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _miniMoisVide(int mois) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _cGrey.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(_nomsMois[mois].substring(0, 3),
            style: const TextStyle(color: Colors.white24, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('—', style: TextStyle(color: Colors.white12, fontSize: 18)),
        ],
      ),
    );
  }

  // ★ v10.31 : _buildModeSelector, _buildLegende, _legendeRow, _seuilField
  //            supprimés (unused_element). L'édition des seuils reste accessible
  //            via _SeuilsParamsSheet (bouton ⚙️ dans le header).

  // ══════════════════════════════════════════════════════════════════════
  //  DIALOG DÉTAIL JOUR — tap sur une case
  // ══════════════════════════════════════════════════════════════════════
  void _ouvrirDetailJour(
    BuildContext ctx,
    DonneeJourCalendrier dd,
    DateTime moisRef,
  ) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DetailJourSheet(dd: dd, moisRef: moisRef),
    );
  }

  // ── Utilitaires ───────────────────────────────────────────────────────
  Widget _emptyState(String msg) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(msg,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white38, fontSize: 14)),
    );
  }

  Widget _statBox(String value, String label, Color color) {
    return Column(children: [
      Text(value,
        style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.bold)),
      const SizedBox(height: 2),
      Text(label,
        style: const TextStyle(color: Colors.white38, fontSize: 14)),
    ]);
  }

  Widget _divV() => Container(
    width: 1, height: 30,
    color: Colors.white.withValues(alpha: 0.07),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
//  SPARKLINE PAINTER
// ═══════════════════════════════════════════════════════════════════════════
class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color        color;

  const _SparklinePainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final maxV = values.reduce((a, b) => a > b ? a : b).clamp(0.01, 1.0);
    final step = size.width / (values.length - 1);

    // Zone de remplissage (gradient)
    final fillPath = Path();
    fillPath.moveTo(0, size.height);
    for (int i = 0; i < values.length; i++) {
      final x = i * step;
      final y = size.height - (values[i] / maxV) * size.height * 0.85;
      if (i == 0) fillPath.lineTo(x, y);
      else        fillPath.lineTo(x, y);
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0.02)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // Ligne principale
    final linePath = Path();
    final linePaint = Paint()
      ..color       = color
      ..strokeWidth = 2.0
      ..style       = PaintingStyle.stroke
      ..strokeCap   = StrokeCap.round
      ..strokeJoin  = StrokeJoin.round;

    for (int i = 0; i < values.length; i++) {
      final x = i * step;
      final y = size.height - (values[i] / maxV) * size.height * 0.85;
      if (i == 0) linePath.moveTo(x, y);
      else        linePath.lineTo(x, y);
    }
    canvas.drawPath(linePath, linePaint);

    // Points sur la ligne
    final dotPaint = Paint()..color = color..style = PaintingStyle.fill;
    for (int i = 0; i < values.length; i++) {
      final x = i * step;
      final y = size.height - (values[i] / maxV) * size.height * 0.85;
      canvas.drawCircle(Offset(x, y), 3.0, dotPaint);
    }

    // Ligne de référence à 40%
    final refY    = size.height - (0.40 / maxV) * size.height * 0.85;
    if (refY > 0 && refY < size.height) {
      final refPaint = Paint()
        ..color       = _cGreen.withValues(alpha: 0.25)
        ..strokeWidth = 1.0
        ..style       = PaintingStyle.stroke;
      canvas.drawLine(Offset(0, refY), Offset(size.width, refY), refPaint);
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      !listEquals(old.values, values) || old.color != color;
}

// ═══════════════════════════════════════════════════════════════════════════
//  BOTTOM SHEET — Détail d'une journée
// ═══════════════════════════════════════════════════════════════════════════
class _DetailJourSheet extends StatelessWidget {
  final DonneeJourCalendrier dd;
  final DateTime             moisRef;

  const _DetailJourSheet({required this.dd, required this.moisRef});

  static const _nomsMois = [
    '', 'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
    'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre',
  ];

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        '${dd.jour} ${_nomsMois[moisRef.month]} ${moisRef.year}';
    final taux      = dd.taux;
    final tauxPct   = '${(taux * 100).toStringAsFixed(0)}%';
    final palier    = dd.palier;
    final bons      = dd.pronostics
        .where((p) => IaMemoryService.instance
            .estBonConseil(p, p.typePariConseille ?? ''))
        .toList();

    // ★ v10.55 — Récupérer les premiums enregistrés ce jour-là
    // pour afficher le badge doré sur les cartes correspondantes.
    final premiumsDuJour = IaMemoryService.instance
        .premiumsPourDate(moisRef.year, moisRef.month, dd.jour);

    // ★ v10.60 — Date de la bulle calendrier = référence historique exacte pour le streak.
    // Ne PAS utiliser DateTime.now() : les anciennes bulles doivent garder leur phrase.
    final dateRef = DateTime(moisRef.year, moisRef.month, dd.jour);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize:     0.4,
      maxChildSize:     0.92,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: _cCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // En-tête
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            child: Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: palier.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: palier.border),
                ),
                child: Center(
                  child: Text(palier.emoji,
                    style: TextStyle(color: palier.fg, fontSize: 20)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(dateLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,        // ★ v10.30 : agrandi
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  )),
                const SizedBox(height: 4),
                Text('${dd.nbBons}/${dd.nbCourses} bons conseils · $tauxPct',
                  style: const TextStyle(color: Colors.white54, fontSize: 14)),
                const SizedBox(height: 3),
                Text(palier.label,
                  style: TextStyle(color: palier.fg, fontSize: 14,
                      fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(_descriptifTaux(taux, dd.palier),
                  style: const TextStyle(color: Colors.white38, fontSize: 14)),
              ])),
            ]),
          ),

          const Divider(color: Colors.white12, height: 1),

          // Liste des pronostics
          Expanded(
            child: ListView(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
              children: [

                // ★ v10.59 — Pas de bandeau streak dans cette version (rollback visuel).
                if (bons.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Aucun pronostic gagnant ce jour',
                        style: TextStyle(color: Colors.white38, fontSize: 14),
                      ),
                    ),
                  )
                else ...[
                  // ★ v10.27 : Gagnants uniquement — perdants masqués (données conservées)
                  Text('✅ Pronostics réussis (${bons.length})',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    )),
                  const SizedBox(height: 10),
                  ...bons.map((p) => _buildPronosticCard(context, p, premiumsDuJour, dateRef)),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ★ v10.59 — _buildStreakBadge supprimé (rollback visuel v10.57).
  // Les données streak restent calculées dans IaMemoryService mais ne s'affichent pas ici.

  /// ★ v10.26 : Descriptif dynamique du taux affiché dans le BottomSheet
  static String _descriptifTaux(double taux, PalierCalendrier palier) {
    if (palier == PalierCalendrier.or)
      return 'Tiercé, Quarté+ ou Quinté+ réussi — exploit rare et précieux !';
    if (palier == PalierCalendrier.gris)
      return 'Aucune course analysée ce jour.';
    final pct = (taux * 100).toStringAsFixed(0);
    if (taux >= 0.30)
      return '$pct% de pronostics corrects — au-dessus de la norme (≥30%).';
    if (taux >= 0.25)
      return '$pct% de pronostics corrects — dans la norme (25–29%).';
    if (taux >= 0.20)
      return '$pct% de pronostics corrects — en dessous de la norme (20–24%). L\'IA continue d\'apprendre.';
    return '$pct% de pronostics corrects — journée difficile (<20%).';
  }

  // ★ v10.27 : Card plus grande, titre blanc (jamais vert sur fond vert), contraste renforcé
  // ★ v10.55 : badge doré ⭐ Premium si ce prono correspond à un widget premium gagnant strict.
  // ★ v10.60 : phrase dynamique série — calcul streak sur dateRef (date de la bulle, pas aujourd'hui)
  Widget _buildPronosticCard(
    BuildContext context,
    IaPronostic p,
    List<PremiumPronosticDuJour> premiumsDuJour,
    DateTime dateRef,
  ) {
    final type   = p.typePariConseille ?? 'Inconnu';
    final favNom = p.favoriIaNom ?? '?';
    final rang   = p.rangFavoriIaDansArrivee;
    final score  = p.scorePerformance;
    final conf   = p.confiancePredite;
    final hip    = p.hippodrome;
    final disc   = p.discipline;
    final topIA  = p.topNIA.take(3).map((e) => 'N°$e').join(' · ');
    final arriv  = p.arriveeReelle != null
        ? p.arriveeReelle!.take(3).map((e) => 'N°$e').join('-')
        : '—';

    // ★ v10.55 — Détection premium gagnant strict (délègue à IaMemoryService)
    final isPremium = estPremiumGagnantPourCarte(
      prono: p,
      premiumsDuJour: premiumsDuJour,
    );
    final sourceP = isPremium
        ? sourcePremiumPourCarte(prono: p, premiumsDuJour: premiumsDuJour)
        : null;

    // ★ v10.60/v10.61 — Streak calculé à la date de la bulle (historique exact).
    // Utilise le helper commun premium_streak_ui.dart (même source que Home/BestBet).
    final PremiumStreak? streakCarte = (isPremium && sourceP != null)
        ? streakPourSource(sourceWidget: sourceP, dateReference: dateRef)
        : null;

    // ★ v10.59 — Restauration exacte du design screenshot :
    //   fond doré translucide 0x1AFFD700, bordure dorée 2.2px,
    //   badge pill "⭐ Premium — Plus Sûr" via _labelSourcePremium().
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isPremium
            ? const Color(0x1AFFD700)
            : const Color(0xFF142030),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isPremium
              ? const Color(0xFFFFD700)
              : const Color(0xFF26384D),
          width: isPremium ? 2.2 : 1.2,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ★ v10.59 — Badge premium pill exactement comme le screenshot
        // ★ v10.60 — Phrase série sous le badge (streak ≥ 2, date historique exacte)
        if (isPremium) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0x26FFD700),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(0x99FFD700),
                width: 1,
              ),
            ),
            child: Text(
              '⭐ Premium — ${_labelSourcePremium(sourceP)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          // ★ v10.61 — Phrase série via helper commun (même rendu que Home/BestBet)
          buildPremiumStreakPhrase(streak: streakCarte),
          const SizedBox(height: 14),
        ],
        // Titre course — blanc pour lisibilité (jamais vert sur fond vert)
        Row(children: [
          Expanded(
            child: Text(
              p.nomCourse.isEmpty ? 'Course' : p.nomCourse,
              style: const TextStyle(
                color: Colors.white,          // ★ blanc, pas _cGreen
                fontSize: 15,                 // ★ +2 vs ancien 13
                fontWeight: FontWeight.bold,
                letterSpacing: 0.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Badge score — couleur dynamique selon performance
          // ★ v10.35 : Badge score avec distinction réussite complète vs partielle
          Builder(builder: (ctx) {
            final sc   = score ?? 0;
            final rang = p.rangFavoriIaDansArrivee;
            final type = p.typePariConseille ?? '';
            // Gagnant+Placé : distinguer rang==1 (complet) de rang 2-3 (partiel/Placé seul)
            final estPartiel = type == 'Gagnant+Placé' && rang != null && rang > 1;
            final badgeEmoji = estPartiel ? '🎯' : '✅'; // 🎯 = Placé seul, ✅ = Gagnant
            final badgeColor = sc >= 70
                ? const Color(0xFFFFD700)
                : sc >= 50
                    ? const Color(0xFF7C4DFF)
                    : Colors.white54;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: badgeColor.withValues(alpha: 0.45)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(badgeEmoji, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 4),
                    if (score != null)
                      Text('${sc.toStringAsFixed(0)}',
                        style: TextStyle(
                          color: badgeColor,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        )),
                  ]),
                ),
                if (estPartiel)
                  const Text('Placé seul',
                    style: TextStyle(color: Colors.white38, fontSize: 14)),
              ],
            );
          }),
        ]),
        const SizedBox(height: 5),

        // Hippodrome + discipline — texte plus lisible
        if (hip.isNotEmpty || disc.isNotEmpty)
          Text(
            '$hip${disc.isNotEmpty ? ' · $disc' : ''}',
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),

        const SizedBox(height: 10),

        // Type de pari cliquable + favori
        Row(children: [
          // ★ v10.30 : tap sur le type de pari → explication
          GestureDetector(
            onTap: () => _ouvrirDescriptifTypePari(
              context, type,
              numeros: p.topNIA.take(
                type == 'Quinté+' ? 5 : type == 'Quarté+' ? 4 :
                type == 'Tiercé'  ? 3 : type.contains('Couplé') ? 2 : 1
              ).toList(),
              nomFavori: p.favoriIaNom,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF7C4DFF).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: const Color(0xFF7C4DFF).withValues(alpha: 0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(type,
                  style: const TextStyle(
                    color: Color(0xFFB39DDB),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  )),
                const SizedBox(width: 4),
                const Icon(Icons.info_outline,
                    color: Color(0xFF7C4DFF), size: 14),
              ]),
            ),
          ),
          const SizedBox(width: 6),
          _pill('Favori : $favNom',
              Colors.white.withValues(alpha: 0.07), Colors.white54),
        ]),
        const SizedBox(height: 10),

        // IA vs Réel — section bien séparée
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('IA prévoyait',
                style: TextStyle(color: Colors.white38, fontSize: 14)),
              const SizedBox(height: 3),
              Text(topIA.isEmpty ? '—' : topIA,
                style: const TextStyle(
                  color: Colors.white,          // ★ blanc pour lisibilité
                  fontSize: 14,                 // ★ +2
                  fontWeight: FontWeight.w600,
                )),
            ])),
            Container(width: 1, height: 36, color: Colors.white12),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Arrivée réelle',
                style: TextStyle(color: Colors.white38, fontSize: 14)),
              const SizedBox(height: 3),
              // ★ v10.30 : Arrivée réelle en doré — distinct de la prévision IA (blanc)
              Text(arriv,
                style: const TextStyle(
                  color: Color(0xFFFFD700), // doré = résultat réel PMU
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                )),
            ])),
            if (rang != null) ...[
              const SizedBox(width: 8),
              Column(children: [
                const Text('Rang',
                  style: TextStyle(color: Colors.white38, fontSize: 14)),
                const SizedBox(height: 3),
                Text('#$rang',
                  style: TextStyle(
                    color: rang == 1 ? _cGold : rang <= 3 ? _cGreen : Colors.white60,
                    fontSize: 16,               // ★ +2
                    fontWeight: FontWeight.bold,
                  )),
              ]),
            ],
          ]),
        ),

        // Confiance si disponible
        // ★ v10.36 fix : confiancePredite est en 0–100 (pas 0–1).
        // L'ancien "conf * 100" transformait 69.99 → 6999%. Supprimé.
        if (conf != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.psychology_outlined, color: Colors.white38, size: 14),
            const SizedBox(width: 5),
            const Text('Confiance : ',
              style: TextStyle(color: Colors.white38, fontSize: 14)),
            Text('${conf.clamp(0.0, 100.0).toStringAsFixed(0)}%',
              style: TextStyle(
                color: conf >= 75 ? _cGreen
                     : conf >= 55 ? _cYellow
                     : _cOrange,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              )),
          ]),
        ],
      ]),
    );
  }

  // ★ v10.59 — Helper local (identique à labelSourcePremium de premium_utils mais privé à ce widget)
  String _labelSourcePremium(String? source) {
    switch (source) {
      case 'conseilJour':    return 'Conseil IA du jour';
      case 'meilleurPari':   return 'Meilleur Pari du jour';
      case 'topEquilibre':   return 'Top Équilibre';
      case 'plusSur':        return 'Plus Sûr';
      case 'plusRentable':   return 'Plus Rentable';
      default:               return 'Premium';
    }
  }

  Widget _pill(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: TextStyle(color: fg, fontSize: 14)),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  ★ v10.30 : Descriptif des types de paris
// ══════════════════════════════════════════════════════════════════════════════

void _ouvrirDescriptifTypePari(BuildContext context, String type,
    {List<String> numeros = const <String>[], String? nomFavori}) {
  showModalBottomSheet(
    context:            context,
    backgroundColor:    Colors.transparent,
    isScrollControlled: true,
    builder: (_) => TypePariDescriptifSheet( // ★ v10.30 : source unique
        type: type, numeros: numeros, nomFavori: nomFavori),
  );
}


// ══════════════════════════════════════════════════════════════════════════════
//  ★ v10.33 : Sheet paramétrage d'UN seul palier — ouvert depuis la légende
// ══════════════════════════════════════════════════════════════════════════════
class _SeuilUniquSheet extends StatefulWidget {
  final PalierCalendrier palier;
  final double seuilVert, seuilJaune, seuilOrange;
  final void Function(double v, double j, double o) onApply;

  const _SeuilUniquSheet({
    required this.palier,
    required this.seuilVert,
    required this.seuilJaune,
    required this.seuilOrange,
    required this.onApply,
  });

  @override
  State<_SeuilUniquSheet> createState() => _SeuilUniquSheetState();
}

class _SeuilUniquSheetState extends State<_SeuilUniquSheet> {
  late TextEditingController _ctrl;
  String? _erreur;

  // Valeurs courantes des 3 seuils (pour recalculer les bornes)
  late double _v, _j, _o;

  @override
  void initState() {
    super.initState();
    _v = widget.seuilVert;
    _j = widget.seuilJaune;
    _o = widget.seuilOrange;
    // Valeur initiale = seuil du palier concerné
    final initial = _valeurCourante();
    _ctrl = TextEditingController(text: initial.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double _valeurCourante() {
    switch (widget.palier) {
      case PalierCalendrier.vert:   return _v;
      case PalierCalendrier.jaune:  return _j;
      case PalierCalendrier.orange: return _o;
      default: return _v;
    }
  }

  // Infos du palier sélectionné
  Color get _color {
    switch (widget.palier) {
      case PalierCalendrier.vert:   return const Color(0xFF4CAF7D);
      case PalierCalendrier.jaune:  return const Color(0xFFFFD700);
      case PalierCalendrier.orange: return const Color(0xFFFF7043);
      default: return Colors.white54;
    }
  }

  String get _label {
    switch (widget.palier) {
      case PalierCalendrier.vert:   return '✅ Bonne journée';
      case PalierCalendrier.jaune:  return '📊 Dans la norme';
      case PalierCalendrier.orange: return '⚠️ En dessous';
      default: return '';
    }
  }

  String get _description {
    switch (widget.palier) {
      case PalierCalendrier.vert:
        return '🟢 VERT  : taux ≥ valeur saisie\n'
            '🟡 JAUNE : taux entre ${_j.toStringAsFixed(0)}% et (valeur saisie − 1)%\n'
            '🟠 ORANGE: taux entre ${_o.toStringAsFixed(0)}% et ${(_j - 1).toStringAsFixed(0)}%\n'
            '🔴 ROUGE : taux < ${_o.toStringAsFixed(0)}%\n\n'
            'Valeur autorisée : entre ${(_j + 1).toStringAsFixed(0)}% et 60%';
      case PalierCalendrier.jaune:
        return '🟢 VERT  : taux ≥ ${_v.toStringAsFixed(0)}%\n'
            '🟡 JAUNE : taux entre valeur saisie et ${(_v - 1).toStringAsFixed(0)}%\n'
            '🟠 ORANGE: taux entre ${_o.toStringAsFixed(0)}% et (valeur saisie − 1)%\n'
            '🔴 ROUGE : taux < ${_o.toStringAsFixed(0)}%\n\n'
            'Valeur autorisée : entre ${(_o + 1).toStringAsFixed(0)}% et ${(_v - 1).toStringAsFixed(0)}%';
      case PalierCalendrier.orange:
        return '🟢 VERT  : taux ≥ ${_v.toStringAsFixed(0)}%\n'
            '🟡 JAUNE : taux entre ${_j.toStringAsFixed(0)}% et ${(_v - 1).toStringAsFixed(0)}%\n'
            '🟠 ORANGE: taux entre valeur saisie et ${(_j - 1).toStringAsFixed(0)}%\n'
            '🔴 ROUGE : taux < valeur saisie\n\n'
            'Valeur autorisée : entre 5% et ${(_j - 1).toStringAsFixed(0)}%';
      default: return '';
    }
  }

  // Bornes selon le palier
  double get _min {
    switch (widget.palier) {
      case PalierCalendrier.vert:   return _j + 1;
      case PalierCalendrier.jaune:  return _o + 1;
      case PalierCalendrier.orange: return 5;
      default: return 5;
    }
  }

  double get _max {
    switch (widget.palier) {
      case PalierCalendrier.vert:   return 60;
      case PalierCalendrier.jaune:  return _v - 1;
      case PalierCalendrier.orange: return _j - 1;
      default: return 60;
    }
  }

  void _valider() {
    final txt = _ctrl.text.trim().replaceAll('%', '');
    final val = double.tryParse(txt);
    if (val == null) {
      setState(() => _erreur = 'Entrez un nombre valide (ex: 28)');
      return;
    }
    final rounded = val.roundToDouble();
    if (rounded < _min || rounded > _max) {
      setState(() => _erreur = 'Valeur entre ${_min.toStringAsFixed(0)} et ${_max.toStringAsFixed(0)}%');
      return;
    }
    // Appliquer selon le palier
    double nv = _v, nj = _j, no = _o;
    switch (widget.palier) {
      case PalierCalendrier.vert:   nv = rounded; break;
      case PalierCalendrier.jaune:  nj = rounded; break;
      case PalierCalendrier.orange: no = rounded; break;
      default: break;
    }
    widget.onApply(nv, nj, no);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        decoration: const BoxDecoration(
          color: Color(0xFF111F30),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Handle
          Center(child: Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2)),
          )),

          // En-tête palier
          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Center(child: Text(
                widget.palier == PalierCalendrier.vert   ? '✅' :
                widget.palier == PalierCalendrier.jaune  ? '📊' : '⚠️',
                style: const TextStyle(fontSize: 22),
              )),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_label, style: TextStyle(
                  color: color, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Modifier le seuil de déclenchement',
                style: const TextStyle(color: Colors.white38, fontSize: 14)),
            ])),
          ]),

          const SizedBox(height: 16),
          Text(_description,
            style: const TextStyle(
                color: Colors.white54, fontSize: 14, height: 1.5)),

          const SizedBox(height: 20),

          // Champ de saisie
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: false),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: color, fontSize: 28, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  suffix: Text('%', style: TextStyle(
                      color: color.withValues(alpha: 0.7), fontSize: 20)),
                  filled: true,
                  fillColor: color.withValues(alpha: 0.08),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: color.withValues(alpha: 0.4)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: color.withValues(alpha: 0.35)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: color, width: 1.8),
                  ),
                  hintText: _valeurCourante().toStringAsFixed(0),
                  hintStyle: TextStyle(color: color.withValues(alpha: 0.3)),
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 16, horizontal: 12),
                  errorText: null,
                ),
                onSubmitted: (_) => _valider(),
              ),
            ),
          ]),

          if (_erreur != null) ...[  
            const SizedBox(height: 8),
            Text(_erreur!, style: const TextStyle(
                color: Color(0xFFEF5350), fontSize: 14)),
          ],

          const SizedBox(height: 8),
          Text(
            'Plage autorisée : ${_min.toStringAsFixed(0)}% – ${_max.toStringAsFixed(0)}%',
            style: const TextStyle(color: Colors.white24, fontSize: 14),
          ),

          const SizedBox(height: 24),

          // Bouton Valider
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              onPressed: _valider,
              child: const Text('Valider',
                style: TextStyle(color: Colors.white,
                    fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ),
    );
  }
}
