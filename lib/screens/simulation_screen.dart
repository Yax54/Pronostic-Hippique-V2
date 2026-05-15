import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/simulation_models.dart';
import '../services/simulation_service.dart';
import '../widgets/ia/simulation_assistant_panel.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  SimulationScreen — Laboratoire IA  ★ v10.30
//
//  LECTURE SEULE — aucune modification des poids, aucun apprentissage.
//  "Sauvegarder candidat" → SharedPreferences uniquement, jamais IaMemoryService.
//
//  Nouveautés v10.30 :
//  • Sliders "modifiés seulement" — les 19 non touchés sont masqués
//  • Ajout de critère via sélecteur "+" pour l'activer
//  • Badge danger surpondération (≥2 critères > 1.6x ou 1 critère = 2.0)
//  • Impact dominant détecté (top contributeurs positifs/négatifs)
//  • Profils presets : Conservateur / Rentable / Outsider / Stable
//  • Assistant Simulation panneau contextuel dynamique
//  • Top 5 ROI / Stabilité / Outsiders depuis candidats sauvegardés
// ═══════════════════════════════════════════════════════════════════════════

// ── Profils presets ──────────────────────────────────────────────────────────
class _Preset {
  final String            label;
  final String            emoji;
  final Color             color;
  final String            tooltip;
  final Map<String, double> mults;
  const _Preset(this.label, this.emoji, this.color, this.tooltip, this.mults);
}

const _presets = [
  _Preset('Conservateur', '🛡️', Color(0xFF00E676),
    'Amplifie les critères de régularité (Forme, Constance) et réduit le risque (Cote).',
    {'f': 1.3, 'k': 1.3, 'c': 0.7, 'r': 1.2}),
  _Preset('Rentable', '💰', Color(0xFFFFD700),
    'Maximise le ROI : amplifie Divergence et réduit Gains (effet outsiders).',
    {'dv': 1.4, 'g': 0.7, 'mc': 1.3, 'c': 0.8}),
  _Preset('Outsider', '🎲', Color(0xFFFF9800),
    'Recherche les chevaux surprises : Cote amplifiée, Forme réduite.',
    {'c': 1.5, 'f': 0.6, 'dv': 1.3, 'pg': 1.2}),
  _Preset('Stable', '📐', Color(0xFF00BCD4),
    'Maximise Top3 : amplifie Forme, Distance, Hippodrome.',
    {'f': 1.3, 'ds': 1.3, 'hp': 1.2, 'k': 1.2}),
];

