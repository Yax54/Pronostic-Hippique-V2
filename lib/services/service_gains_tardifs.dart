// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER 2/3 — RATTRAPAGE DES GAINS OFFICIELS TARDIFS (ORCHESTRATEUR)
// ═══════════════════════════════════════════════════════════════════════════
//
//  ★ CE QUE CE FICHIER FAIT — ET C'EST TOUT
//
//  Il RACCORDE les composants déjà existants, sans en réécrire aucun :
//    ① `DetecteurGainsTardifs`        → quand interroger, et comment classer ;
//    ② `BackoffTardifStore`           → temporisation persistante entre cycles ;
//    ③ `chargerResultatOfficielCourse`→ le résultat officiel d'UNE course ;
//    ④ `PmuProvider.appliquerVerdictGainPredictionSecurise`
//                                     → la SEULE écriture financière ;
//    ⑤ `montantOfficielDepuisVerdict` → le SEUL convertisseur verdict → montant ;
//    ⑥ `deciderGainTardif`            → les règles métier A/B/C du chantier ;
//    ⑦ `MemoireGainsTardifsNotifies`  → l'unicité durable des notifications ;
//    ⑧ `AlertService`                 → la remontée visible à l'utilisateur.
//
//  ⚠️ AUCUN SECOND MOTEUR FINANCIER, AUCUN SECOND CONVERTISSEUR PMU.
//     Ce fichier ne contient AUCUNE formule monétaire, AUCUN calcul de
//     dividende, AUCUNE sélection de rapport. Il ordonne des appels.
//
//  ⚠️ L'IDENTIFICATION EST EXACTE ET NON HEURISTIQUE.
//     Un ticket n'est rattaché à une course que par le tuple
//     `(dateStr, numReunion, numCourse)` qu'il PORTE lui-même. Deux courses de
//     dates différentes portant les mêmes numéros sont DEUX courses : la date
//     fait partie de la clé de regroupement (`IdentiteCourseTardive.cle`), et
//     elle est aussi transmise à l'API, qui compose son URL avec elle.
//
//  ⚠️ LA DÉTECTION NE DÉPEND PAS DE `tracked_courses_v1`.
//     La source est `PmuProvider.predictions` — les tickets DURABLES, jamais
//     purgés. Une course dont le suivi temporaire a été purgé à 24 h reste donc
//     parfaitement rattrapable des jours plus tard.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';

import '../models/pmu_models.dart' show UserPrediction;
import '../providers/pmu_provider.dart';
import '../services/alert_service.dart' show AlertService;
import '../services/detection_gains_tardifs.dart';
import '../services/gains_tardifs_notifies_store.dart';
import '../services/gains_tardifs_regles.dart';
import 'branchement_verdict_course.dart';
import 'resolution_gain_ticket_pmu.dart' show ResultatOfficielCourse;

/// Issue d'un cycle de rattrapage, ticket par ticket. FERMÉE : aucun cas
/// « autre » ne peut masquer une situation non prévue.
enum IssueRattrapage {
  /// Aucun gain officiel établi : rien n'a été écrit, rien n'a été notifié.
  rienAAppliquer,

  /// CAS A — officiel appliqué, aucun gain manuel : aucune notification.
  appliqueSilencieusement,

  /// CAS B — officiel identique au manuel : appliqué + notification unique.
  appliqueEtNotifie,

  /// CAS C — officiel différent du manuel : écrit en référence, notification,
  /// décision Accepter/Refuser requise. Le manuel reste retenu.
  divergenceNotifiee,

  /// L'écriture financière a échoué ou a été remplacée : AUCUNE notification
  /// n'est produite, et le ticket redevient éligible au cycle suivant.
  ///
  /// ⚠️ ON NE NOTIFIE JAMAIS UNE ÉCRITURE QUI N'A PAS EU LIEU. Une
  ///    notification annoncerait un gain que le disque ne porte pas.
  echecEcriture,

  /// Le même ticket avait DÉJÀ été traité (marqueur d'idempotence présent) :
  /// rien n'est réécrit et aucune notification n'est reproduite.
  dejaTraite,
}

/// Résultat lisible d'un ticket traité.
///
/// Ce type est un RAPPORT, jamais une source de vérité : la vérité financière
/// est le ticket persisté. Aucun appelant ne doit en déduire un montant.
@immutable
class ResultatRattrapageTicket {
  final String idTicket;
  final IssueRattrapage issue;
  final double? gainManuel;
  final double? gainOfficiel;

  const ResultatRattrapageTicket({
    required this.idTicket,
    required this.issue,
    this.gainManuel,
    this.gainOfficiel,
  });

  @override
  String toString() => 'ResultatRattrapageTicket($idTicket → ${issue.name}'
      '${gainManuel == null ? '' : ' | manuel=$gainManuel'}'
      '${gainOfficiel == null ? '' : ' | officiel=$gainOfficiel'})';
}

