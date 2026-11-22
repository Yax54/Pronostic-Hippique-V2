// ═══════════════════════════════════════════════════════════════════════════
//  AFFICHAGE STRUCTURÉ DU GAIN — LOT B-4.5
// ═══════════════════════════════════════════════════════════════════════════
//
//  ★ POURQUOI CE FICHIER
//
//  Deux sources de vérité coexistent après B-4.5 :
//
//    • TICKETS STRUCTURÉS (`etatGain != null`) : la source est le VERDICT
//      OFFICIEL persisté (`etatGain`, `rapportsAttribues`, `etatTirelire`,
//      `motifNonDetermination`). Les champs historiques `isGagne`,
//      `dividendePmuReel` et `messageResultat` sont CONSERVÉS en base mais ne
//      doivent plus décider de l'affichage : un dividende sélectionné par
//      `reduce(MAX)` ne peut plus être présenté comme un gain confirmé.
//
//    • TICKETS HISTORIQUES (`etatGain == null`) : la source reste l'historique
//      inchangé. Rien n'est réécrit, rien n'est recalculé, et le libellé
//      distingue explicitement « non vérifié » de « confirmé ».
//
//  Ce fichier ne contient AUCUNE règle financière nouvelle. Le montant d'un
//  ticket structuré est RECONSTRUIT par `resoudreTotalDepuisRapports`, qui
//  additionne des `montantRetour` DÉJÀ persistés et calculés une seule fois
//  par `RapportAttribue.calculer`. Il n'y a donc AUCUNE multiplication ici :
//  multiplier `pourUnEuro × mise` une seconde fois produirait exactement le
//  double comptage que le lot doit éliminer.
//
//  ⚠️ `dividendeGagnant` et `dividendePlace` valent `pourUnEuro`, jamais un
//     gain (verrouillé par B-4.3/3.3 et B-4.4/3.3). Ils ne sont donc JAMAIS
//     présentés ici comme un montant encaissé.
// ═══════════════════════════════════════════════════════════════════════════

import '../utils/format_euros.dart';
import 'alert_service.dart';
import 'enregistreur_verdict_gain_pmu.dart' show resoudreTotalDepuisRapports;
import 'gain_pmu_types.dart';

/// Nature du gain affiché. Quatre états du verdict, plus un état historique.
enum NatureAffichageGain {
  /// `attribue` : un montant officiel est démontrable.
  attribue,

  /// `perdu` : la perte est établie. Aucun montant gagnant n'est affiché.
  perdu,

  /// `rembourse` : le remboursement est démontré. Ce n'est PAS un gain.
  rembourse,

  /// `nonDetermine` : aucun montant n'est démontrable. Motif affichable.
  indetermine,

  /// Ticket sans verdict structuré : l'information est HISTORIQUE, donc non
  /// vérifiée officiellement. Le libellé doit le dire.
  historique,
}

/// Vue d'affichage d'un ticket : ce que l'écran doit montrer, et rien de plus.
class AffichageGain {
  final NatureAffichageGain nature;

  /// Montant en euros, UNIQUEMENT quand il est démontrable. `null` sinon.
  ///
  /// Pour [NatureAffichageGain.attribue], c'est le retour BRUT officiel.
  /// Pour [NatureAffichageGain.rembourse], c'est le montant remboursé (déjà
  /// égal à la somme des retours attribués). Jamais pour `perdu` ni
  /// `indetermine`.
  final double? montant;

  /// Texte principal, prêt à afficher.
  final String libelle;

  /// Texte secondaire explicatif, ou `null`.
  final String? detail;

  const AffichageGain({
    required this.nature,
    required this.libelle,
    this.montant,
    this.detail,
  });

  /// `true` si un montant positif est affiché. Sert aux tests et au rendu.
  bool get afficheUnMontant => montant != null && montant! > 0;
}

