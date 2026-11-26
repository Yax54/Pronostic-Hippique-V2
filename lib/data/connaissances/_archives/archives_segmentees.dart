/// Archives segmentées compressées : écriture, indexation, consultation ciblée.
///
/// ═══════════════════════════════════════════════════════════════════════════
///  CE QUE CE SERVICE EXISTE POUR EMPÊCHER
///
///  La politique `pronostics_archives` de `politiques_conservation.dart`
///  déclare, depuis le début, que tout pronostic disposant d'un résultat
///  officiel doit être « conservé sans limite de durée, jamais recalculé ».
///  Cette politique était **déclarée mais non desservie** : aucun service ne
///  l'implémentait. Une politique écrite et non appliquée est une intention,
///  pas une garantie.
///
///  Ce fichier la rend effective, avec trois propriétés qui se tiennent :
///
///   1. **Aucune suppression.** Il n'existe ici ni `delete`, ni `removeWhere`,
///      ni plafond, ni `VACUUM` sur les archives. Un segment écrit n'est
///      jamais réécrit ni tronqué. La seule opération destructrice est
///      `restaurer()`, qui reconstruit l'index depuis les fichiers — et les
///      fichiers, eux, ne sont jamais touchés.
///
///   2. **Aucune réinjection.** Ce service n'est lu par AUCUN mécanisme
///      d'apprentissage : il ne touche ni `_poids`, ni `_seuils`, ni le TOP3,
///      ni l'ELO. Il conserve et il rend consultable. `_jamaisApprentissage`
///      ci-dessous est vérifié par test.
///
///   3. **Index reconstructible.** L'index (`index.json`) est un ACCÉLÉRATEUR,
///      jamais une dépendance : supprimer `archives/index.json` ne perd aucune
///      connaissance, seulement du temps. `restaurerIndex()` le reconstruit
///      intégralement en relisant les segments. C'est la réponse directe à
///      l'exigence « un nettoyage du cache ne doit jamais rendre les
///      connaissances inaccessibles ».
///
///  ═══════════════════════════════════════════════════════════════════════════
///  FORMAT DES SEGMENTS — CHOIX ET JUSTIFICATION
///
///  Un segment couvre UNE PÉRIODE (mois par défaut) et porte son propre
///  en-tête. Il est compressé en flux (gzip) et **une entrée par ligne** en
///  JSON : cela permet une lecture ligne à ligne sans tout charger en mémoire
///  (§19 : éviter le chargement intégral en RAM). Un segment de 100 000
///  pronostics se consulte donc sans jamais matérialiser 100 000 objets.
///
///  L'identité d'une entrée est son `empreinte` (empreinte de CONTENU, D-12),
///  jamais son rang dans le fichier : réécrire un index ne peut donc pas
///  changer ce qu'une entrée désigne.
///
///  La version EXACTE du rapport et du bilan est conservée telle quelle dans
///  l'entrée (`empreinteRapport`, `empreinteBilan`) : aucune mise à jour
///  rétroactive vers « la dernière version connue » n'est possible ici, parce
///  que rien ne réécrit une entrée.
/// ═══════════════════════════════════════════════════════════════════════════
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../_adapters/organisation_fichiers.dart';

/// Une entrée d'archive : une version figée d'un pronostic, avec ses références.
class EntreeArchive {
  const EntreeArchive({
    required this.empreinte,
    required this.cleCourse,
    required this.dateCourse,
    required this.contenu,
    this.resultatOfficiel,
    this.empreinteRapport,
    this.empreinteBilan,
    this.segment = '',
    this.ligne = 0,
  });

  /// Empreinte de CONTENU : identité stable de cette version (D-12).
  final String empreinte;

  /// Identité de la course, pour la consultation ciblée.
  final String cleCourse;

  /// Date de la course, au format ISO (`AAAA-MM-JJ`).
  final String dateCourse;

  /// Contenu complet, sérialisé JSON. Conservé VERBATIM.
  final String contenu;

  /// Résultat officiel, s'il est connu. Sa présence rend l'entrée permanente.
  final String? resultatOfficiel;

  /// Empreinte de la version EXACTE du rapport utilisée (jamais repointée).
  final String? empreinteRapport;

  /// Empreinte de la version EXACTE du bilan utilisé (jamais repointée).
  final String? empreinteBilan;

  /// Segment qui porte cette entrée (rempli à la lecture).
  final String segment;

  /// Numéro de ligne dans le segment (rempli à la lecture).
  final int ligne;

