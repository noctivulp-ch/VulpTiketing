package com.vulptiketing.vulp_tiketing

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Publica un archivo en la carpeta Descargas del teléfono.
 *
 * Hace falta código nativo porque desde Android 10 el almacenamiento es
 * "scoped": `dart:io` no puede escribir en /storage/emulated/0/Download aunque
 * la carpeta exista y se vea — comprobado en el aparato, da EACCES. Lo único
 * que la app puede usar sin pedirle permisos al usuario es MediaStore, y eso no
 * tiene API en Dart.
 *
 * La alternativa era dejar los archivos en Android/data/<paquete>/, que es
 * donde caían: accesibles conectando el teléfono a una computadora y por nada
 * más. Para quien atiende la soda, un backup que solo existe conectando el
 * teléfono a una PC no es un backup.
 */
class MainActivity : FlutterActivity() {
    private val canal = "vulp/almacen_publico"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, canal)
            .setMethodCallHandler { call, resultado ->
                when (call.method) {
                    "publicar" -> publicar(
                        call.argument("origen")!!,
                        call.argument("nombre")!!,
                        call.argument("mime")!!,
                        resultado,
                    )
                    else -> resultado.notImplemented()
                }
            }
    }

    private fun publicar(
        origen: String,
        nombre: String,
        mime: String,
        resultado: MethodChannel.Result,
    ) {
        val archivo = File(origen)
        if (!archivo.exists()) {
            resultado.error("sin_origen", "No existe $origen", null)
            return
        }
        try {
            val destino = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                publicarPorMediaStore(archivo, nombre, mime)
            } else {
                publicarPorArchivo(archivo, nombre)
            }
            resultado.success(destino)
        } catch (e: Exception) {
            resultado.error("fallo_publicar", e.message, null)
        }
    }

    /** Android 10+: la única vía sin permisos. */
    private fun publicarPorMediaStore(archivo: File, nombre: String, mime: String): String {
        val valores = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, nombre)
            put(MediaStore.Downloads.MIME_TYPE, mime)
            // Subcarpeta propia: un backup, un catálogo y tres reportes sueltos
            // entre las descargas del navegador no se encuentran.
            put(
                MediaStore.Downloads.RELATIVE_PATH,
                "${Environment.DIRECTORY_DOWNLOADS}/VulpTiketing",
            )
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val resolver = contentResolver
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, valores)
            ?: throw IllegalStateException("MediaStore no aceptó el archivo")

        resolver.openOutputStream(uri).use { salida ->
            archivo.inputStream().use { entrada -> entrada.copyTo(salida!!) }
        }
        // Hasta que se baja IS_PENDING el archivo no le aparece a nadie más:
        // así nadie abre un backup a medio escribir.
        resolver.update(
            uri,
            ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) },
            null,
            null,
        )

        // El nombre REAL, no el que se pidió: si ya había uno igual, MediaStore
        // guarda "reporte (1).csv" sin avisar. Devolver el pedido mandaba al
        // usuario a buscar un archivo que existe pero es OTRO —el de la
        // exportación anterior, con otros datos—, que es peor que no decir nada.
        return "Descargas/VulpTiketing/${nombreReal(uri) ?: nombre}"
    }

    /** Cómo quedó llamándose de verdad el archivo que acaba de insertarse. */
    private fun nombreReal(uri: android.net.Uri): String? {
        return contentResolver.query(
            uri,
            arrayOf(MediaStore.Downloads.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }
    }

    /** Android 9 y anteriores: ahí sí se puede escribir directo. */
    private fun publicarPorArchivo(archivo: File, nombre: String): String {
        val carpeta = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "VulpTiketing",
        )
        carpeta.mkdirs()
        val destino = File(carpeta, nombre)
        archivo.copyTo(destino, overwrite = true)
        return "Descargas/VulpTiketing/$nombre"
    }
}
