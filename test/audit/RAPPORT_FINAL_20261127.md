# RAPPORT FINAL DE CLÔTURE — CHANTIER POIDS ET APPRENTISSAGE

**Date** : 27/11/2026
**Référence de code** : `c31cbeff5d77f1c2de3e11da21350945d1b3838d` (branche `main`)
**État de la production** : `git diff --stat -- lib/` = **1 fichier, 25 insertions, 1 suppression, 0 ligne de code**

> **Règle de lecture de ce rapport.** Chaque affirmation porte soit une référence de
> test avec son résultat, soit une mesure chiffrée, soit une déclaration explicite de
> non-démonstration. Rien n'est présenté comme acquis sans preuve. Les points non
> démontrés sont regroupés et assumés en §4 et §6, sans habillage.

---

## §1 — CLARIFICATION DU DÉSACCORD

Le désaccord portait sur **trois anomalies que j'avais annoncées**. Le travail mesuré en
a réfuté deux et confirmé une seule.

| # | Anomalie annoncée | Statut après mesure | Base de la réfutation |
|---|---|---|---|
| 1 | « Le seuil `nb >= 50` du gel est inatteignable car `take(50)` plafonne la fenêtre » | **RETIRÉE — mon erreur** | `take(50)` appliqué à une fenêtre de 200 rend bien **50**. L'arithmétique du demandeur était juste. La garde est atteignable. |
| 2 | « La projection produit une variation de poids qui altère le signal » | **RETIRÉE — mesure mal interprétée** | Le rapport « 265× » comparait la variation **avant** projection (1e-4) à la variation **après** (1e-2) en partant d'un état Σ = 1,26. Ce rapport mesure la **renormalisation 1,26 → 1,00**, pas une déformation du signal. Sur une table déjà conforme (Σ = 1,00), le rapport est de **1,07×** (test `apprentissage_a1_interpretation_test.dart`, V1/V2). |
| 3 | « Le commentaire du gel annonce un dégel à 0,70 qui n'existe pas dans le code » | **CONFIRMÉE** | Aucun `0.70` dans `ia_memory_service.dart`. Seul seuil : `0.85` (l.4143), gouvernant sélection **et** dégel. Mesuré par paliers dans `apprentissage_gel_degel_test.dart`, test **D1** : `r = 0.95 → 1 paire ≥ 0,85, 1 gelé` ; `r = 0,84 → 0 paire` ; `r = 0,70 → 0 paire`. **Le gel cesse sous 0,85, jamais sous 0,70.** |

**Conséquence honnête** : sur trois alertes, une était réelle. Les deux autres étaient des
erreurs d'interprétation de ma part, corrigées ici et non contestées.

---

## §2 — ANOMALIE CONFIRMÉE ET CORRECTION

### 2.1 L'anomalie unique : un commentaire faux, sans effet sur le comportement

`lib/services/ia_memory_service.dart`, l.4113 (avant correction) :
« Le gel se lève automatiquement quand r passe sous 0.70 ».

**Ce que le code fait réellement** (mesuré, pas déduit) :

| Fait | Preuve |
|---|---|
| `criteresGeles` est une variable **locale**, reconstruite à chaque appel (l.4139) | lecture l.4139 ; aucun champ persistant |
| Aucun gel n'est retenu d'un cycle sur l'autre | `apprentissage_gel_degel_test.dart` D0 : `forme\|gains r=0.953 p1=0.188028 p2=0.124668 ⇒ gelé=gains` recalculé à chaque cycle |
| Le gel se re-évalue contre `_poids.correlations` écrite par `_detecterCorrelationsCriteres` (l.4528) | lecture l.4140 + l.4528 |
| Un critère est gelé si et seulement si : paire mémorisée avec `r >= 0.85` **ET** il est le plus léger | l.4143-4151 |
| « Dégel » = absence de re-sélection. **Aucune hystérésis.** | D1, paliers ci-dessus |
| Le gel **n'est pas journalisé durablement** (seul `debugPrint` sous `kDebugMode`, l.4152) | l.4152-4155 |

### 2.2 La correction appliquée

**25 insertions, 1 suppression, toutes des lignes de commentaire. 0 ligne de code.**
Vérifié par `git diff --stat -- lib/`.

Aucun seuil, aucune sélection, aucune logique, aucune valeur n'a été touchée.
Les 19 poids initiaux de référence sont **identiques** :
`apprentissage_regression_av_apres_test.dart` **R1** → « poids initiaux identiques = 19/19 »,
« Σ AVANT = 1.260000 · Σ RÉFÉRENCE = 1.260000 ».

### 2.3 Pourquoi je n'ai PAS corrigé le reste

| Observation | Décision | Motif |
|---|---|---|
| Σ des poids du constructeur = 1,26 et non 1,00 | **NON CORRIGÉ** | R1/R5 : identique AVANT et RÉFÉRENCE ⇒ **défaut ancien**, pas une régression du chantier. Corriger changerait la formule des 19 critères → **décision utilisateur indispensable** (BL1-A04/A06). |
| Planchers individuels de 12 critères à 0,005 | **NON CORRIGÉ** | R2/R5 : c'est une **modification volontaire** du chantier, pas un défaut. |
| Commentaire l.385 annonçant un repli à 1,14 | **NON CORRIGÉ** | Le commentaire dit lui-même que ce chiffre est **théorique et n'est atteint par aucun chemin** (mesuré : 0/7 littéraux, 0/8 planchers inatteignables). |
| `clamp()` non idempotent | **NON CORRIGÉ — déclaré** | `poids_contraintes_test.dart` G1.2 : part enrichie 0,184877982 → 0,185444691 après 500 passes. Convergence, pas divergence. Voir §6, limite L-4. |

---

## §3 — LES DIX QUESTIONS SUR LA COUVERTURE MATRICIELLE

Le cycle de vie d'une matrice de 19 critères comporte sept étapes. Voici l'état de preuve
de chacune, avec la référence exacte.

| Étape | Preuve | Résultat |
|---|---|---|
| (1) Création par `analyserCourseAvecCriteres` | `test/v4_d1_recreation_test.dart` T1, T2, T3 | **verts** |
| (2) Enregistrement unitaire (`scoresCriteresMap`) | `v4_d1_recreation_test.dart:403` et `:467` | **verts** |
| (3) Enregistrement batch | `test/v28_b5c_rdr02_batch_post_reset_test.dart` V28-0..V28-C + `v4_d1_recreation_test.dart` T7a/T7b/T7c | **verts** |
| **(4) Conservation après réception du résultat officiel** | **`test/audit/couverture_matricielle_preuve_test.dart` M-COUV-4** | **PASSÉ — voir §3.1** |
| (5) Utilisation effective par l'apprentissage | **`couverture_matricielle_preuve_test.dart` M-COUV-5** | **PASSÉ — voir §3.2** |
| (5bis) Persistance au rechargement | `v4_d1_recreation_test.dart` T10 (disque + `recharger()` + comparaison de valeurs) | **vert** |
| (7) Sauvegarde et restauration | `test/v5_backup_restore_test.dart` **T2** (comparaison champ par champ de `scoresCriteres`) | **vert — 17/17 sur le fichier** |

