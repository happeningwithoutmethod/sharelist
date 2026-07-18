pluginManagement {
    // Resolve AVG truststore from this android/ directory, not the process CWD
    // (IDE sync often uses a different working directory than ./gradlew).
    val avgTrust = file(".certs/avg-truststore.jks")
    if (avgTrust.isFile) {
        System.setProperty("javax.net.ssl.trustStore", avgTrust.absolutePath)
        System.setProperty("javax.net.ssl.trustStorePassword", "changeit")
    }

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
    id("com.android.application") version "9.0.1" apply false
    // Match Flutter tools' embedded Kotlin (see flutter_tools/gradle/build.gradle.kts).
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
