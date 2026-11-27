# CHANTIER POIDS IA — RAPPORT DÉCISIONNEL UNIQUE

**Projet** : Pronostic-Hippique-V2 / « Race Predictor »
**Portée** : étude décisionnelle des pondérations des 19 critères. **Aucune
modification de production.**
**Branche** : `main`, commit de base `b3a0107`, mesures commitées `cd788bc`.
**Aucun push GitHub. Aucun APK. Aucun recalcul historique. Aucun reset.**

---

## 0. AVERTISSEMENT DE MÉTHODE, ET AVEU D'ERREURS

Ce rapport contient trois choses que l'utilisateur exige de distinguer
strictement :

1. des **mesures** (chiffres reproductibles par un harnais nommé) ;
2. des **lectures** de ces mesures (interprétation, toujours signalée) ;
3. des **hypothèses non prouvées** (signalées comme telles, jamais promues).

**Trois de mes propres hypothèses ont été réfutées par la mesure pendant ce
chantier.** Elles sont conservées dans le code avec la correction visible,
parce que les effacer reviendrait à masquer le raisonnement :

| Mon affirmation intermédiaire | Ce que la mesure a établi | Où |
|---|---|---|
| « la hiérarchie des poids est verrouillée mathématiquement » | **FAUX** : 0 paire verrouillée sur 342. Toute paire peut être inversée dans la boîte admissible. | `A3` |
| « à discrimination égale, l'ordre des poids ne bouge pas (ancrage) » | **FAUX** : l'ordre change. Les valeurs de départ sont **oubliées**, les poids convergent vers un point fixe. | `A6`, `A11` |
| « le rapport `forme`/`repos` au point fixe vaut exactement 1/0,3 » | **FAUX** : 3,571429. L'écart est dû au **plafond de groupe** qui épingle la base à 0,60. | `A11` |

**Corollaire de méthode** : je n'annonce ci-dessous comme *démontré* que ce
qu'un harnais mesure, et je signale chaque fois la **taille d'échantillon**
et la **réserve chronologique**.

---

## 1. LES QUATRE TABLES DE POIDS — MESURÉES, PAS SUPPOSÉES

### 1.1 Sommes réelles

| Table | Source | Somme mesurée |
|---|---|---|
| Constructeur | `ia_memory_models.dart:592-612` | **1,260000000** |
| `.defauts` | `ia_memory_models.dart:943` | **1,260000000** |
| `fromJson` (repli) | `ia_memory_models.dart:846-869` | **1,370000000** |
| `clampDiscipline` (repli) | `ia_memory_models.dart:785-804` | **1,000000000** après division interne |

*Preuve* : `test/audit_poids_familles_test.dart` (20/20 verts, M1/M2).

### 1.2 La seule divergence entre les familles

| Critère | Constructeur | `.defauts` | `fromJson` | `clampDiscipline` | Verdict |
|---|---|---|---|---|---|
| `forme` | 0,250000 | 0,250000 | **0,320000** | 0,245161 | **DIVERGENT** |
| les 18 autres | identiques | identiques | identiques | normalisés | cohérent |

*Mesure brute* : `forme | 0.2500000000 | 0.2500000000 | 0.3200000000 | 0.2451612903 | ⚠ DIVERGENT`.

**Lecture** : constructeur et `.defauts` sont **strictement identiques**. Une
seule valeur diffère réellement : le repli de `forme` dans `fromJson`
(0,32 au lieu de 0,25). Ce n'est pas une incohérence de conception : c'est une
valeur de repli **plus ancienne** (période où `forme` pesait 32 %), restée
telle quelle lors du rééquilibrage. Elle ne s'applique **que** si la clé
`forme` est absente d'un JSON sauvegardé — cas qui ne se produit pas sur un
sauvegarde normale (le champ est toujours écrit).

### 1.3 Le fait que je n'avais pas anticipé : deux échelles coexistent

`_calculerScoreBrutEtCriteres` (`ia_pronostic_engine.dart:391-409`) calcule une
somme pondérée **sans diviser par le total des poids**. Tant que l'IA n'a jamais
appris, la somme vaut 1,26 et le score composite peut atteindre **126,00** pour
100 partout. Après `clamp()`, il plafonne à **100,00**.

*Preuves* : `A5` (somme 1,26), `A1` (somme 1,00), `C3` (score max 126 vs 100).

**Conséquence MESURÉE, et elle n'est pas cosmétique** — `poids_echelle_test.dart`,
C1, 2000 courses simulées, seules les poids changent d'échelle, mêmes notes :

