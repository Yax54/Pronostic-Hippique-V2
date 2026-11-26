// ═══════════════════════════════════════════════════════════════════════════
//  POINT DE PASSAGE UNIQUE POUR L'ACQUISITION PMU
//
//  ═══════════════════════════════════════════════════════════════════════════
//  POURQUOI CETTE COUCHE EXISTE — DISPERSION MESURÉE AVANT SA CRÉATION
//
//  L'acquisition des données PMU était répartie sur SIX fichiers distincts,
//  chacun construisant son URL, son délai et son traitement d'erreur :
//
//    lib/services/zone_turf_service.dart      programme + participants + perfdet
//    lib/services/data_refresh_service.dart   rapports-definitifs (arrivées)
//    lib/services/ia_memory_service.dart      ×3 (résultats, rapports)
//    lib/services/alert_service.dart          rapports (alertes)
//    lib/services/cote_tracker_service.dart   cotes
//    lib/services/pmu_api_service.dart        base URL dupliquée
//
//  Conséquence mesurée : les quatre situations d'échec (absence de course,
//  panne réseau, réponse invalide, erreur serveur) n'étaient distinguées
//  NULLE PART — chaque site rendait `null`, `[]` ou levait une exception selon
//  son propre code, sans nom commun. C'est ce qui a rendu possible le défaut
//  M4-a (une panne réseau présentée comme une actualisation réussie).
//
//  ⚠️ CE QUE CETTE COUCHE EST
//     Un point de passage UNIQUE qui répond à trois questions et à elles
//     seules : quelle URL, quel délai, et QUELLE EST LA NATURE de ce qui est
//     revenu. Il ne connaît aucun modèle métier, aucun score, aucun critère,
//     et n'écrit rien.
//
//  ⚠️ CE QUE CETTE COUCHE N'EST PAS
//     • ce n'est PAS un troisième système d'acquisition : c'est le seul, et les
//       services existants y délèguent leur transport ;
//     • elle ne remplace NI `ZoneTurfService` (interprétation et validation des
//       données PMU) NI `DataRefreshService` (orchestration, détection des
//       changements utiles, déclenchement des traitements) ;
//     • elle n'ajoute aucun cache : la mutualisation et les TTL restent là où
//       ils sont déjà, avec leurs clés et leurs durées existantes.
//
//  ⚠️ AUCUNE FORMULE, AUCUN POIDS, AUCUN SEUIL N'EST CONCERNÉ ICI.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Nature d'une réponse d'acquisition, quel que soit l'endpoint.
///
/// ⚠️ CES SEPT VALEURS SONT DISTINCTES PARCE QUE L'ACTION ATTENDUE DIFFÈRE :
///    • [succes]            → exploiter la charge ;
///    • [aucuneDonnee]      → la source a répondu « rien » : ne pas réessayer
///                            agressivement, ce n'est pas une panne ;
///    • [reseauIndisponible]→ réessayer plus tard, cause extérieure ;
///    • [delaiDepasse]      → réessayer, mais la cause est la lenteur ;
///    • [reponseInvalide]   → la source est joignable, son contenu ne l'est pas ;
///    • [erreurServeur]     → la source est en défaut ;
///    • [nonConfigure]      → l'appel est refusé AVANT tout réseau.
enum NatureReponse {
  succes,
  aucuneDonnee,
  reseauIndisponible,
  delaiDepasse,
  reponseInvalide,
  erreurServeur,
  nonConfigure,
}

/// Réponse d'acquisition : la nature, la charge éventuelle, et le détail.
///
/// [details] est destiné au diagnostic et aux messages utilisateur ; il n'est
/// jamais interprété par une règle métier.
class ReponsePmu {
  const ReponsePmu({
    required this.nature,
    this.charge,
    this.statutHttp,
    this.details,
    this.uri,
  });

  final NatureReponse nature;

  /// Charge JSON décodée si [nature] vaut [NatureReponse.succes] ET que le
  /// corps était du JSON. `null` sinon — jamais une valeur inventée.
  final Object? charge;

  final int? statutHttp;
  final String? details;
  final Uri? uri;

  bool get estSucces => nature == NatureReponse.succes;

  /// Vrai si l'échec est susceptible de réussir en réessayant plus tard.
  ///
  /// ⚠️ [NatureReponse.aucuneDonnee] et [NatureReponse.nonConfigure] n'en sont
  ///    PAS : réessayer ne changerait rien à une journée sans course, et un
  ///    appel non configuré est un défaut de code, pas une condition.
  bool get estReessayable =>
      nature == NatureReponse.reseauIndisponible ||
      nature == NatureReponse.delaiDepasse ||
      nature == NatureReponse.reponseInvalide ||
      nature == NatureReponse.erreurServeur;

  @override
  String toString() =>
      'ReponsePmu(${nature.name}${statutHttp != null ? ", HTTP $statutHttp" : ""}'
      '${details != null ? ", $details" : ""})';
}

