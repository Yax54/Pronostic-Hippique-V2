// ═══════════════════════════════════════════════════════════════════════════
//  IA JOURNAL SCREEN — v10.65
//  ★ v9.91  : structure hiérarchique 3 niveaux
//  ★ v10.64 : IA Narrative Engine V1 — carte narrative dynamique en tête de journal
//  ★ v10.65 : IA Narrative Engine V2 — mémoire anti-répétition, tendances 7j, discipline forte
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ia_memory_service.dart';
import '../services/ia_memory_models.dart';
import '../services/ia_personality_service.dart';
import '../models/ia_narrative_models.dart';      // ★ v10.64
import '../services/ia_narrative_engine.dart';    // ★ v10.65
import '../widgets/ia_narrative_card.dart';        // ★ v10.64

class IaJournalScreen extends StatefulWidget {
  const IaJournalScreen({super.key});
  @override
  State<IaJournalScreen> createState() => _IaJournalScreenState();
}

class _IaJournalScreenState extends State<IaJournalScreen> {
  // Clés de dépliage : 'mois-YYYY-MM' | 'sem-YYYY-MM-DD'
  final Set<String> _expanded = {};

  // ★ v10.65 — Cache narratif async (refraisé à chaque ouverture du journal)
  String _pseudoUtilisateur = '';
  String? _messageNarratif;          // null = chargement en cours
  bool   _narratifCharge = false;

  @override
  void initState() {
    super.initState();
    _initialiserNarratif();
  }

  Future<void> _initialiserNarratif() async {
    // 1. Charger le pseudo
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final pseudo = prefs.getString('profil_nom') ?? '';

    // 2. Construire le contexte (synchrone) sur les rapports en mémoire
    final rapports = IaMemoryService.instance.rapports;
    final ctx = _buildNarrativeContext(rapports, pseudo);

    // 3. Générer le message V2 (async, anti-répétition)
    final msg = await IaNarrativeEngine.genererResumeV2(ctx);

    if (!mounted) return;
    setState(() {
      _pseudoUtilisateur = pseudo;
      _messageNarratif   = msg;
      _narratifCharge    = true;
    });
  }

  // ★ v10.65 — Construit le contexte narratif depuis les données existantes
  IaNarrativeContext _buildNarrativeContext(
    List<RapportJournalier> rapports,
    String pseudo,
  ) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final hier  = today.subtract(const Duration(days: 1));

    // ── Rapport d'aujourd'hui ────────────────────────────────────────────
    RapportJournalier? rapportJour;
    try {
      rapportJour = rapports.firstWhere((r) {
        final d = DateTime(r.date.year, r.date.month, r.date.day);
        return d == today;
      });
    } catch (_) {
      rapportJour = null;
    }

    // ── Rapport d'hier ───────────────────────────────────────────────────
    RapportJournalier? rapportHier;
    try {
      rapportHier = rapports.firstWhere((r) {
        final d = DateTime(r.date.year, r.date.month, r.date.day);
        return d == hier;
      });
    } catch (_) {
      rapportHier = null;
    }

    // ── ★ v10.65 : Tendances 7 jours ────────────────────────────────────
    // Rapports des 7 derniers jours (J-1 à J-7)
    // Rapports des 7 jours précédents (J-8 à J-14)
    double taux7j = 0.0;
    double taux7jPrecedent = 0.0;

    try {
      final rapports7j = rapports.where((r) {
        final d = DateTime(r.date.year, r.date.month, r.date.day);
        final diff = today.difference(d).inDays;
        return diff >= 1 && diff <= 7 && r.nbAvecResultat > 0;
      }).toList();

      final rapportsPrecedents = rapports.where((r) {
        final d = DateTime(r.date.year, r.date.month, r.date.day);
        final diff = today.difference(d).inDays;
        return diff >= 8 && diff <= 14 && r.nbAvecResultat > 0;
      }).toList();

      if (rapports7j.isNotEmpty) {
        taux7j = rapports7j.fold(0.0, (s, r) => s + r.tauxGagnant) /
            rapports7j.length / 100;
      }
      if (rapportsPrecedents.isNotEmpty) {
        taux7jPrecedent = rapportsPrecedents.fold(
                0.0, (s, r) => s + r.tauxGagnant) /
            rapportsPrecedents.length / 100;
      }
    } catch (_) {}