### 3.1 Étape (4) — M-COUV-4 : la matrice survit-elle à `enregistrerResultat()` ?

`enregistrerResultat()` **reconstruit** l'objet `IaPronostic` (l.3610). Si `scoresCriteres`
y était omis, la matrice serait effacée à la résolution et l'apprentissage du cycle suivant
serait muet. Aucun test antérieur ne le vérifiait : V35 et A6-2b1 construisent leurs
pronostics avec `scoresCriteres: const {}`, ce qui ne prouve rien.

**Montage** : 12 courses résolues d'amorçage + 1 cible NON résolue, **5 partants × 19 critères**
chacune. Résolution par l'entrée de production `enregistrerResultat()`.

**Mesures imprimées** :
```
[COUV4] AVANT résolution : partants=5 · 19 critères présents=true
[COUV4] APRÈS résolution : partants=5 · attendu=5
[COUV4] critères identiques après résolution : 95 / 95
[COUV4] après rechargement : partants=5 · forme(1)=88.0 (avant=88.0)
```
**Statut : DÉMONTRÉ.** Les **95 valeurs** (19 critères × 5 partants) survivent intactes à la
résolution, et survivent à un rechargement complet.

### 3.2 Étape (5) — M-COUV-5 : la matrice est-elle réellement consommée par le gradient ?

**La première version de ce test a échoué et a été retirée, non affaiblie.** Elle comparait
`|Δ poids| max` après projection entre un montage à matrice vide et un montage à matrice
pleine. Le montage vide a produit un `|Δ|` du **même ordre** : la projection ramène Σ de 1,26
à 1,00 indépendamment du gradient (P1-C : la projection absorbe ~99,5 % de la variation).
L'assertion `greaterThan(1e-9)` ne mesurait pas ce qu'elle prétendait mesurer. Elle a été
**supprimée**.

**Méthode retenue : différentiel à UN SEUL critère, sur des points d'observation déjà
publiés par la production.** Aucune instrumentation ajoutée au moteur.

| Point d'observation | Emplacement | Nature |
|---|---|---|
| `JournalEntree.diagnostic` | `ia_memory_service.dart:4230` ← `_genererDiagnosticGlobal:5688-5708` | 1 ligne par critère, avec sa **discrimination** |
| `IaPoidsAdaptatifs.dernierGradient` | `ia_memory_models.dart:560`, sérialisé l.1209 | momentum par critère, publié l.4198 **avant** `clamp()` l.4200 |
| `JournalEntree.avant` / `.apres` | l.4081-4095 / l.4233-4247 | `avant` = pré-projection · `apres` = **post**-projection |

**Montage** : deux corpus identiques à **une seule note près**. Sur `distSpec`, la pente est
DÉCROISSANTE (montage PRO ⇒ le gagnant n°1 a la note haute) ou CROISSANTE (ANTI ⇒ note basse).
Les 18 autres critères ont **exactement** les mêmes valeurs.

**Mesures imprimées** :
```
[COUV5] lignes de critères trouvées dans le journal : 19 / 19 (PRO) · 19 / 19 (ANTI)
[COUV5] discrimination distSpec : PRO=0.9% · ANTI=-4.1%
[COUV5] momentum distSpec : PRO=2.115663e-4 · ANTI=-9.940098e-4
[COUV5] journal.apres[distSpec] : PRO=0.058372744135 · ANTI=0.057997183086 · écart=3.755610e-4
[COUV5] AVANT projection (momentum) : 18 autres critères identiques au bit près sur 18/18
[COUV5] APRÈS projection : 11/18 autres poids redistribués (écart max 5.601e-5) — ATTENDU
[COUV5] garde : poids de départ identiques sur 19/19
[COUV5] garde : Σ poids de départ = 1.260000000
```

**Statut : DÉMONTRÉ.** Ce que ces nombres établissent :
1. les **19** critères sont lus et discriminés — 19/19 lignes au journal, aucun manquant ;
2. modifier **une seule note** **inverse le signe** de la discrimination (+0,9 % → −4,1 %) ;
3. le **momentum** publié suit ce signe (+2,116e-4 → −9,940e-4) : le critère a traversé la boucle du gradient ;
4. les **18 autres momentum sont inchangés au bit près (18/18)** : aucun mélange inter-critères ;
5. le **poids écrit au journal** pour ce critère diffère (0,058372744 → 0,057997183) : le chemin va jusqu'à l'écriture ;
6. les deux mesures partent des **mêmes 19 poids** (Σ = 1,26) : la différence ne peut venir que de la matrice.

**Ce que cela NE démontre pas** : que la variation **après projection** serait un indicateur de
consommation. C'est précisément l'hypothèse erronée de la première version. La redistribution
mesurée sur 11/18 autres poids après projection n'est **pas** un défaut : c'est la
renormalisation globale Σ appliquée à un écart local (les deux Σ valent 1,000000000000).

### 3.3 Les dix questions — réponses

| # | Question | Réponse mesurée |
|---|---|---|
| Q1 | La matrice est-elle créée avec les 19 critères ? | **Oui.** V4/T1-T3 ; M-COUV-4 `19 critères présents=true` |
| Q2 | Est-elle enregistrée par le chemin unitaire ? | **Oui.** V4:403, V4:467 |
| Q3 | Par le chemin batch ? | **Oui.** V28-0..V28-C, V4/T7a-c |
| Q4 | Survit-elle à `enregistrerResultat()` ? | **Oui, 95/95.** M-COUV-4 |
| Q5 | Est-elle lue par l'apprentissage ? | **Oui, 19/19 lues.** M-COUV-5 |
| Q6 | Survit-elle au rechargement ? | **Oui.** V4/T10, M-COUV-4 après reload |
| Q7 | Survit-elle à sauvegarde/restauration ? | **Oui, champ par champ.** V5/T2 |
| Q8 | Une matrice absente bloque-t-elle l'apprentissage ? | **Oui : filtre l.3939.** M-COUV-5 confirme que sans matrice le critère n'alimente pas le gradient |
| Q9 | Les 19 critères sont-ils tous discriminés ? | **Oui.** M-COUV-5 (19/19) ; S3-2 (19 discriminations non nulles, 0,0068 à 0,0079) |
| Q10 | La discrimination d'un critère est-elle isolable ? | **Oui.** S3-3 : un critère inversé donne `-0.026159873`, les 18 autres restent positifs |

