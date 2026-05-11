import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/pmu_models.dart';
import '../services/gain_calculator.dart';
import '../services/prediction_engine.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// Widget MiseGain — Calculateur de gains paramétrable
///
/// S'intègre dans :
///   • ConseilsScreen (onglet Conseils IA, détails expandés)
///   • ComparaisonScreen (détails comparaison)
///   • RaceDetailScreen (onglet Pronostics)
/// ─────────────────────────────────────────────────────────────────────────────
class MiseGainWidget extends StatefulWidget {
  final RaceRecommendation recommendation;
  final EquidiaPronostics? equidiaPronostics;
  final List<PmuParticipant> participants;

  const MiseGainWidget({
    super.key,
    required this.recommendation,
    this.equidiaPronostics,
    required this.participants,
  });

  @override
  State<MiseGainWidget> createState() => _MiseGainWidgetState();
}

class _MiseGainWidgetState extends State<MiseGainWidget> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _miseController = TextEditingController(text: '10');
  double _mise = 10.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _miseController.dispose();
    super.dispose();
  }

  void _updateMise(double valeur) {
    setState(() {
      _mise = valeur;
      _miseController.text = valeur % 1 == 0 ? valeur.toStringAsFixed(0) : valeur.toStringAsFixed(2);
    });
  }

  @override
  Widget build(BuildContext context) {
    final rec = widget.recommendation;
    final nbPartants = widget.participants.length;

    // Cotes des partants top 5 IA
    final cotesIA = rec.ranked
        .take(5)
        .map((p) => p.coteAffichee > 1 ? p.coteAffichee : 5.0)
        .toList();

    // Cotes Equidia si disponible
    List<double> cotesEquidia = [];
    if (widget.equidiaPronostics != null && !widget.equidiaPronostics!.isEmpty) {
      cotesEquidia = widget.equidiaPronostics!.selections.take(5).map((s) {
        final p = widget.participants.where((pp) => pp.numero == s.numPartant).toList();
        final cote = p.isNotEmpty ? p.first.coteAffichee : s.coteProbDecimale;
        return cote > 1 ? cote : 5.0;
      }).toList();
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A1F12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─ En-tête ─
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700).withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(bottom: BorderSide(color: const Color(0xFFFFD700).withValues(alpha: 0.25))),
            ),
            child: Row(children: [
              const Icon(Icons.calculate_outlined, color: Color(0xFFFFD700), size: 18),
              const SizedBox(width: 8),
              const Text('💰 Simulateur de Gains', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              const Spacer(),
              _InfoTooltip(),
            ]),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─ Saisie de la mise ─
                _MiseSaisie(
                  controller: _miseController,
                  mise: _mise,
                  onChanged: (v) => setState(() => _mise = v),
                  onPreset: _updateMise,
                ),
                const SizedBox(height: 14),

                // ─ Onglets IA / Equidia ─
                if (cotesEquidia.isNotEmpty) ...[
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D2818),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicatorColor: const Color(0xFFFFD700),
                      labelColor: const Color(0xFFFFD700),
                      unselectedLabelColor: Colors.white38,
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(icon: Icon(Icons.auto_awesome, size: 14), text: 'Gains IA'),
                        Tab(icon: Icon(Icons.tv, size: 14), text: 'Gains Equidia'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: _tabHeight(cotesIA, cotesEquidia, nbPartants),
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _GainPanel(cotes: cotesIA, mise: _mise, nbPartants: nbPartants, source: 'IA', recommendation: rec),
                        _GainPanel(cotes: cotesEquidia, mise: _mise, nbPartants: nbPartants, source: 'Equidia', recommendation: rec),
                      ],
                    ),
                  ),
                ] else
                  // Pas d'Equidia → affichage direct IA
                  _GainPanel(cotes: cotesIA, mise: _mise, nbPartants: nbPartants, source: 'IA', recommendation: rec),

                const SizedBox(height: 12),

                // ─ Scénarios extrêmes ─
                _ScenariosExtreme(mise: _mise, cotesIA: cotesIA, nbPartants: nbPartants),

                const SizedBox(height: 10),
                // Disclaimer
                Text(
                  '⚠️ Estimations indicatives basées sur les cotes PMU actuelles. Les rapports définitifs sont publiés par PMU après l\'arrivée.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 14, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _tabHeight(List<double> cotesIA, List<double> cotesEq, int nbPartants) {
    // Hauteur dynamique selon les paris disponibles
    int nbParis = 2; // Gagnant + Placé toujours
    if (cotesIA.length >= 2) nbParis++;
    if (cotesIA.length >= 3) nbParis++;
    if (cotesIA.length >= 4) nbParis++;
    if (cotesIA.length >= 5) nbParis++;
    return (nbParis * 80.0 + 20).clamp(200, 600);
  }
}

