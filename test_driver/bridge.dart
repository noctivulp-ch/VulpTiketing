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

void main(List<String> args) async {
  final vmService = _leerArg(args, '--vm-service');
  if (vmService == null) {
    stderr.writeln('Uso: dart run test_driver/bridge.dart --vm-service=<url>');
    exit(1);
  }

  stdout.writeln('Conectando a $vmService ...');
  _driver = await FlutterDriver.connect(dartVmServiceUrl: vmService);
  stdout.writeln('Conectado. Bridge escuchando en http://127.0.0.1:$_puertoBridge');

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(_router);
  await shelf_io.serve(handler, InternetAddress.loopbackIPv4, _puertoBridge);
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
        final body = await _body(request);
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
