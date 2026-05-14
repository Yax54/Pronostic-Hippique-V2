import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../services/alert_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  Widget : Onglet Paramètres alertes (page complète)
// ══════════════════════════════════════════════════════════════════════════════

class AlertSettingsTab extends StatefulWidget {
  final AlertService alertSvc;
  const AlertSettingsTab({super.key, required this.alertSvc});

  @override
  State<AlertSettingsTab> createState() => _AlertSettingsTabState();
}

class _AlertSettingsTabState extends State<AlertSettingsTab> {
  late AlertConfig _config;

  @override
  void initState() {
    super.initState();
    _config = widget.alertSvc.config;
    // ★ v10.35 : écouter les changements de permission pour mise à jour dynamique
    widget.alertSvc.addListener(_onAlertSvcChanged);
  }

  @override
  void dispose() {
    widget.alertSvc.removeListener(_onAlertSvcChanged);
    super.dispose();
  }

  void _onAlertSvcChanged() {
    if (mounted) setState(() { _config = widget.alertSvc.config; });
  }

  Future<void> _save() async {
    await widget.alertSvc.updateConfig(_config);
  }

  @override
  Widget build(BuildContext context) {
    final hasPermission = widget.alertSvc.hasNotificationPermission;
    final permStatus = widget.alertSvc.permissionStatus;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildPermissionBanner(context, hasPermission, permStatus),
        const SizedBox(height: 12),
        // ★ v10.35 : Mode Sommeil
        _ModeSommeilWidget(alertSvc: widget.alertSvc),
        const SizedBox(height: 20),
        _buildSectionTitle('🎯 Périmètre des alertes', 'Choisissez pour quelles courses recevoir des alertes'),
        const SizedBox(height: 12),
        _buildScopeSelector(),
        const SizedBox(height: 20),
        _buildSectionTitle('🔔 Types d\'alertes', 'Choisissez les événements à signaler'),
        const SizedBox(height: 12),
        _buildSwitchTile(
          icon: Icons.timer,
          color: const Color(0xFFFFB74D),
          title: 'Course imminente',
          subtitle: 'Alerte X minutes avant le départ',
          value: _config.activerCourseImminente,
          onChanged: (v) => setState(() {
            _config = _config.copyWith(activerCourseImminente: v);
            _save();
          }),
        ),
        if (_config.activerCourseImminente) ...[
          Container(
            margin: const EdgeInsets.only(left: 14, right: 14, bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFB74D).withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFB74D).withValues(alpha: 0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('⏱ Délai avant le départ',
                      style: TextStyle(color: Colors.white70, fontSize: 15)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB74D).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_config.minutesAvantDepart} min',
                      style: const TextStyle(
                          color: Color(0xFFFFB74D),
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.spaceAround,
                spacing: 8,
                runSpacing: 8,
                children: [5, 10, 15, 20, 30].map((min) {
                  final isSelected = _config.minutesAvantDepart == min;
                  return GestureDetector(
                    onTap: () => setState(() {
                      _config = _config.copyWith(minutesAvantDepart: min);
                      _save();
                    }),
                    child: Container(
                      width: 62,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFFFB74D).withValues(alpha: 0.25)
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? const Color(0xFFFFB74D) : Colors.white12,
                          width: isSelected ? 2.0 : 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$min min',
                          style: TextStyle(
                              color: isSelected ? const Color(0xFFFFB74D) : Colors.white38,
                              fontSize: 14,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ]),
          ),
        ],
        _buildSwitchTile(
          icon: Icons.flag,
          color: const Color(0xFF4CAF7D),
          title: 'Départ de la course',
          subtitle: 'Notification quand la course commence',
          value: _config.activerCourseCommence,
          onChanged: (v) => setState(() {
            _config = _config.copyWith(activerCourseCommence: v);
            _save();
          }),
        ),
        _buildSwitchTile(
          icon: Icons.radio_button_checked,
          color: const Color(0xFF64B5F6),
          title: 'Course en cours',
          subtitle: 'Rappel pendant le déroulement de la course',
          value: _config.activerCourseEnCours,
          onChanged: (v) => setState(() {
            _config = _config.copyWith(activerCourseEnCours: v);
            _save();
          }),
        ),
        _buildSwitchTile(
          icon: Icons.emoji_events,
          color: const Color(0xFFFFD700),
          title: 'Résultat du pari',
          subtitle: '🎉 Gagnant ou 😔 perdu — résultat final',
          value: _config.activerResultats,
          onChanged: (v) => setState(() {
            _config = _config.copyWith(activerResultats: v);
            _save();
          }),
        ),
        _buildSwitchTile(
          icon: Icons.payments,
          color: const Color(0xFFFF9800),
          title: 'Rappel de mise',
          subtitle: 'Confirmation quand vous ajoutez un suivi',
          value: _config.activerRappelMise,
          onChanged: (v) => setState(() {
            _config = _config.copyWith(activerRappelMise: v);
            _save();
          }),
        ),
        // ★ v10.24 : Alerte Cote qui chute
        _buildSwitchTile(
          icon: Icons.trending_down,
          color: const Color(0xFFEF5350),
          title: 'Cote qui chute',
          subtitle: 'Alerte si une cote baisse de 20%+ en moins d\'1h (argent informé)',
          value: _config.activerCoteChute,
          onChanged: (v) => setState(() {
            _config = _config.copyWith(activerCoteChute: v);
            _save();
          }),
        ),
        // ★ v10.24 : Alerte Dernière chance
        _buildSwitchTile(
          icon: Icons.alarm,
          color: const Color(0xFFFF6F00),
          title: 'Dernière chance',
          subtitle: 'Rappel 30 min avant le départ si course dans tes critères et pas encore misé',
          value: _config.activerDerniereChance,
          onChanged: (v) => setState(() {
            _config = _config.copyWith(activerDerniereChance: v);
            _save();
          }),
        ),
        const SizedBox(height: 20),
        _buildSectionTitle('⚙️ Options', 'Personnaliser le comportement des alertes'),
        const SizedBox(height: 12),
        // ★ v10.24 : Rappel quotidien à heure fixe (Feature #9)
        _buildSwitchTile(
          icon: Icons.schedule,
          color: const Color(0xFF7C4DFF),
          title: 'Rappel quotidien',
          subtitle: 'Notification à heure fixe pour consulter les pronostics du jour',
          value: _config.activerRappelQuotidien,
          onChanged: (v) => setState(() {
            _config = _config.copyWith(activerRappelQuotidien: v);
            _save();
          }),
        ),
        if (_config.activerRappelQuotidien)
          _buildRappelTimePicker(),
        _buildSwitchTile(
          icon: Icons.vibration,
          color: const Color(0xFF9C27B0),
          title: 'Vibrations',
          subtitle: 'Faire vibrer le téléphone lors des alertes importantes',
          value: _config.vibrationsActivees,
          onChanged: (v) => setState(() {
            _config = _config.copyWith(vibrationsActivees: v);
            _save();
          }),
        ),
        _buildSwitchTile(
          icon: Icons.volume_up,
          color: const Color(0xFF2196F3),
          title: 'Sons',
          subtitle: 'Son de notification pour les alertes critiques',
          value: _config.sonsActives,
          onChanged: (v) => setState(() {
            _config = _config.copyWith(sonsActives: v);
            _save();
          }),
        ),
        const SizedBox(height: 20),
        Center(
          child: TextButton.icon(
            icon: const Icon(Icons.restore, size: 16, color: Colors.white38),
            label: const Text('Remettre par défaut',
                style: TextStyle(color: Colors.white38, fontSize: 15)),
            onPressed: () async {
              setState(() => _config = AlertConfig.defaut);
              await widget.alertSvc.updateConfig(AlertConfig.defaut);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Paramètres réinitialisés'),
                    backgroundColor: Color(0xFF1B5E20),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
        ),
        const SizedBox(height: 16),
        _buildConfigSummary(),
      ]),
    );
  }

  // ★ v10.16 : multi-sélection — on peut cocher Favoris + Suivies simultanément
  bool _scopeIsChecked(AlertScope scope) {
    switch (scope) {
      case AlertScope.toutesLesCourses: return _config.scopeToutes;
      case AlertScope.coursesFavoris:   return _config.scopeFavoris;
      case AlertScope.coursesSuivies:   return _config.scopeSuivies;
    }
  }

  void _toggleScope(AlertScope scope) {
    switch (scope) {
      case AlertScope.toutesLesCourses:
        // Cocher "Toutes" décoche les deux autres (exclusif)
        _config = _config.copyWith(
          scopeToutes:   !_config.scopeToutes,
          scopeFavoris:  false,
          scopeSuivies:  false,
        );
        break;
      case AlertScope.coursesFavoris:
        // Cocher Favoris décoche "Toutes"
        _config = _config.copyWith(
          scopeFavoris: !_config.scopeFavoris,
          scopeToutes:  false,
        );
        break;
      case AlertScope.coursesSuivies:
        // Cocher Suivies décoche "Toutes"
        _config = _config.copyWith(
          scopeSuivies: !_config.scopeSuivies,
          scopeToutes:  false,
        );
        break;
    }
    // Sécurité : si tout est décoché, on remet "Toutes" par défaut
    if (!_config.scopeToutes && !_config.scopeFavoris && !_config.scopeSuivies) {
      _config = _config.copyWith(scopeToutes: true);
    }
    _save();
  }

  Widget _buildScopeSelector() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Titre explicatif
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Vous pouvez combiner plusieurs options',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          ...AlertScope.values.map((scope) {
            final isChecked = _scopeIsChecked(scope);
            return GestureDetector(
              onTap: () => setState(() => _toggleScope(scope)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isChecked
                      ? scope.color.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isChecked
                        ? scope.color.withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.07),
                    width: isChecked ? 1.5 : 1.0,
                  ),
                ),
                child: Row(children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: isChecked
                          ? scope.color.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.04),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(scope.icon,
                        color: isChecked ? scope.color : Colors.white24,
                        size: 17),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(scope.label,
                            style: TextStyle(
                                color: isChecked ? Colors.white : Colors.white54,
                                fontSize: 15,
                                fontWeight: isChecked
                                    ? FontWeight.bold
                                    : FontWeight.normal)),
                        Text(scope.description,
                            style: const TextStyle(
                                color: Colors.white30, fontSize: 13, height: 1.3)),
                      ],
                    ),
                  ),
                  // ★ Checkbox au lieu de radio button
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: isChecked
                        ? Icon(Icons.check_box, color: scope.color, size: 22,
                            key: const ValueKey('checked'))
                        : Icon(Icons.check_box_outline_blank,
                            color: Colors.white24, size: 22,
                            key: const ValueKey('unchecked')),
                  ),
                ]),
              ),
            );
          }),
          // ★ v10.23 : Alerte Conseil IA déplacée dans le Périmètre
          const SizedBox(height: 4),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.06),
              margin: const EdgeInsets.symmetric(vertical: 6)),
          _buildSwitchTile(
            icon: Icons.stars,
            color: const Color(0xFF4CAF7D),
            title: 'Alerte Conseil IA',
            subtitle: 'Notifie quand une course entre dans tes critères de filtres',
            value: _config.activerConseilIA,
            onChanged: (v) => setState(() {
              _config = _config.copyWith(activerConseilIA: v);
              _save();
            }),
          ),
          if (_config.activerConseilIA)
            _buildConseilIACriteresResume(),
        ],
      ),
    );
  }

  Widget _buildPermissionBanner(BuildContext context, bool hasPermission,
      NotificationPermissionStatus status) {
    if (status == NotificationPermissionStatus.notChecked) {
      return const SizedBox.shrink();
    }
    if (hasPermission) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF4CAF7D).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF4CAF7D).withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.notifications_active, color: Color(0xFF4CAF7D), size: 24),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Notifications activées ✅',
                  style: TextStyle(
                      color: Color(0xFF4CAF7D),
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
              SizedBox(height: 2),
              Text('Vous recevrez les alertes de courses.',
                  style: TextStyle(color: Colors.white54, fontSize: 14)),
            ]),
          ),
        ]),
      );
    }
    return GestureDetector(
      onTap: () => widget.alertSvc.ouvrirParametresNotification(),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFEF5350).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEF5350).withValues(alpha: 0.4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.notifications_off, color: Color(0xFFEF5350), size: 22),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Notifications désactivées',
                  style: TextStyle(
                      color: Color(0xFFEF5350),
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFEF5350).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFEF5350).withValues(alpha: 0.5)),
              ),
              child: const Text('Activer →',
                  style: TextStyle(
                      color: Color(0xFFEF5350),
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.only(left: 32),
            child: Text(
              '⚠️ Sans cette permission, vous ne pourrez pas recevoir '
              'd\'alertes en dehors de l\'application.\n\n'
              'Appuyez ici → Paramètres → Notifications → Activer',
              style: TextStyle(color: Colors.white38, fontSize: 16, height: 1.5),
            ),
          ),
        ]),
      ),
    );
  }

  // ★ v10.23 : Résumé des critères actifs pour l'alerte Conseil IA
  Widget _buildConseilIACriteresResume() {
    return FutureBuilder<Map<String, dynamic>>(
      future: widget.alertSvc.getCriteresConseilIA(),
      builder: (context, snap) {
        final criteres = snap.data;
        if (criteres == null) return const SizedBox();
        final types  = (criteres['types']  as List?)?.cast<String>() ?? [];
        final hippos = (criteres['hippos'] as List?)?.cast<String>() ?? [];
        final discs  = (criteres['discs']  as List?)?.cast<String>() ?? [];
        final conf   = criteres['confMin'] as int? ?? 0;
        final actifs = criteres['actifs']  as bool? ?? false;

        return Container(
          margin: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0D2535),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF4CAF7D).withValues(alpha: 0.3)),
          ),
          child: !actifs
              ? const Text(
                  '⚙️ Aucun filtre actif — configure-les dans Conseils IA',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Critères actifs :',
                        style: TextStyle(color: Colors.white54, fontSize: 11)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6, runSpacing: 6,
                      children: [
                        if (conf > 0)
                          _critereBadge('≥ $conf% confiance', const Color(0xFF00E5FF)),
                        ...types.map((t) => _critereBadge(t, const Color(0xFFFFD700))),
                        ...hippos.map((h) => _critereBadge(h, const Color(0xFF4CAF7D))),
                        ...discs.map((d) => _critereBadge(d, const Color(0xFF7C4DFF))),
                      ],
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _critereBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildSectionTitle(String title, String subtitle) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: const TextStyle(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
      const SizedBox(height: 3),
      Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 14)),
      const SizedBox(height: 4),
      Container(height: 1, color: Colors.white.withValues(alpha: 0.06)),
    ]);
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: value ? color.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value ? color.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: value ? color.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: value ? color : Colors.white24, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    color: value ? Colors.white : Colors.white54,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            Text(subtitle,
                style: const TextStyle(
                    color: Colors.white30, fontSize: 16, height: 1.3)),
          ]),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: color,
          inactiveThumbColor: Colors.white24,
          inactiveTrackColor: Colors.white12,
        ),
      ]),
    );
  }

  // ★ v10.24 : Sélecteur d'heure pour le rappel quotidien
  Widget _buildRappelTimePicker() {
    final h = _config.rappelHeure.toString().padLeft(2, '0');
    final m = _config.rappelMinute.toString().padLeft(2, '0');
    return Container(
      margin: const EdgeInsets.only(left: 14, right: 14, bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF7C4DFF).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        const Icon(Icons.access_time, color: Color(0xFF7C4DFF), size: 20),
        const SizedBox(width: 10),
        const Text('Heure du rappel', style: TextStyle(color: Colors.white70, fontSize: 14)),
        const Spacer(),
        GestureDetector(
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(
                hour:   _config.rappelHeure,
                minute: _config.rappelMinute,
              ),
              builder: (context, child) => Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary:   Color(0xFF7C4DFF),
                    onPrimary: Colors.white,
                    surface:   Color(0xFF111F30),
                    onSurface: Colors.white70,
                  ),
                ),
                child: child!,
              ),
            );
            if (picked != null && mounted) {
              setState(() {
                _config = _config.copyWith(
                  rappelHeure:   picked.hour,
                  rappelMinute:  picked.minute,
                );
              });
              await _save();
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF7C4DFF).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.5)),
            ),
            child: Text(
              '$h:$m',
              style: const TextStyle(
                color: Color(0xFF7C4DFF),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildConfigSummary() {
    final actives = [
      if (_config.activerCourseImminente) '⏰ ${_config.minutesAvantDepart} min avant',
      if (_config.activerCourseCommence) '🏇 Au départ',
      if (_config.activerCourseEnCours) '🔴 Pendant la course',
      if (_config.activerResultats) '🎉 Résultats',
      if (_config.activerRappelMise) '💰 Rappels mise',
      if (_config.activerCoteChute) '📉 Cote qui chute',
      if (_config.activerDerniereChance) '⏳ Dernière chance',
      if (_config.activerConseilIA) '✨ Conseil IA',
      if (_config.activerRappelQuotidien)
        '📅 Quotidien ${_config.rappelHeure.toString().padLeft(2, '0')}:${_config.rappelMinute.toString().padLeft(2, '0')}',
    ];
    if (actives.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFEF5350).withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFEF5350).withValues(alpha: 0.2)),
        ),
        child: const Text(
          '⚠️ Aucune alerte activée — vous ne recevrez aucune notification.',
          style: TextStyle(color: Colors.white38, fontSize: 14),
          textAlign: TextAlign.center,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF101E35).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2E7D52).withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Alertes actives :',
            style: TextStyle(
                color: Colors.white54,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: actives
              .map((a) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF7D).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFF4CAF7D).withValues(alpha: 0.3)),
                    ),
                    child: Text(a,
                        style: const TextStyle(
                            color: Color(0xFF4CAF7D), fontSize: 16)),
                  ))
              .toList(),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Widget : Bottom Sheet paramètres alertes (compact)
