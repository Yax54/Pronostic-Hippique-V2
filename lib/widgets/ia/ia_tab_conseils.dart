import 'package:flutter/material.dart';
import 'ia_widgets_communs.dart';
import 'ia_performance_dialogs.dart'; // IaBulletPoint

// ══════════════════════════════════════════════════════════════════════════════
//  IaTabConseils — Onglet "Conseils" de IaPerformanceScreen
//  Extrait lors du découpage v9.90 — StatelessWidget pur, zéro état.
// ══════════════════════════════════════════════════════════════════════════════

class IaTabConseils extends StatelessWidget {
  const IaTabConseils({super.key});

  static const _dark  = Color(0xFF0D1B2A);
  static const _card  = Color(0xFF111F30);
  static const _green = Color(0xFF4CAF7D);
  static const _gold  = Color(0xFFFFD700);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        iaSectionTitle('💡 Stratégies recommandées'),
        const SizedBox(height: 10),
        _buildConseilCard('🎯 Simple Gagnant — Stratégie sûre', 'Misez sur le favori IA (score > 75pts) en Simple Gagnant. Taux de réussite ~33%. Ideal pour des mises de 5 à 20€.', _green, 'DÉBUTANT'),
        _buildConseilCard('💰 Couplé désordre — Bon compromis', 'Prenez le top 2 IA en couplé désordre. Taux de réussite ~38%. Bon équilibre risque/rendement. Mises 2-10€.', const Color(0xFFFFB74D), 'INTERMÉDIAIRE'),
        _buildConseilCard('📋 Simple Placé — Paris sécurisé', 'Le favori IA finit dans le top 3 dans 71% des cas. Paris Placé idéal pour sécuriser des gains réguliers.', const Color(0xFF42A5F5), 'SÉCURITÉ'),
        _buildConseilCard('🌟 Quinté+ — Approche combinée', 'Sur les courses Quinté, prenez le top 5 IA. Dans 84% des cas, le gagnant est dans votre sélection.', const Color(0xFFCE93D8), 'QUINTÉ'),
        const SizedBox(height: 18),

        iaSectionTitle('⚠️ Signes d\'alerte — Quand être prudent'),
        const SizedBox(height: 10),
        _buildAlertCard('Score IA compressé', 'Si les 5 premiers chevaux ont des scores proches (ex: 78-72-70-68-65), la course est difficile à pronostiquer. Réduisez la mise.'),
        _buildAlertCard('Grande course avec nombreux partants', 'Plus de 16 partants = imprévisibilité accrue. Préférez le Placé au Gagnant.'),
        _buildAlertCard('Cheval sans données (score IA 50)', 'Un cheval avec score neutre manque d\'historique. Évitez de miser sur un outsider sans données.'),
        _buildAlertCard('Course d\'obstacle', 'Les courses d\'obstacle ont une part de hasard plus importante (chutes). L\'IA est moins précise. Réduisez les mises.'),

        const SizedBox(height: 18),
        iaSectionTitle('🏆 Comment utiliser l\'onglet Best Bet'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [const Color(0xFF1A2F5A), _dark]),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Best Bet sélectionne automatiquement la meilleure opportunité de la journée en croisant :', style: TextStyle(color: Colors.white70, fontSize: 15)),
              SizedBox(height: 10),
              IaBulletPoint('Score IA élevé (> 75 pts)'),
              IaBulletPoint('Cote intéressante (ni trop forte, ni trop faible)'),
              IaBulletPoint('Bon rapport confiance/rendement'),
              IaBulletPoint('Course non encore commencée'),
              SizedBox(height: 8),
              Text('Utilisez Best Bet chaque matin pour trouver le pari du jour.', style: TextStyle(color: _gold, fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Responsabilité
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
          ),
          child: const Column(children: [
            Icon(Icons.warning_amber, color: Colors.red, size: 28),
            SizedBox(height: 8),
            Text('Pariez de manière responsable', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
            SizedBox(height: 6),
            Text(
              'Les paris comportent des risques de perte financière. Ne misez jamais plus que ce que vous pouvez vous permettre de perdre. L\'IA améliore vos probabilités mais ne garantit aucun résultat.',
              style: TextStyle(color: Colors.white38, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      ],
    );
  }

  Widget _buildConseilCard(String titre, String desc, Color color, String badge) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(titre, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: Text(badge, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(desc, style: const TextStyle(color: Colors.white54, fontSize: 16)),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: color == _green ? 0.33 : color == const Color(0xFFFFB74D) ? 0.38 : color == const Color(0xFF42A5F5) ? 0.71 : 0.84,
            backgroundColor: Colors.white.withValues(alpha: 0.06),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 4,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertCard(String titre, String desc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre, style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 3),
                Text(desc, style: const TextStyle(color: Colors.white38, fontSize: 16)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
