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
