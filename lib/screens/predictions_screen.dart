import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/pmu_provider.dart';
import '../models/pmu_models.dart';
import '../services/bookmaker_service.dart';
import '../utils/format_euros.dart';

class PredictionsScreen extends StatelessWidget {
  const PredictionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PmuProvider>();
    final preds = provider.predictions;

    return Scaffold(
      backgroundColor: const Color(0xFF0D2818),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1F12),
        elevation: 0,
        title: const Row(children: [
          Icon(Icons.how_to_vote, color: Color(0xFF4CAF7D), size: 20),
          SizedBox(width: 8),
          Text('Mes Pronostics',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
        ]),
        actions: [
          if (preds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Color(0xFFEF5350)),
              tooltip: 'Effacer tout',
              onPressed: () => _confirmerEffacerTout(context, provider),
            ),
        ],
      ),
      body: Column(children: [
        // ─ Bannière résumé ─
        if (preds.isNotEmpty) _SummaryBanner(provider: provider),

        // ─ Liste des pronostics ─
        Expanded(
          child: preds.isEmpty
              ? const _EmptyView()
              : ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  itemCount: preds.length,
                  itemBuilder: (ctx, i) => _PredCard(
                    pred: preds[i],
                    provider: provider,
                    onDelete: () =>
                        provider.removePrediction(preds[i].id),
                    onShowBookmakers: () =>
                        _showBookmakerBottomSheet(context, preds[i]),
                  ),
                ),
        ),
      ]),
    );
  }

  // ─── Dialogue confirmation effacer tout ──────────────────────────────────

  void _confirmerEffacerTout(BuildContext context, PmuProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1F12),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.warning_amber, color: Color(0xFFFFB74D)),
          SizedBox(width: 8),
          Text('Effacer tout ?',
              style: TextStyle(color: Colors.white, fontSize: 18)),
        ]),
        content: const Text(
          'Voulez-vous supprimer tous vos pronostics enregistrés ?\nCette action est irréversible.',
          style: TextStyle(color: Colors.white60, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler',
                style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              provider.clearAllPredictions();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Tous les pronostics ont été supprimés'),
                  backgroundColor: Color(0xFF2E7D52),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF5350)),
            child: const Text('Effacer tout',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ─── Bottom sheet comparateur de cotes ───────────────────────────────────

  void _showBookmakerBottomSheet(BuildContext context, UserPrediction pred) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A1F12),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _BookmakerSheet(pred: pred),
    );
  }
}

// ─── Bannière résumé ─────────────────────────────────────────────────────────

class _SummaryBanner extends StatelessWidget {
  final PmuProvider provider;
  const _SummaryBanner({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A6B3A), Color(0xFF0D3D20)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E7D52)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _StatItem(
          icon: Icons.list_alt,
          label: 'Total',
          value: '${provider.totalPredictions}',
          color: Colors.white,
        ),
        Container(width: 1, height: 36, color: const Color(0xFF2E7D52)),
        _StatItem(
          icon: Icons.check_circle,
          label: 'Réussis',
          value: '${provider.correctPredictions}',
          color: const Color(0xFF4CAF7D),
        ),
        Container(width: 1, height: 36, color: const Color(0xFF2E7D52)),
        _StatItem(
          icon: Icons.percent,
          label: 'Taux',
          value: '${provider.successRate.toStringAsFixed(0)}%',
          color: const Color(0xFFFFB74D),
        ),
        Container(width: 1, height: 36, color: const Color(0xFF2E7D52)),
        _StatItem(
          icon: Icons.account_balance_wallet,
          label: 'Gains nets',
          value: '${provider.totalGainsNet >= 0 ? '+' : ''}${fmtEuros(provider.totalGainsNet)}€',
          color: provider.totalGainsNet >= 0 ? const Color(0xFF69F0AE) : const Color(0xFFEF5350),
        ),
      ]),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatItem(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(height: 4),
      Text(value,
          style: TextStyle(
              color: color, fontSize: 18, fontWeight: FontWeight.bold)),
      Text(label,
          style: const TextStyle(color: Colors.white54, fontSize: 13)),
    ]);
  }
}

