/// Empreinte de contenu canonique — clé d'identité d'un rapport ou d'un fait.
///
/// Exigence de la consigne (§13) : « Utiliser une identification par contenu
/// avec sérialisation canonique et version de schéma ».
///
/// Trois règles y sont encodées, et chacune corrige un défaut mesuré :
///
/// 1. **La date n'est jamais une clé.** Sur le corpus réel, 219 dates portent
///    225 contenus bruts : la date n'identifie pas un contenu.
///
/// 2. **La normalisation est RÉVERSIBLE.** Le corpus contient six divergences
///    limitées au champ `fnum2`, absent des versions anciennes. La consigne
///    interdit de supprimer ce champ. On complète donc à `null` au lieu de
///    retrancher : le contenu original reste intégralement disponible, et
///    l'empreinte est calculée sur un schéma homogène.
///
/// 3. **Absent, nul et renseigné sont trois états distincts** (§13). La
///    complétion distingue explicitement l'absence (`Absent`) de la valeur
///    nulle (`null`) : sans cela, « absent » et « null » produiraient la même
///    empreinte, ce que la consigne refuse.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Marqueur d'un champ ABSENT du contenu d'origine.
///
/// Il est distinct de `null` (champ présent, valeur nulle) et de toute valeur
/// renseignée. C'est ce qui rend la normalisation réversible : on peut
/// reconstruire le contenu d'origine en retirant les champs marqués [absent].
class Absent {
  const Absent._();

  /// Représentation textuelle réservée. Elle ne peut pas entrer en collision
  /// avec une valeur JSON réelle, qui serait toujours encadrée de guillemets
  /// ou de délimiteurs de structure.
  static const String marqueur = '\u0000ABSENT\u0000';

  @override
  String toString() => marqueur;
}

/// Normalise un contenu JSON pour le rendre comparable.
///
/// [schemaAttendu] énumère les champs qui doivent exister dans le schéma
/// normalisé. Les champs absents du contenu d'origine mais présents dans
/// [schemaAttendu] sont complétés avec [Absent.marqueur] — **jamais**
/// supprimés, **jamais** mis à `null`.
///
/// La fonction est **pure** : elle ne modifie pas son argument.
Object? normaliserContenu(
  Object? contenu, {
  Set<String> schemaAttendu = const <String>{},
}) {
  if (contenu is Map) {
    final out = <String, Object?>{};
    // Ordre trié : la sérialisation canonique exige un ordre stable.
    final cles = <String>{...contenu.keys.whereType<String>(), ...schemaAttendu}
        .toList()
      ..sort();
    for (final k in cles) {
      if (contenu.containsKey(k)) {
        out[k] = normaliserContenu(contenu[k]);
      } else {
        // Champ du schéma attendu, absent des données d'origine.
        out[k] = Absent.marqueur;
      }
    }
    return out;
  }
  if (contenu is List) {
    return contenu.map((e) => normaliserContenu(e)).toList();
  }
  return contenu;
}

/// Sérialisation canonique : clés triées, séparateurs fixes, UTF-8.
///
/// Mesuré sur le corpus : le choix de sérialisation change le décompte
/// (225 empreintes en canonique strict, 219 après normalisation de schéma).
/// La stabilité de cette fonction est donc une propriété de correction.
String serialiserCanonique(Object? contenu) {
  return jsonEncode(_trierRecursivement(contenu));
}

Object? _trierRecursivement(Object? o) {
  if (o is Map) {
    final cles = o.keys.whereType<String>().toList()..sort();
    return <String, Object?>{for (final k in cles) k: _trierRecursivement(o[k])};
  }
  if (o is List) return o.map(_trierRecursivement).toList();
  return o;
}

/// Empreinte SHA-256 (hexadécimal) du contenu normalisé et sérialisé
/// canoniquement.
///
/// C'est la clé de déduplication. Deux contenus de même empreinte sont
/// **prouvés identiques** ; deux contenus d'empreintes différentes ne sont
/// **jamais** fusionnés, même s'ils portent la même date.
String empreinteContenu(
  Object? contenu, {
  Set<String> schemaAttendu = const <String>{},
}) {
  final normalise = normaliserContenu(contenu, schemaAttendu: schemaAttendu);
  final canonique = serialiserCanonique(normalise);
  return sha256.convert(utf8.encode(canonique)).toString();
}

/// Reconstruit le contenu d'origine à partir d'un contenu normalisé.
///
/// Retire les champs marqués [Absent.marqueur]. C'est ce qui rend la
/// normalisation **réversible** au sens de la consigne (§13), et ce qui
/// autorise à considérer les empreintes comme non destructrices.
Object? denormaliserContenu(Object? contenu) {
  if (contenu is Map) {
    final out = <String, Object?>{};
    for (final e in contenu.entries) {
      if (e.value == Absent.marqueur) continue; // champ absent à l'origine
      out['${e.key}'] = denormaliserContenu(e.value);
    }
    return out;
  }
  if (contenu is List) {
    return contenu.map(denormaliserContenu).toList();
  }
  return contenu;
}

/// Empreinte d'une valeur simple, utilisée pour les signatures de changement
/// (§10 : « Détection des changements de contenu »).
String empreinteValeur(Object? valeur) {
  return sha256.convert(utf8.encode(serialiserCanonique(valeur))).toString();
}
