// ═══════════════════════════════════════════════════════════════════════════
//  BackupService — Sauvegarde & Restauration COMPLETE des donnees
//  Pronostic Hippique v5.0 — Couverture 100% de toutes les SharedPreferences
//
//  ── INVENTAIRE COMPLET DES CLES SAUVEGARDEES ─────────────────────────────
//
//  🧠 MEMOIRE IA (ia_memory_service.dart) — 9 cles
//     ia_poids_v3          : Poids adaptatifs (19 criteres + PoidsIndices
//                            [criteres/confiance/reussite] + momentum
//                            + poidsParDiscipline) — COEUR de l'IA
//     ia_pronostics_v2     : 600 pronostics avec scores par critere,
//                            arrivee reelle, rangFavori, nbTop3, nbTop5,
//                            scorePerformance, typePariConseille,
//                            tauxReussiteAuMoment, precisionIA
//     ia_journal_v2        : 150 entrees journal gradient (avant/apres poids,
//                            diagnostic, methode, scorePerf)
//     ia_rapports_v1       : 60 rapports journaliers glissants (stats, note, discipline,
//                            19 criteres poidsApres, detail cours par cours,
//                            stats par type de pari, heure analyse)
//     ia_derniere_analyse_v1 : Date dernière analyse journée (format ddMMyyyy)
//     ia_stats_types_v1    : Stats cumulatives par type de pari (nbJoues,
//                            nbGagnes, nbPerdus, gainNet)
//     ia_precision_v2      : Precision IA par type de pari (StatsPrecisionParType)
//     ia_seuils_v1         : Seuils de confiance adaptatifs (SeuilsConfianceAdaptatifs)
//     ia_premium_historique_v1 : ★ v10.38 — Historique premium calendrier étoile (multi-jours)
//     ia_premium_du_jour_v1    : ★ v10.38 — Ancien format compat lecture (migration)
//     premium_widgets_selection_jour_v1 : ★ v10.62 — Figeage 5 widgets premium du jour
//
//  🎯 CONFIG FUSION BestBet — 4 CLES HERITEES, MODULE SUPPRIME (BL1-A16)
//     fusion_poids_confiance : Poids confiance (double)
//     fusion_poids_gain      : Poids qualite gain (double)
//     fusion_poids_risque    : Poids rapport risque (double)
//     fusion_seuil_min       : Seuil confiance minimum (int)
//
//     Le module qui ecrivait ces 4 cles a ete supprime (BL1-A16 : ecran,
//     service et moteur inatteignables). Elles sont CONSERVEES dans les
//     listes de collecte et de restauration pour une SEULE raison :
//     une sauvegarde ANCIENNE qui les contient doit pouvoir etre restauree
//     sans erreur. Elles sont restaurees telles quelles, sans etre relues,
//     et ne reactivent AUCUN module. Ne pas les retirer.
//
//  📋 PARIS UTILISATEUR (pmu_provider.dart) — 1 cle
//     user_predictions_v2  : Liste complete des paris (id, date, cheval,
//                            cote, typePari, mise, gain, isCorrect, scoreIA)
//
//  🔔 ALERTES (alert_service.dart) — 5 cles
//     alert_config_v2               : Configuration alertes (activees, seuil, types)
//     alert_history_v1              : Historique des alertes recues
//     tracked_courses_v1            : Courses actuellement suivies
//     alert_sent_ids_v1             : Anti-doublons notifications
//     alert_resultats_verifies_v1   : Resultats deja verifies
//
//  👤 PROFIL UTILISATEUR (profile_screen.dart) — 2 cles
//     profil_nom        : Nom affiche dans l'app
//     profil_gmail      : Adresse email de l'utilisateur
//     NOTE: profil_photo_path exclu (chemin local non portable entre appareils)
//
//  📱 WIDGET ANDROID (widget_service.dart) — clés écrites via MethodChannel
//     widget_course_name  : Nom de la course affichee dans le widget
//     widget_horse_name   : Nom du cheval favori IA
//     widget_horse_num    : Numero du cheval favori
//     widget_confiance    : Niveau de confiance IA (%)
//     widget_gain         : Gain potentiel estime
//     widget_hippodrome   : Hippodrome
//     widget_heure        : Heure de la course
//     widget_nb_courses   : Nombre de courses disponibles
//     widget_updated_at   : Derniere mise a jour du widget
//     widget_score_ia     : Score IA du cheval favori
//     widget_type_pari    : Type de pari conseillé
//     widget_tendance     : Tendance du cheval
//     widget_elo          : Rating ELO du cheval
//     widget_course2_name / widget_horse2_name / widget_heure2 / widget_confiance2
//     widget_course3_name / widget_horse3_name / widget_heure3 / widget_confiance3
//
//  🧪 LABO IA — Simulations sauvegardées (simulation_candidate_service.dart) — 1 clé
//     simulation_candidates_v1 : Pistes de simulation enregistrées (candidats)
//                                Obligatoire — non recalculable.
//
//  📊 CACHE AUDIT — Cache de calcul IA (ia_audit_cache_service.dart) — 1 clé
//     ia_audit_cache_v1 : Cache des 4 onglets Audit (Utilité, Morts,
//                         Corrélations, Discipline). Optionnel — recalculable.
//
//  ── TOTAL : 41 CLES — COUVERTURE 100% ────────────────────────────────────
//
//  ── CE QUE CONTIENT CHAQUE CLE ───────────────────────────────────────────
//
//  ia_poids_v3 (String JSON) contient :
//    • forme, gains, record, cote, constance, victoires, discipline (7 poids de base)
//    • distSpec, jockey, repos, hippo (4 poids enrichis v4.1/v7.0)
//    • momentum (Map<String,double> : vitesse apprentissage par critere)
//    • poidsParDiscipline (Map<discipline, Map<critere, double>>)
//    • nbMisesAJour (compteur d'apprentissages)
//    • poidsIndices.pc / pco / pr (PoidsIndices : criteres/confiance/reussite)
//    • calibration (score de calibration global)
//
//  ia_pronostics_v2 (StringList<JSON>) contient par pronostic :
//    • courseKey, nomCourse, hippodrome, discipline, datePronostic
//    • scoresIA : Map<numCheval, scoreIA>
//    • rangFavori : rang predit du favori IA
//    • scoresCriteres : Map<numCheval, ScoresCriteres{19 criteres}>
//    • arriveeReelle : liste d'arrivee (si connue)
//    • nbTop3, nbTop5, scorePerformance
//    • typePariConseille, tauxReussiteAuMoment, precisionIA
//    • confianceIA : score de confiance (0-100)
//
//  ── RETROCOMPATIBILITE ───────────────────────────────────────────────────
//     v1.0 : Sans configIA/alertes/widget → import partiel, sans crash
//     v2.x : Sans ameliorations IA v6.0   → restaure, formules appliquees
//     v3.0 : Sans widget + double/int fusion → restaure correctement
//     v4.0 : Couverture 100% (groupes separes)
//     v5.0 : Correction caracteres + reinitialisation complete + compteurs corrects
//     v7.2 : +cooldown bulle, +message jour, +heure analyse, +conseils notifiés
//     v7.3 : +résumé hebdo lundi, +anti-doublon cote chute, retrait clé orpheline
//     v7.4 : +bt_discipline, +bt_hippodrome, +flags transitoires ELO/conseils
//     v7.6 : +ia_premium_historique_v1 (étoiles calendrier), +ia_premium_du_jour_v1 (compat)
//     v7.7 : +premium_widgets_selection_jour_v1 (figeage 5 widgets premium du jour)
//     v7.8 : +ia_narrative_memory_v1 (mémoire narrative anti-répétition)
//     v7.9 : +ia_narrative_daily_cache_v1 (cache journalier narratif anti-rebuild)
//     v8.0 : +ia_stats_filtre_actif_v1, +ia_stats_date_debut_v1, +ia_stats_date_fin_v1 (filtres Précision IA — préférences affichage uniquement)
//     v9.0 : +ia_quasi_gros_paris_v1 (Gros paris à surveiller + Quasi gagnants — non recalculable)
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'alert_service.dart'; // ★ v10.26d
import 'elo_service.dart'; // ★ v8.0
import 'cote_tracker_service.dart'; // ★ B5b
import 'ia_memory_service.dart'; // ★ v10.26c
import 'ia_archive_service.dart'; // ★ E3
// ★ L0 : stockage passif des arrivées officielles complètes (lecture seule
//   vis-à-vis de l'apprentissage). Utilisé UNIQUEMENT pour l'export et la
//   restauration des sauvegardes, jamais pour déclencher un calcul.
import 'arrivee_officielle_service.dart';
import 'resultat_officiel_repository.dart'; // ★ BLOC 1 (périmètre financier)
import 'pronostic_resultats_repository.dart'; // ★ v10.85 (B4)
import 'quasi_gros_paris_service.dart'; // ★ v10.72
import 'ia_badges_service.dart'; // ★ B5c
import 'ia_user_prefs_service.dart'; // ★ B5c
import 'data_refresh_service.dart'; // ★ B5c-RDR-01-b
import 'zone_turf_service.dart'; // ★ B5c-RDR-01-b

// ★ ENSEMBLE 4 — nouveau système de sauvegarde/restauration.
import '../data/connaissances/_adapters/pont_elo.dart';
import '../data/connaissances/_migration/migrateur_elo.dart';
import '../data/connaissances/_migration/recuperateur_rapports.dart';
import '../data/connaissances/_sauvegarde/format_sauvegarde.dart';
import '../data/connaissances/_sauvegarde/restaurateur.dart';
import '../data/connaissances/_sauvegarde/transaction_globale.dart';

class BackupService {
  BackupService._();
  static final instance = BackupService._();

  // ── Numero de version du format backup ───────────────────────────────────
  static const _backupVersion =
      '9.1'; // ★ E3 : +archiveIA (archive permanente des pronostics évincés)

  // ════════════════════════════════════════════════════════════════════════
  //  ★ X6 — NOM DE FICHIER DE SAUVEGARDE UNIQUE
  //
  //  DÉFAUT CORRIGÉ (mesuré) : le nom ne portait que le JOUR
  //     'backup_pronostic_hippique_ddMMyyyy.json'
  //  Deux exports effectués le même jour produisaient donc le MÊME nom, donc
  //  le MÊME chemin dans le répertoire temporaire : le second ÉCRASAIT le
  //  premier (`writeAsBytes` sur une `File` existante). Un utilisateur qui
  //  exportait deux fois dans la journée perdait la première sauvegarde sans
  //  le moindre message — et le partage Android proposait alors un fichier
  //  dont le contenu ne correspondait plus à ce qu'il croyait avoir exporté.
  //
  //  CE QUI CHANGE : le nom porte désormais date + heure + millisecondes,
  //     'backup_pronostic_hippique_ddMMyyyy_HHmmssSSS.json'
  //
  //  ⚠️ COMPATIBILITÉ PRÉSERVÉE, ET VÉRIFIABLE :
  //     • le PRÉFIXE 'backup_pronostic_hippique_' et le SUFFIXE '.json' sont
  //       inchangés — c'est ce que le test `v5_backup_restore_test.dart:421-422`
  //       verrouille (`contains` + `endsWith`) ;
  //     • le nom reste un IDENTIFIANT de fichier, jamais une donnée lue pour
  //       restaurer : la restauration ne parse PAS ce nom. Aucune ancienne
  //       sauvegarde ne devient illisible, puisqu'aucun code ne dépend de la
  //       forme exacte du nom.
  //     • le suffixe horaire est APRÈS le jour, donc deux noms d'un MÊME jour se
  //       trient dans l'ordre des heures.
  //       ⚠️ NUANCE MESURÉE : ce tri n'est PAS chronologique ENTRE deux jours
  //       différents d'un même mois ni entre deux mois d'une même année, parce
  //       que le label est `JJMMAAAA` (jour en tête). '01102026' se trie avant
  //       '30092026'. Ce défaut d'ORDRE est antérieur à X6, il n'a AUCUNE
  //       incidence sur l'unicité (qui n'utilise que l'égalité) et sur aucun
  //       autre comportement : le nom n'est jamais trié ni parsé par l'app. Il
  //       est signalé ici pour ne pas laisser croire que la propriété tient.
  //
  //  ⚠️ PORTÉE : cette méthode ne touche NI au contenu JSON, NI à Google Drive,
  //     NI au partage, NI à la restauration. Elle ne produit qu'une chaîne.
  //
  //  ── POURQUOI UN COMPTEUR, ET PAS SEULEMENT L'HORODATAGE (MESURÉ) ─────────
  //     L'exigence « garantir l'absence de collision, même pour deux exports
  //     très rapprochés » ne peut PAS être satisfaite par l'horloge seule. Sur
  //     cette machine, mesuré :
  //       • deux `DateTime.now()` consécutifs partagent la MILLISECONDE dans
  //         199 981 cas sur 200 000 ;
  //       • même en descendant aux MICROSECONDES, le delta est nul dans
  //         90 859 cas sur 100 000.
  //     Un nom purement horodaté serait donc identique en pratique pour deux
  //     exports enchaînés.
  //
  //  ── DÉFAUT DE LA PREMIÈRE CORRECTION, MESURÉ PUIS CORRIGÉ ────────────────
  //     Une première version comparait le nom CANDIDAT au nom ÉMIS juste avant
  //     avec `compareTo`, et n'ajoutait un suffixe `_qN` que si le candidat
  //     n'était pas strictement supérieur. C'ÉTAIT FAUX, pour deux raisons
  //     distinctes :
  //
  //     1) L'ORDRE LEXICOGRAPHIQUE D'UN LABEL `JJMMAAAA` N'EST PAS CHRONOLOGIQUE.
  //          '01102026' < '30092026'  → le 1er octobre « recule » devant le 30/09
  //          '01012027' < '31122026'  → le 1er janvier « recule » devant le 31/12
  //        Un changement de mois, un changement d'année, ou un simple RECUL
  //        d'horloge (resynchronisation NTP) étaient donc interprétés comme un
  //        recul. Mesuré sur la version fautive :
  //          X6f-1 : 01/10/2026 après 30/09/2026 → '..._01102026_000000000_q999'
  //          X6f-2 : 01/01/2027 après 31/12/2026 → '..._01012027_000000000_q999'
  //          X6f-3 : recul de 400 ms le même jour  → '..._140509100_q999'
  //        Le suffixe `_q999` trahissait une plage de suffixes déjà consommée.
  //
  //     2) LA BORNE `sequence < 1000` RENDAIT UN DOUBLON SILENCIEUX.
  //        Quand la plage de suffixes était épuisée, la boucle s'arrêtait et la
  //        fonction rendait `_q999` — un nom DÉJÀ ÉMIS. Mesuré sur la version
  //        fautive :
  //          X6f-4 : 1000 émissions du même instant → 30 noms uniques (970 doublons)
  //          X6f-5 : 1000 émissions après un changement de mois → 1 nom unique
  //          X6f-6 : 7 émissions → 6 noms uniques ('_140509500.json' rendu 2 fois)
  //        C'est exactement l'écrasement que X6 doit empêcher.
  //
  //  ── CE QUI GARANTIT L'UNICITÉ MAINTENANT ─────────────────────────────────
  //     La clé de comptage n'est PLUS le nom de fichier : c'est l'HORODATAGE
  //     lui-même, comparé par ÉGALITÉ et non par ordre. Pour chaque horodatage
  //     (à la milliseconde), un compteur du processus retient combien de noms
  //     ont déjà été émis :
  //        1re émission  → 'backup_pronostic_hippique_JJMMAAAA_HHmmssSSS.json'
  //        2e émission   → '..._HHmmssSSS_q0001.json'
  //        3e émission   → '..._HHmmssSSS_q0002.json'
  //        Ne émission   → '..._HHmmssSSS_q000(N-1).json'
  //     Propriétés, toutes mesurées par les tests X6 :
  //       • deux noms émis ne peuvent pas être égaux : à horodatage égal le
  //         numéro croît, à horodatage différent le label diffère ;
  //       • AUCUNE hypothèse sur l'horloge : un recul, un changement de mois ou
  //         d'année ne change rien, puisque seule l'ÉGALITÉ est utilisée ;
  //       • AUCUNE borne supérieure : le numéro n'est pas tronqué, donc la
  //         fonction ne peut pas « atterrir » sur un nom déjà émis. Il n'y a
  //         plus de `sequence < 1000` ;
  //       • le numéro est écrit sur 4 chiffres (`_q0001`), donc un tri
  //         lexicographique des noms d'un même horodatage reste NUMÉRIQUE
  //         jusqu'à 9 999 exports dans la même milliseconde.
  //     Le suffixe reste APRÈS le label de date, donc le préfixe et le suffixe
  //     `.json` sont inchangés et l'unicité tient sans toucher au format.
  //
  //     ⚠️ MÉMOIRE : une entrée de compteur par HORODATAGE distinct exporté,
  //        soit une poignée d'entrées par jour en usage réel. Aucune purge n'est
  //        faite : purger réintroduirait la collision. La rétention du registre
  //        (lot X1) est un sujet différent et n'est pas traitée ici.
  //
  //     ⚠️ Le garde-fou final est un CONTRÔLE, pas une troncature : si un nom
  //        déjà émis était sur le point d'être rendu, la fonction LÈVE une
  //        `StateError` au lieu de le rendre en silence.
  // ════════════════════════════════════════════════════════════════════════

  /// Nombre de noms déjà émis, par HORODATAGE (clé = label complet
  /// `JJMMAAAA_HHmmssSSS`). Comparaison par ÉGALITÉ : aucune hypothèse sur
  /// l'ordre ni sur la monotonie de l'horloge.
  static final Map<String, int> _compteurParHorodatage = <String, int>{};

  /// Tous les noms déjà émis par [nomFichierBackup] dans ce processus.
  /// Sert uniquement de CONTRÔLE d'invariant : si un candidat y figurait déjà,
  /// ce serait un défaut de la présente logique, et il faut le voir plutôt que
  /// de rendre un doublon.
  static final Set<String> _nomsEmis = <String>{};

  /// Réinitialise l'état de génération. Réservé aux tests : en production l'état
  /// doit survivre à tous les exports du processus, c'est lui qui garantit
  /// l'unicité.
  @visibleForTesting
  static void reinitialiserNomsPourTest() {
    _compteurParHorodatage.clear();
    _nomsEmis.clear();
  }

