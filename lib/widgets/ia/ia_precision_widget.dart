// ignore_for_file: unused_element
import 'package:flutter/material.dart';
import '../../services/ia_memory_service.dart';
import '../../services/ia_memory_models.dart';
import '../../utils/format_euros.dart';

// ─── Couleurs partagées (palette IaPerformanceScreen) ─────────────────────────
const Color _kDark   = Color(0xFF0D1B2A);
const Color _kCard   = Color(0xFF111F30);
const Color _kGreen  = Color(0xFF4CAF7D);
const Color _kDGreen = Color(0xFF2E7D52);
const Color _kGold   = Color(0xFFFFD700);
const Color _kPurple = Color(0xFF7C4DFF);

// ══════════════════════════════════════════════════════════════════════════════
//  Helpers partagés
// ══════════════════════════════════════════════════════════════════════════════

Widget _buildSectionTitle(String title) => Padding(
  padding: const EdgeInsets.only(bottom: 4),
  child: Text(title,
    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
);

// ══════════════════════════════════════════════════════════════════════════════
//  Sections Précision IA et Stats Types Paris — extraites de IaPerformanceScreen
//  Ces fonctions sont appelées directement depuis le State du screen principal.
// ══════════════════════════════════════════════════════════════════════════════

Widget buildSectionStatsTypesParis(BuildContext context) {
    final statsTypes = IaMemoryService.instance.statsParType;

    if (statsTypes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(children: [
          _buildSectionTitle('🎰 Vos paris réels — taux de réussite'),
          const SizedBox(height: 10),
          const Row(children: [
            Icon(Icons.info_outline, color: Colors.white24, size: 15),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Les stats apparaîtront dès que vous enregistrez une mise (€ > 0) sur une course.',
                style: TextStyle(color: Colors.white38, fontSize: 16),
              ),
            ),
          ]),
        ]),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('🎰 Vos paris réels — taux de réussite'),
        const SizedBox(height: 6),
        Text(
          'Uniquement vos paris avec mise > 0 € — '
          '${statsTypes.fold(0, (s, t) => s + t.nbJoues)} paris comptabilisés',
          style: const TextStyle(color: Colors.white38, fontSize: 15),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            children: [
              // En-tête du tableau
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: const [
                  SizedBox(width: 26),
                  Expanded(flex: 3, child: Text('Type de pari', style: TextStyle(color: Colors.white38, fontSize: 15, fontWeight: FontWeight.bold))),
                  SizedBox(width: 6),
                  SizedBox(width: 36, child: Text('Misés', style: TextStyle(color: Colors.white38, fontSize: 15), textAlign: TextAlign.center)),
                  SizedBox(width: 6),
                  SizedBox(width: 36, child: Text('Gagnés', style: TextStyle(color: Colors.white38, fontSize: 15), textAlign: TextAlign.center)),
                  SizedBox(width: 6),
                  SizedBox(width: 44, child: Text('Taux', style: TextStyle(color: Colors.white38, fontSize: 15), textAlign: TextAlign.center)),
                  SizedBox(width: 6),
                  SizedBox(width: 52, child: Text('Gain net', style: TextStyle(color: Colors.white38, fontSize: 15), textAlign: TextAlign.right)),
                ]),
              ),
              const Divider(height: 1, color: Colors.white12),
              ...statsTypes.asMap().entries.map((entry) {
                final idx = entry.key;
                final st  = entry.value;
                final isLast = idx == statsTypes.length - 1;
                return _buildLigneTypePari(st, isLast: isLast);
              }),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Meilleur type de pari
        _buildMeilleurTypePari(statsTypes),
      ],
    );
  }

Widget _buildLigneTypePari(StatsTypePari st, {bool isLast = false}) {
    final taux = st.tauxReussite;
    final hasData = st.nbGagnes + st.nbPerdus > 0;
    final tauxColor = !hasData ? Colors.white24
        : taux >= 50 ? _kGreen
        : taux >= 30 ? const Color(0xFFFFB74D)
        : const Color(0xFFEF5350);
    final gainColor = st.gainNet >= 0 ? _kGreen : const Color(0xFFEF5350);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(children: [
          Text(st.emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(st.typePari, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
              if (st.nbEnAttente > 0)
                Text('${st.nbEnAttente} en attente', style: const TextStyle(color: Colors.white24, fontSize: 15)),
            ]),
          ),
          const SizedBox(width: 6),
          // Nb joués
          SizedBox(width: 36, child: Text('${st.nbJoues}', style: const TextStyle(color: Colors.white60, fontSize: 16), textAlign: TextAlign.center)),
          const SizedBox(width: 6),
          // Nb gagnés
          SizedBox(width: 36, child: Text('${st.nbGagnes}', style: TextStyle(color: st.nbGagnes > 0 ? _kGreen : Colors.white38, fontSize: 16, fontWeight: st.nbGagnes > 0 ? FontWeight.bold : FontWeight.normal), textAlign: TextAlign.center)),
          const SizedBox(width: 6),
          // Taux
          SizedBox(
            width: 44,
            child: hasData
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: tauxColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: tauxColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      '${taux.toStringAsFixed(0)}%',
                      style: TextStyle(color: tauxColor, fontSize: 15, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  )
                : const Text('—', style: TextStyle(color: Colors.white24, fontSize: 16), textAlign: TextAlign.center),
          ),
          const SizedBox(width: 6),
          // Gain net
          SizedBox(
            width: 52,
            child: Text(
              st.gainNet == 0 ? '—'
                  : '${st.gainNet >= 0 ? '+' : ''}${fmtEuros(st.gainNet)}€',
              style: TextStyle(color: st.gainNet == 0 ? Colors.white24 : gainColor, fontSize: 15, fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
          ),
        ]),
      ),
      if (!isLast) Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
    ]);
  }

Widget _buildMeilleurTypePari(List<StatsTypePari> stats) {
    // Filtrer seulement ceux avec au moins 3 paris résolus
    final resolus = stats.where((s) => s.nbGagnes + s.nbPerdus >= 3).toList();
    if (resolus.isEmpty) return const SizedBox();

    // Meilleur taux
    final meilleur = resolus.reduce((a, b) => a.tauxReussite >= b.tauxReussite ? a : b);
    // Plus rentable (gain net max)
    final rentable = resolus.reduce((a, b) => a.gainNet >= b.gainNet ? a : b);

    return Row(children: [
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _kGreen.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kGreen.withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            const Text('🏆', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Meilleur taux', style: TextStyle(color: Colors.white38, fontSize: 15)),
              Text('${meilleur.typePari} — ${meilleur.tauxReussite.toStringAsFixed(0)}%',
                  style: const TextStyle(color: _kGreen, fontSize: 16, fontWeight: FontWeight.bold)),
            ])),
          ]),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _kGold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kGold.withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            const Text('💰', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Plus rentable', style: TextStyle(color: Colors.white38, fontSize: 15)),
              Text(
                '${rentable.typePari} — ${rentable.gainNet >= 0 ? '+' : ''}${fmtEuros(rentable.gainNet)}€',
                style: TextStyle(color: rentable.gainNet >= 0 ? _kGold : Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ])),
          ]),
        ),
      ),
    ]);
  }

  // ── Widget : Précision IA — 3 niveaux réels ──────────────────────────────
  //
  //  Affiche les 3 niveaux de précision IA calculés sur les vrais résultats PMU :
  //   • 🥇 Gagnant   : favori IA arrivé 1er       → signal pour Simple Gagnant
  //   • 🏅 Placé     : favori IA dans le top 3     → signal pour Couplé / Tiercé
  //   • 🎯 Sélectif  : ≥ 4 des 5 premiers IA dans le top 5 réel → signal pour Quinté+
  //
  //  Chaque niveau alimente un ajustement complémentaire des poids IA.
  // ─────────────────────────────────────────────────────────────────────────

