/// ★ v10.55 — Helpers premium centralisés.
///
/// OBJECTIF : éviter toute divergence future entre Home, BestBet et Calendrier.
/// Une seule source de vérité pour :
///   • Calcul typePari + numeros depuis une ZtCourse
///   • Label lisible d'un sourceWidget
///   • Style doré d'une carte premium (calendrier)
///   • Emoji affiché selon le type de pari
///
/// NE PAS MODIFIER :
///   • IaPoidsAdaptatifs.normaliseDiscipline()  → normaliseur interne IA
///   • EloService.normaliserDiscipline()         → normaliseur interne ELO
///   • _estPremiumExactGagnantStrict()           → validation stricte
///   • _estBonConseilParType()                   → validation bons conseils
library;

import 'package:flutter/material.dart';
import '../models/zt_models.dart';
import '../services/ia_memory_service.dart';
import '../services/ia_memory_models.dart' show PremiumPronosticDuJour, IaPronostic;
import '../services/recommandation_pari_service.dart'
    as source
    show cascadeRecommandation, regleNbNumerosPourTypePari;

// ─── 1. Calcul typePari + numéros depuis une course réelle ───────────────────

/// Calcule le typePari conseillé et les numéros complets depuis la course.
///
/// ★ CORRECTION BLOC 1 (BL1-A02 / BL1-A03 / BL1-A08 / BL1-A14 / BL1-A15 /
///   BL3-A26) : cette fonction N'IMPLÉMENTE PLUS de cascade. Elle délègue à
///   `cascadeRecommandation()` (`services/recommandation_pari_service.dart`),
///   désormais SOURCE DE VÉRITÉ UNIQUE du type de pari.
///
///   Avant cette correction, la cascade existait en SEPT exemplaires :
///   cette fonction et `best_bet_screen` dupliquaient la version ADAPTATIVE,
///   tandis que `conseils_screen`, `alert_service` et `widget_service`
///   dupliquaient une version FIGÉE (80/75/65/50/35), et
///   `data_refresh_service` en contenait deux variantes sans branche Quarté+.
///   Résultat mesuré : jusqu'à 20 points d'écart de seuil Tiercé, et deux
///   types de pari différents pour la MÊME course selon l'écran.
///
///   La signature et le type de retour sont INCHANGÉS : aucun appelant n'est
///   modifié, et les libellés de type de pari restent identiques (ils sont
///   comparés par égalité de chaîne par la persistance et l'apprentissage).
///
/// Couche LECTURE uniquement — ne modifie pas les données IA.
///
/// Retourne (tp: 'Quarté+', nums: ['6','4','8','12']) par exemple.
({String tp, List<String> nums}) typePariEtNumerosPourCourse(ZtCourse course) {
  final sorted = course.partantsParRangIA;
  if (sorted.isEmpty) return (tp: '', nums: []);

  final seuils = IaMemoryService.instance.seuilsConfiance;
  final reco = source.cascadeRecommandation(
    course: course,
    seuils: seuils,
    scoreConf: sorted.first.scoreIA,
    score2nd: sorted.length >= 2 ? sorted[1].scoreIA : null,
    score3: sorted.length >= 3 ? sorted[2].scoreIA : null,
    score4: sorted.length >= 4 ? sorted[3].scoreIA : null,
    coteTop: sorted.first.coteDecimale,
  );

  final nums = sorted.take(reco.nbNumeros).map((p) => p.numero).toList();
  return (tp: reco.typePari, nums: nums);
}

/// Nombre de numéros à stocker/afficher selon le type de pari.
///
/// Délègue à la définition unique de `recommandation_pari_service.dart` :
/// une seule implémentation, aucun risque de divergence (le tableau exact
/// était dupliqué ici et utilisé par `best_bet_screen`).
int nbNumerosPourTypePari(String typePari) =>
    source.regleNbNumerosPourTypePari(typePari);

// ─── 2. Emoji selon le type de pari ─────────────────────────────────────────

/// Retourne l'emoji correspondant au type de pari pour l'affichage UI.
String emojiPourTypePari(String typePari) {
  if (typePari == 'Quinté+') return '⭐';
  if (typePari == 'Quarté+') return '🏆';
  if (typePari.contains('Tiercé')) return '🥉';
  if (typePari.contains('Couplé')) return '👥';
  if (typePari == 'Simple Gagnant') return '🎯';
  if (typePari == 'Simple Placé') return '🏅';
  if (typePari == 'Gagnant+Placé') return '🎯';
  return '📌';
}

// ─── 3. Label lisible du sourceWidget ────────────────────────────────────────

/// Retourne le label affiché dans le badge Premium du calendrier.
String labelSourcePremium(String? source) {
  switch (source) {
    case 'conseilJour':   return 'Conseil IA du jour';
    case 'meilleurPari':  return 'Meilleur Pari du jour';
    case 'topEquilibre':  return 'Top Équilibre';
    case 'plusSur':       return 'Plus Sûr';
    case 'plusRentable':  return 'Plus Rentable';
    default:              return 'Premium';
  }
}

// ─── 4. Détection premium gagnant strict pour la carte calendrier ────────────

/// Retourne true si ce pronostic correspond à un des widgets premium gagnants du jour.
/// Délègue à _estPremiumExactGagnantStrict() via IaMemoryService — ne duplique pas la logique.
bool estPremiumGagnantPourCarte({
  required IaPronostic prono,
  required List<PremiumPronosticDuJour> premiumsDuJour,
}) {
  if (premiumsDuJour.isEmpty) return false;
  return premiumsDuJour.any((premium) =>
      IaMemoryService.instance.estPremiumGagnantStrict(
        premium: premium,
        prono: prono,
      ));
}

/// Retourne le sourceWidget du premier premium gagnant correspondant à ce prono.
/// null si aucun premium ne correspond.
String? sourcePremiumPourCarte({
  required IaPronostic prono,
  required List<PremiumPronosticDuJour> premiumsDuJour,
}) {
  for (final premium in premiumsDuJour) {
    if (IaMemoryService.instance.estPremiumGagnantStrict(
      premium: premium,
      prono: prono,
    )) {
      return premium.sourceWidget;
    }
  }
  return null;
}

// ─── 5. Style doré pour une carte premium dans le calendrier ─────────────────

/// Décoration de container pour une carte premium gagnante (bordure + fond dorés).
BoxDecoration decorationCartePremium({bool isPremium = false}) {
  if (!isPremium) {
    return BoxDecoration(
      color: const Color(0xFF0D1B2A),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 1.0),
    );
  }
  return BoxDecoration(
    color: const Color(0xFF1A1400), // fond très sombre teinté doré
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: const Color(0xFFFFD700), width: 2.0),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFFFFD700).withValues(alpha: 0.12),
        blurRadius: 10,
        offset: const Offset(0, 2),
      ),
    ],
  );
}

/// Badge "⭐ Premium — [source]" affiché en haut d'une carte premium.
Widget badgePremium(String? source) {
  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFFFD700).withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: const Color(0xFFFFD700).withValues(alpha: 0.5),
      ),
    ),
    child: Text(
      '⭐ Premium — ${labelSourcePremium(source)}',
      style: const TextStyle(
        color: Color(0xFFFFD700),
        fontWeight: FontWeight.w800,
        fontSize: 13,
      ),
    ),
  );
}