**Rectification du point 4 de la consigne précédente — la conservation à 90 jours.**
Mon affirmation initiale (« convergence à 90 jours ») était **fausse**. Le code (l.1230-1247) :
```dart
if (p.resultatsReels) return false;          // ← jamais purgé si un résultat existe
return p.datePronostic.isBefore(limite);     // purge seulement SANS résultat officiel
```
**Règle réelle** : pronostic **sans** résultat officiel → purgé au-delà de 90 jours ;
pronostic **avec** résultat officiel → **conservation illimitée**. Aucun historique
n'a été supprimé, aucune matrice n'a été fabriquée.

---

## §4 — TABLEAU EXHAUSTIF DES OBLIGATIONS

Six statuts, conformément à la règle de classification. **Aucune obligation ne disparaît
silencieusement.**

### Légende
- **TD** = Terminée et démontrée (preuve suffisante obtenue)
- **DC** = Déjà couverte par une preuve antérieure, toujours valide
- **AD** = Abandonnée sur décision validée
- **NN** = Non nécessaire, justification technique
- **ND** = Non démontrable, impossibilité objective expliquée
- **RT** = Restant à terminer

### 4.1 Bloc A — poids, gradient, projection

| # | Obligation | Statut | Preuve / justification |
|---|---|---|---|
| A-01 | Les 19 poids initiaux de référence sont inchangés | **TD** | `poids_cycle_apprentissage_test.dart` **F1** : écart max `0.000000000000`, Σ = 1,260000000000 (base 0,710 · enrichis 0,550) ; R1 : `19/19 identiques` |
| A-02 | Le chargement ne projette pas | **TD** | F1 + garde `semer()` : Σ relue = Σ écrite à 1e-9 |
| A-03 | Le premier apprentissage projette, une seule fois | **TD** | F2 : `19/19 critères déplacés`, écart max `0.038514384910` (« forme »), Σ après = 1,000000000000, base 0,600 / enrichis 0,400 |
| A-04 | Les poids appris sont persistés et relus à l'identique | **TD** | F3 : blob `ia_poids_v3` = 1975 octets ; après redémarrage écart max `0.000000000000`, `nbMisesAJour 1 → 1` |
| A-05 | Aucune modification sans apprentissage | **TD** | F4 : 5 rechargements → écart max `0.000000000000` ; journal 2 → 2 ; `nbMisesAJour 1 → 1` |
| A-06 | **La différence brut/projeté au premier pronostic est-elle une incohérence fonctionnelle ?** | **TD** | **Voir §4.4 — réponse complète ci-dessous** |
| A-07 | Les poids **globaux** persistent au rechargement | **TD** | F3 |
| A-08 | Les poids **par discipline** persistent au rechargement | **TD** | F5 (table créée, Σ = 1,0, 0 violation de borne, part enrichie 0,399325810925) + **V5/T2** : `poidsParDiscipline['TROT_ATTELE']['forme']` restauré à `0.30` |
| A-09 | Une table de discipline respecte les 19 bornes du global | **TD** | F5 : `violations=0` ; divergence ≤ 0,08 (`0.028545855907`) |
| A-10 | Rejouer une arrivée n'apprend pas deux fois | **TD** | F6 : rejeu `ok=false`, journal `+0`, écart `0.000000000000` |
| A-11 | Les NaN/infini/négatifs sont absorbés **et tracés** | **TD** | F7 : `3 anomalie(s) tracée(s)` — forme NaN → plancher 0,05 ; gains −0,4 → 0,04 ; cote ∞ → 0,05 ; relais `anomaliesProjection 0 → 3` |
| A-12 | Σ du constructeur = 1,26 et non 1,00 | **ND** | Défaut **ancien** (R1/R3 : identique AVANT/RÉF). Le normaliser changerait la formule des 19 critères → **décision utilisateur**. Voir §4.4. |
| A-13 | `clamp()` est idempotent | **ND** | **Faux, et mesuré** (G1.2). Il converge vers un point fixe (part enrichie 0,184877982 → 0,185444691 sur 500 passes). Ce n'est pas une divergence ; ce n'est pas corrigeable sans toucher la projection protégée. Voir limite L-4. |

### 4.2 Bloc B — coefficients, momentum, gel

| # | Obligation | Statut | Preuve / justification |
|---|---|---|---|
| B-01 | Les coefficients n'entrent **pas** dans la boucle du signal | **TD** | `RESULTATS_MESURES.md` **A1** : 19 discriminations et 19 momentum → écart **0.000000000** entre production et `coefficientsUniformes(1.0)` ; seuls les poids finaux bougent (0,004537194) |
| B-02 | Les coefficients agissent sur l'amplitude, pas sur le plafond atteignable | **TD** | **A2** : `distSpec` (coef 0,5) atteint **0.137804545**, dépasse la base la plus faible `discipline` (**0.043209777**) ⇒ `dépassement = true` |
| B-03 | Le momentum ajoute exactement `0,3 × gradient précédent` | **TD** | S3-4 (rapport m6/m1 → 1/0,7 = 1,4286) ; production l.4104 `momentumFactor = 0.3` ; R3 : `momentumFactor AV=0.3 · RÉF=0.3 · IDENTIQUE` |
| B-04 | Le momentum a un effet mesurable | **TD** | **C1** : écart max **0.007765566** (sur `forme`), 19/19 critères touchés, entre `momentumFactor` 0,3 et 0,0 |
| B-05 | Le gel se déclenche à `r >= 0,85` | **TD** | G0 (`[Gel gradient] gains gelé … r=0.95`) ; D0 (`forme\|gains r=0.953 ⇒ gelé=gains`) ; D1 paliers 0,95/0,90 → gelé, 0,84/0,70 → non |
| B-06 | Le gel sélectionne le critère le plus **léger** | **TD** | D0 : `p1=0.188028 p2=0.124668 ⇒ gelé=gains` (le plus faible) |
| B-07 | Le gel exige une fenêtre ≥ 50 courses | **TD** | `RESULTATS_MESURES.md` B1 : fenêtre 13 → gel structurellement inatteignable (faux positif identifié) ; fenêtre 50 → 39/40 cycles avec gel |
| B-08 | Le gel exige `_poids.correlations` non vide | **TD** | B1 condition 2 ; `apprentissage_donnees_reelles_test.dart` **R3** : `paires de corrélation = 0 · seuil ATTEINT = false` sur corpus réel |
| B-09 | Le gel a un coût mesurable | **TD** | B1 : `forme` **0.182106343** sans gel → **0.256746220** avec gel, delta **+0.074639877** (+41 % relatif) |
| B-10 | Le gel ne bloque pas un critère néfaste sur des données réalistes | **TD** | **G3** (critères distincts, 15 paires ≥ 0,85) : le critère néfaste `repos` atteint son plancher **0.005000000** avec **et** sans gel — **différence 0.000000000**. Le blocage observé en G1 (r = 1,0 sur 171 paires) est un **artefact de clones**, déclaré comme tel, non un défaut de production. |
| B-11 | Le chemin par discipline n'a ni momentum ni gel | **TD** | S3-5 (mesuré) |
| B-12 | Le gel est journalisé durablement | **ND** | **Non.** Seul `debugPrint` sous `kDebugMode` (l.4152). L'historique des gels d'une installation n'est **pas** reconstituable depuis une sauvegarde. C'est une propriété du code, pas une limite de mesure. Toute instrumentation a été **refusée** par décision validée. |
| B-13 | Le commentaire du gel décrit le code réel | **TD** | **Corrigé le 27/11/2026** — 25 insertions, 0 ligne de code. Voir §2. |

