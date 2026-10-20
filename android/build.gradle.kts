group = "ai.mubeen.mubeen_flutter"
version = "1.0-SNAPSHOT"

buildscript {
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        // No Kotlin Gradle plugin on this classpath: Flutter applies Kotlin to this
        // subproject itself (see the note further down), so pinning KGP here only cost a
        // cold build an extra resolution and gave us a version that would drift.
        classpath("com.android.tools.build:gradle:9.1.0")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "ai.mubeen.mubeen_flutter"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        // Matches deviceintel-lib's own minSdk (device_intel_lib/build.gradle.kts).
        minSdk = 24
        // Applied to the CLIENT app's R8 pass, not ours: see consumer-rules.pro.
        consumerProguardFiles("consumer-rules.pro")
    }

    testOptions {
        unitTests {
            // Robolectric needs the merged resources and the real android.jar behaviour.
            isIncludeAndroidResources = true

            all {
                // JUnit 4 + Robolectric: useJUnitPlatform() here would silently run zero tests.
                it.outputs.upToDateWhen { false }
                // `-DliveUpload=true` on the command line reaches the Gradle daemon, not this
                // forked test JVM. Forward it so LiveUploadIT's assume-gate can see it.
                it.systemProperty("liveUpload", System.getProperty("liveUpload") ?: "false")
                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

// No `org.jetbrains.kotlin.android`: Flutter's built-in Kotlin migration for plugin authors
// (docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors),
// which is why pubspec.yaml's floor is Flutter 3.44.
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("ai.mubeen:deviceintel-lib:1.7.3")

    testImplementation("junit:junit:4.13.2")
    testImplementation("io.mockk:mockk:1.13.5")
    // 4.17 is the first Robolectric with an android-all jar for API 36; an older one fails
    // every test at init with "targetSdkVersion=36 > maxSdkVersion", since compileSdk is 36.
    testImplementation("org.robolectric:robolectric:4.17")
    testImplementation("androidx.test:core:1.6.1")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.7.3")
}
