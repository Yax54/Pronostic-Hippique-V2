// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER 2/3 — BLOC DE DÉCISION « GAIN OFFICIEL TARDIF »
// ═══════════════════════════════════════════════════════════════════════════
//
//  ★ CE QUE CE WIDGET FAIT
//
//  Il AFFICHE une décision en attente et PROPOSE les deux actions. Il ne
//  décide RIEN et n'écrit RIEN : les deux boutons appellent les chemins
//  sécurisés de `PmuProvider` (`accepterGainOfficiel` / `refuserGainOfficiel`),
//  et c'est l'ISSUE RÉELLE de ces appels qui pilote l'affichage.
//
//  ⚠️ UNE DÉCISION N'EST ANNONCÉE ENREGISTRÉE QUE SI `IssueEcritureGain.confirme`
//     EST RENVOYÉE. Tout autre cas affiche un message d'échec explicite et le
//     bloc RESTE affiché : la décision est reportée, jamais perdue.
//
//  ⚠️ FERMER UNE NOTIFICATION N'EST PAS UNE DÉCISION. Ce widget ne réagit
//     qu'à un appui explicite sur « Accepter » ou « Refuser ».
//
//  ⚠️ LES CINQ INFORMATIONS SONT AFFICHÉES SÉPARÉMENT, jamais fusionnées :
//     gain manuel · gain officiel · remboursement officiel · gain retenu ·
//     état de la décision. Additionner un remboursement au gain rendrait
//     l'intitulé « Gain gagné » faux — c'est l'arbitrage validé au chantier 1.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../providers/pmu_provider.dart';
import '../services/gains_tardifs_en_attente.dart';

/// Formatage en euros, identique au reste de l'application (jamais inventé).
String _euros(double? v) => v == null ? '—' : v.toStringAsFixed(2);

/// Couleurs du bloc, alignées sur l'or « gain » déjà utilisé ailleurs.
const Color _or = Color(0xFFFFD700);
const Color _bleu = Color(0xFF64B5F6);
const Color _rouge = Color(0xFFEF5350);

class BlocDecisionGainTardif extends StatefulWidget {
  /// La décision à présenter. Tous les montants sont des LECTURES du ticket.
  final DecisionEnAttente decision;

  /// Le provider — les deux boutons passent par SES chemins sécurisés.
  final PmuProvider provider;

  /// Appelé après une décision CONFIRMÉE, pour que l'écran hôte rafraîchisse
  /// ses statistiques. Jamais appelé sur un échec.
  final VoidCallback? onDecisionConfirmee;

  /// Mode compact, pour l'insertion dans une carte de liste.
  final bool compact;

  const BlocDecisionGainTardif({
    super.key,
    required this.decision,
    required this.provider,
    this.onDecisionConfirmee,
    this.compact = false,
  });

  @override
  State<BlocDecisionGainTardif> createState() => _BlocDecisionGainTardifState();
}

class _BlocDecisionGainTardifState extends State<BlocDecisionGainTardif> {
  /// Une écriture est en vol : les deux boutons sont désactivés, donc aucun
  /// double appui ne peut produire deux décisions concurrentes.
  bool _enCours = false;

  /// Message d'échec EXPLICITE. Tant qu'il est non nul, le bloc reste affiché.
  String? _erreur;

  Future<void> _decider({required bool accepter}) async {
    if (_enCours) return;
    setState(() {
      _enCours = true;
      _erreur = null;
    });

    final id = widget.decision.id;
    final IssueEcritureGain issue;
    try {
      issue = accepter
          ? await widget.provider.accepterGainOfficiel(id)
          : await widget.provider.refuserGainOfficiel(id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _erreur = 'La décision n\'a pas pu être enregistrée. '
            'Elle reste en attente et sera représentée.';
      });
      return;
    }

    if (!mounted) return;

    // ⚠️ SEUL `confirme` PROUVE QUE LE DISQUE PORTE LA DÉCISION.
    if (issue != IssueEcritureGain.confirme) {
      setState(() {
        _enCours = false;
        _erreur = switch (issue) {
          IssueEcritureGain.remplacee =>
            'Une autre opération a été enregistrée entre-temps. '
                'La décision reste en attente.',
          IssueEcritureGain.echec =>
            'Enregistrement impossible. La décision reste en attente.',
          IssueEcritureGain.echecNonReconcilie =>
            'Enregistrement impossible et cohérence non rétablie. '
                'La décision reste en attente.',
          IssueEcritureGain.confirme => null,
        };
      });
      return;
    }

    setState(() => _enCours = false);
    widget.onDecisionConfirmee?.call();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.decision;
    return Container(
      margin: widget.compact
          ? const EdgeInsets.only(top: 8)
          : const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _or.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _or.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.emoji_events, color: _or, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Décision requise — gain officiel disponible',
                style: const TextStyle(
                  color: _or,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
          const SizedBox(height: 8),

          // ── LES CINQ INFORMATIONS, CHACUNE SUR SA LIGNE ────────────────
          _ligne('Gain déclaré', '${_euros(d.gainManuel)} €', Colors.white70),
          _ligne('Gain officiel PMU', '${_euros(d.gainOfficiel)} €', Colors.white),
          if (d.remboursement != null && d.remboursement! > 0)
            _ligne('Remboursement officiel',
                '${_euros(d.remboursement)} €', _bleu),
          _ligne(
            'Gain gagné actuellement retenu',
            '${_euros(d.gainRetenu)} €',
            _or,
            gras: true,
          ),
          _ligne('État', 'Décision en attente', Colors.orangeAccent),

          const SizedBox(height: 6),
          const Text(
            'Votre gain déclaré reste retenu tant que vous n\'avez pas décidé.',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),

          // ── LES DEUX ACTIONS ─────────────────────────────────────────
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _enCours ? null : () => _decider(accepter: true),
                icon: _enCours
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check, size: 16),
                label: const Text('Accepter', style: TextStyle(fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _or.withValues(alpha: 0.18),
                  foregroundColor: _or,
                  side: BorderSide(color: _or.withValues(alpha: 0.6)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _enCours ? null : () => _decider(accepter: false),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Refuser', style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _rouge,
                  side: BorderSide(color: _rouge.withValues(alpha: 0.6)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ]),

          if (_erreur != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.warning_amber, color: _rouge, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _erreur!,
                  style: const TextStyle(color: _rouge, fontSize: 11),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _ligne(String libelle, String valeur, Color couleur,
      {bool gras = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              libelle,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Text(
            valeur,
            style: TextStyle(
              color: couleur,
              fontSize: 12,
              fontWeight: gras ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
