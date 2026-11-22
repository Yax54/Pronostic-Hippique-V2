import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/pmu_models.dart';
import '../services/gain_calculator.dart';
import '../services/gain_ticket_calculator.dart' show RapportOfficiel;

// ───────────────────────────────────────────────────────────────────────────
//  ★ LOT B-4.6 — DIAGNOSTIC DES RAPPORTS MANQUANTS
//
//  Constat mesuré (B-4.6) : huit chemins distincts rendaient `[]` et étaient
//  INDISCERNABLES en release, parce que les neuf `debugPrint` du service sont
//  tous sous `kDebugMode`. Une réponse vide (`200` + `[]`), un `404`, un `500`,
//  un `timeout`, une erreur réseau, un corps HTML et une racine non-liste
//  produisaient exactement le même résultat observable : une liste vide.
//
//  Cette énumération et le diagnostic ci-dessous sont PURS : ils n'entrent
//  dans AUCUN calcul, ne changent AUCUN montant et ne modifient AUCUNE règle.
//  Ils rendent seulement la cause OBSERVABLE hors debug.
// ───────────────────────────────────────────────────────────────────────────

/// Cause exacte pour laquelle aucun rapport n'a pu être obtenu.
enum CauseAbsenceRapports {
  /// Au moins un rapport exploitable a été obtenu : il n'y a rien à signaler.
  aucune,

  /// L'API a répondu, mais avec un code HTTP autre que 200.
  /// [DiagnosticRapports.codeHttp] porte le code réellement reçu.
  httpNonOk,

  /// Le délai de 15 s du service a été dépassé.
  timeout,

  /// Le réseau est injoignable, ou la connexion a été coupée.
  reseau,

  /// La réponse n'est pas du JSON (page d'erreur, HTML de maintenance…).
  corpsNonJson,

  /// La réponse EST du JSON valide, mais ce n'est pas une liste : c'est la
  /// forme d'un fichier de PROGRAMME (`{"programme": {...}}`), pas celle de
  /// rapports. Cas réel mesuré sur les captures `prog_*.json`.
  racineNonListe,

  /// La réponse est une liste valide, mais elle ne contient **aucune ligne**
  /// de rapport : la course n'a pas encore ses rapports définitifs.
  aucunRapportPublie,

  /// La réponse publie des lignes, mais **toutes** ont été écartées par le
  /// filtre historique `dividendeNormalise > 0` de
  /// [PmuApiService.decoderRapportsDefinitifs].
  ///
  /// ★ B-4.6 — cette cause existe pour une raison précise : le filtre
  /// s'applique *pendant* le décodage, donc une liste vide ne prouve pas que
  /// le PMU n'a rien publié. Sans cette distinction, une course dont toutes
  /// les lignes sont à dividende nul serait présentée comme « aucun rapport
  /// publié » alors que des rapports **ont** été publiés.
  /// Mesuré : 0 occurrence sur 358 captures réelles — le défaut était latent,
  /// jamais observé. Il est désormais nommé au lieu d'être confondu.
  aucunRapportExploitable,
}

/// Résultat d'une récupération de rapports : les rapports, ET la raison de
/// leur absence éventuelle.
///
/// `aDesRapports == false` n'est donc plus une information unique : la [cause]
/// dit laquelle des situations s'est produite.
class DiagnosticRapports {
  const DiagnosticRapports({
    required this.rapports,
    required this.cause,
    this.codeHttp,
    this.lignesPubliees = 0,
  });

  final List<RapportPmu> rapports;
  final CauseAbsenceRapports cause;
  final int? codeHttp;

  /// Nombre de lignes de rapport **réellement présentes dans le corps**, avant
  /// le filtre `dividendeNormalise > 0`. Permet de distinguer « rien publié »
  /// de « publié mais rien d'exploitable ». `0` hors des cas HTTP 200.
  final int lignesPubliees;

  bool get aDesRapports => rapports.isNotEmpty;

  @override
  String toString() =>
      'DiagnosticRapports(rapports=${rapports.length}, cause=${cause.name}'
      '${lignesPubliees > 0 ? ', lignesPubliees=$lignesPubliees' : ''}'
      '${codeHttp != null ? ', http=$codeHttp' : ''})';
}

