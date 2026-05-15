import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/simulation_models.dart';
import '../services/simulation_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  SimulationScreen — Laboratoire IA
//
//  LECTURE SEULE — aucune modification des poids, aucun apprentissage.
//  "Sauvegarder candidat" → SharedPreferences uniquement, jamais IaMemoryService.
// ═══════════════════════════════════════════════════════════════════════════

class SimulationScreen extends StatefulWidget {
  const SimulationScreen({super.key});

  @override
  State<SimulationScreen> createState() => _SimulationScreenState();
}

class _SimulationScreenState extends State<SimulationScreen> {
  final GlobalKey _repaintKey = GlobalKey();
  final SimulationService _svc = SimulationService.instance;

  // ── État ──────────────────────────────────────────────────────────────────
  SimulationParams _params = const SimulationParams();
  SimulationResultat? _resultat;
  bool _enCours    = false;
  bool _showResult = false;

  // Critères vivants (clés courtes)
  List<String> _critersVivants = [];

  // Multiplicateurs courants (clé courte → valeur 0.5–2.0)
  final Map<String, double> _mults = {};

  // Candidats sauvegardés
  List<Map<String, dynamic>> _candidats = [];
  bool _showCandidats = false;

  static const _disciplines = ['Toutes', 'Plat', 'Trot', 'Obstacle'];
  static const Color _gold = Color(0xFFFFD700);
  static const Color _bg   = Color(0xFF0D1B2A);

  @override
  void initState() {
    super.initState();
    _critersVivants = _svc.critersVivants();
    _chargerCandidats();
  }

  Future<void> _chargerCandidats() async {
    final c = await _svc.chargerCandidats();
    setState(() => _candidats = c);
  }

  // ── Lancer la simulation ──────────────────────────────────────────────────
  Future<void> _lancer() async {
    setState(() { _enCours = true; _showResult = false; });
    await Future.delayed(const Duration(milliseconds: 80)); // laisser Flutter redessiner

    final params = SimulationParams(
      discipline:      _params.discipline,
      multiplicateurs: Map.from(_mults),
    );

    final res = await Future(() => _svc.simuler(params));

    setState(() {
      _resultat   = res;
      _params     = params;
      _enCours    = false;
      _showResult = true;
    });
  }

  void _reset() {
    setState(() {
      _mults.clear();
      _showResult = false;
      _resultat   = null;
    });
  }

