# RAPPORT DÉCISIONNEL UNIQUE — APPRENTISSAGE IA DES 19 CRITÈRES

**Chantier** : validation approfondie du comportement de l'apprentissage (complément du chantier poids).
**Référence** : `c31cbeff5d77f1c2de3e11da21350945d1b3838d` (HEAD de `main`).
**Environnement** : Flutter 3.35.4 / Dart 3.9.2, gelé.
**Portée** : investigation et mesure uniquement. **Aucun fichier de production modifié** — vérifié à chaque étape par `git diff --stat -- lib/` (sortie vide).
**Branche** : `main` uniquement. Aucun push, aucun APK, aucune réinitialisation, aucune modification des sauvegardes.

---

## 0. Légende des statuts

| Statut | Signification exacte |
|---|---|
| **DÉMONTRÉ** | Établi par la lecture du code de production **et** par une mesure reproductible qui ne peut s'expliquer autrement. |
| **MESURÉ** | Chiffre obtenu par exécution du moteur réel, reproductible, mais dont l'interprétation causale n'est pas entièrement démontrée. |
| **RÉFUTÉ** | Une hypothèse a été testée et les faits la contredisent. |
| **NON DÉTERMINABLE** | La mesure exigerait soit de modifier la production (interdit §2), soit des données absentes. Le motif est explicité dans chaque cas. |

**Harnais utilisés** (tous reproductibles, `flutter test <fichier> -j 1`) :

```
test/support/atelier_apprentissage.dart            (atelier partagé — n'est PAS un moteur)
test/audit/apprentissage_chaine_19_criteres_test.dart      7 tests   §3
test/audit/apprentissage_dynamique_longue_test.dart        5 tests   §6 §7 §8 §10
test/audit/apprentissage_gel_coefficients_test.dart        4 tests   §4 §5
test/audit/apprentissage_donnees_reelles_test.dart         3 tests   §11
```

État mesuré, **en deux exécutions distinctes** (et non en une seule passe, ce qui est précisé ici pour ne rien laisser croire de plus) :
- `flutter test test/audit/apprentissage_chaine_19_criteres_test.dart test/audit/apprentissage_dynamique_longue_test.dart test/audit/apprentissage_gel_coefficients_test.dart -j 1` → **`07:33 +16: All tests passed!`**, `EXITCODE=0`
- `flutter test test/audit/apprentissage_donnees_reelles_test.dart -j 1` → **`00:05 +3: All tests passed!`**

Soit **19 tests verts sur 19**, 0 échec.

**Avertissement méthodologique majeur.** Tous les harnais pilotent le **moteur de production réel** (`IaMemoryService`, `enregistrerResultat`, `_apprendreParGradient`, `_apprendreParDiscipline`, `_mettreAJourCalibration`). **Aucun second moteur n'a été écrit.** Deux tentatives de reconstruire l'arithmétique à la main ont d'ailleurs été **abandonnées et documentées comme fautives** (§3.1), ce qui confirme *a posteriori* que la règle du §2 était fondée.

---

## 1. §3 — CHAÎNE COMPLÈTE DES 19 CRITÈRES (13 points)

### 1.1 Comportement attendu
Un cycle d'apprentissage devrait produire une variation de poids dont le **signe** suit la discrimination mesurée (critère discriminant → poids monte), dont l'**amplitude** est modulée par le coefficient, et dont la **borne** est respectée. Le journal publié devrait permettre de reconstituer la variation *proposée* avant projection.

### 1.2 Comportement réellement observé

