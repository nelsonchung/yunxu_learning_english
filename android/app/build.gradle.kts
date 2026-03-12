import org.gradle.api.GradleException
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseSigning =
    keystorePropertiesFile.exists().also { exists ->
        if (exists) {
            keystorePropertiesFile.inputStream().use(keystoreProperties::load)
        }
    }

val requiresReleaseSigning =
    gradle.startParameter.taskNames.any { taskName ->
        taskName.contains("release", ignoreCase = true) ||
            taskName.contains("bundle", ignoreCase = true) ||
            taskName.contains("publish", ignoreCase = true)
    }

val requiredKeystoreKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val missingKeystoreKeys =
    requiredKeystoreKeys.filter { key ->
        keystoreProperties.getProperty(key).isNullOrBlank()
    }
val releaseKeystoreFile =
    if (hasReleaseSigning && missingKeystoreKeys.isEmpty()) {
        rootProject.file(keystoreProperties.getProperty("storeFile"))
    } else {
        null
    }

android {
    namespace = "com.yunxu.yunxulearn"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.yunxu.yunxulearn"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning && missingKeystoreKeys.isEmpty()) {
            create("release") {
                storeFile = releaseKeystoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (!hasReleaseSigning && requiresReleaseSigning) {
                throw GradleException(
                    "Missing android/key.properties. Copy android/key.properties.example and fill in your upload keystore settings before building a release."
                )
            }
            if (missingKeystoreKeys.isNotEmpty() && requiresReleaseSigning) {
                throw GradleException(
                    "android/key.properties is missing: ${missingKeystoreKeys.joinToString(", ")}"
                )
            }
            if (requiresReleaseSigning && releaseKeystoreFile?.exists() == false) {
                throw GradleException(
                    "Upload keystore not found: ${releaseKeystoreFile.path}. Check storeFile in android/key.properties."
                )
            }
            if (hasReleaseSigning && missingKeystoreKeys.isEmpty()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:1.2.2")
}
