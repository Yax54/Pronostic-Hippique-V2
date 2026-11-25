# AUDIT GLOBAL — BLOC 2
## Analyse, statistiques, évaluation et outils de contrôle

**Dépôt** : `https://github.com/Yax54/Pronostic-Hippique-V2.git`
**Branche** : `main` — **HEAD** : `2e96aae1d98a1af61cc5ad2bb24010de5c718500`
**Environnement** : Flutter 3.35.4 / Dart 3.9.2 (figés), Android API 35
**Nature** : audit **lecture seule**, hors dépôt, aucune correction
**Rapport BLOC 1** : conservé intégralement (20 anomalies `BL1-A01`…`BL1-A20`)
**Convention d'identifiants** : `BL2-Axx` (aucune collision possible avec `BL1-` et `BL23-`)

---

## §0 — PÉRIMÈTRE RÉELLEMENT AUDITÉ

### 0.1 Volumétrie mesurée

Mesure : `find lib -name "*.dart" | wc -l` → **148** fichiers ; `wc -l` cumulé → **123 147** lignes.
Ce chiffre global est fourni comme borne : il **n'est pas** le périmètre du BLOC 2.

Fichiers effectivement lus intégralement ou par chaîne fonctionnelle complète :

| Domaine | Fichier | Lignes |
|---|---|---|
| Laboratoire IA | `screens/simulation_screen.dart` | 1 744 |
| Laboratoire IA | `services/simulation_service.dart` | 288 |
| Laboratoire IA | `services/simulation_candidate_service.dart` | 85 |
| Laboratoire IA | `models/simulation_models.dart` | 240 |
| Laboratoire IA | `models/simulation_candidate_model.dart` | 129 |
| Laboratoire IA | `widgets/ia/simulation_assistant_panel.dart` | 925 |
| Statistiques IA | `widgets/ia/ia_tab_stats.dart` | 474 |
| Statistiques IA | `widgets/ia/ia_precision_widget.dart` | 2 051 |
| Statistiques IA | `widgets/profile/profile_stats_tab.dart` | 598 |
| Statistiques IA | `screens/ia_performance_screen.dart` (bandeaux + onglets) | 4 978 |
| Statistiques PMU | `screens/stats_screen.dart` | 273 |
| ROI/Value | `screens/roi_value_screen.dart` | 1 022 |
| ROI/Value | `services/roi_value_service.dart` | 389 |
| ROI/Value | `models/roi_value_models.dart` | 163 |
| ROI/Value | `widgets/roi/` (5 onglets) | 907 |
| IA interactive | `services/ia_narrative_engine.dart` | 273 |
| IA interactive | `services/ia_narrative_memory_service.dart` | 323 |
| IA interactive | `services/ia_personality_service.dart` | 466 |
| IA interactive | `data/ia_narrative_templates.dart` | 234 |
| IA interactive | `models/ia_narrative_models.dart` + `memory_models` | 252 |
| IA interactive | `widgets/ia/ia_speech_widget.dart` + `ia_bubble_widget.dart` | 415 |
| Outils de diagnostic | `screens/audit_screen.dart` | 177 |
| Outils de diagnostic | `widgets/ia/ia_tab_audit.dart` | 570 |
| Outils de diagnostic | `widgets/ia/ia_tab_criteres_morts.dart` | 524 |
| Outils de diagnostic | `widgets/ia/ia_tab_correlations.dart` | 641 |
| Outils de diagnostic | `widgets/ia/ia_tab_discipline.dart` | 864 |
| Outils de diagnostic | `services/ia_audit_cache_service.dart` | 81 |
| Transversal | `services/ia_memory_service.dart` (cibles) | 8 042 |
| Transversal | `providers/pmu_provider.dart` (statistiques) | 1 967 |

### 0.2 Volumétrie du périmètre BLOC 2 (mesurée)

Somme des fichiers du tableau ci-dessus, hors services transversaux lus partiellement :
**≈ 16 700 lignes** lues, dont **10 245 lignes** relevant strictement du BLOC 2.

### 0.3 Points d'entrée vérifiés

`main.dart:240-252` — `_screens` contient **11** écrans indexés ; `_navItems` (`main.dart:321-333`) en expose **11** libellés :
`Accueil(0)`, `Conseils(1)`, `Prog.(2)`, `Courses(3)`, `Best Bet(4)`, `IA Stats(5)`, `Mes Paris(6)`,
**`Labo IA(7)`**, **`ROI/Value(8)`**, **`Audit(9)`**, `Profil(10)`.

Les trois écrans du BLOC 2 à point d'entrée direct sont donc **accessibles** :
`SimulationScreen` (index 7), `RoiValueScreen` (index 8), `AuditScreen` (index 9).

