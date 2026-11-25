# AUDIT BLOC 1 — RAPPORT FINAL CONSOLIDÉ
## Application « Race Predictor » / « Pronostic-Hippique-V2 » — IA hippique

**Dépôt** : `Yax54/Pronostic-Hippique-V2` · branche `main` · HEAD au moment de l'audit : `2e96aae`
**Périmètre** : BLOC 1 uniquement (IA hippique, 19 critères, poids, seuils, scores, descente de gradient,
apprentissage IA, TOP3, Mémoire IA — tous outils, BACKTESTING, Best Bet — tous outils, interactions transversales).
**BLOCS 2 et 3 : NON ENTRAMÉS** (arrêt volontaire conformément à la consigne).
**Environnement figé** : Flutter 3.35.4 · Dart 3.9.2 · Android API 35 · build-tools 35.0.0 · Java 17.
**Protections** : aucune correction, aucune modification de code/test/donnée/poids/seuil/algorithme,
aucun recalcul historique, aucun commit, aucun push, aucune compilation APK.
`git status --porcelain` → **vide**. Tous les outils d'analyse sont **hors dépôt** (`/home/user/audit_bloc1/`).

---

## 0. VÉRIFICATION DES OUTILS D'ANALYSE

| Outil | Présent | Verdict |
|---|---|---|
| Dart SDK | 3.9.2 (stable) | ✅ |
| Flutter | 3.35.4, revision `d693b4b9db` | ✅ |
| Dart Analysis Server (`dart analysis-server`) | oui | ✅ déclarations uniquement |
| `package:analyzer` dans le projet | **non** (86 paquets, 0 dans `pubspec.lock`) | ❌ |
| `package:analyzer` via pub-cache | 6.9.0 exige `_macros 0.3.3 from sdk` (**absent en 3.9.2**) ; 7.4.5 plante dans `macro_injected_impl.dart` | ❌ |
| `dart_code_metrics` | absent | ❌ |
| `flutter_lints`, `lints` | présents | ✅ |

## 0bis. ÉCHEC DÉMONTRÉ DE LA CARTOGRAPHIE AUTOMATIQUE DES RÉFÉRENCES (3 preuves)

1. `search.getElementDeclarations` **fonctionne** à l'échelle du projet : **10 489 déclarations en 57 s**,
   avec résolution sémantique réelle (`computeAll` → `METHOD`, `returnType: List<BetOpportunity>`).
2. `search.findElementReferences` **n'émet jamais** la notification `search.results`
   (3 diagnostics indépendants `diag.py`, `diag2.py`, `diag3.py` ; `diag3` attend 600 s : `status=None`,
   puis 3 recherches TIMEOUT à 180 s).
3. `analysis.getNavigation` → `0 targets`.

**Conséquence assumée** : `carto.json` (3,7 Mo, `refs: []` sur 10 489/10 489) est **INVALIDE et exclu** de
toutes les conclusions. La cartographie a été faite par **lecture ciblée des chaînes fonctionnelles** +
`grep -rn`, chaque constat étant datable à un numéro de ligne et à un extrait de code.
**Limite de preuve conservée** : un `grep` vide n'est **pas** une preuve de code mort (aucune référence
dynamique `Function.apply` / map de callbacks n'a été trouvée, mais l'absence n'est pas une preuve formelle) ;
et l'absence d'appelant statique n'exclut pas un appel via `Provider`, `InheritedWidget` ou factory.

---

## 1. NAVIGATION — CHAÎNE PROUVÉE

`main()` l.75 → `runApp(PronosticHippiqueApp())` l.142 → `MaterialApp` l.161 →
`home: IaBubbleOverlay(child: MainNavigation())` l.211 → `MainNavigation` l.218.
`NavigationNotifier extends ChangeNotifier` l.40, `goTo(int)` l.44, raccourcis sémantiques l.52-58.
`_navItems` = **11 entrées** (l.321). `Scaffold(body: IndexedStack(index: currentIndex, children: _screens))` l.449-452.

Chaîne **démontrée** : `_navItems[9]` « Audit » → `goTo(9)` → `goToAudit()` → `IndexedStack(index: 9)` → `AuditScreen`.
Aucun routage nommé, aucun GoRouter, aucun `Navigator.pushNamed` dans toute l'application.
`IndexedStack` maintient **les 11 écrans montés en permanence** — conséquence : tous les services d'un écran
sont vivants dès le démarrage (cf. §16 interactions).

---

## 2. `best_bet_engine.dart` — CORRECTION DÉFINITIVE

- Déclarations mesurées : `FusionConfig` l.38, `BestBetEngine` l.109, `BestBetSort` l.306, `_RawOpportunity`,
  `BetOpportunity`, `FusionLevel`. `computeAll(...)` l.111, retour `List<BetOpportunity>`.
- `computeAll()` : **0 appelant** dans `lib/`, `test/`, `integration_test/`. Seule occurrence textuelle : un
  **commentaire** dans `best_bet_screen.dart:341`.
- **Le fichier n'est PAS du code mort** : `TypePariCalc` 51 occurrences externes, `GainResult` 31,
  `StatDiscipline` 8, `StatTypePari` 4, `BetOpportunity` 2.
- **`FusionConfigScreen` (l.15) n'est importé nulle part** ; `FusionConfigService` n'est lu par aucun service ;
  les 4 clés de config fusion sont pourtant listées dans les clés de backup (`backup_service.dart:29`).
  → écran accessible depuis **aucun** point de navigation.
- **Remplacement fonctionnel NON démontré** : `best_bet_screen` n'a ni `valeurAttendue`, ni normalisation
  relative au groupe du jour, ni bonus ×1.15 / ×1.07, ni pénalités ×0.80 / ×0.92 / ×0.88, ni `FusionConfig`,
  ni évaluation multi-type de `GainCalculator`.

---

## 3. POIDS IA — CLARIFICATION N° 2 : JSON COMPLET vs JSON INCOMPLET

### 3.1 Ce que `IaPoidsAdaptatifs.toJson()` écrit réellement (mesuré, `ia_memory_models.dart` l.790-809)

Les **19 clés de critères** sont toutes écrites, plus :
`nbMisesAJour`, `calibrationScore`, `poidsParDiscipline`, `dernierGradient`, `poidsIndices`, `correlations`.
Les commentaires `★ v9.92` / `★ v9.93` signalent que `mouvCote` et `placeDepart` **manquaient avant** ces versions.

`fromJson` (l.812-852) lit exactement les mêmes 19 clés. Replis mesurés :

| Clé | Repli `fromJson` | Constructeur `IaPoidsAdaptatifs()` |
|---|---|---|
| `forme` | **0.32** | 0.25 |
| `gains` | **0.15** | 0.13 |
| `record` | **0.12** | 0.10 |
| 16 autres | = constructeur | identiques |

### 3.2 CONCLUSION PRÉCISE — LE 1.37 N'EST PAS GÉNÉRALISABLE

`_save()` (`ia_memory_service.dart:2693`) écrit **toujours** `json.encode(_poids.toJson())` : tout JSON produit
par l'application contient **forme, gains et record**. Le total restauré est donc **celui qui avait été sauvegardé**,
jamais 1.37.

| Chemin de restauration | Contenu du JSON | Total après `_load()` |
|---|---|---|
| 1ᵉʳ lancement (clé absente) | — | `_poids` = constructeur → **1.26**, forme 0.25 |
| `resetPoids()` | `_save()` écrit intégralement le constructeur | **1.26**, forme 0.25 |
| Backup antérieur au 1ᵉʳ apprentissage | 19 clés écrites par `toJson()` | **1.26**, forme 0.25 |
| Backup post-apprentissage | 19 clés | **valeur apprise** |
| Backup antérieur à v9.92 / v9.93 | 17 clés (sans `mouvCote`, `placeDepart`) | valeur sauvegardée + replis 0.06 / 0.03 → **inchangé** |
| **JSON tronqué / édité / corrompu, sans `forme`/`gains`/`record`** | incomplet | **1.37** ← **seul cas** |

**Le 1.37 est donc un repli LATENT, atteignable uniquement par donnée corrompue ou éditée à la main — pas par
une restauration de backup normale.** Toute affirmation antérieure « un backup pré-apprentissage restaure 1.37 »
est **retirée** et corrigée (§17, corrections n°9).

Reste vrai et mesuré : `_load()` (l.2227-2231) et `resetPoids()` (l.6402-6407) **n'appellent ni `clamp()` ni
`normaliser()`** → la somme n'est ramenée à 1.000000 que par l'apprentissage (`clamp()` l.3992 / l.4402,
`normaliser()` l.5902).

### 3.3 Deux jeux par défaut divergents subsistent ailleurs

`IaPoidsAdaptatifs.defauts` (const, l.858) = **1.37 / forme 0.32** est utilisé comme **repli de calcul** en
deux endroits : `ia_memory_service.dart:4180` (gradient discipline) et `simulation_service.dart:200`.
Une même notion de « poids par défaut » a donc **deux valeurs** (0.25/1.26 et 0.32/1.37) selon le fichier.

---

## 4. POIDS IA — CLARIFICATION N° 3 : SOMME vs DISTRIBUTION SOUS LA NORMALISATION RÉELLE

### 4.1 Normalisation réellement appliquée (`ia_pronostic_engine.dart:160-180`)

```dart
if (range <= 1.0) return;                       // pas de normalisation
ratioNorme = n <= 6 ? 0.40 : n <= 12 ? 0.60 : 0.75;
ratioBrut  = 1.0 - ratioNorme;
scores[k]  = ((brut - minS)/range*100) * ratioNorme + brut * ratioBrut;
```
Ce **n'est pas un min-max pur** : la composante brute est conservée à hauteur de `ratioBrut` (25 % à 60 %).
Conséquence mathématique exacte : pour un facteur d'échelle global `k` sur tous les poids,
`minS`, `maxS`, `range` et `(brut-min)/range` sont **invariants** ⇒ **l'ORDRE des partants ne change jamais** ;
seule la composante brute `brut * ratioBrut` est multipliée par `k` ⇒ **les valeurs absolues changent**.

### 4.2 Mesures (Monte-Carlo, 4 000 courses par scénario, tailles n ∈ {5,6,8,10,12,14,16,18}, critères uniformes)

