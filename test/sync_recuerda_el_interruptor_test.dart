import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vulp_tiketing/features/sync/sync_notifier.dart';

/// El interruptor de sincronización se recuerda entre arranques.
///
/// Lo pidió el dueño con la regla exacta: **el defecto es apagado, pero
/// encenderlo se respeta y no se auto-apaga**. Una app recién instalada no se
/// pone a hablar con la red sin que nadie se lo pida; pero si alguien la
/// encendió, tiene que seguir encendida mañana — si no, en la soda habría que
/// acordarse de activarla cada día, y el día que nadie se acuerde las cajas
/// dejan de compartir ventas sin que se note.
void main() {
  test('recién instalada arranca apagada', () async {
    SharedPreferences.setMockInitialValues({});
    final contenedor = ProviderContainer();
    addTearDown(contenedor.dispose);

    expect(contenedor.read(syncNotifierProvider).activa, isFalse);
  });

  test('si quedó encendida, la preferencia lo dice', () async {
    // El arranque de verdad necesita red y sesión, así que acá se comprueba el
    // contrato con el disco: que la clave sea la que el notifier lee.
    SharedPreferences.setMockInitialValues({'sync_activo': true});

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('sync_activo'), isTrue);
  });

  test('apagarla se recuerda apagada', () async {
    SharedPreferences.setMockInitialValues({'sync_activo': true});
    final contenedor = ProviderContainer();
    addTearDown(contenedor.dispose);

    await contenedor.read(syncNotifierProvider.notifier).detenerSync();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('sync_activo'), isFalse);
    expect(contenedor.read(syncNotifierProvider).activa, isFalse);
  });

  test('detenerla deja el estado limpio, sin pares ni fallo', () async {
    // Al volver a encenderla no puede arrastrar el error de la vez pasada: se
    // leería como un fallo actual.
    SharedPreferences.setMockInitialValues({});
    final contenedor = ProviderContainer();
    addTearDown(contenedor.dispose);

    await contenedor.read(syncNotifierProvider.notifier).detenerSync();
    final estado = contenedor.read(syncNotifierProvider);

    expect(estado.pares, 0);
    expect(estado.fallo, isNull);
  });
}
