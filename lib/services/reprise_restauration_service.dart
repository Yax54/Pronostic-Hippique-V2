/// Reprise d'une restauration interrompue, exécutée au démarrage.
///
/// Consigne §1 du présent tour :
/// > « Le journal d'intention doit permettre une reprise sécurisée au prochain
/// > démarrage. »
///
/// Un mécanisme de reprise qui n'est jamais appelé ne protège rien. Ce service
/// est donc branché dans `main()` **après** l'ouverture du dépôt structuré
/// (faite par `EloService.init()`), et **avant** que l'interface n'affiche des
/// données.
///
/// Ce qu'il fait, et ne fait pas :
///
/// * il ne décide rien : la décision appartient à `Restaurateur.reprendre()`,
///   seule logique métier de restauration ;
/// * il **n'échoue jamais de façon bloquante** : une reprise impossible ne doit
///   pas empêcher l'application de démarrer — elle doit être visible dans le
///   journal et dans l'état retourné ;
/// * il ne déclenche **aucun apprentissage** : il rétablit ou conserve des
///   données, il ne les recalcule pas.
library;

import 'package:flutter/foundation.dart';

import '../data/connaissances/_adapters/pont_elo.dart';
import '../data/connaissances/_sauvegarde/restaurateur.dart';

/// Résultat de la reprise au démarrage, pour l'interface et le journal.
class BilanRepriseDemarrage {
  const BilanRepriseDemarrage({
    required this.executee,
    this.resultat,
    this.erreur,
  });

  /// `true` si une reprise a réellement eu lieu.
  final bool executee;

  /// Détail de ce qui a été fait, quand il y a eu quelque chose à faire.
  final ResultatReprise? resultat;

  /// Renseigné si la reprise elle-même n'a pas pu être tentée.
  final String? erreur;

  /// Message destiné à l'utilisateur, ou `null` si rien ne s'est produit.
  ///
  /// On ne l'affiche que si quelque chose de réel s'est passé : signaler une
  /// reprise qui n'a pas eu lieu serait du bruit inquiétant.
  String? get messageUtilisateur {
    final r = resultat;
    if (r == null) return null;
    switch (r.action) {
      case ResultatReprise.actionAnnulee:
        return 'Une restauration interrompue a été annulée : vos données '
            'antérieures ont été rétablies.';
      case ResultatReprise.actionControlesRejoues:
        return 'Une restauration interrompue a été finalisée : les données '
            'restaurées ont été conservées.';
      case ResultatReprise.actionIrrecuperable:
        return 'Une restauration interrompue n\'a pas pu être analysée. '
            'Aucune donnée n\'a été supprimée. Détail dans le journal.';
      default:
        return null;
    }
  }
}

/// Point d'entrée unique de la reprise au démarrage.
class RepriseRestaurationService {
  RepriseRestaurationService._();

  static final RepriseRestaurationService instance =
      RepriseRestaurationService._();

  BilanRepriseDemarrage? _dernier;
  BilanRepriseDemarrage? get dernier => _dernier;

  /// Exécute la reprise. À appeler une seule fois, au démarrage.
  ///
  /// Ne lève jamais : une reprise impossible est un état à constater, pas une
  /// raison de priver l'utilisateur de son application.
  Future<BilanRepriseDemarrage> executerAuDemarrage() async {
    final depot = PontElo.instance.depotPourSauvegarde;
    final racine = PontElo.instance.racine;
    if (depot == null || racine.isEmpty) {
      // Sans dépôt ouvert, il n'y a rien à reprendre : la méta de reprise vit
      // dans le dépôt. Ce n'est pas une erreur, c'est un cas normal.
      final bilan = const BilanRepriseDemarrage(
        executee: false,
        erreur: 'dépôt structuré non ouvert',
      );
      _dernier = bilan;
      return bilan;
    }

    try {
      final resultat = await const Restaurateur().reprendre(
        depot: depot,
        dossierTemp: '$racine/temp',
        dossierBase: racine,
        versionLocale: _versionApplication,
      );
      final bilan = BilanRepriseDemarrage(
        executee: resultat != null && !resultat.rienAFaire,
        resultat: resultat,
      );
      _dernier = bilan;
      if (kDebugMode && bilan.executee) {
        debugPrint('[Reprise] ${resultat!.action} — ${resultat.detail}');
      }
      return bilan;
    } catch (e) {
      if (kDebugMode) debugPrint('[Reprise] ÉCHEC de la reprise : $e');
      final bilan = BilanRepriseDemarrage(
        executee: false,
        erreur: '$e',
      );
      _dernier = bilan;
      return bilan;
    }
  }

  /// Version applicative, utilisée dans le manifeste des instantanés.
  ///
  /// Volontairement constante plutôt que lue depuis le `pubspec` : lire le
  /// `pubspec` à l'exécution demanderait un asset supplémentaire, pour une
  /// information qui ne sert ici qu'à identifier l'auteur d'un instantané.
  static const String _versionApplication = '9.94';
}
