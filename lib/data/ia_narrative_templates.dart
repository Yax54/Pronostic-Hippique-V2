// ═══════════════════════════════════════════════════════════════════════════
//  IA NARRATIVE TEMPLATES — v10.64
//  Templates de phrases par situation.
//  Règles UX : max 2 phrases, ton analytique, jamais "je ressens/pense".
//  {pseudo} est remplacé par le pseudo utilisateur au moment du rendu.
// ═══════════════════════════════════════════════════════════════════════════

class IaNarrativeTemplates {
  // ── Progression : aujourd'hui > hier ──────────────────────────────────────
  static const List<String> progressionJour = [
    '{pseudo}, les résultats progressent par rapport à hier.',
    'Belle amélioration aujourd\'hui, {pseudo} — les sélections sont plus précises qu\'hier.',
    '{pseudo}, la journée est en hausse : les indicateurs s\'améliorent.',
    'Les performances sont en progression aujourd\'hui, {pseudo}.',
    '{pseudo}, les critères ont mieux ciblé aujourd\'hui qu\'hier.',
  ];

  // ── Régression : aujourd'hui < hier ──────────────────────────────────────
  static const List<String> regressionJour = [
    '{pseudo}, la journée est plus difficile qu\'hier.',
    'Les résultats sont en retrait aujourd\'hui, {pseudo}.',
    '{pseudo}, certaines sélections restent moins précises que la veille.',
    'Journée plus compliquée que hier, {pseudo} — les données restent analysées.',
    '{pseudo}, le taux de réussite baisse légèrement par rapport à hier.',
  ];

  // ── Stable : pas de variation significative ───────────────────────────────
  static const List<String> jourStable = [
    '{pseudo}, les résultats restent globalement stables.',
    'Journée régulière pour l\'analyse, {pseudo}.',
    'Les performances sont cohérentes aujourd\'hui, {pseudo}.',
    '{pseudo}, les indicateurs restent dans la même tendance qu\'hier.',
    'Continuité dans les résultats aujourd\'hui, {pseudo}.',
  ];

  // ── Série premium active ──────────────────────────────────────────────────
  static const List<String> premiumSerie = [
    'Les paris premium confirment une bonne régularité sur la série en cours.',
    '{pseudo}, une série premium reste active — la dynamique se maintient.',
    'Les widgets premium gardent une dynamique positive sur plusieurs jours.',
    'La série premium en cours renforce la cohérence des sélections, {pseudo}.',
  ];

  // ── Fallback : pas assez de données pour comparer ─────────────────────────
  static const List<String> fallback = [
    '{pseudo}, l\'analyse du jour continue d\'enrichir les données.',
    'Les données du jour sont en cours d\'intégration, {pseudo}.',
    '{pseudo}, l\'IA affine ses tendances au fil des courses.',
    'L\'analyse se complète au fur et à mesure des résultats, {pseudo}.',
  ];
}
