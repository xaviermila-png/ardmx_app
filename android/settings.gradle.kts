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
    // AGP 9.x breaks file_picker's Kotlin compilation (its build.gradle skips
    // applying the Kotlin plugin when AGP >= 9, assuming AGP's built-in
    // Kotlin support will compile it instead — that didn't happen in
    // practice here, leaving FilePickerPlugin.kt uncompiled and the app
    // failing to build with "cannot find symbol: class FilePickerPlugin").
    // Pinned to the latest 8.x line instead, which Flutter still fully
    // supports and file_picker actually works with.
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")
