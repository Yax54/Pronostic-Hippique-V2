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

import 'package:flutter/material.dart';
import '../models/zt_models.dart';
import '../services/ia_memory_service.dart';
import '../services/ia_memory_models.dart' show PremiumPronosticDuJour, IaPronostic;

// ─── 1. Calcul typePari + numéros depuis une course réelle ───────────────────

/// Calcule le typePari conseillé et les numéros complets depuis la course.
/// Identique à la logique de best_bet_screen._calculerOpportunites().
/// Couche LECTURE uniquement — ne modifie pas les données IA.
///
/// Retourne (tp: 'Quarté+', nums: ['6','4','8','12']) par exemple.
({String tp, List<String> nums}) typePariEtNumerosPourCourse(ZtCourse course) {
  final sorted = course.partantsParRangIA;
  if (sorted.isEmpty) return (tp: '', nums: []);

  final top       = sorted.first;
  final scoreConf = top.scoreIA;
  final score2nd  = sorted.length >= 2 ? sorted[1].scoreIA : 0.0;
  final ecart12   = (scoreConf - score2nd).abs();
  final estEquil  = ecart12 <= 15 && scoreConf >= 60 && score2nd >= 50;
  final coteTop   = top.coteDecimale;
  final seuils    = IaMemoryService.instance.seuilsConfiance;

  final String typePari;
  if (course.isQuinte) {
    typePari = 'Quinté+';
  } else if (course.isQuarte) {
    typePari = 'Quarté+';
  } else if (estEquil && scoreConf >= seuils.seuilCoupleGagnant) {
    typePari = 'Couplé Gagnant';
  } else if (estEquil && scoreConf >= seuils.seuilCouplePlace) {
    typePari = 'Couplé Placé';
  } else if (scoreConf >= seuils.seuilSimpleGagnant && coteTop <= 8.0) {
    typePari = 'Simple Gagnant';
  } else if (scoreConf >= seuils.seuilSimpleGagnant && coteTop > 8.0) {
    typePari = 'Gagnant+Placé';
  } else if (scoreConf >= seuils.seuilSimplePlace) {
    typePari = 'Simple Placé';
  } else if (scoreConf >= seuils.seuilGagnantPlace) {
    typePari = 'Gagnant+Placé';
  } else if (scoreConf >= seuils.seuilTierce) {
    typePari = 'Tiercé';
  } else {
    typePari = 'À surveiller';
  }

  final int nbNum = nbNumerosPourTypePari(typePari);
  final nums = sorted.take(nbNum).map((p) => p.numero).toList();
  return (tp: typePari, nums: nums);
}

/// Nombre de numéros à stocker/afficher selon le type de pari.
/// Utilisé par typePariEtNumerosPourCourse et best_bet_screen.
int nbNumerosPourTypePari(String typePari) {
  if (typePari == 'Quinté+') return 5;
  if (typePari == 'Quarté+') return 4;
  if (typePari == 'Tiercé' ||
      typePari == 'Tiercé Ordre' ||
      typePari == 'Tiercé Désordre') return 3;
  if (typePari == 'Couplé Gagnant' || typePari == 'Couplé Placé') return 2;
  return 1;
}

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
