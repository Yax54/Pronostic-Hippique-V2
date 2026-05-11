// ═══════════════════════════════════════════════════════════════════════════
//  IA PERFORMANCE SCREEN — Widgets secondaires
//  ★ v9.93 : Extrait de ia_performance_screen.dart pour réduire la taille.
//  Contient les widgets de lecture/affichage sans dépendances d'état mutable :
//    • _buildJournalCriteres, _buildStatutApprentissage
//    • _buildJournalCard, _buildPronosticCard, _buildPronosticCardAttente
//    • _buildSectionCorrelations, _buildSectionHippoXDisc
// ═══════════════════════════════════════════════════════════════════════════

part of 'ia_performance_screen.dart';

extension IaPerfSecondaryWidgets on _IaPerformanceScreenState {
  // ── Couleurs partagées (static const de la classe principale) ───────────
  Color get _card   => const Color(0xFF111F30);
  Color get _green  => const Color(0xFF4CAF7D);
  Color get _gold   => const Color(0xFFFFD700);
  Color get _purple => const Color(0xFF7C4DFF);

  Widget _buildJournalCriteres(IaMemoryService mem) {
    // Analyser les 7 derniers rapports pour détecter les tendances
    final rapports = mem.rapports.take(7).toList();
    if (rapports.length < 2) return const SizedBox();

    const labels = {
      'forme': 'Forme récente', 'gains': 'Gains carrière',
      'record': 'Record/Vitesse', 'cote': 'Cote marché',
      'constance': 'Régularité', 'victoires': 'Victoires récentes',
      'discipline': 'Compatibilité', 'distSpec': 'Distance spécifique',
      'jockey': 'Jockey/Driver', 'repos': 'Fraîcheur',
      'hippo': 'Hippodrome', 'entraineur': 'Entraîneur',
      'elo': 'ELO dynamique', 'terrain': 'Terrain',
      'divergence': 'Coup préparé', 'poidsRel': 'Poids porté',
      'progression': 'Progression', 'mouvCote': 'Mvt de cote',
      'placeDepart': 'Place départ', // ★ v9.93
    };

    // Calculer les variations de poids sur les 7 derniers jours
    final premier = rapports.last.poidsApres;   // le plus ancien
    final dernier  = rapports.first.poidsApres;  // le plus récent

    final variations = <String, double>{};
    for (final k in dernier.keys) {
      final avant = premier[k] ?? 0.0;
      final apres = dernier[k] ?? 0.0;
      final delta = apres - avant;
      if (delta.abs() > 0.001) variations[k] = delta;
    }

    if (variations.isEmpty) return const SizedBox();

    // Trier : plus fortes variations en premier
    final sorted = variations.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    final top = sorted.take(6).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      iaSectionTitle('📉 Évolution des critères (7 derniers jours)'),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Column(children: [
          // Explication contextuelle
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF7C4DFF).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline, color: Color(0xFF7C4DFF), size: 16),
              SizedBox(width: 8),
              Expanded(child: Text(
                'Ces mouvements reflètent ce que l\'IA a appris cette semaine. '
                'Un critère renforcé a bien discriminé les gagnants. '
                'Un critère réduit induisait en erreur.',
                style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
              )),
            ]),
          ),
          const SizedBox(height: 12),
          ...top.map((e) {
            final label   = labels[e.key] ?? e.key;
            final delta   = e.value;
            final isHausse = delta > 0;
            final color   = isHausse ? const Color(0xFF4CAF7D) : Colors.redAccent;
            final pct     = (delta * 100).abs();
            final sign    = isHausse ? '+' : '−';
            final icon    = isHausse ? Icons.trending_up : Icons.trending_down;
            final message = isHausse
                ? 'bien discriminé les gagnants cette semaine'
                : 'induisait en erreur — poids réduit';

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(icon, color: color, size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text(label,
                      style: const TextStyle(color: Colors.white, fontSize: 13,
                          fontWeight: FontWeight.w600))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: color.withValues(alpha: 0.35)),
                    ),
                    child: Text('$sign${pct.toStringAsFixed(1)}%',
                        style: TextStyle(color: color, fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ),
                ]),
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.only(left: 22),
                  child: Text(
                    isHausse
                        ? '↑ Ce critère a $message'
                        : '↓ Ce critère $message',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 11, height: 1.3),
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 22),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: (pct / 5.0).clamp(0.05, 1.0), // max à 5%
                      backgroundColor: Colors.white.withValues(alpha: 0.06),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                      minHeight: 4,
                    ),
                  ),
                ),
              ]),
            );
          }),
        ]),
      ),
    ]);
  }

  // ── Widget : Statut de l'apprentissage ─────────────────────────────────────

  Widget _buildStatutApprentissage(IaPoidsAdaptatifs poids, IaStats stats) {
    final misesAJour  = poids.nbMisesAJour;
    final calibration = poids.calibrationScore;
    // ★ v9.1 : Nombre de courses avec résultat pour la phase de stabilisation
    final nbAvecRes   = IaMemoryService.instance.pronosticsAvecResultat.length;

    String statutText;
    Color statutColor;
    String statutEmoji;
    String conseil;

    if (misesAJour == 0) {
      statutText = 'En apprentissage';
      statutColor = Colors.white38;
      statutEmoji = '🌱';
      conseil = 'Suivez des courses pour que l\'IA commence à apprendre';
    } else if (misesAJour < 5) {
      statutText = 'Apprentissage débutant';
      statutColor = const Color(0xFFFFB74D);
      statutEmoji = '📈';
      conseil = 'L\'IA apprend encore — continuez à suivre des courses';
    } else if (misesAJour < 15) {
      statutText = 'En progression';
      statutColor = _green;
      statutEmoji = '🧠';
      conseil = 'L\'IA commence à cerner les bons critères pour vos courses';
    } else {
      statutText = 'Bien entraîné';
      statutColor = _gold;
      statutEmoji = '⭐';
      conseil = 'L\'IA a suffisamment de données pour des prédictions optimisées';
    }

    // ★ v9.1 : Phase de stabilisation du gradient (seuil minimum anti-surapprentissage)
    final String phaseGradient;
    final Color  phaseColor;
    final String phaseExplication;
    if (nbAvecRes < 10) {
      phaseGradient    = '🔒 Poids figés ($nbAvecRes/10 courses)';
      phaseColor       = Colors.white38;
      phaseExplication = 'Les poids IA ne bougent pas encore — données insuffisantes pour éviter le surapprentissage';
    } else if (nbAvecRes < 30) {
      phaseGradient    = '🐢 Apprentissage prudent ($nbAvecRes/30 courses)';
      phaseColor       = const Color(0xFFFFB74D);
      phaseExplication = 'Taux d\'apprentissage réduit (×0.3) — l\'IA ajuste ses poids doucement';
    } else {
      phaseGradient    = '🚀 Apprentissage normal ($nbAvecRes courses)';
      phaseColor       = _green;
      phaseExplication = 'Taux d\'apprentissage complet — l\'IA optimise ses poids sur votre historique';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [statutColor.withValues(alpha: 0.12), _card],
          begin: Alignment.topLeft,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statutColor.withValues(alpha: 0.4)),
      ),
      child: Column(children: [
        Row(children: [
          Text(statutEmoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('IA : $statutText', style: TextStyle(color: statutColor, fontWeight: FontWeight.bold, fontSize: 16)),
              Text(conseil, style: const TextStyle(color: Colors.white54, fontSize: 16)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$misesAJour', style: TextStyle(color: statutColor, fontSize: 22, fontWeight: FontWeight.bold)),
            const Text('mises à jour', style: TextStyle(color: Colors.white38, fontSize: 15)),
          ]),
        ]),
        if (misesAJour > 0) ...[
          const SizedBox(height: 12),
          Row(children: [
            const Text('Calibration confiance :', style: TextStyle(color: Colors.white38, fontSize: 15)),
            const SizedBox(width: 8),
            Expanded(
              child: Stack(children: [
                Container(height: 6, decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(3),
                )),
                FractionallySizedBox(
                  widthFactor: (calibration / 100).clamp(0.0, 1.0),
                  child: Container(height: 6, decoration: BoxDecoration(
                    color: calibration > 60 ? _green : calibration > 40 ? const Color(0xFFFFB74D) : Colors.red,
                    borderRadius: BorderRadius.circular(3),
                  )),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            Text('${calibration.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.white54, fontSize: 15)),
          ]),
          const SizedBox(height: 4),
          Text(
            calibration > 60
              ? '✅ L\'IA est bien calibrée : elle est plus précise quand elle est confiante'
              : calibration > 40
                ? '➖ Calibration neutre : la confiance de l\'IA est en cours d\'étalonnage'
                : '⚠️ Calibration faible : la confiance de l\'IA ne prédit pas encore sa précision',
            style: const TextStyle(color: Colors.white24, fontSize: 15),
          ),
          // ★ v9.1 : Phase de stabilisation du gradient
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: phaseColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: phaseColor.withValues(alpha: 0.30)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(phaseGradient,
                    style: TextStyle(color: phaseColor, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 3),
                Text(phaseExplication,
                    style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
        ],
      ]),
    );
  }

  // ── Widget : Poids par discipline ──────────────────────────────────────────

  Widget _buildDisciplinePoidsCard(String discKey, IaPoidsAdaptatifs poids) {
    final poidsDisc = poids.poidsParDiscipline[discKey] ?? {};
    if (poidsDisc.isEmpty) return const SizedBox();

    final noms = {
      'trot_attele': '🏇 Trot Attelé',
      'trot_monte': '🏇 Trot Monté',
      'plat': '🐎 Plat',
      'obstacle': '🚧 Obstacle / Haies',
      'global': '🌐 Global',
    };

    final nomDisc = noms[discKey] ?? discKey;

    // Critère dominant pour cette discipline
    final critPrincipal = poidsDisc.entries.reduce((a, b) => a.value > b.value ? a : b);
    // ★ v5.0 : labels 10 critères
    final labels = {
      'forme': 'Forme', 'gains': 'Gains', 'record': 'Record',
      'cote': 'Cote', 'constance': 'Régularité', 'victoires': 'Victoires', 'discipline': 'Discipline',
      'distSpec': 'Dist. spécialisée', 'jockey': 'Jockey/Driver', 'repos': 'Fraîcheur',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _purple.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(nomDisc, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _purple.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${labels[critPrincipal.key] ?? critPrincipal.key} dominant (${(critPrincipal.value * 100).toStringAsFixed(0)}%)',
              style: TextStyle(color: _purple, fontSize: 15),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        _buildPoidsComparatifDisc('Forme',      poidsDisc['forme']     ?? 0.38, 0.38, _green),
        _buildPoidsComparatifDisc('Cote',       poidsDisc['cote']      ?? 0.13, 0.13, const Color(0xFFFF9800)),
        _buildPoidsComparatifDisc('Gains',      poidsDisc['gains']     ?? 0.18, 0.18, _gold),
        _buildPoidsComparatifDisc('Record',     poidsDisc['record']    ?? 0.14, 0.14, const Color(0xFF42A5F5)),
        _buildPoidsComparatifDisc('Régularité', poidsDisc['constance'] ?? 0.09, 0.09, const Color(0xFFCE93D8)),
      ]),
    );
  }

  Widget _buildPoidsComparatifDisc(String label, double valeur, double defaut, Color color) {
    final diff = valeur - defaut;
    final isUp = diff > 0.005;
    final isDown = diff < -0.005;
    final pct = (valeur * 100).toStringAsFixed(0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(width: 80, child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 15))),
        Expanded(
          child: Stack(children: [
            Container(height: 10, decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(5),
            )),
            // Ligne de référence (défaut)
            FractionallySizedBox(
              widthFactor: (defaut / 0.55).clamp(0.0, 1.0),
              child: Container(height: 10, decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(5),
              )),
            ),
            // Valeur apprise
            FractionallySizedBox(
              widthFactor: (valeur / 0.55).clamp(0.0, 1.0),
              child: Container(height: 10, decoration: BoxDecoration(
                color: color.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(5),
              )),
            ),
          ]),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 50,
          child: Row(children: [
            Text('$pct%', style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold)),
            if (isUp) const Text(' ↑', style: TextStyle(color: Colors.greenAccent, fontSize: 16))
            else if (isDown) const Text(' ↓', style: TextStyle(color: Colors.redAccent, fontSize: 16)),
          ]),
        ),
      ]),
    );
  }

  // ── Widget : Journal d'apprentissage ───────────────────────────────────────

  Widget _buildJournalCard(JournalEntree e) {
    final methode = e.methode ?? 'gradient';
    Color methodeColor;
    String methodeLabel;
    String methodeEmoji;

    switch (methode) {
      case 'gradient':
        methodeColor = _green;
        methodeLabel = 'Gradient global';
        methodeEmoji = '🔬';
        break;
      case 'discipline_gradient':
        methodeColor = _purple;
        methodeLabel = e.discipline.isNotEmpty ? e.discipline : 'Discipline';
        methodeEmoji = '🏇';
        break;
      case 'regles':
        methodeColor = const Color(0xFFFF9800);
        methodeLabel = 'Règles basiques';
        methodeEmoji = '⚙️';
        break;
      case 'journee_atypique': // ★ v9.93
        methodeColor = Colors.redAccent;
        methodeLabel = 'Journée atypique';
        methodeEmoji = '⚠️';
        break;
      case 'annulation_atypique': // ★ v9.93
        methodeColor = _green;
        methodeLabel = 'Atypique annulée';
        methodeEmoji = '✅';
        break;
      default:
        methodeColor = Colors.white38;
        methodeLabel = methode;
        methodeEmoji = '🧠';
    }

    final scoreColor = e.scorePerf >= 60 ? _green : e.scorePerf >= 35 ? const Color(0xFFFF9800) : Colors.redAccent;
    final isAtypique = methode == 'journee_atypique';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: methodeColor.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(methodeEmoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.nomCourse, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: methodeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(methodeLabel, style: TextStyle(color: methodeColor, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 6),
                Text('${e.nbCoursesAnalysees} courses', style: const TextStyle(color: Colors.white24, fontSize: 15)),
              ]),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${e.scorePerf.toStringAsFixed(0)}/100', style: TextStyle(color: scoreColor, fontWeight: FontWeight.bold, fontSize: 15)),
            Text(_timeAgo(e.date), style: const TextStyle(color: Colors.white24, fontSize: 16)),
        ]),
        ]),
        const SizedBox(height: 8),
        // Deltas des poids
        _buildDeltasPoids(e.avant, e.apres),
        // Résumé du diagnostic (première ligne)
        const SizedBox(height: 6),
        Text(
          e.diagnostic.split('\n').firstWhere((l) => l.isNotEmpty, orElse: () => ''),
          style: const TextStyle(color: Colors.white38, fontSize: 15),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        // ★ v9.93 : Bouton annulation journée atypique
        if (isAtypique) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => _confirmerAnnulationAtypique(e.date),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.undo, color: Colors.orange, size: 15),
                SizedBox(width: 6),
                Text('Annuler la pondération — recalculer normalement',
                    style: TextStyle(color: Colors.orange, fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }

  // ★ v9.93 : Confirmation avant annulation journée atypique
  void _confirmerAnnulationAtypique(DateTime date) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1B2A),
        title: const Row(children: [
          Icon(Icons.warning_amber, color: Colors.orange),
          SizedBox(width: 8),
          Text('Annuler la pondération ?',
              style: TextStyle(color: Colors.white, fontSize: 16)),
        ]),
        content: Text(
          'L\'IA recalculera le gradient du ${date.day}/${date.month}/${date.year} '
          'avec un facteur ×1.0 (normal) au lieu de ×0.3.\n\n'
          'Faites ça uniquement si vous estimez que l\'IA aurait dû apprendre '
          'normalement de cette journée.',
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () {
              Navigator.pop(context);
              IaMemoryService.instance.annulerJourneeAtypique(date);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('✅ Gradient recalculé normalement'),
                backgroundColor: Color(0xFF4CAF7D),
                duration: Duration(seconds: 2),
              ));
            },
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }

  Widget _buildDeltasPoids(Map<String, double> avant, Map<String, double> apres) {
    final labels = {'forme': 'F', 'gains': 'G', 'record': 'R', 'cote': 'C', 'constance': 'Rg', 'victoires': 'V', 'discipline': 'D'};
    final deltas = <Widget>[];

    for (final key in ['forme', 'gains', 'record', 'cote', 'constance', 'victoires']) {
      final av = avant[key] ?? 0;
      final ap = apres[key] ?? av;
      final diff = ap - av;
      if (diff.abs() < 0.003) continue;

      final color = diff > 0 ? Colors.greenAccent : Colors.redAccent;
      final sign = diff > 0 ? '+' : '';
      deltas.add(Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          '${labels[key] ?? key}: $sign${(diff * 100).toStringAsFixed(1)}%',
          style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ));
    }

    if (deltas.isEmpty) {
      return const Text('Aucun changement significatif', style: TextStyle(color: Colors.white24, fontSize: 15));
    }

    return Wrap(children: deltas);
  }

  static String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours}h';
    if (diff.inDays < 7) return 'il y a ${diff.inDays}j';
    return '${date.day}/${date.month}';
  }

  Widget _buildPoidsBar(String label, double valeur, double defaut, Color color) {
    final pct     = (valeur * 100).toStringAsFixed(0);
    final defautPct = (defaut * 100).toStringAsFixed(0);
    final diff    = valeur - defaut;
    final isUp    = diff > 0.005;
    final isDown  = diff < -0.005;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.white60, fontSize: 15))),
        Expanded(
          child: Stack(
            children: [
              // Barre fond
              Container(height: 14, decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(7),
              )),
              // Barre défaut (gris)
              FractionallySizedBox(
                widthFactor: defaut / 0.55,
                child: Container(height: 14, decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                )),
              ),
              // Barre actuelle
              FractionallySizedBox(
                widthFactor: (valeur / 0.55).clamp(0.0, 1.0),
                child: Container(height: 14, decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(7),
                )),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 52,
          child: Row(children: [
            Text('$pct%', style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold)),
            if (isUp) const Text(' ↑', style: TextStyle(color: Colors.greenAccent, fontSize: 15))
            else if (isDown) const Text(' ↓', style: TextStyle(color: Colors.redAccent, fontSize: 15))
            else Text(' =$defautPct%', style: TextStyle(color: Colors.white24, fontSize: 16)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildStatCard(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(children: [
          Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 15), textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  Widget _buildPronosticCard(IaPronostic p) {
    final topIA   = p.topNIA.take(5).toList();
    final arrivee = p.arriveeReelle?.take(5).toList() ?? [];
    final rang    = p.rangFavoriIaDansArrivee;
    final score   = p.scorePerformance ?? 0;

    Color scoreCol;
    String scoreEmoji;
    if (score >= 70)      { scoreCol = _green; scoreEmoji = '🎯'; }
    else if (score >= 40) { scoreCol = const Color(0xFFFF9800); scoreEmoji = '👍'; }
    else                  { scoreCol = const Color(0xFFEF5350); scoreEmoji = '😔'; }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scoreCol.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('$scoreEmoji ', style: const TextStyle(fontSize: 16)),
          Expanded(
            child: Text(p.nomCourse, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: scoreCol.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('${score.toStringAsFixed(0)}/100', style: TextStyle(color: scoreCol, fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          // Pronostic IA
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('IA prédit :', style: TextStyle(color: Colors.white38, fontSize: 15)),
              Wrap(spacing: 4, children: topIA.asMap().entries.map((e) {
                final colors = [_gold, _green, const Color(0xFF42A5F5), const Color(0xFFFF9800), const Color(0xFFCE93D8)];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors[e.key % colors.length].withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: colors[e.key % colors.length].withValues(alpha: 0.4)),
                  ),
                  child: Text('N°${e.value}', style: TextStyle(color: colors[e.key % colors.length], fontSize: 15, fontWeight: FontWeight.bold)),
                );
              }).toList()),
            ]),
          ),
          const SizedBox(width: 8),
          // Arrivée réelle
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Arrivée réelle :', style: TextStyle(color: Colors.white38, fontSize: 15)),
              Wrap(spacing: 4, children: arrivee.asMap().entries.map((e) {
                final isIATop = topIA.take(5).contains(e.value.toString());
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: isIATop ? _green.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: isIATop ? _green.withValues(alpha: 0.5) : Colors.white12),
                  ),
                  child: Text('N°${e.value}', style: TextStyle(
                    color: isIATop ? _green : Colors.white54,
                    fontSize: 15,
                    fontWeight: isIATop ? FontWeight.bold : FontWeight.normal,
                  )),
                );
              }).toList()),
            ]),
          ),
        ]),
        if (rang != null) ...[
          const SizedBox(height: 4),
          Text(
            rang == 1 ? '✅ Favori IA en 1ère place !' : rang <= 3 ? '👍 Favori IA en $rang ème place' : '😔 Favori IA en $rang e place',
            style: TextStyle(color: rang <= 3 ? _green : Colors.white38, fontSize: 15),
          ),
        ],
      ]),
    );
  }

  // ★ v9.92 POINT 4 : Section précision hippodrome × discipline ───────────────
  // ★ v9.93 POINT 2 : Corrélations entre critères ──────────────────────────
  Widget _buildSectionCorrelations() {
    final corr = IaMemoryService.instance.poids.correlations;
    if (corr.isEmpty) return const SizedBox();

    const labels = {
      'forme': 'Forme', 'gains': 'Gains', 'record': 'Record',
      'cote': 'Cote', 'constance': 'Régularité', 'victoires': 'Victoires',
      'discipline': 'Discipline', 'distSpec': 'Distance', 'jockey': 'Jockey',
      'repos': 'Fraîcheur', 'hippo': 'Hippodrome', 'entraineur': 'Entraîneur',
      'elo': 'ELO', 'terrain': 'Terrain', 'divergence': 'Coup préparé',
      'poidsRel': 'Poids porté', 'progression': 'Progression',
      'mouvCote': 'Mvt cote', 'placeDepart': 'Place départ',
    };

    final sorted = corr.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      iaSectionTitle('🔗 Corrélations entre critères'),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline, color: Colors.orange, size: 15),
              SizedBox(width: 8),
              Expanded(child: Text(
                'Deux critères très corrélés mesurent la même chose — l\'IA '
                'peut surpondérer cette information. r > 0.80 = fort, r > 0.65 = modéré.',
                style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.4),
              )),
            ]),
          ),
          const SizedBox(height: 12),
          ...sorted.take(8).map((e) {
            final parts = e.key.split('|');
            if (parts.length < 2) return const SizedBox();
            final c1    = labels[parts[0]] ?? parts[0];
            final c2    = labels[parts[1]] ?? parts[1];
            final r     = e.value;
            final color = r >= 0.80 ? Colors.redAccent
                : r >= 0.70 ? Colors.orange
                : const Color(0xFFFFD700);
            final label = r >= 0.80 ? 'Forte'
                : r >= 0.70 ? 'Modérée' : 'Faible';
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('$c1  ↔  $c2',
                      style: const TextStyle(color: Colors.white70,
                          fontSize: 13, fontWeight: FontWeight.w600))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: color.withValues(alpha: 0.4)),
                    ),
                    child: Text('r = ${r.toStringAsFixed(2)} · $label',
                        style: TextStyle(color: color, fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                ]),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: r.clamp(0.0, 1.0),
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 4,
                  ),
                ),
                if (r >= 0.75)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '⚠️ Ces critères se chevauchent — l\'IA peut les rééquilibrer.',
                      style: TextStyle(color: color.withValues(alpha: 0.65),
                          fontSize: 10, fontStyle: FontStyle.italic),
                    ),
                  ),
              ]),
            );
          }),
          if (sorted.length > 8)
            Text('+ ${sorted.length - 8} autres paires',
                style: const TextStyle(color: Colors.white24, fontSize: 11)),
        ]),
      ),
    ]);
  }

  Widget _buildSectionHippoXDisc() {
    final data = IaMemoryService.instance.precisionHippodromeXDiscipline;
    if (data.isEmpty) return const SizedBox();

    // Trier par nb décroissant
    final sorted = data.entries.toList()
      ..sort((a, b) => (b.value['nb'] as int).compareTo(a.value['nb'] as int));

    // Regrouper par hippodrome pour affichage hiérarchique
    final Map<String, List<MapEntry<String, Map<String, dynamic>>>> parHippo = {};
    for (final e in sorted) {
      final parts = e.key.split('|');
      if (parts.length < 2) continue;
      parHippo.putIfAbsent(parts[0], () => []).add(e);
    }
    if (parHippo.isEmpty) return const SizedBox();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 16),
      iaSectionTitle('🏇 Précision IA par hippodrome × discipline'),
      const SizedBox(height: 8),
      ...parHippo.entries.map((hippoEntry) {
        final hippo = hippoEntry.key;
        final disciplines = hippoEntry.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(hippo, style: const TextStyle(color: Colors.white,
                fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...disciplines.map((e) {
              final parts = e.key.split('|');
              final disc  = parts.length > 1 ? parts[1] : '?';
              final nb    = e.value['nb'] as int;
              final tGag  = (e.value['tauxGagnant'] as double) * 100;
              final tTop3 = (e.value['tauxTop3']    as double) * 100;
              final fiable = e.value['fiable'] as bool;
              final color = tGag >= 40
                  ? const Color(0xFF4CAF7D)
                  : tGag >= 25
                      ? const Color(0xFFFFB74D)
                      : Colors.redAccent;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Container(width: 3, height: 32,
                      decoration: BoxDecoration(color: color,
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 8),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(disc, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      Text('$nb course${nb > 1 ? "s" : ""}${fiable ? "" : " — peu de données"}',
                          style: TextStyle(color: fiable ? Colors.white38 : Colors.orange,
                              fontSize: 10)),
                    ],
                  )),
                  Text('${tGag.toStringAsFixed(0)}% gagnant',
                      style: TextStyle(color: color, fontSize: 12,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Text('${tTop3.toStringAsFixed(0)}% top3',
                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
                ]),
              );
            }),
          ]),
        );
      }),
    ]);
  }

  Widget _buildPronosticCardAttente(IaPronostic p) {
    final topIA = p.topNIA.take(5).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(children: [
        const Text('⏳', style: TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.nomCourse, style: const TextStyle(color: Colors.white70, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('IA : ${topIA.take(5).map((n) => "N°$n").join(" · ")}', style: const TextStyle(color: Colors.white38, fontSize: 15)),
          ]),
        ),
        const Text('En attente', style: TextStyle(color: Colors.white24, fontSize: 15)),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ v10.24 — Feature #5 : Calendrier des performances mensuelles
  //  Grille 7 colonnes (Lun→Dim) colorée par résultat IA :
  //   • Vert  : au moins 1 favori IA gagnant (rang 1)
  //   • Rouge : courses analysées mais aucun gagnant
  //   • Gris  : aucune course ce jour
  //  Navigation mois précédent / suivant — score moyen du mois en bas.
  // ══════════════════════════════════════════════════════════════════════════

  // ── State local du calendrier (mois affiché) ────────────────────────────
  // On stocke dans un Map sur l'extension pour éviter un StatefulWidget lourd.
  // Dart extensions ne supportent pas le state mutable directement,
  // on utilise donc un champ sur _IaPerformanceScreenState via _calMoisOffset.

  Widget _buildCalendrierPerformances() {
    final historique = IaMemoryService.instance.pronosticsAvecResultat;
    if (historique.isEmpty) return const SizedBox();

    // Mois à afficher : aujourd'hui + offset (stocké sur l'écran parent)
    final now     = DateTime.now();
    final moisRef = DateTime(now.year, now.month + _calMoisOffset, 1);
    final moisLabel = _nomMois(moisRef.month);

    // ── Agréger par jour ─────────────────────────────────────────────────
    // Map<jourDuMois, {nbCourses, nbGagnants, scoreTotal}>
    final Map<int, _JourCal> parJour = {};
    for (final p in historique) {
      final d = p.datePronostic;
      if (d.year != moisRef.year || d.month != moisRef.month) continue;
      final j = parJour.putIfAbsent(d.day, () => _JourCal());
      j.nbCourses++;
      if (p.rangFavoriIaDansArrivee == 1) j.nbGagnants++;
      j.scoreTotal += p.scorePerformance ?? 0;
    }

    // ── Dimensions grille ─────────────────────────────────────────────────
    final dernierJour  = DateTime(moisRef.year, moisRef.month + 1, 0).day;
    // 1 = lundi … 7 = dimanche
    final premierWday  = DateTime(moisRef.year, moisRef.month, 1).weekday; // 1-7
    final nbCasesAvant = premierWday - 1; // décalage pour aligner lundi

    // ── Calcul stats du mois ──────────────────────────────────────────────
    int totalCourses  = 0;
    int totalGagnants = 0;
    int joursActifs   = 0;
    for (final j in parJour.values) {
      totalCourses  += j.nbCourses;
      totalGagnants += j.nbGagnants;
      if (j.nbCourses > 0) joursActifs++;
    }
    final tauxMois = totalCourses > 0
        ? (totalGagnants / totalCourses * 100)
        : 0.0;

    // Peut-on naviguer vers le mois suivant ?
    final peutSuivant = _calMoisOffset < 0;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      iaSectionTitle('📅 Calendrier des performances'),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF111F30),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Column(children: [

          // ── En-tête navigation mois ───────────────────────────────────
          Row(children: [
            // Bouton précédent
            _calNavBtn(Icons.chevron_left, () {
              // ignore: invalid_use_of_protected_member
              setState(() => _calMoisOffset--);
            }),
            Expanded(
              child: Text(
                '$moisLabel ${moisRef.year}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // Bouton suivant (désactivé si mois courant)
            _calNavBtn(
              Icons.chevron_right,
              // ignore: invalid_use_of_protected_member
              peutSuivant ? () { setState(() => _calMoisOffset++); } : null,
            ),
          ]),
          const SizedBox(height: 12),

          // ── Labels jours de la semaine ────────────────────────────────
          Row(children: ['L','M','M','J','V','S','D'].map((lbl) =>
            Expanded(
              child: Text(lbl,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ).toList()),
          const SizedBox(height: 6),

          // ── Grille des jours ──────────────────────────────────────────
          _buildGrilleJours(
            dernierJour:  dernierJour,
            nbCasesAvant: nbCasesAvant,
            parJour:      parJour,
            moisRef:      moisRef,
            now:          now,
          ),
          const SizedBox(height: 14),

          // ── Légende ───────────────────────────────────────────────────
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _calLegende(const Color(0xFF2E7D52), '✓ Gagnant'),
            const SizedBox(width: 14),
            _calLegende(const Color(0xFF7B1E1E), 'Raté'),
            const SizedBox(width: 14),
            _calLegende(const Color(0xFF1A2535), 'Repos'),
          ]),
          const SizedBox(height: 14),

          // ── Bilan du mois ─────────────────────────────────────────────
          if (joursActifs > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _calStat('$joursActifs', 'jours actifs',
                      const Color(0xFF42A5F5)),
                  _calDivider(),
                  _calStat('$totalCourses', 'courses',
                      Colors.white54),
                  _calDivider(),
                  _calStat('$totalGagnants', 'gagnants',
                      const Color(0xFF4CAF7D)),
                  _calDivider(),
                  _calStat('${tauxMois.toStringAsFixed(0)}%', 'réussite',
                      tauxMois >= 35
                          ? const Color(0xFF4CAF7D)
                          : tauxMois >= 20
                              ? const Color(0xFFFFB74D)
                              : const Color(0xFFEF5350)),
                ],
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Aucune course analysée ce mois',
                style: TextStyle(color: Colors.white38, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
        ]),
      ),
      const SizedBox(height: 16),
    ]);
  }

  // ── Grille des cases jour ─────────────────────────────────────────────────
  Widget _buildGrilleJours({
    required int                dernierJour,
    required int                nbCasesAvant,
    required Map<int, _JourCal> parJour,
    required DateTime           moisRef,
    required DateTime           now,
  }) {
    final List<Widget> rows = [];
    final List<Widget> caseSemaine = [];

    // Cases vides avant le 1er
    for (int i = 0; i < nbCasesAvant; i++) {
      caseSemaine.add(const Expanded(child: SizedBox(height: 36)));
    }

    for (int jour = 1; jour <= dernierJour; jour++) {
      final data       = parJour[jour];
      final estAuj     = now.year  == moisRef.year &&
                         now.month == moisRef.month &&
                         now.day   == jour;
      final estFutur   = DateTime(moisRef.year, moisRef.month, jour)
                           .isAfter(now);

      // Couleur de fond
      Color bgColor;
      Color textColor;
      Color borderColor;
      String? badge;

      if (data == null || estFutur) {
        bgColor     = const Color(0xFF1A2535);
        textColor   = estFutur ? Colors.white12 : Colors.white24;
        borderColor = Colors.transparent;
      } else if (data.nbGagnants > 0) {
        // Vert — intensité selon nb gagnants
        final intensity = (data.nbGagnants / (data.nbCourses)).clamp(0.3, 1.0);
        bgColor     = Color.lerp(
          const Color(0xFF1B3A2A),
          const Color(0xFF2E7D52),
          intensity,
        )!;
        textColor   = const Color(0xFF80CBC4);
        borderColor = const Color(0xFF4CAF7D).withValues(alpha: 0.5);
        badge       = data.nbGagnants > 1 ? '×${data.nbGagnants}' : null;
      } else {
        // Rouge — courses analysées, aucun gagnant
        bgColor     = const Color(0xFF3A1B1B);
        textColor   = const Color(0xFFEF9A9A);
        borderColor = const Color(0xFFEF5350).withValues(alpha: 0.3);
      }

      caseSemaine.add(Expanded(
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: estAuj
                    ? const Color(0xFFFFD700).withValues(alpha: 0.8)
                    : borderColor,
                width: estAuj ? 1.5 : 0.8,
              ),
            ),
            child: Stack(alignment: Alignment.center, children: [
              Text(
                '$jour',
                style: TextStyle(
                  color: estAuj ? const Color(0xFFFFD700) : textColor,
                  fontSize: 12,
                  fontWeight: estAuj
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
              // Badge nb gagnants en haut à droite
              if (badge != null)
                Positioned(
                  top: 1, right: 2,
                  child: Text(badge,
                    style: const TextStyle(
                      color: Color(0xFF4CAF7D),
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ));

      // Nouvelle ligne toutes les 7 cases
      if ((nbCasesAvant + jour) % 7 == 0 || jour == dernierJour) {
        // Compléter la dernière ligne avec des cases vides
        if (jour == dernierJour && caseSemaine.length < 7) {
          while (caseSemaine.length < 7) {
            caseSemaine.add(const Expanded(child: SizedBox(height: 36)));
          }
        }
        rows.add(Row(children: List.from(caseSemaine)));
        rows.add(const SizedBox(height: 2));
        caseSemaine.clear();
      }
    }

    return Column(children: rows);
  }

  // ── Helpers UI calendrier ─────────────────────────────────────────────────

  Widget _calNavBtn(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: onTap != null
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon,
          color: onTap != null ? Colors.white70 : Colors.white12,
          size: 20,
        ),
      ),
    );
  }

  Widget _calLegende(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 12, height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
    ]);
  }

  Widget _calStat(String value, String label, Color color) {
    return Column(children: [
      Text(value,
        style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
      Text(label,
        style: const TextStyle(color: Colors.white38, fontSize: 11)),
    ]);
  }

  Widget _calDivider() => Container(
    width: 1, height: 28,
    color: Colors.white.withValues(alpha: 0.07),
  );

  String _nomMois(int m) => const [
    '', 'Janvier','Février','Mars','Avril','Mai','Juin',
    'Juillet','Août','Septembre','Octobre','Novembre','Décembre',
  ][m];
}

// ── Data class légère pour l'agrégation par jour ───────────────────────────
class _JourCal {
  int    nbCourses  = 0;
  int    nbGagnants = 0;
  double scoreTotal = 0;
}

