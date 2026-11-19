plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// Release signing reads the keystore from the environment (set by scripts/build-release.sh):
//   POCKETPASTE_KEYSTORE=/absolute/path/to/pocketpaste-release.jks
//   POCKETPASTE_KEYSTORE_PASSWORD=…   (store and key password are the same, PKCS12)
// The keystore is kept off this machine; see RELEASING.md. Without it, assembleRelease produces an unsigned APK.
val releaseKeystore = System.getenv("POCKETPASTE_KEYSTORE")?.takeIf { it.isNotBlank() }
val releaseKeystorePassword = System.getenv("POCKETPASTE_KEYSTORE_PASSWORD")

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
        if (releaseKeystore != null && releaseKeystorePassword != null) {
            create("release") {
                storeFile = file(releaseKeystore)
                storePassword = releaseKeystorePassword
                keyAlias = "pocketpaste"
                keyPassword = releaseKeystorePassword
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
