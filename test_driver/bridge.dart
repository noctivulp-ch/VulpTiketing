// Bridge HTTP para el harness del MCP (scripts/mcp-driver/). Mantiene UNA
// conexion flutter_driver persistente contra la app real (lanzada con
// test_driver/app.dart) y la expone como endpoints REST simples — el
// servidor MCP en Node solo hace fetch() a este bridge, toda la logica de
// flutter_driver vive aca.
//
// Uso:
//   dart run test_driver/bridge.dart --vm-service=http://127.0.0.1:PUERTO/TOKEN=/
//
// El puerto+token del VM service lo imprime `flutter run` al arrancar la
// app (linea "A Dart VM Service on ... is available at: ...").
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

const _puertoBridge = 8765;

FlutterDriver? _driver;

/// El token que la persona del aparato generó en Configuración → Herramientas.
/// Sin él el bridge no arranca: no hay modo "sin autenticar".
String? _token;

void main(List<String> args) async {
  final vmService = _leerArg(args, '--vm-service');
  final token = _leerArg(args, '--token');
  if (vmService == null || token == null) {
    stderr.writeln('Uso: dart run test_driver/bridge.dart --vm-service=<url> --token=<token>');
    stderr.writeln();
    stderr.writeln('El token lo genera la persona que atiende el aparato, en');
    stderr.writeln('Configuracion -> Herramientas. Hay que pedirselo: no se puede');
    stderr.writeln('deducir de la contrasena ni de ningun otro dato de la app.');
    exit(1);
  }
  _token = token;

  stdout.writeln('Conectando a $vmService ...');
  _driver = await FlutterDriver.connect(dartVmServiceUrl: vmService);

  // Se comprueba ANTES de abrir el puerto, contra la app: así un token
  // equivocado falla acá con un mensaje claro, y no más tarde y disfrazado de
  // "el comando no hizo nada".
  final prueba = jsonDecode(
    await _driver!.requestData(jsonEncode({'cmd': 'ping', 'token': token})),
  );
  if (prueba['ok'] != true) {
    stderr.writeln('Token rechazado por la app: ${prueba['error']}');
    exit(2);
  }

  stdout.writeln('Token aceptado. Bridge escuchando en http://127.0.0.1:$_puertoBridge');

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_exigirToken)
      .addHandler(_router);
  await shelf_io.serve(handler, InternetAddress.loopbackIPv4, _puertoBridge);
}

/// Cada petición trae el token en `X-Vulp-Token`.
///
/// El bridge escucha solo en loopback, así que esto no protege de la red — de
/// eso se encarga el bind. Protege de OTRO proceso de esta misma computadora:
/// sin esto, cualquier cosa que corra acá podía manejar la caja con un `curl`.
Handler _exigirToken(Handler siguiente) {
  return (Request request) async {
    if (request.headers['x-vulp-token'] != _token) {
      return Response.forbidden(
        jsonEncode({'ok': false, 'error': 'Falta la cabecera X-Vulp-Token o no coincide'}),
        headers: {'content-type': 'application/json'},
      );
    }
    return siguiente(request);
  };
}

String? _leerArg(List<String> args, String nombre) {
  for (final a in args) {
    if (a.startsWith('$nombre=')) return a.substring(nombre.length + 1);
  }
  return null;
}

