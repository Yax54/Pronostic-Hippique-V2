import 'package:flutter/material.dart';
import '../services/gain_calculator.dart';
import '../services/prediction_engine.dart';
import '../models/pmu_models.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// Widget simulateur de gains — Pronostic Hippique
///
/// Affiche :
///   • Presets de mise rapide (2€, 5€, 10€, 20€, 50€, 100€)
///   • Slider de mise personnalisée (1€–200€)
///   • Gain potentiel MAX (meilleur scénario)
///   • Gain potentiel MIN (scénario limiter les pertes)
///   • Mise conseillée par l'IA selon le niveau de confiance
///   • Probabilité estimée en %
///
/// Usage : s'intègre dans ConseilsScreen et ComparaisonScreen
/// ─────────────────────────────────────────────────────────────────────────────

class GainSimulatorWidget extends StatefulWidget {
  /// Recommandation IA avec les infos du favori
  final RaceRecommendation rec;

  /// Nombre de partants (pour le calcul Placé)
  final int nbPartants;

  /// Source des pronostics pour l'affichage (null = IA seulement)
  final EquidiaPronostics? equidia;

  /// Participants pour retrouver les cotes Equidia
  final List<PmuParticipant> participants;

  const GainSimulatorWidget({
    super.key,
    required this.rec,
    required this.nbPartants,
    this.equidia,
    this.participants = const [],
  });

  @override
  State<GainSimulatorWidget> createState() => _GainSimulatorWidgetState();
}

class _GainSimulatorWidgetState extends State<GainSimulatorWidget> {
  double _mise = 10.0;
  // 0 = IA, 1 = Equidia (si disponible)
  int _sourceIdx = 0;

  // Cote du favori IA
  double get _coteIa => widget.rec.gagnant?.coteAffichee ?? 0.0;

  // Cote du favori Equidia (premier de la liste)
  double get _coteEquidia {
    final eq = widget.equidia;
    if (eq == null || eq.isEmpty) return 0.0;
    final selNum = eq.selections.first.numPartant;
    final p = widget.participants.where((x) => x.numero == selNum).toList();
    if (p.isNotEmpty) return p.first.coteAffichee;
    return eq.selections.first.coteProbDecimale;
  }

  bool get _hasEquidia =>
      widget.equidia != null && !widget.equidia!.isEmpty && _coteEquidia > 0;

  double get _coteActive => _sourceIdx == 0 ? _coteIa : _coteEquidia;

  // Mise conseillée selon le niveau de confiance
  double get _miseConseillee {
    final conf = widget.rec.niveauConfiance;
    if (conf >= 85) return 20.0;
    if (conf >= 70) return 10.0;
    if (conf >= 55) return 5.0;
    return 2.0;
  }

  // Label mise conseillée
  String get _miseConseileeLabel {
    final conf = widget.rec.niveauConfiance;
    if (conf >= 85) return '20€ — Confiance FORTE';
    if (conf >= 70) return '10€ — Confiance BONNE';
    if (conf >= 55) return '5€ — Confiance MOYENNE';
    return '2€ — Confiance FAIBLE';
  }

  @override
  void initState() {
    super.initState();
    // Partir de la mise conseillée par défaut
    _mise = _miseConseillee;
  }

