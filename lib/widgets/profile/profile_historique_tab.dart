import 'package:flutter/material.dart';
import '../../providers/pmu_provider.dart';
import '../../models/pmu_models.dart';
import '../../services/alert_service.dart' show TrackedCourse;
import '../../utils/format_euros.dart';
import '../../utils/type_pari_utils.dart' show estEtatSansPariRecommande;
import '../../utils/validation_manuelle_ticket.dart';
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

  const ProfileHistoriqueTab({super.key, 
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

  const ProfileHistoriqueCard({super.key, required this.pred, required this.provider});

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
    // ★ LOT G+P / AFFICHAGE : un gain G+P non établi ne doit pas être
    //   présenté comme un montant. `gain` reste la valeur de la formule
    //   existante (inchangée) ; c'est ici que l'on décide de ne pas
    //   l'AFFICHER comme un gain confirmé.
    final bool gainAffiche = pred.gainGagnantPlaceEtabli;
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
              if (pred.montantMise > 0 || pred.miseTotaleEngagee != null) ...[
                Text(
                  isCorrect == null
                      ? 'Mise : ${fmtEuros(pred.montantMise)}€'
                      : !gainAffiche
                          ? 'Gain non établi (G+P)'
                          : '${gain >= 0 ? '+' : ''}${fmtEuros(gain)}€',
                  style: TextStyle(
                    color: isCorrect == null
                        ? Colors.white54
                        : !gainAffiche
                            ? const Color(0xFFFFB74D)
                            : gain >= 0
                                ? const Color(0xFF69F0AE)
                                : const Color(0xFFEF5350),
                    fontSize: gainAffiche ? 13 : 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                // Badge "PMU officiel" si dividende réel récupéré
                //   ★ G+P : le badge n'est pas affiché si le gain n'est pas
                //   établi — un dividende mono-combinaison ne vaut pas gain.
                if (pred.dividendeRecupere && isCorrect == true && gainAffiche)
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
            //   ★ LOT C2 : jamais proposé pour un ticket sans pari recommandé.
            //   Le dialogue porte sa propre garde (voir _validerDialog).
            if (isCorrect == null && !estEtatSansPariRecommande(pred.typePari))
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
    // ★ LOT C1/C2 — Deuxième des deux endroits qui inventaient une mise
    //   (`pred.montantMise > 0 ? … : 10.0`) avant d'appeler
    //   `validatePrediction`. Un ticket sans pari recommandé ne porte ni
    //   mise, ni gain, ni perte : on s'arrête AVANT tout calcul.
    //   Rien n'est écrit : le ticket reste tel quel, « En attente ».
    if (estEtatSansPariRecommande(pred.typePari)) {
      _afficherAucunPariRecommande(context);
      return;
    }

    // ★ LOT G+P — LA MISE N'EST PLUS INVENTÉE (même correction que
    //   `predictions_screen._validerDialog`).
    //
    //   Avant : `double mise = pred.montantMise > 0 ? pred.montantMise : 10.0;`
    //   Pour un Gagnant+Placé dont `montantMise` vaut 0, c'était 10 €
    //   inventés alors que le pari engage DEUX composantes déjà enregistrées.
    //
    //   La décision est prise par le module pur `validation_manuelle_ticket`,
    //   qui réutilise le calculateur B et la garde A-0. Si les deux
    //   composantes ne sont pas établies, on refuse sans fabriquer de montant.
    final decision = deciderValidationManuelle(pred);
    if (decision is! ValidationManuelleAutorisee) {
      _afficherValidationRefusee(
          context, (decision as ValidationManuelleRefusee).motif);
      return;
    }
    // `mise` reste mutable : le curseur la modifie pour un pari mono-
    // composante. Pour un Gagnant+Placé, les contrôles sont DÉSACTIVÉS
    // (voir plus bas) : les deux mises sont déjà enregistrées sur le ticket
    // et laisser l'utilisateur réécrire un total reviendrait à en inventer un.
    double mise = decision.miseTotale;
    final bool estDeuxComposantes = decision.deuxComposantes;
    final estCombine = pred.estPariCombine;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInnerState) {
          // Pour les simples → calcul via cote réelle PMU
          // Pour les combinés → gain saisi manuellement (dividende PMU réel)
          //
          // ★ LOT G+P — point 6 : plus AUCUNE valeur de repli inventée.
          //   Avant, `pred.cote <= 1.0` produisait `mise * 1.5`, un gain
          //   fabriqué de toutes pièces. On rend `null` : pas de cote réelle
          //   ⇒ pas de gain estimable, plutôt qu'un chiffre faux.
          //   Pour un Gagnant+Placé, aucun gain n'est affiché : la cote
          //   enregistrée est celle du Gagnant seul et ne permet pas de
          //   calculer les deux composantes (c'est exactement le motif A-0).
          final double? gainEstime = estCombine
              ? null // combiné : dividende PMU après la course
              : (estDeuxComposantes
                  ? null // G+P : deux composantes, gain non estimable ici
                  : (pred.cote > 1.0 ? (pred.cote * mise) - mise : null));

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
                    onTap: estDeuxComposantes
                        ? null // ★ G+P : mises déjà enregistrées, non modifiables
                        : () => setInnerState(() => mise = v),
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
                // ★ G+P : mises déjà enregistrées, non modifiables ici.
                onChanged: estDeuxComposantes
                    ? null
                    : (v) => setInnerState(() => mise = v.roundToDouble()),
              ),
              Text('Mise : ${mise.toStringAsFixed(0)} €',
                  style: const TextStyle(color: Color(0xFF4CAF7D), fontWeight: FontWeight.bold)),
              // ★ LOT G+P : un Gagnant+Placé engage DEUX composantes ; la mise
              //   affichée est leur SOMME réelle (10 + 10 = 20 €), jamais 10 €.
              if (estDeuxComposantes)
                Text(
                  'Gagnant + Placé : '
                  '${pred.miseGagnant!.toStringAsFixed(0)} € + '
                  '${pred.misePlace!.toStringAsFixed(0)} € = '
                  '${mise.toStringAsFixed(0)} € engagés',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 12),
              // Gain estimé — adapté selon type de pari
              if (!estCombine)
                Text(
                  // ★ LOT G+P : plus de valeur de repli inventée. Sans gain
                  //   réellement calculable, on l'annonce au lieu d'afficher
                  //   un chiffre fabriqué (`mise * 1.5` a été supprimé).
                  gainEstime != null
                      ? 'Gain estimé si gagnant : +${fmtEuros(gainEstime)} €'
                      : estDeuxComposantes
                          ? 'Gain Gagnant + Placé : non calculé ici '
                              '(deux composantes distinctes)'
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
                      // Pour les simples → calcul via cote réelle
                      // Pour les combinés/G+P sans dividende → marquer gagné,
                      //   le gain officiel sera récupéré après la course.
                      // ★ LOT G+P — point 6 : `gainRealise` reste `null` si
                      //   aucun gain n'est réellement calculable. On n'écrit
                      //   jamais un montant déduit d'un dividende ambigu.
                      //   Pour un Gagnant+Placé, on n'écrit AUCUN gain : même le
                      //   `dividendePmuReel` du ticket est écarté, car il a été
                      //   obtenu pour une seule combinaison et les deux
                      //   composantes G+P ne sont pas ventilées.
                      //
                      //   `montantMise` n'est PAS réécrit pour un G+P : il y
                      //   porte la mise PAR COMPOSANTE (contrat B2-A :
                      //   `miseTotaleEngagee == montantMise × 2`). Écrire la
                      //   somme (20 €) doublerait la mise affichée (40 €).
                      final double? gainFinal = estDeuxComposantes
                          ? null
                          : (pred.dividendeRecupere ? pred.gainNet : gainEstime);
                      provider.validatePrediction(pred.id,
                          isCorrect: true,
                          montantMise: estDeuxComposantes ? null : mise,
                          gainRealise: gainFinal);
                      Navigator.pop(ctx);
                      final String gainMsg = pred.dividendeRecupere && !estDeuxComposantes
                          ? '+${fmtEuros(pred.gainNet)} € (PMU officiel)'
                          : estDeuxComposantes
                              ? 'gain non calculé (deux composantes distinctes)'
                              : gainEstime != null
                                  ? '+${gainEstime.toStringAsFixed(2)} €'
                                  : 'gain calculé après la course';
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
                      // « Perdu » est un FAIT constaté : la perte écrite est la
                      // mise réellement engagée, y compris pour un G+P (A-0 ne
                      // neutralise que les gains G+P). `montantMise` n'est pas
                      // réécrit pour un G+P (il porte la mise par composante).
                      provider.validatePrediction(pred.id,
                          isCorrect: false,
                          montantMise: estDeuxComposantes ? null : mise,
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

  /// Motif affiché lorsque la validation financière est refusée faute de
  /// pouvoir établir la mise réellement engagée.
  ///
  /// ❗Aucun montant n'est affiché — il n'y a rien de connu à montrer.
  void _afficherValidationRefusee(BuildContext context, String motif) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1628),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.report_problem, color: Color(0xFFFFB74D)),
          SizedBox(width: 8),
          Expanded(
            child: Text('Validation impossible',
                style: TextStyle(color: Colors.white, fontSize: 15)),
          ),
        ]),
        content: Text(
          '$motif\n\n'
          'Renseignez la ou les mises réellement engagées pour pouvoir '
          'valider ce ticket. Rien n\'a été enregistré.',
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer', style: TextStyle(color: Colors.white38)),
          ),
        ],
      ),
    );
  }

  /// Motif affiché lorsqu'un ticket ne porte aucun pari recommandé.
  ///
  /// Aucune écriture financière n'est proposée : le ticket n'a jamais été un
  /// pari, il n'y a donc rien à valider. Message aligné sur
  /// `predictions_screen.dart` et sur le sens métier de
  /// `conseils_screen.dart:1284` (« passer »).
  void _afficherAucunPariRecommande(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1628),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.block, color: Color(0xFF78909C)),
          SizedBox(width: 8),
          Expanded(
            child: Text('Aucun pari recommandé',
                style: TextStyle(color: Colors.white, fontSize: 15)),
          ),
        ]),
        content: const Text(
          'Ce ticket ne correspond à aucun pari recommandé : l\'IA avait '
          'conseillé de passer cette course.\n\n'
          'Il ne peut donc porter ni mise, ni gain, ni perte. '
          'Aucun montant ne sera enregistré.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer', style: TextStyle(color: Colors.white38)),
          ),
        ],
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
      // ★ ÉTAPE 4-F : la carte partagée doit refléter le pari TEL QU'IL A ÉTÉ
      //   JOUÉ. Sans ces quatre lignes, un Tiercé Ordre partagé afficherait un
      //   pari dont la variante et l'ordre ont disparu — la carte serait alors
      //   plus pauvre que le ticket d'origine qu'elle prétend représenter.
      codePmuOfficiel: pred.codePmuOfficiel,
      varianteChoisie: pred.varianteChoisie,
      numerosDansOrdre: pred.numerosDansOrdre,
      formulePari: pred.formulePari,
      // ★ LOT B-1 : cette carte est construite depuis un `UserPrediction`, qui
      //   porte désormais les mêmes sept champs de gain. Les recopier évite
      //   qu'une carte de partage devienne, demain, plus pauvre que le ticket
      //   qu'elle prétend représenter — même raisonnement que pour la capture
      //   4-F juste au-dessus.
      //   ATTENTION, mesuré : le montant affiché par la carte ne vient PAS
      //   d'ici. Il est passé séparément en `gainTotal:` depuis
      //   `pred.gainNet`, sous la garde G+P `pred.gainGagnantPlaceEtabli`
      //   (voir la ligne `final gain = ...` juste après). Ces sept champs sont
      //   donc, en l'état, inertes pour l'affichage : ils ne créent aucune
      //   seconde source de vérité pour le montant.
      etatGain: pred.etatGain,
      rapportsAttribues: pred.rapportsAttribues,
      etatTirelire: pred.etatTirelire,
      dividendeGagnant: pred.dividendeGagnant,
      dividendePlace: pred.dividendePlace,
      miseBaseCentimesUtilisee: pred.miseBaseCentimesUtilisee,
      motifNonDetermination: pred.motifNonDetermination,
    );

    // ★ LOT G+P / AFFICHAGE : la carte partagée ne doit pas annoncer un gain
    //   G+P non établi comme un gain confirmé. Le résultat sportif
    //   (`estGagnant`) est conservé tel quel ; seul le montant est retiré.
    final gain =
        pred.isCorrect == true && pred.gainGagnantPlaceEtabli ? pred.gainNet : null;

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
  const ProfileSmallTag(this.label, this.color, {super.key});

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


