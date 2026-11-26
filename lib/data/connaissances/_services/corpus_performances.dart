/// Corpus local des performances authentiques : écriture et lecture.
///
/// Consigne §3 du présent tour :
/// > « Ne te limite pas à lire le code ou à créer de nouvelles classes isolées.
/// > Réalise le raccordement fonctionnel complet. »
///
/// ═══════════════════════════════════════════════════════════════════════════
///  LE DÉFAUT QUE CE SERVICE CORRIGE
///
///  Avant ce fichier, `_chargerPerformancesDetaillees` appelait le PMU à chaque
///  course, et **rien** n'était conservé : la table `performances` existait dans
///  le schéma depuis le début, mais n'était ni écrite ni lue par aucun code de
///  production. Conséquences mesurables :
///
///  * la même course était retéléchargée indéfiniment (le cache mémoire a un
///    TTL de quelques minutes, il ne survit pas à un redémarrage) ;
///  * hors ligne, les 19 critères perdaient toute alimentation historique ;
///  * une connaissance payée une fois n'était jamais réutilisée.
///
///  Ce service fait deux choses, et rien d'autre :
///
///  * **écrire** ce que le PMU a publié, sans interprétation (`enregistrer`) ;
///  * **lire** ce qui est déjà connu avant d'appeler le réseau (`charger`).
///
///  Il ne calcule aucun critère, ne modifie aucune formule, ne fusionne aucune
///  entité. C'est un magasin, pas un moteur.
///  ═══════════════════════════════════════════════════════════════════════════
library;

import 'package:flutter/foundation.dart';

import '../_adapters/depot_sqlite.dart';
import '../_adapters/pont_elo.dart';
import '../_core/depot.dart';
import '../_core/identifiants.dart';

/// Une course passée telle que le corpus la restitue.
///
/// Volontairement minimale et **sans interprétation** : la place et la distance
/// sont nullables, parce que « le PMU ne l'a pas publié » n'est pas la même
/// information que « 0 ».
class PerformanceLocale {
  const PerformanceLocale({
    required this.datePerf,
    required this.hippodrome,
    required this.discipline,
    this.distanceMetres,
    this.etatTerrain = '',
    this.place,
    this.reductionKm,
    this.gainsMemeCourse,
  });

  /// Date ISO-8601 (`AAAA-MM-JJ`), ou `null` si illisible.
  final String? datePerf;
  final String hippodrome;
  final String discipline;

  /// Distance en mètres, `null` si non publiée.
  final int? distanceMetres;

  /// État du terrain publié, chaîne vide si absent. Ce n'est pas la surface.
  final String etatTerrain;

  /// Place réelle, `null` si non publiée. **Jamais 0 par défaut.**
  final int? place;

  final double? reductionKm;
  final double? gainsMemeCourse;

  bool get estDisputee => datePerf != null && datePerf!.isNotEmpty;
}

/// Écriture et lecture du corpus local de performances.
///
/// Toutes les méthodes **absorbent leurs erreurs** : l'absence de corpus local
/// ne doit jamais faire échouer l'analyse d'une course. Un dépôt indisponible
/// ramène `null` / liste vide, et l'appelant retombe sur le chemin réseau — ce
/// qui est le comportement d'avant, donc jamais une régression.
class CorpusPerformancesService {
  CorpusPerformancesService._();

  static final CorpusPerformancesService instance =
      CorpusPerformancesService._();

  DepotSqlite? get _depot => PontElo.instance.depotPourSauvegarde;

  /// Nombre de performances connues localement.
  Future<int> compter() async {
    final d = _depot;
    if (d == null) return 0;
    try {
      return await d.compterPerformances();
    } catch (e) {
      if (kDebugMode) debugPrint('[CorpusPerf] comptage impossible : $e');
      return 0;
    }
  }

