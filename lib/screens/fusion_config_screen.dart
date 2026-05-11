import 'package:flutter/material.dart';
import '../services/best_bet_engine.dart';
import '../services/fusion_config_service.dart';

/// ═════════════════════════════════════════════════════════════════════════════
/// Écran de configuration du moteur de fusion "Top Équilibre"
///
/// Permet de :
///   - Ajuster les poids des 3 critères (confiance, gain, risque)
///   - Définir le seuil minimal de confiance
///   - Appliquer un preset prédéfini (Conseillé, Très sûr, Chasseur de gains)
///   - Réinitialiser aux valeurs conseillées
/// ═════════════════════════════════════════════════════════════════════════════

class FusionConfigScreen extends StatefulWidget {
  final FusionConfig initialConfig;
  final ValueChanged<FusionConfig> onConfigChanged;

  const FusionConfigScreen({
    super.key,
    required this.initialConfig,
    required this.onConfigChanged,
  });

  @override
  State<FusionConfigScreen> createState() => _FusionConfigScreenState();
}

class _FusionConfigScreenState extends State<FusionConfigScreen> {
  late double _confiance;
  late double _gain;
  late double _risque;
  late double _seuil;
  bool _saved = false;

  static const _kGreen  = Color(0xFF4CAF7D);
  static const _kOrange = Color(0xFFFF9800);
  static const _kBlue   = Color(0xFF64B5F6);
  static const _kGold   = Color(0xFFFFD700);
  static const _kBg     = Color(0xFF0D2818);
  static const _kCard   = Color(0xFF0A1F12);
  static const _kBorder = Color(0xFF1A4731);

  @override
  void initState() {
    super.initState();
    _confiance = widget.initialConfig.poidsConfiance;
    _gain      = widget.initialConfig.poidsGain;
    _risque    = widget.initialConfig.poidsRisque;
    _seuil     = widget.initialConfig.seuilConfianceMin.toDouble();
  }

  // Total doit rester à 1.0 — ajuster automatiquement les autres
  void _onConfianceChanged(double val) {
    setState(() {
      _confiance = val;
      final reste = (1.0 - val).clamp(0.0, 1.0);
      // Redistribuer proportionnellement gain et risque
      final total23 = _gain + _risque;
      if (total23 > 0) {
        _gain   = (_gain   / total23 * reste).clamp(0.05, 0.90);
        _risque = (reste - _gain).clamp(0.05, 0.50);
      } else {
        _gain   = (reste * 0.71).clamp(0.05, 0.90);
        _risque = (reste * 0.29).clamp(0.05, 0.50);
      }
      _saved = false;
    });
  }

  void _onGainChanged(double val) {
    setState(() {
      _gain   = val;
      _risque = (1.0 - _confiance - val).clamp(0.05, 0.50);
      _saved  = false;
    });
  }

  void _applyPreset(FusionConfig preset) {
    setState(() {
      _confiance = preset.poidsConfiance;
      _gain      = preset.poidsGain;
      _risque    = preset.poidsRisque;
      _seuil     = preset.seuilConfianceMin.toDouble();
      _saved     = false;
    });
  }

  FusionConfig get _currentConfig => FusionConfig(
    poidsConfiance:    double.parse(_confiance.toStringAsFixed(2)),
    poidsGain:         double.parse(_gain.toStringAsFixed(2)),
    poidsRisque:       double.parse(_risque.toStringAsFixed(2)),
    seuilConfianceMin: _seuil.round(),
  );

  bool get _isConseillee => FusionConfigService.estConfigConseillee(_currentConfig);