Future<Response> _router(Request request) async {
  final driver = _driver;
  if (driver == null) return _json({'ok': false, 'error': 'sin conexion a flutter_driver'});

  try {
    switch ('${request.method} ${request.url.path}') {
      case 'GET health':
        await driver.checkHealth();
        return _json({'ok': true});

      case 'POST tap':
        final body = await _body(request);
        // runUnsynchronized: por defecto flutter_driver espera a que no
        // haya "frames pendientes" antes de actuar (frame sync) - un campo
        // de texto con foco (cursor parpadeante) nunca llega a ese estado,
        // asi que CUALQUIER accion se cuelga para siempre en cuanto hay un
        // campo enfocado en pantalla (bug real encontrado probando esto:
        // el segundo tap de la sesion, sobre un campo ya autofocused, se
        // colgo indefinidamente sin este wrapper).
        await driver.runUnsynchronized(
          () => driver.tap(_finderDe(body), timeout: _timeout(body)),
        );
        return _json({'ok': true});

      case 'POST enter_text':
        final body = await _body(request);
        // enter_text escribe en el campo con foco actual — hay que tocarlo
        // (POST /tap) antes, es el mismo flujo que un usuario real.
        //
        // La emulacion de texto se enciende SOLO para este instante y se
        // apaga siempre despues, incluso si falla. Mientras esta encendida,
        // `TestTextInput` reemplaza la entrada de texto del sistema y el
        // teclado fisico deja de escribir en la app: dejarla encendida (el
        // default de `enableFlutterDriverExtension`) hacia imposible usar la
        // app a mano. Ver el comentario largo en test_driver/app.dart.
        await driver.runUnsynchronized(() async {
          await driver.setTextEntryEmulation(enabled: true);
          try {
            await driver.enterText(body['text'] as String);
          } finally {
            await driver.setTextEntryEmulation(enabled: false);
          }
        });
        return _json({'ok': true});

      case 'GET screenshot':
        // Captura renderizada por el MOTOR de la app, no por el compositor.
        // Es la unica forma robusta en este entorno: no depende del foco, ni
        // de en que monitor esta la ventana, ni de que este visible — con
        // `grim` la captura fallaba cuando niri dejaba la ventana desplazada
        // fuera del viewport por compartir workspace con otra.
        final png = await driver.runUnsynchronized(() => driver.screenshot());
        return Response.ok(
          png,
          headers: {'content-type': 'image/png'},
        );

      case 'GET get_text':
        final body = request.url.queryParameters;
        final texto = await driver.runUnsynchronized(
          () => driver.getText(_finderDe(body)),
        );
        return _json({'ok': true, 'resultado': texto});

      case 'POST wait_for':
        final body = await _body(request);
        await driver.runUnsynchronized(
          () => driver.waitFor(_finderDe(body), timeout: _timeout(body)),
        );
        return _json({'ok': true});

      case 'POST wait_for_absent':
        final body = await _body(request);
        await driver.runUnsynchronized(
          () => driver.waitForAbsent(_finderDe(body), timeout: _timeout(body)),
        );
        return _json({'ok': true});

      case 'POST direct':
        final body = {...await _body(request), 'token': _token};
        final respuesta = await driver.runUnsynchronized(
          () => driver.requestData(jsonEncode(body)),
        );
        return _json(jsonDecode(respuesta) as Map<String, dynamic>);

      default:
        return Response.notFound('not found');
    }
  } catch (e) {
    return _json({'ok': false, 'error': e.toString()});
  }
}

Future<Map<String, dynamic>> _body(Request request) async {
  final texto = await request.readAsString();
  if (texto.isEmpty) return {};
  return jsonDecode(texto) as Map<String, dynamic>;
}

/// Acepta `text`, `tooltip` o `key` (en ese orden de prioridad) — cubre la
/// gran mayoria de los widgets de la app sin tener que agregarles una Key
/// explicita (botones/campos ya tienen texto o tooltip visible).
SerializableFinder _finderDe(Map<String, dynamic> body) {
  if (body['text'] != null) return find.text(body['text'] as String);
  if (body['tooltip'] != null) return find.byTooltip(body['tooltip'] as String);
  if (body['key'] != null) return find.byValueKey(body['key'] as String);
  throw ArgumentError('se necesita "text", "tooltip" o "key"');
}

Duration? _timeout(Map<String, dynamic> body) {
  final ms = body['timeoutMs'];
  return ms == null ? null : Duration(milliseconds: ms as int);
}

Response _json(Map<String, dynamic> data) {
  return Response.ok(jsonEncode(data), headers: {'content-type': 'application/json'});
}
