import 'package:flutter/material.dart';
import '../../services/alert_service.dart';
import '../../services/ia_memory_models.dart'; // ★ BL2-A09 : IaStats (mesures réelles)
import '../../services/ia_memory_service.dart'; // ★ v10.24 : precisionParHippodromeAvecFiabilite
import '../../utils/format_euros.dart';
import 'ia_widgets_communs.dart';
import 'ia_performance_dialogs.dart'; // IaCircleGaugePainter

// ══════════════════════════════════════════════════════════════════════════════
//  IaTabStats — Onglet "Statistiques" de IaPerformanceScreen
//  Extrait lors du découpage v9.90.
//  Reçoit alertService en paramètre pour afficher les paris suivis.
//
//  ★ CORRECTION BLOC 2 (BL2-A09 / BL2-A10 / BL2-A13) — STATISTIQUES FABRIQUÉES
//  ════════════════════════════════════════════════════════════════════════════
//  DÉFAUT MESURÉ AVANT CORRECTION (lecture intégrale du fichier, 474 lignes) :
//    • `_statsDiscipline` (4 lignes en dur) affichait, IDENTIQUEMENT pour tous
//      les utilisateurs : tauxTop3 73.2 / 68.5 / 70.8 / 65.3 et tauxGagnant
//      34.1 / 30.2 / 33.5 / 28.7 ;
//    • `_buildTypesPariStats()` affichait 4 taux en dur 32.8 / 71.4 / 84.2 /
//      38.4, dont le 71.4 était sous-titré « Simple placé sur le N°1 IA »
//      alors que son libellé était « Favori IA Top 3 » ;
//    • `_buildVsAleatoireCard()` comparait une base « Aléatoire » = 25.0 à
//      « IA » = 71.4 et en tirait la phrase
//      « L'IA améliore vos chances de +43% par rapport à une sélection au
//      hasard ». Une base aléatoire de 25 % n'est justifiable pour AUCUN
//      nombre de partants : pour un champ de n partants, l'espérance d'un
//      tirage uniforme au TOP1 vaut 1/n (≈ 6,7 % à 15 partants), au TOP3
//      ≈ 3/n (20 %), au TOP5 ≈ 5/n (33 %). Le « 25 % » ne correspond à aucun
//      de ces trois cas et ne dépend d'aucune donnée. Le « +43 % » est donc
//      une affirmation arithmétiquement infondée, retirée.
//
//  CE QUI EST DÉSORMAIS AFFICHÉ — uniquement des mesures, jamais des constantes
//  ──────────────────────────────────────────────────────────────────────────
//  1. `IaMemoryService.instance.calculerStats()` → `tauxFavoriGagnant`
//     (rang==1), `tauxFavoriTop3` (rang<=3), `tauxFavoriTop5` (rang<=5),
//     tous sur le dénominateur COMMUN `coursesAvecResultat`. Chaque ligne porte
//     son libellé exact : TOP1 ≠ TOP3 ≠ TOP5 (exigence BL2-A14 : « un TOP3 ne
//     doit pas être présenté comme un taux Gagnant »).
//  2. `IaMemoryService.instance.precisionParType` → `StatsPrecisionParType`
//     (`nbBons / nbTotal`), c'est-à-dire la réussite du PARI CONSEILLÉ selon
//     sa règle propre (`_estBonConseilParType`). Libellé distinct de (1) :
//     « pari conseillé » n'est pas « favori gagnant » — deux objectifs métier
//     réels, jamais fusionnés.
//  3. Par discipline : `IaStats.tauxParDiscipline`, dont le prédicat mesuré est
//     `rang <= 3` (`ia_memory_service.dart:4571`). Affiché sous le libellé
//     « Top 3 » et JAMAIS sous « Gagnant » : c'était exactement le défaut (2)
//     de BL2-A14. Le dénominateur `parDiscipline[disc]` est affiché (n).
//
//  CE QUI A ÉTÉ SUPPRIMÉ — aucune estimation de remplacement
//  ─────────────────────────────────────────────────────────
//  • Les 4 lignes `_statsDiscipline` (fabriquées) ;
//  • les 4 taux de `_buildTypesPariStats` (fabriqués) ;
//  • la carte « IA vs Stratégie aléatoire » ENTIÈRE : sa base de comparaison
//    n'était pas justifiable, et le mandat impose de la retirer plutôt que de
//    la remplacer par une autre estimation arbitraire ;
//  • la mention « estimations théoriques » du bandeau de bas de page, qui
//    décrivait faussement des constantes comme des estimations calculées.
//    Elle est remplacée par une description EXACTE de ce qui est mesuré.
//
//  ABSENCE DE DONNÉES : chaque section affiche un état vide explicite
//  (« aucune course avec résultat ») au lieu d'un 0 % ou d'un chiffre d'apparat.
//  Un 0 % serait un résultat mesuré ; une absence n'en est pas un.
// ══════════════════════════════════════════════════════════════════════════════

