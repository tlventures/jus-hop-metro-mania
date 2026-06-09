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
    // compileSdk 36: required by google_mobile_ads 9.x and several other
    // plugins. targetSdk stays at 35 (Play's current requirement); compiling
    // against a higher SDK is backward compatible.
    compileSdk = 36

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
        // Explicit SDK levels rather than the Flutter defaults so a toolchain
        // bump can never silently regress us below Play Store requirements.
        //   minSdk 23   — required by firebase_auth / google_mobile_ads 7.x.
        //   targetSdk 35 — Play Store mandates target API 35 for new app
        //     submissions and updates (effective Aug 2025).
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["adMobApplicationId"] =
            (project.findProperty("ADMOB_APP_ID") as String?)
                ?: System.getenv("ADMOB_APP_ID")
                ?: "ca-app-pub-3940256099942544~3347511713"

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