**DÉMONTRÉ — le journal ne publie pas la variation proposée, mais la variation déjà projetée.**
`JournalEntree.apres` (`poidsApres`, l.4209) est construit **après** `_poids.clamp()` (l.4176). Mesure : `journal.apres` ↔ `getPoids()` — **identiques sur 19/19 critères, écart max = 0.000000000000**. Toute lecture du journal comme source « avant projection » est donc fausse. *(Cette erreur avait été commise dans la première version du harnais, puis corrigée ; elle est documentée dans l'en-tête de `atelier_apprentissage.dart`.)*

**MESURÉ — cycle 1, `lr = 0.019200000000`, mise à jour n° 1 :**

```
critère      | discrim×100 | grad brut   | coef | proposé     | obtenu      | proj.       | Σ
forme        | 7.631e-1    | 1.465e-4    | 1.0  | 1.465e-4    | -3.891e-2   | -3.905e-2   | ↓
gains        | 7.558e-1    | 1.451e-4    | 1.0  | 1.451e-4    | -2.017e-2   | -2.032e-2   | ↓
record       | 7.484e-1    | 1.437e-4    | 1.0  | 1.437e-4    | -1.549e-2   | -1.563e-2   | ↓
cote         | 7.785e-1    | 1.495e-4    | 1.0  | 1.495e-4    | -1.236e-2   | -1.251e-2   | ↓
constance    | 7.341e-1    | 1.409e-4    | 1.0  | 1.409e-4    | -1.393e-2   | -1.407e-2   | ↓
victoires    | 7.144e-1    | 1.372e-4    | 1.0  | 1.372e-4    | -6.129e-3   | -6.266e-3   | ↓
discipline   | 7.045e-1    | 1.353e-4    | 1.0  | 1.353e-4    | -3.008e-3   | -3.143e-3   | ↓
distSpec     | 7.893e-1    | 1.515e-4    | 0.5  | 7.577e-5    | -2.184e-2   | -2.191e-2   | ↓
jockey       | 7.356e-1    | 1.412e-4    | 0.5  | 7.061e-5    | -1.910e-2   | -1.917e-2   | ↓
repos        | 7.193e-1    | 1.381e-4    | 0.3  | 4.143e-5    | -8.179e-3   | -8.221e-3   | ↓
hippo        | 7.499e-1    | 1.440e-4    | 0.4  | 5.759e-5    | -1.090e-2   | -1.096e-2   | ↓
entraineur   | 7.158e-1    | 1.374e-4    | 0.4  | 5.498e-5    | -1.091e-2   | -1.096e-2   | ↓
elo          | 7.573e-1    | 1.454e-4    | 0.5  | 7.270e-5    | -1.363e-2   | -1.370e-2   | ↓
terrain      | 7.119e-1    | 1.367e-4    | 0.5  | 6.834e-5    | -1.363e-2   | -1.370e-2   | ↓
divergence   | 6.848e-1    | 1.315e-4    | 0.4  | 5.259e-5    | -1.091e-2   | -1.096e-2   | ↓
poidsRel     | 7.385e-1    | 1.418e-4    | 0.3  | 4.254e-5    | -8.179e-3   | -8.221e-3   | ↓
progression  | 6.975e-1    | 1.339e-4    | 0.4  | 5.357e-5    | -8.171e-3   | -8.224e-3   | ↓
mouvCote     | 6.932e-1    | 1.331e-4    | 0.5  | 6.654e-5    | -1.637e-2   | -1.644e-2   | ↓
placeDepart  | 7.519e-1    | 1.444e-4    | 0.3  | 4.331e-5    | -8.178e-3   | -8.221e-3   | ↓

Σ avant = 1.260000000000 · Σ proposé = 1.261698122703 · Σ obtenu = 1.000000000000
déséquilibre proposé = 1.698123e-3
critères à signature de gel = 0
⇒ la projection RÉÉCRIT la proposition sur 19/19 critères
   amplitude max de réécriture = 3.905186e-2
```

### 1.3 Anomalie démontrée n° 1 — le gradient est intégralement réécrit, avec inversion de signe

**DÉMONTRÉ.** Les 19 discriminations mesurées sont **positives** (0.6848 → 0.7893), donc le gradient propose une **hausse** pour les 19 critères. La projection livre une **baisse** pour les 19. L'amplitude de réécriture atteint `3.905e-2` pour un gradient proposé de `1.465e-4`, soit un facteur **≈ 265×**.

**Conséquence sur l'apprentissage** : l'information directionnelle issue de la discrimination est **détruite au cycle 1**. Le moteur ne « ralentit » pas ; il **substitue** à la proposition une répartition dictée par la structure (budget de groupe + part enrichie + bornes). Ce n'est pas une hypothèse : c'est la comparaison terme à terme des deux états, mesurée 19 fois.

### 1.4 « Peu pertinent » vs « insuffisamment alimenté » — distinction tenue

**MESURÉ.** `S3-3` : un seul critère reçoit des notes inversées, les 18 autres restent alignées. Résultat : ce critère obtient **discrimination = −0.026159873**, les 18 autres restent positives. Un critère réellement *peu pertinent* est donc **mesurable comme tel** (signe négatif).

**MESURÉ.** Un critère dont la note est constante (neutralisée) produit une discrimination **≈ 0** (campagnes D2, D3, G1 en contrôle). C'est la signature d'un critère *insuffisamment alimenté* — distincte du signe négatif.

⇒ **La distinction demandée au §3 est opérationnelle** : signe négatif = information défavorable ; discrimination nulle = absence d'information. Les deux ne doivent pas être traités de la même façon dans une éventuelle correction.

### 1.5 Chemins de production vérifiés

- **Global** : `_apprendreParGradient` → momentum → gel → coefficients → `clamp()` (projection). Vérifié, mesuré.
- **Par discipline** : `_apprendreParDiscipline` — **MESURÉ** : 19 clés, Σ = 1.0, écart max vs global `0.010684552427`, 19/19 valeurs distinctes. **DÉMONTRÉ** : ce chemin n'a **ni momentum ni gel** (lecture l.4255-4430, aucun accès à `dernierGradient` ni `criteresGeles`), et il est réécrit par `clampDiscipline`.

### 1.6 Limites de la preuve
- Les notes 0–100 sont **injectées par le harnais** ; c'est le seul levier légal (le harnais ne peut pas influencer l'algorithme, seulement les données). Les conclusions portent donc sur le **comportement du moteur pour des entrées données**, pas sur la pertinence réelle des 19 critères hippiques.
- Un seul cycle détaillé ici ; la dynamique multi-cycles est au §8/§10.

---

## 2. §4 — COEFFICIENTS 1.0 / 0.5 / 0.4 / 0.3 CONTRE 19 × 1.0

### 2.1 Comportement attendu
Une comparaison expérimentale suppose de pouvoir **injecter** une autre table de coefficients dans le moteur réel, à données et poids initiaux identiques.

### 2.2 Statut : **NON DÉTERMINABLE AVEC LES DONNÉES DISPONIBLES**

**DÉMONTRÉ (lecture)** : les 19 coefficients sont **codés en dur** dans un `switch` sur le nom du critère, aux lignes **4148-4172** de `lib/services/ia_memory_service.dart`. Il n'existe **aucun point d'injection** : ni paramètre, ni champ de modèle, ni constante exposée.

Deux voies étaient possibles, toutes deux fermées :
1. **Modifier la production** pour rendre la table paramétrable → interdit par le §2.
2. **Rejouer l'arithmétique dans un harnais** avec 19 × 1.0 → c'est exactement « un second moteur susceptible de diverger du moteur réel », interdit par le §2. Précédent mesuré dans ce dépôt : `poids_plage_atteignable_test.dart` réimplémente l'arithmétique (helper `cycle()`), et cette pratique est précisément ce que le §2 proscrit désormais.

⇒ **La comparaison directe demandée au §4 n'est pas réalisable sans violer le §2.** C'est un fait, pas une esquive.

### 2.3 Ce qui a pu être mesuré indirectement

**MESURÉ (D1, 300 cycles, signal identique sur les 19 critères).** L'équilibre atteint **classe les critères par coefficient**, pas par discrimination :

| coef | poids d'équilibre | exemples |
|---|---|---|
| 1.0 | 0.082–0.092 | forme 0.092478 · gains 0.087015 · record 0.085649 · cote 0.084739 · constance 0.085194 · victoires 0.082918 · discipline 0.082007 |
| 0.5 | ≈ 0.0402 | distSpec 0.040796 · jockey 0.040478 · elo 0.039841 · terrain 0.039841 · mouvCote 0.040159 |
| 0.4 | ≈ 0.0319 | hippo 0.031873 · entraineur 0.031873 · divergence 0.031873 · progression 0.031554 |
| 0.3 | ≈ 0.0239 | repos 0.023904 · poidsRel 0.023904 · placeDepart 0.023904 |

