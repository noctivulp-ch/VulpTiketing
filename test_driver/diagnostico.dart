// Detección temprana de problemas para el entorno de desarrollo.
//
// Vive en `test_driver/` y NO en `lib/` a propósito: desde acá no puede
// colarse en un build de release ni por accidente. No hay flags que recordar
// activar ni código muerto en producción — el entrypoint real (`lib/main.dart`)
// ni siquiera lo conoce.
//
// Por qué existe, con un caso concreto: el splash granulado entró el 28/07 con
// un `.chain()` invertido que lanzaba una excepción EN CADA TOQUE. La excepción
// caía durante el pintado, así que el frame se perdía y la pantalla parpadeaba
// en blanco. Estuvo dos días. Se encontró porque el usuario lo vio a ojo y
// pidió grabar la pantalla — no porque nada lo avisara, aunque la consola lo
// gritaba 16 veces cada 14 segundos.
//
// Lo que faltaba no era el dato: era que alguien lo mirara. Esto lo acumula y
// lo deja consultable desde el harness, así que después de cualquier
// interacción se puede preguntar "¿hubo errores?" y obtener una respuesta.

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

class _ErrorAcumulado {
  _ErrorAcumulado(this.mensaje, this.biblioteca, this.pila);

  final String mensaje;
  final String biblioteca;
  final String pila;
  int veces = 1;
  DateTime ultima = DateTime.now();
}

/// Recolector de problemas del entorno de desarrollo.
class DiagnosticoDev {
  DiagnosticoDev._();

  /// Errores agrupados por mensaje. Agrupados y no en bruto porque un fallo de
  /// pintado se repite en cada frame: sin agrupar, un solo defecto llena el
  /// reporte con cientos de líneas idénticas y esconde los demás.
  static final _errores = <String, _ErrorAcumulado>{};

  /// Duración de los frames que pasaron del presupuesto, en milisegundos.
  static final _framesLentos = <int>[];
  static int _framesTotales = 0;

  /// Presupuesto de un frame a 60 Hz.
  static const _presupuestoMs = 16;

  static bool _instalado = false;

  static void instalar() {
    if (_instalado) return;
    _instalado = true;

    // Se conserva el manejador anterior: la idea es AGREGAR un registro, no
    // silenciar la consola. Tragarse los errores para "limpiar" la salida sería
    // exactamente el problema que esto viene a resolver.
    final anterior = FlutterError.onError;
    FlutterError.onError = (detalles) {
      _registrar(
        detalles.exceptionAsString(),
        detalles.library ?? 'desconocida',
        detalles.stack?.toString() ?? '',
      );
      anterior?.call(detalles);
    };

    // Errores asíncronos que no pasan por FlutterError (un Future sin catch).
    final anteriorPlataforma = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, pila) {
      _registrar(error.toString(), 'asincrono', pila.toString());
      return anteriorPlataforma?.call(error, pila) ?? true;
    };

    SchedulerBinding.instance.addTimingsCallback((tiempos) {
      for (final t in tiempos) {
        _framesTotales++;
        final ms = t.totalSpan.inMilliseconds;
        if (ms > _presupuestoMs) _framesLentos.add(ms);
      }
    });
  }

  static void _registrar(String mensaje, String biblioteca, String pila) {
    // La primera línea alcanza para agrupar: el resto suele traer valores
    // variables (un radio, una coordenada) que romperían el agrupamiento.
    final clave = mensaje.split('\n').first.trim();
    final ya = _errores[clave];
    if (ya != null) {
      ya.veces++;
      ya.ultima = DateTime.now();
      return;
    }
    _errores[clave] = _ErrorAcumulado(clave, biblioteca, _pilaCorta(pila));
  }

  /// Solo los primeros marcos de la pila, y sin los del framework: lo que
  /// importa es en qué archivo NUESTRO empezó.
  static String _pilaCorta(String pila) {
    final lineas = pila.split('\n').where((l) => l.trim().isNotEmpty);
    final propias = lineas.where((l) => l.contains('vulp_tiketing')).take(3);
    return (propias.isNotEmpty ? propias : lineas.take(3)).join('\n');
  }

  static void limpiar() {
    _errores.clear();
    _framesLentos.clear();
    _framesTotales = 0;
  }

  /// Resumen consultable desde el harness.
  ///
  /// Se reportan MEDIANA y percentil 90, no solo cuántos pasaron del
  /// presupuesto. Medido en el aparato: en una build de depuración los 39 de 39
  /// frames superaban los 16 ms, así que ese contador no distinguía nada — sin
  /// AOT todo va varias veces más lento. La mediana sí se mueve cuando un
  /// cambio mejora o empeora, que es para lo que sirve: comparar antes/después
  /// DENTRO de la misma build, nunca como cifra absoluta.
  ///
  /// Los errores, en cambio, valen igual en cualquier build.
  static Map<String, Object?> resumen({int maximo = 10}) {
    final ordenados = List<int>.from(_framesLentos)..sort();
    int percentil(double p) => ordenados.isEmpty
        ? 0
        : ordenados[(p * (ordenados.length - 1)).round()];
    return {
      'errores': _errores.length,
      'ocurrencias': _errores.values.fold<int>(0, (s, e) => s + e.veces),
      'detalle': [
        for (final e in _errores.values.take(maximo))
          {
            'mensaje': e.mensaje,
            'biblioteca': e.biblioteca,
            'veces': e.veces,
            'origen': e.pila,
          },
      ],
      'framesTotales': _framesTotales,
      'framesLentos': _framesLentos.length,
      'medianaMs': percentil(0.5),
      'p90Ms': percentil(0.9),
      'peorFrameMs': ordenados.isEmpty ? 0 : ordenados.last,
      'nota': 'Los tiempos de frame solo comparan dentro de la misma build: en '
          'depuración TODOS pasan del presupuesto. Mirar la mediana entre un '
          'antes y un después, no el valor suelto.',
    };
  }
}
