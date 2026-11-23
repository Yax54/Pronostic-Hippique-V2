// ═══════════════════════════════════════════════════════════════════════════
//  B1-T12 / LOT 2-C — VUE D'AFFICHAGE DURABLE, SOURCE UNIQUE
// ═══════════════════════════════════════════════════════════════════════════
//
//  ★ POURQUOI CE FICHIER
//
//  Une SEULE implémentation de la priorité financière, exposant à la fois le
//  MONTANT et le LIBELLÉ. Le libellé de la carte « Mes Paris » et le montant
//  de la carte de partage sortent donc de LA MÊME décision : ils ne peuvent
//  pas se contredire en affichant deux sommes différentes pour le même pari.
//
//  ⚠️ AUCUN CALCUL PMU ICI, ET C'EST DÉLIBÉRÉ.
//     On LIT des montants déjà établis et déjà persistés. Aucun rapport n'est
//     reconstruit, aucune multiplication n'est refaite, aucun dividende n'est
//     sélectionné. C'est exactement l'inverse d'un second moteur de calcul :
//     ce fichier ne contient pas une seule formule.
//
//  ⚠️ `null` EST LA VALEUR QUI PRÉSERVE L'EXISTANT.
//     Chaque fonction rend `null` quand elle n'a rien de durable à dire. Les
//     appelants retombent alors sur leur chaîne historique, À L'IDENTIQUE.
//     C'est ce qui garantit qu'un ticket sans décision B1-T12 ne change pas
//     d'apparence d'un seul caractère.
// ═══════════════════════════════════════════════════════════════════════════

import '../models/decision_gain_pmu.dart';
import '../models/pmu_models.dart';
import '../utils/format_euros.dart';

/// Vue durable : montant brut et libellé, issus de la MÊME règle.
class GainDurable {
  /// Montant BRUT en euros. `null` = indéterminé : AUCUN montant n'est
  /// inventé. `0.0` est un résultat (perte ou déclaration nulle), distinct de
  /// `null` (inconnu) — la confusion des deux ferait apparaître un gain de 0 €
  /// là où l'on ne sait simplement rien.
  final double? montant;

  /// Texte principal, prêt à afficher.
  final String libelle;

  /// `true` si le montant vient du PMU (décision acceptée), `false` s'il est
  /// déclaré par l'utilisateur.
  final bool estOfficiel;

  const GainDurable({
    required this.montant,
    required this.libelle,
    required this.estOfficiel,
  });
}

/// Décision B1-T12 enregistrée, ou `null` si aucune ne s'applique.
///
/// VERROU D'ÉTAT — un ticket qui ne porte QU'un gain manuel (lot 2-A) rend
/// `null` : son affichage reste donc historique. On ne s'active que si une
/// demande a réellement existé, c'est-à-dire si `montantOfficielPmu` est
/// renseigné, ou si `decisionGainPmu` porte une décision, ou si l'appelant
/// fournit une preuve externe ([demandeOuverte]).
///
/// PRIORITÉS (mandat §5) :
///   • accepté   → officiel ;
///   • refusé    → manuel ;
///   • en attente (`decisionGainPmu == null`) → manuel, JAMAIS l'officiel.
///
/// [verdictOfficielPresent] : défense en profondeur. Un appel direct ne peut
/// pas contourner un verdict B-3/B-4.5, même si `vueDurable` l'a déjà écarté.
GainDurable? decisionGainDurable(
  UserPrediction? p, {
  bool demandeOuverte = false,
  bool verdictOfficielPresent = false,
}) {
  if (p == null) return null;

  // Le verdict officiel prime TOUJOURS. Une décision B1-T12 ne peut pas le
  // contourner, et l'afficher ne provoque aucune acceptation financière :
  // ce fichier ne fait que lire.
  if (verdictOfficielPresent) return null;

  final aUnOfficiel = p.montantOfficielPmu != null;
  if (!aUnOfficiel && p.decisionGainPmu == null && !demandeOuverte) return null;

  if (p.decisionGainPmu == DecisionGainPmu.accepte) {
    final o = p.montantOfficielPmu;
    if (o == null) {
      // Accepté sans montant : on le DIT, on n'invente rien.
      return const GainDurable(
        montant: null,
        estOfficiel: true,
        libelle: '❔ Gain officiel accepté mais montant indisponible',
      );
    }
    return GainDurable(
      montant: o,
      estOfficiel: true,
      libelle: o > 0
          ? '🏆 Gain gagné : ${fmtEuros(o)} € brut (gain officiel PMU)'
          : '❌ Perdu : gain officiel PMU établi à 0 €',
    );
  }

  // ── EN ATTENTE : un officiel est connu, aucune décision n'est prise.
  //    L'officiel ne remplace JAMAIS le manuel avant acceptation explicite.
  if (p.decisionGainPmu == null) {
    final m = p.montantGainManuel;
    return GainDurable(
      montant: m, // `null` = inconnu, jamais l'officiel
      estOfficiel: false,
      libelle: m == null
          ? '⏳ Gain officiel PMU disponible — votre décision est attendue'
          : m > 0
              ? '🏆 Gain gagné : ${fmtEuros(m)} € brut (montant déclaré) — '
                  'décision PMU en attente'
              : '❌ Gain déclaré : 0 € — décision PMU en attente',
    );
  }

  // ── REFUS explicite : le montant manuel fait foi.
  final m = p.montantGainManuel;
  if (m == null) {
    return const GainDurable(
      montant: null,
      estOfficiel: false,
      libelle: '❔ Gain officiel refusé, mais aucun montant déclaré',
    );
  }
  return GainDurable(
    montant: m,
    estOfficiel: false,
    libelle: m > 0
        ? '🏆 Gain gagné : ${fmtEuros(m)} € brut (montant déclaré)'
        : '❌ Gain déclaré : 0 €',
  );
}

