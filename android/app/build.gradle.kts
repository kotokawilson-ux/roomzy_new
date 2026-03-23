plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.roomzy_new"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"                // ← fix 1: was JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.roomzy_new"
        minSdk = flutter.minSdkVersion                     // ← fix 2: was flutter.minSdkVersion (too low)
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = file(System.getenv("CM_KEYSTORE_PATH") ?: "debug.keystore")
            storePassword = System.getenv("CM_KEYSTORE_PASSWORD") ?: "android"
            keyAlias = System.getenv("CM_KEY_ALIAS") ?: "androiddebugkey"
            keyPassword = System.getenv("CM_KEY_PASSWORD") ?: "android"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false     // ← fix 3: was minifyEnabled
            isShrinkResources = false   // ← fix 4: was shrinkResources
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:34.10.0"))
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-firestore")
    implementation("com.google.firebase:firebase-auth")
}