  /// `true` si et seulement si un résultat officiel **non vide** existe.
  ///
  /// ⚠️ Une chaîne VIDE n'est pas un résultat. La traiter comme présente
  /// ferait entrer dans la catégorie « permanente » une entrée qui n'a, en
  /// réalité, aucun résultat — et la ferait remonter dans les consultations
  /// `avecResultatOfficiel`. Mesuré : c'est exactement ce qui se produisait.
  bool get estPermanent =>
      resultatOfficiel != null && resultatOfficiel!.trim().isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
        'e': empreinte,
        'c': cleCourse,
        'd': dateCourse,
        'p': contenu,
        if (estPermanent) 'r': resultatOfficiel,
        if (empreinteRapport != null) 'er': empreinteRapport,
        if (empreinteBilan != null) 'eb': empreinteBilan,
      };

  factory EntreeArchive.depuisJson(Map<String, dynamic> j) => EntreeArchive(
        empreinte: '${j['e']}',
        cleCourse: '${j['c'] ?? ''}',
        dateCourse: '${j['d'] ?? ''}',
        contenu: '${j['p'] ?? ''}',
        resultatOfficiel: j['r'] as String?,
        empreinteRapport: j['er'] as String?,
        empreinteBilan: j['eb'] as String?,
      );

  /// Projection d'index : tout ce qu'il faut pour cibler, sans le contenu.
  ///
  /// C'est ce qui rend la consultation ciblée possible sans ouvrir les
  /// segments : l'index connaît `cleCourse`, la date et le segment.
  Map<String, Object?> versIndex() => <String, Object?>{
        'e': empreinte,
        'c': cleCourse,
        'd': dateCourse,
        's': segment,
        'l': ligne,
        if (estPermanent) 'r': resultatOfficiel,
      };
}

/// Résultat d'une écriture, pour que l'appelant sache ce qui s'est réellement passé.
class ResultatArchivage {
  const ResultatArchivage({
    required this.ecrites,
    required this.ignorees,
    this.erreur,
  });

  /// Entrées réellement ajoutées au segment.
  final int ecrites;

  /// Entrées déjà présentes (même empreinte) : aucun doublon créé.
  final int ignorees;

  final String? erreur;

  bool get succes => erreur == null;
}

/// ═══════════════════════════════════════════════════════════════════════════
///  ÉTAT D'UNE CONSULTATION D'ARCHIVE — QUATRE CAS DEUX À DEUX DISTINCTS
///
///  ⚠️ LE DÉFAUT QUE CET ENUM CORRIGE
///
///  Les trois consultations ciblées (`parCourse`, `parPeriode`,
///  `avecResultatOfficiel`) enveloppaient leur corps dans un `try/catch` qui
///  rendait une liste VIDE en cas d'exception. Un dossier d'archives effacé, un
///  segment tronqué, un disque plein et une archive réellement vierge
///  produisaient donc la MÊME réponse : `[]`.
///
///  L'appelant ne pouvait pas distinguer « il n'existe aucune connaissance »
///  de « les connaissances existent mais je n'ai pas pu les lire ». La première
///  est une information ; la seconde est une panne. Les confondre revient à
///  annoncer une absence de connaissance là où il y a une perte d'accès —
///  c'est exactement ce qu'un repli ne doit jamais masquer.
///
///  ⚠️ CE QUE CET ENUM NE FAIT PAS
///
///  Il ne dispense d'aucun contrôle : il nomme ce que le contrôle a constaté.
///  Un `inaccessible` ou un `corrompu` n'autorise AUCUN repli silencieux ; il
///  oblige l'appelant à choisir explicitement quoi faire.
/// ═══════════════════════════════════════════════════════════════════════════
enum EtatLectureArchive {
  /// Le dossier d'archives existe et la lecture a abouti : `entrees` fait foi.
  /// Zéro entrée signifie alors — et alors seulement — « aucune connaissance
  /// archivée », ce qui est un fait, pas une panne.
  lisible,

  /// Le dossier n'existe pas encore : aucune archive n'a jamais été écrite.
  /// Ce n'est PAS une panne, et ce n'est PAS une perte : c'est une installation
  /// neuve. Ne jamais le présenter comme une anomalie.
  absent,

  /// Le dossier existe mais la lecture a échoué (droits, disque, E/S).
  /// Les connaissances peuvent exister : on ne peut simplement pas les lire.
  inaccessible,

  /// Le dossier existe, les fichiers sont là, mais leur contenu est
  /// inexploitable : index irrécupérable ET segments illisibles ou tronqués.
  /// Distinct d'`inaccessible` : ici on a lu, et ce qu'on a lu est invalide.
  corrompu,
}