// ─── Carte pronostic ──────────────────────────────────────────────────────────

class _PredCard extends StatelessWidget {
  final UserPrediction pred;
  final PmuProvider provider;
  final VoidCallback onDelete;
  final VoidCallback onShowBookmakers;

  const _PredCard({
    required this.pred,
    required this.provider,
    required this.onDelete,
    required this.onShowBookmakers,
  });

  @override
  Widget build(BuildContext context) {
    final isCorrect = pred.isCorrect;
    Color borderColor = const Color(0xFF2E7D52).withValues(alpha: 0.4);
    if (isCorrect == true) borderColor = const Color(0xFF4CAF7D);
    else if (isCorrect == false) borderColor = const Color(0xFFEF5350);

    return Dismissible(
      key: Key(pred.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFEF5350).withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xFFEF5350).withValues(alpha: 0.5)),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete, color: Color(0xFFEF5350), size: 28),
            Text('Supprimer',
                style: TextStyle(color: Color(0xFFEF5350), fontSize: 13)),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF0A1F12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            title: const Text('Supprimer ce pronostic ?',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            content: Text(
              '${pred.nomCheval} — ${pred.nomCourse}',
              style: const TextStyle(color: Colors.white60),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler',
                    style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF5350)),
                child: const Text('Supprimer',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (_) {
        onDelete();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${pred.nomCheval} supprimé'),
            backgroundColor: const Color(0xFF1A4731),
            action: SnackBarAction(
              label: 'OK',
              textColor: const Color(0xFF4CAF7D),
              onPressed: () {},
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A4731).withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: borderColor),
        ),
        child: Column(children: [
          // ─ Ligne principale ─
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              // Numéro cheval
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFF0D2818),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF2E7D52)),
                ),
                child: Center(
                  child: Text('${pred.numeroCheval}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),

              // Infos
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pred.nomCheval,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                    Text(pred.nomCourse,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 14),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 5),
                    Wrap(spacing: 5, children: [
                      _Tag(pred.hippodrome, const Color(0xFF1A4731)),
                      _Tag(pred.typePari, const Color(0xFF2E7D52)),
                      _Tag(
                          'Cote ${pred.cote > 0 ? pred.cote.toStringAsFixed(1) : "-"}',
                          const Color(0xFF1B5E20)),
                    ]),
                  ],
                ),
              ),

              // Statut + gains
              Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                if (isCorrect == true)
                  const Icon(Icons.check_circle, color: Color(0xFF4CAF7D), size: 26)
                else if (isCorrect == false)
                  const Icon(Icons.cancel, color: Color(0xFFEF5350), size: 26)
                else
                  const Icon(Icons.watch_later_outlined, color: Color(0xFFFFB74D), size: 26),
                const SizedBox(height: 4),
                // Gains nets affichés si mise définie
                if (pred.montantMise > 0)
                  Text(
                    isCorrect == null
                        ? '${fmtEuros(pred.montantMise)}€ misé'
                        : '${pred.gainNet >= 0 ? '+' : ''}${fmtEuros(pred.gainNet)}€',
                    style: TextStyle(
                      color: isCorrect == null
                          ? Colors.white38
                          : pred.gainNet >= 0
                              ? const Color(0xFF69F0AE)
                              : const Color(0xFFEF5350),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                const SizedBox(height: 4),
                // Bouton supprimer
                GestureDetector(
                  onTap: onDelete,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF5350).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFEF5350).withValues(alpha: 0.4)),
                    ),
                    child: const Icon(Icons.delete_outline, color: Color(0xFFEF5350), size: 14),
                  ),
                ),
              ]),
            ]),
          ),

          // ─ Bouton Valider le résultat (si pas encore validé) ─
          if (pred.isCorrect == null)
            InkWell(
              onTap: () => _validerDialog(context, pred),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.07),
                  border: Border(
                    top: BorderSide(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.25)),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.how_to_reg, color: Color(0xFFFFD700), size: 15),
                    SizedBox(width: 6),
                    Text('Valider le résultat',
                        style: TextStyle(
                            color: Color(0xFFFFD700),
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),

          // ─ Bouton Comparer les cotes ─
          if (pred.cote > 0)
            InkWell(
              onTap: onShowBookmakers,
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(13)),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.12),
                  border: Border(
                    top: BorderSide(
                        color: const Color(0xFF2E7D52)
                            .withValues(alpha: 0.3)),
                  ),
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(13)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.compare_arrows,
                        color: Color(0xFF64B5F6), size: 16),
                    SizedBox(width: 6),
                    Text('Comparer les cotes bookmakers',
                        style: TextStyle(
                            color: Color(0xFF64B5F6),
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward_ios,
                        color: Color(0xFF64B5F6), size: 10),
                  ],
                ),
              ),
            ),
        ]),
      ),
    );
  }

  void _validerDialog(BuildContext context, UserPrediction pred) {
    double mise = pred.montantMise > 0 ? pred.montantMise : 10.0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInnerState) {
          final gainEstime = (pred.cote * mise) - mise;
          return AlertDialog(
            backgroundColor: const Color(0xFF0A1F12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              const Icon(Icons.how_to_reg, color: Color(0xFFFFD700)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Valider : ${pred.nomCheval}',
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
              ),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Mise jouée (€) :', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [2.0, 5.0, 10.0, 20.0, 50.0].map((v) {
                  final sel = (mise - v).abs() < 0.01;
                  return GestureDetector(
                    onTap: () => setInnerState(() => mise = v),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: sel ? const Color(0xFF2E7D52) : const Color(0xFF1A4731).withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: sel ? const Color(0xFF4CAF7D) : const Color(0xFF2E7D52).withValues(alpha: 0.4)),
                      ),
                      child: Text('${v.toStringAsFixed(0)}€',
                          style: TextStyle(
                              color: sel ? Colors.white : Colors.white54, fontSize: 14)),
                    ),
                  );
                }).toList(),
              ),
              Slider(
                value: mise,
                min: 1,
                max: 200,
                divisions: 199,
                activeColor: const Color(0xFF4CAF7D),
                inactiveColor: const Color(0xFF2E7D52).withValues(alpha: 0.3),
                onChanged: (v) => setInnerState(() => mise = v.roundToDouble()),
              ),
              Text('Mise : ${mise.toStringAsFixed(0)} €',
                  style: const TextStyle(color: Color(0xFF4CAF7D), fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              Text('Gain estimé si gagnant : +${gainEstime.toStringAsFixed(2)} €',
                  style: const TextStyle(color: Color(0xFFFFD700), fontSize: 14)),
              const SizedBox(height: 14),
              const Text('Résultat ?', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check, color: Colors.white, size: 16),
                    label: const Text('Gagné ✅', style: TextStyle(color: Colors.white, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      provider.validatePrediction(pred.id,
                          isCorrect: true,
                          montantMise: mise,
                          gainRealise: gainEstime);
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('🏆 ${pred.nomCheval} gagné ! +${gainEstime.toStringAsFixed(2)} €'),
                        backgroundColor: const Color(0xFF1B5E20),
                      ));
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
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('❌ ${pred.nomCheval} perdu — ${fmtEuros(mise)} €'),
                        backgroundColor: const Color(0xFF7F1919),
                      ));
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
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color),
      ),
      child: Text(label,
          style: const TextStyle(color: Colors.white60, fontSize: 14)),
    );
  }
}