| Indicateur | Valeur mesurée |
|---|---|
| Classements modifiés par la seule échelle | **1 268 / 2000 = 63,40 %** |
| TOP1 différent | **104 / 2000 = 5,20 %** |
| TOP3 différent | **230 / 2000 = 11,50 %** |
| Écart de rang maximum | 4 places |

**Pourquoi** : `_normaliserScores` (`ia_pronostic_engine.dart:224-242`) écrit
`score = 0,60 × normalisé + 0,40 × brut`. La composante *normalisée* est
invariante d'échelle, la composante *brute* ne l'est pas : le mélange
40/60 rend donc le classement **dépendant de l'échelle absolue des poids**.
Ce n'est pas une hypothèse, c'est l'arithmétique du code, vérifiée par
l'identité `C2` : l'écart entre deux chevaux vaut exactement
`Δnote × Δpoids`, donc il est proportionnel à l'échelle.

---

## 2. CAPACITÉ RÉELLE D'APPRENTISSAGE — LA RÉPONSE DU §4

### 2.1 Ce qui est DÉMONTRÉ : aucune impossibilité individuelle

`A3` — matrice complète des 342 paires ordonnées, calculée sur la boîte
admissible **exacte** (`clamp()` réel, validé par `A0` sur 7 600 comparaisons) :

> **0 paire verrouillée sur 342 (0,0 %).**

Chaque critère peut, dans la boîte admissible, **dépasser chacun des 18
autres**. Il n'existe donc **aucune limitation mathématique individuelle**.

Cela **réfute** mon hypothèse de départ et, surtout, cela **réfute** une
lecture paresseuse des mesures antérieures (`M9`, `M10`) qui concluaient
« l'inversion est structurellement impossible ». Ces mesures étaient justes
**pour un scénario donné** (discrimination concentrée sur un seul critère,
les autres à zéro) ; elles ne mesuraient pas la boîte admissible.

### 2.2 Ce qui est DÉMONTRÉ : quelle est la vraie limite

`A11` — discrimination **strictement identique** sur les 19 critères,
5 000 cycles de gradient réels :

| Groupe de facteur | Valeur de convergence |
|---|---|
| 7 critères de base (facteur 1,0) | **0,085714286** = 0,60/7 |
| facteur 0,5 (`distSpec`, `jockey`, `elo`, `terrain`, `mouvCote`) | **0,040000000** |
| facteur 0,4 (`hippo`, `entraineur`, `divergence`, `progression`) | **0,032000000** |
| facteur 0,3 (`repos`, `poidsRel`, `placeDepart`) | **0,024000000** |

Deux faits en découlent, tous deux mesurés :

1. **Les valeurs de départ sont OUBLIÉES.** Les 7 critères de base partent de
   0,02 / 0,04 / 0,08 / 0,09 / 0,10 / 0,13 / 0,25 et convergent **tous** vers la
   même valeur 0,085714286. Vérifié : `les 7 de base sont-ils TOUS égaux à
   0,60/7 ? → true`.
2. **Le point fixe ne dépend QUE du facteur de gradient, jamais de la
   discrimination observée**, tant qu'elle est constante et égale.

> **C'est la limitation réelle, et elle est démontrée :** le gradient ne
> « dose » pas les poids selon l'importance hippique ; il les pousse vers un
> point fixe déterminé par les **constantes du code** (facteurs 1,0/0,5/0,4/0,3
> et plafonds de groupe). Une différenciation entre critères ne peut naître que
> si leurs discriminations **diffèrent** — ce qui dépend entièrement de
> l'alimentation des critères, pas du mécanisme d'apprentissage.

### 2.3 Ce qui est DÉMONTRÉ : la borne basse est atteignable, mais elle bloque

`A9` — `forme` seule pénalisée (discrimination −0,50) : elle descend de 0,25 à
**0,050000** en 10 cycles puis **n'en bouge plus**. Le minimum mathématique
serait 0,017647 : il est **inatteignable par gradient**, car `clamp()` la
ramène à 0,05 à chaque cycle.

> Un critère fort **peut** perdre 80 % de son poids. Il ne peut pas descendre
> sous son plancher individuel.

### 2.4 Ce qui est DÉMONTRÉ sur les données réelles : la famille enrichie est écrasée

C'est le résultat le plus lourd du chantier. Source : les deux backups réels.

| Mesure | Valeur |
|---|---|
| Somme des **planchers individuels** des 12 enrichis | **0,160000** |
| **Plancher de groupe** de `normaliser()` | **0,180000** |
| ⇒ Marge de liberté totale des 12 enrichis | **0,020000** |
| ⇒ soit, par critère, en moyenne | **0,001667** |