// ════════════════════════════════════════════════════════════════════════════
//  SectionPrecisionIA — StatefulWidget autonome (filtre période intégré)
// ════════════════════════════════════════════════════════════════════════════

class SectionPrecisionIA extends StatefulWidget {
  const SectionPrecisionIA({super.key});
  @override
  State<SectionPrecisionIA> createState() => _SectionPrecisionIAState();
}

class _SectionPrecisionIAState extends State<SectionPrecisionIA> {
  String?   _filtrePeriode;
  DateTime? _filtreDebut;
  DateTime? _filtreFin;

  void _afficherDetailParType(StatsPrecisionParType p) {
    // Note: _DialogDetailTypePari est défini dans ia_dialog_detail_type_pari.dart
    // Pour éviter les problèmes d'accès private cross-file, on utilise showDialog direct
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0D1B2A),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(p.typePari, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('${p.nbBons}/${p.nbTotal} bons conseils sur 60j', style: const TextStyle(color: Colors.white60)),
            const SizedBox(height: 16),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
          ]),
        ),
      ),
    );
  }

  Future<void> _choisirPeriodePersonnalisee() async {
    final now   = DateTime.now();
    final debut = await showDatePicker(
      context: context,
      initialDate: _filtreDebut ?? now,
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
      initialDate: _filtreFin ?? now,
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
    setState(() {
      _filtrePeriode = 'custom';
      _filtreDebut   = debut;
      _filtreFin     = fin;
    });
  }

  Widget _boutonFiltre(String label, String? valeur, {IconData? icone}) {
    final actif = _filtrePeriode == valeur;
    const vertActif    = Color(0xFF4CAF7D);
    const jauneInactif = Color(0xFFFFD700);
    return GestureDetector(
      onTap: () => setState(() => _filtrePeriode = valeur),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: actif
              ? vertActif.withValues(alpha: 0.22)
              : jauneInactif.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: actif ? vertActif : jauneInactif,
            width: actif ? 2.0 : 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icone != null) ...[
              Icon(icone, size: 14,
                  color: actif ? vertActif : jauneInactif),
              const SizedBox(width: 5),
            ],
            Text(label,
                style: TextStyle(
                  color: actif ? vertActif : jauneInactif,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltrePeriode(List<StatsPrecisionParType> prList) {
    final now = DateTime.now();
    const joursF = ['','Lun','Mar','Mer','Jeu','Ven','Sam','Dim'];
    const moisF  = ['','Jan','Fév','Mar','Avr','Mai','Juin','Juil','Aoû','Sep','Oct','Nov','Déc'];
    final jourSemaine = joursF[now.weekday];
    final libAuj = '$jourSemaine ${now.day} ${moisF[now.month]}';
    final libPeriode = (_filtrePeriode == 'custom' && _filtreDebut != null && _filtreFin != null)
        ? '${_filtreDebut!.day.toString().padLeft(2,'0')}/${_filtreDebut!.month.toString().padLeft(2,'0')}'
          ' → ${_filtreFin!.day.toString().padLeft(2,'0')}/${_filtreFin!.month.toString().padLeft(2,'0')}'
        : 'Période';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            _boutonFiltre('Tout',    'all',   icone: Icons.all_inclusive),
            const SizedBox(width: 8),
            _boutonFiltre('60j IA',  null,    icone: Icons.psychology),
            const SizedBox(width: 8),
            _boutonFiltre('7 jrs',   '7j',    icone: Icons.date_range),
            const SizedBox(width: 8),
            _boutonFiltre(libAuj,    'today', icone: Icons.today),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _choisirPeriodePersonnalisee(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: _filtrePeriode == 'custom'
                      ? _kPurple.withValues(alpha: 0.22)
                      : const Color(0xFFFFD700).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _filtrePeriode == 'custom'
                        ? _kPurple
                        : const Color(0xFFFFD700),
                    width: _filtrePeriode == 'custom' ? 1.8 : 1.3,
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.calendar_month,
                      size: 12,
                      color: _filtrePeriode == 'custom'
                          ? _kPurple
                          : const Color(0xFFFFD700)),
                  const SizedBox(width: 4),
                  Text(libPeriode,
                      style: TextStyle(
                        color: _filtrePeriode == 'custom'
                            ? _kPurple
                            : const Color(0xFFFFD700),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      )),
                ]),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        _buildResumePeriode(prList),
      ],
    );
  }

  Widget _buildResumePeriode(List<StatsPrecisionParType> prList) {
    int totalNb = 0, totalBons = 0;
    for (final p in prList) {
      final stats = _statsFiltre(p);
      totalNb   += stats['nb']   ?? 0;
      totalBons += stats['bons'] ?? 0;
    }
    if (totalNb == 0) return const SizedBox();
    final taux = totalNb > 0 ? totalBons / totalNb * 100 : 0.0;
    const moisR = ['','Jan','Fév','Mar','Avr','Mai','Juin','Juil','Aoû','Sep','Oct','Nov','Déc'];
    final now2  = DateTime.now();
    final label = _filtrePeriode == null
        ? '60j glissants'
        : _filtrePeriode == 'all'
            ? 'Depuis installation'
            : _filtrePeriode == '7j'
                ? '7 derniers jours'
                : _filtrePeriode == 'today'
                    ? "Aujourd'hui ${now2.day} ${moisR[now2.month]}"
                    : _filtrePeriode == 'custom'
                        ? 'Période personnalisée'
                        : _libelleFiltre(_filtrePeriode!);
    return Row(children: [
      const Icon(Icons.bar_chart, color: Colors.white38, size: 13),
      const SizedBox(width: 5),
      Text('$label : $totalBons/$totalNb conseils bons — ${taux.toStringAsFixed(0)}% tous types',
          style: const TextStyle(color: Colors.white38, fontSize: 11)),
    ]);
  }

  Map<String, int> _statsFiltre(StatsPrecisionParType p) {
    if (_filtrePeriode == null) {
      return {'nb': p.nbTotal, 'bons': p.nbBons, 'ordre': p.nbOrdre, 'desordre': p.nbDesordre};
    } else if (_filtrePeriode == 'all') {
      return {'nb': p.nbTotalAll, 'bons': p.nbBonsAll, 'ordre': p.nbOrdreAll, 'desordre': p.nbDesordreAll};
    } else if (_filtrePeriode == '7j') {
      final fin   = DateTime.now();
      final debut = fin.subtract(const Duration(days: 7));
      return p.statsPourPeriode(debut, fin);
    } else if (_filtrePeriode == 'today') {
      final now = DateTime.now();
      final jour = DateTime(now.year, now.month, now.day);
      return p.statsPourPeriode(jour, jour);
    } else if (_filtrePeriode == 'custom' && _filtreDebut != null && _filtreFin != null) {
      return p.statsPourPeriode(_filtreDebut!, _filtreFin!);
    }
    return {'nb': p.nbTotal, 'bons': p.nbBons, 'ordre': p.nbOrdre, 'desordre': p.nbDesordre};
  }


  // ── Libellés de filtre ────────────────────────────────────────────────────
  String _libelleJour(String yyyyMMdd) {
    if (yyyyMMdd.length != 10) return yyyyMMdd;
    final parts = yyyyMMdd.split('-');
    const moisCourts = ['','Jan','Fév','Mar','Avr','Mai','Juin','Juil','Aoû','Sep','Oct','Nov','Déc'];
    final m = int.tryParse(parts[1]) ?? 0;
    final d = int.tryParse(parts[2]) ?? 0;
    return '$d ${m < moisCourts.length ? moisCourts[m] : parts[1]}';
  }

  String _libelleFiltre(String filtre) {
    if (filtre.length == 10) return _libelleJour(filtre);
    if (filtre.length == 7)  return _libelleMois(filtre);
    return filtre;
  }

  String _libelleMois(String yyyyMM) {
    if (yyyyMM.length < 7) return yyyyMM;
    final parts = yyyyMM.split('-');
    const mois = ['','Jan','Fév','Mar','Avr','Mai','Juin','Juil','Aoû','Sep','Oct','Nov','Déc'];
    final m = int.tryParse(parts[1]) ?? 0;
    final y = parts[0].substring(2);
    return '${m < mois.length ? mois[m] : parts[1]} $y';
  }

  Widget _buildLigneSeuilAdaptatif(String label, double valeurActuelle, double valeurDefaut) {
    final delta = valeurActuelle - valeurDefaut;
    Color deltaColor = Colors.white38;
    String deltaTxt = '';
    if (delta.abs() >= 0.5) {
      deltaTxt = ' (${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)})';
      deltaColor = delta > 0 ? const Color(0xFFFFB74D) : _kGreen;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(label,
            style: const TextStyle(color: Colors.white60, fontSize: 12))),
        Text(valeurActuelle.toStringAsFixed(1),
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        Text(deltaTxt, style: TextStyle(color: deltaColor, fontSize: 11)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ★ v10.77 : source fusionnée IA + Gros Paris (stats utilisateur uniquement)
    // precisionParTypeAvecGrosParis = _precisionParType (IA) + PronosticResultatsRepository
    // JAMAIS injecté dans le gradient — apprentissage inchangé.
    final prList = IaMemoryService.instance.precisionParTypeAvecGrosParis;
    final seuils = IaMemoryService.instance.seuilsConfiance;
    final poidsIdx = IaMemoryService.instance.poidsIndices;
    final hasData = prList.any((p) => p.nbTotal >= 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('🎯 Précision IA — Synthèse des 3 Indices'),
        const SizedBox(height: 6),

        // ── Encart : les 3 indices et leurs poids actuels ───────────────────
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_kPurple.withValues(alpha: 0.12), _kCard],
              begin: Alignment.topLeft,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kPurple.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Text('📐', style: TextStyle(fontSize: 15)),
                SizedBox(width: 6),
                Text('PrécisionIA = Indice 1 + Indice 2 + Indice 3',
                    style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 10),
              _buildIndiceRow(
                emoji: '📊',
                label: 'Indice 1 — Score multicritères',
                soustitre: '10 critères pondérés classent les chevaux',
                poids: poidsIdx.poidsCriteres,
                couleur: const Color(0xFF42A5F5),
              ),
              const SizedBox(height: 6),
              _buildIndiceRow(
                emoji: '🔮',
                label: 'Indice 2 — Confiance IA',
                soustitre: 'Variance des scores + domination du favori',
                poids: poidsIdx.poidsConfiance,
                couleur: const Color(0xFFAB47BC),
              ),
              const SizedBox(height: 6),
              _buildIndiceRow(
                emoji: '🏆',
                label: 'Indice 3 — Taux de Réussite',
                soustitre: 'Conseils IA corrects / total par type de pari',
                poids: poidsIdx.poidsReussite,
                couleur: _kGreen,
              ),
              const SizedBox(height: 8),
              const Text(
                '💡 Les poids s\'ajustent automatiquement : l\'indice le plus prédictif gagne en influence.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // Note explicative Taux de Réussite
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: _kGreen.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kGreen.withValues(alpha: 0.2)),
          ),
          child: Row(children: const [
            Icon(Icons.emoji_events_outlined, color: Color(0xFF66BB6A), size: 14),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                "🏆 Précision IA (30j glissants) : sur X courses conseillées Quinté+, combien l'IA avait-elle raison selon PMU ?\n"
                "Ex : 3 bons sur 5 Quinté+ = 60% de précision. ⚠️ Ces chiffres concernent les CONSEILS IA, pas vos paris.",
                // NB : le tableau 🎰 Taux de réussite par type (plus bas) concerne VOS paris enregistrés.
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),

        // ── Sélecteur de période ────────────────────────────────────────────
        if (prList.isNotEmpty) _buildFiltrePeriode(prList),

        const SizedBox(height: 10),

        if (!hasData)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(children: const [
              Icon(Icons.analytics_outlined, color: Colors.white24, size: 15),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "La précision s'affichera après la première analyse de la journée "
                  '(résultats PMU disponibles le soir).',
                  style: TextStyle(color: Colors.white38, fontSize: 14),
                ),
              ),
            ]),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(children: [
              // En-tête du tableau
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  Expanded(flex: 3, child: Text(
                    () {
                      const moisT = ['','Jan','Fév','Mar','Avr','Mai','Juin','Juil','Aoû','Sep','Oct','Nov','Déc'];
                      final nowT  = DateTime.now();
                      if (_filtrePeriode == null)       return '🏆 Précision IA — 60j glissants';
                      if (_filtrePeriode == 'all')      return '🏆 Précision IA — Depuis installation';
                      if (_filtrePeriode == '7j')       return '🏆 Précision IA — 7 derniers jours';
                      if (_filtrePeriode == 'today')    return "🏆 Précision IA — Aujourd'hui ${nowT.day} ${moisT[nowT.month]}";
                      if (_filtrePeriode == 'custom')   return '🏆 Précision IA — Période personnalisée';
                      return '🏆 Précision IA — ${_libelleFiltre(_filtrePeriode!)}';
                    }(),
                    // ★ v10.36 : fontSize 12→14 pour meilleure lisibilité
                    style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
                  )),
                  const SizedBox(width: 4),
                  // ★ v10.36 : fontSize 10→13, 11→13
                  const SizedBox(width: 58, child: Text('Bons/Total', style: TextStyle(color: Colors.white38, fontSize: 13), textAlign: TextAlign.center)),
                  const SizedBox(width: 4),
                  const SizedBox(width: 46, child: Text('Taux', style: TextStyle(color: Colors.white38, fontSize: 13), textAlign: TextAlign.center)),
                  const SizedBox(width: 4),
                  const SizedBox(width: 24, child: Text('7j', style: TextStyle(color: Colors.white38, fontSize: 13), textAlign: TextAlign.center)),
                  const SizedBox(width: 14),
                ]),
              ),
              const Divider(height: 1, color: Colors.white12),
              // Lignes par type de pari
              ...prList.asMap().entries.map((entry) {
                final i = entry.key;
                final p = entry.value;
                return _buildLignePrecisionParType(p, isLast: i == prList.length - 1, statsFiltre: _statsFiltre, afficherDetail: _afficherDetailParType);
              }),
            ]),
          ),

        if (hasData) ...[
          const SizedBox(height: 10),
          // Section seuils adaptatifs courants
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Text('⚙️', style: TextStyle(fontSize: 14)),
                  SizedBox(width: 6),
                  Text('Seuils de confiance actuels (adaptatifs)',
                      style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 8),
                const Text(
                  'Ces seuils évoluent selon la précision réelle — '
                  "l'IA devient plus ou moins sélective par type de pari.",
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
                const SizedBox(height: 8),
                _buildLigneSeuilAdaptatif('🥇 Simple Gagnant',  seuils.seuilSimpleGagnant,  80.0),
                _buildLigneSeuilAdaptatif('🎖️ Gagnant+Placé',   seuils.seuilGagnantPlace,   50.0),
                _buildLigneSeuilAdaptatif('🏅 Simple Placé',    seuils.seuilSimplePlace,    65.0),
                _buildLigneSeuilAdaptatif('🔗 Couplé Gagnant',  seuils.seuilCoupleGagnant,  75.0),
                _buildLigneSeuilAdaptatif('🔀 Couplé Placé',    seuils.seuilCouplePlace,    60.0),
                _buildLigneSeuilAdaptatif('🎯 Tiercé',          seuils.seuilTierce,         35.0),
                _buildLigneSeuilAdaptatif('4️⃣ Quarté+',          seuils.seuilQuarte,         80.0),
                _buildLigneSeuilAdaptatif('⭐ Quinté+',          seuils.seuilQuinte,          0.0),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "💡 Après chaque analyse de la journée, les 3 indices et les poids IA s'ajustent automatiquement.",
            style: TextStyle(color: Colors.white24, fontSize: 12),
          ),
        ],
      ],
    );
  }
} // fin _SectionPrecisionIAState

  /// Ligne affichant un indice de PrécisionIA avec son poids actuel et une barre de progression
