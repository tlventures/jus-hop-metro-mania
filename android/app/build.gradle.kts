import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

// Load signing config from android/key.properties (not committed to git)
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.tlventures.metrosafar"
    compileSdk = flutter.compileSdkVersion

    // Update NDK version to match what plugins require
    ndkVersion = "29.0.13113456"

    compileOptions {
        // Enable desugaring for Java 8+ features
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    defaultConfig {
        applicationId = "com.tlventures.metrosafar"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["adMobApplicationId"] =
            (project.findProperty("ADMOB_APP_ID") as String?)
                ?: System.getenv("ADMOB_APP_ID")
                ?: "ca-app-pub-3940256099942544~3347511713"

        // Google Maps SDK key. Kept out of source: supplied via the gitignored
        // android/key.properties (mapsApiKey=...), a -PMAPS_API_KEY gradle
        // property, or the MAPS_API_KEY env var. Empty by default so debug
        // builds still assemble; a real key is required before any map screen
        // ships. See RELEASE_SETUP.md.
        manifestPlaceholders["mapsApiKey"] =
            (keystoreProperties["mapsApiKey"] as String?)
                ?: (project.findProperty("MAPS_API_KEY") as String?)
                ?: System.getenv("MAPS_API_KEY")
                ?: ""

        // Enable multidex support
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    // Update desugaring dependency to required version
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // For multidex support
    implementation("androidx.multidex:multidex:2.0.1")

    // Flutter's deferred-component manager references Play Feature Delivery
    // classes during R8 minification even when no deferred modules are used.
    implementation("com.google.android.play:feature-delivery:2.1.0")

    // Android 12+ Splash Screen API (animated launch icon shown immediately
    // by the OS, before the Flutter engine boots).
    implementation("androidx.core:core-splashscreen:1.0.1")
}

flutter {
    source = "../.."
}
