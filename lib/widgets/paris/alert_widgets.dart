import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart' show NavigationNotifier;
import '../../models/zt_models.dart';
import '../../services/alert_service.dart';
import '../../services/data_refresh_service.dart';
import '../../screens/paris_detail_screen.dart';
import '../../screens/course_detail_screen.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  Widget : Onglet Alertes
// ══════════════════════════════════════════════════════════════════════════════

// ★ v10.1 : StatefulWidget pour marquer automatiquement toutes les alertes lues
// à l'entrée dans l'onglet Historique (résout le badge qui reste affiché)
class AlertesTab extends StatefulWidget {
  final AlertService alertSvc;
  const AlertesTab({super.key, required this.alertSvc});

  @override
  State<AlertesTab> createState() => _AlertesTabState();
}

class _AlertesTabState extends State<AlertesTab> {
  // ★ v9.99 : suppression du markAllRead() automatique dans initState —
  // il marquait toutes les alertes lues dès l'ouverture de l'onglet,
  // avant tout tap utilisateur. Les alertes se marquent lues uniquement
  // au tap individuel (markRead) ou via le bouton "Tout marquer lu".

  @override
  Widget build(BuildContext context) {
    final alertSvc = widget.alertSvc;
    final alerts = alertSvc.alerts;

    if (alerts.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.notifications_none,
              color: Colors.white.withValues(alpha: 0.1), size: 64),
          const SizedBox(height: 14),
          const Text('Aucune alerte',
              style: TextStyle(color: Colors.white38, fontSize: 15)),
          const SizedBox(height: 8),
          const Text(
            'Les alertes apparaissent ici lorsque vous\nsuivez des courses.',
            style: TextStyle(color: Colors.white24, fontSize: 15),
            textAlign: TextAlign.center,
          ),
        ]),
      );
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
        child: Row(children: [
          Text('${alerts.length} alerte${alerts.length > 1 ? "s" : ""}',
              style: const TextStyle(color: Colors.white38, fontSize: 14)),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.done_all, size: 14, color: Color(0xFF4CAF7D)),
            label: const Text('Tout marquer lu',
                style: TextStyle(color: Color(0xFF4CAF7D), fontSize: 14)),
            onPressed: alertSvc.markAllRead,
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            icon: const Icon(Icons.delete_sweep, size: 14, color: Colors.white38),
            label: const Text('Effacer',
                style: TextStyle(color: Colors.white38, fontSize: 14)),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: const Color(0xFF0A1628),
                title: const Text('Effacer l\'historique ?',
                    style: TextStyle(color: Colors.white)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Annuler',
                        style: TextStyle(color: Colors.white38)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF5350)),
                    onPressed: () {
                      alertSvc.clearHistory();
                      Navigator.pop(context);
                    },
                    child: const Text('Effacer'),
                  ),
                ],
              ),
            ),
          ),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
          itemCount: alerts.length,
          itemBuilder: (ctx, i) {
            final alert = alerts[i];
            return AlertTile(alert: alert, alertSvc: alertSvc);
          },
        ),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Widget : Tuile d'alerte individuelle
// ══════════════════════════════════════════════════════════════════════════════

class AlertTile extends StatelessWidget {
  final AppAlert alert;
  final AlertService alertSvc;
  const AlertTile({super.key, required this.alert, required this.alertSvc});

  // Anti-double-tap : verrou statique partagé entre toutes les tuiles
  static final Set<String> _handling = {};

