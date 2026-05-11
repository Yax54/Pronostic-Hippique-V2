import 'package:flutter/material.dart';
import '../../providers/pmu_provider.dart';
import '../../models/pmu_models.dart';
import '../../services/alert_service.dart' show TrackedCourse;
import '../../utils/format_euros.dart';
import '../../widgets/share_card_generator.dart';

import 'profile_common_widgets.dart';

// Onglet Historique du ProfileScreen

class ProfileHistoriqueTab extends StatefulWidget {
  final PmuProvider provider;
  final List<UserPrediction> allFiltered;
  final DateTime? dateDebut;
  final DateTime? dateFin;
  final VoidCallback onPickDate;
  final VoidCallback onResetDate;

  const ProfileHistoriqueTab({
    required this.provider,
    required this.allFiltered,
    required this.dateDebut,
    required this.dateFin,
    required this.onPickDate,
    required this.onResetDate,
  });

  @override
  State<ProfileHistoriqueTab> createState() => ProfileHistoriqueTabState();
}

class ProfileHistoriqueTabState extends State<ProfileHistoriqueTab> {
  String _statutFilter = 'Tous'; // Tous, Gagné, Perdu, Attente

  @override
  Widget build(BuildContext context) {
    // Filtre par statut
    List<UserPrediction> preds = widget.allFiltered;
    if (_statutFilter == 'Gagné') {
      preds = preds.where((p) => p.isCorrect == true).toList();
    } else if (_statutFilter == 'Perdu') {
      preds = preds.where((p) => p.isCorrect == false).toList();
    } else if (_statutFilter == 'Attente') {
      preds = preds.where((p) => p.isCorrect == null).toList();
    }

    return Column(children: [
      // ─ Filtres ─
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: Column(children: [
          ProfileDateFilterBar(
            dateDebut: widget.dateDebut,
            dateFin: widget.dateFin,
            onPickDate: widget.onPickDate,
            onReset: widget.onResetDate,
          ),
          const SizedBox(height: 8),
          // Filtre statut
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['Tous', 'Gagné', 'Perdu', 'Attente'].map((s) {
                final sel = _statutFilter == s;
                final color = s == 'Gagné'
                    ? const Color(0xFF4CAF7D)
                    : s == 'Perdu'
                        ? const Color(0xFFEF5350)
                        : s == 'Attente'
                            ? const Color(0xFFFFB74D)
                            : Colors.white54;
                return GestureDetector(
                  onTap: () => setState(() => _statutFilter = s),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: sel ? color.withValues(alpha: 0.2) : const Color(0xFF162033).withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: sel ? color : color.withValues(alpha: 0.3)),
                    ),
                    child: Text(s,
                        style: TextStyle(
                            color: sel ? color : Colors.white38,
                            fontSize: 14,
                            fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                  ),
                );
              }).toList(),
            ),
          ),
        ]),
      ),

      // ─ Liste ─
      Expanded(
        child: preds.isEmpty
            ? Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.history, color: Colors.white.withValues(alpha: 0.1), size: 64),
                  const SizedBox(height: 14),
                  const Text('Aucun paris pour cette période',
                      style: TextStyle(color: Colors.white38, fontSize: 15)),
                ]),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                itemCount: preds.length,
                itemBuilder: (ctx, i) => ProfileHistoriqueCard(
                  pred: preds[i],
                  provider: widget.provider,
                ),
              ),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Onglet PROFIL / Paramètres  (avec personnalisation nom + photo)
// ══════════════════════════════════════════════════════════════════════════════


// ══════════════════════════════════════════════════════════════════════════════
//  Onglet PROGRESSION ★ Lot 3 — Graphiques + Backtesting
// ══════════════════════════════════════════════════════════════════════════════

class ProfileHistoriqueCard extends StatelessWidget {
  final UserPrediction pred;
  final PmuProvider provider;

  const ProfileHistoriqueCard({required this.pred, required this.provider});

