/// Identifiants stables des entités de connaissance.
///
/// Consigne §7 : « Privilégier les identifiants authentiques disponibles »,
/// « Distinguer les identités permanentes des attributs susceptibles de
/// changer », « Les noms normalisés ne doivent pas constituer une preuve
/// suffisante d'identité ».
///
/// Décision D-11 (validée avec conditions) : identifiant fournisseur lorsqu'il
/// existe et que sa stabilité est démontrée ; à défaut identité interne stable
/// avec alias ; **jamais** de fusion automatique sur le seul nom.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Niveau de confiance d'une identité. Il conditionne ce que l'on a le droit
/// de faire avec l'entité : une identité [provisoire] ne doit jamais alimenter
/// une statistique présentée comme complète, ni fusionner avec une autre.
enum NiveauIdentite {
  /// Identifiant fournisseur reconnu stable (ex. identifiant SIRE si exposé).
  fournisseur,

  /// Clé composite d'attributs durables (nom + année de naissance + sexe).
  composite,

  /// Entité créée sans preuve suffisante. Conservée, jamais fusionnée.
  provisoire,
}

/// Résultat de la résolution d'identité d'un cheval.
///
/// [id] est l'identifiant interne stable — il ne change jamais, même si le nom
/// du cheval est corrigé. C'est lui qui sert de clé étrangère partout.
class IdentiteCheval {
  const IdentiteCheval({
    required this.id,
    required this.nomNormalise,
    required this.niveau,
    this.idFournisseur,
    this.anneeNaissance,
    this.sexe,
    this.disciplineObservee,
  });

  /// Identifiant interne stable et immuable.
  final String id;

  /// Nom normalisé — **attribut**, pas identité (consigne §7).
  final String nomNormalise;

  final NiveauIdentite niveau;

  /// Identifiant authentique du fournisseur, s'il existe.
  final String? idFournisseur;

  final int? anneeNaissance;
  final String? sexe;

  /// Discipline observée. C'est un **contexte de performance**, jamais une
  /// composante de l'identité permanente (D-19 validé).
  final String? disciplineObservee;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'nom_normalise': nomNormalise,
        'niveau': niveau.name,
        'id_fournisseur': idFournisseur,
        'annee_naissance': anneeNaissance,
        'sexe': sexe,
        'discipline_observee': disciplineObservee,
      };
}

