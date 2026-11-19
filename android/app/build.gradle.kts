import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// Release signing reads android/keystore.properties (not in git):
//   storeFile=/absolute/path/to/pocketpaste-release.jks
//   storePassword=…
//   keyAlias=pocketpaste
//   keyPassword=…
// Without it, assembleRelease produces an unsigned APK.
val keystoreProperties = Properties().apply {
    rootProject.file("keystore.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) }
}

android {
    namespace = "io.github.sirreal7808.pocketpaste"
    compileSdk = 36

    defaultConfig {
        applicationId = "io.github.sirreal7808.pocketpaste"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    signingConfigs {
        if (keystoreProperties.isNotEmpty()) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation("androidx.work:work-runtime:2.10.1")
    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")
    testImplementation("junit:junit:4.13.2")
}

// The integration test talks to a running Mac app: ./gradlew test -PpocketpasteTestKey=... -PpocketpasteTestPort=...
tasks.withType<Test>().configureEach {
    listOf("pocketpasteTestKey", "pocketpasteTestPort", "pocketpasteTestHost").forEach { name ->
        project.findProperty(name)?.let { systemProperty(name, it) }
    }
    outputs.upToDateWhen { false }
}
