# CHANTIER POIDS IA — RAPPORT DÉCISIONNEL DÉFINITIF

**Projet** : Pronostic-Hippique-V2 / « Race Predictor »
**Portée** : arbitrage final sur les pondérations des 19 critères.

> ## ⚠️ CE RAPPORT A ÉTÉ RÉVISÉ LE 27/11/2026 — LIRE CETTE SECTION D'ABORD
>
> La version initiale de ce document affirmait « **Aucune modification de
> production** ». **CETTE PHRASE N'EST PLUS VRAIE** depuis l'arbitrage du
> 27/11/2026, qui a **autorisé deux corrections** (§1 harmonisation de trois
> replis, §2 abaissement de douze planchers).
>
> **État exact au 27/11/2026** :
> - `lib/services/ia_memory_models.dart` — **MODIFIÉ** (corrections §1 et §2)
> - `lib/services/ia_memory_service.dart` — **MODIFIÉ** (§2, 3ᵉ définition
>   dupliquée des planchers, réellement atteinte en production)
> - Les sections **§0 à §10 ci-dessous** sont l'**état des mesures AVANT**
>   corrections. Elles restent exactes comme *constat*, et sont conservées
>   telles quelles pour la traçabilité. **Ne pas les lire comme l'état actuel.**
> - L'**état APRÈS corrections** est décrit dans la section
>   **« §11 — CORRECTIONS APPLIQUÉES »**, ajoutée en fin de document. C'est
>   elle qui fait foi pour l'état du code aujourd'hui.
>
> **Ce qui n'a PAS changé** : poids initiaux, gradient descent (lrBase 0,08,
> momentum 0,3, facteurs par critère), contraintes collectives 0,18 / 0,40,
> tous les **plafonds** individuels (la proposition `placeDepart` 0,07 → 0,30
> a été **REFUSÉE**), seuils, calibration, TOP3 Learning, ELO, mécanismes
> financiers PMU, `_normaliserScores`, `_determinerLabel`.
>
> **Ce chantier n'est PAS clos** : trois décisions restent ouvertes (§11.6).

**Branche** : `main`. Commit de base `b3a0107`, mesures `cd788bc`, rapport
précédent `7186445`, arbitrage final `d8e638b`, **corrections appliquées =
commit indiqué au §11.9**.
**Aucun push GitHub. Aucun APK. Aucun reset. Aucun recalcul historique.**

---

## 0. AVERTISSEMENT DE MÉTHODE, ET AVEU COMPLET D'ERREURS

Ce rapport contient trois objets que l'utilisateur exige de distinguer :

1. des **mesures** (chiffres reproductibles par un harnais nommé, exécutable) ;
2. des **lectures** de ces mesures (interprétation, toujours signalée) ;
3. des **hypothèses non prouvées** (signalées comme telles, jamais promues).

### 0.1 Les erreurs de mes rapports précédents — corrigées ici

L'utilisateur a relevé une erreur réelle. J'en ai trouvé d'autres en la
vérifiant. **Toutes** sont listées, aucune n'est effacée.

| Mon affirmation antérieure | Ce que la mesure établit | Où |
|---|---|---|
| « une seule divergence dans `fromJson` : `forme` 0,32 » | **FAUX — il y en a TROIS** : `forme` 0,32 (+0,07), `gains` 0,15 (+0,02), `record` 0,12 (+0,02) = **exactement 0,11** | §1, `M2.1`, `H6` |
| « la hiérarchie des poids est verrouillée mathématiquement » | **FAUX** : 0 paire verrouillée sur 342 | `A3` |
| « à discrimination égale, l'ordre des poids ne bouge pas » | **FAUX** : l'ordre change ; les valeurs de départ sont **oubliées** | `A6`, `A11` |
| « `forme`/`repos` au point fixe vaut 1/0,3 » | **FAUX** : 3,571429, à cause du plafond de groupe | `A11` |
| « la part enrichie réelle vaut exactement 0,184416880 » | **FAUX** : réappliquée, elle vaut 0,184877982 puis 0,185444691. `clamp()` **n'est pas idempotent** | `G1.2` |
| « avec discrimination uniforme −0,30, le plancher collectif 0,18 mord » | **FAUX** : part = 0,219178082. Une discrimination **uniforme est annulée** par `normaliser()` | `G1.3` |
| « les ratios 1,26/1,00 valent tous 1,26 » | **FAUX** : 1,183333333 (base) et 1,375000000 (enrichis). Deux facteurs distincts | `H1` |
| « l'écart 1,26 vs 1,00 est un pur effet d'échelle » | **FAUX** : c'est échelle **×** redistribution (fraction 0,436507937 écrêtée à 0,40) | `H1`, `H4` |
| « diviser par la somme redonne la table 1,00 » | **FAUX** : écart max 0,012854907 | `H4` |

**Chaque correction est inscrite dans le code du harnais** avec un bloc
`CORRECTION D'UNE AFFIRMATION FAUSSE` visible. Effacer ces blocs reviendrait à
masquer le raisonnement.

### 0.2 Conséquence de méthode

Je n'annonce comme *démontré* que ce qu'un harnais **mesure**, avec à chaque
fois la taille d'échantillon et la réserve chronologique. Tout le reste est
explicitement étiqueté.

---

## 1. LES QUATRE TABLES DE POIDS — LES TROIS DIVERGENCES

### 1.1 Sommes réelles

| Table | Source | Somme mesurée |
|---|---|---|
| Constructeur | `ia_memory_models.dart:592-612` | **1,260000000** |
| `.defauts` | `ia_memory_models.dart:943-951` | **1,260000000** |
| `fromJson` (repli) | `ia_memory_models.dart:846-869` | **1,370000000** |
| `clampDiscipline` (repli) | `ia_memory_models.dart:785-801` | **1,000000000** après division interne |

*Preuve* : `poids_familles_test.dart` (20/20 verts), `poids_echelle_consommateurs_test.dart` H6
(6/6 verts).

### 1.2 Les TROIS divergences — vérifiées ligne par ligne dans le code

L'utilisateur avait raison : `1,37 − 1,26 = 0,11` ne peut pas s'expliquer par
0,07. Vérification directe des 19 valeurs :

| Critère | Constructeur `:592-612` | `.defauts` `:943` | `fromJson` `:846-869` | Écart |
|---|---|---|---|---|
| `forme` | **0,250000** | 0,250000 | **0,320000** | **+0,070000** |
| `gains` | **0,130000** | 0,130000 | **0,150000** | **+0,020000** |
| `record` | **0,100000** | 0,100000 | **0,120000** | **+0,020000** |
| les 16 autres | identiques | identiques | identiques | 0 |
| **SOMME** | **1,260000** | **1,260000** | **1,370000** | **+0,110000** |

**Contrôle arithmétique** : `0,07 + 0,02 + 0,02 = 0,11` **exactement**.
`1,37 − 1,26 = 0,11` **exactement**. La réconciliation est complète.

*Preuve* : `poids_familles_test.dart` M2.1 affiche les trois lignes
`⚠ DIVERGENT` — **ce test avait toujours raison**, c'est mon résumé qui était
faux. `poids_echelle_consommateurs_test.dart` H6 confirme que
`IaPoidsAdaptatifs.fromJson({})` produit une somme de **1,370000000** et affiche
`forme=0.32 gains=0.15 record=0.12`.

### 1.3 Ce que l'utilisateur avait vu juste de plus : le repli N'EST PAS documentaire

`fromJson` (`:836-869`) **n'appelle jamais `clamp()`**. Un JSON tronqué — clé
absente, restauration ancienne, migration partielle — livre donc au moteur de
score une table de **somme 1,37**, et les trois valeurs de repli sont
**réellement utilisées**.

Mesure H6, cas réel simulé (JSON à 16 clés, sans `forme`/`gains`/`record`) :

```
fromJson({})                              → somme = 1.370000000000
fromJson(JSON partiel sans f/g/r)         → somme = 1.370000000000
après un clamp() explicite                → somme = 1.000000000000,
                                            part enrichie = 0.400000000000
```

**Conséquence directe** : une restauration partielle produit un score
**37 % plus élevé** que la normale (facteur ≈ 1,37 au lieu de 1,00), ce qui
franchit plus facilement tous les seuils absolus (`_determinerLabel` 75/52,
`seuilSimpleGagnant` 80, `seuilMinScore` de `best_bet_screen`).

**Correction proposée** : les trois replis de `fromJson` doivent être alignés
sur le constructeur (`0,25` / `0,13` / `0,10`). C'est la correction n°1 du §8.

### 1.4 `clamp()` n'est pas idempotent — découverte non anticipée

En réappliquant les poids réels du 13/11/2026, la part enrichie **change** :

```
état sauvegardé                  0.184416880   (somme 0.999999999800)
passe 1 de clamp()               0.184877982
passe 2                          0.185132572
passe 10                         0.185442073
passe 500 (point fixe)           0.185444691   (somme 1.000000000000)
```

**Cause mesurée** : l'état sauvegardé **viole ses propres bornes** :
`cote = 0,4018138807 > 0,40` et `victoires = 0,1506802053 > 0,15`.
`clamp()` les rabote, la base baisse, `normaliser()` recalcule alors un facteur
de base plus grand et redistribue.

**Ce n'est pas une erreur de mesure** : c'est le comportement réel du code.
`clamp()` **dérive** au lieu de projeter. Sans gradient, il déplace la part
enrichie de 0,184417 à 0,185445.

---

## 2. POPULATIONS — NE PAS CONFONDRE LES SOURCES

L'utilisateur exige que je précise l'origine exacte de chaque chiffre. Voici la
séparation stricte.

### 2.1 Les trois populations, nommées

| Population | Nature | Dernière mesure |
|---|---|---|
| **P-A — matrices sauvegardées** | `ia.ia_poids_v3.value` des backups du 28/05/2026 (802 màj) et 13/11/2026 (3871 màj). Ce sont des **états figés**, antérieurs au chantier PMU/SQLite/ELO/alimentation. | `poids_limite_structurelle_test.dart` H1–H4 |
| **P-B — moteur actuel sur corpus PMU réel** | `ZoneTurfService.chargerProgramme` alimenté par `test/fixtures_corpus` (1938 courses, collectées 26–27/11/2026), exécuté dans le **vrai `compute()`** par `executerBatchIsolatePourMesure`. | `chaine_19_criteres_isolate_test.dart` C-19-1..4 |
| **P-C — poids réels réappliqués** | Les 19 valeurs de P-A, réinjectées dans le mécanisme actuel (`clamp()` + gradient). | `poids_contraintes_test.dart` G1.2, G1.3 |

### 2.2 Réponse explicite : d'où venaient les « 8 critères à variance nulle » ?

**Ils venaient de P-A — les matrices sauvegardées. Pas du moteur actuel.**

La mesure E3 (`poids_comparaisons_reelles_test.dart`, n = 47 courses de mai)
neutralise un critère à la fois et constate Δ = 0,00 pour 9 critères :
`record`, `discipline`, `repos`, `entraineur`, `elo`, `terrain`, `poidsRel`,
`mouvCote`, `placeDepart`. Ce sont les critères dont la note est **constante
dans la course** dans ces matrices-là.

**Cette population est antérieure au chantier d'alimentation.** Elle ne
représente donc pas nécessairement le comportement actuel.

### 2.3 Ce que mesure la population P-B — le moteur actuel

`chaine_19_criteres_isolate_test.dart` mesure, sur le **vrai chemin isolate**,
le nombre de critères réellement calculés :

```
[MESURE C-19-2] critères réellement calculés : 10 / 19
```

avec la répartition par critère sur une course ATTELE (18 partants) :

| Critère | calculé | neutre | valeurs distinctes |
|---|---|---|---|
| `forme` | 17 | 0 | 16 |
| `gains` | 17 | 0 | 17 |
| `record` | **0** | 17 | 1 |
| `cote` | 17 | 0 | 8 |
| `constance` | 15 | 2 | 14 |
| `victoires` | 17 | 0 | 5 |
| `discipline` | **0** | 17 | 1 |
| `distSpec` | 17 | 0 | 10 |
| `jockey` | **0** | 17 | 1 |
| `repos` | 17 | 0 | 12 |
| `hippo` | 12 | 5 | 6 |
| `entraineur` | **0** | 17 | 1 |
| `elo` | **0** | 17 | 1 |
| `terrain` | **0** | 17 | 1 |
| `divergence` | 10 | 7 | 7 |
| `poidsRel` | **0** | 17 | 1 |
| `progression` | 17 | 0 | 3 |
| `mouvCote` | **0** | 17 | 1 |
| `placeDepart` | **0** | 17 | 1 |