// ─── Saisie de mise ──────────────────────────────────────────────────────────

class _MiseSaisie extends StatelessWidget {
  final TextEditingController controller;
  final double mise;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onPreset;

  const _MiseSaisie({
    required this.controller,
    required this.mise,
    required this.onChanged,
    required this.onPreset,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Ma mise', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(children: [
          // Champ texte libre
          SizedBox(
            width: 100,
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
              style: const TextStyle(color: Color(0xFFFFD700), fontSize: 18, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                suffixText: '€',
                suffixStyle: const TextStyle(color: Color(0xFFFFB74D), fontSize: 16),
                filled: true,
                fillColor: const Color(0xFF0D2818),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFFFD700))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFFFB74D))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFFFD700), width: 2)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              onChanged: (v) {
                final parsed = double.tryParse(v);
                if (parsed != null && parsed > 0) onChanged(parsed);
              },
            ),
          ),
          const SizedBox(width: 10),
          // Boutons +/-
          _PlusMinusBtn(label: '-', onTap: () {
            final v = (mise - 1).clamp(1.0, 9999.0);
            onPreset(v);
          }),
          const SizedBox(width: 4),
          _PlusMinusBtn(label: '+', onTap: () {
            final v = (mise + 1).clamp(1.0, 9999.0);
            onPreset(v);
          }),
        ]),
        const SizedBox(height: 8),
        // Préréglages rapides
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: MisePreset.presets.map((p) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => onPreset(p.valeur),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: mise == p.valeur
                        ? const Color(0xFFFFD700).withValues(alpha: 0.2)
                        : const Color(0xFF0D2818),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: mise == p.valeur
                          ? const Color(0xFFFFD700)
                          : const Color(0xFF2E7D52).withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    p.label,
                    style: TextStyle(
                      color: mise == p.valeur ? const Color(0xFFFFD700) : Colors.white54,
                      fontSize: 14,
                      fontWeight: mise == p.valeur ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            )).toList(),
          ),
        ),
      ],
    );
  }
}

class _PlusMinusBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PlusMinusBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFF1A4731),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF2E7D52)),
        ),
        child: Center(child: Text(label, style: const TextStyle(color: Color(0xFF4CAF7D), fontSize: 20, fontWeight: FontWeight.bold))),
      ),
    );
  }
}

// ─── Panneau de gains par source ─────────────────────────────────────────────

class _GainPanel extends StatelessWidget {
  final List<double> cotes;
  final double mise;
  final int nbPartants;
  final String source;
  final RaceRecommendation recommendation;

  const _GainPanel({
    required this.cotes,
    required this.mise,
    required this.nbPartants,
    required this.source,
    required this.recommendation,
  });

  @override
  Widget build(BuildContext context) {
    if (cotes.isEmpty) {
      return const Center(child: Text('Cotes non disponibles', style: TextStyle(color: Colors.white38)));
    }

    final cote1 = cotes.isNotEmpty ? cotes[0] : 3.0;
    final isIA = source == 'IA';
    final accentColor = isIA ? const Color(0xFF4CAF7D) : const Color(0xFF64B5F6);

    final resultats = <GainResult>[
      GainCalculator.simpleGagnant(mise, cote1),
      GainCalculator.place(mise, cote1, nbPartants),
      GainCalculator.gagnantEtPlace(mise, cote1, nbPartants),
      if (cotes.length >= 3) GainCalculator.tierce(mise, cotes.take(3).toList(), nbPartants),
      if (cotes.length >= 4) GainCalculator.quarte(mise, cotes.take(4).toList(), nbPartants),
      if (cotes.length >= 5) GainCalculator.quinte(mise, cotes.take(5).toList(), nbPartants),
    ];

    // Identifier le pari conseillé par l'IA
    final typePariConseille = recommendation.typePariConseille;

    return SingleChildScrollView(
      child: Column(
        children: resultats.map((r) {
          final isConseille = _isTypePariConseille(r.type, typePariConseille) && isIA;
          return _GainLine(
            result: r,
            accentColor: accentColor,
            isConseille: isConseille,
          );
        }).toList(),
      ),
    );
  }