// ─── Bottom Sheet Comparateur de cotes ───────────────────────────────────────

class _BookmakerSheet extends StatefulWidget {
  final UserPrediction pred;
  const _BookmakerSheet({required this.pred});

  @override
  State<_BookmakerSheet> createState() => _BookmakerSheetState();
}

class _BookmakerSheetState extends State<_BookmakerSheet> {
  double _mise = 10.0;

  @override
  Widget build(BuildContext context) {
    final cotes = BookmakerService.getCotesTriees(widget.pred.cote);
    final meilleure = cotes.isNotEmpty ? cotes.first : null;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0A1F12),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Titre
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.compare_arrows,
                      color: Color(0xFFFFD700), size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Comparer les cotes — ${widget.pred.nomCheval}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(
                  '${widget.pred.nomCourse} • ${widget.pred.hippodrome}',
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),

                // Disclaimer
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB74D).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color:
                            const Color(0xFFFFB74D).withValues(alpha: 0.3)),
                  ),
                  child: const Row(children: [
                    Icon(Icons.info_outline,
                        color: Color(0xFFFFB74D), size: 14),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Cotes estimées — vérifiez les cotes réelles sur chaque site avant de parier.',
                        style: TextStyle(
                            color: Color(0xFFFFB74D), fontSize: 13),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),

          // Mise slider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: _MiseRowSimple(
              mise: _mise,
              onChanged: (v) => setState(() => _mise = v),
            ),
          ),

          const SizedBox(height: 8),

          // Meilleure cote highlight
          if (meilleure != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _MeilleureCoteCard(
                bm: meilleure,
                mise: _mise,
                cotePmu: widget.pred.cote,
              ),
            ),

          const SizedBox(height: 10),

          // Liste bookmakers
          Expanded(
            child: ListView.builder(
              controller: scrollCtrl,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              itemCount: cotes.length,
              itemBuilder: (_, i) => _BookmakerRow(
                bm: cotes[i],
                mise: _mise,
                cotePmu: widget.pred.cote,
              ),
            ),
          ),

          // Footer légal
          Container(
            padding: const EdgeInsets.all(12),
            color: const Color(0xFF071A0F),
            child: const Text(
              '⚠️ Le jeu d\'argent comporte des risques. Jouez de manière responsable. 18+ uniquement.',
              style: TextStyle(color: Colors.white30, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Slider de mise simple ────────────────────────────────────────────────────

class _MiseRowSimple extends StatelessWidget {
  final double mise;
  final ValueChanged<double> onChanged;
  const _MiseRowSimple({required this.mise, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const Text('Mise :',
          style: TextStyle(color: Colors.white60, fontSize: 14)),
      const SizedBox(width: 10),
      // Presets
      ...([2.0, 5.0, 10.0, 20.0, 50.0]).map((v) {
        final sel = (mise - v).abs() < 0.01;
        return GestureDetector(
          onTap: () => onChanged(v),
          child: Container(
            margin: const EdgeInsets.only(right: 5),
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: sel
                  ? const Color(0xFF2E7D52)
                  : const Color(0xFF1A4731).withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: sel
                      ? const Color(0xFF4CAF7D)
                      : const Color(0xFF2E7D52).withValues(alpha: 0.4)),
            ),
            child: Text('${v.toStringAsFixed(0)}€',
                style: TextStyle(
                    color: sel ? Colors.white : Colors.white54,
                    fontSize: 14,
                    fontWeight:
                        sel ? FontWeight.bold : FontWeight.normal)),
          ),
        );
      }),
      const Spacer(),
      Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF2E7D52).withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF4CAF7D)),
        ),
        child: Text('${mise.toStringAsFixed(0)}€',
            style: const TextStyle(
                color: Color(0xFF4CAF7D),
                fontWeight: FontWeight.bold,
                fontSize: 14)),
      ),
    ]);
  }
}