    // ── ★ v10.65 : Meilleure discipline ─────────────────────────────────
    String meilleureDiscipline = '';
    try {
      final rapports14j = rapports.where((r) {
        final d = DateTime(r.date.year, r.date.month, r.date.day);
        return today.difference(d).inDays <= 14 && r.parDiscipline.isNotEmpty;
      }).toList();

      if (rapports14j.isNotEmpty) {
        // Agréger taux par discipline
        final tauxParDisc = <String, List<double>>{};
        for (final r in rapports14j) {
          for (final disc in r.parDiscipline) {
            if (disc.discipline.isNotEmpty && disc.nbCourses > 0) {
              tauxParDisc.putIfAbsent(disc.discipline, () => []);
              tauxParDisc[disc.discipline]!.add(disc.tauxGagnant);
            }
          }
        }
        if (tauxParDisc.isNotEmpty) {
          meilleureDiscipline = tauxParDisc.entries
              .reduce((a, b) {
                final moyA = a.value.reduce((x, y) => x + y) / a.value.length;
                final moyB = b.value.reduce((x, y) => x + y) / b.value.length;
                return moyA > moyB ? a : b;
              })
              .key;
        }
      }
    } catch (_) {}

    // ── ★ v10.65 : Widget premium le plus stable ─────────────────────────
    final svc = IaMemoryService.instance;
    String widgetStable = '';
    try {
      const sources = [
        'conseilJour', 'meilleurPari', 'topEquilibre', 'plusSur', 'plusRentable'
      ];
      int maxJours = 0;
      for (final src in sources) {
        final s = svc.calculerStreakPremium(
          sourceWidget: src, dateReference: today);
        if (s.jours > maxJours) {
          maxJours   = s.jours;
          widgetStable = s.jours >= 2 ? src : '';
        }
      }
    } catch (_) {}

    // ── Streaks premium (lecture seule) ──────────────────────────────────
    final streakConseil   = svc.calculerStreakPremium(sourceWidget: 'conseilJour',    dateReference: today);
    final streakMeilleur  = svc.calculerStreakPremium(sourceWidget: 'meilleurPari',   dateReference: today);
    final streakEquilibre = svc.calculerStreakPremium(sourceWidget: 'topEquilibre',   dateReference: today);
    final streakSur       = svc.calculerStreakPremium(sourceWidget: 'plusSur',        dateReference: today);
    final streakRentable  = svc.calculerStreakPremium(sourceWidget: 'plusRentable',   dateReference: today);

