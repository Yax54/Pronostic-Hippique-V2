import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/ia_memory_service.dart';
import '../../services/ia_memory_models.dart';
import '../../services/ia_audit_cache_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Onglet Critères Morts — lecture seule
// Pour chaque critère : % fois score réel vs fallback 50
// ─────────────────────────────────────────────────────────────────────────────

class IaTabCriteresMorts extends StatefulWidget {
  const IaTabCriteresMorts({super.key});

  @override
  State<IaTabCriteresMorts> createState() => _IaTabCriteresMortsState();
}

class _IaTabCriteresMortsState extends State<IaTabCriteresMorts> {
  final GlobalKey _repaintKey = GlobalKey();
  List<_CritereVitalite> _resultats = [];
  int _nbPartants = 0;
  bool _calcule = false;
  // Couverture Repos/Fraîcheur : % de chevaux avec joursRepos connu
  double _pctReposCouverture = 0.0;

  final IaAuditCacheService _cache = IaAuditCacheService();

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
    _chargerOuCalculer();
  }

  // ── Cache : charger depuis le cache ou recalculer ★ v10.35 ───────────────
  Future<void> _chargerOuCalculer() async {
    final svc = IaMemoryService.instance;
    final nbAvecResultat = svc.pronostics
        .where((p) => p.resultatsReels && p.arriveeReelle != null && p.arriveeReelle!.isNotEmpty)
        .length;

    // Tentative lecture cache
    final valide = await _cache.isCacheValid(nbAvecResultat);
    if (valide) {
      final cached = await _cache.readCache();
      final raw = cached?['auditCriteresVivants'];
      if (raw is Map<String, dynamic>) {
        final rawResultats   = raw['resultats']          as List?;
        final nbPartants     = raw['nbPartants']         as int?;
        final pctRepos       = (raw['pctReposCouverture'] as num?)?.toDouble();
        if (rawResultats != null && rawResultats.isNotEmpty) {
          final resultats = rawResultats
              .map((e) => _CritereVitalite.fromJson(e as Map<String, dynamic>))
              .toList();
          if (mounted) {
            setState(() {
              _resultats          = resultats;
              _nbPartants         = nbPartants ?? 0;
              _pctReposCouverture = pctRepos   ?? 0.0;
              _calcule            = true;
            });
          }
          return;
        }
      }
    }

    // Recalcul complet + mise en cache
    await _calculer();
  }

  Future<void> _calculer() async {
    final svc = IaMemoryService.instance;
    final pronostics = svc.pronostics
        .where((p) => p.scoresCriteres.isNotEmpty)
        .toList();

    if (pronostics.isEmpty) {
      if (mounted) setState(() { _calcule = true; });
      return;
    }

    // Compter : réel vs fallback 50
    final Map<String, int> nbReel     = {};
    final Map<String, int> nbFallback = {};
    int total = 0;
    // Couverture Repos : nbChevaux avec joursRepos > 0 dans les prono
    int nbAvecRepos    = 0;
    int nbTotalChevaux = 0;

    for (final prono in pronostics) {
      for (final entry in prono.scoresCriteres.entries) {
        final sc  = entry.value;
        final map = sc.toMap();
        for (final crit in _labels.keys) {
          final val = map[crit];
          if (val == null) continue;
          // Fallback = exactement 50.0
          if (val == 50.0) {
            nbFallback[crit] = (nbFallback[crit] ?? 0) + 1;
          } else {
            nbReel[crit] = (nbReel[crit] ?? 0) + 1;
          }
        }
        // Couverture Repos/Fraîcheur :
        // repos != 50.0 = score calculé = donnée disponible
        final reposScore = map['rp'];
        nbTotalChevaux++;
        if (reposScore != null && reposScore != 50.0) nbAvecRepos++;
        total++;
      }
    }

    final resultats = <_CritereVitalite>[];
    for (final crit in _labels.keys) {
      final reel      = nbReel[crit]    ?? 0;
      final fallback  = nbFallback[crit] ?? 0;
      final totalCrit = reel + fallback;
      if (totalCrit == 0) continue;
      final pctReel = reel / totalCrit * 100;
      resultats.add(_CritereVitalite(
        cle:        crit,
        label:      _labels[crit]!,
        pctReel:    pctReel,
        nbReel:     reel,
        nbFallback: fallback,
      ));
    }

    // Tri par % réel décroissant (les plus vivants en haut)
    resultats.sort((a, b) => b.pctReel.compareTo(a.pctReel));

    final pctRepos = nbTotalChevaux > 0
        ? (nbAvecRepos / nbTotalChevaux * 100)
        : 0.0;

    // ── Mise en cache ★ v10.35 ──────────────────────────────────────────────
    final nbAvecResultat = svc.pronostics
        .where((p) => p.resultatsReels && p.arriveeReelle != null && p.arriveeReelle!.isNotEmpty)
        .length;
    final cacheActuel = await _cache.readCache();
    await _cache.writeCache(
      nbPronosticsAvecResultat: nbAvecResultat,
      auditUtiliteGlobal:   cacheActuel?['auditUtiliteGlobal'],
      auditCriteresVivants: {
        'resultats':          resultats.map((r) => r.toJson()).toList(),
        'nbPartants':         total,
        'pctReposCouverture': pctRepos,
      },
      auditCorrelations:    cacheActuel?['auditCorrelations'],
      auditParDiscipline:   cacheActuel?['auditParDiscipline'],
    );

    if (mounted) {
      setState(() {
        _resultats          = resultats;
        _nbPartants         = total;
        _calcule            = true;
        _pctReposCouverture = pctRepos;
      });
    }
  }

  // ── Export tableau complet ───────────────────────────────────────────────
  Future<void> _exporterJpeg() async {
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image    = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final pngBytes = byteData.buffer.asUint8List();
      final tempDir  = await getTemporaryDirectory();
      final file     = File('${tempDir.path}/audit_criteres_morts.png');
      await file.writeAsBytes(pngBytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          subject: 'Audit Critères Morts — Pronostic Hippique',
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
              Text('Aucun pronostic enregistré', style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // ── Header ───────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_nbPartants partants analysés',
                      style: const TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    // ── Couverture Repos/Fraîcheur ──────────────────────────
                    Row(
                      children: [
                        const Text('💤 J — Repos : ',
                            style: TextStyle(color: Colors.white38, fontSize: 14)),
                        Text(
                          '${_pctReposCouverture.toStringAsFixed(0)}% de couverture',
                          style: TextStyle(
                            color: _pctReposCouverture >= 60
                                ? const Color(0xFF00E676)
                                : _pctReposCouverture >= 30
                                    ? const Color(0xFFFFD700)
                                    : const Color(0xFFEF5350),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _exporterJpeg,
                icon: const Icon(Icons.share, size: 15),
                label: const Text('Export', style: TextStyle(fontSize: 15)),
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
              _puce(const Color(0xFF00E676), 'Vivant >80%'),
              const SizedBox(width: 10),
              _puce(const Color(0xFFFFD700), 'Partiel 40-80%'),
              const SizedBox(width: 10),
              _puce(const Color(0xFFFF6D00), 'Faible 10-40%'),
              const SizedBox(width: 10),
              _puce(const Color(0xFFEF5350), 'Mort <10%'),
            ],
          ),
        ),

        // ── Tableau scrollable + RepaintBoundary complet ──────────────────
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
                      _buildEnTete(),
                      const SizedBox(height: 6),
                      ..._resultats.map((r) => _buildLigne(r)),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          '🔍 Lecture seule — aucun poids modifié.\n'
                          'Réel = score calculé ≠ 50 • Fallback = retour à 50 (données absentes).\n'
                          'Un critère "Mort" (<10% réel) ne contribue pas à l\'IA.',
                          style: TextStyle(color: Colors.white38, fontSize: 14, height: 1.5),
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

  Widget _puce(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 14)),
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
          Expanded(flex: 5, child: Text('Critère', style: TextStyle(color: Color(0xFFFFD700), fontSize: 15, fontWeight: FontWeight.bold))),
          SizedBox(width: 6),
          _ColH('% Réel'),
          SizedBox(width: 6),
          _ColH('Réel'),
          SizedBox(width: 6),
          _ColH('F.50'),
          SizedBox(width: 6),
          Expanded(flex: 3, child: Text('Statut', style: TextStyle(color: Color(0xFFFFD700), fontSize: 15, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildLigne(_CritereVitalite r) {
    final color  = r.couleur;
    final statut = r.statut;

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(r.label, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 6),
          // Barre de vitalité inline
          SizedBox(
            width: 42,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${r.pctReel.toStringAsFixed(0)}%', style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: r.pctReel / 100,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _ValC('${r.nbReel}', Colors.white70),
          const SizedBox(width: 6),
          _ValC('${r.nbFallback}', Colors.white38),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(statut, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
      ),
    );
  }
}

class _ColH extends StatelessWidget {
  final String text;
  const _ColH(this.text);
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 42,
    child: Text(text, style: const TextStyle(color: Color(0xFFFFD700), fontSize: 15, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
  );
}

class _ValC extends StatelessWidget {
  final String text;
  final Color color;
  const _ValC(this.text, this.color);
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 42,
    child: Text(text, style: TextStyle(color: color, fontSize: 15), textAlign: TextAlign.center),
  );
}

class _CritereVitalite {
  final String cle;
  final String label;
  final double pctReel;
  final int    nbReel;
  final int    nbFallback;

  const _CritereVitalite({
    required this.cle,
    required this.label,
    required this.pctReel,
    required this.nbReel,
    required this.nbFallback,
  });

  // ★ v10.35 : sérialisation pour le cache SharedPreferences
  Map<String, dynamic> toJson() => {
    'cle':        cle,
    'label':      label,
    'pctReel':    pctReel,
    'nbReel':     nbReel,
    'nbFallback': nbFallback,
  };

  factory _CritereVitalite.fromJson(Map<String, dynamic> j) => _CritereVitalite(
    cle:        j['cle']        as String,
    label:      j['label']      as String,
    pctReel:    (j['pctReel']   as num).toDouble(),
    nbReel:     j['nbReel']     as int,
    nbFallback: j['nbFallback'] as int,
  );

  String get statut {
    if (pctReel >= 80) return 'Vivant';
    if (pctReel >= 40) return 'Partiel';
    if (pctReel >= 10) return 'Faible';
    return 'Mort';
  }

  Color get couleur {
    if (pctReel >= 80) return const Color(0xFF00E676);
    if (pctReel >= 40) return const Color(0xFFFFD700);
    if (pctReel >= 10) return const Color(0xFFFF6D00);
    return const Color(0xFFEF5350);
  }
}

extension _ScoresCriteresMapExt on ScoresCriteres {
  Map<String, double> toMap() => {
    'f':  forme,    'g':  gains,    'r':  record,
    'c':  cote,     'k':  constance,'v':  victoires,
    'd':  discipline,'ds': distSpec,'j':  jockey,
    'rp': repos,    'hp': hippo,    'en': entraineur,
    'el': elo,      'tr': terrain,  'dv': divergence,
    'pr': poidsRel, 'pg': progression,'mc': mouvCote,
    'pd': placeDepart,
  };
}
