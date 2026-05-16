import 'package:flutter/material.dart';
import '../../services/ia_memory_service.dart';
import '../../services/ia_memory_models.dart';
import 'ia_widgets_communs.dart';

// ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
//  IaTabMethodologie â Onglet "Algorithme" de IaPerformanceScreen
//  â v10.36 : Converti en StatefulWidget + listener IaMemoryService
//  â les poids se mettent Ã  jour immediatement apres chaque apprentissage,
//    sans avoir Ã  quitter et revenir sur l'onglet (fix latence criteres).
// ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

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
        iaSectionTitle('ð§  Comment fonctionne l\'IA ?'),
        const SizedBox(height: 6),
        Text(
          poids.nbMisesAJour > 0
            ? '⚡ Poids actuellement adaptes apres ${poids.nbMisesAJour} apprentissage(s)'
            : '📊 Poids par défaut – l\'IA adaptera ces valeurs avec l\'expérience',
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
        _buildMethodeCard('E', 'Cote marché (${(poids.cote * 100).toStringAsFixed(0)}%)', 'La cote PMU reflète l\'opinion de milliers de parieurs. Un outsider à 14€ peut avoir une cote justifiée par le jockey ou la distance.', const Color(0xFFFF9800), Icons.bar_chart, poids.cote, 0.08),
        _buildMethodeCard('F', 'Dist. spécialisée (${(poids.distSpec * 100).toStringAsFixed(0)}%)', 'Analyse la forme du cheval filtrée sur des distances similaires (±100 m). Corrige le biais de la forme globale : un cheval peut exceller sur 1850 m sans que sa musique générale le montre.', const Color(0xFF26C6DA), Icons.straighten, poids.distSpec, 0.08),
        _buildMethodeCard('G', 'Jockey/Driver (${(poids.jockey * 100).toStringAsFixed(0)}%)', 'Impact du jockey ou driver : un pilote à 20 % de victoires sur un outsider est un signal fort que les autres parieurs ignorent souvent.', const Color(0xFFAB47BC), Icons.person, poids.jockey, 0.07),
        _buildMethodeCard('H', 'Victoires récentes (${(poids.victoires * 100).toStringAsFixed(0)}%)', 'Bonus momentum : un cheval qui vient de gagner a tendance à confirmer. 5 victoires récentes = score maximum.', const Color(0xFFEF5350), Icons.emoji_events, poids.victoires, 0.04),
        _buildMethodeCard('I', 'Fraîcheur physique (${(poids.repos * 100).toStringAsFixed(0)}%)', 'Jours de repos depuis la dernière course. Zone idéale : 14–35 jours. Au-delà de 55 jours – risque de rouille. En-dessous de 7 jours – risque de fatigue.', const Color(0xFF66BB6A), Icons.hotel, poids.repos, 0.03),
        _buildMethodeCard('J', 'Vitesse/Discipline (${(poids.discipline * 100).toStringAsFixed(0)}%)', 'Compatibilité cheval/discipline et distance. Bonus si le record du cheval est particulièrement adapté aux conditions du jour.', const Color(0xFF80DEEA), Icons.speed, poids.discipline, 0.02),
        _buildMethodeCard('K', 'Hippodrome (${(poids.hippo * 100).toStringAsFixed(0)}%)', 'Spécialité de circuit : certains chevaux excellent sur un hippodrome précis (virages, nature de la piste, longueur des lignes droites). Historique filtré sur ce circuit.', const Color(0xFF4DB6AC), Icons.location_on, poids.hippo, 0.04),
        _buildMethodeCard('L', 'Entraîneur (${(poids.entraineur * 100).toStringAsFixed(0)}%)', 'Taux de réussite de l\'entraîneur sur ce type de course et cette distance. Un entraîneur en forme avec une bonne forme d\'écurie est un signal fort.', const Color(0xFFFFB74D), Icons.person_pin, poids.entraineur, 0.04),
        _buildMethodeCard('M', 'ELO dynamique (${(poids.elo * 100).toStringAsFixed(0)}%)', 'Score ELO calculé dynamiquement comme aux échecs : chaque course met à jour la cote du cheval selon la force des adversaires battus ou par lesquels il a été battu. Reflète le niveau réel.', const Color(0xFFBA68C8), Icons.trending_up, poids.elo, 0.05),
        _buildMethodeCard('N', 'Terrain (${(poids.terrain * 100).toStringAsFixed(0)}%)', 'Performance du cheval sur l\'état de terrain du jour (souple, lourd, très lourd, bon…). Certains chevaux sont radicalement différents selon l\'état du sol.', const Color(0xFF81C784), Icons.grass, poids.terrain, 0.05),
        _buildMethodeCard('O', 'Divergence forme/cote (${(poids.divergence * 100).toStringAsFixed(0)}%)', 'Détecte les "coups préparés" : un cheval avec une bonne forme récente mais une cote élevée (sous-estimé par le marché) est une opportunité. Mesure l\'écart forme – cote.', const Color(0xFFFF7043), Icons.compare_arrows, poids.divergence, 0.04),
        _buildMethodeCard('P', 'Poids porté (${(poids.poidsRel * 100).toStringAsFixed(0)}%)', 'Poids porté relatif au champ (galop uniquement). Un cheval léger face à des chevaux lourdement chargés a un avantage mécanique mesurable sur les longues distances.', const Color(0xFF90A4AE), Icons.fitness_center, poids.poidsRel, 0.03),
        _buildMethodeCard('Q', 'Progression carrière (${(poids.progression * 100).toStringAsFixed(0)}%)', 'Trajectoire de carrière du cheval : un jeune cheval en progression constante est plus dangereux que son palmarès brut ne le suggère. Mesure la pente d\'amélioration sur les 10 dernières courses.', const Color(0xFFF48FB1), Icons.rocket_launch, poids.progression, 0.03),
        _buildMethodeCard('R', 'Mouvement de cote (${(poids.mouvCote * 100).toStringAsFixed(0)}%)', 'Détecte les variations significatives de cote en temps réel. Une cote qui chute de −40 % en moins de 15 min signale un cheval très soutenu par les insiders – signal fort ignoré par le grand public.', const Color(0xFFFF6E40), Icons.moving, poids.mouvCote, 0.02),
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
              const Text('C\'est le principe du gradient descent adapte aux courses hippiques.', style: TextStyle(color: Colors.white38, fontSize: 15, fontStyle: FontStyle.italic)),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Ameliorations v3.1
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
              _buildBulletPt('Pondération par récence : les courses récentes ont 3–4× plus d\'impact que les anciennes.'),
              _buildBulletPt('Gradient avec momentum : l\'IA mémorise la tendance pour éviter les oscillations de poids.'),
              _buildBulletPt('Signal top-5 étendu : les chevaux 4e-5e contribuent partiellement à l\'apprentissage.'),
              _buildBulletPt('Poids par discipline : Trot, Plat et Obstacle ont chacun leurs poids specialises.'),
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
                        '${isPos ? '+' : 'â'}${pct.toStringAsFixed(2)}%',
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
        const SizedBox(height: 16),
        // â v10.36 : Diagnostic de convergence IA
        _buildDiagnosticConvergence(poids),
      ],
    );
  }

  // â v10.36 : Diagnostic de convergence â repond Ã  "l'IA apprend-elle vraiment ?"
  Widget _buildDiagnosticConvergence(IaPoidsAdaptatifs poids) {
    const Map<String, double> defauts = {
      'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
      'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
      'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
      'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05,
      'divergence': 0.04, 'poidsRel': 0.03, 'progression': 0.03,
      'mouvCote': 0.06, 'placeDepart': 0.03,
    };
    const Map<String, String> noms = {
      'forme': 'Forme récente', 'gains': 'Gains', 'record': 'Record/Temps',
      'cote': 'Cote marché', 'constance': 'Régularité', 'victoires': 'Victoires',
      'discipline': 'Discipline', 'distSpec': 'Distance spéc.', 'jockey': 'Jockey/Driver',
      'repos': 'Fraîcheur', 'hippo': 'Hippodrome', 'entraineur': 'Entraîneur',
      'elo': 'ELO dynamique', 'terrain': 'Terrain', 'divergence': 'Divergence',
      'poidsRel': 'Poids relatif', 'progression': 'Progression',
      'mouvCote': 'Mouv. cote', 'placeDepart': 'Place départ',
    };

    // ââ Historique par jour depuis le journal ââââââââââââââââââââââââââââââââ
    // On groupe les entrees journal par jour (date tronquee) et on garde
    // la derniere entree gradient du jour (poids "apres" = etat final du jour).
    final journal = IaMemoryService.instance.journal;
    final Map<String, Map<String, double>> snapshotParJour = {};
    for (final e in journal.reversed) {
      // Uniquement les entrees de gradient global (pas discipline ni atypique)
      if (e.methode != 'gradient' && e.methode != null) continue;
      if (e.apres.isEmpty) continue;
      final key = '${e.date.year}-'
          '${e.date.month.toString().padLeft(2, '0')}-'
          '${e.date.day.toString().padLeft(2, '0')}';
      snapshotParJour[key] ??= Map<String, double>.from(e.apres);
    }
    // Trier par date croissante, garder les 14 derniers jours max
    final joursTries = snapshotParJour.keys.toList()..sort();
    final joursAffiches = joursTries.length > 14
        ? joursTries.sublist(joursTries.length - 14)
        : joursTries;

    // ââ Derive totale vs defauts âââââââââââââââââââââââââââââââââââââââââââââ
    double deriveTotal = 0.0;
    final criteres = defauts.keys.toList();
    for (final c in criteres) {
      deriveTotal += (poids.getPoids(c) - defauts[c]!).abs();
    }
    final tries = criteres.toList()
      ..sort((a, b) {
        final da = (poids.getPoids(a) - defauts[a]!).abs();
        final db = (poids.getPoids(b) - defauts[b]!).abs();
        return db.compareTo(da);
      });

    // ââ Diagnostic global ââââââââââââââââââââââââââââââââââââââââââââââââââââ
    final String diagnostic;
    final Color diagColor;
    if (poids.nbMisesAJour == 0) {
      diagnostic = '⚠️ Aucun apprentissage – poids encore aux valeurs initiales';
      diagColor = Colors.white38;
    } else if (deriveTotal < 0.05) {
      diagnostic = '🔄 Poids quasi-inchangés (normal si < 2 semaines)';
      diagColor = Colors.orange;
    } else if (deriveTotal < 0.15) {
      diagnostic = '📈 Convergence modérée – ajustement progressif en cours';
      diagColor = _gold;
    } else {
      diagnostic = '✅ Convergence forte – critères significativement adaptés';
      diagColor = _green;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ââ En-tÃªte ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
        Row(children: [
          const Text('ð¬', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Diagnostic de convergence IA',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _gold.withValues(alpha: 0.4)),
            ),
            child: Text('${poids.nbMisesAJour} analyse(s)',
                style: const TextStyle(color: _gold, fontSize: 14, fontWeight: FontWeight.bold)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(diagnostic, style: TextStyle(color: diagColor, fontSize: 14)),
        const SizedBox(height: 4),
        Text(
          'Derive totale vs valeurs initiales : ${(deriveTotal * 100).toStringAsFixed(1)} pts',
          style: const TextStyle(color: Colors.white38, fontSize: 14),
        ),

        // ââ Historique jour par jour âââââââââââââââââââââââââââââââââââââââââ
        if (joursAffiches.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('Évolution des 3 critères principaux (14j)',
              style: TextStyle(color: Colors.white54, fontSize: 14)),
          const SizedBox(height: 8),
          // Les 3 criteres les plus modifies = les plus interessants Ã  suivre
          // ★ v10.37 : message < 3 jours
          if (joursAffiches.length < 3)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(children: [
                const Text('📊', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  'Graphe disponible après 3 analyses '
                  '(${joursAffiches.length}/3 effectuées)',
                  style: const TextStyle(color: Colors.white38, fontSize: 14),
                )),
              ]),
            )
          else
          // Les 3 critères les plus modifiés = les plus intéressants à suivre
          ...tries.take(3).map((c) {
            final couleurCritere = c == 'forme' ? const Color(0xFF4CAF7D)
                : c == 'cote'  ? const Color(0xFFFF9800)
                : c == 'jockey'? const Color(0xFFAB47BC)
                : c == 'elo'   ? const Color(0xFFBA68C8)
                : c == 'mouvCote' ? const Color(0xFF26C6DA)
                : _gold;

            // Collecter les valeurs par jour pour ce critere
            final valeurs = joursAffiches.map((j) {
              final snap = snapshotParJour[j]!;
              return snap[c] ?? defauts[c]!;
            }).toList();

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 10, height: 10,
                      decoration: BoxDecoration(color: couleurCritere, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(noms[c] ?? c,
                      style: TextStyle(color: couleurCritere, fontSize: 14, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text(
                    'init: ${(defauts[c]! * 100).toStringAsFixed(0)}%  '
                    'â  actuel: ${(poids.getPoids(c) * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(color: Colors.white38, fontSize: 16),
                  ),
                ]),
                const SizedBox(height: 5),
                // Mini graphe en barres horizontales
                SizedBox(
                  height: 28,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: joursAffiches.asMap().entries.map((entry) {
                      final i   = entry.key;
                      final j   = entry.value;
                      final val = valeurs[i];
                      final def = defauts[c]!;
                      // Hauteur relative : defaut = 50% de hauteur, variation autour
                      final ratio = (val / (def * 2.5)).clamp(0.1, 1.0);
                      final isLast = i == joursAffiches.length - 1;
                      final dayLbl = j.substring(8); // jj
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Flexible(
                                child: FractionallySizedBox(
                                  heightFactor: ratio,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: isLast
                                          ? couleurCritere
                                          : couleurCritere.withValues(alpha: 0.45),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(dayLbl,
                                  style: TextStyle(
                                    color: isLast ? Colors.white54 : Colors.white24,
                                    fontSize: 14,
                                  )),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ]),
            );
          }),
        ],


        // ââ 19 criteres complets âââââââââââââââââââââââââââââââââââââââââââââ
        const SizedBox(height: 12),
        const Text('19 critères – variation vs valeurs initiales :',
            style: TextStyle(color: Colors.white54, fontSize: 14)),
        const SizedBox(height: 8),
        ...tries.map((c) {
          final actuel  = poids.getPoids(c);
          final defaut  = defauts[c]!;
          final diff    = actuel - defaut;
          final isUp    = diff > 0.003;
          final isDown  = diff < -0.003;
          final color   = isUp ? _green : isDown ? Colors.redAccent : Colors.white38;
          final fleche  = isUp ? 'â' : isDown ? 'â' : 'â';
          final pctAct  = (actuel * 100).toStringAsFixed(1);
          final pctDef  = (defaut * 100).toStringAsFixed(1);
          final pctDiff = '${diff >= 0 ? '+' : ''}${(diff * 100).toStringAsFixed(1)}';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              SizedBox(width: 115,
                  child: Text(noms[c] ?? c,
                      style: const TextStyle(color: Colors.white70, fontSize: 14))),
              Text('$pctDef%', style: const TextStyle(color: Colors.white38, fontSize: 14)),
              const Text(' â ', style: TextStyle(color: Colors.white24, fontSize: 14)),
              Text('$pctAct%',
                  style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('$fleche $pctDiff%',
                    style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ]),
          );
        }),

        // ââ Synergie Î2 : 3 indices combines ââââââââââââââââââââââââââââââââ
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.35)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Text('ð', style: TextStyle(fontSize: 14)),
              SizedBox(width: 6),
              Text('Synergie Î2 â poids des 3 indices du score final',
                  style: TextStyle(color: Color(0xFF7C4DFF),
                      fontSize: 14, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 4),
            const Text(
              'L\'IA apprend aussi le meilleur mix entre les criteres (Î1), '
              'la confiance IA, et le taux historique par type de pari.',
              style: TextStyle(color: Colors.white38, fontSize: 16),
            ),
            const SizedBox(height: 8),
            _buildLigneIndice('Score multicriteres (Î1)',
                poids.poidsIndices.poidsCriteres, 0.40,
                const Color(0xFF4CAF7D)),
            _buildLigneIndice('Confiance IA',
                poids.poidsIndices.poidsConfiance, 0.35,
                const Color(0xFF42A5F5)),
            _buildLigneIndice('Reussite par type pari',
                poids.poidsIndices.poidsReussite, 0.25,
                const Color(0xFFFFB74D)),
          ]),
        ),

        const SizedBox(height: 8),
        const Text(
          'Si rien ne bouge après 3+ semaines — les données API PMU '
          'atteignent peut-être leur limite prédictive.',
          style: TextStyle(color: Colors.white24, fontSize: 16),
        ),

        // ★ v10.37 : Date de dernière mise à jour
        if (journal.isNotEmpty) ...[
          const SizedBox(height: 6),
          Builder(builder: (context) {
            final dernier = journal.first;
            final d = dernier.date;
            final now = DateTime.now();
            // ★ v10.37 fix : comparaison par date calendaire (pas par durée)
            // inDays tronque — une analyse hier à 23h58 consultée à 00h05
            // donnerait "il y a 0 jours". On compare les dates sans heure.
            final aujourdhuiDate = DateTime(now.year, now.month, now.day);
            final dateAnalyse    = DateTime(d.year, d.month, d.day);
            final ecartJours = aujourdhuiDate.difference(dateAnalyse).inDays;
            final String label;
            if (ecartJours == 0)      label = "aujourd'hui";
            else if (ecartJours == 1) label = 'hier';
            else                      label = 'il y a $ecartJours jours';
            return Text(
              'Dernière mise à jour : $label '
              '(${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')} '
              'à ${d.hour.toString().padLeft(2,'0')}h${d.minute.toString().padLeft(2,'0')})',
              style: const TextStyle(color: Colors.white24, fontSize: 16),
            );
          }),
        ],
      ]),
    );
  }

  Widget _buildLigneIndice(String nom, double actuel, double defaut, Color color) {
    final diff   = actuel - defaut;
    final isUp   = diff > 0.003;
    final isDown = diff < -0.003;
    final c      = isUp ? _green : isDown ? Colors.redAccent : Colors.white38;
    final fleche = isUp ? 'â' : isDown ? 'â' : 'â';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Container(width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        SizedBox(width: 155,
            child: Text(nom, style: const TextStyle(color: Colors.white70, fontSize: 14))),
        Text('${(defaut * 100).toStringAsFixed(0)}%',
            style: const TextStyle(color: Colors.white38, fontSize: 14)),
        const Text(' â ', style: TextStyle(color: Colors.white24, fontSize: 14)),
        Text('${(actuel * 100).toStringAsFixed(1)}%',
            style: TextStyle(color: c, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(width: 6),
        Text('$fleche ${diff >= 0 ? '+' : ''}${(diff * 100).toStringAsFixed(1)}%',
            style: TextStyle(color: c, fontSize: 16)),
      ]),
    );
  }

  Widget _buildBulletPt(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('â ', style: TextStyle(color: _gold, fontSize: 16)),
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
                        isUp ? 'â IA renforce' : 'â IA reduit',
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