/// Gain DÉCLARÉ par l'utilisateur (lot 2-A), désormais réellement affiché.
///
/// SÉPARÉE de [decisionGainDurable], comme exigé : elle ne dépend d'AUCUNE
/// décision et ne peut donc jamais faire apparaître un état B1-T12 inexistant.
///
/// Rend `null` — donc affichage historique — dans trois cas :
///   • aucune déclaration (`montantGainManuel == null`) : absence ≠ 0 € ;
///   • un verdict officiel structuré existe : B-3/B-4.5 GARDE LA PRIORITÉ ;
///   • une décision B1-T12 existe : c'est alors [decisionGainDurable] qui
///     tranche, et cette fonction n'a pas à s'exprimer.
GainDurable? gainDeclareDurable(
  UserPrediction? p, {
  required bool verdictOfficielPresent,
  required bool decisionB1T12Presente,
}) {
  if (p == null) return null;
  if (verdictOfficielPresent) return null;
  if (decisionB1T12Presente) return null;
  final m = p.montantGainManuel;
  if (m == null) return null;
  return GainDurable(
    montant: m,
    estOfficiel: false,
    libelle: m > 0
        ? '🏆 Gain gagné : ${fmtEuros(m)} € brut (montant déclaré)'
        : '❌ Gain déclaré : 0 €',
  );
}

/// La vue qui doit s'appliquer, dans l'ordre imposé par la table de priorité.
///
/// `null` = aucune décision durable applicable ⇒ l'appelant garde son
/// comportement historique, sans un caractère de différence.
///
/// ORDRE — il est le cœur de la garantie :
///   ① verdict officiel présent  → `null` (le verdict garde l'affichage) ;
///   ② décision B1-T12           → c'est elle qui tranche ;
///   ③ gain déclaré seul         → affiché, puisque le lot 2-A l'ignorait.
GainDurable? vueDurable(
  UserPrediction? p, {
  required bool verdictOfficielPresent,
  bool demandeOuverte = false,
}) {
  // ① CAS 1 DE LA TABLE — LE VERDICT COUPE AVANT TOUT.
  //   Placé ICI, avant tout appel, pour qu'aucun chemin ne puisse l'oublier.
  if (verdictOfficielPresent) return null;

  // ② Une décision existe-t-elle ?
  final decision = decisionGainDurable(p, demandeOuverte: demandeOuverte);
  if (decision != null) return decision;

  // ③ Sinon, un gain déclaré est-il durablement connu ?
  return gainDeclareDurable(
    p,
    verdictOfficielPresent: false, // déjà écarté au ①
    decisionB1T12Presente: false,  // déjà écartée au ②
  );
}
