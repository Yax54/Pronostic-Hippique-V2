// ═══════════════════════════════════════════════════════════════════
//  ARRIVEE REELLE WIDGET — Affichage de l'arrivée officielle PMU
//  Réutilisable dans tous les écrans (Programme, Courses, Conseils,
//  Best Bet, Home, Détail course).
//
//  Logique v9.6 :
//   • Course à venir (pas encore terminée) → "Arrivée réelle : Course à venir"
//   • Course terminée sans résultat connu  → spinner + récupération auto API PMU
//   • Course terminée avec résultat        → badges N°X colorés
//     - Vert  : numéro était dans la sélection IA (top 5)
//     - Blanc : numéro absent de la sélection IA
//
//  ★ v9.6 : fetchArriveeDirecte() — récupération automatique même sans pari
//    Le widget est désormais StatefulWidget : il déclenche lui-même l'appel
//    API PMU si la course est terminée et que le résultat est absent du cache.
//    Plus besoin de passer par AlertService/_trackedCourses.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../services/ia_memory_service.dart';
import '../services/arrivee_officielle_service.dart'; // ★ L2-1 — lecture L0
import 'arrivee_officielle_groupes_widget.dart'; // ★ A6 — rendu ex æquo

/// Construit la courseKey au format utilisé par IaMemoryService :
/// "R{numReunion}C{numCourse}_{ddmmyyyy}"
String buildCourseKey({
  required String reunionCode,  // ex: "R1", "R2"
  required int numCourse,       // ex: 3
  required String dateStr,      // ex: "14042026"
}) {
  // reunionCode peut être "R1", "R2"... on extrait le numéro
  final numR = reunionCode.replaceAll(RegExp(r'[^0-9]'), '');
  return 'R${numR}C${numCourse}_$dateStr';
}

/// ★ L2-1 : d'où vient l'arrivée affichée.
enum _SourceArrivee {
  /// Groupes officiels complets lus dans L0 — ex æquo préservés.
  l0,
  /// Repli : pronostic IA historique, liste plate (comportement d'avant L2-1).
  historique,
}

/// Widget affichant l'arrivée réelle PMU.
///
/// [courseKey]       : clé unique de la course (ex: "R1C3_14042026")
/// [isTerminee]      : true si la course est passée (heure dépassée de >40 min)
/// [heureDepart]     : heure réelle de la course (pour appel API PMU direct)
/// [selectionIA]     : liste des numéros prédits par l'IA (pour colorer en vert)
/// [compact]         : si true, affichage horizontal compact (pour listes)
///                     si false, affichage bloc complet (pour détail course)
class ArriveReelleWidget extends StatefulWidget {
  final String courseKey;
  final bool isTerminee;
  final DateTime? heureDepart;
  final List<String> selectionIA;
  final bool compact;
  /// ★ v9.93 : true si grande course classique (Groupe 1/2, Poule, etc.)
  /// → afficher message explicatif quand PMU retourne seulement 3 arrivants
  final bool isClassiqueSansMultiple;
  /// ★ R1 : autorise (true, défaut) ou interdit (false) le déclenchement
  /// d'une récupération réseau depuis ce widget.
  /// À false, le widget reste purement passif : il affiche l'arrivée si elle
  /// est déjà connue, mais ne provoque ni appel API PMU, ni écriture,
  /// ni apprentissage. Utilisé par les écrans en consultation (calendrier).
  final bool autoriserRecuperation;
  /// ★ L2-1 : true = lire l'arrivée officielle complète dans L0
  /// (`ArriveeOfficielleService`), qui conserve les groupes d'ex æquo.
  ///
  /// Défaut `false` → les autres écrans gardent exactement le comportement
  /// d'avant L2-1 (repli sur `IaMemoryService.arriveeConnue`, liste plate).
  ///
  /// À `true`, l'ordre de lecture est : L0 d'abord ; si L0 ne possède pas
  /// l'arrivée, repli sur `IaMemoryService.arriveeConnue`. La provenance est
  /// signalée à l'utilisateur (« Officielle complète » / « Résultat
  /// historique ») pour qu'il ne confonde jamais les deux fidélités.
  final bool sourceL0;

  const ArriveReelleWidget({
    super.key,
    required this.courseKey,
    required this.isTerminee,
    this.heureDepart,
    this.selectionIA = const [],
    this.compact = true,
    this.isClassiqueSansMultiple = false, // ★ v9.93
    this.autoriserRecuperation = true, // ★ R1
    this.sourceL0 = false, // ★ L2-1
  });