  @override
  Widget build(BuildContext context) {
    final isCorrect = pred.isCorrect;
    Color borderColor = const Color(0xFF1E3A5C).withValues(alpha: 0.35);
    Color bgColor = const Color(0xFF101E35).withValues(alpha: 0.25);
    if (isCorrect == true) {
      borderColor = const Color(0xFF4CAF7D).withValues(alpha: 0.7);
      bgColor = const Color(0xFF0D3B1F).withValues(alpha: 0.35);
    } else if (isCorrect == false) {
      borderColor = const Color(0xFFEF5350).withValues(alpha: 0.6);
      bgColor = const Color(0xFF7F1919).withValues(alpha: 0.18);
    }

    final gain = pred.gainNet;
    final dateStr = _fmtDate(pred.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: borderColor),
      ),
      child: Column(children: [
        // ─ Ligne principale ─
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(children: [
            // Numéro cheval
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF0A1628),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF1E3A5C)),
              ),
              child: Center(
                child: Text('${pred.numeroCheval}',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 10),

            // Infos course
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(pred.nomCheval,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                Text(pred.nomCourse,
                    style: const TextStyle(color: Colors.white54, fontSize: 14),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Wrap(spacing: 5, children: [
                  ProfileSmallTag(pred.hippodrome, const Color(0xFF162033)),
                  ProfileSmallTag(pred.typePari, const Color(0xFF162033)),
                  ProfileSmallTag(dateStr, Colors.white12),
                ]),
                // Badge confiance IA — toujours visible (avec score ou "non dispo")
                const SizedBox(height: 5),
                _buildScoreIABadgeSmall(pred.scoreIA),
              ]),
            ),