Poids réellement observés dans le backup du 13/11/2026 (3 871 mises à jour) :

| Critère | Défaut | 28/05 (802 maj) | 13/11 (3 871 maj) | Sur une borne ? |
|---|---|---|---|---|
| `cote` | 0,08000 | 0,38382 | **0,40181** | **PLAFOND** |
| `victoires` | 0,04000 | 0,11978 | **0,15068** | **PLAFOND** |
| `gains` | 0,13000 | 0,03963 | **0,04018** | **PLANCHER** |
| `record` | 0,10000 | 0,02972 | **0,03014** | **PLANCHER** |
| `discipline` | 0,02000 | 0,00991 | **0,01005** | **PLANCHER** |
| `jockey` | 0,07000 | 0,01995 | **0,02009** | **PLANCHER** |
| `elo` | 0,05000 | 0,00997 | **0,01005** | **PLANCHER** |
| `terrain` | 0,05000 | 0,00997 | **0,01005** | **PLANCHER** |
| `repos`, `hippo`, `entraineur`, `divergence`, `poidsRel`, `progression`, `placeDepart` | 0,03–0,04 | 0,00997 | **0,01005** | **PLANCHER** |
| `mouvCote` | 0,06000 | 0,01995 | **0,02009** | **PLANCHER** |
| `forme` | 0,25000 | 0,14196 | 0,05877 | — |
| `constance` | 0,09000 | 0,09517 | 0,12395 | — |
| `distSpec` | 0,08000 | 0,05035 | 0,05383 | — |

**16 des 19 critères sont à moins de 2 % d'une borne** après 3 871 mises à
jour. L'apprentissage ne cherche pas des valeurs intermédiaires : il pousse
contre les bornes.

Et la **signature arithmétique** est sans ambiguïté (`H4`) : le rapport interne
de la famille enrichie est **identique à 10⁻⁶ près** entre mai (802 maj) et
novembre (3 871 maj) pour **11 des 12 enrichis**. Il vaut exactement 1,0 ou 2,0
— c'est-à-dire le rapport de leurs **planchers** (0,01 vs 0,01 et 0,02).
Seul `distSpec` bouge (écart 0,309555), parce qu'il est le seul à ne pas être
sur son plancher.

> **Conclusion §4, en trois niveaux distincts :**
> - **13 des 19 critères sont incapables de devenir importants** : les 12
>   enrichis sont écrasés sur un plancher de groupe quasi saturé (marge
>   0,020000), et `discipline` est sur son plancher propre. Ce n'est **pas**
>   une impossibilité mathématique individuelle (A3), c'est une **contrainte
>   de groupe démontrée** (H1/H4).
> - **Les 7 critères de base peuvent réellement changer de rang**, et l'ont
>   fait : `cote` est passé de 8ᵉ à 1ᵉʳ (×5,02) et `forme` de 1ᵉʳ à
>   quasi-dernier (×0,24). La promotion **est** mesurée comme possible.
> - **Mais le mécanisme ne récompense pas la pertinence hippique** : à
>   discrimination égale, le résultat est fixé par les constantes, pas par les
>   résultats (A11). C'est une limitation **démontrée**, pas une convergence
>   lente.

### 2.5 Ce que cette promotion a réellement produit sur la qualité

`H3` le montre et je ne le maquille pas : la promotion de `cote` à 0,40 est
une **conséquence du mécanisme**, pas une preuve de sa pertinence. Sur le
corpus réel (voir §3), `cote` seule atteint un niveau comparable à
l'ensemble des 19 critères. Il est donc impossible d'affirmer que la montée de
`cote` a amélioré les pronostics : **on ne confond pas hausse de poids et
hausse de qualité.**

---

## 3. COMPARAISONS SUR CORPUS RÉEL — CE QUE LES DONNÉES PERMETTENT

### 3.1 Le corpus, mesuré

| Source | Pronostics | Avec `scoresCriteres` **et** arrivée |
|---|---|---|
| Backup 28/05/2026 | 572 | **47** |
| Backup 13/11/2026 | 600 | **4** |

*Preuve* : `poids_comparaisons_reelles_test.dart`, `E1`.

> **Réserve déclarée** : 47 et 4. À n = 4, un seul cheval déplace le TOP1 de
> 25 points. **Aucune conclusion n'est tirée de novembre.** Toute la suite
> porte sur n = 47.

Couverture par discipline (tous pronostics, y compris sans `scoresCriteres`) :
Attelé 266/295, Plat 208/196, Haies 40/41, Monté 33/45, Steeple 21/18,
Cross 4/5.