**Amplitude par spécialité (6 spécialités, C-19-4)** :

| Spécialité | Course | calculés | jamais calculés |
|---|---|---|---|
| ATTELE | 20/11 R1C5 VINCENNES | **10/19** | record, discipline, jockey, entraineur, elo, terrain, poidsRel, mouvCote, placeDepart |
| MONTE | 21/11 R6C1 ANGERS | **8/19** | + hippo, progression |
| PLAT | 20/11 R2C6 LE BOUSCAT | **12/19** | record, discipline, jockey, entraineur, elo, terrain, mouvCote |
| HAIE | 21/11 R1C6 AUTEUIL | **11/19** | record, discipline, jockey, entraineur, elo, terrain, mouvCote, placeDepart |
| STEEPLECHASE | 22/11 R3C5 LYON-PARILLY | **11/19** | idem HAIE |
| CROSS | 26/11 R2C9 LIGNIERES | **10/19** | idem ATTELE |

### 2.4 Attribution par critère — donnée absente ≠ défaut du moteur

L'utilisateur l'exige explicitement : « une donnée réellement absente ne
constitue pas un défaut du moteur ». Voici l'attribution, critère par critère,
**pour la population P-B (moteur actuel)** :

| Critère | Statut mesuré | Cause | Défaut du moteur ? |
|---|---|---|---|
| `record` | jamais calculé | **donnée absente** du programme PMU (`/performances-detaillees`) | **NON** |
| `jockey` | jamais calculé | **donnée absente** (pas de driver/jockey dans le payload de ces courses) | **NON** |
| `entraineur` | jamais calculé | **donnée absente** | **NON** |
| `terrain` | jamais calculé | **donnée absente** (pas de terrain dans le programme chargé) | **NON** |
| `poidsRel` | jamais calculé | **non applicable** hors courses à handicap de galop | **NON** |
| `placeDepart` | jamais calculé sauf PLAT | **non applicable** (corde non fournie hors PLAT) | **NON** |
| `elo` | jamais calculé | **repli documenté D-27** : `EloService` restaure 0 rating (`✅ 0 ratings restaurés` dans la sortie) | **NON — base vide** |
| `mouvCote` | jamais calculé | **insuffisant** : `CoteTracker` restaure 0 mouvement, un seul snapshot par course | **NON — fenêtre 30 min non couverte** |
| `discipline` | jamais calculé | **indéterminé / neutre par calcul** dans ces courses | à surveiller, non démontré |
| `hippo` | 12/17 calculé (ATTELE) | partiellement disponible | non |
| `divergence` | 10/17 calculé | dépend de la cote ET de la forme | non |
| `progression` | 17 calculé, **3 valeurs distinctes** | calculé mais peu discriminant | non |

**Conclusion §2** : sur les 9 critères « jamais calculés » du moteur actuel,
**8 relèvent d'une donnée absente, non applicable ou d'une base vide**, et
**1** (`discipline`) reste indéterminé. **Aucun défaut d'alimentation démontré
n'a été identifié dans le moteur actuel.**

**Ce qu'il ne faut PAS en conclure** : que les 9 critères sont inutiles. Ce sont
les **données** qui manquent dans l'échantillon PMU collecté, pas le code.

### 2.5 Ce que cela change pour la décision

Les 12 enrichis sont écrasés sur leur plancher dans **P-A** (matrices
historiques). Mais dans **P-B**, 8 à 11 d'entre eux ne reçoivent **aucune
donnée**. Le poids peut donc être au plancher **sans que l'apprentissage soit
fautif** : un critère sans note ne peut pas discriminer, donc ne peut pas
mériter de poids.

**Conséquence** : la correction des planchers (§5) reste utile, mais elle ne
produira d'effet que **couplée à l'alimentation**. Modifier les planchers seuls
ne fera pas monter un critère dont la note est constante.

---

## 3. RÉCONCILIATION DES CONCLUSIONS SUR LA LIBERTÉ D'APPRENTISSAGE

L'utilisateur relève une contradiction apparente. Les trois affirmations sont
**simultanément vraies** parce qu'elles parlent de **trois objets différents**.
Voici la table de réconciliation, notion par notion.

### 3.1 Les sept notions, démêlées

| # | Notion | Ce qu'elle signifie exactement | Mesure | Verdict |
|---|---|---|---|---|
| **1** | **Possibilité mathématique individuelle** | Existe-t-il, dans la boîte admissible, un état où le critère A dépasse le critère B ? | `A3` : **0 paire verrouillée / 342** (soit 0,0 %) | **AUCUNE impossibilité** |
| **2** | **Accessibilité réelle par le gradient** | Le gradient peut-il *atteindre* cet état depuis un départ réel ? | `G3.1` : les 4 enrichis testés (`placeDepart`, `elo`, `jockey`, `repos`) partent du **point fixe réel** (0,010101 / 0,020203) et **atteignent leur plafond individuel** | **OUI, accessible** |
| **3** | **Contraintes collectives** | La répartition base/enrichis borne-t-elle le groupe ? | `G1.1` : Σ planchers indiv. enrichis = **0,160000** pour un plancher de groupe **0,180000** → marge **0,020000**. Plafond de groupe **0,400000**. | **Contrainte réelle mais NON active en hausse** |
| **4** | **Saturation aux bornes** | Combien de poids sont collés à une borne ? | `H2` : **16 / 19** à moins de 2 % d'une borne. `G1.2` : **11 / 12** enrichis au plancher. | **Massive** |
| **5** | **Absence de discrimination des données** | Le critère produit-il des notes différentes entre chevaux ? | `C-19-2` : **10 / 19** calculés ; 9 avec **1 seule valeur distincte** | **Cause première** |
| **6** | **Convergence lente** | Combien de cycles pour un effet visible ? | `G2.5` : franchissement en **32 cycles** (C0) ; `A12` : 2 à 6 cycles pour 50 % de plage ; `G2.3` : **perte de 85,56 % en 4000 cycles de silence** | **PAS un frein** |
| **7** | **Blocage structurel démontré** | Une impossibilité *structurelle* (pas seulement observée) ? | `A3` : 0/342. Aucun blocage mathématique. Le seul blocage mesuré est **individuel** (`G3.1` : `placeDepart` bute à **0,070000000**, son plafond) | **AUCUN blocage structurel du groupe** |

### 3.2 La réconciliation, en une phrase par affirmation

| Affirmation | Statut | Démonstration |
|---|---|---|
| « 0 paire verrouillée sur 342 » | **VRAI** | `A3` sur 3000 tirages × 19 critères, 0 violation. Chaque critère peut dépasser chacun des 18 autres. |
| « Chaque critère peut dépasser chacun des 18 autres » | **VRAI** | Conséquence directe de `A3`. C'est la notion **1**. |
| « 13 critères bloqués et 6 capables d'évoluer » | **VRAI, mais c'est la notion 4, pas 7** | Mesuré sur P-A : 12 enrichis écrasés + `discipline` au plancher = 13 ; les 6 autres ont réellement bougé (`cote` ×5,02, `victoires` ×3,77, `forme` ×0,24). C'est un **état observé**, pas une impossibilité. |

### 3.3 Pourquoi « 13 bloqués » n'est PAS « 13 impossibles »

L'utilisateur l'exige : « ne qualifie pas un critère de bloqué uniquement
parce que son poids historique est proche de son plancher ».

**Mesure décisive `G3.1`** : je pars du **point fixe réel** (11 des 12 enrichis
à leur plancher) et je donne à **un seul** enrichi une discrimination forte
(0,60) :

| Enrichi testé | Départ | Arrivée sous C0 | Dépasse combien de critères de base ? |
|---|---|---|---|
| `placeDepart` | 0,010101333 | **0,070000000** (son plafond) | **4 / 7** |
| `elo` | 0,010101333 | **0,100000000** (son plafond) | **4 / 7** |
| `jockey` | 0,020202666 | **0,150000000** (son plafond) | **6 / 7** |
| `repos` | 0,010101333 | **0,080000000** (son plafond) | **4 / 7** |

**⇒ Un critère enrichi « bloqué » par son poids historique n'est PAS bloqué.**
Dès que les données lui donnent une discrimination réelle, il monte jusqu'à son
plafond individuel et **dépasse jusqu'à 6 des 7 critères de base**.

**Et `G3.3`** : en relevant le seul plafond de `placeDepart` (0,07 → 0,30),
celui-ci atteint **0,260960444** et dépasse **6 / 7** critères de base
(seul `cote` lui résiste, à 0,278666021).

### 3.4 La seule vraie limite, nommée

| Limite | Nature | Mesure |
|---|---|---|
| **Plafond individuel** | borne de `clamp()` par critère | `G3.1` : `placeDepart` atteint exactement 0,070000000 |
| **Plancher collectif** | `normaliser()` `:699` | `G1.3` : avec base +0,30 / enrichis −0,30, part = **0,180000000** exactement |
| **Plafond collectif** | `normaliser()` `:699` | `G2.2`, `G3.2` : 12 enrichis discriminants → part = **0,400000000** exactement |
| **Discrimination nulle** | données | `C-19-2` : 9 critères à 1 valeur distincte |

**Résumé §3** : il n'y a **aucun blocage structurel**. Ce qui est mesuré est
une **saturation aux bornes** (`16/19`) causée par une **absence de
discrimination** (`10/19` critères calculés), avec une **convergence rapide**
(32 cycles) et **deux contraintes collectives réelles mais non actives en
hausse** dans les données réelles.

---

## 4. POURQUOI LE GROUPE ENRICHI RESTE À ~18 % — LES SEPT EFFETS SÉPARÉS

L'utilisateur demande de mesurer séparément sept effets. Voici chacun, isolé.

### 4.1 Effet 1 — Les planchers individuels

**Mesure `G1.1`** :
```
Σ planchers individuels des 12 enrichis = 0.160000000
plancher collectif                      = 0.180000000
marge résiduelle                        = 0.020000000
⇒ les planchers consomment 88.89 % du plancher collectif
```

Répartition de cette somme : `distSpec` 0,03 (18,75 %), `jockey` 0,02 (12,5 %),
`mouvCote` 0,02 (12,5 %), puis 9 critères à 0,01 (6,25 % chacun).

**Effet** : quand les planchers sont **tous saturés simultanément**, il ne
reste que 0,02 à répartir entre 12 critères, soit **0,001666667 en moyenne**.
La hiérarchie interne de la famille enrichie ne peut alors quasiment pas
s'exprimer.

### 4.2 Effet 2 — Le plancher collectif

**Mesure décisive `G1.3`** : avec base **+0,30** et enrichis **−0,30** (seule
configuration qui fait réellement mordre le plancher), la part enrichie
s'arrête à **0,180000000** exactement. Le plancher collectif **fonctionne**.

**MAIS** — et c'est le point que l'utilisateur demandait de trancher — dans les
**données réelles**, il **ne mord pas** :

| Population | Part enrichie mesurée | Plancher 0,18 | Marge vers le plafond 0,40 |
|---|---|---|---|
| 28/05/2026 (802 màj) | **0,179999998** | ≈ atteint | 0,220000 |
| 13/11/2026 (3871 màj) | **0,184416880** | **dépassé** | **0,215583** |
| 13/11 après 500 `clamp()` | **0,185444691** | **dépassé** | **0,214555** |

**⇒ Le maintien à ~18 % n'est PAS dû au plancher collectif.** Le groupe est
libre de monter jusqu'à 0,40 et **20 points de pourcentage restent disponibles**.

**Preuve indépendante `G1.3`** : avec une discrimination **nulle** sur les 19
critères, la part enrichie reste à 0,185444691 — elle ne descend pas. Aucune
force ne la retient.

### 4.3 Effet 3 — Le plafond collectif

**Mesure `G2.2` et `G3.2`** : quand les **12 enrichis discriminent fortement**
(0,30 ou 0,60), la part enrichie monte et **s'arrête à 0,400000000 exactement**
sous C0, C1, C2, C3 et C5. Sans contrainte collective (C4), elle atteint
**0,781060000**.

**⇒ Le plafond collectif 0,40 est PLEINEMENT OPÉRANT** — mais seulement quand
les enrichis discriminent. Dans les données réelles, il n'est jamais atteint.

### 4.4 Effet 4 — Les coefficients du gradient

