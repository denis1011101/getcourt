import java.util.Properties

plugins {
    id("com.android.application")
}

// Upload key lives outside the repo; release builds stay unsigned without it.
val keystoreProperties = Properties().apply {
    val path = providers.gradleProperty("getcourt.keystoreProperties")
        .getOrElse("${System.getProperty("user.home")}/.android-keys/getcourt.properties")
    file(path).takeIf { it.exists() }?.inputStream()?.use(::load)
}

android {
    namespace = "co.getcourt.app"
    compileSdk = 36

    defaultConfig {
        applicationId = "co.getcourt.app"
        minSdk = 28
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
        buildConfigField("String", "BASE_URL", "\"https://getcourt.co\"")
    }

    signingConfigs {
        if (keystoreProperties.isNotEmpty()) {
            create("upload") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        // Installs next to the store build and points at `bin/dev` via `adb reverse tcp:3000 tcp:3000`.
        debug {
            applicationIdSuffix = ".debug"
            buildConfigField("String", "BASE_URL", "\"http://localhost:3000\"")
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.findByName("upload")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        buildConfig = true
    }
}

dependencies {
    implementation("dev.hotwire:core:1.3.2")
    implementation("dev.hotwire:navigation-fragments:1.3.2")
}
