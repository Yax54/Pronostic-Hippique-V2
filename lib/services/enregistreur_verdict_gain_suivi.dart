// ═══════════════════════════════════════════════════════════════════════════
//  LOT B-4.4 — ENREGISTREMENT SÉCURISÉ D'UN VERDICT B-3 SUR UN `TrackedCourse`
//
//  ── CE QUE CE FICHIER AJOUTE, ET RIEN DE PLUS ─────────────────────────────
//  1. `copyWith` sur `TrackedCourse`, qui n'en avait AUCUN (mesuré :
//     `grep -n copyWith lib/services/alert_service.dart` ne rend qu'UNE seule
//     occurrence, l.320, et c'est `AlertConfig`).
//  2. L'APPLICATION de la décision B-4.3 au modèle `TrackedCourse`.
//  3. La BARRIÈRE D'IDENTITÉ entre `UserPrediction` et `TrackedCourse`.
//
//  ── CE QU'IL NE FAIT JAMAIS ──────────────────────────────────────────────
//  • il ne réécrit AUCUNE règle financière : la décision est
//    [deciderEcritureVerdict] (B-4.3), appelée TELLE QUELLE. Ce fichier ne
//    contient ni identité de rapport, ni `RapportAttribue.calculer`, ni
//    contrôle de total, ni tolérance monétaire ;
//  • il n'appelle PAS le moteur B-3 (`resoudreGainTicket`) : le verdict est
//    une ENTRÉE, jamais un calcul ;
//  • il ne crée AUCUN mécanisme de synchronisation entre les deux modèles.
//    Voir la section 4 : la preuve d'identité est une CONDITION, et cette
//    condition n'est satisfaite dans aucun cas mesurable aujourd'hui ;
//  • il n'écrit rien sur disque, n'appelle aucun provider, aucun écran ;
//  • il ne modifie pas l'objet reçu (tout passe par `copyWith`).
//
//  ── LA RÈGLE FONDAMENTALE (consigne utilisateur, verbatim) ────────────────
//  « Le rapport affiché et le "Gain gagné" doivent obligatoirement
//    correspondre au pari réellement joué et au résultat officiel. Il ne faut
//    jamais sélectionner automatiquement le dividende le plus élevé. »
// ═══════════════════════════════════════════════════════════════════════════

import '../models/pmu_models.dart';
import 'alert_service.dart';
import 'enregistreur_verdict_gain_pmu.dart';
import 'gain_pmu_types.dart';
import 'moteur_gain_pmu.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  1. SENTINELLE D'OMISSION — même mécanique que B-4.3
// ═══════════════════════════════════════════════════════════════════════════
//
//  POURQUOI UNE SENTINELLE, ET PAS UN SIMPLE `T? parametre` :
//  sur les champs facultatifs de `TrackedCourse`, `null` est une VALEUR
//  MÉTIER (« aucun dividende Gagnant », « aucun rapport attribué », « aucun
//  motif »). Avec un paramètre `double? dividendeGagnant`, on ne pourrait pas
//  distinguer « je ne touche pas » de « j'efface » : les deux se
//  confondraient, et un `copyWith` de routine effacerait silencieusement un
//  gain. C'est précisément le défaut que B-4.3 a écarté sur `UserPrediction`.
//
//  La sentinelle est PRIVÉE à ce fichier : aucun appelant extérieur ne peut
//  l'injecter, et elle ne peut pas entrer en collision avec celle de
//  `pmu_models.dart` (elle aussi privée, donc invisible ici).
class _InchangeSuivi {
  const _InchangeSuivi();
}

const Object _inchangeSuivi = _InchangeSuivi();

