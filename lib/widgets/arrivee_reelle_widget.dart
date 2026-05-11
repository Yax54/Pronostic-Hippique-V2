// ═══════════════════════════════════════════════════════════════════
//  ARRIVEE REELLE WIDGET — Affichage de l'arrivée officielle PMU
//  Réutilisable dans tous les écrans (Programme, Courses, Conseils,
//  Best Bet, Home, Détail course).
//
//  Logique v9.6 :
//   • Course à venir (pas encore terminée) → "Arrivée réelle : Course à venir"
//   • Course terminée sans résultat connu  → spinner + récupération auto API PMU
//   • Course terminée avec résultat        → badges N°X colorés
//     - Vert  : numéro était dans la sélection IA (top 5)
//     - Blanc : numéro absent de la sélection IA
//
//  ★ v9.6 : fetchArriveeDirecte() — récupération automatique même sans pari
//    Le widget est désormais StatefulWidget : il déclenche lui-même l'appel
//    API PMU si la course est terminée et que le résultat est absent du cache.
//    Plus besoin de passer par AlertService/_trackedCourses.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../services/ia_memory_service.dart';

/// Construit la courseKey au format utilisé par IaMemoryService :
/// "R{numReunion}C{numCourse}_{ddmmyyyy}"
String buildCourseKey({
  required String reunionCode,  // ex: "R1", "R2"
  required int numCourse,       // ex: 3
  required String dateStr,      // ex: "14042026"
}) {
  // reunionCode peut être "R1", "R2"... on extrait le numéro
  final numR = reunionCode.replaceAll(RegExp(r'[^0-9]'), '');
  return 'R${numR}C${numCourse}_$dateStr';
}

/// Widget affichant l'arrivée réelle PMU.
///
/// [courseKey]       : clé unique de la course (ex: "R1C3_14042026")
/// [isTerminee]      : true si la course est passée (heure dépassée de >40 min)
/// [heureDepart]     : heure réelle de la course (pour appel API PMU direct)
/// [selectionIA]     : liste des numéros prédits par l'IA (pour colorer en vert)
/// [compact]         : si true, affichage horizontal compact (pour listes)
///                     si false, affichage bloc complet (pour détail course)
class ArriveReelleWidget extends StatefulWidget {
  final String courseKey;
  final bool isTerminee;
  final DateTime? heureDepart;
  final List<String> selectionIA;
  final bool compact;

  const ArriveReelleWidget({
    super.key,
    required this.courseKey,
    required this.isTerminee,
    this.heureDepart,
    this.selectionIA = const [],
    this.compact = true,
  });

  @override
  State<ArriveReelleWidget> createState() => _ArriveReelleWidgetState();
}

class _ArriveReelleWidgetState extends State<ArriveReelleWidget> {
  @override
  void initState() {
    super.initState();
    // ★ v9.6 : si la course est terminée et le résultat absent → fetch immédiat
    if (widget.isTerminee) {
      _fetchSiNecessaire();
    }
  }

  @override
  void didUpdateWidget(ArriveReelleWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Déclencher si le statut passe à "terminée"
    if (widget.isTerminee && !oldWidget.isTerminee) {
      _fetchSiNecessaire();
    }
  }

  void _fetchSiNecessaire() {
    final svc = IaMemoryService.instance;
    // Déjà en cache → rien à faire
    if (svc.arriveeConnue(widget.courseKey) != null) return;
    // Pas d'heure de départ → impossible d'appeler l'API
    if (widget.heureDepart == null) return;
    // Lancer la récupération en arrière-plan (pas d'await = non-bloquant)
    svc.fetchArriveeDirecte(
      courseKey: widget.courseKey,
      heureDepart: widget.heureDepart!,
    ).then((arrivee) {
      if (arrivee.isNotEmpty && mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    // ★ v9.6 : utiliser arriveeConnue() qui cherche dans le cache RAM + pronostics
    final arrivee = IaMemoryService.instance.arriveeConnue(widget.courseKey);

    if (widget.compact) {
      return _buildCompact(arrivee);
    } else {
      return _buildFull(arrivee);
    }
  }

  // ── Mode compact : une ligne (utilisé dans Programme, Courses, Conseils, Home, Best Bet)
  Widget _buildCompact(List<int>? arrivee) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            '🏁',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(width: 6),
          const Text(
            'Arrivée réelle :',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _buildContenu(arrivee, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ── Mode complet : bloc (utilisé dans CourseDetailScreen)
  Widget _buildFull(List<int>? arrivee) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D2818).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (arrivee != null && arrivee.isNotEmpty)
              ? const Color(0xFF4CAF7D).withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🏁', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              const Text(
                'Arrivée réelle PMU',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (arrivee != null && arrivee.isNotEmpty) ...[
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF7D).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color:
                            const Color(0xFF4CAF7D).withValues(alpha: 0.4)),
                  ),
                  child: const Text(
                    'Officiel',
                    style: TextStyle(
                      color: Color(0xFF4CAF7D),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          _buildContenu(arrivee, fontSize: 14),
          if (arrivee != null && arrivee.isNotEmpty && widget.selectionIA.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '🟢 Vert = cheval prédit par l\'IA',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Contenu commun : badges numéros ou texte d'état
  Widget _buildContenu(List<int>? arrivee, {required double fontSize}) {
    // Pas encore terminée
    if (!widget.isTerminee) {
      return Text(
        'Course à venir',
        style: TextStyle(
          color: Colors.white38,
          fontSize: fontSize,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    // Terminée mais pas encore de résultat
    if (arrivee == null || arrivee.isEmpty) {
      return Row(
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'En attente des résultats PMU...',
            style: TextStyle(
              color: Colors.white38,
              fontSize: fontSize,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
    }

    // Résultats disponibles → badges colorés
    final top5 = arrivee.take(5).toList();
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: top5.asMap().entries.map((e) {
        final position = e.key; // 0 = 1er, 1 = 2ème...
        final num = e.value;
        final isIA = widget.selectionIA.contains(num.toString());
        final isFirst = position == 0;

        Color borderColor;
        Color textColor;
        Color bgColor;

        if (isFirst) {
          // 1er : toujours doré
          borderColor = const Color(0xFFFFD700).withValues(alpha: 0.7);
          textColor = const Color(0xFFFFD700);
          bgColor = const Color(0xFFFFD700).withValues(alpha: 0.12);
        } else if (isIA) {
          // Dans la sélection IA → vert
          borderColor = const Color(0xFF4CAF7D).withValues(alpha: 0.6);
          textColor = const Color(0xFF4CAF7D);
          bgColor = const Color(0xFF4CAF7D).withValues(alpha: 0.12);
        } else {
          // Hors sélection IA → blanc discret
          borderColor = Colors.white.withValues(alpha: 0.2);
          textColor = Colors.white54;
          bgColor = Colors.white.withValues(alpha: 0.04);
        }

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: fontSize > 12 ? 7 : 5,
            vertical: fontSize > 12 ? 4 : 2,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: borderColor),
          ),
          child: Text(
            'N°$num',
            style: TextStyle(
              color: textColor,
              fontSize: fontSize,
              fontWeight: isFirst || isIA ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        );
      }).toList(),
    );
  }
}
