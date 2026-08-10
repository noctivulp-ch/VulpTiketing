package com.vulptiketing.vulp_tiketing

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.MethodChannel

/**
 * Atajos a las pantallas de ajustes de Android que la app necesita.
 *
 * Existe porque nadie las encuentra. La exención de batería vive a cinco toques
 * de profundidad y con un nombre distinto en cada marca —"Optimización de
 * batería", "Inicio automático", "Aplicaciones protegidas"—, y sin ella el
 * sistema mata la sincronización en cuanto la pantalla se apaga: la caja deja de
 * compartir ventas y nada en la app avisa de que dejó de hacerlo.
 *
 * Son atajos, no permisos: la app no puede concederse nada a sí misma. Lo único
 * que hace es dejar al usuario en la pantalla correcta.
 *
 * Cada método dice si pudo abrir algo. Ninguna de estas pantallas existe en
 * todas las versiones ni en todas las marcas —hay fabricantes que se las quitan
 * de encima— y un `Intent` que nadie atiende lanza `ActivityNotFoundException`.
 * Decirlo permite avisar en pantalla en vez de dejar la app muerta al toque.
 */
class AjustesAndroid(private val actividad: Activity) {

    fun atender(metodo: String, resultado: MethodChannel.Result, url: String? = null) {
        when (metodo) {
            "abrirEnlace" -> resultado.success(url != null && abrirEnlace(url))
            "estado" -> resultado.success(estado())
            "bateria" -> resultado.success(abrirBateria())
            "permisos" -> resultado.success(abrir(detallesDeLaApp()))
            "datosEnSegundoPlano" -> resultado.success(abrirDatosEnSegundoPlano())
            "abrirPorDefecto" -> resultado.success(abrirPorDefecto())
            else -> resultado.notImplemented()
        }
    }

    /**
     * Lo que se puede saber sin abrir nada.
     *
     * Solo la exención de batería es consultable: Android la expone con una API
     * y las demás no. Se devuelve para poder marcar en la pantalla lo que ya
     * está hecho — una lista de atajos sin estado obliga a entrar en cada uno
     * para averiguar si hacía falta.
     */
    private fun estado(): Map<String, Any> {
        val power = actividad.getSystemService(Context.POWER_SERVICE) as PowerManager
        return mapOf(
            "sinOptimizacionDeBateria" to power.isIgnoringBatteryOptimizations(
                actividad.packageName,
            ),
            "version" to Build.VERSION.SDK_INT,
            "fabricante" to Build.MANUFACTURER,
        )
    }

    /**
     * Pide la exención directamente, y si no se puede cae a la lista del sistema.
     *
     * El diálogo directo (`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`) es un sí
     * o no y se acaba; la lista obliga a buscar la app entre todas. Se prefiere
     * el diálogo, pero hay ROMs que lo bloquean, y ahí la lista es mejor que
     * nada.
     */
    private fun abrirBateria(): Boolean {
        val power = actividad.getSystemService(Context.POWER_SERVICE) as PowerManager
        if (power.isIgnoringBatteryOptimizations(actividad.packageName)) {
            // Ya está concedida: se abre la lista para poder QUITARLA. El diálogo
            // de petición no aparece cuando ya se tiene, así que el toque no
            // haría nada y parecería que la app se colgó.
            return abrir(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }
        val directo = Intent(
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:${actividad.packageName}"),
        )
        return abrir(directo) || abrir(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
    }

    /**
     * La pantalla de uso de datos de esta app, donde se permite el segundo plano.
     *
     * `ACTION_IGNORE_BACKGROUND_DATA_RESTRICTIONS_SETTINGS` es la específica, y
     * cuando no está se cae a los detalles de la app: desde ahí se llega en un
     * toque más, que sigue siendo mucho menos que buscarla desde cero.
     */
    private fun abrirDatosEnSegundoPlano(): Boolean {
        val especifica = Intent(
            Settings.ACTION_IGNORE_BACKGROUND_DATA_RESTRICTIONS_SETTINGS,
            Uri.parse("package:${actividad.packageName}"),
        )
        return abrir(especifica) || abrir(detallesDeLaApp())
    }

    /**
     * "Abrir por defecto": qué archivos abre esta app al tocarlos.
     *
     * La pantalla dedicada existe desde Android 12. En versiones anteriores la
     * asociación se resuelve sola —el sistema pregunta con qué app abrir la
     * primera vez— así que se cae a los detalles de la app, donde también está.
     */
    private fun abrirPorDefecto(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val porDefecto = Intent(
                Settings.ACTION_APP_OPEN_BY_DEFAULT_SETTINGS,
                Uri.parse("package:${actividad.packageName}"),
            )
            if (abrir(porDefecto)) return true
        }
        return abrir(detallesDeLaApp())
    }

    /**
     * Abre una direccion en el navegador.
     *
     * Va por el mismo camino que el resto de estos atajos —un `Intent` y a ver
     * quien lo atiende— en vez de traer `url_launcher`: es una linea de codigo
     * nativo contra una dependencia mas, y en este proyecto cada plugin nuevo
     * arrastra avisos de Gradle y riesgo de compilacion en tres plataformas.
     */
    private fun abrirEnlace(url: String): Boolean {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
            // La app no esta en una tarea de navegador: sin esto, la direccion se
            // abre DENTRO de la pila de la app y al volver atras se sale de ella.
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return abrir(intent)
    }

    private fun detallesDeLaApp() = Intent(
        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
        Uri.parse("package:${actividad.packageName}"),
    )

    private fun abrir(intent: Intent): Boolean {
        return try {
            actividad.startActivity(intent)
            true
        } catch (e: Exception) {
            // Cualquier excepción, no solo `ActivityNotFoundException`: hay ROMs
            // que lanzan `SecurityException` al pedir pantallas que consideran
            // suyas. Desde acá el único desenlace útil es "no se pudo".
            false
        }
    }
}