// ── Screen ───────────────────────────────────────────────────────────────────
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

  // Tous les critères vivants (clés courtes)
  List<String> _tousLesCriters = [];

  // Critères "actifs" dans l'écran (ceux dont le slider est affiché)
  // = ceux dont le multiplicateur ≠ 1.0 OU ajoutés manuellement
  final Set<String> _critersActifs = {};

  // Multiplicateurs courants (clé courte → valeur 0.5–2.0)
  final Map<String, double> _mults = {};

  // Candidats sauvegardés
  List<Map<String, dynamic>> _candidats = [];
  bool _showCandidats = false;

  // Expansion sections
  bool _presetExpanded  = false;
  bool _assistantExpanded = true;

  static const _disciplines = ['Toutes', 'Plat', 'Trot', 'Obstacle'];
  static const Color _gold = Color(0xFFFFD700);
  static const Color _bg   = Color(0xFF0D1B2A);
  static const Color _cyan = Color(0xFF00E5FF);

  @override
  void initState() {
    super.initState();
    _tousLesCriters = _svc.critersVivants();
    _chargerCandidats();
  }

  Future<void> _chargerCandidats() async {
    final c = await _svc.chargerCandidats();
    if (mounted) setState(() => _candidats = c);
  }

  // ── Critères affichés = actifs (modifiés) ────────────────────────────────
  List<String> get _critersAffiches => _tousLesCriters
      .where((k) => _critersActifs.contains(k) || (_mults[k] ?? 1.0) != 1.0)
      .toList();

  // ── Lancer la simulation ──────────────────────────────────────────────────
  Future<void> _lancer() async {
    setState(() { _enCours = true; _showResult = false; });
    await Future.delayed(const Duration(milliseconds: 80));

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

  // ── Reset ─────────────────────────────────────────────────────────────────
  void _reset() => setState(() {
    _mults.clear();
    _critersActifs.clear();
    _showResult = false;
    _resultat   = null;
  });

  // ── Appliquer preset ──────────────────────────────────────────────────────
  void _appliquerPreset(_Preset p) {
    setState(() {
      _mults.clear();
      _critersActifs.clear();
      _showResult = false;
      _resultat   = null;
      for (final e in p.mults.entries) {
        if (_tousLesCriters.contains(e.key)) {
          _mults[e.key]       = e.value;
          _critersActifs.add(e.key);
        }
      }
    });
  }

  // ── Test prudent / agressif ───────────────────────────────────────────────
  void _testPrudent() {
    setState(() {
      for (final k in _critersActifs) {
        final v = _mults[k] ?? 1.0;
        // Ramène tous les multiplicateurs vers 1.0 de 30%
        _mults[k] = 1.0 + (v - 1.0) * 0.5;
      }
      // Si rien d'actif, applique preset Conservateur
      if (_critersActifs.isEmpty) _appliquerPreset(_presets[0]);
      _showResult = false;
      _resultat   = null;
    });
  }

  void _testAgressif() {
    setState(() {
      for (final k in _critersActifs) {
        final v = _mults[k] ?? 1.0;
        // Amplifie de 30% supplémentaires
        _mults[k] = (1.0 + (v - 1.0) * 1.5).clamp(0.5, 2.0);
      }
      if (_critersActifs.isEmpty) _appliquerPreset(_presets[1]);
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

  // ── Sélecteur d'ajout de critère ──────────────────────────────────────────
  Future<void> _ajouterCritere() async {
    final disponibles = _tousLesCriters
        .where((k) => !_critersActifs.contains(k) && (_mults[k] ?? 1.0) == 1.0)
        .toList();
    if (disponibles.isEmpty) return;

    final choix = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2744),
        title: const Text('Ajouter un critère', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 280,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: disponibles.length,
            itemBuilder: (ctx2, i) {
              final k = disponibles[i];
              return ListTile(
                dense: true,
                title: Text(kLabelsSimu[k] ?? k,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
                onTap: () => Navigator.pop(ctx, k),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );

    if (choix != null && mounted) {
      setState(() => _critersActifs.add(choix));
    }
  }

  // ── Build principal ───────────────────────────────────────────────────────
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
          // Badge candidats
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
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBandeauLecture(),
                  _buildSecteurDiscipline(),
                  _buildPresets(),
                  _buildSecteurSliders(),
                  _buildBoutonLancer(),
                  if (_enCours) _buildChargement(),
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
                            _buildFiabiliteBloc(_resultat!),
                          ],
                        ),
                      ),
                    ),
                  ],
                  // ── Panneau assistant (toujours visible, dans le scroll) ──
                  _buildAssistantSection(),
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

  // ── Discipline ────────────────────────────────────────────────────────────
  Widget _buildSecteurDiscipline() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text('Discipline',
          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
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

  // ── Profils presets ───────────────────────────────────────────────────────
  Widget _buildPresets() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      GestureDetector(
        onTap: () => setState(() => _presetExpanded = !_presetExpanded),
        child: Row(
          children: [
            const Text('Profils rapides',
              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
            const Spacer(),
            Icon(
              _presetExpanded ? Icons.expand_less : Icons.expand_more,
              color: Colors.white38, size: 18,
            ),
          ],
        ),
      ),
      if (_presetExpanded) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: _presets.map((p) => Tooltip(
            message: p.tooltip,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: p.color,
                side: BorderSide(color: p.color.withValues(alpha: 0.6)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => _appliquerPreset(p),
              child: Text('${p.emoji} ${p.label}',
                style: TextStyle(fontSize: 12, color: p.color, fontWeight: FontWeight.w600)),
            ),
          )).toList(),
        ),
        const SizedBox(height: 6),
        const Text(
          'Les profils appliquent des multiplicateurs typiques — modifiez ensuite à la main.',
          style: TextStyle(color: Colors.white24, fontSize: 10, fontStyle: FontStyle.italic),
        ),
      ],
      const SizedBox(height: 12),
    ],
  );

  // ── Sliders — affichage critères modifiés seulement ───────────────────────
  Widget _buildSecteurSliders() {
    if (_tousLesCriters.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'Pas encore assez de données pour détecter des critères vivants.',
          style: TextStyle(color: Colors.white38, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      );
    }

    final affiches = _critersAffiches;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── En-tête section sliders ─────────────────────────────────────
        Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Multiplicateurs',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                Text(
                  affiches.isEmpty
                      ? 'Aucun critère modifié — appuie sur + pour commencer'
                      : '${affiches.length} critère(s) actif(s) · ${_tousLesCriters.length - affiches.length} masqués',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
            const Spacer(),
            // Bouton réinitialiser
            if (affiches.isNotEmpty)
              TextButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.refresh, size: 13, color: Colors.white38),
                label: const Text('Réinit.', style: TextStyle(color: Colors.white38, fontSize: 11)),
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (affiches.isEmpty)
          // Aucun slider actif → invite à ajouter
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                style: BorderStyle.solid,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.tune, color: Colors.white24, size: 18),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Tous les critères sont à leur valeur neutre (x1.0).\n'
                    'Appuie sur "+" pour modifier un critère ou utilise un profil rapide.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
              ],
            ),
          )
        else
          // Sliders des critères actifs
          ...affiches.map((k) => _buildSlider(k)),

        // ── Bouton ajouter critère ──────────────────────────────────────
        const SizedBox(height: 6),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: _cyan,
            side: BorderSide(color: _cyan.withValues(alpha: 0.4)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const Icon(Icons.add, size: 14),
          label: Text(
            'Ajouter un critère (${_tousLesCriters.length - _critersAffiches.length} disponibles)',
            style: const TextStyle(fontSize: 11),
          ),
          onPressed: _tousLesCriters.length > _critersAffiches.length
              ? _ajouterCritere
              : null,
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildSlider(String k) {
    final val   = _mults[k] ?? 1.0;
    final label = kLabelsSimu[k] ?? k;
    final isModified = (val - 1.0).abs() > 0.01;
    final color = val > 1.05
        ? const Color(0xFF00E676)
        : val < 0.95
            ? const Color(0xFFEF5350)
            : Colors.white54;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          // Retirer du panneau si modif nulle
          if (!isModified)
            GestureDetector(
              onTap: () => setState(() {
                _mults.remove(k);
                _critersActifs.remove(k);
              }),
              child: const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.close, size: 13, color: Colors.white24),
              ),
            )
          else
            const SizedBox(width: 17),
          SizedBox(
            width: 95,
            child: Text(label,
              style: TextStyle(
                color: isModified ? Colors.white : Colors.white54,
                fontSize: 11,
                fontWeight: isModified ? FontWeight.w600 : FontWeight.normal,
              )),
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
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  // ── Bouton lancer ─────────────────────────────────────────────────────────
  Widget _buildBoutonLancer() => Padding(
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

  // ── Section assistant (expandable) ────────────────────────────────────────
  Widget _buildAssistantSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Toggle expansion
      GestureDetector(
        onTap: () => setState(() => _assistantExpanded = !_assistantExpanded),
        child: Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, color: Color(0xFF00E5FF), size: 16),
              const SizedBox(width: 8),
              const Text('Assistant Simulation',
                style: TextStyle(color: Color(0xFF00E5FF), fontSize: 13, fontWeight: FontWeight.bold)),
              const Spacer(),
              Icon(
                _assistantExpanded ? Icons.expand_less : Icons.expand_more,
                color: const Color(0xFF00E5FF), size: 18,
              ),
            ],
          ),
        ),
      ),
      if (_assistantExpanded)
        SimulationAssistantPanel(
          discipline: _params.discipline,
          mults:      Map.from(_mults),
          resultat:   _showResult ? _resultat : null,
          candidats:  _candidats,
          onTestPrudent:  _testPrudent,
          onTestAgressif: _testAgressif,
          onReset:        _reset,
          onSauvegarder:  _sauvegarderCandidat,
          onExporter:     _exporter,
        ),
    ],
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

  // ── Tableau comparaison ───────────────────────────────────────────────────
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.10),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 3, child: Text('Mesure',      style: TextStyle(color: _gold, fontSize: 11, fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('IA actuelle', style: TextStyle(color: _gold, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text('Simulation',  style: TextStyle(color: _gold, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text('Δ',           style: TextStyle(color: _gold, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
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
          Expanded(flex: 3, child: Text(label,    style: const TextStyle(color: Colors.white70, fontSize: 12))),
          Expanded(flex: 2, child: Text(avant,    style: const TextStyle(color: Colors.white,   fontSize: 12), textAlign: TextAlign.center)),
          Expanded(flex: 2, child: Text(apres,    style: const TextStyle(color: Colors.white,   fontSize: 12), textAlign: TextAlign.center)),
          Expanded(flex: 2, child: Text(deltaStr, style: TextStyle(color: deltaColor, fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  // ── Blocs périodes ────────────────────────────────────────────────────────
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

  // ── Bloc fiabilité ────────────────────────────────────────────────────────
  Widget _buildFiabiliteBloc(SimulationResultat res) => Container(
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

  // ── Liste candidats ───────────────────────────────────────────────────────
  Widget _buildListeCandidats() => Column(
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
                title: Text(nom,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
