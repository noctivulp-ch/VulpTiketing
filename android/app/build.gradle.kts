import java.util.Properties

// La clave de firma del release, si esta maquina la tiene.
//
// Vive en `android/key.properties`, que NO esta en el repositorio, y apunta a un
// keystore fuera del proyecto. Si el archivo no esta, el release se firma con la
// clave de depuracion y se avisa al compilar: sirve para probar en otra maquina,
// pero un APK firmado asi NO se puede instalar encima del de produccion.
val propiedadesDeFirma = Properties().apply {
    val archivo = rootProject.file("key.properties")
    if (archivo.exists()) archivo.inputStream().use { load(it) }
}
val hayClavePropia = propiedadesDeFirma.getProperty("storeFile") != null

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.vulptiketing.vulp_tiketing"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.vulptiketing.vulp_tiketing"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hayClavePropia) {
            create("produccion") {
                storeFile = file(propiedadesDeFirma.getProperty("storeFile"))
                storePassword = propiedadesDeFirma.getProperty("storePassword")
                keyAlias = propiedadesDeFirma.getProperty("keyAlias")
                keyPassword = propiedadesDeFirma.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // La clave de firma es lo que permite instalar una actualizacion
            // ENCIMA de la app del negocio. Con otra clave, Android exige
            // desinstalar, y desinstalar borra las ventas cobradas.
            signingConfig = if (hayClavePropia) {
                signingConfigs.getByName("produccion")
            } else {
                logger.warn(
                    "AVISO: sin android/key.properties, el release se firma con la clave de " +
                        "DEPURACION. Ese APK no se instala encima del de produccion.",
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