class IaTabStats extends StatelessWidget {
  final AlertService alertService;

  const IaTabStats({super.key, required this.alertService});

  static const _card   = Color(0xFF111F30);
  static const _gold   = Color(0xFFFFD700);

  /// Seuil SOUS LEQUEL un échantillon n'est pas présenté comme un taux.
  /// Valeur DÉCLARÉE et non métier : elle sert uniquement à décider d'un
  /// affichage (« échantillon insuffisant »), jamais d'un calcul, d'une
  /// décision de pari, d'un poids ou d'un seuil IA.
  static const int _minEchantillonAffiche = 5;

  @override
  Widget build(BuildContext context) {
    final stats = IaMemoryService.instance.calculerStats();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        iaSectionTitle('📈 Précision du favori IA — TOP 1 / TOP 3 / TOP 5'),
        const SizedBox(height: 10),
        _buildTypesPariStats(stats),
        const SizedBox(height: 18),

        iaSectionTitle('🏇 Performance par discipline (TOP 3)'),
        const SizedBox(height: 10),
        _buildDisciplines(stats),
        const SizedBox(height: 18),

        // ★ v10.24 : Feature #3 — Taux réussite par hippodrome (données réelles IA)
        iaSectionTitle('🌆 Performance par hippodrome (TOP 1)'),
        const SizedBox(height: 10),
        _buildHippodromeStats(),
        const SizedBox(height: 18),

        iaSectionTitle('💰 Vos paris suivis'),
        const SizedBox(height: 10),
        _buildMesParis(),
        const SizedBox(height: 18),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
          ),
          // ★ BL2-A09 — le texte précédent disait « estimations théoriques
          //   basées sur l'algorithme IA ». C'était faux deux fois : les
          //   chiffres n'étaient pas des estimations, et ils ne dépendaient
          //   pas de l'algorithme. Le texte décrit maintenant la source réelle.
          child: const Text(
            '⚠️ Ces taux sont calculés sur VOS courses terminées, à partir des '
            'résultats officiels enregistrés. « TOP 1 / TOP 3 / TOP 5 » désigne '
            'le rang d\'arrivée du cheval classé n°1 par l\'IA. Les performances '
            'passées ne garantissent pas les résultats futurs. Pariez de façon '
            'responsable.',
            style: TextStyle(color: Colors.white38, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  // ── Bloc 1 : précision du favori IA (3 rangs distincts) ──────────────────
  Widget _buildTypesPariStats(IaStats stats) {
    final n = stats.coursesAvecResultat;

    if (n == 0) {
      return _etatVide(
        icone: Icons.bar_chart,
        titre: 'Aucune course terminée',
        detail: 'Ces taux apparaîtront dès qu\'une course aura un résultat '
            'officiel enregistré.',
      );
    }

    // Chaque valeur vient d'IaStats, même dénominateur `coursesAvecResultat`.
    // Libellés volontairement explicites : sinon un TOP3 passerait pour un
    // taux de victoire (BL2-A14).
    final lignes = <Map<String, Object>>[
      {
        'nom': 'Favori IA gagnant',
        'desc': 'Le n°1 IA termine 1er — TOP 1',
        'taux': stats.tauxFavoriGagnant,
        'compte': stats.favoriGagnant,
        'color': 0xFF4CAF7D,
        'emoji': '🏆',
      },
      {
        'nom': 'Favori IA dans le top 3',
        'desc': 'Le n°1 IA termine dans les 3 premiers — TOP 3',
        'taux': stats.tauxFavoriTop3,
        'compte': stats.favoriTop3,
        'color': 0xFFFFD700,
        'emoji': '🥇',
      },
      {
        'nom': 'Favori IA dans le top 5',
        'desc': 'Le n°1 IA termine dans les 5 premiers — TOP 5',
        'taux': stats.tauxFavoriTop5,
        'compte': stats.favoriTop5,
        'color': 0xFF42A5F5,
        'emoji': '🎯',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final l in lignes) _ligneTaux(l, n),
        _buildPrecisionParPariConseille(),
      ],
    );
  }

  Widget _ligneTaux(Map<String, Object> t, int denominateur) {
    final taux  = t['taux'] as double;
    final color = Color(t['color'] as int);
    final compte = t['compte'] as int;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(t['emoji'] as String, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t['nom'] as String,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                  Text(t['desc'] as String,
                      style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${taux.toStringAsFixed(1)}%',
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 20)),
                // Le dénominateur est affiché : sans lui, un 100 % sur
                // 1 course et un 34 % sur 300 courses sont indistinguables.
                Text('$compte / $denominateur',
                    style: const TextStyle(color: Colors.white30, fontSize: 11)),
              ],
            ),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (taux / 100).clamp(0.0, 1.0),
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  // ── Bloc 2 : réussite du PARI CONSEILLÉ, par type ────────────────────────
  //
  // Source : `precisionParType` → `StatsPrecisionParType.tauxReussite`
  // = `nbBons / nbTotal`, où « bon » est décidé par `_estBonConseilParType`
  // (règle propre à chaque type : ordre/désordre pour Tiercé+, etc.).
  // Cette grandeur est DIFFÉRENTE de la précision du favori top 1/3/5
  // ci-dessus : c'est pourquoi elle porte un titre et un libellé distincts.
  Widget _buildPrecisionParPariConseille() {
    final types = IaMemoryService.instance.precisionParType
        .where((t) => t.nbTotal > 0)
        .toList();

    if (types.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 4),
        child: Text(
          'Réussite du pari conseillé : aucune donnée par type de pari pour '
          'l\'instant.',
          style: TextStyle(color: Colors.white30, fontSize: 12),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Réussite du pari conseillé (par type)',
              style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
          const SizedBox(height: 2),
          const Text(
            'Un « bon conseil » dépend de la règle du type (ex. Tiercé en '
            'ordre ou désordre). Ce n\'est pas la précision du favori ci-dessus.',
            style: TextStyle(color: Colors.white30, fontSize: 11),
          ),
          const SizedBox(height: 8),
          for (final t in types) _ligneTypePari(t),
        ],
      ),
    );
  }

  Widget _ligneTypePari(StatsPrecisionParType t) {
    final fiable = t.nbTotal >= _minEchantillonAffiche;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Text(t.emoji, style: const TextStyle(fontSize: 15)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(t.typePari,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              overflow: TextOverflow.ellipsis),
        ),
        Text('${t.nbBons}/${t.nbTotal}',
            style: const TextStyle(color: Colors.white30, fontSize: 11)),
        const SizedBox(width: 8),
        // Un taux sur 2 courses n'est pas un taux : on affiche l'absence
        // d'échantillon suffisant plutôt qu'un pourcentage trompeur.
        if (!fiable)
          const Text('échantillon insuffisant',
              style: TextStyle(color: Colors.white24, fontSize: 11))
        else
          Text('${t.tauxReussite.toStringAsFixed(1)}%',
              style: const TextStyle(
                  color: Color(0xFF4CAF7D),
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
      ]),
    );
  }

  // ── Bloc 3 : par discipline — TOP 3, jamais « Gagnant » ──────────────────
  Widget _buildDisciplines(IaStats stats) {
    if (stats.tauxParDiscipline.isEmpty) {
      return _etatVide(
        icone: Icons.pets,
        titre: 'Aucune donnée par discipline',
        detail: 'Les taux s\'alimentent dès qu\'une course est résolue.',
      );
    }

    final entrees = stats.tauxParDiscipline.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      children: entrees.map((e) {
        final disc = e.key;
        final taux = e.value;
        final nb   = stats.parDiscipline[disc] ?? 0;
        final fiable = nb >= _minEchantillonAffiche;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: fiable
                  ? const Color(0xFF4CAF7D).withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Row(children: [
            const Text('🐎', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(disc,
                      style: TextStyle(
                          color: fiable ? Colors.white : Colors.white60,
                          fontWeight:
                              fiable ? FontWeight.bold : FontWeight.normal,
                          fontSize: 15),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  // ★ BL2-A14 — le prédicat mesuré de `tauxParDiscipline` est
                  //   `rang <= 3` : le libellé dit « Top 3 », jamais « Gagnant ».
                  Row(children: [
                    _miniStat('Top 3', '${taux.toStringAsFixed(0)}%',
                        const Color(0xFF4CAF7D)),
                    const SizedBox(width: 8),
                    _miniStat('$nb courses', fiable ? 'fiable' : 'partiel',
                        fiable ? const Color(0xFF4CAF7D) : Colors.white38),
                  ]),
                ],
              ),
            ),
            SizedBox(
              width: 50,
              height: 50,
              child: CustomPaint(
                painter: IaCircleGaugePainter(
                    (taux / 100).clamp(0.0, 1.0), const Color(0xFF4CAF7D)),
                child: Center(
                  child: Text('${taux.toStringAsFixed(0)}%',
                      style: const TextStyle(
                          color: Color(0xFF4CAF7D),
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ]),
        );
      }).toList(),
    );
  }

  Widget _etatVide({
    required IconData icone,
    required String titre,
    required String detail,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icone, color: Colors.white24, size: 36),
          const SizedBox(height: 8),
          Text(titre,
              style: const TextStyle(color: Colors.white38, fontSize: 14)),
          const SizedBox(height: 4),
          Text(detail,
              style: const TextStyle(color: Colors.white24, fontSize: 12),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(width: 4),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  // ★ v10.24 : Feature #3 — Taux réussite par hippodrome
  Widget _buildHippodromeStats() {
    final data = IaMemoryService.instance.precisionParHippodromeAvecFiabilite;

    if (data.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          children: [
            Icon(Icons.bar_chart, color: Colors.white24, size: 36),
            SizedBox(height: 8),
            Text('Aucune donnée d’hippodrome disponible',
                style: TextStyle(color: Colors.white38, fontSize: 14)),
            SizedBox(height: 4),
            Text('Les stats s’alimentent après chaque analyse de journée',
                style: TextStyle(color: Colors.white24, fontSize: 12),
                textAlign: TextAlign.center),
          ],
        ),
      );
    }

    // Trier par taux décroissant, puis par nb de courses décroissant
    final sorted = data.entries.toList()
      ..sort((a, b) {
        final tA = (a.value['taux'] as double);
        final tB = (b.value['taux'] as double);
        if ((tA - tB).abs() > 0.01) return tB.compareTo(tA);
        return (b.value['nb'] as int).compareTo(a.value['nb'] as int);
      });

    // Limiter à 12 hippodromes max pour ne pas écraser la UI
    final displayed = sorted.take(12).toList();
    final maxTaux   = displayed.isEmpty ? 1.0
        : (displayed.first.value['taux'] as double).clamp(0.01, 1.0);

    return Column(
      children: [
        // Légende
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              _miniStat('Fiable', '≥ 5 courses', const Color(0xFF4CAF7D)),
              const SizedBox(width: 8),
              _miniStat('En cours', '< 5 courses', Colors.white38),
            ],
          ),
        ),
        ...displayed.map((e) {
          final hippodrome = e.key;
          final taux   = (e.value['taux'] as double);
          final nb     = e.value['nb'] as int;
          final fiable = e.value['fiable'] as bool;
          final tauxPct = (taux * 100).round();
          final barFill = maxTaux > 0 ? taux / maxTaux : 0.0;

          // Couleur progressive : rouge < 25%, orange < 40%, vert ≥ 40%
          final Color barColor;
          if (tauxPct >= 40) {
            barColor = const Color(0xFF4CAF7D);
          } else if (tauxPct >= 25) {
            barColor = const Color(0xFFFFB74D);
          } else {
            barColor = const Color(0xFFEF5350);
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: fiable
                    ? barColor.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.06),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Row(children: [
                      const Text('🌆', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          hippodrome,
                          style: TextStyle(
                            color: fiable ? Colors.white : Colors.white60,
                            fontWeight: fiable
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!fiable)
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('échantillon',
                              style: TextStyle(
                                  color: Colors.white30, fontSize: 11)),
                        ),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Text('$tauxPct%',
                      style: TextStyle(
                          color: barColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                  const SizedBox(width: 6),
                  Text('($nb)',
                      style: const TextStyle(
                          color: Colors.white30, fontSize: 11)),
                ]),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: barFill.clamp(0.0, 1.0),
                    backgroundColor: Colors.white.withValues(alpha: 0.07),
                    valueColor: AlwaysStoppedAnimation<Color>(barColor),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          );
        }),
        if (sorted.length > 12)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '+ ${sorted.length - 12} autres hippodromes',
              style: const TextStyle(color: Colors.white30, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  Widget _buildMesParis() {
    final paris = alertService.trackedCourses;
    if (paris.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: _card, borderRadius: BorderRadius.circular(12)),
        child: const Column(
          children: [
            Icon(Icons.inbox, color: Colors.white24, size: 40),
            SizedBox(height: 8),
            Text('Aucun pari suivi pour l\'instant',
                style: TextStyle(color: Colors.white38, fontSize: 14)),
            SizedBox(height: 4),
            Text('Placez un pari depuis l\'onglet Courses',
                style: TextStyle(color: Colors.white24, fontSize: 12)),
          ],
        ),
      );
    }

    return Column(
      children: paris.entries.take(5).map((entry) {
        final tc = entry.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: const Color(0xFF4CAF7D).withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D52).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('💰', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tc.nomCourse,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(
                      'N°${tc.numeroCheval ?? '?'} ${tc.nomCheval} — ${tc.hippodrome}',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            Text(
                '${tc.miseEngagee != null ? fmtEuros(tc.miseEngagee!) : '?'} €',
                style: const TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
          ]),
        );
      }).toList(),
    );
  }
}
