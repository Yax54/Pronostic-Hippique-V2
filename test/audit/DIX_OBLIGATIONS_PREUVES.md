# Les dix obligations architecturales — rattachement des preuves

**Commit de référence** : `f292d88` (branche `main`)
**Exécution des preuves** : `flutter test test/data/connaissances/` → **190/190 verts en 61 s**

> ⚠️ **Règle de lecture de ce document.** Un fichier de test n'est pas une preuve.
> Chaque ligne ci-dessous cite un **nom de test précis** (celui qui s'affiche dans
> la sortie de `flutter test`) et, quand elle existe, la **mesure chiffrée** que ce
> test imprime. Ce qui n'a pas de preuve est déclaré **NON PROUVÉ** en fin de
> document, sans habillage.

---

## Obligation 1 — Permanence et reconstruction des index

| Preuve | Fichier:ligne | Mesure |
|---|---|---|
| « l'INDEX N'EST PAS UNE DÉPENDANCE : le supprimer ne perd rien » | `test/data/connaissances/archives_segmentees_test.dart:115` | — |
| « un index CORROMPU n'est jamais une perte de connaissance » | `archives_segmentees_test.dart:229` | `[MESURE] index corrompu → 1 entrée(s) retrouvée(s) par consultation ciblée, 12 au total (avant : 12)` |
| « l'écriture est en AJOUT SEUL et idempotente » | `archives_segmentees_test.dart:70` | — |
| « segmentation : un nouveau segment s'ouvre, RIEN n'est supprimé » | `archives_segmentees_test.dart:191` | — |
| « la lecture complète est en FLUX et ne matérialise rien » | `archives_segmentees_test.dart:261` | `[MESURE] parcours en flux : 100 entrée(s), somme des scores = 12000.00` |

**Production concernée** : `lib/data/connaissances/_archives/archives_segmentees.dart`
(`[Archives] ✅ index reconstruit : N entrée(s) depuis M segment(s)` observé en exécution).
**Conformité : PROUVÉE.** L'index corrompu est reconstruit à l'identique depuis les
segments ; aucune connaissance n'est perdue.

---

## Obligation 2 — Protection contre les homonymes

| Preuve | Fichier:ligne |
|---|---|
| « deux homonymes d'années différentes ne partagent pas l'identité » | `test/data/connaissances/depot_sqlite_test.dart:82` |
| « un nom sans année de naissance reste au niveau provisoire » | `depot_sqlite_test.dart:92` |
| « un identifiant fournisseur est du niveau le plus élevé » | `depot_sqlite_test.dart:97` |
| « la normalisation des noms est stable et sans accent » | `depot_sqlite_test.dart:103` |

Le test `:82` est **fonctionnel, pas déclaratif** : il insère réellement deux
`NELSON DU RIB` (2015 et 2019) dans le dépôt et vérifie que `compterChevaux()` rend
**2**, pas 1. La fusion serait détectée.

**Production concernée** : `lib/data/connaissances/_core/identifiants.dart:105,127`
(identité composite), `_adapters/depot_sqlite.dart:629`, `_services/corpus_performances.dart:389`.
**Conformité : PROUVÉE.**

---

## Obligation 3 — Identité stable des chevaux et des courses

| Preuve | Fichier:ligne |
|---|---|
| « deux homonymes d'années différentes ne partagent pas l'identité » | `depot_sqlite_test.dart:82` |
| « la normalisation des noms est stable et sans accent » | `depot_sqlite_test.dart:103` |
| « les deux disciplines d'un même cheval restent séparées » | `depot_sqlite_test.dart:130`, `pont_elo_test.dart:85` |
| « les ratings d'identité non résolue sont conservés (D-20) » | `pont_elo_test.dart:100` |
| « la date n'est jamais un identifiant » | `recuperateur_rapports_test.dart:153` |
| Identité de course ELO (observabilité, deltas appariés) | `test/a7_33b2b_identite_course_test.dart` |
| « deux contenus de même date restent deux rapports distincts » | `recuperateur_rapports_test.dart:252` |

**Production concernée** : `identifiants.dart` (niveaux `provisoire` / supérieur),
`zt_models.dart` `IdentiteCourseElo`, `courseKey` = `R<r>C<c>_<JJMMAAAA>`.
**Conformité : PROUVÉE.** Le cheval n'est **jamais** identifié par son seul nom, ni
la course par sa seule date.

---

## Obligation 4 — Conservation des connaissances authentiques lors des corrections officielles partielles