  // Calcul des gains selon le type de pari
  GainResult _calcGain(TypePari type, double cote) {
    final nb = widget.nbPartants;
    switch (type) {
      case TypePari.simpleGagnant:
        return GainCalculator.simpleGagnant(_mise, cote);
      case TypePari.simpleGagnantPlace:
        return GainCalculator.gagnantEtPlace(_mise, cote, nb);
      case TypePari.place:
        return GainCalculator.place(_mise, cote, nb);
      case TypePari.tierce:
        final cotes = widget.rec.tierce
            .map((p) => p.coteAffichee > 0 ? p.coteAffichee : 5.0)
            .take(3)
            .toList();
        if (cotes.length < 3) return GainCalculator.simpleGagnant(_mise, cote);
        return GainCalculator.tierce(_mise, cotes, nb);
      case TypePari.quarteplus:
        final cotesQ4 = widget.rec.quarte
            .map((p) => p.coteAffichee > 0 ? p.coteAffichee : 6.0)
            .take(4)
            .toList();
        if (cotesQ4.length < 4) return GainCalculator.tierce(_mise, cotesQ4.take(3).toList(), nb);
        return GainCalculator.quarte(_mise, cotesQ4, nb);
      case TypePari.quinteplus:
        final cotesQ5 = widget.rec.quinte
            .map((p) => p.coteAffichee > 0 ? p.coteAffichee : 7.0)
            .take(5)
            .toList();
        if (cotesQ5.length < 5) return GainCalculator.tierce(_mise, cotesQ5.take(3).toList(), nb);
        return GainCalculator.quinte(_mise, cotesQ5, nb);
      case TypePari.aucun:
        return GainCalculator.simpleGagnant(_mise, cote);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cote = _coteActive;
    final type = widget.rec.typePariConseille;
    final gainResult = cote > 0 ? _calcGain(type, cote) : null;
    final confiance = widget.rec.niveauConfiance;
    final confianceColor = confiance >= 70
        ? const Color(0xFF4CAF7D)
        : confiance >= 50
            ? const Color(0xFFFFB74D)
            : const Color(0xFFEF9A9A);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0A2B18).withValues(alpha: 0.95),
            const Color(0xFF071A0F).withValues(alpha: 0.95),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E7D52), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─ Titre ─
          Row(children: [
            const Text('💶', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Simulateur de Gain',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold),
              ),
            ),
            // Badge confiance
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: confianceColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: confianceColor.withValues(alpha: 0.5)),
              ),
              child: Text(
                '$confiance% confiance',
                style: TextStyle(
                    color: confianceColor,
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ]),
          const SizedBox(height: 12),

          // ─ Sélection source si Equidia disponible ─
          if (_hasEquidia) ...[
            _SourceToggle(
              sourceIdx: _sourceIdx,
              onChanged: (idx) => setState(() => _sourceIdx = idx),
              coteIa: _coteIa,
              coteEquidia: _coteEquidia,
            ),
            const SizedBox(height: 12),
          ],

          // ─ Mise conseillée par l'IA ─
          _MiseConseilleeRow(label: _miseConseileeLabel, onUse: () {
            setState(() => _mise = _miseConseillee);
          }),
          const SizedBox(height: 10),

          // ─ Presets de mise rapide ─
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: MisePreset.presets.map((preset) {
                final isSelected = (_mise - preset.valeur).abs() < 0.01;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _mise = preset.valeur),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF2E7D52)
                            : const Color(0xFF1A4731).withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF4CAF7D)
                              : const Color(0xFF2E7D52).withValues(alpha: 0.4),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Text(
                        preset.label,
                        style: TextStyle(
                          color:
                              isSelected ? Colors.white : Colors.white60,
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),

          // ─ Slider de mise personnalisée ─
          _MiseSlider(
            mise: _mise,
            onChanged: (v) => setState(() => _mise = v),
          ),
          const SizedBox(height: 12),

          // ─ Résultats de gain ─
          if (cote <= 0)
            _NoCoteInfo()
          else if (gainResult != null)
            _GainResults(
              gainResult: gainResult,
              mise: _mise,
              typePari: widget.rec.typePariLabel,
              cote: cote,
            ),
        ],
      ),
    );
  }
}

// ─── Toggle source IA / Equidia ───────────────────────────────────────────────

class _SourceToggle extends StatelessWidget {
  final int sourceIdx;
  final ValueChanged<int> onChanged;
  final double coteIa;
  final double coteEquidia;

  const _SourceToggle({
    required this.sourceIdx,
    required this.onChanged,
    required this.coteIa,
    required this.coteEquidia,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D2818),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1A4731)),
      ),
      child: Row(children: [
        Expanded(
          child: _ToggleBtn(
            label: '🤖 IA',
            subLabel: coteIa > 0 ? 'Cote ${coteIa.toStringAsFixed(1)}' : '-',
            selected: sourceIdx == 0,
            color: const Color(0xFF2E7D52),
            onTap: () => onChanged(0),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: _ToggleBtn(
            label: '📺 Equidia',
            subLabel:
                coteEquidia > 0 ? 'Cote ${coteEquidia.toStringAsFixed(1)}' : '-',
            selected: sourceIdx == 1,
            color: const Color(0xFF1565C0),
            onTap: () => onChanged(1),
          ),
        ),
      ]),
    );
  }
}

