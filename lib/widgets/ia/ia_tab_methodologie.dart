import 'package:flutter/material.dart';
import '../../services/ia_memory_service.dart';
import 'ia_widgets_communs.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  IaTabMethodologie — Onglet "Algorithme" de IaPerformanceScreen
//  ★ v10.36 : Converti en StatefulWidget + listener IaMemoryService
//  → les poids se mettent à jour immédiatement après chaque apprentissage,
//    sans avoir à quitter et revenir sur l'onglet (fix latence critères).
// ══════════════════════════════════════════════════════════════════════════════

class IaTabMethodologie extends StatefulWidget {
  const IaTabMethodologie({super.key});

  @override
  State<IaTabMethodologie> createState() => _IaTabMethodologieState();
}

class _IaTabMethodologieState extends State<IaTabMethodologie> {
  // ignore: unused_field
  static const _dark   = Color(0xFF0D1B2A);
  static const _card   = Color(0xFF111F30);
  static const _gold   = Color(0xFFFFD700);
  static const _green  = Color(0xFF4CAF7D);

  @override
  void initState() {
    super.initState();
    IaMemoryService.instance.addListener(_onPoidsChange);
  }

  @override
  void dispose() {
    IaMemoryService.instance.removeListener(_onPoidsChange);
    super.dispose();
  }

  void _onPoidsChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final poids = IaMemoryService.instance.poids;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        iaSectionTitle('🧠 Comment fonctionne l\'IA ?'),
        const SizedBox(height: 6),
        Text(
          poids.nbMisesAJour > 0
            ? '⚡ Poids actuellement adaptés après ${poids.nbMisesAJour} apprentissage(s)'
            : '📊 Poids par défaut — l\'IA adaptera ces valeurs avec l\'expérience',
          style: TextStyle(
            color: poids.nbMisesAJour > 0 ? _gold : Colors.white38,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 12),
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
        _buildMethodeCard('K', 'Hippodrome (${(poids.hippo * 100).toStringAsFixed(0)}%)', 'Spécialité de circuit : certains chevaux excellent sur un hippodrome précis (virages, nature de la piste, longueur des lignes droites). Historique filtré sur ce circuit.', const Color(0xFF4DB6AC), Icons.location_on, poids.hippo, 0.04),
        _buildMethodeCard('L', 'Entraîneur (${(poids.entraineur * 100).toStringAsFixed(0)}%)', 'Taux de réussite de l\'entraîneur sur ce type de course et cette distance. Un entraîneur en forme avec une bonne forme d\'écurie est un signal fort.', const Color(0xFFFFB74D), Icons.person_pin, poids.entraineur, 0.04),
        _buildMethodeCard('M', 'ELO dynamique (${(poids.elo * 100).toStringAsFixed(0)}%)', 'Score ELO calculé dynamiquement comme aux échecs : chaque course met à jour la cote du cheval selon la force des adversaires battus ou par lesquels il a été battu. Reflète le niveau réel.', const Color(0xFFBA68C8), Icons.trending_up, poids.elo, 0.05),
        _buildMethodeCard('N', 'Terrain (${(poids.terrain * 100).toStringAsFixed(0)}%)', 'Performance du cheval sur l\'état de terrain du jour (souple, lourd, très lourd, bon…). Certains chevaux sont radicalement différents selon l\'état du sol.', const Color(0xFF81C784), Icons.grass, poids.terrain, 0.05),
        _buildMethodeCard('O', 'Divergence forme/cote (${(poids.divergence * 100).toStringAsFixed(0)}%)', 'Détecte les "coups préparés" : un cheval avec une bonne forme récente mais une cote élevée (sous-estimé par le marché) est une opportunité. Mesure l\'écart forme ↔ cote.', const Color(0xFFFF7043), Icons.compare_arrows, poids.divergence, 0.04),
        _buildMethodeCard('P', 'Poids porté (${(poids.poidsRel * 100).toStringAsFixed(0)}%)', 'Poids porté relatif au champ (galop uniquement). Un cheval léger face à des chevaux lourdement chargés a un avantage mécanique mesurable sur les longues distances.', const Color(0xFF90A4AE), Icons.fitness_center, poids.poidsRel, 0.03),
        _buildMethodeCard('Q', 'Progression carrière (${(poids.progression * 100).toStringAsFixed(0)}%)', 'Trajectoire de carrière du cheval : un jeune cheval en progression constante est plus dangereux que son palmarès brut ne le suggère. Mesure la pente d\'amélioration sur les 10 dernières courses.', const Color(0xFFF48FB1), Icons.rocket_launch, poids.progression, 0.03),
        _buildMethodeCard('R', 'Mouvement de cote (${(poids.mouvCote * 100).toStringAsFixed(0)}%)', 'Détecte les variations significatives de cote en temps réel. Une cote qui chute de −40% en moins de 15 min signale un cheval très soutenu par les insiders — signal fort ignoré par le grand public.', const Color(0xFFFF6E40), Icons.moving, poids.mouvCote, 0.02),
        _buildMethodeCard('S', 'Place au départ (${(poids.placeDepart * 100).toStringAsFixed(0)}%)', 'Position sur la grille de départ. En trot attelé, la corde (position 1-2) est un avantage majeur. En galop, les rails intérieurs sur les virages serrés favorisent les chevaux de petit numéro.', const Color(0xFFB2DFDB), Icons.looks_one, poids.placeDepart, 0.02),
        const SizedBox(height: 16),

        // Auto-apprentissage
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _gold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _gold.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.school, color: _gold, size: 20),
                SizedBox(width: 8),
                Text('Comment l\'IA apprend-elle ?', style: TextStyle(color: _gold, fontWeight: FontWeight.bold, fontSize: 16)),
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

        // Améliorations v3.1
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
          const labels = {'forme': 'Forme', 'gains': 'Gains', 'record': 'Record', 'cote': 'Cote', 'constance': 'Régularité', 'victoires': 'Victoires', 'discipline': 'Discipline'};
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _gold.withValues(alpha: 0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.trending_up, color: _gold, size: 16),
                SizedBox(width: 6),
                Text('Gradient actuel (momentum)', style: TextStyle(color: _gold, fontWeight: FontWeight.bold, fontSize: 16)),
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
                        color: (isPos ? _green : Colors.red).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${isPos ? '+' : '−'}${pct.toStringAsFixed(2)}%',
                        style: TextStyle(color: isPos ? _green : Colors.redAccent, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ]),
                );
              }),
            ]),
          );
        }),
        const SizedBox(height: 12),

        // Normalisation
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF7C4DFF).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.3)),
          ),
          child: const Column(
            children: [
              Icon(Icons.auto_fix_high, color: Color(0xFF7C4DFF), size: 28),
              SizedBox(height: 8),
              Text('Normalisation 0-100', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: 6),
              Text(
                'Après calcul, tous les scores sont normalisés de 0 à 100 par rapport au meilleur et au moins bon cheval du champ. Cela permet une comparaison objective entre courses.',
                style: TextStyle(color: Colors.white54, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBulletPt(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('→ ', style: TextStyle(color: _gold, fontSize: 16)),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white60, fontSize: 16))),
      ]),
    );
  }

  Widget _buildMethodeCard(String lettre, String titre, String desc, Color color, IconData icon,
      [double? valeurActuelle, double? valeurDefaut]) {
    final hasVariation = valeurActuelle != null && valeurDefaut != null;
    final diff = hasVariation ? valeurActuelle - valeurDefaut : 0.0;
    final isUp   = diff > 0.005;
    final isDown = diff < -0.005;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
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
}
