import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Qué es el archivo con el que se abrió la app.
enum ClaseDeArchivo {
  /// Un catálogo: productos y categorías. Se puede fusionar o reemplazar.
  catalogo,

  /// Un respaldo completo y cifrado. Restaurarlo pisa la base entera y necesita
  /// la contraseña con la que se exportó.
  respaldo,
}

class ArchivoEntrante {
  const ArchivoEntrante({required this.ruta, required this.nombre, required this.clase});

  final String ruta;

  /// El nombre con el que se ve en el explorador. Se muestra al preguntar: es lo
  /// único que le permite al usuario reconocer si es el archivo que quería.
  final String nombre;

  final ClaseDeArchivo clase;
}

/// El archivo con el que alguien abrió la app tocándolo en el explorador.
///
/// El lado nativo ya lo copió a un archivo propio —un `content://` no se puede
/// leer con `dart:io`, y el permiso de lectura muere con el intent— así que acá
/// solo llega una ruta normal.
///
/// **La extensión decide.** Es lo único que separa un catálogo de un respaldo
/// completo, y confundirlos sería importar productos donde se quería restaurar la
/// base, o pisar la base entera donde solo se quería la carta. Un archivo con
/// otra extensión se descarta: el filtro del manifest es por patrón de ruta y
/// puede colar algo que no es nuestro.
class ArchivoEntranteService {
  const ArchivoEntranteService();

  static const _canal = MethodChannel('vulp/archivo_entrante');

  static final _avisos = StreamController<void>.broadcast();
  static bool _escuchando = false;

  /// Avisa cuando llega un archivo con la app **ya abierta**.
  ///
  /// Hace falta porque el ciclo de vida no basta: tocar un archivo con la app en
  /// primer plano no produce ningún cambio de estado, así que esperar a
  /// `resumed` dejaba el archivo esperando sin que pasara nada — medido en el
  /// aparato. El aviso lo manda `onNewIntent` en cuanto tiene algo.
  static Stream<void> get avisos {
    if (!_escuchando) {
      _escuchando = true;
      _canal.setMethodCallHandler((llamada) async {
        if (llamada.method == 'llego') _avisos.add(null);
      });
    }
    return _avisos.stream;
  }

  /// Lo recoge y lo olvida: un archivo se abre una vez, no en cada arranque.
  ///
  /// Devuelve `null` si no había ninguno, si la extensión no es de las nuestras
  /// o si el archivo copiado ya no está.
  Future<ArchivoEntrante?> recoger() async {
    if (!Platform.isAndroid) return null;
    try {
      final datos = await _canal.invokeMapMethod<String, String>('recoger');
      if (datos == null) return null;

      final ruta = datos['ruta'];
      final nombre = datos['nombre'];
      if (ruta == null || nombre == null) return null;
      if (!File(ruta).existsSync()) return null;

      final clase = claseDe(nombre);
      if (clase == null) return null;

      return ArchivoEntrante(ruta: ruta, nombre: nombre, clase: clase);
    } on PlatformException {
      return null;
    }
  }

  /// La clase por la extensión del nombre, o `null` si no es de las nuestras.
  ///
  /// Estático y público para poder probarlo sin canal nativo: es la decisión que
  /// importa de todo esto.
  static ClaseDeArchivo? claseDe(String nombre) {
    final minusculas = nombre.toLowerCase();
    if (minusculas.endsWith('.tiketdata')) return ClaseDeArchivo.catalogo;
    if (minusculas.endsWith('.tiketback')) return ClaseDeArchivo.respaldo;
    return null;
  }
}