| Preuve | Fichier:ligne |
|---|---|
| « mode conservateur : la valeur locale divergente est conservée » | `restaurateur_test.dart:489` |
| « mode complet : la valeur est remplacée ET le conflit est tracé » | `restaurateur_test.dart:515` |
| « des valeurs identiques ne créent aucun conflit » | `restaurateur_test.dart:542` |
| « le retour arrière rétablit la valeur locale antérieure » | `restaurateur_test.dart:563` |
| « un conflit est enregistré en attente, jamais résolu seul » | `depot_sqlite_test.dart:392` |
| « les copies multiples d'un même contenu sont toutes tracées » | `depot_sqlite_test.dart:311` |

**Production concernée** : `lib/data/connaissances/_sauvegarde/restaurateur.dart`,
`_adapters/depot_sqlite.dart` (table de conflits).
**Conformité : PROUVÉE.** Une correction partielle **n'écrase pas** silencieusement
une valeur locale divergente : elle est conservée en mode conservateur, ou remplacée
**avec trace** en mode complet. Le conflit n'est **jamais** résolu automatiquement.

---

## Obligation 5 — Traçabilité et provenance des données

| Preuve | Fichier:ligne | Mesure |
|---|---|---|
| « les 3 sources sont distinguées et totalisées » | `recuperateur_rapports_test.dart:80` | 524 copies physiques |
| « 225 contenus bruts distincts » | `recuperateur_rapports_test.dart:87` | 225 |
| « 24 rapports n'existent que dans les bilans » | `recuperateur_rapports_test.dart:107` | 24 |
| « 6 divergences de même date sont détectées » | `recuperateur_rapports_test.dart:116` | 6 |
| « absent, null et renseigné produisent trois empreintes distinctes » | `depot_sqlite_test.dart:301` | — |
| « un bilan référence la version EXACTE du rapport utilisé » | `restaurateur_test.dart:672` | — |
| « un bilan mensuel référence aussi les rapports de ses semaines » | `restaurateur_test.dart:719` | — |
| « fnum2 est conservé dans le contenu stocké » | `depot_sqlite_test.dart:272` | — |
| « la sauvegarde source n'est pas modifiée par la lecture » | `recuperateur_rapports_test.dart:165` | — |

**Production concernée** : `_core/empreinte_contenu.dart`, `_migration/recuperateur_rapports.dart`.
**Conformité : PROUVÉE.** La provenance (quelle source, quelle copie, quelle version)
est conservée et distinguée ; `Absent.marqueur` empêche la confusion absent/null/renseigné.

---

## Obligation 6 — SQLite comme source de référence pour les données migrées

| Preuve | Fichier:ligne |
|---|---|
| « le schéma s'applique et la version est enregistrée » | `depot_sqlite_test.dart:47` |
| « toutes les tables déclarées existent réellement » | `depot_sqlite_test.dart:51` |
| « le contrôle d'intégrité SQLite répond ok » | `depot_sqlite_test.dart:59` |
| « la base vit sur un vrai fichier, pas en mémoire » | `depot_sqlite_test.dart:64` |
| « l'intégrité SQLite du dépôt de production est saine » | `pont_elo_test.dart:151` |
| « les 6 dossiers sont créés sous la racine applicative » | `pont_elo_test.dart:48` |
| « le fichier de base existe sur disque après ouverture » | `pont_elo_test.dart:57` |
| « une écriture ELO est répliquée dans le dépôt » | `pont_elo_test.dart:63` |
| « l'inventaire reflète les lignes réellement écrites » | `pont_elo_test.dart:139` |
| « la recherche par cheval fonctionne sur le dépôt de production » | `pont_elo_test.dart:158` |

**Production concernée** : `_adapters/schema_sqlite.dart`, `_adapters/depot_sqlite.dart`,
`_adapters/pont_elo.dart`. Base **sur disque**, pas en mémoire ; intégrité vérifiée.
**Conformité : PROUVÉE.**

---

## Obligation 7 — Intégrité de la reprise après restauration interrompue

