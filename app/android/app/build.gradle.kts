import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// google-services: aplicado SOLO si `google-services.json` está
// presente. Así un checkout fresco (sin Firebase configurado
// localmente) sigue compilando — útil para CI local debug y para
// onboarding del repo. El workflow de release siempre baja el
// archivo desde un secret antes de buildear, y todos los APK release
// quedan listos para App Distribution.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// Keystore de release. Si existe `android/key.properties`, lo usamos
// para firmar la build de release con una llave estable. Sin él
// (clean checkout, dev local), caemos a la debug keystore para que
// `flutter run --release` siga funcionando.
//
// IMPORTANTE: cada APK que distribuimos por OTA tiene que ir firmado
// con LA MISMA llave. Si dos builds tienen firma distinta, Android
// rechaza la actualización en silencio (el instalador cierra sin
// mensaje). Antes (todos los builds del CI con la debug keystore
// efímera de la VM), ningún update OTA funcionaba.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hayKeystoreRelease = keystorePropertiesFile.exists()
if (hayKeystoreRelease) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "dev.matix.matix"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Requerido por `flutter_local_notifications` para usar las APIs
        // de java.time en versiones de Android sin soporte nativo.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "dev.matix.matix"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hayKeystoreRelease) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                // `storeFile` en key.properties es relativa a android/.
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Si hay key.properties → firmamos con la llave estable
            // (caso CI release, que distribuye OTA).
            // Si no → debug keystore para que `flutter run --release`
            // local siga funcionando sin obligar al desarrollador a
            // generar una llave propia.
            signingConfig = if (hayKeystoreRelease) {
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

dependencies {
    // Core library desugaring para `flutter_local_notifications`.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