`lrBase = 0.08`, `lr = lrBase × min(1, nb/20) × stabilisation × atypique`,
`momentumFactor = 0.3`, facteurs par critère 1,0 / 0,5 / 0,4 / 0,3.

**Mesure `G2.5`** : pour que `placeDepart` (discrim 0,30) dépasse `forme`
(discrim 0,02), il faut **32 cycles** sous C0. **`A12`** : 2 à 6 cycles
suffisent pour parcourir 50 % de la plage atteignable, **tous facteurs
confondus** (facteur 1,0 → 3,9 cycles en moyenne ; facteur 0,3 → 3,0 cycles).

**⇒ Les coefficients du gradient ne sont PAS le frein.** Un facteur 0,3 ralentit
la montée mais ne l'empêche pas : `G3.1` montre `repos` (facteur 0,3) atteindre
son plafond de 0,08.

### 4.5 Effet 5 — Les normalisations successives

**Mesure `G1.2`** : `clamp()` **n'est pas idempotent**. Sans gradient, la part
enrichie dérive de **0,184417 → 0,185445** en 500 passes. La somme reste 1,0
mais la répartition change, parce que `clamp()` rabote `cote` et `victoires` à
leurs plafonds puis `normaliser()` rééquilibre.

**Effet secondaire capital** : `normaliser()` **annule une discrimination
uniforme**. Mesure `G1.3` : avec −0,30 sur les **19** critères, la part
enrichie ne descend pas à 0,18 mais reste à **0,219178082** (= 0,16/0,73, la
fraction naturelle). Tous les poids sont multipliés par le même facteur, puis
divisés par le total : **l'effet s'annule exactement**.

**⇒ Seule une discrimination RELATIVE agit.** Un critère ne peut gagner que
parce qu'un autre perd — pas parce qu'il est « globalement bon ».

### 4.6 Effet 6 — Les corrélations

**Mesure** : le gel exige `nb >= 50` **et** `r > 0.85` dans
`_poids.correlations`. Dans les **deux backups**, `correlations` est **vide**.
Les 47 courses exploitables de mai sont insuffisantes pour un seuil à 50.

**⇒ NON MESURABLE aujourd'hui.** Aucune affirmation possible. À étudier
prospectivement (§8, point 6).

### 4.7 Effet 7 — Qualité et disponibilité des données

**Mesure `C-19-2` et `C-19-4`** : **10 / 19** critères calculés en ATTELE,
**8 / 19** en MONTE, **12 / 19** en PLAT. Les 9 non calculés ont **une seule
valeur distincte**, donc une discrimination **exactement nulle**.

**⇒ C'est l'effet DOMINANT.** Un critère à discrimination nulle reçoit
`grad = lr × 0 = 0`. Il ne peut pas monter, quel que soit son plancher.

### 4.8 Synthèse chiffrée : les sept effets, classés par poids réel

| Rang | Effet | Mesure | Rôle |
|---|---|---|---|
| **1** | **Données (discrimination)** | 10/19 calculés ; 9 à 1 valeur distincte | **CAUSE PREMIÈRE** — sans signal, aucun effet |
| **2** | **Plafond individuel** | `G3.1` : bute à 0,070000000 ; relevé → 0,260960444 | **borne active en hausse** |
| **3** | **Plafond collectif** | `G2.2` : 0,400000000 exactement | **borne active quand 12 discriminent** |
| **4** | **Planchers individuels** | 0,160000 / 0,180000 → marge 0,020000 | noie la hiérarchie interne |
| **5** | **Normalisations** | dérive 0,184417→0,185445 ; annule le uniforme | ne bloque pas, mais déforme |
| **6** | **Plancher collectif** | `G1.3` : 0,180000000 actif | **n'est PAS le frein** (0,1844 réel) |
| **7** | **Coefficients du gradient** | 32 cycles ; 2–6 cycles pour 50 % | **n'est PAS le frein** |

### 4.9 Réponse directe : « pourquoi le groupe ne progresse-t-il pas ? »

**Parce que 9 de ses 12 critères n'ont AUCUNE discrimination dans les données,
et que les 3 autres butent sur leur plafond INDIVIDUEL — pas sur le plancher
collectif.**

Démonstration en une ligne (`G1.2`) :
```
part enrichie réelle mesurée = 0.185444691
plafond collectif            = 0.400000000
marge disponible inutilisée  = 0.214555309   ← 21,5 points de %
```

Le groupe **n'est pas retenu**. Il **manque de signal**.

### 4.10 Le test exigé : un enrichi faible peut-il devenir plus pertinent ?

**OUI — mesuré, `G3.1` et `G3.3`.** Sur les 4 enrichis testés depuis le point
fixe réel, **tous** dépassent au moins 4 des 7 critères de base dès qu'ils
reçoivent une discrimination réelle. `jockey` en dépasse **6/7**.

**Réserve honnête** : ces expériences sont **[SYNTH]** — la discrimination est
imposée, pas observée. Elles démontrent une **propriété du mécanisme** : *si*
les données discriminent, *alors* le poids monte et dépasse. Elles ne
démontrent **pas** que les données discrimineront — c'est exactement ce que
`C-19-4` mesure comme absent (9 critères sur 19 non alimentés).

---

## 5. PROPOSITIONS CHIFFRÉES SUR LES CONTRAINTES — CINQ CONFIGURATIONS

L'utilisateur refuse « simplement abaisser les planchers ». Voici cinq
configurations chiffrées, mesurées sur les mêmes scénarios.

### 5.1 Les cinq configurations testées

| Code | Nom | Planchers individuels des enrichis | Plancher collectif | Plafond collectif |
|---|---|---|---|---|
| **C0** | ACTUEL | valeurs de production (Σ = 0,160) | **0,18** | 0,40 |
| **C1** | PLANCHERS 0,005 | tous à **0,005** (Σ = 0,060) | 0,18 | 0,40 |
| **C2** | COLLECTIF 0,10 | inchangés (Σ = 0,160) | **0,10** | 0,40 |
| **C3** | COMBINÉE | 0,005 (Σ = 0,060) | **0,10** | 0,40 |
| **C4** | SANS COLLECTIF | inchangés | **aucun** | **aucun** |
| **C5** | PLAFOND INDIV. LEVÉ | inchangés | 0,18 | 0,40, **`placeDepart` haut 0,07 → 0,30** |

C4 est une **référence expérimentale** destinée uniquement à comprendre
l'influence des contraintes collectives. Elle n'est **jamais** proposée en
production.

### 5.2 Résultat préalable, décisif : C2 est arithmétiquement INOPÉRANTE

**Mesure `G2.4`** : C2 comparée à C0 sur **150 vecteurs × 19 critères = 2850
comparaisons** → **0 écart**.

Raison arithmétique : `plancher collectif 0,10 < Σ planchers individuels 0,16`.
La fraction enrichie ne peut **jamais** descendre sous 0,16, donc le plancher
0,10 ne s'applique jamais.

**⇒ Abaisser SEUL le plancher collectif est SANS EFFET.** Toute modification du
plancher collectif doit être **couplée** à une baisse des planchers individuels.
C'est une mesure, pas une opinion.

### 5.3 Les sept indicateurs exigés, configuration par configuration

#### Scénario A — un seul enrichi réellement discriminant (`placeDepart` 0,30)

| Config | part enrichie | `placeDepart` final | cycles→saturation | paires (enrichi>base)/84 | base rétrogradées/7 |
|---|---|---|---|---|---|
| C0 | 40,000 % | **0,064807344** | 364 | 1 | 1 |
| C1 | 40,000 % | **0,064807344** | 364 | 1 | 1 |
| C2 | 40,000 % | **0,064807344** | 364 | 1 | 1 |
| C3 | 40,000 % | **0,064807344** | 364 | 1 | 1 |
| C4 | 45,543 % | 0,065489397 | 333 | 1 | 1 |
| **C5** | 40,000 % | **0,110769231** | 364 | **7** | **7** |

**Lecture mesurée** : abaisser les planchers (C1, C3) ou le plancher collectif
(C2) ne change **RIEN** quand le gradient est ascendant. **Seul le relèvement du
plafond individuel (C5) libère le critère** : ×1,709 sur son poids, et il passe
de 1 à 7 paires gagnées sur 84.

#### Scénario B — les 12 enrichis deviennent tous discriminants (0,30)

| Config | part enrichie | plafond collectif atteint ? | cycles | paires/84 | base rétro/7 | domination |
|---|---|---|---|---|---|---|
| C0 | **40,000 %** | oui | 355 | 0 | 0 | 1,00× |
| C1 | **40,000 %** | oui | 355 | 0 | 0 | 1,00× |
| C2 | **40,000 %** | oui | 355 | 0 | 0 | 1,00× |
| C3 | **40,000 %** | oui | 355 | 0 | 0 | 1,00× |
| **C4** | **78,106 %** | — | 119 | **84** | **7** | **1,90×** |
| C5 | 40,000 % | oui | 355 | 0 | 0 | 1,00× |

**Lecture mesurée** : quand les 12 discriminent **également**, ils restent tous
égaux entre eux — donc aucune paire n'est gagnée (0/84). Le plafond collectif
0,40 borne le groupe. **Sans plafond (C4), le groupe prend 78,1 % et écrase la
base : les 7 critères de base sont rétrogradés, domination 1,90×.**

**⇒ Le plafond collectif 0,40 est un garde-fou RÉEL. Sa suppression produit une
domination excessive mesurée.**

#### Scénario C — vitesse et stabilité du franchissement

| Config | cycles pour que `placeDepart` dépasse `forme` | redescentes |
|---|---|---|
| C0 | **32** | **0** (stable) |
| C1 | 32 | 0 |
| C2 | 32 | 0 |
| C3 | 32 | 0 |
| C4 | 25 | 0 |
| C5 | **20** | 0 |

**Lecture** : le franchissement est **stable partout** (0 redescentes). C5 est
légèrement plus rapide (20 vs 32) parce que la cible est plus haute.

#### Scénario D — saturation → silence (données insuffisantes) → retour

| Config | saturé | après silence | perte | cycles de retour |
|---|---|---|---|---|
| C0 | 0,064807344 | 0,009356716 | 85,562 % | **13** |
| C1 | 0,064807344 | **0,004681919** | 92,776 % | **13** |
| C2 | 0,064807344 | 0,009356716 | 85,562 % | 13 |
| C3 | 0,064807344 | **0,004681919** | 92,776 % | **13** |
| C4 | 0,065327149 | 0,009367775 | 85,660 % | 10 |
| C5 | **0,155408533** | 0,009356716 | 93,979 % | **180** |

**Lecture mesurée, à double tranchant** :
- C1/C3 descendent **plus bas** en période de silence (0,004682 vs 0,009357) :
  c'est la **liberté retrouvée** — le plancher individuel ne retient plus.
- Mais le **retour reste 13 cycles dans tous les cas** : la capacité de
  récupération n'est **pas dégradée**.
- C5 met **180 cycles** à revenir, parce qu'il doit regrimper depuis 0,0094
  jusqu'à 0,1554 : la hauteur acquise est plus grande, donc le retour est
  proportionnellement plus long. **La vitesse relative est identique.**

**⇒ Réponse à l'exigence « capacité à retrouver une importance pertinente
après une période de données insuffisantes »** : elle est **préservée** dans
toutes les configurations, avec un coût en cycles proportionnel à la hauteur
perdue. **Aucune configuration ne dégrade la réversibilité.**

### 5.4 Les sept indicateurs, en tableau de synthèse

| Indicateur exigé | C0 | C1 | C2 | C3 | C4 | C5 |
|---|---|---|---|---|---|---|
| **Liberté d'évolution des 19** | 19 (théorique) mais saturée 16/19 | **meilleure** (Σ planchers 0,060) | **identique à C0** (0 écart) | **meilleure** | **maximale** | inchangée sauf `placeDepart` |
| **Capacité de promotion** | 1/84 (scénario A) | 1/84 | 1/84 | 1/84 | 1/84 | **7/84** |
| **Capacité de rétrogradation** | 1/7 | 1/7 | 1/7 | 1/7 | 1/7 | **7/7** |
| **Vitesse de convergence** | 32 cycles | 32 | 32 | 32 | **25** | **20** |
| **Stabilité** | 0 redescente | 0 | 0 | 0 | 0 | 0 |
| **Saturation** | **16/19** | réduite | identique | réduite | réduite | 16/19 |
| **Risque de domination** | **1,00×** | 1,00× | 1,00× | 1,00× | **1,90× — ÉLEVÉ** | 1,00× |
| **Récupération après silence** | 13 cycles | 13 | 13 | 13 | 10 | 180 (proportionnel) |

