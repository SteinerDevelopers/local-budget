# Steiner Budget · R8 rules (enablement 2026-11-16)
# Companion of build.gradle.kts release block; baseline optimization rules
# arrive via getDefaultProguardFile("proguard-android-optimize.txt").

# The ML Kit wall (2026-11-07, first seen on Steiner Vault): the bundled
# text-recognition artifact soft-references optional language/model classes
# that deliberately do NOT ship in the free build. They are resolved at
# runtime only when a language pack is installed; R8 must not fail on them.
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.internal.mlkit_**.

# Flutter plugin classes are instantiated by GeneratedPluginRegistrant
# (direct references R8 sees); no blanket keeps. If a future plugin loads
# by reflection and dies only in release, the fix belongs HERE, named and
# commented with the plugin — never a broad -keep.

# House rule: shrinking stays auditable. Every keep/dontwarn line must
# carry (a) the artifact it serves and (b) the day it was needed.
