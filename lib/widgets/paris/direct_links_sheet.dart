import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/alert_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  Widget : Feuille liens directs (PMU.fr, Equidia)
// ══════════════════════════════════════════════════════════════════════════════

class DirectLinksSheet extends StatelessWidget {
  final TrackedCourse course;
  const DirectLinksSheet({super.key, required this.course});

  @override
  Widget build(BuildContext context) {
    final links = _buildLinks(course);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0A1628),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(
              20, 12, 20,
              MediaQuery.of(context).padding.bottom + 20,
            ),
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(children: [
                const Icon(Icons.live_tv, color: Color(0xFF4CAF7D)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('Suivre en direct',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    Text(course.nomCourse,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 14),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              ...links.map((link) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: LinkTile(link: link),
                  )),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(children: [
                  Icon(Icons.info_outline, color: Colors.white38, size: 14),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Certaines chaînes nécessitent un abonnement. '
                      'PMU.fr propose un live gratuit pour les courses du jour.',
                      style: TextStyle(
                          color: Colors.white30, fontSize: 14, height: 1.4),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  List<DirectLink> _buildLinks(TrackedCourse course) {
    final dep = course.heureDepart;
    final dd = dep.day.toString().padLeft(2, '0');
    final mm = dep.month.toString().padLeft(2, '0');
    final yyyy = dep.year.toString();
    final dateStr = '$dd$mm$yyyy';
    final r = course.numReunion.toString().padLeft(2, '0');
    final c = course.numCourse.toString().padLeft(2, '0');
    final urlPmu = 'https://www.pmu.fr/turf/$dateStr/R$r/C$c';
    return [
      DirectLink(
        logo: '🏇',
        name: 'PMU.fr — Programme officiel',
        description: 'Programme, pronostics et paris en ligne',
        url: urlPmu,
        color: const Color(0xFF4CAF7D),
      ),
      DirectLink(
        logo: '📺',
        name: 'Equidia — Live TV',
        description: 'Direct gratuit des courses hippiques',
        url: 'https://www.equidia.fr/direct',
        color: const Color(0xFFFFD700),
      ),
    ];
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Modèle : lien direct
// ══════════════════════════════════════════════════════════════════════════════

class DirectLink {
  final String logo;
  final String name;
  final String description;
  final String url;
  final Color color;

  const DirectLink({
    required this.logo,
    required this.name,
    required this.description,
    required this.url,
    required this.color,
  });
}

// ══════════════════════════════════════════════════════════════════════════════
//  Widget : tuile lien
// ══════════════════════════════════════════════════════════════════════════════

class LinkTile extends StatelessWidget {
  final DirectLink link;
  const LinkTile({super.key, required this.link});

  Future<void> _openLink(BuildContext context) async {
    final uri = Uri.parse(link.url);
    bool launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!launched) {
      try {
        launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (_) {}
    }
    if (!launched && link.url.contains('pmu.fr/turf/')) {
      final fallback = Uri.parse('https://www.pmu.fr/turf/offre/courses');
      try {
        launched =
            await launchUrl(fallback, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Impossible d\'ouvrir. Copiez : ${link.url}'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openLink(context),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: link.color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: link.color.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Text(link.logo, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(link.name,
                  style: TextStyle(
                      color: link.color,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
              Text(link.description,
                  style:
                      const TextStyle(color: Colors.white38, fontSize: 16)),
            ]),
          ),
          Icon(Icons.open_in_new, color: link.color, size: 16),
        ]),
      ),
    );
  }
}