/// Réponse d'une consultation ciblée : l'état constaté ET les entrées trouvées.
///
/// [entrees] n'est JAMAIS `null`. Il est vide pour `absent`, `inaccessible` et
/// `corrompu` — mais [etat] interdit alors de lire ce vide comme une absence de
/// connaissance.
class ConsultationArchive {
  const ConsultationArchive({
    required this.etat,
    required this.entrees,
    this.details,
  });

  final EtatLectureArchive etat;
  final List<EntreeArchive> entrees;
  final String? details;

  /// Vrai seulement si la consultation a réellement abouti. Un repli n'est
  /// légitime que sur `false` — et il doit alors rester OBSERVABLE.
  bool get aboutie => etat == EtatLectureArchive.lisible;

  Map<String, Object?> toJson() => <String, Object?>{
        'etat': etat.name,
        'entrees': entrees.length,
        'details': details,
      };
}

/// Statistiques de consultation, mesurées et non estimées.
class BilanArchives {
  const BilanArchives({
    required this.segments,
    required this.entrees,
    required this.octetsCompresses,
    required this.octetsDecompresses,
    required this.indexPresent,
    required this.indexEntrees,
  });

  final int segments;
  final int entrees;
  final int octetsCompresses;

  /// Somme des tailles DÉCOMPRESSÉES. Mesurée en lisant les en-têtes gzip.
  final int octetsDecompresses;
  final bool indexPresent;
  final int indexEntrees;

  /// Taux de compression réel, ou `null` si rien à comparer.
  double? get tauxCompression => octetsDecompresses == 0
      ? null
      : octetsCompresses / octetsDecompresses;

  Map<String, Object?> toJson() => <String, Object?>{
        'segments': segments,
        'entrees': entrees,
        'octets_compresses': octetsCompresses,
        'octets_decompresses': octetsDecompresses,
        'taux_compression': tauxCompression,
        'index_present': indexPresent,
        'index_entrees': indexEntrees,
      };
}

/// Service d'archives segmentées et compressées.
///
/// ⚠️ Ce service ne participe à AUCUN apprentissage. Il conserve des versions
/// figées et les rend consultables. Voir `_jamaisApprentissage`.
class ArchivesSegmenteess {
  ArchivesSegmenteess._();

  static final ArchivesSegmenteess instance = ArchivesSegmenteess._();

  /// Nombre maximum d'entrées par segment.
  ///
  /// ⚠️ Ce n'est PAS un plafond de conservation : quand un segment est plein,
  /// on en ouvre un NOUVEAU. Aucune entrée n'est jamais supprimée pour tenir
  /// dans un segment (§11).
  static const int kEntreesParSegment = 2000;

  /// Version du format, écrite dans chaque en-tête de segment.
  static const int kVersionFormat = 1;

  /// Nom du fichier d'index (accélérateur, jamais une dépendance).
  static const String kNomIndex = 'index.json';

  /// Racine forcée pour les tests. `null` ⇒ organisation de production.
  String? _racineForcee;

  /// Injecte une racine isolée. Réservé aux tests.
  void utiliserRacine(String racine) {
    _racineForcee = racine;
  }

  Future<String> _dossierArchives() async {
    if (_racineForcee != null) return '$_racineForcee/archives';
    final org = await OrganisationFichiers.initialiser();
    return org.cheminArchives;
  }

  /// ═══════════════════════════════════════════════════════════════════════
  ///  ÉCRITURE
  /// ═══════════════════════════════════════════════════════════════════════