  @override
  Widget build(BuildContext context) {
    final color = alert.type.color;
    final timeStr = _formatTime(alert.timestamp);

    return Dismissible(
      key: Key(alert.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => alertSvc.deleteAlert(alert.id),
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFEF5350),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 22),
      ),
      child: GestureDetector(
        onTap: () {
          if (_handling.contains(alert.id)) return;
          _handling.add(alert.id);
          Future.delayed(const Duration(milliseconds: 600), () {
            _handling.remove(alert.id);
          });

          if (alert.numReunion != null && alert.numCourse != null) {
            final drs = DataRefreshService.instance;
            ZtReunion? foundReunion;
            ZtCourse? foundCourse;
            for (final r in drs.reunions) {
              final rNum = int.tryParse(r.code.replaceAll('R', '')) ?? -1;
              if (rNum != alert.numReunion) continue;
              for (final c in r.courses) {
                if (c.numCourse == alert.numCourse) {
                  foundReunion = r;
                  foundCourse = c;
                  break;
                }
              }
              if (foundCourse != null) break;
            }

            TrackedCourse? foundTracked;
            for (final entry in alertSvc.trackedCourses.entries) {
              final tc = entry.value;
              if (tc.numReunion == alert.numReunion &&
                  tc.numCourse == alert.numCourse) {
                foundTracked = tc;
                break;
              }
            }

            if (foundTracked != null) {
              alertSvc.markRead(alert.id);
              if (context.mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ParisDetailScreen(
                      tracked: foundTracked!,
                      alertSvc: alertSvc,
                    ),
                  ),
                );
              }
            } else if (foundCourse != null && foundReunion != null) {
              alertSvc.markRead(alert.id);
              if (context.mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CourseDetailScreen(
                      course: foundCourse!,
                      reunion: foundReunion!,
                    ),
                  ),
                );
              }
            } else {
              // Course introuvable dans le programme courant
              alertSvc.markRead(alert.id);
              if (context.mounted) {
                if (alert.type == AlertType.conseilIA) {
                  // "Nouvelle course dans tes critères" → Conseils IA (index 1)
                  context.read<NavigationNotifier>().goTo(1);
                } else {
                  // Autre type (résultat, rappel…) → SnackBar informatif
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(children: [
                        const Icon(Icons.flag_circle,
                            color: Color(0xFFFFD700), size: 22),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Course terminée — résultat disponible dans l\'historique PMU.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ]),
                      backgroundColor: const Color(0xFF2E4A1E),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }
              }
            }
          } else {
            // ★ fix : alertes sans course associée → naviguer vers la bonne section
            alertSvc.markRead(alert.id);
            // Normalisation robuste : suppression accents + minuscules
            final titreRaw   = alert.titre;
            final titreNorm  = titreRaw
                .toLowerCase()
                .replaceAll('é', 'e')
                .replaceAll('è', 'e')
                .replaceAll('ê', 'e')
                .replaceAll('à', 'a')
                .replaceAll('û', 'u');
            if (context.mounted) {
              final nav = context.read<NavigationNotifier>();
              // "🏁 Résultats PMU du jour disponibles" → IA Stats (index 5)
              if (titreNorm.contains('resultats pmu') ||
                  titreNorm.contains('pmu du jour') ||
                  titreRaw.contains('PMU')) {
                nav.goTo(5);
              } else if (titreNorm.contains('pronostics du jour') ||
                         titreNorm.contains('bonjour')) {
                // "Bonjour — Pronostics du jour disponibles" → Conseils (index 1)
                nav.goTo(1);
              } else if (titreNorm.contains('critere') ||
                         titreNorm.contains('correspond') ||
                         titreNorm.contains('nouvelle course')) {
                // "Nouvelle course dans tes critères" → Conseils IA (index 1)
                nav.goTo(1);
              } else if (titreNorm.contains('conseil ia') ||
                         titreNorm.contains('conseil du jour')) {
                // Conseil IA → Conseils IA (index 1)
                nav.goTo(1);
              } else if (titreNorm.contains('best bet') ||
                         titreNorm.contains('meilleur pari')) {
                // Best Bet → Best Bet (index 4)
                nav.goTo(4);
              } else if (titreNorm.contains('rappel') ||
                         titreNorm.contains('30 min') ||
                         titreNorm.contains('depart')) {
                // Rappel mise / départ → Mes Paris (index 6)
                nav.goTo(6);
              }
              // autres alertes génériques → rien (markRead suffit)
            }
          }
        },
        child: Opacity(
          opacity: alert.isRead ? 0.50 : 1.0,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: alert.isRead
                  ? const Color(0xFF0D1B2A)
                  : color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: alert.isRead
                    ? Colors.white.withValues(alpha: 0.12)
                    : color.withValues(alpha: 0.65),
                width: alert.isRead ? 1 : 2.0,
              ),
            ),
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(
                      alpha: alert.isRead ? 0.10 : 0.20),
                  shape: BoxShape.circle,
                ),
                child: Icon(alert.type.icon, color: color, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Expanded(
                      child: Text(alert.titre,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: alert.isRead
                                  ? FontWeight.normal
                                  : FontWeight.bold)),
                    ),
                    if (!alert.isRead) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: color.withValues(alpha: 0.50)),
                        ),
                        child: Text('NOUVEAU',
                            style: TextStyle(
                                color: color,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5)),
                      ),
                      const SizedBox(width: 6),
                    ],
                    GestureDetector(
                      onTap: () => alertSvc.deleteAlert(alert.id),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(Icons.close,
                            color: Colors.white24, size: 16),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 3),
                  Text(alert.message,
                      style: TextStyle(
                          color: alert.isRead
                              ? Colors.white70
                              : Colors.white,
                          fontSize: 14,
                          height: 1.4)),
                  const SizedBox(height: 4),
                  Text(timeStr,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Créée à l\'instant';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
    return '${dt.day}/${dt.month} à ${dt.hour.toString().padLeft(2, '0')}h${dt.minute.toString().padLeft(2, '0')}';
  }
}
