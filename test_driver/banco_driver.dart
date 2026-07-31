// Driver del banco de rendimiento: recoge lo que midió
// `integration_test/banco_rendimiento_test.dart` en el aparato y lo deja en
// `build/banco/`.
//
// De cada escenario de interfaz sale un resumen con los tiempos de build y de
// raster (promedio, p90, p99, peor) y cuántos frames se pasaron del
// presupuesto. De las consultas sale un milisegundos por operación.
import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() {
  return integrationDriver(
    responseDataCallback: (datos) async {
      if (datos == null) return;
      final salida = Directory('build/banco')..createSync(recursive: true);

      final consultas = datos['consultas'] as Map<String, dynamic>?;
      if (consultas != null) {
        File(
          '${salida.path}/consultas.json',
        ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(consultas));
      }

      final interfaz = datos['interfaz'] as Map<String, dynamic>?;
      if (interfaz != null) {
        File(
          '${salida.path}/interfaz.json',
        ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(interfaz));
      }
    },
  );
}