| Preuve | Fichier:ligne |
|---|---|
| « aucun travail en cours : reprendre() ne fait rien » | `reprise_restauration_test.dart:89` |
| « §2 — reprise idempotente : un second appel ne fait rien » | `reprise_restauration_test.dart:320` |
| « interruption PENDANT le retour arrière : le rejeu est idempotent » | `reprise_restauration_test.dart:358` |
| « le journal d'intention porte bien le chemin de l'instantané » | `reprise_restauration_test.dart:450` |
| « l'instantané couvre réellement les quatre supports » | `reprise_restauration_test.dart:482` |
| « une transaction annulée ne laisse aucune trace partielle » | `depot_sqlite_test.dart:363` |
| « rejouer une étape ne duplique rien (idempotence) » | `depot_sqlite_test.dart:382` |
| « le journal permet de reprendre une opération » | `depot_sqlite_test.dart:405` |
| « une écriture interrompue ne détruit pas la sauvegarde précédente » | `restaurateur_test.dart:363` |
| « un instantané de retour arrière est écrit AVANT toute écriture » | `restaurateur_test.dart:396` |
| « un dossier temp inexistant provoque un refus AVANT écriture » | `restaurateur_test.dart:433` |

**Production concernée** : `_sauvegarde/transaction_globale.dart`,
`_services/reprise_restauration_service` (via `lib/services/reprise_restauration_service.dart`).
**Conformité : PROUVÉE.** L'instantané est écrit **avant** toute écriture ; une
interruption pendant le retour arrière laisse un état rejouable sans perte.

---

## Obligation 8 — Conservation exhaustive des connaissances ELO

| Preuve | Fichier:ligne | Mesure |
|---|---|---|
| « un rating est restitué à l'identique, sans arrondi » | `depot_sqlite_test.dart:112` | — |
| « les deux disciplines d'un même cheval restent séparées » | `depot_sqlite_test.dart:130` | — |
| « un rating orphelin (identité non résolue) est conservé » | `depot_sqlite_test.dart:152` | — |
| « aucun plafond : 25 000 ratings coexistent sans purge » | `depot_sqlite_test.dart:167` | 25 000 |
| « les ratings d'identité non résolue sont conservés (D-20) » | `pont_elo_test.dart:100` | — |
| « la comparaison ELO est exhaustive et aucun rating n'est fusionné » | `raccordement_backup_test.dart:177` | — |
| « la restauration de la sauvegarde 13/11 rend 9 001 ratings, valeurs … » | `restaurateur_test.dart:768` | 9 001 |
| « la sauvegarde 28/05 restaure aussi ses ratings » | `restaurateur_test.dart:884` | `[MESURE] contrôle ELO exhaustif 28/05 : **1934/1934** ratings vérifiés sur 6 attributs, 0 sans discipline résolue (D-20), **0 écart**` |
| « la restauration de 9 001 ratings tient dans un temps mesuré » | `restaurateur_test.dart:923` | `[MESURE] 5224 ms pour 9001 ratings` |
| « rejouer la réplication ne duplique rien » | `pont_elo_test.dart:114` | — |
| « une mise à jour remplace la valeur, sans en créer une seconde » | `pont_elo_test.dart:125` | — |
| ELO en isolate : trois distinctions mesurées | `test/v2_d3_elo_isolate_test.dart` (T7) | `isolate={1:75.0, 2:37.5, 3:0.0, 4:50.0} principal={idem}` |
| Écritures ELO pendant un reset : aucune | `test/v29b_b5c_rdr05_verifications_test.dart` | `écritures ELO de toute la session = []` |

**Production concernée** : `elo_service.dart`, `_adapters/pont_elo.dart`,
`_migration/migrateur_elo.dart`, `_migration/bascule_elo.dart`.
**Conformité : PROUVÉE.** Aucun plafond, aucune purge (D-20), aucun arrondi,
aucune fusion ; `1934/1934` ratings vérifiés sur 6 attributs avec **0 écart**.

---

## Obligation 9 — Conservation des rapports historiques et de leurs versions

| Preuve | Fichier:ligne | Mesure |
|---|---|---|
| « les versions EXACTES de rapport et de bilan sont conservées » | `archives_segmentees_test.dart:211` | `[MESURE] versions de rapport conservées : {RAPPORT_v1, RAPPORT_v2} ; bilans : {BILAN_v1}` |
| « 524 copies physiques sont récupérées » | `recuperateur_rapports_test.dart:74` | 524 |
| « le corpus réel est enregistré sans perte » | `recuperateur_rapports_test.dart:175` | — |
| « fnum2 survit intégralement à l'enregistrement » | `recuperateur_rapports_test.dart:195` | — |
| « un rapport présent uniquement en bilan est bien récupéré » | `recuperateur_rapports_test.dart:207` | — |
| « rejouer l'enregistrement ne duplique rien » | `recuperateur_rapports_test.dart:231` | — |
| « deux contenus de même date restent deux rapports distincts » | `recuperateur_rapports_test.dart:252`, `restaurateur_test.dart:594` | — |
| « la normalisation est réversible : l'original se reconstruit » | `depot_sqlite_test.dart:290` | — |
| « deux copies identiques ne créent qu'un enregistrement » | `depot_sqlite_test.dart:221` | — |
| « deux contenus de même date mais différents restent deux » | `depot_sqlite_test.dart:249` | — |
| « rejouer une restauration ne duplique aucun rapport (§14) » | `restaurateur_test.dart:637` | — |
| « les rapports de la sauvegarde 13/11 sont restaurés avec leur … » | `restaurateur_test.dart:817` | — |