// ─── Meilleure cote highlight ─────────────────────────────────────────────────

class _MeilleureCoteCard extends StatelessWidget {
  final BookmakerCote bm;
  final double mise;
  final double cotePmu;
  const _MeilleureCoteCard(
      {required this.bm, required this.mise, required this.cotePmu});

  @override
  Widget build(BuildContext context) {
    final gain = bm.gainPour(mise);
    final bonusPct = BookmakerService.bonusCoteVsPmu(cotePmu, bm.cote);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFD700).withValues(alpha: 0.15),
            const Color(0xFFFFD700).withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
      ),
      child: Row(children: [
        const Text('🏆', style: TextStyle(fontSize: 22)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('MEILLEURE COTE',
                style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Row(children: [
              Text('${bm.bookmaker.emoji} ${bm.bookmaker.nom}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              if (bonusPct > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF7D).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: const Color(0xFF4CAF7D)
                            .withValues(alpha: 0.6)),
                  ),
                  child: Text('+${bonusPct.toStringAsFixed(0)}% vs PMU',
                      style: const TextStyle(
                          color: Color(0xFF4CAF7D),
                          fontSize: 14,
                          fontWeight: FontWeight.bold)),
                ),
            ]),
            if (bm.bookmaker.bonus.isNotEmpty)
              Text(bm.bookmaker.bonus,
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 13)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(bm.cote.toStringAsFixed(2),
              style: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 26,
                  fontWeight: FontWeight.bold)),
          Text('+${fmtEuros(gain)}€ / ${fmtEuros(mise)}€ misé',
              style: const TextStyle(color: Colors.white54, fontSize: 13)),
        ]),
      ]),
    );
  }
}