  Future<void> _save() async {
    final config = _currentConfig;
    await FusionConfigService.save(config);
    widget.onConfigChanged(config);
    setState(() => _saved = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(children: [
            Icon(Icons.check_circle, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('Configuration sauvegardée et appliquée !'),
          ]),
          backgroundColor: const Color(0xFF1B5E20),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _reset() async {
    await FusionConfigService.reset();
    _applyPreset(FusionConfig.conseillee);
    widget.onConfigChanged(FusionConfig.conseillee);
    setState(() => _saved = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(children: [
            Icon(Icons.refresh, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('Configuration réinitialisée (valeurs conseillées)'),
          ]),
          backgroundColor: const Color(0xFF1A4731),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kCard,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('⚙️ Paramètres du moteur IA',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            Text('Mode Top Équilibre',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
          ],
        ),
        actions: [
          if (!_isConseillee)
            TextButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.restore, color: _kOrange, size: 16),
              label: const Text('Conseillé', style: TextStyle(color: _kOrange, fontSize: 14)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── Explication principale ─────────────────────────────────────────
          _InfoBanner(
            icon: Icons.info_outline,
            color: _kBlue,
            title: 'Comment fonctionne le mode Top Équilibre ?',
            body: 'L\'IA analyse chaque course selon 3 critères et calcule un '
                  'score pondéré. Plus le poids d\'un critère est élevé, plus '
                  'il influence le classement. La confiance IA est le critère '
                  'le plus fiable pour prédire une victoire.',
          ),

          const SizedBox(height: 16),

          // ── Presets rapides ────────────────────────────────────────────────
          _SectionHeader(icon: Icons.speed, label: 'Profils prédéfinis'),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _PresetCard(
              title: '🌟 Conseillé',
              subtitle: 'Meilleur ratio\ngagner/perdre',
              highlight: true,
              selected: _isConseillee,
              config: FusionConfig.conseillee,
              onTap: () => _applyPreset(FusionConfig.conseillee),
            )),
            const SizedBox(width: 8),
            Expanded(child: _PresetCard(
              title: '🛡️ Très sûr',
              subtitle: 'Priorité max\nsécurité',
              selected: !_isConseillee &&
                  (_confiance - FusionConfig.tresSure.poidsConfiance).abs() < 0.01,
              config: FusionConfig.tresSure,
              onTap: () => _applyPreset(FusionConfig.tresSure),
            )),
            const SizedBox(width: 8),
            Expanded(child: _PresetCard(
              title: '💰 Gains',
              subtitle: 'Plus de gains\npotentiels',
              selected: !_isConseillee &&
                  (_confiance - FusionConfig.chasseurGains.poidsConfiance).abs() < 0.01,
              config: FusionConfig.chasseurGains,
              onTap: () => _applyPreset(FusionConfig.chasseurGains),
            )),
          ]),

          const SizedBox(height: 20),

          // ── Aperçu visuel du score actuel ──────────────────────────────────
          _ScorePreview(
            confiance: _confiance,
            gain: _gain,
            risque: _risque,
          ),

          const SizedBox(height: 20),

          // ── Curseur Confiance ──────────────────────────────────────────────
          _SectionHeader(icon: Icons.verified_user, label: 'Critère 1 — Confiance IA'),
          const SizedBox(height: 6),
          _CritereCard(
            color: _kGreen,
            icon: Icons.verified,
            title: 'Confiance IA',
            poids: _confiance,
            description: 'Priorité recommandée : 65–80%\n'
                'La confiance IA mesure à quel point le pronostic est solide. '
                'C\'est LE critère le plus important : mieux vaut être sûr de gagner '
                'un petit gain que de risquer de perdre pour un grand gain hypothétique.',
            conseil: 'Recommandé entre 60% et 75%',
            onChanged: _onConfianceChanged,
            min: 0.30,
            max: 0.90,
          ),

          const SizedBox(height: 14),

          // ── Curseur Gain ───────────────────────────────────────────────────
          _SectionHeader(icon: Icons.attach_money, label: 'Critère 2 — Qualité du gain'),
          const SizedBox(height: 6),
          _CritereCard(
            color: _kOrange,
            icon: Icons.trending_up,
            title: 'Qualité du gain',
            poids: _gain,
            description: 'Ce n\'est pas le gain brut mais le gain AJUSTÉ AU RISQUE. '
                'Un gain de 15€ à cote 1.8 vaut mieux qu\'un gain de 200€ à cote 50. '
                'Ce critère récompense les paris "valeur" — bonne cote sans trop de risque.',
            conseil: 'Recommandé entre 15% et 30%',
            onChanged: _onGainChanged,
            min: 0.05,
            max: 0.60,
          ),

          const SizedBox(height: 14),

          // ── Critère Risque (lecture seule, calculé) ────────────────────────
          _SectionHeader(icon: Icons.analytics, label: 'Critère 3 — Rapport statistique'),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _kBlue.withValues(alpha: 0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.calculate, color: _kBlue, size: 16),
                const SizedBox(width: 8),
                const Text('Valeur attendue statistique',
                    style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _kBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kBlue.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    '${(_risque * 100).round()}%',
                    style: const TextStyle(color: _kBlue, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                'Calculé automatiquement : ${(_risque * 100).round()}% = reste après Confiance (${(_confiance * 100).round()}%) + Gain (${(_gain * 100).round()}%)\n'
                'Ce critère mesure mathématiquement si le pari a une valeur positive : '
                '(probabilité × gain potentiel) − (1-probabilité × mise). '
                'Il affine la sélection sans trop peser sur le classement final.',
                style: const TextStyle(color: Colors.white38, fontSize: 14, height: 1.5),
              ),
            ]),
          ),

          const SizedBox(height: 20),

          // ── Seuil minimal de confiance ─────────────────────────────────────
          _SectionHeader(icon: Icons.filter_alt, label: 'Filtre — Seuil de confiance minimum'),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _kGold.withValues(alpha: 0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.block, color: _kGold, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Exclure les cours sous ${_seuil.round()}% de confiance',
                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _kGold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kGold.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    '≥ ${_seuil.round()}%',
                    style: const TextStyle(color: _kGold, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                'Les courses sous ce seuil n\'apparaissent PAS dans le mode "Top Équilibre". '
                'Elles restent visibles dans "Plus Sûr" et "Plus Rentable".',
                style: const TextStyle(color: Colors.white38, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 10),
              Slider(
                value: _seuil,
                min: 28,
                max: 70,
                divisions: 42,
                activeColor: _kGold,
                inactiveColor: _kBorder,
                label: '≥ ${_seuil.round()}%',
                onChanged: (v) => setState(() { _seuil = v; _saved = false; }),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('28% — Permissif', style: TextStyle(color: Colors.white24, fontSize: 14)),
                  Text('42% — Conseillé ★', style: TextStyle(color: _kGold, fontSize: 14, fontWeight: FontWeight.bold)),
                  Text('70% — Strict', style: TextStyle(color: Colors.white24, fontSize: 14)),
                ],
              ),
            ]),
          ),