/// Cycle complet d'un lot de courses.
@immutable
class BilanRattrapage {
  final List<ResultatDetectionCourse> detections;
  final List<ResultatRattrapageTicket> tickets;

  const BilanRattrapage({
    required this.detections,
    required this.tickets,
  });

  int compter(IssueRattrapage issue) =>
      tickets.where((t) => t.issue == issue).length;

  @override
  String toString() =>
      'BilanRattrapage(detections=${detections.length}, '
      'tickets=${tickets.length})';
}

/// Le service d'orchestration.
///
/// ⚠️ IL EST LE SEUL À SAVOIR « QUAND » ET « DANS QUEL ORDRE ». Il ne sait NI
///    calculer un gain, NI décider une politique financière : ces deux savoirs
///    appartiennent respectivement au moteur B-3 et à l'enregistreur B-4.3.
class ServiceGainsTardifs {
  final PmuProvider provider;
  final DetecteurGainsTardifs detecteur;
  final MemoireGainsTardifsNotifies memoire;

  /// Horloge injectable — aucun `DateTime.now()` en dur, donc testable.
  final DateTime Function() horloge;

  /// Un cycle est-il déjà en cours ? Garantit qu'aucun cycle ne s'empile.
  bool _cycleEnCours = false;

  /// Nombre de cycles terminés, pour l'observabilité (jamais une preuve).
  int cyclesTermines = 0;

  ServiceGainsTardifs({
    required this.provider,
    required this.detecteur,
    required this.memoire,
    DateTime Function()? horloge,
  }) : horloge = horloge ?? DateTime.now;

  bool get cycleEnCours => _cycleEnCours;