            // Statut + gains
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (isCorrect == true)
                const Icon(Icons.check_circle, color: Color(0xFF4CAF7D), size: 24)
              else if (isCorrect == false)
                const Icon(Icons.cancel, color: Color(0xFFEF5350), size: 24)
              else
                const Icon(Icons.watch_later_outlined, color: Color(0xFFFFB74D), size: 24),
              const SizedBox(height: 4),
              if (pred.montantMise > 0) ...[
                Text(
                  isCorrect == null
                      ? 'Mise : ${fmtEuros(pred.montantMise)}€'
                      : '${gain >= 0 ? '+' : ''}${fmtEuros(gain)}€',
                  style: TextStyle(
                    color: isCorrect == null
                        ? Colors.white54
                        : gain >= 0
                            ? const Color(0xFF69F0AE)
                            : const Color(0xFFEF5350),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                // Badge "PMU officiel" si dividende réel récupéré
                if (pred.dividendeRecupere && isCorrect == true)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D3B1F),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF4CAF7D).withValues(alpha: 0.5)),
                    ),
                    child: const Text('×PMU', style: TextStyle(color: Color(0xFF4CAF7D), fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
              ],
              // Cercle score IA — toujours visible
              const SizedBox(height: 4),
              _buildScoreIACircle(pred.scoreIA),
            ]),
          ]),
        ),

        // ─ Ligne actions ─
        Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: const Color(0xFF1E3A5C).withValues(alpha: 0.3)),
            ),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(13)),
          ),
          child: Row(children: [
            // Bouton Valider (si pas encore validé)
            if (isCorrect == null)
              Expanded(
                child: InkWell(
                  onTap: () => _validerDialog(context, pred, provider),
                  borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(13)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E3A5C).withValues(alpha: 0.15),
                      borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(13)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.how_to_reg, color: Color(0xFFFFD700), size: 15),
                        SizedBox(width: 5),
                        Text('Valider le résultat',
                            style: TextStyle(
                                color: Color(0xFFFFD700), fontSize: 14, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),

            // Bouton Partager
            InkWell(
              onTap: () => _partagerPrediction(context, pred),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.06),
                  border: Border(
                    left: BorderSide(color: const Color(0xFF1E3A5C).withValues(alpha: 0.3)),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.share, color: Color(0xFFFFD700), size: 14),
                    SizedBox(width: 4),
                    Text('Partager',
                        style: TextStyle(color: Color(0xFFFFD700), fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),

            // Bouton Supprimer
            Expanded(
              child: InkWell(
                onTap: () => _confirmerSuppression(context, pred, provider),
                borderRadius: BorderRadius.only(
                  bottomLeft: isCorrect == null ? Radius.zero : const Radius.circular(13),
                  bottomRight: const Radius.circular(13),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF5350).withValues(alpha: 0.06),
                    borderRadius: BorderRadius.only(
                      bottomLeft: isCorrect == null ? Radius.zero : const Radius.circular(13),
                      bottomRight: const Radius.circular(13),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delete_outline, color: Color(0xFFEF5350), size: 14),
                      SizedBox(width: 5),
                      Text('Supprimer',
                          style: TextStyle(color: Color(0xFFEF5350), fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ─── Dialogue de validation du résultat ───────────────────────────────────
  void _validerDialog(BuildContext context, UserPrediction pred, PmuProvider provider) {
    double mise = pred.montantMise > 0 ? pred.montantMise : 10.0;
    final estCombine = pred.estPariCombine;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInnerState) {
          // Pour les simples → calcul via cote réelle PMU
          // Pour les combinés → gain saisi manuellement (dividende PMU réel)
          final gainEstime = estCombine
              ? 0.0  // pour les combinés, on ne peut pas estimer avant la course
              : (pred.cote > 1.0 ? (pred.cote * mise) - mise : mise * 1.5);

          return AlertDialog(
            backgroundColor: const Color(0xFF0A1628),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              const Icon(Icons.how_to_reg, color: Color(0xFFFFD700)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Valider : ${pred.typePari}',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              // Info pari combiné
              if (estCombine) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D2818),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF4CAF7D).withValues(alpha: 0.4)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Row(children: [
                      Icon(Icons.info_outline, color: Color(0xFF4CAF7D), size: 14),
                      SizedBox(width: 6),
                      Text('Pari combiné PMU', style: TextStyle(color: Color(0xFF4CAF7D), fontSize: 12, fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 4),
                    const Text(
                      '⚠️ Le dividende est fixé par PMU après la course.\n'
                      'Le gain réel sera récupéré automatiquement via l\'API PMU.',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    if (pred.dividendeRecupere) ...[
                      const SizedBox(height: 6),
                      Text(
                        '✅ Dividende PMU officiel : ×${pred.dividendePmuReel!.toStringAsFixed(2)}\n'
                        'Gain net : +${fmtEuros(pred.gainNet)} €',
                        style: const TextStyle(color: Color(0xFF4CAF7D), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ]),
                ),
                const SizedBox(height: 10),
              ],
              // Mise
              const Text('Mise jouée (€) :', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                ...[2.0, 5.0, 10.0, 20.0, 50.0].map((v) {
                  final sel = (mise - v).abs() < 0.01;
                  return GestureDetector(
                    onTap: () => setInnerState(() => mise = v),
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: sel ? const Color(0xFF1565C0) : const Color(0xFF101E35).withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: sel ? const Color(0xFF42A5F5) : const Color(0xFF1E3A5C).withValues(alpha: 0.4)),
                      ),
                      child: Text('${v.toStringAsFixed(0)}€',
                          style: TextStyle(color: sel ? Colors.white : Colors.white54, fontSize: 14)),
                    ),
                  );
                }),
              ]),
              const SizedBox(height: 4),
              Slider(
                value: mise,
                min: 1,
                max: 200,
                divisions: 199,
                activeColor: const Color(0xFF4CAF7D),
                inactiveColor: const Color(0xFF1E3A5C).withValues(alpha: 0.3),
                onChanged: (v) => setInnerState(() => mise = v.roundToDouble()),
              ),
              Text('Mise : ${mise.toStringAsFixed(0)} €',
                  style: const TextStyle(color: Color(0xFF4CAF7D), fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              // Gain estimé — adapté selon type de pari
              if (!estCombine)
                Text(
                  pred.cote > 1.0
                      ? 'Gain estimé si gagnant : +${fmtEuros(gainEstime)} €'
                      : 'Gain calculé après la course',
                  style: const TextStyle(color: Color(0xFFFFD700), fontSize: 14),
                )
              else if (pred.dividendeRecupere)
                Text(
                  '🏆 Dividende PMU réel : +${fmtEuros(pred.gainNet)} €\n(×${pred.dividendePmuReel!.toStringAsFixed(2)} — officiel)',
                  style: const TextStyle(color: Color(0xFF4CAF7D), fontSize: 13, fontWeight: FontWeight.bold),
                )
              else
                const Text(
                  '⚠️ Dividende Tiercé/Quarté/Quinté :\nrécupéré automatiquement après la course',
                  style: TextStyle(color: Color(0xFFFFB74D), fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 16),
              // Boutons résultat
              const Text('Résultat ?', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check, color: Colors.white, size: 16),
                    label: const Text('Gagné ✅', style: TextStyle(color: Colors.white, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B5E20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      // Pour les combinés avec dividende récupéré → utiliser le vrai gain
                      // Pour les simples → calculer via cote réelle
                      // Pour les combinés sans dividende → marquer gagné, gain récupéré plus tard
                      final gainFinal = pred.dividendeRecupere
                          ? pred.gainNet
                          : estCombine ? null : gainEstime;
                      provider.validatePrediction(pred.id,
                          isCorrect: true,
                          montantMise: mise,
                          gainRealise: gainFinal);
                      Navigator.pop(ctx);
                      final gainMsg = pred.dividendeRecupere
                          ? '+${fmtEuros(pred.gainNet)} € (PMU officiel)'
                          : estCombine
                              ? 'dividende récupéré après la course'
                              : '+${gainEstime.toStringAsFixed(2)} €';
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('🏆 ${pred.typePari} gagné ! $gainMsg'),
                          backgroundColor: const Color(0xFF1B5E20),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.close, color: Colors.white, size: 16),
                    label: const Text('Perdu ❌', style: TextStyle(color: Colors.white, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF5350),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      provider.validatePrediction(pred.id,
                          isCorrect: false,
                          montantMise: mise,
                          gainRealise: -mise);
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('❌ ${pred.typePari} perdu — ${fmtEuros(mise)} €'),
                          backgroundColor: const Color(0xFF7F1919),
                        ),
                      );
                    },
                  ),
                ),
              ]),
            ]),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler', style: TextStyle(color: Colors.white38)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _partagerPrediction(BuildContext context, UserPrediction pred) {
    // Créer un TrackedCourse factice depuis UserPrediction pour la carte
    final fakeCourse = TrackedCourse(
      numReunion: pred.numReunion,
      numCourse: pred.numCourse,
      nomCourse: pred.nomCourse,
      hippodrome: pred.hippodrome,
      heureDepart: pred.createdAt,
      nomCheval: pred.nomCheval,
      numeroCheval: pred.numeroCheval,
      miseEngagee: pred.montantMise,
      typePari: pred.typePari,
      numerosJoues: pred.numeroCheval > 0 ? [pred.numeroCheval] : [],
      scoreIA: pred.scoreIA,
    );

    final gain = pred.isCorrect == true ? pred.gainNet : null;

    ShareCardService.partagerCourse(
      context,
      data: ShareCardData(
        typePariLabel: pred.typePari,
        paris: [fakeCourse],
        miseTotal: pred.montantMise,
        gainTotal: gain,
        estGagnant: pred.isCorrect,
        coteGlobale: pred.cote,
        scoreIA: pred.scoreIA,
      ),
    );
  }

  void _confirmerSuppression(BuildContext context, UserPrediction pred, PmuProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1628),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Supprimer ce pronostic ?',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text('${pred.nomCheval} — ${pred.nomCourse}',
            style: const TextStyle(color: Colors.white60)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              provider.removePrediction(pred.id);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF5350)),
            child: const Text('Supprimer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Badge horizontal compact pour le score IA (affiché sous les tags)
  Widget _buildScoreIABadgeSmall(double score) {
    Color color;
    String label;
    String emoji;
    // score == 0 → pari ancien sans score enregistré
    if (score <= 0) {
      color = Colors.white24;
      label = 'Non disponible';
      emoji = '⚪';
    } else if (score >= 80) {
      color = const Color(0xFF4CAF7D);
      label = 'Très haute';
      emoji = '🟢';
    } else if (score >= 65) {
      color = const Color(0xFFFFD700);
      label = 'Haute';
      emoji = '🟡';
    } else if (score >= 50) {
      color = const Color(0xFFFF9800);
      label = 'Moyenne';
      emoji = '🟠';
    } else {
      color = const Color(0xFFEF5350);
      label = 'Faible';
      emoji = '🔴';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.psychology, color: color, size: 11),
        const SizedBox(width: 3),
        Text(
          score <= 0
              ? '$emoji Confiance IA : —'
              : '$emoji Confiance IA : ${score.round()}% — $label',
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }

  /// Petit cercle score IA affiché en colonne droite
  Widget _buildScoreIACircle(double score) {
    Color color;
    // score == 0 → pari ancien sans score
    if (score <= 0) {
      color = Colors.white24;
      return Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color, width: 1.5),
        ),
        child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.psychology, color: Colors.white30, size: 16),
        ]),
      );
    }
    if (score >= 80) {
      color = const Color(0xFF4CAF7D);
    } else if (score >= 65) {
      color = const Color(0xFFFFD700);
    } else if (score >= 50) {
      color = const Color(0xFFFF9800);
    } else {
      color = const Color(0xFFEF5350);
    }
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('${score.round()}',
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.bold, height: 1.1)),
        Text('%', style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 9)),
      ]),
    );
  }
}

class ProfileSmallTag extends StatelessWidget {
  final String label;
  final Color color;
  const ProfileSmallTag(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color),
      ),
      child: Text(label, style: const TextStyle(color: Colors.white60, fontSize: 14)),
    );
  }
}

// ─── Composants hérités ────────────────────────────────────────────────────────


