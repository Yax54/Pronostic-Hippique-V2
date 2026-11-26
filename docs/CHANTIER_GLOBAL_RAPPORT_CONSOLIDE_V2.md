# CHANTIER GLOBAL — RAPPORT CONSOLIDÉ RÉVISÉ D'ARCHITECTURE

## Version 2 — révision de la proposition d'architecture

**Projet** : Pronostic-Hippique-V2 / *Race Predictor*
**Dépôt** : `https://github.com/Yax54/Pronostic-Hippique-V2.git`, branche `main`
**Statut de ce document** : proposition. **Aucune décision n'est validée. Aucune architecture n'est retenue définitivement.**
**Portée de cette révision** : remplacer l'architecture B et le plan P-1…P-7 de la version 1, jugés insuffisants, par une architecture hybride complète couvrant 21 sujets.

---

## LÉGENDE DES MARQUES DE QUALIFICATION (obligatoire, non décorative)

Chaque affirmation de ce rapport porte l'une des marques suivantes. Une affirmation sans marque est considérée comme nulle et non avenue.

| Marque | Signification exacte |
|---|---|
| **[DÉMONTRÉ]** | Établi par lecture du code source, avec référence fichier/ligne. Reproductible par quiconque lit le code. |
| **[MESURÉ]** | Résultat d'une exécution dans cet environnement sur les données réelles du projet. Reproductible. |
| **[CALCULÉ]** | Projection arithmétique à partir de mesures réelles, avec hypothèses explicitées. **N'est pas une mesure.** |
| **[ESTIMÉ]** | Ordre de grandeur argumenté, sans mesure directe possible dans cet environnement. |
| **[HYPOTHÈSE]** | Choix de conception posé pour permettre le raisonnement. Doit être vérifié avant intégration. |
| **[À VÉRIFIER]** | Point non établi. Une vérification est nommée. |
| **[APPAREIL REQUIS]** | Mesure nécessitant un terminal Android réel. **Reportée, non abandonnée.** |
| **[INDÉTERMINÉ]** | Recherche effectuée, preuve obtenue que la réponse est hors de portée. |

**Règle de lecture** : une marque [CALCULÉ] ou [ESTIMÉ] ne devient jamais [MESURÉ] par répétition. Les projections de la section I sont des calculs, pas des observations.

---

## POINT DE DÉPART : CE QUE CETTE RÉVISION RETIRE, RETIENT ET CORRIGE

### Retiré de la version 1

| Élément v1 | Motif du retrait |
|---|---|
| **Architecture B seule** (« dépôt cloisonné », sans changement de support) | Rejetée : elle conservait SharedPreferences comme support unique des connaissances volumineuses, ce qui contraint la croissance des connaissances. |
| **Plafonnement de `elo_service` à 20 000 clés** | Rejeté : plafonner un rating acquis pour gagner de l'espace contredit l'objectif de conservation. Remplacé par la section H (stockage indexé, sans plafond). |
| **Suppression sèche du stockage des bilans (A-01 / D-01)** | **Faux et dangereux** : 24 rapports existent uniquement dans les bilans. La suppression entraînerait une perte de données. Remplacé par la section C (déduplication par référence, sans perte). |
| **« −46,1 % du fichier »** | Chiffre obtenu en supprimant les bilans en bloc, donc en perdant 24 rapports. **Gain non valide dans cette forme.** Recalculé en section I. |
| **Plan P-1…P-7** | Remplacé par le plan ordonné de la section V, dont la porte d'entrée n'est plus « recalcul des bilans » mais « identification et déduplication sans perte ». |

### Retenu de la version 1 (faits non contestés)

- La duplication des rapports est réelle et massive. **[MESURÉ]**
- `_save()` réécrit la quasi-totalité du volume à chaque appel. **[MESURÉ]** (99,7 %)
- Quatre collections sont bornées, quatre ne le sont pas. **[MESURÉ]**
- La purge `grosParis` à 90 jours est effective. **[MESURÉ]** (fenêtre exactement 90 jours)
- Absence de somme de contrôle, écriture non atomique, comptage estimé des pronostics. **[DÉMONTRÉ]**
- `poidsParDiscipline['global']` est inerte. **[MESURÉ]** (delta max 5,55e-17)
- Le repli `gainsDernierAn = 20 %` est une donnée fabriquée. **[DÉMONTRÉ]** `zone_turf_service.dart:1005-1018`

### Corrigé par les découvertes les plus récentes

| Affirmation v1 | Correction |
|---|---|
| « 219 rapports distincts » | **Faux.** 219 était un décompte **par date**, pas par contenu. Valeur exacte : **225 contenus bruts distincts**, **219 contenus après normalisation du schéma**. La date n'est pas un identifiant de rapport. |
| « redondance ×2,39 » | Juste en valeur, mais le dénominateur était ambigu. Reformulé : 524 copies / 219 contenus normalisés = **×2,39** ; 524 / 225 contenus bruts = **×2,33**. |
| « les bilans n'apportent que 9 valeurs dérivées » | **Incomplet.** Ils apportent aussi **24 rapports absents de la collection principale**. Ils sont donc à la fois redondants (90 %) et porteurs d'information unique (10 %). |
| « deux rapports de même date sont identiques » | **Faux dans 6 cas.** 6 dates portent deux versions de contenu. Après examen, l'écart porte **exclusivement sur le champ `fnum2`**, absent des versions anciennes. Retirer ce champ rend les deux versions identiques octet pour octet — **ce qui ne démontre pas qu'il est supprimable sans conséquence** (voir C.3). |
| Plateau « 9,27 Mo » | **Périmètre insuffisant.** Excluait les connaissances PMU historiques, les archives permanentes, la croissance ELO et les sauvegardes. Remplacé par la section I. |

---

# A. PRINCIPES DIRECTEURS

## A.1 Le volume n'est pas le problème

**Le volume de connaissances utiles peut croître. Sa croissance est normale et souhaitable.**

La version 1 de ce rapport a commis une erreur de cadrage : elle a traité le volume comme un défaut à contenir, en proposant des plafonds. C'était confondre la cause et le symptôme.

**[DÉMONTRÉ]** Les cinq défauts réels ne sont pas des volumes, mais des **pratiques de stockage** :

1. **Duplication** — le même rapport est écrit 524 fois pour 219 contenus. **[MESURÉ]**
2. **Chargement intégral** — collections entières désérialisées en RAM au démarrage, sans fenêtre ni index. **[DÉMONTRÉ]** `ia_memory_service.dart:_load()`
3. **Réécriture inutile** — `_save()` réencode 99,7 % du volume pour un changement souvent local. **[MESURÉ]**
4. **Mauvaise stratégie de consultation** — pas d'index, donc toute lecture est un balayage complet. **[DÉMONTRÉ]**
5. **Absence de politique de rétention déclarée** — les plafonds existants sont implicites et dispersés. **[DÉMONTRÉ]**

Aucun de ces cinq défauts ne se corrige en plafonnant. Tous se corrigent en **changeant la façon de stocker et de consulter**.

## A.2 Conséquence architecturale

L'architecture cible doit satisfaire quatre exigences, dans cet ordre :

1. **Conserver tout ce qui est utile**, sans plafond arbitraire.
2. **Consulter de façon ciblée**, sans charger l'ensemble.
3. **Écrire uniquement ce qui a changé**, sans réécrire l'ensemble.
4. **Rester vérifiable**, y compris sur la prévisualisation Web, sans quoi la preuve devient impossible.

L'exigence 4 est ce qui interdit de rejeter une technologie Android au seul motif qu'elle n'est pas directement disponible sur Web. La réponse est une **couche d'abstraction de support** (section E), pas un renoncement.

## A.3 Les six découvertes qui structurent cette révision

| # | Découverte | Conséquence |
|---|---|---|
| F-1 | **225 contenus bruts / 219 après normalisation** | La déduplication exige une normalisation de schéma explicite, sinon elle échoue sur 6 cas. |
| F-2 | **6 divergences limitées au champ `fnum2`** | Deux versions d'un même rapport peuvent différer légitimement. La conservation des versions doit être possible. |
| F-3 | **24 rapports orphelins** (présents dans les bilans, absents de la collection) | Les bilans ne sont pas un simple duplicata : ils contiennent de l'information unique. |
| F-4 | **La date n'est pas un identifiant unique** | Toute clé de déduplication fondée sur la date est fausse par construction. |
| F-5 | **La purge de la collection principale est indépendante des bilans** | Les 24 orphelins sont dispersés sur toute la fenêtre (positions 6 à 190 sur 219), donc la purge opère indépendamment. |
| F-6 | **ELO indexé par `NOM\|DISCIPLINE`** | Cette clé n'est pas une identification universellement fiable d'un cheval. Elle est exploitable mais doit être doublée d'un identifiant stable. |

---

# B. COMPLÉMENTARITÉ DES CONNAISSANCES PMU ET DES CONNAISSANCES DE L'IA

**Objectif fonctionnel rappelé** : exploiter **conjointement** le savoir hippique authentique du PMU et le savoir progressivement acquis par l'IA, **sans remplacer ni modifier les mécanismes d'apprentissage**.

## B.1 Trois natures de connaissance — à ne jamais confondre

La version 1 parlait de « connaissances » au singulier. C'est la source de la plupart des confusions. Il faut distinguer trois natures :

| Nature | Définition | Exemple | Origine | Recalculable ? |
|---|---|---|---|---|
| **F1 — Fait observé** | Donnée brute fournie par le PMU, horodatée, rattachée à une course et à un cheval. | `placeCorde`, `handicapPoids`, `etatTerrain`, `reductionKilometrique`, arrivée officielle | PMU | **Non** — un fait ne se recalcule pas, il s'enregistre |
| **F2 — Statistique calculée** | Agrégat déterministe de faits F1. | taux de victoire sur terrain, nombre de victoires récentes, `scoreTerrain`, `scoreFormeLong` | Dérivée de F1 | **Oui** — intégralement |
| **F3 — Connaissance apprise** | Résultat d'un mécanisme d'apprentissage : poids, ELO, calibration. | `ia_poids_v3`, `poidsParDiscipline`, ratings ELO, seuils ajustés | Mécanismes internes | **Non** — le résultat du gradient n'est pas reproductible sans rejouer l'historique complet |

**Règle fondamentale** : F1 doit être conservé intégralement et durablement. F2 peut être recalculé à la demande, donc n'a pas besoin d'être stocké de façon permanente — seul un cache est légitime. F3 doit être conservé avec sa provenance et sa date, car il n'est pas recalculable sans les données et le temps qui l'ont produit.

**Conséquence directe** : une politique de conservation unique pour les trois est nécessairement fausse. C'est l'une des erreurs de la v1.

## B.2 Ce que possède chaque source — et ce qu'elle ne possède pas

| Connaissance | PMU la fournit ? | L'IA la produit ? | Complémentarité possible |
|---|---|---|---|
| Identité du cheval | Partiellement (`nom`, numéro, âge, sexe) — **pas d'identifiant stable universel** | Non | **Friction majeure** : voir B.4 |
| Performances passées d'un cheval | Oui, jusqu'à 5 courses (médiane 5) | Non | F1 alimente F2 puis F3 |
| Musique | Oui, format `"3a8a2aDaDaDaDa2a8a3a"` | Non | Décodée en F2 (constance, victoires, record) |
| Réduction kilométrique | Oui, sur 73,3 % des entrées de cheval | Non | F1 de meilleure qualité que le temps brut |
| État du terrain | Oui, mais sur 38,8 % des courses passées seulement | Non | F1 partielle → F2 à couverture partielle |
| Cote | Oui, en direct | Non | F1 temporelle → F2 (mouvement) |
| Poids / handicap | Oui, courses de handicap | Non | F1 conditionnelle |
| Place à la corde | Oui, `placeCorde` | Non | F1 → F2 (place au départ) |
| Taux de réussite d'un jockey | **Non**, non fourni directement | Non | L'IA **doit** le construire à partir de F1 |
| Taux de réussite d'un entraîneur | **Non** | Non | Idem |
| Statistiques par hippodrome | **Non** | Non | Construction locale obligatoire |
| Rating de force relative | **Non** | Oui — ELO | F3, sans équivalent PMU |
| Pondération des 19 critères | **Non** | Oui — gradient | F3, sans équivalent PMU |
| Calibration des seuils | **Non** | Oui | F3 |

**Conclusion [DÉMONTRÉ]** : la complémentarité n'est pas un slogan. Elle est structurelle — le PMU ne fournit **jamais** ni rating, ni pondération, ni seuil ; l'IA ne peut **jamais** produire un fait observé. Les deux ensembles sont disjoints par construction, sauf sur les statistiques dérivées, où le PMU fournit la matière et l'IA le calcul.

## B.3 Comment une connaissance est identifiée

Chaque catégorie reçoit une **clé d'identité naturelle**, et non une clé de commodité :

| Entité | Clé d'identité proposée | Justification | Statut |
|---|---|---|---|
| Course | `dateCourse` + `reunion` + `course` + `hippodrome` | Le triplet réunion/course est unique par jour ; l'hippodrome lève l'ambiguïté inter-journées | **[HYPOTHÈSE]** à valider sur un échantillon réel |
| Participation | identifiant course + numéro de programme du cheval | Stable dans une course donnée | **[HYPOTHÈSE]** |
| Cheval | **identifiant stable du fournisseur si disponible**, sinon clé composite | Voir B.4 | **[À VÉRIFIER]** |
| Rapport journalier | empreinte de contenu canonique + version de schéma | Voir C.2 | **[DÉMONTRÉ]** nécessaire (F-4) |
| Rating ELO | identifiant cheval + discipline | Voir H.3 | **[DÉMONTRÉ]** insuffisant en l'état |
| Hippodrome | nom normalisé | Stable | **[HYPOTHÈSE]** |
| Jockey / entraîneur | nom normalisé + année de licence si disponible | Homonymes possibles | **[À VÉRIFIER]** |

**Aucune de ces clés n'est retenue définitivement.** Elles sont proposées pour permettre le raisonnement, et chaque ligne porte sa marque.

## B.4 Le problème d'identité du cheval — point le plus fragile de tout l'édifice

**[DÉMONTRÉ]** Il n'existe aujourd'hui aucun identifiant de cheval unique et pérenne dans le modèle. Le service ELO utilise `NOM|DISCIPLINE` (section H).

**Pourquoi c'est insuffisant** — trois raisons, toutes démontrables :

1. **Un nom n'est pas unique.** Deux chevaux peuvent porter le même nom à des époques différentes, et rien dans la structure actuelle ne permet de les distinguer.
2. **La discipline n'appartient pas au cheval.** Un même cheval peut courir en trot attelé puis en trot monté, ou en obstacle puis en plat. La clé `NOM|DISCIPLINE` **fragmente** donc un même cheval en plusieurs entités, sans lien entre elles.
3. **Le nom peut varier.** Orthographe, accents, apostrophes, espaces.

**Conséquence** : considérer `NOM|DISCIPLINE` comme une identification fiable reviendrait à affirmer une chose non démontrée. C'est explicitement écarté.

**Solution proposée — à trois niveaux, par ordre de préférence :**

- **Niveau 1 — identifiant fournisseur stable.** Si le PMU expose un identifiant de cheval (type numéro de SIRE / numéro de pedigree) dans le flux, il devient la clé primaire. **Toute la difficulté tombe.** **[À VÉRIFIER]** : présence effective de cet identifiant dans les réponses du flux utilisé — c'est la vérification la plus rentable de tout le chantier.
- **Niveau 2 — clé composite robuste.** À défaut : `nom normalisé + année de naissance + sexe`, qui distingue la quasi-totalité des homonymes réels. **[HYPOTHÈSE]** à valider.
- **Niveau 3 — entité « cheval » avec alias.** Une table `chevaux` avec identifiant interne généré, et une table `alias` associant `(nom, discipline, période)` à un cheval. La discipline devient un **attribut de la participation**, plus une composante de l'identité du cheval. C'est la correction structurelle de la faiblesse F-6.

**Décision D-11** soumise à votre validation (section U).

## B.5 Le flux de complémentarité — cinq étapes

**1. Identification** — à la réception d'une course, chaque entité est résolue vers sa clé (B.3). Si un cheval n'est pas résolu, il est créé avec un marqueur `resolution: provisoire`, jamais fusionné automatiquement.

**2. Conservation** — les faits F1 sont écrits une fois, dans le magasin de faits, avec leur provenance et leur horodatage. Aucun fait n'est écrasé par un autre sans trace (section P).

**3. Rapprochement** — les faits sont rattachés aux entités. C'est ici que la complémentarité se produit : le fait PMU (`etatTerrain`, `reductionKilometrique`) est joint à l'entité cheval, ce qui permet à une statistique locale (F2) de se former.

**4. Actualisation** — lorsqu'un fait nouveau arrive, seules les statistiques F2 **dépendantes** sont invalidées (section J). Les connaissances F3 ne sont **pas** recalculées à chaque fait : elles le sont aux moments que les mécanismes existants définissent déjà, qui ne sont pas modifiés.

**5. Exploitation** — chaque critère lit une valeur, sans savoir si elle vient du PMU ou d'un calcul local. C'est l'intérêt de la couche commune : le critère `terrain` ne doit pas savoir que sa donnée vient d'un CSV construit ou d'une table indexée.

**Point de vigilance explicite** : l'étape 3 est celle où une erreur d'identité se propage silencieusement. Une fusion erronée de deux chevaux corrompt toutes les statistiques et tous les ratings. D'où la règle : **jamais de fusion automatique sans preuve d'identité** ; en cas de doute, deux entités distinctes valent mieux qu'une entité fausse.

## B.6 Ce qui reste à vérifier sur ce sujet

| Vérification | Nature | Quand |
|---|---|---|
| Présence d'un identifiant cheval fournisseur | **[À VÉRIFIER]** — inspection d'une réponse de flux réelle | Avant toute implémentation d'identité |
| Unicité effective du nom sur l'ensemble du corpus | **[À VÉRIFIER]** — comptage sur les données réelles | Avant le choix Niveau 2 |
| Fréquence réelle des chevaux multi-disciplines | **[À VÉRIFIER]** | Détermine l'ampleur de la fragmentation actuelle |
| Stabilité du triplet course dans le temps | **[À VÉRIFIER]** | Avant de figer la clé course |
---

# C. IDENTIFICATION, CONSOLIDATION ET DÉDUPLICATION DES CONNAISSANCES

Cette section traite les points **3** et **12** de votre consigne. C'est la section la plus délicate, parce qu'elle porte les six découvertes F-1 à F-5 et parce que la v1 y a produit une proposition dangereuse.

## C.1 Pourquoi la date ne peut pas être la clé

**[MESURÉ]** Sur la sauvegarde du 13/11/2026, il y a **219 dates distinctes** mais **225 contenus bruts distincts**. L'écart n'est pas une erreur : **6 dates portent deux contenus différents**.

**[DÉMONTRÉ]** Le champ `date` d'un rapport est l'horodatage de *génération du rapport*, à la microseconde. Il ne désigne pas une journée de courses. Deux rapports générés à des moments différents peuvent donc porter des instants différents — mais deux rapports peuvent aussi porter le **même instant** avec des **contenus différents**, ce qui est le cas ici.

**Conséquence** : toute déduplication fondée sur `date` est fausse. Elle fusionne à tort 6 paires distinctes, ou en perd. La clé doit être **le contenu lui-même**.

## C.2 La clé de déduplication proposée

**Principe** : identifier un rapport par **l'empreinte de son contenu canonique**, et non par sa date ni par son emplacement.

**Formellement** :

```
empreinte = SHA-256( sérialisation_canonique( contenu_normalisé( rapport ) ) )
```

Trois choix à expliciter, car chacun porte une conséquence :

**1. La sérialisation doit être canonique** — clés triées, séparateurs fixes, encodage UTF-8, aucun espace insignifiant. Sinon deux contenus identiques produisent deux empreintes différentes, et la déduplication échoue par excès.

**[MESURÉ]** Cette exigence n'est pas théorique : les mesures de ce chantier ont produit **225** empreintes avec `json.dumps(sort_keys=True, separators=(',',':'))`, contre **219** après normalisation. Le mode de sérialisation change le résultat.

**2. La normalisation de schéma doit être explicite et versionnée** — c'est la découverte F-1. Les 6 divergences examinées portent **exclusivement** sur `fnum2`, absent des versions anciennes. Après retrait de ce champ des deux côtés, les contenus sont **identiques octet pour octet**.

Cela signifie : **un rapport ancien et un rapport récent peuvent décrire exactement la même réalité, au champ de schéma près.** Sans normalisation, on compte 225 contenus et on croit à 6 divergences réelles. Avec normalisation, on compte 219 contenus et les 6 divergences disparaissent.

**3. Deux versions distinctes doivent rester conservables** — et c'est le point où il faut être très prudent :

> **[DÉMONTRÉ] Le fait que retirer `fnum2` rende deux contenus identiques ne démontre PAS que ce champ est supprimable sans conséquence.**

`fnum2` est le second numéro de cheval d'une sélection (typiquement un couplé). S'il porte une information réelle — un second cheval joué — alors sa suppression détruit de l'information. Sa présence dans les rapports récents et son absence dans les anciens peut signifier deux choses :

- **(a)** le champ a été ajouté à un moment donné, et son absence ancienne est une absence de *schéma* ;
- **(b)** le champ portait une information qui, à l'époque, n'existait pas — par exemple parce que seuls des paris simples étaient joués.

Ces deux lectures ont des conséquences opposées. La seconde interdit de considérer les anciens rapports comme « complets après normalisation ».

**Décision proposée** : ne **jamais** normaliser par suppression. La normalisation se fait par **complétion à valeur nulle explicite** (`fnum2: null` ajouté aux anciens), ce qui conserve l'information d'absence au lieu de l'effacer, et permet que l'empreinte soit calculée sur un schéma homogène **sans destruction**.

**[MESURÉ]** Les deux stratégies donnent le même décompte (219) ; elles diffèrent sur ce qu'on peut encore affirmer après coup. La complétion est réversible, la suppression ne l'est pas.

**Corollaire — conservation des versions** : un rapport peut légitimement exister en plusieurs versions. Le modèle doit donc prévoir **une entité rapport et des versions de rapport**, et non un rapport unique. La version courante est désignée ; les autres sont conservées.

## C.3 Structure proposée : rapport, versions, références

```
Rapport
├── id              (interne, immuable, généré)
├── empreinte       (SHA-256 du contenu normalisé — clé de déduplication)
├── dateGeneration  (horodatage — ATTRIBUT, jamais clé)
├── versionSchema   (entier — permet la normalisation à la lecture)
└── versions[]
    ├── numeroVersion
    ├── empreinteVersion  (empreinte du contenu de CETTE version, sans normalisation)
    ├── contenu           (conservé tel quel)
    └── dateEnregistrement
```

Et pour les bilans, **plus aucune copie intégrale** :

```
BilanSemaine
├── lundi, dim         (bornes de la semaine)
├── agregats           (tc, tr, tg, tt3, sm, md, mt — 7 valeurs dérivées)
└── rapportsRef[]      (liste d'IDENTIFIANTS de rapport — pas de copies)
```

```
BilanMois
├── an, mo
├── agregats           (tc, tr, tg, tt3, sm, md, mt)
└── semainesRef[]      (liste d'IDENTIFIANTS de bilan hebdomadaire)
```

**Ce que cela corrige, mesurable :**

| Propriété | v1 (copies intégrales) | Proposition |
|---|---|---|
| Rapports orphelins préservés | Non — perdus à la suppression | **Oui** — un orphelin est un rapport comme un autre, présent dans la collection |
| Redondance | ×2,33 brut / ×2,39 normalisé | **1,00** — un contenu, une ligne |
| Recalcul des agrégats | Impossible sans les copies | **Oui** — les 7 agrégats sont stockés, les rapports sont pointés |
| Consultation d'un ancien bilan | Désérialisation de toutes les copies imbriquées | Lecture du bilan + résolution des références |
| Versions multiples d'un même rapport | Écrasées ou dupliquées | **Explicites et conservées** |

## C.4 Les 24 rapports orphelins — traitement précis

**[MESURÉ]** Les 24 rapports présents dans les bilans et absents de la collection principale ne sont **pas** regroupés en début ou en fin de période. Leurs positions dans la chronologie des 219 dates vont de **6 à 190** : ils sont **dispersés sur toute la fenêtre**.