          const SizedBox(height: 24),

          // ── Bouton Sauvegarder ─────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _save,
              icon: Icon(_saved ? Icons.check : Icons.save, color: Colors.white),
              label: Text(
                _saved ? 'Configuration appliquée !' : 'Sauvegarder et appliquer',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _saved ? const Color(0xFF2E7D32) : _kGreen,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 4,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ── Bouton Reset ───────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.restore, color: _kOrange, size: 16),
              label: const Text(
                'Rétablir la configuration conseillée ★',
                style: TextStyle(color: _kOrange, fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _kOrange, width: 1),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),

          const SizedBox(height: 30),

          // ── Exemple concret de simulation ──────────────────────────────────
          _ConcreteExampleCard(
            confiance: _confiance,
            gain: _gain,
            risque: _risque,
          ),

          const SizedBox(height: 16),

          // ── Explication des presets ────────────────────────────────────────
          _InfoBanner(
            icon: Icons.lightbulb_outline,
            color: _kGold,
            title: 'Pourquoi la configuration conseillée ?',
            body: 'Confiance 65% + Gain 25% + Statistique 10%\n\n'
                  '• 65% confiance : C\'est le meilleur prédicteur de victoire. '
                  'L\'IA analyse cote, historique, forme récente et gains de carrière.\n\n'
                  '• 25% qualité du gain : On préfère un gain raisonnable très probable '
                  'à un gros gain improbable.\n\n'
                  '• 10% statistique : La valeur attendue mathématique sert d\'arbitre '
                  'en cas d\'égalité entre deux courses.\n\n'
                  'Seuil 42% : On n\'affiche que des paris où l\'IA a au minimum '
                  'une conviction modérée — pas de pari "au hasard".',
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Widgets privés
// ══════════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: const Color(0xFF4CAF7D), size: 15),
      const SizedBox(width: 6),
      Text(label,
          style: const TextStyle(
              color: Colors.white60, fontSize: 14, fontWeight: FontWeight.bold,
              letterSpacing: 0.5)),
    ]);
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  const _InfoBanner({required this.icon, required this.color,
      required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 6),
          Expanded(
            child: Text(title,
                style: TextStyle(
                    color: color, fontSize: 14, fontWeight: FontWeight.bold)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(body, style: const TextStyle(color: Colors.white54, fontSize: 14, height: 1.5)),
      ]),
    );
  }
}