  @override
  State<ArriveReelleWidget> createState() => _ArriveReelleWidgetState();
}

class _ArriveReelleWidgetState extends State<ArriveReelleWidget> {
  @override
  void initState() {
    super.initState();
    // ★ v9.6 : si la course est terminée et le résultat absent → fetch immédiat
    if (widget.isTerminee) {
      _fetchSiNecessaire();
    }
  }

  @override
  void didUpdateWidget(ArriveReelleWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Déclencher si le statut passe à "terminée"
    if (widget.isTerminee && !oldWidget.isTerminee) {
      _fetchSiNecessaire();
    }
  }

  void _fetchSiNecessaire() {
    // ★ R1 : mode consultation → aucune récupération réseau, aucune écriture,
    // aucun apprentissage. L'affichage des arrivées déjà connues est conservé
    // par build() qui lit arriveeConnue() sans effet de bord.
    if (!widget.autoriserRecuperation) return;
    final svc = IaMemoryService.instance;
    // Déjà en cache → rien à faire
    if (svc.arriveeConnue(widget.courseKey) != null) return;
    // Pas d'heure de départ → impossible d'appeler l'API
    if (widget.heureDepart == null) return;
    // Lancer la récupération en arrière-plan (pas d'await = non-bloquant)
    svc.fetchArriveeDirecte(
      courseKey: widget.courseKey,
      heureDepart: widget.heureDepart!,
    ).then((arrivee) {
      if (arrivee.isNotEmpty && mounted) setState(() {});
    });
  }

  /// ★ L2-1 : provenance de l'arrivée affichée.
  /// `l0` = groupes officiels complets (ex æquo préservés), `historique` =
  /// repli sur la liste plate de `IaMemoryService`.
  _SourceArrivee? _source;
  /// Groupes L0 quand la source est `l0`. JAMAIS aplatis pour l'affichage.
  List<List<int>>? _groupesL0;

  /// Lit l'arrivée selon [ArriveReelleWidget.sourceL0].
  ///
  /// L0 d'abord (aucun effet de bord : `arrivee()` lit la RAM et ne charge
  /// rien). Si L0 ne possède pas l'arrivée, repli sur le chemin historique.
  /// Aucune conversion des groupes L0 en liste plate n'est effectuée ici : le
  /// rendu groupé les consomme tels quels.
  List<int>? _resoudreArrivee() {
    _source = null;
    _groupesL0 = null;

    if (widget.sourceL0) {
      final groupes = ArriveeOfficielleService.instance.arrivee(widget.courseKey);
      if (groupes != null && groupes.isNotEmpty) {
        _groupesL0 = groupes;
        _source = _SourceArrivee.l0;
        // Projection PLATE utilisée UNIQUEMENT comme repli de rendu pour les
        // branches héritées (isClassiqueSansMultiple.length). Elle ne sert
        // JAMAIS à afficher les numéros quand _groupesL0 est disponible.
        return groupes.expand((g) => g).toList(growable: false);
      }
    }

    final historique = IaMemoryService.instance.arriveeConnue(widget.courseKey);
    if (historique != null && historique.isNotEmpty) {
      _source = _SourceArrivee.historique;
    }
    return historique;
  }

  @override
  Widget build(BuildContext context) {
    final arrivee = _resoudreArrivee();

    if (widget.compact) {
      return _buildCompact(arrivee);
    } else {
      return _buildFull(arrivee);
    }
  }

