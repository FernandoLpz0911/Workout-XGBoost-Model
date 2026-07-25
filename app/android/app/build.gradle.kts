plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.fernandolpzdev.workoutml"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // ADDED THIS LINE:
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.fernandolpzdev.workoutml"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release signing only configures itself when the REPIQ_* keystore properties are
    // supplied (a real release build). Without them — e.g. CI building a debug/test
    // APK — release falls back to the auto-generated debug key instead of crashing
    // Gradle configuration on a null keystore path.
    val hasReleaseKeystore = project.hasProperty("REPIQ_STORE_FILE")

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(project.property("REPIQ_STORE_FILE") as String)
                storePassword = project.property("REPIQ_STORE_PASSWORD") as String
                keyAlias = project.property("REPIQ_KEY_ALIAS") as String
                keyPassword = project.property("REPIQ_KEY_PASSWORD") as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

// ADDED THIS ENTIRE BLOCK AT THE BOTTOM:
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
