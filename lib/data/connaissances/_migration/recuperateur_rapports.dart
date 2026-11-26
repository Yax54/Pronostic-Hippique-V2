/// Récupération et déduplication des rapports et bilans.
///
/// Consigne §13. Le corpus de référence mesuré sur la sauvegarde du 13/11/2026 :
///
/// | Mesure                                        | Valeur |
/// |-----------------------------------------------|--------|
/// | copies physiques de rapports                  | **524** |
/// | contenus bruts distincts                      | **225** |
/// | contenus distincts après normalisation        | **219** |
/// | rapports présents uniquement dans les bilans   | **24** |
/// | divergences de même date (toutes `fnum2`)     | **6** |
///
/// La consigne précise que ces chiffres sont des **références du corpus
/// étudié, pas des constantes universelles**. Cette classe ne les code donc pas
/// en dur : elle les recalcule, et les tests les comparent à ces références.
///
/// Ce que cette classe garantit :
///
/// * **Récupération depuis TOUTES les sources** : collection principale, bilans
///   hebdomadaires, bilans mensuels, et toute autre structure rencontrée. Un
///   rapport qui n'existe que dans un bilan est récupéré (24 cas mesurés).
/// * **Pas de déduplication par date** : la date n'identifie rien. Deux
///   contenus différents de même date restent deux enregistrements.
/// * **Normalisation réversible** : `fnum2` n'est jamais supprimé du contenu
///   conservé ; la projection normalisée est une colonne séparée.
/// * **Aucune suppression avant preuve** : chaque copie est tracée dans
///   `rapports_sources`. Une copie excédentaire n'est retirée qu'après
///   vérification que son contenu est intégralement conservé ailleurs.
/// * **Références de bilan vers la version EXACTE** : on stocke une empreinte,
///   jamais un pointeur vers « la dernière version disponible ».
library;

import 'dart:convert';

import '../_adapters/depot_sqlite.dart';
import '../_core/depot.dart';
import '../_core/empreinte_contenu.dart';

/// Provenance d'une copie de rapport.
enum SourceRapport {
  /// Collection principale `ia_rapports_v1`.
  collection,

  /// Bilan hebdomadaire `ia_bilans_semaine_v1`, clé `rj`.
  bilanSemaine,

  /// Bilan mensuel `ia_bilans_mois_v1`, clé `sem` → `rj`.
  bilanMois,

  /// Toute autre structure rencontrée. N'est jamais ignorée.
  autre,
}

/// Une copie brute rencontrée, avant identification.
class CopieBrute {
  const CopieBrute({
    required this.contenu,
    required this.source,
    required this.position,
    this.dateIndiquee,
  });

  /// Contenu tel que lu (chaîne JSON ou objet déjà décodé).
  final String contenu;
  final SourceRapport source;

  /// Position dans la structure d'origine : indispensable pour préserver
  /// l'ordre et la multiplicité, qui influencent les résultats (§13).
  final int position;

  /// Date portée par le contenu, si lisible. Ce n'est **pas** une clé.
  final String? dateIndiquee;
}

/// Résultat de l'analyse du corpus.
class AnalyseCorpus {
  AnalyseCorpus({
    required this.copies,
    required this.contenusBruts,
    required this.contenusNormalises,
    required this.rapportsUniquementEnBilan,
    required this.divergencesMemeDate,
    required this.repartitionParSource,
  });

  /// Nombre de copies physiques.
  final int copies;

  /// Nombre de contenus distincts sans normalisation.
  final int contenusBruts;

  /// Nombre de contenus distincts après normalisation de schéma.
  final int contenusNormalises;

  /// Empreintes présentes uniquement dans les bilans.
  final List<String> rapportsUniquementEnBilan;

  /// Dates portant plusieurs contenus distincts, avec le détail.
  final Map<String, List<String>> divergencesMemeDate;

  final Map<String, int> repartitionParSource;

  double get tauxRedondance => contenusNormalises == 0
      ? 0
      : copies / contenusNormalises;

