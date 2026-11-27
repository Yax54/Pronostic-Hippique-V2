# INSTRUMENTS EXPÉRIMENTAUX — ORGANISATION DÉFINITIVE

Date de consolidation : 27/11/2026
Décision : validée par le demandeur (consigne du 27/11/2026, point 2).

---

## 1. RÈGLE ABSOLUE — AUCUN INSTRUMENT EXPÉRIMENTAL DANS L'APK

**Preuve vérifiable, pas déclaration :**

    grep -rn "ia_experimentation\|IaExperimentation" lib/
    → 0 occurrence

Le fichier `lib/services/ia_experimentation.dart` **n'existe pas** en production.
Il n'a jamais existé que dans l'espace isolé `/home/user/exp`. C'est le seul
fichier qui rend les paramètres du moteur réglables ; sans lui, **aucun** harnais
de cette archive ne peut s'exécuter. Son absence de `lib/` est donc la preuve
mécanique que les instruments expérimentaux sont hors de l'application livrée.

Toute la famille de harnais v4 (et v3, v2 avant elle) importe ce fichier.
Elle est donc **de fait inintégrable à l'APK**, indépendamment de toute
discipline de développement.

---

## 2. POURQUOI LES SOURCES SONT ICI MAIS NON EXÉCUTABLES

Ces fichiers sont conservés comme **preuves reproductibles**, pas comme
instruments actifs.

- Tous les fichiers de `sources/` portent l'extension **`.dart.txt`** : ce ne sont
  plus des fichiers Dart, donc `flutter analyze` et `flutter test` les ignorent
  **structurellement** — aucune configuration d'analyse n'a été modifiée, aucune
  règle de lint n'a été désactivée.
- Chacun porte en outre un en-tête « ARCHIVE NON EXÉCUTABLE ».
- Ils **ne compilent pas dans ce dépôt** : ils importent
  `package:pronostic_hippique/services/ia_experimentation.dart`, absent.
- Vérification : `flutter analyze --no-pub test/audit/` → `No issues found!`
  alors que 48 fichiers d'archive sont présents dans le sous-dossier.

---

## 3. INSTRUMENTS CONSERVÉS COMME ACTIFS (dans le projet, exécutables)

Ceux-ci n'ont **pas** besoin du fork et tournent sur le **vrai moteur** :

| Fichier | Rôle | État |
|---|---|---|
| `test/audit/apprentissage_donnees_reelles_test.dart` | R1/R2/R3 — apprentissage sur corpus réel, mesure de la fenêtre | **actif, vérifié `EXITCODE=0`** |
| `test/audit/poids_comparaisons_reelles_test.dart` | comparaisons de poids sur données réelles | actif |
| `test/audit/poids_contraintes_test.dart` | bornes et contraintes collectives | actif |
| `test/audit/poids_plafonds_contrat_test.dart` | contrat des plafonds | actif |
| `test/audit/poids_nature_projection_test.dart` | nature de la projection | actif |
| `test/audit/poids_echelle_test.dart` / `poids_echelle_consommateurs_test.dart` | échelles Σ | actif |
| `test/audit/apprentissage_gel_degel_test.dart` | gel/dégel sur moteur réel | actif |
| `test/audit/apprentissage_gel_coefficients_test.dart` | gel et coefficients | actif |
| `test/audit/apprentissage_chaine_19_criteres_test.dart` | chaîne des 19 critères | actif |
| `test/audit/mecanismes_actualisation_mesure_test.dart` | actualisation | actif |
| `test/audit/chaine_19_criteres_isolate_test.dart` | chaîne en isolate | actif |
| `test/support/corpus_pmu_replay.dart` | rejeu des fixtures PMU | actif |
| `test/fixtures_corpus/` (89 fichiers, 44 courses) | corpus de non-régression | actif |

---

## 4. ARCHIVÉ — PREUVES DE CAMPAGNES TERMINÉES

Le fichier `preuves/traces_campagnes_20261127.tgz` (521 Ko) contient les journaux
bruts des campagnes **terminées et validées** :

