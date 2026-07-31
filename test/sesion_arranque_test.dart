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
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

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
}
