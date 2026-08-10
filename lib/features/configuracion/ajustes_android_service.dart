import 'dart:io';

import 'package:flutter/services.dart';

/// Lo que Android deja saber de sí mismo sin abrir nada.
class EstadoDeAjustes {
  const EstadoDeAjustes({
    required this.sinOptimizacionDeBateria,
    required this.version,
    required this.fabricante,
  });

  const EstadoDeAjustes.desconocido()
    : sinOptimizacionDeBateria = false,
      version = 0,
      fabricante = '';

  /// Si el sistema ya dejó a la app fuera de la optimización de batería. Es el
  /// único de estos ajustes que Android permite consultar.
  final bool sinOptimizacionDeBateria;

  /// Nivel de API. Cambia qué pantallas existen: "Abrir por defecto" tiene la
  /// suya desde Android 12 y antes hay que ir a los detalles de la app.
  final int version;

  final String fabricante;
}

/// Qué ajuste del sistema se va a abrir.
enum AjusteAndroid {
  bateria(
    'Optimización de batería',
    'Sin esta exención el sistema mata la sincronización cuando se apaga la '
        'pantalla, y nada avisa de que dejó de sincronizar.',
  ),
  permisos(
    'Permisos de la app',
    'Cámara para la foto de un producto. Lo demás —guardar archivos, leer un '
        'respaldo— no pide permiso: va por el selector del sistema.',
  ),
  datosEnSegundoPlano(
    'Uso en segundo plano',
    'Deja a la app hablar con las otras cajas mientras está atrás. Con el '
        'ahorro de datos puesto, el sistema la corta.',
  ),
  abrirPorDefecto(
    'Abrir archivos de la app',
    'Para que un .tiketdata o un .tiketback se abran acá al tocarlos en el '
        'explorador.',
  );

  const AjusteAndroid(this.etiqueta, this.explicacion);

  final String etiqueta;
  final String explicacion;
}

/// Abre las pantallas de ajustes de Android que la app necesita.
///
/// No concede nada: una app no puede darse permisos a sí misma. Lo que hace es
/// dejar al usuario en la pantalla correcta, y eso es el 90 % del problema —la
/// exención de batería vive a cinco toques y con un nombre distinto en cada
/// marca ("Inicio automático", "Aplicaciones protegidas").
///
/// Cada llamada devuelve si se pudo abrir algo. Ninguna de estas pantallas
/// existe en todas las versiones ni en todas las marcas, y un atajo que no hace
/// nada al tocarlo se lee como que la app se colgó.
class AjustesAndroidService {
  const AjustesAndroidService();

  static const _canal = MethodChannel('vulp/ajustes_android');

  /// Solo en Android. En Linux y Windows no hay nada de esto que abrir, y la
  /// sección entera se esconde en vez de mostrar atajos muertos.
  bool get disponible => Platform.isAndroid;

  Future<EstadoDeAjustes> estado() async {
    if (!disponible) return const EstadoDeAjustes.desconocido();
    try {
      final datos = await _canal.invokeMapMethod<String, Object?>('estado');
      if (datos == null) return const EstadoDeAjustes.desconocido();
      return EstadoDeAjustes(
        sinOptimizacionDeBateria: datos['sinOptimizacionDeBateria'] as bool? ?? false,
        version: datos['version'] as int? ?? 0,
        fabricante: datos['fabricante'] as String? ?? '',
      );
    } on PlatformException {
      return const EstadoDeAjustes.desconocido();
    }
  }

  /// Devuelve `false` si el aparato no tiene esa pantalla.
  Future<bool> abrir(AjusteAndroid ajuste) async {
    if (!disponible) return false;
    try {
      return await _canal.invokeMethod<bool>(ajuste.name) ?? false;
    } on PlatformException {
      return false;
    }
  }
}
