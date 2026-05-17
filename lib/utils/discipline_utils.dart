/// ★ v10.53 — Normalisation discipline pour affichage UI uniquement.
///
/// RÈGLE D'OR :
///   • Couche LECTURE uniquement — ne modifie jamais les données brutes PMU.
///   • [disciplineBrute] (ZtReunion.discipline) reste inchangé partout.
///   • NE PAS utiliser pour l'apprentissage IA :
///       → IaPoidsAdaptatifs.normaliseDiscipline() → keys 'trot_attele' / 'plat' / etc.
///       → EloService.normaliserDiscipline()        → normaliseur interne ELO
///   • Utiliser UNIQUEMENT pour : filtres UI, chips, labels affichés à l'utilisateur.
///
/// Catégories canoniques retournées :
///   'Trot'     — Trot Attelé, Trot Monté, Course Attelée, Attelé, Trot …
///   'Monté'    — Trot Monté, Monté
///   'Plat'     — Plat, Course Plate
///   'Obstacle' — Haies, Steeple-Chase, Steeple Chase, Steeple, Cross, Obstacle
///   'Autre'    — string vide ou non reconnue
///
/// Fallback : si non reconnu et non vide → retourne la valeur brute trimée
///            (évite de masquer une discipline inconnue).

/// Liste canonique des disciplines UI — ordre d'affichage stable.
const List<String> disciplinesUICanoniques = ['Trot', 'Monté', 'Plat', 'Obstacle'];

/// Normalise une string discipline brute PMU vers un label UI canonique.
///
/// Exemples :
///   'TROT ATTELE'       → 'Trot'
///   'trot attelé'       → 'Trot'
///   'Course attelée'    → 'Trot'
///   'TROT MONTE'        → 'Monté'
///   'trot monté'        → 'Monté'
///   'PLAT'              → 'Plat'
///   'Steeple-Chase'     → 'Obstacle'
///   'Steeple Chase'     → 'Obstacle'
///   'STEEPLE'           → 'Obstacle'
///   'HAIES'             → 'Obstacle'
///   'CROSS'             → 'Obstacle'
///   'OBSTACLE'          → 'Obstacle'
///   ''                  → 'Autre'
///   'Inconnue'          → 'Inconnue'  (fallback brute)
String normaliserDisciplineUI(String raw) {
  final d = raw.toLowerCase().trim();

  if (d.isEmpty) return 'Autre';

  // ── Obstacle (haies, steeple, cross, obstacle) ─────────────────────────
  if (d.contains('haie') ||
      d.contains('obstacle') ||
      d.contains('steeple') ||
      d.contains('cross')) {
    return 'Obstacle';
  }

  // ── Monté — AVANT Trot : "trot monté" contient "mont" et "trot" ────────
  // ⚠️ Même piège que "Désordre/Ordre" : tester Monté avant Trot générique.
  if (d.contains('mont')) return 'Monté';

  // ── Trot (attelé, course attelée, trot générique) ─────────────────────
  if (d.contains('attel') || d.contains('trot')) return 'Trot';

  // ── Plat ───────────────────────────────────────────────────────────────
  if (d.contains('plat')) return 'Plat';

  // ── Fallback : valeur brute trimée (non vide, non reconnue) ────────────
  // Permet de détecter de nouvelles disciplines sans masquer des données.
  return raw.trim();
}
