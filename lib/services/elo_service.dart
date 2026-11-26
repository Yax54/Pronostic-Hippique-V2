// ═══════════════════════════════════════════════════════════════════
//  ELO SERVICE — v9.92
//
//  ★ v9.92 : ELO par discipline — clé = "NOM_CHEVAL|DISCIPLINE"
//    Un cheval qui passe du Trot Attelé au Plat repart à 1500
//    sur la nouvelle discipline. Les ELO ne se polluent plus.
//    K-factor par discipline conservé (48 débutant, 32 confirmé).
//    Rétrocompatibilité : anciens ELO sans discipline → clé globale
//    conservée en lecture, mais les nouvelles mises à jour utilisent
//    la clé disciplinée.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/zt_models.dart';
// ★ Raccordement du dépôt structuré (pont ELO). Voir pont_elo.dart pour la
// justification : la persistance principale reste SharedPreferences, le dépôt
// est un miroir d'écriture consultable en lecture indexée.
import '../data/connaissances/_adapters/pont_elo.dart';
import '../data/connaissances/_migration/bascule_elo.dart';
// ★ A7 (3.3-B2-b) : validation de la date portée par une `courseKey`.
//   `date_utils.dart` n'a AUCUN import (mesuré) : aucune dépendance circulaire.
import '../utils/date_utils.dart' show dateDepuisCourseKey;
// ★ A7 (3.3-B2-d1) : lecture du diagnostic pré-import.
//   `elo_empreinte.dart` n'importe que `dart:typed_data` et `zt_models.dart`
//   (verrou T-S5) ; `elo_registre_v3.dart` n'importe que `dart:convert`
//   (verrou T-S4). Aucune de ces deux bibliothèques n'importe un service :
//   aucun cycle n'est créé par ces deux ajouts.
// ★ X1-b : `octetsUtf8` est ajoutée à la liste `show`. Elle EXISTAIT déjà
//   (elo_empreinte.dart l.164) et n'était lue par aucun code de production
//   (mesuré : 1 seule occurrence dans `lib/`, sa définition). Aucun cycle :
//   `elo_empreinte.dart` n'importe ni service ni écran (verrou T-S5).
import '../utils/elo_empreinte.dart' show empreinte64Ratings, octetsUtf8;
// ★ A7 (3.3-B2-d2) : le registre est désormais ÉCRIT — mais seulement pour y
//   AJOUTER une entrée `horsCourse`. Aucune fonction de ce modèle ne rend des
//   ratings (verrou T-S6) : le registre reste un TÉMOIN, jamais une source.
import '../models/elo_registre_v3.dart'
    show
        ChevalJournalise,
        DiagnosticCoherenceElo,
        EntreeRegistreElo,
        EtapeEntreeRegistre,
        ImageRatingElo,
        IssueEcritureElo,
        MotifHorsCourse,
        // ★ X1-b : niveau de rétention, PUREMENT INFORMATIF. `classerRetention`
        //   et `NiveauRetentionElo` existaient déjà (elo_registre_v3.dart
        //   l.885-910) et n'étaient lus par aucun code de production (mesuré :
        //   1 seule occurrence dans `lib/`, leur définition). Ajout en lecture
        //   seule : ni constante, ni valeur d'énumération n'est modifiée.
        NiveauRetentionElo,
        OrigineRegistreElo,
        RegistreEloV3,
        ResultatDiagnosticElo,
        TypeEntreeRegistre,
        classerRetention,
        diagnostiquerRegistre,
        kCleRegistreElo;

/// ★ A7 (3.2) — RÉSULTAT D'UNE TENTATIVE DE PERSISTANCE ELO.
///
/// Ce type existe parce qu'un `Future<void>` ne permet pas de distinguer une
/// écriture CONFIRMÉE d'une écriture REFUSÉE, d'une écriture en ERREUR, ou
/// d'un appel qui n'a rien eu à écrire. Aujourd'hui, l'appelant reçoit la fin
/// de la future et ne peut rien en déduire — c'est le défaut que 3.2 corrige.
///
/// ⚠️ CE QUE CES ÉTATS NE DISENT **PAS** — À LIRE AVANT TOUT USAGE
/// ────────────────────────────────────────────────────────────────
/// `refusee` et `echouee` signifient **« persistance NON CONFIRMÉE »**,
/// JAMAIS « ratings persistés inchangés ». Le stockage peut avoir écrit puis
/// répondu `false`, ou avoir levé après une écriture partielle. Aucun code ne
/// doit déduire de ces états que le disque est resté intact.
///
/// Corollaire : ces états ne constituent PAS une autorisation de rejouer
/// l'opération. 3.2 n'implémente aucun rejeu. La RAM a été modifiée dans tous
/// les cas où l'état n'est pas [nonTentee] / [abandonneeParReset] : la
/// sauvegarde SUIVANTE resérialisera `_ratings` en entier et persistera donc
/// la course dont l'écriture avait échoué. C'est un rattrapage de fait, non
/// une garantie — le journal d'intention de 3.3 est ce qui le rendra explicite.
enum EtatPersistanceElo {
  /// `setString` a répondu `true` sur `elo_ratings_v2`.
  /// C'est la SEULE valeur qui constitue une confirmation d'écriture.
  persistee,

  /// `setString` a répondu `false`. Persistance NON CONFIRMÉE.
  refusee,

  /// Une exception est survenue pendant l'écriture. Persistance NON CONFIRMÉE.
  echouee,

  /// Rien n'a été tenté : arrivée vide, ou moins de deux partants.
  /// Ce n'est PAS un échec — aucun écriture n'était justifiée.
  nonTentee,

  /// Refusée par la barrière de reset (contrôle 1 ou 2 de `_sauvegarder`).
  /// Ce n'est PAS un échec — l'écriture a été invalidée volontairement.
  abandonneeParReset,
}

// ═══════════════════════════════════════════════════════════════════════════
//  ★ A7 (3.3-B2-b) — IDENTITÉ DE COURSE VALIDÉE, PRÉPARÉE POUR LE REGISTRE.
//
//  OBJET : transformer une `courseKey` en une identité EXPLOITABLE par le futur
//  journal ELO (`numR`, `numC`, `date` ISO, discipline normalisée), ou REFUSER
//  toute identité partielle. Le lot PRÉPARE et PROUVE la validation ; il ne
//  journalise rien.
//
//  ⚠️ CE QUE CE TYPE NE FAIT PAS — À LIRE AVANT TOUTE INTERPRÉTATION
//  ─────────────────────────────────────────────────────────────────
//   • il n'accède PAS à `elo_registre_v3` : ni lecture, ni écriture, ni
//     suppression, ni migration. Il n'ajoute AUCUNE clé SharedPreferences ;
//   • il ne décide PAS de la signification définitive de `EntreeRegistreElo.cle`
//     — cette question reste réservée à B2-d. Aucun getter composite de type
//     « clé de journal » n'est donc exposé ici : seulement les CONSTITUANTS ;
//   • il n'invente JAMAIS un constituant. Si `numR`, `numC` ou la date manque,
//     [tenter] rend `null`. Aucune valeur par défaut, aucun `R0C0`, aucune
//     date de remplacement (règle D-B2-1 : pas de clé fictive).
//
//  RÈGLES DE VALIDATION — MESURÉES, PAS SUPPOSÉES
//  ──────────────────────────────────────────────
//   • `numR` et `numC` doivent être STRICTEMENT POSITIFS. Sont donc refusés
//     `R0C0_…`, `R0C5_…`, `R5C0_…` et `R00C5_…` (même valeur 0) ;
//   • la date doit être une date CALENDAIRE RÉELLE. La validation est DÉLÉGUÉE
//     à `dateDepuisCourseKey` (`lib/utils/date_utils.dart`), qui accepte les
//     DEUX formats déjà présents dans les données (`JJMMAAAA` et ISO) et
//     refuse `31022026`, `29022025`, `32012026`. Aucune borne d'ANNÉE n'est
//     ajoutée : ce serait une règle inventée, et `date_utils.dart` la refuse
//     explicitement pour la même raison ;
//   • la discipline est normalisée par [EloService.normaliserDiscipline] —
//     EXACTEMENT la fonction qui produit la clé ELO, donc sans divergence
//     possible entre l'identité préparée et les ratings réellement mis à jour.
//
//  ⚠️ `null` N'EST PAS UN ÉCHEC D'EXÉCUTION. C'est le résultat attendu quand
//  l'appelant ne fournit pas de `courseKey` (cas de TOUS les appels existants,
//  qui n'en passent pas) ou quand la clé n'est pas exploitable. Le comportement
//  ELO reste identique dans tous les cas : ce lot ne conditionne aucune
//  écriture à la présence d'une identité.
// ═══════════════════════════════════════════════════════════════════════════
class IdentiteCourseElo {
  const IdentiteCourseElo._({
    required this.courseKey,
    required this.numR,
    required this.numC,
    required this.date,
    required this.discipline,
  });

  /// `courseKey` d'origine, `trim()` appliqué, JAMAIS réécrite. Conservée
  /// telle quelle pour que l'identité reste traçable jusqu'à sa source.
  final String courseKey;

  /// Numéro de réunion, STRICTEMENT positif.
  final int numR;

  /// Numéro de course, STRICTEMENT positif.
  final int numC;

  /// Date ISO `AAAA-MM-JJ`, telle que rendue par `dateDepuisCourseKey`.
  /// Jamais recalculée, jamais reformatée à partir d'une autre source.
  final String date;

  /// Discipline canonique (`TROT_ATTELE`, `TROT_MONTE`, `OBSTACLE_*`, `PLAT`,
  /// ou `INCONNU` si le libellé n'est pas reconnu). `INCONNU` est une valeur
  /// RÉELLE de la normalisation de production, pas une invention de ce lot.
  final String discipline;

  /// `R{numR}C{numC}_{JJMMAAAA}[_suffixe]` — même motif que
  /// `date_utils.dart` l.85-86.
  static final RegExp _reDdMmYyyy =
      RegExp(r'^R(\d+)C(\d+)_(\d{2})(\d{2})(\d{4})(?:_.*)?$');

  /// `R{numR}C{numC}_{AAAA-MM-JJ}[_suffixe]` — même motif que
  /// `date_utils.dart` l.90-91.
  static final RegExp _reIso =
      RegExp(r'^R(\d+)C(\d+)_(\d{4})-(\d{2})-(\d{2})(?:_.*)?$');

  /// Tente de construire une identité EXPLOITABLE. Rend `null` — jamais une
  /// identité partielle — dès qu'un constituant manque ou est invalide.
  ///
  /// [courseKey] peut être `null` : c'est le cas nominal des appels existants,
  /// et le résultat est alors `null` sans aucune autre conséquence.
  static IdentiteCourseElo? tenter({
    String? courseKey,
    String discipline = '',
  }) {
    if (courseKey == null) return null;
    final cle = courseKey.trim();
    if (cle.isEmpty) return null;

    // 1. La DATE est validée par l'helper déjà éprouvé : les DEUX formats sont
    //    acceptés et une date impossible rend `null`. Aucune date inventée.
    final String? date = dateDepuisCourseKey(cle);
    if (date == null) return null;

    // 2. `numR`/`numC` proviennent de la MÊME lecture de clé que la date, avec
    //    les motifs identiques à ceux de l'helper : aucune divergence possible
    //    entre la date acceptée et les numéros acceptés.
    final Match? m = _reDdMmYyyy.firstMatch(cle) ?? _reIso.firstMatch(cle);
    if (m == null) return null;

    // `tryParse` et non `parse` : un groupe de chiffres démesuré rend `null`
    // au lieu de lever — refuser est le comportement voulu.
    final int? numR = int.tryParse(m.group(1)!);
    final int? numC = int.tryParse(m.group(2)!);
    if (numR == null || numC == null) return null;
    if (numR <= 0 || numC <= 0) return null;

    return IdentiteCourseElo._(
      courseKey: cle,
      numR: numR,
      numC: numC,
      date: date,
      discipline: EloService.normaliserDiscipline(discipline),
    );
  }

  @override
  String toString() => 'IdentiteCourseElo(numR: $numR, numC: $numC, '
      'date: $date, discipline: $discipline)';
}

/// ★ A7 (3.3-B2-d1) — DIAGNOSTIC DE L'ÉTAT ELO **AVANT** UN IMPORT.
///
/// OBJET : établir, avant toute mutation provoquée par
/// [EloService.importerDepuisBackup], si les ratings RÉELLEMENT PERSISTÉS sont
/// cohérents avec ce que le registre `elo_registre_v3` déclare. Ce type ne fait
/// que PORTER le résultat : il ne décide rien.
///
/// ⚠️ POURQUOI CE TYPE EXISTE — LA RAISON EST DATÉE, PAS ESTHÉTIQUE.
///    La cohérence d'un registre est un fait HISTORIQUE : elle compare
///    l'empreinte que le registre déclare à l'empreinte des ratings qu'il
///    prétend décrire. Après `_sauvegarder()`, le disque porte l'empreinte
///    APRÈS import ; un registre auparavant cohérent serait alors vu
///    `divergent` par construction, et la branche de réancrage deviendrait
///    inatteignable. Le diagnostic doit donc être calculé AVANT la mutation,
///    avec l'empreinte d'AVANT.
///
/// ⚠️ CE QUE CE TYPE NE FAIT PAS — À LIRE AVANT TOUTE INTERPRÉTATION.
///    • il n'ÉCRIT rien : ni `elo_registre_v3`, ni aucune autre clé ;
///    • il ne SUPPRIME rien, ne migre rien, n'invalide rien ;
///    • il n'AUTORISE ni ne BLOQUE aucune opération : [autoriseApplication] et
///      [protegeContreDoubleApplication] sont EXPOSÉS pour l'observation
///      seule. Aucun chemin de production ne les consulte dans ce lot ;
///    • il n'ajoute AUCUNE clé SharedPreferences (le compte de
///      `_toutesLesCles` reste 108) ;
///    • il ne reconstruit JAMAIS de ratings depuis le registre (verrou T-S6) ;
///    • il ne touche NI les formules ELO, NI les coefficients K, NI les
///      mécanismes d'apprentissage, NI les critères A–Q.
///
/// ⚠️ `null` NE SIGNIFIE PAS « RIEN À SIGNALER ». Il signifie « le diagnostic
///    n'a pas pu être établi », et [etablissementImpossible] en donne alors la
///    raison EXACTE. Confondre les deux ferait passer une ignorance pour une
///    absence de problème.
class DiagnosticPreImportElo {
  /// Empreinte des ratings LUS SUR LE DISQUE avant mutation, `null` si la
  /// lecture a échoué (voir [etablissementImpossible]).
  final String? empreintePersistee;

  /// Nombre de ratings LUS SUR LE DISQUE avant mutation.
  final int nombrePersistee;

  /// Empreinte des ratings EN MÉMOIRE au moment du diagnostic.
  ///
  /// Conservée pour rendre observable la distinction « RAM identique au
  /// disque » / « RAM différente du disque ». Elle n'entre dans AUCUNE
  /// décision : le diagnostic porte sur le disque, pas sur la RAM.
  final String empreinteRam;

  /// Nombre de ratings EN MÉMOIRE au moment du diagnostic.
  final int nombreRam;

  /// Verdict rendu par `diagnostiquerRegistre`, `null` si non établi.
  final ResultatDiagnosticElo? resultat;

  /// Raison de l'échec d'établissement, `null` quand [resultat] est présent.
  final String? etablissementImpossible;

  const DiagnosticPreImportElo({
    required this.empreintePersistee,
    required this.nombrePersistee,
    required this.empreinteRam,
    required this.nombreRam,
    required this.resultat,
    required this.etablissementImpossible,
  });

  /// Vrai si le diagnostic a pu être établi.
  bool get etabli => resultat != null;

  /// Vrai si la RAM reflète exactement le disque.
  ///
  /// ⚠️ FAUX NE SIGNIFIE PAS « ERREUR ». Un import peut légitimement être
  ///    demandé sur une RAM non chargée (l'import n'a pas de garde `_charge`,
  ///    limite conservée de B1). Dans ce cas c'est le DISQUE qui fait foi.
  bool get ramIdentiqueAuDisque =>
      etabli &&
      nombreRam == nombrePersistee &&
      empreinteRam == empreintePersistee;

  /// Cohérence déclarée, `null` si non établie.
  ///
  /// `null` ici ne doit JAMAIS être interprété comme `coherent`.
  DiagnosticCoherenceElo? get coherence => resultat?.coherence;

  /// Origine déclarée par le registre, `null` si non établie.
  OrigineRegistreElo? get origine => resultat?.origine;

  /// Empreinte DÉCLARÉE par le registre, `null` si le registre est absent,
  /// illisible ou si le diagnostic n'a pas pu être établi.
  ///
  /// ⚠️ `null` ne signifie donc PAS « empreinte vide » : une empreinte vide est
  ///    une valeur (`16ed60fcfaed47f4`), pas une absence.
  String? get empreinteRegistre => resultat?.empreinteRegistre;

  /// Valeur d'`autoriseApplication` du modèle, `null` si non établie.
  ///
  /// ⚠️ EXPOSÉ POUR L'OBSERVATION SEULE. Ce lot ne s'en sert pas pour
  ///    autoriser ou bloquer quoi que ce soit.
  bool? get autoriseApplication => resultat?.autoriseApplication;

  /// Valeur de `protegeContreDoubleApplication` du modèle, `null` si non
  /// établie. `false` est la valeur ATTENDUE en mode `historiqueInconnu`.
  bool? get protegeContreDoubleApplication =>
      resultat?.protegeContreDoubleApplication;

  @override
  String toString() {
    if (!etabli) {
      return 'DiagnosticPreImportElo(NON ÉTABLI: $etablissementImpossible, '
          'nombrePersistee: $nombrePersistee, nombreRam: $nombreRam)';
    }
    return 'DiagnosticPreImportElo(coherence: ${coherence!.name}, '
        'origine: ${origine!.name}, '
        'empreintePersistee: $empreintePersistee, '
        'empreinteRam: $empreinteRam, '
        'nombrePersistee: $nombrePersistee, nombreRam: $nombreRam, '
        'ramIdentiqueAuDisque: $ramIdentiqueAuDisque, '
        'autoriseApplication: $autoriseApplication, '
        'protege: $protegeContreDoubleApplication)';
  }
}

/// ★ A7 (3.3-B2-d2) — MOTIF EXACT POUR LEQUEL LE TÉMOIN N'A PAS ÉTÉ ÉCRIT.
///
/// Chaque valeur correspond à UNE branche mesurée de la décision. Aucun autre
/// code n'est possible : c'est ce qui rend le non-écrit AUDITABLE au lieu
/// d'être un silence.
enum MotifNonEcritureTemoin {
  /// Le registre est ABSENT : son absence est déjà honnête (le modèle rend
  /// `registreAbsent`), et écrire créerait une preuve historique rétroactive
  /// que rien ne justifie. Décision D5 retenue : on n'écrit pas.
  registreAbsent,

  /// Le registre était DÉJÀ DIVERGENT avant l'import. Sa cause est inconnue :
  /// un réancrage automatique effacerait une information, c'est interdit.
  dejaDivergent,

  /// Le registre est ILLISIBLE. Le contrat du modèle impose de ne le ni
  /// supprimer, ni réparer, ni réinterpréter.
  corrompu,

  /// Le registre est d'un SCHÉMA ou d'une VERSION inconnus. Même raison.
  schemaIncompatible,

  /// Le diagnostic pré-import n'a pas pu être établi. `null` n'autorise rien.
  diagnosticNonEtabli,

  /// Les ratings n'ont PAS été persistés — donc aucune opération n'a eu lieu,
  /// et attester d'une empreinte serait attester d'un fait inconnu.
  ratingsNonPersistes,

  /// L'import n'a pas changé les ratings : aucune écriture inutile.
  aucunChangement,

  /// L'allocation d'un `id` ou d'une `horloge` a échoué (collision,
  /// débordement, registre incohérent). On n'écrit pas : mieux vaut aucun
  /// témoin qu'un identifiant faux.
  allocationImpossible,

  /// Le contrôle de génération a refusé l'écriture : un reset est intervenu
  /// après la persistance des ratings. Écrire recréerait la clé effacée.
  abandonneParReset,

  /// La sérialisation du registre a levé (`jsonEncode` sur `NaN`/`Infinity`,
  /// mesuré et documenté par le modèle lui-même).
  serialisationImpossible,

  /// Le stockage a REFUSÉ l'écriture (`setString` a rendu `false`).
  refuseeParStockage,

  /// L'écriture a LEVÉ une exception.
  echoueeParException,

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ A7 (3.3-C12 / A7-39) — MOTIFS DU REFUS ANTICIPÉ D'UN REGISTRE ENRICHI.
  //
  //  Ces trois valeurs n'existent QUE pour la branche d'import d'une
  //  sauvegarde PORTANT un registre (`_elo_registre`). Elles sont produites
  //  AVANT toute mutation des ratings : c'est ce qui les distingue de
  //  `ratingsNonPersistes`, qui suppose la mutation déjà faite.
  //
  //  ⚠️ PORTÉE EXACTE — AUCUNE DE CES VALEURS N'EST UNE ISSUE D'ÉCRITURE.
  //     Elles décrivent un NON-ÉCRIT DÉLIBÉRÉ dans lequel aucune écriture
  //     n'a été TENTÉE, ni sur `elo_ratings_v2`, ni sur `elo_registre_v3`.
  //     Les confondre avec `refuseeParStockage` ferait lire « le stockage a
  //     refusé » là où, en réalité, il n'a jamais été sollicité.
  // ══════════════════════════════════════════════════════════════════════════

  /// Le registre transporté par la sauvegarde n'est pas une chaîne : son type
  /// est inattendu. Même exigence que
  /// [DiagnosticPreImportElo.etablissementImpossible] : un type inattendu rend
  /// le diagnostic NON ÉTABLI, il ne se devine jamais.
  registreEnrichiNonTextuel,

  /// Le registre transporté par la sauvegarde est ILLISIBLE, ou d'un `schema`
  /// / d'une `version` que le code courant ne sait pas interpréter.
  ///
  /// ⚠️ Ni réparé, ni réinterprété, ni remplacé par un registre neuf : le
  ///    contrat du modèle l'interdit explicitement.
  registreEnrichiIllisible,

  /// Le registre transporté est lisible et interprétable, mais son empreinte
  /// ne décrit PAS les ratings de la même sauvegarde.
  ///
  /// Sauvegarde auto-incohérente : aucune valeur de référence n'existe, donc
  /// aucun recalage n'est possible — et il est interdit.
  registreEnrichiIncoherent,

  /// La RELECTURE du stockage n'a pas confirmé que les ratings persistés sont
  /// bien ceux qui viennent d'être importés.
  ///
  /// ⚠️ Ce motif n'est PAS redondant avec [ratingsNonPersistes] : celui-ci
  ///    couvre `setString` qui a répondu `false` ou qui a levé. Ici, `setString`
  ///    a répondu `true` — mais un booléen n'est pas une preuve de CONTENU.
  ///    La relecture est donc la seule preuve admise avant d'écrire dans le
  ///    registre une empreinte qui prétend décrire le disque.
  relectureNonConfirmee,
}

/// ★ A7 (3.3-B2-d2) — RÉSULTAT COMPLET D'UN IMPORT, SANS CHANGER SON RETOUR.
///
/// ⚠️ POURQUOI CE TYPE EXISTE AU LIEU D'UN RETOUR ENRICHI.
///    `importerDepuisBackup` rend `Future<EtatPersistanceElo>`, et
///    `backup_service.dart` (l.1107-1145) en fait un `switch` EXHAUSTIF sur
///    les 5 valeurs de l'enum. Changer le retour OU ajouter une valeur
///    casserait la compilation d'un fichier que ce lot n'a pas le droit de
///    modifier. Le résultat complet est donc publié À CÔTÉ, exactement comme
///    [EloService.dernierDiagnosticPreImport] l'est depuis B2-d1.
///
/// ⚠️ CE QUE [operationSecurisee] NE DIT **JAMAIS**.
///    Elle ne revendique AUCUNE protection contre une double application. En
///    mode `historiqueInconnu`, [protegeContreDoubleApplication] vaut `false`
///    PAR CONSTRUCTION, et une réussite des deux persistances ne change rien à
///    cela : le témoin constate l'opération, il ne prémunit pas contre une
///    réapplication historique, qui reste INDÉTECTABLE.
class ResultatImportElo {
  /// État rendu par `_sauvegarder()` pour les RATINGS. Toujours renseigné.
  final EtatPersistanceElo etatRatings;

  /// Issue de l'écriture du TÉMOIN, `null` si elle n'a PAS été TENTÉE.
  final IssueEcritureElo? issueTemoin;

  /// Motif EXACT de l'absence de témoin persisté.
  ///
  /// ⚠️ DEUX FAMILLES, DISCTINCTES ET COMPLÉMENTAIRES — les confondre ferait
  ///    lire une tentative échouée comme un refus délibéré :
  ///    • [issueTemoin] `null` ⇒ le témoin n'a jamais été tenté, et
  ///      [motifNonEcriture] porte la RAISON de ce non-écrit (liste blanche
  ///      de `_doitEcrireTemoin`, allocation impossible, sérialisation, reset) ;
  ///    • [issueTemoin] non `null` et non `persistee` ⇒ le témoin A ÉTÉ tenté
  ///      et a échoué, et [motifNonEcriture] vaut alors
  ///      [MotifNonEcritureTemoin.refuseeParStockage] ou
  ///      [MotifNonEcritureTemoin.echoueeParException].
  ///    `null` n'est donc rendu QUE lorsque [issueTemoin] vaut `persistee`.
  final MotifNonEcritureTemoin? motifNonEcriture;

  /// Cohérence constatée AVANT l'import, `null` si le diagnostic n'était pas
  /// établi.
  final DiagnosticCoherenceElo? coherenceAvant;

  /// Empreinte des ratings AVANT l'import (disque), si établie.
  final String? empreinteAvant;

  /// Empreinte des ratings APRÈS l'import (RAM venant d'être persistée), si
  /// l'import a été mené à son terme.
  final String? empreinteApres;

  /// Origine appliquée au registre par le réancrage, `null` si aucun
  /// réancrage n'a eu lieu.
  final OrigineRegistreElo? origineAppliquee;

  /// Valeur de `protegeContreDoubleApplication` APRÈS l'opération. `false`
  /// est la valeur ATTENDUE et HONNÊTE en `historiqueInconnu`.
  final bool protegeApres;

  const ResultatImportElo({
    required this.etatRatings,
    required this.issueTemoin,
    required this.motifNonEcriture,
    required this.coherenceAvant,
    required this.empreinteAvant,
    required this.empreinteApres,
    required this.origineAppliquee,
    required this.protegeApres,
  });

  /// Vrai si les ratings ET le témoin ont été persistés.
  ///
  /// ⚠️ NE PAS lire cette valeur comme « protégé ». Voir la documentation de
  ///    la classe : elle ne dit rien de la protection anti-double-application.
  bool get operationSecurisee =>
      etatRatings == EtatPersistanceElo.persistee &&
      issueTemoin == IssueEcritureElo.persistee;

  /// Vrai si les ratings sont persistés mais que le témoin ne l'est pas.
  /// C'est l'état « à moitié sécurisé », qui ne doit JAMAIS être présenté
  /// comme un succès complet.
  bool get ratingsSeulsPersistes =>
      etatRatings == EtatPersistanceElo.persistee &&
      issueTemoin != IssueEcritureElo.persistee;

  @override
  String toString() => 'ResultatImportElo(etatRatings: ${etatRatings.name}, '
      'issueTemoin: ${issueTemoin?.name ?? "NON TENTÉ"}, '
      'motifNonEcriture: ${motifNonEcriture?.name ?? "-"}, '
      'coherenceAvant: ${coherenceAvant?.name ?? "-"}, '
      'origineAppliquee: ${origineAppliquee?.name ?? "-"}, '
      'protegeApres: $protegeApres, '
      'operationSecurisee: $operationSecurisee)';
}

/// ★ A7 (3.3-B2-d2) — ALLOCATION DÉTERMINISTE DES IDENTIFIANTS DU REGISTRE.
///
/// ⚠️ POURQUOI CE TYPE EXISTE.
///    Le modèle ne fournit AUCUN allocateur (mesuré : 0 occurrence de
///    `prochainId` / `maxId` / `allouer`), et `EntreeRegistreElo.id` est un
///    `int` NON NULLABLE sans contrainte d'unicité vérifiée à la
///    désérialisation. L'allocation doit donc être décidée ICI, et nulle part
///    ailleurs, pour rester vérifiable.
///
/// ⚠️ RÈGLES RETENUES, ET LEUR JUSTIFICATION MESURÉE.
///    • `id` : `max(id) + 1`, ou `0` si la liste est vide. `entreePourCle`
///      (modèle l.540) compare `entree.id > trouvee.id` pour élire la PLUS
///      RÉCENTE : une suite strictement croissante est donc la seule qui
///      préserve cette sémantique. Aucun identifiant existant n'est réutilisé.
///    • `horloge` : `horloge + 1`, une unité par entrée ajoutée. `vierge()`
///      part de `0` (modèle l.500), donc la progression reste stricte.
///
/// ⚠️ REFUS PLUTÔT QUE DEVINETTE. Si l'allocation ne peut pas être prouvée
///    sûre (débordement, identifiants incohérents, collision), l'objet rend
///    `null` et AUCUNE écriture n'a lieu. Un témoin absent est préférable à un
///    témoin portant un identifiant faux.
class AllocationEntreeElo {
  final int id;
  final int horloge;

  const AllocationEntreeElo._(this.id, this.horloge);

