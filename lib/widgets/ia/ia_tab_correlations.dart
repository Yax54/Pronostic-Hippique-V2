import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/ia_memory_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Onglet Corrélations IA — lecture seule, pas de modification de poids
//
// Règles :
//   • Uniquement les critères vivants / partiels (variance > 0 sur l'échantillon)
//   • Critères à 50.0 constant → exclus (mort → fausserait Pearson)
//   • Corrélation de Pearson sur les vecteurs bruts de scores par partant
//   • Interprétation :
//       > 0.80  → doublon probable    🔴
//       0.50–0.80 → forte relation    🟠
//       0.20–0.50 → relation légère   🟡
//       < 0.20  → indépendant         🟢
// ─────────────────────────────────────────────────────────────────────────────

class IaTabCorrelations extends StatefulWidget {
  const IaTabCorrelations({super.key});

  @override
  State<IaTabCorrelations> createState() => _IaTabCorrelationsState();
}

class _IaTabCorrelationsState extends State<IaTabCorrelations> {
  final GlobalKey _repaintKey = GlobalKey();

  // Liste ordonnée des paires (triées par |corrélation| décroissant)
  List<_PaireCritere> _paires = [];
  // Critères vivants détectés (ont une variance > seuil sur l'échantillon)
  List<String> _critersVivants = [];
  int _nbPartants = 0;
  int _nbCourses  = 0;
  bool _calcule   = false;

  // ── Labels identiques à ia_tab_audit.dart ────────────────────────────────
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

  // Seuil : un critère est considéré "vivant" si son écart-type dépasse ce seuil
  // (50 pur = σ = 0 → mort ; quelques valeurs non-50 → σ faible → partiel)
  static const double _seuilVariance = 2.0; // σ minimum pour être inclus

  @override
  void initState() {
    super.initState();
    _calculer();
  }

  // ── Calcul Pearson ────────────────────────────────────────────────────────
  void _calculer() {
    final svc        = IaMemoryService.instance;
    final pronostics = svc.pronostics
        .where((p) => p.scoresCriteres.isNotEmpty)
        .toList();

    if (pronostics.isEmpty) {
      setState(() { _calcule = true; });
      return;
    }

    // 1. Construire un vecteur de valeurs par critère, tous partants confondus
    //    (chaque observation = un partant dans une course)
    final Map<String, List<double>> vecteurs = {
      for (final k in _labels.keys) k: [],
    };

    int nbPartantsTotal = 0;

    for (final prono in pronostics) {
      for (final sc in prono.scoresCriteres.values) {
        final m = sc.toJson();
        for (final k in _labels.keys) {
          final v = (m[k] as num?)?.toDouble();
          if (v != null) vecteurs[k]!.add(v);
        }
        nbPartantsTotal++;
      }
    }

    // 2. Identifier les critères vivants (σ > seuil)
    final critersVivants = <String>[];
    for (final k in _labels.keys) {
      final vals = vecteurs[k]!;
      if (vals.length < 10) continue; // pas assez de données
      final sigma = _ecartType(vals);
      if (sigma >= _seuilVariance) critersVivants.add(k);
    }

    // 3. Calculer Pearson pour toutes les paires de critères vivants
    final paires = <_PaireCritere>[];
    for (int i = 0; i < critersVivants.length; i++) {
      for (int j = i + 1; j < critersVivants.length; j++) {
        final kA = critersVivants[i];
        final kB = critersVivants[j];

        // Aligner les vecteurs sur le même indice partant
        final vA = <double>[];
        final vB = <double>[];

        // Reconstruire les paires alignées (même partant)
        for (final prono in pronostics) {
          for (final sc in prono.scoresCriteres.values) {
            final m  = sc.toJson();
            final va = (m[kA] as num?)?.toDouble();
            final vb = (m[kB] as num?)?.toDouble();
            if (va != null && vb != null) {
              vA.add(va);
              vB.add(vb);
            }
          }
        }

        if (vA.length < 10) continue;

        final r = _pearson(vA, vB);
        final absR = r.abs();

        final niveau = absR >= 0.80 ? _NiveauCorr.doublon
            : absR >= 0.50 ? _NiveauCorr.forte
            : absR >= 0.20 ? _NiveauCorr.legere
            : _NiveauCorr.independant;

        paires.add(_PaireCritere(
          cleA:   kA,
          cleB:   kB,
          labelA: _labels[kA]!,
          labelB: _labels[kB]!,
          r:      r,
          niveau: niveau,
          n:      vA.length,
        ));
      }
    }

    // 4. Trier par |r| décroissant
    paires.sort((a, b) => b.r.abs().compareTo(a.r.abs()));

    setState(() {
      _paires         = paires;
      _critersVivants = critersVivants;
      _nbPartants     = nbPartantsTotal;
      _nbCourses      = pronostics.length;
      _calcule        = true;
    });
  }

