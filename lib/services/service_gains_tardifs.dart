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
//    ⑤ `deciderGainTardif`            → les règles métier A/B/C du chantier ;
//    ⑥ `MemoireGainsTardifsNotifies`  → l'unicité durable des notifications ;
//    ⑦ `AlertService`                 → la remontée visible à l'utilisateur.
//
//  ⚠️ AUCUN SECOND MOTEUR FINANCIER, AUCUN SECOND CONVERTISSEUR PMU.
//     Ce fichier ne contient AUCUNE formule monétaire, AUCUN calcul de
//     dividende, AUCUNE sélection de rapport. Il ordonne des appels.
//
//  ★ CORRECTION DU DÉFAUT DE `dcb4b49` — TROIS ÉTAPES DISSOCIÉES
//
//  DÉFAUT MESURÉ : un seul marqueur servait à la fois de preuve d'écriture et
//  de preuve de traitement. Un ticket dont l'écriture réussissait mais dont la
//  notification échouait (ou était refusée parce que les notifications étaient
//  désactivées) sortait des candidats — `ticketsARattraper()` écarte tout
//  ticket dont `etatGain != null` — et la notification attendue disparaissait
//  DÉFINITIVEMENT.
//
//  CORRECTION : les trois étapes sont désormais calculées séparément par
//  `resteAFaire(...)` (pur, testable) :
//    ① ÉCRITURE du résultat officiel — marqueur `ge1:` ;
//    ② NOTIFICATION — marqueur `gt1:`, calculée INDÉPENDAMMENT de ① ;
//    ③ DÉCISION Accepter/Refuser — vérité portée par le TICKET
//      (`decisionGainPmu`), marqueur d'audit `gd1:`.
//
//  ⚠️ CONSÉQUENCES DIRECTES, chacune exigée par la consigne :
//    • une notification encore nécessaire est REPRISE SANS RÉSEAU et SANS
//      RÉÉCRITURE du résultat officiel ([reprendreNotifications]) ;
//    • une notification refusée par la configuration n'est PAS marquée comme
//      émise : elle sera reprise à la réactivation ;
//    • une décision en attente reste accessible même si l'historique des
//      alertes est purgé, puisqu'elle se déduit du ticket.
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

  /// Le même ticket avait DÉJÀ été traité (marqueurs présents) : rien n'est
  /// réécrit et aucune notification n'est reproduite.
  dejaTraite,

  /// Une notification encore nécessaire a été REPRISE sans réseau et sans
  /// réécriture du résultat officiel déjà persisté.
  notificationReprise,
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

  /// Les tickets dont l'ÉCRITURE officielle reste à faire.
  ///
  /// ⚠️ FILTRES, chacun justifié :
  ///   • `etatGain != null` ⇒ le verdict est DÉJÀ posé (définitif ou
  ///     nonDeterminé). Le retraiter rouvrirait une course réglée : c'est
  ///     exactement la boucle infinie que le chantier interdit. Un ticket
  ///     `perdu` ou `rembourse` est donc DÉFINITIVEMENT hors périmètre de
  ///     récupération réseau — SAUF si sa notification manque encore, cas
  ///     traité séparément par [reprendreNotifications], qui n'utilise PAS le
  ///     réseau.
  ///
  /// ★ CORRECTION DU DÉFAUT `dcb4b49` : ce filtre ne sert PLUS à décider de
  ///   l'opportunité d'une notification. Il ne gouverne QUE la récupération du
  ///   rapport officiel. La notification a son propre calcul.
  List<UserPrediction> ticketsARattraper() {
    final out = <UserPrediction>[];
    for (final p in provider.predictions) {
      if (p.etatGain != null) continue; // écriture faite : pas de réseau
      out.add(p);
    }
    out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return List<UserPrediction>.unmodifiable(out);
  }

  /// Les COURSES à interroger, déduites des tickets ci-dessus.
  ///
  /// Dédoublonnage par `IdentiteCourseTardive.cle`, qui INCLUT la date : deux
  /// courses de dates différentes aux mêmes numéros sont deux courses.
  ///
  /// ⚠️ C'EST LA MUTUALISATION EXIGÉE : N tickets d'une même course ne
  ///    produisent qu'UNE entrée ici, donc UNE requête dans `appliquerCourse`.
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

  /// Exécute UN cycle borné : reprise des notifications, puis détection et
  /// application aux tickets.
  ///
  /// ⚠️ NON RÉENTRANT. Un second appel pendant un cycle rend immédiatement un
  ///    bilan vide, sans toucher au réseau : deux cycles concurrents
  ///    écriraient le même ticket deux fois.
  ///
  /// ★ ORDRE : les notifications REPRISES passent EN PREMIER, parce qu'elles
  ///   ne coûtent aucun réseau et qu'elles sont la correction du défaut. Un
  ///   cycle qui échouerait ensuite sur le réseau a quand même rendu le
  ///   service attendu.
  Future<BilanRattrapage> executerCycle() async {
    if (_cycleEnCours) {
      return const BilanRattrapage(
        detections: <ResultatDetectionCourse>[],
        tickets: <ResultatRattrapageTicket>[],
      );
    }
    _cycleEnCours = true;
    try {
      final tickets = <ResultatRattrapageTicket>[];
      tickets.addAll(await reprendreNotifications());

      final candidates = coursesCandidates();
      final detections = await detecteur.executerCycle(candidates);

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

  /// REPRISE DES NOTIFICATIONS ENCORE NÉCESSAIRES — SANS RÉSEAU, SANS
  /// RÉÉCRITURE.
  ///
  /// ★ C'EST LA CORRECTION DU DÉFAUT. Sont concernés les tickets dont le
  ///   résultat officiel est DÉJÀ persisté (`etatGain != null`) mais dont la
  ///   notification manque : échec d'émission, notifications désactivées au
  ///   moment du traitement, ou interruption entre l'écriture et la
  ///   notification.
  ///
  /// ⚠️ AUCUN APPEL RÉSEAU : le montant officiel est lu sur le ticket. C'est
  ///    ce qui rend la reprise possible même quand le rapport n'est plus
  ///    récupérable, et ce qui évite de « réécrire inutilement le résultat
  ///    financier officiel à chaque tentative » (exigence littérale).
  ///
  /// ⚠️ UN TICKET DÉJÀ NOTIFIÉ N'EST PAS RENOTIFIÉ : le marqueur `gt1:` est
  ///    consulté AVANT toute émission.
  Future<List<ResultatRattrapageTicket>> reprendreNotifications() async {
    final out = <ResultatRattrapageTicket>[];
    for (final p in provider.predictions) {
      // L'écriture doit être faite : sinon c'est le cycle normal qui s'en
      // charge, avec le réseau.
      if (p.etatGain == null) continue;

      final decision = deciderGainTardif(
        gainManuel: p.montantGainManuel,
        gainOfficiel: p.montantOfficielPmu,
      );
      final etapes = resteAFaire(
        resultatOfficielPersiste: _resultatOfficielPersiste(p),
        ecritureDejaConfirmee: memoire.dejaMarque(cleIdempotenceEcriture(p.id)),
        notificationDejaEmise:
            memoire.dejaMarque(cleIdempotenceNotification(p.id)),
        decisionEnregistree: p.decisionGainPmu != null,
        decisionRequiseParLaRegle: decision.notificationRequise,
      );
      if (!etapes.notification) continue;

      final emise = await _notifier(p, decision);
      if (emise) {
        await memoire.marquer(cleIdempotenceNotification(p.id), quand: horloge());
      }
      out.add(ResultatRattrapageTicket(
        idTicket: p.id,
        issue: emise
            ? IssueRattrapage.notificationReprise
            : IssueRattrapage.echecEcriture,
        gainManuel: p.montantGainManuel,
        gainOfficiel: p.montantOfficielPmu,
      ));
    }
    return List<ResultatRattrapageTicket>.unmodifiable(out);
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
  ///   ① ÉTAPES CALCULÉES : `resteAFaire` dit séparément ce qui manque.
  ///   ② ÉCRITURE SÉCURISÉE, uniquement si elle est nécessaire : le chemin
  ///      validé au chantier 1/3, avec `enregistrerMontantOfficiel: true`.
  ///      Aucun autre chemin d'écriture.
  ///   ③ CONFIRMATION RÉELLE : l'issue doit être `confirme`. Un échec, un
  ///      remplacement, ou un `echecNonReconcilie` interrompt TOUT : pas de
  ///      notification, pas de marqueur `ge1:`, donc nouvelle tentative.
  ///   ④ RÈGLE MÉTIER A/B/C sur les montants RÉELLEMENT persistés après
  ///      écriture — relus depuis le ticket, jamais recalculés.
  ///   ⑤ NOTIFICATION UNIQUE, puis marqueur `gt1:` SEME si elle a été émise.
  ///      ⚠️ Le marqueur n'est posé qu'APRÈS une émission réellement
  ///         confirmée : une notification refusée n'est jamais « émise ».
  Future<ResultatRattrapageTicket> appliquerTicket(
    UserPrediction ticket,
    ResultatOfficielCourse resultat,
  ) async {
    // ① ── ÉTAPES ──────────────────────────────────────────────────────────
    final avant = deciderGainTardif(
      gainManuel: ticket.montantGainManuel,
      gainOfficiel: ticket.montantOfficielPmu,
    );
    final etapesAvant = resteAFaire(
      resultatOfficielPersiste: _resultatOfficielPersiste(ticket),
      ecritureDejaConfirmee: memoire.dejaMarque(cleIdempotenceEcriture(ticket.id)),
      notificationDejaEmise:
          memoire.dejaMarque(cleIdempotenceNotification(ticket.id)),
      decisionEnregistree: ticket.decisionGainPmu != null,
      decisionRequiseParLaRegle: avant.notificationRequise,
    );
    if (!etapesAvant.ecriture && !etapesAvant.notification) {
      return ResultatRattrapageTicket(
        idTicket: ticket.id,
        issue: IssueRattrapage.dejaTraite,
        gainManuel: ticket.montantGainManuel,
        gainOfficiel: ticket.montantOfficielPmu,
      );
    }

    // ② ── ÉCRITURE, SEULEMENT SI NÉCESSAIRE ──────────────────────────────
    if (etapesAvant.ecriture) {
      final issue = await provider.appliquerVerdictGainPredictionSecurise(
        ticket.id,
        resultat,
        enregistrerMontantOfficiel: true,
      );
      if (issue != IssueEcritureGain.confirme) {
        return ResultatRattrapageTicket(
          idTicket: ticket.id,
          issue: IssueRattrapage.echecEcriture,
          gainManuel: ticket.montantGainManuel,
          gainOfficiel: ticket.montantOfficielPmu,
        );
      }
      // Marqueur d'ÉCRITURE posé dès la confirmation : il dit « le résultat
      // officiel est sur le ticket », PAS « gain trouvé » ni « notifié ».
      await memoire.marquer(cleIdempotenceEcriture(ticket.id), quand: horloge());
    }

    // ③ ── LECTURE DES MONTANTS RÉELLEMENT PERSISTÉS ──────────────────────
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

    // ④ ── NOTIFICATION, CALCULÉE INDÉPENDAMMENT DE L'ÉCRITURE ────────────
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

    if (memoire.dejaMarque(cleIdempotenceNotification(ticket.id))) {
      // Une notification a déjà été émise pour ce ticket (marqueur séparé).
      return ResultatRattrapageTicket(
        idTicket: ticket.id,
        issue: IssueRattrapage.dejaTraite,
        gainManuel: gainManuel,
        gainOfficiel: gainOfficiel,
      );
    }

    final notifie = await _notifier(apres, decision);
    if (notifie) {
      await memoire.marquer(cleIdempotenceNotification(ticket.id),
          quand: horloge());
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

  /// Le ticket porte-t-il un résultat officiel DÉJÀ persisté ?
  ///
  /// ⚠️ DEUX FORMES, toutes deux légitimes :
  ///    • un gain officiel (`montantOfficielPmu`, y compris `0.0` = perte) ;
  ///    • un remboursement officiel (`remboursementPmu`), qui n'est PAS un
  ///      gain mais qui prouve que le résultat a été écrit. Sans cette
  ///      seconde forme, un remboursement pur serait considéré comme « rien
  ///      d'écrit » et provoquerait une récupération réseau à chaque cycle —
  ///      exactement la boucle interdite.
  bool _resultatOfficielPersiste(UserPrediction p) =>
      p.montantOfficielPmu != null || p.remboursementPmu != null;

  /// Mémorise qu'une décision a été CONFIRMÉE, pour l'audit.
  ///
  /// ⚠️ N'EST JAMAIS UNE CONDITION DE CORRECTION : la vérité financière est
  ///    `decisionGainPmu` sur le ticket. Ce marqueur ne fait que tracer.
  Future<bool> memoriserDecision(String idTicket) =>
      memoire.marquer(cleIdempotenceDecision(idTicket), quand: horloge());

  /// Émet LA notification unique de remontée tardive.
  ///
  /// Rend `true` seulement si l'alerte a été réellement enregistrée ET
  /// persistée par `AlertService`. Le contenu est calculé pour être LISIBLE et
  /// VÉRIDIQUE : les deux montants sont affichés au CAS C, l'égalité est dite
  /// au CAS B, et un remboursement est nommé séparément — il n'est JAMAIS
  /// additionné au gain.
  Future<bool> _notifier(
      UserPrediction ticket, DecisionGainTardif decision) async {
    final manuel = decision.gainManuel;
    final officiel = decision.gainOfficiel;
    final remboursement = ticket.remboursementPmu;

    final String message;
    if (decision.cas == CasGainTardif.identique) {
      message = 'PMU : ${_euros(officiel)} € — identique à votre gain déclaré '
          '(${_euros(manuel)} €). Aucune action nécessaire.';
    } else {
      message = 'PMU : ${_euros(officiel)} € · vous avez déclaré '
          '${_euros(manuel)} €. Votre montant déclaré reste retenu jusqu\'à '
          'votre décision — Accepter ou Refuser le gain officiel.';
    }
    // Remboursement : information AJOUTÉE, jamais fusionnée au gain.
    final messageComplet = remboursement == null
        ? message
        : '$message\nRemboursement officiel : '
            '${_euros(remboursement)} € (distinct du gain).';

    try {
      return await AlertService.instance.emettreAlerteGainTardif(
        idTicket: ticket.id,
        titre: '🏆 Gain officiel disponible',
        message: messageComplet,
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