  bool _isTypePariConseille(TypePariCalc calc, TypePari conseille) {
    switch (conseille) {
      case TypePari.simpleGagnant: return calc == TypePariCalc.simpleGagnant;
      case TypePari.simpleGagnantPlace: return calc == TypePariCalc.gagnantEtPlace;
      case TypePari.place: return calc == TypePariCalc.place;
      case TypePari.tierce: return calc == TypePariCalc.tierce;
      case TypePari.quarteplus: return calc == TypePariCalc.quarte;
      case TypePari.quinteplus: return calc == TypePariCalc.quinte;
      case TypePari.aucun: return false;
    }
  }
}

// ─── Ligne de résultat d'un pari ─────────────────────────────────────────────

class _GainLine extends StatelessWidget {
  final GainResult result;
  final Color accentColor;
  final bool isConseille;

  const _GainLine({required this.result, required this.accentColor, required this.isConseille});

  @override
  Widget build(BuildContext context) {
    final gainMin = result.gainMin;
    final gainMax = result.gainMax;
    final proba = result.probabiliteEstimee;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isConseille
            ? const Color(0xFFFFD700).withValues(alpha: 0.07)
            : const Color(0xFF0D2818).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConseille
              ? const Color(0xFFFFD700).withValues(alpha: 0.6)
              : accentColor.withValues(alpha: 0.2),
          width: isConseille ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─ Ligne 1 : Type + badge conseillé ─
          Row(children: [
            Text(result.typeEmoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Text(result.typeLabel, style: TextStyle(color: isConseille ? const Color(0xFFFFD700) : Colors.white, fontSize: 13, fontWeight: isConseille ? FontWeight.bold : FontWeight.w500)),
            const Spacer(),
            if (isConseille)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.7)),
                ),
                child: const Text('⭐ CONSEILLÉ', style: TextStyle(color: Color(0xFFFFD700), fontSize: 14, fontWeight: FontWeight.bold)),
              ),
            // Probabilité
            const SizedBox(width: 6),
            _ProbaChip(proba: proba),
          ]),

          const SizedBox(height: 10),

          // ─ Ligne 2 : Mise + Scénarios gain ─
          Row(children: [
            // Mise engagée
            _MontantTile(
              label: 'Mise',
              valeur: '-${GainCalculator.formatEuros(result.mise)}',
              color: const Color(0xFFEF9A9A),
              isNeg: true,
            ),
            const SizedBox(width: 8),
            // Gain minimum (si placé ou désordre)
            _MontantTile(
              label: gainMin > 0 ? 'Gain min.' : 'Perte',
              valeur: GainCalculator.formatGain(gainMin),
              color: gainMin > 0 ? accentColor : const Color(0xFFEF9A9A),
              isNeg: gainMin <= 0,
            ),
            const SizedBox(width: 8),
            // Gain maximum (si gagnant / ordre)
            _MontantTile(
              label: 'Gain max.',
              valeur: GainCalculator.formatGain(gainMax),
              color: const Color(0xFFFFD700),
              isNeg: false,
            ),
          ]),

          const SizedBox(height: 8),

          // ─ Barre visuelle gain/risque ─
          _GainRiskBar(gainMin: gainMin, gainMax: gainMax, mise: result.mise),
        ],
      ),
    );
  }
}

// ─── Tuile montant ────────────────────────────────────────────────────────────

