# Steiner Budget · R8 rules (enablement 2026-11-16)
# Companion of build.gradle.kts release block; baseline optimization rules
# arrive via getDefaultProguardFile("proguard-android-optimize.txt").

# The ML Kit wall (2026-11-07, first seen on Steiner Vault): the bundled
# text-recognition artifact soft-references optional language/model classes
# that deliberately do NOT ship in the free build. They are resolved at
# runtime only when a language pack is installed; R8 must not fail on them.
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.internal.mlkit_**.

# ML Kit reflection keeps — DEVICE-PROVEN NEED, 2026-11-16, SL219A.
# With shrinking on and only dontwarns present, every OCR call died at
# app start (logcat, after clearing adbd echo noise): ML Kit assembles
# its components via Firebase's ServiceLoader discovery —
# NoSuchMethodException: CommonComponentRegistrar.<init> [] and
# TextRegistrar.<init> [] — every registrar is instantiated by
# REFLECTION through a no-arg constructor, and an un-assembled client
# NPEs on every call afterwards. The app's collapse-to-[] design made
# all of it SILENT to CI and the Review sheet; only the hardware walk
# caught it.
#
# The keep is the interface rule (mirrors Firebase's own documented
# guidance): exactly the registrar classes and their <init>(), nothing
# else. Deliberately NOT "-keep class com.google.mlkit.** { *; }" —
# a blanket keep would exempt the whole OCR stack from obfuscation and
# optimization, defeating the DEX scorecard purpose of this whole MR.
# Everything that is NOT reflection surface stays shrunk.
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }

# Flutter plugin classes are instantiated by GeneratedPluginRegistrant
# (direct references R8 sees); no blanket keeps. If a future plugin loads
# by reflection and dies only in release, the fix belongs HERE, named and
# commented with the plugin — never a broad -keep.

# House rule: shrinking stays auditable. Every keep/dontwarn line must
# carry (a) the artifact it serves and (b) the day it was needed.
