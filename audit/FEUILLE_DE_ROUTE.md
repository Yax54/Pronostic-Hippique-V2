# FEUILLE DE ROUTE — TROIS GRANDS CHANTIERS DE CORRECTION

**Référence** : `2e96aae1d98a1af61cc5ad2bb24010de5c718500` — branche `main`
**Règle absolue** : **chaque correction a UN SEUL chantier responsable.** Aucun mécanisme n'est corrigé deux fois.

---

## Vue d'ensemble

```
┌───────────────────────────────────────────────────────────────────────────┐
│  CHANTIER 1 — INTELLIGENCE ET PERFORMANCES                                │
│  BL1-A01…A20 (20) + BL3-A22, A23, A24, A26, A27                            │
│  ▸ Critères IA, moteur de décision, un seul barème                         │
│  ⛔ INTERDIT : poids, seuils, formule, descente de gradient, TOP3,         │
│     scores historiques, recalcul rétroactif                                │
└───────────────────────────────────┬───────────────────────────────────────┘
                                    │ fournit : ancre normalisée + barème unique
                                    ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  CHANTIER 2 — ANALYSE, STATISTIQUES ET OUTILS DE CONTRÔLE                 │
│  BL2-A01…A22 (22) + BL3-A01, A02, A03, A04, A06, A28, A39, A43             │
│  ▸ Écrans de mesure, cohérence affichage ↔ calcul, outils réellement       │
│    exécutables                                                            │
│  ⛔ Ne recrée AUCUN barème : consomme celui du chantier 1                  │
└───────────────────────────────────┬───────────────────────────────────────┘
                                    │ fournit : indicateurs fiables
                                    ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  CHANTIER 3 — FONCTIONNEMENT GÉNÉRAL ET INTÉGRATION                       │
│  BL3-A05, A07–A19, A29–A38, A40–A42, A44–A50                               │
│  ▸ Datation, persistance, notifications natives, sauvegarde, Android       │
│  ⛔ Ne réécrit AUCUNE clé historique persistée                             │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## CHANTIER 1 — CORRECTION BLOC 1 : Intelligence et performances

### Périmètre
- **Hérité** : BL1-A01 → BL1-A20 (20 anomalies, rapport `audit_bloc1/RAPPORT_FINAL_BLOC1.md`).
- **Rattaché depuis le BLOC 3** :

| Ordre | ID | Correction | Contrainte impérative |
|---|---|---|---|
| 1.3 | **A22** | Raccorder la **donnée** d'ancre à ce qu'attend le critère R | **Ne pas toucher** la formule, ni `mouvCote: 0.06`, ni les poids, ni les scores historiques. Correction **aval uniquement**. |
| 1.4 | **A23** | Raccorder la **donnée** terrain (aujourd'hui figée `'Pelouse'`) | Ne pas modifier le poids `terrain: 0.05`. |
| 1.5 | **A24** | Raccorder la **donnée** catégorie (aujourd'hui `''`) | L'ajustement Handicap/Réclamer doit retrouver son alimentation, pas sa formule. |
| 1.1 | **A26** | Unifier les **7 barèmes** de décision en un seul, adaptatif | Distinguer 4 incidences : (a) recommandation affichée, (b) type de pari enregistré, (c) statistiques, (d) apprentissage effectif. **Ne pas conclure à une corruption sans preuve.** |
| 1.2 | **A27** | Décider du sort de `BestBetEngine` (587 l.) et de sa `FusionConfig` | Supprimer **ou** brancher — jamais laisser deux identités de classe. |

### Ordre interne imposé
`A26` (barème unique) **AVANT** `A01/A02` du chantier 2. `A22` (ancre) **AVANT** toute correction d'affichage du critère R.

### Interdits spécifiques
19 critères A→S, `IaPoidsAdaptatifs.defauts` (19 poids), `SeuilsConfianceAdaptatifs` (8 seuils + bornes de clamp),
descente de gradient, apprentissage TOP3, `ajusterSeuil` (delta ±2.0), **tout recalcul historique**.

---

## CHANTIER 2 — CORRECTION BLOC 2 : Analyse, statistiques et outils de contrôle

### Périmètre
- **Hérité** : BL2-A01 → BL2-A22 (22 anomalies, dont **19 réellement nouvelles**).
- **Rattaché depuis le BLOC 3** :

| Ordre | ID | Correction |
|---|---|---|
| 2.1 | **A01** | Aligner les recommandations de la page d'accueil sur le moteur (dépend de `A26`) |
| 2.2 | **A02** | Supprimer le barème d'accueil divergent |
| 2.3 | **A03** | Raccorder les compteurs d'accueil à la donnée réelle |
| 2.4 | **A04** | Distinguer **état vide** et **erreur réseau** |
| 2.5 | **A06** | Donner un retour d'état au rafraîchissement |
| 2.6 | **A39** | Retirer ou rendre fonctionnel `diagnosticPronosticRepository(DateTime(2026,5,21))` (`main.dart:132-137`) |
| 2.7 | **A28** | `WidgetService.updateFromOpportunities` : implémenter ou retirer |
| 2.8 | **A43** | Décider du sort de `reinitialiserComplet` : l'exposer au Profil **ou** assumer qu'il est réservé aux tests |

### Interdits spécifiques
Aucune création de barème. Aucune modification des seuils de confiance pour « faire passer » un test.

---

## CHANTIER 3 — CORRECTION BLOC 3 : Fonctionnement général et intégration

### Périmètre
Tout le reste du BLOC 3. **Le plus gros volume, la plus faible densité de risque.**

| Ordre | IDs | Correction | Contrainte |
|---|---|---|---|
| 3.1 | **A30** | Une seule source de vérité du programme (`PmuProvider` vs `DataRefreshService`) | **Prérequis** de 3.2 |
| 3.2 | **A05, A29, A35, A37** | **Datation des clés de course** (famille F1, 7 sites) | **Ne pas réécrire les clés historiques persistées.** Migration additive uniquement. |
| 3.3 | **A45, A46, A47** | Une seule fonction de datation ; `.toLocal()` dans `widget_service.dart:357` ; sentinelle `DateTime(2000,…)` | Dépend de 3.2 |
| 3.4 | **A32, A31, A33, A34** | Notifications natives : préfixe `flutter.`, respect des 17 champs, vibration, doublons Dart/Kotlin | `HippiqueWorker.kt`, `MainActivity.kt` |
| 3.5 | **A40, A41, A42, A44** | Intégrité de la sauvegarde : somme de contrôle, comparaison `backupVer`, booléens de setters, barrière de reset | Dépend de 3.8 (`A43`) |
| 3.6 | **A07–A18** | Paramètres du Profil sans effet réel (12 constats) | Un par un, avec vérification de l'effet **mesuré** |
| 3.7 | **A19** | Deux instances de `ProgrammeScreen` | — |
| 3.8 | **A43** | Sort de `reinitialiserComplet` (déjà rattaché au chantier 2 pour la décision ; **l'implémentation est ici**) | Un seul chantier pour le code : **3** |
| 3.9 | **A36** | Gains tardifs : worker natif ou assomption explicite du premier plan | Ne pas déplacer la logique métier |
| 3.10 | **A38** | Commentaire contredisant 4 `.ignore()` : corriger le commentaire ou rendre les erreurs visibles | — |
| 3.11 | **A48, A49, A50** | R8/ProGuard, 3 fichiers `.bak`, `USE_EXACT_ALARM` | Suppression des `.bak` **hors audit** |

### Interdits spécifiques
Aucune réécriture de clé persistée. Aucune suppression de donnée utilisateur. Aucune modification de la formule du
critère R, de son poids, ni des scores historiques.

---

## Matrice de non-duplication (contrôle final)

| Mécanisme | Chantier **responsable** | Chantiers **consommateurs** |
|---|---|---|
| Ancre du critère R | **1** | 2 (affichage), 3 (réutilisation, sans re-normaliser) |
| Barème unique de décision | **1** | 2 (statistiques), 3 (type de pari enregistré) |
| Datation des clés de course | **3** | 2 (lecture seule) |
| Source de vérité du programme | **3** | 1 et 2 (lecture) |
| Conversion temporelle | **3** | 2 (lecture) |
| Intégrité de la sauvegarde | **3** | 2 (indicateurs) |
| `reinitialiserComplet` — décision | **2** | — |
| `reinitialiserComplet` — implémentation | **3** | — |

**Aucun sous-chantier nécessitant une validation intermédiaire.** Chaque chantier est autonome une fois les dépendances
respectées dans l'ordre indiqué.

---

## Ce qui ne doit PAS être fait

1. ~~Modifier les 19 critères, poids, seuils, descente de gradient, TOP3~~.
2. ~~Recalculer les scores, pronostics ou résultats historiques~~.
3. ~~Réécrire les clés persistées existantes~~.
4. ~~Supprimer un fichier pour « nettoyer »~~ (sauf les 3 `.bak`, explicitement listés).
5. ~~Ajouter une fonctionnalité~~ : ce chantier ne corrige que l'existant.
6. ~~Créer une nouvelle branche ou réécrire l'historique git~~.
7. ~~Compiler un APK localement~~ : GitHub Actions reste seul bâtisseur.

**ARRÊT. Aucune correction n'est engagée dans cette session.**
