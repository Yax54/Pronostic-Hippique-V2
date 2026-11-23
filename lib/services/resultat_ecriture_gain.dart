// ═══════════════════════════════════════════════════════════════════════════
//  B1-T12 / LOT 2-C — ISSUE RÉELLE D'UNE ÉCRITURE DE GAIN DÉCLARÉ
// ═══════════════════════════════════════════════════════════════════════════
//
//  Un booléen confondait quatre situations très différentes. `true` ne veut
//  plus dire « à peu près enregistré » : chaque état nomme EXACTEMENT ce qui
//  a été écrit, et surtout ce qui ne l'a pas été.
//
//  ⚠️ NOM DISTINCT VOLONTAIREMENT : `ResultatEcriture` existe DÉJÀ deux fois
//     dans ce dépôt (`ia_memory_service.dart` et `arrivee_officielle_service
//     .dart`). On n'ajoute donc pas une troisième homonymie.
// ═══════════════════════════════════════════════════════════════════════════

/// Issue d'une écriture de gain déclaré par l'utilisateur.
enum ResultatEcritureGain {
  /// ① Gain écrit DURABLEMENT **et** suivi temporaire écrit.
  complet,

  /// ② Gain écrit DURABLEMENT, suivi temporaire non écrit. Aucune perte
  ///    financière : la purge de 24 h ne supprimera rien d'essentiel, mais
  ///    la limite est dite à l'utilisateur.
  durableSeul,

  /// ③ Ticket NON LIÉ à un `UserPrediction` : aucune écriture durable n'est
  ///    possible. La saisie est ACCEPTÉE et écrite dans le suivi, mais sa
  ///    conservation s'arrête à la purge. La limite est EXPLIQUÉE.
  nonLie,

  /// ④ Écriture refusée par le disque. RIEN n'est annoncé comme enregistré.
  echecFinancier,

  /// ⑤ Clé de suivi inconnue : aucun ticket, rien n'est créé.
  ticketIntrouvable,

  /// ⑥ La valeur demandée a été REMPLACÉE par une opération plus récente.
  ///    Elle n'est donc PAS enregistrée : on ne l'annonce jamais comme telle.
  remplaceeParPlusRecente,

  /// ⑦ Échec dont la réconciliation a échoué : la cohérence mémoire/disque
  ///    n'est PAS prouvée. On ne l'affirme jamais.
  echecNonReconcilie,
}
