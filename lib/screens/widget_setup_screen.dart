import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/alert_service.dart';

/// ══════════════════════════════════════════════════════════════════════════════
/// WidgetSetupScreen — Guide du widget + raccourcis Pronostic Hippique
///
/// Explique comment utiliser les fonctionnalités de l'app.
/// Les widgets natifs Android nécessitent une configuration spéciale non
/// disponible dans cette version — remplacé par un guide de raccourcis utiles.
/// ══════════════════════════════════════════════════════════════════════════════

class WidgetSetupScreen extends StatefulWidget {
  const WidgetSetupScreen({super.key});

  @override
  State<WidgetSetupScreen> createState() => _WidgetSetupScreenState();
}

class _WidgetSetupScreenState extends State<WidgetSetupScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  static const _kGold   = Color(0xFFFFD700);
  static const _kBg     = Color(0xFF0D1B2A);
  static const _kCard   = Color(0xFF111F30);
  static const _kGreen  = Color(0xFF4CAF7D);
  static const _kDgreen = Color(0xFF2E7D52);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1628),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('⚙️ Paramètres & Raccourcis',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            Text('Configuration de l\'application',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
          ],
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: _kGold,
          labelColor: _kGold,
          unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: '📱 Raccourcis'),
            Tab(text: '🏇 Sites de paris'),
            Tab(text: '⏰ Notifications'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildTabRaccourcis(),
          _buildTabBookmakers(),
          _buildTabNotifications(),
        ],
      ),
    );
  }

  // ── Onglet 1 : Raccourcis ────────────────────────────────────────────────────

  Widget _buildTabRaccourcis() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [

        // Aperçu app
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A3A5C), Color(0xFF0D1B2A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              const Text('🏇', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 8),
              const Text('Pronostic Hippique', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Pronostics IA pour les courses hippiques', style: TextStyle(color: Colors.white54, fontSize: 14), textAlign: TextAlign.center),
              const SizedBox(height: 14),
              _buildStatRow(),
            ],
          ),
        ),
        const SizedBox(height: 20),

        _sectionTitle('📋 Guide d\'utilisation rapide'),
        const SizedBox(height: 10),

        _buildGuideStep(
          '1', Icons.calendar_today, _kGreen,
          'Programme du jour',
          'Onglet "Programme" → Consultez toutes les réunions du lendemain avec leurs courses et partants inscrits.',
        ),
        _buildGuideStep(
          '2', Icons.sports, _kGold,
          'Courses & Pronostics IA',
          'Onglet "Courses" → Sélectionnez une réunion → Chaque course affiche le Top 3 IA avec scores de confiance.',
        ),
        _buildGuideStep(
          '3', Icons.auto_awesome, const Color(0xFF7C4DFF),
          'Conseils personnalisés',
          'Onglet "Conseils" → L\'IA trie toutes les courses par niveau de confiance. Les meilleures opportunités en premier.',
        ),
        _buildGuideStep(
          '4', Icons.emoji_events, _kGold,
          'Best Bet du jour',
          'Onglet "Best Bet" → La sélection automatique du meilleur pari de la journée avec gain estimé.',
        ),
        _buildGuideStep(
          '5', Icons.euro, _kGreen,
          'Placer un pari',
          'Bouton "Parier" sur n\'importe quelle course → Choisissez le cheval, la mise, le type de pari → Comparez les cotes sur PMU, Betclic, Winamax...',
        ),
        _buildGuideStep(
          '6', Icons.psychology, const Color(0xFF7C4DFF),
          'IA Stats & Méthodologie',
          'Onglet "IA Stats" → Consultez les performances de l\'algorithme IA et les conseils de stratégie.',
        ),
        _buildGuideStep(
          '7', Icons.track_changes, const Color(0xFFFF9800),
          'Mes Paris',
          'Onglet "Mes Paris" → Gérez vos paris enregistrés et activez les alertes de départ.',
        ),

        const SizedBox(height: 20),
        _sectionTitle('💡 Astuces'),
        const SizedBox(height: 10),

        _buildAstuce('🌅 Chaque matin', 'Consultez l\'onglet Best Bet pour trouver la meilleure opportunité du jour.'),
        _buildAstuce('⏰ 30 min avant', 'Vérifiez les Mes Paris pour rappel de mise sur vos courses suivies.'),
        _buildAstuce('📊 Score > 80', 'Un score IA supérieur à 80/100 indique une forte confiance — idéal pour le Simple Gagnant.'),
        _buildAstuce('🎯 Top 5 IA', 'Dans 84% des cas, le vrai gagnant est dans le Top 5 sélectionné par l\'IA.'),
        _buildAstuce('💶 Comparez les cotes', 'Utilisez l\'onglet "Sites" du BetSheet pour trouver la meilleure cote entre bookmakers.'),

        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildStatRow() {
    final alertSvc = AlertService.instance;
    final nbParis = alertSvc.trackedCourses.length;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildStatBadge('$nbParis', 'Paris\nsuivis', _kGreen),
        _buildStatBadge('84%', 'Top 5 IA\ncontient le gagnant', _kGold),
        _buildStatBadge('6', 'Sites de\nparis intégrés', const Color(0xFF7C4DFF)),
      ],
    );
  }

  Widget _buildStatBadge(String val, String label, Color color) {
    return Column(children: [
      Text(val, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 14), textAlign: TextAlign.center),
    ]);
  }

  Widget _buildGuideStep(String num, IconData icon, Color color, String titre, String desc) {
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
            width: 34, height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Text(num, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(icon, color: color, size: 15),
                  const SizedBox(width: 6),
                  Text(titre, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ]),
                const SizedBox(height: 4),
                Text(desc, style: const TextStyle(color: Colors.white54, fontSize: 14, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAstuce(String titre, String desc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titre, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(desc, style: const TextStyle(color: Colors.white38, fontSize: 14, height: 1.4)),
          ),
        ],
      ),
    );
  }

  // ── Onglet 2 : Sites de paris ────────────────────────────────────────────────

  Widget _buildTabBookmakers() {
    final bookmakers = [
      _BookmakerInfo(
        nom: 'PMU', emoji: '🇫🇷', color: const Color(0xFF1B5E20),
        url: 'https://www.pmu.fr/turf/offre/courses',
        description: 'L\'opérateur officiel français des paris hippiques. Toutes les courses françaises disponibles.',
        bonus: 'Pas de bonus d\'inscription',
        avantage: 'Cotes officielles PMU, Paris Quinté+, iOS/Android',
        marge: 'Marge 18-20% (cotes plus basses)',
      ),
      _BookmakerInfo(
        nom: 'Betclic', emoji: '🔵', color: const Color(0xFF1565C0),
        url: 'https://www.betclic.fr/hippisme-s7',
        description: 'Leader des paris sportifs en France. Très bonnes cotes hippisme.',
        bonus: 'Jusqu\'à 100€ offerts à l\'inscription',
        avantage: 'Meilleures cotes hippisme, interface moderne',
        marge: 'Marge 8-10% (meilleures cotes)',
      ),
      _BookmakerInfo(
        nom: 'Winamax', emoji: '🃏', color: const Color(0xFFE53935),
        url: 'https://www.winamax.fr/paris-sportifs/sports/16',
        description: 'Excellent pour les paris hippiques avec des cotes compétitives.',
        bonus: '1er pari remboursé jusqu\'à 200€',
        avantage: 'Cash out, streaming, app mobile top',
        marge: 'Marge 8-12%',
      ),
      _BookmakerInfo(
        nom: 'Unibet', emoji: '🟢', color: const Color(0xFF2E7D32),
        url: 'https://www.unibet.fr/sport/horse-racing',
        description: 'Leader européen des paris sportifs. Solide offre hippisme.',
        bonus: '100€ de bonus sans conditions',
        avantage: 'Streaming des courses, app ergonomique',
        marge: 'Marge 10-14%',
      ),
      _BookmakerInfo(
        nom: 'ZEbet', emoji: '⚡', color: const Color(0xFFF57F17),
        url: 'https://www.zebet.fr/fr/sport/52-horse_racing',
        description: 'Spécialiste hippisme français. Cotes boostées régulières.',
        bonus: '100€ offerts + freebets',
        avantage: 'Spécialiste hippisme, cotes boostées',
        marge: 'Marge 9-11%',
      ),
      _BookmakerInfo(
        nom: 'ParionsSport', emoji: '🏅', color: const Color(0xFF4527A0),
        url: 'https://www.enligne.parionssport.fdj.fr/paris-hippiques',
        description: 'L\'offre de paris en ligne de la FDJ. Fiable et sécurisé.',
        bonus: '150€ de bonus',
        avantage: 'FDJ officiel, largement disponible',
        marge: 'Marge 12-15%',
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _kGold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kGold.withValues(alpha: 0.3)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.lightbulb_outline, color: _kGold, size: 18),
                SizedBox(width: 8),
                Text('Conseil IA', style: TextStyle(color: _kGold, fontWeight: FontWeight.bold, fontSize: 14)),
              ]),
              SizedBox(height: 6),
              Text(
                'Comparez toujours les cotes ! Un même cheval peut avoir une cote 10-15% plus élevée sur Betclic ou ZEbet vs PMU. Sur 100€ pariés, ça fait une vraie différence.',
                style: TextStyle(color: Colors.white60, fontSize: 14, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        _sectionTitle('📊 Comparatif des bookmakers'),
        const SizedBox(height: 10),

        ...bookmakers.map((bm) => _buildBookmakerDetailCard(bm)),

        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
          ),
          child: const Text(
            '⚠️ Les paris en ligne sont réservés aux personnes majeures (+18 ans). Jouez de manière responsable. Pariez uniquement ce que vous pouvez vous permettre de perdre.',
            style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.4),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildBookmakerDetailCard(_BookmakerInfo bm) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: bm.color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          // En-tête
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            onTap: () async {
              final uri = Uri.parse(bm.url);
              if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(
                  width: 46, height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: bm.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: bm.color.withValues(alpha: 0.5)),
                  ),
                  child: Text(bm.emoji, style: const TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(bm.nom, style: TextStyle(color: bm.color, fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(bm.description, style: const TextStyle(color: Colors.white54, fontSize: 14, height: 1.3)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: bm.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: bm.color.withValues(alpha: 0.5)),
                  ),
                  child: Row(children: [
                    Text('Ouvrir', style: TextStyle(color: bm.color, fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 4),
                    Icon(Icons.open_in_new, color: bm.color, size: 13),
                  ]),
                ),
              ]),
            ),
          ),
          // Détails
          Container(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(
              children: [
                const Divider(color: Colors.white12, height: 1),
                const SizedBox(height: 10),
                _detailRow(Icons.card_giftcard, 'Bonus', bm.bonus, _kGold),
                const SizedBox(height: 6),
                _detailRow(Icons.star_outline, 'Avantages', bm.avantage, _kGreen),
                const SizedBox(height: 6),
                _detailRow(Icons.percent, 'Marge', bm.marge,
                    bm.marge.contains('8') ? _kGreen : const Color(0xFFFFB74D)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 6),
        Text('$label : ', style: const TextStyle(color: Colors.white38, fontSize: 14)),
        Expanded(child: Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w500))),
      ],
    );
  }

  // ── Onglet 3 : Notifications ─────────────────────────────────────────────────

  Widget _buildTabNotifications() {
    final alertSvc = AlertService.instance;
    final config = alertSvc.config;
    final nbParis = alertSvc.trackedCourses.length;
    final nbAlertes = alertSvc.alerts.length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [

        // Statut global
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _kDgreen.withValues(alpha: 0.3),
                _kBg,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kGreen.withValues(alpha: 0.4)),
          ),
          child: Column(children: [
            Row(children: [
              const Icon(Icons.notifications_active, color: _kGreen, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Système d\'alertes actif', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  Text('Surveillance toutes les 60 secondes', style: TextStyle(color: _kGreen, fontSize: 14)),
                ]),
              ),
              Container(
                width: 12, height: 12,
                decoration: BoxDecoration(color: _kGreen, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: _kGreen.withValues(alpha: 0.5), blurRadius: 6)]),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _statCard('$nbParis', 'Courses\nsuivies', _kGreen)),
              const SizedBox(width: 8),
              Expanded(child: _statCard('$nbAlertes', 'Alertes\nreçues', _kGold)),
              const SizedBox(width: 8),
              Expanded(child: _statCard('${config.minutesAvantDepart}min', 'Rappel\navant départ', const Color(0xFFFF9800))),
            ]),
          ]),
        ),
        const SizedBox(height: 20),

        _sectionTitle('⏰ Types d\'alertes automatiques'),
        const SizedBox(height: 10),

        _buildAlertTypeCard(Icons.timer, const Color(0xFFFFB74D), 'Alerte imminente',
            'Vous recevez une notification ${config.minutesAvantDepart} minutes avant le départ de chaque course suivie.',
            config.activerCourseImminente),
        _buildAlertTypeCard(Icons.flag, _kGreen, 'Départ !',
            'Alerte au moment du départ pour que vous puissiez suivre la course en direct.',
            config.activerCourseCommence),
        _buildAlertTypeCard(Icons.payments, const Color(0xFFFF9800), 'Rappel de mise',
            'Rappel de placer votre mise avant la fermeture des paris (quelques minutes avant le départ).',
            config.activerRappelMise),

        const SizedBox(height: 20),
        _sectionTitle('📋 Comment ça marche ?'),
        const SizedBox(height: 10),

        _buildHowStep('1', 'Aller sur une course', 'Dans l\'onglet Courses ou Programme, trouvez une course qui vous intéresse.'),
        _buildHowStep('2', 'Appuyer sur "Parier"', 'Le bouton vert 💰 Parier ouvre la fiche de pari.'),
        _buildHowStep('3', 'Valider votre pari', 'Choisissez le cheval, la mise et validez. La course est automatiquement ajoutée à vos suivis.'),
        _buildHowStep('4', 'Recevoir les alertes', 'L\'app vous notifie ${config.minutesAvantDepart} minutes avant chaque course suivie avec un rappel de votre mise.'),
        _buildHowStep('5', 'Gérer vos paris', 'L\'onglet "Mes Paris" centralise toutes vos courses suivies et historique d\'alertes.'),

        const SizedBox(height: 20),
        _sectionTitle('💡 Paramètre de rappel'),
        const SizedBox(height: 10),

        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Rappel avant le départ', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text('Vous pouvez modifier cette valeur dans l\'onglet Mes Paris → Paramètres des alertes.', style: TextStyle(color: Colors.white38, fontSize: 14)),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (final mins in [5, 10, 15, 30])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: mins == config.minutesAvantDepart
                            ? _kDgreen.withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: mins == config.minutesAvantDepart
                              ? _kGreen
                              : Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Text(
                        '$mins min',
                        style: TextStyle(
                          color: mins == config.minutesAvantDepart ? _kGreen : Colors.white38,
                          fontWeight: mins == config.minutesAvantDepart ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
              ]),
            ],
          ),
        ),

        const SizedBox(height: 30),
      ],
    );
  }

  Widget _statCard(String val, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(children: [
        Text(val, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 14), textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _buildAlertTypeCard(IconData icon, Color color, String titre, String desc, bool active) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? color.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: active ? color : Colors.white24, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titre, style: TextStyle(color: active ? Colors.white : Colors.white38, fontWeight: FontWeight.bold, fontSize: 13)),
              Text(desc, style: const TextStyle(color: Colors.white38, fontSize: 14, height: 1.3)),
            ],
          ),
        ),
        Icon(
          active ? Icons.check_circle : Icons.cancel_outlined,
          color: active ? color : Colors.white24,
          size: 20,
        ),
      ]),
    );
  }

  Widget _buildHowStep(String num, String titre, String desc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26, height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _kDgreen.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(num, style: const TextStyle(color: _kGreen, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Text(desc, style: const TextStyle(color: Colors.white38, fontSize: 14, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) {
    return Text(t, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold));
  }
}

// ── Modèle bookmaker ──────────────────────────────────────────────────────────

class _BookmakerInfo {
  final String nom, emoji, url, description, bonus, avantage, marge;
  final Color color;
  const _BookmakerInfo({
    required this.nom, required this.emoji, required this.color,
    required this.url, required this.description, required this.bonus,
    required this.avantage, required this.marge,
  });
}