  /// Enregistre ce qu'une réponse PMU a publié pour une course.
  ///
  /// [reponses] associe le numéro PMU du cheval à son historique décodé. Le
  /// décodage reste la responsabilité de l'appelant, qui possède déjà la
  /// logique de lecture du JSON PMU ; ici, on ne fait que persister.
  ///
  /// Retourne le nombre de lignes réellement créées. Un rejeu de la même
  /// course retourne 0, ce qui est le comportement correct : rien de nouveau.
  Future<int> enregistrer({
    required String dateStr,
    required int numR,
    required int numC,
    required Map<String, List<PerformancePmu>> parNumero,
    required String source,
  }) async {
    final d = _depot;
    if (d == null) return 0;
    if (parNumero.isEmpty) return 0;

    final dateCourse = _dateIso(dateStr);
    final aEcrire = <PerformanceStockee>[];

    parNumero.forEach((numPmu, courses) {
      for (final c in courses) {
        if (!c.estExploitable) continue;
        // Identité : on ne la DEVINE pas (§7). Le nom brut est conservé, et
        // `idCheval` reste null tant qu'une résolution n'a pas eu lieu. Un
        // identifiant synthétique stable est dérivé du nom + discipline, ce qui
        // permet de retrouver les lignes d'un même cheval sans prétendre que
        // deux graphies sont le même animal.
        final idCheval = identifiantPerformanceCheval(
          nomBrut: c.nomCheval,
          discipline: c.discipline,
        );
        aEcrire.add(PerformanceStockee(
          id: clePerformance(
            idCheval: idCheval,
            datePerf: c.dateIso,
            hippodrome: c.hippodrome,
            source: source,
          ),
          idCheval: idCheval,
          nomChevalBrut: c.nomCheval,
          discipline: c.discipline.isEmpty ? null : c.discipline,
          datePerf: c.dateIso,
          hippodrome: c.hippodrome.isEmpty ? null : c.hippodrome,
          place: c.place,
          reductionKm: c.reductionKm,
          gains: c.gains,
          // Distance et état du terrain : null si le PMU ne les publie pas.
          // On ne substitue JAMAIS 0 ni une chaîne vide signifiante (§9).
          distanceMetres: (c.distance ?? 0) > 0 ? c.distance : null,
          etatTerrain: c.etatTerrain.trim().isEmpty ? null : c.etatTerrain,
          source: source,
          chargeBrute: c.chargeBrute,
        ));
      }
    });

    if (aEcrire.isEmpty) return 0;

    try {
      final crees = await d.insererPerformancesEnLot(aEcrire);
      if (kDebugMode && crees > 0) {
        debugPrint('[CorpusPerf] +$crees performance(s) pour '
            '${dateCourse ?? dateStr} R${numR}C$numC (source $source)');
      }
      return crees;
    } catch (e) {
      // Une écriture en échec ne doit pas casser l'analyse en cours.
      if (kDebugMode) debugPrint('[CorpusPerf] écriture impossible : $e');
      return 0;
    }
  }

  /// Lit les performances locales d'un cheval, de la plus récente à la plus
  /// ancienne.
  ///
  /// [nomBrut] est utilisé quand aucun identifiant stable n'est connu : c'est
  /// le cas le plus fréquent, et c'est précisément pourquoi la lecture par nom
  /// existe. Elle ne prétend pas résoudre l'identité, elle restitue ce qui a
  /// été stocké sous ce nom.
  Future<List<PerformanceLocale>> charger({
    String? idCheval,
    String? nomBrut,
    int limite = 12,
  }) async {
    final d = _depot;
    if (d == null) return const <PerformanceLocale>[];
    try {
      final lignes = idCheval != null && idCheval.isNotEmpty
          ? await d.performancesDuCheval(idCheval, limite: limite)
          : nomBrut != null && nomBrut.isNotEmpty
              ? await d.performancesParNom(nomBrut, limite: limite)
              : const <PerformanceStockee>[];
      if (lignes.isEmpty) return const <PerformanceLocale>[];

      return <PerformanceLocale>[
        for (final p in lignes)
          PerformanceLocale(
            datePerf: p.datePerf,
            hippodrome: p.hippodrome ?? '',
            discipline: p.discipline ?? '',
            distanceMetres: p.distanceMetres,
            etatTerrain: p.etatTerrain ?? '',
            place: p.place,
            reductionKm: p.reductionKm,
            gainsMemeCourse: p.gains,
          ),
      ];
    } catch (e) {
      if (kDebugMode) debugPrint('[CorpusPerf] lecture impossible : $e');
      return const <PerformanceLocale>[];
    }
  }