// ═══════════════════════════════════════════════════════════════════════════
//  2. `copyWith` SUR `TrackedCourse`
// ═══════════════════════════════════════════════════════════════════════════
//
//  MESURE PRÉALABLE : `TrackedCourse` n'a AUCUN `copyWith`. Ses
//  reconstructions existantes recopient les 37 champs à la main :
//    • `TrackedCourse.withResultat`  (alert_service.dart:3290)
//    • `TrackedCourse.withDividende` (alert_service.dart:3400)
//    • `AlertService.ajouterSuivi`   (alert_service.dart:726)
//  Ces trois-là propagent DÉJÀ les sept champs B-1 (vérifié champ par champ,
//  `storageKey` inclus) : il n'y avait donc, de ce côté, aucun chemin de
//  perte à corriger. C'est un résultat de mesure, pas une supposition.
//
//  Ce `copyWith` existe pour une raison PRÉCISE : l'enregistreur doit changer
//  SEPT champs et seulement sept. Reconstruire le ticket à la main ferait
//  courir le risque exact que R1, B2-C, 4-F et B-1 ont documenté à cinq
//  reprises — oublier une ligne dans une reconstruction champ par champ.
//
//  ⚠️ LISTES : recopiées, jamais partagées. Deux tickets distincts ne doivent
//     pas pouvoir modifier la même `List` (même garantie qu'en B-4.3 sur
//     `UserPrediction`).
//  ⚠️ Les champs OBLIGATOIRES et non nullables (`numReunion`, `nomCourse`,
//     `addedAt`, `typePari`, `scoreIA`, `cote`…) n'ont pas de sentinelle :
//     `null` n'y a aucune signification métier, ce serait un effacement
//     invalide. Ils suivent donc le `??` classique.
extension TrackedCourseCopy on TrackedCourse {
  /// Copie ce ticket en ne remplaçant QUE les champs explicitement fournis.
  ///
  /// Sans argument, la copie est identique champ par champ à la source —
  /// vérifié par le test B4.4/2.1, qui compare les 37 champs ET les 28 clés
  /// JSON (aucune clé B-1 n'apparaît).
  ///
  /// Un argument `null` EXPLICITE efface le champ : ce n'est pas une omission
  /// (test B4.4/2.2). Comportement identique à `UserPrediction.copyWith`.
  TrackedCourse copyWith({
    int? numReunion,
    int? numCourse,
    String? nomCourse,
    String? hippodrome,
    DateTime? heureDepart,
    Object? nomCheval = _inchangeSuivi,
    Object? numeroCheval = _inchangeSuivi,
    Object? miseEngagee = _inchangeSuivi,
    Object? miseGagnant = _inchangeSuivi,
    Object? misePlace = _inchangeSuivi,
    Object? coteGagnant = _inchangeSuivi,
    Object? cotePlace = _inchangeSuivi,
    DateTime? addedAt,
    Object? storageKey = _inchangeSuivi,
    String? typePari,
    Object? numerosJoues = _inchangeSuivi,
    Object? iaMemKey = _inchangeSuivi,
    double? scoreIA,
    double? cote,
    Object? isGagne = _inchangeSuivi,
    Object? arriveeFinale = _inchangeSuivi,
    Object? messageResultat = _inchangeSuivi,
    Object? dividendePmuReel = _inchangeSuivi,
    Object? combinaisonPmu = _inchangeSuivi,
    Object? arriveeGroupes = _inchangeSuivi,
    Object? arriveeDefinitive = _inchangeSuivi,
    Object? codePmuOfficiel = _inchangeSuivi,
    Object? varianteChoisie = _inchangeSuivi,
    Object? numerosDansOrdre = _inchangeSuivi,
    Object? formulePari = _inchangeSuivi,
    // ── Les sept champs B-1 ──────────────────────────────────────────────
    Object? etatGain = _inchangeSuivi,
    Object? rapportsAttribues = _inchangeSuivi,
    Object? etatTirelire = _inchangeSuivi,
    Object? dividendeGagnant = _inchangeSuivi,
    Object? dividendePlace = _inchangeSuivi,
    Object? miseBaseCentimesUtilisee = _inchangeSuivi,
    Object? motifNonDetermination = _inchangeSuivi,
    // ── B1-T12 / étape 1 — gain manuel et liaison certaine ────────────────
    //  Sentinelle obligatoire : `null` doit pouvoir être écrit explicitement
    //  pour ANNULER un gain manuel (retour au calcul PMU) ou délier un ticket.
    Object? montantGainManuel = _inchangeSuivi,
    Object? idTicketLie = _inchangeSuivi,
    // ── CHANTIER 1/3 — remboursement officiel, distinct du gain ───────────
    Object? remboursementPmu = _inchangeSuivi,
  }) {
    return TrackedCourse(
      numReunion: numReunion ?? this.numReunion,
      numCourse: numCourse ?? this.numCourse,
      nomCourse: nomCourse ?? this.nomCourse,
      hippodrome: hippodrome ?? this.hippodrome,
      heureDepart: heureDepart ?? this.heureDepart,
      nomCheval: identical(nomCheval, _inchangeSuivi)
          ? this.nomCheval
          : nomCheval as String?,
      numeroCheval: identical(numeroCheval, _inchangeSuivi)
          ? this.numeroCheval
          : numeroCheval as int?,
      miseEngagee: identical(miseEngagee, _inchangeSuivi)
          ? this.miseEngagee
          : miseEngagee as double?,
      miseGagnant: identical(miseGagnant, _inchangeSuivi)
          ? this.miseGagnant
          : miseGagnant as double?,
      misePlace: identical(misePlace, _inchangeSuivi)
          ? this.misePlace
          : misePlace as double?,
      coteGagnant: identical(coteGagnant, _inchangeSuivi)
          ? this.coteGagnant
          : coteGagnant as double?,
      cotePlace: identical(cotePlace, _inchangeSuivi)
          ? this.cotePlace
          : cotePlace as double?,
      addedAt: addedAt ?? this.addedAt,
      storageKey: identical(storageKey, _inchangeSuivi)
          ? this.storageKey
          : storageKey as String?,
      typePari: typePari ?? this.typePari,
      numerosJoues: identical(numerosJoues, _inchangeSuivi)
          ? List<int>.of(this.numerosJoues)
          : List<int>.of(numerosJoues as List<int>),
      iaMemKey: identical(iaMemKey, _inchangeSuivi)
          ? this.iaMemKey
          : iaMemKey as String?,
      scoreIA: scoreIA ?? this.scoreIA,
      cote: cote ?? this.cote,
      isGagne:
          identical(isGagne, _inchangeSuivi) ? this.isGagne : isGagne as bool?,
      arriveeFinale: identical(arriveeFinale, _inchangeSuivi)
          ? List<int>.of(this.arriveeFinale)
          : List<int>.of(arriveeFinale as List<int>),
      messageResultat: identical(messageResultat, _inchangeSuivi)
          ? this.messageResultat
          : messageResultat as String?,
      dividendePmuReel: identical(dividendePmuReel, _inchangeSuivi)
          ? this.dividendePmuReel
          : dividendePmuReel as double?,
      combinaisonPmu: identical(combinaisonPmu, _inchangeSuivi)
          ? this.combinaisonPmu
          : combinaisonPmu as String?,
      arriveeGroupes: identical(arriveeGroupes, _inchangeSuivi)
          ? this.arriveeGroupes?.map((g) => List<int>.of(g)).toList()
          : (arriveeGroupes == null
              ? null
              : (arriveeGroupes as List<List<int>>)
                  .map((g) => List<int>.of(g))
                  .toList()),
      arriveeDefinitive: identical(arriveeDefinitive, _inchangeSuivi)
          ? this.arriveeDefinitive
          : arriveeDefinitive as bool?,
      codePmuOfficiel: identical(codePmuOfficiel, _inchangeSuivi)
          ? this.codePmuOfficiel
          : codePmuOfficiel as String?,
      varianteChoisie: identical(varianteChoisie, _inchangeSuivi)
          ? this.varianteChoisie
          : varianteChoisie as String?,
      numerosDansOrdre: identical(numerosDansOrdre, _inchangeSuivi)
          ? (this.numerosDansOrdre == null
              ? null
              : List<int>.of(this.numerosDansOrdre!))
          : (numerosDansOrdre == null
              ? null
              : List<int>.of(numerosDansOrdre as List<int>)),
      formulePari: identical(formulePari, _inchangeSuivi)
          ? this.formulePari
          : formulePari as String?,
      // ── Les sept champs B-1 : `null` explicite = effacement DÉCIDÉ ─────
      etatGain: identical(etatGain, _inchangeSuivi)
          ? this.etatGain
          : etatGain as EtatGain?,
      rapportsAttribues: identical(rapportsAttribues, _inchangeSuivi)
          ? (this.rapportsAttribues == null
              ? null
              : List<RapportAttribue>.unmodifiable(this.rapportsAttribues!))
          : (rapportsAttribues == null
              ? null
              : List<RapportAttribue>.unmodifiable(
                  rapportsAttribues as List<RapportAttribue>)),
      etatTirelire: identical(etatTirelire, _inchangeSuivi)
          ? this.etatTirelire
          : etatTirelire as EtatTirelire?,
      dividendeGagnant: identical(dividendeGagnant, _inchangeSuivi)
          ? this.dividendeGagnant
          : dividendeGagnant as double?,
      dividendePlace: identical(dividendePlace, _inchangeSuivi)
          ? this.dividendePlace
          : dividendePlace as double?,
      miseBaseCentimesUtilisee:
          identical(miseBaseCentimesUtilisee, _inchangeSuivi)
              ? this.miseBaseCentimesUtilisee
              : miseBaseCentimesUtilisee as int?,
      motifNonDetermination: identical(motifNonDetermination, _inchangeSuivi)
          ? this.motifNonDetermination
          : motifNonDetermination as MotifNonDetermination?,
      // ★ B1-T12 / étape 1 — propagés avec la sentinelle : `null` explicite
      //   possible (annulation du gain manuel, déliaison du ticket).
      montantGainManuel: identical(montantGainManuel, _inchangeSuivi)
          ? this.montantGainManuel
          : montantGainManuel as double?,
      idTicketLie: identical(idTicketLie, _inchangeSuivi)
          ? this.idTicketLie
          : idTicketLie as String?,
      // ★ CHANTIER 1/3 — propagé avec la sentinelle : `null` explicite
      //   possible (retour à « aucun remboursement établi »).
      remboursementPmu: identical(remboursementPmu, _inchangeSuivi)
          ? this.remboursementPmu
          : remboursementPmu as double?,
    );
  }

