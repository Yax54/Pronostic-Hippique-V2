// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER 2/3 — DÉCLENCHEURS DU RATTRAPAGE DES GAINS TARDIFS
// ═══════════════════════════════════════════════════════════════════════════
//
//  ★ CE QUE CE FICHIER FAIT — ET C'EST TOUT
//
//  Il décide QUAND un cycle de rattrapage a le droit de démarrer. Il ne
//  calcule rien, ne lit aucun rapport, n'écrit aucun montant : ce travail
//  appartient entièrement à `ServiceGainsTardifs` (et, derrière lui, au moteur
//  B-3 et au chemin d'écriture sécurisée du lot 2-C).
//
//  Les TROIS déclencheurs exigés par le chantier :
//    ① ouverture de l'application          → [demarrer]
//    ② retour au premier plan              → [retourPremierPlan]
//    ③ périodiquement pendant l'usage      → le minuteur interne
//
//  ⚠️ UN SEUL CYCLE À LA FOIS, À DEUX NIVEAUX.
//     • [ServiceGainsTardifs.executerCycle] est déjà non réentrant ;
//     • ce planificateur ajoute sa propre barrière [_enCours] AVANT de
//       l'appeler, et une DISTANCE MINIMALE entre deux cycles.
//     Le second niveau n'est pas une redondance décorative : il évite de
//     seulement ENTRER dans le service (et donc de construire un bilan vide)
//     quand l'application revient au premier plan trois fois en dix secondes.
//
//  ⚠️ AUCUNE REQUÊTE NE PART D'ICI. Le groupement des tickets d'une même
//     course est fait par `ServiceGainsTardifs.appliquerCourse` : une seule
//     requête pour N tickets. Ce fichier ne connaît même pas les tickets.
//
//  ⚠️ LES ERREURS NE SONT JAMAIS PROPAGÉES.
//     Un échec réseau au démarrage de l'application ne doit pas empêcher
//     l'application de démarrer. Elles sont capturées, comptées, et le cycle
//     suivant repartira — c'est exactement l'exigence « ne jamais abandonner
//     définitivement un ticket ».
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/service_gains_tardifs.dart';

/// Le planificateur. Il possède le minuteur, pas le savoir-faire financier.
class PlanificateurGainsTardifs {
  /// Le service réel. `null` tant que [demarrer] n'a pas abouti : sans
  /// `SharedPreferences` ouvert, aucun marqueur d'idempotence ne peut être
  /// lu, donc aucun cycle ne doit tourner.
  final Future<ServiceGainsTardifs> Function() _fabrique;

  /// Intervalle entre deux cycles automatiques.
  final Duration intervalle;

  /// Distance minimale entre deux cycles, tous déclencheurs confondus. Empêche
  /// qu'un retour au premier plan suivi d'un tic de minuterie ne fasse deux
  /// cycles pour rien.
  final Duration distanceMinimale;

  /// Horloge injectable — testable, aucun `DateTime.now()` en dur.
  final DateTime Function() horloge;

  ServiceGainsTardifs? _service;
  Timer? _minuteur;

  /// Barrière de non-réentrance, propre au planificateur.
  bool _enCours = false;

  DateTime? _dernierDemarrage;

  /// Compteurs d'observabilité — jamais des preuves.
  int cyclesLances = 0;
  int demarragesRefuses = 0;
  int echecs = 0;

  PlanificateurGainsTardifs({
    required Future<ServiceGainsTardifs> Function() fabrique,
    this.intervalle = const Duration(minutes: 5),
    this.distanceMinimale = const Duration(minutes: 2),
    DateTime Function()? horloge,
  })  : _fabrique = fabrique,
        horloge = horloge ?? DateTime.now;

  /// Le service est-il construit ? (diagnostic)
  bool get pret => _service != null;

  /// Un cycle est-il en cours ? (diagnostic)
  bool get enCours => _enCours;

  /// ① OUVERTURE DE L'APPLICATION — construit le service puis lance un cycle,
  /// et arme le minuteur périodique (③).
  ///
  /// Rend `true` si un cycle a réellement été lancé. Rend `false` sans lever
  /// d'exception si la construction a échoué : l'application doit démarrer
  /// normalement même sans rattrapage.
  Future<bool> demarrer() async {
    try {
      _service ??= await _fabrique();
    } catch (e) {
      echecs++;
      debugPrint('PlanificateurGainsTardifs : construction impossible : $e');
      return false;
    }
    _armerMinuteur();
    return lancerCycle();
  }

  /// ③ PÉRIODIQUE — armé une seule fois par [demarrer]. Un second appel ne
  /// crée pas un second minuteur (sinon les cycles se multiplieraient à chaque
  /// retour au premier plan).
  void _armerMinuteur() {
    if (_minuteur != null) return;
    _minuteur = Timer.periodic(intervalle, (_) {
      // Un tic de minuterie est silencieux : personne n'attend son résultat.
      unawaited(lancerCycle());
    });
  }

  /// ② RETOUR AU PREMIER PLAN.
  Future<bool> retourPremierPlan() => lancerCycle();

  /// Tente UN cycle. Les trois déclencheurs passent tous par ici : la
  /// politique de temporisation est donc identique quel que soit l'appelant.
  ///
  /// Rend `true` si un cycle a été exécuté, `false` s'il a été refusé
  /// (service absent, cycle déjà en cours, ou trop tôt après le précédent).
  Future<bool> lancerCycle() async {
    final service = _service;
    if (service == null) {
      demarragesRefuses++;
      return false;
    }
    if (_enCours) {
      demarragesRefuses++;
      return false;
    }
    final maintenant = horloge();
    final dernier = _dernierDemarrage;
    if (dernier != null &&
        maintenant.difference(dernier) < distanceMinimale) {
      demarragesRefuses++;
      return false;
    }

    _enCours = true;
    _dernierDemarrage = maintenant;
    cyclesLances++;
    try {
      await service.executerCycle();
      return true;
    } catch (e) {
      // ⚠️ AUCUNE propagation : un échec de rattrapage ne doit jamais casser
      //    l'écran qui l'a déclenché. Le prochain cycle réessaiera.
      echecs++;
      debugPrint('PlanificateurGainsTardifs : cycle en échec : $e');
      return false;
    } finally {
      _enCours = false;
    }
  }

  /// Arrête le minuteur. Idempotent.
  void arreter() {
    _minuteur?.cancel();
    _minuteur = null;
  }
}
