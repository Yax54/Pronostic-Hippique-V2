// ═══════════════════════════════════════════════════════════════════════════
//  SimulationScreen — Laboratoire IA  ★ v10.32
//
//  LECTURE SEULE — aucune modification des poids, aucun apprentissage.
//  "Enregistrer comme piste" → SimulationCandidateService (SharedPreferences),
//  jamais IaMemoryService.
//
//  Nouveautés v10.32 :
//  • Tailles de texte augmentées (lisibilité mobile)
//  • Bandeau verdict agrandi avec emoji et phrase claire
//  • Saisie manuelle coefficient (champ texte + slider synchronisés)
//  • Bloc "Critères modifiés" et "Critères inactifs" (repliable)
//  • Presets discipline-aware : Plat/Trot/Obstacle × prudent/agressif
//  • Export PNG page entière via RepaintBoundary hors écran
//  • Bouton "Mes pistes" → push navigation interne
//  • Renommage "Enregistrer comme piste" + sous-texte sécurité
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/simulation_models.dart';
import '../models/simulation_candidate_model.dart';
import '../services/simulation_service.dart';
import '../services/simulation_candidate_service.dart';
import '../widgets/ia/simulation_assistant_panel.dart';

// ══════════════════════════════════════════════════════════════════════════
//  Presets discipline-aware ★ v10.32
// ══════════════════════════════════════════════════════════════════════════

class _Preset {
  final String label;
  final String emoji;
  final Color  color;
  final String discipline;  // 'Plat' | 'Trot' | 'Obstacle' | 'Toutes'
  final String type;        // 'prudent' | 'agressif'
  final Map<String, double> mults;
  const _Preset(this.label, this.emoji, this.color, this.discipline, this.type, this.mults);
}

const _presets = [
  // Plat
  _Preset('Plat prudent',   '🛡️', Color(0xFF00E676), 'Plat',     'prudent',
      {'dv': 1.20, 'g': 0.80, 'ds': 0.90}),
  _Preset('Plat agressif',  '🚀', Color(0xFFEF5350), 'Plat',     'agressif',
      {'dv': 1.35, 'g': 0.60, 'ds': 0.80}),
  // Trot
  _Preset('Trot prudent',   '🛡️', Color(0xFF00E676), 'Trot',     'prudent',
      {'ds': 1.20, 'g': 1.10, 'j': 0.90}),
  _Preset('Trot agressif',  '🚀', Color(0xFFEF5350), 'Trot',     'agressif',
      {'ds': 1.30, 'g': 1.15, 'j': 0.85}),
  // Obstacle
  _Preset('Obstacle prudent',  '🛡️', Color(0xFF00E676), 'Obstacle', 'prudent',
      {'f': 1.20, 'hp': 1.20, 'g': 0.80, 'dv': 0.80}),
  _Preset('Obstacle agressif', '🚀', Color(0xFFEF5350), 'Obstacle', 'agressif',
      {'f': 1.40, 'hp': 1.30, 'g': 0.60, 'dv': 0.70}),
];

// Critères inactifs connus avec leurs raisons
const _critersInactifs = <String, String>{
  'tr':  'Terrain : données insuffisantes',
  'rp':  'Repos : fallback 50',
  'mc':  'Mouvement cote : historique absent',
  'pd':  'Place départ : non alimenté',
  'r':   'Record : non exploitable',
};

// ══════════════════════════════════════════════════════════════════════════
//  SimulationScreen
// ══════════════════════════════════════════════════════════════════════════

class SimulationScreen extends StatefulWidget {
  // Pré-remplissage depuis "Mes pistes" → Rejouer
  final String?              preloadDiscipline;
  final Map<String, double>? preloadCoefficients;

  const SimulationScreen({
    super.key,
    this.preloadDiscipline,
    this.preloadCoefficients,
  });

  @override
  State<SimulationScreen> createState() => _SimulationScreenState();
}

class _SimulationScreenState extends State<SimulationScreen> {
  // Clé pour l'export PNG page entière
  final GlobalKey _exportKey = GlobalKey();

  final SimulationService          _svc  = SimulationService.instance;
  final SimulationCandidateService _cSvc = SimulationCandidateService();

  // ── État ──────────────────────────────────────────────────────────────────
  SimulationParams   _params    = const SimulationParams();
  SimulationResultat? _resultat;
  bool _enCours    = false;
  bool _showResult = false;

  List<String> _tousLesCriters = [];
  final Set<String>    _critersActifs   = {};
  final Map<String, double> _mults      = {};

  // Saisie manuelle en cours par critère (clé → TextEditingController)
  final Map<String, TextEditingController> _textCtrls = {};
  final Map<String, String?> _textErrors = {};

  // Candidats (pour panneau assistant — historique simple)
  List<Map<String, dynamic>> _candidats = [];

  // Sections repliables
  bool _presetExpanded      = false;
  bool _assistantExpanded   = true;
  bool _inactifsExpanded    = false;