  /// ★ B1-T12 / étape 1 (complément) — Copie DÉLIÉE, prête à être persistée.
  ///
  /// RAISON D'ÊTRE, MESURÉE : la création d'un pari fait DEUX écritures non
  /// transactionnelles (`ajouterSuivi` puis `addPrediction`). Si la seconde
  /// échoue, le suivi survivrait en prétendant être lié à un profil inexistant.
  /// Il faut alors publier « non lié ».
  ///
  /// POURQUOI ICI ET NON DANS `alert_service.dart` : le test B4.4/12.3
  /// verrouille le fait que `alert_service.dart` ne contient AUCUN `copyWith`
  /// de `TrackedCourse` (une seule occurrence, `AlertConfig.copyWith`). C'est
  /// ce même contrat qui impose que la copie vive dans cette extension. Le
  /// test n'a pas été modifié : c'est le code qui respecte le contrat.
  ///
  /// Ne touche RIEN d'autre : ni verdict, ni rapports, ni les sept champs B-1,
  /// ni `dividendePmuReel`. Un ticket délié conserve son gain manuel.
  TrackedCourse copieDeliee() => copyWith(idTicketLie: null);

  /// ★ B1-T12 / étape 2 (lot 2-A) — Copie portant un GAIN MANUEL, ou l'annulant.
  ///
  /// Même raison d'emplacement que [copieDeliee] : le test B4.4/12.3 verrouille
  /// l'absence de `copyWith` dans `alert_service.dart`, où vit l'écriture.
  ///
  /// [montant] `null` ANNULE la déclaration (le PMU redevient seul maître).
  /// `0.0` est un montant : il reste DISTINCT de l'absence de saisie, grâce à
  /// la sentinelle que porte `copyWith`.
  ///
  /// Ne modifie AUCUN autre champ : ni les rapports PMU, ni `dividendePmuReel`,
  /// ni les sept champs B-1, ni le verdict.
  TrackedCourse copieAvecGainManuel(double? montant) =>
      copyWith(montantGainManuel: montant);
}

