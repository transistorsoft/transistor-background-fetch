plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.transistorsoft.backgroundfetch.example"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.transistorsoft.backgroundfetch.example"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = "11"
    }
    buildFeatures {
        viewBinding = true
    }
}

dependencies {
    // ── Background Fetch SDK (Maven Central) ─────────────────────────────────
    // The library AAR contributes its own manifest entries (FetchJobService,
    // BootReceiver, FetchAlarmReceiver + RECEIVE_BOOT_COMPLETED / WAKE_LOCK /
    // SCHEDULE_EXACT_ALARM), so this app declares none of them itself.
    implementation("com.transistorsoft:tsbackgroundfetch:4.1.1")

    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("com.google.android.material:material:1.13.0")
}
