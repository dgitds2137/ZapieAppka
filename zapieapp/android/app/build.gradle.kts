import java.util.Properties

val googlePlayTargetSdk = 35

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use(keystoreProperties::load)
}

android {
    namespace = "pl.zapieapp.mobile"
    compileSdk = googlePlayTargetSdk
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = (keystoreProperties["storeFile"] as String?)?.let(::file)
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

    defaultConfig {
        applicationId = "pl.zapieapp.mobile"
        minSdk = flutter.minSdkVersion
        targetSdk = googlePlayTargetSdk
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appName"] = "Zapie Appka"
        manifestPlaceholders["usesCleartextTraffic"] = "false"
    }

    flavorDimensions += "env"
    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            manifestPlaceholders["appName"] = "Zapie Appka DEV"
            manifestPlaceholders["usesCleartextTraffic"] = "true"
        }
        create("prod") {
            dimension = "env"
            manifestPlaceholders["appName"] = "Zapie Appka"
            manifestPlaceholders["usesCleartextTraffic"] = "false"
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
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

gradle.taskGraph.whenReady {
    val blockedTasks = allTasks
        .map { it.name }
        .filter { taskName ->
            taskName in setOf(
                "assembleDebug",
                "assembleProfile",
                "assembleRelease",
                "bundleDebug",
                "bundleProfile",
                "bundleRelease",
                "installDebug",
                "installProfile",
                "installRelease",
            )
        }

    if (blockedTasks.isNotEmpty()) {
        throw GradleException(
            "Unflavored Android build is disabled. Use --flavor dev or --flavor prod.",
        )
    }

    val prodReleaseTasks = allTasks
        .map { it.name }
        .filter { taskName ->
            taskName in setOf(
                "assembleProdRelease",
                "bundleProdRelease",
                "installProdRelease",
            )
        }

    if (prodReleaseTasks.isNotEmpty() && !keystorePropertiesFile.exists()) {
        throw GradleException(
            "Production release builds require android/key.properties with the Play upload key.",
        )
    }
}
