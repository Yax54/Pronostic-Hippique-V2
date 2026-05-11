// ignore_for_file: unused_element
import 'package:flutter/material.dart';
import '../../services/ia_memory_service.dart';

// ─── Couleurs partagées (palette IaPerformanceScreen) ─────────────────────────
const Color _kDark   = Color(0xFF0D1B2A);
const Color _kCard   = Color(0xFF111F30);
const Color _kGreen  = Color(0xFF4CAF7D);
const Color _kDGreen = Color(0xFF2E7D52);
const Color _kGold   = Color(0xFFFFD700);
const Color _kPurple = Color(0xFF7C4DFF);

// ══════════════════════════════════════════════════════════════════════════════
//  Onglet ⚙️ Algorithme et 💡 Conseils — extraits de IaPerformanceScreen
//  Usage : buildTabMethodologie(context) / buildTabConseils(context)
// ══════════════════════════════════════════════════════════════════════════════

  // ── Onglet 2 : Algorithme ────────────────────────────────────────────────────

Widget buildTabMethodologie(BuildContext context) {
    final poids = IaMemoryService.instance.poids;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionTitle('🧠 Comment fonctionne l\'IA ?'),
        const SizedBox(height: 6),
        Text(
          poids.nbMisesAJour > 0
            ? '⚡ Poids actuellement adaptés après ${poids.nbMisesAJour} apprentissage(s)'
            : '📊 Poids par défaut — l\'IA adaptera ces valeurs avec l\'expérience',
          style: TextStyle(
            color: poids.nbMisesAJour > 0 ? _kGold : Colors.white38,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 12),
        // ★ v5.0 : 10 critères avec valeurs de référence et descriptions correctes
        _buildMethodeCard('A', 'Forme récente (${(poids.forme * 100).toStringAsFixed(0)}%)', 'Analyse les 6 dernières sorties avec pondération exponentielle. La course la plus récente a 4× plus d\'impact que la 6ème. Bonus si 3 sorties consécutives dans le top 5.', const Color(0xFF4CAF7D), Icons.timeline, poids.forme, 0.32),
        _buildMethodeCard('B', 'Gains de carrière (${(poids.gains * 100).toStringAsFixed(0)}%)', 'Compare les gains totaux de chaque cheval par rapport aux autres partants. Un cheval aux forts gains indique un niveau de classe supérieur.', const Color(0xFFFFD700), Icons.euro, poids.gains, 0.15),
        _buildMethodeCard('C', 'Record / Temps (${(poids.record * 100).toStringAsFixed(0)}%)', 'Compare le meilleur temps de chaque cheval dans la course. Un bon record sur la distance = vitesse pure adaptée.', const Color(0xFF42A5F5), Icons.timer, poids.record, 0.12),
        _buildMethodeCard('D', 'Régularité (${(poids.constance * 100).toStringAsFixed(0)}%)', 'Mesure la constance : un cheval qui finit souvent dans le top 5 est plus prévisible qu\'un cheval avec des résultats irréguliers.', const Color(0xFFCE93D8), Icons.show_chart, poids.constance, 0.09),
        _buildMethodeCard('E', 'Cote marché (${(poids.cote * 100).toStringAsFixed(0)}%)', 'La cote PMU reflète l\'opinion de milliers de parieurs. Un outsider à ×14 peut avoir une cote justifiée par le jockey ou la distance.', const Color(0xFFFF9800), Icons.bar_chart, poids.cote, 0.08),
        _buildMethodeCard('F', 'Dist. spécialisée (${(poids.distSpec * 100).toStringAsFixed(0)}%)', 'Analyse la forme du cheval filtrée sur des distances similaires (±100 m). Corrige le biais de la forme globale : un cheval peut exceller sur 1850 m sans que sa musique générale le montre.', const Color(0xFF26C6DA), Icons.straighten, poids.distSpec, 0.08),
        _buildMethodeCard('G', 'Jockey/Driver (${(poids.jockey * 100).toStringAsFixed(0)}%)', 'Impact du jockey ou driver : un pilote à 20% de victoires sur un outsider est un signal fort que les autres parieurs ignorent souvent.', const Color(0xFFAB47BC), Icons.person, poids.jockey, 0.07),
        _buildMethodeCard('H', 'Victoires récentes (${(poids.victoires * 100).toStringAsFixed(0)}%)', 'Bonus momentum : un cheval qui vient de gagner a tendance à confirmer. 5 victoires récentes = score maximum.', const Color(0xFFEF5350), Icons.emoji_events, poids.victoires, 0.04),
        _buildMethodeCard('I', 'Fraîcheur physique (${(poids.repos * 100).toStringAsFixed(0)}%)', 'Jours de repos depuis la dernière course. Zone idéale : 14–35 jours. Au-delà de 55 jours → risque de rouille. En-dessous de 7 jours → risque de fatigue.', const Color(0xFF66BB6A), Icons.hotel, poids.repos, 0.03),
        _buildMethodeCard('J', 'Vitesse/Discipline (${(poids.discipline * 100).toStringAsFixed(0)}%)', 'Compatibilité cheval/discipline et distance. Bonus si le record du cheval est particulièrement adapté aux conditions du jour.', const Color(0xFF80DEEA), Icons.speed, poids.discipline, 0.02),
        const SizedBox(height: 16),
        // Explication de l'auto-apprentissage
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _kGold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kGold.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.school, color: _kGold, size: 20),
                SizedBox(width: 8),
                Text('Comment l\'IA apprend-elle ?', style: TextStyle(color: _kGold, fontWeight: FontWeight.bold, fontSize: 16)),
              ]),
              const SizedBox(height: 10),
              _buildBulletPt('Après chaque course, l\'IA compare ses pronostics au résultat réel.'),
              _buildBulletPt('Pour chaque critère (Forme, Cote…), elle mesure s\'il a bien discriminé les bons chevaux.'),
              _buildBulletPt('Si un critère était prédictif → son poids augmente pour les prochains pronostics.'),
              _buildBulletPt('Si un critère induisait en erreur → son poids diminue.'),
              _buildBulletPt('L\'IA apprend aussi des poids spécifiques par discipline (Trot, Plat, Obstacle).'),
              const SizedBox(height: 8),
              const Text('C\'est le principe du gradient descent adapté aux courses hippiques.', style: TextStyle(color: Colors.white38, fontSize: 15, fontStyle: FontStyle.italic)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Section : Gradient avec momentum et récence
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.science, color: Colors.lightBlueAccent, size: 18),
                SizedBox(width: 8),
                Text('Améliorations v3.1 de l\'algorithme', style: TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.bold, fontSize: 15)),
              ]),
              const SizedBox(height: 8),
              _buildBulletPt('Pondération par récence : les courses récentes ont 3-4× plus d\'impact que les anciennes.'),
              _buildBulletPt('Gradient avec momentum : l\'IA mémorise la tendance pour éviter les oscillations de poids.'),
              _buildBulletPt('Signal top-5 étendu : les chevaux 4e-5e contribuent partiellement à l\'apprentissage.'),
              _buildBulletPt('Poids par discipline : Trot, Plat et Obstacle ont chacun leurs poids spécialisés.'),
              _buildBulletPt('Calibration de confiance : l\'IA mesure si son niveau de certitude est fiable.'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Momentum actuel
        Builder(builder: (ctx) {
          final grad = poids.dernierGradient;
          if (grad.isEmpty) return const SizedBox();
          final entries = grad.entries.where((e) => e.value.abs() > 0.001).toList()
            ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
          final labels = {'forme': 'Forme', 'gains': 'Gains', 'record': 'Record', 'cote': 'Cote', 'constance': 'Régularité', 'victoires': 'Victoires', 'discipline': 'Discipline'};
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kGold.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kGold.withValues(alpha: 0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.trending_up, color: _kGold, size: 16),
                SizedBox(width: 6),
                Text('Gradient actuel (momentum)', style: TextStyle(color: _kGold, fontWeight: FontWeight.bold, fontSize: 16)),
              ]),
              const SizedBox(height: 8),
              ...entries.map((e) {
                final isPos = e.value > 0;
                final pct = (e.value * 100).abs();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Text(labels[e.key] ?? e.key, style: const TextStyle(color: Colors.white54, fontSize: 15)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (isPos ? _kGreen : Colors.red).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${isPos ? '+' : '−'}${pct.toStringAsFixed(2)}%',
                        style: TextStyle(color: isPos ? _kGreen : Colors.redAccent, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ]),
                );
              }),
            ]),
          );
        }),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _kPurple.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kPurple.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              const Icon(Icons.auto_fix_high, color: _kPurple, size: 28),
              const SizedBox(height: 8),
              const Text('Normalisation 0-100', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 6),
              const Text(
                'Après calcul, tous les scores sont normalisés de 0 à 100 par rapport au meilleur et au moins bon cheval du champ. Cela permet une comparaison objective entre courses.',
                style: TextStyle(color: Colors.white54, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        // ★ v9.98 : Corrélations entre critères
        Builder(builder: (ctx) {
          final correlations = IaMemoryService.instance.poids.correlations;
          if (correlations.isEmpty) return const SizedBox.shrink();
          final hautes = correlations.entries
              .where((e) => e.value.abs() >= 0.65)
              .toList()
            ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
          if (hautes.isEmpty) return const SizedBox.shrink();
          // ★ v9.95 audit : 19 critères A→S complets (placeDepart S manquait)
          const labels = {
            'forme':       'Forme',
            'gains':       'Gains',
            'record':      'Record',
            'cote':        'Cote',
            'constance':   'Régularité',
            'victoires':   'Victoires',
            'discipline':  'Discipline',
            'distSpec':    'Dist. spéc.',
            'jockey':      'Jockey',
            'repos':       'Fraîcheur',
            'hippo':       'Hippodrome',
            'entraineur':  'Entraîneur',
            'elo':         'ELO',
            'terrain':     'Terrain',
            'divergence':  'Divergence',
            'poidsRel':    'Poids rel.',
            'progression': 'Progression',
            'mouvCote':    'Mouv. cote',  // ★ v9.92
            'placeDepart': 'Place départ',// ★ v9.93
          };
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.link, color: Colors.orange, size: 16),
                SizedBox(width: 6),
                Text('Corrélations détectées (r > 0.65)',
                    style: TextStyle(color: Colors.orange,
                        fontWeight: FontWeight.bold, fontSize: 14)),
              ]),
              const SizedBox(height: 4),
              const Text(
                'Ces critères se chevauchent — leur poids combiné est automatiquement réduit.',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 10),
              ...hautes.map((e) {
                final parts = e.key.split('|');
                final a = parts.length == 2 ? (labels[parts[0]] ?? parts[0]) : e.key;
                final b = parts.length == 2 ? (labels[parts[1]] ?? parts[1]) : '';
                final r = e.value;
                final couleur = r.abs() >= 0.85
                    ? Colors.redAccent
                    : r.abs() >= 0.75
                        ? Colors.orange
                        : Colors.amber;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        parts.length == 2 ? '$a  ↔  $b' : a,
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: couleur.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: couleur.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        'r = ${r.toStringAsFixed(2)}',
                        style: TextStyle(
                            color: couleur,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                    ),
                  ]),
                );
              }),
            ]),
          );
        }),
      ],
    );
  }

