// ═══════════════════════════════════════════════════════════════════════════
//  V36 — A-2 : RANGEMENT PREMIUM SOUS LA DATE RÉELLE DE LA COURSE
//
//  DÉFAUT CORRIGÉ
//    `enregistrerPronosticsPremiumDuJour()` rangeait toutes les entrées sous
//    `_todayKey()` (date du TÉLÉPHONE), alors que le lecteur
//    `donneesCalendrierJour()` (ia_memory_service.dart:856) lit sous la date
//    du PRONOSTIC. Divergence ⇒ l'entrée existe sur le disque mais n'est
//    jamais lue ⇒ `hasBestBet = false` ⇒ perte silencieuse et définitive.
//
//  CE QUE CES TESTS VERROUILLENT
//    • la date de rangement provient de `courseKey`, jamais de l'horloge ;
//    • aucun identifiant n'est réécrit (suffixes préservés) ;
//    • les deux formats réellement présents (djmmaaaa et ISO) sont acceptés ;
//    • une date indéterminable est REJETÉE, jamais remplacée ;
//    • le dédoublonnage, les resets et la persistance sont intacts ;
//    • ni `_poids`, ni `_seuils`, ni `_pronostics` ne sont touchés.
//
//  DÉTERMINISME
//    Aucune dépendance à l'horloge : tous les cas où « la date du téléphone »
//    compterait emploient des dates de course FIXES et distinctes de la date
//    courante. Aucun `sleep`, aucun `Timer`, aucune attente réseau.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/utils/date_utils.dart';

// ─── Store espion minimal (même principe que v26/v27) ───────────────────────