**Production concernée** : `_migration/recuperateur_rapports.dart`,
`_archives/archives_segmentees.dart`, `_adapters/depot_sqlite.dart` (déduplication par contenu).
**Conformité : PROUVÉE.** Les versions distinctes sont conservées **toutes** ;
la déduplication se fait par **contenu**, jamais par date seule.

---

## Obligation 10 — Sauvegarde et restauration complètes de l'ensemble des données permanentes

| Preuve | Fichier:ligne |
|---|---|
| « l'export couvre TOUTES les clés prefs, y compris une clé inconnue » | `raccordement_backup_test.dart:83` |
| « le manifeste déclare une exclusion quand le dépôt est fermé » | `raccordement_backup_test.dart:119` |
| « deux exports successifs produisent deux fichiers distincts » | `raccordement_backup_test.dart:139` |
| « une clé supprimée localement est rétablie par la restauration » | `raccordement_backup_test.dart:154` |
| « un conteneur altéré est refusé sans aucune écriture » | `raccordement_backup_test.dart:223` |
| « un conteneur illisible est refusé proprement » | `raccordement_backup_test.dart:244` |
| « une sauvegarde JSON v9.0 est restaurée par le chemin historique » | `raccordement_backup_test.dart:254` |
| « l'instantané couvre les quatre supports et se vérifie » | `raccordement_backup_test.dart:288` |
| « le retour arrière rétablit prefs, SQLite et fichiers » | `raccordement_backup_test.dart:321` |
| « le retour arrière est idempotent : rejouer ne dégrade pas » | `raccordement_backup_test.dart:375` |
| « un instantané altéré est refusé : retour arrière impossible, et dit » | `raccordement_backup_test.dart:398` |
| « une ancienne sauvegarde JSON est reconnue legacy, sans faux … » | `restaurateur_test.dart:170` |
| « un JSON illisible est refusé sans qu'aucune écriture n'ait lieu » | `restaurateur_test.dart:188` |
| « un bloc altéré est refusé, et aucun autre bloc n'est appliqué » | `restaurateur_test.dart:203` |
| « extraireBloc refuse un bloc altéré » | `restaurateur_test.dart:248` |
| « un cache déclaré est ignoré et signalé, jamais restauré » | `restaurateur_test.dart:327` |

**Production concernée** : `_sauvegarde/format_sauvegarde.dart`,
`_sauvegarde/restaurateur.dart`, `lib/services/backup_service.dart`.
Quatre supports couverts : **prefs, SQLite, fichiers, archives**.
**Conformité : PROUVÉE.** Sauvegarde exhaustive (clés inconnues incluses),
restauration authentifiée, refus intégral en cas d'altération partielle.

---

# Ce qui n'est PAS prouvé ici — déclaré sans détour

1. **Aucune exécution sur appareil Android physique.** Toutes les mesures
   proviennent de la VM Dart sous `sqflite_common_ffi`. Le comportement du
   `sqflite` natif Android (verrous, chemins, permissions) n'est **pas** validé
   par ces tests. C'est une limite réelle, non une omission.
2. **La disponibilité réelle des rapports PMU en production** n'est pas prouvée :
   `test/audit/double_apprentissage_chemins_test.dart` utilise un réseau **simulé**
   (`MockClient`). Il prouve les chemins et les gardes, pas le taux de couverture
   réel des rapports.
3. **Les obligations 1 à 10 sont prouvées pour les composants couverts par
   `test/data/connaissances/`**. Les services historiques (`ia_memory_service`,
   `elo_service`, `ia_archive_service`) ont leurs propres preuves, rattachées
   séparément dans les sections §2 et §4 du rapport final. Aucun des deux
   ensembles ne prouve l'autre.
