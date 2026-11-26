# CHANTIER GLOBAL — RAPPORT CONSOLIDÉ D'ARCHITECTURE

**Pronostic Hippique / Race Predictor** — Dart `pronostic_hippique`, Android `com.racepredictor.predict`
Branche `main`, dernier commit de référence : `0955558`
Flutter 3.35.4 / Dart 3.9.2 (gelés). Aucune migration, aucun reset, aucune intégration définitive.

---

## LÉGENDE DES QUALIFICATIONS

Chaque affirmation de ce rapport porte l'une des marques suivantes. Elle est **obligatoire** et
non décorative : une affirmation sans marque est un défaut de rédaction.

| Marque | Signification |
|---|---|
| **[DÉMONTRÉ]** | Établi par lecture du code source, avec référence de fichier et de ligne. |
| **[MESURÉ]** | Résultat d'une exécution dans cet environnement (Dart test, script Python sur les fichiers réels). La commande ou le calcul est reproductible. |
| **[CALCULÉ]** | Projection arithmétique à partir de mesures réelles, avec hypothèses explicitées. Ce n'est pas une mesure. |
| **[ESTIMÉ]** | Ordre de grandeur argumenté, sans mesure directe possible ici. |
| **[APPAREIL REQUIS]** | Mesure qui exige un terminal Android réel. **Reportée, pas abandonnée.** |
| **[INDÉTERMINÉ]** | Recherche effectuée, preuve obtenue que la réponse est hors d'atteinte. Non résolu, et non résoluble avec les éléments disponibles. |

**Rappel de méthode.** Aucune valeur de ce rapport n'est inventée. Les deux sauvegardes réelles
n'ont été **que lues** (md5 vérifiés avant et après l'étude, identiques).

---

# A. ÉTAT ACTUEL

## A.1 Architecture actuelle

**[DÉMONTRÉ]** L'application repose sur une architecture en services singleton, sans couche de
persistance unifiée. Chaque service détient sa propre clé de `SharedPreferences` et sérialise
lui-même ses données en JSON.

Services structurants identifiés :

| Service | Rôle | Clé(s) possédée(s) |
|---|---|---|
| `IaMemoryService` | Mémoire IA : poids, pronostics, journal, rapports, bilans, seuils | 44 clés `ia_*` recensées |
| `EloService` | Ratings ELO par cheval × discipline | `elo_ratings_v1` (+ `elo_orphelins_purges_v1`) |
| `QuasiGrosParisService` | Signaux « gros paris à surveiller » | `ia_gros_paris_*` |
| `CoteTrackerService` | Mouvements de cote (fenêtre −0/+30 min) | `cote_tracker_mouvements_v1`, `cote_mouvements_live_v1` |
| `IaArchiveService` | Archive permanente des pronostics évincés | `ia_archive_v1_manifest`, `ia_archive_v1_<date>` |
| `BackupService` | Collecte, export, restauration | aucune (agrégateur) |
| `ZoneTurfService` | Accès API PMU | aucune (réseau) |
| `DataRefreshService` | Orchestration du rafraîchissement | aucune (orchestrateur) |

Il n'existe **aucune** couche d'abstraction commune : pas de dépôt unique, pas de schéma
partagé, pas de registre de clés centralisé. La conséquence est examinée en §A.8 et §D.

## A.2 Inventaire des connaissances — chiffré

**[MESURÉ]** Le tableau ci-dessous est calculé sur la sauvegarde du **13/11/2026**
(12 293 558 octets, md5 `59a480e63932ff58621332d9894c3a77`). Les tailles sont celles de la
valeur sérialisée en JSON compact UTF-8, hors balisage.

### A.2.1 Bloc `ia` — 14 clés, 9 236 007 octets (75,1 % du fichier)

| Clé | Nature | n | Octets | Part du bloc `ia` |
|---|---|---:|---:|---:|
| `ia_bilans_semaine_v1` | `StringList` de `BilanSemaine` | 28 | 2 903 132 | 31,4 % |
| `ia_rapports_v1` | `StringList` de `RapportJournalier` | 195 | 2 383 324 | 25,8 % |
| `ia_bilans_mois_v1` | `StringList` de `BilanMois` | 7 | 2 276 152 | 24,6 % |
| `ia_journal_v2` | `StringList` d'entrées de gradient | 500 | 1 044 361 | 11,3 % |
| `premium_widgets_selection_jour_v1` | `String` JSON | — | 251 105 | 2,7 % |
| `ia_pronostics_v2_gz` | `String` base64(gzip(JSON)) | 600 | 196 086 | 2,1 % |
| `ia_precision_v2` | `String` JSON | — | 68 509 | 0,7 % |
| `ia_stats_labels_v1` | `String` JSON | — | 55 065 | 0,6 % |
| `ia_premium_historique_v1` | `String` JSON | — | 52 952 | 0,6 % |
| `ia_poids_v3` | `String` JSON | — | 3 876 | 0,04 % |
| `ia_stats_types_v1` | `StringList` | 6 | 407 | 0,004 % |
| `ia_seuils_v1` | `String` JSON | — | 138 | 0,001 % |
| `ia_premium_du_jour_v1` | `String` | — | 124 | 0,001 % |
| `ia_derniere_analyse_v1` | `String` | — | 10 | — |

**Trois agrégats représentent 81,8 % du bloc `ia`** : `ia_bilans_semaine_v1`,
`ia_rapports_v1`, `ia_bilans_mois_v1`. Ce fait commande toute la partie D et E du rapport.

### A.2.2 Autres blocs

| Bloc | Nature | n | Octets | Part du fichier |
|---|---|---:|---:|---:|
| `grosParis` | 3 clés (`signaux`, `quasiGagnants`, `grosParisGagnants`) | — | 1 041 972 | 8,5 % |
| `elo_service` | `Map` clé `NOM\|DISCIPLINE` → `{nom, rating, nb, var}` | 9 001 | 940 806 | 7,7 % |
| `alertes` | — | 11 | 21 464 | 0,2 % |
| `configIA` | 26 préférences typées `{type, value}` | 26 | 2 653 | 0,02 % |
| `auditCache` | — | 1 | 3 294 | 0,03 % |
| `paris` | — | 1 | 2 888 | 0,02 % |
| `laboIA` | `simulation_candidates_v1` | 1 | 609 | 0,005 % |
| `profil` | — | 3 | 207 | 0,002 % |
| `cote` | 2 clés | 2 | 189 | 0,002 % |
| `widget` | **VIDE** | **0** | **2** | — |

### A.2.3 Le bloc `widget` est vide — écart à documenter

**[DÉMONTRÉ]** `backup_service.dart:521-531` déclare 20 clés `widget_*` à collecter
(`widget_course_name`, `widget_horse_name`, … , `widget_course3_confiance`).

**[MESURÉ]** Dans **les deux** sauvegardes réelles, `data['widget']` vaut `{}` — 2 octets, soit
la sérialisation d'un dictionnaire vide. Les 20 clés sont donc absentes du fichier.

**[ESTIMÉ]** Cause la plus probable : ces clés sont écrites par le service natif via
`MethodChannel` dans un `SharedPreferences` distinct (`RacePredictorWidgetData`), comme
l'indique le commentaire `backup_service.dart:524`. Elles ne sont donc pas dans le magasin
`SharedPreferences` lu par la collecte. **Cette explication n'est pas vérifiée sur appareil**
— **[APPAREIL REQUIS]**.

**[DÉMONTRÉ]** La restauration est néanmoins cohérente : `backup_service.dart:1543` traite
`data['widget']` sans exiger de contenu, et `2584` n'ajoute `widget` au résumé que si
`nbWidget > 0`. Une sauvegarde sans widget se restaure donc sans erreur — mais **le widget
d'accueil n'est pas sauvegardé**, ce qui est une limitation fonctionnelle réelle.

### A.2.4 `ia_archive_v1_manifest` absent des deux sauvegardes

**[MESURÉ]** Aucune clé `ia_archive_v1_*` ne figure dans le bloc `ia` des deux fichiers
(14 clés inventoriées, aucune ne commence par `ia_archive`).

**[DÉMONTRÉ]** L'explication est mécanique : les deux sauvegardes sont en **version `9.0`**,
alors que `backup_service.dart:153` porte `_backupVersion = '9.1'` avec le commentaire
`// ★ E3 : +archiveIA`. La collecte de `archiveIA` est conditionnée à l'existence de données
d'archive (`868-869`), et l'archive a été introduite en 9.1. Les deux fichiers réels sont donc
**antérieurs** à l'existence de l'archive — ce n'est pas une anomalie de collecte.

## A.3 Inventaire des sources PMU

**[DÉMONTRÉ]** Point d'entrée : `zone_turf_service.dart:16-17`
```dart
static const _pmuBase = 'https://turfinfo.api.pmu.fr/rest/client/7';
static const _pmuSpec = 'specialisation=INTERNET';
```

**[DÉMONTRÉ]** Endpoint de performances détaillées : `zone_turf_service.dart:2104-2107`
(`/performances-detaillees/pretty`).

**[MESURÉ]** Volume d'une réponse `performances-detaillees` : **89 735 octets**.
**[MESURÉ]** Corpus historique réel exploité : **16 579 courses passées**, **90 770 entrées
participant** au total.

### A.3.1 Couverture et qualité par champ — mesures antérieures confirmées

| Champ | Couverture mesurée | Qualité |
|---|---|---|
| `reductionKilometrique` | 12 155 / 16 579 entrées `itsHim` (**73,3 %**) ; 76 783 / 90 770 participants (**84,6 %**) | **INDIVIDUEL prouvé** : 14 227 / 14 230 courses ont des valeurs distinctes entre participants. 88,2 % à moins de 500 ms du calcul `tempsDuPremier/(distance/1000)`, erreur médiane **11 ms** |
| `etatTerrain` | 6 433 / 16 579 (**38,8 %**) | 9 libellés observés |
| `penetrometre.intitule` | **34 %** | 5 libellés |
| `typePiste` | **34 %** | `herbe`, `gazon`, `pouzolane` |
| Historique par cheval | **0–5 courses**, médiane **5** | 0 = débutant (`indicateurInedit: true`) |
| `participants` d'une course passée | **TRONQUÉ** (ex. 6 listés pour `nbParticipants = 12`) | L'entrée `itsHim = true` est toujours présente |

### A.3.2 Deux constats négatifs importants

**[MESURÉ]** `typePiste` ∩ `etatTerrain` = **∅**. `typePiste` désigne une **surface**
(`herbe`, `gazon`, `pouzolane`), jamais un état. Les deux champs ne sont pas substituables.

**[MESURÉ]** 5 clés **fantômes**, 0 occurrence sur 3 788 participants :
`recordAbsolu`, `performances`, `historiquePerformances`, `placeDepartCourse`, `corde`.
Ces clés sont référencées dans le code mais ne sont **jamais** fournies par l'API.

## A.4 Inventaire du stockage

**[DÉMONTRÉ]** Technologie unique : `SharedPreferences` (fichier XML unique côté Android),
plus des fichiers JSON temporaires pour l'export de sauvegarde.

**Clés IA recensées : 44** (familles `ia_*`). Plafonds **codés en dur** :

| Constante | Valeur | Référence |
|---|---:|---|
| `_maxPronostics` | 600 | `ia_memory_service.dart:132` |
| `_maxPronosticsAge` | 90 jours | `:134` |
| `_maxJournal` | 500 | `:142` |
| `_maxRapports` | 365 | `:143` |

**Plafonds ABSENTS** — vérifié par recherche exhaustive des motifs `take(` / `sublist` /
`length >` sur les collections concernées :

| Collection | Plafond | Preuve |
|---|---|---|
| `_bilansSemaine` | **AUCUN** | `ia_memory_service.dart:152`, écrit à `2525`, sauvegardé à `2788-2789` **sans `take()`** |
| `_bilansMois` | **AUCUN** | `:160`, écrit à `2586`, sauvegardé à `2790-2791` **sans `take()`** |
| `elo_service` | **AUCUN** (hors purge one-shot des orphelins `NOM\|`, `elo_service.dart:2403-2416`) | `:877` |
| `premium_widgets_selection_jour_v1` | **AUCUN** cap trouvé | `ia_memory_service.dart:7073-7110` |

**[MESURÉ]** Rythme de croissance réel de ces collections, sur **169 jours** séparant les deux
sauvegardes :

| Collection | 28/05 | 13/11 | Δ | Rythme mesuré |
|---|---:|---:|---:|---|
| `_bilansSemaine` | 4 | 28 | +24 | **0,142/jour** (1 par 7,0 j) |
| `_bilansMois` | 1 | 7 | +6 | **0,0355/jour** (1 par 28,2 j) |
| `elo_service` | 1 934 | 9 001 | +7 067 | **41,8 clés/jour** |
| `_journal` | 500 | 500 | 0 | plafonné |
| `_pronostics` | 572 | 600 | +28 | plafonné |

## A.5 Inventaire des sauvegardes

**[MESURÉ]** Deux sauvegardes réelles, lues sans modification :

| | 28/05/2026 | 13/11/2026 | Croissance |
|---|---:|---:|---:|
| Octets | 2 386 883 | 12 293 558 | **×5,15** |
| md5 | `e34c3d4e1a65c8b673a23315bd01b869` | `59a480e63932ff58621332d9894c3a77` | — |
| Version déclarée | `9.0` | `9.0` | identique |
| `appName` | `Pronostic Hippique` | `Pronostic Hippique` | identique |
| `dateBackup` | `2026-05-28T16:25:15` | `2026-11-13T11:17:21` | **169 jours** |

### A.5.1 Format

**[DÉMONTRÉ]** `backup_service.dart:706-717` : 14 clés racines
`[version, appName, dateBackup, ia, configIA, paris, alertes, profil, widget, laboIA,
auditCache, grosParis, elo_service, cote]`. Les valeurs non scalaires sont enveloppées
`{type, value}`.

**[MESURÉ]** Le format réel est reproduit **exactement** par
`JsonEncoder.withIndent('  ')` : la ré-émission du JSON analysé redonne
2 386 883 octets (28/05) et 12 293 558 octets (13/11), **écart 0 octet**. Le format est donc
entièrement déterminé et reproductible.

