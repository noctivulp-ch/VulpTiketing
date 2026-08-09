import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/features/configuracion/token_mcp_service.dart';

/// La llave que deja manejar la app desde fuera.
///
/// Es **aleatoria**, no derivada de la contraseña. Derivarla era la idea
/// inicial y se descartó por dos motivos que la hunden: la contraseña son
/// cuatro dígitos —diez mil posibilidades, con el algoritmo a la vista en el
/// repo— y, al revés, un token filtrado dejaría recuperar la contraseña por
/// fuerza bruta. La contraseña protege igual, pero en el sitio correcto: hace
/// falta para VER el token, no para calcularlo.
void main() {
  TokenMcpService servicioCon(_AlmacenFalso almacen, {Random? aleatorio}) =>
      TokenMcpService(storage: almacen, aleatorio: aleatorio);

  test('sin generar nada no hay token, y no se acepta ninguno', () async {
    // El estado de fábrica es "cerrado". Mientras nadie pida la llave, no hay
    // llave que robar.
    final servicio = servicioCon(_AlmacenFalso());

    expect(await servicio.leer(), isNull);
    expect(await servicio.verificar('lo-que-sea'), isFalse);
    expect(await servicio.verificar(''), isFalse);
    expect(await servicio.verificar(null), isFalse);
  });

  test('el token generado se acepta, y solo él', () async {
    final servicio = servicioCon(_AlmacenFalso());

    final token = await servicio.generar();

    expect(await servicio.verificar(token), isTrue);
    expect(await servicio.verificar('$token '), isFalse);
    expect(await servicio.verificar(token.substring(1)), isFalse);
    expect(await servicio.verificar(token.toUpperCase()), isFalse);
  });

  test('dos tokens seguidos son distintos', () async {
    // Si se repitieran, rotar no serviría de nada.
    final servicio = servicioCon(_AlmacenFalso());

    final generados = {for (var i = 0; i < 20; i++) await servicio.generar()};

    expect(generados, hasLength(20));
  });

  test('generar otro invalida el anterior: es el botón de revocar acceso', () async {
    final servicio = servicioCon(_AlmacenFalso());
    final viejo = await servicio.generar();

    final nuevo = await servicio.generar();

    expect(await servicio.verificar(viejo), isFalse);
    expect(await servicio.verificar(nuevo), isTrue);
  });

  test('revocar deja el aparato cerrado otra vez', () async {
    final servicio = servicioCon(_AlmacenFalso());
    final token = await servicio.generar();

    await servicio.revocar();

    expect(await servicio.leer(), isNull);
    expect(await servicio.verificar(token), isFalse);
  });

  test('el token no se puede deducir de la contraseña', () async {
    // La prueba que da sentido a todo el diseño. Dos aparatos con la MISMA
    // contraseña tienen tokens distintos, porque el token no sale de ella: si
    // saliera, cualquiera que sepa los cuatro dígitos —o que los pruebe todos—
    // tendría la llave.
    final unAparato = servicioCon(_AlmacenFalso());
    final otroAparato = servicioCon(_AlmacenFalso());

    expect(await unAparato.generar(), isNot(await otroAparato.generar()));
  });

  test('es lo bastante largo como para no adivinarse', () async {
    final token = await servicioCon(_AlmacenFalso()).generar();

    // 32 bytes en base64 sin relleno. Lo copia una máquina, así que no hay
    // razón para acercarse a lo memorizable.
    expect(token.length, greaterThanOrEqualTo(40));
    expect(
      token,
      matches(RegExp(r'^[A-Za-z0-9_-]+$')),
      reason: 'seguro en URL y en línea de comandos',
    );
  });

  group('el token de desarrollo', () {
    // Existe para que el harness no obligue a generar y copiar un token a mano
    // en cada reinstalación: durante el desarrollo la app se reinstala decenas
    // de veces al día y cada una empieza sin token.
    //
    // Estas pruebas corren en modo debug, o sea con el token habilitado. Que en
    // RELEASE no exista lo comprueba `harness_fuera_de_produccion_test.dart`
    // buscando la cadena dentro del APK de verdad — acá no se puede, porque una
    // prueba no puede cambiarse su propio `kReleaseMode`.

    test('se acepta sin haber generado ninguno', () async {
      final servicio = servicioCon(_AlmacenFalso());

      expect(await servicio.verificar(TokenMcpService.tokenDeDesarrollo), isTrue);
      // Y no deja rastro: sigue sin haber token guardado, así que el panel
      // sigue diciendo "sin token" y revocar no tiene nada que revocar.
      expect(await servicio.leer(), isNull);
    });

    test('convive con uno generado: valen los dos', () async {
      // Si generar uno propio apagara el de desarrollo, cada vez que se probara
      // el flujo de token a mano habría que acordarse de revocarlo después.
      final servicio = servicioCon(_AlmacenFalso());
      final propio = await servicio.generar();

      expect(await servicio.verificar(propio), isTrue);
      expect(await servicio.verificar(TokenMcpService.tokenDeDesarrollo), isTrue);
    });

    test('revocar no lo apaga: no es un token guardado', () async {
      final servicio = servicioCon(_AlmacenFalso());
      await servicio.generar();

      await servicio.revocar();

      expect(await servicio.verificar(TokenMcpService.tokenDeDesarrollo), isTrue);
    });

    test('se nota que es de desarrollo con solo leerlo', () async {
      // Va a aparecer en logs, en líneas de comando y en capturas. Que se
      // explique solo evita que alguien lo tome por un token de verdad.
      expect(TokenMcpService.tokenDeDesarrollo, contains('dev'));
      expect(TokenMcpService.tokenDeDesarrollo, contains('produccion'));
    });

    test('la app sabe decir que este build lo acepta', () async {
      // Es lo que enciende el aviso rojo del panel. Sin esto, un build de
      // pruebas se ve igual que uno de la soda.
      expect(TokenMcpService.esBuildDeDesarrollo, isTrue, reason: 'las pruebas corren en debug');
    });
  });

  test('sobrevive a reabrir la app', () async {
    // Vive en el almacén, no en memoria: si se perdiera al cerrar, habría que
    // reconfigurar la herramienta externa en cada arranque.
    final almacen = _AlmacenFalso();
    final token = await servicioCon(almacen).generar();

    expect(await servicioCon(almacen).verificar(token), isTrue);
  });
}

/// Un llavero en memoria. El de verdad no se puede usar en pruebas: su canal
/// nativo no es interceptable.
class _AlmacenFalso implements FlutterSecureStorage {
  final datos = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async => datos[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async {
    if (value == null) {
      datos.remove(key);
    } else {
      datos[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async => datos.remove(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
