/// Diagnostic de l'alimentation des critères — observabilité exigée par D-27
/// et §9.
///
/// Le problème mesuré, que ce fichier existe pour rendre visible :
///
/// * `IaPoidsAdaptatifs.normaliseDiscipline()` renvoie `'global'` pour toute
///   discipline qu'elle ne reconnaît pas (ligne 682 du fichier de modèles).
/// * `poidsParDiscipline['global']` a été mesuré **inerte** : sa variation
///   maximale sur 169 jours est de `5.55e-17`, contre `6.32e-2` pour `plat`,
///   `5.58e-2` pour `obstacle` et `5.11e-2` pour `trot_attele`. Autrement dit,
///   les courses qui tombent dans `global` sont prédites avec des poids qui
///   n'apprennent rien — mais rien dans l'application ne le signale.
///
/// D-27 (VALIDÉ) demande exactement deux choses :
///
/// 1. **Rendre le fallback observable dans les diagnostics.** C'est l'objet de
///    ce fichier.
/// 2. **Préserver son fonctionnement existant et ne pas supprimer la famille
///    `global`.** Ce fichier ne modifie donc **aucun** poids, **aucun** calcul,
///    **aucune** décision. Il observe.
///
/// Corollaire important pour l'honnêteté du diagnostic : la valeur `50.0` n'est
/// pas en soi une anomalie, et une valeur variable n'est pas en soi une preuve
/// de fiabilité (§9). Ce diagnostic ne classe donc pas les critères en « bons »
/// ou « mauvais » : il distingue des **états d'alimentation**.
library;

/// État d'alimentation d'un critère, du point de vue de la donnée d'entrée.
///
/// La distinction est celle qu'impose §9 : « Distinguer les cas où une donnée
/// authentique est disponible, absente, invalide, insuffisante, ou lorsque le
/// critère n'est pas applicable ».
enum EtatAlimentationCritere {
  /// Donnée authentique présente et exploitable.
  authentique,

  /// Aucune donnée : le critère rend sa valeur neutre existante.
  absent,

  /// Donnée présente mais inexploitable (sentinelle, format non reconnu).
  invalide,

  /// Donnée présente mais trop peu nombreuse pour être concluante.
  insuffisant,

  /// Le critère ne s'applique pas à cette course (ex. terrain en trot).
  nonApplicable,

  /// Le critère utilise un repli explicitement prévu par le code existant.
  repliExistant,
}

/// Constat d'alimentation pour un critère et un partant.
class DiagnosticCritere {
  const DiagnosticCritere({
    required this.critere,
    required this.etat,
    required this.detail,
    this.valeurAffichee,
  });

  /// Nom technique du critère (`gains`, `progression`, `terrain`, ...).
  final String critere;

  final EtatAlimentationCritere etat;

  /// Explication lisible : ce qui a été lu, et pourquoi cet état.
  final String detail;

  /// Valeur effectivement transmise au calcul, si elle existe.
  final double? valeurAffichee;

  Map<String, Object?> toJson() => <String, Object?>{
        'critere': critere,
        'etat': etat.name,
        'detail': detail,
        'valeur': valeurAffichee,
      };
}

/// Diagnostic du repli de discipline.
///
/// Il répond à une seule question : **cette course est-elle prédite avec des
/// poids réellement appris pour sa discipline, ou avec la famille `global` ?**
class DiagnosticDiscipline {
  const DiagnosticDiscipline({
    required this.disciplineSource,
    required this.disciplineNormalisee,
    required this.repliGlobal,
    required this.famillePoidsUtilisee,
  });

  /// Discipline telle que fournie par la course (`course.type`).
  final String disciplineSource;

  /// Résultat de `normaliseDiscipline`.
  final String disciplineNormalisee;

  /// `true` si la discipline n'a pas été reconnue et est retombée sur `global`.
  final bool repliGlobal;

  /// Famille de poids réellement employée pour le calcul.
  final String famillePoidsUtilisee;

  /// Message destiné aux diagnostics. Il ne modifie rien : il informe.
  String get message {
    if (!repliGlobal) {
      return 'Discipline « $disciplineSource » reconnue → famille '
          '« $disciplineNormalisee ». Poids réellement appris.';
    }
    return 'Discipline « $disciplineSource » NON reconnue → repli sur la '
        'famille « global ». Les poids de cette famille ont été mesurés '
        'inertes (variation 5.55e-17 sur 169 jours) : le calcul fonctionne, '
        'mais il n\'apprend pas. Famille conservée (D-27).';
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'discipline_source': disciplineSource,
        'discipline_normalisee': disciplineNormalisee,
        'repli_global': repliGlobal,
        'famille_poids': famillePoidsUtilisee,
        'message': message,
      };
}