### 5.5 Ce que je propose, et pourquoi — avec les valeurs justifiées

| Proposition | Valeur | Justification mesurée | Statut |
|---|---|---|---|
| **P-1. Ne PAS modifier le plancher collectif seul** | — | `G2.4` : 0 écart sur 2850 comparaisons. C2 est inopérante. | **mesuré** |
| **P-2. Ne PAS supprimer le plafond collectif** | garder 0,40 | `G2.2`/C4 : sa suppression produit 78,1 % de part enrichie, 7/7 base rétrogradées, domination **1,90×** | **mesuré** |
| **P-3. Abaisser les planchers individuels des 12 enrichis de 0,01 à 0,005** | 0,005 | Σ passe de 0,160 à 0,060 ; la marge sous le plancher collectif 0,18 passe de **0,020 à 0,120** (×6) ; **aucune régression** de réversibilité (13 cycles), de stabilité (0 redescente), de vitesse (32 cycles) | **mesuré** |
| **P-4. Relever sélectivement le plafond individuel** | à décider | `G3.1`/`G3.3` : c'est **le** verrou en hausse. `placeDepart` 0,07 → 0,30 fait passer son poids de 0,0648 à 0,2610 et ses paires de 1 à 7 | **mesuré, mais valeur à arbitrer** |
| **P-5. Ne PAS toucher aux coefficients d'apprentissage** | inchangés | `A12` : 2–6 cycles pour 50 % de plage ; `G2.5` : 32 cycles. Le gradient n'est pas le frein | **mesuré** |

### 5.6 Ce que P-3 ne résoudra PAS — et il faut le dire

**P-3 ne fera monter AUCUN critère dont la note est constante.** Mesure
`G1.3` : avec discrimination nulle, la part enrichie reste à 0,185444691 quel
que soit le plancher. Un critère sans note ne reçoit aucun gradient.

**⇒ P-3 est une condition NÉCESSAIRE, pas suffisante.** Elle ne produira d'effet
qu'avec l'alimentation (§2.4 : 9 critères non calculés).

### 5.7 Valeur recommandée pour les planchers, et pourquoi 0,005

Trois raisons mesurables :
1. **0,005 = la moitié du plus petit plancher actuel** (0,01). C'est une
   modification **graduée**, pas une suppression. Un plancher nul rendrait un
   critère totalement effaçable, ce qu'aucune mesure ne justifie.
2. **Σ = 0,060** laisse **0,120 de marge** sous le plancher collectif 0,18 au
   lieu de 0,020 — soit **×6**. C'est la marge nécessaire pour qu'une
   hiérarchie interne puisse exister.
3. **Aucune régression mesurée** sur les cinq indicateurs surveillés
   (vitesse 32 cycles, stabilité 0, réversibilité 13, pas de domination).

**Ce que cette valeur n'a PAS** : elle n'est pas optimale. Aucune mesure ne
permet de dire que 0,005 vaut mieux que 0,004 ou 0,008. C'est une valeur
**graduée et prudente**, cohérente avec les mesures, pas un optimum démontré.

---

## 6. L'INCOHÉRENCE DES ÉCHELLES 1,26 / 1,00

### 6.1 Les conditions EXACTES de la mesure 63,40 % / 5,20 %

L'utilisateur exige la précision. Voici le protocole complet, reproductible par
`poids_echelle_consommateurs_test.dart` H1 :

| Paramètre | Valeur |
|---|---|
| Poids A | `IaPoidsAdaptatifs()` **sans** `clamp()` → somme **1,260000000000** |
| Poids B | `IaPoidsAdaptatifs()..clamp()` → somme **1,000000000000** |
| Scores de critères | `Uniform(10,90)` par critère et par partant |
| Graine | `math.Random(424242)` — **déterministe** |
| Partants | 5 à 20 (`5 + alea.nextInt(16)`) |
| Nombre de courses | **2000** |
| Formule | somme pondérée **NON divisée** (`ia_pronostic_engine.dart:391-409`) |
| Normalisation | `_normaliserScores` répliquée (`:224-242`), ratio 0,40/0,60/0,75 |

**Résultat reproduit** (`H1`) :

| Indicateur | Valeur mesurée |
|---|---|
| Classements modifiés | **64,55 %** |
| TOP1 modifié | **5,30 %** |
| TOP3 modifié | **10,90 %** |
| n | 2000 courses |

Les valeurs **63,40 % / 5,20 %** annoncées précédemment et **64,55 % / 5,30 %**
mesurées ici sont **le même phénomène**, à ±2 points près : la différence vient
de la graine et de la génération exacte des scores. **La mesure est reproduite.**

### 6.2 DÉCOUVERTE DÉCISIVE : ce n'est PAS un pur effet d'échelle

Mon rapport précédent affirmait que seule l'échelle différait. **C'est faux, et
c'est important.**

**Mesure `H1`** : les ratios A/B ne valent pas 1,26 uniformément :

| Groupe | Ratio A/B | Uniforme ? |
|---|---|---|
| les **7** critères de base | **1,183333333** | oui (7/7) |
| les **12** critères enrichis | **1,375000000** | oui (12/12) |

**Explication mesurée** : la table 1,26 a une fraction enrichie de
**0,436507937**, que `normaliser()` **écrête à 0,40**. Passer de 1,26 à 1,00
n'est donc pas une homothétie : c'est **échelle × redistribution de 4,35 points
de poids des enrichis vers la base**.

**Conséquence mesurée `H2`** : le rapport `score_A / score_B` **varie** d'un
partant à l'autre, entre **1,233369810** et **1,294257867**, selon la
composition de ses notes. Il n'est **jamais** égal à 1,26.

**⇒ La phrase « 63,40 % des classements changent à cause de l'échelle » est
trompeuse.** La formulation exacte est : *63,40 % changent à cause du couple
(échelle × redistribution), les deux effets étant mesurables séparément.*

### 6.3 Tous les consommateurs de score, et leur sensibilité mesurée

L'utilisateur exige la liste complète. Voici les consommateurs **identifiés
dans le code**, avec leur sensibilité mesurée (`H3`, 2000 courses).

| Consommateur | Fichier:ligne | Ce qu'il consomme | Sensibilité mesurée à l'échelle |
|---|---|---|---|
| **Classement** | `ia_pronostic_engine.dart:103-104` | ordre des scores | **64,55 %** de classements modifiés |
| **Étiquette du TOP1** | `ia_pronostic_engine.dart:642-652` (`_determinerLabel`, seuils **75** et **52**) | `scoreAff` **absolu** | **11,75 %** des étiquettes TOP1 changent |
| **Confiance** | `zt_models.dart:1216-1240` (`confianceIA`) | les 3 premiers scores **absolus** | écart **médian 3,0162 pt**, p95 **5,9128 pt**, max **8,8642 pt** |
| **Seuil de sélection** | `best_bet_screen.dart:592` (`seuilMinScore`) | `top.scoreIA` **absolu** | **0 %** dans cet échantillon (score min jamais atteint) |
| **Score de gain** | `best_bet_screen.dart:605` `(100.0 - top.scoreIA).clamp(20.0, 80.0)` | `scoreIA` **absolu** | **17,00 %** des valeurs modifiées |
| **Score composite** | `best_bet_screen.dart:609` `scoreConf*0.65 + scoreGainRaw*0.35` | dérivé | impact indirect |
| **Seuils appris** | `ia_memory_models.dart:1596-1603` (`IaSeuilsAppris` : 80/50/65/75/60/35/80/0) | comparés à `scoreIA` | consommateurs absolus |
| **TOP3 / score2nd / score3** | `best_bet_screen.dart:629-631` | `sorted[i].scoreIA` | absolu |
| **Affichage IA Performance** | `ia_performance_screen.dart:3186-3197` | seuils appris | affichage |

### 6.4 Le détail qui change la décision

Sur 2000 courses, **le seuil 62 de `best_bet_screen.dart:592` n'a JAMAIS changé
de camp** (0 %). Raison : les scores normalisés par `_normaliserScores` restent
dans une plage où le TOP1 dépasse presque toujours 62.

**⇒ Le risque « un seuil absolu est franchi plus facilement » est RÉEL mais
CIRCONSTANCIÉ** : il touche les étiquettes (11,75 %) et le score de gain
(17 %), pas le filtre de sélection principal sur cet échantillon.

### 6.5 Les trois transformations, mesurées et distinctes

| Code | Définition | Somme | Effet |
|---|---|---|---|
| **T1** | table brute du constructeur | **1,26** | ce que reçoit `poidsEffectifsPourDiscipline` sur une instance non clampée (`H5`) |
| **T2** | `clamp()` puis `normaliser()` | **1,00** | **la production** |
| **T3** | T1 divisée par sa somme (1,26) | **1,00** | « diviser par la somme des poids effectifs » |

**Mesure `H4`** :
- **T2 ≠ T3** : écart maximal sur les 19 poids = **0,012854907**. C'est l'effet
  de l'écrêtage (0,436507937 → 0,40).
- **T2 sur T2** (rediviser une table déjà normalisée) = **no-op exact** :
  0/2000 classements modifiés, écart max **0,000000000000000**.

**⇒ « Diviser par la somme des poids effectifs » a DEUX sens possibles, et ils
ne sont pas équivalents :**
- appliqué à une table **déjà normalisée** : **no-op total** (rien ne change) ;
- appliqué à la table **brute 1,26** : produit T3, qui **diffère** de la
  production T2 de 0,0129 par critère et **change 65,15 % des classements** par
  rapport à T1.

### 6.6 Les solutions comparées — sans toucher la production

| Solution | Description | Rang | Échelle absolue | Verdict |
|---|---|---|---|---|
| **S-rien** | Statu quo : T2 partout, corriger les replis `fromJson` (§1.3) pour qu'aucune table 1,37 ne fuite | inchangé | **100** | **RECOMMANDÉE** |
| **S-diviser-au-score** | Diviser au moment du score par la somme effective | **identique à S-rien quand les poids valent déjà 1,00** (`H4` : no-op exact) ; différent seulement si le repli 1,26 fuite | 100 | **Équivalent fonctionnel à S-rien**, mais ajoute un coût de calcul et **n'élimine pas** la cause (le repli 1,37) |
| **S-normaliser-la-source** | Garantir que tout poids servi est passé par `clamp()` | identique à S-rien | 100 | **Équivalent**, mais agit **à la source** — plus robuste |

### 6.7 Ma recommandation §6, et sa justification mesurée

**Je ne recommande PAS de diviser les scores par la somme des poids.** Mesure
`H4` : sur une table déjà normalisée, c'est un **no-op exact**
(écart 0,000000000000000). Cela n'apporte rien et ajoute un coût.

**Je recommande de corriger la CAUSE** : les trois replis de `fromJson`
(§1.3). Mesure `H6` : c'est **la seule** source d'une table non normalisée en
production (somme 1,37, soit **+37 % sur tous les scores**).

**Ce que je ne propose PAS** : aucune modification des seuils (75, 52, 80, 50,
65, 75, 60, 35, 80, 0, `seuilMinScore`). L'utilisateur l'interdit
explicitement, et aucune mesure ne le justifie : le seuil 62 n'a jamais changé
de camp (0 %).

**Point à valider prospectivement** : l'impact réel de l'échelle sur les
**étiquettes** (11,75 %) et le **score de gain** (17 %) doit être réévalué
**après** la correction des replis, sur données réelles et non synthétiques.
Mes expériences `H1`–`H3` sont **[SYNTH]** et ne remplacent pas cette mesure.

---

## 7. PERTINENCE DES POIDS INITIAUX

### 7.1 Ce qui est mesuré

| Fait | Mesure |
|---|---|
| Les poids initiaux sont **progressivement oubliés** | `A11` : après 5000 cycles à discrimination constante et égale, les 7 de base valent **tous 0,085714286** (= 0,60/7), **malgré des départs allant de 0,02 à 0,25** |
| Le point fixe ne dépend **que des facteurs de gradient** | `A11` : facteur 0,5 → 0,040000 ; 0,4 → 0,032000 ; 0,3 → 0,024000 |
| Le point fixe **ne dépend pas** de la discrimination observée (à discrimination égale) | `A11` |
| Un critère initialement faible **peut devenir le plus fort** | `H3` : `cote` 0,08 → 0,4018 = **×5,02** ; `victoires` 0,04 → 0,1507 = **×3,77** |
| Un critère initialement fort **peut devenir le plus faible** | `H3` : `forme` 0,25 → 0,0588 = **×0,24** |