Ratios mesurés `0.0239 : 0.0319 : 0.0402` ≈ `0.3 : 0.4 : 0.5`. Stabilité : Σ = 1.000000000000, part enrichie = 0.400000000000 à t=0 **et** t=299, mouvement max sur les 50 derniers cycles = **1.125e-4**. **Aucun critère n'est « libre » au sens dynamique : les 19 sont à l'équilibre, et cet équilibre est une image des coefficients.**

**MESURÉ (G1, contre-exemple nécessaire — le coefficient n'est PAS un veto absolu).** Avec un signal fort sur `jockey` (coef 0.5) :
- `jockey` **sans** signal : `0.041780191`
- `jockey` **avec** signal : `0.054398912` → **écart +1.262e-2**
- ses 4 pairs de même coefficient (distSpec, elo, terrain, mouvCote) avec signal : moyenne `0.039238009` → **ratio jockey/pairs = 1.3864**
- `forme` (coef 1.0) : `0.107543798`

### 2.4 Conclusion §4 (formulation tenue par les deux mesures)
- **MESURÉ** : les coefficients **ne sont pas qu'un ralentissement**. À signal égal ils **fixent l'ordre d'équilibre final** (classement strictement conforme aux facteurs, écarts proportionnels aux facteurs).
- **MESURÉ** : ils n'introduisent pas pour autant un **veto absolu** — un critère à coefficient 0.5 fortement alimenté dépasse de 38,6 % ses pairs de même coefficient.
- **MESURÉ** : mais il ne peut pas franchir la barrière de coefficient — `jockey` à 0.0544 reste très loin de `forme` à 0.1075 malgré un signal ciblé.
⇒ Un critère enrichi **ne peut structurellement pas** dépasser un critère de base à alimentation comparable. La capacité « enrichi > base » demandée au §4 est donc **RÉFUTÉE** dans le régime mesuré.

### 2.5 Limites
Aucune conclusion n'est tirée sur ce que donnerait 19 × 1.0 : **ce n'est pas mesuré, ce n'est pas affirmé**. Les chiffres ci-dessus décrivent la configuration de production actuelle.

---

## 3. §5 — GEL PAR CORRÉLATION

### 3.1 Deux échecs de mesure préalables, diagnostiqués et corrigés
Documentés dans l'en-tête de `apprentissage_gel_coefficients_test.dart`, ils sont une mise en garde méthodologique :
1. **Notes constantes ⇒ variance nulle ⇒ `pearson` retourne 0.0** (garde `n < 10` / `denom == 0`, l.4500). Aucune paire n'est détectée.
2. **`varianceScores` constant ⇒ `hautConfiance.isEmpty` ⇒ `_detecterCorrelationsCriteres` n'est JAMAIS appelé.** La porte non documentée est `_mettreAJourCalibration` l.4444-4454 (retour anticipé si `avecVariance.length < 5` ou listes de confiance vides), appel l.4468.
⇒ Sans faire **varier** à la fois les notes **et** la variance des scores, le gel paraît « inactif » alors qu'il fonctionne. Ce piège a produit deux faux négatifs avant d'être levé.

### 3.2 Les 15 aspects demandés

| Aspect | Constat | Statut |
|---|---|---|
| Calcul des corrélations | Pearson par paire sur `.take(80)`, `avecScores.length >= 20` requis | **DÉMONTRÉ** (lecture) |
| Période / nombre de courses nécessaires | **171/171 paires** à r = 1.000000 dès ~15 courses ; gel effectif au **cycle 37**, quand la fenêtre atteint **50** (l.4116) | **MESURÉ** |
| Données manquantes | `pearson` renvoie 0 si n < 10 ou dénominateur nul (vecteur constant) → paire ignorée, jamais « gelée par défaut » | **DÉMONTRÉ** (lecture l.4500) |
| Corrélations négatives | **`pearson(...).abs()`** l.4520 → le **signe est écrasé** : une anti-corrélation forte est traitée comme une redondance | **DÉMONTRÉ** |
| Seuil de déclenchement | population à `r >= 0.65` (l.4521) ; gel à `r >= 0.85` (l.4119) | **DÉMONTRÉ** |
| Sélection du critère gelé | `aGeler = p1 <= p2 ? c1 : c2` → **le plus léger** est gelé | **DÉMONTRÉ** |
| Traitement des égalités | `p1 <= p2` ⇒ à égalité stricte, c'est **c1** qui gèle (première clé dans l'ordre de `kClesOrdonnees`) | **DÉMONTRÉ** |
| Remise à zéro du momentum | `momentum[c] = 0.0; continue;` pour chaque critère gelé | **DÉMONTRÉ + MESURÉ** (`gelesSuspects` : momentum 0 et proposition 0) |
| Durée du gel | **103 cycles sur 140** avec au moins un gel ; **1494 critères-gel** cumulés | **MESURÉ** |
| Fréquence de réévaluation | À chaque cycle, dès que la fenêtre ≥ 50 — mais voir ci-dessous | **DÉMONTRÉ** |
| Conditions de dégel | **Aucun seuil à 0.70 n'existe dans le code.** Le commentaire l.4113 l'annonce ; un `grep` exhaustif des 0.70 ne trouve que l.4015, 4032, 4047, 4465, 4605, tous sans rapport. Le seul « dégel » est la **fenêtre qui retombe sous 50** | **DÉMONTRÉ — désynchronisation commentaire/code** |
| Possibilité de réactivation | Oui, mesurée (G3 : dégel au cycle 299 quand la fenêtre retombe) | **MESURÉ** |
| Évolution indirecte pendant le gel | Le poids du critère gelé **continue de bouger** — la projection le déplace en tant que membre du groupe (mesuré G3 : 0.0215 → 0.0182 pendant le gel) | **MESURÉ** |
| Interactions entre paires multiples | 171 paires coexistent ; l'union des seconds membres gèle **18 critères sur 19** | **MESURÉ** |
| Global vs par discipline | `_apprendreParDiscipline` **n'a pas de gel du tout** | **DÉMONTRÉ** (lecture) |