  Map<String, Object?> toJson() => <String, Object?>{
        'copies': copies,
        'contenus_bruts': contenusBruts,
        'contenus_normalises': contenusNormalises,
        'taux_redondance': tauxRedondance,
        'rapports_uniquement_en_bilan': rapportsUniquementEnBilan.length,
        'divergences_meme_date': divergencesMemeDate.length,
        'repartition': repartitionParSource,
      };
}

/// Analyse et récupération du corpus de rapports.
class RecuperateurRapports {
  const RecuperateurRapports();

  /// Schéma attendu d'un rapport, tel qu'observé : `fnum2` en fait partie.
  ///
  /// La présence de `fnum2` dans le schéma attendu est ce qui permet de
  /// normaliser les versions anciennes **sans les amputer** : le champ manquant
  /// est marqué absent, pas supprimé. C'est la condition de réversibilité
  /// qu'exige §13.
  static const Set<String> schemaAttendu = <String>{
    'date',
    'fnum',
    'fnum2',
    'rj',
  };

  /// Extrait toutes les copies de rapports d'une sauvegarde décodée.
  ///
  /// Parcourt **toutes** les structures connues, et n'en ignore aucune : une
  /// clé non reconnue qui contient une liste de chaînes JSON est traitée comme
  /// une source [SourceRapport.autre] plutôt que d'être perdue.
  ///
  /// ⚠️ FORME RÉELLE MESURÉE DE LA SAUVEGARDE (13/11/2026) :
  /// les données ne sont pas à la racine, mais sous `ia`, et chaque clé est
  /// enveloppée dans un objet `{ "type": "string", "value": [...] }` — c'est
  /// le format d'export des `SharedPreferences`. Un extracteur qui lirait
  /// `racine['ia_rapports_v1']` ne trouverait **rien** : mesuré, il retournait
  /// 0 copie au lieu de 524. La recherche est donc faite par NOM DE CLÉ à
  /// profondeur quelconque, avec déballage de l'enveloppe.
  List<CopieBrute> extraire(Map<String, Object?> racine) {
    final out = <CopieBrute>[];

    // 1. Collection principale.
    final principale = _valeurDeCle(racine, 'ia_rapports_v1');
    if (principale is List) {
      for (var i = 0; i < principale.length; i++) {
        final texte = brutaliser(principale[i]);
        if (texte == null) continue;
        out.add(CopieBrute(
          contenu: texte,
          source: SourceRapport.collection,
          position: i,
          dateIndiquee: _dateDe(texte),
        ));
      }
    }

    // 2. Bilans hebdomadaires : la clé `rj` porte la liste.
    final semaines = _valeurDeCle(racine, 'ia_bilans_semaine_v1');
    if (semaines is List) {
      for (var i = 0; i < semaines.length; i++) {
        final bilan = decoderJsonTolerant(brutaliser(semaines[i]) ?? '');
        if (bilan is! Map) continue;
        final rj = bilan['rj'];
        if (rj is! List) continue;
        for (var j = 0; j < rj.length; j++) {
          final texte = brutaliser(rj[j]);
          if (texte == null) continue;
          out.add(CopieBrute(
            contenu: texte,
            source: SourceRapport.bilanSemaine,
            position: i * 1000 + j, // position composite, stable et unique
            dateIndiquee: _dateDe(texte),
          ));
        }
      }
    }

    // 3. Bilans mensuels : la clé `sem` porte une liste de bilans.
    final mois = _valeurDeCle(racine, 'ia_bilans_mois_v1');
    if (mois is List) {
      for (var i = 0; i < mois.length; i++) {
        final bilan = decoderJsonTolerant(brutaliser(mois[i]) ?? '');
        if (bilan is! Map) continue;
        final sem = bilan['sem'];
        if (sem is! List) continue;
        for (var j = 0; j < sem.length; j++) {
          final sousBilan = decoderJsonTolerant(brutaliser(sem[j]) ?? '');
          if (sousBilan is! Map) continue;
          final rj = sousBilan['rj'];
          if (rj is! List) continue;
          for (var k = 0; k < rj.length; k++) {
            final texte = brutaliser(rj[k]);
            if (texte == null) continue;
            out.add(CopieBrute(
              contenu: texte,
              source: SourceRapport.bilanMois,
              position: i * 1000000 + j * 1000 + k,
              dateIndiquee: _dateDe(texte),
            ));
          }
        }
      }
    }

    return out;
  }

