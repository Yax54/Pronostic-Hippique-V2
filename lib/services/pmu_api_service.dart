import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/pmu_models.dart';
import '../services/gain_calculator.dart';

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
    final url = kIsWeb
        ? '$_proxyBase/programme/$date/R$numR/C$numC/rapports-definitifs'
        : '$_baseUrl/programme/$date/R$numR/C$numC/rapports-definitifs?$_specialisation';

    try {
      final resp = await http.get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        if (kDebugMode) debugPrint('⏳ Rapports non disponibles R${numR}C$numC: HTTP ${resp.statusCode}');
        return [];
      }
      final data = jsonDecode(resp.body);
      if (data is! List) return [];

      final rapports = <RapportPmu>[];
      for (final item in data) {
        final typePari = item['typePari'] as String? ?? '';
        final listeRapports = item['rapports'] as List<dynamic>? ?? [];
        for (final r in listeRapports) {
          final combinaison = r['combinaison'] as String? ?? '';

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
            rapports.add(RapportPmu(
              typePari: typePari,
              combinaison: combinaison,
              dividende: dividendeNormalise,
              // NP = "N'importe quelle Position" = Désordre (API PMU réelle)
              estOrdre: !combinaison.contains('NP') && !combinaison.contains('D') && !combinaison.contains('d'),
            ));
          }
        }
      }

      if (kDebugMode) {
        debugPrint('✅ Rapports définitifs R${numR}C$numC: ${rapports.length} rapports');
        for (final r in rapports) {
          debugPrint('  ${r.typePari} | ${r.combinaison} | ×${r.dividende.toStringAsFixed(2)}');
        }
      }
      return rapports;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ fetchRapportsDefinitifs R${numR}C$numC error: $e');
      return [];
    }
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
        l.contains('gagnant+place'))  return ['E_SIMPLE_GAGNANT', 'E_SIMPLE_PLACE'];
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
