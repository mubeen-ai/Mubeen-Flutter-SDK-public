import java.util.Base64

plugins {
    id("com.android.application")
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
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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
