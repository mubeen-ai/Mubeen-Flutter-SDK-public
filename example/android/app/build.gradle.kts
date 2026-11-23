import java.util.Base64

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "ai.mubeen.mubeen_flutter_example"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "ai.mubeen.mubeen_flutter_example"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Literals: Flutter 3.22 exposes these as methods (flutter.versionCode()), newer
        // Flutter as properties (flutter.versionCode), so no one form builds on every Flutter
        // this legacy build supports. The harness never ships to a store.
        versionCode = 1
        versionName = "1.0"
    }

    sourceSets {
        // Debug builds (and so the integration tests) may reach the fake ingestion
        // server over plain HTTP; the manifest attribute is in src/debug.
        getByName("debug").res.srcDir("src/e2eCleartext/res")
        // A release build gets the same, narrow, cleartext allowance only when it is
        // the CI self-test build. Keying it on the dart-define that turns the
        // self-test on means the two cannot drift apart, and a normal
        // `flutter build apk --release` stays exactly as strict as a client's.
        if (isReleaseSelfTestBuild()) {
            getByName("release") {
                manifest.srcFile("src/e2eCleartext/AndroidManifest.xml")
                res.srcDir("src/e2eCleartext/res")
            }
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

/**
 * Whether this build carries --dart-define=MUBEEN_E2E_SELFTEST_ENDPOINT=<non-empty>.
 * The Flutter tool passes dart-defines to Gradle as `-Pdart-defines=<base64>,<base64>`.
 */
fun isReleaseSelfTestBuild(): Boolean =
    (project.findProperty("dart-defines") as String?)
        .orEmpty()
        .split(",")
        .filter { it.isNotBlank() }
        .map { String(Base64.getDecoder().decode(it)) }
        .any { it.startsWith("MUBEEN_E2E_SELFTEST_ENDPOINT=") && it.length > "MUBEEN_E2E_SELFTEST_ENDPOINT=".length }

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