/// Point de passage unique de l'acquisition PMU.
///
/// Volontairement SANS état : aucune table, aucun cache, aucun compteur. L'état
/// appartient aux services qui orchestrent, pas au transport. C'est ce qui
/// garantit qu'ajouter cette couche ne crée pas un second magasin (§4).
class AcquisitionPmu {
  AcquisitionPmu._();

  /// Base de l'API PMU officielle (v7), seule autorité d'URL.
  static const String base = 'https://turfinfo.api.pmu.fr/rest/client/7';

  /// Spécialisation attendue par l'API pour les réponses complètes.
  static const String specialisation = 'INTERNET';

  /// Délai par défaut, aligné sur le comportement historique de
  /// `ZoneTurfService` pour ne modifier aucune temporisation existante.
  static const Duration delaiDefaut = Duration(seconds: 20);

  /// En-têtes envoyés à l'API.
  static Map<String, String> get entetes => const <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  /// Construit l'URL d'un chemin (`programme/01012026/R1/C1/participants`).
  ///
  /// ⚠️ [specialisation] n'est ajoutée que si le chemin ne la porte pas déjà :
  ///    les appelants historiques ne sont donc pas obligés de la connaître, et
  ///    aucun ne peut la dupliquer par accident.
  static Uri uri(String chemin, {bool avecSpecialisation = true}) {
    var c = chemin.startsWith('/') ? chemin.substring(1) : chemin;
    if (avecSpecialisation &&
        !c.contains('specialisation=')) {
      c = '$c${c.contains('?') ? '&' : '?'}specialisation=$specialisation';
    }
    return Uri.parse('$base/$c');
  }

  /// Exécute une acquisition GET et en qualifie la NATURE.
  ///
  /// ⚠️ CETTE MÉTHODE NE LANCE JAMAIS D'EXCEPTION. Toute cause d'échec est
  ///    traduite en [NatureReponse] : c'est la condition pour qu'un appelant
  ///    puisse décider sans deviner, et pour qu'aucun `catch` local n'ait à
  ///    réinterpréter une cause qu'il ne connaît pas.
  static Future<ReponsePmu> get(
    String chemin, {
    Duration? delai,
    Map<String, String>? entetesSupplementaires,
    http.Client? client,
  }) async {
    final Uri cible;
    try {
      cible = uri(chemin);
    } catch (e) {
      return ReponsePmu(
        nature: NatureReponse.nonConfigure,
        details: 'URL inexploitable pour « $chemin » : $e',
      );
    }

    final entetesFinaux = <String, String>{...entetes};
    if (entetesSupplementaires != null) {
      entetesFinaux.addAll(entetesSupplementaires);
    }

    final http.Response reponse;
    try {
      final futur = (client ?? http.Client())
          .get(cible, headers: entetesFinaux);
      reponse = await futur.timeout(delai ?? delaiDefaut);
    } on TimeoutException catch (e) {
      return ReponsePmu(
        nature: NatureReponse.delaiDepasse,
        uri: cible,
        details: 'Délai dépassé sur ${cible.path} : $e',
      );
    } catch (e) {
      // Toute autre exception de transport (DNS, socket, TLS) signifie
      // qu'AUCUNE réponse n'a été obtenue. Ce n'est pas un contenu invalide.
      return ReponsePmu(
        nature: NatureReponse.reseauIndisponible,
        uri: cible,
        details: 'Aucune réponse de ${cible.host} : $e',
      );
    }

    if (reponse.statusCode != 200) {
      return ReponsePmu(
        nature: NatureReponse.erreurServeur,
        statutHttp: reponse.statusCode,
        uri: cible,
        details: 'HTTP ${reponse.statusCode} sur ${cible.path}',
      );
    }

    // Corps vide : la source a répondu, mais sans contenu. Ce n'est ni un JSON
    // invalide ni une absence de données métier : on le dit tel quel.
    if (reponse.body.trim().isEmpty) {
      return ReponsePmu(
        nature: NatureReponse.aucuneDonnee,
        statutHttp: reponse.statusCode,
        uri: cible,
        details: 'Corps vide sur ${cible.path}',
      );
    }

    final Object? decode;
    try {
      decode = jsonDecode(reponse.body);
    } catch (e) {
      return ReponsePmu(
        nature: NatureReponse.reponseInvalide,
        statutHttp: reponse.statusCode,
        uri: cible,
        details: 'Corps non-JSON sur ${cible.path} : $e',
      );
    }

    // Une liste vide est une ABSENCE DE DONNÉES, pas un succès porteur
    // d'information. La distinction compte : `rapports-definitifs` rend `[]`
    // quand la course n'a pas encore d'arrivée — le traitement doit s'arrêter
    // sans rien enregistrer, non « traiter une liste vide ».
    if (decode is List && decode.isEmpty) {
      return ReponsePmu(
        nature: NatureReponse.aucuneDonnee,
        charge: decode,
        statutHttp: reponse.statusCode,
        uri: cible,
        details: 'Liste vide sur ${cible.path}',
      );
    }

    return ReponsePmu(
      nature: NatureReponse.succes,
      charge: decode,
      statutHttp: reponse.statusCode,
      uri: cible,
    );
  }
}
