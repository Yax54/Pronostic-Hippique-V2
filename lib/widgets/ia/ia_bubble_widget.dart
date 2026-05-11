// ═══════════════════════════════════════════════════════════════════════════
//  IA BUBBLE WIDGET — v10.10
//  Bulle flottante animée qui s'affiche quand l'IA veut s'exprimer
//  ★ v10.10 : durée 9s (au lieu de 6s) + tap ouvre la page concernée
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/ia_personality_service.dart';
import '../../main.dart'; // NavigationNotifier

class IaBubbleOverlay extends StatefulWidget {
  final Widget child;
  const IaBubbleOverlay({super.key, required this.child});

  @override
  State<IaBubbleOverlay> createState() => IaBubbleOverlayState();
}

class IaBubbleOverlayState extends State<IaBubbleOverlay> {
  static IaBubbleOverlayState? _current;

  OverlayEntry? _entry;
  String _message  = '';
  String _type     = 'info'; // 'info' | 'victoire' | 'defaite' | 'niveau'

  @override
  void initState() {
    super.initState();
    _current = this;
  }

  @override
  void dispose() {
    _current = null;
    _entry?.remove();
    super.dispose();
  }

  /// Afficher un message depuis n'importe où
  static void afficher(String message, {String type = 'info'}) {
    _current?._afficher(message, type: type);
  }

  void _afficher(String message, {String type = 'info'}) {
    final svc = IaPersonalityService.instance;
    // ★ v9.93 : Types prioritaires (niveau, badge, analyse, nonPartant) bypassent
    // le cooldown 30 min — ils sont déclenchés par des événements rares et importants.
    // Seuls les types 'info' génériques sont soumis au cooldown.
    const prioritaires = {'niveau', 'badge', 'analyse', 'nonPartant', 'victoire', 'defaite'};
    if (!prioritaires.contains(type) && !svc.peutAfficherBulle()) return;

    _message = message;
    _type    = type;
    // Marquer cooldown uniquement pour les bulles non-prioritaires
    if (!prioritaires.contains(type)) svc.marquerBulleAffichee();

    _entry?.remove();
    _entry = OverlayEntry(
      builder: (_) => _IaBubble(
        message: _message,
        avatarEmoji: svc.avatarEmoji,
        prenom: svc.prenom,
        type: _type,
        onDismiss: _dismiss,
        onTap: () => _naviguerVersPage(message, type),
      ),
    );

    Overlay.of(context).insert(_entry!);

    // ★ v10.10 : Auto-disparition après 9 secondes (au lieu de 6s)
    Future.delayed(const Duration(seconds: 9), _dismiss);
  }

  /// ★ v9.93 : Navigation corrigée — table réelle 0=Accueil 1=Conseils 2=Prog
  ///            3=Courses 4=BestBet 5=IAStats 6=MesParis 7=Profil
  void _naviguerVersPage(String message, String type) {
    _dismiss();
    if (!mounted) return;
    final nav = context.read<NavigationNotifier>();

    // Types explicites
    if (type == 'victoire' || type == 'defaite') { nav.goTo(6); return; }
    if (type == 'niveau')                         { nav.goTo(7); return; }
    if (type == 'badge')                          { nav.goTo(7); return; } // ★ v9.93 badge → Profil
    if (type == 'analyse')                        { nav.goTo(5); return; } // ★ v9.93 après analyse → IA Stats
    if (type == 'nonPartant')                     { nav.goTo(3); return; } // ★ v9.93 retrait → Courses

    final msg = message.toLowerCase();

    // Soir / après analyse → IA Stats (5)
    if ((msg.contains('lancer') && msg.contains('analys')) ||
        msg.contains('apprenne') || msg.contains('journal') ||
        msg.contains('réussite') || msg.contains('analyse terminée') ||
        msg.contains('excellente analyse')) {
      nav.goTo(5);
      return;
    }

    // Matin / conseil / courses → Conseils IA (1)
    if (msg.contains('pronostic') || msg.contains('cours') ||
        msg.contains('conseil') || msg.contains('critères') ||
        msg.contains('se profile') || msg.contains('miser') ||
        msg.contains('bonjour') || msg.contains('belle journée') ||
        msg.contains('en feu') || msg.contains('correspond')) {
      nav.goTo(1);
      return;
    }

    // Par défaut → IA Stats (5)
    nav.goTo(5);
  }