class _ToggleBtn extends StatelessWidget {
  final String label;
  final String subLabel;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _ToggleBtn({
    required this.label,
    required this.subLabel,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color : Colors.transparent,
          ),
        ),
        child: Column(children: [
          Text(label,
              style: TextStyle(
                  color: selected ? Colors.white : Colors.white38,
                  fontSize: 14,
                  fontWeight:
                      selected ? FontWeight.bold : FontWeight.normal)),
          Text(subLabel,
              style: TextStyle(
                  color: selected
                      ? color
                      : Colors.white24,
                  fontSize: 13)),
        ]),
      ),
    );
  }
}

// ─── Mise conseillée ─────────────────────────────────────────────────────────

class _MiseConseilleeRow extends StatelessWidget {
  final String label;
  final VoidCallback onUse;

  const _MiseConseilleeRow({required this.label, required this.onUse});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD700).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        const Text('⭐', style: TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Mise conseillée par l\'IA',
                style: TextStyle(color: Color(0xFFFFD700), fontSize: 13)),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
          ]),
        ),
        GestureDetector(
          onTap: onUse,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.5)),
            ),
            child: const Text('Appliquer',
                style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
    );
  }
}

// ─── Slider de mise ──────────────────────────────────────────────────────────

class _MiseSlider extends StatelessWidget {
  final double mise;
  final ValueChanged<double> onChanged;

  const _MiseSlider({required this.mise, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Row(children: [
        const Text('Ma mise :',
            style: TextStyle(color: Colors.white60, fontSize: 14)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF2E7D52).withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF4CAF7D)),
          ),
          child: Text(
            '${mise.toStringAsFixed(0)} €',
            style: const TextStyle(
                color: Color(0xFF4CAF7D),
                fontSize: 16,
                fontWeight: FontWeight.bold),
          ),
        ),
      ]),
      const SizedBox(height: 4),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: const Color(0xFF2E7D52),
          inactiveTrackColor: const Color(0xFF1A4731),
          thumbColor: const Color(0xFF4CAF7D),
          overlayColor: const Color(0xFF4CAF7D).withValues(alpha: 0.2),
          trackHeight: 5,
          thumbShape:
              const RoundSliderThumbShape(enabledThumbRadius: 10),
        ),
        child: Slider(
          min: 1,
          max: 200,
          divisions: 199,
          value: mise.clamp(1, 200),
          onChanged: onChanged,
        ),
      ),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('1€', style: TextStyle(color: Colors.white30, fontSize: 13)),
        const Text('200€',
            style: TextStyle(color: Colors.white30, fontSize: 13)),
      ]),
    ]);
  }
}

// ─── Résultats de gain ────────────────────────────────────────────────────────

class _GainResults extends StatelessWidget {
  final GainResult gainResult;
  final double mise;
  final String typePari;
  final double cote;

  const _GainResults({
    required this.gainResult,
    required this.mise,
    required this.typePari,
    required this.cote,
  });