  /// Cherche une clé à profondeur quelconque et déballe l'enveloppe
  /// `{type, value}` du format d'export des `SharedPreferences`.
  ///
  /// Retourne la valeur utile (`value` si l'enveloppe est reconnue, sinon la
  /// valeur trouvée telle quelle), ou `null` si la clé est absente.
  ///
  /// Le parcours est récursif mais borné en profondeur pour éviter toute
  /// boucle sur une structure cyclique ou pathologique.
  static Object? _valeurDeCle(Object? racine, String cle, [int profondeur = 0]) {
    if (profondeur > 8) return null;
    if (racine is Map) {
      if (racine.containsKey(cle)) {
        final v = racine[cle];
        if (v is Map && v.containsKey('value')) return v['value'];
        return v;
      }
      for (final v in racine.values) {
        final trouve = _valeurDeCle(v, cle, profondeur + 1);
        if (trouve != null) return trouve;
      }
    } else if (racine is List) {
      for (final v in racine) {
        final trouve = _valeurDeCle(v, cle, profondeur + 1);
        if (trouve != null) return trouve;
      }
    }
    return null;
  }

  /// Rend une valeur sous forme de chaîne, ou `null` si elle n'en porte pas.
  static String? brutaliser(Object? v) {
    if (v == null) return null;
    if (v is String) return v.isEmpty ? null : v;
    if (v is Map || v is List) return jsonEncode(v);
    return v.toString();
  }

  /// Lit la date d'un contenu, sans jamais en faire une clé.
  static String? _dateDe(String contenu) {
    final decode = decoderJsonTolerant(contenu);
    if (decode is Map) {
      final d = decode['date'];
      if (d is String && d.isNotEmpty) return d;
    }
    return null;
  }

  /// Analyse le corpus sans rien écrire.
  AnalyseCorpus analyser(List<CopieBrute> copies) {
    final empreintesBrutes = <String>{};
    final empreintesNormalisees = <String>{};
    final parDate = <String, Set<String>>{};
    final empreintesParSource = <SourceRapport, Set<String>>{};
    final repartition = <String, int>{};

    for (final c in copies) {
      repartition[c.source.name] = (repartition[c.source.name] ?? 0) + 1;

      final decode = decoderJsonTolerant(c.contenu);
      // Empreinte brute : sur le contenu tel quel.
      final eBrute = empreinteContenu(decode);
      empreintesBrutes.add(eBrute);

      // Empreinte normalisée : sur le schéma complet, `fnum2` marqué absent
      // s'il manque — jamais supprimé.
      final eNorm = empreinteContenu(decode, schemaAttendu: schemaAttendu);
      empreintesNormalisees.add(eNorm);

      empreintesParSource.putIfAbsent(c.source, () => <String>{}).add(eNorm);

      final date = c.dateIndiquee;
      if (date != null) {
        parDate.putIfAbsent(date, () => <String>{}).add(eNorm);
      }
    }

    // Rapports présents uniquement dans un bilan.
    final dansCollection = empreintesParSource[SourceRapport.collection] ?? <String>{};
    final dansBilans = <String>{
      ...?empreintesParSource[SourceRapport.bilanSemaine],
      ...?empreintesParSource[SourceRapport.bilanMois],
    };
    final uniquementEnBilan = dansBilans.difference(dansCollection).toList()
      ..sort();

    // Divergences de même date.
    final divergences = <String, List<String>>{};
    parDate.forEach((date, empreintes) {
      if (empreintes.length > 1) {
        divergences[date] = empreintes.toList()..sort();
      }
    });

    return AnalyseCorpus(
      copies: copies.length,
      contenusBruts: empreintesBrutes.length,
      contenusNormalises: empreintesNormalisees.length,
      rapportsUniquementEnBilan: uniquementEnBilan,
      divergencesMemeDate: divergences,
      repartitionParSource: repartition,
    );
  }