Widget _buildIndiceRow({
    required String emoji,
    required String label,
    required String soustitre,
    required double poids, // 0.0 à 1.0
    required Color couleur,
  }) {
    final pct = (poids * 100).round();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(label,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: couleur.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: couleur.withValues(alpha: 0.4)),
                  ),
                  child: Text('$pct%',
                      style: TextStyle(color: couleur, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ]),
              const SizedBox(height: 3),
              Text(soustitre, style: const TextStyle(color: Colors.white38, fontSize: 11)),
              const SizedBox(height: 4),
              // Barre de progression du poids
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: poids.clamp(0.15, 0.55) / 0.55,
                  backgroundColor: Colors.white10,
                  valueColor: AlwaysStoppedAnimation<Color>(couleur.withValues(alpha: 0.7)),
                  minHeight: 4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // _afficherDetailParType est défini dans _SectionPrecisionIAState

  /// Liste scrollable de pronostics avec carte détaillée (conservée pour extension future)
Widget _buildListePronostics(List<IaPronostic> liste, String typePari,
      {required String emptyMsg}) {
    if (liste.isEmpty) {
      return Center(child: Text(emptyMsg,
          style: const TextStyle(color: Colors.white38, fontSize: 12),
          textAlign: TextAlign.center));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      itemCount: liste.length,
      itemBuilder: (_, i) => _buildCartePronostic(liste[i], typePari),
    );
  }

  /// Carte détaillée d'un pronostic IA
