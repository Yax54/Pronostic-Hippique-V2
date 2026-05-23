// ignore_for_file: unused_element
import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../services/ia_memory_service.dart';
import '../../services/ia_memory_models.dart';
import '../../services/pronostic_resultats_repository.dart' show PronosticResultatsRepository;

// ─── Couleurs partagées (palette IaPerformanceScreen) ─────────────────────────
const Color _kDark   = Color(0xFF0D1B2A);
const Color _kCard   = Color(0xFF111F30);
const Color _kGreen  = Color(0xFF4CAF7D);
const Color _kDGreen = Color(0xFF2E7D52);
const Color _kGold   = Color(0xFFFFD700);
const Color _kPurple = Color(0xFF7C4DFF);

// ══════════════════════════════════════════════════════════════════════════════
//  _BulletPoint, _CircleGaugePainter, _DialogDetailTypePari
//  Extraits de IaPerformanceScreen.
// ══════════════════════════════════════════════════════════════════════════════

// ── Bullet point ─────────────────────────────────────────────────────────────

class _BulletPoint extends StatelessWidget {
  final String text;
  const _BulletPoint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        const Text('• ', style: TextStyle(color: Color(0xFF4CAF7D), fontSize: 16)),
        Flexible(child: Text(text, style: const TextStyle(color: Colors.white60, fontSize: 16))),
      ]),
    );
  }
}

// ── Peintre de jauge circulaire ───────────────────────────────────────────────

class _CircleGaugePainter extends CustomPainter {
  final double progress;
  final Color color;

