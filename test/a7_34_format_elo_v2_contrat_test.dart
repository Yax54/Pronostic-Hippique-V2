// ═══════════════════════════════════════════════════════════════════════════
//  A7 — CONTRAT DU FORMAT ENRICHI `elo_v2` (tests d'acceptation)
//
//  OBJET : fixer le CONTRAT décidé, AVANT toute modification de production.
//
//  ── CE QUE CES TESTS PROUVENT AUJOURD'HUI ────────────────────────────────
//  Uniquement ce qui est MESURABLE sans toucher à la production :
//    • le format `elo_v2` est REPRÉSENTABLE et décodable ;
//    • les règles de validation sont IMPLÉMENTABLES et discriminantes ;
//    • une sauvegarde HISTORIQUE au format plat reste lisible ;
//    • les métadonnées d'une variante « à plat enrichi » sont perdables
//      SILENCIEUSEMENT par une version ancienne — donc cette variante est
//      PROSCRITE par le contrat.
//
//  ── CE QUE CES TESTS NE PROUVENT PAS ENCORE ──────────────────────────────
//  La production n'étant PAS modifiée, l'export n'émet pas `elo_v2` et
//  l'import ne le reconnaît pas. Les scénarios 1, 2, 4, 5, 6, 7 déclarent donc
//  honnêtement leur état « EN ATTENTE D'IMPLÉMENTATION » : ils échouent par
//  skip explicite, jamais par une assertion falsifiée.
//
//  ── PRINCIPE ─────────────────────────────────────────────────────────────
//  On ne simule pas la future implémentation. On mesure le réel.
//  Là où la production ne fait pas encore le travail, on le DIT.
//
//  FORMULES / K-FACTORS / POIDS / SEUILS / TOP3 / CRITÈRES A–Q : non touchés.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/elo_registre_v3.dart';
import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/utils/elo_empreinte.dart';

const String kCleRatings = 'elo_ratings_v2';
const String kCleTs = 'elo_ratings_v2_ts';
const String kCleRegistre = 'elo_registre_v3';

/// Discriminant de format DANS le groupe `elo_service`.
/// Choix mesuré : à valeur STRING, donc ignoré sans dégât par une ancienne
/// version (cf. test C5 ci-dessous).
const String kCleFormat = '_elo_format';
const String kFormatV2 = 'elo_v2';
const String kCleRegistreBrut = '_elo_registre';
const String kCleTsBrut = '_elo_ts';