  /// Nom de fichier de sauvegarde, UNIQUE dans ce processus.
  ///
  /// Format nominal : `backup_pronostic_hippique_ddMMyyyy_HHmmssSSS.json`
  /// (`dd`/`MM`/`yyyy` = jour/mois/année, `HH`/`mm`/`ss` = heure/minute/seconde,
  /// `SSS` = millisecondes), tous les champs à largeur fixe.
  ///
  /// Si ce nom a déjà été émis (deux exports dans la même milliseconde), un
  /// suffixe `_q0001`, `_q0002`… est ajouté AVANT l'extension, à partir de la
  /// DEUXIÈME émission. Exemple réel (mesuré en test, X6b-1) :
  ///   `backup_pronostic_hippique_18112026_140509123.json`
  ///   `backup_pronostic_hippique_18112026_140509123_q0001.json`
  ///   `backup_pronostic_hippique_18112026_140509123_q0002.json`
  ///
  /// Garanties, toutes vérifiables par test :
  ///   • deux appels rendent TOUJOURS deux noms DIFFÉRENTS, même avec le MÊME
  ///     [instant], même après un recul d'horloge, même à un changement de mois
  ///     ou d'année ;
  ///   • l'unicité ne dépend PAS de l'ordre des instants ni de la monotonie de
  ///     l'horloge : seule l'égalité des horodatages est utilisée ;
  ///   • le préfixe `backup_pronostic_hippique_` et le suffixe `.json` sont
  ///     INCHANGÉS (compatibilité des tests et des usages existants) ;
  ///   • aucun nom déjà émis n'est rendu silencieusement : le dépassement de la
  ///     capacité de numérotation lèverait une `StateError` (jamais observé, la
  ///     numérotation n'étant pas bornée).
  ///
  /// [instant] est injecté pour rendre la garantie testable ; en production il
  /// vaut `DateTime.now()`.
  static String nomFichierBackup(DateTime instant) {
    String deux(int v) => v.toString().padLeft(2, '0');
    final String jour = '${deux(instant.day)}${deux(instant.month)}'
        '${instant.year.toString().padLeft(4, '0')}';
    final String heure = '${deux(instant.hour)}${deux(instant.minute)}'
        '${deux(instant.second)}'
        '${instant.millisecond.toString().padLeft(3, '0')}';

    // La clé est l'HORODATAGE, pas le nom : une égalité stricte de chaînes.
    // Aucun `compareTo` n'intervient, donc l'ordre des dates n'a plus
    // d'influence — c'est ce qui neutralise le changement de mois, le
    // changement d'année et le recul d'horloge.
    final String horodatage = '${jour}_$heure';
    final int emission = (_compteurParHorodatage[horodatage] ?? 0) + 1;
    _compteurParHorodatage[horodatage] = emission;

    final String base = 'backup_pronostic_hippique_$horodatage';
    // 1re émission : nom nominal. Ensuite : numéro NON BORNÉ, sur 4 chiffres.
    final String candidat = emission == 1
        ? '$base.json'
        : '${base}_q${(emission - 1).toString().padLeft(4, '0')}.json';

    // CONTRÔLE d'invariant — jamais une troncature. Rendre un nom déjà émis
    // écraserait un fichier existant en silence : on refuse bruyamment.
    if (!_nomsEmis.add(candidat)) {
      throw StateError(
        'X6 : le nom "$candidat" a déjà été émis dans ce processus. '
        'Refus de rendre un doublon (il écraserait une sauvegarde existante).',
      );
    }
    return candidat;
  }

  // ════════════════════════════════════════════════════════════════════════
  //  INVENTAIRE COMPLET DES CLES — toutes les SharedPreferences de l'app
  // ════════════════════════════════════════════════════════════════════════

  // 🧠 Memoire IA — coeur de l'apprentissage
  // ia_poids_v3 inclut : 19 poids adaptatifs + PoidsIndices + momentum
  //                      + poidsParDiscipline + nbMisesAJour + calibration
  //                      + mouvCote (R) + placeDepart (S) + atypiques_YYYY-MM
  static const _keysIA = [
    'ia_pronostics_v2', // 600 pronostics (non compressé — rétrocompatibilité)
    'ia_pronostics_v2_gz', // ★ Lot 4 : pronostics compressés gzip+base64
    'ia_poids_v3', // Poids adaptatifs (19 critères v10.x : +mouvCote, +placeDepart)
    'ia_journal_v2', // Journal gradient (150 entrées) + journées atypiques
    'ia_rapports_v1', // 365 rapports journaliers glissants (★ v9.91 : monté de 60→365)
    'ia_bilans_semaine_v1', // ★ v9.91 : Bilans de semaine archivés
    'ia_bilans_mois_v1', // ★ v9.91 : Bilans de mois archivés
    'ia_derniere_analyse_v1', // ★ v9.6 : Date dernière analyse (pour rappel Worker Kotlin)
    'ia_stats_types_v1', // Stats cumulatives par type de pari
    'ia_precision_v2', // Précision IA par type de pari
    'ia_stats_labels_v1', // ★ v9.0 : Stats par label IA
    'ia_seuils_v1', // Seuils de confiance adaptatifs
    // ★ v10.38 : Historique premium calendrier (étoiles multi-jours)
    'ia_premium_historique_v1', // Historique premium calendrier étoile (non recalculable)
    'ia_premium_du_jour_v1', // Ancien format compat (lecture seule — migration vers _historique)
    // ★ v10.62 : Figeage des 5 widgets premium du jour (conseilJour/meilleurPari/topEquilibre/plusSur/plusRentable)
    // Non recalculable — doit être restauré pour préserver le figeage inter-sessions.
    'premium_widgets_selection_jour_v1',
    // Note : ia_rapport_hebdo_v1 retiré (jamais écrit — clé orpheline v9.87)
  ];

  // 📡 ELO & Cote — données dynamiques par discipline
  static const _keysELO = [
    'elo_ratings_v2', // ★ v9.92 : Ratings ELO par cheval×discipline (K-factor adaptatif)
    'elo_ratings_v2_ts', // ★ v9.92 : Timestamp dernière mise à jour ELO
    'elo_ratings_v1', // ★ B5 : relique de migration — réimportée par EloService
    //   au démarrage (_charger l.66) si elo_ratings_v2 est
    //   absente. Sans cette ligne, un reset complet laisse la
    //   clé v1 sur le disque et les anciens ratings
    //   ressuscitent au prochain lancement.
    'cote_tracker_mouvements_v1', // ★ v9.97 : Mouvements de cote en temps réel
    'cote_mouvements_live_v1', // ★ v9.97 : Sync Flutter→Kotlin Worker (alertes cote)
    // ★ A7 (3.1) : registre d'application ELO — clé SÉPARÉE de
    //   `elo_ratings_v2`, qui garde son format plat. Le registre est un
    //   TÉMOIN d'application : il ne duplique AUCUN rating et ne doit
    //   JAMAIS servir de source pour reconstruire `elo_ratings_v2`.
    //
    //   POURQUOI ICI, ET PAS AILLEURS : les ratings et leur témoin doivent
    //   appartenir au MÊME périmètre. Mesuré : sans cette ligne, un reset
    //   complet efface `elo_ratings_v2` mais LAISSE le registre sur le
    //   disque — le registre témoignerait alors de courses dont les ratings
    //   n'existent plus, c'est-à-dire l'état « appliqué » sans la donnée.
    //   Le contrat de reset est donc : les deux disparaissent ensemble.
    'elo_registre_v3', // ★ A7 : témoin d'application ELO (jamais
    //   une source de reconstruction)
  ];

  // 🎯 Config fusion BestBet — 4 cles HERITEES, MODULE SUPPRIME (BL1-A16)
  // IMPORTANT : fusion_poids_* sont stockes en DOUBLE, fusion_seuil_min en INT
  // On les serialise tous en String JSON pour une restauration universelle
  // ⚠️ CONSERVER CES 4 CLES : une sauvegarde ancienne doit rester restaurable.
  //    Aucun module ne les lit plus ; leur presence ici est de la
  //    COMPATIBILITE, pas une fonctionnalite.
  static const _keysConfigIA = [
    'fusion_poids_confiance',
    'fusion_poids_gain',
    'fusion_poids_risque',
    'fusion_seuil_min',
    // ★ v9.80 : Préférences Backtesting
    'bt_mise',
    'bt_jours',
    'bt_type',
    'bt_confiance_min',
    'bt_discipline', // ★ v10.371-audit : filtre discipline backtesting
    'bt_hippodrome', // ★ v10.371-audit : filtre hippodrome backtesting
    // ★ v10.22 : Filtres Conseils IA (persistés dans conseils_screen.dart)
    'conseils_filtres_types_paris',
    'conseils_filtres_confiance_min',
    'conseils_filtres_hippodromes',
    'conseils_filtres_disciplines',
    'conseils_filtres_tri_mode', // ★ v10.24 audit
    'conseils_filtres_actifs', // ★ v9.93 : état ON/OFF bouton filtres
    // ★ v9.85 : Identité de l'IA
    'ia_prenom',
    'ia_avatar_id',
    'ia_date_installation',
    'ia_bulle_active',
    // ★ v9.94 : Cooldown bulle et message du jour (manquants dans v7.1)
    'ia_derniere_bulle', // Timestamp dernière bulle affichée (cooldown 30min)
    'ia_dernier_message_jour', // Message IA du jour (évite répétition)
    // ★ v9.85 : Préférences utilisateur et badges
    'ia_user_prefs_v1',
    'ia_badges_v1',
    // ★ v10.27 : Seuils paliers calendrier (editables par l'utilisateur)
    'ia_calendrier_seuils_v1',
    // ★ v10.34/v10.35 : Flags migration précision (recalcul après fix Couplé)
    'ia_precision_migrated_v2',
    'ia_precision_migrated_v3',
    // ★ v10.65 : Mémoire narrative anti-répétition (secondaire — recréable si absente)
    // Si absente dans un ancien backup : créée vide automatiquement, jamais crash
    'ia_narrative_memory_v1',
    // ★ v10.66 : Cache narratif journalier (secondaire — recréable proprement si absent)
    // En cas d'absence dans un ancien backup → reset cache uniquement, jamais bloquer la restauration
    'ia_narrative_daily_cache_v1',
    // ★ v10.371-audit : flags transitoires (one-shot — restaurer évite un recalcul inutile)
    'elo_orphelins_purges_v1', // Flag purge ELO orphelins (elo_service)
    'conseils_inject_pending', // Flag injection conseils en attente
    // ★ v10.70 : Filtres Précision IA (préférences d'affichage uniquement)
    // Ces clés NE touchent PAS : apprentissage IA, poids, premium, backtesting, calendrier.
    // Si absentes dans un ancien backup → filtre par défaut '60j' utilisé. Jamais bloquant.
    'ia_stats_filtre_actif_v1', // Filtre actif : '60j', 'all', '7j', 'today', 'custom'
    'ia_stats_date_debut_v1', // Date début période personnalisée (ISO 8601)
    'ia_stats_date_fin_v1', // Date fin période personnalisée (ISO 8601)
  ];

  // 📋 Paris utilisateur — historique complet
  static const _keysParis = [
    'user_predictions_v2',
  ];

  // 🔔 Alertes — config + historique + courses suivies
  static const _keysAlertes = [
    'alert_config_v2',
    'alert_history_v1',
    'tracked_courses_v1',
    'alert_sent_ids_v1',
    'alert_resultats_verifies_v1',
    'hippique_favorites_v1', // ★ v9.5 : Cours favorites (FavoriButton)
    // ★ v9.94 : Conseils IA notifiés (anti-spam + résumé matinal)
    'conseil_ia_notifies_v1', // CourseKeys déjà notifiées ce jour
    // ★ B5c R-12 : marqueur de jour associé à 'conseil_ia_notifies_v1'.
    //   Cette clé était absente de TOUS les groupes : elle survivait donc au
    //   reset complet. Conséquence : `_resetConseilIANotifiesIfNewDay()`
    //   comparait `stored == todayKey`, concluait « même jour » et ne remettait
    //   jamais le compteur anti-doublon à zéro APRÈS le vidage — tout en
    //   réécrivant la liste effacée au passage.
    'conseil_ia_notifies_v1_date',
    'conseil_ia_resume_date', // Date du dernier résumé matinal
    // ★ v9.94-audit : clés manquantes
    'alert_cote_chute_notifies_v1', // Anti-doublons alertes cote chute (alert_service)
    'data_refresh_resume_hebdo_date', // Date dernier résumé hebdo lundi (data_refresh_service)
    'alerte_sommeil_v1', // ★ v10.41 : Mode Sommeil — plage horaire sans alertes
    // ★ CHANTIER 2/3 — IDEMPOTENCE DES GAINS OFFICIELS TARDIFS.
    //
    //   DÉFAUT QUE CETTE PRÉSENCE CORRIGE : sans elle, un export/restauration
    //   reperdait les trois familles de marqueurs (`ge1:` écriture, `gt1:`
    //   notification, `gd1:` décision). Conséquences mesurables : une
    //   notification DÉJÀ ÉMISE était réémise après restauration, et une
    //   reprise d'écriture était retentée inutilement.
    //
    //   ⚠️ ELLE EST PLACÉE DANS LE GROUPE « ALERTES », ET C'EST DÉLIBÉRÉ :
    //      ce groupe est le seul dont la sauvegarde ET la restauration
    //      passent par `_lireEntree` / `_restaurerGroupe`, donc la seule
    //      façon d'obtenir la couverture complète sans écrire un second
    //      chemin d'export. La nommer « alertes » reste exact : c'est bien
    //      l'état de la remontée d'alerte qui est conservé.
    //
    //   ⚠️ CETTE CLÉ N'EST PAS FINANCIÈRE. Sa perte ne fausse aucun montant :
    //      elle ne peut produire qu'un doublon visuel ou une reprise
    //      inutile. Les montants, décisions et remboursements vivent dans
    //      `user_predictions_v2`, déjà sauvegardé dans `_keysParis`.
    'gains_tardifs_notifies_v1',
    // ★ CHANTIER 2/3 — temporisation des tentatives (15 min → 48 h, sans
    //   abandon définitif). La perdre ne fait que réinterroger plus tôt : ce
    //   n'est pas une donnée financière, mais sa conservation évite une rafale
    //   de requêtes juste après une restauration.
    'gains_tardifs_backoff_v1',
  ];

  // 👤 Profil — identite de l'utilisateur
  // profil_photo_path exclu : chemin local non portable entre telephones
  static const _keysProfil = [
    'profil_nom',
    'profil_gmail',
    'chevaux_suivis_v1',
    // ★ v9.85 : Bankroll
    'bankroll_capital_v1',
    // ★ v9.94 : Heure dernière analyse (manquante dans v7.1)
    'ia_derniere_analyse_heure_v1', // Heure précise de la dernière analyse journée
  ];

  // 📱 Widget Android — etat du widget affiche sur l'ecran d'accueil
  // Clés alignées avec widget_service.dart (écrites via MethodChannel → RacePredictorWidgetData)
  // NOTE : ces clés sont dans FlutterSharedPreferences (préfixe flutter. ajouté automatiquement)
  // mais le widget natif lit dans RacePredictorWidgetData via son propre getSharedPreferences.
  // Le backup de ces clés sert à restaurer l'affichage inter-sessions (régénéré au prochain refresh).
  static const _keysWidget = [
    'widget_course_name',
    'widget_horse_name',
    'widget_horse_num',
    'widget_confiance',
    'widget_gain',
    'widget_hippodrome',
    'widget_heure',
    'widget_nb_courses',
    'widget_updated_at',
    // ★ Lot 4 : nouveaux champs widget v2.0
    'widget_score_ia',
    'widget_type_pari',
    'widget_tendance',
    'widget_elo',
    'widget_course2_name',
    'widget_horse2_name',
    'widget_heure2',
    'widget_confiance2',
    'widget_course3_name',
    'widget_horse3_name',
    'widget_heure3',
    'widget_confiance3',
    // ★ v10.24 audit : Feature #7 — compteur Conseils IA + forme top cheval
    'widget_nb_criteres',
    'widget_forme',
  ];

  // 🧪 Labo IA — pistes de simulation sauvegardées par l'utilisateur
  // OBLIGATOIRE : non recalculable (données saisies manuellement par l'utilisateur)
  static const _keysLaboIA = [
    'simulation_candidates_v1', // Pistes Labo IA (SimulationCandidateService)
  ];

  // 📊 Cache Audit — résultats pré-calculés des 4 onglets Audit
  // OPTIONNEL : recalculable, mais évite 30s de recalcul au premier lancement
  static const _keysAuditCache = [
    'ia_audit_cache_v1', // Cache des onglets Audit (IaAuditCacheService)
  ];

  // ⚠️ Gros Paris — signaux Gros paris à surveiller + Quasi gagnants archivés
  // OBLIGATOIRE : non recalculable (signaux d'avant-course disparus après la course)
  // Rétrocompat : absent dans un ancien backup → reset à liste vide (jamais crash)
  static const _keysGrosParis = [
    'ia_quasi_gros_paris_v1', // ★ v10.72 : Signaux Gros paris + Quasi gagnants
    'ia_gros_paris_resultats_v1', // ★ v10.75b : Vrais gagnants ordre/désordre
    // ★ v10.76 : Nouvelles clés
    'pronostic_resultats_repository_v2', // Repository résultats utilisateur
    'home_best_bet_snapshot_v2', // Snapshot "Meilleur Pari" Home
    'home_best_bet_snapshot_date_v2', // Date snapshot Home
    'ia_migration_gros_paris_desordre_v1_done', // Flag migration one-shot v10.76
    // ★ v10.77 : Migration stats — branchement PronosticResultatsRepository dans écrans stats
    'ia_migration_gros_paris_stats_v2_done', // Flag migration stats v10.77
    // ★ v10.79 : Migration types dérivés — évalue Tiercé/Quarté+/Quinté+ séparément
    'ia_migration_gros_paris_types_derives_v1_done', // Flag migration types dérivés v10.79
    // ★ v10.80 : Migration suite IA classique — réussites dérivées depuis topNIA figé
    'ia_migration_suite_ia_classique_v1_done', // Flag migration suite IA classique v10.80
  ];

  // 📨 File de notifications natives en attente (lue par HippiqueWorker.kt)
  //
  // ★ B5c R-13 : cette clé est écrite par `AlertService._sendNativeNotification()`
  //   et consommée par le Worker Kotlin. Elle n'était effacée par aucun groupe,
  //   donc jusqu'à 10 anciennes notifications pouvaient encore sortir après un
  //   reset complet.
  //
  //   Volontairement ABSENTE de `_collecterDonnees()` : restaurer une file de
  //   notifications périmées n'a aucun sens. Présente dans `_toutesLesCles` et
  //   dans `reinitialiserAlertes()`.
  //
  //   Rappel technique : `SharedPreferences` préfixe TOUTE clé par 'flutter.'
  //   côté natif (shared_preferences_legacy.dart:173). La clé réellement écrite
  //   par Dart est donc 'flutter.flutter.hippique_pending_notifs', et c'est
  //   bien celle-ci qu'un `prefs.remove('flutter.hippique_pending_notifs')`
  //   supprime — le préfixe est ajouté automatiquement.
  static const _keysNotificationsEnAttente = [
    'flutter.hippique_pending_notifs',
  ];