### 7.2 Pourquoi « oubliés » ne signifie pas « adaptés »

L'utilisateur a raison sur ce point : le fait que les poids initiaux soient
oubliés **ne prouve pas** qu'ils sont bons au démarrage.

**Ce que je peux affirmer** : aucune mesure ne démontre qu'un autre jeu initial
produirait de meilleurs pronostics. C'est une **absence de preuve**, pas une
preuve d'optimalité.

**Ce que je peux affirmer aussi** : les poids initiaux ont une importance
**réelle et brève**. Mesure `G2.5` : il faut **32 cycles** pour qu'un critère
discriminant dépasse la forme initiale. Sur un redémarrage à zéro, les
**32 premières courses** voient donc la pondération initiale dominer.

### 7.3 Comparaison avec les autres configurations étudiées

| Configuration | `forme` | `gains` | `record` | `cote` | Somme |
|---|---|---|---|---|---|
| Constructeur (initiale) | 0,25 | 0,13 | 0,10 | 0,08 | 1,26 |
| `.defauts` | 0,25 | 0,13 | 0,10 | 0,08 | 1,26 |
| `fromJson` (repli) | **0,32** | **0,15** | **0,12** | 0,08 | **1,37** |
| `clampDiscipline` (repli) | 0,38 puis ÷1,55 → 0,2452 | 0,18 → 0,1161 | 0,14 → 0,0903 | 0,13 → 0,0839 | 1,00 |
| Appris 28/05/2026 | **0,14196** | 0,03963 | 0,02972 | **0,38382** | 1,00 |
| Appris 13/11/2026 | **0,05877** | 0,04018 | 0,03014 | **0,40181** | 1,00 |

**Lecture** : les poids initiaux (`forme` 0,25 en tête) sont **très éloignés**
de ce que l'apprentissage produit (`cote` 0,40 en tête, `forme` 0,06). Le
gradient renverse complètement la hiérarchie.

**Mais** : ces valeurs apprises sont **in-sample** et issues d'un corpus de
47 courses exploitables. Elles ne constituent **pas** une cible à viser.

### 7.4 Ma recommandation §7 — conservation provisoire, sans prétendre à l'optimalité

**Je recommande de CONSERVER PROVISOIREMENT les poids initiaux du constructeur
tels quels (0,25 / 0,13 / 0,10 / 0,08 / 0,09 / 0,04 / 0,02 pour la base).**

**Justification** :
1. **Aucune mesure** ne permet de déterminer une meilleure pondération
   initiale : le corpus exploitable est de **47 courses** (mai) et **4**
   (novembre), et l'évaluation est **in-sample**.
2. Les poids initiaux n'ont d'effet que sur les **~32 premières courses**
   (`G2.5`), après quoi le gradient les efface (`A11`).
3. Les modifier reviendrait à **substituer une intuition à une mesure**.

**Ce que cette recommandation N'EST PAS** : elle ne dit **pas** que 0,25 pour
`forme` est optimal. Elle dit qu'**aucune donnée disponible ne justifie de le
changer**, et que le coût d'un changement non prouvé (perturber 32 courses)
dépasse le bénéfice non démontré.

**Ce qui devra être fait après le redémarrage à zéro** : mesurer, sur les
premières 200 courses **hors échantillon**, si une autre pondération initiale
aurait produit un meilleur TOP1/TOP3. C'est le protocole du §8.7.

---

## 8. PROPOSITION DÉCISIONNELLE FINALE

Neuf décisions, chacune avec son fondement mesuré et son statut de preuve.

### 8.1 Quelles valeurs de repli harmoniser

| Décision | Valeur actuelle | Valeur proposée | Fondement mesuré |
|---|---|---|---|
| `fromJson` → `forme` | **0,32** | **0,25** | `M2.1`, `H6` |
| `fromJson` → `gains` | **0,15** | **0,13** | `M2.1`, `H6` |
| `fromJson` → `record` | **0,12** | **0,10** | `M2.1`, `H6` |

**Les TROIS doivent être harmonisées** — c'est la correction complète que
l'utilisateur demandait. Leur somme passe de **1,37** à **1,26**, alignée sur le
constructeur et sur `.defauts`.

**Impact mesuré** : nul sur un JSON complet (les 19 clés sont toujours écrites
par `toJson`). **Non nul** sur une restauration partielle : une table de somme
**1,37** produit des scores **37 % plus élevés**, franchissant plus facilement
les seuils absolus. Mesure `H6` : après un `clamp()` explicite, la somme revient
bien à 1,000000000000.

**Risque** : nul — la valeur harmonisée est celle du constructeur, qui est la
référence. **Statut : MESURÉ, correction sûre.**

**Gain complémentaire, non demandé mais mesuré** : `fromJson` **n'appelle pas
`clamp()`**. Ce n'est pas l'objet de cette décision, mais cela signifie qu'une
restauration partielle livrerait la table à 1,37 **directement au moteur de
score**. C'est la raison pour laquelle l'harmonisation est **nécessaire** et pas
seulement documentaire.

### 8.2 Quels planchers conserver ou modifier