class _MontantTile extends StatelessWidget {
  final String label;
  final String valeur;
  final Color color;
  final bool isNeg;
  const _MontantTile({required this.label, required this.valeur, required this.color, required this.isNeg});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 14)),
            const SizedBox(height: 2),
            Text(valeur, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// ─── Barre visuelle gain/risque ───────────────────────────────────────────────

class _GainRiskBar extends StatelessWidget {
  final double gainMin;
  final double gainMax;
  final double mise;
  const _GainRiskBar({required this.gainMin, required this.gainMax, required this.mise});

  @override
  Widget build(BuildContext context) {
    // Ratio : gain max / (mise + gain max) pour visualiser l'espérance
    final total = mise + gainMax.abs();
    final ratio = total > 0 ? (gainMax / total).clamp(0.0, 1.0) : 0.0;
    final color = ratio >= 0.7
        ? const Color(0xFFFFD700)
        : ratio >= 0.5
            ? const Color(0xFF4CAF7D)
            : ratio >= 0.3
                ? const Color(0xFFFFB74D)
                : const Color(0xFFEF9A9A);

    return Row(children: [
      Text('Rapport risque/gain', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 14)),
      const SizedBox(width: 8),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            backgroundColor: const Color(0xFF1A4731),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
        ),
      ),
      const SizedBox(width: 6),
      Text('×${(gainMax / mise).toStringAsFixed(1)}', style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
    ]);
  }
}

// ─── Badge probabilité ────────────────────────────────────────────────────────

class _ProbaChip extends StatelessWidget {
  final double proba;
  const _ProbaChip({required this.proba});

  @override
  Widget build(BuildContext context) {
    final color = proba >= 30
        ? const Color(0xFF4CAF7D)
        : proba >= 15
            ? const Color(0xFFFFB74D)
            : const Color(0xFFEF9A9A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text('${proba.toStringAsFixed(0)}%', style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
    );
  }
}

// ─── Scénarios extrêmes résumé ────────────────────────────────────────────────

class _ScenariosExtreme extends StatelessWidget {
  final double mise;
  final List<double> cotesIA;
  final int nbPartants;
  const _ScenariosExtreme({required this.mise, required this.cotesIA, required this.nbPartants});

  @override
  Widget build(BuildContext context) {
    if (cotesIA.isEmpty) return const SizedBox.shrink();

    final cote1 = cotesIA[0];
    // Scénario minimum : placé
    final place = GainCalculator.place(mise, cote1, nbPartants);
    // Scénario maximum : gagnant
    final gagnant = GainCalculator.simpleGagnant(mise, cote1);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A4731).withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2E7D52).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📊 Résumé avec cette mise', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            // Perte maximum
            Expanded(child: _ScenarioTile(
              emoji: '😬',
              label: 'Pire cas',
              desc: 'Cheval non placé',
              valeur: GainCalculator.formatGain(-mise),
              color: const Color(0xFFEF9A9A),
            )),
            const SizedBox(width: 8),
            // Gain minimum (placé)
            Expanded(child: _ScenarioTile(
              emoji: '😊',
              label: 'Cas minimum',
              desc: 'Placé top 3',
              valeur: GainCalculator.formatGain(place.gainMin),
              color: const Color(0xFFFFB74D),
            )),
            const SizedBox(width: 8),
            // Gain maximum (gagnant)
            Expanded(child: _ScenarioTile(
              emoji: '🎉',
              label: 'Cas idéal',
              desc: 'Vainqueur',
              valeur: GainCalculator.formatGain(gagnant.gainMax),
              color: const Color(0xFFFFD700),
            )),
          ]),
        ],
      ),
    );
  }
}

class _ScenarioTile extends StatelessWidget {
  final String emoji;
  final String label;
  final String desc;
  final String valeur;
  final Color color;
  const _ScenarioTile({required this.emoji, required this.label, required this.desc, required this.valeur, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          Text(desc, style: const TextStyle(color: Colors.white30, fontSize: 14), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(valeur, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// ─── Tooltip info ─────────────────────────────────────────────────────────────

class _InfoTooltip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF0D2818),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF2E7D52))),
          title: const Text('ℹ️ Comment ça marche ?', style: TextStyle(color: Colors.white, fontSize: 15)),
          content: const Text(
            'Le simulateur calcule vos gains potentiels selon les cotes PMU actuelles.\n\n'
            '• Simple Gagnant : votre cheval termine 1er\n'
            '• Placé : votre cheval termine dans le top 3\n'
            '• Gagnant + Placé : 2 paris combinés\n'
            '• Tiercé : les 3 premiers dans l\'ordre ou le désordre\n\n'
            '⚠️ Les cotes évoluent jusqu\'au départ. Les rapports définitifs sont calculés par PMU.',
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Compris', style: TextStyle(color: Color(0xFF4CAF7D))))],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFF1A4731),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF2E7D52)),
        ),
        child: const Icon(Icons.info_outline, color: Color(0xFF4CAF7D), size: 14),
      ),
    );
  }
}
