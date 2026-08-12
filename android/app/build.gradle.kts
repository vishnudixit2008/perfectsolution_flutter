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
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.perfectsolution.shop_management_flutter"
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
        applicationId = "com.perfectsolution.shop_management_flutter"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        val keystorePath = keystoreProperties.getProperty("storeFile") ?: "upload-keystore.jks"
        val keystoreFile = file(keystorePath)
        val altKeystoreFile = project.file("app/$keystorePath")

        if (keystorePropertiesFile.exists() && (keystoreFile.exists() || altKeystoreFile.exists())) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias") ?: "upload"
                keyPassword = keystoreProperties.getProperty("keyPassword") ?: "shopmanagement123"
                storeFile = if (keystoreFile.exists()) keystoreFile else altKeystoreFile
                storePassword = keystoreProperties.getProperty("storePassword") ?: "shopmanagement123"
            }
        }
    }

    buildTypes {
        release {
            val releaseConfig = signingConfigs.findByName("release")
            if (releaseConfig != null) {
                signingConfig = releaseConfig
            } else {
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }

}

flutter {
    source = "../.."
}