### 3.2 Comparaison des pondérations (`E2`, corpus mai, n = 47)

| Pondération | TOP1 | TOP3 | TOP5 | Rang moyen |
|---|---|---|---|---|
| Poids **défaut** (constructeur) | 23,40 % | 46,81 % | 70,21 % | 4,09 |
| Poids **appris mai** | 29,79 % | 57,45 % | 78,72 % | 3,64 |
| **Uniforme** (1/19 partout) | 23,40 % | 48,94 % | 74,47 % | 4,00 |
| **Cote seule** (référence externe) | 29,79 % | 51,06 % | 78,72 % | 3,66 |

> **Deux réserves, cumulatives :**
> 1. Les poids « appris mai » ont été appris **sur ces 47 mêmes courses**. Leur
>    score est **in-sample** : ce n'est pas une validation.
> 2. n = 47 ⇒ un écart de ±5 points de TOP1 vaut 2 à 3 courses et n'est **pas
>    significatif**.
>
> **Ce qui reste défendable malgré ces réserves** : « cote seule », qui
> n'utilise **aucun** des 18 autres critères, atteint **le même TOP1 (29,79 %)**
> et le même TOP5 que les 19 critères appris. L'apport mesurable des 18 autres
> critères sur cet échantillon est donc **nul à non démontré**.

### 3.3 Pouvoir discriminant réel par critère (mesure décisive)

Sur les courses exploitables, nombre de courses où le critère a une
**variance nulle** (même note pour tous les partants) — un critère à variance
nulle ne peut **mathématiquement pas** influencer le classement :

| Critère | Variance nulle | Range moyen |
|---|---|---|
| `record` | **100,0 %** (52/52) | 0,00 |
| `discipline` | **100,0 %** (52/52) | 0,00 |
| `repos` | **100,0 %** (52/52) | 0,00 |
| `entraineur` | **100,0 %** (52/52) | 0,00 |
| `terrain` | **100,0 %** (52/52) | 0,00 |
| `poidsRel` | **100,0 %** (52/52) | 0,00 |
| `mouvCote` | **100,0 %** (52/52) | 0,00 |
| `placeDepart` | **100,0 %** (52/52) | 0,00 |
| `elo` | 84,6 % (44/52) | 1,38 |
| `victoires` | 23,1 % (12/52) | 34,27 |
| `jockey` | 15,4 % (8/52) | 22,06 |
| `gains` | 1,9 % | 70,27 |
| `constance` | 1,9 % | 72,96 |
| `forme` | 0,0 % | 63,67 |
| `cote` | 0,0 % | 51,45 |
| `distSpec` | 1,9 % | 50,60 |
| `hippo` | 1,9 % | 59,05 |
| `divergence` | 1,9 % | 52,19 |
| `progression` | 1,9 % | 8,44 |

**9 critères sur 19 n'ont AUCUN effet mesurable** dans la moitié des cas ou
plus. Pire : `E3` mesure que **9 critères mis à zéro ne changent strictement
rien** au classement sur les 47 courses — `record`, `discipline`, `repos`,
`entraineur`, `elo`, `terrain`, `poidsRel`, `mouvCote`, `placeDepart`.

> **Nuance exigée par l'utilisateur, et elle est juste** : un critère neutre
> dans le corpus **n'est pas nécessairement inutile** ; il peut être
> **mal alimenté**. C'est le cas ici : `mouvCote` est neutre *par conception*
> hors de la fenêtre des 30 minutes ; `elo` est bloqué à 37,5–42 sur presque
> tous les chevaux ; `terrain`, `poidsRel`, `placeDepart`, `entraineur`,
> `repos`, `record` valent 50,0 constant. La chaîne d'alimentation est en
> cause, **pas la pertinence hippique du critère**.

### 3.4 Neutralisation individuelle (`E3`, poids défaut, n = 47)

Effets non nuls uniquement : `gains` (+4,26 TOP1 / +8,51 TOP3 en le retirant
!), `jockey` (+8,51 TOP3), `constance` (+8,51 TOP3), `cote` (+6,38 TOP3),
`hippo` (+4,26), `divergence` (+4,26), `forme` (−2,13), `distSpec` (+2,13),
`victoires` (+2,13), `progression` (+2,13).

> **Lecture, à ne pas surinterpréter** : retirer `gains` ou `jockey` *améliore*
> le TOP3 sur cet échantillon. À n = 47, cela représente 4 courses. Ce n'est
> **pas** une preuve que ces critères nuisent : c'est un signal qui justifie
> un protocole prospectif, rien de plus.