| Journal | Campagne | Résultat |
|---|---|---|
| `g4v3_TERMINE.log` | G4v3 — gel et adaptation, 800 cycles | 800/800, `EXITCODE=0`, 4/4 blocs de phase |
| `g4v4_controle_causal` (dans sources) | G4v4 — contrôle causal 2×2, 4×200 cycles | `EXITCODE=0`, écart **exactement 0** sur 4 cellules |
| `p1c_TERMINE.log` | P1-C — poids bruts vs projetés | `EXITCODE=0` |
| `d5v2_TERMINE.log` | D5v2 — 19 critères, planchers et plafonds | 11 400 cycles mesurés |
| `g4v2_termine.log` | G4v2 — trace du gel | 68 cycles gelés, momentum exactement 0 |
| `e1.log` | E1 — collectif (171 paires parasites) | `EXITCODE=1` **refus assumé**, défaut n°20 |
| `g5.log` | G5 — poids initiaux négatifs | conservé |

Ces journaux ne sont **pas** à rejouer : leurs conclusions sont acquises.

---

## 5. ABANDONNÉ — NE PAS RÉPARER

| Instrument | Raison de l'abandon |
|---|---|
| `_campagne_g4v5_gel_nefaste_test.dart` | Refusé par son propre garde : `\|r\|80 = 0,0268` au lieu de 0,80. Le scénario « critère devenu néfaste en conservant la corrélation » est **inexprimable** dans la famille v4, car `motif(n) = 3 − n` est PARTAGÉ : inverser γ **détruit** la covariance au lieu de la conserver. |
| `_sonde_G5_calibrage_test.dart` | Sonde écrite pour calibrer G4v5 ; sans objet puisque G4v5 est abandonné. |

**Décision explicite :** ces deux fichiers restent dans `sources/` comme trace de
la tentative, mais **aucun effort de réparation ne leur sera consacré**. Le
demandeur a arbitré : on ne perfectionne pas un instrument dont l'utilité pour
l'application n'est pas démontrée.

---

## 6. DOUBLONS — v2 ET v3

`_harnais_v2.dart` et `_harnais_v3.dart` sont conservés dans `sources/` (preuve
historique) mais sont **remplacés par `harnais_v4`**.

Vérification des dépendances avant tout retrait : 17 harnais de campagne
importent encore v3 (D5, E1, T3, I1, F, G4v2, G5, H, V0/V1…), ce sont
précisément les campagnes dont les conclusions sont **acquises ou abandonnées**.
Aucun instrument **actif** ne dépend de v2 ou v3.

Conservation décidée : ils restent dans `sources/` à titre de preuve. Aucune
suppression physique n'a été effectuée — conformément à la consigne
« aucune suppression définitive des instruments avant validation ».

---

## 7. DÉFAUTS DE HARNAIS — BILAN DES 21

| Statut | Nombre | Détail |
|---|---|---|
| **Corrigés définitivement** | 18 | n°1 à n°14 (voir `DIX_OBLIGATIONS_PREUVES.md`), n°15 à n°21 sauf ci-dessous |
| **Corrigés et vérifiés** | 3 | n°15 (sel du bruit), n°18 (sel du signal latent), n°19 (amorçage), n°21 (instant de vérification) — voir note |
| **Restants, dans des instruments ABANDONNÉS** | 3 | G4v5 (scénario inexprimable), sonde G5 (sans objet), E1 (171 paires parasites — campagne remplacée par E1v2) |
| **Devenus sans objet** | 0 | — |

> Note : les n°15 à n°21 sont comptés dans les 18 corrigés ; la ligne
> « corrigés et vérifiés » liste ceux dont la correction a été **re-mesurée**
> après coup. Les trois défauts restants n'ont **aucune conséquence** sur les
> conclusions du rapport : ils appartiennent tous à des instruments dont les
> résultats ne sont pas utilisés.

---

## 8. RÈGLE DE MAINTENANCE

1. Aucun fichier de `sources/` ne doit être rendu exécutable sans décision explicite.
2. Aucun harnais nouveau ne doit être créé sans une question de production à trancher.
3. Les instruments actifs (§3) tournent sur le **vrai moteur**, jamais sur un fork.
4. Toute conclusion doit reposer sur une mesure du moteur réel, pas sur une
   propriété supposée du générateur.