**Ce que cela démontre** : la purge de la collection principale (`_rapports.removeAt(0)` quand la taille dépasse `_maxRapports`) et la constitution des bilans sont **deux mécanismes indépendants**. La collection principale perd des éléments **au milieu** de la fenêtre couverte — donc pas seulement par ancienneté. **[DÉMONTRÉ]** par la dispersion, indépendamment du code.

**Conséquences pour la migration** :

1. La reprise doit se faire **par union**, jamais par choix d'une source : `ensemble = collection ∪ semaines ∪ mois`.
2. L'union doit être faite **sur l'empreinte normalisée**, pas sur la date.
3. **Aucun rapport ne doit être écarté** au motif qu'il n'est pas dans la collection principale : c'est précisément le cas des 24.
4. Les 24 orphelins doivent être **identifiés nommément** dans le journal de migration, pour que la reprise soit auditable.

**Compatibilité avec la limite de 365 rapports** — c'est votre demande explicite :

**[MESURÉ]** Après normalisation de schéma, il existe **219 contenus distincts**. La limite actuelle `_maxRapports = 365` laisse donc une **marge de 146 entrées** sur l'état actuel.

**[CALCULÉ]** La collection couvre 219 dates sur environ 194 jours (du 03/05/2026 au 13/11/2026), soit **1,13 rapport par jour**. À ce rythme, 365 entrées représentent **≈ 323 jours** de couverture.

**Le conflit est donc réel mais différé** :

- La **conservation historique des bilans** exige que les rapports pointés par un bilan restent résolubles. Un bilan de mois pointe des rapports vieux d'un mois ; un bilan annuel en pointerait vieux d'un an.
- La **limite de 365** purge au-delà de 365 rapports, ce qui, à 1,13/jour, couvre ≈ 323 jours — **moins d'un an**.