---

## 4. §5 — LES 19 CRITÈRES PAR SPÉCIALITÉ : CE QUI EST PROUVABLE

**Limite honnête** : la réévaluation par spécialité exige des effectifs par
discipline. Mesurés : Attelé 266+295, Plat 208+196, Monté 33+45, Haies 40+41,
Steeple 21+18, Cross **4+5**. **Cross-country n'est pas évaluable** (9 cas).
Et les `scoresCriteres` exploitables ne sont que 47 au total, toutes
disciplines confondues. **Je ne peux donc pas produire un tableau par
spécialité qui soit autre chose qu'une impression.** Je le déclare plutôt que
de l'inventer.

Ce qui **est** mesuré et exploitable :

| Constat | Mesure |
|---|---|
| `mouvCote` neutre hors fenêtre 30 min | 100 % de variance nulle sur 52 courses |
| `elo` quasi constant | 84,6 % de variance nulle, range moyen 1,38 pt |
| 7 critères à 50,0 constant | `record`, `discipline`, `repos`, `entraineur`, `terrain`, `poidsRel`, `placeDepart` |
| Corrélations | non mesurables : le gel n'agit qu'à partir de **50 courses** dans la fenêtre, et l'état `correlations` n'est pas renseigné dans ces backups |

**Sur les interactions exigées** (forme × constance × distance × spécialité ×
gains × victoires × cote × ELO) : elles ne peuvent pas être mesurées sur 47
courses sans produire du bruit. **Non mesuré, donc non affirmé.**

---

## 5. §7 — COMPARAISON AVEC LES MÉTHODES EXTERNES

Trois catégories, strictement séparées :

**a) Scientifiquement documenté (modèles à choisir comme référence)**
- **Bolton & Chapman (1986)**, *Searching for Positive Returns at the Track:
  A Multinomial Logit Model for Handicapping Horse Races* — modèle logit
  multinomial conditionnel, longtemps « gold standard » du domaine.
- **Benter (1994)**, *Computer Based Horse Race Handicapping and Wagering
  Systems: A Report* — même famille (logit multinomial), avec une démarche
  explicite de combinaison modèle + marché.
- **Figlewski (1979)**, **Sung & Johnson (2007)**, **Ali (1998)** — variantes
  et évaluations.

**b) Programme vérifiable** : `SimulationService` de notre propre app, et les
harnais de ce rapport. Ce sont les seules méthodes dont je peux vérifier le
code ligne par ligne.

**c) Allégations commerciales** : non traitées. Je n'ai vérifié aucun logiciel
commercial et je ne reprends aucun coefficient d'un tiers.

> **Point méthodologique capital, et il va contre un réflexe tentant** : ces
> modèles documentés **ne sont pas transposables** à notre architecture. Un
> logit multinomial estime des **coefficients par maximum de vraisemblance sur
> une fonction de choix** (probabilité de gagner), avec des **écarts
> normalisés entre chevaux**. Notre moteur fait une **somme pondérée de notes
> 0-100, puis un mélange min-max**. Ce sont deux objets mathématiques
> différents : transposer des coefficients n'aurait aucun sens.
> **Ce qui EST transposable, c'est le protocole d'évaluation** : séparation
> stricte apprentissage/validation, mesure hors échantillon, et comparaison à
> la cote du marché comme référence — exactement ce que §3 fait déjà.

---

## 6. §8 — RAPPORT DÉCISIONNEL, PROBLÈME PAR PROBLÈME

### P1 — Deux échelles de poids coexistent (1,26 et 1,00)

| | |
|---|---|
| **Fichiers** | `ia_pronostic_engine.dart:391-409` (somme brute) ; `ia_memory_models.dart:685-728` (`normaliser`) |
| **Cause exacte** | Le score est une somme pondérée **non divisée**. `clamp()` n'est appelé qu'après apprentissage ; `poidsEffectifsPourDiscipline` renvoie les poids bruts tant qu'aucune discipline n'est apprise. |
| **Conséquences réelles** | Score max 126 au lieu de 100 avant apprentissage ; **63,40 % des classements changent** selon l'échelle seule (C1) ; les seuils absolus (`seuilSimpleGagnant` 80…) sont franchis plus facilement avant apprentissage qu'après. |
| **Preuves** | `A1`, `A5`, `C1`, `C2`, `C3`, `M12.2` |
| **Correction proposée** | Normaliser les poids à la **source** (dans `_calculerScoreBrutEtCriteres`, diviser par la somme des poids effectifs) — ou garantir que tout poids servi est passé par `clamp()`. |
| **Avantages** | Une seule échelle ; seuils absolus interprétables ; suppression d'un facteur de 63,40 % de variabilité non contrôlée. |
| **Risques** | Change **tous** les scores actuels ⇒ déplace les seuils de labellisation. Touche la formule ⇒ **DÉCISION UTILISATEUR OBLIGATOIRE**. |
| **Conséquence apprentissage** | Aucune sur la dynamique du gradient ; forte sur la lisibilité des seuils. |
| **Tests avant adoption** | `C1` doit passer de 63,40 % à 0 % de classements modifiés. |

