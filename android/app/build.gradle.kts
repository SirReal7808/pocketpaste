plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "dev.macclip.android"
    compileSdk = 36

    defaultConfig {
        applicationId = "dev.macclip.android"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
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

// The integration test talks to a running Mac app: ./gradlew test -PmacclipTestKey=... -PmacclipTestPort=...
tasks.withType<Test>().configureEach {
    listOf("macclipTestKey", "macclipTestPort", "macclipTestHost").forEach { name ->
        project.findProperty(name)?.let { systemProperty(name, it) }
    }
    outputs.upToDateWhen { false }
}