  // ── Pearson ───────────────────────────────────────────────────────────────
  static double _pearson(List<double> x, List<double> y) {
    final n   = x.length;
    if (n < 2) return 0.0;
    final mx  = x.reduce((a, b) => a + b) / n;
    final my  = y.reduce((a, b) => a + b) / n;
    double num = 0, dx = 0, dy = 0;
    for (int i = 0; i < n; i++) {
      final a = x[i] - mx;
      final b = y[i] - my;
      num += a * b;
      dx  += a * a;
      dy  += b * b;
    }
    final denom = math.sqrt(dx * dy);
    return denom == 0 ? 0.0 : num / denom;
  }

  static double _ecartType(List<double> vals) {
    if (vals.length < 2) return 0.0;
    final m   = vals.reduce((a, b) => a + b) / vals.length;
    final variance = vals.map((v) => (v - m) * (v - m)).reduce((a, b) => a + b) / vals.length;
    return math.sqrt(variance);
  }

  // ── Export JPEG ───────────────────────────────────────────────────────────
  Future<void> _exporterJpeg() async {
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image    = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final pngBytes = byteData.buffer.asUint8List();
      final tempDir  = await getTemporaryDirectory();
      final file     = File('${tempDir.path}/audit_correlations.png');
      await file.writeAsBytes(pngBytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          subject: 'Audit Corrélations IA — Pronostic Hippique',
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

    if (_paires.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🔗', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 16),
              const Text(
                'Pas encore de données suffisantes',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Il faut au moins 10 partants avec des scores variés\npour calculer les corrélations.\n\n'
                'Critères vivants détectés : ${_critersVivants.length}/19',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // ── Header stats ──────────────────────────────────────────────────
        _buildHeader(),
        // ── Légende ───────────────────────────────────────────────────────
        _buildLegende(),
        // ── Tableau des paires ────────────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            child: RepaintBoundary(
              key: _repaintKey,
              child: Container(
                color: const Color(0xFF0D1B2A),
                child: Column(
                  children: [
                    _buildTableauHeader(),
                    ..._paires.map(_buildLigne),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    // Compter par niveau
    final nbDoublons     = _paires.where((p) => p.niveau == _NiveauCorr.doublon).length;
    final nbFortes       = _paires.where((p) => p.niveau == _NiveauCorr.forte).length;
    final nbLegeres      = _paires.where((p) => p.niveau == _NiveauCorr.legere).length;
    final nbIndependants = _paires.where((p) => p.niveau == _NiveauCorr.independant).length;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🔗', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Corrélations de Pearson — $_nbCourses courses · $_nbPartants partants',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
              // Bouton export
              GestureDetector(
                onTap: _exporterJpeg,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.4)),
                  ),
                  child: const Text('📤', style: TextStyle(fontSize: 14)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_critersVivants.length} critères vivants analysés · ${_paires.length} paires calculées',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 8),
          // Résumé par niveau
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _badgeNiveau('🔴 $nbDoublons doublon${nbDoublons > 1 ? 's' : ''}', const Color(0xFFEF5350)),
              _badgeNiveau('🟠 $nbFortes forte${nbFortes > 1 ? 's' : ''}',       const Color(0xFFFF9800)),
              _badgeNiveau('🟡 $nbLegeres légère${nbLegeres > 1 ? 's' : ''}',    const Color(0xFFFFD700)),
              _badgeNiveau('🟢 $nbIndependants indép.',                           const Color(0xFF66BB6A)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badgeNiveau(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
  );

  // ── Légende ───────────────────────────────────────────────────────────────
  Widget _buildLegende() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(child: _legendeItem('🔴', '> 0.80', 'Doublon probable')),
          Expanded(child: _legendeItem('🟠', '0.50–0.80', 'Forte relation')),
          Expanded(child: _legendeItem('🟡', '0.20–0.50', 'Relation légère')),
          Expanded(child: _legendeItem('🟢', '< 0.20', 'Indépendant')),
        ],
      ),
    );
  }

  Widget _legendeItem(String emoji, String seuil, String label) => Column(
    children: [
      Text(emoji, style: const TextStyle(fontSize: 14)),
      Text(seuil, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9), textAlign: TextAlign.center),
    ],
  );

  // ── En-tête tableau ───────────────────────────────────────────────────────
  Widget _buildTableauHeader() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD700).withValues(alpha: 0.12),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
      ),
      child: const Row(
        children: [
          SizedBox(width: 28), // emoji
          Expanded(flex: 3, child: Text('Critère A',   style: TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.bold))),
          Expanded(flex: 3, child: Text('Critère B',   style: TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.bold))),
          SizedBox(width: 52, child: Text('r',          style: TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
          Expanded(flex: 3, child: Text('Interprétation', style: TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  // ── Ligne paire ───────────────────────────────────────────────────────────
  Widget _buildLigne(_PaireCritere p) {
    final color  = _couleurNiveau(p.niveau);
    final emoji  = _emojiNiveau(p.niveau);
    final interp = _interpretationTexte(p);
    final rStr   = p.r >= 0
        ? '+${p.r.toStringAsFixed(2)}'
        : p.r.toStringAsFixed(2);

    // Abréger les labels pour tenir dans la ligne
    final abrevA = _abrev(p.labelA);
    final abrevB = _abrev(p.labelB);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        border: Border(
          left: BorderSide(color: color, width: 3),
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
        ),
      ),
      child: Row(
        children: [
          // Emoji niveau
          SizedBox(
            width: 28,
            child: Text(emoji, style: const TextStyle(fontSize: 15)),
          ),
          // Critère A
          Expanded(
            flex: 3,
            child: Text(
              abrevA,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Critère B
          Expanded(
            flex: 3,
            child: Text(
              abrevB,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Valeur r
          SizedBox(
            width: 52,
            child: Text(
              rStr,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // Interprétation
          Expanded(
            flex: 3,
            child: Text(
              interp,
              style: TextStyle(color: color.withValues(alpha: 0.85), fontSize: 11),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Color _couleurNiveau(_NiveauCorr n) {
    switch (n) {
      case _NiveauCorr.doublon:     return const Color(0xFFEF5350); // rouge
      case _NiveauCorr.forte:       return const Color(0xFFFF9800); // orange
      case _NiveauCorr.legere:      return const Color(0xFFFFD700); // jaune
      case _NiveauCorr.independant: return const Color(0xFF66BB6A); // vert
    }
  }

  String _emojiNiveau(_NiveauCorr n) {
    switch (n) {
      case _NiveauCorr.doublon:     return '🔴';
      case _NiveauCorr.forte:       return '🟠';
      case _NiveauCorr.legere:      return '🟡';
      case _NiveauCorr.independant: return '🟢';
    }
  }

  String _interpretationTexte(_PaireCritere p) {
    final sign = p.r >= 0 ? 'Quand A↑ B↑' : 'Quand A↑ B↓';
    switch (p.niveau) {
      case _NiveauCorr.doublon:
        return 'Doublon · $sign';
      case _NiveauCorr.forte:
        return 'Forte · $sign';
      case _NiveauCorr.legere:
        return 'Légère · $sign';
      case _NiveauCorr.independant:
        return 'Indépendant';
    }
  }

  /// Abrège un label long pour affichage compact
  /// Ex: "A — Forme récente" → "A·Forme"
  String _abrev(String label) {
    final parts = label.split('—');
    if (parts.length < 2) return label;
    final lettre = parts[0].trim(); // "A"
    final nom    = parts[1].trim(); // "Forme récente"
    // Garder le 1er mot du nom
    final mot = nom.split(' ').first;
    return '$lettre · $mot';
  }
}

// ─── Data classes ─────────────────────────────────────────────────────────────

enum _NiveauCorr { doublon, forte, legere, independant }

class _PaireCritere {
  final String cleA;
  final String cleB;
  final String labelA;
  final String labelB;
  final double r;        // coefficient Pearson -1..+1
  final _NiveauCorr niveau;
  final int n;           // nb observations

  const _PaireCritere({
    required this.cleA,
    required this.cleB,
    required this.labelA,
    required this.labelB,
    required this.r,
    required this.niveau,
    required this.n,
  });
}

// Note : ScoresCriteres.toJson() est utilisé directement
// pour accéder aux scores bruts par clé string.