### P2 — Les 12 critères enrichis sont écrasés sur leur plancher

| | |
|---|---|
| **Fichiers** | `ia_memory_models.dart:699` (`fractionEnrichi.clamp(0.18, 0.40)`), `:731-750` (bornes individuelles) |
| **Cause exacte** | Somme des planchers individuels des 12 enrichis = **0,160000** pour un plancher de groupe de **0,180000**. Il ne reste que **0,020000** à répartir. |
| **Conséquences réelles** | 11 des 12 enrichis ont des proportions internes **figées** (H4) ; 9 critères sans aucun effet sur le classement (E3). |
| **Preuves** | `H1`, `H2`, `H4`, `E3` |
| **Correction proposée** | Abaisser les **planchers individuels** des enrichis (ex. 0,005 au lieu de 0,01) OU relever le plancher de groupe. **Ne pas** toucher au plafond de 0,40 sans mesure. |
| **Avantages** | Rend la famille enrichie capable d'exprimer une hiérarchie. |
| **Risques** | Touche `clamp()` ⇒ **DÉCISION UTILISATEUR**. Peut déstabiliser des poids appris. |
| **Conséquence apprentissage** | Rend enfin l'apprentissage possible sur 12 critères aujourd'hui inertes. |
| **Tests avant adoption** | `H1` doit montrer une marge ≫ 0,02 ; `H4` doit voir les rapports internes **bouger** entre deux époques. |

### P3 — 9 critères n'ont aucun effet mesurable

| | |
|---|---|
| **Fichiers** | Chaîne d'alimentation : `ia_pronostic_engine.dart` (`_scoreRecord`, `_scorePlaceDepart`, `scoreMouvementCote`, ELO) |
| **Cause exacte** | Notes **constantes** (50,0 ou 37,5) ⇒ variance nulle ⇒ le critère ne peut pas classer. `mouvCote` est neutre **par conception** hors fenêtre 30 min. |
| **Conséquences réelles** | `record`, `discipline`, `repos`, `entraineur`, `elo`, `terrain`, `poidsRel`, `mouvCote`, `placeDepart` : neutralisation = **Δ 0,00** (E3). |
| **Preuves** | §3.3 (100 % / 84,6 % de variance nulle), `E3` |
| **Correction proposée** | Traiter **l'alimentation**, pas les poids : un poids élevé sur un critère neutre est sans effet. C'est un chantier distinct du chantier des poids. |
| **Avantages** | C'est ici que se trouve le gain réel de qualité, pas dans les pondérations. |
| **Risques** | Aucun sur la formule ; risque de données manquantes PMU. |
| **Conséquence apprentissage** | Un critère qui discrimine **peut** alors être appris (A11 : la différenciation exige une discrimination différente). |
| **Tests avant adoption** | Mesurer la variance nulle par critère **avant/après** correction d'alimentation. |

### P4 — Le point fixe du gradient ignore la pertinence (A11)

| | |
|---|---|
| **Fichiers** | `ia_memory_service.dart:4018-4021` (lr), `:4066-4088` (facteurs), `:4093` (`clamp()`) |
| **Cause exacte** | À discrimination constante, la convergence ne dépend que des facteurs 1,0/0,5/0,4/0,3 et des plafonds de groupe. |
| **Conséquences réelles** | Les valeurs de départ sont **oubliées** (bien) ; mais la hiérarchie finale est dictée par les constantes (mal). |
| **Preuves** | `A6`, `A11` |
| **Correction proposée** | **À ÉTUDIER PROSPECTIVEMENT**, pas à corriger à l'aveugle : le comportement est arithmétiquement sain. Le vrai levier est P3. |
| **Risques** | Modifier les facteurs = toucher l'apprentissage ⇒ **interdit sans autorisation**. |

### P5 — Divergence `forme` du repli `fromJson` (0,32 vs 0,25)