// ═══════════════════════════════════════════════════════════════════════════
//  3. APPLICATION DE LA DÉCISION B-4.3 AU MODÈLE `TrackedCourse`
// ═══════════════════════════════════════════════════════════════════════════

/// Résultat d'une tentative d'enregistrement sur un `TrackedCourse`.
///
/// [ticket] est TOUJOURS non nul : en cas de refus, c'est l'original rendu
/// tel quel. Un appelant peut donc l'utiliser sans le tester.
class ResultatEnregistrementVerdictSuivi {
  final TrackedCourse ticket;
  final StatutEnregistrementVerdict statut;
  final String? motif;
  final bool persistanceComplete;
  final List<String> informationsNonPersistees;

  const ResultatEnregistrementVerdictSuivi._({
    required this.ticket,
    required this.statut,
    required this.motif,
    required this.persistanceComplete,
    required this.informationsNonPersistees,
  });

  bool get estEnregistre =>
      statut == StatutEnregistrementVerdict.enregistre;

  bool get estRefuse =>
      statut != StatutEnregistrementVerdict.enregistre &&
      statut != StatutEnregistrementVerdict.dejaIdentique;

  bool get ticketInchange => !estEnregistre;

  @override
  String toString() => 'ResultatEnregistrementVerdictSuivi(${statut.name}'
      '${motif == null ? '' : ' — $motif'}'
      ' | persistanceComplete=$persistanceComplete)';
}