### 3.3 Anomalie démontrée n° 2 — verrou auto-renforçant

**MESURÉ (G2, 140 cycles).**
- `[G2] cycles avec gel = 103/140 · cycles où la liste gelée est IDENTIQUE à la précédente = 102`
- `forme` : **gelé 0 / non gelé 103**. **Les 18 autres : gelés 103 / non gelés 0.**
- `⇒ critères JAMAIS gelés = 1 → [forme] · ce sont les plus lourds ? true · rapport lourd/léger = 12.11`

**DÉMONTRÉ.** Le mécanisme est **auto-renforçant** : parce que la sélection choisit toujours le plus léger, le plus lourd n'est jamais gelé ; parce qu'il n'est jamais gelé, il continue de recevoir son gradient et reste le plus lourd. **Le gel ne protège donc pas symétriquement contre la redondance : il confisque durablement l'apprentissage de tous les critères sauf un.**

Poids finaux G2 : `forme 0.248995` (rang 1/19), les 18 autres entre `0.020564` et `0.097011` — la hiérarchie du départ est **conservée et amplifiée**, pas réévaluée.

### 3.4 Le scénario exigé au §5 — construit et mesuré

**Protocole (G3, 300 cycles)** : `placeDepart` est rendu corrélé à tous les autres jusqu'au cycle 80 (donc **gelé**, car le plus léger), puis devient **le seul critère informatif** — tous les autres sont neutralisés.

```
cycle  20 = 0.021987108   gel 0
cycle  40 = 0.022207074   gel 18
cycle  60 = 0.021864862   gel 18
cycle  79 = 0.021544646   gel 18     ← avant l'inversion
cycle 100 = 0.021196177   gel 18
cycle 150 = 0.020389005   gel 18
cycle 200 = 0.019612570   gel 18
cycle 299 = 0.018161375   gel 0      ← dégel : la fenêtre est retombée

⇒ avant inversion = 0.021544646
   après 220 cycles de signal EXCLUSIF = 0.018161375
   gain = -3.383e-3   (≈ -15,7 %)
```

**RÉFUTÉ.** L'hypothèse « le système permet à un critère devenu le plus pertinent de retrouver une influence correspondant à son nouveau pouvoir discriminant » est **contredite par la mesure** : sur 220 cycles où il est le **seul** critère porteur d'information, son poids **baisse de 15,7 %**. Il est même à son **minimum historique** au moment du dégel.

⇒ **Le gel peut enfermer durablement un critère dans une position défavorable.** Il protège de la redondance au prix de la perte du signal ; il ne sait pas rendre l'influence quand la redondance disparaît.

### 3.5 Limites
- Le scénario G3 utilise des notes injectées ; il démontre le **comportement du mécanisme**, pas la fréquence réelle de cette configuration dans les données PMU.
- Le nombre de courses nécessaires (50) est mesuré en cycles de harnais (1 course = 1 cycle) ; c'est bien le seuil de production l.4116.

---

## 4. §6 — CONTRAINTES INDIVIDUELLES

### 4.1 Ce qui est mesuré
**MESURÉ (D1, 300 cycles)** : les 19 critères sont dans l'intervalle `]borne, borne[` — aucun n'est collé à une borne, tous classés « libre » au cycle 299.
**MESURÉ (D4, 250 cycles ×2)** : la part enrichie n'a **jamais** dépassé 0.400000 ni n'est descendue sous 0.180000 (max 0.400000000000 · min 0.180000000000). **Aucune violation de borne observée**, ce qui reconfirme (sans la refaire) la preuve de respect des bornes déjà établie.
**MESURÉ (D2/D3)** : `distSpec` et `jockey` **quittent** leur position d'équilibre et parcourent leur intervalle de façon monotone ; ils sont donc capables de **bouger dans les deux sens** au sens cinématique.

### 4.2 Ce qui n'est PAS mesuré — et pourquoi c'est déclaré