  _CircleGaugePainter(this.progress, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 3;

    // Fond
    final bgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(center, radius, bgPaint);

    // Arc de progression
    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_CircleGaugePainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════
//  _DialogDetailTypePari — Dialogue StatefulWidget avec filtre période
//  Affiche la liste complète des conseils IA pour un type de pari donné,
//  filtrée par mois, période personnalisée, ou depuis l'installation.
// ═══════════════════════════════════════════════════════════════════════════

class _DialogDetailTypePari extends StatefulWidget {
  final StatsPrecisionParType stats;
  final String? filtreInitial;
  final DateTime? filtreDebutInitial;
  final DateTime? filtreFinInitial;
  final Widget Function(IaPronostic, String) buildCarte;
  final Widget Function(String, Color) chipStat;
  final Color green;

  const _DialogDetailTypePari({
    required this.stats,
    required this.filtreInitial,
    required this.filtreDebutInitial,
    required this.filtreFinInitial,
    required this.buildCarte,
    required this.chipStat,
    required this.green,
  });

  @override
  State<_DialogDetailTypePari> createState() => _DialogDetailTypePariState();
}

class _DialogDetailTypePariState extends State<_DialogDetailTypePari> {
  // Filtre local au dialogue — null='60j' | 'all' | 'YYYY-MM-DD' | 'custom'
  String? _filtre;
  DateTime? _debut;
  DateTime? _fin;

  // Tous les pronostics du type en mémoire (non filtrés)
  late final List<IaPronostic> _tousPronostics;

  @override
  void initState() {
    super.initState();
    _filtre = widget.filtreInitial;
    _debut  = widget.filtreDebutInitial;
    _fin    = widget.filtreFinInitial;
    _tousPronostics = IaMemoryService.instance.pronostics
        .where((pr) => pr.typePariConseille == widget.stats.typePari)
        .toList()
      ..sort((a, b) => b.datePronostic.compareTo(a.datePronostic));
  }

  // ── Filtrage des pronostics selon la période active ─────────────────────
  // SOURCE UNIQUE : tout vient des IaPronostic en RAM — plus de double source
  // Valeurs de _filtre : null='60j' | 'all' | '7j' | 'today' | 'custom'
  List<IaPronostic> get _pronosticsFiltres {
    if (_filtre == null) {
      // 60j glissants
      final limite = DateTime.now().subtract(const Duration(days: 60));
      return _tousPronostics
          .where((pr) => pr.datePronostic.isAfter(limite))
          .toList();
    }
    if (_filtre == 'all') return _tousPronostics;
    if (_filtre == '7j') {
      final limite = DateTime.now().subtract(const Duration(days: 7));
      return _tousPronostics
          .where((pr) => pr.datePronostic.isAfter(limite))
          .toList();
    }
    if (_filtre == 'today') {
      final now = DateTime.now();
      final deb = DateTime(now.year, now.month, now.day);
      final fin = DateTime(now.year, now.month, now.day, 23, 59, 59);
      return _tousPronostics
          .where((pr) => !pr.datePronostic.isBefore(deb) && !pr.datePronostic.isAfter(fin))
          .toList();
    }
    if (_filtre == 'custom' && _debut != null && _fin != null) {
      // Inclusif : du début 00:00 à la fin 23:59:59
      final deb = DateTime(_debut!.year, _debut!.month, _debut!.day);
      final fin = DateTime(_fin!.year,   _fin!.month,   _fin!.day, 23, 59, 59);
      return _tousPronostics
          .where((pr) => !pr.datePronostic.isBefore(deb) && !pr.datePronostic.isAfter(fin))
          .toList();
    }
    return _tousPronostics;
  }

  // ── Libellé de la période active ─────────────────────────────────────────
  String get _libellePeriode {
    if (_filtre == null) return '60j glissants';
    if (_filtre == 'all') return 'Depuis installation';
    if (_filtre == '7j') return '7 derniers jours';
    if (_filtre == 'today') {
      final now = DateTime.now();
      const mois = ['','Jan','Fév','Mar','Avr','Mai','Juin','Juil','Aoû','Sep','Oct','Nov','Déc'];
      return "Aujourd'hui ${now.day} ${mois[now.month]}";
    }
    if (_filtre == 'custom' && _debut != null && _fin != null) {
      final d = '${_debut!.day.toString().padLeft(2,'0')}/${_debut!.month.toString().padLeft(2,'0')}';
      final f = '${_fin!.day.toString().padLeft(2,'0')}/${_fin!.month.toString().padLeft(2,'0')}';
      return '$d → $f';
    }
    return '60j';
  }

  // ── Sélecteur de période personnalisée ───────────────────────────────────
  Future<void> _choisirPeriode() async {
    final now = DateTime.now();
    final debut = await showDatePicker(
      context: context,
      initialDate: _debut ?? now,               // ★ date initiale = aujourd'hui
      firstDate: DateTime(2024),
      lastDate: now,
      helpText: 'DATE DE DÉBUT',
      confirmText: 'VALIDER',
      cancelText: 'ANNULER',
      fieldLabelText: 'Entrez la date',
      fieldHintText: 'jj/mm/aaaa',
      errorFormatText: 'Format invalide',
      errorInvalidText: 'Date invalide',
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: Color(0xFF4CAF7D)),
        ),
        child: child!,
      ),
    );
    if (debut == null || !mounted) return;
    final fin = await showDatePicker(
      context: context,
      initialDate: _fin ?? now,                 // ★ date initiale = aujourd'hui
      firstDate: debut,
      lastDate: now,
      helpText: 'DATE DE FIN',
      confirmText: 'VALIDER',
      cancelText: 'ANNULER',
      fieldLabelText: 'Entrez la date',
      fieldHintText: 'jj/mm/aaaa',
      errorFormatText: 'Format invalide',
      errorInvalidText: 'Date invalide',
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: Color(0xFF4CAF7D)),
        ),
        child: child!,
      ),
    );
    if (fin == null || !mounted) return;
    setState(() { _filtre = 'custom'; _debut = debut; _fin = fin; });
  }

  // ── Bouton filtre — vert si sélectionné, jaune si non sélectionné ─────────
  // ★ v10.36 : fontSize 11→14, padding augmenté
  Widget _bouton(String label, String? valeur, {IconData? icone}) {
    final actif = _filtre == valeur;
    const vertActif   = Color(0xFF4CAF7D);
    const jauneInactif = Color(0xFFFFD700);
    return GestureDetector(
      onTap: () => setState(() => _filtre = valeur),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: actif
              ? vertActif.withValues(alpha: 0.18)
              : jauneInactif.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: actif ? vertActif : jauneInactif.withValues(alpha: 0.55),
            width: actif ? 1.8 : 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icone != null) ...[
              Icon(icone, size: 14,
                  color: actif ? vertActif : jauneInactif.withValues(alpha: 0.8)),
              const SizedBox(width: 5),
            ],
            Text(label,
                style: TextStyle(
                  color: actif ? vertActif : jauneInactif.withValues(alpha: 0.85),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                )),
          ],
        ),
      ),
    );
  }

  // ── Barre de filtres : 5 boutons sur 2 lignes (Wrap) ★ v10.36
  Widget _buildFiltreBarre() {
    final now     = DateTime.now();
    const moisC   = ['','Jan','Fév','Mar','Avr','Mai','Juin','Juil','Aoû','Sep','Oct','Nov','Déc'];
    final libAuj  = 'Auj. ${now.day} ${moisC[now.month]}';
    final libPeriode = (_filtre == 'custom' && _debut != null && _fin != null)
        ? '${_debut!.day.toString().padLeft(2,'0')}/${_debut!.month.toString().padLeft(2,'0')}'
          ' → ${_fin!.day.toString().padLeft(2,'0')}/${_fin!.month.toString().padLeft(2,'0')}'
        : 'Période';

    // ★ v10.36 : Wrap = 2 lignes auto, plus grand, plus lisible
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _bouton('Tout',   'all',   icone: Icons.all_inclusive),
        _bouton('60j IA', null,    icone: Icons.psychology),
        _bouton('7 jrs',  '7j',    icone: Icons.date_range),
        _bouton(libAuj,   'today', icone: Icons.today),
        // Bouton Période — ouvre le sélecteur de dates
        GestureDetector(
          onTap: _choisirPeriode,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: _filtre == 'custom'
                  ? const Color(0xFF9C27B0).withValues(alpha: 0.18)
                  : const Color(0xFFFFD700).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _filtre == 'custom'
                    ? const Color(0xFF9C27B0)
                    : const Color(0xFFFFD700).withValues(alpha: 0.55),
                width: _filtre == 'custom' ? 1.8 : 1.2,
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.calendar_month,
                  size: 14,
                  color: _filtre == 'custom'
                      ? const Color(0xFF9C27B0)
                      : const Color(0xFFFFD700).withValues(alpha: 0.8)),
              const SizedBox(width: 5),
              Text(libPeriode,
                  style: TextStyle(
                    color: _filtre == 'custom'
                        ? const Color(0xFF9C27B0)
                        : const Color(0xFFFFD700).withValues(alpha: 0.85),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.2,
                  )),
            ]),
          ),
        ),
      ],
    );
  }

  // ── Calcul ordre/désordre depuis les IaPronostic filtrés ─────────────────
  // SOURCE UNIQUE : on compte ordre/désordre directement dans les pronostics
  // (plus de _statsFiltrees qui lisait historiqueComplet — source différente)
  Map<String, int> _compterOrdreDesordre(List<IaPronostic> gagnants) {
    int ord = 0, des = 0;
    for (final pr in gagnants) {
      final type = widget.stats.typePari;
      if (type != 'Tiercé' && type != 'Quarté+' && type != 'Quinté+') continue;
      final arrivee = pr.arriveeReelle;
      if (arrivee == null || arrivee.isEmpty) continue;
      final topIA = pr.topNIA.map((e) => int.tryParse(e)).whereType<int>().toList();
      bool? estOrdre;
      switch (type) {
        case 'Tiercé':
          if (topIA.length >= 3 && arrivee.length >= 3) {
            if (topIA[0]==arrivee[0] && topIA[1]==arrivee[1] && topIA[2]==arrivee[2]) {
              estOrdre = true;
            } else if (topIA.take(3).toSet().intersection(arrivee.take(3).toSet()).length >= 3) {
              estOrdre = false;
            }
          }
          break;
        case 'Quarté+':
          if (topIA.length >= 4 && arrivee.length >= 4) {
            if (topIA[0]==arrivee[0] && topIA[1]==arrivee[1] &&
                topIA[2]==arrivee[2] && topIA[3]==arrivee[3]) {
              estOrdre = true;
            } else if (topIA.take(4).toSet().intersection(arrivee.take(4).toSet()).length >= 3) {
              estOrdre = false;
            }
          }
          break;
        case 'Quinté+':
          if (topIA.length >= 5 && arrivee.length >= 5) {
            if (topIA[0]==arrivee[0] && topIA[1]==arrivee[1] && topIA[2]==arrivee[2] &&
                topIA[3]==arrivee[3] && topIA[4]==arrivee[4]) {
              estOrdre = true;
            } else if (topIA.take(5).toSet().intersection(arrivee.take(5).toSet()).length >= 3) {
              estOrdre = false;
            }
          }
          break;
      }
      if (estOrdre == true)  ord++;
      if (estOrdre == false) des++;
    }
    return {'ordre': ord, 'desordre': des};
  }

  // ★ v10.80 : Section "Suite IA classique" — réussites dérivées
  // Affichée uniquement dans ce dialog de détail, jamais dans les listes compactes.
  // Source : PronosticResultatsRepository filtré par typePari + source='suiteIAClassique'.
  Widget _buildSectionSuiteIAClassique() {
    final repo = PronosticResultatsRepository.instance;
    final items = repo.tous.where((r) =>
        r.typePari == widget.stats.typePari &&
        r.source == 'suiteIAClassique' &&
        r.gagnant).toList()
      ..sort((a, b) => b.dateCourse.compareTo(a.dateCourse));

    if (items.isEmpty) return const SizedBox.shrink();

    const mois = ['','Jan','Fév','Mar','Avr','Mai','Juin',
                   'Juil','Aoû','Sep','Oct','Nov','Déc'];

    return Container(
      width: double.maxFinite,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A3A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // En-tête
          Row(children: [
            const Text('🔎', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            const Text('Suite IA classique',
                style: TextStyle(color: Color(0xFF7C4DFF),
                    fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
              ),
              child: const Text('Hors apprentissage',
                  style: TextStyle(color: Colors.orange, fontSize: 10)),
            ),
          ]),
          const SizedBox(height: 6),
          // Liste des réussites dérivées
          ...items.take(5).map((r) {
            final d = r.dateCourse;
            final dateStr = '${d.day} ${mois[d.month]} ${d.year}';
            final ordreLabel = r.ordreExact ? '🎯 Ordre' : '🔀 Désordre';
            final ordreColor = r.ordreExact
                ? const Color(0xFF4CAF7D)
                : const Color(0xFFFFB74D);
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                const Text('✅ ', style: TextStyle(fontSize: 11)),
                Expanded(child: Text(dateStr,
                    style: const TextStyle(color: Colors.white60, fontSize: 11))),
                Text(ordreLabel,
                    style: TextStyle(color: ordreColor,
                        fontSize: 11, fontWeight: FontWeight.bold)),
              ]),
            );
          }),
          if (items.length > 5)
            Text('… et ${items.length - 5} autre(s)',
                style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ── Tout calculé depuis _pronosticsFiltres — UNE SEULE SOURCE ────────
    final filtres   = _pronosticsFiltres;
    final resolus   = filtres.where((pr) => pr.resultatsReels).toList();
    final enAttente = filtres.where((pr) => !pr.resultatsReels).toList();
    final gagnants  = resolus
        .where((pr) => IaMemoryService.instance.estBonConseil(pr, widget.stats.typePari))
        .toList();
    final perdants  = resolus
        .where((pr) => !IaMemoryService.instance.estBonConseil(pr, widget.stats.typePari))
        .toList();

    // Score depuis les pronostics filtrés (cohérent avec les chips)
    final nbTotal = resolus.length;
    final nbBons  = gagnants.length;
    final taux    = nbTotal > 0 ? (nbBons / nbTotal * 100).toStringAsFixed(0) : '—';

    // Ordre/désordre calculé depuis les gagnants filtrés
    final od       = _compterOrdreDesordre(gagnants);
    final nbOrdre  = od['ordre']    ?? 0;
    final nbDesordre = od['desordre'] ?? 0;

    return DefaultTabController(
      length: 3,
      child: AlertDialog(
        backgroundColor: const Color(0xFF0D1B2A),
        contentPadding: EdgeInsets.zero,
        titlePadding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── En-tête type + score ─────────────────────────────────
            Row(children: [
              Text(widget.stats.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.stats.typePari,
                      // ★ v10.36 : 15→17
                      style: const TextStyle(color: Colors.white, fontSize: 17,
                          fontWeight: FontWeight.bold)),
                  Text('Conseils IA — $_libellePeriode',
                      // ★ v10.36 : 10→13
                      style: const TextStyle(color: Colors.white38, fontSize: 13)),
                ],
              )),
              // ★ v10.57 : libéllé explicité pour éviter la confusion "8/14 = 814"
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('$nbBons gagnants / $nbTotal',
                    style: TextStyle(color: widget.green, fontSize: 16,
                        fontWeight: FontWeight.bold)),
                Text('$taux% de réussite',
                    style: const TextStyle(color: Colors.white38, fontSize: 13)),
              ]),
            ]),
            const SizedBox(height: 10),
            // ── Filtre période ───────────────────────────────────────
            _buildFiltreBarre(),
            const SizedBox(height: 10),
            // ── Chips récap ──────────────────────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                widget.chipStat('✅ ${gagnants.length}', widget.green),
                const SizedBox(width: 5),
                widget.chipStat('❌ ${perdants.length}', const Color(0xFFEF5350)),
                if (enAttente.isNotEmpty) ...[
                  const SizedBox(width: 5),
                  widget.chipStat('⏳ ${enAttente.length}', const Color(0xFFFFB74D)),
                ],
                if (nbOrdre > 0 || nbDesordre > 0) ...[
                  const SizedBox(width: 5),
                  widget.chipStat('🎯 Ordre $nbOrdre', const Color(0xFF66BB6A)),
                  const SizedBox(width: 4),
                  widget.chipStat('🔀 Désordre $nbDesordre', const Color(0xFFFFB74D)),
                ],
              ]),
            ),
            const SizedBox(height: 8),
            // ── Onglets ──────────────────────────────────────────────
            TabBar(
              labelColor: widget.green,
              unselectedLabelColor: Colors.white38,
              indicatorColor: widget.green,
              indicatorSize: TabBarIndicatorSize.tab,
              // ★ v10.36 : 11→13
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              tabs: [
                Tab(text: '✅ Gagnants (${gagnants.length})'),
                Tab(text: '❌ Perdants (${perdants.length})'),
                Tab(text: '⏳ Attente (${enAttente.length})'),
              ],
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          // ★ v10.36 : 400→450 pour compenser les filtres sur 2 lignes
          height: 450,
          child: _tousPronostics.isEmpty
              ? Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('🤖', style: TextStyle(fontSize: 36)),
                    const SizedBox(height: 10),
                    Text('Aucun conseil IA ${widget.stats.typePari} enregistré.',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 6),
                    const Text(
                      'Les conseils IA sont générés automatiquement\nau chargement du programme du matin.\n\nLancez ensuite l\'analyse journée pour\nobtenir les résultats.',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ))
              : filtres.isEmpty
                  ? Center(child: Text(
                      'Aucun conseil IA pour $_libellePeriode.\nChangez la période ci-dessus.',
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                      textAlign: TextAlign.center,
                    ))
                  : TabBarView(children: [
                      // ── Onglet 1 : GAGNANTS ─────────────────────
                      _buildListe(gagnants,
                          'Aucun conseil gagnant sur cette période.\nLes succès apparaîtront ici.'),
                      // ── Onglet 2 : PERDANTS ─────────────────────
                      _buildListe(perdants, 'Aucun perdant enregistré.'),
                      // ── Onglet 3 : EN ATTENTE ────────────────────
                      _buildListe(enAttente, 'Aucun conseil en attente.'),
                    ]),
        ),
        actions: [
          // ★ v10.80 : Section Suite IA classique — réussites dérivées hors apprentissage
          _buildSectionSuiteIAClassique(),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer', style: TextStyle(color: Color(0xFF4CAF7D))),
          ),
        ],
      ),
    );
  }

  Widget _buildListe(List<IaPronostic> liste, String emptyMsg) {
    if (liste.isEmpty) {
      return Center(
        child: Text(emptyMsg,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
            textAlign: TextAlign.center),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      itemCount: liste.length,
      itemBuilder: (_, i) => widget.buildCarte(liste[i], widget.stats.typePari),
    );
  }
}

