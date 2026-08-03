import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vulp_tiketing/features/auth/sesion_notifier.dart';

/// El arranque abre con la pista de las preferencias y corrige después contra
/// el almacén seguro. Lo que importa probar es la corrección: si la pista
/// pudiera mentir sin consecuencia, sería un agujero, no una optimización.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Corto: lo que se prueba es qué hace la app cuando expira, no cuánto
    // aguanta. El valor real son 8 s y dejaría la suite esperando de verdad.
    SesionNotifier.limiteAlmacenSeguro = const Duration(milliseconds: 50);
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  /// Un contenedor cuyo almacén seguro nunca contesta.
  ProviderContainer contenedorColgado() {
    final c = ProviderContainer(
      overrides: [almacenSeguroProvider.overrideWithValue(const _AlmacenColgado())],
    );
    addTearDown(c.dispose);
    return c;
  }

  ProviderContainer contenedor() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('sin pista ni sesión guardada, arranca sin rol', () async {
    final c = contenedor();
    await c.read(sesionNotifierProvider.notifier).restaurar();
    expect(c.read(sesionNotifierProvider), isNull);
  });

  test('la pista abre la sesión sin esperar al almacén seguro', () async {
    SharedPreferences.setMockInitialValues({'rol_activo_pista': 'gerente'});
    FlutterSecureStorage.setMockInitialValues({'rol_activo': 'gerente'});

    final c = contenedor();
    await c.read(sesionNotifierProvider.notifier).restaurar();

    expect(c.read(sesionNotifierProvider), Rol.gerente);
  });

  test('una pista que miente se corrige contra el almacén seguro', () async {
    // El caso que justifica que la pista sea solo una pista: alguien escribe
    // "gerente" en las preferencias, pero el almacén seguro dice registradora.
    SharedPreferences.setMockInitialValues({'rol_activo_pista': 'gerente'});
    FlutterSecureStorage.setMockInitialValues({'rol_activo': 'registradora'});

    final c = contenedor();
    final notifier = c.read(sesionNotifierProvider.notifier);
    await notifier.restaurar();
    // La verificación va por detrás: hay que dejarla terminar.
    await Future<void>.delayed(Duration.zero);

    expect(c.read(sesionNotifierProvider), Rol.registradora);
  });

  test('una pista sin sesión real termina en la pantalla de Login', () async {
    SharedPreferences.setMockInitialValues({'rol_activo_pista': 'gerente'});
    FlutterSecureStorage.setMockInitialValues({});

    final c = contenedor();
    await c.read(sesionNotifierProvider.notifier).restaurar();
    await Future<void>.delayed(Duration.zero);

    expect(c.read(sesionNotifierProvider), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('rol_activo_pista'), isNull, reason: 'la pista falsa debe borrarse');
  });

  test('cerrar sesión borra la pista, no solo el almacén', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final c = contenedor();
    final notifier = c.read(sesionNotifierProvider.notifier);
    await notifier.iniciarSesion(Rol.gerente, '1359');
    expect((await SharedPreferences.getInstance()).getString('rol_activo_pista'), 'gerente');

    await notifier.cerrarSesion();

    expect(c.read(sesionNotifierProvider), isNull);
    expect(
      (await SharedPreferences.getInstance()).getString('rol_activo_pista'),
      isNull,
      reason: 'una pista huérfana volvería a abrir la sesión en el próximo arranque',
    );
  });

  group('cuando el almacén seguro no contesta', () {
    // El fallo que el usuario reportó como "el login no se mantiene": abrir el
    // Keystore cuesta 1104–1573 ms medidos, y compitiendo con el arranque
    // pasaba del límite. Expirar se leía como "no hay sesión", así que la app
    // mandaba al Login Y borraba la pista: la vez siguiente tampoco arrancaba
    // abierta.
    test('la sesión abierta con la pista se conserva', () async {
      SharedPreferences.setMockInitialValues({'rol_activo_pista': 'gerente'});

      final c = contenedorColgado();
      await c.read(sesionNotifierProvider.notifier).restaurar();
      // Más que el límite de la lectura: se quiere ver qué pasa DESPUÉS de que
      // expire, que es donde estaba el fallo.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(
        c.read(sesionNotifierProvider),
        Rol.gerente,
        reason: 'no poder comprobar no es lo mismo que no tener sesión',
      );
      expect(
        (await SharedPreferences.getInstance()).getString('rol_activo_pista'),
        'gerente',
        reason: 'borrar la pista dejaba el próximo arranque igual de roto',
      );
    });

    test('sin pista sigue pidiendo credenciales', () async {
      // La otra mitad de la regla: nunca dar acceso por no poder comprobar.
      SharedPreferences.setMockInitialValues({});
      final c = contenedorColgado();
      await c.read(sesionNotifierProvider.notifier).restaurar();

      expect(c.read(sesionNotifierProvider), isNull);
    });
  });
}

/// No falla ni responde: se queda esperando, que es lo que hace un Keystore que
/// tarda de más o un backend que no está.
class _AlmacenColgado extends FlutterSecureStorage {
  const _AlmacenColgado();

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => Completer<String?>().future;
}
