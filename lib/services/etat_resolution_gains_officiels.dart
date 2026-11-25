// ═══════════════════════════════════════════════════════════════════════════
//  BLOC 1 — ÉTAT DE LA RÉSOLUTION OFFICIELLE DES GAINS (Best Bet)
//
//  POURQUOI CE FICHIER EXISTE
//  --------------------------
//  L'écran Best Bet ne doit pas figer définitivement un gain laissé
//  « non déterminé » par un incident de source, MAIS il ne doit pas non plus
//  marteler le réseau indéfiniment. Ces deux exigences se contredisent si la
//  décision reste noyée dans un `setState` au milieu d'un `finally`.
//
//  Elles sont donc sorties ici sous forme d'une décision PURE, sans `await`,
//  sans `BuildContext`, sans stockage : on peut l'énumérer exhaustivement en
//  test et prouver qu'aucun chemin ne fige un indéterminé ni ne boucle.
//
//  DÉFAUT MESURÉ QUE CETTE CLASSE CORRIGE
//  --------------------------------------
//  Avant, `_resolutionOfficielleTerminee` était posé à `true` dans le
//  `finally` de `_resoudreGainsOfficiels`, donc AUSSI en cas d'exception ou de
//  source muette. La garde du `build` étant
//      `if (!_resolutionOfficielleTerminee && !_resolutionOfficielleLancee)`
//  un seul incident au premier rendu supprimait toute tentative ultérieure :
//  les gains restaient indéterminés jusqu'au redémarrage de l'application, et
//  la fonction de rafraîchissement prévue pour rattraper cela n'avait aucun
//  appelant.
//
//  La correction naïve (« ne plus poser le verrou sur un échec ») introduit un
//  second défaut, tout aussi mesurable : le `setState` du `finally` provoque un
//  `build`, qui relance une passe, qui échoue, qui provoque un `build`… soit
//  une boucle réseau sans fin. D'où le plafond ci-dessous.
//
//  CE QUE CE FICHIER NE FAIT PAS
//  -----------------------------
//  Il ne touche à AUCUNE règle métier protégée : ni critère, ni coefficient,
//  ni seuil, ni règle financière, ni apprentissage. Il décide seulement quand
//  l'écran a le droit de redemander une résolution officielle.
// ═══════════════════════════════════════════════════════════════════════════

/// Nombre maximal de passes AUTOMATIQUES tentées sans succès complet.
///
/// Trois passes : de quoi absorber un démarrage à froid (première requête
/// réseau), une absence temporaire de rapports, puis la fenêtre de
/// rectification des drapeaux « définitif ». Au-delà, l'automatisme s'arrête et
/// seule une action EXPLICITE de l'utilisateur relance — la résolution n'est
/// jamais fermée, elle cesse simplement d'être spontanée.
const int kMaxTentativesResolutionAuto = 3;

/// Décision « le verrou de résolution officielle doit-il être posé ? ».
///
/// Immuable : chaque passe produit un NOUVEL état, ce qui interdit une mise à
/// jour partielle oubliée (le défaut le plus fréquent sur un état de vue
/// manipulé par `setState`).
class EtatResolutionGainsOfficiels {
  const EtatResolutionGainsOfficiels({this.tentativesAuto = 0});

  /// Passes automatiques déjà consommées SANS succès complet.
  final int tentativesAuto;

  /// État initial : rien n'a encore été tenté, la résolution est ouverte.
  static const EtatResolutionGainsOfficiels initial =
      EtatResolutionGainsOfficiels();

  /// Vrai quand l'écran ne doit plus relancer spontanément la résolution.
  ///
  /// Deux causes distinctes, volontairement fusionnées dans cette seule
  /// propriété parce que leur SEUL effet est identique (ne pas relancer seul) :
  ///   • le succès complet — il n'y a plus rien à demander ;
  ///   • le plafond atteint — la source ne répond manifestement pas.
  bool get verrouille => tentativesAuto >= kMaxTentativesResolutionAuto;

  /// Vrai quand il reste un gain à établir ET qu'une passe automatique est
  /// encore autorisée. C'est la seule condition qui déclenche du réseau sans
  /// intention explicite de l'utilisateur.
  bool get doitRelancerAutomatiquement => !verrouille;

  /// Applique le résultat d'UNE passe.
  ///
  /// [passeComplete] : la boucle est allée au bout sans exception.
  /// [resteIndetermine] : au moins un gain terminé n'a pas de sort établi.
  ///
  /// Un succès complet REMET le compteur à zéro : après une reprise réussie,
  /// un futur incident doit de nouveau disposer de ses trois passes, sinon un
  /// seul échec en fin de session suffirait à désarmer l'écran pour de bon.
  EtatResolutionGainsOfficiels apresPasse({
    required bool passeComplete,
    required bool resteIndetermine,
  }) {
    final succesComplet = passeComplete && !resteIndetermine;
    if (succesComplet) {
      return const EtatResolutionGainsOfficiels(tentativesAuto: 0);
    }
    // Un échec ne fait JAMAIS reculer le compteur, et ne le fait progresser
    // qu'une fois : deux appels concurrents ou un rejeu ne consomment pas
    // deux passes.
    if (tentativesAuto >= kMaxTentativesResolutionAuto) {
      return EtatResolutionGainsOfficiels(tentativesAuto: tentativesAuto);
    }
    return EtatResolutionGainsOfficiels(tentativesAuto: tentativesAuto + 1);
  }

  /// Résultat d'un rafraîchissement MANUEL.
  ///
  /// Action explicite : elle ignore le plafond (sinon le bouton « Réessayer »
  /// deviendrait inopérant dès le troisième échec, ce qui reviendrait au gel
  /// définitif que la correction supprime). Elle ne modifie pas le compteur
  /// automatique : réarmer la reprise spontanée après un clic serait un
  /// comportement non voulu par l'utilisateur.
  EtatResolutionGainsOfficiels apresRafraichissementManuel() => this;

  @override
  String toString() => 'EtatResolutionGainsOfficiels(tentativesAuto: '
      '$tentativesAuto, verrouille: $verrouille)';
}