/// Compte les lignes de rapport présentes dans une réponse déjà décodée.
///
/// Compte **ce que le PMU publie**, sans aucune règle financière : une ligne
/// est comptée dès qu'elle est un objet JSON à l'intérieur du tableau
/// `rapports` d'un bloc, quels que soient son dividende et son code de pari.
/// Le filtre `dividendeNormalise > 0` de
/// [PmuApiService.decoderRapportsDefinitifs] n'intervient pas ici.
int _compterLignesPubliees(dynamic decode) {
  if (decode is! List) return 0;
  var n = 0;
  for (final bloc in decode) {
    if (bloc is! Map) continue;
    final lignes = bloc['rapports'];
    if (lignes is! List) continue;
    for (final ligne in lignes) {
      if (ligne is Map) n++;
    }
  }
  return n;
}

/// Lit la variante Ordre / Désordre dans le libellé officiel du PMU.
///
/// Rend `null` quand le libellé ne tranche pas : l'appelant garde alors
/// l'heuristique historique. C'est volontaire — la plupart des libellés réels
/// (« e-Simple Placé », « e-2sur4 », « e-Trio », « e-Multi en 6 ») ne portent
/// ni « ordre » ni « désordre », et leur appliquer une règle générale
/// inverserait leur classement (mesuré : 4050 lignes sur 4684).
///
/// Seules les deux mentions explicites sont reconnues. « Désordre » est testé
/// en premier parce qu'il **contient** la chaîne « ordre ».
///
/// Le test ignore la casse et les accents de « Désordre » : mesuré, les
/// libellés réels emploient la forme accentuée (« e-Tiercé Désordre »).
@visibleForTesting
bool? estOrdreDepuisLibelleOfficiel(String libelle) =>
    _estOrdreDepuisLibelle(libelle);

bool? _estOrdreDepuisLibelle(String libelle) {
  if (libelle.isEmpty) return null;
  final l = libelle.toLowerCase();
  if (l.contains('ésordre') || l.contains('esordre')) return false;
  if (l.contains('ordre')) return true;
  return null;
}

/// Service API PMU — 100% données réelles, zéro démo
/// Toutes les méthodes retournent des données réelles depuis l'API officielle PMU.
class PmuApiService {
  static const String _baseUrl = 'https://turfinfo.api.pmu.fr/rest/client/7';
  static const String _specialisation = 'specialisation=INTERNET';

  static String get _proxyBase {
    if (kIsWeb) {
      final origin = Uri.base.origin;
      return '$origin/api/pmu';
    }
    return _baseUrl;
  }

  static Map<String, String> get _headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  static String _today() {
    final now = DateTime.now();
    final d = now.day.toString().padLeft(2, '0');
    final m = now.month.toString().padLeft(2, '0');
    final y = now.year.toString();
    return '$d$m$y';
  }

  // ─── Programme du jour ────────────────────────────────────────────────────

  /// Retourne les réunions françaises du jour (vraies données PMU).
  /// Lance une exception si l'API est inaccessible.
  static Future<List<PmuReunion>> fetchProgramme({String? dateStr}) async {
    final date = dateStr ?? _today();
    final url = kIsWeb
        ? '$_proxyBase/programme/$date'
        : '$_baseUrl/programme/$date?$_specialisation';

    try {
      final resp = await http.get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        throw Exception('API PMU: HTTP ${resp.statusCode}');
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final reunions = (data['programme']?['reunions'] as List<dynamic>? ?? []);
      final result = reunions
          .map((r) => PmuReunion.fromJson(r as Map<String, dynamic>, date))
          .where((r) => r.isFrench)
          .toList();
      if (kDebugMode) debugPrint('✅ Programme PMU: ${result.length} réunions françaises');
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ fetchProgramme error: $e');
      rethrow;
    }
  }

  // ─── Participants d'une course ────────────────────────────────────────────

  /// Récupère les vrais participants d'une course depuis l'API PMU.
  ///
  /// Retourne une liste vide si la course n'a pas encore de partants (HTTP 404/204).
  /// Lance une exception pour toute autre erreur réseau ou serveur.
  static Future<List<PmuParticipant>> fetchParticipants(
      String date, int numR, int numC) async {
    final url = kIsWeb
        ? '$_proxyBase/programme/$date/R$numR/C$numC/participants'
        : '$_baseUrl/programme/$date/R$numR/C$numC/participants?$_specialisation';

    try {
      final resp = await http.get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 15));