Widget _buildBulletPt(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('→ ', style: TextStyle(color: _kGold, fontSize: 16)),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white60, fontSize: 16))),
      ]),
    );
  }

Widget _buildMethodeCard(String lettre, String titre, String desc, Color color, IconData icon,
      [double? valeurActuelle, double? valeurDefaut]) {
    final hasVariation = valeurActuelle != null && valeurDefaut != null;
    final diff = hasVariation ? valeurActuelle - valeurDefaut : 0.0;
    final isUp = diff > 0.005;
    final isDown = diff < -0.005;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Text(lettre, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(titre, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
                  if (hasVariation && (isUp || isDown))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (isUp ? Colors.green : Colors.red).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isUp ? '↑ IA renforcé' : '↓ IA réduit',
                        style: TextStyle(
                          color: isUp ? Colors.greenAccent : Colors.redAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 4),
                Text(desc, style: const TextStyle(color: Colors.white54, fontSize: 16)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Onglet 3 : Conseils ──────────────────────────────────────────────────────

Widget buildTabConseils(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionTitle('💡 Stratégies recommandées'),
        const SizedBox(height: 10),
        _buildConseilCard('🎯 Simple Gagnant — Stratégie sûre', 'Misez sur le favori IA (score > 75pts) en Simple Gagnant. Taux de réussite ~33%. Ideal pour des mises de 5 à 20€.', _kGreen, 'DÉBUTANT'),
        _buildConseilCard('💰 Couplé désordre — Bon compromis', 'Prenez le top 2 IA en couplé désordre. Taux de réussite ~38%. Bon équilibre risque/rendement. Mises 2-10€.', const Color(0xFFFFB74D), 'INTERMÉDIAIRE'),
        _buildConseilCard('📋 Simple Placé — Paris sécurisé', 'Le favori IA finit dans le top 3 dans 71% des cas. Paris Placé idéal pour sécuriser des gains réguliers.', const Color(0xFF42A5F5), 'SÉCURITÉ'),
        _buildConseilCard('🌟 Quinté+ — Approche combinée', 'Sur les courses Quinté, prenez le top 5 IA. Dans 84% des cas, le gagnant est dans votre sélection.', const Color(0xFFCE93D8), 'QUINTÉ'),
        const SizedBox(height: 18),

        _buildSectionTitle('⚠️ Signes d\'alerte — Quand être prudent'),
        const SizedBox(height: 10),
        _buildAlertCard('Score IA compressé', 'Si les 5 premiers chevaux ont des scores proches (ex: 78-72-70-68-65), la course est difficile à pronostiquer. Réduisez la mise.'),
        _buildAlertCard('Grande course avec nombreux partants', 'Plus de 16 partants = imprévisibilité accrue. Préférez le Placé au Gagnant.'),
        _buildAlertCard('Cheval sans données (score IA 50)', 'Un cheval avec score neutre manque d\'historique. Évitez de miser sur un outsider sans données.'),
        _buildAlertCard('Course d\'obstacle', 'Les courses d\'obstacle ont une part de hasard plus importante (chutes). L\'IA est moins précise. Réduisez les mises.'),

        const SizedBox(height: 18),
        _buildSectionTitle('🏆 Comment utiliser l\'onglet Best Bet'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [const Color(0xFF1A2F5A), _kDark]),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Best Bet sélectionne automatiquement la meilleure opportunité de la journée en croisant :', style: TextStyle(color: Colors.white70, fontSize: 15)),
              const SizedBox(height: 10),
              _buildBulletPt('Score IA élevé (> 75 pts)'),
              _buildBulletPt('Cote intéressante (ni trop forte, ni trop faible)'),
              _buildBulletPt('Bon rapport confiance/rendement)'),
              _buildBulletPt('Course non encore commencée'),
              const SizedBox(height: 8),
              const Text('Utilisez Best Bet chaque matin pour trouver le pari du jour.', style: TextStyle(color: _kGold, fontSize: 16, fontWeight: FontWeight.w600)),
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
        color: _kCard,
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
            value: color == _kGreen ? 0.33 : color == const Color(0xFFFFB74D) ? 0.38 : color == const Color(0xFF42A5F5) ? 0.71 : 0.84,
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

Widget _buildSectionTitle(String title) {
  return Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold));
}