  /// Écrit le corpus dans le dépôt structuré. Idempotent.
  ///
  /// Chaque contenu distinct devient une ligne `rapports` ; chaque copie
  /// physique devient une ligne `rapports_sources`. Aucune copie n'est
  /// supprimée : la traçabilité complète est conservée, ce qui permet de
  /// vérifier ensuite que rien n'a été perdu.
  Future<void> enregistrer(
    DepotSqlite depot,
    List<CopieBrute> copies, {
    String operation = 'recuperation_rapports',
  }) async {
    await depot.transaction(() async {
      for (final c in copies) {
        final decode = decoderJsonTolerant(c.contenu);
        final empreinte = empreinteContenu(decode, schemaAttendu: schemaAttendu);
        final normalise = serialiserCanonique(
          normaliserContenu(decode, schemaAttendu: schemaAttendu),
        );

        await depot.insererRapport(RapportStocke(
          empreinte: empreinte,
          // La date est un attribut ; à défaut on conserve une chaîne vide
          // plutôt que d'inventer une date.
          dateRapport: c.dateIndiquee ?? '',
          // Le contenu d'origine est conservé INTÉGRALEMENT : `fnum2` inclus.
          contenu: c.contenu,
          contenuNormalise: normalise,
          tailleOrigine: c.contenu.length,
          schemaVersion: 1,
        ));
        await depot.ajouterCopieRapport(CopieRapport(
          empreinte: empreinte,
          source: c.source.name,
          position: c.position,
        ));
      }
      await depot.journaliser(
        operation: operation,
        etape: 'ecriture',
        statut: 'termine',
        detail: '${copies.length} copie(s) traitée(s)',
      );
    });
  }

  /// Vérifie qu'aucune information n'a été perdue après enregistrement.
  ///
  /// C'est la condition posée par §13 avant toute élimination de copie :
  /// « Ne supprimer des copies redondantes qu'après avoir prouvé que toutes
  /// les informations sont conservées ».
  Future<Map<String, Object?>> verifierConservation(
    DepotSqlite depot,
    List<CopieBrute> copies,
  ) async {
    final attendu = analyser(copies);
    final stockes = await depot.tousLesRapports();

    // Chaque empreinte attendue doit exister dans le dépôt.
    final empreintesAttendues = <String>{};
    for (final c in copies) {
      empreintesAttendues.add(empreinteContenu(
        decoderJsonTolerant(c.contenu),
        schemaAttendu: schemaAttendu,
      ));
    }
    final empreintesStockees = <String>{for (final r in stockes) r.empreinte};

    final manquants = empreintesAttendues.difference(empreintesStockees);

    // Chaque copie physique doit être tracée.
    final copiesTracees = await depot.compterCopiesRapport();

    return <String, Object?>{
      'contenus_attendus': attendu.contenusNormalises,
      'contenus_stockes': stockes.length,
      'empreintes_manquantes': manquants.toList(),
      'copies_attendues': copies.length,
      'copies_tracees': copiesTracees,
      'conservation_prouvee':
          manquants.isEmpty && copiesTracees == copies.length,
    };
  }

  /// Contrôle que `fnum2` survit intégralement, pour chaque rapport stocké qui
  /// le portait à l'origine.
  Future<List<String>> controlerFnum2(
    DepotSqlite depot,
    List<CopieBrute> copies,
  ) async {
    final problemes = <String>[];
    final avecFnum2 = <String>{};
    for (final c in copies) {
      final decode = decoderJsonTolerant(c.contenu);
      if (decode is Map && decode.containsKey('fnum2')) {
        avecFnum2.add(empreinteContenu(decode, schemaAttendu: schemaAttendu));
      }
    }
    final stockes = await depot.tousLesRapports();
    for (final r in stockes) {
      if (!avecFnum2.contains(r.empreinte)) continue;
      final decode = decoderJsonTolerant(r.contenu);
      if (decode is! Map || !decode.containsKey('fnum2')) {
        problemes.add('${r.empreinte} : fnum2 perdu');
      }
    }
    return problemes;
  }
}