/// Construit le diagnostic de discipline.
///
/// [normalise] est la fonction **existante** du projet, passée en paramètre
/// pour que ce fichier ne duplique ni ne remplace la logique de normalisation.
DiagnosticDiscipline diagnostiquerDiscipline({
  required String disciplineSource,
  required String Function(String) normalise,
  required bool familleGlobalDisponible,
}) {
  final norm = normalise(disciplineSource);
  final repli = norm == 'global';
  return DiagnosticDiscipline(
    disciplineSource: disciplineSource,
    disciplineNormalisee: norm,
    repliGlobal: repli,
    famillePoidsUtilisee: repli && !familleGlobalDisponible
        ? 'defauts_constructeur'
        : norm,
  );
}

/// Agrège les diagnostics d'une course pour les exposer d'un bloc.
class DiagnosticCourse {
  DiagnosticCourse({
    required this.discipline,
    required this.criteres,
  });

  final DiagnosticDiscipline discipline;
  final List<DiagnosticCritere> criteres;

  /// Nombre de critères par état. Sert à repérer un appauvrissement global de
  /// l'alimentation sans juger critère par critère.
  Map<String, int> get repartition {
    final out = <String, int>{};
    for (final c in criteres) {
      out[c.etat.name] = (out[c.etat.name] ?? 0) + 1;
    }
    return out;
  }

  /// Les critères dont l'alimentation est dégradée. Liste vide ⇒ tout est
  /// authentique ou explicitement non applicable.
  List<DiagnosticCritere> get degrades => criteres
      .where((c) =>
          c.etat == EtatAlimentationCritere.absent ||
          c.etat == EtatAlimentationCritere.invalide ||
          c.etat == EtatAlimentationCritere.insuffisant)
      .toList(growable: false);

  Map<String, Object?> toJson() => <String, Object?>{
        'discipline': discipline.toJson(),
        'criteres': [for (final c in criteres) c.toJson()],
        'repartition': repartition,
        'degrades': degrades.map((c) => c.critere).toList(growable: false),
      };
}

/// Analyse un CSV de statistiques `terrain|nbCourses|nbVictoires|nbTop3`.
///
/// Ce contrôle existe parce que le défaut mesuré était **silencieux** : la
/// chaîne était toujours vide, `scoreTerrain` rendait 50.0, et rien ne le
/// disait. La valeur 50.0 n'est pas une anomalie en soi (§9) — c'est le fait
/// qu'elle masquait une absence totale de donnée qui en était une.
///
/// Ne modifie rien : rend un état.
DiagnosticCritere diagnostiquerTerrainCsv(String csv) {
  if (csv.trim().isEmpty) {
    return const DiagnosticCritere(
      critere: 'terrain',
      etat: EtatAlimentationCritere.absent,
      detail: 'Aucune statistique par terrain disponible. Le critère rend sa '
          'valeur neutre existante (50.0). Ce n\'est pas une anomalie de '
          'calcul, c\'est une absence de donnée.',
    );
  }
  final entrees = csv.split(';').where((e) => e.trim().isNotEmpty).toList();
  if (entrees.isEmpty) {
    return const DiagnosticCritere(
      critere: 'terrain',
      etat: EtatAlimentationCritere.absent,
      detail: 'Chaîne non vide mais sans entrée exploitable.',
    );
  }
  var totalCourses = 0;
  for (final e in entrees) {
    final parts = e.split('|');
    if (parts.length < 2) {
      return const DiagnosticCritere(
        critere: 'terrain',
        etat: EtatAlimentationCritere.invalide,
        detail: 'Format d\'entrée non reconnu : moins de deux champs.',
      );
    }
    totalCourses += int.tryParse(parts[1]) ?? 0;
  }
  if (totalCourses == 0) {
    return const DiagnosticCritere(
      critere: 'terrain',
      etat: EtatAlimentationCritere.insuffisant,
      detail: 'Entrées présentes mais aucune course comptabilisée.',
    );
  }
  return DiagnosticCritere(
    critere: 'terrain',
    etat: EtatAlimentationCritere.authentique,
    detail: '${entrees.length} terrain(s), $totalCourses course(s) au total.',
  );
}
