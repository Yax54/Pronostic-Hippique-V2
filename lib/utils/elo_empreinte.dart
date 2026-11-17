// ═══════════════════════════════════════════════════════════════════════════
//  elo_empreinte.dart — A7 / 3.3-A : EMPREINTE DÉTERMINISTE DES RATINGS ELO
//
//  RÔLE
//  ────
//  Produire une empreinte stable et NON AMBIGUË du contenu complet de
//  `elo_ratings_v2`, afin qu'un écart entre le disque et ce que le registre
//  `elo_registre_v3` déclare avoir laissé soit DÉTECTABLE.
//
//  CE QUE CE FICHIER NE FAIT PAS — À LIRE AVANT TOUT USAGE
//  ───────────────────────────────────────────────────────
//  • Il ne modifie AUCUN rating. Toutes les fonctions sont PURES et en
//    lecture seule.
//  • Il n'écrit aucune SharedPreferences, n'importe aucun service.
//  • Il ne sert JAMAIS à reconstruire des ratings, ni à identifier un contenu
//    parmi N : il vérifie UNE égalité.
//  • Une empreinte égale NE PROUVE PAS la durabilité physique de l'écriture.
//    `shared_preferences_android` écrit par `.apply()` (aucun `.commit()`
//    mesuré) : `setString → true` est une confirmation LOGIQUE, pas physique.
//
//  ALGORITHME DE HACHAGE — NOM EXACT
//  ─────────────────────────────────
//  Le nom « FNV-1a 64 bits » serait FAUX et n'est pas employé ici. Ce fichier
//  reproduit à l'identique le hash maison de `ia_archive_service.dart`
//  (l.584-600) : DEUX accumulateurs 32 bits, prime `0x01000193`, bases
//  `0x811c9dc5` et `0x7fed3c85`, sortie de 16 caractères hexadécimaux.
//  Ce n'est pas FNV-1a 64 (qui exige la prime 0x100000001b3 et un état 64 bits).
//
//  LIMITE STRUCTURELLE MESURÉE : l'accumulateur `a` ne consomme que
//  `unit & 0xff` (8 bits bas) ; seul `b` voit `unit >> 8`. La dispersion est
//  donc plus faible qu'un vrai 64 bits, sans effet sur le déterminisme.
//
//  LIMITES DE COLLISION — DÉCLARÉES SANS ATTÉNUATION
//  ─────────────────────────────────────────────────
//  • Espace de sortie : 2^64 = 1,845 × 10^19.
//  • Collision FORTUITE, n empreintes : P ≈ n²/2^65. Mesuré : 1 000 → 2,7e-14 ;
//    20 000 → 1,08e-11. Négligeable pour une comparaison d'égalité.
//  • Collision CHOISIE : un hash non cryptographique se casse en O(1).
//    Un fichier de sauvegarde FORGÉ peut donc porter une empreinte correcte
//    sur un contenu différent. L'empreinte protège contre l'ACCIDENT, jamais
//    contre l'INTENTION.
//  • L'empreinte ne PROUVE jamais qu'un contenu est « l'original » : elle
//    prouve seulement qu'il est ÉGAL à celui qu'on attendait.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:typed_data';

import '../models/zt_models.dart';

// ───────────────────────────────────────────────────────────────────────────
//  ENCODAGE CANONIQUE — POURQUOI UN PRÉFIXE DE LONGUEUR
//
//  Le schéma de clé du dépôt est AMBIGU (défaut préexistant, non introduit
//  ici) : `_cleNom()` ne filtre pas le séparateur `|`, donc
//    nom "A|B" + discipline "TROT_ATTELE"  →  "A|B|TROT_ATTELE"
//    nom "A"   + discipline "B|TROT_ATTELE" →  "A|B|TROT_ATTELE"
//  sont la MÊME chaîne. Une concaténation naïve `K + '|' + valeur` n'est donc
//  pas injective sur l'ensemble réel des clés.
//
//  `encoderChamp` préfixe la longueur, ce qui rend la concaténation injective :
//    enc("AB") + enc("C")  = "2:AB1:C"
//    enc("A")  + enc("BC") = "1:A2:BC"   → distincts
// ───────────────────────────────────────────────────────────────────────────

/// Encode un champ avec sa LONGUEUR en unités de code UTF-16.
///
/// Injectif : deux suites de champs différentes ne peuvent pas produire la
/// même chaîne, même si les champs contiennent `:`, `|`, `;` ou un saut de
/// ligne.
///
/// ⚠️ `String.length` compte les surrogates comme 2 unités. Les noms de
///    chevaux du domaine sont en latin étendu (aucun caractère hors BMP n'a
///    été mesuré) ; si un nom en contenait, l'encodage resterait DÉTERMINISTE
///    — il compterait simplement 2 unités. Aucun risque d'instabilité.
String encoderChamp(String valeur) => '${valeur.length}:$valeur';

/// Encode un mot de 32 bits non signé en 8 caractères hexadécimaux.
String _encoderMot32(int mot) => mot.toRadixString(16).padLeft(8, '0');

