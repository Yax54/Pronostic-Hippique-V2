import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/ia_memory_service.dart';
import '../../services/ia_audit_cache_service.dart';
import '../../services/ia_memory_models.dart';
import 'ia_tab_audit.dart'; // ← extension ScoresCriteresMap.toMap()

// ═══════════════════════════════════════════════════════════════════════════
//  IaTabDiscipline — Audit IA par discipline (lecture seule)
//
//  Règles strictes :
//   • LECTURE SEULE — aucun poids modifié, aucun apprentissage, aucune sauvegarde
//   • Critères morts (σ < 2.0) ignorés
//   • Critères avec < 30 valeurs réelles ignorés
//   • Corrélations affichées uniquement si |r| >= 0.20
//   • Regroupements :
//       Plat     → type == "Plat"
//       Trot     → type == "Attelé" || "Monté"
//       Obstacle → type == "Haies" || "Steeple"
// ═══════════════════════════════════════════════════════════════════════════

class IaTabDiscipline extends StatefulWidget {
  const IaTabDiscipline({super.key});

  @override
  State<IaTabDiscipline> createState() => _IaTabDisciplineState();
}

class _IaTabDisciplineState extends State<IaTabDiscipline>
    with SingleTickerProviderStateMixin {

  late TabController _discCtrl;

  // Une section par discipline dans l'ordre d'affichage
  static const _disciplines = ['Plat', 'Trot', 'Obstacle'];

  // Résultats calculés — map discipline → données
  final Map<String, _DiscData> _data = {};
  bool _calcule = false;

  final IaAuditCacheService _cache = IaAuditCacheService();

  // Clés RepaintBoundary pour l'export JPEG, une par onglet discipline
  final Map<String, GlobalKey> _repaintKeys = {
    'Plat':     GlobalKey(),
    'Trot':     GlobalKey(),
    'Obstacle': GlobalKey(),
  };

  // ── Labels 19 critères ────────────────────────────────────────────────────
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

  static const double _seuilSigma     = 2.0;  // σ minimum → critère vivant
  static const int    _seuilNbValeurs = 30;   // nb observations minimum
  static const double _seuilCorrMin   = 0.20; // corrélations à afficher

  @override
  void initState() {
    super.initState();
    _discCtrl = TabController(length: _disciplines.length, vsync: this);
    _chargerOuCalculer();
  }

  @override
  void dispose() {
    _discCtrl.dispose();
    super.dispose();
  }

  // ── Regroupement type → discipline ───────────────────────────────────────
  static String? _groupeDisc(String type) {
    final t = type.trim();
    if (t == 'Plat')                       return 'Plat';
    if (t == 'Attelé' || t == 'Monté')    return 'Trot';
    if (t == 'Haies'  || t == 'Steeple')  return 'Obstacle';
    return null; // inconnu → ignoré
  }

  // ── Calcul principal ──────────────────────────────────────────────────────

  // ── Cache : charger depuis le cache ou recalculer ★ v10.33 ───────────────
  Future<void> _chargerOuCalculer() async {
    final svc = IaMemoryService.instance;
    final nbAvecResultat = svc.pronostics
        .where((p) => p.resultatsReels && p.arriveeReelle != null && p.arriveeReelle!.isNotEmpty)
        .length;

    final valide = await _cache.isCacheValid(nbAvecResultat);
    if (valide) {
      final cached = await _cache.readCache();
      final rawDisc = cached?['auditParDiscipline'];
      if (rawDisc is Map<String, dynamic> && rawDisc.isNotEmpty) {
        bool allOk = true;
        for (final d in ['Plat', 'Trot', 'Obstacle']) {
          final raw = rawDisc[d];
          if (raw is Map<String, dynamic>) {
            _data[d] = _DiscData.fromJson(raw);
          } else {
            allOk = false; break;
          }
        }
        if (allOk && mounted) {
          setState(() { _calcule = true; });
          return;
        }
      }
    }

    _calculer();
  }
  Future<void> _calculer() async {
    final svc        = IaMemoryService.instance;
    final pronostics = svc.pronostics; // tous, pas seulement avec résultats

    // Partitionner les pronostics par discipline
    final Map<String, List<IaPronostic>> parDisc = {
      for (final d in _disciplines) d: [],
    };
    for (final p in pronostics) {
      final g = _groupeDisc(p.discipline);
      if (g != null) parDisc[g]!.add(p);
    }

    for (final disc in _disciplines) {
      _data[disc] = _calculerDisc(disc, parDisc[disc]!);
    }


    // Mise en cache ★ v10.33
    final svc2 = IaMemoryService.instance;
    final nbAvecResultat = svc2.pronostics
        .where((p) => p.resultatsReels && p.arriveeReelle != null && p.arriveeReelle!.isNotEmpty)
        .length;
    final cacheActuel = await _cache.readCache();
    await _cache.writeCache(
      nbPronosticsAvecResultat: nbAvecResultat,
      auditUtiliteGlobal:   cacheActuel?['auditUtiliteGlobal'],
      auditCriteresVivants: cacheActuel?['auditCriteresVivants'],
      auditCorrelations:    cacheActuel?['auditCorrelations'],
      auditParDiscipline: {
        for (final d in ['Plat', 'Trot', 'Obstacle'])
          if (_data.containsKey(d)) d: _data[d]!.toJson(),
      },
    );

    if (mounted) setState(() { _calcule = true; });
  }

  // ── Calcul pour une discipline ────────────────────────────────────────────
  _DiscData _calculerDisc(String disc, List<IaPronostic> pronostics) {
    final avecResultat = pronostics
        .where((p) => p.resultatsReels && p.arriveeReelle != null && p.arriveeReelle!.isNotEmpty)
        .toList();

    // ── 1. Tableau utilité (Top3 / HorsTop5 / Delta) ─────────────────────
    final Map<String, List<double>> top3Sc    = {};
    final Map<String, List<double>> horsTop5Sc = {};
    int nbPartants = 0;

    for (final prono in avecResultat) {
      final arrivee  = prono.arriveeReelle!;
      final top3Set  = arrivee.take(3).toSet();
      final top5Set  = arrivee.take(5).toSet();

      for (final entry in prono.scoresCriteres.entries) {
        final numInt = int.tryParse(entry.key);
        if (numInt == null) continue;
        final isTop3     = top3Set.contains(numInt);
        final isHorsTop5 = !top5Set.contains(numInt);
        final m = entry.value.toMap(); // extension ScoresCriteresMap

        for (final k in _labels.keys) {
          final val = m[k];
          if (val == null) continue;
          if (isTop3)     top3Sc.putIfAbsent(k, () => []).add(val);
          else if (isHorsTop5) horsTop5Sc.putIfAbsent(k, () => []).add(val);
        }
        nbPartants++;
      }
    }

    // ── 2. Construire critères vivants (σ ≥ seuil ET nb ≥ seuil) ─────────
    // Vecteur complet (tous partants avec scores, pas seulement arrivée connue)
    final Map<String, List<double>> tousVecteurs = {
      for (final k in _labels.keys) k: [],
    };
    for (final prono in pronostics) {
      for (final sc in prono.scoresCriteres.values) {
        final m = sc.toMap();
        for (final k in _labels.keys) {
          final v = m[k];
          if (v != null) tousVecteurs[k]!.add(v);
        }
      }
    }

    final critersVivants = <String>[];
    for (final k in _labels.keys) {
      final vals = tousVecteurs[k]!;
      if (vals.length < _seuilNbValeurs) continue;
      if (_ecartType(vals) < _seuilSigma) continue;
      critersVivants.add(k);
    }

    // ── 3. Résultats utilité (sur critères vivants uniquement) ────────────
    final criteres = <_CritereDisc>[];
    for (final k in critersVivants) {
      final t3  = top3Sc[k]    ?? [];
      final ht5 = horsTop5Sc[k] ?? [];
      if (t3.isEmpty && ht5.isEmpty) continue;
      final moyT3  = t3.isEmpty  ? 0.0 : t3.reduce((a, b)  => a + b) / t3.length;
      final moyHt5 = ht5.isEmpty ? 0.0 : ht5.reduce((a, b) => a + b) / ht5.length;
      criteres.add(_CritereDisc(
        cle:   k,
        label: _labels[k]!,
        moyTop3:     moyT3,
        moyHorsTop5: moyHt5,
        delta:       moyT3 - moyHt5,
        nbTop3:      t3.length,
        nbHorsTop5:  ht5.length,
      ));
    }
    criteres.sort((a, b) => b.delta.compareTo(a.delta));

    // ── 4. Corrélations Pearson (critères vivants, paires alignées) ───────
    final paires = <_PaireDisc>[];
    for (int i = 0; i < critersVivants.length; i++) {
      for (int j = i + 1; j < critersVivants.length; j++) {
        final kA = critersVivants[i];
        final kB = critersVivants[j];
        final vA = <double>[], vB = <double>[];
        for (final prono in pronostics) {
          for (final sc in prono.scoresCriteres.values) {
            final m = sc.toMap();
            final va = m[kA], vb = m[kB];
            if (va != null && vb != null) { vA.add(va); vB.add(vb); }
          }
        }
        if (vA.length < _seuilNbValeurs) continue;
        final r = _pearson(vA, vB);
        if (r.abs() < _seuilCorrMin) continue;
        paires.add(_PaireDisc(
          cleA:   kA, cleB: kB,
          labelA: _labels[kA]!, labelB: _labels[kB]!,
          r: r,
          n: vA.length,
        ));
      }
    }
    paires.sort((a, b) => b.r.abs().compareTo(a.r.abs()));

    return _DiscData(
      nbCourses:      pronostics.length,
      nbAvecResultat: avecResultat.length,
      nbPartants:     nbPartants,
      criteres:       criteres,
      paires:         paires,
      critersVivants: critersVivants.length,
    );
  }

  // ── Pearson / écart-type ──────────────────────────────────────────────────
  static double _pearson(List<double> x, List<double> y) {
    final n = x.length;
    if (n < 2) return 0.0;
    final mx = x.reduce((a, b) => a + b) / n;
    final my = y.reduce((a, b) => a + b) / n;
    double num = 0, dx = 0, dy = 0;
    for (int i = 0; i < n; i++) {
      final a = x[i] - mx, b = y[i] - my;
      num += a * b; dx += a * a; dy += b * b;
    }
    final den = math.sqrt(dx * dy);
    return den == 0 ? 0.0 : num / den;
  }

  static double _ecartType(List<double> vals) {
    if (vals.length < 2) return 0.0;
    final m   = vals.reduce((a, b) => a + b) / vals.length;
    final v   = vals.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / vals.length;
    return math.sqrt(v);
  }

  // ── Export JPEG ───────────────────────────────────────────────────────────
  Future<void> _exporter(String disc) async {
    try {
      final key      = _repaintKeys[disc]!;
      final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image    = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes    = byteData.buffer.asUint8List();
      final dir      = await getTemporaryDirectory();
      final file     = File('${dir.path}/audit_discipline_$disc.png');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(ShareParams(
        files:   [XFile(file.path, mimeType: 'image/png')],
        subject: 'Audit IA par discipline — $disc — Pronostic Hippique',
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur export : $e')),
        );
      }
    }
  }

  // ── Build racine ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (!_calcule) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700)));
    }

    return Column(
      children: [
        // Sous-TabBar disciplines
        Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            controller: _discCtrl,
            labelColor: const Color(0xFF00E676),
            unselectedLabelColor: Colors.white54,
            indicator: BoxDecoration(
              color: const Color(0xFF00E676).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.4)),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(fontSize: 15),
            tabs: const [
              Tab(text: '🏇 Plat'),
              Tab(text: '🔄 Trot'),
              Tab(text: '🚧 Obstacle'),
            ],
          ),
        ),
        // Contenu
        Expanded(
          child: TabBarView(
            controller: _discCtrl,
            children: _disciplines
                .map((d) => _buildOngletDisc(d))
                .toList(),
          ),
        ),
      ],
    );
  }

  // ── Onglet d'une discipline ───────────────────────────────────────────────
  Widget _buildOngletDisc(String disc) {
    final d = _data[disc]!;
    final echanFaible = d.nbAvecResultat < 20;

    return RepaintBoundary(
      key: _repaintKeys[disc],
      child: Container(
        color: const Color(0xFF0D1B2A),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Bandeau header + export ──────────────────────────────────
              _buildHeader(disc, d, echanFaible),
              if (echanFaible) _buildAvertissement(d.nbAvecResultat),

              // ── Tableau utilité ──────────────────────────────────────────
              _sectionTitre('📊 Utilité des critères', '— Delta = Top3 moy. − HorsTop5 moy.'),
              if (d.criteres.isEmpty)
                _vide('Pas de critères vivants avec suffisamment de données')
              else ...[
                _tableauUtiliteHeader(),
                ...d.criteres.map((c) => _ligneUtilite(c)),
              ],

              const SizedBox(height: 16),

              // ── Tableau corrélations ─────────────────────────────────────
              _sectionTitre('🔗 Corrélations principales', '— Pearson |r| ≥ 0.20'),
              _legendeCorr(),
              if (d.paires.isEmpty)
                _vide('Aucune corrélation significative (|r| ≥ 0.20) détectée')
              else ...[
                _tableauCorrHeader(),
                ...d.paires.map((p) => _ligneCorr(p)),
              ],

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header discipline ─────────────────────────────────────────────────────
  Widget _buildHeader(String disc, _DiscData d, bool echanFaible) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  disc,
                  style: const TextStyle(
                    color: Color(0xFF00E676),
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  children: [
                    _statChip('📁', '${d.nbCourses}', 'courses'),
                    _statChip('✅', '${d.nbAvecResultat}', 'avec résultat'),
                    _statChip('🐴', '${d.nbPartants}', 'partants'),
                    _statChip('🔬', '${d.critersVivants}', 'critères vivants'),
                  ],
                ),
              ],
            ),
          ),
          // Bouton export
          GestureDetector(
            onTap: () => _exporter(disc),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.4)),
              ),
              child: const Column(
                children: [
                  Text('📤', style: TextStyle(fontSize: 18)),
                  Text('Export', style: TextStyle(color: Color(0xFFFFD700), fontSize: 15)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statChip(String emoji, String val, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(emoji, style: const TextStyle(fontSize: 14)),
      const SizedBox(width: 3),
      Text(val,   style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
      const SizedBox(width: 2),
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 14)),
    ],
  );

  // ── Avertissement échantillon faible ─────────────────────────────────────
  Widget _buildAvertissement(int nb) => Container(
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFFF9800).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.4)),
    ),
    child: Row(
      children: [
        const Text('⚠️', style: TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Échantillon faible ($nb courses avec résultat). '
            'Les résultats sont indicatifs — interprétez avec précaution.',
            style: const TextStyle(color: Color(0xFFFF9800), fontSize: 14),
          ),
        ),
      ],
    ),
  );

  // ── Titre section ─────────────────────────────────────────────────────────
  Widget _sectionTitre(String titre, String sous) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titre, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        Text(sous,  style: const TextStyle(color: Colors.white38, fontSize: 14)),
      ],
    ),
  );

  Widget _vide(String msg) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    child: Text(msg, style: const TextStyle(color: Colors.white38, fontSize: 14, fontStyle: FontStyle.italic)),
  );

  // ── Tableau utilité ───────────────────────────────────────────────────────
  Widget _tableauUtiliteHeader() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFFFFD700).withValues(alpha: 0.10),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
    ),
    child: const Row(
      children: [
        Expanded(flex: 4, child: _TH('Critère')),
        _TH('Top3'),
        _TH('HT5'),
        _TH('Delta'),
        Expanded(flex: 3, child: _TH('Diagnostic', right: true)),
      ],
    ),
  );

  Widget _ligneUtilite(_CritereDisc c) {
    final color = c.couleur;
    final abrev = _abrev(c.label);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        border: Border(
          left: BorderSide(color: color, width: 3),
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(abrev,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _TV(c.moyTop3.toStringAsFixed(1),    Colors.white70),
          _TV(c.moyHorsTop5.toStringAsFixed(1), Colors.white38),
          _TV(
            (c.delta >= 0 ? '+' : '') + c.delta.toStringAsFixed(1),
            color,
            bold: true,
          ),
          Expanded(
            flex: 3,
            child: Text(
              c.diagnostic,
              style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ── Tableau corrélations ──────────────────────────────────────────────────
  Widget _legendeCorr() => Container(
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Expanded(child: _lItem('🔴', '>0.80', 'Doublon')),
        Expanded(child: _lItem('🟠', '0.50–0.80', 'Forte')),
        Expanded(child: _lItem('🟡', '0.20–0.50', 'Légère')),
      ],
    ),
  );

  Widget _lItem(String e, String s, String l) => Column(
    children: [
      Text(e, style: const TextStyle(fontSize: 14)),
      Text(s, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
      Text(l, style: const TextStyle(color: Colors.white54, fontSize: 15)),
    ],
  );

  Widget _tableauCorrHeader() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFFFFD700).withValues(alpha: 0.10),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
    ),
    child: const Row(
      children: [
        SizedBox(width: 24),
        Expanded(flex: 3, child: _TH('Critère A')),
        Expanded(flex: 3, child: _TH('Critère B')),
        SizedBox(width: 48, child: _TH('r', center: true)),
        Expanded(flex: 3, child: _TH('Interprétation', right: true)),
      ],
    ),
  );

  Widget _ligneCorr(_PaireDisc p) {
    final absR  = p.r.abs();
    final color = absR >= 0.80 ? const Color(0xFFEF5350)
                : absR >= 0.50 ? const Color(0xFFFF9800)
                : const Color(0xFFFFD700);
    final emoji = absR >= 0.80 ? '🔴' : absR >= 0.50 ? '🟠' : '🟡';
    final interp = absR >= 0.80 ? 'Doublon probable'
                 : absR >= 0.50 ? 'Forte relation'
                 : 'Relation légère';
    final rStr  = (p.r >= 0 ? '+' : '') + p.r.toStringAsFixed(2);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        border: Border(
          left: BorderSide(color: color, width: 3),
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(width: 24, child: Text(emoji, style: const TextStyle(fontSize: 15))),
          Expanded(
            flex: 3,
            child: Text(_abrev(p.labelA),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(_abrev(p.labelB),
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(rStr,
              style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(interp,
              style: TextStyle(color: color.withValues(alpha: 0.85), fontSize: 14),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ── Abréger label ─────────────────────────────────────────────────────────
  static String _abrev(String label) {
    final parts = label.split('—');
    if (parts.length < 2) return label;
    final mot = parts[1].trim().split(' ').first;
    return '${parts[0].trim()} · $mot';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Data classes
// ═══════════════════════════════════════════════════════════════════════════

class _DiscData {
  final int nbCourses;
  final int nbAvecResultat;
  final int nbPartants;
  final int critersVivants;
  final List<_CritereDisc> criteres;
  final List<_PaireDisc>   paires;

  const _DiscData({
    required this.nbCourses,
    required this.nbAvecResultat,
    required this.nbPartants,
    required this.critersVivants,
    required this.criteres,
    required this.paires,
  });

  // ★ v10.33 : sérialisation cache
  Map<String, dynamic> toJson() => {
    'nbCourses': nbCourses, 'nbAvecResultat': nbAvecResultat,
    'nbPartants': nbPartants, 'critersVivants': critersVivants,
    'criteres': criteres.map((c) => c.toJson()).toList(),
    'paires':   paires.map((p) => p.toJson()).toList(),
  };

  factory _DiscData.fromJson(Map<String, dynamic> j) => _DiscData(
    nbCourses:      j['nbCourses'] as int,
    nbAvecResultat: j['nbAvecResultat'] as int,
    nbPartants:     j['nbPartants'] as int,
    critersVivants: j['critersVivants'] as int,
    criteres: (j['criteres'] as List).map((e) => _CritereDisc.fromJson(e as Map<String, dynamic>)).toList(),
    paires:   (j['paires']   as List).map((e) => _PaireDisc.fromJson(e   as Map<String, dynamic>)).toList(),
  );
}

class _CritereDisc {
  final String cle;
  final String label;
  final double moyTop3;
  final double moyHorsTop5;
  final double delta;
  final int    nbTop3;
  final int    nbHorsTop5;

  const _CritereDisc({
    required this.cle,
    required this.label,
    required this.moyTop3,
    required this.moyHorsTop5,
    required this.delta,
    required this.nbTop3,
    required this.nbHorsTop5,
  });

  // ★ v10.33
  Map<String, dynamic> toJson() => {
    'cle': cle, 'label': label,
    'moyTop3': moyTop3, 'moyHorsTop5': moyHorsTop5,
    'delta': delta, 'nbTop3': nbTop3, 'nbHorsTop5': nbHorsTop5,
  };
  factory _CritereDisc.fromJson(Map<String, dynamic> j) => _CritereDisc(
    cle: j['cle'] as String, label: j['label'] as String,
    moyTop3: (j['moyTop3'] as num).toDouble(),
    moyHorsTop5: (j['moyHorsTop5'] as num).toDouble(),
    delta: (j['delta'] as num).toDouble(),
    nbTop3: j['nbTop3'] as int, nbHorsTop5: j['nbHorsTop5'] as int,
  );

  String get diagnostic {
    if (delta >= 8.0)  return 'Très utile';
    if (delta >= 4.0)  return 'Utile';
    if (delta >= 1.5)  return 'Léger signal';
    if (delta > -1.5)  return 'Neutre';
    return 'Trompeur ?';
  }

  Color get couleur {
    if (delta >= 8.0)  return const Color(0xFF00E676);
    if (delta >= 4.0)  return const Color(0xFF2196F3);
    if (delta >= 1.5)  return const Color(0xFFFF6D00);
    if (delta > -1.5)  return Colors.white38;
    return const Color(0xFFEF5350);
  }
}

class _PaireDisc {
  final String cleA, cleB;
  final String labelA, labelB;
  final double r;
  final int    n;

  const _PaireDisc({
    required this.cleA, required this.cleB,
    required this.labelA, required this.labelB,
    required this.r, required this.n,
  });

  // ★ v10.33
  Map<String, dynamic> toJson() => {
    'cleA': cleA, 'cleB': cleB,
    'labelA': labelA, 'labelB': labelB,
    'r': r, 'n': n,
  };
  factory _PaireDisc.fromJson(Map<String, dynamic> j) => _PaireDisc(
    cleA: j['cleA'] as String, cleB: j['cleB'] as String,
    labelA: j['labelA'] as String, labelB: j['labelB'] as String,
    r: (j['r'] as num).toDouble(), n: j['n'] as int,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
//  Widgets helpers internes
// ═══════════════════════════════════════════════════════════════════════════

class _TH extends StatelessWidget {
  final String text;
  final bool right;
  final bool center;
  const _TH(this.text, {this.right = false, this.center = false});

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(color: Color(0xFFFFD700), fontSize: 14, fontWeight: FontWeight.bold),
    textAlign: right ? TextAlign.right : center ? TextAlign.center : TextAlign.left,
  );
}

class _TV extends StatelessWidget {
  final String text;
  final Color  color;
  final bool   bold;
  const _TV(this.text, this.color, {this.bold = false});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 42,
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 14, fontWeight: bold ? FontWeight.bold : FontWeight.normal),
      textAlign: TextAlign.center,
    ),
  );
}
