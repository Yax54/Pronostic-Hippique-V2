// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER 2/3 — MÉMOIRE DURABLE D'IDEMPOTENCE DES GAINS TARDIFS
// ═══════════════════════════════════════════════════════════════════════════
//
//  ★ POURQUOI CE FICHIER N'EST PAS `alert_history_v1`
//
//  L'historique des alertes est TEMPORAIRE et PURGÉ. S'en servir comme unique
//  preuve qu'une notification a déjà été produite rendrait le doublon
//  inévitable dès la première purge — c'est-à-dire précisément ce que le
//  chantier interdit.
//
//  La preuve vit donc dans une clé DÉDIÉE et PERSISTANTE
//  (`gains_tardifs_notifies_v1`), qui survit :
//    • au redémarrage de l'application ;
//    • à l'export / import / restauration ;
//    • à la purge 24 h de `tracked_courses_v1` ;
//    • à la purge de l'historique des alertes ;
//    • à une nouvelle récupération du MÊME rapport officiel.
//
//  ★ TROIS FAMILLES DE MARQUEURS, JAMAIS CONFONDUES
//
//  DÉFAUT MESURÉ AVANT CORRECTION (commit `dcb4b49`, signalé puis corrigé ici) :
//  `ServiceGainsTardifs` utilisait UN SEUL marqueur (`ge1:`) pour deux
//  responsabilités différentes — « écriture faite » ET « ticket traité ». Comme
//  `ticketsARattraper()` écarte tout ticket dont `etatGain != null`, un ticket
//  dont l'écriture avait réussi mais dont la NOTIFICATION avait échoué (ou
//  avait été refusée parce que les notifications étaient désactivées) sortait
//  DÉFINITIVEMENT des candidats. La notification attendue disparaissait pour
//  toujours. C'est le défaut que les préfixes ci-dessous rendent impossible.
//
//    `ge1:<id>`  écriture du résultat officiel CONFIRMÉE sur le disque.
//    `gt1:<id>`  notification de remontée tardive ÉMISE ET CONFIRMÉE.
//    `gd1:<id>`  décision Accepter/Refuser CONFIRMÉE (audit ; la vérité
//                financière reste le champ `decisionGainPmu` du ticket).
//
//  ⚠️ UN SEUL PREFIXE PAR RESPONSABILITÉ. Un marqueur ne peut donc plus
//     servir de preuve pour une autre étape : « écriture faite » n'implique
//     jamais « notification faite », et inversement.
//
//  ⚠️ CETTE CLÉ N'EST **PAS** UNE DONNÉE FINANCIÈRE. Elle ne porte aucun
//     montant et aucun verdict. La perdre ne fausserait aucun calcul — elle ne
//     provoquerait qu'un doublon visuel ou une reprise. C'est pourquoi une
//     lecture illisible rend une carte VIDE plutôt qu'une exception : une
//     donnée de confort corrompue ne doit pas bloquer l'application,
//     contrairement à une donnée financière.
//
//  ⚠️ ELLE N'EST PAS NON PLUS LA SOURCE DE VÉRITÉ DES DÉCISIONS EN ATTENTE.
//     Une décision en attente se déduit du TICKET PERSISTÉ
//     (`montantOfficielPmu != null && decisionGainPmu == null`), donc elle
//     survit à la perte de cette clé. Le marqueur `gd1:` n'est qu'un témoin
//     d'audit : sa disparition ne rouvre jamais une décision déjà tranchée.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Clé `SharedPreferences` de la mémoire d'idempotence.
///
/// ⚠️ Elle est déclarée ICI et NULLE PART AILLEURS. Deux déclarations d'une
///    même clé rendraient possible une divergence silencieuse entre deux
///    écritures — le défaut classique qui produit des doublons.
const String kClePrefsGainsTardifsNotifies = 'gains_tardifs_notifies_v1';

/// Mémoire durable : quels tickets ont DÉJÀ franchi quelle étape, et quand.
class MemoireGainsTardifsNotifies {
  static const String clePrefs = kClePrefsGainsTardifsNotifies;

  final SharedPreferences _prefs;

  MemoireGainsTardifsNotifies(this._prefs);

  static Future<MemoireGainsTardifsNotifies> ouvrir() async =>
      MemoireGainsTardifsNotifies(await SharedPreferences.getInstance());

  /// Une clé d'idempotence a-t-elle déjà été posée ?
  ///
  /// ⚠️ La clé testée est TOUJOURS une clé construite par
  ///    `cleIdempotenceEcriture` / `cleIdempotenceNotification` /
  ///    `cleIdempotenceDecision` — jamais l'identifiant brut. Les trois
  ///    familles ne peuvent donc pas se confondre.
  bool dejaMarque(String cleIdempotence) =>
      lireTout().containsKey(cleIdempotence);

  /// Compatibilité ascendante : ancien nom, même sémantique.
  bool dejaNotifie(String cleIdempotence) => dejaMarque(cleIdempotence);

  /// Tous les marqueurs connus : clé d'idempotence → horodatage ISO-8601.
  Map<String, String> lireTout() {
    final brut = _prefs.getString(clePrefs);
    if (brut == null || brut.isEmpty) return <String, String>{};
    try {
      final decode = jsonDecode(brut);
      if (decode is! Map) return <String, String>{};
      final out = <String, String>{};
      decode.forEach((k, v) {
        if (k is! String) return;
        // La valeur est un horodatage d'audit ; une valeur d'un autre type est
        // ignorée plutôt que convertie : on ne fabrique pas une date.
        if (v is String) out[k] = v;
      });
      return out;
    } catch (_) {
      return <String, String>{};
    }
  }

  /// Marque UNE clé comme franchie. Rend `true` seulement si l'écriture a été
  /// acceptée par le support ET relue.
  ///
  /// ⚠️ LE RÉSULTAT EST RENDU, JAMAIS IGNORÉ. Un appelant qui marquerait sans
  ///    vérifier pourrait croire à une idempotence qui n'est pas persistée, et
  ///    produire un doublon au prochain cycle. Le marqueur n'est donc posé en
  ///    mémoire qu'APRÈS confirmation du support.
  Future<bool> marquer(String cleIdempotence, {DateTime? quand}) async {
    var tout = lireTout();
    // Réécriture de la MÊME clé : on rafraîchit l'horodatage sans créer
    // d'entrée supplémentaire (aucune accumulation illimitée par ticket).
    tout[cleIdempotence] = (quand ?? DateTime.now()).toIso8601String();
    try {
      final encode = <String, dynamic>{...tout};
      final ok = await _prefs.setString(clePrefs, jsonEncode(encode));
      if (!ok) return false;
      // Confirmation par RELECTURE : le cache mémoire du support peut différer
      // du stockage réel, exactement comme pour les écritures financières.
      await _prefs.reload();
      return lireTout().containsKey(cleIdempotence);
    } catch (_) {
      return false;
    }
  }

  /// Efface UN marqueur. N'est utilisé que pour annuler un marqueur dont la
  /// contrepartie n'a pas eu lieu — jamais pour « réessayer au hasard ».
  Future<bool> effacer(String cleIdempotence) async {
    final tout = lireTout();
    if (!tout.containsKey(cleIdempotence)) return true;
    tout.remove(cleIdempotence);
    try {
      final ok =
          await _prefs.setString(clePrefs, jsonEncode(<String, dynamic>{...tout}));
      if (!ok) return false;
      await _prefs.reload();
      return !lireTout().containsKey(cleIdempotence);
    } catch (_) {
      return false;
    }
  }
}
