import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.kspstadk.rupeetrack"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Needed by flutter_local_notifications (java.time on old Androids).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // The id on Google Play; it can never change after the first upload.
        // (The Kotlin code keeps its original package, `namespace` above.)
        applicationId = "com.rupio.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release signing: android/key.properties (storeFile, storePassword,
    // keyAlias, keyPassword) when present. Otherwise a shared dev key that is
    // committed to the repo, so every test build has the same signature: new
    // APKs install over old ones (keeping data) and Google sign-in sees a
    // stable SHA-1. The dev key is public: never use it for the Play Store.
    val keyProps = Properties().apply {
        val f = rootProject.file("key.properties")
        if (f.exists()) f.inputStream().use { load(it) }
    }
    signingConfigs {
        if (keyProps.containsKey("storeFile")) {
            create("release") {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
        create("dev") {
            storeFile = file("dev-keystore.jks")
            storePassword = "rupeetrack-dev"
            keyAlias = "dev"
            keyPassword = "rupeetrack-dev"
        }
    }

    // Two builds of the same app:
    //  - direct: the APK people download from GitHub. Reads bank SMS and is
    //    always signed with the dev key, so it installs over earlier builds.
    //  - play: the Google Play bundle. No SMS permission (Play only allows
    //    it after a separate declaration is approved); signed with the
    //    private upload key from android/key.properties.
    flavorDimensions += "store"
    productFlavors {
        create("direct") {
            dimension = "store"
            signingConfig = signingConfigs.getByName("dev")
        }
        create("play") {
            dimension = "store"
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("dev")
        }
    }

    buildTypes {
        release {
            // Signing comes from the flavor (see above).
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