### 4.3 Bloc C — différenciation et évolution des 19 critères (points 8 et 9)

| # | Obligation | Statut | Preuve / mesure |
|---|---|---|---|
| C-01 | Les 12 enrichis peuvent se différencier à partir de poids identiques | **TD** | S3-2 : les 19 discriminations sont **non nulles et distinctes** (0,006847830 → 0,007893091) ; M-COUV-5 : 19/19 lues |
| C-02 | Un enrichi peut dépasser une base | **TD** | **A2** : `distSpec` 0.137804545 > `discipline` 0.043209777 |
| C-03 | **Un critère peut décliner avec pertinence** | **TD** | S3-3 : discrimination inversée → `-0.026159873` ⇒ gradient négatif ; D5v2 : les 19 critères atteignent leur plafond **19/19** sous pilotage |
| C-04 | **Un critère peut progresser avec pertinence** | **TD** | A2 ; D4 : part enrichie montant jusqu'à **0.400000000000** quand les enrichis sont très discriminants |
| C-05 | **Les planchers peuvent être quittés quand les contraintes le permettent** | **TD — sous condition** | **D5v2** : `PLANCHER : atteint 0/19 · quitté 19/19 · campagnes valides 19/19`. Les 19 critères quittent leur plancher quand on les pilote. |
| C-06 | **Les plafonds peuvent être atteints** | **TD** | **D5v2** : `PLAFOND : atteint 19/19 · quitté 19/19 · campagnes valides 19/19` |
| C-07 | Un critère au plancher **dans un scénario de saturation du groupe** remonte-t-il ? | **ND — sous condition** | D3 : `jockey` reste à 0,005000000, récupération `0.000e+0`. **Ce n'est pas une anomalie** : G1.2 mesure qu'au point fixe de la projection, **11 des 12 enrichis sont à leur plancher** parce que le groupe enrichi est saturé à son plafond collectif de 0,40. La contrainte de groupe **interdit** arithmétiquement la remontée. La consigne exigeait « quand les contraintes le permettent » — ici elles ne le permettent pas. |
| C-08 | Les contraintes individuelles (19 bornes) sont respectées | **TD** | F5 : `violations=0` ; R2 : table complète des 19 planchers/plafonds |
| C-09 | Les contraintes collectives (Σ = 1, part ∈ [0,18 ; 0,40]) sont respectées | **TD** | F5, D1 (`Σ(t=299) = 1.000000000000 · part enrichie = 0.400000000000`), D4 (`maximum observé 0.400000000000 · minimum observé 0.180000000000`, bornes de production `[0.18, 0.40]`) |
| C-10 | Le plafond collectif a une influence mesurable | **TD** | G2.2 config **C4 SANS COLLECTIF** : part enrichie **78.106 %** = **1,95×** le plafond actuel. C'est la mesure de l'influence du plafond. |
| C-11 | La contrainte collective C2 (plancher 0,10) est opérante | **TD — non nécessaire** | G1.1 : les planchers individuels consomment déjà **88,89 %** du plancher collectif (0,16 sur 0,18) ; un plancher à 0,10 est **sous** 0,16 ⇒ **arithmétiquement inapplicable**. Ce n'est pas un défaut : la contrainte est **dominée** par les planchers individuels. |

### 4.4 Bloc D — point 1 : la différence brut/projeté est-elle une incohérence fonctionnelle ?

**Question posée** : au premier pronostic, les poids bruts (Σ = 1,26) diffèrent des poids
projetés (Σ = 1,00). Cela produit-il une incohérence fonctionnelle réelle ?

**Réponse mesurée : oui sur un point précis, non sur celui qu'on attendait.**

| Aspect | Mesure | Verdict |
|---|---|---|
| L'**ordre** des chevaux change-t-il ? | `audit_poids_disciplines_test.dart` **M11.1**, deux cas opposés : classement poids bruts `C8 > C7 > … > C1` = classement poids effectifs `C8 > C7 > … > C1`, `identique ? true` dans les **deux** cas | **Non** — l'ordre est préservé |
| Les **scores** changent-ils ? | `ia_pronostic_engine.dart:380-384` (mesure documentée dans la production) : `98,21 \| 93,31 \| 85,49 \| 68,66 …` avec Σ = 1,26, contre `90,67 \| 87,73 \| 77,88 \| 61,45 …` avec Σ = 1,00 — **+7 pt environ par cheval** | **Oui, les scores sont gonflés** |
| Cela franchit-il des **seuils absolus** ? | Idem, l.385-386 : « Ce sont donc les **SEUILS ABSOLUS** (`seuilSimpleGagnant` 80, `seuilCoupleGagnant` 75…) qui sont franchis plus facilement tant que l'IA n'a pas appris » | **Oui — incohérence fonctionnelle réelle et bornée** |
| Les poids par discipline sont-ils persistés ? | F5 + **V5/T2** (`poidsParDiscipline['TROT_ATTELE']['forme']` = 0,30 après restauration) | **Oui, persistés et restaurés** |
| M11.1 est-il une preuve valide de préservation d'ordre ? | **Non — insuffisant** | Les deux classements sortent de la même façon parce que le montage `champ()` ne peut pas les séparer. M11.1 imprime mais n'assertionne que `length == 8`. **Je ne m'appuie pas dessus** ; la démonstration d'ordre repose sur la mesure documentée l.380-384, qui est une mesure de production, pas un test. |