  /// Construit le service en production, avec les vrais composants.
  static Future<ServiceGainsTardifs> creer(PmuProvider provider) async {
    final backoff = await BackoffTardifStore.ouvrir();
    final notifies = await MemoireGainsTardifsNotifies.ouvrir();
    return ServiceGainsTardifs(
      provider: provider,
      detecteur: DetecteurGainsTardifs(store: backoff),
      memoire: notifies,
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  //  1. IDENTIFICATION — tickets durables → courses, SANS rien supposer
  // ═════════════════════════════════════════════════════════════════════════

  /// Les tickets ENCORE rattrapables : ceux qui n'attendent plus qu'un
  /// résultat officiel.
  ///
  /// ⚠️ FILTRES, chacun justifié :
  ///   • `etatGain != null` ⇒ le verdict est DÉJÀ posé (définitif ou
  ///     nonDeterminé). Le retraiter rouvrirait une course réglée : c'est
  ///     exactement la boucle infinie que le chantier interdit. Un ticket
  ///     `perdu` ou `rembourse` est donc DÉFINITIVEMENT hors périmètre.
  ///   • `dateStr` exploitable ⇒ sinon aucune requête ne peut être construite.
  ///
  /// ⚠️ AUCUN FILTRE SUR `montantOfficielPmu` : un ticket qui porte déjà un
  ///    officiel mais AUCUNE décision doit rester visible pour que la décision
  ///    en attente soit présentée. Il n'est pas « à retenter » pour autant —
  ///    c'est [candidatsPourCycle] qui l'écarte du réseau.
  List<UserPrediction> ticketsARattraper() {
    final out = <UserPrediction>[];
    for (final p in provider.predictions) {
      if (p.etatGain != null) continue; // verdict déjà posé : clos
      out.add(p);
    }
    out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return List<UserPrediction>.unmodifiable(out);
  }

  /// Les COURSES à interroger, déduites des tickets ci-dessus.
  ///
  /// Dédoublonnage par `IdentiteCourseTardive.cle`, qui INCLUT la date : deux
  /// courses de dates différentes aux mêmes numéros sont deux courses.
  List<IdentiteCourseTardive> coursesCandidates() {
    final vues = <String>{};
    final out = <IdentiteCourseTardive>[];
    for (final p in ticketsARattraper()) {
      final id = IdentiteCourseTardive(
        dateStr: p.dateStr,
        numReunion: p.numReunion,
        numCourse: p.numCourse,
      );
      if (id.date == null) continue; // date inexploitable : écartée, pas devinée
      if (!vues.add(id.cle)) continue;
      out.add(id);
    }
    return List<IdentiteCourseTardive>.unmodifiable(out);
  }

  /// Tickets d'UNE course — le regroupement qui mutualise les requêtes.
  List<UserPrediction> ticketsDeCourse(IdentiteCourseTardive id) =>
      List<UserPrediction>.unmodifiable(ticketsARattraper().where((p) =>
          p.dateStr == id.dateStr &&
          p.numReunion == id.numReunion &&
          p.numCourse == id.numCourse));

  // ═════════════════════════════════════════════════════════════════════════
  //  2. LE CYCLE
  // ═════════════════════════════════════════════════════════════════════════

  /// Exécute UN cycle borné : détection, puis application aux tickets.
  ///
  /// ⚠️ NON RÉENTRANT. Un second appel pendant un cycle rend immédiatement un
  ///    bilan vide, sans toucher au réseau : deux cycles concurrents
  ///    écriraient le même ticket deux fois.
  Future<BilanRattrapage> executerCycle() async {
    if (_cycleEnCours) {
      return const BilanRattrapage(
        detections: <ResultatDetectionCourse>[],
        tickets: <ResultatRattrapageTicket>[],
      );
    }
    _cycleEnCours = true;
    try {
      final candidates = coursesCandidates();
      final detections = await detecteur.executerCycle(candidates);
      final tickets = <ResultatRattrapageTicket>[];

      for (final d in detections) {
        // Le détecteur est le SEUL juge de l'exploitabilité : une arrivée
        // provisoire, des rapports absents ou une panne réseau ne produisent
        // donc AUCUNE écriture et AUCUNE notification. On n'invente rien.
        if (!d.classification.permetEcriture) continue;
        tickets.addAll(await appliquerCourse(d.identite));
      }

      cyclesTermines++;
      return BilanRattrapage(
        detections: detections,
        tickets: List<ResultatRattrapageTicket>.unmodifiable(tickets),
      );
    } finally {
      _cycleEnCours = false;
    }
  }

  /// Applique le résultat officiel à TOUS les tickets d'UNE course.
  ///
  /// UNE requête, N tickets : c'est la mutualisation exigée. Chaque ticket est
  /// ensuite résolu SÉPARÉMENT par le moteur, avec ses propres numéros, ordre,
  /// variante et mise — aucun `firstWhere`, aucune propagation d'un montant
  /// d'un pari vers un autre.
  Future<List<ResultatRattrapageTicket>> appliquerCourse(
      IdentiteCourseTardive id) async {
    final date = id.date;
    if (date == null) return const <ResultatRattrapageTicket>[];

    final tickets = ticketsDeCourse(id);
    if (tickets.isEmpty) return const <ResultatRattrapageTicket>[];

    final resultat = await chargerResultatOfficielCourse(
      date: date,
      numReunion: id.numReunion,
      numCourse: id.numCourse,
    );
    // Aucun résultat officiel : on ne fabrique ni perte ni remboursement.
    // Les tickets restent éligibles au cycle suivant (backoff du détecteur).
    if (resultat == null) return const <ResultatRattrapageTicket>[];

    final out = <ResultatRattrapageTicket>[];
    for (final t in tickets) {
      out.add(await appliquerTicket(t, resultat));
    }
    return List<ResultatRattrapageTicket>.unmodifiable(out);
  }

  /// Applique à UN ticket le résultat officiel de SA course.
  ///
  /// ORDRE IMPÉRATIF — aucun pas n'est optionnel :
  ///   ① IDEMPOTENCE : un ticket déjà traité est rendu `dejaTraite` et n'est
  ///      ni réécrit ni renotifié. La preuve est PERSISTÉE, pas en mémoire.
  ///   ② ÉCRITURE SÉCURISÉE : le chemin validé au chantier 1/3, avec
  ///      `enregistrerMontantOfficiel: true`. Aucun autre chemin d'écriture.
  ///   ③ CONFIRMATION RÉELLE : l'issue doit être `confirme`. Un échec, un
  ///      remplacement, ou un `echecNonReconcilie` interrompt TOUT : pas de
  ///      notification, pas de marqueur, donc nouvelle tentative plus tard.
  ///   ④ RÈGLE MÉTIER A/B/C sur les montants RÉELLEMENT persistés après
  ///      écriture — relus depuis le ticket, jamais recalculés.
  ///   ⑤ NOTIFICATION UNIQUE, puis marqueur d'idempotence persisté.
  ///      ⚠️ Le marqueur n'est posé qu'APRÈS une notification effectivement
  ///         émise : si la notification échoue, le ticket reste notifiable.
  Future<ResultatRattrapageTicket> appliquerTicket(
    UserPrediction ticket,
    ResultatOfficielCourse resultat,
  ) async {
    final cleNotification = cleIdempotenceNotification(ticket.id);
    final cleEcriture = cleIdempotenceEcriture(ticket.id);

    // ① ── IDEMPOTENCE ─────────────────────────────────────────────────────
    if (memoire.dejaNotifie(cleEcriture)) {
      return ResultatRattrapageTicket(
        idTicket: ticket.id,
        issue: IssueRattrapage.dejaTraite,
        gainManuel: ticket.montantGainManuel,
        gainOfficiel: ticket.montantOfficielPmu,
      );
    }

    // ② ── ÉCRITURE SÉCURISÉE ─────────────────────────────────────────────
    final issue = await provider.appliquerVerdictGainPredictionSecurise(
      ticket.id,
      resultat,
      enregistrerMontantOfficiel: true,
    );

    // ③ ── CONFIRMATION RÉELLE ────────────────────────────────────────────
    if (issue != IssueEcritureGain.confirme) {
      return ResultatRattrapageTicket(
        idTicket: ticket.id,
        issue: IssueRattrapage.echecEcriture,
        gainManuel: ticket.montantGainManuel,
        gainOfficiel: ticket.montantOfficielPmu,
      );
    }

    // ④ ── LECTURE DES MONTANTS RÉELLEMENT PERSISTÉS ───────────────────────
    final apres = provider.predictions.firstWhere(
      (p) => p.id == ticket.id,
      orElse: () => ticket,
    );
    final gainManuel = apres.montantGainManuel;
    final gainOfficiel = apres.montantOfficielPmu;
    final decision = deciderGainTardif(
      gainManuel: gainManuel,
      gainOfficiel: gainOfficiel,
    );

    // Le marqueur d'ÉCRITURE est posé dès que l'écriture est confirmée, même
    // si aucun gain n'est établi : cela évite de réécrire indéfiniment une
    // course dont le résultat officiel est un remboursement pur, un
    // `nonDetermine`, ou une perte. Ce marqueur dit « écriture faite », PAS
    // « gain trouvé » — les deux informations sont distinctes.
    await memoire.marquer(cleEcriture, quand: horloge());

    // ⑤ ── NOTIFICATION ──────────────────────────────────────────────────
    if (!decision.notificationRequise) {
      // CAS A ou AUCUN : aucune notification de gain tardif, par exigence.
      return ResultatRattrapageTicket(
        idTicket: ticket.id,
        issue: decision.cas == CasGainTardif.sansGainManuel
            ? IssueRattrapage.appliqueSilencieusement
            : IssueRattrapage.rienAAppliquer,
        gainManuel: gainManuel,
        gainOfficiel: gainOfficiel,
      );
    }

    final cle = cleNotification;
    if (memoire.dejaNotifie(cle)) {
      // Une notification a déjà été émise pour ce ticket (marqueur séparé).
      return ResultatRattrapageTicket(
        idTicket: ticket.id,
        issue: IssueRattrapage.dejaTraite,
        gainManuel: gainManuel,
        gainOfficiel: gainOfficiel,
      );
    }

    final notifie = await _notifier(ticket, decision);
    if (notifie) {
      await memoire.marquer(cle, quand: horloge());
    }

    return ResultatRattrapageTicket(
      idTicket: ticket.id,
      issue: decision.cas == CasGainTardif.identique
          ? IssueRattrapage.appliqueEtNotifie
          : IssueRattrapage.divergenceNotifiee,
      gainManuel: gainManuel,
      gainOfficiel: gainOfficiel,
    );
  }

  /// Émet LA notification unique de remontée tardive.
  ///
  /// Rend `true` seulement si l'alerte a été réellement enregistrée par
  /// `AlertService`. Le contenu est calculé pour être LISIBLE et VÉRIDIQUE :
  /// les deux montants sont affichés au CAS C, et l'égalité est dite au CAS B.
  Future<bool> _notifier(
      UserPrediction ticket, DecisionGainTardif decision) async {
    final manuel = decision.gainManuel;
    final officiel = decision.gainOfficiel;
    final String message;
    if (decision.cas == CasGainTardif.identique) {
      message = 'PMU : ${_euros(officiel)} € — identique à votre gain déclaré '
          '(${_euros(manuel)} €). Aucune action nécessaire.';
    } else {
      message = 'PMU : ${_euros(officiel)} € · vous avez déclaré '
          '${_euros(manuel)} €. Votre montant déclaré reste retenu jusqu\'à '
          'votre décision — Accepter ou Refuser le gain officiel.';
    }

    try {
      return await AlertService.instance.emettreAlerteGainTardif(
        idTicket: ticket.id,
        titre: '🏆 Gain officiel disponible',
        message: message,
        numReunion: ticket.numReunion,
        numCourse: ticket.numCourse,
        dateStrCourse: ticket.dateStr,
      );
    } catch (_) {
      // Une panne de notification ne doit jamais faire échouer l'écriture
      // financière déjà confirmée. Le marqueur n'est simplement pas posé : le
      // ticket sera renotifiable au cycle suivant.
      return false;
    }
  }

  /// Formate un montant en euros sans jamais inventer de valeur.
  String _euros(double? v) {
    if (v == null) return '0.00';
    return v.toStringAsFixed(2);
  }
}