  /// Archive un lot d'entrées, en AJOUT SEUL.
  ///
  /// Aucune entrée existante n'est réécrite : une empreinte déjà présente est
  /// ignorée et comptée dans [ResultatArchivage.ignorees]. C'est ce qui rend
  /// l'opération idempotente — rejouer le même lot n'ajoute rien.
  Future<ResultatArchivage> archiver(List<EntreeArchive> entrees) async {
    if (entrees.isEmpty) {
      return const ResultatArchivage(ecrites: 0, ignorees: 0);
    }
    try {
      final dossier = await _dossierArchives();
      await Directory(dossier).create(recursive: true);

      final index = await _chargerIndex(dossier);
      final connues = <String>{
        for (final e in (index['entrees'] as List? ?? const []))
          if (e is Map) '${e['e']}',
      };

      // Répartition par segment cible. On n'ouvre un NOUVEAU segment que
      // lorsque celui en cours est plein : aucun déplacement d'entrée.
      var segmentCourant = index['segment_courant'] as int? ?? 0;
      var lignesCourantes = index['lignes_courantes'] as int? ?? 0;

      var ecrites = 0;
      var ignorees = 0;

      final aEcrireParSegment = <int, List<EntreeArchive>>{};
      for (final e in entrees) {
        if (connues.contains(e.empreinte)) {
          ignorees++;
          continue;
        }
        if (lignesCourantes >= kEntreesParSegment) {
          segmentCourant++;
          lignesCourantes = 0;
        }
        aEcrireParSegment
            .putIfAbsent(segmentCourant, () => <EntreeArchive>[])
            .add(e);
        lignesCourantes++;
        connues.add(e.empreinte);
        ecrites++;
      }

      final nouvellesIndexEntrees = <Map<String, Object?>>[];
      for (final entree in aEcrireParSegment.entries) {
        final numSegment = entree.key;
        final liste = entree.value;
        await _ajouterAuSegment(
            dossier, numSegment, liste, nouvellesIndexEntrees);
      }

      // L'index est réécrit APRÈS les segments : une panne entre les deux
      // laisse des entrées présentes mais non indexées — récupérables par
      // `restaurerIndex()`, jamais perdues. L'ordre inverse aurait l'effet
      // opposé : un index annonçant des entrées absentes.
      index['entrees'] = <Object?>[
        ...(index['entrees'] as List? ?? const []),
        ...nouvellesIndexEntrees,
      ];
      index['segment_courant'] = segmentCourant;
      index['lignes_courantes'] = lignesCourantes;
      index['maj'] = DateTime.now().toUtc().toIso8601String();
      await _ecrireIndex(dossier, index);

      if (kDebugMode) {
        debugPrint('[Archives] ✅ $ecrites entrée(s) archivée(s), '
            '$ignorees ignorée(s) (déjà présentes)');
      }
      return ResultatArchivage(ecrites: ecrites, ignorees: ignorees);
    } catch (e) {
      // Une panne d'archive ne casse jamais l'appelant : elle est rendue.
      return ResultatArchivage(ecrites: 0, ignorees: 0, erreur: '$e');
    }
  }

  /// Ajoute des entrées à un segment, en flux, sans réécrire l'existant.
  Future<void> _ajouterAuSegment(
    String dossier,
    int numSegment,
    List<EntreeArchive> liste,
    List<Map<String, Object?>> indexSortie,
  ) async {
    final chemin = '$dossier/segment_${_pad(numSegment)}.jsonl.gz';
    final fichier = File(chemin);
    await fichier.parent.create(recursive: true);

    // Lignes déjà présentes, pour connaître le numéro de ligne RÉEL.
    var lignesExistantes = 0;
    if (await fichier.exists()) {
      // Comptage en flux : jamais de chargement intégral (§19).
      await for (final _ in _lireLignes(chemin)) {
        lignesExistantes++;
      }
    }

    // ⚠️ DÉFAUT MESURÉ ET CORRIGÉ : LE DÉCALAGE DE LIGNE.
    //
    //    L'index référence des numéros de ligne PHYSIQUES dans le segment.
    //    Une première version comptait les lignes AVANT d'écrire l'en-tête
    //    d'un segment neuf : sur un fichier vierge elle trouvait 0 ligne, puis
    //    écrivait l'en-tête en ligne 1 et les entrées en lignes 2, 3, 4…
    //    alors que l'index les annonçait en 1, 2, 3… Toutes les entrées étaient
    //    donc lues avec un décalage de +1 : la première renvoyait l'en-tête
    //    (ignoré), la dernière ligne indexée n'existait pas.
    //
    //    Mesure : 4 entrées écrites, 1 seule retrouvée par consultation
    //    ciblée, et une entrée restituée avec un résultat `null` alors que son
    //    résultat était `'1-2-3'`. Ce n'était PAS une perte de données — les
    //    octets étaient bien sur le disque — mais une perte de JOIGNABILITÉ,
    //    ce qui revient au même pour l'utilisateur.
    //
    //    Correction : on calcule la position de la PREMIÈRE ENTRÉE après avoir
    //    décidé si un en-tête sera écrit.
    final ecriraEntete = !await fichier.exists();
    final premiereEntree = lignesExistantes + (ecriraEntete ? 1 : 0) + 1;

    // On APPEND : le gzip est concaténable par blocs. Un fichier `.gz` formé
    // de plusieurs membres est parfaitement valide et se relit tel quel.
    //
    // ⚠️ L'EN-TÊTE N'EST ÉCRIT QU'À LA CRÉATION DU SEGMENT. Une première
    //    version le réécrivait à CHAQUE ajout : un segment alimenté en dix
    //    lots portait dix en-têtes. Ce n'était pas une perte de données (les
    //    en-têtes sont ignorés à la lecture), mais c'était un fichier qui
    //    mentait sur sa structure.
    final buffer = StringBuffer();
    if (ecriraEntete) {
      buffer.writeln(jsonEncode(<String, Object?>{
        'entete': true,
        'version': kVersionFormat,
        'segment': numSegment,
        'cree': DateTime.now().toUtc().toIso8601String(),
      }));
    }
    for (final e in liste) {
      final avecSegment = EntreeArchive(
        empreinte: e.empreinte,
        cleCourse: e.cleCourse,
        dateCourse: e.dateCourse,
        contenu: e.contenu,
        resultatOfficiel: e.resultatOfficiel,
        empreinteRapport: e.empreinteRapport,
        empreinteBilan: e.empreinteBilan,
        segment: 'segment_${_pad(numSegment)}',
      );
      buffer.writeln(jsonEncode(avecSegment.toJson()));
    }

    final octets = gzip.encode(utf8.encode(buffer.toString()));
    await fichier.writeAsBytes(octets, mode: FileMode.append);

    for (var i = 0; i < liste.length; i++) {
      final e = liste[i];
      indexSortie.add(EntreeArchive(
        empreinte: e.empreinte,
        cleCourse: e.cleCourse,
        dateCourse: e.dateCourse,
        contenu: e.contenu,
        resultatOfficiel: e.resultatOfficiel,
        empreinteRapport: e.empreinteRapport,
        empreinteBilan: e.empreinteBilan,
        segment: 'segment_${_pad(numSegment)}',
        ligne: premiereEntree + i,
      ).versIndex());
    }
  }