/// Enregistre un [verdict] sur un `TrackedCourse`.
///
/// ★ AUCUNE RÈGLE N'EST RÉÉCRITE ICI. Les quatre lectures d'état existant sont
///   transmises à [deciderEcritureVerdict] (B-4.3), qui rend la décision ; ce
///   fichier ne fait que l'APPLIQUER au modèle `TrackedCourse`.
///
/// Politique, refus et statuts sont donc IDENTIQUES à ceux de
/// [enregistrerVerdictGain] sur `UserPrediction` — c'est exactement ce que
/// vérifient les tests B4.4/8.x, qui font tourner les DEUX modèles sur les
/// mêmes verdicts et comparent statut par statut.
///
/// ★ UNE SEULE DIFFÉRENCE, VOULUE ET DOCUMENTÉE : cette fonction ne touche
///   JAMAIS `isGagne`, ni `dividendePmuReel`, ni `messageResultat`. Ces trois
///   champs appartiennent au chemin historique d'affichage et à l'IA ; les
///   modifier ici reviendrait à changer un calcul de gain existant, ce que la
///   consigne interdit. Le verdict structuré est écrit à côté, pas à la place.
ResultatEnregistrementVerdictSuivi enregistrerVerdictGainSuivi({
  required TrackedCourse ticket,
  required VerdictGain verdict,
  List<RapportPublie> rapportsOfficiels = const <RapportPublie>[],
  int? miseBaseCentimesOfficielle,
}) {
  final decision = deciderEcritureVerdict(
    etatExistant: ticket.etatGain,
    etatTirelireExistant: ticket.etatTirelire,
    motifExistant: ticket.motifNonDetermination,
    rapportsExistants: ticket.rapportsAttribues,
    verdict: verdict,
    rapportsOfficiels: rapportsOfficiels,
    miseBaseCentimesOfficielle: miseBaseCentimesOfficielle,
  );

  if (decision.estDejaIdentique) {
    return ResultatEnregistrementVerdictSuivi._(
      ticket: ticket, // l'original, non copié : rien n'a changé
      statut: StatutEnregistrementVerdict.dejaIdentique,
      motif: null,
      persistanceComplete: true,
      informationsNonPersistees: const <String>[],
    );
  }

  if (!decision.estEnregistre) {
    return ResultatEnregistrementVerdictSuivi._(
      ticket: ticket,
      statut: decision.statut,
      motif: decision.motif,
      persistanceComplete: false,
      informationsNonPersistees: const <String>[],
    );
  }

  final e = decision.ecriture!;
  return ResultatEnregistrementVerdictSuivi._(
    ticket: ticket.copyWith(
      etatGain: e.etat,
      motifNonDetermination: e.motif,
      etatTirelire: e.etatTirelire,
      rapportsAttribues: e.rapportsAttribues,
      dividendeGagnant: e.dividendeGagnant,
      dividendePlace: e.dividendePlace,
      miseBaseCentimesUtilisee: e.miseBaseCentimesUtilisee,
      // ★ CHANTIER 1/3 — même propagation que pour `UserPrediction` : le
      //   remboursement établi par le verdict doit survivre à l'écriture sur
      //   le ticket suivi. Sans cette ligne, un remboursement démontré
      //   disparaîtrait au premier enregistrement de verdict.
      remboursementPmu: e.remboursement,
    ),
    statut: StatutEnregistrementVerdict.enregistre,
    motif: null,
    // ⚠️ `explication` n'a AUCUN champ B-1 : on ne prétend pas une
    //    persistance complète. `total`, lui, se reconstitue exactement.
    persistanceComplete: false,
    informationsNonPersistees: const <String>['explication'],
  );
}