// ══════════════════════════════════════════════════════════════════════════════

class AlertSettingsSheet extends StatefulWidget {
  const AlertSettingsSheet({super.key});

  @override
  State<AlertSettingsSheet> createState() => _AlertSettingsSheetState();
}

class _AlertSettingsSheetState extends State<AlertSettingsSheet> {
  late AlertConfig _config;

  @override
  void initState() {
    super.initState();
    _config = AlertService.instance.config;
  }

  Future<void> _save() async {
    await AlertService.instance.updateConfig(_config);
  }

  // ★ v10.16 : multi-sélection — même logique que _AlertSettingsTabState
  bool _scopeIsChecked(AlertScope scope) {
    switch (scope) {
      case AlertScope.toutesLesCourses: return _config.scopeToutes;
      case AlertScope.coursesFavoris:   return _config.scopeFavoris;
      case AlertScope.coursesSuivies:   return _config.scopeSuivies;
    }
  }

  void _toggleScope(AlertScope scope) {
    switch (scope) {
      case AlertScope.toutesLesCourses:
        _config = _config.copyWith(
          scopeToutes:  !_config.scopeToutes,
          scopeFavoris: false,
          scopeSuivies: false,
        );
        break;
      case AlertScope.coursesFavoris:
        _config = _config.copyWith(
          scopeFavoris: !_config.scopeFavoris,
          scopeToutes:  false,
        );
        break;
      case AlertScope.coursesSuivies:
        _config = _config.copyWith(
          scopeSuivies: !_config.scopeSuivies,
          scopeToutes:  false,
        );
        break;
    }
    if (!_config.scopeToutes && !_config.scopeFavoris && !_config.scopeSuivies) {
      _config = _config.copyWith(scopeToutes: true);
    }
    _save();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scroll) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0A1628),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(children: [
              const Icon(Icons.tune, color: Color(0xFFFFD700), size: 20),
              const SizedBox(width: 8),
              const Text('Paramètres alertes',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() => _config = AlertConfig.defaut);
                  _save();
                },
                child: const Text('Réinitialiser',
                    style: TextStyle(color: Colors.white38, fontSize: 14)),
              ),
            ]),
          ),
          Expanded(
            child: ListView(
                controller: scroll,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
              // ── Sélecteur périmètre ──────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(bottom: 4, top: 4),
                child: Text('🎯 Périmètre',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ),
              _buildScopeSelector(),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('🔔 Types d\'alertes',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ),
              _buildItem(
                  Icons.timer,
                  const Color(0xFFFFB74D),
                  'Course imminente',
                  _config.activerCourseImminente,
                  (v) => setState(() {
                        _config = _config.copyWith(activerCourseImminente: v);
                        _save();
                      })),
              if (_config.activerCourseImminente) _buildDelaiSelector(),
              _buildItem(
                  Icons.flag,
                  const Color(0xFF4CAF7D),
                  'Départ de la course',
                  _config.activerCourseCommence,
                  (v) => setState(() {
                        _config = _config.copyWith(activerCourseCommence: v);
                        _save();
                      })),
              _buildItem(
                  Icons.emoji_events,
                  const Color(0xFFFFD700),
                  'Résultat du pari (gagnant/perdu)',
                  _config.activerResultats,
                  (v) => setState(() {
                        _config = _config.copyWith(activerResultats: v);
                        _save();
                      })),
              _buildItem(
                  Icons.radio_button_checked,
                  const Color(0xFF64B5F6),
                  'Course en cours',
                  _config.activerCourseEnCours,
                  (v) => setState(() {
                        _config = _config.copyWith(activerCourseEnCours: v);
                        _save();
                      })),
              _buildItem(
                  Icons.payments,
                  const Color(0xFFFF9800),
                  'Rappel de mise',
                  _config.activerRappelMise,
                  (v) => setState(() {
                        _config = _config.copyWith(activerRappelMise: v);
                        _save();
                      })),
              _buildItem(
                  Icons.vibration,
                  const Color(0xFF9C27B0),
                  'Vibrations',
                  _config.vibrationsActivees,
                  (v) => setState(() {
                        _config = _config.copyWith(vibrationsActivees: v);
                        _save();
                      })),
              const SizedBox(height: 20),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildItem(IconData icon, Color color, String label, bool value,
      ValueChanged<bool> cb) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: value ? color.withValues(alpha: 0.07) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value
              ? color.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: Row(children: [
        Icon(icon, color: value ? color : Colors.white30, size: 18),
        const SizedBox(width: 10),
        Expanded(
            child: Text(label,
                style: TextStyle(
                    color: value ? Colors.white : Colors.white38,
                    fontSize: 16,
                    fontWeight:
                        value ? FontWeight.w600 : FontWeight.normal))),
        Switch(
          value: value,
          onChanged: cb,
          activeThumbColor: color,
          inactiveThumbColor: Colors.white24,
          inactiveTrackColor: Colors.white12,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ]),
    );
  }

  // ★ v10.16 : version compacte multi-sélection (même logique que le widget principal)
  Widget _buildScopeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Combinable : Favoris + Suivies simultanément',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.40),
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
        ...AlertScope.values.map((scope) {
          final isChecked = _scopeIsChecked(scope);
          return GestureDetector(
            onTap: () => setState(() => _toggleScope(scope)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isChecked
                    ? scope.color.withValues(alpha: 0.10)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isChecked
                      ? scope.color.withValues(alpha: 0.45)
                      : Colors.white.withValues(alpha: 0.07),
                  width: isChecked ? 1.5 : 1.0,
                ),
              ),
              child: Row(children: [
                Icon(scope.icon,
                    color: isChecked ? scope.color : Colors.white30,
                    size: 17),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(scope.label,
                          style: TextStyle(
                              color: isChecked ? Colors.white : Colors.white38,
                              fontSize: 14,
                              fontWeight: isChecked
                                  ? FontWeight.bold
                                  : FontWeight.normal)),
                      Text(scope.description,
                          style: const TextStyle(
                              color: Colors.white24,
                              fontSize: 12,
                              height: 1.3)),
                    ],
                  ),
                ),
                // ★ Checkbox au lieu de radio button
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: isChecked
                      ? Icon(Icons.check_box, color: scope.color, size: 20,
                          key: const ValueKey('chk'))
                      : Icon(Icons.check_box_outline_blank,
                          color: Colors.white24, size: 20,
                          key: const ValueKey('unchk')),
                ),
              ]),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDelaiSelector() {
    return Container(
      margin: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB74D).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFB74D).withValues(alpha: 0.2)),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [5, 10, 15, 20, 30].map((min) {
          final sel = _config.minutesAvantDepart == min;
          return GestureDetector(
            onTap: () => setState(() {
              _config = _config.copyWith(minutesAvantDepart: min);
              _save();
            }),
            child: Container(
              width: 60,
              height: 40,
              decoration: BoxDecoration(
                color: sel
                    ? const Color(0xFFFFB74D).withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: sel ? const Color(0xFFFFB74D) : Colors.white12,
                  width: sel ? 2.0 : 1,
                ),
              ),
              child: Center(
                child: Text('$min min',
                    style: TextStyle(
                        color: sel ? const Color(0xFFFFB74D) : Colors.white38,
                        fontSize: 13,
                        fontWeight:
                            sel ? FontWeight.bold : FontWeight.normal)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}


// ══════════════════════════════════════════════════════════════════════════════
//  ★ v10.35 : Widget Mode Sommeil
//  Plage horaire pendant laquelle aucune alerte/notification n'est envoyée.
//  Persisté dans SharedPreferences : 'alerte_sommeil_v1'
// ══════════════════════════════════════════════════════════════════════════════
class _ModeSommeilWidget extends StatefulWidget {
  final AlertService alertSvc;
  const _ModeSommeilWidget({required this.alertSvc});
  @override
  State<_ModeSommeilWidget> createState() => _ModeSommeilWidgetState();
}

class _ModeSommeilWidgetState extends State<_ModeSommeilWidget> {
  static const _kCle = 'alerte_sommeil_v1';
  bool   _actif   = false;
  int    _heureDebut = 22;
  int    _minuteDebut = 0;
  int    _heureFin   = 7;
  int    _minuteFin  = 0;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_kCle);
    if (raw == null) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (mounted) setState(() {
        _actif       = m['actif']       as bool? ?? false;
        _heureDebut  = m['heureDebut']  as int?  ?? 22;
        _minuteDebut = m['minuteDebut'] as int?  ?? 0;
        _heureFin    = m['heureFin']    as int?  ?? 7;
        _minuteFin   = m['minuteFin']   as int?  ?? 0;
      });
    } catch (_) {}
  }

  Future<void> _sauvegarder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCle, jsonEncode({
      'actif':       _actif,
      'heureDebut':  _heureDebut,
      'minuteDebut': _minuteDebut,
      'heureFin':    _heureFin,
      'minuteFin':   _minuteFin,
    }));
  }

  /// Vérifie si on est actuellement en période de sommeil
  // ignore: unused_element
  static bool estEnSommeil(Map<String, dynamic>? cfg) {
    if (cfg == null) return false;
    if (!(cfg['actif'] as bool? ?? false)) return false;
    final now = TimeOfDay.now();
    final nowMin = now.hour * 60 + now.minute;
    final debutMin = (cfg['heureDebut'] as int? ?? 22) * 60 + (cfg['minuteDebut'] as int? ?? 0);
    final finMin   = (cfg['heureFin']   as int? ?? 7)  * 60 + (cfg['minuteFin']   as int? ?? 0);
    // Gérer le cas où la plage chevauche minuit (ex: 22h → 7h)
    if (debutMin > finMin) {
      return nowMin >= debutMin || nowMin < finMin;
    }
    return nowMin >= debutMin && nowMin < finMin;
  }

  String _fmt(int h, int m) =>
      '${h.toString().padLeft(2, '0')}h${m.toString().padLeft(2, '0')}';

  Future<void> _choisirHeure(bool estDebut) async {
    final init = TimeOfDay(
      hour:   estDebut ? _heureDebut  : _heureFin,
      minute: estDebut ? _minuteDebut : _minuteFin,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: init,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF1565C0),
            onPrimary: Colors.white,
            surface: Color(0xFF0D1B2A),
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (estDebut) { _heureDebut = picked.hour;  _minuteDebut = picked.minute; }
      else          { _heureFin   = picked.hour;  _minuteFin   = picked.minute; }
    });
    await _sauvegarder();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1628),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _actif
              ? const Color(0xFF1565C0).withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // En-tête avec toggle
        Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.4)),
            ),
            child: const Center(
              child: Text('🌙', style: TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Mode Sommeil',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
              Text(
                _actif
                    ? 'Actif : ${_fmt(_heureDebut, _minuteDebut)} → ${_fmt(_heureFin, _minuteFin)}'
                    : 'Aucune alerte pendant une plage horaire',
                style: TextStyle(
                  color: _actif
                      ? const Color(0xFF64B5F6)
                      : Colors.white38,
                  fontSize: 12),
              ),
            ]),
          ),
          Switch(
            value: _actif,
            onChanged: (v) async {
              setState(() => _actif = v);
              await _sauvegarder();
            },
            activeColor: const Color(0xFF1565C0),
            activeTrackColor: const Color(0xFF1565C0).withValues(alpha: 0.3),
          ),
        ]),

        // Plage horaire (visible uniquement si actif)
        if (_actif) ...[
          const SizedBox(height: 12),
          const Divider(color: Colors.white12),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _choisirHeure(true),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF1565C0).withValues(alpha: 0.3)),
                  ),
                  child: Column(children: [
                    const Text('Début',
                      style: TextStyle(color: Colors.white38, fontSize: 10)),
                    const SizedBox(height: 4),
                    Text(_fmt(_heureDebut, _minuteDebut),
                      style: const TextStyle(
                        color: Color(0xFF64B5F6),
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
                  ]),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('→',
                style: TextStyle(color: Colors.white38, fontSize: 20))),
            Expanded(
              child: GestureDetector(
                onTap: () => _choisirHeure(false),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF1565C0).withValues(alpha: 0.3)),
                  ),
                  child: Column(children: [
                    const Text('Fin',
                      style: TextStyle(color: Colors.white38, fontSize: 10)),
                    const SizedBox(height: 4),
                    Text(_fmt(_heureFin, _minuteFin),
                      style: const TextStyle(
                        color: Color(0xFF64B5F6),
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
                  ]),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            'Aucune notification de ${_fmt(_heureDebut, _minuteDebut)} à ${_fmt(_heureFin, _minuteFin)}.'
            '${_heureDebut > _heureFin ? ' (plage traverse minuit)' : ''}',
            style: const TextStyle(color: Colors.white38, fontSize: 10),
            textAlign: TextAlign.center,
          ),
        ],
      ]),
    );
  }
}