  /// Alloue le prochain couple `(id, horloge)` pour [registre], ou `null`.
  ///
  /// Ne lève pas : un registre incohérent est un REFUS, pas une exception.
  static AllocationEntreeElo? pour(RegistreEloV3 registre) {
    final int horloge = registre.horloge;
    // `horloge + 1` doit rester un entier positif représentable. En Dart, un
    // `int` est un entier 64 bits sur la VM et un double sûr jusqu'à 2^53 sur
    // le Web : on refuse la valeur qui ne serait plus exactement représentable
    // sur les deux plateformes.
    if (horloge < 0 || horloge >= kHorlogeMaxElo) return null;

    if (registre.entrees.isEmpty) {
      return AllocationEntreeElo._(0, horloge + 1);
    }

    int maxId = -1;
    for (final entree in registre.entrees) {
      if (entree.id < 0) return null; // identifiant négatif : registre suspect
      if (entree.id > maxId) maxId = entree.id;
    }
    if (maxId >= kIdMaxElo) return null;

    return AllocationEntreeElo._(maxId + 1, horloge + 1);
  }

  @override
  String toString() => 'AllocationEntreeElo(id: $id, horloge: $horloge)';
}

/// Borne haute de sécurité pour `horloge`. `2^53` est la limite au-delà de
/// laquelle un `int` cesse d'être exactement représentable en JavaScript.
const int kHorlogeMaxElo = 9007199254740992; // 2^53

/// Borne haute de sécurité pour `id`, pour la même raison.
const int kIdMaxElo = 9007199254740992; // 2^53

/// ★ A7 (3.3-B2-e) — MOTIF NOMMÉ D'UN REFUS D'APPLICATION ELO.
///
/// ⚠️ POURQUOI UN TYPE NOUVEAU, ET PAS UNE EXTENSION DE `EtatPersistanceElo`.
///    `EtatPersistanceElo` possède un `switch` EXHAUSTIF dans
///    `backup_service.dart` (l.1101-1145), fichier gelé. Ajouter une valeur OU
///    changer le type de retour de `mettreAJourApresArrivee` casserait la
///    compilation d'un fichier interdit. Le motif de refus est donc publié par
///    un OBSERVABLE SÉPARÉ, exactement comme `dernierResultatImport` en B2-d2.
///
/// ⚠️ TOUS CES MOTIFS SIGNIFIENT « AUCUNE MUTATION ELO ». Un refus n'écrit
///    jamais de ratings : il rend l'opération non tentée, jamais à moitié faite.
enum MotifRefusApplicationElo {
  /// Aucun `courseKey` fourni, ou clé inexploitable (motif, date, numéros).
  /// Aucune identité ⇒ aucune journalisation possible ⇒ aucune application.
  identiteNonExploitable,

  /// Le registre persisté n'a pas pu être lu ou décodé. Ce n'est PAS une
  /// absence : une erreur de lecture n'autorise jamais un amorçage.
  registreIllisible,

  /// Le registre existant est `divergent`, `corrompu` ou `schemaIncompatible`.
  /// Refus SANS réparation, SANS remplacement, SANS migration (§4, §11).
  registreNonCoherent,

  /// Un registre `course` existe déjà pour cette clé, à l'état `appliquee`
  /// OU incertain (`intention`, `nonConfirmee`). Les trois états bloquent.
  courseDejaJournalisee,

  /// La date de la course est postérieure à la date de référence disponible.
  /// ⚠️ Garde d'ANTÉRIORITÉ, JAMAIS une preuve de non-réapplication (§3, §7).
  datePosterieure,

  /// L'écriture de l'entrée `intention` a échoué ou levé. Aucune mutation.
  intentionNonPersistee,

  /// L'allocation d'un `(id, horloge)` sûr a été refusée (débordement,
  /// identifiants suspects). Refus plutôt que devinette.
  allocationImpossible,

  /// L'amorçage du registre (cas A ou B) n'a pas pu être persisté.
  /// Sans registre persisté, aucune journalisation n'est possible ⇒ refus.
  amorcageNonPersiste,

  /// La sérialisation du registre a levé (ex. `NaN`/`Infinity` dans une image).
  serialisationImpossible,
}

/// ★ A7 (3.3-B2-e) — RÉSULTAT COMPOSITE D'UNE APPLICATION ELO APRÈS ARRIVÉE.
///
/// Le type de retour public de `mettreAJourApresArrivee` reste
/// `EtatPersistanceElo` (contrat inchangé). Ce type porte les faits que
/// l'enum ne peut pas exprimer : le motif d'un refus, l'état du registre, et
/// si une entrée `course` a été durablement journalisée.
class ResultatApplicationElo {
  /// Issue de la persistance des ratings (inchangée par B2-e).
  final EtatPersistanceElo etatRatings;

  /// Motif du refus, ou `null` si l'opération a été tentée.
  final MotifRefusApplicationElo? motifRefus;

  /// Cohérence du registre AVANT décision. `null` si le diagnostic n'a pas
  /// pu être établi (lecture en échec) — ce cas est un refus, pas un silence.
  final DiagnosticCoherenceElo? coherenceAvant;

  /// Origine du registre au moment de la décision. INDICATEUR D'AFFICHAGE
  /// SEULEMENT : conformément à l'option 1 arbitrée, `historiqueInconnu` ne
  /// constitue JAMAIS à lui seul un motif de refus.
  final OrigineRegistreElo? origineAvant;

  /// `true` ssi un registre a été créé par cette opération (cas A ou B).
  final bool amorcageEffectue;

  /// Étape finale de l'entrée `course` écrite, ou `null` si aucune écriture.
  final EtapeEntreeRegistre? etapeEntree;

  /// Identifiant de l'entrée `course` écrite, ou `null`.
  final int? idEntree;

  /// `true` ssi l'entrée `course` de cette opération a été persistée ET
  /// finalisée en `appliquee`. Seul état qui rend la protection effective.
  final bool journalisationConfirmee;

  const ResultatApplicationElo({
    required this.etatRatings,
    required this.motifRefus,
    required this.coherenceAvant,
    required this.origineAvant,
    required this.amorcageEffectue,
    required this.etapeEntree,
    required this.idEntree,
    required this.journalisationConfirmee,
  });

  /// Vrai ssi aucune mutation ELO n'a eu lieu.
  bool get refusee => motifRefus != null;

  /// Vrai ssi les ratings ont été persistés, que la journalisation soit
  /// confirmée ou non.
  bool get ratingsPersistes => etatRatings == EtatPersistanceElo.persistee;

  /// ⚠️ Vrai ssi l'opération est COMPLÈTEMENT protégée : ratings persistés ET
  /// entrée finalisée. Un `true` ici est la seule base licite pour affirmer
  /// qu'une réapplication sera refusée.
  bool get protectionEffective => ratingsPersistes && journalisationConfirmee;

  @override
  String toString() => 'ResultatApplicationElo(etatRatings: ${etatRatings.name}, '
      'motifRefus: ${motifRefus?.name ?? "-"}, '
      'coherenceAvant: ${coherenceAvant?.name ?? "-"}, '
      'origineAvant: ${origineAvant?.name ?? "-"}, '
      'amorcage: $amorcageEffectue, '
      'etapeEntree: ${etapeEntree?.name ?? "-"}, '
      'idEntree: ${idEntree?.toString() ?? "-"}, '
      'journalisationConfirmee: $journalisationConfirmee)';
}

/// ★ A7 (3.3-B2-e) — INTENTION D'APPLICATION PRÉPARÉE, AVANT TOUTE MUTATION.
///
/// Porte les trois faits nécessaires aux phases B et D :
///  • [id] — identifiant de l'entrée, alloué UNE SEULE FOIS ;
///  • [registreAvecIntention] — registre à persister en phase B (étape
///    `intention`, sans `issue` ni `tsFinal`) ;
///  • [empreinteApres] — la PROMESSE d'empreinte, calculée sans toucher les
///    ratings, qui sera relue et vérifiée après la mutation.
///
/// ⚠️ [chevaux] et [empreinteAvant] sont conservés pour construire l'entrée
///    finale en phase D sans recalculer quoi que ce soit : la finalisation doit
///    compléter la MÊME entrée, pas en construire une autre.
class IntentionEntreeElo {
  final int id;
  final RegistreEloV3 registreAvecIntention;
  final String empreinteAvant;
  final String empreinteApres;
  final List<ChevalJournalise> chevaux;
  final IdentiteCourseElo identite;
  final int horloge;
  final int tsIntention;

  const IntentionEntreeElo({
    required this.id,
    required this.registreAvecIntention,
    required this.empreinteAvant,
    required this.empreinteApres,
    required this.chevaux,
    required this.identite,
    required this.horloge,
    required this.tsIntention,
  });
}

/// ★ A7 (3.3-C9) — CLÉS DU FORMAT D'EXPORT `elo_v2`.
///
/// Privées à la bibliothèque : elles ne font pas partie de l'API publique du
/// service. Les tests emploient les littéraux, ce qui les rend indépendants
/// d'un éventuel renommage — et donc capables de détecter un renommage.
const String _kCleMarqueurFormat = '_elo_format';
const String _kCleMarqueurRegistre = '_elo_registre';
const String _kCleMarqueurTs = '_elo_ts';

/// Valeur du marqueur de format. Un export ancien (sans ce marqueur) reste
/// lisible : c'est le lecteur qui doit traiter l'absence, pas l'écrivain.
const String _kFormatEloV2 = 'elo_v2';

/// ★ A7 (3.3-C9) — STATUT D'UN EXPORT ELO ENRICHI.
///
/// Quatre valeurs SEULEMENT, et une seule autorise un groupe exportable
/// complet. Ce type existe parce que `exporterPourBackup()` rend une
/// `Map<String, dynamic>` : une map n'a AUCUN emplacement pour dire « je n'ai
/// pas pu lire le registre » ou « le registre est divergent ». Sans ce type,
/// le troisième cas produirait une sauvegarde d'apparence normale, ce qui est
/// précisément ce qu'il faut interdire.
///
/// ⚠️ `refusee` et `indisponible` ne sont PAS la même chose :
///   • `refuse`         → on a PU regarder, et ce qu'on a vu est inutilisable
///                        (corrompu, incompatible, divergent). Le refus est
///                        un FAIT mesuré, pas une incertitude.
///   • `diagnosticImpossible` → on n'a PAS pu regarder (stockage indisponible,
///                        `reload()` en échec, registre d'un type inattendu).
///                        Aucune conclusion n'est tirée, aucune donnée ELO
///                        n'est exportée, PAS MÊME L'HORODATAGE.
enum StatutExportElo {
  /// Registre PRÉSENT, interprétable et cohérent avec les ratings du disque.
  /// Seul statut qui autorise `_elo_registre` dans le groupe exporté.
  complet,

  /// Le registre est RÉELLEMENT ABSENT et le diagnostic a pu être établi.
  /// On exporte les ratings sans registre — on n'en invente aucun.
  sansRegistre,

  /// Le registre existe mais est INUTILISABLE. Aucun groupe exportable.
  /// Cause exacte portée par [ResultatExportElo.motif].
  refuse,

  /// Le diagnostic n'a PAS pu être établi. Aucun groupe exportable,
  /// et aucun horodatage isolé.
  diagnosticImpossible,
}

/// ★ A7 (3.3-C9) — RÉSULTAT COMPLET DE `exporterPourBackupEnrichi()`.
///
/// Porte TROIS informations qu'il ne faut jamais confondre :
///   • [statut]       — ce qui a pu être établi ;
///   • [motif]        — POURQUOI, quand le statut est un refus ou une
///                      impossibilité. `null` ssi le statut est `complet` ou
///                      `sansRegistre` ;
///   • [groupe]       — les données exportables, et RIEN d'autre. VIDE dès
///                      que le statut n'autorise pas d'export.
///
/// Invariant vérifié par les tests : `groupe` est vide si et seulement si le
/// statut n'est ni `complet` ni `sansRegistre`.
class ResultatExportElo {
  /// Statut de l'export. Voir [StatutExportElo].
  final StatutExportElo statut;

  /// Motif explicite du refus ou de l'impossibilité. `null` quand l'export
  /// est autorisé.
  final String? motif;

  /// Groupe exportable, au format enrichi À PLAT :
  ///   • clés historiques `NOM|DISCIPLINE` → `EloScore.toJson()` ;
  ///   • `_elo_format` (toujours, si le groupe est non vide) ;
  ///   • `_elo_registre` (UNIQUEMENT si `statut == complet`) ;
  ///   • `_elo_ts` (si disponible).
  ///
  /// ⚠️ AUCUN sous-objet `ratings`. Mesuré au tour précédent : un sous-objet
  ///    fait perdre les deux ratings réels et crée un cheval fantôme.
  final Map<String, dynamic> groupe;

  const ResultatExportElo({
    required this.statut,
    required this.motif,
    required this.groupe,
  });

  /// Vrai ssi un groupe exportable a été produit. Seule base licite pour
  /// écrire `elo_service` dans la sauvegarde.
  bool get exportable =>
      statut == StatutExportElo.complet ||
      statut == StatutExportElo.sansRegistre;

  /// Vrai ssi le registre accompagne effectivement le groupe.
  bool get registreExporte => groupe.containsKey(_kCleMarqueurRegistre);

  @override
  String toString() => 'ResultatExportElo(statut: ${statut.name}, '
      'motif: ${motif ?? "-"}, '
      'clefs: ${groupe.length}, '
      'registreExporte: $registreExporte)';
}

class EloService {
  static final EloService _instance = EloService._();
  static EloService get instance => _instance;
  EloService._();

  static const String _prefsKey   = 'elo_ratings_v2';   // ★ v9.92 : nouvelle clé (par discipline)
  static const String _prefsKeyTs = 'elo_ratings_v2_ts';
  // Ancienne clé — lue en migration uniquement
  static const String _prefsKeyOld = 'elo_ratings_v1';

  static const double _eloDefaut    = 1500.0;
  static const double _kFactor      = 32.0;
  static const double _kDebutant    = 48.0;

  // ★ v9.93 POINT 3 : K-factor adapté par discipline
  // Trot Attelé : très discriminant → K plus élevé (convergence rapide)
  // Obstacle : part d'aléatoire importante (chutes) → K réduit
  // Galop Plat : valeur standard
  static double _kFacteurPourDiscipline(String discipline, bool estDebutant) {
    return switch (discipline) {
      'TROT_ATTELE'      => estDebutant ? 52.0 : 36.0,
      'TROT_MONTE'       => estDebutant ? 50.0 : 34.0,
      'OBSTACLE_HAIE'    => estDebutant ? 44.0 : 28.0,
      'OBSTACLE_STEEPLE' => estDebutant ? 42.0 : 26.0,
      'OBSTACLE_CROSS'   => estDebutant ? 40.0 : 24.0,
      'PLAT'             => estDebutant ? 48.0 : 32.0,
      _                  => estDebutant ? _kDebutant : _kFactor,
    };
  }
  static const int    _seuilDebutant = 20;
  static const double _eloMin       = 800.0;
  static const double _eloMax       = 2500.0;

