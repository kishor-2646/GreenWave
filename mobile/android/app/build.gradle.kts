import java.util.Properties
import java.io.FileInputStream

// 1. Logic to read the .env file from the root directory
val dotenv = Properties()
val dotenvFile = project.rootProject.file("../.env")
if (dotenvFile.exists()) {
    dotenvFile.inputStream().use { dotenv.load(it) }
}

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.green_wave"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // --- FIX: ENABLE CORE LIBRARY DESUGARING ---
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.green_wave"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Ensure multiDex is enabled for the desugaring library
        multiDexEnabled = true

        // 2. Correct Kotlin DSL syntax to inject the API key into AndroidManifest.xml
        manifestPlaceholders["googleMapsApiKey"] = dotenv.getProperty("GOOGLE_MAPS_API_KEY") ?: ""
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // --- ADD THE DESUGARING LIBRARY ---
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")

    // Ensure you have multidex if your app grows large
    implementation("androidx.multidex:multidex:2.0.1")
}