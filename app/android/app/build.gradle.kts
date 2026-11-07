plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.steiner.local_budget"
    // Highest *released* platform. 37 does not exist in the sdkmanager repo
    // yet (pipeline 43), and the share plugin is pinned to 1.8.1 (compileSdk
    // 34), so nothing in the graph demands 37.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications (#35, design e3 §5) runs on java.time.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.steiner.local_budget"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // ML Kit GenAI (Gemini Nano via AICore, issue #29) requires API 26;
        // the feasibility doc's Android floor is 8.0 either way.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // E9 (#47) · SELF-SIGNING (decision 13): this key IS the app
        // signing key — Play merely ships what it signs. There is NO
        // support-side key reset if it is lost: custody is the encrypted
        // blob in two cloud buckets + the passphrase split (password
        // manager & safe deposit box). CI supplies it as a secret-file
        // variable (SIGNING_KEYSTORE -> keystore path) plus
        // SIGNING_KEYSTORE_PASSWORD (+ optional SIGNING_KEY_ALIAS, default
        // "signing"). No env (every local `flutter run --release`, debug
        // packaging lanes): stays on debug keys exactly as before.
        create("signing") {
            val ks = System.getenv("SIGNING_KEYSTORE")
            if (!ks.isNullOrEmpty() && file(ks).exists()) {
                storeFile = file(ks)
                storePassword = System.getenv("SIGNING_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("SIGNING_KEY_ALIAS")?.takeIf { it.isNotEmpty() } ?: "signing"
                keyPassword = System.getenv("SIGNING_KEY_PASSWORD")
                    ?.takeIf { it.isNotEmpty() }
                    ?: System.getenv("SIGNING_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Signed with the self-held app signing key when CI provides
            // it; debug keys as the local fallback so
            // `flutter run --release` still works without secrets (the CI
            // aab lane GATES on the env and never ships a debug-signed aab).
            signingConfig = if (System.getenv("SIGNING_KEYSTORE")?.isNotEmpty() == true)
                signingConfigs.getByName("signing")
            else
                signingConfigs.getByName("debug")
            // AGP 9 (gradle 9.3 era) defaults shrinking ON, and R8 trips over
            // ML Kit's optional language jars (referenced-but-absent classes)
            // — the wall Steiner Vault hit on 2026-11-07 (no release build
            // had ever run here either). Release-kit work re-enables with
            // keep rules; permission merging does not depend on shrinking.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // E6 v2 (spec §2): two store listings, one codebase. `free` keeps the
    // original applicationId; `pro` is a distinct package (.pro suffix) so
    // both install side by side and the signature-permission transfer can
    // cross between them (same signing key). Each build MUST also pass
    // --dart-define=APP_FLAVOR=pro for the pro flavor — flavor pairing is
    // documented in the spec and enforced by CI job names, not by Gradle.
    flavorDimensions += "tier"
    productFlavors {
        create("free") {
            dimension = "tier"
        }
        create("pro") {
            dimension = "tier"
            applicationIdSuffix = ".pro"
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
    // Tier-3 structurer (issue #29): ML Kit GenAI prompt API. The Flutter
    // wrapper package stubs inference, so MainActivity talks to this
    // artifact through the localbudget/capture channel.
    implementation("com.google.mlkit:genai-prompt:1.0.0-beta4")
    // java.time backport for flutter_local_notifications (needs ≥ 2.1.4).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // E7c §4: the Glance widget trio. Receivers are declared only in the
    // pro flavor's manifest, so the free app ships the classes as inert
    // dead weight (R8 strips them in release). API 26+ matches minSdk.
    implementation("androidx.glance:glance-appwidget:1.1.1")
    // E7c §4.3 day-rollover tick — scheduled from the pro Application only.
    implementation("androidx.work:work-runtime-ktx:2.9.1")
    // Parity guard against the Dart codec fixture (packages/core).
    testImplementation("junit:junit:4.13.2")
    // Unit tests run against the mockable android.jar, whose org.json is a
    // throw-everything stub; the real artifact must shadow it on the test
    // classpath for WidgetState.parse to do anything there.
    testImplementation("org.json:json:20240303")
}