| Élément | Décision | Valeur | Fondement |
|---|---|---|---|
| Planchers individuels des **12 enrichis** | **MODIFIER** | 0,01 → **0,005** (les 3 planchers à 0,02 et 0,03 restent proportionnellement plus hauts, mais descendent aussi si l'on veut Σ = 0,060) | `G1.1` (marge 0,020 → 0,120), `H4` (11/12 figés) |
| Planchers individuels des **7 de base** | **CONSERVER** | inchangés (0,05 / 0,04 / 0,03 / 0,05 / 0,03 / 0,01 / 0,01) | Aucune mesure ne montre qu'ils gênent : `H3` a mesuré `cote` ×5,02 et `victoires` ×3,77 |
| Plancher collectif | **CONSERVER** | **0,18** | `G1.3` : il fonctionne (0,180000000 exactement) ; `G2.4` : l'abaisser seul est sans effet |

**Précision importante sur les 12 planchers enrichis** : ils ne valent pas tous
0,01. Détail mesuré : `distSpec` 0,03, `jockey` 0,02, `mouvCote` 0,02, et les
9 autres 0,01 → **Σ = 0,160**. Ramener **tous** à 0,005 donne **Σ = 0,060**,
soit une marge de **0,120** sous le plancher collectif.

**Statut** : MESURÉ sur les cinq indicateurs. **Aucune régression constatée**
(vitesse 32 cycles, stabilité 0 redescente, réversibilité 13 cycles).

### 8.3 Quelles contraintes collectives conserver ou modifier

| Élément | Décision | Valeur | Fondement |
|---|---|---|---|
| **Plafond collectif** | **CONSERVER À 0,40** | 0,40 | `G2.2`/C4 : sa suppression produit 78,106 % de part enrichie, **7/7** critères de base rétrogradés, domination **1,90×**. C'est un garde-fou **nécessaire**. |
| **Plancher collectif** | **CONSERVER À 0,18** | 0,18 | `G1.3` : il fonctionne ; dans les données réelles il n'est **pas** le frein (0,184417 mesuré) |
| **Écrêtage de la fraction enrichie** | **CONSERVER** | `clamp(0.18, 0.40)` | C'est ce qui produit la redistribution mesurée en §6.2. Le supprimer changerait l'échelle des scores de façon **non mesurée** — refusé faute de preuve. |

**Ce que je NE propose PAS ici** : relever le plafond collectif au-delà de
0,40. Aucune mesure ne le justifie : dans les données réelles la part enrichie
vaut **0,1844**, très loin de 0,40. Relever un plafond qu'on n'atteint jamais
n'aurait aucun effet mesurable.

### 8.4 Comment résoudre l'incohérence des échelles

| Décision | Contenu | Fondement |
|---|---|---|
| **NE PAS diviser les scores par la somme des poids** | Mesure `H4` : sur une table déjà normalisée, c'est un **no-op exact** (0 changement de classement sur 2000 courses) | `H4` |
| **CORRIGER les trois replis `fromJson`** | Ramène toute table à 1,26 puis 1,00 après `clamp()`. C'est **la seule source** d'une échelle non normalisée en production | `H6` |
| **NE PAS modifier les seuils** | Interdit par la consigne ; aucune mesure ne le justifie (`seuilMinScore` 62 : 0 % de changement de camp) | `H3` |
| **VALIDER PROSPECTIVEMENT** l'impact réel sur les étiquettes | `H3` mesure 11,75 % d'étiquettes changées, mais sur données **synthétiques** | `H1`–`H3` sont [SYNTH] |

**Formulation exacte de l'incohérence, corrigée** : il n'y a pas « deux échelles
qui se côtoient » au sens d'un simple facteur 1,26. Il y a :
- une échelle **1,00** (production, après `clamp()`), au ratio base/enrichis **0,60/0,40** ;
- une échelle **1,26** (table brute), au ratio **0,71/0,55** = fraction enrichie **0,436507937** ;
- une échelle **1,37** (repli `fromJson`), qui **fuite** en production sur restauration partielle.

Les deux premières diffèrent par **échelle × redistribution**. La troisième est
un **défaut réel** à corriger.

### 8.5 Des défauts d'alimentation subsistent-ils dans le moteur actuel ?

**Réponse mesurée : AUCUN défaut d'alimentation démontré.**

Sur les 9 critères jamais calculés dans le moteur actuel (`C-19-2`, `C-19-4`) :

| Critère | Cause démontrée | Défaut du moteur ? |
|---|---|---|
| `record`, `jockey`, `entraineur`, `terrain` | **donnée absente** du payload PMU | **NON** |
| `poidsRel` | **non applicable** hors handicap de galop | **NON** |
| `placeDepart` | **non applicable** hors PLAT (corde non fournie) | **NON** |
| `elo` | **base vide** : `✅ 0 ratings restaurés` | **NON** |
| `mouvCote` | **1 seul snapshot** par course, fenêtre 30 min non couverte | **NON** |
| `discipline` | indéterminé / neutre par calcul | **à surveiller** |

**Un seul point reste incertain** : `discipline`. Il n'est pas démontré
défaillant, mais sa neutralité systématique sur 6 spécialités mérite une
vérification dédiée. **Ce n'est pas une correction à faire maintenant** : ce
serait un nouveau chantier, hors périmètre.

**Ce que cela implique pour les décisions 8.2/8.4** : modifier les planchers
(8.2) ne rendra **aucun** de ces 9 critères actif. Il faut d'abord **les
alimenter**. Les deux chantiers sont **indépendants et tous deux nécessaires**.

### 8.6 Ce qui doit rester INCHANGÉ faute de preuve suffisante

| Élément | Décision | Pourquoi |
|---|---|---|
| **Poids initiaux (constructeur)** | **INCHANGÉS** | Aucune donnée ne détermine une meilleure pondération initiale. Corpus exploitable : **47** courses (mai), **4** (novembre), **in-sample** |
| **Coefficients du gradient** (`lrBase` 0,08, `momentumFactor` 0,3, facteurs 1,0/0,5/0,4/0,3) | **INCHANGÉS** | `A12` : 2–6 cycles pour 50 % de plage. Le gradient **n'est pas le frein** |
| **Formule des 19 critères** | **INCHANGÉE** | Interdit par les protections absolues ; aucune mesure ne la met en cause |
| **Seuils appris** (`IaSeuilsAppris` 80/50/65/75/60/35/80/0) | **INCHANGÉS** | Interdit ; aucune mesure ne le justifie |
| **Seuils d'étiquetage** (75 / 52) | **INCHANGÉS** | Interdit ; l'impact mesuré (11,75 %) est **synthétique** |
| **Calibration, TOP3 Learning, mécanismes financiers PMU** | **INCHANGÉS** | Hors périmètre, protections absolues |
| **Mécanisme `poidsParDiscipline`** | **INCHANGÉ** | `M12.3` : effet réel mesuré (1,119 vs 1,200). Le mécanisme fonctionne |
| **Gel sur corrélations** | **INCHANGÉ, NON MESURABLE** | `correlations` est **vide** dans les deux backups ; le seuil de 50 courses n'est pas atteint (47 max) |

### 8.7 Ce qui devra être validé PROSPECTIVEMENT après le redémarrage à zéro

| # | Élément à valider | Protocole | Seuil de décision |
|---|---|---|---|
| **V-1** | Bénéfice réel de **P-3** (planchers 0,005) | Comparer, sur courses **postérieures** à la date T uniquement, TOP1/TOP3 avec planchers 0,01 vs 0,005 | n ≥ **200** courses hors échantillon |
| **V-2** | Bénéfice réel de **P-4** (relèvement des plafonds individuels) | Idem, par critère relevé | n ≥ 200 |
| **V-3** | Impact réel de l'échelle sur les **étiquettes** et le **score de gain** | Rejouer `H3` sur les **scores réels** enregistrés, pas sur `Uniform(10,90)` | tous les pronostics disponibles |
| **V-4** | Meilleure **pondération initiale** | Après le zéro-redémarrage, figer 3 jeux initiaux sur 3 périodes distinctes, comparer hors échantillon | n ≥ 200 par période |
| **V-5** | Effet réel du **gel sur corrélations** | Attendre `nb ≥ 50` **et** `correlations` non vide | r > 0,85 observé |
| **V-6** | `discipline` est-il réellement neutre ? | Instrumenter le calcul sur les 6 spécialités | toute variance non nulle |

**Règle absolue pour toutes ces validations** : **les résultats historiques
in-sample ne constituent JAMAIS une validation indépendante.** Les chiffres E2
(`TOP1 29,79 %` pour les poids appris de mai, sur les 47 courses de mai) sont
**in-sample** et ne sont cités ici que pour montrer l'ordre de grandeur, jamais
comme preuve de supériorité.

### 8.8 Tableau récapitulatif — les 9 décisions

| # | Décision | Valeur | Preuve | Statut |
|---|---|---|---|---|
| 1 | Harmoniser `fromJson` `forme` | 0,32 → **0,25** | `M2.1`, `H6` | **MESURÉ — SÛR** |
| 2 | Harmoniser `fromJson` `gains` | 0,15 → **0,13** | `M2.1`, `H6` | **MESURÉ — SÛR** |
| 3 | Harmoniser `fromJson` `record` | 0,12 → **0,10** | `M2.1`, `H6` | **MESURÉ — SÛR** |
| 4 | Planchers individuels des 12 enrichis | 0,01 → **0,005** | `G1.1`, `G2.4`, `H4`, `G2.3` | **MESURÉ — À ARBITRER** |
| 5 | Plafond individuel sélectif | **à décider par critère** | `G3.1`, `G3.3` | **MESURÉ — VALEUR À ARBITRER** |
| 6 | Plancher collectif 0,18 | **CONSERVER** | `G1.3`, `G2.4` | **MESURÉ** |
| 7 | Plafond collectif 0,40 | **CONSERVER** | `G2.2`, C4 | **MESURÉ** |
| 8 | Division des scores par la somme | **NE PAS FAIRE** (no-op mesuré) | `H4` | **MESURÉ** |
| 9 | Poids initiaux, gradient, seuils, formules | **INCHANGÉS** | Absence de preuve | **CONSERVATION PROVISOIRE** |

### 8.9 Ce que je refuse de proposer, et pourquoi

- **Je ne propose pas un jeu de poids « optimal ».** Le corpus ne le permet pas
  (47 + 4 courses, in-sample).
- **Je ne propose aucune modification de seuil** pour compenser l'échelle :
  l'utilisateur l'interdit et aucune mesure ne le justifie.
- **Je ne propose pas de supprimer le plafond collectif** : `C4` mesure une
  domination de 1,90× et 7/7 critères de base rétrogradés.
- **Je ne propose pas de toucher aux coefficients d'apprentissage** : `A12`
  démontre qu'ils ne sont pas le frein.
- **Je ne prétends pas que P-3 améliorera les pronostics.** P-3 rend
  l'apprentissage **possible** ; elle ne le rend pas **efficace** sans
  alimentation.

---

## 9. TRAÇABILITÉ — OÙ CHAQUE CHIFFRE EST REPRODUCTIBLE

| Harnais | Tests | Ce qu'il établit |
|---|---|---|
| `test/audit_poids_familles_test.dart` | 20 | Sommes des 4 familles, **les 3 divergences** (`M2.1`), replis (`M3`) |
| `test/audit_poids_mecanique_test.dart` | 7 | `placeDepart` vs `forme`, contre-factuels (`M9`/`M10`) |
| `test/audit_poids_disciplines_test.dart` | 6 | `M11`/`M12`, coexistence 1,26/1,00 par discipline |
| `test/audit_poids_comparaison_test.dart` | 4 | `M13`, actuel vs historique |
| `test/audit/poids_plage_atteignable_test.dart` | 12 | `A0` (garde), `A3` (0/342), `A11` (point fixe), `A12` (vitesse), `A9` |
| `test/audit/poids_echelle_test.dart` | 3 | `C1` (classements), `C2`, `C3` (score max 126) |
| `test/audit/poids_limite_structurelle_test.dart` | 4 | `H1`–`H4` sur backups réels |
| `test/audit/poids_comparaisons_reelles_test.dart` | 4 | `E1`–`E4`, corpus réel |
| **`test/audit/poids_contraintes_test.dart`** | **12** | **`G0` (garde 7600 comparaisons), `G1.1`–`G1.3` (planchers/collectif/gradient), `G2.1`–`G2.5` (5+1 configurations), `G3.1`–`G3.3` (déblocage réel)** |
| **`test/audit/poids_echelle_consommateurs_test.dart`** | **6** | **`H1`–`H6` : conditions exactes, ratios 1,1833/1,3750, consommateurs, 3 transformations, réplique de discipline, `fromJson` 1,37** |
| `test/audit/chaine_19_criteres_isolate_test.dart` | 5 | `C-19-1`..`4` : **10/19** critères calculés, 6 spécialités |

**Total mesuré par exécution : `00:32 +83: All tests passed!` — 83 tests verts,
0 échec** sur les **11** harnais listés ci-dessus, lancés ensemble avec `-j 1`.

**Détail du calcul** : 20 + 7 + 6 + 4 + 12 + 3 + 4 + 4 + 12 + 6 + 5 = **83**.
`flutter analyze` sur chacun des deux nouveaux harnais → **`No issues found!`**

**Point de méthode** : j'ai d'abord écrit « 78 tests » dans une version
antérieure de ce tableau, en recomposant de mémoire. Le décompte exact par
`grep -cE "^\s*(test|testWidgets)\("` puis par **exécution réelle** donne
**83**. C'est la valeur retenue.

**Aucune production modifiée.** Aucun push. Aucun APK. Aucun recalcul
historique. Aucun reset. Aucune sauvegarde modifiée. Aucune donnée fabriquée.

---

## 10. RÉSERVE FINALE — CE QUE CE RAPPORT NE PROUVE PAS

1. **Rien sur la qualité réelle des pronostics.** n = 47 (mai) et 4 (novembre),
   **in-sample**. Les chiffres `E2` décrivent un échantillon ; ils **ne
   valident pas** le modèle. La référence « cote seule » atteint le même TOP1
   (29,79 %), ce qui **borne** l'apport démontré des 19 critères.
2. **Rien sur le Cross-country** (9 cas) ni sur les interactions entre critères.
3. **Rien sur les corrélations** : `correlations` est **vide** dans les deux
   backups, et le gel exige 50 courses (47 disponibles au maximum).
4. **Rien sur les appareils physiques** : ces harnais sont des tests Dart, pas
   des mesures sur Android.
5. **Les expériences `G*` et `H1`–`H3` sont [SYNTH]** : elles démontrent des
   **propriétés du mécanisme**, pas le comportement sur des courses hippiques
   réelles. Seuls `E1`–`E4`, `H1`(données de backup), `H2`(`H4` structurel),
   `C-19-*` et `G1.2`/`G1.3` portent sur des données réelles.
6. **La promotion de `cote` à 0,40 n'est PAS prouvée bénéfique.** Elle est
   mesurée comme **conséquence du mécanisme**. « Cote seule » atteignant le même
   TOP1, l'apport des 18 autres critères **n'est pas démontré**.
7. **P-3 n'améliorera pas les pronostics à elle seule.** Elle rend
   l'apprentissage **possible** ; sans alimentation des 9 critères neutres, elle
   ne rend rien **efficace**.
8. **Aucune valeur proposée n'est optimale.** 0,005 est une valeur **graduée et
   prudente**, justifiée comme amélioration mesurée, pas comme optimum.

---

# §11 — CORRECTIONS APPLIQUÉES (27/11/2026)

Cette section est le **rapport consolidé unique** demandé au §9 de l'arbitrage.
Elle décrit l'état du code **après** corrections. Les §0 à §10 décrivent l'état
**avant** et sont conservés comme constat historique.

## 11.1 — Modifications exactes effectuées

### A. §1 — Harmonisation des trois replis `fromJson`

**Fichier** : `lib/services/ia_memory_models.dart`, factory `fromJson`.

| Clé | Avant | Après | Écart supprimé |
|---|---|---|---|
| `forme` | `?? 0.32` | `?? 0.25` | −0,07 |
| `gains` | `?? 0.15` | `?? 0.13` | −0,02 |
| `record` | `?? 0.12` | `?? 0.10` | −0,02 |
| **Total** | **1,37** | **1,26** | **−0,11** |

Les **16 autres replis sont inchangés** (vérifié par `S1.9`).

**Portée stricte du changement** — elle a été mesurée, pas supposée :

| Cas | Comportement |
|---|---|
| Clé absente du JSON | repli appliqué (0,25 / 0,13 / 0,10) |
| Clé présente à `null` | repli appliqué |
| Clé présente numérique | **valeur reprise telle quelle**, aucun arrondi |
| Clé présente non numérique (`String`) | **`TypeError`** — le repli n'est PAS appliqué |

> ⚠️ **Correction d'une affirmation que j'avais écrite dans le code.**
> J'avais commenté que le repli jouait « aussi si la valeur est non numérique ».
> **C'est faux, et c'est mesuré** (`S1.4`) : `(j['forme'] as num?)` ne renvoie
> `null` que sur absence ou `null` explicite ; sur une `String`, le cast lève
> `type 'String' is not a subtype of type 'num?'` et `fromJson` échoue
> **entièrement**. Un JSON corrompu n'est donc **pas** toléré — ni avant, ni
> après cette correction. Comportement **préexistant, laissé inchangé**, et
> signalé pour arbitrage (§11.6, décision D-3) plutôt que corrigé sans
> autorisation.

### B. §2 — Abaissement des douze planchers individuels enrichis

Les **douze** planchers passent à **0,005**. Les valeurs de départ n'étaient
**pas** toutes égales à 0,01 — c'était le point d'attention de l'utilisateur, et
il était fondé :

| Critère | Plancher avant | Plancher après | Plafond (inchangé) |
|---|---|---|---|
| `distSpec` | **0,03** | 0,005 | 0,18 |
| `jockey` | **0,02** | 0,005 | 0,15 |
| `mouvCote` | **0,02** | 0,005 | 0,12 |
| `repos` | 0,01 | 0,005 | 0,08 |
| `hippo` | 0,01 | 0,005 | 0,10 |
| `entraineur` | 0,01 | 0,005 | 0,08 |
| `elo` | 0,01 | 0,005 | 0,10 |
| `terrain` | 0,01 | 0,005 | 0,10 |
| `divergence` | 0,01 | 0,005 | 0,08 |
| `poidsRel` | 0,01 | 0,005 | 0,07 |
| `progression` | 0,01 | 0,005 | 0,08 |
| `placeDepart` | 0,01 | 0,005 | 0,07 |
| **Σ** | **0,160** | **0,060** | 1,210 |

**Trois définitions dupliquées** — et il y en avait **trois**, pas deux :

| # | Emplacement | Rôle | Traitement |
|---|---|---|---|
| 1 | `ia_memory_models.dart` `clamp()` | sortie standard du gradient | **modifiée** |
| 2 | `ia_memory_models.dart` `clampDiscipline()` | sortie par discipline | **modifiée** |
| 3 | `ia_memory_service.dart` `_mettreAJourPrecisionIA()` | piste « stats par label », 4 critères (`divergence`, `terrain`, `progression`, `poidsRel`) | **modifiée** |

La définition #3 est **réellement atteinte en production** : `_mettreAJourPrecisionIA`
est appelée sans `apprendre: false` en `ia_memory_service.dart:5240`, donc avec
la valeur par défaut `true`. La laisser à 0,01 aurait rendu la correction **non
uniforme** — exactement ce que l'utilisateur voulait éviter en parlant de
« définitions dupliquées ».

**Effet sur la marge de répartition** :

| Grandeur | Avant | Après |
|---|---|---|
| Σ planchers enrichis | 0,160 | **0,060** |
| Plancher collectif enrichi | 0,18 | 0,18 |
| **Marge de liberté** | **0,020** | **0,120** (×6) |

> **Ce que cela NE prouve PAS** : aucune amélioration de la précision hippique.
> C'est une augmentation de liberté mathématique laissée au gradient. Le §8 du
> protocole prospectif reste la seule voie de mesure du bénéfice réel.

### C. Ce qui n'a PAS été modifié

- Poids initiaux : 19/19 identiques (vérifié `S2.8`).
- Plafonds individuels : 19/19 identiques (vérifié `S2.4`). **La proposition
  `placeDepart` 0,07 → 0,30 a été refusée et n'a pas été appliquée.**
- Contraintes collectives `clamp(0.18, 0.40)` : intactes (vérifié `S2.8`, `T7d`).
- Gradient descent : `lrBase 0.08`, `momentumFactor 0.3`, tous les facteurs par
  critère — intacts (vérifié `T7d`).
- Seuils, calibration, TOP3 Learning, ELO, mécanismes PMU : intacts.
- `_normaliserScores`, `_determinerLabel` : intacts.
- Sauvegardes originales : non touchées (lecture seule).

## 11.2 — Résultats des tests

**110 tests verts, 0 échec.** `flutter analyze lib/ test/` → `No issues found!`

| Harnais | Tests | État |
|---|---|---|
| `audit_poids_familles_test.dart` | 20 | ✅ (3 assertions mises à jour, voir 11.3) |
| `audit_poids_mecanique_test.dart` | 7 | ✅ |
| `audit_poids_disciplines_test.dart` | 6 | ✅ |
| `audit_poids_comparaison_test.dart` | 4 | ✅ |
| `poids_plage_atteignable_test.dart` | 12 | ✅ |
| `poids_echelle_test.dart` | 3 | ✅ |
| `poids_limite_structurelle_test.dart` | 4 | ✅ |
| `poids_comparaisons_reelles_test.dart` | 4 | ✅ |
| `poids_contraintes_test.dart` | 12 | ✅ |
| `poids_echelle_consommateurs_test.dart` | 6 | ✅ (1 assertion mise à jour) |
| `chaine_19_criteres_isolate_test.dart` | 5 | ✅ |
| **`poids_harmonisation_replis_test.dart`** | **18** | ✅ **neuf** |
| **`poids_plafonds_contrat_test.dart`** | **9** | ✅ **neuf** |
| **TOTAL** | **110** | **✅** |

> La suite complète des 3689 tests **n'a pas été relancée** : l'utilisateur l'a
> explicitement réservée à la clôture définitive (§7).

## 11.3 — Assertions mises à jour, et pourquoi ce n'est pas un contournement

Trois assertions **verrouillaient les anciennes valeurs**. Elles ont été mises à
jour en **conservant la trace de l'état antérieur**, avec la raison écrite dans
le test. Il faut le dire clairement pour que personne ne puisse croire à un
affaiblissement de test :

| Test | Avant | Après | Raison |
|---|---|---|---|
| `M1.3` (familles) | `Σ fromJson({}) == 1.37` | `== 1.26` | le test **constatait un défaut** ; le défaut est corrigé |
| `M3.2` (familles) | `forme == 0.32`, `gains == 0.15`, `record == 0.12` | `0.25 / 0.13 / 0.10` | idem |
| `M3.3` (familles) | `Δ forme > 0` | `|Δ forme| < 1e-12` | **inversion** : le repli ne doit plus dévier |
| `H6` (échelle) | `Σ == 1.37` | `== 1.26` | idem |
| `M6.1` (familles) | bornes enrichies 0,03/0,02/0,01 | 0,005 | reflet de §2 |

**Aucune règle de lint n'a été désactivée. Aucun `ignore` ajouté pour masquer un
diagnostic. Aucun fichier exclu de l'analyse. Aucun test supprimé.** Les deux
nouveaux harnais **renforcent** la couverture : ils testent des cas que rien ne
couvrait (JSON partiel par clé, ancienne sauvegarde, sauvegarde apprise,
aller-retour, réactivation après neutralité, contrat mathématique).

## 11.4 — Tableau des 19 critères (§3)

Plafond **accessible** = valeur obtenue après `clamp()` quand ce critère seul est
poussé à son plafond et **tous les autres à leur plancher** (mesure `T1`).

| Critère | Groupe | Plancher av. | Plancher ap. | Plafond | Plafond ACCESSIBLE | Bridé par |
|---|---|---|---|---|---|---|
| `forme` | base | 0,05 | 0,05 | 0,55 | **0,626389** | collectif base |
| `gains` | base | 0,04 | 0,04 | 0,40 | **0,565517** | collectif base |
| `record` | base | 0,03 | 0,03 | 0,35 | **0,531481** | collectif base |
| `cote` | base | 0,05 | 0,05 | 0,40 | **0,575439** | collectif base |
| `constance` | base | 0,03 | 0,03 | 0,25 | **0,465909** | collectif base |
| `victoires` | base | 0,01 | 0,01 | 0,15 | **0,341667** | collectif base |
| `discipline` | base | 0,01 | 0,01 | 0,10 | **0,264516** | collectif base |
| `distSpec` | enrichi | 0,03 | **0,005** | 0,18 | **0,306383** | collectif enrichis |
| `jockey` | enrichi | 0,02 | **0,005** | 0,15 | **0,292683** | collectif enrichis |
| `repos` | enrichi | 0,01 | **0,005** | 0,08 | **0,225352** | collectif enrichis |
| `hippo` | enrichi | 0,01 | **0,005** | 0,10 | **0,258065** | collectif enrichis |
| `entraineur` | enrichi | 0,01 | **0,005** | 0,08 | **0,225352** | collectif enrichis |
| `elo` | enrichi | 0,01 | **0,005** | 0,10 | **0,258065** | collectif enrichis |
| `terrain` | enrichi | 0,01 | **0,005** | 0,10 | **0,258065** | collectif enrichis |
| `divergence` | enrichi | 0,01 | **0,005** | 0,08 | **0,225352** | collectif enrichis |
| `poidsRel` | enrichi | 0,01 | **0,005** | 0,07 | **0,202899** | collectif enrichis |
| `progression` | enrichi | 0,01 | **0,005** | 0,08 | **0,225352** | collectif enrichis |
| `mouvCote` | enrichi | 0,02 | **0,005** | 0,12 | **0,274286** | collectif enrichis |
| `placeDepart` | enrichi | 0,01 | **0,005** | 0,07 | **0,202899** | collectif enrichis |

### Les trois constats que ce tableau impose

**1. Plafond nominal ≠ plafond accessible : 19/19 dépassés.**
Chaque critère peut effectivement dépasser son plafond nominal **dans le coin**
où tous les autres sont à leur plancher. Mais le coefficient multiplicateur est
modeste (×1,14 pour `forme`, ×2,90 pour `poidsRel`), et il décroît quand les
autres critères remontent. **Ce n'est donc pas une « domination sans limite »** :
c'est la conséquence arithmétique de la renormalisation à somme 1 quand le
dénominateur est minimal.

**2. Le vrai brideur n'est pas le plafond individuel, c'est le plafond collectif.**
Un critère seul ne peut pas dépasser ~0,20–0,63 selon son groupe. C'est la
contrainte `0,18 / 0,40` qui détermine la part maximale du groupe, pas la borne
individuelle.

**3. Une proposition de relèvement de plafond n'est PAS justifiée par ces mesures.**
`placeDepart` à 0,07 est bridé, mais **`poidsRel` l'est davantage** (0,2029
accessible), et **tous** les enrichis sont bridés de la même façon. Relever un
seul plafond traiterait un symptôme, pas la cause — la cause étant la contrainte
collective de 0,40 sur les douze enrichis. **Je ne propose donc aucun relèvement
de plafond** ; la décision de refus de l'utilisateur est cohérente avec la mesure.