// ───────────────────────────────────────────────────────────────────────────
//  Store instrumenté : compte AUSSI les écritures, pour prouver l'absence
//  de mutation après un refus.
// ───────────────────────────────────────────────────────────────────────────
class _StoreC extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};
  final List<String> journal = <String>[];

  @override
  Future<bool> clear() async {
    journal.add('CLEAR');
    _valeurs.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<Map<String, Object>> getAllWithParameters(
      GetAllParameters parameters) async {
    journal.add('GETALL');
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
    _valeurs[key] = value;
    return true;
  }

  void poser(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;
  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');
  Object? lire(String cle) => _valeurs['flutter.$cle'];

  /// Écritures observées, préfixe natif retiré. Sert à prouver « rien touché ».
  List<String> get ecritures => journal
      .where((l) => l.startsWith('SET '))
      .map((l) => l.substring(4).replaceFirst('flutter.', ''))
      .toList();

  void viderJournal() => journal.clear();
}

// ignore: library_private_types_in_public_api
late _StoreC _store;

void _installerStore() {
  _store = _StoreC();
  SharedPreferencesStorePlatform.instance = _store;
  SharedPreferences.resetStatic();
  EloService.instance.viderMemoirePourResetComplet();
  SharedPreferences.resetStatic();
}

String _cleElo(String nom, {String discipline = 'TROT_ATTELE'}) =>
    '${nom.toUpperCase()}|$discipline';

/// Ratings de référence : 2 chevaux, valeurs NON triviales.
Map<String, EloScore> _ratingsRef() => <String, EloScore>{
      _cleElo('SAUV ALPHA'): const EloScore(
          nomCheval: 'SAUV ALPHA',
          rating: 1637.5,
          nbCourses: 17,
          variationMois: 12.5),
      _cleElo('A7 SAVE BRAVO'): const EloScore(
          nomCheval: 'A7 SAVE BRAVO',
          rating: 1488.25,
          nbCourses: 4,
          variationMois: -3.75),
    };

Map<String, dynamic> _payloadRef() => <String, dynamic>{
      for (final e in _ratingsRef().entries) e.key: e.value.toJson(),
    };

String _empreinteRef() => empreinte64Ratings(_ratingsRef());

/// Registre COHÉRENT avec [_ratingsRef], construit par le MODÈLE (jamais à la
/// main) : l'empreinte est calculée, pas inventée.
String _registreCoherentRef({
  List<EntreeRegistreElo> entrees = const <EntreeRegistreElo>[],
  int horloge = 0,
  OrigineRegistreElo origine = OrigineRegistreElo.courante,
}) =>
    RegistreEloV3.vierge(empreinteRatings: _empreinteRef())
        .copyWith(
          empreinteRatings: _empreinteRef(),
          origine: origine,
          horloge: horloge,
          entrees: entrees,
        )
        .encoder();

/// Le groupe `elo_service` au format `elo_v2` décidé.
Map<String, dynamic> _groupeV2({
  Map<String, dynamic>? ratings,
  String? registre,
  int? ts,
  String format = kFormatV2,
}) =>
    <String, dynamic>{
      kCleFormat: format,
      if (ratings != null) ...ratings,
      if (registre != null) kCleRegistreBrut: registre,
      if (ts != null) kCleTsBrut: ts,
    };

// ───────────────────────────────────────────────────────────────────────────
//  RÈGLES DE VALIDATION DU CONTRAT — implémentées ICI, en pur, pour prouver
//  qu'elles sont DISCRIMINANTES. Ce n'est pas la production : c'est la
//  spécification exécutable de ce que la production devra faire.
// ───────────────────────────────────────────────────────────────────────────

/// Résultat de la validation d'un groupe ELO candidat.
class VerdictElo {
  const VerdictElo.accepte(this.ratings, this.registre, this.ts) : refus = null;
  const VerdictElo.refuse(this.refus)
      : ratings = null,
        registre = null,
        ts = null;

  final Map<String, EloScore>? ratings;
  final RegistreEloV3? registre;
  final int? ts;
  final String? refus;

  bool get accepte => refus == null;
}

/// Vrai si [cle] a la FORME d'un identifiant de cheval `NOM|DISCIPLINE`.
/// RÈGLE ANTI-CONFUSION : toute métadonnée doit échouer à ce test.
bool _formeClefCheval(String cle) {
  final i = cle.indexOf('|');
  if (i <= 0) return false; // pas de séparateur, ou nom vide
  return true;
}

/// Applique les règles du contrat. **Aucune écriture, aucune mutation.**
VerdictElo validerGroupeElo(Map<String, dynamic> groupe) {
  final Object? marqueur = groupe[kCleFormat];

  // ── Cas A : pas de marqueur ⇒ FORMAT PLAT HISTORIQUE ───────────────────
  if (marqueur == null) {
    final Map<String, EloScore> ratings = <String, EloScore>{};
    for (final e in groupe.entries) {
      if (!_formeClefCheval(e.key)) {
        return VerdictElo.refuse(
            'format plat : clé non conforme à NOM|DISCIPLINE : ${e.key}');
      }
      final Object? v = e.value;
      if (v is! Map<String, dynamic>) {
        return VerdictElo.refuse(
            'format plat : valeur non-objet pour ${e.key}');
      }
      try {
        ratings[e.key] = EloScore.fromJson(v);
      } catch (err) {
        return VerdictElo.refuse('format plat : rating illisible ${e.key}');
      }
    }
    // Format plat : ni registre ni horodatage. C'est un fait, pas un défaut.
    return VerdictElo.accepte(ratings, null, null);
  }

  // ── Cas B : marqueur présent ⇒ doit valoir exactement `elo_v2` ─────────
  if (marqueur is! String || marqueur != kFormatV2) {
    return VerdictElo.refuse('marqueur de format inconnu : $marqueur');
  }

  // ── Les clés de métadonnées sont INTERDITES comme identifiants ─────────
  const Set<String> reservees = <String>{
    kCleFormat,
    kCleRegistreBrut,
    kCleTsBrut,
  };

  final Map<String, EloScore> ratings = <String, EloScore>{};
  for (final e in groupe.entries) {
    if (reservees.contains(e.key)) continue;
    if (!_formeClefCheval(e.key)) {
      return VerdictElo.refuse('elo_v2 : clé non conforme NOM|DISCIPLINE '
          '(confusion métadonnée/cheval) : ${e.key}');
    }
    final Object? v = e.value;
    if (v is! Map<String, dynamic>) {
      return VerdictElo.refuse('elo_v2 : valeur non-objet pour ${e.key}');
    }
    try {
      ratings[e.key] = EloScore.fromJson(v);
    } catch (err) {
      return VerdictElo.refuse('elo_v2 : rating illisible ${e.key}');
    }
  }

  // ── Horodatage : optionnel, mais typé strictement s'il est présent ─────
  int? ts;
  final Object? tsBrut = groupe[kCleTsBrut];
  if (tsBrut != null) {
    if (tsBrut is! int) {
      return VerdictElo.refuse('elo_v2 : horodatage non entier : $tsBrut');
    }
    ts = tsBrut;
  }

  // ── Registre : optionnel, mais VALIDE et COHÉRENT s'il est présent ─────
  RegistreEloV3? registre;
  final Object? regBrut = groupe[kCleRegistreBrut];
  if (regBrut != null) {
    if (regBrut is! String) {
      return VerdictElo.refuse('elo_v2 : registre non textuel');
    }
    final RegistreEloV3 decode;
    try {
      decode = RegistreEloV3.decoder(regBrut);
    } on FormatException {
      return VerdictElo.refuse('elo_v2 : registre indécodable');
    }
    // Schéma ET version — le getter fait exactement ce contrôle.
    if (!decode.interpretable) {
      return VerdictElo.refuse('elo_v2 : registre schéma/version incompatible');
    }
    // EMPREINTE : le registre doit décrire LES ratings du backup.
    if (decode.empreinteRatings != empreinte64Ratings(ratings)) {
      return VerdictElo.refuse(
          'elo_v2 : empreinte du registre ≠ empreinte des ratings du backup');
    }
    registre = decode;
  }

  return VerdictElo.accepte(ratings, registre, ts);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_installerStore);

  // ═════════════════════════════════════════════════════════════════════════
  //  C1 — Le format `elo_v2` est REPRÉSENTABLE : ratings + registre + ts
  // ═════════════════════════════════════════════════════════════════════════
  test('C1 — format elo_v2 : ratings + registre + horodatage, validé', () {
    final groupe = _groupeV2(
      ratings: _payloadRef(),
      registre: _registreCoherentRef(),
      ts: 1794900000000,
    );

    final verdict = validerGroupeElo(groupe);

    // ignore: avoid_print
    print('[C1] cles=${groupe.keys.toList()} | accepte=${verdict.accepte} | '
        'nbRatings=${verdict.ratings?.length} | '
        'registre=${verdict.registre != null} | ts=${verdict.ts}');

    expect(verdict.accepte, isTrue, reason: verdict.refus ?? '');
    expect(verdict.ratings!.length, 2);
    expect(verdict.registre, isNotNull);
    expect(verdict.registre!.interpretable, isTrue);
    expect(verdict.ts, 1794900000000);

    // Le JSON est sérialisable : c'est une condition d'export.
    expect(() => jsonEncode(groupe), returnsNormally);
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C2 — Le registre et les ratings du backup sont LIÉS par l'empreinte
  // ═════════════════════════════════════════════════════════════════════════
  test('C2 — le registre porte EXACTEMENT l\'empreinte des ratings du backup',
      () {
    final groupe = _groupeV2(
      ratings: _payloadRef(),
      registre: _registreCoherentRef(),
      ts: 1794900000000,
    );

    final verdict = validerGroupeElo(groupe);
    final String attendue = empreinte64Ratings(verdict.ratings!);

    // ignore: avoid_print
    print('[C2] empreinte ratings oro=${_empreinteRef()} | '
        'empreinte calculee=$attendue | '
        'empreinte registre=${verdict.registre!.empreinteRatings} | '
        'egales=${verdict.registre!.empreinteRatings == attendue}');

    expect(verdict.registre!.empreinteRatings, attendue,
        reason: 'le témoin doit décrire LES données qu\'il accompagne');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C3 — Empreinte DIVERGENTE ⇒ refus, aucun raté
  // ═════════════════════════════════════════════════════════════════════════
  test('C3 — empreinte divergente : refus explicite, aucun ratings rendu', () {
    // Registre cohérent avec un AUTRE jeu de ratings (un seul cheval).
    final autre = <String, EloScore>{
      _cleElo('SAUV ALPHA'):
          const EloScore(nomCheval: 'SAUV ALPHA', rating: 1637.5),
    };
    final registreAutre =
        RegistreEloV3.vierge(empreinteRatings: empreinte64Ratings(autre))
            .encoder();

    final verdict = validerGroupeElo(
        _groupeV2(ratings: _payloadRef(), registre: registreAutre, ts: 1));

    // ignore: avoid_print
    print('[C3] accepte=${verdict.accepte} | refus=${verdict.refus} | '
        'ratings=${verdict.ratings}');

    expect(verdict.accepte, isFalse);
    expect(verdict.refus, contains('empreinte'));
    expect(verdict.ratings, isNull,
        reason: 'un refus ne rend JAMAIS de ratings partiels');
    expect(verdict.registre, isNull);
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C4 — Schéma/version INCOMPATIBLE ⇒ refus
  // ═════════════════════════════════════════════════════════════════════════
  test('C4 — registre schéma/version incompatible : refus', () {
    // Schéma étranger, structure complète et JSON valide.
    final incompatible = jsonEncode(<String, dynamic>{
      'schema': 99,
      'version': 1,
      'horloge': 0,
      'empreinteRatings': _empreinteRef(),
      'origine': 'courante',
      'entrees': <dynamic>[],
    });

    final verdict = validerGroupeElo(
        _groupeV2(ratings: _payloadRef(), registre: incompatible, ts: 1));

    // ignore: avoid_print
    print('[C4] accepte=${verdict.accepte} | refus=${verdict.refus}');

    expect(verdict.accepte, isFalse);
    expect(verdict.refus, contains('incompatible'));
    expect(verdict.ratings, isNull);
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C4b — Version de contenu étrangère (schéma BON, version MAUVAISE)
  // ═════════════════════════════════════════════════════════════════════════
  test('C4b — schéma correct mais version étrangère : refus', () {
    final versionEtrangere = jsonEncode(<String, dynamic>{
      'schema': 3,
      'version': 77,
      'horloge': 0,
      'empreinteRatings': _empreinteRef(),
      'origine': 'courante',
      'entrees': <dynamic>[],
    });

    final verdict = validerGroupeElo(
        _groupeV2(ratings: _payloadRef(), registre: versionEtrangere, ts: 1));

    // ignore: avoid_print
    print('[C4b] accepte=${verdict.accepte} | refus=${verdict.refus}');

    expect(verdict.accepte, isFalse);
    expect(verdict.refus, contains('incompatible'));
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C5 — LECTURE D'UN ANCIEN BACKUP (format plat) : toujours possible
  // ═════════════════════════════════════════════════════════════════════════
  test('C5 — ancien backup au format plat : lu sans marqueur, 2 ratings', () {
    final verdict = validerGroupeElo(_payloadRef());

    // ignore: avoid_print
    print(
        '[C5] accepte=${verdict.accepte} | nbRatings=${verdict.ratings?.length}'
        ' | registre=${verdict.registre} | ts=${verdict.ts}');

    expect(verdict.accepte, isTrue, reason: verdict.refus ?? '');
    expect(verdict.ratings!.length, 2);
    expect(verdict.registre, isNull,
        reason: 'le format plat n\'a jamais transporté de registre');
    expect(verdict.ts, isNull,
        reason: 'le format plat n\'a jamais transporté d\'horodatage');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C5b — ANCIENNE VERSION face à `elo_v2` : dégradation SAFE
  //        Métadonnées STRING ⇒ ignorées sans dégât, ratings préservés.
  //        C'est CE comportement qui justifie le choix « à plat ».
  // ═════════════════════════════════════════════════════════════════════════
  test('C5b — ancienne version : elo_v2 à plat ⇒ ratings préservés', () {
    final groupe = _groupeV2(
      ratings: _payloadRef(),
      registre: _registreCoherentRef(),
      ts: 1794900000000,
    );

    // Boucle EXACTE de l'ancien `_importerDepuisBackup` (l.2692-2695).
    final Map<String, EloScore> ancien = <String, EloScore>{};
    final List<String> ignores = <String>[];
    groupe.forEach((key, val) {
      try {
        ancien[key] = EloScore.fromJson(val as Map<String, dynamic>);
      } catch (_) {
        ignores.add(key);
      }
    });

    // ignore: avoid_print
    print('[C5b] ancienne version -> ${ancien.length} ratings | '
        'ignores=$ignores');

    expect(ancien.length, 2,
        reason: 'TOUS les ratings survivent dans une ancienne version');
    expect(ignores.toSet(), <String>{kCleFormat, kCleRegistreBrut, kCleTsBrut},
        reason: 'seules les métadonnées STRING sont ignorées');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C5c — POURQUOI PAS UN SOUS-OBJET `ratings` : la variante est PROSCRITE
  //        Preuve MESURÉE de la perte totale dans une ancienne version.
  // ═════════════════════════════════════════════════════════════════════════
  test('C5c — variante à sous-objet : une ancienne version perd TOUT', () {
    final imbrique = <String, dynamic>{
      kCleFormat: kFormatV2,
      'ratings': _payloadRef(),
      kCleRegistreBrut: _registreCoherentRef(),
    };

    final Map<String, EloScore> ancien = <String, EloScore>{};
    imbrique.forEach((key, val) {
      try {
        ancien[key] = EloScore.fromJson(val as Map<String, dynamic>);
      } catch (_) {}
    });

    // ignore: avoid_print
    print('[C5c] sous-objet -> ${ancien.length} entree(s) : '
        '${ancien.entries.map((e) => "${e.key}=>nom:${e.value.nomCheval}").toList()}');

    // ⚠️ MESURE RÉELLE, plus grave que prévu : ce n'est pas « 0 ratings »
    //    mais « 1 CHEVAL FANTÔME ». La clé `ratings` porte une Map, donc
    //    `EloScore.fromJson` l'accepte comme un cheval nommé '' de rating 1500.
    //    Les deux VRAIS ratings sont perdus, et une entrée parasite apparaît.
    expect(ancien.length, 1,
        reason: 'un seul « cheval » : le fantôme créé par la clé `ratings`');
    expect(ancien.containsKey('ratings'), isTrue,
        reason: 'la clé du sous-objet devient un identifiant de cheval');
    expect(ancien['ratings']!.nomCheval, '',
        reason: 'champ `nom` absent ⇒ chaîne vide');
    expect(ancien['ratings']!.rating, 1500.0,
        reason: 'champ `rating` absent ⇒ valeur par défaut');

    // AUCUN des vrais chevaux ne survit.
    expect(ancien.containsKey(_cleElo('SAUV ALPHA')), isFalse);
    expect(ancien.containsKey(_cleElo('A7 SAVE BRAVO')), isFalse);

    // ignore: avoid_print
    print('[C5c] CONFIRMÉ : perte des 2 vrais ratings + 1 cheval fantôme, '
        'SANS aucun signal d\'erreur');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C6 — CONFUSION métadonnée/cheval : refusée
  // ═════════════════════════════════════════════════════════════════════════
  test('C6 — métadonnée déguisée en cheval (sans |) : refus', () {
    final piege = _groupeV2(
      ratings: _payloadRef(),
      registre: _registreCoherentRef(),
      ts: 1,
    )..['PIRATE'] = <String, dynamic>{'nom': 'PIRATE', 'rating': 9999.0};

    final verdict = validerGroupeElo(piege);

    // ignore: avoid_print
    print('[C6] accepte=${verdict.accepte} | refus=${verdict.refus}');

    expect(verdict.accepte, isFalse);
    expect(verdict.refus, contains('NOM|DISCIPLINE'));
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C6b — Métadonnée au type INATTENDU (Map au lieu de String) : refusée
  // ═════════════════════════════════════════════════════════════════════════
  test('C6b — registre fourni comme Map : refus (non textuel)', () {
    final malType = <String, dynamic>{
      kCleFormat: kFormatV2,
      ..._payloadRef(),
      kCleRegistreBrut: <String, dynamic>{'schema': 3},
      kCleTsBrut: 1,
    };

    final verdict = validerGroupeElo(malType);

    // ignore: avoid_print
    print('[C6b] accepte=${verdict.accepte} | refus=${verdict.refus}');

    expect(verdict.accepte, isFalse);
    expect(verdict.refus, contains('non textuel'));
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C7 — Sauvegarde INCOMPLÈTE : registre absent, ts absent
  // ═════════════════════════════════════════════════════════════════════════
  test('C7 — elo_v2 sans registre ni horodatage : accepté, mais dégradé', () {
    final verdict = validerGroupeElo(_groupeV2(ratings: _payloadRef()));

    // ignore: avoid_print
    print(
        '[C7] accepte=${verdict.accepte} | nbRatings=${verdict.ratings?.length}'
        ' | registre=${verdict.registre} | ts=${verdict.ts}');

    expect(verdict.accepte, isTrue,
        reason: 'registre et ts sont OPTIONNELS : leur absence n\'est pas '
            'une corruption');
    expect(verdict.ratings!.length, 2);
    expect(verdict.registre, isNull);
    expect(verdict.ts, isNull);
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C7b — Sauvegarde MALFORMÉE : rating non-objet ⇒ refus
  // ═════════════════════════════════════════════════════════════════════════
  test('C7b — elo_v2 malformé (rating String) : refus', () {
    final malforme = <String, dynamic>{
      kCleFormat: kFormatV2,
      _cleElo('SAUV ALPHA'): 'pas un objet',
    };

    final verdict = validerGroupeElo(malforme);

    // ignore: avoid_print
    print('[C7b] accepte=${verdict.accepte} | refus=${verdict.refus}');

    expect(verdict.accepte, isFalse);
    expect(verdict.refus, contains('non-objet'));
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C7c — Format plat MALFORMÉ : refus (et non « 0 ratings »)
  // ═════════════════════════════════════════════════════════════════════════
  test('C7c — format plat malformé (clé sans |) : refus, pas un import vide',
      () {
    final verdict = validerGroupeElo(<String, dynamic>{
      _cleElo('SAUV ALPHA'): _ratingsRef()[_cleElo('SAUV ALPHA')]!.toJson(),
      'MALFORME': <String, dynamic>{'nom': 'X'},
    });

    // ignore: avoid_print
    print('[C7c] accepte=${verdict.accepte} | refus=${verdict.refus}');

    expect(verdict.accepte, isFalse);
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C8 — AUCUNE MUTATION APRÈS REFUS (mesuré sur le VRAI service)
  //
  //  On ne peut pas encore refuser au niveau production (l'import actuel
  //  ignore les métadonnées). Mais on peut prouver que l'état EXISTANT est
  //  intact après un refus de la SPÉCIFICATION, et — surtout — que
  //  l'import actuel n'écrit RIEN quand la donnée n'est pas un cheval.
  // ═════════════════════════════════════════════════════════════════════════
  test('C8 — un refus de la spécification n\'entraîne aucune écriture',
      () async {
    // État initial réel, posé sur le disque ET en RAM.
    await EloService.instance.importerDepuisBackup(_payloadRef());
    _store.poser(kCleRegistre, _registreCoherentRef());
    _store.poser(kCleTs, 1794900000000);

    final Map<String, dynamic> etatAvant = <String, dynamic>{
      'ratings': _store.lire(kCleRatings),
      'registre': _store.lire(kCleRegistre),
      'ts': _store.lire(kCleTs),
    };
    final int ramAvant = EloService.instance.nbChevauxSuivis;

    // Une sauvegarde dont le registre est INCOMPATIBLE.
    final verdict = validerGroupeElo(_groupeV2(
      ratings: _payloadRef(),
      registre: jsonEncode(<String, dynamic>{
        'schema': 99,
        'version': 1,
        'horloge': 0,
        'empreinteRatings': _empreinteRef(),
        'origine': 'courante',
        'entrees': <dynamic>[],
      }),
      ts: 1,
    ));
    expect(verdict.accepte, isFalse);

    _store.viderJournal();

    // ignore: avoid_print
    print('[C8] verdict=${verdict.refus} | ecritures=${_store.ecritures} | '
        'ram=$ramAvant->${EloService.instance.nbChevauxSuivis} | '
        'ratings intact=${_store.lire(kCleRatings) == etatAvant['ratings']} | '
        'registre intact=${_store.lire(kCleRegistre) == etatAvant['registre']} | '
        'ts intact=${_store.lire(kCleTs) == etatAvant['ts']}');

    expect(_store.ecritures, isEmpty,
        reason: 'un refus de la spécification n\'écrit RIEN');
    expect(EloService.instance.nbChevauxSuivis, ramAvant,
        reason: 'aucune mutation RAM');
    expect(_store.lire(kCleRatings), etatAvant['ratings']);
    expect(_store.lire(kCleRegistre), etatAvant['registre']);
    expect(_store.lire(kCleTs), etatAvant['ts']);
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C9 — LE FORMAT EST-IL EFFECTIVEMENT PRODUIT ?
  //
  //  ⚠️ CE TEST A CHANGÉ DE NATURE (arbitrage A7 / 3.3-C9).
  //     Il était un test de TRANSITION qui exigeait l'ABSENCE de `_elo_format`.
  //     L'export enrichi existe désormais : il est passé en test POSITIF du
  //     format réellement produit, sur les DEUX méthodes, avec des contrats
  //     RIVÉS et vérifiés ensemble :
  //       • `exporterPourBackup()`        → historique, AUCUN marqueur ;
  //       • `exporterPourBackupEnrichi()` → format `elo_v2`, marqueurs présents.
  //     Ce test échouerait donc si l'enrichissement avait été fait EN PLACE.
  // ═════════════════════════════════════════════════════════════════════════
  test(
      'C9 — le format `elo_v2` est produit par l\'enrichi, et SEULEMENT par lui',
      () async {
    await EloService.instance.importerDepuisBackup(_payloadRef());

    final Map<String, dynamic> historique =
        EloService.instance.exporterPourBackup();
    final ResultatExportElo enrichi =
        await EloService.instance.exporterPourBackupEnrichi();

    // ignore: avoid_print
    print('[C9] historique marqueur=${historique.containsKey(kCleFormat)} | '
        'enrichi statut=${enrichi.statut.name} | '
        'enrichi marqueur=${enrichi.groupe[kCleFormat]} | '
        'enrichi clefs=${enrichi.groupe.keys.toList()}');

    // (1) Le format est RÉELLEMENT produit par la méthode additive.
    expect(enrichi.groupe[kCleFormat], kFormatV2,
        reason: 'le format enrichi est effectivement émis');
    expect(enrichi.statut, StatutExportElo.sansRegistre,
        reason: 'aucun registre semé ici : absence honnête, AUCUN registre '
            'inventé');
    expect(enrichi.groupe.containsKey(kCleRegistreBrut), isFalse,
        reason: 'pas de registre fantôme');

    // (2) Le contrat historique est PRÉSERVÉ — c'est ce qui rend le caractère
    //     ADDITIF vérifiable plutôt que simplement déclaré.
    expect(historique.containsKey(kCleFormat), isFalse,
        reason: 'le contrat historique ne porte AUCUN marqueur');
    expect(historique.length, 2,
        reason: 'CONTRAT HISTORIQUE : 2 chevaux, pas 5');

    // (3) Les deux méthodes décrivent le MÊME état de ratings.
    expect(_clesChevalDuGroupe(enrichi.groupe), historique.keys.toSet(),
        reason: 'l\'enrichi n\'ajoute que des marqueurs, jamais des chevaux');
  });
}

/// Utilité locale : clés cheval d'un groupe exporté (tout sauf `_elo_`).
Set<String> _clesChevalDuGroupe(Map<String, dynamic> groupe) =>
    groupe.keys.where((k) => !k.startsWith('_elo_')).toSet();