| | |
|---|---|
| **Fichier** | `ia_memory_models.dart:846` |
| **Cause exacte** | Valeur de repli historique jamais réactualisée. |
| **Conséquences réelles** | **Aucune en pratique** : la clé `forme` est toujours écrite par `toJson` (`:815`). Ne s'applique qu'à un JSON tronqué. |
| **Preuves** | `M2` (20/20) ; les deux backups réels contiennent bien les 19 clés. |
| **Verdict** | **À CORRIGER pour cohérence documentaire**, sans urgence fonctionnelle. Mettre 0,25. |
| **Risques** | Nul. |
| **Tests** | `audit_poids_familles_test` doit voir 4 familles concordantes sur `forme`. |

### P6 — Somme déclarée 1,26 ≠ 1,00 (documentation)

| | |
|---|---|
| **Fichiers** | `ia_memory_models.dart:569-620` (commentaires déjà corrigés par mesure) |
| **État** | **DÉJÀ CORRIGÉ** lors d'un chantier antérieur : le code porte désormais la mesure exacte et signale que l'arbitrage est une décision utilisateur. |
| **Verdict** | **À CONSERVER tel quel** — c'est de la documentation honnête. |

### P7 — `poidsParDiscipline` inopérant tant qu'il est vide

| | |
|---|---|
| **Fichiers** | `ia_memory_models.dart:634-670` ; `ia_memory_service.dart:4288` |
| **Cause exacte** | `poidsEffectifsPourDiscipline` renvoie les globaux si la map est vide. |
| **Conséquences réelles** | Écart inter-disciplines **exactement 0,0000000000** sur état vierge (`M12.1`). Après apprentissage d'**une** discipline, deux échelles coexistent (P1). |
| **Preuves** | `M12.1`, `M12.2`, `M12.3` (écart de score 1,119 en Trot attelé vs 1,200 en Plat) |
| **Verdict** | **À CONSERVER le mécanisme**, **À CORRIGER** l'échelle (voir P1). |

### P8 — Absence de protocole de validation hors échantillon

| | |
|---|---|
| **Cause** | Le corpus réel ne contient `scoresCriteres` que sur 47 courses (mai) et 4 (novembre). |
| **Conséquences réelles** | Toute comparaison de pondérations est **in-sample** ⇒ aucune optimisation n'est défendable aujourd'hui. |
| **Preuves** | `E1`, `E4` |
| **Correction proposée** | **PROTOCOLE PROSPECTIF** (voir §7) : accumuler, puis n'évaluer à T que les pronostics postérieurs à T. |
| **Risques** | Aucun. |
| **Verdict** | **À ÉTUDIER PROSPECTIVEMENT — c'est la seule voie honnête.** |

---

## 7. PROPOSITION COHÉRENTE SUR LES 9 POINTS

Pour chaque point, conclusion explicite : **garder / corriger / supprimer si
vraiment inutile / étudier prospectivement**.

| # | Élément | Conclusion | Justification mesurée |
|---|---|---|---|
| 1 | **Poids initiaux des 19 critères** | **GARDER** | Aucune mesure ne démontre qu'un autre jeu initial produirait de meilleurs pronostics. Les valeurs de départ sont de toute façon **oubliées** par le gradient (A11). Les changer ne changerait donc presque rien à long terme — c'est mesuré, pas supposé. |
| 2 | **Valeurs de repli** | **CORRIGER (1 seule)** : `forme` 0,32 → 0,25 dans `fromJson` | Seule divergence réelle entre les 4 familles (M2). Sans effet pratique, mais l'incohérence documentaire doit disparaître. |
| 3 | **Pondérations par discipline** | **GARDER le mécanisme**, **CORRIGER l'échelle** (P1) | Le mécanisme fonctionne (`M12.3` : effet réel 1,119 vs 1,200) ; c'est l'échelle 1,26/1,00 qui perturbe. |
| 4 | **Bornes d'évolution** | **CORRIGER** : abaisser les planchers individuels des 12 enrichis | Mesure décisive : 0,160000 de planchers pour 0,180000 de plancher de groupe ⇒ marge 0,020000. **DÉCISION UTILISATEUR OBLIGATOIRE** (touche `clamp()`). |
| 5 | **Coefficients d'apprentissage** | **NE PAS TOUCHER — ÉTUDIER PROSPECTIVEMENT** | Ils ne sont **pas** la cause du désavantage : `A12` mesure 2 à 6 cycles pour parcourir 50 % de la plage, tous facteurs confondus. Le frein n'est pas la vitesse. |
| 6 | **Contraintes de répartition par famille** | **CORRIGER** : le plancher de groupe 0,18 est saturé par les planchers individuels | Voir point 4. Le plafond 0,40, lui, **n'est pas** la contrainte dominante dans les données réelles (Σ enrichis = 0,1844). |
| 7 | **Gestion des corrélations** | **ÉTUDIER PROSPECTIVEMENT** | Non mesurable ici : le gel exige **50 courses** et `correlations` est vide dans les deux backups. Aucune affirmation possible. |
| 8 | **Capacité d'évolution des 19 critères** | **13 incapables / 6 capables** | Mesuré : les 12 enrichis sont écrasés (marge 0,020000) et `discipline` est sur son plancher ; les 6 autres peuvent réellement permuter (`cote` ×5,02, `forme` ×0,24). **Ce n'est PAS une impossibilité mathématique** (A3 : 0/342 paires verrouillées). |
| 9 | **Protocole de validation après le futur zéro-redémarrage** | **ÉTUDIER PROSPECTIVEMENT — obligatoire** | Le corpus actuel ne le permet pas (47 courses). Protocole : n'exécuter une comparaison qu'avec `scoresCriteres` ET `arriveeReelle`, séparer strictement les dates, viser n ≥ 200, comparer à « cote seule » comme référence externe. |