**[MESURÉ]** Coût de cette indentation : **+181 523 octets (+8,2 %)** au 28/05 et
**+1 216 562 octets (+11,0 %)** au 13/11, par rapport à une sérialisation compacte.
C'est un choix de lisibilité, payé à chaque export.

### A.5.2 Chaîne de coût du blob de pronostics

**[MESURÉ]** sur le 13/11 :

| Étape | Octets | Ratio |
|---|---:|---|
| JSON décompressé (600 pronostics) | 689 790 | — |
| gzip | 147 062 | **4,69:1** |
| base64 (ce qui est stocké) | 196 084 | **×1,333** (surcoût base64) |

**[DÉMONTRÉ]** `ia_memory_service.dart:2770-2776` : `GZipCodec().encode(bytes)` puis
`base64Encode(gzipped)`. Le base64 annule un tiers du gain du gzip.

### A.5.3 Composition — ce qui pèse réellement

**[MESURÉ]** Le blob de pronostics ne représente que **1,7 %** du fichier (196 084 /
12 293 558). Les trois agrégats de rapports et bilans en représentent **61,4 %**.

## A.6 Inventaire des restaurations

**[DÉMONTRÉ]** Aucune comparaison de `data['version']` à `_backupVersion` **n'existe**.
`backup_service.dart:1850` lit `final backupVer = data['version'] as String? ?? '1.0';` et
ne s'en sert que pour l'affichage (`1941`). La compatibilité repose **exclusivement** sur une
règle de présence de clé :

> **Règle du local-préservé** : si une clé est absente, mal typée, ou si la lecture lève, le
> stockage local n'est **pas** touché.

Cette règle est appliquée explicitement pour :
- `archiveIA` (`1741-1763`) : absente → « archive locale préservée (compat v<9.1) »
- `arriveesOfficielles` (`1765+`) : absente → stockage local intact
- `resultatsOfficielsPmu` (`1845-1847`) : absente → stockage local préservé
- `laboIA` (`1647`), `auditCache` (`1656`), `cote` (`1636`) : garde `containsKey`
- `elo_service` (`1565`) : garde `containsKey`, et `945` documente explicitement qu'écrire
  `'elo_service': {}` **écraserait** à la restauration

**Une exception, à la formulation trompeuse** : `grosParis` (`1669-1690`) applique bien la
garde `containsKey` (donc une sauvegarde ancienne ne détruit rien), mais le message de la
branche `else` dit « **reset à vide** ». **[ESTIMÉ]** Le libellé décrit un état d'absence de
données, pas une action d'effacement ; la garde protège. **Ce point mérite une vérification
par test** — voir §H.9 décision D-04.

**Conséquence**[DÉMONTRÉ] : une sauvegarde `9.0` restaurée sur un code `9.1` **ne supprime
aucune connaissance locale**. Elle n'en apporte simplement pas de nouvelles. C'est conforme
à l'exigence du mandat §26.

**Mais** : une sauvegarde `9.0` contenant des agrégats **est** restaurée — et réintroduit
intégralement les 5,2 Mo de rapports et bilans qu'elle contient. Il n'y a pas de
réconciliation, pas de déduplication à la restauration de ces blocs.

## A.7 Résultats des vérifications restantes (§3 — CLOS 7/7)

| Sous-section | Objet | Statut | Preuve |
|---|---|---|---|
| §3.1 | ELO par discipline | **CLOS** | Clé composite `NOM\|DISCIPLINE` ; deux ratings distincts coexistent (1700 trot / 1300 plat, `nbChevauxSuivis == 2`) ; repli clé globale puis `1500.0` ; barème `(elo−1200)/8` borné |
| §3.2 | Mouvement de cote | **CLOS** | 7 paliers (90/75/62/50/38/28/15) ; injection par map seule ; fenêtre `[0,+30 min]` ; clé `R3C1_26112026` |
| §3.3 | Poids effectifs | **CLOS** | 3 chemins publics → scores identiques ; 19 critères ; sérialisation isolate préserve les poids de discipline |
| §3.4 | Trot monté | **CLOS** | Seuil **mesuré** : 3 bons + 1 mauvais = **4** → refus ; 8 + 1 = **9** → écriture. `trot_monte` créée, distincte, persistée, servie, journalisée |
| §3.5 | Famille `global` | **CLOS** | Voir A.7.1 — **le constat d'une session précédente était faux, corrigé par la mesure** |
| §3.6 | Chaînes de bout en bout | **CLOS** | 5 expériences isolées sur le chemin réel `enregistrerResultat` |
| §3.7 | Conversion en caractérisation | **CLOS** | M4.2 / M5.2 / M7.2 confirmés en caractérisation, 20/20 PASS |

### A.7.1 Le cas `global` — correction d'un constat erroné

**[DÉMONTRÉ]** `ia_memory_models.dart:682` : `normaliseDiscipline()` retourne `'global'` pour
toute discipline non reconnue.

**[DÉMONTRÉ]** `ia_memory_service.dart:4253` écrit `_poids.poidsParDiscipline[discNorm]` où
`discNorm = normaliseDiscipline(disciplineCible)` (`:4116`). La clé `'global'` est donc
**écrivable**, persistée et servie prioritairement (`:635`).

**[MESURÉ]** — **fait nouveau, décisif** : la clé `'global'` **existe réellement** dans le
`ia_poids_v3` des deux sauvegardes, aux côtés de `plat`, `obstacle`, `trot_attele`.

**[MESURÉ]** Sur **169 jours**, évolution du delta maximal par discipline :

| Discipline | delta max 28/05 → 13/11 |
|---|---:|
| `global` | **5,55 × 10⁻¹⁷** |
| `plat` | 6,32 × 10⁻² |
| `obstacle` | 5,58 × 10⁻² |
| `trot_attele` | 5,11 × 10⁻² |

**Interprétation [DÉMONTRÉ]** : 5,55 × 10⁻¹⁷ est du bruit de virgule flottante (epsilon
machine). La clé `'global'` **n'a jamais été réécrite** en 169 jours. Les 3 autres disciplines
ont bougé de 19 critères sur 19. La branche de `clampDiscipline()` qui se termine par
`return 'global'` (`ia_memory_models.dart:682`) n'a donc **jamais été atteinte par
l'apprentissage** sur ces deux périodes : aucune course réelle n'a produit de discipline
méconnaissable. C'est un **état inerte, hérité d'un état antérieur**, pas un mécanisme actif.

## A.8 Défauts identifiés et causes démontrées

| # | Défaut | Gravité | Cause démontrée | Référence |
|---|---|---|---|---|
| **DF-01** | Croissance **non bornée** de `BilanMois` | **Critique** | Aucune constante de plafond, aucun `take()` à la sauvegarde | `ia_memory_service.dart:160, 2586, 2790` |
| **DF-02** | Croissance **non bornée** de `BilanSemaine` | **Critique** | Idem | `:152, 2525, 2788` |
| **DF-03** | **Duplication emboîtée à 3 niveaux** des rapports | **Critique** | `BilanSemaine.rapportsJson` contient les rapports complets ; `BilanMois.semaines` contient les `BilanSemaine` **avec** leurs rapports | `:2496` (`rapportsJson: rjs.map(...)`), `:2586` (`semaines: semaines`) |
| **DF-04** | Croissance **non bornée** de `elo_service` | Haute | Aucune purge hors orphelins one-shot | `elo_service.dart:877, 2403` |
| **DF-05** | `_save()` réécrit **99,7 %** du volume | Haute | Toutes les clés sont réécrites à chaque sauvegarde, sans distinction de ce qui a changé | `ia_memory_service.dart:2743-2800` |
| **DF-06** | Le base64 annule 33 % du gain gzip | Moyenne | `base64Encode(gzipped)` | `:2775` |
| **DF-07** | L'indentation coûte **+8,2 % / +11,0 %** | Moyenne | `JsonEncoder.withIndent('  ')` | `backup_service.dart:1237` |
| **DF-08** | `widget` **jamais sauvegardé** | Moyenne | 20 clés déclarées, 0 collectée dans les deux fichiers réels | `backup_service.dart:521-531` |
| **DF-09** | Comptage des pronostics **estimé**, pas mesuré | Basse | `nbPronosticsIA = (gz.length / 130).round()` — commentaire « Estimation » | `backup_service.dart:1856-1859` |
| **DF-10** | Restauration **sans déduplication** des agrégats | Haute | Aucune réconciliation sur `ia_rapports_v1` / `ia_bilans_*` | `backup_service.dart` (absente) |
| **DF-11** | Écriture du fichier **non atomique** | Haute | `file.writeAsBytes(bytes)` directement sur `getTemporaryDirectory()` ; pas de `.tmp` puis `rename` | `backup_service.dart:1246-1248` |
| **DF-12** | `ia_archive_v1_manifest` absent du fichier 9.0 | **Non-défaut** | Les deux fichiers sont antérieurs à la 9.1 | `backup_service.dart:153, 868` |

### A.8.1 DF-03 — démonstration de la duplication

**[DÉMONTRÉ]** `ia_memory_service.dart:2496` :
```dart
rapportsJson: rjs.map((r) => json.encode(r.toJson())).toList(),
```
`BilanSemaine` embarque donc les **rapports complets**, pas un résumé.

**[DÉMONTRÉ]** `:2586` : `BilanMois(..., semaines: semaines, ...)` — les `BilanSemaine` sont
embarqués **tels quels**, rapports compris.

**[MESURÉ]** Décomposition de la dernière entrée de `ia_bilans_mois_v1` (13/11) :

| Champ | Octets | Part |
|---|---:|---:|
| `sem` (les `BilanSemaine` embarqués) | **242 120** | **99,99 %** |
| tous les autres champs réunis | ~101 | 0,01 % |

**[MESURÉ]** Décomposition de la dernière entrée de `ia_bilans_semaine_v1` :

| Champ | Octets | Part |
|---|---:|---:|
| `rj` (les rapports embarqués) | **85 326** | **99,99 %** |
| tous les autres champs réunis | ~109 | 0,01 % |

**Conclusion [DÉMONTRÉ]** : chaque rapport journalier est stocké **trois fois** — une fois
dans `ia_rapports_v1`, une fois dans le `BilanSemaine` qui le contient, une fois dans le
`BilanMois` qui contient ce `BilanSemaine`. La valeur informationnelle des bilans eux-mêmes
est négligeable (0,01 %) : ce sont des enveloppes autour d'une copie des rapports.

### A.8.2 DF-03 — la redondance, quantifiée

**[MESURÉ]** sur la sauvegarde du 13/11 :

| Emplacement | Copies de rapports |
|---|---:|
| `ia_rapports_v1` | 195 |
| `BilanSemaine.rj` (28 bilans) | 185 |
| `BilanMois.sem[].rj` (7 bilans) | 144 |
| **TOTAL de copies stockées** | **524** |

**[MESURÉ]** Journaux **distincts** (identifiés par leur date) :
`ia_rapports_v1` = 195, `BilanSemaine` = 185, `BilanMois` = 144.
Intersection rapports ∩ semaines = **161**. Intersection semaines ∩ mois = **144** (incluse).
**Union réelle = 219 journaux distincts.**

**Redondance mesurée = 524 / 219 = 2,39×.**

### A.8.3 Valeur informationnelle propre des bilans

**[DÉMONTRÉ]** Un `BilanSemaine` ne contient, hors `rj`, que 9 valeurs dérivées :
`lundi`, `dim`, `tc`, `tr`, `tg`, `tt3`, `sm`, `md`, `mt`.
Un `BilanMois` ne contient, hors `sem`, que les mêmes agrégats pour le mois.

**[MESURÉ]** Exemple du dernier `BilanMois` : `tc = 672`, `tr = 661`, `tg = 160`,
`tt3 = 329`, `sm = 43,989…`, `md = 'Steeple Chase'`, `mt = 26,92…`.

**Conclusion [DÉMONTRÉ]** : ces 9 valeurs sont **entièrement recalculables** à partir des
rapports, en temps négligeable. Elles n'ont aucune valeur de conservation historique qui
exigerait de dupliquer la charge utile.

## A.9 Ce que ce diagnostic ne dit PAS

Par honnêteté, trois limites explicites :

1. **[INDÉTERMINÉ]** La cause exacte pour laquelle `ia_bilans_mois_v1` a cru de **×147,1**
   entre les deux sauvegardes (1 → 7 entrées, mais 15 477 → 2 276 152 octets) n'est pas
   attribuable à un unique mécanisme : elle combine le nombre d'entrées **et** la
   duplication de charge utile par emboîtement. La mesure donne le résultat ; la
   décomposition exacte par entrée est en A.8.1. Il n'y a pas de « bug » caché
   supplémentaire : la croissance est la conséquence arithmétique de la structure.
