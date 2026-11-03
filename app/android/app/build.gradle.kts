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

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
}