// ═══════════════════════════════════════════════════════════════════════════
//  4. ★ BARRIÈRE D'IDENTITÉ ENTRE `UserPrediction` ET `TrackedCourse`
//
//  CONSIGNE §3, VERBATIM :
//  « Vérifier les règles permettant d'associer un UserPrediction et un
//    TrackedCourse au même pari. Ne jamais supposer qu'ils correspondent
//    uniquement parce qu'ils concernent la même course. Contrôler les
//    identifiants disponibles, le type de pari, les numéros joués et les
//    mises. En cas d'association ambiguë, ne pas propager un verdict. Ne pas
//    créer de synchronisation automatique entre les deux modèles sans preuve
//    de leur identité. »
//
//  ── MESURES QUI FONDENT CETTE SECTION ────────────────────────────────────
//
//  1. `grep -c "storageKey" lib/models/pmu_models.dart`              → 0
//     `UserPrediction` ne porte AUCUNE trace de la clé du ticket suivi.
//
//  2. `grep -c "predId\|predictionId\|userPredictionId"
//      lib/services/alert_service.dart`                              → 0
//     `TrackedCourse` ne porte AUCUNE trace de l'identifiant utilisateur.
//
//  ⇒ Il n'existe AUCUNE clé étrangère croisée. Aucune fonction ne peut
//    aujourd'hui affirmer « ces deux objets sont le même pari ».
//
//  3. Les deux identifiants qui pourraient y ressembler sont produits par
//     DEUX appels distincts à `DateTime.now()`, dans le même flux :
//        bet_bottom_sheet.dart:3126  predId =
//            '${_courseKey}_${DateTime.now().millisecondsSinceEpoch}'
//        bet_bottom_sheet.dart:3116  → `ajouterSuivi` construit
//            storageKey = '${baseKey}_${DateTime.now().millisecondsSinceEpoch}'
//     Ils partagent le PRÉFIXE (`_courseKey` ici, `baseKey` là — même valeur
//     textuelle `R{r}C{c}_ddmmyyyy`), mais les deux millisecondes sont lues
//     séparément : les chaînes complètes sont, en pratique, toujours
//     différentes. Aucun rapprochement par préfixe n'est probant : le préfixe
//     identifie une COURSE, pas un PARI.
//
//  4. Six paris sur la même course sont LÉGITIMES et prévus :
//        `addPrediction` (pmu_provider.dart:340) — « plusieurs paris sur la
//        même course autorisés » ;
//        `ajouterSuivi` (alert_service.dart:735) — une clé datée par appel.
//     La course ne peut donc JAMAIS servir d'identité de pari.
//
//  ── CONSÉQUENCE ASSUMÉE ──────────────────────────────────────────────────
//  [identitePari] rend `null` — donc aucune propagation n'est autorisée —
//  dans TOUS les cas mesurables aujourd'hui. Ce n'est pas une prudence de
//  style, c'est le résultat des mesures ci-dessus. Les critères sont écrits
//  de façon exhaustive pour qu'un futur identifiant réellement partagé
//  suffise à ouvrir la porte sans réécrire la règle — et pour qu'AUCUN autre
//  critère ne puisse la fonder à sa place.
//
//  ★ AUCUN MÉCANISME DE PROPAGATION N'EST CRÉÉ DANS CE LOT. Ce n'est pas un
//    oubli : propager exigerait de RECONSTITUER un `VerdictGain` depuis des
//    champs persistés (composantes, rôles, total). Une telle reconstitution
//    inventerait ce que le moteur B-3 avait décidé, ce qui est exactement le
//    contraire de la règle fondamentale. Les tests B4.4/10.x le prouvent :
//    il n'existe aucun chemin de synchronisation automatique.
// ═══════════════════════════════════════════════════════════════════════════