Widget _buildCartePronostic(IaPronostic pr, String typePari) {
    final resolu     = pr.resultatsReels;
    final bonConseil = resolu && IaMemoryService.instance.estBonConseil(pr, typePari);
    final enAttente  = !resolu;

    final Color borderColor;
    final String icone;
    if (enAttente)       { borderColor = const Color(0xFFFFB74D); icone = '⏳'; }
    else if (bonConseil) { borderColor = _kGreen;                  icone = '✅'; }
    else                 { borderColor = const Color(0xFFEF5350); icone = '❌'; }

    final d       = pr.datePronostic;
    final dateStr = '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
    final heureStr= '${d.hour.toString().padLeft(2,'0')}h${d.minute.toString().padLeft(2,'0')}';

    // Top N chevaux conseillés par l'IA (jusqu'à 5)
    final topIA = pr.topNIA;
    final nbAfficher = typePari == 'Quinté+' ? 5
        : typePari == 'Quarté+' ? 4
        : (typePari == 'Tiercé') ? 3
        : (typePari.contains('Couplé')) ? 2 : 1;
    final chevauxStr = topIA.take(nbAfficher).join(' - ');

    // Arrivée réelle PMU
    String arriveeStr = '';
    if (resolu && pr.arriveeReelle != null && pr.arriveeReelle!.isNotEmpty) {
      arriveeStr = pr.arriveeReelle!.take(nbAfficher + 2).join(' - ');
    }

    // Score confiance
    final conf = pr.confiancePredite;
    final confStr = conf != null ? '${conf.toStringAsFixed(0)} pts' : '—';

    // Rang favori + top3/top5
    String perf = '';
    if (resolu) {
      final rang = pr.rangFavoriIaDansArrivee;
      final top3 = pr.nbTop3DansArriveeReelle ?? 0;
      final top5 = pr.nbTop5DansArriveeReelle ?? 0;
      if (rang != null) {
        perf = rang == 1 ? '🥇 1er' : rang <= 3 ? '🏅 ${rang}e' : '${rang}e';
      }
      if (top3 > 0 || top5 > 0) perf += '  top3:$top3  top5:$top5';
    }

    // Ordre / Désordre
    String ordreLabel = '';
    if (resolu && bonConseil) {
      if (typePari == 'Tiercé' || typePari == 'Quarté+' || typePari == 'Quinté+') {
        final estOrdre = _verifierOrdreLocal(pr, typePari);
        if (estOrdre == true)       ordreLabel = '🎯 ORDRE';
        else if (estOrdre == false) ordreLabel = '🔀 DÉSORDRE';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: borderColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Ligne 1 : icone + nom course + date ───────────────────
          Row(children: [
            Text(icone, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(child: Text(pr.nomCourse,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis)),
            Text(dateStr, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ]),
          const SizedBox(height: 4),
          // ── Ligne 2 : hippodrome + heure + discipline ─────────────
          Row(children: [
            const SizedBox(width: 24),
            Text('📍 ${pr.hippodrome}  •  $heureStr  •  ${pr.discipline}',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ]),
          const SizedBox(height: 6),
          // ── Ligne 3 : chevaux conseillés IA ───────────────────────
          Row(children: [
            const SizedBox(width: 24),
            const Text('🤖 IA : ', style: TextStyle(color: Colors.white54, fontSize: 11)),
            Text(chevauxStr.isNotEmpty ? chevauxStr : '—',
                style: TextStyle(color: borderColor, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Text('($confStr)', style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ]),
          // ── Ligne 4 : arrivée réelle PMU (si résolu) ──────────────
          if (resolu && arriveeStr.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(children: [
              const SizedBox(width: 24),
              const Text('🏁 PMU : ', style: TextStyle(color: Colors.white54, fontSize: 11)),
              Text(arriveeStr,
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
            ]),
          ],
          // ── Ligne 5 : performance + ordre/désordre ─────────────────
          if (perf.isNotEmpty || ordreLabel.isNotEmpty) ...[
            const SizedBox(height: 5),
            Row(children: [
              const SizedBox(width: 24),
              if (perf.isNotEmpty)
                Text(perf, style: TextStyle(
                    color: bonConseil ? _kGreen : Colors.white38,
                    fontSize: 11, fontWeight: FontWeight.w600)),
              if (ordreLabel.isNotEmpty) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: (ordreLabel.contains('ORDRE') && !ordreLabel.contains('DES'))
                        ? const Color(0xFF66BB6A).withValues(alpha: 0.15)
                        : const Color(0xFFFFB74D).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: (ordreLabel.contains('ORDRE') && !ordreLabel.contains('DES'))
                          ? const Color(0xFF66BB6A).withValues(alpha: 0.5)
                          : const Color(0xFFFFB74D).withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(ordreLabel,
                      style: TextStyle(
                          color: (ordreLabel.contains('ORDRE') && !ordreLabel.contains('DES'))
                              ? const Color(0xFF66BB6A)
                              : const Color(0xFFFFB74D),
                          fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ]),
          ],
        ]),
      ),
    );
  }

  /// Vérifie ordre/désordre directement depuis IaPronostic (sans appel service)
  bool? _verifierOrdreLocal(IaPronostic pr, String typePari) {
    final arrivee = pr.arriveeReelle;
    if (arrivee == null || arrivee.isEmpty) return null;
    final topIA = pr.topNIA.map((e) => int.tryParse(e)).whereType<int>().toList();
    switch (typePari) {
      case 'Tiercé':
        if (topIA.length < 3 || arrivee.length < 3) return null;
        if (topIA[0]==arrivee[0] && topIA[1]==arrivee[1] && topIA[2]==arrivee[2]) return true;
        final ok = topIA.take(3).toSet().intersection(arrivee.take(3).toSet()).length >= 3;
        return ok ? false : null;
      case 'Quarté+':
        if (topIA.length < 4 || arrivee.length < 4) return null;
        if (topIA[0]==arrivee[0] && topIA[1]==arrivee[1] &&
            topIA[2]==arrivee[2] && topIA[3]==arrivee[3]) return true;
        final ok = topIA.take(4).toSet().intersection(arrivee.take(4).toSet()).length >= 3;
        return ok ? false : null;
      case 'Quinté+':
        // ✅ VERT si au moins 4 des 5 chevaux IA dans les 5 premiers (correction v10.13)
        if (topIA.length < 5 || arrivee.length < 5) return null;
        if (topIA[0]==arrivee[0] && topIA[1]==arrivee[1] && topIA[2]==arrivee[2] &&
            topIA[3]==arrivee[3] && topIA[4]==arrivee[4]) return true;
        final ok = topIA.take(5).toSet().intersection(arrivee.take(5).toSet()).length >= 4;
        return ok ? false : null;
      default: return null;
    }
  }

Widget _chipStat(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(label,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
      );

  /// ── v9.53 : ligne de détail utilisée dans le dialogue par type ──────────
  // _buildDetailRow supprimé en v9.55 : remplacé par _buildDetailRowIA
  // (source = IaPronostic au lieu de TrackedCourse — section Précision IA)

Widget _buildLignePrecisionParType(StatsPrecisionParType p, {required bool isLast, required Map<String,int> Function(StatsPrecisionParType) statsFiltre, required void Function(StatsPrecisionParType) afficherDetail}) {
    final double seuilBon;
    final double seuilMoyen;
    switch (p.typePari) {
      case 'Simple Gagnant':   seuilBon = 30; seuilMoyen = 20; break;
      case 'Gagnant+Placé':    seuilBon = 35; seuilMoyen = 25; break;
      case 'Simple Placé':     seuilBon = 50; seuilMoyen = 35; break;
      case 'Couplé Gagnant':   seuilBon = 35; seuilMoyen = 25; break;
      case 'Couplé Placé':     seuilBon = 45; seuilMoyen = 30; break;
      case 'Tiercé':           seuilBon = 40; seuilMoyen = 25; break;
      case 'Quarté+':          seuilBon = 35; seuilMoyen = 22; break;
      case 'Quinté+':          seuilBon = 30; seuilMoyen = 18; break;
      default:                  seuilBon = 40; seuilMoyen = 25;
    }

    // ── Stats selon le filtre actif ─────────────────────────────────────────
    final stats   = statsFiltre(p);
    final nb      = stats['nb']       ?? 0;
    final bons    = stats['bons']     ?? 0;
    final ordreF  = stats['ordre']    ?? 0;
    final desordF = stats['desordre'] ?? 0;

    final taux      = nb > 0 ? bons / nb * 100.0 : 0.0;
    final tauxColor = taux >= seuilBon   ? _kGreen
        : taux >= seuilMoyen ? const Color(0xFFFFB74D)
        : nb > 0 ? const Color(0xFFEF5350) : Colors.white24;

    final tendance = p.tendance7j;
    String tendTxt = '→';
    Color tendColor = Colors.white38;
    if (tendance != null) {
      if (tendance > 2)       { tendTxt = '↑'; tendColor = _kGreen; }
      else if (tendance < -2) { tendTxt = '↓'; tendColor = const Color(0xFFEF5350); }
    }

    final hasOrdreDesordre = (p.typePari == 'Tiercé' || p.typePari == 'Quarté+' || p.typePari == 'Quinté+')
        && (ordreF > 0 || desordF > 0);

    return Column(children: [
      GestureDetector(
        onTap: nb > 0 ? () => afficherDetail(p) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Ligne principale ─────────────────────────────────────────
              Row(children: [
                Text(p.emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(p.typePari,
                      // ★ v10.36 : 13→15
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                // Bons / Total selon filtre
                _cellStat('$bons/$nb',
                    bons > 0 ? _kGreen : Colors.white38,
                    width: 58, bold: bons > 0),
                const SizedBox(width: 6),
                // Taux
                SizedBox(
                  width: 46,
                  child: nb > 0
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                          decoration: BoxDecoration(
                            color: tauxColor.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: tauxColor.withValues(alpha: 0.4)),
                          ),
                          child: Text('${taux.toStringAsFixed(0)}%',
                              // ★ v10.36 : 12→14
                              style: TextStyle(color: tauxColor, fontSize: 14, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center),
                        )
                      : const SizedBox(),
                ),
                const SizedBox(width: 4),
                // Tendance 7j
                SizedBox(width: 20,
                    child: Text(tendTxt,
                        style: TextStyle(color: tendColor, fontSize: 15, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center)),
                if (nb > 0)
                  const Icon(Icons.chevron_right, color: Colors.white24, size: 16),
              ]),
              // ── Sous-ligne Ordre / Désordre ──────────────────────────────
              if (hasOrdreDesordre)
                Padding(
                  padding: const EdgeInsets.only(left: 22, top: 4, bottom: 2),
                  child: Row(children: [
                    _badgeOrdre('🎯 Ordre', ordreF, const Color(0xFF66BB6A)),
                    const SizedBox(width: 8),
                    _badgeOrdre('🔀 Désordre', desordF, const Color(0xFFFFB74D)),
                    const SizedBox(width: 8),
                    if (bons > 0)
                      Text(
                        '(${ordreF + desordF}/$bons classés)',
                        // ★ v10.36 : 10→12
                        style: const TextStyle(color: Colors.white24, fontSize: 12),
                      ),
                  ]),
                ),
            ],
          ),
        ),
      ),
      if (!isLast) const Divider(height: 1, color: Colors.white12, indent: 14, endIndent: 14),
    ]);
  }

Widget _cellStat(String txt, Color color, {double width = 40, bool bold = false}) =>
      SizedBox(
        width: width,
        child: Text(txt,
            style: TextStyle(color: color, fontSize: 13,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal),
            textAlign: TextAlign.center),
      );

Widget _badgeOrdre(String label, int count, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text('$label : $count',
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
      );
Widget _buildRapportJournalierComplet(RapportJournalier r) {
    final dateStr = '${r.date.day.toString().padLeft(2,'0')}/${r.date.month.toString().padLeft(2,'0')}/${r.date.year}';
    final noteColor = _couleurNote(r.noteJournee ?? '');

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [noteColor.withValues(alpha: 0.08), _kCard],
          begin: Alignment.topLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: noteColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── En-tête : date + note ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: noteColor.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              Icon(Icons.calendar_today_rounded, color: noteColor, size: 16),
              const SizedBox(width: 8),
              Text(dateStr,
                  style: TextStyle(color: noteColor, fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: noteColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: noteColor.withValues(alpha: 0.5)),
                ),
                child: Text(r.noteJournee ?? '—',
                    style: TextStyle(color: noteColor, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ]),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // ── Stats globales du jour ──────────────────────────────────────
              Row(children: [
                _buildTuile('${r.tauxGagnant.toStringAsFixed(0)}%',
                    'Favori\ngagnant', _kGold),
                const SizedBox(width: 8),
                _buildTuile('${r.tauxTop3.toStringAsFixed(0)}%',
                    'Favori\ntop 3', _kGreen),
                const SizedBox(width: 8),
                _buildTuile('${r.tauxTop5.toStringAsFixed(0)}%',
                    'Favori\ntop 5', _kPurple),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                _buildTuile('${r.nbAvecResultat}',
                    'Courses\nanalysées', const Color(0xFF42A5F5)),
                const SizedBox(width: 8),
                _buildTuile('${r.scoreMoyenJour.toStringAsFixed(0)}/100',
                    'Score IA\nmoyen', const Color(0xFFFF9800)),
                const SizedBox(width: 8),
                _buildTuile('${r.tauxTop3Correct.toStringAsFixed(0)}%',
                    '2/3 IA\ncorrects', Colors.teal),
              ]),

              // ── Jauge visuelle du taux gagnant ──────────────────────────────
              const SizedBox(height: 14),
              _buildJaugeAvecLabel(
                'Favori IA 🥇 gagnant',
                r.tauxGagnant / 100,
                _kGold,
                '${r.favoriGagnant}/${r.nbAvecResultat} courses',
              ),
              const SizedBox(height: 6),
              _buildJaugeAvecLabel(
                'Favori IA 🏆 dans le top 3',
                r.tauxTop3 / 100,
                _kGreen,
                '${r.favoriTop3}/${r.nbAvecResultat} courses',
              ),
              const SizedBox(height: 6),
              _buildJaugeAvecLabel(
                'Score IA moyen',
                r.scoreMoyenJour / 100,
                const Color(0xFFFF9800),
                '${r.scoreMoyenJour.toStringAsFixed(1)}/100',
              ),

              // ── Stats par discipline ────────────────────────────────────────
              if (r.parDiscipline.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Par discipline', style: TextStyle(
                    color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...r.parDiscipline.where((d) => d.nbCourses > 0).map(
                  (d) => _buildLigneDisicpline(d),
                ),
              ],

              // ── Poids appris aujourd'hui ─────────────────────────────────────
              if (r.poidsApres.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Divider(color: Colors.white12, height: 1),
                const SizedBox(height: 10),
                Row(children: [
                  const Icon(Icons.tune_rounded, color: Colors.white38, size: 14),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Poids IA après apprentissage (mise à jour n°${r.nbMisesAJourPoids})',
                      style: const TextStyle(color: Colors.white38, fontSize: 15))),
                ]),
                const SizedBox(height: 8),
                _buildPoidsMinimaux(r.poidsApres),
              ],

              // ── Message éventuel ─────────────────────────────────────────────
              if (r.nbCoursesEchouees > 0) ...[
                const SizedBox(height: 10),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.schedule, color: Colors.orange, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${r.nbCoursesEchouees} course(s) sans résultat officiel au moment de l\'analyse.\n'
                      'Normal si lancé en cours de journée — réanalysez après 20h30.',
                      style: const TextStyle(color: Colors.orange, fontSize: 14),
                    ),
                  ),
                ]),
              ],
              // Rapport "vide" : explication claire
              if (r.nbAvecResultat == 0 && r.nbCoursesAnalysees == 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                  ),
                  child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('💡', style: TextStyle(fontSize: 16)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'L\'API PMU ne publie pas encore les résultats officiels de la journée.\n'
                        'Relancez l\'analyse après 20h30 pour comparer les pronostics IA aux arrivées réelles et déclencher l\'apprentissage.',
                        style: TextStyle(color: Colors.white60, fontSize: 15),
                      ),
                    ),
                  ]),
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  // ── Widget : Historique des rapports (mini-cartes) ─────────────────────────