    return IaNarrativeContext(
      pseudoUtilisateur:          pseudo,
      nbCoursesJour:              rapportJour?.nbAvecResultat ?? 0,
      nbBonnesCoursesJour:        rapportJour != null
          ? ((rapportJour.tauxGagnant / 100) * rapportJour.nbAvecResultat).round()
          : 0,
      nbCoursesHier:              rapportHier?.nbAvecResultat ?? 0,
      nbBonnesCoursesHier:        rapportHier != null
          ? ((rapportHier.tauxGagnant / 100) * rapportHier.nbAvecResultat).round()
          : 0,
      roiJour:                    0,
      roiHier:                    0,
      streakPlusSur:              streakSur.jours,
      streakMeilleurPari:         streakMeilleur.jours,
      streakTopEquilibre:         streakEquilibre.jours,
      streakPlusRentable:         streakRentable.jours,
      streakConseilJour:          streakConseil.jours,
      taux7j:                     taux7j,
      taux7jPrecedent:            taux7jPrecedent,
      meilleureDiscipline:        meilleureDiscipline,
      widgetPremiumLePlusStable:  widgetStable,
    );
  }

  static const _dark   = Color(0xFF0D1B2A);
  static const _card   = Color(0xFF111F30);
  static const _gold   = Color(0xFFFFD700);
  static const _green  = Color(0xFF4CAF7D);
  static const _blue   = Color(0xFF42A5F5);
  static const _orange = Color(0xFFFFB74D);
  static const _red    = Color(0xFFEF5350);

  @override
  Widget build(BuildContext context) {
    final ia      = IaPersonalityService.instance;
    final rapports = IaMemoryService.instance.rapports; // plus récent en premier
    final bilansSemaine = IaMemoryService.instance.bilansSemaine;
    final bilansMois    = IaMemoryService.instance.bilansMois;
    final hebdo = IaMemoryService.instance.calculerRapportHebdo();

    // Semaine en cours : rapports qui ne sont dans aucun BilanSemaine archivé
    final archivesLundis = bilansSemaine.map((bs) => bs.lundi).toSet();
    final rapportsSemaineCourante = rapports.where((r) {
      final rLundi = DateTime(r.date.year, r.date.month, r.date.day)
          .subtract(Duration(days: r.date.weekday - 1));
      return !archivesLundis.contains(rLundi);
    }).toList();

    final isEmpty = rapports.isEmpty && bilansSemaine.isEmpty && bilansMois.isEmpty;

    return Scaffold(
      backgroundColor: _dark,
      appBar: AppBar(
        backgroundColor: _dark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          Text(ia.avatarEmoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Journal de ${ia.prenom}',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            Text('${rapports.length} entrée${rapports.length > 1 ? "s" : ""}',
                style: const TextStyle(color: Colors.white38, fontSize: 14)),
          ]),
        ]),
      ),
      body: isEmpty
          ? _buildVide(ia)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              children: [
                // ── ★ v10.65 : Carte narrative IA (V2 async, anti-répétition) ──
                IaNarrativeCard(
                  // Si le message narratif est prêt : l'afficher.
                  // En cours de chargement : phrase courte sobre (jamais vide).
                  message: _narratifCharge && _messageNarratif != null
                      ? _messageNarratif!
                      : '',
                ),

                // ── Bilan hebdo (semaine en cours) ───────────────────────
                if (hebdo != null) _buildBilanHebdo(hebdo, ia),

                // ── Rapports semaine en cours (toujours visibles) ─────────
                ...rapportsSemaineCourante.map((r) =>
                    _buildEntree(r, ia, r == rapportsSemaineCourante.first)),

                // ── Bilans de semaines archivées (pas encore dans un mois) ─
                ...bilansSemaine
                    .where((bs) => !bilansMois.any((bm) =>
                        bm.semaines.any((s) => s.lundi == bs.lundi)))
                    .map((bs) => _buildBilanSemaine(bs, ia)),

                // ── Bilans de mois (les plus récents en premier) ───────────
                ...bilansMois.reversed.map((bm) => _buildBilanMois(bm, ia)),
              ],
            ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  BILAN MOIS — replié par défaut, cliquable
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildBilanMois(BilanMois bm, IaPersonalityService ia) {
    final key    = 'mois-${bm.annee}-${bm.mois}';
    final isOpen = _expanded.contains(key);
    final couleur = _couleurTaux(bm.tauxGagnant);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: couleur.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(children: [
        // ★ v9.93 Bug 2 fix : toute la ligne header est cliquable
        InkWell(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16), topRight: Radius.circular(16)),
          onTap: () => setState(() =>
              isOpen ? _expanded.remove(key) : _expanded.add(key)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: couleur.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('📅', style: TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(bm.libelle,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                Text('${bm.semaines.length} semaine${bm.semaines.length > 1 ? "s" : ""} · ${bm.totalCourses} courses',
                    style: const TextStyle(color: Colors.white54, fontSize: 14)),
              ])),
              _badgeTaux(bm.tauxGagnant, couleur),
              const SizedBox(width: 8),
              Icon(isOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: Colors.white38),
            ]),
          ),
        ),
        // Stats rapides
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: Row(children: [
            _chipStat('🥇', '${bm.tauxGagnant.toStringAsFixed(0)}%', couleur),
            const SizedBox(width: 8),
            _chipStat('🎯', '${bm.tauxTop3.toStringAsFixed(0)}% top3', Colors.white38),
            if (bm.meilleureDisc.isNotEmpty) ...[ 
              const SizedBox(width: 8),
              _chipStat('🏆', bm.meilleureDisc.split(' ').first, _gold),
            ],
          ]),
        ),
        // Contenu déplié : les semaines
        if (isOpen) ...[ 
          const Divider(height: 1, color: Colors.white12),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: bm.semaines.reversed
                .map((bs) => _buildBilanSemaine(bs, ia, inMois: true))
                .toList()),
          ),
        ],
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  BILAN SEMAINE — replié par défaut, cliquable
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildBilanSemaine(BilanSemaine bs, IaPersonalityService ia,
      {bool inMois = false}) {
    final key    = 'sem-${bs.lundi.year}-${bs.lundi.month}-${bs.lundi.day}';
    final isOpen = _expanded.contains(key);
    final couleur = _couleurTaux(bs.tauxGagnant);

    return Container(
      margin: EdgeInsets.only(bottom: inMois ? 8 : 16),
      decoration: BoxDecoration(
        color: inMois ? _dark : _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: couleur.withValues(alpha: 0.35)),
      ),
      child: Column(children: [
        // ★ v9.93 Bug 2 fix : tout le header semaine est cliquable
        InkWell(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14), topRight: Radius.circular(14)),
          onTap: () => setState(() =>
              isOpen ? _expanded.remove(key) : _expanded.add(key)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: couleur.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('📋', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(bs.libelle,
                    style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
                Text('${bs.rapportsJson.length} jour${bs.rapportsJson.length > 1 ? "s" : ""} · ${bs.totalCourses} courses',
                    style: const TextStyle(color: Colors.white38, fontSize: 14)),
              ])),
              _badgeTaux(bs.tauxGagnant, couleur),
              const SizedBox(width: 8),
              Icon(isOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: Colors.white24, size: 18),
            ]),
          ),
        ),
        if (isOpen) ...[
          const Divider(height: 1, color: Colors.white12),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(children: bs.rapportsJson.reversed.map((rjson) {
              try {
                final r = RapportJournalier.fromJson(
                    json.decode(rjson) as Map<String, dynamic>);
                return _buildEntree(r, ia, false, compact: true);
              } catch (_) {
                return const SizedBox();
              }
            }).toList()),
          ),
        ],
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  BILAN HEBDO — semaine en cours (widget existant conservé)
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildBilanHebdo(Map<String, dynamic> h, IaPersonalityService ia) {
    final nbJours      = h['nbJours']       as int;
    final tauxGagnant  = (h['tauxGagnant']  as num).toDouble();
    final tauxTop3     = (h['tauxTop3']     as num).toDouble();
    final totalCourses = h['totalCourses']  as int;
    final meilleureDisc= h['meilleureDisc'] as String;
    final meilleurTaux = (h['meilleurTaux'] as num).toDouble();
    final semaine      = h['semaine']       as String;
    final evolutionPoids = (h['evolutionPoids'] as Map<String, dynamic>?) ?? {};
    final couleur = _couleurTaux(tauxGagnant);

    final gains = evolutionPoids.entries
        .where((e) => (e.value as num) > 0).toList()
      ..sort((a, b) => (b.value as num).compareTo(a.value as num));
    final top3Gains = gains.take(3).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [couleur.withValues(alpha: 0.18), _card],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: couleur.withValues(alpha: 0.5), width: 1.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('📅', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Bilan de la semaine (depuis le $semaine)',
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            Text('$nbJours jour${nbJours > 1 ? "s" : ""} analysé${nbJours > 1 ? "s" : ""} · $totalCourses courses',
                style: const TextStyle(color: Colors.white54, fontSize: 14)),
          ])),
          _badgeTaux(tauxGagnant, couleur),
        ]),
        const SizedBox(height: 14),
        const Divider(color: Colors.white12, height: 1),
        const SizedBox(height: 12),
        Wrap(spacing: 16, runSpacing: 8, children: [
          _statHebdo('🥇', 'Gagnant', '${tauxGagnant.toStringAsFixed(0)}%', couleur),
          _statHebdo('🎯', 'Top 3', '${tauxTop3.toStringAsFixed(0)}%',
              tauxTop3 >= 65 ? _green : Colors.white54),
          if (meilleureDisc.isNotEmpty && meilleurTaux > 0)
            _statHebdo('🏆', meilleureDisc.split(' ').first,
                '${meilleurTaux.toStringAsFixed(0)}%', _gold),
        ]),
        if (top3Gains.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Critères renforcés cette semaine :',
              style: TextStyle(color: Colors.white54, fontSize: 14)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, children: top3Gains.map((e) {
            final delta = (e.value as num).toDouble();
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _green.withValues(alpha: 0.3)),
              ),
              child: Text('${e.key} +${(delta * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(color: _green, fontSize: 14)),
            );
          }).toList()),
        ],
        const SizedBox(height: 12),
        Text(
          _phraseBilanHebdo(tauxGagnant, nbJours, meilleureDisc, ia.prenom),
          style: const TextStyle(color: Colors.white70, fontSize: 16,
              fontStyle: FontStyle.italic, height: 1.4),
        ),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  ENTREE JOURNALIERE
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildEntree(RapportJournalier rapport, IaPersonalityService ia,
      bool isLatest, {bool compact = false}) {
    final date        = rapport.date;
    final nbCourses   = rapport.nbAvecResultat;
    final tauxGagnant = rapport.tauxGagnant;
    final tauxTop3    = rapport.tauxTop3;
    final note        = rapport.noteJournee ?? '';
    final disciplines = rapport.parDiscipline;
    final texte       = _genererTexte(rapport, ia);
    final couleur     = _couleurNote(note);
    final emojiNote   = _emojiNote(note);
    final jourStr     = _formatDate(date);

    return Container(
      margin: EdgeInsets.only(bottom: compact ? 8 : 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          Container(
            width: compact ? 32 : 40,
            height: compact ? 32 : 40,
            decoration: BoxDecoration(
              color: couleur.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: couleur.withValues(alpha: 0.5),
                  width: isLatest ? 2 : 1),
            ),
            child: Center(child: Text(emojiNote,
                style: TextStyle(fontSize: compact ? 14 : 18))),
          ),
          Container(width: 2, height: 20, color: Colors.white12),
        ]),
        SizedBox(width: compact ? 8 : 12),
        Expanded(
          child: Container(
            padding: EdgeInsets.all(compact ? 14 : 14),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isLatest ? couleur.withValues(alpha: 0.4) : Colors.white12,
                width: isLatest ? 1.5 : 1,
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(jourStr, style: TextStyle(
                    color: isLatest ? Colors.white : Colors.white70,
                    fontSize: compact ? 16 : 18,
                    fontWeight: FontWeight.bold))),
                if (isLatest)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: couleur.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('Dernière entrée',
                        style: TextStyle(color: couleur, fontSize: 14,
                            fontWeight: FontWeight.bold)),
                  ),
              ]),
              SizedBox(height: compact ? 6 : 10),
              if (!compact) ...[
                Text(ia.avatarEmoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(height: 6),
              ],
              Text(texte, style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 16 : 18,
                  height: 1.55,
                  fontStyle: FontStyle.italic)),
              SizedBox(height: compact ? 8 : 12),
              const Divider(color: Colors.white12, height: 1),
              SizedBox(height: compact ? 6 : 10),
              Wrap(spacing: 12, runSpacing: 6, children: [
                _stat('🏇', '$nbCourses courses'),
                if (rapport.nbAvecResultat > 0)
                  _stat('✅', '${tauxGagnant.toStringAsFixed(0)}% gagnant'),
                if (rapport.nbAvecResultat > 0)
                  _stat('🎯', '${tauxTop3.toStringAsFixed(0)}% top 3'),
                if (disciplines.isNotEmpty)
                  _stat('📍', '${disciplines.length} discipline${disciplines.length > 1 ? "s" : ""}'),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildVide(IaPersonalityService ia) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(ia.avatarEmoji, style: const TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          Text('${ia.prenom} n\'a pas encore de journal',
              style: const TextStyle(color: Colors.white, fontSize: 18,
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text(
            'Lance une analyse journée pour que je commence à écrire mes observations.',
            style: TextStyle(color: Colors.white54, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════════════════════════
  Widget _badgeTaux(double taux, Color couleur) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: couleur.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text('${taux.toStringAsFixed(0)}% ✓',
        style: TextStyle(color: couleur, fontSize: 15, fontWeight: FontWeight.bold)),
  );

  Widget _chipStat(String emoji, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(emoji, style: const TextStyle(fontSize: 14)),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _statHebdo(String emoji, String label, String valeur, Color couleur) =>
    Column(mainAxisSize: MainAxisSize.min, children: [
      Text(emoji, style: const TextStyle(fontSize: 16)),
      const SizedBox(height: 2),
      Text(valeur, style: TextStyle(color: couleur, fontSize: 14, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 14)),
    ]);

  Widget _stat(String emoji, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
    Text(emoji, style: const TextStyle(fontSize: 16)),
    const SizedBox(width: 5),
    Text(label, style: const TextStyle(color: Colors.white54, fontSize: 15)),
  ]);

  Color _couleurTaux(double taux) {
    if (taux >= 60) return _green;
    if (taux >= 40) return _blue;
    if (taux >= 25) return _orange;
    return _red;
  }

  Color _couleurNote(String note) {
    if (note.contains('Excellente')) return _green;
    if (note.contains('Bonne'))      return _blue;
    if (note.contains('Moyenne'))    return _orange;
    return _red;
  }

  String _emojiNote(String note) {
    if (note.contains('Excellente')) return '⭐';
    if (note.contains('Bonne'))      return '👍';
    if (note.contains('Moyenne'))    return '➖';
    if (note.contains('Faible'))     return '⚠️';
    return '📋';
  }

  String _phraseBilanHebdo(double taux, int nbJours, String disc, String prenom) {
    if (taux >= 60) return 'Belle semaine ! Avec $nbJours jours et ${taux.toStringAsFixed(0)}% de réussite, mes algorithmes progressent.${disc.isNotEmpty ? " $disc est ma discipline forte." : ""}';
    if (taux >= 40) return 'Semaine correcte : ${taux.toStringAsFixed(0)}% sur $nbJours jours. J\'affine mes poids pour la semaine prochaine.';
    return 'Semaine difficile avec ${taux.toStringAsFixed(0)}% de réussite. Mais chaque erreur m\'apprend quelque chose — j\'ajuste mes critères en conséquence.';
  }

  String _formatDate(DateTime date) {
    const mois = ['','jan','fév','mar','avr','mai','juin','juil','aoû','sep','oct','nov','déc'];
    final now     = DateTime.now();
    final today   = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(date.year, date.month, date.day);
    final diff    = today.difference(dateOnly).inDays;
    final dateStr = '${date.day.toString().padLeft(2,'0')}/${date.month.toString().padLeft(2,'0')}/${date.year}';
    if (diff == 0) return 'Aujourd\'hui · $dateStr';
    if (diff == 1) return 'Hier · $dateStr';
    if (diff < 7)  return 'Il y a $diff jours · $dateStr';
    return '${date.day} ${mois[date.month]} ${date.year}';
  }

  String _genererTexte(RapportJournalier rapport, IaPersonalityService ia) {
    final rng         = Random();
    final nbCourses   = rapport.nbAvecResultat;
    final tauxGagnant = rapport.tauxGagnant;
    final tauxTop3    = rapport.tauxTop3;
    final nbPoids     = rapport.nbMisesAJourPoids;
    final note        = rapport.noteJournee ?? '';
    final disciplines = rapport.parDiscipline;
    final courses     = rapport.coursesDetail;
    final now         = DateTime.now();
    final today       = DateTime(now.year, now.month, now.day);
    final rDay        = DateTime(rapport.date.year, rapport.date.month, rapport.date.day);
    final isToday     = rDay == today;

    final buf = StringBuffer();

    if (isToday && nbCourses == 0) {
      final nbTotal = rapport.nbCoursesAnalysees;
      if (nbTotal > 0) {
        return 'Journée en cours — $nbTotal course${nbTotal > 1 ? "s" : ""} dans le programme, résultats PMU pas encore disponibles.';
      }
      return 'Journée en cours — résultats PMU attendus après 20h.';
    }

    if (nbCourses == 0) {
      return 'Journée sans courses terminées à analyser.';
    }

    final intros = isToday
        ? ['Bilan partiel : $nbCourses course${nbCourses > 1 ? "s" : ""} avec résultat officiel (journée en cours).']
        : [
            'J\'ai analysé $nbCourses course${nbCourses > 1 ? "s" : ""} avec résultat officiel.',
            '$nbCourses course${nbCourses > 1 ? "s" : ""} terminée${nbCourses > 1 ? "s" : ""} pour cette journée.',
          ];
    buf.write(intros[rng.nextInt(intros.length)]);

    buf.write(' Sur $nbCourses avec résultat officiel, ');
    if (tauxGagnant >= 70) {
      buf.write('mon favori a gagné dans ${tauxGagnant.toStringAsFixed(0)}% des cas — excellente journée.');
    } else if (tauxGagnant >= 50) {
      buf.write('mon favori a gagné dans ${tauxGagnant.toStringAsFixed(0)}% des cas. Satisfaisant.');
    } else if (tauxGagnant >= 30) {
      buf.write('mon taux était de ${tauxGagnant.toStringAsFixed(0)}%. Journée difficile.');
    } else {
      buf.write('je n\'ai réussi qu\'à ${tauxGagnant.toStringAsFixed(0)}%. J\'ai du travail.');
    }
    if (tauxTop3 >= 70) buf.write(' Top 3 à ${tauxTop3.toStringAsFixed(0)}% — bonne calibration.');

    if (courses.isNotEmpty) {
      try {
        final confirmees = courses.where((c) => c.favoriTop3).toList();
        final ratees     = courses.where((c) => !c.favoriTop3).toList();
        if (confirmees.isNotEmpty) {
          final c = confirmees[rng.nextInt(confirmees.length)];
          if (c.nomCourse.isNotEmpty) buf.write(' ${c.nomCourse} m\'a confirmé mes critères.');
        } else if (ratees.isNotEmpty) {
          final c = ratees[rng.nextInt(ratees.length)];
          if (c.nomCourse.isNotEmpty) buf.write(' ${c.nomCourse} m\'a surprise — je vais revoir ce type de course.');
        }
      } catch (_) {}
    }

    if (nbPoids > 0) buf.write(' J\'ai mis à jour $nbPoids paramètre${nbPoids > 1 ? "s" : ""} de mon algorithme.');

    if (disciplines.isNotEmpty) {
      try {
        final meilleure = disciplines.reduce((a, b) => a.tauxGagnant > b.tauxGagnant ? a : b);
        if (meilleure.discipline.isNotEmpty && meilleure.tauxGagnant > 0) {
          buf.write(' Meilleure discipline : ${meilleure.discipline} (${meilleure.tauxGagnant.toStringAsFixed(0)}%).');
        }
      } catch (_) {}
    }

    if (note.contains('Excellente')) buf.write(' Une journée dont je suis fière.');
    else if (note.contains('Faible')) buf.write(' Je retiens les leçons pour m\'améliorer.');

    return buf.toString();
  }
}