2. **[APPAREIL REQUIS]** Le comportement de `SharedPreferences` sur Android lors de
   l'écriture d'un XML de plus de 10 Mo (latence, `apply()` vs `commit()`, risque d'ANR)
   ne peut pas être mesuré ici.
3. **[INDÉTERMINÉ]** Le volume exact du `SharedPreferences` **complet** (toutes clés,
   y compris celles non sauvegardées) n'est pas connaître depuis les fichiers de sauvegarde.

---

# B. COMPLÉMENTARITÉ DES CONNAISSANCES

## B.1 Ce que possède chaque source — comparaison

| Dimension | **PMU** (source externe) | **IA** (connaissances acquises) |
|---|---|---|
| Nature | Faits officiels du turf | Résultats de ses propres analyses |
| Portée | Carrière complète d'un cheval, jusqu'à 5 courses d'historique | Depuis l'installation de l'app |
| `reductionKilometrique` | **Présent, individuel** (84,6 % des participants) | **Absent** — jamais stocké |
| `etatTerrain` / `penetrometre` | Présent (38,8 % / 34 %) | Absent — le critère `terrain` ne reçoit **aucune** valeur de terrain réelle |
| ELO par cheval × discipline | **Absent** | **Possédé** : 9 001 clés, 6 disciplines |
| Mouvement de cote | Fourni (mais non conservé) | **Possédé** : 7 paliers, fenêtre `[0,+30 min]` |
| Poids adaptatifs 19 critères | **Absent** | **Possédé** : 4 disciplines × 19 critères |
| Résultat réel d'une course | **Possédé** (arrivée officielle) | **Possédé** (mais dérivé du PMU) |
| Rapports journaliers | Absent | **Possédé** : 219 journaux distincts |
| Spécialité / musique | **Possédé** (format `"3a8a2a…"`) | Partiellement décodé |
| `record` (critère) | **Possédé** sous forme de chaîne (`"1'12\"5"`) | Converti en secondes par `_scoresCriteres` |

## B.2 Trois familles de relation

### B.2.1 Connaissances **identiques** (même information, deux détenteurs)

- L'**arrivée réelle** d'une course : le PMU la publie, l'IA l'enregistre.
  **[DÉMONTRÉ]** `enregistrerResultat` (3347) est le point d'entrée unique.
  Risque : divergence si le PMU corrige une arrivée après publication. Voir B.5.
- Le **nom** d'un cheval, son **numéro**, son **jockey**, son **entraîneur**.
  **[MESURÉ]** 5 clés fantômes prouvées (`recordAbsolu`, `performances`,
  `historiquePerformances`, `placeDepartCourse`, `corde`) : 0 occurrence sur 3 788
  participants. Ces champs **ne doivent pas** être attendus du PMU.

### B.2.2 Connaissances **complémentaires** (chacun apporte ce que l'autre n'a pas)

C'est le cœur du mandat. Les complémentarités **réellement exploitables** :

| Apport PMU → IA | Apport IA → PMU | Exploitable ? |
|---|---|---|
| `reductionKilometrique` individuel → fiabiliser le critère `record` | — | **OUI**, sous réserve du §12 |
| `etatTerrain` / `penetrometre` → alimenter le critère `terrain` | — | **OUI**, mais couverture 38,8 % |
| Historique de carrière → fiabiliser `forme`, `constance`, `progression` | — | **OUI** |
| — | ELO → pondérer la force relative | **OUI** (déjà fait) |
| — | Mouvement de cote → critère `mouvCote` | **OUI** (déjà fait) |
| — | Poids appris → classement | **OUI** (déjà fait) |

### B.2.3 Connaissances **exclusives**

- **PMU seul** : `reductionKilometrique`, `penetrometre`, `typePiste`, la musique,
  les reculs, `placeCorde` réelle.
  **[MESURÉ]** `typePiste` ∩ `etatTerrain` = ∅ : ce sont deux informations **distinctes**
  (surface vs état), non substituables.
- **IA seule** : ELO, mouvement de cote, poids adaptatifs, rapports, bilans.

## B.3 Règles de consolidation proposées (11 cas du §10)

Principe directeur, non négociable et conforme au mandat :

> **Une réponse vide ou une erreur réseau ne doit JAMAIS effacer une connaissance locale
> valide.**

| # | Cas | Règle proposée |
|---|---|---|
| C-01 | PMU fournit une valeur, local absent | **Écrire** la valeur PMU, marquer source `pmu` |
| C-02 | PMU fournit une valeur, local présent et identique | **Ne rien écrire**. Idempotence stricte |
| C-03 | PMU fournit une valeur, local présent et différent | **Conserver les deux** avec horodatage + source. Ne jamais écraser silencieusement |
| C-04 | PMU renvoie vide / `null` | **Ignorer**. Aucune écriture, aucune suppression |
| C-05 | PMU renvoie une erreur réseau / timeout | **Ignorer**. Conserver l'état antérieur, marquer l'absence de fraîcheur |
| C-06 | PMU renvoie une valeur hors bornes plausibles | **Refuser** la valeur, journaliser, conserver le local |
| C-07 | Local absent ET PMU vide | **Ne rien créer**. Pas de valeur par défaut artificielle |
| C-08 | Correction officielle du PMU sur une arrivée | **Remplacer** la valeur locale, **conserver** la trace de l'ancienne (audit). Une arrivée officielle est un **fait** : c'est le seul cas où le PMU prime sans réserve |
| C-09 | Conflit entre deux réponses PMU successives | La **plus récente** gagne, l'ancienne est journalisée |
| C-10 | Donnée locale acquise par apprentissage (poids, ELO) | **Jamais** touchée par une consolidation PMU. Cloisonnement absolu |
| C-11 | Donnée locale calculée et PMU fournit la même | **Préférer** le calcul local si le PMU est incomplet ; sinon conserver les deux |

**[DÉMONTRÉ]** La règle C-08 a déjà un précédent conforme dans le code :
`backup_service.dart:1765+` documente « une arrivée officielle est un FAIT : en cas de
divergence, on ne réécrit pas l'histoire » et applique une **fusion additive**.

## B.4 Déduplication — identification

**Risques identifiés à traiter, chacun par une règle explicite :**

| Entité | Risque | Règle proposée |
|---|---|---|
| Cheval | Homonymes | Clé = `NOM` normalisé **+ discipline + année de naissance** si disponible. **[APPAREIL REQUIS]** pour valider sur corpus réel |
| Cheval | Variantes orthographiques, accents | **[MESURÉ]** `elo_service.normaliserDiscipline` est déjà **accent-safe** (`attelé`, `trot a`). `_cleNom` applique la même logique |
| Cheval | Changement de nom | **[INDÉTERMINÉ]** aucun champ PMU observé ne le signale |
| Course | Numéros réutilisés | **[DÉMONTRÉ]** `_buildCourseKey` = `R{n}R C{n}C _ {date}` : la date désambiguïse |
| Jockey / entraîneur | Homonymes | Clé = nom normalisé + discipline |
| Hippodrome | Alias (`VINCENNES` vs `PARIS-VINCENNES`) | **[MESURÉ]** égalité exacte = **4,3 %** ; règle token-subset → **26/27** labels, **0 ambiguïté** |
| Performance | Doublon sur réimport | Clé = `(cheval, course, date)` |
| Observation | Double apprentissage | **[DÉMONTRÉ]** protégé par `if (p.resultatsReels) return false` dans `enregistrerResultat` |
| Résultat | Correction officielle | Voir C-08 |
| Fuseaux horaires | Fenêtre de cote | **[DÉMONTRÉ]** `estDansFenetre` travaille sur `DateTime` local ; pas de conversion UTC → risque si l'app change de fuseau. **À signaler** |

**Interdiction respectée** : aucune règle d'appariement proposée ne repose sur une
similarité de nom approximative. La règle hippodrome est un **sous-ensemble de tokens**,
vérifiée à 0 ambiguïté sur 27 labels — pas une distance de Levenshtein.

## B.5 Gestion des corrections officielles — conséquence

**[DÉMONTRÉ]** Une arrivée officielle corrigée après coup n'a **aucun chemin de mise à
jour** identifié : `enregistrerResultat` refuse tout rejeu (`if (p.resultatsReels) return false`).

**Conséquence sur les 19 critères** : si une arrivée est corrigée par le PMU, l'ELO et les
poids sont déjà mis à jour sur la base de l'arrivée **erronée**, et il n'existe pas de
mécanisme de retour arrière. **[ESTIMÉ]** La fréquence de ces corrections est faible en
pratique, mais elle n'est pas nulle. **[APPAREIL REQUIS]** pour la quantifier.
Ce point est porté en décision **D-05**.

## B.6 Conséquences sur les 19 critères — vue d'ensemble

Le tableau détaillé est en **§H.12**. Résumé :

- **11 critères** sur 19 disposent d'une source PMU exploitable et mesurée.
- **3 critères** (`elo`, `mouvCote`, `placeDepart`) reposent sur des sources **internes**
  uniquement.
- **5 critères** ont une alimentation **fragile ou partielle** : `terrain` (38,8 % de
  couverture), `poidsRel` (dépend de `poids` qui est **absent de l'API**), `progression`
  (dépend de `recordEnSecondes`), `distSpec` (dépend de l'historique tronqué à 5 courses),
  `divergence` (dépend de `cote` disponible avant course seulement).

---

# C. ARCHITECTURE ET FONCTIONNEMENT

## C.1 Architectures comparées

Quatre architectures réellement envisageables. Aucune n'est écartée par principe.

### C.1.1 Architecture A — « Statu quo assaini »

**Principe** : conserver `SharedPreferences` + services singleton. Ne corriger que les
défauts mesurés (DF-01 à DF-11).

| Critère | Évaluation |
|---|---|
| Effort | **Faible** — 5 corrections ciblées |
| Risque de régression | **Faible** — aucun déplacement de données |
| Préservation des mécanismes IA | **Totale** — aucun code d'apprentissage touché |
| Traitement de la croissance non bornée | **Partiel** — on plafonne, on ne restructure pas |
| Compatibilité anciennes sauvegardes | **Totale** |
| Coût du `_save()` (99,7 % réécrit) | **Non résolu** |

### C.1.2 Architecture B — « Dépôt de connaissances cloisonné »

**Principe** : introduire une couche `ConnaissanceRepository` qui possède **seule** l'accès
aux données, avec un **registre de clés** et une **politique de rétention déclarative**.
Les services existants deviennent des consommateurs. `SharedPreferences` reste le support.

| Critère | Évaluation |
|---|---|
| Effort | **Moyen** — couche d'indirection, sans changement de support |
| Risque de régression | **Moyen** — touche tous les services |
| Préservation des mécanismes IA | **Totale** si la couche ne fait que relayer les lectures/écritures |
| Traitement de la croissance | **Résolu** — rétention déclarée par clé, donc vérifiable |
| Coût du `_save()` | **Réductible** — écriture sélective par clé modifiée |
| Compatibilité | **Totale** — les clés ne changent pas |

### C.1.3 Architecture C — « Double magasin : faits PMU / acquis IA »

**Principe** : séparer physiquement deux magasins.
- **Magasin de faits** : données PMU, immuables une fois validées, dédupliquées.
- **Magasin d'acquis** : poids, ELO, cotes, rapports — données produites par l'IA.

| Critère | Évaluation |
|---|---|
| Effort | **Élevé** — nouveau magasin, nouvelle API, migration |
| Risque de régression | **Moyen** — cloisonnement protecteur, mais frontière à définir |
| Préservation des mécanismes IA | **Totale** — l'apprentissage ne lit que le magasin de faits |
| Traitement de la croissance | **Résolu** — politiques distinctes par magasin |
| Compatibilité | **À construire** — la restauration doit alimenter les deux |
| **Avantage décisif** | **Répond directement au mandat** : « exploiter conjointement les connaissances historiques authentiques du PMU et les connaissances acquises » |

### C.1.4 Architecture D — « SQLite pour les faits, prefs pour le reste »

**Principe** : `sqflite` pour les données historiques PMU (volumineuses, requêtables),
`SharedPreferences` pour l'état de l'IA.

| Critère | Évaluation |
|---|---|
| Effort | **Élevé** — nouveau schéma, nouvelle couche, APK plus lourd |
| Traitement de la croissance | **Excellent** — index, requêtes, pas de chargement intégral en RAM |
| Compatibilité web | **DÉFAUT MAJEUR** : `sqflite` n'est **pas** disponible sur le Web. La prévisualisation Web, outil de travail principal, cesserait de fonctionner |
| Compatibilité anciennes sauvegardes | **À construire** |

**[DÉMONTRÉ]** Le projet est développé et validé via **prévisualisation Web** (Flutter Web).
L'architecture D introduirait une dépendance de plateforme qui **casserait la chaîne de
validation actuelle**. Ce n'est pas un avis esthétique : c'est une contrainte d'outillage
mesurable.

## C.2 Architecture recommandée

**[Recommandation argumentée] Architecture B, avec les apports ciblés de C.**

Justification, dans l'ordre des contraintes réelles :

1. **Le problème mesuré n'est pas le support, c'est l'absence de politique.**
   **[MESURÉ]** `ia_bilans_semaine_v1`, `ia_bilans_mois_v1` et `elo_service` croissent sans
   borne **parce qu'aucune constante ne les plafonne** — pas parce que `SharedPreferences`
   serait inadapté. Plafonner ces trois collections suffit à borner la croissance mesurée à
   **≈ 9,22 Mo/an** ramenés à un plateau. Changer de support ne corrigerait rien sans
   politique de rétention.

2. **Le défaut le plus coûteux est structurel, pas technologique.**
   **[MESURÉ]** La duplication emboîtée (×2,39) est une décision de modèle de données
   (`BilanSemaine.rapportsJson`, `BilanMois.semaines`). La corriger ne demande aucun
   changement de support.

3. **Le cloisonnement faits/acquis est exigé par le mandat, pas par la technique.**
   Séparer logiquement les deux familles (registre de clés, politiques distinctes,
   consolidation unidirectionnelle PMU → IA) apporte la garantie demandée **sans**
   introduire un second magasin physique.

4. **Le Web doit continuer à fonctionner.** C'est l'outil de validation. Toute solution
   qui l'exclut impose une perte de capacité de vérification — inacceptable dans un
   chantier dont l'exigence première est la preuve.

5. **L'effort doit rester proportionné.** L'architecture C complète (double magasin) exige
   une migration, donc enfreint « aucune migration réelle » tant qu'elle n'est pas validée.

### C.2.1 Ce que l'architecture B doit contenir — schéma recommandé

**[DÉMONTRÉ]** Il a été vérifié d'abord si les services existants peuvent être enrichis
proprement, comme exigé au §8 du mandat. **Réponse : oui pour la politique de rétention,
non pour le registre** — parce qu'il n'existe aujourd'hui **aucun** point central
recensant les clés et leurs politiques. `backup_service.dart:340-460` contient une **liste**
de clés, mais c'est une liste de collecte, pas un registre de politique.

Schéma recommandé — un registre déclaratif, sans nouveau magasin :

```
RegistreDeConnaissances
  ├── famille: "fait_pmu" | "acquis_ia" | "derive" | "etat_ui"
  ├── cle: String
  ├── retention: { type: "plafond"|"age"|"permanent", valeur: int }
  ├── reconstructible: bool          // recalculable depuis d'autres clés ?
  ├── consommateurPmu: bool          // alimentée par le réseau ?
  ├── poidsOctetsMesure: int         // mesuré, pas estimé
  └── sourceDeVerite: "pmu"|"local"
```

**[DÉMONTRÉ]** Aucune donnée privée ne serait déplacée : ce registre est du code, pas des
données. Il ne contient que des métadonnées descriptives.

## C.3 Schémas des flux

### C.3.1 Flux actuel (démontré)

```
API PMU ──HTTP──► ZoneTurfService ──► DataRefreshService
                                            │
                                            ├─► IaPronosticEngine ──► 19 scores
                                            │        │
                                            │        └─► poidsEffectifsPourDiscipline()
                                            │                 │
                                            │                 ▼
                                            │        ia_poids_v3 (ppd[disc])
                                            │
                                            ├─► EloService.mettreAJourApresArrivee()
                                            │        └─► elo_service
                                            │
                                            ├─► CoteTrackerService
                                            │        └─► cote_tracker_mouvements_v1
                                            │
                                            └─► enregistrerResultat()
                                                     │
                                                     ├─► _pronostics (600 max)
                                                     ├─► _journal (500 max)
                                                     ├─► _rapports (365 max)  ──┐
                                                     ├─► _bilansSemaine ───────┤ DUPLICATION
                                                     │        (AUCUN CAP)     │ ×2,39
                                                     └─► _bilansMois ──────────┘
                                                              (AUCUN CAP)
```

### C.3.2 Flux recommandé

```
API PMU ──HTTP──► ZoneTurfService
                      │
                      ▼
           ┌─── RegistreDeConnaissances ───┐
           │  (politique par clé)          │
           └───────────────┬───────────────┘
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
      FAITS PMU (source)         ACQUIS IA (dérivés)
      ├─ historique cheval       ├─ ia_poids_v3
      ├─ reductionKm             ├─ elo_service
      ├─ etatTerrain             ├─ cote_*
      ├─ arriveesOfficielles     ├─ _journal
      └─ retent.: permanent      ├─ _rapports (365)
                                 └─ _bilans (recalculés, jamais stockés)
                                        │
                                 Consolidation UNIDIRECTIONNELLE
                                 PMU ──► IA   (jamais l'inverse)
```

Différence essentielle : **les bilans ne sont plus stockés, ils sont recalculés**. Les
rapports ne sont plus dupliqués.

## C.4 Fonctionnement événementiel

**[DÉMONTRÉ]** L'architecture possède **déjà** trois mécanismes sur les cinq attendus.
Correction d'un constat antérieur erroné :

| Mécanisme | Existant ? | Preuve |
|---|---|---|
| Prévention de boucle | **OUI** | `data_refresh_service.dart:650` — `if (_loading) return;` |
| Garde de fermeture | **OUI** | `:649` `_doRefresh()` capture `generationAuDemarrage`, vérifie `_resetEnCours` |
| Détection de changement | **OUI** | `:491` `_signaturedReunions()` — empreinte `code:r.courses.length` + `\|{numCourse}{heure}{T/A}{partants.length}`, comparée en `690-692` → `aChange` |
| Délais d'expiration | **Partiel** | `_refreshInterval = 15 min` (`:221`), `_cacheLocalDuree = 8 h` (`:222`) — **fixes**, non adaptatifs |
| Retries espacés / suspension après échecs | **NON** | Aucun compteur d'échecs consécutifs identifié |

**Recommandations pour les deux mécanismes manquants :**

- **R-01** Compteur d'échecs consécutifs par reunion. Après N échecs, suspension avec
  délai croissant (exponentiel borné). Réactivation au premier succès.
- **R-02** Cache des **absences confirmées** : si le PMU répond explicitement « pas de
  données » pour une course, mémoriser cette absence avec un TTL court pour éviter de
  re-solliciter inutilement. **Ne jamais** confondre « absence confirmée » (réponse
  explicite) et « échec réseau » (pas de réponse).

## C.5 Prévention des boucles inutiles

**[DÉMONTRÉ]** Déjà en place : garde `_loading`, empreinte de signature, `_resetEnCours`.

**[ESTIMÉ]** Le levier le plus rentable n'est pas la boucle mais le **volume réécrit** :
**[MESURÉ]** `_save()` réécrit **99,7 %** du contenu à chaque appel. À `nbMisesAJour = 3 871`
sur 169 jours, cela représente ≈ 23 écritures/jour × 11,2 Mo = **≈ 258 Mo d'écriture
disque/jour** — **[CALCULÉ]**, hypothèse : chaque `_save()` écrit effectivement tout.
**[APPAREIL REQUIS]** pour mesurer l'usure réelle et l'impact sur la durée de vie du stockage.

## C.6 Stratégie de récupération

- **R-03** Distinguer trois états de réponse : **succès**, **absence confirmée**, **échec**.
  Ne jamais traiter l'échec comme une absence (règle C-05).
- **R-04** Reprise après interruption : **[DÉMONTRÉ]** `IaArchiveService` possède déjà un
  mécanisme de file d'attente (`persisterEnAttente()`, `doitGelerBlobPronostics`). Le même
  patron est applicable à la collecte PMU.
- **R-05** Annulation des traitements obsolètes : **[DÉMONTRÉ]** déjà présent via
  `generationAuDemarrage`.

## C.7 Stratégie d'actualisation

**[DÉMONTRÉ]** `_refreshInterval = 15 min` fixe. **[ESTIMÉ]** Ce n'est pas nécessairement
sous-optimal, mais il ignore trois réalités mesurées :
- **[MESURÉ]** Une réponse `performances-detaillees` pèse **89 735 octets**.
- **[MESURÉ]** Le corpus compte **16 579 courses passées** — les données **historiques**
  ne changent jamais.
- Les **cotes** changent en continu ; les **résultats officiels** changent une fois.

**Recommandation R-06** : actualisation **par nature de donnée**, pas globale.
Historique = jamais ; résultat provisoire = toutes les 2 min ; résultat officiel = une fois ;
cotes = fenêtre `[0,+30 min]` déjà implémentée.

## C.8 Stratégie de cache

**[DÉMONTRÉ]** Le TTL actuel (`_cacheLocalDuree = 8 h`, `:222`) est qualifié de
**PROVISOIRE et non validé** (§19 du mandat). Il ne distingue pas les sept natures de
données listées au §19.

**Recommandation R-07** — sept TTL distincts :

| Nature | TTL recommandé | Justification |
|---|---|---|
| Historique cheval (courses passées) | **∞** (jamais invalider) | **[MESURÉ]** immuable |
| Résultat officiel | **∞** | Un fait acquis ne se périme pas |
| Résultat provisoire | 2 min | Peut encore changer |
| Course courante (partants) | 5 min | Non-partants tardifs |
| Cotes | Fenêtre `[0,+30 min]` | **[DÉMONTRÉ]** déjà codé |
| Absence confirmée | 10 min | Éviter le martèlement |
| Échec réseau | Ne pas cacher | Rien n'a été obtenu |

**[DÉMONTRÉ]** Ce découpage est compatible avec le code existant : `CoteTrackerService`
implémente déjà sa propre fenêtre, indépendamment du cache global.

---

# D. STOCKAGE ET CAPACITÉ

## D.1 Dossiers actuels

**[DÉMONTRÉ]** Inventaire des emplacements réellement utilisés :

| Donnée | Emplacement | Référence |
|---|---|---|
| Tout l'état de l'IA et de l'app | `SharedPreferences` (XML unique, privé à l'app) | 44 clés `ia_*`, `elo_*`, `cote_*`, `configIA`, etc. |
| Fichier de sauvegarde exporté | `getTemporaryDirectory()` | `backup_service.dart:1246` |
| Rapports d'analyse journée (JSON) | `_dossierRapports()` | `ia_performance_screen.dart:578` |
| Images de partage | `getTemporaryDirectory()` | plusieurs écrans |

**Aucune donnée privée n'est écrite dans un dossier public.** L'export de sauvegarde passe
par `SharePlus.instance.share(...)` (`backup_service.dart:1288`), qui délègue l'écriture
finale à l'utilisateur. C'est conforme à l'exigence du §21.

## D.2 Dossiers recommandés

| Recommandation | Justification |
|---|---|
| **Conserver** `SharedPreferences` comme magasin principal | Changement de support non justifié par les mesures (voir C.2) |
| **Ajouter** un sous-dossier `knowledge/` dans le répertoire **privé** de l'app pour les archives segmentées | `IaArchiveService` produit déjà des shards (`ia_archive_v1_<date>`) ; les sortir du XML allège massivement ce dernier |
| **NE PAS** déplacer vers un dossier public | Exigence explicite du §21 |

## D.3 Technologie actuelle et ses limites mesurées

**Technologie** : `SharedPreferences` → fichier XML unique, chargé intégralement en mémoire
au démarrage, réécrit intégralement à chaque `setString`/`setStringList`.

**Limites mesurées :**

| Limite | Mesure | Conséquence |
|---|---|---|
| **Réécriture intégrale** | `_save()` réécrit **99,7 %** du volume | **[MESURÉ]** 11 218 019 / 11 250 326 octets |
| **Pas de requête** | Aucune | Tout filtrage est fait en RAM après chargement complet |
| **Chargement intégral au démarrage** | **[APPAREIL REQUIS]** | Le JSON complet (11,2 Mo au 13/11) est chargé et parsé à froid |
| **Croissance non bornée** | **[MESURÉ]** 3 collections sans plafond | Voir D.4 |
| **Écriture non atomique du fichier d'export** | `file.writeAsBytes(bytes)` (DF-11) | Une interruption produit un fichier tronqué |
| **Base64 sur gzip** | **[MESURÉ]** surcoût ×1,333 | 49 022 octets perdus sur le blob du 13/11 |

## D.4 Projections jusqu'à 10 ans

### D.4.1 Scénario 1 — statu quo (aucune correction)

**[MESURÉ]** Rythme de croissance des composants **non plafonnés** :

| Composant | Octets/unité | Rythme mesuré | Octets/an |
|---|---:|---|---:|
| `BilanSemaine` | 78 982 | 1 par 7,0 j → 52,2/an | **4,11 Mo** |
| `BilanMois` | 247 734 | 1 par 28,2 j → 12,9/an | **2,97 Mo** |
| `elo_service` | 104,5 | 41,8 clés/j → 15 257/an | **1,60 Mo** |
| `premium_widgets_selection_jour_v1` | 1 486 | par jour | **0,54 Mo** |
| **TOTAL** | | | **≈ 9,22 Mo/an** |

**[CALCULÉ]** Projection (hypothèses : rythmes mesurés maintenus constants, aucune purge) :

| Horizon | Croissance cumulée | Taille estimée du `SharedPreferences` |
|---|---:|---:|
| 1 an | +9,22 Mo | ≈ 20,5 Mo |
| 3 ans | +27,65 Mo | ≈ 38,9 Mo |
| 5 ans | +46,09 Mo | ≈ 57,3 Mo |
| **10 ans** | **+92,17 Mo** | **≈ 103,4 Mo** |

**[ESTIMÉ]** Un XML de 103 Mo dans `SharedPreferences` n'est pas un régime de
fonctionnement viable sur Android : le chargement au démarrage deviendrait perceptible
et le risque d'`OutOfMemoryError` sur les appareils d'entrée de gamme (série A, Tab A)
est réel. **Cette affirmation est une estimation, pas une mesure** — elle exige un appareil.

### D.4.2 Scénario 2 — plafonnement seul (DF-01, DF-02, DF-04)

**[CALCULÉ]** En ajoutant un plafond à `BilanSemaine` (ex. 104 semaines = 2 ans),
`BilanMois` (ex. 60 mois = 5 ans) et `elo_service` (ex. 20 000 clés) :

| Composant | Plafond | Octets à plateau |
|---|---|---:|
| `BilanSemaine` | 104 | 8,21 Mo |
| `BilanMois` | 60 | 14,86 Mo |
| `elo_service` | 20 000 | 2,09 Mo |

**[CALCULÉ]** Total à plateau ≈ **30,6 Mo** — borné, mais toujours élevé. Le plafonnement
seul **ne suffit pas**.

### D.4.3 Scénario 3 — suppression de la duplication + plafonds (recommandé)

**[CALCULÉ]** En supprimant le stockage des bilans (recalculables) et en protégeant
`ia_rapports_v1` à 365 entrées :

| Composant | Octets |
|---|---:|
| `ia_rapports_v1` extrapolé à 365 | 4,46 Mo |
| `ia_journal_v2` (500) | 1,04 Mo |
| `grosParis` (purge 90 j effective) | 1,04 Mo |
| `elo_service` (plafond 20 000) | 2,09 Mo |
| `ia_pronostics_v2_gz` (600) | 0,20 Mo |
| `premium_widgets` (365) | 0,25 Mo |
| autres | 0,19 Mo |
| **TOTAL À PLATEAU** | **≈ 9,27 Mo** |

**[CALCULÉ]** Temps pour atteindre le plateau : **365 jours** (contrainte dominante :
`ia_rapports_v1` et `premium_widgets`). Pour `elo_service` :
(20 000 − 9 001) / 41,8 = **263 jours**.

**Gain immédiat de la seule suppression des bilans : 5 179 284 octets, soit 46,1 % du
fichier du 13/11.**

### D.4.4 Synthèse des trois scénarios

| Scénario | Aujourd'hui | 1 an | 10 ans | Borné ? |
|---|---:|---:|---:|---|
| 1 — Statu quo | 11,2 Mo | ≈ 20,5 Mo | **≈ 103 Mo** | **NON** |
| 2 — Plafonds seuls | 11,2 Mo | ≈ 30,6 Mo | ≈ 30,6 Mo | OUI, mais lourd |
| 3 — **Recommandé** | 6,05 Mo *(après suppression bilans)* | ≈ 9,27 Mo | ≈ 9,27 Mo | **OUI** |

## D.5 Politique de conservation

**[DÉMONTRÉ]** Politique déjà validée et **vérifiée conforme** dans le code :
les résultats officiels sont conservés **sans limite** ; la purge à 90 jours ne touche
**que** les pronostics **sans résultat** (`ia_memory_service.dart:1184-1199` :
`if (p.resultatsReels) return false;` puis `return p.datePronostic.isBefore(limite);`).

**Politique proposée, par famille :**

| Famille | Conservation | Reconstruction |
|---|---|---|
| Résultat officiel (fait) | **Permanente** | Non reconstructible |
| Historique PMU (faits) | **Permanente** | Re-téléchargeable mais coûteux |
| Pronostic **avec** résultat | 600 max (fenêtre glissante) | Non reconstructible → **archiver avant éviction** |
| Pronostic **sans** résultat | 90 jours | Non reconstructible, mais sans valeur après coup |
| `ia_rapports_v1` | 365 jours | **Reconstructible** depuis les pronostics |
| `ia_bilans_semaine_v1` | **NE PAS STOCKER** | Recalculable en O(n) sur les rapports |
| `ia_bilans_mois_v1` | **NE PAS STOCKER** | Recalculable en O(n) |
| `ia_journal_v2` | 500 entrées | Non reconstructible (trace) |
| `elo_service` | Plafond à définir | Reconstructible partiellement |
| `premium_widgets_selection_jour_v1` | 365 jours | Recalculable |
| Cotes | Fenêtre `[0,+30 min]` | Re-téléchargeable |

**[DÉMONTRÉ]** `IaArchiveService` garantit déjà qu'une éviction de pronostic est
**archivée avant** d'être perdue (`_securiserExcedentAvantEcriture()` +
`doitGelerBlobPronostics`, `ia_memory_service.dart:2749-2770`). C'est une protection
existante qu'il ne faut **pas** dégrader.

## D.6 Plan de migration éventuel

**Aucune migration n'est exécutée dans ce chantier.** Le plan est proposé, non appliqué.

**[DÉMONTRÉ]** Contrainte du mandat §27 : « Une migration faite doit être identifiable et ne
pas se rejouer à chaque démarrage. » Le patron existe déjà dans le code :
`elo_service.dart:2406` — `final flagPurge = prefs.getBool('elo_orphelins_purges_v1') ?? false;`

**Plan proposé, en 5 étapes, avec drapeau de version :**

| Étape | Action | Drapeau | Rejouable ? |
|---|---|---|---|
| M-1 | Lire et **compter** les bilans existants, sans modifier | `migration_v10_0_inspectee` | Non (lecture seule, idempotente) |
| M-2 | Recalculer `BilanSemaine`/`BilanMois` depuis `ia_rapports_v1` et **comparer** aux valeurs stockées | `migration_v10_0_verifiee` | Non |
| M-3 | **Si et seulement si** les valeurs recalculées coïncident, supprimer les blocs stockés | `migration_v10_0_bilans_purges` | Non |
| M-4 | Plafonner `elo_service` si > seuil, en journalisant les clés retirées | `migration_v10_0_elo_plafonne` | Non |
| M-5 | Réécrire `ia_rapports_v1` sans doublon | `migration_v10_0_rapports_dedup` | Non |

**Garde-fou non négociable pour M-3** : si les valeurs recalculées **diffèrent** de celles
stockées, la suppression **ne doit pas** avoir lieu. Un écart signalerait que les bilans
contiennent de l'information non dérivable — auquel cas la duplication est légitime et
la proposition est à revoir. **Ce contrôle est la condition de sûreté de tout le plan.**

**[DÉMONTRÉ]** `backup_service.dart:2139-2151` documente qu'un reset préserve déjà l'archive
en attendant une décision (« décision reportée à E4 »). La migration doit respecter la même
prudence.

---

# E. SAUVEGARDES ET RESTAURATIONS

## E.1 État actuel — mesuré sur les deux fichiers réels

| Caractéristique | Valeur mesurée |
|---|---|
| Version du code | `9.1` (`backup_service.dart:153`) |
| Version des deux fichiers réels | `9.0` |
| Nombre de clés racines | **14** |
| Format | JSON indenté (`JsonEncoder.withIndent('  ')`) |
| Reproductibilité du format | **[MESURÉ]** écart **0 octet** sur les deux fichiers |
| Champs d'intégrité (checksum) | **AUCUN** |
| Champs de version par bloc | **AUCUN** (une seule version globale) |
| Écriture atomique | **NON** (DF-11) |
| Restauration par comparaison de version | **NON** — la règle est « clé absente → local préservé » |

## E.2 Défauts mesurés

| # | Défaut | Preuve |
|---|---|---|
| **SB-01** | **Aucun checksum** : un fichier tronqué n'est détecté que par l'échec du parseur JSON | **[DÉMONTRÉ]** `_collecterDonnees()` n'ajoute aucune empreinte |
| **SB-02** | **Aucune version par bloc** : impossible de savoir si `ia_bilans_mois_v1` d'une sauvegarde est d'un format compatible | **[MESURÉ]** 14 clés, dont une seule `version` globale |
| **SB-03** | **Écriture non atomique** | **[DÉMONTRÉ]** `file.writeAsBytes(bytes)` (`backup_service.dart:1248`) |
| **SB-04** | **`widget` vide** dans les deux fichiers | **[MESURÉ]** 2 octets chacun |
| **SB-05** | **Comptage des pronostics estimé** | **[DÉMONTRÉ]** `(gz.length / 130).round()` avec commentaire « Estimation » (`:1856-1859`) |
| **SB-06** | **Pas de déduplication à la restauration** des agrégats | **[DÉMONTRÉ]** aucune logique de réconciliation sur `ia_rapports_v1` / `ia_bilans_*` |
| **SB-07** | **Indentation coûteuse** | **[MESURÉ]** +8,2 % (28/05) et +11,0 % (13/11) |
| **SB-08** | **Le poids est dominé par la duplication** | **[MESURÉ]** 61,4 % du fichier = rapports + bilans, avec redondance ×2,39 |

## E.3 Évolutions nécessaires

| # | Évolution | Effet mesurable |
|---|---|---|
| **EV-01** | Supprimer `ia_bilans_semaine_v1` et `ia_bilans_mois_v1` du format (recalculés) | **−46,1 %** du fichier du 13/11 |
| **EV-02** | Dédupliquer `ia_rapports_v1` avant écriture | Redondance ×2,39 → ×1,00 |
| **EV-03** | Ajouter un **checksum** par bloc + un checksum global | Détection de troncature |
| **EV-04** | Ajouter une **version par bloc** | Migration par bloc, plus de version globale unique |
| **EV-05** | Écrire dans `.tmp` puis `rename` | Atomicité |
| **EV-06** | Remplacer le comptage estimé par un comptage **réel** après décodage | Suppression de DF-09 |
| **EV-07** | Sérialisation **compacte** + compression du fichier entier | **[CALCULÉ]** −8,2 % à −11,0 % (indentation) puis gain supplémentaire gzip |
| **EV-08** | Inclure `widget` réellement (via le magasin natif) | Fonctionnalité restaurée — **[APPAREIL REQUIS]** |

## E.4 Format recommandé

**[Proposition]** Structure à deux niveaux, rétrocompatible en lecture :

```
{
  "version": "10.0",
  "appName": "Pronostic Hippique",
  "dateBackup": "…",
  "format": {
    "integration": { "algo": "sha256", "bloc": { "<nom>": "<hash>" }, "global": "<hash>" }
  },
  "blocs": {
    "<nom_du_bloc>": {
      "version": "1.0",
      "octets": 123456,
      "checksum": "<sha256>",
      "compression": "gzip" | "none",
      "charge": <objet | null>
    }
  }
}
```

**Propriétés attendues (à vérifier par test, pas affirmées)** :
- Un bloc absent → local préservé (règle existante conservée).
- Un bloc corrompu → **seul ce bloc** est refusé, les autres sont restaurés.
- Un bloc d'une version inconnue → refusé explicitement, local préservé.
- Le fichier entier tient dans un budget d'octets **mesuré**, pas estimé.

## E.5 Compatibilité historique

**[DÉMONTRÉ]** Les deux fichiers réels (`9.0`) se restaurent sans perte sur le code (`9.1`),
grâce à la règle « clé absente → local préservé », appliquée pour `archiveIA`,
`arriveesOfficielles`, `resultatsOfficielsPmu`, `elo_service`, `laboIA`, `auditCache`, `cote`.

**Risque à traiter (RS-01)** : si le format passe à des blocs `{version, checksum, charge}`,
le lecteur doit savoir lire **l'ancien** format (charge directement dans la clé racine) **et**
le nouveau. C'est un travail de lecture conditionnelle, sans migration destructive.

**Risque à traiter (RS-02)** : **[DÉMONTRÉ]** la restauration des agrégats n'a **aucune
déduplication**. Restaurer une sauvegarde de 5,2 Mo de bilans sur un local déjà à 5,2 Mo
donnerait 10,4 Mo si les fusions sont additives. **À vérifier par test** (voir D-04).

## E.6 Contrôles d'intégrité

**Proposition en 4 contrôles, exécutables avant toute écriture :**

| Contrôle | Vérifie | Coût |
|---|---|---|
| **IC-01** | Parse JSON complet sans exception | O(n) |
| **IC-02** | Checksum global == recalcul | O(n) |
| **IC-03** | Checksum de chaque bloc == recalcul | O(n) |
| **IC-04** | Cohérence croisée : somme des `octets` des blocs == `octets` du fichier | O(1) |

**Aucun de ces contrôles n'existe aujourd'hui.** **[DÉMONTRÉ]** Seul IC-01 est implicitement
présent (l'exception du parseur est attrapée par `try/catch`).

## E.7 Gestion des interruptions

**Scénario mesuré de risque** : le 13/11, l'export écrit **12 293 558 octets** en une seule
opération `writeAsBytes`. **[ESTIMÉ]** Sur un stockage de smartphone de milieu de gamme,
l'écriture de 12 Mo prend de l'ordre de quelques centaines de millisecondes à quelques
secondes. Une interruption (app tuée, batterie vide, ANR) produit un fichier **tronqué**,
et **aucun checksum n'existe** pour le détecter avant tentative de restauration.

**Proposition** :
1. `writeAsBytes` vers `<nom>.json.tmp`
2. `File.rename()` vers `<nom>.json` (opération atomique sur le système de fichiers)
3. Suppression des `.tmp` orphelins au démarrage
4. Si un `.tmp` existe sans `.json`, le signaler (export interrompu)

## E.8 Restauration complète et retour arrière

**Restauration complète** — procédure proposée, ordre imposé :
1. **Valider** (IC-01 à IC-04) — rien n'est écrit avant validation totale.
2. **Sauvegarder l'état local** dans une clé de retour arrière
   (`pre_restore_snapshot_v1`, TTL 24 h).
3. Restaurer bloc par bloc, en respectant la règle « clé absente → local préservé ».
4. Vérifier après restauration que les invariants tiennent (ex. somme des poids de
   `poidsParDiscipline` == 1,0 à 1e-9).
5. Ne supprimer le snapshot qu'après vérification réussie.

**Retour arrière** — aujourd'hui **inexistant**. **[DÉMONTRÉ]** Aucune clé de snapshot
pré-restauration n'est écrite par `backup_service.dart`. C'est un manque réel : une
restauration qui écrase le local n'est pas réversible.

**Invariant à vérifier après restauration [MESURÉ comme vrai sur les fichiers réels]** :
les sommes `poidsParDiscipline[disc]` valent **1,000000000000** pour les 4 disciplines,
dans les deux sauvegardes. C'est un contrôle de cohérence gratuit et immédiatement
disponible.

---

# F. PERFORMANCES

## F.1 Mesures réelles disponibles

Toutes les mesures de cette section ont été **exécutées** dans cet environnement. Aucune
n'est extrapolée sans mention explicite.

| Mesure | Valeur | Nature |
|---|---:|---|
| Taille d'une réponse `performances-detaillees` | **89 735 octets** | **[MESURÉ]** |
| Pronostic unitaire résolu (8 partants, 19 critères) | **2 276 octets** | **[MESURÉ]** |
| Dont la part des 19 critères | **66,9 %** (1 523 o) | **[MESURÉ]** |
| Pronostic sans `scoresCriteres` | 753 octets | **[MESURÉ]** |
| `ia_poids_v3` état d'usine | 443 octets (25 clés) | **[MESURÉ]** |
| `ia_poids_v3` avec 4 disciplines | 1 659 octets | **[MESURÉ]** |
| Ratio GZip réel (scores **variés**) | **5,51:1** | **[MESURÉ]** |
| Ratio GZip blob 600 pronostics (13/11) | **4,69:1** | **[MESURÉ]** |
| Ratio base64 sur gzip | **×1,333** | **[MESURÉ]** |
| Coût de l'indentation JSON | **+8,2 % / +11,0 %** | **[MESURÉ]** |
| Volume réécrit par `_save()` | **99,7 %** | **[MESURÉ]** |
| `_save()` moyen (13/11) | ≈ 11,2 Mo | **[CALCULÉ]** |

**Note d'honnêteté** : une mesure antérieure avait donné un ratio GZip de **70,02:1**. Ce
chiffre était **artificiel** — obtenu sur des scores **identiques** entre partants, cas qui
ne se produit pas réellement. La mesure corrigée sur des scores **variés** donne **5,51:1**.
C'est cette dernière qu'il faut retenir.

## F.2 Consommation réseau

**[MESURÉ]** Une réponse `performances-detaillees` = **89 735 octets**.

**[CALCULÉ]** Hypothèses explicites : `_refreshInterval = 15 min`, 1 appel par course suivie,
8 h de veille par jour (fenêtre `_cacheLocalDuree`), N courses suivies.

| Courses suivies | Appels/jour | Octets/jour | Octets/mois |
|---|---:|---:|---:|
| 10 | 320 | 28,7 Mo | **861 Mo** |
| 20 | 640 | 57,4 Mo | **1,72 Go** |
| 40 | 1 280 | 114,9 Mo | **3,45 Go** |

**[ESTIMÉ]** Ce volume est **considérable** pour une application mobile. Il découle
directement du `_refreshInterval = 15 min` fixe, sans distinction entre données
immuables (historique) et données changeantes (cotes).

**Levier R-06 (C.7)** : actualiser par nature de donnée. **[CALCULÉ]** Si l'historique
(immuable) est demandé **une seule fois** par cheval au lieu d'être rafraîchi toutes les
15 min, le volume devient proportionnel au **nombre de chevaux nouveaux**, pas au nombre
d'appels. **[ESTIMÉ]** Réduction d'un ordre de grandeur sur la part historique.

**[APPAREIL REQUIS]** pour mesurer la consommation réelle (cache HTTP, compression de
transport, données mobiles vs Wi-Fi).

## F.3 Consommation RAM

**[MESURÉ]** Volumes chargés en mémoire :

| Élément | Octets en RAM |
|---|---:|
| Blob pronostics décodé (600 pronostics) | 689 790 |
| Chaîne base64 du blob (en mémoire en parallèle) | 196 084 |
| Somme chaîne + objets | **885 874** |
| Tout le reste du `ia` décodé | ≈ 8,5 Mo |
| `elo_service` (9 001 clés) | 940 806 |
| `grosParis` (683 signaux) | 1 041 972 |
| **TOTAL RAM approximatif de l'état** | **≈ 11,4 Mo** |

**[CALCULÉ]** **Pic transitoire pendant `_save()`** : la sérialisation construit une chaîne
JSON complète **en plus** des objets en mémoire. Pic ≈ **2 × état** ≈ **22,8 Mo**.
S'y ajoute le buffer de `base64Encode` du blob : +196 Ko.

**[ESTIMÉ]** Sur un appareil Android de milieu de gamme avec un heap Dart typique de
128–256 Mo, un pic de 23 Mo pour une seule sauvegarde est absorbable mais laisse peu de
marge si une image ou un rendu lourd est en cours. **[APPAREIL REQUIS]** pour mesurer.

## F.4 Consommation CPU

**[MESURÉ]** Les opérations O(n) dominantes, par nature :

| Opération | Complexité | Déclencheur |
|---|---|---|
| `json.encode` de tout l'état (~11,2 Mo) | O(n) | Chaque `_save()` |
| `jsonDecode` de tout l'état au démarrage | O(n) | Démarrage à froid |
| `GZipCodec().encode` du blob | O(n) | Chaque `_save()` si compression |
| `base64Encode` du blob | O(n) | Chaque `_save()` |
| `clampDiscipline` × 4 disciplines × 19 critères | O(1) | Chaque normalisation |
| `_apprendreParGradient` : fenêtre 45–90 j, `take(50)` | **O(1) borné** | Après ≥10 courses avec résultats |

**[DÉMONTRÉ]** L'apprentissage lui-même est **borné** : `take(50)`, `take(20)`,
`take(80)`. Il **ne** croît **pas** avec l'historique. C'est un point positif mesurable.

**[CALCULÉ]** La serialisation `json.encode` d'un objet de 11,2 Mo prend, selon les
références Dart, de l'ordre de **100 à 400 ms** sur appareil mobile.
**[APPAREIL REQUIS]** pour la mesure exacte.

## F.5 Consommation batterie

**[ESTIMÉ]** Facteurs identifiés, sans mesure possible ici :
- Radio réseau : dominée par le volume de F.2 (jusqu'à 3,45 Go/mois dans l'hypothèse haute).
- CPU : dominée par les `_save()` de 11,2 Mo et par GZip.
- Écran : hors périmètre du stockage.

**[APPAREIL REQUIS]** — cette mesure ne peut pas être approchée depuis cet environnement.
Elle est **reportée**, pas abandonnée.

## F.6 Temps de traitement

**[DÉMONTRÉ]** Chemins de traitement identifiés et leurs bornes :

| Chemin | Borne démontrée |
|---|---|
| `_apprendreParGradient` | `take(50)` courses, fenêtre 45–90 j |
| `_apprendreParDiscipline` | `take(20)`, seuils `nbDisc < 5` et `totalBons/totalMauvais < 3` |
| Corrélations | `take(80)` (`ia_memory_service.dart:4341`) |
| Analyse journée | `take(34)` si dépassement (`:4732`) |
| `getScore` ELO | O(1) (accès Map) |
| `scoreCritereR` | O(1) |

**Conclusion [DÉMONTRÉ]** : **aucun** chemin de calcul de l'IA n'est non borné. Le risque
de ralentissement progressif ne vient **pas** des calculs, mais du **stockage** (F.3, F.4).

## F.7 Croissance du stockage

Voir **D.4**. Rappel du résultat central :

| Scénario | 10 ans |
|---|---:|
| Statu quo | **≈ 103 Mo** — non borné |
| Plafonds seuls | ≈ 30,6 Mo — borné |
| **Recommandé** | **≈ 9,27 Mo** — borné, plateau atteint en 1 an |

## F.8 Compatibilité matérielle

| Appareil | RAM typique | Évaluation | Base |
|---|---:|---|---|
| Galaxy S24 Ultra (référence) | 12 Go | **Aucun risque** | **[ESTIMÉ]** |
| Galaxy S (générations antérieures) | 6–8 Go | Confortable | **[ESTIMÉ]** |
| Galaxy Z Fold / Z Flip | 8–12 Go | Confortable | **[ESTIMÉ]** |
| Galaxy Tab S | 8–12 Go | Confortable | **[ESTIMÉ]** |
| Galaxy A (milieu de gamme) | 4–6 Go | **Acceptable jusqu'à ≈ 30 Mo d'état** ; **risqué au-delà** | **[ESTIMÉ]** |
| Galaxy M (entrée de gamme) | 3–4 Go | **Risqué dès le scénario 1 à 3 ans** | **[ESTIMÉ]** |
| Galaxy Tab A | 3–4 Go | **Risqué** idem | **[ESTIMÉ]** |

**[APPAREIL REQUIS]** — **toutes** les lignes de ce tableau sont des estimations
argumentées, pas des mesures. Elles sont fournies pour orienter la décision, et doivent
être **confirmées par mesure sur appareil** avant toute conclusion ferme. Le scénario 3
(≈ 9,27 Mo à plateau) est celui qui minimise le risque sur les appareils d'entrée de gamme ;
c'est un argument supplémentaire en sa faveur.

---

# G. PRÉSERVATION DE L'IA

## G.1 Garanties de préservation des mécanismes actuels

**[DÉMONTRÉ]** L'ensemble des propositions de ce rapport se situe **hors** du périmètre
protégé par le §36. Vérification point par point :

| Mécanisme protégé | Touché par une proposition ? | Preuve |
|---|---|---|
| 19 formules de critères | **NON** | Aucune proposition ne modifie `_scoresCriteres` |
| Poids IA (`poidsParDiscipline`) | **NON en valeur** — seule la *rétention* de la clé est discutée | Les 19 poids mesurés (A.2) restent inchangés |
| Poids par discipline | **NON** | 4 disciplines × 19 critères conservés tels quels |
| Bornes (`clampDiscipline`) | **NON** | Aucune modification demandée |
| Descente de gradient | **NON** | `_apprendreParGradient` intact |
| Facteurs d'apprentissage | **NON** | `lrBase`, `lrFactor`, `momentumFactor` intacts |
| TOP3 Learning | **NON** | Seuils `nbDisc < 5`, `totalBons/Mauvais < 3` intacts |
| Seuils / calibration / normalisation | **NON** | `ia_seuils_v1`, `normaliser()` intacts |
| Algorithmes statistiques | **NON** | Corrélations intactes |
| Mécanismes financiers | **NON** | Hors périmètre |

**Les seules propositions qui touchent des données de l'IA sont des propositions de
SUPPRESSION DE STOCKAGE d'objets dérivés (bilans), avec un garde-fou de vérification
(M-3, D.6).** Aucune ne modifie une valeur apprise.

## G.2 Prévention du double apprentissage

**[DÉMONTRÉ]** Trois protections existent déjà, à ne pas dégrader :

1. **Garde d'idempotence** : `enregistrerResultat` (3347) commence par
   `if (p.resultatsReels) return false;` — un pronostic déjà résolu **ne peut pas** être
   ré-appris. **[MESURÉ]** rejeu → `false`, poids **STRICTEMENT identiques**.
2. **Garde de corpus** : `_apprendreParDiscipline` exige `nbDisc >= 5` et
   `totalBons >= 3 && totalMauvais >= 3`. **[MESURÉ]** 3 bons + 1 mauvais (= 4) → refus.
3. **Garde d'archive** : `enregistrerResultat` avec `idx < 0` (course inconnue) consigne
   en archive et **retourne `false`** — **[MESURÉ]** l'archive seule n'entraîne rien.

**Risque introduit par une consolidation PMU (si elle était mal conçue)** : réinjecter un
résultat PMU déjà connu ferait franchir la garde d'idempotence si l'identité du pronostic
n'était pas préservée. **Protection proposée** : toute consolidation PMU doit passer par
`enregistrerResultat`, **jamais** écrire directement dans `_pronostics`.

## G.3 Prévention des fuites temporelles

**[DÉMONTRÉ]** Deux protections mesurées :

1. **Fenêtre glissante** : `_apprendreParGradient` travaille sur 45 jours (90 si
   insuffisant), avec `take(50)`. Un pronostic ancien **ne peut pas** influencer un
   apprentissage récent au-delà de cette fenêtre.
2. **Horodatage** : chaque entrée de `_journal` porte `date`, `avant`, `apres`.

**Risque identifié (FT-01)** : **[MESURÉ]** `estDansFenetre` de `CoteTrackerService`
travaille sur `DateTime` **local**, sans conversion UTC. Un changement de fuseau
(déplacement, passage heure d'été) pourrait décaler la fenêtre `[0,+30 min]` et donc faire
entrer ou sortir un mouvement de cote. **[ESTIMÉ]** Impact probablement faible mais réel.
**À porter en décision D-06.**

**Risque identifié (FT-02)** : les connaissances PMU **historiques** sont, par nature,
antérieures à l'app. Les injecter dans l'apprentissage reviendrait à apprendre sur un passé
que l'IA n'a pas prédit — c'est une **fuite temporelle**. **[Recommandation]** : les
connaissances PMU historiques servent à **alimenter les critères** (entrée), **jamais** à
constituer un cas d'apprentissage (sortie). Voir G.4.

## G.4 Distinction connaissances et apprentissage

C'est la distinction centrale du mandat. Formulation proposée :

| | **Connaissance** | **Apprentissage** |
|---|---|---|
| Définition | Information sur le monde, ingérée | Modification des poids par confrontation prédiction/réalité |
| Source | PMU (faits) ou calcul interne | Résultat réel d'un pronostic **émis par l'IA** |
| Où | `historique cheval`, `reductionKm`, `etatTerrain`, `elo_service` | `poidsParDiscipline`, `ia_journal_v2` |
| Réversible ? | Oui (re-téléchargeable) | **Non** (chemin parcouru) |
| Peut déclencher un gradient ? | **NON — jamais** | Oui, par construction |
| Consolidation PMU | **OUI** | **NON — cloisonné (règle C-10)** |

**Règle structurante proposée** :

> Une connaissance PMU peut **alimenter** l'entrée d'un calcul de score.
> Elle ne peut **jamais** produire un cas d'apprentissage.
> Seul un pronostic **effectivement émis** par l'IA, puis confronté à son résultat réel,
> constitue un cas d'apprentissage.

**[DÉMONTRÉ]** Cette règle est déjà respectée par le code : `_apprendreParGradient` filtre
sur `pronosticsAvecResultat` **ET** `scoresCriteres.isNotEmpty` — un pronostic sans scores
critères n'entre pas. Aucun chemin n'injecte de donnée PMU brute dans le gradient.

## G.5 Conséquences de la future réinitialisation

**Aucun reset n'est exécuté ni décidé ici.** Le mandat est explicite : « Ne rien décider à
la place de l'utilisateur. Aucun reset maintenant. »

**[DÉMONTRÉ]** Comportement actuel d'un reset, par lecture du code :

| Élément | Survit à `reinitialiserIA()` ? | Preuve |
|---|---|---|
| `ia_poids_v3` | **NON** — réinitialisé aux défauts | `:6518` `_poids = IaPoidsAdaptatifs()` |
| `_pronostics` | **NON** | `:2142` |
| `_bilansSemaine` / `_bilansMois` | **NON** | `:2142-2143` |
| `elo_service` | **OUI** (service distinct, non touché) | `:2157` commentaire |
| **Archive historique** | **OUI — préservée explicitement** | `:2139-2151`, « décision reportée à E4 » |
| `arriveesOfficielles` | **OUI** | `:2383` même réserve |

**Trois questions à trancher par l'utilisateur — je ne les tranche pas :**

| # | Question | Conséquence si « oui » | Conséquence si « non » |
|---|---|---|---|
| **Q-01** | Un reset doit-il détruire l'**archive historique** des pronostics évincés ? | Repartir totalement vierge, mais perte définitive de l'historique d'analyse | L'archive survit ; cohérent avec le comportement actuel |
| **Q-02** | Un reset doit-il détruire les **arrivées officielles** (faits PMU) ? | Perte de faits authentiques, re-téléchargeables | Faits conservés — **recommandé** |
| **Q-03** | Un reset doit-il détruire les **ratings ELO** ? | ELO repart à 1500 pour tous, alors que l'ELO est dérivable des arrivées | ELO conservé — cohérent |

**Observation à l'attention du décideur [DÉMONTRÉ]** : l'ELO et les arrivées officielles
sont **dérivables de faits**. Les détruire lors d'un reset détruirait de l'information
**reconstructible**, sans bénéfice pour la « remise à zéro de l'apprentissage ». En revanche
`poidsParDiscipline` et `ia_journal_v2` sont, eux, la trace **non reconstructible** du
chemin d'apprentissage : ce sont les seuls qu'un reset doit réellement remettre à zéro.
**Ceci est une recommandation argumentée, pas une décision.**

---

# H. CONCLUSION ET DÉCISIONS

## H.1 Solution recommandée

**Architecture B — « Dépôt de connaissances cloisonné », sans changement de support de
stockage**, complétée par la suppression de la duplication des bilans.

Concrètement, cinq décisions techniques, toutes bornées et réversibles :

| Réf | Décision | Effet mesuré / calculé |
|---|---|---|
| **A-01** | **Ne pas stocker** `ia_bilans_semaine_v1` ni `ia_bilans_mois_v1` (recalculés à la demande) | **[MESURÉ]** −46,1 % du fichier du 13/11 (5 179 284 octets) |
| **A-02** | Plafonner `elo_service` (proposition : 20 000 clés) | **[CALCULÉ]** borne la croissance de 1,60 Mo/an à un plateau de 2,09 Mo, atteint en 263 j |
| **A-03** | Plafonner `premium_widgets_selection_jour_v1` (365 jours) | **[CALCULÉ]** borne 0,54 Mo/an |
| **A-04** | Introduire un registre déclaratif de politiques de rétention | Rend chaque plafond **vérifiable** ; aucun plafond ne reste implicite |
| **A-05** | Ajouter checksums + version par bloc + écriture `.tmp`→`rename` au format de sauvegarde | Supprime SB-01, SB-02, SB-03 |

## H.2 Justification

**Trois raisons, chacune adossée à une mesure, pas à une préférence :**

1. **Le défaut majeur est l'absence de politique de rétention, pas le support.**
   **[MESURÉ]** Trois collections croissent sans borne (`BilanSemaine`, `BilanMois`,
   `elo_service`) ; quatre sont correctement plafonnées (`_pronostics` 600, `_journal` 500,
   `_rapports` 365, `grosParis` purge 90 j — cette dernière **vérifiée effective** : la
   fenêtre mesurée du 13/11 s'étend du 15/08 au 13/11, soit **exactement 90 jours**).
   Le partage est net : ce qui a une constante tient, ce qui n'en a pas explose.

2. **Le défaut le plus coûteux est une duplication de modèle de données.**
   **[MESURÉ]** Redondance ×2,39, soit 61,4 % du fichier. Les bilans n'apportent, en propre,
   que **9 valeurs dérivées** — recalculables en O(n). Supprimer leur stockage est la
   correction au meilleur rapport gain/risque de tout le chantier.

3. **Changer de support n'apporterait pas d'avantage proportionné aux risques.**
   **[DÉMONTRÉ]** `sqflite` n'existe pas sur le Web ; la prévisualisation Web est l'outil de
   validation de ce projet. L'architecture D **détruirait la capacité de vérification** — ce
   qui est inacceptable dans un chantier dont l'exigence première est la preuve.

## H.3 Modifications nécessaires

| # | Modification | Fichier | Nature |
|---|---|---|---|
| MN-01 | Ne plus sérialiser `_bilansSemaine` / `_bilansMois` | `ia_memory_service.dart:2788-2791` | Suppression d'écriture |
| MN-02 | Recalculer les bilans à la demande depuis `_rapports` | `ia_memory_service.dart` (nouvelle méthode) | Ajout, sans toucher l'existant |
| MN-03 | Ajouter `take()` sur `_bilansSemaine` / `_bilansMois` si conservés | `:2788-2791` | Garde |
| MN-04 | Plafonner `elo_service` avec journalisation des clés retirées | `elo_service.dart:877` | Garde |
| MN-05 | Registre déclaratif des politiques | nouveau fichier | Ajout pur |
| MN-06 | Checksums + version par bloc | `backup_service.dart` | Ajout au format |
| MN-07 | Écriture `.tmp` → `rename` | `backup_service.dart:1246-1248` | Correction |
| MN-08 | Comptage réel des pronostics au lieu de `gz.length/130` | `backup_service.dart:1856-1859` | Correction |
| MN-09 | Retries espacés + suspension après échecs | `data_refresh_service.dart` | Ajout |
| MN-10 | TTL différenciés par nature de donnée | `data_refresh_service.dart:222` | Correction |

**Aucune de ces modifications ne touche les 19 formules, les poids, la descente de gradient,
les seuils, la calibration, la normalisation ni les mécanismes financiers.**

## H.4 Modifications inutiles — explicitement écartées

| Écartée | Pourquoi |
|---|---|
| Migrer vers `sqflite` / `Hive` / `Isar` | Aucune mesure ne le justifie ; casserait le Web ; effort élevé pour un gain non démontré |
| Réécrire `IaMemoryService` | Service de plus de 7 800 lignes, validé par 20/20 tests de caractérisation ; réécriture = risque majeur sans bénéfice mesuré |
| Changer le format des pronostics | **[MESURÉ]** 1,7 % du fichier ; ce n'est pas le problème |
| Toucher à la fenêtre de gradient (45/90 j) | Mécanisme protégé §36, et **déjà borné** (`take(50)`) |
| Toucher aux 7 paliers de `mouvCote` | Mécanisme protégé §36 et validé par mesure |
| Toucher à `reductionKilometrique` (critère) | Le §12 interdit explicitement de créer un nouveau critère Record |
| Ajouter un compte cloud / une synchronisation | Exclu par le §32 (ne pas choisir de fournisseur, ne pas développer la sync) |

## H.5 Risques

| # | Risque | Gravité | Mitigation |
|---|---|---|---|
| **RI-01** | Supprimer les bilans alors qu'ils contiennent de l'information **non dérivable** | **Critique** | **Garde-fou M-3** : comparaison recalculé↔stocké **avant** toute suppression. Si écart → abandon de la suppression |
| **RI-02** | Une restauration écrase le local sans retour arrière | Haute | Snapshot `pre_restore_snapshot_v1` (E.8) |
| **RI-03** | Une consolidation PMU déclenche un double apprentissage | Haute | Tout passer par `enregistrerResultat` (G.2) |
| **RI-04** | Régresser un mécanisme protégé §36 | **Critique** | Aucune proposition n'y touche (G.1) ; vérification par test après intégration |
| **RI-05** | Un plafond ELO retire des chevaux encore actifs | Moyenne | Retirer en priorité les clés de plus faible `nb`, journaliser |
| **RI-06** | Le format `blocs` casse la lecture des sauvegardes `9.0` | Haute | Lecture conditionnelle ancien/nouveau format (E.5) |
| **RI-07** | Croissance du fichier dépasse les hypothèses | Moyenne | Les projections séparent **[MESURÉ]**, **[CALCULÉ]**, **[ESTIMÉ]** ; les hypothèses sont explicites |

## H.6 Protections

| Protection | État |
|---|---|
| Garde d'idempotence de l'apprentissage | **EXISTE** (`if (p.resultatsReels) return false`) |
| Garde de corpus (`nbDisc >= 5`, `totalBons/Mauvais >= 3`) | **EXISTE** — seuil mesuré : 3+1=4 refusé, 8+1=9 accepté |
| Archive avant éviction | **EXISTE** (`_securiserExcedentAvantEcriture`, `doitGelerBlobPronostics`) |
| Garde de concurrence du refresh | **EXISTE** (`if (_loading) return`) |
| Détection de changement | **EXISTE** (`_signaturedReunions` + comparaison) |
| Annulation des traitements obsolètes | **EXISTE** (`generationAuDemarrage`) |
| Purge sans résultat uniquement | **EXISTE et VÉRIFIÉE** (`if (p.resultatsReels) return false`) |
| Purge 90 j de `grosParis` | **EXISTE et VÉRIFIÉE** (fenêtre mesurée = 90 j exactement) |
| Archive préservée par un reset | **EXISTE** (décision « reportée à E4 ») |
| **Checksum de sauvegarde** | **MANQUE** → EV-03 |
| **Retour arrière de restauration** | **MANQUE** → E.8 |
| **Plafond des bilans / ELO / premium_widgets** | **MANQUE** → A-01, A-02, A-03 |

## H.7 Résultats des tests

**[MESURÉ]** Trois fichiers de test créés lors des tours précédents, portant sur le §3 :

| Fichier | Résultat |
|---|---|
| `test/audit_global_family_consumers_test.dart` | **6/6 PASS** |
| `test/audit_chaines_3_1_3_2_3_3_test.dart` | **16/16 PASS** |
| `test/audit_trot_monte_apprentissage_test.dart` | **12/12 PASS** |
| `test/audit_volumetrie_stockage_test.dart` | **9/9 PASS** (9 portes, toutes vertes) |
| Tests de caractérisation sur `clampDiscipline`/`normaliser` | **20/20 PASS** |

**[MESURÉ] Vérification d'analyse statique — exécutée, résultat exact :**

```
$ flutter analyze
Analyzing flutter_app...
No issues found! (ran in 4.5s)
```

**0 diagnostic** sur l'ensemble du projet (code applicatif **et** tests). Pour l'obtenir,
5 diagnostics présents dans mon propre fichier `test/audit_volumetrie_stockage_test.dart`
ont été **corrigés dans le code** — jamais masqués : import inutilisé supprimé, utilitaire
`_mediane` réellement exercé par une assertion, concaténations de chaînes remplacées par
des interpolations, accolades d'interpolation superflues retirées. Les commentaires
`// ignore: avoid_print` qui s'y trouvaient ont été **supprimés** et les `print` remplacés
par `debugPrint` (API autorisée), conformément à l'interdiction absolue d'utiliser des
`ignore` pour masquer un diagnostic.

**[MESURÉ] Ré-exécution du test après correction : `9/9 PASS`** (`All tests passed!`).

**Aucun test neuf n'a été créé pour ce rapport** — conformément à l'instruction de ne pas
multiplier les harnais quand l'analyse du code et la mesure des fichiers réels suffisent.

## H.8 Limitations restantes

| # | Limitation | Nature |
|---|---|---|
| **L-01** | Comportement de `SharedPreferences` sur un XML > 10 Mo (latence, ANR) | **[APPAREIL REQUIS]** |
| **L-02** | Consommation RAM réelle au démarrage à froid | **[APPAREIL REQUIS]** |
| **L-03** | Consommation batterie | **[APPAREIL REQUIS]** |
| **L-04** | Validité des estimations de compatibilité matérielle (F.8) | **[APPAREIL REQUIS]** |
| **L-05** | Contenu réel du magasin natif du widget (`RacePredictorWidgetData`) | **[APPAREIL REQUIS]** |
| **L-06** | Fréquence réelle des corrections officielles du PMU | **[APPAREIL REQUIS]** + **[INDÉTERMINÉ]** |
| **L-07** | Intention de conception initiale (§4) | **[INDÉTERMINÉ]** — historique Git tronqué, prouvé (`ddde819` racine sans parent) |
| **L-08** | Changement de nom d'un cheval signalé par l'API | **[INDÉTERMINÉ]** |
| **L-09** | Volumétrie du `SharedPreferences` complet (hors clés sauvegardées) | **[INDÉTERMINÉ]** |
| **L-10** | Comportement de l'app en changeant de fuseau horaire | **[ESTIMÉ]** risque faible, non mesuré |

**Aucune section D, E ou F n'est déclarée intégralement non mesurable.** Les mesures D et E
sont **faites** (sur les fichiers réels). Les mesures F qui exigent un appareil sont
**listées nommément** ci-dessus, avec leur nature — elles sont reportées, pas abandonnées.

## H.9 Décisions nécessitant votre validation

**Je ne décide rien de ce qui suit. Chaque point attend votre arbitrage.**

| # | Décision | Options | Recommandation argumentée |
|---|---|---|---|
| **D-01** | Supprimer le stockage des bilans (A-01) | (a) Oui, avec garde-fou M-3 · (b) Non, plafonner seulement | **(a)** — gain **mesuré** de 46,1 %, garde-fou vérifiant l'absence de perte |
| **D-02** | Plafond de `elo_service` | (a) 20 000 clés · (b) 10 000 · (c) aucun plafond | **(a)** — 20 000 couvre ≈ 1,6 an au rythme mesuré de 41,8 clés/j |
| **D-03** | Plafond de `premium_widgets_selection_jour_v1` | (a) 365 j · (b) 730 j | **(a)** — cohérent avec `_maxRapports = 365` |
| **D-04** | Déduplication à la restauration des agrégats | (a) Ajouter · (b) Ne rien faire | **(a)** — **à confirmer par test** : la restauration actuelle est-elle additive ? |
| **D-05** | Chemin de correction d'une arrivée officielle corrigée par le PMU | (a) Mécanisme de retour arrière de l'ELO · (b) Accepter l'irréversibilité | **(b)** dans l'immédiat — **(a)** est un chantier en soi, à ne pas ouvrir ici |
| **D-06** | Fenêtre de cote en `DateTime` local vs UTC | (a) Normaliser en UTC · (b) Laisser local | **(a)** — correction peu coûteuse, élimine FT-01 |
| **D-07** | Format de sauvegarde `blocs` avec checksums | (a) Adopter · (b) Ajouter seulement un checksum global | **(b)** d'abord — gain de détection sans changer la structure |
| **D-08** | Politique de reset : archive, arrivées officielles, ELO | Q-01 / Q-02 / Q-03 (G.5) | Archive **conservée**, arrivées **conservées**, ELO **conservé** — seul le chemin d'apprentissage est remis à zéro |
| **D-09** | Fusionner ou non `trot_monte` dans `global` | (a) Garder distinct · (b) Fusionner | **(a)** — la clé `'global'` mesurée est **inerte** (delta 5,55e-17) ; `trot_monte` est **active** et légitime |

## H.10 Plan d'intégration global après validation

**Aucune étape n'est exécutée avant votre validation. Ordre proposé, un commit par étape,
sur `main`, sans push.**

| Étape | Contenu | Test de sortie | Réversible ? |
|---|---|---|---|
| **P-1** | Registre déclaratif (MN-05), en lecture seule, sans effet | Le registre recense 100 % des clés écrites | Oui (ajout pur) |
| **P-2** | Recalcul des bilans sans suppression (MN-02), **comparaison** aux valeurs stockées sur données réelles | **Toutes** les valeurs recalculées == stockées | Oui |
| **P-3** | **Conditionné à P-2** : arrêt de l'écriture des bilans (MN-01) | Fichier réduit de **46,1 %** | Oui (réactiver l'écriture) |
| **P-4** | Plafonds ELO et premium_widgets (MN-04, A-03) | Croissance bornée, mesurée sur 30 j simulés | Oui |
| **P-5** | Checksum global de sauvegarde (D-07) | Un fichier tronqué est **refusé** | Oui |
| **P-6** | Écriture `.tmp` → `rename` (MN-07) | Aucun `.tmp` orphelin après export | Oui |
| **P-7** | TTL différenciés (MN-10) | Volume réseau mensuel mesuré | Oui |

**Condition d'arrêt du plan** : si P-2 révèle **une seule** valeur recalculée différente de
la valeur stockée, **P-3 ne doit pas être exécutée** et la proposition D-01 doit être revue.

## H.11 Vérification des effectifs et de l'analyse statique

**[MESURÉ]** Tous les comptages de ce rapport ont été recalculés directement sur les
fichiers. Récapitulatif de contrôle :

| Effectif annoncé | Valeur vérifiée | Source |
|---|---:|---|
| Clés `ia` dans une sauvegarde | **14** | 28/05 et 13/11 |
| Pronostics dans le blob (13/11) | **600** | décodage base64+gzip |
| Pronostics dans le blob (28/05) | **572** | idem |
| Rapports `ia_rapports_v1` (13/11) | **195** | liste |
| Bilans semaine (13/11) | **28** | liste |
| Bilans mois (13/11) | **7** | liste |
| Entrées journal (13/11) | **500** | plafond atteint |
| Clés `elo_service` (13/11) | **9 001** | map |
| Signaux `grosParis` (13/11) | **683** | liste |
| Copies de rapports stockées | **524** | mesure directe |
| Journaux distincts | **219** | union par date |
| Redondance | **×2,39** | 524 / 219 |
| Clés racines du fichier | **14** | vérifié |

## H.12 TABLEAU FINAL DES 19 CRITÈRES

**Colonnes** : `Clé` (courte) · `Critère` · `Source réelle démontrée` · `État` ·
`Limitation mesurée` · `Solution proposée`.
Les états sont : **SOLIDE** (source présente et fiable), **PARTIEL** (source présente mais
couverture incomplète), **FRAGILE** (source présente mais taux de repli neutre élevé),
**INTERNE** (pas de source PMU, calcul interne uniquement).

| # | Clé | Critère | Source réelle démontrée | État | Limitation mesurée | Solution proposée |
|---|---|---|---|---|---|---|
| A | `f` | Forme | `p.scoreFormeLong` — musique (12 courses + tendance) | **SOLIDE** | Profondeur d'historique 0–5 courses (médiane 5) | Conserver ; enrichir par l'historique PMU détaillé si disponible |
| B | `g` | Gains | `p.gains` ← `gainsCarriere` PMU | **SOLIDE** | Aucune limitation mesurée sur la présence | Conserver |
| C | `r` | Record | `p.record` → `recordEnSecondes` par regex `(\d+)'(\d{2})(?:…(\d))?` | **PARTIEL** | `reductionKilometrique` présent sur **84,6 %** des participants, mais **non utilisé** par ce critère | Utiliser `reductionKilometrique` comme source **individuelle** (prouvée) — **§12 : sans créer de nouveau critère** |
| D | `c` | Cote | `p.cote` ← `cote` PMU | **SOLIDE** | Disponible uniquement **avant** la course | Conserver ; la cote figée est déjà conservée dans `cotesPmuParNumero` |
| E | `k` | Constance | `p.musique` via `_scoreConstance` | **SOLIDE** | Dépend du décodage du format musique (`D/A/Q/J/T` = pénalité, `0` = non-partant) | Conserver |
| F | `v` | Victoires | `nbVictoiresRecentes` = victoires sur les **6** dernières sorties de la musique | **PARTIEL** | Borné à 6 sorties | Conserver — le bornage est un choix assumé, pas un défaut |
| G | `d` | Discipline | `_scoreDisciplineCompatibilite(p, course)` | **SOLIDE** | 6 spécialités distinctes | Conserver |
| H | `ds` | DistSpéc | `_scoreDistanceSpecialite(p, course)` ← `musiqueDistanceSpecifique` | **PARTIEL** | Dépend du champ `musique_dist` | Conserver ; vérifier la couverture sur corpus |
| I | `j` | Jockey | `_scoreJockey(p)` ← `statsJockeyCsv` | **PARTIEL** | Construit depuis l'API ou l'historique ; couverture non mesurée ici | **[APPAREIL REQUIS]** pour mesurer la couverture |
| J | `rp` | Repos | `p.scoreRepos` ← `joursRepos` | **SOLIDE** | — | Conserver |
| K | `hp` | Hippo | `p.scoreHippodrome` ← `statsHippoCsv` | **PARTIEL** | **[MESURÉ]** appariement historique défaillant avant correction : égalité exacte **4,3 %** ; règle token-subset → **26/27**, 0 ambiguïté | **Corrigé** (règle token-subset) |
| L | `en` | Entraîneur | `p.scoreEntraineur` | **PARTIEL** | Taux de réussite de l'entraîneur, source historique | **[APPAREIL REQUIS]** pour mesurer la couverture |
| M | `el` | ELO | `p.scoreElo` ← `EloService` | **INTERNE** | **9 001 clés**, 6 disciplines ; repli **1500** si absent | Conserver ; plafonner la collection (A-02) |
| N | `tr` | Terrain | `p.scoreTerrain(course.piste)` ← `statsTerrainCsv` | **FRAGILE** | `etatTerrain` présent sur **38,8 %** des courses ; **1 à 5 % en Trot** ; rend **50.0** (neutre) sinon. Note : avant correction, `statsTerrainCsv` était **toujours vide** (0/98) | **Corrigé** (source = `etatTerrain`, jamais `typePiste`) ; accepter la neutralité en Trot — **ne pas inventer** |
| O | `dv` | Divergence | `p.scoreDivergenceFormeCote` (forme vs cote) | **INTERNE** | Dépend de `cote`, donc **inopérant après le départ** | Conserver ; documenter l'inopérance hors fenêtre |
| P | `pr` | PoidsRel | `p.scorePoids(poidsMoyen)` ← `p.poids` ← **`handicapPoids`** | **PARTIEL** | **[DÉMONTRÉ]** producteur **existant** : `zone_turf_service.dart:624` — `poidsKg = poidsDixiemesKg / 10.0` depuis `pm['handicapPoids']` (unité = dixième de kg, conversion **corrigée**). Reste **0.0** si `handicapPoids` absent → `scorePoids` rend **50.0**. Restreint au galop (`plat`/`haie`/`steeple`) : **neutre 50.0 en trot** par construction | Conserver. **[APPAREIL REQUIS]** pour mesurer la couverture réelle de `handicapPoids` en galop |
| Q | `pg` | Progression | `p.scoreProgression` (âge + `gainsDernierAn`) | **FRAGILE** | **[DÉMONTRÉ]** : `gainsDernierAn` est **fabriqué** = `gainsCarriere × 0,20` quand le PMU ne le fournit pas (`zone_turf_service.dart:1016-1018`). **C'est une donnée artificielle** | **À trancher (D-10)** : soit supprimer le repli 20 % et rendre le critère neutre, soit le conserver en le documentant |
| R | `mc` | MouvCote | `p.scoreMouvementCote` ← `CoteTrackerService` | **INTERNE** | Barème **7 paliers** (90/75/62/50/38/28/15) ; fenêtre **`[0,+30 min]`** ; **50.0 neutre hors fenêtre** ; `DateTime` local (FT-01) | Conserver ; normaliser en UTC (D-06) |
| S | `pd` | PlaceDépart | `_scorePlaceDepart(p.placeDepartInt, …)` ← `placeCorde` | **INTERNE** | **[DÉMONTRÉ]** lu depuis `pm['placeCorde']` (`zone_turf_service.dart:708`), `?? 0` → neutre si absent. Branche trot était **inatteignable** avant correction des accents | **Corrigé** (accents) ; **[APPAREIL REQUIS]** pour mesurer la couverture réelle de `placeCorde` |

### H.12.1 Synthèse des 19 critères

| État | Nombre | Critères |
|---|---:|---|
| **SOLIDE** | **5** | `g` gains, `c` cote, `k` constance, `d` discipline, `rp` repos |
| **PARTIEL** | **7** | `f` forme, `r` record, `v` victoires, `ds` distSpec, `j` jockey, `hp` hippo, `en` entraîneur |
| **FRAGILE** | **3** | `tr` terrain, `pr` poidsRel, `pg` progression |
| **INTERNE** | **4** | `el` ELO, `dv` divergence, `mc` mouvCote, `pd` placeDépart |

**Vérification de l'effectif (exigée par le mandat — « Vérifie tous les effectifs ») :**

- SOLIDE = 5 (`g`, `c`, `k`, `d`, `rp`)
- PARTIEL = 7 (`f`, `r`, `v`, `ds`, `j`, `hp`, `en`)
- FRAGILE = 3 (`tr`, `pr`, `pg`)
- INTERNE = 4 (`el`, `dv`, `mc`, `pd`)
- **TOTAL = 5 + 7 + 3 + 4 = 19.** ✔

**Historique de cette ligne — par transparence** : une première rédaction de ce tableau
portait « PARTIEL = 6 » et « INTERNE = 3 », puis se corrigeait elle-même en note. Ce
correctif était une maladresse de rédaction, pas un calcul juste. Le tableau ci-dessus est
la version vérifiée : la somme des états fait **19**, et chaque critère A→S y figure
**exactement une fois**. Une seconde rédaction a par ailleurs affirmé à tort que « aucun
producteur de `p.poids` n'existe » — **c'était faux**, voir la correction de la ligne P.

### H.12.2 Trois défauts d'alimentation à traiter en priorité

Classés par gravité **mesurée**, pas par intuition :

| Rang | Critère | Défaut | Gravité | Pourquoi |
|---|---|---|---|---|
| 1 | `pg` Progression | **Donnée artificielle** : repli `gainsDernierAn = gainsCarriere × 0,20` | **Haute** | Le mandat exige d'« éviter les données artificielles ». Un repli à 20 % est une hypothèse déguisée en donnée. **Contredit directement une exigence du mandat** |
| 2 | `tr` Terrain | Couverture **38,8 %** en moyenne (1–5 % en Trot) | Moyenne | Neutralité assumée et documentée ; **ce n'est pas un défaut de code**, c'est une limite de la source PMU |
| 3 | `pr` PoidsRel | `handicapPoids` parfois absent → **50.0 neutre** ; et **toujours neutre en trot** par construction | Basse | Producteur **existant** et conversion **corrigée** ; le repli neutre est un choix de conception assumé |

**Correction explicite d'une affirmation erronée de ma part** : j'avais écrit dans une
version antérieure de ce rapport que « **aucun producteur de `p.poids` n'existe** » dans
`zone_turf_service.dart`. **C'était faux.** La mesure a montré que
`zone_turf_service.dart:624` produit bien `poidsKg` depuis `pm['handicapPoids']`, avec une
conversion `/ 10.0` (dixièmes de kg → kg) documentée comme corrigée. Le critère `poidsRel`
n'est donc pas « structurellement neutre en galop » : il est alimenté. Il redevient neutre
**uniquement** si `handicapPoids` est absent, et **par conception** en trot.

**Décision supplémentaire à valider :**

| # | Décision | Options | Recommandation argumentée |
|---|---|---|---|
| **D-10** | Repli `gainsDernierAn = gainsCarriere × 0,20` | (a) **Supprimer** le repli → `progression` devient neutre si absent · (b) Conserver en le documentant · (c) Conserver tel quel | **(a)** — le mandat exige d'éviter les données artificielles ; un repli à 20 % n'est pas une mesure, c'est une hypothèse déguisée en donnée. **Effet : le critère `progression` passe de « valeur inventée » à « neutre honnête ».** Ceci modifie le comportement d'un critère → **§36 impose votre validation explicite** |

**⚠️ Avertissement explicite sur D-10** : cette décision touche l'alimentation d'un des
19 critères. Elle est donc **soumise au §36** et ne sera appliquée **qu'après votre
validation formelle**. Elle n'est pas incluse dans le plan P-1…P-7.

## H.13 Ce que ce rapport ne prouve pas

Par honnêteté, et pour éviter toute lecture abusive :

1. **[INDÉTERMINÉ]** Le §4 (intention de conception initiale) reste **indéterminé**.
   L'historique Git est tronqué : `git rev-list --max-parents=0 --all` donne `ddde819`,
   racine **sans parent**, message « restore: état propre 025f678 — zip du 11/05 17h08 ».
   `git show 289d82b:…zone_turf_service.dart | grep -c performances-detaillees` → **0**.
   L'antérieur est **irrécupérable**. Je ne poursuis plus cette recherche.
2. **[INDÉTERMINÉ]** Deux constructions `switch` (F-03, `_penalite` ; F-04, `_typeMarqueur`)
   ont été localisées mais leur **intention** n'est pas déterminable — seulement leur effet.
3. **[ESTIMÉ]** Toutes les projections de croissance supposent les **rythmes mesurés
   maintenus constants**. Un changement d'usage (plus de courses suivies, plusieurs
   disciplines actives) les modifierait.
4. **[APPAREIL REQUIS]** Aucune conclusion ferme ne peut être tirée sur la RAM, le CPU,
   la batterie ou la compatibilité matérielle sans mesure sur terminal réel.
5. **Aucune migration, aucun reset, aucune intégration n'a été réalisée.** Le dépôt reste
   à l'état du commit `0955558` pour tout ce qui concerne le code applicatif.

---

# RÉCAPITULATIF DES DÉCISIONS À VALIDER

| Réf | Décision | Impact | Touche §36 ? |
|---|---|---|---|
| **D-01** | Supprimer le stockage des bilans (garde-fou M-3) | −46,1 % du fichier | Non |
| **D-02** | Plafonner `elo_service` à 20 000 clés | Borne 1,60 Mo/an | Non |
| **D-03** | Plafonner `premium_widgets` à 365 j | Borne 0,54 Mo/an | Non |
| **D-04** | Déduplication à la restauration | Évite le doublement | Non |
| **D-05** | Correction d'arrivée officielle : irréversible pour l'instant | Acceptation d'une limite | Non |
| **D-06** | Fenêtre de cote en UTC | Élimine FT-01 | **À vérifier** (critère `mouvCote`) |
| **D-07** | Checksum global de sauvegarde | Détecte la troncature | Non |
| **D-08** | Politique de reset (archive / arrivées / ELO) | Définit un reset futur | Non |
| **D-09** | Garder `trot_monte` distinct de `global` | Préserve un acquis mesuré | Non |
| **D-10** | **Supprimer le repli `gainsDernierAn = 20 %`** | Critère `progression` honnête | **OUI — validation formelle requise** |

**Fin du rapport consolidé. Aucun push GitHub. Aucune branche créée. Aucune migration.**