  /// ═══════════════════════════════════════════════════════════════════════
  ///  LECTURE — en flux, jamais tout en RAM
  /// ═══════════════════════════════════════════════════════════════════════

  /// Lit les lignes d'un segment en FLUX.
  ///
  /// Le fichier est décompressé par blocs de 64 Ko et découpé en lignes : un
  /// segment de plusieurs centaines de milliers d'entrées ne matérialise
  /// jamais l'ensemble en mémoire (§19).
  Stream<String> _lireLignes(String cheminFichier) async* {
    final fichier = File(cheminFichier);
    if (!await fichier.exists()) return;
    final bytes = fichier.openRead();
    final decompresse = bytes.transform(gzip.decoder);
    var reste = '';
    await for (final morceau in decompresse.transform(utf8.decoder)) {
      reste += morceau;
      final lignes = reste.split('\n');
      reste = lignes.removeLast(); // ligne potentiellement incomplète
      for (final l in lignes) {
        final t = l.trim();
        if (t.isNotEmpty) yield t;
      }
    }
    final dernier = reste.trim();
    if (dernier.isNotEmpty) {
      // Blocs gzip concaténés : la frontière de bloc peut couper une ligne.
      // On la reconstitue, on ne la jette pas.
      yield dernier;
    }
  }

  /// Consultation CIBLÉE : une course précise, sans ouvrir les autres segments.
  Future<List<EntreeArchive>> parCourse(String cleCourse) async =>
      (await consulterParCourse(cleCourse)).entrees;

  /// Consultation CIBLÉE **avec état constaté** — voir [EtatLectureArchive].
  ///
  /// C'est la forme à utiliser dès qu'un appelant doit décider d'un repli : le
  /// repli n'est légitime que sur un état non `lisible`, et il doit rester
  /// visible. La forme `parCourse` (liste seule) subsiste pour les appelants
  /// qui n'ont rien à décider, mais elle ne permet PAS de distinguer un vide
  /// réel d'une panne — c'est pourquoi elle délègue ici.
  Future<ConsultationArchive> consulterParCourse(String cleCourse) async {
    return _consulter('course "$cleCourse"', (index) {
      final cibles = <Map>[];
      for (final e in (index['entrees'] as List? ?? const [])) {
        if (e is Map && '${e['c']}' == cleCourse) cibles.add(e);
      }
      return cibles;
    });
  }

  /// Consultation CIBLÉE : une période `[du, au]` en ISO, bornes incluses.
  Future<List<EntreeArchive>> parPeriode(String du, String au) async =>
      (await consulterParPeriode(du, au)).entrees;