Widget _buildHistoriqueRapports(List<RapportJournalier> rapports) {
    return Column(
      children: rapports.map((r) => _buildMiniCarteRapport(r)).toList(),
    );
  }

Widget _buildMiniCarteRapport(RapportJournalier r) {
    final dateStr =
        '${r.date.day.toString().padLeft(2,'0')}/${r.date.month.toString().padLeft(2,'0')}';
    final noteColor = _couleurNote(r.noteJournee ?? '');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: noteColor.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        // Date
        SizedBox(
          width: 34,
          child: Text(dateStr,
              style: TextStyle(color: noteColor, fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
        ),
        const SizedBox(width: 10),
        // Mini jauges
        Expanded(
          child: Column(children: [
            _buildJaugeMini('Gagnant', r.tauxGagnant / 100, _kGold),
            const SizedBox(height: 3),
            _buildJaugeMini('Top 3  ', r.tauxTop3    / 100, _kGreen),
          ]),
        ),
        const SizedBox(width: 10),
        // Note + nb courses
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: noteColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              (r.noteJournee ?? '—').split(' ').first,
              style: TextStyle(color: noteColor, fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 3),
          Text('${r.nbAvecResultat} courses',
              style: const TextStyle(color: Colors.white24, fontSize: 15)),
        ]),
      ]),
    );
  }

  // ── Helpers visuels ─────────────────────────────────────────────────────────

  Color _couleurNote(String note) {
    if (note.contains('Excellente')) return const Color(0xFFFFD700);
    if (note.contains('Bonne'))      return const Color(0xFF4CAF7D);
    if (note.contains('Moyenne'))    return const Color(0xFFFFB74D);
    return const Color(0xFFEF5350);
  }