  // ── Mode compact : une ligne (utilisé dans Programme, Courses, Conseils, Home, Best Bet)
  Widget _buildCompact(List<int>? arrivee) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            '🏁',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(width: 6),
          const Text(
            'Arrivée réelle :',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _buildContenu(arrivee, fontSize: 12),
          ),
          // ★ B-2 bis : l'encadré « Ex æquo » n'est plus placé à côté du titre.
          //   La spécification le veut SOUS chaque cheval ex æquo, et sous lui
          //   seul : c'est `LigneArriveeExAequo._buildNumero` qui le rend.
          // ★ L2-1 : provenance affichée UNIQUEMENT quand sourceL0 est actif.
          // À false, rien n'est ajouté : rendu strictement identique à avant.
          if (widget.sourceL0 && _source != null && widget.isTerminee) ...[
            const SizedBox(width: 6),
            _buildBadgeSource(),
          ],
        ],
      ),
    );
  }

  // ── Mode complet : bloc (utilisé dans CourseDetailScreen)
  Widget _buildFull(List<int>? arrivee) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D2818).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (arrivee != null && arrivee.isNotEmpty)
              ? const Color(0xFF4CAF7D).withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🏁', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              const Text(
                'Arrivée réelle PMU',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              // ★ B-2 bis : l'encadré « Ex æquo » n'est plus placé ici ; il est
              //   rendu sous chaque cheval ex æquo par `LigneArriveeExAequo`.
              if (arrivee != null && arrivee.isNotEmpty) ...[
                const Spacer(),
                // ★ L2-1 : « Officielle complète » (L0) ou « Résultat
                // historique » (repli IA). À sourceL0=false, le libellé
                // reste « Officiel » — comportement inchangé.
                if (widget.sourceL0 && _source != null)
                  _buildBadgeSource()
                else
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF7D).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color:
                              const Color(0xFF4CAF7D).withValues(alpha: 0.4)),
                    ),
                    child: const Text(
                      'Officiel',
                      style: TextStyle(
                        color: Color(0xFF4CAF7D),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          _buildContenu(arrivee, fontSize: 14),
          if (arrivee != null && arrivee.isNotEmpty && widget.selectionIA.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '🟢 Vert = cheval prédit par l\'IA',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 11,
              ),
            ),
          ],
          // ★ v9.93 : message explicatif si grande course classique (PMU limite au Tiercé)
          if (widget.isClassiqueSansMultiple && arrivee != null && arrivee.length <= 3) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: const Row(children: [
                Icon(Icons.info_outline, color: Colors.orange, size: 13),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Grande course classique — Quarté/Quinté non disponibles sur PMU. '
                    'Résultat limité au Tiercé officiel.',
                    style: TextStyle(
                        color: Colors.orange,
                        fontSize: 10,
                        height: 1.4),
                  ),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  // ── Contenu commun : badges numéros ou texte d'état
  Widget _buildContenu(List<int>? arrivee, {required double fontSize}) {
    // ★ L2-1 : si les groupes L0 sont disponibles, ils sont la SEULE source
    // du rendu. On ne passe jamais par la liste plate.
    if (_groupesL0 != null && _groupesL0!.isNotEmpty && widget.isTerminee) {
      return _buildGroupesL0(fontSize: fontSize);
    }

    // Pas encore terminée
    if (!widget.isTerminee) {
      return Text(
        'Course à venir',
        style: TextStyle(
          color: Colors.white38,
          fontSize: fontSize,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    // Terminée mais pas encore de résultat
    if (arrivee == null || arrivee.isEmpty) {
      return Row(
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'En attente des résultats PMU...',
            style: TextStyle(
              color: Colors.white38,
              fontSize: fontSize,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
    }

    // Résultats disponibles → badges colorés
    final top5 = arrivee.take(5).toList();
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: top5.asMap().entries.map((e) {
        final position = e.key; // 0 = 1er, 1 = 2ème...
        final num = e.value;
        final isIA = widget.selectionIA.contains(num.toString());
        final isFirst = position == 0;

        Color borderColor;
        Color textColor;
        Color bgColor;

        if (isFirst) {
          // 1er : toujours doré
          borderColor = const Color(0xFFFFD700).withValues(alpha: 0.7);
          textColor = const Color(0xFFFFD700);
          bgColor = const Color(0xFFFFD700).withValues(alpha: 0.12);
        } else if (isIA) {
          // Dans la sélection IA → vert
          borderColor = const Color(0xFF4CAF7D).withValues(alpha: 0.6);
          textColor = const Color(0xFF4CAF7D);
          bgColor = const Color(0xFF4CAF7D).withValues(alpha: 0.12);
        } else {
          // Hors sélection IA → blanc discret
          borderColor = Colors.white.withValues(alpha: 0.2);
          textColor = Colors.white54;
          bgColor = Colors.white.withValues(alpha: 0.04);
        }

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: fontSize > 12 ? 7 : 5,
            vertical: fontSize > 12 ? 4 : 2,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: borderColor),
          ),
          child: Text(
            'N°$num',
            style: TextStyle(
              color: textColor,
              fontSize: fontSize,
              fontWeight: isFirst || isIA ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── ★ A6 : sélection du rendu groupé
  //
  //  DEUX rendus coexistent, et le choix est EXPLICITE :
  //
  //  (a) `arriveeAvecExAequo(_groupesL0)` est FAUX → `_buildGroupesL0Historique`,
  //      reproduction EXACTE du rendu d'avant A6. Aucun rang sous les
  //      numéros, aucun encadré « Ex æquo » : l'exigence « conserver
  //      strictement l'affichage actuel » est tenue au caractère près.
  //
  //  (b) au moins un groupe de 2 chevaux ou plus → `_buildGroupesL0`, qui
  //      délègue au widget partagé `LigneArriveeExAequo` : fond jaune doré
  //      et bordure assortie sur les SEULS chevaux ex æquo, rang officiel
  //      (« 2e », « 3e »…) sous chacun d'eux, positions sautées respectées.
  Widget _buildGroupesL0({required double fontSize}) {
    if (!arriveeAvecExAequo(_groupesL0)) {
      return _buildGroupesL0Historique(fontSize: fontSize);
    }
    return LigneArriveeExAequo(
      groupes: _groupesL0!,
      fontSize: fontSize,
      numerosIa: widget.selectionIA.toSet(),
    );
  }

  // ── Rendu HISTORIQUE (avant A6) — à l'identique
  //
  //  Conservé SANS modification pour toute arrivée sans ex æquo. Toute
  //  retouche ici changerait l'affichage de la grande majorité des courses,
  //  ce que la spécification interdit explicitement.
  Widget _buildGroupesL0Historique({required double fontSize}) {
    final groupes = _groupesL0!;
    final children = <Widget>[];

    // Rang cumulé : un groupe de k chevaux consomme k places.
    var rang = 1;
    for (var gi = 0; gi < groupes.length; gi++) {
      final groupe = groupes[gi];
      final plusieurs = groupe.length > 1;
      final estPremier = rang == 1;
      final estExAequo = plusieurs;

      // Couleur : or pour le 1er rang, ambre pour un ex æquo non premier,
      // vert si dans la sélection IA, blanc sinon.
      Color borderColor;
      Color textColor;
      Color bgColor;
      if (estPremier && !plusieurs) {
        borderColor = const Color(0xFFFFD700).withValues(alpha: 0.7);
        textColor = const Color(0xFFFFD700);
        bgColor = const Color(0xFFFFD700).withValues(alpha: 0.12);
      } else if (estExAequo) {
        borderColor = const Color(0xFFFFB74D).withValues(alpha: 0.85);
        textColor = const Color(0xFFFFB74D);
        bgColor = const Color(0xFFFFB74D).withValues(alpha: 0.16);
      } else if (groupe.any((n) => widget.selectionIA.contains(n.toString()))) {
        borderColor = const Color(0xFF4CAF7D).withValues(alpha: 0.6);
        textColor = const Color(0xFF4CAF7D);
        bgColor = const Color(0xFF4CAF7D).withValues(alpha: 0.12);
      } else {
        borderColor = Colors.white.withValues(alpha: 0.2);
        textColor = Colors.white54;
        bgColor = Colors.white.withValues(alpha: 0.04);
      }

      // Séparateur entre groupes.
      if (gi > 0) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            '·',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: fontSize,
            ),
          ),
        ));
      }

      for (var ni = 0; ni < groupe.length; ni++) {
        final num = groupe[ni];
        final isIA = widget.selectionIA.contains(num.toString());

        // « = » entre deux numéros du MÊME rang : marque l'ex æquo.
        if (ni > 0) {
          children.add(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              '=',
              style: TextStyle(
                color: const Color(0xFFFFB74D),
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          ));
        }

        children.add(Container(
          padding: EdgeInsets.symmetric(
            horizontal: fontSize > 12 ? 7 : 5,
            vertical: fontSize > 12 ? 4 : 2,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: borderColor),
          ),
          child: Text(
            'N°$num',
            style: TextStyle(
              color: textColor,
              fontSize: fontSize,
              fontWeight: (estPremier || estExAequo || isIA)
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),
        ));
      }

      rang += groupe.length;
    }

    return Wrap(spacing: 4, runSpacing: 4, children: children);
  }

  // ── ★ L2-1 : badge de provenance
  Widget _buildBadgeSource() {
    final l0 = _source == _SourceArrivee.l0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: (l0 ? const Color(0xFF4CAF7D) : const Color(0xFF64B5F6))
            .withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: (l0 ? const Color(0xFF4CAF7D) : const Color(0xFF64B5F6))
              .withValues(alpha: 0.45),
        ),
      ),
      child: Text(
        l0 ? 'Officielle complète' : 'Résultat historique',
        style: TextStyle(
          color: l0 ? const Color(0xFF4CAF7D) : const Color(0xFF64B5F6),
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
