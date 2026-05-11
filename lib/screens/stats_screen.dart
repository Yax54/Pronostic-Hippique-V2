import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pmu_provider.dart';
import '../models/pmu_models.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PmuProvider>();
    final courses = provider.allCourses;

    if (provider.loadingState == LoadingState.loading) {
      return const Scaffold(backgroundColor: Color(0xFF0D2818), body: Center(child: CircularProgressIndicator(color: Color(0xFF4CAF7D))));
    }

    final avenir = courses.where((c) => c.status == CourseStatus.aVenir).length;
    final enCours = courses.where((c) => c.status == CourseStatus.enCours).length;
    final terminee = courses.where((c) => c.status == CourseStatus.terminee).length;

    final hippoMap = <String, int>{};
    final discMap = <String, int>{};
    for (final c in courses) {
      final reunion = provider.reunions.firstWhere((r) => r.numOfficiel == c.numReunion, orElse: () => PmuReunion(numOfficiel: 0, hippodrome: '?', hippodromeCode: '', dateStr: '', courses: []));
      hippoMap[reunion.hippodrome] = (hippoMap[reunion.hippodrome] ?? 0) + 1;
      discMap[c.discipline] = (discMap[c.discipline] ?? 0) + 1;
    }
    final sortedHippos = hippoMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topCourse = courses.isEmpty ? null : courses.reduce((a, b) => a.montantPrix > b.montantPrix ? a : b);

    return Scaffold(
      backgroundColor: const Color(0xFF0D2818),
      appBar: AppBar(backgroundColor: const Color(0xFF0D2818), title: const Text('Statistiques PMU', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mes performances
            const Text('Mes Performances', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF1A6B3A), Color(0xFF0D3D20)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF2E7D52)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _BigStat(label: 'Pronostics', value: '${provider.totalPredictions}'),
                      _BigStat(label: 'Réussis', value: '${provider.correctPredictions}'),
                      _BigStat(label: 'Taux', value: '${provider.successRate.toStringAsFixed(0)}%'),
                    ],
                  ),
                  if (provider.totalPredictions > 0) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: provider.successRate / 100,
                        backgroundColor: const Color(0xFF0D2818),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4CAF7D)),
                        minHeight: 8,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Statut du programme
            const Text('Programme du Jour', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _StatusCard(label: 'À venir', count: avenir, color: const Color(0xFF4CAF7D), icon: Icons.schedule)),
                const SizedBox(width: 8),
                Expanded(child: _StatusCard(label: 'En cours', count: enCours, color: const Color(0xFFFFB74D), icon: Icons.directions_run)),
                const SizedBox(width: 8),
                Expanded(child: _StatusCard(label: 'Terminées', count: terminee, color: const Color(0xFF9E9E9E), icon: Icons.flag)),
              ],
            ),

            const SizedBox(height: 20),

            // Course la plus dotée
            if (topCourse != null) ...[
              const Text('Course Prestige', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              _PrestigeCard(course: topCourse, provider: provider),
              const SizedBox(height: 20),
            ],

            // Hippodromes
            const Text('Réunions par Hippodrome', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ...sortedHippos.map((e) => _HippoBar(name: e.key, count: e.value, total: courses.length)),

            const SizedBox(height: 20),

            // Disciplines
            const Text('Types de Courses', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _DiscGrid(discMap: discMap),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _BigStat extends StatelessWidget {
  final String label;
  final String value;
  const _BigStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 14)),
    ]);
  }
}

class _StatusCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  const _StatusCard({required this.label, required this.count, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text('$count', style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 13)),
      ]),
    );
  }
}

class _PrestigeCard extends StatelessWidget {
  final PmuCourse course;
  final PmuProvider provider;
  const _PrestigeCard({required this.course, required this.provider});

  @override
  Widget build(BuildContext context) {
    final reunion = provider.reunions.firstWhere((r) => r.numOfficiel == course.numReunion, orElse: () => PmuReunion(numOfficiel: 0, hippodrome: '?', hippodromeCode: '', dateStr: '', courses: []));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD700).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(course.libelle, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                Text(reunion.hippodrome, style: const TextStyle(color: Colors.white54, fontSize: 14)),
                Text('${(course.montantPrix / 1000).toStringAsFixed(0)} 000 €', style: const TextStyle(color: Color(0xFFFFD700), fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Text(course.disciplineIcon, style: const TextStyle(fontSize: 28)),
        ],
      ),
    );
  }
}

class _HippoBar extends StatelessWidget {
  final String name;
  final int count;
  final int total;
  const _HippoBar({required this.name, required this.count, required this.total});

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? count / total : 0.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name, style: const TextStyle(color: Colors.white, fontSize: 13)),
              Text('$count course${count > 1 ? 's' : ''}', style: const TextStyle(color: Colors.white54, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: const Color(0xFF1A4731).withValues(alpha: 0.4),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4CAF7D)),
              minHeight: 7,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscGrid extends StatelessWidget {
  final Map<String, int> discMap;
  const _DiscGrid({required this.discMap});

  String _icon(String disc) {
    switch (disc) {
      case 'PLAT': return '🏇';
      case 'HAIE': return '🚧';
      case 'STEEPLECHASE': return '🌿';
      case 'ATTELE':
      case 'TROT_ATTELE': return '🛒';
      case 'TROT_MONTE': return '🏃';
      default: return '🐎';
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = discMap.entries.toList();
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: entries.map((e) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A4731).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2E7D52).withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Text(_icon(e.key), style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 4),
            Text('${e.value}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            Text(e.key.replaceAll('_', ' '), style: const TextStyle(color: Colors.white54, fontSize: 14)),
          ],
        ),
      )).toList(),
    );
  }
}
