import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El harness de control remoto **no puede colarse en la app que se instala**.
///
/// Es la defensa que más vale por lo que cuesta, y va antes que el token: el
/// token protege si alguien llega a la puerta, esto evita que la puerta exista.
/// Hoy se cumple —lo verifiqué sobre el APK instalado, buscando las cadenas de
/// los comandos del harness, y no aparece ninguna—, pero se cumple por
/// convención, y una convención sin comprobar es una que se rompe el día que
/// alguien agregue un import "solo para probar algo".
void main() {
  final raiz = Directory.current.path;

  test('flutter_driver es dependencia de desarrollo, no de producción', () {
    // Si subiera a `dependencies` viajaría en el APK aunque nadie la use, y con
    // ella la extensión que permite manejar la app entera desde fuera.
    final pubspec = File('$raiz/pubspec.yaml').readAsStringSync();
    final dev = pubspec.indexOf('dev_dependencies:');
    final posicion = pubspec.indexOf('flutter_driver:');

    expect(posicion, greaterThan(0), reason: 'flutter_driver debería seguir declarada');
    expect(
      posicion,
      greaterThan(dev),
      reason: 'flutter_driver está en `dependencies`: entraría en el APK de la soda',
    );
  });

  test('lib/ no importa nada del harness', () {
    // `lib/` es lo que se compila en la app. `test_driver/` puede importar de
    // `lib/` —lo hace—, pero nunca al revés: en cuanto un archivo de `lib/`
    // tocara `driver_extension`, la app instalada quedaría manejable desde
    // fuera sin que nadie lo notara.
    final prohibidos = ['flutter_driver', 'driver_extension', 'test_driver/'];
    final ofensores = <String>[];

    for (final archivo in Directory('$raiz/lib').listSync(recursive: true)) {
      if (archivo is! File || !archivo.path.endsWith('.dart')) continue;
      final fuente = archivo.readAsStringSync();
      for (final linea in fuente.split('\n')) {
        if (!linea.trimLeft().startsWith('import ') && !linea.trimLeft().startsWith('export ')) {
          continue;
        }
        for (final prohibido in prohibidos) {
          if (linea.contains(prohibido)) {
            ofensores.add('${archivo.path.replaceFirst('$raiz/', '')}: ${linea.trim()}');
          }
        }
      }
    }

    expect(ofensores, isEmpty, reason: 'lib/ importa el harness:\n${ofensores.join('\n')}');
  });

  test('el entrypoint de producción no habilita la extensión', () {
    // `lib/main.dart` es lo que arranca en el aparato. El harness vive en un
    // entrypoint aparte (`test_driver/app.dart`) justamente para esto.
    final main = File('$raiz/lib/main.dart').readAsStringSync();

    expect(main, isNot(contains('enableFlutterDriverExtension')));
  });

  test('el harness exige el token en cada comando directo', () {
    // Los comandos directos son los que tocan datos —sembrar, exportar,
    // borrar—. Si dejaran de comprobar el token, el panel de Configuración
    // pasaría a ser decoración.
    final app = File('$raiz/test_driver/app.dart').readAsStringSync();

    expect(app, contains('tokenMcpServiceProvider'));
    expect(app, contains('verificar('));
  });

  test('el token de desarrollo está detrás de kReleaseMode', () {
    // La garantía es de compilación, no de tiempo de ejecución:
    // `kReleaseMode` es una constante, así que en release la rama entera
    // —incluida la cadena del token— se elimina del binario.
    //
    // Se comprueba el código y no el APK porque compilar uno tarda dos minutos
    // y esta prueba corre en cada cambio. La comprobación sobre el binario de
    // verdad está en `scripts/verificar-release.sh`, que sí lo hace, y se corre
    // antes de dejar un aparato en la soda.
    final servicio = File(
      '$raiz/lib/features/configuracion/token_mcp_service.dart',
    ).readAsStringSync();

    expect(servicio, contains('kReleaseMode'));
    expect(
      servicio,
      contains('_devHabilitado && '),
      reason: 'el token de desarrollo tiene que estar detrás de la condición, no suelto',
    );
  });

  test('el bridge no arranca sin token', () {
    final bridge = File('$raiz/test_driver/bridge.dart').readAsStringSync();

    expect(bridge, contains('--token'));
    expect(bridge, contains('x-vulp-token'));
    // Y sigue escuchando solo en loopback: si esto pasara a `anyIPv4`, la caja
    // quedaría manejable desde cualquier punto de la red del local.
    expect(bridge, contains('InternetAddress.loopbackIPv4'));
    expect(bridge, isNot(contains('InternetAddress.anyIPv4')));
  });
}
