plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.sensoritetest"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.sensoritetest"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

tasks.register("copyDebugApkOutputs") {
    dependsOn("assembleDebug")
    doLast {
        copy {
            from(layout.buildDirectory.file("outputs/apk/debug/app-debug.apk"))
            into(layout.buildDirectory.dir("outputs/flutter-apk"))
            rename("app-debug.apk", "app-debug.apk")
        }
        copy {
            from(layout.buildDirectory.file("outputs/apk/debug/app-debug.apk"))
            into(layout.buildDirectory.dir("outputs/flutter-apk"))
            rename("app-debug.apk", "sensorite-debug.apk")
        }
    }
}

tasks.register("copyReleaseApkOutputs") {
    dependsOn("assembleRelease")
    doLast {
        copy {
            from(layout.buildDirectory.file("outputs/apk/release/app-release.apk"))
            into(layout.buildDirectory.dir("outputs/flutter-apk"))
            rename("app-release.apk", "app-release.apk")
        }
        copy {
            from(layout.buildDirectory.file("outputs/apk/release/app-release.apk"))
            into(layout.buildDirectory.dir("outputs/flutter-apk"))
            rename("app-release.apk", "sensorite-release.apk")
        }
    }
}

afterEvaluate {
    tasks.findByName("assembleDebug")?.finalizedBy("copyDebugApkOutputs")
    tasks.findByName("assembleRelease")?.finalizedBy("copyReleaseApkOutputs")
}

flutter {
    source = "../.."
}