/// Preuve qu'un `UserPrediction` et un `TrackedCourse` désignent le MÊME pari.
///
/// Cette classe ne peut être construite QUE par [identitePari], et seulement
/// lorsqu'un identifiant réellement partagé compare égal. Le TYPE porte donc
/// la preuve : il est impossible d'« affirmer » une identité sans la démontrer.
class IdentitePari {
  /// L'identifiant qui a permis la démonstration (jamais vide).
  final String identifiantPartage;

  const IdentitePari._(this.identifiantPartage);

  @override
  String toString() => 'IdentitePari($identifiantPartage)';
}

/// Démontre — ou refuse de démontrer — que [prediction] et [course] sont le
/// même pari.
///
/// Rend une [IdentitePari] UNIQUEMENT si les QUATRE conditions tiennent :
///   1. les deux modèles portent un identifiant partagé non vide et ÉGAL —
///      champ qui n'existe pas dans le schéma actuel (cf. mesures) ;
///   2. le type de pari est identique et non vide ;
///   3. les numéros joués sont identiques, DANS LE MÊME ORDRE ;
///   4. les mises sont identiques au centime près.
///
/// Rend `null` sinon ; `null` signifie « aucune propagation autorisée ».
///
/// ⚠️ Les conditions 2 à 4 NE FONDENT JAMAIS l'identité : elles ne peuvent
///    que la RÉFUTER. Deux paris différents sur la même course, avec le même
///    type, les mêmes numéros et la même mise, restent deux paris différents —
///    l'utilisateur a le droit de jouer deux fois le même pari. C'est
///    l'application littérale de la consigne : « ne jamais supposer qu'ils
///    correspondent uniquement parce qu'ils concernent la même course ».
IdentitePari? identitePari({
  required UserPrediction prediction,
  required TrackedCourse course,
}) {
  // ── Condition 1 : identifiant partagé ───────────────────────────────────
  //
  // MESURE : aucun champ de ce type n'existe. `UserPrediction.id` est un
  // identifiant PROPRE au profil (timestamp), `TrackedCourse.storageKey` un
  // identifiant PROPRE au suivi (autre timestamp). Aucun n'a de correspondant
  // dans l'autre modèle — vérifié par les deux greps vides cités plus haut.
  //
  // La comparaison est écrite malgré tout : le jour où un identifiant
  // partagé existera, cette porte s'ouvrira sans réécriture de la règle.
  final identifiantPartage = _identifiantReellementPartage(
    idPrediction: prediction.id,
    idSuivi: course.storageKey ?? '',
  );
  if (identifiantPartage == null) return null;

  // ── Condition 2 : type de pari identique, non vide ──────────────────────
  final typePrediction = prediction.typePari.trim();
  final typeSuivi = course.typePari.trim();
  if (typePrediction.isEmpty || typeSuivi.isEmpty) return null;
  if (typePrediction != typeSuivi) return null;

  // ── Condition 3 : numéros joués identiques, dans le MÊME ORDRE ──────────
  //
  // L'ordre compte : `numerosJoues` est ordonné pour les paris qui imposent un
  // ordre à la saisie (Tiercé, Quarté+, Quinté+ — cf. `exigeOrdreExactSaisie`).
  // Comparer en ensemble ferait passer `[1,2,3]` et `[3,2,1]` pour identiques.
  if (prediction.numerosJoues.length != course.numerosJoues.length) {
    return null;
  }
  for (var i = 0; i < prediction.numerosJoues.length; i++) {
    if (prediction.numerosJoues[i] != course.numerosJoues[i]) return null;
  }

  // ── Condition 4 : mises identiques au centime près ──────────────────────
  //
  // Deux pièges évités :
  //   • `montantMise` de `UserPrediction` vaut `0.0` par défaut : un ticket
  //     sans mise saisie (race_detail_screen.dart:409 documente
  //     explicitement « montantMise n'est PAS renseigné ») ne peut pas être
  //     comparé à une mise réelle. Zéro n'est pas une mise, c'est une absence.
  //   • `Gagnant+Placé` engage `miseGagnant` ET `misePlace` : la mise totale
  //     réellement engagée est la SOMME, jamais l'une des deux. Comparer
  //     `miseEngagee` seul déclarerait identiques un G+P et un Simple Gagnant
  //     de même montant affiché.
  final misePrediction = prediction.montantMise;
  final miseSuivi = course.miseEngagee;
  if (misePrediction <= 0 || miseSuivi == null || miseSuivi <= 0) return null;
  if (!_memeMise(misePrediction, miseSuivi)) return null;

  // ── Condition 4 bis : ventilation Gagnant / Placé cohérente ─────────────
  //
  // Si l'un des deux modèles porte une ventilation, l'autre doit porter la
  // MÊME. Une ventilation partielle (un seul côté renseigné) est une
  // divergence, pas une tolérance.
  final predG = prediction.miseGagnant;
  final predP = prediction.misePlace;
  final suiviG = course.miseGagnant;
  final suiviP = course.misePlace;
  final predVentilee = predG != null || predP != null;
  final suiviVentile = suiviG != null || suiviP != null;
  if (predVentilee != suiviVentile) return null;
  if (predVentilee) {
    if (predG == null || suiviG == null) return null;
    if (predP == null || suiviP == null) return null;
    if (!_memeMise(predG, suiviG)) return null;
    if (!_memeMise(predP, suiviP)) return null;
  }

  return IdentitePari._(identifiantPartage);
}

/// Les deux chaînes sont-elles le MÊME identifiant partagé, NON VIDE ?
///
/// Rend `null` si l'un est vide : une chaîne vide ne prouve rien. C'est le
/// piège exact du préfixe `R{r}C{c}_ddmmyyyy` commun aux deux modèles — il
/// identifie une COURSE, pas un PARI, et ne doit jamais être accepté seul.
String? _identifiantReellementPartage({
  required String idPrediction,
  required String idSuivi,
}) {
  final a = idPrediction.trim();
  final b = idSuivi.trim();
  if (a.isEmpty || b.isEmpty) return null;
  if (a != b) return null;
  return a;
}

/// Égalité de deux mises, au centime près, SANS division flottante.
///
/// On compare en centimes ENTIERS : `(a * 100).round() == (b * 100).round()`.
/// Un écart d'un centime est un écart, pas un arrondi.
bool _memeMise(double a, double b) => (a * 100).round() == (b * 100).round();
