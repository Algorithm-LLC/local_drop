import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use(keystoreProperties::load)
}

fun releaseSecret(envName: String, propertyName: String): String? {
    val fromEnv = providers.environmentVariable(envName).orNull?.trim()
    if (!fromEnv.isNullOrEmpty()) {
        return fromEnv
    }
    val fromProperties = keystoreProperties.getProperty(propertyName)?.trim()
    if (!fromProperties.isNullOrEmpty()) {
        return fromProperties
    }
    return null
}

val releaseStoreFilePath = releaseSecret("LOCALDROP_KEYSTORE_PATH", "storeFile")
val releaseStorePassword = releaseSecret("LOCALDROP_KEYSTORE_PASSWORD", "storePassword")
val releaseKeyAlias = releaseSecret("LOCALDROP_KEY_ALIAS", "keyAlias")
val releaseKeyPassword = releaseSecret("LOCALDROP_KEY_PASSWORD", "keyPassword")
val hasReleaseSigning = listOf(
    releaseStoreFilePath,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrEmpty() }

android {
    namespace = "com.algorithm.localdrop"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.algorithm.localdrop"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStoreFilePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                // Keep CI/local release APKs installable when a real release keystore
                // is not configured yet. Production releases should still provide
                // LOCALDROP_* signing secrets or android/key.properties.
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