  // Toutes les cles reunies (pour reinitialisation complete)
  // ★ B5c-RDR-01-a — PRÉFIXE DES CLÉS DE CACHE DYNAMIQUES.
  //
  //  `DataRefreshService` persiste le programme du jour sous DEUX clés dont le
  //  nom dépend de la date (data_refresh_service.dart l.180, l.288, l.329-330) :
  //      cache_reunions_<ddmmyyyy>        → JSON des réunions
  //      cache_reunions_<ddmmyyyy>_ts     → horodatage (epoch ms)
  //
  //  Une clé dynamique ne peut pas être nommée dans une liste fixe : elle
  //  échappait donc totalement à `_toutesLesCles` (mesuré V31 R01-B : les deux
  //  clés survivaient au reset, puis étaient réinjectées par
  //  `_chargerCacheLocal()` — mesuré V31 R01-F).
  //
  //  La constante est DUPLIQUÉE depuis `DataRefreshService._prefsCachePrefix`,
  //  qui est privée et donc inaccessible ici. La duplication est volontaire :
  //  la seule alternative serait d'élargir l'API publique de DataRefreshService,
  //  ce qui est hors du périmètre autorisé de cette correction. Le préfixe est
  //  une constante de persistance, pas une règle métier : il ne doit pas varier.
  static const String _prefsCacheReunionsPrefix = 'cache_reunions_';

  static List<String> get _toutesLesCles => [
        ..._keysIA,
        ..._keysConfigIA,
        ..._keysELO, // ★ B5 : les 5 cles ELO/Cote etaient OMISES — elles
        //   survivaient a un reset « complet » alors qu'elles
        //   sont bel et bien sauvegardees dans le backup.
        //   ★ A7 (3.1) : le groupe compte desormais 6 cles,
        //   `elo_registre_v3` ayant rejoint le perimetre.
        ..._keysParis,
        ..._keysAlertes,
        ..._keysProfil,
        ..._keysWidget,
        ..._keysLaboIA,
        ..._keysAuditCache,
        ..._keysGrosParis,
        ..._keysNotificationsEnAttente, // ★ B5c R-13
      ];

  /// ★ CHANTIER 2/3 — LE PÉRIMÈTRE RÉELLEMENT SAUVEGARDÉ, POUR LES TESTS.
  ///
  /// Rend la liste EXACTE utilisée par la sauvegarde et par la réinitialisation
  /// complète (`_toutesLesCles`), sans la recopier. Un test qui recopierait la
  /// liste ne prouverait rien : il vérifierait sa propre copie.
  ///
  /// ⚠️ Lecture seule : aucune écriture, aucune modification du périmètre.
  @visibleForTesting
  static List<String> clesSauvegardeesPourTest() =>
      List<String>.unmodifiable(_toutesLesCles);

  // ════════════════════════════════════════════════════════════════════════
  //  LECTURE UNIVERSELLE — supporte StringList, String, int, double, bool
  // ════════════════════════════════════════════════════════════════════════

  /// Lit une cle SharedPreferences en detectant automatiquement son type.
  /// Retourne null si la cle n'existe pas.
  Map<String, dynamic>? _lireEntree(SharedPreferences prefs, String key) {
    // Priority 1 : StringList (ia_pronostics_v2, ia_journal_v2, etc.)
    try {
      final list = prefs.getStringList(key);
      if (list != null) return {'type': 'StringList', 'value': list};
    } catch (_) {}

    // Priority 2 : Scalaire via prefs.get()
    final v = prefs.get(key);
    if (v == null) return null;
    if (v is String) return {'type': 'String', 'value': v};
    if (v is int) return {'type': 'int', 'value': v};
    if (v is double) return {'type': 'double', 'value': v};
    if (v is bool) return {'type': 'bool', 'value': v};
    if (v is List) {
      return {
        'type': 'StringList',
        'value': List<String>.from(v.map((e) => e.toString()))
      };
    }
    return null;
  }

  // ════════════════════════════════════════════════════════════════════════
  //  COLLECTE — lit TOUTES les donnees de l'app
  // ════════════════════════════════════════════════════════════════════════