class _ScorePreview extends StatelessWidget {
  final double confiance;
  final double gain;
  final double risque;
  const _ScorePreview({required this.confiance, required this.gain, required this.risque});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1F12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Text('⚖️', style: TextStyle(fontSize: 14)),
          SizedBox(width: 6),
          Text('Formule de calcul actuelle',
              style: TextStyle(color: Color(0xFFFFD700), fontSize: 14, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 12),
        // Visualisation proportionnelle
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Row(children: [
            Flexible(
              flex: (confiance * 100).round(),
              child: Container(
                height: 20,
                color: const Color(0xFF4CAF7D),
                child: Center(child: Text(
                  '${(confiance * 100).round()}% Conf.',
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                )),
              ),
            ),
            Flexible(
              flex: (gain * 100).round(),
              child: Container(
                height: 20,
                color: const Color(0xFFFF9800),
                child: Center(child: Text(
                  '${(gain * 100).round()}% Gain',
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                )),
              ),
            ),
            Flexible(
              flex: (risque * 100).round(),
              child: Container(
                height: 20,
                color: const Color(0xFF64B5F6),
                child: Center(child: Text(
                  '${(risque * 100).round()}%',
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                )),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Text(
          'Score = ${(confiance * 100).round()}% × Confiance IA  +  ${(gain * 100).round()}% × Qualité gain  +  ${(risque * 100).round()}% × Statistique',
          style: const TextStyle(color: Colors.white38, fontSize: 13, fontStyle: FontStyle.italic),
        ),
      ]),
    );
  }
}

class _CritereCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final double poids;
  final String description;
  final String conseil;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;

  const _CritereCard({
    required this.color, required this.icon, required this.title,
    required this.poids, required this.description, required this.conseil,
    required this.onChanged, required this.min, required this.max,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1F12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(title,
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Text(
              '${(poids * 100).round()}%',
              style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Text(description,
            style: const TextStyle(color: Colors.white38, fontSize: 14, height: 1.4)),
        const SizedBox(height: 10),
        Slider(
          value: poids,
          min: min,
          max: max,
          divisions: ((max - min) * 100).round(),
          activeColor: color,
          inactiveColor: color.withValues(alpha: 0.2),
          label: '${(poids * 100).round()}%',
          onChanged: onChanged,
        ),
        Row(children: [
          Icon(Icons.star, color: color.withValues(alpha: 0.6), size: 11),
          const SizedBox(width: 4),
          Text(conseil,
              style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 13,
                  fontStyle: FontStyle.italic)),
        ]),
      ]),
    );
  }
}

class _PresetCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final bool highlight;
  final FusionConfig config;
  final VoidCallback onTap;

  const _PresetCard({
    required this.title, required this.subtitle,
    required this.selected, required this.config, required this.onTap,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = highlight
        ? const Color(0xFFFFD700)
        : selected
            ? const Color(0xFF4CAF7D)
            : const Color(0xFF2E7D52);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : const Color(0xFF0A1F12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : const Color(0xFF1A4731),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                color: selected ? color : Colors.white60,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              )),
          const SizedBox(height: 4),
          Text(subtitle,
              style: TextStyle(
                color: selected ? color.withValues(alpha: 0.7) : Colors.white30,
                fontSize: 14,
              )),
          const SizedBox(height: 6),
          // Mini barres
          _MiniBar(color: const Color(0xFF4CAF7D), value: config.poidsConfiance, label: 'Conf.'),
          const SizedBox(height: 2),
          _MiniBar(color: const Color(0xFFFF9800), value: config.poidsGain, label: 'Gain'),
        ]),
      ),
    );
  }
}

class _MiniBar extends StatelessWidget {
  final Color color;
  final double value;
  final String label;
  const _MiniBar({required this.color, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(
        width: 25,
        child: Text(label, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 7)),
      ),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: value,
            backgroundColor: color.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 4,
          ),
        ),
      ),
      const SizedBox(width: 4),
      Text('${(value * 100).round()}%',
          style: TextStyle(color: color, fontSize: 7, fontWeight: FontWeight.bold)),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Exemple concret chiffré
// ══════════════════════════════════════════════════════════════════════════════