### Ce que je ne propose PAS, et pourquoi

- **Je ne propose pas d'unifier les 4 tables.** Mesure : constructeur et
  `.defauts` sont **identiques**, `clampDiscipline` **doit** normaliser (c'est
  un autre espace), et `fromJson` n'est qu'un repli. Unifier détruirait une
  distinction légitime entre *valeur initiale*, *repli* et *espace normalisé*.
- **Je ne propose pas de relever le plafond des enrichis à 0,40.** Les données
  réelles montrent Σ enrichis = 0,1844, **très loin** du plafond. Le plafond
  n'est pas le problème : les **planchers** le sont.
- **Je ne propose aucune modification « parce qu'elle semble meilleure ».** Ex.
  retirer `gains` (E3 : +8,51 TOP3) n'est fondé que sur 4 courses.

---

## 8. TRAÇABILITÉ — OÙ CHAQUE CHIFFRE EST REPRODUCTIBLE

| Harnais | Tests | Ce qu'il établit |
|---|---|---|
| `test/audit_poids_familles_test.dart` | 20 | Sommes des 4 familles, divergence `forme` |
| `test/audit_poids_mecanique_test.dart` | 7 | placeDepart vs forme, contre-factuels |
| `test/audit_poids_comparaison_test.dart` | 4 | Actuel vs historique |
| `test/audit_poids_disciplines_test.dart` | 6 | M11/M12, effet inter-disciplines |
| `test/audit/poids_plage_atteignable_test.dart` | 12 | `A3` (0/342 verrou), `A11` (point fixe), `A9` (plancher) |
| `test/audit/poids_echelle_test.dart` | 3 | `C1` (63,40 %), `C2`, `C3` |
| `test/audit/poids_limite_structurelle_test.dart` | 4 | `H1`–`H4` sur backups réels |
| `test/audit/poids_comparaisons_reelles_test.dart` | 4 | `E1`–`E4`, corpus réel |

**Total : 60 tests verts, `flutter analyze lib/ test/` : `No issues found!`**

**Aucune production modifiée.** Aucun push. Aucun APK. Aucun recalcul
historique. Aucun reset. Aucune donnée fabriquée.

---

## 9. RÉSERVE FINALE — CE QUE CE RAPPORT NE PROUVE PAS

1. **Rien sur la qualité réelle des pronostics.** n = 47, in-sample. Les
   chiffres du §3.2 décrivent un échantillon, ils ne valident pas le modèle.
2. **Rien sur `Cross-country`** (9 cas) ni sur les interactions entre critères
   (effectif insuffisant).
3. **Rien sur les corrélations** : le gel exige 50 courses dans la fenêtre et
   `correlations` est vide dans les deux backups.
4. **Rien sur les appareils physiques** : ces harnais sont des tests Dart, pas
   des mesures sur Android.
5. **La promotion de `cote` à 0,40 n'est PAS prouvée bénéfique.** Elle est
   mesurée comme *conséquence du mécanisme* ; « cote seule » atteignant le même
   TOP1, l'apport des 18 autres critères n'est pas démontré.

**Toute lecture de ce rapport qui conclurait « l'IA apprend bien » ou « l'IA est
cassée » dépasserait ce que les mesures autorisent.** Ce qui est établi est plus
précis et plus étroit : *le mécanisme d'apprentissage est arithmétiquement sain,
mais il ne peut pas récompenser la pertinence hippique tant que 13 critères sur
19 restent bloqués par des contraintes de bornes ou une alimentation constante.*