  Future<({Map<String, dynamic> data, List<String> avertissements})>
      _collecterDonnees() async {
    final prefs = await SharedPreferences.getInstance();

    // ★ A7 (3.3-C11) — CANAL D'AVERTISSEMENTS DE LA COLLECTE.
    //
    // ⚠️ POURQUOI UN ENREGISTREMENT ET NON UNE CLÉ DANS `data`
    //   Une clé `_avertissements` serait écrite DANS le fichier sauvegardé :
    //   elle polluerait le format et serait relue par les versions futures.
    //   Une liste locale ne sort de la méthode que par le type de retour.
    //
    // ⚠️ CE CANAL N'EST PAS UTILISÉ PAR TOUS LES GROUPES, ET C'EST VOULU.
    //   Les quatre groupes GRO / REP / ARC / ARR gardent leur `catch` muet
    //   historique (règle « local préservé » à la restauration). Les y verser
    //   dans ce lot changerait le comportement d'export de groupes qui ne sont
    //   pas dans le périmètre autorisé de C11.
    final avertissements = <String>[];

    final data = <String, dynamic>{
      'version': _backupVersion,
      'appName': 'Pronostic Hippique',
      'dateBackup': DateTime.now().toIso8601String(),
      'ia': <String, dynamic>{},
      'configIA': <String, dynamic>{},
      'paris': <String, dynamic>{},
      'alertes': <String, dynamic>{},
      'profil': <String, dynamic>{},
      'widget': <String, dynamic>{},
      'laboIA': <String, dynamic>{}, // ★ v10.35 : Pistes Labo IA
      'auditCache': <String, dynamic>{}, // ★ v10.35 : Cache Audit
      'grosParis': <String, dynamic>{}, // ★ v10.72 : Gros Paris à surveiller
    };

    // ── 🧠 Memoire IA ────────────────────────────────────────────────────
    for (final key in _keysIA) {
      final entry = _lireEntree(prefs, key);
      if (entry != null) {
        data['ia'][key] = entry;
        if (kDebugMode) {
          final val = entry['value'];
          final info =
              val is List ? '${val.length} entrees' : 'ok (${entry['type']})';
          debugPrint('[Backup] IA  $key -> $info');
        }
      } else {
        if (kDebugMode) debugPrint('[Backup] IA  $key -> ABSENT (ok)');
      }
    }

    // ── 🎯 Config Fusion BestBet ─────────────────────────────────────────
    // fusion_poids_* : double | fusion_seuil_min : int
    for (final key in _keysConfigIA) {
      final entry = _lireEntree(prefs, key);
      if (entry != null) {
        data['configIA'][key] = entry;
        if (kDebugMode) debugPrint('[Backup] CFG $key -> ${entry['value']}');
      }
    }

    // ── 📋 Paris utilisateur ─────────────────────────────────────────────
    for (final key in _keysParis) {
      final list = prefs.getStringList(key) ?? [];
      data['paris'][key] = {'type': 'StringList', 'value': list};
      if (kDebugMode) debugPrint('[Backup] PAR $key -> ${list.length} paris');
    }

    // ── 🔔 Alertes ────────────────────────────────────────────────────────
    for (final key in _keysAlertes) {
      final entry = _lireEntree(prefs, key);
      if (entry != null) {
        data['alertes'][key] = entry;
        if (kDebugMode) {
          final val = entry['value'];
          final info = val is List ? '${val.length} entrees' : 'ok';
          debugPrint('[Backup] ALT $key -> $info');
        }
      }
    }

    // ── 👤 Profil ─────────────────────────────────────────────────────────
    for (final key in _keysProfil) {
      final entry = _lireEntree(prefs, key);
      if (entry != null) {
        data['profil'][key] = entry;
        if (kDebugMode) debugPrint('[Backup] PRF $key -> ok');
      }
    }

    // ── 📱 Widget Android ─────────────────────────────────────────────────
    for (final key in _keysWidget) {
      final entry = _lireEntree(prefs, key);
      if (entry != null) {
        data['widget'][key] = entry;
        if (kDebugMode) debugPrint('[Backup] WGT $key -> ok');
      }
    }

    // ── 🧪 Labo IA — pistes de simulation ★ v10.35 ───────────────────────
    for (final key in _keysLaboIA) {
      final entry = _lireEntree(prefs, key);
      if (entry != null) {
        data['laboIA'][key] = entry;
        if (kDebugMode) {
          final val = entry['value'];
          final info =
              val is List ? '${val.length} pistes' : 'ok (${entry['type']})';
          debugPrint('[Backup] LAB $key -> $info');
        }
      } else {
        if (kDebugMode) debugPrint('[Backup] LAB $key -> ABSENT (ok)');
      }
    }

    // ── 📊 Cache Audit — ★ v10.35 ────────────────────────────────────────
    for (final key in _keysAuditCache) {
      final entry = _lireEntree(prefs, key);
      if (entry != null) {
        data['auditCache'][key] = entry;
        if (kDebugMode) debugPrint('[Backup] AUD $key -> ok');
      } else {
        if (kDebugMode) debugPrint('[Backup] AUD $key -> ABSENT (ok)');
      }
    }

    // ── ⚠️ Gros Paris ★ v10.72 / v10.75b ──────────────────────────────────────
    // Les données sont gérées par QuasiGrosParisService (pas des SharedPreferences
    // classiques) — on les exporte via la méthode dédiée du service.
    // ★ v10.75b : inclut maintenant grosParisGagnants (ia_gros_paris_resultats_v1)
    try {
      final grosParisData = QuasiGrosParisService.instance.exporterPourBackup();
      if (grosParisData.isNotEmpty) {
        data['grosParis'] = grosParisData;
        if (kDebugMode) {
          final nbSignaux = (grosParisData['signaux'] as List? ?? []).length;
          final nbQG = (grosParisData['quasiGagnants'] as List? ?? []).length;
          final nbGagnants =
              (grosParisData['grosParisGagnants'] as List? ?? []).length;
          debugPrint(
              '[Backup] GRO -> $nbSignaux signaux, $nbQG quasi-gagnants, '
              '$nbGagnants gagnants (ia_gros_paris_resultats_v1)');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Backup] GRO export partiel : $e');
    }

    // ── 📊 Résultats des Gros Paris ★ v10.85 — B4 ──────────────────────────
    // `pronostic_resultats_repository_v2` était DÉCLARÉE dans _keysGrosParis
    // mais n'était JAMAIS collectée (aucune boucle _lireEntree ne parcourt
    // cette liste) : résultats gagnants/perdants, ordre exact, numéros
    // trouvés et dates des Gros Paris étaient donc perdus à la restauration.
    // (PronosticResultatUtilisateur ne porte aucun champ monétaire :
    //  ni montant ni mise — seulement gagnant/perdant, ordreExact,
    //  nbTrouves/nbRequis, predictionIA, arriveePMUComplete, source.)
    //
    // Même approche qu'EloService : le repository expose déjà
    // `exporterPourBackup()` / `restaurerDepuisBackup()` — on les utilise.
    // Lecture seule ici : exporterPourBackup() ne fait que sérialiser _items,
    // il ne modifie ni ne recalcule aucune donnée.
    try {
      final repoResultats =
          PronosticResultatsRepository.instance.exporterPourBackup();
      if (repoResultats.isNotEmpty) {
        data['resultatsGrosParis'] = repoResultats;
        if (kDebugMode) {
          debugPrint('[Backup] REP -> '
              '${repoResultats['nbResultats']} résultats '
              '(${repoResultats['nbGagnants']} gagnants)');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Backup] REP export partiel : $e');
    }

    // ── 🗄️ ARCHIVE HISTORIQUE IA ★ E3 ───────────────────────────────────────
    // Archive permanente des pronostics évincés : manifeste + TOUS les shards
    // mensuels (gzip+base64) + fiches détaillées complètes + les évictions dont
    // l'écriture n'a pas encore été confirmée (sinon perdues au changement de
    // téléphone). Lecture seule vis-à-vis de l'apprentissage : ni _poids, ni
    // _seuils, aucun recalcul de pronostic.
    try {
      final archiveData = await IaArchiveService.instance.exporterPourBackup();
      data['archiveIA'] = archiveData;
      if (kDebugMode) {
        debugPrint('[Backup] ARC -> ${archiveData['nbShards']} shard(s), '
            '${archiveData['nbVersions']} version(s), '
            '${archiveData['nbPredictions']} prédiction(s), '
            '${archiveData['nbEnAttente']} en attente');
      }
    } catch (e) {
      // Clé ABSENTE en cas d'échec = règle « local préservé » à la restauration.
      if (kDebugMode) debugPrint('[Backup] ARC export partiel : $e');
    }

    // ── 🏁 ARRIVÉES OFFICIELLES COMPLÈTES ★ L0 ─────────────────────────────
    // Stockage passif des arrivées PMU complètes (`ordreArrivee` de la course,
    // ex æquo conservés). Découverte DYNAMIQUE des clés mensuelles par
    // `exporterPourBackup()` : une liste figée de mois ne pourrait pas couvrir
    // un mois écrit par une version future de l'application.
    //
    // Lecture seule vis-à-vis de l'apprentissage : ce bloc ne lit, ne modifie
    // et ne réécrit AUCUNE donnée de `IaMemoryService`, d'`EloService` ou des
    // statistiques. Il ne fait que recopier des clés de stockage.
    try {
      final arriveesData =
          await ArriveeOfficielleService.instance.exporterPourBackup();
      data['arriveesOfficielles'] = arriveesData;
      if (kDebugMode) {
        debugPrint('[Backup] ARR -> ${arriveesData['nbClefs']} shard(s) '
            'mensuel(s), ${(arriveesData['enAttente'] as List).length} '
            'en attente');
      }
    } catch (e) {
      // Clé ABSENTE en cas d'échec = règle « local préservé » à la restauration.
      if (kDebugMode) debugPrint('[Backup] ARR export partiel : $e');
    }

    // ── 💰 RÉSULTATS OFFICIELS PMU ★ BLOC 1 (périmètre financier) ─────────
    // Persistance PARTAGÉE des résultats officiels complets, indexée par
    // identité de course (date + réunion + course) : arrivées groupées,
    // caractère définitif / provisoire / inconnu, rapports officiels, statuts
    // des partants.
    //
    // Pourquoi une entrée PAR COURSE et non des rapports dans chaque
    // `IaPronostic` : dupliquer tous les rapports dans chaque pronostic
    // gonflerait la mémoire et rendrait toute mise à jour incohérente. Une
    // entrée, partagée par tous les paris de la course.
    //
    // Lecture seule vis-à-vis de l'apprentissage : ce bloc ne déclenche AUCUN
    // apprentissage, ne recalcule AUCUN score historique et ne réécrit aucune
    // donnée de `IaMemoryService`.
    try {
      final resultatsData =
          await ResultatOfficielRepository.instance.exporterPourBackup();
      data['resultatsOfficielsPmu'] = resultatsData;
      if (kDebugMode) {
        debugPrint('[Backup] ROP -> ${resultatsData['nbEntrees']} entrée(s), '
            '${(resultatsData['moisConnus'] as List).length} mois');
      }
    } catch (e) {
      // Clé ABSENTE en cas d'échec = règle « local préservé » à la restauration.
      if (kDebugMode) debugPrint('[Backup] ROP export partiel : $e');
    }

    // ── 🏇 ELO SERVICE ★ A7 (3.3-C11) ──────────────────────────────────────
    // `exporterPourBackupEnrichi()` rend un STATUT en plus des données. C'est
    // ce qui permet de distinguer trois situations que l'ancien code
    // confondait toutes en une seule : « pas de données ELO ».
    //
    //   • `complet`              → registre présent, interprétable et cohérent.
    //   • `sansRegistre`         → absence RÉELLE du registre, diagnostic établi.
    //                              Ratings exportés, registre JAMAIS inventé.
    //   • `refuse`               → registre corrompu / incompatible / divergent,
    //                              ou RAM divergente du disque.
    //   • `diagnosticImpossible` → état ELO illisible.
    //
    // ⚠️ DÉCISION DE SÉCURITÉ — `refuse` ET `diagnosticImpossible` N'ÉCRIVENT
    //    AUCUN groupe, pas même un groupe vide.
    //      Écrire `'elo_service': {}` reviendrait, à la restauration, à
    //      ÉCRASER les ratings d'un appareil par une écurie vide. L'absence
    //      de clé est traitée par l'importeur comme « pas de volet ELO »
    //      (règle « local préservé »), donc l'absence est PLUS SÛRE qu'un
    //      groupe vide. Le refus n'est pas masqué : il est SIGNALÉ.
    //
    // ⚠️ EXCEPTION INATTENDUE — COMPORTEMENT HISTORIQUE CONSERVÉ.
    //    Avant C11, `exporterPourBackup()` n'était dans AUCUN `try` : une
    //    exception faisait échouer TOUT l'export. Ce lot ne la transforme
    //    pas en simple avertissement : sans `try` autour, elle remonte à
    //    `exporterDonnees()`, qui rend `succes: false`. C'est l'arbitrage
    //    « échec global » retenu.
    final ResultatExportElo eloEnrichi =
        await EloService.instance.exporterPourBackupEnrichi();

    switch (eloEnrichi.statut) {
      case StatutExportElo.complet:
        data['elo_service'] = eloEnrichi.groupe;
        if (kDebugMode) {
          debugPrint('[Backup] ELO -> ${eloEnrichi.groupe.length} clefs '
              '(complet, registre inclus)');
        }
      case StatutExportElo.sansRegistre:
        data['elo_service'] = eloEnrichi.groupe;
        if (kDebugMode) {
          debugPrint('[Backup] ELO -> ${eloEnrichi.groupe.length} clefs '
              '(sansRegistre)');
        }
        avertissements.add(
            'ELO : ratings sauvegardés SANS le registre d\'historique '
            '(registre absent sur cet appareil). Aucune protection '
            'anti-double-application n\'est revendiquée par cette sauvegarde.');
      case StatutExportElo.refuse:
        avertissements.add(
            'ELO NON SAUVEGARDÉ : ${eloEnrichi.motif ?? "motif non renseigné"}. '
            'Les ratings ELO ne figurent PAS dans cette sauvegarde.');
        if (kDebugMode) {
          debugPrint(
              '[Backup] ⚠️ ELO REFUSÉ — aucune clé `elo_service` écrite : '
              '${eloEnrichi.motif}');
        }
      case StatutExportElo.diagnosticImpossible:
        avertissements.add('ELO NON SAUVEGARDÉ : état ELO illisible '
            '(${eloEnrichi.motif ?? "motif non renseigné"}). '
            'Les ratings ELO ne figurent PAS dans cette sauvegarde.');
        if (kDebugMode) {
          debugPrint('[Backup] ⚠️ ELO INDISPONIBLE — aucune clé `elo_service` '
              'écrite : ${eloEnrichi.motif}');
        }
    }

    // ── 📡 CoteTracker ★ v9.97 ─────────────────────────────────────────────
    // Mouvements de cote en temps réel + sync Flutter→Kotlin Worker
    data['cote'] = <String, dynamic>{};
    for (final key in _keysELO.where((k) => k.startsWith('cote_'))) {
      final entry = _lireEntree(prefs, key);
      if (entry != null) {
        data['cote'][key] = entry;
        if (kDebugMode) debugPrint('[Backup] COT $key -> ok');
      }
    }

    return (data: data, avertissements: avertissements);
  }

  // ════════════════════════════════════════════════════════════════════════
  //  RESTAURATION UNIVERSELLE d'un groupe de cles
  // ════════════════════════════════════════════════════════════════════════

  Future<int> _restaurerGroupe(
    SharedPreferences prefs,
    Map<String, dynamic>? groupe,
  ) async {
    if (groupe == null) return 0;
    int nbRestaurees = 0;

    for (final entry in groupe.entries) {
      final key = entry.key;
      final raw = entry.value;

      try {
        // Format v4.0/v5.0 : {'type': '...', 'value': ...}
        if (raw is Map<String, dynamic> &&
            raw.containsKey('type') &&
            raw.containsKey('value')) {
          final type = raw['type'] as String;
          final val = raw['value'];

          switch (type) {
            case 'StringList':
              final list =
                  List<String>.from((val as List).map((e) => e.toString()));
              await prefs.setStringList(key, list);
            case 'String':
              await prefs.setString(key, val as String);
            case 'int':
              // Robustesse : val peut etre int ou double selon JSON parse
              await prefs.setInt(key, (val as num).toInt());
            case 'double':
              await prefs.setDouble(key, (val as num).toDouble());
            case 'bool':
              await prefs.setBool(key, val as bool);
            default:
              // Fallback : si type inconnu, tenter String
              await prefs.setString(key, val.toString());
          }
          nbRestaurees++;
        }
        // Retrocompatibilite v1–v3 : valeur brute sans enveloppe 'type'
        else if (raw is List) {
          final list = List<String>.from(raw.map((e) => e.toString()));
          await prefs.setStringList(key, list);
          nbRestaurees++;
        } else if (raw is String) {
          await prefs.setString(key, raw);
          nbRestaurees++;
        } else if (raw is int) {
          await prefs.setInt(key, raw);
          nbRestaurees++;
        } else if (raw is double) {
          await prefs.setDouble(key, raw);
          nbRestaurees++;
        } else if (raw is bool) {
          await prefs.setBool(key, raw);
          nbRestaurees++;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[Backup] Restauration $key : $e');
      }
    }
    return nbRestaurees;
  }

  // ════════════════════════════════════════════════════════════════════════
  //  ★ v10.84 — B1/B3 : choix de l'UNIQUE format de pronostics à conserver
  //
  //  Contexte du défaut (V5/T3, V5/T4b, V5/T11)
  //  ────────────────────────────────────────────────────────────────────
  //  Les pronostics sont stockés sous DEUX clés possibles :
  //    • ia_pronostics_v2      → StringList JSON (format ancien)
  //    • ia_pronostics_v2_gz   → String base64(gzip(json)) (format actuel)
  //  `_save()` n'en laisse jamais qu'une, mais `_restaurerGroupe()` écrit
  //  ce que contient le backup SANS supprimer la clé du format OPPOSÉ déjà
  //  présente sur l'appareil. Résultat : les deux clés coexistent, et
  //  `_load()` donnant la priorité au gzip (ia_memory_service.dart:1325),
  //  la mémoire IA rechargeait l'ANCIEN jeu local au lieu de celui du
  //  backup. Le résidu JSON pouvait aussi ressusciter via le `catch` de
  //  `_load()` (l.1338) si le gzip devenait illisible.
  //
  //  Règle appliquée ici — une seule version, jamais de mélange :
  //    • backup avec une seule clé        → cette clé gagne, l'autre est purgée
  //    • backup avec les deux clés        → la PLUS RICHE gagne (nb pronostics),
  //                                         à égalité le gzip (format actuel)
  //    • backup sans aucune clé exploitable → on ne touche à RIEN
  //      (restauration invalide ⇒ données locales préservées)
  //
  //  Aucune donnée de pronostic n'est lue, modifiée ou réécrite ici :
  //  scores IA, 19 critères, résultats réels restent ceux du backup.
  //  Ne touche ni aux poids, ni aux seuils, ni à l'apprentissage.
  // ════════════════════════════════════════════════════════════════════════

  /// Compte les pronostics contenus dans un groupe `ia` de backup.
  /// Retourne null si le groupe ne contient aucune version exploitable.
  int? _compterPronosticsBackup(Map<String, dynamic>? groupeIA) {
    if (groupeIA == null) return null;

    int? lire(String cle) {
      final raw = groupeIA[cle];
      if (raw is! Map) return null;
      final val = raw['value'];
      if (val is List) return val.length;
      if (val is String) {
        // gzip+base64 : on décompresse réellement pour compter exactement.
        if (cle.endsWith('_gz')) {
          if (val.isEmpty) return null;
          try {
            final bytes = GZipCodec().decode(base64Decode(val));
            final list = json.decode(utf8.decode(bytes));
            return list is List ? list.length : null;
          } catch (_) {
            return null;
          }
        }
        // StringList sérialisée en String (anciens formats)
        try {
          final list = json.decode(val);
          return list is List ? list.length : null;
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    final nbJson = lire('ia_pronostics_v2');
    final nbGz = lire('ia_pronostics_v2_gz');

    if (nbJson == null && nbGz == null) return null;
    if (nbJson == null) return nbGz;
    if (nbGz == null) return nbJson;
    return nbJson > nbGz ? nbJson : nbGz;
  }

  /// Purge la clé de pronostics NON retenue, uniquement si le backup
  /// contient un jeu exploitable. Retourne la clé conservée, ou null.
  Future<String?> _choisirFormatPronostics(
    SharedPreferences prefs,
    Map<String, dynamic>? groupeIA,
  ) async {
    if (groupeIA == null) return null;

    final aJson = groupeIA.containsKey('ia_pronostics_v2');
    final aGz = groupeIA.containsKey('ia_pronostics_v2_gz');

    // Backup sans pronostics → ne jamais purger les données locales
    if (!aJson && !aGz) {
      if (kDebugMode) {
        debugPrint(
            '[Backup] Pronostics : aucun dans le backup → local préservé');
      }
      return null;
    }

    // Une seule version dans le backup → elle gagne sans ambiguïté
    if (aGz && !aJson) {
      await prefs.remove('ia_pronostics_v2');
      if (kDebugMode) {
        debugPrint('[Backup] Pronostics : gzip retenu, résidu JSON purgé');
      }
      return 'ia_pronostics_v2_gz';
    }
    if (aJson && !aGz) {
      await prefs.remove('ia_pronostics_v2_gz');
      if (kDebugMode) {
        debugPrint('[Backup] Pronostics : JSON retenu, résidu gzip purgé');
      }
      return 'ia_pronostics_v2';
    }

    // ★ Backup HYBRIDE (les deux clés) → la plus riche gagne
    final nbJson = _compterPronosticsBackup(
        {'ia_pronostics_v2': groupeIA['ia_pronostics_v2']});
    final nbGz = _compterPronosticsBackup(
        {'ia_pronostics_v2_gz': groupeIA['ia_pronostics_v2_gz']});

    if (nbJson == null && nbGz == null) {
      // Les deux versions sont illisibles → restaurer tel quel serait ambigu,
      // et purger reviendrait à détruire les données locales.
      if (kDebugMode) {
        debugPrint(
            '[Backup] Pronostics : 2 formats illisibles → local préservé');
      }
      return null;
    }

    final garderGz = nbGz != null && (nbJson == null || nbGz >= nbJson);
    if (kDebugMode) {
      debugPrint('[Backup] Pronostics : backup hybride '
          '(JSON=${nbJson ?? 0}, gzip=${nbGz ?? 0}) → '
          '${garderGz ? 'gzip' : 'JSON'} retenu');
    }
    return garderGz ? 'ia_pronostics_v2_gz' : 'ia_pronostics_v2';
  }

  /// Applique le choix : restaure uniquement la version retenue.
  Future<int> _restaurerPronostics(
    SharedPreferences prefs,
    Map<String, dynamic>? groupeIA,
  ) async {
    final conservee = await _choisirFormatPronostics(prefs, groupeIA);
    if (conservee == null) return 0;

    final autre = conservee == 'ia_pronostics_v2_gz'
        ? 'ia_pronostics_v2'
        : 'ia_pronostics_v2_gz';

    final nb = await _restaurerGroupe(prefs, {conservee: groupeIA![conservee]});
    // Sécurité : ne purger qu'APRÈS avoir écrit la version retenue
    await prefs.remove(autre);
    return nb;
  }

  // ════════════════════════════════════════════════════════════════════════
  //  ★ ENSEMBLE 4 — EXPORT AU FORMAT `.ptg` (multi-blocs, vérifiable)
  //
  //  Le format historique reste produit par [exporterDonnees] : il est conservé
  //  parce que les anciennes sauvegardes doivent rester lisibles, et parce que
  //  les tests de non-régression le verrouillent. Ce nouveau chemin s'ajoute.
  //
  //  Ce qu'il apporte, et que le JSON unique ne peut pas apporter :
  //   • manifeste lisible sans décompresser aucun bloc ;
  //   • empreinte par bloc ET empreinte globale couvrant l'inventaire ;
  //   • provenance et nombre d'enregistrements par bloc ;
  //   • exclusions justifiées ;
  //   • écriture atomique (fichier temporaire + vérification de relecture +
  //     renommage) : une interruption ne détruit pas la sauvegarde précédente.
  //
  //  ⚠️ EXHAUSTIVITÉ. Le bloc `prefs_complet` couvre **toutes** les clés
  //  SharedPreferences réellement présentes, et non une liste recopiée à la
  //  main. C'est la seule façon de garantir qu'une clé ajoutée plus tard soit
  //  sauvegardée sans qu'on ait à y penser — et donc de ne pas reproduire le
  //  défaut de la liste historique, qui n'a cessé de dériver.
  // ════════════════════════════════════════════════════════════════════════

  /// Produit une sauvegarde au format `.ptg`, couvrant tous les supports.
  ///
  /// Prend un instantané cohérent : SharedPreferences **intégralement**, SQLite
  /// via `VACUUM INTO` (sans chargement en RAM), et les fichiers permanents de
  /// `archives/` et `config/`.
  ///
  /// Retourne un [ExportResult] dont `fileName` porte l'extension `.ptg`. En cas
  /// d'indisponibilité du dépôt structuré (par exemple sur une installation qui
  /// n'a jamais ouvert la base), le bloc SQLite est déclaré en EXCLUSION
  /// JUSTIFIÉE au lieu d'être omis en silence : le manifeste dit alors
  /// exactement ce qui manque.
  Future<ExportResult> exporterDonneesStructurees() async {
    try {
      final now = DateTime.now();
      final fileName = nomFichierBackup(now).replaceFirst('.json', '.ptg');
      final tmpDir = await getTemporaryDirectory();
      final chemin = '${tmpDir.path}/$fileName';

      const format = FormatSauvegarde();
      final prefs = await SharedPreferences.getInstance();
      const magasin = MagasinPrefs();

      // ── Bloc 1 : SharedPreferences INTÉGRAL ──────────────────────────────
      // Aucun filtre : une clé écrite par un module oublié doit être
      // sauvegardée. Les seules exclusions admises sont les caches
      // reconstructibles, et elles sont déclarées au manifeste.
      final prefsComplet = magasin.capturer(prefs);

      // ── Bloc 2 : SQLite, si le dépôt est ouvert ──────────────────────────
      final blocs = <Map<String, Object?>>[
        FormatSauvegarde.bloc(
          nom: 'prefs_complet',
          categorie: 'parametres_et_memoire',
          nature: NatureBloc.permanente,
          contenu: prefsComplet,
          provenance: 'SharedPreferences intégral',
          nbEnregistrements: prefsComplet.length,
        ),
      ];
      final exclusions = <Map<String, String>>[];
      final avertissements = <String>[];

      final depot = PontElo.instance.depotPourSauvegarde;
      if (depot != null) {
        final sqliteDir = await getTemporaryDirectory();
        final cheminDb = '${sqliteDir.path}/_snap_'
            '${now.millisecondsSinceEpoch}.db';
        try {
          final inventaire = await depot.instantaneVers(cheminDb);
          final octets = await File(cheminDb).readAsBytes();
          blocs.add(FormatSauvegarde.bloc(
            nom: 'sqlite_complet',
            categorie: 'base_structuree',
            nature: NatureBloc.permanente,
            contenu: <String, Object?>{
              'base64': base64Encode(octets),
              'inventaire': inventaire,
              'octets': octets.length,
            },
            provenance: 'VACUUM INTO (copie cohérente produit par le moteur)',
            nbEnregistrements: inventaire.values.fold<int>(0, (s, n) => s + n),
          ));
        } finally {
          final f = File(cheminDb);
          if (await f.exists()) await f.delete();
        }
      } else {
        // Exclusion DÉCLARÉE, pas omission silencieuse. Le manifeste porte la
        // raison, et la restauration saura que ce bloc n'existait pas.
        exclusions.add(<String, String>{
          'bloc': 'sqlite_complet',
          'justification': 'dépôt structuré non ouvert à cet instant : aucune '
              'base à copier. Les données restent intégralement dans '
              'prefs_complet.',
        });
      }

      // ── Bloc 3 : fichiers permanents (archives/ et config/) ──────────────
      final racine = PontElo.instance.racine;
      if (racine.isNotEmpty) {
        final fichiers = <String, Object?>{};
        for (final sousDossier in <String>['archives', 'config']) {
          final dir = Directory('$racine/$sousDossier');
          if (!await dir.exists()) continue;
          await for (final e in dir.list(recursive: true)) {
            if (e is! File) continue;
            final relatif =
                e.path.substring(racine.length + 1).replaceAll('\\', '/');
            final octets = await e.readAsBytes();
            fichiers[relatif] = <String, Object?>{
              'base64': base64Encode(octets),
              'octets': octets.length,
            };
          }
        }
        blocs.add(FormatSauvegarde.bloc(
          nom: 'fichiers_permanents',
          categorie: 'fichiers',
          nature: NatureBloc.permanente,
          contenu: fichiers,
          provenance: 'archives/ et config/',
          nbEnregistrements: fichiers.length,
        ));
      }

      final conteneur = format.construire(
        blocs: blocs,
        appVersion: _backupVersion,
        exclusions: exclusions,
      );
      await format.ecrireAtomiquement(conteneur, chemin);

      // Relecture obligatoire : une sauvegarde dont on n'a pas vérifié
      // l'intégrité ne doit pas être annoncée comme réussie.
      final verif = format.verifier(await File(chemin).readAsString());
      if (!verif.utilisable) {
        return ExportResult(
          succes: false,
          erreur: 'sauvegarde produite mais non vérifiable : '
              '${verif.messages.join(" ; ")}',
        );
      }

      final taille = await File(chemin).length();
      if (kDebugMode) {
        debugPrint('[Backup] Export .ptg OK -> $chemin '
            '(${(taille / 1024).toStringAsFixed(1)} Ko, '
            '${blocs.length} bloc(s), empreinte '
            '${verif.manifeste!.empreinteGlobale.substring(0, 12)}…, '
            'ratio ${format.tauxCompression(verif.manifeste!).toStringAsFixed(2)}x)');
      }
      return ExportResult(
        succes: true,
        filePath: chemin,
        fileName: fileName,
        tailleOctets: taille,
        avertissements: avertissements,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Backup] Export .ptg ERREUR : $e');
      return ExportResult(succes: false, erreur: e.toString());
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  EXPORT — Genere le fichier JSON de sauvegarde
  // ════════════════════════════════════════════════════════════════════════

  Future<ExportResult> exporterDonnees() async {
    try {
      // ★ A7 (3.3-C11) : `_collecterDonnees()` rend desormais les donnees ET
      // les avertissements de collecte. Le corps de l'export est INCHANGE.
      final collecte = await _collecterDonnees();
      final data = collecte.data;
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      final bytes = utf8.encode(jsonStr);

      final now = DateTime.now();
      // ★ X6 : date + heure + millisecondes — deux exports le même jour ne
      // peuvent plus porter le même nom, donc le second n'écrase plus le
      // premier. Voir [nomFichierBackup] pour la garantie et sa justification.
      final fileName = nomFichierBackup(now);

      final tmpDir = await getTemporaryDirectory();
      final file = File('${tmpDir.path}/$fileName');
      await file.writeAsBytes(bytes);

      if (kDebugMode) {
        debugPrint(
            '[Backup] Export OK -> ${file.path} (${(bytes.length / 1024).toStringAsFixed(1)} Ko)'
            '${collecte.avertissements.isEmpty ? "" : " | ${collecte.avertissements.length} avertissement(s)"}');
      }
      return ExportResult(
        succes: true,
        filePath: file.path,
        fileName: fileName,
        tailleOctets: bytes.length,
        avertissements: collecte.avertissements,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Backup] Export ERREUR : $e');
      return ExportResult(succes: false, erreur: e.toString());
    }
  }

  /// Ouvre le menu de partage natif pour un fichier DÉJÀ produit.
  ///
  /// ★ A7 (3.3-C12) — EXTRACTION MINIMALE, comportement IDENTIQUE à l'ancien
  /// corps en ligne de [partagerBackup] : mêmes `ShareParams`, même ordre,
  /// même `dateStr` calculée au moment de l'appel.
  ///
  /// ⚠️ CETTE MÉTHODE NE COLLECTE RIEN. Elle reçoit le résultat d'un export
  ///    déjà effectué, précisément pour que l'appelant sache QUEL fichier est
  ///    proposé au partage. C'est ce qui interdit qu'un avertissement décrive
  ///    une autre collecte que le fichier réellement présenté.
  ///
  /// Lève si l'ouverture échoue : c'est à l'appelant de décider si cet échec
  /// est une erreur globale ou un simple avertissement.
  Future<void> _ouvrirPartage(ExportResult result) async {
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(result.filePath!, mimeType: 'application/json')],
        text: 'Sauvegarde Pronostic Hippique du $dateStr\n'
            'Contient : IA (19 critères + ELO + terrain + progression + mémoire + PoidsIndices) + Paris + Alertes + Profil + Widget v2.0',
        subject: 'Sauvegarde Pronostic Hippique $dateStr',
      ),
    );
  }

  /// Partage le fichier backup via le menu natif Android
  ///
  /// Conservée STRICTEMENT pour ses appelants historiques :
  /// `sauvegarderSurDrive()` (l.1013) et tout code lisant un `bool`. Elle
  /// effectue sa PROPRE collecte et **jette** les avertissements — c'est
  /// pourquoi les écrans qui veulent les afficher doivent utiliser
  /// [partagerBackupAvecResultat].
  Future<bool> partagerBackup() async {
    try {
      final result = await exporterDonnees();
      if (!result.succes) return false;

      await _ouvrirPartage(result);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[Backup] Partage ERREUR : $e');
      return false;
    }
  }

  /// ★ A7 (3.3-C12) — PARTAGE QUI REND LE RÉSULTAT DE **SA** COLLECTE.
  ///
  /// ── LE DÉFAUT QUE CETTE MÉTHODE SUPPRIME ────────────────────────────────
  /// `_exporter()` appelait `exporterDonnees()` **puis** `partagerBackup()`,
  /// qui refaisait une seconde collecte. Le nom de fichier étant horodaté au
  /// JOUR, la seconde collecte réécrivait le MÊME chemin : le fichier présenté
  /// au partage n'était pas celui que le premier résultat décrivait. Mesuré
  /// en C12 : `[X6-3] MEME CHEMIN reutilise=true | contenu identique a la 1re
  /// collecte=false`, et `[X6-4] r1 annonçait complet=true MAIS fichier reel
  /// elo_service=false`.
  ///
  /// ── CE QUE CETTE MÉTHODE GARANTIT ───────────────────────────────────────
  ///   • **un seul** appel à [exporterDonnees] — jamais deux ;
  ///   • le [ExportResult] retourné est CELUI de cet appel unique : ses
  ///     `avertissements` décrivent exactement le fichier passé au partage ;
  ///   • le même fichier (`result.filePath`) sert à ouvrir le menu natif.
  ///
  /// ── DISTINCTION DES DEUX ÉCHECS ────────────────────────────────────────
  ///   • échec de CRÉATION du fichier → `succes == false` (rendu par
  ///     [exporterDonnees] lui-même), `erreur` renseignée ;
  ///   • échec d'OUVERTURE du partage   → `succes == true` (le fichier EXISTE
  ///     bel et bien) **plus un avertissement dédié**. On ne dégrade pas en
  ///     `succes == false` : le fichier est réellement sur le disque, et
  ///     l'effacer du compte rendrait la sauvegarde indisponible au prochain
  ///     essai. On ne le transforme pas non plus en succès muet.
  ///
  /// ⚠️ AUCUNE PRÉTENTION D'ENVOI. `SharePlus.share` rend la main quand le
  ///    menu natif a été SOLLICITÉ — pas quand le destinataire a reçu quoi que
  ///    ce soit. Ni cette méthode ni l'interface n'affirment une réception.
  Future<ExportResult> partagerBackupAvecResultat() async {
    // ⚠️ UN SEUL APPEL. C'est l'invariant central du lot.
    final ExportResult result = await exporterDonnees();
    if (!result.succes) return result; // échec de CRÉATION : rendu tel quel

    try {
      await _ouvrirPartage(result);
      // Le fichier présenté est celui que `result` décrit : ses avertissements
      // sont donc, par construction, ceux du fichier réellement proposé.
      return ExportResult(
        succes: true,
        filePath: result.filePath,
        fileName: result.fileName,
        tailleOctets: result.tailleOctets,
        avertissements: result.avertissements,
        partageOuvert: true,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Backup] Partage ERREUR (fichier créé) : $e');
      return ExportResult(
        succes: true,
        filePath: result.filePath,
        fileName: result.fileName,
        tailleOctets: result.tailleOctets,
        // ⚠️ ÉCHEC D'OUVERTURE, PAS UN ÉCHEC DE SAUVEGARDE. Le fichier existe.
        partageOuvert: false,
        avertissements: <String>[
          ...result.avertissements,
          'Le fichier de sauvegarde a bien été créé '
              '(${result.fileName}), mais le menu de partage n\'a pas pu '
              's\'ouvrir ($e). Aucun envoi n\'est confirmé : le fichier reste '
              'disponible sur cet appareil.',
        ],
      );
    }
  }

  /// Ouvre Google Drive avec le fichier backup (via le menu de partage)
  Future<bool> sauvegarderSurDrive() async => partagerBackup();

  /// Copie le fichier backup dans le dossier Telechargements du telephone
  Future<ExportResult> telechargerSurTelephone() async {
    try {
      final result = await exporterDonnees();
      if (!result.succes) return result;

      final downloadsDir = await getExternalStorageDirectory();
      String downloadPath;

      if (downloadsDir != null) {
        final parts = downloadsDir.path.split('/');
        final androidIdx = parts.indexOf('Android');
        downloadPath = androidIdx > 0
            ? '${parts.take(androidIdx).join('/')}/Download'
            : '${downloadsDir.path}/backup';
      } else {
        return ExportResult(
            succes: false, erreur: 'Stockage externe inaccessible');
      }

      final destDir = Directory(downloadPath);
      if (!await destDir.exists()) await destDir.create(recursive: true);

      final destFile = File('$downloadPath/${result.fileName}');
      await File(result.filePath!).copy(destFile.path);

      if (kDebugMode) debugPrint('[Backup] Telecharge -> ${destFile.path}');
      return ExportResult(
        succes: true,
        filePath: destFile.path,
        fileName: result.fileName,
        tailleOctets: result.tailleOctets,
        // ★ A7 (3.3-C11) — PROPAGATION EXPLICITE.
        //   Ce chemin produit un ExportResult NEUF : sans cette ligne, les
        //   avertissements de `exporterDonnees()` seraient PERDUS, et le
        //   fichier copie serait annonce complet alors qu'il ne l'est pas.
        avertissements: result.avertissements,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Backup] Telechargement ERREUR : $e');
      return ExportResult(succes: false, erreur: e.toString());
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  IMPORT — Restaure depuis un fichier JSON selectionne par l'utilisateur
  // ════════════════════════════════════════════════════════════════════════

  Future<ImportResult> importerDepuisFichier() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        // ★ ENSEMBLE 4 : `.ptg` (nouveau conteneur vérifiable) accepté à côté
        // de `.json` (format historique). Aucun ancien fichier ne devient
        // illisible : `.json` est toujours listé et toujours pris en charge.
        allowedExtensions: ['json', 'ptg'],
        withData: true,
      );

      if (picked == null || picked.files.isEmpty) {
        return ImportResult(succes: false, erreur: 'Aucun fichier selectionne');
      }

      final file = picked.files.first;
      String contenu;

      if (file.bytes != null) {
        contenu = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        contenu = await File(file.path!).readAsString();
      } else {
        return ImportResult(
            succes: false, erreur: 'Impossible de lire le fichier');
      }

      // Le FORMAT est déterminé par le CONTENU, pas par l'extension : un
      // fichier renommé à la main doit quand même être traité correctement.
      const format = FormatSauvegarde();
      final verif = format.verifier(contenu);
      if (verif.formatReconnu && !verif.legacy) {
        return await _restaurerDepuisConteneur(verif, contenu);
      }
      return await _restaurerDepuisJson(contenu);
    } catch (e) {
      if (kDebugMode) debugPrint('[Backup] Import ERREUR : $e');
      return ImportResult(succes: false, erreur: e.toString());
    }
  }

  /// Point d'entrée de restauration à partir d'un CONTENU déjà lu.
  ///
  /// Existe pour que les tests et un futur import par lien puissent exercer
  /// EXACTEMENT le même aiguillage que [importerDepuisFichier] (format déterminé
  /// par le contenu, `.ptg` ou JSON historique), sans passer par le sélecteur de
  /// fichiers natif — indisponible en test. Aucune logique n'est dupliquée ici :
  /// la méthode appelle les mêmes chemins privés que la production.
  Future<ImportResult> restaurerDepuisContenu(String contenu) async {
    const format = FormatSauvegarde();
    final verif = format.verifier(contenu);
    if (verif.formatReconnu && !verif.legacy) {
      return _restaurerDepuisConteneur(verif, contenu);
    }
    if (!verif.lisible) {
      return ImportResult(
        succes: false,
        erreur: 'contenu illisible : ${verif.messages.join(" ; ")}',
      );
    }
    return _restaurerDepuisJson(contenu);
  }

  @visibleForTesting
  Future<ImportResult> restaurerDepuisContenuPourTest(String contenu) =>
      restaurerDepuisContenu(contenu);

  // ════════════════════════════════════════════════════════════════════════
  //  ★ ENSEMBLE 4 — AVANCÉE DU MAGASIN STRUCTURÉ APRÈS RESTAURATION JSON
  //
  //  Pourquoi cette méthode existe :
  //
  //  La restauration JSON écrit dans SharedPreferences puis s'arrête là. Le
  //  dépôt SQLite reste alors figé sur l'état d'avant la restauration. Deux
  //  magasins, deux états : exactement la situation que §4 interdit
  //  (« ne laisse pas subsister deux magasins concurrents susceptibles de
  //  produire des états divergents »).
  //
  //  Cette méthode reporte l'état restauré vers le dépôt, en réutilisant le
  //  migreur ELO déjà validé (1 934 et 9 001 clés, zéro écart mesuré). Elle ne
  //  recalcule AUCUN rating : elle recopie, et vérifie.
  //
  //  ⚠️ ELLE NE LÈVE JAMAIS. Un échec de report est journalisé et compté : la
  //  restauration SharedPreferences, elle, a bien eu lieu, et prétendre le
  //  contraire tromperait l'utilisateur. L'écart est ensuite visible dans le
  //  journal du dépôt.
  // ════════════════════════════════════════════════════════════════════════

  Future<void> _avancerMagasinStructure(SharedPreferences prefs) async {
    final depot = PontElo.instance.depotPourSauvegarde;
    if (depot == null) {
      if (kDebugMode) {
        debugPrint('[Backup] dépôt structuré non ouvert : report sauté '
            '(SharedPreferences reste la référence, aucune donnée perdue)');
      }
      return;
    }
    try {
      // ── 1. ELO : report des ratings restaurés ──────────────────────────
      final ratings = EloService.instance.exporterPourBackup();
      if (ratings.isNotEmpty) {
        final resultat = await const MigrateurElo().migrer(
          depot,
          ratings,
          operation: 'report_apres_restauration_json',
        );
        if (kDebugMode) {
          debugPrint('[Backup] ELO reporté au dépôt : '
              '${resultat.clesEcrites} clé(s), '
              'écarts=${resultat.ecartsValeur}, conforme=${resultat.conforme}');
        }
        if (!resultat.conforme) {
          // Un écart de valeur après report signale un défaut de transport.
          // Il est journalisé comme conflit, jamais corrigé d'office.
          await depot.enregistrerConflit(
            categorie: 'report_elo',
            description: 'Report ELO non conforme après restauration JSON : '
                '${resultat.ecartsValeur} écart(s) de valeur, '
                '${resultat.ecartsChamp} écart(s) de champ',
            valeurLocale: '${resultat.clesLues}',
            valeurDistante: '${resultat.clesEcrites}',
          );
        }
      }

      // ── 2. Rapports et bilans : reconstruction du corpus ───────────────
      //     `enregistrer` est idempotent (empreinte de contenu) : rejouer ne
      //     duplique rien. Aucune donnée historique n'est supprimée.
      const recup = RecuperateurRapports();
      final racine = <String, Object?>{
        for (final cle in prefs.getKeys()) cle: prefs.get(cle),
      };
      final copies = recup.extraire(racine);
      await recup.enregistrer(depot, copies);
      final avant = await depot.compterRapports();
      if (kDebugMode) {
        debugPrint('[Backup] corpus reporté : ${copies.length} copie(s), '
            '$avant contenu(s) distinct(s) en base');
      }

      await depot.journaliser(
        operation: 'report_apres_restauration_json',
        etape: 'application',
        statut: 'termine',
        detail: 'elo=${ratings.length} copies=${copies.length} '
            'rapports=$avant',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Backup] report au dépôt ERREUR : $e');
      try {
        await depot.journaliser(
          operation: 'report_apres_restauration_json',
          etape: 'application',
          statut: 'echec',
          detail: '$e',
        );
      } catch (_) {
        // Le journal lui-même peut échouer si le dépôt s'est fermé : ce n'est
        // pas une raison de faire échouer la restauration déjà appliquée.
      }
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  ★ ENSEMBLE 4 — RESTAURATION TRANSACTIONNELLE (tous les supports)
  //
  //  Garanties effectives, et leurs limites réelles :
  //
  //  1. **Vérification AVANT toute écriture.** Un conteneur dont un bloc est
  //     altéré est refusé, sans qu'aucune donnée ne soit touchée.
  //  2. **Instantané global vérifié.** Les quatre supports sont capturés dans
  //     un `.ptg` avant la première écriture. Si l'instantané échoue (disque
  //     plein, permission), la restauration est refusée : c'est là que
  //     l'espace insuffisant devient inoffensif.
  //  3. **Retour arrière automatique.** Si une étape échoue après le début des
  //     écritures, `TransactionGlobale.annuler()` rétablit l'état antérieur des
  //     quatre supports. Une transaction SQLite seule ne protégerait pas les
  //     SharedPreferences ni les fichiers — c'est précisément pourquoi ce
  //     mécanisme existe séparément.
  //  4. **Aucun double apprentissage.** Les poids, seuils, rapports et journal
  //     sont ÉCRITS tels quels, jamais recalculés. Aucun `enregistrerPronostics`
  //     ni calcul de gradient n'est déclenché ici.
  //  5. **Conflits ELO explicites.** Aucun rating divergent n'est remplacé
  //     silencieusement : chaque divergence produit une ligne de conflit (D-24).
  // ════════════════════════════════════════════════════════════════════════

  /// Traduit une restauration multi-supports en `ImportResult`.
  ///
  /// ⚠️ CETTE MÉTHODE NE CONTIENT PLUS AUCUNE RÈGLE MÉTIER.
  ///
  /// Avant unification, elle réimplémentait ici la comparaison ELO, la trace
  /// des conflits (D-24) et l'ordre des écritures — en parallèle de
  /// `Restaurateur`, qui faisait la même chose autrement. Deux logiques pour un
  /// même acte, c'est deux comportements possibles selon le chemin emprunté.
  ///
  /// Désormais, tout est dans `Restaurateur.restaurer()` : aiguillage par
  /// layout, instantané vérifié, intention, application, contrôles, retour
  /// arrière, reprise. Ici, on ne fait que traduire le résultat.
  Future<ImportResult> _restaurerDepuisConteneur(
    VerificationSauvegarde verif,
    String contenu,
  ) async {
    final depot = PontElo.instance.depotPourSauvegarde;
    final racine = PontElo.instance.racine;
    if (depot == null || racine.isEmpty) {
      // Sans dépôt structuré, la restauration concernerait SharedPreferences
      // seule. Elle est refusée plutôt que d'être appliquée partiellement : une
      // restauration partielle non annoncée est exactement ce que §16 interdit.
      return ImportResult(
        succes: false,
        version: 'ptg/${verif.manifeste?.versionFormat ?? "?"}',
        erreur: 'dépôt structuré indisponible : restauration refusée pour ne '
            'pas appliquer un état partiel',
      );
    }

    final resultat = await const Restaurateur().restaurer(
      depot: depot,
      contenuSauvegarde: contenu,
      mode: ModeRestauration.complet,
      dossierTemp: '$racine/temp',
      dossierBase: racine,
      versionLocale: _backupVersion,
    );

    if (!resultat.reussie) {
      return ImportResult(
        succes: false,
        version: 'ptg/${verif.manifeste?.versionFormat ?? "?"}',
        erreur: resultat.erreur,
      );
    }

    // ── Les services en mémoire doivent relire l'état restauré (§4) ───────
    // Sans cela, l'application continuerait d'afficher l'ancien état jusqu'au
    // redémarrage : l'utilisateur croirait à un échec et retenterait, ce qui
    // risquerait de produire un second apprentissage.
    await IaMemoryService.instance.recharger();
    await EloService.instance.rechargerDepuisStockage();

    final prefs = await SharedPreferences.getInstance();
    return ImportResult(
      succes: true,
      version: 'ptg/${verif.manifeste!.versionFormat}',
      nbClesRestaurees: resultat.nbPrefsEcrites + resultat.nbFichiersRestaures,
      nbIA: resultat.nbPrefsEcrites,
      nbPronosticsIA: (prefs.getStringList('ia_pronostics_v2') ?? []).length,
      nbParis: (prefs.getStringList('user_predictions_v2') ?? []).length,
      nbAlertes: (prefs.getStringList('alert_history_v1') ?? []).length,
      nbEloRestaures: resultat.eloIdentiques + resultat.eloConflits +
          resultat.eloRestaures,
      dateBackup: verif.manifeste!.dateCreation,
      avertissementElo: resultat.eloConflits > 0
          ? '${resultat.eloConflits} rating(s) divergent(s) : tracés en '
              'conflit, aucune fusion (D-24)'
          : null,
    );
  }

  Future<ImportResult> _restaurerDepuisJson(String jsonStr) async {
    try {
      final Map<String, dynamic> data =
          json.decode(jsonStr) as Map<String, dynamic>;

      if (data['appName'] != 'Pronostic Hippique') {
        return ImportResult(
            succes: false, erreur: 'Fichier invalide ou incompatible');
      }

      final prefs = await SharedPreferences.getInstance();
      int total = 0;

      // 🧠 Memoire IA
      // ★ v10.84 — B1/B3 : les pronostics sont restaurés à part, avec choix
      // d'UN SEUL format (JSON ou gzip). Les autres clés IA continuent de
      // passer par `_restaurerGroupe()` sans changement.
      final groupeIA = data['ia'] as Map<String, dynamic>?;
      Map<String, dynamic>? groupeIASansPronostics;
      if (groupeIA != null) {
        groupeIASansPronostics = Map<String, dynamic>.from(groupeIA);
        groupeIASansPronostics.remove('ia_pronostics_v2');
        groupeIASansPronostics.remove('ia_pronostics_v2_gz');
      }

      final nbIA = await _restaurerGroupe(prefs, groupeIASansPronostics);
      total += nbIA;
      final nbPronosticsRestaures = await _restaurerPronostics(prefs, groupeIA);
      total += nbPronosticsRestaures;
      if (kDebugMode) {
        debugPrint('[Backup] IA restauree : $nbIA cles '
            '(+ pronostics : $nbPronosticsRestaures)');
      }

      // 🎯 Config Fusion — 4 cles heritees (BL1-A16). Restauration silencieuse :
      //    aucune ecriture ne les relit, mais une sauvegarde ancienne qui les
      //    contient doit s'appliquer sans erreur.
      final nbCfg = await _restaurerGroupe(
          prefs, data['configIA'] as Map<String, dynamic>?);
      total += nbCfg;
      if (kDebugMode) debugPrint('[Backup] Config IA restauree : $nbCfg cles');

      // 📋 Paris
      final nbParisCles =
          await _restaurerGroupe(prefs, data['paris'] as Map<String, dynamic>?);
      total += nbParisCles;
      // Compter le nombre reel de paris restaures
      int nbParisCount = 0;
      try {
        final list = prefs.getStringList('user_predictions_v2') ?? [];
        nbParisCount = list.length;
      } catch (_) {}
      if (kDebugMode) {
        debugPrint('[Backup] Paris restaures : $nbParisCount paris');
      }

      // 🔔 Alertes
      final nbAlertesCles = await _restaurerGroupe(
          prefs, data['alertes'] as Map<String, dynamic>?);
      total += nbAlertesCles;
      // Compter le nombre reel d'alertes
      int nbAlertesCount = 0;
      try {
        final list = prefs.getStringList('alert_history_v1') ?? [];
        nbAlertesCount = list.length;
      } catch (_) {}
      if (kDebugMode) {
        debugPrint(
            '[Backup] Alertes restaurees : $nbAlertesCount alertes ($nbAlertesCles cles)');
      }

      // 👤 Profil
      final nbProfil = await _restaurerGroupe(
          prefs, data['profil'] as Map<String, dynamic>?);
      total += nbProfil;
      if (kDebugMode) debugPrint('[Backup] Profil restaure : $nbProfil cles');

      // 📱 Widget
      final nbWidget = await _restaurerGroupe(
          prefs, data['widget'] as Map<String, dynamic>?);
      total += nbWidget;
      if (kDebugMode) debugPrint('[Backup] Widget restaure : $nbWidget cles');

      // ── ★ ENSEMBLE 4 : AVANCÉE DU MAGASIN STRUCTURÉ ──────────────────────
      //
      // La restauration JSON historique écrit dans SharedPreferences. Le dépôt
      // SQLite de production doit refléter ce même état, sinon deux magasins
      // concurrents produiraient des états divergents — ce que §4 interdit.
      //
      // Ce bloc est donc exécuté APRÈS les écritures SharedPreferences, et
      // seulement si un dépôt est ouvert. Il est IDEMPOTENT : `enregistrer` et
      // `migrer` reposent sur des clés déterministes, donc un rejeu ne duplique
      // rien (§14).
      await _avancerMagasinStructure(prefs);

      // ── 🏇 ELO SERVICE ★ v8.0 ────────────────────────────────────────────
      // Restaurer les ratings ELO depuis le backup si présents
      //
      // ★ A7 (3.2) — CE BLOC NE JETAIT RIEN MOINS QUE L'ISSUE DE L'ÉCRITURE.
      //   `importerDepuisBackup()` rend un `EtatPersistanceElo` depuis 3.2 ;
      //   il était consommé par un `await` muet, et le tampon « ELO restaure »
      //   s'imprimait même quand `setString` avait répondu `false`.
      //
      //   ⚠️ CE QUI N'EST **PAS** FAIT ICI, VOLONTAIREMENT :
      //   • `succes` n'est JAMAIS dégradé — un échec du volet ELO n'est pas un
      //     échec de la restauration : les autres groupes sont restaurés ;
      //   • `total` / `nbClesRestaurees` ne reçoivent RIEN — l'ELO n'écrit pas
      //     via `_restaurerGroupe`, il compte séparément depuis toujours ;
      //   • aucune exception ne s'échappe : le `catch` reste en place pour le
      //     seul cas encore atteignable, une charge `elo_service` malformée
      //     (le cast ci-dessous lève alors AVANT l'appel).
      int nbEloRestaures = 0;
      String? avertissementElo;
      if (data.containsKey('elo_service')) {
        try {
          final EtatPersistanceElo etatElo = await EloService.instance
              .importerDepuisBackup(
                  data['elo_service'] as Map<String, dynamic>);
          // Ratings réellement détenus en RAM après l'import. Ne prouve
          // AUCUNE persistance disque — voir la doc du champ.
          nbEloRestaures = EloService.instance.nbChevauxSuivis;
          switch (etatElo) {
            case EtatPersistanceElo.persistee:
              if (kDebugMode) {
                debugPrint('[Backup] ELO restaure — '
                    '$nbEloRestaures ratings en RAM, persistance CONFIRMEE');
              }
            case EtatPersistanceElo.refusee:
            case EtatPersistanceElo.echouee:
              // Persistance NON CONFIRMÉE. On ne dit surtout pas que le
              // disque est resté intact : il peut avoir écrit puis répondu
              // `false`, ou avoir levé après une écriture partielle.
              avertissementElo =
                  'Ratings ELO chargés en mémoire ($nbEloRestaures), mais '
                  'leur écriture disque n\'est PAS confirmée '
                  '(${etatElo.name}). L\'état du stockage ELO n\'est pas '
                  'connu et n\'est pas prouvé inchangé.';
              debugPrint('[Backup] ⚠️ ELO persistance NON confirmée : '
                  '${etatElo.name}');
            case EtatPersistanceElo.abandonneeParReset:
              avertissementElo =
                  'Restauration ELO ABANDONNÉE : un reset complet est en '
                  'cours ou est intervenu. Aucune écriture ELO n\'a été '
                  'tentée ; les ratings lus ne sont pas persistés.';
              debugPrint('[Backup] ⚠️ ELO abandonné par un reset concurrent');
            case EtatPersistanceElo.nonTentee:
              // ★ A7-39 — CETTE BRANCHE EST ATTEIGNABLE, ET ELLE EST MÊME LE
              //   CAS NOMINAL D'UN REFUS ANTICIPÉ.
              //
              //   `importerDepuisBackup()` rend `nonTentee` lorsqu'une
              //   sauvegarde ENRICHIE porte un registre illisible,
              //   incompatible ou incohérent : la décision est prise AVANT
              //   toute mutation, donc avant `_sauvegarder()`. Les ratings de
              //   l'appareil sont restés INTACTS et aucune écriture n'a été
              //   tentée.
              //
              //   ⚠️ `nbEloRestaures` EST REMIS À ZÉRO ICI, VOLONTAIREMENT.
              //      Il a été renseigné plus haut par `nbChevauxSuivis`, qui
              //      compte les ratings DÉJÀ PRÉSENTS en RAM. Les présenter
              //      comme « restaurés » serait un mensonge : rien n'a été
              //      restauré, l'appareil garde son état antérieur. Ce n'est
              //      pas un échec non plus — c'est un refus délibéré, et le
              //      message le dit.
              nbEloRestaures = 0;
              avertissementElo =
                  'Restauration ELO non tentée : le registre ELO contenu dans '
                  'la sauvegarde est inutilisable (illisible, incompatible ou '
                  'incohérent avec ses propres ratings). Aucun rating n\'a été '
                  'modifié et aucune écriture n\'a été tentée ; les données ELO '
                  'de l\'appareil sont restées telles quelles.';
              debugPrint('[Backup] ⛔ Refus anticipé du registre ELO — '
                  'ratings intacts, aucune écriture tentée');
          }
        } catch (e) {
          // Seul cas atteignable : le cast de `data['elo_service']` a levé.
          // On le SIGNALE au lieu de le noyer dans un `debugPrint`.
          avertissementElo = 'Donnée ELO illisible dans la sauvegarde : $e. '
              'Les ratings ELO n\'ont pas été restaurés.';
          debugPrint('[Backup] ⚠️ ELO restauration impossible : $e');
        }
      }

      // ── 📡 COTE TRACKER ★ v9.97 ──────────────────────────────────────────
      // Restaurer les mouvements de cote en temps réel
      if (data.containsKey('cote')) {
        final nbCote = await _restaurerGroupe(
            prefs, data['cote'] as Map<String, dynamic>?);
        total += nbCote;
        if (kDebugMode) {
          debugPrint('[Backup] CoteTracker restaure : $nbCote cles');
        }
      }

      // ── 🧪 LABO IA ★ v10.35 ──────────────────────────────────────────────
      // Restaurer les pistes de simulation (obligatoire — non recalculable)
      if (data.containsKey('laboIA')) {
        final nbLabo = await _restaurerGroupe(
            prefs, data['laboIA'] as Map<String, dynamic>?);
        total += nbLabo;
        if (kDebugMode) debugPrint('[Backup] LaboIA restaure : $nbLabo cles');
      }

      // ── 📊 CACHE AUDIT ★ v10.35 ──────────────────────────────────────────
      // Restaurer le cache Audit (optionnel — recalculable si absent)
      if (data.containsKey('auditCache')) {
        final nbAudit = await _restaurerGroupe(
            prefs, data['auditCache'] as Map<String, dynamic>?);
        total += nbAudit;
        if (kDebugMode) {
          debugPrint('[Backup] AuditCache restaure : $nbAudit cles');
        }
      }

      // ── ⚠️ GROS PARIS ★ v10.72 ───────────────────────────────────────────
      // Restaurer les signaux Gros Paris + Quasi Gagnants (obligatoire — non recalculable)
      // Rétrocompat : clé absente dans un ancien backup → reset à vide, jamais crash
      try {
        if (data.containsKey('grosParis')) {
          final grosParisRaw = data['grosParis'];
          if (grosParisRaw is Map<String, dynamic>) {
            await QuasiGrosParisService.instance
                .importerDepuisBackup(grosParisRaw);
            if (kDebugMode) {
              final nbS = (grosParisRaw['signaux'] as List? ?? []).length;
              final nbQ = (grosParisRaw['quasiGagnants'] as List? ?? []).length;
              final nbG =
                  (grosParisRaw['grosParisGagnants'] as List? ?? []).length;
              debugPrint(
                  '[Backup] GrosParis restaure : $nbS signaux, $nbQ quasi-gagnants, '
                  '$nbG gagnants (ia_gros_paris_resultats_v1)');
            }
          }
        } else {
          // Rétrocompat : absent dans un ancien backup → reset propre à vide
          await QuasiGrosParisService.instance
              .importerDepuisBackup({'signaux': [], 'quasiGagnants': []});
          if (kDebugMode) {
            debugPrint(
                '[Backup] grosParis absent → reset à vide (compat v<9.0)');
          }
        }
      } catch (e) {
        // Clé corrompue : reset uniquement cette clé, ne jamais bloquer la restauration
        if (kDebugMode) {
          debugPrint('[Backup] GrosParis restauration partielle (reset) : $e');
        }
        try {
          await QuasiGrosParisService.instance
              .importerDepuisBackup({'signaux': [], 'quasiGagnants': []});
        } catch (_) {}
      }

      // ── 📊 RÉSULTATS GROS PARIS ★ v10.85 — B4 ─────────────────────────────
      // Rétrocompat : clé ABSENTE dans une ancienne sauvegarde → on ne touche
      // à RIEN sur l'appareil (les résultats locaux sont préservés).
      // Clé présente → le repository remplace sa liste par celle du backup,
      // sans dédoublonnage ni recalcul (restaurerDepuisBackup fait clear+add).
      if (data.containsKey('resultatsGrosParis')) {
        try {
          final brut = data['resultatsGrosParis'];
          if (brut is Map<String, dynamic>) {
            await PronosticResultatsRepository.instance
                .restaurerDepuisBackup(brut);
            if (kDebugMode) {
              debugPrint('[Backup] REP -> '
                  '${PronosticResultatsRepository.instance.tous.length} '
                  'résultats restaurés');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[Backup] REP restauration partielle : $e');
          }
        }
      } else {
        if (kDebugMode) {
          debugPrint('[Backup] resultatsGrosParis absent → local préservé '
              '(compat v<10.85)');
        }
      }

      // ── 🗄️ ARCHIVE HISTORIQUE IA ★ E3 ─────────────────────────────────────
      // EXIGENCES 3 et 4 :
      //   • `archiveIA` PRÉSENTE  → FUSION PROTECTRICE (union par empreinte,
      //     aucune suppression locale, aucune rétrogradation des fiches
      //     complètes : voir IaArchiveService.restaurerDepuisBackup).
      //   • `archiveIA` ABSENTE   → on ne touche À RIEN : archive locale intacte
      //     (toutes les sauvegardes v ≤ 9.0 restent compatibles).
      //   • clé mal typée         → même règle : local préservé.
      if (data.containsKey('archiveIA')) {
        try {
          final brut = data['archiveIA'];
          if (brut is Map<String, dynamic>) {
            final res =
                await IaArchiveService.instance.restaurerDepuisBackup(brut);
            if (kDebugMode) {
              debugPrint('[Backup] ARC restauration -> '
                  '${res.shardsLus} shard(s) lus, '
                  '${res.versionsAjoutees} version(s) ajoutée(s), '
                  '${res.versionsDejaPresentes} doublon(s) évité(s), '
                  '${res.predictionsAmelioreesLabel}');
            }
          } else if (kDebugMode) {
            debugPrint('[Backup] archiveIA mal typée → local préservé');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[Backup] ARC restauration partielle : $e');
          }
        }
      } else if (kDebugMode) {
        debugPrint('[Backup] archiveIA absent → archive locale préservée '
            '(compat v<9.1)');
      }

      // ── 🏁 ARRIVÉES OFFICIELLES COMPLÈTES ★ L0 ───────────────────────────
      // EXIGENCES :
      //   • `arriveesOfficielles` PRÉSENTE → FUSION ADDITIVE : on n'ajoute que
      //     les courses absentes localement. Une arrivée officielle est un
      //     FAIT : en cas de divergence, on ne réécrit pas l'histoire.
      //   • `arriveesOfficielles` ABSENTE → on ne touche À RIEN : le stockage
      //     local reste intact (toutes les sauvegardes antérieures à L0
      //     restent compatibles).
      //   • clé mal typée → même règle : local préservé.
      //
      // Aucune réinjection dans la mémoire active : ce bloc n'écrit que dans
      // les clés `arrivee_officielle_complete_v1_*`.
      if (data.containsKey('arriveesOfficielles')) {
        try {
          final brut = data['arriveesOfficielles'];
          if (brut is Map<String, dynamic>) {
            final res = await ArriveeOfficielleService.instance
                .restaurerDepuisBackup(brut);
            if (kDebugMode) {
              debugPrint('[Backup] ARR restauration -> '
                  '${res.shardsLus} shard(s) lu(s), '
                  '${res.shardsIllisibles} illisible(s), '
                  '${res.entreesAjoutees} arrivée(s) ajoutée(s), '
                  '${res.entreesDejaPresentes} doublon(s) évité(s)'
                  '${res.aDesConflits ? ', ⚠️ ${res.conflits.length} CONFLIT(S) '
                      'NON RÉSOLU(S) — local conservé : ${res.conflits.join(", ")}' : ''}'
                  '${res.moisNonEcrits > 0 ? ', ${res.moisNonEcrits} mois non écrit(s)' : ''}');
            }
          } else if (kDebugMode) {
            debugPrint(
                '[Backup] arriveesOfficielles mal typée → local préservé');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[Backup] ARR restauration partielle : $e');
          }
        }
      } else if (kDebugMode) {
        debugPrint('[Backup] arriveesOfficielles absent → stockage local '
            'préservé (compat sauvegardes < L0)');
      }

      // ── 💰 RÉSULTATS OFFICIELS PMU ★ BLOC 1 ──────────────────────────────
      // Mêmes règles que le bloc des arrivées, volontairement :
      //   • clé ABSENTE  → on ne touche À RIEN : les sauvegardes antérieures
      //                    restent compatibles, le stockage local est intact ;
      //   • clé MAL TYPÉE → local préservé ;
      //   • clé présente → restauration ADDITIVE : une entrée locale plus
      //                    complète n'est jamais écrasée par une plus pauvre,
      //                    et un conflit d'arrivées définitives divergentes est
      //                    signalé en conservant la version LOCALE.
      // Aucune réinjection dans la mémoire active, aucun apprentissage.
      if (data.containsKey('resultatsOfficielsPmu')) {
        try {
          final brut = data['resultatsOfficielsPmu'];
          if (brut is Map<String, dynamic>) {
            final res = await ResultatOfficielRepository.instance
                .restaurerDepuisBackup(brut);
            if (kDebugMode) {
              debugPrint('[Backup] ROP restauration -> '
                  '${res.shardsLus} shard(s) lu(s), '
                  '${res.shardsIllisibles} illisible(s), '
                  '${res.entreesAjoutees} entrée(s) ajoutée(s), '
                  '${res.entreesDejaPresentes} doublon(s) évité(s)'
                  '${res.aDesConflits ? ', ⚠️ ${res.conflits.length} CONFLIT(S) NON RÉSOLU(S) — local conservé : ${res.conflits.join(", ")}' : ''}'
                  '${res.moisNonEcrits > 0 ? ', ${res.moisNonEcrits} mois non écrit(s)' : ''}');
            }
          } else if (kDebugMode) {
            debugPrint(
                '[Backup] resultatsOfficielsPmu mal typée → local préservé');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[Backup] ROP restauration partielle : $e');
          }
        }
      } else if (kDebugMode) {
        debugPrint('[Backup] resultatsOfficielsPmu absent → stockage local '
            'préservé (compat sauvegardes antérieures au BLOC 1)');
      }

      // Retrocompatibilite : anciens formats v1/v2/v3 sans certains groupes
      final backupVer = data['version'] as String? ?? '1.0';
      final dateBackup = data['dateBackup'] as String? ?? '';

      // Compter les pronostics IA restaurés (version compressée ou non)
      int nbPronosticsIA = 0;
      try {
        // D'abord chercher la version compressée (Lot 4)
        final gz = prefs.getString('ia_pronostics_v2_gz') ?? '';
        if (gz.isNotEmpty) {
          // Estimation : ~1 pronostic = ~200 octets JSON = ~100 octets gzip base64
          nbPronosticsIA = (gz.length / 130).round();
        } else {
          final list = prefs.getStringList('ia_pronostics_v2') ?? [];
          nbPronosticsIA = list.length;
        }
      } catch (_) {}

      if (kDebugMode) {
        debugPrint('[Backup] Import complet — $total cles restaurees '
            '($nbParisCount paris, $nbPronosticsIA pronostics) — format v$backupVer');
      }

      // ★ v10.65 — Compatibilité mémoire narrative (secondaire)
      // Si ia_narrative_memory_v1 est absente dans un ancien backup :
      //   → supprimer la clé existante pour repartir proprement sur mémoire vide
      //   → ne jamais crasher — la narration est secondaire
      try {
        final configGroupe = data['configIA'] as Map<String, dynamic>?;
        final hasNarrativeMemory = configGroupe != null &&
            configGroupe.containsKey('ia_narrative_memory_v1');
        if (!hasNarrativeMemory) {
          await prefs.remove('ia_narrative_memory_v1');
          if (kDebugMode) {
            debugPrint(
                '[Backup] ia_narrative_memory_v1 absente → mémoire narrative vide (compat)');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[Backup] ia_narrative_memory_v1 compat (ignoré) : $e');
        }
      }

      // ★ v10.66 — Compatibilité cache narratif journalier (secondaire — recréable)
      // Si ia_narrative_daily_cache_v1 est absente dans un ancien backup :
      //   → reset du cache uniquement → régénération normale au prochain affichage du Journal IA
      //   → ne jamais bloquer la restauration principale
      try {
        final configGroupe = data['configIA'] as Map<String, dynamic>?;
        final hasDailyCache = configGroupe != null &&
            configGroupe.containsKey('ia_narrative_daily_cache_v1');
        if (!hasDailyCache) {
          await prefs.remove('ia_narrative_daily_cache_v1');
          if (kDebugMode) {
            debugPrint(
                '[Backup] ia_narrative_daily_cache_v1 absente → cache narratif reset (compat)');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
              '[Backup] ia_narrative_daily_cache_v1 compat (ignoré) : $e');
        }
      }

      // ★ v10.26c — Recharger la RAM IaMemoryService depuis les SharedPreferences restaurées
      // Indispensable si la restauration est appelée hors UI (appel direct au service)
      await IaMemoryService.instance.recharger();
      if (kDebugMode) {
        debugPrint(
            '[Backup] IaMemoryService rechargé depuis SharedPreferences');
      }

      // ★ v10.26d — Recharger AlertService (alertes, courses suivies, anti-doublons)
      await AlertService.instance.recharger();
      if (kDebugMode) {
        debugPrint('[Backup] AlertService rechargé depuis SharedPreferences');
      }

      return ImportResult(
        succes: true,
        nbClesRestaurees: total,
        nbParis: nbParisCount,
        nbPronosticsIA: nbPronosticsIA,
        nbIA: nbIA,
        nbAlertes: nbAlertesCount,
        nbAlertesCles: nbAlertesCles,
        nbWidget: nbWidget,
        nbConfigIA: nbCfg,
        nbProfil: nbProfil,
        dateBackup:
            dateBackup.isNotEmpty ? DateTime.tryParse(dateBackup) : null,
        version: backupVer,
        nbEloRestaures: nbEloRestaures,
        avertissementElo: avertissementElo,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Backup] Parsing JSON : $e');
      return ImportResult(succes: false, erreur: 'Fichier corrompu : $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  GMAIL — Acces direct a l'email de l'utilisateur
  // ════════════════════════════════════════════════════════════════════════

  Future<String?> lireGmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('profil_gmail');
  }

  Future<void> sauvegarderGmail(String gmail) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profil_gmail', gmail.trim().toLowerCase());
  }

  Future<void> supprimerGmail() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('profil_gmail');
  }

  // ════════════════════════════════════════════════════════════════════════
  //  INFOS — Resume du contenu actuel pour affichage dans l'UI
  // ════════════════════════════════════════════════════════════════════════

  Future<BackupInfo> obtenirInfos() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // ── Paris utilisateur ────────────────────────────────────────────────
      final nbParis = (prefs.getStringList('user_predictions_v2') ?? []).length;

      // ── Memoire IA ───────────────────────────────────────────────────────
      final nbPronostics =
          (prefs.getStringList('ia_pronostics_v2') ?? []).length;
      final nbJournal = (prefs.getStringList('ia_journal_v2') ?? []).length;
      final nbRapports = (prefs.getStringList('ia_rapports_v1') ?? []).length;

      // Poids IA — nb de mises a jour (indique si l'IA a appris)
      bool iaApprise = false;
      int nbAjustements = 0;
      Map<String, double> poidsActuels = {};
      PoidsIndicesResume? poidsIndices;
      final poidsStr = prefs.getString('ia_poids_v3');
      if (poidsStr != null) {
        try {
          final p = json.decode(poidsStr) as Map<String, dynamic>;
          nbAjustements = (p['nbMisesAJour'] as num?)?.toInt() ?? 0;
          iaApprise = nbAjustements > 0;
          // Extraire les 19 poids adaptatifs pour affichage (v9.93)
          for (final key in [
            'forme', 'gains', 'record', 'cote', 'constance', 'victoires',
            'discipline', 'distSpec', 'jockey', 'repos', 'hippo',
            'entraineur', 'elo', // v8.0
            'terrain', 'divergence', 'poidsRel', 'progression', // v9.0
            'mouvCote', 'placeDepart'
          ]) {
            // v9.92/v9.93
            final val = (p[key] as num?)?.toDouble();
            if (val != null) poidsActuels[key] = val;
          }
          // Extraire PoidsIndices (pc/pco/pr)
          final piMap = p['poidsIndices'] as Map<String, dynamic>?;
          if (piMap != null) {
            poidsIndices = PoidsIndicesResume(
              criteres: (piMap['pc'] as num?)?.toDouble() ?? 0.40,
              confiance: (piMap['pco'] as num?)?.toDouble() ?? 0.35,
              reussite: (piMap['pr'] as num?)?.toDouble() ?? 0.25,
            );
          }
        } catch (_) {}
      }

      // Seuils adaptatifs
      final aSeuilsAdaptatifs = prefs.getString('ia_seuils_v1') != null;

      // Precision IA par type de pari
      int nbTypesPrecision = 0;
      final precStr = prefs.getString('ia_precision_v2');
      if (precStr != null) {
        try {
          final pMap = json.decode(precStr) as Map<String, dynamic>;
          nbTypesPrecision = pMap.length;
        } catch (_) {}
      }

      // ★ v9.0 : Stats par label IA
      int nbStatsLabels = 0;
      final labelsStr = prefs.getString('ia_stats_labels_v1');
      if (labelsStr != null) {
        try {
          final lMap = json.decode(labelsStr) as Map<String, dynamic>;
          nbStatsLabels = lMap.length;
        } catch (_) {}
      }

      // Stats par type de pari
      final nbStatsTypes =
          (prefs.getStringList('ia_stats_types_v1') ?? []).length;

      // ── Alertes ──────────────────────────────────────────────────────────
      final nbAlertes = (prefs.getStringList('alert_history_v1') ?? []).length;
      final nbCoursesTrack =
          (prefs.getStringList('tracked_courses_v1') ?? []).length;

      // ── Profil ────────────────────────────────────────────────────────────
      final nomProfil = prefs.getString('profil_nom');
      final gmail = prefs.getString('profil_gmail');

      // ── Config Fusion — RETIRÉE DE L'ÉTAT AFFICHÉ (BL1-A16) ──────────────
      //
      //   Les clés `fusion_poids_*` restent SAUVEGARDÉES et RESTAURÉES (voir
      //   `_keysConfigIA` et le bloc « Config Fusion BestBet » de `_exporter`),
      //   mais elles ne sont plus LUES ici : le module qui leur donnait un sens
      //   a été supprimé (BL1-A16), donc plus aucun consommateur ne peut les
      //   produire, et `BackupInfo.aConfigFusion` / `.fusionConfiance` /
      //   `.fusionSeuil` n'avaient AUCUN lecteur d'interface (mesuré :
      //   `grep -rn "aConfigFusion\|fusionConfiance\|fusionSeuil" lib/` → les
      //   seules occurrences étaient dans ce fichier).
      //
      //   ⚠️ NE PAS CONFONDRE « plus affiché » et « plus sauvegardé » : la
      //      compatibilité des anciennes sauvegardes exige que les 4 clés
      //      restent dans les listes de collecte ET de restauration.

      // ── Widget ────────────────────────────────────────────────────────────
      final widgetUpdatedAt = prefs.getString('widget_updated_at');
      final aWidget = widgetUpdatedAt != null;

      // ── Taille estimee ────────────────────────────────────────────────────
      // ★ fix #6 : estimation rapide sans sérialiser tout le JSON
      // On additionne les tailles brutes des clés SharedPreferences (≈ même ordre de grandeur)
      int taille = 0;
      for (final key in [
        'user_predictions_v2',
        'ia_pronostics_v2',
        'ia_journal_v2',
        'ia_rapports_v1',
        'alert_history_v1',
        'tracked_courses_v1',
        'ia_poids_v3',
        'ia_seuils_v1',
        'ia_precision_v2',
        'ia_stats_labels_v1',
        'ia_stats_types_v1'
      ]) {
        final s =
            prefs.getString(key) ?? (prefs.getStringList(key) ?? []).join(',');
        taille += utf8.encode(s).length;
      }

      return BackupInfo(
        tailleOctets: taille,
        nbParis: nbParis,
        nbPronostics: nbPronostics,
        nbJournal: nbJournal,
        nbRapports: nbRapports,
        nbAlertes: nbAlertes,
        nbCoursesTrack: nbCoursesTrack,
        iaApprise: iaApprise,
        nbAjustements: nbAjustements,
        poidsActuels: poidsActuels,
        poidsIndices: poidsIndices,
        aSeuilsAdaptatifs: aSeuilsAdaptatifs,
        nbTypesPrecision: nbTypesPrecision,
        nbStatsTypes: nbStatsTypes,
        nbStatsLabels: nbStatsLabels, // ★ v9.0
        gmail: gmail,
        nomProfil: nomProfil,
        aWidget: aWidget,
        widgetUpdatedAt: widgetUpdatedAt,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Backup] obtenirInfos : $e');
      return BackupInfo(
        tailleOctets: 0,
        nbParis: 0,
        nbPronostics: 0,
        nbJournal: 0,
        nbRapports: 0,
        nbAlertes: 0,
      );
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  REINITIALISATION — efface des donnees selectivement
  // ════════════════════════════════════════════════════════════════════════

  /// Efface uniquement la memoire IA (conserve les paris et le profil)
  ///
  /// ⚠️ L'archive historique n'est VOLONTAIREMENT PAS effacée ici.
  /// La décision « un reset de la mémoire IA doit-il détruire l'archive ? »
  /// est reportée à l'étape E4 : elle exige un inventaire complet de ce qui
  /// est supprimé et une confirmation explicite de l'utilisateur.
  /// En attendant cette décision, l'archive est préservée par tout reset.
  Future<void> reinitialiserIA() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _keysIA) {
      await prefs.remove(key);
    }
    if (kDebugMode) {
      debugPrint('[Backup] IA reinitialisee (${_keysIA.length} cles effacees) '
          '— archive historique préservée (décision reportée à E4)');
    }
  }

  /// Efface TOUTES les donnees de l'application (remise a zero complete)
  ///
  /// ⚠️ Même réserve que [reinitialiserIA] : l'archive historique survit.
  Future<void> reinitialiserComplet() async {
    final prefs = await SharedPreferences.getInstance();

    // ══════════════════════════════════════════════════════════════════════
    //  ★ B5c — AlertService encadre TOUTE la phase d'effacement
    //
    //  C'est le SEUL service appelé AVANT la boucle `remove()`, et c'est
    //  volontaire : `executerResetComplet()` installe une barrière d'écriture
    //  (`_resetEnCours` + `_generationCache`), draine les écritures déjà
    //  engagées, puis exécute le callback d'effacement — le tout dans le même
    //  `try/finally`.
    //
    //  Appelé APRÈS la boucle, comme les cinq autres services, le drain
    //  serait trop tardif : une écriture suspendue dans `prefs.setString()`
    //  se terminerait après l'effacement et réécrirait les clés avec les
    //  anciennes données. AlertService possède 8 chemins d'écriture, dont un
    //  déclenché par le watchdog de 60 s sans action utilisateur.
    //
    //  Les cinq autres services n'ont pas de barrière : leur `_sauvegarder()`
    //  écrirait, ils doivent donc rester APRÈS l'effacement (ordre validé en
    //  B5, B5b et B5c-1..4).
    //
    //  ★ B5c-P3 — IaMemoryService est désormais IMBRIQUÉ à l'intérieur, pas
    //  ajouté à la liste des six services d'après-effacement. Raison : il
    //  possède 26 chemins d'écriture (25 `_save()` + 7 unités directes) et un
    //  `_load()` qui ÉCRIT lui-même (flag de migration l.1596, `_save()`
    //  l.4280). Appelé après la boucle, son vidage RAM serait trop tardif et
    //  ses écritures suspendues réécriraient les clés effacées.
    //
    //  La boucle des 108 clés reste UNIQUE : elle est passée en callback à la
    //  barrière INTERNE, qui s'exécute elle-même dans la barrière EXTERNE.
    //  Les deux barrières sont donc actives pendant tout l'effacement.
    //
    //  ★ B5c-C1-a — CONTRÔLE DU RÉSULTAT DE CHAQUE SUPPRESSION
    //
    //  `SharedPreferences.remove()` a DEUX modes d'échec :
    //    1. exception → visible, donc déjà correctement remontée ;
    //    2. retour `false` → SILENCIEUX. Le contrat (shared_preferences_legacy
    //       .dart:173-177) est : `_preferenceCache.remove(key)` d'abord, PUIS
    //       `_store.remove(prefixedKey)` dont le booléen est rendu tel quel.
    //       Le cache est donc déjà vidé même quand la suppression disque a
    //       échoué : la clé SURVIT sur le disque alors que la RAM croit le
    //       contraire. Avant C1-a, ce booléen était ignoré et le reset
    //       s'annonçait réussi avec des clés encore présentes.
    //
    //  On collecte les échecs au lieu de lever immédiatement : la boucle reste
    //  UNIQUE et parcourt les 108 clés, ce qui donne un diagnostic COMPLET
    //  (quelles clés ont survécu) plutôt qu'un arrêt à la première. La liste
    //  des clés n'est pas modifiée et l'ordre de parcours est inchangé.
    //
    //  ⚠️ Un reset partiellement effectué n'est PAS une transaction annulée :
    //     les clés déjà supprimées le restent. L'exception le dit explicitement.
    // ══════════════════════════════════════════════════════════════════════
    await AlertService.instance.executerResetComplet(() async {
      await IaMemoryService.instance.executerResetComplet(() async {
        // ★ B5c-RDR-05 — EloService encadre la boucle d'effacement au même
        //   titre que les deux autres. Sa barrière est fermée AVANT, ses
        //   écritures en vol sont DRAINÉES avant, et son vidage RAM a lieu
        //   dans un `finally` : il est donc inconditionnel, y compris quand
        //   la StateError ci-dessous est levée (décision D-M1).
        //
        //   Sans cet encadrement, une écriture ELO encore en vol recréait
        //   `elo_ratings_v2` APRÈS sa suppression (scénarios V29-A/V29-B),
        //   et une écriture née PENDANT l'effacement survivait à la fin du
        //   reset (scénario V29-I).
        //
        // ★ B5c-RDR-01-c — DataRefreshService rejoint les trois services
        //   encadrants. Sa barrière est la SEULE qui puisse couvrir le cache
        //   `cache_reunions_*`, dont l'écriture est faite par `_doRefresh`
        //   via `.ignore()` (donc invisible de l'appelant), sur un cycle
        //   pouvant durer 20 s. Trois défauts mesurés la rendent nécessaire :
        //     • V31b R01-J : reset pendant `setString` → la clé réapparaît ;
        //     • V31b R01-K : suspension entre `setString` et `setInt` → `_ts`
        //       orpheline après un reset pourtant terminé ;
        //     • R01-b l'a montré pour la RAM : un refresh EN VOL repeuplait
        //       `_reunions` après le vidage.
        //   Placé IMBRIQUÉ, comme AlertService et IaMemoryService : sa
        //   barrière est fermée AVANT la boucle et son vidage RAM a lieu dans
        //   son `finally`, donc avant la réouverture.
        await EloService.instance.executerResetComplet(() async {
          await DataRefreshService.instance.executerResetComplet(() async {
            final echecs = <String>[];
            for (final key in _toutesLesCles) {
              // `false` et exception réelle sont deux échecs distincts : le premier
              // est ajouté ici, le second remonte tel quel et interrompt la boucle.
              final ok = await prefs.remove(key);
              if (!ok) echecs.add(key);
            }

            // ════════════════════════════════════════════════════════════════
            //  ★ B5c-RDR-01-a — BALAYAGE DES CLÉS DE CACHE DYNAMIQUES.
            //
            //  POURQUOI ICI, ET PAS DANS `_toutesLesCles` : la liste est FIXE,
            //  une clé datée ne peut pas y figurer. Le seul moyen de nommer les
            //  clés réellement présentes est de les LIRE sur le stockage.
            //
            //  POURQUOI APRÈS LA BOUCLE FIXE : l'ordre existant n'est pas
            //  modifié, et le balayage voit un stockage déjà nettoyé des 108
            //  clés connues — il ne peut donc pas retomber sur l'une d'elles.
            //
            //  PORTÉE : `getKeys()` rend les clés SANS le préfixe natif
            //  `flutter.` (shared_preferences_legacy.dart l.111 : il expose
            //  `_preferenceCache.keys`). C'est le même niveau de nommage que
            //  `prefs.remove(key)`, qui ajoute lui-même ce préfixe. Le filtre
            //  `startsWith('cache_reunions_')` couvre donc à la fois
            //  `cache_reunions_<ddmmyyyy>` ET `cache_reunions_<ddmmyyyy>_ts` :
            //  les clés `_ts` sont des préfixes valides, y compris ORPHELINES
            //  (une `_ts` sans JSON, laissée par un `setString` en échec —
            //  comportement mesuré V31b R01-L).
            //
            //  ÉCHECS : même logique que la boucle ci-dessus. Un `remove` qui
            //  rend `false` est enregistré dans `echecs`, qui est le MÊME
            //  accumulateur — le diagnostic `StateError` reste donc unique et
            //  complet, et rien n'est avalé silencieusement.
            //
            //  LIMITE ASSUMÉE : une clé écrite APRÈS ce balayage (c'est-à-dire
            //  pendant la suite du reset, ou par une écriture concurrente non
            //  encore terminée) n'est pas vue ici. Ce point relève de R01-c et
            //  n'est PAS traité par cette correction — voir V31 R01-J / R01-K,
            //  qui doivent continuer à démontrer la réapparition jusqu'à R01-c.
            // ════════════════════════════════════════════════════════════════
            final clesCacheDynamiques = prefs
                .getKeys()
                .where((k) => k.startsWith(_prefsCacheReunionsPrefix))
                .toList();
            for (final key in clesCacheDynamiques) {
              final ok = await prefs.remove(key);
              if (!ok) echecs.add(key);
            }

            if (echecs.isNotEmpty) {
              throw StateError(
                  'Reset complet INCOMPLET : ${echecs.length} suppression(s) '
                  'refusée(s) par le stockage sur ${_toutesLesCles.length} '
                  'clés fixes + ${clesCacheDynamiques.length} clés de cache '
                  'dynamiques — '
                  'clés encore présentes sur le disque : ${echecs.join(', ')}. '
                  'Les suppressions déjà réussies ne sont PAS annulées.');
            }
          });
        });
      });
    });

    // ★ B5 : les clés sont effacées du disque, mais EloService garde ses
    //   ratings EN MÉMOIRE. Sans ce vidage, la prochaine mise à jour ELO
    //   (mettreAJourApresArrivee → _sauvegarder) réécrirait les anciennes
    //   valeurs et le reset serait annulé. On vide donc la RAM — sans
    //   passer par reinitialiser(), qui recréerait 'elo_ratings_v2' = '{}'.
    //
    // ★ B5c-RDR-05 : CET APPEL A ÉTÉ SUPPRIMÉ. Le vidage est désormais fait
    //   par `EloService.executerResetComplet()`, DANS SON `finally`, donc
    //   AVANT la fermeture des barrières et AVANT ce point. Le conserver
    //   serait redondant — et nuisible : exécuté après coup, il masquerait
    //   l'écart entre « vidé parce que le reset a réussi » et « vidé parce
    //   qu'un échec partiel a été rattrapé ».
    //   La méthode `viderMemoirePourResetComplet()` est CONSERVÉE sur
    //   EloService : elle sert d'utilitaire de vidage RAM à v18 et reste le
    //   moyen sûr de jeter la mémoire sans recréer les clés.
    // ★ B5b : même défaut pour le suivi de cote. Le disque est effacé, mais
    //   `_mouvements` alimentait encore les alertes « cotes qui chutent » et
    //   les écritures différées pouvaient recréer les clés après coup.
    //   Le vidage attend les écritures en vol et invalide les opérations
    //   asynchrones déjà démarrées.
    await CoteTrackerService.instance.viderCachePourResetComplet();
    // ★ B5c : même défaut pour le repository de résultats. Le disque est
    //   effacé, mais `_items` restait peuplé en RAM et `_charge` restait à
    //   `true`. Comme `charger()` sort immédiatement quand `_charge` est vrai
    //   (`if (_charge) return`), le prochain `ajouterOuRemplacer()` réécrivait
    //   toutes les anciennes entrées et annulait le reset.
    //   On ne passe pas par `restaurerDepuisBackup({})` : elle appelle
    //   `_sauvegarder()` et recréerait la clé effacée avec `[]`.
    PronosticResultatsRepository.instance.viderMemoirePourResetComplet();
    // ★ B5c : même défaut pour les gros paris. Le disque est effacé, mais les
    //   trois listes restaient peuplées et `_charge` restait à `true`.
    //   `charger()` sortant immédiatement (`if (_charge) return`), le prochain
    //   `ajouterSignauxBatch()` — appelé à chaque ouverture de BestBetScreen —
    //   réécrivait les anciennes entrées et annulait le reset.
    //   On ne passe pas par `importerDepuisBackup({})` : elle appelle
    //   `_sauvegarder()` et recréerait les deux clés effacées, vides.
    QuasiGrosParisService.instance.viderMemoirePourResetComplet();
    // ★ B5c : même défaut pour les badges. Le disque est effacé, mais
    //   `_debloques` restait peuplé en RAM. `_sauvegarder()` écrivant la map
    //   ENTIÈRE (l.203), le prochain `debloquer()` — déclenché par le bouton
    //   « Analyser la journée » — réécrivait tous les anciens badges avec
    //   leurs dates d'origine, annulant le reset.
    //   Contrairement aux étapes 1 et 2, aucun flag `_charge` à réarmer :
    //   `init()` n'est appelé qu'au démarrage (main.dart:73).
    IaBadgesService.instance.viderMemoirePourResetComplet();
    // ★ B5c : idem pour les préférences utilisateur. Le disque est effacé,
    //   mais `_prefs` gardait les habitudes détectées (hippodrome favori,
    //   mise habituelle, suggestions de mise), affichées par 3 widgets.
    //   Contrairement aux étapes 1 à 3, ce service ne fusionne jamais avec
    //   l'ancien état : `_sauvegarder()` n'a qu'un appelant, qui remplace
    //   `_prefs` par un recalcul complet. Pas de résurrection disque possible.
    IaUserPrefsService.instance.viderMemoirePourResetComplet();
    // ★ B5c-RDR-01-b — même défaut, mesuré cette fois : le disque est effacé
    //   (108 clés fixes + balayage dynamique R01-a), mais DEUX caches RAM
    //   conservaient l'état d'AVANT le reset et le réservaient à l'UI.
    //
    //   • DataRefreshService : `_reunions` gardait les réunions
    //     (V31 R01-H : `lieu=RAM-SURVIT` avant ET après reset), et
    //     `_partantsParCourse` / `_nonPartantsNotifies` / `_lastRefresh` /
    //     `_lastError` restaient peuplés. `_lastError` était affiché
    //     directement par l'UI : une erreur d'avant le reset serait restée
    //     visible sans cause.
    //   • ZoneTurfService : `_cache` / `_cacheTime` (statiques, 15 min)
    //     réservaient les réunions d'avant le reset au chemin des écrans,
    //     qui appelle `chargerProgramme()` SANS `forceRefresh`
    //     (V31b R01-N : `reunions=1 appelsRéseau=0`).
    //
    //   ★ B5c-RDR-01-c — LE VIDAGE DATAREFRESH N'EST PLUS ICI.
    //     Il a été DÉPLACÉ dans `DataRefreshService.executerResetComplet()`,
    //     dont le `finally` s'exécute avant la réouverture de la barrière.
    //     Un appel ici serait non seulement redondant, mais TROMPEUR : il
    //     laisserait croire que la protection vient de l'ordre des appels de
    //     `BackupService`, alors qu'elle vient de la barrière du service.
    //     C'est le même raisonnement que R-DR-05 pour EloService.
    //
    //   La purge ZoneTurf, elle, RESTE ICI : ce cache statique n'a pas de
    //   barrière (aucune écriture disque), il n'a donc rien à drainer.
    ZoneTurfService.viderCachePourResetComplet();
    if (kDebugMode) {
      debugPrint('[Backup] Reinitialisation complete '
          '(${_toutesLesCles.length} cles effacees) '
          '— archive historique préservée (décision reportée à E4)');
    }
  }

  /// Efface uniquement les paris utilisateur (conserve la memoire IA)
  Future<void> reinitialiserParis() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _keysParis) {
      await prefs.remove(key);
    }
    if (kDebugMode) {
      debugPrint(
          '[Backup] Paris reinitialises (${_keysParis.length} cles effacees)');
    }
  }

  /// Efface uniquement les alertes
  Future<void> reinitialiserAlertes() async {
    final prefs = await SharedPreferences.getInstance();
    // ★ B5c R-13 : la file de notifications natives fait partie des données
    //   d'alertes. Elle est traitée ici en plus de `reinitialiserComplet()`.
    for (final key in [..._keysAlertes, ..._keysNotificationsEnAttente]) {
      await prefs.remove(key);
    }
    if (kDebugMode) {
      debugPrint('[Backup] Alertes reinitialisees '
          '(${_keysAlertes.length + _keysNotificationsEnAttente.length} '
          'cles effacees)');
    }
  }
}

// ── Resume PoidsIndices pour l'affichage ─────────────────────────────────────

class PoidsIndicesResume {
  final double criteres; // Poids du score multicriteres (0-1)
  final double confiance; // Poids de la confiance IA (0-1)
  final double reussite; // Poids du taux de reussite historique (0-1)

  const PoidsIndicesResume({
    required this.criteres,
    required this.confiance,
    required this.reussite,
  });

  String get resume => 'Criteres:${(criteres * 100).toStringAsFixed(0)}% '
      'Confiance:${(confiance * 100).toStringAsFixed(0)}% '
      'Reussite:${(reussite * 100).toStringAsFixed(0)}%';
}

// ── Resultats Export ─────────────────────────────────────────────────────────

class ExportResult {
  final bool succes;
  final String? filePath;
  final String? fileName;
  final int tailleOctets;
  final String? erreur;

  /// ★ A7 (3.3-C11) — AVERTISSEMENTS NON BLOQUANTS.
  ///
  /// Un export peut RÉUSSIR tout en étant INCOMPLET : un groupe a pu être
  /// omis par refus explicite (registre ELO divergent, lecture impossible).
  /// Sans ce champ, `succes == true` était le SEUL signal, et il ne dit
  /// qu'une chose : « le fichier a été écrit ».
  ///
  /// ⚠️ CE CHAMP N'EST **PAS** UN CANAL D'ERREUR.
  ///   • `erreur` reste réservé à l'ÉCHEC TOTAL (`succes == false`) ;
  ///   • `avertissements` accompagne un `succes == true` et signale ce qui
  ///     manque dans le fichier produit.
  ///   Les confondre afficherait une erreur rouge sur une sauvegarde réussie.
  ///
  /// Liste VIDE par défaut : tout appelant historique obtient `[]` sans
  /// changer une ligne. Aucun constructeur existant n'est cassé.
  final List<String> avertissements;

  /// ★ A7 (3.3-C12) — ÉTAT DE L'OUVERTURE DU MENU DE PARTAGE.
  ///
  /// ⚠️ POURQUOI CE CHAMP EXISTE
  ///   Une sauvegarde partielle (avertissement ELO) et un échec d'OUVERTURE du
  ///   menu de partage produisent tous deux des `avertissements`. Sans un
  ///   marqueur distinct, l'interface ne peut pas savoir si elle peut dire
  ///   « le menu de partage a été ouvert » — et elle l'affirmait à tort.
  ///   Distinguer les deux par le TEXTE de l'avertissement serait fragile :
  ///   un changement de formulation casserait silencieusement l'affichage.
  ///
  /// Valeurs :
  ///   • `null`  → sans objet : le parcours n'ouvre pas de menu de partage
  ///               (téléchargement sur l'appareil, export seul) ;
  ///   • `true`  → le menu natif a été SOLLICITÉ sans lever ;
  ///   • `false` → l'ouverture du menu a LEVÉ. Le fichier existe néanmoins.
  ///
  /// ⚠️ `true` ne prouve AUCUN envoi : `SharePlus.share` rend la main quand le
  ///    menu a été sollicité, pas quand un destinataire a reçu le fichier.
  ///
  /// Défaut `null` : aucun appelant historique n'est affecté.
  final bool? partageOuvert;

  ExportResult({
    required this.succes,
    this.filePath,
    this.fileName,
    this.tailleOctets = 0,
    this.erreur,
    this.avertissements = const <String>[],
    this.partageOuvert,
  });

  /// Vrai si le fichier a été écrit ET qu'aucun groupe n'a été omis.
  ///
  /// Distinct de [succes] : `succes` décrit l'écriture du fichier,
  /// [complet] décrit son CONTENU. Un export partiel est `succes == true`
  /// et `complet == false`.
  bool get complet => succes && avertissements.isEmpty;

  String get tailleLisible {
    if (tailleOctets < 1024) return '$tailleOctets o';
    if (tailleOctets < 1024 * 1024) {
      return '${(tailleOctets / 1024).toStringAsFixed(1)} Ko';
    }
    return '${(tailleOctets / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }
}

// ── Resultats Import ─────────────────────────────────────────────────────────

class ImportResult {
  final bool succes;
  final int nbClesRestaurees;
  final int nbParis; // Nombre reel de paris restaures
  final int nbPronosticsIA; // Nombre reel de pronostics IA restaures
  final int nbIA; // Nombre de cles IA restaurees
  final int nbAlertes; // Nombre reel d'alertes restaurees
  final int nbAlertesCles; // Nombre de cles alertes restaurees
  final int nbWidget; // Nombre de cles widget restaurees
  final int nbConfigIA; // Nombre de cles config IA restaurees
  final int nbProfil; // Nombre de cles profil restaurees
  final DateTime? dateBackup;
  final String version;
  final String? erreur;

  // ── ★ A7 (3.2) — VOLET ELO ────────────────────────────────────────────────
  // Avant 3.2, la restauration ELO etait un `await` MUET : l'etat rendu par
  // `EloService.importerDepuisBackup()` etait JETE, et le tampon « ELO
  // restaure » s'imprimait INCONDITIONNELLEMENT — y compris quand le stockage
  // avait repondu `false`. Ces deux champs sont la seule trace lisible de ce
  // qui s'est reellement passe. Ils ne modifient NI `succes`, NI
  // `nbClesRestaurees`, NI aucun autre groupe de restauration.

  /// Nombre de ratings ELO **charges en memoire (RAM)** depuis la sauvegarde.
  ///
  /// ⚠️ Ce nombre ne prouve AUCUNE persistance physique : il compte ce que
  /// [EloService] detient en RAM apres l'import, pas ce qui est ecrit sur le
  /// disque. Vaut 0 si la sauvegarde ne contenait pas de volet ELO.
  final int nbEloRestaures;

  /// Avertissement sur le resultat REEL du volet ELO.
  /// `null` = persistance CONFIRMEE, ou aucun volet ELO dans la sauvegarde.
  ///
  /// Non nul dans deux familles de cas, qu'il ne faut jamais confondre :
  ///  - persistance **NON CONFIRMEE** (`setString` a repondu `false`, ou a
  ///    leve une exception) — l'etat du stockage n'est alors PAS conclu, et
  ///    il n'est surtout PAS prouve inchange ;
  ///  - ecriture **ABANDONNEE** par un reset complet concurrent — aucune
  ///    ecriture n'a ete tentee.
  ///
  /// Ce champ ne doit JAMAIS etre lu comme « rien n'a change sur le disque ».
  final String? avertissementElo;

  ImportResult({
    required this.succes,
    this.nbClesRestaurees = 0,
    this.nbParis = 0,
    this.nbPronosticsIA = 0,
    this.nbIA = 0,
    this.nbAlertes = 0,
    this.nbAlertesCles = 0,
    this.nbWidget = 0,
    this.nbConfigIA = 0,
    this.nbProfil = 0,
    this.dateBackup,
    this.version = '?',
    this.erreur,
    this.nbEloRestaures = 0,
    this.avertissementElo,
  });

  String get dateBackupLisible {
    if (dateBackup == null) return 'inconnue';
    final d = dateBackup!;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} a ${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';
  }

  /// Resume lisible du resultat de l'import
  String get resumeRestauration {
    if (!succes) return 'Echec : ${erreur ?? 'Erreur inconnue'}';
    final parts = <String>[];
    if (nbParis > 0) parts.add('$nbParis paris');
    if (nbPronosticsIA > 0) parts.add('$nbPronosticsIA pronostics IA');
    if (nbIA > 0) parts.add('$nbIA cles IA');
    if (nbAlertes > 0) parts.add('$nbAlertes alertes');
    if (nbWidget > 0) parts.add('widget');
    if (nbProfil > 0) parts.add('profil');
    return 'Restaure : ${parts.isEmpty ? '$nbClesRestaurees cles' : parts.join(', ')}';
  }
}

// ── Informations sur le backup actuel ────────────────────────────────────────

class BackupInfo {
  // Volume de donnees
  final int tailleOctets;
  final int nbParis;
  final int nbPronostics;
  final int nbJournal;
  final int nbRapports;

  // Alertes
  final int nbAlertes;
  final int nbCoursesTrack;

  // IA
  final bool iaApprise;
  final int nbAjustements;
  final Map<String, double>
      poidsActuels; // 19 critères adaptatifs (v10.x : +mouvCote, +placeDepart)
  final PoidsIndicesResume? poidsIndices; // Indices criteres/confiance/reussite
  final bool aSeuilsAdaptatifs;
  final int nbTypesPrecision;
  final int nbStatsTypes;
  final int nbStatsLabels; // ★ v9.0 : Stats par label IA

  // Profil
  final String? gmail;
  final String? nomProfil;

  // Config Fusion — CHAMPS RETIRÉS (BL1-A16)
  //
  //   Ils décrivaient une configuration produite par un module supprimé et
  //   n'étaient lus par AUCUNE interface. Les 4 clés `fusion_poids_*` restent
  //   collectées et restaurées : c'est la COMPATIBILITÉ DE SAUVEGARDE qui est
  //   préservée, pas l'affichage d'un module qui n'existe plus.

  // Widget
  final bool aWidget;
  final String? widgetUpdatedAt;

  BackupInfo({
    required this.tailleOctets,
    required this.nbParis,
    required this.nbPronostics,
    required this.nbJournal,
    required this.nbRapports,
    required this.nbAlertes,
    this.nbCoursesTrack = 0,
    this.iaApprise = false,
    this.nbAjustements = 0,
    this.poidsActuels = const {},
    this.poidsIndices,
    this.aSeuilsAdaptatifs = false,
    this.nbTypesPrecision = 0,
    this.nbStatsTypes = 0,
    this.nbStatsLabels = 0, // ★ v9.0
    this.gmail,
    this.nomProfil,
    this.aWidget = false,
    this.widgetUpdatedAt,
  });

  String get tailleLisible {
    if (tailleOctets < 1024) return '$tailleOctets o';
    if (tailleOctets < 1024 * 1024) {
      return '${(tailleOctets / 1024).toStringAsFixed(1)} Ko';
    }
    return '${(tailleOctets / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }

  /// Pourcentage de couverture (indicateur sante du backup)
  /// Compte les 10 categories principales presentant des donnees
  int get couverturePct {
    int couvert = 0;
    if (nbPronostics > 0) couvert++; // Pronostics IA
    if (nbJournal > 0) couvert++; // Journal gradient
    if (nbRapports > 0) couvert++; // Rapports journaliers
    if (nbParis > 0) couvert++; // Paris utilisateur
    if (nbAlertes > 0) couvert++; // Alertes
    if (iaApprise) couvert++; // IA a appris (poids ajustes)
    if (aSeuilsAdaptatifs) couvert++; // Seuils adaptatifs
    if (gmail != null) couvert++; // Profil Gmail
    if (aWidget) couvert++; // Widget Android
    return couvert * 10; // /10 categories = %
  }

  /// Description des poids IA pour l'UI
  String get resumePoidsIA {
    if (poidsActuels.isEmpty) return 'IA non initialisee';
    final parts = <String>[];
    void ajouter(String key, String label) {
      final v = poidsActuels[key];
      if (v != null) parts.add('$label:${(v * 100).toStringAsFixed(0)}%');
    }

    ajouter('forme', 'Forme');
    ajouter('cote', 'Cote');
    ajouter('gains', 'Gains');
    ajouter('jockey', 'Jockey');
    ajouter('hippo', 'Hippo');
    return parts.join(' | ');
  }
}