Widget _buildTuile(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(children: [
          Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 15),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }

Widget _buildJaugeAvecLabel(String label, double value, Color color, String detail) {
    // pct non utilisée directement dans ce widget (widthFactor utilise value)
    return Row(children: [
      SizedBox(
        width: 130,
        child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 15)),
      ),
      Expanded(
        child: Stack(children: [
          Container(height: 7, decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(4),
          )),
          FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(height: 7, decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            )),
          ),
        ]),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 58,
        child: Text(detail,
            style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold),
            textAlign: TextAlign.right),
      ),
    ]);
  }

Widget _buildJaugeMini(String label, double value, Color color) {
    return Row(children: [
      SizedBox(
        width: 44,
        child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 15)),
      ),
      Expanded(
        child: Stack(children: [
          Container(height: 5, decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(3),
          )),
          FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(height: 5, decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            )),
          ),
        ]),
      ),
      const SizedBox(width: 6),
      Text('${(value * 100).toStringAsFixed(0)}%',
          style: TextStyle(color: color, fontSize: 15)),
    ]);
  }

Widget _buildLigneDisicpline(StatsDisciplineJour d) {
    final emoji = d.discipline.contains('Trot Att') ? '🏇'
        : d.discipline.contains('Trot Mon') ? '🏇'
        : d.discipline.contains('Plat') ? '🐎'
        : '🚧';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 6),
        SizedBox(
          width: 90,
          child: Text(d.discipline.length > 12 ? '${d.discipline.substring(0,12)}…' : d.discipline,
              style: const TextStyle(color: Colors.white60, fontSize: 15)),
        ),
        const SizedBox(width: 6),
        Expanded(child: Stack(children: [
          Container(height: 6, decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(3),
          )),
          FractionallySizedBox(
            widthFactor: (d.tauxTop3 / 100).clamp(0.0, 1.0),
            child: Container(height: 6, decoration: BoxDecoration(
              color: _kGreen.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(3),
            )),
          ),
        ])),
        const SizedBox(width: 8),
        Text(
          '${d.tauxGagnant.toStringAsFixed(0)}% | top3: ${d.tauxTop3.toStringAsFixed(0)}%',
          style: const TextStyle(color: Colors.white38, fontSize: 15),
        ),
      ]),
    );
  }