/// Représentation canonique des BITS IEEE 754 d'un `double`.
///
/// Produit 16 caractères hexadécimaux, sous forme de DEUX mots 32 bits NON
/// SIGNÉS. `getUint64` n'est jamais utilisé : mesuré, il rend un entier
/// SIGNÉ, donc un hexadécimal négatif pour tout `double` négatif
/// (`getUint64(-1512.5)` → `-4569005176060379136`, hex `-3f685e0000000000`).
///
/// Propriétés, toutes mesurées :
///   • `0.0`   → `0000000000000000`
///   • `-0.0`  → `8000000000000000`   ← DIFFÉRENTS : voir ci-dessous
///   • `NaN`, `±Infinity` → encodés SANS lever (aucune exception)
///   • `1512.5` et `1512.5000000000002` → DIFFÉRENTS au bit
///
/// ⚠️ AUCUNE NORMALISATION DU ZÉRO. Une normalisation `v == 0.0 ? 0.0 : v`
///    a été envisagée puis REJETÉE : elle rendrait `0.0` et `-0.0`
///    indiscernables, donc un disque portant `-0.0` face à une RAM portant
///    `0.0` produirait la MÊME empreinte — une divergence INVISIBLE,
///    c'est-à-dire un faux NÉGATIF (fail-open). Un faux positif (divergence
///    signalée à tort) est fail-closed, donc préférable.
String encoderReelBits(double valeur) {
  final octets = ByteData(8)..setFloat64(0, valeur, Endian.big);
  return _encoderMot32(octets.getUint32(0)) +
      _encoderMot32(octets.getUint32(4));
}

/// Représentation canonique complète d'une map de ratings.
///
/// Forme exacte :
/// ```
/// "<n>;" ++ concatène( pour chaque clé K de tri(keys) :
///     enc(K) ++ enc(hexBits(rating)) ++ enc(nbCourses) ++ enc(hexBits(var)) )
/// ```
///
/// • `tri` = `List<String>.sort()`, comparaison d'unités de code — STABLE.
///   Indispensable : mesuré, `jsonEncode` d'une `Map` DÉPEND de l'ordre
///   d'insertion (`{"Z":1,"A":2}` ≠ `{"A":2,"Z":1}`).
/// • Le compte de tête `"<n>;"` auto-délimite le domaine : deux maps de
///   tailles différentes ne peuvent pas produire la même chaîne par décalage.
String canoniqueRatings(Map<String, EloScore> ratings) {
  final cles = ratings.keys.toList()..sort();
  final tampon = StringBuffer()..write('${cles.length};');
  for (final cle in cles) {
    final score = ratings[cle]!;
    tampon
      ..write(encoderChamp(cle))
      ..write(encoderChamp(encoderReelBits(score.rating)))
      ..write(encoderChamp(score.nbCourses.toString()))
      ..write(encoderChamp(encoderReelBits(score.variationMois)));
  }
  return tampon.toString();
}

/// Hash maison à deux accumulateurs 32 bits — reproduit `ia_archive_service.dart`
/// l.584-600 à l'identique (constantes, ordre des opérations, masquage).
///
/// ⚠️ Un accumulateur 64 bits serait SIGNÉ en Dart : `0xFFFFFFFFFFFFFFFF`
///    vaut -1 et `toRadixString(16)` produirait une chaîne négative.
///    Deux mots de 32 bits garantissent exactement 16 caractères
///    hexadécimaux, déterministes d'une exécution à l'autre (jamais
///    `hashCode`).
String empreinte64Brut(String chaine) {
  const int p = 0x01000193;
  var a = 0x811c9dc5; // base FNV-1a 32
  var b = 0x7fed3c85; // second accumulateur, base distincte
  for (final unit in chaine.codeUnits) {
    a = ((a ^ (unit & 0xff)) * p) & 0xffffffff;
    b = ((b ^ (unit >> 8)) * p) & 0xffffffff;
    b = ((b ^ (unit & 0xff)) * p) & 0xffffffff;
  }
  return a.toRadixString(16).padLeft(8, '0') +
      b.toRadixString(16).padLeft(8, '0');
}

/// Empreinte déterministe d'une map de ratings ELO.
///
/// Sortie : 16 caractères hexadécimaux minuscules.
///
/// Cette fonction est PURE : elle ne lit ni n'écrit aucun état, ne modifie
/// aucun rating et ne peut pas lever, y compris sur `NaN` ou `±Infinity`.
String empreinte64Ratings(Map<String, EloScore> ratings) =>
    empreinte64Brut(canoniqueRatings(ratings));

/// Longueur en octets UTF-8 d'une chaîne — utilisée pour les seuils de
/// rétention du registre (mesurés en octets, pas en nombre d'entrées).
int octetsUtf8(String chaine) {
  var total = 0;
  for (final unit in chaine.codeUnits) {
    if (unit <= 0x7f) {
      total += 1;
    } else if (unit <= 0x7ff) {
      total += 2;
    } else {
      total += 3;
    }
  }
  return total;
}