  /// Le corpus est-il suffisant pour alimenter un critère ?
  ///
  /// Distinct de « non vide » : un critère « musique sur 5 courses » ne peut
  /// pas être calculé avec 2 lignes. Cette méthode rend la distinction
  /// explicite plutôt que de laisser chaque critère la réinventer — c'est
  /// l'exigence §9 de distinguer absent / insuffisant / réellement calculé.
  Future<bool> estSuffisant({
    String? idCheval,
    String? nomBrut,
    required int minimum,
  }) async {
    final lignes = await charger(
      idCheval: idCheval,
      nomBrut: nomBrut,
      limite: minimum,
    );
    return lignes.where((p) => p.estDisputee).length >= minimum;
  }
}

/// Une course passée telle que le décodeur PMU l'a extraite.
///
/// C'est le **format de transport** entre le décodeur (dans `ZoneTurfService`)
/// et le corpus. Il est séparé de [PerformanceLocale] volontairement : la
/// lecture PMU et la lecture locale n'ont pas les mêmes garanties, et les
/// confondre masquerait la provenance.
class PerformancePmu {
  const PerformancePmu({
    required this.nomCheval,
    this.dateIso,
    this.hippodrome = '',
    this.discipline = '',
    this.distance,
    this.place,
    this.reductionKm,
    this.gains,
    this.chargeBrute,
    this.etatTerrain = '',
  });

  final String nomCheval;
  final String? dateIso;
  final String hippodrome;
  final String discipline;
  final int? distance;
  final int? place;
  final double? reductionKm;
  final double? gains;
  final String? chargeBrute;

  /// État du terrain publié par le PMU (chaîne vide s'il ne le publie pas).
  /// Ce n'est PAS la surface de la piste : la distinction est conservée.
  final String etatTerrain;

  /// Une entrée sans date ni nom n'est pas exploitable : elle est écartée au
  /// lieu d'être stockée comme une ligne vide qui polluerait les comptes.
  bool get estExploitable =>
      nomCheval.trim().isNotEmpty && dateIso != null && dateIso!.isNotEmpty;
}

/// Clé déterministe d'une performance.
///
/// Elle reproduit exactement la contrainte UNIQUE du schéma, ce qui rend deux
/// calculs indépendants convergents : la même performance produit la même clé,
/// donc un rejeu n'ajoute rien.
String clePerformance({
  required String? idCheval,
  required String? datePerf,
  required String? hippodrome,
  required String source,
}) =>
    '${idCheval ?? "?"}|${datePerf ?? "?"}|${hippodrome ?? "?"}|$source';

/// Identifiant **stable et non fusionnant** d'un cheval pour ses performances.
///
/// ⚠️ §7 : le nom normalisé n'est pas une preuve d'identité. Cet identifiant
/// n'affirme donc **pas** que deux graphies désignent le même cheval ; il
/// fournit une clé interne stable pour regrouper les performances publiées
/// sous une même graphie et une même discipline. Deux chevaux homonymes de même
/// discipline resteraient confondus — c'est une limite **réelle**, signalée
/// comme telle, que seule une résolution par identifiant fournisseur lèverait
/// (D-11).
String identifiantPerformanceCheval({
  required String nomBrut,
  required String discipline,
}) {
  final n = normaliserNom(nomBrut);
  final d = discipline.trim().toLowerCase();
  return d.isEmpty ? 'perf:$n' : 'perf:$n|$d';
}

/// `AAAA-MM-JJ` depuis `AAAAMMJJ`, ou `null` si la chaîne n'est pas une date.
String? _dateIso(String dateStr) {
  if (dateStr.length != 8) return null;
  final a = int.tryParse(dateStr.substring(0, 4));
  final m = int.tryParse(dateStr.substring(4, 6));
  final j = int.tryParse(dateStr.substring(6, 8));
  if (a == null || m == null || j == null) return null;
  if (m < 1 || m > 12 || j < 1 || j > 31) return null;
  return '${dateStr.substring(0, 4)}-${dateStr.substring(4, 6)}-'
      '${dateStr.substring(6, 8)}';
}