Widget _buildPoidsMinimaux(Map<String, double> poids) {
    // ★ v5.0 : labels pour les 10 critères
    const labels = {
      'forme': 'Forme', 'gains': 'Gains', 'record': 'Record',
      'cote': 'Cote', 'constance': 'Régul.', 'victoires': 'Vict.',
      'discipline': 'Disc.', 'distSpec': 'Dist.', 'jockey': 'Jockey', 'repos': 'Repos',
    };
    final sorted = poids.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: sorted.map((e) {
        final pct = (e.value * 100).toStringAsFixed(0);
        final isHigh = e.value == sorted.first.value;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: isHigh ? _kGold.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: isHigh ? _kGold.withValues(alpha: 0.4) : Colors.white12),
          ),
          child: Text(
            '${labels[e.key] ?? e.key} $pct%',
            style: TextStyle(
              color: isHigh ? _kGold : Colors.white38,
              fontSize: 15,
              fontWeight: isHigh ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Widget : Statut de l'apprentissage ─────────────────────────────────────

Widget _buildStatutApprentissage(IaPoidsAdaptatifs poids, IaStats stats) {
    final misesAJour = poids.nbMisesAJour;
    final calibration = poids.calibrationScore;

    String statutText;
    Color statutColor;
    String statutEmoji;
    String conseil;

    if (misesAJour == 0) {
      statutText = 'En apprentissage';
      statutColor = Colors.white38;
      statutEmoji = '🌱';
      conseil = 'Suivez des courses pour que l\'IA commence à apprendre';
    } else if (misesAJour < 5) {
      statutText = 'Apprentissage débutant';
      statutColor = const Color(0xFFFFB74D);
      statutEmoji = '📈';
      conseil = 'L\'IA apprend encore — continuez à suivre des courses';
    } else if (misesAJour < 15) {
      statutText = 'En progression';
      statutColor = _kGreen;
      statutEmoji = '🧠';
      conseil = 'L\'IA commence à cerner les bons critères pour vos courses';
    } else {
      statutText = 'Bien entraîné';
      statutColor = _kGold;
      statutEmoji = '⭐';
      conseil = 'L\'IA a suffisamment de données pour des prédictions optimisées';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [statutColor.withValues(alpha: 0.12), _kCard],
          begin: Alignment.topLeft,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statutColor.withValues(alpha: 0.4)),
      ),
      child: Column(children: [
        Row(children: [
          Text(statutEmoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('IA : $statutText', style: TextStyle(color: statutColor, fontWeight: FontWeight.bold, fontSize: 16)),
              Text(conseil, style: const TextStyle(color: Colors.white54, fontSize: 16)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$misesAJour', style: TextStyle(color: statutColor, fontSize: 22, fontWeight: FontWeight.bold)),
            const Text('mises à jour', style: TextStyle(color: Colors.white38, fontSize: 15)),
          ]),
        ]),
        if (misesAJour > 0) ...[
          const SizedBox(height: 12),
          Row(children: [
            const Text('Calibration confiance :', style: TextStyle(color: Colors.white38, fontSize: 15)),
            const SizedBox(width: 8),
            Expanded(
              child: Stack(children: [
                Container(height: 6, decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(3),
                )),
                FractionallySizedBox(
                  widthFactor: (calibration / 100).clamp(0.0, 1.0),
                  child: Container(height: 6, decoration: BoxDecoration(
                    color: calibration > 60 ? _kGreen : calibration > 40 ? const Color(0xFFFFB74D) : Colors.red,
                    borderRadius: BorderRadius.circular(3),
                  )),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            Text('${calibration.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.white54, fontSize: 15)),
          ]),
          const SizedBox(height: 4),
          Text(
            calibration > 60
              ? '✅ L\'IA est bien calibrée : elle est plus précise quand elle est confiante'
              : calibration > 40
                ? '➖ Calibration neutre : la confiance de l\'IA est en cours d\'étalonnage'
                : '⚠️ Calibration faible : la confiance de l\'IA ne prédit pas encore sa précision',
            style: const TextStyle(color: Colors.white24, fontSize: 15),
          ),
        ],
      ]),
    );
  }

  // ── Widget : Poids par discipline ──────────────────────────────────────────

Widget _buildDisciplinePoidsCard(String discKey, IaPoidsAdaptatifs poids) {
    final poidsDisc = poids.poidsParDiscipline[discKey] ?? {};
    if (poidsDisc.isEmpty) return const SizedBox();

    final noms = {
      'trot_attele': '🏇 Trot Attelé',
      'trot_monte': '🏇 Trot Monté',
      'plat': '🐎 Plat',
      'obstacle': '🚧 Obstacle / Haies',
      'global': '🌐 Global',
    };

    final nomDisc = noms[discKey] ?? discKey;

    // Critère dominant pour cette discipline
    final critPrincipal = poidsDisc.entries.reduce((a, b) => a.value > b.value ? a : b);
    // ★ v5.0 : labels 10 critères
    final labels = {
      'forme': 'Forme', 'gains': 'Gains', 'record': 'Record',
      'cote': 'Cote', 'constance': 'Régularité', 'victoires': 'Victoires', 'discipline': 'Discipline',
      'distSpec': 'Dist. spécialisée', 'jockey': 'Jockey/Driver', 'repos': 'Fraîcheur',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kPurple.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(nomDisc, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _kPurple.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${labels[critPrincipal.key] ?? critPrincipal.key} dominant (${(critPrincipal.value * 100).toStringAsFixed(0)}%)',
              style: const TextStyle(color: _kPurple, fontSize: 15),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        _buildPoidsComparatifDisc('Forme',      poidsDisc['forme']     ?? 0.38, 0.38, _kGreen),
        _buildPoidsComparatifDisc('Cote',       poidsDisc['cote']      ?? 0.13, 0.13, const Color(0xFFFF9800)),
        _buildPoidsComparatifDisc('Gains',      poidsDisc['gains']     ?? 0.18, 0.18, _kGold),
        _buildPoidsComparatifDisc('Record',     poidsDisc['record']    ?? 0.14, 0.14, const Color(0xFF42A5F5)),
        _buildPoidsComparatifDisc('Régularité', poidsDisc['constance'] ?? 0.09, 0.09, const Color(0xFFCE93D8)),
      ]),
    );
  }

Widget _buildPoidsComparatifDisc(String label, double valeur, double defaut, Color color) {
    final diff = valeur - defaut;
    final isUp = diff > 0.005;
    final isDown = diff < -0.005;
    final pct = (valeur * 100).toStringAsFixed(0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(width: 80, child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 15))),
        Expanded(
          child: Stack(children: [
            Container(height: 10, decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(5),
            )),
            // Ligne de référence (défaut)
            FractionallySizedBox(
              widthFactor: (defaut / 0.55).clamp(0.0, 1.0),
              child: Container(height: 10, decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(5),
              )),
            ),
            // Valeur apprise
            FractionallySizedBox(
              widthFactor: (valeur / 0.55).clamp(0.0, 1.0),
              child: Container(height: 10, decoration: BoxDecoration(
                color: color.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(5),
              )),
            ),
          ]),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 50,
          child: Row(children: [
            Text('$pct%', style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold)),
            if (isUp) const Text(' ↑', style: TextStyle(color: Colors.greenAccent, fontSize: 16))
            else if (isDown) const Text(' ↓', style: TextStyle(color: Colors.redAccent, fontSize: 16)),
          ]),
        ),
      ]),
    );
  }

  // ── Widget : Journal d'apprentissage ───────────────────────────────────────