  static const _disciplines = ['Toutes', 'Plat', 'Trot', 'Obstacle'];
  static const Color _gold  = Color(0xFFFFD700);
  static const Color _bg    = Color(0xFF0D1B2A);
  static const Color _cyan  = Color(0xFF00E5FF);
  static const Color _vert  = Color(0xFF00E676);
  static const Color _rouge = Color(0xFFEF5350);

  // ── Init ──────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _tousLesCriters = _svc.critersVivants();
    _chargerCandidats();

    // Pré-remplissage si "Rejouer" depuis Mes pistes
    if (widget.preloadDiscipline != null) {
      _params = _params.copyWith(discipline: widget.preloadDiscipline!);
    }
    if (widget.preloadCoefficients != null) {
      for (final e in widget.preloadCoefficients!.entries) {
        if (_tousLesCriters.contains(e.key) && (e.value - 1.0).abs() > 0.01) {
          _mults[e.key]       = e.value;
          _critersActifs.add(e.key);
        }
      }
    }
  }

  @override
  void dispose() {
    for (final c in _textCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Charger candidats (liste simple pour le panneau) ─────────────────────
  Future<void> _chargerCandidats() async {
    final c = await _svc.chargerCandidats();
    if (mounted) setState(() => _candidats = c);
  }

  // ── Critères affichés (modifiés ou ajoutés manuellement) ─────────────────
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
  void _reset() {
    for (final c in _textCtrls.values) c.dispose();
    _textCtrls.clear();
    _textErrors.clear();
    setState(() {
      _mults.clear();
      _critersActifs.clear();
      _showResult = false;
      _resultat   = null;
    });
  }

  // ── Appliquer preset ──────────────────────────────────────────────────────
  void _appliquerPreset(_Preset p) {
    for (final c in _textCtrls.values) c.dispose();
    _textCtrls.clear();
    _textErrors.clear();
    setState(() {
      _mults.clear();
      _critersActifs.clear();
      _showResult = false;
      _resultat   = null;
      // Ajuster la discipline si besoin
      if (p.discipline != 'Toutes') {
        _params = _params.copyWith(discipline: p.discipline);
      }
      for (final e in p.mults.entries) {
        if (_tousLesCriters.contains(e.key)) {
          _mults[e.key]       = e.value;
          _critersActifs.add(e.key);
        }
      }
    });
  }

  // ── Test prudent / agressif depuis l'assistant ────────────────────────────
  void _testPrudent() {
    final disc = _params.discipline;
    // Cherche le preset prudent correspondant
    final preset = _presets.firstWhere(
      (p) => p.discipline == disc && p.type == 'prudent',
      orElse: () => _presets.firstWhere((p) => p.type == 'prudent'),
    );
    _appliquerPreset(preset);
  }

  void _testAgressif() {
    final disc = _params.discipline;
    final preset = _presets.firstWhere(
      (p) => p.discipline == disc && p.type == 'agressif',
      orElse: () => _presets.firstWhere((p) => p.type == 'agressif'),
    );
    _appliquerPreset(preset);
  }

  // ── Saisie manuelle coefficient ★ v10.32 ──────────────────────────────────
  TextEditingController _ctrlFor(String k) {
    if (!_textCtrls.containsKey(k)) {
      final val = _mults[k] ?? 1.0;
      _textCtrls[k] = TextEditingController(text: val.toStringAsFixed(2));
    }
    return _textCtrls[k]!;
  }

  void _appliquerSaisie(String k) {
    final ctrl = _ctrlFor(k);
    final raw  = ctrl.text.trim().replaceAll(',', '.');
    final val  = double.tryParse(raw);
    if (val == null || val < 0.50 || val > 2.00) {
      setState(() => _textErrors[k] = 'Entre 0.50 et 2.00');
      return;
    }
    setState(() {
      _textErrors[k] = null;
      _mults[k]      = double.parse(val.toStringAsFixed(2));
      ctrl.text      = val.toStringAsFixed(2);
    });
  }

  // ── Export PNG page entière ★ v10.33 ──────────────────────────────────────
  // Inclut : Résultats + Critères modifiés + Verdict + Assistant complet
  Future<void> _exporter() async {
    if (_resultat == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lancez d\'abord une simulation.')));
      }
      return;
    }
    try {
      // 1. Forcer le dépliement de l'assistant pour qu'il soit dans l'image
      bool wasCollapsed = false;
      if (!_assistantExpanded) {
        wasCollapsed = true;
        setState(() => _assistantExpanded = true);
        // Laisser Flutter rendre le widget déplié
        await Future.delayed(const Duration(milliseconds: 300));
      } else {
        await Future.delayed(const Duration(milliseconds: 150));
      }

      final boundary = _exportKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Erreur : widget non rendu.')));
        }
        return;
      }

      final image    = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();
      final dir   = await getTemporaryDirectory();
      final now   = DateTime.now();
      final fname = 'simulation_ia_${_params.discipline}_'
          '${now.year}${now.month.toString().padLeft(2,"0")}${now.day.toString().padLeft(2,"0")}'
          '_${now.hour.toString().padLeft(2,"0")}${now.minute.toString().padLeft(2,"0")}.png';
      final file  = File('${dir.path}/$fname');
      await file.writeAsBytes(bytes);

      // 2. Reployer l'assistant si nécessaire
      if (wasCollapsed && mounted) {
        setState(() => _assistantExpanded = false);
      }

      await SharePlus.instance.share(ShareParams(
        files:   [XFile(file.path, mimeType: 'image/png')],
        subject: 'Simulation IA — ${_params.discipline} — Pronostic Hippique',
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur export : $e')));
      }
    }
  }

  // ── Enregistrer comme piste ★ v10.32 ──────────────────────────────────────
  Future<void> _enregistrerPiste() async {
    if (_resultat == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lancez d\'abord une simulation.')));
      return;
    }
    final nom = await _demanderNom();
    if (nom == null || nom.trim().isEmpty) return;

    // Calcul score confiance (même logique que l'assistant)
    final n = _resultat!.avant.nbCourses;
    int score;
    if (n < 30) score = 10;
    else if (n < 50) score = 35;
    else if (n < 150) score = 65;
    else score = 85;
    final dTop3 = _resultat!.apres.top3 - _resultat!.avant.top3;
    final dRoi  = _resultat!.apres.roi  - _resultat!.avant.roi;
    if (dTop3 > 0) score += 10;
    if (dRoi  > 0) score += 10;
    final nbMod = _mults.values.where((v) => (v - 1.0).abs() > 0.01).length;
    if (nbMod > 3) score -= 15;
    if (_mults.values.any((v) => v > 1.70)) score -= 20;
    score = score.clamp(0, 100);

    final candidate = SimulationCandidate(
      id:             SimulationCandidateService.generateId(),
      createdAt:      DateTime.now(),
      discipline:     _params.discipline,
      label:          nom.trim(),
      coefficients:   Map.from(_mults),
      top1Avant:      _resultat!.avant.top1,
      top1Apres:      _resultat!.apres.top1,
      top3Avant:      _resultat!.avant.top3,
      top3Apres:      _resultat!.apres.top3,
      top5Avant:      _resultat!.avant.top5,
      top5Apres:      _resultat!.apres.top5,
      roiAvant:       _resultat!.avant.roi,
      roiApres:       _resultat!.apres.roi,
      gainNetAvant:   _resultat!.avant.gainNet,
      gainNetApres:   _resultat!.apres.gainNet,
      outsidersAvant: _resultat!.avant.outsiders.toDouble(),
      outsidersApres: _resultat!.apres.outsiders.toDouble(),
      scoreConfiance: score,
      verdict:        _resultat!.verdict,
    );

    await _cSvc.saveCandidate(candidate);
    await _chargerCandidats();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Piste enregistrée — aucun poids IA modifié'),
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
        title: const Text('Nom de la piste',
          style: TextStyle(color: Colors.white, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: const InputDecoration(
                hintText: 'Ex: Trot Distance +30%',
                hintStyle: TextStyle(color: Colors.white38),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFFFD700)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Ne modifie pas l\'IA réelle.',
              style: TextStyle(color: Colors.white38, fontSize: 12,
                  fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _gold),
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Enregistrer', style: TextStyle(color: Colors.black)),
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
        title: const Text('Ajouter un critère',
          style: TextStyle(color: Colors.white, fontSize: 18)),
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
                  style: const TextStyle(color: Colors.white, fontSize: 15)),
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

  // ── Navigation vers Mes pistes ★ v10.32 ───────────────────────────────────
  Future<void> _ouvrirMesPistes() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const _MesPistesScreen()),
    );
    // Rechargement au retour (une piste peut avoir été rejouée)
    await _chargerCandidats();
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  BUILD PRINCIPAL
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: const Text('🧪 Laboratoire IA',
          style: TextStyle(color: _gold, fontWeight: FontWeight.bold, fontSize: 20)),
        actions: [
          // Bouton Mes pistes ★ v10.32
          TextButton.icon(
            icon: const Icon(Icons.bookmarks_outlined, color: _cyan, size: 18),
            label: const Text('Mes pistes',
              style: TextStyle(color: _cyan, fontSize: 13, fontWeight: FontWeight.w600)),
            onPressed: _ouvrirMesPistes,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 50),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBandeauLecture(),
            _buildSecteurDiscipline(),
            _buildPresets(),
            _buildCriteresModifies(),
            _buildSecteurSliders(),
            _buildCriteresInactifs(),
            _buildBoutonLancer(),
            if (_enCours) _buildChargement(),

            // ── Zone exportable page entière ★ v10.33 ─────────────────
            // RepaintBoundary englobe Résultats + Assistant (export complet)
            if (_showResult && _resultat != null)
              RepaintBoundary(
                key: _exportKey,
                child: Container(
                  color: _bg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildVerdictBanner(_resultat!),
                      _buildTableauComparaison(_resultat!),
                      _buildBlocPeriode('Historique complet',
                          _resultat!.avant,   _resultat!.apres),
                      _buildBlocPeriode('30 derniers jours',
                          _resultat!.avant30j, _resultat!.apres30j),
                      _buildBlocPeriode('7 derniers jours',
                          _resultat!.avant7j,  _resultat!.apres7j),
                      _buildFiabiliteBloc(_resultat!),
                      _buildPiedExport(),
                      // ★ v10.33 : Panneau assistant inclus dans l'export
                      _buildAssistantSection(),
                    ],
                  ),
                ),
              )
            else
              // Panneau assistant visible même sans simulation
              _buildAssistantSection(),
          ],
        ),
      ),
    );
  }

  // ── Bandeau lecture seule ─────────────────────────────────────────────────
  Widget _buildBandeauLecture() => Container(
    margin: const EdgeInsets.only(bottom: 12, top: 4),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.blue.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
    ),
    child: const Row(
      children: [
        Icon(Icons.science_outlined, color: Colors.blue, size: 18),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Lecture seule — aucun poids modifié, aucun apprentissage',
            style: TextStyle(color: Colors.blue, fontSize: 14),
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
        padding: EdgeInsets.only(bottom: 10),
        child: Text('Discipline',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      Wrap(
        spacing: 9,
        children: _disciplines.map((d) {
          final sel = _params.discipline == d;
          return ChoiceChip(
            label: Text(d, style: TextStyle(
              color:      sel ? Colors.black : Colors.white70,
              fontWeight: sel ? FontWeight.bold : FontWeight.normal,
              fontSize:   15,
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
      const SizedBox(height: 16),
    ],
  );

  // ── Presets discipline-aware ★ v10.32 ─────────────────────────────────────
  Widget _buildPresets() {
    // Filtre les presets pertinents selon la discipline choisie
    final disc     = _params.discipline;
    final pertinents = _presets.where(
      (p) => p.discipline == disc || disc == 'Toutes',
    ).toList();
    // Si Toutes, montre juste les presets d'une seule discipline
    final affiches = disc == 'Toutes'
        ? _presets.where((p) => p.discipline == 'Plat').toList()
        : pertinents;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _presetExpanded = !_presetExpanded),
          child: Row(
            children: [
              const Text('Profils rapides',
                style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.bold)),
              if (disc != 'Toutes')
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text('($disc)',
                    style: const TextStyle(color: _gold, fontSize: 13)),
                ),
              const Spacer(),
              Icon(_presetExpanded ? Icons.expand_less : Icons.expand_more,
                color: Colors.white38, size: 20),
            ],
          ),
        ),
        if (_presetExpanded) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 9,
            runSpacing: 8,
            children: affiches.map((p) => OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: p.color,
                side: BorderSide(color: p.color.withValues(alpha: 0.65)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => _appliquerPreset(p),
              child: Text('${p.emoji} ${p.label}',
                style: TextStyle(fontSize: 14, color: p.color, fontWeight: FontWeight.w600)),
            )).toList(),
          ),
          const SizedBox(height: 7),
          const Text(
            'Les profils appliquent des multiplicateurs typiques — modifiez ensuite à la main.',
            style: TextStyle(color: Colors.white24, fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ],
        const SizedBox(height: 14),
      ],
    );
  }

  // ── Bloc "Critères modifiés" ★ v10.32 ─────────────────────────────────────
  Widget _buildCriteresModifies() {
    final modifies = _mults.entries
        .where((e) => (e.value - 1.0).abs() > 0.01)
        .toList();
    if (modifies.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: const Row(
          children: [
            Icon(Icons.tune, color: Colors.white24, size: 18),
            SizedBox(width: 8),
            Text('Aucun critère modifié.',
              style: TextStyle(color: Colors.white38, fontSize: 17)),
          ],
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _cyan.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _cyan.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Critères modifiés',
            style: TextStyle(color: _cyan, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...modifies.map((e) {
            final label = kLabelsSimu[e.key] ?? e.key;
            final color = e.value > 1.0 ? _vert : _rouge;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(e.value > 1.0 ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 14, color: color),
                  const SizedBox(width: 6),
                  Text(label,
                    style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w500)),
                  const Spacer(),
                  Text('x${e.value.toStringAsFixed(2)}',
                    style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Sliders + saisie manuelle ★ v10.32 ────────────────────────────────────
  Widget _buildSecteurSliders() {
    if (_tousLesCriters.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Text(
          'Pas encore assez de données pour détecter des critères vivants.',
          style: TextStyle(color: Colors.white38, fontSize: 15),
          textAlign: TextAlign.center,
        ),
      );
    }

    final affiches = _critersAffiches;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── En-tête ──────────────────────────────────────────────────────
        Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Multiplicateurs',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text(
                  affiches.isEmpty
                      ? 'Appuie sur + pour commencer'
                      : '${affiches.length} critère(s) actif(s)',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
            const Spacer(),
            if (affiches.isNotEmpty)
              TextButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.refresh, size: 15, color: Colors.white38),
                label: const Text('Réinit.', style: TextStyle(color: Colors.white38, fontSize: 13)),
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),

        if (affiches.isEmpty)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                const Icon(Icons.tune, color: Colors.white24, size: 20),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Tous les critères sont à leur valeur neutre (x1.0).\n'
                    'Appuie sur "+" ou utilise un profil rapide.',
                    style: TextStyle(color: Colors.white38, fontSize: 14),
                  ),
                ),
              ],
            ),
          )
        else
          ...affiches.map((k) => _buildSliderWithInput(k)),

        // ── Bouton ajouter critère ────────────────────────────────────────
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: _cyan,
            side: BorderSide(color: _cyan.withValues(alpha: 0.4)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const Icon(Icons.add, size: 16),
          label: Text(
            'Ajouter un critère (${_tousLesCriters.length - _critersAffiches.length} disponibles)',
            style: const TextStyle(fontSize: 13),
          ),
          onPressed: _tousLesCriters.length > _critersAffiches.length
              ? _ajouterCritere
              : null,
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  // ── Slider + champ saisie manuelle ★ v10.32 ──────────────────────────────
  Widget _buildSliderWithInput(String k) {
    final val   = _mults[k] ?? 1.0;
    final label = kLabelsSimu[k] ?? k;
    final isModified = (val - 1.0).abs() > 0.01;
    final color = val > 1.05
        ? _vert
        : val < 0.95
            ? _rouge
            : Colors.white54;
    final ctrl  = _ctrlFor(k);
    final erreur = _textErrors[k];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isModified
                ? color.withValues(alpha: 0.25)
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Ligne label + bouton supprimer ─────────────────────────
            Row(
              children: [
                if (!isModified)
                  GestureDetector(
                    onTap: () => setState(() {
                      _mults.remove(k);
                      _critersActifs.remove(k);
                      _textCtrls[k]?.dispose();
                      _textCtrls.remove(k);
                      _textErrors.remove(k);
                    }),
                    child: const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.close, size: 15, color: Colors.white24),
                    ),
                  )
                else
                  const SizedBox(width: 21),
                Text(label, style: TextStyle(
                  color: isModified ? Colors.white : Colors.white54,
                  fontSize: 16,
                  fontWeight: isModified ? FontWeight.w600 : FontWeight.normal,
                )),
                const Spacer(),
                // Valeur actuelle affichée à droite
                Text('x${val.toStringAsFixed(2)}',
                  style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),

            // ── Slider ─────────────────────────────────────────────────
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor:   color,
                thumbColor:         color,
                inactiveTrackColor: Colors.white12,
                overlayColor:       color.withValues(alpha: 0.15),
                trackHeight:        4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                value:     val,
                min:       0.5,
                max:       2.0,
                divisions: 30,
                onChanged: (v) {
                  setState(() {
                    _mults[k]  = v;
                    ctrl.text  = v.toStringAsFixed(2);
                    _textErrors[k] = null;
                  });
                },
              ),
            ),

            // ── Saisie manuelle ★ v10.32 ───────────────────────────────
            Row(
              children: [
                const Text('Coefficient : ',
                  style: TextStyle(color: Colors.white54, fontSize: 14)),
                SizedBox(
                  width: 72,
                  height: 34,
                  child: TextField(
                    controller: ctrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      isDense:       true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: color.withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: color),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: _rouge),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onSubmitted: (_) => _appliquerSaisie(k),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: color,
                    side: BorderSide(color: color.withValues(alpha: 0.6)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _appliquerSaisie(k),
                  child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                if (erreur != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(erreur,
                      style: const TextStyle(color: _rouge, fontSize: 12)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Critères inactifs (repliable) ★ v10.32 ────────────────────────────────
  Widget _buildCriteresInactifs() {
    final inactifs = _critersInactifs.entries
        .where((e) => !_tousLesCriters.contains(e.key))
        .toList();

    // Ajoute aussi les critères vivants non proposés dans l'interface (trop rares)
    if (inactifs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _inactifsExpanded = !_inactifsExpanded),
          child: Row(
            children: [
              const Text('Critères inactifs',
                style: TextStyle(color: Colors.white38, fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              Text('(${inactifs.length})',
                style: const TextStyle(color: Colors.white24, fontSize: 13)),
              const Spacer(),
              Icon(_inactifsExpanded ? Icons.expand_less : Icons.expand_more,
                color: Colors.white24, size: 18),
            ],
          ),
        ),
        if (_inactifsExpanded) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              children: inactifs.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    const Icon(Icons.block_outlined, size: 14, color: Colors.white24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(e.value,
                        style: const TextStyle(color: Colors.white38, fontSize: 14)),
                    ),
                  ],
                ),
              )).toList(),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Ces critères ne sont pas proposés dans la simulation.',
            style: TextStyle(color: Colors.white24, fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ],
        const SizedBox(height: 14),
      ],
    );
  }

  // ── Bouton Lancer ─────────────────────────────────────────────────────────
  Widget _buildBoutonLancer() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: _gold,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: const Icon(Icons.play_arrow_rounded, size: 24),
        label: const Text('Lancer la simulation',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        onPressed: _enCours ? null : _lancer,
      ),
    ),
  );

  Widget _buildChargement() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 28),
    child: Center(child: Column(children: [
      CircularProgressIndicator(color: _gold),
      SizedBox(height: 14),
      Text('Calcul en cours…', style: TextStyle(color: Colors.white54, fontSize: 15)),
    ])),
  );

  // ── Pied export (métadonnées) ★ v10.32 ───────────────────────────────────
  Widget _buildPiedExport() {
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Text(
        'Export Simulation IA — ${_params.discipline} — '
        '${now.day.toString().padLeft(2,"0")}/${now.month.toString().padLeft(2,"0")}/${now.year} '
        '${now.hour.toString().padLeft(2,"0")}:${now.minute.toString().padLeft(2,"0")}',
        style: const TextStyle(color: Colors.white24, fontSize: 11),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ── Panneau assistant ─────────────────────────────────────────────────────
  Widget _buildAssistantSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      GestureDetector(
        onTap: () => setState(() => _assistantExpanded = !_assistantExpanded),
        child: Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _cyan.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _cyan.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, color: _cyan, size: 18),
              const SizedBox(width: 8),
              const Text('Assistant Simulation',
                style: TextStyle(color: _cyan, fontSize: 15, fontWeight: FontWeight.bold)),
              const Spacer(),
              Icon(_assistantExpanded ? Icons.expand_less : Icons.expand_more,
                color: _cyan, size: 20),
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
          onSauvegarder:  _enregistrerPiste,
          onExporter:     _exporter,
        ),
    ],
  );

  // ── Verdict ★ v10.32 (gros bandeau) ──────────────────────────────────────
  Widget _buildVerdictBanner(SimulationResultat res) {
    final v = res.verdict;
    Color color;
    String emoji;
    String phrase;

    if (v.startsWith('🟢')) {
      color  = _vert;
      emoji  = '🟢';
      phrase = 'ROI et Top3 progressent : piste à surveiller.';
    } else if (v.startsWith('🟡')) {
      color  = _gold;
      emoji  = '🟡';
      phrase = 'Amélioration trop faible pour décider.';
    } else if (v.startsWith('🟠')) {
      color  = const Color(0xFFFF9800);
      emoji  = '🟠';
      phrase = 'ROI monte mais stabilité baisse.';
    } else if (v.startsWith('🔴')) {
      color  = _rouge;
      emoji  = '🔴';
      phrase = 'Réglage défavorable.';
    } else {
      color  = Colors.white38;
      emoji  = '⚪';
      phrase = 'Pas de signal clair.';
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(v.replaceFirst(RegExp(r'^[🟢🟡🟠🔴⚪]\s*'), ''),
                  style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(phrase,
            style: TextStyle(color: color.withValues(alpha: 0.85), fontSize: 16)),
        ],
      ),
    );
  }

  // ── Tableau comparaison ───────────────────────────────────────────────────
  Widget _buildTableauComparaison(SimulationResultat res) {
    final a = res.avant;
    final s = res.apres;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.10),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 3, child: Text('Mesure',
                  style: TextStyle(color: _gold, fontSize: 14, fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('IA actuelle',
                  style: TextStyle(color: _gold, fontSize: 14, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text('Simulation',
                  style: TextStyle(color: _gold, fontSize: 14, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text('Δ',
                  style: TextStyle(color: _gold, fontSize: 14, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center)),
              ],
            ),
          ),
          _ligneCompa('Courses testées', '${a.nbCourses}', '${s.nbCourses}', null),
          _ligneCompa('Courses ROI', '${a.nbCoursesRoi}', '${s.nbCoursesRoi}', null),
          _ligneCompa('Top1 gagnant',
            '${a.top1.toStringAsFixed(1)}%', '${s.top1.toStringAsFixed(1)}%',
            s.top1 - a.top1, pct: true),
          _ligneCompa('Top3 touché',
            '${a.top3.toStringAsFixed(1)}%', '${s.top3.toStringAsFixed(1)}%',
            s.top3 - a.top3, pct: true),
          _ligneCompa('Top5 touché',
            '${a.top5.toStringAsFixed(1)}%', '${s.top5.toStringAsFixed(1)}%',
            s.top5 - a.top5, pct: true),
          _ligneCompa('ROI théorique',
            '${a.roi.toStringAsFixed(1)}%', '${s.roi.toStringAsFixed(1)}%',
            s.roi - a.roi, pct: true),
          _ligneCompa('Gain net (€)',
            '${a.gainNet.toStringAsFixed(2)}€', '${s.gainNet.toStringAsFixed(2)}€',
            s.gainNet - a.gainNet),
          _ligneCompa('Outsiders Top3',
            '${a.outsiders}', '${s.outsiders}',
            (s.outsiders - a.outsiders).toDouble()),
        ],
      ),
    );
  }

  Widget _ligneCompa(String label, String avant, String apres, double? delta, {bool pct = false}) {
    Color  deltaColor = Colors.white54;
    String deltaStr   = '—';
    if (delta != null) {
      deltaStr  = (delta >= 0 ? '+' : '') +
          (pct ? '${delta.toStringAsFixed(1)}%' : delta.toStringAsFixed(2));
      deltaColor = delta > 0.1 ? _vert : delta < -0.1 ? _rouge : Colors.white38;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 15))),
          Expanded(flex: 2, child: Text(avant,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            textAlign: TextAlign.center)),
          Expanded(flex: 2, child: Text(apres,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            textAlign: TextAlign.center)),
          Expanded(flex: 2, child: Text(deltaStr,
            style: TextStyle(color: deltaColor, fontSize: 15, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  // ── Blocs périodes ────────────────────────────────────────────────────────
  Widget _buildBlocPeriode(String titre, SimBloc avant, SimBloc apres) {
    if (avant.nbCourses == 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(titre,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text(avant.fiabiliteLabel,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _miniStat('Top3',
                '${avant.top3.toStringAsFixed(0)}%', '${apres.top3.toStringAsFixed(0)}%',
                apres.top3 - avant.top3),
              _miniStat('ROI',
                '${avant.roi.toStringAsFixed(1)}%', '${apres.roi.toStringAsFixed(1)}%',
                apres.roi - avant.roi),
              _miniStat('Top1',
                '${avant.top1.toStringAsFixed(0)}%', '${apres.top1.toStringAsFixed(0)}%',
                apres.top1 - avant.top1),
              _miniStat('n', '${avant.nbCourses}', '${apres.nbCourses}', null),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String av, String ap, double? d) {
    Color  c  = Colors.white38;
    String ds = '';
    if (d != null) {
      c  = d > 0.5 ? _vert : d < -0.5 ? _rouge : Colors.white38;
      ds = (d >= 0 ? '↑' : '↓');
    }
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
          Text('$av→$ap', style: const TextStyle(color: Colors.white70, fontSize: 13)),
          if (ds.isNotEmpty)
            Text(ds, style: TextStyle(color: c, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ── Bloc fiabilité ────────────────────────────────────────────────────────
  Widget _buildFiabiliteBloc(SimulationResultat res) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Fiabilité',
          style: TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        _fiabLigne('<30 courses',    '⚠️ Très faible — non exploitable'),
        _fiabLigne('30–50 courses',  '🟡 Indicatif — prudence requise'),
        _fiabLigne('50–150 courses', '🟠 Intéressant — piste à surveiller'),
        _fiabLigne('>150 courses',   '🟢 Exploitable — résultat fiable'),
        const SizedBox(height: 6),
        Text(
          'Courses ROI : ${res.apres.nbCoursesRoi} (dividende ou cote disponibles)',
          style: const TextStyle(color: Colors.white38, fontSize: 13),
        ),
      ],
    ),
  );

  Widget _fiabLigne(String seuil, String desc) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      SizedBox(width: 100, child: Text(seuil,
        style: const TextStyle(color: Colors.white38, fontSize: 12))),
      Expanded(child: Text(desc,
        style: const TextStyle(color: Colors.white54, fontSize: 12))),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════
//  _MesPistesScreen — Écran "Mes pistes" (push navigation) ★ v10.32
// ══════════════════════════════════════════════════════════════════════════

class _MesPistesScreen extends StatefulWidget {
  const _MesPistesScreen();
  @override
  State<_MesPistesScreen> createState() => _MesPistesScreenState();
}

class _MesPistesScreenState extends State<_MesPistesScreen> {
  final SimulationCandidateService _svc = SimulationCandidateService();
  List<SimulationCandidate> _pistes = [];
  bool _loading = true;

  static const Color _gold  = Color(0xFFFFD700);
  static const Color _bg    = Color(0xFF0D1B2A);
  static const Color _cyan  = Color(0xFF00E5FF);
  static const Color _vert  = Color(0xFF00E676);
  static const Color _rouge = Color(0xFFEF5350);

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final list = await _svc.listCandidates();
    if (mounted) setState(() { _pistes = list; _loading = false; });
  }

  Future<void> _supprimer(String id) async {
    await _svc.deleteCandidate(id);
    await _charger();
  }

  Future<void> _rejouer(SimulationCandidate p) async {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SimulationScreen(
          preloadDiscipline:    p.discipline,
          preloadCoefficients:  Map.of(p.coefficients),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: const Text('📋 Mes pistes',
          style: TextStyle(color: _gold, fontWeight: FontWeight.bold, fontSize: 20)),
        actions: [
          if (_pistes.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white38),
              tooltip: 'Tout effacer',
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF1A2744),
                    title: const Text('Effacer toutes les pistes ?',
                      style: TextStyle(color: Colors.white, fontSize: 17)),
                    content: const Text(
                      'Cette action est irréversible.',
                      style: TextStyle(color: Colors.white54, fontSize: 15)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Annuler',
                          style: TextStyle(color: Colors.white54))),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: _rouge),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Effacer tout',
                          style: TextStyle(color: Colors.white))),
                    ],
                  ),
                );
                if (ok == true) {
                  await _svc.clearCandidates();
                  await _charger();
                }
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : _pistes.isEmpty
              ? _buildVide()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 50),
                  itemCount: _pistes.length,
                  itemBuilder: (ctx, i) => _buildCarte(_pistes[i]),
                ),
    );
  }

  Widget _buildVide() => const Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.bookmarks_outlined, color: Colors.white24, size: 60),
        SizedBox(height: 16),
        Text('Aucune piste enregistrée.',
          style: TextStyle(color: Colors.white38, fontSize: 18)),
        SizedBox(height: 8),
        Text('Lancez une simulation et appuyez\nsur "Enregistrer comme piste".',
          style: TextStyle(color: Colors.white24, fontSize: 15),
          textAlign: TextAlign.center),
      ],
    ),
  );

  Widget _buildCarte(SimulationCandidate p) {
    final dRoi  = p.roiApres  - p.roiAvant;
    final dTop3 = p.top3Apres - p.top3Avant;
    final colRoi  = dRoi  > 0 ? _vert : dRoi  < 0 ? _rouge : Colors.white54;
    final colTop3 = dTop3 > 0 ? _vert : dTop3 < 0 ? _rouge : Colors.white54;
    final scoreColor = p.scoreConfiance >= 70
        ? _vert
        : p.scoreConfiance >= 45
            ? _gold
            : p.scoreConfiance >= 20
                ? Colors.orange
                : _rouge;
    final modifies = p.coefficientsModifies;

    return Card(
      color: const Color(0xFF1A2744),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── En-tête ────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(p.label,
                    style: const TextStyle(color: Colors.white,
                        fontSize: 17, fontWeight: FontWeight.bold)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: scoreColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scoreColor.withValues(alpha: 0.4)),
                  ),
                  child: Text('${p.scoreConfiance}/100',
                    style: TextStyle(color: scoreColor, fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('${p.disciplineLabel} · ${p.dateLabel}',
              style: const TextStyle(color: Colors.white38, fontSize: 13)),
            const SizedBox(height: 10),

            // ── Coefficients modifiés ──────────────────────────────────
            if (modifies.isNotEmpty) ...[
              Wrap(
                spacing: 7, runSpacing: 5,
                children: modifies.entries.map((e) {
                  final label = kLabelsSimu[e.key] ?? e.key;
                  final col   = e.value > 1.0 ? _vert : _rouge;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: col.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: col.withValues(alpha: 0.4)),
                    ),
                    child: Text('$label x${e.value.toStringAsFixed(2)}',
                      style: TextStyle(color: col, fontSize: 13)),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
            ],

            // ── Métriques avant/après ──────────────────────────────────
            Row(
              children: [
                _metriqueCard('Top3',
                  '${p.top3Avant.toStringAsFixed(1)}%',
                  '${p.top3Apres.toStringAsFixed(1)}%',
                  dTop3, colTop3),
                const SizedBox(width: 8),
                _metriqueCard('ROI',
                  '${p.roiAvant.toStringAsFixed(1)}%',
                  '${p.roiApres.toStringAsFixed(1)}%',
                  dRoi, colRoi),
              ],
            ),
            const SizedBox(height: 8),

            // ── Verdict ────────────────────────────────────────────────
            Text(p.verdict,
              style: const TextStyle(color: Colors.white54, fontSize: 14,
                  fontStyle: FontStyle.italic)),
            const SizedBox(height: 12),

            // ── Boutons ────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _cyan,
                      side: BorderSide(color: _cyan.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.replay, size: 16),
                    label: const Text('Rejouer', style: TextStyle(fontSize: 14)),
                    onPressed: () => _rejouer(p),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _rouge,
                    side: BorderSide(color: _rouge.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Supprimer', style: TextStyle(fontSize: 14)),
                  onPressed: () => _supprimer(p.id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metriqueCard(String titre, String av, String ap, double delta, Color col) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: col.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: col.withValues(alpha: 0.20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titre, style: const TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 3),
            Row(
              children: [
                Text('$av → $ap',
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
                const Spacer(),
                Text('${delta >= 0 ? "+" : ""}${delta.toStringAsFixed(1)}%',
                  style: TextStyle(color: col, fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
