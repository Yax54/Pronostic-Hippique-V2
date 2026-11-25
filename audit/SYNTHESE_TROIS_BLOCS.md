# SYNTHÈSE CONSOLIDÉE DES TROIS BLOCS
## Application « Race Predictor » / « Pronostic-Hippique-V2 » — Dart `pronostic_hippique`

**Référence auditée** : `2e96aae1d98a1af61cc5ad2bb24010de5c718500` — branche `main`
**Protocole** : lecture statique exclusive. Aucune exécution, aucun build, aucune modification du dépôt.

---

## 1. Bilan chiffré

| Bloc | Identifiants | Distinctes | Nouveautés réelles | Livrable |
|---|---|---|---|---|
| **BLOC 1** — Intelligence et performances | BL1-A01 → A20 | **20** | 20 | `audit_bloc1/RAPPORT_FINAL_BLOC1.md` — 1102 l. / 76 458 o |
| **BLOC 2** — Analyse, statistiques, outils de contrôle | BL2-A01 → A22 | **22** | **19** (3 recoupements) | `audit_bloc2/RAPPORT_BLOC2.md` — 1358 l. / 108 174 o |
| **BLOC 3** — Fonctionnement général et intégration | BL3-A01 → A50 | **49** (A20 fusionné) | — | `audit_bloc3/RAPPORT_BLOC3.md` |
| **TOTAL** | **92 numéros** | **91** | — | 3 rapports |

**Rapprochement par cause technique** : après élimination des doublons inter-blocs, le total consolidé est de
**88 anomalies distinctes** (voir §3 ci-dessous). Le chiffre « 39 distinctes » cité à l'ouverture du BLOC 3 ne
concernait que les blocs 1 et 2.

---

## 2. Répartition par gravité — BLOC 3

| Gravité | Nombre | Identifiants |
|---|---|---|
| **CRITIQUE** | **2** | A22 (critère R neutralisé), A26 (7 barèmes concurrents) |
| **HAUTE** | **5** | A05, A21, A29, A31, A32 |
| **MOYENNE** | **22** | A01, A02, A07–A18 (partiel), A19, A23, A24, A27, A30, A33, A34, A35, A36, A40, A41, A42, A43, A45, A46, A50 |
| **FAIBLE** | **20** | A03, A04, A06, A11, A25, A28, A37, A38, A39, A44, A47, A48, A49 + constats §3 |
| **Fusionné (non compté)** | **1** | A20 → conséquence de A19 |

---

## 3. Les neuf familles transversales (une cause, plusieurs sites)

| Famille | Cause unique | Sites mesurés | IDs |
|---|---|---|---|
| **F1** Clé de course sans date | Construction `R{n}C{m}` sans `dateStr` | **7 sites** dans `lib/` | **A05, A29, A35, A37** |
| **F2** Critère IA neutralisé | Donnée source absente / mauvais format | 3 critères (R, Terrain, Catégorie) | **A22, A23, A24** |
| **F3** Barèmes concurrents | 7 implémentations de « quel pari conseiller » | 3 adaptatives / 4 figées | **A26, A27** |
| **F4** Paramètre UI sans effet | Contrôle non raccordé au moteur | 12 constats au Profil | **A07–A18** |
| **F5** Préfixe `flutter.` ignoré | Lecture `prefs` native sans `removePrefix` | **6 canaux sur 6** | **A32** |
| **F6** Double moteur de notification | Dart + Kotlin émettent en parallèle | 3 doublons par course | **A31, A34** |
| **F7** Validation d'entrée absente | Import / restauration sans contrôle | 5 groupes, 13 champs | **A40, A41, A42** |
| **F8** Fonction sans appelant | Code exposé mais jamais invoqué | `reinitialiserComplet` (1 occ.), `updateFromOpportunities` | **A28, A43** |
| **F9** Conversion temporelle non centralisée | 3 formats, 4 conversions indépendantes | 19 `DateTime.parse`, 1 `.toLocal()` manquant | **A45, A46, A47** |

---

## 4. Les six défauts à traiter en premier (P0)

