// ═══════════════════════════════════════════════════════════════════════════
//  IA NARRATIVE TEMPLATES — v10.66
//  Templates avec ID pour l'anti-répétition.
//  Règles UX : max 2 phrases, ton analytique, jamais "je ressens/pense".
//  {pseudo}     → pseudo utilisateur
//  {discipline} → meilleure discipline IA
//  {widget}     → widget premium le plus stable
//  {typePari}   → ★ v10.66 : type de pari le plus stable
// ═══════════════════════════════════════════════════════════════════════════

class IaNarrativeTemplate {
  final String id;
  final String text;

  const IaNarrativeTemplate({required this.id, required this.text});
}

class IaNarrativeTemplates {
  // ── Progression : aujourd'hui > hier ──────────────────────────────────────
  static const List<IaNarrativeTemplate> progressionJour = [
    IaNarrativeTemplate(
      id: 'progression_1',
      text: '{pseudo}, les résultats progressent par rapport à hier.',
    ),
    IaNarrativeTemplate(
      id: 'progression_2',
      text: 'Belle amélioration aujourd\'hui, {pseudo} — les sélections sont plus précises qu\'hier.',
    ),
    IaNarrativeTemplate(
      id: 'progression_3',
      text: '{pseudo}, la journée est en hausse : les indicateurs s\'améliorent.',
    ),
    IaNarrativeTemplate(
      id: 'progression_4',
      text: 'Les performances sont en progression aujourd\'hui, {pseudo}.',
    ),
    IaNarrativeTemplate(
      id: 'progression_5',
      text: '{pseudo}, les critères ont mieux ciblé aujourd\'hui qu\'hier.',
    ),
  ];

  // ── Régression : aujourd'hui < hier ──────────────────────────────────────
  static const List<IaNarrativeTemplate> regressionJour = [
    IaNarrativeTemplate(
      id: 'regression_1',
      text: '{pseudo}, la journée est plus difficile qu\'hier.',
    ),
    IaNarrativeTemplate(
      id: 'regression_2',
      text: 'Les résultats sont en retrait aujourd\'hui, {pseudo}.',
    ),
    IaNarrativeTemplate(
      id: 'regression_3',
      text: '{pseudo}, certaines sélections restent moins précises que la veille.',
    ),
    IaNarrativeTemplate(
      id: 'regression_4',
      text: 'Journée plus compliquée qu\'hier, {pseudo} — les données restent analysées.',
    ),
    IaNarrativeTemplate(
      id: 'regression_5',
      text: '{pseudo}, le taux de réussite baisse légèrement par rapport à hier.',
    ),
  ];

  // ── Stable : pas de variation significative ───────────────────────────────
  static const List<IaNarrativeTemplate> jourStable = [
    IaNarrativeTemplate(
      id: 'stable_1',
      text: '{pseudo}, les résultats restent globalement stables.',
    ),
    IaNarrativeTemplate(
      id: 'stable_2',
      text: 'Journée régulière pour l\'analyse, {pseudo}.',
    ),
    IaNarrativeTemplate(
      id: 'stable_3',
      text: 'Les performances sont cohérentes aujourd\'hui, {pseudo}.',
    ),
    IaNarrativeTemplate(
      id: 'stable_4',
      text: '{pseudo}, les indicateurs restent dans la même tendance qu\'hier.',
    ),
    IaNarrativeTemplate(
      id: 'stable_5',
      text: 'Continuité dans les résultats aujourd\'hui, {pseudo}.',
    ),
  ];

  // ── Tendance 7 jours positive ─────────────────────────────────────────────
  static const List<IaNarrativeTemplate> tendance7j = [
    IaNarrativeTemplate(
      id: 'tendance7j_1',
      text: '{pseudo}, la tendance sur 7 jours s\'améliore progressivement.',
    ),
    IaNarrativeTemplate(
      id: 'tendance7j_2',
      text: 'Les résultats récents montrent une meilleure stabilité sur la semaine.',
    ),
    IaNarrativeTemplate(
      id: 'tendance7j_3',
      text: '{pseudo}, la régularité sur les 7 derniers jours est en hausse.',
    ),
    IaNarrativeTemplate(
      id: 'tendance7j_4',
      text: 'La dynamique hebdomadaire reste positive sur cette période, {pseudo}.',
    ),
  ];

  // ── Tendance 7 jours négative ─────────────────────────────────────────────
  static const List<IaNarrativeTemplate> regression7j = [
    IaNarrativeTemplate(
      id: 'regression7j_1',
      text: '{pseudo}, la tendance sur 7 jours marque un léger recul.',
    ),
    IaNarrativeTemplate(
      id: 'regression7j_2',
      text: 'Les résultats hebdomadaires restent en dessous de la période précédente.',
    ),
  ];