/// Construit l'affichage d'un ticket suivi.
///
/// SI `etatGain != null`, la décision vient EXCLUSIVEMENT du verdict.
/// `isGagne` et `dividendePmuReel` ne sont alors même pas lus : il n'existe
/// donc aucun chemin par lequel l'historique pourrait contredire le verdict.
///
/// SI `etatGain == null`, on retombe sur le comportement historique, en
/// marquant explicitement que le montant n'est pas officiellement vérifié.
AffichageGain affichageGainSuivi(TrackedCourse c) {
  final etat = c.etatGain;

  if (etat != null) {
    switch (etat) {
      case EtatGain.attribue:
        final total = resoudreTotalDepuisRapports(c.rapportsAttribues);
        if (total == null || !(total > 0)) {
          // Verdict « attribue » sans preuve de montant : on ne fabrique rien.
          return const AffichageGain(
            nature: NatureAffichageGain.indetermine,
            libelle: 'Résultat indéterminé',
            detail: 'Verdict attribué mais aucun montant persisté.',
          );
        }
        return AffichageGain(
          nature: NatureAffichageGain.attribue,
          libelle: '🏆 Gain gagné : ${fmtEuros(total)} € brut',
          montant: total,
          detail: _detailTirelire(c.etatTirelire),
        );

      case EtatGain.perdu:
        return const AffichageGain(
          nature: NatureAffichageGain.perdu,
          libelle: '❌ Pari perdu',
          detail: 'Perte établie par le résultat officiel.',
        );

      case EtatGain.rembourse:
        final total = resoudreTotalDepuisRapports(c.rapportsAttribues);
        return AffichageGain(
          nature: NatureAffichageGain.rembourse,
          libelle: total != null && total > 0
              ? '↩️ Remboursé : ${fmtEuros(total)} € (retour de mise)'
              : '↩️ Pari remboursé',
          montant: total != null && total > 0 ? total : null,
          detail: 'Remboursement démontré — ce n\'est pas un gain.',
        );

      case EtatGain.nonDetermine:
        final motif = c.motifNonDetermination;
        return AffichageGain(
          nature: NatureAffichageGain.indetermine,
          libelle: '❔ Résultat indéterminé',
          detail: motif == null
              ? 'Aucun montant démontrable.'
              : 'Aucun montant démontrable (motif : ${motif.name}).',
        );
    }
  }

  // ── Ticket HISTORIQUE : aucune réécriture, aucun recalcul ────────────────
  // Le montant reste celui qui existe déjà, mais il n'est PAS présenté comme
  // officiellement confirmé — c'est toute la distinction exigée par le lot.
  final isGagne = c.isGagne;
  if (isGagne == false) {
    return const AffichageGain(
      nature: NatureAffichageGain.historique,
      libelle: '❌ Pari perdu',
      detail: 'Résultat historique, non revérifié.',
    );
  }

  final div = c.dividendePmuReel;
  if (div != null && div > 0) {
    final mise = c.miseTotaleEngagee;
    if (mise != null && mise > 0) {
      return AffichageGain(
        nature: NatureAffichageGain.historique,
        libelle: '💰 Gain enregistré : ${fmtEuros(div * mise)} € (non vérifié)',
        montant: div * mise,
        detail: 'Montant historique conservé — non confirmé par un verdict '
            'officiel (dividende sélectionné avant le lot B-4.5).',
      );
    }
    return const AffichageGain(
      nature: NatureAffichageGain.historique,
      libelle: '💰 Gain enregistré (non vérifié)',
      detail: 'Montant historique conservé — non confirmé officiellement.',
    );
  }

  if (isGagne == true) {
    return const AffichageGain(
      nature: NatureAffichageGain.historique,
      libelle: '🏆 Pari gagnant — montant non vérifié',
      detail: 'Résultat historique sans rapport officiel rattaché.',
    );
  }

  return const AffichageGain(
    nature: NatureAffichageGain.historique,
    libelle: '⏳ En attente du rapport officiel',
  );
}

String? _detailTirelire(EtatTirelire? etat) {
  switch (etat) {
    case EtatTirelire.incluse:
      return 'Rapport « + Tirelire » retenu comme rapport définitif.';
    case EtatTirelire.nonDeterminee:
      return 'Tirelire non déterminée : aucun montant de Tirelire ajouté.';
    case EtatTirelire.sansObjet:
    case null:
      return null;
  }
}