  @override
  Widget build(BuildContext context) {
    final gr = gainResult;

    return Column(children: [
      // ─ Titre pari + cote ─
      Row(children: [
        Expanded(
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1A4731).withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color(0xFF2E7D52).withValues(alpha: 0.4)),
            ),
            child: Row(children: [
              Text(gr.typeEmoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(gr.typeLabel,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold)),
                  Text('Cote : ${cote.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 13)),
                ]),
              ),
              // Probabilité
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${gr.probabiliteEstimee.toStringAsFixed(0)}%',
                    style: const TextStyle(
                        color: Color(0xFFFFB74D),
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
                const Text('chance estimée',
                    style:
                        TextStyle(color: Colors.white38, fontSize: 14)),
              ]),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 10),

      // ─ Gains MAX / MIN ─
      Row(children: [
        // Gain MAX
        Expanded(
          child: _GainCard(
            label: 'Gain MAX',
            emoji: '🚀',
            subLabel: 'Meilleur scénario',
            amount: gr.scenarioOptimiste,
            color: const Color(0xFF4CAF7D),
            isPositif: gr.scenarioOptimiste > 0,
          ),
        ),
        const SizedBox(width: 8),
        // Gain MIN / Limiter les pertes
        Expanded(
          child: _GainCard(
            label: gr.gainMin > 0 ? 'Gain MIN' : 'Perte MAX',
            emoji: gr.gainMin > 0 ? '🛡️' : '📉',
            subLabel: gr.gainMin > 0
                ? 'Limiter les pertes'
                : 'Si cheval non classé',
            amount: gr.gainMin > 0 ? gr.gainMin : gr.scenarioPessimiste,
            color: gr.gainMin > 0
                ? const Color(0xFF81C784)
                : const Color(0xFFEF5350),
            isPositif: gr.gainMin > 0,
          ),
        ),
      ]),
      const SizedBox(height: 8),

      // ─ Retour total si gagnant ─
      if (gr.retourTotal > 0)
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0D2818),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: const Color(0xFF1A4731)),
          ),
          child: Row(children: [
            const Text('💰',
                style: TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Text(
              'Retour total si gagnant : ',
              style: const TextStyle(color: Colors.white60, fontSize: 14),
            ),
            Text(
              GainCalculator.formatEuros(gr.retourTotal),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold),
            ),
            const Text(' (mise incluse)',
                style: TextStyle(
                    color: Colors.white38, fontSize: 13)),
          ]),
        ),

      const SizedBox(height: 8),

      // ─ Scénarios résumés ─
      _ScenariosRow(mise: mise, gr: gr),
    ]);
  }
}

// ─── Carte de gain ───────────────────────────────────────────────────────────

class _GainCard extends StatelessWidget {
  final String label;
  final String emoji;
  final String subLabel;
  final double amount;
  final Color color;
  final bool isPositif;

  const _GainCard({
    required this.label,
    required this.emoji,
    required this.subLabel,
    required this.amount,
    required this.color,
    required this.isPositif,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 6),
          Text(
            GainCalculator.formatGain(amount),
            style: TextStyle(
                color: isPositif ? color : const Color(0xFFEF5350),
                fontSize: 22,
                fontWeight: FontWeight.bold),
          ),
          Text(subLabel,
              style: const TextStyle(color: Colors.white38, fontSize: 14)),
        ],
      ),
    );
  }
}

// ─── Résumé des scénarios ─────────────────────────────────────────────────────

class _ScenariosRow extends StatelessWidget {
  final double mise;
  final GainResult gr;

  const _ScenariosRow({required this.mise, required this.gr});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📊 Résumé des scénarios',
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _ScenarioLine(
            label: '🏆 Cheval gagnant :',
            value: GainCalculator.formatGain(gr.gainMax),
            color: const Color(0xFF4CAF7D),
          ),
          if (gr.type == TypePariCalc.gagnantEtPlace ||
              gr.type == TypePariCalc.place)
            _ScenarioLine(
              label: '🎯 Cheval placé (2e ou 3e) :',
              value: GainCalculator.formatGain(gr.gainMin),
              color: const Color(0xFF81C784),
            ),
          _ScenarioLine(
            label: '📉 Cheval non classé :',
            value: GainCalculator.formatGain(gr.scenarioPessimiste),
            color: const Color(0xFFEF5350),
          ),
        ],
      ),
    );
  }
}

class _ScenarioLine extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _ScenarioLine({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(children: [
        Expanded(
            child: Text(label,
                style:
                    const TextStyle(color: Colors.white54, fontSize: 13))),
        Text(value,
            style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

// ─── Pas de cote disponible ───────────────────────────────────────────────────

class _NoCoteInfo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: const Row(children: [
        Icon(Icons.info_outline, color: Colors.white38, size: 18),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Cote non disponible — le calcul des gains sera possible dès l\'ouverture des paris.',
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ),
      ]),
    );
  }
}