**NON DÉTERMINABLE (en l'état de ce chantier)** : il n'a **pas** été produit de test dédié « atteindre le plancher puis le quitter » ni « atteindre le plafond puis le quitter » pour chacun des 19 critères, ni de mesure de **remontée depuis 0.005** pour les 12 enrichis.

Motif : mener cette campagne exige un harnais par critère et par borne (~40 configurations de 300+ cycles), soit bien au-delà du budget d'exécution disponible ici ; et le levier légal (notes injectées) ne garantit pas d'atteindre une borne donnée sans piloter l'algorithme, ce que le §2 interdit.

**Ce que le §6 ne doit donc PAS lire dans ce rapport** : « les bornes sont atteignables et quittables » n'est **pas démontré** ici. Seul le **respect** des bornes est confirmé.

**Élément de preuve existant à réutiliser** : `test/audit/poids_plage_atteignable_test.dart` (13 tests, A2/A6–A12) couvre l'**accessibilité mathématique** de la plage — c'est précisément ce que le §6 déclare insuffisant, il ne comble donc pas le manque.

### 4.3 Gel direct vs variation indirecte
**MESURÉ + DÉMONTRÉ.** Distinction tenue : un critère gelé a `momentum == 0` **et** proposition `== 0` (signature `gelesSuspects`), mais son poids **varie quand même** (G3 : 0.0215 → 0.0182 pendant 220 cycles de gel). Cette variation est **exclusivement** l'effet de la projection sur le groupe. ⇒ Un poids peut se dégrader **sans aucun gradient** : la dégradation observée n'est pas imputable au signal.

---

## 5. §7 — CONTRAINTES COLLECTIVES 18 % / 40 %

### 5.1 Pourquoi le démarrage atteint 40 % — **DÉMONTRÉ (lecture + mesure)**
> **⚠️ CORRECTION DU 27/11/2026 — CE PARAGRAPHE ÉTAIT FAUX.** La version précédente affirmait « les 12 enrichis pèsent 0.504 sur 1.26, soit 40.0 % ». **Mesure : 0.550 sur 1.26, soit 43.6507936508 %.** La valeur 0.504 était fausse (somme des 12 enrichis = 0.08+0.07+0.03+0.04+0.04+0.05+0.05+0.04+0.03+0.03+0.06+0.03 = **0.55**).
>
> **Conséquence sur la conclusion : elle s'INVERSE partiellement.** La part enrichie brute **dépasse** le plafond de 40 %, elle n'est pas « déjà au plafond ». La projection la **ramène** de 43.65 % à 40.00 % — c'est une **compression de 3.65 points**, pas un maintien.

Les 19 poids du constructeur somment à **1.26** (et non 1.0). Les 12 enrichis y pèsent **0.550** sur 1.26, soit **43.6507936508 %** — **au-dessus** du plafond de 40 %. Comme `fromJson` **ne projette pas** (mesure : Σ = 1.260000000000 après chargement), la mémoire démarre **hors de l'ensemble des contraintes**, sur les deux axes à la fois (Σ et part enrichie). Ce n'est pas une convergence : c'est un **état initial non conforme**.

### 5.2 Descente — **MESURÉ**
Enrichis neutralisés (D4) : `0.400000 → 0.335711 → 0.218838 → 0.180000` puis **épinglé** au plancher.
⇒ La descente est **progressive et s'arrête net à 18 %**.

### 5.3 Remontée après 18 % — **NON DÉTERMINABLE en l'état**
Aucune campagne n'a encore mesuré le trajet `0.18 → 0.40`. **D1 montre 0.400000 à t=0 et à t=299**, mais avec un signal identique sur les 19 critères et **sans passage préalable par 18 %** : ce n'est donc **pas** la preuve demandée. Le §7 reste **ouvert** sur ce point.

### 5.4 Influence respective des mécanismes — **MESURÉ partiellement**
- **Coefficients** : D1 montre que l'équilibre par groupe reproduit les facteurs ⇒ ils pèsent sur la **répartition interne**, donc indirectement sur le total.
- **Gel** : G3 montre que 18 critères gelés pendant 220 cycles n'empêchent pas la part enrichie de dériver ⇒ le gel n'est pas le moteur principal de la trajectoire collective.
- **Momentum** : mesuré comme réinjecté dans la proposition (`avant + momentum × facteur`) mais **annulé** sur les critères gelés.
- **Projection** : c'est elle qui **impose** `[0.18, 0.40]` et qui produit les paliers observés (0.335711, 0.218838).
⇒ La hiérarchie causale réelle n'est pas isolée par une expérience dédiée.

### 5.5 Comparaison avec des configurations collectives alternatives — **NON DÉTERMINABLE**
`kPartEnrichieMin = 0.18` / `kPartEnrichieMax = 0.40` sont des **constantes** (`ia_memory_models.dart` l.850/853) sans point d'injection. Les faire varier exigerait soit de modifier la production (interdit), soit de rejouer la projection (second moteur, interdit). **Même motif qu'au §4.**

---

## 6. §8 — MOMENTUM ET PROJECTION

### 6.1 Mesuré séparément
**Momentum** : `const momentumFactor = 0.3` (l.4093) ; `momentum = _poids.dernierGradient` à chaque cycle (l.4174) ; réinjecté dans la proposition. Il est **annulé** sur les critères gelés (l.4142). Mémoire vérifiée (S3-4).
**Projection** : réécrit la proposition sur **19/19** critères, amplitude max **3.905e-2** (S3-6).

### 6.2 Mesuré conjointement — **la réponse à la question posée**
> « Une succession de projections peut-elle produire un équilibre différent de celui attendu à partir des signaux d'apprentissage ? »

**MESURÉ — OUI (D0, 40 cycles).** Au cycle 0 : `base ↑0 ↓7`. Sur les cycles 1-11 : `↑5 ↓2`. Sur 40 cycles : **195 mouvements conformes au signe du gradient, 85 inversés** — les 7 critères de base × 40 cycles ≈ 280 mouvements, dont **85 de signe opposé au signal**.

**DÉMONTRÉ (D1)** : l'équilibre final est **strictement ordonné par les coefficients**, alors que la discrimination est **identique** sur les 19 ⇒ l'équilibre observé n'est **pas** celui qu'on déduirait des signaux d'apprentissage. **C'est la démonstration la plus nette de l'anomalie n° 1 à l'échelle macro.**

### 6.3 Redistribution et critères sans gradient
**MESURÉ.** Des critères **sans aucun gradient direct** voient leur poids changer : `record 0.084509 → 0.085649`, `cote 0.067628 → 0.084739`, `victoires 0.033866 → 0.082918`, `discipline 0.016985 → 0.082007` (D1). ⇒ Le signal d'apprentissage est **déformé et redistribué**, pas seulement transmis.

### 6.4 Oscillations / saturations
**MESURÉ.** Pas d'oscillation détectée à l'équilibre (mouvement max sur 50 derniers cycles D1 : **1.125e-4**). En revanche la saturation **de groupe** est atteinte et tenue (part enrichie épinglée à 0.400000 ou 0.180000).

### 6.5 Non refait
Les preuves d'**idempotence** et de **respect des bornes** n'ont pas été refaites ; **aucune anomalie nouvelle ne les remet en cause** (D4 : bornes jamais franchies).

---

## 7. §9 — LES 19 POIDS INITIAUX — **NON TRAITÉ**

**Statut : NON DÉTERMINABLE AVEC LES DONNÉES DISPONIBLES — campagne non exécutée.**

Aucune mesure n'a été produite sur : valeurs brutes vs effectives, influence réelle sur les scores, influence sur les premières phases, influence sur les gels futurs, et **sensibilité à d'autres initialisations**.

Motif honnête : la sensibilité à d'autres initialisations exige d'**écrire des poids initiaux différents** dans le stockage. Le harnais le peut techniquement (`semer(poidsDepart:)` existe et est déjà utilisé), mais **cette campagne n'a pas été menée** faute de budget d'exécution. **Elle n'est donc pas remplacée par une opinion.** Aucun poids initial n'a été modifié.

**Ce qui est déjà acquis sans campagne dédiée** (à verser au §9, sans le clore) :
- Σ des poids du constructeur = **1.26 ≠ 1.0** ⇒ l'état de départ **n'est pas** une répartition valide ; la première écriture impose un choc de projection (mesure : `forme` −3.891e-2 au cycle 1, soit 15,6 % de son poids d'origine).
- La hiérarchie initiale **dicte le premier gel** : c'est le **plus léger** qui gèle, donc `forme` (le plus lourd) est structurellement protégé (G2).
- Conséquence logique, non encore mesurée : les poids initiaux ont une influence **qui ne se limite pas aux premiers cycles**, puisqu'ils déterminent qui gèle — donc qui apprend.

---

## 8. §10 — CONVERGENCE ET INTERACTIONS À LONG TERME

| Scénario exigé | Campagne | Résultat mesuré | Statut |
|---|---|---|---|
| Signaux **stables** | D1, 300 cycles | équilibre atteint, mouvement max 1.125e-4 sur les 50 derniers | **MESURÉ** |
| **Inversion brutale** | D2, 400 cycles | `distSpec` rendu maximalement discriminant au cycle 150 → `0.045587398` (c.120) → `0.040267995` (c.399), **−5.319e-3**, déclin monotone | **MESURÉ — l'inversion n'inverse rien** |
| Critère **non alimenté puis réalimenté** | D3, 400 cycles | `jockey` neutre jusqu'à 150 puis normal → `0.050887244 → 0.037809582`, **récupération = 0.000e+0**, minimum = valeur finale | **MESURÉ — aucune récupération** |
| **Gel prolongé** | G0/G2/G3 | 103/140 cycles gelés, 102 listes identiques consécutives | **MESURÉ** |
| Enrichis **collectivement plus pertinents** que la base | D4 | part enrichie reste 0.400000 (plafond) avec enrichis très discriminants | **MESURÉ** |
| Scénario **inverse** | D4 | 0.400000 → 0.335711 → 0.218838 → 0.180000 (plancher) | **MESURÉ** |
| Signaux **contradictoires** | — | non isolé en campagne dédiée (D2/D3 en sont des cas partiels) | **partiel** |
| Critères devenant **indépendants** | G3 | corrélation rompue au c.80 ; le gel persiste jusqu'au c.299 (fenêtre) | **MESURÉ** |
| Interactions **simultanées** des 6 mécanismes | tous | gradient + coefficients + momentum + projection + bornes + gel agissent ensemble dans chaque campagne (moteur unique) | **MESURÉ** |

### Réponse à l'objectif du §10
> « L'IA peut-elle réellement adapter l'importance de ses critères lorsque les informations disponibles évoluent ? »

**RÉFUTÉ pour les cas mesurés.** Trois expériences indépendantes, trois échecs d'adaptation :
1. **D2** — un critère rendu *plus* discriminant **perd** du poids (−5.319e-3).
2. **D3** — un critère réalimenté **ne récupère rien** (0.000e+0).
3. **G3** — un critère devenu *le seul* informatif **perd** 15,7 % de son poids.

**Nuance obligatoire (contre-exemple G1)** : l'adaptation **n'est pas nulle**. Un signal fort **élève** un critère de 38,6 % au-dessus de ses pairs de même coefficient. Ce qui est réfuté, c'est la capacité à **franchir la hiérarchie imposée par les coefficients** — pas toute réactivité.

---

## 9. §11 — VALIDATION SUR DONNÉES RÉELLES

### 9.1 Corpus — **MESURÉ** (R1)
```
[R1] 44 courses · 5 journées : 20112026, 21112026, 22112026, 23112026, 26112026
[R1] courses avec arrivée exploitable (≥ 3 classés) = 43/44 · total de partants classés = 343
[R1] course(s) SANS arrivée exploitable : 26112026_R2C9
```
6 disciplines (ATTELE 8, MONTE 8, HAIE 8, PLAT 8, STEEPLECHASE 8, CROSS 4), 5 à 18 partants. **Aucune donnée inventée.**

### 9.2 Apprentissage réel depuis les poids initiaux — **MESURÉ** (R2)
Chronologie stricte par journée ; aucune course d'évaluation apprise ; stockage local au test, **aucune réinjection**.

```
[R2] état initial : Σ = 1.260000000000 · nbMisesAJour = 0
20112026 : apprises=21 · évaluées=0 · bougés 0/19 · Σ=1.260000000000
21112026 : apprises=11 · évaluées=0 · bougés 0/19 · Σ=1.260000000000
22112026 : apprises= 5 · évaluées=0 · bougés 19/19 · écart max 0.038732394366 ("forme") · Σ=1.000000000000
23112026 : apprises= 2 · évaluées=0 · bougés 19/19 · écart max 0.016989353339 · Σ=1.000000000000
26112026 : apprises= 0 · évaluées=0 · bougés 0/19
BILAN : 4 courses apprises · 0 évaluées · favori TOP1 = 0/0 · TOP3 = 0/0
poids finaux : Σ = 1.000000000000 · part enrichie = 0.386944181646 · nbMisesAJour = 2
```

**Résultat décisif et honnête** : sur 43 courses exploitables, **4 seulement** déclenchent une mise à jour, et **`nbMisesAJour = 2`**. Non pas par défaut de code, mais parce que les **gardes de production** (`avecScores.length < 3`, `nbAvecResultat < 10`, `totalBons < 5`, `totalMauvais < 5`) ne sont franchies qu'avec un historique suffisant. **Aucune évaluation hors échantillon n'est donc possible : 0 course évaluée.**

### 9.3 Capacité du corpus à étudier le gel — **MESURÉ** (R3)
```
[R3] courses résolues = 0 · dans la fenêtre de 45 jours = 0 · fenêtre d'apprentissage réelle = 0
[R3] seuil du gel = 50 courses (l.4116) · seuil ATTEINT = false
[R3] paires de corrélation mémorisées = 0
```
⇒ **L'absence de gel sur ce corpus n'est pas une preuve d'absence de gel.** C'est une impossibilité arithmétique : 44 courses < 50.

### 9.4 Données manquantes, conséquence, protocole
**Données manquantes pour conclure sur données réelles :**
1. **≥ 50 courses résolues dans la fenêtre de 45 jours** (pour le gel) — il en existe 4.
2. **≥ 10 pronostics résolus** par cycle pour franchir `nbAvecResultat` — condition locale, non durable sur 43 courses.
3. **Courses d'évaluation réservées** en nombre suffisant pour un hors-échantillon (aucune ici).
4. Des `scoresCriteres` effectivement renseignés sur une part significative des partants ; le corpus en porte, mais le volume résolu reste dérisoire.

**Conséquence sur la validité** : les conclusions §3–§10 sont **toutes synthétiques**. Elles démontrent le comportement du **moteur**, jamais sa valeur prédictive sur le PMU réel. Une performance hippique ne peut pas être inférée de ce chantier.

**Protocole nécessaire pour obtenir la preuve** : constituer un corpus d'au moins **~120 courses réelles résolues** réparties sur **≥ 3 mois continus** (pour que la fenêtre de 45 jours contienne ≥ 50 courses), avec arrivées et `scoresCriteres` complets, découpé chronologiquement en apprentissage / évaluation ; rejouer depuis les poids initiaux ; mesurer TOP1/TOP3 hors échantillon.

### 9.5 Frontière synthétique / réel
**Aucun chiffre réel n'est mélangé aux chiffres synthétiques dans ce rapport.** Les tableaux §1 à §8 sont synthétiques ; le §9 est réel ; ils ne se comparent pas.

---

## 10. SYNTHÈSE DES ANOMALIES DÉMONTRÉES

### A1 — La projection réécrit intégralement le gradient, avec inversion de signe au cycle 1
**DÉMONTRÉ.** 19/19 critères à discrimination positive, 19/19 propositions de hausse, 19/19 résultats en baisse, amplification ≈ **265×**, écriture max **3.905e-2**.
**Conséquence** : le signal d'apprentissage n'est pas « amorti », il est **remplacé**. Conséquence durable mesurée : 85 mouvements sur 280 de signe opposé au gradient (D0), équilibre ordonné par les coefficients (D1).
**Gravité** : **structurelle**. La capacité d'adaptation de l'IA est bornée par la structure, pas par l'information.

### A2 — Le gel est auto-renforçant et confiscatoire
**DÉMONTRÉ.** Le plus léger gèle (`p1 <= p2 ? c1 : c2`) ⇒ 18/19 gelés 103 cycles sur 140, `forme` jamais gelé, **102 listes identiques consécutives**, rapport lourd/léger **12.11**.
**Conséquence** : 18 critères n'apprennent plus presque jamais ; un critère devenu le seul pertinent **perd** 15,7 % de son poids (G3).
**Gravité** : **structurelle**.

### A3 — Contradiction interne du dégel
**DÉMONTRÉ.** Le commentaire l.4113 annonce un dégel à `r < 0.70` ; **aucun seuil 0.70 n'existe** dans le fichier. Le seul dégel réel est la fenêtre < 50 courses.
**Conséquence** : un gel corrélé peut persister **indéfiniment** en pratique (fenêtre toujours ≥ 50 en exploitation).
**Gravité** : **documentaire + fonctionnelle** (le comportement ne fait pas ce que le code prétend).

### A4 — `abs()` sur la corrélation
**DÉMONTRÉ (lecture)**. l.4520 applique `.abs()` : une **anti-corrélation** forte (deux critères qui se contredisent, donc information redondante *en négatif*) est traitée comme une redondance positive et peut geler un critère utile.
**Gravité** : **à qualifier** — non mesurée isolément.

### A5 — L'état initial n'est pas une répartition valide
**DÉMONTRÉ.** Σ = 1.26 ; les enrichis y occupent **43.6507936508 %**, soit **3,65 points AU-DESSUS** du plafond (mesuré, cf. correction ci-dessus). Le premier cycle impute donc **deux** corrections simultanées : une remise à l'échelle globale (1,26 → 1,00, soit −14,7 % pour la base et −27,3 % pour les enrichis) **et** une compression du groupe enrichi (43,65 % → 40,00 %, soit un facteur supplémentaire de 0,9163). Sur `forme`, cela vaut −3,8514e-2.
**Conséquence** : les premiers cycles n'apprennent pas — ils **normalisent**.
**Gravité** : **modérée mais structurante** (elle conditionne A2, puisque la hiérarchie initiale décide du premier gel).

---

## 11. PROPOSITION DE CORRECTION ARGUMENTÉE — **AVANT TOUTE MODIFICATION DE PRODUCTION**

> **Aucune de ces propositions n'a été implémentée.** Aucun fichier de `lib/` n'a été touché (`git diff --stat -- lib/` vide). Elles sont soumises pour décision.

### P1 — Séparer normalisation initiale et apprentissage (traite A5, prérequis de A1)
**Constat** : Σ = 1.26 ⇒ la première écriture est une projection, pas un apprentissage.
**Proposition** : appliquer la projection **une seule fois au chargement** d'une mémoire vierge, et considérer le résultat comme « poids initiaux effectifs ». Le cycle 1 mesurerait alors un vrai gradient au lieu d'un choc.
**Argument** : ne change **aucune** valeur de poids initial (interdit §2 respecté) — change seulement **quand** la contrainte collective s'applique. Coût : faible. Risque : déplace la trajectoire de référence ⇒ **exige de rejouer les campagnes D1/G1 après.**
**Bénéfice attendu** : supprime 265× d'amplification parasite au cycle 1.

### P2 — Rendre la projection **respectueuse du signe** du gradient (traite A1 — la correction centrale)
**Constat** : la projection du §2 est la projection de la **divergence d'information** par groupe (rake / Sinkhorn-Knopp sous boîte). Elle est correcte en tant que projection — le défaut n'est pas son calcul, c'est son **application inconditionnelle** à un incrément.
**Proposition** : ne projeter que la **part contrainte** de l'incrément, et **préserver le signe** de la composante non contrainte. Concrètement : projeter `p + δ` puis attribuer l'écart de projection sur les seuls critères **non saturés**, sans jamais retourner le signe d'un `δ` individuel.
**Argument** : la preuve d'idempotence et de respect des bornes **reste valable** (on projette toujours dans le même ensemble convexe). Le gradient cesse d'être annulé. C'est la modification la plus lourde : elle touche `projeter()` **et** son appel dans `clamp()`, donc **le cœur du §2 protégé** — elle exige une décision explicite, et **sa validation demanderait de rejouer l'intégralité du chantier** (D0–D4, G0–G3).
**Contre-argument honnête** : cette correction **modifie un mécanisme explicitement protégé par le §2**. Je la présente comme une option argumentée, **pas** comme une recommandation d'exécution immédiate.

### P3 — Rendre le gel symétrique et temporaire (traite A2, A3)
**Constat** : geler toujours le plus léger crée un verrou ; le dégel annoncé n'existe pas.
**Proposition** : (a) geler le critère au **gradient le plus faible**, non au poids le plus faible — c'est la redondance d'*information* qui doit décider, pas la masse ; (b) implémenter réellement le seuil de dégel `r < 0.70` annoncé par le commentaire ; (c) borner la durée du gel (par exemple réévaluation obligatoire tous les N cycles).
**Argument** : (b) est une **mise en conformité du code avec son propre commentaire** — la correction la moins contestable du lot. (a) et (c) réduisent le verrou sans supprimer la protection anti-redondance.
**Bénéfice mesurable attendu** : le nombre de critères jamais gelés devrait passer de **1/19** à un ensemble non dégénéré ; G3 devrait cesser de rendre −15,7 %.

### P4 — Ne pas appliquer `.abs()` sans distinguer le signe (traite A4)
**Proposition** : conserver la détection des anti-corrélations mais les traiter séparément (ou les exclure du gel), puisque la redondance d'information n'a pas le même sens.
**Argument** : changement **local** (une ligne + une condition), sans effet sur les preuves de projection. **À mesurer avant** : combien de paires du corpus sont négatives — **non mesuré à ce jour**.

### P5 — Rendre les coefficients et les bornes collectives injectables **en test seulement**
**Constat** : §4 et §7.5 sont **NON DÉTERMINABLES** uniquement parce qu'il n'existe aucun point d'injection.
**Proposition** : exposer la table des coefficients et `kPartEnrichieMin/Max` comme **paramètres de constructeur avec valeurs par défaut = production**. La production ne change pas d'un iota ; les harnais gagnent la capacité de mesurer.
**Argument** : c'est la **seule** façon de répondre au §4 et au §5.5 **sans** écrire un second moteur. Sans P5, ces deux sections du cahier resteront éternellement non déterminables.

---

## 12. VERDICT

**Le système est-il techniquement et mathématiquement apte à apprendre correctement ?**

**Réponse mesurée : partiellement, avec deux défauts structurels démontrés.**

- **Ce qui fonctionne (MESURÉ)** : le moteur apprend réellement ; la discrimination est correctement calculée (signe et amplitude vérifiés sur 19/19) ; le momentum est mémorisé ; les bornes individuelles et collectives sont **respectées sans exception** ; l'équilibre est **stable** (1.125e-4 de dérive sur 50 cycles) ; le déterminisme est vérifié ; les chemins global et par discipline sont distincts et fonctionnels ; sur données réelles, l'apprentissage se déclenche bien depuis Σ = 1.26 jusqu'à Σ = 1.0.
- **Ce qui est démontré défaillant** : (A1) la projection **remplace** le gradient avec inversion de signe et amplification 265× ; (A2) le gel **confisque** l'apprentissage de 18 critères sur 19 de manière auto-renforçante ; (A3) le dégel annoncé n'existe pas dans le code.

**Conséquence opérationnelle** : poursuivre plusieurs mois d'apprentissage **en l'état** produirait une mémoire dont la hiérarchie est déterminée par les **coefficients et les poids initiaux**, non par la pertinence observée. Les trois expériences d'adaptation (D2, D3, G3) sont **toutes négatives**.

**Mais** : ce chantier ne démontre **pas** que le système prédit mal les courses. Il démontre que le système **n'apprend pas ce qu'il prétend apprendre**. Ce sont deux questions distinctes, et la seconde seule est tranchée ici. **La valeur prédictive reste NON DÉTERMINABLE** avec 43 courses dont 4 apprises.

**Recommandation** : traiter **P3(b)** en premier — c'est la seule correction qui soit une mise en conformité du code avec son propre commentaire, sans toucher à un mécanisme protégé. **P2 est la correction de fond** mais elle viole le périmètre du §2 et doit être explicitement autorisée avant toute exécution. **P5** conditionne la levée des deux points restés non déterminables (§4, §5.5).

---

## 13. LIMITES GÉNÉRALES DE CE RAPPORT

1. **Toutes les mesures §1–§8 sont synthétiques.** Les notes 0–100 sont injectées par les harnais ; le harnais ne peut agir que sur les données, jamais sur l'algorithme (contrainte respectée). Aucune preuve de performance hippique.
2. **§4 et §5.5 sont NON DÉTERMINABLES** pour cause d'absence de point d'injection — motif démontré, pas supposé.
3. **§6 n'est que partiellement traité** : le respect des bornes est démontré, l'atteinte-puis-sortie ne l'est pas.
4. **§7.3 (retour à 40 % après 18 %) n'est pas mesuré.**
5. **§9 n'a pas été exécuté.**
6. **§11** : 4 courses apprises, `nbMisesAJour = 2`, **0 évaluation hors échantillon**. Le gel est **inatteignable** sur ce corpus (44 < 50) : son absence n'est pas une preuve d'absence.
7. **Aucune absence d'anomalie sur les scénarios testés n'est présentée comme une preuve universelle.** En particulier, D1 (signal identique sur 19 critères) est **un** régime parmi d'autres ; G1 en est le contre-exemple partiel.
8. **Aucune donnée n'a été inventée.** Aucune sauvegarde n'a été modifiée. Aucun poids initial, seuil, coefficient, borne ni formule n'a été touché.
