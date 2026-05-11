import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(FileInputStream(keyPropertiesFile))
}

android {
    namespace = "com.racepredictor.predict"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    signingConfigs {
        create("release") {
            keyAlias = keyProperties["keyAlias"] as? String ?: ""
            keyPassword = keyProperties["keyPassword"] as? String ?: ""
            storeFile = keyProperties["storeFile"]?.let { rootProject.file(it as String) }
            storePassword = keyProperties["storePassword"] as? String ?: ""
        }
    }

    defaultConfig {
        applicationId = "com.racepredictor.predict"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ★ WorkManager — tâche arrière-plan toutes les heures (cotes PMU + alertes favorites)
    implementation("androidx.work:work-runtime-ktx:2.9.0")
}