## 11.5 — Défaut de cohérence de `clamp()` (§4)

### Ordre réel des opérations — mesuré, pas déduit

`clamp()` (`ia_memory_models.dart:752-778`) :

1. **19 planchers individuels** puis **19 plafonds individuels** (`clamp` Dart).
2. **`normaliser()`** — qui applique, dans cet ordre :
   a. calcul de `fractionEnrichi = totalEnrichi / totalAll` ;
   b. **contrainte collective** `fractionEnrichi.clamp(0.18, 0.40)` ;
   c. **mise à l'échelle des deux groupes** par `target / total`.
3. **`clampDiscipline()`** pour chaque discipline :
   a. 19 bornes individuelles ;
   b. **division par le total des 19**.

**Le point décisif : l'étape 2 vient APRÈS l'étape 1.** Les bornes individuelles
sont appliquées **avant** la contrainte collective, jamais après. Elles sont donc
systématiquement susceptibles d'être écrasées.

### Le dépassement n'est pas systématique — deux mesures opposées

J'avais d'abord écrit « un critère au plafond ressort au-dessus de son plafond ».
**Mesure contredisante (`T2a`)** : avec tous les autres critères à leurs valeurs
d'usine, `cote = 0,40` ressort à **0,236686390533**, donc **très en dessous**.

Le dépassement existe, mais seulement dans un **coin** de l'espace (`T2a`) :
`cote` au plafond avec **tous les autres au plancher** ressort à
**0,575438596491** > 0,40. C'est ce coin que `T1` explore pour les 19 critères.

### Preuve en production

La sauvegarde réelle du **13/11/2026** contient **déjà** les deux violations,
sans aucune intervention de ma part (`T2b`) :

```
cote      = 0.401813880733  > plafond 0,40
victoires = 0.150680205275  > plafond 0,15
```

### Dérive sans apprentissage — et son ampleur réelle après §2

En partant de cette sauvegarde et en appelant `clamp()` **sans aucun gradient** :

| Passes | Part enrichie |
|---|---|
| 0 (sauvegardée) | 0,184840837400 |
| 1 | 0,180000000000 |
| 10 | 0,180000000000 |
| 500 (point fixe) | 0,180000000000 |