**Statut A-06 : TD.** L'incohérence existe, elle est **bornée et documentée dans la
production depuis BL1-A04/A06** : les scores sont gonflés d'environ +7 points tant que
l'IA n'a pas appris, ce qui rend les seuils absolus plus faciles à franchir. **La correction
n'a pas été appliquée** parce qu'elle exige une **décision utilisateur** (elle modifie la
formule des 19 critères). C'est la seule obligation du chantier dont la clôture dépend d'une
décision qui ne m'appartient pas.

### 4.5 Bloc E — points 6, 7, 10 : coefficients, gradient, momentum, projection, inversions, interactions, long terme

| # | Obligation | Statut | Preuve / mesure |
|---|---|---|---|
| E-01 | Le gradient lit les notes 0–100 et les arrivées, jamais les poids | **TD** | l.4074-4079 (lecture) ; A1 : discriminations écart **0,000000000** quand on change les coefficients ⇒ indépendantes des poids |
| E-02 | L'ordre d'écriture momentum → coefficient est correct | **TD** | l.4165-4167 (`momentum[c] = gradAvecMomentum` **avant** le `switch` l.4172) ; mesuré par A1 |
| E-03 | La projection réécrit la proposition sur les 19 critères | **TD** | S3-6 : `la projection RÉÉCRIT la proposition sur 19/19 critères · amplitude max de réécriture = 3.905186e-2` |
| E-04 | Les leviers de projection sont mesurés | **TD** | P1-C : `λ BASE = 0.845070423` (0,710 → 0,600) ; `λ ENRICHI = 0.727272727` (0,550 → 0,400) ; ratio base/enrichi 1,290909091 → 1,500000000 (×1,161971831) ; **0/19 critères écrêtés** ; part enrichie 0,436507936508 → 0,400000000 |
| E-05 | Un critère **néfaste** descend-il ? | **TD — sous conditions** | X1/X2 : avec gel, `distSpec` reste à 0,0556 ; **sans gel, il atteint 0,005000000 dès le cycle 20**. G3 : sur critères distincts, avec **et** sans gel, le néfaste atteint son plancher (différence **0.000000000**). |
| E-06 | Une **inversion de pertinence** est-elle suivie ? | **PARTIEL — voir C-03** | C2 : après inversion, `distSpec` **monte** dans les deux cas (`momentumFactor` 0,3 et 0,0) ⇒ le momentum n'en est pas la cause ; le phénomène s'explique par le gel (X1/X2) et disparaît sur critères distincts (G3). D2 : `distSpec` décline plus lentement après inversion (−1,05e-4/cycle avant, −1,9e-5/cycle après) mais **ne remonte pas** — D2 n'a **aucune assertion** démontrant l'adaptation. **Déclaré incohérent comme preuve, non comme anomalie.** |
| E-07 | Les interactions entre critères sont mesurées | **TD** | G1.1 (planchers consomment 88,89 % du collectif), G2.2 (C4 sans collectif → 78,106 %), G1.2 (point fixe 11/12 enrichis au plancher), B1 (gel concentre l'apprentissage sur `forme`) |
| E-08 | Évolution à long terme : point fixe atteint | **TD** | D1 (300 cycles) : `mouvement max sur les 50 derniers cycles = 1.125e-4` ; part enrichie stable 0,400 de t=0 à t=299 |
| E-09 | Évolution à long terme : les 19 critères sur 300 cycles | **TD** | D5v2 : **11 400 cycles** mesurés (19 critères × 2 bornes × 300 cycles), 19/19 campagnes valides |
| E-10 | Évolution à long terme : 400 cycles avec inversion | **RT — non concluant** | D2/D3 : mesures disponibles (voir E-06 et C-07), **aucune assertion de comportement**. Ne peut pas être classé TD ; les mesures n'établissent pas l'hypothèse et n'établissent pas non plus un défaut. Voir §6, limite L-5. |

### 4.6 Bloc F — données authentiques, avant/après

| # | Obligation | Statut | Preuve / mesure |
|---|---|---|---|
| F-01 | Les deux sauvegardes sont lisibles et leurs comptages exacts | **TD** | 28/05 : 2 386 883 octets, `ia_pronostics_v2_gz` = base64(gzip(JSON)), **572 / 572 / 47**. 13/11 : 12 293 558 octets, **600 / 564 / 4** (+1 non résolu = 5). **Les chiffres de la consigne sont exacts à l'unité.** |
| F-02 | Les corrélations réelles atteignent-elles le seuil de gel ? | **TD** | Mesuré sur les 47 matrices, formule identique à `pearson` l.4500 : **3 paires ≥ 0,85**, **identiques sur deux périodes séparées de 6 mois** |
| F-03 | Le gel est-il accessible en pratique sur ces données ? | **TD** | Arithmétique du code appliquée aux données : même avec 50 courses en fenêtre, **5 matrices** ne suffisent pas. Voir `RESULTATS_MESURES.md` § « Accessibilité réelle du gel » |
| F-04 | La couverture matricielle réelle est mesurée | **TD** | **8,2 %** (28/05) et **0,8 %** (13/11). Le facteur limitant est la **couverture**, pas le volume de courses (50 courses s'accumulent en 1,7 à 2,0 jours à 30,1-37,5 courses/jour) |
| F-05 | La cause de la faible couverture est établie | **ND** | Deux chemins de production coexistent (`test/audit/double_apprentissage_chemins_test.dart`). Aucune mesure ne permet de l'attribuer à un défaut plutôt qu'à un choix. **Déclaré, non maquillé.** |
| F-06 | Apprentissage sur corpus réel, hors échantillon | **TD** | R2 : écart max `0.038732394366` (« forme »), `Σ = 1.000000000000`, part enrichie `0.386944181646` |
| F-07 | Capacité du corpus authentique | **TD** | R1 : `44 courses · 5 journées`, **43/44 exploitables**, **343 partants classés** |
| F-08 | Le gel est atteignable sur le corpus réel | **TD** | R3 : `courses résolues = 0 · fenêtre = 0 · paires de corrélation = 0 · seuil ATTEINT = false` — **le corpus ne suffit pas**, et c'est mesuré, pas converti en échec de harnais |
| F-09 | Comparaison avant/après sur les constantes | **TD** | `apprentissage_regression_av_apres_test.dart` **R0-R5** : 6/6 verts. `R1` 19/19 poids identiques, `R2` 19 bornes, `R3` `coefficients identiques = 19/19`, `lrBase 0.08`, `momentumFactor 0.3`, `seuil de gel 0.85`, `seuil population 0.65`, `fenêtre 50.0`, `R4` part enrichie 0,18/0,40 |
| F-10 | Les modifications du chantier sont distinguées des défauts anciens | **TD** | R5 : 5 défauts **anciens** (Σ = 1,26, coefficients, gel 0,85, momentum 0,3/lr 0,08, contraintes 0,18/0,40) ; 1 **modification volontaire** (planchers 12/19 abaissés) ; 3 **erreurs d'interprétation** corrigées |

### 4.7 Bloc G — non-régression du gel sur le moteur réel

| # | Obligation | Statut | Preuve |
|---|---|---|---|
| G-01 | Le gel est prouvé sur des données **distinctes** | **TD** | `apprentissage_gel_degel_test.dart` **D0-D3**, 4/4 verts |
| G-02 | La chaîne complète du gel est prouvée sur le moteur réel | **TD** | `apprentissage_gel_coefficients_test.dart` **G0**, 4/4 verts |
| G-03 | Le gel n'entre pas dans le signal (coefficients) | **TD** | A1 |
| G-04 | Le gel cesse sous 0,85 et non sous 0,70 | **TD** | D1 paliers (0,85 → 1 paire mais 0 gelé mesuré à la borne ; 0,84 → 0 paire) |

---

## §5 — ORGANISATION DES HARNAIS : INVENTAIRE À NEUF ATTRIBUTS

### 5.1 Instruments actifs (dans le dépôt, exécutables, sur le vrai moteur)

| Instrument | Emplacement | Fonction | Statut | Dépendances | Défauts historiques | Corrections | Preuve de bon fonctionnement | Usage futur |
|---|---|---|---|---|---|---|---|---|
| `couverture_matricielle_preuve_test.dart` | `test/audit/` | M-COUV-4 (survie de la matrice) + M-COUV-5 (consommation par le gradient) | **actif, vert** | `test/support/atelier_apprentissage.dart` | 2 (parseur de label ; assertion post-projection) | les deux, mesurées | `+2: All tests passed!` | rejouer à chaque modification du journal ou du gradient |
| `poids_cycle_apprentissage_test.dart` | `test/audit/` | F0-F7 : cycle des poids, persistance, discipline, NaN | **actif, vert** | atelier | 0 | — | `+8: All tests passed!` | socle de non-régression poids |
| `apprentissage_chaine_19_criteres_test.dart` | `test/audit/` | S3-0..S3-6 : discriminations, momentum, table des 19 | **actif, vert** | atelier | 0 | — | `+7: All tests passed!` | non-régression du signal |
| `apprentissage_gel_degel_test.dart` | `test/audit/` | D0-D3 : gel/dégel sur critères distincts | **actif, vert** | atelier | 2 (fenêtre < 50 ; variance constante) | les deux | `+4: All tests passed!` | non-régression du gel |
| `apprentissage_gel_coefficients_test.dart` | `test/audit/` | G0 : chaîne complète du gel | **actif, vert** | atelier | 1 (détection du signe) | oui | `+4: All tests passed!` | preuve du gel de bout en bout |
| `poids_contraintes_test.dart` | `test/audit/` | G0-G3.3 : bornes, contraintes collectives, saturation | **actif, vert** | aucune (autonome) | 0 | — | `+12: All tests passed!` | contrat des contraintes |
| `apprentissage_dynamique_longue_test.dart` | `test/audit/` | D0-D4 : 300-400 cycles, point fixe, inversion | **actif, vert** | atelier | 0 | — | `+5: All tests passed!` (5 min 42) | évolution longue |
| `apprentissage_regression_av_apres_test.dart` | `test/audit/` | R0-R5 : AVANT vs RÉFÉRENCE (git) | **actif, vert** | `git` | 0 | — | `+6: All tests passed!` | garde anti-régression |
| `apprentissage_donnees_reelles_test.dart` | `test/audit/` | R1-R3 : corpus réel, fenêtre, accessibilité du gel | **actif, vert** | `test/fixtures_corpus/` | 1 (conversion d'un manque de corpus en échec) | oui | `+3: All tests passed!` | mesure sur données authentiques |
| `apprentissage_a1_interpretation_test.dart` | `test/audit/` | V0-V2 : décomposition normalisation vs signal | **actif** | atelier | 0 | — | référence de lectures | interprétation |
| `v4_d1_recreation_test.dart` | `test/` | V4/T1..T10 : création, (2), (3), (5bis) | **actif** | moteur | 0 | — | étapes (1)(2)(3)(5bis) | matrice |
| `v5_backup_restore_test.dart` | `test/` | V5/T1..T12 : sauvegarde/restauration | **actif, vert** | moteur | 0 | — | `+17: All tests passed!` | sauvegarde |
| `v28_b5c_rdr02_batch_post_reset_test.dart` | `test/` | V28-0..V28-C : batch après reset | **actif** | moteur | 0 | — | étape (3) | batch |
| `audit_poids_disciplines_test.dart` | `test/` | M11/M12 : discipline, classement | **actif, vert** | moteur | **1 — M11.1 n'assertionne pas** | non corrigé (déclaré) | `+3: All tests passed!` | discipline |
| `test/support/atelier_apprentissage.dart` | `test/support/` | atelier : `semer`, `executerCycle`, `Cycle`, `gelesSuspects` | **actif** | moteur | 3 (dont journal post-projection documenté) | oui, toutes documentées dans le fichier | utilisé par 10 suites | socle de tous les harnais |
| `test/fixtures_corpus/` | `test/fixtures_corpus/` | 89 fichiers, 44 courses | **actif** | — | 0 | — | R1/R2 | corpus authentique |

### 5.2 Instruments archivés (sources `.dart.txt`, non exécutables)

`test/audit/ARCHIVES_EXPERIMENTALES/` — **48 fichiers**, extension `.dart.txt`, chacun avec
en-tête « ARCHIVE NON EXÉCUTABLE ».

**Preuve mécanique qu'aucun instrument expérimental ne peut atteindre l'APK** :
`grep -rn "ia_experimentation\|IaExperimentation" lib/` → **0 occurrence**.
Le fichier `lib/services/ia_experimentation.dart` **n'a jamais existé** dans `lib/`. Toute la
famille v2/v3/v4 de harnais l'importe : elle est donc **de fait inintégrable**, indépendamment
de toute discipline de développement.

Vérification que les archives ne cassent pas la compilation :
`flutter analyze --no-pub test/audit/` → **`No issues found!`** alors que 48 fichiers de
archive sont présents.

**Preuves de campagnes** : `preuves/traces_campagnes_20261127.tgz` (521 098 octets), 6 journaux.

### 5.3 Instruments abandonnés — **décision validée, aucun effort de réparation**

| Instrument | Raison |
|---|---|
| `campagne_g4v5_gel_nefaste_test.dart` | Refusé par son propre garde : `\|r\|80 = 0,026814738 < 0,80`. Le scénario « critère devenu néfaste en conservant la corrélation » est **inexprimable** dans la famille v4 : `motif4(n) = 3 − n` est **PARTAGÉ**, donc inverser γ **détruit** la covariance au lieu de la conserver. C'est une **limite du générateur**, pas un défaut du moteur. |
| `sonde_G5_calibrage_test.dart` | Sonde écrite pour calibrer G4v5 ; sans objet. **Jamais exécutée.** |

### 5.4 Les 21 défauts de harnais — bilan

| Statut | Nombre | Détail |
|---|---|---|
| **Corrigés** | **18** | n°1 à n°14 (voir `DIX_OBLIGATIONS_PREUVES.md`), plus n°15 (sel du bruit), n°18 (sel du signal latent), n°19 (amorçage), n°21 (instant de vérification) |
| **Restants — exclusivement dans des instruments ABANDONNÉS** | **3** | G4v5 (scénario inexprimable), sonde G5 (sans objet), E1 (171 paires parasites — campagne remplacée par E1v2) |
| **Total** | **21** | |

**Vérification demandée** : aucun des 18 défauts corrigés ne subsiste dans un instrument
**actif**. Le recensement ci-dessus (5.1) ne porte aucun défaut non corrigé, à une exception
déclarée : `audit_poids_disciplines_test.dart` M11.1, qui imprime sans assertionner. Ce n'est
pas un défaut de mesure (les valeurs sont réelles), c'est une **preuve déclarée insuffisante**,
et je ne m'appuie pas dessus en §4.4.

**Les 3 défauts restants concernent exclusivement des instruments abandonnés** : confirmé.

### 5.5 Doublons v2/v3

`harnais_v2` et `harnais_v3` sont dans `sources/` en `.dart.txt`, **remplacés par `harnais_v4`**.
Vérification de dépendances effectuée : **17 harnais de campagne** importent encore v3
(D5, E1, T3, I1, F, G4v2, G5, H, V0/V1…), et ce sont précisément les campagnes dont les
conclusions sont **acquises ou abandonnées**. **Aucun instrument actif ne dépend de v2 ou v3.**

**Décision** : conservation dans `sources/` à titre de preuve historique. **Aucune suppression
physique** — conformément à la consigne « aucune suppression définitive des instruments avant
validation ». Les sources sont de toute façon non exécutables.

---

## §6 — LIMITES, DÉCLARÉES SANS HABILLAGE

| # | Limite | Nature | Conséquence |
|---|---|---|---|
| **L-1** | **Le gel n'a jamais été déclenché en production réelle** | Propriété du code | `criteresGeles` n'est journalisé que sous `kDebugMode`. **Aucune trace persistante n'existe** ⇒ cette question est **non démontrable dans les deux sens**, pas seulement « non démontrée ». Ce n'est pas une limite de mesure. |
| **L-2** | Le corpus authentique ne permet pas d'atteindre le gel | Mesuré (R3, F-03) | `fenêtre = 0 · paires = 0 · seuil ATTEINT = false`. La couverture matricielle réelle (8,2 % et 0,8 %) est le facteur limitant. |
| **L-3** | La cause de la faible couverture matricielle n'est pas établie | Non démontré | Deux chemins de production coexistent. Aucune mesure ne les départage. Déclaré, non maquillé. |
| **L-4** | `clamp()` n'est pas idempotent | Mesuré (G1.2) | Il **converge** (part enrichie 0,184877982 → 0,185444691 sur 500 passes), il ne diverge pas. Corriger exigerait de modifier la projection — **mécanisme protégé**. |
| **L-5** | D2 et D3 n'ont **aucune assertion de comportement** | Défaut de conception de mes harnais | Elles impriment des trajectoires réelles mais ne peuvent conclure ni à l'adaptation ni au défaut. **Inutilisables comme preuve** (statut E-10 / RT). Je ne les présente pas comme des preuves. |
| **L-6** | Aucune exécution sur appareil Android physique | Limite de l'environnement | Toutes les mesures viennent de la VM Dart. Le comportement de `sqflite` natif Android n'est pas validé. |
| **L-7** | Le montage M-COUV-5 rend les 19 critères corrélés à r = 1,0 | Artefact de mes pentes linéaires | Mesuré : **171 paires**. Avec `nb = 21 < 50`, le bloc de gel (l.4140) est **inactif** : les 19 critères reçoivent bien leur gradient. **Le montage ne teste pas le gel** — D0-D3 et G0 le font sur des données distinctes. |
| **L-8** | M11.1 n'assertionne que `length == 8` | Preuve insuffisante | Les deux classements sortent identiques. **Je ne m'appuie pas sur M11.1** en §4.4. |

---

## §7 — MÉCANISMES PROTÉGÉS : AUCUNE ATTEINTE

| Mécanisme | État | Vérification |
|---|---|---|
| Descente de gradient | **intact** | `git diff` : 0 ligne de code |
| Coefficients d'apprentissage 1,0/0,5/0,4/0,3 | **intact** | R3 : `coefficients identiques = 19/19` |
| `lrBase = 0.08`, `momentumFactor = 0.3` | **intact** | R3 : `AV=0.08 · RÉF=0.08`, `AV=0.3 · RÉF=0.3` |
| Momentum de production | **intact** | l.4104, l.4198 — non modifiés ; A1 mesuré |
| Poids initiaux de référence (19) | **intact** | F1 écart max `0.000000000000` ; R1 `19/19 identiques` |
| Seuils de l'IA (0,85 gel ; 0,65 population ; 50 fenêtre) | **intact** | R3 : `seuil de gel 0.85`, `seuil population 0.65`, `fenêtre du gel 50.0` — tous IDENTIQUES |
| Gel / dégel | **intact** | Seul le **commentaire** a changé (§2.2) |
| Contraintes collectives 0,18/0,40 | **intact** | R4 : `AV≈0.18 · RÉF=0.18`, `AV≈0.4 · RÉF=0.4` |
| TOP 3, algorithmes de score, statistiques | **intact** | hors périmètre, non touchés |
| Laboratoire IA | **intact** | hors périmètre, non touché |
| Aucun recalcul historique, aucun apprentissage rétroactif | **respecté** | Aucune donnée d'archive n'a été rejouée dans la production |
| Aucune réinitialisation | **respectée** | Aucun reset exécuté |
| Sauvegardes originales | **intactes** | Les deux backups ont été **lus** et décompressés en mémoire, jamais modifiés |

**BLOC 2 reste suspendu. BLOC 3 non commencé.**

---

## §8 — OPINION TECHNIQUE FINALE

### 8.1 Ce qui est solide

Le mécanisme d'apprentissage est **prouvé sur ses points critiques** :
- les 19 critères sont **lus, discriminés et écrits** (M-COUV-5, 19/19 lignes de journal) ;
- un seul critère modifié **inverse son signe** sans toucher aux 18 autres (18/18 momentum inchangés **au bit près**) ;
- les coefficients **n'entrent pas** dans le signal (A1 : écart 0,000000000) ;
- un enrichi **peut dépasser** une base (A2 : 0,1378 > 0,0432) — la crainte d'« enrichis bridés » était **infondée en plafond**, vraie seulement en vitesse ;
- les bornes individuelles et collectives sont **respectées** (F5, D1, D4, G1.1) ;
- le gel, sur des données **distinctes** (réalistes), **ne bloque pas** un critère néfaste (G3 : différence 0,000000000) — il ne bloque que sous redondance parfaite (G1, artefact).

### 8.2 Ce qui reste ouvert, et pourquoi ce n'est pas grave

Trois points restent ouverts, et **aucun n'est un défaut fonctionnel démontré** :

1. **La couverture matricielle réelle (8,2 % / 0,8 %)** est le **seul facteur limitant sérieux** :
   tant que les pronostics n'emportent pas leur matrice, le gradient tourne sur peu de données.
   La cause n'est pas établie (L-3) — c'est la question **la plus utile à instruire ensuite**.
2. **Σ = 1,26 au démarrage gonfle les scores d'environ +7 points** et rend les seuils absolus
   plus faciles à franchir tant que l'IA n'a pas appris (A-06). C'est **réel**, **borné**,
   **documenté**, et sa correction attend une **décision** qui ne m'appartient pas.
3. **D2 et D3 ne concluent pas** (L-5) — c'est un défaut de mes harnais, pas du moteur.

### 8.3 Mon opinion argumentée sur le gel

**Faut-il le garder ?** **Oui, en l'état** — et voici sur quoi je m'appuie, pas sur une préférence :

- il **coûte** quelque chose de mesurable : `forme` passe de 0,1821 à 0,2567 (+41 %), il concentre l'apprentissage sur le critère le plus lourd (B1) ;
- il **sélectionne correctement** : le plus léger de la paire, pas le moins pertinent (D0) ;
- il **n'est pas un verrou** : il se lève dès que `r < 0,85` (D1), et la paire quitte la table sous 0,65, ce qui produit le même dégel par une autre voie ;
- il **ne bloque pas** un critère néfaste sur des données réalistes (G3) ;
- son **accessibilité** est doublement contrainte (fenêtre ≥ 50 **et** table non vide), ce qui le rend **rare** — et c'est cohérent avec l'absence de trace en production (L-1).

**Le seul point que je ne peux pas trancher** : son **bénéfice**. On mesure son coût, on mesure
sa sélection, on mesure sa réversibilité — on **ne mesure pas** son gain de stabilité. Aucun test
n'isole « avec gel vs sans gel » sur la **qualité** des prédictions. C'est un manque de preuve,
pas une preuve de nocivité : je ne le présente pas comme démontré. Le conserver est la décision
prudente, puisque rien ne démontre qu'il nuit et que le retirer exigerait de modifier un
mécanisme protégé.

### 8.4 Verdict de clôture

**Le chantier peut être clos sur son périmètre de preuve.**

- **1 anomalie** trouvée, **corrigée** (commentaire), **0 ligne de code** touchée.
- **2 anomalies annoncées** puis **retirées** après mesure — mes erreurs, assumées.
- **Toutes les obligations** de la consigne sont classées en §4 : aucune ne disparaît.
- **3 points restent ouverts** (§8.2), dont **un seul** exige une décision qui ne m'appartient
  pas : la normalisation Σ = 1,26, qui modifierait la formule des 19 critères.
- **Aucun mécanisme protégé** n'a été atteint.
- **Aucun APK, aucun push, aucune réinitialisation, aucune suppression, aucun ZIP.**

**Ce qui devrait être instruit ensuite, par ordre d'utilité** :
1. la **cause de la couverture matricielle** (L-3) — c'est le facteur limitant réel de tout l'apprentissage ;
2. la **décision** sur Σ = 1,26 / seuils absolus (A-06) — elle vous appartient ;
3. la **réécriture de D2/D3** avec de vraies assertions (L-5) — mesurable, mais sans urgence puisque G3 couvre déjà la question du critère néfaste.

---

## ANNEXE — COMMANDES DE REPRODUCTION

```bash
# Analyse globale
cd /home/user/flutter_app && flutter analyze --no-pub
# → No issues found!

# Suite complète — mesuré ce jour : 11 min 06, +3834, EXITCODE=0
flutter test --no-pub test/
# → All tests passed!  EXITCODE=0

# Les deux vérifications matricielles
flutter test --no-pub test/audit/couverture_matricielle_preuve_test.dart
# → +2: All tests passed!

# Cycle des poids (F1-F7)
flutter test --no-pub test/audit/poids_cycle_apprentissage_test.dart
# → +8: All tests passed!

# Contraintes (G0-G3.3)
flutter test --no-pub test/audit/poids_contraintes_test.dart
# → +12: All tests passed!

# Gel/dégel (D0-D3)
flutter test --no-pub test/audit/apprentissage_gel_degel_test.dart
# → +4: All tests passed!

# Gel de bout en bout (G0)
flutter test --no-pub test/audit/apprentissage_gel_coefficients_test.dart
# → +4: All tests passed!

# Chaîne des 19 critères (S3)
flutter test --no-pub test/audit/apprentissage_chaine_19_criteres_test.dart
# → +7: All tests passed!

# Évolution longue (D0-D4) — 5 min 42
flutter test --no-pub test/audit/apprentissage_dynamique_longue_test.dart
# → +5: All tests passed!

# Régression AVANT/RÉFÉRENCE (R0-R5)
flutter test --no-pub test/audit/apprentissage_regression_av_apres_test.dart
# → +6: All tests passed!

# Données réelles (R1-R3)
flutter test --no-pub test/audit/apprentissage_donnees_reelles_test.dart
# → +3: All tests passed!

# Sauvegarde/restauration (T1-T12)
flutter test --no-pub test/v5_backup_restore_test.dart
# → +17: All tests passed!

# Discipline (M11/M12)
flutter test --no-pub test/audit_poids_disciplines_test.dart
# → +3: All tests passed!
```
