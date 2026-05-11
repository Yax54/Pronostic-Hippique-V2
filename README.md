# 🏇 Pronostic Hippique — Application Flutter

Application Android de pronostics PMU alimentée par IA, données Zone-Turf et API PMU officielle.

## ✨ Fonctionnalités

- 📊 **Programme du jour** : toutes les réunions PMU françaises en temps réel
- 🤖 **IA de pronostics** : moteur de prédiction adaptatif avec mémoire ELO par cheval
- 💰 **Gestion des paris** : suivi des mises, gains/pertes, historique complet
- 🏆 **Best Bet Engine** : sélection automatique du meilleur pari du jour
- 🔔 **Alertes** : notifications push pour départs, non-partants, arrivées
- 📱 **Widget Android** : widget écran d'accueil pour le prochain départ
- 📤 **Partage** : partage de pronostics en image
- 💾 **Sauvegarde** : export/import des données

## 🛠 Stack technique

| Couche | Technologie |
|--------|-------------|
| Framework | Flutter 3.x / Dart 3 |
| État | Provider |
| HTTP | `http` package |
| Stockage local | `shared_preferences` |
| Données | API PMU (`turfinfo.api.pmu.fr`) + Zone-Turf |
| Notifications | MethodChannel natif Android |
| Widget | AppWidgetProvider Kotlin |

## 🚀 Démarrage rapide

### Prérequis

- Flutter SDK `>=3.0.0`
- Android Studio / VS Code
- JDK 11+

### Installation

```bash
git clone https://github.com/VOTRE_USER/Pronostic-Hippique-V2.git
cd Pronostic-Hippique-V2
flutter pub get
```

### Build debug

```bash
flutter run
```

### Build release (APK)

1. **Configurer la signature** (une seule fois) :
   ```bash
   cp android/key.properties.template android/key.properties
   # Éditer android/key.properties avec vos vraies valeurs
   ```

2. **Générer l'APK** :
   ```bash
   flutter build apk --release
   # → build/app/outputs/flutter-apk/app-release.apk
   ```

3. **Générer un AAB** (pour le Play Store) :
   ```bash
   flutter build appbundle --release
   ```

## 🐍 Proxy Python (mode Web uniquement)

Le fichier `proxy_server.py` est **uniquement nécessaire pour la version Web** (contournement CORS).
Pour la version APK Android, l'app appelle directement les APIs sans proxy.

```bash
# Démarrer le proxy (si déploiement web)
python3 proxy_server.py
# Écoute sur http://localhost:5060
```

## 📁 Structure du projet

```
lib/
├── main.dart                    # Point d'entrée, navigation principale
├── models/                      # Modèles de données (PMU, ZoneTurf)
├── providers/                   # State management (Provider)
├── screens/                     # Écrans de l'application
│   ├── home_screen.dart
│   ├── programme_screen.dart
│   ├── predictions_screen.dart
│   ├── best_bet_screen.dart
│   ├── mes_paris_screen.dart
│   ├── ia_performance_screen.dart
│   └── profile_screen.dart
├── services/                    # Logique métier
│   ├── pmu_api_service.dart     # API PMU officielle
│   ├── zone_turf_service.dart   # Scraping Zone-Turf
│   ├── ia_pronostic_engine.dart # Moteur IA
│   ├── ia_memory_service.dart   # Mémoire adaptative
│   ├── elo_service.dart         # Ratings ELO chevaux
│   ├── alert_service.dart       # Notifications push
│   └── prediction_engine.dart   # Calcul des pronostics
└── widgets/                     # Composants UI réutilisables
android/
├── app/
│   ├── build.gradle.kts         # Config build Android
│   ├── key.properties.template  # Template de signature (⚠️ copier en key.properties)
│   └── src/main/kotlin/         # Code natif Kotlin
│       ├── MainActivity.kt
│       ├── RacePredictorWidget.kt
│       └── BootReceiver.kt
```

## 🔑 Signature & Sécurité

- Le fichier `android/key.properties` est **exclu du dépôt** (`.gitignore`)
- Les APKs compilés sont **exclus du dépôt** — voir la section [Releases](../../releases)
- Ne jamais committer le fichier `.jks` / `.keystore`

## 📦 Releases

Les APKs signés sont disponibles dans les [GitHub Releases](../../releases).

## 📄 Licence

Projet privé — tous droits réservés.