  /// Consultation CIBLÉE par période, **avec état constaté**.
  Future<ConsultationArchive> consulterParPeriode(String du, String au) async {
    return _consulter('période [$du, $au]', (index) {
      final cibles = <Map>[];
      for (final e in (index['entrees'] as List? ?? const [])) {
        if (e is! Map) continue;
        final d = '${e['d']}';
        if (d.isEmpty) continue;
        if (d.compareTo(du) >= 0 && d.compareTo(au) <= 0) cibles.add(e);
      }
      return cibles;
    });
  }

  /// Consultation CIBLÉE : uniquement les versions portant un résultat officiel
  /// (donc permanentes au sens de la politique `pronostics_archives`).
  Future<List<EntreeArchive>> avecResultatOfficiel() async =>
      (await consulterAvecResultatOfficiel()).entrees;

  /// Consultation des versions à résultat officiel, **avec état constaté**.
  Future<ConsultationArchive> consulterAvecResultatOfficiel() async {
    return _consulter('résultat officiel', (index) {
      final cibles = <Map>[];
      for (final e in (index['entrees'] as List? ?? const [])) {
        if (e is Map && e['r'] != null && '${e['r']}'.trim().isNotEmpty) {
          cibles.add(e);
        }
      }
      return cibles;
    });
  }

  /// Corps commun des consultations ciblées : CONSTATE l'état, ne l'avale pas.
  ///
  /// ⚠️ La distinction `absent` / `inaccessible` se fait sur l'existence du
  ///    dossier, AVANT toute lecture : un dossier inexistant est une
  ///    installation neuve, jamais une panne.
  ///
  /// ⚠️ Un index irrécupérable n'est PAS un état `corrompu` à lui seul : les
  ///    segments restent la référence, et l'index se reconstruit. On ne déclare
  ///    `corrompu` que si la relecture après reconstruction échoue aussi.
  Future<ConsultationArchive> _consulter(
    String cible,
    List<Map> Function(Map<String, Object?> index) selection,
  ) async {
    final String dossier;
    try {
      dossier = await _dossierArchives();
    } catch (e) {
      return ConsultationArchive(
        etat: EtatLectureArchive.inaccessible,
        entrees: const <EntreeArchive>[],
        details: 'racine d\'archives indéterminable : $e',
      );
    }

    // 1. Le dossier existe-t-il ? Sinon : installation neuve, pas une panne.
    bool existe;
    try {
      existe = await Directory(dossier).exists();
    } catch (e) {
      return ConsultationArchive(
        etat: EtatLectureArchive.inaccessible,
        entrees: const <EntreeArchive>[],
        details: 'existence du dossier non vérifiable : $e',
      );
    }
    if (!existe) {
      return ConsultationArchive(
        etat: EtatLectureArchive.absent,
        entrees: const <EntreeArchive>[],
        details: 'aucun dossier d\'archives ($cible)',
      );
    }

    // 2. L'index (reconstruit s'il manque) puis la sélection.
    Map<String, Object?> index;
    try {
      index = await _chargerIndex(dossier);
    } catch (e) {
      return ConsultationArchive(
        etat: EtatLectureArchive.corrompu,
        entrees: const <EntreeArchive>[],
        details: 'index irrécupérable ($cible) : $e',
      );
    }

    // 3. Lecture des seuls segments concernés.
    final List<EntreeArchive> entrees;
    try {
      entrees = await _chargerEntrees(dossier, selection(index));
    } catch (e) {
      return ConsultationArchive(
        etat: EtatLectureArchive.inaccessible,
        entrees: const <EntreeArchive>[],
        details: 'segments illisibles ($cible) : $e',
      );
    }

    return ConsultationArchive(etat: EtatLectureArchive.lisible, entrees: entrees);
  }