/// Montre avec des chiffres réels l'impact de la configuration sur 2 courses fictives
class _ConcreteExampleCard extends StatelessWidget {
  final double confiance;
  final double gain;
  final double risque;

  const _ConcreteExampleCard({
    required this.confiance,
    required this.gain,
    required this.risque,
  });

  @override
  Widget build(BuildContext context) {
    // Exemple fictif : 2 courses avec profils opposés
    const double confA = 78; // Course A : haute confiance, gain modéré
    const double gainQA = 52; // qualité gain normalisée
    const double confB = 55; // Course B : confiance modérée, gain élevé
    const double gainQB = 88; // qualité gain normalisée

    // Calcul avec la config actuelle
    double scoreA = confiance * confA + gain * gainQA + risque * 60;
    double scoreB = confiance * confB + gain * gainQB + risque * 70;
    // Bonus croisé
    if (confA >= 70 && gainQA >= 60) scoreA *= 1.15;
    if (confB >= 70 && gainQB >= 60) scoreB *= 1.15;

    final aGagne = scoreA >= scoreB;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1F12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF4CAF7D).withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Text('🔬', style: TextStyle(fontSize: 13)),
          SizedBox(width: 6),
          Text(
            'Simulation avec votre configuration',
            style: TextStyle(
              color: Color(0xFF4CAF7D),
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ]),
        const SizedBox(height: 4),
        const Text(
          'Exemple : quelle course choisir ?',
          style: TextStyle(color: Colors.white38, fontSize: 13),
        ),
        const SizedBox(height: 10),

        Row(children: [
          // Course A
          Expanded(
            child: _ExCourse(
              name: 'Course A',
              confiance: confA.toInt(),
              gainLabel: 'Modéré',
              score: scoreA,
              isWinner: aGagne,
              confianceLabel: '78% confiance',
              gainMsg: 'Gain ajusté 52/100',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(children: [
              const Text('VS', style: TextStyle(color: Colors.white24, fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Icon(
                aGagne ? Icons.arrow_back : Icons.arrow_forward,
                color: const Color(0xFFFFD700),
                size: 16,
              ),
            ]),
          ),
          // Course B
          Expanded(
            child: _ExCourse(
              name: 'Course B',
              confiance: confB.toInt(),
              gainLabel: 'Élevé',
              score: scoreB,
              isWinner: !aGagne,
              confianceLabel: '55% confiance',
              gainMsg: 'Gain ajusté 88/100',
            ),
          ),
        ]),

        const SizedBox(height: 8),

        // Verdict
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF1A4731).withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            aGagne
                ? '→ Avec votre config (${(confiance * 100).round()}% confiance), '
                    'la Course A (78% certitude) prime sur le gain élevé de B. '
                    'Approche prudente : on choisit la sécurité.'
                : '→ Avec votre config (${(confiance * 100).round()}% confiance), '
                    'la Course B (fort gain) dépasse A malgré moins de certitude. '
                    'Approche plus risquée mais potentiellement plus rentable.',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 13,
              height: 1.4,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ]),
    );
  }
}

class _ExCourse extends StatelessWidget {
  final String name;
  final int confiance;
  final String gainLabel;
  final double score;
  final bool isWinner;
  final String confianceLabel;
  final String gainMsg;

  const _ExCourse({
    required this.name, required this.confiance, required this.gainLabel,
    required this.score, required this.isWinner,
    required this.confianceLabel, required this.gainMsg,
  });

  @override
  Widget build(BuildContext context) {
    final color = isWinner ? const Color(0xFFFFD700) : Colors.white24;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isWinner
            ? const Color(0xFFFFD700).withValues(alpha: 0.07)
            : const Color(0xFF0D1F0F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isWinner
              ? const Color(0xFFFFD700).withValues(alpha: 0.4)
              : Colors.white12,
          width: isWinner ? 1.5 : 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (isWinner) const Text('🏆 ', style: TextStyle(fontSize: 13)),
          Text(name, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 4),
        Text(confianceLabel, style: const TextStyle(color: Color(0xFF4CAF7D), fontSize: 14)),
        Text(gainMsg, style: const TextStyle(color: Color(0xFFFF9800), fontSize: 14)),
        const SizedBox(height: 4),
        Text(
          'Score : ${score.toStringAsFixed(0)}',
          style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ]),
    );
  }
}
