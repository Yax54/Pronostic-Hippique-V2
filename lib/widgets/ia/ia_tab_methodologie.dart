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
            ? 'â¡ Poids actuellement adaptes apres ${poids.nbMisesAJour} apprentissage(s)'
            : 'ð Poids par defaut â l\'IA adaptera ces valeurs avec l\'experience',
          style: TextStyle(
            color: poids.nbMisesAJour > 0 ? _gold : Colors.white38,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 12),
        _buildMethodeCard('A', 'Forme recente (${(poids.forme * 100).toStringAsFixed(0)}%)', 'Analyse les 6 dernieres sorties avec ponderation exponentielle. La course la plus recente a 4Ã plus d\'impact que la 6eme. Bonus si 3 sorties consecutives dans le top 5.', const Color(0xFF4CAF7D), Icons.timeline, poids.forme, 0.32),
        _buildMethodeCard('B', 'Gains de carriere (${(poids.gains * 100).toStringAsFixed(0)}%)', 'Compare les gains totaux de chaque cheval par rapport aux autres partants. Un cheval aux forts gains indique un niveau de classe superieur.', const Color(0xFFFFD700), Icons.euro, poids.gains, 0.15),
        _buildMethodeCard('C', 'Record / Temps (${(poids.record * 100).toStringAsFixed(0)}%)', 'Compare le meilleur temps de chaque cheval dans la course. Un bon record sur la distance = vitesse pure adaptee.', const Color(0xFF42A5F5), Icons.timer, poids.record, 0.12),
        _buildMethodeCard('D', 'Regularite (${(poids.constance * 100).toStringAsFixed(0)}%)', 'Mesure la constance : un cheval qui finit souvent dans le top 5 est plus previsible qu\'un cheval avec des resultats irreguliers.', const Color(0xFFCE93D8), Icons.show_chart, poids.constance, 0.09),
        _buildMethodeCard('E', 'Cote marche (${(poids.cote * 100).toStringAsFixed(0)}%)', 'La cote PMU reflete l\'opinion de milliers de parieurs. Un outsider Ã  Ã14 peut avoir une cote justifiee par le jockey ou la distance.', const Color(0xFFFF9800), Icons.bar_chart, poids.cote, 0.08),
        _buildMethodeCard('F', 'Dist. specialisee (${(poids.distSpec * 100).toStringAsFixed(0)}%)', 'Analyse la forme du cheval filtree sur des distances similaires (Â±100 m). Corrige le biais de la forme globale : un cheval peut exceller sur 1850 m sans que sa musique generale le montre.', const Color(0xFF26C6DA), Icons.straighten, poids.distSpec, 0.08),
        _buildMethodeCard('G', 'Jockey/Driver (${(poids.jockey * 100).toStringAsFixed(0)}%)', 'Impact du jockey ou driver : un pilote Ã  20% de victoires sur un outsider est un signal fort que les autres parieurs ignorent souvent.', const Color(0xFFAB47BC), Icons.person, poids.jockey, 0.07),
        _buildMethodeCard('H', 'Victoires recentes (${(poids.victoires * 100).toStringAsFixed(0)}%)', 'Bonus momentum : un cheval qui vient de gagner a tendance Ã  confirmer. 5 victoires recentes = score maximum.', const Color(0xFFEF5350), Icons.emoji_events, poids.victoires, 0.04),
        _buildMethodeCard('I', 'Fraicheur physique (${(poids.repos * 100).toStringAsFixed(0)}%)', 'Jours de repos depuis la derniere course. Zone ideale : 14â35 jours. Au-delÃ  de 55 jours â risque de rouille. En-dessous de 7 jours â risque de fatigue.', const Color(0xFF66BB6A), Icons.hotel, poids.repos, 0.03),
        _buildMethodeCard('J', 'Vitesse/Discipline (${(poids.discipline * 100).toStringAsFixed(0)}%)', 'Compatibilite cheval/discipline et distance. Bonus si le record du cheval est particulierement adapte aux conditions du jour.', const Color(0xFF80DEEA), Icons.speed, poids.discipline, 0.02),
        _buildMethodeCard('K', 'Hippodrome (${(poids.hippo * 100).toStringAsFixed(0)}%)', 'Specialite de circuit : certains chevaux excellent sur un hippodrome precis (virages, nature de la piste, longueur des lignes droites). Historique filtre sur ce circuit.', const Color(0xFF4DB6AC), Icons.location_on, poids.hippo, 0.04),
        _buildMethodeCard('L', 'Entraineur (${(poids.entraineur * 100).toStringAsFixed(0)}%)', 'Taux de reussite de l\'entraineur sur ce type de course et cette distance. Un entraineur en forme avec une bonne forme d\'ecurie est un signal fort.', const Color(0xFFFFB74D), Icons.person_pin, poids.entraineur, 0.04),
        _buildMethodeCard('M', 'ELO dynamique (${(poids.elo * 100).toStringAsFixed(0)}%)', 'Score ELO calcule dynamiquement comme aux echecs : chaque course met Ã  jour la cote du cheval selon la force des adversaires battus ou par lesquels il a ete battu. Reflete le niveau reel.', const Color(0xFFBA68C8), Icons.trending_up, poids.elo, 0.05),
        _buildMethodeCard('N', 'Terrain (${(poids.terrain * 100).toStringAsFixed(0)}%)', 'Performance du cheval sur l\'etat de terrain du jour (souple, lourd, tres lourd, bonâ¦). Certains chevaux sont radicalement differents selon l\'etat du sol.', const Color(0xFF81C784), Icons.grass, poids.terrain, 0.05),
        _buildMethodeCard('O', 'Divergence forme/cote (${(poids.divergence * 100).toStringAsFixed(0)}%)', 'Detecte les "coups prepares" : un cheval avec une bonne forme recente mais une cote elevee (sous-estime par le marche) est une opportunite. Mesure l\'ecart forme â cote.', const Color(0xFFFF7043), Icons.compare_arrows, poids.divergence, 0.04),
        _buildMethodeCard('P', 'Poids porte (${(poids.poidsRel * 100).toStringAsFixed(0)}%)', 'Poids porte relatif au champ (galop uniquement). Un cheval leger face Ã  des chevaux lourdement charges a un avantage mecanique mesurable sur les longues distances.', const Color(0xFF90A4AE), Icons.fitness_center, poids.poidsRel, 0.03),
        _buildMethodeCard('Q', 'Progression carriere (${(poids.progression * 100).toStringAsFixed(0)}%)', 'Trajectoire de carriere du cheval : un jeune cheval en progression constante est plus dangereux que son palmares brut ne le suggere. Mesure la pente d\'amelioration sur les 10 dernieres courses.', const Color(0xFFF48FB1), Icons.rocket_launch, poids.progression, 0.03),
        _buildMethodeCard('R', 'Mouvement de cote (${(poids.mouvCote * 100).toStringAsFixed(0)}%)', 'Detecte les variations significatives de cote en temps reel. Une cote qui chute de â40% en moins de 15 min signale un cheval tres soutenu par les insiders â signal fort ignore par le grand public.', const Color(0xFFFF6E40), Icons.moving, poids.mouvCote, 0.02),
        _buildMethodeCard('S', 'Place au depart (${(poids.placeDepart * 100).toStringAsFixed(0)}%)', 'Position sur la grille de depart. En trot attele, la corde (position 1-2) est un avantage majeur. En galop, les rails interieurs sur les virages serres favorisent les chevaux de petit numero.', const Color(0xFFB2DFDB), Icons.looks_one, poids.placeDepart, 0.02),
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
              _buildBulletPt('Apres chaque course, l\'IA compare ses pronostics au resultat reel.'),
              _buildBulletPt('Pour chaque critere (Forme, Coteâ¦), elle mesure s\'il a bien discrimine les bons chevaux.'),
              _buildBulletPt('Si un critere etait predictif â son poids augmente pour les prochains pronostics.'),
              _buildBulletPt('Si un critere induisait en erreur â son poids diminue.'),
              _buildBulletPt('L\'IA apprend aussi des poids specifiques par discipline (Trot, Plat, Obstacle).'),
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
                Text('Ameliorations v3.1 de l\'algorithme', style: TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.bold, fontSize: 15)),
              ]),
              const SizedBox(height: 8),
              _buildBulletPt('Ponderation par recence : les courses recentes ont 3-4Ã plus d\'impact que les anciennes.'),
              _buildBulletPt('Gradient avec momentum : l\'IA memorise la tendance pour eviter les oscillations de poids.'),
              _buildBulletPt('Signal top-5 etendu : les chevaux 4e-5e contribuent partiellement Ã  l\'apprentissage.'),
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
          const labels = {'forme': 'Forme', 'gains': 'Gains', 'record': 'Record', 'cote': 'Cote', 'constance': 'Regularite', 'victoires': 'Victoires', 'discipline': 'Discipline'};
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
                'Apres calcul, tous les scores sont normalises de 0 Ã  100 par rapport au meilleur et au moins bon cheval du champ. Cela permet une comparaison objective entre courses.',
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
      'forme': 'Forme recente', 'gains': 'Gains', 'record': 'Record/Temps',
      'cote': 'Cote marche', 'constance': 'Regularite', 'victoires': 'Victoires',
      'discipline': 'Discipline', 'distSpec': 'Distance spec.', 'jockey': 'Jockey/Driver',
      'repos': 'Fraicheur', 'hippo': 'Hippodrome', 'entraineur': 'Entraineur',
      'elo': 'ELO dynamique', 'terrain': 'Terrain', 'divergence': 'Divergence',
      'poidsRel': 'Poids relatif', 'progression': 'Progression',
      'mouvCote': 'Mouv. cote', 'placeDepart': 'Place depart',
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
      diagnostic = 'â ï¸ Aucun apprentissage â poids encore aux valeurs initiales';
      diagColor = Colors.white38;
    } else if (deriveTotal < 0.05) {
      diagnostic = 'ð Poids quasi-inchanges (normal si < 2 semaines)';
      diagColor = Colors.orange;
    } else if (deriveTotal < 0.15) {
      diagnostic = 'ð Convergence moderee â ajustement progressif en cours';
      diagColor = _gold;
    } else {
      diagnostic = 'â Convergence forte â criteres significativement adaptes';
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
                style: const TextStyle(color: _gold, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(diagnostic, style: TextStyle(color: diagColor, fontSize: 13)),
        const SizedBox(height: 4),
        Text(
          'Derive totale vs valeurs initiales : ${(deriveTotal * 100).toStringAsFixed(1)} pts',
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),

        // ââ Historique jour par jour âââââââââââââââââââââââââââââââââââââââââ
        if (joursAffiches.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('Ãvolution des 3 criteres principaux (14j)',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 8),
          // Les 3 criteres les plus modifies = les plus interessants Ã  suivre
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
                      style: TextStyle(color: couleurCritere, fontSize: 12, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text(
                    'init: ${(defauts[c]! * 100).toStringAsFixed(0)}%  '
                    'â  actuel: ${(poids.getPoids(c) * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
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
                                    fontSize: 9,
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
        const Text('19 criteres â variation vs valeurs initiales :',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
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
                      style: const TextStyle(color: Colors.white70, fontSize: 13))),
              Text('$pctDef%', style: const TextStyle(color: Colors.white38, fontSize: 12)),
              const Text(' â ', style: TextStyle(color: Colors.white24, fontSize: 12)),
              Text('$pctAct%',
                  style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('$fleche $pctDiff%',
                    style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
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
                      fontSize: 12, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 4),
            const Text(
              'L\'IA apprend aussi le meilleur mix entre les criteres (Î1), '
              'la confiance IA, et le taux historique par type de pari.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
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
          'Si rien ne bouge apres 3+ semaines â les donnees API PMU '
          'atteignent peut-Ãªtre leur limite predictive.',
          style: TextStyle(color: Colors.white24, fontSize: 11),
        ),
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
            child: Text(nom, style: const TextStyle(color: Colors.white70, fontSize: 12))),
        Text('${(defaut * 100).toStringAsFixed(0)}%',
            style: const TextStyle(color: Colors.white38, fontSize: 12)),
        const Text(' â ', style: TextStyle(color: Colors.white24, fontSize: 12)),
        Text('${(actuel * 100).toStringAsFixed(1)}%',
            style: TextStyle(color: c, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(width: 6),
        Text('$fleche ${diff >= 0 ? '+' : ''}${(diff * 100).toStringAsFixed(1)}%',
            style: TextStyle(color: c, fontSize: 11)),
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