| Scénario | rang 1 différent | ordre complet différent | label du top1 différent | inflation moyenne du score du top1 |
|---|---|---|---|---|
| **S1 — EFFET DE LA SOMME SEULE** (distribution identique, 1.00 vs 1.26) | **0.00 %** | **0.00 %** | 3.43 % (fourchette 1.5-5.5 % selon l'étalement supposé des critères) | **+5.98 pts** (max +7.93) |
| **S2 — EFFET DE LA DISTRIBUTION SEULE** (les deux ramenés à 1.00) | **7.45 %** | **73.80 %** | 0.55 % | +0.24 pt |
| **S3 — PRODUCTION BRUTE** (1.26 vs 1.37, aucun `clamp`) | 8.38 % | 73.65 % | 0.00 % | +2.82 pts |

Détail mesuré du seuil 75 (saturation) sur 4 000 courses, composante somme seule :
`score ≥ 75` : 98.40 % → **100.00 %**, soit **+1.60 pt de bascule** ; seuil 52 : 100 % → 100 % (**+0.00 pt**).
`confianceIA` (`zt_models.dart:939`) : **+2.12 pts en moyenne** (max +4.90, min +1.23).

### 4.3 Conclusion — la démonstration antérieure était mal attribuée

- **La somme des poids ne modifie JAMAIS l'ordre** (0.00 % sur 32 000 comparaisons) : elle n'inflate que les
  **valeurs absolues** (+≈6 pts) et ne déplace donc que les pronostics déjà situés à la frontière du seuil
  absolu 75 de `_determinerLabel()` (`ia_pronostic_engine.dart:705-707`), soit ≈1,5 à 5,5 % des courses.
- **La distribution relative, elle, change réellement l'ordre** : 7,45 % de rang 1 différents et 73,80 % d'ordres
  complets différents. C'est **le seul effet métier réellement dangereux**.
- Le chiffre antérieur « 12,23 % de changements de label, +6,10 pts, max +60,41 » **n'est pas reproductible**
  avec la normalisation réellement codée (le max mesuré est **+12,38** sur les étalements testés). Il est
  **retiré** et remplacé par les trois scénarios ci-dessus. La conclusion de fond demeure : `_determinerLabel()`
  compare des seuils **absolus** (75 / 52) à des scores dont l'échelle dépend des poids — **non invariant à
  l'échelle**, donc l'inflation est réelle, mais **bornée à +≈6 pts** et **sans effet sur le classement**.

---

## 5. CASCADES DE TYPE DE PARI — CLARIFICATION N° 1 : IMPLÉMENTATIONS / SITES D'APPEL / CONSOMMATEURS

Le rapport précédent annonçait « 5 sites » tout en listant 6 lignes, et mentionnait d'autres consommateurs
ensuite. **Les trois notions sont désormais séparées.**

### 5.1 Les 15 occurrences de `if (course.isQuinte)` — classement exhaustif (mesuré : 55 occurrences de `isQuinte` dans `lib/`)

| # | Fichier:ligne | Nature réelle |
|---|---|---|
| 1 | `best_bet_screen.dart:354` | **Implémentation de cascade** (famille A) |
| 2 | `conseils_screen.dart:303` | **Implémentation de cascade** (famille B) — `_getTypePariPourCourse` |
| 3 | `conseils_screen.dart:1274` | **Implémentation de cascade** (famille B) — widget carte |
| 4 | `conseils_screen.dart:1355` | **Affichage** d'un badge « Quinté » (pas une cascade) |
| 5 | `home_screen.dart:1408` | **Affichage** d'un badge (pas une cascade) |
| 6 | `home_screen.dart:2828` | **Affichage** d'un badge (pas une cascade) |
| 7 | `programme_screen.dart:737` | **Affichage** d'un badge (pas une cascade) |
| 8 | `races_screen.dart:559` | **Affichage** d'un badge (pas une cascade) |
| 9 | `alert_service.dart:1945` | **Implémentation de cascade** (famille B) |
| 10 | `ia_memory_service.dart:6215` | **Implémentation de cascade** (famille A) — `recreerPronosticsManquants` |
| 11 | `ia_pronostic_engine.dart:725` | **Texte explicatif** (`_genererExplication`) — pas un type de pari |
| 12 | `widget_service.dart:104` | **Implémentation de cascade** (famille A) |
| 13 | `data_refresh_service.dart:115` | **Implémentation de cascade** (famille A) — isolate |
| 14 | `data_refresh_service.dart:1062` | **Implémentation de cascade** (famille A, **incomplète**) — fallback |
| 15 | `premium_utils.dart:41` | **Implémentation de cascade** (famille A) — « source unique de vérité » |

### 5.2 Nombre exact

- **Implémentations de cascade de type de pari : 9** (lignes 1, 2, 3, 9, 10, 12, 13, 14, 15 du tableau ;
  ligne 11 exclue car simple texte explicatif) → précisément **9** blocs de code :
  `best_bet_screen:354`, `conseils_screen:303`, `conseils_screen:1274`, `alert_service:1945`,
  `ia_memory_service:6215`, `widget_service:104`, `data_refresh_service:115`,
  `data_refresh_service:1062`, `premium_utils:41`. Les lignes 4 à 8 et la ligne 11 ne sont pas des
  implémentations : 5 sont de purs affichages de badge, 1 est un texte explicatif (cf. §5.1).
- **Sites d'appel** : `best_bet_screen` = 1 appel interne ; `conseils_screen:303` = 1 (`_getTypePariPourCourse`) ;
  `conseils_screen:1274` = 1 (builder de carte) ; `alert_service:1945` = **2** appelants directs
  (l.1783 et l.1881) ; `ia_memory_service:6215` = 1 (`recreerPronosticsManquants`) ;
  `widget_service:104` = 1 (`updateFromReunions`, appelé par `data_refresh_service.dart:694`) ;
  `data_refresh_service:115` = 1 (isolate `_calculerPronosticsBatch`) ; `data_refresh_service:1062` = 1
  (fallback, atteint seulement si l'isolate échoue) ; `premium_utils:41` = 5 appelants
  (`home_screen.dart` l.569, 597, 630, 662, 1741).
- **Consommateurs finaux** (qui voit le verdict) : Best Bet (écran 4), Conseils (écran 1) via 2 cascades,
  notifications `AlertService`, `IaPronostic.typePariConseille` persisté (donc Calendrier, IA Stats,
  ROI/Value, Backtesting, Profil), widgets premium du jour, widget Android (`WidgetService`),
  Home (via `premium_utils`).

### 5.3 Deux familles persistantes (confirmé)

| Famille | Accès aux seuils appris | Membres |
|---|---|---|
| **A — adaptative** | `IaMemoryService.instance.seuilsConfiance` | `best_bet_screen:307`, `premium_utils:38`, `data_refresh:1053`(+payload isolate l.944-945), `ia_memory:6215` (`_seuils`), `widget_service:99` |
| **B — figée** | **aucun** (`grep "seuilsConfiance\|_seuils\."` → **0 occurrence**) | `conseils_screen`, `alert_service` |

### 5.4 Divergence codée en dur dans la famille A

`data_refresh_service.dart:1062` (`_enregistrerPronosticsBatchFallback`, l.1030) **omet la branche
`else if (course.isQuarte) typePari = 'Quarté+'`** présente aux l.117 (isolate), `ia_memory:6217`,
`premium_utils:43` et `best_bet_screen:356`. Chemin d'atteinte : `_enregistrerPronosticsAuto` (l.872)
→ `_enregistrerPronosticsBatchIsolate` (l.886) → `catch` l.1025 → fallback. **Atteignable uniquement si
l'isolate échoue** (pression mémoire) — un échec suffit à écrire un `typePariConseille` erroné pour toutes
les courses Quarté+ du lot, donc dans l'historique exploité par le backtesting et les statistiques.

### 5.5 Cascade supplémentaire non recensée auparavant : `widget_service.dart:104`

Elle **n'a pas de branche `Couplé Placé`** (contrairement aux 4 autres membres de la famille A) et s'arrête
à `else { typePari = 'À surveiller'; }` sans passer par `seuilGagnantPlace` ni `seuilTierce`. Un score de
40-49 donne donc `'À surveiller'` là où `best_bet_screen` aurait donné `'Tiercé'` (seuil 35).

### 5.6 Cloisonnement mesuré des seuils sur 8

`seuilQuarte` et `seuilQuinte` ne sont **lus par aucune cascade** : leurs seules lectures sont
**d'affichage** (`ia_performance_screen.dart:3123-3124`, `ia_precision_widget.dart:756-757`).
`ajusterSeuil` les modifie pourtant (`ia_memory_service.dart:7693`) et les persiste (`toJson` `'qa'`/`'qi'`).
→ **2 seuils sur 8 sont appris, persistés, affichés, et sans aucun effet sur une décision.**

---

## 6. SEUILS — `seuilGagnantPlace` = 50.0 (et non 80)

| Seuil | Commentaire de classe | Valeur réelle |
|---|---|---|
| `seuilSimpleGagnant` | 80 | 80.0 ✅ |
| **`seuilGagnantPlace`** | **80 (ou 50)** | **50.0** ❌ **−30 pts** |
| `seuilSimplePlace` | 65 | 65.0 ✅ |
| `seuilCoupleGagnant` | 75 | 75.0 ✅ |
| `seuilCouplePlace` | 60 | 60.0 ✅ |
| `seuilTierce` | 35 | 35.0 ✅ |
| `seuilQuarte` | 80 | 80.0 ✅ (affichage seul) |
| `seuilQuinte` | 0 | 0.0 ✅ (affichage seul) |

Le commentaire ligne 7648 est trompeur. Valeur effective **50.0**, cohérente entre constructeur, `fromJson`
(`'gp' ?? 50.0`, l.7715) et **affichage** (`ia_performance_screen.dart:3119` passe `50.0` en valeur « par défaut »).
**Conséquence** : la branche `scoreConf >= seuilGagnantPlace → 'Gagnant+Placé'` (best_bet:379, data_refresh:129
et 1074, ia_memory:6229, premium_utils:55) se déclenche dès 50/100, **après** `seuilSimplePlace` (65) dans la
cascade — elle est donc évaluée **après** `seuilSimplePlace` (65) et **ne capte que la plage 50-64**.
**Conclusion mesurée** : pour tout `scoreConf` de 50 à 64, la cascade franchit `seuilSimpleGagnant` (80) non,
`seuilSimplePlace` (65) non, puis `seuilGagnantPlace` (50) **oui** → le libellé produit est `'Gagnant+Placé'`.
La plage 50-64 est donc **atteinte et active**, alors que la documentation de classe annonce 80.
Le libellé `'Simple Placé'` (branche `seuilSimplePlace`=65) n'est jamais atteint pour un score < 65, et la
branche `seuilGagnantPlace` ne peut jamais être atteinte au-delà de 64 puisque `seuilSimplePlace` la
précède dans la cascade.

---

## 7. CLARIFICATION N° 4 — RÉINITIALISATION DES ÉTOILES DU CALENDRIER : EFFETS RÉELS

### 7.1 Interface (mesuré, `ia_calendrier_tab.dart`)

- `onTap: () => _ouvrirResetEtoile(context)` l.393 → `BottomSheet` l.419 avec **2 choix** :
  `Navigator.pop(_, 'date')` l.475 et `Navigator.pop(_, 'all')` l.487.
- Mode `'date'` : `showDatePicker` puis **`AlertDialog` de confirmation** (Annuler l.544 / Supprimer l.548).
- Mode `'all'` : **`AlertDialog` « Zone dangereuse »** (Annuler l.597 / Tout supprimer l.601).
- **Les deux chemins sont confirmés** → aucune anomalie de protection ici.

### 7.2 Effets réels — écritures

| Action | Écritures SharedPreferences | Écritures services indirectes |
|---|---|---|
| `resetPremiumPourDate(date)` (`ia_memory_service.dart:6854`) | `setString('ia_premium_historique_v1', …)` (l.6875 ou l.6879) ; **si la date est aujourd'hui** : `remove('ia_premium_du_jour_v1')` (l.6889) | **aucune** (`_chargerPremiumHistorique()` l.6822 = lecture pure ; `notifyListeners()`) |
| `resetToutesEtoilesPremium()` (l.6907) | `remove('ia_premium_historique_v1')` (l.6914) + `remove('ia_premium_du_jour_v1')` (l.6915) | **aucune** |

Les deux passent par `_ecrireProtege(..., propagerErreur: true)` (`ia_memory_service.dart:6925`), qui
**n'appelle ni `_save()`, ni `_purgerVieuxPronostics()`, ni `_basculerBilans()`**. Vérifié : `_ecrireProtege`
exécute **uniquement** l'action fournie (l.6874-6886).

### 7.3 Effets fonctionnels réels (ce qui est VRAIMENT perdu)

| Donnée | Touchée ? | Preuve |
|---|---|---|
| `_premiumHistorique` (RAM) | **oui**, vidé ou amputé d'une date | l.6895 / l.6918 |
| `_premiumCourseKeys` (RAM, jour) | **oui si reset du jour** | l.6890 / l.6919 |
| `_pronostics`, poids, seuils, gradient, TOP3, journal, rapports, bilans, stats | **non** | aucune écriture de ces clés dans les 2 méthodes |
| `IaArchiveService` (shards permanents) | **non** | 0 occurrence d'`IaArchiveService` dans les 2 méthodes |
| `premium_widgets_selection_jour_v1` (5 sélections figées) | **non** | clé distincte (l.121), jamais touchée ici |
| `pronostic_resultats_repository_v2` (gros paris) | **non** | jamais touché ici |

### 7.4 Conséquences observables

1. **Perte DÉFINITIVE des étoiles** : `enregistrerPronosticsPremiumDuJour` (`ia_memory_service.dart:6409`) ne
   réécrit que les premiums **du jour présent**. Une fois l'historique supprimé, **aucune réparation n'est
   possible pour les jours passés** — c'est irréversible, comme annoncé par le dialogue.
2. **`calculerStreakPremium` (l.6743) et `calculerToutesStreaksPremium` (l.6775)** repartent de 0 : les séries
   affichées sur **Home** (`home_screen.dart:446-450`, 5 appels) disparaissent rétroactivement.
   Un reset d'**une seule date** casse aussi la série : `_premiumSourceGagnantLeJour` renvoie `false` pour ce
   jour → `break` immédiat (l.6759). **Effet en cascade sur tous les jours antérieurs.**
3. **Palier OR du calendrier** (`ia_calendrier_tab.dart:299`) et badges dorés (`premiumsPourDate`, l.2642)
   perdent les jours effacés.
4. **Traçabilité du backtesting** (`ia_tab_backtesting.dart:1480`, `_buildTraceabiliteBacktesting`) : le
   compteur « Affichés en Premium » retombe à 0 sur la période — **le backtesting ne devient pas faux, mais
   son indicateur de traçabilité premium devient vide alors que les courses ont bien existé**.
5. **Aucune conséquence sur l'apprentissage** : le gradient, les poids, les seuils, le TOP3 ne lisent jamais
   `_premiumHistorique`. **Confirmé par lecture** : les 12 lectures de `_premiumHistorique` (l.914, 6504, 6515,
   6534, 6684, 6718, 6754, 6816-6840, 6895, 6918) sont toutes dans la couche premium/streak/Calendrier.

**Verdict** : l'affirmation de l'interface (« ne touche pas à la mémoire IA ni à l'apprentissage ») est
**exacte**. L'affirmation implicite de réversibilité ne l'est pas — mais le dialogue annonce explicitement
« Cette action est irréversible ». **Aucune anomalie de protection. Une anomalie de traçabilité (BL1-A07).**

---

## 8. CLARIFICATION N° 5 — ANOMALIE PRIORITAIRE : `resetPoids()` SANS CONFIRMATION

**Code exact** (`ia_performance_screen.dart`) :

```
1387:  GestureDetector(
1388:    onTap: () async {
1389:      await mem.resetPoids();
1390:      if (mounted) { ... SnackBar('Poids réinitialisés aux valeurs par défaut') ... }
```

- **Aucun `showDialog`, aucune confirmation, aucun `AlertDialog`** dans le bloc l.1387-1400.
- Le bouton est un simple `Container` de 8 px de padding horizontal sur 4 px vertical, libellé « Reset » en
  rouge — **cible tactile très petite, donc exposée au tap accidentel**, dans une carte de l'onglet 1
  « 🧠 Mémoire IA ».
- **Asymétrie démontrée** : la même page protège l'effacement total par un dialogue
  (« Effacer la mémoire IA ? », l.1521-1537) avant `clearHistory()` + `resetPoids()` (l.1536-1537). **Le geste
  le moins protégé est aussi le moins visible.**
- **Ce qui est perdu** : `resetPoids()` = `_poids = IaPoidsAdaptatifs()` (l.6402-6407) → **19 poids appris
  détruits**, `nbMisesAJour` remis à 0, `calibrationScore` à 50.0, `poidsParDiscipline` vidé,
  `dernierGradient` vidé, `correlations` vidées, `poidsIndices` réinitialisé. **`_save()` est appelé
  immédiatement** → la perte est **persistante et irréversible** (aucune corbeille, aucun backup automatique).
- Effet induit : `nbMisesAJour` retombe à 0 → `best_bet_screen:314-318` **bloque entièrement** la liste
  (`if (nbMaj < 5) return []`) et la branche « Progression : n / 15 analyses » s'affiche.
  **L'écran Best Bet devient vide pendant au moins 5 cycles d'apprentissage.**
- Non corrigé par `clamp()` : `resetPoids()` n'appelle que `_save()`.

**Gravité : ÉLEVÉE.** C'est la seule action destructive de l'onglet 1 sans barrière.

---

## 9. CLARIFICATION N° 6 — L'ANCIEN MOTEUR BEST BET N'EST PAS PRÉSUMÉ SUPÉRIEUR

Évaluation sur ses propres termes, sans aucune présomption de supériorité.

### 9.1 Ce qu'il fait réellement (`best_bet_engine.dart:111-286`)

| Élément | Valeur mesurée | Évaluation critique |
|---|---|---|
| Source de pronostic | `PredictionEngine.generateRecommendation` | **Moteur distinct** de l'IA 19 critères : `prediction_engine.dart` note via `_computeScoreDetail` + bonus d'écart dominant. **Ce n'est pas le score IA à 19 critères.** |
| `probaEst` | `reco.niveauConfiance / 100.0` (l.150) | `niveauConfiance` = `niveauFiabilite.confiance.toInt()` (`prediction_engine.dart:435`) ; **déjà un pourcentage 0-100 borné**, donc `probaEst` ∈ [0,1] — **cohérent formellement**, mais ce n'est **pas** une probabilité calibrée (aucune fréquence observée) |
| `valeurAttendue` | `probaEst * gainSG.gainMax - (1-probaEst) * mise` (l.151) | Formule d'espérance **correcte** ; mais `gainMax` = `gainNet` = `mise*cote - mise` (`gain_calculator.dart:435`). La formule est donc `p*(m*c-m) - (1-p)*m`, **correcte** |
| `probabiliteEstimee` de `GainCalculator` | `(1/cote * 100).clamp(1,95)` (`gain_calculator.dart:300-302`) | **Probabilité « de marché »**, pas une probabilité IA. Elle **n'entre pas** dans `valeurAttendue` (qui utilise `probaEst`). Deux probabilités coexistent dans le même objet sans être réconciliées |
| `scoreVA` | `(valeurAttendue/mise*10 + 50).clamp(0,100)` (l.154) | Transformation affine arbitraire ; **non normalisée** avant la normalisation de groupe qui suit |
| Normalisation | **relative au groupe du jour** (`/max`), l.203-214 | **Point fort réel** : rend les scores comparables entre courses d'une même journée. `best_bet_screen` ne le fait pas |
| Bonus / pénalités | ×1.15 / ×1.07 ; ×0.80 / ×0.92 / ×0.88 ; `< seuil` → 0.0 | **Point fort réel** : traitement du risque absent de `best_bet_screen` |
| Types évalués | `simpleGagnant`, `place`, `gagnantEtPlace`, `tierce`, `quarte`, `quinte` (l.147-155) + `couple` (l.405) = **7** | **Meilleure couverture** que `best_bet_screen` (0 calcul de gain) |
| Multiplicateurs | Délégués à `GainCalculator` | ⚠️ `GainCalculator` calcule des gains **théoriques** par formule de cote, non des rapports PMU réels |

### 9.2 Faiblesses mesurées du moteur ancien

1. **`FusionConfigScreen` inaccessible** (§2) → l'utilisateur ne peut **jamais** changer de preset en pratique :
   le moteur tournerait toujours en `conseillee` (0.65 / 0.25 / 0.10, seuil 42).
2. **`assert(poidsConfiance + poidsGain + poidsRisque <= 1.01)`** (l.60) : en release les `assert` sont
   supprimés → une config invalide chargée depuis prefs ne serait pas rejetée. `FusionConfigService.fromPrefs`
   fait toutefois un contrôle `total < 0.99 || total > 1.01` (l.24) — **protection partielle**.
3. **`probaEst` non calibrée** : `valeurAttendue` repose sur une confiance auto-déclarée, sans aucune
   fréquence observée. Un `niveauConfiance` systématiquement optimiste gonfle `scoreVA` de façon uniforme.
4. **`scoreVA` dépend de `mise`** (10 € codée en dur, l.132) : changer la mise change le classement, ce qui
   n'a pas de sens métier.
5. **Aucun accès au 19-critères** : il ignore `scoresCriteres`, le gradient, les seuils adaptatifs, l'ELO
   par discipline. Il n'utilise **aucune** des données que le BLOC 1 protège.

### 9.3 Verdict

**Ni supérieur, ni inférieur : non comparable.** Les deux moteurs ne répondent pas à la même question :
`best_bet_engine` classe des **opportunités de gain** (espérance + risque) sur un scoring ancien,
`best_bet_screen` classe des **confiances IA** sur le scoring 19 critères avec des seuils appris.
**Toute réactivation supposerait d'abord** : (a) rendre `FusionConfigScreen` atteignable, (b) remplacer
`reco.niveauConfiance` par la fréquence de réussite observée par type (`_precisionParType` existe déjà),
(c) faire porter la mise par la config et non par une constante, (d) décider quel scoring fait autorité.
**Aucune réactivation n'est proposée dans ce rapport.**

---

## 10. CLARIFICATION N° 7 — ANOMALIES MÉTIER vs DIFFÉRENCES JUSTIFIÉES

| Élément | Anomalie métier ? | Justification |
|---|---|---|
| Deux familles de cascades (A adaptative / B figée) | **OUI — anomalie** | Deux réponses différentes à la même course, sans avertissement. La famille B prétend suivre l'IA (« copie de conseils_screen ») mais ignore les seuils appris |
| `data_refresh:1062` sans branche `isQuarte` | **OUI — anomalie** | Divergence accidentelle à l'intérieur de la famille A ; commentaire `★ fix` présent dans `ia_memory_service:6229` mais **absent** ici |
| `widget_service:104` sans `Couplé Placé` ni `Tiercé` | **OUI — anomalie** | Le commentaire dit « Aligné sur la philosophie BestBetEngine » mais la cascade est tronquée |
| `seuilGagnantPlace` 50 vs 80 documenté | **OUI — anomalie documentaire** | 30 pts d'écart, commentaire faux |
| `seuilQuarte`/`seuilQuinte` appris mais jamais lus | **OUI — anomalie** | 2 seuils sur 8 sans effet décisionnel |
| `resetPoids()` sans confirmation | **OUI — anomalie prioritaire** | §8 |
| `_load()`/`resetPoids()` sans `clamp()` | **OUI — anomalie** | Somme ≠ 1.00 hors apprentissage |
| Deux `defauts` divergents (0.25/1.26 vs 0.32/1.37) | **OUI — anomalie** | Même notion, deux valeurs |
| `1.37` sur JSON incomplet | **NON — repli latent** | Non atteignable par un backup normal (§3.2). **Différence de robustesse, pas anomalie active** |
| `conseils_screen` et `alert_service` figés | **OUI** (familles) mais **NON** pour l'écran Conseils seul | Si l'objectif est « un conseil stable et non appris », c'est un choix. **Aucune documentation de ce choix n'existe** → non justifié |
| `IaTabStats` et `IaTabMethodologie` sans aucune action | **NON — différence justifiée** | Objectif = affichage/lecture. 0 `onTap`/`onPressed` et 0 écriture prefs : c'est cohérent |
| `IaTabConseils` statique | **NON — différence justifiée** | Contenu pédagogique |
| Backtesting sans persistance | **NON — différence justifiée** | Outil de simulation ; le résultat est éphémère par conception, et `BacktestingService` n'écrit **rien** (0 `SharedPreferences`, 0 `_save`) |
| Martingale « Gagnant seul » et cote 2.5 | **OUI — anomalie de cohérence** | Écart avec `BacktestingService` (cote 4.5) et absence de choix de type |
| 5ᵉ backtest non couvert par les tests | **OUI — anomalie de couverture** | §12 |

---

## 11. POINT 1 — INVENTAIRE EXHAUSTIF DES 6 ONGLETS DE LA MÉMOIRE IA

Écran `IaPerformanceScreen` (`lib/screens/ia_performance_screen.dart`, 4 978 lignes). `TabBar` à **6 onglets**.

### 11.1 Onglet 1 — 🧠 « Mémoire IA » (`_buildTabMemoire()`, l.1187-1553, 366 lignes)

| Élément | Ligne | Type | Effet |
|---|---|---|---|
| Carte « L'IA a ajusté ses poids N fois » | 1378-1386 | affichage | lecture `poids.nbMisesAJour` |
| **Bouton « Reset »** | **1387-1388** (`GestureDetector.onTap`) | **ACTION DESTRUCTIVE** | `mem.resetPoids()` — **AUCUNE CONFIRMATION** (§8) |
| Bloc « Pas encore de données réelles » | 1454 | affichage conditionnel | — |
| Journal d'apprentissage (5 dernières entrées) | 1485-1500 | affichage | `mem.journal.take(5)` |
| **Bouton « Effacer toute la mémoire IA »** | 1522-1535 | **ACTION DESTRUCTIVE** | `showDialog` l.1526 → `clearHistory()` + `resetPoids()` l.1536-1537 → **CONFIRMÉE** |
| Statistiques IA (calculerStats) | 1189 | affichage | `_statsReelles ?? mem.calculerStats()` |

Outils **hors** du corps de l'onglet mais présents sur la même page :
| Élément | Ligne | Effet |
|---|---|---|
| Encadré « Dernière analyse » | `_buildEncadreDerniereAnalyse()` l.1715 | affichage |
| **Bouton « Recréer les pronostics manquants »** | `_buildBoutonRecreer()` l.1716 → `_recreerPronostics()` l.434 | **écrit** `_pronostics` (jusqu'à saturation du plafond 600) |
| **Bouton « Analyser la journée »** | l.1724 (`GestureDetector`) → `_lancerAnalyseJournee()` l.633 | **écrit** pronostics + déclenche l'apprentissage |
| **Bouton « Relancer récupération PMU »** | l.1817 | câble `sourceProgrammeHistorique` puis relance réseau |
| **Bouton « Purger les pronostics sans résultat »** | l.2065 | **ACTION DESTRUCTIVE CONFIRMÉE** (`showDialog` l.2036-2066) → `purgerCoursesSansResultat()` l.1812 |
| Auto-recréation du jour | `_autoRecreerSiVide()` l.157 | **écrit** une fois par jour (`auto_recreer_YYYYMMDD`) |
| Filtre période Précision IA | `_chargerFiltreIaStats()` l.179 | écrit 3 prefs (`_kFiltreActif`, `_kFiltreDebut`, `_kFiltreFin`) |

**Total actions de l'onglet 1 : 2 destructives internes (dont 1 non confirmée) + 4 outils de page
(dont 2 écrivantes) + 1 auto-action + 1 filtre persistant.**

### 11.2 Onglet 2 — 🔬 « Backtesting » (`IaTabBacktesting`, 2 574 lignes) — 19 actions

| # | Élément | Ligne | Effet |
|---|---|---|---|
| 1 | Lancer le backtest | 1157 → `_lancerBacktest()` 107 | lecture seule |
| 2 | **Comparer les 7 types** | 1193 → `_lancerComparaison()` 166 | 7 × `lancer()` en parallèle |
| 3 | **Martingale** | 1217 → `_lancerMartingale()` 351 | **5ᵉ backtest autonome** (§12) |
| 4 | Export complet (image PNG) | 541 → `_exporterBacktestingComplet()` 588 | `SharePlus` |
| 5 | Export texte d'un résultat | 1658 → `_exporterResultats()` 662 | `SharePlus` |
| 6 | Choix mise | 959 | écrit `bt_mise` |
| 7 | Choix nb jours | 837 | écrit `bt_jours` |
| 8 | Choix type de pari | 864 | écrit `bt_type` |
| 9 | Choix confiance min | 959 → `_btConfianceMin` | écrit `bt_confiance_min` |
| 10-13 | Discipline (4 boutons) | 1025, 1041 | écrit/`remove` `bt_discipline` |
| 14-17 | Hippodrome (4 boutons) | 1073, 1089 | écrit/`remove` `bt_hippodrome` |
| 18 | **« Injecter les filtres dans Conseils »** | 1357-1371 | **écrit 5 clés** `conseils_filtres_*` + `conseils_inject_pending` |
| 19 | Afficher tout / replier | 2430 | UI seule |
| — | Bulles de comparaison cliquables | 272 | relance un backtest |
| — | Traceabilité premium | 1466 | lecture `premiumsPourDate` |

### 11.3 Onglet 3 — 📅 « Calendrier » (`IaCalendrierTab`, 4 001 lignes) — 19 actions

| # | Élément | Ligne | Effet |
|---|---|---|---|
| 1 | Aujourd'hui | 356 | navigation |
| 2 | **Reset étoile** | 393 → `_ouvrirResetEtoile()` 419 | §7 |
| 3-4 | Choix « une date » / « toutes » | 475 / 487 | pop |
| 5-6 | Confirmation date | 544 / 548 | `resetPremiumPourDate()` |
| 7-8 | Confirmation « tout » | 597 / 601 | `resetToutesEtoilesPremium()` |
| 9 | Carte jour cliquable | 944 | `_ouvrirDetailJour` 2461 |
| 10 | Édition seuils (palier) | 818 → `_ouvrirSeuilPourPalier()` 847 | `_DialogSeuil._valider()` 3443 → `setString('ia_calendrier_seuils_v1')` |
| 11 | Valider seuils | 3585 | idem |
| 12 | Filtre stats par type | 1594 | **local**, non persisté |
| 13 | Choix période stats | 1634 → 1671 | **local**, non persisté |
| 14 | Fiche gros pari gagnant | 1819 → 1919 | lecture `PronosticResultatsRepository` |
| 15 | Fiche quasi-gagnant | 2121 → 2228 | lecture |
| 16 | Descriptif type de pari | 3185 → 3316 | lecture |
| 17 | Voir tout / replier | 3716 | UI |
| 18 | Carte générique | 630 | navigation |
| 19 | `_reculer`/`_avancer` (276/281) | — | navigation |

**1 seule clé prefs écrite dans 4 001 lignes : `ia_calendrier_seuils_v1`.**
Seuils **purement visuels** (`_getPalierDynamique` l.249) : **ne touchent ni les seuils IA ni les poids.**
Gardes de chargement présentes : `v > j && j > o && o > 0` (l.222).

### 11.4 Onglet 4 — 📊 « Statistiques » (`IaTabStats`, 474 lignes)

`class IaTabStats extends StatelessWidget` l.14. **0 `onTap`, 0 `onPressed`** (grep). 0 écriture prefs.
Source unique : `precisionParHippodromeAvecFiabilite` l.268. **Onglet 100 % lecture.**

### 11.5 Onglet 5 — ⚙️ « Algorithme » (`IaTabMethodologie`, 641 lignes)

`StatefulWidget` l.13. `addListener(_onPoidsChange)` l.30 / `removeListener` l.35 / `_onPoidsChange()` l.39.
Lit `poids` l.45 et `journal` l.239. **0 `onTap`, 0 `onPressed`, 0 écriture prefs.** Onglet 100 % lecture.

### 11.6 Onglet 6 — 💡 « Conseils » (`IaTabConseils`, 154 lignes)

`StatelessWidget` l.10. 100 % statique.

### 11.7 Tableau de synthèse

| Onglet | Fichier | Lignes | Actions UI | Écritures prefs | Actions destructives |
|---|---|---|---|---|---|
| 1 Mémoire IA | `ia_performance_screen.dart` | 366 (corps) | 2 + 4 outils page | via services | **2** (1 non confirmée) |
| 2 Backtesting | `ia_tab_backtesting.dart` | 2 574 | 19 | **11 clés** (6 `bt_*` + 5 `conseils_*`) | 0 |
| 3 Calendrier | `ia_calendrier_tab.dart` | 4 001 | 19 | **1 clé** | 2 (confirmées) |
| 4 Statistiques | `ia_tab_stats.dart` | 474 | **0** | 0 | 0 |
| 5 Algorithme | `ia_tab_methodologie.dart` | 641 | **0** | 0 | 0 |
| 6 Conseils | `ia_tab_conseils.dart` | 154 | **0** | 0 | 0 |

---

## 12. POINT 3 — CONSOMMATEURS DES RÉSULTATS DU BACKTESTING

### 12.1 `BacktestResult` — 4 producteurs distincts, 2 consommateurs UI

| Producteur | Fichier:ligne | Type |
|---|---|---|
| `BacktestingService.lancer()` | `backtesting_service.dart:168` | service (théorique) |
| `IaTabBacktesting._lancerBacktest/_lancerComparaison` | `ia_tab_backtesting.dart:107/166` | UI onglet 2 |
| **`_lancerMartingale()`** | `ia_tab_backtesting.dart:351` | **5ᵉ implémentation, autonome** |
| `ProfileProgressionTab._lancerBacktest()` | `profile_progression_tab.dart:650` | **2ᵉ écran consommateur** |

| Consommateur | Fichier:ligne | Ce qu'il fait |
|---|---|---|
| `_showComparaisonDialog` | `ia_tab_backtesting.dart:201` | tableau comparatif 7 types |
| `_exporterResultats(r)` | 662 | export **texte** via `SharePlus` |
| `_exporterBacktestingComplet()` | 588 | export **image PNG** du `RepaintBoundary` |
| `_buildTraceabiliteBacktesting(r)` | 1466 | croise avec `premiumsPourDate` (traceabilité) |
| `_buildBtResultats(r)` | 1607 | affichage |
| `_buildResultatBacktest(r)` | `profile_progression_tab.dart:667` | affichage (ROI, gain net, séries) |

### 12.2 Persistance des résultats

- `_btResult` (`ia_tab_backtesting.dart:30`) et `_martingaleResult` (l.47) sont des **champs d'état volatils**.
  **Aucune clé prefs ne les sérialise.** → **tout résultat de backtesting est perdu à la fermeture de l'app.**
  Seuls les **paramètres** survivent (`bt_*`).
- `BacktestingService` : **0 `SharedPreferences`, 0 `_save()`, 0 `IaArchiveService`**, 2 imports seulement
  (`flutter/foundation.dart`, `ia_memory_service.dart`). **Lecture pure confirmée.**
- `_keyCapital` (`profile_progression_tab.dart:62/68`) est le **seul** état persistant lié au backtesting
  (capital de départ), et il n'est pas un résultat.

### 12.3 Le pont backtesting → Conseils (seul effet réellement persistant)

`ia_tab_backtesting.dart:1363-1371` écrit `conseils_filtres_types_paris`, `conseils_filtres_hippodromes`,
`conseils_filtres_disciplines`, `conseils_filtres_confiance_min`, `conseils_inject_pending`.
Lus par : `conseils_screen.dart:104` (`_rechargerSiInjectPending`, consommé puis remis à `false` l.107) **et**
`alert_service.dart:1834-1838` + `1907-1911` (filtrage des notifications).
→ **Un backtest peut donc modifier silencieusement le filtrage des notifications et l'écran Conseils.**
Aucune confirmation de périmètre ; le dialogue l.1384 annonce seulement « Filtres appliqués ».
**Anomalie de couplage (BL1-A13).**

### 12.4 Périmètre de données du backtesting

`lancer()` lit `IaMemoryService.instance.pronostics` (**mémoire seule**, jamais l'archive) filtré sur
`resultatsReels && arriveeReelle != null && datePronostic.isAfter(now - nbJours)`.
**Conséquence structurelle** : le backtesting ne voit **que les 600 derniers pronostics**. Au-delà, les
données existent dans l'archive mais ne sont **pas** backtestables. `plageDisponible` (l.470) et
`nbCoursesDisponibles` (l.466) partagent cette limite.
`roi_value_service.dart:44/388`, `ia_calendrier_tab.dart:1439`, `profile_profil_tab.dart:343`,
`ia_perf_secondary_widgets.dart:157`, `ia_tab_backtesting.dart:356` : **tous lisent `pronosticsAvecResultat`
= mémoire seule.** **Un seul outil lit l'archive : le Calendrier (§13).**

---

## 13. POINT 4 — UTILISATION DES ARCHIVES PERMANENTES

### 13.1 API d'écriture / lecture de `IaArchiveService`

| Méthode | Sens | Appelants |
|---|---|---|
| `enregistrerEviction(p, motif)` l.719 | **écriture** | `ia_memory_service.dart:2581` (`_evincerAuDelaDeLaLimite`), `2594` (`_securiserExcedentAvantEcriture`) |
| `persisterEnAttente()` l.738 | **écriture durable** | `ia_memory_service.dart:2705` (dans `_save()`) |
| `versionRetenue(courseKey)` | **lecture** | `ia_memory_service.dart:800, 819, 3509, 6728` |
| `versionsDuMoisParDate(mois)` | **lecture** | `ia_memory_service.dart:811` (seul appelant) |
| `exporterPourBackup()` | **lecture** | `backup_service.dart:847` |
| `restaurerDepuisBackup(brut)` | **écriture** | `backup_service.dart:1657` |
| `exporterPourBackup` du repository | lecture | `backup_service.dart:827` |

### 13.2 Qui lit réellement l'archive pour du métier ?

**Un seul consommateur métier : `_pronosticsDuMoisFusionnes(annee, mois)` (`ia_memory_service.dart:784`)**,
appelé **uniquement** par `donneesCalendrierJour(annee, mois)` (l.850).
Donc **seul le Calendrier** voit les pronostics évincés.

| Outil | Lit l'archive ? | Preuve |
|---|---|---|
| Calendrier (`donneesCalendrierJour`) | ✅ **oui** | l.850 → l.784 |
| `calculerStreakPremium` / `_premiumSourceGagnantLeJour` | ✅ **oui** | l.6728 (`versionRetenue`) |
| Séries premium Home | ✅ (via streak) | `home_screen.dart:446-450` |
| Apprentissage (gradient, TOP3, calibration, labels) | ❌ **non** | l.3759, 4234, 4467, 5769-5995 = `pronosticsAvecResultat` (mémoire) |
| Backtesting (service + martingale + profil) | ❌ **non** | §12.4 |
| IA Stats (`IaTabStats`) | ❌ non | `precisionParHippodromeAvecFiabilite` (l.977, `_pronostics`) |
| ROI/Value | ❌ non | `roi_value_service.dart:44` |
| Stats Calendrier par type (`_buildStatsByType`) | ❌ **non** | `ia_calendrier_tab.dart:1439` = `pronosticsAvecResultat` — **alors que le calendrier mensuel, lui, lit l'archive** → **incohérence interne à l'onglet 3** |
| Profil | ❌ non | `profile_profil_tab.dart:343` |
| `recreerPronosticsManquants` | ❌ non | l.6188-6267 |
| `_consignerResultatEnArchive` (l.3506) | ✅ **écrit** dans l'archive (résultats L0 sur fiches archivées) | l.3506, 3509 |

### 13.3 Anomalie d'asymétrie (BL1-A09)

**L'archive est écrite par 3 chemins mais lue par 2 (Calendrier mensuel + séries premium), et jamais par
un seul outil d'apprentissage ou de mesure.** Conséquence directe : **plus la mémoire dépasse 600 entrées,
plus les statistiques, le backtesting et le ROI sous-estiment l'historique**, alors que les données existent
sur le disque. Le Calendrier est le **seul** endroit de l'application où l'utilisateur peut revoir une course
évincée.

---

## 14. POINT 5 — LIMITE DE 600 PRONOSTICS ET CONSERVATION DES RÉSULTATS OFFICIELS

### 14.1 Mécanique exacte

- `_maxPronostics = 600` (l.130), `_maxPronosticsAge = 90` (l.132).
- 4 sites d'insertion, **tous en tête** : `_pronostics.insert(0, …)` l.2926, 3096, 3262, 6267 → liste
  **du plus récent au plus ancien**.
- Éviction : `_evincerAuDelaDeLaLimite()` (l.2575) prend `_pronostics.last` = **le plus ancien**, appelle
  `enregistrerEviction(...)` **avant** `removeLast()`. Appelée depuis l.2928, 3112, 3264 (3 sites) ;
  **pas** depuis l'insertion de masse l.6267.
- Filet de sécurité : `_securiserExcedentAvantEcriture()` (l.2590) archive `skip(600)` **avant** que `_save()`
  n'écrive `take(600)`. Appelée depuis `_save()` **sous le verrou** `_ecrireProtege` (l.2698-2700).
- **Ordre d'éviction** : `skip(600)` sur une liste triée du plus récent au plus ancien évince bien **les plus
  anciens**. ✅ Conforme.
- En cas d'échec d'écriture de l'archive : `archive.doitGelerBlobPronostics` (l.2714) **gèle la réécriture du
  blob** → la version disque précédente n'est jamais détruite. ✅ Protecteur.

### 14.2 Les pronostics AVEC résultat officiel sont-ils conservés ? — RÉPONSE PRÉCISE

| Mécanisme | Protège les résolus ? | Preuve |
|---|---|---|
| `_purgerVieuxPronostics()` (l.1134) | ✅ **OUI** — `if (p.resultatsReels) return false;` avant le test de date | l.1140 |
| `_evincerAuDelaDeLaLimite()` (l.2575) | ❌ **NON** — aucune distinction, prend `_pronostics.last` quel qu'il soit | l.2580-2586 |
| `_securiserExcedentAvantEcriture()` (l.2590) | ⚠️ **NON en mémoire**, mais **archivé** avant la troncature | l.2592-2598 |
| `purgerCoursesSansResultat()` (l.1812, manuel, confirmé) | ✅ **OUI** — `removeWhere((p) => !p.resultatsReels)` | l.1818 |

**Conclusion mesurée et sans ambiguïté** : la purge **temporelle** ne touche jamais un pronostic résolu
(exigence B satisfaite). En revanche, le **plafond 600 n'épargne pas les résolus** : une fiche résolue évincée
**sort de `_pronostics`** et donc de `pronosticsAvecResultat`, de `calculerStats`, du gradient, du TOP3, du
backtesting, du ROI et des stats du Calendrier. **Elle n'est pas détruite** : elle est **archivée** en shard
mensuel (`_sharder`, `_integrerEnMemoire`) et **reste lisible uniquement par le Calendrier et les séries premium.**

**Le test `v13_c1a_archive_test.dart` P-9 (l.513-548) démontre exactement ce point** : 2 000 pronostics
insérés → **600 en mémoire + 1 400 en archive = 2 000 identités distinctes conservées, sans doublon,
y compris après redémarrage**. Et **T5 (l.376-388)** démontre le corollaire :
`pronosticsAvecResultat` reste **vide** après 10 évictions archivées → **l'archive n'alimente jamais les
statistiques d'apprentissage**. Les deux tests **confirment les conclusions du présent audit** (ils ne les
infirment pas) : la conservation existe, mais **le périmètre de lecture ne s'étend pas**.

### 14.3 Incidence quantitative (non mesurée sur données réelles — limite honnête)

Le nombre de courses enregistrées par jour n'a **pas** été mesuré en exécution (aucune exécution autorisée).
Ordre de grandeur déduit du code : `_enregistrerPronosticsAuto` (l.872) enregistre **toutes** les courses du
programme dont `partants` est non vide et dont `getPronostic(courseKey)` est `null` — donc potentiellement
**5 à 9 réunions × 6 à 9 courses ≈ 30 à 80 pronostics/jour**. Avec 600 places, la mémoire couvre donc
**≈ 8 à 20 jours** d'historique, pas 90 jours. **La purge à 90 jours est donc, en pratique, inopérante :
c'est le plafond 600 qui gouverne la rétention.** C'est un constat de conception majeur, non mesuré
dynamiquement → **proposition de mesure, pas d'affirmation**.

---

## 15. POINT 6 — CONSÉQUENCES RÉELLES DES DIVERGENCES ADAPTATIF / FIGÉ

### 15.1 Effet d'un ajustement de seuil

`ajusterSeuil(type, delta)` (l.7670) borne `delta` à **±2.0** par appel et borne chaque seuil
(sg 65-92, gp 40-75, sp 50-80, cg 60-88, cp 45-78, ti 25-55, qa 65-92).
Appelé **uniquement** sous `apprendre == true` (`ia_memory_service.dart:5959`).

| Type de pari | Seuil | Famille A lit | Famille B lit | Écart possible |
|---|---|---|---|---|
| Couplé Gagnant | A: apprenti (60-88) / B: **75** | oui | non | jusqu'à **13 pts** |
| Couplé Placé | A: apprenti (45-78) / B: **60** | oui | non | jusqu'à **18 pts** |
| Simple Gagnant | A: apprenti (65-92) / B: **80** | oui | non | jusqu'à **12 pts** |
| Simple Placé | A: apprenti (50-80) / B: **65** | oui | non | jusqu'à **15 pts** |
| Tiercé | A: apprenti (25-55) / B: **35** | oui | non | jusqu'à **20 pts** |
| Gagnant+Placé | A: 50 / B: **50** (littéral) | oui | non | 0 (mais B atteint 50 en littéral, A aussi) |

**Conséquence démontrée par lecture** : après quelques cycles d'apprentissage, un score de 70 peut donner
`'Couplé Placé'` en famille A (si `seuilCouplePlace` est descendu à 58) et `'Simple Placé'` (65) en famille B
— **deux types de pari différents pour la même course, sans avertissement**. Le type A est **persisté** dans
`IaPronostic.typePariConseille` et alimente Calendrier/Stats/Backtesting/ROI, le type B alimente
**l'écran Conseils et les notifications**. → **incohérence visible par l'utilisateur entre deux écrans.**

### 15.2 Effet du `conseils_inject_pending` (couplage §12.3)

Un backtest sur `typePari = 'Quinté+'` écrit `conseils_filtres_types_paris = ['Quinté+']` → l'écran Conseils
et `AlertService` ne montrent plus que ce type. **Un outil de simulation modifie donc le filtrage de
production des notifications.** C'est l'effet transversal le plus concret du BLOC 1.

### 15.3 Ce qui n'est PAS affecté

Les scores IA eux-mêmes (`_calculerScoreBrutEtCriteres`) sont **indépendants** du type de pari : les deux
familles classent les chevaux **identiquement**. Seul le **libellé du pari conseillé** diverge. ✅ Pas de
contamination du classement par la cascade.

---

## 16. POINT 2 — CARTOGRAPHIE TRANSVERSALE DES INTERACTIONS

```
                    ┌──────────────────────┐
                    │  DataRefreshService  │◄── réseau PMU / ZoneTurf
                    └──────────┬───────────┘
       poids.toJson() ────────►│ isolate _calculerPronosticsBatch (l.60)
       seuils.toJson() l.944 ─►│   → cascade ADAPTATIVE l.115 (AVEC isQuarte)
       elo.exporterBackup() ──►│   → fallback l.1030 → cascade l.1062 (SANS isQuarte)
                               ▼
                    ┌──────────────────────┐
                    │  IaMemoryService     │  _pronostics (max 600, insert(0))
                    │  _poids / _seuils    │  _premiumHistorique (permanent)
                    └───┬───────┬───────┬──┘
        apprendre()     │       │       │  _save()
   gradient l.3780-3990 │       │       └──────────► _securiserExcedentAvantEcriture
   TOP3 l.4402          │       │                     _evincerAuDelaDeLaLimite
   labels l.5902        │       │                          │
   seuils l.5959        │       │                          ▼
                        │       │                  ┌──────────────┐
                        ▼       ▼                  │IaArchiveService│
              ┌──────────────┐  ┌────────────┐     │ shards/mois  │
              │ 19 poids     │  │ 8 seuils   │     └──────┬───────┘
              │ (_poidsKey)  │  │(_seuilsKey)│            │
              └──────┬───────┘  └─────┬──────┘            │
                     │                │                   │
    ┌────────────────┼────────────────┼───────────────────┼──────────────┐
    ▼                ▼                ▼                   ▼              ▼
premium_utils   best_bet_screen  data_refresh     donneesCalendrier  series premium
 (Home, 5x)      (Famille A)      (Famille A)      Jour (ARCHIVE)     (ARCHIVE)
    │                │                │                   │              │
    ▼                ▼                ▼                   ▼              ▼
 widgets du jour  écran 4        pronostics        calendrier mensuel  Home
    │                                                        
    └── enregistrerPronosticsPremiumDuJour ──► _premiumHistorique (PERMANENT)

Famille B (FIGÉE, 0 accès aux seuils) : conseils_screen (2 cascades) + alert_service (2 appels)
      ▲                          ▲
      └── conseils_inject_pending ┘  ◄── ia_tab_backtesting:1363-1371 (COUPLAGE)
```

### 16.1 Matrice des dépendances

| De → Vers | Mécanisme | Effet |
|---|---|---|
| `DataRefreshService` → `IaMemoryService` | `enregistrerPronosticsBatch` | création de fiches |
| `DataRefreshService` → `IaMemoryService` | `poids.toJson()`, `seuils.toJson()` (l.944-945) | **fige l'état IA** pour l'isolate |
| `DataRefreshService` → `WidgetService` | `updateFromReunions(...).ignore()` (l.694) | widget Android |
| `IaMemoryService` → `IaArchiveService` | `enregistrerEviction`, `persisterEnAttente` | archivage |
| `IaMemoryService` → `PronosticResultatsRepository` | `utilisablesStats` (l.360, 454, 520) | stats enrichies gros paris |
| `IaMemoryService` → `ArriveeOfficielleService` | `arrivee(courseKey)` (l.1328, 1450, 1947, 4914) | résultats L0 |
| `IaMemoryService` → `_poids`/`_seuils` | `clamp()` l.3992/4402, `normaliser()` l.5902 | **seuls normaliseurs** |
| `BestBetScreen` → `IaMemoryService` | `seuilsConfiance` l.307, `poids` l.314, `enregistrerPronosticsPremiumDuJour` l.257 | famille A + premium |
| `ConseilsScreen` → `IaMemoryService` | filtré par `conseils_inject_pending` l.104 | **famille B** |
| `AlertService` → `IaMemoryService` | `conseils_filtres_*` l.1834/1907 | **famille B** |
| `IaTabBacktesting` → `IaMemoryService` | `pronosticsAvecResultat` l.356, `premiumsPourDate` l.1480 | lecture |
| `IaTabBacktesting` → **prefs globales** | `conseils_filtres_*` + `conseils_inject_pending` | **COUPLAGE SORTANT** |
| `IaCalendrierTab` → `IaMemoryService` | `premiumsPourDate` l.2642, `resetPremium*` | lecture + 2 destructifs |
| `IaCalendrierTab` → `IaArchiveService` | `addListener` l.182, `charger()` l.183 | **seul abonné** |
| `IaMemoryService` → `IaCalibrationRegistry` | `update(_poids.calibrationScore)` l.2110 | confiance globale |
| `zt_models.confianceIA` → `IaCalibrationRegistry` | `value` l.965 | module la confiance de **toutes** les courses |

### 16.2 Interactions non évidentes mesurées

1. **`IndexedStack` monte les 11 écrans** → `IaTabBacktesting`, `IaTabMethodologie` (2 listeners sur
   `IaMemoryService`), `IaCalendrierTab` (2 listeners) et `BestBetScreen` sont **tous vivants dès le
   démarrage** et réagissent à chaque `notifyListeners()`.
2. **`IaCalibrationRegistry` est un statique** : `confianceIA` de **toute** course dépend de
   `_poids.calibrationScore` (l.965), y compris pour des courses jamais analysées.
3. **`resetPoids()` ne resynchronise pas `IaCalibrationRegistry`** — contrairement à `executerResetComplet()`
   qui appelle `IaCalibrationRegistry.update(...)` (l.2110). → après un `resetPoids`, `calibrationScore` vaut
   50.0 en mémoire poids mais le registre garde l'**ancienne** valeur jusqu'au prochain
   `_mettreAJourCalibration()`. **Anomalie BL1-A05.**
4. **`seuilsJson` est figé AVANT le calcul** (l.944) mais `_save()` peut modifier `_seuils` **pendant** le
   calcul → le lot est écrit avec les seuils d'avant. **Comportement voulu et documenté** (cohérence
   atomique) → **non anomalie**.

---

## 17. POINT 7 — INVENTAIRE COMPLET DU BEST BET ACTIF ET DES PARIS RÉELLEMENT ÉVALUÉS

### 17.1 Fonctionnalités (`best_bet_screen.dart`, 2 289 lignes)

| Élément | Ligne | Détail |
|---|---|---|
| 4 onglets (grille 2×2) | `TabController(length: 4)` l.81 ; `_buildBestBetTabGrid` l.652 | Top Équilibre / Plus Sûr / Plus Rentable / **Gros paris à surveiller** |
| Tri Top Équilibre | `_sortedBy(0)` | `scoreComposite` desc |
| Tri Plus Sûr | `_sortedBy(1)` | `scoreConfiance` desc |
| Tri Plus Rentable | `_sortedBy(2)` | `scoreGain` desc |
| **Sélection figée du jour** | `_trouverOppFigee` l.126, `_sortedBy` l.… | lecture `premium_widgets_selection_jour_v1`, forcée en position 0 |
| Mise simulée | `_mise = 10.0` l.67, `_changerMise` l.1032 | modifiable 2-200 € |
| **Bankroll Kelly** | `_bankroll = 200.0` l.68, `_configurerBankroll` l.986 | `GainCalculator.miseConseilleeKelly` l.547 |
| Bonus « Séries IA récentes » | l.1990-2011 | lecture `_precisionParType` |
| Arrivée réelle PMU | `ArriveReelleWidget` l.2023 | `ArriveeOfficielleService` |
| **Gros paris à surveiller** | l.1130-1270, `_chargerSignauxPersistants` l.90 | `QuasiGrosParisService` |
| Fiche détail gros pari | `_FicheDetailGrosPari` l.1457 | — |
| Bouton Parier | `onBet` l.2080 | `BetBottomSheet` |
| Navigation vers analyse | `onTap` l.925/945/977 | `course_detail_screen` |
| Enregistrement premium | l.257 `enregistrerPronosticsPremiumDuJour` | → `_premiumHistorique` |
| Figeage 3 widgets | l.265-280 `obtenirOuCreerSelectionWidgetPremiumDuJour` | → `premium_widgets_selection_jour_v1` |

### 17.2 Types de paris réellement évalués par le Best Bet actif

| Type | Produit par la cascade ? | **Gain calculé ?** | Gain affiché ? |
|---|---|---|---|
| Quinté+ | ✅ (`isQuinte`) | ❌ **non** | ❌ |
| Quarté+ | ✅ (`isQuarte`) | ❌ **non** | ❌ |
| Couplé Gagnant | ✅ | ❌ non | ❌ |
| Couplé Placé | ✅ | ❌ non | ❌ |
| Simple Gagnant | ✅ | ❌ non (seule la cote entre dans `scoreGain`) | ❌ |
| Gagnant+Placé | ✅ (2 branches) | ❌ non | ❌ |
| Simple Placé | ✅ | ❌ non | ❌ |
| Tiercé | ✅ | ❌ non | ❌ |
| À surveiller | ✅ (défaut) | — | — |

**Mesure clé** : dans `best_bet_screen.dart`, `GainCalculator` n'apparaît **qu'une fois** (l.547, Kelly).
**Aucun `GainResult`, aucun `gainMax`, aucun multiplicateur.** Les 3 seules mentions d'euro sont :
la mise simulée (l.578), la mise Kelly (l.618), et `gainEstime = mise × cote` (l.1047/1075, l.1820, l.2159)
— **une simple multiplication de cote, sans distinction de type de pari.**

→ **Le Best Bet actif évalue 9 libellés de type de pari mais ne calcule le gain que pour un seul schéma
(`mise × cote`), appliqué indifféremment à tous.** Un « Tiercé » y est présenté avec un gain estimé
`mise × cote`, ce qui **n'a aucun sens** pour un pari combiné à 3 chevaux.
**Anomalie métier BL1-A11 (gravité élevée, trompeur pour l'utilisateur).**

---

## 18. ANOMALIES — IDENTIFIANTS UNIQUES, CLASSIFICATION, CAUSES, CONSÉQUENCES, PREUVES

Convention d'identifiant : **`BL1-Axx`** pour BLOC 1, **`BL23-Axx`** réservé aux BLOCS 2/3 (aucun créé ici, donc
aucun doublon possible). Numérotation stable pour insertion ultérieure.

### ÉLEVÉE

**BL1-A01 — `resetPoids()` exécuté sans confirmation**
- *Cause* : `GestureDetector.onTap` direct (`ia_performance_screen.dart:1387-1388`), aucun `showDialog`.
- *Conséquence* : destruction persistante des 19 poids appris + `nbMisesAJour`→0 (donc **Best Bet vide** min. 5 cycles) + `poidsParDiscipline`/`dernierGradient`/`correlations` vidés.
- *Preuve* : lecture l.1387-1400 ; comparaison avec l.1526-1537 (même page, action protégée).
- *Dépendances* : aucune. *Correction proposée* : `showDialog` identique à l.1526.
- *Clarification n°5.*

**BL1-A02 — Deux familles de cascades incompatibles (A adaptative / B figée)**
- *Cause* : duplication de logique dans `conseils_screen` (l.303, 1274) et `alert_service` (l.1945) sans accès
  à `seuilsConfiance` (`grep` → **0 occurrence**).
- *Conséquence* : jusqu'à **20 pts** d'écart (Tiercé 25-55 vs 35) ; deux types de pari différents pour la
  même course entre Best Bet/Calendrier et Conseils/Notifications.
- *Preuve* : §5.3, §15.1 ; grep vide dans les 2 fichiers.
- *Dépendances* : BL1-A03. *Correction proposée* : faire de `premium_utils.typePariEtNumerosPourCourse` la
  source unique, ou documenter explicitement le choix figé.

**BL1-A03 — `data_refresh_service.dart:1062` omet la branche `isQuarte`**
- *Cause* : omission dans `_enregistrerPronosticsBatchFallback` (l.1030) ; un `★ fix` équivalent existe en
  `ia_memory_service.dart:6229` mais pas ici.
- *Conséquence* : si l'isolate échoue, toutes les courses Quarté+ du lot reçoivent un `typePariConseille`
  erroné, persisté puis exploité par Calendrier/Stats/Backtesting/ROI.
- *Preuve* : comparaison l.115-135 (avec `isQuarte`) vs l.1062-1080 (sans).
- *Dépendances* : BL1-A02. *Correction proposée* : aligner le fallback sur l'isolate.

**BL1-A04 — `_load()` et `resetPoids()` ne normalisent pas les poids**
- *Cause* : `IaPoidsAdaptatifs.fromJson` (l.2227-2231) et `IaPoidsAdaptatifs()` (l.6402) sans `clamp()`.
- *Conséquence* : somme ≠ 1.00 hors apprentissage → inflation absolue du score (+≈6 pts) et mention
  « FAVORI IA » déplacée dans ≈1,5-5,5 % des courses. **Aucun effet sur le classement.**
- *Preuve* : §4.2 scénario S1 ; `clamp()` appelé seulement l.3992/4402.
- *Dépendances* : BL1-A06. *Correction proposée* : appeler `_poids.clamp()` après chargement (protégé par
  le fait que `clamp()` ne fait que normaliser/border).

**BL1-A11 — Le Best Bet affiche `mise × cote` comme « gain estimé » pour TOUS les types**
- *Cause* : `_BetOpp` ne porte aucun `GainResult` ; `gainEstime = mise * cote` (l.1820, l.2159, l.1047).
- *Conséquence* : un Tiercé/Quarté+/Quinté+ est présenté avec le gain d'un Simple Gagnant → **estimation
  trompeuse** ; l'utilisateur peut surestimer ou sous-estimer massivement.
- *Preuve* : `grep GainCalculator` → 1 occurrence (Kelly, l.547) ; §17.2.
- *Dépendances* : BL1-A12. *Correction proposée* : soit calculer via `GainCalculator` par type, soit
  **supprimer** toute mention de gain pour les paris combinés.

**BL1-A12 — 5ᵉ backtest non couvert, incohérent avec le service**
- *Cause* : `_lancerMartingale()` (`ia_tab_backtesting.dart:351`) réimplémente une simulation complète.
- *Conséquence* : critère de gain **`rangFavoriIaDansArrivee == 1`** (Gagnant seul) alors que `_btType` est
  ignoré ; cote de repli **2.5** (l.394) vs **4.5** dans `BacktestingService:372-374` ; aucun test ne le
  couvre (`grep martingale test/` → 0).
- *Preuve* : lecture l.351-420 ; §12.1.
- *Dépendances* : néant. *Correction proposée* : unifier la cote de repli et respecter `_btType`, ou
  documenter explicitement « simulation Gagnant seul ».

### MOYENNE

**BL1-A05 — `resetPoids()` ne resynchronise pas `IaCalibrationRegistry`**
- *Cause* : `executerResetComplet()` appelle `IaCalibrationRegistry.update(...)` (l.2110) ; `resetPoids()`
  (l.6402-6407) ne le fait pas.
- *Conséquence* : `confianceIA` (`zt_models.dart:965`) reste pondérée par l'ancienne calibration alors que
  `_poids.calibrationScore` vaut 50.0 → **incohérence de confiance affichée** jusqu'au prochain
  `_mettreAJourCalibration()`.
- *Preuve* : comparaison des 2 méthodes. *Dépendances* : BL1-A01.

**BL1-A06 — Deux valeurs de « poids par défaut » (0.25/1.26 vs 0.32/1.37)**
- *Cause* : constructeur (l.570) ≠ `fromJson` fallbacks (l.822-824) ≠ `static const defauts` (l.858).
- *Conséquence après `normaliser()`* : forme **+10.83 %**, cote/constance/victoires/discipline **−13.41 %**,
  rapport forme/record 2.5000 vs 2.6667. **La pondération relative change réellement** → 7,45 % de rang 1
  différents (§4.2 S2). `defauts` (1.37) sert de repli de calcul en `ia_memory_service.dart:4180` et
  `simulation_service.dart:200`.
- *Preuve* : §3.1-3.3, §4.2-4.3. *Dépendances* : BL1-A04.

**BL1-A07 — Perte irréversible et non réparable des étoiles premium**
- *Cause* : les 2 resets (`ia_memory_service.dart:6854`, `6907`) suppriment des jours passés ;
  `enregistrerPronosticsPremiumDuJour` (l.6409) ne réécrit que le jour présent.
- *Conséquence* : séries Home (`home_screen:446-450`) cassées, palier OR et badges dorés perdus,
  traçabilité backtesting (`ia_tab_backtesting:1480`) vidée. **Aucun effet sur l'apprentissage** (prouvé).
- *Preuve* : §7.2-7.4 ; **les deux resets sont confirmés par `AlertDialog`** (l.544/548, 597/601).
- *Dépendances* : néant. *Correction proposée* : aucune — comportement annoncé ; documenter seulement la
  perte de traçabilité backtesting.

**BL1-A08 — `seuilGagnantPlace` = 50.0 alors que la documentation annonce 80**
- *Cause* : valeur du constructeur (l.7655) non alignée avec le commentaire (l.7648).
- *Conséquence* : la branche `'Gagnant+Placé'` par seuil capte la plage **50-64** ; la plage 50-64 n'est donc
  ni « À surveiller » ni « Tiercé ».
- *Preuve* : §6 ; `ajusterSeuil` borne 40-75 → la valeur 50 est **dans** les bornes.
- *Dépendances* : BL1-A02. *Correction proposée* : corriger le commentaire, ou remonter le seuil — **décision
  métier à prendre hors audit**.

**BL1-A09 — L'archive permanente n'alimente aucun outil d'apprentissage ni de mesure**
- *Cause* : `pronosticsAvecResultat` (l.975) = `_pronostics.where(...)` uniquement.
- *Conséquence* : au-delà de 600 fiches (≈8-20 jours), backtesting, IA Stats, ROI/Value, stats Calendrier par
  type, Profil **sous-estiment l'historique** alors que les données sont sur disque. Seuls le Calendrier
  mensuel (`_pronosticsDuMoisFusionnes` l.784) et les séries premium voient l'archive.
- *Preuve* : §12.4, §13.2 ; test `v13_c1a` **T5** (l.376-388) le démontre explicitement.
- *Dépendances* : BL1-A10. *Correction proposée* : hors périmètre de correction — nécessite une décision
  d'architecture (l'archive est-elle une source de mesure ?).

**BL1-A10 — Incohérence interne à l'onglet Calendrier (mois vs stats par type)**
- *Cause* : `donneesCalendrierJour` lit l'archive (l.850) mais `_buildStatsByType` lit `pronosticsAvecResultat`
  (`ia_calendrier_tab.dart:1439`).
- *Conséquence* : le calendrier affiche des jours que les statistiques de la **même page** ignorent.
- *Preuve* : les 2 lectures. *Dépendances* : BL1-A09.

**BL1-A13 — Le backtesting écrit des filtres de production (`conseils_*` + `conseils_inject_pending`)**
- *Cause* : `ia_tab_backtesting.dart:1363-1371`.
- *Conséquence* : un outil de simulation modifie le filtrage de l'écran Conseils (`conseils_screen:104`) **et
  des notifications** (`alert_service:1834`, `1907`).
- *Preuve* : écritures l.1363-1371 ; 2 lecteurs cités. *Dépendances* : néant. *Correction proposée* : préfixer
  ces clés d'un namespace `simulation_` ou demander une confirmation explicite.

**BL1-A14 — `widget_service.dart:104` : cascade tronquée**
- *Cause* : pas de branche `Couplé Placé`, pas de `seuilGagnantPlace`, pas de `seuilTierce`.
- *Conséquence* : un score 40-49 donne `'À surveiller'` sur le widget Android là où Best Bet donnerait
  `'Tiercé'` (seuil 35).
- *Preuve* : lecture l.104-122 vs `best_bet_screen:354-392`. *Dépendances* : BL1-A02.

**BL1-A15 — 2 seuils sur 8 (`seuilQuarte`, `seuilQuinte`) appris et persistés sans effet décisionnel**
- *Cause* : seules lectures = affichage (`ia_performance_screen:3123-3124`, `ia_precision_widget:756-757`).
- *Conséquence* : `ajusterSeuil` les modifie (l.7693 / non modifiable pour Quinté) et les persiste sans
  influencer aucune décision.
- *Preuve* : §5.6. *Dépendances* : néant.

**BL1-A16 — `FusionConfigScreen` et `FusionConfigService` inaccessibles**
- *Cause* : 0 import, 0 appelant (mesuré).
- *Conséquence* : les 3 presets de fusion ne sont **jamais** applicables ; 4 clés de config sont pourtant
  sauvegardées/restaurées par `backup_service.dart:29`.
- *Preuve* : `grep -rn "FusionConfigScreen" lib/` → **vide** hors fichier ; §2.
- *Dépendances* : BL1-A17. *Correction proposée* : aucune réactivation recommandée (§9.3).

### FAIBLE

**BL1-A17 — `BestBetEngine.computeAll()` sans appelant (fichier non mort)**
- *Preuve* : 0 appelant ; `TypePariCalc` 51, `GainResult` 31, `StatDiscipline` 8, `StatTypePari` 4 occurrences
  externes. *Correction proposée* : aucune (documentation seule).

**BL1-A18 — Code mort confirmé à preuve élevée**
- `ia_analyse_journee_widget.dart` (`buildResumeAnalyse`, 0 appelant, `ignore_for_file: unused_element`) ;
  `ia_precision_widget.dart` (`SectionPrecisionIA` l.245, déjà documenté CODE MORT dans
  `test/z3_reproduction_n5_n6_filtres_test.dart:30`) ; `ia_tab_algo_conseils.dart`
  (`_buildTabMethodologieLegacy` 10 critères A→J, `buildTabConseils`, remplacés par `IaTabMethodologie`
  19 critères — **remplacement démontré**) ; `_DialogDetailTypePari` privé (`ia_dialog_detail_type_pari.dart:84`,
  2 occurrences externes = 2 **commentaires**).
- *Limite* : preuve par absence d'appelant statique ; aucune référence dynamique trouvée, mais absence ≠ preuve formelle.

**BL1-A19 — Commentaires faux dans le code de production**
- « somme = 1.00 ✅ » et « Total brut ≈ 1.07 » (constructeur, valeurs réelles 1.26) ;
- « identiques aux seuils codés dans best_bet_screen » (faux pour `seuilGagnantPlace`) ;
- « défaut 80 (+ cote > 8) ou 50 » (valeur réelle 50.0) ;
- « Aligné sur la philosophie BestBetEngine » (`widget_service:…`) alors que la cascade est tronquée ;
- « Identique à la logique de best_bet_screen » (`premium_utils.dart:24`) : **vrai**, mais `best_bet_screen`
  n'est pas la seule cascade (famille B non alignée).

**BL1-A20 — Résultats de backtesting non persistés**
- *Preuve* : `_btResult` / `_martingaleResult` = champs d'état ; 0 clé prefs les sérialise.
- *Conséquence* : perte totale à la fermeture, y compris les paramètres d'un export. **Différence justifiée
  pour un outil de simulation** — signalée pour transparence, sans proposition de correction.

---

## 19. ACQUIS CONFORMES (à ne pas réauditer)

| # | Acquis | Preuve |
|---|---|---|
| 1 | Navigation impérative complète, 11 écrans montés, `AuditScreen` accessible en index 9 | §1 |
| 2 | Purge temporelle 90 j ne touche jamais un pronostic résolu | `if (p.resultatsReels) return false;` l.1140 |
| 3 | Aucun recalcul rétroactif | 23/23 champs préservés (l.3434, 3577, 4997) ; `scMap`/`scRaw` = variables locales de `fromJson` (l.394-396), pas des champs |
| 4 | Formule de gradient conforme | `(moyBon - moyMauvais)/100.0` l.3896 |
| 5 | Backtesting = lecture pure | 0 `SharedPreferences`, 0 `_save()`, 0 `IaArchiveService`, 2 imports |
| 6 | Éviction 600 = plus ancien, archivé avant retrait | `_pronostics.insert(0,…)` ×4 ; `enregistrerEviction` avant `removeLast()` |
| 7 | Gel du blob si archive non durable | `doitGelerBlobPronostics` l.2714 |
| 8 | Conservation permanente des étoiles premium (E5) | purge 90 j supprimée (l.6519-6521) ; tests C-1→C-6 (90/180/365/730 j) |
| 9 | 2 000 identités survivent au plafond 600 | test `v13_c1a` **P-9** (l.513-548) |
| 10 | Les resets premium sont tous deux confirmés par dialogue | l.544/548 et l.597/601 |
| 11 | Les seuils du Calendrier sont purement visuels | `_getPalierDynamique` l.249 ; 1 seule clé prefs |
| 12 | Les onglets 4, 5, 6 sont 100 % lecture | 0 `onTap`/`onPressed`, 0 écriture prefs |
| 13 | Garde anti-corruption des seuils Calendrier | `v > j && j > o && o > 0` l.222 |
| 14 | `_ecrireProtege` n'écrit que l'action fournie | l.6874-6886 ; aucun `_save()` indirect |

---

## 20. ERREURS COMMISES ET CORRIGÉES (conservées comme traçabilité)

1. `IaTabCorrelations`/`IaTabDiscipline`/`IaTabAudit`/`IaTabCriteresMorts` déclarés morts sur simple grep de
   nom de fichier → **FAUX**, tous instanciés (`audit_screen.dart:152-155`, 165-170).
2. `AuditScreen` « accessibilité à vérifier » → **prouvé accessible en index 9**.
3. `best_bet_engine.dart` qualifié de code mort → **FAUX** (§2).
4. Sites financiers de `alert_service` l.651/2783/… puis l.1032/3972/… → **les deux exacts**, référentiels
   différents (commentaires retirés vs brut).
5. « 1.26 cohérent » → **trois jeux** : 1.26 / 1.37 / 1.37 (§3).
6. Chemin `lib/screens/particulars/ia_performance_screen.dart` → **FAUX**, le fichier est
   `lib/screens/ia_performance_screen.dart`.
7. « 4 cascades » puis « 5 cascades » → **9 implémentations, 13 sites d'appel, 7 consommateurs finaux** (§5).
8. « `computeAll()` remplacé par `best_bet_screen` » → **NON DÉMONTRÉ** (§2).
9. **« Un backup antérieur au premier apprentissage restaure 1.37 »** → **RETIRÉ** : `toJson()` écrit toujours
   forme/gains/record ; le 1.37 n'est atteignable que sur JSON incomplet (§3.2).
10. **« Monte-Carlo : 12,23 % de changements de label, +6,10 pts, max +60,41 »** → **RETIRÉ** : non
    reproductible avec la normalisation réellement codée (max mesuré +12,38). Remplacé par S1/S2/S3 (§4.2).
    L'attribution initiale (somme des poids) était **fausse** : c'est la **distribution** qui change l'ordre.

---

## 21. PROPOSITIONS DE CORRECTION — HIÉRARCHISÉES (aucune appliquée)

| Priorité | Anomalie | Correction proposée | Risque IA |
|---|---|---|---|
| **P0** | BL1-A01 | Ajouter un `showDialog` de confirmation avant `resetPoids()` (copier l.1526) | **nul** (UI pure) |
| **P0** | BL1-A05 | Appeler `IaCalibrationRegistry.update(50.0)` dans `resetPoids()` | **nul** (cohérence d'affichage) |
| **P1** | BL1-A03 | Ajouter la branche `isQuarte` en `data_refresh:1062` | **faible** (alignement sur l'existant) |
| **P1** | BL1-A11 | Supprimer ou typer le gain affiché par type | **faible** (UI pure) |
| **P1** | BL1-A13 | Namespacer les clés `conseils_*` écrites par le backtesting | **faible** |
| **P2** | BL1-A02 | Unifier via `premium_utils`, ou documenter le choix figé | **MOYEN — touche une cascade** |
| **P2** | BL1-A04 | `_poids.clamp()` après `_load()` et après `resetPoids()` | **MOYEN — modifie les scores** |
| **P2** | BL1-A06 | Aligner les 3 jeux de défauts (1 valeur unique) | **MOYEN — modifie les scores** |
| **P2** | BL1-A08 | Corriger le commentaire, ou décider du seuil | **MOYEN** |
| **P2** | BL1-A14 | Aligner `widget_service` sur la famille A complète | **MOYEN** |
| **P3** | BL1-A09/A10 | Décision d'architecture sur l'archive comme source de mesure | **ÉLEVÉ — hors audit** |
| **P3** | BL1-A12 | Unifier la cote de repli (2.5 vs 4.5) | faible |
| **P3** | BL1-A15/16/17/18/19/20 | Documentation, nettoyage, traçabilité | faible |

**Aucune correction n'a été appliquée. P0 et P1 sont hors du périmètre protégé (aucune modification d'IA,
de poids, de seuil, d'algorithme, de gradient, de TOP3 ni d'apprentissage).**

---

## 22. CLÔTURE DU BLOC 1 — POINT DE REPRISE ET PROTECTIONS

### 22.1 Ce qui est CLOS

Les 7 points demandés sont traités : inventaire exhaustif des 6 onglets (§11), cartographie transversale (§16),
consommateurs du backtesting (§12), usage des archives (§13), incidence du plafond 600 et conservation des
résultats officiels (§14), conséquences des divergences A/B (§15), inventaire Best Bet et paris réellement
évalués (§17).
Les 7 clarifications sont traitées : implémentations/sites d'appel/consommateurs (§5), JSON complet vs
incomplet (§3), somme vs distribution sous la normalisation réelle (§4), effets du reset des étoiles (§7),
`resetPoids()` sans confirmation comme anomalie prioritaire **BL1-A01** (§8), évaluation sans présomption de
l'ancien moteur (§9), distinction anomalies métier / différences justifiées (§10).

### 22.2 Ce qui reste NON prouvé (transparence)

1. **Nombre réel de courses enregistrées par jour** : non mesuré en exécution. L'estimation 30-80/jour
   (§14.3) est déduite du code, **pas mesurée**. Elle conditionne la conclusion « le plafond 600 gouverne
   la rétention plus que la purge 90 j ».
2. **Fréquence réelle des déclenchements de la famille B** : preuve **statique** uniquement (absence d'accès
   aux seuils). Aucun compteur d'exécution posé.
3. **Fréquence réelle d'échec de l'isolate** déclenchant BL1-A03 : non mesurée.
4. **Toutes les simulations Monte-Carlo** supposent des critères uniformes indépendants : les résultats
   (7,45 % de rang 1, +5,98 pts) sont **bornés par cette hypothèse**, pas des valeurs observées sur les
   vraies courses.
5. **Aucune validation sur téléphone réel** : toutes les conclusions sont **statiques** (lecture + grep +
   simulation). Aucun test unitaire ou widget n'est présenté comme validation réelle.

### 22.3 Protections — vérification finale

- Aucune modification de `lib/`, `test/`, `integration_test/`, `pubspec.yaml`, `android/`.
- `git status --porcelain` → **vide**. HEAD `2e96aae`. Branche `main`. Aucun commit, aucun push.
- Aucune compilation APK. Aucun `flutter build`. Aucun `flutter test`.
- Aucun recalcul historique. Aucune modification de poids, seuil, algorithme, gradient, TOP3, calibration.
- Tous les outils d'analyse en `/home/user/audit_bloc1/` (hors dépôt). Aucun outil permanent ajouté à l'app.

### 22.4 Arrêt

**BLOC 1 EST CLOS. BLOC 2 N'EST PAS ENTRAMÉ.**
Le présent document (`RAPPORT_FINAL_BLOC1.md`) est le rapport consolidé téléchargeable.
Le rapport cumulatif antérieur reste archivé sous `RAPPORT_BLOC1_v1_backup.md` (499 lignes) pour traçabilité
des corrections n°9 et n°10.
