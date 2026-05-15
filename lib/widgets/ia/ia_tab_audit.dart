import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/ia_memory_service.dart';
import '../../services/ia_memory_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Onglet Audit Critères IA — lecture seule
// Analyse les 19 critères A→S sur l'historique réel stocké
// Affiche : Top3 moy. / HorsTop5 moy. / Delta / Diagnostic
// ─────────────────────────────────────────────────────────────────────────────

class IaTabAudit extends StatefulWidget {
  const IaTabAudit({super.key});

  @override
  State<IaTabAudit> createState() => _IaTabAuditState();
}

class _IaTabAuditState extends State<IaTabAudit> {
  final GlobalKey _repaintKey = GlobalKey();
  List<_CritereAudit> _resultats = [];
  int _nbCourses = 0;
  int _nbPartants = 0;
  bool _calcule = false;

  // ── Labels des 19 critères A→S ────────────────────────────────────────────
  static const Map<String, String> _labels = {
    'f':  'A — Forme récente',
    'g':  'B — Gains carrière',
    'r':  'C — Record / Vitesse',
    'c':  'D — Cote marché',
    'k':  'E — Constance',
    'v':  'F — Victoires récentes',
    'd':  'G — Discipline',
    'ds': 'H — Distance spécifique',
    'j':  'I — Jockey / Driver',
    'rp': 'J — Repos / Fraîcheur',
    'hp': 'K — Hippodrome',
    'en': 'L — Entraîneur',
    'el': 'M — ELO dynamique',
    'tr': 'N — Terrain',
    'dv': 'O — Divergence forme/cote',
    'pr': 'P — Poids porté',
    'pg': 'Q — Progression carrière',
    'mc': 'R — Mouvement de cote',
    'pd': 'S — Place au départ',
  };

  @override
  void initState() {
    super.initState();
    _calculer();
  }

  // ── Calcul de l'audit sur l'historique ───────────────────────────────────
  void _calculer() {
    final svc = IaMemoryService.instance;
    final pronostics = svc.pronostics
        .where((p) => p.resultatsReels && p.arriveeReelle != null && p.arriveeReelle!.isNotEmpty)
        .toList();

    if (pronostics.isEmpty) {
      setState(() { _calcule = true; });
      return;
    }

    // Accumulateurs par critère
    final Map<String, List<double>> top3Scores    = {};
    final Map<String, List<double>> horsTop5Scores = {};

    int nbPartantsTotal = 0;

    for (final prono in pronostics) {
      final arrivee = prono.arriveeReelle!;
      final top3Set = arrivee.take(3).toSet();
      final top5Set = arrivee.take(5).toSet();

      for (final entry in prono.scoresCriteres.entries) {
        final numero = entry.key;
        final sc     = entry.value;
        final numInt = int.tryParse(numero);
        if (numInt == null) continue;

        final isTop3    = top3Set.contains(numInt);
        final isHorsTop5 = !top5Set.contains(numInt);

        final critMap = sc.toMap();
        for (final crit in _labels.keys) {
          final val = critMap[crit];
          if (val == null) continue;
          if (isTop3) {
            top3Scores.putIfAbsent(crit, () => []).add(val);
          } else if (isHorsTop5) {
            horsTop5Scores.putIfAbsent(crit, () => []).add(val);
          }
        }
        nbPartantsTotal++;
      }
    }

    // Construction des résultats
    final resultats = <_CritereAudit>[];
    for (final crit in _labels.keys) {
      final t3  = top3Scores[crit]    ?? [];
      final ht5 = horsTop5Scores[crit] ?? [];
      if (t3.isEmpty && ht5.isEmpty) continue;

      final moyTop3    = t3.isEmpty  ? 0.0 : t3.reduce((a, b) => a + b) / t3.length;
      final moyHorsTop5 = ht5.isEmpty ? 0.0 : ht5.reduce((a, b) => a + b) / ht5.length;
      final delta = moyTop3 - moyHorsTop5;

      resultats.add(_CritereAudit(
        cle:         crit,
        label:       _labels[crit]!,
        moyTop3:     moyTop3,
        moyHorsTop5: moyHorsTop5,
        delta:       delta,
        nbTop3:      t3.length,
        nbHorsTop5:  ht5.length,
      ));
    }

    // Tri par delta décroissant
    resultats.sort((a, b) => b.delta.compareTo(a.delta));

    setState(() {
      _resultats   = resultats;
      _nbCourses   = pronostics.length;
      _nbPartants  = nbPartantsTotal;
      _calcule     = true;
    });
  }