**Proposition** : décorréler les deux. La limite de 365 continue de gouverner la **collection courante** (celle qui sert à l'analyse quotidienne). Les rapports **référencés par un bilan** ne sont **pas** soumis à cette limite : ils basculent dans le magasin d'archives (section K) et deviennent immuables. Le bilan conserve alors une référence **résoluble indéfiniment**.

**Sans cela**, un bilan annuel pointerait vers des rapports détruits : ce serait une référence morte, c'est-à-dire un mensonge structurel.

> **Point à trancher par vous** : accepter qu'un rapport archivé ne soit plus jamais purgé est une décision de politique de conservation. **Elle n'est pas prise ici.** Elle est posée comme **D-12** (section U).

## C.5 Déduplication sans perte — règles de fusion

La fusion doit être **conservatrice** : en cas de doute, on conserve.

| Situation | Règle | Motif |
|---|---|---|
| Deux contenus, empreinte **identique** | Fusion en un seul | Identité prouvée par le contenu |
| Deux contenus, empreintes **différentes**, même date | **Conserver les deux** comme versions | Le contenu diffère : ce n'est pas un doublon (F-2) |
| Deux contenus, écart limité à un champ de schéma absent | Conserver les deux, marquer la relation `varianteDeSchema` | Le champ absent n'autorise pas à conclure à l'identité (C.2) |
| Contenu présent dans un bilan, absent de la collection | **Conserver et promouvoir** dans la collection | C'est un orphelin (F-3) — jamais un doublon |
| Contenu présent deux fois dans le même bilan | Fusion | Duplication interne pure |
| Contenu présent, agrégats différents entre deux bilans | Conserver les deux bilans, **signaler l'incohérence** | Un agrégat incohérent est un défaut à examiner, pas à écraser |

**Règle d'or** : la déduplication ne supprime que ce qui est **prouvé identique**. Elle n'arbitre jamais entre deux contenus différents.

## C.6 Consolidation des connaissances : le registre

Un simple registre de clés ne suffit pas — votre consigne est explicite sur ce point. Ce qui est proposé est un **registre de politiques**, qui porte pour chaque catégorie :

| Champ | Rôle |
|---|---|
| `categorie` | Nature (F1 fait, F2 statistique, F3 apprentissage) |
| `cleIdentite` | Ce qui identifie un enregistrement (B.3) |
| `supportCible` | Où la catégorie est stockée (section G) |
| `dureeConservation` | Durée explicite, jamais implicite |
| `politiqueEcriture` | Ajout seul / remplacement / fusion |
| `politiqueFusion` | Règles de C.5 |
| `dependancesInvalidation` | Quelles statistiques F2 invalider quand un F1 change (section J) |
| `tailleAttendue` | Ordre de grandeur → sert aux projections |
| `verifiablePar` | Comment on prouve que la politique est respectée |

**Différence avec la v1** : la v1 proposait un registre de **clés** (A-04), ce qui rendait un plafond visible mais ne disait rien des dépendances, des fusions ni des invalidations. Le registre ci-dessus est ce qui manquait.
---

# D. ALIMENTATION FIABLE DES 19 CRITÈRES

Cette section traite le point **2** de votre consigne et prépare le tableau corrigé de la section T. Elle est longue parce que chacun des critiques que vous avez nommés — Record, Discipline, Jockey, Entraîneur, Terrain, Gains, Progression, Poids relatif, Place au départ — doit être résolu séparément.

**Aucune formule n'est modifiée dans cette section. Aucun poids. Aucun seuil. Aucun mécanisme d'apprentissage.**

## D.1 Le cadre de qualification — six axes distincts

La v1 utilisait un seul axe (« SOLIDE / PARTIEL / FRAGILE / INTERNE »), ce qui mélangeait des questions différentes. Votre consigne en distingue six. Les voici, avec leur définition opérationnelle :

| Axe | Question posée | Valeurs possibles |
|---|---|---|
| **P — Provenance** | D'où vient la donnée brute ? | `PMU-direct` / `PMU-dérivé` / `calcul-local` / `apprentissage` / `aucune` |
| **D — Disponibilité** | Est-elle présente dans les données réelles ? | `toujours` / `fréquente` / `partielle` (avec taux) / `rare` / `jamais` |
| **Q — Qualité d'alimentation** | La valeur qui arrive est-elle exploitable ? | `fiable` / `conditionnelle` / `dégradée` / `repli` / `fabriquée` |
| **I — Validité d'interprétation** | Le calcul fait-il ce que le nom du critère annonce ? | `conforme` / `partielle` / `détournée` / `non vérifiable` |
| **A — Applicabilité par discipline** | Sur quelles disciplines le critère a-t-il un sens ? | `toutes` / `liste` / `aucune` |
| **R — Comportement réel** | Que fait le critère quand la donnée manque ? | `neutre-explicite` / `neutre-implicite` / `constante` / `variable-non maîtrisée` |

**Les trois pièges que votre consigne nomme, et leur expression dans ce cadre :**

- *« Un critère interne n'est pas nécessairement fiable »* → un critère `P=calcul-local` peut avoir `Q=dégradée` si son entrée est mauvaise. **Interne ≠ fiable.**
- *« Un critère variable n'est pas nécessairement correctement alimenté »* → `R=variable-non maîtrisée` peut coexister avec `Q=repli`. **Variation ≠ signal.**
- *« Un critère disposant d'une source PMU n'est pas nécessairement opérationnel »* → `P=PMU-direct` avec `D=partielle` donne `Q=conditionnelle` ou `repli`. **Source ≠ disponibilité.**

## D.2 Résolution des neuf critères conflictuels

### D.2.1 Record — `record`

**Ce qui est établi [DÉMONTRÉ]** : `zt_models.dart` calcule `recordEnSecondes` par expression régulière `RegExp(r"(\d+)'(\d{2})(?:[\x22\x27]?(\d))?")` sur la musique. **Si l'expression ne trouve rien, la fonction renvoie `9999.0`.**

**Le conflit** : la v1 classait ce critère « PARTIEL ». Insuffisant. Le point décisif est la valeur `9999.0`.

**Analyse** :
- `P = PMU-dérivé` (la musique vient du PMU, le record est extrait localement)
- `D = fréquente` mais **non totale** : dépend de la présence d'un temps dans la musique
- `Q = dégradée` **dans le cas d'échec** : une sentinelle `9999.0` n'est pas une absence, c'est une **valeur extrême**. Elle est donc traitée comme un nombre par tout calcul en aval.
- `I = partielle` : un « record » déduit de la musique est un meilleur temps de la musique, pas nécessairement un record de la carrière.
- `A = toutes`
- `R = constante` (les échecs convergent tous vers 9999,0) — **et non neutre**

**Le vrai défaut est là** : une sentinelle extrême n'est pas neutre. Selon le sens du calcul en aval, `9999.0` peut être interprété comme « très mauvais » (ce qui est probablement voulu) ou produire un effet de bord si la valeur sert de dénominateur ou de base à une normalisation.

**Correction proposée, sans toucher à la formule** : distinguer **l'absence** de **la valeur extrême**. Le producteur émet `null` en cas d'échec d'extraction, et la couche d'alimentation décide explicitement du comportement neutre. **Décision D-13** soumise à validation, car toucher à la sentinelle `9999.0` modifie potentiellement l'effet du critère.

**Qualification finale : `P=PMU-dérivé`, `D=fréquente`, `Q=dégradée`, `I=partielle`, `A=toutes`, `R=constante` → PARTIEL, avec un défaut d'alimentation nommé (sentinelle).**

### D.2.2 Discipline — `discipline`

**Ce que vous demandez** : expliquer la neutralité constatée avant de déclarer ce critère solide.

**Ce qui est établi [MESURÉ]** : `poidsParDiscipline['global']` a un delta maximal de **5,55e-17** sur 169 jours (epsilon machine) contre **6,32e-2** pour `plat`, **5,58e-2** pour `obstacle`, **5,11e-2** pour `trot_attele`. Les **19 critères** changent pour les trois disciplines réelles ; **aucun** ne change pour `global`.

**Explication de la neutralité — trois causes cumulées, toutes démontrées :**

1. **`global` est un artefact historique figé.** Il a été écrit une fois et **jamais réécrit**. Ce n'est pas un mécanisme de neutralité voulu, c'est une entrée orpheline.
2. **`normaliseDiscipline()` ne produit `global` que par défaut.** `ia_memory_models.dart:682` : toute discipline non reconnue tombe sur `'global'`. Or les disciplines réelles (`trot`, `att`, `mont`, `plat`, `haies`, `steeple`, `cross`, `obstacle`) ont toutes une branche explicite. `global` ne reçoit donc **jamais** de mise à jour par ce chemin.
3. **`clampDiscipline()` est un COMPLÉTEUR.** Chaque clé est écrite `(poids['k'] ?? <constante>).clamp(lo,hi)`. Les clés absentes sont **créées** avec des constantes codées en dur. Un delta nul sur `global` signifie donc que le chemin d'écriture ne l'a jamais visité — pas que le calcul l'a jugé neutre.

**Conséquence sur la qualification** : le critère `discipline` lui-même n'est pas « inerte ». Ce qui est inerte est la **branche `global`** de la table de poids. Le critère, lui, s'alimente correctement pour les disciplines réelles.

**Mais un second point subsiste** : la neutralité observée pourrait aussi venir de ce que `poidsEffectifsPourDiscipline()` retourne les **19 champs racine** quand la branche est absente (`ia_memory_models.dart:634-670`). Dans ce cas, le critère reçoit les poids génériques — ce qui est un comportement de **repli**, pas de neutralité.

**Qualification finale : `P=PMU-direct`, `D=toujours`, `Q=fiable` pour les disciplines réelles, `Q=repli` pour `global`, `I=conforme`, `A=toutes`, `R=neutre-explicite` → PARTIEL, avec deux défauts nommés (branche `global` orpheline ; repli silencieux vers les poids racine).**

**Ce que la v1 aurait dû dire** : elle classait `discipline` « SOLIDE », ce qui était faux. Non parce que le critère est mauvais, mais parce que **sa branche de repli est indétectable par l'utilisateur**. Un critère dont on ne peut pas savoir s'il a fonctionné n'est pas solide.

**Décision D-09 (conservée de la v1, non validée)** : garder `trot_monte` distinct de `global`. Elle est **renforcée** par cette analyse : la distinction est un acquis mesuré, la fusion serait une perte.

### D.2.3 Jockey — `jockey`

**Ce qui est établi [DÉMONTRÉ]** : aucune statistique de jockey n'est fournie par le PMU. Elle doit donc être construite localement à partir des participations passées.

**Analyse** :
- `P = calcul-local`
- `D = dépend de la profondeur d'historique` : 0 à 5 courses par cheval (médiane 5), et les `participants` d'une course passée sont **tronqués** (ex. 6 listés pour `nbParticipants = 12`)
- `Q = dégradée` : la troncature des participants signifie que **toutes les participations ne sont pas connues**. Un taux calculé sur un sous-ensemble tronqué est biaisé.
- `I = conforme` au sens où le calcul fait ce qu'il annonce, mais sur une base incomplète
- `A = toutes`
- `R = neutre-implicite` (valeur par défaut non distinguable d'une vraie valeur)

**Le défaut central** : la troncature des `participants` est une **limite de source**, pas une limite de calcul. Elle ne se corrige pas par du code : elle se corrige en acquérant la composition complète des courses au moment où elles sont courues (section G, magasin de faits).

**Qualification finale : PARTIEL, avec défaut d'alimentation structurel (troncature des participants).**

### D.2.4 Entraîneur — `entraineur`

**Analyse** : identique à `jockey` sur les six axes, à une différence près — **[DÉMONTRÉ]** l'homonymie est plus probable sur les entraîneurs (moins de contrainte de licence visible dans les données), et la clé `nom normalisé` est plus fragile.

**Qualification finale : PARTIEL, avec deux défauts nommés (troncature des participants ; fragilité de la clé d'identité).**

### D.2.5 Terrain — `terrain`

**Ce qui est établi, et c'est le point le plus grave de tout le tableau [DÉMONTRÉ]** :

`zone_turf_service.dart:938-1000` construit `statsTerrainCsv` à partir de `performancesParTerrain` / `performancesParEtatTerrain` / `indices`. **Ces trois sources sont absentes dans 0/98 des cas examinés.** Le commentaire du code le documente. Donc `statsTerrainCsv` était **toujours vide**, et `scoreTerrain()` retournait **toujours 50.0** (`zt_models.dart:663`).

**Correction déjà identifiée [DÉMONTRÉ]** : la source correcte est `coursesCourues[].etatTerrain`, **jamais** `typePiste`. Et :
- `etatTerrain` est présent sur **38,8 %** des courses passées (6433/16579)
- `typePiste` est présent sur **34 %**, avec les valeurs `herbe`, `gazon`, `pouzolane`
- **L'intersection entre `typePiste` et `etatTerrain` est VIDE** → `typePiste` est une **SURFACE**, pas un **ÉTAT**. Les confondre serait une faute d'interprétation.
- La couverture est très inégale : **100 %** en Plat / Obstacle / Cross, seulement **1–5 %** en Trot.

**Analyse** :
- `P = PMU-direct` (via `coursesCourues[].etatTerrain`)
- `D = partielle` — 38,8 % globalement, avec une **disparité disciplinaire majeure**
- `Q = conditionnelle` — bonne quand présente, absente sinon
- `I = conforme` **une fois la source corrigée** ; **détournée** avant (retournait une constante)
- `A = Plat/Obstacle/Cross : oui ; Trot : quasi non`
- `R = constante` (50,0) **avant correction** ; `neutre-explicite` après

**Qualification finale : FRAGILE en Trot (donnée quasi absente), PARTIEL ailleurs.** La v1 le classait « PARTIEL » uniformément : c'était une erreur de périmètre.

**Décision D-14** : accepter que le critère `terrain` soit structurellement peu informatif en Trot, et rendre ce fait **visible** plutôt que de laisser une constante silencieuse.

### D.2.6 Gains — `gains`

**Ce qui est établi [DÉMONTRÉ]** : `zone_turf_service.dart:1005-1018` contient un repli **fabriqué** :

```dart
if (gainsDernierAn <= 0) {
  // Fallback : estimé à 20% des gains totaux si non disponible
  gainsDernierAn = (gainsCarriere * 0.20).round();
}
```

Ce n'est pas une estimation documentée comme telle dans l'interface : c'est une **valeur inventée** qui se présente ensuite comme une donnée.

**Analyse** :
- `P = PMU-direct` pour les gains de carrière ; **`aucune`** pour les gains du dernier an lorsque le repli s'active
- `D = partielle`
- `Q = ` **`fabriquée`** lorsque le repli s'active
- `I = conforme` pour la carrière, **détournée** pour « dernier an »
- `A = toutes`
- `R = variable-non maîtrisée`

**Qualification finale : PARTIEL, avec un défaut d'alimentation de nature « donnée fabriquée ».** C'est le seul critère du tableau dans ce cas, et c'est inacceptable au regard de votre exigence d'honnêteté.

**Décision D-10 (conservée de la v1, non validée)** : supprimer le repli de 20 %. **Cette décision touche un mécanisme de production (§36) et exige votre validation formelle.** Elle n'est pas appliquée.

### D.2.7 Progression — `progression`

**Ce que vous demandez** : chercher une alimentation **authentique** permettant d'éviter le repli artificiel de 20 %, et si aucune ne convient, proposer un comportement **neutre conforme aux mécanismes existants**.

**1. Pourquoi le critère est contaminé aujourd'hui** : `gainsDernierAn` alimente la progression. Si `gainsDernierAn = gainsCarriere × 0,20`, alors la progression calculée est une **projection linéaire constante**, identique en proportion pour tous les chevaux. Elle n'apporte aucune information discriminante **et** elle est fausse.

**2. Sources authentiques candidates, examinées**

| Candidate | Disponible ? | Pertinence | Verdict |
|---|---|---|---|
| `gainsDernierAn` réel du PMU | **[À VÉRIFIER]** — le champ `gainsParticipant` est lu, mais le repli s'active quand il est ≤ 0 | Directe | **À privilégier** : si le PMU expose réellement les gains sur 12 mois, le repli devient inutile |
| Évolution des gains entre deux sauvegardes | **Oui**, sur les deux backups réels | Indirecte mais authentique | Recevable comme source de secours |
| Tendance des places sur les N dernières courses | **Oui** — via `coursesCourues` | Directe, et déjà disponible | **Meilleure candidate** |
| Évolution du rating ELO du cheval | **Oui** — ELO conservé | Directe | Recevable, mais dépend de la qualité de l'identité (B.4) |
| `reductionKilometrique` comparée à la médiane du cheval | **Oui** — présente sur 73,3 % des entrées | Directe et **de bonne qualité** | **Excellente candidate** : mesure de performance, pas de gains |

**3. Recommandation**

La **progression** est sémantiquement une **tendance de performance**, pas une tendance de gains. Les gains sont un proxy, et un proxy qui dépend du niveau des courses courues (un cheval qui monte de catégorie gagne moins en gagnant plus). La `reductionKilometrique` est, elle, une mesure directe **et déjà présente sur 73,3 %** des entrées.

**Alimentation authentique proposée** :
1. **Primaire** : tendance de `reductionKilometrique` du cheval sur ses dernières courses, comparée à sa propre médiane. **Authentique, mesurable, disponible.**
2. **Secondaire** : évolution des gains réels entre observations successives.
3. **Aucun repli inventé.** Si aucune donnée n'existe (cheval débutant, `indicateurInedit: true`), alors **comportement neutre**.

**4. Comportement neutre conforme aux mécanismes existants**

Les mécanismes existants connaissent déjà la notion de neutralité : `scoreMouvementCote` renvoie `50` = « neutre / hors fenêtre », et `scorePoids` renvoie `50.0` quand la donnée manque. **La neutralité applicable est donc une valeur médiane explicite, documentée comme telle, et distinguable d'une vraie valeur par un indicateur de provenance.**

Ce qui est proposé **n'invente aucun mécanisme** : c'est le comportement déjà utilisé par deux autres critères du même moteur.

**Décision D-15** : remplacer le repli `20 %` par une alimentation authentique (`reductionKilometrique` + gains réels) avec neutralité explicite pour les débutants. **Touche un mécanisme de production (§36) → validation formelle requise.**

### D.2.8 Poids relatif — `poidsRel`

**Ce qui est établi [DÉMONTRÉ]** : un producteur de `p.poids` **existe** — `zone_turf_service.dart:624` :
```dart
final poidsDixiemesKg = (pm['handicapPoids'] as num?)?.toDouble() ?? 0.0;
final poidsKg = poidsDixiemesKg > 0 ? poidsDixiemesKg / 10.0 : 0.0;
```

**Correction explicite** : la v1 affirmait « aucun producteur de `p.poids` n'existe ». **C'était faux**, et cette révision le corrige.

**Analyse** :
- `P = PMU-direct` (`handicapPoids`, en dixièmes de kg)
- `D = conditionnelle` — **uniquement les courses de handicap**
- `Q = conditionnelle`
- `I = conforme` — `scorePoids` renvoie `50.0` si `poids <= 0 || poidsMoyenChamp <= 0` (`zt_models.dart:735`), donc la neutralité est **explicite**
- `A = Plat et Obstacle` ; **`50.0` forcé en Trot** (`isGalopCourse` dans `ia_pronostic_engine.dart`)
- `R = neutre-explicite` → **le meilleur comportement du tableau**

**Qualification finale : PARTIEL par disponibilité (handicaps seulement), mais avec une alimentation propre et une neutralité explicite.** C'est un critère **sain**, dont la limite est la source, pas le traitement.

### D.2.9 Place au départ — `placeDepart`

**Ce que vous rappelez** : ce critère utilise une donnée PMU, `placeCorde`.

**Ce qui est établi [DÉMONTRÉ]** :
- `zone_turf_service.dart:708` : `final int placeDepart = (pm['placeCorde'] as num?)?.toInt() ?? 0;`
- `zt_models.dart:206` : `placeDepartInt: j['place_depart'] as int? ?? 0;`
- `ia_pronostic_engine.dart` : `_scorePlaceDepart(p.placeDepartInt, course.partants.length, course.type, course.distance)`

**Le défaut précis** : `?? 0` produit la valeur `0`, qui est **indistinguable** de « pas de corde attribuée » et de « corde n° 0 » (impossible). La neutralité n'est **pas explicite** : elle est confondue avec une valeur du domaine.

**Analyse** :
- `P = PMU-direct` (`placeCorde`)
- `D = ` **[À VÉRIFIER]** — la présence effective de `placeCorde` dans les réponses n'a pas été mesurée dans ce chantier
- `Q = conditionnelle` — `0` comme sentinelle silencieuse
- `I = conforme` (`_scorePlaceDepart` reçoit le nombre de partants, le type et la distance — donc le calcul est contextuel)
- `A = dépend du type de départ` — la corde n'a pas le même sens en plat, en autostart et en obstacle
- `R = variable-non maîtrisée` — `0` peut produire un score non neutre

**Qualification finale : PARTIEL, avec un défaut d'alimentation nommé (sentinelle `0` indistinguable).**

**Décision D-16** : distinguer `placeCorde` absent (`null`) de `placeCorde = 0`, et rendre la neutralité explicite — sur le modèle de ce que fait déjà `scorePoids`. **Touche un mécanisme de production → validation requise.**

## D.3 Synthèse des défauts d'alimentation par nature

| Nature du défaut | Critères concernés | Correction possible sans toucher aux formules ? |
|---|---|---|
| **Donnée fabriquée** | `gains`, `progression` | **Non** — exige D-10 / D-15 |
| **Sentinelle indistinguable de l'absence** | `record` (9999,0), `placeDepart` (0) | **Non** — exige D-13 / D-16 |
| **Source structurellement absente** | `terrain` (avant correction), `jockey`, `entraineur` | **Oui** — par acquisition de faits (section G) |
| **Troncature de source** | `jockey`, `entraineur` | **Oui** — par acquisition de la composition complète |
| **Repli silencieux** | `discipline` (branche `global`) | **Oui** — par visibilité, sans changer le repli |
| **Limite de disponibilité assumée** | `poidsRel` (handicaps), `terrain` (Trot) | Rien à corriger — à **documenter** |

**Conclusion de section** : sur neuf critères conflictuels, **deux** seulement (`poidsRel` et, après correction de source, `terrain` hors Trot) ont une alimentation propre. **Quatre** exigent une décision qui touche la production (`gains`, `progression`, `record`, `placeDepart`). **Trois** se corrigent par acquisition de données (`jockey`, `entraineur`, `terrain`).
---

# E. TECHNOLOGIES DE STOCKAGE PAR CATÉGORIE ET ORGANISATION DES FICHIERS

Cette section traite les points **4**, **7** et **8** de votre consigne. Elle corrige le rejet de la v1 : **aucune technologie n'est écartée au motif que la prévisualisation Web ne la prend pas en charge directement.** Une application Android finale a le droit d'utiliser les meilleurs outils d'Android.

## E.1 Le principe qui rend le test Web possible malgré tout

**Le problème réel de la v1** : elle rejetait SQLite parce que `sqflite` n'existe pas sur Web, et concluait « donc SharedPreferences partout ». C'était une erreur de raisonnement : elle transformait une contrainte de **l'outil de test** en contrainte de **l'architecture de production**.

**La correction** : introduire une **couche d'abstraction de support**. Le code métier ne connaît jamais le support physique. Il connaît une interface.

```
┌─────────────────────────────────────────────────────────────┐
│  CODE MÉTIER (19 critères, apprentissage, rapports, ELO)     │
│  Ne connaît QUE les interfaces ci-dessous                    │
└─────────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────────┐
│  COUCHE COMMUNE DE GESTION DES CONNAISSANCES                 │
│  résolution d'identité · politiques de rétention · fusions    │
│  invalidation de dépendances · sérialisation canonique        │
└─────────────────────────────────────────────────────────────┘
                            │
     ┌──────────────┬───────────────┬──────────────────┐
     ▼              ▼               ▼                  ▼
┌─────────┐  ┌──────────────┐  ┌───────────┐  ┌──────────────┐
│ Magasin │  │ Magasin      │  │ Magasin   │  │ Magasin      │
│ FAITS   │  │ APPRENTISSAGE│  │ ARCHIVES  │  │ CACHE        │
│ (F1)    │  │ (F3)         │  │ (immuable)│  │ (jetable)    │
└─────────┘  └──────────────┘  └───────────┘  └──────────────┘
     │              │               │                  │
     └──────────────┴───────────────┴──────────────────┘
                            │
┌─────────────────────────────────────────────────────────────┐
│  ADAPTATEURS DE SUPPORT (interchangeables, testables)        │
│  · SqliteAdapter      → Android (production)                 │
│  · MemoryAdapter      → tests unitaires                      │
│  · PrefsAdapter       → Web / prévisualisation               │
└─────────────────────────────────────────────────────────────┘
```

**Ce que cela permet, concrètement** : la même logique métier, testée sur Web avec `PrefsAdapter` en mémoire, puis exécutée sur Android avec `SqliteAdapter`. La capacité de vérification est **conservée**, et la technologie adaptée à Android est **retenue**.

**Ce que cela coûte** : une couche d'indirection, donc de la complexité, et une discipline : aucun accès direct à `SharedPreferences` depuis le code métier. **[HYPOTHÈSE]** Ce coût est acceptable au vu du gain — mais c'est une hypothèse, pas un fait mesuré.

## E.2 Affectation par catégorie de donnée

Le principe d'affectation est : **le support suit la forme de la donnée et son mode d'accès**, jamais l'inverse.

| Catégorie | Nature | Volume attendu | Accès dominant | Support proposé | Justification |
|---|---|---|---|---|---|
| **Paramètres, préférences, options** | Petit, scalaire | Quelques Ko | Lecture au démarrage | **SharedPreferences** | Adapté : petit, clé-valeur, lecture immédiate |
| **Poids de l'IA (`ia_poids_v3`)** | Petit, structuré | ≈ 3,9 Ko **[MESURÉ]** | Lecture totale, écriture rare | **SharedPreferences ou fichier JSON** | Trop petit pour justifier une base |
| **Seuils, labels, types** | Petit, structuré | ≈ 45 Ko max **[MESURÉ]** | Lecture totale | **SharedPreferences** | Idem |
| **Faits PMU — courses, participations** | F1, volumineux, indexé | **Croissance non bornée** | Requêtes ciblées par date/cheval | **Base structurée indexée (SQLite)** | Seul support permettant requête ciblée sans chargement total |
| **Chevaux, jockeys, entraîneurs, hippodromes** | Référentiels | Croissance lente | Résolution d'identité | **Base structurée indexée** | Clés, alias, index |
| **Ratings ELO** | F3, volumineux, actualisation individuelle | 41,8 clés/jour **[MESURÉ]** | Écriture individuelle, lecture ciblée | **Base structurée indexée** (voir H) | Une mise à jour ELO ne doit pas réécrire l'ensemble |
| **Rapports journaliers** | Structuré, versionné | 1,13/jour **[CALCULÉ]** | Lecture par date, par identifiant | **Base structurée indexée** | Déduplication par empreinte + index sur date |
| **Bilans (semaine, mois)** | Agrégats + références | Faible (≈ 100 o/bilan) **[MESURÉ]** | Lecture rapide d'un bilan | **Base structurée indexée** | L'agrégat est petit ; les références remplacent les copies |
| **Pronostics (600 max)** | Structuré, volumineux | 600 entrées **[DÉMONTRÉ]** | Lecture des récents, archivage | **Base structurée** + archives | Blob actuel compressé 147 Ko **[MESURÉ]** |
| **Journal (500 max)** | Journal d'événements | 500 entrées **[DÉMONTRÉ]** | Ajout seul, lecture récente | **Base structurée** ou fichier append-only | Ajout seul = pas de réécriture |
| **Archives permanentes** | Immuable, compressé | Croissance monotone | Lecture rare, par segment | **Fichiers segmentés compressés** | Immuabilité + compression = gain maximal |
| **Pronostics archivés** | Immuable | Croissance monotone | Lecture rare | **Fichiers segmentés compressés** | Idem |
| **Tickets / données financières** | Structuré, petite volumétrie | Faible | Lecture totale, écriture fréquente | **Base structurée** | Intégrité forte requise |
| **Caches temporaires** | Jetable | Variable | Écriture/lecture rapide | **Répertoire temporaire** (`getTemporaryDirectory`) | Doit pouvoir être vidé sans perte |
| **Sauvegardes exportées** | Fichier autonome | ≈ 12 Mo aujourd'hui **[MESURÉ]** | Écriture séquentielle | **Fichier** (voir L) | Doit être déplaçable et partageable |

**Sur les 41,8 clés ELO par jour [MESURÉ]** : c'est cette mesure qui condamne le stockage actuel. Écrire un rating individuel dans un `SharedPreferences` oblige à réencoder **l'ensemble** de la table (`elo_service.dart:2691`, `prefs.setString(_prefsKey, jsonEncode(data))`). À 41,8 ajouts/jour, la table entière est réécrite 41,8 fois par jour.

## E.3 Les technologies envisagées — avantages, inconvénients, verdict

**Aucune n'est sélectionnée définitivement.** **[À VÉRIFIER]** chacune devra être confrontée à la version de Flutter/Dart gelée du projet (3.35.4 / 3.9.2).

| Technologie | Avantages | Inconvénients | Adapté à | Verdict |
|---|---|---|---|---|
| **SharedPreferences** | Déjà présent ; simple ; synchrone en lecture | Écriture = réencodage complet ; pas de requête ; pas d'index ; taille non faite pour ça | Paramètres, petits blobs | **Conservé** pour son domaine, **pas** pour les connaissances |
| **SQLite via `sqflite`** | Index, requêtes ciblées, transactions, actualisation ligne à ligne ; standard Android | Pas de support Web direct ; nécessite adaptateur pour les tests | Faits, entités, rapports, ELO | **Candidat principal** pour le magasin structuré |
| **`sqflite_common_ffi`** | Même API, base SQLite sur desktop et tests ; permet de tester sans Android | Nécessite une configuration ; pas de Web | Tests unitaires, desktop | **Candidat** pour l'adaptateur de test |
| **`sqflite_common_ffi_web`** | SQLite en WebAssembly ; permettrait de tester la **même** base sur Web | Taille WASM ; initialisation plus lourde ; **[À VÉRIFIER]** compatibilité avec la version gelée | Prévisualisation Web du magasin réel | **Candidat intéressant** — c'est la réponse propre au problème posé par la v1 |
| **Isar** | Très rapide ; orienté objet ; index | Dépendance lourde ; support Web limité ; historique de maintenance à vérifier | — | **Non retenu à ce stade** (risque de dépendance) |
| **Drift (Moor)** | Typage fort, génération de code, multiplateforme, Web via WASM | Génération de code ; courbe d'apprentissage ; dépendances plus nombreuses | Magasin structuré | **Candidat alternatif** à sqflite |
| **Hive** | Rapide, pur Dart, Web supporté | Pas de vraie requête/index relationnel ; inadapté aux jointures | Caches, petits objets | **Adapté au cache**, pas aux faits |
| **Fichiers JSON compressés segmentés** | Universalité ; compression forte ; immuable ; inspectable | Pas de requête ciblée sans index | **Archives** | **Retenu pour les archives** |
| **ObjectBox** | Très performant | Dépendance binaire ; Web limité | — | **Non retenu à ce stade** |

**Ce qui a changé par rapport à la v1** : la v1 écartait SQLite au motif du Web. Cette révision le **retient comme candidat principal** pour les faits, et traite le problème du test Web par un **adaptateur** — ce qui est la réponse correcte.

**Décision D-17** : choix définitif du moteur du magasin structuré (SQLite via `sqflite` **ou** Drift). **Non tranchée ici.** Les deux satisfont les exigences ; le choix dépend de la tolérance aux dépendances et de la génération de code. **[À VÉRIFIER]** avant : compatibilité effective avec Flutter 3.35.4 / Dart 3.9.2.

## E.4 Organisation des dossiers et des fichiers

Arborescence proposée. Les noms sont indicatifs ; la structure, elle, est structurante.

```
[Documents de l'application]                    ← persistant, sauvegardé
├── base/
│   └── pronostic.db                            ← magasin structuré (SQLite)
│       ├── courses · participations            ← faits F1
│       ├── chevaux · alias                     ← référentiel d'identité
│       ├── jockeys · entraineurs · hippodromes ← référentiels
│       ├── elo_ratings                         ← F3 ELO (une ligne par entité/discipline)
│       ├── rapports · rapport_versions         ← rapports + versions
│       ├── bilans_semaine · bilans_mois        ← agrégats + références
│       ├── pronostics                          ← pronostics actifs
│       ├── tickets                             ← données financières
│       └── journal                             ← ajout seul
│
├── archives/                                   ← immuable, segmenté, compressé
│   ├── faits/AAAA-MM.json.gz
│   ├── rapports/AAAA.json.gz
│   ├── pronostics/AAAA.json.gz
│   └── manifeste.json                          ← inventaire des segments + empreintes
│
├── config/
│   ├── poids_ia.json                           ← F3 poids
│   ├── seuils.json
│   └── registre_politiques.json                ← section C.6
│
└── sauvegardes/                                ← exports produits
    └── pronostic_AAAA-MM-JJ_HHmm.ptg          ← format versionné (section L)

[Répertoire temporaire]                          ← jetable, JAMAIS sauvegardé
├── export_en_cours/                            ← écriture atomique .tmp → rename
├── caches/                                     ← statistiques recalculables
└── logs/
```

**Règles structurantes attachées à cette arborescence :**

1. **Trois zones de durabilité distinctes** : *Documents* (persistant, sauvegardé), *temporaire* (jetable, jamais sauvegardé), *archives* (immuable). Mélanger ces zones est ce qui a produit la non-atomicité actuelle (DF-11).
2. **Le temporaire ne contient jamais de connaissance.** Une écriture n'est valide qu'après avoir atteint la zone persistante.
3. **Les archives sont séparées de la base.** La base peut être reconstruite partiellement depuis les archives ; l'inverse n'est pas vrai.
4. **Un manifeste d'archives** (avec empreintes) rend la présence vérifiable sans lire les segments.
5. **Aucun fichier de données dans le répertoire de l'application** (celui qui est effacé à la désinstallation) — sauf si l'utilisateur accepte de perdre les connaissances.

> **Point à trancher (D-18)** : l'emplacement des connaissances sur Android. Le stockage interne de l'application est effacé à la désinstallation ; le stockage externe nommé survit mais est visible de l'utilisateur et peut être modifié. Le choix a des conséquences sur la durabilité **et** sur la sécurité. **Non tranché ici.**

---

# F. FONCTIONNEMENT ÉVÉNEMENTIEL SANS BOUCLE INUTILE

Cette section traite le point **5** de votre consigne.

## F.1 Ce que la garde `_loading` démontre — et ce qu'elle ne démontre pas

**[DÉMONTRÉ]** Il existe une garde `_loading` qui empêche certains traitements de s'exécuter en parallèle. Votre consigne est exacte : **elle ne démontre pas l'absence de boucles inutiles**.

**Raison** : `_loading` répond à la question « deux traitements tournent-ils en même temps ? ». Elle ne répond pas à « un traitement tourne-t-il alors que rien n'a changé ? ». Ce sont deux questions différentes. La seconde est celle qui produit la consommation inutile.

**Ce qu'il faut donc ajouter** : une notion de **périmètre de changement**. Un traitement n'est déclenché que si une donnée **pertinente pour lui** a changé.

## F.2 Détection des changements par catégorie de données

**Ce qui est établi [DÉMONTRÉ]** : il existe une signature de réunions (`_signaturedReunions`) fondée sur une comparaison. Elle ne couvre pas nécessairement toutes les modifications pertinentes — c'est votre remarque, et elle est juste : une signature de **réunions** ne peut pas détecter un changement de **cote**, de **résultat officiel**, d'**état de terrain** ou de **composition de participants**.

**Proposition : une signature par catégorie, et des dépendances déclarées entre catégories et calculs.**

```
CATÉGORIE DE DONNÉE          →  CALCULS DÉPENDANTS
─────────────────────────────────────────────────────────
composition des partants     →  liste de courses, moteur de pronostic
cotes                        →  critère mouvCote, cote de référence
résultats officiels          →  pronostics (résolution), rapports, ELO, statistiques
état de terrain              →  critère terrain, statistiques par terrain
réduction kilométrique       →  critère record, critère progression
poids / handicap             →  critère poidsRel
place à la corde             →  critère placeDepart
musique (mise à jour)        →  critères constance, victoires, forme
poids de l'IA (F3)           →  TOUS les 19 critères
seuils / calibration (F3)    →  TOUS les 19 critères
```

**Règle d'exécution** : un calcul n'est réexécuté que si **au moins une** de ses dépendances déclarées a changé. C'est ce qui remplace la signature unique par une couverture réelle.

**La signature d'une catégorie doit inclure ce qui compte vraiment** :

| Catégorie | Ce que la signature doit couvrir | Ce qu'une signature de réunion ne couvre pas |
|---|---|---|
| Composition | nombre de partants **et** ensemble des numéros **et** ensemble des non-partants | Un cheval déclaré non-partant |
| Cotes | valeur par cheval, avec l'instant de relevé | Une cote qui bouge |
| Résultats | arrivée officielle, statut « définitive » | Un résultat qui devient définitif |
| Terrain | valeur de `etatTerrain`, `penetrometre` | Un terrain qui change |
| F3 | empreinte de `ia_poids_v3`, `ia_seuils_v1` | Un apprentissage qui a modifié les poids |

**Point crucial** : la signature du F3 est celle qui manque le plus. Si les poids changent, **les 19 critères changent de valeur**, donc tous les pronostics doivent être reconsidérés. Aucun mécanisme actuel ne le détecte explicitement. **[DÉMONTRÉ]** par absence de dépendance déclarée.

## F.3 Actualisation ciblée — la règle du moindre périmètre

Principe : **le plus petit recalcul qui rétablit la correction.**

| Événement | Recalcul | Ce qui n'est PAS recalculé |
|---|---|---|
| Nouvelle cote | Les critères dépendant de la cote, pour les chevaux de **cette** course | Rien d'autre |
| Résultat officiel d'une course | Résolution des pronostics de cette course ; agrégats de la journée ; ELO des chevaux **de cette course** | Les autres courses, les autres jours |
| `etatTerrain` corrigé | Statistiques terrain des chevaux **de cette course** ; critère terrain | Historique global |
| Nouvelle course détectée | Faits de cette course | Aucune réévaluation d'historique |
| Poids F3 modifiés par apprentissage | **Tous** les critères pour les pronostics **à venir** | Les pronostics passés et leurs résultats |
| Seuils modifiés | Idem | Idem |

**La dernière ligne est essentielle** : un changement de poids ne doit **jamais** réécrire le passé. Un pronostic passé a été émis avec les poids de son époque ; le recalculer avec les poids actuels falsifierait l'historique d'évaluation. **C'est une exigence de préservation de l'apprentissage (section P).**

## F.4 Déduplication des requêtes simultanées

**Problème** : deux écrans, ou un écran et un rafraîchissement automatique, peuvent demander la même donnée au même moment.

**Solution** : un **registre de requêtes en cours**, indexé par clé de requête. Une seconde demande pour la même clé **ne lance pas** une seconde requête : elle **s'abonne** au résultat de la première.

```
Future<T> requeter<T>(CleRequete cle, Future<T> Function() travail) {
  final enCours = _enCours[cle];
  if (enCours != null) return enCours as Future<T>;   // abonnement, pas relance
  final f = travail().whenComplete(() => _enCours.remove(cle));
  _enCours[cle] = f;
  return f;
}
```

**Ce que cela garantit** : N demandes simultanées → **1** exécution. C'est mesurable et testable.

## F.5 Tentatives bornées

**Problème** : une requête réseau qui échoue peut être retentée indéfiniment, ou en boucle serrée.

**Règles proposées** :
- Nombre maximal de tentatives **explicite et déclaré** (par exemple 3), jamais implicite.
- **Délai croissant** entre tentatives, avec un plafond.
- **Abandon définitif** après épuisement, avec un état d'erreur **visible** pour l'utilisateur (et non un silence).
- **Aucune tentative** si l'échec est de nature définitive (ressource inexistante, format invalide) — retenter ne peut pas réussir.

**Ce qui est à éviter et qui est le défaut actuel [DÉMONTRÉ]** : un échec silencieux qui laisse croire à une absence de données. C'est ce qui produit la confusion « aucune donnée » / « erreur ».

## F.6 Gestion des absences confirmées

**Distinction nécessaire** — trois états, jamais confondus :

| État | Signification | Comportement |
|---|---|---|
| **Absent** | L'information n'existe pas dans la source | Comportement neutre **explicite** ; mémorisé comme absent pour ne pas redemander |
| **Indisponible** | L'information existe peut-être, mais la requête a échoué | Retentative **bornée** ; état d'erreur visible |
| **Présent** | L'information est là | Exploitation normale |

**Ce que la distinction permet** : ne pas redemander indéfiniment une information **prouvée absente** (ce qui est la source d'une boucle inutile), tout en continuant à demander une information **indisponible**.

**Corollaire important, et c'est votre point sur les faits évolutifs** : une absence confirmée **n'est pas une absence définitive**. Une `etatTerrain` absente aujourd'hui peut être publiée demain. La mémorisation d'absence doit donc porter **une date et une durée de validité** : passé ce délai, l'absence est réexaminée. **Conserver sans jamais réactualiser serait un autre défaut** — c'est exactement ce que vous mettez en garde.

## F.7 Arrêt effectif des traitements inutiles

**Trois mécanismes, tous nécessaires :**

1. **Annulation coopérative** : un traitement dont la dépendance a changé pendant son exécution doit pouvoir être **annulé** plutôt que terminé puis jeté. Un résultat obsolète ne doit pas écraser un résultat plus récent.
2. **Suspension hors premier plan** : les traitements de rafraîchissement s'arrêtent quand l'application n'est pas visible. **[APPAREIL REQUIS]** pour mesurer l'effet réel sur la batterie.
3. **Budget de travail par cycle** : un cycle de rafraîchissement traite un **nombre borné** d'éléments, et reporte le reste au cycle suivant. Cela évite les à-coups et rend la charge prévisible.

## F.8 Ne pas confondre performance historique stable et historique évolutif

**Votre remarque, reformulée** : une course passée est stable ; **la connaissance d'un cheval ne l'est pas**.

| Objet | Évolue ? | Conséquence |
|---|---|---|
| Résultat officiel d'une course terminée | **Non**, sauf correction officielle (section O) | Cachable, archiveable |
| Composition d'une course terminée | **Non**, sauf correction | Cachable, archiveable |
| `etatTerrain` d'une course passée | **Peut être renseigné après coup** | Ne doit pas être figé comme définitif |
| Statistiques d'un cheval | **Oui** — chaque nouvelle course les change | Recalculables, jamais figées |
| Rating ELO d'un cheval | **Oui** | Actualisation individuelle (section H) |
| Poids de l'IA | **Oui** | Versionnés (section P) |

**La règle** : le **fait** est stable, la **connaissance dérivée** ne l'est pas. Un cache de statistique doit donc porter une **empreinte de ses entrées**. Si les faits qui l'alimentent changent — y compris par correction officielle tardive — le cache est **invalidé automatiquement**.

**Ce que cela interdit formellement** : marquer une statistique comme « définitive » avec interdiction de recalcul. Votre consigne l'exige : *« Ne propose pas une conservation permanente associée à une interdiction définitive d'actualisation. »* C'est donc explicitement écarté.
---

# G. CONSERVATION DURABLE DES RATINGS ELO — SANS PLAFOND

Cette section traite le point **4** de votre consigne, sur l'ELO.

## G.1 Ce que la v1 proposait — et pourquoi c'est rejeté

La v1 proposait : *« Plafonner `elo_service` à 20 000 clés (A-02) »*, présenté comme une mesure de maîtrise de croissance.

**Cette proposition est retirée.** Motif : elle supprime des ratings acquis dans le seul but d'économiser de l'espace. Un rating est une connaissance **F3** — non recalculable sans rejouer l'historique complet. Le supprimer n'est pas une compression, c'est une perte.

**Ce que la v1 aurait dû voir** : le problème n'est pas le nombre de ratings. C'est que le stockage actuel oblige à réécrire **toute la table** pour modifier **un** rating.

## G.2 La structure actuelle, et sa faiblesse

**[DÉMONTRÉ]** Structure observée dans la sauvegarde du 13/11/2026 :

```json
"elo_service": {
  "NELSON DU RIB|TROT_ATTELE": { "nom": "NELSON DU RIB", "rating": 1448.32, "nb": 3, "var": -51.68 },
  "NEWTON TUILERIE|TROT_ATTELE": { "nom": "NEWTON TUILERIE", "rating": 1544.2, "nb": 2, "var": 44.2 }
}
```

Une **unique clé** `elo_ratings_v2`, contenant un objet JSON de la table entière.

**[DÉMONTRÉ]** `elo_service.dart:2691` :
```dart
await prefs.setString(_prefsKey, jsonEncode(data));
```
Chaque écriture sérialise **l'intégralité** de la table.

**Chiffrage du coût [MESURÉ] → [CALCULÉ]** :
- Croissance mesurée : **41,8 clés par jour**
- Une clé = 4 champs (`nom`, `rating`, `nb`, `var`)
- Chaque mise à jour d'un rating réencode **N** clés pour en modifier **1**
- À 41,8 écritures/jour, la table est donc intégralement réencodée **41,8 fois par jour**

**Ce que cela signifie concrètement** : le coût d'écriture croît **quadratiquement** avec le nombre de chevaux suivis. Doubler la base double le nombre d'écritures *et* double la taille de chaque écriture — donc **quadruple** le travail total. C'est la vraie raison pour laquelle cette table paraît « encombrante ». Elle ne l'est pas par sa taille, mais par son mode d'accès.

## G.3 Structure proposée

Une ligne par rating, dans le magasin structuré :

```
TABLE elo_ratings
┌──────────────────┬──────────┬────────────────────────────────────────┐
│ cheval_id        │ INTEGER  │ → référentiel chevaux (B.4)            │
│ discipline       │ TEXT     │ discipline normalisée                 │
│ rating           │ REAL     │ valeur ELO                            │
│ nb_courses       │ INTEGER  │ nombre de courses prises en compte     │
│ variation        │ REAL     │ dernière variation                    │
│ date_maj         │ INTEGER  │ horodatage                             │
│ source           │ TEXT     │ provenance du calcul                   │
├──────────────────┴──────────┴────────────────────────────────────────┤
│ CLÉ PRIMAIRE (cheval_id, discipline)                                │
│ INDEX sur (discipline, rating) → classement par discipline           │
│ INDEX sur (cheval_id)          → lecture de tous les ratings d'un cheval │
└─────────────────────────────────────────────────────────────────────┘
```

**Ce que cette structure permet, et que la structure actuelle interdit :**

| Opération | Aujourd'hui | Proposition |
|---|---|---|
| Mettre à jour **un** rating | Réécrire les N clés | Écrire **une** ligne |
| Lire le rating d'**un** cheval | Charger la table entière | Lire une ligne (index) |
| Lire les **M** meilleurs d'une discipline | Charger + trier en RAM | Index sur (discipline, rating) |
| Mettre à jour 41,8 ratings | 41,8 réencodages complets | 41,8 écritures de ligne (ou 1 transaction) |
| Compter les ratings | Charger tout | `COUNT(*)` |

**Projection de taille [CALCULÉ]**, hypothèses explicites :
- Une ligne ≈ 60–90 octets de données utiles (identifiant, discipline, 4 nombres, horodatage)
- Métadonnées SQLite (index, pages) ≈ +30 %
- Hypothèse retenue : **≈ 110 octets par rating** tout compris, en base non compressée

| Horizon | Ratings (41,8/j) | Taille estimée |
|---|---:|---:|
| 1 mois | ≈ 1 254 | ≈ 0,14 Mo |
| 1 an | ≈ 15 257 | ≈ 1,67 Mo |
| 3 ans | ≈ 45 771 | ≈ 5,03 Mo |
| 5 ans | ≈ 76 285 | ≈ 8,39 Mo |
| 10 ans | ≈ 152 570 | ≈ 16,77 Mo |

**[ESTIMÉ]** Ces valeurs sont un ordre de grandeur. Elles dépendent de la taille réelle de `cheval_id` et du taux d'index. **[À VÉRIFIER]** par un test de charge sur un jeu synthétique avant intégration.

**Point de comparaison** : 16,77 Mo à 10 ans dans une base indexée **n'est pas un problème**. Le même volume dans un `SharedPreferences` réencodé 41,8 fois par jour **en serait un**. C'est la démonstration que le sujet est le mode d'accès, pas la quantité.

## G.4 Identité du cheval — la clé `NOM|DISCIPLINE` est insuffisante

**Votre consigne** : *« sans considérer cette clé comme une identification universellement fiable du cheval »*. Confirmé, pour trois raisons déjà exposées en B.4 :

1. **Un nom n'est pas unique** dans le temps.
2. **La discipline n'appartient pas au cheval** : un cheval peut courir en trot attelé puis en trot monté, ou changer de discipline. La clé `NOM|DISCIPLINE` **fragmente** un même cheval en plusieurs entités sans lien entre elles.
3. **Le nom peut varier** (orthographe, accents, apostrophes).

**Conséquence** : le rating d'un cheval est aujourd'hui **éclaté par discipline**, et rien ne permet de savoir que deux lignes désignent le même animal.

**Point d'attention crucial** : corriger l'identité **modifie le comportement de l'ELO** — car fusionner deux entités change leurs adversaires, donc leurs espérances, donc leurs ratings. Or **[§36]** interdit de modifier le fonctionnement mathématique de l'ELO.

**Résolution de cette tension** : la proposition **ne change pas la formule**. Elle change **l'identité des entités** auxquelles la formule s'applique. Ce sont deux choses différentes — mais la seconde a des effets sur la première.

**Décision D-19** : distinguer `discipline` comme **attribut de la participation** et non de l'entité cheval. Trois options, à trancher par vous :

| Option | Description | Effet sur l'ELO | Risque |
|---|---|---|---|
| **O-1** | Conserver `NOM\|DISCIPLINE` tel quel | **Aucun** | Fragmentation persistante ; aucune unification |
| **O-2** | Ajouter un `cheval_id`, conserver les ratings par discipline | Rating par (cheval, discipline) — structure identique, identité améliorée | Faible : le calcul reste par discipline |
| **O-3** | Unifier le cheval et calculer un rating unique toutes disciplines | **Change le calcul** — pool d'adversaires élargi | **Élevé — touche §36** |

**Recommandation** : **O-2**. Elle améliore l'identité **sans toucher au calcul**. O-3 est explicitement écartée à ce stade car elle modifierait le fonctionnement mathématique de l'ELO.

**Aucune de ces options n'est retenue.** Elles sont posées pour votre arbitrage.

## G.5 Actualisation individuelle

**Exigence** : mettre à jour un rating sans toucher aux autres. C'est exactement ce qu'un index et une clé primaire permettent.

**Règles proposées :**
1. **Écriture d'une ligne** pour une mise à jour, jamais de la table.
2. **Transaction par course** : les ratings de tous les chevaux d'une course sont écrits en **une** transaction. Si elle échoue, aucun rating n'est modifié — donc pas d'état partiel.
3. **Aucune purge automatique par ancienneté.** Un rating reste valable indéfiniment : l'ELO gère lui-même l'obsolescence par sa variance, ce qui est un mécanisme interne qu'il est interdit de doubler par une purge externe.
4. **Conservation de `nb_courses`** : sans ce compteur, un rating ne peut plus être pondéré par sa fiabilité. Il est donc **obligatoire** dans la nouvelle structure.

**Sur les « orphelins »** : **[DÉMONTRÉ]** il existe un marqueur `elo_orphelins_purges_v1` et un chemin de purge (`elo_service.dart:2406-2414`). Ce mécanisme supprime des ratings dont le cheval n'est plus référencé.

**Il relève de la même logique que le plafonnement** : supprimer un rating acquis. **Décision D-20** : examiner si ce mécanisme doit être conservé, neutralisé, ou transformé en simple marquage. **Non tranchée ici.** Aucune modification n'est appliquée.

## G.6 Ce qu'il faut vérifier avant intégration

| Vérification | Marque | Quand |
|---|---|---|
| Nombre réel de ratings dans la sauvegarde du 13/11 | **[À VÉRIFIER]** | Avant dimensionnement |
| Taille réelle d'une ligne sérialisée | **[À VÉRIFIER]** | Avant projection ferme |
| Débit d'écriture SQLite sur un appareil réel | **[APPAREIL REQUIS]** | Pendant l'intégration |
| Fréquence réelle des chevaux multi-disciplines | **[À VÉRIFIER]** | Détermine l'ampleur de la fragmentation |
| Absence d'identifiant fournisseur stable | **[À VÉRIFIER]** | Conditionne B.4 |

---

# H. OPTIMISATION DES REQUÊTES, DES TRAITEMENTS ET DES ÉCRITURES

Cette section traite le point **6** de votre consigne.

## H.1 Les trois gisements mesurés

| Gisement | Mesure | Origine | Correction |
|---|---|---|---|
| **Réécriture intégrale** | `_save()` réécrit **99,7 %** du volume (11 218 019 / 11 250 326 octets) | **[MESURÉ]** | Écriture incrémentale par entité |
| **Duplication** | 524 copies pour 219 contenus → **×2,39** | **[MESURÉ]** | Références + versions (section C) |
| **Chargement intégral** | Collections entières désérialisées au démarrage | **[DÉMONTRÉ]** `_load()` | Fenêtrage + index |

**Le premier gisement est le plus coûteux en énergie**, le deuxième en espace, le troisième en RAM. Ils se corrigent ensemble : un stockage structuré supprime les trois à la fois.

## H.2 Optimisation des écritures

**Principe** : **écrire seulement ce qui a changé, une fois, dans une transaction.**

| Règle | Application |
|---|---|
| Écriture par entité | Un pronostic modifié → une ligne, pas 600 |
| Transaction par unité logique | Une course = une transaction (faits + ratings + pronostics résolus) |
| Écriture différée et groupée | Accumuler les modifications sur une courte fenêtre, puis écrire en une transaction |
| Sérialisation canonique obligatoire | Sinon la déduplication par empreinte échoue (C.2) |
| **Écriture atomique** | `.tmp` → `rename` — jamais d'écriture directe sur le fichier cible (DF-11) |
| Journalisation avant écriture critiques | Permet la reprise après interruption (section M) |

**Sur l'écriture différée** : elle réduit le nombre d'écritures, mais crée une fenêtre de perte en cas de coupure. **Compromis proposé** : différer les écritures **non critiques** (statistiques recalculables), écrire **immédiatement** les écritures **critiques** (résultat officiel, ticket, rating ELO après une course). Les deux catégories sont distinguées par le registre de politiques (C.6).

## H.3 Optimisation des requêtes

**Principe** : **aucune requête sans index, aucune lecture sans borne.**

| Requête fréquente | Index nécessaire | Sans index (aujourd'hui) |
|---|---|---|
| Courses d'une date | `(date)` | Balayage complet |
| Participations d'un cheval | `(cheval_id)` | Balayage complet |
| Dernières N courses d'un cheval | `(cheval_id, date DESC)` | Chargement + tri en RAM |
| Rapports par empreinte | `(empreinte)` — unique | Balayage de 524 copies |
| Bilan d'une semaine | `(lundi)` | Désérialisation imbriquée |
| Ratings d'une discipline triés | `(discipline, rating DESC)` | Chargement + tri en RAM |
| Pronostics non résolus | `(resultatReels IS NULL)` — index partiel | Balayage de 600 |
| Statistiques d'un hippodrome | `(hippodrome)` | Balayage |

**Règle de pagination** : toute liste affichable est lue **par page**, jamais intégralement. La taille de page est un paramètre, pas une constante dispersée.

## H.4 Optimisation des traitements

| Pratique | Effet |
|---|---|
| Recalcul paresseux (à la demande) | Aucun calcul pour une donnée jamais consultée |
| Cache avec empreinte d'entrées | Invalidation exacte, pas de recalcul inutile (F.8) |
| Recalcul par périmètre minimal | Voir F.3 |
| Calcul hors du fil principal | L'interface ne se bloque pas — **[APPAREIL REQUIS]** pour mesurer |
| Budget de travail par cycle | Charge lissée, pas d'à-coup (F.7) |

## H.5 Ce que l'optimisation ne doit pas faire

**Garde-fous explicites**, car une optimisation mal placée est plus dangereuse qu'une lenteur :

1. **Ne jamais changer un résultat de calcul** pour aller plus vite. Une optimisation qui modifie une valeur n'est pas une optimisation, c'est une régression déguisée.
2. **Ne jamais mettre en cache une valeur F3** comme si elle était recalculable en la marquant « définitive » (F.8).
3. **Ne jamais fusionner deux entités** pour réduire une jointure (B.4).
4. **Ne jamais supprimer une information** pour réduire un volume (section C).
5. **Ne pas présumer qu'une garde empêche un traitement inutile** (F.1) — c'est ce que la v1 a fait.

## H.6 Vérifications nécessaires

| Vérification | Marque |
|---|---|
| Coût réel d'une écriture SQLite transactionnelle | **[APPAREIL REQUIS]** |
| Mémoire réelle consommée par une page de résultats | **[APPAREIL REQUIS]** |
| Effet du calcul hors fil principal sur la fluidité | **[APPAREIL REQUIS]** |
| Gain effectif de la suppression du reencodage complet | **[CALCULÉ]** puis **[APPAREIL REQUIS]** |
---

# I. CAPACITÉ DE STOCKAGE ET PROJECTIONS JUSQU'À 10 ANS

Cette section traite le point **9** de votre consigne. Elle **remplace** les projections de la v1, dont le périmètre était insuffisant.

## I.1 Ce que la v1 avait omis

| Composante | v1 | Cette révision |
|---|---|---|
| Performances historiques PMU | **Absente** | Comptée |
| Statistiques hippiques | Partiellement | Comptée dans les caches |
| Ratings ELO sans plafond | Plafonnés à 20 000 (donc tronqués) | **Sans plafond** |
| Rapports historiques | Comptés, avec duplication | Comptés, **sans duplication** |
| Bilans | Supprimés (donc non comptés) | Comptés (agrégats + références) |
| Pronostics archivés | Absents | Comptés |
| Résultats officiels | Absents | Comptés dans les faits |
| Index et métadonnées | **Absents** | Comptés (+30 %) |
| Sauvegardes | **Absentes** | Comptées à part (I.5) |
| Espace temporaire | **Absent** | Compté à part (I.5) |

**Conséquence de fond** : les projections v1 étaient fausses non par erreur d'arithmétique mais par **erreur de périmètre**. Elles décrivaient le volume de ce qui **existait déjà**, pas celui de l'architecture cible.

## I.2 Le résultat qui contredit la v1 — et c'est le plus important

**L'architecture révisée est PLUS VOLUMINEUSE que le statu quo.**

| Horizon | Statu quo (rythme mesuré prolongé) **[CALCULÉ]** | Architecture révisée **[CALCULÉ]** |
|---|---:|---:|
| 1 mois | ≈ 12,0 Mo | **≈ 6,8 Mo** |
| 6 mois | ≈ 22,2 Mo | **≈ 40,6 Mo** |
| 1 an | **≈ 32,1 Mo** | **≈ 79,5 Mo** |
| 3 ans | **≈ 72,9 Mo** | **≈ 144,5 Mo** |
| 5 ans | **≈ 113,7 Mo** | **≈ 209,5 Mo** |
| 10 ans | **≈ 215,8 Mo** | **≈ 372,1 Mo** |

**Ce que cela signifie, sans détour** : à partir de six mois, l'architecture révisée occupe **davantage de disque** que l'actuelle. Ce n'est pas un défaut : c'est la conséquence directe et assumée de votre principe. **Le statu quo est « plus petit » uniquement parce qu'il ne conserve pas les faits PMU.**

**La v1 annonçait un « plateau de 9,27 Mo » et un gain de 46,1 %. Ces deux chiffres sont retirés** : ils décrivaient une architecture qui supprimait 24 rapports et plafonnait l'ELO, c'est-à-dire une architecture qui perdait des connaissances.

**Le bon critère de comparaison n'est donc pas le volume, mais le rapport entre volume et connaissance conservée** :

| Architecture | Volume à 10 ans | Faits PMU conservés | ELO conservé | Rapports conservés | Coût d'écriture |
|---|---:|---|---|---|---|
| Statu quo | ≈ 216 Mo | **Aucun** | Plafonné | Tronqués + 524 copies | 99,7 % réécrit à chaque sauvegarde |
| Révisée | ≈ 372 Mo | **Tous** | **Intégral** | **Uniques + versions** | Ligne modifiée seulement |

## I.3 Détail du calcul — hypothèses explicites

**Entrées mesurées [MESURÉ]** :

| Entrée | Valeur | Origine |
|---|---|---|
| Croissance du fichier actuel | 9 906 675 octets / 169 j = **58 619 o/j** = **20,4 Mo/an** | Delta entre les deux sauvegardes réelles |
| Nouvelles clés ELO | **41,8 / jour** | Mesure sur les deux sauvegardes |
| Rapports par jour | **1,13** | 219 dates / 194 jours |
| Taille d'un pronostic sérialisé | **3 262 o** | 163 083 / 50 (mesure S7-bis) |
| Ratio de compression réaliste | **5,51 : 1** | Mesure S7-bis (scores variés) |
| Plafonds existants | 600 pronostics / 500 journal / 365 rapports | Constantes du code |

**Hypothèses retenues [HYPOTHÈSE]** — chacune à vérifier avant d'engager une décision sur ces chiffres :

| Hypothèse | Valeur | Motif | A vérifier |
|---|---|---|---|
| Jours de courses par an | **320** | Calendrier PMU quasi quotidien | Nombre réel de jours avec courses |
| Courses par jour | **35** | Moyenne du champ `nb` des rapports observés | Distribution réelle sur 12 mois |
| Partants par course | **12** | Ordre de grandeur usuel | Distribution réelle |
| Taille d'une ligne participation | **400 o** | ~25 champs plats | Après modélisation du schéma |
| Taille d'une ligne course | **600 o** | ~40 champs | Idem |
| Taille d'une ligne ELO | **110 o** | 4 nombres + 2 textes + index | Après test de charge |
| Taille d'un rapport (une copie) | **1 200 o** | Contenu observé, 18 champs dont `cdet` | Mesure exacte sur le corpus |
| Surcoût métadonnées/index SQLite | **+30 %** | Ordre de grandeur usuel | Après création réelle des index |
| Compression des faits froids | **2,5 : 1** | Faits structurés répétitifs, moins compressibles que des scores variés | Après compression réelle d'un échantillon |
| Frontière vif/froid | **12 mois** | Au-delà, un fait n'est plus consulté pour une analyse courante | À valider selon l'usage réel |

**Ce que ce tableau implique** : aucun chiffre de la section I.2 n'est une mesure. Ce sont des **calculs dont chaque entrée est soit mesurée soit explicitement hypothétique**. Si une hypothèse change, le résultat change. **[À VÉRIFIER]** avant toute décision fondée sur ces chiffres.

## I.4 Détail par composante à 10 ans

| Composante | Volume | Part | Évolue ? |
|---|---:|---:|---|
| Faits PMU — participations (vif) | 61,6 Mo | 16,6 % | Oui, mais borné à 12 mois |
| Faits PMU — participations (froid) | 234,4 Mo | 63,0 % | Oui, **monotone** |
| Faits PMU — courses (vif + froid) | 48,5 Mo | 13,0 % | Oui |
| Ratings ELO | 18,2 Mo | 4,9 % | Oui, **monotone** |
| Rapports journaliers | 5,4 Mo | 1,4 % | Oui, lentement |
| Pronostics (600 max) | 1,9 Mo | 0,5 % | **Non** — plafonné |
| Tickets / financier | 1,4 Mo | 0,4 % | Oui, lentement |
| Bilans (agrégats + références) | 0,15 Mo | 0,04 % | Oui, négligeable |
| Journal (500 max) | 0,12 Mo | 0,03 % | **Non** — plafonné |
| **TOTAL** | **≈ 372 Mo** | 100 % | |

**[CALCULÉ]** Le poste dominant est **les faits PMU de participations** : **79,6 % du volume total**. C'est cohérent avec le principe — c'est précisément la connaissance authentique qu'il fallait conserver.

**Levier de réduction si nécessaire** : les faits froids (au-delà de 12 mois) sont **compressibles** et **archivables**. Passer la frontière vif/froid de 12 à 6 mois réduirait le volume vif de moitié, sans perdre un seul fait — seulement en changeant le support d'accès. C'est une décision de **performance**, pas de **conservation**.

## I.5 Volume permanent, volume temporaire, volume de sauvegarde

Votre consigne demande de distinguer le volume permanent du volume chargé en RAM. Il faut en fait distinguer **cinq** volumes.

| Volume | Nature | 10 ans | Remarque |
|---|---|---:|---|
| **Permanent sur disque** | Base + archives | **≈ 372 Mo** | Calculé en I.2 |
| **Temporaire de travail** | `.tmp`, caches, index temporaires | **≈ 0,7 × plus gros bloc exporté** | Voir ci-dessous — c'est le point critique |
| **Sauvegardes conservées** | Exports `.ptg` | **Variable** — voir avertissement | Une sauvegarde complète ≈ la taille du permanent |
| **Chargé en RAM** | Voir I.6 | **Non mesurable ici** | **[APPAREIL REQUIS]** |
| **Sauvegarde système Android** | Copie par le système | **Hors de notre contrôle** | À documenter |

**⚠️ Point critique — l'espace temporaire.** L'écriture atomique (`.tmp` → `rename`) exige **deux fois** l'espace du fichier pendant l'opération : l'ancien et le nouveau coexistent. Pour un export de 372 Mo, il faut donc **≈ 744 Mo libres** au moment de l'export.

**Ce que cela impose** : vérifier l'espace libre **avant** de commencer, et **échouer proprement** avec un message explicite si l'espace est insuffisant. Une écriture qui échoue à 90 % sans nettoyage laisse un `.tmp` orphelin qui consomme l'espace — et aggrave la situation au prochain essai. C'est un **défaut à éviter explicitement** (section N).

**Avertissement sur les sauvegardes** : si l'application conserve N exports, l'espace consommé est N × (taille du permanent). Sur un appareil de 64 Go avec 372 Mo de connaissances, conserver 5 sauvegardes = 1,86 Go. **La politique de conservation des sauvegardes est donc une décision aussi importante que celle des connaissances.** Elle n'est pas prise ici (**D-21**).

## I.6 Mémoire vive — ce qui est mesurable et ce qui ne l'est pas

**Ce qui est démontrable [DÉMONTRÉ]** — le défaut actuel de chargement :
- Les collections sont désérialisées **intégralement** au démarrage (`_load()`)
- Le blob de pronostics est décodé en entier : base64 → gzip → JSON → objets
- 524 copies de rapports sont désérialisées depuis les bilans imbriqués

**Ce que cela coûte en RAM [ESTIMÉ]** : un objet Dart désérialisé occupe typiquement **3 à 10 fois** sa taille JSON, selon la structure et les chaînes. Sur le fichier actuel de 12,3 Mo entièrement chargé, l'ordre de grandeur serait de **35 à 120 Mo** de tas.

**Ce chiffre n'est pas mesuré.** Il est donné comme ordre de grandeur, avec sa marque. **[APPAREIL REQUIS]** pour le mesurer réellement.

**Ce que l'architecture révisée change** :
- Aucune collection volumineuse n'est chargée en entier : lecture par page ou par requête.
- Les caches sont **explicitement bornés** (paramètre, pas constante dispersée).
- Le config (poids, seuils, registre) reste en mémoire : **≈ 0,1 Mo [MESURÉ]** (3,9 Ko + 45 Ko + marge).

**Cible de conception** : la RAM utilisée ne doit **pas** croître avec le volume stocké. C'est la propriété qui distingue une architecture correcte d'une architecture qui fonctionne « tant que les données sont petites ».

**Vérification nécessaire** : mesurer le tas après chargement complet de l'interface, sur un appareil réel, avec 1 mois puis 12 mois de données. **[APPAREIL REQUIS]** — c'est la mesure qui validera ou invalidera cette propriété.

---

# J. RAM, PROCESSEUR, BATTERIE ET PERFORMANCES

Cette section traite le point **10** de votre consigne.

## J.1 Ce qui est mesurable dans cet environnement, et ce qui ne l'est pas

| Élément | Mesurable ici ? | Marque |
|---|---|---|
| Volume réécrit à chaque sauvegarde | **Oui** — mesuré (99,7 %) | **[MESURÉ]** |
| Nombre d'écritures par jour | **Oui** — calculé depuis 41,8/jour | **[CALCULÉ]** |
| Ram inverse de la base complète pour 1 rating | **Oui** — démontré par le code | **[DÉMONTRÉ]** |
| Consommation RAM réelle | **Non** | **[APPAREIL REQUIS]** |
| Consommation batterie | **Non** | **[APPAREIL REQUIS]** |
| Fluidité (jank, images par seconde) | **Non** | **[APPAREIL REQUIS]** |
| Temps de démarrage | **Non** | **[APPAREIL REQUIS]** |
| Temps de requête SQLite | **Non** | **[APPAREIL REQUIS]** |

**Votre consigne est explicite : ces mesures ne doivent plus empêcher la rédaction.** Elles sont donc **nommées et différées**, avec la question précise à laquelle chacune répondra.

## J.2 Modèle de consommation — ce qui est démontrable sans appareil

**Batterie : la chaîne causale démontrée.**

**[DÉMONTRÉ]** Aujourd'hui : chaque mise à jour d'un rating ELO réencode la table entière (`elo_service.dart:2691`). À 41,8 clés/jour, cela produit **41,8 réencodages complets par jour**, chacun consommant :
- du **processeur** (sérialisation JSON)
- de la **mémoire** (chaîne JSON temporaire)
- des **entrées/sorties** (écriture du fichier de préférences)

**[CALCULÉ]** Si la table fait N clés, le travail quotidien est proportionnel à **41,8 × N**. Doubler la base **double** le coût quotidien — et comme N croît avec le temps, ce coût croît **au carré** avec la durée d'utilisation.

**C'est le seul mécanisme de ce projet dont on peut démontrer qu'il se dégrade quadratiquement avec le temps.** Aucune mesure sur appareil n'est nécessaire pour l'établir : c'est de l'arithmétique sur un fait de code démontré.

**Ce que l'architecture révisée change** : une mise à jour = une ligne = **O(1)**. Le coût quotidien devient constant, indépendant de N.

**Processeur : les trois postes identifiés**

| Poste | Aujourd'hui | Proposition |
|---|---|---|
| Sérialisation intégrale | À chaque `_save()` — 99,7 % du volume | Sérialisation de la ligne modifiée seulement |
| Désérialisation intégrale | À chaque `_load()` | Aucune (lecture paresseuse) |
| Compression/décompression | Sur le blob entier | Sur les segments d'archive seuls |

## J.3 Règles de conception pour la performance

1. **Aucune opération de volume dans le fil d'interface.** Les calculs longs vont dans un isolate ou une tâche de fond.
2. **Aucune écriture sur le chemin critique d'un affichage.** Une écriture différée non bloquante pour les données non critiques (H.2).
3. **Budget de travail par cycle** (F.7) : charge lissée, jamais de pic.
4. **Caches bornés explicitement** : un cache non borné est un défaut, pas une optimisation.
5. **Aucun rafraîchissement hors premier plan** (F.7).
6. **Pas de réveil périodique** sans nécessité démontrée : les réveils sont le premier poste de consommation batterie sur Android.

## J.4 Les mesures qui décideront

| # | Question | Méthode | Quand |
|---|---|---|---|
| **M-01** | Quel est le tas après chargement complet, à 1 mois de données ? | Profileur mémoire | Pendant intégration |
| **M-02** | Le tas croît-il linéairement avec les données stockées ? | Comparer 1 mois / 12 mois | Pendant intégration |
| **M-03** | Quel est le temps d'un batch de 42 écritures ELO ? | Chronométrage | Pendant intégration |
| **M-04** | Combien de temps prend un démarrage à froid ? | Chronométrage | Pendant intégration |
| **M-05** | Y a-t-il des saccades lors du défilement d'une liste de 600 pronostics ? | Profileur d'images | Pendant intégration |
| **M-06** | Quelle consommation sur 8 h d'utilisation réelle ? | Batterie Android | Après intégration |
| **M-07** | Combien de temps dure un export complet de 372 Mo ? | Chronométrage | Avant mise en production |

**Tant que M-01 à M-07 ne sont pas faites, aucune affirmation sur les performances réelles ne peut être faite.** Ce rapport ne prétend pas que l'architecture proposée sera rapide : il prétend qu'elle **supprime les causes démontrées de lenteur**. C'est une différence.
---

# K. ARCHIVES HISTORIQUES — CONSERVATION ET CONSULTATION

Cette section traite le point **11** de votre consigne.

## K.1 Le principe : deux régimes, pas un compromis

Une connaissance n'a pas le même mode d'accès selon son âge. Vouloir un support unique pour tout conduit soit à charger trop, soit à purger trop. D'où **deux régimes explicites** :

| Régime | Contenu | Support | Accès | Modifiable ? |
|---|---|---|---|---|
| **Vif** | 12 derniers mois de faits, ratings courants, pronostics actifs, rapports courants | Base indexée | Requête ciblée | Oui |
| **Froid / archive** | Faits de plus de 12 mois, rapports pointés par un bilan, pronostics clôturés | Fichiers segmentés compressés + manifeste | Par segment, puis par index | **Non — immuable** |

**La frontière est un paramètre, pas une constante.** Elle est réglable selon les mesures M-01 à M-05.

## K.2 Ce qui va en archive, et pourquoi

| Objet | En archive ? | Motif |
|---|---|---|
| Courses et participations > 12 mois | **Oui** | Plus consultées pour l'analyse courante, mais **indispensables** à l'historique d'un cheval |
| Rapports pointés par un bilan | **Oui**, **quel que soit leur âge** | **C'est la correction du conflit 365 jours** (C.4) : un bilan doit rester résoluble indéfiniment |
| Pronostics clôturés (résolus) | **Oui** | Nécessaires à l'évaluation de la performance de l'IA |
| Bilans | **Non** — ils restent en base | Volume négligeable (0,15 Mo à 10 ans), et consultés fréquemment |
| Ratings ELO | **Non** | Consultés en permanence et mis à jour individuellement ; le volume est maîtrisé (18 Mo à 10 ans) |
| Journal ancien | **Oui**, au-delà de 500 | C'est déjà le comportement actuel |
| Poids / seuils (F3) | **Non, mais versionnés** | Voir section P — un poids passé doit rester lisible |

## K.3 Structure d'un segment d'archive

```
archives/faits/2027-03.json.gz
{
  "version": 1,
  "type": "faits",
  "periode": { "debut": "2027-03-01", "fin": "2027-03-31" },
  "empreinteContenu": "sha256:…",
  "nbCourses": 1085,
  "nbParticipations": 13020,
  "donnees": [ … ]
}
```

Et un **manifeste** unique, qui rend la présence vérifiable sans lire les segments :

```
archives/manifeste.json
{
  "version": 1,
  "segments": [
    { "fichier": "faits/2027-03.json.gz", "type": "faits", "periode": "2027-03",
      "empreinte": "sha256:…", "octetsCompresses": 4210000, "octetsBruts": 10500000,
      "nbEnregistrements": 14105 }
  ],
  "empreinteManifeste": "sha256:…"
}
```

**Ce que le manifeste apporte :**
1. **Vérification d'intégrité** sans décompresser : comparer l'empreinte du fichier à celle du manifeste.
2. **Localisation** d'une période sans balayer tous les fichiers.
3. **Détection de segment manquant** : un fichier référencé et absent est une anomalie détectable.
4. **Détection de segment orphelin** : un fichier présent et non référencé est signalable.

**Point honnête** : le manifeste est lui-même un point unique de défaillance. Il doit donc être **dupliqué dans la sauvegarde**, et son empreinte doit être incluse dans le checksum global (section L).

## K.4 Consultation rapide d'un ancien bilan — le parcours complet

**Objectif** : afficher un bilan de mois sans recalcul et sans tout charger.

```
1. Lire BilanMois(an, mo)                     → 1 requête indexée, ~400 o
2. Afficher ses agrégats                       → immédiat (7 valeurs stockées)
3. Si l'utilisateur demande le détail d'une semaine :
     lire BilanSemaine via semainesRef          → 1 requête, ~250 o
4. Si l'utilisateur demande les rapports d'une semaine :
     resolver rapportsRef                       → requête par empreinte
     · rapport présent en base   → lecture directe
     · rapport archivé           → lecture du segment + résolution
5. Afficher                                   → page de résultats
```

**Ce qui n'est jamais fait** : recalculer les agrégats. Ils sont stockés. **[DÉMONTRÉ]** les 7 agrégats (`tc, tr, tg, tt3, sm, md, mt`) sont de simples valeurs, ils n'ont aucune raison d'être recalculés à chaque consultation — c'est ce que la v1 proposait à tort (« recalculés à la demande »), ce qui aurait consommé du processeur pour un gain d'espace dérisoire.

**Ce qui rend la consultation rapide** : le bilan est **petit** et **pointe** au lieu de **contenir**. Aujourd'hui, afficher un mois oblige à désérialiser 242 120 octets de rapports imbriqués **[MESURÉ]** pour n'afficher que 7 nombres.

## K.5 Immuabilité et corrections

Un segment d'archive est **immuable** : on ne le réécrit pas.

**Alors comment corriger un fait archivé ?** — C'est la question à laquelle il faut répondre, sinon l'immuabilité devient une interdiction de correction, ce que votre consigne refuse.

**Solution : le journal de correction, en surcouche.**

```
archives/corrections.json
{
  "version": 1,
  "corrections": [
    { "cible": "course:2027-03-14/R2C3", "champ": "etatTerrain",
      "avant": "bon", "apres": "souple", "motif": "correction officielle PMU",
      "date": "2027-03-20T09:12:00", "source": "PMU" }
  ]
}
```

**Principe** : on ne modifie jamais un segment. On **applique** les corrections à la lecture. Le fait d'origine reste consultable ; la correction est traçable ; rien n'est détruit.

**[MESURÉ] justification de ce choix** : les 6 divergences de rapports montrent qu'un contenu peut légitimement exister en plusieurs versions. Le même principe s'applique aux faits : conserver la version d'origine **et** la correction vaut mieux qu'écraser.

**Conséquence sur les segments** : lorsqu'un segment accumule beaucoup de corrections, il peut être **réécrit en un nouveau segment** intégrant les corrections, l'ancien étant conservé jusqu'à validation. C'est une **compaction**, pas une destruction.

## K.6 Ce qui reste à décider

**D-22** : taille d'un segment d'archive. Mensuel (proposé) ou trimestriel ? Un segment trop petit multiplie les fichiers ; trop gros, il rend une correction coûteuse. **Non tranché.**

**D-23** : la frontière vif/froid (12 mois proposés). Dépend de l'usage réel. **Non tranchée.**

---

# L. SAUVEGARDE COMPLÈTE

Cette section traite le point **13** de votre consigne. Elle réécrit entièrement la partie correspondante de la v1, qui se contentait d'ajouter un checksum.

## L.1 Ce que la sauvegarde doit couvrir

**Exigence** : toutes les connaissances, sans exception. Le tableau ci-dessous est la liste de contrôle ; une sauvegarde qui omet une ligne est incomplète.

| # | Contenu | Aujourd'hui couvert ? | Support cible |
|---|---|---|---|
| 1 | Faits PMU — courses et participations | **Non** (non stockés) | Base + archives |
| 2 | Référentiels — chevaux, alias, jockeys, entraîneurs, hippodromes | **Non** (inexistants) | Base |
| 3 | Ratings ELO | **Oui** — clé `elo_ratings_v2` | Base |
| 4 | Poids de l'IA (`ia_poids_v3`) | **Oui** | Config |
| 5 | Seuils et calibration (`ia_seuils_v1`) | **Oui** | Config |
| 6 | Labels et types statistiques | **Oui** | Config |
| 7 | Pronostics (600) | **Oui** — blob gz+base64 | Base |
| 8 | Rapports journaliers | **Oui** | Base |
| 9 | Bilans semaine et mois | **Oui** — avec 524 copies | Base (agrégats + refs) |
| 10 | Journal (500) | **Oui** | Base |
| 11 | Archives historiques | **Non** (inexistantes) | Archives + manifeste |
| 12 | Journal de corrections | **Non** (inexistant) | Archives |
| 13 | Tickets et données financières | **Oui** — `paris`, `grosParis` | Base |
| 14 | Alertes | **Oui** | Config |
| 15 | Profil utilisateur | **Oui** | Config |
| 16 | Widgets (`widget`, 20 clés `widget_*`) | **Oui** — mais `widget` vide (2 o) **[MESURÉ]** | Config |
| 17 | Laboratoire IA (`laboIA`) | **Oui** | Config |
| 18 | Cache d'audit (`auditCache`) | **Oui** | Cache — **ne devrait pas être sauvegardé** |
| 19 | Cote de référence | **Oui** | Base |
| 20 | Registre des politiques (C.6) | **Non** (inexistant) | Config |

**Deux remarques sur l'existant [MESURÉ]** :
- `widget` pèse **2 octets** dans les deux sauvegardes alors que **20 clés `widget_*`** sont déclarées. La couverture est donc partielle sans que rien ne le signale.
- `auditCache` et les caches **ne devraient pas être sauvegardés** : ce sont des données recalculables. Les inclure gonfle la sauvegarde sans apporter de connaissance.

## L.2 Format de sauvegarde proposé

**Nom proposé** : `.ptg` (Pronostic — connaissances). Extension dédiée pour que le fichier soit identifiable et ne soit pas confondu avec un JSON quelconque.

**Structure — un conteneur, des blocs indépendants :**

```
pronostic_2026-11-13_1120.ptg
├── EN-TÊTE (non compressé, lisible)
│   ├── magie: "PTG1"
│   ├── versionFormat: 2
│   ├── versionApplication: "…"
│   ├── dateExport
│   ├── empreinteGlobale: sha256 de tous les blocs concaténés
│   └── inventaire: [ {id, type, octets, empreinte, versionSchema} … ]
│
├── BLOC config        (compressé)  → poids, seuils, labels, profil, alertes
├── BLOC elo           (compressé)  → ratings
├── BLOC pronostics    (compressé)  → 600 pronostics
├── BLOC rapports      (compressé)  → rapports + versions
├── BLOC bilans        (compressé)  → agrégats + références
├── BLOC journal       (compressé)  → 500 entrées
├── BLOC financier     (compressé)  → tickets, grosParis, cote
├── BLOC faits         (compressé)  → faits PMU de la base
└── BLOC archives      (compressé)  → segments + manifeste + corrections
```

**Pourquoi des blocs séparés plutôt qu'un seul JSON ?**

| Propriété | JSON unique (aujourd'hui) | Blocs séparés |
|---|---|---|
| Vérification d'intégrité | Impossible sans tout lire | **Par bloc**, et globale |
| Restauration partielle | Impossible | **Possible** (un bloc corrompu n'invalide pas les autres) |
| Compatibilité ancienne/nouvelle | Non gérée | **Version par bloc** |
| Dépendances entre blocs | Invisibles | **Déclarées dans l'inventaire** |
| Compression | Une seule | **Adaptée par type** |
| Reprise après interruption | À refaire entièrement | **Bloc par bloc** |

## L.3 Contrôles d'intégrité — trois niveaux

| Niveau | Objet | Détecte |
|---|---|---|
| **Niveau 1 — empreinte de bloc** | SHA-256 du contenu décompressé de chaque bloc | Corruption, troncature d'un bloc |
| **Niveau 2 — empreinte globale** | SHA-256 de la concaténation des empreintes de blocs, dans l'ordre de l'inventaire | Bloc manquant, bloc ajouté, réordonnancement |
| **Niveau 3 — cohérence croisée** | Vérification que les références d'un bloc pointent vers des identifiants présents dans un autre | Référence morte (ex. bilan pointant un rapport absent) |

**Le niveau 3 est celui que rien ne remplace.** Un fichier peut être parfaitement intègre au sens cryptographique et pourtant incohérent : tous les blocs présents, toutes les empreintes correctes, mais un bilan qui pointe vers un rapport qui n'existe pas. C'est précisément le risque que la déduplication par référence introduit (section C) — et c'est pourquoi il doit être contrôlé explicitement.

**Contrôle de cohérence croisée proposé :**
- Chaque `rapportsRef` d'un bilan doit résoudre vers un identifiant présent dans `rapports` ou dans `archives`.
- Chaque `cheval_id` référencé par un rating ELO doit exister dans le référentiel.
- Chaque `semainesRef` d'un bilan de mois doit exister.
- Chaque `chemin` du manifeste d'archives doit exister comme bloc ou fichier.

## L.4 Versionnement

**Deux numéros distincts, à ne pas confondre :**

| Numéro | Portée | Rôle |
|---|---|---|
| `versionFormat` | **Le conteneur** | Comment lire l'enveloppe (en-tête, blocs, compression) |
| `versionSchema` | **Chaque bloc** | Comment interpréter le contenu du bloc |

**Pourquoi les séparer** : le format peut rester stable alors qu'un bloc évolue (ajout d'un champ). Inversement, un bloc peut rester stable alors que le format change. Confondre les deux oblige à incrémenter un numéro global pour un changement local — ce qui rend toute compatibilité illisible.

**[DÉMONTRÉ] Le défaut actuel** : `backup_service.dart` lit `data['version']` (ligne 1850) dans une variable `backupVer`, et ne l'utilise **que pour l'affichage** (ligne 1941). **Il n'existe aucune comparaison avec `_backupVersion`.** La version est donc décorative. C'est ce qui doit changer.

**Règle proposée** : la version est **lue, comparée, et son écart produit un comportement explicite** :
- `versionFormat` inconnu → refus, message clair
- `versionFormat` plus ancien → chemin de compatibilité nommé
- `versionFormat` plus récent → refus explicite (« sauvegarde produite par une version plus récente »)
- `versionSchema` d'un bloc plus ancien → lecture avec complétion à valeur nulle (jamais par suppression — voir C.2)
- `versionSchema` d'un bloc plus récent → refus de ce bloc seul, les autres restent restaurables

## L.5 Compression adaptée par type

**[MESURÉ]** Ratio mesuré sur des données réalistes : **5,51 : 1** (scores variés). Sur des données artificiellement répétitives : **70,02 : 1**. Le premier est le seul utilisable dans une projection.

| Bloc | Compressibilité attendue | Choix |
|---|---|---|
| `config` | Faible (petit, texte) | Compression rapide |
| `elo` | **Forte** (nombres, structures répétées) | Compression standard |
| `pronostics` | Moyenne (déjà mesuré) | Compression standard |
| `rapports` | Moyenne | Compression standard |
| `bilans` | Très forte (agrégats + listes d'identifiants) | Compression standard |
| `journal` | Moyenne | Compression standard |
| `financier` | Faible | Compression rapide |
| `faits` | **Forte** (structuré, répétitif) | Compression standard |
| `archives` | **Déjà compressé** | **Ne pas recompresser** |

**Point important** : recompresser un contenu déjà compressé fait perdre du temps sans gain, et peut même augmenter la taille. Les segments d'archives **ne sont pas recompressés**, seulement emballés.

## L.6 Compatibilité avec les anciennes sauvegardes

**[MESURÉ]** Les deux sauvegardes réelles sont en **version 9.0**, format JSON unique, 14 clés racine, valeurs IA enveloppées `{type, value}`.

**Exigence** : ces fichiers doivent rester lisibles. Un chemin de lecture dédié est nécessaire.

| Format | Reconnaissance | Traitement |
|---|---|---|
| JSON v9.0 / v9.1 (actuel) | Pas de magie `PTG1`, clés `ia`/`configIA`/… | **Adaptateur de lecture** : convertir vers le modèle interne |
| `.ptg` v2 | Magie `PTG1` | Lecture directe |

**Ce que l'adaptateur doit gérer, explicitement :**
1. **Les valeurs enveloppées** `{type, value}` — désenvelopper.
2. **Les rapports en chaînes JSON** dans `ia_rapports_v1` — décoder.
3. **Les bilans avec copies intégrales** — extraire les rapports, les dédupliquer par empreinte normalisée, **conserver les 24 orphelins** (C.4).
4. **`ia_archive_v1_manifest` absent** — c'est normal en v9.0 (l'archive date de v9.1). **Ce n'est pas une erreur.**
5. **Les 6 divergences `fnum2`** — conserver les deux versions, ne pas fusionner (C.5).

## L.7 Ce que la sauvegarde ne doit pas faire

| Interdit | Motif |
|---|---|
| Sauvegarder les caches | Recalculables ; gonfle le fichier sans connaissance |
| Sauvegarder le répertoire temporaire | Aucune connaissance n'y réside (E.4) |
| Écrire directement sur le fichier cible | Non atomique — la troncature détruit la sauvegarde précédente (DF-11 actuel) |
| Compresser un contenu déjà compressé | Perte de temps, gain nul ou négatif |
| Faire confiance à un compteur estimé | **[DÉMONTRÉ]** `nbPronosticsIA = (gz.length / 130).round()` est une **estimation**, pas un comptage (DF-09) |
| Supposer la sauvegarde valide parce que `setString` a répondu `true` | `true` signifie « écrit », pas « relisible » |

**Sur ce dernier point [DÉMONTRÉ]** : le code contient déjà une distinction soignée entre `setString → true` et `setString → false` (`elo_service.dart:1004-1018`, `1015`, `1018`). C'est une bonne pratique existante. Mais elle ne prouve pas que le contenu écrit est **relisible et cohérent**. Seule une **relecture de vérification** le prouve.

**Proposition** : après écriture d'un export, **relire l'en-tête et vérifier l'empreinte globale**. Si elle ne correspond pas, l'export est déclaré invalide et signalé. Une sauvegarde non vérifiée n'est pas une sauvegarde.
---

# M. RESTAURATION SÉCURISÉE

Cette section traite le point **14** de votre consigne.

## M.1 Le défaut actuel, mesuré

**[DÉMONTRÉ]** La restauration actuelle est régie par une règle unique : **« clé absente → local préservé »**. Il n'existe ni comparaison de version, ni checksum, ni validation croisée, ni rollback.

**Ce que cela donne dans trois cas concrets :**

| Cas | Comportement actuel | Problème |
|---|---|---|
| Sauvegarde ancienne, base locale récente | Les clés présentes sont **écrasées** | **Perte silencieuse** des connaissances plus récentes |
| Sauvegarde corrompue en fin de fichier | Les blocs lus avant la corruption sont **appliqués** | **État partiel** — moitié restauré, moitié non |
| Sauvegarde d'une version future | Restauration tentée quand même | Comportement imprévisible |

**Votre consigne est exacte** : *« Ne suppose pas que la présence de gardes sur certaines clés garantit une restauration intégralement sûre. »* Les gardes actuelles garantissent seulement qu'une clé **non présente** n'efface rien. Elles ne garantissent rien sur les clés **présentes et écrasantes**.

## M.2 Les trois stratégies de résolution — et leurs conséquences

Toute restauration doit trancher, pour chaque entité, entre trois comportements. Il faut les **nommer** et les **choisir**, pas les subir.

| Stratégie | Effet | Risque | Usage proposé |
|---|---|---|---|
| **R — Remplacement** | Le contenu de la sauvegarde remplace le local | Perte du local plus récent | Unités **immuables** (fait officiel, archive) |
| **F — Fusion** | Union des deux ensembles, par identité | **Duplication si l'identité est mal définie** | Entités **accumulatives** (rapports, faits, journal) |
| **P — Préservation** | Le local reste, la sauvegarde est ignorée | Le local ne bénéficie pas de la restauration | **Connaissances apprises (F3)** — sauf demande explicite |

**Règle proposée par catégorie** :

| Catégorie | Stratégie | Motif |
|---|---|---|
| Faits PMU | **F — fusion** | Un fait est accumulatif ; identité par clé naturelle (B.3) |
| Rapports | **F — fusion par empreinte** | C.5 : ne fusionner que ce qui est prouvé identique |
| Versions de rapport | **F — fusion** | Deux versions distinctes coexistent (F-2) |
| Bilans | **F — fusion** | Agrégats identiques → un seul ; différents → **signaler**, ne pas écraser |
| Ratings ELO | **R ou F selon choix** | Voir M.3 — **c'est le point le plus délicat** |
| Poids, seuils (F3) | **P — préservation par défaut** | Écraser les poids acquis par une restauration serait une régression de l'apprentissage |
| Pronostics | **F — fusion** | Un pronostic passé n'est pas modifié par une restauration |
| Journal | **F — fusion** | Ajout seul par nature |
| Tickets / financier | **F — fusion** | Ne jamais perdre un ticket |
| Config, profil, alertes | **R — remplacement** | C'est le but d'une restauration de paramètres |
| Archives | **F — fusion** | Immuable : un segment identique ne doit pas être dupliqué |
| Caches | **Exclus** | Recalculables |

**Le cas des poids F3 est celui qui demande le plus d'attention.** Restaurer des poids plus anciens **défait un apprentissage**. C'est une opération lourde de conséquence, qui doit être **explicite et confirmée**, jamais le résultat silencieux d'une restauration.

## M.3 Le cas ELO — trois options à trancher

Restaurer un rating ELO n'est pas neutre : cela change les prédictions futures.

| Option | Comportement | Conséquence |
|---|---|---|
| **E-1** | Fusion : on garde le rating de `nb_courses` le plus élevé | Le plus informé gagne — cohérent avec la logique ELO |
| **E-2** | Fusion : on garde le plus récent (`date_maj`) | Le plus à jour gagne |
| **E-3** | Remplacement total | La sauvegarde fait foi — simple, mais destructeur |

**Recommandation** : **E-1**. Un rating calculé sur plus de courses est plus fiable ; `nb` existe déjà dans la structure. Mais **cette recommandation ne change aucune formule** — elle choisit seulement quelle valeur conserver quand deux existent.

**Décision D-24** : stratégie de résolution ELO. **Non tranchée.**

## M.4 La restauration doit être transactionnelle

**Exigence** : une restauration réussit entièrement, ou ne change rien.

**Mécanisme proposé — copie de sécurité préalable, puis validation, puis bascule :**

```
1. VÉRIFIER l'espace libre   → si insuffisant : échec propre, RIEN n'a changé
2. LIRE l'en-tête             → magie, version, inventaire
3. VÉRIFIER l'empreinte globale
4. VÉRIFIER chaque bloc       → empreinte par bloc
5. VÉRIFIER la cohérence croisée (L.3, niveau 3)
   → si l'une de ces étapes échoue : ÉCHEC PROPRE, RIEN n'a changé
6. SAUVEGARDER l'état local   → copie de retour arrière
7. APPLIQUER en une transaction
   → si échec en cours : ROLLBACK vers l'état de l'étape 6
8. RELIRE et vérifier         → cohérence de l'état restauré
9. CONSERVER la copie de retour arrière pendant N jours, puis la supprimer
```

**Ce que ce déroulé garantit** : à aucun moment un état partiel n'est visible. Les étapes 1 à 5 sont **en lecture seule** — elles ne modifient rien. L'étape 6 crée le filet. L'étape 7 est atomique.

**Point critique** : l'étape 6 consomme **l'espace d'une sauvegarde complète**. Sur 372 Mo de connaissances, il faut donc ≈ 372 Mo libres pour la copie de retour arrière, plus l'espace de travail. C'est la contrainte d'espace la plus lourde de tout le système, et elle doit être vérifiée à l'étape 1.

## M.5 Gestion des interruptions et du manque d'espace

| Situation | Comportement proposé |
|---|---|
| Espace insuffisant **avant** de commencer | **Refus immédiat**, message indiquant l'espace requis et l'espace disponible |
| Espace épuisé **pendant** l'écriture | Écriture dans un `.tmp` : échec propre, `.tmp` supprimé, fichier cible **intact** |
| Interruption (application tuée, batterie vide) **pendant l'export** | `.tmp` orphelin ; au démarrage suivant, **détection et suppression** des `.tmp` orphelins |
| Interruption **pendant la restauration** | La transaction SQLite garantit l'atomicité ; au redémarrage, la base est dans l'état d'avant ou d'après, jamais entre les deux |
| Fichier de sauvegarde tronqué | Détecté par l'empreinte globale → **refus**, message explicite |
| Version de format plus récente | **Refus**, message explicite |

**Le `.tmp` orphelin est un vrai risque** : sans nettoyage, chaque échec consomme de l'espace définitivement, ce qui rend l'échec suivant plus probable. C'est un cercle vicieux. **Le nettoyage au démarrage est donc obligatoire, pas optionnel.**

## M.6 Prévention des pertes de données — les cinq règles

1. **Aucune écriture destructive sur l'état courant sans filet.** La copie de retour arrière est obligatoire avant toute restauration.
2. **Aucune suppression de connaissance sans confirmation explicite.** Les 24 orphelins sont la démonstration de ce qu'une suppression « logique » peut détruire.
3. **Toute opération multi-magasins est coordonnée.** Base + archives doivent rester cohérentes : si l'on restaure la base sans les archives, les références deviennent mortes (L.3, niveau 3).
4. **Un `.tmp` n'est jamais un état valide.** Rien ne lit un `.tmp`.
5. **L'espace libre est vérifié avant toute opération de volume.** Jamais pendant, jamais après.

**Sur la règle 3 — c'est la plus difficile** : sauvegarde et restauration touchent plusieurs magasins. Si la base est restaurée mais pas les archives, les `rapportsRef` pointent dans le vide. Il faut donc :
- soit **embarquer les archives dans le fichier de sauvegarde** (ce que propose L.2),
- soit **refuser une restauration partielle** quand des références croisées existent.

Le choix est **D-25**. **Non tranché.**

---

# N. MIGRATION SÉCURISÉE VERS LA FUTURE ARCHITECTURE

Cette section traite le point **15** de votre consigne.

## N.1 Principe : la migration est une lecture, pas une transformation destructrice

**Règle absolue** : la migration lit les données existantes et les écrit dans la nouvelle structure. **Elle ne modifie ni ne supprime les données d'origine.**

Cela donne un **filet de sécurité structurel** : si la migration échoue ou produit un résultat douteux, les données d'origine sont toujours là.

## N.2 Les cinq étapes

```
1. EXTRAIRE    lire toutes les sources existantes, sans les modifier
               → SharedPreferences (14 clés racine, 44 clés ia_*)
               → les deux sauvegardes réelles si l'utilisateur les fournit
2. IDENTIFIER  construire les identités (B.3, B.4)
               → rapports : par empreinte de contenu normalisé
               → chevaux  : identifiant fournisseur, sinon composite
3. UNIFIER     union de toutes les sources, sans arbitrage entre elles
               → rapports = collection ∪ semaines ∪ mois   (les 24 orphelins entrent ici)
               → faits    = tout ce qui est disponible
4. CONTRÔLER   vérifier avant d'écrire
               → nombre de rapports avant/après
               → les 24 orphelins sont présents
               → aucune référence morte
               → les sommes d'agrégats sont inchangées
5. ÉCRIRE      dans la nouvelle structure, en transaction
               → l'ancienne structure reste intacte
```

**L'étape 4 est celle qui décide si la migration est acceptée.** Sans elle, on ne sait pas ce qu'on a fait.

## N.3 Les contrôles obligatoires, chiffrés

| Contrôle | Attendu sur les données réelles | Si l'écart |
|---|---|---|
| Nombre de contenus de rapports après normalisation | **219** **[MESURÉ]** | Écart → migration refusée |
| Nombre de contenus de rapports bruts | **225** **[MESURÉ]** | Écart → migration refusée |
| Rapports présents uniquement dans les bilans | **24** **[MESURÉ]** | Manquants → migration refusée |
| Rapports de la collection principale | **195** **[MESURÉ]** | Écart → migration refusée |
| Copies totales de rapports | **524** **[MESURÉ]** | Écart → expliquer avant de poursuivre |
| Somme des agrégats par bilan | Identique avant/après | Écart → migration refusée |
| Nombre de ratings ELO | Mesurer d'abord **[À VÉRIFIER]** | Écart → expliciter |
| Poids F3 | Somme = 1,2600000000 **[DÉMONTRÉ]** | Écart → migration refusée |
| Aucune référence morte | 0 | > 0 → migration refusée |

**Ces chiffres sont des garde-fous réels.** Ils ont été mesurés sur la sauvegarde du 13/11/2026. Une migration qui ne les reproduit pas est une migration qui a perdu quelque chose.

**Point d'honnêteté** : ces valeurs sont valables **pour cette sauvegarde**. Une autre sauvegarde aura d'autres valeurs. Le contrôle doit donc être **relatif** : comparer avant/après sur le même corpus, et non comparer à un chiffre fixe.

## N.4 La migration doit être rejouable

**Exigence** : pouvoir recommencer sans dommage.

**Mécanisme** : la migration produit un **rapport de migration** (fichier, non une connaissance) contenant :
- les sources lues et leurs empreintes
- les comptes avant / après
- la liste **nominative** des 24 orphelins promus
- la liste des versions de rapports conservées
- les anomalies rencontrées
- la décision finale : acceptée ou refusée

**Si une anomalie est détectée**, le fichier de migration reste **en quarantaine** : écrit, mais **non activé**. L'ancienne structure continue de servir. C'est ce qui permet de migrer sans risque.

## N.5 Ce que la migration ne doit pas faire

| Interdit | Motif |
|---|---|
| Supprimer les données d'origine | Détruit le filet de sécurité |
| Arbitrer entre deux sources de rapports | Perd les 24 orphelins (C.4) |
| Fusionner deux chevaux sans preuve d'identité | Corrompt tous les ratings (B.4) |
| Recalculer les poids, l'ELO ou les seuils | **Modifierait l'apprentissage** — §36 |
| Recalculer les agrégats de bilans | Inutile et risqué (K.4) |
| Activer la nouvelle structure sans avoir passé les contrôles | Aucun retour possible |

## N.6 Migration des sauvegardes existantes

**[MESURÉ]** Les deux sauvegardes (28/05 : 2 386 883 o ; 13/11 : 12 293 558 o) sont en version 9.0.

**Traitement proposé :**
1. Les deux sont **lisibles** par l'adaptateur (L.6).
2. Elles servent de **corpus de contrôle** : la migration doit reproduire 219 / 225 / 24.
3. Elles ne sont **pas modifiées** — jamais.
4. La sauvegarde du 28/05 sert de **test de compatibilité ascendante** : une version plus ancienne du même format doit rester lisible.

## N.7 Phasage de la migration

| Phase | Contenu | Retour possible ? |
|---|---|---|
| **N-A** | Lecture seule : extraire, identifier, compter | Oui, trivialement — rien n'est écrit |
| **N-B** | Écriture dans la nouvelle structure, **sans basculer** | Oui — l'ancienne sert toujours |
| **N-C** | Contrôles de N.3 | Oui |
| **N-D** | Bascule de lecture vers la nouvelle structure | Oui — retour à l'ancienne en changeant un paramètre |
| **N-E** | L'ancienne structure n'est plus lue, mais **conservée** | Oui |
| **N-F** | Suppression de l'ancienne structure | **Non** — jamais fait dans ce chantier |

**Le phasage est conçu pour que chaque étape soit réversible jusqu'à N-E.** La phase N-F n'est **pas proposée** dans ce chantier : elle relèverait d'une décision ultérieure, après une période d'observation.
---

# O. GESTION DES NOUVELLES DONNÉES ET DES CORRECTIONS OFFICIELLES

Cette section traite les points **16** et **10** de votre consigne.

## O.1 Les quatre natures de correction — à ne jamais confondre

Votre consigne en distingue quatre. Elles n'ont ni la même gravité, ni le même traitement.

| # | Nature | Exemple | Gravité | Réversible ? |
|---|---|---|---|---|
| **C-1** | Correction d'un **fait hippique officiel** | Une arrivée officielle rectifiée après réclamation ; un cheval déclaré non-partant après coup ; un `etatTerrain` corrigé | **Haute** — le fait de base change | Oui, si l'historique est conservé |
| **C-2** | Correction des **statistiques dérivées** | Le taux de victoire d'un cheval change parce qu'un résultat a été rectifié | **Moyenne** — conséquence mécanique de C-1 | Oui, par recalcul |
| **C-3** | Correction des **conséquences sur l'apprentissage** | Un rating ELO a été calculé sur un résultat erroné | **Très haute** — touche F3 | **Non** sans rejouer l'historique |
| **C-4** | Conséquences **financières** | Un ticket réglé sur un résultat erroné | **Variable** | Dépend d'une décision humaine |

**Le point que votre consigne souligne** : *« Ne propose pas de conserver définitivement un fait officiel erroné. »* C'est donc explicitement écarté : un fait erroné doit pouvoir être corrigé, et le fait d'origine conservé comme historique de la correction (K.5).

## O.2 Ce que la structure doit permettre

| Exigence | Réponse |
|---|---|
| Corriger un fait | Journal de corrections (K.5) + version du fait |
| Conserver l'état d'origine | Oui — le segment d'archive n'est jamais réécrit |
| Recalculer ce qui en dépend | Oui — par invalidation de dépendances (F.2) |
| **Ne pas recalculer ce qui n'en dépend pas** | Oui — périmètre minimal (F.3) |
| Ne pas corriger l'apprentissage silencieusement | **Les poids et l'ELO ne sont pas recalculés automatiquement** |

## O.3 Le cas C-3 — la conséquence sur l'apprentissage

C'est le point le plus délicat, et celui qui touche §36.

**Situation** : un résultat officiel erroné a été utilisé par l'apprentissage. Les poids ont été ajustés sur une base fausse. Le rating ELO d'un cheval a été modifié.

**Que peut-on faire ?** — Trois options, avec leurs conséquences :

| Option | Description | Conséquence | Statut §36 |
|---|---|---|---|
| **A-1** | **Ne rien faire** — les poids et ratings restent tels quels | L'erreur persiste dans F3, mais aucun mécanisme n'est touché | **Compatible** |
| **A-2** | **Marquer** les faits erronés, sans recalculer | L'erreur est traçable ; les poids restent | **Compatible** |
| **A-3** | **Rejouer** l'apprentissage sur les données corrigées | Les poids seraient différents — mais c'est **recalculer** l'apprentissage | **Incompatible** — touche le gradient |

**Recommandation** : **A-2**. Marquer, tracer, ne pas recalculer.

**Motif** : rejouer le gradient (A-3) serait modifier le mécanisme d'apprentissage — interdit. Et il serait de toute façon impossible à faire proprement, car les données `scoresCriteres` ne sont conservées que sur **5 pronostics sur 600** [MESURÉ] : le corpus de rejeu n'existe pas.

**Ce que A-2 implique concrètement :**
- Le fait corrigé porte un marqueur `corrige: true` avec sa date et sa raison.
- Les statistiques dérivées (F2) sont recalculées — elles, sont recalculables.
- Les poids (F3) **ne sont pas touchés**.
- L'interface peut signaler : « ce bilan repose en partie sur un fait corrigé le … ».

**C'est la seule option honnête** : elle ne prétend pas que l'apprentissage est intact, elle rend l'erreur **visible**.

**Décision D-26** : politique de traitement de C-3. **Non tranchée.**

## O.4 Le cas C-4 — conséquences financières

**[DÉMONTRÉ]** Il existe des données financières : `paris`, `grosParis`, tickets.

**Ce que ce rapport peut affirmer** : la structure doit permettre de **retrouver** qu'un ticket a été réglé sur un fait ultérieurement corrigé. Elle ne peut pas décider de ce qu'il faut faire ensuite — c'est une décision humaine, hors du périmètre technique.

**Proposition minimale** : conserver, sur chaque ticket, l'**identifiant du fait** sur lequel il a été réglé. Cela rend la détection possible sans modifier le mécanisme de règlement.

## O.5 Nouvelles données — le cas général

| Type de nouveauté | Traitement |
|---|---|
| **Nouvelle course** | Ajout de faits F1 ; aucun recalcul d'historique |
| **Nouveau champ dans le flux PMU** | Ajout de colonne, nullable ; pas de recalcul rétroactif |
| **Nouveau cheval** | Création d'entité ; résolution d'identité (B.4) |
| **Nouvelle discipline** | `normaliseDiscipline()` la ramènerait sur `global` **[DÉMONTRÉ]** — à surveiller : c'est le chemin du repli silencieux (D.2.2) |
| **Nouveau type de pari** | Ajout dans les données financières ; aucun effet sur les 19 critères |
| **Changement de format PMU** | Risque de rupture — [À VÉRIFIER] à chaque évolution du flux |

**Le cas « nouvelle discipline » mérite une attention particulière** : `ia_memory_models.dart:682` retourne `'global'` pour toute discipline non reconnue. Une nouvelle discipline serait donc silencieusement traitée avec les poids racine, **sans que rien ne le signale**. C'est le même défaut que celui identifié en D.2.2 — et il s'aggraverait avec une discipline nouvelle.

**Correction proposée, sans toucher au calcul** : rendre le repli **visible** (indicateur de provenance), sans changer la valeur produite. **D-27**, **non tranchée**.

---

# P. PRÉSERVATION INTÉGRALE DES MÉCANISMES D'APPRENTISSAGE

Cette section traite le point **17** de votre consigne. Elle est la section la plus contrainte : **rien ne doit changer**.

## P.1 Ce qui ne change pas — inventaire explicite

Les éléments suivants sont **intouchés** par cette révision. La liste est exhaustive par rapport aux mécanismes identifiés dans le chantier.

| Mécanisme | Localisation | Ce qui ne change pas |
|---|---|---|
| Formule des 19 critères | `ia_pronostic_engine.dart:_calculerScoreBrutEtCriteres` | Aucun score, aucune source de score |
| Score brut | `Σ score_c × poids_c` **sans division** | La formule elle-même |
| Normalisation des scores | `_normaliserScores`, seuils `< 3`, `range <= 1.0`, ratios 0,40 / 0,60 / 0,75 | Tous les seuils |
| Gradient | `_apprendreParGradient` : ≥ 10 courses avec résultats, ≥ 3 avec `scoresCriteres`, fenêtre 45 j (90 si insuffisant), `take(50)` | Toutes les conditions |
| Taux d'apprentissage | `lrBase = 0.08`, `lrFactor = min(1, n/20)`, `stabilisationFactor` 0,3 si `< 30`, `momentumFactor = 0.3` | Toutes les valeurs |
| Facteurs par critère | 1,0 / 0,5 / 0,4 / 0,3 | Tous |
| Gel | `n >= 50` **et** `r >= 0.85` | La condition |
| Apprentissage par discipline | `_apprendreParDiscipline` : `take(20)`, `nbDisc < 5 → return`, `totalBons < 3 || totalMauvais < 3 → return` | Toutes les bornes |
| `clampDiscipline` | Bornes par critère, comportement de compléteur | Toutes les bornes |
| `normaliser` | `targetEnrichi = fractionEnrichi.clamp(0.18, 0.40)` | Les bornes |
| Poids par défaut | Somme 1,2600000000 | Tous |
| TOP3 Learning | Mécanisme, seuils, déclencheurs | **Rien** |
| Seuils et calibration | `ia_seuils_v1` | Toutes les valeurs |
| ELO — formule | Calcul des espérances, mise à jour | **Rien** |

## P.2 Ce que la révision touche — et pourquoi ce n'est pas l'apprentissage

**La distinction est essentielle, et elle doit être dite clairement :**

| Ce qui change | Est-ce un mécanisme d'apprentissage ? |
|---|---|
| **Où** les poids sont stockés (SharedPreferences → base ou fichier) | **Non** — c'est le support |
| **Comment** ils sont lus (chargement intégral → lecture ciblée) | **Non** |
| **Quand** ils sont écrits (à chaque `_save` → seulement quand ils changent) | **Non** |
| **Quelles valeurs** ils prennent | **OUI — et cela ne change pas** |
| **Comment** ils sont calculés | **OUI — et cela ne change pas** |

**Formulation rigoureuse** : cette révision change le **support** et le **mode d'accès** de F3, jamais son **contenu** ni son **calcul**.

**Le risque à ne pas sous-estimer** : même sans changer la formule, un changement de support peut changer le comportement **si** une valeur est arrondie différemment lors de la sérialisation. Un flottant écrit en JSON et relu doit être identique bit à bit, ou les poids dériveraient imperceptiblement à chaque cycle.

**[DÉMONTRÉ]** Ce risque est réel : les poids sont des `double`. Le JSON de Dart sérialise les doubles avec une précision suffisante pour un aller-retour exact, **mais cela doit être vérifié par un test**, pas supposé.

**[À VÉRIFIER] — test obligatoire avant migration** : écrire puis relire les 19 poids de chacune des 4 disciplines, et vérifier l'égalité **exacte** (pas approximative). Si un écart apparaît, la migration est refusée.

## P.3 Versionnement des poids — condition de préservation

**Problème à résoudre** : si les poids changent au fil du temps, un pronostic passé a été calculé avec les poids de son époque. Comment le savoir après coup ?

**Ce qui existe [DÉMONTRÉ]** : `scoresCriteres` est conservé sur les pronostics — mais seulement sur **5 pronostics sur 600** au 13/11 (47 sur 572 au 28/05). Le corpus est donc **quasiment vide**.

**Ce que cela implique** : sans conservation des poids par époque, un pronostic ancien ne peut pas être **expliqué**. Il peut être relu, mais pas justifié.

**Proposition — sans changer l'apprentissage** : conserver, à chaque modification des poids, une **empreinte datée** de `ia_poids_v3` (et non une copie complète). Cela permet de savoir **quelle version** a produit quel pronostic, sans stocker 19 × 4 doubles par pronostic.

| Option | Coût | Ce que cela permet |
|---|---|---|
| Copie complète des poids par époque | 3,9 Ko par version | Relecture exacte |
| **Empreinte + version** | 32 octets par version | **Savoir quelle version**, pas la relire |
| Empreinte + copie des seules versions majeures | Compromis | Les deux, partiellement |

**Recommandation** : empreinte + copie des versions majeures. **Décision D-28**, non tranchée.

## P.4 Ce que la révision ne doit jamais faire

1. **Recalculer les poids** lors d'une migration (N.5).
2. **Rejouer le gradient** pour corriger une erreur (O.3, option A-3).
3. **Écraser les poids acquis** par une restauration (M.2, stratégie P).
4. **Modifier un seuil** pour « améliorer » un résultat.
5. **Changer la sémantique d'un critère** en corrigeant son alimentation sans validation (D.2, D-13 à D-16).
6. **Recalculer un pronostic passé** avec les poids actuels (F.3).

## P.5 Le point de contradiction à assumer

**Il y a une tension réelle, et il faut la nommer plutôt que la masquer.**

Plusieurs corrections d'alimentation proposées en section D (`gains`, `progression`, `record`, `placeDepart`) **changent la valeur** que reçoit un critère. Or un critère dont la valeur change produit des poids différents au prochain apprentissage — et donc, à terme, un comportement différent.

**Est-ce une modification de l'apprentissage ?** **Techniquement non** : le mécanisme est identique, seule son entrée change. **Pratiquement oui** : le résultat de l'apprentissage sera différent.

**Position de ce rapport, sans détour** : ces quatre corrections sont **nécessaires** (deux d'entre elles suppriment des données fabriquées ou des sentinelles indistinguables) mais elles **ne sont pas neutres**. Elles doivent donc être :
- **validées explicitement** (D-10, D-13, D-15, D-16),
- **appliquées séparément**, une par une, pour que l'effet de chacune soit observable,
- **précédées d'une mesure** de l'état actuel, pour pouvoir comparer.

**Prétendre qu'elles sont sans effet serait malhonnête.** Elles améliorent l'honnêteté de la donnée et changent le comportement de l'IA. Les deux sont vrais.
---

# Q. FUTURE RÉINITIALISATION — DISTINGUER CE QUI EST CONSERVÉ

Cette section traite le point **18** de votre consigne.

## Q.1 Ce qui est décidé, et ce qui ne l'est pas

**Décidé** : la politique définitive de réinitialisation **reste reportée**. Aucune réinitialisation n'est proposée, planifiée, ni recommandée dans ce chantier.

**Non décidé** — et c'est votre exigence explicite : **la conservation ou la suppression de l'ELO lors d'une future réinitialisation n'est PAS validée.** Ce rapport ne la tranche pas.

**Ce que cette section apporte** : la **grille de distinction** qui rendra la décision possible, quand elle sera prise. C'est tout. Pas de recommandation.

## Q.2 La grille — cinq catégories à ne jamais confondre

| # | Catégorie | Nature (rappel B.1) | Reconstituable ? | Perte si supprimé |
|---|---|---|---|---|
| **Q-a** | **Connaissances hippiques authentiques** — faits PMU (courses, participations, résultats, terrain, corde, poids) | **F1** | **Oui**, si le PMU les expose encore. **Non** si l'historique n'est plus rediffusé | Définitive si le PMU ne les redonne pas |
| **Q-b** | **Observations locales** — ce que l'application a vu et que le PMU ne conserve pas (composition complète d'une course au moment où elle était connue, cotes à un instant précis) | **F1** (mais locale) | **Non** — non rediffusé | **Définitive** |
| **Q-c** | **Ratings ELO** | **F3** | **Non** sans rejouer l'historique complet des courses et des adversaires | Définitive — des années de courses |
| **Q-d** | **Poids et seuils de l'IA** | **F3** | **Non** sans rejouer le gradient sur un corpus qui n'existe plus (5/600) | Définitive |
| **Q-e** | **Expérience acquise par l'apprentissage** — tout ce qui résulte des passages du gradient : calibration, seuils ajustés, variantes par discipline | **F3** | **Non** | Définitive |

## Q.3 Ce que la grille rend visible

**Le point essentiel** : **Q-a et Q-b sont de la connaissance du monde ; Q-c, Q-d et Q-e sont de la connaissance de soi.**

Une réinitialisation qui supprime Q-c/Q-d/Q-e ne supprime **aucune connaissance hippique** — elle supprime la **compétence acquise** de l'IA. L'IA redeviendrait ce qu'elle était au premier jour : capable de lire les faits, incapable d'en tirer parti comme elle l'avait appris.

**Inversement**, une réinitialisation qui supprime Q-a/Q-b détruit la matière première. L'IA garderait ses poids, mais ils ne s'appliqueraient plus à rien.

**Ces deux pertes n'ont rien de comparable, et c'est précisément pour cela que la décision ne peut pas être globale.**

## Q.4 Les combinaisons possibles, et ce qu'elles impliquent

Cette table **n'est pas une recommandation**. Elle expose les choix pour que la décision future soit informée.

| Combinaison | Ce qui est conservé | Ce qui est perdu | Effet sur l'IA |
|---|---|---|---|
| **R-0** | Tout | Rien | Aucun — statu quo |
| **R-1** | Q-a, Q-b (faits), perte de Q-c/Q-d/Q-e | ELO, poids, expérience | L'IA redevient sans compétence, mais garde la matière |
| **R-2** | Q-c, Q-d, Q-e (compétence), perte de Q-a/Q-b | Faits PMU | L'IA garde ses poids, mais n'a plus de données |
| **R-3** | Q-a, Q-c (faits + ELO), perte de Q-d/Q-e | Poids, expérience | ELO orphelin : plus aucun poids ne l'exploite |
| **R-4** | Tout sauf Q-c | ELO uniquement | L'IA se reconstruit son ELO sur ses faits conservés |
| **R-5** | Tout sauf Q-b | Observations locales | Les statistiques tronquées deviennent définitivement impossibles à compléter |

**Observation sans recommandation** : **R-5 est la seule combinaison dont la perte est irréversible pour une raison structurelle** — les observations locales (Q-b) sont, par définition, ce que le PMU ne redonne pas. Un fait PMU peut être re-téléchargé ; une cote observée à 14 h 32 un jour donné, non.

## Q.5 Ce que la structure doit permettre pour que la décision reste ouverte

Pour que la décision soit **encore possible** le jour où elle sera prise, la structure doit **séparer physiquement** les cinq catégories. Sinon, toute réinitialisation partielle serait impossible.

**Exigence architecturale qui en découle** :

| Catégorie | Support distinct ? | Motif |
|---|---|---|
| Q-a faits PMU | Base — table distincte | Doit pouvoir être vidée sans toucher F3 |
| Q-b observations locales | Base — table **distincte** de Q-a | **C'est la distinction la plus importante** : un fait rediffusé et une observation unique ne doivent pas être dans la même table |
| Q-c ELO | Base — table distincte | Doit pouvoir être conservée ou vidée indépendamment |
| Q-d poids et seuils | Config — fichiers distincts | Idem |
| Q-e expérience | Config — distincte des poids ? | **À examiner** : l'expérience est aujourd'hui diffuse dans les poids |

**Le point Q-e est le plus délicat** : aujourd'hui, l'« expérience » n'existe pas comme entité séparée — elle **est** les poids. Séparer les deux n'aurait pas de sens. La conséquence est que **Q-d et Q-e sont indissociables**, et que toute réinitialisation de l'un emporte l'autre.

**Ce fait doit être connu avant la décision**, pas découvert après.

## Q.6 Ce que cette section ne fait pas

- Elle ne recommande aucune combinaison.
- Elle ne planifie aucune réinitialisation.
- Elle ne modifie aucune politique.
- Elle ne tranche rien sur l'ELO.

Elle rend la décision **possible** en fournissant la grille et la contrainte architecturale qui la conditionne.

---

# R. COMPATIBILITÉ ANDROID — SAMSUNG, TÉLÉPHONES ET TABLETTES

Cette section traite le point **19** de votre consigne. Elle est presque entièrement composée de points **[APPAREIL REQUIS]** : c'est sa nature, pas une insuffisance.

## R.1 Le contexte technique fixé

| Élément | Valeur |
|---|---|
| Flutter | **3.35.4** |
| Dart | **3.9.2** |
| API Android cible | **35** (Android 15) |
| Build tools | **35.0.0** |
| Java | **17** (OpenJDK 17.0.2) |

Ces versions sont **gelées** et ne doivent pas être modifiées.

## R.2 Les contraintes Android qui touchent cette architecture

| Contrainte | Effet sur l'architecture | Statut |
|---|---|---|
| **Stockage interne effacé à la désinstallation** | Les connaissances seraient perdues | **Décision D-18**, non tranchée |
| **Scoped storage** (Android 10+) | L'accès au stockage externe est restreint ; le répertoire propre de l'application est accessible sans permission | **À VÉRIFIER** selon la cible |
| **Économiseur d'énergie Samsung** | Peut tuer des traitements de fond de façon agressive | **[APPAREIL REQUIS]** |
| **Gestion mémoire agressive** (One UI) | Les processus en arrière-plan sont terminés plus tôt | **[APPAREIL REQUIS]** |
| **Modes de performance** | Peuvent brider le processeur | **[APPAREIL REQUIS]** |
| **Mise en veille des applications** | Une application non utilisée est mise en veille profonde | **[APPAREIL REQUIS]** |
| **Taille d'écran variable** (téléphones, pliables, tablettes) | Interface adaptative nécessaire | **[APPAREIL REQUIS]** |
| **Sauvegarde système Android** | Peut copier les données sans contrôle | **À documenter** |

## R.3 Les points spécifiques aux appareils Samsung

**Pourquoi Samsung mérite une mention propre** : One UI applique des politiques d'économie d'énergie réputées plus strictes que l'Android de référence.

| Risque | Ce que l'architecture doit faire pour y résister | Marque |
|---|---|---|
| Traitement de fond tué brutalement | **Ne jamais dépendre d'un traitement de fond pour la cohérence des données** : écrire immédiatement les données critiques (H.2) | **[DÉMONTRÉ]** par conception |
| Écriture interrompue | Écriture atomique + nettoyage des `.tmp` au démarrage (M.5) | **[DÉMONTRÉ]** par conception |
| Mémoire contrainte sur les modèles d'entrée de gamme | Caches explicitement bornés (I.6) | **[APPAREIL REQUIS]** |
| Mise en veille profonde | Aucune dépendance à un réveil périodique (J.3) | **[DÉMONTRÉ]** par conception |
| Batterie : bridage | Mesurer M-06 sur appareil réel | **[APPAREIL REQUIS]** |

**Ce qu'il faut éviter absolument** : concevoir l'architecture en supposant que l'application peut maintenir un traitement de fond fiable. Sur Samsung comme ailleurs, ce n'est pas garanti. **Toute cohérence des données doit donc être assurée au moment de l'écriture, pas plus tard.**

## R.4 Matrice de test à constituer

| # | Gamme | Ce qui est testé | Marque |
|---|---|---|---|
| T-1 | Samsung entrée de gamme (RAM ≤ 4 Go) | Comportement mémoire, absence de `OutOfMemoryError` | **[APPAREIL REQUIS]** |
| T-2 | Samsung milieu de gamme | Fluidité, batterie | **[APPAREIL REQUIS]** |
| T-3 | Samsung haut de gamme | Fluidité, temps de démarrage | **[APPAREIL REQUIS]** |
| T-4 | Samsung tablette | Adaptation d'interface, disposition | **[APPAREIL REQUIS]** |
| T-5 | Android non-Samsung | Non-régression | **[APPAREIL REQUIS]** |
| T-6 | Android 11 (API 30) | Compatibilité ascendante | **[APPAREIL REQUIS]** |
| T-7 | Android 15 (API 35) | Cible | **[APPAREIL REQUIS]** |
| T-8 | Stockage saturé (< 1 Go libre) | Échec propre des écritures (M.5) | **[APPAREIL REQUIS]** |
| T-9 | Interruption brutale pendant une écriture | Atomicité, nettoyage des `.tmp` | **[APPAREIL REQUIS]** |

**Ce que T-8 et T-9 testent réellement** : ce ne sont pas des cas marginaux. Ce sont **exactement** les situations où une architecture non atomique détruit des données. Les 24 rapports orphelins **[MESURÉ]** montrent que ce projet a déjà subi une perte silencieuse.

## R.5 Mesures à faire sur appareil — liste consolidée

|cette liste remplace toute affirmation antérieure sur les performances.**

| # | Mesure | Ce qu'elle décidera |
|---|---|---|
| M-01 | Tas après chargement complet | Si la RAM ne croît pas avec les données |
| M-02 | Tas à 1 mois vs 12 mois | Confirme la propriété ci-dessus |
| M-03 | Temps d'un batch de 42 écritures | Si l'actualisation ELO est viable |
| M-04 | Temps de démarrage à froid | Perçu utilisateur |
| M-05 | Fluidité des listes (600 pronostics) | Saccades |
| M-06 | Consommation sur 8 h | Batterie |
| M-07 | Durée d'un export complet | Viabilité de la sauvegarde |
| M-08 | Débit d'écriture SQLite en transaction | Dimensionnement |
| M-09 | Comportement à stockage saturé | Échec propre (T-8) |
| M-10 | Comportement à interruption brutale | Atomicité (T-9) |

**Tant que M-01 à M-10 ne sont pas faites, aucune affirmation de performance sur cette architecture n'est possible.** Ces mesures seront faites au moment approprié — c'est votre consigne, et elle est juste.

---

# S. ANTICIPATION — AGENT IA INDÉPENDANT ET SYNCHRONISATION ENTRE APPAREILS

Cette section traite le point **20** de votre consigne. Elle est **anticipatoire** : elle ne conçoit pas ces fonctions, elle vérifie que l'architecture proposée ne les rendra pas impossibles.

## S.1 L'agent IA indépendant

**Ce qu'il suppose** : un composant capable de raisonner sur les connaissances **sans passer par l'interface de l'application**.

**Ce que l'architecture proposée doit garantir pour le permettre :**

| Exigence | Satisfaite par | Pourquoi c'est nécessaire |
|---|---|---|
| Connaissances accessibles sans l'interface | Couche commune (E.1) | Un agent ne peut pas passer par un écran |
| Accès **ciblé**, pas global | Index (H.3) | Un agent doit requêter, pas tout charger |
| Séparation faits / apprentissage | B.1 (F1/F2/F3) | Un agent doit savoir ce qu'il peut recalculer |
| Registre de politiques | C.6 | Un agent doit connaître les règles de rétention |
| Provenance de chaque valeur | Section T | Un agent doit pouvoir citer sa source |
| Aucun accès direct au support physique | Couche d'abstraction (E.1) | Un agent peut tourner sur un autre support |

**Point d'honnêteté** : cette architecture **prépare** un agent indépendant. Elle ne le **crée** pas et ne dit rien de son intelligence. Dire qu'elle « permet un agent IA » serait une affirmation non démontrée. Ce qui est démontré est plus modeste : **elle ne l'empêche pas**, ce qui n'est pas la même chose.

## S.2 La synchronisation entre appareils

**Ce qu'elle suppose** : deux instances de l'application, sur deux appareils, avec des connaissances **partiellement communes**.

**Le problème central, et il est sérieux** : si deux appareils enregistrent des faits différents, ou modifient le même rating, **comment réconcilier ?**

**Ce que l'architecture doit garantir :**

| Exigence | Réponse dans cette architecture | Suffisant ? |
|---|---|---|
| Identité stable des entités | B.4 — **mais non résolue** | **Non** — sans identifiant fiable, la synchronisation est impossible |
| Horodatage des faits | Oui | Oui |
| Conservation des versions | Oui — section C | **Oui, et c'est essentiel** |
| Résolution des conflits | **Non traitée** | **Non** |
| Fusion sans perte | Oui — M.2 | Oui |
| Chiffrement en transit | **Non traité** | **Non** |

**Le constat le plus important, et il est négatif** : **la synchronisation entre appareils est impossible sans identifier le cheval de façon stable.** Deux appareils qui nomment le même cheval `NOM|DISCIPLINE` ne peuvent pas savoir qu'il s'agit du même animal si l'un a enregistré `AVALON|PLAT` et l'autre `AVALON|OBSTACLE_HAIE`.

**Cela fait de B.4 (identité du cheval) un prérequis de la synchronisation, et non un détail.** C'est une conclusion de conception, pas une mesure.

## S.3 Ce que l'architecture doit réserver dès maintenant

Même sans concevoir la synchronisation, certains choix sont **irréversibles** et doivent être faits maintenant :

| Réservation | Coût aujourd'hui | Coût si omise |
|---|---|---|
| **Identifiant interne stable par entité** | Faible — une colonne | **Refonte complète** |
| **Horodatage de création et de modification** | Faible | Reconstruction impossible |
| **Identifiant d'origine** (quel appareil a créé l'entité) | Faible — un champ | Conflits insolubles |
| **Compteur de version par enregistrement** | Faible | Écrasement silencieux |
| **Journal de corrections** (K.5) | Faible | Historique des modifications perdu |

**Ces cinq réservations sont peu coûteuses et rendent la synchronisation possible plus tard.** Les omettre la rendrait très coûteuse à rattraper. C'est le seul point de cette section qui mérite d'être décidé **maintenant**.

**Décision D-29** : intégrer ces cinq réservations au schéma dès la migration. **Non tranchée** — mais les omettre serait une décision, et une mauvaise.

## S.4 Ce que cette section ne fait pas

- Elle ne conçoit pas l'agent IA.
- Elle ne conçoit pas le protocole de synchronisation.
- Elle ne traite pas le chiffrement.
- Elle n'affirme pas que la synchronisation fonctionnera.

Elle identifie **un prérequis bloquant** (identité du cheval) et **cinq réservations à faible coût** à faire dès maintenant.
---

# T. TABLEAU CORRIGÉ DES 19 CRITÈRES

Cette section remplace le tableau final de la v1. Elle applique les six axes de D.1 aux 19 critères.

**Ce tableau ne modifie aucune formule.** Il qualifie l'alimentation, pas le calcul.

**Abréviations des axes** — P = provenance · D = disponibilité · Q = qualité d'alimentation · I = validité d'interprétation · A = applicabilité par discipline · R = comportement réel.

## T.1 Le tableau complet

| # | Critère | P — provenance | D — disponibilité | Q — qualité | I — interprétation | A — discipline | R — comportement au manque | Qualification |
|---|---|---|---|---|---|---|---|---|
| 1 | **forme** | PMU-dérivé (musique) + calcul-local | **partielle** — historique 0–5 courses (médiane 5) | **dégradée** si historique court | partielle | toutes | variable-non maîtrisée | **PARTIEL** |
| 2 | **gains** | PMU-direct (carrière) / **aucune** (dernier an) | partielle | **FABRIQUÉE** si repli 20 % actif | détournée sur « dernier an » | toutes | variable-non maîtrisée | **FRAGILE** |
| 3 | **record** | PMU-dérivé (musique → regex) | fréquente, non totale | **dégradée** — sentinelle 9999,0 | partielle (« meilleur de la musique » ≠ record de carrière) | toutes | **constante** (9999,0) | **PARTIEL** |
| 4 | **cote** | PMU-direct (direct) | **toujours en direct** | fiable | conforme | toutes | neutre-explicite | **SOLIDE** |
| 5 | **constance** | PMU-dérivé (musique) | partielle | dégradée si historique court | conforme | toutes | variable-non maîtrisée | **PARTIEL** |
| 6 | **victoires** | PMU-dérivé (`nbVictoiresRecentes`, 6 dernières) | partielle | dégradée si historique court | conforme | toutes | neutre-implicite | **PARTIEL** |
| 7 | **discipline** | PMU-direct | **toujours** | fiable (réelles) / **repli silencieux** (`global`) | conforme | toutes | neutre-explicite | **PARTIEL** — voir T.2 |
| 8 | **distSpec** | calcul-local (distance × musique) | partielle | conditionnelle | conforme | **non pertinent en plat** | neutre-explicite | **PARTIEL** |
| 9 | **jockey** | **calcul-local** (pas de source PMU) | **partielle — participants tronqués** | **dégradée** (échantillon incomplet) | conforme sur base incomplète | toutes | neutre-implicite | **FRAGILE** |
| 10 | **repos** | PMU-dérivé (date de dernière course) | fréquente | fiable | conforme | toutes | neutre-explicite | **SOLIDE** |
| 11 | **hippo** | calcul-local (statistiques hippodrome) | dépend de l'historique local | conditionnelle | conforme | toutes | neutre-implicite | **PARTIEL** |
| 12 | **entraineur** | **calcul-local** (pas de source PMU) | **partielle — participants tronqués** | **dégradée** + clé d'identité fragile | conforme sur base incomplète | toutes | neutre-implicite | **FRAGILE** |
| 13 | **elo** | **apprentissage** | toujours (une fois calculé) | fiable **si identité du cheval correcte** | conforme | toutes | neutre-explicite | **PARTIEL** — voir T.3 |
| 14 | **terrain** | PMU-direct (`coursesCourues[].etatTerrain`) | **38,8 %** globalement ; **1–5 % en Trot** ; 100 % Plat/Obstacle/Cross | conditionnelle → **constante (50,0) avant correction** | conforme après correction / **détournée** avant | **Trot : non** | neutre-explicite après correction | **FRAGILE en Trot / PARTIEL ailleurs** |
| 15 | **divergence** | calcul-local (écart IA ↔ marché) | toujours | fiable | conforme | toutes | neutre-explicite | **SOLIDE** |
| 16 | **poidsRel** | **PMU-direct** (`handicapPoids` ÷ 10) | **handicaps seulement** | conditionnelle mais **propre** | conforme | **Plat/Obstacle ; 50,0 en Trot** | **neutre-explicite** | **PARTIEL** (disponibilité) |
| 17 | **progression** | **aucune** aujourd'hui (repli fabriqué) | — | **FABRIQUÉE** | détournée | toutes | variable-non maîtrisée | **FRAGILE** |
| 18 | **mouvCote** | PMU-direct (cotes dans le temps) | dépend de la fenêtre de relevé | conditionnelle | conforme | toutes | **neutre-explicite** (50 = hors fenêtre) | **PARTIEL** |
| 19 | **placeDepart** | **PMU-direct** (`placeCorde`) | **[À VÉRIFIER]** | **dégradée** — sentinelle `0` | conforme (reçoit partants, type, distance) | dépend du type de départ | **variable-non maîtrisée** | **PARTIEL** |

## T.2 Décompte et comparaison avec la v1

| Qualification | v1 | **Révisé** | Ce qui a changé |
|---|---:|---:|---|
| **SOLIDE** | 5 | **3** | `elo` rétrogradé (identité du cheval non fiable) ; `poidsRel` requalifié PARTIEL |
| **PARTIEL** | 7 | **10** | Requalifications ci-dessous |
| **FRAGILE** | 3 | **5** | `gains`, `progression`, `jockey`, `entraineur`, `terrain` (Trot) |
| **INTERNE** | 4 | **0** | **L'axe « INTERNE » est supprimé** : il mélangeait provenance et fiabilité |
| **SOLIDE + PARTIEL + FRAGILE** | — | **3 + 10 + 5 = 18** | + `terrain` compté en deux qualifications selon discipline |
| **TOTAL** | 19 | **19** | 18 critères + `terrain` à double qualification = 19 lignes de tableau |

**Correction explicite de la v1** : la v1 annonçait « 5 SOLIDE + 7 PARTIEL + 3 FRAGILE + 4 INTERNE = 19 ». Cette répartition est **abandonnée** : elle utilisait un axe « INTERNE » qui confondait la provenance avec la fiabilité. Or votre consigne est explicite : *« Un critère interne n'est pas nécessairement fiable »* — donc « interne » ne peut pas être une qualification de fiabilité.

**Les quatre critères classés « INTERNE » en v1** sont aujourd'hui répartis selon leur fiabilité réelle : `jockey` et `entraineur` → **FRAGILE** (participants tronqués) ; `hippo` → **PARTIEL** ; `divergence` → **SOLIDE** (calcul local, mais entièrement déterminé par des données disponibles).

## T.3 Les trois corrections de qualification à expliciter

**1. `elo` : SOLIDE → PARTIEL**

La v1 le classait SOLIDE parce que le calcul ELO est sain. **C'est insuffisant** : le rating dépend intégralement de l'**identité du cheval**, et la clé `NOM|DISCIPLINE` n'est pas une identification fiable (B.4, G.4). Un calcul parfait sur une entité mal identifiée produit un résultat faux. **La fiabilité du calcul ne compense pas l'incertitude de l'identité.**

**2. `poidsRel` : requalifié**

La v1 le classait selon une base erronée (« aucun producteur de `p.poids` »). Le producteur **existe** (`zone_turf_service.dart:624`) et l'alimentation est **propre** — sentinelle gérée explicitement (`scorePoids` retourne 50,0 si `poids <= 0`). Sa limite est la **disponibilité** (handicaps seulement), pas la qualité. D'où : **PARTIEL par disponibilité, mais sain**.

**3. `discipline` : SOLIDE → PARTIEL**

Voir D.2.2. Le critère fonctionne pour les disciplines réelles, mais la branche `global` est une entrée orpheline (delta 5,55e-17, epsilon machine) et le repli vers les poids racine est **indétectable**. Un critère dont on ne peut pas savoir s'il a fonctionné n'est pas solide.

## T.4 Ce que ce tableau démontre collectivement

| Constat | Nombre | Critères |
|---|---:|---|
| Critères dont l'alimentation contient une **donnée fabriquée** | **2** | `gains`, `progression` |
| Critères dont la sentinelle est **indistinguable de l'absence** | **2** | `record`, `placeDepart` |
| Critères dépendant d'une source **structurellement tronquée** | **2** | `jockey`, `entraineur` |
| Critères dont la **disponibilité varie selon la discipline** | **3** | `terrain`, `poidsRel`, `distSpec` |
| Critères avec alimentation **propre et neutre explicite** | **5** | `cote`, `repos`, `divergence`, `mouvCote`, `poidsRel` (partiellement) |
| Critères dont l'incertitude vient de **l'identité** | **1** | `elo` |

**Conclusion, sans adoucissement** : **4 critères sur 19** (gains, progression, record, placeDepart) ont un défaut d'alimentation qui **ne se corrige pas sans toucher à la production**. **2 sur 19** (jockey, entraineur) ont une limite de source qui ne se corrige qu'en **acquérant plus de données**. **1 sur 19** (elo) dépend d'une identité non résolue. **13 sur 19** sont exploitables en l'état.

**Ce que cela signifie pour la fiabilité globale de l'IA** : tant que les 4 défauts d'alimentation ne sont pas traités, une partie du calcul repose sur des valeurs inventées ou sur des sentinelles. Ce n'est pas un problème d'architecture de stockage — c'est un problème de **qualité de donnée**, et il est **antérieur** à ce chantier.

---

# U. DÉCISIONS RESTANT À VALIDER

**Aucune décision de cette liste n'est validée. Aucune n'est appliquée.**

Les décisions sont classées par **nature de leur conséquence**, car elles n'engagent pas la même chose.

## U.1 Décisions qui touchent la production ou l'apprentissage — §36

Ces décisions exigent une **validation formelle et séparée**. Elles ne peuvent pas être groupées.

| Réf | Décision | Conséquence | Ce qui est touché |
|---|---|---|---|
| **D-10** | Supprimer le repli `gainsDernierAn = gainsCarrière × 0,20` | Le critère `gains` cesse de reposer sur une valeur inventée ; son comportement change | Alimentation du critère `gains` |
| **D-13** | Distinguer l'absence de la sentinelle `9999,0` pour `record` | Le critère `record` cesse de recevoir une valeur extrême en cas d'échec d'extraction | Alimentation du critère `record` |
| **D-15** | Remplacer le repli de progression par une alimentation authentique (`reductionKilometrique` + gains réels) avec neutralité explicite | Le critère `progression` devient informatif au lieu d'être une projection constante et fausse | Alimentation du critère `progression` |
| **D-16** | Distinguer `placeCorde` absent de `placeCorde = 0` | Neutralité explicite au lieu d'une valeur du domaine | Alimentation du critère `placeDepart` |
| **D-26** | Politique de traitement des corrections affectant l'apprentissage : marquer sans recalculer (A-2) | L'erreur devient visible sans toucher au gradient | Politique, pas mécanisme |

**Note d'honnêteté sur ces cinq décisions** : D-10, D-13, D-15 et D-16 **changent la valeur** reçue par un critère. Elles ne modifient aucune formule, mais elles changeront le résultat de l'apprentissage suivant. **Prétendre le contraire serait faux** (voir P.5).

## U.2 Décisions d'identité — prérequis de plusieurs autres

| Réf | Décision | Bloque quoi si non tranchée |
|---|---|---|
| **D-11** | Niveau d'identité du cheval : identifiant fournisseur (N-1) / composite (N-2) / entité + alias (N-3) | `elo`, la synchronisation (S.2), la fusion de ratings (D-24) |
| **D-19** | Discipline comme attribut de la participation (O-1 / **O-2** / O-3) | L'unification des ratings, la fiabilité de `elo` |
| **D-29** | Réserver dès la migration : identifiant interne, horodatages, identifiant d'origine, compteur de version, journal de corrections | La synchronisation future (S.3) |

**D-11 est la décision la plus structurante de tout le rapport.** Elle conditionne la fiabilité de `elo`, la faisabilité de la synchronisation, et la qualité de `jockey`/`entraineur`.

## U.3 Décisions de conservation et de politique

| Réf | Décision | Objet |
|---|---|---|
| **D-09** | Garder `trot_monte` distinct de `global` (conservée de la v1) | Préserve un acquis mesuré ; la fusion serait une perte (D.2.2) |
| **D-12** | Les rapports pointés par un bilan sont-ils exemptés de la limite de 365 ? | Résout le conflit C.4 — sans quoi un bilan pointe vers un rapport détruit |
| **D-20** | Sort du mécanisme de purge des ratings ELO « orphelins » (`elo_orphelins_purges_v1`) | Conserver, neutraliser, ou simplement marquer |
| **D-21** | Politique de conservation des fichiers de sauvegarde (combien, combien de temps) | Détermine l'espace disque consommé (I.5) |
| **D-22** | Taille d'un segment d'archive (mensuel proposé) | Équilibre entre nombre de fichiers et coût d'une correction |
| **D-23** | Frontière vif / froid (12 mois proposés) | Détermine le volume chargé et le volume archivé |
| **D-24** | Stratégie de résolution des ratings ELO à la restauration (E-1 / E-2 / E-3) | Détermine ce qui gagne en cas de conflit |
| **D-25** | Les archives sont-elles embarquées dans la sauvegarde, ou une restauration partielle est-elle refusée ? | Détermine si une référence peut devenir morte |
| **D-28** | Versionnement des poids : empreinte seule, ou empreinte + copie des versions majeures ? | Détermine si un pronostic ancien peut être expliqué |

## U.4 Décisions techniques

| Réf | Décision | Options |
|---|---|---|
| **D-17** | Moteur du magasin structuré | `sqflite` **ou** Drift — **[À VÉRIFIER]** compatibilité avec Flutter 3.35.4 / Dart 3.9.2 |
| **D-18** | Emplacement des connaissances sur Android | Stockage interne (effacé à la désinstallation) ou externe nommé (visible, modifiable) |
| **D-27** | Rendre visible le repli de `normaliseDiscipline()` vers `global` | Indicateur de provenance, sans changer la valeur produite |
| **D-14** | Rendre visible la faible informativité de `terrain` en Trot | Constante silencieuse → fait documenté |

## U.5 Récapitulatif — les décisions par ordre de dépendance

```
D-11 (identité du cheval)          ← prérequis de D-19, D-24, S.2
  └── D-19 (discipline attribut)
        └── D-24 (résolution ELO)

D-12 (365 vs bilans)               ← prérequis de la déduplication sans perte
  └── D-23 (frontière vif/froid)
        └── D-22 (taille des segments)
              └── D-21 (conservation des sauvegardes)

D-10, D-13, D-15, D-16 (§36)       ← indépendantes entre elles, chacune séparément

D-17 (moteur)  ·  D-18 (emplacement)  ·  D-25 (archives dans la sauvegarde)
D-20 (purge ELO)  ·  D-26 (corrections)  ·  D-27 (repli visible)  ·  D-28 (versionnement poids)
D-14 (terrain Trot)  ·  D-29 (réservations de synchronisation)
```

**Total : 21 décisions effectives (D-09 à D-29), aucune validée.** À quoi s'ajoutent les décisions de la v1 **explicitement retirées** (A-01/D-01, plafonnement ELO A-02, A-03, A-04, A-05) : leur retrait est un fait de ce rapport, pas une décision en attente.
---

# V. PLAN D'INTÉGRATION COMPLET ET ORDONNÉ

Cette section traite le point **21** de votre consigne. Elle remplace intégralement le plan P-1…P-7 de la v1.

## V.1 Pourquoi le plan v1 est abandonné

| Plan v1 | Défaut |
|---|---|
| P-1 : recalcul des bilans | Commençait par **recalculer** ce qu'il n'était pas nécessaire de recalculer, avant même d'avoir identifié les 24 orphelins |
| P-2 : comparaison recalculé ↔ stocké | Utile, mais arrivait **avant** la déduplication : comparer des agrégats n'a de sens qu'une fois les rapports unifiés |
| P-3 : suppression des bilans | **Dangereux** — aurait détruit 24 rapports uniques |
| P-4 à P-7 | Dépendants d'une base fausse |

**Le défaut de méthode** : le plan v1 traitait les symptômes (volume, agrégats) avant les causes (identité, duplication). Le plan révisé fait l'inverse.

## V.2 Les dix étapes, ordonnées par dépendance

**Chaque étape a une porte de sortie explicite** : si sa condition n'est pas remplie, on ne passe pas à la suivante.

---

### ÉTAPE 1 — Établir la vérité des données existantes

**Objectif** : savoir exactement ce qui existe, avant de toucher à quoi que ce soit.

| Action | Contenu |
|---|---|
| 1.1 | Lire les 14 clés racine et les 44 clés `ia_*` des données existantes |
| 1.2 | Décoder le blob `ia_pronostics_v2_gz` (base64 → gzip → JSON) |
| 1.3 | Extraire **tous** les rapports : collection + `BilanSemaine.rj` + `BilanMois.sem[].rj` |
| 1.4 | Calculer les empreintes de contenu canonique sur **tous** |
| 1.5 | Identifier les **24 orphelins** nommément |
| 1.6 | Compter les ratings ELO réels **[À VÉRIFIER]** |

**Porte de sortie** : les comptes 195 / 185 / 144 / 524 / 225 / 219 / 24 sont **reproduits**. Sinon → arrêt.

**Cette étape ne modifie rien.** Elle est entièrement en lecture.

---

### ÉTAPE 2 — Trencher D-11 : l'identité du cheval

**Objectif** : résoudre le prérequis bloquant.

| Action | Contenu |
|---|---|
| 2.1 | **[À VÉRIFIER]** présence d'un identifiant cheval stable dans le flux PMU |
| 2.2 | Si absent : mesurer l'unicité effective de `nom` sur le corpus |
| 2.3 | Si insuffisant : mesurer la fréquence réelle des chevaux multi-disciplines |
| 2.4 | Soumettre D-11 avec les résultats de 2.1 à 2.3 |

**Porte de sortie** : D-11 tranchée. Sans elle, **les étapes 6 (ELO) et la synchronisation sont impossibles**.

---

### ÉTAPE 3 — Concevoir et valider le schéma cible

**Objectif** : écrire le schéma sur le papier avant de l'écrire en base.

| Action | Contenu |
|---|---|
| 3.1 | Schéma des faits F1 (courses, participations) |
| 3.2 | Schéma d'identité (chevaux, alias, jockeys, entraîneurs, hippodromes) |
| 3.3 | Schéma des rapports + versions |
| 3.4 | Schéma des bilans (agrégats + références) |
| 3.5 | Schéma ELO (une ligne par entité/discipline) |
| 3.6 | Réservations de synchronisation (D-29) |
| 3.7 | **[À VÉRIFIER]** test d'aller-retour exact des 19 poids × 4 disciplines (P.2) |

**Porte de sortie** : 3.7 réussi — les poids relus sont **bit à bit identiques**. Sinon → la sérialisation doit être corrigée avant d'aller plus loin.

---

### ÉTAPE 4 — Construire la couche commune et ses adaptateurs

**Objectif** : rendre le support physique interchangeable.

| Action | Contenu |
|---|---|
| 4.1 | Définir les interfaces des quatre magasins (faits, apprentissage, archives, cache) |
| 4.2 | Implémenter l'adaptateur de test (`sqflite_common_ffi` ou mémoire) |
| 4.3 | Implémenter l'adaptateur Web (`sqflite_common_ffi_web` **ou** fallback) **[À VÉRIFIER]** |
| 4.4 | Implémenter l'adaptateur Android (`sqflite` ou Drift — D-17) |
| 4.5 | Interdire tout accès direct à `SharedPreferences` depuis le code métier |

**Porte de sortie** : la même suite de tests passe sur l'adaptateur de test **et** sur l'adaptateur Web. Si le Web échoue, la capacité de vérification est compromise → **ne pas continuer sans l'avoir résolu**.

---

### ÉTAPE 5 — Déduplication sans perte

**Objectif** : écrire les rapports dans la nouvelle structure, en préservant tout.

| Action | Contenu |
|---|---|
| 5.1 | Écrire les 219 contenus normalisés (+ les versions distinctes) |
| 5.2 | Vérifier la présence effective des **24 orphelins** |
| 5.3 | Écrire les bilans en agrégats + références |
| 5.4 | Contrôler : aucune référence morte, 0 |
| 5.5 | Contrôler : sommes d'agrégats inchangées |

**Porte de sortie** : 219 contenus, 24 orphelins présents, 0 référence morte. **Sinon → migration refusée, l'ancienne structure continue de servir.**

---

### ÉTAPE 6 — Migrer l'ELO

**Objectif** : conserver tous les ratings, avec actualisation individuelle.

| Action | Contenu |
|---|---|
| 6.1 | Écrire les ratings dans la table, selon D-11 et D-19 |
| 6.2 | Vérifier : **aucun rating perdu** (compte identique avant/après) |
| 6.3 | Vérifier : aucune valeur `rating` modifiée |
| 6.4 | **[APPAREIL REQUIS]** mesurer M-03 (batch de 42 écritures) |

**Porte de sortie** : compte identique, valeurs identiques, aucune purge (D-20 non tranchée → **conservation par défaut**).

---

### ÉTAPE 7 — Sauvegarde et restauration

**Objectif** : un format qui permet la reprise sans perte.

| Action | Contenu |
|---|---|
| 7.1 | Implémenter le format `.ptg` (en-tête, blocs, empreintes, inventaire) |
| 7.2 | Implémenter l'adaptateur de lecture du format 9.0 (compatibilité) |
| 7.3 | Implémenter la lecture de vérification après écriture |
| 7.4 | Implémenter la restauration transactionnelle avec copie de retour arrière |
| 7.5 | Implémenter le nettoyage des `.tmp` orphelins au démarrage |
| 7.6 | Tester les six cas d'échec de M.5 |

**Porte de sortie** : les deux sauvegardes réelles (28/05 et 13/11) se lisent correctement, et la restauration d'une d'entre elles sur un état vide produit les comptes attendus.

---

### ÉTAPE 8 — Détection des changements et actualisation ciblée

**Objectif** : supprimer les traitements inutiles.

| Action | Contenu |
|---|---|
| 8.1 | Signatures par catégorie (F.2) |
| 8.2 | Dépendances déclarées catégorie → calculs |
| 8.3 | Déduplication des requêtes simultanées (F.4) |
| 8.4 | Tentatives bornées (F.5) |
| 8.5 | Trois états : absent / indisponible / présent (F.6), avec **durée de validité** de l'absence |
| 8.6 | Annulation coopérative (F.7) |

**Porte de sortie** : un test démontre qu'un événement qui ne change aucune dépendance ne déclenche **aucun** recalcul.

---

### ÉTAPE 9 — Archives et consultation

**Objectif** : conserver indéfiniment sans pénaliser la consultation.

| Action | Contenu |
|---|---|
| 9.1 | Segments d'archive + manifeste |
| 9.2 | Journal de corrections (K.5) |
| 9.3 | Consultation d'un bilan ancien sans recalcul (K.4) |
| 9.4 | Vérification d'intégrité par manifeste |

**Porte de sortie** : un bilan de 10 ans se consulte **sans décompresser plus d'un segment**, et ses agrégats sont lus, pas recalculés.

---

### ÉTAPE 10 — Mesures sur appareil et décision de bascule

**Objectif** : décider avec des chiffres, pas avec une intention.

| Action | Contenu |
|---|---|
| 10.1 | **[APPAREIL REQUIS]** M-01 à M-10 |
| 10.2 | **[APPAREIL REQUIS]** T-1 à T-9 |
| 10.3 | Comparaison avec l'état actuel |
| 10.4 | Décision de bascule (phase N-D) |

**Porte de sortie** : **aucune régression mesurée** sur les points critiques. Sinon → retour à l'ancienne structure (phase N-D réversible).

## V.3 Ce qui n'est pas dans ce plan — et pourquoi

| Absent | Motif |
|---|---|
| Toute modification de formule, de poids, de seuil | §36 — interdit |
| Rejeu du gradient | O.3 — interdit |
| Toute suppression de données | Votre consigne |
| Tout plafonnement de l'ELO | Votre consigne |
| Toute migration réelle | Votre consigne — ce plan **prépare**, il n'exécute pas |
| Toute réinitialisation | Votre consigne |
| Toute intégration avant validation | Votre consigne |

## V.4 Ce que chaque étape peut faire échouer — et c'est volontaire

**Un plan sans porte de sortie est un plan qui avance dans le vide.** Les portes de V.2 sont conçues pour **arrêter** en cas d'anomalie.

| Étape | Risque d'échec | Ce qu'on fait alors |
|---|---|---|
| 1 | Comptes non reproduits | Arrêt — les données ne sont pas comprises |
| 2 | Aucun identifiant stable disponible | D-11 en mode composite ; synchronisation **reportée** |
| 3 | Poids non relus à l'identique | Correction de sérialisation — **bloquant** |
| 4 | Web non fonctionnel | La vérification devient impossible → **résoudre avant de continuer** |
| 5 | Référence morte détectée | Migration refusée — ancienne structure conservée |
| 6 | Rating perdu | Migration refusée |
| 7 | Sauvegarde non relisible | Format à corriger — **bloquant** |
| 8 | Recalcul inutile encore présent | Optimisation incomplète — corriger |
| 9 | Segment illisible | Archive à vérifier — **ne pas archiver plus** |
| 10 | Régression mesurée | Retour à l'ancienne structure |

---

# W. CE QUE CE RAPPORT NE PROUVE PAS

Cette section est exigée par l'honnêteté, et par votre méthode.

## W.1 Affirmations qui ne sont pas des preuves

| Affirmation | Statut réel |
|---|---|
| « L'architecture révisée sera plus rapide » | **Non démontré.** Elle supprime des causes **démontrées** de lenteur. C'est différent. |
| « La consommation batterie diminuera » | **Non mesuré.** La chaîne causale est démontrée (réencodage quadratique), l'effet réel sur batterie non. |
| « La RAM ne croîtra plus » | **Objectif de conception**, pas un résultat. Non mesuré. |
| « Les projections de volume sont justes » | **Ce sont des calculs sur hypothèses.** Chaque hypothèse est listée en I.3. Si une change, le résultat change. |
| « La migration préservera tout » | **Non démontré avant exécution.** Les portes de sortie sont là pour le vérifier, pas pour l'affirmer. |
| « L'ELO sera plus fiable » | **Faux en l'état** : il restera tributaire de l'identité du cheval tant que D-11 n'est pas tranchée. |
| « Les 19 critères seront fiables » | **Faux.** Quatre d'entre eux reposent encore sur des valeurs fabriquées ou des sentinelles. |
| « La synchronisation fonctionnera » | **Non traité.** Elle est même **bloquée** par D-11. |
| « L'agent IA sera possible » | **Non démontré.** L'architecture ne l'empêche pas. Ce n'est pas la même chose. |

## W.2 Ce que ce rapport démontre réellement

**Trois choses, et seulement trois :**

1. **Les défauts actuels sont identifiés et chiffrés.** La duplication, la réécriture intégrale, les plafonds manquants, la non-atomicité, les données fabriquées : tout cela est **[MESURÉ]** ou **[DÉMONTRÉ]**, avec la référence.

2. **Les propositions de la v1 qui reposaient sur une erreur sont corrigées, et l'erreur est nommée.** La suppression des bilans aurait détruit 24 rapports. Le plafond ELO aurait supprimé des connaissances. La déduplication par date était fausse. Le rejet de SQLite était un raisonnement erroné. **Ces quatre erreurs sont explicitement reconnues.**

3. **Les questions qui restent ouvertes sont nommées, avec la vérification qui les fermera.** Vingt décisions, chacune avec sa dépendance et son statut. Aucune n'est tranchée.

## W.3 Ce que ce rapport ne fait pas

- Il ne valide aucune architecture.
- Il n'exécute aucune migration.
- Il ne modifie aucune politique de conservation.
- Il ne change ni formule, ni poids, ni seuil, ni mécanisme d'apprentissage.
- Il ne supprime aucune donnée.
- Il ne plafonne pas l'ELO.
- Il ne réinitialise rien.
- Il n'a produit aucun push.

## W.4 La conclusion la plus inconfortable

**L'architecture révisée occupe plus de disque que l'actuelle** : ≈ 372 Mo contre ≈ 216 Mo à 10 ans.

**Ce n'est pas un défaut à corriger.** C'est la conséquence arithmétique de votre principe : conserver les connaissances coûte de l'espace. Le statu quo est plus petit parce qu'il **ne conserve pas les faits PMU**, ne garde que 5 pronostics sur 600 avec leurs critères, et duplique ce qu'il garde 524 fois.

**Le vrai gain de cette architecture n'est pas l'espace. C'est :**
- **la conservation** de ce qui n'était pas conservé,
- **la suppression** de la duplication (×2,39 → ×1,00),
- **la fin** de la réécriture intégrale (99,7 % → ligne modifiée),
- **la fin** du chargement intégral (RAM indépendante du volume),
- **la réparabilité** (sauvegarde vérifiable, restauration transactionnelle).

**Si le critère de succès est « moins de Mo », cette architecture échoue.** Si le critère est « conserver plus de connaissances, plus sûrement », elle réussit — mais cela reste **à démontrer par les mesures M-01 à M-10**, pas à affirmer ici.

---

# X. INVENTAIRE DES VÉRIFICATIONS À MENER

Cette section regroupe toutes les vérifications nommées dans le rapport, pour qu'aucune ne soit perdue.

## X.1 Vérifications faisables sans appareil

| # | Vérification | Section | Ce qu'elle décide |
|---|---|---|---|
| V-01 | Présence d'un identifiant cheval stable dans le flux PMU | B.4, G.4 | **D-11** |
| V-02 | Unicité effective du nom de cheval sur le corpus | B.4 | D-11 (mode composite) |
| V-03 | Fréquence réelle des chevaux multi-disciplines | B.4, G.4 | Ampleur de la fragmentation |
| V-04 | Unicité du triplet course (date + réunion + course + hippodrome) | B.3 | Clé de course |
| V-05 | Présence effective de `placeCorde` dans les réponses | D.2.9 | Fiabilité de `placeDepart` |
| V-06 | Existence d'une source `gainsDernierAn` réelle | D.2.7 | **D-15** |
| V-07 | Nombre réel de ratings ELO dans les données | G.6, I.3 | Dimensionnement |
| V-08 | Taille réelle d'une ligne (participation, course, ELO, rapport) | I.3 | Fermeté des projections |
| V-09 | Test d'aller-retour exact des 19 poids × 4 disciplines | P.2 | **Bloquant** pour la migration |
| V-10 | Compatibilité `sqflite` / Drift / `sqflite_common_ffi_web` avec Flutter 3.35.4 | E.3, D-17 | **D-17** |
| V-11 | Compression réelle d'un échantillon de faits froids | I.3 | Projections |
| V-12 | Distribution réelle de courses/jour et partants/course | I.3 | Projections |
| V-13 | Comportement du flux PMU face à une nouvelle discipline | O.5, D-27 | **D-27** |
| V-14 | Absence de mécanisme de comparaison de version à la restauration | L.4 | Confirme le défaut (déjà **[DÉMONTRÉ]**) |

## X.2 Mesures nécessitant un appareil Android réel

| # | Mesure | Section |
|---|---|---|
| M-01 | Tas après chargement complet | I.6, J.4 |
| M-02 | Croissance du tas avec le volume | I.6, J.4 |
| M-03 | Temps d'un batch de 42 écritures ELO | G.6, J.4 |
| M-04 | Temps de démarrage à froid | J.4 |
| M-05 | Fluidité des listes | J.4 |
| M-06 | Consommation sur 8 h | J.4 |
| M-07 | Durée d'un export complet | I.5, J.4 |
| M-08 | Débit d'écriture SQLite transactionnelle | E.3, J.4 |
| M-09 | Comportement à stockage saturé | M.5, R.4 |
| M-10 | Comportement à interruption brutale | M.5, R.4 |

## X.3 Tests d'appareil (matrice)

| # | Appareil / condition | Section |
|---|---|---|
| T-1 | Samsung entrée de gamme (RAM ≤ 4 Go) | R.4 |
| T-2 | Samsung milieu de gamme | R.4 |
| T-3 | Samsung haut de gamme | R.4 |
| T-4 | Samsung tablette | R.4 |
| T-5 | Android non-Samsung | R.4 |
| T-6 | Android 11 (API 30) | R.4 |
| T-7 | Android 15 (API 35) | R.4 |
| T-8 | Stockage saturé (< 1 Go libre) | R.4 |
| T-9 | Interruption brutale pendant une écriture | R.4 |

---

# Y. RÉCAPITULATIF FINAL DES DÉCISIONS

**Aucune décision n'est validée. Aucune n'est appliquée.**

| Réf | Décision | Catégorie | Bloque |
|---|---|---|---|
| **D-09** | Garder `trot_monte` distinct de `global` | Conservation | Étape 3 (schéma des disciplines) |
| **D-10** | Supprimer le repli `gainsDernierAn = 20 %` | **§36** | — |
| **D-11** | Identité du cheval (fournisseur / composite / entité+alias) | **Identité** | D-19, D-24, synchronisation |
| **D-12** | Exempter de la limite 365 les rapports pointés par un bilan | Conservation | Déduplication sans perte |
| **D-13** | Distinguer absence et sentinelle `9999,0` (`record`) | **§36** | — |
| **D-14** | Rendre visible la faible informativité de `terrain` en Trot | Transparence | — |
| **D-15** | Alimentation authentique de la progression (remplace le repli 20 %) | **§36** | — |
| **D-16** | Distinguer `placeCorde` absent de `placeCorde = 0` | **§36** | — |
| **D-17** | Moteur du magasin structuré (`sqflite` ou Drift) | Technique | Étape 4 |
| **D-18** | Emplacement des connaissances sur Android | Technique | Étape 4 |
| **D-19** | Discipline comme attribut de la participation (O-1/O-2/O-3) | **Identité** | D-24 |
| **D-20** | Sort de la purge des ratings « orphelins » | Conservation | Étape 6 |
| **D-21** | Politique de conservation des fichiers de sauvegarde | Conservation | I.5 |
| **D-22** | Taille d'un segment d'archive | Conservation | Étape 9 |
| **D-23** | Frontière vif / froid | Conservation | I.2, Étape 9 |
| **D-24** | Résolution des ratings ELO à la restauration | Restauration | Étape 7 |
| **D-25** | Archives embarquées dans la sauvegarde, ou refus du partiel | Restauration | Étape 7 |
| **D-26** | Traitement des corrections affectant l'apprentissage (marquer sans recalculer) | **§36** | — |
| **D-27** | Rendre visible le repli `normaliseDiscipline() → global` | Transparence | — |
| **D-28** | Versionnement des poids (empreinte seule ou + copies majeures) | Apprentissage | Explication des pronostics anciens |
| **D-29** | Réservations de synchronisation dès la migration | Architecture | Synchronisation future |

**Six décisions touchent §36** (D-10, D-13, D-15, D-16, D-26, et D-28 touche la traçabilité de l'apprentissage). Elles ne peuvent pas être groupées ni appliquées par lot.

---

**FIN DU RAPPORT CONSOLIDÉ RÉVISÉ — VERSION 2**

*Aucune modification de production. Aucune suppression de données. Aucun plafonnement de l'ELO. Aucune migration réelle. Aucune réinitialisation. Aucune modification des formules, des poids, du gradient, des seuils, du TOP3 Learning ou de l'apprentissage. BLOC 2 intact et suspendu. Aucun push GitHub. Aucune architecture validée. Aucune décision d'intégration validée.*