**Amplitude de dérive : 0,004840837400, soit 2,6189 % de la part enrichie.**
Elle est **réelle** et **converge** (pas d'oscillation).

> **★ Effet structurel de §2, mesuré et à ne pas cacher.** Le point fixe a
> **changé** avec l'abaissement des planchers :
>
> | | Avant §2 | Après §2 |
> |---|---|---|
> | Part enrichie au point fixe | 0,185444691312 | **0,180000000000** |
> | `cote` au point fixe | 0,400000000000 (**saturée**) | 0,342084344963 (sous le plafond) |
> | `victoires` au point fixe | 0,150000000000 (**saturée**) | 0,128281629361 (résorbé) |
>
> Autrement dit : **la réduction des planchers fait mordre le plancher collectif
> de 0,18, qui ne mordait pas avant.** C'est un effet réel et vérifiable, pas
> cosmétique. Il n'est **pas** une amélioration prouvée de précision hippique.

### Chemins de production réellement concernés

| Ligne | Appel | Sortie de | Gradient ? |
|---|---|---|---|
| `ia_memory_service.dart:4093` | `_poids.clamp()` | `_apprendreParGradient` | oui |
| `ia_memory_service.dart:4288` | `clampDiscipline()` | `_apprendreParDiscipline` | oui |
| `ia_memory_service.dart:4507` | `_poids.clamp()` | `_apprendreReglesBase` | oui |
| `ia_memory_service.dart:6015` | `_poids.normaliser()` | `_mettreAJourPrecisionIA` | oui (`apprendre: true`) |
| `ia_memory_service.dart:6008-6011` | 4 × `.clamp(0.005, …)` | idem | oui |

**La dérive ne peut donc se produire que dans un cycle d'apprentissage**, jamais
à la lecture.

### Distinction poids sauvegardés / poids nouveaux — vérifiée par lecture de source

`fromJson` ne contient **aucun** `clamp()` et **aucune** normalisation (vérifié
`T6`, commentaires filtrés). Conséquence :

- **Poids sauvegardés** → restitués **à l'identique**, y compris s'ils violent
  leurs bornes. C'est ce que `S1.7` et `S2.7` prouvent sur les deux sauvegardes
  réelles : 19/19 valeurs intactes, et les violations de `cote`/`victoires` du
  13/11 sont **préservées**, pas « réparées en douce ».
- **Poids nouveaux** → passent par l'une des cinq sorties ci-dessus, donc sont
  projetés.

### Contrat mathématique attendu

Lorsque les contraintes sont compatibles (`Σ planchers ≤ budget ≤ Σ plafonds`),
un `clamp()` devrait garantir :

| # | Clause | Exigence |
|---|---|---|
| C1 | Somme | `Σ = 1` à `1e-9` près (tolérance documentée) |
| C2 | Bornes individuelles | `plancher_k ≤ w_k ≤ plafond_k` pour les 19 |
| C3 | Contraintes collectives | `0,18 ≤ part enrichie ≤ 0,40` |
| C4 | Valeurs finies | aucun `NaN`, `±∞`, ni valeur négative |
| C5 | Idempotence | `clamp(clamp(x)) = clamp(x)` à `1e-12` |
| C6 | Conservation | si `x` satisfait déjà C1–C3, `clamp(x) = x` à `1e-12` |

### Solution candidate — isolée, NON appliquée, soumise à arbitrage

**Principe** : « projection à budgets de groupe et remplissage par écumoire »
(*group-budget projection + water-filling*). Écrite dans le **test uniquement**,
sous le nom `_Projection`, **jamais dans `lib/`** (vérifié par `T3a` : 0
occurrence dans les 158 fichiers `.dart` de `lib/`).

Algorithme en 4 étapes :

1. **Bornes individuelles** sur les 19 (avec repli au plancher si `NaN`/`∞`).
2. **Part collective visée** = part courante, ramenée dans `[0,18 ; 0,40]`.
3. **Budgets de groupe** : `budgetEnrichi = part`, `budgetBase = 1 − part` — leur
   somme vaut 1 **par construction**.
4. **Remplissage par écumoire sur chaque groupe** : trouver `λ` tel que
   `Σ_k clip(λ·w_k, plancher_k, plafond_k) = budget`. La fonction `λ ↦ Σ` est
   croissante et continue ⇒ solution **unique** dès que
   `Σ planchers ≤ budget ≤ Σ plafonds`. Recherche par dichotomie (400 itérations,
   précision `~1e-120`), puis correction résiduelle exacte répartie sur les seuls
   critères **non saturés**.

**Faisabilité démontrée** (`T3`, `T4`, `T5`) :

| Preuve | Résultat |
|---|---|
| Contrat sur l'état réel du 13/11 (qui viole ses bornes) | **0 violation** — Σ = 1,000000000000, part = 0,180000000000 |
| Contrat sur 400 tables aléatoires | **400 / 400** respectent C1–C4 |
| Idempotence, 1 → 2 passes | écart max **0,000000000000** |
| Idempotence, 1 → 10 passes | écart max **0,000000000000** |
| Idempotence sur 400 tables × 2 passages | écart max **0,000000000000** |
| Conservation d'une table déjà conforme | écart max **0,000000000000** |
| Isolement | **0** occurrence dans `lib/` |

**Ce qu'elle coûterait** : un critère **exactement au plafond** resterait au
plafond (point fixe en bord) au lieu d'être dilué par la renormalisation. Elle
change donc la répartition effective à la marge, ce qui **n'est pas neutre** pour
les scores. **Elle n'est PAS autorisée en production** et requiert un arbitrage
explicite (§11.6, décision D-1).

## 11.6 — Décisions restant à arbitrer

| # | Décision | Pourquoi elle n'est pas prise d'office |
|---|---|---|
| **D-1** | Adopter la projection de `clamp()` (§11.5) | Dépasse la simple harmonisation de constantes autorisée en §1/§2. L'utilisateur a exigé une soumission à arbitrage. |
| **D-2** | Uniformiser les **plafonds** de la 3ᵉ définition (`ia_memory_service.dart:6008-6011`) | Pour `divergence`, cette piste autorise **0,10** alors que `clamp()` plafonne à **0,08** (et `terrain` : 0,10 vs 0,10 ; `progression` 0,08/0,08 ; `poidsRel` 0,07/0,07). **Seul `divergence` diverge.** Ce sont des **plafonds**, donc hors du champ de l'autorisation §2, et §3 interdit toute modification de plafond. |
| **D-3** | Tolérer un JSON de poids corrompu (valeur texte) | `fromJson` lève un `TypeError` et échoue entièrement. Comportement préexistant, non couvert par §1 (qui ne concerne que les replis sur valeurs **absentes**). |

## 11.7 — Conséquences sur les données existantes

| Donnée | Conséquence |
|---|---|
| Sauvegarde 28/05/2026 (802 maj, base 0,820000000000 / enr. 0,180000000000) | **Restituée à l'identique**, 19/19 (`S1.6`) |
| Sauvegarde 13/11/2026 (3871 maj, base 0,815583119656 / enr. 0,184416880344) | **Restituée à l'identique**, 19/19 (`S1.7`) |
| Poids historiques sous le nouveau plancher | **Aucune remontée rétroactive** : `fromJson` ne clampe pas (`S2.7`) |
| Pronostics archivés | **Aucune lecture, aucune écriture** |
| Prochain cycle d'apprentissage | Appliquera les **nouveaux** planchers — c'est l'effet voulu |
| Recalcul historique | **Aucun** |
| Reset | **Aucun** |

**Point d'honnêteté** : la correction **changera** les poids que produira le
prochain apprentissage, par rapport à ce qu'aurait produit l'ancienne
configuration. Ce n'est **pas** une modification rétroactive — les poids déjà
enregistrés sont intacts — mais c'est une **rupture de continuité** sur les
prochains poids produits. Elle doit être connue avant le redémarrage à zéro.

## 11.8 — Protections vérifiées

| Protection | Vérification | Résultat |
|---|---|---|
| Poids initiaux (19) | `S2.8` | 19/19 identiques |
| Plafonds individuels (19) | `S2.4`, `T1` | 19/19 identiques |
| Contraintes collectives 0,18/0,40 | `S2.8`, `T7d` | intactes |
| Gradient descent (lrBase 0,08, momentum 0,3, facteurs) | `T7d` | intacts |
| `_normaliserScores` | aucun diff | intact |
| Seuils / calibration / TOP3 / ELO / PMU | aucun diff | intacts |
| Sauvegardes originales | lecture seule | non modifiées |
| `ignore` / lint désactivé / fichier exclu | `flutter analyze` | **0 issue**, aucun `ignore` ajouté pour masquer |
| Aucun test supprimé | inventaire | 110 tests, tous verts |
| Branche | `git status` | `main` uniquement |
| Push GitHub / APK / reset | non exécutés | aucun |

## 11.9 — Fichiers modifiés et commit

| Fichier | Nature |
|---|---|
| `lib/services/ia_memory_models.dart` | **production** — §1 (3 replis) + §2 (2 définitions de planchers) |
| `lib/services/ia_memory_service.dart` | **production** — §2 (3ᵉ définition de planchers, 4 critères) |
| `test/audit/poids_harmonisation_replis_test.dart` | **neuf** — 18 tests (§1 et §2) |
| `test/audit/poids_plafonds_contrat_test.dart` | **neuf** — 9 tests (§3, §4, §6, §7) |
| `test/audit_poids_familles_test.dart` | 5 assertions mises à jour |
| `test/audit/poids_echelle_consommateurs_test.dart` | 1 assertion mise à jour (H6) |
| `test/audit/RAPPORT_DECISIONNEL_POIDS_IA.md` | ce rapport |

**Commit local** : voir le hash rapporté en fin de conversation (branche `main`,
aucun push).

## 11.10 — Ce que ces corrections ne prouvent PAS

1. **Aucune amélioration de précision hippique** n'est démontrée. Réduire un
   plancher augmente la liberté du gradient ; cela ne dit rien du résultat.
2. **La part enrichie ne montera pas par décret.** Elle vaut 0,180000000000 au
   point fixe — c'est-à-dire **exactement le plancher collectif**. La marge
   libérée (0,120) est une **possibilité**, pas un mouvement observé. Le groupe
   enrichi manquait de **signal**, pas de permission — constat inchangé du §4.
3. **La dérive de `clamp()` subsiste** (2,6189 %) tant que D-1 n'est pas tranchée.
4. **La dilatation d'échelle 1,26 → 1,00 subsiste** : elle est **expliquée**
   (§11.11) mais **non corrigée**, et le §6 interdisait de la corriger.
5. **Aucune mesure sur corpus réel** n'a été refaite ici : n=47 (mai) et n=4
   (novembre) restent trop petits pour conclure quoi que ce soit.
6. **Le chantier n'est pas clos** : D-1, D-2, D-3 sont ouvertes.

## 11.11 — §6 : cohérence d'échelle après harmonisation (mesurée)

Six chemins de production, mesurés (`T8`) :

| Chemin | Σ |
|---|---|
| A — constructeur brut | 1,260000000000 |
| B — `fromJson({})` | 1,260000000000 |
| C — aller-retour | 1,260000000000 |
| D — après `clamp()` | 1,000000000000 |
| E — `poidsEffectifsPourDiscipline` (19 clés) | 1,260000000000 |
| F — `clampDiscipline()` | 1,000000000000 |

**Les 4 chemins « bruts » sont cohérents entre eux (1,26). Les 2 chemins
« normalisés » sont cohérents entre eux (1,00).** Il n'existe **aucun** troisième
niveau d'échelle.

**L'écart 1,26 → 1,00 est entièrement expliqué, et il est plus petit qu'annoncé :**

> ⚠️ **Seconde correction d'une affirmation fausse.** J'avais écrit que passer de
> 1,26 à 1,00 **dilatait** la base d'un facteur 1,183333. **Mesure exacte** :
> ```
> base     0,710000000000 → 0,600000000000 = ×0,845070422535
> enrichis 0,550000000000 → 0,400000000000 = ×0,727272727273
> ```
> **Les deux facteurs sont INFÉRIEURS à 1.** `normaliser()` ne dilate rien : la
> table 1,26 a une fraction enrichie de `0,550/1,26 = 0,436507937`, **écrêtée à
> 0,40** ; la base est donc **contractée** à 0,60 et les enrichis à 0,40. C'est
> une **contraction inégale** (écart entre les deux facteurs : 0,117797695), et
> c'est précisément la raison mesurée pour laquelle le rapport de score entre
> deux partants **varie** au lieu de valoir 1,26.

**Conclusion §6** : après l'harmonisation §1, il ne subsiste **aucune incohérence
d'échelle non expliquée**. L'écart 1,26 / 1,00 est documenté, chiffré, et sa
cause est nommée. Le §6 interdisait de le corriger — il n'a pas été corrigé.
La dilatation maximale possible est passée de **37 % à 26 %** simplement par la
correction §1, sans toucher à la formule.

## 11.12 — §5 : veille « alimentation des critères » (aucune action)

Conservé tel quel, sans réouverture du chantier, conformément à l'arbitrage :

- données réellement absentes ;
- critères non applicables par spécialité ;
- disponibilité des connaissances ELO après accumulation ;
- snapshots nécessaires au mouvement de cote ;
- comportement du critère `discipline`, **toujours indéterminé** ;
- consultation effective des archives ;
- disponibilité réelle des données PMU.

**Aucune donnée artificielle. Aucune formule modifiée pour rendre un critère
artificiellement discriminant.**

## 11.13 — §8 : protocole prospectif préservé (aucun reset)

Protocole **inchangé**, à appliquer **après** le futur redémarrage à zéro :

- pronostics enregistrés **avant** les résultats ;
- échantillons **chronologiques indépendants** ;
- comparaison à la **cote PMU seule** ;
- comparaison à la **configuration de référence** ;
- mesures **globales et par discipline** ;
- évolution des **19 poids** ;
- **saturation aux bornes** (désormais 0,005 en bas) ;
- **TOP1 / TOP3 / TOP5**, calibration, rentabilité officielle lorsque mesurable.

**Le seuil de 200 courses est un premier point de contrôle, pas une garantie de
puissance statistique.** Aucun reset effectué.

## 11.14 — État de clôture

**Le chantier n'est PAS clos.** Les corrections §1 et §2 sont **appliquées,
testées et vertes**, mais trois décisions structurantes restent ouvertes
(D-1, D-2, D-3), et le bénéfice hippique réel n'est **pas** mesuré — il ne peut
l'être qu'après le redémarrage à zéro, par le protocole §11.13.

**BLOC 2 : suspendu. BLOC 3 : non commencé.** Aucun push, aucun APK, aucun reset.