  // ── Export — tableau complet via ScrollController ─────────────────────────
  Future<void> _exporterJpeg() async {
    try {
      // On capture le RepaintBoundary qui enveloppe la Column complète
      // La Column est dans un SingleChildScrollView — on doit d'abord
      // faire défiler jusqu'en haut, puis capturer toute la hauteur de scroll
      final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      // Forcer le rendu de toute la hauteur du scroll
      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final pngBytes = byteData.buffer.asUint8List();
      final tempDir  = await getTemporaryDirectory();
      final file     = File('${tempDir.path}/audit_ia_criteres.png');
      await file.writeAsBytes(pngBytes);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          subject: 'Audit Critères IA — Pronostic Hippique',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur export : $e')),
        );
      }
    }
  }



  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (!_calcule) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700)));
    }

    if (_resultats.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('🔬', style: TextStyle(fontSize: 48)),
              SizedBox(height: 16),
              Text(
                'Pas encore de données suffisantes',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                'L\'audit nécessite des courses avec résultats réels enregistrés.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // ── Bouton export ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$_nbCourses courses • $_nbPartants partants analysés',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _exporterJpeg,
                icon: const Icon(Icons.share, size: 15),
                label: const Text('Export', style: TextStyle(fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),

        // ── Légende ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              _legendePuce(const Color(0xFF00E676), 'Très utile'),
              const SizedBox(width: 10),
              _legendePuce(const Color(0xFF2196F3), 'Utile'),
              const SizedBox(width: 10),
              _legendePuce(const Color(0xFFFF6D00), 'Léger'),
              const SizedBox(width: 10),
              _legendePuce(Colors.white38, 'Neutre'),
              const SizedBox(width: 10),
              _legendePuce(const Color(0xFFEF5350), 'Trompeur'),
            ],
          ),
        ),

        // ── Tableau scrollable avec capture complète ──────────────────────
        Expanded(
          child: SingleChildScrollView(
            child: RepaintBoundary(
              key: _repaintKey,
              child: ColoredBox(
                color: const Color(0xFF0D1B2A),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // En-tête tableau
                      _buildEnTete(),
                      const SizedBox(height: 6),
                      // Toutes les lignes (pas de ListView — Column complète)
                      ..._resultats.map((r) => _buildLigne(r)),
                      const SizedBox(height: 16),
                      // Note de bas de page
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          '🔍 Lecture seule — aucun poids modifié.\n'
                          'Top3 = chevaux arrivés 1er/2e/3e • HorsTop5 = arrivés 6e et au-delà.\n'
                          'Delta positif = le critère discrimine bien les bons chevaux.',
                          style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _legendePuce(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );
  }

  Widget _buildEnTete() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD700).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.2)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 5, child: Text('Critère', style: TextStyle(color: Color(0xFFFFD700), fontSize: 13, fontWeight: FontWeight.bold))),
          SizedBox(width: 6),
          _ColHeader('Top3'),
          SizedBox(width: 6),
          _ColHeader('Hors5'),
          SizedBox(width: 6),
          _ColHeader('Delta'),
          SizedBox(width: 6),
          Expanded(flex: 3, child: Text('Diagnostic', style: TextStyle(color: Color(0xFFFFD700), fontSize: 13, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildLigne(_CritereAudit r) {
    final color     = r.couleur;
    final diag      = r.diagnostic;

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          // Label critère
          Expanded(
            flex: 5,
            child: Text(
              r.label,
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          // Top3
          _ValCell(r.moyTop3.toStringAsFixed(1), Colors.white70),
          const SizedBox(width: 6),
          // HorsTop5
          _ValCell(r.moyHorsTop5.toStringAsFixed(1), Colors.white54),
          const SizedBox(width: 6),
          // Delta
          _ValCell(
            '${r.delta >= 0 ? '+' : ''}${r.delta.toStringAsFixed(1)}',
            color,
            bold: true,
          ),
          const SizedBox(width: 6),
          // Diagnostic
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                diag,
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Widgets helpers ───────────────────────────────────────────────────────────

class _ColHeader extends StatelessWidget {
  final String text;
  const _ColHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      child: Text(
        text,
        style: const TextStyle(color: Color(0xFFFFD700), fontSize: 13, fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _ValCell extends StatelessWidget {
  final String text;
  final Color color;
  final bool bold;
  const _ValCell(this.text, this.color, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ── Modèle de résultat audit ──────────────────────────────────────────────────

class _CritereAudit {
  final String cle;
  final String label;
  final double moyTop3;
  final double moyHorsTop5;
  final double delta;
  final int    nbTop3;
  final int    nbHorsTop5;

  const _CritereAudit({
    required this.cle,
    required this.label,
    required this.moyTop3,
    required this.moyHorsTop5,
    required this.delta,
    required this.nbTop3,
    required this.nbHorsTop5,
  });

  String get diagnostic {
    if (delta > 8.0)  return 'Très utile';
    if (delta > 4.0)  return 'Utile';
    if (delta > 1.5)  return 'Léger signal';
    if (delta > -1.5) return 'Neutre';
    return 'Trompeur ?';
  }

  Color get couleur {
    if (delta > 8.0)  return const Color(0xFF00E676);
    if (delta > 4.0)  return const Color(0xFF2196F3);
    if (delta > 1.5)  return const Color(0xFFFF6D00);
    if (delta > -1.5) return Colors.white38;
    return const Color(0xFFEF5350);
  }
}

// ── Extension toMap() sur ScoresCriteres ─────────────────────────────────────
extension ScoresCriteresMap on ScoresCriteres {
  Map<String, double> toMap() => {
    'f':  forme,
    'g':  gains,
    'r':  record,
    'c':  cote,
    'k':  constance,
    'v':  victoires,
    'd':  discipline,
    'ds': distSpec,
    'j':  jockey,
    'rp': repos,
    'hp': hippo,
    'en': entraineur,
    'el': elo,
    'tr': terrain,
    'dv': divergence,
    'pr': poidsRel,
    'pg': progression,
    'mc': mouvCote,
    'pd': placeDepart,
  };
}