Widget _buildJournalCard(JournalEntree e) {
    final methode = e.methode ?? 'gradient';
    Color methodeColor;
    String methodeLabel;
    String methodeEmoji;

    switch (methode) {
      case 'gradient':
        methodeColor = _kGreen;
        methodeLabel = 'Gradient global';
        methodeEmoji = '🔬';
        break;
      case 'discipline_gradient':
        methodeColor = _kPurple;
        methodeLabel = e.discipline.isNotEmpty ? e.discipline : 'Discipline';
        methodeEmoji = '🏇';
        break;
      case 'regles':
        methodeColor = const Color(0xFFFF9800);
        methodeLabel = 'Règles basiques';
        methodeEmoji = '⚙️';
        break;
      default:
        methodeColor = Colors.white38;
        methodeLabel = methode;
        methodeEmoji = '🧠';
    }

    final scoreColor = e.scorePerf >= 60 ? _kGreen : e.scorePerf >= 35 ? const Color(0xFFFF9800) : Colors.redAccent;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: methodeColor.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(methodeEmoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.nomCourse, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: methodeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(methodeLabel, style: TextStyle(color: methodeColor, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 6),
                Text('${e.nbCoursesAnalysees} courses', style: const TextStyle(color: Colors.white24, fontSize: 15)),
              ]),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${e.scorePerf.toStringAsFixed(0)}/100', style: TextStyle(color: scoreColor, fontWeight: FontWeight.bold, fontSize: 15)),
            Text(_timeAgo(e.date), style: const TextStyle(color: Colors.white24, fontSize: 16)),
        ]),
        ]),
        const SizedBox(height: 8),
        // Deltas des poids
        _buildDeltasPoids(e.avant, e.apres),
        // Résumé du diagnostic (première ligne)
        const SizedBox(height: 6),
        Text(
          e.diagnostic.split('\n').firstWhere((l) => l.isNotEmpty, orElse: () => ''),
          style: const TextStyle(color: Colors.white38, fontSize: 15),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ]),
    );
  }

Widget _buildDeltasPoids(Map<String, double> avant, Map<String, double> apres) {
    final labels = {'forme': 'F', 'gains': 'G', 'record': 'R', 'cote': 'C', 'constance': 'Rg', 'victoires': 'V', 'discipline': 'D'};
    final deltas = <Widget>[];

    for (final key in ['forme', 'gains', 'record', 'cote', 'constance', 'victoires']) {
      final av = avant[key] ?? 0;
      final ap = apres[key] ?? av;
      final diff = ap - av;
      if (diff.abs() < 0.003) continue;

      final color = diff > 0 ? Colors.greenAccent : Colors.redAccent;
      final sign = diff > 0 ? '+' : '';
      deltas.add(Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          '${labels[key] ?? key}: $sign${(diff * 100).toStringAsFixed(1)}%',
          style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ));
    }

    if (deltas.isEmpty) {
      return const Text('Aucun changement significatif', style: TextStyle(color: Colors.white24, fontSize: 15));
    }

    return Wrap(children: deltas);
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours}h';
    if (diff.inDays < 7) return 'il y a ${diff.inDays}j';
    return '${date.day}/${date.month}';
  }

Widget _buildPoidsBar(String label, double valeur, double defaut, Color color) {
    final pct     = (valeur * 100).toStringAsFixed(0);
    final defautPct = (defaut * 100).toStringAsFixed(0);
    final diff    = valeur - defaut;
    final isUp    = diff > 0.005;
    final isDown  = diff < -0.005;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.white60, fontSize: 15))),
        Expanded(
          child: Stack(
            children: [
              // Barre fond
              Container(height: 14, decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(7),
              )),
              // Barre défaut (gris)
              FractionallySizedBox(
                widthFactor: defaut / 0.55,
                child: Container(height: 14, decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                )),
              ),
              // Barre actuelle
              FractionallySizedBox(
                widthFactor: (valeur / 0.55).clamp(0.0, 1.0),
                child: Container(height: 14, decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(7),
                )),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 52,
          child: Row(children: [
            Text('$pct%', style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold)),
            if (isUp) const Text(' ↑', style: TextStyle(color: Colors.greenAccent, fontSize: 15))
            else if (isDown) const Text(' ↓', style: TextStyle(color: Colors.redAccent, fontSize: 15))
            else Text(' =$defautPct%', style: TextStyle(color: Colors.white24, fontSize: 16)),
          ]),
        ),
      ]),
    );
  }

Widget _buildStatCard(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(children: [
          Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 15), textAlign: TextAlign.center),
        ]),
      ),
    );
  }

Widget _buildPronosticCard(IaPronostic p) {
    final topIA   = p.topNIA.take(5).toList();
    final arrivee = p.arriveeReelle?.take(5).toList() ?? [];
    final rang    = p.rangFavoriIaDansArrivee;
    final score   = p.scorePerformance ?? 0;

    Color scoreCol;
    String scoreEmoji;
    if (score >= 70)      { scoreCol = _kGreen; scoreEmoji = '🎯'; }
    else if (score >= 40) { scoreCol = const Color(0xFFFF9800); scoreEmoji = '👍'; }
    else                  { scoreCol = const Color(0xFFEF5350); scoreEmoji = '😔'; }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scoreCol.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('$scoreEmoji ', style: const TextStyle(fontSize: 16)),
          Expanded(
            child: Text(p.nomCourse, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: scoreCol.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('${score.toStringAsFixed(0)}/100', style: TextStyle(color: scoreCol, fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          // Pronostic IA
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('IA prédit :', style: TextStyle(color: Colors.white38, fontSize: 15)),
              Wrap(spacing: 4, children: topIA.asMap().entries.map((e) {
                final colors = [_kGold, _kGreen, const Color(0xFF42A5F5), const Color(0xFFFF9800), const Color(0xFFCE93D8)];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors[e.key % colors.length].withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: colors[e.key % colors.length].withValues(alpha: 0.4)),
                  ),
                  child: Text('N°${e.value}', style: TextStyle(color: colors[e.key % colors.length], fontSize: 15, fontWeight: FontWeight.bold)),
                );
              }).toList()),
            ]),
          ),
          const SizedBox(width: 8),
          // Arrivée réelle
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Arrivée réelle :', style: TextStyle(color: Colors.white38, fontSize: 15)),
              Wrap(spacing: 4, children: arrivee.asMap().entries.map((e) {
                final isIATop = topIA.take(5).contains(e.value.toString());
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: isIATop ? _kGreen.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: isIATop ? _kGreen.withValues(alpha: 0.5) : Colors.white12),
                  ),
                  child: Text('N°${e.value}', style: TextStyle(
                    color: isIATop ? _kGreen : Colors.white54,
                    fontSize: 15,
                    fontWeight: isIATop ? FontWeight.bold : FontWeight.normal,
                  )),
                );
              }).toList()),
            ]),
          ),
        ]),
        if (rang != null) ...[
          const SizedBox(height: 4),
          Text(
            rang == 1 ? '✅ Favori IA en 1ère place !' : rang <= 3 ? '👍 Favori IA en $rang ème place' : '😔 Favori IA en $rang e place',
            style: TextStyle(color: rang <= 3 ? _kGreen : Colors.white38, fontSize: 15),
          ),
        ],
      ]),
    );
  }

Widget _buildPronosticCardAttente(IaPronostic p) {
    final topIA = p.topNIA.take(5).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(children: [
        const Text('⏳', style: TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.nomCourse, style: const TextStyle(color: Colors.white70, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('IA : ${topIA.take(5).map((n) => "N°$n").join(" · ")}', style: const TextStyle(color: Colors.white38, fontSize: 15)),
          ]),
        ),
        const Text('En attente', style: TextStyle(color: Colors.white24, fontSize: 15)),
      ]),
    );
  }

  // ── Onglet 1 : Statistiques (ex onglet 0) ───────────────────────────────────


