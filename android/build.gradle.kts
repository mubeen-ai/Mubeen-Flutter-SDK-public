group = "ai.mubeen.mubeen_flutter"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.4.0"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        // Supplies AGP and the Kotlin Gradle plugin only when the client's build does not
        // already load them; a client app's own versions win. This module is not meant to
        // be built on its own (it needs the Flutter embedding from the app's build).
        classpath("com.android.tools.build:gradle:9.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
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
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "ai.mubeen.mubeen_flutter"

    // 34, not 36, in the legacy build: AGP 7.x (Flutter 3.22's app template pins 7.3.0)
    // ships an aapt2 that cannot read the android-36 platform jar. The plugin uses no API
    // above 33 (TIRAMISU), and deviceintel-lib's AAR declares minCompileSdk=1.
    compileSdk = 34

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

// Legacy build for apps on Flutter older than 3.44: this module applies the Kotlin Gradle
// plugin itself instead of relying on Flutter's built-in Kotlin.
// This script is compiled and run by the CLIENT app's Gradle and Kotlin Gradle plugin, not
// the versions in `buildscript` above, so it sticks to DSL that old client toolchains have:
// - task-level `compilerOptions` (KGP 1.8+), not `kotlin { compilerOptions { } }`, which
//   Flutter 3.27-3.29 app templates (KGP 1.8.22) do not have;
// - `.set()`, not `=`: Gradle < 8.2 (Flutter 3.22's template: 7.6.3) has no Kotlin DSL
//   property assignment.
// Task-level `compilerOptions` needs KGP 1.8.0+. Apps created by Flutter 3.22 to 3.24.1 pin
// 1.7.10 (raise to 1.8.0+); 3.24.2 or newer pin 1.8.22 or newer (README).
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
}

dependencies {
    implementation("ai.mubeen:deviceintel-lib:1.7.3")

    testImplementation("junit:junit:4.13.2")
    testImplementation("io.mockk:mockk:1.13.5")
    // compileSdk is 34 in this build. 4.17 is kept in step with the main build, whose
    // compileSdk 36 needs it (the first Robolectric with an android-all jar for API 36).
    testImplementation("org.robolectric:robolectric:4.17")
    testImplementation("androidx.test:core:1.6.1")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.7.3")
}