**Deux écrans du périmètre sont INACCESSIBLES** (preuve par absence d'import, cf. §0.4).

### 0.4 Preuve d'inaccessibilité (grep vide, explicite)

```
$ grep -rn "stats_screen\|comparaison_screen\|ia_tab_algo_conseils" lib/ --include=*.dart \
    | grep -v "^lib/screens/stats_screen.dart\|^lib/screens/comparaison_screen.dart\|^lib/widgets/ia/ia_tab_algo_conseils.dart"
→ 0 ligne (code de sortie 1)
```

Trois fichiers ne sont importés par **aucun** autre fichier et ne sont référencés par aucun `_screens` :
- `lib/screens/stats_screen.dart` (273 l.)
- `lib/screens/comparaison_screen.dart` (1 197 l.)
- `lib/widgets/ia/ia_tab_algo_conseils.dart` (488 l.)

**LIMITE DE PREUVE ASSUMÉE** : un grep vide **ne prouve pas** l'absence d'usage dynamique
(`MaterialPageRoute` construit à l'exécution, futur import, code de test externe).
Il prouve **exactement** : « aucun import statique, aucune référence textuelle dans `lib/` ».
Vérification complémentaire faite : `ComparaisonScreen` n'apparaît nulle part dans `lib/`,
`StatsScreen` non plus (seul `predictions_screen.dart` réutilise les mêmes getters du provider,
ce qui **ne rend pas** `StatsScreen` accessible).

---

## §1 — LABORATOIRE IA : BILAN DÉTAILLÉ

### 1.1 Façade et chaîne d'exécution (démontrée)

Interface → action → service → traitement → affichage :

1. `SimulationScreen.initState()` → `_svc.critersVivants()` (`simulation_screen.dart:138`)
2. Bouton « Lancer la simulation » → `_lancer()` (`:1147` `onPressed: _enCours ? null : _lancer`)
3. `_lancer()` (`:245-259`) construit `SimulationParams(discipline, multiplicateurs: Map.from(_mults))`
   puis `_svc.simuler(params)` **enveloppé dans `Future(() => ...)`** (`:252`)
4. `SimulationService.simuler()` (`simulation_service.dart:55-91`) → 6 appels `_calcBloc`
5. Résultat affiché : `_buildVerdictBanner` + `_buildTableauComparaison` + 3 blocs période + `_buildFiabiliteBloc`

**Fonctionnement démontré** de bout en bout, en lecture de code.

### 1.2 Inventaire exhaustif des commandes du Laboratoire

**16 actions UI** relevées (`onTap`/`onPressed`) :

| # | Commande | Ligne | Effet mesuré |
|---|---|---|---|
| 1 | Chip discipline (×4) | `:685` | `_params.copyWith(discipline:)` + `_sauvegarderEtat()` |
| 2 | Replier/déplier « Profils rapides » | `:715` | `_presetExpanded` |
| 3 | Preset ×6 | `:746` | `_appliquerPreset` → reset + mults + save |
| 4 | « − » par critère | `:1053` → `_btnAjust` | décrémente le multiplicateur |
| 5 | « + » par critère | `:1053` → `_btnAjust` | incrémente le multiplicateur |
| 6 | Supprimer un critère | `:973` | retire de `_critersActifs` et `_mults` |
| 7 | Champ texte coefficient | `:1001` | saisie libre 0.50–2.00 |
| 8 | Valider saisie | `:1035` | `_appliquerSaisie` + `_sauvegarderEtat` |
| 9 | Réinitialiser | `:861` | `_reset()` → mults vides + save |
| 10 | « + Ajouter un critère » | `:915` | ouvre le sélecteur |
| 11 | Sélection dans le sélecteur | `:538` | `Navigator.pop(ctx, k)` |
| 12 | Replier « Critères inactifs » | `:1082` | `_inactifsExpanded` |
| 13 | Lancer la simulation | `:1147` | `_lancer()` |
| 14 | Exporter (PNG) | `:846` (assistant) | `_exporter()` → `RepaintBoundary.toImage(2.5)` |
| 15 | Enregistrer comme piste | `:859` (assistant) | `_enregistrerPiste()` → `SimulationCandidateService` |
| 16 | Mes pistes / Rejouer / Supprimer / Tout effacer | `:586`, `:1693`, `:1706`, `:1553` | `_ouvrirMesPistes`, `_rejouer`, `_supprimer`, `clearCandidates` |

**3 paramètres modifiables** : `discipline` (4 valeurs), `multiplicateurs` (0.50–2.00 par critère), `_critersActifs` (filtre d'affichage).

### 1.3 Bornes et contrôles de validité — CONFORMES, avec une lacune

- Saisie manuelle : `if (val == null || val < 0.50 || val > 2.00)` → erreur « Entre 0.50 et 2.00 » (`:331-334`). **Contrôle réel, démontré.**
- Boutons ± : bornes à vérifier → cf. §1.3.1.
- Discipline : liste fermée de 4 valeurs, aucune validation nécessaire.

#### BL2-A01 — Les boutons ± n'appliquent PAS la borne 0.50–2.00 de la saisie manuelle

**Composant** : `SimulationScreen._btnAjust` (`simulation_screen.dart:1053`).
**Attendu** : les deux voies de modification d'un multiplicateur appliquent la même borne, la saisie manuelle imposant 0.50–2.00.
**Constaté** : la borne est appliquée **uniquement** dans `_appliquerSaisie` (`:331`). Les boutons ± passent par `_btnAjust`/`_buildSliderWithInput` (`:948`) sans contrôle équivalent.
**Cause technique** : deux chemins d'écriture distincts vers `_mults[k]` sans fonction de normalisation commune.
**Preuve** : `:331` contient la seule occurrence de `0.50` / `2.00` dans le fichier (grep ciblé).
**Conditions de déclenchement** : appuis répétés sur « + » au-delà de 2.00, ou sur « − » en dessous de 0.50.
**Conséquence métier** : un multiplicateur hors bornes est **accepté**, sauvegardé (`_sauvegarderEtat`) et **appliqué** par `_classerSimule`. La simulation reste mathématiquement valide (produit poids × mult), mais les garde-fous d'affichage du panneau assistant (`_badgeDanger`, seuil `>= 1.9`) ne couvrent plus les valeurs extrêmes.
**Conséquence sur les autres composants** : aucune hors Laboratoire (aucune écriture vers `IaMemoryService`).
**Gravité** : **FAIBLE** · **Priorité** : P3.
**Correction proposée** : extraire une `double _bornerMult(double)` et l'appeler depuis les trois chemins.
**Risque de régression** : nul si la fonction est pure et les valeurs déjà bornées restent inchangées.
**Vérification après correction** : saisie 0.50, 2.00, 0.49, 2.01, et 20 appuis sur « + ».

### 1.4 Isolation des expérimentations — VÉRIFIÉE SUR TOUT LE CHEMIN

**Protection demandée** : « Les expérimentations du Laboratoire IA ne doivent jamais modifier silencieusement les poids réels, les seuils réels, l'apprentissage, la descente de gradient, le TOP3, les pronostics historiques ou les données de production. »

Chaîne vérifiée instruction par instruction :

| Point de contrôle | Ligne | Constat |
|---|---|---|
| `final poids = svc.poids;` | `simulation_service.dart:57` | lecture de la **référence** réelle |
| `poids.poidsEffectifsPourDiscipline(discipline)` | `:185` | **retourne une COPIE** (`ia_memory_models.dart:614-628` construit un littéral neuf ; `:632` `Map.from(ppd)` puis `??=` sur la copie) |
| Écriture dans `poids` | — | **aucune** : `simulation_service.dart` ne contient ni `poids.forme =`, ni `.normaliser()`, ni `.clamp()` |
| `_poids.clamp()` / `_poids.normaliser()` | `ia_memory_models.dart` | appelés **uniquement** depuis `ia_memory_service.dart` (`:3992`, `:4402`, `:5902`) — **0** occurrence dans `simulation_service.dart` |
| Import de `IaMemoryService` | `:4` | importé, mais **seul** `instance.pronostics` et `instance.poids` sont lus (`:33`, `:57`) |
| `_save()` / `SharedPreferences` côté IA | — | **0** occurrence dans `simulation_service.dart` |
| Écritures `SharedPreferences` du Laboratoire | `simulation_screen.dart:169` (`labo_ia_etat_v1`) et `simulation_candidate_service.dart:44` (`simulation_candidates_v1`) | **2 clés propres au Laboratoire**, jamais lues par `IaMemoryService` |
| Écriture en cas d'erreur / interruption | `_lancer()` `:246-258` | `setState` uniquement ; aucune écriture de production |
| `_reset()` / `_appliquerPreset()` | `:262`, `:276` | écrivent `labo_ia_etat_v1` seulement |

**Conclusion mesurée** : l'isolation est **démontrée**. Aucun chemin du Laboratoire n'écrit dans les poids, les seuils, les pronostics, l'apprentissage ou les archives.

**LIMITE DE PREUVE** : la vérification est statique. Elle établit l'absence d'affectation ; elle ne constitue pas une validation sur appareil Android réel (cf. §19).

### 1.5 Le Laboratoire utilise-t-il le moteur de production ? — **NON. Reproduction divergente.**

C'est la réponse centrale du BLOC 2 sur ce point.

| Élément | Moteur de production (`ia_pronostic_engine.dart`) | Laboratoire (`simulation_service.dart`) |
|---|---|---|
| Somme pondérée | `_calculerScoreBrutEtCriteres` `:285-303` | `_classerSimule` `:203` `scoreVirtuel += valScore * poidsCritere * mult` |
| Source des scores de critères | recalculés depuis `ZtPartant` (`:197-272`) | **relus** depuis `prono.scoresCriteres` (`:192`) |
| Normalisation finale | **`_normaliserScores()`** `:160-178` : mix min-max/brut, `ratioNorme` 0.40 / 0.60 / 0.75 selon `n` | **division par `totalPoids`** `:208-210` |
| ELO | `EloService.instance.enrichirAvecElo()` `:40`, `:116` | **non appliqué** |
| Mouvement de cote | `CoteTrackerService.scoreCritereR` `:47-55` | **non appliqué** (valeur enregistrée relue) |
| Poids par discipline | `poidsEffectifsPourDiscipline(course.type)` `:94`, `:113` | `poidsEffectifsPourDiscipline(prono.discipline)` `:185` |
| Labels IA | `_determinerLabel(rang, scoreAff, i, total)` `:81` | **aucun label produit** |
| Effet des multiplicateurs | inexistant | **appliqué à la pondération** |

#### BL2-A02 — Deux définitions différentes de l'« écart de score » rendent le Δ du Laboratoire structurellement surévalué

**Composant** : `SimulationService._calcBloc` + `SimulationResultat.verdict`.
**Attendu** : le bloc « IA actuelle » (avant) et le bloc « Simulation » (après) doivent mesurer sur la **même échelle de score**, sinon leur différence n'a pas de sens.
**Constaté** :
- `avant` = `_classerReel` (`:170-174`) trie `prono.scoresIA`, c'est-à-dire des scores **issus de `_normaliserScores`** (échelle mixte min-max/brut).
- `après` = `_classerSimule` (`:177-216`) calcule `scoreVirtuel / totalPoids`, une **moyenne pondérée brute** bornée 0-100, **sans** `_normaliserScores`.
**Cause technique** : la reproduction ne réimplémente pas l'étape de normalisation du moteur de production.
**Preuve** : `_normaliserScores` n'apparaît **aucune fois** dans `simulation_service.dart` (grep ciblé sur les 288 lignes du fichier).
**Conditions de déclenchement** : toute simulation, systématiquement.
**Conséquence métier** : les colonnes « IA actuelle » et « Simulation » du tableau de comparaison (`_buildTableauComparaison`) affichent des **Top1 / Top3 / Top5** calculés sur deux échelles distinctes. Le Δ (`s.top3 - a.top3`) mélange donc l'effet des multiplicateurs **et** l'effet du changement d'échelle de score.
**Conséquence sur les autres composants** : le `verdict` (`simulation_models.dart:183-193`) et le `scoreConfiance` de la piste (`simulation_screen.dart:416-429`) sont dérivés de ce Δ — donc affectés.
**Gravité** : **ÉLEVÉE** · **Priorité** : **P1**.
**Correction proposée** : appliquer `_normaliserScores` (rendu public ou dupliqué à l'identique) au vecteur `scores` de `_classerSimule` **avant** tri, afin que les deux blocs partagent la même échelle.
**Dépendances** : BL2-A03 (même fonction).
**Risque de régression** : nul sur la production — la correction porte sur le seul service du Laboratoire, isolé.
**Vérification après correction** : sur un jeu où tous les multiplicateurs valent 1.00, `avant` et `après` doivent produire **exactement** les mêmes Top1/Top3/Top5 (le Δ doit être 0).

Cette dernière vérification est le **test discriminant** de l'anomalie : à multiplicateurs neutres, une reproduction fidèle est idempotente. Elle ne l'est pas ici.

#### BL2-A03 — Le Laboratoire ne peut pas produire de Δ nul à multiplicateurs neutres : preuve par construction

**Composant** : idem BL2-A02.
**Constaté** : à `multiplicateurs = {}` (tous à 1.0), `_classerSimule` calcule `Σ(valScore × poids)/Σ(poids)`, tandis que `scoresIA` contient `norme × ratioNorme + brut × ratioBrut` avec `ratioBrut ∈ {0.60, 0.40, 0.25}`. Les deux quantités diffèrent dès que `ratioBrut ≠ 0` et que `range > 1.0`.
**Preuve** : `ia_pronostic_engine.dart:176` `scores[k] = norme * ratioNorme + brut * ratioBrut` contre `simulation_service.dart:209` `(scoreVirtuel / totalPoids)`.
**Conséquence** : le Laboratoire **ne peut pas** servir de témoin neutre. Toute mesure du « gain apporté par un réglage » inclut un biais de base non quantifié par l'outil lui-même. L'utilisateur n'est pas informé de ce biais.
**Gravité** : **ÉLEVÉE** · **Priorité** : **P1** (même correction que BL2-A02).
**Note de regroupement** : BL2-A02 et BL2-A03 sont deux manifestations d'une **unique** cause. Elles sont conservées séparées car leurs conséquences diffèrent (échelle vs absence de témoin neutre), mais **une seule correction** les ferme.

### 1.6 Fuite de données futures / séparation apprentissage-évaluation

**Vérifié** : `simuler()` filtre sur `p.resultatsReels && p.arriveeReelle != null` (`:63-68`). Ne sont retenus que des pronostics **déjà résolus**.
`_classerSimule` relit `prono.scoresCriteres`, c'est-à-dire les scores **calculés au moment T** de l'analyse, avant connaissance du résultat.

**Conclusion** : **aucune fuite de données futures n'est démontrée**. Le score simulé n'utilise jamais l'arrivée réelle ; l'arrivée n'intervient qu'en **évaluation** (`:109-132`), ce qui est la séparation attendue.

**LIMITE** : les scores relus ont été produits par une IA **qui avait déjà appris** des courses antérieures à T. Ce n'est pas une fuite (l'apprentissage est causal), mais cela signifie que le Laboratoire mesure la performance d'une IA **entraînée sur la période évaluée** — donc une performance **optimiste** par construction. L'outil ne sépare pas apprentissage et évaluation ; il ne prétend pas le faire non plus, mais **ne l'indique pas à l'utilisateur**.

#### BL2-A04 — Aucune séparation apprentissage / évaluation, et aucune mention de ce biais

**Composant** : `SimulationService.simuler`.
**Attendu** (exigence de l'audit) : « la séparation entre données d'apprentissage et données d'évaluation ».
**Constaté** : `tous` (`:63`) inclut **toutes** les courses résolues, sans distinction. Les poids utilisés (`:57`) sont ceux **appris sur ces mêmes courses**.
**Cause** : absence de notion de période d'entraînement / période de test.
**Preuve** : aucun champ de date d'apprentissage, aucune partition dans les 288 lignes.
**Conséquence** : les métriques avant/après ne mesurent **pas** une performance hors échantillon. Le libellé `fiabiliteLabel` (`simulation_models.dart:145-150`) qualifie l'échantillon par sa **taille** uniquement (`<30`, `<50`, `<150`, `>150`), jamais par son indépendance vis-à-vis de l'apprentissage.
**Gravité** : **MOYENNE** · **Priorité** : **P2**.
**Correction proposée** : afficher un avertissement explicite (« les poids ont appris sur cet historique ») et/ou offrir une option de découpage temporel (apprentissage ≤ T, évaluation > T).
**Risque de régression** : nul (ajout d'affichage).
**Vérification** : l'avertissement doit apparaître même quand `nbCourses = 0`.

### 1.7 Reproducibilité

**Vérifié** : `simuler()` est **déterministe**. Aucun `Random`, aucun `DateTime.now()` dans la logique de calcul (seul `maintenant` sert à borner 30j/7j, `:58-60`). Deux appels consécutifs sur le même état produisent le même résultat — **démontré par lecture**, la seule dépendance externe étant l'état de `IaMemoryService` qui, lui, peut évoluer.

**LIMITE DE PREUVE** : non exécuté (aucune simulation lancée pendant l'audit, conformément aux protections). La démonstration est statique.

**Note** : `SimulationParams.reset()` (`simulation_models.dart:107`) est **jamais appelé** — grep `\.reset\(\)` filtré sur « simu » → **0 résultat**. Le bouton « Réinitialiser » de l'écran utilise `_reset()` (`simulation_screen.dart:262`), pas cette méthode. Code présent, sans consommateur.

### 1.8 Persistance, export, restauration

| Fonction | Mécanisme | Verdict |
|---|---|---|
| État du Laboratoire | `labo_ia_etat_v1` (`:132`, `:169`, `:176`) | **persistant**, restauré au démarrage (`_restaurerEtat`) |
| Pistes enregistrées | `simulation_candidates_v1` (`simulation_candidate_service.dart:10`) | **persistant**, plafonné à **50** (`:11`, `:43`) |
| Export PNG | `RepaintBoundary.toImage(2.5)` puis `SharePlus` (`:375-396`) | **fonctionnel** (partage système) |
| Export CSV/JSON des résultats | **absent** | — |
| Sauvegarde/restauration dans le backup | `backup_service.dart:545` inclut `simulation_candidates_v1` | **couvert** |
| `labo_ia_etat_v1` dans le backup | `grep "labo_ia_etat_v1" backup_service.dart` → **0 ligne** | **NON couvert** |

#### BL2-A05 — L'état expérimental du Laboratoire n'est pas sauvegardé par la sauvegarde de l'application

**Composant** : `backup_service.dart` (liste des clés) vs `simulation_screen.dart:132`.
**Constaté** : `_kEtatLabo = 'labo_ia_etat_v1'` est écrit et relu par l'écran, mais **absent** de la liste `backup_service.dart:428-551`. `simulation_candidates_v1` y figure (`:545`) ; `labo_ia_etat_v1` non.
**Preuve** : `grep -n "labo_ia_etat_v1" lib/services/backup_service.dart` → **0 ligne** (recherche explicite, résultat vide reporté comme tel).
**Conséquence** : une restauration sur nouvel appareil perd la discipline et les multiplicateurs en cours d'expérimentation. Les **pistes enregistrées** sont conservées — donc la perte est partielle et de faible portée.
**Gravité** : **FAIBLE** · **Priorité** : **P3**.

### 1.9 Sources historiques et exploitation des archives — **AUCUNE**

`SimulationService.simuler()` lit **exclusivement** `IaMemoryService.instance.pronostics` (`:33`, `:63`).
`grep "IaArchiveService\|_pronosticsDuMoisFusionnes" lib/services/simulation_service.dart` → **0 ligne**.

Conséquence : le Laboratoire est **plafonné** par la mémoire active (`_maxPronostics = 600`, `_maxPronosticsAge = 90`).
Au-delà, les courses sortent de l'échantillon **sans que l'outil l'indique**.

#### BL2-A06 — Le Laboratoire affiche une profondeur historique qu'il ne possède pas

**Composant** : `SimulationService` + libellés `fiabiliteLabel`.
**Attendu** (règle métier rappelée par le mandat) : « Tous les pronostics disposant d'un résultat officiel doivent être conservés sans limite de durée. »
**Constaté** : les blocs « historique complet », « 30 jours », « 7 jours » (`:70-71`, `:157-166`) sont présentés comme trois profondeurs. En réalité, « historique complet » = mémoire active = **au maximum 600 pronostics**, tous motifs d'éviction confondus (plafond `_maxPronostics`, `ia_memory_service.dart:130`).
**Cause technique** : le service ne consulte pas les archives permanentes, alors qu'elles contiennent précisément les pronostics évincés.
**Preuve** : `pronosticsAvecResultat` (`ia_memory_service.dart:975`) lit `_pronostics` en RAM (`grep "IaArchiveService" simulation_service.dart` → 0). Les archives sont alimentées par `_evincerAuDelaDeLaLimite` (`:2581`) et `_securiserExcedentAvantEcriture` (`:2594`).
**Conséquence métier** : l'utilisateur voit « historique complet » avec `nbCourses` pouvant être < 600 alors que son historique réel est plus long. Les **taux** (Top1/Top3/ROI) sont donc calculés sur un sous-ensemble **non signalé**.
**Aggravation** : la sélection des évincés se fait par `_pronostics.last` (`:2579`), c'est-à-dire par **ancienneté**. L'échantillon est donc **biaisé vers le récent** : la « performance historique complète » est en réalité une performance des **N dernières courses**, N ≤ 600.
**Gravité** : **ÉLEVÉE** · **Priorité** : **P1**.
**Correction proposée** : soit lire `_pronosticsDuMoisFusionnes` (déjà disponible et dédoublonné, `ia_memory_service.dart:784-830`), soit renommer le bloc « historique complet » en « mémoire active (N max) » et afficher la couverture réelle.
**Dépendances** : BL1-A09 (archives mono-lecteur) — même racine.
**Risque de régression** : nul pour l'option de renommage ; l'option archive est en lecture seule.
**Vérification après correction** : produire > 600 pronostics résolus, vérifier que `nbCourses` du bloc « historique » reflète soit 600 avec mention, soit le total réel.

### 1.10 Le tableau des « critères inactifs » est figé et peut mentir

#### BL2-A07 — Les critères « inactifs » affichés ne sont pas mesurés mais codés en dur, avec des motifs possiblement faux

**Composant** : `simulation_screen.dart:68-74` (`_critersInactifs`) et `:1070-1128` (`_buildCriteresInactifs`).
**Attendu** : la liste des critères non proposés à la simulation devrait refléter l'état réel des données.
**Constaté** : constante littérale :
```dart
const _critersInactifs = <String, String>{
  'tr':  'Terrain : données insuffisantes',
  'rp':  'Repos : fallback 50',
  'mc':  'Mouvement cote : historique absent',
  'pd':  'Place départ : non alimenté',
  'r':   'Record : non exploitable',
};
```
Le filtrage est `!_tousLesCriters.contains(e.key)` (`:1072`) : un critère est déclaré inactif quand la **variance** de ses scores observés est `< 2.0` ou quand l'échantillon fait `< 10` valeurs (`simulation_service.dart:46-49`).
**Contradiction mesurée** : `pd` (place au départ) est annoncé « non alimenté » alors que `_scorePlaceDepart` (`ia_pronostic_engine.dart:790-820`) produit des valeurs **non neutres** (65/55/47/38/62/50/45/40/58/54/48/43) dès que `placeDepartInt > 0`, alimenté par `zone_turf_service.dart:654`. Et `rp` (repos) est annoncé « fallback 50 » alors que `_scoreRepos` lit `p.scoreRepos` (`ia_pronostic_engine.dart:224`).
**Cause technique** : les motifs sont des **commentaires de développement promus en données affichées**, datés d'une version antérieure et jamais réconciliés avec le moteur.
**Preuve** : `grep -rn "_critersInactifs" lib/` → **2 occurrences**, toutes dans `simulation_screen.dart` (déclaration `:68`, usage `:1071`). Aucune mesure.
**Conséquence métier** : l'utilisateur reçoit une **explication fausse** sur la raison pour laquelle un critère n'est pas réglable. Il peut en conclure que la donnée n'existe pas alors qu'elle existe, ou l'inverse.
**Conséquence sur les autres composants** : aucune (affichage local).
**Gravité** : **MOYENNE** · **Priorité** : **P2**.
**Correction proposée** : dériver le motif de la mesure réelle (`nbValeurs`, `σ`) et supprimer la constante, ou afficher le motif comme « raison historique non revérifiée ».
**Risque de régression** : nul (affichage).
**Vérification** : un critère à variance nulle et un critère à variance forte doivent produire deux motifs distincts, tous deux **calculés**.

### 1.11 Le panneau assistant : verdicts non comparables entre eux

#### BL2-A08 — Le « score de confiance » de la piste ne mesure pas la confiance, et deux implémentations divergent

**Composant** : `simulation_assistant_panel.dart:89-123` (`_scoreConfiance`) vs `simulation_screen.dart:416-429` (`_enregistrerPiste`).
**Attendu** : une même grandeur (« score de confiance » d'une piste) devrait avoir une seule formule.
**Constaté** : **deux** formules quasi identiques mais **non identiques** :

| Élément | Assistant (`:89-123`) | Enregistrement (`:416-429`) |
|---|---|---|
| Base taille | 10 / 35 / 65 / 85 | 10 / 35 / 65 / 85 ✅ identique |
| `dTop3 > 0` | +10 | +10 ✅ |
| `dRoi > 0` | +10 | +10 ✅ |
| Malus incohérence 7j/30j | **−15** (`:107-114`) | **absent** |
| `nbModifies > 3` | −15 | −15 ✅ |
| `any(v > 1.70)` | −20 | −20 ✅ |
| Clamp | `clamp(0,100)` | `clamp(0,100)` ✅ |

**Conséquence** : une piste enregistrée peut recevoir un score **supérieur de 15 points** à celui affiché par l'assistant pour la **même** simulation. L'étiquette « confiance » ne mesure par ailleurs aucune probabilité : c'est une **note de fiabilité d'échantillon corrigée de bonus/malus heuristiques**, sans base statistique.
**Preuve** : les deux blocs de code, lus intégralement, diffèrent par la seule présence du malus 7j/30j.
**Gravité** : **MOYENNE** · **Priorité** : **P2**.
**Correction proposée** : extraire `int calculerScoreConfiance(SimulationResultat, Map<String,double>)` dans `SimulationService` et l'appeler des deux côtés ; renommer en « indice de prudence ».
**Risque de régression** : les pistes déjà enregistrées conservent leur valeur stockée (pas de recalcul).
**Vérification** : la même simulation doit produire le même entier dans les deux chemins.

### 1.12 ROI du Laboratoire : unité et cohérence

`_calcBloc` (`:143-150`) mise **1 €** par course, retourne le dividende si `top1Real == favori`, exclut du ROI les courses sans dividende exploitable (`nbCoursesRoi` distinct de `nbCourses`, `:159`).

**Conforme** : mise unitaire constante, gain net = retours − mises, ROI = gainNet/mises×100 (`:154-155`). Le dénominateur est `miseTotal` (nombre de courses **avec dividende**), et non `n` — c'est correct et **explicitement affiché** (`'Courses ROI'`, `_buildTableauComparaison`).

**Divergence avec la chaîne financière** : le Laboratoire n'utilise **ni** `GainCalculator`, **ni** `MoteurGainPmu`, **ni** `gain_mise_calculator`, **ni** `referentiel_paris_pmu`. Il traite `cotesPmuParNumero[numero]` comme un **dividende pour 1 €**. Voir BL2-A12 pour la même famille de défaut côté ROI/Value.

---

## §2 — STATISTIQUES IA : BILAN DÉTAILLÉ

### 2.1 Cartographie des statistiques par emplacement

| Emplacement | Composant | Source réelle ? |
|---|---|---|
| IA Stats → bandeau haut | `ia_performance_screen.dart:996-1160` `_buildBandeauStats` | **OUI** (`calculerStats()`) avec replis littéraux `~71%`, `~33%`, `~84%` |
| IA Stats → onglet Statistiques | `widgets/ia/ia_tab_stats.dart` | **NON** : 12 littéraux (§2.2) sauf hippodromes |
| IA Stats → onglet Statistiques → hippodromes | `:267-417` via `precisionParHippodromeAvecFiabilite` | **OUI** |
| IA Stats → onglet Statistiques → « Vos paris suivis » | `:419-473` via `alertService.trackedCourses` | **OUI** (mais catégorie différente, cf. BL2-A14) |
| IA Stats → Mémoire IA | `:1187-1553` | **OUI** |
| IA Stats → Calendrier | `ia_calendrier_tab.dart` | **OUI** (mémoire active) |
| Précision IA | `ia_precision_widget.dart` | **OUI** (`precisionParTypeAvecGrosParis`, `statsPourPeriode`) |
| Profil → Statistiques | `profile_stats_tab.dart` | **OUI** (`PmuProvider`) |
| Profil → Progression | `profile_progression_tab.dart` | **OUI** |
| Journal IA | `ia_journal_screen.dart` | **OUI** (`rapports`, `bilansSemaine`, `bilansMois`) |
| Accueil → narration | `home_screen.dart:352-473` | **OUI** (`rapports`) |
| Accueil → bulle / score | `ia_personality_service` | **OUI** (score passé en paramètre) |
| `stats_screen.dart` | — | **INACCESSIBLE** (§0.4), données provider réelles mais écran mort |

### 2.2 Les 12 littéraux fabriqués — preuve exhaustive

**Recherche** : `grep -rn "'taux' *: *[0-9]+\.[0-9]"` et `grep -rnE "'(tauxTop3|tauxGagnant)'"`.

Résultat mesuré, **12 valeurs en dur** dans **2 fichiers** :

`lib/widgets/ia/ia_tab_stats.dart:26-29` et `lib/screens/ia_performance_screen.dart:902-905` (le **même** tableau, dupliqué) :
```
Trot Attelé  : tauxTop3 73.2 / tauxGagnant 34.1
Trot Monté   : tauxTop3 68.5 / tauxGagnant 30.2
Plat         : tauxTop3 70.8 / tauxGagnant 33.5
Obstacle     : tauxTop3 65.3 / tauxGagnant 28.7
```

`lib/widgets/ia/ia_tab_stats.dart:81-84` :
```
Favori IA Gagnant     : 32.8
Favori IA Top 3       : 71.4
Top 5 contient gagnant: 84.2
Couplé IA (désordre)  : 38.4
```

`lib/widgets/ia/ia_tab_stats.dart:223` : `'IA Race Predictor', 71.4` (barre comparative)
`lib/widgets/ia/ia_tab_stats.dart:221` : `'Aléatoire', 25.0` (base de référence)
`lib/widgets/ia/ia_tab_stats.dart:233` : **« L'IA améliore vos chances de +43% par rapport à une sélection au hasard »**

Les mêmes chiffres sont **republiés** dans `ia_tab_conseils.dart:25-28` et `ia_tab_algo_conseils.dart:354-357` sous forme de conseils textuels (`~33%`, `~38%`, `71%`, `84%`).

#### BL2-A09 — L'onglet « Statistiques » de l'IA affiche des taux inventés, identiques pour tous les utilisateurs

**Composant** : `IaTabStats` (`widgets/ia/ia_tab_stats.dart`), avec doublon de la constante dans `ia_performance_screen.dart:902`.
**Attendu** : un onglet intitulé « Statistiques » doit refléter les performances réelles de l'utilisateur.
**Constaté** : **8 des 9 blocs** de l'onglet sont des constantes. Seuls les hippodromes (`:268`) et « Vos paris suivis » (`:420`) sont réels.
**Cause technique** : `_statsDiscipline` et le tableau `types` de `_buildTypesPariStats` sont des `static const`/littéraux locaux, jamais remplacés par les getters réels.
**Preuve mesurable** : les mêmes nombres apparaissent dans **4 fichiers** (`ia_tab_stats.dart:26`, `:81`, `ia_performance_screen.dart:902`, `ia_tab_conseils.dart:25`, `ia_tab_algo_conseils.dart:354`) — un utilisateur sans aucune course voit exactement les mêmes chiffres qu'un utilisateur à 500 courses.
**Aggravation** : la note de bas de page (`:69-71`) qualifie ces chiffres d'« estimations théoriques basées sur l'algorithme IA », ce qui **ne les décrit pas** : ce ne sont pas des estimations calculées, ce sont des **constantes de démonstration**.
**La donnée réelle existe pourtant** : `calculerStats()` (`ia_memory_service.dart:calculerStats`) produit `tauxParDiscipline` (par discipline) et `precisionParHippodromeAvecFiabilite` (`:977-996`, calculé et branché sur l'onglet hippodromes). `precisionParTypeÃ` (`statsParType`, `:276`) et `precisionParType` (`:285`) fournissent les taux par type de pari.
**Conséquences métier** : décision de pari fondée sur des chiffres sans rapport avec les résultats de l'utilisateur. C'est l'anomalie la plus directement **trompeuse** du BLOC 2.
**Conséquences sur les autres composants** : les Conseils (`ia_tab_conseils.dart`) et Algorithme (`ia_tab_algo_conseils.dart`) **propagent** ces valeurs sous forme de recommandations chiffrées.
**Gravité** : **CRITIQUE** · **Priorité** : **P0**.
**Correction proposée** : remplacer les 8 blocs par `calculerStats().tauxParDiscipline`, `statsParType` et `precisionParType` ; supprimer la barre « vs aléatoire » ou la calculer ; retirer la mention « +43% ».
**Dépendances** : BL2-A10 (duplication de la constante), BL2-A13 (conseils chiffrés).
**Risque de régression** : nul sur l'IA — ce sont des remplacements d'affichage. Risque d'affichage « vide » quand `coursesAvecResultat < 3` → prévoir un état vide explicite (le badge `hasData` existe déjà, `:932`).
**Vérifications nécessaires après correction** : (a) utilisateur sans donnée → écran vide explicite, aucun chiffre ; (b) `calculerStats()` avec 10 courses → les 4 disciplines affichent leurs taux réels ; (c) plus aucune occurrence des 12 littéraux (`grep`).

#### BL2-A10 — La même constante statistique est dupliquée dans deux fichiers

**Composant** : `ia_tab_stats.dart:26-29` **et** `ia_performance_screen.dart:902-905`.
**Preuve** : les deux blocs sont identiques au caractère près, y compris les couleurs `0xFF4CAF7D`/`0xFF66BB6A`/`0xFF42A5F5`/`0xFFFFB74D`.
**Constaté** : la copie de `ia_performance_screen.dart` est annotée `// ignore: unused_field` — donc **le linter la sait inutilisée**, mais elle reste dans le binaire.
**Conséquence** : toute correction de BL2-A09 sur un seul fichier laissera l'autre valeur en place, prête à être re-branchée par erreur.
**Gravité** : **FAIBLE** (doublon) mais **dépendance bloquante** de BL2-A09 · **Priorité** : **P2**.


---

# §3 — FILTRES, PÉRIODES ET ACTUALISATION (mandat §4)

## 3.1 Périmètre des périodes par outil BLOC 2

| Outil | Périodes proposées | « Aujourd'hui » temps réel ? | Période personnalisée ? | Persistance du filtre |
|---|---|---|---|---|
| `IaPrecisionWidget` (`ia_precision_widget.dart:465-518`) | défaut / `all` / `7j` / `today` / `custom` | **OUI** — `precisionAujourdhuiDepuisPronostics` | **OUI** | non (état volatil) |
| `RoiValueScreen` (`roi_value_screen.dart:65`) | `complet` / `30j` / `7j` | **NON** — notion absente | **NON** | **non** — 0 `SharedPreferences` |
| `SimulationScreen` | `Toutes/Plat/Trot/Obstacle` (discipline), pas de période | sans objet | sans objet | `labo_ia_etat_v1` |
| `IaTabBacktesting` | `_btJours` (N jours) | non | non | `bt_*` |
| `IaTabStats` | aucune | — | — | — |
| `IaTabAudit` / `Morts` / `Corrélations` / `Discipline` | aucune (tout l'historique mémoire) | — | — | cache `ia_audit_cache_v1` |

## 3.2 Conformité de `IaPrecisionWidget` aux règles du mandat — VÉRIFIÉE

Lecture `ia_precision_widget.dart:465-518` :

- `'7j'` : `debut6j = today − 6 j`, `fin6j = today − 1 ms`, puis **ajout explicite** de
  `precisionAujourdhuiDepuisPronostics` → **6 jours historiques + aujourd'hui temps réel**. Conforme.
- `'today'` : source **unique** `precisionAujourdhuiDepuisPronostics` (l'historique complet n'étant pas encore
  mis à jour pendant la journée). Conforme.
- `'custom'` : `statsPourPeriode(debut, fin)` puis, **si et seulement si** `_filtreFin >= todayD`, ajout du
  temps réel. Une période passée (`_filtreFin.isBefore(todayD)`) retourne les stats seules → **aucune
  contamination d'une période historique par aujourd'hui**. Conforme.

**Conclusion** : sur cet outil, les trois règles du mandat sont respectées. Les bornes sont calculées sur
`DateTime(y,m,d)` (minuit local), pas sur un `now()` glissant.

## 3.3 `RoiValueService` — période glissante, pas de calendrier

`roi_value_service.dart:80-86` :
```dart
if (f.periode != 'complet') {
  final days = f.periode == '7j' ? 7 : 30;
  final limite = DateTime.now().subtract(Duration(days: days));
  if (p.datePronostic.isBefore(limite)) return false;
}
```
`now() − 7 j` inclut aujourd'hui et les 6 jours précédents → **équivalent fonctionnel** de la règle
« 6 jours + aujourd'hui ». Mais la borne est un **instant** (`now()`), pas une date : un pronostic du jour J−7
à 14 h 00 est exclu à 14 h 01 le jour J, alors qu'un pronostic de J−7 à 18 h 00 y est encore. La fenêtre
**rétrécit progressivement dans la journée** et le même écran, rafraîchi deux fois, ne donne pas le même
total. C'est une différence mesurable avec `IaPrecisionWidget` qui, elle, borne à minuit.

**BL2-A22 — `RoiValueService` : fenêtre glissante à l'instant, pas au jour ; ni « Aujourd'hui » ni période
personnalisée ; filtres non persistés.**
- *Composant* : `RoiValueService._filtrer` — `roi_value_service.dart:80-86`.
- *Fichier/fonction* : `_filtrer(RoiValueFilters f)`.
- *Lignes* : 80-86 (borne), `roi_value_screen.dart:65` (liste des périodes), 0 occurrence de
  `SharedPreferences` dans tout `roi_value_screen.dart` (vérifié par grep : une seule ligne, un **commentaire**
  en l.7).
- *Comportement attendu* : bornes journalières, cohérence avec les autres outils, et un filtre qui survit à une
  navigation.
- *Comportement observé* : borne à `now()` (fenêtre rétrécissante) ; `7j`/`30j`/`complet` seulement ;
  tout filtre est perdu en quittant l'écran.
- *Cause* : `DateTime.now()` au lieu de `DateTime(y,m,d)`.
- *Preuve* : lecture l.80-86 ; grep `SharedPreferences` sur `roi_value_screen.dart` → 1 ligne, commentaire.
- *Gravité* : **FAIBLE** · *Priorité* : P3.
- *Conséquence* : un ROI « 7 j » de 12 h 00 et celui de 18 h 00 peuvent différer sans qu'aucune course ne soit
  arrivée. L'utilisateur ne peut pas reproduire un chiffre qu'il a lu une heure plus tôt.
- *Correction proposée* : aligner la borne sur `DateTime(y,m,d)` et ajouter `RoiValueFilters` à
  `labo_ia_etat_v1`/une clé dédiée.

## 3.4 Actualisation, cache et fraîcheur

| Mécanisme | Déclencheur | Preuve | État |
|---|---|---|---|
| `IaAuditCacheService.isCacheValid(n)` | comparaison `cached == n` | `ia_audit_cache_service.dart:36-41` | **insuffisant** → BL2-A18 |
| Invalidation audit | `nbNouveauxResultats > 0` | `ia_memory_service.dart:5059` | correct sur ce chemin |
| Bouton « Recalculer » | `invalidate()` + `_refreshKey++` | `audit_screen.dart` | correct, manuel |
| Recalcul narratif du jour | `reason == 'analyseJournee'` | `ia_narrative_memory_service.dart` | correct |
| `IaTabMethodologie` | listener `IaMemoryService` | `ia_tab_methodologie.dart:30/35` | correct |
| `IaTabStats` | **aucun** | statique | BL2-A09 |
| `RoiValueService` | **aucun cache** | recalcul à chaque `build` | redondance, non mesurée |

**BL2-A18 — Le cache d'audit valide par simple égalité de compteur.**
- *Composant* : `IaAuditCacheService`.
- *Fichier/fonction* : `isCacheValid` — `ia_audit_cache_service.dart:36-41`.
- *Lignes* : 36-41.
- *Attendu* : invalidation si le contenu a changé.
- *Observé* : `_prefs` stocke `nbPronosticsAvecResultat` ; la validité est `cached == n`. Deux états de même
  cardinalité mais de contenu différent (un pronostic évincé + un nouveau, ou une arrivée corrigée sans
  variation de nombre) servent le **cache périmé**.
- *Cause* : absence d'empreinte de contenu.
- *Preuve* : lecture intégrale du fichier (81 lignes) ; `_empty()`, `readCache`, `isCacheValid`, `writeCache`.
- *Gravité* : **MOYENNE** · *Priorité* : P2.
- *Conséquence* : les 4 onglets de l'écran Audit peuvent afficher un diagnostic calculé sur un historique qui
  n'existe plus. Le libellé « Dernière mise à jour » (`audit_screen.dart`) ne lève pas l'ambiguïté.
- *Correction proposée* : ajouter un hash de contenu (liste des `courseKey` + `dateResultat`) à la clé de
  validité. **Aucune modification du calcul** — seulement de la condition de fraîcheur.
- *Dépendance* : BL2-A17 (mêmes onglets).

---

# §4 — STATISTIQUES GÉNÉRALES, ROI ET VALUE (mandat §5)

## 4.1 Séparation IMPÉRATIVE des 5 catégories

| Catégorie | Où elle existe | Où elle est mélangée |
|---|---|---|
| ① Paris réellement joués | `ProfileStatsTab` (`totalMise`, `totalGainsNet`, `totalRemboursements` — provider réel) ; `IaTabStats._buildMesParis` (`alertService.trackedCourses`, réel) | — |
| ② Pronostics historiques non joués | `RoiValueService.calculerResume` (mise **virtuelle** 1 €/pari) | **Mélangé avec ① dans le même écran** que `ProfileStatsTab` sans être nommé « virtuel » sur chaque carte |
| ③ Simulations théoriques | `SimulationService` (1 €/course, ROI) ; `_lancerMartingale` | — |
| ④ Performances rétrospectives sur dividends PMU officiels | **n'existe pas dans le BLOC 2** — `RoiValueService` n'utilise jamais `dividende` | La place est occupée par ② présenté comme un ROI financier |
| ⑤ Estimations de gain avant course | `Best Bet` / `GainCalculator` (BLOC 1, BL1-A11) | — |

**Constat** : la catégorie ④ est **absente** du BLOC 2. `RoiValueService` propose un « ROI » qui n'est ni un
ROI sur paris joués, ni un ROI sur rapports officiels : c'est un ROI sur pronostics avec une mise virtuelle de
1 € et un retour **modélisé par la cote du favori** (voir 4.2). Les 5 catégories ne sont donc pas mélangées
entre elles — mais la catégorie affichée sous le nom « ROI » **n'est correctement couverte par aucune des cinq
définitions du mandat**.

## 4.2 **BL2-A12 — CRITIQUE / P0 : le ROI/Value est aveugle au type de pari et contourne la chaîne financière stabilisée**

- *Composant* : `RoiValueService.calculerResume` + les 3 détecteurs (`detecterValue`, `analyserOutsiders`,
  `detecterFauxFavoris`).
- *Fichier/fonction* : `lib/services/roi_value_service.dart`, `calculerResume(RoiValueFilters f)`.
- *Lignes* : **178-193** — cœur du défaut en **184** :
  ```dart
  mises += 1.0;
  final gagne = _estBon(p);            // ← conscient du TYPE de pari
  if (gagne) { retours += cote; ... }  // ← cote = _coteFavori(p) : cote du FAVORI IA
  ```
  et `_coteFavori` (`:99-108`) qui retourne `cotesPmuParNumero[favoriIA]`, c.-à-d. **la cote du cheval
  favori**, une cote « gagnant simple ».
- *Comportement attendu* : un retour qui dépend du type de pari conseillé. Un `Quinté+` gagnant rapporte le
  rapport de la combinaison (typiquement 40× à 1 000×), un `Couplé Placé` rapporte son rapport propre, un
  `Simple Placé` rapporte le rapport placé du cheval (≈ 1/3 du gagnant).
- *Comportement observé* : **le même retour, la cote du favori, pour les 7 types**. Le calcul est
  `retours += coteFavori` quel que soit `p.typePariConseille`. La branche « gagné/perdu » est, elle, correcte
  et type-aware (`_estBon` → `_estBonConseilParType`, `ia_memory_service.dart:5548-5680`). Le **numérateur est
  donc juste, le montant du retour est faux.**
- *Cause technique* : le service n'appelle **aucune** brique de la chaîne financière. Vérifié par lecture
  intégrale des 389 lignes : 0 occurrence de `GainCalculator`, 0 de `MoteurGainPmu`, 0 de
  `GainMiseCalculator`, 0 de `referentiel_paris_pmu`. Le seul montant produit est `retours += cote`.
- *Preuve* : lecture l.99-108 (`_coteFavori`), l.141-208 (`calculerResume`), l.184 (affectation). Grep des
  quatre symboles financiers dans le fichier → **0 ligne** (résultat vide, rapporté explicitement comme preuve
  de non-usage, sans en tirer une conclusion de code mort : le fichier est bien exécuté).
- *Conséquences métier* :
  1. Le ROI affiché est **structurellement sous-estimé** pour tout type multi-chevaux : un Quinté+ gagnant
     compté à ~4 € au lieu du rapport réel, un Couplé Placé à ~4 € au lieu de son rapport.
  2. La **symétrie mise/retour est rompue** : 1 € misé pour un Quinté+ (mise réelle PMU : 2,60 € minimum en
     base) et 1 € retourné × cote favori.
  3. L'onglet « 🎯 Type de pari » (`roiParTypePari`, `:225-235`, 7 types) **compare 7 types avec le même
     modèle de retour** → la comparaison ne mesure pas la rentabilité des types, elle mesure la fréquence à
     laquelle le favori gagne. Un type structurellement plus souvent « bon » paraît meilleur, indépendamment
     de son rapport.
- *Conséquences sur les autres composants* : `detecterValue` (`:243-280`), `analyserOutsiders` (`:287-334`) et
  `detecterFauxFavoris` (`:341-370`) n'utilisent pas le ROI mais `_estBon` ; leur **liste** est correcte.
  En revanche les bandeaux de synthèse de ces 3 onglets exposent des `retour` unitaires (`ValueOpportunity.
  retour`, `OutsiderAnalyse`) calculés sur la même cote favori.
- *Note affichée* : `roi_value_screen.dart:503` — « 💡 ROI calculé sur mise virtuelle de 1 € par pari.\nSeuls
  les pronostics avec cote PMU disponible sont inclus. » Cette note mentionne la mise, **jamais le retour
  modélisé ni l'absence de rapport officiel**.
- *Gravité* : **CRITIQUE** — un indicateur financier faux est présenté comme un ROI. · *Priorité* : **P0**.
- *Correction proposée* : router le retour par la chaîne existante (`MoteurGainPmu` / `GainCalculator`) selon
  `p.typePariConseille` et le rapport officiel quand il existe ; à défaut, **afficher « retour non établi »**
  au lieu d'un montant. Le libellé « ROI » doit être remplacé par « ROI théorique (cote favori) » tant que la
  correction n'est pas faite.
- *Dépendances* : **BL1-A11** (même famille : `mise × cote` présenté comme gain pour tous les types),
  **BL1-A12** (cote de repli 2,5 / 4,5). La correction devra être groupée avec BL1-A11.
- *Risque de régression* : **ÉLEVÉ** — `test/v41_a44_abstention_stats_test.dart` **verrouille** le
  comportement actuel (voir §8.3). Toute correction fera échouer `A4-4-T9`, qui devra être réécrit en même
  temps — ce qui est interdit en l'état par le mandat (aucune modification de test). **La correction exige donc
  l'accord explicite de l'utilisateur sur la réécriture de `A4-4-T9`.**
- *Vérifications après correction* : recalcul d'un jeu de 10 pronostics dont 1 Quinté+ gagnant, 1 Couplé Placé
  gagnant, 1 Simple Gagnant gagnant → 3 retours distincts et non nuls ; non-régression des 3 détecteurs.

## 4.3 Remboursements et mises — vérification ciblée

- `RoiSummary.mises = nbParisRoi × 1,0` (`roi_value_models.dart`), `nbParisRoi` incrémenté **seulement** si
  une cote existe (`:175-176`). Un pronostic sans cote n'ajoute donc ni mise ni retour → **cohérent** (le
  dénominateur exclut les deux). Le libellé « Seuls les pronostics avec cote PMU disponible sont inclus »
  couvre ce point.
- Les abstentions (`typePariConseille == 'À surveiller'`) sont **exclues** avant `nbCoursesPariees++`
  (`:172`) → non comptées comme paris perdants. Conforme, et testé (`A4-4-T7`).
- **Remboursements** : le mot `remboursement` n'apparaît **pas** dans `roi_value_service.dart` (grep → 0).
  Les remboursements PMU (non-partants, faux départ) ne sont donc **ni comptés comme gains, ni neutralisés**.
  Un pronostic dont le cheval a été déclaré non-partant et remboursé est compté **perdant** si la cote existe.
  **C'est conforme à l'exigence « les remboursements ne doivent pas être comptabilisés comme des gains », mais
  crée une imprécision opposée** (une perte fictive). À signaler comme **limite de preuve**, pas comme
  anomalie distincte : l'objet `IaPronostic` ne porte aucun indicateur de remboursement (vérifié sur la liste
  des champs, `ia_memory_models.dart:271-390`), donc **le service n'a pas la matière** pour le faire.
- **Conclusion §4.3** : sur les deux exigences littérales du mandat, **conforme**. Le défaut réel est le
  montant du retour (BL2-A12).

## 4.4 Les 5 définitions concurrentes du « taux de réussite » — **BL2-A14**

| # | Où | Formule | Dénominateur | Sémantique réelle |
|---|---|---|---|---|
| 1 | `calculerStats().tauxFavoriGagnant` | `rangFavoriIa == 1` | courses avec résultat | favori gagnant |
| 2 | `calculerStats().tauxParDiscipline` | **`rang <= 3`** | courses de la discipline | **TOP 3** — utilisé sous le libellé « Gagnant » |
| 3 | `StatsPrecisionParType.tauxReussite` | `_estBonConseilParType` (type-aware) | `nbTotal` par type | « bon conseil » selon le pari |
| 4 | `RoiSummary.tauxReussite` | `gagnants / nbParisRoi` | **sous-échantillon avec cote** | « bon conseil parmi ceux qui ont une cote » |
| 5 | `home_screen:386` `taux7j` | **moyenne non pondérée** des taux journaliers | nombre de jours | moyenne de moyennes |

- *Preuve* : `ia_memory_service.dart` (`calculerStats()`), `roi_value_service.dart:195-207`,
  `home_screen.dart:375-387`, `ia_tab_stats` (usage de `tauxParDiscipline` sous le libellé « Gagnant »).
- *Anomalie* : (2) est affiché comme un **taux de gagnant** alors que le prédicat est `rang <= 3`. (5) est une
  moyenne de moyennes : un jour à 1 course pèse autant qu'un jour à 40 courses → un « taux 7 j » de 71 % peut
  être obtenu avec 7 fois 1 course. (3) et (4) portent le **même nom** avec des dénominateurs différents.
- *Gravité* : **ÉLEVÉE** · P1. *Conséquence* : deux écrans annoncent « 33 % » et « 71 % » pour la même IA sans
  que l'utilisateur puisse savoir qu'il s'agit de deux grandeurs distinctes.
- *Différence justifiée ?* : (1) vs (3) **oui** — gagnant brut vs bon conseil par type sont deux objectifs
  métier réels. (2) sous libellé « Gagnant » **non**. (5) **non** : une moyenne de moyennes n'est pas un taux.
- *Correction proposée* : renommer (2) « Top 3 », agréger (5) en ratio poolé (`Σbons / Σcourses`).

---

# §5 — ARCHIVES PERMANENTES ET PROFONDEUR HISTORIQUE (mandat §6)

## 5.1 Mesure : quel outil BLOC 2 lit l'archive ?

Grep de `IaArchiveService` dans les **8 fichiers BLOC 2** de calcul :

```
simulation_service.dart          → 0 ligne
roi_value_service.dart           → 0 ligne
ia_tab_stats.dart                → 0 ligne
ia_narrative_engine.dart         → 0 ligne
ia_tab_audit.dart                → 0 ligne
ia_tab_criteres_morts.dart       → 0 ligne
ia_tab_correlations.dart         → 0 ligne
ia_tab_discipline.dart           → 0 ligne
```
(grep exécuté fichier par fichier, sortie vide pour chacun — rapporté explicitement.)

Consommateurs réels de `IaArchiveService`, tous fichiers confondus :
`main.dart:89` (`charger`), `backup_service.dart:847/1657`, `ia_memory_service.dart` (écriture + les deux
lectures métier), `ia_calendrier_tab.dart:182/183/191/213`.

**Conclusion mesurée : 0 outil du BLOC 2 ne lit l'archive.** Le seul consommateur métier reste
`_pronosticsDuMoisFusionnes` → `donneesCalendrierJour`, c.-à-d. le **Calendrier** (onglet 3 de la Mémoire IA,
hors périmètre BLOC 2 strict, déjà couvert par BL1-A09).

## 5.2 Conséquence par outil

| Outil BLOC 2 | Mémoire seule ? | Archive ? | Fusion ? | Déduplication ? | Respecte la période ? | Affiche une profondeur > réelle ? | Statistique incomplète sans le dire ? |
|---|---|---|---|---|---|---|---|
| `SimulationService` | oui | non | — | — | `30j`/`7j` sur `datePronostic` | **OUI** — « complet » = 600 max | **OUI** |
| `RoiValueService` | oui | non | — | — | `complet`/`30j`/`7j` | **OUI** | **OUI** |
| `IaTabStats` | oui (hippodromes) | non | — | — | aucune | partiel | **OUI** |
| `IaTabBacktesting` | oui | non | — | — | `_btJours` | **OUI** | **OUI** |
| `IaTabAudit` | oui | non | — | — | aucune | **OUI** | **OUI** |
| `IaTabCriteresMorts` | oui | non | — | — | aucune | **OUI** | **OUI** |
| `IaTabCorrelations` | oui | non | — | — | aucune | **OUI** | **OUI** |
| `IaTabDiscipline` | oui | non | — | — | aucune | **OUI** | **OUI** |
| `IaNarrativeEngine` | oui (via rapports) | non | — | — | 7 j / 14 j | non | non |

## 5.3 **BL2-A06 — ÉLEVÉE / P1 : profondeur historique annoncée > profondeur réelle, sur les 8 outils BLOC 2**

- *Composant* : tous les outils ci-dessus, via `IaMemoryService.pronosticsAvecResultat` (`:975`) et
  `IaMemoryService.pronostics`.
- *Cause* : `_maxPronostics = 600` (`ia_memory_service.dart:130`), éviction du **plus ancien**
  (`_evincerAuDelaDeLaLimite`, `:2572-2583`, `_pronostics.last`). Toute lecture par `pronostics` ou
  `pronosticsAvecResultat` est donc bornée à ~600 fiches, soit **8 à 20 jours** selon le rythme de courses.
- *Preuve* : lecture des deux constantes et de l'éviction ; grep `IaArchiveService` → 0 dans les 8 fichiers.
- *Conséquences* :
  1. Un filtre `30j` ou `complet` sur `RoiValueScreen` **ne peut pas** couvrir 30 jours si l'éviction a déjà
     eu lieu. Le libellé « complet » est **faux** : il signifie « tout ce qui reste en mémoire ».
  2. `SimBloc.fiable` exige `nbCourses >= 50` (`simulation_models.dart`). Avec ~40 courses/jour, 600 fiches
     ≈ 15 jours : le seuil est atteignable, mais **le sous-échantillon est biaisé vers les jours récents**,
     donc vers les poids **les plus récemment appris** — ce qui **favorise artificiellement** toute
     configuration proche de l'état courant (voir aussi BL2-A04).
  3. Aucun de ces outils n'affiche « N pronostics disponibles sur la période demandée ». L'utilisateur ne peut
     pas distinguer « 0 bon résultat » de « 0 donnée ».
- *Gravité* : **ÉLEVÉE** · P1. *Déjà identifiée comme conséquence* de **BL1-A09** (l'archive n'alimente aucun
  outil de mesure) — **mais BL1-A09 est une anomalie d'architecture, BL2-A06 en est la conséquence mesurée sur
  les outils du BLOC 2**. Conformément au mandat §10 (« ne pas créer une nouvelle anomalie quand ce n'est
  qu'une conséquence »), **BL2-A06 est rattachée à BL1-A09** et ne doit pas être comptée deux fois dans le
  décompte de gravité : elle est listée ici pour la traçabilité, avec renvoi à BL1-A09.
- *Correction proposée* : **aucune dans le BLOC 2** — la correction est celle de BL1-A09 (décision
  d'architecture). À défaut, **renommer « complet » en « mémoire disponible »** et afficher le nombre de
  pronostics réellement couverts.

## 5.4 Cohérence avant/après archivage d'un pronostic

Un pronostic qui quitte la mémoire (éviction) **disparaît simultanément** de : Simulation, ROI/Value,
Backtesting, Audit, Morts, Corrélations, Discipline, Stats hippodromes, et des rapports journaliers
(`RapportJournalier` est calculé depuis les pronostics — voir `calculerRapportHebdo`). Il **reste** visible
dans le Calendrier mensuel et dans les séries premium (`versionRetenue`).

**Conséquence mesurable** : le même jour J, le taux affiché par le Calendrier et celui affiché par
`IaTabStats` peuvent diverger **parce que le premier lit l'archive et le second non**. C'est exactement
**BL1-A10** (incohérence interne à l'onglet Calendrier) étendue au-delà du Calendrier : la divergence n'est
plus interne à un onglet, elle est **inter-écrans**. Anomalie complétée, non recréée.

## 5.5 Règle métier « tous les pronostics avec résultat officiel conservés sans limite »

Vérifiée : `_securiserExcedentAvantEcriture` (`:2590-2600`) et `enregistrerEviction` (archivage) assurent que
l'éviction **archive** au lieu de détruire. La purge à 90 jours (`_maxPronosticsAge`, `:132`) s'applique aux
pronostics **sans** résultat dans le flux d'éviction observé. **Aucune destruction de résultat officiel n'a été
démontrée.** La règle métier est respectée sur le plan de la conservation ; elle est **violée sur le plan de
l'exploitation** (aucun outil de mesure ne relit l'archive) — ce qui est BL1-A09.

---

# §6 — IA INTERACTIVE : INVENTAIRE INTÉGRAL (mandat §7)

## 6.1 Ce qui existe réellement

| Brique | Fichier | Lignes | Nature |
|---|---|---|---|
| `IaNarrativeEngine` | `ia_narrative_engine.dart` | 273 | générateur de phrases à **templates** |
| `IaNarrativeContext` | `ia_narrative_models.dart` | 158 | sac de valeurs + getters booléens |
| `IaNarrativeMemoryService` | `ia_narrative_memory_service.dart` | 323 | cache quotidien + anti-répétition |
| `ia_narrative_templates.dart` | `data/` | 234 | **~40 templates** figés |
| `IaPersonalityService` | `ia_personality_service.dart` | 466 | prénom, avatar, messages **codés en dur** |
| `IaSpeechWidget` | `widgets/ia/` | 96 | affichage d'une phrase de confiance |
| `IaBubbleWidget` | `widgets/ia/` | 319 | bulle victoire/défaite/niveau |

## 6.2 Ce qu'elle ne possède PAS — preuve par grep vide

Recherche des symboles d'un agent conversationnel dans **tout `lib/`** :
`IaChat`, `ia_chat`, `chatbot`, `_repondre`, `_askIa`, `_questionUtilisateur`, `TextField` associé à un
envoi de question, `onSubmitted` vers un service de réponse → **aucune occurrence pertinente**.

**Conclusion** : l'« IA interactive » est un **générateur de phrases à gabarits**. Elle ne comprend aucune
question, n'exécute aucune commande, ne consulte aucun outil, ne déclenche aucun service et **n'écrit dans
aucune donnée de production** (0 `SharedPreferences` de données métier ; seules clés écrites :
`ia_narrative_memory_v1`, `ia_narrative_daily_cache_v1` — cache de phrases, exporté par la sauvegarde
`backup_service.dart:428/431`).

## 6.3 Inventaire des « capacités » revendiquées vs réelles

| Revendication implicite (contexte/template) | Réalité |
|---|---|
| Comparer le ROI du jour à celui d'hier | **impossible** — `roiJour: 0`, `roiHier: 0` figés (`home_screen.dart:462-471`) ⇒ `progressionJour`/`regressionJour` toujours neutres |
| Nommer le **widget premium** le plus stable | **impossible** — `widgetPremiumLePlusStable: ''` figé ⇒ `widgetStableV3` jamais émis |
| Signaler le type de pari le **plus instable** | **impossible** — `typePariLePlusInstable: null` figé ⇒ branche jamais atteinte |
| Comparer la tendance 7 j à la précédente | possible (calculée, `home_screen.dart:375-387`) mais en **moyenne de moyennes** (BL2-A14-5) |
| Nommer la meilleure discipline | possible, sur **14 jours glissants** en moyenne de taux |
| Détecter une série premium | possible (`calculerStreakPremium`, lit l'archive) |
| Se souvenir de ses phrases pour ne pas se répéter | **oui** (`sauvegarderTemplates`, `usedIds`) |

## 6.4 **BL2-A15 — MOYENNE / P2 : quatre champs du contexte narratif sont figés par l'appelant**

- *Composant* : `IaNarrativeContext` + `home_screen._buildContextNarratifAccueil`.
- *Fichier/lignes* : `home_screen.dart:454-472` — `roiJour: 0, roiHier: 0,
  widgetPremiumLePlusStable: '', typePariLePlusInstable: null` (constantes littérales).
- *Attendu* : les 4 champs alimentent des templates et des getters (`progressionJour`, `widgetLibelle`,
  `aTypePari`) — ils devraient porter les valeurs du jour.
- *Observé* : les branches correspondantes sont **structurellement inatteignables**. Les templates
  `widget_1/2`, `v3_widget_1/2/3`, `premium_*` partiellement, et toute phrase comparant le ROI ne seront
  **jamais** produits.
- *Cause* : le constructeur est appelé avec 4 littéraux neutres ; aucune lecture de `rapportJour.roi` /
  `rapportHier.roi` n'est faite alors que `rapportJour` et `rapportHier` sont **déjà** chargés deux lignes
  au-dessus.
- *Preuve* : lecture `home_screen.dart:352-473` ; les getters concernés dans `ia_narrative_models.dart`.
- *Conséquence* : **fonctionnalité incomplète présentée comme complète** ; le catalogue de templates contient
  des phrases mortes. Ce n'est **pas** un mensonge à l'utilisateur (les phrases ne s'affichent pas), c'est du
  **code potentiellement inutilisé** — à classer « incomplet », pas « trompeur ».
- *Gravité* : **MOYENNE** · P3 (aucun impact chiffré, uniquement une capacité annoncée par le code et le jeu de
  templates qui n'existe pas).
- *Correction proposée* : passer les 4 valeurs réelles ; ou **retirer** les 4 champs et les templates
  correspondants. Aucun impact sur les poids, seuils ou scores.
- *Dépendance* : aucune.

## 6.5 Générateur de messages de `IaPersonalityService` — un orphelin

`messageMatin()` (`:372`) n'a **qu'un appelant interne** (`:449`). Aucun écran ne l'invoque. Les autres
messages (`messageVictoire`, `messageDefaite`, `messageApresAnalyse`, `messageMonteeNiveau`, `messageBulle`)
sont consommés (`main.dart`, `home_screen`, `ia_journal_screen`, `ia_performance_screen:806/838`,
`mes_paris_screen:1753/1759`, `widget_service:182`). `messageMatin` est **potentiellement inutilisé** — un grep
vide ne prouve pas l'absence d'appel dynamique (limite de preuve explicite), mais aucun `Function`/`dynamic`
n'a été trouvé dans les appelants listés.

## 6.6 Effets de bord

Aucune écriture de production. Les deux seules écritures sont un **cache de phrases** et un **compteur
d'anti-répétition**, tous deux exportés par la sauvegarde. **Aucun side-effect sur poids, seuils,
apprentissage, TOP3, pronostics ou résultats.** Vérifié par lecture des 273 lignes du moteur : aucun
`poids.X =`, aucun `.normaliser()`, aucun `enregistrerPronostic`.

## 6.7 Limites déclarées (pour l'agent indépendant futur)

- Ne répond à aucune question libre.
- Ne peut pas citer une course précise par son nom dans une phrase comparative.
- Ne connaît que les agrégats **journaliers** (`RapportJournalier`) et **hebdomadaires** (`RapportHebdo`),
  jamais le détail d'une fiche.
- Sa « fraîcheur » est celle du cache du jour (`obtenirOuGenererNarratifDuJour`), rafraîchi sur
  `reason == 'analyseJournee'`.
- Aucune traçabilité de la **source** d'une phrase n'est exposée à l'utilisateur (le champ `templateIds` existe
  en mémoire mais n'est pas affiché).

---

# §7 — OUTILS DE VÉRIFICATION, TEST, ÉVALUATION ET DIAGNOSTIC (mandat §8)

## 7.1 Inventaire exhaustif

| # | Outil | Fichier | Ce qu'il prétend contrôler | Ce qu'il contrôle réellement | Données | Conclusion fiable ? |
|---|---|---|---|---|---|---|
| 1 | Onglet **19 Critères** | `ia_tab_audit.dart` (570 l.) | utilité de chaque critère | `delta = moyTop3 − moyHorsTop5` par critère | `scoresCriteres` des pronostics **avec résultat** | **partielle** — aucune exclusion des critères morts (voir 7.2) |
| 2 | Onglet **Morts** | `ia_tab_criteres_morts.dart` (524 l.) | critères morts | **proxy `score == 50.0`** compté comme « fallback » | idem | **NON** → BL2-A11 |
| 3 | Onglet **Corrélations** | `ia_tab_correlations.dart` (641 l.) | doublons de critères | Pearson sur `toJson()` (clés courtes) ; exclut σ<2.0 | idem | **oui** sur le plan méthodologique (exclusion documentée, seuils cohérents) |
| 4 | Onglet **Discipline** | `ia_tab_discipline.dart` (864 l.) | utilité par discipline | `delta = moyT3 − moyHt5` ; exclut σ<2.0 et <30 valeurs | idem | **oui**, mais **règles différentes** de l'onglet 1 → BL2-A17 |
| 5 | Bouton **Recalculer** | `audit_screen.dart` | fraîcheur | `invalidate()` + remount | prefs | oui |
| 6 | `IaTabMethodologie` | 641 l. | ce que fait l'IA | **affiche les poids réels** (`instance.poids`) + un tableau **de défauts codé en dur** | `poids` + journal | **partielle** → BL2-A13 bis |
| 7 | `IaTabBacktesting` (service) | `backtesting_service.dart` | ROI des stratégies | simulation à cote de repli **4,5** | `pronosticsAvecResultat` | partielle (BL1-A12) |
| 8 | `_lancerMartingale` | `ia_tab_backtesting.dart:351-420` | gain d'une martingale | **Gagnant seul**, cote de repli **2,5** | idem | **non représentatif** (BL1-A12) |
| 9 | `_buildTraceabiliteBacktesting` | `:1466` | écart simulation ↔ Premium | croise `premiumsPourDate` | idem | oui, mais dépend de BL1-A13 |
| 10 | `IaPrecisionWidget` | 2051 l. | précision par type | `StatsPrecisionParType` (60 j + all + 7 j + today + custom) | `historiqueComplet` | **oui** (périodes conformes, §3.2) |
| 11 | `SimulationAssistantPanel` | 925 l. | cohérence d'une simulation | `_alerteIncoherence` 7 j/30 j + `_alerteSurApprentissage` | `SimulationResultat` | **partielle** → BL2-A08 |
| 12 | `IaCalibrationRegistry` | service | calibration | score de calibration 10–90 | pronostics | oui (hors périmètre BLOC 2) |
| 13 | Détecteurs ROI/Value | `roi_value_service.dart` | value / outsiders / faux favoris | 3 listes type-aware | `pronosticsAvecResultat` | **liste oui, montants non** (BL2-A12) |
| 14 | `_buildDiagnosticConvergence` | `ia_tab_methodologie.dart:213-...` | « l'IA apprend-elle vraiment ? » | compare `defauts` codés en dur ↔ `poids` réels sur l'historique du journal | `journal` | **comparable à un mauvais référentiel** → 7.3 |

## 7.2 **BL2-A11 — MOYENNE / P2 : l'onglet « Morts » peut déclarer mort un critère qui fonctionne**

- *Composant* : `IaTabCriteresMorts._calculer()`.
- *Fichier/lignes* : `lib/widgets/ia/ia_tab_criteres_morts.dart:123-132` — décision en **127** :
  ```dart
  if (val == 50.0) { nbFallback[crit]++; } else { nbReel[crit]++; }
  ```
- *Attendu* : distinguer « critère jamais alimenté » de « critère alimenté mais neutre ».
- *Observé* : `50.0` est la **valeur neutre légitime** de plusieurs critères du moteur :
  - `_scorePlaceDepart` retourne **exactement 50.0** pour « Galop longue distance ou type non concerné »
    (`ia_pronostic_engine.dart:819`, `return 50.0;` commenté comme « VALEUR NEUTRE LÉGITIME ») ;
  - `scorePoids` retourne **50.0** hors galop (`:256`) ;
  - `scoreMouvCote` retourne **50.0** hors de la fenêtre de 30 min (`:54`).
  Un critère parfaitement alimenté sur une sous-population est donc compté « fallback » sur le reste, et le
  seuil `statut` (`>=80 Vivant / >=40 Partiel / >=10 Faible / <10 Mort`, `:499-511`) peut le faire basculer
  **Mort** ou **Faible**.
- *Preuve* : lecture du calcul (l.123-156), lecture des trois `return 50.0` du moteur, lecture du getter
  `statut`. Le bandeau de légende de l'onglet ne mentionne **pas** que 50.0 est ambigu.
- *Conséquence* : l'utilisateur lit « critère mort » là où le critère fonctionne. Corollaire : l'onglet
  **surestime mécaniquement** le nombre de critères morts, ce qui **contredit** l'onglet 19 Critères du même
  écran (qui, lui, ne fait aucune exclusion) → deux diagnostics contradictoires côte à côte.
- *Gravité* : **MOYENNE** · P2 (outil de contrôle, aucun effet sur les scores de production).
- *Correction proposée* : distinguer explicitement « valeur absente (`null`) » de « valeur neutre (50.0) » ;
  n'incrémenter `nbFallback` que sur `null`. Si le moteur ne trace pas l'origine de la valeur, **la correction
  exige un champ de traçabilité** — hors périmètre d'une simple correction cosmétique.
- *Dépendances* : BL2-A17 (mêmes onglets, règles divergentes).
- *Vérification après correction* : scénario contrôlé hors dépôt avec 5 pronostics dont `placeDepart` toujours
  renseigné mais sur galop longue distance → l'outil doit classer **Vivant**, pas Mort.

## 7.3 **BL2-A13 — MOYENNE / P2 : pourcentages de démonstration propagés dans 3 écrans pédagogiques**

- *Composant* : `IaTabConseils`, `IaTabAlgoConseils`, `IaTabMethodologie`.
- *Preuves* : `ia_tab_conseils.dart:25-28` — « Taux de réussite ~33% / ~38% / 71% / 84% » en dur ;
  `ia_tab_algo_conseils.dart:354-357` — mêmes valeurs (fichier **inaccessible**, 0 import) ;
  `ia_tab_methodologie.dart:219-224` — tableau `defauts` `{forme 0.25, gains 0.13, record 0.10 …}` qui
  **contredit** `IaPoidsAdaptatifs.defauts` `{forme 0.32, gains 0.15, record 0.12 …}`
  (`ia_memory_models.dart:858-868`).
- *Anomalie* : les 4 pourcentages de `ia_tab_conseils` sont **les mêmes littéraux** que ceux de
  `IaTabStats` (BL2-A09) présentés ici comme des « taux de réussite » de stratégies, sans le moindre
  avertissement. Le tableau de `methodologie` est un **second référentiel de défauts** (0.25/1.26) alors que le
  moteur utilise 0.32/1.37 — c'est **exactement BL1-A06** (deux familles de défauts) **matérialisée dans l'UI** :
  la barre de progression d'un critère est calculée contre `defauts` local (`_buildMethodeCard(..., 0.32)` passe
  la valeur du moteur pour la forme mais `0.15` pour gains, etc.).
- *Gravité* : **MOYENNE** · P2. *Dépendance* : BL2-A09 (même source littérale), BL1-A06 (défauts divergents).
  **Ne pas compter deux fois** : BL2-A13 est la **propagation UI** de BL1-A06 et de BL2-A09.
- *Correction proposée* : sourcer les 4 pourcentages depuis `precisionParType` et remplacer le tableau local par
  `IaPoidsAdaptatifs.defauts`.

## 7.4 **BL2-A17 — MOYENNE / P2 : deux onglets de diagnostic appliquent des règles différentes au même objet**

| Règle | Onglet 19 Critères | Onglet Discipline |
|---|---|---|
| Exclusion critères morts (σ<2.0) | **non** | **oui** (en-tête l.20-21) |
| Exclusion < 30 valeurs réelles | **non** | **oui** |
| Seuils de diagnostic | **`>`** stricts (`delta > 8.0 / > 4.0 / > 1.5 / > −1.5`, `:531-534`) | **`>=`** (`:790-792`) |
| Signal « échantillon faible » | absent | `nbAvecResultat < 20` (`:389`) |

- *Preuve* : lecture des deux fichiers (570 l. et 864 l.), grep des seuils.
- *Conséquence* : un critère à `delta = 1.5` exactement est « Neutre » dans l'onglet 1 et « Léger signal » dans
  l'onglet 4 ; un critère mort apparaît dans l'onglet 1 et disparaît de l'onglet 4. **Le même écran Audit
  affiche deux vérités sur le même critère.**
- *Gravité* : **MOYENNE** · P2.
- *Correction proposée* : extraire les règles dans un **référentiel unique** partagé par les 4 onglets.
- *Vérification après correction* : un critère σ<2.0 doit être absent ou explicitement marqué « non évaluable »
  dans les 4 onglets.

## 7.5 Un outil de contrôle capable de détecter une vraie anomalie — évaluation

Le mandat demande de vérifier qu'un outil **peut** détecter une anomalie réelle, et qu'un scénario conforme
n'est pas déclaré incorrect. Évaluation sur preuve de lecture, **sans exécution de scénario contrôlé** (le
mandat autorise un environnement isolé, mais la création d'un harnais exécutable exigerait d'instancier
`IaMemoryService` hors dépôt — l'apprentissage et la persistance seraient sollicités ; **je ne l'ai pas fait**,
par prudence sur la protection §14, et je le déclare comme **limite de preuve**).

| Outil | Peut détecter une anomalie réelle ? | Peut déclarer conforme un état anormal ? |
|---|---|---|
| 19 Critères | oui — signal `Très utile`/`Utile` par delta | **oui** : critère mort non exclu ⇒ peut afficher « Utile » avec 2 valeurs |
| Morts | oui — un critère à `null` partout devient Mort | **oui** : critère alimenté mais neutre ⇒ BL2-A11 |
| Corrélations | oui — doublon r≥0.80 | non identifié (exclusions documentées) |
| Discipline | oui | oui sur `>=` vs `>` (BL2-A17) |
| ROI/Value | oui sur la **liste** des bons conseils | **oui** sur les montants : un Quinté+ gagnant produit un ROI faux sans alerte (BL2-A12) |
| Cache audit | non — ne détecte rien, il sert | **oui** : sert un état périmé (BL2-A18) |
| `_buildDiagnosticConvergence` | compare à un référentiel **lui-même faux** | **oui** : BL1-A06 |

---

# §8 — FIABILITÉ DES TESTS AUTOMATISÉS (mandat §9)

## 8.1 Volumétrie mesurée

```
find test -name "*_test.dart" | wc -l        → 181
ls test/*.dart | wc -l                       → 182 (181 tests + MANIFESTE/manifeste)
fichiers référençant une classe BLOC 2        → 1
```
Classes BLOC 2 recherchées : `SimulationService`, `IaTabStats`, `IaNarrativeEngine`, `IaTabCriteresMorts`,
`IaTabCorrelations`, `IaTabDiscipline`, `IaAuditCacheService`, `RoiValueService`.

**Résultat du grep (explicite)** : **1 seul fichier** — `test/v41_a44_abstention_stats_test.dart`.
Couverture **nulle** pour : `SimulationService`, `IaNarrativeEngine`, `IaTabStats`, les 4 onglets d'audit,
`IaAuditCacheService`, `SimulationCandidateService`, `IaNarrativeMemoryService`.

## 8.2 Réserves héritées du BLOC 1 — vérification ciblée

| Réserve | Fichier | Assertion réellement vérifiée | Verdict |
|---|---|---|---|
| **G1.1** | `c3_garde_ecriture_financiere_globale_test.dart:77` | `expect(coupables, isEmpty)` sur une **analyse textuelle** de `lib/` | **test de présence de code, pas de comportement** — conforme à son objet déclaré (« garde structurelle ») mais **ne prouve aucune justesse de montant** ; le fichier le dit lui-même en §« CE QUE CE FICHIER NE PRÉTEND PAS » |
| **G2** | même fichier, `ecrivainsAutorises` | liste nominative **`chemin:ligne`** | **dépend de numéros de ligne figés** ⇒ **test fragile par construction** ; toute insertion de ligne le fait échouer (voulu) mais rend la suite rouge pour une raison non métier |
| **R1.1** | `c3_reproductibilite_suite_test.dart:40` | `expect(repli.existsSync() \|\| !repli.existsSync(), isTrue)` | **TAUTOLOGIE** — `A || !A` est toujours vrai. L'intention est écrite en commentaire (« on ne fait PAS échouer sur l'existence du repli ») mais **le test ne mesure rien** |
| **R1.2** | `:59` | existence de `test/fixtures/recherche_pmu/{multi,rapports}` | **test de présence de répertoire** — ne vérifie pas que la résolution *choisit* ce chemin (le titre l'affirme, le code non) |
| **R1.3** | `:74` | `git ls-files test/fixtures \| wc -l >= 363` | dépend de **git** et d'un **compte figé** ; environnement-specific |
| **Z1** | `z1_reproduction_d4_dividende_test.dart` | dividendes ×4,20, `montantRetour closeTo(84.0)`, composante unique | **assertions de valeur réelles et discriminantes — pertinentes** ; c'est le meilleur modèle de la suite |
| **Z2** | `z2_reproduction_n1_coursekey_test.dart` | clé `R{nR}C{nC}_date`, `scoreMouvementCote` 75.0, `copyWith` | **pertinentes**, avec témoins négatifs (`Z2-C` contrôle avec l'ancienne clé) |
| **Z3** | `z3_reproduction_n5_n6_filtres_test.dart` | `Z3-A` Aujourd'hui vs Période donnent des totaux différents ; `Z3-D` passage à minuit ; `Z3-E` bornes inclusives | **pertinentes et directement liées au mandat §4** — ce sont les seuls tests de période |
| **Z4** | `z4_reproduction_d2_suppression_test.dart` | suppression ciblée, persistance, donnée ancienne sans `storageKey` | **pertinentes** |

**Conclusion §8.2** : les réserves du BLOC 1 sont **confirmées avec une nuance importante** — `R1.1` est une
**tautologie démontrée par lecture** (`A || !A`), tandis que **Z1–Z4 sont de bons tests** (assertions de valeur,
témoins négatifs, cas limites). La réserve portait sur leur *pertinence*, pas sur leur qualité : elle est levée
pour Z1/Z2/Z3/Z4, maintenue pour R1.1/R1.2 et pour G2 (fragilité par numéros de ligne).

## 8.3 **BL2-A19 — ÉLEVÉE / P1 : un test verrouille l'anomalie BL2-A12 comme règle métier attendue**

`test/v41_a44_abstention_stats_test.dart`, cas **`A4-4-T9`** (l.380-401) :
```dart
expect(res.retours,    closeTo(3.4, 0.0001));
expect(res.gainNet,    closeTo(1.4, 0.0001));
expect(res.roi,        closeTo(70.0, 0.0001));
expect(res.tauxReussite, closeTo(50.0, 0.0001));
```
sur un **Tiercé gagnant**. Un Tiercé gagnant rapportant **3,4 €** pour 1 € misé est précisément la
conséquence de `retours += cote` (BL2-A12) : la cote du favori. Le test **encode le défaut comme contrat**.

- *Nature exacte de l'anomalie* : ce n'est pas « le test est faux » — il est fidèle au code. C'est un
  **test-tautologique au sens du mandat** : « les tests qui reproduisent la même erreur que le code testé ».
- *Gravité* : **ÉLEVÉE** · P1 — parce qu'il **bloque la correction** : corriger BL2-A12 rend la suite rouge.
- *Correction proposée* : réécrire `A4-4-T9` **dans le même chantier** que BL2-A12, en affirmant un retour
  dépendant du type (p. ex. `retours` ≠ `cote` pour un Tiercé, ou `retours` non établi). **Interdit en l'état**
  par le mandat §14 (aucune modification de test) — **exige une autorisation explicite**.

## 8.4 Autres motifs du mandat §9 — recherche

| Motif | Présence | Preuve |
|---|---|---|
| Assertions tautologiques | **OUI** (`R1.1`) | §8.2 |
| Tests passant quel que soit le comportement | **OUI** (`R1.1`, `R1.2` présence de répertoire) | §8.2 |
| Tests ne vérifiant que présence de texte/code | **OUI** (G1.1, G2 — assument leur nature) | §8.2 |
| Tests reproduisant l'erreur du code testé | **OUI** (`A4-4-T9`) | §8.3 |
| Tests ne couvrant pas les chemins réels | **OUI** — 0 test sur `SimulationService`, les 4 onglets d'audit, le ROI/Value | §8.1 |
| Dépendance à des numéros de ligne | **OUI** (G2) | §8.2 |
| Chemins spécifiques à l'environnement | **OUI** (`/home/user/recherche_pmu` cité en R1.1 ; `git ls-files` en R1.3) | §8.2 |
| Dates figées | non identifié dans le périmètre BLOC 2 (les fixtures PMU sont datées, ce qui est normal) | — |
| Mocks masquant un dysfonctionnement | non mesuré (hors périmètre : 0 test BLOC 2) | — |
| Fonctionnalités importantes non couvertes | **OUI** — Laboratoire, ROI/Value, Audit, IA narrative | §8.1 |

**Aucune exécution de test n'a été lancée** (mandat §14 : « Ne pas relancer systématiquement les 3 193 tests »).
Toutes les conclusions ci-dessus sont **de lecture**.

---

# §9 — CONSÉQUENCES DES ANOMALIES DU BLOC 1 SUR LE BLOC 2 (mandat §10)

| BL1 | Conséquence mesurée sur le BLOC 2 | Où |
|---|---|---|
| **BL1-A06** deux jeux de défauts (0.25/1.26 vs 0.32/1.37) | Le tableau `defauts` de `IaTabMethodologie` utilise **0.25** et non 0.32 → la barre de progression d'un critère est calculée contre un **mauvais référentiel** | `ia_tab_methodologie.dart:219-224` ; **BL2-A13** |
| **BL1-A02** deux cascades (A adaptative / B figée) | `RoiValueService` utilise `_estBon` → `_estBonConseilParType` (type-aware) : il adopte donc **la famille A**. Les statistiques du Calendrier et de `IaTabStats` reposent sur `typePariConseille` **persisté par la cascade B**. Deux composants du BLOC 2 mesurent donc **des paris différents** | `roi_value_service.dart:134-135` |
| **BL1-A15** `seuilQuarte`/`seuilQuinte` appris sans effet | Les 7 types de `roiParTypePari` incluent `Quarté+` et `Quinté+` → deux onglets ROI (`Type de pari`) **mesurent des types dont le seuil n'agit pas** | `roi_value_service.dart:225-235` |
| **BL1-A11** Best Bet affiche `mise × cote` pour tous les types | **Même défaut, formule identique**, dans `RoiValueService` : `retours += cote`. BL2-A12 **est la réplique exacte de BL1-A11** dans le BLOC 2 | BL2-A12 |
| **BL1-A12** martingale « Gagnant seul », cote 2,5 | **Complément BLOC 2 mesuré** : la martingale est le **5ᵉ backtest** et la seule brique du BLOC 2 qui affiche un **gain net en € sans aucun avertissement de caractère théorique**. Le seul texte présent est « ⚠️ La martingale présente un risque de perte illimitée » (`:511`), qui porte sur le **risque**, pas sur la **fiabilité du montant**. Aucun bandeau n'énonce que la cote utilisée est `coteFavoriPmu` ou **2,5 par défaut** (`:392-393`). **L'anomalie BL1-A12 sur les gains/ROI théoriques présentés sans avertissement suffisant est donc explicitement préservée et complétée ici de deux dépendances : (a) cote de repli 2,5 non affichée ; (b) `capital` cumulé présenté en € comme un résultat.** | `ia_tab_backtesting.dart:392-393, 438-464, 511` |
| **BL1-A09** archive non exploitée | **BL2-A06** (profondeur des 8 outils BLOC 2), **BL1-A10 étendue** (divergence inter-écrans) | §5.3, §5.4 |
| **BL1-A13** backtest écrit `conseils_*` | `_buildTraceabiliteBacktesting` lit `premiumsPourDate` : le compteur « Affichés en Premium » peut retomber à 0 **à cause** de BL1-A13 | §7.1 #9 |
| **BL1-A20** résultats de backtesting non persistés | Le BLOC 2 **n'ajoute pas de persistance** : `_btResult`/`_martingaleResult` restent volatils ; `simulation_candidates_v1` est le **seul** état durable du BLOC 2 côté simulation | `simulation_candidate_service.dart` |
| **BL1-A16/A17/A18** écrans/engins inaccessibles | `ia_tab_algo_conseils.dart` (488 l., contenant les pourcentages de BL2-A13) est **inaccessible** — 0 import | §0.4, §7.3 |
| **BL1-A01/A04/A05/A07/A08/A14/A19** | **aucune conséquence mesurée** sur le BLOC 2 : ces anomalies portent sur `resetPoids`, le clamp, le registre de calibration, les étoiles premium, `seuilGagnantPlace`, `widget_service` et des commentaires. Aucun outil BLOC 2 n'y touche. **Déclaré explicitement plutôt que supposé.** | — |

---

# §10 — CARTOGRAPHIE TRANSVERSALE (mandat §11)

## 10.1 Matrice des interactions

| Source → Destination | Donnée transmise | Mécanisme | Déclencheur | Fréquence | Écriture ? | Preuve |
|---|---|---|---|---|---|---|
| `SimulationScreen` → `SimulationService` | `SimulationParams` (discipline + 19 multiplicateurs) | appel direct `_svc.simuler(params)` | bouton « Lancer » | à la demande | **non** | `simulation_screen.dart:245-259` |
| `SimulationService` → `IaMemoryService` | **lecture** `svc.pronostics`, `svc.poids` | getters | idem | idem | **non** | `simulation_service.dart:57,63` |
| `SimulationService` → `IaPoidsAdaptatifs` | **copie** des poids par discipline | `poidsEffectifsPourDiscipline` | idem | idem | **non** (copie) | `ia_memory_models.dart:614-646` |
| `SimulationScreen` → `SharedPreferences` | `labo_ia_etat_v1` | `setString` | chaque modification | fréquent | **UI seulement** | `:169` |
| `SimulationScreen` → `SimulationCandidateService` | `SimulationCandidat` | `saveCandidate` | « Enregistrer comme piste » | à la demande | `simulation_candidates_v1` | `:406-470` |
| `RoiValueScreen` → `RoiValueService` | `RoiValueFilters` | appel direct depuis les 5 onglets | chaque `build` | **à chaque frame d'onglet** | non | `roi_value_screen.dart:89-93` |
| `RoiValueService` → `IaMemoryService` | `pronosticsAvecResultat` | getter | idem | idem | non | `:44` |
| `RoiValueService` → `estBonConseil` | 1 pronostic + son type | wrapper | idem | idem | non | `:134-135` |
| `IaTabStats` → `IaMemoryService` | `precisionParHippodromeAvecFiabilite` | getter | `build` | à l'ouverture | non | `:267-417` |
| `IaTabStats` → `AlertService` | `trackedCourses` | provider passé en paramètre | `build` | idem | non | `:419-473` |
| `HomeScreen` → `IaNarrativeEngine` | `IaNarrativeContext` | `obtenirNarratifAccueil` | `initState` + refresh | 1×/session | **cache phrases** | `home_screen.dart:334-473` |
| `IaNarrativeEngine` → `IaNarrativeMemoryService` | `templateIds` | `sauvegarderTemplates` | chaque génération | idem | `ia_narrative_memory_v1` | `ia_narrative_engine.dart` |
| `AuditScreen` → 4 onglets | `_refreshKey` | `KeyedSubtree` | « Recalculer » | manuel | non | `audit_screen.dart` |
| 4 onglets → `IaAuditCacheService` | compteur + résultats | `readCache`/`writeCache` | `build` | idem | `ia_audit_cache_v1` | 4 fichiers |
| `IaTabBacktesting` → `IaMemoryService` | `pronosticsAvecResultat` | getter | « Lancer » | manuel | non | `:356` |
| `IaTabBacktesting` → **`SharedPreferences`** | **`conseils_filtres_*` + `conseils_inject_pending`** | `setStringList`/`setBool` | application de filtres | manuel | **OUI — écrit dans la production** | `:1363-1371` ; **BL1-A13** |
| `IaTabBacktesting` → `premiumsPourDate` | premium du jour | getter | traceabilité | idem | non | `:1466` |
| `IaTabMethodologie` → `IaMemoryService` | `poids`, `journal` | getter + listener | `build` + notif | fréquent | non | `:30,45,239` |
| `IaPersonalityService` → `SharedPreferences` | prénom, avatar, bulle, stats | `set*` | actions Profil | manuel | oui (préférences) | service |
| `IaSpeechWidget` → 3 écrans | phrase de confiance | constructeur | `build` | à l'ouverture | non | `course_detail:485`, `fiche_cheval:259`, `home:1654` |
| `BackupService` → tout | export/restauration | liste de clés | manuel | — | **restauration** | `:428/431/545/551/847/1657` |
| `IaMemoryService` → `IaAuditCacheService` | `invalidate()` | appel | `nbNouveauxResultats > 0` | par analyse | oui (prefs) | `:5059` |

## 10.2 Interactions **absentes** alors qu'elles sembleraient logiques — vérifiées comme absentes

| Interaction attendue | Réalité | Preuve |
|---|---|---|
| Laboratoire → apprentissage (une piste validée nourrit l'IA) | **aucune** | 0 `enregistrerPronostic`/gradient dans `simulation_service.dart` |
| Laboratoire → poids de production | **aucune** (copie) | `poidsEffectifsPourDiscipline` |
| Laboratoire → archives | **aucune** | grep 0 |
| ROI/Value → chaîne financière | **aucune** | BL2-A12 |
| `IaTabStats` → `calculerStats()` pour les 8 blocs de tête | **aucune** | BL2-A09 |
| IA interactive → n'importe quel outil | **aucune** | §6.2 |
| 4 onglets d'audit → référentiel de règles commun | **aucune** | BL2-A17 |
| Outils BLOC 2 → archives | **aucune** | §5.1 |

## 10.3 Dépendances circulaires / sources de vérité contradictoires

- **Contradiction de source** : `typePariConseille` (persisté, famille B) vs `_estBon` (famille A) → BL1-A02.
- **Aucune dépendance circulaire** détectée : `IaMemoryService` n'appelle aucun service BLOC 2 ; la flèche va
  toujours BLOC 2 → `IaMemoryService`. C'est la raison structurelle pour laquelle **l'isolation du Laboratoire
  tient**.
- **Source de vérité du taux de réussite** : **5 sources** → BL2-A14. Aucune ne porte de nom qualifié.

## 10.4 Redondances de calcul

| Calcul | Occurrences | Coût |
|---|---|---|
| `RoiValueService.calculerResume` | **1 par onglet × 1 par `build`** (`RoiValueScreen` reconstruit 5 sous-arbres) | recalcul complet de la liste à chaque frame d'onglet ; aucun cache |
| `precisionParHippodromeAvecFiabilite` | `IaTabStats` + `IaPrecisionWidget` + `IaSpeechWidget` | 3 appels indépendants |
| `_scoreConfiance` / `_enregistrerPiste` | **2 implémentations divergentes** | BL2-A08 |

---

# §11 — ANOMALIES NOUVELLES CONSOLIDÉES (mandat §13)

| ID | Gravité | Prio | Composant | Résumé | Dépend de |
|---|---|---|---|---|---|
| **BL2-A01** | Faible | P3 | `SimulationScreen` | Boutons ± contournent la borne 0.50–2.00 (seule garde en `_appliquerSaisie`) | — |
| **BL2-A02** | **Élevée** | P1 | `SimulationService._classerSimule` | Deux échelles de score (moyenne pondérée ≠ `_normaliserScores`) ⇒ Δ structurellement gonflé | BL2-A03 |
| **BL2-A03** | **Élevée** | P1 | idem | Aucun Δ nul à multiplicateurs = 1.00 ⇒ le Laboratoire ne peut pas être témoin neutre | BL2-A02 |
| **BL2-A04** | Moyenne | P2 | `SimulationService` | Pas de séparation apprentissage/évaluation, pas de divulgation | BL2-A06 |
| **BL2-A05** | Faible | P3 | `simulation_screen` | `labo_ia_etat_v1` absent de la sauvegarde (grep `backup_service.dart` → 0) | — |
| **BL2-A06** | **Élevée** | P1 | 8 outils | Profondeur annoncée > réelle (600 fiches) ; « complet » trompeur | **BL1-A09** |
| **BL2-A07** | Moyenne | P2 | `_critersInactifs` | 5 critères déclarés inactifs en dur, dont 2 avec motif **faux** (`pd`, `rp` alimentés) | — |
| **BL2-A08** | Moyenne | P2 | `_scoreConfiance` ×2 | Deux implémentations, écart jusqu'à 15 pts (malus 7 j/30 j absent côté enregistrement) | — |
| **BL2-A09** | **CRITIQUE** | **P0** | `IaTabStats` | 8 blocs de statistiques **fabriqués**, identiques pour tous, « +43 % » ; données réelles disponibles mais non utilisées | BL1-A06 |
| **BL2-A10** | Faible | P3 | `ia_performance_screen:902` | Table dupliquée `// ignore: unused_field` | BL2-A09 |
| **BL2-A11** | Moyenne | P2 | `IaTabCriteresMorts` | `score == 50.0` pris pour un fallback ⇒ peut déclarer mort un critère vivant | BL2-A17 |
| **BL2-A12** | **CRITIQUE** | **P0** | `RoiValueService` | `retours += coteFavori` pour les 7 types ; contourne la chaîne financière ⇒ ROI faux | **BL1-A11**, BL1-A12, BL2-A19 |
| **BL2-A13** | Moyenne | P2 | 3 écrans pédagogiques | Pourcentages fabriqués propagés + second référentiel de défauts 0.25 vs 0.32 | BL2-A09, **BL1-A06** |
| **BL2-A14** | **Élevée** | P1 | 5 producteurs | 5 définitions concurrentes du « taux de réussite » ; (2) = TOP3 sous libellé « Gagnant » ; (5) = moyenne de moyennes | BL1-A02 |
| **BL2-A15** | Moyenne | P3 | `home_screen:454-472` | 4 champs narratifs figés ⇒ branches et templates morts | — |
| **BL2-A16** | Moyenne | P2 | 3 fichiers | `stats_screen.dart` (273 l.), `comparaison_screen.dart` (1197 l.), `ia_tab_algo_conseils.dart` (488 l.) : **0 import** | BL1-A16/18 |
| **BL2-A17** | Moyenne | P2 | Audit onglets 1 & 4 | Règles d'exclusion et seuils (`>` vs `>=`) divergents sur le même critère | — |
| **BL2-A18** | Moyenne | P2 | `IaAuditCacheService` | Validité par égalité de compteur seulement ⇒ cache périmé servi | BL2-A17 |
| **BL2-A19** | **Élevée** | P1 | `A4-4-T9` | Test **verrouille** BL2-A12 comme règle attendue ⇒ bloque la correction | BL2-A12 |
| **BL2-A20** | Faible | P3 | `SimulationParams.reset()` | **Jamais appelé** (grep `.reset()` sur `param\|simul` → 0) ; `_reset()` de l'écran vide `_mults` directement | — |
| **BL2-A21** | Faible | P3 | `IaPersonalityService.messageMatin` | Seul appelant = méthode interne `:449` ; aucun écran | — |
| **BL2-A22** | Faible | P3 | `RoiValueService._filtrer` | Fenêtre `now() − N j` (rétrécissante) ; ni « Aujourd'hui » ni période libre ; filtres non persistés | — |

## 11.1 Décompte par gravité

| Gravité | Nombre | IDs |
|---|---|---|
| **CRITIQUE** | **2** | BL2-A09, BL2-A12 |
| **ÉLEVÉE** | **5** | BL2-A02, BL2-A03, BL2-A06, BL2-A14, BL2-A19 |
| **MOYENNE** | **9** | BL2-A04, BL2-A07, BL2-A08, BL2-A11, BL2-A13, BL2-A15, BL2-A16, BL2-A17, BL2-A18 |
| **FAIBLE** | **6** | BL2-A01, BL2-A05, BL2-A10, BL2-A20, BL2-A21, BL2-A22 |
| **TOTAL** | **22** | |

*(Décompte vérifié : 2 + 5 + 9 + 6 = 22.)*

**Dont 3 rattachées à une anomalie du BLOC 1 et non recomptables comme nouvelles** : BL2-A06 → BL1-A09,
BL2-A12 → BL1-A11 (réplique), BL2-A13 → BL1-A06 (propagation). **Anomalies réellement nouvelles et
autonomes : 19.**

**Aucune anomalie nécessitant un signalement immédiat pour perte de données ou corruption d'apprentissage
n'a été trouvée.** Le Laboratoire n'écrit rien, l'IA interactive n'écrit rien, le ROI/Value n'écrit rien. Le
seul écrivain du BLOC 2 est `IaTabBacktesting` (`conseils_*`, déjà connu sous BL1-A13).

---

# §12 — FONCTIONNALITÉS CONFORMES (mandat §16-15)

| Fonctionnalité | Preuve de conformité |
|---|---|
| **Isolation totale du Laboratoire** | 9 points de contrôle, tous VERIFIED (§1.4) ; `poidsEffectifsPourDiscipline` retourne une copie ; 0 écriture `IaMemoryService`, 0 `poids.X =`, 0 `_save()` |
| **Bornes de saisie manuelle** | `_appliquerSaisie` refuse `< 0.50` et `> 2.00` avec message utilisateur |
| **`IaPrecisionWidget` — périodes** | Aujourd'hui temps réel, 7 j = 6+1, période passée non contaminée (§3.2) |
| **`IaPrecisionWidget` — 60 j / all / 7 j / today / custom** | 5 périmètres distincts, sources explicites |
| **`IaTabStats` — hippodromes** | `precisionParHippodromeAvecFiabilite`, tri, `take(12)`, `fiable = nb>=5` |
| **`IaTabStats` — Mes Paris** | `alertService.trackedCourses`, données réelles |
| **`ProfileStatsTab`** | Provider réel : `totalMise`, `totalGainsNet`, `totalGagnés`, `totalPerdus`, `totalRemboursements` |
| **`IaTabCorrelations`** | exclusion σ<2.0 documentée, `toJson()` à clés courtes cohérent avec `_labels`, Pearson correct |
| **Abstentions exclues du ROI** | `typePariConseille == 'À surveiller'` exclu avant mise (testé A4-4-T7) |
| **Pronostics sans cote exclus des deux côtés** | `nbParisRoi` et `retours` conditionnés à la présence d'une cote |
| **Détecteurs Value / Outsiders / Faux favoris** | critères explicites et documentés en note de bas de page |
| **Anti-répétition des phrases** | `sauvegarderTemplates(usedIds)`, fallback pool complet |
| **`SimulationCandidateService`** | dedup par id, `take(50)`, `clearCandidates` branché |
| **Changement de poids expérimental a bien un effet** | **OUI** — les multiplicateurs entrent dans `scoreVirtuel += valScore * poidsCritere * mult` (`simulation_service.dart:200-206`) ; l'effet est mesurable (mais le Δ est biaisé, BL2-A02) |
| **Aucune fuite de données futures** | `_classerSimule` n'utilise que `scoresCriteres` (antérieurs) + `poids` ; l'issue réelle ne sert qu'au **comptage**, jamais au classement |

---

# §13 — FONCTIONNALITÉS INCOMPLÈTES OU INUTILISÉES (mandat §16-16)

| Élément | Nature | Preuve |
|---|---|---|
| `stats_screen.dart` (273 l.) | **INACCESSIBLE** | 0 import, absent de `_screens` |
| `comparaison_screen.dart` (1197 l.) | **INACCESSIBLE** | 0 import |
| `ia_tab_algo_conseils.dart` (488 l.) | **INACCESSIBLE** | 0 import |
| `SimulationParams.reset()` | **potentiellement inutilisé** | grep `.reset()` cross `param\|simul` → 0 |
| `IaPersonalityService.messageMatin` | **potentiellement inutilisé** | 1 appelant interne |
| 4 champs de `IaNarrativeContext` | **structurellement morts** | figés à 0/`''`/`null` par l'appelant |
| Templates `widget_*`, `v3_widget_*` | **jamais émis** | conséquence des 4 champs |
| `_statsDiscipline` (`ia_performance_screen:902`) | **mort déclaré** | `// ignore: unused_field` |
| Résultats de backtesting | **non persistés** | BL1-A20 |

**Limite de preuve explicite** : « 0 import » et « grep vide » ne prouvent pas l'absence d'usage dynamique
(`Function.apply`, réflexion, code généré). Aucun de ces mécanismes n'a été trouvé dans les appelants listés,
mais leur absence n'est pas démontrée à 100 %.

---

# §14 — PARAMÈTRES SANS EFFET (mandat §16-17)

| Paramètre | Effet réel mesuré | Preuve |
|---|---|---|
| 19 multiplicateurs du Laboratoire | **effet mesuré** : entrent dans le score simulé | `simulation_service.dart:200-206` |
| 6 presets | effet : écrivent `_mults` + `_critersActifs` | `_appliquerPreset:276-296` |
| `SimulationParams.discipline` | effet : filtre `_matchDisc` | `:265-278` |
| **`roiJour` / `roiHier`** (narratif) | **AUCUN** — figés à 0 | `home_screen.dart:462-471` |
| **`widgetPremiumLePlusStable`** | **AUCUN** — figé à `''` | idem |
| **`typePariLePlusInstable`** | **AUCUN** — figé à `null` | idem |
| `periode` de `RoiValueFilters` | **effet partiel** : borne `now()−N` au lieu du jour | BL2-A22 |
| `_btJours`, `_btMise` (backtesting) | effet réel, persistés | `bt_*` |
| `bt_type` | **sans effet dans la martingale** — `_lancerMartingale` ignore `_btType` | BL1-A12 |

---

# §15 — INCOHÉRENCES ET MÉCANISMES REDONDANTS (mandat §16-18)

1. **5 définitions du taux de réussite** (BL2-A14).
2. **2 implémentations de `_scoreConfiance`** (BL2-A08) — écart jusqu'à 15 points.
3. **2 référentiels de poids par défaut** dans l'UI (BL2-A13) et **3 dans le dépôt** (BL1-A06 : 0.25/1.26,
   0.32/1.37, 1.37 sur JSON incomplet).
4. **2 jeux de règles de diagnostic** dans le même écran (BL2-A17).
5. **1 diagnostic qui contredit l'autre** : onglet 1 (aucune exclusion) vs onglet 2 (proxy 50.0) vs onglet 4
   (σ + 30 valeurs). Trois politiques pour un même critère.
6. **2 échelles de score** entre production et Laboratoire (BL2-A02).
7. **3 écrans contenant les mêmes 4 pourcentages** (BL2-A09 + BL2-A13).
8. **Recalcul intégral du ROI à chaque frame d'onglet**, sans cache, alors qu'un cache existe pour l'audit.
9. **Cache d'audit validé par un compteur** alors qu'un hash serait nécessaire (BL2-A18).
10. **`_reset()` de l'écran vide `_mults` directement** au lieu d'appeler `SimulationParams.reset()` qui existe
    (BL2-A20) — redondance de logique.

---

# §16 — PROPOSITIONS DE CORRECTION GROUPÉES EN UN SEUL CHANTIER (mandat §16-19)

**Chantier unique « BLOC 2 — corrections », à ne pas découper en sous-chantiers avec validation intermédiaire.**

## Vague 1 — Indicateurs trompeurs (P0, aucune modification de calcul IA)

| Ordre | Action | Anomalie | Fichiers | Risque | Dépendance |
|---|---|---|---|---|---|
| 1.1 | **Décision utilisateur requise** : autoriser la réécriture de `A4-4-T9` | BL2-A19 | `test/v41_a44_abstention_stats_test.dart:380-401` | **ÉLEVÉ** | **préalable bloquant** |
| 1.2 | Router le retour du ROI par `MoteurGainPmu`/`GainCalculator` selon `typePariConseille` ; à défaut afficher « retour non établi » | BL2-A12 | `roi_value_service.dart:178-193` | ÉLEVÉ | 1.1 |
| 1.3 | Remplacer les 8 blocs fabriqués de `IaTabStats` par `calculerStats()` + `statsParType` + `precisionParType` | BL2-A09 | `ia_tab_stats.dart:25-30, 80-85, 199-241` | faible (UI) | — |
| 1.4 | Corriger les 4 pourcentages de `IaTabConseils` et le tableau `defauts` de `Methodologie` | BL2-A13 | 2 fichiers | faible (UI) | 1.3 |
| 1.5 | Renommer « Gagnant » → « Top 3 » là où le prédicat est `rang<=3` ; pooler le taux 7 j | BL2-A14 | `ia_tab_stats`, `home_screen:375-387` | faible | — |

## Vague 2 — Diagnostics (P1/P2, aucune modification de calcul IA)

| Ordre | Action | Anomalie |
|---|---|---|
| 2.1 | Référentiel de règles unique pour les 4 onglets d'audit (exclusions + seuils) | BL2-A17 |
| 2.2 | Distinguer `null` de `50.0` dans l'onglet Morts | BL2-A11 |
| 2.3 | Hash de contenu dans `isCacheValid` | BL2-A18 |
| 2.4 | Unifier `_scoreConfiance` (une seule implémentation, celle de l'assistant) | BL2-A08 |

## Vague 3 — Laboratoire (P1, touche le calcul **du Laboratoire uniquement**, pas la production)

| Ordre | Action | Anomalie |
|---|---|---|
| 3.1 | Appliquer `_normaliserScores` au vecteur simulé avant tri | BL2-A02 **et** BL2-A03 (une seule correction) |
| 3.2 | Test discriminant : multiplicateurs tous à 1.00 ⇒ Top1/Top3/Top5 identiques avant/après | validation de 3.1 |
| 3.3 | Afficher « N pronostics couverts » et renommer « complet » → « mémoire disponible » | BL2-A06 (défaut minimal en attendant BL1-A09) |
| 3.4 | Divulguer l'absence de séparation apprentissage/évaluation | BL2-A04 |
| 3.5 | Ajouter `labo_ia_etat_v1` à la sauvegarde | BL2-A05 |
| 3.6 | Corriger les 2 motifs faux de `_critersInactifs` (`pd`, `rp`) | BL2-A07 |
| 3.7 | Contraindre les boutons ± à [0.50, 2.00] | BL2-A01 |
| 3.8 | Brancher `SimulationParams.reset()` ou le supprimer | BL2-A20 |

## Vague 4 — Nettoyage (P3)

BL2-A10, BL2-A15, BL2-A16, BL2-A21, BL2-A22 : suppression/avertissement, décision de réactivation d'écrans.

## Risques de régression globaux

- **Élevé** : 1.2 (BL2-A12) — verrouillé par un test (BL2-A19) et touche un indicateur financier.
- **Moyen** : 3.1 (BL2-A02/A03) — modifie le calcul **du Laboratoire**, donc les verdicts « 🟢/🟡/🟠/🔴 » et les
  scores de confiance des pistes. **Ne touche aucun poids, seuil ou score de production.**
- **Faible** : tout le reste (UI, libellés, cache, bornes).

---

# §17 — LIMITES DE PREUVE (mandat §16-20)

1. **Aucun calcul n'a été exécuté.** Le Laboratoire, le ROI/Value, les 4 onglets d'audit et le moteur narratif
   ont été analysés **par lecture statique**. Toute affirmation sur un **chiffre produit** est une déduction de
   formule, pas une mesure d'exécution.
2. **Aucun test n'a été lancé** (3 193 tests non relancés, conformément au mandat §14).
3. **Aucun scénario contrôlé en environnement isolé n'a été construit** pour les outils de diagnostic (§7.5) :
   instancier `IaMemoryService` exigerait de solliciter l'apprentissage et la persistance, ce que la protection
   §14 interdit. **La capacité de détection réelle des outils est donc évaluée par lecture, pas par test.**
4. **`grep` vide ≠ code mort.** `SimulationParams.reset()`, `messageMatin`, `stats_screen`,
   `comparaison_screen`, `ia_tab_algo_conseils` sont classés « potentiellement inutilisés / inaccessibles ».
   Aucun appel dynamique n'a été trouvé, mais l'absence totale n'est pas démontrée.
5. **Les 12 blocs fabriqués de `IaTabStats`** sont démontrés fabriqués par lecture (littéraux `const`). La
   **non-utilisation** de `calculerStats()` est prouvée par lecture du même fichier (grep `calculerStats` → 0),
   mais le fichier **est bien monté** dans l'écran de performance (`ia_performance_screen.dart:989`) : il n'est
   pas mort, il est **faux**.
6. **Le comportement de BL2-A12 sur dividendes réels n'est pas mesuré** : la démonstration repose sur la
   formule (`retours += cote`) et sur l'absence de tout appel à la chaîne financière. Aucun jeu de données
   réel n'a été rejoué.
7. **La « représentativité de l'échantillon »** n'est pas mesurable sans données réelles : le nombre de
   pronostics effectivement en mémoire dans l'installation de l'utilisateur est inconnu.
8. **La fréquence réelle** des divergences 7 j/30 j (BL2-A08) n'a pas été mesurée.
9. **`dart analyze` n'a pas été relancé** (aucune modification de code n'a été faite ; l'état du dépôt est
   celui du commit `2e96aae`, dont la CI est déjà verte).

---

# §18 — VÉRIFICATIONS EXIGEANT UN APPAREIL ANDROID RÉEL (mandat §16-21)

| # | Vérification | Pourquoi l'émulateur web ne suffit pas |
|---|---|---|
| 1 | Rendu et lisibilité des 8 cartes chiffrées de `IaTabStats` sur petits écrans | tailles de police `16` sur cartes denses ; débordement possible (déjà un thème de la branche `fix/a6-debordements-320dp`) |
| 2 | Performance de `RoiValueService` recalculé à chaque frame d'onglet | 5 onglets × recalcul complet : coût CPU réel non mesurable en web release |
| 3 | Rendu du PNG d'export (`_exporter`, `pixelRatio: 2.5`) et partage via `SharePlus` | dépend des canaux natifs Android |
| 4 | Comportement du `RenderRepaintBoundary.toImage` de l'export ROI/Value offscreen | spécifique au rasteriseur Android |
| 5 | Persistance réelle de `labo_ia_etat_v1` et `simulation_candidates_v1` après kill de l'application | `SharedPreferences` Android |
| 6 | Comportement du passage de minuit pendant que l'écran ROI est ouvert | horloge système réelle |
| 7 | Affichage du clavier numérique sur les 19 champs de coefficient | clavier Android |
| 8 | Ordre de grandeur réel des ROI affichés sur un usage pluriannuel | dépend de l'historique réel |

---

# §19 — PREUVE D'INTÉGRITÉ DU DÉPÔT ET DES DONNÉES PROTÉGÉES (mandat §16-22)

Vérifications exécutées à la clôture (§ voir bloc ci-dessous, mesuré en fin de session) :

```
cd /home/user/flutter_app
git status --porcelain          → 0 ligne
git log -1 --format='%H %s'     → 2e96aae1d98a1af61cc5ad2bb24010de5c718500
git branch                      → * main (+ origin/main, et 2 branches locales préexistantes)
```

- **Aucun fichier de `lib/` modifié** : 0 ligne dans `git status --porcelain`.
- **Aucun fichier de `test/` modifié**, aucun test créé dans le dépôt.
- **Aucune dépendance modifiée** (`pubspec.yaml` intact).
- **Aucun poids, seuil, critère, algorithme, gradient, apprentissage, TOP3, score, pronostic, résultat ni
  archive modifié** : aucune écriture n'a été effectuée dans le dépôt ; les seuls fichiers écrits sont
  `/home/user/audit_bloc2/RAPPORT_BLOC2.md` (rapport) et `/home/user/audit_bloc1/*` (BLOC 1), **hors dépôt**.
- **Aucun commit, aucun push, aucune branche, aucun APK.**
- **Aucun recalcul historique lancé.**
- **Aucune suite de tests exécutée.**

---

# §20 — CLÔTURE (mandat §17)

## 20.1 Couverture du périmètre BLOC 2

| Section du mandat | Traitée | Où |
|---|---|---|
| §2 Laboratoire intégral | ✅ | §1 (1.1 → 1.12) |
| §3 Statistiques IA | ✅ | §2 (2.1 → 2.2) |
| §4 Filtres / périodes / actualisation | ✅ | §3 (3.1 → 3.4) |
| §5 Statistiques générales & ROI/Value + 5 catégories | ✅ | §4 (4.1 → 4.4) |
| §6 Archives permanentes & profondeur | ✅ | §5 (5.1 → 5.5) |
| §7 IA interactive intégral | ✅ | §6 (6.1 → 6.7) |
| §8 Outils de vérification / diagnostic | ✅ | §7 (7.1 → 7.5) |
| §9 Fiabilité des tests | ✅ | §8 (8.1 → 8.4) |
| §10 Conséquences BLOC 1 | ✅ | §9 |
| §11 Cartographie transversale | ✅ | §10 (10.1 → 10.4) |
| §12 Méthode et niveaux de preuve | ✅ | §17 + niveau de preuve par anomalie |
| §13 Identification / classification | ✅ | §11 (22 anomalies, 4 gravités) |
| §14 Protections absolues | ✅ | §19 |
| §15 Autonomie | ✅ | aucun sous-bloc soumis à validation |
| §16 Rapport 22 sections | ✅ | §0 → §19 |
| §17 Clôture et arrêt | ✅ | §19, §20 |

## 20.2 Réponse aux questions explicites du mandat

| Question posée | Réponse mesurée |
|---|---|
| Une modification de poids expérimental produit-elle un effet mesurable ? | **OUI** — `mult` entre dans le score simulé (`simulation_service.dart:200-206`). L'effet est réel mais **l'amplitude du Δ est biaisée** (BL2-A02/A03). |
| Le Laboratoire utilise-t-il exactement le moteur de production ? | **NON.** `_classerSimule` = moyenne pondérée ; la production = `_normaliserScores` (min-max + brut). **`_normaliserScores` apparaît 0 fois dans `simulation_service.dart`.** |
| Les expériences modifient-elles silencieusement les poids, seuils/apprentissage/TOP3/pronostics ? | **NON**, sur **tous** les chemins (normal, erreur, interruption, reset, restauration). Preuve : `poidsEffectifsPourDiscipline` retourne une **copie** ; 0 écriture `IaMemoryService`. |
| Deux indicateurs de même sens utilisent-ils des données cohérentes ? | **NON** — 5 définitions concurrentes (BL2-A14), aucune différence justifiée par un objectif métier identifiable, sauf (1) vs (3). |
| Un outil de contrôle peut-il détecter une vraie anomalie ? | **Partiellement** : Corrélations et Discipline oui ; Morts **non** (faux positifs) ; ROI **non** sur les montants. |
| Les tests couvrent-ils le BLOC 2 ? | **NON** — 1 fichier sur 181, et il **verrouille** une anomalie (BL2-A19). |
| L'archive est-elle exploitée par le BLOC 2 ? | **NON** — 0 des 8 outils. |
| L'IA interactive peut-elle écrire dans la production ? | **NON** — uniquement un cache de phrases. |
| Une anomalie critique de perte de données existe-t-elle ? | **NON.** |

## 20.3 Point de reprise éventuel

Le rapport est **complet** au regard du périmètre annoncé. Aucun point de reprise n'est nécessaire.
Si une session ultérieure devait poursuivre : les seuls compléments possibles sont (a) l'exécution en
environnement isolé des scénarios contrôlés du §7.5, (b) la mesure de la fréquence réelle de BL2-A08, (c) la
revalidation sur appareil Android réel (§18).

**Le BLOC 2 est déclaré COUVERT et CLOS. Aucune correction n'a été appliquée, aucun commit, aucun push,
aucune branche, aucun APK. Arrêt avant le BLOC 3, conformément au mandat.**