      // 404 / 204 = partants pas encore disponibles (normal avant la course)
      if (resp.statusCode == 404 || resp.statusCode == 204) {
        if (kDebugMode) debugPrint('⏳ Partants R${numR}C$numC non disponibles (${resp.statusCode})');
        return [];
      }
      if (resp.statusCode != 200) {
        throw Exception('API PMU participants: HTTP ${resp.statusCode}');
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = (data['participants'] as List<dynamic>? ?? []);
      final participants = list
          .map((p) => PmuParticipant.fromJson(p as Map<String, dynamic>))
          .where((p) => p.statut != 'NON_PARTANT')
          .toList()
        ..sort((a, b) => a.numero.compareTo(b.numero));
      if (kDebugMode) debugPrint('✅ R${numR}C$numC: ${participants.length} partants réels');
      return participants;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ fetchParticipants R${numR}C$numC error: $e');
      rethrow;
    }
  }

  // ─── Pronostics Equidia ───────────────────────────────────────────────────

  /// Récupère les vrais pronostics Equidia pour une course.
  static Future<EquidiaPronostics?> fetchPronostics(
      String date, int numR, int numC) async {
    final url = kIsWeb
        ? '$_proxyBase/programme/$date/R$numR/C$numC/pronostics'
        : '$_baseUrl/programme/$date/R$numR/C$numC/pronostics?$_specialisation';

    try {
      final resp = await http.get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['selection'] == null) return null;
      return EquidiaPronostics.fromJson(data);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ fetchPronostics R${numR}C$numC error: $e');
      return null;
    }
  }

  // ─── Rapports définitifs après course ────────────────────────────────────

  /// Récupère les vrais dividendes PMU après la course (rapports-definitifs).
  /// Retourne une map typePari → liste de RapportPmu.
  /// Disponible uniquement après l'arrivée définitive de la course.
  ///
  /// Types de paris retournés par l'API :
  ///   E_SIMPLE_GAGNANT, E_SIMPLE_PLACE, E_COUPLE_GAGNANT, E_COUPLE_PLACE,
  ///   E_TIERCE, E_QUARTE_PLUS, E_QUINTE_PLUS, E_MULTI_EN_4, E_MULTI_EN_3
  static Future<List<RapportPmu>> fetchRapportsDefinitifs(
      String date, int numR, int numC) async {
    final d = await fetchRapportsAvecDiagnostic(date, numR, numC);
    return d.rapports;
  }

  /// ★ LOT B-4.6 — la MÊME récupération, mais la cause de l'absence est rendue.
  ///
  /// Le comportement observable de [fetchRapportsDefinitifs] est INCHANGÉ :
  /// elle rend toujours `[]` dans les sept cas d'échec, jamais d'exception.
  /// Seule la cause devient disponible pour l'appelant qui la demande.
  ///
  /// Aucune règle métier, aucun montant, aucun verdict n'est touché ici : on
  /// ne fait que QUALIFIER une absence qui existait déjà.
  static Future<DiagnosticRapports> fetchRapportsAvecDiagnostic(
      String date, int numR, int numC) async {
    final url = kIsWeb
        ? '$_proxyBase/programme/$date/R$numR/C$numC/rapports-definitifs'
        : '$_baseUrl/programme/$date/R$numR/C$numC/rapports-definitifs?$_specialisation';

    try {
      final resp = await http.get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        if (kDebugMode) debugPrint('⏳ Rapports non disponibles R${numR}C$numC: HTTP ${resp.statusCode}');
        return DiagnosticRapports(
          rapports: const <RapportPmu>[],
          cause: CauseAbsenceRapports.httpNonOk,
          codeHttp: resp.statusCode,
        );
      }

      // ── Qualification de la réponse AVANT décodage ────────────────────
      // `jsonDecode` est volontairement laissé non protégé dans le décodeur
      // historique ; on isole donc ici les deux causes de forme.
      dynamic decode;
      try {
        decode = jsonDecode(resp.body);
      } on FormatException {
        return const DiagnosticRapports(
          rapports: <RapportPmu>[],
          cause: CauseAbsenceRapports.corpsNonJson,
          codeHttp: 200,
        );
      }
      if (decode is! List) {
        return const DiagnosticRapports(
          rapports: <RapportPmu>[],
          cause: CauseAbsenceRapports.racineNonListe,
          codeHttp: 200,
        );
      }

      final rapports = decoderRapportsDefinitifs(resp.body);

      // ★ B-4.6 — le filtre `dividendeNormalise > 0` agit PENDANT le décodage.
      //   Une liste vide ne prouve donc pas que le PMU n'a rien publié : il
      //   faut compter les lignes réellement présentes dans le corps.
      final lignesPubliees = _compterLignesPubliees(decode);

      if (kDebugMode) {
        debugPrint('✅ Rapports définitifs R${numR}C$numC: ${rapports.length} '
            'rapport(s) retenu(s) sur $lignesPubliees ligne(s) publiée(s)');
        for (final r in rapports) {
          debugPrint('  $r');
        }
      }
      return DiagnosticRapports(
        rapports: rapports,
        cause: rapports.isNotEmpty
            ? CauseAbsenceRapports.aucune
            : (lignesPubliees == 0
                ? CauseAbsenceRapports.aucunRapportPublie
                : CauseAbsenceRapports.aucunRapportExploitable),
        codeHttp: 200,
        lignesPubliees: lignesPubliees,
      );
    } on TimeoutException catch (e) {
      if (kDebugMode) debugPrint('❌ fetchRapportsDefinitifs R${numR}C$numC timeout: $e');
      return const DiagnosticRapports(
        rapports: <RapportPmu>[],
        cause: CauseAbsenceRapports.timeout,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ fetchRapportsDefinitifs R${numR}C$numC error: $e');
      // Toute exception non liée à la forme du corps est une défaillance
      // d'échange : le réseau n'a pas rendu de réponse exploitable.
      return const DiagnosticRapports(
        rapports: <RapportPmu>[],
        cause: CauseAbsenceRapports.reseau,
      );
    }
  }

  /// ★ ÉTAPE 4-C — DÉCODAGE PUR, SANS RÉSEAU.
  ///
  /// Extrait du corps de [fetchRapportsDefinitifs] pour être **testable sans
  /// HTTP**. Le comportement est celui d'avant, à l'identique, sur les quatre
  /// champs historiques :
  ///
  ///   • `typePari`      ← `item['typePari']` du BLOC
  ///   • `combinaison`   ← `r['combinaison']`
  ///   • `dividende`     ← `dividendePourUnEuro` / 100, à défaut `dividende` / 100
  ///   • `estOrdre`      ← heuristique historique, reproduite telle quelle
  ///   • un rapport dont le dividende normalisé n'est pas > 0 est ÉCARTÉ
  ///
  /// S'y ajoutent désormais, **sans rien retirer**, les informations
  /// officielles que le format réel publie et qui étaient jetées :
  /// `libelle` (par rapport), `rangCombinaisonPayable` (par rapport),
  /// `rembourse` / `miseBase` / `dividendeUnite` (par bloc), et le code du
  /// bloc lui-même ([RapportPmu.codePariOfficiel]).
  ///
  /// Aucune de ces additions n'entre dans un calcul de montant : les
  /// consommateurs actuels lisent `dividende`, qui est inchangé.
  ///
  /// Retourne une liste vide (jamais une exception) si le corps n'est pas une
  /// liste JSON : c'est le comportement d'avant.
  @visibleForTesting
  static List<RapportPmu> decoderRapportsDefinitifs(String corps) {
    final data = jsonDecode(corps);
    if (data is! List) return [];

    final rapports = <RapportPmu>[];
    for (final item in data) {
      if (item is! Map) {
        continue;
      }

      final typePari = item['typePari'] as String? ?? '';
      final listeRapports = item['rapports'] as List<dynamic>? ?? [];

      // ── Informations portées par le BLOC (jamais par le rapport) ────────
      final rembourseBloc = item['rembourse'] == true;
      final miseBaseBrute = item['miseBase'];
      final miseBase =
          miseBaseBrute is num ? miseBaseBrute.toInt() : null;
      final uniteBloc = item['dividendeUnite']?.toString() ?? '';

      for (final r in listeRapports) {
        if (r is! Map) {
          continue;
        }
        final combinaison = r['combinaison'] as String? ?? '';
        final libelle = r['libelle']?.toString() ?? '';

        // ── Parsing dividende unifié ──────────────────────────────────────
        // L'API PMU renvoie TOUJOURS le dividende en centimes d'euro
        // dans 'dividendePourUnEuro' (ex: 210 = 2,10€ pour 1€ misé).
        // Le champ 'dividende' (s'il existe) est parfois en centimes aussi.
        // Règle : priorité à 'dividendePourUnEuro' / 100, sinon 'dividende' / 100.
        // ⚠️ Ne JAMAIS lire le champ brut sans diviser par 100.
        final rawDivPourUnEuro = r['dividendePourUnEuro'];
        final rawDivLegacy     = r['dividende'];

        double dividendeNormalise = 0.0;
        if (rawDivPourUnEuro != null) {
          // Champ officiel PMU : valeur en centimes → /100
          dividendeNormalise = (rawDivPourUnEuro as num).toDouble() / 100.0;
        } else if (rawDivLegacy != null) {
          // Champ alternatif : également en centimes → /100
          dividendeNormalise = (rawDivLegacy as num).toDouble() / 100.0;
        }

        if (dividendeNormalise > 0) {
          // ── Rang payable : conservé tel quel, sans interprétation ───────
          final rangBrut = r['rangCombinaisonPayable'];
          final rang = rangBrut is num ? rangBrut.toInt() : null;

          rapports.add(RapportPmu(
            // ── Les 4 champs historiques : VALEURS INCHANGÉES ────────────
            typePari: typePari,
            combinaison: combinaison,
            dividende: dividendeNormalise,
            // ★ B-4.6 — heuristique historique, CORRIGÉE sur un seul point.
            //
            //   Historique : `!combinaison.contains('NP') && !combinaison
            //   .contains('D')`. Mesuré sur 4684 lignes réelles : AUCUNE
            //   combinaison ne contient « D » → le second terme vaut toujours
            //   `true` et ne distinguait donc rien.
            //
            //   Or les blocs à couple Ordre/Désordre publient la MÊME
            //   combinaison (mesuré : 20 paires sur 20). Seul le libellé les
            //   sépare. Résultat mesuré avant correction : 70 lignes libellées
            //   « Désordre » (e-Tiercé, e-Quarté+, e-Quinté+, e-Super Pick5)
            //   étaient présentées comme « Dans l'ordre », avec l'icône Ordre.
            //
            //   Correction MINIMALE : seul un libellé « désordre » explicite
            //   force `false`. Aucun autre libellé n'est interprété —
            //   appliquer la règle inverse (« ordre » explicite ⇒ `true`) a été
            //   mesuré et inverserait 4050 lignes (Simple Placé, 2sur4, Trio…),
            //   car la plupart des libellés ne portent aucune des deux mentions.
            //
            //   `estOrdre` n'entre dans AUCUN calcul de montant : la chaîne
            //   financière lit `RapportPublie.variante` (type `RapportAttribue`,
            //   socle de gain). Cette correction n'affecte que libellés et
            //   icônes d'affichage.
            estOrdre: _estOrdreDepuisLibelle(libelle)
                ?? (!combinaison.contains('NP') &&
                    !combinaison.contains('D') &&
                    !combinaison.contains('d')),
            // ── Informations officielles désormais PRÉSERVÉES ────────────
            libelleOfficiel: r['libelle']?.toString() ?? '',
            codePariOfficiel: typePari,
            rangCombinaisonPayable: rang,
            rembourse: rembourseBloc,
            miseBaseCentimes: miseBase,
            dividendeUnite: r['dividendeUnite']?.toString().isNotEmpty == true
                ? r['dividendeUnite'].toString()
                : uniteBloc,
          ));
        }
      }
    }

    return rapports;
  }

  /// Construit les [RapportOfficiel] attendus par le résolveur de rapports
  /// à partir d'une réponse brute.
  ///
  /// ★ ÉTAPE 4-C — PONT DE COMPATIBILITÉ, **PAS ENCORE RACCORDÉ**.
  ///
  /// Cette méthode n'est appelée par AUCUNE écriture financière : elle sert à
  /// vérifier, par test, que `RapportOfficiel.depuisJson` — qui n'avait
  /// jusqu'ici aucun appelant — accepte bien une réponse au format réel et que
  /// le résolveur en tire des verdicts distincts (Ordre / Désordre / Bonus).
  ///
  /// Elle ne remplace ni ne réordonne rien : elle parcourt les blocs dans
  /// l'ordre publié et conserve chaque rapport tel quel.
  @visibleForTesting
  static List<RapportOfficiel> decoderRapportsOfficiels(String corps) {
    final data = jsonDecode(corps);
    if (data is! List) return const <RapportOfficiel>[];

    final out = <RapportOfficiel>[];
    for (final item in data) {
      if (item is! Map) {
        continue;
      }
      final typePari = item['typePari'] as String? ?? '';
      final miseBaseBrute = item['miseBase'];
      final miseBase = miseBaseBrute is num ? miseBaseBrute.toInt() : null;
      final liste = item['rapports'] as List<dynamic>? ?? [];

      for (final r in liste) {
        if (r is! Map) {
          continue;
        }
        // ⚠️ `RapportOfficiel.depuisJson` lit `rembourse` SUR LE RAPPORT, alors
        // que l'API le publie SUR LE BLOC (mesuré : clé de bloc uniquement).
        // On rétablit donc l'information du bloc, sans rien inventer : si le
        // bloc ne la porte pas, `depuisJson` garde son défaut `false`.
        final json = Map<String, dynamic>.from(r);
        json.putIfAbsent('rembourse', () => item['rembourse']);

        final rapport = RapportOfficiel.depuisJson(
          json,
          typePari: typePari,
          miseBaseCentimes: miseBase,
        );
        // `depuisJson` rend `null` pour un rapport sans libelle NI combinaison :
        // ce refus est conservé tel quel, jamais contourné.
        if (rapport != null) out.add(rapport);
      }
    }
    return out;
  }

  /// Retourne le dividende PMU réel pour un type de pari donné et une
  /// combinaison de numéros de chevaux. Ex: typePari='E_TIERCE', numeros=[5,12,3]
  /// Retourne null si le rapport n'est pas disponible (course pas encore terminée).
  static Future<RapportPmu?> fetchDividendePourPari({
    required String date,
    required int numR,
    required int numC,
    required String typePari,
    required List<int> numerosJoues,
  }) async {
    final rapports = await fetchRapportsDefinitifs(date, numR, numC);
    if (rapports.isEmpty) return null;

    // Recherche le rapport correspondant au type de pari
    final typesPari = _typePariApiFromLabel(typePari);
    for (final tp in typesPari) {
      final matching = rapports.where((r) => r.typePari == tp).toList();
      if (matching.isNotEmpty) {
        // Cherche la combinaison exacte ou prend le premier disponible
        final combStr = numerosJoues.join('-');
        final exact = matching.where((r) => r.combinaison == combStr).toList();
        if (exact.isNotEmpty) return exact.first;
        // Sinon retourne n'importe quel rapport de ce type (pour info)
        return matching.first;
      }
    }
    return null;
  }

  /// Mappe un label de type de pari vers le(s) vrai(s) code(s) API PMU
  /// Codes réels retournés par l'API turfinfo :
  ///   E_SIMPLE_GAGNANT, E_SIMPLE_PLACE,
  ///   E_COUPLE_GAGNANT, E_COUPLE_PLACE,
  ///   E_TRIO        (= Tiercé),
  ///   E_SUPER_QUATRE (= Quarté+),
  ///   E_MULTI / E_MINI_MULTI (= Quinté+)
  static List<String> _typePariApiFromLabel(String label) {
    final l = label.toLowerCase();
    // Ordre important : tester les plus spécifiques en premier
    if (l.contains('gagnant+placé') || l.contains('gagnant + placé') ||
        l.contains('gagnant+place')) {
      return ['E_SIMPLE_GAGNANT', 'E_SIMPLE_PLACE'];
    }
    if (l.contains('couplé gagnant')) return ['E_COUPLE_GAGNANT'];
    if (l.contains('couplé placé'))   return ['E_COUPLE_PLACE'];
    if (l.contains('quinté'))         return ['E_MULTI', 'E_MINI_MULTI'];
    if (l.contains('quarté'))         return ['E_SUPER_QUATRE'];
    if (l.contains('tiercé'))         return ['E_TRIO'];
    if (l.contains('simple gagnant')) return ['E_SIMPLE_GAGNANT'];
    if (l.contains('simple placé'))   return ['E_SIMPLE_PLACE'];
    if (l.contains('gagnant'))        return ['E_SIMPLE_GAGNANT'];
    if (l.contains('placé'))          return ['E_SIMPLE_PLACE'];
    return [];
  }
}