  // ★ v9.92 : clé = "NOM_NORMALISE|DISCIPLINE_NORM"
  final Map<String, EloScore> _ratings = {};
  bool _charge = false;

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ B5c-RDR-05 — barrière de reset (patron CoteTrackerService B5b /
  //  IaMemoryService B5c-P1).
  //
  //  AUCUNE formule ELO, aucun K-factor, aucun rating n'est concerné : on ne
  //  fait qu'encadrer les ÉCRITURES disque de `_sauvegarder()`.
  //
  //  Les trois protections couvrent trois scénarios DISTINCTS et mesurés
  //  (V29-A, V29-B, V29-I) — aucun n'est redondant :
  //    • contrôle 1 (`_resetEnCours`) → écriture née PENDANT l'effacement ;
  //    • contrôle 2 (génération)      → écriture née APRÈS le reset ;
  //    • drain                        → écriture ENGAGÉE avant le reset,
  //      jamais refusable (elle a franchi les deux contrôles).
  // ══════════════════════════════════════════════════════════════════════════
  bool _resetEnCours = false;
  int _generationCache = 0;
  final Set<Future<void>> _ecrituresEnCours = <Future<void>>{};

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ A7 (3.3-B2-e / A-2) — JETON DE NAISSANCE PENDANT UN RESET.
  //
  //  DÉFAUT MESURÉ (arbitrage A-2) : `executerResetComplet` incrémente
  //  `_generationCache` AVANT de drainer. Une opération NÉE PENDANT le reset
  //  capture donc la génération DÉJÀ incrémentée : `generation ==
  //  _generationCache` est vrai pour toujours, et le contrôle de génération est
  //  INERTE pour elle. Sa seule protection restante était `_resetEnCours` ;
  //  si elle est retenue dans une attente de `SharedPreferences.getInstance()`
  //  qui se résout APRÈS la réouverture de la barrière, cette protection est
  //  retombée. Mesuré (B2e-9b) : elle écrivait alors `elo_ratings_v2`,
  //  `elo_ratings_v2_ts` ET `elo_registre_v3` après l'effacement, et rendait
  //  `persistee`. Résurrection post-barrière complète.
  //
  //  POURQUOI UN JETON, ET NON UN CONTRÔLE SUPPLÉMENTAIRE.
  //  Un contrôle posé après un `await` peut lui-même devenir obsolète pendant
  //  l'attente suivante. Le seul fait INVARIANT est celui de la NAISSANCE :
  //  l'opération a-t-elle commencé alors qu'un reset courait ? Cette
  //  information est capturée SYNCHRONEMENT, une seule fois, dans
  //  `_executerEnFile`, et voyage ensuite avec l'opération : elle ne peut plus
  //  devenir obsolète, puisqu'elle ne dépend plus d'un état mutable.
  //
  //  ENCODAGE — le jeton est NÉGATIF, et porte l'identité du reset :
  //    jeton = -(generationDuReset + 1)  ⇒  generationDuReset = -jeton - 1
  //  Une génération « normale » est toujours ≥ 0 : les deux espaces sont donc
  //  disjoints, et un jeton ne peut jamais être confondu avec une génération.
  //  Porter l'identité du reset (et non un simple booléen « pendant un reset »)
  //  couvre le cas de DEUX resets successifs : une opération née pendant R1 et
  //  reprise pendant R2 reste périmée, car `_generationCache` a encore changé.
  //
  //  ⚠️ CE QUE CE JETON NE CHANGE PAS : une opération née pendant le reset et
  //     qui court ENTIÈREMENT à l'intérieur de ce reset reste autorisée à
  //     avancer, puis est refusée par le CONTRÔLE 1 de `_sauvegarder`
  //     (`abandonneeParReset`, `nbRefusParReset` +1). C'est le contrat T8 /
  //     V29-I / V29-H, mesuré par delta EXACT : il est intégralement préservé.
  // ══════════════════════════════════════════════════════════════════════════

  /// Encode le jeton d'une opération née pendant le reset de génération
  /// [generationReset]. Toujours négatif, donc jamais confondu avec une
  /// génération réelle (≥ 0).
  static int _jetonNaissancePendantReset(int generationReset) =>
      -(generationReset + 1);

  /// Nombre de vidages effectués (observable par les tests).
  int get generationCache => _generationCache;

  /// Écritures encore en vol (observable par les tests).
  int get nbEcrituresEnCours => _ecrituresEnCours.length;

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ A7 (3.3-B2-a) — SUIVI DE TOUTES LES ÉCRITURES PERSISTANTES.
  //
  //  OBJET : permettre au reset d'attendre TOUTE écriture persistante, sans
  //  toucher au compteur historique [nbEcrituresEnCours].
  //
  //  ⚠️ POURQUOI UN SECOND ENSEMBLE, ET NON UN ENSEMBLE ÉLARGI.
  //  [_ecrituresEnCours] est mesuré par DELTA EXACT dans des tests validés :
  //    • `a7_32_observabilite_persistance_test.dart:428`     → 0 ;
  //    • `a7_32b_restauration_elo_contrat_test.dart:424`     → 0 ;
  //    • `a7_32c_concurrence_ts_test.dart:261` et `:292`     → 1 ;
  //    • `a7_33b1_file_fifo_elo_test.dart:654`               → 1.
  //  Y inscrire une écriture supplémentaire (registre ELO) changerait ces
  //  valeurs. Le second ensemble rend le drain plus large SANS modifier
  //  l'observable historique : c'est exactement l'objet de B2-a.
  //
  //  ÉTAT ACTUEL (B2-a) : les deux ensembles reçoivent EXACTEMENT les mêmes
  //  futures, car la seule écriture persistante existante est celle de
  //  `_sauvegarder()`. Aucun accès à `elo_registre_v3` n'est introduit :
  //  le registre n'est ni lu, ni écrit, ni supprimé, ni migré par ce lot.
  //
  //  INVARIANT : toute future inscrite ici en est RETIRÉE à sa complétion,
  //  succès OU échec (`whenComplete`), afin que le drain ne puisse pas
  //  boucler sur un ensemble qui ne se vide jamais.
  // ══════════════════════════════════════════════════════════════════════════

  /// TOUTES les écritures persistantes en vol (ratings aujourd'hui, registre
  /// ELO dans un lot ultérieur). Sert UNIQUEMENT au drain du reset.
  ///
  /// Distinct de [_ecrituresEnCours], qui reste le témoin historique exposé
  /// par [nbEcrituresEnCours] et n'est jamais élargi.
  final Set<Future<void>> _ecrituresPersistantesEnCours = <Future<void>>{};

  /// Écritures persistantes encore en vol, tous types confondus.
  ///
  /// Compteur NOUVEAU et purement additif : aucun test existant ne le lit
  /// (mesuré : `grep nbEcrituresEnCours` ne rend que l'ancien nom).
  int get nbEcrituresPersistantesEnCours =>
      _ecrituresPersistantesEnCours.length;

  /// Refus par le CONTRÔLE 1 — écriture née pendant l'effacement.
  int _nbRefusParReset = 0;
  int get nbRefusParReset => _nbRefusParReset;

  /// Refus par le CONTRÔLE 2 — génération périmée (écriture née avant le reset).
  int _nbRefusParGeneration = 0;
  int get nbRefusParGeneration => _nbRefusParGeneration;

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ A7 (3.2) — COMPTEURS D'OBSERVABILITÉ DE LA PERSISTANCE.
  //
  //  ⚠️ CES COMPTEURS S'AJOUTENT, ILS NE REMPLACENT RIEN. Les quatre
  //  compteurs historiques ci-dessus gardent leur valeur, leur point
  //  d'incrément et leur sémantique : `v29`/`v29b` les mesurent par DELTA
  //  avant/après, donc leur ajouter des voisins n'a aucun effet sur eux.
  //
  //  Un compteur ne s'incrémente QUE sur l'issue qu'il nomme :
  //    • nbPersistees       ← `setString(true)` ;
  //    • nbRefuseesStockage ← `setString(false)` ;
  //    • nbEchouees         ← exception pendant l'écriture des ratings ;
  //    • nbEchecsTs         ← `setInt(false)` ou exception sur `_ts` SEUL.
  //  Un échec de `_ts` N'INCRÉMENTE PAS `nbEchecs` : le rating est persisté.
  // ──────────────────────────────────────────────────────────────────────────
  int _nbPersistees = 0;
  int _nbRefuseesStockage = 0;
  int _nbEchouees = 0;
  int _nbEchecsTs = 0;

  /// Écritures de `elo_ratings_v2` CONFIRMÉES par `setString → true`.
  int get nbPersistees => _nbPersistees;

  /// Écritures de `elo_ratings_v2` REFUSÉES par `setString → false`.
  /// Persistance NON CONFIRMÉE (voir [EtatPersistanceElo]).
  int get nbRefuseesStockage => _nbRefuseesStockage;

  /// Écritures de `elo_ratings_v2` ayant LEVÉ une exception.
  /// Persistance NON CONFIRMÉE (voir [EtatPersistanceElo]).
  int get nbEchouees => _nbEchouees;

  /// Défauts SECONDAIRES sur `elo_ratings_v2_ts`, indépendants du rating.
  /// `elo_ratings_v2_ts` n'est PAS une preuve d'application ELO.
  int get nbEchecsTs => _nbEchecsTs;

  /// Dernière exception observée pendant une écriture, ou `null`.
  /// Conservée pour le diagnostic : 3.2 n'ouvre AUCUN rejeu à partir d'elle.
  Object? _derniereErreurEcriture;
  Object? get derniereErreurEcriture => _derniereErreurEcriture;

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ A7 (3.3-B2-b) — IDENTITÉ DE COURSE DE LA DERNIÈRE APPLICATION.
  //
  //  OBJET : rendre OBSERVABLE, sans aucun effet de bord, ce que la validation
  //  d'identité a produit pour la dernière opération ELO exécutée. C'est ce qui
  //  permet de PROUVER que les constituants sont préparés — sans écrire quoi
  //  que ce soit et sans toucher aux ratings.
  //
  //  ⚠️ CE CHAMP N'EST PAS UN JOURNAL. Il ne survit pas au processus, n'est pas
  //  persisté, n'est lu par AUCUNE logique de production : il n'existe que
  //  pour l'observation. Le futur registre lira l'identité à la SOURCE (le
  //  paramètre `courseKey`), jamais ce champ.
  //
  //  ⚠️ SA VALEUR EST `null` PAR DÉFAUT, ET C'EST LE CAS NOMINAL : tous les
  //  appels existants ne passent pas de `courseKey`, donc aucune identité n'est
  //  produite (D-B2-1 : pas de clé fictive). `null` ne conditionne RIEN : les
  //  ratings sont mis à jour exactement comme avant ce lot.
  //
  //  ⚠️ RÉINITIALISATION : le champ est remis à `null` au DÉBUT de chaque
  //  opération ELO, avant toute attente. Sans cela, une opération sans
  //  `courseKey` laisserait observer l'identité de l'opération PRÉCÉDENTE, et
  //  un test pourrait croire qu'une identité a été produite là où il n'y en a
  //  pas. Il n'est PAS touché par `executerResetComplet` : ce lot ne modifie
  //  pas le reset.
  // ══════════════════════════════════════════════════════════════════════════
  IdentiteCourseElo? _derniereIdentiteCourse;

  /// Identité de course de la DERNIÈRE opération ELO, ou `null`.
  ///
  /// `null` signifie « aucune identité exploitable n'a été fournie » — jamais
  /// « identité perdue ». Aucun code de production ne doit décider d'une
  /// écriture à partir de ce getter (voir la documentation du champ).
  IdentiteCourseElo? get derniereIdentiteCourse => _derniereIdentiteCourse;

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ A7 (3.3-B2-d1) — DIAGNOSTIC PRÉ-IMPORT DE L'ÉTAT ELO.
  //
  //  OBJET : rendre OBSERVABLE l'état ELO établi AVANT la mutation d'un import,
  //  et le figer pour que les tests puissent le vérifier après coup.
  //
  //  ⚠️ CE CHAMP N'EST PAS UN JOURNAL. Il ne survit pas au processus, n'est
  //  persisté nulle part, et AUCUNE logique de production ne le consulte dans
  //  ce lot : il n'autorise et ne bloque exactement RIEN.
  //
  //  ⚠️ SA VALEUR EST `null` TANT QU'AUCUN IMPORT N'A ÉTÉ TENTÉ, et elle est
  //  remise à `null` au DÉBUT de chaque import, AVANT toute attente. Sans cette
  //  remise, un import qui s'abandonne laisserait observer le diagnostic de
  //  l'import PRÉCÉDENT — un test pourrait alors croire qu'un diagnostic a été
  //  établi là où il ne l'a pas été.
  //
  //  ⚠️ `null` APRÈS UN IMPORT SIGNIFIE « non établi », JAMAIS « aucune
  //  anomalie » : le motif exact est porté par [etablissementImpossible] du
  //  dernier diagnostic effectivement produit.
  //
  //  ⚠️ IL N'EST PAS TOUCHÉ PAR `executerResetComplet` : ce lot ne modifie pas
  //  le reset. Un reset n'écrit donc rien ici, et son drain n'attend rien de
  //  ce champ puisqu'il ne produit aucune écriture.
  // ══════════════════════════════════════════════════════════════════════════
  DiagnosticPreImportElo? _dernierDiagnosticPreImport;

  /// Diagnostic de l'état ELO établi AVANT le DERNIER import tenté, ou `null`.
  ///
  /// Lecture seule. Voir la documentation de [DiagnosticPreImportElo] : ce
  /// getter n'existe que pour l'observation et la vérification, jamais pour
  /// décider d'une écriture, d'un blocage ou d'une autorisation.
  DiagnosticPreImportElo? get dernierDiagnosticPreImport =>
      _dernierDiagnosticPreImport;

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ A7 (3.3-B2-d2) — RÉSULTAT COMPLET DU DERNIER IMPORT.
  //
  //  ⚠️ AMBIGUÏTÉ DOCUMENTÉE (réserve R3 de la consigne).
  //  `null` signifie « aucun import n'a encore été tenté, ou le dernier import
  //  s'est abandonné avant de produire un résultat ». Il ne signifie JAMAIS
  //  « import réussi ». AUCUNE décision de production ne doit lire ce getter
  //  comme une preuve de succès : [ResultatImportElo.operationSecurisee] est
  //  le seul indicateur de double persistance, et il ne vaut que pour un
  //  résultat effectivement produit.
  // ══════════════════════════════════════════════════════════════════════════
  ResultatImportElo? _dernierResultatImport;

  /// Résultat complet du DERNIER import mené à son terme, ou `null`.
  ///
  /// Lecture seule. Voir l'avertissement ci-dessus : `null` n'est pas un
  /// succès. Ne conditionne aucune écriture — le point de contrôle unique est
  /// [_doitEcrireTemoin].
  ResultatImportElo? get dernierResultatImport => _dernierResultatImport;

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ A7 (3.3-B2-e) — OBSERVABLE DE L'APPLICATION ELO APRÈS ARRIVÉE.
  //
  //  Même raison d'être que `dernierResultatImport` : le type de retour public
  //  de `mettreAJourApresArrivee` reste `EtatPersistanceElo` — `backup_service`
  //  en fait un `switch` exhaustif (l.1101-1145) et il est gelé. Les faits que
  //  l'enum ne peut pas porter (motif de refus, origine, journalisation) sont
  //  donc publiés ici.
  //
  //  ⚠️ `null` N'EST PAS UN SUCCÈS. Il signifie « aucune opération arrivée à
  //     son terme », y compris un abandon par reset.
  // ══════════════════════════════════════════════════════════════════════════
  ResultatApplicationElo? _dernierResultatMiseAJour;

  /// Résultat complet de la DERNIÈRE application ELO après arrivée, ou `null`.
  ///
  /// Lecture seule. Ne conditionne aucune écriture : le point de décision reste
  /// [_chargerOuAmorcerRegistre] puis [_doitEcrireTemoin] pour l'import.
  ResultatApplicationElo? get dernierResultatMiseAJour =>
      _dernierResultatMiseAJour;

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ X1-b — SURVEILLANCE DE LA TAILLE DU REGISTRE ELO.
  //
  //  ⚠️ STRICTEMENT INFORMATIF. Ces deux champs ne sont LUS PAR AUCUNE
  //     DÉCISION : ils ne conditionnent aucune écriture, aucun refus, aucune
  //     autorisation. Le point de décision reste [_chargerOuAmorcerRegistre]
  //     puis [_doitEcrireTemoin] ; le seul verrou de doublon reste
  //     `registre.entreePourCle(...) != null` (voir `mettreAJourApresArrivee`).
  //     Aucun refus ELO n'est introduit à 1,5, 3 ou 6 Mio : les seuils
  //     `kSeuilVeilleOctets` / `kSeuilAlerteOctets` / `kSeuilSaturationOctets`
  //     ne servent ici qu'à NOMMER un niveau, jamais à décider.
  //
  //  ⚠️ AUCUNE COMPACTION, AUCUNE PURGE, AUCUNE SUPPRESSION. La surveillance
  //     ne touche jamais `registre.entrees`, jamais `chevaux`, jamais les
  //     images avant/après d'un cheval. Elle ne fait que MESURER une chaîne.
  //
  //  ⚠️ AUCUNE CLÉ SharedPreferences SUPPLÉMENTAIRE. L'état vit en RAM.
  //     `test/a7_33b2b_identite_course_test.dart` l.678 verrouille
  //     `cles.length == 3` : une clé ajoutée casserait ce contrat.
  //
  //  ── DEUX SOURCES, DEUX GARANTIES DISTINCTES ──────────────────────────────
  //
  //   • [_hydraterNiveauRegistre] — mesure EXACTE en octets, au CHARGEMENT.
  //     Reçoit le JSON réellement lu depuis SharedPreferences. Aucune lecture
  //     ni aucun décodage JSON supplémentaire n'est ajouté : la chaîne est
  //     déjà en main à l'endroit de l'appel.
  //
  //   • [_observerNiveauRegistre] — MINORANT, après une écriture CONFIRMÉE.
  //     `brut.length` compte des UNITÉS UTF-16, pas des octets. Comme
  //     `octetsUtf8` facture au moins 1 par unité, on a toujours
  //     `octetsUtf8(s) >= s.length` : la valeur est un MINORANT GARANTI.
  //     Elle SOUS-ESTIME donc, et ne SURESTIME JAMAIS. Écart mesuré sur du
  //     contenu réaliste : 0,00 % en ASCII pur, 1,20 % avec des noms accentués
  //     (`_cleNom` ne retire pas les diacritiques). Conséquence : le niveau
  //     annoncé peut être en RETARD, jamais en avance. Il est marqué ESTIMÉ.
  //
  //  ── PAS DE MONOTONIE : LE NIVEAU PEUT REDESCENDRE ────────────────────────
  //
  //   Les deux méthodes ÉCRASENT le champ, elles ne conservent JAMAIS un
  //   maximum historique. C'est la correction de l'audit : après une
  //   restitution verbatim d'un registre plus petit, ou après un reset, un
  //   `max` conserverait un niveau faux (mesuré : annonçait `saturation` pour
  //   un registre de niveau `normal`).
  //
  //  ── SUR RESTAURATION ET RESET : CE QUI EST PROUVÉ ─────────────────────────
  //
  //   RESTAURATION — le registre ne suit PAS le chemin des autres groupes.
  //  `_restaurerGroupe` (défini `backup_service.dart` l.930) écrit les autres
  //  clés directement par `prefs.setString` (l.952). Le groupe `elo_service`
  //  est traité à part (l.1455-1459, `importerDepuisBackup`) et atteint
  //  `_ecrireRegistreVerbatim` — c'est-à-dire P4, le chemin INSTRUMENTÉ.
  //  MESURÉ : une écriture de registre par restauration, dans les DEUX sens.
  //
  //  ⚠️ AUCUN SEUIL DE TAILLE NE BLOQUE CETTE RESTAURATION. Ni
  //    `kSeuilVeilleOctets`, ni `kSeuilAlerteOctets`, ni
  //    `kSeuilSaturationOctets` n'est consulté sur ce chemin. Recherche
  //    `grep -rnE "brut\.length\s*[<>]" lib/services/elo_service.dart` :
  //    aucune occurrence. Une restauration peut donc AUGMENTER comme
  //    DIMINUER la taille du registre, sans limite : mesuré 7 144 737 →
  //    1 561 octets puis retour, sur le même appareil.
  //
  //  CE QUI EST MIS À JOUR, ET COMMENT — trois choses DISTINCTES, à ne pas
  //  confondre :
  //    1. la MESURE des OCTETS : exacte au chargement (`octetsUtf8` sur le
  //       JSON du disque), minorante après une écriture (`brut.length`) ;
  //    2. le CLASSEMENT du NIVEAU : `classerRetention` appliqué à cette
  //       mesure — informatif, sans effet décisionnel ;
  //    3. la FRAÎCHEUR de l'indicateur : `true` seulement si la valeur
  //       provient d'une lecture réelle du disque. Après une écriture
  //       confirmée, elle vaut `false` — la valeur est déclarée ESTIMÉE,
  //       jamais présentée comme une mesure actuelle garantie.
  //  Un niveau peut donc être JUSTE et NON EXACT en même temps : les deux
  //  propriétés sont indépendantes.
  //
  //  RESET DONT L'EFFACEMENT ÉCHOUE. `executerResetComplet` ne peut affirmer
  //  l'absence du registre que si le callback d'effacement a rendu la main
  //  SANS lever. Si l'effacement échoue, la clé peut survivre sur le disque
  //  (contrat C1-a : « les suppressions déjà réussies ne sont PAS annulées »).
  //  Le niveau n'est alors PAS réécrit en `normal` — aucune valeur n'est
  //  inventée — et la mesure est déclarée NON EXACTE. La vérité est rétablie
  //  à la première opération qui retraverse P1.
  //
  //  ⚠️ UNE SEULE CHOSE EST GARANTIE : une valeur EXACTE
  //    (`niveauRegistreEstExact == true`) provient d'une lecture réelle du
  //    disque et reflète son contenu au moment de cette lecture. Une valeur
  //    non exacte ne doit jamais être présentée comme actuelle.
  // ══════════════════════════════════════════════════════════════════════════
  NiveauRetentionElo _niveauRegistre = NiveauRetentionElo.normal;
  bool _niveauRegistreExact = false;

  /// Niveau de rétention correspondant à la taille connue du registre ELO.
  ///
  /// INFORMATIF. Ne décide d'AUCUNE écriture, d'AUCUN refus, d'AUCUNE
  /// autorisation. Voir [niveauRegistreEstExact] pour la fraîcheur.
  NiveauRetentionElo get niveauRegistre => _niveauRegistre;

  /// `true` si et seulement si [niveauRegistre] provient d'une mesure EXACTE
  /// en octets, faite sur le JSON réellement lu depuis le stockage.
  ///
  /// `false` signifie : valeur ESTIMÉE par minorant (`brut.length`), ou
  /// héritée d'un état antérieur. Dans ce cas elle ne doit pas être
  /// présentée comme une mesure actuelle garantie.
  bool get niveauRegistreEstExact => _niveauRegistreExact;

  /// Recalcule le niveau depuis le JSON du DISQUE. `null` = registre absent.
  ///
  /// Mesure EXACTE via [octetsUtf8]. C'est la SEULE source de vérité : elle
  /// est appelée au chargement du registre et après un reset complet.
  ///
  /// ⚠️ Ne pas lui passer une chaîne fabriquée depuis la RAM (un
  ///    `registre.encoder()`) : cela re-sérialiserait tout le registre et la
  ///    valeur ne serait plus celle du disque. Le paramètre doit être le JSON
  ///    réellement lu, ou `null` quand la clé n'existe pas.
  void _hydraterNiveauRegistre(String? jsonDisque) {
    if (jsonDisque == null) {
      _niveauRegistre = NiveauRetentionElo.normal;
    } else {
      _niveauRegistre = classerRetention(octetsUtf8(jsonDisque));
    }
    _niveauRegistreExact = true;
  }

  /// Recalcule un MINORANT depuis une chaîne DÉJÀ sérialisée.
  ///
  /// Appelée UNIQUEMENT après confirmation d'une écriture réussie : le disque
  /// contient alors exactement `brut`, donc mesurer `brut` reflète l'état
  /// persisté. Ne PAS appeler avant l'acquittement (le disque pourrait avoir
  /// refusé l'écriture).
  ///
  /// Coût : `O(1)` (`String.length`), aucune allocation, aucun parcours.
  void _observerNiveauRegistre(String brut) {
    _niveauRegistre = classerRetention(brut.length);
    _niveauRegistreExact = false;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ A7 (3.3-B2-d2) — POINT DE CONTRÔLE UNIQUE DE L'ÉCRITURE DU TÉMOIN.
  //
  //  RÈGLE DE SÉCURITÉ, ÉNONCÉE ICI UNE FOIS ET NULLE PART AILLEURS :
  //  le témoin n'est écrit QUE si, et seulement si, ce point rend `null`
  //  (aucun motif de refus). Toute autre branche du service doit passer par
  //  lui — jamais par un `if (diagnostic.etabli)` dispersé.
  //
  //  ⚠️ `null`, `etabli == false` et tout diagnostic non établi sont traités
  //  comme des REFUS, jamais comme des autorisations. C'est l'inverse exact du
  //  piège consistant à laisser un `false` par défaut autoriser une écriture.
  //
  //  ⚠️ LISTE BLANCHE, PAS LISTE NOIRE. Seule la cohérence `coherent` autorise.
  //  `registreAbsent`, `dejaDivergent`, `corrompu`, `schemaIncompatible` et
  //  `diagnosticNonEtabli` sont refusés — la liste noire serait une invitation
  //  à oublier un futur cas.
  // ══════════════════════════════════════════════════════════════════════════

  /// Rend `null` si le témoin PEUT être écrit, ou le motif EXACT du refus.
  ///
  /// FONCTION PURE : aucun accès disque, aucune mutation.
  static MotifNonEcritureTemoin? _doitEcrireTemoin({
    required DiagnosticPreImportElo diagnostic,
    required EtatPersistanceElo etatRatings,
    required String? empreinteAvant,
    required String? empreinteApres,
  }) {
    // 1. Le diagnostic doit être ÉTABLI. Un `null` n'autorise rien.
    if (!diagnostic.etabli) {
      return MotifNonEcritureTemoin.diagnosticNonEtabli;
    }

    // 2. Les ratings doivent avoir été PERSISTÉS. Avant cela, l'import n'a pas
    //    eu lieu : attester d'une empreinte serait attester d'un fait inconnu.
    if (etatRatings != EtatPersistanceElo.persistee) {
      return MotifNonEcritureTemoin.ratingsNonPersistes;
    }

    // 3. Le registre doit avoir été COHÉRENT avant l'import. Liste blanche.
    switch (diagnostic.coherence!) {
      case DiagnosticCoherenceElo.coherent:
        break; // seul cas autorisé
      case DiagnosticCoherenceElo.registreAbsent:
        return MotifNonEcritureTemoin.registreAbsent;
      case DiagnosticCoherenceElo.divergent:
        return MotifNonEcritureTemoin.dejaDivergent;
      case DiagnosticCoherenceElo.corrompu:
        return MotifNonEcritureTemoin.corrompu;
      case DiagnosticCoherenceElo.schemaIncompatible:
        return MotifNonEcritureTemoin.schemaIncompatible;
    }

    // 4. Aucune écriture artificielle si rien n'a changé.
    if (empreinteAvant != null && empreinteAvant == empreinteApres) {
      return MotifNonEcritureTemoin.aucunChangement;
    }

    return null; // autorisé
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ A7 (3.3-C12 / A7-39) — REFUS ANTICIPÉ D'UN REGISTRE ENRICHI.
  //
  //  OBJET : décider, AVANT toute mutation des ratings, si le registre
  //  transporté par une sauvegarde peut être RESTITUÉ. C'est la seule fonction
  //  qui autorise la restitution : toute autre branche refuse.
  //
  //  ⚠️ POURQUOI AVANT LA MUTATION, ET PAS APRÈS.
  //  Un refus découvert APRÈS `_sauvegarder()` laisserait l'appareil avec des
  //  ratings importés et un registre périmé, donc `divergent` : plus aucune
  //  application ELO possible, sans réparation automatique (interdite). Une
  //  sauvegarde MANIFESTEMENT invalide ne doit pas produire cet état. La
  //  décision est donc prise hors ligne, sur des données locales, sans aucun
  //  accès disque et sans aucune mutation.
  //
  //  ⚠️ FONCTION PURE. Elle ne lit ni n'écrit `SharedPreferences`, ne touche
  //  pas `_ratings`, ne touche à aucun compteur. Le seul effet de bord admis
  //  est le décodage tolérant des ratings DANS UNE MAP LOCALE, dont le résultat
  //  est rendu à l'appelant pour être réutilisé — jamais recalculé.
  //
  //  ⚠️ LISTE BLANCHE. Aucun cas par défaut n'autorise :
  //    • marqueur absent            ⇒ chemin HISTORIQUE, pas de restitution ;
  //    • marqueur non textuel       ⇒ `registreEnrichiNonTextuel` ;
  //    • décodage qui lève          ⇒ `registreEnrichiIllisible` ;
  //    • `!interpretable`           ⇒ `registreEnrichiIllisible` ;
  //    • empreinte ≠ ratings        ⇒ `registreEnrichiIncoherent` ;
  //    • tout le reste              ⇒ restitution AUTORISÉE.
  // ══════════════════════════════════════════════════════════════════════════

  /// Verdict du refus anticipé. Voir [motif] : `null` signifie « restitution
  /// autorisée », et c'est le SEUL cas qui l'autorise.
  static ({
    MotifNonEcritureTemoin? motif,
    Map<String, EloScore>? candidats,
    String? registreBrut,
    RegistreEloV3? registre,
  }) _analyserRegistreEnrichi(Map<String, dynamic> data) {
    ({MotifNonEcritureTemoin? motif, Map<String, EloScore>? candidats,
        String? registreBrut, RegistreEloV3? registre}) refus(
      MotifNonEcritureTemoin motif) =>
        (
          motif: motif,
          candidats: null,
          registreBrut: null,
          registre: null,
        );

    // ── 0. Marqueur ABSENT : ce n'est PAS un refus, c'est le chemin
    //       historique. Rendons un quadruplet vide et un motif NUL : les
    //       appelants distinguent les deux cas par `data.containsKey`.
    final Object? marqueurBrut = data[_kCleMarqueurRegistre];
    if (marqueurBrut == null) {
      return (
        motif: null,
        candidats: null,
        registreBrut: null,
        registre: null,
      );
    }

    // ── 1. Type du marqueur : un registre est TOUJOURS une chaîne.
    if (marqueurBrut is! String) {
      return refus(MotifNonEcritureTemoin.registreEnrichiNonTextuel);
    }

    // ── 2. Empreinte des ratings de la SAUVEGARDE, calculée sans muter la RAM.
    //       Le filtre `_elo_` est INDISPENSABLE : sans lui, on dépendrait du
    //       fait accidentel qu'un `String`/`int` soit rejeté par
    //       `as Map<String, dynamic>`. Cette coïncidence est réelle mais ne
    //       doit pas porter une décision de sécurité.
    //       Décodage TOLÉRANT, identique à `_charger` et à la mutation : une
    //       entrée illisible est ignorée, partout de la même façon. C'est ce
    //       qui rend l'empreinte d'ici comparable à celle de la RAM après
    //       mutation, et donc la barrière F3' possible.
    final Map<String, EloScore> candidats = <String, EloScore>{};
    data.forEach((key, val) {
      if (key.startsWith('_elo_')) return;
      try {
        candidats[key] = EloScore.fromJson(val as Map<String, dynamic>);
      } catch (_) {}
    });
    final String empreinteCandidats = empreinte64Ratings(candidats);

    // ── 3. Décodage STRICT du registre. Une `FormatException` est un refus,
    //       jamais un repli.
    final RegistreEloV3 registre;
    try {
      registre = RegistreEloV3.decoder(marqueurBrut);
    } on FormatException {
      return refus(MotifNonEcritureTemoin.registreEnrichiIllisible);
    } catch (_) {
      // `jsonDecode` peut lever autre chose qu'une `FormatException` sur une
      // entrée pathologique : même décision, jamais un succès.
      return refus(MotifNonEcritureTemoin.registreEnrichiIllisible);
    }

    // ── 4. Interprétable : `schema` ET `version` doivent être connus.
    //       Un registre d'un schéma futur n'est ni réparé, ni réinterprété.
    if (!registre.interpretable) {
      return refus(MotifNonEcritureTemoin.registreEnrichiIllisible);
    }

    // ── 5. L'empreinte déclarée doit décrire LES RATINGS DE CETTE SAUVEGARDE.
    //       C'est la seule preuve disponible, et elle est INTERNE au fichier :
    //       elle ne dépend d'aucun état de l'appareil cible.
    if (registre.empreinteRatings != empreinteCandidats) {
      return refus(MotifNonEcritureTemoin.registreEnrichiIncoherent);
    }

    // ── 6. Restitution AUTORISÉE. La chaîne brute est rendue VERBATIM : elle
    //       sera écrite telle quelle, sans réencodage, donc `entrees`,
    //       `horloge`, `schema`, `version` et `origine` sont préservés à
    //       l'octet. Aucune entrée n'est ajoutée : un import ne doit pas
    //       inventer d'historique.
    return (
      motif: null,
      candidats: candidats,
      registreBrut: marqueurBrut,
      registre: registre,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  A7 / B2-e — CHARGEMENT ET AMORÇAGE DU REGISTRE
  // ==========================================================================
  //  RÔLE : obtenir un registre UTILISABLE pour décider et journaliser, ou
  //  expliquer pourquoi il est impossible d'en obtenir un.
  //
  //  RÈGLE CENTRALE (option 1 arbitrée) :
  //   • registre ABSENT + aucun rating  ⇒ amorcer `origine: courante` ;
  //   • registre ABSENT + ratings      ⇒ amorcer `origine: historiqueInconnu`,
  //     sans inventer une seule entrée et sans toucher aux ratings ;
  //   • registre COHÉRENT (quelle que soit son origine) ⇒ utilisable ;
  //   • registre DIVERGENT / CORROMPU / INCOMPATIBLE ⇒ refus, jamais remplacé ;
  //   • LECTURE EN ERREUR ⇒ refus. Une erreur de lecture n'est JAMAIS une
  //     absence légitime (§6, condition impérative).
  //
  //  ⚠️ `historiqueInconnu` n'est PAS un motif de refus. C'est un indicateur :
  //     le registre journalise les opérations NOUVELLES, et ne prétend rien
  //     sur les applications antérieures à l'amorçage. Cette limite est
  //     assumée au §1 de l'arbitrage, et ne doit jamais être présentée comme
  //     une garantie rétroactive.
  // ══════════════════════════════════════════════════════════════════════════
  Future<({RegistreEloV3? registre, MotifRefusApplicationElo? refus,
          bool amorcage})> _chargerOuAmorcerRegistre({
    required int generation,
    int? jeton,
  }) async {
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return (registre: null, refus: MotifRefusApplicationElo.registreIllisible,
              amorcage: false);
    }

    // `reload()` : la lecture doit porter sur le STORE, pas sur le cache. Le
    // registre peut avoir été écrit par une opération antérieure et n'être
    // visible qu'après rechargement — `getString` seul lirait `_preferenceCache`.
    try {
      await prefs.reload();
    } catch (_) {
      return (registre: null, refus: MotifRefusApplicationElo.registreIllisible,
              amorcage: false);
    }

    final Object? brut = prefs.get(kCleRegistreElo);
    if (brut != null && brut is! String) {
      // Type inattendu : ni absence, ni corruption du JSON — un refus explicite.
      return (registre: null, refus: MotifRefusApplicationElo.registreIllisible,
              amorcage: false);
    }

    final String? jsonRegistre = brut as String?;

    // ★ X1-b (P1) — MESURE EXACTE AU CHARGEMENT.
    //   `jsonRegistre` vient d'être lu (`prefs.get` l.1359, après `reload()`
    //   l.1353) : c'est le JSON du DISQUE. Aucune lecture, aucun décodage
    //   supplémentaire n'est introduit — on ne fait que compter les octets
    //   de la chaîne déjà en main. `null` (clé absente) => niveau `normal`.
    //   Placé AVANT la branche d'amorçage pour couvrir aussi le registre
    //   absent, et donc le cas d'un redémarrage après reset.
    _hydraterNiveauRegistre(jsonRegistre);

    // ── Registre ABSENT : seul cas où un amorçage est autorisé. ─────────────
    if (jsonRegistre == null) {
      final String empreinte = empreinte64Ratings(_ratings);
      final RegistreEloV3 neuf = _ratings.isEmpty
          // Cas A — tout premier usage : aucun historique à protéger.
          ? RegistreEloV3.vierge(empreinteRatings: empreinte)
          // Cas B — des ratings existent sans registre. `vierge()` pose
          // `courante` ; on corrige en `historiqueInconnu` : nous ne
          // connaissons AUCUNE des applications antérieures. Aucune entrée
          // historique n'est inventée, aucun rating n'est modifié.
          : RegistreEloV3.vierge(empreinteRatings: empreinte)
              .copyWith(origine: OrigineRegistreElo.historiqueInconnu);

      // ★ A-1 : on ne teste PLUS un `null` ambigu, mais le fait mesuré — la
      //   persistance de l'amorçage a-t-elle été CONFIRMÉE ?
      final ({bool confirmee, MotifRefusApplicationElo? refus}) amorcage =
          await _persisterRegistre(
        registre: neuf,
        generation: generation,
        jetonNaissance: jeton,
      );
      if (amorcage.refus != null) {
        return (registre: null,
                refus: MotifRefusApplicationElo.amorcageNonPersiste,
                amorcage: false);
      }
      // ⚠️ A-1 — `confirmee == false` sans refus signifie : écriture SAUTÉE par
      //    un reset en cours. Le registre Neuf existe alors en MÉMOIRE mais il
      //    n'a AUCUNE existence durable : l'amorçage n'est PAS annoncé. Le
      //    registre est tout de même rendu pour que les contrôles suivants
      //    (doublon, antériorité) puissent s'exercer — c'est exactement ce que
      //    faisait le `return null` précédent — mais `amorcage` reste FALSE.
      return (registre: neuf, refus: null, amorcage: amorcage.confirmee);
    }

    // ── Registre PRÉSENT : décodage puis diagnostic. Jamais d'amorçage. ─────
    final RegistreEloV3 registre;
    try {
      registre = RegistreEloV3.decoder(jsonRegistre);
    } on FormatException {
      // Ni remplacement, ni réinitialisation, ni migration (§4, §11).
      return (registre: null, refus: MotifRefusApplicationElo.registreNonCoherent,
              amorcage: false);
    }

    if (!registre.interpretable) {
      return (registre: null, refus: MotifRefusApplicationElo.registreNonCoherent,
              amorcage: false);
    }

    final ResultatDiagnosticElo diagnostic = diagnostiquerRegistre(
      jsonRegistre: jsonRegistre,
      empreinteDisque: empreinte64Ratings(_ratings),
      nombreRatings: _ratings.length,
    );

    // Liste blanche : SEUL `coherent` autorise. `divergent` est refusé sans
    // réparation ; `corrompu`/`schemaIncompatible` le sont déjà plus haut.
    if (diagnostic.coherence != DiagnosticCoherenceElo.coherent) {
      return (registre: null, refus: MotifRefusApplicationElo.registreNonCoherent,
              amorcage: false);
    }

    return (registre: registre, refus: null, amorcage: false);
  }

  /// Persiste [registre] sous `kCleRegistreElo`, en respectant P1.
  ///
  /// ⚠️ AUCUN `await` ENTRE LE CONTRÔLE DE GÉNÉRATION ET L'INSCRIPTION DANS
  ///    `_ecrituresPersistantesEnCours`. Sans cette contiguïté, un reset
  ///    pourrait s'intercaler dans la fenêtre et la future ne serait pas
  ///    drainée — l'écriture ressusciterait `elo_registre_v3` après effacement
  ///    (défaut V29-A).
  ///
  /// Rend un couple EXPLICITE `(confirmee, refus)` — jamais un simple `null`.
  ///
  /// ★ A-1 : `null` signifiait à la fois « le stockage a CONFIRMÉ » et
  ///   « l'écriture a été SAUTÉE pendant un reset ». L'appelant d'amorçage
  ///   interprétait ce `null` comme un succès et publiait `amorcageEffectue:
  ///   true` alors qu'aucune écriture n'avait eu lieu. Les deux faits sont
  ///   désormais DISTINGUÉS : `confirmee` est le SEUL critère d'un amorçage
  ///   réel, et un refus reste un refus.
  Future<({bool confirmee, MotifRefusApplicationElo? refus})>
      _persisterRegistre({
    required RegistreEloV3 registre,
    required int generation,
    int? jetonNaissance,
  }) async {
    final String brut;
    try {
      brut = registre.encoder();
    } catch (_) {
      return (confirmee: false, refus: MotifRefusApplicationElo.serialisationImpossible);
    }

    // Contrôle G avant toute attente.
    if (_estPerimeeParReset(generation)) {
      return (confirmee: false, refus: MotifRefusApplicationElo.intentionNonPersistee);
    }

    // ★ A2 — opération ENGAGÉE pendant un reset DÉJÀ ACHEVÉ : le jeton est
    //   immuable, ce contrôle ne peut pas être rendu obsolète par une attente.
    if (jetonNaissance != null) {
      final MotifRefusApplicationElo? refusJeton =
          _motifRefusEcriturePersistante(jetonNaissance);
      if (refusJeton != null) return (confirmee: false, refus: refusJeton);
    }

    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return (confirmee: false, refus: MotifRefusApplicationElo.intentionNonPersistee);
    }

    // Contrôle G après `getInstance()` : c'est une attente.
    if (_estPerimeeParReset(generation)) {
      return (confirmee: false, refus: MotifRefusApplicationElo.intentionNonPersistee);
    }

    // ★ A2 — re-vérification après l'attente, sur le jeton immuable.
    if (jetonNaissance != null) {
      final MotifRefusApplicationElo? refusJeton =
          _motifRefusEcriturePersistante(jetonNaissance);
      if (refusJeton != null) return (confirmee: false, refus: refusJeton);
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  ★ A7 (3.3-B2-e) — CORRECTIF DU DÉFAUT DE RÉSURRECTION DU REGISTRE ELO.
    //
    //  DÉFAUT MESURÉ : une opération NÉE PENDANT un reset capture la génération
    //  DÉJÀ incrémentée par ce reset (`executerResetComplet` incrémente AVANT
    //  de drainer). Le contrôle de génération ci-dessus la laisse donc passer, et
    //  son `setString` s'exécutait APRÈS le `remove` du reset : la clé
    //  `elo_registre_v3` était RECRÉÉE. Preuve : 3 écritures du registre
    //  observées pendant un reset, clé survivante.
    //
    //  POURQUOI CE N'EST PAS UN GARDE `_resetEnCours` QUI REFUSE.
    //  Un refus, ici, remonterait en `intentionNonPersistee` et l'opération
    //  rendrait `nonTentee` SANS atteindre `_sauvegarder()`. Mesuré : cela casse
    //  T8 (`a7_32`), V29-I et V29-H, qui exigent `abandonneeParReset`, la RAM
    //  mutée et `nbRefusParReset` incrémenté EXACTEMENT une fois. Ces contrats
    //  sont validés et ne doivent pas changer.
    //
    //  SOLUTION RETENUE : l'écriture physique est SAUTÉE, mais l'appel est
    //  acquitté. Justification, et elle est stricte :
    //    • le reset est EN COURS et va effacer le registre : il n'existe aucune
    //      version de registre à écrire qui puisse être durable. Écrire serait
    //      non seulement inutile, mais nuisible (résurrection) ;
    //    • l'état final de l'opération reste décidé AILLEURS, par les contrôles
    //      existants : `_sauvegarder()` rend `abandonneeParReset` (contrôle 1) et
    //      incrémente `nbRefusParReset`. Aucun contrat observable ne bouge ;
    //    • ce n'est PAS une réparation automatique et PAS une fausse preuve :
    //      on ne prétend pas que le registre est persisté, on constate qu'il
    //      n'a pas à l'être. `_finaliserEntreeCourse` refuse symétriquement.
    //
    //  ORDONNANCEMENT COUVERT — les DEUX sens sont traités :
    //    (a) écriture ENGAGÉE avant le reset : sa future est déjà inscrite dans
    //        `_ecrituresPersistantesEnCours`, donc le drain l'attend AVANT
    //        d'effacer. Le reset garde la priorité ;
    //    (b) écriture NÉE pendant le reset : on n'écrit pas du tout.
    //  Le contrôle est placé APRÈS le dernier `await` (`getInstance()`), donc il
    //  ne peut pas devenir obsolète pendant une attente, et il est CONTIGU à
    //  l'inscription dans `_ecrituresPersistantesEnCours` (invariant P1 : aucun
    //  `await` ne les sépare).
    // ══════════════════════════════════════════════════════════════════════════
    // ★ A-1 — LE SAUT D'ÉCRITURE N'EST PLUS UN `null` AMBIGU.
    //   Le retour est désormais un couple explicite `(confirmee, refus)`. Le
    //   saut rend `confirmee: false` : aucun appelant ne peut plus le lire
    //   comme une persistance. L'issue de l'OPÉRATION reste décidée ailleurs,
    //   par le contrôle 1 de `_sauvegarder()` — les contrats T8 / V29-I / V29-H
    //   sont donc préservés à l'identique.
    if (_resetEnCours) {
      debugPrint('[EloService] ⏭️ écriture du registre SAUTÉE (reset en cours) '
          '— la clé ne sera pas recréée après effacement');
      return (confirmee: false, refus: null);
    }

    final Future<bool> future = prefs.setString(kCleRegistreElo, brut);
    // ↓↓↓ Aucun `await` entre le contrôle ci-dessus et cette inscription. ↓↓↓
    _ecrituresPersistantesEnCours.add(future);
    future.whenComplete(() {
      _ecrituresPersistantesEnCours.remove(future);
    }).ignore();

    try {
      final bool ok = await future;
      // ★ X1-b (P2) — APPLICATION ELO RÉUSSIE.
      //   Uniquement si `ok` : le disque contient alors exactement `brut`.
      //   Si l'écriture est refusée ou lève, on ne touche à RIEN : l'état
      //   antérieur reste vrai puisque le disque n'a pas changé.
      if (ok) {
        _observerNiveauRegistre(brut);
      }
      return ok
          ? (confirmee: true, refus: null)
          : (confirmee: false,
             refus: MotifRefusApplicationElo.intentionNonPersistee);
    } catch (_) {
      return (confirmee: false,
              refus: MotifRefusApplicationElo.intentionNonPersistee);
    }
  }

  /// ★ A7 (3.3-B2-e) — REFUS D'APPLICATION, SANS AUCUNE MUTATION.
  ///
  /// Point unique : tout refus d'application passe par ici, ce qui garantit
  /// qu'aucun chemin ne peut publier un motif sans laisser `_ratings` intact
  /// ET sans publier l'observable correspondant.
  ///
  /// Rend `EtatPersistanceElo.nonTentee` — la valeur existante qui signifie
  /// exactement « rien n'a été tenté ». Aucune valeur d'enum n'est ajoutée
  /// (`backup_service.dart` l.1101-1145 en fait un `switch` exhaustif).
  EtatPersistanceElo _refuserApplication(
    MotifRefusApplicationElo motif, {
    DiagnosticCoherenceElo? coherence,
    OrigineRegistreElo? origine,
    bool amorcage = false,
  }) {
    _dernierResultatMiseAJour = ResultatApplicationElo(
      etatRatings: EtatPersistanceElo.nonTentee,
      motifRefus: motif,
      coherenceAvant: coherence,
      origineAvant: origine,
      amorcageEffectue: amorcage,
      etapeEntree: null,
      idEntree: null,
      journalisationConfirmee: false,
    );
    debugPrint('[EloService] ⏭️ application ELO refusée (${motif.name}) — '
        'aucune mutation des ratings');
    return EtatPersistanceElo.nonTentee;
  }

  /// ★ A7 (3.3-B2-e) — CONSTRUIT L'INTENTION SANS MUTER LES RATINGS.
  ///
  /// Rend `null` si l'allocation `(id, horloge)` n'est pas prouvable sûre —
  /// refus plutôt que devinette, comme [AllocationEntreeElo.pour].
  ///
  /// ⚠️ FONCTION PURE À L'ÉGARD DE `_ratings` : elle lit et calcule, elle
  ///    n'affecte rien. C'est ce qui permet d'écrire l'intention AVANT la
  ///    mutation tout en annonçant une empreinte « après » exacte.
  IntentionEntreeElo? _construireIntentionCourse({
    required IdentiteCourseElo identite,
    required RegistreEloV3 registre,
    required Map<String, double> deltas,
    required List<ZtPartant> partants,
    required String discipline,
    required String empreinteAvant,
  }) {
    final AllocationEntreeElo? allocation = AllocationEntreeElo.pour(registre);
    if (allocation == null) return null;

    // ── Images et empreinte « après », calculées SANS toucher `_ratings`. ──
    // Les formules de transformation sont RECOPIÉES À L'IDENTIQUE de la boucle
    // de mutation (mêmes clamp, mêmes constantes). Toute divergence rendrait la
    // promesse fausse : les deux doivent rester alignées ligne à ligne.
    final Map<String, EloScore> projection =
        Map<String, EloScore>.of(_ratings);
    final List<ChevalJournalise> chevaux = <ChevalJournalise>[];

    deltas.forEach((cle, delta) {
      final nomDisc = cle.split('|');
      final nomNorm = nomDisc[0];

      String nomOriginal;
      try {
        nomOriginal = partants
            .firstWhere((p) => _cleNom(p.nom) == nomNorm)
            .nom;
      } catch (_) {
        nomOriginal = nomNorm; // le nom n'entre PAS dans l'empreinte
      }

      final EloScore? ancien = _ratings[cle];
      final double ancienR = ancien?.rating ?? _eloDefaut;
      final double nouveau = (ancienR + delta).clamp(_eloMin, _eloMax);
      final double varMois =
          ((ancien?.variationMois ?? 0.0) + delta).clamp(-300.0, 300.0);

      projection[cle] = EloScore(
        nomCheval:     nomOriginal,
        rating:        nouveau,
        nbCourses:     (ancien?.nbCourses ?? 0) + 1,
        variationMois: varMois,
      );

      chevaux.add(ChevalJournalise(
        cle: cle,
        nom: nomOriginal,
        // `avant == null` signifie : la clé était ABSENTE de `_ratings`.
        avant: ancien == null
            ? null
            : ImageRatingElo(
                rating:        ancien.rating,
                nbCourses:     ancien.nbCourses,
                variationMois: ancien.variationMois,
              ),
        apres: ImageRatingElo(
          rating:        nouveau,
          nbCourses:     (ancien?.nbCourses ?? 0) + 1,
          variationMois: varMois,
        ),
      ));
    });

    final String empreinteApres = empreinte64Ratings(projection);
    final int tsIntention = DateTime.now().millisecondsSinceEpoch;

    // ── Entrée d'INTENTION : `issue == null` et `tsFinal == null` (invariant
    //    du modèle, `elo_registre_v3.dart` l.379-388). ──────────────────────
    final EntreeRegistreElo entree = EntreeRegistreElo(
      id: allocation.id,
      type: TypeEntreeRegistre.course,
      cle: identite.courseKey,
      numR: identite.numR,
      numC: identite.numC,
      date: identite.date,
      discipline: identite.discipline,
      etape: EtapeEntreeRegistre.intention,
      issue: null,
      tsIntention: tsIntention,
      tsFinal: null,
      empreinteAvant: empreinteAvant,
      // ⚠️ L'empreinte du registre reste CELLE DU DISQUE tant que la mutation
      //    n'a pas eu lieu : annoncer `empreinteApres` ici rendrait le registre
      //    divergent vis-à-vis des ratings réellement persistés (§9).
      empreinteApres: empreinteApres,
      chevaux: chevaux,
    );

    // Le registre d'intention conserve l'empreinte des RATINGS PERSISTÉS
    // (= `empreinteAvant`, puisque rien n'a encore changé), et non la promesse.
    final RegistreEloV3 registreIntention = registre.copyWith(
      horloge: allocation.horloge,
      entrees: <EntreeRegistreElo>[...registre.entrees, entree],
    );

    return IntentionEntreeElo(
      id: allocation.id,
      registreAvecIntention: registreIntention,
      empreinteAvant: empreinteAvant,
      empreinteApres: empreinteApres,
      chevaux: chevaux,
      identite: identite,
      horloge: allocation.horloge,
      tsIntention: tsIntention,
    );
  }

  /// ★ A7 (3.3-B2-e) — PHASE D : COMPLÈTE LA MÊME ENTRÉE.
  ///
  /// `appliquee` si et seulement si les ratings sont persistés ET que le
  /// registre final est persisté. Sinon `nonConfirmee`, avec `issue` ∈
  /// {refusee, echouee} — état TERMINAL incertain, jamais convertible.
  ///
  /// Rend `true` ssi le registre final a été persisté en `appliquee`.
  ///
  /// ⚠️ EN CAS D'ÉCHEC, L'INTENTION N'EST PAS SUPPRIMÉE et aucune réécriture
  ///    n'est tentée : le registre reste sur l'état `intention`, donc l'entrée
  ///    reste incertaine, donc la course reste bloquée. C'est le comportement
  ///    voulu — un état incertain est PRÉFÉRABLE à une fausse preuve.
  Future<bool> _finaliserEntreeCourse({
    required IntentionEntreeElo prep,
    required EtatPersistanceElo etatRatings,
    required int generation,
    int? jetonNaissance,
  }) async {
    if (_estPerimeeParReset(generation)) return false;

    final bool appliquee = etatRatings == EtatPersistanceElo.persistee;
    final int tsFinal = DateTime.now().millisecondsSinceEpoch;

    final EntreeRegistreElo finale = EntreeRegistreElo(
      id: prep.id,
      type: TypeEntreeRegistre.course,
      cle: prep.identite.courseKey,
      numR: prep.identite.numR,
      numC: prep.identite.numC,
      date: prep.identite.date,
      discipline: prep.identite.discipline,
      etape: appliquee
          ? EtapeEntreeRegistre.appliquee
          : EtapeEntreeRegistre.nonConfirmee,
      // `appliquee` exige `persistee` ; `nonConfirmee` exige refusee|echouee.
      issue: appliquee
          ? IssueEcritureElo.persistee
          : (etatRatings == EtatPersistanceElo.refusee
              ? IssueEcritureElo.refusee
              : IssueEcritureElo.echouee),
      tsIntention: prep.tsIntention,
      tsFinal: appliquee ? tsFinal : null,
      empreinteAvant: prep.empreinteAvant,
      empreinteApres: prep.empreinteApres,
      chevaux: prep.chevaux,
    );

    // Remplacement de l'entrée par son `id`, sans réallocation.
    final List<EntreeRegistreElo> entrees =
        prep.registreAvecIntention.entrees.map((e) {
      return e.id == prep.id ? finale : e;
    }).toList(growable: false);

    // ⚠️ L'empreinte déclarée du registre suit l'état RÉEL des ratings :
    //    `empreinteApres` seulement si la mutation a été persistée.
    final RegistreEloV3 registreFinal =
        prep.registreAvecIntention.copyWith(
      empreinteRatings:
          appliquee ? prep.empreinteApres : prep.empreinteAvant,
      entrees: entrees,
    );

    final ({bool confirmee, MotifRefusApplicationElo? refus}) ecriture =
        await _persisterRegistre(
      registre: registreFinal,
      generation: generation,
      jetonNaissance: jetonNaissance,
    );
    // `appliquee` reste le terme principal : sous reset, il vaut `false`, donc
    // la finalisation est refusée même si l'écriture a été « acquittée ».
    return appliquee && ecriture.confirmee;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ A7 (3.3-C12 / A7-39) — PORTIER DE LA RESTITUTION VERBATIM.
  //
  //  ⚠️ POURQUOI CE PORTIER N'EST PAS `_doitEcrireTemoin`.
  //  `_doitEcrireTemoin` régit l'APPEND d'une entrée de témoin sur un registre
  //  DÉJÀ PRÉSENT : son étape 3 refuse `registreAbsent`. Or restaurer une
  //  sauvegarde enrichie sur un appareil VIERGE est précisément le cas où le
  //  registre DE L'APPAREIL est absent — le registre à écrire venant de la
  //  SAUVEGARDE, pas de l'appareil. Réutiliser `_doitEcrireTemoin` rendrait la
  //  restauration impossible sur un appareil neuf. Les deux fonctions répondent
  //  à deux questions différentes, et chacune a SA liste blanche.
  //
  //  LISTE BLANCHE — cinq refus, puis autorisation. Aucun cas par défaut.
  // ══════════════════════════════════════════════════════════════════════════

  /// Rend `null` si le registre de la sauvegarde peut être réécrit VERBATIM.
  ///
  /// FONCTION PURE : aucun accès disque, aucune mutation. L'empreinte relue lui
  /// est FOURNIE — c'est [_empreinteRelueDepuisDisque] qui porte la preuve.
  static MotifNonEcritureTemoin? _doitRestituerRegistre({
    required EtatPersistanceElo etatRatings,
    required String? empreinteRelue,
    required String empreinteApresMutation,
    required String? empreinteRegistre,
  }) {
    // 1. Écrire un registre avant de savoir que les ratings sont persistés
    //    reviendrait à attester d'un fait non advenu.
    if (etatRatings != EtatPersistanceElo.persistee) {
      return MotifNonEcritureTemoin.ratingsNonPersistes;
    }

    // 2. `null` = relecture non menée à son terme. Ce n'est PAS « disque vide ».
    if (empreinteRelue == null) {
      return MotifNonEcritureTemoin.relectureNonConfirmee;
    }

    // 3. Sans empreinte déclarée par le registre, il n'y a rien à confronter.
    if (empreinteRegistre == null) {
      return MotifNonEcritureTemoin.registreEnrichiIllisible;
    }

    // 4. F3' — la RAM APRÈS MUTATION doit être ce que le disque vient de rendre.
    //    Couvre tout écart entre le décodage du prédicat et celui de la
    //    mutation : si les deux divergeaient, cette égalité tomberait.
    if (empreinteRelue != empreinteApresMutation) {
      return MotifNonEcritureTemoin.registreEnrichiIncoherent;
    }

    // 5. La RAM persistée doit être EXACTEMENT ce que le registre déclare. Sans
    //    cela, écrire ce registre créerait un `divergent` immédiat.
    if (empreinteApresMutation != empreinteRegistre) {
      return MotifNonEcritureTemoin.registreEnrichiIncoherent;
    }

    return null; // restitution autorisée
  }

  /// CHEMIN ENRICHI — réécrit VERBATIM le registre transporté par la
  /// sauvegarde, sous les contrôles de [_doitRestituerRegistre].
  ///
  /// ── CE QUI EST ÉCRIT, ET CE QUI NE L'EST PAS ───────────────────────────
  ///   • la CHAÎNE de la sauvegarde, telle quelle (`registreBrut`) : aucune
  ///     entrée `importBackup` n'est ajoutée, `horloge` n'est pas avancée,
  ///     `origine` n'est pas réécrite, `schema`/`version` sont préservés ;
  ///   • donc AUCUNE allocation d'identifiant : le risque
  ///     `allocationImpossible` sur un `horloge` hérité très grand disparaît de
  ///     ce chemin — effet direct du verbatim, ce n'est pas une facilité ;
  ///   • l'ANCIEN registre de l'appareil n'est jamais supprimé au préalable :
  ///     une suppression ouvrirait `registreAbsent`, donc
  ///     `autoriseApplication == true`, c'est-à-dire la double application que
  ///     le registre doit précisément empêcher. Il est écrasé, jamais effacé.
  ///
  /// ── ORDRE DES ATTESTATIONS ─────────────────────────────────────────────
  ///   1. ratings persistés (`etat == persistee`) ;
  ///   2. relecture disque effective (`reload()` puis décodage) ;
  ///   3. F3' : RAM après mutation == empreinte RELUE ;
  ///   4. RAM après mutation == empreinte DÉCLARÉE par le registre.
  /// Un seul de ces contrôles qui tombe ⇒ aucun registre écrit, et un motif
  /// exact. Aucune valeur de repli, aucune réparation.
  /// ── PROTECTION CONSTATÉE (A7-39, correction finale) ─────────────────────
  /// Le champ [protectionApres] n'est PAS une intention : il porte le verdict
  /// du MODÈLE (`protegeContreDoubleApplication`) recalculé sur le disque
  /// RELU APRÈS l'écriture du registre. Il vaut `null` dès qu'aucune
  /// constatation n'est possible — refus, écriture non confirmée, diagnostic
  /// post-écriture non établi. `null` n'est jamais converti en protection.
  Future<({
    IssueEcritureElo? issue,
    OrigineRegistreElo? origine,
    MotifNonEcritureTemoin? motif,
    bool? protectionApres,
  })> _restaurerRegistreSauvegarde({
    required String registreBrut,
    required RegistreEloV3 registre,
    required int generation,
    required String empreinteApresMutation,
    required EtatPersistanceElo etatRatings,
  }) async {
    // La relecture n'est tentée que si les ratings sont persistés : le portier
    // rend `ratingsNonPersistes` sans avoir besoin du disque, et un `GETALL`
    // inutile serait du bruit dans les journaux des tests de concurrence.
    String? empreinteRelue;
    if (etatRatings == EtatPersistanceElo.persistee) {
      empreinteRelue = await _empreinteRelueDepuisDisque();
    }

    final MotifNonEcritureTemoin? refus = _doitRestituerRegistre(
      etatRatings: etatRatings,
      empreinteRelue: empreinteRelue,
      empreinteApresMutation: empreinteApresMutation,
      empreinteRegistre: registre.empreinteRatings,
    );
    if (refus != null) {
      debugPrint('[EloService] ⚠️ Restitution du registre REFUSÉE '
          '(${refus.name}) — registre de l\'appareil PRÉSERVÉ, aucune '
          'réparation automatique');
      return (issue: null, origine: null, motif: refus, protectionApres: null);
    }

    final ({
      IssueEcritureElo? issue,
      MotifNonEcritureTemoin? motif,
    }) ecriture = await _ecrireRegistreVerbatim(
      registreBrut: registreBrut,
      generation: generation,
    );
    if (ecriture.motif != null) {
      return (
        issue: ecriture.issue,
        origine: null,
        motif: ecriture.motif,
        protectionApres: null,
      );
    }

    // ══════════════════════════════════════════════════════════════════════
    //  ★ A7-39 — CONSTATATION DE LA PROTECTION APRÈS RESTAURATION.
    //
    //  La question posée n'est plus « ai-je voulu écrire un témoin ? » mais
    //  « le registre RÉELLEMENT EN PLACE protège-t-il ? ». La réponse ne peut
    //  venir que du disque relu APRÈS l'écriture, passée à la fonction de
    //  diagnostic du registre — jamais d'une valeur supposée.
    //
    //  POURQUOI CE SECOND PASSAGE EST NÉCESSAIRE. La relecture de
    //  `_doitRestituerRegistre` (étape 2) porte sur les RATINGS ; elle prouve
    //  que le disque rend bien l'empreinte attendue, mais elle ne dit RIEN de la
    //  chaîne du registre telle qu'elle a été écrite. Seule une relecture
    //  postérieure à `_ecrireRegistreVerbatim` peut l'établir : c'est cette
    //  chaîne-là que le modèle doit juger.
    //
    //  ⚠️ AUCUNE VALEUR PAR DÉFAUT. Si `reload()` lève, si la clé est absente
    //     ou d'un type inattendu, `_etablirDiagnosticApresRegistre` rend `null`
    //     et la protection reste INCONNUE — donc non revendiquée. Un `false`
    //     inventé serait aussi faux qu'un `true` inventé : les deux
    //     masqueraient l'absence de preuve.
    //
    //  ⚠️ COÛT : une lecture supplémentaire (`getInstance` + `reload`). Elle
    //     n'est consentie QUE sur ce chemin, après une écriture CONFIRMÉE. Les
    //     chemins de refus, d'échec d'écriture et le chemin historique
    //     n'en paient aucune.
    // ══════════════════════════════════════════════════════════════════════
    final bool? protectionApres = await _protectionConstateeApresEcriture();

    // L'origine revendiquée est celle du registre RÉELLEMENT écrit. Elle peut
    // être `courante` : A-2 l'autorise ICI, et seulement ici, parce que le
    // registre restauré est celui de la sauvegarde et qu'il décrit exactement
    // les ratings restaurés — F3, la relecture disque et F3' l'ont prouvé.
    debugPrint('[EloService] ✅ Registre RESTAURÉ VERBATIM '
        '(origine=${registre.origine.name}, ${registre.entrees.length} entrées '
        'héritées telles quelles, aucune entrée ajoutée) — protection '
        'constatée après écriture : ${protectionApres ?? "NON ÉTABLIE"}');
    return (
      issue: ecriture.issue,
      origine: registre.origine,
      motif: null,
      protectionApres: protectionApres,
    );
  }

  /// ★ A7-39 — Protection RÉELLEMENT constatée sur le registre en place.
  ///
  /// Relit le registre depuis le store (après `reload()`, comme toute lecture
  /// prouvante de ce service) et le soumet à `diagnostiquerRegistre`, la
  /// fonction PURE du modèle. Rend `null` — jamais `false` — si la constatation
  /// n'aboutit pas.
  ///
  /// ⚠️ `nombreRatings` vient de `_ratings` : sur ce chemin, `_sauvegarder` a
  ///    répondu `persistee` et la relecture des ratings a été confirmée avant
  ///    l'écriture du registre. Le cardinal en RAM est donc celui du disque,
  ///    et c'est lui qui distingue `registreAbsent`/`courante` de
  ///    `registreAbsent`/`historiqueInconnu`.
  ///
  /// ⚠️ Le registre relu est celui qui vient d'être écrit : un `divergent` ici
  ///    signifierait que l'écriture n'a pas produit ce qu'on annonce, et la
  ///    protection serait alors légitimement refusée par le modèle.
  Future<bool?> _protectionConstateeApresEcriture() async {
    final ({
      String? jsonRegistre,
      String empreinteDisque,
      int nombreRatings,
    })? disque = await _lireEtatEloProuve();
    if (disque == null) return null;

    final ResultatDiagnosticElo diagnostic = diagnostiquerRegistre(
      jsonRegistre: disque.jsonRegistre,
      empreinteDisque: disque.empreinteDisque,
      nombreRatings: disque.nombreRatings,
    );
    return diagnostic.protegeContreDoubleApplication;
  }

  /// ★ A7-39 — Lecture PROUVANTE de l'état ELO sur disque.
  ///
  /// `getInstance()` + `reload()` (le cache de `SharedPreferences` ne reflète
  /// pas le store sans lui), puis décodage TOLÉRANT identique à `_charger`,
  /// au diagnostic pré-import et à la relecture des ratings : une entrée
  /// illisible est ignorée, sans quoi l'empreinte ne serait comparable à rien.
  ///
  /// Rend `null` sur le moindre doute — store indisponible, `reload()` en
  /// échec, ratings non textuels ou JSON illisible, registre d'un type
  /// inattendu. Aucune valeur de repli, aucun `catch` muet qui transformerait
  /// une panne en constat.
  Future<({
    String? jsonRegistre,
    String empreinteDisque,
    int nombreRatings,
  })?> _lireEtatEloProuve() async {
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('[EloService] ⚠️ Constatation de protection impossible '
          '(SharedPreferences indisponible) : $e');
      return null;
    }

    try {
      await prefs.reload();
    } catch (e) {
      debugPrint('[EloService] ⚠️ Constatation de protection impossible '
          '(reload() en échec — cache non actualisé) : $e');
      return null;
    }

    // ── Ratings réellement persistés ───────────────────────────────────────
    final Map<String, EloScore> persistes = <String, EloScore>{};
    final Object? brutRatings = prefs.get(_prefsKey);
    if (brutRatings != null) {
      if (brutRatings is! String) {
        debugPrint('[EloService] ⚠️ Constatation de protection impossible : '
            '`$_prefsKey` n\'est pas une chaîne '
            '(reçu ${brutRatings.runtimeType})');
        return null;
      }
      if (brutRatings.isNotEmpty) {
        try {
          final Object? decode = jsonDecode(brutRatings);
          if (decode is! Map<String, dynamic>) {
            debugPrint('[EloService] ⚠️ Constatation de protection impossible : '
                '`$_prefsKey` n\'est pas un objet JSON');
            return null;
          }
          decode.forEach((cle, valeur) {
            try {
              persistes[cle] = EloScore.fromJson(valeur as Map<String, dynamic>);
            } catch (_) {}
          });
        } on FormatException catch (e) {
          debugPrint('[EloService] ⚠️ Constatation de protection impossible : '
              '`$_prefsKey` illisible ($e)');
          return null;
        }
      }
    }

    // ── Registre réellement présent ────────────────────────────────────────
    final Object? brutRegistre = prefs.get(kCleRegistreElo);
    if (brutRegistre != null && brutRegistre is! String) {
      debugPrint('[EloService] ⚠️ Constatation de protection impossible : '
          '`$kCleRegistreElo` n\'est pas une chaîne '
          '(reçu ${brutRegistre.runtimeType})');
      return null;
    }

    return (
      jsonRegistre: brutRegistre as String?,
      empreinteDisque: empreinte64Ratings(persistes),
      nombreRatings: persistes.length,
    );
  }

  /// CHEMIN HISTORIQUE — inchangé depuis B2-d2 : ajoute une entrée
  /// `horsCourse` de motif `importBackup` et force `historiqueInconnu`.
  ///
  /// ⚠️ N'est appelée QUE si la sauvegarde ne portait AUCUN registre
  ///    (`analyse.registreBrut == null`). C'est le contrat A-2 : une sauvegarde
  ///    ancienne ne permet pas de prétendre que l'historique est mémorisé.
  Future<({
    IssueEcritureElo? issue,
    OrigineRegistreElo? origine,
    MotifNonEcritureTemoin? motif,
    bool? protectionApres,
  })> _restaurerTemoinHistorique({
    required DiagnosticPreImportElo diagnostic,
    required EtatPersistanceElo etatRatings,
    required String empreinteApresMutation,
    required String? empreinteAvantDisque,
    required int nombreAvantDisque,
    required int nombreApres,
    required int generation,
  }) async {
    // `_doitEcrireTemoin` a rendu `null` : diagnostic établi + cohérent +
    // ratings persistés + changement d'empreinte. Les deux valeurs ci-dessous
    // sont donc NON NULLES par construction — on le VÉRIFIE plutôt que de le
    // supposer.
    final RegistreEloV3? registreAvant = diagnostic.resultat?.registre;
    if (registreAvant == null || empreinteAvantDisque == null) {
      // Inatteignable si `_doitEcrireTemoin` est correct. On refuse
      // explicitement au lieu de forcer : une incohérence interne ne doit
      // jamais devenir une écriture.
      return (
        issue: null,
        origine: null,
        motif: MotifNonEcritureTemoin.diagnosticNonEtabli,
        protectionApres: null,
      );
    }

    final ({
      IssueEcritureElo? issue,
      MotifNonEcritureTemoin? motif,
    }) ecriture = await _ecrireTemoinImport(
      registreAvant: registreAvant,
      empreinteAvant: empreinteAvantDisque,
      empreinteApres: empreinteApresMutation,
      nombreAvant: nombreAvantDisque,
      nombreApres: nombreApres,
      generation: generation,
    );
    return (
      issue: ecriture.issue,
      origine: ecriture.issue == IssueEcritureElo.persistee
          ? OrigineRegistreElo.historiqueInconnu
          : null,
      motif: ecriture.motif,
      // ⚠️ CHEMIN HISTORIQUE : AUCUNE constatation de protection n'est faite
      //    ici, et le contrat B2-d2 est préservé À L'IDENTIQUE. Le témoin écrit
      //    force `historiqueInconnu`, pour lequel
      //    `protegeContreDoubleApplication` vaut `false` PAR CONSTRUCTION : il
      //    n'y a rien à relire pour le découvrir. `null` signifie donc
      //    exactement « non constaté sur ce chemin », et la formule d'appel
      //    retombe sur son calcul d'origine — comportement inchangé, verrouillé
      //    par les tests A7 existants (dont `a7_33b2d2`, l.716).
      protectionApres: null,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ A7 (3.3-B1) — FILE FIFO STRICTE DES OPÉRATIONS CRITIQUES.
  //
  //  OBJET : sérialiser les opérations qui MUTENT `_ratings` puis persistent,
  //  afin qu'un import ne puisse pas écraser la RAM au milieu d'une
  //  application ELO (et réciproquement). C'est la décision D11, option A :
  //  une application ELO en cours TERMINE avant qu'un import puisse commencer.
  //
  //  ⚠️ CE QUE CETTE FILE N'EST PAS — À LIRE AVANT TOUTE EXTENSION :
  //   • ce n'est PAS le registre transactionnel de 3.3-B2/C. Aucune intention,
  //     aucun acquittement, aucun journal n'est écrit. `elo_registre_v3` n'est
  //     ni lu ni écrit par ce mécanisme ;
  //   • elle ne touche NI les formules ELO, NI les coefficients K, NI
  //     `facteurDistance`, NI aucun mécanisme d'apprentissage : elle n'enveloppe
  //     que la section « mutation RAM + persistance », jamais les calculs ;
  //   • elle n'ajoute AUCUNE clé SharedPreferences (le compte de
  //     `_toutesLesCles` reste 108) ;
  //   • elle ne change pas le format de `elo_ratings_v2`.
  //
  //  ⚠️ `executerResetComplet` N'ENTRE JAMAIS DANS CETTE FILE.
  //  Le reset draine `_ecrituresEnCours` (l.594-602) en attendant des futures
  //  que la file pourrait retenir ⇒ attente circulaire garantie. Le reset
  //  reste donc HORS file, et son drain n'attend jamais la file.
  //
  //  ⚠️ `_sauvegarder()` N'EST JAMAIS ENFILÉE ELLE-MÊME. Elle est appelée
  //  DEPUIS l'intérieur d'une opération enfilée ; l'enfiler créerait
  //  l'attente circulaire « l'opération attend la file, la file attend
  //  l'opération ». La file enveloppe l'OPÉRATION, pas la primitive d'écriture.
  //
  //  ORDRE : strictement FIFO, y compris en cas d'échec (la queue est
  //  relâchée dans tous les cas). DÉMARRAGE SYNCHRONE quand la file est vide :
  //  le cas non concurrent — celui de tous les tests historiques — n'observe
  //  donc AUCUN décalage de microtâche par rapport à avant 3.3-B1.
  // ══════════════════════════════════════════════════════════════════════════

  /// Queue de la file. `null` = file vide = aucune opération en cours ni
  /// en attente. Une opération qui entre alors démarre IMMÉDIATEMENT.
  Future<void>? _queueFile;

  /// Nombre de maillons vivants (opération en cours + opérations en attente).
  /// C'est le SEUL critère de vacuité : `_fileProfondeur == 0` ⟺ file vide.
  int _fileProfondeur = 0;

  /// Nombre d'opérations actuellement en attente dans la file (hors celle qui
  /// s'exécute). Observable par les tests, comme le registre d'écritures.
  int _nbOperationsFileEnAttente = 0;
  int get nbOperationsFileEnAttente => _nbOperationsFileEnAttente;

  /// Opérations enfilées qui ont été exécutées jusqu'au bout (succès ou échec).
  /// Compteur NOUVEAU, purement additif : aucun compteur existant n'est touché.
  int _nbOperationsFileExecutees = 0;
  int get nbOperationsFileExecutees => _nbOperationsFileExecutees;

  /// Opérations ABANDONNÉES par le CONTRÔLE G (génération périmée), donc
  /// rejetées AVANT toute mutation RAM.
  /// Compteur NOUVEAU, distinct de [nbRefusParReset] et de
  /// [nbRefusParGeneration] : ces deux-là sont mesurés par delta EXACT dans
  /// des tests validés (T8 attend `nbRefusParReset == avant + 1`) et ne
  /// doivent donc jamais recevoir d'incrément supplémentaire.
  int _nbAbandonsFileParGeneration = 0;
  int get nbAbandonsFileParGeneration => _nbAbandonsFileParGeneration;

  /// Bilan de la dernière bascule ELO, pour le diagnostic et l'interface.
  ///
  /// Exposé volontairement : la décision « SQLite est-il la référence ? » ne
  /// doit pas être une supposition de l'extérieur, elle doit être lisible.
  BilanBasculeElo? _bilanBascule;
  BilanBasculeElo? get bilanBascule => _bilanBascule;

  /// Issue RÉELLE de la dernière réplication vers SQLite.
  ///
  /// `false` signifie : prefs a accepté l'écriture, SQLite ne l'a pas reçue.
  /// Jusqu'ici cette information n'existait pas dans le service — la
  /// réplication rendait `void` — et une perte silencieuse restait donc
  /// indétectable. Elle est désormais observée (§27 : un défaut de repli doit
  /// être observable, il ne doit jamais être muet).
  bool? _derniereReplicationConfirmee;
  bool? get derniereReplicationConfirmee => _derniereReplicationConfirmee;

  /// Nombre d'écritures confirmées dans prefs dont la réplique SQLite a échoué
  /// pendant la vie de ce processus.
  int _nbRepliquesEnRetard = 0;
  int get nbRepliquesEnRetard => _nbRepliquesEnRetard;

  static Future<void> init() async => _instance._charger();

  /// Relit l'état ELO depuis le stockage, après une restauration.
  ///
  /// Sans cette méthode, une restauration écrirait bien les nouvelles valeurs
  /// sur le disque mais l'application continuerait d'afficher les anciennes
  /// jusqu'au redémarrage suivant — ce qui donnerait l'illusion d'un échec et
  /// pousserait l'utilisateur à relancer l'opération, donc à risquer un double
  /// apprentissage. La relecture est volontairement forcée : elle ne dépend pas
  /// de l'état `_charge`.
  ///
  /// Aucune formule n'est touchée : la méthode se contente de relire.
  Future<void> rechargerDepuisStockage() async {
    _charge = false;
    await _charger();
  }

  Future<void> _charger() async {
    if (_charge) return;
    try {
      final prefs = await SharedPreferences.getInstance();

      // ★ Ouverture du dépôt structuré. Non bloquante pour la suite : si le
      //   dépôt ne peut pas s'ouvrir, `_charger()` continue normalement et
      //   SharedPreferences reste la référence (aucune donnée perdue).
      await PontElo.instance.ouvrir();

      // ════════════════════════════════════════════════════════════════════
      //  ★ BASCULE ELO (§1 du présent tour) — SQLITE DEVIENT LA RÉFÉRENCE
      //
      //  Avant cette bascule, SQLite n'était qu'un miroir d'ÉCRITURE : chaque
      //  `setString` confirmé y était répliqué, mais la LECTURE au démarrage
      //  se faisait exclusivement depuis SharedPreferences. Deux supports,
      //  une seule source lue, donc un second état possible — exactement ce
      //  que §4 interdit.
      //
      //  Le point délicat, et la raison d'être de `BasculeElo` : « la base est
      //  vide » a six causes possibles, dont cinq n'appellent PAS une
      //  réimportation. Le discriminant est un marqueur DURABLE, jamais un
      //  nombre de lignes. Sans lui, une base vidée après migration serait
      //  réalimentée par les anciennes données restées dans prefs.
      // ════════════════════════════════════════════════════════════════════
      final depot = PontElo.instance.depotPourSauvegarde;
      var bilanBascule = await const BasculeElo().executer(
        depot: depot,
        prefs: prefs,
      );
      _bilanBascule = bilanBascule;
      if (kDebugMode) {
        debugPrint('[EloService] bascule : ${bilanBascule.etat.name} — '
            '${bilanBascule.nbLignesSqlite} ligne(s) SQLite, '
            '${bilanBascule.nbLignesPrefs} ligne(s) prefs');
        for (final m in bilanBascule.messages) {
          debugPrint('[EloService]   $m');
        }
      }

      // ── LECTURE : SQLite d'abord, quand il est la référence ────────────
      //
      // La règle est stricte : on ne lit SQLite que si la bascule l'a déclaré
      // référence. Dans le cas contraire (migration refusée, anomalie), on
      // reste sur SharedPreferences — jamais un mélange des deux, qui
      // produirait un état qui n'existe nulle part sur le disque.
      var luDepuisSqlite = false;
      if (bilanBascule.sqliteEstReference && depot != null) {
        try {
          final lignes = await depot.tousLesElo();
          if (lignes.isNotEmpty) {
            for (final l in lignes) {
              _ratings[l.cle] = EloScore(
                nomCheval: l.nomOrigine,
                rating: l.rating,
                nbCourses: l.nb,
                variationMois: l.var_,
              );
            }
            luDepuisSqlite = true;
            debugPrint('[EloService] ✅ ${_ratings.length} ratings lus depuis '
                'SQLITE (source de référence)');
          } else if (bilanBascule.etat == EtatBasculeElo.baseLegitimementVide ||
              bilanBascule.etat == EtatBasculeElo.premiereInstallation) {
            // Base vide ET marqueur valide : l'état légitime est « aucun
            // rating ». On ne va surtout pas chercher les anciennes données
            // de prefs, qui ne sont que des archives de migration.
            luDepuisSqlite = true;
            debugPrint('[EloService] base vide légitime : 0 rating, aucune '
                'réimportation depuis SharedPreferences');
          }
        } catch (e) {
          // Une lecture SQLite en échec ne doit pas vider la mémoire : on
          // retombe sur prefs, et l'écart est signalé.
          debugPrint('[EloService] ⚠️ lecture SQLite échouée ($e) : repli sur '
              'SharedPreferences pour cette session');
        }
      }

      if (!luDepuisSqlite) {
        // ── Migration v1 → v2 (anciennes clés sans discipline) ──────────
        final jsonV2 = prefs.getString(_prefsKey);
        if (jsonV2 == null || jsonV2.isEmpty) {
          final jsonV1 = prefs.getString(_prefsKeyOld);
          if (jsonV1 != null && jsonV1.isNotEmpty) {
            final Map<String, dynamic> old =
                jsonDecode(jsonV1) as Map<String, dynamic>;
            // Les anciens ELO sont stockés sans discipline — on les garde
            // sous la clé "NOM|" (discipline vide) pour ne pas les perdre
            // mais ils ne seront plus mis à jour (les nouvelles mises à jour
            // utilisent la clé avec discipline).
            old.forEach((key, val) {
              try {
                _ratings['$key|'] =
                    EloScore.fromJson(val as Map<String, dynamic>);
              } catch (_) {}
            });
            debugPrint('[EloService] ✅ Migration v1→v2 : '
                '${_ratings.length} ELO importés');
            // ★ v9.99 : supprimer l'ancienne clé après migration pour libérer
            //   l'espace. Ce retrait est sans risque : les valeurs viennent
            //   d'être copiées en mémoire sous une clé plus riche.
            await prefs.remove(_prefsKeyOld);
          }
        } else {
          final Map<String, dynamic> data =
              jsonDecode(jsonV2) as Map<String, dynamic>;
          data.forEach((key, val) {
            try {
              _ratings[key] = EloScore.fromJson(val as Map<String, dynamic>);
            } catch (_) {}
          });
        }
      }
      _charge = true;
      debugPrint('[EloService] ✅ ${_ratings.length} ratings chargés '
          '(${luDepuisSqlite ? "sqlite" : "prefs"})');

      // ★ D-20 / §11 — PURGE DES ORPHELINS SUPPRIMÉE.
      //
      //   ⚠️ COMPORTEMENT MESURÉ AVANT CORRECTION. Le code faisait :
      //        `_ratings.remove(k)` pour toute clé se terminant par « | »,
      //      c'est-à-dire tout rating dont la discipline n'a pas pu être
      //      résolue, issu de la migration v1→v2. Ces ratings étaient donc
      //      DÉFINITIVEMENT DÉTRUITS, puis la suppression était persistée
      //      immédiatement sur le disque (`_sauvegarder()`).
      //
      //   ⚠️ POURQUOI C'EST INTERDIT. D-20 est sans ambiguïté :
      //      « Conserver intégralement les ratings existants, y compris ceux
      //      dont l'identité n'est pas encore résolue. Aucune suppression
      //      arbitraire. » Le motif invoqué par le code (« jamais lues car le
      //      moteur cherche NOM|DISCIPLINE ») est un argument d'UTILITÉ, pas
      //      une preuve d'ABSENCE D'INFORMATION : ces lignes portent un nom et
      //      un rating, donc de la connaissance issue de l'apprentissage, non
      //      reconstructible sans rejouer l'historique (§17).
      //
      //   ✅ CE QUI EST FAIT À LA PLACE. Les ratings sont CONSERVÉS dans
      //      `_ratings` et rendus consultables. Le marqueur historique
      //      `elo_orphelins_purges_v1` est écrit pour que le comportement soit
      //      idempotent (aucune re-purge au prochain démarrage), et le nombre
      //      conservé est journalisé. Aucune valeur n'est modifiée, aucune
      //      fusion n'est faite, aucun rating n'est recalculé.
      final flagPurge = prefs.getBool('elo_orphelins_purges_v1') ?? false;
      if (!flagPurge) {
        final clefsOrphelines = _ratings.keys
            .where((k) => k.endsWith('|'))
            .toList(growable: false);

        // Marqueur écrit même si la liste est vide : le traitement est ainsi
        // exécuté une seule fois, sans dépendre du nombre trouvé.
        await prefs.setBool('elo_orphelins_purges_v1', true);

        if (clefsOrphelines.isNotEmpty) {
          debugPrint('[EloService] ✅ ${clefsOrphelines.length} rating(s) '
              'd\'identité non résolue CONSERVÉ(S) (D-20) — aucune purge. '
              'Ces valeurs restent consultables et restaurées par la '
              'sauvegarde.');
          // Persistance non requise ici : rien n'a changé dans `_ratings`.
          // Écrire coûterait une réécriture complète du volume pour rien.
        }
      }
    } catch (e) {
      debugPrint('[EloService] ⚠️ Erreur chargement : $e');
      _charge = true;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ A7 (3.3-B1) — MÉCANISME DE LA FILE FIFO STRICTE.
  //
  //  [operation] reçoit la génération capturée à l'ENTRÉE de la file et doit
  //  la vérifier elle-même (contrôle G) AVANT toute mutation RAM, puis après
  //  chacune de ses attentes pertinentes. La file ne fait pas ce contrôle à la
  //  place de l'opération : elle ne sait pas où se trouve la mutation.
  // ──────────────────────────────────────────────────────────────────────────
  Future<EtatPersistanceElo> _executerEnFile(
      Future<EtatPersistanceElo> Function(int generation) operation) {
    // ── 1. CAPTURE SYNCHRONE — aucun `await` en amont dans cette méthode. ──
    // C'est l'unique garantie qu'une opération née avant un reset soit vue
    // comme périmée, même si le reset démarre avant qu'elle n'ait pu courir.
    //
    // ★ A2 — LE JETON ENCODE LA NAISSANCE. Si un reset court DÉJÀ au moment de
    //   cette capture, la valeur est NÉGATIVE et identifie CE reset ; sinon
    //   c'est la génération courante (≥ 0). Une opération née pendant un reset
    //   ne peut donc plus jamais être confondue avec une opération valide pour
    //   la génération en cours : c'est un fait IMMUABLE, qui ne dépend d'aucun
    //   état mutable et ne peut donc pas devenir obsolète pendant une attente.
    final int generation = _resetEnCours
        ? _jetonNaissancePendantReset(_generationCache)
        : _generationCache;

    // ── 2. VACUITÉ LUE SUR LA PROFONDEUR, JAMAIS SUR LA QUEUE. ─────────────
    // `_queueFile` n'est jamais remis à `null` : le remettre depuis le
    // `finally` d'une opération exposerait une course avec l'affectation de la
    // queue du maillon suivant. La profondeur est l'unique critère :
    // `_fileProfondeur == 0` ⟺ file vide ⟹ démarrage synchrone.
    final Future<void>? queuePrecedente =
        _fileProfondeur == 0 ? null : _queueFile;
    final Completer<EtatPersistanceElo> resultat =
        Completer<EtatPersistanceElo>();

    _fileProfondeur++;

    Future<void> corps() async {
      // ── 3. Attente STRICTE du maillon précédent, si la file est occupée. ──
      // `queuePrecedente` ne peut jamais échouer (la queue est enveloppée dans
      // un `then` neutralisant l'erreur). Aucune attente circulaire n'est
      // possible : on n'attend QUE le maillon précédent, jamais la file
      // entière ni `executerResetComplet`.
      if (queuePrecedente != null) {
        _nbOperationsFileEnAttente++;
        await queuePrecedente;
        _nbOperationsFileEnAttente--;
      }
      try {
        final EtatPersistanceElo etat = await operation(generation);
        _nbOperationsFileExecutees++;
        if (!resultat.isCompleted) resultat.complete(etat);
      } catch (e, st) {
        // ── 4. UNE ERREUR NE BLOQUE JAMAIS LA FILE. ──
        // Elle est rendue à l'appelant TELLE QUELLE (jamais convertie en
        // succès, jamais transformée en état de persistance), et le `finally`
        // ci-dessous relâche la place : le maillon suivant s'exécutera.
        if (!resultat.isCompleted) resultat.completeError(e, st);
      } finally {
        // ── 5. RELÂCHEMENT INCONDITIONNEL. ──
        _fileProfondeur--;
      }
    }

    // Démarrage SYNCHRONE quand la file est vide : `corps()` exécute son début
    // immédiatement, puis l'opération elle-même jusqu'à sa première attente —
    // exactement comme avant 3.3-B1. Aucun décalage de microtâche n'est donc
    // introduit pour le cas non concurrent, qui est celui de tous les tests
    // historiques.
    final Future<void> maillon = corps();
    // La queue est rendue NON-ÉCHOUANTE : un échec est déjà porté par
    // `resultat`, il ne doit pas se propager dans la chaîne et bloquer les
    // maillons suivants.
    _queueFile = maillon.then<void>((_) {}, onError: (Object _) {});

    return resultat.future;
  }

  /// ★ A7 (3.3-B1) — CONTRÔLE G : l'opération est-elle devenue périmée ?
  ///
  /// Distinct des contrôles 1 et 2 de [_sauvegarder] :
  ///   • le contrôle 1 (`_resetEnCours`) refuse une ÉCRITURE née pendant
  ///     l'effacement, APRÈS la mutation RAM — comportement exigé par V29-I
  ///     et T8, qui attendent que la RAM soit peuplée et que
  ///     `nbRefusParReset` soit incrémenté ;
  ///   • le contrôle 2 (génération) refuse une écriture née avant le reset ;
  ///   • le contrôle G, lui, refuse l'OPÉRATION ENTIÈRE avant qu'elle ne touche
  ///     `_ratings` — c'est ce qui empêche une opération EN ATTENTE de
  ///     ressusciter des ratings après un reset.
  ///
  /// Il N'INCINCRÉMENTE NI [nbRefusParReset] NI [nbRefusParGeneration] : ces
  /// compteurs sont mesurés par delta EXACT dans des tests validés.
  bool _estPerimeeParReset(int generation) {
    // ★ A2 — SÉPARATION DES DEUX CONTRÔLES (arbitrage PRIORITÉ 1).
    //   Un JETON NÉGATIF n'est PAS une génération historique : il ne doit donc
    //   JAMAIS être déclaré « périmé » par ce contrôle. Sans cette garde, une
    //   opération née pendant le reset s'abandonnait AVANT le point de
    //   non-retour, ce qui cassait T8 / V29-I / V29-H (mesuré : 3 échecs).
    //   Pour un jeton, la seule décision est prise par
    //   [_neePendantResetAcheve], et pendant le reset par le contrôle 1 de
    //   [_sauvegarder] — comportement historique intégralement préservé.
    if (_neePendantReset(generation)) return false;
    return generation != _generationCache;
  }

  /// Signale l'abandon d'une opération par le contrôle G et rend l'état.
  EtatPersistanceElo _abandonnerParGenerationFile(String methode) {
    _nbAbandonsFileParGeneration++;
    debugPrint('[EloService] ⚠️ $methode : opération ABANDONNÉE par le '
        'contrôle de génération (reset intervenu) — aucune mutation RAM, '
        'aucune écriture tentée');
    return EtatPersistanceElo.abandonneeParReset;
  }

  /// ★ B5c-RDR-05 — Enveloppe l'écriture disque dans la barrière de reset.
  ///
  /// Deux contrôles historiques INCHANGÉS (`_resetEnCours`, puis génération),
  /// ★ A2 (B2-e) — l'opération a-t-elle été ENGAGÉE pendant un reset ?
  ///
  /// Vrai si [generation] est un jeton négatif, c'est-à-dire si l'opération a
  /// été capturée par `_executerEnFile` alors qu'un reset courait. Cette
  /// propriété est IMMUABLE : elle ne dépend d'aucun état mutable, donc elle ne
  /// peut pas devenir obsolète pendant une attente — contrairement à un
  /// contrôle posé sur `_resetEnCours`.
  bool _neePendantReset(int generation) => generation < 0;

  /// Rend [generation] comme jeton de naissance, ou `null` si l'opération n'est
  /// PAS née pendant un reset (aucun contrôle supplémentaire n'est alors
  /// nécessaire : les contrôles historiques suffisent et restent inchangés).
  int? _jetonNaissance(int generation) =>
      _neePendantReset(generation) ? generation : null;

  /// ★ A2 (B2-e) — opération ENGAGÉE pendant un reset, et ce reset est-il
  /// ACHEVÉ (barrière rouverte) ?
  ///
  /// Couvre exactement la fenêtre mesurée par B2e-9 : le reset est allé au bout
  /// (`_generationCache` a dépassé la génération du jeton) et plus aucune
  /// barrière ne bloque l'écriture. La seule issue licite est alors l'ABANDON
  /// AVANT toute écriture : la génération a été effacée, rien de ce que
  /// l'opération porte ne peut être durable.
  bool _neePendantResetAcheve(int generation) {
    // ⚠️ MESURE QUI CORRIGE UNE PREMIÈRE TENTATIVE FAUSSE : comparer
    //    `_generationCache > generationDuJeton` ne détecte RIEN, parce que la
    //    génération capturée pendant un reset EST DÉJÀ celle de ce reset
    //    (`executerResetComplet` incrémente avant de drainer). Le seul fait
    //    observable à la reprise est donc : « je suis née sous barrière, et
    //    plus aucune barrière n'est fermée MAINTENANT ».
    //    Si un SECOND reset court à la reprise, le jeton vaut `true` : on
    //    laisse alors avancer, et c'est le contrôle 1 de `_sauvegarder` qui
    //    refuse — aucune écriture n'est possible sous barrière.
    return _neePendantReset(generation) && !_resetEnCours;
  }

  /// ★ A2 (B2-e) — contrôle d'entrée COMMUN aux deux primitive d'écriture
  /// persistante (`_persisterRegistre`, `_ecrireTemoinImport`).
  ///
  /// Rend le motif de refus à opposer à l'appelant, ou `null` si l'écriture
  /// peut se poursuivre. Placé APRÈS la dernière attente, il est de toute façon
  /// doublé par le jeton de naissance, qui lui est immuable.
  MotifRefusApplicationElo? _motifRefusEcriturePersistante(int generation) {
    if (_neePendantResetAcheve(generation)) {
      debugPrint('[EloService] ⛔ écriture persistante REFUSÉE : opération née '
          'pendant un reset ACHEVÉ (jeton=$generation, '
          'génération=$_generationCache) — aucune écriture tentée');
      return MotifRefusApplicationElo.intentionNonPersistee;
    }
    return null;
  }

  /// mêmes compteurs, mêmes points d'incrément. Ce qui change en 3.2 : les
  /// sorties ne sont plus muettes, elles rendent une valeur explicite.
  ///
  /// ★ SÉMANTIQUE DU RETOUR (3.2) : [EtatPersistanceElo.refusee] et
  /// [EtatPersistanceElo.echouee] signifient PERSISTANCE NON CONFIRMÉE,
  /// JAMAIS « disque inchangé ». Aucun rejeu ne doit en être déduit.
  Future<EtatPersistanceElo> _sauvegarder([int? jetonNaissance]) async {
    if (_resetEnCours) {
      _nbRefusParReset++;
      return EtatPersistanceElo.abandonneeParReset; // Contrôle 1
    }
    // ★ A2 — contrôle 1-bis : opération ENGAGÉE pendant un reset ACHEVÉ.
    //   Placé AVANT l'attente de `getInstance()`, mais il ne peut PAS devenir
    //    obsolète : le jeton est immuable. Un second contrôle existe après
    //    l'attente, pour couvrir un reset qui démarrerait entre-temps.
    if (jetonNaissance != null && _neePendantResetAcheve(jetonNaissance)) {
      _nbRefusParGeneration++;
      return EtatPersistanceElo.abandonneeParReset;
    }
    final generation = _generationCache;
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      // ★ 3.2 : n'était qu'un `debugPrint` + `return` muet. L'échec est
      // désormais COMPTÉ et CONSERVÉ — plus jamais silencieux.
      _nbEchouees++;
      _derniereErreurEcriture = e;
      debugPrint('[EloService] ⚠️ Sauvegarde impossible '
          '(SharedPreferences indisponible) : $e');
      return EtatPersistanceElo.echouee;
    }
    // ★ A2 — re-vérification APRÈS l'attente, sur le jeton immuable.
    if (jetonNaissance != null && _neePendantResetAcheve(jetonNaissance)) {
      _nbRefusParGeneration++;
      return EtatPersistanceElo.abandonneeParReset;
    }
    if (_resetEnCours || generation != _generationCache) {
      // Contrôle 2 — distinct du contrôle 1 : une génération peut avoir
      // changé alors qu'aucun reset n'est plus EN COURS (il est terminé).
      _nbRefusParGeneration++;
      return EtatPersistanceElo.abandonneeParReset;
    }
    // ↓↓↓ AUCUN `await` de ce point jusqu'au `add` (invariant P1) ↓↓↓
    final Future<EtatPersistanceElo> f = _executerSauvegarde(prefs);
    _ecrituresEnCours.add(f);
    // ★ A7 (3.3-B2-a) : la MÊME future rejoint le suivi des écritures
    //   persistantes, qui pilote le drain. Les deux ensembles restent
    //   DISTINCTS (voir la documentation du champ) mais reçoivent ici la même
    //   future : aucune écriture n'est perdue, aucune n'est comptée deux fois
    //   dans un même ensemble.
    _ecrituresPersistantesEnCours.add(f);
    f.whenComplete(() {
      _ecrituresEnCours.remove(f);
      _ecrituresPersistantesEnCours.remove(f);
    }).ignore();
    return f;
  }

  /// Corps de l'écriture, isolé pour que [_sauvegarder] obtienne la future
  /// AVANT le premier `await` — c'est la condition du registre sans trou.
  ///
  /// ★ A7 (3.2) — DEUX changements, et deux seulement :
  ///   • les retours `bool` de `setString`/`setInt` ne sont plus jetés ;
  ///   • l'exception n'est plus avalée : journalisée, comptée, convertie.
  ///
  /// ⚠️ NOMBRE D'ÉCRITURES — ÉNONCÉ EXACT (corrigé en 3.2 / lot 1, cf. C2).
  /// Au cas NOMINAL, le comportement est identique à avant 3.2 : deux
  /// écritures, `_prefsKey` puis `_prefsKeyTs`, dans cet ordre exact.
  ///
  /// En CAS D'ÉCHEC de `setString`, il DIFFÈRE, et il faut le savoir :
  /// avant 3.2 les deux `await` vivaient dans UN SEUL `try`, donc une
  /// exception sur `setString` sautait `setInt` (0 écriture `_ts`) ; depuis
  /// 3.2 `_prefsKeyTs` est écrite dans un `try` SÉPARÉ, donc elle est
  /// TENTÉE (1 écriture `_ts`) même quand les ratings ont échoué. C'est
  /// voulu : c'est ce qui rend l'échec secondaire observable et comptable
  /// séparément, sans jamais altérer le résultat principal.
  ///
  /// ⚠️ `_prefsKeyTs` N'EST PAS une preuve d'application ELO. Son échec
  /// n'altère donc JAMAIS le résultat principal : si `setString` a confirmé
  /// le rating, le résultat reste [EtatPersistanceElo.persistee] et le défaut
  /// secondaire est seulement compté dans [nbEchecsTs].
  Future<EtatPersistanceElo> _executerSauvegarde(
      SharedPreferences prefs) async {
    EtatPersistanceElo etat;
    try {
      final data  = <String, dynamic>{};
      _ratings.forEach((k, v) => data[k] = v.toJson());
      // ★ 3.2 : le booléen était JETÉ, il ne l'est plus.
      final bool okRatings =
          await prefs.setString(_prefsKey, jsonEncode(data));
      if (okRatings) {
        _nbPersistees++;
        etat = EtatPersistanceElo.persistee;
      } else {
        _nbRefuseesStockage++;
        etat = EtatPersistanceElo.refusee;
        debugPrint('[EloService] ⚠️ Sauvegarde REFUSÉE par le stockage sur '
            '`$_prefsKey` — persistance NON CONFIRMÉE (le disque n\'est PAS '
            'prouvé inchangé)');
      }
    } catch (e, st) {
      // ★ 3.2 : exception JOURNALISÉE, COMPTÉE, CONSERVÉE — jamais avalée.
      _nbEchouees++;
      _derniereErreurEcriture = e;
      etat = EtatPersistanceElo.echouee;
      debugPrint('[EloService] ⚠️ Exception pendant la sauvegarde de '
          '`$_prefsKey` — persistance NON CONFIRMÉE : $e\n$st');
    }

    // ── Horodatage SECONDAIRE, hors du mécanisme de preuve ────────────────
    // Écrit dans TOUS les cas, exactement comme avant. Son issue ne modifie
    // jamais `etat` : elle est seulement rendue observable.
    try {
      final bool okTs = await prefs.setInt(
          _prefsKeyTs, DateTime.now().millisecondsSinceEpoch);
      if (!okTs) {
        _nbEchecsTs++;
        debugPrint('[EloService] ⚠️ Horodatage REFUSÉ sur `$_prefsKeyTs` '
            '(défaut SECONDAIRE — le rating n\'est PAS concerné)');
      }
    } catch (e) {
      _nbEchecsTs++;
      debugPrint('[EloService] ⚠️ Exception sur `$_prefsKeyTs` '
          '(défaut SECONDAIRE — le rating n\'est PAS concerné) : $e');
    }

    // ── RACCORDEMENT AU DÉPÔT STRUCTURÉ (pont ELO) ────────────────────────
    //
    //   La réplication n'a lieu QUE si la persistance principale est confirmée :
    //   le dépôt ne contient donc jamais un état que SharedPreferences a
    //   refusé. Un échec du pont est compté et journalisé par le pont lui-même,
    //   et ne remonte jamais ici : `etat` reste celui de la persistance
    //   principale, qui est la référence.
    //
    // ★ §4 — DEUX MAGASINS, DEUX ÉTATS : LE DÉFAUT MESURÉ ET SA CORRECTION.
    //
    //   Avant ce correctif, la réplication rendait `void` et avalait l'échec.
    //   Tant que SQLite n'était qu'un miroir jamais relu, c'était sans
    //   conséquence. Depuis la bascule, `_charger()` lit SQLite EN PRIORITÉ :
    //   une écriture confirmée par `setString` mais non répliquée devenait
    //   DÉFINITIVEMENT invisible au démarrage suivant — sans exception, sans
    //   message, sans écart observable. Une perte silencieuse.
    //
    //   Correction, strictement dans l'ordre de sûreté :
    //     1. si la réplication a réussi → les deux supports sont d'accord, rien
    //        d'autre à faire (cas nominal, aucune écriture supplémentaire) ;
    //     2. si elle a échoué → on repose le marqueur de bascule à l'état
    //        `migrationNecessaire`. Au démarrage suivant, `BasculeElo` voit une
    //        base sans marqueur valide avec des ratings dans prefs, et REJOUE
    //        la migration — qui est idempotente et vérifiée par contrôle
    //        indépendant avant de reposer le marqueur.
    //   Ainsi une réplique en retard est RATTRAPÉE automatiquement, et jamais
    //   troquée contre une réimportation abusive : le marqueur n'est retiré que
    //   lorsque SQLite est réellement en retard, jamais quand il est à jour.
    //
    //   ⚠️ Aucun rating n'est calculé, modifié ni fusionné ici : la marqueur ne
    //   porte que l'état de la migration. Aucune formule, aucun poids, aucun
    //   seuil n'est concerné.
    if (etat == EtatPersistanceElo.persistee) {
      final replique = await PontElo.instance.repliquer(_ratings);
      _derniereReplicationConfirmee = replique;
      if (!replique) {
        _nbRepliquesEnRetard++;
        await _signalerRepliqueEnRetard();
        debugPrint('[EloService] ⚠️ réplique SQLite EN RETARD : le marqueur '
            'de bascule sera rejoué au prochain démarrage (aucune écriture '
            'confirmée n\'est perdue)');
      }
    }

    return etat;
  }

  /// Remet le marqueur de bascule en état « migration nécessaire ».
  ///
  /// Appelé **uniquement** quand prefs a confirmé une écriture que SQLite n'a
  /// pas reçue. Le marqueur reste dans SQLite (il décrit la base qu'il
  /// qualifie), il change seulement d'état : la prochaine ouverture rejouera
  /// la migration, qui est idempotente et vérifiée.
  ///
  /// Ne lève jamais : un échec ici laisserait simplement la réplique en retard,
  /// comme avant le correctif — l'application ne doit pas s'arrêter pour cela.
  Future<void> _signalerRepliqueEnRetard() async {
    try {
      final depot = PontElo.instance.depotPourSauvegarde;
      if (depot == null) return;
      final contenu = <String, Object?>{
        'etat': 'migration_necessaire',
        'date': DateTime.now().toUtc().toIso8601String(),
        'nb_lignes': await depot.compterElo(),
        'source': 'shared_preferences',
        'schema': 1,
        'motif': 'replique_en_retard',
      };
      await depot.ecrireMeta(kMetaBasculeElo, jsonEncode(contenu));
    } catch (e) {
      debugPrint('[EloService] ⚠️ signalement de réplique en retard impossible '
          '($e) : la réplique reste en retard, comme avant le correctif');
    }
  }
  String _cleNom(String nom) =>
      nom.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');

  // ★ v9.92 : normalise le type de course en discipline canonique
  static String normaliserDiscipline(String type) {
    final t = type.toLowerCase();
    if (t.contains('attele') || t.contains('attelé') || t.contains('trot a')) return 'TROT_ATTELE';
    if (t.contains('monte')  || t.contains('monté')  || t.contains('trot m')) return 'TROT_MONTE';
    if (t.contains('haie')   || t.contains('haies'))                           return 'OBSTACLE_HAIE';
    if (t.contains('steeple'))                                                  return 'OBSTACLE_STEEPLE';
    if (t.contains('cross'))                                                    return 'OBSTACLE_CROSS';
    if (t.contains('plat'))                                                     return 'PLAT';
    if (t.contains('trot'))                                                     return 'TROT_ATTELE';
    if (t.contains('galop'))                                                    return 'PLAT';
    return 'INCONNU';
  }

  // ★ v9.92 : clé composite NOM|DISCIPLINE
  String _cle(String nom, String discipline) =>
      '${_cleNom(nom)}|${normaliserDiscipline(discipline)}';

  // ── Obtenir le score ELO d'un cheval pour une discipline ──────────
  EloScore getScore(String nomCheval, {String discipline = ''}) {
    if (discipline.isNotEmpty) {
      final cleDisc = _cle(nomCheval, discipline);
      if (_ratings.containsKey(cleDisc)) return _ratings[cleDisc]!;
    }
    // Fallback : ancienne clé globale (migration)
    final cleOld = '${_cleNom(nomCheval)}|';
    return _ratings[cleOld] ??
        EloScore(nomCheval: nomCheval, rating: _eloDefaut);
  }

  double getRating(String nomCheval, {String discipline = ''}) =>
      getScore(nomCheval, discipline: discipline).rating;

  // ── Mettre à jour les ELO après une arrivée ── ★ v9.92 : + discipline
  //
  // ★ A7 (3.2) : retourne l'ISSUE de la persistance. Les calculs, formules,
  //   K-factors et les deux sorties anticipées sont STRICTEMENT inchangés ;
  //   seules leurs valeurs de retour deviennent explicites.
  //
  // ★ A7 (3.3-B1) : l'opération est désormais ENFILÉE. La signature publique
  //   est IDENTIQUE (`Future<EtatPersistanceElo>`) — les appelants ne changent
  //   pas. La file enveloppe l'opération ENTIÈRE : chargement éventuel,
  //   mutation RAM et persistance. Aucune formule n'est déplacée ni modifiée :
  //   le corps est seulement reçu avec la génération capturée à l'entrée.
  //
  // ★ A7 (3.3-B2-b) : + `courseKey`, OPTIONNEL et NOMMÉ.
  //   Les appels existants ne changent PAS d'une ligne : le paramètre a une
  //   valeur par défaut (`null`) et aucun appel positionnel n'existe (mesuré :
  //   l'unique appel de production, `data_refresh_service.dart:1267`, passe
  //   trois arguments NOMMÉS). `data_refresh_service.dart` n'est donc PAS
  //   modifié par ce lot — c'est l'objet du lot distinct B2-e.
  Future<EtatPersistanceElo> mettreAJourApresArrivee({
    required List<int>       arrivee,
    required List<ZtPartant> partants,
    String discipline = '',  // ★ v9.92 : type de course passé par l'appelant
    String? courseKey,       // ★ B2-b : identité de course, optionnelle
  }) {
    return _executerEnFile((int generation) => _mettreAJourApresArrivee(
          arrivee:    arrivee,
          partants:   partants,
          discipline: discipline,
          courseKey:  courseKey,
          generation: generation,
        ));
  }

  /// Corps de [mettreAJourApresArrivee], exécuté DANS la file.
  ///
  /// [generation] est la valeur de `_generationCache` capturée SYNCHRONEMENT à
  /// l'entrée de la file, avant toute microtâche. Elle est vérifiée :
  ///   • AVANT `_charger()`, pour qu'une opération restée en attente pendant un
  ///     reset soit abandonnée sans même relire le disque ;
  ///   • APRÈS `_charger()`, qui est la SEULE attente séparant l'entrée de la
  ///     mutation RAM — c'est le contrôle qui interdit une résurrection.
  ///
  /// [courseKey] est FACULTATIVE. Elle est validée en [IdentiteCourseElo] dès
  /// l'entrée, AVANT toute attente, mais son résultat n'est publié dans
  /// [derniereIdentiteCourse] qu'AU POINT DE NON-RETOUR (juste avant la
  /// mutation RAM) : une opération abandonnée ou sans effet ne laisse aucune
  /// identité observable. Elle ne conditionne AUCUNE écriture : les ratings
  /// sont mis à jour et persistés exactement comme avant B2-b, que l'identité
  /// soit exploitable ou non.
  Future<EtatPersistanceElo> _mettreAJourApresArrivee({
    required List<int>       arrivee,
    required List<ZtPartant> partants,
    required String          discipline,
    required String?         courseKey,
    required int             generation,
  }) async {
    // ★ A2 — jeton de NAISSANCE (négatif si l'opération est née pendant un
    // reset). Il est propagé à TOUTES les primitives d'écriture persistante,
    // qui refusent alors d'écrire si ce reset est déjà terminé.
    final int? jeton = _jetonNaissance(generation);
    // ── B2-b : identité de course, VALIDÉE dès l'entrée, sans effet de bord. ──
    // `IdentiteCourseElo.tenter` ne lève pas, ne lit rien sur le disque et ne
    // touche à AUCUN rating : elle rend `null` si la clé n'est pas exploitable.
    //
    // Le résultat est gardé en LOCAL, et non affecté au champ observable : une
    // opération qui va être ABANDONNÉE (contrôle G, listes vides, arrivée trop
    // courte) ne doit laisser derrière elle AUCUNE identité que la suite
    // pourrait prendre pour un journal exploitable. L'affectation se fait donc
    // au point de non-retour, juste avant la mutation RAM (voir plus bas).
    //
    // Le champ est remis à `null` ICI, avant toute attente : une opération sans
    // `courseKey` ne doit jamais laisser observer l'identité de la PRÉCÉDENTE.
    _derniereIdentiteCourse = null;
    _dernierResultatMiseAJour = null;
    final IdentiteCourseElo? identite = IdentiteCourseElo.tenter(
      courseKey:  courseKey,
      discipline: discipline,
    );

    // ── Contrôle G n°1 : opération périmée AVANT toute lecture disque. ──────
    if (_estPerimeeParReset(generation)) {
      return _abandonnerParGenerationFile('mettreAJourApresArrivee');
    }

    if (!_charge) await _charger();

    // ── Contrôle G n°2 : après `_charger()`, avant toute autre attente. ─────
    if (_estPerimeeParReset(generation)) {
      return _abandonnerParGenerationFile('mettreAJourApresArrivee');
    }

    if (arrivee.isEmpty || partants.isEmpty) {
      return EtatPersistanceElo.nonTentee; // rien à écrire : pas un échec
    }

    final Map<int, ZtPartant> mapPartants = {
      for (final p in partants)
        if (int.tryParse(p.numero) != null) int.parse(p.numero): p
    };
    final n = arrivee.length;
    // « Arrivée trop courte » n'est pas un refus : c'est « rien à faire ». Ce
    // cas conserve donc exactement sa sémantique B2-b (`nonTentee`, sans motif).
    if (n < 2) return EtatPersistanceElo.nonTentee;

    // ══════════════════════════════════════════════════════════════════════════
    //  A7 / B2-e — ÉTAPE A : IDENTITÉ, REGISTRE, COHÉRENCE, DOUBLON, ANTÉRIORITÉ
    //
    //  Placée APRÈS les retours « rien à faire » : ces cas ne mutent rien et ne
    //  sont pas des échecs — les transformer en refus changerait une sémantique
    //  validée depuis B2-b.
    //
    //  ⚠️ TOUT REFUS ICI LAISSE `_ratings` INTACT : il est rendu AVANT le
    //     moindre calcul de delta, donc avant toute mutation.
    // ══════════════════════════════════════════════════════════════════════════

    // A.1 — Identité exploitable. Sans elle, aucune journalisation possible,
    // donc aucune application : une identité absente n'est JAMAIS « neutre ».
    if (identite == null) {
      return _refuserApplication(MotifRefusApplicationElo.identiteNonExploitable);
    }

    // A.2 — Chargement, diagnostic et amorçage éventuel (2 attentes internes).
    final ({RegistreEloV3? registre, MotifRefusApplicationElo? refus,
            bool amorcage}) chargement =
        await _chargerOuAmorcerRegistre(generation: generation, jeton: jeton);

    // A.3 — Contrôle G après les attentes de chargement/amorçage.
    if (_estPerimeeParReset(generation)) {
      return _abandonnerParGenerationFile('mettreAJourApresArrivee');
    }

    if (chargement.refus != null) return _refuserApplication(chargement.refus!);

    final RegistreEloV3 registre = chargement.registre!;

    // A.4 — Doublon. `entreePourCle` ne retient que `type == course`, et les
    // TROIS étapes bloquent (`bloqueNouvelleSoumission` rend toujours `true`) :
    // `appliquee` (déjà comptée), `intention` et `nonConfirmee` (preuve
    // manquante). Aucune dérogation, aucune tentative de réparation.
    if (registre.entreePourCle(identite.courseKey) != null) {
      return _refuserApplication(
        MotifRefusApplicationElo.courseDejaJournalisee,
        coherence: DiagnosticCoherenceElo.coherent,
        origine: registre.origine,
        amorcage: chargement.amorcage,
      );
    }

    // A.5 — Garde d'ANTÉRIORITÉ (jamais une preuve de non-réapplication).
    //  Une date de course POSTÉRIEURE au lendemain de « maintenant » ne peut pas
    //  être une arrivée officielle déjà disputée. La borne est le LENDEMAIN et
    //  non l'instant, pour tolérer un fuseau en avance d'un jour entier : on
    //  refuse le franchement impossible, on n'invente aucune preuve temporelle.
    //  Une date non parsable n'entraîne pas de refus ici : la validité
    //  calendaire a déjà été exigée par `IdentiteCourseElo.tenter`.
    final DateTime? dateCourse = DateTime.tryParse(identite.date);
    if (dateCourse != null) {
      final DateTime maintenant = DateTime.now();
      final DateTime borne =
          DateTime(maintenant.year, maintenant.month, maintenant.day + 1);
      if (dateCourse.isAfter(borne)) {
        return _refuserApplication(
          MotifRefusApplicationElo.datePosterieure,
          coherence: DiagnosticCoherenceElo.coherent,
          origine: registre.origine,
          amorcage: chargement.amorcage,
        );
      }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  CALCUL DES DELTAS — FORMULES STRICTEMENT INCHANGÉES DEPUIS B2-b.
    //  Aucune ligne de cette boucle n'est modifiée par B2-e.
    // ══════════════════════════════════════════════════════════════════════════
    final Map<String, double> deltas = {};

    for (int i = 0; i < n; i++) {
      for (int j = i + 1; j < math.min(i + 4, n); j++) {
        final partantA = mapPartants[arrivee[i]];
        final partantB = mapPartants[arrivee[j]];
        if (partantA == null || partantB == null) continue;

        final cleA = _cle(partantA.nom, discipline);
        final cleB = _cle(partantB.nom, discipline);
        final rA   = getRating(partantA.nom, discipline: discipline);
        final rB   = getRating(partantB.nom, discipline: discipline);

        final probA = 1.0 / (1.0 + math.pow(10, (rB - rA) / 400));
        final probB = 1.0 - probA;

        final nbA = getScore(partantA.nom, discipline: discipline).nbCourses;
        final nbB = getScore(partantB.nom, discipline: discipline).nbCourses;
        final kA  = _kFacteurPourDiscipline(
            EloService.normaliserDiscipline(discipline), nbA < _seuilDebutant);
        final kB  = _kFacteurPourDiscipline(
            EloService.normaliserDiscipline(discipline), nbB < _seuilDebutant);

        final facteurDistance = math.pow(0.7, j - i - 1).toDouble();
        deltas[cleA] = (deltas[cleA] ?? 0.0) + kA * (1.0 - probA) * facteurDistance;
        deltas[cleB] = (deltas[cleB] ?? 0.0) + kB * (0.0 - probB) * facteurDistance;
      }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  ÉTAPE B — INTENTION PERSISTÉE AVANT TOUTE MUTATION
    //
    //  Le calcul ci-dessus est SYNCHRONE et n'a touché AUCUN rating : `_ratings`
    //  est encore exactement l'état qui vient d'être fingerprinté. C'est
    //  indispensable — l'empreinte « avant » doit coïncider avec celle du
    //  disque, sinon le registre naîtrait incohérent et se refuserait lui-même.
    //
    //  L'image « après » ne peut pas être LUE : elle n'existe pas encore. Elle
    //  est CALCULÉE sans toucher `_ratings`, et cette promesse est exacte :
    //    • `nbCourses` ne dépend que de l'ancienne image ;
    //    • `rating` et `variationMois` n'influencent que leur propre champ, donc
    //      les deux deltas se calculent indépendamment ;
    //    • l'empreinte ne dépend ni du nom du cheval, ni de l'ordre des clés
    //      (`canoniqueRatings` trie les clés — `elo_empreinte.dart` l.119).
    //
    //  ⚠️ SI L'INTENTION N'EST PAS CONFIRMÉE : aucune mutation, aucun appel à
    //     `_sauvegarder()`, aucune entrée `appliquee`.
    // ══════════════════════════════════════════════════════════════════════════
    final String empreinteAvant = empreinte64Ratings(_ratings);

    final IntentionEntreeElo? prep = _construireIntentionCourse(
      identite: identite,
      registre: registre,
      deltas: deltas,
      partants: partants,
      discipline: discipline,
      empreinteAvant: empreinteAvant,
    );
    if (prep == null) {
      return _refuserApplication(
        MotifRefusApplicationElo.allocationImpossible,
        coherence: DiagnosticCoherenceElo.coherent,
        origine: registre.origine,
        amorcage: chargement.amorcage,
      );
    }

    final ({bool confirmee, MotifRefusApplicationElo? refus}) ecritureIntention =
        await _persisterRegistre(
      registre: prep.registreAvecIntention,
      generation: generation,
      jetonNaissance: jeton,
    );

    // Contrôle G après l'attente de persistance de l'intention.
    if (_estPerimeeParReset(generation)) {
      return _abandonnerParGenerationFile('mettreAJourApresArrivee');
    }

    if (ecritureIntention.refus != null) {
      return _refuserApplication(
        MotifRefusApplicationElo.intentionNonPersistee,
        coherence: DiagnosticCoherenceElo.coherent,
        origine: registre.origine,
        amorcage: chargement.amorcage,
      );
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  ÉTAPE C — MUTATION RAM PUIS SAUVEGARDE DES RATINGS (mécanisme INCHANGÉ)
    //
    //  ↓↓↓ AUCUNE attente entre le contrôle G ci-dessus et la mutation RAM ↓↓↓
    // ══════════════════════════════════════════════════════════════════════════
    //
    // ★ B2-b : c'est ICI, au point de non-retour — après tous les contrôles et
    //   tous les retours anticipés, juste avant la mutation — que l'identité
    //   devient observable.
    _derniereIdentiteCourse = identite;
    deltas.forEach((cle, delta) {
      // Extraire le nom depuis la clé "NOM|DISC"
      final nomDisc  = cle.split('|');
      final nomNorm  = nomDisc[0];
      final partant  = partants.firstWhere(
        (p) => _cleNom(p.nom) == nomNorm,
        orElse: () => partants.first,
      );
      final ancien   = _ratings[cle];
      final ancienR  = ancien?.rating ?? _eloDefaut;
      final nouveau  = (ancienR + delta).clamp(_eloMin, _eloMax);
      final varMois  = ((ancien?.variationMois ?? 0.0) + delta).clamp(-300.0, 300.0);

      _ratings[cle] = EloScore(
        nomCheval:     partant.nom,
        rating:        nouveau,
        nbCourses:     (ancien?.nbCourses ?? 0) + 1,
        variationMois: varMois,
      );
    });

    // ── Contrôle G n°3 : après la mutation, avant la persistance. ───────────
    if (_estPerimeeParReset(generation)) {
      return _abandonnerParGenerationFile('mettreAJourApresArrivee');
    }

    final EtatPersistanceElo etat = await _sauvegarder(jeton);
    debugPrint('[EloService] ${etat == EtatPersistanceElo.persistee ? "✅" : "⚠️"} '
        '${deltas.length} ELO mis à jour (discipline: $discipline) — '
        'persistance: ${etat.name}');

    // ══════════════════════════════════════════════════════════════════════════
    //  ÉTAPE D — FINALISATION DE LA MÊME ENTRÉE
    //
    //  Sauvegarde confirmée ⇒ `appliquee` (seul état terminal nominal).
    //  Toute autre issue ⇒ `nonConfirmee` : ni preuve d'écriture, ni preuve
    //  d'absence. L'entrée reste INCERTAINE, donc BLOQUANTE — c'est ce qui
    //  interdit une seconde application automatique après une interruption
    //  entre mutation et finalisation.
    //
    //  ⚠️ AUCUNE SECONDE OPÉRATION : c'est la MÊME entrée (`id`) qui est
    //     complétée. `id` et `horloge` ne sont PAS réalloués.
    // ══════════════════════════════════════════════════════════════════════════
    final bool journalisationConfirmee = await _finaliserEntreeCourse(
      prep: prep,
      etatRatings: etat,
      generation: generation,
      jetonNaissance: jeton,
    );

    _dernierResultatMiseAJour = ResultatApplicationElo(
      etatRatings: etat,
      motifRefus: null,
      coherenceAvant: DiagnosticCoherenceElo.coherent,
      origineAvant: registre.origine,
      amorcageEffectue: chargement.amorcage,
      etapeEntree: journalisationConfirmee
          ? EtapeEntreeRegistre.appliquee
          : EtapeEntreeRegistre.nonConfirmee,
      idEntree: prep.id,
      journalisationConfirmee: journalisationConfirmee,
    );

    return etat;
  }

  // ── Enrichir les partants avec leur ELO ── ★ v9.92 : + discipline
  List<ZtPartant> enrichirAvecElo(List<ZtPartant> partants,
      {String discipline = ''}) {
    return partants.map((p) {
      final score = getScore(p.nom, discipline: discipline);
      return p.copyWith(
        eloRating:        score.rating,
        eloNbCourses:     score.nbCourses,
        eloVariationMois: score.variationMois,
      );
    }).toList();
  }

  int    get nbChevauxSuivis => _ratings.length;
  double get ratingMoyen {
    if (_ratings.isEmpty) return _eloDefaut;
    return _ratings.values.map((e) => e.rating).reduce((a, b) => a + b) / _ratings.length;
  }

  Map<String, dynamic> exporterPourBackup() {
    final data = <String, dynamic>{};
    _ratings.forEach((k, v) => data[k] = v.toJson());
    return data;
  }

  /// ★ A7 (3.3-C9) — EXPORT ENRICHI, ADDITIF.
  ///
  /// [exporterPourBackup] reste **strictement inchangée**. Raison mesurée :
  /// 12 assertions de test lisent `exporterPourBackup().length` comme un
  /// NOMBRE DE CHEVAUX et deux mesurent `isEmpty` (v18_b5 l.160/188/216/263/272,
  /// v5 l.441/465/1036/1578, a7_ambiguite l.245/311/602). Toute métadonnée
  /// ajoutée dans sa map les casserait.
  ///
  /// ── LE PROBLÈME DES DEUX SOURCES ─────────────────────────────────────────
  /// `_etablirDiagnosticPreImport` décrit les ratings **DU DISQUE**
  /// ([DiagnosticPreImportElo.empreintePersistee]), tandis que
  /// `exporterPourBackup()` sérialise `_ratings` **EN RAM**. Assembler les deux
  /// produirait un groupe dont l'empreinte déclarée ne décrit pas les ratings
  /// exportés — exactement le défaut `divergent` que ce lot doit rendre visible.
  ///
  /// **Décision : la source du groupe est le DISQUE**, relu une seule fois.
  ///   • Aucune fonction du modèle de registre ne rend des ratings (verrou
  ///     T-S6) : on ne peut pas reconstruire les ratings depuis le registre.
  ///   • La RAM ne sert donc qu'à MESURER un écart, jamais à exporter.
  ///   • L'instantané disque est ensuite CONFRONTÉ au diagnostic : nombre ET
  ///     empreinte doivent coïncider, sinon le disque a bougé entre les deux
  ///     lectures et l'export est refusé.
  ///
  /// ⚠️ SI LA RAM DIVERGE DU DISQUE, L'EXPORT EST REFUSÉ. Une RAM en retard
  ///    signifie une écriture en vol ou un `_charger()` non exécuté : aucune
  ///    des deux sources ne peut alors prétendre décrire l'état réel.
  ///
  /// ── CE QUI N'EST JAMAIS FAIT ─────────────────────────────────────────────
  ///   • aucun registre inventé, réparé, réinterprété ni réencodé : la chaîne
  ///     exportée est la chaîne **PERSISTÉE, verbatim** ;
  ///   • aucune empreinte recalculée : celle du registre est un champ ;
  ///   • aucun horodatage isolé quand le diagnostic a échoué ;
  ///   • aucune conversion d'un refus en sauvegarde d'apparence complète.
  ///
  /// Aucune formule ELO, aucun rating, aucun critère n'est touché : cette
  /// méthode LIT et SÉRIALISE.
  Future<ResultatExportElo> exporterPourBackupEnrichi() async {
    // ── 1. Autorité : le diagnostic existant, LECTURE SEULE. ──────────────
    final DiagnosticPreImportElo diagnostic =
        await _etablirDiagnosticPreImport();

    if (!diagnostic.etabli) {
      // Aucun groupe ET aucun horodatage : on ne sait rien, on n'exporte rien.
      return ResultatExportElo(
        statut: StatutExportElo.diagnosticImpossible,
        motif: diagnostic.etablissementImpossible ??
            'diagnostic non établi, motif non renseigné',
        groupe: const <String, dynamic>{},
      );
    }

    // ── 2. Le REFUS, avant toute sérialisation. ───────────────────────────
    //  Registre corrompu, incompatible ou divergent → on ne peut pas affirmer
    //  que l'empreinte déclarée décrit les ratings exportés. Aucun groupe.
    final DiagnosticCoherenceElo coherence = diagnostic.coherence!;
    switch (coherence) {
      case DiagnosticCoherenceElo.corrompu:
      case DiagnosticCoherenceElo.schemaIncompatible:
      case DiagnosticCoherenceElo.divergent:
        return ResultatExportElo(
          statut: StatutExportElo.refuse,
          motif: 'registre ${coherence.name} — empreinte déclarée par le '
              'registre : ${diagnostic.empreinteRegistre ?? "illisible"}, '
              'empreinte des ratings persistés : ${diagnostic.empreintePersistee}. '
              'Aucune réparation automatique, export refusé',
          groupe: const <String, dynamic>{},
        );
      case DiagnosticCoherenceElo.registreAbsent:
      case DiagnosticCoherenceElo.coherent:
        break; // seuls états autorisant un export
    }

    // ── 3. Parité RAM / disque, AVANT toute lecture supplémentaire. ───────
    if (!diagnostic.ramIdentiqueAuDisque) {
      final String nature = diagnostic.nombreRam == 0 &&
              diagnostic.nombrePersistee > 0
          ? 'mémoire non chargée (RAM vide, disque non vide)'
          : 'RAM et disque différents';
      return ResultatExportElo(
        statut: StatutExportElo.refuse,
        motif: '$nature — RAM ${diagnostic.nombreRam} ratings '
            '(${diagnostic.empreinteRam}), disque '
            '${diagnostic.nombrePersistee} ratings '
            '(${diagnostic.empreintePersistee}). Aucune source unique '
            'décrivable : export refusé',
        groupe: const <String, dynamic>{},
      );
    }

    // ── 4. Instantané du disque : SEULE source des ratings exportés. ──────
    final ({
      Map<String, EloScore>? ratings,
      String? registreBrut,
      int? ts,
      String? motif
    }) instantane = await _lireInstantaneDisque();

    if (instantane.motif != null || instantane.ratings == null) {
      return ResultatExportElo(
        statut: StatutExportElo.diagnosticImpossible,
        motif: instantane.motif ?? 'instantané disque indisponible',
        groupe: const <String, dynamic>{},
      );
    }
    final Map<String, EloScore> persistes = instantane.ratings!;

    // ── 5. Contiguïté diagnostic ↔ instantané. ────────────────────────────
    //  Le disque peut avoir changé entre les deux lectures. On le DÉTECTE au
    //  lieu de l'ignorer : sans cette comparaison, le groupe exporté pourrait
    //  ne plus être celui dont l'empreinte a servi au diagnostic.
    final String empreinteInstantane = empreinte64Ratings(persistes);
    if (persistes.length != diagnostic.nombrePersistee ||
        empreinteInstantane != diagnostic.empreintePersistee) {
      return ResultatExportElo(
        statut: StatutExportElo.refuse,
        motif: 'le disque a changé entre le diagnostic et la lecture — '
            'diagnostic ${diagnostic.nombrePersistee} ratings '
            '(${diagnostic.empreintePersistee}), instantané '
            '${persistes.length} ratings ($empreinteInstantane). '
            'Source non cohérente, export refusé',
        groupe: const <String, dynamic>{},
      );
    }

    // ── 6. Groupe À PLAT, sans sous-objet `ratings`. ──────────────────────
    //  Les ratings exportés sont EXACTEMENT ceux dont l'empreinte vient d'être
    //  confrontée au diagnostic : la correspondance est structurelle, pas
    //  déclarative.
    final Map<String, dynamic> groupe = <String, dynamic>{};
    persistes.forEach((k, v) => groupe[k] = v.toJson());
    groupe[_kCleMarqueurFormat] = _kFormatEloV2;

    // ── 7. Registre : VERBATIM, et seulement si cohérent. ─────────────────
    if (coherence == DiagnosticCoherenceElo.coherent) {
      final String? brut = instantane.registreBrut;

      if (brut == null) {
        // Cohérent sans registre est contradictoire : on refuse plutôt que de
        // produire un `complet` sans registre, ou un `sansRegistre` mensonger.
        return ResultatExportElo(
          statut: StatutExportElo.refuse,
          motif: 'registre déclaré cohérent mais absent de la lecture '
              'verbatim — contradiction, export refusé',
          groupe: const <String, dynamic>{},
        );
      }

      //  Le registre relu doit être CELUI que le diagnostic a jugé. Sans cette
      //  vérification, une écriture intercalée pourrait faire exporter un
      //  registre que le diagnostic n'a jamais vu.
      final RegistreEloV3 relu;
      try {
        relu = RegistreEloV3.decoder(brut);
      } catch (e) {
        return ResultatExportElo(
          statut: StatutExportElo.refuse,
          motif: 'registre devenu illisible entre le diagnostic et la '
              'lecture verbatim ($e) — export refusé',
          groupe: const <String, dynamic>{},
        );
      }
      if (relu.empreinteRatings != diagnostic.empreinteRegistre) {
        return ResultatExportElo(
          statut: StatutExportElo.refuse,
          motif: 'registre différent de celui diagnostiqué — déclaré '
              '${diagnostic.empreinteRegistre}, relu '
              '${relu.empreinteRatings}. Export refusé',
          groupe: const <String, dynamic>{},
        );
      }

      // ⚠️ CHAÎNE PERSISTÉE, COPIÉE TELLE QUELLE. Pas de `registre.encoder()` :
      //    réencoder un objet décodé n'est pas garanti identique à l'octet
      //    près à la chaîne d'origine.
      groupe[_kCleMarqueurRegistre] = brut;
    }
    //  `registreAbsent` : `_elo_registre` n'est PAS écrit. On n'invente aucun
    //  registre, on n'en fabrique pas un vierge — ce serait une preuve
    //  historique rétroactive. Même décision que
    //  `MotifNonEcritureTemoin.registreAbsent` (l.339-343).

    // ── 8. Horodatage : optionnel, jamais bloquant, jamais isolé. ─────────
    final int? ts = instantane.ts;
    if (ts != null) groupe[_kCleMarqueurTs] = ts;

    return ResultatExportElo(
      statut: coherence == DiagnosticCoherenceElo.coherent
          ? StatutExportElo.complet
          : StatutExportElo.sansRegistre,
      motif: null,
      groupe: groupe,
    );
  }

  /// Lit en UNE passe l'instantané du disque utile à l'export enrichi :
  /// ratings persistés, registre **brut** (jamais réencodé), horodatage.
  ///
  /// Le décodage des ratings reproduit VOLONTAIREMENT celui de
  /// [_etablirDiagnosticPreImport] (même tolérance, même convention) : c'est ce
  /// qui permet à l'appelant de comparer l'empreinte obtenue ici à celle du
  /// diagnostic. Toute divergence de ce décodage deviendrait donc DÉTECTABLE
  /// par la comparaison de l'étape 5, au lieu d'être silencieuse.
  ///
  /// Rend `motif` non nul si l'instantané n'a pas pu être établi — jamais une
  /// lecture partielle présentée comme complète.
  Future<({
    Map<String, EloScore>? ratings,
    String? registreBrut,
    int? ts,
    String? motif
  })> _lireInstantaneDisque() async {
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      return (
        ratings: null,
        registreBrut: null,
        ts: null,
        motif: 'SharedPreferences indisponible : $e',
      );
    }

    try {
      await prefs.reload();
    } catch (e) {
      return (
        ratings: null,
        registreBrut: null,
        ts: null,
        motif: 'reload() impossible — cache non actualisé : $e',
      );
    }

    // ── Ratings persistés ─────────────────────────────────────────────────
    final Map<String, EloScore> persistes = <String, EloScore>{};
    final Object? brut = prefs.get(_prefsKey);
    if (brut != null) {
      if (brut is! String) {
        return (
          ratings: null,
          registreBrut: null,
          ts: null,
          motif: '`$_prefsKey` n\'est pas une chaîne '
              '(reçu ${brut.runtimeType})',
        );
      }
      if (brut.isNotEmpty) {
        try {
          final Object? decode = jsonDecode(brut);
          if (decode is! Map<String, dynamic>) {
            return (
              ratings: null,
              registreBrut: null,
              ts: null,
              motif: '`$_prefsKey` : objet JSON attendu '
                  '(reçu ${decode.runtimeType})',
            );
          }
          decode.forEach((key, val) {
            try {
              persistes[key] = EloScore.fromJson(val as Map<String, dynamic>);
            } catch (_) {}
          });
        } on FormatException catch (e) {
          return (
            ratings: null,
            registreBrut: null,
            ts: null,
            motif: '`$_prefsKey` : JSON illisible ($e)',
          );
        }
      }
    }

    // ── Registre BRUT — `get` et non `getString` : un type inattendu doit
    //    produire un motif explicite plutôt qu'une `TypeError` en profondeur.
    final Object? registreBrut = prefs.get(kCleRegistreElo);
    if (registreBrut != null && registreBrut is! String) {
      return (
        ratings: null,
        registreBrut: null,
        ts: null,
        motif: '`$kCleRegistreElo` n\'est pas une chaîne '
            '(reçu ${registreBrut.runtimeType})',
      );
    }

    // ── Horodatage : secondaire. Un type inattendu vaut ABSENCE, jamais 0.
    final Object? tsBrut = prefs.get(_prefsKeyTs);
    final int? ts = tsBrut is int ? tsBrut : null;

    return (
      ratings: persistes,
      registreBrut: registreBrut as String?,
      ts: ts,
      motif: null,
    );
  }

  /// ★ A7 (3.3-B2-d1) — ÉTABLIT L'ÉTAT ELO **AVANT** TOUTE MUTATION D'IMPORT.
  ///
  /// Rend le diagnostic, ou un diagnostic NON ÉTABLI dont
  /// [DiagnosticPreImportElo.etablissementImpossible] porte la raison exacte.
  /// **N'ÉCRIT RIEN**, ne supprime rien, ne migre rien, n'invalide rien.
  ///
  /// ── POURQUOI LE DISQUE FAIT FOI, ET NON `_ratings` ───────────────────────
  ///   `_importerDepuisBackup` n'a pas de garde `_charge` (limite conservée de
  ///   B1) : la RAM peut être VIDE ou dater d'un autre état. Diagnostiquer
  ///   contre `_ratings` reviendrait donc à comparer le registre à une mémoire
  ///   qui n'a jamais prétendu décrire le disque. On relit donc la clé
  ///   `elo_ratings_v2` et on la décode pour calculer l'empreinte RÉELLEMENT
  ///   PERSISTÉE.
  ///
  /// ── POURQUOI UNE RElecture EST NÉCESSAIRE ────────────────────────────────
  ///   `SharedPreferences.getString` lit le **cache** `_preferenceCache`
  ///   (mesuré : `shared_preferences_legacy.dart` l.130), pas le store. Une
  ///   instance déjà obtenue peut donc porter un cache antérieur. Pour une
  ///   observation stricte, `reload()` vide et recharge ce cache depuis le
  ///   store (l.227-231) : c'est une LECTURE, elle n'écrit rien.
  ///
  /// ── ORDRE DES ATTENTES ET CONTRÔLES DE GÉNÉRATION ────────────────────────
  ///   Deux attentes sont introduites : `getInstance()` puis `reload()`. Le
  ///   contrôle de génération est refait APRÈS CHACUNE. `reload()` est refait
  ///   sans condition, y compris quand l'appelant vient d'obtenir `prefs` : un
  ///   cache non actualisé produirait un diagnostic faux, et un diagnostic faux
  ///   vaut moins qu'aucun diagnostic.
  ///
  /// ⚠️ LIMITE MESURÉE, À NE PAS MASQUER : `reload()` peut lever. L'exception
  ///    est alors CONSERVÉE dans [DiagnosticPreImportElo.etablissementImpossible]
  ///    et le diagnostic est rendu NON ÉTABLI. Elle n'est ni avalée
  ///    silencieusement, ni convertie en « cohérent ».
  Future<DiagnosticPreImportElo> _etablirDiagnosticPreImport() async {
    // Empreinte de la RAM, calculée AVANT toute attente : elle décrit l'état
    // au moment de l'appel, pas un état obtenu après un `await`.
    final String empreinteRam = empreinte64Ratings(_ratings);
    final int nombreRam = _ratings.length;

    DiagnosticPreImportElo nonEtabli(String motif) => DiagnosticPreImportElo(
          empreintePersistee: null,
          nombrePersistee: 0,
          empreinteRam: empreinteRam,
          nombreRam: nombreRam,
          resultat: null,
          etablissementImpossible: motif,
        );

    // ── Attente 1 : obtention des préférences ──────────────────────────────
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      return nonEtabli('SharedPreferences indisponible : $e');
    }

    // ── Attente 2 : rechargement du cache depuis le store (LECTURE seule) ──
    try {
      await prefs.reload();
    } catch (e) {
      return nonEtabli('reload() impossible — cache non actualisé : $e');
    }

    // ── Lecture des ratings RÉELLEMENT PERSISTÉS ───────────────────────────
    // Même décodage tolérant que celui déjà employé par `_charger` et
    // `_importerDepuisBackup` : une entrée illisible est ignorée, comme
    // partout ailleurs dans ce service. Le but est de reproduire l'empreinte
    // que produirait le chargement réel, pas d'auditer le JSON.
    final Map<String, EloScore> persistes = <String, EloScore>{};
    final Object? brut = prefs.get(_prefsKey);
    if (brut != null) {
      if (brut is! String) {
        return nonEtabli('`$_prefsKey` n\'est pas une chaîne '
            '(reçu ${brut.runtimeType})');
      }
      if (brut.isNotEmpty) {
        try {
          final Object? decode = jsonDecode(brut);
          if (decode is! Map<String, dynamic>) {
            return nonEtabli('`$_prefsKey` : objet JSON attendu '
                '(reçu ${decode.runtimeType})');
          }
          decode.forEach((key, val) {
            try {
              persistes[key] = EloScore.fromJson(val as Map<String, dynamic>);
            } catch (_) {}
          });
        } on FormatException catch (e) {
          return nonEtabli('`$_prefsKey` : JSON illisible ($e)');
        }
      }
    }

    final String empreintePersistee = empreinte64Ratings(persistes);
    final int nombrePersistee = persistes.length;

    // ── Lecture du registre — LECTURE SEULE ────────────────────────────────
    // `get` et non `getString` : un type inattendu doit produire un diagnostic
    // NON ÉTABLI explicite plutôt qu'une `TypeError` au fond du service.
    final Object? registreBrut = prefs.get(kCleRegistreElo);
    if (registreBrut != null && registreBrut is! String) {
      return nonEtabli('`$kCleRegistreElo` n\'est pas une chaîne '
          '(reçu ${registreBrut.runtimeType})');
    }

    // `diagnostiquerRegistre` est PURE : aucun accès disque, aucune mutation.
    final ResultatDiagnosticElo resultat = diagnostiquerRegistre(
      jsonRegistre: registreBrut as String?,
      empreinteDisque: empreintePersistee,
      nombreRatings: nombrePersistee,
    );

    return DiagnosticPreImportElo(
      empreintePersistee: empreintePersistee,
      nombrePersistee: nombrePersistee,
      empreinteRam: empreinteRam,
      nombreRam: nombreRam,
      resultat: resultat,
      etablissementImpossible: null,
    );
  }

  /// ★ A7 (3.3-B2-d2) — ÉCRITURE DU TÉMOIN, APPEND-ONLY, SOUS CONTRÔLE.
  ///
  /// N'est appelée QUE si [_doitEcrireTemoin] a rendu `null`.
  ///
  /// ── CE QUI EST ÉCRIT ─────────────────────────────────────────────────────
  ///   • une entrée `horsCourse` de motif `importBackup`, `etape: appliquee`,
  ///     `issue: persistee` (l'écriture des ratings a réellement été confirmée
  ///     avant d'arriver ici) ;
  ///   • `chevaux` VIDE — invariant du modèle pour `horsCourse` (l.443-448) :
  ///     un import peut porter des centaines de chevaux, l'image par cheval est
  ///     réservée à la porte d'application.
  ///   • `entrees: [...anciennes, neuve]` — APPEND-ONLY. Aucun filtre, aucune
  ///     compaction : les entrées incertaines survivent intactes.
  ///   • `origine: historiqueInconnu` — JAMAIS `courante`. L'import ne permet
  ///     pas de prétendre que l'historique complet est mémorisé.
  ///
  /// ── SUIVI DE L'ÉCRITURE ──────────────────────────────────────────────────
  ///   La future est inscrite dans [_ecrituresPersistantesEnCours] UNIQUEMENT.
  ///   [_ecrituresEnCours] garde sa signification historique B2-a : elle ne
  ///   compte que les écritures de `_sauvegarder()`, donc `nbEcrituresEnCours`
  ///   ne bouge pas. Le drain du reset attend les DEUX ensembles, il attendra
  ///   donc aussi le témoin — ce qui interdit de recréer `elo_registre_v3`
  ///   après son effacement (transposition de V29-A).
  ///
  ///   ⚠️ AUCUN `await` ENTRE LE CONTRÔLE DE GÉNÉRATION ET L'INSCRIPTION.
  ///   Sans cette contiguïté, un reset pourrait s'intercaler dans la fenêtre et
  ///   la future ne serait pas drainée.
  ///
  /// Rend l'issue de l'écriture, ou le motif du refus.
  Future<({IssueEcritureElo? issue, MotifNonEcritureTemoin? motif})>
      _ecrireTemoinImport({
    required RegistreEloV3 registreAvant,
    required String empreinteAvant,
    required String empreinteApres,
    required int nombreAvant,
    required int nombreApres,
    required int generation,
  }) async {
    // ── Allocation : refus plutôt que devinette. ──────────────────────────
    final AllocationEntreeElo? allocation =
        AllocationEntreeElo.pour(registreAvant);
    if (allocation == null) {
      return (
        issue: null,
        motif: MotifNonEcritureTemoin.allocationImpossible,
      );
    }

    final EntreeRegistreElo neuve = EntreeRegistreElo(
      id: allocation.id,
      type: TypeEntreeRegistre.horsCourse,
      motif: MotifHorsCourse.importBackup,
      nbChevauxAvant: nombreAvant,
      nbChevauxApres: nombreApres,
      etape: EtapeEntreeRegistre.appliquee,
      issue: IssueEcritureElo.persistee,
      tsIntention: DateTime.now().millisecondsSinceEpoch,
      tsFinal: DateTime.now().millisecondsSinceEpoch,
      empreinteAvant: empreinteAvant,
      empreinteApres: empreinteApres,
      chevaux: const <ChevalJournalise>[],
    );

    final RegistreEloV3 neuf = registreAvant.copyWith(
      horloge: allocation.horloge,
      empreinteRatings: empreinteApres,
      origine: OrigineRegistreElo.historiqueInconnu,
      entrees: <EntreeRegistreElo>[...registreAvant.entrees, neuve],
    );

    // ── Sérialisation : peut lever (`jsonEncode` sur NaN/Infinity). ───────
    final String brut;
    try {
      brut = neuf.encoder();
    } catch (e) {
      _derniereErreurEcriture = e;
      debugPrint('[EloService] ⚠️ Témoin ELO : sérialisation impossible '
          '(registre NON écrit) : $e');
      return (
        issue: null,
        motif: MotifNonEcritureTemoin.serialisationImpossible,
      );
    }

    // ── Contrôle de génération IMMÉDIATEMENT avant l'écriture. ────────────
    if (_estPerimeeParReset(generation)) {
      return (
        issue: null,
        motif: MotifNonEcritureTemoin.abandonneParReset,
      );
    }

    // ── Obtention des préférences — ATTENTE, donc contrôle de génération
    //    APRÈS elle (voir juste plus bas). ────────────────────────────────
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      _derniereErreurEcriture = e;
      return (issue: null, motif: MotifNonEcritureTemoin.echoueeParException);
    }

    // Second contrôle : `getInstance()` est une attente.
    if (_estPerimeeParReset(generation)) {
      return (issue: null, motif: MotifNonEcritureTemoin.abandonneParReset);
    }

    // ── Écriture, avec inscription IMMÉDIATE (aucun `await` intermédiaire). ─
    //  ★ Correction B2-d2 (mesurée) : le booléen rendu par `setString` n'est
    //    plus converti en exception. Avant cette correction, un REFUS EXPLICITE
    //    du stockage (`false`) était transformé en `StateError`, donc en
    //    `IssueEcritureElo.echouee`, et `MotifNonEcritureTemoin.refuseeParStockage`
    //    n'était JAMAIS produit — un cas de documentation fausse, détecté en
    //    confrontant l'enum aux branches réelles. Le refus et l'exception sont
    //    désormais DISTINGUÉS, comme le fait déjà `_executerSauvegarde`.
    IssueEcritureElo issue;
    final Future<bool> future = prefs.setString(kCleRegistreElo, brut);
    // ↓↓↓ Aucun `await` entre le contrôle ci-dessus et cette inscription. ↓↓↓
    _ecrituresPersistantesEnCours.add(future);
    future.whenComplete(() {
      _ecrituresPersistantesEnCours.remove(future);
    }).ignore();

    try {
      final bool ok = await future;
      if (ok) {
        issue = IssueEcritureElo.persistee;
        // ★ X1-b (P3) — TÉMOIN D'IMPORT ÉCRIT AVEC SUCCÈS.
        //   `brut` est exactement ce que le disque contient désormais.
        _observerNiveauRegistre(brut);
      } else {
        issue = IssueEcritureElo.refusee;
        debugPrint('[EloService] ⚠️ Témoin ELO REFUSÉ par le stockage sur '
            '`$kCleRegistreElo` — persistance NON CONFIRMÉE (le registre '
            'existant n\'est PAS prouvé inchangé), aucune réparation');
      }
    } catch (e) {
      _derniereErreurEcriture = e;
      issue = IssueEcritureElo.echouee;
      debugPrint('[EloService] ⚠️ Témoin ELO : écriture NON confirmée '
          '(registre existant PRÉSERVÉ, aucune réparation) : $e');
    }

    // Le motif accompagne TOUJOURS une issue non confirmée : un refus ou une
    // exception ne doit jamais être rendu comme un simple « pas de motif ».
    if (issue == IssueEcritureElo.refusee) {
      return (issue: issue, motif: MotifNonEcritureTemoin.refuseeParStockage);
    }
    if (issue == IssueEcritureElo.echouee) {
      return (issue: issue, motif: MotifNonEcritureTemoin.echoueeParException);
    }
    return (issue: issue, motif: null);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ A7 (3.3-C12 / A7-39) — RESTITUTION VERBATIM DU REGISTRE SAUVEGARDÉ.
  //
  //  OBJET : écrire dans `elo_registre_v3` la chaîne EXACTE reçue de la
  //  sauvegarde, après avoir prouvé que les ratings persistés sont bien ceux
  //  que cette chaîne décrit.
  //
  //  ── CE QUI EST ÉCRIT, ET RIEN DE PLUS ────────────────────────────────────
  //   • la chaîne du backup, TELLE QUELLE. Aucun `copyWith`, aucun
  //     `encoder()`, aucun recalcul d'horloge, aucune entrée ajoutée.
  //   • Conséquence assumée et vérifiable : `entrees`, `horloge`, `schema`,
  //     `version` et `origine` sont préservés À L'OCTET. Un import ne laisse
  //     AUCUNE trace dans le journal : il ne fabrique pas d'historique.
  //
  //  ── POURQUOI VERBATIM, ET PAS `copyWith(empreinteRatings: …)` ───────────
  //   `copyWith` reconstruirait un objet ; `encoder()` n'est pas garanti
  //   identique à l'octet près à la chaîne d'origine (le modèle le dit
  //   explicitement, l. « réencoder un objet décodé n'est pas garanti
  //   identique »). Or l'empreinte des ratings de la sauvegarde est DÉJÀ
  //   égale à celle de la RAM après mutation : le refus anticipé l'a prouvé
  //   hors ligne, et la barrière F3' le re-vérifie juste avant d'appeler ici.
  //   Il n'y a donc RIEN à recaler. Recoder serait au mieux inutile, au pire
  //   destructeur.
  //
  //  ── SUIVI DE L'ÉCRITURE ─────────────────────────────────────────────────
  //   La future est inscrite dans [_ecrituresPersistantesEnCours] UNIQUEMENT.
  //   [_ecrituresEnCours] garde sa signification historique : `nbEcrituresEnCours`
  //   ne bouge pas. Le drain du reset attend les DEUX ensembles, donc il
  //   attendra aussi cette écriture — ce qui interdit de recréer
  //   `elo_registre_v3` après son effacement.
  //
  //  ⚠️ AUCUN `await` ENTRE LE CONTRÔLE DE GÉNÉRATION ET L'INSCRIPTION
  //     (invariant P1). Sans cette contiguïté, un reset pourrait s'intercaler
  //     et l'écriture ne serait pas drainée.
  //
  //  Rend l'issue de l'écriture, ou le motif du refus. `issue == persistee` et
  //  `motif == null` SONT LE SEUL couple qui autorise à revendiquer une
  //  protection — et même alors, seul l'appelant sait si elle est démontrée.
  // ══════════════════════════════════════════════════════════════════════════
  Future<({IssueEcritureElo? issue, MotifNonEcritureTemoin? motif})>
      _ecrireRegistreVerbatim({
    required String registreBrut,
    required int generation,
  }) async {
    // ── Contrôle de génération IMMÉDIATEMENT avant toute attente. ──────────
    if (_estPerimeeParReset(generation)) {
      return (issue: null, motif: MotifNonEcritureTemoin.abandonneParReset);
    }

    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      _derniereErreurEcriture = e;
      return (issue: null, motif: MotifNonEcritureTemoin.echoueeParException);
    }

    // Second contrôle : `getInstance()` est une attente.
    if (_estPerimeeParReset(generation)) {
      return (issue: null, motif: MotifNonEcritureTemoin.abandonneParReset);
    }

    // ── Écriture, avec inscription IMMÉDIATE (aucun `await` intermédiaire). ─
    IssueEcritureElo issue;
    final Future<bool> future = prefs.setString(kCleRegistreElo, registreBrut);
    // ↓↓↓ Aucun `await` entre le contrôle ci-dessus et cette inscription. ↓↓↓
    _ecrituresPersistantesEnCours.add(future);
    future.whenComplete(() {
      _ecrituresPersistantesEnCours.remove(future);
    }).ignore();

    try {
      final bool ok = await future;
      if (ok) {
        issue = IssueEcritureElo.persistee;
        // ★ X1-b (P4) — RESTITUTION VERBATIM RÉUSSIE.
        //   C'est le chemin d'une restauration. ÉCRASEMENT, pas de `max` :
        //   si `registreBrut` est plus PETIT que l'état antérieur, le niveau
        //   REDESCEND — comportement exigé par l'audit.
        _observerNiveauRegistre(registreBrut);
      } else {
        issue = IssueEcritureElo.refusee;
        debugPrint('[EloService] ⚠️ Registre VERBATIM REFUSÉ par le stockage '
            'sur `$kCleRegistreElo` — persistance NON CONFIRMÉE (le registre '
            'existant n\'est PAS prouvé inchangé), aucune réparation');
      }
    } catch (e) {
      _derniereErreurEcriture = e;
      issue = IssueEcritureElo.echouee;
      debugPrint('[EloService] ⚠️ Registre VERBATIM : écriture NON confirmée '
          '(exception sur `$kCleRegistreElo`) : $e');
    }

    if (issue == IssueEcritureElo.refusee) {
      return (issue: issue, motif: MotifNonEcritureTemoin.refuseeParStockage);
    }
    if (issue == IssueEcritureElo.echouee) {
      return (issue: issue, motif: MotifNonEcritureTemoin.echoueeParException);
    }
    return (issue: issue, motif: null);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ A7 (3.3-C12 / A7-39) — RELECTURE PROUVANTE AVANT ÉCRITURE DU REGISTRE.
  //
  //  OBJET : établir que ce qui est SUR LE DISQUE est bien ce qui vient d'être
  //  importé, AVANT d'écrire un registre qui prétendra le décrire.
  //
  //  ⚠️ POURQUOI CE N'EST PAS REDONDANT AVEC `etat == persistee`.
  //  `persistee` signifie « `setString` a répondu `true` ». Ce n'est PAS une
  //  preuve de CONTENU : le contrat d'[EtatPersistanceElo] est explicite —
  //  `refusee` et `echouee` valent « persistance NON CONFIRMÉE », JAMAIS
  //  « disque inchangé ». Réciproquement, un `true` prouve que le store a
  //  accepté, pas que la valeur relue est celle qu'on croit. Écrire dans le
  //  registre une empreinte déduite d'un booléen serait revendiquer une
  //  protection non démontrée.
  //
  //  La relecture passe par `reload()` : `getString` seul lirait le CACHE de
  //  `SharedPreferences`, qui a été alimenté AVANT l'appel au store
  //  (`shared_preferences_legacy.dart` `_setValue`). Sans `reload()`, la
  //  vérification serait circulaire et ne prouverait rien.
  //
  //  ⚠️ MÊME DÉCODAGE TOLÉRANT QUE PARTOUT (`_charger`, diagnostic, mutation).
  //     Une entrée illisible est ignorée. Ce n'est pas une indulgence : c'est
  //     la condition pour que l'empreinte d'ici soit comparable à celle de la
  //     RAM. Un décodage plus strict rendrait la comparaison structurellement
  //     impossible.
  //
  //  Rend l'empreinte relue, ou `null` si la relecture n'a pas pu être menée
  //  à son terme — jamais une valeur de repli.
  // ══════════════════════════════════════════════════════════════════════════
  Future<String?> _empreinteRelueDepuisDisque() async {
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      _derniereErreurEcriture = e;
      debugPrint('[EloService] ⚠️ Relecture ELO impossible '
          '(SharedPreferences indisponible) : $e');
      return null;
    }

    try {
      await prefs.reload();
    } catch (e) {
      _derniereErreurEcriture = e;
      debugPrint('[EloService] ⚠️ Relecture ELO impossible '
          '(reload() en échec — cache non actualisé) : $e');
      return null;
    }

    final Object? brut = prefs.get(_prefsKey);
    if (brut == null) {
      // `null` = la clé a disparu. Ce n'est PAS « zéro rating » : c'est un
      // état non prouvé, et il ne doit jamais devenir une empreinte.
      debugPrint('[EloService] ⚠️ Relecture ELO : `$_prefsKey` ABSENTE après '
          'écriture — contenu non prouvé');
      return null;
    }
    if (brut is! String) {
      debugPrint('[EloService] ⚠️ Relecture ELO : `$_prefsKey` n\'est pas une '
          'chaîne (reçu ${brut.runtimeType}) — contenu non prouvé');
      return null;
    }

    final Map<String, EloScore> relus = <String, EloScore>{};
    if (brut.isNotEmpty) {
      try {
        final Object? decode = jsonDecode(brut);
        if (decode is! Map<String, dynamic>) {
          debugPrint('[EloService] ⚠️ Relecture ELO : objet JSON attendu '
              '(reçu ${decode.runtimeType}) — contenu non prouvé');
          return null;
        }
        decode.forEach((key, val) {
          try {
            relus[key] = EloScore.fromJson(val as Map<String, dynamic>);
          } catch (_) {}
        });
      } on FormatException catch (e) {
        debugPrint('[EloService] ⚠️ Relecture ELO : JSON illisible ($e) — '
            'contenu non prouvé');
        return null;
      }
    }

    return empreinte64Ratings(relus);
  }

  /// ★ A7 (3.3-B1) : opération ENFILÉE. Un import ne peut donc plus
  /// `_ratings.clear()` au milieu d'une application ELO en cours — c'est la
  /// décision D11 option A (« une application ELO en cours termine avant
  /// qu'un import puisse commencer »), rendue vraie par la file et non plus
  /// par le calendrier.
  ///
  /// ⚠️ LIMITE CONSERVÉE (hors périmètre B1, annoncée) : cette méthode n'a
  /// TOUJOURS PAS de garde `_charge` — elle n'appelle pas `_charger()` et ne
  /// dépend donc pas de l'état de chargement. La file ne change rien à ce
  /// point, qui n'a pas été demandé.
  Future<EtatPersistanceElo> importerDepuisBackup(
      Map<String, dynamic> data) {
    return _executerEnFile(
        (int generation) => _importerDepuisBackup(data, generation));
  }

  /// Corps de [importerDepuisBackup], exécuté DANS la file.
  ///
  /// La mutation RAM (l. `clear()` puis `forEach`) est SYNCHRONE et contiguë,
  /// séparée du contrôle G par aucune attente. Une opération restée en attente
  /// pendant un reset est donc abandonnée AVANT de vider la RAM : c'est ce qui
  /// interdit la résurrection des ratings (test B1-4 / B1-5).
  ///
  /// ★ A7 (3.3-B2-d1) : l'état ELO est désormais ÉTABLI avant la mutation, et
  ///   rendu observable par [dernierDiagnosticPreImport]. Le diagnostic
  ///   n'autorise et ne bloque RIEN : le comportement de l'import est
  ///   exactement celui de B1, aux deux contrôles de génération près.
  ///
  /// ⚠️ TROIS CONTRÔLES DE GÉNÉRATION, ET POURQUOI.
  ///   Le diagnostic introduit DEUX attentes (`getInstance`, `reload`) avant la
  ///   mutation. Un reset peut démarrer pendant l'une d'elles :
  ///     • Contrôle G #1 — à l'entrée, comme en B1 (aucune attente en amont) ;
  ///     • Contrôle G #2 — après les deux attentes du diagnostic, AVANT la
  ///       mutation. Il remplace et généralise la garantie de B1 : celle-ci ne
  ///       couvrait qu'une opération restée en attente DANS LA FILE, pas une
  ///       attente interne au corps ;
  ///     • Contrôles 1 & 2 de `_sauvegarder` — inchangés, ils couvrent
  ///       l'attente de la persistance elle-même.
  ///   Un contrôle négatif prouve qu'aucun reset n'a commencé, car
  ///   `_generationCache++` est incrémenté SYNCHRONEMENT au début du reset.
  ///
  /// ⚠️ AUCUN `await` N'EST INSÉRÉ ENTRE LE CONTRÔLE G #2 ET LE `clear()` :
  ///   l'invariant de contiguïté de B1 est préservé à l'identique.
  Future<EtatPersistanceElo> _importerDepuisBackup(
      Map<String, dynamic> data, int generation) async {
    // ── Remise à `null` des observables AVANT toute attente. ───────────────
    // Un abandon ne doit laisser ni un diagnostic ni un résultat périmés.
    _dernierDiagnosticPreImport = null;
    _dernierResultatImport = null;

    // ── Contrôle G #1 : opération périmée → aucune mutation RAM. ───────────
    // ★ A2 : pour un JETON (opération née pendant un reset), `_estPerimeeParReset`
    //   est volontairement inerte ; c'est [_neePendantResetAcheve] qui décide.
    if (_neePendantResetAcheve(generation)) {
      return _abandonnerParGenerationFile('importerDepuisBackup');
    }
    if (_estPerimeeParReset(generation)) {
      return _abandonnerParGenerationFile('importerDepuisBackup');
    }

    // ── Diagnostic PRÉ-IMPORT (lecture seule, deux attentes internes) ──────
    final DiagnosticPreImportElo diagnostic =
        await _etablirDiagnosticPreImport();

    // ── Contrôle G #2 : après les attentes du diagnostic, AVANT mutation. ──
    if (_estPerimeeParReset(generation)) {
      return _abandonnerParGenerationFile('importerDepuisBackup');
    }

    // Publication CONDITIONNELLE : un abandon par reset ne doit pas laisser
    // croire qu'un diagnostic exploitable a été produit pour cette opération.
    _dernierDiagnosticPreImport = diagnostic;

    // ══════════════════════════════════════════════════════════════════════
    //  ★ A7 (3.3-C12 / A7-39) — REFUS ANTICIPÉ D'UN REGISTRE ENRICHI.
    //
    //  DÉCISION PRISE ICI, AVANT TOUTE MUTATION, ET SANS AUCUN `await` :
    //  il n'y a, entre le contrôle G #2 ci-dessus et ce point, que des
    //  instructions synchrones. L'invariant de contiguïté de B1 est préservé.
    //
    //  ⚠️ POURQUOI AVANT, ET PAS APRÈS LA PERSISTANCE.
    //  Une sauvegarde MANIFESTEMENT invalide (registre illisible, incompatible,
    //  ou ne décrivant pas ses propres ratings) ne doit pas modifier les
    //  ratings puis laisser l'appareil `divergent` — état dont la seule sortie
    //  serait un reset complet explicite. Refuser AVANT rend l'opération
    //  entièrement inoffensive : la RAM n'est pas touchée, aucune écriture
    //  n'est tentée, ni sur `elo_ratings_v2` ni sur `elo_registre_v3`.
    //
    //  ⚠️ CE REFUS NE S'APPLIQUE QU'AUX SAUVEGARDES PORTANT `_elo_registre`.
    //  Le chemin HISTORIQUE (marqueur absent) est intégralement préservé : le
    //  prédicat rend `motif == null` et `registreBrut == null`, et la suite
    //  du corps est celle d'avant ce lot, instruction pour instruction.
    // ══════════════════════════════════════════════════════════════════════
    final bool porteeEnrichie = data.containsKey(_kCleMarqueurRegistre);
    final ({
      MotifNonEcritureTemoin? motif,
      Map<String, EloScore>? candidats,
      String? registreBrut,
      RegistreEloV3? registre,
    }) analyse = porteeEnrichie
        ? _analyserRegistreEnrichi(data)
        : (
            motif: null,
            candidats: null,
            registreBrut: null,
            registre: null,
          );

    if (analyse.motif != null) {
      // ── REFUS ANTICIPÉ : aucune mutation, aucune écriture, aucun compteur
      //    de persistance touché. Le résultat est PUBLIÉ pour que l'appelant
      //    puisse expliquer exactement ce qui s'est passé — sans jamais
      //    revendiquer une protection.
      _dernierResultatImport = ResultatImportElo(
        etatRatings: EtatPersistanceElo.nonTentee,
        issueTemoin: null,
        motifNonEcriture: analyse.motif,
        coherenceAvant: diagnostic.coherence,
        empreinteAvant: diagnostic.empreintePersistee,
        empreinteApres: null,
        origineAppliquee: null,
        protegeApres: false,
      );
      debugPrint('[EloService] ⛔ Registre enrichi REFUSÉ AVANT MUTATION '
          '(${analyse.motif!.name}) — ratings INTACTS, aucune écriture tentée, '
          'aucune réparation automatique');
      return EtatPersistanceElo.nonTentee;
    }

    // ── MUTATION RAM — contiguë au contrôle G #2, aucun `await` inséré. ────
    //  Les images « avant » proviennent du DIAGNOSTIC (donc du disque), plus
    //  bas ; elles ne sont donc PAS relevées ici. Relever l'empreinte de la
    //  RAM remplacée serait relever un état qui n'a jamais décrit le disque.
    _ratings.clear();
    data.forEach((key, val) {
      try { _ratings[key] = EloScore.fromJson(val as Map<String, dynamic>); } catch (_) {}
    });
    final etat = await _sauvegarder(_jetonNaissance(generation));

    debugPrint('[EloService] ${etat == EtatPersistanceElo.persistee ? "✅" : "⚠️"} '
        'Import backup : ${_ratings.length} ratings restaurés — '
        'persistance: ${etat.name}');

    // ══════════════════════════════════════════════════════════════════════
    //  ★ A7 (3.3-B2-d2) — TÉMOIN DU REGISTRE, APRÈS persistance des ratings.
    //
    //  L'ORDRE EST STRUCTURANT : ratings puis témoin, jamais l'inverse. Le
    //  registre CONSTATE ce qui a eu lieu ; il ne doit pas précéder le fait
    //  qu'il atteste. Un échec du témoin laisse alors le registre à l'ancienne
    //  empreinte, donc `divergent` au prochain diagnostic : fail-closed et
    //  honnête, jamais une fausse protection.
    // ══════════════════════════════════════════════════════════════════════
    final String empreinteApresMutation = empreinte64Ratings(_ratings);
    final int nombreApres = _ratings.length;

    // ⚠️ L'IMAGE « AVANT » DU TÉMOIN EST CELLE DU DISQUE, PAS CELLE DE LA RAM.
    //    Correction B2-d2 : la première version utilisait l'empreinte de la RAM
    //    remplacée. C'était FAUX dans deux cas mesurables :
    //      • une RAM vide (import demandé avant tout `_charger`) aurait inscrit
    //        l'empreinte de la map VIDE, alors que le disque portait des ratings
    //        réels que le témoin prétendait décrire ;
    //      • la chaîne vérifiable du registre exige que `empreinteAvant` de la
    //        nouvelle entrée soit EXACTEMENT l'empreinte que le registre
    //        déclarait déjà — c'est-à-dire `empreintePersistee`. Une valeur
    //        issue de la RAM romprait cette chaîne sans le dire.
    //    ⚠️ AUCUNE ASSERTION NON NULLE ICI : un diagnostic non établi laisse
    //       `empreintePersistee` à `null`, et `_doitEcrireTemoin` refuse alors
    //       AVANT toute utilisation. Placer un `!` créerait un plantage
    //       exactement sur le chemin qui doit rester sûr.
    final String? empreinteAvantDisque =
        diagnostic.etabli ? diagnostic.empreintePersistee : null;
    final int nombreAvantDisque =
        diagnostic.etabli ? diagnostic.nombrePersistee : 0;

    final MotifNonEcritureTemoin? refus = _doitEcrireTemoin(
      diagnostic: diagnostic,
      etatRatings: etat,
      empreinteAvant: empreinteAvantDisque,
      empreinteApres: empreinteApresMutation,
    );

    // ══════════════════════════════════════════════════════════════════════
    //  ★ A7-39 — DEUX CHEMINS DE RESTITUTION, SÉPARÉS ET EXCLUSIFS.
    //
    //  Le choix se fait sur `analyse.registreBrut`, c'est-à-dire sur la présence
    //  d'un registre VALIDE dans la sauvegarde — décidée AVANT la mutation par
    //  `_analyserRegistreEnrichi`. Aucun `try`/`catch`, aucun état par défaut :
    //  il est donc toujours possible de dire lequel des deux a été pris.
    //
    //  ⚠️ POURQUOI LE CHEMIN ENRICHI NE PASSE PAS PAR `_doitEcrireTemoin`.
    //    Ce dernier exige `coherence == coherent` côté APPAREIL (il refuse
    //    `registreAbsent`) : il régit l'APPEND d'un témoin sur un registre déjà
    //    présent. Restaurer une sauvegarde enrichie sur un appareil vierge est
    //    un autre problème — le registre à écrire vient de la SAUVEGARDE. Les
    //    contrôles du chemin enrichi sont donc ceux exigés par A7-39 :
    //    persistance confirmée, relecture effective, F3', concordance avec le
    //    registre transporté.
    // ══════════════════════════════════════════════════════════════════════
    IssueEcritureElo? issueTemoin;
    MotifNonEcritureTemoin? motif;
    OrigineRegistreElo? origineAppliquee;

    // Protection RÉELLEMENT constatée après écriture, `null` si non constatée.
    // Seul le chemin enrichi la renseigne : le chemin historique n'a rien à
    // relire (son témoin force `historiqueInconnu`, donc `false` par
    // construction) et conserve donc son calcul d'origine, à l'identique.
    bool? protectionConstatee;

    if (analyse.registreBrut != null) {
      final ({
        IssueEcritureElo? issue,
        OrigineRegistreElo? origine,
        MotifNonEcritureTemoin? motif,
        bool? protectionApres,
      }) restitution = await _restaurerRegistreSauvegarde(
        registreBrut: analyse.registreBrut!,
        registre: analyse.registre!,
        generation: generation,
        empreinteApresMutation: empreinteApresMutation,
        etatRatings: etat,
      );
      issueTemoin = restitution.issue;
      motif = restitution.motif;
      origineAppliquee = restitution.origine;
      protectionConstatee = restitution.protectionApres;
    } else {
      // ── CHEMIN HISTORIQUE — contrat A-2, inchangé depuis B2-d2. ─────────
      motif = refus;
      if (refus == null) {
        final ({
          IssueEcritureElo? issue,
          OrigineRegistreElo? origine,
          MotifNonEcritureTemoin? motif,
          bool? protectionApres,
        }) temoin = await _restaurerTemoinHistorique(
          diagnostic: diagnostic,
          etatRatings: etat,
          empreinteApresMutation: empreinteApresMutation,
          empreinteAvantDisque: empreinteAvantDisque,
          nombreAvantDisque: nombreAvantDisque,
          nombreApres: nombreApres,
          generation: generation,
        );
        issueTemoin = temoin.issue;
        motif = temoin.motif;
        origineAppliquee = temoin.origine;
      }
    }

    // Publication du résultat COMPLET, sans changer le retour de la méthode.
    //
    // ══════════════════════════════════════════════════════════════════════
    //  ⚠️ `protegeApres` — CORRIGÉ EN A7-39 (correction finale autorisée).
    //
    //  CE QUE MESURAIENT LES TESTS M1/M9/M10 AVANT CORRECTION :
    //    la valeur était calculée par la formule B2-d2, qui lit
    //    `diagnostic.protegeContreDoubleApplication`, c'est-à-dire le verdict
    //    portant sur le registre de l'APPAREIL AVANT import. Deux résultats
    //    faux en découlaient, tous deux mesurés :
    //      • appareil VIERGE + sauvegarde enrichie : `coherenceAvant ==
    //        registreAbsent` donc protection rendue `false`, ALORS QUE le
    //        registre restauré est cohérent, d'origine `courante`, et protège
    //        effectivement → `false` mensonger (M1, M10) ;
    //      • appareil déjà cohérent, mêmes ratings : aucun témoin tenté,
    //        `issueTemoin == null`, formule satisfaite → `true` alors
    //        qu'AUCUNE protection n'a été créée et que rien n'a été écrit (M9).
    //    La formule mesurait donc une INTENTION D'ÉCRIRE UN TÉMOIN, pas l'état
    //    de protection après l'opération.
    //
    //  CE QUI CHANGE, ET RIEN DE PLUS :
    //    • CHEMIN ENRICHI : `protectionConstatee` porte le verdict du MODÈLE,
    //      recalculé par `diagnostiquerRegistre` sur la chaîne de registre
    //      RÉELLEMENT RELUE après `_ecrireRegistreVerbatim`. C'est la réponse à
    //      la seule question qui compte : le registre EN PLACE protège-t-il ?
    //    • `null` (constatation impossible : relecture en échec, clé absente,
    //      type inattendu) ⇒ `false`. Une preuve manquante ne devient JAMAIS
    //      une protection annoncée.
    //    • CHEMIN HISTORIQUE : `protectionConstatee` reste `null`, et la
    //      formule B2-d2 d'origine s'applique SANS AUCUNE MODIFICATION —
    //      contrat préservé à l'identique (verrouillé par `a7_33b2d2`, l.716).
    //
    //  ⚠️ AUCUN `true` ARTIFICIEL : la valeur vient d'un diagnostic, jamais
    //     d'une constante. Aucun calcul ELO, coefficient, poids, seuil, TOP3 ni
    //     apprentissage n'est concerné : c'est un indicateur d'import.
    // ══════════════════════════════════════════════════════════════════════
    final bool empreintesIdentiques = empreinteAvantDisque != null &&
        empreinteAvantDisque == empreinteApresMutation;
    final bool protectionPreservee = etat == EtatPersistanceElo.persistee &&
        empreintesIdentiques &&
        issueTemoin != IssueEcritureElo.persistee &&
        (diagnostic.protegeContreDoubleApplication ?? false);

    //  Le choix entre les deux mesures suit le CHEMIN RÉELLEMENT PRIS.
    //
    //  ⚠️ A7-39 (dernière vérification) — `??` ÉTAIT FAUTIF ICI, ET LE DÉFAUT A
    //     ÉTÉ MESURÉ AVANT CORRECTION. Écrire
    //         protegeApresPublie = protectionConstatee ?? protectionPreservee
    //     faisait retomber TOUT retour `null` du chemin ENRICHI sur la formule
    //     B2-d2, laquelle lit encore `diagnostic.protegeContreDoubleApplication`
    //     — c'est-à-dire le verdict de l'APPAREIL AVANT import. Deux façons
    //     d'obtenir `null` sur le chemin enrichi :
    //       • la constatation post-écriture échoue (relecture finale en échec,
    //         clé absente, type inattendu) ;
    //       • l'écriture du registre n'a pas eu lieu (refus, abandon par reset),
    //         donc il n'y a rien à relire.
    //     Dans ces deux cas, un appareil PROPRIÉTAIRE d'un registre cohérent et
    //     protégé, importé sans changement d'empreinte, satisfaisait
    //     `protectionPreservee` (`etat == persistee`, empreintes identiques,
    //     `issueTemoin == null`) : une protection était donc REVENDIQUÉE sans
    //     la moindre constatation post-import. C'était exactement la fausse
    //     sécurité que ce lot doit interdire.
    //
    //  ── RÈGLE POSÉE ──────────────────────────────────────────────────────────
    //     • CHEMIN ENRICHI : la valeur est `protectionConstatee`, et `null`
    //       devient `false`. Aucune revendication sans constatation.
    //     • CHEMIN HISTORIQUE : formule B2-d2 d'origine, STRICTEMENT inchangée
    //       (le témoin forcé `historiqueInconnu` rend la protection nulle par
    //       construction ; ce comportement est verrouillé par les tests A7).
    //     Le discriminant est `analyse.registreBrut`, la même condition que
    //     celle qui a choisi la branche de restitution — jamais une heuristique.
    final bool protegeApresPublie = analyse.registreBrut != null
        ? (protectionConstatee ?? false)
        : protectionPreservee;

    _dernierResultatImport = ResultatImportElo(
      etatRatings: etat,
      issueTemoin: issueTemoin,
      motifNonEcriture: motif,
      coherenceAvant: diagnostic.coherence,
      empreinteAvant: diagnostic.empreintePersistee,
      empreinteApres: empreinteApresMutation,
      origineAppliquee: origineAppliquee,
      protegeApres: protegeApresPublie,
    );

    if (motif != null) {
      if (issueTemoin == null) {
        debugPrint('[EloService] ⚠️ Registre NON ÉCRIT (${motif.name}) — '
            'registre existant PRÉSERVÉ, aucune réparation automatique');
      } else {
        debugPrint('[EloService] ⚠️ Registre TENTÉ puis NON CONFIRMÉ '
            '(issue=${issueTemoin.name}, motif=${motif.name}) — AUCUNE '
            'réparation automatique, aucune restitution de l\'ancienne valeur');
      }
    } else {
      // Le libellé suit le CHEMIN RÉELLEMENT PRIS : annoncer
      // `historiqueInconnu` sur une restitution verbatim serait un mensonge.
      final bool cheminEnrichi = analyse.registreBrut != null;
      debugPrint('[EloService] ✅ Registre écrit '
          '(origine=${origineAppliquee?.name}) — protection '
          'anti-double-application APRÈS import : '
          '${protegeApresPublie == true ? "constatée" : "non constatée"}'
          '${cheminEnrichi ? "" : " (chemin historique : formule d origine)"}');
    }

    return etat;
  }

  /// ★ v10.82 — D3 : chargement SYNCHRONE depuis une Map JSON, sans
  /// SharedPreferences (indisponible dans un isolate `compute()`).
  ///
  /// Lecture seule : ne sauvegarde rien, ne modifie aucun rating,
  /// ne touche à aucune formule ELO. Utilisé exclusivement par
  /// l'isolate de data_refresh_service.
  ///
  /// Sans ceci, dans un isolate, `EloService.instance` est une instance
  /// neuve (`_ratings` vide) et `enrichirAvecElo()` écrase `eloRating`
  /// avec le défaut 1500 → critère M figé à 37.5 pour tous les chevaux.
  void chargerDepuisMapIsolate(Map<String, dynamic> data) {
    _ratings.clear();
    data.forEach((key, val) {
      try {
        _ratings[key] = EloScore.fromJson(val as Map<String, dynamic>);
      } catch (_) {}
    });
    _charge = true;
    debugPrint('[EloService/isolate] ✅ ${_ratings.length} ratings restaurés');
  }

  /// ★ A7 (3.3-B1) — `reinitialiser()` reste HORS de la file FIFO, VOLONTAIREMENT.
  ///
  /// ⚠️ LIMITE DE CONCURRENCE ASSUMÉE ET DOCUMENTÉE (validée avec l'audit B1,
  /// non résolue par ce lot) :
  ///   • cette méthode vide `_ratings` (l. suivante) PUIS sauvegarde, sans
  ///     passer par [_executerEnFile]. Un `importerDepuisBackup` ou un
  ///     `mettreAJourApresArrivee` concurrent peut donc encore s'entrelacer
  ///     avec elle ;
  ///   • le `clear()` étant SYNCHRONE et le `_sauvegarder()` qui suit étant
  ///     soumis aux contrôles 1 et 2, le pire cas est une persistance NON
  ///     CONFIRMÉE — jamais une résurrection après un reset, ce cas-là étant
  ///     couvert par `executerResetComplet` ;
  ///   • elle n'a AUCUN appelant en production (mesuré : `grep` sur `lib/`,
  ///     0 occurrence) : 35 usages de test, dont un non attendu
  ///     (`test/v12_d2h8_lifecycle_test.dart:126`, en `setUp`). L'enfiler
  ///     rendrait son `clear()` asynchrone et décalerait ce `setUp`, avec un
  ///     risque de régression sur un test validé pour un gain nul en production.
  /// ⇒ NE PAS considérer cette limite comme définitivement résolue : elle
  ///   relève d'un lot ultérieur, si un appelant de production apparaît.
  Future<EtatPersistanceElo> reinitialiser() async {
    _ratings.clear();
    final etat = await _sauvegarder();
    debugPrint('[EloService] 🔄 ELO réinitialisés — persistance: ${etat.name}');
    return etat;
  }

  /// ★ B5-RDR-05 — Vide l'état RAM SANS écrire sur le disque.
  ///
  /// ⚠️ DEPUIS R-DR-05, CETTE MÉTHODE N'EST PLUS APPELÉE PAR LE RESET.
  /// `BackupService.reinitialiserComplet()` utilise désormais
  /// [executerResetComplet], qui vide `_ratings` dans son `finally`.
  ///
  /// Elle est CONSERVÉE parce que :
  ///   • elle est utilisée comme utilitaire de vidage RAM par
  ///     `test/v18_b5_reset_elo_test.dart` (setUp, tearDown et simulation de
  ///     redémarrage) — la supprimer casserait un test validé ;
  ///   • elle reste le moyen sûr de jeter la mémoire sans recréer les clés
  ///     (contrairement à [reinitialiser], qui termine par `_sauvegarder()`).
  ///
  /// ⚠️ COMPORTEMENT RÉSIDUEL DOCUMENTÉ (décision D-M2, non corrigé) :
  /// cette méthode est SYNCHRONE et n'attend RIEN. Appelée alors qu'une
  /// écriture de `_sauvegarder()` est encore en vol, elle vide `_ratings`
  /// mais n'empêche pas cette écriture d'aboutir avec la map qu'elle a déjà
  /// sérialisée. Elle ne ferme pas la barrière, n'incrémente pas la
  /// génération et ne draine pas le registre.
  /// ⇒ Pour un reset, utiliser [executerResetComplet]. Cette méthode ne doit
  ///   JAMAIS être utilisée comme substitut d'un encadrement de reset.
  void viderMemoirePourResetComplet() {
    _ratings.clear();
    debugPrint('[EloService] 🧹 Mémoire vidée (reset complet, disque non réécrit)');
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ B5c-RDR-05 — ENCADREMENT DU RESET COMPLET
  //
  //  Appelé EXCLUSIVEMENT par `BackupService.reinitialiserComplet()`, autour
  //  de la boucle des 108 suppressions, à l'intérieur des barrières
  //  d'`AlertService` et d'`IaMemoryService`.
  //
  //  Sémantique : identique à celle des autres services. On ne calcule RIEN,
  //  on jette un état mémoire devenu obsolète. Aucune formule, aucun
  //  K-factor, aucun rating n'est recalculé ni modifié.
  //
  //  Pourquoi le vidage RAM est dans le `finally` (décision D-M1) :
  //  `supprimerLesCles()` peut lever une `StateError` (C1-a) quand une
  //  suppression est refusée. Avant R-DR-05, l'appel au vidage était situé
  //  APRÈS le bloc, donc jamais atteint sur ce chemin : `_ratings` gardait
  //  les anciennes valeurs alors que les clés ELO avaient été supprimées du
  //  disque. Le `finally` rend le vidage INCONDITIONNEL, y compris en cas
  //  d'échec partiel.
  //
  //  ⚠️ `supprimerLesCles()` n'est entouré d'AUCUN `catch` : l'exception
  //  originale remonte telle quelle, avec sa pile, sans être transformée en
  //  succès. Seul un `finally` est présent.
  //
  //  ⚠️ `_charge` n'est PAS touché : il reste `true`. C'est mesuré et voulu
  //  (V29-C) — repasser `_charge` à `false` ferait relire le disque par
  //  `_charger()` et IMPORTERAIT les données résiduelles.
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> executerResetComplet(
      Future<void> Function() supprimerLesCles) async {
    // 1. Barrière SYNCHRONE — aucun `await` avant ces deux lignes, sinon une
    //    écriture pourrait naître dans la fenêtre.
    _resetEnCours = true;
    _generationCache++;
    //  ★ X1-b (correctif fraîcheur) — TÉMOIN DE L'EFFACEMENT DISQUE.
    //  Passe à `true` UNIQUEMENT quand `supprimerLesCles()` a rendu la main
    //  SANS lever. C'est la seule preuve dont dispose ce service que les clés
    //  ont effectivement été supprimées : il ne relit pas le stockage.
    //  Déclaré AVANT le `try` pour être visible dans le `finally`.
    var effacementConfirme = false;
    try {
      // 2. Drain des écritures ENGAGÉES. Boucle et non `Future.wait` unique :
      //    `whenComplete` s'exécute en microtâche APRÈS la complétion, donc
      //    un `wait` simple peut rendre la main registre non vide.
      //
      //    Sans ce drain, une écriture déjà au-delà des deux contrôles
      //    achèverait son `setString` APRÈS l'effacement et recréerait la clé
      //    (scénario V29-A, mesuré).
      //
      //    ★ A7 (3.3-B2-a) : le drain couvre désormais DEUX ensembles.
      //    [_ecrituresEnCours] est le témoin HISTORIQUE, inchangé et toujours
      //    exposé par `nbEcrituresEnCours`. [_ecrituresPersistantesEnCours]
      //    reçoit TOUTE écriture persistante, y compris celles que le lot
      //    B2-d ajoutera pour le registre ELO. Attendre les deux est ce qui
      //    empêchera un acquittement de recréer `elo_registre_v3` après son
      //    effacement — sans jamais changer la valeur du compteur historique.
      //
      //    CONVERGENCE : le drain est sous barrière (`_resetEnCours = true`
      //    et génération incrémentée, l.839-840, AVANT cette boucle). Toute
      //    opération nouvelle est donc vue comme périmée et s'abandonne AVANT
      //    d'écrire quoi que ce soit : aucun ensemble ne peut recevoir une
      //    nouvelle future pendant le drain. Il ne peut donc pas boucler
      //    indéfiniment.
      while (_ecrituresEnCours.isNotEmpty ||
          _ecrituresPersistantesEnCours.isNotEmpty) {
        final enVol = <Future<void>>{
          ..._ecrituresEnCours,
          ..._ecrituresPersistantesEnCours,
        };
        try {
          await Future.wait(enVol);
        } catch (_) {
          // Une écriture en échec ne doit jamais faire échouer le reset :
          // l'erreur est déjà journalisée par `_executerSauvegarde`.
        }
      }

      // 3. Effacement disque — TOUJOURS sous barrière.
      //    Aucune exception capturée : elle remonte TELLE QUELLE.
      await supprimerLesCles();
      //  ★ X1-b (correctif fraîcheur) — PREUVE D'EFFACEMENT.
      //  Atteint SEULEMENT si l'appel ci-dessus a rendu la main sans lever.
      //  Aucun `await` ne sépare ce marquage du `finally` : l'état observé
      //  par le `finally` est exactement celui de la sortie du `try`.
      effacementConfirme = true;
    } finally {
      // 4. Libérations INCONDITIONNELLES, même sur exception.
      //
      //    `_ratings.clear()` est ici, et pas après le bloc : c'est la
      //    décision D-M1. Un reset partiellement échoué ne doit pas laisser
      //    une RAM peuplée face à un disque dont les clés ELO sont parties.
      //
      //    Aucun `await` ne sépare ces deux instructions : aucune autre tâche
      //    ne peut s'intercaler entre le vidage et la réouverture.
      _ratings.clear();
      // ★ X1-b (P5) — RESET COMPLET, CONDITIONNÉ À LA PREUVE D'EFFACEMENT.
      //
      //  CAS 1 — `effacementConfirme == true` : `supprimerLesCles()` a rendu
      //  la main sans lever. La clé `elo_registre_v3` a donc été supprimée
      //  (elle figure dans `_keysELO`, lui-même inclus dans `_toutesLesCles`
      //  de `backup_service.dart`). Le registre est ABSENT : niveau `normal`
      //  et mesure EXACTE. `_niveauRegistre` ne conserve aucun maximum
      //  historique, la mesure est donc bien celle du disque.
      //
      //  CAS 2 — `effacementConfirme == false` : l'effacement a LEVÉ. Son
      //  contrat C1-a est explicite : « les suppressions déjà réussies ne
      //  sont PAS annulées ». Le disque est donc dans un état INTERMÉDIAIRE
      //  et `elo_registre_v3` peut y être encore présente. Annoncer `normal`
      //  + `exact = true` serait alors une mesure à la fois FAUSSE et
      //  présentée comme EXACTE (défaut mesuré : niveau annoncé `normal`,
      //  disque `saturation`, 7 144 737 octets encore présents).
      //
      //  On ne peut donc RIEN affirmer : le niveau reste INCHANGÉ (aucune
      //  valeur artificielle n'est inventée, notamment pas `normal`) et la
      //  mesure est déclarée NON EXACTE. La vérité est rétablie par la
      //  prochaine lecture réelle du disque, c'est-à-dire P1 (vérifié par
      //  mesure : dès la première opération traversant P1, niveau et disque
      //  redeviennent concordants et exacts).
      if (effacementConfirme) {
        _hydraterNiveauRegistre(null);
      } else {
        _niveauRegistreExact = false;
      }
      _resetEnCours = false;
      debugPrint('[EloService] 🧹 Mémoire vidée (reset complet, disque non réécrit)');
    }
  }
}