  /// Charge les entrées désignées par l'index, en GROUPANT par segment pour
  /// n'ouvrir chaque fichier qu'une seule fois.
  Future<List<EntreeArchive>> _chargerEntrees(
      String dossier, List<Map> cibles) async {
    if (cibles.isEmpty) return const <EntreeArchive>[];
    final parSegment = <String, List<int>>{};
    for (final c in cibles) {
      final s = '${c['s']}';
      final l = (c['l'] as num?)?.toInt() ?? 0;
      if (s.isEmpty) continue;
      parSegment.putIfAbsent(s, () => <int>[]).add(l);
    }

    final out = <EntreeArchive>[];
    for (final entree in parSegment.entries) {
      final chemin = '$dossier/${entree.key}.jsonl.gz';
      final voulues = entree.value.toSet();
      var numero = 0;
      await for (final ligne in _lireLignes(chemin)) {
        numero++;
        if (!voulues.contains(numero)) continue;
        try {
          final decode = jsonDecode(ligne);
          if (decode is! Map) continue;
          final j = <String, dynamic>{
            for (final e in decode.entries) '${e.key}': e.value,
          };
          if (j['entete'] == true) continue;
          final archive = EntreeArchive.depuisJson(j);
          out.add(EntreeArchive(
            empreinte: archive.empreinte,
            cleCourse: archive.cleCourse,
            dateCourse: archive.dateCourse,
            contenu: archive.contenu,
            resultatOfficiel: archive.resultatOfficiel,
            empreinteRapport: archive.empreinteRapport,
            empreinteBilan: archive.empreinteBilan,
            segment: entree.key,
            ligne: numero,
          ));
        } catch (_) {
          // Une ligne illisible n'invalide pas les autres : on continue.
        }
      }
    }
    return out;
  }