| Rang | ID | Défaut | Conséquence **mesurée** |
|---|---|---|---|
| 1 | **A22** | Ancre produite `'$numOfficiel$numOrdre'` ≠ ancre attendue `R{n}C{m}` par le critère R | **Critère R neutralisé en permanence** — 6 % (`mouvCote: 0.06`) du score jamais appliqué |
| 2 | **A26** | 7 barèmes concurrents, 4 figés | La recommandation **affichée** n'est pas nécessairement celle **enregistrée** |
| 3 | **A05 / A29** | Clé de course sans date | **Un pari d'hier peut être réglé par la course d'aujourd'hui** |
| 4 | **A32** | 6 canaux natifs violent le préfixe `flutter.` | **3 fonctionnalités d'arrière-plan inertes** |
| 5 | **A31** | 17 champs d'`AlertConfig` ignorés hors premier plan | L'utilisateur reçoit des alertes qu'il a désactivées |
| 6 | **A21** | Panne réseau présentée comme « aucune course aujourd'hui » | L'utilisateur conclut à l'absence de course |

---

## 5. Ce que l'audit n'a PAS prouvé — et ne prétend pas

| Point | Formulation exacte |
|---|---|
| **Corruption de l'apprentissage** | **Non prouvée.** A26 décrit une divergence de barèmes ; aucune corruption des scores historiques n'est démontrée. |
| **Code mort des 5 écrans** | **Non prouvé.** Formulation retenue : « chemin d'accès non identifié ». Un point d'entrée hors du parcours lu n'est pas exclu. |
| **Performance réelle** | **Aucune mesure** de RAM, batterie, latence, frame rate. Tous les énoncés sont des **risques statiques**. |
| **Affichage / accessibilité** | **Aucun test sur appareil**, aucun `adb`, aucune capture. |
| **Perte de gain observée** | **Aucune.** A40/A42 sont des **absences de contrôle**, pas des pertes constatées. |
| **`USE_EXACT_ALARM`** | Usage dans `flutter_local_notifications` **non exclu** ; formulation : « usage non démontré côté dépôt ». |
| **Fusion des archives IA** | `IaArchiveService` : **algorithme non audité**. |

---

## 6. Points positifs à ne pas défaire

1. **Rétention réellement bornée** : `_maxPronostics = 600`, `_maxPronosticsAge = 90 j`, `_premiumHistoriqueMaxJours = 90`,
   `_sentAlertIds.take(200)` avant persistance, `_securiserExcedentAvantEcriture` avant écriture tronquée.
2. **Barrières anti-course raccordées** dans 5 services (`_resetEnCours` / `_generationCache`), avec drainage en boucle
   `while (_ecrituresEnCours.isNotEmpty)` — motif correct, rare.
3. **Chaîne des gains tardifs** : la **seule** du dépôt qui documente et neutralise explicitement le risque de clé non
   datée (`IdentiteCourseTardive.cle`, validation à trois composantes, `if (id.date == null) continue;`).
4. **Aucun secret en dur**, **aucun `http://`** dans `lib/`, `profil_photo_path` exclu de l'export.
5. **Séparation des 7 catégories financières** vérifiée conforme ; aucun recalcul historique détecté.
6. **Deux convertisseurs d'horodatage sur trois** appliquent bien `.toLocal()` — l'anomalie A46 est **l'exception**.
7. **Ceinture de sécurité ELO** documentée : `mettreAJourApresArrivee` n'a pas d'idempotence interne, le garde est posé
   à l'appelant (`data_refresh_service.dart:1186-1194`).

---

## 7. Verdict

L'application **fonctionne** : aucune perte de données n'a été observée, aucun crash n'a été démontré, aucun recalcul
historique n'a eu lieu. Mais **trois mécanismes centraux sont partiellement neutralisés** (critère R, Terrain,
Catégorie), **sept barèmes coexistent**, la datation des clés est **incohérente sur 7 sites**, et l'intégrité de la
sauvegarde repose sur **un seul champ `appName`**.

Le chantier de correction est donc **justifié**, mais il doit respecter impérativement les règles de non-duplication et
l'interdiction de modifier poids, seuils, formules et scores historiques.

**ARRÊT. Aucune correction n'a été engagée.**
