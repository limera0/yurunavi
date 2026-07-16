plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.westinx.gpsinjector"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.westinx.gpsinjector"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    buildTypes {
        debug {
            // 별도 서명 불필요 — 디버그 키만 사용, 실기기 사이드로드 전용 도구
        }
    }
}
