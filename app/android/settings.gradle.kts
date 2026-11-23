pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
    // Glance widgets compile @Composable lambdas in :app Kotlin; without the
    // Compose Compiler plugin K2 emits provideContent(..., Function0, ...)
    // call sites against glance-appwidget's Function2 (composable) signature
    // — every widget tile then dies NoSuchMethodError at the launcher
    // (launch blocker, pipeline 1125 dex forensics). Version MUST equal KGP.
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.0" apply false
}

include(":app")
