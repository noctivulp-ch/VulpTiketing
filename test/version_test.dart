import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/core/version.dart';

/// La versión que muestra la app es la de verdad.
///
/// `lib/core/version.dart` duplica lo que dice `pubspec.yaml`, y una constante
/// duplicada se queda vieja sin que nadie lo note: la pantalla de Acerca de
/// diría 1.0.0 build 1 con el teléfono corriendo otra cosa, y entonces el dato
/// no solo es inútil — es peor que no tenerlo, porque se usa para decidir si dos
/// aparatos corren el mismo código.
///
/// Esta prueba es el precio de no traer una dependencia nativa solo para leer un
/// número de versión, y es un precio barato: si alguien sube `pubspec.yaml` y se
/// olvida de esto, falla acá.
void main() {
  late String pubspec;

  setUpAll(() {
    pubspec = File('pubspec.yaml').readAsStringSync();
  });

  /// `version: 1.0.0+1` → ('1.0.0', 1)
  (String, int) versionDePubspec(String texto) {
    final linea = texto.split('\n').firstWhere((l) => l.startsWith('version:'), orElse: () => '');
    expect(linea, isNotEmpty, reason: 'pubspec.yaml sin línea "version:"');

    final valor = linea.substring('version:'.length).trim();
    final partes = valor.split('+');
    expect(partes, hasLength(2), reason: 'se esperaba "x.y.z+build", hay "$valor"');
    return (partes.first, int.parse(partes.last));
  }

  test('la versión semántica coincide con pubspec.yaml', () {
    final (semantica, _) = versionDePubspec(pubspec);
    expect(versionApp, semantica);
  });

  test('el número de compilación coincide con pubspec.yaml', () {
    final (_, compilacion) = versionDePubspec(pubspec);
    expect(compilacionApp, compilacion);
  });

  test('el nombre visible no es el del paquete', () {
    // `pubspec.yaml` dice `vulp_tiketing` porque un nombre de paquete Dart no
    // admite mayúsculas; lo que se le muestra a la gente es VulpTiketing. El
    // dueño lo pidió explícitamente: "vulp_tiketing eso queda muy debug".
    expect(nombreApp, 'VulpTiketing');
    expect(nombreApp, isNot(contains('_')));
  });

  group('el enlace del autor', () {
    test('es una dirección https válida y parseable', () {
      final uri = Uri.parse(enlaceAutor);
      expect(uri.scheme, 'https');
      expect(uri.host, 'www.patreon.com');
    });

    test('apunta a la cuenta del autor', () {
      expect(Uri.parse(enlaceAutor).pathSegments, ['cw', 'NoctiVulp']);
    });

    test('conserva los parámetros del enlace original', () {
      // El enlace lo dio el dueño tal cual, con sus parámetros de seguimiento.
      // Recortarlos sería reescribir lo que pidió, y son los que le dicen a él de
      // dónde llegó la visita.
      final parametros = Uri.parse(enlaceAutor).queryParameters;
      expect(parametros['utm_source'], 'join_link');
      expect(parametros['utm_campaign'], 'creatorshare_creator');
      expect(parametros['utm_content'], 'copyLink');
      expect(parametros['utm_medium'], 'unknown');
    });

    test('el nombre del autor es el corto que usa como dev', () {
      expect(autorApp, 'NoctiVulp');
    });
  });
}
