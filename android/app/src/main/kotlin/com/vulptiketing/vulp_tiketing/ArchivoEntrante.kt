package com.vulptiketing.vulp_tiketing

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import java.io.File

/**
 * El archivo con el que alguien abrió la app desde un explorador.
 *
 * Cuando se toca un `.tiketdata` o un `.tiketback` en Archivos, Android arranca
 * la app con `ACTION_VIEW` y un `content://…`. Dos cosas obligan a resolverlo en
 * código nativo:
 *
 * 1. **`dart:io` no puede leer un `content://`.** No es un archivo del sistema
 *    de archivos, es un flujo que sirve otra app a través del ContentResolver.
 *    Hay que copiarlo a un archivo propio para que Dart lo vea.
 * 2. **El permiso de lectura dura lo que dura el intent.** Si se guardara la URI
 *    para leerla después —al confirmar el diálogo de restaurar, por ejemplo— ya
 *    no se podría abrir. Se copia al llegar, y punto.
 *
 * El nombre real importa: el `content://` no lleva extensión, y la extensión es
 * lo único que distingue un catálogo (`.tiketdata`) de un respaldo completo
 * (`.tiketback`). Confundirlos sería importar productos donde se quería
 * restaurar la base entera, o al revés.
 */
object ArchivoEntrante {
    /**
     * Lo copiado y todavía sin recoger, o `null`.
     *
     * Se guarda hasta que Dart lo pide porque el intent llega antes de que exista
     * la interfaz: en un arranque en frío, `configureFlutterEngine` corre antes
     * de que nadie pueda preguntar.
     */
    private var pendiente: Map<String, String>? = null

    fun recibir(contexto: Context, intent: Intent?) {
        val uri = uriDe(intent) ?: return
        val nombre = nombreDe(contexto, uri) ?: "importado"
        // A la caché y con nombre único: dos archivos que se llamen igual
        // abiertos uno detrás de otro no pueden pisarse, y la caché es lo que el
        // sistema puede limpiar solo cuando le haga falta espacio.
        val destino = File.createTempFile("entrante-", "-$nombre", contexto.cacheDir)
        try {
            contexto.contentResolver.openInputStream(uri).use { entrada ->
                destino.outputStream().use { salida -> entrada!!.copyTo(salida) }
            }
            // Vacío es un fallo, no un archivo vacío. Pasa con un `file:///sdcard`
            // en Android 10 o superior: la app no puede leer el almacenamiento
            // compartido sin permiso y la copia sale de cero bytes sin lanzar
            // nada. Medido en el aparato — el archivo quedaba en la caché y la
            // app se ofrecía a importar la nada.
            if (destino.length() == 0L) throw IllegalStateException("copia vacía")
            pendiente = mapOf("ruta" to destino.absolutePath, "nombre" to nombre)
        } catch (e: Exception) {
            // Sin ruido: el usuario tocó un archivo, no pidió un diagnóstico. La
            // app abre normal y él vuelve a intentarlo o lo importa desde
            // Configuración, que es el camino de siempre. Pero el resto a medias
            // no se deja: un archivo de cero bytes en la caché es basura que solo
            // confunde al mirar por qué no pasó nada.
            destino.delete()
            pendiente = null
        }
    }

    fun hayPendiente(): Boolean = pendiente != null

    /** Lo entrega y lo olvida: un archivo se abre una vez, no en cada arranque. */
    fun recoger(): Map<String, String>? {
        val actual = pendiente
        pendiente = null
        return actual
    }

    private fun uriDe(intent: Intent?): Uri? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            // Compartir desde otra app ("Enviar a…") llega como SEND con la URI
            // en un extra, no en `data`. Es el otro camino por el que un respaldo
            // puede llegar: desde WhatsApp o el correo, sin pasar por Archivos.
            Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM)
            else -> null
        }
    }

    /**
     * El nombre que el proveedor declara, o el último tramo de la ruta.
     *
     * Se pregunta al ContentResolver porque el `content://` de Archivos no lleva
     * el nombre en la URI: viene en `DISPLAY_NAME`, y es de donde sale la
     * extensión con la que se decide qué hacer con el archivo.
     */
    private fun nombreDe(contexto: Context, uri: Uri): String? {
        contexto.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) return cursor.getString(0)
            }
        return uri.lastPathSegment?.substringAfterLast('/')
    }
}
