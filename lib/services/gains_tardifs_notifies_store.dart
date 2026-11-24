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
//  ⚠️ CETTE CLÉ N'EST **PAS** UNE DONNÉE FINANCIÈRE. Elle ne porte aucun
//     montant, aucune décision, aucun verdict. Elle dit seulement « une
//     remontée tardive a déjà été signalée pour CE ticket ». La perdre ne
//     fausse donc aucun calcul : elle ne provoquerait qu'un doublon visuel.
//     C'est pourquoi une lecture illisible rend une carte VIDE plutôt qu'une
//     exception : une donnée de confort corrompue ne doit pas bloquer
//     l'application, contrairement à une donnée financière.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Clé `SharedPreferences` de la mémoire d'idempotence.
///
/// ⚠️ Elle est déclarée ICI et NULLE PART AILLEURS. Deux déclarations d'une
///    même clé rendraient possible une divergence silencieuse entre deux
///    écritures — le défaut classique qui produit des doublons.
const String kClePrefsGainsTardifsNotifies = 'gains_tardifs_notifies_v1';

/// Mémoire durable : quels tickets ont DÉJÀ été notifiés, et quand.
class MemoireGainsTardifsNotifies {
  static const String clePrefs = kClePrefsGainsTardifsNotifies;

  final SharedPreferences _prefs;

  MemoireGainsTardifsNotifies(this._prefs);

  static Future<MemoireGainsTardifsNotifies> ouvrir() async =>
      MemoireGainsTardifsNotifies(await SharedPreferences.getInstance());

  /// Une notification a-t-elle déjà été produite pour ce ticket ?
  ///
  /// ⚠️ La clé testée est la CLÉ D'IDEMPOTENCE construite par
  ///    `cleIdempotenceNotification` — jamais l'identifiant brut. Cela isole
  ///    les trois familles de marqueurs (`gt1:` notification, `ge1:` écriture)
  ///    dans un même conteneur sans qu'elles puissent se confondre.
  bool dejaNotifie(String cleIdempotence) => lireTout().containsKey(cleIdempotence);

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

  /// Marque une clé comme traitée. Rend `true` seulement si l'écriture a été
  /// acceptée par le support.
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
}
