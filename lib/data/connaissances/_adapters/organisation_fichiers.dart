/// Organisation physique des connaissances sur le disque.
///
/// Consigne §6 : « base/ », « archives/ », « config/ », « cache/ »,
/// « sauvegardes/ », « temp/ », adaptables aux conventions Android/Flutter.
/// Aucune connaissance permanente ne doit être écrite dans un dossier que le
/// système peut vider.
///
/// Choix technique : toutes les racines sont sous le répertoire privé de
/// l'application (`getApplicationSupportDirectory`), qui n'est **pas** vidé par
/// Android lors d'une mise à jour de l'APK, et qui n'est **pas** non plus un
/// dossier de cache. C'est la condition pour que §6 (« Une mise à jour de l'APK
/// doit préserver les données ») soit tenue.
///
/// Ce que chaque dossier contient, et pourquoi il peut y être :
///
/// | Dossier        | Contenu                                         | Vidable ? |
/// |----------------|-------------------------------------------------|-----------|
/// | `base/`        | Base SQLite, faits, observations, ELO, rapports  | **non**   |
/// | `archives/`    | Archives segmentées et compressées, pronostics   | **non**   |
/// | `config/`      | Poids, seuils, états d'apprentissage              | **non**   |
/// | `sauvegardes/` | Sauvegardes exportées par l'application          | **non**   |
/// | `cache/`       | Caches entièrement reconstructibles              | oui       |
/// | `temp/`        | Fichiers temporaires de migration/restauration   | oui       |
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Rôle d'un dossier, et si sa perte est admissible.
enum RoleDossier {
  /// Connaissances permanentes : jamais vidé par le système ni par l'app.
  permanent,

  /// Entièrement reconstructible : peut être vidé sans perte de connaissance.
  volatil,
}

/// Description d'un dossier racine.
class DossierConnaissance {
  const DossierConnaissance({
    required this.nom,
    required this.role,
    required this.justification,
  });

  final String nom;
  final RoleDossier role;
  final String justification;
}

/// Les six dossiers de la consigne, avec leur rôle déclaré.
const List<DossierConnaissance> kDossiers = <DossierConnaissance>[
  DossierConnaissance(
    nom: 'base',
    role: RoleDossier.permanent,
    justification:
        'Base structurée (faits PMU, observations locales, ELO, rapports, '
        'bilans). Perte irréversible : doit survivre aux mises à jour de l\'APK.',
  ),
  DossierConnaissance(
    nom: 'archives',
    role: RoleDossier.permanent,
    justification:
        'Archives segmentées et compressées des pronostics et rapports '
        'historiques. Conservation sans limite de durée (§11).',
  ),
  DossierConnaissance(
    nom: 'config',
    role: RoleDossier.permanent,
    justification:
        'Poids, poids par discipline, seuils, calibration, états '
        'd\'apprentissage. Ne se reconstitue pas sans rejouer l\'historique.',
  ),
  DossierConnaissance(
    nom: 'sauvegardes',
    role: RoleDossier.permanent,
    justification:
        'Sauvegardes exportées. Une sauvegarde exportée par l\'utilisateur '
        'n\'est JAMAIS supprimée automatiquement (D-21).',
  ),
  DossierConnaissance(
    nom: 'cache',
    role: RoleDossier.volatil,
    justification:
        'Caches reconstructibles : réponses réseau récentes, agrégats '
        'recalculables. Vidable sans perte de connaissance (§15).',
  ),
  DossierConnaissance(
    nom: 'temp',
    role: RoleDossier.volatil,
    justification:
        'Espace de travail des migrations et restaurations. Vidé au démarrage '
        'et après chaque opération terminée.',
  ),
];

/// Résolution et création des dossiers de connaissances.
class OrganisationFichiers {
  OrganisationFichiers._(this.racine);

  /// Racine privée de l'application.
  final Directory racine;

  /// Prépare l'organisation sous le répertoire privé de l'application.
  ///
  /// [racineForcee] permet aux tests de travailler dans un dossier isolé —
  /// condition posée par §14 : « Les tests doivent utiliser des copies
  /// isolées ».
  static Future<OrganisationFichiers> initialiser({String? racineForcee}) async {
    final Directory base;
    if (racineForcee != null) {
      base = Directory(racineForcee);
    } else {
      // `getApplicationSupportDirectory` : dossier privé, non purgé par
      // Android à la mise à jour, distinct des caches système.
      base = await getApplicationSupportDirectory();
    }
    final org = OrganisationFichiers._(base);
    await org.creerTous();
    return org;
  }

  Future<void> creerTous() async {
    for (final d in kDossiers) {
      final dir = Directory('${racine.path}/${d.nom}');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }
  }

  /// Chemin absolu d'un dossier déclaré.
  String chemin(String nom) => '${racine.path}/$nom';

  /// Chemin de la base structurée.
  String get cheminBase => '${chemin('base')}/pronostic.db';

  /// Chemin des archives segmentées.
  String get cheminArchives => chemin('archives');

  /// Chemin des sauvegardes exportées.
  String get cheminSauvegardes => chemin('sauvegardes');

  /// Chemin des fichiers temporaires.
  String get cheminTemp => chemin('temp');

  /// Chemin des caches.
  String get cheminCache => chemin('cache');

  /// Chemin de configuration.
  String get cheminConfig => chemin('config');

  /// Vide `cache/` et `temp/` uniquement. Les dossiers permanents ne sont
  /// **jamais** touchés par cette méthode.
  Future<int> viderVolatils() async {
    var supprimes = 0;
    for (final d in kDossiers.where((d) => d.role == RoleDossier.volatil)) {
      final dir = Directory(chemin(d.nom));
      if (!await dir.exists()) continue;
      await for (final e in dir.list()) {
        await e.delete(recursive: true);
        supprimes++;
      }
    }
    return supprimes;
  }

  /// Inventaire des dossiers, avec nombre de fichiers et volume cumulé.
  ///
  /// Sert aux diagnostics de volumétrie (§11 : distinguer volume permanent,
  /// temporaire, index, sauvegardes). Aucun plafond n'est appliqué ici.
  Future<Map<String, Map<String, Object?>>> inventaire() async {
    final out = <String, Map<String, Object?>>{};
    for (final d in kDossiers) {
      final dir = Directory(chemin(d.nom));
      var fichiers = 0;
      var octets = 0;
      if (await dir.exists()) {
        await for (final e in dir.list(recursive: true)) {
          if (e is File) {
            fichiers++;
            octets += await e.length();
          }
        }
      }
      out[d.nom] = <String, Object?>{
        'role': d.role.name,
        'fichiers': fichiers,
        'octets': octets,
      };
    }
    return out;
  }

  /// Espace disque disponible, en octets. `null` si le système ne le fournit
  /// pas. Consigne §11 / §15 : gérer proprement une place insuffisante plutôt
  /// que de supprimer des connaissances.
  Future<int?> espaceDisponible() async {
    try {
      final r = await Process.run('df', <String>['-k', racine.path]);
      if (r.exitCode != 0) return null;
      final lignes = '${r.stdout}'.trim().split('\n');
      if (lignes.length < 2) return null;
      final champs = lignes[1].split(RegExp(r'\s+'));
      if (champs.length < 4) return null;
      final ko = int.tryParse(champs[3]);
      return ko == null ? null : ko * 1024;
    } catch (_) {
      return null;
    }
  }
}
