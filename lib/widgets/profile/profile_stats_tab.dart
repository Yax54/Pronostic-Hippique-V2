import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../main.dart' show NavigationNotifier; // ★ Fix navigation En attente
import '../../providers/pmu_provider.dart';
import '../../models/pmu_models.dart';

import '../../utils/format_euros.dart';

import 'profile_common_widgets.dart';

// Onglet Stats du ProfileScreen

class ProfileStatsTab extends StatelessWidget {
  final PmuProvider provider;
  final DateTime? dateDebut;
  final DateTime? dateFin;
  final List<UserPrediction> allFiltered;
  final double gainsNet;
  final double miseTotal;
  final int nbGagnes;
  final int nbPerdus;
  final int nbAttente;
  final double taux;
  final VoidCallback onPickDate;
  final VoidCallback onResetDate;

  const ProfileStatsTab({
    required this.provider,
    required this.dateDebut,
    required this.dateFin,
    required this.allFiltered,
    required this.gainsNet,
    required this.miseTotal,
    required this.nbGagnes,
    required this.nbPerdus,
    required this.nbAttente,
    required this.taux,
    required this.onPickDate,
    required this.onResetDate,
  });

  @override
  Widget build(BuildContext context) {
    final gainsNetsAll = provider.totalGainsNet;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Bannière totaux depuis le début ──────────────────────────────────
        ProfileTotauxCard(
          gainsNet: gainsNetsAll,
          miseTotal: provider.totalMise,
          totalGagnes: provider.totalGagnes,
          totalPerdu: provider.totalPerdu,
          totalPreds: provider.totalPredictions,
        ),

        const SizedBox(height: 14),

        // ── Filtre de dates ──────────────────────────────────────────────────
        ProfileDateFilterBar(
          dateDebut: dateDebut,
          dateFin: dateFin,
          onPickDate: onPickDate,
          onReset: onResetDate,
        ),

        const SizedBox(height: 14),

        // ── Titre période ─────────────────────────────────────────────────────
        Text(
          dateDebut == null
              ? 'Toutes les périodes (${allFiltered.length} paris)'
              : '${allFiltered.length} paris — ${_fmt(dateDebut!)} → ${_fmt(dateFin!)}',
          style: const TextStyle(color: Colors.white54, fontSize: 14),
        ),
        const SizedBox(height: 10),

        // ── Grille de stats ───────────────────────────────────────────────────
        ProfileStatsGrid(
          nbGagnes: nbGagnes,
          nbPerdus: nbPerdus,
          nbAttente: nbAttente,
          taux: taux,
          gainsNet: gainsNet,
          miseTotal: miseTotal,
        ),

        const SizedBox(height: 14),

        // ── Barre de progression victoires + ventilation par type de pari ─────
        if (allFiltered.isNotEmpty) ProfileProgressBar(nbGagnes: nbGagnes, nbPerdus: nbPerdus, nbAttente: nbAttente, allFiltered: allFiltered),

        const SizedBox(height: 14),

        // ── Connexion PMU ─────────────────────────────────────────────────────
        ProfileApiStatusCard(provider: provider),
      ]),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// ══════════════════════════════════════════════════════════════════════════════
//  Onglet HISTORIQUE
// ══════════════════════════════════════════════════════════════════════════════

class ProfileTotauxCard extends StatelessWidget {
  final double gainsNet;
  final double miseTotal;
  final double totalGagnes;
  final double totalPerdu;
  final int totalPreds;

  const ProfileTotauxCard({
    required this.gainsNet,
    required this.miseTotal,
    required this.totalGagnes,
    required this.totalPerdu,
    required this.totalPreds,
  });

  @override
  Widget build(BuildContext context) {
    final isPositif = gainsNet >= 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPositif
              ? [const Color(0xFF1B5E20), const Color(0xFF0D2A4A)]
              : [const Color(0xFF7F1919), const Color(0xFF3D0D0D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPositif ? const Color(0xFF4CAF7D) : const Color(0xFFEF5350),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isPositif ? const Color(0xFF4CAF7D) : const Color(0xFFEF5350)).withValues(alpha: 0.15),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.account_balance_wallet,
              color: isPositif ? const Color(0xFFFFD700) : const Color(0xFFEF9A9A), size: 20),
          const SizedBox(width: 8),
          const Text('TOTAL DEPUIS LE DÉBUT',
              style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold,
                  letterSpacing: 0.5)),
        ]),
        const SizedBox(height: 10),

        // Gains net en grand
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            '${isPositif ? '+' : ''}${gainsNet.toStringAsFixed(2)} €',
            style: TextStyle(
              color: isPositif ? const Color(0xFF69F0AE) : const Color(0xFFFF5252),
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'gains nets',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
            ),
          ),
        ]),

        const SizedBox(height: 12),

        // Détails en 3 colonnes
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          ProfileMiniStat(
            label: 'Total misé',
            value: '${miseTotal.toStringAsFixed(0)} €',
            color: Colors.white70,
            icon: Icons.payments_outlined,
          ),
          ProfileMiniStat(
            label: 'Gains bruts',
            value: '${fmtEuros(totalGagnes)} €',
            color: const Color(0xFF4CAF7D),
            icon: Icons.trending_up,
          ),
          ProfileMiniStat(
            label: 'Pertes',
            value: '-${fmtEuros(totalPerdu)} €',
            color: const Color(0xFFEF5350),
            icon: Icons.trending_down,
          ),
        ]),
      ]),
    );
  }
}

class ProfileMiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const ProfileMiniStat({required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 13)),
      ]),
      Text(value,
          style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
    ]);
  }
}

// ─── Barre filtre de dates ─────────────────────────────────────────────────────
class ProfileStatsGrid extends StatelessWidget {
  final int nbGagnes;
  final int nbPerdus;
  final int nbAttente;
  final double taux;
  final double gainsNet;
  final double miseTotal;

  const ProfileStatsGrid({
    required this.nbGagnes,
    required this.nbPerdus,
    required this.nbAttente,
    required this.taux,
    required this.gainsNet,
    required this.miseTotal,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.1,
      children: [
        ProfileStatCell(
          label: 'Gagnés',
          value: '$nbGagnes',
          color: const Color(0xFF4CAF7D),
          icon: Icons.check_circle,
        ),
        ProfileStatCell(
          label: 'Perdus',
          value: '$nbPerdus',
          color: const Color(0xFFEF5350),
          icon: Icons.cancel,
        ),
        ProfileStatCell(
          label: 'En attente',
          value: '$nbAttente',
          color: const Color(0xFFFFB74D),
          icon: Icons.watch_later,
          // ★ Fix : tap → ouvre directement l'onglet Mes Paris
          // ★ v9.92 : navigue vers Mes Paris onglet Suivi (index 1)
          onTap: nbAttente > 0 ? () {
            context.read<NavigationNotifier>().requestMesParisSuivi();
          } : null,
        ),
        ProfileStatCell(
          label: 'Taux réussite',
          value: '${taux.toStringAsFixed(0)}%',
          color: const Color(0xFF64B5F6),
          icon: Icons.percent,
        ),
        ProfileStatCell(
          label: 'Gains nets',
          value: '${gainsNet >= 0 ? '+' : ''}${fmtEuros(gainsNet)}€',
          color: gainsNet >= 0 ? const Color(0xFF69F0AE) : const Color(0xFFEF5350),
          icon: Icons.account_balance_wallet,
        ),
        ProfileStatCell(
          label: 'Total misé',
          value: '${miseTotal.toStringAsFixed(0)}€',
          color: Colors.white70,
          icon: Icons.payments,
        ),
      ],
    );
  }
}

class ProfileStatCell extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap; // ★ Fix : navigation optionnelle au tap

  const ProfileStatCell({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.onTap, // ★
  });

  @override
  Widget build(BuildContext context) {
    final widget = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: onTap != null ? 0.6 : 0.3),
            width: onTap != null ? 1.5 : 1),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 14),
              textAlign: TextAlign.center),
          if (onTap != null) ...[
            const SizedBox(width: 3),
            Icon(Icons.arrow_forward_ios, color: color.withValues(alpha: 0.6), size: 10),
          ],
        ]),
      ]),
    );
    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: widget);
    }
    return widget;
  }
}

// ─── Barre de progression ──────────────────────────────────────────────────────
class ProfileProgressBar extends StatelessWidget {
  final int nbGagnes;
  final int nbPerdus;
  final int nbAttente;
  final List<UserPrediction> allFiltered;

  const ProfileProgressBar({
    required this.nbGagnes,
    required this.nbPerdus,
    required this.nbAttente,
    required this.allFiltered,
  });

  /// Couleur par type de pari
  static Color _couleurType(String type) {
    final t = type.toLowerCase();
    if (t.contains('quinté'))  return const Color(0xFF9C27B0);
    if (t.contains('quarté'))  return const Color(0xFF2196F3);
    if (t.contains('tiercé'))  return const Color(0xFF00BCD4);
    if (t.contains('couplé'))  return const Color(0xFFFF9800);
    if (t.contains('gagnant')) return const Color(0xFF4CAF7D);
    if (t.contains('placé'))   return const Color(0xFF8BC34A);
    return const Color(0xFF607D8B);
  }

