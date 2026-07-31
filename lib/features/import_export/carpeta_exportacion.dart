import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dónde deja la app lo que exporta: backups, catálogos y reportes.
///
/// **Se elige una vez, no en cada exportación.** Antes cada exportar abría el
/// selector de archivos del sistema, que además en Android estaba roto:
/// `saveFile` exige los bytes del archivo por adelantado —lanza `ArgumentError`
/// sin ellos—, y un backup de la soda puede pesar más que la memoria
/// disponible. Con una carpeta fija, exportar es escribir un archivo y ya.
///
/// Por defecto va al directorio de la app en el almacenamiento externo
/// (`Android/data/<paquete>/files/VulpTiketing`): no pide ningún permiso, se ve
/// al conectar el teléfono por USB y se borra sola si alguien desinstala la
/// app. Se puede cambiar desde Configuración → Exportar.
class CarpetaExportacion {
  const CarpetaExportacion();

  static const _key = 'carpeta_exportacion';
  static const _subcarpeta = 'VulpTiketing';

  /// La carpeta lista para escribir, creada si no existía.
  Future<Directory> resolver() async {
    final prefs = await SharedPreferences.getInstance();
    final guardada = prefs.getString(_key);
    if (guardada != null) {
      final elegida = Directory(guardada);
      // Si la carpeta elegida desapareció —tarjeta SD quitada, carpeta
      // borrada— se vuelve a la de por defecto en vez de fallar al exportar.
      if (await elegida.exists()) return elegida;
      await prefs.remove(_key);
    }
    return _porDefecto();
  }

  Future<Directory> _porDefecto() async {
    // `getExternalStorageDirectory` es solo Android; en el resto vale el
    // directorio de documentos de la app.
    final base = Platform.isAndroid
        ? await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory()
        : await getApplicationDocumentsDirectory();
    final carpeta = Directory(p.join(base.path, _subcarpeta));
    if (!await carpeta.exists()) await carpeta.create(recursive: true);
    return carpeta;
  }

  /// Cambia la carpeta. Devuelve `false` si no se puede escribir en ella, que
  /// es lo que pasa cuando el selector devuelve algo que `dart:io` no sabe
  /// abrir (en Android, una carpeta compartida por SAF llega como `content://`).
  Future<bool> cambiar(String ruta) async {
    final carpeta = Directory(ruta);
    try {
      if (!await carpeta.exists()) await carpeta.create(recursive: true);
      // Se comprueba de verdad: que exista no implica que la app pueda
      // escribir, y descubrirlo recién al exportar un backup sería tarde.
      final prueba = File(p.join(carpeta.path, '.vulp-prueba'));
      await prueba.writeAsString('ok');
      await prueba.delete();
    } catch (_) {
      return false;
    }
    await (await SharedPreferences.getInstance()).setString(_key, carpeta.path);
    return true;
  }

  /// Vuelve a la carpeta por defecto.
  Future<void> restablecer() async {
    await (await SharedPreferences.getInstance()).remove(_key);
  }

  /// Un archivo dentro de la carpeta, con el nombre libre de choques: si ya
  /// existe uno igual se le agrega un número en vez de pisarlo. Perder el
  /// backup de ayer por exportar el de hoy sería inaceptable.
  Future<File> archivoPara(String nombre) async {
    final carpeta = await resolver();
    final base = p.basenameWithoutExtension(nombre);
    final extension = p.extension(nombre);

    var candidato = File(p.join(carpeta.path, nombre));
    var intento = 2;
    while (await candidato.exists()) {
      candidato = File(p.join(carpeta.path, '$base ($intento)$extension'));
      intento++;
    }
    return candidato;
  }
}

/// La carpeta actual, para mostrarla en Configuración.
final carpetaExportacionProvider = FutureProvider<Directory>(
  (ref) => const CarpetaExportacion().resolver(),
);