// ─── Ligne bookmaker ──────────────────────────────────────────────────────────

class _BookmakerRow extends StatelessWidget {
  final BookmakerCote bm;
  final double mise;
  final double cotePmu;
  const _BookmakerRow(
      {required this.bm, required this.mise, required this.cotePmu});

  @override
  Widget build(BuildContext context) {
    final gain = bm.gainPour(mise);
    final color = Color(bm.bookmaker.couleur);
    final isFirst = bm.isMeilleure;
    final bonusPct = BookmakerService.bonusCoteVsPmu(cotePmu, bm.cote);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isFirst
            ? color.withValues(alpha: 0.12)
            : const Color(0xFF1A4731).withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFirst ? color.withValues(alpha: 0.8) : color.withValues(alpha: 0.3),
          width: isFirst ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openBookmaker(context, bm.bookmaker.urlApp),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            // Logo / Emoji
            Text(bm.bookmaker.emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),

            // Nom + description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(bm.bookmaker.nom,
                        style: TextStyle(
                            color: isFirst ? Colors.white : Colors.white70,
                            fontSize: 14,
                            fontWeight: isFirst
                                ? FontWeight.bold
                                : FontWeight.normal)),
                    if (isFirst) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: const Color(0xFFFFD700)
                                  .withValues(alpha: 0.6)),
                        ),
                        child: const Text('MEILLEURE',
                            style: TextStyle(
                                color: Color(0xFFFFD700),
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ]),
                  Text(bm.bookmaker.description,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 13)),
                  if (bm.bookmaker.bonus.isNotEmpty)
                    Text('🎁 ${bm.bookmaker.bonus}',
                        style: const TextStyle(
                            color: Color(0xFF4CAF7D), fontSize: 14)),
                ],
              ),
            ),

            // Cote + gain
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(bm.cote.toStringAsFixed(2),
                  style: TextStyle(
                      color: isFirst ? const Color(0xFFFFD700) : color,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              Text('+${fmtEuros(gain)}€',
                  style: const TextStyle(
                      color: Color(0xFF4CAF7D),
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              if (bonusPct > 0 && bm.bookmaker.nom != 'PMU')
                Text('+${bonusPct.toStringAsFixed(0)}% vs PMU',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 14)),
            ]),

            const SizedBox(width: 8),
            const Icon(Icons.open_in_new, color: Colors.white30, size: 14),
          ]),
        ),
      ),
    );
  }

  Future<void> _openBookmaker(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ouvrir : $url'),
              backgroundColor: const Color(0xFF1A4731),
            ),
          );
        }
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible d\'ouvrir le lien'),
            backgroundColor: Color(0xFF1A4731),
          ),
        );
      }
    }
  }
}

// ─── Vue vide ─────────────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.how_to_vote,
            color: Colors.white.withValues(alpha: 0.12), size: 72),
        const SizedBox(height: 18),
        const Text('Aucun pronostic enregistré',
            style: TextStyle(
                color: Colors.white54,
                fontSize: 17,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
          'Ouvrez une course depuis l\'onglet Courses\net sélectionnez votre cheval pour enregistrer\nun pronostic.',
          style: TextStyle(color: Colors.white30, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF2E7D52).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: const Color(0xFF2E7D52).withValues(alpha: 0.4)),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.save, color: Color(0xFF4CAF7D), size: 16),
            SizedBox(width: 8),
            Text(
              'Vos pronostics sont sauvegardés\nautomatiquement sur votre téléphone',
              style: TextStyle(color: Color(0xFF4CAF7D), fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      ]),
    );
  }
}