  void _dismiss() {
    _entry?.remove();
    _entry = null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ─── Widget bulle ────────────────────────────────────────────────────────────
class _IaBubble extends StatefulWidget {
  final String message;
  final String avatarEmoji;
  final String prenom;
  final String type;
  final VoidCallback onDismiss;
  final VoidCallback onTap;

  const _IaBubble({
    required this.message,
    required this.avatarEmoji,
    required this.prenom,
    required this.type,
    required this.onDismiss,
    required this.onTap,
  });

  @override
  State<_IaBubble> createState() => _IaBubbleState();
}

class _IaBubbleState extends State<_IaBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;
  late Animation<double>   _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _scale   = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _accentColor {
    switch (widget.type) {
      case 'victoire': return const Color(0xFF4CAF7D);
      case 'defaite':  return const Color(0xFFEF5350);
      case 'niveau':   return const Color(0xFFFFD700);
      default:         return const Color(0xFF7C4DFF);
    }
  }

  /// ★ v9.93 : Label de l'action corrigé selon le type et le contenu
  String get _actionLabel {
    if (widget.type == 'victoire' || widget.type == 'defaite') return '👉 Voir Mes Paris';
    if (widget.type == 'niveau')      return '👉 Voir mon Profil';
    if (widget.type == 'badge')       return '👉 Voir mes badges';
    if (widget.type == 'analyse')     return '👉 Voir IA Stats';
    if (widget.type == 'nonPartant')  return '👉 Voir les courses';  // ★ v9.93

    final msg = widget.message.toLowerCase();

    // Soir / après analyse → IA Stats
    if ((msg.contains('lancer') && msg.contains('analys')) ||
        msg.contains('apprenne') || msg.contains('journal') ||
        msg.contains('réussite') || msg.contains('analyse terminée')) {
      return '👉 Voir IA Stats';
    }
    // Matin / conseils / courses → Conseils IA
    if (msg.contains('pronostic') || msg.contains('cours') ||
        msg.contains('conseil') || msg.contains('critères') ||
        msg.contains('se profile') || msg.contains('miser') ||
        msg.contains('bonjour') || msg.contains('correspond')) {
      return '👉 Voir Conseils IA';
    }
    return '👉 Voir IA Stats';
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 90,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: FadeTransition(
          opacity: _opacity,
          child: ScaleTransition(
            scale: _scale,
            alignment: Alignment.bottomRight,
            child: GestureDetector(
              onTap: widget.onTap, // ★ v10.10 : tap → navigation
              child: Container(
                constraints: const BoxConstraints(maxWidth: 280),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1B2A),
                  borderRadius: const BorderRadius.only(
                    topLeft:     Radius.circular(16),
                    topRight:    Radius.circular(16),
                    bottomLeft:  Radius.circular(16),
                    bottomRight: Radius.circular(4),
                  ),
                  border: Border.all(
                      color: _accentColor.withValues(alpha: 0.6), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: _accentColor.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // En-tête avatar + prénom + fermer
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: _accentColor.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: _accentColor.withValues(alpha: 0.5)),
                          ),
                          child: Center(
                            child: Text(widget.avatarEmoji,
                                style: const TextStyle(fontSize: 16)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.prenom,
                          style: TextStyle(
                            color: _accentColor,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: widget.onDismiss, // X = fermer seulement
                          child: const Icon(Icons.close,
                              color: Colors.white38, size: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Message
                    Text(
                      widget.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // ★ v10.10 : label navigation + fermer
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _actionLabel,
                          style: TextStyle(
                            color: _accentColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Appuyer pour ouvrir',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.25),
                              fontSize: 10),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