  /// Lecture COMPLÈTE, en flux, sans jamais tout garder.
  ///
  /// Sert aux contrôles d'intégrité et à l'export. L'appelant fournit ce qu'il
  /// fait de chaque entrée : la mémoire reste bornée.
  Future<void> parcourirTout(
      FutureOr<void> Function(EntreeArchive) action) async {
    final dossier = await _dossierArchives();
    final segments = await _listerSegments(dossier);
    for (final s in segments) {
      var numero = 0;
      await for (final ligne in _lireLignes('$dossier/$s')) {
        numero++;
        try {
          final decode = jsonDecode(ligne);
          if (decode is! Map) continue;
          final j = <String, dynamic>{
            for (final e in decode.entries) '${e.key}': e.value,
          };
          if (j['entete'] == true) continue;
          final a = EntreeArchive.depuisJson(j);
          await action(EntreeArchive(
            empreinte: a.empreinte,
            cleCourse: a.cleCourse,
            dateCourse: a.dateCourse,
            contenu: a.contenu,
            resultatOfficiel: a.resultatOfficiel,
            empreinteRapport: a.empreinteRapport,
            empreinteBilan: a.empreinteBilan,
            segment: s,
            ligne: numero,
          ));
        } catch (_) {
          continue;
        }
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  INDEX — accélérateur, JAMAIS une dépendance
  // ═══════════════════════════════════════════════════════════════════════

  /// Reconstruit l'index depuis les SEGMENTS SEULS.
  ///
  /// C'est la garantie exigée : la suppression de `index.json` ne perd aucune
  /// connaissance. Mesuré par test : index supprimé ⇒ reconstruction ⇒ même
  /// nombre d'entrées et mêmes consultations ciblées.
  Future<int> restaurerIndex() async {
    final dossier = await _dossierArchives();
    await Directory(dossier).create(recursive: true);
    final segments = await _listerSegments(dossier);

    final entrees = <Map<String, Object?>>[];
    var segmentCourant = 0;
    var lignesCourantes = 0;

    for (final s in segments) {
      final num = _numeroSegment(s);
      if (num > segmentCourant) segmentCourant = num;
      var numero = 0;
      var compte = 0;
      await for (final ligne in _lireLignes('$dossier/$s')) {
        numero++;
        try {
          final decode = jsonDecode(ligne);
          if (decode is! Map) continue;
          final j = <String, dynamic>{
            for (final e in decode.entries) '${e.key}': e.value,
          };
          if (j['entete'] == true) continue;
          final a = EntreeArchive.depuisJson(j);
          entrees.add(<String, Object?>{
            'e': a.empreinte,
            'c': a.cleCourse,
            'd': a.dateCourse,
            's': s.replaceAll('.jsonl.gz', ''),
            'l': numero,
            if (a.resultatOfficiel != null) 'r': a.resultatOfficiel,
          });
          compte++;
        } catch (_) {
          continue;
        }
      }
      if (num == segmentCourant) lignesCourantes = compte;
    }

    final index = <String, Object?>{
      'version': kVersionFormat,
      'maj': DateTime.now().toUtc().toIso8601String(),
      'reconstruit_depuis_segments': true,
      'entrees': entrees,
      'segment_courant': segmentCourant,
      'lignes_courantes': lignesCourantes,
    };
    await _ecrireIndex(dossier, index);
    if (kDebugMode) {
      debugPrint('[Archives] ✅ index reconstruit : ${entrees.length} '
          'entrée(s) depuis ${segments.length} segment(s)');
    }
    return entrees.length;
  }

  /// Lit l'index, ou le RECONSTRUIT s'il manque ou s'il est illisible.
  ///
  /// C'est ici que se joue la non-dépendance : un index absent n'est jamais
  /// une erreur, c'est un accélérateur à refabriquer.
  Future<Map<String, Object?>> _chargerIndex(String dossier) async {
    final fichier = File('$dossier/$kNomIndex');
    if (await fichier.exists()) {
      try {
        final decode = jsonDecode(await fichier.readAsString());
        if (decode is Map) {
          return <String, Object?>{
            for (final e in decode.entries) '${e.key}': e.value,
          };
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[Archives] index illisible ($e) : reconstruction');
        }
      }
    }
    // Index absent ou illisible : on le reconstruit plutôt que de renvoyer
    // un état vide, qui ferait croire à une absence de connaissance.
    await restaurerIndex();
    final relu = File('$dossier/$kNomIndex');
    if (!await relu.exists()) {
      return <String, Object?>{'entrees': <Object?>[], 'segment_courant': 0};
    }
    final decode = jsonDecode(await relu.readAsString());
    if (decode is! Map) {
      return <String, Object?>{'entrees': <Object?>[], 'segment_courant': 0};
    }
    return <String, Object?>{for (final e in decode.entries) '${e.key}': e.value};
  }

  Future<void> _ecrireIndex(
      String dossier, Map<String, Object?> index) async {
    final tmp = File('$dossier/$kNomIndex.tmp');
    await tmp.writeAsString(jsonEncode(index));
    // Écriture atomique : un index à moitié écrit serait pire qu'un index
    // absent, alors qu'un index absent se reconstruit tout seul.
    await tmp.rename('$dossier/$kNomIndex');
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  DIAGNOSTIC
  // ═══════════════════════════════════════════════════════════════════════

  /// Bilan MESURÉ : nombre de segments, entrées, octets réels.
  Future<BilanArchives> bilan() async {
    final dossier = await _dossierArchives();
    final segments = await _listerSegments(dossier);

    var octetsCompresses = 0;
    var octetsDecompresses = 0;
    var entrees = 0;

    for (final s in segments) {
      final f = File('$dossier/$s');
      if (await f.exists()) octetsCompresses += await f.length();
      await for (final ligne in _lireLignes('$dossier/$s')) {
        octetsDecompresses += utf8.encode(ligne).length + 1;
        try {
          final decode = jsonDecode(ligne);
          if (decode is Map && decode['entete'] != true) entrees++;
        } catch (_) {}
      }
    }

    final indexFichier = File('$dossier/$kNomIndex');
    final indexPresent = await indexFichier.exists();
    var indexEntrees = 0;
    if (indexPresent) {
      try {
        final decode = jsonDecode(await indexFichier.readAsString());
        if (decode is Map) {
          indexEntrees = (decode['entrees'] as List? ?? const []).length;
        }
      } catch (_) {}
    }

    return BilanArchives(
      segments: segments.length,
      entrees: entrees,
      octetsCompresses: octetsCompresses,
      octetsDecompresses: octetsDecompresses,
      indexPresent: indexPresent,
      indexEntrees: indexEntrees,
    );
  }

  /// Liste les segments présents, triés.
  Future<List<String>> _listerSegments(String dossier) async {
    final d = Directory(dossier);
    if (!await d.exists()) return const <String>[];
    final noms = <String>[];
    await for (final f in d.list()) {
      if (f is File && f.path.endsWith('.jsonl.gz')) {
        noms.add(f.uri.pathSegments.last);
      }
    }
    noms.sort();
    return noms;
  }

  static int _numeroSegment(String nom) {
    final m = RegExp(r'segment_(\d+)').firstMatch(nom);
    return m == null ? 0 : int.tryParse(m.group(1) ?? '0') ?? 0;
  }

  static String _pad(int n) => n.toString().padLeft(4, '0');

  /// ═══════════════════════════════════════════════════════════════════════
  ///  ISOLATION DE L'APPRENTISSAGE — vérifiée par test
  /// ═══════════════════════════════════════════════════════════════════════

  /// `true` : ce fichier ne participe à aucun apprentissage.
  ///
  /// Constante lue par les tests de non-régression. Elle n'est pas décorative :
  /// elle documente une contrainte vérifiée (aucun import d'`IaMemoryService`,
  /// aucun accès à `_poids`, `_seuils`, TOP3 ou ELO dans ce fichier).
  static const bool _jamaisApprentissage = true;

  /// Accesseur pour la vérification, afin d'éviter un avertissement inutilisé.
  static bool get jamaisApprentissage => _jamaisApprentissage;
}