  // ── Export ────────────────────────────────────────────────────────────────
  Future<void> _exporter() async {
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image    = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes    = byteData.buffer.asUint8List();
      final dir      = await getTemporaryDirectory();
      final file     = File('${dir.path}/simulation_ia.png');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(ShareParams(
        files:   [XFile(file.path, mimeType: 'image/png')],
        subject: 'Simulation IA — ${_params.discipline} — Pronostic Hippique',
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur export : $e')),
        );
      }
    }
  }

  // ── Sauvegarder candidat ──────────────────────────────────────────────────
  Future<void> _sauvegarderCandidat() async {
    if (_resultat == null) return;
    final nom = await _demanderNom();
    if (nom == null || nom.trim().isEmpty) return;
    await _svc.sauvegarderCandidat(_resultat!, nom.trim());
    await _chargerCandidats();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Candidat sauvegardé — aucun poids modifié'),
          backgroundColor: Color(0xFF2E7D32),
        ),
      );
    }
  }

  Future<String?> _demanderNom() async {
    final ctrl = TextEditingController(
      text: 'Simu ${_params.discipline} ${DateTime.now().day}/${DateTime.now().month}',
    );
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2744),
        title: const Text('Nom du candidat', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Ex: Trot Distance +40%',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFFFD700)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _gold),
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Sauvegarder', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: const Text('🧪 Laboratoire IA',
          style: TextStyle(color: _gold, fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          // Candidats sauvegardés
          if (_candidats.isNotEmpty)
            IconButton(
              icon: Badge(
                label: Text('${_candidats.length}'),
                child: const Icon(Icons.history, color: Colors.white70),
              ),
              onPressed: () => setState(() => _showCandidats = !_showCandidats),
            ),
        ],
      ),
      body: _showCandidats
          ? _buildListeCandidats()
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBandeauLecture(),
                  _buildSecteurDiscipline(),
                  _buildSecteurSliders(),
                  _buildBoutons(),
                  if (_enCours)    _buildChargement(),
                  if (_showResult && _resultat != null) ...[
                    RepaintBoundary(
                      key: _repaintKey,
                      child: Container(
                        color: _bg,
                        child: Column(
                          children: [
                            _buildVerdictBanner(_resultat!),
                            _buildTableauComparaison(_resultat!),
                            _buildBlocPeriode('Historique complet', _resultat!.avant, _resultat!.apres),
                            _buildBlocPeriode('30 derniers jours',  _resultat!.avant30j, _resultat!.apres30j),
                            _buildBlocPeriode('7 derniers jours',   _resultat!.avant7j,  _resultat!.apres7j),
                            _buildFiabilite(_resultat!),
                          ],
                        ),
                      ),
                    ),
                    _buildBoutonsResultat(),
                  ],
                ],
              ),
            ),
    );
  }

  // ── Bandeau lecture seule ─────────────────────────────────────────────────
  Widget _buildBandeauLecture() => Container(
    margin: const EdgeInsets.only(bottom: 10, top: 4),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.blue.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
    ),
    child: const Row(
      children: [
        Icon(Icons.science_outlined, color: Colors.blue, size: 16),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Lecture seule — aucun poids modifié, aucun apprentissage',
            style: TextStyle(color: Colors.blue, fontSize: 12),
          ),
        ),
      ],
    ),
  );

  // ── Sélecteur discipline ──────────────────────────────────────────────────
  Widget _buildSecteurDiscipline() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text('Discipline', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
      ),
      Wrap(
        spacing: 8,
        children: _disciplines.map((d) {
          final sel = _params.discipline == d;
          return ChoiceChip(
            label: Text(d, style: TextStyle(
              color: sel ? Colors.black : Colors.white70,
              fontWeight: sel ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            )),
            selected: sel,
            selectedColor: _gold,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            side: BorderSide(color: sel ? _gold : Colors.white24),
            onSelected: (_) => setState(() {
              _params = _params.copyWith(discipline: d);
              _showResult = false;
            }),
          );
        }).toList(),
      ),
      const SizedBox(height: 14),
    ],
  );

  // ── Sliders multiplicateurs ───────────────────────────────────────────────
  Widget _buildSecteurSliders() {
    if (_critersVivants.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'Pas encore assez de données pour détecter des critères vivants.',
          style: TextStyle(color: Colors.white38, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Multiplicateurs', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.refresh, size: 14, color: Colors.white38),
              label: const Text('Réinitialiser', style: TextStyle(color: Colors.white38, fontSize: 12)),
            ),
          ],
        ),
        const Text(
          '1.0 = neutre · Glissez pour amplifier ou réduire un critère',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
        const SizedBox(height: 8),
        ..._critersVivants.map((k) => _buildSlider(k)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildSlider(String k) {
    final val   = _mults[k] ?? 1.0;
    final label = kLabelsSimu[k] ?? k;
    final color = val > 1.05
        ? const Color(0xFF00E676)
        : val < 0.95
            ? const Color(0xFFEF5350)
            : Colors.white54;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor:   color,
                thumbColor:         color,
                inactiveTrackColor: Colors.white12,
                overlayColor:       color.withValues(alpha: 0.15),
                trackHeight:        3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value:    val,
                min:      0.5,
                max:      2.0,
                divisions: 30,
                onChanged: (v) => setState(() => _mults[k] = v),
              ),
            ),
          ),
          SizedBox(
            width: 38,
            child: Text(
              'x${val.toStringAsFixed(1)}',
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  // ── Bouton principal ──────────────────────────────────────────────────────
  Widget _buildBoutons() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: _gold,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.play_arrow_rounded, size: 22),
        label: const Text('Lancer la simulation',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        onPressed: _enCours ? null : _lancer,
      ),
    ),
  );

  Widget _buildChargement() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 24),
    child: Center(child: Column(children: [
      CircularProgressIndicator(color: _gold),
      SizedBox(height: 12),
      Text('Calcul en cours…', style: TextStyle(color: Colors.white54, fontSize: 13)),
    ])),
  );

  // ── Verdict ───────────────────────────────────────────────────────────────
  Widget _buildVerdictBanner(SimulationResultat res) {
    final v = res.verdict;
    Color color;
    if (v.startsWith('🟢'))      color = const Color(0xFF00E676);
    else if (v.startsWith('🟡')) color = const Color(0xFFFFD700);
    else if (v.startsWith('🟠')) color = const Color(0xFFFF9800);
    else if (v.startsWith('🔴')) color = const Color(0xFFEF5350);
    else                          color = Colors.white38;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Verdict', style: TextStyle(color: color, fontSize: 11)),
          const SizedBox(height: 4),
          Text(v, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ── Tableau comparaison principal ─────────────────────────────────────────
  Widget _buildTableauComparaison(SimulationResultat res) {
    final a = res.avant;
    final s = res.apres;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.10),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 3, child: Text('Mesure',        style: TextStyle(color: _gold, fontSize: 11, fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('IA actuelle',   style: TextStyle(color: _gold, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text('Simulation',    style: TextStyle(color: _gold, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text('Δ',             style: TextStyle(color: _gold, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
              ],
            ),
          ),
          _ligneCompa('Courses testées', '${a.nbCourses}',            '${s.nbCourses}',            null),
          _ligneCompa('Courses ROI',     '${a.nbCoursesRoi}',         '${s.nbCoursesRoi}',         null),
          _ligneCompa('Top1 gagnant',    '${a.top1.toStringAsFixed(1)}%', '${s.top1.toStringAsFixed(1)}%', s.top1 - a.top1, pct: true),
          _ligneCompa('Top3 touché',     '${a.top3.toStringAsFixed(1)}%', '${s.top3.toStringAsFixed(1)}%', s.top3 - a.top3, pct: true),
          _ligneCompa('Top5 touché',     '${a.top5.toStringAsFixed(1)}%', '${s.top5.toStringAsFixed(1)}%', s.top5 - a.top5, pct: true),
          _ligneCompa('ROI théorique',   '${a.roi.toStringAsFixed(1)}%',  '${s.roi.toStringAsFixed(1)}%',  s.roi - a.roi,  pct: true),
          _ligneCompa('Gain net (€)',    '${a.gainNet.toStringAsFixed(2)}€', '${s.gainNet.toStringAsFixed(2)}€', s.gainNet - a.gainNet),
          _ligneCompa('Outsiders Top3',  '${a.outsiders}',            '${s.outsiders}',            (s.outsiders - a.outsiders).toDouble()),
        ],
      ),
    );
  }

  Widget _ligneCompa(String label, String avant, String apres, double? delta, {bool pct = false}) {
    Color deltaColor = Colors.white54;
    String deltaStr  = '—';
    if (delta != null) {
      deltaStr  = (delta >= 0 ? '+' : '') + (pct ? '${delta.toStringAsFixed(1)}%' : delta.toStringAsFixed(2));
      deltaColor = delta > 0.1 ? const Color(0xFF00E676)
                 : delta < -0.1 ? const Color(0xFFEF5350)
                 : Colors.white38;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12))),
          Expanded(flex: 2, child: Text(avant, style: const TextStyle(color: Colors.white,   fontSize: 12), textAlign: TextAlign.center)),
          Expanded(flex: 2, child: Text(apres, style: const TextStyle(color: Colors.white,   fontSize: 12), textAlign: TextAlign.center)),
          Expanded(flex: 2, child: Text(deltaStr, style: TextStyle(color: deltaColor, fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  // ── Bloc par période ──────────────────────────────────────────────────────
  Widget _buildBlocPeriode(String titre, SimBloc avant, SimBloc apres) {
    if (avant.nbCourses == 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(titre, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text(avant.fiabiliteLabel, style: const TextStyle(color: Colors.white54, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _miniStat('Top3', '${avant.top3.toStringAsFixed(0)}%', '${apres.top3.toStringAsFixed(0)}%', apres.top3 - avant.top3),
              _miniStat('ROI',  '${avant.roi.toStringAsFixed(1)}%',  '${apres.roi.toStringAsFixed(1)}%',  apres.roi  - avant.roi),
              _miniStat('Top1', '${avant.top1.toStringAsFixed(0)}%', '${apres.top1.toStringAsFixed(0)}%', apres.top1 - avant.top1),
              _miniStat('n',    '${avant.nbCourses}',                '${apres.nbCourses}',                null),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String av, String ap, double? d) {
    Color c = Colors.white38;
    String ds = '';
    if (d != null) {
      c  = d > 0.5 ? const Color(0xFF00E676) : d < -0.5 ? const Color(0xFFEF5350) : Colors.white38;
      ds = (d >= 0 ? '↑' : '↓');
    }
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
          Text('$av→$ap', style: const TextStyle(color: Colors.white70, fontSize: 11)),
          if (ds.isNotEmpty) Text(ds, style: TextStyle(color: c, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ── Fiabilité globale ─────────────────────────────────────────────────────
  Widget _buildFiabilite(SimulationResultat res) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Fiabilité', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        _fiabLigne('<30 courses',    '⚠️ Très faible — non exploitable'),
        _fiabLigne('30–50 courses',  '🟡 Indicatif — prudence requise'),
        _fiabLigne('50–150 courses', '🟠 Intéressant — piste à surveiller'),
        _fiabLigne('>150 courses',   '🟢 Exploitable — résultat fiable'),
        const SizedBox(height: 4),
        Text(
          'Courses ROI : ${res.apres.nbCoursesRoi} (dividende ou cote disponibles)',
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
          ),
          child: const Text(
            '⚠️ La simulation mesure les performances sur l\'historique passé.\n'
            'Un bon résultat sur l\'historique complet peut refléter du sur-apprentissage.\n'
            'Validez toujours sur la période récente (30j/7j) avant de tirer des conclusions.',
            style: TextStyle(color: Colors.orange, fontSize: 11),
          ),
        ),
      ],
    ),
  );

  Widget _fiabLigne(String seuil, String desc) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(children: [
      SizedBox(width: 90, child: Text(seuil, style: const TextStyle(color: Colors.white38, fontSize: 10))),
      Text(desc, style: const TextStyle(color: Colors.white54, fontSize: 10)),
    ]),
  );

  // ── Boutons après résultats ───────────────────────────────────────────────
  Widget _buildBoutonsResultat() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _gold,
              side: const BorderSide(color: _gold),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.share, size: 16),
            label: const Text('Export PNG', style: TextStyle(fontSize: 12)),
            onPressed: _exporter,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.bookmark_add, size: 16, color: Colors.white),
            label: const Text('Sauvegarder', style: TextStyle(color: Colors.white, fontSize: 12)),
            onPressed: _sauvegarderCandidat,
          ),
        ),
      ],
    ),
  );

  // ── Liste candidats ───────────────────────────────────────────────────────
  Widget _buildListeCandidats() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Text('Journal des candidats',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _showCandidats = false),
                child: const Text('← Retour', style: TextStyle(color: _gold)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _candidats.length,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemBuilder: (ctx, i) {
              final c       = _candidats[i];
              final nom     = c['nom'] as String? ?? '—';
              final date    = c['date'] as String? ?? '';
              final verdict = (c['resultat'] as Map?)?['verdict'] as String? ?? '—';
              final id      = c['id'] as String? ?? '';
              final disc    = ((c['resultat'] as Map?)?['params'] as Map?)?['discipline'] as String? ?? '—';

              return Card(
                color: const Color(0xFF1A2744),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(nom, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Text('$disc · $date\n$verdict',
                    style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () async {
                      await _svc.supprimerCandidat(id);
                      await _chargerCandidats();
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
