import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Deja un archivo exportado donde el dueño del teléfono pueda encontrarlo:
/// **Descargas/VulpTiketing**.
///
/// Por qué existe: la app escribe en su carpeta privada
/// (`Android/data/<paquete>/files/`), que no pide permisos pero tampoco la ve
/// nadie — hay que conectar el teléfono a una computadora. Un backup que solo
/// existe conectando el teléfono a una PC no es un backup.
///
/// Y no se puede escribir en Descargas desde Dart: desde Android 10 el
/// almacenamiento es "scoped" y `dart:io` recibe un `Permission denied` incluso
/// para una carpeta que se ve en cualquier explorador —comprobado en el
/// aparato—. La única vía sin pedirle permisos al usuario es MediaStore, que no
/// tiene API en Dart, así que va por un canal a `MainActivity`.
///
/// El archivo se escribe primero en la carpeta privada y se COPIA acá. Escribir
/// dos veces cuesta, pero el camino de escritura de cada formato queda igual
/// que estaba —y ese camino ya está probado— en vez de reescribirse contra un
/// `content://`.
class AlmacenPublico {
  const AlmacenPublico();

  static const _canal = MethodChannel('vulp/almacen_publico');

  /// Publica [archivo] y devuelve dónde quedó, para poder decírselo al usuario.
  ///
  /// Si no se puede publicar —no es Android, o MediaStore lo rechaza— devuelve
  /// la ruta original. Exportar no falla por no poder copiar: el archivo ya
  /// está escrito, y decir "no se pudo" cuando sí se guardó sería mentir.
  Future<String> publicar(File archivo) async {
    if (!Platform.isAndroid) return archivo.path;
    final nombre = p.basename(archivo.path);
    try {
      final donde = await _canal.invokeMethod<String>('publicar', {
        'origen': archivo.path,
        'nombre': nombre,
        'mime': mimeDe(nombre),
      });
      if (donde == null) return archivo.path;
      // El de la carpeta privada era solo el paso intermedio. Dejarlo hacía que
      // la próxima exportación se llamara "catalogo (2)" —`archivoPara` numera
      // para no pisar nada— cuando el archivo bueno, el de Descargas, no
      // existía dos veces. Ese numerito lo pone MediaStore si hace falta.
      try {
        await archivo.delete();
      } catch (_) {}
      return donde;
    } on PlatformException {
      return archivo.path;
    } on MissingPluginException {
      // La app instrumentada del arnés no registra la actividad nativa.
      return archivo.path;
    }
  }

  /// El tipo que MediaStore necesita para indexar el archivo. Sin uno correcto,
  /// tocar el PDF desde Descargas no ofrece con qué abrirlo.
  ///
  /// Los formatos propios van como `octet-stream` **a propósito**, aunque
  /// `.tiketdata` sea JSON por dentro: MediaStore RENOMBRA el archivo para que
  /// la extensión case con el tipo, y con `application/json` el catálogo salía
  /// como `catalogo.tiketdata.json` —comprobado en el aparato—. La extensión es
  /// parte del formato: es por lo que el selector de importar lo reconoce.
  static String mimeDe(String nombre) => switch (p.extension(nombre).toLowerCase()) {
    '.pdf' => 'application/pdf',
    '.csv' => 'text/csv',
    _ => 'application/octet-stream',
  };
}