/// Normalise un nom pour comparaison — **jamais** pour prouver une identité.
///
/// Le résultat sert à rapprocher des candidats, jamais à décider seul d'une
/// fusion (consigne §7, D-11 : « Ne jamais fusionner automatiquement deux
/// chevaux sur la seule base de leur nom »).
String normaliserNom(String nom) {
  var s = nom.trim().toUpperCase();
  // Accents français les plus fréquents dans les noms de chevaux.
  const remplacements = <String, String>{
    'À': 'A', 'Â': 'A', 'Ä': 'A', 'Á': 'A', 'Ã': 'A', 'Å': 'A',
    'Ç': 'C',
    'È': 'E', 'É': 'E', 'Ê': 'E', 'Ë': 'E',
    'Ì': 'I', 'Í': 'I', 'Î': 'I', 'Ï': 'I',
    'Ñ': 'N',
    'Ò': 'O', 'Ó': 'O', 'Ô': 'O', 'Ö': 'O', 'Õ': 'O',
    'Ù': 'U', 'Ú': 'U', 'Û': 'U', 'Ü': 'U',
    'Ý': 'Y', 'Ÿ': 'Y',
    'Æ': 'AE', 'Œ': 'OE',
  };
  remplacements.forEach((k, v) => s = s.replaceAll(k, v));
  // Apostrophes et traits d'union deviennent des espaces, puis on compacte.
  s = s.replaceAll(RegExp(r"['’\-_\.]"), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

/// Construit une identité **provisoire** — état par défaut, sûr.
///
/// L'identifiant interne est dérivé d'une empreinte du nom normalisé complété
/// par les attributs disponibles. Il est **stable pour un même jeu d'attributs**
/// et **distinct** dès qu'un attribut diffère : deux chevaux homonymes d'années
/// de naissance différentes ne partagent donc pas le même identifiant.
///
/// Ce n'est **pas** une preuve d'identité : le niveau reste [provisoire].
String idInterneProvisoire({
  required String nom,
  int? anneeNaissance,
  String? sexe,
}) {
  final base = <String>[
    normaliserNom(nom),
    anneeNaissance?.toString() ?? '?',
    (sexe ?? '?').toUpperCase(),
  ].join('|');
  final h = sha256.convert(utf8.encode(base)).toString();
  return 'ch_${h.substring(0, 16)}';
}

/// Construit une identité de niveau [composite], utilisable pour alimenter des
/// statistiques **à condition d'indiquer la limite**.
///
/// Elle exige le nom **et** l'année de naissance : sans année de naissance, on
/// reste en [provisoire], car deux homonymes d'époques différentes seraient
/// sinon confondus.
IdentiteCheval identiteComposite({
  required String nom,
  int? anneeNaissance,
  String? sexe,
  String? disciplineObservee,
}) {
  final nomNorm = normaliserNom(nom);
  final id = idInterneProvisoire(
    nom: nom,
    anneeNaissance: anneeNaissance,
    sexe: sexe,
  );
  return IdentiteCheval(
    id: id,
    nomNormalise: nomNorm,
    niveau:
        anneeNaissance == null ? NiveauIdentite.provisoire : NiveauIdentite.composite,
    anneeNaissance: anneeNaissance,
    sexe: sexe,
    disciplineObservee: disciplineObservee,
  );
}

/// Construit une identité de niveau [fournisseur] à partir d'un identifiant
/// authentique. C'est le seul cas où l'identité est considérée comme prouvée.
IdentiteCheval identiteFournisseur({
  required String idFournisseur,
  required String nom,
  int? anneeNaissance,
  String? sexe,
  String? disciplineObservee,
}) {
  final h = sha256.convert(utf8.encode('fournisseur|$idFournisseur')).toString();
  return IdentiteCheval(
    id: 'ch_${h.substring(0, 16)}',
    nomNormalise: normaliserNom(nom),
    niveau: NiveauIdentite.fournisseur,
    idFournisseur: idFournisseur,
    anneeNaissance: anneeNaissance,
    sexe: sexe,
    disciplineObservee: disciplineObservee,
  );
}

/// Clé d'une course. La date **seule** ne suffit pas : deux journées peuvent
/// porter les mêmes numéros de réunion et de course (consigne §7 : « La date,
/// le numéro de réunion et le numéro de course doivent être correctement pris
/// en compte pour éviter les collisions entre journées »).
String cleCourse({
  required String dateCourse,
  required int reunion,
  required int course,
  String? hippodrome,
}) {
  final d = dateCourse.length >= 10 ? dateCourse.substring(0, 10) : dateCourse;
  final base = '$d|R$reunion|C$course|${(hippodrome ?? '').toUpperCase()}';
  final h = sha256.convert(utf8.encode(base)).toString();
  return 'co_${h.substring(0, 16)}';
}

/// Clé d'une participation : course + numéro de programme du cheval.
String cleParticipation({
  required String cleCourse_,
  required int numeroProgramme,
}) {
  final h = sha256
      .convert(utf8.encode('$cleCourse_|#${numeroProgramme.toString()}'))
      .toString();
  return 'pa_${h.substring(0, 16)}';
}

/// Clé d'une entité nommée (jockey, driver, entraîneur, hippodrome).
///
/// Le préfixe distingue les rôles : un même nom peut être jockey dans une
/// discipline et driver dans une autre (consigne §9 : « Distinguer jockey et
/// driver selon les disciplines »). Hippodrome et rôle ne sont donc pas
/// interchangeables.
String cleEntiteNommee({required String role, required String nom}) {
  final h = sha256
      .convert(utf8.encode('$role|${normaliserNom(nom)}'))
      .toString();
  return 'en_${h.substring(0, 16)}';
}
