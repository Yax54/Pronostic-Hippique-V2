import 'package:flutter/material.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  Widget : Vue vide (aucune course suivie)
// ══════════════════════════════════════════════════════════════════════════════

class EmptyTrackedView extends StatelessWidget {
  const EmptyTrackedView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.track_changes,
              color: Colors.white.withValues(alpha: 0.08), size: 72),
          const SizedBox(height: 20),
          const Text('Aucune course suivie',
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text(
            'Appuyez sur le bouton "Suivre une course"\npour ajouter des courses du programme PMU.',
            style: TextStyle(color: Colors.white30, fontSize: 16, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D52).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2E7D52).withValues(alpha: 0.3)),
            ),
            child: Column(children: [
              const Icon(Icons.auto_awesome, color: Color(0xFF4CAF7D), size: 28),
              const SizedBox(height: 8),
              const Text('PMU IA',
                  style: TextStyle(color: Color(0xFF4CAF7D), fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              const Text(
                'Données de courses en temps réel\navec pronostics IA intégrés',
                style: TextStyle(color: Colors.white38, fontSize: 16, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Widget : Bouton action compact
// ══════════════════════════════════════════════════════════════════════════════

class ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.55), width: 1.2),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 18),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Widget : Point clignotant (course en cours)
// ══════════════════════════════════════════════════════════════════════════════

class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key});

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _anim = Tween(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Opacity(
        opacity: _anim.value,
        child: Container(
          width: 12,
          height: 12,
          decoration: const BoxDecoration(
            color: Color(0xFFEF5350),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