class StoreV36 extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};
  final List<String> journal = <String>[];
  int nbSetString = 0;

  @override
  Future<bool> clear() async {
    _valeurs.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => getAllWithParameters(
        GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
      );

  @override
  Future<Map<String, Object>> getAllWithParameters(
      GetAllParameters parameters) async {
    final prefix = parameters.filter.prefix;
    return <String, Object>{
      for (final e in _valeurs.entries)
        if (e.key.startsWith(prefix)) e.key: e.value,
    };
  }

  @override
  Future<bool> remove(String key) async {
    journal.add('REM $key');
    _valeurs.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    journal.add('SET $key');
    if (key == 'flutter.$_kPremiumHistorique') nbSetString++;
    _valeurs[key] = value;
    return true;
  }

  void semer(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;
  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');
}

const String _kPremiumHistorique = 'ia_premium_historique_v1';

late StoreV36 store;

void _installerStore({Map<String, Object>? data}) {
  store = StoreV36();
  SharedPreferencesStorePlatform.instance = store;
  SharedPreferences.resetStatic();
  if (data != null) {
    data.forEach(store.semer);
  }
}

// ─── Fabriques ──────────────────────────────────────────────────────────────

/// Entrée premium dont la `courseKey` porte la date FOURNIE, sans lien aucun
/// avec la date du téléphone. C'est le cœur du défaut A-2.
PremiumPronosticDuJour _premium({
  required String courseKey,
  String typePari = 'Quinté+',
  String sourceWidget = 'conseilJour',
  List<String> numeros = const <String>['3', '7', '1', '5', '2'],
}) =>
    PremiumPronosticDuJour(
      courseKey: courseKey,
      typePari: typePari,
      numeros: numeros,
      sourceWidget: sourceWidget,
    );

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Force `_loaded = false` puis `_load()` : seul chemin public qui fasse cela.
/// (Mécanisme officiel du projet, utilisé par v15/v16/v26/v27/v28.)
Future<void> _recharger() => IaMemoryService.instance.recharger();

/// Garantit que la mémoire est chargée pour l'appel en cours.
Future<void> _amorcer() async {
  await IaMemoryService.init();
  await _recharger();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═════════════════════════════════════════════════════════════════════════
  //  A — `dateDepuisCourseKey` et `estDateCourseCalendaireValide` :
  //      fonctions PURES, sans état, sans horloge.
  // ═════════════════════════════════════════════════════════════════════════

  group('A — Extraction pure de la date depuis une courseKey', () {
    test('A-1 — jour ≠ mois : 23/04/2026 (détecte toute inversion année/mois/jour)',
        () {
      // 23 et 04 sont DIFFÉRENTS et le jour dépasse 12 : une inversion
      // `DateTime(annee, jour, mois)` ou `DateTime(annee, mois, jour)`
      // mal ordonnée produit un mois 23 normalisé en silence et échoue.
      expect(dateDepuisCourseKey('R1C5_23042026'), '2026-04-23');
      // Contre-vérification par le prédicat bas niveau.
      expect(estDateCourseCalendaireValide('23042026'), isTrue);
    });

    test('A-2 — plusieurs dates à jour ≠ mois, dans les deux sens', () {
      expect(dateDepuisCourseKey('R2C3_05072026'), '2026-07-05'); // 05 ≠ 07
      expect(dateDepuisCourseKey('R3C1_31122026'), '2026-12-31'); // 31 ≠ 12
      expect(dateDepuisCourseKey('R1C1_01092026'), '2026-09-01'); // 01 ≠ 09
      expect(dateDepuisCourseKey('R1C1_12012026'), '2026-01-12'); // 12 ≠ 01
    });

    test('A-3 — un suffixe est TOLÉRÉ, jamais un motif de rejet', () {
      // Suffixe `_ia` (bet_bottom_sheet.dart:2794) et suffixe d'horodatage
      // (alert_service.dart:713). La clé est légitime : sa date doit sortir.
      expect(dateDepuisCourseKey('R99C1005_23042026_ia'), '2026-04-23');
      expect(dateDepuisCourseKey('R4C7_23042026_1745000000000'), '2026-04-23');
    });

    test('A-4 — le format ISO déjà présent dans les données est accepté', () {
      // v26/v27 utilisent `R1C1_2026-01-05` : ne pas le reconnaître ferait
      // échouer l'amorçage de ces suites (régression mesurée, pas théorique).
      expect(dateDepuisCourseKey('R1C1_2026-01-05'), '2026-01-05');
      expect(dateDepuisCourseKey('R9C9_2026-03-02'), '2026-03-02');
      expect(dateDepuisCourseKey('R1C1_2026-01-05_ia'), '2026-01-05');
    });

    test('A-5 — une date indéterminable retourne null (aucune invention)', () {
      // `R1C3_` est ce que produit `buildCourseKey` quand `dateStr == ''`
      // (défaut de ZtCourse, zt_models.dart:773). `isNotEmpty` le laissait
      // passer : c'est précisément le trou fermé par A-2.
      expect(dateDepuisCourseKey('R1C3_'), isNull);
      expect(dateDepuisCourseKey('R1C3'), isNull);
      expect(dateDepuisCourseKey('KEY_PERSONNALISEE'), isNull);
      expect(dateDepuisCourseKey(''), isNull);
      expect(dateDepuisCourseKey('R1C1_abcdefgh'), isNull);
    });

    test('A-6 — calendrier strict : 31/02, 29/02 non bissextile, mois 32 rejetés',
        () {
      expect(estDateCourseCalendaireValide('31022026'), isFalse); // 31 février
      expect(estDateCourseCalendaireValide('29022025'), isFalse); // non bissextile
      expect(estDateCourseCalendaireValide('29022024'), isTrue);  // bissextile
      expect(estDateCourseCalendaireValide('32012026'), isFalse); // jour 32
      expect(estDateCourseCalendaireValide('00132026'), isFalse); // mois 13
      expect(estDateCourseCalendaireValide('00002026'), isFalse); // mois 00
      expect(estDateCourseCalendaireValide('31042026'), isFalse); // avril = 30 j

      expect(dateDepuisCourseKey('R1C1_31022026'), isNull);
      expect(dateDepuisCourseKey('R1C1_29022025'), isNull);
      expect(dateDepuisCourseKey('R1C1_29022024'), '2024-02-29');
      expect(dateDepuisCourseKey('R1C1_32012026'), isNull);
      expect(dateDepuisCourseKey('R1C1_00132026'), isNull);
    });

    test('A-7 — 01/01/2000 est une date RÉELLE : acceptée, non « corrigée »', () {
      // Valeur fabriquée par `heureDateTime` quand dateStr est absent
      // (zt_models.dart:829). A-2 ne l'invente pas et ne la remplace pas :
      // elle est simplement une date valide, donc extraite telle quelle.
      // La cause racine de cette fabrication relève de A-3, hors périmètre.
      expect(dateDepuisCourseKey('R5C3_01012000'), '2000-01-01');
    });

    test('A-8 — la clé n\'est jamais modifiée par l\'extraction', () {
      const cle = 'R4C7_23042026_1745000000000';
      final avant = cle;
      dateDepuisCourseKey(cle);
      expect(cle, avant, reason: 'la fonction est pure : identité préservée');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B — Rangement réel dans le service
  // ═════════════════════════════════════════════════════════════════════════

  group('B — Rangement sous la date réelle de la course', () {
    test('B-1 — la date du téléphone n\'est plus utilisée : 23/04/2026', () async {
      _installerStore();
      await _amorcer();
      final mem = IaMemoryService.instance;

      await mem.enregistrerPronosticsPremiumDuJour(
          [_premium(courseKey: 'R1C5_23042026')]);

      // TÉMOIN : la date du jour n'est PAS celle de la course (sinon le test
      // ne prouverait rien). On ne suppose rien de l'horloge, on la constate.
      final now = DateTime.now();
      final estAujourdhui = now.year == 2026 && now.month == 4 && now.day == 23;
      if (estAujourdhui) {
        debugPrint('B-1 AVERTISSEMENT : le test tourne un 23/04/2026 — '
            'la distinction date-téléphone / date-course est neutralisée');
      }

      // La date réelle de la course.
      expect(mem.premiumsPourDate(2026, 4, 23).length, 1,
          reason: 'entrée rangée sous la date de la COURSE');
      expect(mem.premiumsPourDate(2026, 4, 23).first.courseKey, 'R1C5_23042026',
          reason: 'identifiant COMPLET conservé, suffixe compris');

      // Et surtout PAS sous la date du téléphone (si elle diffère).
      if (!estAujourdhui) {
        expect(mem.premiumsPourDate(now.year, now.month, now.day), isEmpty,
            reason: 'aucune entrée sous la date du téléphone');
      }
    });

    test('B-2 — lot multijours : 3 dates de course → 3 buckets distincts',
        () async {
      _installerStore();
      await _amorcer();
      final mem = IaMemoryService.instance;

      await mem.enregistrerPronosticsPremiumDuJour([
        _premium(courseKey: 'R1C1_23042026', sourceWidget: 'conseilJour'),
        _premium(courseKey: 'R2C2_24042026', sourceWidget: 'meilleurPari'),
        _premium(courseKey: 'R3C3_25042026', sourceWidget: 'topEquilibre'),
      ]);

      expect(mem.premiumsPourDate(2026, 4, 23).length, 1);
      expect(mem.premiumsPourDate(2026, 4, 24).length, 1);
      expect(mem.premiumsPourDate(2026, 4, 25).length, 1);
      expect(mem.premiumsPourDate(2026, 4, 26), isEmpty,
          reason: 'aucune date inventée entre les trois');

      expect(mem.premiumsPourDate(2026, 4, 23).first.courseKey, 'R1C1_23042026');
      expect(mem.premiumsPourDate(2026, 4, 24).first.courseKey, 'R2C2_24042026');
      expect(mem.premiumsPourDate(2026, 4, 25).first.courseKey, 'R3C3_25042026');
    });

    test('B-3 — une seule écriture disque pour un lot multijours', () async {
      _installerStore();
      await _amorcer();
      final mem = IaMemoryService.instance;

      final avant = store.nbSetString;
      await mem.enregistrerPronosticsPremiumDuJour([
        _premium(courseKey: 'R1C1_23042026'),
        _premium(courseKey: 'R2C2_24042026'),
        _premium(courseKey: 'R3C3_25042026'),
        _premium(courseKey: 'R4C4_26042026'),
      ]);

      expect(store.nbSetString - avant, 1,
          reason: 'regroupement puis UNE seule sauvegarde');
      expect(store.contient(_kPremiumHistorique), isTrue);
    });

    test('B-4 — clé à suffixe `_ia` : date extraite, identité intacte', () async {
      _installerStore();
      await _amorcer();
      final mem = IaMemoryService.instance;

      await mem.enregistrerPronosticsPremiumDuJour(
          [_premium(courseKey: 'R99C1005_23042026_ia')]);

      final liste = mem.premiumsPourDate(2026, 4, 23);
      expect(liste.length, 1);
      expect(liste.first.courseKey, 'R99C1005_23042026_ia',
          reason: 'le suffixe est CONSERVÉ : aucune réécriture d\'identité');
    });

    test('B-5 — format ISO : rangé sous la bonne date', () async {
      _installerStore();
      await _amorcer();
      final mem = IaMemoryService.instance;

      await mem.enregistrerPronosticsPremiumDuJour(
          [_premium(courseKey: 'R1C1_2026-01-05')]);

      expect(mem.premiumsPourDate(2026, 1, 5).length, 1);
      expect(mem.premiumsPourDate(2026, 1, 5).first.courseKey, 'R1C1_2026-01-05');
    });

    test('B-6 — date indéterminable : REJETÉE, aucune date de remplacement',
        () async {
      _installerStore();
      await _amorcer();
      final mem = IaMemoryService.instance;
      final now = DateTime.now();

      await mem.enregistrerPronosticsPremiumDuJour([
        _premium(courseKey: 'R1C3_'),            // dateStr vide
        _premium(courseKey: 'R1C1_31022026'),    // 31 février
        _premium(courseKey: 'R2C2_29022025'),    // 29/02 non bissextile
      ]);

      // Aucune des trois n'est rangée, nulle part.
      expect(mem.premiumsPourDate(now.year, now.month, now.day), isEmpty,
          reason: 'aucun repli sur la date du téléphone');
      expect(mem.premiumsPourDate(2026, 2, 31), isEmpty);
      expect(mem.premiumsPourDate(2025, 2, 29), isEmpty);
      expect(mem.premiumsPourDate(2026, 2, 28), isEmpty,
          reason: 'aucune date voisine inventée par normalisation');

      // Et rien n'a été écrit sur le disque.
      expect(store.contient(_kPremiumHistorique), isFalse,
          reason: 'un lot entièrement rejeté n\'écrit rien');
    });

    test('B-7 — lot mixte : les valides sont rangées, les invalides écartées',
        () async {
      _installerStore();
      await _amorcer();
      final mem = IaMemoryService.instance;

      await mem.enregistrerPronosticsPremiumDuJour([
        _premium(courseKey: 'R1C1_23042026', sourceWidget: 'conseilJour'),
        _premium(courseKey: 'R2C2_'),           // rejetée
        _premium(courseKey: 'R3C3_24042026', sourceWidget: 'meilleurPari'),
      ]);

      expect(mem.premiumsPourDate(2026, 4, 23).length, 1);
      expect(mem.premiumsPourDate(2026, 4, 24).length, 1);
      // La rejetée n'a pollué aucune date.
      final toutes = <PremiumPronosticDuJour>[];
      for (final j in [23, 24]) {
        toutes.addAll(mem.premiumsPourDate(2026, 4, j));
      }
      expect(toutes.any((p) => p.courseKey == 'R2C2_'), isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C — Dédoublonnage, conservation, resets : NON-RÉGRESSION
  // ═════════════════════════════════════════════════════════════════════════

  group('C — Mécanismes existants préservés', () {
    test('C-1 — dédoublonnage (courseKey + sourceWidget + typePari) intact',
        () async {
      _installerStore();
      await _amorcer();
      final mem = IaMemoryService.instance;

      await mem.enregistrerPronosticsPremiumDuJour([
        _premium(courseKey: 'R1C5_23042026', sourceWidget: 'conseilJour'),
      ]);
      await mem.enregistrerPronosticsPremiumDuJour([
        _premium(
          courseKey: 'R1C5_23042026',
          sourceWidget: 'conseilJour',
          numeros: const <String>['9', '8', '7', '6', '5'],
        ),
      ]);

      // Même triplet → remplacé, pas dupliqué.
      final liste = mem.premiumsPourDate(2026, 4, 23);
      expect(liste.length, 1, reason: 'aucun doublon');
      expect(liste.first.numeros, const <String>['9', '8', '7', '6', '5'],
          reason: 'la version la plus récente remplace l\'ancienne');
    });

    test('C-2 — deux sources différentes sur la même course coexistent',
        () async {
      _installerStore();
      await _amorcer();
      final mem = IaMemoryService.instance;

      await mem.enregistrerPronosticsPremiumDuJour([
        _premium(courseKey: 'R1C5_23042026', sourceWidget: 'conseilJour'),
        _premium(courseKey: 'R1C5_23042026', sourceWidget: 'meilleurPari'),
        _premium(courseKey: 'R1C5_23042026', sourceWidget: 'topEquilibre'),
      ]);

      expect(mem.premiumsPourDate(2026, 4, 23).length, 3,
          reason: 'sourceWidget distinct → entrées distinctes');
    });

    test('C-3 — dédoublonnage à travers des dates différentes', () async {
      _installerStore();
      await _amorcer();
      final mem = IaMemoryService.instance;

      await mem.enregistrerPronosticsPremiumDuJour([
        _premium(courseKey: 'R1C5_23042026', sourceWidget: 'conseilJour'),
        _premium(courseKey: 'R2C6_24042026', sourceWidget: 'conseilJour'),
      ]);
      // Deuxième lot : les mêmes, mises à jour.
      await mem.enregistrerPronosticsPremiumDuJour([
        _premium(
            courseKey: 'R1C5_23042026',
            sourceWidget: 'conseilJour',
            numeros: const <String>['1', '1', '1', '1', '1']),
        _premium(
            courseKey: 'R2C6_24042026',
            sourceWidget: 'conseilJour',
            numeros: const <String>['2', '2', '2', '2', '2']),
      ]);

      expect(mem.premiumsPourDate(2026, 4, 23).length, 1);
      expect(mem.premiumsPourDate(2026, 4, 24).length, 1);
      expect(mem.premiumsPourDate(2026, 4, 23).first.numeros.first, '1');
      expect(mem.premiumsPourDate(2026, 4, 24).first.numeros.first, '2');
    });

    test('C-4 — entrée historique d\'un autre jour : ni touchée ni déplacée',
        () async {
      // Historique existant, injecté directement sur le disque (comme un
      // appareil utilisé depuis des mois). A-2 ne migre RIEN.
      final ancienne = <String, Object>{
        _kPremiumHistorique: jsonEncode({
          'entries': {
            '2025-11-30': [
              _premium(courseKey: 'R7C7_30112025').toJson(),
            ],
          },
        }),
      };
      _installerStore(data: ancienne);
      await _amorcer();
      final mem = IaMemoryService.instance;

      await mem.enregistrerPronosticsPremiumDuJour(
          [_premium(courseKey: 'R1C5_23042026')]);

      // L'ancienne est intacte, à sa place.
      expect(mem.premiumsPourDate(2025, 11, 30).length, 1);
      expect(mem.premiumsPourDate(2025, 11, 30).first.courseKey, 'R7C7_30112025');
      // La nouvelle est à sa place.
      expect(mem.premiumsPourDate(2026, 4, 23).length, 1);
      // Aucune migration de l'ancienne vers la date de la nouvelle.
      expect(mem.premiumsPourDate(2026, 4, 23).length, 1);
    });

    test('C-5 — resetPremiumPourDate reste opérant', () async {
      _installerStore();
      await _amorcer();
      final mem = IaMemoryService.instance;

      await mem.enregistrerPronosticsPremiumDuJour([
        _premium(courseKey: 'R1C5_23042026'),
        _premium(courseKey: 'R2C6_24042026'),
      ]);
      expect(mem.premiumsPourDate(2026, 4, 23).length, 1);

      await mem.resetPremiumPourDate(DateTime(2026, 4, 23));

      expect(mem.premiumsPourDate(2026, 4, 23), isEmpty,
          reason: 'reset ciblé effectif');
      expect(mem.premiumsPourDate(2026, 4, 24).length, 1,
          reason: 'reset ciblé ne touche pas les autres dates');
    });

    test('C-6 — resetToutesEtoilesPremium reste opérant', () async {
      _installerStore();
      await _amorcer();
      final mem = IaMemoryService.instance;

      await mem.enregistrerPronosticsPremiumDuJour([
        _premium(courseKey: 'R1C5_23042026'),
        _premium(courseKey: 'R2C6_24042026'),
      ]);

      await mem.resetToutesEtoilesPremium();

      expect(mem.premiumsPourDate(2026, 4, 23), isEmpty);
      expect(mem.premiumsPourDate(2026, 4, 24), isEmpty);
      expect(store.contient(_kPremiumHistorique), isFalse);
    });

    test('C-7 — persistance : le rangement survit à un rechargement', () async {
      _installerStore();
      await _amorcer();
      final mem = IaMemoryService.instance;

      await mem.enregistrerPronosticsPremiumDuJour(
          [_premium(courseKey: 'R1C5_23042026')]);

      // Rechargement depuis le disque réel du store.
      await _recharger();

      expect(mem.premiumsPourDate(2026, 4, 23).length, 1,
          reason: 'la date de rangement est bien persistée');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  D — Aucune atteinte à l'IA, aucune invention
  // ═════════════════════════════════════════════════════════════════════════

  group('D — IA intacte, aucune invention', () {
    test('D-1 — _poids et _seuils ne bougent pas', () async {
      _installerStore();
      await _amorcer();
      final mem = IaMemoryService.instance;

      final poidsAvant = jsonEncode(mem.poids.toJson());
      final seuilsAvant = jsonEncode(mem.seuilsConfiance.toJson());

      await mem.enregistrerPronosticsPremiumDuJour([
        _premium(courseKey: 'R1C5_23042026'),
        _premium(courseKey: 'R2C6_24042026'),
        _premium(courseKey: 'R3C7_'), // rejetée
      ]);

      expect(jsonEncode(mem.poids.toJson()), poidsAvant,
          reason: 'poids inchangés');
      expect(jsonEncode(mem.seuilsConfiance.toJson()), seuilsAvant,
          reason: 'seuils inchangés');
    });

    test('D-2 — la mémoire de travail (_pronostics) n\'est pas alimentée',
        () async {
      _installerStore();
      await _amorcer();
      final mem = IaMemoryService.instance;
      final nbAvant = mem.pronostics.length;

      await mem.enregistrerPronosticsPremiumDuJour([
        _premium(courseKey: 'R1C5_23042026'),
      ]);

      expect(mem.pronostics.length, nbAvant,
          reason: 'aucun pronostic créé par l\'enregistrement premium');
    });

    test('D-3 — une entrée absente n\'est jamais reconstituée', () async {
      // L'utilisateur n'a plus rien pour le 23/04 : A-2 ne doit rien créer.
      _installerStore();
      await _amorcer();
      final mem = IaMemoryService.instance;

      await mem.enregistrerPronosticsPremiumDuJour(
          [_premium(courseKey: 'R1C5_25042026')]);

      expect(mem.premiumsPourDate(2026, 4, 23), isEmpty,
          reason: 'A-2 n\'invente jamais une entrée pour un autre jour');
    });

    test('D-4 — un lot vide ou entièrement invalide n\'écrit rien', () async {
      _installerStore();
      await _amorcer();
      final mem = IaMemoryService.instance;

      await mem.enregistrerPronosticsPremiumDuJour(const <PremiumPronosticDuJour>[]);
      expect(store.contient(_kPremiumHistorique), isFalse);

      await mem.enregistrerPronosticsPremiumDuJour([
        _premium(courseKey: ''),
        _premium(courseKey: 'R1C1_'),
      ]);
      expect(store.contient(_kPremiumHistorique), isFalse,
          reason: 'aucune écriture pour un lot sans date valide');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  E — Cohérence écriture ↔ lecture (le défaut A-2 lui-même)
  // ═════════════════════════════════════════════════════════════════════════

  group('E — La date écrite est exactement celle que le lecteur consulte', () {
    test('E-1 — la clé de rangement respecte le format du lecteur', () {
      // Le lecteur `donneesCalendrierJour` construit sa clé ainsi
      // (ia_memory_service.dart:856) :
      //   '$annee-${mois.padLeft(2,'0')}-${jour.padLeft(2,'0')}'
      // et `premiumsPourDate` fait de même (l.5561).
      // A-2 doit produire EXACTEMENT ce format.
      for (final cas in <String, String>{
        'R1C5_23042026': '2026-04-23',
        'R2C3_05072026': '2026-07-05',
        'R1C1_01092026': '2026-09-01',
        'R9C9_2026-01-05': '2026-01-05',
      }.entries) {
        final extrait = dateDepuisCourseKey(cas.key);
        expect(extrait, cas.value);
        // Reproduit la construction du lecteur à partir des composantes.
        final parts = cas.value.split('-');
        final cleLecteur = '${parts[0]}-${parts[1]}-${parts[2]}';
        expect(extrait, cleLecteur,
            reason: 'format identique à donneesCalendrierJour l.856');
      }
    });

    test('E-2 — écriture puis lecture par la clé du lecteur', () async {
      _installerStore();
      await _amorcer();
      final mem = IaMemoryService.instance;

      // Une course datée du 23/04/2026, enregistrée alors que « aujourd'hui »
      // est un autre jour. C'est le scénario exact du défaut A-2.
      await mem.enregistrerPronosticsPremiumDuJour(
          [_premium(courseKey: 'R1C5_23042026')]);

      // Le lecteur, lui, calcule sa clé depuis `p.datePronostic`.
      final datePronostic = DateTime(2026, 4, 23);
      final cleLecteur = _ymd(datePronostic);

      expect(cleLecteur, '2026-04-23');
      expect(mem.premiumsPourDate(2026, 4, 23).length, 1,
          reason: 'écriture et lecture se rencontrent enfin');
      expect(mem.premiumsPourDate(2026, 4, 23).first.courseKey, 'R1C5_23042026');
    });
  });
}