  // ── Discipline forte ──────────────────────────────────────────────────────
  static const List<IaNarrativeTemplate> disciplineForte = [
    IaNarrativeTemplate(
      id: 'discipline_1',
      text: 'Les courses {discipline} ressortent comme le signal le plus solide récemment.',
    ),
    IaNarrativeTemplate(
      id: 'discipline_2',
      text: '{discipline} reste la discipline la mieux ciblée sur la période, {pseudo}.',
    ),
  ];

  // ── Widget premium stable ─────────────────────────────────────────────────
  static const List<IaNarrativeTemplate> widgetStable = [
    IaNarrativeTemplate(
      id: 'widget_1',
      text: 'Le widget {widget} reste le plus régulier sur les derniers jours.',
    ),
    IaNarrativeTemplate(
      id: 'widget_2',
      text: '{widget} confirme sa régularité sur la série en cours, {pseudo}.',
    ),
  ];

  // ── Série premium active ──────────────────────────────────────────────────
  static const List<IaNarrativeTemplate> premiumSerie = [
    IaNarrativeTemplate(
      id: 'premium_1',
      text: 'Les paris premium confirment une bonne régularité sur la série en cours.',
    ),
    IaNarrativeTemplate(
      id: 'premium_2',
      text: '{pseudo}, une série premium reste active — la dynamique se maintient.',
    ),
    IaNarrativeTemplate(
      id: 'premium_3',
      text: 'Les widgets premium gardent une dynamique positive sur plusieurs jours.',
    ),
    IaNarrativeTemplate(
      id: 'premium_4',
      text: 'La série premium en cours renforce la cohérence des sélections, {pseudo}.',
    ),
  ];

  // ── ★ v10.66 : Discipline forte V3 (ton plus expert) ─────────────────────
  static const List<IaNarrativeTemplate> disciplineForteV3 = [
    IaNarrativeTemplate(
      id: 'v3_discipline_1',
      text: '{pseudo}, le {discipline} ressort comme le signal le plus stable récemment.',
    ),
    IaNarrativeTemplate(
      id: 'v3_discipline_2',
      text: 'Les courses {discipline} offrent les signaux les plus réguliers en ce moment.',
    ),
    IaNarrativeTemplate(
      id: 'v3_discipline_3',
      text: 'Sur les 14 derniers jours, {discipline} concentre les meilleures performances.',
    ),
  ];

  // ── ★ v10.66 : Widget stable V3 (ton plus expert) ────────────────────────
  static const List<IaNarrativeTemplate> widgetStableV3 = [
    IaNarrativeTemplate(
      id: 'v3_widget_1',
      text: 'Le widget {widget} reste le repère le plus fiable sur les derniers jours.',
    ),
    IaNarrativeTemplate(
      id: 'v3_widget_2',
      text: '{widget} confirme une bonne régularité dans les sélections récentes.',
    ),
    IaNarrativeTemplate(
      id: 'v3_widget_3',
      text: '{pseudo}, {widget} ressort comme le signal premium le plus constant actuellement.',
    ),
  ];

  // ── ★ v10.66 : Type de pari V3 ───────────────────────────────────────────
  static const List<IaNarrativeTemplate> typePariV3 = [
    IaNarrativeTemplate(
      id: 'v3_typepari_1',
      text: 'Les paris {typePari} montrent une meilleure cohérence récemment.',
    ),
    IaNarrativeTemplate(
      id: 'v3_typepari_2',
      text: '{pseudo}, les signaux sont plus nets sur les paris {typePari}.',
    ),
    IaNarrativeTemplate(
      id: 'v3_typepari_3',
      text: 'Sur la période récente, les {typePari} affichent la meilleure régularité.',
    ),
  ];

  // ── Fallback : pas assez de données ──────────────────────────────────────
  static const List<IaNarrativeTemplate> fallback = [
    IaNarrativeTemplate(
      id: 'fallback_1',
      text: '{pseudo}, l\'analyse du jour continue d\'enrichir les données.',
    ),
    IaNarrativeTemplate(
      id: 'fallback_2',
      text: 'Les données du jour sont en cours d\'intégration, {pseudo}.',
    ),
    IaNarrativeTemplate(
      id: 'fallback_3',
      text: '{pseudo}, l\'IA affine ses tendances au fil des courses.',
    ),
    IaNarrativeTemplate(
      id: 'fallback_4',
      text: 'L\'analyse se complète au fur et à mesure des résultats, {pseudo}.',
    ),
  ];
}