  /// Emoji par type de pari
  static String _emojiType(String type) {
    final t = type.toLowerCase();
    if (t.contains('quinté'))  return '🏆';
    if (t.contains('quarté'))  return '🥇';
    if (t.contains('tiercé'))  return '🎯';
    if (t.contains('couplé'))  return '🔗';
    if (t.contains('gagnant')) return '✅';
    if (t.contains('placé'))   return '📍';
    return '🎲';
  }

  @override
  Widget build(BuildContext context) {
    final total = nbGagnes + nbPerdus + nbAttente;
    if (total == 0) return const SizedBox.shrink();

    final pGagne = nbGagnes / total;
    final pPerdu = nbPerdus / total;

    // ── Ventilation par type de pari ─────────────────────────────────────────
    final Map<String, int> parType = {};
    for (final p in allFiltered) {
      final t = p.typePari.trim().isEmpty ? 'Autre' : p.typePari.trim();
      parType[t] = (parType[t] ?? 0) + 1;
    }
    // Trier par ordre préférentiel puis par count décroissant
    const ordre = ['Quinté+', 'Quarté+', 'Tiercé', 'Tiercé Ordre', 'Tiercé Désordre',
                   'Couplé Gagnant', 'Couplé Placé', 'Simple Gagnant', 'Simple Placé'];
    final entries = parType.entries.toList()
      ..sort((a, b) {
        final iA = ordre.indexWhere((o) => a.key.toLowerCase().contains(o.toLowerCase()));
        final iB = ordre.indexWhere((o) => b.key.toLowerCase().contains(o.toLowerCase()));
        if (iA != -1 && iB != -1) return iA.compareTo(iB);
        if (iA != -1) return -1;
        if (iB != -1) return 1;
        return b.value.compareTo(a.value);
      });

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ─ Titre ─
      const Text('Répartition des paris',
          style: TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),

      // ─ Barre résultats (Gagnés / Perdus / En attente) ─
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 12,
          child: Row(children: [
            if (pGagne > 0)
              Expanded(
                flex: (pGagne * 100).round(),
                child: Container(color: const Color(0xFF4CAF7D)),
              ),
            if (pPerdu > 0)
              Expanded(
                flex: (pPerdu * 100).round(),
                child: Container(color: const Color(0xFFEF5350)),
              ),
            if (nbAttente > 0)
              Expanded(
                flex: (nbAttente * 100 / total).round(),
                child: Container(color: const Color(0xFFFFB74D).withValues(alpha: 0.5)),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        ProfileLegendDot(color: const Color(0xFF4CAF7D), label: 'Gagnés ($nbGagnes)'),
        ProfileLegendDot(color: const Color(0xFFEF5350), label: 'Perdus ($nbPerdus)'),
        ProfileLegendDot(color: const Color(0xFFFFB74D), label: 'Attente ($nbAttente)'),
      ]),

      // ─ Ventilation par type de pari ─
      if (entries.isNotEmpty) ...[
        const SizedBox(height: 16),
        const Text('Types de paris joués',
            style: TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        ...entries.map((e) {
          final pct = e.value / total;
          final couleur = _couleurType(e.key);
          final emoji = _emojiType(e.key);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              // Label + emoji
              SizedBox(
                width: 130,
                child: Text(
                  '$emoji ${e.key}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Barre
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 10,
                    child: Row(children: [
                      Expanded(
                        flex: (pct * 100).round().clamp(1, 100),
                        child: Container(color: couleur.withValues(alpha: 0.75)),
                      ),
                      if ((pct * 100).round() < 100)
                        Expanded(
                          flex: 100 - (pct * 100).round().clamp(1, 100),
                          child: Container(color: Colors.white.withValues(alpha: 0.05)),
                        ),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Compteur
              Text(
                '${e.value}',
                style: TextStyle(
                  color: couleur,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ]),
          );
        }),
      ],
    ]);
  }
}

class ProfileLegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const ProfileLegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 13)),
    ]);
  }
}

// ─── Statut API ────────────────────────────────────────────────────────────────
class ProfileApiStatusCard extends StatelessWidget {
  final PmuProvider provider;
  const ProfileApiStatusCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A3A).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E3A5C).withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: const Color(0xFF0A1628), borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.auto_awesome, color: Color(0xFF4CAF7D), size: 20),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('PMU — Données en temps réel', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            Text('Pronostics basés sur PMU + moteur IA', style: TextStyle(color: Colors.white54, fontSize: 14)),
          ]),
        ),
        const Icon(Icons.check_circle, color: Color(0xFF4CAF7D), size: 20),
      ]),
    );
  }
}

// ─── Carte historique ──────────────────────────────────────────────────────────

